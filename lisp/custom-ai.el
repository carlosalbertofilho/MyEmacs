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
(declare-function gptel-agent "gptel-agent")
(declare-function gptel-get-backend "gptel")
(declare-function gptel-request "gptel")
(declare-function gptel-send "gptel")
(declare-function project-root "project")

;; ── gptel core ──────────────────────────────────────────────────────
(use-package gptel
  :ensure t
  :config
  ;; Incluir tool calls e resultados no buffer para visibilidade
  (setq gptel-include-tool-results t)

  ;; ── Backend: OpenCode Zen (OpenAI-compatible) ─────────────────────
  ;; Host real: opencode.ai (zen.opencode.ai NÃO resolve — NXDOMAIN).
  (gptel-make-openai "OpenCode Zen"
    :host "opencode.ai"
    :protocol "https"
    :endpoint "/zen/v1/chat/completions"
    :stream t
    :key (lambda () (getenv "OPENCODE_ZEN_API_KEY"))
    :models '("deepseek-v4-flash-free"
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
    :models '("gemini-2.5-flash"
              "gemini-2.5-pro"))

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
              "mlx-community/Qwen3-14B-4bit")))

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

  ;; Cria o diretório se não existir
  (unless (file-directory-p (expand-file-name "~/.agents/gptel/"))
    (make-directory (expand-file-name "~/.agents/gptel/") t))

  ;; Personas globais em ~/.agents/gptel/
  (add-to-list 'gptel-agent-dirs (expand-file-name "~/.agents/gptel/"))

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
4. Code must compile with `-Wall -Wextra -Werror`.")
             (cpp-42 . "You are an expert C++ mentor at 42 School.
1. Adhere to C++98 standard.
2. ALWAYS implement the 'Orthodox Canonical Form' (Constructor, Destructor, Copy Constructor, Assignment).")
             (python . "You are a senior Python Developer. Follow PEP8, use Type Hinting, write pythonic code, and prefer modern Python 3.10+ syntax.")))
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
(defvar +carlos/gptel-agent-backend "Zen Claude"
  "Backend padrão para sessões de agente.")

(defvar +carlos/gptel-agent-model 'claude-sonnet-5
  "Modelo padrão para sessões de agente.")

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

(provide 'custom-ai)
;;; custom-ai.el ends here
