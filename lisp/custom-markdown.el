;;; custom-markdown.el --- Markdown and GFM support -*- lexical-binding: t; -*-

;;; Commentary:
;; markdown-mode and gfm-mode for editing Markdown files.
;; Prefers gfm-mode for Git repositories (better code blocks, tables, task lists).
;; LaTeX math rendering via markdown-enable-math.
;; Markup hiding toggle: C-c C-x C-m (markdown-toggle-markup-hiding).

;;; Code:

;; ── markdown-mode + gfm-mode ────────────────────────────────────────
(use-package markdown-mode
  :ensure t
  :mode (("README\\.md\\'" . gfm-mode)
         ("\\.md\\'" . gfm-mode)
         ("\\.markdown\\'" . gfm-mode))
  :init
  ;; Use pandoc if available, fallback to markdown
  (setq markdown-command "pandoc")
  :config
  ;; Feature toggles
  (setq markdown-enable-math t              ; LaTeX math highlighting
        markdown-enable-html t              ; HTML tag highlighting
        markdown-fontify-code-blocks-natively t   ; Native syntax in code blocks
        markdown-gfm-use-electric-backquote t   ; ``` inserts GFM block
        markdown-make-gfm-checkboxes-buttons t  ; Task lists clickable
        markdown-hide-urls nil              ; Show full URLs in links
        markdown-hide-markup nil            ; Toggle with C-c C-x C-m
        markdown-split-window-direction 'right  ; Preview on right
        markdown-live-preview-delete-export 'delete-on-export ; Clean up after preview
        markdown-reference-location 'header ; Ref defs before next heading
        markdown-footnote-location 'end     ; Footnotes at end of file
        markdown-list-indent-width 4        ; List indent depth
        markdown-indent-on-enter t          ; Auto-indent on RET
        markdown-gfm-uppercase-checkbox t)  ; [X] instead of [x] (org compat)

  ;; Preview settings
  (setq markdown-display-remote-images t    ; Show remote images inline
        markdown-max-image-size '(800 . 600)) ; Max image size

  ;; Header scaling (variable-pitch by level)
  (setq markdown-header-scaling t
        markdown-header-scaling-values '(2.0 1.7 1.4 1.1 1.0 1.0)))

;; ── edit-indirect (for editing code blocks in indirect buffer) ──────
(use-package edit-indirect
  :ensure t)

;; ── markdown-mermaid: render Mermaid diagrams inline ────────────────
;; Requires mmdc (@mermaid-js/mermaid-cli) installed via Nix.
(use-package markdown-mermaid
  :config
  (setq markdown-mermaid-path "mmdc"))

(provide 'custom-markdown)
;;; custom-markdown.el ends here
