;;; custom-magent-tool-ast.el --- Ferramentas Magent para AST e Tree-Sitter -*- lexical-binding: t; -*-

;;; Commentary:
;; Domínio de introspecção estática de código via Tree-sitter.
;; Busca referências e estruturas sem depender de LSPs.

;;; Code:

(require 'treesit)
(require 'project)
(require 'custom-magent-tools)

(defconst +carlos/magent-treesit-ext-map
  '((python . "\\.py\\'")
    (elisp . "\\.el\\'")
    (javascript . "\\.[cm]?js\\'")
    (typescript . "\\.[cm]?ts\\'")
    (tsx . "\\.tsx\\'")
    (c . "\\.[ch]\\'")
    (cpp . "\\.\\(cpp\\|hpp\\|cc\\|hh\\|cxx\\|hxx\\)\\'")
    (go . "\\.go\\'"))
  "Mapeamento de linguagem tree-sitter para regex de arquivos.")

(defun +carlos/magent-tool-treesit-query (language query-str &rest args)
  "Executa QUERY-STR via tree-sitter na linguagem LANGUAGE.
ARGS é uma plist onde :path pode restringir a busca a um arquivo/diretório
e :limit pode limitar a quantidade de arquivos (default 500).
Retorna uma string contendo os matches e suas posições."
  (unless (treesit-available-p)
    (error "O suporte a tree-sitter não está disponível neste Emacs"))
  (let ((lang-sym (if (stringp language) (intern language) language)))
    (unless (treesit-language-available-p lang-sym)
      (error "A gramática tree-sitter para '%s' não está instalada ou falhou ao carregar" lang-sym))
    (let* ((path (plist-get args :path))
           (limit (or (plist-get args :limit) 500))
           (ext-regex (or (cdr (assq lang-sym +carlos/magent-treesit-ext-map))
                          "\\.\\(py\\|el\\|ts\\|js\\|c\\|go\\|tsx\\)\\'"))
           (search-dir (if path
                           (if (file-directory-p path) path (file-name-directory path))
                         (let ((proj (project-current)))
                           (if proj (project-root proj) default-directory))))
           (files (if (and path (not (file-directory-p path)))
                      (list path)
                    (directory-files-recursively search-dir ext-regex)))
           (query (treesit-query-compile lang-sym query-str))
           (results nil)
           (files-processed 0))
      
      (catch 'limit-reached
        (dolist (file files)
          (when (>= files-processed limit)
            (throw 'limit-reached t))
          ;; Tenta abrir sem acionar os hooks pesados (usando buffer temporário)
          (with-temp-buffer
            (insert-file-contents file)
            ;; O parser tree-sitter opera no buffer atual
            (let* ((parser (treesit-parser-create lang-sym))
                   (matches (treesit-query-capture parser query)))
              (when matches
                (let ((file-results nil))
                  (dolist (match matches)
                    (let* ((node (cdr match))
                           (capture-name (car match))
                           (start (treesit-node-start node))
                           (line (line-number-at-pos start))
                           (text (treesit-node-text node t)))
                      (push (format "  [%s] L%d: %s" capture-name line text) file-results)))
                  (when file-results
                    (push (format "File: %s\n%s" 
                                  (file-relative-name file search-dir)
                                  (mapconcat #'identity (nreverse file-results) "\n"))
                          results)))))
            (cl-incf files-processed))))
      
      (if results
          (mapconcat #'identity (nreverse results) "\n\n")
        "Nenhum match encontrado para a query."))))

(defvar magent-tools-catalog)
(defvar magent-enable-tools)
(defvar +carlos/magent-tool-treesit-query)

;; Registra a ferramenta: cria o struct gptel-tool, o publica no catálogo
;; do Magent (roteamento por :permission) e expõe via gptel-tools.
(with-eval-after-load 'gptel
  (setq +carlos/magent-tool-treesit-query
        (gptel-make-tool
         :name "magent_treesit_query"
         :description "Faz uma busca no código-fonte usando uma query Tree-Sitter estruturada (AST).
Ideal para encontrar callers, definições, classes e métodos com 100% de precisão sem depender de LSP.
Argumentos:
- LANGUAGE: Linguagem do código (ex: 'python', 'elisp', 'c', 'typescript', 'go').
- QUERY-STR: String da query no formato Tree-Sitter s-expression.
- PATH (opcional): Diretório ou arquivo específico para restringir a busca.
Exemplo de query: (function_definition name: (identifier) @func_name)"
         :args '((:name "language" :type string :description "Linguagem da árvore (ex: python, elisp)")
                 (:name "query-str" :type string :description "A S-expression da query")
                 (:name "path" :type string :description "Opcional: diretório ou arquivo alvo"))
         :function #'+carlos/magent-tool-treesit-query
         :category "magent")))

(with-eval-after-load 'magent-tools
  (when (and (boundp 'magent-tools-catalog)
             +carlos/magent-tool-treesit-query)
    (add-to-list 'magent-tools-catalog
                 `(:name "magent_treesit_query" :tool ,+carlos/magent-tool-treesit-query
                         :permission magent_treesit_query))))

(with-eval-after-load 'magent-config
  (when (boundp 'magent-enable-tools)
    (add-to-list 'magent-enable-tools 'magent_treesit_query)))

(provide 'custom-magent-tool-ast)
;;; custom-magent-tool-ast.el ends here
