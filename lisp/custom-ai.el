;;; custom-ai.el --- AI assistants (gptel unificado) -*- lexical-binding: t; -*-

;;; Commentary:
;; gptel backends (OpenCode Zen, Zen Claude, Gemini, Ollama, MLX Local),
;; gptel-agent, gptel-org (integração Org), personas/diretivas,
;; +carlos/gptel-agent-run (reescrito sem advice bug).
;; Nota: gptel 2026 NÃO distribui ob-gptel nem gptel-quick;
;; integração Org é via gptel-org.

;;; Code:

;; ── gptel core ──────────────────────────────────────────────────────
(use-package gptel
  :config
  ;; Incluir tool calls e resultados no buffer para visibilidade
  (setq gptel-include-tool-results t)

  ;; ── Backend: OpenCode Zen (OpenAI-compatible) ─────────────────────
  (gptel-make-openai "OpenCode Zen"
    :host "zen.opencode.ai"
    :protocol "https"
    :stream t
    :models '("deepseek-v4-flash-free"
              "north-mini-code-free"))

  ;; ── Backend: Zen Claude (Anthropic-compatible) ────────────────────
  (gptel-make-anthropic "Zen Claude"
    :host "zen.opencode.ai"
    :protocol "https"
    :stream t
    :models '("claude-sonnet-5"
              "claude-opus-5"))

  ;; ── Backend: Gemini ───────────────────────────────────────────────
  (gptel-make-gemini "Gemini"
    :stream t
    :models '("gemini-2.5-flash"
              "gemini-2.5-pro"))

  ;; ── Backend: Ollama Local ─────────────────────────────────────────
  (gptel-make-ollama "Ollama Local"
    :host "localhost:11434"
    :stream t
    :models '("qwen3.5:latest"))

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
              "mlx-community/Qwen3-14B-4bit")))

;; ── gptel-agent ─────────────────────────────────────────────────────
(use-package gptel-agent
  :after gptel
  :config
  ;; Cria o diretório se não existir
  (unless (file-directory-p "~/.agents/gptel/")
    (make-directory (expand-file-name "~/.agents/gptel/") t))

  ;; Personas globais em ~/.agents/gptel/
  (add-to-list 'gptel-agent-dirs (expand-file-name "~/.agents/gptel/"))

  ;; Personas por projeto (.agents/gptel/ na raiz do repositório)
  (defun +carlos/gptel-agent-project-dirs ()
    "Adiciona `.agents/gptel/' do projeto atual como fonte de agentes.
Sem advice: chamada direta antes de iniciar o agente."
    (when-let* ((proj (project-current))
                (root (project-root proj))
                (dir (expand-file-name ".agents/gptel/" root))
                (file-directory-p dir))
      (add-to-list 'gptel-agent-dirs dir)))

  ;; Registra os presets gptel-agent/gptel-plan e lê os sub-agentes
  (gptel-agent-update))

;; ── gptel-org (integração Org — substitui ob-gptel/gptel-quick) ─────
;; gptel 2026 usa gptel-org. ob-gptel e gptel-quick não são distribuídos.
(with-eval-after-load 'gptel
  (when (require 'gptel-org nil t)
    (when (fboundp 'gptel-org-mode)
      (gptel-org-mode 1))
    (org-babel-do-load-languages
     'org-babel-load-languages
     (append org-babel-load-languages '((gptel . t))))))

;; ── Personas / Diretivas ────────────────────────────────────────────
(with-eval-after-load 'gptel
  (dolist (directive
           '((c-42 . "You are an expert C tutor at 42 School conforming strictly to Norm v4.1.
CRITICAL RULES (Violating these fails the project):
1. FORBIDDEN SYNTAX: No `for`, `do...while`, `switch`, `case`, `goto`, ternary operators, or VLAs.
2. FORMATTING: REAL TABS (width 4). Max 25 lines per function, max 80 columns, max 5 variables.
3. STRUCTURE: Declarations at the top, separated from code by one empty line. No inline initializations (e.g. `int i = 0;` is ILLEGAL).
4. Code must compile with `-Wall -Wextra -Werror`.")
             (cpp-42 . "You are an expert C++ mentor at 42 School.
1. Adhere to C++98 standard.
2. ALWAYS implement the 'Orthodox Canonical Form' (Constructor, Destructor, Copy Constructor, Assignment).")
             (python . "You are a senior Python Developer. Follow PEP8, use Type Hinting, write pythonic code, and prefer modern Python 3.10+ syntax.")))
    (setf (alist-get (car directive) gptel-directives) (cdr directive))))

;; ── +carlos/gptel-agent-run (reescrito sem advice bug) ─────────────
(defvar +carlos/gptel-agent-backend "Zen Claude"
  "Backend padrão para sessões de agente.")

(defvar +carlos/gptel-agent-model 'claude-sonnet-5
  "Modelo padrão para sessões de agente.")

(defun +carlos/gptel-agent-add-project-dirs ()
  "Adiciona `.agents/gptel/' do projeto atual a `gptel-agent-dirs'."
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
  (let ((project-dir (or (project-root (project-current)) default-directory)))
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

;; ── mcp.el (Model Context Protocol client) ──────────────────────────
;; Instalar via Nix ou manualmente:
;;   git clone https://github.com/lizqwerscott/mcp.el.git ~/.emacs.d/site-lisp/mcp
(use-package mcp
  :ensure nil
  :demand t
  :if (locate-library "mcp")
  :config
  ;; Servidores MCP padrão
  (setq mcp-hub-servers
        `(("filesystem" . (:command "npx"
                          :args ("-y" "@modelcontextprotocol/server-filesystem"
                                 ,(expand-file-name "~/Projects"))))
          ("github" . (:command "npx"
                       :args ("-y" "@modelcontextprotocol/server-github")))))
  ;; Iniciar MCP automaticamente com gptel/superchat
  (with-eval-after-load 'gptel
    (require 'gptel-integrations)))

;; ── SuperChat (Claude Code-style UI para gptel) ────────────────────
;; Não está no MELPA — instalar manualmente:
;;   git clone https://github.com/yibie/superchat.git ~/.emacs.d/straight/repos/superchat
;; Ou adicionar ao load-path:
;;   (add-to-list 'load-path "~/.emacs.d/site-lisp/superchat")
(use-package superchat
  :ensure nil
  :demand t
  :if (locate-library "superchat")
  :after gptel
  :config
  ;; Backend padrão (herda do gptel ou usa llm.el)
  (setq superchat-llm-backend
        (make-llm-openai-compatible
         :api-key (or (getenv "OPENCODE_API_KEY") "")
         :endpoint "https://zen.opencode.ai/v1"
         :chat-model "north-mini-code-free"))
  ;; Idioma para variáveis de sistema
  (setq superchat-lang "English")
  ;; Timeout de resposta
  (setq superchat-response-timeout 180)
  ;; Histórico de conversa
  (setq superchat-context-message-count 15
        superchat-conversation-history-limit 80)
  ;; Diretório de dados (memória SQLite, config)
  (setq superchat-data-directory (expand-file-name "~/.emacs.d/superchat/"))
  ;; Ferramentas permitidas
  (setq superchat-llm-tool-names 'all))

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

(add-to-list 'display-buffer-alist
             '("\\*superchat.*"
               (display-buffer-in-direction)
               (direction . right)
               (window-width . 0.45)))

(provide 'custom-ai)
;;; custom-ai.el ends here
