;;; custom-files.el --- File management and remote -*- lexical-binding: t; -*-

;;; Commentary:
;; dirvish com todas as extensões nativas, ibuffer, TRAMP optimization.

;;; Code:

;; ── dired base ──────────────────────────────────────────────────────
(setq dired-listing-switches "-alh --group-directories-first"
      dired-dwim-target t)

;; ── nerd-icons (ícones para dirvish, dashboard, etc) ───────────────
(use-package nerd-icons
  :ensure t
  :config
  ;; Instala ícones na primeira execução se necessário
  (unless (file-directory-p (expand-file-name "nerd-icons/fonts" user-emacs-directory))
    (nerd-icons-install-fonts t)))

;; ── dirvish core ────────────────────────────────────────────────────
(use-package dirvish
  :ensure t
  :after nerd-icons
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
  (dirvish-nerd-icons-height 16)
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
