;;; custom-magent-infra.el --- Infraestrutura de baixo nível, resiliência e helpers portáteis -*- lexical-binding: t; -*-

;;; Commentary:
;; Este módulo provê a infraestrutura central do ecossistema de agentes IA.
;; Inclui:
;;   - Helpers portáteis de string (funcionam em batch -Q sem subr-x)
;;   - Macro with-temp-file-buffer para testes ERT sem leak
;;   - Sanitização de AST, correções de aridade para backends LLM (Gemini)
;;   - Supressão de dumps longos no log
;;   - Circuit Breaker para garantir robustez e fail-fast em requisições de rede

;;; Code:

(require 'cl-lib)

(declare-function magent-llm-gptel--sanitize-info "magent-llm-gptel")
(declare-function magent-llm-gptel--managed-info-p "magent-llm-gptel")
(declare-function gptel-fsm-info "gptel")
(declare-function gptel-tool-args "gptel")

;; ── Helpers Portáteis (batch -Q sem subr-x) ──────────────────────────

(defun +carlos/magent--string-trim-left (s)
  "Remove espaços em branco à esquerda de S.
Portável: funciona em batch -Q sem \\=(require \\='subr-x)."
  (if (string-match "\\`[ \t\n\r]+" s)
      (substring s (match-end 0))
    s))

(defun +carlos/magent--string-trim-right (s)
  "Remove espaços em branco à direita de S.
Portável: funciona em batch -Q sem \\=(require \\='subr-x)."
  (if (string-match "[ \t\n\r]+\\'" s)
      (substring s 0 (match-beginning 0))
    s))

(defun +carlos/magent--string-trim (s)
  "Remove espaços em branco nas duas pontas de S.
Portável: funciona em batch -Q sem \\=(require \\='subr-x)."
  (+carlos/magent--string-trim-right
   (+carlos/magent--string-trim-left s)))

(defmacro with-temp-file-buffer (suffix &rest body)
  "Executa BODY em buffer file-backed temporário.
Cria arquivo temporário com SUFFIX, abre via `find-file-noselect',
executa BODY com o buffer corrente, e limpa arquivo + buffer ao final.
Evita memory leak em testes ERT em lote."
  (declare (indent 1) (debug t))
  (let ((temp-file (make-symbol "tmpfile"))
        (temp-buf (make-symbol "tmpbuf")))
    `(let* ((,temp-file (make-temp-file "magent-test-" nil ,suffix))
            (,temp-buf (find-file-noselect ,temp-file)))
       (unwind-protect
           (with-current-buffer ,temp-buf
             ,@body)
         (when (buffer-live-p ,temp-buf)
           (with-current-buffer ,temp-buf (set-buffer-modified-p nil))
           (kill-buffer ,temp-buf))
          (when (file-exists-p ,temp-file)
            (delete-file ,temp-file))))))

;; ── Project Root Resolution (batch-safe) ────────────────────────────

(defun +carlos/magent-project-root ()
  "Retorna a raiz do projeto atual, com fallback seguro para batch.
Cadeia: project-root → vc-root-dir → default-directory.
Funciona em batch -Q sem pacotes carregados."
  (cond
   ((and (fboundp 'project-root)
         (fboundp 'project-current)
         (project-current))
    (project-root (project-current)))
   ((fboundp 'vc-root-dir)
    (vc-root-dir))
   (t default-directory)))

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
  (if (not format-string)
      (apply orig-fn format-string args)
    (let* ((text (condition-case nil
                     (apply #'format format-string args)
                   (error format-string)))
           (is-error (and (stringp text) (string-match-p "\\(?:Error\\|Warning\\|error\\|timeout\\|Stopped\\|Wrong type\\|DEBUG\\)" text))))
      (if (and (not is-error)
               (stringp text)
               (> (length text) +carlos/magent-message-max-len))
          text  ;; retorna o texto mas não chama message (suprimido do *Messages*)
        (apply orig-fn format-string args)))))

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

;; ── Resiliência de Tool Results e Proteção do Sentinel ───────────────

(defun +carlos/magent-tool-result-require-around (orig-fn value &optional name call-id)
  "Normaliza qualquer retorno de ferramenta para um `magent-tool-result' válido.
Se VALUE não for uma struct `magent-tool-result', em vez de sinalizar
`wrong-type-argument' e derrubar o Sentinel da FSM, encapsula VALUE
graciosamente em um resultado estruturado com status \='completed (ou \='failed
se for erro/sinal de exceção)."
  (condition-case err
      (if (and (fboundp 'magent-tool-result-p) (magent-tool-result-p value))
          (funcall orig-fn value name call-id)
        (if (fboundp 'magent-tool-result-create)
            (magent-tool-result-create
             :name name
             :call-id call-id
             :status 'completed
             :success t
             :output (if (stringp value) value (format "%S" value)))
          value))
    (error
     (let ((msg (format "Tool execution error in '%s': %s"
                        (or name "unknown") (error-message-string err))))
       (if (fboundp 'magent-tool-result-create)
           (magent-tool-result-create
            :name name
            :call-id call-id
            :status 'failed
            :success nil
            :output msg
            :error msg)
         msg)))))

(with-eval-after-load 'magent-protocol
  (advice-add 'magent-tool-result-require
              :around #'+carlos/magent-tool-result-require-around))

(provide 'custom-magent-infra)
;;; custom-magent-infra.el ends here
