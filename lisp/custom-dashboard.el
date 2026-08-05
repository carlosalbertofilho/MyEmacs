;;; custom-dashboard.el --- Dashboard estilo Nano Emacs -*- lexical-binding: t; -*-

;;; Commentary:
;; Dashboard minimalista inspirado no nano-emacs (Nicolas Rougier).
;; - Splash screen com fade-out ao iniciar
;; - Dashboard buffer com quick actions, recent files, projects, agenda
;; - Zero dependências extras (usa recentf, project.el nativos)
;; - Keyboard-first, mouse opcional
;;
;; Uso:
;;   (require 'custom-dashboard)
;;   (+carlos/dashboard-setup-startup-hook)

;;; Code:

(require 'subr-x)
(require 'cl-lib)
(require 'recentf)
(require 'project)

;; Forward declarations for byte-compiler
(defvar org-agenda-files)
(declare-function org-agenda-get-day-entries "org-agenda")
(declare-function gptel "gptel")

;; ── Fontes ──────────────────────────────────────────────────────────
(defvar +carlos/dashboard-font-title "Space Grotesk"
  "Fonte para títulos do dashboard.")

(defvar +carlos/dashboard-font-body "Inter"
  "Fonte para corpo do dashboard.")

(defun +carlos/dashboard-font-available-p (font-name)
  "Verifica se FONT-NAME está instalada no sistema."
  (member font-name (font-family-list)))

(defun +carlos/dashboard-font-face (family &optional height weight)
  "Retorna plist de face com FAMILY, HEIGHT e WEIGHT."
  (let ((font (if (+carlos/dashboard-font-available-p family)
                  family
                "JetBrainsMono Nerd Font")))
    (append (list :family font)
            (when height (list :height height))
            (when weight (list :weight weight)))))

;; ── Faces ───────────────────────────────────────────────────────────
(defface +carlos/dashboard-title
  `((t :inherit bold
       ,@(+carlos/dashboard-font-face +carlos/dashboard-font-title 2.0 'bold)))
  "Face for dashboard title."
  :group 'dashboard)

(defface +carlos/dashboard-subtitle
  `((t :inherit shadow
       ,@(+carlos/dashboard-font-face +carlos/dashboard-font-body 1.2 'normal)))
  "Face for dashboard subtitle."
  :group 'dashboard)

(defface +carlos/dashboard-heading
  `((t :inherit bold
       ,@(+carlos/dashboard-font-face +carlos/dashboard-font-title 1.3 'semibold)))
  "Face for section headings."
  :group 'dashboard)

(defface +carlos/dashboard-key
  `((t :inherit font-lock-keyword-face
       ,@(+carlos/dashboard-font-face +carlos/dashboard-font-body 1.1 'bold)))
  "Face for shortcut keys."
  :group 'dashboard)

(defface +carlos/dashboard-separator
  `((t :inherit shadow
       ,@(+carlos/dashboard-font-face +carlos/dashboard-font-body 0.8 'light)))
  "Face for separator lines."
  :group 'dashboard)

(defface +carlos/dashboard-footer
  `((t :inherit shadow
       ,@(+carlos/dashboard-font-face +carlos/dashboard-font-body 1.1 'normal)))
  "Face for footer text."
  :group 'dashboard)

(defface +carlos/dashboard-body
  `((t :inherit default
       ,@(+carlos/dashboard-font-face +carlos/dashboard-font-body 1.4 'normal)))
  "Face for dashboard body text."
  :group 'dashboard)

;; ── Configurações ───────────────────────────────────────────────────
(defcustom +carlos/dashboard-banner-title "MyEmacs"
  "Título exibido no dashboard."
  :type 'string
  :group 'dashboard)

(defcustom +carlos/dashboard-max-recent 8
  "Número máximo de arquivos recentes exibidos."
  :type 'integer
  :group 'dashboard)

(defcustom +carlos/dashboard-max-projects 5
  "Número máximo de projetos exibidos."
  :type 'integer
  :group 'dashboard)

(defcustom +carlos/dashboard-max-agenda 5
  "Número máximo de itens de agenda exibidos."
  :type 'integer
  :group 'dashboard)

(defcustom +carlos/dashboard-show-splash t
  "Se non-nil, mostra splash screen ao iniciar."
  :type 'boolean
  :group 'dashboard)

(defcustom +carlos/dashboard-splash-timeout 0.5
  "Tempo em segundos antes do fade-out do splash."
  :type 'number
  :group 'dashboard)

(defconst +carlos/dashboard-version "1.0.0"
  "Versão do dashboard.")

;; ── Helpers ─────────────────────────────────────────────────────────
(defun +carlos/dashboard-center-string (str)
  "Centraliza STR na largura da janela."
  (let* ((width (window-body-width))
         (pad (max 0 (/ (- width (length str)) 2))))
    (concat (make-string pad ?\s) str)))

(defun +carlos/dashboard-insert-button (key label action &optional face)
  "Insere botão com KEY, LABEL e ACTION.
FACE é a face do texto (default: link)."
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] action)
    (define-key map (kbd "RET") action)
    (insert "  ")
    (insert (propertize (format "[%s]" key)
                        'face (or face '+carlos/dashboard-key)
                        'mouse-face 'highlight
                        'help-echo label
                        'keymap map
                        'follow-link t))
    (insert (propertize (format " %s" label)
                        'face 'default
                        'mouse-face 'highlight
                        'keymap map
                        'follow-link t))))

(defun +carlos/dashboard-insert-heading (icon title shortcut)
  "Insere heading com ICON, TITLE e SHORTCUT."
  (insert "\n")
  (insert (propertize (format " %s %s" icon title)
                      'face '+carlos/dashboard-heading))
  (insert (propertize (format " [%s]" shortcut)
                      'face '+carlos/dashboard-key))
  (insert "\n"))

(defun +carlos/dashboard-separator ()
  "Insere linha separadora dinâmica."
  (let ((width (max 40 (window-body-width))))
    (insert (propertize (make-string width ?─)
                        'face '+carlos/dashboard-separator))
    (insert "\n")))

(defun +carlos/dashboard-uptime ()
  "Retorna string com uptime do Emacs."
  (let ((seconds (floor (float-time (time-since before-init-time)))))
    (cond
     ((< seconds 60) (format "%ds" seconds))
     ((< seconds 3600) (format "%dm" (/ seconds 60)))
     (t (format "%dh %dm" (/ seconds 3600) (% (/ seconds 60) 60))))))

(defun +carlos/dashboard-refresh-on-resize ()
  "Rebuild dashboard on window resize."
  (when (get-buffer +carlos/dashboard-buffer-name)
    (with-current-buffer +carlos/dashboard-buffer-name
      (when (eq major-mode 'fundamental-mode)
        (+carlos/dashboard-build)))))

;; ── Splash Screen ───────────────────────────────────────────────────
(defun +carlos/dashboard-splash ()
  "Mostra splash screen minimalista com fade-out."
  (interactive)
  (unless +carlos/dashboard-show-splash
    (cl-return-from +carlos/dashboard-splash))

  ;; Não mostra se há buffers com arquivo associado
  (when (cl-some #'buffer-file-name (buffer-list))
    (cl-return-from +carlos/dashboard-splash))

  (let* ((splash-buffer (get-buffer-create "*splash*"))
         (height (round (window-body-height)))
         (padding-center (max 1 (/ (- height 4) 2))))

    (with-current-buffer splash-buffer
      (erase-buffer)
      (setq mode-line-format nil)
      (setq header-line-format nil)
      (setq cursor-type nil)
      (setq line-spacing 0)
      (setq vertical-scroll-bar nil)
      (setq horizontal-scroll-bar nil)
      (setq fill-column (window-body-width))

      ;; Padding vertical para centralizar
      (insert-char ?\n padding-center)

      ;; Título
      (insert (propertize +carlos/dashboard-banner-title
                          'face '+carlos/dashboard-title))
      (insert "\n")

      ;; Subtítulo
      (let ((subtitle (format "Emacs %s · Dashboard %s · %s"
                              emacs-version
                              +carlos/dashboard-version
                              (format-time-string "%Y-%m-%d"))))
        (insert (propertize subtitle
                            'face '+carlos/dashboard-subtitle)))
      (insert "\n\n")

      ;; Dica
      (insert (propertize "Press any key or wait to dismiss"
                          'face 'shadow))

      (goto-char (point-min))
      (read-only-mode 1)

      ;; Qualquer tecla fecha
      (local-set-key [t] '+carlos/dashboard-splash-kill)

      (display-buffer-same-window splash-buffer nil)
      (run-with-idle-timer 0.05 nil (lambda () (message nil)))

      ;; Fade-out após timeout
      (when (fboundp 'mac-start-animation)
        (run-with-idle-timer +carlos/dashboard-splash-timeout nil
                             '+carlos/dashboard-splash-fade-out)
        (run-with-idle-timer (+ +carlos/dashboard-splash-timeout 0.1) nil
                             '+carlos/dashboard-splash-kill)))))

(defun +carlos/dashboard-splash-fade-out ()
  "Fade-out animation (macOS only)."
  (when (and (display-graphic-p) (fboundp 'mac-start-animation))
    (mac-start-animation nil :type 'fade-out :duration 0.5)))

(defun +carlos/dashboard-splash-kill ()
  "Fecha o splash screen imediatamente."
  (interactive)
  (when (get-buffer "*splash*")
    (cancel-function-timers '+carlos/dashboard-splash-fade-out)
    (kill-buffer "*splash*")))

;; ── Dashboard Buffer ────────────────────────────────────────────────
(defvar +carlos/dashboard-buffer-name "*dashboard*"
  "Nome do buffer do dashboard.")

(defvar +carlos/dashboard-sections nil
  "Lista de marcadores de seção para navegação cíclica.")

(defun +carlos/dashboard-insert-header ()
  "Insere header do dashboard."
  (insert "\n")
  (insert (propertize (+carlos/dashboard-center-string +carlos/dashboard-banner-title)
                      'face '+carlos/dashboard-title))
  (insert "\n")
  (let ((subtitle (format "Emacs %s · Dashboard %s · %s"
                          emacs-version
                          +carlos/dashboard-version
                          (format-time-string "%Y-%m-%d %H:%M"))))
    (insert (propertize (+carlos/dashboard-center-string subtitle)
                        'face '+carlos/dashboard-subtitle)))
  (insert "\n\n"))

(defun +carlos/dashboard-insert-quick-actions ()
  "Insere seção de ações rápidas."
  (+carlos/dashboard-insert-heading "⚡" "Quick Actions" "q")
  (insert "\n")

  ;; Use consult-find as fallback if consult-fzf is not installed
  (let ((find-cmd (if (fboundp 'consult-fzf) #'consult-fzf #'consult-find)))
    (+carlos/dashboard-insert-button "f" "Find File"
                                     (lambda () (interactive) (call-interactively find-cmd))))
  (+carlos/dashboard-insert-button "p" "Projects"
                                   (lambda () (interactive) (call-interactively #'project-switch-project)))
  (+carlos/dashboard-insert-button "a" "Agenda"
                                   (lambda () (interactive) (call-interactively #'org-agenda)))
  (insert "\n")
  ;; Guard magit-status in case magit is not loaded
  (when (fboundp 'magit-status)
    (+carlos/dashboard-insert-button "g" "Magit"
                                     (lambda () (interactive) (call-interactively #'magit-status))))
  (+carlos/dashboard-insert-button "i" "AI Chat"
                                   (lambda () (interactive) (call-interactively #'gptel)))
  (+carlos/dashboard-insert-button "d" "Dirvish"
                                   (lambda () (interactive) (call-interactively #'dirvish)))
  (insert "\n"))

(defun +carlos/dashboard-insert-recent-files ()
  "Insere seção de arquivos recentes."
  (+carlos/dashboard-insert-heading "📄" "Recent Files" "r")
  (insert "\n")

  (if (and recentf-mode recentf-list)
      (let ((count 0))
        (dolist (file recentf-list)
          (when (< count +carlos/dashboard-max-recent)
            (let* ((name (file-name-nondirectory file))
                   (dir (file-name-directory file))
                   (map (make-sparse-keymap)))
              (define-key map [mouse-1] `(lambda () (interactive) (find-file ,file)))
              (define-key map (kbd "RET") `(lambda () (interactive) (find-file ,file)))
              (insert "  ")
              (insert (propertize name
                                  'face 'link
                                  'mouse-face 'highlight
                                  'help-echo file
                                  'keymap map
                                  'follow-link t))
              (insert (propertize (format "  %s" dir)
                                  'face 'shadow))
              (insert "\n")
              (cl-incf count)))))
    (insert (propertize "  No recent files yet. Open some files to get started."
                        'face 'shadow))
    (insert "\n"))
  (insert "\n"))

(defun +carlos/dashboard-insert-projects ()
  "Insere seção de projetos."
  (+carlos/dashboard-insert-heading "📁" "Projects" "p")
  (insert "\n")

  (let ((projects (project-known-project-roots)))
    (if projects
        (let ((count 0))
          (dolist (proj projects)
            (when (< count +carlos/dashboard-max-projects)
              (let* ((name (file-name-nondirectory (directory-file-name proj)))
                     (map (make-sparse-keymap)))
                (define-key map [mouse-1] `(lambda () (interactive) (project-switch-project ,proj)))
                (define-key map (kbd "RET") `(lambda () (interactive) (project-switch-project ,proj)))
                (insert "  ")
                (insert (propertize name
                                    'face 'link
                                    'mouse-face 'highlight
                                    'help-echo proj
                                    'keymap map
                                    'follow-link t))
                (insert "\n")
                (cl-incf count)))))
      (insert (propertize "  No projects registered yet. Use C-x p f to find a project."
                          'face 'shadow))
      (insert "\n"))
    (insert "\n")))

(defun +carlos/dashboard-insert-agenda ()
  "Insere seção de agenda de hoje."
  (+carlos/dashboard-insert-heading "📅" "Today's Agenda" "a")
  (insert "\n")

  (when (featurep 'org)
    (require 'org-agenda)
    (let* ((all-entries nil)
           (count 0))
      ;; Coleta entradas de todos os arquivos da agenda
      (dolist (file (or org-agenda-files nil))
        (when (and (stringp file) (file-exists-p file) (< count +carlos/dashboard-max-agenda))
          (let ((entries (org-agenda-get-day-entries file (current-time) :timestamp)))
            (dolist (entry entries)
              (when (< count +carlos/dashboard-max-agenda)
                (push entry all-entries)
                (cl-incf count))))))
      (if all-entries
          (dolist (entry (reverse all-entries))
            (let ((text (substring-no-properties (format "%s" entry))))
              (insert "  ")
              (insert (propertize (truncate-string-to-width text 70 nil nil t)
                                  'face 'default))
              (insert "\n")))
        (insert (propertize "  No agenda items for today. Press C-c a a to view agenda."
                            'face 'shadow))
        (insert "\n"))))
  (insert "\n"))

(defun +carlos/dashboard-insert-footer ()
  "Insere footer com atalhos."
  (+carlos/dashboard-separator)
  (insert "\n")
  (let ((footer (format "  [d] Dashboard  [f] File  [p] Project  [a] Agenda  [g] Magit  [i] AI  |  q: Quit  |  Uptime: %s"
                        (+carlos/dashboard-uptime))))
    (insert (propertize footer
                        'face '+carlos/dashboard-footer)))
  (insert "\n"))

(defun +carlos/dashboard-build ()
  "Constroi o buffer do dashboard."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (setq +carlos/dashboard-sections nil)

    (+carlos/dashboard-insert-header)
    (+carlos/dashboard-separator)
    (+carlos/dashboard-insert-quick-actions)
    (+carlos/dashboard-separator)
    (+carlos/dashboard-insert-recent-files)
    (+carlos/dashboard-insert-projects)
    (+carlos/dashboard-separator)
    (+carlos/dashboard-insert-agenda)
    (+carlos/dashboard-insert-footer)

    (goto-char (point-min))
    (read-only-mode 1)))

(defun +carlos/dashboard-open ()
  "Abre ou atualiza o dashboard."
  (interactive)
  (let ((buf (get-buffer-create +carlos/dashboard-buffer-name)))
    (with-current-buffer buf
      (+carlos/dashboard-build)
      (setq mode-line-format nil)
      (setq header-line-format nil)
      (setq cursor-type nil)

      ;; Keybindings locais
      (local-set-key (kbd "q") '+carlos/dashboard-kill)
      (local-set-key (kbd "C-g") '+carlos/dashboard-kill)
      (local-set-key (kbd "r") '+carlos/dashboard-refresh)
      (local-set-key (kbd "TAB") '+carlos/dashboard-next-section)
      (local-set-key (kbd "<backtab>") '+carlos/dashboard-prev-section)
      ;; Use consult-find as fallback if consult-fzf is not installed
      (let ((find-cmd (if (fboundp 'consult-fzf) #'consult-fzf #'consult-find)))
        (local-set-key (kbd "f") (lambda () (interactive) (call-interactively find-cmd))))
      (local-set-key (kbd "p") (lambda () (interactive) (call-interactively #'project-switch-project)))
      (local-set-key (kbd "a") (lambda () (interactive) (call-interactively #'org-agenda)))
      ;; Guard magit-status in case magit is not loaded
      (when (fboundp 'magit-status)
        (local-set-key (kbd "g") (lambda () (interactive) (call-interactively #'magit-status))))
      (local-set-key (kbd "i") (lambda () (interactive) (call-interactively #'gptel)))
      (local-set-key (kbd "d") (lambda () (interactive) (call-interactively #'dirvish))))

    (switch-to-buffer buf)
    (setq-local window-size-fixed nil)))

(defun +carlos/dashboard-refresh ()
  "Atualiza o dashboard."
  (interactive)
  (when (get-buffer +carlos/dashboard-buffer-name)
    (with-current-buffer +carlos/dashboard-buffer-name
      (+carlos/dashboard-build))))

(defun +carlos/dashboard-kill ()
  "Fecha o dashboard."
  (interactive)
  (when (get-buffer +carlos/dashboard-buffer-name)
    (kill-buffer +carlos/dashboard-buffer-name)))

(defun +carlos/dashboard-next-section ()
  "Pula para a próxima seção."
  (interactive)
  (when (re-search-forward "^ \\[.*\\] " nil t)
    (beginning-of-line)))

(defun +carlos/dashboard-prev-section ()
  "Pula para a seção anterior."
  (interactive)
  (when (re-search-backward "^ \\[.*\\] " nil t)
    (beginning-of-line)))

;; ── Setup Hooks ─────────────────────────────────────────────────────
(defun +carlos/dashboard-setup-startup-hook ()
  "Configura o dashboard para aparecer no startup."
  ;; Inibe splash padrão do Emacs
  (setq inhibit-startup-screen t
        inhibit-startup-message t)

  ;; Mostra splash screen (opcional)
  (when +carlos/dashboard-show-splash
    (add-hook 'window-setup-hook #'+carlos/dashboard-splash))

  ;; Dashboard como buffer inicial (skip in batch mode)
  (unless noninteractive
    ;; Use a function that creates/returns the dashboard buffer
    (setq initial-buffer-choice
          (lambda ()
            (or (get-buffer +carlos/dashboard-buffer-name)
                (+carlos/dashboard-open)))))

  ;; Dashboard em novos frames (emacsclient)
  (add-hook 'server-after-make-frame-hook #'+carlos/dashboard-open)

  ;; Garante recentf ativo
  (unless recentf-mode
    (recentf-mode 1)))

(provide 'custom-dashboard)
;;; custom-dashboard.el ends here
