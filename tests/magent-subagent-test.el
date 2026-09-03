;;; magent-subagent-test.el --- D5: context sharing + durable jobs -*- lexical-binding: t; -*-

;;; Commentary:
;; Suíte ERT para o D5 (custom-magent-subagent.el): persistência/reconciliação
;; de jobs duráveis (:agent-jobs na sessão pai), correlação call-id ↔ job no
;; ledger, verificação da pipeline nativa de AGENTS.md e coleta/renderização
;; do bloco <parent_context>.
;;
;; Testes que dependem do pacote magent rodam apenas onde ele está instalado
;; (prod); no repo aparecem como skipped — nunca falham por ambiente.

;;; Code:
(require 'ert)
(require 'cl-lib)

;; ── Loader ───────────────────────────────────────────────────────────────────
(defvar myemacs-subagent-config-dir
  (or (getenv "EMACS_TEST_DIR") "~/.config/emacs")
  "Diretório de configuração Emacs usado nos testes D5.")

(defvar myemacs-subagent-file
  (expand-file-name "lisp/custom-magent-subagent.el" myemacs-subagent-config-dir)
  "Caminho absoluto do custom-magent-subagent.el do ambiente de teste.")

(defvar myemacs-subagent-available
  (file-readable-p myemacs-subagent-file)
  "Non-nil quando custom-magent-subagent.el está acessível.")

(when myemacs-subagent-available
  (condition-case err
      (load myemacs-subagent-file nil :nomessage)
    (error
     (setq myemacs-subagent-available nil)
     (message "magent-subagent-test: falha ao carregar — %s" err))))

(defun myemacs-subagent-with-magent-p ()
  "Non-nil quando o pacote magent (estruturas de job) está carregado."
  (and myemacs-subagent-available
       (require 'magent-agent-job nil t)
       (featurep 'magent-agent-job)))

;; ── Estrutura: funções D5 existem ────────────────────────────────────────────
(ert-deftest myemacs-magent-subagent-d5-functions-exist ()
  "As funções D5 estão definidas."
  (skip-unless myemacs-subagent-available)
  (should (fboundp '+carlos/magent-subagent-jobs-history))
  (should (fboundp '+carlos/magent-subagent-stale-job-p))
  (should (fboundp '+carlos/magent-subagent-reconcile-stale-jobs))
  (should (fboundp '+carlos/magent-subagent-ledger-note-tool))
  (should (fboundp '+carlos/magent-subagent-ledger-note-job))
  (should (fboundp '+carlos/magent-collect-parent-context))
  (should (fboundp '+carlos/magent-render-parent-context))
  (should (fboundp '+carlos/magent-inject-child-parent-context)))

;; ── D5.1: reconciliação de jobs stale ────────────────────────────────────────
(ert-deftest myemacs-magent-subagent-reconcile-stale-jobs ()
  "Jobs queued/running sem runtime vivo viram cancelled; vivos ficam."
  (skip-unless (myemacs-subagent-with-magent-p))
  (let* ((stale (magent-agent-job-create :id "stale-1" :status 'running))
         (alive (magent-agent-job-create :id "alive-1" :status 'running)))
    (unwind-protect
        (let (persist-called)
          (magent-agent-job-put-runtime "alive-1" (list :session 'fake))
          (cl-letf (((symbol-function 'magent-tools--parent-session)
                     (lambda () 'fake-session))
                    ((symbol-function 'magent-session-agent-jobs)
                     (lambda (_s) (list stale alive)))
                    ((symbol-function 'magent-session-save-deferred-for-session)
                     (lambda (&rest _args) (setq persist-called t))))
            (should (equal (+carlos/magent-subagent-reconcile-stale-jobs)
                           '("stale-1")))
            (should (eq (magent-agent-job-status stale) 'cancelled))
            (should (eq (magent-agent-job-status alive) 'running))
            (should persist-called)))
      (magent-agent-job-clear-runtime "alive-1"))))

(ert-deftest myemacs-magent-subagent-jobs-history-copies-list ()
  "Histórico retorna cópia não-vazia da lista de jobs da sessão pai."
  (skip-unless (myemacs-subagent-with-magent-p))
  (let ((job (magent-agent-job-create :id "h-1" :status 'completed)))
    (cl-letf (((symbol-function 'magent-tools--parent-session)
               (lambda () 'fake-session))
              ((symbol-function 'magent-session-agent-jobs)
               (lambda (_s) (list job))))
      (let ((history (+carlos/magent-subagent-jobs-history)))
        (should (= (length history) 1))))))

(ert-deftest myemacs-magent-subagent-stale-job-p-classifies ()
  "Classificação stale: terminal/running-com-runtime não são stale."
  (skip-unless (myemacs-subagent-with-magent-p))
  (let ((done (magent-agent-job-create :id "d1" :status 'completed)))
    (should (+carlos/magent-subagent-stale-job-p
             (magent-agent-job-create :id "s2" :status 'queued)))
    (should-not (+carlos/magent-subagent-stale-job-p done))))

;; ── D5.2: registro call-id ↔ job ─────────────────────────────────────────────
(ert-deftest myemacs-magent-subagent-ledger-tracks-spawn-and-wait ()
  "tool-call-start/end alimentam o registro; tools não rastreadas são ignoradas."
  (skip-unless myemacs-subagent-available)
  (+carlos/magent-subagent-ledger-reset)
  (unwind-protect
      (progn
        (+carlos/magent-subagent-ledger-note-tool
         '(:time 1.0 :call-id "c-spawn" :tool-name "spawn_agent"
                 :args (:agent "explore")))
        (should (equal (plist-get (+carlos/magent-subagent-call-entry "c-spawn")
                                  :tool)
                       "spawn_agent"))
        ;; wait_agent carrega o job id nos args:
        (+carlos/magent-subagent-ledger-note-tool
         '(:time 2.0 :call-id "c-wait" :tool-name "wait_agent"
                 :args (:job_id "job-77")))
        (should (equal (plist-get (+carlos/magent-subagent-call-entry "c-wait")
                                  :job-id)
                       "job-77"))
        ;; tool não rastreada não entra:
        (+carlos/magent-subagent-ledger-note-tool
         '(:time 3.0 :call-id "c-bash" :tool-name "bash" :args nil))
        (should-not (+carlos/magent-subagent-call-entry "c-bash"))
        ;; end fecha a entrada:
        (+carlos/magent-subagent-ledger-note-tool
         '(:call-id "c-wait" :tool-name "wait_agent" :status completed)
         :end)
        (let ((entry (+carlos/magent-subagent-call-entry "c-wait")))
          (should (eq (plist-get entry :status) 'completed))
          (should (numberp (plist-get entry :finished-at)))))
    (+carlos/magent-subagent-ledger-reset)))

(ert-deftest myemacs-magent-subagent-ledger-links-job-lifecycle ()
  "agent-job-event liga job às entradas: spawn aberto adota; wait só em match."
  (skip-unless (myemacs-subagent-with-magent-p))
  (+carlos/magent-subagent-ledger-reset)
  (unwind-protect
      (let ((spawn-job (magent-agent-job-create :id "jx" :status 'running)))
        (+carlos/magent-subagent-ledger-note-tool
         '(:time 1.0 :call-id "c1" :tool-name "spawn_agent" :args nil))
        (+carlos/magent-subagent-ledger-note-tool
         '(:time 1.5 :call-id "c2" :tool-name "wait_agent"
                 :args (:job_id "jy")))
        (+carlos/magent-subagent-ledger-note-job
         `(:type agent-job-event :event failed :job ,spawn-job
                 :detail "boom"))
        ;; c1 (spawn aberto, sem id) adota jx:
        (let ((e1 (+carlos/magent-subagent-call-entry "c1")))
          (should (equal (plist-get e1 :job-id) "jx"))
          (should (equal (plist-get e1 :job-status) 'failed)))
        ;; c2 espera jy — NÃO adota jx:
        (should (equal (plist-get (+carlos/magent-subagent-call-entry "c2")
                                  :job-id)
                       "jy"))
        ;; evento do próprio jy atualiza c2:
        (let ((jy (magent-agent-job-create :id "jy" :status 'completed)))
          (+carlos/magent-subagent-ledger-note-job
           `(:type agent-job-event :event completed :job ,jy :detail "ok"))
          (should (equal (plist-get (+carlos/magent-subagent-call-entry "c2")
                                    :job-status)
                         'completed))))
    (+carlos/magent-subagent-ledger-reset)))

(ert-deftest myemacs-magent-subagent-sink-registered ()
  "O sink D5 está registrado no barramento de lifecycle events."
  (skip-unless myemacs-subagent-available)
  (skip-unless (require 'magent-lifecycle-events nil t))
  (should (member #'+carlos/magent-subagent-lifecycle-sink
                  magent-lifecycle-events--sinks)))

;; ── D5.3: pipeline nativa AGENTS.md (verificação estrutural) ────────────────
(ert-deftest myemacs-magent-subagent-agents-md-pipeline-native ()
  "Descoberta/injeção de AGENTS.md é nativa e está habilitada."
  (skip-unless myemacs-subagent-available)
  (require 'magent-project-instructions nil t)
  (skip-unless (featurep 'magent-project-instructions))
  (should (member "AGENTS.md" magent-project-instruction-file-names))
  (should magent-project-instructions-max-bytes)
  (should (fboundp 'magent-project-instructions-discover))
  (should (fboundp 'magent-project-instructions-system-message)))

;; ── D5.4: coleta e renderização do contexto pai ──────────────────────────────
(ert-deftest myemacs-magent-subagent-collect-parent-context ()
  "Coleta session-id/goal/message-count da sessão pai fake."
  (skip-unless myemacs-subagent-available)
  (let ((magent-tools--request-context nil))
    (cl-letf (((symbol-function 'magent-tools--parent-session)
               (lambda () 'fake-session))
              ((symbol-function 'magent-session-get-messages)
               (lambda (_s) '(msg-a msg-b)))
              ((symbol-function 'magent-msg-role)
               (lambda (_m) 'user))
              ((symbol-function 'magent-msg-content)
               (lambda (_m) "Refatore o módulo X"))
              ((symbol-function 'magent-session-get-id)
               (lambda (_s) "sess-9")))
      (let ((ctx (+carlos/magent-collect-parent-context)))
        (should (equal (plist-get ctx :session-id) "sess-9"))
        (should (null (plist-get ctx :project-root)))
        (should (equal (plist-get ctx :goal) "Refatore o módulo X"))
        (should (= (plist-get ctx :message-count) 2))))))

(ert-deftest myemacs-magent-subagent-render-parent-context-block ()
  "Renderiza bloco <parent_context> capado e coerente."
  (skip-unless myemacs-subagent-available)
  (should (null (+carlos/magent-render-parent-context nil)))
  (let ((block (+carlos/magent-render-parent-context
                (list :session-id "s1"
                      :project-root "/tmp/p"
                      :goal "objetivo atual"
                      :message-count 3))))
    (should (string-prefix-p "<parent_context>" block))
    (should (string-suffix-p "</parent_context>" block))
    (should (string-match-p "session: s1" block))
    (should (string-match-p "project_root: /tmp/p" block))
    (should (string-match-p "current_goal: objetivo atual" block))
    (should (string-match-p "messages: 3" block)))
  ;; Cap de tamanho (~300–500 tokens):
  (let ((long-goal (make-string 5000 ?g))
        (+carlos/magent-parent-context-max-chars 2000))
    (should (< (length (+carlos/magent-render-parent-context
                        (list :session-id "s2" :goal long-goal)))
               2200))))

(ert-deftest myemacs-magent-subagent-inject-child-context-filter ()
  "Filter-return anexa <parent_context> só para subagentes."
  (skip-unless myemacs-subagent-available)
  ;; A flag é variável especial (declarada com valor em custom-magent-tools.el);
  ;; em batch isolado ela pode estar unbound, então usamos setq dinâmico com
  ;; unwind-protect (let lexical NÃO criaria binding dinâmico visível à função).
  (let ((old (and (boundp '+carlos/magent-current-agent-is-orchestrator)
                  +carlos/magent-current-agent-is-orchestrator)))
    (unwind-protect
        (progn
          (setq +carlos/magent-current-agent-is-orchestrator t)
          (should (equal (+carlos/magent-inject-child-parent-context "PROMPT")
                         "PROMPT"))
          (setq +carlos/magent-current-agent-is-orchestrator nil)
          (cl-letf (((symbol-function 'magent-tools--parent-session)
                     (lambda () 'fake-session))
                    ((symbol-function 'magent-session-get-messages)
                     (lambda (_s) nil))
                    ((symbol-function 'magent-session-get-id)
                     (lambda (_s) "sess-x")))
            (let ((out (+carlos/magent-inject-child-parent-context "BASE")))
              (should (string-prefix-p "BASE\n\n<parent_context>" out))
              (should (string-match-p "session: sess-x" out)))))
      (if old
          (setq +carlos/magent-current-agent-is-orchestrator old)
        (makunbound '+carlos/magent-current-agent-is-orchestrator)))))

(ert-deftest myemacs-magent-subagent-compose-advice-registered ()
  "O filter-return está registrado em magent-agent--compose-system-message."
  (skip-unless myemacs-subagent-available)
  (skip-unless (require 'magent-agent nil t))
  (should (advice-member-p #'+carlos/magent-inject-child-parent-context
                           'magent-agent--compose-system-message)))

;; ── Coder Lite: filtro por permission keys (regressão 2026-08-30) ───────────

(ert-deftest myemacs-magent-subagent-lite-tools-native-permission-keys ()
  "lite-tools usa *permission keys* de `magent-enable-tools', não nomes
de tool com underscore. Regressão: filtro por `read_file'/
`run_command'/'replace_file_content' deixava o modelo local sem
read/write/bash (interseção vazia) — code-repair batch falhava."
  (skip-unless myemacs-subagent-available)
  (should (boundp '+carlos/magent-subagent-lite-tools))
  (let ((lite +carlos/magent-subagent-lite-tools))
    (dolist (key '(read write edit bash context_search))
      (should (memq key lite)))
    (dolist (stale '(read_file run_command replace_file_content))
      (should-not (memq stale lite)))))

(ert-deftest myemacs-magent-subagent-lite-filter-keeps-native ()
  "O filtro lite preserva as chaves nativas já presentes em
`magent-enable-tools' (ex.: o default do pacote)."
  (skip-unless myemacs-subagent-available)
  (let ((enable '(read write edit grep glob bash emacs_eval agent web_search)))
    (should (equal (seq-filter (lambda (t-name)
                                  (memq t-name +carlos/magent-subagent-lite-tools))
                                enable)
                   '(read write edit bash)))))

(ert-deftest myemacs-magent-orchestrator-hides-mutation-tools-test ()
  "Verifica se ferramentas de mutação são filtradas para o orchestrator."
  (skip-unless myemacs-subagent-available)
  (let* ((tools '(read write edit elisp_smart_edit org_smart_edit write_to_file replace_file_content spawn_agent wait_agent))
         (filtered (seq-filter
                    (lambda (sym)
                      (let ((s (symbol-name sym)))
                        (not (or (memq sym '(read write edit snippet_expand buffer))
                                 (string-match-p "smart_edit" s)
                                 (string-match-p "write_to_file" s)
                                 (string-match-p "replace_file" s)))))
                    tools)))
    (should-not (memq 'elisp_smart_edit filtered))
    (should-not (memq 'org_smart_edit filtered))
    (should-not (memq 'write_to_file filtered))
    (should-not (memq 'replace_file_content filtered))
    (should-not (memq 'write filtered))
    (should (memq 'spawn_agent filtered))
    (should (memq 'wait_agent filtered))))

(ert-deftest myemacs-magent-subagent-spawn-validate-prompt-test ()
  "Verifica se placeholders em spawn_agent são rejeitados."
  (skip-unless myemacs-subagent-available)
  (let ((failed-msg nil))
    (cl-letf (((symbol-function 'magent-tools--fail)
               (lambda (_cb msg) (setq failed-msg msg))))
      ;; Placeholder [Insert Synthesis Here]
      (+carlos/magent-tools-spawn-agent-around
       (lambda (&rest _) nil)
       #'ignore
       "coder"
       "[Insert Synthesis Here]")
      (should (string-match-p "invalid placeholder" (or failed-msg "")))
      
      ;; Prompt vazio
      (setq failed-msg nil)
      (+carlos/magent-tools-spawn-agent-around
       (lambda (&rest _) nil)
       #'ignore
       "coder"
       "   ")
      (should (string-match-p "required" (or failed-msg ""))))))

(ert-deftest myemacs-magent-subagent-abort-and-cancel-job-test ()
  "Verifica se abort-and-cancel-job transiciona o status para cancelled e limpa timers."
  (skip-unless myemacs-subagent-available)
  (when (myemacs-subagent-with-magent-p)
    (let* ((job (magent-agent-job-create
                 :parent-session-id "s-1"
                 :agent-name "coder"
                 :prompt "test task"))
           (jid (magent-agent-job-id job)))
      (magent-agent-job-set-status job 'running)
      (puthash jid (run-at-time 100 nil #'ignore) +carlos/magent-job-watchdog-timers)
      (+carlos/magent-abort-and-cancel-job job "Wait timed out")
      (should (eq (magent-agent-job-status job) 'cancelled))
      (should (equal (magent-agent-job-error job) "Wait timed out"))
      (should-not (gethash jid +carlos/magent-job-watchdog-timers)))))

(provide 'magent-subagent-test)

;;; magent-subagent-test.el ends here
