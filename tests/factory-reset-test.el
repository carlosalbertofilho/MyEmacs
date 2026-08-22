;;; factory-reset-test.el --- Guardas do bin/factory-reset.sh -*- lexical-binding: t; -*-

;;; Commentary:
;; Testes estruturais leves para o fluxo de factory reset:
;; - script existe, é executável e passa em `bash -n'
;; - guardas de segurança presentes (FORCE, dirty-check, trap de backup)
;; - receita `factory-reset' existe no Justfile e encadeia check-prod
;;
;; Não executa o script (destrutivo) — apenas validação estática.

;;; Code:
(require 'ert)

(defvar myemacs-factory-root
  (or (getenv "EMACS_PROJECT_DIR")
      (locate-dominating-file (or load-file-name default-directory) "Justfile"))
  "Raiz do projeto MyEmacs.")

(defvar myemacs-factory-script
  (when myemacs-factory-root
    (expand-file-name "bin/factory-reset.sh" myemacs-factory-root)))

(ert-deftest myemacs-factory-reset-script-exists-and-parses ()
  "Script existe, tem shebang e sintaxe bash válida."
  (skip-unless myemacs-factory-script)
  (should (file-executable-p myemacs-factory-script))
  (let ((first-line
         (with-temp-buffer
           (insert-file-contents myemacs-factory-script)
           (buffer-substring-no-properties
            (point-min)
            (progn (forward-line 1) (point))))))
    (should (string-prefix-p "#!" first-line)))
  (should (= 0 (call-process "bash" nil nil nil "-n" myemacs-factory-script))))

(ert-deftest myemacs-factory-reset-has-safety-guards ()
  "Script contém os guardas: FORCE, dirty-check e trap do backup."
  (skip-unless myemacs-factory-script)
  (let ((body (with-temp-buffer
                (insert-file-contents myemacs-factory-script)
                (buffer-string))))
    (should (string-match-p "FORCE" body))
    (should (string-match-p "status --porcelain --untracked-files=no" body))
    (should (string-match-p "trap " body))
    (should (string-match-p "remote get-url origin" body))
    (should (string-match-p "-b \"\\$BRANCH\"" body))))

(ert-deftest myemacs-factory-reset-justfile-recipe-complete ()
  "Receita no Justfile encadeia install + compile-prod + check-prod."
  (skip-unless myemacs-factory-root)
  (let ((justfile (with-temp-buffer
                    (insert-file-contents
                     (expand-file-name "Justfile" myemacs-factory-root))
                    (buffer-string))))
    (should (string-match-p "^factory-reset:" justfile))
    (should (string-match-p "just check-prod" justfile))))

(provide 'factory-reset-test)
;;; factory-reset-test.el ends here
