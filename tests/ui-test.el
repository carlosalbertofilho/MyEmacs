;;; ui-test.el --- UI config regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Validações de custom-ui.el: regra de display-buffer-alist que ancora
;; o buffer *ert* no rodapé (direção bottom) — dívida do commit 79e9830
;; (item marcado DONE sem teste na época).

;;; Code:

(require 'ert)
(require 'cl-lib)

(defvar myemacs-ui-config-available
  (file-readable-p
   (expand-file-name "lisp/custom-ui.el"
                     (or (getenv "EMACS_TEST_DIR") "~/.config/emacs")))
  "Non-nil quando o ambiente de teste expõe lisp/custom-ui.el.")

(ert-deftest myemacs-ui-ert-buffer-display-bottom ()
  "\\*ert\\* casa com a entrada do display-buffer-alist e abre em bottom."
  (skip-unless myemacs-ui-config-available)
  (let ((hits (cl-loop for (rx . action) in display-buffer-alist
                       when (and (stringp rx) (string-match-p rx "*ert*"))
                       collect action)))
    (should hits)
    (should (member '(display-buffer-in-direction) (car hits)))
    (should (eq 'bottom (cdr (assq 'direction (car hits)))))))

(provide 'ui-test)
;;; ui-test.el ends here
