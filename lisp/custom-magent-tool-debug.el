;;; custom-magent-tool-debug.el --- Magent Tool for DAP (dape) -*- lexical-binding: t; -*-

;;; Commentary:
;; Ferramenta do Magent para orquestrar o depurador nativo via `dape`.
;; Permite ao agente iniciar sessões, colocar breakpoints e avaliar expressões.
;; (Faz parte da Fase 5: Onisciência do Agente)

;;; Code:

(require 'dape nil t)
(require 'custom-magent-infra)
(require 'trace)

;; Garantir fallback para projeto ao rodar em batch (solução parcial até a Fase 6)
(defun +carlos/--magent-debug-ensure-project-root ()
  "Retorna a raiz do projeto atual. Se em batch, tenta fallbacks."
  (+carlos/magent-project-root))

(defun +carlos/magent-tool-debug (action &optional arg1 arg2)
  "Orquestra o depurador dape para o Magent.
ACTION: `start', `stop', `breakpoint' (arg1=file, arg2=line), `eval'."
  (unless (featurep 'dape)
    (error "Pacote dape não está carregado. A depuração não está disponível"))
  
  (let ((root (+carlos/--magent-debug-ensure-project-root)))
    (pcase action
      ("start"
       ;; arg1 deve ser a config do dape (ex: 'python', 'go', 'node')
       (unless arg1 (error "É necessário informar a configuração do dape para iniciar"))
       (let ((default-directory root)
             (config (alist-get (intern arg1) dape-configs)))
         (unless config
           (error "Configuração dape '%s' não encontrada" arg1))
         (dape config)
         "Sessão de depuração iniciada."))
      
      ("stop"
       (dape-quit)
       "Sessão de depuração encerrada.")
       
      ("continue"
       (unless (dape--live-connection 'stopped)
         (error "O depurador já está rodando ou não foi iniciado"))
       (dape-continue (dape--live-connection 'stopped))
       "Execução continuada.")
       
      ("pause"
       (unless (dape--live-connection 'running)
         (error "O depurador já está pausado ou não foi iniciado"))
       (dape-pause (dape--live-connection 'running))
       "Execução pausada.")
      
      ("breakpoint"
       (unless (and arg1 arg2) (error "Para 'breakpoint' forneça arquivo e linha"))
       (let ((file (expand-file-name arg1 root))
             (line (if (stringp arg2) (string-to-number arg2) arg2)))
         (unless (file-exists-p file)
           (error "Arquivo %s não encontrado para breakpoint" file))
         (with-current-buffer (find-file-noselect file)
           (save-excursion
             (goto-char (point-min))
             (forward-line (1- line))
             (dape-breakpoint-toggle)
             (format "Breakpoint alternado em %s:%d" file line)))))
             
      ("eval"
       (unless arg1 (error "É necessário informar a expressão para avaliar"))
       (unless (dape--live-connection 'stopped)
         (error "O depurador precisa estar pausado para avaliar expressões"))
       (dape-evaluate-expression (dape--live-connection 'stopped) arg1)
       (format "Expressão avaliada no console. Verifique o buffer *dape-repl*."))
       
      (_ (error "Ação '%s' desconhecida em magent-tool-debug" action)))))

(defvar magent-tools-catalog)
(defvar magent-enable-tools)
(defvar +carlos/magent-tool-debug)

;; Registra a ferramenta: cria o struct gptel-tool, o publica no catálogo
;; do Magent (roteamento por :permission) e expõe via gptel-tools.
(with-eval-after-load 'gptel
  (setq +carlos/magent-tool-debug
        (gptel-make-tool
         :name "magent_debug"
         :description "Orquestra o depurador nativo via dape. Use 'start' (arg1=config_name), 'stop', 'continue', 'pause', 'breakpoint' (arg1=filepath, arg2=line_number), ou 'eval' (arg1=expression)."
         :function #'+carlos/magent-tool-debug
         :category "debugging")))

(with-eval-after-load 'magent-tools
  (when (and (boundp 'magent-tools-catalog)
             +carlos/magent-tool-debug)
    (add-to-list 'magent-tools-catalog
                 `(:name "magent_debug" :tool ,+carlos/magent-tool-debug
                         :permission magent_debug))))

(with-eval-after-load 'magent-config
  (when (boundp 'magent-enable-tools)
    (add-to-list 'magent-enable-tools 'magent_debug)))

;; ── Introspecção e Avaliação Dinâmica Elisp ───────────────────────────

(defvar +carlos/magent-tool-elisp-eval nil)

(defun +carlos/magent-tool-elisp-eval (form-str &optional macroexpand-p _reason)
  "Avalia FORM-STR de forma segura e retorna o resultado ou erro.
Se MACROEXPAND-P for não-nil e diferente de \"false\"/\"0\", expande a
forma usando `macroexpand' sem executá-la."
  (if (or (null form-str) (string-empty-p form-str))
      "Erro: form-str não pode ser vazia."
    (condition-case err
        (let* ((parsed (read-from-string form-str))
               (form (car parsed))
               (expand (and macroexpand-p
                            (not (member macroexpand-p '("0" "false" "nil" nil))))))
          (if expand
              (format "Expansão da macro:\n%S" (macroexpand form))
            (let* ((out-buf (generate-new-buffer " *elisp-eval-out*"))
                   (standard-output out-buf)
                   (res (eval form t))
                   (out-str (with-current-buffer out-buf (buffer-string))))
              (kill-buffer out-buf)
              (if (string-empty-p out-str)
                  (format "%S" res)
                (format "Stdout:\n%s\nRetorno:\n%S" out-str res)))))
      (error
       (format "Erro de avaliação Elisp: %s" (error-message-string err))))))

(with-eval-after-load 'gptel
  (setq +carlos/magent-tool-elisp-eval
        (gptel-make-tool
         :name "elisp_eval"
         :description "Avalia uma expressão Elisp FORM-STR de forma segura ou a expande se MACROEXPAND-P for verdadeiro. Retorna stdout, valor e erros."
         :args '((:name "form-str" :type string)
                 (:name "macroexpand-p" :type boolean)
                 (:name "reason" :type string))
         :function #'+carlos/magent-tool-elisp-eval
         :category "debugging")))

(with-eval-after-load 'magent-tools
  (when (and (boundp 'magent-tools-catalog)
             +carlos/magent-tool-elisp-eval)
    (add-to-list 'magent-tools-catalog
                 `(:name "elisp_eval" :tool ,+carlos/magent-tool-elisp-eval
                         :permission elisp_eval))))

(with-eval-after-load 'magent-config
  (when (boundp 'magent-enable-tools)
    (add-to-list 'magent-enable-tools 'elisp_eval)))

;; ── Introspecção de Macros e AST ──────────────────────────────────────

(defvar +carlos/magent-tool-elisp-macroexpand nil)

(defun +carlos/magent-tool-elisp-macroexpand (form-str &optional step-only-p _reason)
  "Expande a macro Elisp contida em FORM-STR e a formata com `pp-to-string'.
Se STEP-ONLY-P for não-nil e não-\"false\", usa `macroexpand-1' (um único passo).
Caso contrário, usa `macroexpand-all' para expansão completa da forma.
Retorna o código Elisp expandido ou mensagem de erro."
  (if (or (null form-str) (string-empty-p form-str))
      "Erro: form-str não pode ser vazia."
    (condition-case err
        (let* ((parsed (read-from-string form-str))
               (form (car parsed))
               (one-step (and step-only-p (not (member step-only-p '("0" "false" "nil" nil)))))
               (expanded (if one-step
                             (macroexpand-1 form)
                           (macroexpand-all form))))
          (format "Expansão de macro (%s):\n%s"
                  (if one-step "macroexpand-1" "macroexpand-all")
                  (pp-to-string expanded)))
      (error
       (format "Erro ao expandir macro Elisp: %s" (error-message-string err))))))

(with-eval-after-load 'gptel
  (setq +carlos/magent-tool-elisp-macroexpand
        (gptel-make-tool
         :name "elisp_macroexpand"
         :description "Expande uma macro Elisp FORM-STR (usando macroexpand-all ou macroexpand-1 se STEP-ONLY-P for verdadeiro). Retorna o código resultante formatado."
         :args '((:name "form-str" :type string)
                 (:name "step-only-p" :type boolean)
                 (:name "reason" :type string))
         :function #'+carlos/magent-tool-elisp-macroexpand
         :category "debugging")))

(with-eval-after-load 'magent-tools
  (when (and (boundp 'magent-tools-catalog)
             +carlos/magent-tool-elisp-macroexpand)
    (add-to-list 'magent-tools-catalog
                 `(:name "elisp_macroexpand" :tool ,+carlos/magent-tool-elisp-macroexpand
                         :permission elisp_macroexpand))))

(with-eval-after-load 'magent-config
  (when (boundp 'magent-enable-tools)
    (add-to-list 'magent-enable-tools 'elisp_macroexpand)))

;; ── Instrumentação e Rastreamento em Tempo de Execução ────────────────

(defvar +carlos/magent-tool-elisp-trace nil)

(defun +carlos/magent-tool-elisp-trace (action &optional symbol-str _reason)
  "Controla rastreamento nativo de execução Elisp via `trace-function'.
ACTION pode ser `trace' (inicia rastreamento de SYMBOL-STR),
`untrace' (cessa rastreamento de SYMBOL-STR),
`untrace_all' (remove todos os rastreamentos ativos),
`show_trace' (retorna o conteúdo recente do buffer de trace), ou
`clear_trace' (limpa o buffer de trace)."
  (require 'trace)
  (pcase (and action (downcase (string-trim action)))
    ("trace"
     (if (or (null symbol-str) (string-empty-p symbol-str))
         "Erro: informe o símbolo da função a rastrear em symbol-str."
       (let ((sym (intern-soft symbol-str)))
         (if (and sym (fboundp sym))
             (progn
               (trace-function sym)
               (format "Rastreamento ativado para a função `%s'. As chamadas serão gravadas no buffer de trace." sym))
           (format "Erro: função `%s' não encontrada ou não vinculada." symbol-str)))))
    ("untrace"
     (if (or (null symbol-str) (string-empty-p symbol-str))
         "Erro: informe o símbolo da função em symbol-str para desativar rastreamento."
       (let ((sym (intern-soft symbol-str)))
         (if sym
             (progn
               (untrace-function sym)
               (format "Rastreamento desativado para `%s'." sym))
           (format "Erro: símbolo `%s' inválido." symbol-str)))))
    ("untrace_all"
     (untrace-all)
     "Todos os rastreamentos de funções foram desativados.")
    ("show_trace"
     (let ((buf (get-buffer "*trace-output*")))
       (if (and buf (buffer-live-p buf))
           (with-current-buffer buf
             (let ((content (buffer-string)))
               (if (string-empty-p (string-trim content))
                   "Buffer de trace (*trace-output*) está vazio."
                 (format "Trace recente:\n%s" content))))
         "Nenhum buffer de trace (*trace-output*) ativo no momento.")))
    ("clear_trace"
     (let ((buf (get-buffer "*trace-output*")))
       (when (and buf (buffer-live-p buf))
         (with-current-buffer buf (erase-buffer)))
       "Buffer de trace limpo."))
    (_
     "Ação inválida. Use 'trace', 'untrace', 'untrace_all', 'show_trace' ou 'clear_trace'.")))

(with-eval-after-load 'gptel
  (setq +carlos/magent-tool-elisp-trace
        (gptel-make-tool
         :name "elisp_trace"
         :description "Controla o rastreamento em tempo de execução de funções Elisp via trace-function. Ações: 'trace' (com symbol-str), 'untrace', 'untrace_all', 'show_trace', 'clear_trace'."
         :args '((:name "action" :type string)
                 (:name "symbol-str" :type string)
                 (:name "reason" :type string))
         :function #'+carlos/magent-tool-elisp-trace
         :category "debugging")))

(with-eval-after-load 'magent-tools
  (when (and (boundp 'magent-tools-catalog)
             +carlos/magent-tool-elisp-trace)
    (add-to-list 'magent-tools-catalog
                 `(:name "elisp_trace" :tool ,+carlos/magent-tool-elisp-trace
                         :permission elisp_trace))))

(with-eval-after-load 'magent-config
  (when (boundp 'magent-enable-tools)
    (add-to-list 'magent-enable-tools 'elisp_trace)))


(provide 'custom-magent-tool-debug)
;;; custom-magent-tool-debug.el ends here
