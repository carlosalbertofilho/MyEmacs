;;; custom-norminette.el --- 42 Norminette integration for Flycheck/Eglot -*- lexical-binding: t; -*-

;;; Commentary:
;; Modern integration of 42 School's Norminette with Emacs.
;; Uses JSON output (-f json --no-colors) for reliable parsing.
;; Supports checking unsaved buffers via --cfile.
;; Chains after eglot: eglot (clangd LSP) → norminette (style checker).

;;; Code:

(require 'flycheck)
(require 'json)

;; ── Configuration ───────────────────────────────────────────────────

(defgroup custom-norminette nil
  "42 School Norminette integration for Flycheck."
  :group 'flycheck
  :prefix "custom-norminette-")

(defcustom custom-norminette-executable "norminette"
  "Path to the norminette executable."
  :type 'string
  :group 'custom-norminette)

(defcustom custom-norminette-check-on-save t
  "Whether to check buffer on save."
  :type 'boolean
  :group 'custom-norminette)

;; ── Contextual hints for common errors ──────────────────────────────

(defvar custom-norminette-hints
  '(("INVALID_HEADER" . "Missing or invalid 42 header — Use C-c h to insert/update")
    ("TOO_MANY_FUNCS" . "More than 5 functions per file — Split into multiple files")
    ("TOO_MANY_LINES" . "Function has more than 25 lines — Refactor function")
    ("TOO_MANY_ARGS" . "Function has more than 4 arguments — Use struct or split")
    ("SPACE_REPLACE_TAB" . "Found space when expecting tab — Use tabs for indentation")
    ("TAB_REPLACE_SPACE" . "Found tab when expecting space — Use spaces where expected")
    ("SPACE_BEFORE_FUNC" . "Space before function name — Use tab for indentation")
    ("TOO_FEW_TAB" . "Missing tabs for indent level — Add proper indentation")
    ("NL_AFTER_PREPROC" . "Preprocessor must be followed by newline — Add blank line after #include")
    ("NO_ARGS_IN_MAIN" . "main() should have void args — Use int main(void)")
    ("BRACE_SHOULD_EOL" . "Opening brace should be on its own line — Move brace to new line")
    ("EOL_OPERATOR" . "Line ends with operator — Move operator to next line")
    ("SPACE_AFTER_CAST" . "Missing space after cast — Add space")
    ("PARENTHESIS_AROUND_RETURN" . "Return value needs parentheses — Use return (value)")
    ("RETURN_PARENTHESIS" . "Return with unnecessary parentheses — Remove parentheses")
    ("IDENTIFIER_TOO_LONG" . "Identifier exceeds max length — Shorten name")
    ("EXTRA_NEWLINE" . "Extra newline at end of file — Remove extra newline")
    ("SPACE_EMPTY_LINE" . "Space on empty line — Remove spaces")
    ("WRONG_SCOPE_VAR" . "Variable in wrong scope — Move declaration")
    ("VAR_DECL_START_FUNC" . "Variable declaration not at start — Move to top")
    ("TOO_MANY_VARIABLES" . "More than 5 variables in function — Reduce variables")
    ("TOO_MANY_STMTS" . "Too many statements in block — Refactor"))
  "Alist of norminette error names and contextual hints.")

;; ── JSON Parser ─────────────────────────────────────────────────────

(defun custom-norminette--parse-json (output &optional _filename)
  "Parse norminette JSON OUTPUT into flycheck errors."
  (when-let* ((data (ignore-errors (json-read-from-string output)))
              (files (alist-get 'files data))
              (file-data (car files))
              (errors (alist-get 'errors file-data '())))
    (let ((parsed-errors '()))
      (dolist (err errors)
        (let* ((name (alist-get 'name err))
               (text (alist-get 'text err))
               (level (alist-get 'level err))
               (highlights (alist-get 'highlights err))
               (highlight (car highlights))
               (line (alist-get 'lineno highlight 1))
               (col (alist-get 'column highlight 1))
               (length (alist-get 'length highlight))
               (hint (alist-get 'hint highlight))
               (message (format "%s: %s" name text)))
          ;; Add contextual hint if available
          (when-let* ((hint-entry (assoc name custom-norminette-hints)))
            (setq message (format "%s — %s" message (cdr hint-entry))))
          ;; Also use hint from JSON if present
          (when hint
            (setq message (format "%s (Hint: %s)" message hint)))
          (push (list :line line :col col :level level
                      :name name :message message :length length)
                parsed-errors)))
      parsed-errors)))

;; ── Flycheck Checker (JSON-based) ───────────────────────────────────

(flycheck-define-checker c-norminette
  "A C syntax checker using 42 School's Norminette (JSON output).

Checks C source files for compliance with 42 coding standards.
Uses JSON output for reliable parsing.
See URL `https://github.com/42School/norminette' for more information."
  :command ("norminette" "-f" "json" "--no-colors" source)
  :error-parser flycheck-parse-json
  :error-patterns
  ((error line-start
          (zero-or-more not-newline)
          "\"name\":\"" (id (one-or-more (not (any ?\")))) "\""
          (zero-or-more not-newline)
          "\"text\":\"" (message (one-or-more (not (any ?\")))) "\""
          (zero-or-more not-newline)
          "\"lineno\":" (zero-or-more space) line ","
          (zero-or-more space) "\"column\":" (zero-or-more space) column
          line-end))
  :error-filter
  (lambda (errors)
    (dolist (err errors)
      ;; Clean up message and add contextual hints
      (when-let* ((msg (flycheck-error-message err)))
        ;; Remove ANSI escape codes (shouldn't be there with --no-colors, but just in case)
        (setq msg (replace-regexp-in-string "\033\\[\\([0-9;]*\\)m" "" msg))
        (setq msg (string-trim msg))
        (setf (flycheck-error-message err) msg)
        ;; Add contextual hint based on error name
        (dolist (hint-entry custom-norminette-hints)
          (when (string-match (car hint-entry) msg)
            (setf (flycheck-error-message err)
                  (format "%s — %s" msg (cdr hint-entry)))
            (cl-return)))))
    ;; Filter out "OK" messages
    (seq-filter
     (lambda (err)
       (not (string-match "No norminette errors found\\|OK!"
                         (or (flycheck-error-message err) ""))))
     errors))
  :modes (c-mode c-ts-mode c++-mode c++-ts-mode)
  :predicate
  (lambda ()
    (and buffer-file-name
         (string-match-p "\\.\\(c\\|h\\)\\'" buffer-file-name)
         (executable-find custom-norminette-executable))))

;; ── Buffer check without saving (--cfile) ──────────────────────────

(defun custom-norminette-check-buffer ()
  "Run norminette on current buffer content without saving.
Uses --cfile to pass buffer content directly to norminette."
  (interactive)
  (unless (executable-find custom-norminette-executable)
    (user-error "Norminette not found.  Install with: python3 -m pip install norminette"))
  (unless buffer-file-name
    (user-error "Buffer must be associated with a file"))
  (unless (string-match-p "\\.\\(c\\|h\\)\\'" buffer-file-name)
    (user-error "Not a C/C++ file"))

  (let* ((content (buffer-string))
         (filename (file-name-nondirectory buffer-file-name))
         ;; Escape single quotes in content for shell
         (escaped-content (replace-regexp-in-string "'" "'\\''" content))
         (cmd (format "norminette -f json --no-colors --cfile '%s' --filename '%s'"
                      escaped-content filename))
         (output (shell-command-to-string cmd)))
    (if (string-match-p "\"status\":\"OK\"" output)
        (message "✅ Norminette: No errors found!")
      (let ((errors (custom-norminette--parse-json output filename)))
        (if errors
            (progn
              (flycheck-display-errors errors)
              (message "❌ Norminette: %d error(s) found" (length errors)))
          (message "✅ Norminette: No errors found!"))))))

;; ── Setup function ──────────────────────────────────────────────────

;;;###autoload
(defun custom-norminette-setup ()
  "Setup Norminette integration with Flycheck and Eglot."
  (interactive)
  ;; Add checker to flycheck
  (add-to-list 'flycheck-checkers 'c-norminette)

  ;; Chain after eglot (run norminette after LSP diagnostics)
  ;; Only if eglot checker is registered (not in batch mode)
  (when (and (fboundp 'flycheck-add-next-checker)
             (flycheck-checker-get 'eglot 'start))
    (flycheck-add-next-checker 'eglot 'c-norminette t))

  ;; Configure flycheck behavior
  (setq-default flycheck-check-syntax-automatically
                '(save mode-enabled newline)
                flycheck-display-errors-delay 0.3)

  ;; Enable on save if configured
  (when custom-norminette-check-on-save
    (add-hook 'after-save-hook #'custom-norminette--check-on-save nil t))

  (message "✅ Norminette integration ready (JSON-based)"))

(defun custom-norminette--check-on-save ()
  "Run norminette check after saving buffer."
  (when (and (derived-mode-p 'c-mode 'c-ts-mode 'c++-mode 'c++-ts-mode)
             buffer-file-name
             (executable-find custom-norminette-executable))
    (flycheck-buffer)))

;; ── Interactive commands ────────────────────────────────────────────

;;;###autoload
(defun custom-norminette-toggle ()
  "Toggle norminette checking on/off for the current buffer."
  (interactive)
  (if flycheck-mode
      (progn (flycheck-mode -1) (message "Norminette checking disabled"))
    (progn (flycheck-mode 1) (message "Norminette checking enabled"))))

;;;###autoload
(defun custom-norminette-select-checker ()
  "Select c-norminette as the active checker for this buffer."
  (interactive)
  (flycheck-select-checker 'c-norminette))

;; ── Auto-enable for C files ─────────────────────────────────────────

;;;###autoload
(defun custom-norminette-auto-enable ()
  "Automatically enable norminette for C/C++ files."
  (when (and buffer-file-name
             (string-match-p "\\.\\(c\\|h\\)\\'" buffer-file-name)
             (executable-find custom-norminette-executable))
    (flycheck-mode 1)
    (flycheck-select-checker 'c-norminette)))

(provide 'custom-norminette)
;;; custom-norminette.el ends here
