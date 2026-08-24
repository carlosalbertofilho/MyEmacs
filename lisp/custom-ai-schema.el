;;; custom-ai-schema.el --- Structured Outputs for gptel -*- lexical-binding: t; -*-

;;; Commentary:
;; Implementa a infraestrutura de Structured Outputs via JSON Schema.
;; Fornece uma DSL declarativa, um Registry de schemas nomeados e conversores
;; para o formato compatível com as APIs suportadas pelo gptel (OpenAI, Gemini, etc).

;;; Code:

(require 'json)
(require 'cl-lib)

;; ── Módulo 3: Registry ───────────────────────────────────────────────

(defvar gptel-schema--registry (make-hash-table :test #'eq)
  "Registro global de schemas nomeados.")

(defvar-local gptel-schema-active nil
  "Schema ativo para o buffer atual.
Pode ser um símbolo (buscado no registry) ou uma plist (schema direto).")

(defun gptel-schema-register (name spec)
  "Registra um schema SPEC sob o identificador NAME."
  (puthash name spec gptel-schema--registry)
  name)

(defun gptel-schema-get (name)
  "Recupera o schema registrado sob NAME."
  (gethash name gptel-schema--registry))

(defun gptel-schema-list ()
  "Lista os identificadores de todos os schemas registrados."
  (let ((keys nil))
    (maphash (lambda (k _v) (push k keys)) gptel-schema--registry)
    keys))

(defun gptel-schema-remove (name)
  "Remove o schema NAME do registry."
  (remhash name gptel-schema--registry))

(defun gptel-schema-set (&optional schema-name)
  "Define interativamente o schema ativo para o buffer atual."
  (interactive
   (list
    (let ((schemas (mapcar #'symbol-name (gptel-schema-list))))
      (when schemas
        (intern (completing-read "Selecione o Schema: " schemas nil t))))))
  (setq gptel-schema-active schema-name)
  (message "Schema ativo definido para: %s" (or schema-name "Nenhum")))


;; ── Módulo 1: DSL ────────────────────────────────────────────────────

(defun gptel-schema--normalize (spec)
  "Normaliza a especificação SPEC para um formato canônico plist."
  ;; Por enquanto, retorna a própria SPEC assumindo que já está correta.
  ;; Implementação futura pode expandir shorthands (e.g. 'string -> '(:type "string")).
  spec)

(defmacro gptel-schema-define (name &rest body)
  "Define um novo schema com NAME usando as propriedades em BODY.
Automaticamente normaliza e registra o schema."
  (declare (indent 1))
  `(gptel-schema-register ',name (gptel-schema--normalize ',body)))


;; ── Módulo 2: Generator ──────────────────────────────────────────────

(defun gptel-schema--emit-type (type-spec)
  "Converte um nó TYPE-SPEC em um hash-table JSON Schema."
  (let ((ht (make-hash-table :test #'equal)))
    (cl-loop for (k v) on type-spec by #'cddr
             do
             (let ((json-key (substring (symbol-name k) 1))) ; remove ":"
               (cond
                ((eq k :type)
                 (puthash "type" (if (symbolp v) (symbol-name v) v) ht))
                ((eq k :properties)
                 (puthash "properties" (gptel-schema--emit-properties v) ht))
                ((eq k :items)
                 (puthash "items" (gptel-schema--emit-type v) ht))
                (t
                 (puthash json-key v ht)))))
    ht))

(defun gptel-schema--emit-properties (props)
  "Converte uma alist PROPS no objeto `properties' do JSON Schema."
  (let ((ht (make-hash-table :test #'equal)))
    (dolist (prop props)
      ;; Exemplo de prop: (:name (:type string :description "Full name"))
      (let ((prop-name (substring (symbol-name (car prop)) 1))
            (prop-spec (cadr prop)))
        (puthash prop-name (gptel-schema--emit-type prop-spec) ht)))
    ht))

(defun gptel-schema--to-json-schema (spec &optional _backend)
  "Converte a SPEC normalizada para o payload final em hash-table."
  (let ((root (make-hash-table :test #'equal)))
    (puthash "name" "gptel_schema" root)
    (puthash "schema" (gptel-schema--emit-type spec) root)
    (puthash "strict" t root)
    root))

(defun gptel-schema--to-json-string (schema-ht)
  "Serializa SCHEMA-HT para string JSON."
  (json-serialize schema-ht :null-object nil :false-object :json-false))

;; ── Módulo 4: Request Interceptor (Advices) ──────────────────────────

(defun gptel-schema--resolve-active ()
  "Resolve o schema ativo para a sua especificação plist."
  (cond
   ((plistp gptel-schema-active) gptel-schema-active)
   ((symbolp gptel-schema-active) (gptel-schema-get gptel-schema-active))
   (t nil)))

(defun gptel-schema--openai-format (spec)
  "Cria a estrutura de response_format para OpenAI a partir da SPEC."
  (let ((ht (make-hash-table :test #'equal)))
    (puthash "type" "json_schema" ht)
    (puthash "json_schema" (gptel-schema--to-json-schema spec) ht)
    ht))

(defun gptel-schema--anthropic-inject (payload spec)
  "Injeta o schema como uma tool obrigatória para o Anthropic no PAYLOAD."
  (let* ((tools (or (plist-get payload :tools) (make-vector 0 nil)))
         (schema-tool (make-hash-table :test #'equal)))
    (puthash "name" "gptel_schema" schema-tool)
    (puthash "description" "Output schema" schema-tool)
    (puthash "input_schema" (gptel-schema--emit-type spec) schema-tool)
    (setq tools (vconcat tools (vector schema-tool)))
    (setq payload (plist-put payload :tools tools))
    (setq payload (plist-put payload :tool_choice
               (let ((ht (make-hash-table :test #'equal)))
                 (puthash "type" "tool" ht)
                 (puthash "name" "gptel_schema" ht)
                 ht)))
    payload))

(defun gptel-schema--gemini-inject (payload spec)
  "Injeta o schema no generationConfig do Gemini no PAYLOAD."
  (let ((gen-config (or (plist-get payload :generationConfig)
                        (make-hash-table :test #'equal))))
    (puthash "responseMimeType" "application/json" gen-config)
    (puthash "responseSchema" (gptel-schema--emit-type spec) gen-config)
    (setq payload (plist-put payload :generationConfig gen-config))
    payload))

(defun gptel-schema--inject-response-format (orig-fn backend &rest args)
  "Around advice: injeta response_format no payload se schema ativo."
  (let ((payload (apply orig-fn backend args)))
    (when-let* ((schema (gptel-schema--resolve-active)))
      (let ((backend-type (type-of backend)))
        (cond
         ;; OpenAI
         ((or (eq backend-type 'gptel-openai)
              (eq backend-type 'gptel-azure))
          (setq payload (plist-put payload :response_format
                                   (gptel-schema--openai-format schema))))
         ;; Anthropic
         ((eq backend-type 'gptel-anthropic)
          (setq payload (gptel-schema--anthropic-inject payload schema)))
         ;; Gemini
         ((eq backend-type 'gptel-gemini)
          (setq payload (gptel-schema--gemini-inject payload schema))))))
    payload))

;; ── Módulo 6: Validação de Resposta ──────────────────────────────────

(defun gptel-schema--validate-type (value type-spec)
  "Verifica se VALUE corresponde ao TYPE-SPEC."
  (let ((type (if (symbolp type-spec)
                  type-spec
                (plist-get type-spec :type))))
    (pcase type
      ('string (stringp value))
      ('integer (integerp value))
      ('number (numberp value))
      ('boolean (memq value '(t nil :json-false)))
      ('array (and (listp value)
                   (let ((item-spec (plist-get type-spec :items)))
                     (cl-every (lambda (v) (gptel-schema--validate-type v item-spec)) value))))
      ('object (and (listp value)
                    (gptel-schema--validate-response value type-spec)))
      (_ t))))

(defun gptel-schema--validate-response (data schema)
  "Verifica se DATA está em conformidade com o SCHEMA."
  (let ((props (plist-get schema :properties))
        (reqs (plist-get schema :required))
        (valid t))
    ;; Verifica required
    (dolist (req reqs)
      (let ((key (intern (concat ":" (symbol-name req)))))
        (unless (plist-member data key)
          (message "gptel-schema: campo obrigatório ausente - %s" req)
          (setq valid nil))))
    ;; Verifica tipos
    (cl-loop for (k v) on data by #'cddr
             do
             (let ((prop-spec (cadr (assoc k props))))
               (if prop-spec
                   (unless (gptel-schema--validate-type v prop-spec)
                     (message "gptel-schema: tipo inválido para o campo %s" k)
                     (setq valid nil))
                 (when (plist-get schema :strict)
                   (message "gptel-schema: campo extra não permitido - %s" k)
                   (setq valid nil)))))
    valid))

;; ── Módulo 5: Response Interceptor & Parser ──────────────────────────

(defun gptel-schema--extract-json (raw-response)
  "Extrai o JSON da RAW-RESPONSE."
  (cond
   ((string-match "```json\n\\(.*?\\)\n```" raw-response)
    (match-string 1 raw-response))
   ((string-match "^{.*}$" raw-response)
    raw-response)
   (t raw-response)))

(defun gptel-schema--format-for-display (data _schema)
  "Formata DATA para exibição no buffer."
  (concat "```json\n"
          (json-serialize data :null-object nil :false-object :json-false)
          "\n```\n"))

(defun gptel-schema--try-parse (response schema)
  "Tenta parsear RESPONSE de acordo com o SCHEMA."
  (when-let* ((json-str (gptel-schema--extract-json response)))
    (condition-case nil
        (let ((parsed (json-parse-string json-str
                                         :object-type 'plist
                                         :array-type 'list
                                         :null-object nil
                                         :false-object :json-false)))
          (when (gptel-schema--validate-response parsed schema)
            parsed))
      (error nil))))

(defvar gptel-schema-post-parse-hook nil
  "Hook executado com a resposta parseada e o schema.")

(defun gptel-schema--parse-response (response)
  "Filter-return: parseia JSON estruturado se schema ativo."
  (if-let* ((schema (gptel-schema--resolve-active))
            (json-str (gptel-schema--extract-json response)))
      (condition-case err
          (let* ((parsed (json-parse-string json-str
                                            :object-type 'plist
                                            :array-type 'list
                                            :null-object nil
                                            :false-object :json-false))
                 (valid (gptel-schema--validate-response parsed schema)))
            (if valid
                (progn
                  (run-hook-with-args 'gptel-schema-post-parse-hook parsed schema)
                  (put-text-property 0 (length response) 'gptel-structured-data parsed response)
                  (gptel-schema--format-for-display parsed schema))
              (message "gptel-schema: resposta não conformou ao schema")
              response))
        (error (message "gptel-schema: falha no parse JSON - %s" err)
               response))
    response))

(defun gptel-schema--capture-callback (orig-fn &rest args)
  "Wrappeia callback para entregar dados estruturados."
  (if-let* ((schema (gptel-schema--resolve-active))
            (callback (plist-get args :callback)))
      (let ((wrapped-cb
             (lambda (response info)
               (let ((structured (gptel-schema--try-parse response schema)))
                 (funcall callback
                          (or structured response)
                          (plist-put info :structured-p (not (null structured))))))))
        (apply orig-fn (plist-put args :callback wrapped-cb)))
    (apply orig-fn args)))

(with-eval-after-load 'gptel
  (advice-add 'gptel--request-data :around #'gptel-schema--inject-response-format)
  (advice-add 'gptel--parse-response :filter-return #'gptel-schema--parse-response)
  (advice-add 'gptel-request :around #'gptel-schema--capture-callback))

(provide 'custom-ai-schema)
;;; custom-ai-schema.el ends here
