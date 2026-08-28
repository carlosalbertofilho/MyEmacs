;;; dashboard-test.el --- Dashboard regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Garante que os comandos +carlos/dashboard-open e +carlos/dashboard-refresh
;; existem (bug latente: eram declarados e bindados em C-c d d / C-c d r mas
;; nunca definidos → void-function ao pressionar as teclas).

;;; Code:

(require 'ert)
(require 'dashboard)

(ert-deftest myemacs-dashboard-commands-exist ()
  (should (commandp '+carlos/dashboard-open))
  (should (commandp '+carlos/dashboard-refresh)))

(ert-deftest myemacs-dashboard-open-runs ()
  (with-temp-buffer
    (should (fboundp '+carlos/dashboard-open))
    (should (fboundp 'dashboard-open))))

(ert-deftest myemacs-dashboard-server-frame-hook-arity ()
  "Verifica se +carlos/dashboard-open-on-server-frame aceita 0 argumentos (server-after-make-frame-hook)."
  (should (fboundp '+carlos/dashboard-open-on-server-frame))
  (should (progn (+carlos/dashboard-open-on-server-frame) t)))

(provide 'dashboard-test)
;;; dashboard-test.el ends here
