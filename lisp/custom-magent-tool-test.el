;;; custom-magent-tool-test.el --- Ferramentas Magent para testes ERT -*- lexical-binding: t; -*-

;;; Commentary:
;; Domínio estritamente focado em testes e asserções.
;; Permite ao Magent rodar e capturar resultados do ERT diretamente do Emacs ativo.

;;; Code:

(require 'ert)
(require 'custom-magent-tools)

(defun +carlos/magent-tool-ert-runner (selector-str &rest _args)
  "Executa testes ERT baseados em SELECTOR-STR e captura a saída.
Se SELECTOR-STR for vazio, executa todos (t).  Pode ser o nome do teste
ou uma regex de match.
Retorna uma string formatada contendo resultados e stack traces."
  (let ((selector (if (or (null selector-str) (string-empty-p selector-str))
                      t
                    ;; Tenta converter para símbolo se for um nome exato válido
                    (let ((sym (intern-soft selector-str)))
                      (if (and sym (ert-test-boundp sym))
                          sym
                        selector-str))))
        (out-buf (generate-new-buffer " *magent-ert*")))
    (unwind-protect
        (let ((standard-output out-buf)
              ;; Configurações para garantir saída verbosa em falhas sem abrir UI
              (ert-debug-on-error nil)
              (ert-batch-backtrace-right-margin 100)
              (ert-batch-print-level 10)
              (ert-batch-print-length 100))
          (condition-case err
              (ert-run-tests-batch selector)
            (error
             (princ (format "\n[ERT] Erro fatal durante a execução: %s\n" err))))
          (with-current-buffer out-buf
            (let ((output (buffer-string)))
              (if (string-empty-p output)
                  "Nenhum teste correspondente encontrado ou erro ao gerar saída."
                output))))
      (kill-buffer out-buf))))

;; Registra a ferramenta no ecossistema de ferramentas do Magent
(with-eval-after-load 'gptel
  (when (fboundp '+carlos/magent-tool-ert-runner)
    (setq gptel-tools
          (append gptel-tools
                  `((:name "magent_ert_runner"
                     :tool ,#'+carlos/magent-tool-ert-runner
                     :permission magent_ert_runner
                     :description "Executa testes ERT (Emacs Lisp) de forma isolada e captura stack traces.
Útil para rodar testes específicos ou suítes inteiras de dentro do editor.
Argumentos:
- SELECTOR-STR: Nome exato do teste (ex: 'myemacs-test-foo'), ou regex, ou vazio para rodar todos."
                     :args (("selector-str" :type string :description "Seletor do teste ou regex. Deixe vazio para todos."))))))))

(provide 'custom-magent-tool-test)
;;; custom-magent-tool-test.el ends here
