;;; custom-lang.el --- Languages and LSP -*- lexical-binding: t; -*-

;;; Commentary:
;; eglot (LSP), treesit-auto, linguagens: Go, TypeScript/React, Python, C/C++.
;; Formatters: ruff (Python), etc.

;;; Code:

;; ── treesit-auto ────────────────────────────────────────────────────
(use-package treesit-auto
  :config
  (global-treesit-auto-mode 1))

;; ── eglot (built-in Emacs 29+) ──────────────────────────────────────
;; NOTE: Avoid `prog-mode' hook — eglot-ensure on ALL prog modes causes slowdown.
;; Use per-mode hooks instead (see language sections below).
(use-package eglot
  :config
  ;; Ignorar formatação do servidor para C/C++ (Norma 42 controla)
  (add-to-list 'eglot-ignored-server-capabilities :documentFormattingProvider)
  (add-to-list 'eglot-ignored-server-capabilities :documentRangeFormattingProvider))

;; ── Go ──────────────────────────────────────────────────────────────
(use-package go-ts-mode
  :ensure nil
  :mode ("\\.go\\'" . go-ts-mode)
  :hook (go-ts-mode . eglot-ensure))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(go-ts-mode go-mode . ("gopls"))))

;; ── TypeScript / React ──────────────────────────────────────────────
(use-package typescript-ts-mode
  :ensure nil
  :mode (("\\.ts\\'"  . typescript-ts-mode)
         ("\\.tsx\\'" . tsx-ts-mode))
  :hook ((typescript-ts-mode tsx-ts-mode) . eglot-ensure))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '((typescript-ts-mode tsx-ts-mode typescript-mode) .
                 ("typescript-language-server" "--stdio"))))

;; ── Python ──────────────────────────────────────────────────────────
(use-package python
  :ensure nil
  :mode (("\\.py\\'" . python-ts-mode))
  :hook (python-ts-mode . eglot-ensure)
  :config
  (setq python-shell-interpreter "ipython"
        python-shell-interpreter-args "-i --simple-prompt --no-color-info"))

(with-eval-after-load 'eglot
  ;; basedpyright como servidor principal
  (add-to-list 'eglot-server-programs
               '(python-ts-mode python-mode . ("basedpyright" "--stdio")))
  ;; ruff como add-on para linting/format
  (add-to-list 'eglot-server-programs
               '((python-ts-mode python-mode) . ("ruff" "server"))))

;; ── C / C++ (42 School) ─────────────────────────────────────────────
;; clangd is detected automatically by eglot.
;; Formatting is ignored (see eglot-ignored-server-capabilities above).
;; NOTE: No eglot-ensure hook — 42 School uses flycheck-norminette instead.

;; ── Elisp ───────────────────────────────────────────────────────────
(use-package emacs-lisp-mode
  :ensure nil
  :hook (emacs-lisp-mode . eglot-ensure))

;; ── Shell / Bash ────────────────────────────────────────────────────
(use-package sh-script
  :ensure nil
  :mode (("\\.sh\\'" . sh-mode)
         ("\\.bash\\'" . sh-mode)))

;; ── JSON ────────────────────────────────────────────────────────────
(use-package json-ts-mode
  :ensure nil
  :mode ("\\.json\\'" . json-ts-mode))

;; ── YAML ────────────────────────────────────────────────────────────
(use-package yaml-mode
  :mode ("\\.ya?ml\\'" . yaml-mode))

;; ── Markdown ────────────────────────────────────────────────────────
(use-package markdown-ts-mode
  :ensure nil
  :mode ("\\.md\\'" . markdown-ts-mode))

;; ── Nix ─────────────────────────────────────────────────────────────
(use-package nix-ts-mode
  :ensure nil
  :mode ("\\.nix\\'" . nix-ts-mode))

;; ── Editorconfig ────────────────────────────────────────────────────
(use-package editorconfig
  :config
  (editorconfig-mode 1))

(provide 'custom-lang)
;;; custom-lang.el ends here
