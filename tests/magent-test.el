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
  "O sink padrao `magent-log--buffer-sink' grava no buffer *magent-log*
mesmo quando o buffer esta em read-only (modo special-mode)."
  (skip-unless myemacs-magent-available)
  (let ((magent-enable-logging t)
        (sink #'magent-log--buffer-sink))
    ;; Sink padrao registrado?
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

(ert-deftest myemacs-magent-no-custom-fsm-advice ()
  "A FSM customizada de orquestração foi removida; proíbe advice no choke point."
  (skip-unless (fboundp 'magent-llm-gptel--emit-completed-or-textual-tool-calls))
  (should-not (advice-member-p
               '+carlos/magent-fsm-orchestrate-a
               'magent-llm-gptel--emit-completed-or-textual-tool-calls)))

(ert-deftest myemacs-magent-sanitize-parse-response-arity ()
  "Garante que `magent-llm-gptel--sanitize-after-parse-response-a' aceite
5 ou mais argumentos sem estourar Wrong number of arguments no Gemini streaming."
  (require 'custom-magent nil t)
  (skip-unless (fboundp 'magent-llm-gptel--sanitize-after-parse-response-a))
  (let ((called nil))
    (cl-letf (((symbol-function 'magent-llm-gptel--managed-info-p) (lambda (&rest _) nil)))
      (magent-llm-gptel--sanitize-after-parse-response-a
       (lambda (&rest args) (setq called args))
       'fake-backend 'fake-response 'fake-info 'include 'extra-arg)
      (should (= 5 (length called))))))

(ert-deftest myemacs-magent-wait-agent-schema-valid ()
  "A tool `wait_agent' expõe `job_ids' (`:type array') com `:items',
senão o backend Gemini rejeita o function_declarations com
\"properties[job_ids].items: missing field\" e toda requisição falha."
  (skip-unless (and myemacs-magent-available
                    (boundp 'magent-tools--wait-agent-tool)
                    (fboundp 'gptel-tool-args)))
  (let* ((tool magent-tools--wait-agent-tool)
         (job-ids-arg (cl-find "job_ids" (gptel-tool-args tool)
                               :key (lambda (arg) (plist-get arg :name))
                               :test #'equal)))
    (should (plist-member job-ids-arg :items))
    (should (equal (plist-get job-ids-arg :items) '(:type "string")))))

(ert-deftest myemacs-magent-sanitize-tool-use-symbol-to-string ()
  "A sanitização de info do gptel deve converter símbolos de nomes de ferramenta
(ex.: 'read_file do gptel-gemini) em strings (\"read_file\"), permitindo a busca
correta de tool-spec por `equal'."
  (skip-unless (fboundp 'magent-llm-gptel--sanitize-info))
  (let ((info (list :tool-use (list (list :name 'read_file :args '(:path "test.el"))))))
    (magent-llm-gptel--sanitize-info info)
    (let ((name (plist-get (car (plist-get info :tool-use)) :name)))
      (should (stringp name))
      (should (equal name "read_file")))))

;; ── Sub-item 1: Orquestrador mais agressivo (2026-08-17) ─────────────

(ert-deftest myemacs-magent-directives-spawn-and-forge ()
  "Garante que as directives contêm o padrão SPAWN-AND-FORGE."
  (should (boundp '+carlos/magent-system-directives))
  (should (string-match-p "SPAWN-AND-FORGE" +carlos/magent-system-directives))
  (should (string-match-p "spawn MULTIPLE agents BEFORE waiting"
                          +carlos/magent-system-directives)))

(ert-deftest myemacs-magent-directives-synthesis-rule ()
  "Garante que as directives contêm a regra de síntese (≤3 bullets)."
  (should (boundp '+carlos/magent-system-directives))
  (should (string-match-p "SYNTHESIS FORMAT" +carlos/magent-system-directives))
  (should (string-match-p "≤3 bullet points" +carlos/magent-system-directives)))

(provide 'magent-test)
;;; magent-test.el ends here
