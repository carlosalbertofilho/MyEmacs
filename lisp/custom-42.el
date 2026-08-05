;;; custom-42.el --- 42 School configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; header42.el, flycheck-norminette.el, estilo C 42 (tabs, 80 cols, whitespace).
;; Carrega os arquivos de site-lisp/.

;;; Code:

;; ── flycheck (dependency for flycheck-norminette) ──────────────────
(use-package flycheck
  :config
  (global-flycheck-mode 1))

;; ── site-lisp ───────────────────────────────────────────────────────
(require 'header42)
(require 'flycheck-norminette)

;; ── header42 ────────────────────────────────────────────────────────
(header-42-enable)                    ; hooks + C-c h (fallback nativo)

;; ── flycheck + norminette ──────────────────────────────────────────
(flycheck-norminette-setup)

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

;; ── Chain eglot → norminette ───────────────────────────────────────
(defun my-setup-flycheck-chain-after-eglot ()
  "Adiciona c-norminette após o checker eglot."
  (when (flycheck-checker-get 'eglot 'start)
    (flycheck-add-next-checker 'eglot 'c-norminette t)))

(add-hook 'eglot-managed-mode-hook #'my-setup-flycheck-chain-after-eglot)

(provide 'custom-42)
;;; custom-42.el ends here
