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

(provide 'magent-test)
;;; magent-test.el ends here
