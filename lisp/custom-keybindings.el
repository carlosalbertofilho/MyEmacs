;;; custom-keybindings.el --- Native keybindings -*- lexical-binding: t; -*-

;;; Commentary:
;; All keybindings using C-c prefix (no Evil mode).
;; Replaces SPC leader from Doom with native Emacs conventions.

;;; Code:

;; Forward declarations for byte-compiler
(declare-function magit-status "magit")
(declare-function gptel "gptel")
(declare-function justl "justl")
(declare-function justl-compile "justl")
(declare-function makefile-executor-execute-project-target "makefile-executor")
(declare-function makefile-executor-execute-last "makefile-executor")
(declare-function denote "denote")
(declare-function denote-date "denote")
(declare-function +carlos/dashboard-open "custom-dashboard")
(declare-function +carlos/dashboard-refresh "custom-dashboard")
(declare-function +carlos/gptel-agent-run "custom-ai")
(declare-function +carlos/ai-rag-ingest "custom-ai")
(declare-function +carlos/magent-show-usage "custom-ai")
(declare-function +carlos/agy-prompt "custom-ai")
(declare-function +carlos/copilot-explain-region "custom-ai")
(declare-function +carlos/gptel-emergency-fallback "custom-ai")
(declare-function +carlos/gptel-generate-commit-message "custom-git")
(declare-function denote-rename-file "denote")
(declare-function denote-backlinks "denote")
(declare-function denote-link "denote")
(declare-function denote-link-dired "denote")
(declare-function olivetti-mode "olivetti")
(declare-function dirvish-side "dirvish")
(declare-function magent-start "magent-agent-shell")
(declare-function magent-agent-shell-interrupt "magent-agent-shell")
(declare-function magent-agent-shell-prompt-region "magent-agent-shell")
(declare-function +carlos/nixos-rebuild-switch "custom-lang")

;; ── Window navigation (windmove with Super) ─────────────────────────
(windmove-default-keybindings 'super)

;; ── File and buffer ─────────────────────────────────────────────────
(global-set-key (kbd "C-x C-f") #'find-file)
(global-set-key (kbd "C-x b")   #'consult-buffer)
(global-set-key (kbd "C-c f")   #'dirvish-side)

;; ── Search ──────────────────────────────────────────────────────────
(global-set-key (kbd "C-c s")   #'consult-ripgrep)
(global-set-key (kbd "C-c S")   #'consult-line)

;; ── Git (Magit) ─────────────────────────────────────────────────────
(global-set-key (kbd "C-c g")   #'magit-status)

;; ── AI (gptel) ──────────────────────────────────────────────────────
(global-set-key (kbd "C-c i")   #'gptel)
(global-set-key (kbd "C-c I")   #'+carlos/gptel-agent-run)
(global-set-key (kbd "C-c r")   #'+carlos/ai-rag-ingest)
;; Commit IA: global gera a mensagem (copias p/ kill-ring);
;; dentro do buffer de commit, C-c C-g insere direto (custom-git.el).
(global-set-key (kbd "C-c C-g") #'+carlos/gptel-generate-commit-message)

;; ── Magent (AI coding agent nativo) ─────────────────────────────────
(global-set-key (kbd "C-c A m") #'+carlos/magent-start)
(global-set-key (kbd "C-c A i") #'+carlos/magent-agent-shell-interrupt)
(global-set-key (kbd "C-c A r") #'+carlos/magent-agent-shell-prompt-region)

;; ── CLI Integrations (agy & copilot) ────────────────────────────────
(global-set-key (kbd "C-c A g") #'+carlos/agy-prompt)
(global-set-key (kbd "C-c A c") #'+carlos/copilot-explain-region)
(global-set-key (kbd "C-c A f") #'+carlos/gptel-emergency-fallback)

;; ── 42 School ───────────────────────────────────────────────────────
(global-set-key (kbd "C-c h")   #'stdheader)

;; ── Just ────────────────────────────────────────────────────────────
(global-set-key (kbd "C-c j")   #'justl)
(global-set-key (kbd "C-c J")   #'justl-compile)

;; ── NixOS ───────────────────────────────────────────────────────────
(global-set-key (kbd "C-c N r") #'+carlos/nixos-rebuild-switch)

;; ── Makefile ────────────────────────────────────────────────────────
;; C-c m e C-c M são associados via :bind do use-package makefile-executor (custom-git.el)

;; ── Denote ──────────────────────────────────────────────────────────
(global-set-key (kbd "C-c n n") #'denote)
(global-set-key (kbd "C-c n d") #'denote-date)
(global-set-key (kbd "C-c n r") #'denote-rename-file)
(global-set-key (kbd "C-c n b") #'denote-backlinks)
(global-set-key (kbd "C-c n l") #'denote-link)
(global-set-key (kbd "C-c n L") #'denote-link-dired)
(global-set-key (kbd "C-c n s") #'+carlos/denote-silo-new)

;; ── Zen UI ──────────────────────────────────────────────────────────
(global-set-key (kbd "C-c z")   #'olivetti-mode)

;; ── Terminal ────────────────────────────────────────────────────────
(global-set-key (kbd "C-c t")   #'vterm)
;; eshell bound in custom-term.el (C-c e)

;; ── Tab bar ─────────────────────────────────────────────────────────
(global-set-key (kbd "C-c TAB") #'tab-bar-mode)

;; ── Useful defaults ─────────────────────────────────────────────────
(global-set-key (kbd "M-o")     #'other-window)
(global-set-key (kbd "C-x k")   #'kill-current-buffer)

;; ── Dashboard ───────────────────────────────────────────────────────
(global-set-key (kbd "C-c d d") #'+carlos/dashboard-open)
(global-set-key (kbd "C-c d r") #'+carlos/dashboard-refresh)
(global-set-key (kbd "C-c d u") #'+carlos/magent-show-usage)

(provide 'custom-keybindings)
;;; custom-keybindings.el ends here
