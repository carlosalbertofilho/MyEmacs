;;; cli-test.el --- Tests for magent-cli wrapper -*- lexical-binding: t; -*-

;;; Commentary:
;; Testes ERT para bin/magent-cli (CLI wrapper).

;;; Code:

(require 'ert)

(defconst +carlos/magent-cli-path
  (expand-file-name "bin/magent-cli" (file-name-directory
                                       (directory-file-name
                                        (file-name-directory
                                         (or load-file-name default-directory)))))
  "Path to the magent-cli script.")

(ert-deftest myemacs-cli-help-exits-zero ()
  "magent-cli --help prints usage and exits 0."
  (let ((exit-code (call-process +carlos/magent-cli-path nil nil nil "--help")))
    (should (= exit-code 0))))

(ert-deftest myemacs-cli-no-tool-exits-nonzero ()
  "magent-cli with no args exits non-zero."
  (let ((exit-code (call-process +carlos/magent-cli-path nil nil nil)))
    (should-not (= exit-code 0))))

(ert-deftest myemacs-cli-list-tools-plain-contains-known-tool ()
  "magent-cli --list-tools --plain lists known tools."
  (let ((output (shell-command-to-string
                 (format "%s --list-tools --plain 2>/dev/null" +carlos/magent-cli-path))))
    (should (string-match-p "magit-status" output))
    (should (string-match-p "elisp-smart-edit" output))))

(ert-deftest myemacs-cli-describe-known-tool ()
  "magent-cli --describe magit_status shows tool info."
  (let ((output (shell-command-to-string
                 (format "%s -d magit_status --plain 2>/dev/null" +carlos/magent-cli-path))))
    (should (string-match-p "magit-status" output))
    (should (string-match-p "directory" output))))

(ert-deftest myemacs-cli-describe-unknown-tool-fails ()
  "magent-cli --describe nonexistent_tool shows error."
  (let ((output (shell-command-to-string
                 (format "%s -d nonexistent_tool --plain 2>/dev/null" +carlos/magent-cli-path))))
    (should (string-match-p "not found" output))))

(ert-deftest myemacs-cli-dry-run-shows-form ()
  "magent-cli --dry-run prints the Elisp form."
  (let ((output (shell-command-to-string
                 (format "%s --dry-run -d magit_status 2>/dev/null" +carlos/magent-cli-path))))
    (should (string-match-p "DRY RUN" output))
    (should (string-match-p "intern-soft" output))))

(ert-deftest myemacs-cli-describe-json-valid ()
  "magent-cli -d magit_status outputs valid JSON."
  (require 'json)
  (let ((output (shell-command-to-string
                 (format "%s -d magit_status 2>/dev/null" +carlos/magent-cli-path))))
    (let ((parsed (json-read-from-string output)))
      (should (consp parsed))
      (should (assq 'name parsed))
      (should (assq 'docstring parsed)))))

;;; cli-test.el ends here
