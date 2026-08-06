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

(provide 'ai-test)
;;; ai-test.el ends here
