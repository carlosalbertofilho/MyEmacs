;;; git-test.el --- Git (magit/commit IA) regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifica o fluxo de commit com IA: funções existem e o bind C-c C-g
;; está direto no git-commit-mode-map (não via hook — hook não aplica em
;; batch e só vale para buffers reais).

;;; Code:

(require 'ert)
(require 'git-commit)

(ert-deftest myemacs-git-commit-ia-functions ()
  (should (fboundp '+carlos/gptel-generate-commit-message))
  (should (fboundp '+carlos/gptel-insert-commit-message)))

(ert-deftest myemacs-git-commit-mode-map-bind ()
  (should (eq (lookup-key git-commit-mode-map (kbd "C-c C-g"))
              '+carlos/gptel-insert-commit-message)))

(ert-deftest myemacs-git-magit-commit-ia-transient ()
  (should (fboundp '+carlos/gptel-generate-commit-message)))

(provide 'git-test)
;;; git-test.el ends here
