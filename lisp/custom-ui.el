;;; custom-ui.el --- UI theme and appearance -*- lexical-binding: t; -*-

;;; Commentary:
;; ef-themes (with mixed fonts, variable-pitch), mood-line, which-key.

;;; Code:

;; ── ef-themes ───────────────────────────────────────────────────────
(use-package ef-themes
  :ensure t
  :init
  ;; Mixed fonts: variable-pitch headings + fixed-pitch code
  (setq ef-themes-mixed-fonts t
        ef-themes-variable-pitch-ui t
        ;; Hierarchical heading sizes with variable-pitch
        ef-themes-headings
        '((1 . (variable-pitch bold 1.3))
          (2 . (variable-pitch bold 1.15))
          (3 . (variable-pitch bold 1.05))
          (4 . (variable-pitch bold 1.0))
          (5 . (variable-pitch bold 1.0))
          (6 . (variable-pitch bold 1.0))
          (7 . (variable-pitch bold 1.0))
          (t . (variable-pitch bold 1.0))))
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
  (setq which-key-idle-delay 0.8
        which-key-show-early-on-C-h t)
  (which-key-mode 1))

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
