;;; custom-knowledge.el --- Knowledge management (Denote) -*- lexical-binding: t; -*-

;;; Commentary:
;; Denote: Zettelkasten por filename, notas com timestamps e tags.
;; Diretorio: ~/org/notes

;;; Code:

;; ── denote ──────────────────────────────────────────────────────────
(use-package denote
  :ensure t
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

;; ── denote-silo-extras (local) — notas em múltiplos diretórios ─────
;; `denote-silo-extras' não existe como pacote; implementação local
;; que cria notas em silos (diretórios extras) sem alterar o padrão.
(defvar +carlos/denote-silo-directories
  (list (expand-file-name "~/org/notes"))
  "Diretórios de notas extras (silos).")

(defun +carlos/denote-silo--with-dir (dir fn)
  "Call FN with `denote-directory' bound to DIR."
  (let ((denote-directory (expand-file-name dir)))
    (funcall fn)))

(defun +carlos/denote-silo-new (&optional dir)
  "Create a new note in silo DIR.
With prefix argument, prompt for the silo directory."
  (interactive
   (list (if current-prefix-arg
             (completing-read "Silo: " +carlos/denote-silo-directories)
           (car +carlos/denote-silo-directories))))
  (+carlos/denote-silo--with-dir dir #'denote))

(global-set-key (kbd "C-c n s") #'+carlos/denote-silo-new)

(provide 'custom-knowledge)
;;; custom-knowledge.el ends here
