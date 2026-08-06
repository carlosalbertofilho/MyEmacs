;;; 42-test.el --- 42 School (header42 + norminette/eglot) tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Testa o header42 (login csilva-d, estrutura 80 colunas, stdheader
;; idempotente) e a integração norminette/eglot: parser JSON, checker
;; registrado no flycheck e chain eglot → c-norminette (regressão do
;; flycheck moderno, que usa `eglot-check' e não mais o checker `eglot').

;;; Code:

(require 'ert)
(require 'cl-lib)

(defun myemacs-42--count-matches (regexp string)
  "Count non-overlapping matches of REGEXP in STRING."
  (with-temp-buffer
    (insert string)
    (count-matches regexp (point-min) (point-max))))

(defun myemacs-42--line (n)
  "Return line N (1-based) of the current buffer."
  (save-excursion
    (goto-char (point-min))
    (forward-line (1- n))
    (buffer-substring-no-properties (line-beginning-position)
                                    (line-end-position))))

;; ── Header42: login ─────────────────────────────────────────────────

(ert-deftest myemacs-42-header-login-custom ()
  (should (equal header-42-login "csilva-d")))

(ert-deftest myemacs-42-header-get-user ()
  (should (equal (header-42-get-user) "csilva-d")))

(ert-deftest myemacs-42-header-get-mail ()
  (should (equal (header-42-get-mail) "csilva-d@student.42.fr")))

(ert-deftest myemacs-42-header-line-6-author ()
  (let ((line (header-42-generate-line 6)))
    (should (string-match-p "By: csilva-d <csilva-d@student.42.fr>" line))))

(ert-deftest myemacs-42-header-lines-80-columns ()
  (dotimes (i 11)
    (should (= header-42-length (length (header-42-generate-line (1+ i)))))))

;; ── Header42: insert/update idempotência ────────────────────────────

(ert-deftest myemacs-42-header-insert-structure ()
  (with-temp-buffer
    (header-42-insert)
    (let ((full (buffer-string)))
      (should (>= (count-lines (point-min) (point-max)) 11))
      (should (string-prefix-p "/* " (myemacs-42--line 1)))
      (should (string-match-p "By: csilva-d" (myemacs-42--line 6)))
      (should (string-match-p "Created: " (myemacs-42--line 8)))
      (should (string-match-p "Updated: " (myemacs-42--line 9)))
      (should (string-suffix-p " */" (myemacs-42--line 11)))
      (should (string-match-p "< new >" (myemacs-42--line 4)))
      (should (= 1 (myemacs-42--count-matches "By: " full))))))

(ert-deftest myemacs-42-header-stdheader-idempotent ()
  (with-temp-buffer
    (stdheader)
    (let ((lines-after-first (count-lines (point-min) (point-max))))
      (stdheader)
      (let ((full (buffer-string)))
        (should (= lines-after-first (count-lines (point-min) (point-max))))
        (should (= 1 (myemacs-42--count-matches "By: " full)))
        (should (= 1 (myemacs-42--count-matches "Updated: " full)))))))

(ert-deftest myemacs-42-header-update-keeps-single-header ()
  (with-temp-buffer
    (header-42-insert)
    (header-42-update)
    (let ((full (buffer-string)))
      (should (= 1 (myemacs-42--count-matches "By: " full)))
      (should (string-match-p "Updated: " (myemacs-42--line 9))))))

;; ── Norminette: parser JSON ─────────────────────────────────────────

(defconst myemacs-42-sample-json
  "{\"files\":[{\"path\":\"/tmp/foo.c\",\"status\":\"Error\",\
\"errors\":[{\"name\":\"INVALID_HEADER\",\"text\":\"Missing or invalid 42 header\",\
\"level\":\"Error\",\"highlights\":[{\"lineno\":1,\"column\":1,\
\"length\":null,\"hint\":null}]}]}]}"
  "Sample norminette JSON output (INVALID_HEADER).")

(ert-deftest myemacs-42-norminette-parse-json ()
  (let* ((errors (custom-norminette--parse-json myemacs-42-sample-json "foo.c"))
         (err (car errors)))
    (should (listp errors))
    (should (= 1 (length errors)))
    (should (string= "INVALID_HEADER" (plist-get err :name)))
    (should (= 1 (plist-get err :line)))
    (should (= 1 (plist-get err :col)))
    (should (string-match-p "INVALID_HEADER" (plist-get err :message)))
    (should (string-match-p "C-c h" (plist-get err :message)))))

(ert-deftest myemacs-42-norminette-parse-ok ()
  (let ((errors (custom-norminette--parse-json
                 "{\"files\":[{\"status\":\"OK\",\"errors\":[]}]}" "foo.c")))
    (should-not errors)))

(ert-deftest myemacs-42-norminette-parse-locale-prefix ()
  "Norminette may print 'Setting locale...' before the JSON output."
  (let* ((output (concat "Setting locale to en_US\n"
                         myemacs-42-sample-json))
         (errors (custom-norminette--parse-json output "foo.c"))
         (err (car errors)))
    (should (listp errors))
    (should (= 1 (length errors)))
    (should (string= "INVALID_HEADER" (plist-get err :name)))))

;; ── Norminette: flycheck integration ────────────────────────────────

(ert-deftest myemacs-42-norminette-parser-3args ()
  "The flycheck 39 error-parser interface requires 3 args."
  (let ((errors (custom-norminette--flycheck-parser
                 myemacs-42-sample-json 'c-norminette nil)))
    (should (listp errors))
    (should (= 1 (length errors)))))

(ert-deftest myemacs-42-norminette-checker-registered ()
  (should (memq 'c-norminette flycheck-checkers))
  (should (memq 'c-mode (flycheck-checker-get 'c-norminette 'modes))))

(ert-deftest myemacs-42-norminette-hints ()
  (should (assoc "INVALID_HEADER" custom-norminette-hints))
  (should (assoc "TOO_MANY_FUNCS" custom-norminette-hints)))

(ert-deftest myemacs-42-norminette-predicate ()
  (skip-unless (executable-find custom-norminette-executable))
  (with-temp-buffer
    (setq buffer-file-name "/tmp/foo.c")
    (setq buffer-file-truename "/tmp/foo.c")
    (should (funcall (flycheck-checker-get 'c-norminette 'predicate)))))

;; ── Chain eglot → c-norminette (regressão) ─────────────────────────

(ert-deftest myemacs-42-norminette-eglot-chain ()
  (let ((chainers '(eglot-check eglot)))
    (should
     (cl-some (lambda (chainer)
                (when (flycheck-valid-checker-p chainer)
                  (memq 'c-norminette
                        (flycheck-checker-get chainer 'next-checkers))))
              chainers))))

(provide '42-test)
;;; 42-test.el ends here
