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

(defvar +carlos/gptel-tracker-file-override nil)

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

          ;; 2. Testar host: aa102-006l (EliteDesk - Ollama Local Default)
          (cl-letf (((symbol-function 'system-name) (lambda () "aa102-006l")))
            (+carlos/gptel-setup-defaults-by-host)
            (should (equal "Ollama Local" (gptel-backend-name gptel-backend)))
            (should (eq 'qwen2.5-coder:3b gptel-model))
            (should (equal "Ollama Local" +carlos/gptel-agent-backend))
            (should (eq 'qwen2.5-coder:3b +carlos/gptel-agent-model))
            (should (equal "Ollama Local" +carlos/gptel-quick-local-backend))
            (should (eq 'qwen2.5-coder:3b +carlos/gptel-quick-local-model)))

          ;; 3. Testar host fallback (outros -> Ollama Local Default)
          (cl-letf (((symbol-function 'system-name) (lambda () "unknown-host")))
            (+carlos/gptel-setup-defaults-by-host)
            (should (equal "Ollama Local" (gptel-backend-name gptel-backend)))
            (should (eq 'qwen2.5-coder:3b gptel-model))
            (should (equal "Ollama Local" +carlos/gptel-quick-local-backend))
            (should (eq 'qwen2.5-coder:3b +carlos/gptel-quick-local-model))))
      
      ;; Garantir a restauração dos estados originais de backend/modelo após o teste
      (setq gptel-backend old-backend
            gptel-model old-model
            +carlos/gptel-agent-backend old-agent-backend
            +carlos/gptel-agent-model old-agent-model
            +carlos/gptel-quick-local-backend old-quick-backend
            +carlos/gptel-quick-local-model old-quick-model))))

(ert-deftest myemacs-ai-dynamic-router ()
  "Valida se o roteamento dinâmico de IA escolhe os modelos/backends certos por contexto."
  :tags '(ai)
  (let ((old-backend gptel-backend)
        (old-model gptel-model))
    (unwind-protect
        (progn
          ;; 1. Testar Roteamento de Planejamento (/plan -> Gemini Pro free tier)
          (let ((buf (get-buffer-create "*gptel-plan*")))
            (with-current-buffer buf
              (setq gptel-backend nil
                    gptel-model nil)
              (+carlos/gptel-dynamic-router-advice "Monte um planejamento" :buffer buf)
              (should (equal "Gemini" (gptel-backend-name gptel-backend)))
              (should (eq 'gemini-2.5-pro gptel-model)))
            (kill-buffer buf))

          ;; 2. Testar Roteamento de Prompt Geral (Local offline -> Gemini Flash)
          (let ((buf (get-buffer-create "*test-general*")))
            (with-current-buffer buf
              (setq gptel-backend nil
                    gptel-model nil)
              (+carlos/gptel-dynamic-router-advice "Resuma o conteudo do link acima por favor" :buffer buf)
              ;; Pode ser Local (se online) ou Gemini Flash
              (should (member (gptel-backend-name gptel-backend) '("Ollama Local" "MLX Local" "Gemini")))
              (should (memq gptel-model '(qwen2.5-coder:3b mlx-community/Qwen3.5-9B-MLX-4bit gemini-2.5-flash))))
            (kill-buffer buf))

          ;; 3. Testar Roteamento de Código (Magent -> Local ou OpenCode Zen free)
          (let ((buf (get-buffer-create "*Magent-test*")))
            (with-current-buffer buf
              (setq gptel-backend nil
                    gptel-model nil)
              (+carlos/gptel-dynamic-router-advice "Escreva uma funcao" :buffer buf)
              (should (member (gptel-backend-name gptel-backend) '("Ollama Local" "MLX Local" "OpenCode Zen")))
              (should (memq gptel-model '(qwen2.5-coder:3b mlx-community/Qwen3.5-9B-MLX-4bit north-mini-code-free big-pickle))))
            (kill-buffer buf)))
)
      (setq gptel-backend old-backend
            gptel-model old-model)))

(ert-deftest myemacs-ai-dynamic-router-skips-magent ()
  "Valida que o roteador dinâmico NÃO sobrescreve requisições gerenciadas
pelo Magent (buffer ` *magent-llm-gptel-request*` ou contexto
:magent-llm-gptel), preservando o backend/modelo local escolhidos pelo Magent."
  :tags '(ai)
  (let ((old-backend gptel-backend)
        (old-model gptel-model))
    (unwind-protect
        (progn
          ;; 1. Requisição gerenciada pelo Magent (buffer) mantém backend/modelo
          (let ((buf (generate-new-buffer " *magent-llm-gptel-request*")))
            (with-current-buffer buf
              (setq-local gptel-backend (gptel-get-backend "Ollama Local")
                          gptel-model "qwen2.5-coder:3b")
              (+carlos/gptel-dynamic-router-advice
               "Ola! Analise o projeto Agent_Smith" :buffer buf)
              (should (equal "Ollama Local" (gptel-backend-name gptel-backend)))
              (should (equal "qwen2.5-coder:3b" gptel-model)))
            (kill-buffer buf))

          ;; 2. Requisição com contexto :magent-llm-gptel mantém backend/modelo
          (let ((buf (get-buffer-create "*test-magent-context*")))
            (with-current-buffer buf
              (setq-local gptel-backend (gptel-get-backend "Ollama Local")
                          gptel-model "qwen2.5-coder:3b")
              (+carlos/gptel-dynamic-router-advice
               "Refatore a funcao" :buffer buf
               :context '(:magent-llm-gptel t :top-p 0.8))
              (should (equal "Ollama Local" (gptel-backend-name gptel-backend)))
              (should (equal "qwen2.5-coder:3b" gptel-model)))
            (kill-buffer buf)))

      (setq gptel-backend old-backend
            gptel-model old-model))))

(ert-deftest myemacs-ai-tracker ()
  "Valida se a gravação de tokens do FinOps funciona e gera a tabela Org corretamente."
  :tags '(ai)
  (let* ((temp-file (make-temp-file "ai-usage-tracker-test" nil ".org")))
    (setq +carlos/gptel-tracker-file-override temp-file)
    (unwind-protect
        (let ((buf (get-buffer-create "*test-tracker*")))
          (with-current-buffer buf
            (cl-letf (((symbol-function 'gptel-backend-name) (lambda (&rest _) "Zen Claude")))
              (setq-local gptel-backend (gptel-get-backend "Zen Claude")
                          gptel-model 'claude-sonnet-5
                          gptel--token-usage '((:input 150 :output 75 :cached 50)
                                               (:input 150 :output 75 :cached 50)))
              (+carlos/gptel-track-usage nil nil)))
          
          ;; Valida se o arquivo foi criado e contém os dados corretos
          (should (file-exists-p temp-file))
          (with-temp-buffer
            (insert-file-contents temp-file)
            (goto-char (point-min))
            (should (search-forward "#+TITLE: Registro de Uso e Consumo de IA - FinOps" nil t))
            (should (search-forward "| No Agent (gptel) | Zen Claude | claude-sonnet-5 | 150 | 75 | 50 | $0.0016 (Market) |" nil t)))
          (kill-buffer buf))
      ;; Garante a limpeza do arquivo temporário e reset do override
      (setq +carlos/gptel-tracker-file-override nil)
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(ert-deftest myemacs-ai-show-usage-dashboard ()
  "Valida se o parser e a geração do dashboard +carlos/magent-show-usage funcionam."
  :tags '(ai)
  (let* ((temp-file (make-temp-file "ai-usage-tracker-test-dashboard" nil ".org")))
    (setq +carlos/gptel-tracker-file-override temp-file)
    (unwind-protect
        (progn
          ;; Prepara o arquivo com dados de teste
          (with-temp-file temp-file
            (insert "#+TITLE: Registro de Uso e Consumo de IA - FinOps\n")
            (insert "| Timestamp | Buffer | Agent | Backend | Modelo | Input | Output | Cached | Custo Est. |\n")
            (insert "|-----------+--------+-------+---------+--------+-------+--------+--------+------------|\n")
            (insert "| 2026-08-07 16:57:52 | *test* | Agent A | Zen Claude | claude-sonnet-5 | 100 | 50 | 10 | $0.0011 (Market) |\n")
            (insert "| 2026-08-07 17:00:00 | *test* | Agent A | Zen Claude | claude-sonnet-5 | 200 | 100 | 20 | $0.0021 (Market) |\n")
            (insert "| 2026-08-07 17:05:00 | *test* | No Agent (gptel) | Gemini | gemini-2.5-flash | 1000 | 500 | 0 | $0.0002 (Market) |\n"))
          
          ;; Executa a função
          (+carlos/magent-show-usage)
          
          ;; Verifica se o buffer foi gerado corretamente
          (let ((buf (get-buffer "*Magent Usage Summary*")))
            (should buf)
            (with-current-buffer buf
              (goto-char (point-min))
              (should (search-forward "#+TITLE: Resumo de Consumo de IA por Agente (Magent)" nil t))
              (should (re-search-forward "|\\s-*Agent\\s-*|\\s-*Input Tokens\\s-*|\\s-*Output Tokens\\s-*|\\s-*Cached Tokens\\s-*|\\s-*Est\\. Cost\\s-*|" nil t))
              ;; Agent A deve ter 300 input, 150 output, 30 cached, e $0.0032
              (should (re-search-forward "|\\s-*Agent A\\s-*|\\s-*300\\s-*|\\s-*150\\s-*|\\s-*30\\s-*|\\s-*\\$0\\.0032\\s-*|" nil t))
              ;; No Agent (gptel) deve ter 1000 input, 500 output, 0 cached, e $0.0002
              (goto-char (point-min))
              (should (re-search-forward "|\\s-*No Agent (gptel)\\s-*|\\s-*1000\\s-*|\\s-*500\\s-*|\\s-*0\\s-*|\\s-*\\$0\\.0002\\s-*|" nil t))
              ;; Total Geral deve ser 1300 input, 650 output, 30 cached, e $0.0034
              (goto-char (point-min))
              (should (re-search-forward "|\\s-*Total Geral\\s-*|\\s-*1300\\s-*|\\s-*650\\s-*|\\s-*30\\s-*|\\s-*\\$0\\.0034\\s-*|" nil t)))
            (kill-buffer buf)))
      ;; Limpeza
      (setq +carlos/gptel-tracker-file-override nil)
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(provide 'ai-test)
;;; ai-test.el ends here
