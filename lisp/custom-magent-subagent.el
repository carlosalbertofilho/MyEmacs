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

(defcustom +carlos/magent-subagent-lite-tools
  '(read write edit bash
    context_search
    elisp_smart_edit nix_smart_edit python_smart_edit
    ts_smart_edit c_smart_edit go_smart_edit org_smart_edit
    sh_smart_edit markdown_smart_edit rust_smart_edit)
  "Permission keys mantidos para backends locais (Coder Lite).
`magent-enable-tools' guarda *permission keys* (`read'→read_file,
`write'→write_file, `edit'→edit_file, `bash'→run_command, ...), não
os nomes de tool (`read_file', `run_command', `replace_file_content').
Filtrar por nomes com underscore zerava o toolset local, deixando o
modelo sem ler arquivos/escrever/executar comando."
  :type '(repeat symbol)
  :group 'magent)

(defun +carlos/--magent-backend-name (backend)
  "Retorna o nome de um backend heterogêneo, ou NIL se indeterminado.
Backend: string, símbolo, plist (:name ...) ou struct gptel-backend.
Função total (nunca lança) — usada pelo Coder Lite p/ backend local."
  (cond
   ((stringp backend) backend)
   ((symbolp backend) (symbol-name backend))
   ((and (fboundp 'gptel-backend-p) (gptel-backend-p backend))
    (gptel-backend-name backend))
   ((and (listp backend) (plist-get backend :name))
    (plist-get backend :name))
   (t nil)))
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
  (let ((local-backend (if (string-match-p "aa102-006l" (system-name))
                           "Gemini"          ;; EliteDesk: nuvem (poupa CPU)
                         "Colibre Local")))  ;; agnes (Mac M2): GPU Metal Colibre
    `(("explore"     :min-tier "free" :preferred-backend ,local-backend)
      ("general"     :min-tier "free" :preferred-backend ,local-backend)
      ("coder"       :min-tier "free" :preferred-backend "OpenCode Zen")
      ("sysadmin"    :min-tier "free" :preferred-backend ,local-backend)
      ("planner"     :min-tier "free" :preferred-backend "Gemini")
      ("tech-writer" :min-tier "free" :preferred-backend "Gemini")
      ("auditor"     :min-tier "free" :preferred-backend "OpenCode Zen")
      ("sec-ops"     :min-tier "free" :preferred-backend ,local-backend)
      ("qa"          :min-tier "free" :preferred-backend "Gemini")))
  "Dicas de roteamento de modelo dos subagentes do Magent (spawn_agent).
Alist de (AGENT-NAME . HINTS) onde HINTS é um plist com:
- `:min-tier' — piso de tier (`local', `free' ou `paid') que o roteamento
  nunca desce abaixo, independente da complexidade da tarefa;
- `:preferred-backend' (opcional) — backend preferido como desempate dentro
  do tier escolhido.
Todos os perfis usam piso \"free\": o roteamento pode preferir nuvem gratuita
e o MLX fica para orquestrador/dev/reasoning via `+carlos/magent-host-profiles'
(nunca exigido para subagentes). NÃO existe modelo concreto pinado por perfil:
o advice `+carlos/magent-subagent-apply-profile' resolve o modelo em runtime
pela complexidade da tarefa (`user-prompt') respeitando estas dicas, e a tool
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
         (backend-obj (and request-state (cl-struct-slot-value 'magent-request-context 'backend request-state)))
         (backend-name (and backend-obj (if (stringp backend-obj) backend-obj (+carlos/--magent-backend-name backend-obj))))
         (is-local (and backend-name (or (string-match-p "MLX" backend-name)
                                         (string-match-p "Colibre" backend-name)
                                         (string-match-p "Ollama" backend-name)
                                         (string-match-p "LM Studio" backend-name))))
         (magent-enable-tools 
          (if (boundp 'magent-enable-tools)
              (let ((tools magent-enable-tools))
                (when is-orchestrator
                  (setq tools (seq-filter
                               (lambda (sym)
                                 (let ((s (symbol-name sym)))
                                   (not (or (memq sym '(read write edit snippet_expand buffer))
                                            (string-match-p "smart_edit" s)
                                            (string-match-p "write_to_file" s)
                                            (string-match-p "replace_file" s)))))
                               tools)))
                (when is-local
                  (setq tools (seq-filter
                                (lambda (t-name) (memq t-name +carlos/magent-subagent-lite-tools))
                                tools)))
                tools)
            nil)))
    (funcall orig-fn user-prompt callback agent-info skill-names event-context
             request-context capability-resolution text-callback request-live-p
             request-state)))

(with-eval-after-load 'magent-agent
  (advice-add 'magent-agent-process
              :around #'+carlos/magent-subagent-apply-profile))

;; ── Subagent Watchdog & Timeout Cleanup (Fase 2) ─────────────────────

(defvar +carlos/magent-job-watchdog-timers (make-hash-table :test 'equal)
  "Hash-table de timers de watchdog ativos mapeados por job-id.")

(defun +carlos/magent-cancel-job-watchdog (job-id)
  "Cancela e remove o timer de watchdog associado a JOB-ID."
  (when-let* ((timer (gethash job-id +carlos/magent-job-watchdog-timers)))
    (when (timerp timer) (cancel-timer timer))
    (remhash job-id +carlos/magent-job-watchdog-timers)))

(defun +carlos/magent-abort-and-cancel-job (job reason)
  "Aborta o child loop e cancela o JOB com REASON."
  (let* ((jid (and (fboundp 'magent-agent-job-id) (magent-agent-job-id job)))
         (runtime (and jid (fboundp 'magent-agent-job-runtime) (magent-agent-job-runtime jid)))
         (loop (and runtime (plist-get runtime :loop))))
    (when jid (+carlos/magent-cancel-job-watchdog jid))
    (when (and loop (fboundp 'magent-agent-loop-p) (magent-agent-loop-p loop))
      (require 'magent-agent-loop nil t)
      (when (fboundp 'magent-agent-loop-abort)
        (magent-agent-loop-abort loop)))
    (when (fboundp 'magent-agent-job-set-status)
      (magent-agent-job-set-status job 'cancelled nil (or reason "Timeout")))
    (when (and jid (fboundp 'magent-agent-job-clear-runtime))
      (magent-agent-job-clear-runtime jid))))

(defun +carlos/magent-tools-wait-agent-around (orig-fn callback &optional job-id job-ids timeout)
  "Garante que se `wait_agent' atingir timeout, todos os jobs não-terminais
sejam abortados via `magent-agent-loop-abort', marcados como 'cancelled
com erro \"Wait timed out\" e limpos do runtime."
  (let* ((wrapped-callback
          (lambda (result)
            (when (and (fboundp 'magent-tool-result-p)
                       (magent-tool-result-p result))
              (let* ((out-str (magent-tool-result-output-string result)))
                (when (and (stringp out-str)
                           (string-match-p "\"status\":[ \t]*\"timeout\"" out-str))
                  (when (fboundp 'magent-tools--parent-session)
                    (let* ((session (magent-tools--parent-session))
                           (ids (if (fboundp 'magent-tools--agent-job-ids)
                                    (magent-tools--agent-job-ids job-id job-ids)
                                  (or (and job-id (list job-id)) job-ids)))
                           (jobs (when (and session (fboundp 'magent-tools--agent-jobs-for-ids))
                                   (magent-tools--agent-jobs-for-ids session ids))))
                      (dolist (job jobs)
                        (unless (and (fboundp 'magent-tools--agent-job-terminal-p)
                                     (magent-tools--agent-job-terminal-p job))
                          (+carlos/magent-abort-and-cancel-job job "Wait timed out"))))))))
            (funcall callback result))))
    (funcall orig-fn wrapped-callback job-id job-ids timeout)))

(defun +carlos/magent-tools-spawn-agent-around (orig-fn callback agent-name prompt &optional task-name)
  "Valida PROMPT rejeitando placeholders e anexa Watchdog Timer autônomo ao job."
  (let* ((trimmed (and (stringp prompt) (+carlos/magent--string-trim prompt)))
         (low (and trimmed (downcase trimmed))))
    (cond
     ((or (null trimmed) (string-empty-p trimmed))
      (if (fboundp 'magent-tools--fail)
          (magent-tools--fail callback "Error: prompt is required and cannot be empty")
        (funcall callback "Error: prompt is required and cannot be empty")))
     ((or (string-prefix-p "[insert" low)
          (string-prefix-p "[todo" low)
          (string-prefix-p "[placeholder" low)
          (string-match-p "\\[synthesis" low))
      (if (fboundp 'magent-tools--fail)
          (magent-tools--fail callback (format "Error: prompt '%s' is an invalid placeholder" prompt))
        (funcall callback (format "Error: prompt '%s' is an invalid placeholder" prompt))))
     (t
      (let* ((wrapped-callback
              (lambda (result)
                (when (and (fboundp 'magent-tool-result-p) (magent-tool-result-p result))
                  (let* ((out-str (magent-tool-result-output-string result)))
                    (when (and (stringp out-str)
                               (string-match "\"job_id\":[ \t]*\"\\([^\"]+\\)\"" out-str))
                      (let* ((jid (match-string 1 out-str))
                             (session (and (fboundp 'magent-tools--parent-session)
                                           (magent-tools--parent-session)))
                             (job (and session (fboundp 'magent-session-agent-job)
                                       (magent-session-agent-job session jid)))
                             (ttl (if (and (boundp 'magent-request-timeout)
                                           (numberp magent-request-timeout)
                                           (> magent-request-timeout 0))
                                      magent-request-timeout
                                    300)))
                        (when job
                          (when (fboundp 'magent-agent-job-add-observer)
                            (magent-agent-job-add-observer
                             job
                             (lambda (j)
                               (when (and (fboundp 'magent-tools--agent-job-terminal-p)
                                          (magent-tools--agent-job-terminal-p j))
                                 (+carlos/magent-cancel-job-watchdog jid)))))
                          (let ((timer (run-at-time
                                        ttl nil
                                        (lambda ()
                                          (when (and (fboundp 'magent-agent-job-status)
                                                     (memq (magent-agent-job-status job)
                                                           '(queued running waiting)))
                                            (+carlos/magent-abort-and-cancel-job job "Job watchdog timeout"))))))
                            (puthash jid timer +carlos/magent-job-watchdog-timers)))))))
                (funcall callback result))))
        (funcall orig-fn wrapped-callback agent-name prompt task-name))))))

(with-eval-after-load 'magent-tools
  (advice-add 'magent-tools--wait-agent :around #'+carlos/magent-tools-wait-agent-around)
  (advice-add 'magent-tools--spawn-agent :around #'+carlos/magent-tools-spawn-agent-around))

(provide 'custom-magent-subagent)

;;; custom-magent-subagent.el ends here
