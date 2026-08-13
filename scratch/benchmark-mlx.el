;;; benchmark-mlx.el --- Benchmark MLX Local Models using Emacs GPTel -*- lexical-binding: t; -*-

;; Ensure elpaca is fully completed before loading packages
(when (fboundp 'elpaca-wait)
  (elpaca-wait))

(require 'custom-ai)
(require 'gptel)
(require 'cl-lib)

(defvar benchmark-prompt "Write a recursive function to calculate the Fibonacci sequence in Emacs Lisp. Be extremely concise, outputting only the code.")

(defun run-single-benchmark (model-name)
  "Executes a prompt against MODEL-NAME using GPTel and returns performance metrics."
  (message "\n==================================================")
  (message "Testing model: %s" model-name)
  (message "==================================================")
  
  (let ((backend (gptel-get-backend "MLX Local")))
    (unless backend
      (error "ERROR: Backend 'MLX Local' not found! Make sure custom-ai is loaded."))
    
    (let* ((start-time (float-time))
           (ttft-time nil)
           (end-time nil)
           (response-text nil)
           (error-msg nil)
           (done nil)
           (temp-buf (generate-new-buffer (format " *benchmark-%s*" model-name))))
      
      ;; Set local variables for the buffer to use the specific model
      (with-current-buffer temp-buf
        (setq-local gptel-backend backend)
        (setq-local gptel-model model-name)
        
        (message "Sending request...")
        (gptel-request benchmark-prompt
          :system "Be concise."
          :buffer temp-buf
          :callback (lambda (response info)
                      (setq end-time (float-time))
                      (if response
                          (setq response-text response)
                        (setq error-msg (plist-get info :error)))
                      (setq done t))))
      
      ;; Wait loop (non-blocking for Emacs process output)
      (let ((timeout 60)
            (wait-start (float-time)))
        (while (and (not done) (< (- (float-time) wait-start) timeout))
          (accept-process-output nil 0.1)))
      
      ;; Clean up buffer
      (kill-buffer temp-buf)
      
      (if error-msg
          (progn
            (message "ERROR: Failed to run model %s: %s" model-name error-msg)
            (list :model model-name :status "error" :error error-msg))
        (if (not response-text)
            (progn
              (message "TIMEOUT: Model %s did not respond within 60s" model-name)
              (list :model model-name :status "timeout"))
          (let* ((duration (- end-time start-time))
                 (char-count (length response-text))
                 ;; Estimate tokens (1 token ≈ 4 characters)
                 (token-count (max 1 (/ char-count 4)))
                 (tokens-per-sec (/ token-count duration)))
            (message "Completed in %.2f seconds." duration)
            (message "Tokens generated: ~%d (chars: %d)" token-count char-count)
            (message "Speed: %.2f tok/s" tokens-per-sec)
            (list :model model-name
                  :status "success"
                  :duration duration
                  :tokens token-count
                  :speed tokens-per-sec
                  :response (substring response-text 0 (min 150 (length response-text))))))))))

(defun run-all-benchmarks ()
  "Runs the benchmark matrix across all 3 active MLX models."
  (let ((models '("mlx-community/gemma-4-e2b-it-4bit"
                  "mlx-community/Qwen3.5-9B-MLX-4bit"
                  "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit"))
        (results nil))
    (dolist (m models)
      (push (run-single-benchmark m) results))
    
    ;; Print Markdown Table of results
    (message "\n\n### MATRIX BENCHMARK RESULTS (agnes.local MLX via gptel)")
    (message "| Model | Status | Speed (tok/s) | Latency / Turn Time | Size (Tokens) | Quality Notes |")
    (message "|-------|--------|---------------|---------------------|---------------|---------------|")
    (dolist (res (reverse results))
      (let ((model (plist-get res :model))
            (status (plist-get res :status)))
        (if (string-equal status "success")
            (let ((speed (plist-get res :speed))
                  (duration (plist-get res :duration))
                  (tokens (plist-get res :tokens))
                  (response (plist-get res :response)))
              (message "| %s | %s | **%.2f tok/s** | %.2fs | ~%d | Code returned: %s... |"
                       model status speed duration tokens (string-replace "\n" " " response)))
          (message "| %s | FAILED (%s) | - | - | - | - |" model status))))))

(run-all-benchmarks)
