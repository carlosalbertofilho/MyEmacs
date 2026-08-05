;;; custom-keybindings.el --- Native keybindings -*- lexical-binding: t; -*-

;;; Commentary:
;; All keybindings using C-c prefix (no Evil mode).
;; Replaces SPC leader from Doom with native Emacs conventions.

;;; Code:

;; Forward declarations for byte-compiler
(declare-function magit-status "magit")
(declare-function gptel "gptel")
(declare-function justl "justl")
(declare-function justl-compile "justl")
(declare-function denote "denote")
(declare-function denote-date "denote")
(declare-function denote-rename-file "denote")
(declare-function denote-backlinks "denote")
(declare-function denote-link "denote")
(declare-function denote-link-dired "denote")
(declare-function olivetti-mode "olivetti")
(declare-function dirvish-side "dirvish")

;; ── Window navigation (windmove with Super) ─────────────────────────
(windmove-default-keybindings 'super)

;; ── File and buffer ─────────────────────────────────────────────────
(global-set-key (kbd "C-x C-f") #'find-file)
(global-set-key (kbd "C-x b")   #'consult-buffer)
(global-set-key (kbd "C-c f")   #'dirvish-side)

;; ── Search ──────────────────────────────────────────────────────────
(global-set-key (kbd "C-c s")   #'consult-ripgrep)
(global-set-key (kbd "C-c S")   #'consult-line)

;; ── Git (Magit) ─────────────────────────────────────────────────────
(global-set-key (kbd "C-c g")   #'magit-status)

;; ── AI (gptel) ──────────────────────────────────────────────────────
(global-set-key (kbd "C-c i")   #'gptel)
(global-set-key (kbd "C-c I")   #'+carlos/gptel-agent-run)

;; ── 42 School ───────────────────────────────────────────────────────
(global-set-key (kbd "C-c h")   #'stdheader)

;; ── Just ────────────────────────────────────────────────────────────
(global-set-key (kbd "C-c j")   #'justl)
(global-set-key (kbd "C-c J")   #'justl-compile)

;; ── Denote ──────────────────────────────────────────────────────────
(global-set-key (kbd "C-c n n") #'denote)
(global-set-key (kbd "C-c n d") #'denote-date)
(global-set-key (kbd "C-c n r") #'denote-rename-file)
(global-set-key (kbd "C-c n b") #'denote-backlinks)
(global-set-key (kbd "C-c n l") #'denote-link)
(global-set-key (kbd "C-c n L") #'denote-link-dired)
(global-set-key (kbd "C-c n s") #'+carlos/denote-silo-new)

;; ── Zen UI ──────────────────────────────────────────────────────────
(global-set-key (kbd "C-c z")   #'olivetti-mode)

;; ── Terminal ────────────────────────────────────────────────────────
(global-set-key (kbd "C-c t")   #'vterm)
;; eshell bound in custom-term.el (C-c e)

;; ── Tab bar ─────────────────────────────────────────────────────────
(global-set-key (kbd "C-c TAB") #'tab-bar-mode)

;; ── Useful defaults ─────────────────────────────────────────────────
(global-set-key (kbd "M-o")     #'other-window)
(global-set-key (kbd "C-x k")   #'kill-current-buffer)

;; ── Dashboard ───────────────────────────────────────────────────────
(global-set-key (kbd "C-c d d") #'+carlos/dashboard-open)
(global-set-key (kbd "C-c d r") #'+carlos/dashboard-refresh)

(provide 'custom-keybindings)
;;; custom-keybindings.el ends here
