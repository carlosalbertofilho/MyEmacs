;;; custom-dashboard.el --- Dashboard Configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Configuração do dashboard.el com visual refinado, ícones e fontes.

;;; Code:

;; Forward declarations for byte-compiler
(declare-function dashboard-setup-startup-hook "dashboard")
(declare-function dashboard-open "dashboard")
(declare-function dashboard-refresh-buffer "dashboard")

(use-package dashboard
  :ensure t
  :demand t
  :config
  (dashboard-setup-startup-hook)
  (setq dashboard-banner-logo-title "My Emacs")
  (setq dashboard-startup-banner (expand-file-name "banner.txt" user-emacs-directory))
  (setq dashboard-center-content t)
  (setq dashboard-show-shortcuts nil)
  (setq dashboard-items '((recents  . 5)
                          (projects . 5)))
  (setq dashboard-set-heading-icons t)
  (setq dashboard-set-file-icons t)
  (setq dashboard-display-icons-p t)
  (setq dashboard-icon-type 'nerd-icons)
  
  (custom-set-faces
   '(dashboard-heading ((t (:family "Space Grotesk" :weight bold :height 1.2))))
   '(dashboard-items-face ((t (:family "Inter" :weight normal))))))

;;;###autoload
(defun +carlos/dashboard-setup-startup-hook ()
  "Setup dashboard startup hook."
  (dashboard-setup-startup-hook))

(defun +carlos/dashboard-open ()
  "Open (or refresh) the *dashboard* buffer."
  (interactive)
  (dashboard-open))

(defun +carlos/dashboard-refresh ()
  "Regenerate the *dashboard* buffer contents."
  (interactive)
  (dashboard-refresh-buffer))

(provide 'custom-dashboard)
;;; custom-dashboard.el ends here
