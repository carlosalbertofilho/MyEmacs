;;; custom-completion.el --- Minibuffer and completion -*- lexical-binding: t; -*-

;;; Commentary:
;; vertico, consult, marginalia, orderless, embark, corfu.
;; All packages installed via Elpaca (git-based, :ensure t by default).

;;; Code:

;; Forward declarations for byte-compiler
(declare-function vertico-mode "vertico")
(declare-function marginalia-mode "marginalia")
(declare-function global-corfu-mode "corfu")
(declare-function embark-consult-help "embark-consult")
(declare-function elpaca "elpaca")
(declare-function elpaca-wait "elpaca")
(declare-function nerd-icons-corfu-formatter "nerd-icons-corfu")
(declare-function tempel-expand "tempel")
(declare-function tempel-complete "tempel")
(declare-function tempel-insert "tempel")
(declare-function eglot-tempel-mode "eglot-tempel")

;; Queue completion packages and wait to prevent race conditions during cold boot
(elpaca vertico)
(elpaca marginalia)
(elpaca orderless)
(elpaca corfu)
(elpaca tempel)
(elpaca tempel-collection)
(elpaca eglot-tempel)
(elpaca-wait)

;; ── vertico ─────────────────────────────────────────────────────────
(use-package vertico
  :ensure nil
  :demand t  ;; Must load immediately for minibuffer completion
  :config
  (vertico-mode 1)
  (setq vertico-cycle t))

;; ── marginalia ──────────────────────────────────────────────────────
(use-package marginalia
  :ensure nil
  :demand t  ;; Must load immediately for minibuffer annotations
  :config
  (marginalia-mode 1))

;; ── orderless ───────────────────────────────────────────────────────
(use-package orderless
  :ensure nil
  :demand t  ;; Must load immediately for completion styles
  :config
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))

;; ── consult ─────────────────────────────────────────────────────────
(use-package consult
  :ensure t
  :bind
   (("C-x b"   . consult-buffer)
    ("C-s"     . consult-line)
    ("C-c s"   . consult-ripgrep)
    ("C-c /"   . consult-history)     ; was C-c h — freed for stdheader (42 School)
    ("M-s i"   . consult-imenu)       ; was C-c i — freed for gptel (AI cluster)
    ("C-c k"   . consult-keep-lines)
    ("M-g g"   . consult-goto-line)
    ("M-g M-g" . consult-goto-line)))

;; Preview on consult commands
(with-eval-after-load 'consult
  (when (fboundp 'consult-preview-at-point-mode)
    (add-hook 'minibuffer-setup-hook #'consult-preview-at-point-mode)))

;; ── embark ──────────────────────────────────────────────────────────
(use-package embark
  :ensure t
  :bind
  (("C-." . embark-act)
   ("C-;" . embark-dwim)))

(use-package embark-consult
  :ensure t
  :after (embark consult)
  :config
  (define-key embark-general-map "?" #'embark-consult-help))

;; ── corfu ───────────────────────────────────────────────────────────
(use-package corfu
  :ensure nil
  :demand t  ;; Must load immediately for global-corfu-mode
  :config
  (global-corfu-mode 1)
  (setq corfu-auto t
        corfu-auto-delay 0.1
        corfu-auto-prefix 2
        corfu-cycle t
        corfu-popupinfo-delay '(0.2 . 0.1))
  (when (fboundp 'corfu-popupinfo-mode)
    (corfu-popupinfo-mode 1)))

;; Corfu minibuffer integration
(defun +carlos/corfu-enable-in-minibuffer ()
  "Enable Corfu in the minibuffer."
  (setq-local corfu-echo-delay nil
              corfu-popupinfo-delay nil))

(with-eval-after-load 'corfu
  (add-hook 'minibuffer-setup-hook #'+carlos/corfu-enable-in-minibuffer 1))

;; ── nerd-icons-corfu ────────────────────────────────────────────────
(use-package nerd-icons-corfu
  :ensure t
  :config
  (with-eval-after-load 'corfu
    (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter)))

;; ── tempel ──────────────────────────────────────────────────────────
(use-package tempel
  :ensure nil
  :demand t  ;; Capf hook must be registered at startup
  :bind (("M-+" . tempel-complete)
         ("M-*" . tempel-insert))
  :config
  (defun +carlos/tempel-setup-capf ()
    "Prepend `tempel-expand' to the local completion Capf list."
    (setq-local completion-at-point-functions
                (cons #'tempel-expand completion-at-point-functions)))
  (add-hook 'prog-mode-hook #'+carlos/tempel-setup-capf)
  (add-hook 'text-mode-hook #'+carlos/tempel-setup-capf)
  (add-hook 'conf-mode-hook #'+carlos/tempel-setup-capf))

;; ── tempel-collection ───────────────────────────────────────────────
(use-package tempel-collection
  :ensure nil
  :demand t)  ;; Load bundled static templates at startup

;; ── eglot-tempel ────────────────────────────────────────────────────
(use-package eglot-tempel
  :ensure nil
  :demand t  ;; Global mode translates LSP snippets for tempel
  :config
  (eglot-tempel-mode 1))

(provide 'custom-completion)
;;; custom-completion.el ends here
