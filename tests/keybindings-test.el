;;; keybindings-test.el --- Keybinding regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifica os binds globais (C-c prefix) e que os comandos referenciados
;; existem (pega void-function latente, ex. +carlos/dashboard-open).

;;; Code:

(require 'ert)

(ert-deftest myemacs-kbd-ai-gptel ()
  (should (eq (key-binding (kbd "C-c i")) 'gptel)))

(ert-deftest myemacs-kbd-ai-agent ()
  (should (eq (key-binding (kbd "C-c I")) '+carlos/gptel-agent-run))
  (should (commandp '+carlos/gptel-agent-run)))

(ert-deftest myemacs-kbd-ai-commit-global ()
  (should (eq (key-binding (kbd "C-c C-g")) '+carlos/gptel-generate-commit-message))
  (should (commandp '+carlos/gptel-generate-commit-message)))

(ert-deftest myemacs-kbd-git-magit ()
  (should (eq (key-binding (kbd "C-c g")) 'magit-status)))

(ert-deftest myemacs-kbd-stdheader-42 ()
  (should (eq (key-binding (kbd "C-c h")) 'stdheader)))

(ert-deftest myemacs-kbd-history-consult ()
  (should (eq (key-binding (kbd "C-c /")) 'consult-history)))

(ert-deftest myemacs-kbd-imenu-consult ()
  (should (eq (key-binding (kbd "M-s i")) 'consult-imenu))
  (should (eq (key-binding (kbd "C-c i")) 'gptel)))

(ert-deftest myemacs-kbd-just ()
  (should (eq (key-binding (kbd "C-c j")) 'justl)))

(ert-deftest myemacs-kbd-denote ()
  (should (eq (key-binding (kbd "C-c n n")) 'denote)))

(ert-deftest myemacs-kbd-dashboard-commands-exist ()
  (should (commandp '+carlos/dashboard-open))
  (should (commandp '+carlos/dashboard-refresh)))

(ert-deftest myemacs-kbd-dashboard-binds ()
  (should (eq (key-binding (kbd "C-c d d")) '+carlos/dashboard-open))
  (should (eq (key-binding (kbd "C-c d r")) '+carlos/dashboard-refresh)))

(ert-deftest myemacs-kbd-zen ()
  (should (eq (key-binding (kbd "C-c z")) 'olivetti-mode)))

(ert-deftest myemacs-kbd-terminal ()
  (should (eq (key-binding (kbd "C-c t")) 'vterm)))

(ert-deftest myemacs-kbd-consult-defaults ()
  (should (eq (key-binding (kbd "C-x b")) 'consult-buffer))
  (should (eq (key-binding (kbd "C-c s")) 'consult-ripgrep))
  (should (eq (key-binding (kbd "C-c S")) 'consult-line)))

(provide 'keybindings-test)
;;; keybindings-test.el ends here
