;;; infra-test.el --- Tests for magent infrastructure utilities -*- lexical-binding: t; -*-

;;; Commentary:
;; Testes ERT para custom-magent-infra: project-root, string-trim, etc.

;;; Code:

(require 'ert)

(ert-deftest myemacs-infra-project-root-returns-string ()
  "project-root must always return a string path."
  (require 'custom-magent-infra nil t)
  (let ((root (+carlos/magent-project-root)))
    (should (stringp root))
    (should (file-name-absolute-p root))))

(ert-deftest myemacs-infra-project-root-is-directory ()
  "project-root must point to an existing directory."
  (require 'custom-magent-infra nil t)
  (let ((root (+carlos/magent-project-root)))
    (should (file-directory-p root))))

(ert-deftest myemacs-infra-string-trim-left ()
  "Portable string-trim-left removes leading whitespace."
  (require 'custom-magent-infra nil t)
  (should (equal (+carlos/magent--string-trim-left "  hello") "hello"))
  (should (equal (+carlos/magent--string-trim-left "hello") "hello"))
  (should (equal (+carlos/magent--string-trim-left "") "")))

(ert-deftest myemacs-infra-string-trim-right ()
  "Portable string-trim-right removes trailing whitespace."
  (require 'custom-magent-infra nil t)
  (should (equal (+carlos/magent--string-trim-right "hello  ") "hello"))
  (should (equal (+carlos/magent--string-trim-right "hello") "hello")))

(ert-deftest myemacs-infra-string-trim ()
  "Portable string-trim removes both leading and trailing whitespace."
  (require 'custom-magent-infra nil t)
  (should (equal (+carlos/magent--string-trim "  hello  ") "hello"))
  (should (equal (+carlos/magent--string-trim "hello") "hello")))

;;; infra-test.el ends here
