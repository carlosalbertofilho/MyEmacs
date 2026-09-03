;;; magent-ui-test.el --- Magent UI event loop (Fase C) regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Suíte ERT para o painel de atividade do Magent (Fase C, custom-magent-ui.el).
;; Cobre: sink de atividade (turn/tool/subagent/reasoning), badge de modelo,
;; advice de resumo de tool call enriquecido e ciclo de vida de subagente.
;;
;; Todos os testes rodam offline e sem depender do pacote magent instalado —
;; testam funções puras de formatação e o registro do sink/advice.

;;; Code:
(require 'ert)
(require 'cl-lib)

;; ── Loader: carrega custom-magent-ui.el do ambiente correto ──────────────────
(defvar myemacs-ui-config-dir
  (or (getenv "EMACS_TEST_DIR") "~/.config/emacs")
  "Diretório de configuração Emacs usado nos testes da UI do Magent.")

(defvar myemacs-ui-file
  (expand-file-name "lisp/custom-magent-ui.el" myemacs-ui-config-dir)
  "Caminho absoluto do custom-magent-ui.el do ambiente de teste.")

(defvar myemacs-ui-available
  (file-readable-p myemacs-ui-file)
  "Non-nil quando custom-magent-ui.el está acessível no ambiente de teste.")

(defvar +carlos/magent-sideband-queue nil
  "Forward declaration para rebinding dinâmico nos testes.")

(when myemacs-ui-available
  (condition-case err
      (load myemacs-ui-file nil :nomessage)
    (error
     (setq myemacs-ui-available nil)
     (message "magent-ui-test: falha ao carregar custom-magent-ui.el — %s" err))))

(defmacro myemacs-ui-with-buffer (&rest body)
  "Evaluate BODY with the sink insert helper pointed at a temp buffer."
  `(with-temp-buffer
     (let ((+carlos/magent-ui-insert-enabled t))
       (cl-letf (((symbol-function 'agent-shell-insert)
                  (lambda (&rest args)
                    (insert (plist-get args :text))))
                 ((symbol-function 'magent-agent-shell--buffer)
                  (lambda (&optional _) (current-buffer))))
         ,@body))))

;; ── Sink: registro ────────────────────────────────────────────────────────────
(ert-deftest myemacs-magent-ui-sink-registered ()
  "O sink de atividade está registrado no barramento de lifecycle events."
  (skip-unless myemacs-ui-available)
  (skip-unless (boundp 'magent-lifecycle-events--sinks))
  (should (member #'+carlos/magent-ui-activity-sink
                  magent-lifecycle-events--sinks)))

(ert-deftest myemacs-magent-ui-sink-functions-exist ()
  "As funções públicas do painel de atividade existem."
  (skip-unless myemacs-ui-available)
  (should (fboundp '+carlos/magent-ui-activity-sink))
  (should (fboundp '+carlos/magent-ui-register-sink)))

;; ── C1: Sink formata linhas por tipo de evento ───────────────────────────────
(ert-deftest myemacs-magent-ui-sink-format-tool-start ()
  "tool-call-start gera uma linha com nome e resumo."
  (skip-unless myemacs-ui-available)
  (myemacs-ui-with-buffer
    (setq +carlos/magent-ui-turn-start-time (float-time))
    (+carlos/magent-ui-activity-sink
     '(:type tool-call-start :call-id "c1" :tool-name "bash"
             :summary "ls -la"))
    (let ((content (buffer-string)))
      (should (string-match-p "ls -la" content))
      (should (string-match-p "⚙" content)))))

(ert-deftest myemacs-magent-ui-sink-format-tool-end ()
  "tool-call-end gera linha com status, exit-code e duração."
  (skip-unless myemacs-ui-available)
  (myemacs-ui-with-buffer
    (puthash "c2" (float-time) +carlos/magent-ui--tool-start-times)
    (+carlos/magent-ui-activity-sink
     '(:type tool-call-end :call-id "c2" :tool-name "bash"
             :status completed :exit-code 0
             :result-summary "README.md"))
    (let ((content (buffer-string)))
      (should (string-match-p "✓" content))
      (should (string-match-p "(exit 0)" content)))))

(ert-deftest myemacs-magent-ui-sink-format-turn-start ()
  "turn-start gera linha com título e badge de modelo quando disponível."
  (skip-unless myemacs-ui-available)
  (myemacs-ui-with-buffer
    (setq +carlos/magent-ui-last-turn-model '("Gemini" . "gemini-3.5-flash"))
    (+carlos/magent-ui-activity-sink
     '(:type turn-start :title "Agent build"))
    (let ((content (buffer-string)))
      (should (string-match-p "Agent build" content))
      (should (string-match-p "\\[Gemini gemini-3.5-flash\\]" content)))))

(ert-deftest myemacs-magent-ui-sink-format-subagent ()
  "agent-job-event gera linha com lifecycle, agente e modelo efetivo."
  (skip-unless myemacs-ui-available)
  (skip-unless (fboundp 'magent-agent-job-create))
  (myemacs-ui-with-buffer
    (let ((job (magent-agent-job-create :id "job-1" :agent-name "explore")))
      (cl-letf (((symbol-function '+carlos/magent-subagent-profile)
                 (lambda (agent)
                   (when (equal agent "explore")
                     '(:min-tier "paid")))))
        (+carlos/magent-ui-activity-sink
         `(:type agent-job-event :event started :job ,job))
        (+carlos/magent-ui-activity-sink
         `(:type agent-job-event :event completed :job ,job))))
    (let ((content (buffer-string)))
      (should (string-match-p "spawned → running" content))
      (should (string-match-p "completed ✓" content))
      (should (string-match-p "explore" content))
      (should (string-match-p "min paid tier" content)))))

(ert-deftest myemacs-magent-ui-sink-reasoning-preview ()
  "turn-end com reasoning acumulado gera preview truncado."
  (skip-unless myemacs-ui-available)
  (myemacs-ui-with-buffer
    (setq +carlos/magent-fsm-reasoning-buffer
          (make-string 1000 ?x))
    (+carlos/magent-ui-activity-sink '(:type turn-end :status completed))
    (let ((content (buffer-string)))
      (should (string-match-p "💭 reasoning" content))
      (should (string-match-p "1000 chars" content))
      (should (< (length content) 900)))))

(ert-deftest myemacs-magent-ui-sink-no-reasoning-empty ()
  "turn-end sem reasoning não gera linha de reasoning."
  (skip-unless myemacs-ui-available)
  (myemacs-ui-with-buffer
    (setq +carlos/magent-fsm-reasoning-buffer "")
    (+carlos/magent-ui-activity-sink '(:type turn-end :status completed))
    (should (string-empty-p (string-trim (buffer-string))))))

;; ── C4: Badge de modelo ──────────────────────────────────────────────────────
(ert-deftest myemacs-magent-ui-model-badge-captures-request ()
  "llm-request-start captura backend/modelo para o badge."
  (skip-unless myemacs-ui-available)
  (setq +carlos/magent-ui-last-turn-model nil)
  (+carlos/magent-ui-activity-sink
   '(:type llm-request-start :backend "MLX Local" :model "gemma-4"))
  (should (equal +carlos/magent-ui-last-turn-model
                 '("MLX Local" . "gemma-4"))))

(ert-deftest myemacs-magent-ui-model-badge-reset-on-turn-end ()
  "turn-end limpa o badge para o próximo turno."
  (skip-unless myemacs-ui-available)
  (myemacs-ui-with-buffer
    (setq +carlos/magent-ui-last-turn-model '("Gemini" . "gemini-3.5-flash")
          +carlos/magent-ui-turn-start-time (float-time))
    (+carlos/magent-ui-activity-sink '(:type turn-end :status completed))
    (should (null +carlos/magent-ui-last-turn-model))
    (should (null +carlos/magent-ui-turn-start-time))))

;; ── C2: Advice de resumo enriquecido ─────────────────────────────────────────
(ert-deftest myemacs-magent-ui-tool-call-detail-advice ()
  "O advice anexa modelo ao spawn_agent e cwd ao bash."
  (skip-unless myemacs-ui-available)
  (let* ((orig (lambda (name args)
                 (if (equal name "spawn_agent")
                     (format "%s: %s"
                             (plist-get args :agent)
                             (or (plist-get args :task_name) "?"))
                   (or (plist-get args :command) "?"))))
         (a #'+carlos/magent-ui-tool-call-summary-a))
    (cl-letf (((symbol-function '+carlos/magent-subagent-profile)
               (lambda (agent)
                 (when (equal agent "explore")
                   '(:min-tier "paid")))))
      (should (string-match-p
               "min paid tier"
               (funcall a orig "spawn_agent"
                        '(:agent "explore" :task_name "diagnose"))))
      (should (string-match-p
               "(in /tmp/proj)"
               (funcall a orig "bash" '(:command "ls" :cwd "/tmp/proj"))))
      (should (string-match-p
               "ls"
               (funcall a orig "bash" '(:command "ls" :cwd "/tmp/proj")))))))

;; ── C3: modelo efetivo de subagente ──────────────────────────────────────────
(ert-deftest myemacs-magent-ui-subagent-model-resolver ()
  "+carlos/magent-ui-subagent-model resolve perfil de agente."
  (skip-unless myemacs-ui-available)
  (cl-letf (((symbol-function '+carlos/magent-subagent-profile)
             (lambda (agent)
               (when (equal agent "general")
                 '(:min-tier "free")))))
    (should (equal (+carlos/magent-ui-subagent-model "general")
                   "(min free tier)"))
    (should (null (+carlos/magent-ui-subagent-model "unknown")))))

;; ── D6: Spinner de subagente ────────────────────────────────────────────────
(ert-deftest myemacs-magent-ui-spinner-inactive-by-default ()
  "O spinner começa inativo (sem timer)."
  (skip-unless myemacs-ui-available)
  (skip-unless (fboundp '+carlos/magent-ui-spinner-active-p))
  (should-not (+carlos/magent-ui-spinner-active-p)))

(ert-deftest myemacs-magent-ui-spinner-start-inserts-line ()
  "start liga o timer e insere a primeira linha de spinner no buffer."
  (skip-unless myemacs-ui-available)
  (skip-unless (fboundp '+carlos/magent-ui-spinner-start))
  (myemacs-ui-with-buffer
    (should (+carlos/magent-ui-spinner-start))
    (should (+carlos/magent-ui-spinner-active-p))
    (should (string-match-p "⏳" (buffer-string)))
    (should (string-match-p "aguardando subagente" (buffer-string)))
    (+carlos/magent-ui-spinner-stop)))

(ert-deftest myemacs-magent-ui-spinner-tick-advances-frame ()
  "tick substitui a linha pelo próximo frame, sem acumular linhas."
  (skip-unless myemacs-ui-available)
  (skip-unless (fboundp '+carlos/magent-ui-spinner-tick))
  (myemacs-ui-with-buffer
    (+carlos/magent-ui-spinner-start)
    (let ((first (buffer-string)))
      (+carlos/magent-ui-spinner-tick)
      (should (= (count-lines (point-min) (point-max)) 1))
      (should (not (string= first (buffer-string)))))
    (+carlos/magent-ui-spinner-stop)))

(ert-deftest myemacs-magent-ui-spinner-stop-removes-line ()
  "stop cancela o timer e remove a linha do spinner."
  (skip-unless myemacs-ui-available)
  (skip-unless (fboundp '+carlos/magent-ui-spinner-stop))
  (myemacs-ui-with-buffer
    (+carlos/magent-ui-spinner-start)
    (+carlos/magent-ui-spinner-stop)
    (should-not (+carlos/magent-ui-spinner-active-p))
    (should (null +carlos/magent-ui-spinner-marker))
    (should (string-empty-p (string-trim (buffer-string))))))

;; ── Permissões: roteamento centralizado de aprovações ────────────────
(ert-deftest myemacs-magent-ui-approval-route-local-without-session ()
  "Request sem audit-context cai na rota local (minibuffer)."
  (skip-unless myemacs-ui-available)
  (let ((+carlos/magent-approval-prefer-acp t))
    (should (eq (+carlos/magent-ui--approval-route
                 '(:request-id "r1" :tool-name "bash"))
                'local))))

(ert-deftest myemacs-magent-ui-approval-route-acp-bound-session ()
  "Request com session-id vinculada a um client ACP vai para a rota acp."
  (skip-unless myemacs-ui-available)
  (require 'magent-acp nil t)
  (skip-unless (fboundp 'magent-acp--approval-provider))
  (let* ((+carlos/magent-approval-prefer-acp t)
         (fake-client (list 'fake-client))
         (bindings (make-hash-table :test #'equal))
         (scopes (make-hash-table :test #'eq :weakness 'key)))
    (puthash "sess-1" 'global bindings)
    (puthash fake-client bindings scopes)
    (let ((magent-acp--client-session-scopes scopes))
      (cl-letf (((symbol-function 'magent-acp--callback-buffer)
                 (lambda (&optional _client _session) (current-buffer))))
        (should (equal (+carlos/magent-ui--approval-route
                        '(:audit-context (:session-id "sess-1")
                          :tool-name "bash"))
                       (list 'acp fake-client "sess-1")))))))

(ert-deftest myemacs-magent-ui-approval-route-local-when-client-dead ()
  "Client ACP com buffer morto não roteia; cai no local."
  (skip-unless myemacs-ui-available)
  (require 'magent-acp nil t)
  (skip-unless (fboundp 'magent-acp--approval-provider))
  (let* ((+carlos/magent-approval-prefer-acp t)
         (fake-client (list 'dead-client))
         (bindings (make-hash-table :test #'equal))
         (scopes (make-hash-table :test #'eq :weakness 'key)))
    (puthash "sess-2" 'global bindings)
    (puthash fake-client bindings scopes)
    (let ((magent-acp--client-session-scopes scopes))
      (cl-letf (((symbol-function 'magent-acp--callback-buffer)
                 (lambda (&optional _client _session) nil)))
        (should (eq (+carlos/magent-ui--approval-route
                     '(:audit-context (:session-id "sess-2")))
                    'local))))))

(ert-deftest myemacs-magent-ui-approval-smart-provider-dispatch ()
  "Provider central despacha para ACP quando há client vivo."
  (skip-unless myemacs-ui-available)
  (require 'magent-acp nil t)
  (skip-unless (fboundp 'magent-acp--approval-provider))
  (let* ((fake-client (list 'dispatch-client))
         (bindings (make-hash-table :test #'equal))
         (scopes (make-hash-table :test #'eq :weakness 'key))
         (seen-request nil)
         (seen-session nil)
         (request '(:audit-context (:session-id "sess-3") :tool-name "write")))
    (puthash "sess-3" 'global bindings)
    (puthash fake-client bindings scopes)
    (let ((magent-acp--client-session-scopes scopes)
          (+carlos/magent-approval-prefer-acp t))
      (cl-letf (((symbol-function 'magent-acp--callback-buffer)
                 (lambda (&optional _client _session) (current-buffer)))
                ((symbol-function 'magent-acp--approval-provider)
                 (lambda (_client session-id)
                   (setq seen-session session-id)
                   (lambda (req) (setq seen-request req)))))
        (+carlos/magent-approval-smart-provider request)))
    ;; Request processado pelo provider ACP fake:
    (should (eq seen-request request))
    (should (equal seen-session "sess-3"))))

(ert-deftest myemacs-magent-ui-approval-provider-installed ()
  "O provider central está instalado como magent-approval-provider-function."
  (skip-unless myemacs-ui-available)
  (require 'magent-approval nil t)
  (skip-unless (featurep 'magent-approval))
  ;; Recarrega o módulo para disparar `with-eval-after-load' agora.
  (load myemacs-ui-file nil :nomessage)
  (should (eq magent-approval-provider-function
              #'+carlos/magent-approval-smart-provider)))

(ert-deftest myemacs-magent-ui-approval-state-line-lifecycle ()
  "Hook anuncia requested/resolved no chat e mantém o hash coerente."
  (skip-unless myemacs-ui-available)
  (myemacs-ui-with-buffer
    (clrhash +carlos/magent-ui--pending-approvals)
    (unwind-protect
        (progn
          (+carlos/magent-ui-approval-state-line
           'requested "abcdefgh1234"
           '(:request (:tool-name "bash" :summary "ls -la /tmp")))
          (should (gethash "abcdefgh1234"
                           +carlos/magent-ui--pending-approvals))
          (should (string-match-p "bash" (buffer-string)))
          (should (string-match-p "aguardando decisão" (buffer-string)))
          (+carlos/magent-ui-approval-state-line
           'resolved "abcdefgh1234"
           '(:request (:tool-name "bash")
             :decision allow-once))
          (should-not (gethash "abcdefgh1234"
                               +carlos/magent-ui--pending-approvals))
          (should (string-match-p "allow-once" (buffer-string))))
      (remhash "abcdefgh1234" +carlos/magent-ui--pending-approvals))))

(ert-deftest myemacs-magent-ui-approval-state-line-drop-cleans-hash ()
  "Evento dropped limpa o registro e insere linha de descarte."
  (skip-unless myemacs-ui-available)
  (myemacs-ui-with-buffer
    (clrhash +carlos/magent-ui--pending-approvals)
    (unwind-protect
        (progn
          (puthash "drop1234" "write" +carlos/magent-ui--pending-approvals)
          (+carlos/magent-ui-approval-state-line
           'dropped "drop1234" '(:request (:tool-name "write")))
          (should-not (gethash "drop1234"
                               +carlos/magent-ui--pending-approvals))
          (should (string-match-p "descartada" (buffer-string))))
      (remhash "drop1234" +carlos/magent-ui--pending-approvals))))

(ert-deftest myemacs-magent-commands-transient-menu-defined ()
  "Garante que o menu Transient +carlos/magent-menu está definido."
  (load (expand-file-name "lisp/custom-magent-commands.el") nil t)
  (should (fboundp '+carlos/magent-menu)))

(ert-deftest myemacs-magent-commands-sideband-queue-test ()
  "Garante que input durante busy é enfileirado na sideband queue sem erro."
  (require 'shell-maker nil t)
  (load (expand-file-name "lisp/custom-magent-commands.el") nil t)
  (let ((+carlos/magent-sideband-queue nil)
        (interrupted nil))
    (with-temp-buffer
      (setq-local shell-maker--busy t)
      (insert "user side note")
      (cl-letf (((symbol-function '+carlos/magent-agent-shell-interrupt)
                 (lambda () (setq interrupted t))))
        (+carlos/magent-shell-maker-submit-around #'ignore))
      (should (equal +carlos/magent-sideband-queue '("user side note")))
      (should-not interrupted))
    (with-temp-buffer
      (setq-local shell-maker--busy t)
      (insert "abort")
      (cl-letf (((symbol-function '+carlos/magent-agent-shell-interrupt)
                 (lambda () (setq interrupted t))))
        (+carlos/magent-shell-maker-submit-around #'ignore))
      (should interrupted))))

(provide 'magent-ui-test)
