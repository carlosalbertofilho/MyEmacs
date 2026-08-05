;;; custom-files.el --- File management and remote -*- lexical-binding: t; -*-

;;; Commentary:
;; dirvish com todas as extensões nativas, ibuffer, TRAMP optimization.

;;; Code:

;; ── dired base ──────────────────────────────────────────────────────
(let ((args (list "-ahl" "-v" "--group-directories-first")))
  (when (featurep :system 'bsd)
    (if-let* ((gls (executable-find "gls")))
        (setq insert-directory-program gls)
      (setq args (list (car args)))))
  (setq dired-listing-switches (string-join args " ")
        dired-dwim-target t))

(add-hook 'dired-mode-hook
          (lambda ()
            (when (file-remote-p default-directory)
              (setq-local dired-actual-switches "-ahl"))))

;; ── nerd-icons (ícones para dirvish, dashboard, etc) ───────────────
(use-package nerd-icons
  :ensure t
  :demand t
  :config
  ;; Instala ícones na primeira execução se necessário
  (unless (file-directory-p (expand-file-name "nerd-icons/fonts" user-emacs-directory))
    (nerd-icons-install-fonts t)))

;; ── dirvish core ────────────────────────────────────────────────────
(use-package dirvish
  :ensure t
  :init
  (dirvish-override-dired-mode 1)
  :custom
  ;; Quick-access entries (2-keystroke jumps)
  (dirvish-quick-access-entries
   '(("h" "~/"                    "Home")
     ("d" "~/Downloads/"          "Downloads")
     ("p" "~/Projects/"           "Projects")
     ("c" "~/.config/"            "Config")
     ("n" "~/org/notes"           "Notes")
     ("e" "~/.config/emacs-vanilla/" "Emacs")))
  ;; Visual attributes (order matters for rendering)
  (dirvish-attributes
   '(vc-state subtree-state nerd-icons collapse git-msg file-time file-size))
  ;; Icon settings
  (dirvish-nerd-icons-height 0.85)
  (dirvish-nerd-icons-offset -2)
  ;; Window / layout
  (dirvish-side-width 30)
  (dirvish-large-directory-threshold 20000)
  (dirvish-hide-cursor t)
  (dirvish-use-mode-line nil)
  ;; Subtree
  (dirvish-subtree-always-show-state nil)
  (dirvish-subtree-state-style "arrow")
  (dirvish-subtree-icon-scale-factor 1.0)
  (dirvish-side-auto-expand t)
  (dirvish-side-open-file-action 'select)
  (dirvish-reuse-session 'open)
  ;; Sidebar specific visual settings (evita truncamento de linhas)
  (dirvish-side-attributes '(vc-state nerd-icons collapse subtree-state))
  (dirvish-side-header-line-format '(:left (project)))
  (dirvish-side-mode-line-format nil)
  ;; Preview dispatchers (correct values: file types, NOT vc commands)
  (dirvish-preview-dispatchers
   '(image gif video audio epub pdf archive))
  :bind
  (:map dirvish-mode-map
   (";"   . dired-up-directory)
   ("?"   . dirvish-dispatch)
   ("TAB" . dirvish-subtree-toggle)
   ("o"   . dirvish-quick-access)
   ("r"   . dirvish-history-jump)
   ("s"   . dirvish-quicksort)
   ("v"   . dirvish-vc-menu)
   ("N"   . dirvish-narrow))
  :config
  ;; Hooks
  (add-hook 'dirvish-mode-hook (lambda () (setq truncate-lines t)))
  (add-hook 'dirvish-mode-hook (lambda () (dired-hide-details-mode 1))))

;; ── diredfl (syntax highlighting para dired/dirvish) ─────────────────
(use-package diredfl
  :ensure t
  :hook ((dired-mode dirvish-directory-view-mode) . diredfl-mode))

;; ── ibuffer (built-in) ──────────────────────────────────────────────
(use-package ibuffer
  :ensure nil
  :bind
  (("C-x C-b" . ibuffer))
  :config
  (setq ibuffer-sorting-mode 'alphabetic
        ibuffer-expert t))

;; ── TRAMP optimization ──────────────────────────────────────────────
(setq tramp-default-method "ssh"
      tramp-ssh-controlmaster-options
      "-o ControlMaster=auto -o ControlPath='~/.ssh/controlmasters/%r@%h:%p' -o ControlPersist=600"
      tramp-use-connection-share t)

;; Ensure controlmasters directory exists
(let ((cm-dir (expand-file-name "~/.ssh/controlmasters")))
  (unless (file-directory-p cm-dir)
    (make-directory cm-dir t)))

;; ── Project (built-in) ──────────────────────────────────────────────
(use-package project
  :ensure nil
  :config
  (setq project-switch-commands
        '((?f project-find-file "Find file")
          (?g project-find-regexp "Find regexp")
          (?d project-dired "Dired")
          (?e project-eshell "Eshell")
          (?c project-compile "Compile")
          (?j +carlos/project-just-run "Just (default)")
          (?t +carlos/eat-just-recipe "Just recipe"))))

(provide 'custom-files)
;;; custom-files.el ends here
