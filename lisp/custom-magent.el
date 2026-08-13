;;; custom-magent.el --- Magent (AI coding agent nativo) -*- lexical-binding: t; -*-

;;; Commentary:
;; Magent: agente de codificação Emacs-Lisp com 15 tools, permissões por
;; agente, sessões por projeto (ledger), skills e capabilities.  Frontend
;; agent-shell (ACP in-process).  Transporte continua sendo gptel-request.
;; Instalado via receita git Elpaca pinada em 50ef707 (não está no MELPA).
;;
;; Este arquivo é a FACHADA do módulo Magent — carrega os sub-módulos e
;; expõe o ponto de entrada da sessão.  A lógica está segregada por domínio:
;;   custom-magent-fsm.el      FSM de orquestração, host routing, watchdog
;;   custom-magent-tools.el    Fixes de tool/schema, directivas, tools curadas
;;   custom-magent-subagent.el Perfis de modelo por subagente
;;   custom-magent-context.el  Auto-compactação por threshold de janela
;;   custom-magent-commands.el Slash commands, workdir e FinOps
;;   custom-magent-ui.el       Painel de atividade (Fase C)

;;; Code:

(require 'custom-magent-fsm)
(require 'custom-magent-tools)
(require 'custom-magent-subagent)
(require 'custom-magent-context)
(require 'custom-magent-commands)
(require 'custom-magent-ui)

(defvar gptel-backend-list)
(defvar magent-skill-directories)
(declare-function magent-start "magent-agent-shell")
(declare-function magent-agent-shell-interrupt "magent-agent-shell")
(declare-function magent-agent-shell-prompt-region "magent-agent-shell")
(declare-function magent-agent-shell-ensure-config "magent-agent-shell")

(defun +carlos/magent-start ()
  "Garante o carregamento do Magent e inicia a sessão agent-shell."
  (interactive)
  (require 'gptel)
  (require 'magent)
  (require 'magent-agent-shell)
  ;; FSM: aplica o perfil de backend/modelo para o host atual
  (+carlos/magent-apply-host-routing)
  (+carlos/magent-fsm-reset)
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
  (magent-include-reasoning nil)  ;; nil = sem thinkingConfig no Gemini (evita thoughtSignature que causa timeout)
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

;; ── Display rules ──────────────────────────────────────────────────
(add-to-list 'display-buffer-alist
             '("\\*Magent"
               (display-buffer-in-direction)
               (direction . bottom)
               (window-height . 0.5)))

(provide 'custom-magent)
;;; custom-magent.el ends here
