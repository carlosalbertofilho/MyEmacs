;;; custom-git.el --- Git and workflow tools -*- lexical-binding: t; -*-

;;; Commentary:
;; magit, just-mode/justl, commit message com IA (reescrito sem magit).

;;; Code:

;; ── magit ───────────────────────────────────────────────────────────
(use-package magit
  :bind
  (("C-c g" . magit-status))
  :config
  (setq magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1))

;; ── just-mode ───────────────────────────────────────────────────────
(use-package just-mode
  :mode ("Justfile\\'" . just-mode))

;; ── justl (interação com Justfile) ─────────────────────────────────
(use-package justl
  :after just-mode
  :config
  (global-set-key (kbd "C-c j") #'justl)
  (global-set-key (kbd "C-c J") #'justl-compile))

;; ── +carlos/gptel-generate-commit-message ──────────────────────────
;; Reescrito sem dependência de magit (usa vc-git / processo git)
(defun +carlos/gptel-generate-commit-message ()
  "Gera uma mensagem de commit usando IA a partir do diff staged.
Sem dependência de magit: usa 'git diff --cached' diretamente."
  (interactive)
  (unless (vc-git-root default-directory)
    (user-error "Not in a Git repository"))
  (let ((diff (shell-command-to-string "git diff --cached")))
    (if (string-empty-p diff)
        (user-error "Nothing staged for commit")
      (let ((rules-dir (expand-file-name "~/.agents/rules"))
            (rules ""))
        (when (file-directory-p rules-dir)
          (dolist (f (directory-files rules-dir t "\\.md$"))
            (setq rules (concat rules (with-temp-buffer (insert-file-contents f) (buffer-string)) "\n\n"))))
        (gptel-request
         (format "Generate a concise, conventional commit message (type: scope: subject) for this diff:\n\n```\n%s\n```\n\nRules:\n%s"
                 diff rules)
         :backend (gptel-get-backend "OpenCode Zen")
         :model 'deepseek-v4-flash-free
         :callback
         (lambda (response _info)
           (when response
             (let ((msg (string-trim response)))
               (kill-new msg)
               (message "Commit message copied to kill-ring: %s" msg)))))))))

(provide 'custom-git)
;;; custom-git.el ends here
