;;; custom-ai.el --- AI assistants (gptel unificado) -*- lexical-binding: t; -*-

;;; Commentary:
;; gptel backends (OpenCode Zen, Zen Claude, Gemini, Ollama, MLX Local),
;; gptel-agent, integração Org automática, personas/diretivas,
;; +carlos/gptel-agent-run e +carlos/gptel-request (helper).
;; Nota: gptel 0.9.9.5 NÃO distribui ob-gptel nem gptel-quick;
;; a integração Org é automática (gptel detecta org-mode via
;; `derived-mode-p' — nenhum minor-mode é necessário).
;; API keys de nuvem vêm do agenix (host agnes): /etc/api-keys.sh exporta
;; OPENCODE_ZEN_API_KEY e GEMINI_API_KEY/GOOGLE_API_KEY.

;;; Code:

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
(declare-function org-table-align "org-table")
(defvar url-connection-timeout)
(defvar url-queue-timeout)

(defvar +carlos/gptel-agent-backend "Zen Claude"
  "Backend padrão para sessões de agente.")

(defvar +carlos/gptel-agent-model 'claude-sonnet-5
  "Modelo padrão para sessões de agente.")

(defvar +carlos/gptel-quick-local-backend "Ollama Local"
  "Backend usado para tarefas locais rápidas como docstrings e testes.")

(defvar +carlos/gptel-quick-local-model 'qwen2.5-coder:3b
  "Modelo usado para tarefas locais rápidas como docstrings e testes.")

(defun +carlos/gptel-setup-defaults-by-host ()
  "Aplica preferências de IA baseadas no hostname do sistema.
Deve ser executada após o gptel ter carregado todos os backends."
  (interactive)
  (let ((hostname (system-name)))
    (cond
     ;; --- HOST: agnes (macOS M2) -> Local-first via MLX ---
     ((string-match-p "agnes" hostname)
      (setq-default gptel-backend (gptel-get-backend "MLX Local")
                    gptel-model 'mlx-community/Qwen3.5-9B-MLX-4bit
                    +carlos/gptel-agent-backend "MLX Local"
                    +carlos/gptel-agent-model 'mlx-community/Qwen3.5-9B-MLX-4bit
                    +carlos/gptel-quick-local-backend "MLX Local"
                    +carlos/gptel-quick-local-model 'mlx-community/Qwen3.5-9B-MLX-4bit)
      (message "Emacs AI: Configurado para MLX Local (agnes) com Qwen 3.5 9B"))
     
     ;; --- HOST: aa102-006l (EliteDesk NixOS) -> API-first (Zen Claude) ---
     ((string-match-p "aa102-006l" hostname)
      (setq-default gptel-backend (gptel-get-backend "Zen Claude")
                    gptel-model 'claude-sonnet-5
                    +carlos/gptel-agent-backend "Zen Claude"
                    +carlos/gptel-agent-model 'claude-sonnet-5
                    +carlos/gptel-quick-local-backend "Ollama Local"
                    +carlos/gptel-quick-local-model 'qwen2.5-coder:3b)
      (message "Emacs AI: Configurado para Zen Claude API (aa102-006l)"))
     
     ;; --- FALLBACK: Outros (ex: nanami) -> API-first ---
     (t
      (setq-default gptel-backend (gptel-get-backend "Zen Claude")
                    gptel-model 'claude-sonnet-5
                    +carlos/gptel-agent-backend "Zen Claude"
                    +carlos/gptel-agent-model 'claude-sonnet-5
                    +carlos/gptel-quick-local-backend "Zen Claude"
                    +carlos/gptel-quick-local-model 'claude-sonnet-5)
      (message "Emacs AI: Configuração fallback carregada")))))

;; ── gptel core ──────────────────────────────────────────────────────
(use-package gptel
  :ensure t
  :demand t
  :config
  ;; Incluir tool calls e resultados no buffer para visibilidade
  (setq gptel-include-tool-results t)

  ;; Permitir incluir qualquer pasta/arquivo no contexto (desativa restrição estrita por git ls-files)
  (setq gptel-context-restrict-to-project-files nil)

  ;; ── Backend: OpenCode Zen (OpenAI-compatible) ─────────────────────
  ;; Host real: opencode.ai (zen.opencode.ai NÃO resolve — NXDOMAIN).
  (gptel-make-openai "OpenCode Zen"
    :host "opencode.ai"
    :protocol "https"
    :endpoint "/zen/v1/chat/completions"
    :stream t
    :key (lambda () (getenv "OPENCODE_ZEN_API_KEY"))
    :models '("big-pickle"
              "gpt-5.3-codex"
              "gpt-5.2-codex"
              "deepseek-v4-pro"
              "deepseek-v4-flash-free"
              "north-mini-code-free"))

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
              "gemma-4-31b-it"
              "antigravity-preview-05-2026"))

  ;; ── Backend: Ollama Local ─────────────────────────────────────────
  (gptel-make-ollama "Ollama Local"
    :host "localhost:11434"
    :stream t
    :models '("qwen2.5-coder:3b"
              "qwen2.5-coder:1.5b"
              "deepseek-r1:1.5b"))

  ;; ── Backend: MLX Local (5 modelos validados, M2/24GB) ────────────
  ;; Servidor roda em 127.0.0.1:8081 via launchd (mlx_lm.server)
  ;; Modelo ativo por padrão: mlx-community/Qwen3-14B-4bit
  (gptel-make-openai "MLX Local"
    :host "127.0.0.1:8081"
    :protocol "http"
    :stream t
    :models '("mlx-community/gemma-4-e2b-it-4bit"
              "mlx-community/Qwen2.5-7B-Instruct-4bit"
              "mlx-community/Qwen3.5-9B-MLX-4bit"
              "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit"
              "mlx-community/Qwen3-14B-4bit"))

  ;; ── Set default backend and model globally (host-based detection) ─
  (setq-default gptel-backend (gptel-get-backend "Zen Claude"))
  (setq-default gptel-model 'claude-sonnet-5)
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

Garante que o gptel esteja carregado antes de buscar o backend."
  (require 'gptel)
  (let ((buffer (get-buffer-create "*gptel-request*")))
    (with-current-buffer buffer
      (setq gptel-backend (gptel-get-backend backend))
      (setq gptel-model model)
      (setq buffer-read-only nil)
      (erase-buffer))
    (apply #'gptel-request prompt :buffer buffer args)))

;; ── +carlos/gptel-agent-run (reescrito sem advice bug) ─────────────

(defun +carlos/gptel-agent-add-project-dirs ()
  "Adiciona `.agents/gptel/' do projeto atual a `gptel-agent-dirs'.
Guarda contra `gptel-agent-dirs' void antes do gptel-agent carregar."
  (when-let* ((proj (project-current))
              (root (project-root proj))
              (dir (expand-file-name ".agents/gptel/" root))
              (file-directory-p dir))
    (unless (boundp 'gptel-agent-dirs)
      (setq gptel-agent-dirs nil))
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

;; Atalhos globais de integração CLI
(global-set-key (kbd "C-c A g") #'+carlos/agy-prompt)
(global-set-key (kbd "C-c A c") #'+carlos/copilot-explain-region)

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

;; ── Network Timeouts for Local LLMs ─────────────────────────────────
(setq gptel-use-curl t)
(setq url-connection-timeout 120)
(setq url-queue-timeout 120)

;; ── Emergency Fallback Router ───────────────────────────────────────
(defun +carlos/gptel-emergency-fallback ()
  "Interrompe a chamada de IA ativa e altera o backend para a nuvem."
  (interactive)
  (require 'gptel)
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
    (message "Re-enviando mensagem para a nuvem...")))

;; Atalho para Emergency Fallback
(global-set-key (kbd "C-c A f") #'+carlos/gptel-emergency-fallback)

;; ── Dynamic Task/Backend Router ─────────────────────────────────────
(defun +carlos/gptel-dynamic-router-advice (prompt &rest args)
  "Roteador dinâmico de IA para PROMPT com ARGS.
Executa :before `gptel-request' para definir backend/modelo ideais."
  (let* ((target-buffer (or (plist-get args :buffer) (current-buffer)))
         (prompt-text (or prompt ""))
         (hostname (system-name)))
    (when (buffer-live-p target-buffer)
      (with-current-buffer target-buffer
        (cond
         ;; REGRA 1: Se for buffer do Magent -> Prioridade para nuvem premium da assinatura (Zen Claude)
         ((or (string-match-p "\\*Magent" (buffer-name))
              (derived-mode-p 'magent-mode))
          (when-let ((backend (gptel-get-backend "Zen Claude")))
            (setq-local gptel-backend backend
                        gptel-model 'claude-sonnet-5)
            (message "Dynamic Route: Magent roteado para Zen Claude (Sonnet 3.5)")))

         ;; REGRA 2: Prompts gerais de resumo, busca ou explicações -> Gemini Cloud (quota gratuita)
         ((let ((case-fold-search t))
            (string-match-p "resuma\\|explicar\\|pesquise\\|rag\\|resumo" prompt-text))
          (when-let ((backend (gptel-get-backend "Gemini")))
            (setq-local gptel-backend backend
                        gptel-model 'gemini-2.5-flash)
            (message "Dynamic Route: Geral roteado para Gemini Cloud (2.5 Flash)")))

         ;; REGRA 3: Tarefas mecânicas locais de programação no macOS -> MLX Local (GPU custo zero)
         ((and (derived-mode-p 'prog-mode)
               (string-match-p "agnes" hostname))
          (when-let ((backend (gptel-get-backend "MLX Local")))
            (setq-local gptel-backend backend
                        gptel-model 'mlx-community/Qwen3.5-9B-MLX-4bit)
            (message "Dynamic Route: Código roteado para MLX Local (Qwen 3.5 9B)")))

         ;; REGRA 4: Tarefas mecânicas no EliteDesk -> Ollama Local (CPU/GPU)
         ((and (derived-mode-p 'prog-mode)
               (string-match-p "aa102-006l" hostname))
          (when-let ((backend (gptel-get-backend "Ollama Local")))
            (setq-local gptel-backend backend
                        gptel-model 'qwen2.5-coder:3b)
            (message "Dynamic Route: Código roteado para Ollama Local (Qwen 2.5 3B)"))))))))

(advice-add 'gptel-request :before #'+carlos/gptel-dynamic-router-advice)

;; ── FinOps Token & Cost Tracker ─────────────────────────────────────
(defvar +carlos/gptel-tracker-file-override nil
  "Se não-nil, substitui o caminho padrão do log de consumo.")

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
         (tracker-file (or +carlos/gptel-tracker-file-override
                           (expand-file-name "docs/ai-usage-tracker.org" 
                                             (or (and (project-current) (project-root (project-current)))
                                                 "~/Projects/Github/MyEmacs")))))
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

(defun +carlos/magent-show-usage ()
  "Exibe o resumo de consumo de IA por agente em buffer Org."
  (interactive)
  (let ((tracker-file (or +carlos/gptel-tracker-file-override
                           (expand-file-name "docs/ai-usage-tracker.org" 
                                             (or (and (project-current) (project-root (project-current)))
                                                 "~/Projects/Github/MyEmacs")))))
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
            (insert "| Agent | Input Tokens | Output Tokens | Cached Tokens | Est. Cost |\n")
            (insert "|-------+--------------+---------------+---------------+-----------|\n")
            (maphash (lambda (agent data)
                       (insert (format "| %s | %d | %d | %d | $%0.4f |\n"
                                       agent (nth 0 data) (nth 1 data) (nth 2 data) (nth 3 data))))
                     usage-hash)
            (insert "|-------+--------------+---------------+---------------+-----------|\n")
            (insert (format "| Total Geral | %d | %d | %d | $%0.4f |\n"
                            total-input total-output total-cached total-cost))
            (goto-char (point-min))
            (when (search-forward "|" nil t)
              (org-table-align))
            (read-only-mode 1))
          (pop-to-buffer buf)
          (message "Resumo de consumo de IA carregado!"))))))

(provide 'custom-ai)
;;; custom-ai.el ends here
