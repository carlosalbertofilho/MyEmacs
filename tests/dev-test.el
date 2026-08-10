;;; dev-test.el --- custom-dev (REPL/ERT runner) regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifica binds do prefixo C-c D (Dev), comandos existem, e que os helpers
;; de selector ERT funcionam. Não roda eval-buffer (só verifica binds).

;;; Code:
(require 'ert)

(ert-deftest myemacs-dev-commands-exist ()
  (should (commandp '+carlos/ielm-open))
  (should (commandp '+carlos/ert-run-buffer))
  (should (commandp '+carlos/ert-run-test-at-point))
  (should (commandp '+carlos/toggle-debug-on-error))
  (should (commandp '+carlos/debug-region-with-ai)))

(ert-deftest myemacs-dev-binds ()
  (should (eq (key-binding (kbd "C-c D r")) '+carlos/ielm-open))
  (should (eq (key-binding (kbd "C-c D t")) '+carlos/ert-run-buffer))
  (should (eq (key-binding (kbd "C-c D T")) '+carlos/ert-run-test-at-point))
  (should (eq (key-binding (kbd "C-c D d")) '+carlos/toggle-debug-on-error))
  (should (eq (key-binding (kbd "C-c D a")) '+carlos/debug-region-with-ai)))

(ert-deftest myemacs-dev-local-elisp-binds ()
  (require 'lisp-mode nil t)
  (should (eq (lookup-key emacs-lisp-mode-map (kbd "C-c C-c"))
              '+carlos/ert-run-buffer))
  (should (eq (lookup-key emacs-lisp-mode-map (kbd "C-c C-t"))
              '+carlos/ert-run-test-at-point)))

(ert-deftest myemacs-dev-selector-from-file ()
  (should (equal "myemacs-spell-" (+carlos/ert-selector-for-file "spell-test.el")))
  (should (equal "myemacs-ai-" (+carlos/ert-selector-for-file "ai-test.el"))))

(ert-deftest myemacs-dev-test-at-point-finds-test ()
  (with-temp-buffer
    (insert ";;; x.el --- test -*- lexical-binding: t; -*-\n\n(require 'ert)\n\n(ert-deftest myemacs-dev-dummy ()\n  (should t))\n")
    ;; Sem ert-deftest antes do ponto -> nil
    (goto-char (point-min))
    (should-not (+carlos/ert-test-at-point))
    ;; Dentro do corpo do ert-deftest -> nome encontrado
    (goto-char (point-max))
    (search-backward "(ert-deftest")
    (forward-line 1)
    (should (eq (+carlos/ert-test-at-point) 'myemacs-dev-dummy))))

(ert-deftest myemacs-dev-no-collisions-kept-prefixes ()
  "Prefixos protegidos por fases anteriores continuam intactos."
  (should (eq (key-binding (kbd "C-c r")) '+carlos/ai-rag-ingest))
  (should (eq (key-binding (kbd "C-c t")) 'vterm)))

(provide 'dev-test)
;;; dev-test.el ends here
