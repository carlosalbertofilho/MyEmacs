;;; heavy-context-benchmark.el --- Heavy Context MLX Model Benchmark -*- lexical-binding: t; -*-

(when (fboundp 'elpaca-wait)
  (elpaca-wait))

(require 'custom-ai)
(require 'gptel)
(require 'cl-lib)

;; Bypass dynamic router advice completely during this benchmark run
(when (advice-member-p #'+carlos/gptel-dynamic-router-advice 'gptel-request)
  (advice-remove 'gptel-request #'+carlos/gptel-dynamic-router-advice))

(defun myemacs-ai--clean-response-to-string (response)
  "Converte RESPONSE (que pode ser string, cons cell ou lista) em uma string limpa."
  (cond
   ((stringp response) response)
   ((and (consp response) (stringp (cdr response))) (cdr response))
   ((and (consp response) (stringp (car response))) (car response))
   ((and (consp response) (listp response))
    (apply #'concat
           (mapcar (lambda (part)
                     (cond ((stringp part) part)
                           ((and (consp part) (stringp (cdr part))) (cdr part))
                           ((and (consp part) (stringp (car part))) (car part))
                           (t "")))
                   response)))
   (t (format "%S" response))))

(defun get-project-context-string ()
  "Reads files in lisp/ and init.el to create a single massive context string."
  (let ((files '("init.el"
                 "early-init.el"
                 "lisp/custom-core.el"
                 "lisp/custom-ai.el"
                 "lisp/custom-magent.el"
                 "lisp/custom-keybindings.el"
                 "lisp/custom-ui.el"))
        (context-parts nil))
    (dolist (f files)
      (let ((path (expand-file-name f "/Users/carlosfilho/Projects/Github/MyEmacs")))
        (if (file-exists-p path)
            (with-temp-buffer
              (insert-file-contents path)
              (push (format "\n;; === FILE: %s ===\n%s\n" f (buffer-string)) context-parts))
          (message "Warning: File %s not found for context collection." f))))
    (apply #'concat (reverse context-parts))))

(defun run-heavy-benchmark-for-model (model-name prompt-context)
  "Runs the heavy context prompt against MODEL-NAME and measures performance."
  (message "\n==================================================")
  (message "HEAVY BENCHMARK: %s" model-name)
  (message "==================================================")
  
  (let ((backend (gptel-get-backend "MLX Local")))
    (unless backend
      (error "ERROR: Backend 'MLX Local' not found! Make sure custom-ai is loaded."))
    
    (let* ((orig-backend gptel-backend)
           (orig-model gptel-model)
           (start-time (float-time))
           (end-time nil)
           (response-text nil)
           (error-msg nil)
           (done nil)
           (temp-buf (generate-new-buffer (format " *heavy-%s*" model-name)))
           (full-prompt (format "You are an expert Emacs Lisp architect. Below is the complete configuration code for the MyEmacs project. Please analyze this code and provide a concise, high-level summary of its architecture (under 250 words), detailing how the modules communicate and highlighting the key strengths and design decisions (such as the dynamic AI routing and local MLX/Ollama fallback setup). Code:\n\n%s" prompt-context)))
      
      (unwind-protect
          (progn
            ;; Set global variables during request and wait loop to guarantee
            ;; that the async curl setup and callback read the correct backend key.
            ;; Convert string to symbol for gptel-model.
            (setq gptel-backend backend
                  gptel-model (intern model-name))
            
            (message "Sending heavy request (Context: ~%d chars)..." (length full-prompt))
            (gptel-request full-prompt
              :system "Be concise, precise, and analytical."
              :buffer temp-buf
              :callback (lambda (response info)
                          (setq end-time (float-time))
                          (if response
                              (setq response-text (myemacs-ai--clean-response-to-string response))
                            (setq error-msg (plist-get info :error)))
                          (setq done t)))
            
            ;; Wait loop (non-blocking for Emacs process output, timeout 180s for heavy context)
            (let ((timeout 180)
                  (wait-start (float-time)))
              (while (and (not done) (< (- (float-time) wait-start) timeout))
                (accept-process-output nil 0.5))))
        ;; Restore global variables
        (setq gptel-backend orig-backend
              gptel-model orig-model))
      
      ;; Clean up buffer
      (kill-buffer temp-buf)
      
      (if error-msg
          (progn
            (message "ERROR: Failed to run heavy benchmark for %s: %s" model-name error-msg)
            (list :model model-name :status "error" :error error-msg))
        (if (not response-text)
            (progn
              (message "TIMEOUT: Model %s did not respond within 180s" model-name)
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
                  :response response-text)))))))

(defun run-all-heavy-benchmarks ()
  "Runs the heavy context benchmark across all 3 active MLX models."
  (message "Collecting project context files...")
  (let* ((context (get-project-context-string))
         (models '("mlx-community/gemma-4-e2b-it-4bit"
                   "mlx-community/Qwen3.5-9B-MLX-4bit"
                   "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit"))
         (results nil))
    (message "Collected context size: %d characters (approx. %d tokens)" (length context) (/ (length context) 4))
    (dolist (m models)
      (push (run-heavy-benchmark-for-model m context) results))
    
    ;; Print Markdown Report of results
    (message "\n\n### HEAVY CONTEXT ARCHITECTURE BENCHMARK RESULTS (agnes.local MLX via gptel)")
    (message "| Model | Status | Speed (tok/s) | Total Time | Size (Tokens) | Architecture Synthesis |")
    (message "|-------|--------|---------------|------------|---------------|------------------------|")
    (dolist (res (reverse results))
      (let ((model (plist-get res :model))
            (status (plist-get res :status)))
        (if (string-equal status "success")
            (let ((speed (plist-get res :speed))
                  (duration (plist-get res :duration))
                  (tokens (plist-get res :tokens))
                  (response (plist-get res :response)))
              (message "| %s | %s | **%.2f tok/s** | %.2fs | ~%d | %s |"
                       model status speed duration tokens (string-replace "\n" " " response)))
          (message "| %s | FAILED (%s) | - | - | - | - |" model status))))))

(run-all-heavy-benchmarks)
