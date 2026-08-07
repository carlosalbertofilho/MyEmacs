;;; ai-test.el --- AI stack (gptel) regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifica backends, URLs corrigidas, diretivas (não clobbered pelo gotcha
;; do Emacs 30), agentes e diretórios globais. Testes ao vivo (rede) ficam
;; em ai-network-test.el (opt-in via EMACS_TEST_NETWORK).

;;; Code:

(require 'ert)
(require 'gptel)
(require 'gptel-context nil t)
(require 'gptel-agent)
(require 'cl-lib)

(defun myemacs-ai--backend-names ()
  "Nomes dos backends registrados no gptel."
  (mapcar #'car gptel--known-backends))

(defun myemacs-ai--agent-names ()
  "Nomes dos agentes registrados no gptel-agent."
  (mapcar #'car gptel-agent--agents))

(ert-deftest myemacs-ai-backends-registered ()
  :tags '(ai)
  (dolist (name '("MLX Local" "Ollama Local" "Gemini" "Zen Claude"
                  "OpenCode Zen"))
    (should (gptel-get-backend name))))

(ert-deftest myemacs-ai-zen-openai-url ()
  :tags '(ai)
  (should (equal "https://opencode.ai/zen/v1/chat/completions"
                 (gptel-backend-url (gptel-get-backend "OpenCode Zen")))))

(ert-deftest myemacs-ai-zen-claude-url ()
  :tags '(ai)
  (should (equal "https://opencode.ai/zen/v1/messages"
                 (gptel-backend-url (gptel-get-backend "Zen Claude")))))

(ert-deftest myemacs-ai-no-gptel-org ()
  :tags '(ai)
  (should-not (featurep 'gptel-org))
  (should-not (fboundp 'gptel-org-mode)))

(ert-deftest myemacs-ai-default-directives-preserved ()
  :tags '(ai)
  (dolist (key '(default programming writing chat))
    (should (assq key gptel-directives))))

(ert-deftest myemacs-ai-custom-directives ()
  :tags '(ai)
  (dolist (key '(c-42 cpp-42 python))
    (should (assq key gptel-directives))))

(ert-deftest myemacs-ai-agent-dir-registered ()
  :tags '(ai)
  (should (member (expand-file-name "~/.agents/gptel/") gptel-agent-dirs)))

(ert-deftest myemacs-ai-agent-dir-exists ()
  :tags '(ai)
  (should (cl-some #'file-directory-p gptel-agent-dirs)))

(ert-deftest myemacs-ai-agents ()
  :tags '(ai)
  (dolist (agent '("researcher" "introspector" "gptel-plan"
                   "gptel-agent" "executor"))
    (should (member agent (myemacs-ai--agent-names)))))

(ert-deftest myemacs-ai-agent-presets ()
  :tags '(ai)
  (dolist (preset '(gptel-agent gptel-plan))
    (should (assq preset gptel--known-presets))))

(ert-deftest myemacs-ai-context-allow-all-files ()
  :tags '(ai)
  (should-not gptel-context-restrict-to-project-files))

(ert-deftest myemacs-ai-host-detection ()
  :tags '(ai)
  (let ((old-backend gptel-backend)
        (old-model gptel-model)
        (old-agent-backend +carlos/gptel-agent-backend)
        (old-agent-model +carlos/gptel-agent-model)
        (old-quick-backend +carlos/gptel-quick-local-backend)
        (old-quick-model +carlos/gptel-quick-local-model))
    (unwind-protect
        (progn
          ;; 1. Testar host: agnes (macOS M2)
          (cl-letf (((symbol-function 'system-name) (lambda () "agnes.local")))
            (+carlos/gptel-setup-defaults-by-host)
            (should (equal "MLX Local" (gptel-backend-name gptel-backend)))
            (should (eq 'mlx-community/Qwen3.5-9B-MLX-4bit gptel-model))
            (should (equal "MLX Local" +carlos/gptel-agent-backend))
            (should (eq 'mlx-community/Qwen3.5-9B-MLX-4bit +carlos/gptel-agent-model))
            (should (equal "MLX Local" +carlos/gptel-quick-local-backend))
            (should (eq 'mlx-community/Qwen3.5-9B-MLX-4bit +carlos/gptel-quick-local-model)))

          ;; 2. Testar host: aa102-006l (EliteDesk)
          (cl-letf (((symbol-function 'system-name) (lambda () "aa102-006l")))
            (+carlos/gptel-setup-defaults-by-host)
            (should (equal "Zen Claude" (gptel-backend-name gptel-backend)))
            (should (eq 'claude-sonnet-5 gptel-model))
            (should (equal "Zen Claude" +carlos/gptel-agent-backend))
            (should (eq 'claude-sonnet-5 +carlos/gptel-agent-model))
            (should (equal "Ollama Local" +carlos/gptel-quick-local-backend))
            (should (eq 'qwen2.5-coder:3b +carlos/gptel-quick-local-model)))

          ;; 3. Testar host fallback (outros)
          (cl-letf (((symbol-function 'system-name) (lambda () "unknown-host")))
            (+carlos/gptel-setup-defaults-by-host)
            (should (equal "Zen Claude" (gptel-backend-name gptel-backend)))
            (should (eq 'claude-sonnet-5 gptel-model))
            (should (equal "Zen Claude" +carlos/gptel-quick-local-backend))
            (should (eq 'claude-sonnet-5 +carlos/gptel-quick-local-model))))
      
      ;; Garantir a restauração dos estados originais de backend/modelo após o teste
      (setq gptel-backend old-backend
            gptel-model old-model
            +carlos/gptel-agent-backend old-agent-backend
            +carlos/gptel-agent-model old-agent-model
            +carlos/gptel-quick-local-backend old-quick-backend
            +carlos/gptel-quick-local-model old-quick-model))))

(provide 'ai-test)
;;; ai-test.el ends here
