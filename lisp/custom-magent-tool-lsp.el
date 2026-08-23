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

(with-eval-after-load 'gptel
  (when (fboundp '+carlos/magent-tool-lsp)
    (setq gptel-tools
          (append gptel-tools
                  `((:name "magent_tool_lsp"
                     :tool ,#'+carlos/magent-tool-lsp
                     :permission magent_tool_lsp
                     :description "Aciona o servidor LSP (eglot) para inspeção profunda de código (hover, goto-definition, references).
Argumentos:
- action: Ação desejada (`hover', `definition', `references').
- path: Caminho relativo do arquivo no projeto (ex: 'src/main.rs').
- query_str: Texto exato (ou regex) para encontrar a linha do símbolo desejado no arquivo alvo."
                     :args (("action" :type string :description "Ação: hover, definition, references")
                            ("path" :type string :description "Caminho relativo do arquivo alvo")
                            ("query_str" :type string :description "Símbolo ou texto exato onde aplicar a ação"))))))))

(provide 'custom-magent-tool-lsp)
;;; custom-magent-tool-lsp.el ends here
