;;; custom-keybindings.el --- Native keybindings -*- lexical-binding: t; -*-

;;; Commentary:
;; All keybindings using C-c prefix (no Evil mode).
;; Replaces SPC leader from Doom with native Emacs conventions.

;;; Code:

;; ── Window navigation (windmove with Super) ─────────────────────────
(windmove-default-keybindings 'super)

;; ── File and buffer ─────────────────────────────────────────────────
(global-set-key (kbd "C-x C-f") #'find-file)
(global-set-key (kbd "C-x b")   #'consult-buffer)

;; ── Search ──────────────────────────────────────────────────────────
(global-set-key (kbd "C-c s")   #'consult-ripgrep)
(global-set-key (kbd "C-c S")   #'consult-line)

;; ── Git (Magit — Fase 3 placeholder) ───────────────────────────────
;; (global-set-key (kbd "C-c g") #'magit-status)

;; ── AI (gptel — Fase 3 placeholder) ────────────────────────────────
;; (global-set-key (kbd "C-c i p") #'gptel)
;; (global-set-key (kbd "C-c i a") #'+carlos/gptel-agent-run)

;; ── 42 School (Fase 2 placeholder) ─────────────────────────────────
;; (global-set-key (kbd "C-c h") #'stdheader)

;; ── Just (Fase 2 placeholder) ──────────────────────────────────────
;; (global-set-key (kbd "C-c j") #'justl)
;; (global-set-key (kbd "C-c J") #'+carlos/just-check)

;; ── Denote (Fase 3 placeholder) ────────────────────────────────────
;; (global-set-key (kbd "C-c n n") #'denote)
;; (global-set-key (kbd "C-c n d") #'denote-date)
;; (global-set-key (kbd "C-c n r") #'denote-rename-file)

;; ── Zen UI ──────────────────────────────────────────────────────────
(global-set-key (kbd "C-c z")   #'olivetti-mode)

;; ── Terminal ────────────────────────────────────────────────────────
(global-set-key (kbd "C-c t")   #'vterm)
(global-set-key (kbd "C-c e")   #'eshell)

;; ── Eshell ──────────────────────────────────────────────────────────
(global-set-key (kbd "C-c E")   #'eshell)

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
