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

(provide 'boot-test)
;;; boot-test.el ends here
