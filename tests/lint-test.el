;;; lint-test.el --- Tests for native linters (custom-magent-lint) -*- lexical-binding: t; -*-

;;; Commentary:
;; Testes ERT para os linters nativos: defun-parens e arity.

;;; Code:

(require 'ert)

(ert-deftest myemacs-lint-native-passes ()
  "Lint-native passa no diretório lisp/ do repo sem erros."
  (let ((results (+carlos/magent-lint-directory
                  (expand-file-name "lisp" user-emacs-directory))))
    (should-not results)))

(ert-deftest myemacs-lint-defun-parens-ok ()
  "defun-parens não reporta erros em código válido."
  (with-temp-buffer
    (insert "(defun foo () (message \"hello\"))\n(defun bar () (message \"world\"))\n")
    (emacs-lisp-mode)
    (let ((errors (+carlos/magent-lint-defun-parens-in-buffer)))
      (should-not errors))))

(ert-deftest myemacs-lint-defun-parens-catches-broken ()
  "defun-parens detecta defun com parênteses não fechados."
  (with-temp-buffer
    (insert "(defun foo () (message \"hello\"))\n(defun bar () (message \"world\")\n")
    (emacs-lisp-mode)
    (let ((errors (+carlos/magent-lint-defun-parens-in-buffer)))
      (should errors)
      (should (= 1 (length errors))))))

(ert-deftest myemacs-lint-arity-ok ()
  "arity linter não reporta erros em chamadas válidas."
  (with-temp-buffer
    (insert "(buffer-string)\n")
    (emacs-lisp-mode)
    (let ((err (+carlos/magent-lint-arity-in-buffer)))
      (should-not err))))

(ert-deftest myemacs-lint-arity-catches-buffer-string-args ()
  "arity linter detecta (buffer-string buf) com argumento."
  (with-temp-buffer
    (insert "(defun foo (buf) (buffer-string buf))\n")
    (emacs-lisp-mode)
    (let ((err (+carlos/magent-lint-arity-in-buffer)))
      (should err)
      (should (string-match-p "buffer-string" err)))))

(provide 'lint-test)
;;; lint-test.el ends here
