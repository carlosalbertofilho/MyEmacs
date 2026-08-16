;;; org-lint.el --- Batch Org structure linter for MyEmacs -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifica a estrutura dos arquivos .org do repositório MyEmacs:
;;   1. Balanceamento de blocos #+BEGIN_*/#+END_* — blocos não fechados quebram
;;      o parser org e o chunking RAG (bug histórico do TODO.org, 2026-08-16).
;;   2. Ausência de headings malformados — linha iniciando com espaço + `*'
;;      (ex.: " * Diretrizes ...") não é heading válido em org.
;;   3. Referências ao nome canônico do arquivo de planejamento — o arquivo é
;;      TODO.org; qualquer `TODO.md' em prosa é referência obsoleta.
;;      Ocorrências dentro de código inline `=TODO.md=' são meta-referências
;;      legítimas (documentam a própria regra) e são ignoradas.
;;
;; Uso (batch):
;;   emacs --batch -Q -l bin/org-lint.el --eval '(org-lint-run-and-exit)'
;;
;; Os mesmos predicados são exercitados pela suíte ERT em
;; tests/org-lint-test.el (padrão: cada bug corrigido ganha um teste).

;;; Code:

(defconst org-lint--begin-re "^[ \t]*#\\+begin_"
  "Regex do início de um bloco org (#+begin_src, #+BEGIN_QUOTE, ...).")

(defconst org-lint--end-re "^[ \t]*#\\+end_"
  "Regex do fim de um bloco org (#+end_src, #+END_QUOTE, ...).")

(defconst org-lint--malformed-heading-re "^ \\*"
  "Regex de heading malformado (espaço antes do asterisco).")

(defconst org-lint--todo-md-re "TODO\\.md"
  "Referência ao nome antigo do arquivo de planejamento.")

(defvar org-lint--source-dir (expand-file-name default-directory)
  "Diretório raiz a varrer (override em testes).")

(defun org-lint--files ()
  "Retorna a lista de arquivos .org a validar na raiz e em docs/."
  (let* ((root (directory-file-name org-lint--source-dir))
         (root-files (directory-files root t "\\.org\\'"))
         (docs (when (file-directory-p (expand-file-name "docs" root))
                 (directory-files (expand-file-name "docs" root) t "\\.org\\'"))))
    (append root-files docs)))

(defun org-lint--balanced-blocks-p (file)
  "Non-nil se FILE tem blocos #+BEGIN_/#+END_ balanceados."
  (let ((begins 0) (ends 0))
    (with-temp-buffer
      (insert-file-contents file)
      (let ((case-fold-search t))
        (goto-char (point-min))
        (while (re-search-forward org-lint--begin-re nil t)
          (setq begins (1+ begins)))
        (goto-char (point-min))
        (while (re-search-forward org-lint--end-re nil t)
          (setq ends (1+ ends)))))
    (= begins ends)))

(defun org-lint--no-malformed-headings-p (file)
  "Non-nil se FILE não tem headings malformados (`^ *')."
  (not (with-temp-buffer
         (insert-file-contents file)
         (re-search-forward org-lint--malformed-heading-re nil t))))

(defun org-lint--no-todo-md-refs-p (file)
  "Non-nil se FILE não referencia o nome antigo `TODO.md' em prosa.
Ocorrências delimitadas por `=' (código inline, ex.: =TODO.md=) são
meta-referências legítimas que documentam a própria regra e são ignoradas."
  (not (with-temp-buffer
         (insert-file-contents file)
         (let ((found nil))
           (goto-char (point-min))
           (while (and (not found) (re-search-forward org-lint--todo-md-re nil t))
             (let* ((start (match-beginning 0))
                    (end (match-end 0))
                    (before (when (> start (point-min)) (char-before start)))
                    (after (when (< end (point-max)) (char-after end))))
               (when (not (and (eq before ?=) (eq after ?=)))
                 (setq found t))))
           found))))

(defun org-lint--check-file (file)
  "Valida FILE. Retorna (FILE . PROBLEMA) ou nil."
  (cond
   ((not (org-lint--balanced-blocks-p file))
    (cons file "blocos #+BEGIN_/#+END_ desbalanceados"))
   ((not (org-lint--no-malformed-headings-p file))
    (cons file "heading malformado (espaço antes de `*')"))
   ((not (org-lint--no-todo-md-refs-p file))
    (cons file "referência a `TODO.md' (usar `TODO.org')"))
   (t nil)))

(defun org-lint-run (&optional dir)
  "Valida todos os .org de DIR (default `org-lint--source-dir').
Retorna a lista de problemas (nil se tudo limpo)."
  (setq org-lint--source-dir (or dir org-lint--source-dir))
  (delq nil (mapcar #'org-lint--check-file (org-lint--files))))

(defun org-lint-run-and-exit (&optional dir)
  "Roda o linter e sai com código de erro se houver problemas."
  (let ((problems (org-lint-run dir)))
    (if problems
        (progn
          (dolist (p problems)
            (message "org-lint: %s: %s" (car p) (cdr p)))
          (message "org-lint: %d problema(s) encontrado(s)" (length problems))
          (kill-emacs 1))
      (message "org-lint: OK — todos os arquivos .org válidos.")
      (kill-emacs 0))))

(provide 'org-lint)
;;; org-lint.el ends here
