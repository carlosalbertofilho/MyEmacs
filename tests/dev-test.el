;;; dev-test.el --- Tests for custom-dev.el -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for interactive Elisp development features: ERT runners,
;; AI test generation, REPL scratch blocks, and keybindings.

;;; Code:

(require 'ert)
(require 'custom-dev)

(ert-deftest myemacs-dev-commands-exist ()
  "Garante que todos os comandos interativos do `custom-dev.el' existem."
  (should (fboundp '+carlos/ielm-open))
  (should (fboundp '+carlos/ert-run-buffer))
  (should (fboundp '+carlos/ert-run-test-at-point))
  (should (fboundp '+carlos/ert-generate-tests))
  (should (fboundp '+carlos/insert-repl-block))
  (should (fboundp '+carlos/toggle-debug-on-error))
  (should (fboundp '+carlos/debug-region-with-ai)))

(ert-deftest myemacs-dev-prompts-defined ()
  "Verifica se os prompts centralizados estão declarados e contêm diretrizes essenciais."
  (should (boundp '+carlos/elisp-ert-prompt))
  (should (boundp '+carlos/elisp-debug-prompt))
  (should (string-match-p "myemacs-" +carlos/elisp-ert-prompt))
  (should (string-match-p "should-error" +carlos/elisp-ert-prompt))
  (should (string-match-p "REPL" +carlos/elisp-debug-prompt)))

(ert-deftest myemacs-dev-binds ()
  "Garante que os atalhos com prefixo `C-c D' estão configurados."
  (should (eq (lookup-key (current-global-map) (kbd "C-c D r")) #'+carlos/ielm-open))
  (should (eq (lookup-key (current-global-map) (kbd "C-c D t")) #'+carlos/ert-run-buffer))
  (should (eq (lookup-key (current-global-map) (kbd "C-c D T")) #'+carlos/ert-run-test-at-point))
  (should (eq (lookup-key (current-global-map) (kbd "C-c D e")) #'+carlos/ert-generate-tests))
  (should (eq (lookup-key (current-global-map) (kbd "C-c D b")) #'+carlos/insert-repl-block))
  (should (eq (lookup-key (current-global-map) (kbd "C-c D d")) #'+carlos/toggle-debug-on-error))
  (should (eq (lookup-key (current-global-map) (kbd "C-c D a")) #'+carlos/debug-region-with-ai)))

(ert-deftest myemacs-dev-local-elisp-binds ()
  "Garante que os atalhos locais no `emacs-lisp-mode-map' estão mapeados."
  (require 'lisp-mode)
  (should (eq (lookup-key emacs-lisp-mode-map (kbd "C-c C-c")) #'+carlos/ert-run-buffer))
  (should (eq (lookup-key emacs-lisp-mode-map (kbd "C-c C-t")) #'+carlos/ert-run-test-at-point))
  (should (eq (lookup-key emacs-lisp-mode-map (kbd "C-c C-e")) #'+carlos/ert-generate-tests))
  (should (eq (lookup-key emacs-lisp-mode-map (kbd "C-c C-b")) #'+carlos/insert-repl-block)))

(ert-deftest myemacs-dev-insert-repl-block ()
  "Testa a inserção do bloco `(when nil ...)` para scratch REPL."
  (with-temp-buffer
    (emacs-lisp-mode)
    (+carlos/insert-repl-block)
    (should (string-match-p "(when nil ;; REPL scratch" (buffer-string)))))

(provide 'dev-test)
;;; dev-test.el ends here
