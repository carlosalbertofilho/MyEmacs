;;; custom-git.el --- Git and workflow tools -*- lexical-binding: t; -*-

;;; Commentary:
;; magit, just-mode/justl, commit message com IA (reescrito sem magit).

;;; Code:

;; Forward declarations for byte-compiler
(declare-function vc-git-root "vc-git")
(declare-function +carlos/gptel-request "custom-ai")
(declare-function +carlos/magent-resolve-cheap-model "custom-magent-context")
(defvar +carlos/gptel-quick-local-backend)
(defvar +carlos/gptel-quick-local-model)
(declare-function makefile-executor-execute-project-target "makefile-executor")
(declare-function makefile-executor-execute-last "makefile-executor")
(declare-function makefile-executor-mode "makefile-executor")
(declare-function justl-compile "justl")
(declare-function transient-append-suffix "transient")

;; ── magit ───────────────────────────────────────────────────────────
;; transient é instalado/ativado cedo no init.el (:ensure (:wait t));
;; um segundo `:ensure t' aqui causaria "Duplicate item ID queued: transient".
(use-package magit
  :ensure t
  :after transient
  :bind
  (("C-c g" . magit-status))
  :config
  (setq magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1))

;; ── just-mode ───────────────────────────────────────────────────────
(use-package just-mode
  :ensure t
  :mode ("Justfile\\'" . just-mode))

;; ── justl (interação com Justfile) ─────────────────────────────────
(use-package justl
  :ensure t
  :after just-mode
  :config
  (global-set-key (kbd "C-c j") #'justl)
  (global-set-key (kbd "C-c J") #'justl-compile))

(declare-function makefile-executor-execute-project-target "makefile-executor")
(declare-function makefile-executor-execute-last "makefile-executor")
(declare-function makefile-executor-mode "makefile-executor")

(defun +carlos/makefile-executor-project-target ()
  "Executa o alvo do Makefile do projeto com fallback seguro."
  (interactive)
  (let ((dir (or (when-let* ((proj (project-current)))
                   (project-root proj))
                 default-directory)))
    (if (file-exists-p (expand-file-name "Makefile" dir))
        (let ((default-directory dir))
          (makefile-executor-execute-project-target))
      (user-error "Nenhum Makefile encontrado no diretório: %s" dir))))

(defun +carlos/makefile-executor-last ()
  "Re-executa o último alvo do Makefile."
  (interactive)
  (if (fboundp 'makefile-executor-execute-last)
      (makefile-executor-execute-last)
    (user-error "Nenhum alvo do Makefile foi executado anteriormente")))

;; ── makefile-executor (interação com Makefiles) ────────────────────
(use-package makefile-executor
  :ensure t
  :hook (makefile-mode . makefile-executor-mode)
  :bind
  (("C-c m m" . +carlos/makefile-executor-project-target)
   ("C-c m l" . +carlos/makefile-executor-last)))

;; ── +carlos/gptel-generate-commit-message ──────────────────────────
;; Reescrito sem dependência de magit (usa vc-git / processo git) e com
;; a API do gptel 0.9.9.5 (sem :backend/:model — usa +carlos/gptel-request).
;; O backend/modelo é resolvido pelo selecionador inteligente da Fase A
;; (local se online, senão flash free) com fallback para os quick vars.

(defun +carlos/git-commit-ai-pair ()
  "Retorna (BACKEND . MODEL) para a geração de commit com IA (B5.2).
Resolve via `+carlos/magent-resolve-cheap-model' (selecionador inteligente:
local se online, senão free da nuvem); em falha, fallback para
`+carlos/gptel-quick-local-backend'/`+carlos/gptel-quick-local-model'."
  (or (when-let* ((choice (+carlos/magent-resolve-cheap-model))
                  (backend (plist-get choice :backend))
                  (model (plist-get choice :model)))
        (cons backend model))
      (cons +carlos/gptel-quick-local-backend +carlos/gptel-quick-local-model)))

(defun +carlos/gptel-generate-commit-message ()
  "Gera uma mensagem de commit usando IA a partir do diff staged.
Sem dependência de magit: usa \\='git diff --cached\\=' diretamente.
Copia a mensagem gerada para o `kill-ring'."
  (interactive)
  (unless (vc-git-root default-directory)
    (user-error "Not in a Git repository"))
  (let ((diff (shell-command-to-string "git diff --cached")))
    (if (string-empty-p diff)
        (user-error "Nothing staged for commit")
      (let* ((rules-dir (expand-file-name "~/.agents/rules"))
             (rules (when (file-directory-p rules-dir)
                      (mapconcat (lambda (f)
                                   (with-temp-buffer
                                     (insert-file-contents f)
                                     (buffer-string)))
                                 (directory-files rules-dir t "\\.md$")
                                 "\n\n")))
             (pair (+carlos/git-commit-ai-pair)))
        (+carlos/gptel-request
         (format "Generate a concise, conventional commit message (type: scope: subject) for this diff:\n\n```\n%s\n```\n\nRules:\n%s"
                 diff rules)
         (car pair) (intern (cdr pair))
         :system "You are an expert at writing conventional commits."
         :callback
         (lambda (response _info)
           (when response
             (let ((msg (string-trim response)))
               (kill-new msg)
               (message "Commit message copied to kill-ring: %s" msg)))))))))

;; ── +carlos/gptel-insert-commit-message ────────────────────────────
(defun +carlos/gptel-insert-commit-message ()
  "Gera uma mensagem de commit e a insere no buffer de commit atual.
Funciona em buffers `git-commit-mode' ou `magit-commit-mode'."
  (interactive)
  (unless (derived-mode-p 'git-commit-mode 'magit-commit-mode)
    (user-error "Not in a git commit buffer"))
  (let ((diff (shell-command-to-string "git diff --cached")))
    (if (string-empty-p diff)
        (user-error "Nothing staged for commit")
      (let ((commit-buf (current-buffer))
            (pair (+carlos/git-commit-ai-pair)))
        (+carlos/gptel-request
         (format "Generate a concise, conventional commit message (type: scope: subject) for this diff:\n\n```\n%s\n```" diff)
         (car pair) (intern (cdr pair))
         :system "You are an expert at writing conventional commits."
         :callback
         (lambda (response _info)
           (when response
             (with-current-buffer commit-buf
               (goto-char (point-min))
               (insert (string-trim response))))))))))

;; Atalho dentro do buffer de commit (magit e git-commit).
;; Bind direto no mapa (não hook) para aplicar já no carregamento e ser
;; verificável em batch.
(with-eval-after-load 'git-commit
  (when (boundp 'git-commit-mode-map)
    (define-key git-commit-mode-map (kbd "C-c C-g")
      #'+carlos/gptel-insert-commit-message)))
(with-eval-after-load 'magit
  (when (boundp 'magit-commit-mode-map)
    (define-key magit-commit-mode-map (kbd "C-c C-g")
      #'+carlos/gptel-insert-commit-message)))

(with-eval-after-load 'magit-commit
  (when (fboundp 'transient-append-suffix)
    (transient-append-suffix 'magit-commit "c"
      '("g" "IA Commit Message" +carlos/gptel-generate-commit-message))))

(provide 'custom-git)
;;; custom-git.el ends here
