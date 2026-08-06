;;; org-test.el --- Org/org-modern regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifica as estilizações do org-modern que já quebraram (ex. setar
;; `org-modern-replace-stars' como t aborta o org-mode-hook com
;; wrong-type-argument sequencep t).

;;; Code:

(require 'ert)
(require 'org)
(require 'org-modern)

(ert-deftest myemacs-org-modern-star-symbol ()
  (should (eq org-modern-star 'replace)))

(ert-deftest myemacs-org-modern-replace-stars-list ()
  (should (listp org-modern-replace-stars))
  (should (>= (length org-modern-replace-stars) 5)))

(ert-deftest myemacs-org-babel-languages ()
  (should (assq 'python org-babel-load-languages))
  (should (assq 'shell org-babel-load-languages)))

(ert-deftest myemacs-org-hide-emphasis ()
  (should (bound-and-true-p org-hide-emphasis-markers)))

(ert-deftest myemacs-org-agenda-keybinding ()
  (should (eq (key-binding (kbd "C-c a")) 'org-agenda)))

(provide 'org-test)
;;; org-test.el ends here
