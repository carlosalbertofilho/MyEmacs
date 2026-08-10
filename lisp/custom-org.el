;;; custom-org.el --- Org mode and literate programming -*- lexical-binding: t; -*-

;;; Commentary:
;; org-mode, org-babel (python, shell, emacs-lisp, mermaid, gptel),
;; emacs-jupyter, pdf-tools (opcional), LaTeX preview, org-fragtog.

;;; Code:

;; ── ob-mermaid ──────────────────────────────────────────────────────
(use-package ob-mermaid
  :ensure t
  :after org
  :config
  (setq ob-mermaid-cli-path "mmdc")
  ;; Registrar a linguagem mermaid dinamicamente após o carregamento
  (add-to-list 'org-babel-load-languages '(mermaid . t))
  (org-babel-do-load-languages 'org-babel-load-languages org-babel-load-languages))

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
     (emacs-lisp . t)))
  :bind
  (("C-c a" . org-agenda)))

;; ── org-fragtog: auto-render LaTeX when cursor leaves ───────────────
(use-package org-fragtog
  :ensure t
  :hook (org-mode . org-fragtog-mode))

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
;; rebuildar. Em vez de compilar a mao, o MyMachine (Nix) provê o binario
;; `epdfinfo' (mesmo commit do elpaca, patch de getline do nixpkgs) no PATH
;; via home.packages. Aqui priorizamos `executable-find "epdfinfo"' e
;; deixamos o fallback manual (build/server/epdfinfo) para ambientes sem Nix.
(use-package pdf-tools
  :ensure t
  :config
  (let ((bin (or (executable-find "epdfinfo")
                 (expand-file-name "build/server/epdfinfo" pdf-tools-directory))))
    (when (and bin (file-executable-p bin))
      (setq pdf-info-epdfinfo-program bin)))
  (unless noninteractive
    (pdf-tools-install :no-query))
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

(provide 'custom-org)
;;; custom-org.el ends here
