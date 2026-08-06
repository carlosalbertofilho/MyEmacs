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

;; ── c_formatter_42: executable guard ────────────────────────────────

(ert-deftest myemacs-42-formatter-executable-custom ()
  "The custom variable for c_formatter_42 executable is defined."
  (should (boundp '+carlos/c-formatter-42-executable))
  (should (stringp +carlos/c-formatter-42-executable))
  (should (string= +carlos/c-formatter-42-executable "c_formatter_42")))

(ert-deftest myemacs-42-formatter-format-on-save-custom ()
  "Format-on-save defaults to nil (off for 42 School)."
  (should (boundp '+carlos/c-formatter-42-format-on-save))
  (should (booleanp +carlos/c-formatter-42-format-on-save))
  (should-not +carlos/c-formatter-42-format-on-save))

(ert-deftest myemacs-42-formatter-commands-exist-when-executable ()
  "Commands are defined when c_formatter_42 is available."
  (skip-unless (executable-find +carlos/c-formatter-42-executable))
  (should (commandp '+carlos/c-formatter-42-buffer))
  (should (commandp '+carlos/c-formatter-42-region)))

(ert-deftest myemacs-42-formatter-keybinding-in-c-mode ()
  "C-c C-f is bound to c_formatter_42 in c-mode buffers."
  (skip-unless (executable-find +carlos/c-formatter-42-executable))
  (with-temp-buffer
    (c-mode)
    (my-c-42-style)
    (should (eq (key-binding (kbd "C-c C-f"))
                '+carlos/c-formatter-42-buffer))))

(ert-deftest myemacs-42-formatter-keybinding-not-global ()
  "C-c C-f is NOT globally bound (avoids dirvish-side conflict on C-c f)."
  (should (eq (key-binding (kbd "C-c f")) 'dirvish-side)))

(ert-deftest myemacs-42-formatter-group-defined ()
  "The defgroup for c_formatter_42 is registered."
  ;; defgroup registers the group symbol with a `group` property.
  (should (get '+carlos/c-formatter-42 'group))
  (should (boundp '+carlos/c-formatter-42-executable))
  (should (boundp '+carlos/c-formatter-42-format-on-save)))

;; ── Norminette: format-and-check pipeline ───────────────────────────

(ert-deftest myemacs-42-norminette-format-and-check-exists ()
  "The format-and-check command is defined when executables exist."
  (skip-unless (and (executable-find "c_formatter_42")
                    (executable-find custom-norminette-executable)))
  (should (commandp '+carlos/norminette-format-and-check)))

(ert-deftest myemacs-42-norminette-format-and-check-errors ()
  "format-and-check errors when c_formatter_42 is not installed."
  (let ((orig-fn (symbol-function 'executable-find)))
    (cl-letf (((symbol-function 'executable-find)
               (lambda (cmd)
                 (if (string= cmd "c_formatter_42") nil (funcall orig-fn cmd)))))
      (should-error (+carlos/norminette-format-and-check)
                    :type 'user-error))))

(provide '42-test)
;;; 42-test.el ends here
