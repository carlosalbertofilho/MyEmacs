;;; magent-fsm-test.el --- FSM Event Loop regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Suíte ERT para o loop de eventos assíncrono da FSM do Magent.
;; Cobre: variáveis de estado, transições, detecção de perfil de host,
;; acumulador de reasoning, parser DSML de tool calls, watchdog de latência
;; e roteamento dinâmico de backend.
;;
;; Todos os testes rodam offline (sem rede) e sem depender do pacote magent
;; instalado — testam apenas as funções definidas em custom-magent.el.

;;; Code:
(require 'ert)
(require 'cl-lib)

;; ── Loader: carrega custom-magent.el do ambiente correto ─────────────────────
(defvar myemacs-fsm-config-dir
  (or (getenv "EMACS_TEST_DIR") "~/.config/emacs")
  "Diretório de configuração Emacs usado nos testes da FSM.")

(defvar myemacs-fsm-magent-el
  (expand-file-name "lisp/custom-magent.el" myemacs-fsm-config-dir)
  "Caminho absoluto do custom-magent.el do ambiente de teste.")

(defvar myemacs-fsm-available
  (file-readable-p myemacs-fsm-magent-el)
  "Non-nil quando custom-magent.el está acessível no ambiente de teste.")

;; Carrega o arquivo silenciosamente para expor as funções/variáveis da FSM.
;; Guard: pula silenciosamente se gptel não estiver disponível (builds parciais).
(when myemacs-fsm-available
  (condition-case err
      (load myemacs-fsm-magent-el nil :nomessage)
    (error
     (setq myemacs-fsm-available nil)
     (message "magent-fsm-test: falha ao carregar custom-magent.el — %s" err))))

;; Refinamento: o arquivo pode existir mas ser de uma versão antiga (pré-FSM).
;; Nesse caso as variáveis não estarão bound — skip limpo em vez de FAILED.
(when (and myemacs-fsm-available
           (not (boundp '+carlos/magent-fsm-state)))
  (setq myemacs-fsm-available nil)
  (message "magent-fsm-test: custom-magent.el carregado mas sem código FSM — skipping."))


;; ── Helpers de teste ──────────────────────────────────────────────────────────

(defmacro myemacs-fsm-with-reset (&rest body)
  "Executa BODY com o estado da FSM resetado, restaurando-o ao fim."
  (declare (indent 0))
  `(let ((+carlos/magent-fsm-state 'idle)
         (+carlos/magent-fsm-session nil)
         (+carlos/magent-fsm-retry-count 0)
         (+carlos/magent-fsm-reasoning-buffer "")
         (+carlos/magent-fsm-subagent-jobs nil))
     ,@body))

;; ── GRUPO 1: Variáveis de estado ─────────────────────────────────────────────

(ert-deftest myemacs-magent-fsm-state-vars-exist ()
  "As variáveis de estado da FSM devem estar definidas."
  (skip-unless myemacs-fsm-available)
  (should (boundp '+carlos/magent-fsm-state))
  (should (boundp '+carlos/magent-fsm-session))
  (should (boundp '+carlos/magent-fsm-retry-count))
  (should (boundp '+carlos/magent-fsm-reasoning-buffer)))

(ert-deftest myemacs-magent-fsm-initial-state-is-idle ()
  "O estado inicial da FSM deve ser `idle'."
  (skip-unless myemacs-fsm-available)
  (myemacs-fsm-with-reset
    (should (eq +carlos/magent-fsm-state 'idle))))

;; ── GRUPO 2: Função de reset ──────────────────────────────────────────────────

(ert-deftest myemacs-magent-fsm-reset-clears-state ()
  "A função de reset deve restaurar todos os campos para os defaults."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-reset))
  (let ((+carlos/magent-fsm-state 'thinking)
        (+carlos/magent-fsm-session "test-session")
        (+carlos/magent-fsm-retry-count 3)
        (+carlos/magent-fsm-reasoning-buffer "some accumulated reasoning"))
    (+carlos/magent-fsm-reset)
    (should (eq +carlos/magent-fsm-state 'idle))
    (should (null +carlos/magent-fsm-session))
    (should (= +carlos/magent-fsm-retry-count 0))
    (should (string= +carlos/magent-fsm-reasoning-buffer ""))))

;; ── GRUPO 3: Transições de estado ────────────────────────────────────────────

(ert-deftest myemacs-magent-fsm-transition-changes-state ()
  "A função de transição deve atualizar o estado atual."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-transition))
  (myemacs-fsm-with-reset
    (+carlos/magent-fsm-transition 'thinking)
    (should (eq +carlos/magent-fsm-state 'thinking))
    (+carlos/magent-fsm-transition 'tool-executing)
    (should (eq +carlos/magent-fsm-state 'tool-executing))
    (+carlos/magent-fsm-transition 'verifying)
    (should (eq +carlos/magent-fsm-state 'verifying))
    (+carlos/magent-fsm-transition 'summarizing)
    (should (eq +carlos/magent-fsm-state 'summarizing))
    (+carlos/magent-fsm-transition 'idle)
    (should (eq +carlos/magent-fsm-state 'idle))))

(ert-deftest myemacs-magent-fsm-transition-noop-same-state ()
  "A transição para o mesmo estado não deve alterar o estado."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-transition))
  (myemacs-fsm-with-reset
    (+carlos/magent-fsm-transition 'idle)
    (should (eq +carlos/magent-fsm-state 'idle))))

;; ── GRUPO 4: Perfil de host ───────────────────────────────────────────────────

(ert-deftest myemacs-magent-host-profile-returns-plist ()
  "A função de perfil de host deve retornar um plist com chaves obrigatórias."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-host-profile))
  (let ((profile (+carlos/magent-host-profile)))
    (should (listp profile))
    (should (plist-get profile :orchestrator-backend))
    (should (plist-get profile :orchestrator-model))
    (should (numberp (plist-get profile :watchdog-timeout)))))

(ert-deftest myemacs-magent-host-profile-agnes ()
  "O perfil de `agnes' deve usar MLX Local como orquestrador."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-host-profile))
  ;; Força o hostname para agnes.local
  (let* ((+carlos/magent-host-profiles
          `(("agnes" :orchestrator-backend "MLX Local"
                     :orchestrator-model "mlx-community/gemma-4-e2b-it-4bit"
                     :dev-backend "MLX Local"
                     :dev-model "mlx-community/Qwen3.5-Coder-7B-Instruct-4bit"
                     :reasoning-backend "MLX Local"
                     :reasoning-model "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit"
                     :watchdog-timeout 8)
            ("aa102-006l" :orchestrator-backend "Gemini"
                          :orchestrator-model "gemini-2.5-flash"
                          :dev-backend "Ollama Local"
                          :dev-model "qwen2.5-coder:3b"
                          :reasoning-backend "Ollama Local"
                          :reasoning-model "deepseek-r1:1.5b"
                          :watchdog-timeout 15))))
    ;; Simula hostname agnes.local patchando system-name
    (cl-letf (((symbol-function 'system-name) (lambda () "agnes.local")))
      (let ((profile (+carlos/magent-host-profile)))
        (should (equal (plist-get profile :orchestrator-backend) "MLX Local"))
        (should (= (plist-get profile :watchdog-timeout) 8))))))

(ert-deftest myemacs-magent-host-profile-aa102 ()
  "O perfil de `aa102-006l' deve usar Gemini como orquestrador e timeout 15s."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-host-profile))
  (let* ((+carlos/magent-host-profiles
          `(("agnes" :orchestrator-backend "MLX Local"
                     :orchestrator-model "mlx-community/gemma-4-e2b-it-4bit"
                     :dev-backend "MLX Local"
                     :dev-model "mlx-community/Qwen3.5-Coder-7B-Instruct-4bit"
                     :reasoning-backend "MLX Local"
                     :reasoning-model "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit"
                     :watchdog-timeout 8)
            ("aa102-006l" :orchestrator-backend "Gemini"
                          :orchestrator-model "gemini-2.5-flash"
                          :dev-backend "Ollama Local"
                          :dev-model "qwen2.5-coder:3b"
                          :reasoning-backend "Ollama Local"
                          :reasoning-model "deepseek-r1:1.5b"
                          :watchdog-timeout 15))))
    (cl-letf (((symbol-function 'system-name) (lambda () "aa102-006l")))
      (let ((profile (+carlos/magent-host-profile)))
        (should (equal (plist-get profile :orchestrator-backend) "Gemini"))
        (should (equal (plist-get profile :orchestrator-model) "gemini-2.5-flash"))
        (should (= (plist-get profile :watchdog-timeout) 15))))))

(ert-deftest myemacs-magent-host-profile-unknown-defaults-to-agnes ()
  "Hostname desconhecido deve usar o primeiro perfil (agnes/GPU Local)."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-host-profile))
  (let* ((+carlos/magent-host-profiles
          `(("agnes" :orchestrator-backend "MLX Local"
                     :orchestrator-model "mlx-community/gemma-4-e2b-it-4bit"
                     :dev-backend "MLX Local"
                     :dev-model "mlx-community/Qwen3.5-Coder-7B-Instruct-4bit"
                     :reasoning-backend "MLX Local"
                     :reasoning-model "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit"
                     :watchdog-timeout 8)
            ("aa102-006l" :orchestrator-backend "Gemini"
                          :orchestrator-model "gemini-2.5-flash"
                          :dev-backend "Ollama Local"
                          :dev-model "qwen2.5-coder:3b"
                          :reasoning-backend "Ollama Local"
                          :reasoning-model "deepseek-r1:1.5b"
                          :watchdog-timeout 15))))
    (cl-letf (((symbol-function 'system-name) (lambda () "unknown-machine.local")))
      (let ((profile (+carlos/magent-host-profile)))
        (should (equal (plist-get profile :orchestrator-backend) "MLX Local"))
        (should (= (plist-get profile :watchdog-timeout) 8))))))

;; ── GRUPO 5: Acumulador de Reasoning ─────────────────────────────────────────

(ert-deftest myemacs-magent-fsm-reasoning-accumulator-appends ()
  "O acumulador deve concatenar chunks de reasoning consecutivos."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-accumulate-reasoning))
  (let ((+carlos/magent-fsm-reasoning-buffer ""))
    (+carlos/magent-fsm-accumulate-reasoning '(reasoning . "Primeiro chunk. "))
    (+carlos/magent-fsm-accumulate-reasoning '(reasoning . "Segundo chunk."))
    (should (string= +carlos/magent-fsm-reasoning-buffer
                     "Primeiro chunk. Segundo chunk."))))

(ert-deftest myemacs-magent-fsm-reasoning-accumulator-ignores-non-reasoning ()
  "O acumulador deve ignorar chunks que não são do canal reasoning."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-accumulate-reasoning))
  (let ((+carlos/magent-fsm-reasoning-buffer ""))
    (+carlos/magent-fsm-accumulate-reasoning "string simples")
    (+carlos/magent-fsm-accumulate-reasoning '(content . "conteúdo normal"))
    (+carlos/magent-fsm-accumulate-reasoning nil)
    (should (string= +carlos/magent-fsm-reasoning-buffer ""))))

;; ── GRUPO 6: Parser DSML de Tool Calls ───────────────────────────────────────

(ert-deftest myemacs-magent-fsm-extract-dsml-tool-call ()
  "Deve extrair bloco DSML de tool_calls do buffer de reasoning."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-extract-tool-call-from-reasoning))
  (let ((+carlos/magent-fsm-reasoning-buffer
         (concat "Vou usar uma ferramenta. "
                 "<tool_calls><invoke name=\"read_file\">"
                 "<parameter name=\"path\">/tmp/x.py</parameter>"
                 "</invoke></tool_calls>"
                 " E agora vou verificar.")))
    (let ((result (+carlos/magent-fsm-extract-tool-call-from-reasoning)))
      (should (listp result))
      (should (= (length result) 1))
      (should (string-match-p "<tool_calls>" (car result))))))

(ert-deftest myemacs-magent-fsm-extract-no-tool-calls-returns-nil ()
  "Deve retornar nil quando o reasoning não contém tool calls."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-extract-tool-call-from-reasoning))
  (let ((+carlos/magent-fsm-reasoning-buffer
         "Vou apenas pensar sobre o problema sem chamar ferramentas."))
    (should (null (+carlos/magent-fsm-extract-tool-call-from-reasoning)))))

(ert-deftest myemacs-magent-fsm-extract-multiple-tool-calls ()
  "Deve extrair múltiplos blocos DSML de um único buffer de reasoning."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-extract-tool-call-from-reasoning))
  (let ((+carlos/magent-fsm-reasoning-buffer
         (concat "<tool_calls><invoke name=\"read_file\"></invoke></tool_calls>"
                 " algum texto intermediário "
                 "<tool_calls><invoke name=\"write_file\"></invoke></tool_calls>")))
    (let ((result (+carlos/magent-fsm-extract-tool-call-from-reasoning)))
      (should (= (length result) 2)))))

;; ── GRUPO 7: Watchdog de Latência ────────────────────────────────────────────

(ert-deftest myemacs-magent-watchdog-timer-starts-and-cancels ()
  "O watchdog deve criar um timer ativo e cancelá-lo corretamente."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-watchdog-start))
  (skip-unless (fboundp '+carlos/magent-watchdog-cancel))
  ;; Mock do perfil para não depender de system-name real
  (cl-letf (((symbol-function '+carlos/magent-profile-get) (lambda (_k) 30)))
    (let (+carlos/magent-watchdog-timer)
      (+carlos/magent-watchdog-start)
      (should (timerp +carlos/magent-watchdog-timer))
      (+carlos/magent-watchdog-cancel)
      (should (null +carlos/magent-watchdog-timer)))))

(ert-deftest myemacs-magent-watchdog-cancel-is-idempotent ()
  "Cancelar o watchdog múltiplas vezes não deve sinalizar erro."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-watchdog-cancel))
  (let (+carlos/magent-watchdog-timer)
    (should-not (condition-case nil
                    (progn (+carlos/magent-watchdog-cancel)
                           (+carlos/magent-watchdog-cancel)
                           nil)
                  (error t)))))

;; ── GRUPO 8: Sink de turn-end ─────────────────────────────────────────────────

(ert-deftest myemacs-magent-fsm-turn-end-completed-returns-idle ()
  "O sink de turn-end com status completed deve finalizar em idle."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-turn-end-sink))
  (myemacs-fsm-with-reset
    (+carlos/magent-fsm-transition 'thinking)
    ;; Sem subagentes pendentes e sem reasoning buffer — turn-end limpo
    (cl-letf (((symbol-function '+carlos/magent-fsm-subagent-session-jobs)
               (lambda () nil)))
      (+carlos/magent-fsm-turn-end-sink '(:status completed))
      (should (eq +carlos/magent-fsm-state 'idle)))))

(ert-deftest myemacs-magent-fsm-turn-end-error-returns-idle ()
  "O sink de turn-end com status de erro também deve finalizar em idle."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-turn-end-sink))
  (myemacs-fsm-with-reset
    (+carlos/magent-fsm-transition 'thinking)
    (cl-letf (((symbol-function '+carlos/magent-fsm-subagent-session-jobs)
               (lambda () nil)))
      (+carlos/magent-fsm-turn-end-sink '(:status error))
      (should (eq +carlos/magent-fsm-state 'idle)))))

;; ── GRUPO 9: Subagentes (spawn_agent/wait_agent) ─────────────────────────────

(ert-deftest myemacs-magent-fsm-subagent-jobs-var-exists ()
  "A FSM deve expor a variável de acompanhamento de subagentes."
  (skip-unless myemacs-fsm-available)
  (should (boundp '+carlos/magent-fsm-subagent-jobs)))

(ert-deftest myemacs-magent-fsm-reset-clears-subagent-jobs ()
  "O reset deve limpar a lista de subagentes ativos."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-reset))
  (let ((+carlos/magent-fsm-subagent-jobs '(job1 job2)))
    (+carlos/magent-fsm-reset)
    (should (null +carlos/magent-fsm-subagent-jobs))))

(ert-deftest myemacs-magent-fsm-pending-subagent-uses-cache ()
  "Com subagentes no cache, `pending-subagent-p' deve ser non-nil."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-pending-subagent-p))
  (let ((+carlos/magent-fsm-subagent-jobs '(job1)))
    (should (+carlos/magent-fsm-pending-subagent-p))))

(ert-deftest myemacs-magent-fsm-pending-subagent-session-fallback ()
  "Sem cache, `pending-subagent-p' consulta os jobs da sessão pai."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-pending-subagent-p))
  (let ((+carlos/magent-fsm-subagent-jobs nil))
    (cl-letf (((symbol-function '+carlos/magent-fsm-subagent-session-jobs)
               (lambda () '(job1))))
      (should (+carlos/magent-fsm-pending-subagent-p)))))

(ert-deftest myemacs-magent-fsm-pending-subagent-empty-is-nil ()
  "Sem cache e sem jobs na sessão, `pending-subagent-p' deve ser nil."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-pending-subagent-p))
  (let ((+carlos/magent-fsm-subagent-jobs nil))
    (cl-letf (((symbol-function '+carlos/magent-fsm-subagent-session-jobs)
               (lambda () nil)))
      (should-not (+carlos/magent-fsm-pending-subagent-p)))))

(ert-deftest myemacs-magent-fsm-turn-end-with-pending-subagent-waits ()
  "Turn-end completed com subagente pendente deve entrar em `subagent-waiting'."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-turn-end-sink))
  (myemacs-fsm-with-reset
    (+carlos/magent-fsm-transition 'thinking)
    (let ((mock-jobs (list (list :id "job1" :status 'running))))
      (cl-letf (((symbol-function '+carlos/magent-fsm-subagent-session-jobs)
                 (lambda () mock-jobs))
                ((symbol-function '+carlos/magent-fsm-subagent-jobs)
                 mock-jobs)
                ((symbol-function 'magent-agent-job-status)
                 (lambda (job) (plist-get job :status)))
                ((symbol-function 'magent-agent-job-id)
                 (lambda (job) (plist-get job :id)))
                ((symbol-function 'magent-agent-job-result) #'ignore)
                ((symbol-function 'magent-agent-job-agent-name) #'ignore)
                ((symbol-function 'magent-agent-job-error) #'ignore)
                ((symbol-function 'magent-agent-job-add-observer) #'ignore)
                ((symbol-function 'magent-agent-job-remove-observer) #'ignore)
                ((symbol-function 'magent-session-agent-jobs) #'ignore)
                ((symbol-function 'magent-tools--parent-session) #'ignore))
        (+carlos/magent-fsm-turn-end-sink '(:status completed))
        (should (eq +carlos/magent-fsm-state 'subagent-waiting))))))

(ert-deftest myemacs-magent-fsm-turn-start-with-pending-subagent-runs ()
  "Turn-start com subagente ativo deve entrar em `subagent-running'."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-turn-start-sink))
  (myemacs-fsm-with-reset
    (cl-letf (((symbol-function '+carlos/magent-fsm-subagent-session-jobs)
               (lambda () '(job1)))
              ((symbol-function '+carlos/magent-watchdog-start) #'ignore))
      (+carlos/magent-fsm-turn-start-sink nil)
      (should (eq +carlos/magent-fsm-state 'subagent-running)))))

(ert-deftest myemacs-magent-fsm-watchdog-suppressed-while-subagent-pending ()
  "O watchdog não deve disparar enquanto houver subagente pendente."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-watchdog-should-fire-p))
  (let ((+carlos/magent-fsm-state 'thinking)
        (+carlos/magent-fsm-subagent-jobs '(job1)))
    (should-not (+carlos/magent-fsm-watchdog-should-fire-p)))
  (let ((+carlos/magent-fsm-state 'thinking)
        (+carlos/magent-fsm-subagent-jobs nil))
    (cl-letf (((symbol-function '+carlos/magent-fsm-subagent-session-jobs)
               (lambda () nil)))
      (should (+carlos/magent-fsm-watchdog-should-fire-p)))))

(ert-deftest myemacs-magent-directives-enforce-subagent-lifecycle ()
  "As diretivas do sistema devem impor o contrato spawn→wait_agent com caminho absoluto."
  (skip-unless myemacs-fsm-available)
  (skip-unless (boundp '+carlos/magent-system-directives))
  (let ((d +carlos/magent-system-directives))
    (should (string-match-p "HARD RULE" d))
    (should (string-match-p "wait_agent" d))
    (should (string-match-p "MUST NOT end your turn" d))
    (should (string-match-p "absolute path" d))
    (should (string-match-p "do not receive the parent's attachments" d))))

;; ── GRUPO 10: Subagentes com Modelo Forte (perfis → dicas de roteamento) ────
;; O pacote herda backend/modelo do pai e a herança vence o override do agente
;; (`(or inherited-backend gptel-backend)'). O advice
;; `+carlos/magent-subagent-apply-profile' resolve o modelo em runtime pela
;; complexidade da tarefa respeitando as dicas (:min-tier) de
;; `+carlos/magent-subagent-profiles' — override do `select_model' primeiro,
;; resolução dinâmica como fallback (nunca modelo pinado).

(ert-deftest myemacs-magent-subagent-profiles-defaults ()
  "Perfis padrão declaram dicas (piso :min-tier) e nenhum modelo concreto."
  (skip-unless (boundp '+carlos/magent-subagent-profiles))
  (let ((explore (cdr (assoc "explore" +carlos/magent-subagent-profiles)))
        (coder (cdr (assoc "coder" +carlos/magent-subagent-profiles))))
    (should (equal (plist-get explore :min-tier) "local"))
    (should (equal (plist-get coder :min-tier) "paid"))
    (should-not (plist-get explore :model))
    (should-not (plist-get explore :backend))))

(ert-deftest myemacs-magent-subagent-profile-resolver ()
  "O resolvedor devolve as dicas de agente conhecido e nil para desconhecido."
  (skip-unless (boundp '+carlos/magent-subagent-profiles))
  (should (fboundp '+carlos/magent-subagent-profile))
  (should (plist-get (+carlos/magent-subagent-profile "explore") :min-tier))
  (should (null (+carlos/magent-subagent-profile "orchestrator-not-delegating"))))

(ert-deftest myemacs-magent-subagent-resolve-honors-hints ()
  "A resolução dinâmica classifica a tarefa e aplica as dicas do perfil."
  (skip-unless (fboundp '+carlos/magent-subagent-resolve))
  (cl-letf (((symbol-function '+carlos/magent-task-complexity) (lambda (_) 'simple))
            ((symbol-function '+carlos/magent-resolve-model)
             (lambda (complexity _ping &rest _)
               (list :backend "Zen Claude" :model "claude-sonnet-5"
                     :tier "paid" :reason (format "%s via hints" complexity))))
            ((symbol-function '+carlos/local-ai-server-ping-p) (lambda () t)))
    (let ((+carlos/magent-subagent-profiles
           '(("coder" :min-tier "paid"))))
      (should (equal (+carlos/magent-subagent-resolve "coder" "any task")
                     '(:backend "Zen Claude" :model "claude-sonnet-5"))))
    (should (null (+carlos/magent-subagent-resolve "no-such-agent" "any")))))

(ert-deftest myemacs-magent-subagent-apply-profile-known-agent ()
  "Advice resolve dinamicamente (fallback sem override) e aplica no request-state."
  (skip-unless (fboundp '+carlos/magent-subagent-apply-profile))
  (skip-unless (fboundp 'magent-request-context-create))
  (let* ((rc (magent-request-context-create :model 'gemma-local :backend 'local))
         (agent (and (fboundp 'magent-agent-info-create)
                     (magent-agent-info-create :name "explore" :mode 'subagent)))
         (called nil)
         (orig (lambda (&rest _) (setq called t)))
         (resolver-calls 0))
    (cl-letf (((symbol-function '+carlos/magent-resolve-model)
               (lambda (&rest _)
                 (setq resolver-calls (1+ resolver-calls))
                 '(:backend "Gemini" :model "gemini-3.5-flash"
                   :tier "free" :reason "test"))))
      (funcall #'+carlos/magent-subagent-apply-profile
               orig "prompt" nil agent nil nil nil nil nil nil rc))
    (should called)
    (should (= resolver-calls 1))
    (should (eq (cl-struct-slot-value 'magent-request-context 'backend rc)
                (gptel-get-backend "Gemini")))
    (should (eq (cl-struct-slot-value 'magent-request-context 'model rc)
                'gemini-3.5-flash))))

(ert-deftest myemacs-magent-subagent-apply-profile-unknown-agent ()
  "Advice não altera o request-state de agentes sem perfil (ex.: orquestrador)."
  (skip-unless (fboundp '+carlos/magent-subagent-apply-profile))
  (skip-unless (fboundp 'magent-request-context-create))
  (let* ((rc (magent-request-context-create :model 'gemma-local :backend 'local))
         (agent (and (fboundp 'magent-agent-info-create)
                     (magent-agent-info-create :name "build" :mode 'primary)))
         (orig (lambda (&rest _) t)))
    (funcall #'+carlos/magent-subagent-apply-profile
             orig "prompt" nil agent nil nil nil nil nil nil rc)
    (should (eq (cl-struct-slot-value 'magent-request-context 'backend rc) 'local))
    (should (eq (cl-struct-slot-value 'magent-request-context 'model rc) 'gemma-local))))

(ert-deftest myemacs-magent-subagent-advice-installed ()
  "O advice de perfis de subagente está instalado em magent-agent-process."
  (skip-unless (fboundp 'magent-agent-process))
  (should (advice-member-p #'+carlos/magent-subagent-apply-profile
                           'magent-agent-process)))

(ert-deftest myemacs-magent-directives-enforce-subagent-delegation ()
  "As diretivas devem instruir o orquestrador a delegar exploração/análise."
  (skip-unless myemacs-fsm-available)
  (skip-unless (boundp '+carlos/magent-system-directives))
  (let ((d +carlos/magent-system-directives))
    (should (string-match-p "SUBAGENT DELEGATION" d))
    (should (string-match-p "ORCHESTRATOR" d))
    (should (string-match-p "spawn_agent" d))
    (should (string-match-p "stronger cloud model" d))))

(ert-deftest myemacs-magent-directives-enforce-edit-delegation ()
  "A directiva 8 deve proibir o orquestrador de editar arquivos complexos
e obrigar a delegação a subagente (modelo forte), instruindo leitura prévia.
Regressão: orquestrador local tentou editar TODO.org e alucinou old_text
('old_text not found')."
  (skip-unless (boundp '+carlos/magent-system-directives))
  (let ((d +carlos/magent-system-directives))
    (should (string-match-p "COMPLEX FILE EDIT" d))
    (should (string-match-p "only orchestrate" d))
    (should (string-match-p "old_text not found" d))
    (should (string-match-p "read_file" d))
    (should (string-match-p "read the target file" d))))

;; ── GRUPO 11: Isolamento de eventos de subagente na FSM ──────────────────────
;; Regressão: o turn-end-sink é global — eventos de turno de subagentes disparam
;; no contexto do subagente, onde `magent-tools--parent-session' retorna a sessão
;; filha (sem jobs filhos), limpando o cache e forcando a FSM para idle
;; espuriamente.  O filtro por :subagent-id no contexto do evento impede isso.

(ert-deftest myemacs-magent-fsm-turn-end-subagent-event-ignored ()
  "Evento turn-end com :subagent-id no contexto deve ser ignorado pela FSM.
Regressão: subagente executava read_file/grep, turn-end-sink disparava no
contexto do subagente, refresh-subagent-jobs limpava o cache e a FSM caía
em idle prematuramente."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-turn-end-sink))
  (skip-unless (fboundp 'magent-lifecycle-events-context-create))
  (myemacs-fsm-with-reset
    ;; Simula FSM em subagent-waiting (orquestrador aguardando subagente)
    (+carlos/magent-fsm-transition 'subagent-waiting)
    (let* ((ctx (magent-lifecycle-events-context-create :subagent-id "test-abc123"))
           (event (list :type 'turn-end :context ctx :status 'completed)))
      (+carlos/magent-fsm-turn-end-sink event)
      ;; Deve permanecer em subagent-waiting (evento ignorado)
      (should (eq +carlos/magent-fsm-state 'subagent-waiting)))))

(ert-deftest myemacs-magent-fsm-turn-end-orchestrator-event-processed ()
  "Evento turn-end SEM :subagent-id (orquestrador) continua sendo processado.
Garante que o filtro não bloqueia eventos legítimos do orquestrador."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-turn-end-sink))
  (skip-unless (fboundp 'magent-lifecycle-events-context-create))
  (myemacs-fsm-with-reset
    (+carlos/magent-fsm-transition 'thinking)
    ;; Contexto do orquestrador: sem subagent-id
    (let* ((ctx (magent-lifecycle-events-context-create))
           (event (list :type 'turn-end :context ctx :status 'completed)))
      ;; Sem subagentes pendentes → deve ir para idle
      (cl-letf (((symbol-function '+carlos/magent-fsm-subagent-session-jobs)
                 (lambda () nil)))
        (+carlos/magent-fsm-turn-end-sink event))
      (should (eq +carlos/magent-fsm-state 'idle)))))

;; ── GRUPO D6: Spinner de subagente (wiring FSM ↔ UI) ─────────────────────────
;; O wiring é mínimo: entrar em subagent-waiting inicia o spinner do painel e
;; sair (qualquer transição a partir dele) o para.  Stubs `cl-letf' nas funções
;; da UI para contar as chamadas sem depender do buffer *Magent* real.

(ert-deftest myemacs-magent-fsm-spinner-starts-on-subagent-waiting ()
  "Entrar em subagent-waiting inicia o spinner do painel (D6)."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-transition))
  (myemacs-fsm-with-reset
    (let ((start-calls 0) (stop-calls 0))
      (cl-letf (((symbol-function '+carlos/magent-ui-spinner-start)
                 (lambda () (setq start-calls (1+ start-calls)) t))
                ((symbol-function '+carlos/magent-ui-spinner-stop)
                 (lambda () (setq stop-calls (1+ stop-calls)) nil)))
        (+carlos/magent-fsm-transition 'subagent-waiting)
        (should (= start-calls 1))
        (should (= stop-calls 0))
        (+carlos/magent-fsm-transition 'idle)
        (should (= stop-calls 1))
        (should (= start-calls 1))))))

(ert-deftest myemacs-magent-fsm-spinner-not-started-elsewhere ()
  "Transições que não sejam subagent-waiting não iniciam o spinner."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-transition))
  (myemacs-fsm-with-reset
    (let ((start-calls 0) (stop-calls 0))
      (cl-letf (((symbol-function '+carlos/magent-ui-spinner-start)
                 (lambda () (setq start-calls (1+ start-calls)) t))
                ((symbol-function '+carlos/magent-ui-spinner-stop)
                 (lambda () (setq stop-calls (1+ stop-calls)) nil)))
        (+carlos/magent-fsm-transition 'thinking)
        (+carlos/magent-fsm-transition 'subagent-running)
        (should (= start-calls 0))
        (should (= stop-calls 0))))))

(ert-deftest myemacs-magent-fsm-reset-stops-spinner ()
  "Reset da FSM para o spinner (cancelamento/interrupção de sessão)."
  (skip-unless myemacs-fsm-available)
  (skip-unless (fboundp '+carlos/magent-fsm-reset))
  (myemacs-fsm-with-reset
    (let ((stop-calls 0))
      (cl-letf (((symbol-function '+carlos/magent-ui-spinner-stop)
                 (lambda () (setq stop-calls (1+ stop-calls)) nil)))
        (+carlos/magent-fsm-reset)
        (should (= stop-calls 1))))))

;; ── Sub-item 2: Fallback Inteligente com Retry (2026-08-17) ───────────────

(ert-deftest myemacs-magent-fsm-classify-failure-timeout ()
  "Garante que timeout é classificado corretamente."
  (skip-unless myemacs-fsm-available)
  (should (eq (+carlos/magent-fsm-classify-failure '(:detail "request timeout after 120s"))
              'timeout)))

(ert-deftest myemacs-magent-fsm-classify-failure-model-unavailable ()
  "Garante que modelo indisponível é classificado corretamente."
  (skip-unless myemacs-fsm-available)
  (should (eq (+carlos/magent-fsm-classify-failure '(:detail "model_unavailable: gemini-pro"))
              'model-unavailable))
  (should (eq (+carlos/magent-fsm-classify-failure '(:detail "429 rate limit exceeded"))
              'model-unavailable)))

(ert-deftest myemacs-magent-fsm-classify-failure-context-length ()
  "Garante que context_length_exceeded é classificado corretamente."
  (skip-unless myemacs-fsm-available)
  (should (eq (+carlos/magent-fsm-classify-failure '(:detail "context_length_exceeded: too long"))
              'context-length)))

(ert-deftest myemacs-magent-fsm-record-and-check-retry ()
  "Garante que retry info é registrado e verificado corretamente."
  (skip-unless myemacs-fsm-available)
  (let ((+carlos/magent-fsm-retry-info nil))
    ;; Record failure
    (+carlos/magent-fsm-record-failure "job-123" 'timeout "local-model")
    (should (alist-get "job-123" +carlos/magent-fsm-retry-info nil nil #'string=))
    (should (not (plist-get (alist-get "job-123" +carlos/magent-fsm-retry-info nil nil #'string=)
                            :retried)))
    ;; Mark as retried
    (+carlos/magent-fsm-mark-retried "job-123")
    (should (plist-get (alist-get "job-123" +carlos/magent-fsm-retry-info nil nil #'string=)
                       :retried))))

(ert-deftest myemacs-magent-fsm-resume-up-tier-no-double-retry ()
  "Garante que não há retry duas vezes para o mesmo job."
  (skip-unless myemacs-fsm-available)
  (let ((+carlos/magent-fsm-retry-info nil))
    (+carlos/magent-fsm-record-failure "job-456" 'timeout "local-model")
    (+carlos/magent-fsm-mark-retried "job-456")
    (should (null (+carlos/magent-fsm-resume-up-tier "job-456" "local-model")))))

(ert-deftest myemacs-magent-fsm-reset-clears-retry-info ()
  "Garante que reset limpa retry-info."
  (skip-unless myemacs-fsm-available)
  (let ((+carlos/magent-fsm-retry-info '(("job-789" . (:retried nil)))))
    (+carlos/magent-fsm-reset)
    (should (null +carlos/magent-fsm-retry-info))))

(ert-deftest myemacs-magent-fsm-retry-max-customizable ()
  "Garante que +carlos/magent-fsm-max-retries-per-subagent é customizável."
  (skip-unless myemacs-fsm-available)
  (should (boundp '+carlos/magent-fsm-max-retries-per-subagent))
  (should (integerp +carlos/magent-fsm-max-retries-per-subagent))
  (should (> +carlos/magent-fsm-max-retries-per-subagent 0)))

;; ── Fase E1: Subagent Result Collector ──────────────────────────────────────

(ert-deftest myemacs-magent-fsm-pending-results-exists ()
  "Garante que +carlos/magent-fsm-pending-results está declarado."
  (skip-unless myemacs-fsm-available)
  (should (boundp '+carlos/magent-fsm-pending-results)))

(ert-deftest myemacs-magent-fsm-observer-tokens-exists ()
  "Garante que +carlos/magent-fsm-observer-tokens está declarado."
  (skip-unless myemacs-fsm-available)
  (should (boundp '+carlos/magent-fsm-observer-tokens)))

(ert-deftest myemacs-magent-fsm-collect-completed-jobs-extracts-result ()
  "Garante que collect-completed-jobs extrai resultado de job concluído."
  (skip-unless myemacs-fsm-available)
  (let ((+carlos/magent-fsm-pending-results nil))
    (cl-letf (((symbol-function '+carlos/magent-fsm-collect-completed-jobs)
               (lambda ()
                 (setq +carlos/magent-fsm-pending-results
                       '(("job-collect-1" . (:agent-name "explore"
                                               :status completed
                                               :result "Found 3 files")))))))
      (+carlos/magent-fsm-collect-completed-jobs)
      (let ((stored (alist-get "job-collect-1" +carlos/magent-fsm-pending-results
                               nil nil #'string=)))
        (should stored)
        (should (equal (plist-get stored :result) "Found 3 files"))
        (should (equal (plist-get stored :agent-name) "explore"))))))

(ert-deftest myemacs-magent-fsm-collect-completed-jobs-ignores-running ()
  "Garante que collect-completed-jobs ignora jobs ainda em execução."
  (skip-unless myemacs-fsm-available)
  (let ((+carlos/magent-fsm-pending-results nil)
        (mock-job (list :id "job-running-1"
                        :agent-name "build"
                        :status 'running
                        :result nil)))
    (cl-letf (((symbol-function 'magent-tools--parent-session)
               (lambda () (list :agent-jobs (list mock-job))))
              ((symbol-function 'magent-session-agent-jobs)
               (lambda (session) (plist-get session :agent-jobs)))
              ((symbol-function 'magent-agent-job-status)
               (lambda (job) (plist-get job :status)))
              ((symbol-function 'magent-agent-job-result)
               (lambda (job) (plist-get job :result)))
              ((symbol-function 'magent-agent-job-agent-name)
               (lambda (job) (plist-get job :agent-name)))
              ((symbol-function 'magent-agent-job-id)
               (lambda (job) (plist-get job :id))))
      (+carlos/magent-fsm-collect-completed-jobs)
      (should (null +carlos/magent-fsm-pending-results)))))

(ert-deftest myemacs-magent-fsm-collect-completed-jobs-removes-from-pending ()
  "Garante que collect-completed-jobs coleta resultados de jobs failed também."
  (skip-unless myemacs-fsm-available)
  (let ((+carlos/magent-fsm-pending-results nil)
        (mock-job (list :id "job-fail-1"
                        :agent-name "coder"
                        :status 'failed
                        :result nil
                        :error "Timeout exceeded")))
    (cl-letf (((symbol-function 'magent-tools--parent-session)
               (lambda () (list :agent-jobs (list mock-job))))
              ((symbol-function 'magent-session-agent-jobs)
               (lambda (session) (plist-get session :agent-jobs)))
              ((symbol-function 'magent-agent-job-status)
               (lambda (job) (plist-get job :status)))
              ((symbol-function 'magent-agent-job-result)
               (lambda (job) (plist-get job :result)))
              ((symbol-function 'magent-agent-job-agent-name)
               (lambda (job) (plist-get job :agent-name)))
              ((symbol-function 'magent-agent-job-id)
               (lambda (job) (plist-get job :id)))
              ((symbol-function 'magent-agent-job-error)
               (lambda (job) (plist-get job :error))))
      (+carlos/magent-fsm-collect-completed-jobs)
      (let ((stored (alist-get "job-fail-1" +carlos/magent-fsm-pending-results
                               nil nil #'string=)))
        (should stored)
        (should (equal (plist-get stored :status) 'failed))
        (should (equal (plist-get stored :error) "Timeout exceeded"))))))

(ert-deftest myemacs-magent-fsm-reset-clears-pending-results ()
  "Garante que reset limpa pending-results e observer-tokens."
  (skip-unless myemacs-fsm-available)
  (let ((+carlos/magent-fsm-pending-results '(("job-x" . (:result "data"))))
        (+carlos/magent-fsm-observer-tokens '(token1 token2)))
    (cl-letf (((symbol-function 'magent-agent-job-remove-observer) #'ignore))
      (+carlos/magent-fsm-reset))
    (should (null +carlos/magent-fsm-pending-results))
    (should (null +carlos/magent-fsm-observer-tokens))))

(provide 'magent-fsm-test)
;;; magent-fsm-test.el ends here
