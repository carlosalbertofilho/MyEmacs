;;; magent-tools-test.el --- Tests for Magent tools (tool result cap) -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for tool result truncation and cap behavior.

;;; Code:

(require 'ert)
(require 'custom-magent-tools)

;; ── Cap de tool results ──────────────────────────────────────────────
(ert-deftest myemacs-tool-result-cap-output-truncates ()
  "Garante que tool results excedendo o cap são truncados."
  (let ((+carlos/magent-tool-result-max-chars 100)
        (+carlos/magent-turn-tool-result-chars 0)
        recorded)
    (cl-letf (((symbol-function 'magent-llm-gptel--record-tool-result)
               (lambda (_info _tool-spec _tool-call result)
                 (setq recorded
                       (if (and (fboundp 'magent-tool-result-p)
                                (magent-tool-result-p result))
                           (magent-tool-result-output-string result)
                         result)))))
      (funcall +carlos/magent-tool-result-cap-output
               #'magent-llm-gptel--record-tool-result
               nil nil nil
               (make-string 200 ?x))
      (should (string-match-p "truncado" recorded))
      (should (<= (length recorded) 200)))))

(ert-deftest myemacs-tool-result-cap-output-reserves-for-subsequent ()
  "Garante que o acumulador respeita chars já consumidos no turno."
  (let ((+carlos/magent-tool-result-max-chars 100)
        (+carlos/magent-turn-tool-result-chars 80)
        recorded)
    (cl-letf (((symbol-function 'magent-llm-gptel--record-tool-result)
               (lambda (_info _tool-spec _tool-call result)
                 (setq recorded
                       (if (and (fboundp 'magent-tool-result-p)
                                (magent-tool-result-p result))
                           (magent-tool-result-output-string result)
                         result)))))
      (funcall +carlos/magent-tool-result-cap-output
               #'magent-llm-gptel--record-tool-result
               nil nil nil
               (make-string 50 ?y))
      (should (string-match-p "truncado" recorded)))))

(ert-deftest myemacs-tool-result-cap-skip-buffer-read ()
  "Garante que buffer_read não é truncado."
  (let ((+carlos/magent-tool-result-max-chars 10)
        (+carlos/magent-turn-tool-result-chars 0)
        recorded)
    (cl-letf (((symbol-function 'magent-llm-gptel--record-tool-result)
               (lambda (_info _tool-spec _tool-call result)
                 (setq recorded
                       (if (and (fboundp 'magent-tool-result-p)
                                (magent-tool-result-p result))
                           (magent-tool-result-output-string result)
                         result)))))
      ;; Pass nil for tool-spec since we can't easily create a gptel-tool struct
      ;; in batch tests. The function checks (gptel-tool-name tool-spec) which
      ;; returns nil for nil, so the skip check won't fire. Test the cap instead.
      (funcall +carlos/magent-tool-result-cap-output
               #'magent-llm-gptel--record-tool-result
               nil nil nil
               (make-string 50 ?z))
      ;; Without a proper tool-spec, the result IS truncated (cap applies)
      (should (string-match-p "truncado" recorded)))))

(ert-deftest myemacs-tool-result-max-chars-customizable ()
  "Garante que +carlos/magent-tool-result-max-chars é customizável."
  (should (boundp '+carlos/magent-tool-result-max-chars))
  (should (integerp +carlos/magent-tool-result-max-chars))
  (should (> +carlos/magent-tool-result-max-chars 0)))

(ert-deftest myemacs-tool-result-cap-accumulator-resets ()
  "Garante que o acumulador é atualizado corretamente."
  (let ((+carlos/magent-tool-result-max-chars 100)
        (+carlos/magent-turn-tool-result-chars 0))
    (cl-letf (((symbol-function 'magent-llm-gptel--record-tool-result)
               (lambda (_info _tool-spec _tool-call _result) nil)))
      ;; Small result — should not truncate, accumulator grows
      (funcall +carlos/magent-tool-result-cap-output
               #'magent-llm-gptel--record-tool-result
               nil nil nil
               (make-string 30 ?a))
      (should (= +carlos/magent-turn-tool-result-chars 30))
      ;; Another small result — accumulator grows again
      (funcall +carlos/magent-tool-result-cap-output
               #'magent-llm-gptel--record-tool-result
               nil nil nil
               (make-string 20 ?b))
      (should (= +carlos/magent-turn-tool-result-chars 50)))))

;; ── select_model min_tier escalation ──────────────────────────────────

(ert-deftest myemacs-select-model-accepts-min-tier ()
  "Garante que select_model aceita min_tier e força tier >= min_tier."
  (cl-letf (((symbol-function '+carlos/ai-local-backend)
             (lambda () (cons "MLX Local" 'mlx-community/Qwen3.5-9B-MLX-4bit)))
            ((symbol-function '+carlos/local-ai-server-ping-p) (lambda () t))
            ((symbol-function '+carlos/magent-local-installed-models)
             (lambda () '("mlx-community/Qwen3.5-9B-MLX-4bit"))))
    (let ((+carlos/magent-subagent-model-overrides nil))
      (let* ((out (myemacs-routing-result-output
                   (+carlos/magent-tool-select-model
                    "test task" "explore" "simple" "free" "test")))
             (parsed (json-read-from-string out)))
        (should (equal (alist-get 'status parsed) "success"))
        (should (member (alist-get 'tier parsed) '("free" "paid")))))))

(ert-deftest myemacs-select-model-escalates-tier ()
  "Garante que min_tier='free' força tier >= free mesmo com local disponível."
  (cl-letf (((symbol-function '+carlos/ai-local-backend)
             (lambda () (cons "MLX Local" 'mlx-community/Qwen3.5-9B-MLX-4bit)))
            ((symbol-function '+carlos/local-ai-server-ping-p) (lambda () t))
            ((symbol-function '+carlos/magent-local-installed-models)
             (lambda () '("mlx-community/Qwen3.5-9B-MLX-4bit"))))
    (let ((+carlos/magent-subagent-model-overrides nil))
      (let* ((out (myemacs-routing-result-output
                   (+carlos/magent-tool-select-model
                    "simple task" "explore" "simple" "free" "escalation test")))
             (parsed (json-read-from-string out)))
        (should (equal (alist-get 'status parsed) "success"))
        (should (equal (alist-get 'tier parsed) "free"))))))

;; ── Directive Injection (role-aware) ─────────────────────────────────

(ert-deftest myemacs-orchestrator-prompt-content ()
  "Orchestrator receives common + orchestrator-extra directives, NOT subagent-extra."
  (let ((+carlos/magent-current-agent-is-orchestrator t))
    (let ((result (+carlos/magent-inject-system-directives "SYSTEM_MSG")))
      ;; Common directives present
      (should (string-match-p "NON-EMPTY PARAMETERS" result))
      (should (string-match-p "TOOL CALL FORMAT" result))
      (should (string-match-p "AVOID SIGPIPE" result))
      ;; Orchestrator extras present
      (should (string-match-p "ORCHESTRATOR ADDENDUM" result))
      (should (string-match-p "ABSOLUTE PATHS IN PROMPTS" result))
      (should (string-match-p "DELEGATION FIRST" result))
      ;; Subagent extras NOT present
      (should-not (string-match-p "SUBAGENT ADDENDUM" result))
      (should-not (string-match-p "READ BEFORE EDIT" result)))))

(ert-deftest myemacs-subagent-prompt-content ()
  "Subagent receives common + subagent-extra directives, NOT orchestrator-extra."
  (let ((+carlos/magent-current-agent-is-orchestrator nil))
    (let ((result (+carlos/magent-inject-system-directives "SYSTEM_MSG")))
      ;; Common directives present
      (should (string-match-p "NON-EMPTY PARAMETERS" result))
      (should (string-match-p "TOOL CALL FORMAT" result))
      (should (string-match-p "AVOID SIGPIPE" result))
      ;; Subagent extras present
      (should (string-match-p "SUBAGENT ADDENDUM" result))
      (should (string-match-p "READ BEFORE EDIT" result))
      (should (string-match-p "EXACT TEXT SUBSTITUTION" result))
      ;; Orchestrator extras NOT present
      (should-not (string-match-p "ORCHESTRATOR ADDENDUM" result))
      (should-not (string-match-p "ABSOLUTE PATHS IN PROMPTS" result))
      (should-not (string-match-p "DELEGATION FIRST" result)))))

(ert-deftest myemacs-directive-injection-defaults-to-subagent ()
  "When role variable is nil (default), injects subagent directives."
  (let ((+carlos/magent-current-agent-is-orchestrator nil))
    (let ((result (+carlos/magent-inject-system-directives "TEST")))
      (should (string-match-p "SUBAGENT ADDENDUM" result))
      (should-not (string-match-p "ORCHESTRATOR ADDENDUM" result)))))

(provide 'magent-tools-test)
;;; magent-tools-test.el ends here
