;;; boot-test.el --- Boot/sanity regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Garante que o init.el carrega todos os módulos e que as invariantes do
;; Emacs 30 (gotcha do `defvar' sem INITVALUE) continuam valendo.

;;; Code:

(require 'ert)

(ert-deftest myemacs-boot-all-modules-loaded ()
  (dolist (feature '(custom-core custom-ui custom-writing custom-completion
                      custom-files custom-term custom-keybindings custom-lang
                      custom-markdown custom-org custom-42 custom-ai
                      custom-knowledge custom-git custom-dashboard))
    (should (featurep feature))))

(ert-deftest myemacs-boot-forward-decls-bound ()
  (dolist (var '(gptel-backend gptel-model gptel-directives gptel-agent-dirs))
    (should (boundp var))))

(ert-deftest myemacs-boot-lisp-in-load-path ()
  (should (member (expand-file-name "lisp" user-emacs-directory) load-path)))

(ert-deftest myemacs-boot-git-root ()
  (require 'vc-git nil t)
  (should (vc-git-root default-directory)))

(ert-deftest myemacs-boot-no-custom-warnings ()
  "Garante que nenhum warning relacionado a custom-* ou +carlos/ foi gerado no boot."
  (let ((warnings-buf (get-buffer "*Warnings*")))
    (when warnings-buf
      (with-current-buffer warnings-buf
        (let ((content (buffer-string)))
          ;; Garante que nenhum warning venha dos nossos arquivos de configuração
          (should-not (or (string-match-p "custom-" content)
                          (string-match-p "\\+carlos/" content))))))))

(ert-deftest myemacs-boot-no-lisp-errors ()
  "Verifica se o buffer *Messages* não contém indícios de erros ocultos de Lisp dos nossos módulos."
  (with-current-buffer "*Messages*"
    (save-excursion
      (goto-char (point-min))
      ;; Buscamos erros severos como void-variable ou void-function
      (should-not (re-search-forward "\\(void-function\\|void-variable\\|Symbol’s value as variable is void\\|Symbol’s function definition is void\\)" nil t)))))

(provide 'boot-test)
;;; boot-test.el ends here
