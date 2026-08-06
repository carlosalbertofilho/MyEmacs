;;; custom-magent.el --- Magent (AI coding agent nativo) -*- lexical-binding: t; -*-

;;; Commentary:
;; Magent: agente de codificação Emacs-Lisp com 15 tools, permissões por
;; agente, sessões por projeto (ledger), skills e capabilities.  Frontend
;; agent-shell (ACP in-process).  Transporte continua sendo gptel-request.
;; Instalado via receita git Elpaca pinada em 50ef707 (não está no MELPA).

;;; Code:

(defvar magent-system-prompt)
(defvar magent-skill-directories)
(defvar magent-project-instruction-file-names)
(autoload 'magent-start "magent-agent-shell" "Start Magent agent-shell session." t)
(autoload 'magent-agent-shell-ensure-config "magent-agent-shell")
(autoload 'magent-agent-shell-interrupt "magent-agent-shell" "Interrupt Magent agent-shell." t)
(autoload 'magent-agent-shell-prompt-region "magent-agent-shell" "Send region to Magent." t)

(use-package magent
  :ensure (magent :repo "Jamie-Cui/magent"
                  :ref "50ef707"
                  :files ("lisp/magent*.el" "prompts" "skills" "capabilities"))
  :custom
  (magent-default-agent "build")
  (magent-enable-audit-log t)
  (magent-project-instruction-file-names '("AGENTS.md"))
  (magent-include-reasoning t))

(with-eval-after-load 'magent
  (magent-agent-shell-ensure-config))

;; ── Display rules ──────────────────────────────────────────────────
(add-to-list 'display-buffer-alist
             '("\\*Magent"
               (display-buffer-in-direction)
               (direction . bottom)
               (window-height . 0.5)))

(provide 'custom-magent)
;;; custom-magent.el ends here
