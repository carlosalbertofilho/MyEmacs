;;; custom-42.el --- 42 School configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; header42.el, custom-norminette.el (JSON-based, eglot chain),
;; estilo C 42 (tabs, 80 cols, whitespace).

;;; Code:

;; ── flycheck (dependency for norminette) ───────────────────────────
;; Installed by custom-lang.el (:ensure t). Use :ensure nil here to prevent duplicate Elpaca queue error.
(use-package flycheck
  :ensure nil
  :demand t
  :config
  (global-flycheck-mode 1)
  ;; Habilitar checker emacs-lisp em modos Elisp
  (setq flycheck-emacs-lisp-load-path
        (append '("~/.config/emacs-vanilla/lisp"
                  "~/.config/emacs-vanilla/site-lisp")
                load-path))
  ;; Permitir checagem em buffers sem arquivo (ex: *scratch*)
  (add-hook 'emacs-lisp-mode-hook #'flycheck-mode)
  (add-hook 'lisp-interaction-mode-hook #'flycheck-mode))

;; Wait for flycheck to be installed before loading custom-norminette
;; (which has a hard (require 'flycheck) at the top)
(elpaca-wait)

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

(with-eval-after-load 'reformatter
  (reformatter-define +carlos/c-formatter-42
    :program +carlos/c-formatter-42-executable
    :args nil
    :lighter " 42fmt"))

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
