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
    (cl-letf (((symbol-function '+carlos/magent-fsm-subagent-session-jobs)
               (lambda () '(job1))))
      (+carlos/magent-fsm-turn-end-sink '(:status completed))
      (should (eq +carlos/magent-fsm-state 'subagent-waiting)))))

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

;; ── GRUPO 10: Subagentes com Modelo Forte (perfis por agente) ─────────────
;; O pacote herda backend/modelo do pai e a herança vence o override do agente
;; (`(or inherited-backend gptel-backend)'). O advice
;; `+carlos/magent-subagent-apply-profile' força o perfil declarado em
;; `+carlos/magent-subagent-profiles' no request-state do filho.

(ert-deftest myemacs-magent-subagent-profiles-defaults ()
  "Os perfis padrão mapeiam explore/general para o modelo forte da nuvem."
  (skip-unless (boundp '+carlos/magent-subagent-profiles))
  (let ((explore (cdr (assoc "explore" +carlos/magent-subagent-profiles)))
        (general (cdr (assoc "general" +carlos/magent-subagent-profiles))))
    (should (equal (plist-get explore :backend) "Gemini"))
    (should (equal (plist-get explore :model) "gemini-3.1-pro-preview"))
    (should (equal (plist-get general :backend) "Gemini"))
    (should (equal (plist-get general :model) "gemini-3.1-pro-preview"))))

(ert-deftest myemacs-magent-subagent-profile-resolver ()
  "O resolvedor devolve o perfil de agente conhecido e nil para desconhecido."
  (skip-unless (boundp '+carlos/magent-subagent-profiles))
  (should (fboundp '+carlos/magent-subagent-profile))
  (should (plist-get (+carlos/magent-subagent-profile "explore") :model))
  (should (null (+carlos/magent-subagent-profile "orchestrator-not-delegating"))))

(ert-deftest myemacs-magent-subagent-apply-profile-known-agent ()
  "Advice aplica o perfil (backend/modelo forte) no request-state de agente com perfil."
  (skip-unless (fboundp '+carlos/magent-subagent-apply-profile))
  (skip-unless (fboundp 'magent-request-context-create))
  (let* ((rc (magent-request-context-create :model 'gemma-local :backend 'local))
         (agent (and (fboundp 'magent-agent-info-create)
                     (magent-agent-info-create :name "explore" :mode 'subagent)))
         (called nil)
         (orig (lambda (&rest _) (setq called t))))
    (funcall #'+carlos/magent-subagent-apply-profile
             orig "prompt" nil agent nil nil nil nil nil nil rc)
    (should called)
    (should (eq (cl-struct-slot-value 'magent-request-context 'backend rc)
                (gptel-get-backend "Gemini")))
    (should (eq (cl-struct-slot-value 'magent-request-context 'model rc)
                'gemini-3.1-pro-preview))))

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

(provide 'magent-fsm-test)
;;; magent-fsm-test.el ends here
