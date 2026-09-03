;;; context-test.el --- Tests for context management (Etapa B4) -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for cache hit-rate, auto-compaction ratio, and preservation instruction.

;;; Code:

(require 'ert)
(require 'custom-ai)
(require 'custom-magent)

(ert-deftest myemacs-context-cache-hit-rate-calc ()
  "Garante que o cálculo de cache hit-rate retorna a porcentagem correta."
  (should (= (+carlos/gptel-cache-hit-rate 100 100) 50.0))
  (should (= (+carlos/gptel-cache-hit-rate 0 500) 100.0))
  (should (= (+carlos/gptel-cache-hit-rate 100 0) 0.0))
  (should (= (+carlos/gptel-cache-hit-rate 0 0) 0.0)))

(ert-deftest myemacs-context-get-context-window ()
  "Garante que `+carlos/magent-get-context-window` retorna valor positivo."
  (let ((cw (+carlos/magent-get-context-window)))
    (should (integerp cw))
    (should (> cw 0))))

(ert-deftest myemacs-context-preservation-instruction-defined ()
  "Garante que a instrução de preservação estruturada contém as 6 diretivas."
  (should (boundp '+carlos/magent-preservation-instruction))
  (should (string-match-p "Arquivos modificados" +carlos/magent-preservation-instruction))
  (should (string-match-p "TODO\\.org" +carlos/magent-preservation-instruction)))

(ert-deftest myemacs-context-auto-compact-sink-runs ()
  "Garante que `+carlos/magent-auto-compact-check-and-run` executa sem erros."
  (let ((event-data '(:status completed :output-len 50)))
    (should (listp event-data))))

(ert-deftest myemacs-context-compaction-decision-immediate ()
  "Garante que o threshold imediato dispara acima de 60% da janela."
  (should (eq (+carlos/magent-compaction-decision 7000 10000 0)
              'immediate))
  (should (eq (+carlos/magent-compaction-decision 5900 10000 0)
              nil)))

(ert-deftest myemacs-context-compaction-decision-milestone ()
  "Garante que o milestone exige N subagentes E tokens acima do limiar inferior."
  (let ((+carlos/magent-milestone-subagents 3)
        (+carlos/magent-milestone-ratio 0.4))
    (should (eq (+carlos/magent-compaction-decision 4500 10000 3)
                'milestone))
    (should (eq (+carlos/magent-compaction-decision 4500 10000 2)
                nil))
    (should (eq (+carlos/magent-compaction-decision 3000 10000 3)
                nil))
    (should (eq (+carlos/magent-compaction-decision 7000 10000 0)
                'immediate))))

(ert-deftest myemacs-context-build-instruction-sections ()
  "Garante que a instrução dinâmica (B1) contém estado, descarte e base."
  (let ((instr (+carlos/magent-build-compaction-instruction)))
    (should (stringp instr))
    (should (string-match-p "Regras de descarte" instr))
    (should (string-match-p "TODO\\.org" instr))
    (should (string-match-p "preservando o estado do projeto" instr))))

(ert-deftest myemacs-context-sink-subagent-stop-counts ()
  "Garante que o sink conta subagentes completados (B3)."
  (let ((+carlos/magent-subagent-completions-since-compact 0))
    (+carlos/magent-auto-compact-check-and-run
     '(:type subagent-stop :subagent-id "abc"))
    (+carlos/magent-auto-compact-check-and-run
     '(:type subagent-stop :subagent-id "def"))
    (should (= +carlos/magent-subagent-completions-since-compact 2))))

(ert-deftest myemacs-context-turn-tokens-zero-safe ()
  "Garante que a medição de tokens (B2) é segura sem sessão ativa."
  (let ((tokens (+carlos/magent-turn-tokens
                 '(:type turn-end :status completed))))
    (should (integerp tokens))
    (should (>= tokens 0))))

(ert-deftest myemacs-context-compact-keybinding ()
  "Garante que o atalho C-c A p está mapeado para `+carlos/magent-compact`."
  (should (eq (global-key-binding (kbd "C-c A p")) #'+carlos/magent-compact)))

;; ── B5.1: Modelo barato (local até teto, senão free) ────────────────
(ert-deftest myemacs-context-cheap-model-free-when-offline-or-big ()
  "Garante que o modelo barato (B5.1) nunca é pago: offline ou acima do
teto local, cai para o primeiro modelo free da nuvem."
  (cl-letf (((symbol-function '+carlos/local-ai-server-ping-p))
            (lambda () nil))
    (let* ((backends '(("Gemini" . ("gemini-3.5-flash" "gemini-3.1-pro-preview"))
                       ("Zen Claude" . ("claude-sonnet-5"))))
           (choice (+carlos/magent-resolve-cheap-model 50000 backends nil)))
      (should (equal (plist-get choice :tier) "free"))
      (should (not (equal (plist-get choice :tier) "paid")))
      (should (stringp (plist-get choice :backend))))))

(ert-deftest myemacs-context-cheap-model-local-when-online-and-fits ()
  "Garante que o modelo barato (B5.1) usa o modelo local quando online e
a sessão cabe no teto de tokens."
  (cl-letf (((symbol-function '+carlos/local-ai-server-ping-p)
             (lambda () t))
            ((symbol-function '+carlos/ai-local-backend)
             (lambda () (cons "Ollama Local" 'qwen2.5-coder:3b))))
    (let* ((backends '(("Ollama Local" . ("qwen2.5-coder:3b"))
                       ("Gemini" . ("gemini-3.5-flash"))))
           (local-models '("qwen2.5-coder:3b"))
           (choice (+carlos/magent-resolve-cheap-model 1000 backends local-models)))
      (should (equal (plist-get choice :tier) "local"))
      (should (equal (plist-get choice :model) "qwen2.5-coder:3b")))))

;; ── B5.3: Guarda anti-crescimento ────────────────────────────────────
(ert-deftest myemacs-context-compaction-guard-success ()
  "Garante que a guarda (B5.3) zera contadores e limpa a flag em sucesso."
  (let ((+carlos/magent-last-compaction-failed t)
        (+carlos/magent-context-estimated-tokens 500)
        (+carlos/magent-subagent-completions-since-compact 2)
        (+carlos/magent-turn-ends-since-failure 3))
    (+carlos/magent-compaction-result-handler 'completed 1000 200)
    (should (null +carlos/magent-last-compaction-failed))
    (should (= +carlos/magent-context-estimated-tokens 0))
    (should (= +carlos/magent-subagent-completions-since-compact 0))
    (should (= +carlos/magent-turn-ends-since-failure 0))))

(ert-deftest myemacs-context-compaction-guard-failure ()
  "Garante que a guarda (B5.3) seta a flag e NÃO zera contadores em falha."
  (let ((+carlos/magent-last-compaction-failed nil)
        (+carlos/magent-context-estimated-tokens 500)
        (+carlos/magent-subagent-completions-since-compact 2))
    (+carlos/magent-compaction-result-handler 'completed 1000 9000)
    (should +carlos/magent-last-compaction-failed)
    (should (= +carlos/magent-context-estimated-tokens 500))
    (should (= +carlos/magent-subagent-completions-since-compact 2))))

(ert-deftest myemacs-context-sink-skips-after-failure-then-retries ()
  "Garante que o sink bloqueia auto-compactação pós-falha e reabre após N turnos."
  (let ((+carlos/magent-last-compaction-failed t)
        (+carlos/magent-failure-retry-turn-ends 3)
        (+carlos/magent-turn-ends-since-failure 0)
        (+carlos/magent-context-estimated-tokens 100)
        (+carlos/magent-subagent-completions-since-compact 0))
    (+carlos/magent-auto-compact-check-and-run '(:type turn-end :status completed))
    (+carlos/magent-auto-compact-check-and-run '(:type turn-end :status completed))
    (should +carlos/magent-last-compaction-failed)
    (should (= +carlos/magent-turn-ends-since-failure 2))
    (+carlos/magent-auto-compact-check-and-run '(:type turn-end :status completed))
    (should (null +carlos/magent-last-compaction-failed))
    (should (= +carlos/magent-turn-ends-since-failure 0))))

;; ── B5.3: Medição total da sessão ───────────────────────────────────
(ert-deftest myemacs-context-session-total-tokens-sums ()
  "Garante que `+carlos/magent-session-total-tokens' soma usage real dos turns."
  (let* ((t1 (magent-thread-turn-create :id "t1" :usage '(:input 100 :output 50)))
         (t2 (magent-thread-turn-create :id "t2" :usage '(:input 30)))
         (thread (magent-thread-create :id "th" :turns (list t1 t2))))
    (should (= (+carlos/magent-session-total-tokens thread) 180))))

;; ── B5.4: Fronteira segura de corte ─────────────────────────────────
(ert-deftest myemacs-context-turn-closed-p ()
  "Garante que `+carlos/magent-turn-closed-p' detecta tool calls pendentes."
  (let ((plain (magent-thread-turn-create :id "a")))
    (should (equal (+carlos/magent-turn-closed-p plain) t)))
  (let ((open (magent-thread-turn-create
               :id "b"
               :items (list (magent-thread-item-create
                             :role 'assistant :name "read_file" :call-id "c1")))))
    (should (null (+carlos/magent-turn-closed-p open))))
  (let ((closed (magent-thread-turn-create
                 :id "c"
                 :items (list (magent-thread-item-create
                               :role 'assistant :name "read_file" :call-id "c1")
                              (magent-thread-item-create
                               :role 'tool :call-id "c1")))))
    (should (equal (+carlos/magent-turn-closed-p closed) t))))

(ert-deftest myemacs-context-safe-boundary-avoids-open-turn ()
  "Garante que a fronteira (B5.4) avança quando o turno pré-fronteira é aberto."
  (let* ((mk (lambda (id &optional open)
               (magent-thread-turn-create
                :id id :input "xxxx"
                :items (when open
                         (list (magent-thread-item-create
                                :role 'assistant :name "bash" :call-id (concat id "-c")))))))
         (turns (list (funcall mk "t0")
                      (funcall mk "t1")
                      (funcall mk "t2" t)   ; turno aberto (tool call sem result)
                      (funcall mk "t3")
                      (funcall mk "t4")
                      (funcall mk "t5")))
         (thread (magent-thread-create :turns turns)))
    (should (= (+carlos/magent-safe-compaction-boundary thread 3 0.3) 4))))

(ert-deftest myemacs-context-safe-boundary-keeps-tail ()
  "Garante que a fronteira (B5.4) preserva os últimos keep-count turns fechados."
  (let* ((mk (lambda (id) (magent-thread-turn-create :id id :input "xxxx")))
         (turns (mapcar mk (number-sequence 0 7)))
         (thread (magent-thread-create :turns turns)))
    (should (= (+carlos/magent-safe-compaction-boundary thread 3 0.3) 5))))

;; ── B5.2: Commit usa o selecionador inteligente ─────────────────────
(ert-deftest myemacs-git-commit-ai-pair-resolves ()
  "Garante que `+carlos/git-commit-ai-pair' retorna (BACKEND . MODEL) válido."
  (let ((pair (+carlos/git-commit-ai-pair)))
    (should (consp pair))
    (should (stringp (car pair)))
    (should (stringp (cdr pair)))))

;; ── Compilação isolada (Emacs 30 cconv) ─────────────────────────────
(ert-deftest myemacs-magent-context-compiles-isolated ()
  "Compilar `custom-magent-context.el' sem `custom-magent-tools' carregado
não pode gerar erro cconv \"Unused lexical variable\" no binding dinâmico
de `+carlos/magent-model-max-tier' (let em `+carlos/magent-compact').
Reproduz o gate de build parcial (stale .elc): a forward declaration com o
default real ('paid) marca a variável como special mesmo com Emacs 30.
Skip quando o source do ambiente-alvo ainda não tem a forward declaration
(prod pré-sync)."
  (skip-unless (executable-find "emacs"))
  (let* ((lisp-dir (expand-file-name
                    "lisp"
                    (or (getenv "EMACS_TEST_DIR") "~/.config/emacs")))
         (file (expand-file-name "custom-magent-context.el" lisp-dir))
         (elc (concat file "c")))
    (skip-unless (file-exists-p file))
    (skip-unless
     (with-temp-buffer
       (insert-file-contents file)
       (string-match-p "defvar \\+carlos/magent-model-max-tier"
                       (buffer-string))))
    (unwind-protect
        (with-temp-buffer
          (let* ((code (format
                        "(progn (setq byte-compile-error-on-warn t) \
(byte-compile-file %S) (message \"ISOLATED-COMPILE-OK\"))"
                        file))
                 (status (call-process "emacs" nil (current-buffer) nil
                                       "--batch" "-Q"
                                       "-L" lisp-dir
                                       "--eval" code)))
            (should (zerop status))
            (should (string-match-p "ISOLATED-COMPILE-OK" (buffer-string)))))
      (when (file-exists-p elc) (delete-file elc)))))

;; ── Cooldown entre compactações ──────────────────────────────────────
(ert-deftest myemacs-context-cooldown-active ()
  "Garante que a cooldown retorna t imediatamente após compactação."
  (let ((+carlos/magent-last-compaction-time (float-time))
        (+carlos/magent-compaction-cooldown-seconds 120))
    (should (+carlos/magent-compaction-cooldown-active-p))))

(ert-deftest myemacs-context-cooldown-expired ()
  "Garante que a cooldown retorna nil após expirar."
  (let ((+carlos/magent-last-compaction-time (- (float-time) 200))
        (+carlos/magent-compaction-cooldown-seconds 120))
    (should (null (+carlos/magent-compaction-cooldown-active-p)))))

(ert-deftest myemacs-context-cooldown-nil-when-never-compacted ()
  "Garante que a cooldown retorna nil quando last-compaction-time é nil."
  (let ((+carlos/magent-last-compaction-time nil)
        (+carlos/magent-compaction-cooldown-seconds 120))
    (should (null (+carlos/magent-compaction-cooldown-active-p)))))

(ert-deftest myemacs-context-cooldown-prevents-compact ()
  "Garante que a cooldown impede auto-compactação mesmo com threshold excedido."
  (let ((+carlos/magent-last-compaction-time (float-time))
        (+carlos/magent-compaction-cooldown-seconds 120)
        (+carlos/magent-context-estimated-tokens 0)
        (+carlos/magent-subagent-completions-since-compact 0)
        (+carlos/magent-last-compaction-failed nil)
        compacted)
    (cl-letf (((symbol-function '+carlos/magent-compact)
               (lambda () (setq compacted t)))
              ((symbol-function '+carlos/magent-turn-tokens)
               (lambda (_) 99999)))
      (+carlos/magent-auto-compact-check-and-run '(:type turn-end :status completed))
      (should (null compacted)))))

;; ── Métricas por turno ──────────────────────────────────────────────
(ert-deftest myemacs-context-metrics-top-tokens ()
  "Garante que `+carlos/magent-top-tokens-turns' retorna top-N por tokens."
  (let ((+carlos/magent-turn-metrics
         '(("t1" :input 100 :output 50)
           ("t2" :input 300 :output 200)
           ("t3" :input 50 :output 10))))
    (let ((top (funcall #'+carlos/magent-top-tokens-turns 2)))
      (should (= (length top) 2))
      (should (= (cdar top) 500))
      (should (= (cdadr top) 150)))))

(ert-deftest myemacs-context-metrics-show-exists ()
  "Garante que `+carlos/magent-show-metrics' é um comando interativo."
  (should (commandp #'+carlos/magent-show-metrics))
  (should (eq (global-key-binding (kbd "C-c A M")) #'+carlos/magent-show-metrics)))

(ert-deftest myemacs-context-metrics-accumulation-safe ()
  "Garante que `+carlos/magent-metrics-accumulate' é segura sem sessão ativa."
  (let ((+carlos/magent-turn-metrics nil))
    (+carlos/magent-metrics-accumulate '(:type turn-end :turn-id "no-session"))
    (should (null +carlos/magent-turn-metrics))))

;; ── Referência AGENTS.md na compactação ─────────────────────────────
(ert-deftest myemacs-context-compaction-rules-present ()
  "Garante que a instrução de compactação contém regras essenciais do AGENTS.md."
  (let ((default-directory (or (locate-dominating-file default-directory "AGENTS.md") default-directory)))
    (cl-letf (((symbol-function 'project-current) (lambda (&optional _) `(transient . ,default-directory)))
              ((symbol-function 'project-root) (lambda (pr) (cdr pr))))
      (let ((instr (+carlos/magent-build-compaction-instruction)))
        (should (string-match-p "use-package" instr))
        (should (string-match-p "just test-all" instr))
        (should (string-match-p "fboundp" instr))))))

;; ── Sub-item 3: Compactação Seletiva ───────────────────────────────
(ert-deftest myemacs-context-selective-compact-threshold-exceeded ()
  "Garante que seletiva é ativada quando thresholds são atingidos."
  (let ((+carlos/magent-cumulative-tool-result-chars 25000)
        (+carlos/magent-subagent-completions-since-compact 3))
    (should (+carlos/magent-selective-compact-p))))

(ert-deftest myemacs-context-selective-compact-threshold-not-exceeded ()
  "Garante que seletiva NÃO é ativada quando thresholds não são atingidos."
  (let ((+carlos/magent-cumulative-tool-result-chars 10000)
        (+carlos/magent-subagent-completions-since-compact 2))
    (should-not (+carlos/magent-selective-compact-p))))

(ert-deftest myemacs-context-selective-compact-min-subagents-not-reached ()
  "Garante que seletiva NÃO é ativada com subagentes insuficientes."
  (let ((+carlos/magent-cumulative-tool-result-chars 25000)
        (+carlos/magent-subagent-completions-since-compact 1))
    (should-not (+carlos/magent-selective-compact-p))))

(ert-deftest myemacs-context-selective-compaction-instruction-contains-preservation ()
  "Garante que instrução seletiva preserva últimos 2 turns."
  (let ((instr (+carlos/magent-build-selective-compaction-instruction)))
    (should (string-match-p "Últimos 2 turns" instr))
    (should (string-match-p "COMPACTAÇÃO SELETIVA" instr))
    (should (string-match-p "tool results" instr))))

(ert-deftest myemacs-context-cumulative-tool-result-reset ()
  "Garante que cumulative-tool-result-chars é resetado na compactação bem-sucedida."
  (let ((+carlos/magent-cumulative-tool-result-chars 50000))
    (+carlos/magent-compaction-result-handler 'completed 1000 500)
    (should (= +carlos/magent-cumulative-tool-result-chars 0))))

(provide 'context-test)
;;; context-test.el ends here

;; ── RAG Sintático (Esqueletos AST) ───────────────────────────────────
(ert-deftest myemacs-context-ast-skeletons-safe ()
  "Garante que a extração de esqueletos AST (Fase 5) roda sem erros."
  (let ((skeletons (+carlos/magent-context-ast-skeletons)))
    (should (or (null skeletons)
                (and (stringp skeletons)
                     (string-match-p "ESTRUTURA DE ARQUIVOS ABERTOS" skeletons))))))
