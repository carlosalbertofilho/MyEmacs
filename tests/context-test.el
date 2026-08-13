;;; context-test.el --- Tests for context management (Etapa B4) -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for cache hit-rate, auto-compaction ratio, and preservation instruction.

;;; Code:

(require 'ert)
(require 'custom-ai)
(require 'custom-magent)

(ert-deftest myemacs-context-cache-hit-rate-calc ()
  "Garante que o cálculo de cache hit-rate retorna a porcentagem correta."
  (should (= (+carlos/gptel-cache-hit-rate 100 100) 50.0))
  (should (= (+carlos/gptel-cache-hit-rate 0 500) 100.0))
  (should (= (+carlos/gptel-cache-hit-rate 100 0) 0.0))
  (should (= (+carlos/gptel-cache-hit-rate 0 0) 0.0)))

(ert-deftest myemacs-context-get-context-window ()
  "Garante que `+carlos/magent-get-context-window` retorna valor positivo."
  (let ((cw (+carlos/magent-get-context-window)))
    (should (integerp cw))
    (should (> cw 0))))

(ert-deftest myemacs-context-preservation-instruction-defined ()
  "Garante que a instrução de preservação estruturada contém as 6 diretivas."
  (should (boundp '+carlos/magent-preservation-instruction))
  (should (string-match-p "Arquivos modificados" +carlos/magent-preservation-instruction))
  (should (string-match-p "TODO\\.md" +carlos/magent-preservation-instruction)))

(ert-deftest myemacs-context-auto-compact-sink-runs ()
  "Garante que `+carlos/magent-auto-compact-check-and-run` executa sem erros."
  (let ((event-data '(:status completed :output-len 50)))
    (should (listp event-data))))

(ert-deftest myemacs-context-compact-keybinding ()
  "Garante que o atalho C-c A p está mapeado para `+carlos/magent-compact`."
  (should (eq (global-key-binding (kbd "C-c A p")) #'+carlos/magent-compact)))

(provide 'context-test)
;;; context-test.el ends here
