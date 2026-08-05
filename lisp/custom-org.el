;;; custom-org.el --- Org mode and literate programming -*- lexical-binding: t; -*-

;;; Commentary:
;; org-mode, org-babel (python, shell, emacs-lisp, mermaid, gptel),
;; emacs-jupyter, pdf-tools (opcional).

;;; Code:

;; ── org-mode ────────────────────────────────────────────────────────
(use-package org
  :ensure nil
  :config
  (setq org-directory "~/org"
        org-confirm-babel-evaluate nil
        org-startup-indented t
        org-startup-with-inline-images t
        org-hide-emphasis-markers t
        org-edit-src-content-indentation 2)
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((python . t)
     (shell . t)
     (emacs-lisp . t)
     (mermaid . t)
     (gptel . t)))
  :bind
  (("C-c a" . org-agenda)))

;; ── org-babel mermaid ───────────────────────────────────────────────
(use-package ob-mermaid
  :config
  (setq ob-mermaid-cli-path "mmdc"))

;; ── markdown-mermaid ────────────────────────────────────────────────
(use-package markdown-mermaid
  :config
  (setq markdown-mermaid-path "mmdc"))

;; ── emacs-jupyter ───────────────────────────────────────────────────
(use-package emacs-jupyter
  :catch t
  :config
  (add-to-list 'org-babel-load-languages '(jupyter . t)))

;; ── pdf-tools (opcional) ───────────────────────────────────────────
(use-package pdf-tools
  :config
  (pdf-tools-install :no-query)
  (setq pdf-view-display-size 'fit-width))

;; ── org-noter (opcional, leitura de PDF com notas) ─────────────────
(use-package org-noter
  :after org
  :config
  (setq org-noter-notes-search-path '("~/org/notes")))

(provide 'custom-org)
;;; custom-org.el ends here
