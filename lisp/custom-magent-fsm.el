;;; custom-magent-fsm.el --- Magent FSM: orquestração, host routing e watchdog -*- lexical-binding: t; -*-

;;; Commentary:
;; Maquina de estados do Magent (orquestracao, subagentes, watchdog de
;; latencia), deteccao de perfil por host e roteamento de backend da sessao.
;; Tambem acumula o canal `reasoning' do gptel e recupera tool calls
;; emitidas dentro do pensamento (DSML/Claude-XML).

;;; Code:

(require 'cl-lib)
(require 'custom-magent-prompts)
(declare-function magent-lifecycle-events-add-sink "magent-lifecycle-events")
(declare-function magent-lifecycle-events-context-subagent-id "magent-lifecycle-events")
(declare-function magent-tools--parent-session "magent-tools")
(declare-function magent-session-agent-jobs "magent-session")
(declare-function magent-agent-job-status "magent-agent")
(declare-function magent-agent-job-id "magent-agent")
(declare-function magent-agent-job-runtime "magent-agent")
(declare-function +carlos/magent-buffer-reset-session "custom-magent-buffer")
(declare-function +carlos/magent-resolve-model "custom-magent-tools")
(declare-function agent-shell--send-command "agent-shell")
(defvar +carlos/magent-model-tier-order)

(defvar magent-fsm-state-changed-hook nil
  "Hook executado após a FSM transicionar para um novo estado.
As funções recebem dois argumentos: PREV-STATE e NEW-STATE.")

(defvar magent-fsm-reset-hook nil
  "Hook executado quando a FSM é resetada.")
;; ── ETAPA 1: Estado da FSM & Detecção de Perfil por Host ────────────────────
;; Variáveis de controle do loop de eventos assíncrono do Magent.
;; São resetadas a cada sessão e nunca persistem entre boots.

(defvar +carlos/magent-fsm-state 'idle
  "Estado atual da FSM do Magent.
Valores possíveis: idle planning thinking tool-executing verifying
summarizing subagent-running subagent-waiting.")

(defvar +carlos/magent-fsm-session nil
  "Identificador da sessão Magent ativa na FSM.")

(defvar +carlos/magent-fsm-subagent-jobs nil
  "Lista de objetos `magent-agent-job' de subagentes ativos na FSM.
Populada a partir da sessão pai via `+carlos/magent-fsm-refresh-subagent-jobs'
e consultada por `+carlos/magent-fsm-pending-subagent-p'.")

(defvar +carlos/magent-fsm-retry-count 0
  "Contador de retries do turno atual.  Resetado a 0 em cada turn-start.")

(defvar +carlos/magent-fsm-reasoning-buffer ""
  "Acumulador de texto do canal `reasoning' do gptel.
Usado pelo sanitizador para detectar tool calls emitidas dentro do pensamento.")

;; ── ETAPA 1d: Loop de Auto-Correção (Fase C — buffer-driver-loop) ─────────
;; Contador de iterações e detecção de progresso para o ciclo
;; read → write → flycheck → fix → re-validate.
;; Critério de parada: zero erros OU 2 tentativas sem progresso.

(defvar +carlos/magent-fsm-healing-attempts 0
  "Contador de tentativas sem progresso no ciclo de auto-correção.
Incrementado quando error-count não diminui.  Resetado a 0 quando
há progresso (error-count diminui) ou ao fim do ciclo.")

(defvar +carlos/magent-fsm-healing-last-error-count nil
  "Número de erros da iteração anterior do loop de auto-correção.
nil na primeira iteração (nenhumhistórico de comparação).")

;; ── ETAPA 1e: Re-anexação Automática de Subagentes (Fase E) ────────────────
;; Coleta resultados de subagentes que completaram sem wait_agent e injeta
;; no próximo turno do orquestrador.

(defvar +carlos/magent-fsm-pending-results nil
  "Alist de (JOB-ID . PLIST) com resultados de subagentes concluídos.
PLIST contém :agent-name (string), :result (string) ou :error (string),
:either (symbol completed/failed).  Preenchido pelo observer ou pela
varredura periódica; limpo após injeção no turno do orquestrador.")

(defvar +carlos/magent-fsm-observer-tokens nil
  "Lista de tokens de observer registrados em jobs de subagentes.
Usado para limpar observers via `magent-agent-job-remove-observer'.")

(defun +carlos/magent-fsm-collect-completed-jobs ()
  "Coleta resultados de jobs de subagentes com status terminal.
Itera os jobs pendentes da sessão pai; para cada job completed/failed,
extrai o resultado e armazena em `+carlos/magent-fsm-pending-results'.
Remove jobs concluídos da lista de pending da FSM."
  (when (and (fboundp 'magent-tools--parent-session)
             (fboundp 'magent-session-agent-jobs)
             (fboundp 'magent-agent-job-status)
             (fboundp 'magent-agent-job-result)
             (fboundp 'magent-agent-job-agent-name)
             (fboundp 'magent-agent-job-id))
    (let ((session (magent-tools--parent-session)))
      (when session
        (dolist (job (magent-session-agent-jobs session))
          (let ((status (magent-agent-job-status job))
                (job-id (magent-agent-job-id job)))
            (when (memq status '(completed failed))
              ;; Armazenar resultado apenas se ainda não coletado
              (unless (alist-get job-id +carlos/magent-fsm-pending-results
                                 nil nil #'string=)
                (let ((result (magent-agent-job-result job))
                      (error-msg (when (fboundp 'magent-agent-job-error)
                                   (magent-agent-job-error job))))
                  (push (cons job-id
                              (list :agent-name (magent-agent-job-agent-name job)
                                    :status status
                                    :result (or result "")
                                    :error (or error-msg "")))
                        +carlos/magent-fsm-pending-results))))))))))

(defun +carlos/magent-fsm-register-observer (job)
  "Registra um observer no JOB para coleta automática de resultado.
O observer é chamado com 1 arg (o job) quando o status muda para
terminal.  Extrai o status via `magent-agent-job-status' para
compatibilidade com o upstream (=magent-agent-job.el:121=).
Retorna o token do observer para remoção posterior."
  (when (and (fboundp 'magent-agent-job-add-observer)
             (fboundp 'magent-agent-job-id))
    (let ((job-id (magent-agent-job-id job)))
      (magent-agent-job-add-observer
       job
       (lambda (observed-job)
         (let ((new-status (magent-agent-job-status observed-job)))
           (when (memq new-status '(completed failed))
             (when (and (fboundp 'magent-agent-job-result)
                        (fboundp 'magent-agent-job-agent-name))
               (let ((result (magent-agent-job-result observed-job))
                     (error-msg (when (fboundp 'magent-agent-job-error)
                                  (magent-agent-job-error observed-job))))
                 (unless (alist-get job-id +carlos/magent-fsm-pending-results
                                    nil nil #'string=)
                   (push (cons job-id
                               (list :agent-name (magent-agent-job-agent-name observed-job)
                                     :status new-status
                                     :result (or result "")
                                     :error (or error-msg "")))
                         +carlos/magent-fsm-pending-results))
                 ;; Auto-resume: quando todos os subagentes concluíram,
                 ;; reabre o turno do orquestrador automaticamente.
                 (+carlos/magent-fsm-maybe-auto-resume))))))))))

(defun +carlos/magent-fsm-register-observers-for-pending ()
  "Registra observers para todos os jobs de subagentes ativos.
Chamado quando a FSM entra em `subagent-waiting'."
  (let ((jobs (+carlos/magent-fsm-subagent-session-jobs)))
    (dolist (job jobs)
      (let ((token (+carlos/magent-fsm-register-observer job)))
        (when token
          (push token +carlos/magent-fsm-observer-tokens))))))

(defun +carlos/magent-fsm-cleanup-observers ()
  "Remove todos os observers registrados e limpa a lista de tokens."
  (when (fboundp 'magent-agent-job-remove-observer)
    (dolist (token +carlos/magent-fsm-observer-tokens)
      (magent-agent-job-remove-observer token)))
  (setq +carlos/magent-fsm-observer-tokens nil))

;; ── ETAPA 2f: Auto-Resume Pós-Subagente ──────────────────────────────────────
;; Quando um observer detecta que o subagente concluiu e não há mais jobs
;; pendentes, reabre programaticamente o turno do orquestrador via
;; `agent-shell--send-command' com um prompt de retomada.

(defvar +carlos/magent-fsm-auto-resume-in-progress nil
  "Flag para prevenir re-entrância no auto-resume.
Setado durante a execução do auto-resume e resetado ao fim.")

(defun +carlos/magent-fsm-active-subagent-names ()
  "Retorna uma lista de nomes dos subagentes ativos (queued/running)."
  (let ((jobs (+carlos/magent-fsm-subagent-session-jobs)))
    (when (and jobs (fboundp 'magent-agent-job-agent-name))
      (cl-remove-duplicates
       (cl-map 'list #'magent-agent-job-agent-name jobs)
       :test #'equal))))

(defun +carlos/magent-fsm-maybe-auto-resume ()
  "Reabre o turno do orquestrador se todos os subagentes concluíram.
Chamado pelo observer quando um job atinge estado terminal.
Condições: FSM em `subagent-waiting', nenhum job ativo restante,
e nenhum auto-resume já em progresso (flag de re-entrância)."
  (when (and (eq +carlos/magent-fsm-state 'subagent-waiting)
             (not +carlos/magent-fsm-auto-resume-in-progress)
             (not (+carlos/magent-fsm-pending-subagent-p))
             (fboundp 'agent-shell--send-command))
    (setq +carlos/magent-fsm-auto-resume-in-progress t)
    (condition-case err
        (progn
          ;; Formatar resultados pendentes como contexto
          (+carlos/magent-fsm-inject-pending-results)
          (let* ((names (+carlos/magent-fsm-active-subagent-names))
                 (prompt (+carlos/magent-prompts-format-subagent-resume names)))
            (message "[Magent FSM] Auto-resume: reabrindo turno do orquestrador")
            ;; Usar a versão base (sem advice) para evitar loop
            (funcall #'agent-shell--send-command :prompt prompt)))
      (error
       (message "[Magent FSM] Auto-resume falhou: %s" (error-message-string err))))
    (setq +carlos/magent-fsm-auto-resume-in-progress nil)))

;; ── ETAPA 2e: Deferred Result Injection (injeção pós-turno) ────────────────
;; Quando a FSM detecta resultados pendentes no turn-start-sink, formata
;; como mensagem de contexto para injetar no próximo turno do orquestrador.

(defvar +carlos/magent-fsm-resume-with-context nil
  "Non-nil quando há resultados de subagentes pendentes para injetar.
Setado por `+carlos/magent-fsm-inject-pending-results'; resetado após uso.")

(defvar +carlos/magent-fsm-pending-context-messages nil
  "Lista de mensagens formatadas de subagentes para injetar no próximo turno.
Preenchido por `+carlos/magent-fsm-inject-pending-results'; consumido por
`+carlos/magent-fsm-consume-pending-context'.")

(defun +carlos/magent-fsm-inject-pending-results ()
  "Formata resultados pendentes de subagentes como mensagens de contexto.
Retorna a lista de mensagens formatadas para injetar no prompt do
orquestrador.  Cada mensagem tem o formato:
  [Subagent <agent-name> (<status>)] <result-or-error>
Armazena mensagens em `+carlos/magent-fsm-pending-context-messages' e
seta `+carlos/magent-fsm-resume-with-context'."
  (when +carlos/magent-fsm-pending-results
    (let ((messages nil))
      (dolist (entry +carlos/magent-fsm-pending-results)
        (let* ((info (cdr entry))
               (agent-name (plist-get info :agent-name))
               (status (plist-get info :status))
               (result (plist-get info :result))
               (error-msg (plist-get info :error))
               (text (+carlos/magent-prompts-format-subagent-result agent-name status result error-msg)))
          (push text messages)))
      (setq +carlos/magent-fsm-pending-results nil
            +carlos/magent-fsm-pending-context-messages (nreverse messages)
            +carlos/magent-fsm-resume-with-context t)
      +carlos/magent-fsm-pending-context-messages)))

(defun +carlos/magent-fsm-consume-pending-context ()
  "Retorna e limpa as mensagens de contexto pendentes.
Chamado pelo handler de UI ou advice para injetar contexto no prompt.
Retorna nil quando não há contexto pendente."
  (when +carlos/magent-fsm-pending-context-messages
    (let ((messages +carlos/magent-fsm-pending-context-messages))
      (setq +carlos/magent-fsm-pending-context-messages nil
            +carlos/magent-fsm-resume-with-context nil)
      messages)))

(defun +carlos/magent-fsm-inject-context-into-prompt (orig &rest args)
  "Advice que injeta contexto de subagentes pendentes no prompt.
Modifica o :prompt em ARGS para incluir resultados de subagentes
coletados antes de delegar para ORIG."
  (let* ((prompt (plist-get args :prompt))
         (context-messages (+carlos/magent-fsm-consume-pending-context))
         (new-args (copy-sequence args)))
    (when (and prompt context-messages)
      (let ((injected (concat (mapconcat #'identity context-messages "\n")
                              "\n\n"
                              prompt)))
        (plist-put new-args :prompt injected)
        (message "[Magent FSM] Injected %d subagent result(s) into prompt"
                 (length context-messages))))
    (apply orig new-args)))

(unless (advice-member-p #'+carlos/magent-fsm-inject-context-into-prompt
                         'agent-shell--send-command)
  (advice-add 'agent-shell--send-command :around
              #'+carlos/magent-fsm-inject-context-into-prompt))

(defun +carlos/magent-fsm-healing-step (error-count)
  "Registra uma iteração do loop de auto-correção.
ERROR-COUNT é o número de erros restantes após a tentativa de fix.
Compara com `+carlos/magent-fsm-healing-last-error-count' para detectar
progresso.  Retorna \\='stop quando zero erros OU 2 tentativas sem
progresso, ou \\='continue quando deve prosseguir."
  (let ((prev +carlos/magent-fsm-healing-last-error-count))
    (setq +carlos/magent-fsm-healing-last-error-count error-count)
    (cond
     ((zerop error-count)
      (setq +carlos/magent-fsm-healing-attempts 0)
      'stop)
     ((and prev (>= +carlos/magent-fsm-healing-attempts 2)
           (>= error-count prev))
      (setq +carlos/magent-fsm-healing-attempts 0)
      'stop)
     ((or (null prev) (< error-count prev))
      (setq +carlos/magent-fsm-healing-attempts 0)
      'continue)
     (t
      (cl-incf +carlos/magent-fsm-healing-attempts)
      'continue))))

;; ── ETAPA 2: Fallback Inteligente com Retry ───────────────────────────────
;; Quando um subagente falha por timeout ou modelo indisponível, retry
;; automático com modelo de tier acima. Máx 1 retry por subagente.

(defvar +carlos/magent-fsm-retry-info nil
  "Alist de (JOB-ID . PLIST) com info de retry de subagentes.
PLIST contém :retried (boolean), :original-model, :failure-reason.")

(defcustom +carlos/magent-fsm-max-retries-per-subagent 1
  "Número máximo de retries por subagente quando falha."
  :type 'integer
  :group '+carlos/ai)

(defun +carlos/magent-fsm-reset ()
  "Reseta o estado da FSM para o início de um novo turno.
Também libera o contrato de sessão de buffers do driver (Fase B/D4) quando o
módulo custom-magent-buffer já está carregado — coordenado com o cancelamento
pela FSM."
  (setq +carlos/magent-fsm-state 'idle
        +carlos/magent-fsm-session nil
        +carlos/magent-fsm-retry-count 0
        +carlos/magent-fsm-reasoning-buffer ""
        +carlos/magent-fsm-subagent-jobs nil
        +carlos/magent-fsm-retry-info nil
        +carlos/magent-fsm-healing-attempts 0
        +carlos/magent-fsm-healing-last-error-count nil
        +carlos/magent-fsm-pending-results nil
        +carlos/magent-fsm-resume-with-context nil
        +carlos/magent-fsm-pending-context-messages nil
        +carlos/magent-fsm-auto-resume-in-progress nil)
  (+carlos/magent-fsm-cleanup-observers)
  (when (fboundp '+carlos/magent-buffer-reset-session)
    (+carlos/magent-buffer-reset-session))
  (run-hooks 'magent-fsm-reset-hook))

(defvar +carlos/magent-fsm-default-gc-cons-threshold gc-cons-threshold
  "Valor padrão de `gc-cons-threshold' restaurado após transições da FSM.")

(defun +carlos/magent-fsm-transition (new-state)
  "Transiciona a FSM para NEW-STATE, emite diagnóstico e gerencia GC dinâmico.
Nos estados computacionalmente intensos (`thinking' e `tool-executing'), eleva
`gc-cons-threshold' para 100MB (evitando engasgos de alocação de UI).
Ao transicionar de volta para `idle', `subagent-waiting' ou `planning',
restaura `gc-cons-threshold' ao valor padrão e executa `(garbage-collect)'."
  (let ((prev +carlos/magent-fsm-state))
    (setq +carlos/magent-fsm-state new-state)
    (unless (eq prev new-state)
      (message "[Magent FSM] %s → %s" prev new-state)
      ;; GC Dinâmico
      (cond
       ((memq new-state '(thinking tool-executing))
        (setq gc-cons-threshold (* 100 1024 1024)))
       ((memq new-state '(idle subagent-waiting planning))
        (setq gc-cons-threshold (or +carlos/magent-fsm-default-gc-cons-threshold (* 16 1024 1024)))
        (garbage-collect)))
      
      (run-hook-with-args 'magent-fsm-state-changed-hook prev new-state))))

;; ── ETAPA 1b: Detecção de Perfil por Host ───────────────────────────────────

(defcustom +carlos/magent-host-profiles
  '(("agnes"      :orchestrator-backend "MLX Local"
                  :orchestrator-model   "mlx-community/gemma-4-e2b-it-4bit"
                  :dev-backend          "MLX Local"
                  :dev-model            "mlx-community/Qwen3.5-Coder-7B-Instruct-4bit"
                  :reasoning-backend    "MLX Local"
                  :reasoning-model      "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit"
                  :watchdog-timeout     8)
    ("aa102-006l" :orchestrator-backend "Gemini"
                  :orchestrator-model   "gemini-2.5-flash"
                  :dev-backend          "OpenCode Zen"
                  :dev-model            "big-pickle"
                  :reasoning-backend    "Ollama Local"
                  :reasoning-model      "deepseek-r1:1.5b"
                  :watchdog-timeout     15))
  "Perfis de backend/modelo por hostname para a FSM do Magent.
Cada entrada é (HOSTNAME-FRAGMENT &rest PLIST-OF-KEYS)."
  :type '(repeat (list string plist))
  :group '+carlos/ai)

(defcustom +carlos/magent-fallback-backend "Gemini"
  "Backend de fallback da nuvem usado quando o watchdog dispara."
  :type 'string
  :group '+carlos/ai)

(defcustom +carlos/magent-fallback-model "gemini-2.5-flash"
  "Modelo de fallback da nuvem usado quando o watchdog dispara."
  :type 'string
  :group '+carlos/ai)

(defun +carlos/magent-host-profile ()
  "Retorna o plist de perfil do host atual baseado em `(system-name)'.
Itera sobre `+carlos/magent-host-profiles' e retorna o primeiro que faz
substring match com o hostname.  Se nenhum casar, retorna o perfil de agnes
como padrão (GPU disponível)."
  (let ((host (system-name)))
    (catch 'found
      (dolist (entry +carlos/magent-host-profiles)
        (when (string-match-p (car entry) host)
          (throw 'found (cdr entry))))
      ;; Default: perfil de agnes (GPU Local)
      (cdr (car +carlos/magent-host-profiles)))))

(defun +carlos/magent-profile-get (key)
  "Retorna o valor KEY do perfil de host atual.
Ex: (+carlos/magent-profile-get :watchdog-timeout) → 8"
  (plist-get (+carlos/magent-host-profile) key))

;; ── ETAPA 1c: Roteamento Dinâmico de Backend na Sessão ─────────────────────
;; Ao iniciar o Magent, configura o gptel-backend e gptel-model de acordo com
;; o perfil do host. Usa o backend de orquestração (Gemini Flash na aa102-006l,
;; Gemma local MLX no agnes).

(defun +carlos/magent-apply-host-routing ()
  "Aplica o perfil de backend do host ao gptel para a sessão Magent.
Quando o backend do perfil não é encontrado, registra um warning visível
em vez de manter silenciosamente o gptel-backend residual."
  (let* ((profile (+carlos/magent-host-profile))
         (orch-backend (plist-get profile :orchestrator-backend))
         (orch-model   (plist-get profile :orchestrator-model))
         (backend-obj  (and orch-backend (gptel-get-backend orch-backend))))
    (if backend-obj
        (progn
          (setq gptel-backend backend-obj
                gptel-model   (intern orch-model))
          (message "[Magent FSM] Host=%s → backend=%s modelo=%s"
                   (system-name) orch-backend orch-model))
      (warn "[Magent FSM] Host=%s: backend '%s' não encontrado em gptel-backends — mantendo backend residual"
            (system-name) orch-backend))))

;; ── ETAPA 2: Acumulador de Reasoning & Parser DSML de Tool Calls ────────────
;; Captura o fluxo de reasoning do gptel e detecta tool calls emitidas dentro
;; do pensamento (silenciosamente descartadas pelo magent nativo).

(defun +carlos/magent-fsm-accumulate-reasoning (response)
  "Acumula texto de RESPONSE no buffer de reasoning da FSM.
Deve ser chamado a cada chunk de reasoning do streaming."
  (when (and (consp response)
             (eq (car response) 'reasoning)
             (stringp (cdr response)))
    (setq +carlos/magent-fsm-reasoning-buffer
          (concat +carlos/magent-fsm-reasoning-buffer (cdr response)))))

(defun +carlos/magent-fsm-extract-tool-call-from-reasoning ()
  "Analisa o `+carlos/magent-fsm-reasoning-buffer' em busca de chamadas de tool.
Suporta formato DSML (<tool_calls><invoke name=...) e Claude-XML legacy,
ou seja <tool_call><function=...>.  Retorna uma lista de strings com os
blocos DSML encontrados, ou nil se nenhum for detectado."
  (let ((buf +carlos/magent-fsm-reasoning-buffer)
        (results nil))
    ;; 1. Formato DSML canônico do Magent
    (let ((pos 0))
      (while (string-match "<tool_calls>\\(.*?\\)</tool_calls>" buf pos)
        (push (match-string 0 buf) results)
        (setq pos (match-end 0))))
    ;; 2. Formato Claude-XML legacy: <tool_call>...</tool_call>
    (let ((pos 0))
      (while (string-match "<tool_call>\\(.*?\\)</tool_call>" buf pos)
        (push (match-string 0 buf) results)
        (setq pos (match-end 0))))
    (nreverse results)))

(defun +carlos/magent-fsm-maybe-rescue-reasoning-tool-calls ()
  "Se o turno terminou vazio mas o reasoning continha chamadas de tool, reinjeta.
Deve ser chamado no evento de turn-end quando o content é vazio.
Retorna t se alguma tool call foi recuperada, nil caso contrário."
  (let ((tool-calls (+carlos/magent-fsm-extract-tool-call-from-reasoning)))
    (when tool-calls
      (message "[Magent FSM] 🔧 %d tool call(s) recuperada(s) do reasoning — reinjetando."
               (length tool-calls))
      ;; Manda o bloco de volta ao parser nativo via log de diagnóstico
      ;; (o parse real ficará na Fase B quando hooks internos estiverem expostos)
      (dolist (block tool-calls)
        (message "[Magent FSM] Rescued tool call block: %s"
                 (truncate-string-to-width block 120 nil nil "…")))
      t)))

;; ── ETAPA 2b: Detecção de Subagentes (spawn_agent/wait_agent) ────────────────
;; O submodelo (spawn_agent) roda em sessão filha assíncrona. O contrato exige
;; que o orquestrador chame wait_agent(job_id) antes de encerrar o turno; quando
;; o turno termina com jobs pendentes, a FSM sinaliza `subagent-waiting' e o
;; watchdog é suprimido (wait de subagente é trabalho legítimo de longa duração,
;; não latência de backend).

(defun +carlos/magent-fsm-subagent-session-jobs ()
  "Retorna os jobs de subagentes ativos (queued/running) da sessão pai.
Usa `magent-tools--parent-session' e `magent-session-agent-jobs' do Magent;
retorna nil quando o Magent não está carregado ou não há sessão."
  (when (and (fboundp 'magent-tools--parent-session)
             (fboundp 'magent-session-agent-jobs)
             (fboundp 'magent-agent-job-status))
    (let ((session (magent-tools--parent-session)))
      (when session
        (cl-remove-if-not
         (lambda (job)
           (memq (magent-agent-job-status job) '(queued running)))
         (magent-session-agent-jobs session))))))

(defun +carlos/magent-fsm-refresh-subagent-jobs ()
  "Sincroniza `+carlos/magent-fsm-subagent-jobs' com a sessão pai.
Quando a infraestrutura de sessão do Magent está disponível, substitui o
cache pela lista atual de jobs ativos (nil limpa jobs já concluídos)."
  (when (and (fboundp 'magent-tools--parent-session)
             (fboundp 'magent-session-agent-jobs)
             (fboundp 'magent-agent-job-status))
    (setq +carlos/magent-fsm-subagent-jobs
          (+carlos/magent-fsm-subagent-session-jobs))))

(defun +carlos/magent-fsm-pending-subagent-p ()
  "Non-nil quando há subagentes ativos (cache ou sessão pai com jobs running)."
  (or +carlos/magent-fsm-subagent-jobs
      (+carlos/magent-fsm-subagent-session-jobs)))

;; ── ETAPA 3: Watchdog de Latência & Fallback para Nuvem ─────────────────────
;; Timer de contagem regressiva que aborta a requisição local lenta e chaveia
;; o turno para o backend de fallback da nuvem.

(defvar +carlos/magent-watchdog-timer nil
  "Timer ativo de watchdog de latência do Magent.  nil quando inativo.")

(defun +carlos/magent-watchdog-cancel ()
  "Cancela o watchdog ativo, se existir."
  (when (timerp +carlos/magent-watchdog-timer)
    (cancel-timer +carlos/magent-watchdog-timer))
  (setq +carlos/magent-watchdog-timer nil))

(defun +carlos/magent-fsm-watchdog-should-fire-p ()
  "Non-nil quando o watchdog deve disparar no estado atual.
Não dispara enquanto houver subagente pendente: wait_agent legítimo é
trabalho de longa duração, não latência de backend."
  (and (memq +carlos/magent-fsm-state '(thinking tool-executing))
       (not (+carlos/magent-fsm-pending-subagent-p))))

(defun +carlos/magent-watchdog-start ()
  "Inicia o watchdog de latência com timeout do perfil do host.
Se o timer disparar antes de a requisição retornar, emite aviso e
registra o evento de fallback no echo area."
  (+carlos/magent-watchdog-cancel)
  (let ((timeout (+carlos/magent-profile-get :watchdog-timeout)))
    (setq +carlos/magent-watchdog-timer
          (run-with-timer
           timeout nil
           (lambda ()
             (setq +carlos/magent-watchdog-timer nil)
             (when (+carlos/magent-fsm-watchdog-should-fire-p)
               (message
                (concat "[Magent FSM] ⚠️  Watchdog disparou após %ds. "
                        "Backend local lento — fallback → %s/%s.")
                timeout
                +carlos/magent-fallback-backend
                +carlos/magent-fallback-model)
               ;; Sinaliza o estado de fallback para que a UI reflita
               (+carlos/magent-fsm-transition 'idle)))))))

;; ── Integração dos hooks FSM com os pontos de extensão do Magent ─────────────
;; Acoplamos os callbacks de ciclo de vida usando lifecycle sinks (quando
;; disponíveis) ou advice leves nos pontos de extensão existentes.

(defun +carlos/magent-fsm-turn-start-sink (event-data)
  "Sink chamado no início de cada turno da sessão do Magent.
EVENT-DATA é o plist do lifecycle event.  Guarda por `:type turn-start'
para não disparar em outros eventos (ex.: turn-end, subagent-start).
Reseta o buffer de reasoning, incrementa a sessão e inicia o watchdog.
Se há resultados de subagentes pendentes, formata e armazena para injeção.
Se um subagente ainda estiver ativo (turno de retomada), entra em
`subagent-running' em vez de `thinking'."
  (when (eq (plist-get event-data :type) 'turn-start)
    (setq +carlos/magent-fsm-reasoning-buffer ""
          +carlos/magent-fsm-retry-count 0)
    ;; Injetar resultados pendentes antes de transicionar
    (let ((injected-messages (+carlos/magent-fsm-inject-pending-results)))
      (when injected-messages
        (message "[Magent FSM] Injecting %d subagent result(s)"
                 (length injected-messages))))
    (if (+carlos/magent-fsm-pending-subagent-p)
        (+carlos/magent-fsm-transition 'subagent-running)
      (+carlos/magent-fsm-transition 'thinking))
    (+carlos/magent-watchdog-start)))

;; ── Fallback Inteligente: classificação de falha e retry up-tier ─────────

(defun +carlos/magent-fsm-classify-failure (event-data)
  "Classifica a falha de um subagente em EVENT-DATA.
Retorna \\='timeout, \\='model-unavailable, \\='context-length, ou nil."
  (let ((detail (or (plist-get event-data :detail) "")))
    (cond
     ((string-match-p "timeout" detail) 'timeout)
     ((string-match-p "model.*unavailable\\|429\\|rate.limit" detail) 'model-unavailable)
     ((string-match-p "context.*length\\|too.*long\\|maximum.*context" detail) 'context-length)
     (t nil))))

(defun +carlos/magent-fsm-resume-up-tier (job-id current-model)
  "Retorna plist (:backend B :model M) para retry com tier acima, ou nil.
JOB-ID é o job que falhou; CURRENT-MODEL é o modelo que causou a falha.
Falha se já houve retry para JOB-ID ou se não há modelo disponível."
  (let* ((info (alist-get job-id +carlos/magent-fsm-retry-info nil nil #'string=))
         (retried (and info (plist-get info :retried))))
    (unless retried
      (let* ((model-str (if (stringp current-model) current-model
                          (symbol-name current-model)))
             (current-tier (cond
                            ((string-match-p "MLX\\|Ollama" model-str) "local")
                            ((string-match-p "flash\\|lite\\|free" model-str) "free")
                            (t "paid")))
             (tier-order +carlos/magent-model-tier-order)
             (current-rank (cl-position current-tier tier-order :test #'equal))
             (next-rank (and current-rank (1+ current-rank)))
             (next-tier (and next-rank (< next-rank (length tier-order))
                            (nth next-rank tier-order))))
        (when (and next-tier (fboundp '+carlos/magent-resolve-model))
          (let ((choice (+carlos/magent-resolve-model
                         nil nil nil nil
                         (list :min-tier next-tier))))
            (when choice
              (list :backend (plist-get choice :backend)
                    :model (plist-get choice :model)))))))))

(defun +carlos/magent-fsm-record-failure (job-id failure-type current-model)
  "Registra falha de JOB-ID com FAILURE-TYPE e CURRENT-MODEL."
  (let ((info (alist-get job-id +carlos/magent-fsm-retry-info nil nil #'string=)))
    (if info
        (setf (alist-get job-id +carlos/magent-fsm-retry-info nil nil #'string=)
              (plist-put info :failure-reason failure-type))
      (setf (alist-get job-id +carlos/magent-fsm-retry-info nil nil #'string=)
            (list :retried nil
                  :original-model current-model
                  :failure-reason failure-type)))))

(defun +carlos/magent-fsm-mark-retried (job-id)
  "Marca JOB-ID como já retryado."
  (let ((info (alist-get job-id +carlos/magent-fsm-retry-info nil nil #'string=)))
    (when info
      (setf (alist-get job-id +carlos/magent-fsm-retry-info nil nil #'string=)
            (plist-put info :retried t)))))

(defun +carlos/magent-fsm-turn-end-sink (event-data)
  "Sink chamado ao fim de cada turno da sessão do Magent.
EVENT-DATA é o plist do lifecycle event do turno.
Cancela o watchdog e verifica se há tool calls perdidas no reasoning.
Se o turno terminou com subagentes pendentes (spawn_agent sem wait_agent
concluído), entra em `subagent-waiting' em vez de `idle'.

EVENTOS DE SUBAGENTE SÃO IGNORADOS: o contexto do subagente tem
`:subagent-id' preenchido (via
`magent-lifecycle-events-create-subagent-context');
o contexto do orquestrador não.  Sem esse filtro, o sink dispara
no contexto do subagente, `magent-tools--parent-session' retorna
a sessão filha (sem jobs filhos), o cache é limpo prematuramente
e a FSM cai em `idle' espuriamente."
  (let ((event-ctx (plist-get event-data :context)))
    (unless (and event-ctx
                 (fboundp 'magent-lifecycle-events-context-subagent-id)
                 (magent-lifecycle-events-context-subagent-id event-ctx))
      ;; ── Lógica original (apenas eventos do orquestrador) ──────────────
      (+carlos/magent-watchdog-cancel)
      (+carlos/magent-fsm-refresh-subagent-jobs)
      (+carlos/magent-fsm-collect-completed-jobs)
      (let ((status (plist-get event-data :status)))
        (cond
         ((eq status 'completed)
          (+carlos/magent-fsm-transition 'verifying)
          ;; Tenta resgatar tool calls do reasoning (turn vazio)
          (+carlos/magent-fsm-maybe-rescue-reasoning-tool-calls)
          (if (+carlos/magent-fsm-pending-subagent-p)
              (progn
                (+carlos/magent-fsm-register-observers-for-pending)
                (+carlos/magent-fsm-transition 'subagent-waiting))
            (+carlos/magent-fsm-transition 'idle)))
         (t
          (+carlos/magent-fsm-transition 'idle)))))))

;; Captura chunks de reasoning acumulando no buffer da FSM.
;; Advice leve em torno da callback do streaming do magent.
(defun +carlos/magent-fsm-reasoning-accumulator-a (orig-fn response &rest args)
  "Advice que acumula chunks de reasoning antes de repassar ao handler nativo.
ORIG-FN é o handler original; RESPONSE é o chunk de streaming do gptel.
ARGS são repassados intactos a ORIG-FN."
  (+carlos/magent-fsm-accumulate-reasoning response)
  (apply orig-fn response args))

(with-eval-after-load 'magent-llm-gptel
  ;; Registrar os sinks de turn-start e turn-end quando disponíveis
  (when (fboundp 'magent-lifecycle-events-add-sink)
    (magent-lifecycle-events-add-sink #'+carlos/magent-fsm-turn-start-sink)
    (magent-lifecycle-events-add-sink #'+carlos/magent-fsm-turn-end-sink))
  ;; Acumular reasoning via advice leve no callback de streaming
  (when (fboundp 'magent-llm-gptel--callback)
    (advice-add 'magent-llm-gptel--callback
                :around #'+carlos/magent-fsm-reasoning-accumulator-a)))

;; ── D5.1: Persistência de jobs de subagente (:agent-jobs) ───────────────────
;; Os jobs duráveis já nascem na sessão pai (`magent-session-agent-jobs') e
;; são salvos via `magent-tools--persist-parent-session'.  Aqui adicionamos o
;; histórico consultável e a reconciliação pós-restart: jobs queued/running
;; sem runtime vivo travariam a FSM (subagent-running/subagent-waiting).

(defun +carlos/magent-subagent-jobs-history (&optional session)
  "Retorna TODOS os jobs de subagente persistidos na SESSION pai.
Qualquer status (queued/running/waiting/completed/failed/closed/cancelled).
SESSION default = `magent-tools--parent-session'.  nil sem infra do Magent."
  (when-let* ((session
               (or session
                   (and (fboundp 'magent-tools--parent-session)
                        (ignore-errors (magent-tools--parent-session))))))
    (and (fboundp 'magent-session-agent-jobs)
         (copy-sequence (magent-session-agent-jobs session)))))

(defun +carlos/magent-subagent-stale-job-p (job)
  "Non-nil quando JOB está queued/running sem runtime vivo."
  (and job
       (memq (magent-agent-job-status job) '(queued running))
       (null (magent-agent-job-runtime (magent-agent-job-id job)))))

(defun +carlos/magent-subagent-reconcile-stale-jobs ()
  "Cancela jobs queued/running sem runtime vivo na sessão pai.
Usa `magent-agent-job-reconcile-after-restart' e agenda persistência da
sessão.  Retorna os ids dos jobs reconciliados (nil = nada a fazer)."
  (when (and (fboundp 'magent-agent-job-status)
             (fboundp 'magent-agent-job-runtime)
             (fboundp 'magent-agent-job-reconcile-after-restart))
    (let* ((session (ignore-errors (magent-tools--parent-session)))
           (jobs (and session (+carlos/magent-subagent-jobs-history session)))
           reconciled)
      (when jobs
        (dolist (job jobs)
          (when (+carlos/magent-subagent-stale-job-p job)
            (magent-agent-job-reconcile-after-restart
             job "Runtime ausente — reconciliado após restart")
            (push (magent-agent-job-id job) reconciled)))
        (when (and reconciled
                   (fboundp 'magent-session-save-deferred-for-session))
          (ignore-errors
            (magent-session-save-deferred-for-session
             session
             (or (and (fboundp 'magent-tools--parent-scope)
                      (ignore-errors (magent-tools--parent-scope)))
                 'global)))))
      (nreverse reconciled))))

;; ── D5.2: Ledger — correlação call-id ↔ job (spawn_agent/wait_agent) ────────
(defcustom +carlos/magent-subagent-tracked-tools '("spawn_agent" "wait_agent")
  "Tools de subagente rastreadas no registro call-id → ciclo de vida do job."
  :type '(repeat string)
  :group 'magent)

(defvar +carlos/magent-subagent--calls (make-hash-table :test #'equal)
  "Registro D5: call-id → plist de correlação tool-call/job.
Chaves: `:tool', `:args', `:started-at', `:status', `:finished-at',
`:job-id', `:job-status'.")

(defun +carlos/magent-subagent-call-entry (call-id)
  "Retorna a entrada do registro para CALL-ID, ou nil."
  (gethash call-id +carlos/magent-subagent--calls))

(defun +carlos/magent-subagent-ledger-reset ()
  "Limpa o registro de correlação call-id → job (uso em testes/boot)."
  (clrhash +carlos/magent-subagent--calls))

(defun +carlos/magent-subagent--job-id-from-args (args)
  "Extrai o primeiro job id dos ARGS da tool wait_agent.
Aceita `:job_id'/`:job-id' (string) e `:job_ids'/`:job-ids' (string,
lista ou vetor)."
  (let ((raw (or (plist-get args :job_id)
                 (plist-get args :job-id)
                 (plist-get args :job_ids)
                 (plist-get args :job-ids))))
    (cond
     ((stringp raw) (and (not (string-empty-p raw)) raw))
     ((vectorp raw) (and (> (length raw) 0) (format "%s" (aref raw 0))))
     ((listp raw) (car raw))
     (t nil))))

(defun +carlos/magent-subagent-ledger-note-tool (event &optional end-p)
  "Atualiza o registro com um evento tool-call-start/end (END-P non-nil)."
  (let ((call-id (plist-get event :call-id))
        (name (plist-get event :tool-name)))
    (when (and call-id (member name +carlos/magent-subagent-tracked-tools))
      (if end-p
          (when-let* ((entry (gethash call-id +carlos/magent-subagent--calls)))
            (puthash call-id
                     (plist-put (plist-put (copy-sequence entry)
                                           :status (plist-get event :status))
                                :finished-at (float-time))
                     +carlos/magent-subagent--calls))
        (unless (gethash call-id +carlos/magent-subagent--calls)
          (puthash call-id
                   (append (list :tool name
                                 :started-at (or (plist-get event :time)
                                                 (float-time))
                                 :status 'running)
                           (when-let* ((job-id (+carlos/magent-subagent--job-id-from-args
                                                (plist-get event :args))))
                             (list :job-id job-id)))
                   +carlos/magent-subagent--calls))))))

(defun +carlos/magent-subagent-ledger-note-job (event)
  "Liga o ciclo de vida do job (evento agent-job-event) às entradas abertas.
Entradas de spawn_agent sem job-id recebem o id/status; entradas com id já
definido (wait_agent) só atualizam em caso de match exato."
  (when-let* ((job (plist-get event :job)))
    (let* ((phase (plist-get event :event))
           (detail (plist-get event :detail)))
      (maphash
       (lambda (call-id entry)
         (let ((entry-job-id (plist-get entry :job-id)))
           (when (or (null entry-job-id)
                     (equal entry-job-id (magent-agent-job-id job)))
             (puthash call-id
                      (plist-put
                       (plist-put
                        (plist-put (copy-sequence entry)
                                   :job-id (magent-agent-job-id job))
                        :job-status phase)
                       :result detail)
                      +carlos/magent-subagent--calls))))
       +carlos/magent-subagent--calls))))


;; ── Registro D5: sink único de lifecycle events ──────────────────────────────
(defun +carlos/magent-subagent-lifecycle-sink (event)
  "Sink D5: reconcile stale jobs no turn-start; alimenta o ledger D5.2."
  (pcase (plist-get event :type)
    ('turn-start (+carlos/magent-subagent-reconcile-stale-jobs))
    ('tool-call-start
     (+carlos/magent-subagent-ledger-note-tool event))
    ('tool-call-end
     (+carlos/magent-subagent-ledger-note-tool event :end))
    ('agent-job-event
     (+carlos/magent-subagent-ledger-note-job event))))

(with-eval-after-load 'magent-lifecycle-events
  (magent-lifecycle-events-add-sink #'+carlos/magent-subagent-lifecycle-sink))


(provide 'custom-magent-fsm)
;;; custom-magent-fsm.el ends here
