;;; custom-magent-ui.el --- Magent UI: loop de eventos informativo (Fase C) -*- lexical-binding: t; -*-

;;; Commentary:
;; Painel de atividade do Magent (Fase C): torna o loop de eventos do chat
;; mais informativo, mostrando detalhes das ações dos modelos (tool calls,
;; reasoning) e o ciclo de vida dos subagentes.  Consome os lifecycle events
;; do Magent via sink (`magent-lifecycle-events-add-sink') e renderiza linhas
;; compactas timestampadas no buffer *Magent* (agent-shell), com faces
;; +carlos/magent-ui-*.  Sem modificar sources do elpaca: só sinks/advices.
;;
;; Eventos consumidos:
;;   turn-start / turn-end / llm-request-start / llm-request-end
;;   tool-call-start / tool-call-end
;;   subagent-start / subagent-stop / agent-job-event

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function magent-lifecycle-events-add-sink "magent-lifecycle-events")
(declare-function agent-shell-insert "agent-shell")
(declare-function magent-agent-shell--buffer "magent-agent-shell")

(defvar +carlos/magent-fsm-reasoning-buffer nil
  "Forward declaration: reasoning acumulado pela FSM (custom-magent-fsm.el).")

;; ── Faces ─────────────────────────────────────────────────────────
(defface +carlos/magent-ui-turn '((t (:inherit font-lock-keyword-face)))
  "Face para linhas de turno (badge de modelo e status).")

(defface +carlos/magent-ui-model '((t (:inherit font-lock-constant-face)))
  "Face para o badge de backend/modelo por turno.")

(defface +carlos/magent-ui-tool-ok '((t (:inherit font-lock-function-name-face)))
  "Face para tool calls concluídas com sucesso.")

(defface +carlos/magent-ui-tool-fail '((t (:inherit error)))
  "Face para tool calls que falharam.")

(defface +carlos/magent-ui-reasoning '((t (:inherit font-lock-comment-face)))
  "Face para reasoning colapsável.")

(defface +carlos/magent-ui-subagent '((t (:inherit font-lock-type-face)))
  "Face para eventos de subagente.")

(defface +carlos/magent-ui-time '((t (:inherit shadow)))
  "Face para timestamp/duração.")

;; ── Estado ────────────────────────────────────────────────────────
(defvar +carlos/magent-ui-turn-count 0
  "Contador de turnos renderizados pelo painel de atividade.")

(defvar +carlos/magent-ui-last-turn-model nil
  "Badge `(BACKEND . MODEL)' capturado no llm-request-start do turno atual.")

(defvar +carlos/magent-ui-turn-start-time nil
  "Timestamp (float-time) do início do turno atual.")

(defvar +carlos/magent-ui-reasoning-max-preview 400
  "Máximo de caracteres do preview de reasoning inserido no buffer.")

(defvar +carlos/magent-ui--tool-start-times (make-hash-table :test #'equal)
  "Hash call-id -> start-time para calcular duração de tool calls.")

(defvar +carlos/magent-ui-insert-enabled t
  "Quando nil, desativa a inserção no buffer *Magent* (útil em batch/testes).")

;; ── Helpers de renderização ───────────────────────────────────────
(defun +carlos/magent-ui--shell-buffer ()
  "Return the live Magent agent-shell buffer, or nil.
Never creates a new buffer — the UI sink is read-only."
  (when (and +carlos/magent-ui-insert-enabled
             (fboundp 'magent-agent-shell--buffer)
             (fboundp 'agent-shell-insert))
    (ignore-errors (magent-agent-shell--buffer t))))

(defun +carlos/magent-ui--insert (line face)
  "Insert LINE with FACE into the Magent shell buffer.
Falls back to `message' when no live Magent shell buffer exists."
  (let ((text (propertize line 'font-lock-face face)))
    (if-let* ((buffer (+carlos/magent-ui--shell-buffer)))
        (with-current-buffer buffer
          (condition-case nil
              (agent-shell-insert :text text :submit nil :shell-buffer buffer)
            (error
             (message "Magent UI: %s" text))))
      (message "Magent UI: %s" text))))

(defun +carlos/magent-ui--timestamp ()
  "Return a compact HH:MM:SS timestamp string."
  (format-time-string "%H:%M:%S"))

(defun +carlos/magent-ui--elapsed (start-time)
  "Return elapsed seconds since START-TIME, or nil."
  (when (numberp start-time)
    (let ((elapsed (- (float-time) start-time)))
      (format "%.1fs" (max 0.0 elapsed)))))

(defun +carlos/magent-ui--model-badge ()
  "Return the `[backend model]' badge string, or nil."
  (when-let* ((pair +carlos/magent-ui-last-turn-model)
              (backend (car pair))
              (model (cdr pair)))
    (format "[%s %s]" backend model)))

(defun +carlos/magent-ui--truncate (text max-width)
  "Truncate TEXT to MAX-WIDTH characters with an ellipsis."
  (when (stringp text)
    (truncate-string-to-width
     (string-trim text) max-width nil nil "...")))

;; ── C1: Sink de atividade ─────────────────────────────────────────
(defun +carlos/magent-ui-activity-sink (event)
  "Render EVENT plist as a compact activity line in the Magent buffer."
  (condition-case err
      (pcase (plist-get event :type)
        ('turn-start
         (setq +carlos/magent-ui-turn-start-time (float-time))
         (let ((title (or (plist-get event :title) "turn")))
           (+carlos/magent-ui--insert
            (format "[%s] %s · %s"
                    (+carlos/magent-ui--timestamp)
                    (propertize title 'face '+carlos/magent-ui-turn)
                    (or (+carlos/magent-ui--model-badge) "sem modelo"))
            '+carlos/magent-ui-turn)))
        ('llm-request-start
         (setq +carlos/magent-ui-last-turn-model
               (cons (or (plist-get event :backend) "?")
                     (or (plist-get event :model) "?"))))
        ('llm-request-end
         (when-let* ((start +carlos/magent-ui-turn-start-time))
           (let ((badge (or (+carlos/magent-ui--model-badge) "sem modelo"))
                 (status (plist-get event :status))
                 (elapsed (+carlos/magent-ui--elapsed start)))
             (+carlos/magent-ui--insert
              (format "[%s] %s %s · %s"
                      (+carlos/magent-ui--timestamp)
                      (if (eq status 'completed) "✓" "✗")
                      (propertize badge 'face '+carlos/magent-ui-model)
                      (or elapsed ""))
              (if (eq status 'completed)
                  '+carlos/magent-ui-turn
                '+carlos/magent-ui-tool-fail)))))
        ('turn-end
         (setq +carlos/magent-ui-turn-start-time nil
               +carlos/magent-ui-last-turn-model nil)
         (when-let* ((reasoning (and (boundp '+carlos/magent-fsm-reasoning-buffer)
                                     +carlos/magent-fsm-reasoning-buffer))
                     ((not (string-empty-p (string-trim reasoning)))))
           (let ((total (length reasoning))
                 (preview (truncate-string-to-width
                          (string-trim
                           (substring reasoning 0
                                      (min (length reasoning)
                                           +carlos/magent-ui-reasoning-max-preview)))
                          (+ +carlos/magent-ui-reasoning-max-preview 2) nil nil "…")))
             (+carlos/magent-ui--insert
              (format "[%s] 💭 reasoning · %d chars\n  %s"
                      (+carlos/magent-ui--timestamp)
                      total
                      (propertize (string-trim preview)
                                  'face '+carlos/magent-ui-reasoning))
              '+carlos/magent-ui-reasoning))))
        ('tool-call-start
         (let ((call-id (or (plist-get event :call-id)
                            (plist-get event :tool-id)))
               (name (or (plist-get event :tool-name)
                         (plist-get event :name))))
           (when call-id
             (puthash call-id (float-time)
                      +carlos/magent-ui--tool-start-times))
           (when name
             (+carlos/magent-ui--insert
              (format "[%s] ⚙ %s"
                      (+carlos/magent-ui--timestamp)
                      (propertize
                       (or (plist-get event :summary)
                           (plist-get event :title)
                           name)
                       'face '+carlos/magent-ui-tool-ok))
              '+carlos/magent-ui-tool-ok))))
        ('tool-call-end
         (let* ((call-id (or (plist-get event :call-id)
                             (plist-get event :tool-id)))
                (start-time (and call-id
                                 (gethash call-id
                                          +carlos/magent-ui--tool-start-times)))
                (status (plist-get event :status))
                (exit-code (plist-get event :exit-code))
                (elapsed (+carlos/magent-ui--elapsed start-time)))
           (when call-id
             (remhash call-id +carlos/magent-ui--tool-start-times))
           (+carlos/magent-ui--insert
            (format "[%s] %s %s%s%s%s"
                    (+carlos/magent-ui--timestamp)
                    (if (eq status 'completed) "✓" "✗")
                    (propertize (or (plist-get event :tool-name)
                                    (plist-get event :title)
                                    "tool")
                                'face (if (eq status 'completed)
                                          '+carlos/magent-ui-tool-ok
                                        '+carlos/magent-ui-tool-fail))
                    (if (integerp exit-code)
                        (format " (exit %d)" exit-code)
                      "")
                    (if elapsed (format " · %s" elapsed) "")
                    (let ((summary (plist-get event :result-summary)))
                      (if (and summary (not (string-empty-p summary)))
                          (format " — %s" (+carlos/magent-ui--truncate
                                            summary 100))
                        "")))
            (if (eq status 'completed)
                '+carlos/magent-ui-tool-ok
              '+carlos/magent-ui-tool-fail))))
        ('subagent-start
         (+carlos/magent-ui--insert
          (format "[%s] ⤷ subagente: %s"
                  (+carlos/magent-ui--timestamp)
                  (propertize (or (plist-get event :title) "?")
                              'face '+carlos/magent-ui-subagent))
          '+carlos/magent-ui-subagent))
        ('agent-job-event
         (let* ((job-event (plist-get event :event))
                (job (plist-get event :job))
                (job-id (and (fboundp 'magent-agent-job-id)
                             (ignore-errors (magent-agent-job-id job))))
                (agent-name (and (fboundp 'magent-agent-job-agent-name)
                                 (ignore-errors
                                   (magent-agent-job-agent-name job))))
                (model (and agent-name
                            (+carlos/magent-ui-subagent-model agent-name)))
                (status-label
                 (pcase job-event
                   ('started "spawned → running")
                   ('completed "completed ✓")
                   ('failed "failed ✗")
                   ('cancelled "cancelled")
                   (_ (format "%s" job-event))))
                (detail (plist-get event :detail)))
           (+carlos/magent-ui--insert
            (format "[%s] ⤷ %s%s%s%s%s"
                    (+carlos/magent-ui--timestamp)
                    (propertize status-label
                                'face '+carlos/magent-ui-subagent)
                    (if job-id (format " (job %s)" job-id) "")
                    (if agent-name (format " · %s" agent-name) "")
                    (if (and model (stringp model))
                        (format " · %s" model)
                      "")
                    (if (and detail (stringp detail)
                             (not (string-empty-p (string-trim detail))))
                        (format " — %s" (+carlos/magent-ui--truncate
                                          detail 80))
                      ""))
            '+carlos/magent-ui-subagent)))
        (_ nil))
    (error
     (message "Magent UI sink error: %s" (error-message-string err)))))

;; ── C2: Detalhe de tool call enriquecido ──────────────────────────
;; Advice leve sobre `magent-agent-loop-tool-call-summary' que enriquece o
;; resumo exibido no buffer: spawn_agent mostra o modelo efetivo do filho
;; (perfil Fase A / override transiente) e bash mostra o diretório de
;; trabalho quando presente nos args.

(defun +carlos/magent-ui-subagent-model (agent-name)
  "Return the effective `BACKEND MODEL' string for AGENT-NAME, or nil."
  (when (fboundp '+carlos/magent-subagent-profile)
    (let* ((override-entry (and (boundp '+carlos/magent-subagent-model-overrides)
                                (assoc agent-name +carlos/magent-subagent-model-overrides)))
           (override (and override-entry (cdr override-entry)))
           (profile (if (and override (stringp (car override)) (stringp (cdr override)))
                        (list :backend (car override) :model (cdr override))
                      (+carlos/magent-subagent-profile agent-name))))
      (when-let* ((backend (plist-get profile :backend))
                  (model (plist-get profile :model)))
        (format "%s %s" backend model)))))

(defun +carlos/magent-ui-tool-call-summary-a (orig-fn name args &rest r)
  "Advice que enriquece o resumo de tool call retornado por ORIG-FN.
Chama ORIG-FN em NAME/ARGS (R, extras, mantidos para compatibilidade de
assinatura) e anexa modelo do filho para `spawn_agent' e cwd para
`bash', quando disponíveis."
  (let* ((base (apply orig-fn name args r))
         (detail
          (cond
           ((string= name "spawn_agent")
            (when-let* ((agent (or (plist-get args :agent) "?"))
                        (model (+carlos/magent-ui-subagent-model agent)))
              (format " → %s" model)))
           ((and (string= name "bash")
                 (plist-member args :cwd))
            (let ((cwd (plist-get args :cwd)))
              (when (stringp cwd)
                (format " (in %s)" cwd))))
           (t nil))))
    (if detail
        (concat base detail)
      base)))

(unless (advice-member-p #'+carlos/magent-ui-tool-call-summary-a
                         'magent-agent-loop-tool-call-summary)
  (advice-add 'magent-agent-loop-tool-call-summary
              :around #'+carlos/magent-ui-tool-call-summary-a))

;; ── Registro do sink ──────────────────────────────────────────────
(defun +carlos/magent-ui-register-sink ()
  "Register the Magent UI activity sink when the lifecycle API is available."
  (when (fboundp 'magent-lifecycle-events-add-sink)
    (magent-lifecycle-events-add-sink #'+carlos/magent-ui-activity-sink)))

(with-eval-after-load 'magent-lifecycle-events
  (+carlos/magent-ui-register-sink))

;; Reinício idempotente (após reload de source durante desenvolvimento)
(with-eval-after-load 'magent-agent-shell
  (+carlos/magent-ui-register-sink))

(provide 'custom-magent-ui)
;;; custom-magent-ui.el ends here
