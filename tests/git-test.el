;;; git-test.el --- Git (magit/forge/commit IA) regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifica o fluxo de commit com IA: funções existem e o bind C-c C-g
;; está direto no git-commit-mode-map (não via hook — hook não aplica em
;; batch e só vale para buffers reais).  Também cobre o parsing de
;; referências de issue/PR das ferramentas Forge do Magent.

;;; Code:

(require 'ert)
(require 'git-commit)
(require 'custom-magent-tools)

(ert-deftest myemacs-git-commit-ia-functions ()
  (should (fboundp '+carlos/gptel-generate-commit-message))
  (should (fboundp '+carlos/gptel-insert-commit-message)))

(ert-deftest myemacs-git-commit-mode-map-bind ()
  (should (eq (lookup-key git-commit-mode-map (kbd "C-c C-g"))
              '+carlos/gptel-insert-commit-message)))

(ert-deftest myemacs-git-magit-commit-ia-transient ()
  (should (fboundp '+carlos/gptel-generate-commit-message)))

(ert-deftest myemacs-git-forge-use-package-declared ()
  "Forge é carregado via use-package :after magit em custom-git."
  (let ((src (with-temp-buffer
               (insert-file-contents
                (expand-file-name "lisp/custom-git.el"
                                  (locate-dominating-file
                                   default-directory "Justfile")))
               (buffer-string))))
    (should (string-match-p "(use-package forge" src))
    (should (string-match-p ":after magit" src))))

;; ── Forge: parsing de referências de issue/PR ────────────────────────

(ert-deftest myemacs-forge-parse-ref-github-issue-url ()
  "URL completa de issue do GitHub extrai owner/repo/number/kind."
  (let ((ref (+carlos/magent-forge-parse-ref
              "https://github.com/myorg/myrepo/issues/123")))
    (should (= (plist-get ref :number) 123))
    (should (equal (plist-get ref :owner) "myorg"))
    (should (equal (plist-get ref :repo) "myrepo"))
    (should (eq (plist-get ref :kind) 'issue))))

(ert-deftest myemacs-forge-parse-ref-github-pull-url ()
  "URL de pull request (/pull/N) classifica kind=pullreq."
  (let ((ref (+carlos/magent-forge-parse-ref
              "https://github.com/myorg/myrepo/pull/9")))
    (should (= (plist-get ref :number) 9))
    (should (eq (plist-get ref :kind) 'pullreq))))

(ert-deftest myemacs-forge-parse-ref-gitlab-issue-url ()
  "URL GitLab com prefixo /-/issues também parseia."
  (let ((ref (+carlos/magent-forge-parse-ref
              "https://gitlab.com/grp/proj/-/issues/55")))
    (should (= (plist-get ref :number) 55))
    (should (equal (plist-get ref :owner) "grp"))
    (should (equal (plist-get ref :repo) "proj"))
    (should (eq (plist-get ref :kind) 'issue))))

(ert-deftest myemacs-forge-parse-ref-owner-repo-hash ()
  "Forma curta owner/repo#N extrai os três campos."
  (let ((ref (+carlos/magent-forge-parse-ref "myorg/myrepo#12")))
    (should (= (plist-get ref :number) 12))
    (should (equal (plist-get ref :owner) "myorg"))
    (should (equal (plist-get ref :repo) "myrepo"))
    (should-not (plist-get ref :kind))))

(ert-deftest myemacs-forge-parse-ref-hash-and-bare-number ()
  "#N e N resolvem apenas o número, sem owner/repo/kind."
  (dolist (input '("#12" "42"))
    (let ((ref (+carlos/magent-forge-parse-ref input)))
      (should ref)
      (should (= (plist-get ref :number)
                 (if (string= input "#12") 12 42)))
      (should-not (plist-get ref :owner))
      (should-not (plist-get ref :kind)))))

(ert-deftest myemacs-git-commit-ai-reasoning-resilience ()
  "Verifica se a geração de commit com IA tolera pares cons de reasoning (gptel/Gemini)."
  (let ((captured-cb nil))
    (cl-letf (((symbol-function '+carlos/gptel-request)
               (lambda (_prompt _backend _model &rest args)
                 (setq captured-cb (plist-get args :callback)))))
      (let ((default-directory (locate-dominating-file default-directory "Justfile")))
        (cl-letf (((symbol-function 'vc-git-root) (lambda (_) default-directory))
                  ((symbol-function 'shell-command-to-string) (lambda (_) "diff content")))
          ;; 1. Transient `c g' -> +carlos/gptel-generate-commit-message
          (+carlos/gptel-generate-commit-message)
          (should (functionp captured-cb))
          (funcall captured-cb '(reasoning . "**Analyzing diff...**") nil)
          (funcall captured-cb "fix: resolve commit error" nil)
          (should (equal (car kill-ring) "fix: resolve commit error"))
          
          ;; 2. Buffer de commit `C-c C-g' -> +carlos/gptel-insert-commit-message
          (with-temp-buffer
            (git-commit-mode 1)
            (+carlos/gptel-insert-commit-message)
            (should (functionp captured-cb))
            (funcall captured-cb '(reasoning . "**Analyzing diff...**") nil)
            (funcall captured-cb "fix: insert commit msg" nil)
            (should (equal (buffer-string) "fix: insert commit msg"))))))))

(provide 'git-test)
;;; git-test.el ends here
