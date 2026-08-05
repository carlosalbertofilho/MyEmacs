;;; custom-knowledge.el --- Knowledge management (Denote) -*- lexical-binding: t; -*-

;;; Commentary:
;; Denote: Zettelkasten por filename, notas com timestamps e tags.
;; Diretorio: ~/org/notes

;;; Code:

;; ── denote ──────────────────────────────────────────────────────────
(use-package denote
  :config
  (setq denote-directory (expand-file-name "~/org/notes")
        denote-known-keywords '("emacs" "nix" "42school" "python" "go" "typescript" "ai" "devops" "linux" "nixos")
        denote-infer-keywords t
        denote-sort-keywords t
        denote-file-type 'org-mode
        denote-org-front-matter t
        denote-date-prompt-use-org-read-date t
        denote-rename-buffer-format "%t"
        denote-excluded-directories-regexp nil)

  ;; Keybindings
  (global-set-key (kbd "C-c n n") #'denote)
  (global-set-key (kbd "C-c n d") #'denote-date)
  (global-set-key (kbd "C-c n r") #'denote-rename-file)
  (global-set-key (kbd "C-c n b") #'denote-backlinks)
  (global-set-key (kbd "C-c n l") #'denote-link)
  (global-set-key (kbd "C-c n L") #'denote-link-dired))

;; ── denote-silo-extras (notas em múltiplos diretórios) ─────────────
(use-package denote-silo-extras
  :catch t
  :after denote
  :config
  (setq denote-silo-extras-directories
        (list (expand-file-name "~/org/notes"))))

(provide 'custom-knowledge)
;;; custom-knowledge.el ends here
