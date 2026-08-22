;;; custom-magent-subagent.el --- Magent subagentes: perfis e modelo por filho -*- lexical-binding: t; -*-

;;; Commentary:
;; Perfis de backend/modelo por agente do Magent (spawn_agent) e advice que
;; força o modelo do filho no request-state, contornando a herança pai→filho.
;; A Fase A (roteamento de modelos pelo orquestrador) registra overrides
;; transientes via `+carlos/magent-subagent-model-overrides' (definido em
;; custom-magent-tools.el, carregado primeiro) e este advice os consome (pop)
;; antes de aplicar o perfil estático.
;;
;; D5 — Context Sharing Dinâmico e Estruturas Duráveis:
;;   1. Persistência de jobs: histórico e reconciliação pós-restart dos jobs
;;      duráveis (:agent-jobs na sessão pai, estrutura `magent-agent-job').
;;   2. Ledger: registro call-id → job ligando rigidamente tool-call/output
;;      de spawn_agent/wait_agent ao ciclo de vida do job (via lifecycle
;;      events), complementando o ledger canônico `magent-thread' (:call-id).
;;   3. Regras locais AGENTS.md: descoberta/injeção é NATIVA desde
;;      magent-agent.el:300 (`magent-project-instructions-system-message',
;;      default '("AGENTS.md"), teto 64KB) — aqui só verificamos a pipeline.
;;   4. Contexto pai: `+carlos/magent-collect-parent-context' + bloco
;;      <parent_context> (capado) injetado no system prompt de SUBAGENTES.

;;; Code:

(require 'cl-lib)

(defvar +carlos/magent-subagent-model-overrides)
(defvar +carlos/magent-current-agent-is-orchestrator)
(defvar +carlos/magent-fsm-subagent-jobs)
(defvar magent-enable-tools)
(defvar magent-tools--request-context)
(declare-function magent-agent-info-name "magent-agent-info")
(declare-function magent-agent-process "magent-agent")
(declare-function magent-agent-job-status "magent-agent-job")
(declare-function magent-agent-job-id "magent-agent-job")
(declare-function magent-agent-job-runtime "magent-agent-job")
(declare-function magent-agent-job-reconcile-after-restart "magent-agent-job")
(declare-function magent-session-agent-jobs "magent-session")
(declare-function magent-session-get-id "magent-session")
(declare-function magent-session-get-messages "magent-session")
(declare-function magent-session-save-deferred-for-session "magent-session")
(declare-function magent-msg-role "magent-ledger")
(declare-function magent-msg-content "magent-ledger")
(declare-function magent-request-context-project-root "magent-runtime-api")
(declare-function magent-tools--parent-session "magent-tools")
(declare-function magent-tools--parent-scope "magent-tools")
(declare-function magent-lifecycle-events-add-sink "magent-lifecycle-events")
(declare-function magent-project-instructions-discover "magent-project-instructions")
(declare-function magent-project-instructions-system-message "magent-project-instructions")
(declare-function +carlos/magent-resolve-cheap-model "custom-magent-context")
(declare-function +carlos/magent-resolve-model "custom-magent-tools")
(declare-function +carlos/magent-task-complexity "custom-magent-tools")
(declare-function +carlos/local-ai-server-ping-p "custom-ai")

;; ── ETAPA 4: Perfis de Subagente (spawn_agent → roteamento por dicas) ──────
;; O pacote Magent faz o subagente HERDAR o backend/modelo do pai e a herança
;; vence o override do agente (`(or inherited-backend gptel-backend)' em
;; magent-agent.el).  Para que o orquestrador leve (local) delegue a modelos
;; fortes, sobrescrevemos o `request-state' do filho — o 11º argumento de
;; `magent-agent-process' — com a resolução dinâmica de modelo por perfil.

(defcustom +carlos/magent-subagent-profiles
  '(("explore"  :min-tier "local")
    ("general"  :min-tier "local")
    ;; Equipe de especialistas (D9, custom-magent-team.el)
    ("coder"       :min-tier "paid")
    ("sysadmin"    :min-tier "paid")
    ("planner"     :min-tier "paid")
    ("tech-writer" :min-tier "free")
    ("auditor"     :min-tier "paid")
    ("sec-ops"     :min-tier "paid")
    ("qa"          :min-tier "paid"))
  "Dicas de roteamento de modelo dos subagentes do Magent (spawn_agent).
Alist de (AGENT-NAME . HINTS) onde HINTS é um plist com:
- `:min-tier' — piso de tier (`local', `free' ou `paid') que o roteamento
  nunca desce abaixo, independente da complexidade da tarefa;
- `:preferred-backend' (opcional) — backend preferido como desempate dentro
  do tier escolhido.
NÃO existe modelo concreto pinado por perfil: o advice
`+carlos/magent-subagent-apply-profile' resolve o modelo em runtime pela
complexidade da tarefa (`user-prompt') respeitando estas dicas, e a tool
`select_model' (Fase A) aplica o override transiente quando o orquestrador
escolhe explicitamente.  Agentes fora desta lista — ex.: o orquestrador —
não são alterados."
  :type '(alist :key-type string
                :value-type (plist :key-type symbol :value-type string))
  :group 'magent)

(defun +carlos/magent-subagent-profile (agent-name)
  "Retorna as dicas de roteamento (plist :min-tier/:preferred-backend) de
AGENT-NAME, ou nil se sem perfil."
  (cdr (assoc agent-name +carlos/magent-subagent-profiles)))

(defun +carlos/magent-subagent-resolve (agent-name task-description)
  "Resolve o modelo de AGENT-NAME para TASK-DESCRIPTION via dicas de perfil.
Classifica TASK-DESCRIPTION com `+carlos/magent-task-complexity' e delega a
`+carlos/magent-resolve-model' com as dicas (:min-tier/:preferred-backend) de
`+carlos/magent-subagent-profiles'.  Retorna plist (:backend B :model M), ou
nil quando AGENT-NAME não tem perfil (a herança do pai fica como fallback
final) ou nada disponível."
  (when (and (fboundp '+carlos/magent-resolve-model)
             (fboundp '+carlos/magent-task-complexity)
             (cdr (assoc agent-name +carlos/magent-subagent-profiles)))
    (let* ((hints (cdr (assoc agent-name +carlos/magent-subagent-profiles)))
           (choice (+carlos/magent-resolve-model
                    (+carlos/magent-task-complexity task-description)
                    (and (fboundp '+carlos/local-ai-server-ping-p)
                         (+carlos/local-ai-server-ping-p))
                    nil nil hints)))
      (when choice
        (list :backend (plist-get choice :backend)
              :model (plist-get choice :model))))))

(defun +carlos/magent-subagent-apply-profile
    (orig-fn user-prompt &optional callback agent-info skill-names event-context
             request-context capability-resolution text-callback request-live-p
             request-state)
  "Força o modelo do subagente conforme override transiente ou resolução dinâmica.
ORIG-FN é `magent-agent-process'; USER-PROMPT, CALLBACK, AGENT-INFO e os
demais argumentos (SKILL-NAMES, EVENT-CONTEXT, REQUEST-CONTEXT,
CAPABILITY-RESOLUTION, TEXT-CALLBACK, REQUEST-LIVE-P) são repassados
intactos, e REQUEST-STATE é alterado in-place pelo `setf'.  Para o agente
interno `compaction' (B5.1) resolve um modelo barato via
`+carlos/magent-resolve-cheap-model' (local se online e cabe no teto;
senão free da nuvem).  Para subagentes, primeiro consome (pop) um override
registrado pela tool `select_model' em
`+carlos/magent-subagent-model-overrides' (Fase A); na ausência ou
invalidade, resolve dinamicamente pela complexidade de USER-PROMPT com as
dicas de `+carlos/magent-subagent-profiles'
(`+carlos/magent-subagent-resolve') — nunca modelo pinado.
Usa `cl-struct-slot-value' em vez dos accessors gerados da struct —
magent-runtime não está carregado no compile-time e `setf' direto viraria
chamada a função vazia no .elc."
  (when (and agent-info request-state)
    (let* ((agent-name (magent-agent-info-name agent-info))
           (choice
            (if (equal agent-name "compaction")
                (+carlos/magent-resolve-cheap-model)
              (let* ((override-entry (assoc agent-name +carlos/magent-subagent-model-overrides))
                     (override (and override-entry (cdr override-entry)))
                     (override-valid (and override
                                          (stringp (car override))
                                          (stringp (cdr override))
                                          (fboundp 'gptel-get-backend)
                                          (gptel-get-backend (car override)))))
                (when override-entry
                  (setq +carlos/magent-subagent-model-overrides
                        (remove override-entry +carlos/magent-subagent-model-overrides)))
                (if override-valid
                    (list :backend (car override) :model (cdr override))
                  (+carlos/magent-subagent-resolve agent-name user-prompt))))))
      (when-let* ((profile choice)
                  (backend-name (plist-get profile :backend))
                  (backend-obj (and (stringp backend-name)
                                    (fboundp 'gptel-get-backend)
                                    (gptel-get-backend backend-name))))
        (setf (cl-struct-slot-value 'magent-request-context 'backend request-state)
              backend-obj
              (cl-struct-slot-value 'magent-request-context 'model request-state)
              (intern (plist-get profile :model))))))
  (let* ((agent-name (and agent-info (magent-agent-info-name agent-info)))
         (is-orchestrator (and agent-name
                               (not (equal agent-name "compaction"))
                               (not (+carlos/magent-subagent-profile agent-name))))
         (+carlos/magent-current-agent-is-orchestrator is-orchestrator)
         (magent-enable-tools (if (and is-orchestrator (boundp 'magent-enable-tools))
                                  (remq 'read (remq 'write (remq 'edit (remq 'snippet_expand (remq 'buffer magent-enable-tools)))))
                                (when (boundp 'magent-enable-tools) magent-enable-tools))))
    (funcall orig-fn user-prompt callback agent-info skill-names event-context
             request-context capability-resolution text-callback request-live-p
             request-state)))

(with-eval-after-load 'magent-agent
  (advice-add 'magent-agent-process
              :around #'+carlos/magent-subagent-apply-profile))

;; ── D5.1: Persistência de jobs de subagente (:agent-jobs) ───────────────────
;; Os jobs duráveis já nascem na sessão pai (`magent-session-agent-jobs') e
;; são salvos via `magent-tools--persist-parent-session'.  Aqui adicionamos o
;; histórico consultável e a reconciliação pós-restart: jobs queued/running
;; sem runtime vivo travariam a FSM (subagent-running/subagent-waiting).

(defun +carlos/magent-subagent-jobs-history (&optional session)
  "Retorna TODOS os jobs de subagente persistidos na SESSION pai.
Qualquer status (queued/running/waiting/completed/failed/closed/cancelled).
SESSION default = `magent-tools--parent-session'.  nil sem infra do Magent."
  (when-let* ((session
               (or session
                   (and (fboundp 'magent-tools--parent-session)
                        (ignore-errors (magent-tools--parent-session))))))
    (and (fboundp 'magent-session-agent-jobs)
         (copy-sequence (magent-session-agent-jobs session)))))

(defun +carlos/magent-subagent-stale-job-p (job)
  "Non-nil quando JOB está queued/running sem runtime vivo."
  (and job
       (memq (magent-agent-job-status job) '(queued running))
       (null (magent-agent-job-runtime (magent-agent-job-id job)))))

(defun +carlos/magent-subagent-reconcile-stale-jobs ()
  "Cancela jobs queued/running sem runtime vivo na sessão pai.
Usa `magent-agent-job-reconcile-after-restart' e agenda persistência da
sessão.  Retorna os ids dos jobs reconciliados (nil = nada a fazer)."
  (when (and (fboundp 'magent-agent-job-status)
             (fboundp 'magent-agent-job-runtime)
             (fboundp 'magent-agent-job-reconcile-after-restart))
    (let* ((session (ignore-errors (magent-tools--parent-session)))
           (jobs (and session (+carlos/magent-subagent-jobs-history session)))
           reconciled)
      (when jobs
        (dolist (job jobs)
          (when (+carlos/magent-subagent-stale-job-p job)
            (magent-agent-job-reconcile-after-restart
             job "Runtime ausente — reconciliado após restart")
            (push (magent-agent-job-id job) reconciled)))
        (when (and reconciled
                   (fboundp 'magent-session-save-deferred-for-session))
          (ignore-errors
            (magent-session-save-deferred-for-session
             session
             (or (and (fboundp 'magent-tools--parent-scope)
                      (ignore-errors (magent-tools--parent-scope)))
                 'global)))))
      (nreverse reconciled))))

;; ── D5.2: Ledger — correlação call-id ↔ job (spawn_agent/wait_agent) ────────
(defcustom +carlos/magent-subagent-tracked-tools '("spawn_agent" "wait_agent")
  "Tools de subagente rastreadas no registro call-id → ciclo de vida do job."
  :type '(repeat string)
  :group 'magent)

(defvar +carlos/magent-subagent--calls (make-hash-table :test #'equal)
  "Registro D5: call-id → plist de correlação tool-call/job.
Chaves: `:tool', `:args', `:started-at', `:status', `:finished-at',
`:job-id', `:job-status'.")

(defun +carlos/magent-subagent-call-entry (call-id)
  "Retorna a entrada do registro para CALL-ID, ou nil."
  (gethash call-id +carlos/magent-subagent--calls))

(defun +carlos/magent-subagent-ledger-reset ()
  "Limpa o registro de correlação call-id → job (uso em testes/boot)."
  (clrhash +carlos/magent-subagent--calls))

(defun +carlos/magent-subagent--job-id-from-args (args)
  "Extrai o primeiro job id dos ARGS da tool wait_agent.
Aceita `:job_id'/`:job-id' (string) e `:job_ids'/`:job-ids' (string,
lista ou vetor)."
  (let ((raw (or (plist-get args :job_id)
                 (plist-get args :job-id)
                 (plist-get args :job_ids)
                 (plist-get args :job-ids))))
    (cond
     ((stringp raw) (and (not (string-empty-p raw)) raw))
     ((vectorp raw) (and (> (length raw) 0) (format "%s" (aref raw 0))))
     ((listp raw) (car raw))
     (t nil))))

(defun +carlos/magent-subagent-ledger-note-tool (event &optional end-p)
  "Atualiza o registro com um evento tool-call-start/end (END-P non-nil)."
  (let ((call-id (plist-get event :call-id))
        (name (plist-get event :tool-name)))
    (when (and call-id (member name +carlos/magent-subagent-tracked-tools))
      (if end-p
          (when-let* ((entry (gethash call-id +carlos/magent-subagent--calls)))
            (puthash call-id
                     (plist-put (plist-put (copy-sequence entry)
                                           :status (plist-get event :status))
                                :finished-at (float-time))
                     +carlos/magent-subagent--calls))
        (unless (gethash call-id +carlos/magent-subagent--calls)
          (puthash call-id
                   (append (list :tool name
                                 :started-at (or (plist-get event :time)
                                                 (float-time))
                                 :status 'running)
                           (when-let* ((job-id (+carlos/magent-subagent--job-id-from-args
                                                (plist-get event :args))))
                             (list :job-id job-id)))
                   +carlos/magent-subagent--calls))))))

(defun +carlos/magent-subagent-ledger-note-job (event)
  "Liga o ciclo de vida do job (evento agent-job-event) às entradas abertas.
Entradas de spawn_agent sem job-id recebem o id/status; entradas com id já
definido (wait_agent) só atualizam em caso de match exato."
  (when-let* ((job (plist-get event :job)))
    (let* ((phase (plist-get event :event))
           (detail (plist-get event :detail)))
      (maphash
       (lambda (call-id entry)
         (let ((entry-job-id (plist-get entry :job-id)))
           (when (or (null entry-job-id)
                     (equal entry-job-id (magent-agent-job-id job)))
             (puthash call-id
                      (plist-put
                       (plist-put
                        (plist-put (copy-sequence entry)
                                   :job-id (magent-agent-job-id job))
                        :job-status phase)
                       :result detail)
                      +carlos/magent-subagent--calls))))
       +carlos/magent-subagent--calls))))

;; ── D5.4: Contexto pai (<parent_context> no system prompt dos filhos) ───────
(defcustom +carlos/magent-parent-context-max-chars 2000
  "Teto de caracteres do bloco <parent_context> (~300–500 tokens)."
  :type 'natnum
  :group 'magent)

(defun +carlos/magent-collect-parent-context ()
  "Coleta contexto essencial da sessão pai para herança pelos filhos.
Retorna plist (:session-id :project-root :goal :message-count), ou nil
sem sessão/infra disponível.  Nunca sinaliza erro."
  (when-let* ((session (and (fboundp 'magent-tools--parent-session)
                            (ignore-errors (magent-tools--parent-session)))))
    (let* ((root
            (and (boundp 'magent-tools--request-context)
                 magent-tools--request-context
                 (fboundp 'magent-request-context-project-root)
                 (ignore-errors
                   (magent-request-context-project-root
                    magent-tools--request-context))))
           (messages
            (and (fboundp 'magent-session-get-messages)
                 (ignore-errors (magent-session-get-messages session))))
           (goal
            (when messages
              (seq-find (lambda (msg) (eq (magent-msg-role msg) 'user))
                        (reverse messages))))
           (goal-text
            (and goal (fboundp 'magent-msg-content)
                 (let ((content (magent-msg-content goal)))
                   (if (stringp content) content (format "%S" content))))))
      (append (when-let* ((id (and (fboundp 'magent-session-get-id)
                                   (ignore-errors
                                     (magent-session-get-id session)))))
                (list :session-id id))
              (when root (list :project-root root))
              (when goal-text
                (list :goal
                      (truncate-string-to-width
                       (string-trim goal-text) 600 nil nil "...")))
              (list :message-count (length messages))))))

(defun +carlos/magent-render-parent-context (context &optional max-chars)
  "Renderiza CONTEXT como bloco <parent_context> capado a MAX-CHARS.
nil quando CONTEXT não tem conteúdo útil."
  (when-let* ((context context)
              (parts
               (delq nil
                     (list
                      (when-let* ((id (plist-get context :session-id)))
                        (format "session: %s" id))
                      (when-let* ((root (plist-get context :project-root)))
                        (format "project_root: %s" root))
                      (when-let* ((goal (plist-get context :goal)))
                        (format "current_goal: %s" goal))
                      (format "messages: %s"
                              (or (plist-get context :message-count) 0)))))
              (body (mapconcat #'identity parts "\n")))
    (format "<parent_context>\n%s\n</parent_context>"
            (truncate-string-to-width
             body
             (or max-chars +carlos/magent-parent-context-max-chars)
             nil nil "..."))))

(defun +carlos/magent-inject-child-parent-context (composed &rest _)
  "Append <parent_context> ao system prompt COMPOSED de SUBAGENTES.
Filter-return de `magent-agent--compose-system-message'; orquestrador
(`+carlos/magent-current-agent-is-orchestrator' non-nil) fica intocado."
  (if (and composed
           (boundp '+carlos/magent-current-agent-is-orchestrator)
           (not +carlos/magent-current-agent-is-orchestrator))
      (if-let* ((block (+carlos/magent-render-parent-context
                        (+carlos/magent-collect-parent-context))))
          (concat composed "\n\n" block)
        composed)
    composed))

(with-eval-after-load 'magent-agent
  (advice-add 'magent-agent--compose-system-message
              :filter-return #'+carlos/magent-inject-child-parent-context))

;; ── Registro D5: sink único de lifecycle events ──────────────────────────────
(defun +carlos/magent-subagent-lifecycle-sink (event)
  "Sink D5: reconcile stale jobs no turn-start; alimenta o ledger D5.2."
  (pcase (plist-get event :type)
    ('turn-start (+carlos/magent-subagent-reconcile-stale-jobs))
    ('tool-call-start
     (+carlos/magent-subagent-ledger-note-tool event))
    ('tool-call-end
     (+carlos/magent-subagent-ledger-note-tool event :end))
    ('agent-job-event
     (+carlos/magent-subagent-ledger-note-job event))))

(with-eval-after-load 'magent-lifecycle-events
  (magent-lifecycle-events-add-sink #'+carlos/magent-subagent-lifecycle-sink))

(provide 'custom-magent-subagent)
;;; custom-magent-subagent.el ends here
