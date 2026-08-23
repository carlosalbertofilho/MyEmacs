;;; custom-magent-infra.el --- Infraestrutura de baixo nível, resiliência e circuit breakers -*- lexical-binding: t; -*-

;;; Commentary:
;; Este módulo provê a infraestrutura central do ecossistema de agentes IA.
;; Inclui sanitização de AST, correções de aridade para backends LLM (Gemini),
;; supressão de dumps longos no log, e implementações do padrão Circuit Breaker
;; para garantir robustez e fail-fast em requisições de rede.

;;; Code:

(require 'cl-lib)

(declare-function magent-llm-gptel--sanitize-info "magent-llm-gptel")
(declare-function magent-llm-gptel--managed-info-p "magent-llm-gptel")
(declare-function gptel-fsm-info "gptel")
(declare-function gptel-tool-args "gptel")

;; ── Infraestrutura, Diagnóstico e Sanitização ────────────────────────
(defvar magent-enable-logging)

(defvar +carlos/magent-message-max-len 400
  "Comprimento máximo de mensagem permitido no *Messages*.
Mensagens mais longas são suprimidas (exceto erros).")

(defcustom +carlos/magent-tool-result-max-chars 8000
  "Limite de caracteres por tool result por turno.
Resultados que excedem este cap são truncados com nota de truncamento.
Acumulador por turno: quando a soma de chars de todos os results do turno
excede este valor, novos results são truncados."
  :type 'integer
  :group '+carlos/ai)

(defun +carlos/magent-suppress-long-messages-a (orig-fn format-string &rest args)
  "Advice de `message' que suprime dumps longos não-erro do *Messages*.
ORIG-FN é `message'; FORMAT-STRING e ARGS são o texto a exibir."
  (let* ((text (condition-case nil
                   (apply #'format format-string args)
                 (error format-string)))
         (is-error (string-match-p "\\(?:Error\\|Warning\\|error\\|timeout\\|Stopped\\|Wrong type\\|DEBUG\\)" text)))
    (if (and (not is-error)
             (> (length text) +carlos/magent-message-max-len))
        text  ;; retorna o texto mas não chama message (suprimido do *Messages*)
      (apply orig-fn format-string args))))

(advice-add 'message :around #'+carlos/magent-suppress-long-messages-a)

(defvar +carlos/magent-disable-logging t
  "Non-nil desativa completamente o magent-log para evitar chamadas de log/message.")

(defun +carlos/magent-log-override-a (orig format-string &rest args)
  "Advice que suprime `magent-log' quando a var de diagnóstico está ativa.
ORIG é `magent-log'; FORMAT-STRING e ARGS são o texto do log."
  (unless +carlos/magent-disable-logging
    (apply orig format-string args)))

(with-eval-after-load 'magent-log
  (when (fboundp 'magent-log)
    (advice-add 'magent-log :around #'+carlos/magent-log-override-a)))

(setq magent-enable-logging nil)

(defun +carlos/magent-sanitize-tool-use-name-a (orig-fn state fsm &rest args)
  "Garante que os nomes em `:tool-use' sejam strings.
ORIG-FN é o handler nativo de tool-use; STATE e FSM são o estado e a FSM
do gptel; ARGS são repassados intactos.  Evita falha em `equal' com
símbolos e previne o timeout de 120s no Gemini."
  (when-let* ((info (and (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm))))
    (when (fboundp 'magent-llm-gptel--sanitize-info)
      (magent-llm-gptel--sanitize-info info)))
  (apply orig-fn state fsm args))

(with-eval-after-load 'magent-llm-gptel
  (defun magent-llm-gptel--sanitize-after-parse-response-a
      (orig-fn backend response info &rest args)
    "Sanitize Magent-managed INFO after gptel parses a response.
Accept &rest ARGS for Gemini streaming 5th argument."
    (prog1 (apply orig-fn backend response info args)
      (when (and (fboundp 'magent-llm-gptel--managed-info-p)
                 (magent-llm-gptel--managed-info-p info))
        (magent-llm-gptel--sanitize-info info))))
  (when (fboundp 'magent-llm-gptel--handle-tool-use)
    (advice-add 'magent-llm-gptel--handle-tool-use
                :around #'+carlos/magent-sanitize-tool-use-name-a)))

(with-eval-after-load 'magent-tools
  (when (and (boundp 'magent-tools--wait-agent-tool)
             (fboundp 'gptel-tool-args))
    (let ((tool magent-tools--wait-agent-tool))
      (aset tool 4
            (mapcar (lambda (arg)
                      (if (and (stringp (plist-get arg :name))
                               (equal (plist-get arg :name) "job_ids"))
                          (plist-put (copy-sequence arg)
                                     :items '(:type "string"))
                        arg))
                    (gptel-tool-args tool))))))

(provide 'custom-magent-infra)
;;; custom-magent-infra.el ends here
