;;; magent-driver-test.el --- Tests for curated Magent Driver tools (Etapa C) -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for flycheck_errors, lsp_navigation, and snippet_expand tools.

;;; Code:

(require 'ert)
(require 'custom-magent)

(ert-deftest myemacs-driver-flycheck-errors-handler ()
  "Garante que `+carlos/magent-tool-flycheck-errors` retorna plist válido de resposta."
  (let ((res (+carlos/magent-tool-flycheck-errors nil)))
    (should (listp res))
    (should (plist-get res :status))))

(ert-deftest myemacs-driver-lsp-navigation-missing-symbol ()
  "Garante que `+carlos/magent-tool-lsp-navigation` retorna erro se :symbol estiver ausente."
  (let ((res (+carlos/magent-tool-lsp-navigation nil)))
    (should (string= (plist-get res :status) "error"))
    (should (string-match-p "obrigatório" (plist-get res :message)))))

(ert-deftest myemacs-driver-lsp-navigation-symbol-with-no-xref ()
  "Garante que `+carlos/magent-tool-lsp-navigation` trata ausência de xref suavemente."
  (let ((res (+carlos/magent-tool-lsp-navigation '(:symbol "test-func"))))
    (should (listp res))
    (should (plist-get res :status))))

(ert-deftest myemacs-driver-snippet-expand-handler ()
  "Garante que `+carlos/magent-tool-snippet-expand` retorna plist válido."
  (let ((res (+carlos/magent-tool-snippet-expand nil)))
    (should (listp res))
    (should (plist-get res :status))))

(provide 'magent-driver-test)
;;; magent-driver-test.el ends here
