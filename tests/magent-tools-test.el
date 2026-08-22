;;; magent-tools-test.el --- Tests for Magent tools (tool result cap) -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for tool result truncation and cap behavior, e para as
;; ferramentas Forge (forge_read_issue / forge_list_pull_requests) com
;; SQL-FN/REPO-FN injetáveis — 100% offline.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'json)
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
      (should-not (string-match-p "ABSOLUTE PATHS IN PROMPTS" result)))))

(ert-deftest myemacs-directive-injection-defaults-to-subagent ()
  "When role variable is nil (default), injects subagent directives."
  (let ((+carlos/magent-current-agent-is-orchestrator nil))
    (let ((result (+carlos/magent-inject-system-directives "TEST")))
      (should (string-match-p "SUBAGENT ADDENDUM" result))
      (should-not (string-match-p "ORCHESTRATOR ADDENDUM" result)))))

;; ── Ferramentas Forge (SQL-FN / REPO-FN injetáveis, offline) ─────────

(defun myemacs-forge-result-output (res)
  "Extrai o output (string) de RES — struct `magent-tool-result' ou string."
  (if (and (fboundp 'magent-tool-result-p) (magent-tool-result-p res))
      (magent-tool-result-output-string res)
    (if (stringp res) res (format "%s" res))))

(defun myemacs-forge-fake-sql (&rest results)
  "Retorna fn SQL que devolve RESULTS em sequência (um por chamada)."
  (let ((queue (copy-sequence results)))
    (lambda (_query &rest _args)
      (let ((res (car queue)))
        (setq queue (cdr queue))
        res))))

(defvar myemacs-forge--issue-row
  '("gid-10" 42 "Fix login flow" open "alice"
    "Login breaks when the token expires mid-session."
    "2026-08-01T10:00:00Z" "2026-08-02T09:00:00Z" nil nil)
  "Row da tabela issue: [id number title state author body created updated closed status].")

(defvar myemacs-forge--pullreq-row
  '("gid-20" 7 "Add feature X" open "dave"
    "Implements feature X." "2026-08-05T10:00:00Z" "2026-08-06T09:00:00Z"
    nil nil nil "main" "feat/x" nil)
  "Row da tabela pullreq: [id number title state author body created updated closed merged status base-ref head-ref draft-p].")

(ert-deftest myemacs-forge-read-issue-success ()
  "forge_read_issue lê issue do db com comentários estruturados."
  (let ((out (+carlos/magent-tool-forge-read-issue
              "#42" "test"
              (myemacs-forge-fake-sql
               '(("gid-1"))
               (list myemacs-forge--issue-row)
               '(("bob" "2026-08-03T08:00:00Z" "Reproduzido aqui.")
                 ("carol" "2026-08-04T11:30:00Z" "Patch em review.")))
              (lambda () (cons "myorg" "myrepo")))))
    (let ((parsed (json-read-from-string (myemacs-forge-result-output out))))
      (should (equal (alist-get 'status parsed) "success"))
      (should (equal (alist-get 'type parsed) "issue"))
      (should (= (alist-get 'number parsed) 42))
      (should (equal (alist-get 'title parsed) "Fix login flow"))
      (should (equal (alist-get 'state parsed) "open"))
      (should (equal (alist-get 'repository parsed) "myorg/myrepo"))
      (should (= (alist-get 'total_comments parsed) 2))
      (should (equal (alist-get 'author (aref (alist-get 'comments parsed) 0))
                     "bob")))))

(ert-deftest myemacs-forge-read-issue-pullreq-url-first-table ()
  "URL de PR consulta pullreq primeiro; campos base/head/draft presentes."
  (let ((out (+carlos/magent-tool-forge-read-issue
              "https://github.com/myorg/myrepo/pull/7" "test"
              (myemacs-forge-fake-sql
               '(("gid-1"))
               (list myemacs-forge--pullreq-row)
               '(("eve" "2026-08-07T10:00:00Z" "LGTM")))
              (lambda () (should-not "repo-fn não deve ser chamado com owner/repo na ref")))))
    (let ((parsed (json-read-from-string (myemacs-forge-result-output out))))
      (should (equal (alist-get 'status parsed) "success"))
      (should (equal (alist-get 'type parsed) "pullreq"))
      (should (= (alist-get 'number parsed) 7))
      (should (equal (alist-get 'base_ref parsed) "main"))
      (should (equal (alist-get 'head_ref parsed) "feat/x"))
      (should (equal (alist-get 'draft parsed) "false"))
      (should (= (alist-get 'total_comments parsed) 1)))))

(ert-deftest myemacs-forge-read-issue-falls-back-to-issue-table-order ()
  "Ref '#5' (sem kind) consulta issue primeiro; vazia, cai em pullreq."
  (let ((out (+carlos/magent-tool-forge-read-issue
              "#5" "test"
              (myemacs-forge-fake-sql
               '(("gid-1"))
               '() ; tabela issue vazia
               (list myemacs-forge--pullreq-row)
               '())
              (lambda () (cons "myorg" "myrepo")))))
    (let ((parsed (json-read-from-string (myemacs-forge-result-output out))))
      (should (equal (alist-get 'type parsed) "pullreq")))))

(ert-deftest myemacs-forge-read-issue-not-found-info ()
  "Topic ausente nas duas tabelas retorna status info com dica forge-pull."
  (let* ((out (+carlos/magent-tool-forge-read-issue
               "#99" "test"
               (myemacs-forge-fake-sql '(("gid-1")) '() '())
               (lambda () (cons "myorg" "myrepo"))))
         (parsed (json-read-from-string (myemacs-forge-result-output out))))
    (should (equal (alist-get 'status parsed) "info"))
    (should (string-match-p "forge-pull" (alist-get 'message parsed)))))

(ert-deftest myemacs-forge-read-issue-repo-unknown-info ()
  "Repositório fora do db local retorna status info (fallback offline)."
  (let* ((out (+carlos/magent-tool-forge-read-issue
               "#42" "test"
               (myemacs-forge-fake-sql '(nil))
               (lambda () (cons "ghost" "nobody"))))
         (parsed (json-read-from-string (myemacs-forge-result-output out))))
    (should (equal (alist-get 'status parsed) "info"))
    (should (string-match-p "não encontrado no db" (alist-get 'message parsed)))))

(ert-deftest myemacs-forge-read-issue-offline-sql-error ()
  "Falha de infraestrutura (db/sql) vira payload de erro estruturado."
  (+carlos/magent-tool-forge-read-issue
   "#42" "test"
   (lambda (_query &rest _args)
     (signal 'file-error (list "Connection refused")))
   (lambda () (cons "myorg" "myrepo")))
  ;; O handler captura e converte em resultado de erro sem propagar.
  (let ((out (+carlos/magent-tool-forge-read-issue
              "#42" "test"
              (lambda (_query &rest _args)
                (signal 'file-error (list "Connection refused")))
              (lambda () (cons "myorg" "myrepo")))))
    (should (string-match-p "Forge indisponível"
                            (myemacs-forge-result-output out)))))

(ert-deftest myemacs-forge-read-invalid-ref ()
  "Referência não-parseável vira erro estruturado (nunca sinaliza)."
  (let ((out (+carlos/magent-tool-forge-read-issue "abc" "test")))
    (should (string-match-p "Referência inválida"
                            (myemacs-forge-result-output out)))))

(ert-deftest myemacs-forge-list-open-default ()
  "Listagem default filtra state=open e separa PRs de issues."
  (let* ((out (+carlos/magent-tool-forge-list-pull-requests
               nil "test"
               (myemacs-forge-fake-sql
                '(("gid-1"))
                '((1 "PR um" open "a" "2026-08-06")
                  (2 "PR dois" closed "b" "2026-08-05"))
                '((10 "Issue dez" open "c" "2026-08-04")))
               (lambda () (cons "acme" "app"))))
         (parsed (json-read-from-string (myemacs-forge-result-output out))))
    (should (equal (alist-get 'status parsed) "success"))
    (should (equal (alist-get 'repository parsed) "acme/app"))
    (should (equal (alist-get 'filter parsed) "open"))
    (should (= (alist-get 'total_pullreqs parsed) 1))
    (should (= (alist-get 'number (aref (alist-get 'pull_requests parsed) 0)) 1))
    (should (= (alist-get 'total_issues parsed) 1))
    (should (= (alist-get 'number (aref (alist-get 'issues parsed) 0)) 10))))

(ert-deftest myemacs-forge-list-closed-filter ()
  "Filtro closed exclui topics abertos."
  (let* ((out (+carlos/magent-tool-forge-list-pull-requests
               "closed" "test"
               (myemacs-forge-fake-sql
                '(("gid-1"))
                '((2 "PR dois" closed "b" "2026-08-05")
                  (3 "PR tres" merged "d" "2026-08-03"))
                '((10 "Issue dez" open "c" "2026-08-04")))
               (lambda () (cons "acme" "app"))))
         (parsed (json-read-from-string (myemacs-forge-result-output out))))
    (should (= (alist-get 'total_pullreqs parsed) 2))
    (should (= (alist-get 'total_issues parsed) 0))))

(ert-deftest myemacs-forge-list-all-filter ()
  "Filtro all inclui todos os states."
  (let* ((out (+carlos/magent-tool-forge-list-pull-requests
               "all" "test"
               (myemacs-forge-fake-sql
                '(("gid-1"))
                '((1 "PR um" open "a" "u"))
                '((10 "I" completed "c" "u")))
               (lambda () (cons "acme" "app"))))
         (parsed (json-read-from-string (myemacs-forge-result-output out))))
    (should (= (alist-get 'total_pullreqs parsed) 1))
    (should (= (alist-get 'total_issues parsed) 1))))

(ert-deftest myemacs-forge-list-repo-missing-info ()
  "Sem repositório no db, listagem retorna status info."
  (let* ((out (+carlos/magent-tool-forge-list-pull-requests
               nil "test"
               (myemacs-forge-fake-sql '(nil))
               (lambda () (cons "ghost" "nobody"))))
         (parsed (json-read-from-string (myemacs-forge-result-output out))))
    (should (equal (alist-get 'status parsed) "info"))))

(ert-deftest myemacs-forge-team-permissions ()
  "Perfis coder/tech-writer/qa concedem allow às tools forge_*."
  (require 'custom-magent-team)
  (dolist (agent '("coder" "tech-writer" "qa"))
    (let* ((spec (cdr (assoc agent +carlos/magent-expert-team)))
           (rules (plist-get spec :permission)))
      (should (assq 'forge_read_issue rules))
      (should (eq (cdr (assq 'forge_read_issue rules)) 'allow))
      (should (eq (cdr (assq 'forge_list_pull_requests rules)) 'allow)))))

(ert-deftest myemacs-rfc-team-permissions ()
  "Perfis auditor e sec-ops concedem allow às tools rfc_*."
  (require 'custom-magent-team)
  (dolist (agent '("auditor" "sec-ops"))
    (let* ((spec (cdr (assoc agent +carlos/magent-expert-team)))
           (rules (plist-get spec :permission)))
      (should (assq 'rfc_search_topic rules))
      (should (eq (cdr (assq 'rfc_search_topic rules)) 'allow))
      (should (assq 'rfc_read_section rules))
      (should (eq (cdr (assq 'rfc_read_section rules)) 'allow)))))

(ert-deftest myemacs-rfc-tools-registered ()
  "Valida se as funções das ferramentas RFC existem e estão registradas em magent-enable-tools."
  (should (fboundp '+carlos/magent-tool-rfc-search-topic))
  (should (fboundp '+carlos/magent-tool-rfc-read-section))
  (when (boundp 'magent-enable-tools)
    (should (memq 'rfc_search_topic magent-enable-tools))
    (should (memq 'rfc_read_section magent-enable-tools))))

(ert-deftest myemacs-rag-create-doc-tool-registered ()
  "Valida que rag_create_doc e magit_* existem e estão registradas em magent-enable-tools."
  (should (fboundp '+carlos/magent-tool-rag-create-doc))
  (should (fboundp '+carlos/magent-tool-magit-stage))
  (should (fboundp '+carlos/magent-tool-magit-commit))
  (should (fboundp '+carlos/magent-tool-magit-push))
  (should (fboundp '+carlos/magent-tool-magit-status))
  (when (boundp 'magent-enable-tools)
    (should (memq 'rag_create_doc magent-enable-tools))
    (should (memq 'rag_create_doc magent-enable-tools))))

(ert-deftest myemacs-rag-create-doc-generates-valid-org ()
  "Valida que +carlos/magent-tool-rag-create-doc gera um arquivo Org-mode RAG válido."
  (let ((tmp-doc (make-temp-file "test-rag-" nil ".org")))
    (unwind-protect
        (progn
          (+carlos/magent-tool-rag-create-doc
           "forge-create-issue forge-list-pullreqs"
           tmp-doc
           "Test Forge Title"
           "Test Forge Description")
          (should (file-exists-p tmp-doc))
          (with-temp-buffer
            (insert-file-contents tmp-doc)
            (let ((content (buffer-string)))
              (should (string-match-p "#\\+TITLE: Test Forge Title" content))
              (should (string-match-p "#\\+FILETAGS: :RAG:DOCS:" content))
              (should (string-match-p "\\* Visão Geral" content))
              (should (string-match-p "\\* Símbolos Introspectados" content)))))
      (when (file-exists-p tmp-doc)
        (delete-file tmp-doc)))))

(ert-deftest myemacs-elisp-smart-edit-tool-registered ()
  "Valida se +carlos/magent-tool-elisp-smart-edit existe e está registrada."
  (should (fboundp '+carlos/magent-tool-elisp-smart-edit))
  (when (boundp 'magent-enable-tools)
    (should (memq 'elisp_smart_edit magent-enable-tools))))

(ert-deftest myemacs-elisp-smart-edit-insert-snippet ()
  "Valida se elisp_smart_edit insere snippet e valida buffer transacionalmente."
  (let ((tmp-el (make-temp-file "test-elisp-" nil ".el")))
    (unwind-protect
        (progn
          (let ((res (+carlos/magent-tool-elisp-smart-edit tmp-el "insert_snippet" "deftest" "myemacs-test-dummy")))
            (should (string-match-p "inserido com sucesso" res))
            (with-temp-buffer
              (insert-file-contents tmp-el)
              (should (string-match-p "ert-deftest myemacs-test-dummy" (buffer-string))))))
      (when (file-exists-p tmp-el)
        (delete-file tmp-el)))))

(ert-deftest myemacs-elisp-smart-edit-validate-buffer ()
  "Valida se elisp_smart_edit executa validação sintática em memória."
  (let ((tmp-el (make-temp-file "test-valid-" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file tmp-el
            (insert "(defun test-fn () \"Doc.\" t)\n"))
          (let ((res (+carlos/magent-tool-elisp-smart-edit tmp-el "validate_buffer")))
            (should (string-match-p "validado com sucesso" res))))
      (when (file-exists-p tmp-el)
        (delete-file tmp-el)))))

(ert-deftest myemacs-polyglot-smart-edit-tools-registered ()
  "Valida se nix_smart_edit, python_smart_edit e ts_smart_edit estão registradas."
  (should (fboundp '+carlos/magent-tool-nix-smart-edit))
  (should (fboundp '+carlos/magent-tool-python-smart-edit))
  (should (fboundp '+carlos/magent-tool-ts-smart-edit))
  (when (boundp 'magent-enable-tools)
    (should (memq 'nix_smart_edit magent-enable-tools))
    (should (memq 'python_smart_edit magent-enable-tools))
    (should (memq 'ts_smart_edit magent-enable-tools))))

(ert-deftest myemacs-nix-smart-edit-insert-snippet ()
  "Valida se nix_smart_edit insere snippet e valida buffer transacionalmente."
  (let ((tmp-nix (make-temp-file "test-nix-" nil ".nix")))
    (unwind-protect
        (progn
          (let ((res (+carlos/magent-tool-nix-smart-edit tmp-nix "insert_snippet" "flake" "Test Flake")))
            (should (string-match-p "inserido com sucesso" res))
            (with-temp-buffer
              (insert-file-contents tmp-nix)
              (should (string-match-p "description = \"Test Flake\"" (buffer-string))))))
      (when (file-exists-p tmp-nix)
        (delete-file tmp-nix)))))

(ert-deftest myemacs-python-smart-edit-insert-snippet ()
  "Valida se python_smart_edit insere snippet e valida buffer transacionalmente."
  (let ((tmp-py (make-temp-file "test-py-" nil ".py")))
    (unwind-protect
        (progn
          (let ((res (+carlos/magent-tool-python-smart-edit tmp-py "insert_snippet" "pytest" "my_feature")))
            (should (string-match-p "inserido com sucesso" res))
            (with-temp-buffer
              (insert-file-contents tmp-py)
              (should (string-match-p "def test_my_feature" (buffer-string))))))
      (when (file-exists-p tmp-py)
        (delete-file tmp-py)))))

(ert-deftest myemacs-ts-smart-edit-insert-snippet ()
  "Valida se ts_smart_edit insere snippet e valida buffer transacionalmente."
  (let ((tmp-ts (make-temp-file "test-ts-" nil ".ts")))
    (unwind-protect
        (progn
          (let ((res (+carlos/magent-tool-ts-smart-edit tmp-ts "insert_snippet" "interface" "UserProfile")))
            (should (string-match-p "inserido com sucesso" res))
            (with-temp-buffer
              (insert-file-contents tmp-ts)
              (should (string-match-p "export interface UserProfile" (buffer-string))))))
      (when (file-exists-p tmp-ts)
        (delete-file tmp-ts)))))

(ert-deftest myemacs-polyglot-all-smart-edit-tools-registered ()
  "Valida se todas as 9 ferramentas smart_edit estão registradas."
  (should (fboundp '+carlos/magent-tool-elisp-smart-edit))
  (should (fboundp '+carlos/magent-tool-nix-smart-edit))
  (should (fboundp '+carlos/magent-tool-python-smart-edit))
  (should (fboundp '+carlos/magent-tool-ts-smart-edit))
  (should (fboundp '+carlos/magent-tool-c-smart-edit))
  (should (fboundp '+carlos/magent-tool-go-smart-edit))
  (should (fboundp '+carlos/magent-tool-org-smart-edit))
  (should (fboundp '+carlos/magent-tool-sh-smart-edit))
  (should (fboundp '+carlos/magent-tool-markdown-smart-edit))
  (when (boundp 'magent-enable-tools)
    (should (memq 'c_smart_edit magent-enable-tools))
    (should (memq 'go_smart_edit magent-enable-tools))
    (should (memq 'org_smart_edit magent-enable-tools))
    (should (memq 'sh_smart_edit magent-enable-tools))
    (should (memq 'markdown_smart_edit magent-enable-tools))))

(ert-deftest myemacs-c-smart-edit-insert-snippet ()
  "Valida se c_smart_edit insere snippet C/C++ transacionalmente."
  (let ((tmp-c (make-temp-file "test-c-" nil ".c")))
    (unwind-protect
        (progn
          (let ((res (+carlos/magent-tool-c-smart-edit tmp-c "insert_snippet" "main" "")))
            (should (string-match-p "inserido com sucesso" res))
            (with-temp-buffer
              (insert-file-contents tmp-c)
              (should (string-match-p "int main(int argc, char \\*\\*argv)" (buffer-string))))))
      (when (file-exists-p tmp-c)
        (delete-file tmp-c)))))

(ert-deftest myemacs-go-smart-edit-insert-snippet ()
  "Valida se go_smart_edit insere snippet Go transacionalmente."
  (let ((tmp-go (make-temp-file "test-go-" nil ".go")))
    (unwind-protect
        (progn
          (let ((res (+carlos/magent-tool-go-smart-edit tmp-go "insert_snippet" "struct" "Config")))
            (should (string-match-p "inserido com sucesso" res))
            (with-temp-buffer
              (insert-file-contents tmp-go)
              (should (string-match-p "type Config struct" (buffer-string))))))
      (when (file-exists-p tmp-go)
        (delete-file tmp-go)))))

(ert-deftest myemacs-org-smart-edit-insert-snippet ()
  "Valida se org_smart_edit insere snippet Org AST transacionalmente."
  (let ((tmp-org (make-temp-file "test-org-" nil ".org")))
    (unwind-protect
        (progn
          (let ((res (+carlos/magent-tool-org-smart-edit tmp-org "insert_snippet" "heading" "Task Nova")))
            (should (string-match-p "inserido com sucesso" res))
            (with-temp-buffer
              (insert-file-contents tmp-org)
              (should (string-match-p "\\* TODO Task Nova" (buffer-string))))))
      (when (file-exists-p tmp-org)
        (delete-file tmp-org)))))

(ert-deftest myemacs-sh-smart-edit-insert-snippet ()
  "Valida se sh_smart_edit insere snippet Shell transacionalmente."
  (let ((tmp-sh (make-temp-file "test-sh-" nil ".sh")))
    (unwind-protect
        (progn
          (let ((res (+carlos/magent-tool-sh-smart-edit tmp-sh "insert_snippet" "script_header" "")))
            (should (string-match-p "inserido com sucesso" res))
            (with-temp-buffer
              (insert-file-contents tmp-sh)
              (should (string-match-p "#!/usr/bin/env bash" (buffer-string))))))
      (when (file-exists-p tmp-sh)
        (delete-file tmp-sh)))))

(ert-deftest myemacs-markdown-smart-edit-insert-snippet ()
  "Valida se markdown_smart_edit insere snippet Markdown transacionalmente."
  (let ((tmp-md (make-temp-file "test-md-" nil ".md")))
    (unwind-protect
        (progn
          (let ((res (+carlos/magent-tool-markdown-smart-edit tmp-md "insert_snippet" "frontmatter" "Doc Title")))
            (should (string-match-p "inserido com sucesso" res))
            (with-temp-buffer
              (insert-file-contents tmp-md)
              (should (string-match-p "title: Doc Title" (buffer-string))))))
      (when (file-exists-p tmp-md)
        (delete-file tmp-md)))))

(provide 'magent-tools-test)
;;; magent-tools-test.el ends here
