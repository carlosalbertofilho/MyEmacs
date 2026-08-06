;;; custom-lang.el --- Languages and LSP -*- lexical-binding: t; -*-

;;; Commentary:
;; eglot (LSP), treesit-auto, linguagens: Go, TypeScript/React, Python, C/C++.
;; Formatters: ruff (Python), etc.

;;; Code:

;; ── treesit-auto ────────────────────────────────────────────────────
(use-package treesit-auto
  :ensure t
  :custom
  (treesit-auto-install 'prompt)
  :config
  (global-treesit-auto-mode 1))

;; ── eglot (built-in Emacs 29+) ──────────────────────────────────────
;; NOTE: Avoid `prog-mode' hook — eglot-ensure on ALL prog modes causes slowdown.
;; Use per-mode hooks instead (see language sections below).
(use-package eglot
  :ensure nil
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

;; ── reformatter.el (wrapper for external CLI reformatters) ──────────
;; Used by custom-42.el to define c_formatter_42 integration.
(use-package reformatter
  :ensure t
  :defer t)

;; ── Elisp ───────────────────────────────────────────────────────────
(use-package elisp-mode
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
  :ensure t
  :mode ("\\.ya?ml\\'" . yaml-mode))

;; ── Markdown ────────────────────────────────────────────────────────
(use-package markdown-mode
  :ensure nil
  :mode ("\\.md\\'" . markdown-mode))

;; ── Nix ─────────────────────────────────────────────────────────────
(use-package nix-mode
  :ensure t
  :mode ("\\.nix\\'" . nix-mode))

;; ── Editorconfig ────────────────────────────────────────────────────
(use-package editorconfig
  :config
  (editorconfig-mode 1))

;; ── Forward declarations for Flycheck, Eldoc-box, Apheleia ──────────
(declare-function flycheck-next-error "flycheck")
(declare-function flycheck-previous-error "flycheck")
(declare-function consult-flycheck "consult-flycheck")
(declare-function flycheck-inline-mode "flycheck-inline")
(declare-function eldoc-box-hover-at-point-mode "eldoc-box")
(declare-function eldoc-box-help-at-point "eldoc-box")
(declare-function apheleia-global-mode "apheleia")
(defvar apheleia-inhibit-functions)

;; ── Flycheck & Flycheck-inline ─────────────────────────────────────
(setq-default flycheck-indication-mode 'left-fringe)

(use-package flycheck
  :ensure t
  :demand t
  :config
  (define-key flycheck-mode-map (kbd "M-g n") #'flycheck-next-error)
  (define-key flycheck-mode-map (kbd "M-g p") #'flycheck-previous-error))
(elpaca-wait)

(use-package consult-flycheck
  :ensure t
  :after (consult flycheck)
  :bind ("C-c ! l" . consult-flycheck))

(use-package flycheck-inline
  :ensure t
  :after flycheck
  :hook (flycheck-mode . flycheck-inline-mode))

;; ── eldoc-box (documentation hover) ────────────────────────────────
(use-package eldoc-box
  :ensure t
  :hook (eglot-managed-mode . eldoc-box-hover-at-point-mode)
  :bind ("C-c c d" . eldoc-box-help-at-point))

;; ── apheleia (code formatting) ─────────────────────────────────────
(use-package apheleia
  :ensure t
  :config
  (apheleia-global-mode +1)
  (add-to-list 'apheleia-inhibit-functions
               (lambda () (derived-mode-p 'c-mode 'c-ts-mode))))

(provide 'custom-lang)
;;; custom-lang.el ends here
