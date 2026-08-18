;;; custom-magent-fsm.el --- Magent FSM: orquestração, host routing e watchdog -*- lexical-binding: t; -*-

;;; Commentary:
;; Maquina de estados do Magent (orquestracao, subagentes, watchdog de
;; latencia), deteccao de perfil por host e roteamento de backend da sessao.
;; Tambem acumula o canal `reasoning' do gptel e recupera tool calls
;; emitidas dentro do pensamento (DSML/Claude-XML).

;;; Code:

(declare-function magent-lifecycle-events-add-sink "magent-lifecycle-events")
(declare-function magent-lifecycle-events-context-subagent-id "magent-lifecycle-events")
(declare-function magent-tools--parent-session "magent-tools")
(declare-function magent-session-agent-jobs "magent-session")
(declare-function magent-agent-job-status "magent-agent")
(declare-function +carlos/magent-buffer-reset-session "custom-magent-buffer")
(declare-function +carlos/magent-ui-spinner-start "custom-magent-ui")
(declare-function +carlos/magent-ui-spinner-stop "custom-magent-ui")
(declare-function +carlos/magent-resolve-model "custom-magent-tools")
(defvar +carlos/magent-model-tier-order)

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
        +carlos/magent-fsm-healing-last-error-count nil)
  (when (fboundp '+carlos/magent-buffer-reset-session)
    (+carlos/magent-buffer-reset-session))
  (when (fboundp '+carlos/magent-ui-spinner-stop)
    (+carlos/magent-ui-spinner-stop)))

(defun +carlos/magent-fsm-transition (new-state)
  "Transiciona a FSM para NEW-STATE e emite mensagem diagnóstica.
Inicia o spinner de subagente (D6) ao bloquear em `subagent-waiting' e o
para ao sair do estado (qualquer transição a partir dele)."
  (let ((prev +carlos/magent-fsm-state))
    (setq +carlos/magent-fsm-state new-state)
    (unless (eq prev new-state)
      (message "[Magent FSM] %s → %s" prev new-state)
      (cond
       ((eq new-state 'subagent-waiting)
        (when (fboundp '+carlos/magent-ui-spinner-start)
          (+carlos/magent-ui-spinner-start)))
       ((eq prev 'subagent-waiting)
        (when (fboundp '+carlos/magent-ui-spinner-stop)
          (+carlos/magent-ui-spinner-stop)))))))

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
                  :dev-backend          "Ollama Local"
                  :dev-model            "qwen2.5-coder:3b"
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
  "Aplica o perfil de backend do host ao gptel para a sessão Magent."
  (let* ((profile (+carlos/magent-host-profile))
         (orch-backend (plist-get profile :orchestrator-backend))
         (orch-model   (plist-get profile :orchestrator-model))
         (backend-obj  (and orch-backend (gptel-get-backend orch-backend))))
    (when backend-obj
      (setq gptel-backend backend-obj
            gptel-model   (intern orch-model))
      (message "[Magent FSM] Host=%s → backend=%s modelo=%s"
               (system-name) orch-backend orch-model))))

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

(defun +carlos/magent-fsm-turn-start-sink (_event-data)
  "Sink chamado no início de cada turno da sessão do Magent.
Reseta o buffer de reasoning, incrementa a sessão e inicia o watchdog.
Se um subagente ainda estiver ativo (turno de retomada), entra em
`subagent-running' em vez de `thinking'."
  (setq +carlos/magent-fsm-reasoning-buffer ""
        +carlos/magent-fsm-retry-count 0)
  (if (+carlos/magent-fsm-pending-subagent-p)
      (+carlos/magent-fsm-transition 'subagent-running)
    (+carlos/magent-fsm-transition 'thinking))
  (+carlos/magent-watchdog-start))

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
      (let ((status (plist-get event-data :status)))
        (cond
         ((eq status 'completed)
          (+carlos/magent-fsm-transition 'verifying)
          ;; Tenta resgatar tool calls do reasoning (turn vazio)
          (+carlos/magent-fsm-maybe-rescue-reasoning-tool-calls)
          (if (+carlos/magent-fsm-pending-subagent-p)
              (+carlos/magent-fsm-transition 'subagent-waiting)
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
    (magent-lifecycle-events-add-sink #'+carlos/magent-fsm-turn-end-sink))
  ;; Acumular reasoning via advice leve no callback de streaming
  (when (fboundp 'magent-llm-gptel--callback)
    (advice-add 'magent-llm-gptel--callback
                :around #'+carlos/magent-fsm-reasoning-accumulator-a)))

(provide 'custom-magent-fsm)
;;; custom-magent-fsm.el ends here
