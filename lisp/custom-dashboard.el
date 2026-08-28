;;; custom-dashboard.el --- Dashboard Configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Configuração do dashboard.el com visual refinado, ícones e fontes.

;;; Code:

(declare-function elpaca "elpaca")
(declare-function elpaca-wait "elpaca")

;; Ensure dashboard package is queued and loaded synchronously via Elpaca
(elpaca dashboard)
(elpaca-wait)

(use-package dashboard
  :ensure nil
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
  (setq initial-buffer-choice (lambda () (get-buffer-create "*dashboard*")))
  
  (custom-set-faces
   '(dashboard-heading ((t (:family "Space Grotesk" :weight bold :height 1.2))))
   '(dashboard-items-face ((t (:family "Inter" :weight normal))))))

;; Ensure new server/daemon frames (emacsclient -c) open the dashboard when no file is passed
(defun +carlos/dashboard-open-on-server-frame (&optional frame)
  "Ensure *dashboard* buffer is displayed on new server FRAME safely."
  (let ((frame (or frame (selected-frame))))
    (when (and (frame-live-p frame)
               (display-graphic-p frame))
      (with-selected-frame frame
        (with-demoted-errors "Dashboard server frame error: %S"
          (when (or (equal (buffer-name) "*scratch*")
                    (string-prefix-p "*scratch*" (buffer-name)))
            (dashboard-open)))))))

(add-hook 'server-after-make-frame-hook #'+carlos/dashboard-open-on-server-frame)

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
