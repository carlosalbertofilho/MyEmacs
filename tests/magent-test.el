;;; magent-test.el --- Magent regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifica: pacote carrega, comandos existem, bind C-c M m sem conflito,
;; configs (skills dir, project instructions) e registro no agent-shell.  Magent
;; pode não estar instalado no repo (builds parciais) — guard.

;;; Code:
(require 'ert)

(defvar myemacs-magent-available
  (condition-case nil (require 'magent) (error nil))
  "Non-nil quando o pacote magent carrega neste ambiente.")

(ert-deftest myemacs-magent-package-loads ()
  (skip-unless myemacs-magent-available)
  (should (featurep 'magent)))

(ert-deftest myemacs-magent-commands-exist ()
  (skip-unless myemacs-magent-available)
  (should (commandp 'magent-start))
  (should (commandp 'magent-agent-shell-interrupt))
  (should (commandp 'magent-agent-shell-prompt-region)))

(ert-deftest myemacs-magent-kbd-bind ()
  (skip-unless myemacs-magent-available)
  (should (eq (key-binding (kbd "C-c A m")) '+carlos/magent-start)))

(ert-deftest myemacs-magent-skill-dirs ()
  (skip-unless myemacs-magent-available)
  (should magent-skill-directories)
  (should (cl-some (lambda (d) (string-suffix-p "magent/skills" d))
                   magent-skill-directories)))

(ert-deftest myemacs-magent-project-instructions ()
  (skip-unless myemacs-magent-available)
  (should (member "AGENTS.md" magent-project-instruction-file-names)))

(ert-deftest myemacs-magent-agent-shell-config ()
  (skip-unless myemacs-magent-available)
  (magent-agent-shell-ensure-config)
  (should (memq #'magent-agent-shell-make-config agent-shell-agent-configs)))

(ert-deftest myemacs-magent-slash-commands-exist ()
  (should (commandp '+carlos/magent-set-workdir))
  (should (commandp '+carlos/magent-add-dir))
  (should (commandp '+carlos/magent-list-dirs))
  (should (commandp '+carlos/magent-render-usage-chat)))

(ert-deftest myemacs-magent-slash-interceptor ()
  (should (+carlos/magent-slash-interceptor "/list-dirs"))
  (should (+carlos/magent-slash-interceptor "/usage"))
  (should-not (+carlos/magent-slash-interceptor "olá mundo")))

(ert-deftest myemacs-magent-tool-sanitizers ()
  (skip-unless myemacs-magent-available)
  (skip-unless (file-directory-p "/home/carlosfilho/Projetos/emacsConfig/MyEmacs"))
  (let ((default-directory "/home/carlosfilho/Projetos/emacsConfig/MyEmacs/"))
    (should (string-prefix-p "/home/carlosfilho/Projetos/emacsConfig/MyEmacs/"
                             (magent-tools--resolve-path "AGENTS.md")))))

(ert-deftest myemacs-magent-analyze-agent-smith-target ()
  "Valida que +carlos/magent-analyze-agent-smith aponta para o projeto
Agent_Smith real (~/Projetos/42rio/CommonCore/Rank05/Agent_Smith) e informa
o caminho ao agente no prompt enviado ao magent-start."
  (skip-unless myemacs-magent-available)
  (skip-unless (file-directory-p
                (expand-file-name "~/Projetos/42rio/CommonCore/Rank05/Agent_Smith")))
  (should (string= "~/Projetos/42rio/CommonCore/Rank05/Agent_Smith"
                   +carlos/magent-agent-smith-dir))
  (let ((expected (expand-file-name "~/Projetos/42rio/CommonCore/Rank05/Agent_Smith")))
    (should (file-directory-p expected))
    (let (captured-prompt captured-dir)
      (cl-letf (((symbol-function 'magent-start)
                 (lambda (prompt &rest _)
                   (setq captured-prompt prompt
                         captured-dir default-directory))))
        (+carlos/magent-analyze-agent-smith))
      (should (stringp captured-prompt))
      (should (string-match-p "Agent_Smith" captured-prompt))
      (should (string-match-p (regexp-quote expected) captured-prompt))
      (should (string= expected captured-dir)))))

(ert-deftest myemacs-magent-log-context ()
  "Fase 2: o sink +carlos/magent-log-sink deve estar registrado no magent-log
e, quando chamado, o buffer *magent-log* recebe a linha mesmo quando o buffer
está read-only (modo magent-log-mode deriva de special-mode)."
  (skip-unless myemacs-magent-available)
  (let ((sink #'+carlos/magent-log-sink))
    ;; Sink registrado?
    (should (memq sink magent-log--sinks))
    ;; Sink grava no buffer *magent-log* mesmo read-only?
    (with-current-buffer (magent-log-buffer)
      (let ((start (point-max)))
        (funcall sink "teste-sink" 'info)
        (goto-char (point-max))
        (should (search-backward "teste-sink" start t))))))

(ert-deftest myemacs-magent-dsml-directive-content ()
  "A diretriz DSML ensina o formato textual parseável pelo magent:
<tool_calls>/<invoke name=...>/<parameter name=...> — nunca <tool_call>
singular, <function=...> ou <parameter=...> (formato Claude que o parser
ignora, deixando o turn vazio)."
  (should (string-match-p "<tool_calls>" +carlos/magent-system-directives))
  (should (string-match-p "<invoke name=\"read_file\">"
                          +carlos/magent-system-directives))
  (should (string-match-p "<parameter name=\"path\">"
                          +carlos/magent-system-directives))
  (should (string-match-p "Do NOT use" +carlos/magent-system-directives))
  (should (string-match-p "<tool_call>'" +carlos/magent-system-directives)))

(ert-deftest myemacs-magent-directives-reasoning-ban ()
  "A diretriz 6 proíbe tool calls dentro de reasoning/thinking blocks,
porque o magent nunca executa reasoning (só parseia DSML do content)."
  (should (string-match-p "NEVER inside reasoning/thinking blocks"
                          +carlos/magent-system-directives))
  (should (string-match-p "Reasoning blocks are never executed"
                          +carlos/magent-system-directives)))

(ert-deftest myemacs-magent-directives-sigpipe ()
  "A diretriz 7 evita `find | head' (SIGPIPE, exit 141) que o magent
reporta como tool FAILED e desestabiliza o modelo local."
  (should (string-match-p "AVOID SIGPIPE" +carlos/magent-system-directives))
  (should (string-match-p "exit 141" +carlos/magent-system-directives))
  (should (string-match-p "head" +carlos/magent-system-directives)))

(ert-deftest myemacs-magent-inject-directives ()
  "O advice +carlos/magent-inject-system-directives preserva o system message
composto e anexa as diretrizes CRITICAL MAGENT TOOL DIRECTIVES."
  (should (fboundp '+carlos/magent-inject-system-directives))
  (let ((out (funcall #'+carlos/magent-inject-system-directives "BASE")))
    (should (string-prefix-p "BASE" out))
    (should (string-match-p "CRITICAL MAGENT TOOL DIRECTIVES" out))
    (should (string-match-p "<tool_calls>" out))))

(ert-deftest myemacs-magent-inject-advice-active ()
  "O advice :filter-return está instalado em
magent-agent--compose-system-message."
  (skip-unless (fboundp 'magent-agent--compose-system-message))
  (should (advice-member-p
           #'+carlos/magent-inject-system-directives
           'magent-agent--compose-system-message)))

(ert-deftest myemacs-magent-composed-system-has-dsml ()
  "O system message composto por magent-agent--compose-system-message
inclui a diretriz DSML após o advice :filter-return."
  (skip-unless (fboundp 'magent-agent--compose-system-message))
  (let* ((out (magent-agent--compose-system-message
               "GLOBAL" "ROLE" "/tmp" nil nil nil)))
    (should (stringp out))
    (should (string-match-p "<tool_calls>" out))
    (should (string-match-p "CRITICAL MAGENT TOOL DIRECTIVES" out))
    (should (string-match-p "Do NOT use '<tool_call>'" out))))

(ert-deftest myemacs-magent-fsm-reasoning-text ()
  "FSM THINK: reasoning chunks ficam invertidos em `:reasoning-chunks'
(push no streaming) e `+carlos/magent--fsm-reasoning-text' reconstrói
a ordem correta."
  (let ((state (make-hash-table :test 'equal)))
    (puthash :reasoning-chunks '("c" "b" "a") state)
    (should (string= "abc"
                     (+carlos/magent--fsm-reasoning-text state)))
    (should (string= ""
                     (+carlos/magent--fsm-reasoning-text
                      (make-hash-table))))))

(ert-deftest myemacs-magent-fsm-claude-xml-params ()
  "FSM DECIDE: parser de parâmetros Claude-XML legado monta plist de args."
  (let ((args (+carlos/magent--fsm-parse-claude-xml-params
               (concat "<parameter=path>~/x.txt</parameter>"
                       "<parameter=reason>teste</parameter>"))))
    (should (plist-get args :path))
    (should (string= "~/x.txt" (plist-get args :path)))
    (should (string= "teste" (plist-get args :reason)))
    (should-not (+carlos/magent--fsm-parse-claude-xml-params
                 "sem parametros aqui"))))

(ert-deftest myemacs-magent-fsm-claude-xml-tool-calls ()
  "FSM DECIDE: parser de tool calls Claude-XML legado produz eventos
normalizados (id, name, args com :source textual-dsml)."
  (skip-unless (fboundp 'magent-llm-tool-call-event))
  (let ((events (+carlos/magent--fsm-parse-claude-xml-tool-calls
                 (concat "<tool_call><function=read_file>"
                         "<parameter=path>AGENTS.md</parameter>"
                         "</function></tool_call>"))))
    (should (= 1 (length events)))
    (let ((ev (car events)))
      (should (string= "read_file" (magent-llm-event-name ev)))
      (should (string= "AGENTS.md"
                       (plist-get (magent-llm-event-arguments ev)
                                  :path)))
      (should (eq 'textual-dsml
                  (plist-get (magent-llm-event-raw ev)
                             :source)))))
  (should-not (+carlos/magent--fsm-parse-claude-xml-tool-calls
               "nenhum tool_call aqui")))

(ert-deftest myemacs-magent-fsm-orchestrate-delegates ()
  "FSM orquestra: quando o content não está vazio (turn normal), o advice
delega para a função original sem intervir."
  (let ((state (make-hash-table :test 'equal))
        (calls 0))
    (cl-letf (((symbol-function 'magent-llm-gptel--pending-tool-use-p)
               (lambda (&rest _) nil)))
      (let ((result (+carlos/magent-fsm-orchestrate-a
                     (lambda (&rest _) (cl-incf calls) 'normal)
                     :request state :info "texto do turn" nil)))
        (should (eq result 'normal))
        (should (= 1 calls))))))

(ert-deftest myemacs-magent-fsm-orchestrate-recover ()
  "FSM DECIDE: content vazio + tool call Claude-XML no reasoning →
  o advice emite os eventos recuperados e devolve tool-call-paused."
  (skip-unless (fboundp 'magent-llm-tool-call-event))
  (let* ((state (make-hash-table :test 'equal))
         (emitted nil))
    (puthash :reasoning-chunks
             (list "</function></tool_call>"
                   "<parameter=path>AGENTS.md</parameter>"
                   "<tool_call><function=read_file>")
             state)
    (cl-letf (((symbol-function 'magent-llm-gptel--pending-tool-use-p)
               (lambda (&rest _) nil))
              ((symbol-function 'magent-llm-gptel--metadata)
               (lambda (&rest _) nil))
              ((symbol-function 'magent-llm-gptel--prepare-textual-continuation)
               (lambda (&rest _) 'continuation))
              ((symbol-function 'magent-llm-gptel--emit-tool-call-batch)
               (lambda (&rest args)
                 (setq emitted (nth 2 args))
                 'batch-end)))
      (let ((result (+carlos/magent-fsm-orchestrate-a
                     (lambda (&rest _) (error "não deve chamar orig"))
                     :request state :info "" nil)))
        (should (eq result 'tool-call-paused))
        (should (= 1 (length emitted)))
        (should (string= "read_file"
                         (magent-llm-event-name (car emitted))))))))

(ert-deftest myemacs-magent-fsm-retry-counter ()
  "FSM RETRY: o contador `:carlos-magent-fsm-retries' limita o número de
re-disparos a `+carlos/magent-fsm-max-retries'."
  (let ((state (make-hash-table :test 'equal)))
    (cl-letf (((symbol-function 'magent-llm-gptel--continue-with-user-message)
               (lambda (&rest _) nil)))
      (should (eq 'completed-paused
                  (+carlos/magent--fsm-retry-empty-turn
                   :request :info state :fsm)))
      (should (eq (gethash :carlos-magent-fsm-retries state)
                  +carlos/magent-fsm-max-retries))
      (should-not (+carlos/magent--fsm-retry-empty-turn
                   :request :info state :fsm)))))

(ert-deftest myemacs-magent-fsm-advice-installed ()
  "O advice da FSM está registrado no choke point
magent-llm-gptel--emit-completed-or-textual-tool-calls."
  (skip-unless (fboundp 'magent-llm-gptel--emit-completed-or-textual-tool-calls))
  (should (advice-member-p
           #'+carlos/magent-fsm-orchestrate-a
           'magent-llm-gptel--emit-completed-or-textual-tool-calls)))

(provide 'magent-test)
;;; magent-test.el ends here
