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
     (mermaid . t)))
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
;; Pacote MELPA chama-se `jupyter' (o repo é emacs-jupyter); kernels
;; fornecidos pelo env python do Nix (home/carlosfilho/emacs.nix).
;; `ob-jupyter' não é autoloaded e não require org — precisa dos dois
;; para definir `org-babel-execute:jupyter' e `org-babel-load-languages'.
(use-package jupyter
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
  :config
  (let ((bin (expand-file-name "build/server/epdfinfo" pdf-tools-directory)))
    (when (file-executable-p bin)
      (setq pdf-info-epdfinfo-program bin)))
  (pdf-tools-install :no-query)
  (setq pdf-view-display-size 'fit-width))

;; Fallback: DocView (built-in) apenas se pdf-tools nao estiver disponivel
(unless (featurep 'pdf-view)
  (use-package doc-view
    :ensure nil
    :config
    (setq doc-view-resolution 300)))

;; ── org-noter (opcional, leitura de PDF com notas) ─────────────────
(use-package org-noter
  :after org
  :config
  (setq org-noter-notes-search-path '("~/org/notes")))

(provide 'custom-org)
;;; custom-org.el ends here
