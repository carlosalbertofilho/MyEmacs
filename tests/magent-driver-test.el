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
  (cl-letf (((symbol-function 'xref-find-backend) (lambda () nil)))
    (let ((res (+carlos/magent-tool-lsp-navigation '(:symbol "test-func"))))
      (should (listp res))
      (should (plist-get res :status)))))

(ert-deftest myemacs-driver-snippet-expand-handler ()
  "Garante que `+carlos/magent-tool-snippet-expand` retorna plist válido em todos os cenários."
  (skip-unless (require 'tempel nil t))
  (let ((mock-templates '((deftest "ert-deftest" n "  (should " p ")")
                          (defun "defun" p "()" n "  " p)))
        tempel-inserted-sym)
    (cl-letf (((symbol-function 'tempel--templates) (lambda () mock-templates))
              ((symbol-function 'tempel-insert) (lambda (sym) (setq tempel-inserted-sym sym))))
      ;; 1. Cenário: Listar todos
      (let ((res (+carlos/magent-tool-snippet-expand nil)))
        (should (string= (plist-get res :status) "success"))
        (should (equal (plist-get res :snippets) '("deftest" "defun"))))
      
      ;; 2. Cenário: Inspecionar um existente
      (let ((res (+carlos/magent-tool-snippet-expand '(:name "deftest" :action "inspect"))))
        (should (string= (plist-get res :status) "success"))
        (should (string-match-p "ert-deftest" (plist-get res :template))))
      
      ;; 3. Cenário: Inspecionar inexistente
      (let ((res (+carlos/magent-tool-snippet-expand '(:name "inexistente" :action "inspect"))))
        (should (string= (plist-get res :status) "error")))
      
      ;; 4. Cenário: Inserir snippet
      (let ((res (+carlos/magent-tool-snippet-expand '(:name "defun" :action "insert"))))
        (should (string= (plist-get res :status) "success"))
        (should (eq tempel-inserted-sym 'defun))))))

(ert-deftest myemacs-driver-tools-catalog-registered ()
  "Garante que as 3 ferramentas curadas estão registradas no Magent."
  (skip-unless (require 'gptel nil t))
  (skip-unless (require 'magent-tools nil t))
  (should (magent-tools-catalog-entry "flycheck_errors"))
  (should (magent-tools-catalog-entry "lsp_navigation"))
  (should (magent-tools-catalog-entry "snippet_expand")))

(provide 'magent-driver-test)
;;; magent-driver-test.el ends here
