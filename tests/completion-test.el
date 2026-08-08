;;; completion-test.el --- Completion stack (tempel) regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifica a integração do Tempel com o Corfu: comandos existem, binds
;; M-+/M-* ativos e o Capf `tempel-expand' registrado nos major modes
;; prog/text/conf. Guard por skip-unless quando o pacote não carrega no
;; ambiente (builds parciais do repo).

;;; Code:

(require 'ert)

(defvar myemacs-completion-tempel-available
  (condition-case nil (progn (require 'tempel nil t) (featurep 'tempel))
    (error nil))
  "Non-nil quando `tempel' carrega neste ambiente.")

(ert-deftest myemacs-completion-tempel-commands ()
  (skip-unless myemacs-completion-tempel-available)
  (should (fboundp 'tempel-expand))
  (should (fboundp 'tempel-complete))
  (should (fboundp 'tempel-insert)))

(ert-deftest myemacs-completion-tempel-binds ()
  (skip-unless myemacs-completion-tempel-available)
  (should (eq (key-binding (kbd "M-+")) 'tempel-complete))
  (should (eq (key-binding (kbd "M-*")) 'tempel-insert)))

(ert-deftest myemacs-completion-tempel-capf ()
  (skip-unless myemacs-completion-tempel-available)
  (with-temp-buffer
    (emacs-lisp-mode)  ; deriva de prog-mode -> roda prog-mode-hook
    (should (memq 'tempel-expand completion-at-point-functions))))

(ert-deftest myemacs-completion-tempel-collection ()
  (skip-unless myemacs-completion-tempel-available)
  (should (featurep 'tempel-collection)))

(ert-deftest myemacs-completion-eglot-tempel ()
  (skip-unless myemacs-completion-tempel-available)
  (should (featurep 'eglot-tempel))
  (should (bound-and-true-p eglot-tempel-mode)))

(provide 'completion-test)
;;; completion-test.el ends here
