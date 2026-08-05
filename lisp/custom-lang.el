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
(use-package eglot
  :hook ((prog-mode . eglot-ensure))
  :config
  ;; Ignorar formatação do servidor para C/C++ (Norma 42 controla)
  (add-to-list 'eglot-ignored-server-capabilities :documentFormattingProvider)
  (add-to-list 'eglot-ignored-server-capabilities :documentRangeFormattingProvider))

;; ── Go ──────────────────────────────────────────────────────────────
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(go-ts-mode go-mode . ("gopls"))))

(use-package go-ts-mode
  :ensure nil
  :mode ("\\.go\\'" . go-ts-mode))

;; ── TypeScript / React ──────────────────────────────────────────────
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '((typescript-ts-mode tsx-ts-mode typescript-mode) .
                 ("typescript-language-server" "--stdio"))))

(use-package typescript-ts-mode
  :ensure nil
  :mode (("\\.ts\\'"  . typescript-ts-mode)
         ("\\.tsx\\'" . tsx-ts-mode)))

;; ── Python ──────────────────────────────────────────────────────────
(with-eval-after-load 'eglot
  ;; basedpyright como servidor principal
  (add-to-list 'eglot-server-programs
               '(python-ts-mode python-mode . ("basedpyright" "--stdio")))
  ;; ruff como add-on para linting/format
  (add-to-list 'eglot-server-programs
               '((python-ts-mode python-mode) . ("ruff" "server"))))

(use-package python
  :ensure nil
  :mode (("\\.py\\'" . python-ts-mode))
  :config
  (setq python-shell-interpreter "ipython"
        python-shell-interpreter-args "-i --simple-prompt --no-color-info"))

;; ── C / C++ (42 School) ─────────────────────────────────────────────
;; eglot já está configurado; clangd é detectado automaticamente.
;; A formatação é ignorada (ver eglot-ignored-server-capabilities acima).

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
