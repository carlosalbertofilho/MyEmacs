;;; magent-routing-test.el --- Tests for Fase A model routing --- -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the orchestrator-driven model routing (Fase A): menu de
;; modelos, heurística de complexidade, escada de tiers, teto do usuário,
;; handler `select_model' e consumo do override pelo advice de subagente.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'custom-magent)

(defun myemacs-routing-result-output (res)
  "Extrai o output (string) de RES — struct `magent-tool-result' ou string."
  (if (and (fboundp 'magent-tool-result-p) (magent-tool-result-p res))
      (magent-tool-result-output-string res)
    (if (stringp res) res (format "%s" res))))

(ert-deftest myemacs-magent-tier-rank ()
  "Garante que o rank reflete a escada local < free < paid."
  (should (= (+carlos/magent-tier-rank "local") 0))
  (should (= (+carlos/magent-tier-rank "free") 1))
  (should (= (+carlos/magent-tier-rank "paid") 2))
  (should (= (+carlos/magent-tier-rank "ultra") -1)))

(ert-deftest myemacs-magent-task-complexity ()
  "Garante que a heurística classifica simple/moderate/deep."
  (should (eq (+carlos/magent-task-complexity "Fix typo in function name")
              'simple))
  (should (eq (+carlos/magent-task-complexity
               "Add tests for the new vertico integration and document the API")
              'moderate))
  (should (eq (+carlos/magent-task-complexity "Refactor the module architecture")
              'deep))
  (should (eq (+carlos/magent-task-complexity (make-string 200 ?x))
              'deep)))

(ert-deftest myemacs-magent-resolve-model-deep-skips-local ()
  "Garante que task 'deep nunca resolve para o tier local."
  (cl-letf (((symbol-function 'gptel-get-backend)
             (lambda (_name) (list :name "any")))
            ((symbol-function '+carlos/ai-local-backend)
             (lambda () (cons "MLX Local" 'mlx-community/gemma-4-e2b-it-4bit))))
    (let ((choice (+carlos/magent-resolve-model 'deep t)))
      (should (stringp (plist-get choice :backend)))
      (should-not (equal (plist-get choice :tier) "local")))))

(ert-deftest myemacs-magent-resolve-model-simple-local-first ()
  "Garante que task 'simple com local online resolve para o tier local."
  (cl-letf (((symbol-function 'gptel-get-backend)
             (lambda (_name) (list :name "any")))
            ((symbol-function '+carlos/ai-local-backend)
             (lambda () (cons "MLX Local" 'mlx-community/gemma-4-e2b-it-4bit))))
    (let ((choice (+carlos/magent-resolve-model 'simple t)))
      (should (equal (plist-get choice :tier) "local"))
      (should (equal (plist-get choice :model) "mlx-community/gemma-4-e2b-it-4bit")))))

(ert-deftest myemacs-magent-resolve-model-simple-local-offline ()
  "Garante que task 'simple com local offline cai para o tier free."
  (cl-letf (((symbol-function 'gptel-get-backend)
             (lambda (_name) (list :name "any")))
            ((symbol-function '+carlos/ai-local-backend)
             (lambda () (cons "MLX Local" 'mlx-community/gemma-4-e2b-it-4bit))))
    (let ((choice (+carlos/magent-resolve-model 'simple nil)))
      (should (equal (plist-get choice :tier) "free")))))

(ert-deftest myemacs-magent-resolve-model-respects-max-tier ()
  "Garante que o teto 'free nunca resolve para local ou paid."
  (cl-letf (((symbol-function 'gptel-get-backend)
             (lambda (_name) (list :name "any"))))
    (let ((+carlos/magent-model-max-tier 'free))
      (dolist (complexity '(simple moderate deep))
        (let ((choice (+carlos/magent-resolve-model complexity nil)))
          (should choice)
          (should-not (equal (plist-get choice :tier) "paid"))
          (should-not (equal (plist-get choice :tier) "local")))))))

(ert-deftest myemacs-magent-system-directives-render ()
  "Garante que as directivas renderizadas incluem rule 9 e o menu."
  (cl-letf (((symbol-function '+carlos/ai-local-backend)
             (lambda () (cons "MLX Local" 'mlx-community/gemma-4-e2b-it-4bit)))
            ((symbol-function '+carlos/local-ai-server-ping-p) (lambda () t)))
    (let ((rendered (+carlos/magent-system-directives-render)))
      (should (string-match-p "MODEL SELECTION MENU" rendered))
      (should (string-match-p "select_model" rendered))
      (should (string-match-p "tier free" rendered))
      (should (string-match-p "tier paid" rendered)))))

(ert-deftest myemacs-magent-inject-system-directives-includes-menu ()
  "Garante que o advice de injeção append o menu no system prompt."
  (cl-letf (((symbol-function '+carlos/ai-local-backend)
             (lambda () (cons "MLX Local" 'mlx-community/gemma-4-e2b-it-4bit)))
            ((symbol-function '+carlos/local-ai-server-ping-p) (lambda () t)))
    (should (string-match-p
             "MODEL SELECTION MENU"
             (+carlos/magent-inject-system-directives "base")))))

(ert-deftest myemacs-magent-menu-respects-max-tier ()
  "Garante que o menu renderizado corta tiers acima do teto."
  (cl-letf (((symbol-function '+carlos/ai-local-backend)
             (lambda () (cons "MLX Local" 'mlx-community/gemma-4-e2b-it-4bit)))
            ((symbol-function '+carlos/local-ai-server-ping-p) (lambda () t)))
    (let ((+carlos/magent-model-max-tier 'free))
      (should-not (string-match-p "tier paid"
                                  (+carlos/magent-model-menu-render))))))

(ert-deftest myemacs-magent-select-model-registers-override ()
  "Garante que `select_model` registra override e retorna payload success."
  (cl-letf (((symbol-function 'gptel-get-backend)
             (lambda (_name) (list :name "any")))
            ((symbol-function '+carlos/ai-local-backend)
             (lambda () (cons "MLX Local" 'mlx-community/gemma-4-e2b-it-4bit)))
            ((symbol-function '+carlos/local-ai-server-ping-p) (lambda () t)))
    (let ((+carlos/magent-subagent-model-overrides nil))
      (let* ((out (myemacs-routing-result-output
                   (+carlos/magent-tool-select-model
                    "Refactor the authentication module" "explore")))
             (parsed (json-read-from-string out)))
        (should (equal (alist-get 'status parsed) "success"))
        (should (equal (alist-get 'agent parsed) "explore"))
        (should (stringp (alist-get 'backend parsed))))
      (should (= (length +carlos/magent-subagent-model-overrides) 1))
      (should (string= (caar +carlos/magent-subagent-model-overrides)
                       "explore")))))

(ert-deftest myemacs-magent-select-model-honors-complexity-arg ()
  "Garante que complexity explícita 'simple' com local online resolve local."
  (cl-letf (((symbol-function 'gptel-get-backend)
             (lambda (_name) (list :name "any")))
            ((symbol-function '+carlos/ai-local-backend)
             (lambda () (cons "MLX Local" 'mlx-community/gemma-4-e2b-it-4bit)))
            ((symbol-function '+carlos/local-ai-server-ping-p) (lambda () t)))
    (let ((+carlos/magent-subagent-model-overrides nil))
      (let* ((out (myemacs-routing-result-output
                   (+carlos/magent-tool-select-model
                    "x" "explore" "simple")))
             (parsed (json-read-from-string out)))
        (should (equal (alist-get 'tier parsed) "local"))
        (should (= (length +carlos/magent-subagent-model-overrides) 1))))))

(ert-deftest myemacs-magent-select-model-tool-args-positional ()
  "Garante que os args do gptel-tool seguem a ordem posicional do handler."
  (skip-unless (and (boundp '+carlos/magent-tool-select-model)
                    (gptel-tool-p +carlos/magent-tool-select-model)))
  (let ((args (gptel-tool-args +carlos/magent-tool-select-model)))
    (should (equal (mapcar (lambda (a) (plist-get a :name)) args)
                   '("task_description" "agent" "complexity" "reason")))))

(ert-deftest myemacs-magent-subagent-override-consumed ()
  "Garante que o override da select_model é consumido (pop) e aplicado."
  (skip-unless (fboundp 'magent-request-context-create))
  (skip-unless (fboundp 'magent-agent-info-create))
  (cl-letf (((symbol-function 'gptel-get-backend)
             (lambda (name) (list :name name))))
    (let* ((+carlos/magent-subagent-model-overrides
            '(("explore" . ("OpenCode Zen" . "big-pickle"))))
           (agent-info (magent-agent-info-create :name "explore" :mode 'subagent))
           (request-state (magent-request-context-create)))
      (+carlos/magent-subagent-apply-profile
       #'ignore "prompt" nil agent-info nil nil nil nil nil nil request-state)
      (should (= (length +carlos/magent-subagent-model-overrides) 0))
      (should (equal
               (cl-struct-slot-value 'magent-request-context 'backend request-state)
               (gptel-get-backend "OpenCode Zen"))))))

(provide 'magent-routing-test)
;;; magent-routing-test.el ends here
