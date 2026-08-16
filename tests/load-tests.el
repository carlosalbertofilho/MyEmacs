;;; load-tests.el --- Loader for the MyEmacs ERT suite -*- lexical-binding: t; -*-

;;; Commentary:
;; Carrega todos os arquivos tests/*-test.el. Deve ser executado DEPOIS do
;; init.el no mesmo processo (os testes assumem a config já carregada).
;;
;; Uso (batch):
;;   emacs --init-directory <dir> --batch -l <dir>/init.el \
;;         -l tests/load-tests.el \
;;         --eval '(ert-run-tests-batch-and-exit t)'
;;
;; Testes de rede (live AI backends) são gated via `skip-unless'
;; (EMACS_TEST_NETWORK=1). Sem a envvar eles aparecem como skipped, não falham.

;;; Code:

(require 'ert)

(dolist (file (directory-files (file-name-directory (or load-file-name
                                                        default-directory))
                               t "-test\\.el$"))
  (load file nil t))

(require 'dev-env-test)
(require 'magent-test)
(require 'local-ai-automation-test)
(require 'context-test)
(require 'magent-driver-test)
(require 'magent-buffer-test)
(require 'magent-team-test)

(provide 'load-tests)
;;; load-tests.el ends here
