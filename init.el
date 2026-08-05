;;; init.el --- Main configuration -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Carlos Alberto Filho
;; Author: Carlos Alberto Filho
;; Based on: Emacs Bedrock (https://codeberg.org/ashton314/emacs-bedrock)

;;; Commentary:
;; Modular Emacs configuration built on Emacs Bedrock principles:
;;   - use-package (built-in Emacs 29+)
;;   - Native-first (eglot, treesit, project.el)
;;   - No Evil mode — pure Emacs keybindings
;;
;; Each domain lives in its own file under lisp/custom-*.el.
;; Site-specific packages (42 School) live under site-lisp/.

;;; Code:

;; ── Guardrail ────────────────────────────────────────────────────────
(when (< emacs-major-version 29)
  (error "This config requires Emacs 29+; you have version %s" emacs-major-version))

;; ── Package repositories ────────────────────────────────────────────
(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))
(package-initialize)

;; Refresh package contents on first run
(unless package-archive-contents
  (package-refresh-contents))

;; Ensure use-package is available (built-in on 29+, but ensure :ensure works)
(unless (package-installed-p 'use-package)
  (package-install 'use-package))
(require 'use-package)
(setq use-package-always-ensure t)

;; ── Load paths ──────────────────────────────────────────────────────
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))
(add-to-list 'load-path (expand-file-name "site-lisp" user-emacs-directory))

;; ── Core settings (from Bedrock) ────────────────────────────────────

;; Automatically reread from disk if the underlying file changes
(setopt auto-revert-avoid-polling t)
(setopt auto-revert-interval 5)
(setopt auto-revert-check-vc-info t)
(global-auto-revert-mode)

;; Save history of minibuffer
(savehist-mode)

;; Move through windows with Ctrl-<arrow keys>
(windmove-default-keybindings 'control)

;; Fix archaic defaults
(setopt sentence-end-double-space nil)

;; Right-click context menu (GUI)
(when (display-graphic-p)
  (context-menu-mode))

;; Backup files in a centralized directory
(let ((backup-dir (expand-file-name "backups/" user-emacs-directory)))
  (unless (file-directory-p backup-dir)
    (make-directory backup-dir t))
  (setopt backup-directory-alist `(("." . ,backup-dir))))

;; Interface defaults
(setopt line-number-mode t)
(setopt column-number-mode t)
(setopt switch-to-buffer-obey-display-actions t)
(setopt show-trailing-whitespace nil)
(setopt indicate-buffer-boundaries 'left)
(blink-cursor-mode -1)
(pixel-scroll-precision-mode)
(xterm-mouse-mode 1)

;; Line numbers in prog-mode
(add-hook 'prog-mode-hook 'display-line-numbers-mode)
(setopt display-line-numbers-width 3)

;; Visual line wrapping in text modes
(add-hook 'text-mode-hook 'visual-line-mode)

;; Highlight current line
(let ((hl-line-hooks '(text-mode-hook prog-mode-hook)))
  (mapc (lambda (hook) (add-hook hook 'hl-line-mode)) hl-line-hooks))

;; Tab-bar
(setopt tab-bar-show 1)

;; ── Discovery aid (refined in custom-ui.el) ─────────────────────────
(use-package which-key
  :config
  (which-key-mode))

;; ── Theme (placeholder — ef-themes loaded in custom-ui.el) ──────────
;; (load-theme 'modus-vivendi t) ; replaced by ef-themes

;; ── Modular configuration ───────────────────────────────────────────
(require 'custom-core)
(require 'custom-ui)
(require 'custom-completion)
(require 'custom-files)
(require 'custom-term)
(require 'custom-keybindings)
;; (require 'custom-lang)          ; Fase 2: eglot (go/ts/python/cc), treesit-auto
;; (require 'custom-org)           ; Fase 2: org-babel, jupyter, mermaid, pdf-tools
;; (require 'custom-42)            ; Fase 2: 42 School style, header42, norminette
;; (require 'custom-ai)            ; Fase 3: gptel, gptel-agent
;; (require 'custom-knowledge)     ; Fase 3: denote
;; (require 'custom-git)           ; Fase 3: magit, just-mode

;; ── Custom file (keep M-x customize out of init.el) ─────────────────
(setq custom-file (expand-file-name "custom-file.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))

;; ── Restore GC threshold ────────────────────────────────────────────
(setq gc-cons-threshold (if (boundp 'bedrock--initial-gc-threshold)
                            bedrock--initial-gc-threshold
                          800000))

(provide 'init)
;;; init.el ends here
