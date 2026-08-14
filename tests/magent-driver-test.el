;;; magent-driver-test.el --- Tests for curated Magent Driver tools (Etapa C) -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for flycheck_errors, lsp_navigation, and snippet_expand tools.
;; Os handlers seguem o contrato de invocação do magent: argumentos posicionais
;; (na ordem do argspec, sem o arg display-only "reason") e retorno de um
;; `magent-tool-result' (ou string JSON quando o magent não está carregado).

;;; Code:

(require 'ert)
(require 'json)
(require 'custom-magent)

(defun myemacs-driver-result-output (res)
  "Extrai o output (string) de RES — struct `magent-tool-result' ou string."
  (if (and (fboundp 'magent-tool-result-p) (magent-tool-result-p res))
      (magent-tool-result-output-string res)
    (if (stringp res) res (format "%s" res))))

(ert-deftest myemacs-driver-flycheck-errors-handler ()
  "Garante que `+carlos/magent-tool-flycheck-errors` retorna resultado válido."
  (let ((out (myemacs-driver-result-output
              (+carlos/magent-tool-flycheck-errors nil))))
    (should (string-match-p "\"status\"" out))))

(ert-deftest myemacs-driver-lsp-navigation-missing-symbol ()
  "Garante que `+carlos/magent-tool-lsp-navigation` retorna erro sem símbolo."
  (let ((out (myemacs-driver-result-output
              (+carlos/magent-tool-lsp-navigation nil))))
    (should (string-match-p "obrigatório" out))))

(ert-deftest myemacs-driver-lsp-navigation-symbol-with-no-xref ()
  "Garante que `+carlos/magent-tool-lsp-navigation` trata ausência de xref suavemente."
  (cl-letf (((symbol-function 'xref-find-backend) (lambda () nil)))
    (let* ((out (myemacs-driver-result-output
                 (+carlos/magent-tool-lsp-navigation "test-func")))
           (parsed (json-read-from-string out)))
      (should (equal (alist-get 'status parsed) "info")))))

(ert-deftest myemacs-driver-snippet-expand-handler ()
  "Garante que `+carlos/magent-tool-snippet-expand` responde em todos os cenários."
  (skip-unless (require 'tempel nil t))
  (let ((mock-templates '((deftest "ert-deftest" n "  (should " p ")")
                          (defun "defun" p "()" n "  " p)))
        tempel-inserted-sym)
    (cl-letf (((symbol-function 'tempel--templates) (lambda () mock-templates))
              ((symbol-function 'tempel-insert) (lambda (sym) (setq tempel-inserted-sym sym))))
      ;; 1. Cenário: Listar todos
      (let* ((out (myemacs-driver-result-output
                   (+carlos/magent-tool-snippet-expand nil)))
             (parsed (json-read-from-string out)))
        (should (equal (alist-get 'status parsed) "success"))
        (should (equal (alist-get 'snippets parsed) ["deftest" "defun"])))

      ;; 2. Cenário: Inspecionar um existente
      (let* ((out (myemacs-driver-result-output
                   (+carlos/magent-tool-snippet-expand "deftest" "inspect")))
             (parsed (json-read-from-string out)))
        (should (equal (alist-get 'status parsed) "success"))
        (should (string-match-p "ert-deftest" (alist-get 'template parsed))))

      ;; 3. Cenário: Inspecionar inexistente
      (let ((out (myemacs-driver-result-output
                  (+carlos/magent-tool-snippet-expand "inexistente" "inspect"))))
        (should (string-match-p "não encontrado" out)))

      ;; 4. Cenário: Inserir snippet
      (let* ((out (myemacs-driver-result-output
                   (+carlos/magent-tool-snippet-expand "defun" "insert")))
             (parsed (json-read-from-string out)))
        (should (equal (alist-get 'status parsed) "success"))
        (should (eq tempel-inserted-sym 'defun))))))

(ert-deftest myemacs-driver-tools-catalog-registered ()
  "Garante que as ferramentas curadas estão registradas no Magent."
  (skip-unless (require 'gptel nil t))
  (skip-unless (require 'magent-tools nil t))
  (should (magent-tools-catalog-entry "flycheck_errors"))
  (should (magent-tools-catalog-entry "lsp_navigation"))
  (should (magent-tools-catalog-entry "snippet_expand"))
  (should (magent-tools-catalog-entry "select_model")))

(provide 'magent-driver-test)
;;; magent-driver-test.el ends here
