;;; custom-magent-tools.el --- Magent tools: fixes, directivas e tools curadas -*- lexical-binding: t; -*-

;;; Commentary:
;; Fixes de streaming/schema para backends Gemini, sanitização de paths e
;; parâmetros de tools, directivas de sistema injetadas no system prompt e
;; as ferramentas curadas (flycheck_errors, lsp_navigation, snippet_expand).

;;; Code:

(require 'cl-lib)
(require 'json)

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
(defvar +carlos/magent-message-max-len 400
  "Comprimento máximo de mensagem permitido no *Messages*.
Mensagens mais longas são suprimidas (exceto erros).")

(defcustom +carlos/magent-tool-result-max-chars 8000
  "Limite de caracteres por tool result por turno.
Resultados que excedem este cap são truncados com nota de truncamento.
Acumulador por turno: quando a soma de chars de todos os results do turno
excede este valor, novos results são truncados."
  :type 'integer
  :group '+carlos/ai)

(defun +carlos/magent-suppress-long-messages-a (orig-fn format-string &rest args)
  "Advice de `message' que suprime dumps longos não-erro do *Messages*.
ORIG-FN é `message'; FORMAT-STRING e ARGS são o texto a exibir."
  (let* ((text (condition-case nil
                   (apply #'format format-string args)
                 (error format-string)))
         (is-error (string-match-p "\\(?:Error\\|Warning\\|error\\|timeout\\|Stopped\\|Wrong type\\|DEBUG\\)" text)))
    (if (and (not is-error)
             (> (length text) +carlos/magent-message-max-len))
        text  ;; retorna o texto mas não chama message (suprimido do *Messages*)
      (apply orig-fn format-string args))))

(advice-add 'message :around #'+carlos/magent-suppress-long-messages-a)

;; ── Diagnóstico: Desativar magent-log ──────────────────────────────
(defvar +carlos/magent-disable-logging t
  "Non-nil desativa completamente o magent-log para evitar chamadas de log/message.")

(defun +carlos/magent-log-override-a (orig format-string &rest args)
  "Advice que suprime `magent-log' quando a var de diagnóstico está ativa.
ORIG é `magent-log'; FORMAT-STRING e ARGS são o texto do log."
  (unless +carlos/magent-disable-logging
    (apply orig format-string args)))

(with-eval-after-load 'magent-log
  (when (fboundp 'magent-log)
    (advice-add 'magent-log :around #'+carlos/magent-log-override-a)))

;; Desativa variaveis internas de log do magent
(setq magent-enable-logging nil)

;; ── Fix para Gemini: Normalizar nomes de tool calls (símbolo -> string) ──
;; O gptel-gemini retorna os nomes de ferramentas em `:tool-use` como símbolos
;; Lisp (ex.: 'glob, 'read_file). `magent-llm-gptel--handle-tool-use` busca a
;; tool-spec usando (equal (gptel-tool-name ts) name). Como (gptel-tool-name ts)
;; é string ("glob"), (equal "glob" 'glob) retorna nil -> tool-spec fica nil,
;; o Magent ignora a chamada da ferramenta e a requisição expira em 120s.
;; Esta advice sanitiza `info` ANTES de extrair `:tool-use`, convertendo símbolos
;; para strings.
(defun +carlos/magent-sanitize-tool-use-name-a (orig-fn state fsm &rest args)
  "Garante que os nomes em `:tool-use' sejam strings.
ORIG-FN é o handler nativo de tool-use; STATE e FSM são o estado e a FSM
do gptel; ARGS são repassados intactos.  Evita falha em `equal' com
símbolos e previne o timeout de 120s no Gemini."
  (when-let* ((info (and (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm))))
    (when (fboundp 'magent-llm-gptel--sanitize-info)
      (magent-llm-gptel--sanitize-info info)))
  (apply orig-fn state fsm args))

;; ── Fix para Gemini Streaming: Aridade de `gptel--parse-response' ─────
;; A função original `magent-llm-gptel--sanitize-after-parse-response-a' do magent
;; declarava apenas 4 argumentos `(orig-fn backend response info)`. No gptel-gemini,
;; `gptel--parse-response' aceita 5 argumentos (`include-text` opcional).
;; Redefinimos a função original com `&rest args` para que a chamada de
;; `magent-llm-gptel--install-boundary-advice` não recoloque a versão de 4 argumentos.
(with-eval-after-load 'magent-llm-gptel
  (defun magent-llm-gptel--sanitize-after-parse-response-a
      (orig-fn backend response info &rest args)
    "Sanitize Magent-managed INFO after gptel parses a response.
Accept &rest ARGS for Gemini streaming 5th argument."
    (prog1 (apply orig-fn backend response info args)
      (when (and (fboundp 'magent-llm-gptel--managed-info-p)
                 (magent-llm-gptel--managed-info-p info))
        (magent-llm-gptel--sanitize-info info))))
  (when (fboundp 'magent-llm-gptel--handle-tool-use)
    (advice-add 'magent-llm-gptel--handle-tool-use
                :around #'+carlos/magent-sanitize-tool-use-name-a)))

;; ── Fix: schema da tool wait_agent para backends Gemini ──────────────
;; O argspec `job_ids' do magent declara `:type array` sem `:items`, e o
;; gptel repassa o schema cru ao Gemini, que exige `items' em arrays
;; (erro "properties[job_ids].items: missing field" — quebra TODA chamada
;; Gemini com as tools do Magent). Aplicamos o `:items' via setf na struct
;; gptel-tool após o load (fix do side do config; o source pinado do magent
;; não deve ser editado). O `:items' deve ser `(:type "string")' — string,
;; não símbolo — pois o json-serialize nativo do Emacs 30 rejeita símbolos
;; (erro "wrong-type-argument json-value-p string" na serialização das tools).
(with-eval-after-load 'magent-tools
  (when (and (boundp 'magent-tools--wait-agent-tool)
             (fboundp 'gptel-tool-args))
    (let ((tool magent-tools--wait-agent-tool))
      (setf (gptel-tool-args tool)
            (mapcar (lambda (arg)
                      (if (and (stringp (plist-get arg :name))
                               (equal (plist-get arg :name) "job_ids"))
                          (plist-put (copy-sequence arg)
                                     :items '(:type "string"))
                        arg))
                    (gptel-tool-args tool))))))

;; ── Tool Sanitization & Path Auto-Expansion ──────────────────────────
(defconst +carlos/magent-system-directives
  "CRITICAL MAGENT TOOL DIRECTIVES:
1. ABSOLUTE PATHS: Use full absolute paths starting with '/' (e.g. '/home/carlosfilho/...').
2. NON-EMPTY PARAMETERS: Do not call write_file or edit_file with empty or missing args.
3. NATIVE TOOLS FIRST: Prefer 'read_file', 'grep' (ripgrep), and 'glob' over shell commands.
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
 11. SUBAGENT RETRY (INTELLIGENT FALLBACK): When a subagent fails with timeout or model_unavailable error, you MAY retry with a stronger model: call 'select_model' with min-tier='free' (if current was local) or min-tier='paid' (if current was free), then 'spawn_agent' with the same task. Maximum 1 retry per subagent — do not retry if already retried. Do NOT retry context_length_exceeded errors (compact first instead)."
  "Instruções estritas de uso de ferramentas para os modelos do Magent.")

(defun +carlos/magent-inject-system-directives (composed &rest _)
  "Append Magent system directives and model menu to COMPOSED message."
  (concat composed "\n\n" (+carlos/magent-system-directives-render)))

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
(defvar +carlos/magent-tool-select-model nil
  "Gptel tool for orchestrator model selection (Fase A).")

(defun +carlos/magent-tool-result (payload &optional error)
  "Constrói o resultado de uma tool do Magent a partir de PAYLOAD (JSON-safe).
Quando `magent-protocol' está carregado retorna um `magent-tool-result'
com `:output' JSON, `:success', `:status' e `:error'; caso contrário (ex.:
testes batch sem o magent), retorna o JSON como string para compatibilidade
com o gptel.  ERROR, quando presente, vira um resultado de falha e o payload
é descartado."
  (let ((output (if error (format "Error: %s" error) (json-encode payload))))
    (if (fboundp 'magent-tool-result-create)
        (magent-tool-result-create
         :output output
         :success (null error)
         :status (if error 'failed 'completed)
         :error error)
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
     ((string-match-p "MLX\\|Ollama" backend-name) "grátis (local)")
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
                        (if (string-match-p "MLX" backend-name)
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
                      (if (string-match-p "MLX" backend-name)
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
(`+carlos/magent--tier-sorted-entries').  BACKENDS e LOCAL-MODELS são
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
                       (gptel-get-backend (car entry)))
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
    (task-description &optional agent complexity _reason)
  "Handler da tool `select_model' (Fase A).
TASK-DESCRIPTION descreve a tarefa do subagente; AGENT é o nome do
subagente alvo (default \"general\"); COMPLEXITY é opcional, \"simple\",
\"moderate\" ou \"deep\" (senão inferido de TASK-DESCRIPTION); _REASON é
display-only e descartado.  Resolve o modelo na escada de tiers, registra
um override transiente em `+carlos/magent-subagent-model-overrides' e
retorna um `magent-tool-result' com o payload JSON (backend, model, tier,
reason)."
  (let* ((agent (or agent "general"))
         (hints (and (boundp '+carlos/magent-subagent-profiles)
                     (cdr (assoc agent +carlos/magent-subagent-profiles))))
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
                   `(:name "select_model" :tool ,+carlos/magent-tool-select-model :permission select_model)))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-flycheck-errors
          (gptel-make-tool
           :name "flycheck_errors"
           :description "Retrieve Flycheck errors and warnings for a file or live buffer in structured format (file, line, column, level, message, checker)."
           :args '((:name "path" :type string :description "Optional file or buffer path")
                   (:name "reason" :type string :description "Reason for checking errors"))
           :function #'+carlos/magent-tool-flycheck-errors
           :category "magent"))

    (setq +carlos/magent-tool-lsp-navigation
          (gptel-make-tool
           :name "lsp_navigation"
           :description "Resolve definition or reference locations for a symbol using Xref/Eglot to eliminate hallucinated names."
           :args '((:name "symbol" :type string :description "Symbol or function name to resolve")
                   (:name "action" :type string :description "Either 'definition' or 'references'")
                   (:name "reason" :type string :description "Reason for navigation"))
           :function #'+carlos/magent-tool-lsp-navigation
           :category "magent"))

    (setq +carlos/magent-tool-snippet-expand
          (gptel-make-tool
           :name "snippet_expand"
           :description "Inspect, list or physically insert a Tempel snippet template in the active buffer."
           :args '((:name "name" :type string :description "Snippet name (e.g. 'deftest')")
                   (:name "action" :type string :description "Either 'inspect' (to get structure), 'list' (to list names) or 'insert' (to physically expand it at point)")
                   (:name "mode" :type string :description "Optional major-mode name filter")
                   (:name "reason" :type string :description "Reason for snippet expansion"))
           :function #'+carlos/magent-tool-snippet-expand
           :category "magent"))

    (setq +carlos/magent-tool-select-model
          (gptel-make-tool
           :name "select_model"
           :description "Select and commit the model for a spawned subagent. Call BEFORE spawn_agent. Provide the task description and the target agent name ('explore' or 'general'); the runtime resolves the model by complexity and the user's tier cap and applies it to the subagent automatically."
           :args '((:name "task_description" :type string :description "The task the subagent will perform")
                   (:name "agent" :type string :description "Target agent name (e.g. 'explore' or 'general')")
                   (:name "complexity" :type string :description "Optional: 'simple', 'moderate' or 'deep'. Inferred from task_description when omitted.")
                   (:name "reason" :type string :description "Reason for this tool call"))
           :function #'+carlos/magent-tool-select-model
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
    (add-to-list 'magent-enable-tools 'select_model)))

(provide 'custom-magent-tools)
;;; custom-magent-tools.el ends here
