;;; custom-magent-context.el --- Magent contexto: compactação estilo opencode -*- lexical-binding: t; -*-

;;; Commentary:
;; Auto-compactação da sessão do Magent estilo opencode (Fase B): instrução
;; de compactação orientada a estado, medição de tokens via ledger (usage
;; por turno do gptel), gatilho por threshold + milestones de subagentes.

;;; Code:

(declare-function magent-runtime-session-compact "magent-runtime-api")
(declare-function magent-runtime-session-current "magent-runtime-api")
(declare-function magent-lifecycle-events-add-sink "magent-lifecycle-events")

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

(defcustom +carlos/magent-context-window-fallback 16384
  "Janela de contexto fallback caso o modelo gptel não declare :context-window."
  :type 'integer
  :group '+carlos/ai)

(defvar +carlos/magent-preservation-instruction
  "Compactar a sessão preservando estruturadamente:
1. Arquivos modificados ou criados (caminhos completos) e a razão da mudança;
2. Nomes de funções de testes ERT associadas às alterações;
3. Decisões técnicas tomadas e suas justificativas;
4. TODOs/estado pendente (não duplicar o TODO.md nem roadmap.org — consulte-os);
5. Restrições e preferências do usuário persistentes;
6. Comandos e gates de compilação/teste válidos (`just ...`).
NÃO replicar conteúdo lido que não tenha sido alterado."
  "Base de preservação estruturada para a auto-compactação do Magent.")

(defvar +carlos/magent-context-estimated-tokens 0
  "Tokens estimados consumidos desde a última compactação.")

(defvar +carlos/magent-subagent-completions-since-compact 0
  "Subagentes completados desde a última compactação.")

(defvar +carlos/magent-last-compaction-time nil
  "Timestamp (float-time) da última compactação automática.")

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

;; ── B1. Instrução de compactação orientada a estado ─────────────────
(defun +carlos/magent-session-preview ()
  "Retorna o preview (resumo) da sessão Magent atual, ou nil."
  (when-let* ((session (and (fboundp 'magent-runtime-session-current)
                            (magent-runtime-session-current)))
              (msession (and (fboundp 'magent-runtime-session-magent-session)
                             (magent-runtime-session-magent-session session)))
              (thread (and (fboundp 'magent-session-thread)
                           (magent-session-thread msession)))
              (preview (and (fboundp 'magent-thread-preview)
                            (magent-thread-preview thread))))
    (and (stringp preview) (string-trim preview))))

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
         (preview (+carlos/magent-session-preview)))
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
     "- Decisões técnicas tomadas e justificativas; arquivos modificados ou "
     "criados (caminhos absolutos) com a razão de cada mudança;\n"
     "- Nomes de funções de testes ERT associadas às alterações;\n"
     "- Comandos e gates de compilação/teste válidos (`just ...`);\n"
     "- Restrições e preferências persistentes do usuário;\n"
     "Regras de descarte: não replique transcripts de leitura reproduzíveis "
     "(output de grep/ls/cat); preserve os últimos 3 turns crus e resuma apenas "
     "o prefixo mais antigo; não duplique TODO.md nem roadmap.org (consulte-os).\n"
     "\nBase de preservação:\n" +carlos/magent-preservation-instruction)))

;; ── B4. Compactação manual + sink de lifecycle ──────────────────────
(defun +carlos/magent-compact (&optional instruction)
  "Compacta a sessão atual do Magent com INSTRUCTION.
Default: instrução dinâmica de `+carlos/magent-build-compaction-instruction'."
  (interactive)
  (let ((instr (or instruction (+carlos/magent-build-compaction-instruction))))
    (if (fboundp 'magent-runtime-session-compact)
        (let ((session (and (fboundp 'magent-runtime-session-current)
                            (magent-runtime-session-current))))
          (if session
              (progn
                (magent-runtime-session-compact session :instruction instr)
                (setq +carlos/magent-context-estimated-tokens 0
                      +carlos/magent-subagent-completions-since-compact 0
                      +carlos/magent-last-compaction-time (float-time))
                (message "[Magent Compact] Compactação de sessão iniciada."))
            (message "[Magent Compact] Nenhuma sessão Magent ativa.")))
      (message "[Magent Compact] magent-runtime-session-compact indisponível."))))

(global-set-key (kbd "C-c A p") #'+carlos/magent-compact)

(defun +carlos/magent-get-context-window ()
  "Retorna o tamanho da janela de contexto do modelo gptel ativo."
  (or (and (boundp 'gptel-model)
           gptel-model
           (get (intern (gptel--model-name gptel-model)) :context-window))
      +carlos/magent-context-window-fallback))

(defun +carlos/magent-auto-compact-check-and-run (event-data)
  "Sink de lifecycle da auto-compactação (Fase B).
Dispacha por :type do EVENT-DATA: `subagent-stop' incrementa o contador
de milestones; `turn-end' com `completed' soma os tokens do turno em
`+carlos/magent-context-estimated-tokens' e decide compactar via
`+carlos/magent-compaction-decision'."
  (pcase (plist-get event-data :type)
    ('subagent-stop
     (setq +carlos/magent-subagent-completions-since-compact
           (1+ +carlos/magent-subagent-completions-since-compact)))
    ('turn-end
     (when (eq (plist-get event-data :status) 'completed)
       (setq +carlos/magent-context-estimated-tokens
             (+ +carlos/magent-context-estimated-tokens
                (+carlos/magent-turn-tokens event-data)))
       (let ((decision (+carlos/magent-compaction-decision
                        +carlos/magent-context-estimated-tokens
                        (+carlos/magent-get-context-window)
                        +carlos/magent-subagent-completions-since-compact)))
         (when decision
           (message "[Magent Auto-Compact] Gatilho %s (%d tokens estimados). Compactando em segundo plano..."
                    decision +carlos/magent-context-estimated-tokens)
           (+carlos/magent-compact)))))))

(with-eval-after-load 'magent-lifecycle-events
  (when (fboundp 'magent-lifecycle-events-add-sink)
    (magent-lifecycle-events-add-sink #'+carlos/magent-auto-compact-check-and-run)))

(provide 'custom-magent-context)
;;; custom-magent-context.el ends here
