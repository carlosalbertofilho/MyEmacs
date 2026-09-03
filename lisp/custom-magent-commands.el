;;; custom-magent-commands.el --- Magent comandos: slash, workdir e FinOps -*- lexical-binding: t; -*-

;;; Commentary:
;; Comandos de usuário do Magent: slash commands (/set-workdir, /add-dir,
;; /list-dirs, /usage), gerenciamento de diretório de trabalho e relatório
;; FinOps de consumo de tokens/custo.

;;; Code:

(defvar magent-skill-directories)
(declare-function +carlos/gptel-tracker-file "custom-ai")

;; ── Slash Commands & Directory Context Scope ──────────────────────
(defvar +carlos/magent-extra-directories nil
  "Lista de diretórios adicionais incluídos no contexto do Magent.")

(defun +carlos/magent-set-workdir (dir)
  "Define DIR como o novo diretório de trabalho base da sessão do Magent."
  (interactive "DSelecione o novo diretório de trabalho: ")
  (let ((expanded (expand-file-name dir)))
    (if (not (file-directory-p expanded))
        (message "Magent: Diretório inválido: %s" expanded)
      (setq default-directory (file-name-as-directory expanded))
      (message "Magent Workdir alterado para: %s" default-directory))))

(defun +carlos/magent-add-dir (dir)
  "Adiciona DIR como diretório adicional ao contexto da sessão do Magent."
  (interactive "DSelecione o diretório para adicionar ao contexto: ")
  (let ((expanded (file-name-as-directory (expand-file-name dir))))
    (if (not (file-directory-p expanded))
        (message "Magent: Diretório inválido: %s" expanded)
      (add-to-list '+carlos/magent-extra-directories expanded)
      (let ((skills-path (expand-file-name "magent/skills" expanded)))
        (when (file-directory-p skills-path)
          (add-to-list 'magent-skill-directories skills-path)))
      (message "Magent: Diretório adicionado ao contexto: %s" expanded))))

(defun +carlos/magent-list-dirs ()
  "Exibe o diretório de trabalho atual e os diretórios extras no contexto."
  (interactive)
  (let ((workdir default-directory)
        (extras +carlos/magent-extra-directories))
    (message "Magent Workdir: %s | Extras: %s"
             workdir
             (if extras (string-join extras ", ") "Nenhum"))))

(defun +carlos/magent-render-usage-chat ()
  "Gera e exibe o relatório FinOps com barra de cota."
  (interactive)
  (require 'custom-ai)
  (let ((tracker-file (+carlos/gptel-tracker-file)))
    (if (not (file-exists-p tracker-file))
        (message "Magent: Nenhum registro de consumo encontrado ainda em %s" tracker-file)
      (let ((usage-hash (make-hash-table :test 'equal))
            (total-input 0)
            (total-output 0)
            (total-cost 0.0))
        (with-temp-buffer
          (insert-file-contents tracker-file)
          (goto-char (point-min))
          (while (not (eobp))
            (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
              (when (string-match-p "^[ \t]*|[ \t]*[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" line)
                (let* ((fields (mapcar #'string-trim (split-string line "|")))
                       (agent (if (>= (length fields) 4) (nth 3 fields) "Unknown"))
                       (input (if (>= (length fields) 7) (string-to-number (nth 6 fields)) 0))
                       (output (if (>= (length fields) 8) (string-to-number (nth 7 fields)) 0))
                       (cost-str (if (>= (length fields) 10) (nth 9 fields) "$0.00"))
                       (cost 0.0))
                  (when (string-match "\\$\\([0-9.]+\\)" cost-str)
                    (setq cost (string-to-number (match-string 1 cost-str))))
                  (let ((agent-data (gethash agent usage-hash (list 0 0 0.0))))
                    (setcar agent-data (+ (nth 0 agent-data) input))
                    (setcar (cdr agent-data) (+ (nth 1 agent-data) output))
                    (setcar (cddr agent-data) (+ (nth 2 agent-data) cost))
                    (puthash agent agent-data usage-hash))
                  (setq total-input (+ total-input input)
                        total-output (+ total-output output)
                        total-cost (+ total-cost cost)))))
            (forward-line 1)))
        (let* ((max-free-tokens 1000000)
               (used-tokens (+ total-input total-output))
               (pct (min 100 (/ (* used-tokens 100) max-free-tokens)))
               (filled-blocks (/ pct 10))
               (empty-blocks (- 10 filled-blocks))
               (bar (concat (make-string filled-blocks ?█) (make-string empty-blocks ?░)))
               (msg (format "📊 FinOps: [%s] %d%% (%dk/%dk tokens) | Custo: $%0.4f USD"
                            bar pct (/ used-tokens 1000) (/ max-free-tokens 1000) total-cost)))
          (message "%s" msg)
          msg)))))

(defun +carlos/magent-slash-interceptor (input)
  "Intercepta comandos barra em INPUT no prompt da sessão."
  (let ((cmd (string-trim (or input ""))))
    (cond
     ((string-match "^/set-workdir\\(?:\\s-+\\(.+\\)\\)?$" cmd)
      (let ((path (match-string 1 cmd)))
        (if (and path (not (string-empty-p path)))
            (+carlos/magent-set-workdir path)
          (call-interactively #'+carlos/magent-set-workdir)))
      t)
     ((string-match "^/add-dir\\(?:\\s-+\\(.+\\)\\)?$" cmd)
      (let ((path (match-string 1 cmd)))
        (if (and path (not (string-empty-p path)))
            (+carlos/magent-add-dir path)
          (call-interactively #'+carlos/magent-add-dir)))
      t)
     ((string-match "^/list-dir\\|/list-dirs\\|/dirs$" cmd)
      (+carlos/magent-list-dirs)
      t)
     ((string-match "^/usage$" cmd)
      (+carlos/magent-render-usage-chat)
      t)
     (t nil))))

;; Atalhos globais para os comandos de diretório e usage
(global-set-key (kbd "C-c M w") #'+carlos/magent-set-workdir)
(global-set-key (kbd "C-c M a") #'+carlos/magent-add-dir)
(global-set-key (kbd "C-c M L") #'+carlos/magent-list-dirs)

;; ── Transient Menu & Prompt Side-band (Fase 2) ──────────────────────

(require 'transient nil t)

(declare-function +carlos/magent-start "custom-magent")
(declare-function +carlos/magent-agent-shell-interrupt "custom-magent")
(declare-function +carlos/magent-agent-shell-prompt-region "custom-magent")

(when (fboundp 'transient-define-prefix)
  (transient-define-prefix +carlos/magent-menu ()
    "Menu de Controle e Operações do Magent."
    ["Magent Agent & Sessões"
     ("m" "Iniciar / Focar Magent" +carlos/magent-start)
     ("i" "Interromper Sessão Ativa" +carlos/magent-agent-shell-interrupt)
     ("r" "Enviar Região ao Magent" +carlos/magent-agent-shell-prompt-region)
     ("u" "Relatório FinOps / Consumo" +carlos/magent-render-usage-chat)]
    ["Gerenciamento de Diretórios & Contexto"
     ("w" "Definir Workdir Base" +carlos/magent-set-workdir)
     ("a" "Adicionar Diretório Extra" +carlos/magent-add-dir)
     ("l" "Listar Diretórios Ativos" +carlos/magent-list-dirs)]))

(defvar +carlos/magent-sideband-queue nil
  "Fila de mensagens do usuário recebidas enquanto o agente estava ocupado.")

(defun +carlos/magent-shell-maker-submit-around (orig-fn &rest args)
  "Intercepta submissões no `shell-maker' enquanto ocupado.
Se `shell-maker--busy' estiver ativo, captura o input do usuário sem lançar erro,
enfileira em `+carlos/magent-sideband-queue' e notifica o usuário no buffer."
  (if (and (bound-and-true-p shell-maker--busy)
           (not (plist-get args :input)))
      (let* ((input (buffer-substring-no-properties
                     (or (and (boundp 'comint-last-input-end) comint-last-input-end) (point-min))
                     (point-max)))
             (trimmed (and input (string-trim input))))
        (if (or (null trimmed) (string-empty-p trimmed))
            nil
          (setq +carlos/magent-sideband-queue (append +carlos/magent-sideband-queue (list trimmed)))
          (message "Magent: Mensagem lateral enfileirada: %s" trimmed)
          (when (member (downcase trimmed) '("abort" "stop" "/abort" "/stop" "cancel"))
            (when (fboundp '+carlos/magent-agent-shell-interrupt)
              (+carlos/magent-agent-shell-interrupt)))
          (delete-region (or (and (boundp 'comint-last-input-end) comint-last-input-end) (point-min))
                         (point-max))))
    (apply orig-fn args)))

(with-eval-after-load 'shell-maker
  (advice-add 'shell-maker-submit :around #'+carlos/magent-shell-maker-submit-around))

(provide 'custom-magent-commands)

;;; custom-magent-commands.el ends here
