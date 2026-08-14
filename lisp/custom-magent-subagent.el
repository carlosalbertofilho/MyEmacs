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

(declare-function magent-agent-info-name "magent-agent-info")
(declare-function magent-agent-process "magent-agent")

;; ── ETAPA 4: Perfis de Subagente (spawn_agent → modelo forte na nuvem) ───────
;; O pacote Magent faz o subagente HERDAR o backend/modelo do pai e a herança
;; vence o override do agente (`(or inherited-backend gptel-backend)' em
;; magent-agent.el). Para que o orquestrador leve (local) delegue a modelos
;; fortes, sobrescrevemos o `request-state' do filho — o 11º argumento de
;; `magent-agent-process' — com o perfil declarado por agente.

(defcustom +carlos/magent-subagent-profiles
  '(("explore"  :backend "Gemini" :model "gemini-3.1-pro-preview")
    ("general"  :backend "Gemini" :model "gemini-3.1-pro-preview"))
  "Perfis de backend/modelo dos subagentes do Magent (spawn_agent).
Alist de (AGENT-NAME . (:backend B :model M)).  O advice
`+carlos/magent-subagent-apply-profile' aplica o perfil no request-state do
filho, contornando a herança pai→filho do pacote.  Agentes fora desta lista —
ex.: o orquestrador — não são alterados."
  :type '(alist :key-type string
                :value-type (plist :key-type symbol :value-type string))
  :group 'magent)

(defun +carlos/magent-subagent-profile (agent-name)
  "Retorna o plist (:backend B :model M) de AGENT-NAME, ou nil se sem perfil."
  (cdr (assoc agent-name +carlos/magent-subagent-profiles)))

(defun +carlos/magent-subagent-apply-profile
    (orig-fn user-prompt &optional callback agent-info skill-names event-context
             request-context capability-resolution text-callback request-live-p
             request-state)
  "Força o modelo do subagente conforme override transiente ou perfil estático.
ORIG-FN é `magent-agent-process'; USER-PROMPT, CALLBACK, AGENT-INFO e os
demais argumentos (SKILL-NAMES, EVENT-CONTEXT, REQUEST-CONTEXT,
CAPABILITY-RESOLUTION, TEXT-CALLBACK, REQUEST-LIVE-P) são repassados
intactos, e REQUEST-STATE é alterado in-place pelo `setf'.  Primeiro
consome (pop) um override registrado pela tool `select_model' em
`+carlos/magent-subagent-model-overrides' (Fase A); na ausência ou
invalidade, aplica o perfil estático de `+carlos/magent-subagent-profiles'.
Usa `cl-struct-slot-value' em vez dos accessors gerados da struct —
magent-runtime não está carregado no compile-time e `setf' direto viraria
chamada a função vazia no .elc."
  (when (and agent-info request-state)
    (let* ((agent-name (magent-agent-info-name agent-info))
           (override-entry (assoc agent-name +carlos/magent-subagent-model-overrides))
           (override (and override-entry (cdr override-entry)))
           (override-valid (and override
                                (stringp (car override))
                                (stringp (cdr override))
                                (fboundp 'gptel-get-backend)
                                (gptel-get-backend (car override)))))
      (when override-entry
        (setq +carlos/magent-subagent-model-overrides
              (remove override-entry +carlos/magent-subagent-model-overrides)))
      (when-let* ((profile (if override-valid
                               (list :backend (car override) :model (cdr override))
                             (+carlos/magent-subagent-profile agent-name)))
                  (backend-name (plist-get profile :backend))
                  (backend-obj (and (stringp backend-name)
                                    (fboundp 'gptel-get-backend)
                                    (gptel-get-backend backend-name))))
        (setf (cl-struct-slot-value 'magent-request-context 'backend request-state)
              backend-obj
              (cl-struct-slot-value 'magent-request-context 'model request-state)
              (intern (plist-get profile :model))))))
  (funcall orig-fn user-prompt callback agent-info skill-names event-context
           request-context capability-resolution text-callback request-live-p
           request-state))

(with-eval-after-load 'magent-agent
  (advice-add 'magent-agent-process
              :around #'+carlos/magent-subagent-apply-profile))

(provide 'custom-magent-subagent)
;;; custom-magent-subagent.el ends here
