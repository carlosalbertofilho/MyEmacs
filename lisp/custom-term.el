;;; custom-term.el --- Terminal and shell -*- lexical-binding: t; -*-

;;; Commentary:
;; eat (ANSI/TUI in Eshell), vterm + vterm-toggle, capf-autosuggest,
;; eshell-git-prompt (Starship-style), popper (window management),
;; AI tool integration (opencode, agy/gemini-cli).

;;; Code:

;; ── vterm ───────────────────────────────────────────────────────────
;; Prevent vterm from prompting for module compilation in batch mode
(defun +carlos/vterm-skip-compile-prompt (orig-fun &rest args)
  "Skip y-or-n-p prompts about vterm module compilation."
  (if (and noninteractive (stringp (car args))
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
  (setq vterm-copy-exclude-prompt t))

;; Multiline prompt helper
(defun +carlos/vterm-write-multiline-prompt ()
  "Write clipboard or selection content as multiline in vterm."
  (interactive)
  (when-let* ((text (or (car kill-ring) "")))
    (vterm-send-string text)))

(with-eval-after-load 'vterm
  (define-key vterm-mode-map (kbd "C-c C-e") #'+carlos/vterm-write-multiline-prompt))

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

;; Toggle between Emacs mode and Char mode (send keys directly to program)
(with-eval-after-load 'eshell
  (define-key eshell-mode-map (kbd "C-c C-q") #'eat-toggle-char-mode))

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

;; ── eshell-git-prompt (Starship/Oh My Zsh style) ───────────────────
;; Replaces eshell-prompt-extras with modern Git-aware prompt.
(use-package eshell-git-prompt
  :ensure t
  :after eshell
  :config
  (eshell-git-prompt-use-theme 'powerline))

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
        eshell-cmpl-cycle-completions nil)
  ;; Sync PATH with system shell so Eshell can find npx, bunx, agy, etc.
  (setq eshell-path-extra
        (append '("/etc/profiles/per-user/carlosfilho/bin"
                  "/var/folders/p6/jvskwtqn1tl1d75kgr4p32g00000gn/T/bunx-501-opencode-ai@latest/node_modules/.bin"
                  "/run/current-system/sw/bin"
                  "/nix/var/nix/profiles/default/bin")
                eshell-path-extra)))

;; AI tool aliases for Eshell
(defun +carlos/eshell-ai-aliases ()
  "Add aliases for opencode and agy (Gemini CLI) in Eshell.
Uses explicit paths since Eshell's PATH may differ from system shell."
  (when (fboundp 'eshell/alias)
    ;; opencode: AI coding assistant CLI (bunx temp path or npx)
    (let ((oc-path (or (executable-find "opencode")
                       "/var/folders/p6/jvskwtqn1tl1d75kgr4p32g00000gn/T/bunx-501-opencode-ai@latest/node_modules/.bin/opencode")))
      (when (file-executable-p oc-path)
        (eshell/alias "oc" (concat oc-path " $*"))
        (eshell/alias "ai" (concat oc-path " $*"))
        (eshell/alias "aif" (concat oc-path " fix $*"))
        (eshell/alias "aireview" (concat oc-path " review $*"))))
    ;; agy: Gemini CLI agent (Nix profile path)
    (let ((agy-path (or (executable-find "agy")
                        "/etc/profiles/per-user/carlosfilho/bin/agy")))
      (when (file-executable-p agy-path)
        (eshell/alias "agy" (concat agy-path " $*"))
        (eshell/alias "gemini" (concat agy-path " $*"))))))

(add-hook 'eshell-mode-hook #'+carlos/eshell-ai-aliases)

;; Force char-mode for AI CLI tools when they start
(defun +carlos/eshell-run-agy ()
  "Run agy (Gemini CLI) with eat char-mode enabled."
  (interactive)
  (let ((agy-path (or (executable-find "agy")
                      "/etc/profiles/per-user/carlosfilho/bin/agy")))
    (if (file-executable-p agy-path)
        (progn
          (insert (concat agy-path " "))
          (eshell-send-input)
          ;; Toggle char-mode after command starts
          (run-with-timer 0.2 nil #'eat-toggle-char-mode))
      (message "agy not found"))))

(defun +carlos/eshell-run-opencode ()
  "Run opencode AI CLI with eat char-mode enabled."
  (interactive)
  (let ((oc-path (or (executable-find "opencode")
                     "/var/folders/p6/jvskwtqn1tl1d75kgr4p32g00000gn/T/bunx-501-opencode-ai@latest/node_modules/.bin/opencode")))
    (if (file-executable-p oc-path)
        (progn
          (insert (concat oc-path " "))
          (eshell-send-input)
          (run-with-timer 0.2 nil #'eat-toggle-char-mode))
      (message "opencode not found"))))

;; Bindings for AI tools in Eshell
(with-eval-after-load 'eshell
  (define-key eshell-mode-map (kbd "C-c A a") #'+carlos/eshell-run-agy)
  (define-key eshell-mode-map (kbd "C-c A o") #'+carlos/eshell-run-opencode))

;; ── popper (Intelligent popup window management) ───────────────────
;; Classifies terminal buffers as popups — toggle/hide without messing layout.
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
