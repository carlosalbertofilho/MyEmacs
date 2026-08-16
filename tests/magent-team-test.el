;;; magent-team-test.el --- Magent equipe de especialistas (D9) regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Suíte ERT para custom-magent-team.el (D9): instanciação da equipe de
;; especialistas como subagentes registrados no registry do Magent.
;;
;; Cobre: dados dos perfis (name/description/prompt/permission), registro no
;; `magent-agent-registry' e perfis de modelo em
;; `+carlos/magent-subagent-profiles'.  Rodam offline; o teste de registro
;; requer o pacote magent no load-path (skip-unless limpo em builds parciais).

;;; Code:
(require 'ert)
(require 'cl-lib)

;; ── Loader: carrega custom-magent-team.el do ambiente correto ─────────────────
(defvar myemacs-team-config-dir
  (or (getenv "EMACS_TEST_DIR") "~/.config/emacs")
  "Diretório de configuração Emacs usado nos testes da equipe de especialistas.")

(defvar myemacs-team-file
  (expand-file-name "lisp/custom-magent-team.el" myemacs-team-config-dir)
  "Caminho absoluto do custom-magent-team.el do ambiente de teste.")

(defvar myemacs-team-available
  (file-readable-p myemacs-team-file)
  "Non-nil quando custom-magent-team.el está acessível no ambiente de teste.")

(when myemacs-team-available
  (condition-case err
      (load myemacs-team-file nil :nomessage)
    (error
     (setq myemacs-team-available nil)
     (message "magent-team-test: falha ao carregar custom-magent-team.el — %s"
              err))))

(defvar myemacs-team-expected-members
  '("coder" "sysadmin" "planner" "tech-writer" "auditor" "sec-ops" "qa")
  "Membros esperados da equipe de especialistas (D9).")

(defun myemacs-team-spec (agent-name)
  "Return the spec plist of team AGENT-NAME, or nil."
  (cdr (assoc agent-name +carlos/magent-expert-team)))

;; ── Dados da equipe ───────────────────────────────────────────────────────────
(ert-deftest myemacs-magent-team-profiles-defined ()
  "A equipe declara todos os perfis esperados com name/description/prompt."
  (skip-unless myemacs-team-available)
  (skip-unless (boundp '+carlos/magent-expert-team))
  (let ((names (mapcar #'car +carlos/magent-expert-team)))
    (should (= (length names) (length myemacs-team-expected-members)))
    (dolist (name myemacs-team-expected-members)
      (should (member name names))
      (let ((spec (myemacs-team-spec name)))
        (should (stringp (plist-get spec :description)))
        (should (not (string-empty-p (plist-get spec :description))))
        (should (stringp (plist-get spec :prompt)))
        (should (not (string-empty-p (plist-get spec :prompt))))
        (should (listp (plist-get spec :permission)))
        (should (assq '* (plist-get spec :permission)))))))

(ert-deftest myemacs-magent-team-prompt-roles ()
  "Cada prompt reflete o papel do perfil (semantic tags do papel)."
  (skip-unless myemacs-team-available)
  (skip-unless (boundp '+carlos/magent-expert-team))
  (dolist (entry '(("coder" . "live-buffer driver")
                   ("sysadmin" . "infrastructure")
                   ("planner" . "Org-mode AST")
                   ("tech-writer" . "Single Source of Truth")
                   ("auditor" . "Norminette")
                   ("sec-ops" . "Security Considerations")
                   ("qa" . "Zero-Warnings")))
    (let* ((name (car entry))
           (needle (cdr entry))
           (prompt (plist-get (myemacs-team-spec name) :prompt)))
      (should (string-match-p needle prompt)))))

(ert-deftest myemacs-magent-team-coder-denies-write-edit ()
  "O perfil coder nega explicitamente write/edit (política D4/docs)."
  (skip-unless myemacs-team-available)
  (skip-unless (boundp '+carlos/magent-expert-team))
  (let ((perms (plist-get (myemacs-team-spec "coder") :permission)))
    (should (not (assq 'write perms)))
    (should (not (assq 'edit perms)))
    (should (eq (cdr (assq '* perms)) 'deny))
    (should (eq (cdr (assq 'buffer perms)) 'allow))))

;; ── Registro no registry do Magent ───────────────────────────────────────────
(ert-deftest myemacs-magent-team-register-returns-count ()
  "Registro retorna o número de perfis registrados quando o API existe."
  (skip-unless myemacs-team-available)
  (skip-unless (fboundp '+carlos/magent-team-register))
  (skip-unless (require 'magent-agent-info nil t))
  (skip-unless (require 'magent-agent-registry nil t))
  (skip-unless (require 'magent-permission nil t))
  (let ((count (+carlos/magent-team-register)))
    (should (integerp count))
    (should (= count (length myemacs-team-expected-members)))))

(ert-deftest myemacs-magent-team-registered-in-registry ()
  "Todos os membros ficam resolvíveis como subagentes no registry."
  (skip-unless myemacs-team-available)
  (skip-unless (fboundp '+carlos/magent-team-registered-p))
  (skip-unless (require 'magent-agent-info nil t))
  (skip-unless (require 'magent-agent-registry nil t))
  (skip-unless (require 'magent-permission nil t))
  (+carlos/magent-team-register)
  (dolist (name myemacs-team-expected-members)
    (should (+carlos/magent-team-registered-p name))))

;; ── Dicas de roteamento (custom-magent-subagent.el) ─────────────────────────
(ert-deftest myemacs-magent-team-model-profiles-present ()
  "Cada membro da equipe tem dicas de roteamento (:min-tier) em
+carlos/magent-subagent-profiles — sem modelo concreto pinado."
  (skip-unless myemacs-team-available)
  (skip-unless (boundp '+carlos/magent-subagent-profiles))
  (dolist (name myemacs-team-expected-members)
    (let ((entry (assoc name +carlos/magent-subagent-profiles)))
      (should entry)
      (should (stringp (plist-get (cdr entry) :min-tier)))
      (should-not (plist-get (cdr entry) :model)))))

(provide 'magent-team-test)
;;; magent-team-test.el ends here
