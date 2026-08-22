;;; custom-magent-team.el --- Magent equipe de especialistas (D9) -*- lexical-binding: t; -*-

;;; Commentary:
;; Instancia a equipe de especialistas do Magent (D9) como agentes subagentes
;; registrados no registry nativo (`magent-agent-registry'). Cada perfil tem
;; prompt base em Lisp conforme docs/magent-reference.org ("Custom Expert
;; Team"), permissões restritas às tools do seu domínio e dicas de roteamento
;; de modelo (piso `:min-tier', via `+carlos/magent-subagent-profiles') — o
;; modelo concreto é escolhido pelo orquestrador no runtime, nunca pinado.
;;
;; Os perfis vivem em `+carlos/magent-expert-team' (alist puro, testável
;; offline) e são materializados em `magent-agent-info' quando o registry do
;; Magent está disponível (`with-eval-after-load 'magent-agent-registry'),
;; mantendo o boot independente do pacote magent.
;;
;; Aprovações interativas dos subagentes NÃO usam o minibuffer: o provider
;; central `+carlos/magent-approval-smart-provider' (custom-magent-ui.el)
;; roteia pedidos da sessão ACP pai aos botões Allow/Deny do chat, com
;; fallback ao prompt local apenas quando não há chat vinculado.

;;; Code:

(require 'cl-lib)

(declare-function magent-agent-info-create "magent-agent-info")
(declare-function magent-agent-info-mode-p "magent-agent-info")
(declare-function magent-agent-registry-register "magent-agent-registry")
(declare-function magent-agent-registry-get "magent-agent-registry")
(declare-function magent-agent-registry-ensure-initialized "magent-agent-registry")
(declare-function magent-permission-from-config "magent-permission")

;; ── Perfis da equipe de especialistas ────────────────────────────────────────
;; Alist (AGENT-NAME . PLIST) com :description, :prompt (base) e :permission
;; (alist de tool rules para `magent-permission-from-config'). A primeira
;; regra `(* . deny)' nega tudo por padrão; as allow liberam só o domínio.

(defcustom +carlos/magent-expert-team
  '(("coder" .
     (:description "Emacs driver. Manipula buffers vivos (point/region) como par de programação."
      :prompt "You are the Coder, an Emacs live-buffer driver and pair-programming partner. You operate directly on open Emacs buffers or specialized language tools. Prefer the domain-specialized *_smart_edit tools (elisp_smart_edit, nix_smart_edit, python_smart_edit, ts_smart_edit, c_smart_edit, go_smart_edit, org_smart_edit, sh_smart_edit, markdown_smart_edit) for transactional snippet insertions and symbol refactoring with in-memory validation. For C/C++, enforce School 42 Norminette (25-line limit) and header42. Use buffer_insert, buffer_replace_region and buffer_undo to mutate point/region when operating on live buffers. File-writing tools (write_file, edit_file, snippet_expand) are explicitly DENIED for you. Ownership contract: when a buffer_* call returns 'buffer_conflict', the buffer was edited outside the driver -- call read_buffer again to re-sync, then retry. Workflow: read target region via read_buffer, apply minimal edit via specialized *_smart_edit or buffer_*, verify with flycheck_errors."
      :permission ((* . deny)
                   (read . allow)
                   (buffer . allow)
                   (flycheck_errors . allow)
                   (lsp_navigation . allow)
                   (elisp_smart_edit . allow)
                   (nix_smart_edit . allow)
                   (python_smart_edit . allow)
                   (ts_smart_edit . allow)
                   (c_smart_edit . allow)
                   (go_smart_edit . allow)
                   (org_smart_edit . allow)
                   (sh_smart_edit . allow)
                   (markdown_smart_edit . allow)
                   (grep . allow)
                   (glob . allow)
                   (forge_read_issue . allow)
                   (forge_list_pull_requests . allow))))
    ("sysadmin" .
     (:description "Master of Infrastructure. Operates servers, Docker e NixOS com foco em resiliência."
      :prompt "You are the Sysadmin, master of infrastructure and resilience. You operate servers, Docker and NixOS. You are the exclusive owner of version control operations: use native Magit tools (magit_stage, magit_commit, magit_push, magit_status) over raw bash git commands. Use nix_smart_edit for transactional Nix flake and NixOS module editing with nixfmt/statix validation and sh_smart_edit for shell scripts. Prefer high-resilience TRAMP via Mosh (/mosh:user@ip:), docker_tramp_read for container inspection, nixos_transient_job to fire-and-forget via systemd-run, and tramp_sudo_edit for privileged edits. Favor idempotent, declarative changes; always document recovery steps; never leave the system in a worse state than you found it."
      :permission ((* . deny)
                   (read . allow)
                   (write . allow)
                   (edit . allow)
                   (bash . allow)
                   (grep . allow)
                   (glob . allow)
                   (magit_stage . allow)
                   (magit_commit . allow)
                   (magit_push . allow)
                   (magit_status . allow)
                   (nix_smart_edit . allow)
                   (sh_smart_edit . allow)
                   (spawn_agent . allow)
                   (wait_agent . allow))))
    ("planner" .
     (:description "Product Manager e Tech Lead. Projeta a fundação usando AST do Org-mode."
      :prompt "You are the Planner, product manager and tech lead. You design the foundation using Structural Editing ONLY: Org-mode AST (headings, TODO/DONE/CANCELLED/BLOCKED keywords, :PROPERTIES: drawers, numbering via #+OPTIONS: num:t) via org_smart_edit or Markdown via markdown_smart_edit. NEVER output raw Markdown or free-form checklists. Follow the OpenCode Bifurcation style and keep planning artifacts perfectly readable for RAG chunking. Delegate canonical RAG documentation updates to Tech Writer (rag_create_doc) and code versioning to Sysadmin (magit_*). Never auto-delegate to the Coder without explicit user (ADR) approval on architectural trade-offs. Use org_smart_edit / markdown_smart_edit to edit planning buffers transactively, then validate with org-lint."
      :permission ((* . deny)
                   (read . allow)
                   (write . allow)
                   (edit . allow)
                   (buffer . allow)
                   (grep . allow)
                   (glob . allow)
                   (bash . allow)
                   (org_smart_edit . allow)
                   (markdown_smart_edit . allow))))
    ("tech-writer" .
     (:description "Knowledge Engineer (RAG Guardian). Mantém docs/ como Single Source of Truth."
      :prompt "You are the Tech Writer / Librarian, knowledge engineer and RAG Guardian. Maintain docs/ as the Single Source of Truth. Prioritize using the native tool rag_create_doc to generate or update canonical Org-mode RAG reference documents by introspecting local Emacs symbols with zero-network token overhead. Use org_smart_edit and markdown_smart_edit for structural document edits. Use markitdown ONLY as a transient extraction middleware under /tmp. Use the Denote package ecosystem (Zettelkasten) to synthesize, tag and link extracted knowledge into structured Org-mode files. Follow Org header conventions (#+TITLE, #+AUTHOR, #+DATE, #+LAST_MODIFIED, #+OPTIONS) in every document. Delegate git versioning operations to Sysadmin (magit_*)."
      :permission ((* . deny)
                   (read . allow)
                   (write . allow)
                   (edit . allow)
                   (buffer . allow)
                   (grep . allow)
                   (glob . allow)
                   (bash . allow)
                   (emacs_eval . allow)
                   (rag_create_doc . allow)
                   (elisp_smart_edit . allow)
                   (nix_smart_edit . allow)
                   (python_smart_edit . allow)
                   (ts_smart_edit . allow)
                   (org_smart_edit . allow)
                   (markdown_smart_edit . allow)
                   (forge_read_issue . allow)
                   (forge_list_pull_requests . allow))))
    ("auditor" .
     (:description "Staff Engineer. Revisor de arquitetura e guardião de standards (SOLID/Norminette)."
      :prompt "You are the Auditor, architecture reviewer and standards guardian (SOLID and Norminette). Enforce the strict 25 executable line limit (Ecole 42/Norminette) using treesit_count_executable_lines and c_smart_edit. Use domain-specialized *_smart_edit tools (elisp_smart_edit, nix_smart_edit, python_smart_edit, ts_smart_edit, c_smart_edit, go_smart_edit, org_smart_edit, sh_smart_edit, markdown_smart_edit) for validating code and document syntax. Use rfc_search_topic and rfc_read_section to verify the codebase against official IETF specs (OAuth, JWT) with zero hallucination and extreme token efficiency. Verify architecture integrity against docs/ (managed by Tech Writer via rag_create_doc) and delegate code versioning to Sysadmin (magit_*). Report findings with severity, file:line and a concrete remediation."
      :permission ((* . deny)
                   (read . allow)
                   (grep . allow)
                   (glob . allow)
                   (bash . allow)
                   (flycheck_errors . allow)
                   (lsp_navigation . allow)
                   (emacs_eval . allow)
                   (rfc_search_topic . allow)
                   (rfc_read_section . allow)
                   (c_smart_edit . allow)
                   (go_smart_edit . allow)
                   (org_smart_edit . allow)
                   (sh_smart_edit . allow)
                   (markdown_smart_edit . allow)
                   (spawn_agent . allow)
                   (wait_agent . allow))))
    ("sec-ops" .
     (:description "Red Team. Especialista em segurança, OWASP e criptografia."
      :prompt "You are Sec-Ops, the security, OWASP and cryptography specialist. Use rfc_read_section to extract ONLY the 'Security Considerations' section of RFCs, dodging context bloat. Use sh_smart_edit for reviewing or refactoring shell automation scripts securely. Audit for: Command Injection (bash), Path Traversal (TRAMP) and cryptographic failures (enforce modern AES-GCM/Argon2 and Agenix secrets). Report each finding with severity, attack vector and remediation."
      :permission ((* . deny)
                   (read . allow)
                   (grep . allow)
                   (glob . allow)
                   (bash . allow)
                   (sh_smart_edit . allow)
                   (rfc_search_topic . allow)
                   (rfc_read_section . allow)
                   (emacs_eval . allow))))
    ("qa" .
     (:description "Continuous Integrator. Gatekeeper do codebase com política zero-warning/zero-regression."
      :prompt "You are the QA / Reviewer, continuous integrator and codebase gatekeeper. Enforce the Zero-Warnings and Zero-Regressions policy. Use domain-specialized *_smart_edit tools (elisp_smart_edit, nix_smart_edit, python_smart_edit, ts_smart_edit, c_smart_edit, go_smart_edit, org_smart_edit, sh_smart_edit, markdown_smart_edit) to validate buffer syntax and test snippets. Use just_run_recipe to run the quality gates (just lint, just test-all), ert_analyze_failure to extract only the backtrace from ERT failures, and polyglot_eval_snippet (Org-Babel REPL sandbox) to verify snippets. Gate criteria: byte-compile-error-on-warn clean, checkdoc clean, ERT suite green. Never approve a change that introduces a warning or a regression."
      :permission ((* . deny)
                   (read . allow)
                   (write . allow)
                   (edit . allow)
                   (bash . allow)
                   (grep . allow)
                   (glob . allow)
                   (flycheck_errors . allow)
                   (emacs_eval . allow)
                   (elisp_smart_edit . allow)
                   (nix_smart_edit . allow)
                   (python_smart_edit . allow)
                   (ts_smart_edit . allow)
                   (c_smart_edit . allow)
                   (go_smart_edit . allow)
                   (org_smart_edit . allow)
                   (sh_smart_edit . allow)
                   (markdown_smart_edit . allow)
                   (spawn_agent . allow)
                   (wait_agent . allow)
                   (forge_read_issue . allow)
                   (forge_list_pull_requests . allow)))))
  "Equipe de especialistas do Magent (D9): alist (AGENT-NAME . PLIST).
Cada PLIST tem :description, :prompt (base do subagente) e :permission
(alist de tool rules para `magent-permission-from-config'). Os perfis são
registrados no `magent-agent-registry' por `+carlos/magent-team-register'
quando o Magent carrega."
  :type '(alist :key-type string
                :value-type (plist :key-type symbol :value-type sexp))
  :group 'magent)

;; ── Registro no registry do Magent ──────────────────────────────────────────

(defun +carlos/magent-team-agent-info (agent-name spec)
  "Build a `magent-agent-info' struct for team agent AGENT-NAME from SPEC."
  (magent-agent-info-create
   :name agent-name
   :description (plist-get spec :description)
   :mode 'subagent
   :hidden t
   :prompt (plist-get spec :prompt)
   :permission (magent-permission-from-config (plist-get spec :permission))
   :source-layer 'builtin))

(defun +carlos/magent-team-register ()
  "Register all expert team subagent profiles in the Magent registry.
Returns the number of profiles registered, or nil when the Magent registry
API is not available. Idempotent across reloads (same layer/scope replaces
the previous definition). Força a inicialização do registry antes de
registrar: a init lazy do Magent faz `clrhash' e apagaria os perfis se
registrados antes dela."
  (when (and (fboundp 'magent-agent-info-create)
             (fboundp 'magent-agent-registry-register)
             (fboundp 'magent-permission-from-config)
             (fboundp 'magent-agent-registry-ensure-initialized))
    (magent-agent-registry-ensure-initialized)
    (let ((count 0))
      (dolist (entry +carlos/magent-expert-team)
        (ignore-errors
          (magent-agent-registry-register
           (+carlos/magent-team-agent-info (car entry) (cdr entry)))
          (setq count (1+ count))))
      count)))

(defun +carlos/magent-team-registered-p (agent-name)
  "Return non-nil when AGENT-NAME is registered as an expert team subagent."
  (and (fboundp 'magent-agent-registry-get)
       (fboundp 'magent-agent-info-mode-p)
       (let ((info (magent-agent-registry-get agent-name)))
         (and info (magent-agent-info-mode-p info 'subagent)))))

;; Registro automático assim que o registry do Magent estiver disponível
(with-eval-after-load 'magent-agent-registry
  (+carlos/magent-team-register))

(provide 'custom-magent-team)
;;; custom-magent-team.el ends here
