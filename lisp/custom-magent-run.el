;;; custom-magent-run.el --- Magent batch agent runner for CLI -*- lexical-binding: t; -*-

;;; Commentary:
;; Fornece +carlos/magent-run-execute — ponto de entrada UI-neutral para
;; rodar um agente Magent em batch (emacs --batch), capturando JSONL status
;; durante execução e JSON final como saída.
;;
;; Usado pelo bin/magent-cli run para testes com Granite local e
;; orquestração externa.

;;; Code:

(declare-function magent-approval-resolve-request "magent-approval")
(require 'cl-lib)
(require 'json)
(require 'custom-magent-infra)

;; ── Variáveis de sessão ─────────────────────────────────────────────

(defvar +carlos/magent-run--status-file nil
  "Caminho do arquivo JSONL de status da sessão run atual.")

(defvar +carlos/magent-run--sink-registered nil
  "Non-nil quando o sink JSONL está registrado.")

;; ── JSONL Sink ──────────────────────────────────────────────────────

(defun +carlos/magent-run--jsonl-sink (event)
  "Escreve EVENT como linha JSONL no status file.
Registrado via magent-lifecycle-events-add-sink."
  (when (and +carlos/magent-run--status-file
             (plist-get event :type))
    (condition-case _err
        (let* ((event-type (plist-get event :type))
               (entry (list :type (symbol-name event-type)
                            :time (plist-get event :time)))
               (extra (pcase event-type
                        ('turn-start
                         (list :turn-id (plist-get event :turn-id)))
                        ('turn-end
                         (list :turn-id (plist-get event :turn-id)
                               :status (symbol-name
                                        (or (plist-get event :status) 'unknown))))
                        ('tool-call-start
                         (list :tool-name (plist-get event :tool-name)
                               :call-id (plist-get event :call-id)))
                        ('tool-call-end
                         (list :tool-name (plist-get event :tool-name)
                               :call-id (plist-get event :call-id)
                               :status (symbol-name
                                        (or (plist-get event :status) 'unknown))))
                        ('llm-request-start
                         (list :backend (plist-get event :backend)
                               :model (plist-get event :model)))
                        ('llm-request-end
                         (list :backend (plist-get event :backend)
                               :model (plist-get event :model)
                               :status (symbol-name
                                        (or (plist-get event :status) 'unknown))))
                        (_ nil))))
          (when extra
            (setq entry (append entry extra)))
          (with-temp-buffer
            (insert (json-encode entry) "\n")
            (append-to-file (point-min) (point-max)
                            +carlos/magent-run--status-file)))
      (error nil))))

(defun +carlos/magent-run--register-sink ()
  "Registra o JSONL sink nos lifecycle events."
  (unless +carlos/magent-run--sink-registered
    (when (fboundp 'magent-lifecycle-events-add-sink)
      (magent-lifecycle-events-add-sink #'+carlos/magent-run--jsonl-sink)
      (setq +carlos/magent-run--sink-registered t))))

(defun +carlos/magent-run--unregister-sink ()
  "Remove o JSONL sink dos lifecycle events."
  (when (and +carlos/magent-run--sink-registered
             (fboundp 'magent-lifecycle-events-remove-sink))
    (magent-lifecycle-events-remove-sink #'+carlos/magent-run--jsonl-sink)
    (setq +carlos/magent-run--sink-registered nil)))

;; ── Resolução de modelo ────────────────────────────────────────────

(defun +carlos/magent-run--resolve-model (profile model-str)
  "Resolu o modelo para o run.
PROFILE: string nome do profile (ex: \"coder\") ou nil.
MODEL-STR: string \"backend/model\" ou \"model\" ou nil.
Retorna plist (:backend-obj :model-symbol :backend-name :model-name)."
  (let* ((hints (when profile
                  (let ((entry (assoc profile +carlos/magent-subagent-profiles)))
                    (when entry (cdr entry)))))
         (min-tier (or (plist-get hints :min-tier) "free"))
         (preferred-backend (plist-get hints :preferred-backend)))
    (if model-str
        ;; Modelo explícito: parse "backend/model" ou "model"
        (let* ((parts (split-string model-str "/" t))
               (backend-name (if (= 1 (length parts))
                                 (or preferred-backend "Ollama Local")
                               (car parts)))
               (model-name (if (= 1 (length parts))
                               (car parts)
                             (string-join (cdr parts) "/")))
               (backend-obj (condition-case _err
                                (when (fboundp 'gptel-get-backend)
                                  (gptel-get-backend backend-name))
                              (error nil))))
          (list :backend-obj backend-obj
                :model-symbol (intern model-name)
                :backend-name backend-name
                :model-name model-name))
      ;; Sem modelo explícito: resolver via perfil
      (when (fboundp '+carlos/magent-resolve-model)
        (let* ((resolved (+carlos/magent-resolve-model
                          'simple nil nil nil
                          (list :min-tier min-tier
                                :preferred-backend preferred-backend)))
               (backend-name (plist-get resolved :backend))
               (model-name (plist-get resolved :model))
               (backend-obj (condition-case _err
                                (when (and backend-name (fboundp 'gptel-get-backend))
                                  (gptel-get-backend backend-name))
                              (error nil))))
          (list :backend-obj backend-obj
                :model-symbol (intern (or model-name "gptel-default"))
                :backend-name backend-name
                :model-name model-name))))))

;; ── Restrição de tools por profile ──────────────────────────────────

(defcustom +carlos/magent-run-profile-tools
  '(("explore"     . (read))
    ("general"     . nil)
    ("coder"       . nil)
    ("sysadmin"    . (read))
    ("planner"     . (read))
    ("tech-writer" . (read))
    ("auditor"     . (read))
    ("sec-ops"     . (read))
    ("qa"          . (read)))
  "Alista profile -> lista de tools PERMITIDAS (nil = todas).
Tools listadas são as ÚNICAS disponíveis. Nil herda o default do magent."
  :type '(alist :key-type string :value-type (choice (const nil) (repeat symbol)))
  :group 'magent)

;; ── Execução principal ──────────────────────────────────────────────

(cl-defun +carlos/magent-run-execute (prompt &key model profile status-file
                                              output-file timeout)
  "Executa um agente Magent em batch com PROMPT.
MODEL: string tipo \"ollama/granite4.1:1b\" ou nil (usa profile default).
PROFILE: nome do profile (\"coder\", \"explore\", etc.) ou nil (\"general\").
STATUS_FILE: caminho para JSONL log (criado automaticamente se nil).
OUTPUT_FILE: caminho para JSON final de saída.
TIMEOUT: segundos antes de abortar (default 120).
Retorna JSON string com status, model, result, metrics, duration."
  (let* ((start-time (float-time))
         (profile (or profile "general"))
         (timeout (or timeout 120))
         (status-file (or status-file
                          (make-temp-file "magent-run-status-" nil ".jsonl")))
         (output-file (or output-file
                          (make-temp-file "magent-run-output-" nil ".json")))
         (done nil)
         (final-status 'timeout)
         (final-result nil)
         (final-error nil)
         (tools-called '())
         (turn-count 0))

    ;; Configurar variáveis de sessão
    (setq +carlos/magent-run--status-file status-file)

    ;; Garantir que magent está inicializado
    (when (fboundp 'magent-runtime-ensure-initialized)
      (magent-runtime-ensure-initialized))

    ;; Resolver modelo
    (let* ((model-info (+carlos/magent-run--resolve-model profile model))
           (backend-obj (plist-get model-info :backend-obj))
           (model-symbol (plist-get model-info :model-symbol))
           (backend-name (plist-get model-info :backend-name))
           (model-name (plist-get model-info :model-name)))

      ;; Configurar gptel globalmente
      (when backend-obj
        (setq gptel-backend backend-obj))
      (when model-symbol
        (setq gptel-model model-symbol))

      ;; Registrar JSONL sink
      (+carlos/magent-run--register-sink)

      ;; Observer para capturar eventos
      (let ((observer (lambda (event)
                        (pcase (plist-get event :type)
                          ('tool-call-start
                           (push (plist-get event :tool-name) tools-called))
                          ('turn-start
                           (cl-incf turn-count))
                          ('llm-request-end
                           (when (eq (plist-get event :status) 'failed)
                             (setq final-error
                                   (or (plist-get event :error)
                                       (format "LLM request failed: %s/%s"
                                               backend-name model-name)))))))))

        ;; Criar sessão e submeter
        (condition-case err
            (let* ((scope (when (fboundp 'magent-session-scope-from-directory)
                            (magent-session-scope-from-directory
                             (+carlos/magent-project-root))))
                   (runtime-session (when (fboundp 'magent-runtime-session-new)
                                      (magent-runtime-session-new scope))))

              ;; Configurar agente do profile com override de modelo
              (when (and runtime-session
                         (fboundp 'magent-runtime-session-set-agent))
                (when (and backend-name model-name)
                  (require 'custom-magent-subagent)
                  (add-to-list '+carlos/magent-subagent-model-overrides
                               (cons profile (cons backend-name model-name))))
                (magent-runtime-session-set-agent runtime-session profile))

              ;; Submeter prompt
              (when (and runtime-session (fboundp 'magent-runtime-submit))
                (magent-runtime-submit
                 runtime-session
                 prompt
                 :observer observer
                 :approval-provider
                 (lambda (request)
                   (magent-approval-resolve-request (plist-get request :request-id) 'allow-once))
                 :on-complete
                 (lambda (status result)
                   (setq final-status status
                         final-result result
                         done t))))

              ;; Bloquear até completar ou timeout
              (let ((deadline (+ start-time timeout)))
                (while (and (not done)
                            (< (float-time) deadline))
                  (accept-process-output nil 0.1))

                (unless done
                  (setq final-status 'timeout
                        final-result ""
                        final-error (format "Timeout after %ss" timeout))
                  (mapc #'delete-process (process-list))))

              ;; Reset FSM
              (when (fboundp '+carlos/magent-fsm-reset)
                (+carlos/magent-fsm-reset)))

          (error (setq final-status 'error
                       final-error (error-message-string err))))

      ;; Remover sink
      (+carlos/magent-run--unregister-sink)

      ;; Extrair resultado
      (let* ((result-text (when (and final-result
                                     (fboundp 'magent-execution-result-content-string))
                            (magent-execution-result-content-string final-result)))
             (duration-ms (round (* 1000 (- (float-time) start-time))))
             (output (list :status (symbol-name final-status)
                           :model (list :name model-name
                                        :backend backend-name
                                        :tier (or (plist-get
                                                   (cdr (assoc profile
                                                               +carlos/magent-subagent-profiles))
                                                   :min-tier)
                                                  "free"))
                           :profile profile
                           :prompt prompt
                           :result (or result-text "")
                           :metrics (list :turns turn-count
                                          :tools_called (nreverse tools-called))
                           :duration_ms duration-ms
                           :errors (if final-error (list final-error) nil))))

        ;; Escrever JSON final
        (let ((json-encoding-pretty-print t))
          (with-temp-file output-file
            (insert (json-encode output))))

        ;; Imprimir na saída (stdout)
        (let ((json-encoding-pretty-print nil))
          (princ (json-encode output))))))))

(provide 'custom-magent-run)
;;; custom-magent-run.el ends here
