;;; magent-batch-test.el --- Batch magent→modelo test with *magent-log* tail -*- lexical-binding: t; -*-

;;; Commentary:
;; Simula uma chamada do Magent ao modelo local via API do agent-shell em
;; batch, escutando o buffer *magent-log* até o shell ficar idle ou dar
;; timeout. Útil para:
;;   - avaliar modelos locais (MLX em agnes.local:8081, Ollama em aa102-006l);
;;   - reproduzir/validar a FSM (THINK/DECIDE/RETRY) sem abrir a GUI;
;;   - validar o sink do magent-log sem spam de "Buffer is read-only".
;;
;; Uso:
;;   MAGENT_SIM_MODEL=mlx-community/gemma-4-e2b-it-4bit \
;;     emacs --init-directory ~/.config/emacs --batch \
;;     -l ~/.config/emacs/init.el -l lisp/../bin/magent-batch-test.el
;;
;; Variáveis de ambiente:
;;   MAGENT_SIM_MODEL   modelo a usar (default: o default local do host)
;;   MAGENT_SIM_BACKEND backend gptel a usar (default: o local do host)
;;   MAGENT_SIM_TIMEOUT segundos de espera (default: 240)
;;   MAGENT_SIM_PROMPT  texto do prompt (default: análise do diretório)
;;
;; O log completo do *magent-log* é impresso no stdout ao final.

;;; Code:

(defvar magent-batch--last-pos 1)
(defvar magent-batch--start-time nil)
(defvar magent-batch--timeout 240)
(defvar magent-batch--done nil)

(defun magent-batch--log-buffer ()
  "Return live *magent-log* buffer."
  (or (get-buffer "*magent-log*")
      (get-buffer-create "*magent-log*")))

(defun magent-batch--print-new-log ()
  "Print lines appended to the log buffer since last poll."
  (let ((buf (magent-batch--log-buffer)))
    (with-current-buffer buf
      (when (> (point-max) magent-batch--last-pos)
        (let ((chunk (buffer-substring-no-properties
                      magent-batch--last-pos (point-max))))
          (princ chunk)
          (setq magent-batch--last-pos (point-max)))))))

(defun magent-batch--busy-p ()
  "Non-nil while the Magent agent-shell is still busy."
  (let ((shells (magent-agent-shell--buffers)))
    (and shells
         (or (map-elt (with-current-buffer (car shells) agent-shell--state)
                      :active-requests)
             (with-current-buffer (car shells)
               (bound-and-true-p shell-maker--busy))))))

(defun magent-batch--poll ()
  "Poll loop: print new log lines until shell idle or timeout."
  (if (or magent-batch--done
          (null magent-batch--start-time))
      nil
    (magent-batch--print-new-log)
    (if (not (magent-batch--busy-p))
        (progn
          (setq magent-batch--done t)
          (princ (format "\n>>> SHELL IDLE after %.1fs\n"
                         (float-time (time-subtract
                                      (current-time) magent-batch--start-time)))))
      (if (> (float-time (time-subtract (current-time) magent-batch--start-time))
             magent-batch--timeout)
          (progn
            (setq magent-batch--done t)
            (princ (format "\n>>> TIMEOUT after %ss\n" magent-batch--timeout)))
        (run-at-time 2 nil #'magent-batch--poll)))))

;; Main
(let* ((project-dir default-directory)
       (prompt (or (getenv "MAGENT_SIM_PROMPT")
                   "Analise o diretório do projeto atual e diga o que você entendeu, apontando para o MyEmacs"))
       (timeout (or (and (getenv "MAGENT_SIM_TIMEOUT")
                         (string-to-number (getenv "MAGENT_SIM_TIMEOUT")))
                    240))
       (sim-model (getenv "MAGENT_SIM_MODEL"))
       (sim-backend (getenv "MAGENT_SIM_BACKEND")))
  (setq magent-batch--timeout timeout)
  (require 'gptel)
  (require 'magent)
  (require 'magent-agent-shell)
  (let ((backend-name (or sim-backend
                          (and (fboundp '+carlos/ai-local-backend)
                               (car (+carlos/ai-local-backend))))))
    (when backend-name
      (if sim-model
          (progn
            (setq gptel-backend (gptel-get-backend backend-name)
                  gptel-model (intern sim-model))
            (when (boundp '+carlos/gptel-agent-backend)
              (setq +carlos/gptel-agent-backend backend-name
                    +carlos/gptel-agent-model (intern sim-model))))
        (setq gptel-backend (gptel-get-backend backend-name)
              gptel-model (cdr (+carlos/ai-local-backend))))))
  (unless gptel-backend
    (setq gptel-backend (or (gptel-get-backend "OpenAI")
                            (gptel-get-backend "Gemini")
                            (gptel-get-backend "Zen Claude")
                            (gptel-get-backend "Ollama Local")
                            (car gptel-backend-list))))
  (unless gptel-model
    (setq gptel-model (or "claude-sonnet-5" "qwen2.5-coder:3b")))
  (princ (format ">>> Magent batch em %s\n>>> Prompt: %s\n>>> Timeout: %ss\n>>> Modelo: %s\n"
                 project-dir prompt timeout (or sim-model gptel-model)))
  ;; Envia o prompt via API do magent
  (condition-case err
      (progn
        (magent-agent-shell-send-prompt prompt :no-focus t)
        (setq magent-batch--start-time (current-time))
        (run-at-time 2 nil #'magent-batch--poll)
        ;; processa timers/processos assíncronos
        (let ((deadline (+ (float-time) (+ timeout 30))))
          (while (and (not magent-batch--done)
                      (< (float-time) deadline))
            (magent-batch--print-new-log)
            (accept-process-output nil 1)
            (sit-for 0.1))))
      (error
       (princ (format "\n>>> ERRO ao enviar prompt: %S\n" err))))
  ;; flush final
  (magent-batch--print-new-log)
  (princ (format "\n>>> FIM. Log final (%d bytes):\n"
                 (with-current-buffer (magent-batch--log-buffer)
                   (point-max))))
  (with-current-buffer (magent-batch--log-buffer)
    (let ((inhibit-read-only t))
      (princ (buffer-string))))
  (kill-emacs 0))

;;; magent-batch-test.el ends here
