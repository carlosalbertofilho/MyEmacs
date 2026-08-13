;;; custom-magent-tools.el --- Magent tools: fixes, directivas e tools curadas -*- lexical-binding: t; -*-

;;; Commentary:
;; Fixes de streaming/schema para backends Gemini, sanitização de paths e
;; parâmetros de tools, directivas de sistema injetadas no system prompt e
;; as ferramentas curadas (flycheck_errors, lsp_navigation, snippet_expand).

;;; Code:

(defvar magent-enable-logging)
(defvar magent-enable-tools)
(defvar magent-tools-catalog)
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
(declare-function magent-llm-tool-call-event "magent-llm")

;; ── Silenciar *Messages*: filtrar dumps longos (plist de tools / system prompt) ──
;; O Emacs/gptel imprime ocasionalmente plists gigantes (lista de tools, system
;; prompt do agente) via `message'. Suprimimos linhas > 400 chars no *Messages*
;; mas mantemos ERROS (prefixo Error/Warning) sempre visíveis.
(defvar +carlos/magent-message-max-len 400
  "Comprimento máximo de mensagem permitido no *Messages*.
Mensagens mais longas são suprimidas (exceto erros).")

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
8. SUBAGENT DELEGATION: You are the ORCHESTRATOR — keep your context window lean. For codebase exploration, file analysis, or multi-step research tasks, ALWAYS delegate: call 'spawn_agent' with agent='explore' (codebase search/analysis) or 'general' (broader multi-step work), giving the subagent a precise task and absolute paths, then call 'wait_agent' and synthesize a CONCISE summary of the subagent's findings in your reply — do not paste the full transcript into your turn. Subagents run on a stronger cloud model with a larger context window."
  "Instruções estritas de uso de ferramentas para os modelos do Magent.")

(defun +carlos/magent-inject-system-directives (composed &rest _)
  "Append Magent system directives to the COMPOSED system message."
  (concat composed "\n\n" +carlos/magent-system-directives))

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

(defun +carlos/magent-tool-flycheck-errors (args)
  "Handler para a ferramenta `flycheck_errors`.
Retorna erros do Flycheck no buffer ativo ou em ARGS :path."
  (let* ((path (plist-get args :path))
         (buf (if (and path (not (string-empty-p path)))
                  (find-buffer-visiting (expand-file-name path))
                (current-buffer))))
    (if (not buf)
        `(:status "error" :message ,(format "Buffer para '%s' não encontrado." (or path "current")))
      (with-current-buffer buf
        (if (and (boundp 'flycheck-mode) flycheck-mode)
            (let ((errors (mapcar (lambda (err)
                                    `(:line ,(flycheck-error-line err)
                                      :column ,(flycheck-error-column err)
                                      :level ,(symbol-name (flycheck-error-level err))
                                      :message ,(flycheck-error-message err)
                                      :checker ,(symbol-name (flycheck-error-checker err))))
                                  (or (bound-and-true-p flycheck-current-errors) nil))))
              `(:status "success"
                :buffer ,(buffer-name buf)
                :file ,(or (buffer-file-name buf) "none")
                :total_errors ,(length errors)
                :errors ,errors))
          `(:status "info" :message "Flycheck-mode não está ativo no buffer." :total_errors 0 :errors []))))))

(defun +carlos/magent-tool-lsp-navigation (args)
  "Handler para a ferramenta `lsp_navigation`.
Resolve definições ou referências de ARGS :symbol usando xref/Eglot."
  (let* ((sym-str (plist-get args :symbol))
         (action (or (plist-get args :action) "definition")))
    (if (not (and sym-str (not (string-empty-p sym-str))))
        `(:status "error" :message "Parâmetro :symbol é obrigatório.")
      (condition-case err
          (let ((xref-backend (and (fboundp 'xref-find-backend) (xref-find-backend))))
            (if (or (not xref-backend)
                    (and (eq xref-backend 'etags)
                         (not (bound-and-true-p tags-file-name))
                         (not (locate-dominating-file default-directory "TAGS"))))
                `(:status "info" :message "Nenhum backend LSP ativo no buffer atual e nenhuma tabela de TAGS disponível.")
              (let* ((xrefs (if (string= action "references")
                                (xref-backend-references xref-backend sym-str)
                              (xref-backend-definitions xref-backend sym-str)))
                     (results (mapcar (lambda (x)
                                        (let* ((loc (xref-item-location x))
                                               (summary (xref-item-summary x))
                                               (file (and (fboundp 'xref-location-group) (xref-location-group loc)))
                                               (line (and (fboundp 'xref-location-line) (xref-location-line loc))))
                                          `(:summary ,summary :file ,file :line ,line)))
                                      xrefs)))
                `(:status "success"
                  :symbol ,sym-str
                  :action ,action
                  :total ,(length results)
                  :results ,results))))
        (error `(:status "error" :message ,(error-message-string err)))))))

(defun +carlos/magent-tool-snippet-expand (args)
  "Handler para a ferramenta `snippet_expand`.
Retorna templates do Tempel, a estrutura do snippet ARGS
:name, ou insere o snippet no buffer."
  (let* ((name-str (plist-get args :name))
         (mode-str (plist-get args :mode))
         (action-str (plist-get args :action))
         (target-mode (if mode-str (intern mode-str) major-mode)))
    (if (not (require 'tempel nil t))
        `(:status "error" :message "Pacote tempel não está disponível.")
      (let ((templates (and (fboundp 'tempel--templates) (tempel--templates))))
        (cond
         ;; Ação: Inserir snippet fisicamente no buffer ativo
         ((string= action-str "insert")
          (if (and name-str (not (string-empty-p name-str)))
              (let ((sym (intern name-str)))
                (if (assoc sym templates)
                    (condition-case err
                        (progn
                          ;; Executa a inserção no buffer atual
                          (tempel-insert sym)
                          `(:status "success"
                            :message ,(format "Snippet '%s' inserido com sucesso no buffer." name-str)))
                      (error `(:status "error" :message ,(format "Erro ao inserir snippet: %s" (error-message-string err)))))
                  `(:status "error" :message ,(format "Snippet '%s' não encontrado." name-str))))
            `(:status "error" :message "Nome do snippet é obrigatório para inserção.")))

         ;; Ação: Inspecionar estrutura de um snippet
         ((and name-str (not (string-empty-p name-str)))
          (let ((found (assoc (intern name-str) templates)))
            (if found
                `(:status "success"
                  :name ,name-str
                  :template ,(format "%S" (cdr found)))
              `(:status "error" :message ,(format "Snippet '%s' não encontrado." name-str)))))

         ;; Ação padrão: Listar todos os snippets
         (t
          (let ((names (mapcar (lambda (tmpl) (symbol-name (car tmpl))) templates)))
            `(:status "success"
              :mode ,(symbol-name target-mode)
              :total ,(length names)
              :snippets ,names))))))))

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
                   `(:name "snippet_expand" :tool ,+carlos/magent-tool-snippet-expand :permission snippet_expand)))))

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

    (when (featurep 'magent-tools)
      (+carlos/magent-register-tools))))

(with-eval-after-load 'magent-tools
  (+carlos/magent-register-tools))

(with-eval-after-load 'magent-config
  (when (boundp 'magent-enable-tools)
    (add-to-list 'magent-enable-tools 'flycheck_errors)
    (add-to-list 'magent-enable-tools 'lsp_navigation)
    (add-to-list 'magent-enable-tools 'snippet_expand)))

(provide 'custom-magent-tools)
;;; custom-magent-tools.el ends here
