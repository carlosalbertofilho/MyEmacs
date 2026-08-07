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

(ert-deftest myemacs-kbd-magent ()
  (should (eq (key-binding (kbd "C-c A m")) '+carlos/magent-start))
  (should (eq (key-binding (kbd "C-c A i")) '+carlos/magent-agent-shell-interrupt))
  (should (eq (key-binding (kbd "C-c A r")) '+carlos/magent-agent-shell-prompt-region)))

(ert-deftest myemacs-kbd-local-ai ()
  (should (eq (key-binding (kbd "C-c c d")) '+carlos/generate-docstring-at-point))
  (should (eq (key-binding (kbd "C-c c t")) '+carlos/generate-test-at-point)))

(ert-deftest myemacs-kbd-cli-ai ()
  (should (eq (key-binding (kbd "C-c A g")) '+carlos/agy-prompt))
  (should (eq (key-binding (kbd "C-c A c")) '+carlos/copilot-explain-region))
  (should (eq (key-binding (kbd "C-c A f")) '+carlos/gptel-emergency-fallback)))

(ert-deftest myemacs-kbd-eshell ()
  (should (eq (key-binding (kbd "C-c e")) 'eshell)))

(ert-deftest myemacs-kbd-no-collisions ()
  "Verifica colisões e integridade de atalhos críticos em diferentes major modes do Emacs."
  (let ((critical-bindings
         '(("C-c g" . magit-status)
           ("C-c i" . gptel)
           ("C-c I" . +carlos/gptel-agent-run)
           ("C-c A m" . +carlos/magent-start)
           ("C-c A i" . +carlos/magent-agent-shell-interrupt)
           ("C-c A r" . +carlos/magent-agent-shell-prompt-region)
           ("C-c A g" . +carlos/agy-prompt)
           ("C-c A c" . +carlos/copilot-explain-region)
           ("C-c A f" . +carlos/gptel-emergency-fallback)
           ("C-c h" . stdheader)
           ("C-c j" . justl)
           ("C-c n n" . denote)
           ("C-c z" . olivetti-mode)
           ("C-c t" . vterm)
           ("C-c e" . eshell)
           ("C-c d d" . +carlos/dashboard-open)
           ("C-c c d" . +carlos/generate-docstring-at-point)
           ("C-c c t" . +carlos/generate-test-at-point)
           ("M-o" . other-window)
           ("C-x k" . kill-current-buffer))))
    
    (dolist (binding critical-bindings)
      (let ((key (car binding))
            (cmd (cdr binding)))
        ;; 1. Garantir que o comando referenciado é interativo e válido
        (should (commandp cmd))
        ;; 2. Validar que o comando está associado ao atalho no escopo global
        (should (eq (key-binding (kbd key)) cmd))))

    ;; 3. Validar ausência de colisão nos principais Major Modes
    (dolist (mode '(org-mode dired-mode c-mode emacs-lisp-mode))
      (let ((buf (generate-new-buffer (format "*temp-kbd-test-%s*" mode))))
        (unwind-protect
            (with-current-buffer buf
              (when (fboundp mode)
                ;; Ativa o modo principal temporariamente no buffer de teste
                (funcall mode)
                (dolist (binding critical-bindings)
                  (let ((key (car binding))
                        (cmd (cdr binding)))
                    ;; Garante que o major-mode local não interceptou/sobrescreveu nosso atalho global
                    (should (eq (key-binding (kbd key)) cmd))))))
          (kill-buffer buf))))))

(provide 'keybindings-test)
;;; keybindings-test.el ends here
