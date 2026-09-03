;;; custom-magent-tools.el --- Magent tools: fixes, directivas e tools curadas -*- lexical-binding: t; -*-

;;; Commentary:
;; Fixes de streaming/schema para backends Gemini, sanitização de paths e
;; parâmetros de tools, directivas de sistema injetadas no system prompt e
;; as ferramentas curadas (flycheck_errors, lsp_navigation, snippet_expand).

;;; Code:

(require 'cl-lib)
(eval-when-compile
  (require 'gptel nil t)
  (require 'forge nil t))
(require 'json)
(require 'seq)
(require 'custom-magent-infra)

(defvar magent-enable-logging)
(defvar magent-enable-tools)
(defvar magent-tools-catalog)
(defvar +carlos/magent-turn-tool-result-chars)
(declare-function magent-tools--failed "magent-tools")
(declare-function magent-agent--compose-system-message "magent-agent")
(declare-function magent-llm-gptel--parse-dsml-tool-calls "magent-llm-gptel")
(declare-function magent-llm-gptel--prepare-textual-continuation "magent-llm-gptel")
(declare-function magent-llm-gptel--emit-tool-call-batch "magent-llm-gptel")
(declare-function magent-llm-gptel--metadata "magent-llm-gptel")
(declare-function magent-llm-gptel--pending-tool-use-p "magent-llm-gptel")
(declare-function magent-llm-gptel--continue-with-user-message "magent-llm-gptel")
(declare-function magent-llm-gptel--managed-info-p "magent-llm-gptel")
(declare-function magent-llm-gptel--sanitize-info "magent-llm-gptel")
(declare-function +carlos/local-ai-server-ping-p "custom-ai")
(declare-function +carlos/ai-local-backend "custom-ai")
(declare-function forge-sql "forge-db")
(declare-function forge-get-repository "forge-core")
(declare-function gptel-get-backend "gptel")
(declare-function gptel-backend-host "gptel")
(declare-function gptel-backend-models "gptel")
(declare-function gptel-backend-protocol "gptel")
(declare-function gptel-tool-name "gptel")
(declare-function gptel--to-string "gptel")
(declare-function tempel-insert "tempel")
(declare-function magent-tool-result-create "magent-protocol")
(declare-function magent-tool-result-output-string "magent-protocol")
(declare-function magent-tool-result-success "magent-protocol")
(declare-function magent-tool-result-status "magent-protocol")
(declare-function magent-tool-result-error "magent-protocol")
(declare-function magent-tool-result-p "magent-protocol")
(declare-function magent-llm-tool-call-event "magent-llm")

;; ── Silenciar *Messages*: filtrar dumps longos (plist de tools / system prompt) ──
;; O Emacs/gptel imprime ocasionalmente plists gigantes (lista de tools, system
;; prompt do agente) via `message'. Suprimimos linhas > 400 chars no *Messages*
;; mas mantemos ERROS (prefixo Error/Warning) sempre visíveis.








;; ── Diagnóstico: Desativar magent-log ──────────────────────────────






;; Desativa variaveis internas de log do magent


;; ── Fix para Gemini: Normalizar nomes de tool calls (símbolo -> string) ──
;; O gptel-gemini retorna os nomes de ferramentas em `:tool-use` como símbolos
;; Lisp (ex.: 'glob, 'read_file). `magent-llm-gptel--handle-tool-use` busca a
;; tool-spec usando (equal (gptel-tool-name ts) name). Como (gptel-tool-name ts)
;; é string ("glob"), (equal "glob" 'glob) retorna nil -> tool-spec fica nil,
;; o Magent ignora a chamada da ferramenta e a requisição expira em 120s.
;; Esta advice sanitiza `info` ANTES de extrair `:tool-use`, convertendo símbolos
;; para strings.


;; ── Fix para Gemini Streaming: Aridade de `gptel--parse-response' ─────
;; A função original `magent-llm-gptel--sanitize-after-parse-response-a' do magent
;; declarava apenas 4 argumentos `(orig-fn backend response info)`. No gptel-gemini,
;; `gptel--parse-response' aceita 5 argumentos (`include-text` opcional).
;; Redefinimos a função original com `&rest args` para que a chamada de
;; `magent-llm-gptel--install-boundary-advice` não recoloque a versão de 4 argumentos.


;; ── Fix: schema da tool wait_agent para backends Gemini ──────────────
;; O argspec `job_ids' do magent declara `:type array` sem `:items`, e o
;; gptel repassa o schema cru ao Gemini, que exige `items' em arrays
;; (erro "properties[job_ids].items: missing field" — quebra TODA chamada
;; Gemini com as tools do Magent). Aplicamos o `:items' via setf na struct
;; gptel-tool após o load (fix do side do config; o source pinado do magent
;; não deve ser editado). O `:items' deve ser `(:type "string")' — string,
;; não símbolo — pois o json-serialize nativo do Emacs 30 rejeita símbolos
;; (erro "wrong-type-argument json-value-p string" na serialização das tools).


;; ── Tool Sanitization & Path Auto-Expansion ──────────────────────────

(defvar +carlos/magent-tool-flycheck-errors nil)
(defvar +carlos/magent-tool-lsp-navigation nil)
(defvar +carlos/magent-tool-snippet-expand nil)
(defvar +carlos/magent-tool-select-model nil)
(defvar +carlos/magent-tool-rag-create-doc nil)
(defvar +carlos/magent-tool-magit-stage nil)
(defvar +carlos/magent-tool-magit-commit nil)
(defvar +carlos/magent-tool-magit-push nil)
(defvar +carlos/magent-tool-magit-status nil)
(defvar +carlos/magent-tool-magit-pull nil)
(defvar +carlos/magent-tool-magit-checkout nil)
(defvar +carlos/magent-tool-magit-diff nil)
(defvar +carlos/magent-tool-magit-log nil)
(defvar +carlos/magent-tool-magit-submodule-list nil)
(defvar +carlos/magent-tool-magit-submodule-update nil)
(defvar +carlos/magent-tool-magit-submodule-add nil)
(defvar +carlos/magent-tool-magit-branch-list nil)
(defvar +carlos/magent-tool-magit-branch-delete nil)
(defvar +carlos/magent-tool-magit-merge nil)
(defvar +carlos/magent-tool-magit-rebase nil)










(defvar +carlos/magent-tool-forge-read-issue nil)
(defvar +carlos/magent-tool-forge-list-pull-requests nil)
(defvar +carlos/magent-tool-forge-create-issue nil)
(defvar +carlos/magent-tool-forge-create-pull-request nil)
(defvar +carlos/magent-tool-forge-post-comment nil)
(defvar +carlos/magent-tool-rfc-search-topic nil)
(defvar +carlos/magent-tool-rfc-read-section nil)

(defvar +carlos/magent-current-agent-is-orchestrator nil
  "Non-nil when the active agent is the orchestrator.
Set dynamically by `+carlos/magent-subagent-apply-profile' before calling
`magent-agent-process'; consumed by `+carlos/magent-inject-system-directives'
to select the correct directive set (orchestrator vs. subagent).")

(defvaralias '+carlos/magent-common-directives '+carlos/magent-system-directives
  "Alias para +carlos/magent-system-directives (compatibilidade de testes).")

(defconst +carlos/magent-system-directives
  "CRITICAL MAGENT TOOL DIRECTIVES:
1. ABSOLUTE PATHS: Use full absolute paths starting with '/' (e.g. '/home/carlosfilho/...').
2. NON-EMPTY PARAMETERS: Do not call write_file or edit_file with empty or missing args.
3. DELEGATION FIRST: When running on small local models, you are the ORCHESTRATOR — do NOT read or edit files directly; delegate to a subagent via 'spawn_agent'. When running on a strong cloud model, you have full access to native reading and smart_edit tools (org_smart_edit, elisp_smart_edit, etc.) and MAY execute single-file changes directly. When delegating, select ONLY registered subagents: 'coder' (Emacs live editing & smart_edit), 'explore' (fast search/read), 'tech-writer' (documentation), 'planner', 'sysadmin', 'qa', 'auditor', 'sec-ops', 'general'. Never invent unregistered agent names.
4. NON-INTERACTIVE SHELL: Avoid interactive shells; git commits must include '-m \"message\"'.
5. SUBAGENT LIFECYCLE (HARD RULE): 'spawn_agent' starts a background job and returns a job id — its result is NOT the answer. After 'spawn_agent', you MUST call 'wait_agent(job_id)' (use the job_id from 'next_action.arguments.job_id') and MUST NOT end your turn until 'wait_agent' returns the subagent's report; if 'wait_agent' reports status 'timeout', call 'wait_agent' again with the same job_id. Always give the subagent a real absolute path (e.g. '/abs/path/file.md') in its prompt — never tell it to analyze a file 'provided' or 'attached', because subagents do not receive the parent's attachments.
6. TOOL CALL FORMAT: Always request tool use through the native structured function-calling mechanism. Tool calls MUST be emitted as native structured function calls in the FINAL response text — NEVER inside reasoning/thinking blocks, NEVER as free-form XML text. Reasoning blocks are never executed, so a tool call written there is silently dropped. If your backend only supports textual tool calls, use EXACTLY this DSML envelope, with nothing else between the tags:
<tool_calls>
<invoke name=\"read_file\">
<parameter name=\"path\">/absolute/path/to/file</parameter>
</invoke>
</tool_calls>
Do NOT use '<tool_call>', '<function=...>', or '<parameter=...>' forms; the runtime only parses the '<tool_calls>'/'<invoke name=...>'/'<parameter name=...>' syntax shown above. After requesting a tool, your next message MUST include the native tool call, not text about calling it.
 7. AVOID SIGPIPE (exit 141): Do not pipe long listings into 'head'/'tail' (e.g. 'find ... | head -50'). Closing the pipe kills the producer with SIGPIPE (exit 141), which the runtime reports as a FAILED tool result. Use 'find ... -maxdepth N' with explicit filters, or 'rg --max-count' instead.
 8. SUBAGENT DELEGATION (HARD RULE): You are the ORCHESTRATOR — you only orchestrate, you do not implement. Keep your context window lean.

   PADE 'SPAWN-AND-FORGE': When tasks are INDEPENDENT (no data dependency between them), spawn MULTIPLE agents BEFORE waiting:
   - Call spawn_agent for Task A, then spawn_agent for Task B, then wait_agent for A, then wait_agent for B.
   - NEVER interleave wait_agent between independent spawns — this wastes context on sequential turns.
   - Example: 'Read file X' and 'Read file Y' → spawn both, then wait for both.

   DELEGATION TRIGGERS (always delegate):
   - Codebase exploration, file analysis, multi-step research
   - Complex file edits (rewrite, refactor, large sections)
   - Content generation beyond 5 lines

   EXCEPTIONS (direct edit allowed):
   - One-line fixes where you just read the exact target line
   - Simple variable renames with grep confirmation

   Subagents run on a stronger cloud model with a larger context window.
   When delegating an edit, tell the subagent to read the target file with 'read_file' first and then edit with exact text copied from the actual file content. NEVER attempt a complex file edit yourself: 'edit_file' requires old_text to match the file byte-for-byte, and the local model hallucinates file content — that is why edits fail with 'old_text not found'.
 9. MODEL SELECTION: Review the MODEL SELECTION MENU appended below. Before calling 'spawn_agent', call 'select_model' with the subagent's task_description and target agent name; the runtime resolves the model from the menu by task complexity and the user's tier cap, and applies it to the subagent automatically. For 'deep' reasoning (refactor, architecture, design, schema, debug, migration, security, plan, review, optimization), you MUST pick a free or paid tier — never the small local model. For 'simple'/'moderate' tasks, prefer the local model when it is ONLINE, then free, then paid. Some agent profiles impose a MINIMUM TIER FLOOR (e.g., paid for coder, sysadmin, planner, auditor, sec-ops, qa) — select_model enforces the floor, so you cannot pick below it for those agents; choose the cheapest model that satisfies the task and the floor. NEVER exceed the tier cap shown in the menu.
   10. SYNTHESIS FORMAT: After receiving subagent results via wait_agent, synthesize findings in ≤3 bullet points in your reply. NEVER paste the full transcript or raw tool output. The subagent's output is for YOUR understanding, not the user's raw view. Include: (a) key findings, (b) file paths modified (if any), (c) decisions made (if any).
 11. SUBAGENT RETRY (INTELLIGENT FALLBACK): When a subagent fails with timeout or model_unavailable error, you MAY retry with a stronger model: call 'select_model' with min-tier='free' (if current was local) or min-tier='paid' (if current was free), then 'spawn_agent' with the same task. Maximum 1 retry per subagent — do not retry if already retried. Do NOT retry context_length_exceeded errors (compact first instead).
 12. BUFFER SELF-HEALING: When user asks to 'fix', 'correct', 'corrija', 'arrume', 'refactor code in this buffer', or 'make this compile', activate the buffer-driver-loop skill. Read the buffer first, make atomic fixes, validate with flycheck_errors after each change, and stop when zero errors remain or after two consecutive fix attempts that make no progress (report remaining diagnostics). Never guess symbol names — resolve with lsp_navigation or describe_elisp_symbol first.
 13. LANGUAGE MATCHING: Always respond and synthesize findings in the SAME language used by the user in their prompt (e.g. Portuguese for Portuguese prompts, English for English prompts).
 14. EXECUTE ON RETRY (HARD RULE): When the user explicitly requests to retry a task or try a specific subagent/model (e.g. 'tente de novo', 'try again', 'use subagent sysadmin'), DO NOT argue, list past failures, or refuse. ALWAYS invoke 'select_model' and 'spawn_agent' immediately to attempt the requested task."
  "Instruções estritas de uso de ferramentas para os modelos do Magent.")


;; ── Role-specific extras ──────────────────────────────────────────────

(defconst +carlos/magent-orchestrator-extra
  "\n\nORCHESTRATOR ADDENDUM:
1. ABSOLUTE PATHS IN PROMPTS (CRITICAL): ALWAYS expand relative paths to absolute paths (starting with '/') before passing them to subagents via spawn_agent. Subagents do NOT inherit the orchestrator's working directory -- they receive only the prompt text. Example: say '/home/carlosfilho/.../file.el' NEVER 'file.el' or 'this file'.
2. DELEGATION FIRST: You are the ORCHESTRATOR -- you do NOT read files directly. Delegate ALL file reading, analysis, and editing to subagents via 'spawn_agent'. The ONLY exception is 'grep' and 'glob' for quick path/name searches."
  "Extra directives injected ONLY into the orchestrator's system prompt.")

(defconst +carlos/magent-subagent-extra
  "\n\nSUBAGENT ADDENDUM (ROLE OVERRIDE):
You are a SUBAGENT EXECUTOR -- you receive a specific task and execute it directly. You are NOT the orchestrator, you do NOT delegate, and you do NOT call spawn_agent or wait_agent.
1. DIRECT EXECUTION: Execute the requested file reading, code editing, or command execution directly using your available tools (read_file, edit_file, buffer_insert, run_command, etc.). Do NOT attempt to delegate.
2. READ BEFORE EDIT: Always use 'read_file' to read the target file before editing. Edit with exact text copied from the actual file content -- NEVER guess or hallucinate file contents.
3. EXACT TEXT SUBSTITUTION: When using edit_file, old_text must match the file byte-for-byte. Copy directly from read_file output. If the edit fails, re-read the file and try again with the correct text.
4. RETURN CLEAR RESULTS: When done, report: (a) what was done, (b) files modified (with absolute paths), (c) any errors encountered. Keep your report concise -- the orchestrator will synthesize for the user.
5. LANGUAGE MATCHING: Always return your findings and reports in the SAME language used by the user in the prompt (e.g. Portuguese for Portuguese prompts).
6. PREFER SMART EDIT TOOLS: Whenever editing code or documents in Elisp, Nix, Python, TS/JS, C/C++, Go, Rust, Org, Shell, or Markdown, PREFER the specialized *_smart_edit tools (elisp_smart_edit, nix_smart_edit, python_smart_edit, ts_smart_edit, c_smart_edit, go_smart_edit, rust_smart_edit, org_smart_edit, sh_smart_edit, markdown_smart_edit) for transactional snippet insertion, symbol refactoring, and in-memory syntax validation."
  "Extra directives injected ONLY into subagent system prompts.")

(defun +carlos/magent-inject-system-directives (composed &rest _)
  "Append Magent system directives and model menu to COMPOSED message.
Selects role-specific extras based on
`+carlos/magent-current-agent-is-orchestrator' (set by
`+carlos/magent-subagent-apply-profile')."
  (let ((role-extra (if +carlos/magent-current-agent-is-orchestrator
                        +carlos/magent-orchestrator-extra
                      +carlos/magent-subagent-extra)))
    (concat composed "\n\n" (+carlos/magent-system-directives-render) role-extra)))

(defun +carlos/magent-resolve-path-advice (orig-fun path)
  "Expande PATH para absoluto com ORIG-FUN usando `default-directory'."
  (if (and (stringp path)
           (not (string-empty-p path))
           (not (file-name-absolute-p path)))
      (funcall orig-fun (expand-file-name path default-directory))
    (funcall orig-fun path)))

(defun +carlos/magent-write-file-advice (orig-fun callback path content)
  "Valida CONTENT não vazio; chama ORIG-FUN com CALLBACK, PATH e CONTENT."
  (if (or (null content) (not (stringp content)) (string-empty-p (string-trim content)))
      (funcall callback (magent-tools--failed "Error: Required parameter 'content' is empty. Please retry providing full content."))
    (funcall orig-fun callback path content)))

(defun +carlos/magent-edit-file-advice (orig-fun callback path old-text new-text)
  "Valida OLD-TEXT não vazio; chama ORIG-FUN com CALLBACK, PATH e NEW-TEXT."
  (if (or (null old-text) (not (stringp old-text)) (string-empty-p (string-trim old-text)))
      (funcall callback (magent-tools--failed "Error: Required parameter 'old_text' is empty. Please retry providing exact text to replace."))
    (funcall orig-fun callback path old-text new-text)))

(with-eval-after-load 'magent-tools
  (advice-add 'magent-tools--resolve-path :around #'+carlos/magent-resolve-path-advice)
  (advice-add 'magent-tools--write-file :around #'+carlos/magent-write-file-advice)
  (advice-add 'magent-tools--edit-file :around #'+carlos/magent-edit-file-advice))

(with-eval-after-load 'magent-agent
  (advice-add 'magent-agent--compose-system-message
              :filter-return #'+carlos/magent-inject-system-directives))

;; ── Cap de tool results por turno ────────────────────────────────────
;; Intercepta `magent-llm-gptel--record-tool-result' (ponto onde o resultado
;; vira string antes de entrar na conversa) e trunca quando o acumulador do
;; turno excede `+carlos/magent-tool-result-max-chars'.  Não aplica a
;; `buffer_read' (estado vivo — resultado já é pequeno e dinâmico).

(defvar +carlos/magent-tool-result-cap-output nil
  "Advice para truncar tool results que excedem o cap por turno.")

(defun +carlos/magent-tool-result-cap-output (orig-fn info tool-spec tool-call result)
  "Trunca RESULT quando acumulador do turno excede o cap.
ORIG-FN é `magent-llm-gptel--record-tool-result'; INFO, TOOL-SPEC,
TOOL-CALL e RESULT são repassados.  Quando o resultado excede o cap,
adiciona nota de truncamento e atualiza o acumulador."
  (let* ((raw (if (and (fboundp 'magent-tool-result-p)
                       (magent-tool-result-p result))
                  (magent-tool-result-output-string result)
                (gptel--to-string result)))
         (name (and (fboundp 'gptel-tool-name)
                    (condition-case nil
                        (gptel-tool-name tool-spec)
                      (wrong-type-argument nil))))
         (max +carlos/magent-tool-result-max-chars)
         (remaining (- max +carlos/magent-turn-tool-result-chars)))
    (if (or (<= remaining 0)
            (<= (length raw) remaining)
            (member name '("buffer_read")))
        (progn
          (cl-incf +carlos/magent-turn-tool-result-chars (length raw))
          (apply orig-fn info tool-spec tool-call (list result)))
      (let* ((truncated (substring raw 0 remaining))
             (dropped (- (length raw) remaining))
             (note (format "\n[... truncado: %d chars restantes ...]" dropped))
             (final (concat truncated note))
             (wrapped (if (and (fboundp 'magent-tool-result-p)
                               (magent-tool-result-p result))
                          (magent-tool-result-create
                           :output final
                           :success (magent-tool-result-success result)
                           :status (magent-tool-result-status result)
                           :error (magent-tool-result-error result))
                        final)))
        (setq +carlos/magent-turn-tool-result-chars max)
        (apply orig-fn info tool-spec tool-call (list wrapped))))))

(setq +carlos/magent-tool-result-cap-output #'+carlos/magent-tool-result-cap-output)

(with-eval-after-load 'magent-llm-gptel
  (advice-add 'magent-llm-gptel--record-tool-result
              :around +carlos/magent-tool-result-cap-output))

;; ── Ferramentas Curadas da Fase A (Magent Driver do Emacs) ───────────
(declare-function flycheck-error-line "flycheck")
(declare-function flycheck-error-column "flycheck")
(declare-function flycheck-error-level "flycheck")
(declare-function flycheck-error-message "flycheck")
(declare-function flycheck-error-checker "flycheck")
(declare-function xref-find-backend "xref")
(declare-function xref-backend-definitions "xref")
(declare-function xref-backend-references "xref")
(declare-function xref-item-location "xref")
(declare-function xref-item-summary "xref")
(declare-function xref-location-group "xref")
(declare-function xref-location-line "xref")
(declare-function tempel--templates "tempel")
(defvar flycheck-mode)
(defvar flycheck-current-errors)

(defvar +carlos/magent-tool-flycheck-errors nil
  "Gptel tool for Flycheck errors.")
(defvar +carlos/magent-tool-lsp-navigation nil
  "Gptel tool for LSP navigation.")
(defvar +carlos/magent-tool-snippet-expand nil
  "Gptel tool for Snippet expansion.")
(defvar +carlos/magent-tool-rfc-search-topic nil
  "Objeto gptel-make-tool da ferramenta rfc_search_topic.")

(defvar +carlos/magent-tool-rfc-read-section nil
  "Objeto gptel-make-tool da ferramenta rfc_read_section.")

(defvar +carlos/magent-tool-select-model nil
  "Gptel tool for orchestrator model selection (Fase A).")

;; ── Sanitização ANSI e XML ──────────────────────────────────────────
(defun +carlos/magent-sanitize-string (str)
  "Sanitiza STR removendo sequências de escape ANSI e caracteres nulos.
Garante integridade textual para codificação JSON e parsing DSML/XML."
  (if (not (stringp str))
      str
    (let* ((clean-ansi (replace-regexp-in-string "\x1b\\[[0-9;]*[a-zA-Z]" "" str))
           (clean-null (replace-regexp-in-string "\x00" "" clean-ansi)))
      clean-null)))

;; ── Circuit Breaker de Nuvem (Preventivo) ──────────────────────────
(defvar +carlos/magent-cb-failures (make-hash-table :test 'equal)
  "Hash-table que rastreia falhas e cooldowns de modelos.
Chaves são nomes de modelos (string/símbolo).
Valores são plists `(:failures N :timestamp TIME)'.")

(defcustom +carlos/magent-cb-max-failures 3
  "Número máximo de falhas consecutivas antes de abrir o Circuit Breaker."
  :type 'integer
  :group '+carlos/ai)

(defcustom +carlos/magent-cb-cooldown-seconds 60
  "Tempo em segundos para o Circuit Breaker permanecer ABERTO (cooldown)."
  :type 'integer
  :group '+carlos/ai)

(defun +carlos/magent-cb-record-failure (model-key)
  "Registra uma falha para MODEL-KEY no Circuit Breaker."
  (let* ((key (format "%s" model-key))
         (entry (gethash key +carlos/magent-cb-failures))
         (failures (1+ (or (plist-get entry :failures) 0))))
    (puthash key (list :failures failures :timestamp (float-time)) +carlos/magent-cb-failures)))

;; ── Advice para capturar resultados assíncronos do gptel-request ──────
(defun +carlos/magent-cb-gptel-request-advice (orig-fn prompt &rest args)
  "Wrap `gptel-request' to record success/failure in the circuit breaker.
ORIG-FN is `gptel-request', PROMPT its first positional argument and ARGS
the remaining keyword arguments (`:backend', `:model', `:callback', ...).
We build a model-key of the form \"backend:model\", wrap the `:callback'
so that when the request finishes we record the outcome — a nil response or
a non-nil `:error' in INFO counts as failure
(`+carlos/magent-cb-record-failure'); otherwise success
(`+carlos/magent-cb-record-success') — and finally invoke the original
callback.  ARGS must NOT contain PROMPT: `plist-get' scans pairs from the
first element and would miss every keyword otherwise."
  (let* ((backend (plist-get args :backend))
         (model (plist-get args :model))
         (backend-name (if (and backend (fboundp 'gptel-backend-p) (gptel-backend-p backend))
                           (gptel-backend-name backend)
                         (format "%s" backend)))
         (model-key (if (and backend model)
                        (format "%s:%s" backend-name model)
                      (or backend-name model "unknown")))
         (callback (plist-get args :callback)))
    (if (+carlos/magent-cb-open-p model-key)
        ;; Conecta o CB à FSM abortando o turno imediatamente via callback falso
        (when callback
          (funcall callback nil (list :error (format "Circuit Breaker OPEN for model %s: temporary cloud instability / backoff active" model-key))))
      (let* ((timeout (or (and (boundp 'magent-request-timeout)
                               (numberp magent-request-timeout)
                               (> magent-request-timeout 0)
                               magent-request-timeout)
                          300))
             (timer nil)
             (done nil)
             (wrapped-callback
              (when callback
                (lambda (response info)
                  (unless done
                    (setq done t)
                    (when (timerp timer) (cancel-timer timer))
                    (if (or (null response)
                            (plist-get info :error)
                            (and (stringp response)
                                 (let ((case-fold-search t))
                                   (string-match-p "insufficient balance" response))))
                        (+carlos/magent-cb-record-failure model-key)
                      (+carlos/magent-cb-record-success model-key))
                    (funcall callback response info))))))
        (when callback
          (setq timer
                (run-at-time
                 timeout nil
                 (lambda ()
                   (unless done
                     (setq done t)
                     (+carlos/magent-cb-record-failure model-key)
                     (funcall callback nil (list :error (format "LLM request timeout after %ds for %s" timeout model-key))))))))
        (apply orig-fn prompt
               (if wrapped-callback
                   (plist-put (copy-sequence args) :callback wrapped-callback)
                 args))))))

;; Registra a advice — roda após a advice do router dinâmico, se presente.
(advice-add 'gptel-request :around #'+carlos/magent-cb-gptel-request-advice)

(defun +carlos/magent-cb-record-success (model-key)
  "Registra um sucesso para MODEL-KEY, resetando a contagem de falhas."
  (remhash (format "%s" model-key) +carlos/magent-cb-failures))

(defun +carlos/magent-cb-open-p (model-key)
  "Retorna t se o Circuit Breaker está ABERTO para MODEL-KEY."
  (let* ((key (format "%s" model-key))
         (entry (gethash key +carlos/magent-cb-failures))
         (failures (or (plist-get entry :failures) 0))
         (timestamp (or (plist-get entry :timestamp) 0.0))
         (now (float-time)))
    (if (>= failures +carlos/magent-cb-max-failures)
        (if (> (- now timestamp) +carlos/magent-cb-cooldown-seconds)
            (progn
              (+carlos/magent-cb-record-success model-key)
              nil)
          t)
      nil)))

(defun +carlos/magent-cb-execute (model-key thunk)
  "Executa THUNK com proteção de Circuit Breaker para MODEL-KEY.
Se o Circuit Breaker estiver ABERTO, sinaliza erro local sem
chamar a API remota."
  (if (+carlos/magent-cb-open-p model-key)
      (error "Circuit Breaker OPEN for model %s: temporary cloud instability / backoff active"
             model-key)
    (condition-case err
        (let ((result (funcall thunk)))
          (+carlos/magent-cb-record-success model-key)
          result)
      (error
       (+carlos/magent-cb-record-failure model-key)
       (signal (car err) (cdr err))))))

(defun +carlos/magent-tool-result (payload &optional error)
  "Constrói o resultado de uma tool do Magent a partir de PAYLOAD (JSON-safe).
Quando `magent-protocol' está carregado retorna um `magent-tool-result'
com `:output' JSON, `:success', `:status' e `:error'; caso contrário (ex.:
testes batch sem o magent), retorna o JSON como string para compatibilidade
com o gptel.  ERROR, quando presente, vira um resultado de falha e o payload
é descartado.  Aplica `+carlos/magent-sanitize-string' no resultado."
  (let* ((raw-output (if error (format "Error: %s" error) (json-encode payload)))
         (output (+carlos/magent-sanitize-string raw-output))
         (clean-error (when error (+carlos/magent-sanitize-string (format "%s" error)))))
    (if (fboundp 'magent-tool-result-create)
        (magent-tool-result-create
         :output output
         :success (null error)
         :status (if error 'failed 'completed)
         :error clean-error)
      output)))

(defun +carlos/magent-tool-flycheck-errors (path &optional _reason)
  "Handler da tool `flycheck_errors'.
PATH é o caminho do arquivo/buffer (opcional, default buffer atual);
_REASON é display-only e descartado.  Retorna os erros do Flycheck em
formato estruturado (file, line, column, level, message, checker) via
`+carlos/magent-tool-result'."
  (let* ((buf (if (and path (not (string-empty-p path)))
                  (find-buffer-visiting (expand-file-name path))
                (current-buffer))))
    (if (not buf)
        (+carlos/magent-tool-result
         nil (format "Buffer para '%s' não encontrado." (or path "current")))
      (with-current-buffer buf
        (if (and (boundp 'flycheck-mode) flycheck-mode)
            (let ((errors (vconcat
                           (mapcar (lambda (err)
                                     (list (cons "line" (flycheck-error-line err))
                                           (cons "column" (flycheck-error-column err))
                                           (cons "level" (symbol-name (flycheck-error-level err)))
                                           (cons "message" (flycheck-error-message err))
                                           (cons "checker" (symbol-name (flycheck-error-checker err)))))
                                   (or (bound-and-true-p flycheck-current-errors) nil)))))
              (+carlos/magent-tool-result
               (list (cons "status" "success")
                     (cons "buffer" (buffer-name buf))
                     (cons "file" (or (buffer-file-name buf) "none"))
                     (cons "total_errors" (length errors))
                     (cons "errors" errors))))
          (+carlos/magent-tool-result
           (list (cons "status" "info")
                 (cons "message" "Flycheck-mode não está ativo no buffer.")
                 (cons "total_errors" 0)
                 (cons "errors" []))))))))

(defun +carlos/magent-tool-lsp-navigation (sym-str &optional action _reason)
  "Handler da tool `lsp_navigation'.
SYM-STR é o símbolo a resolver; ACTION é \"definition\" (default) ou
\"references\"; _REASON é display-only e descartado.  Resolve
definições/referências via xref/Eglot em formato estruturado, ou retorna
info quando não há backend LSP."
  (if (not (and sym-str (not (string-empty-p sym-str))))
      (+carlos/magent-tool-result nil "Parâmetro 'symbol' é obrigatório.")
    (condition-case err
        (let ((xref-backend (and (fboundp 'xref-find-backend) (xref-find-backend))))
          (if (or (not xref-backend)
                  (and (eq xref-backend 'etags)
                       (not (bound-and-true-p tags-file-name))
                       (not (locate-dominating-file default-directory "TAGS"))))
              (+carlos/magent-tool-result
               (list (cons "status" "info")
                     (cons "message" "Nenhum backend LSP ativo no buffer atual e nenhuma tabela de TAGS disponível.")))
            (let* ((xrefs (if (string= action "references")
                              (xref-backend-references xref-backend sym-str)
                            (xref-backend-definitions xref-backend sym-str)))
                   (results (vconcat
                             (mapcar (lambda (x)
                                       (let* ((loc (xref-item-location x))
                                              (summary (xref-item-summary x))
                                              (file (and (fboundp 'xref-location-group)
                                                         (xref-location-group loc)))
                                              (line (and (fboundp 'xref-location-line)
                                                         (xref-location-line loc))))
                                         (list (cons "summary" summary)
                                               (cons "file" file)
                                               (cons "line" line))))
                                     xrefs))))
              (+carlos/magent-tool-result
               (list (cons "status" "success")
                     (cons "symbol" sym-str)
                     (cons "action" action)
                     (cons "total" (length results))
                     (cons "results" results))))))
      (error (+carlos/magent-tool-result nil (error-message-string err))))))

(defun +carlos/magent-tool-snippet-expand (name-str &optional action mode)
  "Handler da tool `snippet_expand'.
NAME-STR é o nome do snippet.  ACTION é \"inspect\", \"insert\" ou
\"list\" (default); MODE é um major-mode opcional para filtrar.  Lista,
inspeciona ou insere um template do Tempel, retornando o resultado via
`+carlos/magent-tool-result'."
  (let* ((action (or action "list"))
         (target-mode (if mode (intern mode) major-mode)))
    (if (not (require 'tempel nil t))
        (+carlos/magent-tool-result nil "Pacote tempel não está disponível.")
      (let ((templates (and (fboundp 'tempel--templates) (tempel--templates))))
        (cond
         ;; Ação: Inserir snippet fisicamente no buffer ativo
         ((string= action "insert")
          (if (and name-str (not (string-empty-p name-str)))
              (let ((sym (intern name-str)))
                (if (assoc sym templates)
                    (condition-case err
                        (progn
                          (tempel-insert sym)
                          (+carlos/magent-tool-result
                           (list (cons "status" "success")
                                 (cons "message" (format "Snippet '%s' inserido com sucesso no buffer." name-str)))))
                      (error (+carlos/magent-tool-result
                              nil (format "Erro ao inserir snippet: %s" (error-message-string err)))))
                  (+carlos/magent-tool-result
                   nil (format "Snippet '%s' não encontrado." name-str))))
            (+carlos/magent-tool-result
             nil "Nome do snippet é obrigatório para inserção.")))
         ;; Ação: Inspecionar estrutura de um snippet
         ((and name-str (not (string-empty-p name-str)))
          (let ((found (assoc (intern name-str) templates)))
            (if found
                (+carlos/magent-tool-result
                 (list (cons "status" "success")
                       (cons "name" name-str)
                       (cons "template" (format "%S" (cdr found)))))
              (+carlos/magent-tool-result
               nil (format "Snippet '%s' não encontrado." name-str)))))
         ;; Ação padrão: Listar todos os snippets
         (t
          (let ((names (apply #'vector
                              (mapcar (lambda (tmpl) (symbol-name (car tmpl)))
                                      templates))))
            (+carlos/magent-tool-result
             (list (cons "status" "success")
                   (cons "mode" (symbol-name target-mode))
                   (cons "total" (length names))
                   (cons "snippets" names))))))))))

;; ── Fase A: Roteamento de Modelos pelo Orquestrador ──────────────────
;; O orquestrador enxerga o menu de modelos no system prompt (rule 9) e
;; escolhe o modelo de cada subagente via a tool `select_model'.  As
;; decisões de custo/disponibilidade ficam AQUI no código: escada de tiers
;; (local < free < paid), heurística de complexidade da tarefa e o teto do
;; usuário (`+carlos/magent-model-max-tier').

(defcustom +carlos/magent-model-tier-config
  '(("free" . ("Gemini" "OpenCode Zen"))
    ("paid" . ("Zen Claude" "OpenCode Zen")))
  "Backends do gptel por tier para o menu de modelos do Magent (Fase A).
Os MODELOS não são listados aqui: são derivados em runtime
de `gptel-backend-models' do backend registrado (fonte única de verdade
no arquivo custom-ai.el) e classificados por `+carlos/magent-classify-model'
entre free tier e assinatura.  O tier local é resolvido separadamente a
partir dos modelos realmente instalados no servidor local ativo."
  :type '(alist :key-type string :value-type (repeat string))
  :group 'magent)

(defcustom +carlos/magent-model-menu-default
  '(("free" . (("Gemini" . "gemini-3.5-flash")
               ("OpenCode Zen" . "big-pickle")
               ("OpenCode Zen" . "deepseek-v4-flash-free")))
    ("paid" . (("Zen Claude" . "claude-sonnet-5")
               ("OpenCode Zen" . "gpt-5.6-sol"))))
  "Fallback do menu de modelos (tiers cloud) quando o gptel não está carregado.
Só usado em ambientes sem o gptel (ex.: suíte ERT no repo, builds elpaca
parciais).  Em runtime normal o menu é derivado de `gptel-backend-models'."
  :type '(alist :key-type string
                :value-type (alist :key-type string :value-type string))
  :group 'magent)

(defcustom +carlos/magent-model-per-tier-max 3
  "Máximo de modelos por backend exibidos em cada tier do menu do Magent.
Mantém o prompt enxuto quando um backend registra muitas variantes (ex.:
OpenCode Zen free).  Modelos são priorizados na ordem de `:models' do
backend registrado."
  :type 'integer
  :group 'magent)

(defcustom +carlos/magent-model-max-tier 'paid
  "Teto de tier permitido no roteamento de modelos do Magent.
Uma das palavras-chave `local', `free' ou `paid'.  O roteamento de modelos
e o menu renderizado respeitam este teto, nunca oferecendo nada acima dele."
  :type '(choice (const local) (const free) (const paid))
  :group 'magent)

(defconst +carlos/magent-model-tier-order '("local" "free" "paid")
  "Ordem da escada de tiers do menu de modelos do Magent.")

(defvar +carlos/magent-subagent-model-overrides nil
  "Overrides transientes de modelo por subagente do Magent.
Alist de (AGENT-NAME . (BACKEND-NAME . MODEL-STRING)), registrado pela
tool `select_model' e consumido uma única vez (pop) pelo advice
`+carlos/magent-subagent-apply-profile' ao criar o subagente.")

;; Forward declaration pelada de `+carlos/magent-subagent-profiles' (definido em
;; custom-magent-subagent.el, carregado depois) — só suprime o warning do
;; byte-compiler; NÃO liga a variável (defvar com valor/docstring ligaria e
;; corromperia o defcustom). O runtime guarda com `boundp' antes de ler.
(defvar +carlos/magent-subagent-profiles)

(defun +carlos/magent-tier-rank (tier)
  "Rank numérico de TIER na escada `+carlos/magent-model-tier-order'."
  (or (cl-position tier +carlos/magent-model-tier-order :test #'equal) -1))

(defun +carlos/magent-model-str (model)
  "Retorna MODEL como string (símbolos viram nomes)."
  (if (stringp model) model (symbol-name model)))

(defun +carlos/magent-local-pair ()
  "Retorna (BACKEND-STRING . MODEL) do modelo local do host (MLX/Ollama)."
  (+carlos/ai-local-backend))

(defun +carlos/magent-model-cost (backend-name model)
  "Classifica o custo de MODEL em BACKEND-NAME para o menu do Magent.
MODEL pode ser string ou símbolo.  Retorna rótulo curto de custo/quota."
  (let ((model-str (+carlos/magent-model-str model)))
    (cond
     ((string-match-p "MLX\\|Ollama\\|LM Studio" backend-name) "grátis (local)")
     ((equal backend-name "OpenCode Zen")
      (if (or (equal model-str "big-pickle") (string-match-p "-free$" model-str))
          "grátis (free tier)"
        "assinatura (zen)"))
     ((string-match-p "flash\\|lite" model-str) "grátis (free tier)")
     ((string-match-p "pro\\|opus\\|sonnet\\|sol" model-str) "assinatura")
     (t "grátis (free tier)"))))

(defun +carlos/magent-model-cost-rank (backend-name model)
  "Custo numérico de MODEL em BACKEND-NAME para ordenar mais barato-primeiro.
Derivado de `+carlos/magent-model-cost': 0 para grátis (free tier)/local,
1 para assinatura Zen (plano já pago — custo marginal zero), 2 para
assinatura metered por uso, 99 para desconhecido."
  (let ((label (+carlos/magent-model-cost backend-name model)))
    (cond ((string-match-p "free tier" label) 0)
          ((string-match-p "local" label) 0)
          ((string-match-p "zen" label) 1)
          ((string-match-p "assinatura" label) 2)
          (t 99))))

(defun +carlos/magent-classify-model (backend-name model)
  "Classifica MODEL no backend BACKEND-NAME como `local', `free' ou `paid'."
  (let ((cost (+carlos/magent-model-cost backend-name model)))
    (cond
     ((string-match-p "local" cost) 'local)
     ((string-match-p "free tier" cost) 'free)
     (t 'paid))))

(defun +carlos/magent-local-installed-models ()
  "Lista os modelos realmente instalados no servidor local ativo.
Consulta o endpoint de listagem do backend local ativo — `/v1/models'
para MLX Local, `/api/tags' para Ollama Local — com timeout de 2s, e
retorna os nomes como lista de strings.  Sem servidor ativo, backend
não registrado ou resposta inválida, retorna nil (nunca lança erro)."
  (when-let* ((pair (+carlos/ai-local-backend))
              (backend-name (car pair))
              (bk (and (fboundp 'gptel-get-backend)
                       (fboundp 'gptel-backend-host)
                       (fboundp 'gptel-backend-protocol)
                       (gptel-get-backend backend-name))))
    (let* ((host (gptel-backend-host bk))
           (protocol (or (gptel-backend-protocol bk) "http"))
           (url (format "%s://%s/%s"
                        protocol host
                        (if (string-match-p "MLX\\|LM Studio" backend-name)
                            "v1/models" "api/tags"))))
      (condition-case nil
          (let ((buf (url-retrieve-synchronously url t nil 2)))
            (when buf
              (unwind-protect
                  (with-current-buffer buf
                    (goto-char (point-min))
                    (re-search-forward "^\r?$" nil t)
                    (let ((json (json-read-from-string
                                 (buffer-substring-no-properties (point) (point-max)))))
                      (if (string-match-p "MLX\\|LM Studio" backend-name)
                          (mapcar (lambda (m) (cdr (assoc 'id m)))
                                  (alist-get 'data json))
                        (mapcar (lambda (m) (cdr (assoc 'name m)))
                                (alist-get 'models json)))))
                (kill-buffer buf))))
        (error nil)))))

(defun +carlos/magent-model-menu-entries (&optional backends local-models)
  "Deriva o menu de modelos (Fase A) para o Magent.
BACKENDS (alist NAME . MODELS) e LOCAL-MODELS (lista de strings) são
overrides para testes; por padrão:
- cloud: `gptel-backend-models' de cada backend de
  `+carlos/magent-model-tier-config', classificados por
  `+carlos/magent-classify-model' e limitados por
  `+carlos/magent-model-per-tier-max' por backend em cada tier;
- local: `+carlos/magent-local-installed-models' (instalados no servidor
  local ativo, via `+carlos/ai-local-backend' como backend).
Retorna alist (TIER . ((BACKEND . MODEL)...)).  Sem gptel carregado,
os tiers cloud usam `+carlos/magent-model-menu-default'."
  (let* ((cloud (if (and (not backends) (not (fboundp 'gptel-get-backend)))
                    +carlos/magent-model-menu-default
                  (+carlos/magent--model-cloud-entries backends)))
         (local-backend (or (car (+carlos/ai-local-backend)) "Local"))
         (local-entries (mapcar (lambda (m) (cons local-backend m))
                                (or local-models
                                    (+carlos/magent-local-installed-models)))))
    (if local-entries
        (cons (cons "local" (nreverse local-entries)) cloud)
      cloud)))

(defun +carlos/magent--model-cloud-entries (backends)
  "Deriva os tiers cloud do menu de modelos do Magent.
BACKENDS é um alist (NAME . MODELS); quando nil, deriva dos backends de
`+carlos/magent-model-tier-config' via gptel (fallback para
`+carlos/magent-model-menu-default' sem gptel).  Classifica cada modelo
com `+carlos/magent-classify-model' e aplica
`+carlos/magent-model-per-tier-max' por backend em cada tier.
Retorna alist (TIER . ((BACKEND . MODEL)...)) na ordem de
`+carlos/magent-model-tier-order'."
  (let* ((src (or backends
                  (let ((result nil))
                    (dolist (pair +carlos/magent-model-tier-config)
                      (let ((names (cdr pair)))
                        (dolist (name names)
                          (push (cons name
                                      (and (fboundp 'gptel-get-backend)
                                           (let ((bk (gptel-get-backend name)))
                                             (and bk
                                                  (fboundp 'gptel-backend-models)
                                                  (gptel-backend-models bk)))))
                                result))))
                    (nreverse result))))
         (tiers nil)
         (per-backend (make-hash-table :test #'equal)))
    (dolist (pair src)
      (let ((name (car pair)))
        (dolist (model (cdr pair))
          (let* ((tier (symbol-name (+carlos/magent-classify-model name model)))
                 (key (format "%s/%s" tier name)))
            (when (< (gethash key per-backend 0) +carlos/magent-model-per-tier-max)
              (puthash key (1+ (gethash key per-backend 0)) per-backend)
              (push (cons name (+carlos/magent-model-str model))
                    (alist-get tier tiers nil nil #'equal)))))))
    (let ((ordered nil))
      (dolist (tier +carlos/magent-model-tier-order)
        (let ((entry (assoc tier tiers)))
          (when entry
            (push (cons tier (nreverse (cdr entry))) ordered))))
      (nreverse ordered))))

(defun +carlos/magent-model-menu-render ()
  "Renderiza o menu de modelos para o system prompt do Magent.
Deriva os tiers cloud de `gptel-backend-models' e o local dos modelos
instalados no servidor (marcados ONLINE/OFFLINE por ping); corta tiers
acima de `+carlos/magent-model-max-tier'."
  (let* ((max-tier (symbol-name +carlos/magent-model-max-tier))
         (max-rank (+carlos/magent-tier-rank max-tier))
         (entries (+carlos/magent-model-menu-entries))
         (local-online (+carlos/local-ai-server-ping-p))
         (lines (list (format "MODEL SELECTION MENU (tier cap: %s):" max-tier))))
    (dolist (tier +carlos/magent-model-tier-order)
      (when (<= (+carlos/magent-tier-rank tier) max-rank)
        (push (format "- tier %s:" tier) lines)
        (dolist (entry (cdr (assoc tier entries)))
          (push (format "  - %s / %s — %s%s"
                        (car entry) (cdr entry)
                        (+carlos/magent-model-cost (car entry) (cdr entry))
                        (if (equal tier "local")
                            (if local-online " [ONLINE]" " [OFFLINE]")
                          ""))
                lines))))
    (mapconcat #'identity (nreverse lines) "\n")))

(defun +carlos/magent-system-directives-render ()
  "Retorna as directivas estáticas seguidas do menu de modelos renderizado."
  (concat +carlos/magent-system-directives
          "\n\n" (+carlos/magent-model-menu-render)))

(defconst +carlos/magent-deep-task-keywords
  '("refactor" "architect" "architecture" "design" "schema" "migrat"
    "securit" "optimiz" "benchmark" "concurr" "thread" "protocol"
    "root cause" "causa raiz" "review" "plan" "analyse" "analyze"
    "analis" "projetar" "arquitetur" "debug" "investigat" "troubleshoot"
    "edit" "editar" "update" "atualiz" "rewrite" "reescrev" "implement"
    "planning")
  "Keywords de raciocínio profundo na heurística de complexidade da Fase A.
Inclui verbos de edição/escrita (`edit', `update', `rewrite', `implement',
`planning') para que qualquer tarefa de alteração de arquivo — que exige
leitura prévia e match exato de `old_text' — seja classificada como `deep'
e delegada a subagente com modelo forte, nunca ao local.")

(defun +carlos/magent-task-complexity (task-description)
  "Classifica TASK-DESCRIPTION como `simple', `moderate' ou `deep'.
`deep' se contém keyword de `+carlos/magent-deep-task-keywords' ou tem mais
de 150 caracteres; `moderate' entre 61 e 150; `simple' até 60."
  (let ((text (downcase (or task-description ""))))
    (cond
     ((or (> (length text) 150)
          (cl-some (lambda (kw) (string-match-p kw text))
                   +carlos/magent-deep-task-keywords))
      'deep)
     ((> (length text) 60) 'moderate)
     (t 'simple))))

(defun +carlos/magent--tier-sorted-entries (tier entries &optional preferred-backend)
  "Retorna as entries do TIER em ENTRIES ordenadas mais barato-primeiro.
Ordena por `+carlos/magent-model-cost-rank' ascendente; dentro do mesmo
custo, modelos de PREFERRED-BACKEND primeiro (dica de perfil) e, por fim,
a ordem do menu como desempate.  ENTRIES é o alist (TIER . ((BACKEND .
MODEL)...)) de `+carlos/magent-model-menu-entries'."
  (let* ((pref (and (stringp preferred-backend) preferred-backend))
         (ranked (cl-loop for entry in (cdr (assoc tier entries))
                          for i from 0
                          collect (list (+carlos/magent-model-cost-rank
                                         (car entry) (cdr entry))
                                        (if (and pref (equal (car entry) pref)) 0 1)
                                        i
                                        entry))))
    (mapcar (lambda (row) (cadddr row))
            (sort ranked
                  (lambda (a b)
                    (let ((ra (nth 0 a)) (rb (nth 0 b))
                          (pa (nth 1 a)) (pb (nth 1 b))
                          (ia (nth 2 a)) (ib (nth 2 b)))
                      (or (< ra rb)
                          (and (= ra rb)
                               (or (< pa pb)
                                   (and (= pa pb) (< ia ib)))))))))))

(defun +carlos/magent-resolve-model
    (complexity &optional local-online-p backends local-models hints)
  "Resolve o modelo para COMPLEXITY (`simple', `moderate' ou `deep').
Escada: local (apenas quando LOCAL-ONLINE-P e não `deep') → free → paid,
nunca acima de `+carlos/magent-model-max-tier'.  HINTS (plist) pode impor
`:min-tier' (piso — o tier escolhido nunca fica abaixo; ex.: \"paid\" para
perfis de alto valor) e `:preferred-backend' (desempate por backend dentro
do tier escolhido).  Dentro do tier, o modelo mais barato vem primeiro
\\(`+carlos/magent--tier-sorted-entries').  BACKENDS e LOCAL-MODELS são
repassados a `+carlos/magent-model-menu-entries' (overrides p/ testes).
Retorna plist com :backend, :model, :tier e :reason, ou nil se nada
disponível."
  (let* ((max-tier (symbol-name +carlos/magent-model-max-tier))
         (max-rank (+carlos/magent-tier-rank max-tier))
         (min-tier (plist-get hints :min-tier))
         (min-rank (and min-tier (+carlos/magent-tier-rank min-tier)))
         (entries (+carlos/magent-model-menu-entries backends local-models))
         (tiers (append (when (and (not (eq complexity 'deep)) local-online-p)
                          '("local"))
                        (cl-remove "local" +carlos/magent-model-tier-order
                                   :test #'string=))))
    (catch 'resolved
      (dolist (tier tiers)
        (when (and (<= (+carlos/magent-tier-rank tier) max-rank)
                   (or (null min-rank)
                       (>= (+carlos/magent-tier-rank tier) min-rank)))
          (dolist (entry (+carlos/magent--tier-sorted-entries
                          tier entries (plist-get hints :preferred-backend)))
            (when (and (stringp (car entry))
                       (fboundp 'gptel-get-backend)
                       (gptel-get-backend (car entry))
                       (not (and (fboundp '+carlos/magent-cb-open-p)
                                 (or (+carlos/magent-cb-open-p (car entry))
                                     (+carlos/magent-cb-open-p (cdr entry))))))
              (throw 'resolved
                     (list :backend (car entry)
                           :model (cdr entry)
                           :tier tier
                           :reason (format "%s task → tier %s%s (%s via %s)"
                                           complexity tier
                                           (if min-tier
                                               (format " [min %s]" min-tier)
                                             "")
                                           (+carlos/magent-model-cost (car entry) (cdr entry))
                                           (car entry)))))))))))

(defun +carlos/magent-tool-select-model
    (task-description &optional agent complexity min-tier-arg backend-preferred _reason)
  "Handler da tool `select_model' (Fase A + F4-select).
TASK-DESCRIPTION descreve a tarefa do subagente; AGENT é o nome do
subagente alvo (default \"general\"); COMPLEXITY é opcional, \"simple\",
\"moderate\" ou \"deep\" (senão inferido de TASK-DESCRIPTION); MIN-TIER-ARG
é opcional, \"local\", \"free\" ou \"paid\" (piso mínimo do tier — força
escalation acima deste nível); BACKEND-PREFERRED é opcional, nome do
backend preferido (ex.: \"gemini\", \"mlx\") — desempata dentro do tier;
_REASON é display-only e descartado.
Resolve o modelo na escada de tiers, registra um override transiente em
`+carlos/magent-subagent-model-overrides' e retorna um `magent-tool-result'
com o payload JSON (backend, model, tier, reason)."
  (let* ((agent (or agent "general"))
         (hints (and (boundp '+carlos/magent-subagent-profiles)
                     (cdr (assoc agent +carlos/magent-subagent-profiles))))
         ;; Merge min-tier-arg into hints (override profile floor)
         (hints (if (and min-tier-arg (stringp min-tier-arg))
                    (plist-put (copy-sequence hints) :min-tier min-tier-arg)
                  hints))
         ;; Merge backend-preferred into hints (explicit user preference)
         (hints (if (and backend-preferred (stringp backend-preferred))
                    (plist-put (copy-sequence hints)
                               :preferred-backend backend-preferred)
                  hints))
         (complexity-sym (pcase complexity
                           ("deep" 'deep)
                           ("moderate" 'moderate)
                           ("simple" 'simple)
                           (_ (+carlos/magent-task-complexity task-description))))
         (choice (+carlos/magent-resolve-model
                  complexity-sym (+carlos/local-ai-server-ping-p) nil nil hints)))
    (if (null choice)
        (+carlos/magent-tool-result
         nil (format "Nenhum modelo disponível para complexidade %s dentro do teto %s."
                     complexity-sym (symbol-name +carlos/magent-model-max-tier)))
      (let ((backend (plist-get choice :backend))
            (model (plist-get choice :model))
            (tier (plist-get choice :tier))
            (reason (plist-get choice :reason)))
        (setq +carlos/magent-subagent-model-overrides
              (cons (cons agent (cons backend model))
                    +carlos/magent-subagent-model-overrides))
        (message "[Magent select_model] %s → %s/%s (tier %s) — %s"
                 agent backend model tier reason)
        (+carlos/magent-tool-result
         (list (cons "status" "success")
               (cons "agent" agent)
               (cons "backend" backend)
               (cons "model" model)
               (cons "tier" tier)
               (cons "reason" reason)))))))

;; ── Ferramentas Forge (Issues/PRs via Forge DB) ──────────────────────
;; Leitura estruturada de issues/PRs do db local do Forge (magit/forge):
;; sem alucinação (dados do db/API, não do modelo) e com economia de
;; tokens (bodies/comentários truncados). Tudo é guardado: sem o pacote
;; forge, ou com o db vazio, as tools retornam resultados JSON estruturados
;; (status info/error) em vez de sinalizar erro ao LLM. As funções de
;; acesso a dados (SQL-FN / REPO-FN) são injetáveis para testes offline.

(defcustom +carlos/magent-forge-body-max-chars 2000
  "Limite de caracteres do corpo de um issue/PR retornado por `forge_read_issue'."
  :type 'integer
  :group '+carlos/ai)

(defcustom +carlos/magent-forge-comment-max-chars 800
  "Limite de caracteres por comentário retornado por `forge_read_issue'."
  :type 'integer
  :group '+carlos/ai)

(defcustom +carlos/magent-forge-list-limit 50
  "Número máximo de topics por tipo em `forge_list_pull_requests'."
  :type 'integer
  :group '+carlos/ai)

(defun +carlos/magent-forge--scalar (value)
  "Normaliza VALUE para tipo JSON-safe (string ou número)."
  (cond
   ((stringp value) value)
   ((numberp value) value)
   ((symbolp value) (symbol-name value))
   ((null value) "")
   (t (format "%s" value))))

(defun +carlos/magent-forge--truncate (str max-chars)
  "Trunca STR em MAX-CHARS chars com nota de truncamento."
  (if (and max-chars (> (length str) max-chars))
      (concat (substring str 0 max-chars)
              (format "\n[... %d chars truncados ...]" (- (length str) max-chars)))
    str))

(defconst +carlos/magent-forge--url-re
  "\\`https?://[^/]+/\\([^/#?]+\\)/\\([^/#?]+\\)/\\(?:-/\\)?\\(?:issues\\|pulls?\\|merge_requests\\)/\\([0-9]+\\)"
  "Regex de URL de issue/PR (GitHub issues|pull; GitLab /-/issues|merge_requests).")

(defun +carlos/magent-forge-parse-ref (input)
  "Parse INPUT para plist (:number N :owner S :repo S :kind K).
Aceita \"123\", \"#123\", \"owner/repo#123\" e URLs completas de issue/PR.
K é `issue' ou `pullreq' quando determinável pela URL; nil caso contrário
— a leitura tenta a tabela de issues antes da de PRs.
Retorna nil quando não há número válido."
  (when (stringp input)
    (let ((str (string-trim input)))
      (save-match-data
        (cond
         ((string-match +carlos/magent-forge--url-re str)
          (list :number (string-to-number (match-string 3 str))
                :owner (match-string 1 str)
                :repo (match-string 2 str)
                :kind (if (string-match-p "\\(?:/pulls?/\\|merge_requests/\\)" str)
                          'pullreq 'issue)))
         ((string-match "\\`\\([A-Za-z0-9._-]+\\)/\\([A-Za-z0-9._-]+\\)#\\([0-9]+\\)\\'" str)
          (list :number (string-to-number (match-string 3 str))
                :owner (match-string 1 str)
                :repo (match-string 2 str)
                :kind nil))
         ((string-match "\\`#?\\([0-9]+\\)\\'" str)
          (list :number (string-to-number (match-string 1 str))
                :owner nil :repo nil :kind nil)))))))

(defun +carlos/magent-forge--current-repo ()
  "Retorna cons (OWNER . NAME) do repositório forge do contexto atual.
Usa `forge-get-repository' (`:known?' com fallback `:stub?'); retorna nil
fora de um repositório suportado.  Nunca sinaliza erro."
  (when (fboundp 'forge-get-repository)
    (ignore-errors
      (let ((repo (or (forge-get-repository :known?)
                      (forge-get-repository :stub?))))
        (when (and repo (slot-exists-p repo 'owner) (slot-exists-p repo 'name))
          (cons (slot-value repo 'owner) (slot-value repo 'name)))))))

(defun +carlos/magent-forge--resolve-repo (sql-fn ref repo-fn)
  "Resolve id/owner/name do repositório no db do Forge.
SQL-FN executa queries emacsql; REF é o plist de
`+carlos/magent-forge-parse-ref' (owner/repo opcionais); REPO-FN (default
`+carlos/magent-forge--current-repo') supre owner/repo quando REF não os
traz.  Retorna lista (ID OWNER NAME) ou nil quando desconhecido."
  (let* ((ident (if (and (plist-get ref :owner) (plist-get ref :repo))
                    (cons (plist-get ref :owner) (plist-get ref :repo))
                  (funcall (or repo-fn #'+carlos/magent-forge--current-repo))))
         (rows (and ident
                    (funcall sql-fn
                             [:select [id] :from repository
                                      :where (and (= owner $s1) (= name $s2))]
                             (car ident) (cdr ident)))))
    (and rows
         (caar rows)
         (list (caar rows) (car ident) (cdr ident)))))

(defun +carlos/magent-forge--comments-payload (rows &optional max-chars)
  "Converte ROWS de posts (AUTHOR CREATED BODY) em vetor JSON-safe.
MAX-CHARS limita o tamanho do corpo de cada comentário."
  (apply #'vector
         (mapcar (lambda (post)
                   (list (cons "author" (+carlos/magent-forge--scalar (nth 0 post)))
                         (cons "created" (+carlos/magent-forge--scalar (nth 1 post)))
                         (cons "body" (+carlos/magent-forge--truncate
                                       (+carlos/magent-forge--scalar (nth 2 post))
                                       max-chars))))
                 rows)))

(defun +carlos/magent-forge--issue-payload (row post-rows owner name)
  "Payload JSON-safe de uma issue.
ROW = (id number title state author body created updated closed status);
POST-ROWS são os comentários crus; OWNER/NAME identificam o repositório."
  (list (cons "status" "success")
        (cons "type" "issue")
        (cons "repository" (format "%s/%s" owner name))
        (cons "number" (nth 1 row))
        (cons "title" (+carlos/magent-forge--scalar (nth 2 row)))
        (cons "state" (+carlos/magent-forge--scalar (nth 3 row)))
        (cons "author" (+carlos/magent-forge--scalar (nth 4 row)))
        (cons "created" (+carlos/magent-forge--scalar (nth 6 row)))
        (cons "updated" (+carlos/magent-forge--scalar (nth 7 row)))
        (cons "closed" (+carlos/magent-forge--scalar (nth 8 row)))
        (cons "body" (+carlos/magent-forge--truncate
                      (+carlos/magent-forge--scalar (nth 5 row))
                      +carlos/magent-forge-body-max-chars))
        (cons "total_comments" (length post-rows))
        (cons "comments" (+carlos/magent-forge--comments-payload
                          post-rows +carlos/magent-forge-comment-max-chars))))

(defun +carlos/magent-forge--pullreq-payload (row post-rows owner name)
  "Payload JSON-safe de um pull request.
ROW = (id number title state author body created updated closed merged
status base-ref head-ref draft-p); POST-ROWS são os comentários crus;
OWNER/NAME identificam o repositório."
  (list (cons "status" "success")
        (cons "type" "pullreq")
        (cons "repository" (format "%s/%s" owner name))
        (cons "number" (nth 1 row))
        (cons "title" (+carlos/magent-forge--scalar (nth 2 row)))
        (cons "state" (+carlos/magent-forge--scalar (nth 3 row)))
        (cons "author" (+carlos/magent-forge--scalar (nth 4 row)))
        (cons "created" (+carlos/magent-forge--scalar (nth 6 row)))
        (cons "updated" (+carlos/magent-forge--scalar (nth 7 row)))
        (cons "closed" (+carlos/magent-forge--scalar (nth 8 row)))
        (cons "merged" (+carlos/magent-forge--scalar (nth 9 row)))
        (cons "base_ref" (+carlos/magent-forge--scalar (nth 11 row)))
        (cons "head_ref" (+carlos/magent-forge--scalar (nth 12 row)))
        (cons "draft" (if (nth 13 row) "true" "false"))
        (cons "body" (+carlos/magent-forge--truncate
                      (+carlos/magent-forge--scalar (nth 5 row))
                      +carlos/magent-forge-body-max-chars))
        (cons "total_comments" (length post-rows))
        (cons "comments" (+carlos/magent-forge--comments-payload
                          post-rows +carlos/magent-forge-comment-max-chars))))

(defvar +carlos/magent-tool-forge-read-issue nil
  "Gptel tool para leitura de issue/PR via Forge DB.")

(defvar +carlos/magent-tool-forge-list-pull-requests nil
  "Gptel tool para listagem de PRs/issues via Forge DB.")

(defun +carlos/magent-forge--read-topic (ref sql-fn repo-fn)
  "Busca topic da REF nas tabelas issue/pullreq via SQL-FN.
REF é o plist de `+carlos/magent-forge-parse-ref'; REPO-FN supre
owner/repo quando ausentes na ref.  Retorna o `magent-tool-result' do
topic ou payload status info."
  (let* ((sql-fn (or sql-fn #'forge-sql))
         (repo (+carlos/magent-forge--resolve-repo sql-fn ref repo-fn))
         (repo-id (nth 0 repo))
         (owner (nth 1 repo))
         (name (nth 2 repo))
         (num (plist-get ref :number))
         (want-pr (eq (plist-get ref :kind) 'pullreq)))
    (if (not repo-id)
        (+carlos/magent-tool-result
         (list (cons "status" "info")
               (cons "message"
                     (format "Repositório '%s' não encontrado no db local do Forge. Rode M-x forge-pull no repositório."
                             (if (and owner name)
                                 (format "%s/%s" owner name)
                               "atual")))))
      (let ((hit
             (catch 'found
               (dolist (tbl (if want-pr '(pullreq issue) '(issue pullreq)))
                 (pcase tbl
                   (`issue
                    (let* ((rows (funcall sql-fn
                                          [:select [id number title state author body created updated closed status]
                                                   :from issue
                                                   :where (and (= repository $s1) (= number $s2))]
                                          repo-id num))
                           (row (car rows)))
                      (when row
                        (throw 'found
                               (+carlos/magent-tool-result
                                (+carlos/magent-forge--issue-payload
                                 row
                                 (funcall sql-fn
                                          [:select [author created body]
                                                   :from issue-post
                                                   :where (= issue $s1)
                                                   :order-by [(asc created)]]
                                          (nth 0 row))
                                 owner name))))))
                   (`pullreq
                    (let* ((rows (funcall sql-fn
                                          [:select [id number title state author body created updated closed merged status base-ref head-ref draft-p]
                                                   :from pullreq
                                                   :where (and (= repository $s1) (= number $s2))]
                                          repo-id num))
                           (row (car rows)))
                      (when row
                        (throw 'found
                               (+carlos/magent-tool-result
                                (+carlos/magent-forge--pullreq-payload
                                 row
                                 (funcall sql-fn
                                          [:select [author created body]
                                                   :from pullreq-post
                                                   :where (= pullreq $s1)
                                                   :order-by [(asc created)]]
                                          (nth 0 row))
                                 owner name)))))))))))
        (if hit
            hit
          (+carlos/magent-tool-result
           (list (cons "status" "info")
                 (cons "message"
                       (format "Topic #%s não encontrado no db local do Forge. Rode M-x forge-pull para sincronizar." num)))))))))





;; ── Ferramentas IETF/RFC (rfc_search_topic / rfc_read_section) ──────

(defcustom +carlos/magent-rfc-section-max-chars 6000
  "Teto de caracteres do texto retornado por `rfc_read_section'."
  :type 'natnum
  :group 'magent)

(defcustom +carlos/magent-rfc-search-limit 8
  "Máximo de resultados por `rfc_search_topic'."
  :type 'natnum
  :group 'magent)

(defun +carlos/magent-rfc--cache-dir ()
  "Diretório de cache de RFCs (segue `rfc-mode-directory' quando carregado)."
  (directory-file-name
   (file-name-as-directory
    (or (and (boundp 'rfc-mode-directory) rfc-mode-directory)
        (expand-file-name "rfc/" user-emacs-directory)))))

(defun +carlos/magent-rfc--ensure-file (name url)
  "Garantir arquivo NAME no cache baixando de URL se necessário."
  (let* ((dir (+carlos/magent-rfc--cache-dir))
         (path (expand-file-name name dir)))
    (unless (file-exists-p path)
      (make-directory dir t)
      (url-copy-file url path t))
    path))

(defun +carlos/magent-rfc--fetch-text (number-or-name url-format)
  "Texto cru do documento NUMBER-OR-NAME usando URL-FORMAT (ex.: 9000 ou \"-index\")."
  (with-temp-buffer
    (insert-file-contents
     (+carlos/magent-rfc--ensure-file
      (format "rfc%s.txt" number-or-name)
      (format url-format number-or-name)))
    (buffer-substring-no-properties (point-min) (point-max))))

;; Parser puro de headings numerados de RFC txt (testável offline):
(defconst +carlos/magent-rfc--heading-re
  "^\\([0-9]+\\(?:\\.[0-9]+\\)*\\|Appendix [A-Z]\\)\\.?[ \t][ \t]+\\([^	].*[^ ]\\)?[ \t]*$"
  "Regex de linha-cabeçalho numerada de RFC txt.
Grupo 1: número (\"3.1\", \"Appendix B\"); grupo 2: título opcional.
Exige >=2 espaços após o número (itens de lista usam 1).")

(defun +carlos/magent-rfc-parse-sections (text)
  "Lista de plists (:num :title :start) das seções numeradas do TEXT.
Ignora linhas de sumário (pontilhado \"...\"/\". . .\") e cabeçalhos de página."
  (let ((start 0)
        (skip-re "[.][.][.]\\|[.] [.]\\|\\[Page")
        out)
    (while (string-match +carlos/magent-rfc--heading-re text start)
      (setq start (match-end 0))
      (unless (string-match-p skip-re (match-string-no-properties 0 text))
        (push (list :num (string-trim-right
                          (match-string-no-properties 1 text) "[.]")
                    :title (or (match-string-no-properties 2 text) "")
                    :start (match-beginning 0))
              out)))
    (nreverse out)))

(defun +carlos/magent-rfc--depth (num)
  "Profundidade de NUM tipo \"3.1.2\" (Appendix tem profundidade 1)."
  (if (string-prefix-p "Appendix" num)
      1
    (length (split-string num "\\." t))))

(defun +carlos/magent-rfc-extract-section (text num &optional max-chars)
  "Texto da seção NUM do TEXT até a próxima seção de profundidade ≤.
Retorna plist (:num :title :text) ou nil se ausente.  Texto capado a
MAX-CHARS (default `+carlos/magent-rfc-section-max-chars')."
  (let* ((secs (+carlos/magent-rfc-parse-sections text))
         (idx (cl-position-if (lambda (s)
                                (equal (plist-get s :num) num))
                              secs)))
    (when idx
      (let* ((cur (nth idx secs))
             (depth (+carlos/magent-rfc--depth num))
             (end (catch 'done
                    (cl-dolist (rest (nthcdr (1+ idx) secs))
                      (when (<= (+carlos/magent-rfc--depth
                                 (plist-get rest :num))
                                depth)
                        (throw 'done (plist-get rest :start))))
                    (length text)))
             (raw (substring text (plist-get cur :start) end))
             (cap (or max-chars +carlos/magent-rfc-section-max-chars))
             (body (if (> (length raw) cap)
                       (concat (substring raw 0 cap) "\n... [truncado]")
                     raw)))
        (list :num num
              :title (plist-get cur :title)
              :text body)))))

(defun +carlos/magent-rfc-normalize-number (number-str)
  "Extrai o número puro de NUMBER-STR (ex.: \"RFC 9000\" -> \"9000\")."
  (save-match-data
    (if (string-match "[0-9]+" number-str)
        (match-string 0 number-str)
      nil)))

(defun +carlos/magent-rfc-search-index-text (index-text query)
  "Busca QUERY (case-insensitive) em INDEX-TEXT.
Retorna plists com :number e :snippet."
  (let ((results nil)
        (limit +carlos/magent-rfc-search-limit))
    (with-temp-buffer
      (let ((case-fold-search t))
        (insert index-text)
        (goto-char (point-min))
        (while (and (< (length results) limit)
                    (re-search-forward (regexp-quote query) nil t))
          (let* ((bop (save-excursion (backward-paragraph) (point)))
                 (eop (save-excursion (forward-paragraph) (point)))
                 (para (buffer-substring-no-properties bop eop))
                 (clean-para (replace-regexp-in-string "\n[ \t]*" " " para)))
            (save-match-data
              (when (string-match "^\\s-*\\([0-9]+\\)\\s-+" clean-para)
                (let ((num (match-string 1 clean-para)))
                  (unless (cl-find num results :key (lambda (x) (plist-get x :number)) :test #'equal)
                    (push (list :number num
                                :snippet (if (> (length clean-para) 300)
                                             (concat (substring clean-para 0 297) "...")
                                           clean-para))
                          results)))))
            (goto-char eop)))))
    (nreverse results)))





(defun +carlos/magent-tool-rag-create-doc (symbols target-file title description &optional filetags _reason)
  "Gera ou atualiza um arquivo Org-mode RAG em TARGET-FILE introspectando SYMBOLS.
SYMBOLS pode ser uma lista de strings/símbolos ou string separada por espaço.
TARGET-FILE é o caminho sob `docs/' ou absoluto.
TITLE e DESCRIPTION formatam o cabeçalho canônico do Org.
FILETAGS (default ':RAG:DOCS:') é a tag do arquivo."
  (ignore-errors (require 'magit))
  (ignore-errors (require 'forge))
  (let* ((sym-list (cond
                    ((listp symbols) symbols)
                    ((stringp symbols) (split-string symbols "[ \t\n,]+" t))
                    (t nil)))
         (tag-str (or (and (stringp filetags) (not (string-empty-p filetags)) filetags) ":RAG:DOCS:"))
         (date-str (format-time-string "%Y-%m-%d"))
         (abs-file (expand-file-name target-file (+carlos/magent-project-root)))
         (dir (file-name-directory abs-file))
         (header-lines (list (format "#+TITLE: %s" title)
                             "#+AUTHOR: Carlos Filho"
                             (format "#+DATE: %s" date-str)
                             (format "#+LAST_MODIFIED: %s" date-str)
                             (format "#+DESCRIPTION: %s" description)
                             (format "#+FILETAGS: %s" tag-str)
                             "#+OPTIONS: toc:2 num:t"
                             ""
                             "* Visão Geral"
                             ""
                             description
                             ""
                             "* Símbolos Introspectados"
                             ""))
         (body-lines nil))
    (unless (file-directory-p dir)
      (make-directory dir t))
    (dolist (sym-item sym-list)
      (let* ((sym (if (symbolp sym-item) sym-item (intern (string-trim (format "%s" sym-item)))))
             (name (symbol-name sym))
             (doc (ignore-errors (documentation sym t)))
             (arglist (ignore-errors (when (fboundp sym) (help-function-arglist sym t))))
             (kind (cond ((macrop sym) "Macro")
                         ((commandp sym) "Comando Interativo")
                         ((fboundp sym) "Função Elisp")
                         ((boundp sym) "Variável")
                         (t "Símbolo"))))
        (push (format "** %s" name) body-lines)
        (push (format "- *Tipo:* %s" kind) body-lines)
        (when arglist
          (push (format "- *Assinatura:* =%s=" (cons name arglist)) body-lines))
        (push "" body-lines)
        (if doc
            (progn
              (push "#+begin_src text" body-lines)
              (push (string-trim doc) body-lines)
              (push "#+end_src" body-lines))
          (push "_Sem documentação registrada._" body-lines))
        (push "" body-lines)))
    (with-temp-file abs-file
      (insert (mapconcat #'identity (append header-lines (nreverse body-lines)) "\n")))
    (format "Documento RAG gerado com sucesso em '%s' (%d símbolos introspectados)."
            abs-file (length sym-list))))

























































;; ── Registro das tools curadas no catálogo do Magent ─────────────────

(defun +carlos/magent-register-tools ()
  "Register Carlos's Magent tools to magent-tools-catalog if available."
  (when (boundp 'magent-tools-catalog)
    (when +carlos/magent-tool-flycheck-errors
      (add-to-list 'magent-tools-catalog
                   `(:name "flycheck_errors" :tool ,+carlos/magent-tool-flycheck-errors :permission flycheck_errors)))
    (when +carlos/magent-tool-lsp-navigation
      (add-to-list 'magent-tools-catalog
                   `(:name "lsp_navigation" :tool ,+carlos/magent-tool-lsp-navigation :permission lsp_navigation)))
    (when +carlos/magent-tool-snippet-expand
      (add-to-list 'magent-tools-catalog
                   `(:name "snippet_expand" :tool ,+carlos/magent-tool-snippet-expand :permission snippet_expand)))
    (when +carlos/magent-tool-select-model
      (add-to-list 'magent-tools-catalog
                   `(:name "select_model" :tool ,+carlos/magent-tool-select-model :permission select_model)))
    (when +carlos/magent-tool-rag-create-doc
      (add-to-list 'magent-tools-catalog
                   `(:name "rag_create_doc" :tool ,+carlos/magent-tool-rag-create-doc :permission rag_create_doc)))
    (when +carlos/magent-tool-magit-stage
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_stage" :tool ,+carlos/magent-tool-magit-stage :permission magit_stage)))
    (when +carlos/magent-tool-magit-commit
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_commit" :tool ,+carlos/magent-tool-magit-commit :permission magit_commit)))
    (when +carlos/magent-tool-magit-push
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_push" :tool ,+carlos/magent-tool-magit-push :permission magit_push)))
    (when +carlos/magent-tool-magit-status
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_status" :tool ,+carlos/magent-tool-magit-status :permission magit_status)))
    (when +carlos/magent-tool-magit-pull
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_pull" :tool ,+carlos/magent-tool-magit-pull :permission magit_pull)))
    (when +carlos/magent-tool-magit-checkout
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_checkout" :tool ,+carlos/magent-tool-magit-checkout :permission magit_checkout)))
    (when +carlos/magent-tool-magit-diff
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_diff" :tool ,+carlos/magent-tool-magit-diff :permission magit_diff)))
    (when +carlos/magent-tool-magit-log
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_log" :tool ,+carlos/magent-tool-magit-log :permission magit_log)))
    (when +carlos/magent-tool-magit-submodule-list
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_submodule_list" :tool ,+carlos/magent-tool-magit-submodule-list :permission magit_submodule_list)))
    (when +carlos/magent-tool-magit-submodule-update
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_submodule_update" :tool ,+carlos/magent-tool-magit-submodule-update :permission magit_submodule_update)))
    (when +carlos/magent-tool-magit-submodule-add
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_submodule_add" :tool ,+carlos/magent-tool-magit-submodule-add :permission magit_submodule_add)))
    (when +carlos/magent-tool-magit-branch-list
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_branch_list" :tool ,+carlos/magent-tool-magit-branch-list :permission magit_branch_list)))
    (when +carlos/magent-tool-magit-branch-delete
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_branch_delete" :tool ,+carlos/magent-tool-magit-branch-delete :permission magit_branch_delete)))
    (when +carlos/magent-tool-magit-merge
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_merge" :tool ,+carlos/magent-tool-magit-merge :permission magit_merge)))
    (when +carlos/magent-tool-magit-rebase
      (add-to-list 'magent-tools-catalog
                   `(:name "magit_rebase" :tool ,+carlos/magent-tool-magit-rebase :permission magit_rebase)))
    (when +carlos/magent-tool-forge-read-issue
      (add-to-list 'magent-tools-catalog
                   `(:name "forge_read_issue" :tool ,+carlos/magent-tool-forge-read-issue :permission forge_read_issue)))
    (when +carlos/magent-tool-forge-list-pull-requests
      (add-to-list 'magent-tools-catalog
                   `(:name "forge_list_pull_requests" :tool ,+carlos/magent-tool-forge-list-pull-requests :permission forge_list_pull_requests)))
    (when +carlos/magent-tool-forge-create-issue
      (add-to-list 'magent-tools-catalog
                   `(:name "forge_create_issue" :tool ,+carlos/magent-tool-forge-create-issue :permission forge_create_issue)))
    (when +carlos/magent-tool-forge-create-pull-request
      (add-to-list 'magent-tools-catalog
                   `(:name "forge_create_pull_request" :tool ,+carlos/magent-tool-forge-create-pull-request :permission forge_create_pull_request)))
    (when +carlos/magent-tool-forge-post-comment
      (add-to-list 'magent-tools-catalog
                   `(:name "forge_post_comment" :tool ,+carlos/magent-tool-forge-post-comment :permission forge_post_comment)))
    (when +carlos/magent-tool-elisp-smart-edit
      (add-to-list 'magent-tools-catalog
                   `(:name "elisp_smart_edit" :tool ,+carlos/magent-tool-elisp-smart-edit :permission elisp_smart_edit)))
    (when +carlos/magent-tool-nix-smart-edit
      (add-to-list 'magent-tools-catalog
                   `(:name "nix_smart_edit" :tool ,+carlos/magent-tool-nix-smart-edit :permission nix_smart_edit)))
    (when +carlos/magent-tool-python-smart-edit
      (add-to-list 'magent-tools-catalog
                   `(:name "python_smart_edit" :tool ,+carlos/magent-tool-python-smart-edit :permission python_smart_edit)))
    (when +carlos/magent-tool-ts-smart-edit
      (add-to-list 'magent-tools-catalog
                   `(:name "ts_smart_edit" :tool ,+carlos/magent-tool-ts-smart-edit :permission ts_smart_edit)))
    (when +carlos/magent-tool-c-smart-edit
      (add-to-list 'magent-tools-catalog
                   `(:name "c_smart_edit" :tool ,+carlos/magent-tool-c-smart-edit :permission c_smart_edit)))
    (when +carlos/magent-tool-go-smart-edit
      (add-to-list 'magent-tools-catalog
                   `(:name "go_smart_edit" :tool ,+carlos/magent-tool-go-smart-edit :permission go_smart_edit)))
    (when +carlos/magent-tool-org-smart-edit
      (add-to-list 'magent-tools-catalog
                   `(:name "org_smart_edit" :tool ,+carlos/magent-tool-org-smart-edit :permission org_smart_edit)))
    (when +carlos/magent-tool-sh-smart-edit
      (add-to-list 'magent-tools-catalog
                   `(:name "sh_smart_edit" :tool ,+carlos/magent-tool-sh-smart-edit :permission sh_smart_edit)))
    (when +carlos/magent-tool-markdown-smart-edit
      (add-to-list 'magent-tools-catalog
                   `(:name "markdown_smart_edit" :tool ,+carlos/magent-tool-markdown-smart-edit :permission markdown_smart_edit)))
    (when +carlos/magent-tool-rust-smart-edit
      (add-to-list 'magent-tools-catalog
                   `(:name "rust_smart_edit" :tool ,+carlos/magent-tool-rust-smart-edit :permission rust_smart_edit)))
    (when +carlos/magent-tool-rfc-search-topic
      (add-to-list 'magent-tools-catalog
                   `(:name "rfc_search_topic" :tool ,+carlos/magent-tool-rfc-search-topic :permission rfc_search_topic)))
    (when +carlos/magent-tool-rfc-read-section
      (add-to-list 'magent-tools-catalog
                   `(:name "rfc_read_section" :tool ,+carlos/magent-tool-rfc-read-section :permission rfc_read_section)))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-flycheck-errors
          (gptel-make-tool
           :name "flycheck_errors"
           :description "Retrieve Flycheck errors and warnings for a file or live buffer in structured format (file, line, column, level, message, checker)."
           :args '((:name "path" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-flycheck-errors
           :category "magent"))

    (setq +carlos/magent-tool-lsp-navigation
          (gptel-make-tool
           :name "lsp_navigation"
           :description "Resolve definition or reference locations for a symbol using Xref/Eglot to eliminate hallucinated names."
           :args '((:name "symbol" :type string)
                   (:name "action" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-lsp-navigation
           :category "magent"))

    (setq +carlos/magent-tool-snippet-expand
          (gptel-make-tool
           :name "snippet_expand"
           :description "Inspect, list or physically insert a Tempel snippet template in the active buffer."
           :args '((:name "name" :type string)
                   (:name "action" :type string)
                   (:name "mode" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-snippet-expand
           :category "magent"))

    (setq +carlos/magent-tool-select-model
          (gptel-make-tool
           :name "select_model"
           :description "Select and commit the model for a spawned subagent. Call BEFORE spawn_agent. Provide the task description and the target agent name ('explore' or 'general'); the runtime resolves the model by complexity and the user's tier cap and applies it to the subagent automatically. Use backend_preferred to force a specific backend (e.g. 'gemini' when user explicitly requests Google/Gemini)."
           :args '((:name "task_description" :type string)
                   (:name "agent" :type string)
                   (:name "complexity" :type string)
                   (:name "min_tier" :type string)
                   (:name "backend_preferred" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-select-model
           :category "magent"))

    (setq +carlos/magent-tool-rag-create-doc
          (gptel-make-tool
           :name "rag_create_doc"
           :description "Generate or update a canonical Org-mode RAG reference document under docs/ by introspecting local Emacs function/variable symbols (zero network token cost)."
           :args '((:name "symbols" :type string)
                   (:name "target_file" :type string)
                   (:name "title" :type string)
                   (:name "description" :type string)
                   (:name "filetags" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-rag-create-doc
           :category "magent"))

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    ;; ── Docker Native Tools ──────────────────────────────────────────────
    
    
    

    

    

    

    ;; ── Systemd Native Tools ─────────────────────────────────────────────
    
    
    

    

    

    

    ;; ── Log Inspection Native Tool ──────────────────────────────────────
    (defvar +carlos/magent-tool-log-inspect nil "Gptel tool for log file inspection.")

    (defun +carlos/magent-tool-log-inspect (log-path &optional regex severity tail remote-host _reason)
      "Inspect log file (local or via TRAMP) with filtering by regex and severity."
      (if (or (not log-path) (string-empty-p log-path))
          (+carlos/magent-tool-result '((status . "error") (message . "log_path parameter is required")))
        (let* ((default-directory (if (and remote-host (not (string-empty-p remote-host)))
                                      (file-name-as-directory remote-host)
                                    default-directory))
               (full-path (expand-file-name log-path default-directory)))
          (if (not (file-exists-p full-path))
              (+carlos/magent-tool-result (list (cons "status" "error")
                                                (cons "message" (format "Log file not found: %s" log-path))))
            (let* ((n-lines (or tail "100"))
                   (cmd (format "tail -n %s %s" (shell-quote-argument n-lines) (shell-quote-argument full-path)))
                   (raw (+carlos/magent-sanitize-string (shell-command-to-string cmd)))
                   (lines (split-string raw "\n" t))
                   (filtered lines))
              (when (and severity (not (string-empty-p severity)))
                (setq filtered (cl-remove-if-not
                                (lambda (line) (string-match-p (regexp-quote severity) line))
                                filtered)))
              (when (and regex (not (string-empty-p regex)))
                (setq filtered (cl-remove-if-not
                                (lambda (line) (string-match-p regex line))
                                filtered)))
              (+carlos/magent-tool-result
               (list (cons "status" "success")
                     (cons "log_path" log-path)
                     (cons "total_lines_read" (length lines))
                     (cons "matched_count" (length filtered))
                     (cons "lines" (mapconcat #'identity (cl-subseq filtered 0 (min (length filtered) 100)) "\n")))))))))

    

    

    

    

    

    

    (setq +carlos/magent-tool-log-inspect
          (gptel-make-tool
           :name "log_inspect"
           :description "Inspect log files (local or via TRAMP) with combined regex and severity filtering."
           :args '((:name "log_path" :type string)
                   (:name "regex" :type string)
                   (:name "severity" :type string)
                   (:name "tail" :type string)
                   (:name "remote_host" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-log-inspect
           :category "magent"))

    

    (when (featurep 'magent-tools)
      (+carlos/magent-register-tools))))

(with-eval-after-load 'magent-tools
  (+carlos/magent-register-tools))

(with-eval-after-load 'magent-config
  (when (boundp 'magent-enable-tools)
    (add-to-list 'magent-enable-tools 'flycheck_errors)
    (add-to-list 'magent-enable-tools 'lsp_navigation)
    (add-to-list 'magent-enable-tools 'snippet_expand)
    (add-to-list 'magent-enable-tools 'select_model)
    (add-to-list 'magent-enable-tools 'rag_create_doc)
    (add-to-list 'magent-enable-tools 'magit_stage)
    (add-to-list 'magent-enable-tools 'magit_commit)
    (add-to-list 'magent-enable-tools 'magit_push)
    (add-to-list 'magent-enable-tools 'magit_status)
    (add-to-list 'magent-enable-tools 'magit_pull)
    (add-to-list 'magent-enable-tools 'magit_checkout)
    (add-to-list 'magent-enable-tools 'magit_diff)
    (add-to-list 'magent-enable-tools 'magit_log)
    (add-to-list 'magent-enable-tools 'magit_submodule_list)
    (add-to-list 'magent-enable-tools 'magit_submodule_update)
    (add-to-list 'magent-enable-tools 'magit_submodule_add)
    (add-to-list 'magent-enable-tools 'magit_branch_list)
    (add-to-list 'magent-enable-tools 'magit_branch_delete)
    (add-to-list 'magent-enable-tools 'magit_merge)
    (add-to-list 'magent-enable-tools 'magit_rebase)
    (add-to-list 'magent-enable-tools 'elisp_smart_edit)
    (add-to-list 'magent-enable-tools 'nix_smart_edit)
    (add-to-list 'magent-enable-tools 'python_smart_edit)
    (add-to-list 'magent-enable-tools 'ts_smart_edit)
    (add-to-list 'magent-enable-tools 'c_smart_edit)
    (add-to-list 'magent-enable-tools 'go_smart_edit)
    (add-to-list 'magent-enable-tools 'org_smart_edit)
    (add-to-list 'magent-enable-tools 'sh_smart_edit)
    (add-to-list 'magent-enable-tools 'markdown_smart_edit)
    (add-to-list 'magent-enable-tools 'rust_smart_edit)
    (add-to-list 'magent-enable-tools 'forge_read_issue)
    (add-to-list 'magent-enable-tools 'forge_list_pull_requests)
    (add-to-list 'magent-enable-tools 'docker_ps)
    (add-to-list 'magent-enable-tools 'docker_logs)
    (add-to-list 'magent-enable-tools 'docker_action)
    (add-to-list 'magent-enable-tools 'systemd_status)
    (add-to-list 'magent-enable-tools 'systemd_action)
    (add-to-list 'magent-enable-tools 'systemd_journal)
    (add-to-list 'magent-enable-tools 'log_inspect)
    (add-to-list 'magent-enable-tools 'rfc_search_topic)
    (add-to-list 'magent-enable-tools 'context_search)
    (add-to-list 'magent-enable-tools 'rfc_read_section)))

;; ---------------------------------------------------------------------------
;; Ferramenta nativa de busca de contexto
;; ---------------------------------------------------------------------------
(defun +carlos/magent-tool-context_search (query &optional directory)
  "Busca a string QUERY (texto simples) em DIRECTORY (padrão `default-directory').
Retorna uma string JSON contendo uma lista de alistas com as chaves :file,
:line e :snippet.
A pesquisa usa o próprio `grep' dentro do Emacs, garantindo que não haja
edições externas e mantendo a integridade da AST.
A lista é limitada a 200 ocorrências para evitar payloads excessivos."
  (let* ((dir (or directory default-directory))
         (cmd (format "grep -nH -F %s %s/*"
                      (shell-quote-argument query)
                      (shell-quote-argument dir)))
         (output (shell-command-to-string cmd))
         (lines (split-string output "\n" t))
         (matches (seq-take
                   (seq-filter
                    (lambda (ln) (not (string-empty-p ln)))
                    (mapcar
                     (lambda (ln)
                       (when (string-match "^\\([^:]+\\):\\([0-9]+\\):\\(.*\\)$" ln)
                         (list :file (match-string 1 ln)
                               :line (string-to-number (match-string 2 ln))
                               :snippet (string-trim (match-string 3 ln)))))
                     lines))
                   200)))
    (json-encode matches)))

(provide 'custom-magent-tools)
;;; custom-magent-tools.el ends here
