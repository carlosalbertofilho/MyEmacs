;;; custom-magent-subagent.el --- Magent subagentes: perfis e modelo por filho -*- lexical-binding: t; -*-

;;; Commentary:
;; Perfis de backend/modelo por agente do Magent (spawn_agent) e advice que
;; força o modelo do filho no request-state, contornando a herança pai→filho.
;; A Fase A (roteamento de modelos pelo orquestrador) registra overrides
;; transientes via `+carlos/magent-subagent-model-overrides' (definido em
;; custom-magent-tools.el, carregado primeiro) e este advice os consome (pop)
;; antes de aplicar o perfil estático.

;;; Code:

(require 'cl-lib)

(defvar +carlos/magent-subagent-model-overrides)
(defvar magent-enable-tools)
(declare-function magent-agent-info-name "magent-agent-info")
(declare-function magent-agent-process "magent-agent")
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
         (magent-enable-tools (if (and is-orchestrator (boundp 'magent-enable-tools))
                                  (remq 'read (remq 'write (remq 'edit (remq 'snippet_expand (remq 'buffer magent-enable-tools)))))
                                (when (boundp 'magent-enable-tools) magent-enable-tools))))
    (funcall orig-fn user-prompt callback agent-info skill-names event-context
             request-context capability-resolution text-callback request-live-p
             request-state)))

(with-eval-after-load 'magent-agent
  (advice-add 'magent-agent-process
              :around #'+carlos/magent-subagent-apply-profile))

(provide 'custom-magent-subagent)
;;; custom-magent-subagent.el ends here
