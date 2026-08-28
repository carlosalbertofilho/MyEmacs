;;; custom-lang.el --- Languages and LSP -*- lexical-binding: t; -*-

;;; Commentary:
;; eglot (LSP), treesit-auto, linguagens: Go, TypeScript/React, Python, C/C++.
;; Formatters: ruff (Python), etc.

;;; Code:

(defvar treesit-extra-load-path)
(defvar +carlos/gptel-quick-local-backend)
(defvar apheleia-mode-alist)
(defvar apheleia-formatters)


;; Registrar diretórios de gramáticas Tree-Sitter do Nix no top-level
(dolist (dir (append (file-expand-wildcards "/nix/store/*-emacs-treesit-grammars")
                     (file-expand-wildcards "/nix/store/*-home-manager-path")
                     '("~/.nix-profile"
                       "~/.nix-profile/lib"
                       "/run/current-system/sw/lib")))
  (let ((expanded (expand-file-name dir)))
    (when (file-directory-p expanded)
      (add-to-list 'treesit-extra-load-path expanded))))

;; ── treesit-auto ────────────────────────────────────────────────────
(defun +carlos/watch-minibuffer-treesit-prompt ()
  "Observa a abertura do minibuffer e loga/auto-confirma prompts do Tree-sitter."
  (when-let* ((prompt (minibuffer-prompt)))
    (when (string-match-p "\\(tree-sitter\\|grammar\\|Tree-sitter\\)" prompt)
      (message "[Minibuffer Watcher] Prompt do Tree-sitter detectado: %s" prompt)
      (ignore-errors (execute-kbd-macro (kbd "y"))))))

(add-hook 'minibuffer-setup-hook #'+carlos/watch-minibuffer-treesit-prompt)

(use-package treesit-auto
  :ensure (:wait t)
  :demand t
  :custom
  (treesit-auto-install 'always)
  :config
  (unless noninteractive
    (global-treesit-auto-mode 1)))

;; ── eglot (built-in Emacs 29+) ──────────────────────────────────────
;; NOTE: Avoid `prog-mode' hook — eglot-ensure on ALL prog modes causes slowdown.
;; Use per-mode hooks instead (see language sections below).
(use-package eglot
  :ensure nil
  :config
  ;; Aumenta limite de memoria V8/Node para servidores LSP Node.js
  (setenv "NODE_OPTIONS" "--max-old-space-size=8192")
  ;; Ignorar formatação do servidor para C/C++ (Norma 42 controla)
  (add-to-list 'eglot-ignored-server-capabilities :documentFormattingProvider)
  (add-to-list 'eglot-ignored-server-capabilities :documentRangeFormattingProvider))
  ;; Suprime popup de erro do Corfu quando o servidor LSP sofre timeout no completion
  (advice-add 'eglot-completion-at-point :around
              (lambda (orig-fun &rest args)
                (condition-case nil
                    (apply orig-fun args)
                  (jsonrpc-error nil))))

;; ── Go ──────────────────────────────────────────────────────────────
(use-package go-ts-mode
  :ensure nil
  :mode ("\\.go\\'" . go-ts-mode)
  :hook (go-ts-mode . eglot-ensure))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '(go-ts-mode go-mode . ("gopls"))))

;; ── TypeScript / React ──────────────────────────────────────────────
(use-package typescript-ts-mode
  :ensure nil
  :mode (("\\.ts\\'"  . typescript-ts-mode)
         ("\\.tsx\\'" . tsx-ts-mode))
  :hook ((typescript-ts-mode tsx-ts-mode) . eglot-ensure))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '((typescript-ts-mode tsx-ts-mode typescript-mode) .
                 ("typescript-language-server" "--stdio"))))

;; ── Python ──────────────────────────────────────────────────────────
(use-package python
  :ensure nil
  :mode (("\\.py\\'" . python-ts-mode))
  :hook ((python-mode python-ts-mode) . eglot-ensure)
  :config
  (setq python-shell-interpreter "ipython"
        python-shell-interpreter-args "-i --simple-prompt --no-color-info"))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               `((python-ts-mode python-mode) . ,(eglot-alternatives (list '("basedpyright-langserver" "--stdio") '("pyright-langserver" "--stdio") '("ruff" "server") "pylsp")))))

(defun +carlos/python-eval-to-minibuffer ()
  "Executa o arquivo Python atual (ou seleção) exibindo na minibuffer."
  (interactive)
  (when (and buffer-file-name (buffer-modified-p))
    (save-buffer))
  (let* ((use-reg (use-region-p))
         (code (if use-reg
                   (buffer-substring-no-properties (region-beginning) (region-end))
                 (buffer-substring-no-properties (point-min) (point-max))))
         (cmd (if (and buffer-file-name (not use-reg))
                  (format "python %s" (shell-quote-argument buffer-file-name))
                (format "python -c %s" (shell-quote-argument code))))
         (output (string-trim (shell-command-to-string cmd))))
    (message "🐍 [%s]\n%s"
             (if buffer-file-name (file-name-nondirectory buffer-file-name) "Snippet")
             (if (string-empty-p output) "(Executado com sucesso, sem saída de texto)" output))))

(with-eval-after-load 'python
  (define-key python-ts-mode-map (kbd "C-c c r") #'+carlos/python-eval-to-minibuffer)
  (define-key python-mode-map (kbd "C-c c r") #'+carlos/python-eval-to-minibuffer))


;; ── C / C++ (42 School) ─────────────────────────────────────────────
;; clangd is detected automatically by eglot.
;; Formatting is ignored (see eglot-ignored-server-capabilities above).
;; NOTE: No eglot-ensure hook — 42 School uses flycheck-norminette instead.

;; ── reformatter.el (wrapper for external CLI reformatters) ──────────
;; Used by custom-42.el to define c_formatter_42 integration.
(use-package reformatter
  :ensure (:wait t)
  :demand t)

;; ── Elisp ───────────────────────────────────────────────────────────
;; Elisp uses native ElDoc and completion-at-point (no LSP required)
(use-package elisp-mode
  :ensure nil)

;; ── Shell / Bash ────────────────────────────────────────────────────
(use-package sh-script
  :ensure nil
  :mode (("\\.sh\\'" . sh-mode)
         ("\\.bash\\'" . sh-mode)))

;; ── JSON ────────────────────────────────────────────────────────────
(use-package json-ts-mode
  :ensure nil
  :mode ("\\.json\\'" . json-ts-mode))

;; ── YAML ────────────────────────────────────────────────────────────
(use-package yaml-mode
  :ensure t
  :mode ("\\.ya?ml\\'" . yaml-mode))

;; ── Markdown ────────────────────────────────────────────────────────
(use-package markdown-mode
  :ensure nil
  :mode ("\\.md\\'" . markdown-mode))

;; ── Nix & NixOS ──────────────────────────────────────────────────────
(use-package nix-mode
  :ensure t
  :mode ("\\.nix\\'" . nix-mode)
  :hook (nix-mode . eglot-ensure))

(use-package envrc
  :ensure t
  :init
  ;; Previne erro 'Invalid function: envrc--with-required-current-env'
  ;; garantindo o carregamento ordenado das macros do envrc
  (with-eval-after-load 'envrc
    (load "envrc" nil t))
  :config
  ;; Desativa envrc em buffers TRAMP para evitar erro code 127
  (setq envrc-remote nil)
  ;; Reconecta o Eglot reativamente quando o direnv/devenv atualiza o $PATH no buffer
  (add-hook 'envrc-mode-hook
            (lambda ()
              (when (and envrc-mode
                         (fboundp 'eglot-reconnect))
                (run-at-time 0.2 nil
                             (lambda ()
                               (ignore-errors (eglot-reconnect)))))))
  :hook (after-init . envrc-global-mode))

(defun +carlos/nixos-rebuild-switch (&optional flake-path)
  "Executes `sudo nixos-rebuild switch` asynchronously using compile mode."
  (interactive
   (list (read-directory-name "NixOS Flake directory: " "/etc/nixos")))
  (let* ((target (expand-file-name (or flake-path "/etc/nixos")))
         (cmd (format "sudo nixos-rebuild switch --flake %s" (shell-quote-argument target))))
    (compile cmd)))

;; ── Rust ────────────────────────────────────────────────────────────
(use-package rust-mode
  :ensure t
  :mode ("\\.rs\\'" . rust-ts-mode)
  :hook (rust-ts-mode . eglot-ensure)
  :config
  (setq rust-mode-treesitter-derive t))

(use-package cargo
  :ensure t
  :hook (rust-ts-mode . cargo-minor-mode))

(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs
               '((rust-ts-mode rust-mode) . ("rust-analyzer")))
  (add-to-list 'eglot-server-programs
               `((nix-mode) . ,(eglot-alternatives '("nixd" "nil" "rnix-lsp")))))

(with-eval-after-load 'apheleia
  (add-to-list 'apheleia-mode-alist '(rust-ts-mode . rustfmt))
  (add-to-list 'apheleia-mode-alist '(rust-mode . rustfmt))
  (add-to-list 'apheleia-mode-alist '(nix-mode . nixfmt))
  (setf (alist-get 'nixfmt apheleia-formatters) '("nixfmt")))

;; ── Editorconfig ────────────────────────────────────────────────────
(use-package editorconfig
  :config
  (editorconfig-mode 1))

;; ── Forward declarations for Flycheck, Eldoc-box, Apheleia, AI ──────
(declare-function flycheck-next-error "flycheck")
(declare-function flycheck-previous-error "flycheck")
(declare-function consult-flycheck "consult-flycheck")
(declare-function flycheck-inline-mode "flycheck-inline")
(declare-function eldoc-box-hover-at-point-mode "eldoc-box")
(declare-function eldoc-box-help-at-point "eldoc-box")
(declare-function apheleia-global-mode "apheleia")
(declare-function +carlos/gptel-request "custom-ai")
(declare-function bounds-of-thing-at-point "thingatpt")

(defvar apheleia-inhibit-functions)

;; ── Flycheck & Flycheck-inline ─────────────────────────────────────
(setq-default flycheck-indication-mode 'left-fringe)

(use-package flycheck
  :ensure (:wait t)
  :demand t
  :config
  (define-key flycheck-mode-map (kbd "M-g n") #'flycheck-next-error)
  (define-key flycheck-mode-map (kbd "M-g p") #'flycheck-previous-error))

(use-package consult-flycheck
  :ensure t
  :after (consult flycheck)
  :bind ("C-c ! l" . consult-flycheck))

(use-package flycheck-inline
  :ensure t
  :after flycheck
  :hook (flycheck-mode . flycheck-inline-mode))

;; ── eldoc-box (documentation hover) ────────────────────────────────
(use-package eldoc-box
  :ensure t
  :hook (eglot-managed-mode . eldoc-box-hover-at-point-mode)
  :bind ("C-c c h" . eldoc-box-help-at-point))

;; ── apheleia (code formatting) ─────────────────────────────────────
(use-package apheleia
  :ensure t
  :config
  (apheleia-global-mode +1)
  (add-to-list 'apheleia-inhibit-functions
               (lambda () (derived-mode-p 'c-mode 'c-ts-mode))))

;; ── Local AI docstring & test generation ───────────────────────────
(defun +carlos/generate-docstring-at-point ()
  "Gera docstring padronizada para a função sob o cursor.
Usa o backend local configurado para tarefas rápidas."
  (interactive)
  (let ((bounds (bounds-of-thing-at-point 'defun)))
    (if (not bounds)
        (message "Nenhuma função encontrada sob o cursor.")
      (let ((code (buffer-substring-no-properties (car bounds) (cdr bounds))))
        (+carlos/gptel-request
         (format "Escreva apenas a docstring padronizada (PEP 257 / Doxygen / Norm 4.1) para o código a seguir. Não inclua código extra:\n\n%s" code)
         +carlos/gptel-quick-local-backend
         +carlos/gptel-quick-local-model
         :stream nil
         :callback (lambda (response info)
                     (if (stringp response)
                         (message "Docstring Gerada:\n%s" response)
                       (when (plist-get info :error)
                         (message "Erro ao gerar docstring: %s" (plist-get info :error))))))))))

(defun +carlos/generate-test-at-point ()
  "Gera esqueleto de teste unitário para a função sob o cursor.
Usa o backend local configurado para tarefas rápidas."
  (interactive)
  (let ((bounds (bounds-of-thing-at-point 'defun)))
    (if (not bounds)
        (message "Nenhuma função encontrada sob o cursor.")
      (let ((code (buffer-substring-no-properties (car bounds) (cdr bounds))))
        (+carlos/gptel-request
         (format "Escreva um teste unitário conciso para a função a seguir:\n\n%s" code)
         +carlos/gptel-quick-local-backend
         +carlos/gptel-quick-local-model
         :stream nil
         :callback (lambda (response info)
                     (if (stringp response)
                         (message "Esqueleto de Teste Gerado:\n%s" response)
                       (when (plist-get info :error)
                         (message "Erro ao gerar teste: %s" (plist-get info :error))))))))))

(global-set-key (kbd "C-c c d") #'+carlos/generate-docstring-at-point)
(global-set-key (kbd "C-c c t") #'+carlos/generate-test-at-point)

(provide 'custom-lang)
;;; custom-lang.el ends here
