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

(ert-deftest myemacs-org-nov-installed ()
  "nov (leitor de EPUB) instalado e visível no load-path."
  (should (or (featurep 'nov) (locate-library "nov"))))

(ert-deftest myemacs-org-djvu-installed ()
  "djvu (DJVU) instalado e visível no load-path."
  (should (or (featurep 'djvu) (locate-library "djvu"))))

(ert-deftest myemacs-org-noter-supported-modes-full ()
  "org-noter suporta PDF, doc-view, nov (EPUB) e djvu sem warnings."
  (require 'org-noter nil t)
  (should (memq 'nov-mode org-noter-supported-modes))
  (should (memq 'djvu-read-mode org-noter-supported-modes)))

(ert-deftest myemacs-org-noter-no-missing-module-warnings ()
  "Boot sem warnings de módulos ausentes do org-noter (nov/djvu)."
  (with-current-buffer "*Messages*"
    (save-excursion
      (goto-char (point-min))
      (should-not (re-search-forward "package not found\\|needs the package" nil t)))))

(provide 'org-test)
;;; org-test.el ends here
