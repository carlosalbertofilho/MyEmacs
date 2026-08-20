;;; custom-magent-buffer.el --- Magent driver de buffer vivo (Fase B/D4) -*- lexical-binding: t; -*-

;;; Commentary:
;; Ferramentas do perfil coder (Operador de Buffer Vivo) do Magent — Etapa C
;; item 6 (Fase B) e D4.  Mutações em buffers abertos do Emacs:
;;   buffer_insert            insere texto em point ou (line, column)
;;   buffer_replace_region    substitui região (linhas inteiras, range exato
;;                            ou região ativa)
;;   buffer_undo              desfaz a última mudança do buffer
;; e sensores:
;;   lsp_hover                hover do Eglot + identificador no ponto
;;   describe_elisp_symbol    documentação/valor/arglist de símbolo Elisp
;;
;; Implementa o contrato de sessão "um dono do buffer por vez": mantém um
;; baseline de `buffer-chars-modified-tick' por buffer em
;; `+carlos/magent-buffer-session'.  Mutações adotam o baseline na primeira
;; operação e falham com buffer_conflict quando o tick atual difere do
;; baseline (edição manual do usuário entre chamadas do driver).  Um advice
;; em `magent-tools--read-buffer' adota o baseline quando o modelo lê o
;; buffer vivo via read_buffer, e `+carlos/magent-buffer-reset-session' (chamado
;; pelo reset da FSM) libera a sessão — coordenado com o cancelamento pela FSM.
;;
;; Contrato de invocação (magent): argumentos posicionais na ordem do argspec,
;; sem o arg display-only "reason"; opcionais omitidos chegam como nil.
;; Resultados via `+carlos/magent-tool-result' (definido em custom-magent-tools).

;;; Code:

(require 'cl-lib)

(defvar magent-enable-tools)
(defvar magent-tools-catalog)
(declare-function magent-tools--resolve-path "magent-tools" (path))
(declare-function magent-tools--read-buffer "magent-tools" (callback path &optional start-line line-count))
(declare-function +carlos/magent-tool-result "custom-magent-tools" (payload &optional error))
(declare-function eglot-managed-p "eglot" (&optional buffer))
(declare-function eglot-hover "eglot" ())
(declare-function eglot--hover-contents "eglot" (hover))
(declare-function help-function-arglist "help-fns" (fn))

;; ── Contrato de sessão: ownership por buffer ──────────────────────────
;; A chave de cada entrada é o nome do buffer e o valor é o tick observado
;; na última leitura (read_buffer) ou mutação (buffer_*) do driver.

(defvar +carlos/magent-buffer-session nil
  "Alist (BUFFER-NAME . BASELINE-TICK) dos buffers sob o driver do Magent.
BASELINE-TICK é o `buffer-chars-modified-tick' observado na última leitura
ou mutação do driver.  Mutações falham com `user-error' buffer_conflict
quando o tick atual difere do baseline — edição externa ao driver (manual)
entre chamadas.  Resetado por `+carlos/magent-buffer-reset-session'.")

(defun +carlos/magent-buffer--baseline (buf tick)
  "Registra ou atualiza o baseline de BUF para TICK."
  (let* ((name (buffer-name buf))
         (entry (assoc name +carlos/magent-buffer-session)))
    (if entry
        (setcdr entry tick)
      (setq +carlos/magent-buffer-session
            (cons (cons name tick) +carlos/magent-buffer-session))))
  tick)

(defun +carlos/magent-buffer-adopt (buf)
  "Adota BUF no contrato de sessão com o baseline no tick atual.
Chamado pelo advice do read_buffer para coordenar o estado vivo lido."
  (+carlos/magent-buffer--baseline
   buf (with-current-buffer buf (buffer-chars-modified-tick))))

(defun +carlos/magent-buffer-sync (buf)
  "Atualiza o baseline de BUF para o tick atual após mutação do driver."
  (+carlos/magent-buffer--baseline
   buf (with-current-buffer buf (buffer-chars-modified-tick))))

(defun +carlos/magent-buffer-ensure-ownership (buf)
  "Verifica/adota o contrato de dono único para BUF.
Sem baseline registrado, adota o tick atual.  Com baseline, falha com
`user-error' buffer_conflict quando o tick atual difere (edição fora do
driver desde a última leitura/mutação)."
  (let* ((name (buffer-name buf))
         (entry (assoc name +carlos/magent-buffer-session))
         (tick (with-current-buffer buf (buffer-chars-modified-tick))))
    (if entry
        (unless (= (cdr entry) tick)
          (user-error (concat "buffer_conflict: %S foi modificado fora do "
                              "driver desde a última operação; chame "
                              "read_buffer novamente para re-sincronizar "
                              "antes de editar")
                      name))
      (setq +carlos/magent-buffer-session
            (cons (cons name tick) +carlos/magent-buffer-session))))
  t)

(defun +carlos/magent-buffer-reset-session ()
  "Limpa o contrato de sessão de buffers do driver do Magent.
Coordenado com o cancelamento pela FSM: um novo turno/sessão recomeça o
contrato do zero (re-adoção na primeira leitura/mutação)."
  (setq +carlos/magent-buffer-session nil))

(defun +carlos/magent-buffer-resolve (buffer-name)
  "Resolve BUFFER-NAME (string) para um buffer vivo, ou o buffer atual.
Sinaliza `user-error' buffer_not_found quando BUFFER-NAME não existe."
  (if (and buffer-name (not (string-empty-p buffer-name)))
      (let ((buf (get-buffer buffer-name)))
        (unless (buffer-live-p buf)
          (user-error "buffer_not_found: %S não é um buffer vivo" buffer-name))
        buf)
    (current-buffer)))

;; ── Helpers de coordenadas (linhas 1-based, colunas 0-based) ──────────

(defun +carlos/magent-buffer-point-at (buf line &optional column)
  "Retorna o ponto em BUF correspondente a LINE (1-based) e COLUMN (0-based).
LINE é limitado à última linha e COLUMN ao fim da linha."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (let ((line (max 1 (or line 1))))
        (forward-line (1- line))
        (when (> (or column 0) 0)
          (forward-char (min (or column 0)
                             (- (line-end-position) (point)))))
        (point)))))

(defun +carlos/magent-buffer--region (buf start-line start-column end-line end-column)
  "Retorna (START . END) do range em BUF a partir das coordenadas.
END-COLUMN nil → modo linhas inteiras: range START-LINE..END-LINE (inclusive),
com END caindo no início da linha seguinte.  END-COLUMN inteiro → range exato
START-LINE,START-COLUMN..END-LINE,END-COLUMN.  START-COLUMN default 0;
END-LINE default START-LINE.  Sinaliza `user-error' em range invertido."
  (let* ((sl (max 1 (or start-line 1)))
         (el (max sl (or end-line sl)))
         (start (if (integerp end-column)
                    (with-current-buffer buf
                      (+carlos/magent-buffer-point-at buf sl start-column))
                  (with-current-buffer buf
                    (save-excursion
                      (goto-char (point-min))
                      (forward-line (1- sl))
                      (point)))))
         (end (if (integerp end-column)
                  (with-current-buffer buf
                    (+carlos/magent-buffer-point-at buf el end-column))
                (with-current-buffer buf
                  (save-excursion
                    (goto-char (point-min))
                    (forward-line el)
                    (point))))))
    (unless (<= start end)
      (user-error "Range inválido (buffer_invalid_range): start depois de end"))
    (cons start end)))

;; ── Handlers das tools ────────────────────────────────────────────────

(defun +carlos/magent-tool-buffer-insert (text &optional buffer line column _reason)
  "Handler da tool `buffer_insert'.
Insere TEXT no buffer vivo (BUFFER, ou o atual quando nil) no ponto atual,
ou em coordenadas LINE (1-based) e COLUMN (0-based).  _REASON é display-only
e descartado.  Aplica o contrato de sessão e retorna o JSON via
`+carlos/magent-tool-result'."
  (if (not (and text (not (string-empty-p text))))
      (+carlos/magent-tool-result nil "Parâmetro 'text' é obrigatório.")
    (condition-case err
        (let* ((buf (+carlos/magent-buffer-resolve buffer))
               (point (with-current-buffer buf
                        (if (integerp line)
                            (+carlos/magent-buffer-point-at buf line column)
                          (point)))))
          (+carlos/magent-buffer-ensure-ownership buf)
          (with-current-buffer buf
            (goto-char point)
            (insert text))
          (+carlos/magent-buffer-sync buf)
          (+carlos/magent-tool-result
           (list (cons "status" "success")
                 (cons "buffer" (buffer-name buf))
                 (cons "text_len" (length text))
                 (cons "line" (with-current-buffer buf
                                (line-number-at-pos point))))))
      (error (+carlos/magent-tool-result nil (error-message-string err))))))

(defun +carlos/magent-tool-buffer-replace-region
    (text &optional buffer start-line start-column end-line end-column _reason)
  "Handler da tool `buffer_replace_region'.
Substitui uma região do buffer vivo por TEXT.  Modos: (a) linhas inteiras —
START-LINE e (opcional) END-LINE, sem colunas; (b) range exato — START-LINE,
START-COLUMN, END-LINE e END-COLUMN; (c) região ativa — sem coordenadas e
sem BUFFER, usando a região do buffer atual.  _REASON é display-only e
descartado.  Aplica o contrato de sessão."
  (if (not (and text (not (string-empty-p text))))
      (+carlos/magent-tool-result nil "Parâmetro 'text' é obrigatório.")
    (condition-case err
        (let* ((buf (+carlos/magent-buffer-resolve buffer))
               (region (cond
                        ((integerp start-line)
                         (+carlos/magent-buffer--region
                          buf start-line start-column end-line end-column))
                        ((and (null buffer) (use-region-p))
                         (cons (region-beginning) (region-end)))
                        (t (user-error "Região requer start_line (buffer_replace_region) ou uma região ativa")))))
          (+carlos/magent-buffer-ensure-ownership buf)
          (with-current-buffer buf
            (delete-region (car region) (cdr region))
            (goto-char (car region))
            (insert text))
          (+carlos/magent-buffer-sync buf)
          (+carlos/magent-tool-result
           (list (cons "status" "success")
                 (cons "buffer" (buffer-name buf))
                 (cons "text_len" (length text))
                 (cons "start_line" (with-current-buffer buf
                                      (line-number-at-pos (car region)))))))
      (error (+carlos/magent-tool-result nil (error-message-string err))))))

(defun +carlos/magent-tool-buffer-undo (&optional buffer _reason)
  "Handler da tool `buffer_undo'.
Desfaz a última mudança do buffer vivo (BUFFER, ou o atual quando nil).
Retorna status \"info\" quando não há o que desfazer.  _REASON é display-only
e descartado."
  (condition-case err
      (let* ((buf (+carlos/magent-buffer-resolve buffer))
             (has-undo (with-current-buffer buf (cdr buffer-undo-list))))
        (if (not has-undo)
            (+carlos/magent-tool-result
             (list (cons "status" "info")
                   (cons "buffer" (buffer-name buf))
                   (cons "message" "Nada para desfazer no buffer.")))
          (with-current-buffer buf
            (undo-start)
            (undo-more 1))
          (+carlos/magent-buffer-sync buf)
          (+carlos/magent-tool-result
           (list (cons "status" "success")
                 (cons "buffer" (buffer-name buf))
                 (cons "message" "Desfazido.")))))
    (error (+carlos/magent-tool-result nil (error-message-string err)))))

(defun +carlos/magent-tool-buffer-save (&optional buffer _reason)
  "Handler da tool `buffer_save'.
Persiste o conteúdo validado do buffer vivo no disco.  BUFFER é o buffer
alvo (ou o atual quando nil).  O buffer DEVE estar visitando um arquivo
\(=buffer-file-name= não-nil\); buffers scratch/ephemeral não podem ser
 salvos.  Retorna o caminho do arquivo salvo e o tamanho em bytes.
_REASON é display-only e descartado."
  (condition-case err
      (let ((buf (+carlos/magent-buffer-resolve buffer)))
        (if (not (buffer-file-name buf))
            (+carlos/magent-tool-result
             (list (cons "status" "error")
                   (cons "buffer" (buffer-name buf))
                   (cons "message" "Buffer não está associado a um arquivo. Use write_file para arquivos novos.")))
          (+carlos/magent-buffer-ensure-ownership buf)
          (let ((file (buffer-file-name buf))
                (bytes (with-current-buffer buf (buffer-size))))
            (with-current-buffer buf
              (save-buffer))
            (+carlos/magent-tool-result
             (list (cons "status" "success")
                   (cons "buffer" (buffer-name buf))
                   (cons "file" file)
                   (cons "bytes" bytes))))))
    (error (+carlos/magent-tool-result nil (error-message-string err)))))

(defun +carlos/magent-eglot-hover-contents (hover)
  "Extrai os contents do eglot-hover HOVER (struct ou plist)."
  (cond
   ((and (fboundp 'eglot-hover-p) (eglot-hover-p hover)
         (fboundp 'eglot--hover-contents))
    (eglot--hover-contents hover))
   ((consp hover) hover)
   (t hover)))

(defun +carlos/magent-eglot-hover-render (contents)
  "Renderiza CONTENTS de um hover do Eglot como string única.
CONTENTS pode ser string, plist (markdown/plaintext :value ...), vector ou
lista de strings."
  (cond
   ((stringp contents) contents)
   ((and (consp contents) (stringp (plist-get contents :value)))
    (plist-get contents :value))
   ((or (vectorp contents) (listp contents))
    (mapconcat (lambda (x) (if (stringp x) x (format "%s" x)))
               (if (vectorp contents) (append contents nil) contents)
               "\n"))
   (t (format "%s" contents))))

(defun +carlos/magent-tool-lsp-hover (&optional buffer line column _reason)
  "Handler da tool `lsp_hover'.
Retorna o hover do Eglot no buffer vivo (BUFFER, ou o atual quando nil) em
coordenadas LINE (1-based) e COLUMN (0-based), default point, com o
identificador no ponto.  Sem servidor LSP retorna status \"info\" com backend
\"none\".  _REASON é display-only e descartado."
  (condition-case err
      (let* ((buf (+carlos/magent-buffer-resolve buffer))
             (result
              (with-current-buffer buf
                (save-excursion
                  (when (integerp line)
                    (goto-char (+carlos/magent-buffer-point-at buf line column)))
                  (let* ((identifier (or (thing-at-point 'symbol t) ""))
                         (managed (and (fboundp 'eglot-managed-p) (eglot-managed-p)))
                         (hover (and managed (fboundp 'eglot-hover) (eglot-hover))))
                    (cond
                     ((null managed)
                      (list (cons "status" "info")
                            (cons "identifier" identifier)
                            (cons "backend" "none")
                            (cons "message" "Nenhum servidor LSP (Eglot) gerenciando o buffer; use lsp_navigation para resolver o símbolo.")))
                     ((null hover)
                      (list (cons "status" "info")
                            (cons "identifier" identifier)
                            (cons "backend" "eglot")
                            (cons "message" "Eglot não retornou hover para o ponto.")))
                     (t (list (cons "status" "success")
                              (cons "identifier" identifier)
                              (cons "backend" "eglot")
                              (cons "hover" (+carlos/magent-eglot-hover-render
                                             (+carlos/magent-eglot-hover-contents hover)))))))))))
        (+carlos/magent-tool-result result))
    (error (+carlos/magent-tool-result nil (error-message-string err)))))

(defun +carlos/magent-truncate (str limit)
  "Trunca STR em LIMIT caracteres com reticências, se necessário."
  (if (and (stringp str) (> (length str) limit))
      (concat (substring str 0 limit) "...")
    str))

(defun +carlos/magent-tool-describe-elisp-symbol (symbol &optional _reason)
  "Handler da tool `describe_elisp_symbol'.
Descreve o símbolo Elisp SYMBOL: kind (function/variable/face/feature),
docstring, valor atual (truncado), arglist e arquivo de definição.  _REASON
é display-only e descartado."
  (if (not (and symbol (not (string-empty-p symbol))))
      (+carlos/magent-tool-result nil "Parâmetro 'symbol' é obrigatório.")
    (condition-case err
        (let* ((sym (intern symbol))
               (kind (cond ((fboundp sym) "function")
                           ((and (boundp sym) (not (memq sym '(nil t)))) "variable")
                           ((facep sym) "face")
                           ((featurep sym) "feature")
                           (t "unknown")))
               (doc (cond ((fboundp sym) (documentation sym))
                          ((and (boundp sym) (not (memq sym '(nil t))))
                           (documentation-property sym 'variable-documentation))
                          ((facep sym) (documentation-property sym 'face-documentation))
                          (t nil)))
               (value (and (boundp sym) (not (memq sym '(nil t)))
                           (prin1-to-string (symbol-value sym))))
               (arglist (and (fboundp sym) (fboundp 'help-function-arglist)
                             (prin1-to-string (help-function-arglist sym))))
               (file (symbol-file sym)))
          (+carlos/magent-tool-result
           (list (cons "status" "success")
                 (cons "symbol" symbol)
                 (cons "kind" kind)
                 (cons "docstring" (+carlos/magent-truncate (or doc "") 500))
                 (cons "value" (+carlos/magent-truncate (or value "") 300))
                 (cons "arglist" (or arglist ""))
                 (cons "file" (or file "")))))
      (error (+carlos/magent-tool-result nil (error-message-string err))))))

;; ── Registro das tools ────────────────────────────────────────────────

(defvar +carlos/magent-tool-buffer-insert nil
  "Gptel tool struct de buffer_insert.")
(defvar +carlos/magent-tool-buffer-replace-region nil
  "Gptel tool struct de buffer_replace_region.")
(defvar +carlos/magent-tool-buffer-undo nil
  "Gptel tool struct de buffer_undo.")
(defvar +carlos/magent-tool-buffer-save nil
  "Gptel tool struct de buffer_save.")
(defvar +carlos/magent-tool-lsp-hover nil
  "Gptel tool struct de lsp_hover.")
(defvar +carlos/magent-tool-describe-elisp-symbol nil
  "Gptel tool struct de describe_elisp_symbol.")

(defun +carlos/magent-register-buffer-tools ()
  "Registra as tools de buffer vivo no `magent-tools-catalog'.
Todas compartilham o permission key `buffer' para permitir/negar o toolkit
de buffer vivo por agente de forma independente de `read'/'write'/'edit'."
  (when (boundp 'magent-tools-catalog)
    (let ((tools (list (cons "buffer_insert" +carlos/magent-tool-buffer-insert)
                       (cons "buffer_replace_region" +carlos/magent-tool-buffer-replace-region)
                       (cons "buffer_undo" +carlos/magent-tool-buffer-undo)
                       (cons "buffer_save" +carlos/magent-tool-buffer-save)
                       (cons "lsp_hover" +carlos/magent-tool-lsp-hover)
                       (cons "describe_elisp_symbol" +carlos/magent-tool-describe-elisp-symbol))))
      (dolist (tool tools)
        (when (cdr tool)
          (add-to-list 'magent-tools-catalog
                       `(:name ,(car tool) :tool ,(cdr tool) :permission buffer)))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-buffer-insert
          (gptel-make-tool
           :name "buffer_insert"
           :description "Insert TEXT into a live Emacs buffer at the current point (default) or at an absolute (line, column). The buffer must already be open in Emacs; this tool never touches disk and never falls back to read_file/write_file. Ownership contract: if the buffer was modified outside the driver since its last read_buffer or buffer_* call, this call fails with 'buffer_conflict' — call read_buffer again to re-sync, then retry. Lines are 1-based, columns 0-based (clamped to the line). Prefer this over edit_file/write_file when driving the user's live buffer."
           :args '((:name "text" :type string :description "Text to insert")
                   (:name "buffer" :type string :description "Target buffer name (optional; defaults to the current buffer)" :optional t)
                   (:name "line" :type integer :description "One-based line at which to insert (default: current point)" :optional t)
                   (:name "column" :type integer :description "Zero-based column within the line (default 0)" :optional t)
                   (:name "reason" :type string :description "Reason for this tool call"))
           :function #'+carlos/magent-tool-buffer-insert
           :category "magent"))

    (setq +carlos/magent-tool-buffer-replace-region
          (gptel-make-tool
           :name "buffer_replace_region"
           :description "Replace a region of a live Emacs buffer with TEXT. Modes: (a) whole lines — give start_line (and optionally end_line), omit columns; (b) exact range — give start_line, start_column, end_line, end_column; (c) active region — omit all coordinates when a region is active in the current buffer. Same ownership contract as buffer_insert: a 'buffer_conflict' result means re-read via read_buffer before retrying. Lines are 1-based, columns 0-based."
           :args '((:name "text" :type string :description "Replacement text")
                   (:name "buffer" :type string :description "Target buffer name (optional; defaults to the current buffer)" :optional t)
                   (:name "start_line" :type integer :description "One-based first line of the region" :optional t)
                   (:name "start_column" :type integer :description "Zero-based column of the region start (default 0)" :optional t)
                   (:name "end_line" :type integer :description "One-based last line of the region (default = start_line)" :optional t)
                   (:name "end_column" :type integer :description "Zero-based end column; omit for whole-lines mode" :optional t)
                   (:name "reason" :type string :description "Reason for this tool call"))
           :function #'+carlos/magent-tool-buffer-replace-region
           :category "magent"))

    (setq +carlos/magent-tool-buffer-undo
          (gptel-make-tool
           :name "buffer_undo"
           :description "Undo the last change in a live Emacs buffer (Emacs undo). Returns 'info' status when there is nothing to undo. Use it to revert a bad buffer_insert or buffer_replace_region."
           :args '((:name "buffer" :type string :description "Target buffer name (optional; defaults to the current buffer)" :optional t)
                   (:name "reason" :type string :description "Reason for this tool call"))
           :function #'+carlos/magent-tool-buffer-undo
           :category "magent"))

    (setq +carlos/magent-tool-buffer-save
          (gptel-make-tool
           :name "buffer_save"
           :description "Persist the validated content of a live Emacs buffer to disk. The buffer MUST be visiting a file (buffer-file-name non-nil); use write_file for new files. Ownership contract: call flycheck_errors or org-lint first to validate, then buffer_save to commit. Returns the file path and byte count on success."
           :args '((:name "buffer" :type string :description "Target buffer name (optional; defaults to the current buffer)" :optional t)
                   (:name "reason" :type string :description "Reason for this tool call"))
           :function #'+carlos/magent-tool-buffer-save
           :category "magent"))

    (setq +carlos/magent-tool-lsp-hover
          (gptel-make-tool
           :name "lsp_hover"
           :description "Return the Eglot LSP hover (signature, docs) at a position in a live buffer plus the identifier at that point. Position defaults to the current point; pass line (1-based) and column (0-based) to target another spot. Returns 'info' with backend 'none' when no LSP server manages the buffer — resolve symbols with lsp_navigation in that case."
           :args '((:name "buffer" :type string :description "Target buffer name (optional; defaults to the current buffer)" :optional t)
                   (:name "line" :type integer :description "One-based line for the hover (default: current point)" :optional t)
                   (:name "column" :type integer :description "Zero-based column within the line (default 0)" :optional t)
                   (:name "reason" :type string :description "Reason for this tool call"))
           :function #'+carlos/magent-tool-lsp-hover
           :category "magent"))

    (setq +carlos/magent-tool-describe-elisp-symbol
          (gptel-make-tool
           :name "describe_elisp_symbol"
           :description "Describe an Emacs Lisp SYMBOL: kind (function/variable/face/feature), docstring, current value (truncated), arglist and source file. Use it to resolve Emacs APIs and options without guessing."
           :args '((:name "symbol" :type string :description "Emacs Lisp symbol name")
                   (:name "reason" :type string :description "Reason for this tool call"))
           :function #'+carlos/magent-tool-describe-elisp-symbol
           :category "magent"))))

;; ── Advice: coordenar read_buffer com o contrato de sessão ─────────────

(defun +carlos/magent-buffer-adopt-on-read-buffer-a (&rest args)
  "Após `magent-tools--read-buffer', adota o baseline do buffer lido.
Ler o buffer vivo via read_buffer \"reivindica\" a posse do driver no estado
observado: qualquer edição externa posterior dispara buffer_conflict na
próxima mutação.  ARGS são os argumentos originais (callback path ...)."
  (let ((path (and (consp args) (nth 1 args))))
    (when (and (stringp path) (fboundp 'magent-tools--resolve-path))
      (condition-case nil
          (let* ((resolved (magent-tools--resolve-path path))
                 (buf (and (stringp resolved)
                           (find-buffer-visiting (expand-file-name resolved)))))
            (when (buffer-live-p buf)
              (+carlos/magent-buffer-adopt buf)))
        (error nil)))))

(with-eval-after-load 'magent-tools
  (+carlos/magent-register-buffer-tools)
  (when (fboundp 'magent-tools--read-buffer)
    (advice-add 'magent-tools--read-buffer :after
                #'+carlos/magent-buffer-adopt-on-read-buffer-a)))

(with-eval-after-load 'magent-config
  (when (boundp 'magent-enable-tools)
    (add-to-list 'magent-enable-tools 'buffer)))

(provide 'custom-magent-buffer)
;;; custom-magent-buffer.el ends here
