;;; custom-42.el --- 42 School configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; header42.el, custom-norminette.el (JSON-based, eglot chain),
;; estilo C 42 (tabs, 80 cols, whitespace).

;;; Code:

;; ── flycheck (dependency for norminette) ───────────────────────────
;; :demand t ensures flycheck is installed and loaded before custom-norminette
;; tries to (require 'flycheck)
(use-package flycheck
  :ensure t
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
  (local-set-key (kbd "<tab>") #'self-insert-command))

(add-hook 'c-mode-hook #'my-c-42-style t)
(add-hook 'c++-mode-hook #'my-c-42-style t)

;; ── Chain eglot → norminette (handled by custom-norminette-setup) ──
;; The custom-norminette-setup function automatically chains norminette
;; after eglot diagnostics using flycheck-add-next-checker.

(provide 'custom-42)
;;; custom-42.el ends here
