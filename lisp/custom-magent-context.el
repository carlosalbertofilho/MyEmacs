;;; custom-magent-context.el --- Magent contexto: compactação estilo opencode -*- lexical-binding: t; -*-

;;; Commentary:
;; Auto-compactação da sessão do Magent estilo opencode (Fase B): instrução
;; de compactação orientada a estado, medição de tokens via ledger (usage
;; por turno do gptel), gatilho por threshold + milestones de subagentes.

;;; Code:

(require 'cl-lib)

(declare-function magent-runtime-session-compact "magent-runtime-api")
(declare-function magent-runtime-session-current "magent-runtime-api")
(declare-function magent-lifecycle-events-add-sink "magent-lifecycle-events")
(declare-function magent-thread-turns "magent-ledger")
(declare-function magent-thread-find-turn "magent-ledger")
(declare-function magent-thread-turn-input "magent-ledger")
(declare-function magent-thread-turn-items "magent-ledger")
(declare-function magent-thread-item-role "magent-ledger")
(declare-function magent-thread-item-call-id "magent-ledger")
(declare-function magent-runtime-session-magent-session "magent-runtime-api")
(declare-function magent-session-thread "magent-ledger")
(declare-function +carlos/magent-resolve-model "custom-magent-tools")
(declare-function +carlos/local-ai-server-ping-p "custom-ai")
(declare-function gptel--model-name "gptel")
(declare-function project-root "project")
(defvar +carlos/magent-model-max-tier 'paid)

;; ── Auto-Compactação Automática (Fase B) ────────────────────────────
(defcustom +carlos/magent-context-compact-ratio 0.6
  "Limite (0.0 a 1.0) da janela do modelo para disparar auto-compactação.
Por padrão, 0.6 (60% da janela do modelo ativo)."
  :type 'float
  :group '+carlos/ai)

(defcustom +carlos/magent-milestone-subagents 3
  "Subagentes completados desde a última compactação para o gatilho de milestone."
  :type 'integer
  :group '+carlos/ai)

(defcustom +carlos/magent-milestone-ratio 0.4
  "Limiar inferior (0.0 a 1.0) da janela para o gatilho por milestone.
Só compacta por milestone quando os tokens estimados excedem este
percentual da janela do modelo."
  :type 'float
  :group '+carlos/ai)

(defcustom +carlos/magent-context-window-fallback 131072
  "Janela de contexto fallback caso o modelo gptel não declare :context-window.
128K (131072) — maioria dos modelos free/locais modernos tem ≥128K."
  :type 'integer
  :group '+carlos/ai)

(defcustom +carlos/magent-compaction-local-max-tokens 32000
  "Teto de tokens da sessão para usar o modelo local na compactação (B5.1).
Acima deste valor, a compactação usa o primeiro modelo free da nuvem —
o equivalente ao flash do Gemini CLI — pois modelos locais pequenos
resumem mal contexto grande."
  :type 'integer
  :group '+carlos/ai)

(defcustom +carlos/magent-compaction-cooldown-seconds 120
  "Intervalo mínimo (em segundos) entre duas compactações automáticas.
Previne thrashing quando tokens crescem rápido pós-compactação."
  :type 'integer
  :group '+carlos/ai)

(defvar +carlos/magent-preservation-instruction
  "Compactar a sessão preservando estruturadamente:
1. Arquivos modificados ou criados (caminhos completos) e a razão da mudança;
2. Nomes de funções de testes ERT associadas às alterações;
3. Decisões técnicas tomadas e suas justificativas;
4. TODOs/estado pendente (não duplicar o TODO.org nem roadmap.org — consulte-os);
5. Restrições e preferências do usuário persistentes;
6. Comandos e gates de compilação/teste válidos (`just ...`).
NÃO replicar conteúdo lido que não tenha sido alterado."
  "Base de preservação estruturada para a auto-compactação do Magent.")

(defconst +carlos/magent-compaction-rules
  "Regras essenciais do projeto (extraído de AGENTS.md):
- Use-package com :ensure para pacotes externos; :ensure nil para built-in.
- Naming: +carlos/function-name para custom, +carlos/--helper para internal.
- NÃO adicionar comments não-solicitados no código.
- Sempre rodar just test-all após mudanças na config.
- Guardas: (fboundp ...) antes de chamar funções de pacotes carregados via :defer.
- require com nil t para carregamento seguro em batch."
  "Regras essenciais do projeto para preservar pós-compactação.")

(defvar +carlos/magent-context-estimated-tokens 0
  "Tokens estimados consumidos desde a última compactação.")

(defvar +carlos/magent-subagent-completions-since-compact 0
  "Subagentes completados desde a última compactação.")

(defvar +carlos/magent-last-compaction-time nil
  "Timestamp (float-time) da última compactação automática.")

(defvar +carlos/magent-last-compaction-failed nil
  "Non-nil quando a última compactação não reduziu o contexto (B5.3).
Bloqueia novas auto-compactações até uma compactação manual ou um novo
lote de `+carlos/magent-failure-retry-turn-ends' turnos.")

(defvar +carlos/magent-failure-retry-turn-ends 5
  "Turnos completados até limpar `+carlos/magent-last-compaction-failed'.
Permite que a auto-compactação tente novamente após uma falha.")

(defvar +carlos/magent-turn-ends-since-failure 0
  "Turnos completados desde que `+carlos/magent-last-compaction-failed' foi setado.")

;; ── Métricas por turno ──────────────────────────────────────────────
(defvar +carlos/magent-turn-metrics nil
  "Alist de (TURN-ID . PLIST) com métricas por turno.
Cada PLIST contém :input, :output, :elapsed, :tool-names, :timestamp.
Últimas 50 entries; entradas mais antigas são descartadas.")

(defvar +carlos/magent-turn-metrics-max-entries 50
  "Número máximo de entries em `+carlos/magent-turn-metrics'.")

;; ── Acesso à sessão (helpers compartilhados) ─────────────────────────
(defun +carlos/magent-session-thread ()
  "Retorna o `magent-thread' da sessão Magent atual, ou nil.
Resolve a cadeia runtime-session → magent-session → thread com guardas."
  (when-let* ((session (and (fboundp 'magent-runtime-session-current)
                            (magent-runtime-session-current)))
              (msession (and (fboundp 'magent-runtime-session-magent-session)
                             (magent-runtime-session-magent-session session)))
              (thread (and (fboundp 'magent-session-thread)
                           (magent-session-thread msession))))
    thread))

(defun +carlos/magent-session-total-tokens (&optional thread)
  "Soma os tokens reais (usage) de todos os turnos de THREAD (B5.3).
THREAD default: thread da sessão atual via `+carlos/magent-session-thread'.
Itera `magent-thread-turns' somando `+carlos/magent-turn-usage-tokens';
sem thread/turnos, retorna 0."
  (let ((th (or thread (+carlos/magent-session-thread))))
    (if (and th (fboundp 'magent-thread-turns))
        (cl-reduce (lambda (acc turn)
                     (+ acc (+carlos/magent-turn-usage-tokens turn)))
                   (magent-thread-turns th)
                   :initial-value 0)
      0)))

;; ── B2. Medição de tokens (usage por turno no ledger) ───────────────
(defun +carlos/magent-turn-usage-tokens (turn)
  "Soma os tokens do TURN: usage real do ledger ou estimativa por input.
O usage do turno (cl-defstruct accessor `magent-thread-turn-usage') é o
plist do gptel com chaves :input e :output; quando ausente, estima
pelo texto de `magent-thread-turn-input' (chars/4).  Retorna 0 se nada."
  (let ((usage (and (fboundp 'magent-thread-turn-usage)
                    (magent-thread-turn-usage turn))))
    (cond
     ((and (listp usage) (plist-member usage :input))
      (+ (or (plist-get usage :input) 0) (or (plist-get usage :output) 0)))
     ((fboundp 'magent-thread-turn-input)
      (let ((input (magent-thread-turn-input turn)))
        (if (stringp input) (/ (length input) 4) 0)))
     (t 0))))

(defun +carlos/magent-turn-tokens (&optional event-data)
  "Retorna os tokens estimados do turno do EVENT-DATA de lifecycle.
Resolve o turno pelo :turn-id do evento na cadeia runtime-session →
magent-session → thread e delega a `+carlos/magent-turn-usage-tokens'.
Sem turno resolvido, retorna 0."
  (or (when-let* ((turn-id (plist-get event-data :turn-id))
                  (session (and (fboundp 'magent-runtime-session-current)
                                (magent-runtime-session-current)))
                  (msession (and (fboundp 'magent-runtime-session-magent-session)
                                 (magent-runtime-session-magent-session session)))
                  (thread (and (fboundp 'magent-session-thread)
                               (magent-session-thread msession)))
                  (turn (and (fboundp 'magent-thread-find-turn)
                             (magent-thread-find-turn thread turn-id))))
      (+carlos/magent-turn-usage-tokens turn))
      0))

;; ── B3. Decisão de compactação (threshold + milestone) ──────────────
(defun +carlos/magent-compaction-decision (total-tokens cwindow subagents)
  "Decide se compactar com TOTAL-TOKENS em uma janela de CWINDOW.
SUBAGENTS é o número de subagentes completados desde a última
compactação.  Retorna `immediate' quando TOTAL-TOKENS excede
`+carlos/magent-context-compact-ratio' da janela; `milestone' quando
SUBAGENTS atinge `+carlos/magent-milestone-subagents' e TOTAL-TOKENS
excede `+carlos/magent-milestone-ratio'; senão nil."
  (cond
   ((> total-tokens (* +carlos/magent-context-compact-ratio cwindow))
    'immediate)
   ((and (>= subagents +carlos/magent-milestone-subagents)
         (> total-tokens (* +carlos/magent-milestone-ratio cwindow)))
    'milestone)
   (t nil)))

;; ── B5.4. Fronteira segura de corte (não dividir tool calls) ─────────
(defun +carlos/magent-turn-closed-p (turn)
  "Non-nil se TURN não tem tool call pendente (B5.4).
Um turno é fechado quando todo item de chamada (role sem ser `tool' e com
call-id) tem seu resultado correspondente (role `tool' com o mesmo
call-id) dentro do PRÓPRIO turno.  Sem items ou sem chamadas → fechado."
  (let ((items (and (fboundp 'magent-thread-turn-items)
                    (magent-thread-turn-items turn))))
    (if (null items)
        t
      (let ((calls (cl-remove-if-not
                    (lambda (it)
                      (and (magent-thread-item-call-id it)
                           (not (eq (magent-thread-item-role it) 'tool))))
                    items))
            (results (cl-remove-if-not
                      (lambda (it)
                        (and (magent-thread-item-call-id it)
                             (eq (magent-thread-item-role it) 'tool)))
                      items)))
        (cl-every (lambda (c)
                    (cl-some (lambda (r)
                               (string= (magent-thread-item-call-id r)
                                        (magent-thread-item-call-id c)))
                             results))
                  calls)))))

(defun +carlos/magent-safe-compaction-boundary
    (thread &optional keep-count keep-ratio)
  "Retorna o índice 0-based do primeiro turno de THREAD a preservar verbatim.
Acumula turns da cauda até KEEP-COUNT (default 3) turns OU KEEP-RATIO
default 0.3 — fração dos caracteres de input do thread —, o que vier
primeiro — e avança a fronteira enquanto o turno imediatamente anterior
não estiver fechado (`+carlos/magent-turn-closed-p'), garantindo que a
região resumida (antes da fronteira) nunca termina com um tool call sem
resultado.  Thread sem turns → 0 (nada a resumir)."
  (let* ((turns (and (fboundp 'magent-thread-turns)
                     (magent-thread-turns thread)))
         (keep-count (or keep-count 3))
         (keep-ratio (or keep-ratio 0.3)))
    (if (null turns)
        0
      (let* ((total-chars (cl-reduce
                           (lambda (acc turn)
                             (+ acc (length (or (magent-thread-turn-input turn) ""))))
                           turns :initial-value 0))
             (n (length turns))
             (b n) (count 0) (chars 0))
        (while (and (> b 0)
                    (or (< count keep-count)
                        (< chars (* keep-ratio total-chars))))
          (setq b (1- b))
          (cl-incf count)
          (cl-incf chars (length (or (magent-thread-turn-input (nth b turns)) ""))))
        (while (and (> b 0)
                    (< b n)
                    (not (+carlos/magent-turn-closed-p (nth (1- b) turns))))
          (cl-incf b))
        b))))

;; ── B1. Instrução de compactação orientada a estado ─────────────────
(defun +carlos/magent-session-preview ()
  "Retorna o preview (resumo) da sessão Magent atual, ou nil."
  (when-let* ((thread (+carlos/magent-session-thread))
              (preview (and (fboundp 'magent-thread-preview)
                            (magent-thread-preview thread))))
    (and (stringp preview) (string-trim preview))))

;; ── B5.1. Modelo barato (compactação/commit) via selecionador ───────
(defun +carlos/magent-resolve-cheap-model
    (&optional token-count backends local-models)
  "Resolve o modelo barato para compactação/commit (B5.1/B5.2).
TOKEN-COUNT é a estimativa de tokens da sessão (default
`+carlos/magent-session-total-tokens'); BACKENDS (alist NAME . MODELS) e
LOCAL-MODELS (lista de strings) são overrides para testes, repassados a
`+carlos/magent-resolve-model'.  Usa o selecionador inteligente da
Fase A: modelo LOCAL se o servidor local está online E TOKEN-COUNT ≤
`+carlos/magent-compaction-local-max-tokens'; caso contrário o primeiro
modelo FREE da nuvem (teto \\='free — nunca pago).  Retorna o plist de
`:backend', `:model', `:tier' e `:reason' de `+carlos/magent-resolve-model',
ou nil sem gptel/backend disponível."
  (let* ((local-online (+carlos/local-ai-server-ping-p))
         (tokens (or token-count (+carlos/magent-session-total-tokens)))
         (local (and local-online
                     (<= tokens +carlos/magent-compaction-local-max-tokens)
                     (+carlos/magent-resolve-model 'simple t backends local-models))))
    (or local
        (let ((+carlos/magent-model-max-tier 'free))
          (+carlos/magent-resolve-model 'simple nil backends local-models)))))

(defun +carlos/magent-build-compaction-instruction ()
  "Constrói a instrução de compactação orientada a estado (Fase B).
Inclui: estado do projeto (raiz + branch/rev git), objetivo corrente,
base de preservação estática e regras de descarte."
  (let* ((root (or (when-let* ((proj (and (fboundp 'project-current)
                                          (project-current))))
                     (project-root proj))
                   default-directory))
         (branch (ignore-errors
                   (string-trim
                    (shell-command-to-string
                     "git rev-parse --abbrev-ref HEAD"))))
         (rev (ignore-errors
                (string-trim
                 (shell-command-to-string
                  "git rev-parse --short HEAD"))))
         (preview (+carlos/magent-session-preview))
         (boundary (when-let* ((thread (+carlos/magent-session-thread)))
                     (+carlos/magent-safe-compaction-boundary thread))))
    (concat
     "Compactar a sessão preservando o estado do projeto:\n"
     "- Estado atual: "
     (or (and root (file-name-nondirectory
                    (directory-file-name root)))
         "n/a")
     (if (and branch rev) (format " (branch %s @ %s)" branch rev) "")
     "\n"
     "- Objetivo/tarefa corrente (preview da sessão): "
     (or preview "indisponível")
     "\n"
     (when boundary
       (format
        "- Fronteira de compactação: resuma apenas os turns 1..%d; preserve do turno %d em diante verbatim. NÃO divida tool calls e seus resultados.\n"
        boundary (1+ boundary)))
     "- Decisões técnicas tomadas e justificativas; arquivos modificados ou "
     "criados (caminhos absolutos) com a razão de cada mudança;\n"
     "- Nomes de funções de testes ERT associadas às alterações;\n"
     "- Comandos e gates de compilação/teste válidos (`just ...`);\n"
     "- Restrições e preferências persistentes do usuário;\n"
      "Regras de descarte: não replique transcripts de leitura reproduzíveis "
      "(output de grep/ls/cat); preserve os últimos 3 turns crus e resuma apenas "
      "o prefixo mais antigo; não duplique TODO.org nem roadmap.org (consulte-os).\n"
      "\n" +carlos/magent-compaction-rules
      "\n\nBase de preservação:\n" +carlos/magent-preservation-instruction)))

;; ── B4. Compactação manual + sink de lifecycle ──────────────────────
(defun +carlos/magent-compaction-result-handler (status before &optional after)
  "Guarda anti-crescimento (B5.3): valida o resultado da compactação.
STATUS é o status reportado pelo `:on-complete'; BEFORE, os tokens da
sessão medidos antes; AFTER (default: medição real pós-compactação via
`+carlos/magent-session-total-tokens') são os tokens depois.  Sucesso:
status `completed' E after < BEFORE*1.05 ou BEFORE zerado (sem medição,
assume sucesso).  Em sucesso zera os contadores e limpa a flag de falha;
em falha seta `+carlos/magent-last-compaction-failed' e registra
before→after."
  (let ((after-tokens (or after (+carlos/magent-session-total-tokens))))
    (if (and (eq status 'completed)
             (or (zerop before) (< after-tokens (* before 1.05))))
        (progn
          (setq +carlos/magent-context-estimated-tokens 0
                +carlos/magent-subagent-completions-since-compact 0
                +carlos/magent-last-compaction-failed nil
                +carlos/magent-turn-ends-since-failure 0
                +carlos/magent-last-compaction-time (float-time))
          (message "[Magent Compact] OK: %d → %d tokens." before after-tokens))
      (setq +carlos/magent-last-compaction-failed t)
      (message (concat
                "[Magent Compact] AVISO: compactação não reduziu o contexto "
                "(%d → %d tokens). Próxima auto-compactação pulada.")
               before after-tokens))))

(defun +carlos/magent-compact (&optional instruction)
  "Compacta a sessão atual do Magent com INSTRUCTION.
Default: instrução dinâmica de `+carlos/magent-build-compaction-instruction'.
Mede os tokens da sessão antes de disparar e valida o resultado em
`:on-complete' via `+carlos/magent-compaction-result-handler' (B5.3)."
  (interactive)
  (let ((instr (or instruction (+carlos/magent-build-compaction-instruction))))
    (if (fboundp 'magent-runtime-session-compact)
        (let ((session (and (fboundp 'magent-runtime-session-current)
                            (magent-runtime-session-current))))
          (if session
              (let ((before (+carlos/magent-session-total-tokens)))
                (magent-runtime-session-compact
                 session :instruction instr
                 :on-complete
                 (lambda (status _result)
                   (+carlos/magent-compaction-result-handler status before)))
                (message (concat
                          "[Magent Compact] Compactação de sessão iniciada "
                          "(%d tokens).")
                         before))
            (message "[Magent Compact] Nenhuma sessão Magent ativa.")))
      (message "[Magent Compact] magent-runtime-session-compact indisponível."))))

(global-set-key (kbd "C-c A p") #'+carlos/magent-compact)
(global-set-key (kbd "C-c A M") #'+carlos/magent-show-metrics)

(defun +carlos/magent-get-context-window ()
  "Retorna o tamanho da janela de contexto do modelo gptel ativo."
  (or (and (boundp 'gptel-model)
           gptel-model
           (get (intern (gptel--model-name gptel-model)) :context-window))
      +carlos/magent-context-window-fallback))

(defun +carlos/magent-compaction-cooldown-active-p ()
  "Non-nil se a cooldown entre compactações está ativa.
Compara `float-time' atual com `+carlos/magent-last-compaction-time'
mais `+carlos/magent-compaction-cooldown-seconds'."
  (when (and +carlos/magent-last-compaction-time
             (> +carlos/magent-compaction-cooldown-seconds 0))
    (let ((elapsed (- (float-time) +carlos/magent-last-compaction-time)))
      (< elapsed +carlos/magent-compaction-cooldown-seconds))))

(defun +carlos/magent-auto-compact-check-and-run (event-data)
  "Sink de lifecycle da auto-compactação (Fase B).
Dispacha por :type do EVENT-DATA: `subagent-stop' incrementa o contador
de milestones; `turn-end' com `completed' soma os tokens do turno em
`+carlos/magent-context-estimated-tokens' e decide compactar via
`+carlos/magent-compaction-decision'.  Bloqueia a compactação automática
enquanto `+carlos/magent-last-compaction-failed' estiver setado, reabrindo
após `+carlos/magent-failure-retry-turn-ends' turnos (B5.3)."
  (pcase (plist-get event-data :type)
    ('subagent-stop
     (setq +carlos/magent-subagent-completions-since-compact
           (1+ +carlos/magent-subagent-completions-since-compact)))
    ('turn-end
     (when (eq (plist-get event-data :status) 'completed)
       (when +carlos/magent-last-compaction-failed
         (setq +carlos/magent-turn-ends-since-failure
               (1+ +carlos/magent-turn-ends-since-failure))
         (when (>= +carlos/magent-turn-ends-since-failure
                   +carlos/magent-failure-retry-turn-ends)
           (setq +carlos/magent-last-compaction-failed nil
                 +carlos/magent-turn-ends-since-failure 0)))
        (setq +carlos/magent-context-estimated-tokens
              (+ +carlos/magent-context-estimated-tokens
                 (+carlos/magent-turn-tokens event-data)))
        (+carlos/magent-metrics-accumulate event-data)
        (let ((decision (+carlos/magent-compaction-decision
                        +carlos/magent-context-estimated-tokens
                        (+carlos/magent-get-context-window)
                        +carlos/magent-subagent-completions-since-compact)))
           (when (and decision
                      (not +carlos/magent-last-compaction-failed)
                      (not (+carlos/magent-compaction-cooldown-active-p)))
             (message (concat
                       "[Magent Auto-Compact] Gatilho %s (%d tokens estimados). "
                       "Compactando em segundo plano...")
                      decision +carlos/magent-context-estimated-tokens)
             (+carlos/magent-compact))
           (when (and decision (+carlos/magent-compaction-cooldown-active-p))
             (message "[Magent Auto-Compact] Cooldown ativo, pulando compactação.")))))))

;; ── Métricas: acumulação e exibição ─────────────────────────────────
(defun +carlos/magent-metrics-accumulate (event-data)
  "Acumula métricas do turno EVENT-DATA em `+carlos/magent-turn-metrics'.
Extrai turn-id, tokens (input+output), elapsed e tool-names dos items
do turno.  Limita o alist a `+carlos/magent-turn-metrics-max-entries'."
  (when-let* ((turn-id (plist-get event-data :turn-id))
              (session (and (fboundp 'magent-runtime-session-current)
                            (magent-runtime-session-current)))
              (msession (and (fboundp 'magent-runtime-session-magent-session)
                             (magent-runtime-session-magent-session session)))
              (thread (and (fboundp 'magent-session-thread)
                           (magent-session-thread msession)))
              (turn (and (fboundp 'magent-thread-find-turn)
                         (magent-thread-find-turn thread turn-id))))
    (let* ((usage (and (fboundp 'magent-thread-turn-usage)
                       (magent-thread-turn-usage turn)))
           (input (or (and (listp usage) (plist-get usage :input)) 0))
           (output (or (and (listp usage) (plist-get usage :output)) 0))
           (items (and (fboundp 'magent-thread-turn-items)
                       (magent-thread-turn-items turn)))
           (tool-names (when items
                         (mapcar (lambda (it)
                                   (and (fboundp 'magent-thread-item-name)
                                        (magent-thread-item-name it)))
                                 (cl-remove-if-not
                                  (lambda (it)
                                    (and (fboundp 'magent-thread-item-call-id)
                                         (magent-thread-item-call-id it)
                                         (not (eq (and (fboundp 'magent-thread-item-role)
                                                       (magent-thread-item-role it))
                                                  'tool))))
                                  items))))
           (elapsed (and (fboundp 'magent-thread-turn-elapsed)
                         (magent-thread-turn-elapsed turn))))
      (let ((entry (cons turn-id
                         (list :input input
                               :output output
                               :elapsed elapsed
                               :tool-names (delq nil tool-names)
                               :timestamp (float-time)))))
        (setq +carlos/magent-turn-metrics
              (cons entry
                    (cl-remove-if (lambda (e) (equal (car e) turn-id))
                                  +carlos/magent-turn-metrics)))
        (when (> (length +carlos/magent-turn-metrics)
                 +carlos/magent-turn-metrics-max-entries)
          (setcdr (nthcdr (1- +carlos/magent-turn-metrics-max-entries)
                          +carlos/magent-turn-metrics)
                  nil))))))

(defun +carlos/magent-top-tokens-turns (&optional n)
  "Retorna os N turnos com mais tokens (input+output).
N default 5.  Retorna lista de (TURN-ID . TOTAL) ordenada decrescente."
  (let* ((n (or n 5))
         (sorted (cl-sort (copy-sequence +carlos/magent-turn-metrics)
                          #'>
                          :key (lambda (e)
                                 (+ (or (plist-get (cdr e) :input) 0)
                                    (or (plist-get (cdr e) :output) 0))))))
    (mapcar (lambda (e) (cons (car e)
                              (+ (or (plist-get (cdr e) :input) 0)
                                 (or (plist-get (cdr e) :output) 0))))
            (cl-subseq sorted 0 (min n (length sorted))))))

(defun +carlos/magent-show-metrics ()
  "Exibe métricas por turno no minibuffer.
Mostra turn-id, tokens (input/output), elapsed e tools para cada turno."
  (interactive)
  (if (null +carlos/magent-turn-metrics)
      (message "[Magent Metrics] Nenhuma métrica registrada ainda.")
    (let ((lines (list "[Magent Metrics] Turnos registrados:")))
      (dolist (entry (cl-sort (copy-sequence +carlos/magent-turn-metrics)
                              #'> :key (lambda (e)
                                         (+ (or (plist-get (cdr e) :input) 0)
                                            (or (plist-get (cdr e) :output) 0)))))
        (let* ((id (car entry))
               (plist (cdr entry))
               (input (or (plist-get plist :input) 0))
               (output (or (plist-get plist :output) 0))
               (tools (plist-get plist :tool-names))
               (elapsed (plist-get plist :elapsed)))
          (push (format "  %s: %d/%d tokens%s%s"
                        id input output
                        (if elapsed (format " (%.1fs)" elapsed) "")
                        (if tools
                            (format " [%s]" (mapconcat #'symbol-name tools ", "))
                          ""))
                lines)))
      (message "%s" (mapconcat #'identity (nreverse lines) "\n")))))

(with-eval-after-load 'magent-lifecycle-events
  (when (fboundp 'magent-lifecycle-events-add-sink)
    (magent-lifecycle-events-add-sink #'+carlos/magent-auto-compact-check-and-run)))

(provide 'custom-magent-context)
;;; custom-magent-context.el ends here
