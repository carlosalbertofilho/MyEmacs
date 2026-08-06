;;; files-test.el --- File management (dirvish) regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifica as configurações do dirvish que já quebraram: layout inválido
;; (10), ícones pequenos (12), atributos e grupos de emerge.

;;; Code:

(require 'ert)
(require 'dirvish)
(require 'dirvish-emerge)
(require 'cl-lib)

(ert-deftest myemacs-files-dirvish-attributes ()
  (dolist (attr '(vc-state git-msg subtree-state nerd-icons collapse
                   file-time file-size))
    (should (memq attr dirvish-attributes))))

(ert-deftest myemacs-files-dirvish-layout-valid ()
  ;; `dirvish-default-layout' é (INDEX SPLIT &optional SIZE) — index 0-5.
  (let ((index (if (consp dirvish-default-layout)
                   (car dirvish-default-layout)
                 dirvish-default-layout)))
    (should (and (numberp index) (>= index 0) (<= index 5)))))

(ert-deftest myemacs-files-dirvish-emerge-groups ()
  (should (>= (length dirvish-emerge-groups) 5)))

(ert-deftest myemacs-files-dirvish-emerge-directories-first ()
  (should (member "Directories" (mapcar #'car dirvish-emerge-groups))))

(ert-deftest myemacs-files-dirvish-peek-mode ()
  (should (bound-and-true-p dirvish-peek-mode)))

(ert-deftest myemacs-files-dirvish-nav-binds ()
  (should (eq (lookup-key dirvish-mode-map (kbd "["))
              '+carlos/dirvish-emerge-previous-group))
  (should (eq (lookup-key dirvish-mode-map (kbd "]"))
              '+carlos/dirvish-emerge-next-group)))

(ert-deftest myemacs-files-dirvish-emerge-functions ()
  (should (fboundp '+carlos/dirvish-emerge-previous-group))
  (should (fboundp '+carlos/dirvish-emerge-next-group)))

(provide 'files-test)
;;; files-test.el ends here
