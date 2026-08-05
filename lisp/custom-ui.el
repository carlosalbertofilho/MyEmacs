;;; custom-ui.el --- UI theme and appearance -*- lexical-binding: t; -*-

;;; Commentary:
;; ef-themes, mood-line, olivetti, which-key refinements.

;;; Code:

;; ── ef-themes ───────────────────────────────────────────────────────
(use-package ef-themes
  :ensure t
  :config
  (setq ef-themes-to-toggle '(ef-spring ef-winter))
  (load-theme 'ef-winter t))

;; ── mood-line ───────────────────────────────────────────────────────
(use-package mood-line
  :ensure t
  :config
  (mood-line-mode 1))

;; ── which-key (built-in Emacs 30+, refine here) ─────────────────────
(use-package which-key
  :ensure nil
  :config
  (setq which-key-idle-delay 0.8)
  (setq which-key-show-early-on-C-h t))

;; ── Visual tweaks ───────────────────────────────────────────────────
;; Highlight matching parens
(show-paren-mode 1)
(setq show-paren-style 'expression)

;; Smooth scrolling
(setq scroll-conservatively 101)
(setq scroll-margin 3)

;; Fringe
(fringe-mode '(8 . 8))

(provide 'custom-ui)
;;; custom-ui.el ends here
