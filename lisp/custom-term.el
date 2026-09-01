;;; custom-term.el --- Terminal and shell -*- lexical-binding: t; -*-

;;; Commentary:
;; eat (ANSI/TUI in Eshell), vterm + vterm-toggle, capf-autosuggest,
;; Starship-style prompt (native Elisp), nerd-icons ls decoration,
;; popper (window management), AI tool integration (opencode, agy/gemini-cli).

;;; Code:

;; Forward declarations for byte-compiler
(declare-function eshell-send-input "esh-mode")
(declare-function eshell-kill-input "esh-mode")
(declare-function eshell/alias "em-alias")
(declare-function eat-toggle-char-mode "eat")
(declare-function eat-exec-cmd "eat")
(declare-function eat-make-buffer "eat")
(declare-function vterm-send-string "vterm")
(declare-function popper-echo-mode "popper")
(declare-function project-root "project")
;; Forward declarations peladas: vterm/eshell definem esses maps com
;; keymap NÃO-nil — `(defvar X nil)' clobberaria o default (gotcha Emacs 30).
;; Os define-key abaixo rodam após o pacote dono carregar (map já bound).
(declare-function eshell/pwd "em-dirs")
(declare-function nerd-icons-icon-for-file "nerd-icons")
(declare-function nerd-icons-icon-for-dir "nerd-icons")
(declare-function eshell-ls-decorated-name "em-ls")
(declare-function eshell-plain-command "esh-ext")
(declare-function magit-log-head "magit-log")
(defvar eshell-last-command-status)
(defvar vterm-mode-map)
(defvar eshell-mode-map)
(defvar eshell-visual-commands)

;; ── vterm ───────────────────────────────────────────────────────────
;; Prevent vterm from prompting for module compilation in batch mode
(defun +carlos/vterm-skip-compile-prompt (orig-fun &rest args)
  "Skip `y-or-n-p` prompt about vterm module compilation in batch or daemon mode.
ORIG-FUN and ARGS are passed to the original function."
  (if (and (or noninteractive (daemonp))
           (stringp (car args))
           (string-match-p "vterm" (car args)))
      nil
    (apply orig-fun args)))

(advice-add 'y-or-n-p :around #'+carlos/vterm-skip-compile-prompt)

(use-package vterm
  :ensure t
  :catch t
  :config
  (setq vterm-keymap-exceptions
        (delete "C-c" (delete "C-u" (delete "C-g" vterm-keymap-exceptions))))
  (setq vterm-max-scrollback 100000)
  (setq vterm-copy-exclude-prompt t)
  ;; Multiline prompt helper
  (define-key vterm-mode-map (kbd "C-c C-e") #'+carlos/vterm-write-multiline-prompt))

;; Multiline prompt helper
(defun +carlos/vterm-write-multiline-prompt ()
  "Write clipboard or selection content as multiline in vterm."
  (interactive)
  (when-let* ((text (or (car kill-ring) "")))
    (vterm-send-string text)))

;; ── vterm-toggle (IDE-style terminal drawer) ────────────────────────
(use-package vterm-toggle
  :ensure t
  :after vterm
  :bind
  (("C-`" . vterm-toggle))
  :config
  (setq vterm-toggle-fullscreen-p nil
        vterm-toggle-scope 'project    ;; Open in current project root
        vterm-toggle-reuse-existing t))

;; ── eat (Emulate A Terminal — ANSI/TUI in Eshell) ──────────────────
;; Eat transforms Eshell into a hybrid: Emacs objects + full terminal emulation.
;; Supports htop, ranger, lazygit, TUIs, ANSI graphics, mouse.
(use-package eat
  :ensure t
  :hook (eshell-mode . eat-eshell-mode)
  :config
  (setq eat-enable-mouse t             ;; Mouse support in TUIs
        eat-kill-buffer-on-exit t      ;; Clean up on exit
        ;; Auto char-mode for interactive commands (y/n prompts, TUIs)
        eat-semi-char-non-semi-commands
        '("just" "opencode" "agy" "gemini" "devenv" "htop" "btop" "ranger" "lazygit" "vim" "nano")))

;; ── Just + Eat integration (Opção 2: Project.el) ──────────────────
;; Run just recipes from project root in an eat buffer.
(defun +carlos/project-just-run ()
  "Run the default just recipe in project root using eat."
  (interactive)
  (when-let* ((root (project-root (project-current t))))
    (let* ((buf-name (format "*just: %s*" (file-name-nondirectory (directory-file-name root))))
           (eat-buf (eat-make-buffer buf-name)))
      (with-current-buffer eat-buf
        (cd root)
        (eat-exec-cmd "just" nil))
      (pop-to-buffer eat-buf))))

(defun +carlos/eat-just-recipe (recipe)
  "Run a specific just RECIPE in project root using eat."
  (interactive
   (list (completing-read "Just recipe: "
                          (process-lines "just" "--summary"))))
  (when-let* ((root (project-root (project-current t))))
    (let* ((buf-name (format "*just: %s*" recipe))
           (eat-buf (eat-make-buffer buf-name)))
      (with-current-buffer eat-buf
        (cd root)
        (eat-exec-cmd "just" (list recipe)))
      (pop-to-buffer eat-buf))))

;; Bindings
(global-set-key (kbd "C-c j j") #'+carlos/project-just-run)
(global-set-key (kbd "C-c j r") #'+carlos/eat-just-recipe)

;; ── capf-autosuggest (Fish/Zsh-style inline completions) ───────────
;; Shows ghost text from history as you type. Press → or End to accept.
(use-package capf-autosuggest
  :ensure t
  :hook (eshell-mode . capf-autosuggest-mode)
  :config
  (setq capf-autosuggest-look-back 1000)) ;; Search back in history

;; ── Eshell Starship-style Prompt ────────────────────────────────────
(defun +carlos/eshell-devenv-env-p (&rest names)
  "Return non-nil if any of the NAMES env vars is set to a non-empty value."
  (seq-some (lambda (n) (and (getenv n) (not (string-empty-p (getenv n))))) names))

(defun +carlos/eshell-devenv-toolchain ()
  "Return the active toolchain labels exported by the devenv, or \"\".
Detects which languages the devenv has exported based on its env traps:
GOROOT/GOPATH, NIX_PYTHONPATH/PYTHONPATH, RUSTFLAGS and CC.  Runs only
when `DEVENV_ROOT' is set, so it is a no-op outside a devenv shell."
  (when (getenv "DEVENV_ROOT")
    (let ((chain '()))
      (when (+carlos/eshell-devenv-env-p "GOROOT" "GOPATH") (push "go" chain))
      (when (+carlos/eshell-devenv-env-p "NIX_PYTHONPATH" "PYTHONPATH") (push "python" chain))
      (when (+carlos/eshell-devenv-env-p "RUSTFLAGS" "RUSTDOCFLAGS") (push "rust" chain))
      (when (+carlos/eshell-devenv-env-p "CC") (push "c" chain))
      (when chain (concat " (" (mapconcat #'identity chain " ") ")")))))

(defun +carlos/eshell-starship-prompt ()
  "Prompt multilinha para Eshell inspirado no Starship com Host, SSH, Docker e Git."
  (let* ((last-status (or (bound-and-true-p eshell-last-command-status) 0))
         (status-color (if (= last-status 0) "#a3be8c" "#bf616a"))
         (remote-info (file-remote-p default-directory))
         (is-ssh (or (getenv "SSH_CLIENT") (getenv "SSH_TTY")
                     (and remote-info (string-match-p "ssh" remote-info))))
         (is-docker (or (file-exists-p "/.dockerenv")
                        (getenv "CONTAINER_ID")
                        (and remote-info (string-match-p "docker\\|container" remote-info))))
         (user-host (concat (user-login-name) "@" (car (split-string (system-name) "\\."))))

         ;; Contexto do Host (Docker, SSH ou Local)
         (host-str (cond
                    (is-docker
                     (propertize (concat "🐳 " user-host " (docker)") 'face '(:foreground "#81a1c1" :weight bold)))
                    (is-ssh
                     (propertize (concat "🌐 " user-host " (ssh)") 'face '(:foreground "#ebcb8b" :weight bold)))
                    (t
                     (propertize (concat "💻 " user-host) 'face '(:foreground "#d8dee9" :weight bold)))))

         ;; Diretório
         (dir (abbreviate-file-name (if (fboundp 'eshell/pwd) (eshell/pwd) default-directory)))
         (dir-str (propertize (concat " 📁 " dir) 'face '(:foreground "#88c0d0" :weight bold)))

         ;; Ambientes (Python Virtualenv, Nix Shell e Devenv)
         (venv (when-let* ((v (getenv "VIRTUAL_ENV"))) (file-name-nondirectory v)))
         (venv-str (if venv (propertize (concat " 🐍 " venv) 'face '(:foreground "#a3be8c")) ""))
         (nix-str (if (getenv "IN_NIX_SHELL") (propertize " ❄️ nix" 'face '(:foreground "#7dcfff")) ""))
         (devenv-root (getenv "DEVENV_ROOT"))
         (devenv-str (when devenv-root
                       (propertize
                        (concat " 🔗 " (file-name-nondirectory devenv-root)
                                (+carlos/eshell-devenv-toolchain))
                        'face '(:foreground "#81a1c1"))))

         ;; Git Branch
         (git-branch (when (and (fboundp 'vc-backend) (vc-backend default-directory))
                       (ignore-errors (substring (vc-working-revision default-directory) 0 7))))
         (git-str (if git-branch
                      (propertize (concat " 🌿 " git-branch) 'face '(:foreground "#b48ead" :weight bold))
                    ""))

         ;; Seta do Prompt (Verde se 0 / Vermelho se Erro)
         (arrow (propertize "❯" 'face `(:foreground ,status-color :weight bold))))

    (concat "\n" host-str dir-str git-str venv-str nix-str devenv-str "\n" arrow " ")))

;; ── eshell (built-in) ───────────────────────────────────────────────
(use-package eshell
  :ensure nil
  :bind
  (("C-c e" . eshell))
  :config
  (setq eshell-buffer-name "*eshell*"
        eshell-scroll-to-bottom-on-input 'all
        eshell-error-if-no-glob t
        eshell-hist-file-size 10000
        eshell-cmpl-cycle-completions nil
        eshell-prompt-function #'+carlos/eshell-starship-prompt
        eshell-prompt-regexp "^❯ ")
  (with-eval-after-load 'em-term
    (dolist (cmd '("ssh" "top" "htop" "devenv" "nix" "tmux" "mosh"))
      (add-to-list 'eshell-visual-commands cmd))))

;; Eshell keybindings (after esh-mode loads; eshell-mode-map lives in
;; esh-mode, which loads lazily after eshell in Emacs 30)
(with-eval-after-load 'esh-mode
  (define-key eshell-mode-map (kbd "C-c C-q") #'eat-toggle-char-mode)
  (define-key eshell-mode-map (kbd "C-c A a") #'+carlos/eshell-run-agy)
  (define-key eshell-mode-map (kbd "C-c A o") #'+carlos/eshell-run-opencode))

;; AI tool aliases for Eshell
(defun +carlos/eshell-ai-aliases ()
  "Add aliases for opencode, agy (Gemini CLI) and ll in Eshell."
  (when (fboundp 'eshell/alias)
    (eshell/alias "oc" "opencode $*")
    (eshell/alias "ai" "opencode $*")
    (eshell/alias "aif" "opencode fix $*")
    (eshell/alias "aireview" "opencode review $*")
    (eshell/alias "agy" "agy $*")
    (eshell/alias "gemini" "agy $*")
    ;; ll como atalho para ls -la (usa o eshell/ls nativo em Elisp)
    (eshell/alias "ll" "ls -la $*")))
(defun eshell/git (&rest args)
  "Map `git log' in Eshell to the graphical Magit buffer.

When the first ARGS is `log' (or a log sub-command like `lg'), open the
Magit commit log `--graph --oneline -20' instead of running plain
`git log'.  All other git invocations fall back to the real git binary,
preserving normal Eshell CLI behavior."
  (if (or (null args)
          (and (stringp (car args)) (member (car args) '("log" "lg"))))
      (progn
        (magit-log-head '("-20" "--graph" "--oneline"))
        nil)
    (eshell-plain-command "git" args)))

(add-hook 'eshell-mode-hook #'+carlos/eshell-ai-aliases)

;; ── Nerd Icons para eshell/ls nativo ───────────────────────────────
;; Decora cada entrada do `ls` com ícone Nerd Fonts por tipo de arquivo.
;; Funciona em local, SSH e Docker (100% Elisp, sem binários externos).
(defun +carlos/eshell-ls-nerd-icon (name)
  "Prefixo o NAME com um ícone nerd-icons baseado no tipo do arquivo."
  (when (require 'nerd-icons nil t)
    (let* ((file (if (stringp name) name (car name)))
           (icon (if (file-directory-p file)
                     (nerd-icons-icon-for-dir file)
                   (nerd-icons-icon-for-file file))))
      (when (and icon (not (string-empty-p icon)))
        (concat icon " "))))  )

(with-eval-after-load 'em-ls
  (advice-add 'eshell-ls-decorated-name :around
              (lambda (orig-fun file)
                "Adiciona ícone nerd-icons antes do nome decorado pelo Eshell."
                (let ((decorated (funcall orig-fun file))
                      (icon (ignore-errors (+carlos/eshell-ls-nerd-icon file))))
                  (if icon (concat icon decorated) decorated)))))

;; Interactive dispatchers for AI tools (Let Eat handle char-mode automatically)
(defun +carlos/eshell-run-in-buffer (cmd)
  "Execute CMD in the current Eshell buffer cleanly."
  (interactive)
  (goto-char (point-max))
  (eshell-kill-input)
  (insert cmd)
  (eshell-send-input))

(defun +carlos/eshell-run-agy ()
  "Run agy (Gemini CLI) in Eshell."
  (interactive)
  (+carlos/eshell-run-in-buffer "agy"))

(defun +carlos/eshell-run-opencode ()
  "Run opencode AI CLI in Eshell."
  (interactive)
  (+carlos/eshell-run-in-buffer "opencode"))

;; ── popper (Intelligent popup window management) ───────────────────
;; Classifies terminal buffers as popups — toggle/hide without messing layout.
;; Popups are shown as a wide left aside (dirvish-aside stays on the right).
(defun +carlos/popper-display-popup-at-left (buffer &optional alist)
  "Display popup-buffer BUFFER at the left side of the screen.
ALIST is an association list of action symbols and values.  See
Info node `(elisp) Buffer Display Action Alists' for details."
  (display-buffer-in-side-window
   buffer
   (append alist
           `((window-width . 0.45)
             (side . left)
             (slot . 0)))))

(defun +carlos/popper-select-popup-at-left (buffer &optional alist)
  "Display and switch to popup-buffer BUFFER at the left side.
ALIST is an association list of action symbols and values."
  (let ((window (+carlos/popper-display-popup-at-left buffer alist)))
    (select-window window)))

(use-package popper
  :ensure t
  :bind
  (("C-`"   . popper-toggle-latest)
   ("M-`"   . popper-cycle)
   ("C-M-`" . popper-toggle-type))
  :init
  (setq popper-reference-buffers
        '("\\*eshell\\*"
          "\\*vterm\\*"
          "\\*eat\\*"
          "\\*compilation\\*"
          "\\*async-shell-command\\*"
          output-mode
          help-mode))
  :config
  (setq popper-display-function #'+carlos/popper-select-popup-at-left)
  (popper-mode 1)
  (popper-echo-mode 1))  ;; Show popup info in echo area

;; ── Display buffer rules (fallback for non-popper windows) ─────────
(add-to-list 'display-buffer-alist
             '("\\*vterm"
               (display-buffer-in-direction)
               (direction . bottom)
               (window-height . 0.4)))

(provide 'custom-term)
;;; custom-term.el ends here
