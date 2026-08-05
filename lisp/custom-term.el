;;; custom-term.el --- Terminal and shell -*- lexical-binding: t; -*-

;;; Commentary:
;; vterm, eshell (+ eshell-prompt-extras).

;;; Code:

;; ── vterm ───────────────────────────────────────────────────────────
(use-package vterm
  :config
  (setq vterm-keymap-exceptions
        (delete "C-c" (delete "C-u" (delete "C-g" vterm-keymap-exceptions))))
  (setq vterm-max-scrollback 100000)
  (setq vterm-copy-exclude-prompt t))

;; Multiline prompt helper
(defun +carlos/vterm-write-multiline-prompt ()
  "Write clipboard or selection content as multiline in vterm."
  (interactive)
  (when-let* ((text (or (car kill-ring) "")))
    (vterm-send-string text)))

(define-key vterm-mode-map (kbd "C-c C-e") #'+carlos/vterm-write-multiline-prompt)

;; ── eshell ──────────────────────────────────────────────────────────
(use-package eshell
  :bind
  (("C-c e" . eshell))
  :config
  (setq eshell-buffer-name "*eshell*"
        eshell-scroll-to-bottom-on-input t))

;; eshell-prompt-extras
(use-package eshell-prompt-extras
  :after eshell
  :config
  (setq eshell-highlight-prompt t
        eshell-prompt-function #'epe-theme-lambda))

;; ── Display buffer rules ────────────────────────────────────────────
(add-to-list 'display-buffer-alist
             '("\\*vterm"
               (display-buffer-in-direction)
               (direction . bottom)
               (window-height . 0.4)))

(provide 'custom-term)
;;; custom-term.el ends here
