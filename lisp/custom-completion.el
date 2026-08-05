;;; custom-completion.el --- Minibuffer and completion -*- lexical-binding: t; -*-

;;; Commentary:
;; vertico, consult, marginalia, orderless, embark, corfu.

;;; Code:

;; ── vertico ─────────────────────────────────────────────────────────
(use-package vertico
  :config
  (vertico-mode 1)
  (setq vertico-cycle t))

;; ── marginalia ──────────────────────────────────────────────────────
(use-package marginalia
  :config
  (marginalia-mode 1))

;; ── orderless ───────────────────────────────────────────────────────
(use-package orderless
  :config
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))

;; ── consult ─────────────────────────────────────────────────────────
(use-package consult
  :bind
  (("C-x b"   . consult-buffer)
   ("C-s"     . consult-line)
   ("C-c s"   . consult-ripgrep)
   ("C-c h"   . consult-history)
   ("C-c i"   . consult-imenu)
   ("C-c k"   . consult-keep-lines)
   ("M-g g"   . consult-goto-line)
   ("M-g M-g" . consult-goto-line)))

;; Preview on consult commands
(with-eval-after-load 'consult
  (when (fboundp 'consult-preview-at-point-mode)
    (add-hook 'minibuffer-setup-hook #'consult-preview-at-point-mode)))

;; ── embark ──────────────────────────────────────────────────────────
(use-package embark
  :bind
  (("C-." . embark-act)
   ("C-;" . embark-dwim)))

(use-package embark-consult
  :after (embark consult)
  :config
  (define-key embark-general-map "?" #'embark-consult-help))

;; ── corfu ───────────────────────────────────────────────────────────
(use-package corfu
  :config
  (global-corfu-mode 1)
  (setq corfu-auto t
        corfu-auto-delay 0.1
        corfu-auto-prefix 2
        corfu-cycle t
        corfu-popupinfo-delay '(0.2 . 0.1)
        corfu-popupinfo-mode t))

;; TAB/RET behavior with corfu
(with-eval-after-load 'corfu
  (defun corfu-enable-always-in-minibuffer ()
    "Enable Corfu in the minibuffer."
    (setq-local corfu-echo-delay nil
                corfu-popupinfo-delay nil))
  (add-hook 'minibuffer-setup-hook #'corfu-enable-always-in-minibuffer 1))

(provide 'custom-completion)
;;; custom-completion.el ends here
