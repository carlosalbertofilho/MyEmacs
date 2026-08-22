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

(ert-deftest myemacs-boot-daemon-debug-init-no-warnings ()
  "Valida a inicialização em modo daemon com --debug-init e coleta de warnings."
  (let* ((emacs-bin (expand-file-name invocation-name invocation-directory))
         (out-buf (generate-new-buffer " *ert-daemon-out*"))
         (exit-code
          (call-process emacs-bin nil out-buf nil
                        "--daemon=ert-test-daemon"
                        "--debug-init"
                        "--init-directory" user-emacs-directory)))
    (unwind-protect
        (progn
          (should (= exit-code 0))
          (with-current-buffer out-buf
            (let ((output (buffer-string)))
              ;; Garante ausência de erros de duplicação do Elpaca e erros de init.el
              (should-not (string-match-p "Duplicate item ID queued" output))
              (should-not (string-match-p "previously queued as dependency" output))
              (should-not (string-match-p "An error occurred while loading" output))
              (should-not (string-match-p "Wrong type argument: listp" output)))))
      (ignore-errors
        (call-process emacs-bin nil nil nil
                      "--socket-name=ert-test-daemon"
                      "--eval" "(kill-emacs)"))
      (when (buffer-live-p out-buf)
        (kill-buffer out-buf)))))

(provide 'boot-test)
;;; boot-test.el ends here
