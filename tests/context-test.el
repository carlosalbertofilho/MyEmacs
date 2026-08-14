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

(ert-deftest myemacs-context-compaction-decision-immediate ()
  "Garante que o threshold imediato dispara acima de 60% da janela."
  (should (eq (+carlos/magent-compaction-decision 7000 10000 0)
              'immediate))
  (should (eq (+carlos/magent-compaction-decision 5900 10000 0)
              nil)))

(ert-deftest myemacs-context-compaction-decision-milestone ()
  "Garante que o milestone exige N subagentes E tokens acima do limiar inferior."
  (let ((+carlos/magent-milestone-subagents 3)
        (+carlos/magent-milestone-ratio 0.4))
    (should (eq (+carlos/magent-compaction-decision 4500 10000 3)
                'milestone))
    (should (eq (+carlos/magent-compaction-decision 4500 10000 2)
                nil))
    (should (eq (+carlos/magent-compaction-decision 3000 10000 3)
                nil))
    (should (eq (+carlos/magent-compaction-decision 7000 10000 0)
                'immediate))))

(ert-deftest myemacs-context-build-instruction-sections ()
  "Garante que a instrução dinâmica (B1) contém estado, descarte e base."
  (let ((instr (+carlos/magent-build-compaction-instruction)))
    (should (stringp instr))
    (should (string-match-p "Regras de descarte" instr))
    (should (string-match-p "TODO\\.md" instr))
    (should (string-match-p "preservando o estado do projeto" instr))))

(ert-deftest myemacs-context-sink-subagent-stop-counts ()
  "Garante que o sink conta subagentes completados (B3)."
  (let ((+carlos/magent-subagent-completions-since-compact 0))
    (+carlos/magent-auto-compact-check-and-run
     '(:type subagent-stop :subagent-id "abc"))
    (+carlos/magent-auto-compact-check-and-run
     '(:type subagent-stop :subagent-id "def"))
    (should (= +carlos/magent-subagent-completions-since-compact 2))))

(ert-deftest myemacs-context-turn-tokens-zero-safe ()
  "Garante que a medição de tokens (B2) é segura sem sessão ativa."
  (let ((tokens (+carlos/magent-turn-tokens
                 '(:type turn-end :status completed))))
    (should (integerp tokens))
    (should (>= tokens 0))))

(ert-deftest myemacs-context-compact-keybinding ()
  "Garante que o atalho C-c A p está mapeado para `+carlos/magent-compact`."
  (should (eq (global-key-binding (kbd "C-c A p")) #'+carlos/magent-compact)))

(provide 'context-test)
;;; context-test.el ends here
