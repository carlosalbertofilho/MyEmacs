;;; custom-magent-tool-lsp.el --- Magent LSP Bridge -*- lexical-binding: t; -*-

;;; Commentary:
;; Domínio de introspecção profunda via LSP (Eglot).
;; Permite hover, go-to-definition e referências para inferência de tipos avançada da IA.

;;; Code:

(require 'project)
(require 'eglot nil t)

(defun +carlos/magent-tool-lsp (action path query-str)
  "Usa o Eglot para extrair informações semânticas de PATH.
ACTION pode ser `hover', `definition' ou `references'.
QUERY-STR é um texto literal (ou regex) para encontrar o ponto no arquivo.
Retorna uma string sumarizada ou erro se o LSP não estiver disponível."
  (unless (featurep 'eglot)
    (error "Eglot não está carregado neste ambiente."))
  (let* ((proj (and (fboundp 'project-current) (project-current)))
         (root (if proj (project-root proj) default-directory))
         (abs-path (expand-file-name path root)))
    (unless (file-exists-p abs-path)
      (error "Arquivo '%s' não encontrado." abs-path))
    (let ((buf (or (find-buffer-visiting abs-path)
                   (find-file-noselect abs-path))))
      (with-current-buffer buf
        (let ((server (and (fboundp 'eglot-current-server) (eglot-current-server))))
          (unless server
            (error "Nenhum servidor LSP (Eglot) ativo para '%s'. O usuário deve abri-lo e ativar eglot." path))
          (save-excursion
            (goto-char (point-min))
            (if (not (search-forward query-str nil t))
                (error "Texto '%s' não encontrado no arquivo '%s'." query-str path)
              (goto-char (match-beginning 0))
              (pcase action
                ("hover"
                 (let* ((params (and (fboundp 'eglot--TextDocumentPositionParams)
                                     (eglot--TextDocumentPositionParams)))
                        (res (and params (jsonrpc-request server :textDocument/hover params))))
                   (if (and res (listp res))
                       (let ((contents (plist-get res :contents)))
                         (if (stringp contents)
                             contents
                           (if (listp contents)
                               (mapconcat (lambda (c) (if (stringp c) c (plist-get c :value))) contents "\n")
                             "Sem documentação LSP.")))
                     "Nenhuma informação de hover disponível.")))
                ("definition"
                 (let* ((params (and (fboundp 'eglot--TextDocumentPositionParams)
                                     (eglot--TextDocumentPositionParams)))
                        (res (and params (jsonrpc-request server :textDocument/definition params))))
                   (if res
                       (let ((locs (if (vectorp res) (append res nil) (list res))))
                         (mapconcat (lambda (loc)
                                      (let* ((uri (plist-get loc :uri))
                                             (targetUri (plist-get loc :targetUri))
                                             (final-uri (or uri targetUri))
                                             (range (or (plist-get loc :targetSelectionRange)
                                                        (plist-get loc :range)))
                                             (start (plist-get range :start))
                                             (line (plist-get start :line)))
                                        (format "%s:%d" (and final-uri (eglot-uri-to-path final-uri)) (1+ line))))
                                    locs "\n"))
                     "Nenhuma definição encontrada pelo LSP.")))
                ("references"
                 (let* ((params (and (fboundp 'eglot--TextDocumentPositionParams)
                                     (eglot--TextDocumentPositionParams)))
                        (ref-params (append params '(:context (:includeDeclaration t))))
                        (res (and params (jsonrpc-request server :textDocument/references ref-params))))
                   (if (and res (vectorp res))
                       (mapconcat (lambda (loc)
                                    (let* ((uri (plist-get loc :uri))
                                           (range (plist-get loc :range))
                                           (start (plist-get range :start))
                                           (line (plist-get start :line)))
                                      (format "%s:%d" (and uri (eglot-uri-to-path uri)) (1+ line))))
                                  (append res nil) "\n")
                     "Nenhuma referência encontrada pelo LSP.")))
                (_ (error "Ação LSP desconhecida: %s" action))))))))))

(defvar magent-tools-catalog)
(defvar magent-enable-tools)
(defvar +carlos/magent-tool-lsp)

;; Registra a ferramenta: cria o struct gptel-tool, o publica no catálogo
;; do Magent (roteamento por :permission) e expõe via gptel-tools.
(with-eval-after-load 'gptel
  (setq +carlos/magent-tool-lsp
        (gptel-make-tool
         :name "magent_tool_lsp"
         :description "Aciona o servidor LSP (eglot) para inspeção profunda de código (hover, goto-definition, references).
Argumentos:
- action: Ação desejada (`hover', `definition', `references').
- path: Caminho relativo do arquivo no projeto (ex: 'src/main.rs').
- query_str: Texto exato (ou regex) para encontrar a linha do símbolo desejado no arquivo alvo."
         :args '((:name "action" :type string)
                 (:name "path" :type string)
                 (:name "query_str" :type string))
         :function #'+carlos/magent-tool-lsp
         :category "magent")))

(with-eval-after-load 'magent-tools
  (when (and (boundp 'magent-tools-catalog)
             +carlos/magent-tool-lsp)
    (add-to-list 'magent-tools-catalog
                 `(:name "magent_tool_lsp" :tool ,+carlos/magent-tool-lsp
                         :permission magent_tool_lsp))))

(with-eval-after-load 'magent-config
  (when (boundp 'magent-enable-tools)
    (add-to-list 'magent-enable-tools 'magent_tool_lsp)))

(provide 'custom-magent-tool-lsp)
;;; custom-magent-tool-lsp.el ends here
