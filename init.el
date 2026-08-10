;;; init.el --- Main configuration -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Carlos Alberto Filho
;; Author: Carlos Alberto Filho
;; Based on: Emacs Bedrock (https://codeberg.org/ashton314/emacs-bedrock)

;;; Commentary:
;; Modular Emacs configuration built on Emacs Bedrock principles:
;;   - Elpaca package manager (git-based, async, native-comp)
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

;; ── Elpaca: Git-based package manager (replaces package.el + MELPA) ─
;; Installs packages directly from upstream git repositories.
;; Async, parallel, native-compilation on install, lock file for reproducibility.
(defvar elpaca-installer-version 0.12)
(defvar elpaca-directory (expand-file-name "elpaca/" user-emacs-directory))
(defvar elpaca-builds-directory (expand-file-name "builds/" elpaca-directory))
(defvar elpaca-sources-directory (expand-file-name "sources/" elpaca-directory))
(defvar elpaca-order '(elpaca :repo "https://github.com/progfolio/elpaca.git"
                              :ref nil :depth 1 :inherit ignore
                              :files (:defaults "elpaca-test.el" (:exclude "extensions"))
                              :build (:not elpaca-activate)))

(let* ((repo  (expand-file-name "elpaca/" elpaca-sources-directory))
       (build (expand-file-name "elpaca/" elpaca-builds-directory))
       (order (cdr elpaca-order))
       (default-directory repo))
  (add-to-list 'load-path (if (file-exists-p build) build repo))
  (unless (file-exists-p repo)
    (make-directory repo t)
    (call-process "git" nil nil nil "clone"
                  "--depth" "1" "--single-branch"
                  "https://github.com/progfolio/elpaca.git" repo))
  (unless (file-exists-p build)
    (with-current-buffer (get-buffer-create "*elpaca-bootstrap*")
      (let ((standard-output (current-buffer)))
        (call-process "git" nil t nil "-C" repo "fetch" "--depth" "1" "origin" "master")
        (call-process "git" nil t nil "-C" repo "checkout" "FETCH_HEAD")
        (call-process "git" nil t nil "-C" repo "submodule" "update" "--init" "--recursive" "--depth" "1")
        (call-process "emacs" nil t nil "--batch" "-L" "." "-l" "elpaca.el"
                      "--eval" "(elpaca-generate-autoloads \"elpaca\" default-directory)")))))

(unless (require 'elpaca-autoloads nil t)
  (require 'elpaca)
  (elpaca-generate-autoloads "elpaca" (expand-file-name "elpaca/" elpaca-sources-directory)))

(add-hook 'after-init-hook #'elpaca-process-queues)
(elpaca `(,@elpaca-order))

;; Elpaca + use-package integration
(elpaca elpaca-use-package
  (elpaca-use-package-mode))
(elpaca-wait)  ;; Block until elpaca-use-package is installed

;; Ensure compat is managed by Elpaca and loaded early to avoid version conflict warnings
(use-package compat :ensure t)
(elpaca-wait)

;; use-package defaults (Elpaca handles :ensure automatically)
(setq use-package-always-defer t
      use-package-expand-minimally t)

;; Ensure transient is installed and activated early.
;; magit, gptel e dirvish dependem de transient; sem isso, o `:demand t'
;; do custom-git pode carregá-lo antes da ativação da Elpaca
;; (warning "transient loaded before Elpaca activation").
(use-package transient :ensure t)
(elpaca-wait)

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

;; Centralize backups and auto-saves in /tmp to prevent pollution in working directories
(let ((backup-dir "/tmp/emacs-backups/")
      (autosave-dir "/tmp/emacs-autosaves/"))
  (unless (file-directory-p backup-dir)
    (make-directory backup-dir t))
  (unless (file-directory-p autosave-dir)
    (make-directory autosave-dir t))
  (setq backup-directory-alist `(("." . ,backup-dir)))
  (setq auto-save-file-name-transforms `((".*" ,autosave-dir t)))
  (setq create-lockfiles nil))

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

;; ── Discovery aid (loaded in custom-ui.el) ─────────────────────────
;; which-key configured in custom-ui.el with proper settings

;; ── Theme (placeholder — ef-themes loaded in custom-ui.el) ──────────
;; (load-theme 'modus-vivendi t) ; replaced by ef-themes

;; ── Modular configuration ───────────────────────────────────────────
(require 'custom-core)
(require 'custom-ui)
(require 'custom-writing)
(require 'custom-completion)
(require 'custom-files)
(require 'custom-term)
(require 'custom-keybindings)
(require 'custom-lang)
(require 'custom-markdown)
(require 'custom-org)
(require 'custom-42)
(require 'custom-ai)
(require 'custom-dev)
(require 'custom-jinx)
(require 'custom-magent)
(require 'custom-knowledge)
(require 'custom-git)
(require 'custom-dashboard)

;; ── Dashboard startup hook ──────────────────────────────────────────
;; (O próprio custom-dashboard agora ativa o hook no :config de forma segura)

;; ── Custom file (keep M-x customize out of init.el) ─────────────────
(setq custom-file (expand-file-name "custom-file.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))

;; ── Restore GC threshold ────────────────────────────────────────────
(setq gc-cons-threshold (if (boundp 'bedrock--initial-gc-threshold)
                            bedrock--initial-gc-threshold
                          800000))

;; Wait for all Elpaca packages to finish installing before completing initialization
;; (prevents async load/require errors on cold startup)
(elpaca-wait)

(provide 'init)
;;; init.el ends here
