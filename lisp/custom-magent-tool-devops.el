;;; custom-magent-tool-devops.el --- Magent DevOps tools -*- lexical-binding: t; -*-

;;; Commentary:
;; Native Docker and Systemd tools for magent.

;;; Code:

;; ── Section ──────────────────────────────────────────────────────────
(defvar +carlos/magent-tool-docker-ps nil "Gptel tool for Docker ps.")

(defun +carlos/magent-tool-docker-ps (&optional all filter remote-host _reason)
  "List Docker containers (local or TRAMP) in structured JSON format."
  (let* ((default-directory (if (and remote-host (not (string-empty-p remote-host)))
                                (file-name-as-directory remote-host)
                              default-directory))
         (args (list "ps" "--format" "{{json .}}"))
         (_ (when (and all (or (equal all "true") (eq all t))) (setq args (cons "ps" (cons "-a" (cdr args))))))
         (_ (when (and filter (not (string-empty-p filter)))
              (setq args (append args (list "-f" filter)))))
         (output (condition-case err
                     (with-output-to-string
                       (with-current-buffer standard-output
                         (apply #'process-lines "docker" args)))
                   (error (format "Error running docker ps: %s" (error-message-string err))))))
    (if (string-prefix-p "Error" output)
        (+carlos/magent-tool-result (list (cons "status" "error") (cons "message" output)))
      (let ((lines (split-string output "\n" t)))
        (+carlos/magent-tool-result
         (list (cons "status" "success")
               (cons "count" (length lines))
               (cons "containers_raw" (+carlos/magent-sanitize-string (mapconcat #'identity lines "\n")))))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-docker-ps
          (gptel-make-tool
           :name "docker_ps"
           :description "List Docker containers (local or remote via TRAMP) with ID, image, status, ports and names in structured format."
           :args '((:name "all" :type string)
                   (:name "filter" :type string)
                   (:name "remote_host" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-docker-ps
           :category "magent"))))


(defvar +carlos/magent-tool-docker-logs nil "Gptel tool for Docker logs.")

(defun +carlos/magent-tool-docker-logs (container-id &optional tail grep-pattern remote-host _reason)
  "Inspect container logs with tail limit and optional grep pattern."
  (if (or (not container-id) (string-empty-p container-id))
      (+carlos/magent-tool-result '((status . "error") (message . "container_id parameter is required")))
    (let* ((default-directory (if (and remote-host (not (string-empty-p remote-host)))
                                  (file-name-as-directory remote-host)
                                default-directory))
           (n-lines (or tail "100"))
           (cmd (format "docker logs --tail %s %s 2>&1"
                        (shell-quote-argument n-lines)
                        (shell-quote-argument container-id)))
           (raw-output (shell-command-to-string cmd))
           (sanitized (+carlos/magent-sanitize-string raw-output))
           (lines (split-string sanitized "\n" t))
           (filtered-lines (if (and grep-pattern (not (string-empty-p grep-pattern)))
                               (cl-remove-if-not (lambda (line) (string-match-p grep-pattern line)) lines)
                             lines)))
      (+carlos/magent-tool-result
       (list (cons "status" "success")
             (cons "container" container-id)
             (cons "matching_lines" (length filtered-lines))
             (cons "logs" (mapconcat #'identity (cl-subseq filtered-lines 0 (min (length filtered-lines) 100)) "\n")))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-docker-logs
          (gptel-make-tool
           :name "docker_logs"
           :description "Inspect recent logs of a Docker container with tail limit and optional regex filter."
           :args '((:name "container_id" :type string)
                   (:name "tail" :type string)
                   (:name "grep_pattern" :type string)
                   (:name "remote_host" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-docker-logs
           :category "magent"))))


(defvar +carlos/magent-tool-docker-action nil "Gptel tool for Docker container actions.")

(defun +carlos/magent-tool-docker-action (container-id action &optional remote-host dry-run _reason)
  "Perform action (start, stop, restart, remove) on a Docker container.
When DRY-RUN is \"true\", returns the command without executing."
  (if (or (not container-id) (string-empty-p container-id)
          (not action) (string-empty-p action))
      (+carlos/magent-tool-result '((status . "error") (message . "container_id and action parameters are required")))
    (let ((act (downcase action)))
      (if (not (member act '("start" "stop" "restart" "remove" "rm")))
          (+carlos/magent-tool-result (list (cons "status" "error")
                                            (cons "message" (format "Unsupported action: %s. Allowed: start, stop, restart, remove." action))))
        (let* ((default-directory (if (and remote-host (not (string-empty-p remote-host)))
                                      (file-name-as-directory remote-host)
                                    default-directory))
               (real-act (if (equal act "remove") "rm" act))
               (cmd (format "docker %s %s" real-act (shell-quote-argument container-id)))
               (is-dry (equal dry-run "true"))
               (destructive (member act '("remove" "rm" "stop"))))
          (if is-dry
              (+carlos/magent-tool-result
               (list (cons "status" "dry_run")
                     (cons "destructive" destructive)
                     (cons "command" cmd)
                     (cons "container" container-id)
                     (cons "action" act)
                     (cons "message" (format "Would %s container '%s'." act container-id))))
            (let ((output (+carlos/magent-sanitize-string (shell-command-to-string cmd))))
              (+carlos/magent-tool-result
               (list (cons "status" "success")
                     (cons "destructive" destructive)
                     (cons "command" cmd)
                     (cons "container" container-id)
                     (cons "action" act)
                                           (cons "output" (string-trim output)))))))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-docker-action
          (gptel-make-tool
           :name "docker_action"
           :description "Perform lifecycle action (start, stop, restart, remove) on a Docker container. Use dry_run='true' to preview without executing."
           :args '((:name "container_id" :type string)
                   (:name "action" :type string)
                   (:name "remote_host" :type string)
                   (:name "dry_run" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-docker-action
           :category "magent"))))


(defvar +carlos/magent-tool-systemd-status nil "Gptel tool for systemd unit status.")

(defun +carlos/magent-tool-systemd-status (unit &optional remote-host _reason)
  "Inspect systemd unit status in JSON-safe format."
  (if (or (not unit) (string-empty-p unit))
      (+carlos/magent-tool-result '((status . "error") (message . "unit parameter is required")))
    (let* ((default-directory (if (and remote-host (not (string-empty-p remote-host)))
                                  (file-name-as-directory remote-host)
                                default-directory))
           (cmd (format "systemctl show %s --property=Id,ActiveState,SubState,UnitFileState,LoadState,Description,ExecMainPID"
                        (shell-quote-argument unit)))
           (raw (+carlos/magent-sanitize-string (shell-command-to-string cmd)))
           (lines (split-string raw "\n" t))
           (props nil))
      (dolist (line lines)
        (when (string-match "\\([^=]+\\)=\\(.*\\)" line)
          (push (cons (downcase (match-string 1 line)) (match-string 2 line)) props)))
      (+carlos/magent-tool-result
       (append (list (cons "status" "success") (cons "unit" unit)) props)))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-systemd-status
          (gptel-make-tool
           :name "systemd_status"
           :description "Inspect systemd unit status (active, inactive, failed, enabled) in structured JSON-safe format."
           :args '((:name "unit" :type string)
                   (:name "remote_host" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-systemd-status
           :category "magent"))))


(defvar +carlos/magent-tool-systemd-action nil "Gptel tool for systemd actions.")

(defun +carlos/magent-tool-systemd-action (unit action &optional remote-host dry-run _reason)
  "Execute systemctl action on UNIT.
When DRY-RUN is \"true\", returns the command without executing."
  (if (or (not unit) (string-empty-p unit)
          (not action) (string-empty-p action))
      (+carlos/magent-tool-result '((status . "error") (message . "unit and action parameters are required")))
    (let ((act (downcase action)))
      (if (not (member act '("start" "stop" "restart" "reload" "enable" "disable")))
          (+carlos/magent-tool-result (list (cons "status" "error")
                                            (cons "message" (format "Unsupported action: %s. Allowed: start, stop, restart, reload, enable, disable." action))))
        (let* ((default-directory (if (and remote-host (not (string-empty-p remote-host)))
                                      (file-name-as-directory remote-host)
                                    default-directory))
               (cmd (format "systemctl %s %s" act (shell-quote-argument unit)))
               (is-dry (equal dry-run "true"))
               (destructive (member act '("stop" "disable"))))
          (if is-dry
              (+carlos/magent-tool-result
               (list (cons "status" "dry_run")
                     (cons "destructive" destructive)
                     (cons "command" cmd)
                     (cons "unit" unit)
                     (cons "action" act)
                     (cons "message" (format "Would %s unit '%s'." act unit))))
            (let ((output (+carlos/magent-sanitize-string (shell-command-to-string cmd))))
              (+carlos/magent-tool-result
               (list (cons "status" "success")
                     (cons "destructive" destructive)
                     (cons "command" cmd)
                     (cons "unit" unit)
                     (cons "action" act)
                                           (cons "message" (if (string-empty-p output) (format "Unit %s %ssuccessfully." unit act) (string-trim output))))))))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-systemd-action
          (gptel-make-tool
           :name "systemd_action"
           :description "Execute systemctl management action (start, stop, restart, reload, enable, disable) on a unit. Use dry_run='true' to preview without executing."
           :args '((:name "unit" :type string)
                   (:name "action" :type string)
                   (:name "remote_host" :type string)
                   (:name "dry_run" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-systemd-action
           :category "magent"))))


(defvar +carlos/magent-tool-systemd-journal nil "Gptel tool for systemd journalctl.")

(defun +carlos/magent-tool-systemd-journal (unit &optional tail priority remote-host _reason)
  "Inspect systemd journalctl entries for a unit."
  (if (or (not unit) (string-empty-p unit))
      (+carlos/magent-tool-result '((status . "error") (message . "unit parameter is required")))
    (let* ((default-directory (if (and remote-host (not (string-empty-p remote-host)))
                                  (file-name-as-directory remote-host)
                                default-directory))
           (n-lines (or tail "50"))
           (p-flag (if (and priority (not (string-empty-p priority)))
                       (format "-p %s " (shell-quote-argument priority))
                     ""))
           (cmd (format "journalctl -u %s -n %s %s--no-pager"
                        (shell-quote-argument unit)
                        (shell-quote-argument n-lines)
                        p-flag))
           (raw (+carlos/magent-sanitize-string (shell-command-to-string cmd)))
           (lines (split-string raw "\n" t)))
      (+carlos/magent-tool-result
       (list (cons "status" "success")
             (cons "unit" unit)
             (cons "priority_filter" (or priority "none"))
             (cons "entries_count" (length lines))
             (cons "journal" (mapconcat #'identity (cl-subseq lines 0 (min (length lines) 100)) "\n")))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-systemd-journal
          (gptel-make-tool
           :name "systemd_journal"
           :description "Inspect journalctl logs for a systemd unit with tail limit and priority filter."
           :args '((:name "unit" :type string)
                   (:name "tail" :type string)
                   (:name "priority" :type string)
                   (:name "remote_host" :type string)
                   (:name "reason" :type string))
           :function #'+carlos/magent-tool-systemd-journal
           :category "magent"))))

(provide 'custom-magent-tool-devops)
;;; custom-magent-tool-devops.el ends here
