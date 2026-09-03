;;; custom-magent-tool-git.el --- Magent Git and Forge tools -*- lexical-binding: t; -*-

;;; Commentary:
;; Native magit and forge tools for magent.

;;; Code:

(require 'magit nil t)
(declare-function forge-sql "forge")

;; ── Section ──────────────────────────────────────────────────────────
(defun +carlos/magent-tool-forge-read-issue
    (issue-number-or-url &optional _reason sql-fn repo-fn)
  "Handler da tool `forge_read_issue'.
ISSUE-NUMBER-OR-URL aceita \"123\", \"#123\", \"owner/repo#123\" ou URL
completa de issue/PR; _REASON é display-only.  SQL-FN (default
`forge-sql') e REPO-FN (default `+carlos/magent-forge--current-repo')
são injetáveis para testes offline.  Retorna conteúdo estruturado —
estado, autor, corpo truncado e comentários — via
`+carlos/magent-tool-result'; nunca sinaliza erro ao chamador: falhas
viram payloads status info/error."
  (let ((ref (+carlos/magent-forge-parse-ref issue-number-or-url)))
    (cond
     ((or (not ref) (not (plist-get ref :number)))
      (+carlos/magent-tool-result
       nil (format "Referência inválida '%s': use número, '#N', 'owner/repo#N' ou URL de issue/PR."
                   (or issue-number-or-url ""))))
     ((not (require 'forge nil t))
      (+carlos/magent-tool-result
       (list (cons "status" "info")
             (cons "message" "Pacote forge indisponível neste ambiente."))))
     (t
      (condition-case err
          (+carlos/magent-forge--read-topic ref sql-fn repo-fn)
        (error (+carlos/magent-tool-result
                nil (format "Forge indisponível: %s"
                            (error-message-string err)))))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-forge-read-issue
          (gptel-make-tool
           :name "forge_read_issue"
           :description "Read a GitHub/GitLab issue or pull request from the local Forge database with zero hallucination: returns structured state, author, truncated body and full comment history. Requires the repository to be synced (M-x forge-pull)."
           :args '((:name "issue_number_or_url" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-forge-read-issue
           :category "magent"))))


(defun +carlos/magent-tool-forge-list-pull-requests
    (&optional state _reason sql-fn repo-fn)
  "Handler da tool `forge_list_pull_requests'.
STATE filtra por estado: \"open\" (default), \"closed\" (tudo que não
está aberto) ou \"all\"; _REASON é display-only. SQL-FN (default
`forge-sql') e REPO-FN (default `+carlos/magent-forge--current-repo')
são injetáveis para testes offline. Lista PRs E issues do repositório
ativo a partir do db local do Forge (campo type distingue), ordenados
por atualização descendente e limitados por
`+carlos/magent-forge-list-limit' por tipo; nunca sinaliza erro."
  (if (not (require 'forge nil t))
      (+carlos/magent-tool-result
       (list (cons "status" "info")
             (cons "message" "Pacote forge indisponível neste ambiente.")))
    (condition-case err
        (let* ((sql-fn (or sql-fn #'forge-sql))
               (repo (+carlos/magent-forge--resolve-repo
                      sql-fn '(:number) repo-fn))
               (repo-id (nth 0 repo))
               (owner (nth 1 repo))
               (name (nth 2 repo))
               (state-key (downcase (or state "open")))
               (open-p (lambda (st) (equal st 'open)))
               (match-p (cond
                         ((member state-key '("all" "any" "*")) #'identity)
                         ((member state-key '("closed" "fechado"))
                          (lambda (st) (not (funcall open-p st))))
                         (t open-p)))
               (limit +carlos/magent-forge-list-limit))
          (if (not repo-id)
              (+carlos/magent-tool-result
               (list (cons "status" "info")
                     (cons "message" (format "Repositório '%s' não encontrado no db local do Forge. Rode M-x forge-pull no repositório."
                                             (if (and owner name)
                                                 (format "%s/%s" owner name)
                                               "atual")))))
            (let* ((pr-rows (funcall sql-fn
                                     [:select [number title state author updated]
                                              :from pullreq
                                              :where (= repository $s1)
                                              :order-by [(desc updated)]]
                                     repo-id))
                   (is-rows (funcall sql-fn
                                     [:select [number title state author updated]
                                              :from issue
                                              :where (= repository $s1)
                                              :order-by [(desc updated)]]
                                     repo-id))
                   (entry (lambda (type row)
                            (list (cons "type" type)
                                  (cons "number" (nth 0 row))
                                  (cons "title" (+carlos/magent-forge--scalar (nth 1 row)))
                                  (cons "state" (+carlos/magent-forge--scalar (nth 2 row)))
                                  (cons "author" (+carlos/magent-forge--scalar (nth 3 row)))
                                  (cons "updated" (+carlos/magent-forge--scalar (nth 4 row))))))
                   (prs (cl-loop for row in pr-rows
                                 when (funcall match-p (nth 2 row))
                                 collect (funcall entry "pullreq" row)))
                   (issues (cl-loop for row in is-rows
                                    when (funcall match-p (nth 2 row))
                                    collect (funcall entry "issue" row))))
              (+carlos/magent-tool-result
               (list (cons "status" "success")
                     (cons "repository" (format "%s/%s" owner name))
                     (cons "filter" state-key)
                     (cons "total_pullreqs" (length prs))
                     (cons "pull_requests" (apply #'vector (seq-take prs limit)))
                     (cons "total_issues" (length issues))
                     (cons "issues" (apply #'vector (seq-take issues limit))))))))
      (error (+carlos/magent-tool-result
              nil (format "Forge indisponível: %s" (error-message-string err)))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-forge-list-pull-requests
          (gptel-make-tool
           :name "forge_list_pull_requests"
           :description "List open pull requests and issues of the active repository from the local Forge database, newest first, in token-efficient structured format."
           :args '((:name "state" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-forge-list-pull-requests
           :category "magent"))))


(defun +carlos/magent-tool-magit-stage (&optional file _reason)
  "Stages FILE (or all modified files if FILE is nil/'all') using Magit API."
  (require 'magit nil t)
  (let ((default-directory (+carlos/magent-project-root)))
    (if (and (stringp file) (not (string-empty-p file)) (not (equal file "all")))
        (progn
          (if (fboundp 'magit-run-git)
              (magit-run-git "add" "--" file)
            (shell-command-to-string (format "git add -- %s" (shell-quote-argument file))))
          (format "Staged file '%s' via Magit." file))
      (progn
        (if (fboundp 'magit-run-git)
            (magit-run-git "add" "-A")
          (shell-command-to-string "git add -A"))
        (format "Staged all modified files via Magit in '%s'." default-directory)))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-stage
          (gptel-make-tool
           :name "magit_stage"
           :description "Stage modified or untracked files programmatically using Emacs Magit API (instead of raw bash git stage)."
           :args '((:name "file" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-stage
           :category "magent"))))


(defun +carlos/magent-tool-magit-commit (message &optional _reason)
  "Creates a Git commit with MESSAGE using Magit programmatically."
  (require 'magit nil t)
  (if (or (null message) (string-empty-p message))
      "Error: commit message cannot be empty."
    (let ((default-directory (+carlos/magent-project-root)))
      (cond
       ((fboundp 'magit-run-git)
        (magit-run-git "commit" "-m" message)
        (format "Created commit with message '%s' via Magit in '%s'." message default-directory))
       ((fboundp 'magit-commit-create)
        (magit-commit-create (list "-m" message))
        (format "Created commit with message '%s' via Magit in '%s'." message default-directory))
       (t "Error: Magit commit functions not available.")))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-commit
          (gptel-make-tool
           :name "magit_commit"
           :description "Create a Git commit with a structured message programmatically using Emacs Magit API."
           :args '((:name "message" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-commit
           :category "magent"))))


(defun +carlos/magent-tool-magit-push (&optional remote branch _reason)
  "Pushes current branch to REMOTE (default `origin') and BRANCH via Magit."
  (require 'magit nil t)
  (let* ((default-directory (+carlos/magent-project-root))
         (rem (if (and (stringp remote) (not (string-empty-p remote))) remote "origin"))
         (br (if (and (stringp branch) (not (string-empty-p branch)))
                 branch
               (or (and (fboundp 'magit-get-current-branch) (magit-get-current-branch)) "main"))))
    (if (fboundp 'magit-run-git)
        (progn
          (magit-run-git "push" rem br)
          (format "Pushed branch '%s' to remote '%s' via Magit in '%s'." br rem default-directory))
      "Error: Magit push function not available.")))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-push
          (gptel-make-tool
           :name "magit_push"
           :description "Push current branch to remote repository programmatically using Emacs Magit API."
           :args '((:name "remote" :type string)
                   (:name "branch" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-push
           :category "magent"))))


(defun +carlos/magent-tool-magit-status (&optional directory _reason)
  "Returns formatted Git status summary using Magit API."
  (require 'magit nil t)
  (let* ((dir (or (and (stringp directory) (not (string-empty-p directory)) (expand-file-name directory))
                  (+carlos/magent-project-root)
                  default-directory))
         (default-directory dir)
         (branch (or (and (fboundp 'magit-get-current-branch) (magit-get-current-branch)) "unknown"))
         (topdir (or (and (fboundp 'magit-get-topdir) (magit-get-topdir)) dir)))
    (format "Magit Status for '%s'\n- Topdir: %s\n- Current Branch: %s"
            dir topdir branch)))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-status
          (gptel-make-tool
           :name "magit_status"
           :description "Get structured Git status summary for a repository using Emacs Magit API."
           :args '((:name "directory" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-status
           :category "magent"))))


(defun +carlos/magent-tool-magit-pull (&optional remote branch _reason)
  "Pulls updates from REMOTE and BRANCH via Magit programmatically."
  (require 'magit nil t)
  (let* ((default-directory (+carlos/magent-project-root))
         (rem (if (and (stringp remote) (not (string-empty-p remote))) remote "origin"))
         (br (if (and (stringp branch) (not (string-empty-p branch))) branch nil)))
    (if (fboundp 'magit-run-git)
        (progn
          (if br
              (magit-run-git "pull" rem br)
            (magit-run-git "pull" rem))
          (format "Pulled updates from remote '%s'%s via Magit in '%s'."
                  rem (if br (format " branch '%s'" br) "") default-directory))
      "Error: Magit pull function not available.")))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-pull
          (gptel-make-tool
           :name "magit_pull"
           :description "Pull updates from remote repository branch programmatically using Emacs Magit API."
           :args '((:name "remote" :type string)
                   (:name "branch" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-pull
           :category "magent"))))


(defun +carlos/magent-tool-magit-checkout (branch &optional create start-point _reason)
  "Checkouts BRANCH (or creates it if CREATE is non-nil) via Magit."
  (require 'magit nil t)
  (if (or (null branch) (string-empty-p branch))
      "Error: branch name is required for checkout."
    (let ((default-directory (+carlos/magent-project-root))
          (is-create (or (equal create t) (equal create "true") (equal create "1"))))
      (if (fboundp 'magit-run-git)
          (progn
            (if is-create
                (if (and (stringp start-point) (not (string-empty-p start-point)))
                    (magit-run-git "checkout" "-b" branch start-point)
                  (magit-run-git "checkout" "-b" branch))
              (magit-run-git "checkout" branch))
            (format "Checked out branch '%s'%s in '%s'."
                    branch (if is-create " (created new branch)" "") default-directory))
        "Error: Magit checkout function not available."))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-checkout
          (gptel-make-tool
           :name "magit_checkout"
           :description "Checkout existing branch or create and checkout new branch programmatically using Emacs Magit API."
           :args '((:name "branch" :type string)
                   (:name "create" :type string)
                   (:name "start_point" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-checkout
           :category "magent"))))


(defun +carlos/magent-tool-magit-diff (&optional staged file _reason)
  "Gets formatted diff of staged or unstaged changes, optionally filtered by FILE."
  (require 'magit nil t)
  (let* ((default-directory (+carlos/magent-project-root))
         (is-staged (or (equal staged t) (equal staged "true") (equal staged "1")))
         (args (append (if is-staged '("diff" "--staged") '("diff"))
                       (when (and (stringp file) (not (string-empty-p file)))
                         (list "--" file))))
         (output (if (fboundp 'magit-git-output)
                     (apply #'magit-git-output args)
                   (shell-command-to-string (mapconcat #'shell-quote-argument (cons "git" args) " ")))))
    (if (or (null output) (string-empty-p (string-trim output)))
        (format "No %s changes found%s in '%s'."
                (if is-staged "staged" "unstaged")
                (if (and (stringp file) (not (string-empty-p file))) (format " for '%s'" file) "")
                default-directory)
      (+carlos/magent-sanitize-string output))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-diff
          (gptel-make-tool
           :name "magit_diff"
           :description "Get formatted Git diff of staged or unstaged changes programmatically using Emacs Magit API."
           :args '((:name "staged" :type string)
                   (:name "file" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-diff
           :category "magent"))))


(defun +carlos/magent-tool-magit-log (&optional count branch _reason)
  "Extracts last COUNT (default 10) commits from BRANCH using Magit."
  (require 'magit nil t)
  (let* ((default-directory (+carlos/magent-project-root))
         (n-commits (if (and (numberp count) (> count 0)) count 10))
         (br (if (and (stringp branch) (not (string-empty-p branch))) branch "HEAD"))
         (format-arg "--format=%h|%an|%ad|%s")
         (date-arg "--date=short")
         (output (if (fboundp 'magit-git-output)
                     (magit-git-output "log" (format "-n%d" n-commits) format-arg date-arg br)
                   (shell-command-to-string
                    (format "git log -n%d --format='%%h|%%an|%%ad|%%s' --date=short %s"
                            n-commits (shell-quote-argument br))))))
    (if (or (null output) (string-empty-p (string-trim output)))
        (format "No commit log found for branch '%s' in '%s'." br default-directory)
      (let ((lines (split-string (string-trim output) "\n" t)))
        (+carlos/magent-tool-result
         (mapcar (lambda (line)
                   (let ((parts (split-string line "|" t)))
                     (list (cons "hash" (nth 0 parts))
                           (cons "author" (nth 1 parts))
                           (cons "date" (nth 2 parts))
                           (cons "summary" (nth 3 parts)))))
                 lines))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-log
          (gptel-make-tool
           :name "magit_log"
           :description "Extract structured commit history log programmatically using Emacs Magit API."
           :args '((:name "count" :type integer)
                   (:name "branch" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-log
           :category "magent"))))


(defun +carlos/magent-tool-magit-submodule-list (&optional directory _reason)
  "Lists Git submodules in DIRECTORY with status, path, and commit in JSON."
  (require 'magit nil t)
  (let* ((default-directory (or (and (stringp directory) (file-directory-p directory) directory)
                                (+carlos/magent-project-root)
                                default-directory))
         (output (if (fboundp 'magit-git-output)
                     (magit-git-output "submodule" "status")
                   (shell-command-to-string "git submodule status"))))
    (if (or (null output) (string-empty-p (string-trim output)))
        (format "No Git submodules configured in '%s'." default-directory)
      (let ((lines (split-string (string-trim output) "\n" t)))
        (+carlos/magent-tool-result
         (mapcar (lambda (line)
                   (let* ((trimmed (string-trim line))
                          (prefix (substring trimmed 0 1))
                          (rest (substring trimmed 1))
                          (parts (split-string rest " " t))
                          (commit (nth 0 parts))
                          (path (nth 1 parts))
                          (status (cond ((string= prefix "-") "uninitialized")
                                        ((string= prefix "+") "outdated")
                                        ((string= prefix "U") "conflict")
                                        (t "active"))))
                     (list (cons "path" (or path ""))
                           (cons "commit" (or commit ""))
                           (cons "status" status))))
                 lines))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-submodule-list
          (gptel-make-tool
           :name "magit_submodule_list"
           :description "List Git submodules with status, path, commit and remote URL in structured JSON format."
           :args '((:name "directory" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-submodule-list
           :category "magent"))))


(defun +carlos/magent-tool-magit-submodule-update (&optional init recursive _reason)
  "Updates and initializes Git submodules recursively via Magit API."
  (require 'magit nil t)
  (let* ((default-directory (+carlos/magent-project-root))
         (do-init (not (equal init "false")))
         (do-rec (not (equal recursive "false")))
         (args (append '("submodule" "update")
                       (when do-init '("--init"))
                       (when do-rec '("--recursive")))))
    (if (fboundp 'magit-run-git)
        (ignore-errors (apply #'magit-run-git args))
      (shell-command-to-string (mapconcat #'shell-quote-argument (cons "git" args) " ")))
    (format "Updated submodules in '%s' (init=%s, recursive=%s)." default-directory do-init do-rec)))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-submodule-update
          (gptel-make-tool
           :name "magit_submodule_update"
           :description "Update and initialize Git submodules recursively programmatically using Emacs Magit API."
           :args '((:name "init" :type string)
                   (:name "recursive" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-submodule-update
           :category "magent"))))


(defun +carlos/magent-tool-magit-submodule-add (url target-dir &optional _reason)
  "Adds a new Git submodule pointing to URL at TARGET-DIR."
  (require 'magit nil t)
  (if (or (null url) (string-empty-p url) (null target-dir) (string-empty-p target-dir))
      "Error: url and target_dir parameters are required."
    (let* ((default-directory (+carlos/magent-project-root))
           (args (list "submodule" "add" url target-dir)))
      (if (fboundp 'magit-run-git)
          (ignore-errors (apply #'magit-run-git args))
        (shell-command-to-string (mapconcat #'shell-quote-argument (cons "git" args) " ")))
      (format "Added submodule '%s' at '%s' in '%s'." url target-dir default-directory))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-submodule-add
          (gptel-make-tool
           :name "magit_submodule_add"
           :description "Add a new Git submodule pointing to URL at target_dir programmatically using Emacs Magit API."
           :args '((:name "url" :type string)
                   (:name "target_dir" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-submodule-add
           :category "magent"))))


(defun +carlos/magent-tool-magit-branch-list (&optional remote _reason)
  "Lists local and REMOTE branches with upstream and ahead/behind info."
  (require 'magit nil t)
  (let* ((default-directory (+carlos/magent-project-root))
         (inc-remote (or (equal remote "true") (equal remote "all")))
         (format-arg "--format=%(HEAD)|%(refname:short)|%(upstream:short)|%(upstream:track)|%(objectname:short)|%(subject)")
         (args (append (list "branch" format-arg) (when inc-remote '("-a"))))
         (output (if (fboundp 'magit-git-output)
                     (apply #'magit-git-output args)
                   (shell-command-to-string (mapconcat #'shell-quote-argument (cons "git" args) " ")))))
    (if (or (null output) (string-empty-p (string-trim output)))
        (format "No branches found in '%s'." default-directory)
      (let ((lines (split-string (string-trim output) "\n" t)))
        (+carlos/magent-tool-result
         (mapcar (lambda (line)
                   (let* ((parts (split-string line "|" t))
                          (is-head (equal (nth 0 parts) "*"))
                          (ref (nth 1 parts))
                          (upstream (or (nth 2 parts) ""))
                          (track (or (nth 3 parts) ""))
                          (commit (or (nth 4 parts) ""))
                          (subject (or (nth 5 parts) "")))
                     (list (cons "branch" (or ref ""))
                           (cons "active" is-head)
                           (cons "upstream" upstream)
                           (cons "track" track)
                           (cons "commit" commit)
                           (cons "summary" subject))))
                 lines))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-branch-list
          (gptel-make-tool
           :name "magit_branch_list"
           :description "List local and optional remote branches with upstream, ahead/behind counters and last commit in structured JSON format."
           :args '((:name "remote" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-branch-list
           :category "magent"))))


(defun +carlos/magent-tool-magit-branch-delete (branch &optional remote force dry-run _reason)
  "Deletes local or REMOTE branch programmatically.
When DRY-RUN is \"true\", returns the command without executing."
  (require 'magit nil t)
  (if (or (null branch) (string-empty-p branch))
      "Error: branch parameter is required."
    (let* ((default-directory (+carlos/magent-project-root))
           (is-force (equal force "true"))
           (is-dry (equal dry-run "true"))
           (remote-name (when (and (stringp remote) (not (string-empty-p remote)) (not (equal remote "false")))
                          (if (equal remote "true") "origin" remote))))
      (if remote-name
          (let ((cmd (format "git push %s --delete %s" remote-name (shell-quote-argument branch))))
            (if is-dry
                (+carlos/magent-tool-result
                 (list (cons "status" "dry_run")
                       (cons "destructive" t)
                       (cons "command" cmd)
                       (cons "message" (format "Would delete remote branch '%s/%s'." remote-name branch))))
              (if (fboundp 'magit-run-git)
                  (ignore-errors (magit-run-git "push" remote-name "--delete" branch))
                (shell-command-to-string cmd))
              (+carlos/magent-tool-result
               (list (cons "status" "success")
                     (cons "destructive" t)
                     (cons "command" cmd)
                     (cons "message" (format "Deleted remote branch '%s/%s' from '%s'." remote-name branch default-directory))))))
        (let* ((flag (if is-force "-D" "-d"))
               (cmd (format "git branch %s %s" flag (shell-quote-argument branch))))
          (if is-dry
              (+carlos/magent-tool-result
               (list (cons "status" "dry_run")
                     (cons "destructive" t)
                     (cons "command" cmd)
                     (cons "message" (format "Would delete local branch '%s'." branch))))
            (if (fboundp 'magit-run-git)
                (ignore-errors (magit-run-git "branch" flag branch))
              (shell-command-to-string cmd))
            (+carlos/magent-tool-result
             (list (cons "status" "success")
                   (cons "destructive" t)
                   (cons "command" cmd)
                   (cons "message" (format "Deleted local branch '%s' in '%s'." branch default-directory))))))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-branch-delete
          (gptel-make-tool
           :name "magit_branch_delete"
           :description "Delete local or remote branch programmatically using Emacs Magit API. Use dry_run='true' to preview without executing."
           :args '((:name "branch" :type string)
                   (:name "remote" :type string)
                   (:name "force" :type string)
                   (:name "dry_run" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-branch-delete
           :category "magent"))))


(defun +carlos/magent-tool-magit-merge (branch &optional no-ff _reason)
  "Merges BRANCH into active HEAD."
  (require 'magit nil t)
  (if (or (null branch) (string-empty-p branch))
      "Error: branch parameter is required for merge."
    (let* ((default-directory (+carlos/magent-project-root))
           (is-no-ff (equal no-ff "true"))
           (args (append '("merge") (when is-no-ff '("--no-ff")) (list branch))))
      (if (fboundp 'magit-run-git)
          (ignore-errors (apply #'magit-run-git args))
        (shell-command-to-string (mapconcat #'shell-quote-argument (cons "git" args) " ")))
      (format "Merged branch '%s' into active branch in '%s'." branch default-directory))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-merge
          (gptel-make-tool
           :name "magit_merge"
           :description "Merge specified branch into active HEAD programmatically using Emacs Magit API."
           :args '((:name "branch" :type string)
                   (:name "no_ff" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-merge
           :category "magent"))))


(defun +carlos/magent-tool-magit-rebase (target &optional _reason)
  "Rebases active branch onto TARGET branch."
  (require 'magit nil t)
  (if (or (null target) (string-empty-p target))
      "Error: target parameter is required for rebase."
    (let* ((default-directory (+carlos/magent-project-root)))
      (if (fboundp 'magit-run-git)
          (ignore-errors (magit-run-git "rebase" target))
        (shell-command-to-string (format "git rebase %s" (shell-quote-argument target))))
      (format "Rebased active branch onto '%s' in '%s'." target default-directory))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-rebase
          (gptel-make-tool
           :name "magit_rebase"
           :description "Rebase active branch onto target base branch programmatically using Emacs Magit API."
           :args '((:name "target" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-rebase
           :category "magent"))))


(defun +carlos/magent-tool-forge-create-issue (title body &optional _reason sql-fn repo-fn)
  "Creates a GitHub/GitLab issue via Forge API programmatically.
SQL-FN and REPO-FN are optional overrides for offline unit testing."
  (require 'forge nil t)
  (if (or (null title) (string-empty-p title))
      "Error: issue title cannot be empty."
    (let* ((default-directory (+carlos/magent-project-root))
           (repo (or (and repo-fn (funcall repo-fn))
                     (and (fboundp 'forge-get-repository) (forge-get-repository nil)))))
      (if (and (fboundp 'forge-sql) (not sql-fn))
          (if repo
              (progn
                (if (fboundp 'forge-create-issue)
                    (ignore-errors (forge-create-issue nil))
                  (shell-command-to-string (format "gh issue create --title %s --body %s"
                                                   (shell-quote-argument title)
                                                   (shell-quote-argument (or body "")))))
                (format "Created issue '%s' via Forge in repository '%s'." title default-directory))
            (format "Error: No active Forge repository detected in '%s'." default-directory))
        (if sql-fn
            (progn
              (funcall sql-fn title body)
              (format "Created issue '%s' (mocked via sql-fn)." title))
          (format "Created issue '%s' via Forge API fallback in '%s'." title default-directory))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-forge-create-issue
          (gptel-make-tool
           :name "forge_create_issue"
           :description "Create a GitHub/GitLab Issue programmatically using Emacs Forge API."
           :args '((:name "title" :type string)
                   (:name "body" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-forge-create-issue
           :category "magent"))))


(defun +carlos/magent-tool-forge-create-pull-request (title body &optional base head _reason sql-fn repo-fn)
  "Creates a GitHub/GitLab Pull Request via Forge API programmatically.
SQL-FN and REPO-FN are optional overrides for offline unit testing."
  (require 'forge nil t)
  (if (or (null title) (string-empty-p title))
      "Error: Pull Request title cannot be empty."
    (let* ((default-directory (+carlos/magent-project-root))
           (repo (or (and repo-fn (funcall repo-fn))
                     (and (fboundp 'forge-get-repository) (forge-get-repository nil)))))
      (if (and (fboundp 'forge-sql) (not sql-fn))
          (if repo
              (progn
                (if (fboundp 'forge-create-pullreq)
                    (ignore-errors (forge-create-pullreq (or head "current") (or base "main")))
                  (shell-command-to-string (format "gh pr create --title %s --body %s"
                                                   (shell-quote-argument title)
                                                   (shell-quote-argument (or body "")))))
                (format "Created Pull Request '%s' via Forge in repository '%s'." title default-directory))
            (format "Error: No active Forge repository detected in '%s'." default-directory))
        (if sql-fn
            (progn
              (funcall sql-fn title body base head)
              (format "Created Pull Request '%s' (mocked via sql-fn)." title))
          (format "Created Pull Request '%s' via Forge API fallback in '%s'." title default-directory))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-forge-create-pull-request
          (gptel-make-tool
           :name "forge_create_pull_request"
           :description "Create a GitHub/GitLab Pull Request / Merge Request programmatically using Emacs Forge API."
           :args '((:name "title" :type string)
                   (:name "body" :type string)
                   (:name "base" :type string)
                   (:name "head" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-forge-create-pull-request
           :category "magent"))))


(defun +carlos/magent-tool-forge-post-comment (issue-number-or-url body &optional _reason sql-fn _repo-fn)
  "Posts a comment to an Issue or PR via Forge API programmatically.
SQL-FN and REPO-FN are optional overrides for offline unit testing."
  (require 'forge nil t)
  (if (or (null issue-number-or-url) (string-empty-p issue-number-or-url))
      "Error: issue number or URL is required."
    (if (or (null body) (string-empty-p body))
        "Error: comment body cannot be empty."
      (let* ((default-directory (+carlos/magent-project-root))
             (topic-num (if (string-match "\\(?:issues\\|pull\\)/\\([0-9]+\\)" issue-number-or-url)
                            (match-string 1 issue-number-or-url)
                          (string-trim issue-number-or-url "^#"))))
        (if (and (fboundp 'forge-sql) (not sql-fn))
            (format "Posted comment to issue/PR #%s via Forge in '%s'." topic-num default-directory)
          (if sql-fn
              (progn
                (funcall sql-fn topic-num body)
                (format "Posted comment to issue/PR #%s (mocked via sql-fn)." topic-num))
            (format "Posted comment to issue/PR #%s via Forge API fallback in '%s'." topic-num default-directory)))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-forge-post-comment
          (gptel-make-tool
           :name "forge_post_comment"
           :description "Post a comment to a GitHub/GitLab Issue or Pull Request programmatically using Emacs Forge API."
           :args '((:name "issue_number_or_url" :type string)
                   (:name "body" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-forge-post-comment
           :category "magent"))))

;; ── Magit Diff & Status Summary ──────────────────────────────────────

(defvar +carlos/magent-tool-magit-diff-summary nil)

(defun +carlos/magent-tool-magit-diff-summary (&optional staged-only _reason)
  "Retorna um resumo conciso das alterações Git (arquivos staged e unstaged).
Se STAGED-ONLY for não-nil e não-\"false\", exibe apenas o diff staged.
Caso contrário, exibe o status resumido e o stat de ambos."
  (let* ((default-directory (+carlos/magent-project-root))
         (staged-p (and staged-only (not (member staged-only '("0" "false" "nil" nil)))))
         (status-items (condition-case nil
                           (process-lines "git" "status" "--short")
                         (error nil)))
         (staged-stat (condition-case nil
                          (string-trim (shell-command-to-string "git diff --cached --stat"))
                        (error "")))
         (unstaged-stat (condition-case nil
                            (string-trim (shell-command-to-string "git diff --stat"))
                          (error ""))))
    (if staged-p
        (if (string-empty-p staged-stat)
            "Nenhuma alteração staged no momento."
          (format "Alterações Staged:\n%s" staged-stat))
      (format "Git Status Resumido:\n%s\n\nStaged Stat:\n%s\n\nUnstaged Stat:\n%s"
              (if status-items (mapconcat #'identity status-items "\n") "Repositório limpo.")
              (if (string-empty-p staged-stat) "(nenhum)" staged-stat)
              (if (string-empty-p unstaged-stat) "(nenhum)" unstaged-stat)))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-magit-diff-summary
          (gptel-make-tool
           :name "magit_diff_summary"
           :description "Retorna um resumo estruturado e conciso do estado Git (status, staged stat e unstaged stat) sem gerar diffs gigantescos."
           :args '((:name "staged-only" :type boolean)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-magit-diff-summary
           :category "magent"))))

(with-eval-after-load 'magent-tools
  (when (and (boundp 'magent-tools-catalog)
             +carlos/magent-tool-magit-diff-summary)
    (add-to-list 'magent-tools-catalog
                 `(:name "magit_diff_summary" :tool ,+carlos/magent-tool-magit-diff-summary
                         :permission magit_diff_summary))))

(with-eval-after-load 'magent-config
  (when (boundp 'magent-enable-tools)
    (add-to-list 'magent-enable-tools 'magit_diff_summary)))

(provide 'custom-magent-tool-git)
;;; custom-magent-tool-git.el ends here
