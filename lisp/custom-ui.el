; TODO: review
;;; custom-ui.el --- UI theme and appearance -*- lexical-binding: t; -*-

;;; Commentary:
;; ef-themes (with mixed fonts, variable-pitch), mood-line, which-key,
;; indent-bars, rainbow-delimiters, hl-line, whitespace.

;;; Code:

(declare-function indent-bars-mode "indent-bars")
(declare-function rainbow-delimiters-mode "rainbow-delimiters")
(declare-function whitespace-mode "whitespace")
(declare-function hl-line-mode "hl-line")

;; ── ef-themes ───────────────────────────────────────────────────────
(use-package ef-themes
  :ensure t
  :demand t  ;; Force load now (theme must be active before modules load)
  :config
  ;; Mixed fonts: variable-pitch headings + fixed-pitch code
  (setq ef-themes-mixed-fonts t
        ef-themes-variable-pitch-ui t
        ;; Hierarchical heading sizes with variable-pitch
        ef-themes-headings
        \'((1 . (variable-pitch bold 1.3))
          (2 . (variable-pitch bold 1.15))
          (3 . (variable-pitch bold 1.05))
          (4 . (variable-pitch bold 1.0))
          (5 . (variable-pitch bold 1.0))
          (6 . (variable-pitch bold 1.0))
          (7 . (variable-pitch bold 1.0))
          (t . (variable-pitch bold 1.0)))
        ef-themes-to-toggle \'(ef-spring ef-winter))
  (load-theme \'ef-winter t))

;; ── mood-line ───────────────────────────────────────────────────────
(use-package mood-line
  :ensure t
  :config
  (mood-line-mode 1))

;; ── which-key (built-in Emacs 30+, refine here) ─────────────────────
(use-package which-key
  :ensure t
  :demand t
  :config
  (setq which-key-idle-delay 0.4
        which-key-show-early-on-C-h t)
  (which-key-mode 1))

;; ── Visual tweaks ───────────────────────────────────────────────────
;; Highlight matching parens
(show-paren-mode 1)
(setq show-paren-style \'expression)

;; Smooth scrolling
(setq scroll-conservatively 101)
(setq scroll-margin 3)

;; Fringe
(fringe-mode \'(8 . 8))

;; Divisórias de janela (permite redimensionar a sidebar com o mouse)
(setq window-divider-default-places \'right-only
      window-divider-default-right-width 1)
(window-divider-mode 1)

;; ── Flycheck wave faces ─────────────────────────────────────────────
(custom-set-faces
 \'(flycheck-error ((t (:underline (:style wave :color "#ff5555")))))
 \'(flycheck-warning ((t (:underline (:style wave :color "#f1fa8c")))))
 \'(flycheck-info ((t (:underline (:style wave :color "#8be9fd"))))))

;; ── Display buffer rules (drawer inferior centralizado) ────────────
(add-to-list \'display-buffer-alist
             \'("\*\(compilation\|eglot events\|magit-process\|vterm.*\|eshell\|gptel.*\)\*"
               (display-buffer-in-direction)
               (direction . bottom)
               (window-height . 0.3)))

;; ── Code visualization (indent-bars, rainbow-delimiters, hl-line, whitespace) ──
(use-package indent-bars
  :ensure t
  :hook (prog-mode . indent-bars-mode)
  :custom
  (indent-bars-treesitter-support t)
  (indent-bars-width 0.2)
  (indent-bars-pad 0.1)
  (indent-bars-color-by-depth \'(:regexp "outline-\([0-9]+\)" :blend 1)))

(use-package rainbow-delimiters
  :ensure t
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package hl-line
  :ensure nil
  :hook (prog-mode . hl-line-mode))

(use-package whitespace
  :ensure nil
  :hook (prog-mode . whitespace-mode)
  :custom
  (whitespace-style \'(face trailing tabs tab-mark)))

(provide \'custom-ui)
;;; custom-ui.el ends here
