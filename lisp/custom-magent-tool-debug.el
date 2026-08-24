;;; custom-magent-tool-debug.el --- Magent Tool for DAP (dape) -*- lexical-binding: t; -*-

;;; Commentary:
;; Ferramenta do Magent para orquestrar o depurador nativo via `dape`.
;; Permite ao agente iniciar sessões, colocar breakpoints e avaliar expressões.
;; (Faz parte da Fase 5: Onisciência do Agente)

;;; Code:

(require 'dape nil t)
(require 'custom-magent-infra)

;; Garantir fallback para projeto ao rodar em batch (solução parcial até a Fase 6)
(defun +carlos/--magent-debug-ensure-project-root ()
  "Retorna a raiz do projeto atual. Se em batch, tenta fallbacks."
  (or (and (fboundp 'project-root)
           (when-let* ((p (project-current)))
             (project-root p)))
      (and (fboundp 'vc-root-dir) (vc-root-dir))
      default-directory
      user-emacs-directory))

(defun +carlos/magent-tool-debug (action &optional arg1 arg2)
  "Orquestra o depurador dape para o Magent.
ACTION: `start', `stop', `breakpoint' (arg1=file, arg2=line), `eval'."
  (unless (featurep 'dape)
    (error "Pacote dape não está carregado. A depuração não está disponível"))
  
  (let ((root (+carlos/--magent-debug-ensure-project-root)))
    (pcase action
      ("start"
       ;; arg1 deve ser a config do dape (ex: 'python', 'go', 'node')
       (unless arg1 (error "É necessário informar a configuração do dape para iniciar"))
       (let ((default-directory root)
             (config (alist-get (intern arg1) dape-configs)))
         (unless config
           (error "Configuração dape '%s' não encontrada" arg1))
         (dape config)
         "Sessão de depuração iniciada."))
      
      ("stop"
       (dape-quit)
       "Sessão de depuração encerrada.")
      
      ("breakpoint"
       (unless (and arg1 arg2) (error "Para 'breakpoint' forneça arquivo e linha"))
       (let ((file (expand-file-name arg1 root))
             (line (if (stringp arg2) (string-to-number arg2) arg2)))
         (unless (file-exists-p file)
           (error "Arquivo %s não encontrado para breakpoint" file))
         (with-current-buffer (find-file-noselect file)
           (save-excursion
             (goto-char (point-min))
             (forward-line (1- line))
             (dape-breakpoint-toggle)
             (format "Breakpoint alternado em %s:%d" file line)))))
             
      ("eval"
       (unless arg1 (error "É necessário informar a expressão para avaliar"))
       (unless (dape--live-connection 'stopped)
         (error "O depurador precisa estar pausado para avaliar expressões"))
       (dape-evaluate-expression (dape--live-connection 'stopped) arg1)
       (format "Expressão avaliada no console. Verifique o buffer *dape-repl*."))
       
      (_ (error "Ação '%s' desconhecida em magent-tool-debug" action)))))

(with-eval-after-load 'gptel
  (when (fboundp '+carlos/magent-tool-debug)
    (setq gptel-tools
          (append gptel-tools
                  `((:name "magent_debug"
                     :tool ,#'+carlos/magent-tool-debug
                     :description "Orquestra o depurador nativo via dape. Use 'start' (arg1=config_name), 'stop', 'breakpoint' (arg1=filepath, arg2=line_number), ou 'eval' (arg1=expression)."
                     :category "debugging"))))))

(provide 'custom-magent-tool-debug)
;;; custom-magent-tool-debug.el ends here
