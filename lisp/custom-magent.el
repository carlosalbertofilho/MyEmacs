;;; custom-magent.el --- Magent (AI coding agent nativo) -*- lexical-binding: t; -*-

;;; Commentary:
;; Magent: agente de codificação Emacs-Lisp com 15 tools, permissões por
;; agente, sessões por projeto (ledger), skills e capabilities.  Frontend
;; agent-shell (ACP in-process).  Transporte continua sendo gptel-request.
;; Instalado via receita git Elpaca pinada em 50ef707 (não está no MELPA).

;;; Code:

(defvar gptel-backend-list)
(declare-function magent-start "magent-agent-shell")
(declare-function magent-agent-shell-interrupt "magent-agent-shell")
(declare-function magent-agent-shell-prompt-region "magent-agent-shell")
(declare-function magent-agent-shell-ensure-config "magent-agent-shell")
(declare-function magent-tools--failed "magent-tools")
(declare-function +carlos/gptel-tracker-file "custom-ai")

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

;; ── Tool Sanitization & Path Auto-Expansion ──────────────────────────
(defconst +carlos/magent-system-directives
  "CRITICAL MAGENT TOOL DIRECTIVES:
1. ABSOLUTE PATHS: Use full absolute paths starting with '/' (e.g. '/home/carlosfilho/...').
2. NON-EMPTY PARAMETERS: Do not call write_file or edit_file with empty or missing args.
3. NATIVE TOOLS FIRST: Prefer 'read_file', 'grep' (ripgrep), and 'glob' over shell commands.
4. NON-INTERACTIVE SHELL: Avoid interactive shells; git commits must include '-m \"message\"'.
5. SUBAGENT LIFECYCLE: When using 'spawn_agent', call 'wait_agent(job_id)' to get results.
6. TOOL CALL FORMAT: Always request tool use through the native structured function-calling mechanism. Never emit a tool call as free-form XML text. If you must encode a tool call in text (some backends only support textual tool calls), use EXACTLY this DSML envelope, with nothing else between the tags:
<tool_calls>
<invoke name=\"read_file\">
<parameter name=\"path\">/absolute/path/to/file</parameter>
</invoke>
</tool_calls>
Do NOT use '<tool_call>', '<function=...>', or '<parameter=...>' forms; the runtime only parses the '<tool_calls>'/'<invoke name=...>'/'<parameter name=...>' syntax shown above."
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
