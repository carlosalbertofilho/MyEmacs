;;; custom-magent-lint.el --- Linters nativos para validação estática -*- lexical-binding: t; -*-

;;; Commentary:
;; Linters que rodam via `emacs --batch' sem dependências externas.
;; Usam parse nativo do Emacs (forward-sexp, read) em vez de regex/ripgrep.
;;
;; Dois linters:
;;   1. defun-parens: valida que cada defun/defsubst/defmacro fecha seus parênteses
;;   2. arity: detecta chamadas com arity errada em funções blacklistadas

;;; Code:

(require 'cl-lib)

;; ── Linter 1: Balanceamento por defun (forward-sexp) ─────────────────

(defun +carlos/magent-lint-defun-parens-in-buffer ()
  "Valida que cada defun/defsubst/defmacro no buffer fecha seus parênteses.
 Retorna lista de strings de erro (vazia = OK).
 Usa `forward-sexp' nativo que respeita syntax-table e strings/comments."
  (save-excursion
    (goto-char (point-min))
    (let ((errors nil))
      (while (re-search-forward "^\\s-*(\\(?:cl-\\)?def\\(?:un\\|subst\\|macro\\)\\s-" nil t)
        (let ((start (match-beginning 0)))
          (goto-char start)
          (condition-case nil
              (forward-sexp 1)
            (scan-error
             (forward-char 1)
             (push (format "Linha %d: defun/defsubst/defmacro não fecha parênteses"
                           (line-number-at-pos start))
                   errors)))))
      (nreverse errors))))

(defun +carlos/magent-lint-defun-parens (file)
  "Valida平衡amento de parênteses por defun em FILE.
 Retorna nil se OK, ou lista de erros."
  (with-temp-buffer
    (insert-file-contents file)
    (emacs-lisp-mode)
    (+carlos/magent-lint-defun-parens-in-buffer)))

;; ── Linter 2: Arity check via AST (read) ────────────────────────────

(defvar +carlos/magent--arity-blacklist
  '(buffer-string)
  "Funções que quebram silenciosamente com args extras em batch.
 Adicione aqui qualquer função que tenha arity 0 mas possa ser
 chamada incorretamente com argumentos.")

(defun +carlos/magent--check-arity-form (form)
  "Analisa FORM recursivamente procurando chamadas com arity errada.
 Sinaliza erro se encontrar uma função da blacklist com argumentos extras."
  (when (consp form)
    (when (and (symbolp (car form))
               (memq (car form) +carlos/magent--arity-blacklist)
               (cdr form))
      (error "Arity: %s recebeu %d args (esperado 0)"
             (car form) (length (cdr form))))
    (dolist (sub form)
      (when (consp sub)
        (+carlos/magent--check-arity-form sub)))))

(defun +carlos/magent-lint-arity-in-buffer ()
  "Valida arity de funções blacklistadas no buffer atual.
 Retorna nil se OK, ou string de erro."
  (goto-char (point-min))
  (let ((err-msg nil))
    (condition-case err
        (while t
          (let ((form (read (current-buffer))))
            (+carlos/magent--check-arity-form form)))
      (error
       (unless (eq (car err) 'end-of-file)
         (setq err-msg (error-message-string err)))))
    err-msg))

(defun +carlos/magent-lint-arity (file)
  "Valida arity de funções blacklistadas em FILE.
 Retorna nil se OK, ou string de erro."
  (with-temp-buffer
    (insert-file-contents file)
    (emacs-lisp-mode)
    (condition-case err
        (progn
          (+carlos/magent-lint-arity-in-buffer)
          nil)
      (error (error-message-string err)))))

;; ── Lint-all: roda todos os linters em um diretório ──────────────────

(defun +carlos/magent-lint-directory (dir &optional pattern)
  "Roda todos os linters nativos em arquivos de DIR.
 PATTERN é o glob para arquivos (padrão: \"*.el\").
 Retorna lista de (FILE . ERROS)."
  (let ((pattern (or pattern "*.el"))
        (results nil))
    (dolist (file (directory-files dir t (concat "\\`" (regexp-quote pattern) "\\'")))
      (let ((errors (append (+carlos/magent-lint-defun-parens file)
                            (let ((arity-err (+carlos/magent-lint-arity file)))
                              (when arity-err (list arity-err))))))
        (when errors
          (push (cons file errors) results))))
    (nreverse results)))

(provide 'custom-magent-lint)
;;; custom-magent-lint.el ends here
