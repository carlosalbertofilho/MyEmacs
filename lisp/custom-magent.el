;;; custom-magent.el --- Magent (AI coding agent nativo) -*- lexical-binding: t; -*-

;;; Commentary:
;; Magent: agente de codificação Emacs-Lisp com 15 tools, permissões por
;; agente, sessões por projeto (ledger), skills e capabilities.  Frontend
;; agent-shell (ACP in-process).  Transporte continua sendo gptel-request.
;; Instalado via receita git Elpaca pinada em 50ef707 (não está no MELPA).

;;; Code:

(defvar gptel-backend-list)
(defvar magent-skill-directories)
(defvar magent-enable-logging)
(declare-function magent-start "magent-agent-shell")
(declare-function magent-agent-shell-interrupt "magent-agent-shell")
(declare-function magent-agent-shell-prompt-region "magent-agent-shell")
(declare-function magent-agent-shell-ensure-config "magent-agent-shell")
(declare-function magent-tools--failed "magent-tools")
(declare-function +carlos/gptel-tracker-file "custom-ai")
(declare-function magent-llm-gptel--parse-dsml-tool-calls "magent-llm-gptel")
(declare-function magent-llm-gptel--prepare-textual-continuation "magent-llm-gptel")
(declare-function magent-llm-gptel--emit-tool-call-batch "magent-llm-gptel")
(declare-function magent-llm-gptel--metadata "magent-llm-gptel")
(declare-function magent-llm-gptel--pending-tool-use-p "magent-llm-gptel")
(declare-function magent-llm-gptel--continue-with-user-message "magent-llm-gptel")
(declare-function magent-llm-tool-call-event "magent-llm")

;; ── Diagnóstico: Desativar magent-log ──────────────────────────────
(defvar +carlos/magent-disable-logging t
  "Non-nil desativa completamente o magent-log para evitar chamadas de log/message.")

(defun +carlos/magent-log-override-a (orig format-string &rest args)
  "Ignora `magent-log` quando `+carlos/magent-disable-logging' é non-nil."
  (unless +carlos/magent-disable-logging
    (apply orig format-string args)))

(with-eval-after-load 'magent-log
  (when (fboundp 'magent-log)
    (advice-add 'magent-log :around #'+carlos/magent-log-override-a)))

;; Desativa variaveis internas de log do magent
(setq magent-enable-logging nil)

;; ── Diagnóstico: FSM customizado ──────────────────────────────────
;; O FSM customizado do magent (`magent-llm-gptel--make-sampling-fsm`) trava
;; o daemon em busy-wait (CPU ~80%, timeout de 120s não dispara).  Este toggle
;; desativa o FSM customizado: `magent-llm-gptel-sample` então recebe o FSM
;; default do gptel (`gptel-make-fsm`).  DIAGNÓSTICO — manter apenas para testar
;; a hipótese; remover depois que a causa raiz for confirmada.
(defvar +carlos/magent-disable-custom-fsm nil
  "Non-nil usa o FSM default do gptel em vez do FSM customizado do magent.")

(defun +carlos/magent--fsm-override-a (orig &rest args)
  "ORIG (magent-llm-gptel--make-sampling-fsm) ou FSM default do gptel.
Quando `+carlos/magent-disable-custom-fsm' é non-nil, ignora ORIG/ARGS e
retorna `(gptel-make-fsm)', deixando o gptel cuidar de tudo (handlers
padrão de tool-use e done)."
  (if +carlos/magent-disable-custom-fsm
      (gptel-make-fsm)
    (apply orig args)))

(with-eval-after-load 'magent-llm-gptel
  (when (fboundp 'magent-llm-gptel--make-sampling-fsm)
    (advice-add 'magent-llm-gptel--make-sampling-fsm :around
                #'+carlos/magent--fsm-override-a)))

;; ── Fix para Gemini: Normalizar nomes de tool calls (símbolo -> string) ──
;; O gptel-gemini retorna os nomes de ferramentas em `:tool-use` como símbolos
;; Lisp (ex.: 'glob, 'read_file). `magent-llm-gptel--handle-tool-use` busca a
;; tool-spec usando (equal (gptel-tool-name ts) name). Como (gptel-tool-name ts)
;; é string ("glob"), (equal "glob" 'glob) retorna nil -> tool-spec fica nil,
;; o Magent ignora a chamada da ferramenta e a requisição expira em 120s.
;; Esta advice sanitiza `info` ANTES de extrair `:tool-use`, convertendo símbolos
;; para strings.
(defun +carlos/magent-sanitize-tool-use-name-a (orig-fn state fsm)
  "Garante que os nomes em `:tool-use' sejam strings.
Evita falha em `equal' com símbolos e previne o timeout de 120s no Gemini."
  (when-let* ((info (and (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm))))
    (when (fboundp 'magent-llm-gptel--sanitize-info)
      (magent-llm-gptel--sanitize-info info)))
  (funcall orig-fn state fsm))

(with-eval-after-load 'magent-llm-gptel
  (when (fboundp 'magent-llm-gptel--handle-tool-use)
    (advice-add 'magent-llm-gptel--handle-tool-use
                :around #'+carlos/magent-sanitize-tool-use-name-a)))

(defun +carlos/magent-start ()
  "Garante o carregamento do Magent e inicia a sessão agent-shell."
  (interactive)
  (require 'gptel)
  (require 'magent)
  (require 'magent-agent-shell)
  (unless gptel-backend
    (setq gptel-backend (or (gptel-get-backend "OpenAI")
                            (gptel-get-backend "Gemini")
                            (gptel-get-backend "Zen Claude")
                            (gptel-get-backend "Ollama Local")
                            (car gptel-backend-list))))
  (unless gptel-model
    (setq gptel-model (or "claude-sonnet-5" "qwen2.5-coder:3b")))
  (if (fboundp 'magent-start)
      (magent-start)
    (user-error "Magent ainda não foi construído/carregado pelo Elpaca")))

(defun +carlos/magent-agent-shell-interrupt ()
  "Interrompe a requisição ativa do Magent."
  (interactive)
  (require 'magent)
  (require 'magent-agent-shell)
  (if (fboundp 'magent-agent-shell-interrupt)
      (magent-agent-shell-interrupt)
    (user-error "Magent ainda não foi construído/carregado pelo Elpaca")))

(defun +carlos/magent-agent-shell-prompt-region ()
  "Envia a região para o Magent."
  (interactive)
  (require 'magent)
  (require 'magent-agent-shell)
  (if (fboundp 'magent-agent-shell-prompt-region)
      (magent-agent-shell-prompt-region)
    (user-error "Magent ainda não foi construído/carregado pelo Elpaca")))

(elpaca (magent :fetcher github
                :repo "Jamie-Cui/magent"
                :ref "50ef707"
                :files ("lisp/magent*.el" "prompts" "skills" "capabilities")))

(use-package magent
  :ensure nil
  :custom
  (magent-default-agent "build")
  (magent-enable-audit-log t)
  (magent-project-instruction-file-names '("AGENTS.md"))
  (magent-include-reasoning t)
  (magent-skill-directories
   (append (let ((new-dir (expand-file-name "magent/skills" user-emacs-directory))
                 (old-dir (expand-file-name "magent-skills" user-emacs-directory)))
             (append (when (file-directory-p old-dir) (list old-dir))
                     (list new-dir)))
           (when-let* ((proj (project-current))
                       (root (project-root proj))
                       (local-dir (expand-file-name "magent/skills" root)))
             (when (file-directory-p local-dir)
               (list local-dir))))))

(with-eval-after-load 'magent
  (when (require 'magent-agent-shell nil t)
    (when (fboundp 'magent-agent-shell-ensure-config)
      (magent-agent-shell-ensure-config))))

;; ── Fix: schema da tool wait_agent para backends Gemini ──────────────
;; O argspec `job_ids' do magent declara `:type array' sem `:items', e o
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
5. SUBAGENT LIFECYCLE: When using 'spawn_agent', call 'wait_agent(job_id)' to get results.
6. TOOL CALL FORMAT: Always request tool use through the native structured function-calling mechanism. Tool calls MUST be emitted as native structured function calls in the FINAL response text — NEVER inside reasoning/thinking blocks, NEVER as free-form XML text. Reasoning blocks are never executed, so a tool call written there is silently dropped. If your backend only supports textual tool calls, use EXACTLY this DSML envelope, with nothing else between the tags:
<tool_calls>
<invoke name=\"read_file\">
<parameter name=\"path\">/absolute/path/to/file</parameter>
</invoke>
</tool_calls>
Do NOT use '<tool_call>', '<function=...>', or '<parameter=...>' forms; the runtime only parses the '<tool_calls>'/'<invoke name=...>'/'<parameter name=...>' syntax shown above. After requesting a tool, your next message MUST include the native tool call, not text about calling it.
7. AVOID SIGPIPE (exit 141): Do not pipe long listings into 'head'/'tail' (e.g. 'find ... | head -50'). Closing the pipe kills the producer with SIGPIPE (exit 141), which the runtime reports as a FAILED tool result. Use 'find ... -maxdepth N' with explicit filters, or 'rg --max-count' instead."
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

;; ── FSM de Orquestração (THINK/DECIDE/RETRY) ──────────────────────
;; Bailiza o comportamento do modelo local: intercepta o terminal do turn
;; (magent-llm-gptel--emit-completed-or-textual-tool-calls, o ponto único por
;; onde passa todo turn vazio) e recupera tool calls que o modelo escreveu no
;; stream de reasoning — que o magent NUNCA parseia. Ver
;; docs/magent-reference.org "Máquina de Estados (FSM) para bailizar o modelo".
(defvar +carlos/magent-fsm-enabled t
  "Habilita/desabilita a FSM de orquestração do Magent (THINK/DECIDE/RETRY).")
(defvar +carlos/magent-fsm-max-retries 1
  "Número máximo de retries quando o turn termina vazio sem tool call.")
(defvar +carlos/magent-fsm-retry-message
  "Your previous response contained no text and no tool call. You MUST now either answer directly in plain text, or request a tool using the native function-calling mechanism. The tool call MUST appear in the final response text — never inside thinking/reasoning blocks."
  "Mensagem injetada no RETRY state quando o turn terminou vazio.")

(defun +carlos/magent--fsm-reasoning-text (state)
  "Retorna o texto completo do reasoning acumulado em STATE.
Reasoning chunks são armazenados invertidos em `:reasoning-chunks'."
  (let ((chunks (gethash :reasoning-chunks state)))
    (apply #'concat (nreverse (copy-sequence chunks)))))

(defun +carlos/magent--fsm-parse-claude-xml-params (inner)
  "Parseia blocos <parameter=KEY>VALUE</parameter> de INNER num plist.
Formato emitido por Qwen3.5-9B (Claude-XML legado): <parameter=path>..."
  (let ((args nil)
        (pos 0))
    (while (< pos (length inner))
      (let ((p-start (string-search "<parameter=" inner pos)))
        (if (null p-start)
            (setq pos (length inner))
          (let ((name-end (string-search ">" inner p-start)))
            (if (null name-end)
                (setq pos (length inner))
              (let* ((name (substring inner
                                      (+ p-start (length "<parameter="))
                                      name-end))
                     (v-start (1+ name-end))
                     (v-end (string-search "</parameter>" inner v-start)))
                (if (null v-end)
                    (setq pos (length inner))
                  (setq pos (+ v-end (length "</parameter>"))
                        args (plist-put args
                                        (intern (concat ":" name))
                                        (string-trim
                                         (substring inner v-start v-end)))))))))))
    args))

(defun +carlos/magent--fsm-parse-claude-xml-tool-calls (text &optional metadata)
  "Parse tool-calls em formato Claude-XML legado de TEXT.
Formato que o Qwen3.5-9B emite sob contexto pesado:
  <tool_call><function=NAME><parameter=KEY>VALUE</parameter>
  </function></tool_call>
Retorna uma lista de eventos normalizados (mesma estrutura do parser DSML)
ou nil.  METADATA opcional acompanha os eventos emitidos.  O `:source'
textual-dsml faz o loop normalizar args pelo schema."
  (when (string-search "<tool_call>" text)
    (let (events (pos 0) (index 0))
      (while (string-search "<tool_call>" text pos)
        (let ((block-start (string-search "<tool_call>" text pos)))
          (let ((block-end (string-search "</tool_call>" text block-start)))
            (if (null block-end)
                (setq pos (length text))
              (let* ((raw-text (substring text block-start block-end))
                     (fn-start (string-search "<function=" raw-text))
                     (fn-name-end (and fn-start
                                       (string-search ">" raw-text fn-start))))
                (if (not (and fn-start fn-name-end))
                    (setq pos (length text))
                  (let* ((name (substring raw-text
                                          (+ fn-start (length "<function="))
                                          fn-name-end))
                         (inner-start (1+ fn-name-end))
                         (inner-end (string-search "</function>"
                                                   raw-text inner-start))
                         (inner (and inner-end
                                     (substring raw-text inner-start inner-end)))
                         (args (+carlos/magent--fsm-parse-claude-xml-params inner)))
                    (when (and inner-end args)
                      (cl-incf index)
                      (let* ((id (format
                                  "textual-claude-xml-%d-%s"
                                  index
                                  (substring (secure-hash 'sha1 raw-text)
                                             0 10)))
                             (raw-call (list :id id
                                             :name name
                                             :args args
                                             :source 'textual-dsml)))
                        (push (magent-llm-tool-call-event
                               id name args raw-call metadata)
                              events)))
                    (setq pos (+ block-end (length "</tool_call>"))))))))))
      (nreverse events))))

(defun +carlos/magent--fsm-parse-reasoning-tool-calls (state info)
  "Extract tool-calls from the reasoning accumulated in STATE.
Roda primeiro o parser DSML nativo do magent; se não achar, tenta o parser
Claude-XML legado.  INFO carrega os metadados da resposta.  Retorna lista de
eventos normalizados ou nil."
  (let* ((reasoning (+carlos/magent--fsm-reasoning-text state))
         (metadata (magent-llm-gptel--metadata info)))
    (when (and reasoning (not (string-empty-p reasoning)))
      (or (when (fboundp 'magent-llm-gptel--parse-dsml-tool-calls)
            (magent-llm-gptel--parse-dsml-tool-calls reasoning metadata))
          (+carlos/magent--fsm-parse-claude-xml-tool-calls reasoning metadata)))))

(defun +carlos/magent--fsm-emit-recovered-events (request state info events fsm)
  "Emit EVENTS recuperados do reasoning como tool-calls reais.
Reusa o mesmo maquinário do caminho textual-DSML nativo (continuation do
gptel + batch-end), devolvendo o símbolo de status esperado pelo caller.
REQUEST/STATE/INFO/FSM são repassados ao maquinário de emissão.
Cada EVENTS é emitido como tool call real (semântica imperativa)."
  (let ((continuation
         (when (fboundp 'magent-llm-gptel--prepare-textual-continuation)
           (magent-llm-gptel--prepare-textual-continuation
            fsm state info events))))
    (when (fboundp 'magent-llm-gptel--emit-tool-call-batch)
      (magent-llm-gptel--emit-tool-call-batch
       request state events
       (append (magent-llm-gptel--metadata info) '(:source textual-dsml))
       continuation))
    (if continuation 'tool-call-paused 'tool-call)))

(defun +carlos/magent--fsm-retry-empty-turn (_request _info state fsm)
  "RETRY state: re-dispara a requisição com mensagem de forçagem nativa.
Injeta uma mensagem de usuário e continua o FSM do gptel (mesmo mecanismo do
recovery textual).  Limita a `+carlos/magent-fsm-max-retries' via contador no
STATE.  Retorna `completed-paused' (não mata o buffer) ou nil se já retried."
  (let ((retries (or (gethash :carlos-magent-fsm-retries state) 0)))
    (if (>= retries +carlos/magent-fsm-max-retries)
        nil
      (puthash :carlos-magent-fsm-retries (1+ retries) state)
      (when (fboundp 'magent-llm-gptel--continue-with-user-message)
        (magent-llm-gptel--continue-with-user-message
         fsm state
         (list :role "user"
               :content +carlos/magent-fsm-retry-message)))
      'completed-paused)))

(defun +carlos/magent-fsm-orchestrate-a
    (orig-fn request state info text &optional fsm)
  "FSM de orquestração sobre o terminal do turn do Magent.
THINK: o reasoning já é acumulado pelo magent em `:reasoning-chunks'.
DECIDE: se o content chegou vazio (tool-call do modelo ficou no reasoning),
parseia o reasoning (DSML nativo + Claude-XML) e emite os eventos reais.
RETRY: sem tool call recuperável, re-dispara com forçagem nativa (1x).
REQUEST/STATE/INFO/TEXT/FSM são os argumentos da função original; ORIG-FN é a
função original (chamada quando não há intervenção da FSM)."
  (if (or (not +carlos/magent-fsm-enabled)
          (not (string-empty-p (or text "")))
          (and (fboundp 'magent-llm-gptel--pending-tool-use-p)
               (magent-llm-gptel--pending-tool-use-p info)))
      (funcall orig-fn request state info text fsm)
    (let ((events (+carlos/magent--fsm-parse-reasoning-tool-calls state info)))
      (cond
       (events
        (+carlos/magent--fsm-emit-recovered-events
         request state info events fsm))
       ((+carlos/magent--fsm-retry-empty-turn request state info fsm))
       (t (funcall orig-fn request state info text fsm))))))

(with-eval-after-load 'magent-llm-gptel
  (unless (advice-member-p #'+carlos/magent-fsm-orchestrate-a
                           'magent-llm-gptel--emit-completed-or-textual-tool-calls)
    (advice-add 'magent-llm-gptel--emit-completed-or-textual-tool-calls
                :around #'+carlos/magent-fsm-orchestrate-a)))

;; ── Slash Commands & Directory Context Scope ──────────────────────
(defvar +carlos/magent-extra-directories nil
  "Lista de diretórios adicionais incluídos no contexto do Magent.")

(defun +carlos/magent-set-workdir (dir)
  "Define DIR como o novo diretório de trabalho base da sessão do Magent."
  (interactive "DSelecione o novo diretório de trabalho: ")
  (let ((expanded (expand-file-name dir)))
    (if (not (file-directory-p expanded))
        (message "Magent: Diretório inválido: %s" expanded)
      (setq default-directory (file-name-as-directory expanded))
      (message "Magent Workdir alterado para: %s" default-directory))))

(defun +carlos/magent-add-dir (dir)
  "Adiciona DIR como diretório adicional ao contexto da sessão do Magent."
  (interactive "DSelecione o diretório para adicionar ao contexto: ")
  (let ((expanded (file-name-as-directory (expand-file-name dir))))
    (if (not (file-directory-p expanded))
        (message "Magent: Diretório inválido: %s" expanded)
      (add-to-list '+carlos/magent-extra-directories expanded)
      (let ((skills-path (expand-file-name "magent/skills" expanded)))
        (when (file-directory-p skills-path)
          (add-to-list 'magent-skill-directories skills-path)))
      (message "Magent: Diretório adicionado ao contexto: %s" expanded))))

(defun +carlos/magent-list-dirs ()
  "Exibe o diretório de trabalho atual e os diretórios extras no contexto."
  (interactive)
  (let ((workdir default-directory)
        (extras +carlos/magent-extra-directories))
    (message "Magent Workdir: %s | Extras: %s"
             workdir
             (if extras (string-join extras ", ") "Nenhum"))))

(defun +carlos/magent-render-usage-chat ()
  "Gera e exibe o relatório FinOps com barra de cota."
  (interactive)
  (require 'custom-ai)
  (let ((tracker-file (+carlos/gptel-tracker-file)))
    (if (not (file-exists-p tracker-file))
        (message "Magent: Nenhum registro de consumo encontrado ainda em %s" tracker-file)
      (let ((usage-hash (make-hash-table :test 'equal))
            (total-input 0)
            (total-output 0)
            (total-cost 0.0))
        (with-temp-buffer
          (insert-file-contents tracker-file)
          (goto-char (point-min))
          (while (not (eobp))
            (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
              (when (string-match-p "^[ \t]*|[ \t]*[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" line)
                (let* ((fields (mapcar #'string-trim (split-string line "|")))
                       (agent (if (>= (length fields) 4) (nth 3 fields) "Unknown"))
                       (input (if (>= (length fields) 7) (string-to-number (nth 6 fields)) 0))
                       (output (if (>= (length fields) 8) (string-to-number (nth 7 fields)) 0))
                       (cost-str (if (>= (length fields) 10) (nth 9 fields) "$0.00"))
                       (cost 0.0))
                  (when (string-match "\\$\\([0-9.]+\\)" cost-str)
                    (setq cost (string-to-number (match-string 1 cost-str))))
                  (let ((agent-data (gethash agent usage-hash (list 0 0 0.0))))
                    (setcar agent-data (+ (nth 0 agent-data) input))
                    (setcar (cdr agent-data) (+ (nth 1 agent-data) output))
                    (setcar (cddr agent-data) (+ (nth 2 agent-data) cost))
                    (puthash agent agent-data usage-hash))
                  (setq total-input (+ total-input input)
                        total-output (+ total-output output)
                        total-cost (+ total-cost cost)))))
            (forward-line 1)))
        (let* ((max-free-tokens 1000000)
               (used-tokens (+ total-input total-output))
               (pct (min 100 (/ (* used-tokens 100) max-free-tokens)))
               (filled-blocks (/ pct 10))
               (empty-blocks (- 10 filled-blocks))
               (bar (concat (make-string filled-blocks ?█) (make-string empty-blocks ?░)))
               (msg (format "📊 FinOps: [%s] %d%% (%dk/%dk tokens) | Custo: $%0.4f USD"
                            bar pct (/ used-tokens 1000) (/ max-free-tokens 1000) total-cost)))
          (message "%s" msg)
          msg)))))

(defun +carlos/magent-slash-interceptor (input)
  "Intercepta comandos barra em INPUT no prompt da sessão."
  (let ((cmd (string-trim (or input ""))))
    (cond
     ((string-match "^/set-workdir\\(?:\\s-+\\(.+\\)\\)?$" cmd)
      (let ((path (match-string 1 cmd)))
        (if (and path (not (string-empty-p path)))
            (+carlos/magent-set-workdir path)
          (call-interactively #'+carlos/magent-set-workdir)))
      t)
     ((string-match "^/add-dir\\(?:\\s-+\\(.+\\)\\)?$" cmd)
      (let ((path (match-string 1 cmd)))
        (if (and path (not (string-empty-p path)))
            (+carlos/magent-add-dir path)
          (call-interactively #'+carlos/magent-add-dir)))
      t)
     ((string-match "^/list-dir\\|/list-dirs\\|/dirs$" cmd)
      (+carlos/magent-list-dirs)
      t)
     ((string-match "^/usage$" cmd)
      (+carlos/magent-render-usage-chat)
      t)
     (t nil))))

;; Atalhos globais para os comandos de diretório e usage
(global-set-key (kbd "C-c M w") #'+carlos/magent-set-workdir)
(global-set-key (kbd "C-c M a") #'+carlos/magent-add-dir)
(global-set-key (kbd "C-c M L") #'+carlos/magent-list-dirs)

;; ── Display rules ──────────────────────────────────────────────────
(add-to-list 'display-buffer-alist
             '("\\*Magent"
               (display-buffer-in-direction)
               (direction . bottom)
               (window-height . 0.5)))

(provide 'custom-magent)
;;; custom-magent.el ends here
