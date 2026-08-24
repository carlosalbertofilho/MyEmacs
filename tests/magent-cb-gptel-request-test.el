;;; tests/magent-cb-gptel-request-test.el --- ERT tests for async circuit‑breaker gptel‑request advice -*- lexical-binding: t; -*-

;;; Commentary:
;; These tests verify that the newly added advice
;; `+carlos/magent-cb-gptel-request-advice` correctly records
;; failures and successes of asynchronous `gptel-request` calls in the
;; circuit‑breaker hash table.

;;; Code:
(require 'ert)
(require 'cl-lib)
(require 'custom-magent-tools) ; ensures the advice is loaded

;; Helper to reset the circuit‑breaker table before each test.
(defun +carlos/test--reset-cb ()
  (setq +carlos/magent-cb-failures (make-hash-table :test 'equal)))

(ert-deftest magent-cb-gptel-request-failure-test ()
  "Ensure a failed gptel‑request registers a failure in the CB."
  (+carlos/test--reset-cb)
  ;; Simulate the original gptel‑request function.
  (let ((orig-fn (lambda (prompt &rest args)
                   (let ((cb (plist-get args :callback)))
                     (funcall cb nil (list :error "simulated failure")))))
        (model-key "test:fail"))
    (funcall #'+carlos/magent-cb-gptel-request-advice
             orig-fn "dummy prompt"
             :backend "test" :model "fail"
             :callback (lambda (_response _info) nil))
    (should (equal (hash-table-count +carlos/magent-cb-failures) 1))
    (should (equal (car (gethash model-key +carlos/magent-cb-failures)) :failures)))
  )

(ert-deftest magent-cb-gptel-request-success-test ()
  "Ensure a successful gptel‑request records a success (clears entry)."
  (+carlos/test--reset-cb)
  (let ((model-key "test:ok"))
    ;; Pre‑populate a failure entry to ensure it gets cleared on success.
    (puthash model-key (list :failures 1 :timestamp (float-time)) +carlos/magent-cb-failures)
    (let ((orig-fn (lambda (prompt &rest args)
                     (let ((cb (plist-get args :callback)))
                       (funcall cb "ok-response" (list))))))
      (funcall #'+carlos/magent-cb-gptel-request-advice
               orig-fn "dummy prompt"
               :backend "test" :model "ok"
               :callback (lambda (_response _info) nil)))
    (should (= (hash-table-count +carlos/magent-cb-failures) 0)))
  )

(provide 'magent-cb-gptel-request-test)
;;; magent-cb-gptel-request-test.el ends here
