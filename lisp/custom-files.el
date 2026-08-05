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
  (dirvish-quick-access-entries
   '(("h" "~/"                    "Home")
     ("d" "~/Downloads/"          "Downloads")
     ("p" "~/Projects/"           "Projects")
     ("c" "~/.config/"            "Config")
     ("n" "~/org/notes"           "Notes")
     ("e" "~/.config/emacs-vanilla/" "Emacs")))
  :config
  ;; Core settings
  (setq dirvish-attributes
        '(nerd-icons vc-state git-msg collapse)
        dirvish-side-width 30
        dirvish-large-directory-threshold 1000
        dirvish-hide-cursor t
        dirvish-use-mode-line nil
        dirvish-nerd-icons-height 16     ; was 12 (too small, causes giant icons)
        dirvish-nerd-icons-offset -2
        dirvish-side-auto-expand t
        dirvish-side-open-file-action 'select
        dirvish-subtree-always-show-state nil
        dirvish-subtree-state-style "arrow"
        dirvish-subtree-icon-scale-factor 1.0)

  ;; Preview in minibuffer
  (dirvish-peek-mode 1)
  (setq dirvish-peek-key 'any)

  ;; VC preview dispatchers (must be at beginning for priority)
  (setq dirvish-preview-dispatchers '(vc-log vc-diff vc-blame))

  ;; Hooks
  (add-hook 'dirvish-mode-hook (lambda () (setq truncate-lines t)))
  (add-hook 'dirvish-mode-hook (lambda () (dired-hide-details-mode 1))))

;; ── dirvish extensions (all consolidated in dirvish :config above) ──
;; dirvish-yank:    Multi-stage copy/paste (async)
;; dirvish-rsync:   Integration with rsync
;; dirvish-emerge:  Group files by filter criteria
;; dirvish-peek:    Preview in minibuffer (enabled in :config)
;; dirvish-vc:      Version control integration (enabled in :config)
;; dirvish-icons:   File icons via nerd-icons (enabled in :config)
;; dirvish-side:    Toggle sidebar
;; dirvish-ls:      LS switches menu
;; dirvish-subtree: Tree browser (enabled in :config)
;; dirvish-history: History navigation
;; dirvish-quick-access: Quick keys for places (enabled in :config)
;; dirvish-collapse: Collapse unique nested paths
;; dirvish-narrow:  Live filtering

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
      tramp-use-ssh-controlmaster-options t)

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
