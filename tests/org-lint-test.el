;;; org-lint-test.el --- Org structure regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Valida a estrutura dos arquivos .org do projeto usando o linter
;; bin/org-lint.el: blocos #+BEGIN_/#+END_ balanceados, ausência de headings
;; malformados (`^ *') e referências ao nome canônico `TODO.org' (nunca
;; `TODO.md'). Protege contra a regressão dos blocos #+BEGIN_QUOTE
;; desbalanceados vistos no TODO.org (2026-08-16).

;;; Code:

(require 'ert)

(defconst org-lint-test--root
  (file-name-directory
   (directory-file-name (file-name-directory (or load-file-name default-directory))))
  "Raiz do repositório (tests/ -> raiz do repo).")

(load (expand-file-name "bin/org-lint.el" org-lint-test--root) nil t)

(ert-deftest myemacs-org-lint-all-files-clean ()
  "Nenhum arquivo .org do repo tem blocos desbalanceados, headings
malformados ou referências a `TODO.md'."
  (let ((problems (org-lint-run org-lint-test--root)))
    (should-not problems)))

(ert-deftest myemacs-org-lint-todo-md-prose-ref-flagged ()
  "Uma referência `TODO.md' em prosa (fora de `=...=') é sinalizada."
  (let ((f (make-temp-file "org-lint-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file f
            (insert "* H\nConsulte TODO.md para o planejamento.\n"))
          (should (org-lint--check-file f)))
      (delete-file f))))

(ert-deftest myemacs-org-lint-todo-md-inline-meta-ok ()
  "Uma meta-referência em código inline (=TODO.md=) não é sinalizada."
  (let ((f (make-temp-file "org-lint-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file f
            (insert "* H\nAusência de refs a =TODO.md= (usar =TODO.org=).\n"))
          (should-not (org-lint--check-file f)))
      (delete-file f))))

(provide 'org-lint-test)
;;; org-lint-test.el ends here
