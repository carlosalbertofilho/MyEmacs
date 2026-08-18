;;; custom-ai.el --- AI assistants (gptel unificado) -*- lexical-binding: t; -*-

;;; Commentary:
;; gptel backends (OpenCode Zen, Zen Claude, Gemini, Ollama, MLX Local),
;; gptel-agent, integração Org automática, personas/diretivas,
;; +carlos/gptel-agent-run e +carlos/gptel-request (helper).
;; Nota: gptel 0.9.9.5 NÃO distribui ob-gptel nem gptel-quick;
;; a integração Org é automática (gptel detecta org-mode via
;; `derived-mode-p' — nenhum minor-mode é necessário).
;; API keys de nuvem vêm do agenix (host agnes): /etc/api-keys.sh exporta
;; OPENCODE_ZEN_API_KEY e GEMINI_API_KEY/GOOGLE_API_KEY. O Emacs GUI
;; (Emacs.app) NÃO herda o ambiente do shell — carregamos o arquivo no
;; boot (guarda file-readable-p) para o gptel encontrar as chaves também
;; em processos GUI e batch (subagentes do magent).

;;; Code:

(defgroup +carlos/ai nil
  "Grupo de customização para as preferências de IA do MyEmacs."
  :group 'convenience
  :prefix "+carlos/")

;; Forward declarations para o byte-compiler.
;; Emacs 30: `defvar' sem INITVALUE NÃO liga a variável (só marca special,
;; suprimindo warnings). Usamos a forma PELADA para gptel-directives e
;; gptel-agent-dirs pois elas têm defaults de defcustom NÃO-NIL (diretivas
;; padrão do gptel e o diretório de agentes embutido do gptel-agent) — um
;; `nil' aqui clobberaria esses defaults. gptel-backend/model têm default
;; nil, então a forma com valor é segura.
(defvar gptel-directives)
(defvar gptel-agent-dirs)
(defvar gptel-backend nil)
(defvar gptel-model nil)
(defvar gptel-context-restrict-to-project-files)
(declare-function gptel-agent "gptel-agent")
(declare-function gptel-get-backend "gptel")
(declare-function gptel-request "gptel")
(declare-function gptel-send "gptel")
(declare-function gptel-make-openai "gptel-openai")
(declare-function gptel-make-anthropic "gptel-anthropic")
(declare-function gptel-make-gemini "gptel-gemini")
(declare-function gptel-make-ollama "gptel-ollama")
(declare-function project-root "project")
(defvar magent--current-session)
(declare-function magent-session-agent "magent-session")
(declare-function magent-agent-info-name "magent-agent-info")
(declare-function magent-log-add-sink "magent-log")
(declare-function magent-start "magent")
(declare-function org-table-align "org-table")
(defvar url-connection-timeout)
(defvar url-queue-timeout)

;; ── API keys do ambiente (GUI Emacs não herda o shell) ──────────────
;; O agenix (host agnes) gera /etc/api-keys.sh com a forma
;;   export VAR="$(cat /run/agenix/secret)"
;; (ver modules/system/agenix-env.nix em MyMachine). O Emacs GUI/batch não
;; passa pelo .zshrc, então carregamos o arquivo aqui, resolvendo tanto a
;; forma agenix (lê o conteúdo do arquivo) quanto literais simples.
(defcustom +carlos/api-keys-file "/etc/api-keys.sh"
  "Arquivo shell que exporta chaves de API como `export NOME=valor'.
Formatos suportados: literal (`export NOME=\"chave\"') e agenix
(`export NOME=\"$(cat CAMINHO)\"'). `nil' desativa o carregamento."
  :type '(choice (const :tag "Nenhum" nil) file)
  :group '+carlos/ai)

(defun +carlos/--api-key-value-from-sh (raw)
  "Resolve o valor da chave a partir da string shell RAW.
Suporta literais com aspas simples/duplas e a forma agenix
`\"$(cat CAMINHO)\"', lendo o conteúdo de CAMINHO (trim de \\n final)."
  (let ((trimmed (string-trim raw)))
    (if (string-match "\\`[\"']?\\$(cat[[:space:]]+\\([^)\"']+\\))[\"']?\\'"
                      trimmed)
        (let* ((secret (match-string-no-properties 1 trimmed))
               (macos-secret (if (string-prefix-p "/run/agenix/" secret)
                                 (concat "/run/agenix.d/1/" (file-name-nondirectory secret))
                               nil))
               (actual-secret (cond
                               ((and (file-readable-p secret) (not (file-directory-p secret))) secret)
                               ((and macos-secret (file-readable-p macos-secret) (not (file-directory-p macos-secret))) macos-secret)
                               (t nil))))
          (when actual-secret
            (string-trim-right
             (with-temp-buffer
               (insert-file-contents actual-secret)
               (buffer-substring-no-properties (point-min) (point-max))))))
      ;; Remove aspas delimitadoras simples/duplas manualmente
      ;; (string-trim nativo do Emacs 30 não respeita charset multi-char).
      (let ((value trimmed))
        (when (and (> (length value) 1)
                   (memq (aref value 0) '(?\" ?'))
                   (eq (aref value (1- (length value))) (aref value 0)))
          (setq value (substring value 1 -1)))
        value))))

(defun +carlos/--source-api-keys-from-file (file)
  "Carrega chaves de API ausentes do ambiente a partir do arquivo shell FILE.
Lê linhas `export VAR=valor' (resolvidas por
`+carlos/--api-key-value-from-sh') e chama `setenv' apenas para
variáveis ainda não definidas — nunca sobrescreve o ambiente."
  (when (and file (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (re-search-forward
              "^[[:space:]]*export[[:space:]]+\\([A-Za-z_][A-Za-z0-9_]*\\)=\\([^\n]*\\)"
              nil t)
        (let* ((var (match-string-no-properties 1))
               (value (+carlos/--api-key-value-from-sh
                       (match-string-no-properties 2))))
          (when (and (not (getenv var)) value)
            (setenv var value)))))))

(+carlos/--source-api-keys-from-file +carlos/api-keys-file)

(defvar +carlos/gptel-agent-backend "Zen Claude"
  "Backend padrão para sessões de agente.")

(defvar +carlos/gptel-agent-model 'claude-sonnet-5
  "Modelo padrão para sessões de agente.")

(defvar +carlos/gptel-quick-local-backend "Gemini"
  "Backend usado para tarefas rápidas como docstrings e testes.
Prefere o Gemini free tier (nuvem) em vez de modelos locais — o
roteamento para backends locais fica apenas como fallback final.")

(defvar +carlos/gptel-quick-local-model 'gemini-3.5-flash
  "Modelo usado para tarefas rápidas como docstrings e testes.")

(defvar +carlos/gptel-grammar-backend "Gemini"
  "Backend usado para correção gramatical/ortográfica profunda.")

(defvar +carlos/gptel-grammar-model 'gemini-3.5-flash
  "Modelo usado para correção gramatical/ortográfica profunda.")

;; ── gptel core ──────────────────────────────────────────────────────
(use-package gptel
  :ensure t
  :demand t
  :custom
  (gptel-include-tool-results t)
  (gptel-context-restrict-to-project-files nil)
  (gptel-use-curl t)
  :config

  ;; ── Backend: OpenCode Zen (OpenAI-compatible) ─────────────────────
  ;; Host real: opencode.ai (zen.opencode.ai NÃO resolve — NXDOMAIN).
  (gptel-make-openai "OpenCode Zen"
    :host "opencode.ai"
    :protocol "https"
    :endpoint "/zen/v1/chat/completions"
    :stream t
    :key (lambda () (getenv "OPENCODE_ZEN_API_KEY"))
    :models '("big-pickle"
              "gpt-5.6-sol"
              "gpt-5.3-codex"
              "gpt-5.2-codex"
              "deepseek-v4-pro"
              "qwen3.6-plus"
              "kimi-k2.7-code"
              ;; Modelos 100% gratuitos (Free Tier no OpenCode Zen)
              "deepseek-v4-flash-free"
              "north-mini-code-free"
              "mimo-v2.5-free"
              "laguna-s-2.1-free"
              "ling-3.0-tiny-free"
              "longcat-2.0-free"
              "nemotron-3-ultra-free"))

  ;; ── Backend: Zen Claude (Anthropic-compatible) ────────────────────
  (gptel-make-anthropic "Zen Claude"
    :host "opencode.ai"
    :protocol "https"
    :endpoint "/zen/v1/messages"
    :stream t
    :key (lambda () (getenv "OPENCODE_ZEN_API_KEY"))
    :models '("claude-sonnet-5"
              "claude-opus-5"))

  ;; ── Backend: Gemini ───────────────────────────────────────────────
  (gptel-make-gemini "Gemini"
    :stream t
    :key (lambda () (or (getenv "GEMINI_API_KEY")
                        (getenv "GOOGLE_API_KEY")))
    :models '("gemini-3.5-flash"
              "gemini-3.5-flash-lite"
              "gemini-3.6-flash"
              "gemini-3.1-pro-preview"
              "gemini-2.5-flash"
              "gemini-2.5-pro"
              "gemini-2.0-flash"
              "gemini-1.5-flash"
              "gemma-4-31b-it"
              "antigravity-preview-05-2026"))

  ;; ── Backend: Ollama Local (endpoint nativo /api/chat) ─────────────
  ;; NOTA: usar gptel-make-ollama (não gptel-make-openai) — o endpoint
  ;; OpenAI-compat /v1/chat/completions IGNORA options.num_ctx (sempre
  ;; 4096), quebrando o magent com prompts >4096 tokens. O endpoint
  ;; nativo /api/chat honra `:options (:num_ctx 16384)`.
  (gptel-make-ollama "Ollama Local"
    :host "localhost:11434"
    :protocol "http"
    :stream t
    :request-params '(:options (:num_ctx 16384))
    :models '("qwen2.5-coder:3b"
              "qwen2.5-coder:1.5b"
              "gemma4:e2b"
              "deepseek-r1:1.5b"
              "mistral"))

  ;; ── Backend: MLX Local (6 modelos validados, M2/24GB) ────────────
  ;; Servidor roda em 127.0.0.1:8081 via launchd (mlx_lm.server)
  ;; Modelo ativo por padrão: mlx-community/gemma-4-e2b-it-4bit
  (gptel-make-openai "MLX Local"
    :host "127.0.0.1:8081"
    :protocol "http"
    :stream t
    :key "any"
    :request-params '(:max_tokens 8192)
    :models '("mlx-community/gemma-4-e2b-it-4bit"
              "mlx-community/gemma-4-9b-it-4bit"
              "mlx-community/Qwen3.5-9B-MLX-4bit"
              "mlx-community/Qwen3.5-Coder-7B-Instruct-4bit"
              "mlx-community/Qwen3.5-Coder-14B-Instruct-4bit"
              "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit"))

  ;; ── Set default backend and model globally (host-based detection) ─
  ;; Chat padrão: Gemini free tier (gemini-3.5-flash) — o agente local
  ;; ficou impraticável em CPU; local agora é apenas fallback final do
  ;; roteador dinâmico.
  (setq-default gptel-backend (gptel-get-backend "Gemini"))
  (setq-default gptel-model 'gemini-1.5-flash)
  (when (fboundp '+carlos/gptel-setup-defaults-by-host)
    (+carlos/gptel-setup-defaults-by-host)))

;; ── gptel-agent ─────────────────────────────────────────────────────
;; NOTA: com `use-package-expand-minimally t', o keyword `:after' do
;; use-package é ignorado — `use-package gptel-agent :after gptel' NÃO
;; carregava o pacote junto com o gptel. Padrão correto: `:ensure t'
;; (Elpaca instala, sem carregar) + `with-eval-after-load' (dispara junto
;; com o gptel — mesmo mecanismo das personas abaixo, que funciona).
(use-package gptel-agent
  :ensure t)

(with-eval-after-load 'gptel
  ;; Carrega o pacote (defuns/defcustoms) — o update precisa do gptel
  (require 'gptel-agent)

  ;; Cria o diretório global se não existir
  (unless (file-directory-p (expand-file-name "~/.agents/gptel/"))
    (make-directory (expand-file-name "~/.agents/gptel/") t))

  ;; Garante apenas diretórios existentes no gptel-agent-dirs
  (let ((global-dir (expand-file-name "~/.agents/gptel/")))
    (unless (boundp 'gptel-agent-dirs)
      (setq gptel-agent-dirs nil))
    (add-to-list 'gptel-agent-dirs global-dir)
    (setq gptel-agent-dirs (cl-delete-if-not #'file-directory-p gptel-agent-dirs)))

  ;; Registra os presets gptel-agent/gptel-plan e lê os sub-agentes
  (gptel-agent-update))

;; ── gptel-org (integração Org) ──────────────────────────────────────
;; Automática em gptel 0.9.9.5: `gptel-request' chama
;; `gptel-org--create-prompt-buffer' e o gptel detecta `derived-mode-p'
;; 'org-mode' no envio. Não existe `gptel-org-mode' nesta versão — não
;; há nada a ativar.

;; ── Personas / Diretivas ────────────────────────────────────────────
(with-eval-after-load 'gptel
  (dolist (directive
           '((c-42 . "You are an expert C tutor at 42 School conforming strictly to Norm v4.1.
CRITICAL RULES (Violating these fails the project):
1. FORBIDDEN SYNTAX: No `for`, `do...while`, `switch`, `case`, `goto`, ternary operators, or VLAs.
2. FORMATTING: REAL TABS (width 4). Max 25 lines per function, max 80 columns, max 5 variables.
3. STRUCTURE: Declarations at the top, separated from code by one empty line. No inline initializations (e.g. `int i = 0;` is ILLEGAL).
4. Code must compile with `-Wall -Wextra -Werror`.
")
             (cpp-42 . "You are an expert C++ mentor at 42 School.
1. Adhere to C++98 standard.
2. ALWAYS implement the 'Orthodox Canonical Form' (Constructor, Destructor, Copy Constructor, Assignment).")
             (python . "You are a senior Python Developer. Follow PEP8, use Type Hinting, write pythonic code, and prefer modern Python 3.10+ syntax.")
             (hephaestus . "You are Hephaestus, a senior coding assistant. Write clean, modular, and optimized code. Avoid boilerplate, focus on dry implementations, use type annotations, and write code that works out of the box.")
             (architect . "You are the Architect, a senior software architect. Analyze system requirements, design clean modular structures, design data models, create Mermaid diagrams to illustrate architecture flows, and prioritize maintainability and scalability.")
             (revisor . "You are the Revisor, a senior code reviewer. Review changes strictly for bug patterns, memory leaks, performance bottlenecks, code style consistency, security holes, and compliance with project conventions (like the 42 School Norm for C code).")))
    (setf (alist-get (car directive) gptel-directives) (cdr directive))))

;; ── +carlos/gptel-request (helper para chamadas programáticas) ──────
;; gptel 0.9.9.5: `gptel-request' NÃO aceita :backend/:model — o backend
;; e o modelo são lidos do buffer (buffer-local). Este helper encapsula
;; o padrão correto para chamadas assíncronas.
(defun +carlos/gptel-request (prompt backend model &rest args)
  "Envia PROMPT para o gptel usando BACKEND e MODEL.

BACKEND é o nome do backend registrado (string); MODEL um símbolo.
ARGS são repassados a `gptel-request' (:system, :callback, ...).
Quando ARGS contém `:buffer', usa esse buffer; senão usa
`*gptel-request*'.

Garante que o gptel esteja carregado antes de buscar o backend."
  (require 'gptel)
  (let* ((buffer-name (or (plist-get args :buffer) "*gptel-request*"))
         (args (cl-loop for (k v) on args by #'cddr
                        unless (eq k :buffer)
                        append (list k v))))
    (let ((buffer (get-buffer-create buffer-name)))
      (with-current-buffer buffer
        (setq gptel-backend (gptel-get-backend backend))
        (setq gptel-model model)
        (setq buffer-read-only nil)
        (erase-buffer))
      ;; gptel 0.9.9.5: resposta JSON só via keyword `:schema' (não
      ;; `:response_format'); callers que precisam de JSON passam :schema.
      (apply #'gptel-request prompt :buffer buffer args))))

;; ── +carlos/gptel-agent-run (reescrito sem advice bug) ─────────────

(defun +carlos/gptel-agent-add-project-dirs ()
  "Adiciona `.agents/gptel/' do projeto atual a `gptel-agent-dirs'.
Garante `gptel-agent' antes para não clobberar os agentes padrão."
  (require 'gptel-agent nil t)
  (when-let* ((proj (project-current))
              (root (project-root proj))
              (dir (expand-file-name ".agents/gptel/" root))
              (file-directory-p dir))
    (add-to-list 'gptel-agent-dirs dir)))

(defun +carlos/gptel-agent-run (&optional task)
  "Inicia uma sessão gptel-agent com TASK no buffer.
Sem advice: chama `+carlos/gptel-agent-add-project-dirs' diretamente."
  (interactive (list (read-string "Tarefa do agente: ")))
  (when (string-empty-p task)
    (user-error "Nenhuma tarefa especificada"))
  (+carlos/gptel-agent-add-project-dirs)
  (let ((project-dir (if-let* ((proj (project-current)))
                         (project-root proj)
                       default-directory)))
    (gptel-agent project-dir 'gptel-agent)
    (when-let* ((buf (seq-find (lambda (b)
                                 (string-prefix-p "*gptel-agent:" (buffer-name b)))
                               (buffer-list))))
      (with-current-buffer buf
        (setq-local gptel-backend (gptel-get-backend +carlos/gptel-agent-backend))
        (setq-local gptel-model +carlos/gptel-agent-model)
        (goto-char (point-max))
        (insert task)
        (gptel-send)
        (message "Agente iniciado — %s" task)))))

;; ── Display buffer rules (popup replacement) ───────────────────────
(add-to-list 'display-buffer-alist
             '("\\*gptel-agent:.*"
               (display-buffer-in-direction)
               (direction . bottom)
               (window-height . 0.5)))

(add-to-list 'display-buffer-alist
             '("\\*gptel.*"
               (display-buffer-in-direction)
               (direction . bottom)
               (window-height . 0.4)))

;; ── CLI Integrations (agy & copilot-cli) ────────────────────────────
(defun +carlos/agy-prompt (prompt)
  "Executa assincronamente o Gemini CLI (agy) passando PROMPT."
  (interactive "sPergunta para o Gemini CLI: ")
  (let ((output-buffer (get-buffer-create "*Gemini CLI Output*")))
    (with-current-buffer output-buffer
      (read-only-mode -1)
      (erase-buffer)
      (markdown-mode)
      (insert (format "# Pergunta: %s\n\n_Aguardando resposta do agy..._\n\n" prompt)))
    (display-buffer output-buffer)
    ;; Dispara o subprocesso de forma assíncrona
    (make-process
     :name "agy-process"
     :buffer output-buffer
     :command (list "agy" prompt)
     :filter (lambda (proc string)
               (when (buffer-live-p (process-buffer proc))
                 (with-current-buffer (process-buffer proc)
                   (let ((inhibit-read-only t))
                     (goto-char (point-max))
                     ;; Substitui a mensagem de aguardando se for a primeira escrita
                     (when (search-backward "_Aguardando resposta do agy..._" nil t)
                       (replace-match ""))
                     (insert string))))))))

(defun +carlos/copilot-explain-region ()
  "Envia a região ativa para o GitHub Copilot CLI explicar."
  (interactive)
  (if (not (use-region-p))
      (user-error "Selecione uma região de código primeiro")
    (let* ((code (buffer-substring-no-properties (region-beginning) (region-end)))
           (prompt (format "Explique o código a seguir:\n\n%s" code))
           (output-buffer (get-buffer-create "*Copilot CLI Output*")))
      (with-current-buffer output-buffer
        (read-only-mode -1)
        (erase-buffer)
        (markdown-mode)
        (insert "# Explicação do Copilot:\n\n"))
      (display-buffer output-buffer)
      (make-process
       :name "copilot-explain"
       :buffer output-buffer
       :command (list "gh" "copilot" "explain" prompt)
       :filter (lambda (proc string)
                 (when (buffer-live-p (process-buffer proc))
                   (with-current-buffer (process-buffer proc)
                     (let ((inhibit-read-only t))
                       (goto-char (point-max))
                       (insert string)))))))))

;; Atalhos globais de integração CLI movidos para custom-keybindings.el (I6)

;; Regras de exibição para os popups de CLI
(add-to-list 'display-buffer-alist
             '("\\*Gemini CLI Output\\*"
               (display-buffer-in-direction)
               (direction . bottom)
               (window-height . 0.4)))

(add-to-list 'display-buffer-alist
             '("\\*Copilot CLI Output\\*"
               (display-buffer-in-direction)
               (direction . bottom)
               (window-height . 0.4)))

;; ── Host-aware local backend (single source of truth) ───────────────
(defun +carlos/ai-local-backend ()
  "Retorna cons (NOME-BACKEND . MODELO) do backend local para o host atual.
MLX Local em hosts contendo \"agnes\", Ollama Local nos demais."
  (if (string-match-p "agnes" (system-name))
      (cons "MLX Local" 'mlx-community/gemma-4-e2b-it-4bit)
    (cons "Ollama Local" 'qwen2.5-coder:3b)))

;; ── Network Timeouts for Local LLMs ─────────────────────────────────
(setq url-connection-timeout 120)
(setq url-queue-timeout 120)

(defvar +carlos/local-ai-ping-cache nil
  "Cons (timestamp . resultado) do último ping do servidor local.
nil quando o resultado atual ainda não é válido ou nunca foi calculado.")

(defvar +carlos/local-ai-ping-ttl-seconds 10
  "TTL em segundos para o cache do ping do servidor local.")

(defun +carlos/local-ai-server-ping-p ()
  "Checa se o servidor de IA local (MLX ou Ollama) está ativo.
Resultado cacheado por `+carlos/local-ai-ping-ttl-seconds' para evitar
~2s de latência a cada `gptel-request' quando o servidor está fora."
  (let* ((now (float-time))
         (age (and +carlos/local-ai-ping-cache
                   (- now (car +carlos/local-ai-ping-cache)))))
    (if (and age (< age +carlos/local-ai-ping-ttl-seconds))
        (cdr +carlos/local-ai-ping-cache)
      (let* ((backend-name (car (+carlos/ai-local-backend)))
             (url (if (string-equal backend-name "MLX Local")
                      "http://127.0.0.1:8081/v1/models"
                    "http://127.0.0.1:11434/api/tags"))
             (result
              (condition-case nil
                  (let ((url-request-method "GET")
                        (url-show-status nil))
                    (with-current-buffer (url-retrieve-synchronously url t t 2)
                      (goto-char (point-min))
                      (search-forward "200 OK" nil t)))
                (error nil))))
        (setq +carlos/local-ai-ping-cache (cons now result))
        result))))

(defun +carlos/gptel-setup-defaults-by-host ()
  "Aplica preferências de IA baseadas no hostname do sistema.
Chat padrão em TODOS os hosts: Gemini free tier (`gemini-3.5-flash').
Agente (Magent/gptel-agent): Zen Claude (claude-sonnet-5, assinatura).
Backends locais (MLX/Ollama) permanecem registrados e são usados apenas
como fallback final pelo roteador dinâmico, não como default de chat.
`when-let*' evita setar gptel-backend como nil caso o backend Gemini
não esteja registrado (ex.: falha na instalação do gptel)."
  (interactive)
  (let ((hostname (system-name)))
    (when-let* ((gemini (gptel-get-backend "Gemini")))
      (setq gptel-backend gemini
            gptel-model 'gemini-1.5-flash
            +carlos/gptel-agent-backend "Zen Claude"
            +carlos/gptel-agent-model 'claude-sonnet-5
            +carlos/gptel-quick-local-backend "Gemini"
            +carlos/gptel-quick-local-model 'gemini-3.5-flash
            +carlos/gptel-grammar-backend "Gemini"
            +carlos/gptel-grammar-model 'gemini-3.5-flash)
      (message "Emacs AI: Chat Gemini free tier (gemini-1.5-flash) em %s — local só como fallback final" hostname))))


;; ── Emergency Fallback & Latency Watchdog ───────────────────────────
(defvar +carlos/gptel-latency-timeout-seconds 8
  "Limite de segundos antes de redirecionar automaticamente por latência.")

(defvar +carlos/gptel-watchdog-backends
  '("OpenCode Zen" "Ollama Local" "MLX Local" "Gemini")
  "Backends monitorados pelo watchdog de latência.
Inclui todos os backends que o roteador dinâmico pode escolher.")

(defun +carlos/gptel-emergency-fallback (&optional buf)
  "Interrompe a chamada de IA ativa e altera o backend para a nuvem.
BUF é o buffer onde a requisição está ativa (default: `current-buffer')."
  (interactive)
  (require 'gptel)
  (let ((target (or buf (current-buffer))))
    (with-current-buffer target
      ;; 1. Se houver processo ativo no buffer, mata-o
      (when-let* ((proc (get-buffer-process (current-buffer))))
        (delete-process proc)
        (message "Chamada lenta interrompida."))
      ;; 2. Altera o backend e modelo para Zen Claude (nuvem da assinatura)
      (setq gptel-backend (gptel-get-backend "Zen Claude"))
      (setq gptel-model 'claude-sonnet-5)
      (setq-default gptel-backend (gptel-get-backend "Zen Claude")
                    gptel-model 'claude-sonnet-5)
      (message "IA reconfigurada para a Nuvem: Zen Claude (claude-sonnet-5)")
      ;; 3. Se for um buffer de chat do gptel, re-envia a requisição automaticamente
      (when (bound-and-true-p gptel-mode)
        (gptel-send)
        (message "Re-enviando mensagem para a nuvem...")))))

(defun +carlos/gptel-latency-watchdog (_prompt &rest args)
  "Monitora `_prompt' e ARGS aplicando fallback em caso de latência.
Somente agenda o timer quando o backend do buffer alvo está em
`+carlos/gptel-watchdog-backends' e a requisição NÃO é gerenciada pelo
Magent (mesmo rationale do roteador: redirecionar para a nuvem quebra o
tool calling local). O fallback age no buffer BUF correto via
`+carlos/gptel-emergency-fallback'."
  (let* ((buf (or (plist-get args :buffer) (current-buffer)))
         (context (plist-get args :context)))
    (when (and (buffer-live-p buf)
               (not (+carlos/magent-managed-request-p buf context))
               (with-current-buffer buf
                 (let ((backend-name (condition-case nil
                                         (if (and (boundp 'gptel-backend)
                                                  gptel-backend
                                                  (fboundp 'gptel-backend-name))
                                             (gptel-backend-name gptel-backend)
                                           "")
                                       (error ""))))
                   (member backend-name +carlos/gptel-watchdog-backends))))
      (run-with-timer
       +carlos/gptel-latency-timeout-seconds nil
       (lambda ()
         (when (and (buffer-live-p buf)
                    (get-buffer-process buf))
           (let ((backend-name (condition-case nil
                                   (with-current-buffer buf
                                     (if (and (boundp 'gptel-backend)
                                              gptel-backend
                                              (fboundp 'gptel-backend-name))
                                         (gptel-backend-name gptel-backend)
                                       ""))
                                 (error ""))))
             (when (member backend-name +carlos/gptel-watchdog-backends)
               (message "⚠️ Latência alta (%ds) em %s. Redirecionando para Zen Claude..."
                        +carlos/gptel-latency-timeout-seconds backend-name)
               (+carlos/gptel-emergency-fallback buf)))))))))

;; ── Dynamic Task/Backend Router ─────────────────────────────────────
;; Precedencia de custo (do mais barato ao mais caro):
;;   Gemini free tier (nuvem, generoso) > OpenCode Zen free (big-pickle
;;   e modelos *-free, custo zero na assinatura) > Local (CPU/GPU gratis,
;;   impraticável em CPU — apenas fallback final)
;;
;; Regras:
;;   PLANEJAMENTO  -> Gemini free tier (gemini-3.5-flash) -> Zen Claude pago (fallback)
;;   CODIGO        -> Gemini free -> big-pickle -> north-mini-code-free -> Local (fallback)
;;   GERAL         -> Gemini free -> big-pickle -> mimo-v2.5-free -> Local (fallback)

(defun +carlos/magent-managed-request-p (buffer context)
  "Non-nil quando o gptel-request para BUFFER com CONTEXT é gerenciado pelo Magent.
O Magent (`magent-llm-gptel') define seu próprio backend/modelo; o roteador
dinâmico e o watchdog de latência NÃO devem tocá-lo — redirecionar para a
nuvem quebra o tool calling local (erro `stop unknown reason').
Também ignora correção gramatical (`*gptel-grammar*'), que fixa o modelo
mistral local em `+carlos/gptel-grammar-model'.
Ignora também buffers de benchmarks e testes locais de rede."
  (or (string-prefix-p " *magent-llm-gptel-request*" (buffer-name buffer))
      (string-prefix-p "*gptel-grammar" (buffer-name buffer))
      (string-prefix-p " *heavy-" (buffer-name buffer))
      (string-prefix-p " *benchmark-" (buffer-name buffer))
      (string-prefix-p " *temp*" (buffer-name buffer))
      (and (listp context) (plist-member context :magent-llm-gptel))))

(defun +carlos/gptel-dynamic-router-advice (prompt &rest args)
  "Roteador dinamico de IA para PROMPT com ARGS com cascata estrita de cotas.
Prioridade: Gemini free tier > OpenCode Zen free (big-pickle / *-free)
> Local (fallback final, impraticável em CPU). Ignora requisições
gerenciadas pelo Magent — ver `+carlos/magent-managed-request-p'."
  (let* ((target-buffer (or (plist-get args :buffer) (current-buffer)))
         (context (plist-get args :context)))
    (unless (+carlos/magent-managed-request-p target-buffer context)
      (let* ((prompt-text (or prompt ""))
             (local-online (+carlos/local-ai-server-ping-p))
             (local-pair (+carlos/ai-local-backend))
             (local-name (car local-pair))
             (local-mdl  (cdr local-pair)))
        (when (buffer-live-p target-buffer)
          (with-current-buffer target-buffer
            (cond
             ;; REGRA 1: Planejamento / Arquitetura / Analise
             ;; -> Gemini free tier (gemini-3.5-flash) -> Zen Claude pago como fallback
             ((or (string-match-p "\\*gptel-plan" (buffer-name))
                  (string-match-p "planejamento\\|arquitetura\\|/plan\\|analis" prompt-text))
              (if-let ((backend (gptel-get-backend "Gemini")))
                  (progn
                    (setq-local gptel-backend backend
                                gptel-model 'gemini-3.5-flash)
                    (message "Dynamic Route: Planejamento roteado para Gemini free tier (gemini-3.5-flash)"))
                (when-let ((backend (gptel-get-backend "Zen Claude")))
                  (setq-local gptel-backend backend
                              gptel-model 'claude-sonnet-5)
                  (message "Dynamic Route: Planejamento -> fallback Zen Claude (pago)"))))

             ;; REGRA 2: Codificacao & Refatoracao (prog-mode)
             ;; -> Gemini free tier -> big-pickle (free) -> north-mini-code-free (free) -> Local (fallback)
             ;; Nota: requisições do Magent já são excluídas acima via
             ;; +carlos/magent-managed-request-p (I7).
             ((derived-mode-p 'prog-mode)
              (cond
               ((gptel-get-backend "Gemini")
                (setq-local gptel-backend (gptel-get-backend "Gemini")
                            gptel-model 'gemini-3.5-flash)
                (message "Dynamic Route: Codigo -> Gemini free tier (gemini-3.5-flash)"))
               ((gptel-get-backend "OpenCode Zen")
                (setq-local gptel-backend (gptel-get-backend "OpenCode Zen")
                            gptel-model 'big-pickle)
                (message "Dynamic Route: Codigo -> OpenCode Zen free (big-pickle)"))
               ((and local-online (gptel-get-backend local-name))
                (setq-local gptel-backend (gptel-get-backend local-name)
                            gptel-model local-mdl)
                (message "Dynamic Route: Codigo -> Local ativo (%s) [fallback]" local-name))))

             ;; REGRA 3: Conversas gerais, resumos, perguntas
             ;; -> Gemini free tier -> big-pickle (free) -> mimo-v2.5-free (free) -> Local (fallback)
             (t
              (cond
               ((gptel-get-backend "Gemini")
                (setq-local gptel-backend (gptel-get-backend "Gemini")
                            gptel-model 'gemini-3.5-flash)
                (message "Dynamic Route: Geral -> Gemini free tier (gemini-3.5-flash)"))
               ((gptel-get-backend "OpenCode Zen")
                (setq-local gptel-backend (gptel-get-backend "OpenCode Zen")
                            gptel-model 'big-pickle)
                (message "Dynamic Route: Geral -> OpenCode Zen free (big-pickle)"))
               ((and local-online (gptel-get-backend local-name))
                (setq-local gptel-backend (gptel-get-backend local-name)
                            gptel-model local-mdl)
                (message "Dynamic Route: Geral -> Local ativo (%s) [fallback]" local-name)))))))
      ;; Ativa o observador de latencia para a requisicao
      (apply #'+carlos/gptel-latency-watchdog prompt args)))))

(advice-add 'gptel-request :before #'+carlos/gptel-dynamic-router-advice)

(defun +carlos/magent-guard-empty-response (beg end)
  "Avisa no minibuffer quando o Magent recebe resposta vazia do modelo.
BEG e END delimitam a resposta inserida pelo gptel; quando iguais, o
modelo não devolveu texto nem chamadas de ferramenta."
  (when (and (string-prefix-p " *magent-llm-gptel-request*" (buffer-name))
             (= beg end))
    (message "Magent: resposta vazia do modelo (sem texto nem tool calls). Verifique o backend local e o roteador dinâmico.")))

(add-hook 'gptel-post-response-functions #'+carlos/magent-guard-empty-response)

;; ── FinOps Token & Cost Tracker ─────────────────────────────────────
(defvar +carlos/gptel-tracker-file-override nil
  "Se não-nil, substitui o caminho padrão do log de consumo.")

(defun +carlos/gptel-tracker-file ()
  "Caminho do arquivo de log de consumo FinOps.
Respeita `+carlos/gptel-tracker-file-override'; senão usa
`docs/ai-usage-tracker.org' na raiz do projeto atual (fallback: MyEmacs).
Nota (I4): decidir com o usuário se o log deve ser sempre no repo MyEmacs
ou por-projeto (comportamento atual)."
  (or +carlos/gptel-tracker-file-override
      (expand-file-name "docs/ai-usage-tracker.org"
                        (or (and (project-current) (project-root (project-current)))
                            "~/Projects/Github/MyEmacs"))))

(defun +carlos/gptel-track-usage (_beg _end)
  "Hook executado após a resposta do gptel para registrar o consumo de tokens."
  (let* ((last-usage (car gptel--token-usage))
         (input (or (plist-get last-usage :input) 0))
         (output (or (plist-get last-usage :output) 0))
         (cached (or (plist-get last-usage :cached) 0))
         (backend-name (if gptel-backend (gptel-backend-name gptel-backend) "Unknown"))
         (model-name (if gptel-model (symbol-name gptel-model) "Unknown"))
         (buf-name (buffer-name))
         (time-str (format-time-string "%Y-%m-%d %H:%M:%S"))
         (agent-name (if (and (bound-and-true-p magent--current-session)
                              (magent-session-agent magent--current-session))
                         (magent-agent-info-name (magent-session-agent magent--current-session))
                       "No Agent (gptel)"))
         (cost-val (cond
                    ((and (string-equal backend-name "Zen Claude") (string-equal model-name "claude-sonnet-5"))
                     (+ (* input (/ 3.0 1000000.0)) (* output (/ 15.0 1000000.0))))
                    ((and (string-equal backend-name "Zen Claude") (string-equal model-name "claude-opus-5"))
                     (+ (* input (/ 15.0 1000000.0)) (* output (/ 75.0 1000000.0))))
                    ((and (string-equal backend-name "Gemini") (string-equal model-name "gemini-2.5-pro"))
                     (+ (* input (/ 1.25 1000000.0)) (* output (/ 5.0 1000000.0))))
                    ((and (string-equal backend-name "Gemini") (string-equal model-name "gemini-2.5-flash"))
                     (+ (* input (/ 0.075 1000000.0)) (* output (/ 0.30 1000000.0))))
                    (t 0.0)))
         (cost-str (if (> cost-val 0.0)
                       (format "$%0.4f (Market)" cost-val)
                     (cond
                      ((string-equal backend-name "MLX Local") "$0.00 (Local GPU)")
                      ((string-equal backend-name "Ollama Local") "$0.00 (Local CPU)")
                      ((string-equal backend-name "Gemini") "$0.00 (Free Tier)")
                      ((string-equal backend-name "Zen Claude") "$0.00 (Signature)")
                      ((string-equal backend-name "OpenCode Zen") "$0.00 (Signature)")
                      (t "$0.00 (Zero Cost)"))))
         (tracker-file (+carlos/gptel-tracker-file)))
    (when (or (> input 0) (> output 0))
      (with-temp-buffer
        (if (and (file-exists-p tracker-file)
                 (> (file-attribute-size (file-attributes tracker-file)) 0))
            (insert-file-contents tracker-file)
          (insert "#+TITLE: Registro de Uso e Consumo de IA - FinOps\n")
          (insert "#+AUTHOR: Carlos Filho\n")
          (insert "#+FILETAGS: :FINOPS:RAG:AI:\n\n")
          (insert "| Timestamp | Buffer | Agent | Backend | Modelo | Input | Output | Cached | Custo Est. |\n")
          (insert "|-----------+--------+-------+---------+--------+-------+--------+--------+------------|\n"))
        (goto-char (point-max))
        (unless (bolp) (insert "\n"))
        (insert (format "| %s | %s | %s | %s | %s | %d | %d | %d | %s |\n"
                        time-str buf-name agent-name backend-name model-name input output cached cost-str))
        (write-region (point-min) (point-max) tracker-file nil 'silent)))))

(add-hook 'gptel-post-response-functions #'+carlos/gptel-track-usage)

(defun +carlos/ai-rag-ingest (target)
  "Ingere um arquivo local ou URL assincronamente via `bin/rag-convert`.
O arquivo Org-mode gerado resultante será aberto no Emacs quando concluído."
  (interactive
   (list (let* ((is-url (y-or-n-p "A origem é uma URL da Web? "))
                (prompt (if is-url "URL para ingestão: " "Escolha o arquivo para ingestão: ")))
           (if is-url
               (read-string prompt)
             (expand-file-name (read-file-name prompt nil nil t))))))
  (let* ((script-path (expand-file-name "bin/rag-convert" user-emacs-directory))
         (buf-name "*rag-ingest*")
         (buf (get-buffer-create buf-name)))
    (unless (file-executable-p script-path)
      (error "O script de conversão RAG não foi encontrado ou não é executável: %s" script-path))
    (message "Iniciando a ingestão de '%s' via RAG converter..." target)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (format "Ingestão iniciada em: %s\nAlvo: %s\nComando: %s %s\n\n--- Saída do Processo ---\n"
                      (current-time-string) target script-path target))
      (setq-local default-directory user-emacs-directory))
    (make-process
     :name "rag-ingest"
     :buffer buf
     :command (list script-path target)
     :sentinel
     (lambda (proc event)
       (when (string= event "finished\n")
         (let ((out-file (concat target ".org")))
           (if (file-exists-p out-file)
               (progn
                 (message "Ingestão concluída com sucesso! Abrindo %s" out-file)
                 (find-file out-file))
             (with-current-buffer (process-buffer proc)
               (goto-char (point-min))
               (if (re-search-forward "✅ Document successfully converted to Org-Mode: \\(.*\\)$" nil t)
                   (let ((resolved-path (match-string 1)))
                     (message "Ingestão concluída com sucesso! Abrindo %s" resolved-path)
                     (find-file resolved-path))
                 (message "Ingestão concluída. Veja o buffer *rag-ingest* para detalhes.")
                 (pop-to-buffer (process-buffer proc)))))))))))

(defun +carlos/gptel-cache-hit-rate (input cached)
  "Calcula a porcentagem de cache hit-rate: `cached / (input + cached)`."
  (let ((total (+ (or input 0) (or cached 0))))
    (if (> total 0)
        (* (/ (float (or cached 0)) (float total)) 100.0)
      0.0)))

(defun +carlos/magent-show-usage ()
  "Exibe o resumo de consumo de IA por agente em buffer Org."
  (interactive)
  (let ((tracker-file (+carlos/gptel-tracker-file)))
    (if (not (file-exists-p tracker-file))
        (message "Arquivo de rastreamento de consumo não encontrado: %s" tracker-file)
      (let ((usage-hash (make-hash-table :test 'equal))
            (total-input 0)
            (total-output 0)
            (total-cached 0)
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
                       (cached (if (>= (length fields) 9) (string-to-number (nth 8 fields)) 0))
                       (cost-str (if (>= (length fields) 10) (nth 9 fields) "$0.00"))
                       (cost 0.0))
                  (when (string-match "\\$\\([0-9.]+\\)" cost-str)
                    (setq cost (string-to-number (match-string 1 cost-str))))
                  ;; Acumular no hash-table
                  (let ((agent-data (gethash agent usage-hash (list 0 0 0 0.0))))
                    (setcar agent-data (+ (nth 0 agent-data) input))
                    (setcar (cdr agent-data) (+ (nth 1 agent-data) output))
                    (setcar (cddr agent-data) (+ (nth 2 agent-data) cached))
                    (setcar (cdddr agent-data) (+ (nth 3 agent-data) cost))
                    (puthash agent agent-data usage-hash))
                  ;; Acumular nos totais gerais
                  (setq total-input (+ total-input input)
                        total-output (+ total-output output)
                        total-cached (+ total-cached cached)
                        total-cost (+ total-cost cost)))))
            (forward-line 1)))
        ;; Agora vamos gerar o buffer de visualização
        (let ((buf (get-buffer-create "*Magent Usage Summary*")))
          (with-current-buffer buf
            (read-only-mode -1)
            (erase-buffer)
            (org-mode)
            (insert "#+TITLE: Resumo de Consumo de IA por Agente (Magent)\n")
            (insert "#+AUTHOR: Carlos Filho\n")
            (insert "#+DATE: " (format-time-string "%Y-%m-%d %H:%M:%S") "\n\n")
            (insert "| Agent | Input Tokens | Output Tokens | Cached Tokens | Cache Hit % | Est. Cost |\n")
            (insert "|-------+--------------+---------------+---------------+-------------+-----------|\n")
            (maphash (lambda (agent data)
                       (let* ((inp (nth 0 data))
                              (cch (nth 2 data))
                              (hit-pct (+carlos/gptel-cache-hit-rate inp cch)))
                         (insert (format "| %s | %d | %d | %d | %0.1f%% | $%0.4f |\n"
                                         agent inp (nth 1 data) cch hit-pct (nth 3 data)))))
                     usage-hash)
            (insert "|-------+--------------+---------------+---------------+-------------+-----------|\n")
            (let ((overall-hit (+carlos/gptel-cache-hit-rate total-input total-cached)))
              (insert (format "| Total Geral | %d | %d | %d | %0.1f%% | $%0.4f |\n"
                              total-input total-output total-cached overall-hit total-cost)))
            (goto-char (point-min))
            (when (search-forward "|" nil t)
              (org-table-align))
            (read-only-mode 1))
          (pop-to-buffer buf)
          (message "Resumo de consumo de IA carregado!"))))))

(defcustom +carlos/magent-agent-smith-dir
  "~/Projetos/42rio/CommonCore/Rank05/Agent_Smith"
  "Diretório do projeto Agent_Smith que o Magent deve analisar."
  :type 'directory
  :group '+carlos/ai)

(defun +carlos/magent-analyze-agent-smith ()
  "Run Magent to analyze the Agent_Smith project using the local backend.
Analisa o projeto em `+carlos/magent-agent-smith-dir' com o modelo local
do host (via `+carlos/ai-local-backend'), contornando o roteador
dinâmico. O caminho do projeto é informado ao agente no prompt."
  (interactive)
  (require 'magent)
  (let* ((target-dir (expand-file-name +carlos/magent-agent-smith-dir))
         (local-pair (+carlos/ai-local-backend))
         (local-backend (car local-pair))
         (local-model (cdr local-pair)))
    (unless (file-directory-p target-dir)
      (user-error "Diretório do projeto Agent_Smith não encontrado: %s" target-dir))
    (let ((default-directory target-dir)
          (gptel-backend (gptel-get-backend local-backend))
          (gptel-model local-model))
      (magent-start (format "Analise o projeto em %s e explique o que voce entendeu"
                            target-dir)))))

(provide 'custom-ai)
;;; custom-ai.el ends here
