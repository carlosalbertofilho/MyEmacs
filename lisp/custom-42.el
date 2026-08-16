;;; custom-42.el --- 42 School configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; header42.el, custom-norminette.el (JSON-based, eglot chain),
;; estilo C 42 (tabs, 80 cols, whitespace).

;;; Code:

;; ── flycheck (dependency for norminette) ───────────────────────────
;; Instalado e ativado por custom-lang.el (:ensure (:wait t)). Use :ensure
;; nil aqui para evitar fila duplicada no Elpaca; o wait já é escopado no lang.
(use-package flycheck
  :ensure nil
  :demand t
  :config
  (global-flycheck-mode 1)
  ;; Habilitar checker emacs-lisp em modos Elisp
  (setq flycheck-emacs-lisp-load-path
        (append (list (expand-file-name "lisp" user-emacs-directory)
                      (expand-file-name "site-lisp" user-emacs-directory))
                load-path))
  ;; Habilitar checagem emacs-lisp para arquivos .el
  (add-hook 'emacs-lisp-mode-hook #'flycheck-mode))

;; ── site-lisp ───────────────────────────────────────────────────────
(require 'header42)

;; ── norminette (new JSON-based integration) ────────────────────────
(require 'custom-norminette)
(custom-norminette-setup)

;; ── c_formatter_42 (reformatter.el wrapper) ─────────────────────────
;; CLI: pip install c-formatter-42 (https://github.com/dawnbeen/c_formatter_42)
;; Reads stdin, writes stdout. Reformatter.el handles buffer replacement.

(defgroup +carlos/c-formatter-42 nil
  "42 School C code formatter using c_formatter_42."
  :group 'c
  :prefix "+carlos/c-formatter-42-")

(defcustom +carlos/c-formatter-42-executable "c_formatter_42"
  "Path to the c_formatter_42 executable."
  :type 'string
  :group '+carlos/c-formatter-42)

(defcustom +carlos/c-formatter-42-format-on-save nil
  "If non-nil, format C buffers on save using c_formatter_42.
Off by default because norminette checks on save and format
may introduce changes that need review before submission."
  :type 'boolean
  :group '+carlos/c-formatter-42)

(require 'reformatter nil t)

(reformatter-define +carlos/c-formatter-42
  :program +carlos/c-formatter-42-executable
  :args nil
  :lighter " 42fmt")

;; Manual format-on-save integration (reformatter :on-save-* not available).
(defun +carlos/c-formatter-42--on-save ()
  "Run c_formatter_42 on buffer before save when enabled."
  (when (and +carlos/c-formatter-42-format-on-save
             (executable-find +carlos/c-formatter-42-executable))
    (ignore-errors (+carlos/c-formatter-42-buffer))))

(add-hook 'before-save-hook #'+carlos/c-formatter-42--on-save)

;; ── header42 ────────────────────────────────────────────────────────
(header-42-enable)                    ; hooks + C-c h (fallback nativo)

;; ── Estilo C 42 ─────────────────────────────────────────────────────
(defun my-c-42-style ()
  "Aplica o estilo C da 42 School: tabs, 4 spaces, 80 cols, whitespace."
  (interactive)
  (setq-local indent-tabs-mode t
              tab-width 4
              c-basic-offset 4
              fill-column 80)
  (when (fboundp 'editorconfig-mode)
    (editorconfig-mode -1))
  (display-fill-column-indicator-mode 1)
  (whitespace-mode 1)
  (add-hook 'before-save-hook #'whitespace-cleanup nil t)
  (add-hook 'before-save-hook #'stdheader nil t)
  (local-set-key (kbd "<tab>") #'self-insert-command)
  ;; Manual format via c_formatter_42
  (when (commandp '+carlos/c-formatter-42-buffer)
    (local-set-key (kbd "C-c C-f") #'+carlos/c-formatter-42-buffer)))

(add-hook 'c-mode-hook #'my-c-42-style t)
(add-hook 'c++-mode-hook #'my-c-42-style t)

;; ── Auto-enable format-on-save if configured ────────────────────────
(when +carlos/c-formatter-42-format-on-save
  (add-hook 'c-mode-hook #'+carlos/c-formatter-42-on-save-mode)
  (add-hook 'c++-mode-hook #'+carlos/c-formatter-42-on-save-mode))

;; ── Chain eglot → norminette (handled by custom-norminette-setup) ──
;; The custom-norminette-setup function automatically chains norminette
;; after eglot diagnostics using flycheck-add-next-checker.

(provide 'custom-42)
;;; custom-42.el ends here
