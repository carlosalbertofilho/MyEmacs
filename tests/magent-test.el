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
e, quando chamado, o buffer *magent-log* recebe a linha."
  (skip-unless myemacs-magent-available)
  (let ((sink #'+carlos/magent-log-sink))
    ;; Sink registrado?
    (should (memq sink magent-log--sinks))
    ;; Sink grava no buffer *magent-log*?
    (with-current-buffer (get-buffer-create "*magent-log*")
      (let ((start (point-max)))
        (funcall sink "teste-sink" 'info)
        (goto-char (point-max))
        (should (search-backward "teste-sink" start t))))))

(provide 'magent-test)
;;; magent-test.el ends here
