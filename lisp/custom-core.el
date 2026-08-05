;;; custom-core.el --- Core editor settings -*- lexical-binding: t; -*-

;;; Commentary:
;; Fundamentos: fontes, GPG, SSH, editor basics, display-line-numbers,
;; truncate-lines, xterm-mouse, auto-revert refinements.

;;; Code:

;; ── Fonts ───────────────────────────────────────────────────────────
(set-face-attribute 'default nil
                    :family "JetBrainsMono Nerd Font"
                    :height 130)
(set-face-attribute 'fixed-pitch nil
                    :family "JetBrainsMono Nerd Font"
                    :height 130)
(set-face-attribute 'variable-pitch nil
                    :family "JetBrainsMono Nerd Font"
                    :height 140)

;; Fallback para símbolos unicode
(when (member "Symbola" (font-family-list))
  (set-fontset-font t 'unicode "Symbola" nil 'prepend))

;; ── Editor defaults ─────────────────────────────────────────────────
(setq-default truncate-lines t)
(setq-default indent-tabs-mode nil)
(setq-default tab-width 4)
(setq delete-by-moving-to-trash t)

;; Kill ring
(setq kill-ring-max 200)

;; Yes/no → y/n
(fset 'yes-or-no-p 'y-or-n-p)

;; ── Auto-revert refinements ─────────────────────────────────────────
(setopt auto-revert-use-notify t)

;; ── GPG / EPA ───────────────────────────────────────────────────────
(require 'epa-file)
(epa-file-enable)
(setq epa-pinentry-mode 'loopback)

;; ── Xterm mouse (tty) ───────────────────────────────────────────────
(when (not (display-graphic-p))
  (xterm-mouse-mode 1))

;; ── Display line numbers ────────────────────────────────────────────
(global-display-line-numbers-mode 1)
(setq display-line-numbers-type 'relative)
(setq display-line-numbers-width 3)

;; ── Save place (remember cursor position per file) ──────────────────
(save-place-mode 1)

;; ── Recent files ────────────────────────────────────────────────────
(recentf-mode 1)
(setq recentf-max-menu-items 50
      recentf-max-saved-items 50)

;; ── Server mode (emacsclient) ───────────────────────────────────────
(require 'server)
(unless (server-running-p)
  (server-start))

(provide 'custom-core)
;;; custom-core.el ends here
