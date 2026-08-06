;;; dev-env-test.el --- Development environment & Dirvish side tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Testes ERT para as customizações do ambiente de desenvolvimento (flycheck inline/wave,
;; eldoc-box, apheleia, nerd-icons-corfu, dirvish-side open action e display-buffer-alist).

;;; Code:

(require 'ert)
(require 'cl-lib)

(declare-function +carlos/dirvish-side-open-action "custom-files")
(declare-function nerd-icons-corfu-formatter "nerd-icons-corfu")
(declare-function flycheck-next-error "flycheck")
(declare-function flycheck-previous-error "flycheck")
(declare-function consult-flycheck "consult-flycheck")
(declare-function flycheck-inline-mode "flycheck-inline")
(declare-function eldoc-box-hover-at-point-mode "eldoc-box")
(declare-function eldoc-box-help-at-point "eldoc-box")

(defvar dirvish-side-open-file-action)
(defvar flycheck-indication-mode)
(defvar corfu-margin-formatters)
(defvar apheleia-global-mode)
(defvar apheleia-inhibit-functions)

(ert-deftest myemacs-dev-dirvish-side-open-action-exists ()
  (should (fboundp '+carlos/dirvish-side-open-action)))

(ert-deftest myemacs-dev-dirvish-side-open-action-configured ()
  (skip-unless (boundp 'dirvish-side-open-file-action))
  (should (eq dirvish-side-open-file-action #'+carlos/dirvish-side-open-action)))

(ert-deftest myemacs-dev-flycheck-wave-faces ()
  (require 'flycheck nil t)
  (skip-unless (featurep 'flycheck))
  (dolist (face '(flycheck-error flycheck-warning flycheck-info))
    (let ((ul (face-attribute face :underline nil)))
      (should (or (eq ul 'wave)
                  (and (listp ul) (eq (plist-get ul :style) 'wave)))))))

(ert-deftest myemacs-dev-flycheck-inline-mode ()
  (skip-unless (fboundp 'flycheck-inline-mode))
  (should (fboundp 'flycheck-inline-mode)))

(ert-deftest myemacs-dev-flycheck-fringe-mode ()
  (should (eq flycheck-indication-mode 'left-fringe)))

(ert-deftest myemacs-dev-flycheck-keybindings ()
  (skip-unless (fboundp 'consult-flycheck))
  (should (fboundp 'flycheck-next-error))
  (should (fboundp 'flycheck-previous-error))
  (should (fboundp 'consult-flycheck)))

(ert-deftest myemacs-dev-corfu-nerd-icons-formatter ()
  (skip-unless (boundp 'corfu-margin-formatters))
  (should (memq #'nerd-icons-corfu-formatter corfu-margin-formatters)))

(ert-deftest myemacs-dev-eldoc-box-commands ()
  (skip-unless (fboundp 'eldoc-box-hover-at-point-mode))
  (should (fboundp 'eldoc-box-hover-at-point-mode))
  (should (fboundp 'eldoc-box-help-at-point)))

(ert-deftest myemacs-dev-apheleia-global-mode ()
  (skip-unless (boundp 'apheleia-global-mode))
  (should apheleia-global-mode))

(ert-deftest myemacs-dev-apheleia-inhibit-c-mode ()
  (skip-unless (boundp 'apheleia-inhibit-functions))
  (with-temp-buffer
    (c-mode)
    (should (cl-some (lambda (fn) (funcall fn)) apheleia-inhibit-functions))))

(ert-deftest myemacs-dev-display-buffer-alist-drawer-rules ()
  (should (cl-some (lambda (entry)
                     (and (stringp (car entry))
                          (string-match-p "compilation" (car entry))
                          (string-match-p "vterm" (car entry))
                          (string-match-p "eshell" (car entry))
                          (string-match-p "magit" (car entry))
                          (string-match-p "gptel" (car entry))))
                   display-buffer-alist)))

(provide 'dev-env-test)
;;; dev-env-test.el ends here
