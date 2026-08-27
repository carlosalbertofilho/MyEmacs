;;; custom-magent-tool-test.el --- Ferramentas Magent para testes ERT -*- lexical-binding: t; -*-

;;; Commentary:
;; Domínio estritamente focado em testes e asserções.
;; Permite ao Magent rodar e capturar resultados do ERT diretamente do Emacs ativo.

;;; Code:

(require 'ert)
(require 'custom-magent-infra)
(require 'custom-magent-tools)

(defun +carlos/magent-tool-ert-runner (selector-str &rest _args)
  "Executa testes ERT baseados em SELECTOR-STR e captura a saída.
Se SELECTOR-STR for vazio, executa todos (t).  Pode ser o nome do teste
ou uma regex de match.
Carrega automaticamente tests/load-tests.el se os testes ainda não
estiverem definidos (batch mode).
Retorna uma string formatada contendo resultados e stack traces."
  (let* ((selector (if (or (null selector-str) (string-empty-p selector-str))
                        t
                      (let ((sym (intern-soft selector-str)))
                        (if (and sym (ert-test-boundp sym))
                            sym
                          selector-str))))
         (selector-sexp (if (eq selector t) "t"
                           (if (symbolp selector) (format "'%s" selector)
                             (format "%S" selector))))
         (init-dir (+carlos/magent-project-root))
         (eval-file (make-temp-file "magent-ert-eval-" nil ".el"))
         (output-file (make-temp-file "magent-ert-out-")))
    (unwind-protect
        (progn
          ;; Write eval form to a temp file — avoids shell quoting hell
          (with-temp-file eval-file
            (insert (format "(ert-run-tests-batch-and-exit %s)" selector-sexp)))
          ;; Run in subprocess with stdout+stderr redirected to tmp file
          (shell-command
           (format "%s --batch --init-directory %s -l init.el -l tests/load-tests.el -l %s > %s 2>&1"
                   invocation-name
                   (shell-quote-argument init-dir)
                   (shell-quote-argument eval-file)
                   (shell-quote-argument output-file)))
          (let ((output (with-temp-buffer
                          (insert-file-contents output-file)
                          (buffer-string))))
            (if (string-match-p "passed\\|failed\\|Ran\\|Running" output)
                output
              (format "Nenhum teste correspondente encontrado.\n%s" output))))
      (ignore-errors (delete-file eval-file))
      (ignore-errors (delete-file output-file)))))

(defvar magent-tools-catalog)
(defvar magent-enable-tools)
(defvar +carlos/magent-tool-ert-runner)

;; Registra a ferramenta: cria o struct gptel-tool, o publica no catálogo
;; do Magent (roteamento por :permission) e expõe via gptel-tools.
(with-eval-after-load 'gptel
  (setq +carlos/magent-tool-ert-runner
        (gptel-make-tool
         :name "magent_ert_runner"
         :description "Executa testes ERT (Emacs Lisp) de forma isolada e captura stack traces.
Útil para rodar testes específicos ou suítes inteiras de dentro do editor.
Argumentos:
- SELECTOR-STR: Nome exato do teste (ex: 'myemacs-test-foo'), ou regex, ou vazio para rodar todos."
         :args '((:name "selector-str" :type string
                        :description "Seletor do teste ou regex. Deixe vazio para todos."))
         :function #'+carlos/magent-tool-ert-runner
         :category "magent")))

(with-eval-after-load 'magent-tools
  (when (and (boundp 'magent-tools-catalog)
             +carlos/magent-tool-ert-runner)
    (add-to-list 'magent-tools-catalog
                 `(:name "magent_ert_runner" :tool ,+carlos/magent-tool-ert-runner
                         :permission magent_ert_runner))))

(with-eval-after-load 'magent-config
  (when (boundp 'magent-enable-tools)
    (add-to-list 'magent-enable-tools 'magent_ert_runner)))

(provide 'custom-magent-tool-test)
;;; custom-magent-tool-test.el ends here
