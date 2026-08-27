;;; magent-run-test.el --- Tests for magent batch runner -*- lexical-binding: t; -*-

;;; Commentary:
;; Testes ERT para custom-magent-run.el (agent launcher batch).

;;; Code:

(require 'ert)

;; ── Sink tests ──────────────────────────────────────────────────────

(ert-deftest myemacs-run-jsonl-sink-writes-valid-jsonl ()
  "JSONL sink writes one valid JSON line per event."
  (let ((tmp (make-temp-file "magent-run-test-" nil ".jsonl"))
        (+carlos/magent-run--status-file nil)
        (+carlos/magent-run--sink-registered nil))
    (unwind-protect
        (progn
          (setq +carlos/magent-run--status-file tmp)
          ;; Simulate a turn-start event
          (funcall '+carlos/magent-run--jsonl-sink
                   (list :type 'turn-start :time (float-time) :turn-id "t1"))
          ;; Simulate a tool-call-start event
          (funcall '+carlos/magent-run--jsonl-sink
                   (list :type 'tool-call-start :time (float-time)
                         :tool-name "elisp_smart_edit" :call-id "c1"))
          ;; Read and parse
          (let ((lines (with-temp-buffer
                         (insert-file-contents tmp)
                         (split-string (buffer-string) "\n" t))))
            (should (= 2 (length lines)))
            ;; Each line should be valid JSON
            (dolist (line lines)
              (let ((parsed (json-read-from-string line)))
                (should (listp parsed))
                (should (assq 'type parsed))
                (should (assq 'time parsed))))))
      (ignore-errors (delete-file tmp)))))

(ert-deftest myemacs-run-jsonl-sink-handles-nil-status-file ()
  "JSONL sink is a no-op when status-file is nil."
  (let (+carlos/magent-run--status-file)
    ;; Should not error
    (funcall '+carlos/magent-run--jsonl-sink
             (list :type 'turn-start :time (float-time)))))

(ert-deftest myemacs-run-jsonl-sink-handles-nil-type ()
  "JSONL sink is a no-op when event type is nil."
  (let ((tmp (make-temp-file "magent-run-test-" nil ".jsonl"))
        (+carlos/magent-run--status-file nil))
    (unwind-protect
        (progn
          ;; Delete the file created by make-temp-file, then set as status-file
          (delete-file tmp)
          (setq +carlos/magent-run--status-file tmp)
          (funcall '+carlos/magent-run--jsonl-sink (list :time (float-time)))
          (should-not (file-exists-p tmp)))  ;; no file written
      (ignore-errors (delete-file tmp)))))

;; ── Model resolution tests ──────────────────────────────────────────

(ert-deftest myemacs-run-resolve-model-with-backend-model ()
  "Model resolution with explicit 'backend/model' string.
When backend is unknown, backend-obj is nil but names are extracted."
  (let ((result (+carlos/magent-run--resolve-model
                 "coder" "unknown-backend/my-model")))
    (should (string= "unknown-backend" (plist-get result :backend-name)))
    (should (string= "my-model" (plist-get result :model-name)))
    ;; backend-obj should be nil since the backend isn't registered
    (should-not (plist-get result :backend-obj))))

(ert-deftest myemacs-run-resolve-model-with-model-only ()
  "Model resolution with model name only (uses profile preferred backend)."
  (let ((result (+carlos/magent-run--resolve-model
                 "coder" "granite4.1:1b")))
    ;; Should use profile's preferred-backend as backend
    (should (string= "granite4.1:1b" (plist-get result :model-name)))
    (should (plist-get result :backend-name))))

(ert-deftest myemacs-run-resolve-model-nil-profile ()
  "Model resolution with nil profile defaults to general."
  (let ((result (+carlos/magent-run--resolve-model nil nil)))
    ;; Should still produce a result (even if model is unresolved)
    (should (listp result))))

;; ── Profile tools tests ─────────────────────────────────────────────

(ert-deftest myemacs-run-profile-tools-defined ()
  "Profile tools alist is defined and has expected entries."
  (should (boundp '+carlos/magent-run-profile-tools))
  (should (assoc "coder" +carlos/magent-run-profile-tools))
  (should (assoc "explore" +carlos/magent-run-profile-tools))
  (should (assoc "general" +carlos/magent-run-profile-tools)))

;; ── Register/unregister sink ────────────────────────────────────────

(ert-deftest myemacs-run-register-unregister-sink ()
  "Register and unregister sink without error."
  (let (+carlos/magent-run--sink-registered)
    (when (fboundp 'magent-lifecycle-events-add-sink)
      (+carlos/magent-run--register-sink)
      (should +carlos/magent-run--sink-registered)
      (+carlos/magent-run--unregister-sink)
      (should-not +carlos/magent-run--sink-registered))))

;; ── Execute function exists ─────────────────────────────────────────

(ert-deftest myemacs-run-execute-function-exists ()
  "+carlos/magent-run-execute is defined and callable."
  (should (fboundp '+carlos/magent-run-execute)))

;;; magent-run-test.el ends here
