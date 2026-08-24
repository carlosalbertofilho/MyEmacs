;;; custom-magent-proxy.el --- Lifecycle management for agy-proxy -*- lexical-binding: t; -*-

;;; Commentary:
;; Gerencia o ciclo de vida do binário `bin/agy-proxy`.

;;; Code:

(defcustom custom-magent-proxy-command
  (expand-file-name "bin/agy-proxy" user-emacs-directory)
  "Caminho para o executável do proxy."
  :type 'string
  :group 'custom-magent)

(defcustom custom-magent-proxy-port 8088
  "Porta do proxy HTTP."
  :type 'integer
  :group 'custom-magent)

(defcustom custom-magent-config-dir
  (expand-file-name ".config/agy" "~")
  "Diretório de configuração do proxy."
  :type 'string
  :group 'custom-magent)

(defvar custom-magent-proxy--process nil
  "Handle do processo proxy.")

(defun custom-magent-proxy-start ()
  "Inicia o proxy como processo filho do Emacs."
  (interactive)
  (when (custom-magent-proxy-alive-p)
    (user-error "Proxy já está rodando"))
  (let ((process-environment
         (append
          (list (format "AGY_PROXY_PORT=%d" custom-magent-proxy-port)
                (format "AGY_CONFIG_DIR=%s" custom-magent-config-dir))
          process-environment)))
    (setq custom-magent-proxy--process
          (make-process
           :name "agy-proxy"
           :buffer "*agy-proxy*"
           :command (list custom-magent-proxy-command
                         "--port" (number-to-string custom-magent-proxy-port)
                         "--log-format" "json")
           :sentinel #'custom-magent-proxy--sentinel
           :noquery t))
    (custom-magent-proxy--wait-ready 5)
    (message "agy-proxy started on port %d" custom-magent-proxy-port)))

(defun custom-magent-proxy-alive-p ()
  "Retorna non-nil se o proxy está rodando."
  (and custom-magent-proxy--process
       (process-live-p custom-magent-proxy--process)))

(defun custom-magent-proxy-stop ()
  "Para o proxy graciosamente."
  (interactive)
  (when (custom-magent-proxy-alive-p)
    (signal-process custom-magent-proxy--process 'SIGTERM)
    (accept-process-output custom-magent-proxy--process 3)
    (unless (not (process-live-p custom-magent-proxy--process))
      (kill-process custom-magent-proxy--process))
    (setq custom-magent-proxy--process nil)
    (message "agy-proxy stopped")))

(defun custom-magent-proxy--sentinel (_process event)
  "Trata eventos do ciclo de vida do proxy."
  (cond
   ((string-match-p "finished" event)
    (message "agy-proxy exited normally"))
   ((string-match-p "\\(exit\\|signal\\)" event)
    (message "agy-proxy crashed: %s — restarting..." event)
    (run-with-timer 2 nil #'custom-magent-proxy-start))))

(defun custom-magent-proxy--wait-ready (timeout)
  "Espera o proxy responder no /health, com TIMEOUT segundos."
  (let ((deadline (+ (float-time) timeout))
        (ready nil))
    (while (and (not ready) (< (float-time) deadline))
      (condition-case nil
          (let ((response (url-retrieve-synchronously
                           (format "http://localhost:%d/health"
                                   custom-magent-proxy-port)
                           t nil 1)))
            (when response
              (setq ready t)
              (kill-buffer response)))
        (error (sleep-for 0.3))))
    (unless ready
      (error "agy-proxy failed to start within %d seconds" timeout))))

(provide 'custom-magent-proxy)
;;; custom-magent-proxy.el ends here
