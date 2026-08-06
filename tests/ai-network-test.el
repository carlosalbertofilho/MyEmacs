;;; ai-network-test.el --- Live AI backend tests (opt-in) -*- lexical-binding: t; -*-

;;; Commentary:
;; Testes de REDE: fazem uma requisição real a cada backend gptel e
;; verificam que respondem "PONG". Gated por EMACS_TEST_NETWORK=1 para não
;; travar o CI. Sem a envvar, os testes aparecem como "skipped".
;;
;; Uso:
;;   EMACS_TEST_NETWORK=1 just test-batch

;;; Code:

(require 'ert)
(require 'gptel)
(require 'cl-lib)

(defun myemacs-ai--request-pong (backend model)
  "Envia \"Reply with exactly: PONG\" para BACKEND/MODEL.
Retorna não-nil se a resposta contiver \"PONG\". Timeout de 90s."
  (let ((done nil) (result nil) (err nil))
    (with-temp-buffer
      (setq-local gptel-backend (gptel-get-backend backend))
      (setq-local gptel-model model)
      (gptel-request "Reply with exactly: PONG" :system "Be concise."
        :callback (lambda (response info)
                    (setq done t)
                    (if response
                        (setq result response)
                      (setq err (plist-get info :error))))))
    (let ((deadline (+ (float-time) 90)))
      (while (and (not done) (< (float-time) deadline))
        (sleep-for 0.5)))
    (cond (result (string-match-p "PONG" result))
          (err (progn
                 (message "myemacs-ai: backend error %S" err)
                 nil))
          (t (message "myemacs-ai: timeout (%s/%s)" backend model) nil))))

(ert-deftest myemacs-ai-network-zen-openai ()
  :tags '(ai network)
  (skip-unless (getenv "EMACS_TEST_NETWORK"))
  (should (myemacs-ai--request-pong "OpenCode Zen" "deepseek-v4-flash-free")))

(ert-deftest myemacs-ai-network-zen-claude ()
  :tags '(ai network)
  (skip-unless (getenv "EMACS_TEST_NETWORK"))
  (should (myemacs-ai--request-pong "Zen Claude" "claude-sonnet-5")))

(ert-deftest myemacs-ai-network-gemini ()
  :tags '(ai network)
  (skip-unless (getenv "EMACS_TEST_NETWORK"))
  (should (myemacs-ai--request-pong "Gemini" "gemini-2.5-flash")))

(ert-deftest myemacs-ai-network-ollama ()
  :tags '(ai network)
  (skip-unless (getenv "EMACS_TEST_NETWORK"))
  (should (myemacs-ai--request-pong "Ollama Local" "qwen3:0.6b")))

(ert-deftest myemacs-ai-network-mlx ()
  :tags '(ai network)
  (skip-unless (getenv "EMACS_TEST_NETWORK"))
  (should (myemacs-ai--request-pong
           "MLX Local" "mlx-community/Qwen3.5-9B-MLX-4bit")))

(provide 'ai-network-test)
;;; ai-network-test.el ends here
