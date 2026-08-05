;;; custom-files.el --- File management and remote -*- lexical-binding: t; -*-

;;; Commentary:
;; dirvish (dired replacement), ibuffer, TRAMP optimization.

;;; Code:

;; ── dired base ──────────────────────────────────────────────────────
(setq dired-listing-switches "-alh --group-directories-first"
      dired-dwim-target t)

;; ── dirvish ─────────────────────────────────────────────────────────
(use-package dirvish
  :config
  (dirvish-override-dired-mode 1)
  (setq dirvish-attributes '(vc-state nerd-icons collapse)
        dirvish-side-width 30
        dirvish-window-size 0.5))

;; ── ibuffer ─────────────────────────────────────────────────────────
(use-package ibuffer
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

;; ── Project ─────────────────────────────────────────────────────────
(use-package project
  :config
  (setq project-switch-commands
        '((project-find-file "Find file")
          (project-find-regexp "Find regexp")
          (project-dired "Dired")
          (project-eshell "Eshell")
          (project-compile "Compile"))))

(provide 'custom-files)
;;; custom-files.el ends here
