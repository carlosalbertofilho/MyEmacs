;;; custom-org.el --- Org mode and literate programming -*- lexical-binding: t; -*-

;;; Commentary:
;; org-mode, org-babel (python, shell, emacs-lisp, mermaid, gptel),
;; emacs-jupyter, pdf-tools (opcional), LaTeX preview, org-fragtog.

;;; Code:

;; ── org-mode ────────────────────────────────────────────────────────
(use-package org
  :ensure nil
  :config
  (setq org-directory "~/org"
        org-confirm-babel-evaluate nil
        org-startup-indented t
        org-startup-with-inline-images t
        org-startup-with-latex-preview t       ;; Render LaTeX fragments on open
        org-hide-emphasis-markers t
        org-edit-src-content-indentation 2)
  ;; LaTeX fragment rendering scale
  (setq org-format-latex-options
        (plist-put org-format-latex-options :scale 1.5))
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((python . t)
     (shell . t)
     (emacs-lisp . t)
     (mermaid . t)))
  :bind
  (("C-c a" . org-agenda)))

;; ── org-fragtog: auto-render LaTeX when cursor leaves ───────────────
(use-package org-fragtog
  :ensure t
  :hook (org-mode . org-fragtog-mode))

;; ── org-babel mermaid ───────────────────────────────────────────────
(use-package ob-mermaid
  :ensure t
  :config
  (setq ob-mermaid-cli-path "mmdc"))

;; ── emacs-jupyter ───────────────────────────────────────────────────
;; Repo: https://github.com/jupyter/emacs-jupyter
;; Kernels provided by Python env (pip/nix).
;; `ob-jupyter' não é autoloaded e não require org — precisa dos dois
;; para definir `org-babel-execute:jupyter' e `org-babel-load-languages'.
(use-package jupyter
  :ensure t
  :catch t
  :config
  (require 'org)
  (when (require 'ob-jupyter nil t)
    (add-to-list 'org-babel-load-languages '(jupyter . t))))

;; ── pdf-tools ───────────────────────────────────────────────────────
;; macOS: o configure nao detecta `getline' (ac_cv_func_getline=no) e o
;; gcc do Nix nao enxerga o SDK, entao `pdf-tools-install' nao consegue
;; rebuildar. O binario epdfinfo e compilado manualmente uma vez em
;; build/server/ (com HAVE_GETLINE + flags do SDK) e apontamos para ele
;; para que o check passe e o rebuild nunca seja disparado.
(use-package pdf-tools
  :ensure t
  :config
  (let ((bin (expand-file-name "build/server/epdfinfo" pdf-tools-directory)))
    (when (file-executable-p bin)
      (setq pdf-info-epdfinfo-program bin)))
  (pdf-tools-install :no-query)
  (setq pdf-view-display-size 'fit-width)
  ;; Dark mode: invert PDF colors to match dark ef-themes
  (add-hook 'pdf-view-mode-hook #'pdf-view-midnight-minor-mode))

;; Fallback: DocView (built-in) apenas se pdf-tools nao estiver disponivel
(unless (featurep 'pdf-view)
  (use-package doc-view
    :ensure nil
    :config
    (setq doc-view-resolution 300)))

;; ── org-noter (opcional, leitura de PDF com notas) ─────────────────
(use-package org-noter
  :ensure t
  :after org
  :config
  (setq org-noter-notes-search-path '("~/org/notes")))

;; ── org-modern: visual moderno para buffers Org ─────────────────────
;; Estiliza headlines, keywords, tables, source blocks, tags, progress bars.
;; Por Daniel Mendler (mesmo autor de vertico, consult, corfu).
(use-package org-modern
  :ensure t
  :hook (org-mode . org-modern-mode)
  :hook (org-agenda-finalize . org-modern-agenda)
  :config
  ;; Estrelas: substituir por bullet characters
  (setq org-modern-star '("◉" "○" "✸" "✿" "✤" "✜" "◆" "▶"))
  ;; Indicadores de folding
  (setq org-modern-replace-stars t
        org-modern-fold-stars " ▾")
  ;; Tags como labels com borda
  (setq org-modern-tag-face t
        org-modern-label-border 0.5)
  ;; Timestamps estilizados
  (setq org-modern-timestamp t)
  ;; Priority estilizado (use text symbols for terminal compatibility)
  (setq org-modern-priority
        '((?A . "[!A]")   ; was "🔴" — emojis may not render in terminal
          (?B . "[~B]")   ; was "🟡"
          (?C . "[iC]"))) ; was "🟢"
  ;; Checklist estilizado
  (setq org-modern-checkbox
        '((unordered . "•")
          (ordered   . "✓")
          (transcoded . "✗")))
  ;; Table style
  (setq org-modern-table t)
  ;; Progress bars para keywords com progresso
  (setq org-modern-progress t)
  ;; Internal targets estilizados
  (setq org-modern-target t)
  ;; Block names estilizados (src, example, quote, verse, center)
  (setq org-modern-block-name
        '((src . "⟨")
          (example . "⟨")
          (quote . "❝")
          (verse . "❞")
          (center . "◇")))
  ;; Horizontal rules
  (setq org-modern-horizontal-line (make-string 40 ?─)))

(provide 'custom-org)
;;; custom-org.el ends here
