;;; custom-files.el --- File management and remote -*- lexical-binding: t; -*-

;;; Commentary:
;; dirvish com todas as extensões nativas, ibuffer, TRAMP optimization.

;;; Code:

(defvar tramp-completion-reread-directory-timeout)

;; ── dired base ──────────────────────────────────────────────────────
(defun +carlos/gnu-ls-p ()
  "Return non-nil when the ls in PATH is GNU coreutils.
Necessário porque o ls do Nix Home Manager é GNU mesmo no macOS
\(mas não se chama `gls'), viabilizando os switches do dirvish-ls."
  (let ((ls (or (executable-find "ls") insert-directory-program)))
    (and ls
         (with-temp-buffer
           (ignore-errors
             (call-process ls nil t nil "--version")
             (goto-char (point-min))
             (search-forward "GNU coreutils" nil t))))))

(let ((args (list "-ahl" "-v" "--group-directories-first")))
  (when (memq system-type '(darwin berkeley-unix))
    (if-let* ((gls (executable-find "gls")))
        (setq insert-directory-program gls)
      (unless (+carlos/gnu-ls-p)
        (setq args (list "-ahl")))))
  (setq dired-listing-switches (string-join args " ")
        dired-dwim-target t))

(add-hook 'dired-mode-hook
          (lambda ()
            (when (file-remote-p default-directory)
              (setq-local dired-actual-switches "-ahl"))))

;; ── nerd-icons (ícones para dirvish, dashboard, etc) ───────────────
(use-package nerd-icons
  :ensure t
  :demand t
  :config
  ;; Instala ícones na primeira execução interativa se necessário
  (unless (or noninteractive (file-directory-p (expand-file-name "nerd-icons/fonts" user-emacs-directory)))
    (nerd-icons-install-fonts t)))

;; ── dirvish-emerge: navegação entre grupos (guard) ─────────────────
;; `dirvish-emerge-next-group' upstream crasheia (+ nil 1) quando o
;; ponto está fora de um overlay de grupo (ex.: cabeçalho do buffer).
(declare-function dirvish-emerge--get-group-overlay "dirvish-emerge")
(declare-function dirvish-emerge-next-group "dirvish-emerge")
(declare-function dirvish-emerge-previous-group "dirvish-emerge")
(declare-function dirvish-peek-mode "dirvish-peek")
(declare-function dirvish-side-follow-mode "dirvish-side")
(defvar dirvish-emerge--group-overlays nil)

(defun +carlos/dirvish-emerge-goto-group (arg)
  "Ir a um grupo emerge ARG passos a partir do atual.
Sem overlay sob o ponto (ex.: header), vai para o primeiro grupo."
  (interactive "^p")
  (if (or (not (bound-and-true-p dirvish-emerge-mode))
          (not dirvish-emerge--group-overlays))
      (message "Emerge inactive — press E to toggle")
    (if (ignore-errors (dirvish-emerge--get-group-overlay))
        (if (> arg 0)
            (dirvish-emerge-next-group arg)
          (dirvish-emerge-previous-group (- arg)))
      (goto-char (point-min)))))

(defun +carlos/dirvish-emerge-next-group ()
  "Ir ao próximo grupo emerge."
  (interactive)
  (+carlos/dirvish-emerge-goto-group 1))

(defun +carlos/dirvish-emerge-previous-group ()
  "Ir ao grupo emerge anterior."
  (interactive)
  (+carlos/dirvish-emerge-goto-group -1))

(defun +carlos/dirvish-side-open-action (file)
  "Abre FILE na última janela de código ativa (MRU).
Ignora popups, sidebars e minibuffer."
  (if-let* ((win (get-mru-window nil nil t)))
      (with-selected-window win
        (find-file file))
    (find-file-other-window file)))

;; ── dirvish core ────────────────────────────────────────────────────
(use-package dirvish
  :ensure t
  :init
  (dirvish-override-dired-mode 1)
  :custom
  ;; Quick-access entries (2-keystroke jumps)
  (dirvish-quick-access-entries
   '(("h" "~/"                    "Home")
     ("d" "~/Downloads/"          "Downloads")
     ("p" "~/Projects/"           "Projects")
     ("c" "~/.config/"            "Config")
     ("n" "~/org/notes"           "Notes")
     ("e" "~/.config/emacs/"         "Emacs")))
  ;; Layout oficial de 3 painéis (main . side . preview)
  (dirvish-default-layout '(1 0.11 0.55))
  ;; Visual attributes (order matters for rendering)
  ;; git-msg apenas no painel principal; sidebar continua limpa (attrs separados)
  (dirvish-attributes
   '(vc-state git-msg subtree-state nerd-icons collapse file-time file-size))
  ;; Icon settings — offset é `:v-adjust` (float); `-2` quebrava o alinhamento
  (dirvish-nerd-icons-height 0.85)
  (dirvish-nerd-icons-offset 0.00)
  ;; Details e cursor ocultos por padrão
  (dirvish-hide-details t)
  (dirvish-hide-cursor t)
  (dirvish-reuse-session 'open)
  ;; Window / layout
  (dirvish-side-width 35)
  (dirvish-large-directory-threshold 20000)
  (dirvish-use-mode-line t)
  (dirvish-mode-line-format '(:left (sort omit symlink) :right (index)))
  (dirvish-header-line-format '(:left (path) :right (free-space)))
  ;; Subtree — minimalista: setas apenas onde há subpastas
  (dirvish-subtree-always-show-state nil)
  (dirvish-subtree-state-style 'chevron)
  (dirvish-subtree-icon-scale-factor '(0.85 . 0.10))
  ;; Sidebar (visual limpo, sem poluição)
  (dirvish-side-attributes '(nerd-icons collapse subtree-state))
  (dirvish-side-mode-line-format '(:left (sort) :right (index)))
  (dirvish-side-header-line-format '(:left (project)))
  (dirvish-side-open-file-action 'reuse)
  (dirvish-side-auto-expand t)
  ;; Preview dispatchers (correct values: file types, NOT vc commands)
  (dirvish-preview-dispatchers
   '(image gif video audio epub pdf archive))
  ;; Emerge: grupos padrão para o toggle `E' (filter stack)
  ;; Predicados antes de extensões: diretórios primeiro (navegação),
  ;; depois arquivos recentes (order = primeira correspondência vence).
  (dirvish-emerge-groups
   '(("Directories"  (predicate . directories))
     ("Recent files" (predicate . recent-files-2h))
     ("Documents"    (extensions "pdf" "tex" "bib" "epub"))
     ("Video"        (extensions "mp4" "mkv" "webm"))
     ("Pictures"     (extensions "jpg" "png" "svg" "gif"))
     ("Audio"        (extensions "mp3" "flac" "wav" "ape" "aac"))
     ("Archives"     (extensions "gz" "rar" "zip"))))
  ;; Peek: preview de arquivos no minibuffer com debounce (evita flicker)
  (dirvish-peek-key (list :debounce 0.5 'any))
  :bind
  (:map dirvish-mode-map
   (";"   . dired-up-directory)
   ("?"   . dirvish-dispatch)
   ("TAB" . dirvish-subtree-toggle)
   ("o"   . dirvish-quick-access)
   ("r"   . dirvish-history-jump)
   ("s"   . dirvish-quicksort)
   ("v"   . dirvish-vc-menu)
   ("E"   . dirvish-emerge-mode)
   ("S"   . dirvish-ls-switches-menu)
   ("N"   . dirvish-narrow)
   ("["   . +carlos/dirvish-emerge-previous-group)
   ("]"   . +carlos/dirvish-emerge-next-group))
  :config
  ;; Preview no minibuffer (vertico) com dirvish
  (dirvish-peek-mode 1)
  ;; Sidebar segue o buffer selecionado (modo global)
  (dirvish-side-follow-mode 1)
  ;; `dirvish-directory-view-mode' deriva de special-mode, não de dired-mode,
  ;; então `dired-mode-hook' não dispara em buffers dirvish.
  (add-hook 'dirvish-directory-view-mode-hook
            (lambda () (display-line-numbers-mode -1)))
  ;; Dired-x / Omit mode (oculta dotfiles, autosaves e backups)
  (with-eval-after-load 'dired
    (require 'dired-x)
    (setq dired-omit-files "^\\.?#\\|^\\.\\.?$\\|^\\..*$\\|~+$"
          dired-omit-verbose nil))
  (add-hook 'dirvish-setup-hook
            (lambda () (dired-omit-mode 1))))

;; ── ibuffer (built-in) ──────────────────────────────────────────────
(use-package ibuffer
  :ensure nil
  :bind
  (("C-x C-b" . ibuffer))
  :config
  (setq ibuffer-sorting-mode 'alphabetic
        ibuffer-expert t))

;; ── TRAMP optimization ──────────────────────────────────────────────
;; Nota: no tramp-ssh-controlmaster-options, os símbolos de porcentagem (%)
;; devem ser escapados como `%%' porque a string é processada pelo `format-spec'
(setq tramp-default-method "ssh"
      tramp-ssh-controlmaster-options
      "-o ControlMaster=auto -o ControlPath='~/.ssh/controlmasters/%%r@%%h:%%p' -o ControlPersist=600"
      tramp-use-connection-share t
      remote-file-name-inhibit-cache nil
      tramp-verbose 1
      tramp-chunksize 8192)

;; Ignorar verificação de VC em caminhos TRAMP para evitar travamentos remotos
(setq vc-ignore-dir-regexp
      (format "\\(%s\\)\\|\\(%s\\)"
              vc-ignore-dir-regexp
              tramp-file-name-regexp))

;; Ensure controlmasters directory exists
(let ((cm-dir (expand-file-name "~/.ssh/controlmasters")))
  (unless (file-directory-p cm-dir)
    (make-directory cm-dir t)))

(with-eval-after-load 'tramp
  (when (fboundp 'connection-local-set-profile-variables)
    (connection-local-set-profile-variables
     'remote-direct-async-process
     '((tramp-direct-async-process . t)))
    (connection-local-set-profiles
     '(:application tramp :protocol "ssh")
     'remote-direct-async-process)))

;; ── recentf filtering ───────────────────────────────────────────────
(with-eval-after-load 'recentf
  (setq recentf-exclude
        '("^/tmp/"
          "^/var/folders/"
          "\\.git/"
          "\\.devenv/"
          "\\.direnv/"
          "\\.cache/"
          "elpaca/"
          "recentf$"
          "bookmarks$"
          "custom-file\\.el$")))

;; ── Project (built-in) ──────────────────────────────────────────────
(declare-function project-remember-projects-under "project")

(defun +carlos/project-register-user-workspaces ()
  "Auto-discover and register active user workspace roots."
  (interactive)
  (when (fboundp 'project-remember-projects-under)
    (dolist (dir '("~/Projects/42rio/CommonCore"
                   "~/Projects/HUPE/intranet-desit"
                   "~/Projects/SIGER/V1"
                   "~/Projetos/Github/MyEmacs"
                   "~/Projetos/Nixos/MyMachine"))
      (let ((expanded (expand-file-name dir)))
        (when (file-directory-p expanded)
          (ignore-errors (project-remember-projects-under expanded)))))))

(use-package project
  :ensure nil
  :config
  ;; Excluir diretórios de cache/ambientes virtuais da varredura do project.el e vc
  (dolist (dir '(".devenv" ".direnv" ".venv" ".cache" "node_modules" "build" "dist"))
    (add-to-list 'vc-directory-exclusion-list dir))
  (setq project-switch-commands
        '((?f project-find-file "Find file")
          (?g project-find-regexp "Find regexp")
          (?d project-dired "Dired")
          (?e project-eshell "Eshell")
          (?c project-compile "Compile")
          (?j +carlos/project-just-run "Just (default)")
          (?t +carlos/eat-just-recipe "Just recipe")))
  (+carlos/project-register-user-workspaces))

;; ── rfc-mode (Normas IETF) ───────────────────────────────────────────
(use-package rfc-mode
  :ensure t
  :custom
  (rfc-mode-directory (expand-file-name "rfc" user-emacs-directory)))

(provide 'custom-files)
;;; custom-files.el ends here
