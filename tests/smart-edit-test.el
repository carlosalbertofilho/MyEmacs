;;; smart-edit-test.el --- Tests for the transactional smart-edit helper -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests para +carlos/magent--smart-edit-transaction e
;; +carlos/magent--smart-edit-replace-core (custom-magent-tool-smart-edit.el).

;;; Code:

(require 'ert)
(require 'custom-magent-tool-smart-edit)

;; ── Meta: zero primitive-undo no módulo ────────────────────────────────
(ert-deftest myemacs-smart-edit-no-primitive-undo ()
  "Garante que primitive-undo foi removido do módulo smart-edit."
  (let ((file (find-file-noselect "lisp/custom-magent-tool-smart-edit.el")))
    (with-current-buffer file
      (should (= 0 (how-many "(primitive-undo" (point-min) (point-max)))))))

(defmacro myemacs-smart-edit-test-with-temp-buf (&rest body)
  "Executa BODY em buffer temporário associado a arquivo tmp.
Garante cleanup automático e desfaz modificações no arquivo."
  (declare (indent 0) (debug body))
  `(let* ((--tmpfile (make-temp-file "smart-edit-test-" nil ".el"))
          (buf (find-file-noselect --tmpfile)))
     (unwind-protect
         (with-current-buffer buf
           ,@body)
       (when (buffer-live-p buf) (kill-buffer buf))
       (when (file-exists-p --tmpfile) (delete-file --tmpfile)))))

;; ── Transactional: snapshot / rollback / save ──────────────────────────
(ert-deftest myemacs-smart-edit-transaction-saves-on-success ()
  "Thunk sem erro: buffer salvo, resultado é string de sucesso."
  (myemacs-smart-edit-test-with-temp-buf
    (insert "(progn nil)")
    (let ((result (+carlos/magent--smart-edit-transaction buf 'code
                    (lambda ()
                      (goto-char (point-max))
                      (insert " x")
                      "inserido"))))
      (should (stringp result))
      (should (not (string-prefix-p "Erro" result)))
      (should (string= result "inserido"))
      (should (string-match-p "x" (buffer-string)))
      (should (not (buffer-modified-p buf))))))

(ert-deftest myemacs-smart-edit-transaction-rolls-back-on-error ()
  "Thunk com erro: buffer restaurado ao estado anterior."
  (myemacs-smart-edit-test-with-temp-buf
    (insert "(progn nil)")
    (let ((original (buffer-string)))
      (let ((result (+carlos/magent--smart-edit-transaction buf 'code
                      (lambda ()
                        (goto-char (point-max))
                        (insert " ILLEGAL")
                        (error "forced error for test")))))
        (should (stringp result))
        (should (string-prefix-p "Erro" result))
        (should (string= original
                         (replace-regexp-in-string "\n\\'" "" (buffer-string))))))))

(ert-deftest myemacs-smart-edit-transaction-raw-kind-skips-gate ()
  "Kind 'raw não executa check-parens."
  (myemacs-smart-edit-test-with-temp-buf
    (insert "(+ - )")
    (let ((result (+carlos/magent--smart-edit-transaction buf 'raw
                    (lambda () "ok"))))
      (should (equal result "ok")))))

(ert-deftest myemacs-smart-edit-transaction-code-kind-gate ()
  "Kind 'code' com buffer inválido: erro de gate antes do thunk."
  (myemacs-smart-edit-test-with-temp-buf
    (insert ")(invalid")
    (let ((result (+carlos/magent--smart-edit-transaction buf 'code
                    (lambda () (error "should not run")))))
      (should (stringp result))
      (should (string-prefix-p "Erro" result)))))

;; ── replace-core: contratos de flags ───────────────────────────────────
(ert-deftest myemacs-smart-edit-replace-core-nil-global ()
  "nil = substitui todas as ocorrências (literal)."
  (with-temp-buffer
    (insert "foo bar foo baz foo")
    (let ((count (+carlos/magent--smart-edit-replace-core "foo" "qux")))
      (should (= 3 count))
      (should (equal (buffer-string) "qux bar qux baz qux")))))

(ert-deftest myemacs-smart-edit-replace-core-first ()
  "FIRST = substitui apenas a primeira ocorrência."
  (with-temp-buffer
    (insert "aaa bbb aaa")
    (let ((count (+carlos/magent--smart-edit-replace-core "aaa" "xxx" "FIRST")))
      (should (= 1 count))
      (should (equal (buffer-string) "xxx bbb aaa")))))

(ert-deftest myemacs-smart-edit-replace-core-word ()
  "WORD = regexp-quote com limitadores de palavra."
  (with-temp-buffer
    (insert "foo foobar foo")
    (let ((count (+carlos/magent--smart-edit-replace-core "foo" "qux" "WORD")))
      (should (= 2 count))
      (should (equal (buffer-string) "qux foobar qux")))))

(ert-deftest myemacs-smart-edit-replace-core-regex ()
  "REGEX = padrão regex bruto."
  (with-temp-buffer
    (insert "abc 123 def 456")
    (let ((count (+carlos/magent--smart-edit-replace-core "[0-9]+" "N" "REGEX")))
      (should (= 2 count))
      (should (equal (buffer-string) "abc N def N")))))

(ert-deftest myemacs-smart-edit-replace-core-no-match ()
  "Sem correspondência: retorna 0 e buffer intacto."
  (with-temp-buffer
    (insert "hello world")
    (let ((count (+carlos/magent--smart-edit-replace-core "xyz" "qux")))
      (should (= 0 count))
      (should (equal (buffer-string) "hello world")))))

(ert-deftest myemacs-smart-edit-org-toggle-checkbox ()
  "toggle_checkbox alterna checkbox no heading alvo."
  (let ((tmp (make-temp-file "test-toggle-" nil ".org")))
    (unwind-protect
        (with-current-buffer (find-file-noselect tmp)
          (erase-buffer)
          (insert "* TODO Tarefa\n  - [ ] Item A\n  - [X] Item B\n")
          (goto-char (point-min))
          (let ((res (+carlos/magent-tool-org-smart-edit tmp "toggle_checkbox" nil "Tarefa")))
            (should (string-match-p "Checkbox toggled" res))
            (should (string-match-p "Tarefa" res))))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest myemacs-smart-edit-org-toggle-checkbox-missing-heading ()
  "toggle_checkbox com heading inexistente retorna erro."
  (let ((tmp (make-temp-file "test-toggle-" nil ".org")))
    (unwind-protect
        (with-current-buffer (find-file-noselect tmp)
          (erase-buffer)
          (insert "* TODO Existe\n")
          (let ((res (+carlos/magent-tool-org-smart-edit tmp "toggle_checkbox" nil "NaoExiste")))
            (should (string-match-p "não encontrado" res))))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest myemacs-smart-edit-org-toggle-checkbox-empty-args ()
  "toggle_checkbox sem args retorna erro de uso."
  (let* ((res (+carlos/magent-tool-org-smart-edit "/tmp/x.org" "toggle_checkbox" nil ""))
         (str (if (and (fboundp 'magent-tool-result-p) (magent-tool-result-p res))
                  (magent-tool-result-output-string res)
                (format "%s" res))))
    (should (string-match-p "Erro\\|Error" str))))

(provide 'smart-edit-test)
;;; smart-edit-test.el ends here
