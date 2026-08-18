;;; magent-buffer-test.el --- Tests for Magent live-buffer driver tools (Fase B/D4) -*- lexical-binding: t; -*-

;;; Commentary:
;; Unit tests for the Fase B/D4 live-buffer driver toolkit: buffer_insert,
;; buffer_replace_region, buffer_undo, lsp_hover, describe_elisp_symbol and
;; the session ownership contract (buffer_conflict; read_buffer adota baseline;
;; reset pela FSM).  Os handlers seguem o contrato de invocação do magent:
;; argumentos posicionais (ordem do argspec, sem o arg display-only "reason")
;; e retorno de um `magent-tool-result' (ou string JSON sem o magent).

;;; Code:

(require 'ert)
(require 'json)
(require 'custom-magent)

(declare-function +carlos/magent-fsm-healing-step "custom-magent-fsm")
(declare-function +carlos/magent-fsm-reset "custom-magent-fsm")
(defvar +carlos/magent-fsm-healing-attempts)
(defvar +carlos/magent-fsm-healing-last-error-count)
(defvar +carlos/magent-system-directives)

(defun myemacs-buffer-result-output (res)
  "Extrai o output (string) de RES — struct `magent-tool-result' ou string."
  (if (and (fboundp 'magent-tool-result-p) (magent-tool-result-p res))
      (magent-tool-result-output-string res)
    (if (stringp res) res (format "%s" res))))

(defun myemacs-buffer-parse (res)
  "Parsa o JSON do output de RES como alist."
  (json-read-from-string (myemacs-buffer-result-output res)))

(defun myemacs-buffer-test-buffer ()
  "Cria/limpa o buffer de teste e retorna (BUF . NAME)."
  (let* ((buf (get-buffer-create "*magent-buffer-test*"))
         (name (buffer-name buf)))
    (with-current-buffer buf
      (erase-buffer)
      (setq buffer-undo-list nil))
    (cons buf name)))

(ert-deftest myemacs-magent-buffer-insert-at-point ()
  "Garante que `buffer_insert` insere no point do buffer alvo."
  (let* ((pair (myemacs-buffer-test-buffer))
         (buf (car pair))
         (name (cdr pair)))
    (unwind-protect
        (progn
          (setq +carlos/magent-buffer-session nil)
          (with-current-buffer buf
            (insert "hello")
            (goto-char (point-max)))
          (let* ((res (+carlos/magent-tool-buffer-insert " WORLD" name))
                 (parsed (myemacs-buffer-parse res)))
            (should (equal (alist-get 'status parsed) "success"))
            (should (equal (alist-get 'buffer parsed) name))
            (with-current-buffer buf
              (should (string= (buffer-string) "hello WORLD")))))
      (kill-buffer buf))))

(ert-deftest myemacs-magent-buffer-insert-at-line-column ()
  "Garante que `buffer_insert` respeita (line 1-based, column 0-based)."
  (let* ((pair (myemacs-buffer-test-buffer))
         (buf (car pair))
         (name (cdr pair)))
    (unwind-protect
        (progn
          (setq +carlos/magent-buffer-session nil)
          (with-current-buffer buf (insert "aaa\nbbb\nccc\n"))
          (let* ((res (+carlos/magent-tool-buffer-insert "XXX" name 2 1))
                 (parsed (myemacs-buffer-parse res)))
            (should (equal (alist-get 'status parsed) "success"))
            (should (equal (alist-get 'line parsed) 2))
            (with-current-buffer buf
              (should (string= (buffer-string) "aaa\nbXXXbb\nccc\n")))))
      (kill-buffer buf))))

(ert-deftest myemacs-magent-buffer-insert-missing-text ()
  "Garante que `buffer_insert` valida o parâmetro obrigatório text."
  (let* ((pair (myemacs-buffer-test-buffer))
         (buf (car pair)))
    (unwind-protect
        (let ((out (myemacs-buffer-result-output
                    (+carlos/magent-tool-buffer-insert nil (buffer-name buf)))))
          (should (string-match-p "obrigatório" out)))
      (kill-buffer buf))))

(ert-deftest myemacs-magent-buffer-insert-conflict ()
  "Edição externa entre mutações do driver dispara buffer_conflict."
  (let* ((pair (myemacs-buffer-test-buffer))
         (buf (car pair))
         (name (cdr pair)))
    (unwind-protect
        (progn
          (setq +carlos/magent-buffer-session nil)
          (with-current-buffer buf (insert "aaa\n"))
          (let* ((res (+carlos/magent-tool-buffer-insert " X" name))
                 (parsed (myemacs-buffer-parse res)))
            (should (equal (alist-get 'status parsed) "success")))
          (with-current-buffer buf (goto-char (point-max)) (insert "user\n"))
          (let ((out (myemacs-buffer-result-output
                      (+carlos/magent-tool-buffer-insert " Y" name))))
            (should (string-match-p "buffer_conflict" out))))
      (kill-buffer buf))))

(ert-deftest myemacs-magent-buffer-replace-region-whole-lines ()
  "`buffer_replace_region` substitui linhas inteiras (start/end line)."
  (let* ((pair (myemacs-buffer-test-buffer))
         (buf (car pair))
         (name (cdr pair)))
    (unwind-protect
        (progn
          (setq +carlos/magent-buffer-session nil)
          (with-current-buffer buf (insert "l1\nl2\nl3\nl4\n"))
          (let* ((res (+carlos/magent-tool-buffer-replace-region "NEW\n" name 2 nil 3))
                 (parsed (myemacs-buffer-parse res)))
            (should (equal (alist-get 'status parsed) "success"))
            (with-current-buffer buf
              (should (string= (buffer-string) "l1\nNEW\nl4\n")))))
      (kill-buffer buf))))

(ert-deftest myemacs-magent-buffer-replace-region-exact-range ()
  "`buffer_replace_region` substitui um range exato (linha/colunas)."
  (let* ((pair (myemacs-buffer-test-buffer))
         (buf (car pair))
         (name (cdr pair)))
    (unwind-protect
        (progn
          (setq +carlos/magent-buffer-session nil)
          (with-current-buffer buf (insert "abcdef\n"))
          (let* ((res (+carlos/magent-tool-buffer-replace-region "XY" name 1 2 1 4))
                 (parsed (myemacs-buffer-parse res)))
            (should (equal (alist-get 'status parsed) "success"))
            (with-current-buffer buf
              (should (string= (buffer-string) "abXYef\n")))))
      (kill-buffer buf))))

(ert-deftest myemacs-magent-buffer-replace-region-active-region ()
  "`buffer_replace_region` usa a região ativa quando não há coordenadas."
  (let* ((pair (myemacs-buffer-test-buffer))
         (buf (car pair)))
    (unwind-protect
        (let ((transient-mark-mode t))
          (setq +carlos/magent-buffer-session nil)
          (with-current-buffer buf
            (insert "hello world\n")
            (goto-char 7)
            (push-mark (point) nil t)
            (goto-char 12)
            (let* ((res (+carlos/magent-tool-buffer-replace-region "there"))
                   (parsed (myemacs-buffer-parse res)))
              (should (equal (alist-get 'status parsed) "success")))
            (should (string= (buffer-string) "hello there\n"))))
      (kill-buffer buf))))

(ert-deftest myemacs-magent-buffer-replace-region-missing-coords ()
  "`buffer_replace_region` exige start_line ou região ativa."
  (let* ((pair (myemacs-buffer-test-buffer))
         (buf (car pair)))
    (unwind-protect
        (progn
          (setq +carlos/magent-buffer-session nil)
          (with-current-buffer buf (insert "abc\n") (deactivate-mark))
          (let ((out (myemacs-buffer-result-output
                      (+carlos/magent-tool-buffer-replace-region "X" (buffer-name buf)))))
            (should (string-match-p "requer start_line" out))))
      (kill-buffer buf))))

(ert-deftest myemacs-magent-buffer-undo ()
  "`buffer_undo` reverte a última mutação do driver."
  (let* ((pair (myemacs-buffer-test-buffer))
         (buf (car pair))
         (name (cdr pair)))
    (unwind-protect
        (progn
          (setq +carlos/magent-buffer-session nil)
          (with-current-buffer buf (insert "base\n") (undo-boundary))
          (should (equal (alist-get 'status
                                    (myemacs-buffer-parse
                                     (+carlos/magent-tool-buffer-insert "X" name)))
                         "success"))
          (with-current-buffer buf
            (should (string= (buffer-string) "base\nX")))
          (let* ((res (+carlos/magent-tool-buffer-undo name))
                 (parsed (myemacs-buffer-parse res)))
            (should (equal (alist-get 'status parsed) "success"))
            (with-current-buffer buf
              (should (string= (buffer-string) "base\n")))))
      (kill-buffer buf))))

(ert-deftest myemacs-magent-buffer-undo-nothing ()
  "`buffer_undo` responde info quando não há o que desfazer."
  (let* ((pair (myemacs-buffer-test-buffer))
         (buf (car pair))
         (name (cdr pair)))
    (unwind-protect
        (let* ((res (+carlos/magent-tool-buffer-undo name))
               (parsed (myemacs-buffer-parse res)))
          (should (equal (alist-get 'status parsed) "info")))
      (kill-buffer buf))))

(ert-deftest myemacs-magent-buffer-lsp-hover-no-eglot ()
  "`lsp_hover` responde info/backend none sem servidor LSP, com identifier."
  (let* ((pair (myemacs-buffer-test-buffer))
         (buf (car pair))
         (name (cdr pair)))
    (unwind-protect
        (progn
          (setq +carlos/magent-buffer-session nil)
          (with-current-buffer buf (insert "car cdr") (goto-char 2))
          (let* ((res (+carlos/magent-tool-lsp-hover name))
                 (parsed (myemacs-buffer-parse res)))
            (should (equal (alist-get 'status parsed) "info"))
            (should (equal (alist-get 'backend parsed) "none"))
            (should (equal (alist-get 'identifier parsed) "car"))))
      (kill-buffer buf))))

(ert-deftest myemacs-magent-buffer-describe-symbol ()
  "`describe_elisp_symbol` descreve função e variável do Elisp."
  (let* ((res (+carlos/magent-tool-describe-elisp-symbol "car"))
         (parsed (myemacs-buffer-parse res)))
    (should (equal (alist-get 'status parsed) "success"))
    (should (equal (alist-get 'kind parsed) "function"))
    (should (stringp (alist-get 'docstring parsed)))
    (should (> (length (alist-get 'docstring parsed)) 0)))
  (let* ((res (+carlos/magent-tool-describe-elisp-symbol "case-fold-search"))
         (parsed (myemacs-buffer-parse res)))
    (should (equal (alist-get 'kind parsed) "variable"))))

(ert-deftest myemacs-magent-buffer-describe-symbol-missing ()
  "`describe_elisp_symbol` valida o parâmetro obrigatório symbol."
  (let ((out (myemacs-buffer-result-output
              (+carlos/magent-tool-describe-elisp-symbol nil))))
    (should (string-match-p "obrigatório" out))))

(ert-deftest myemacs-magent-buffer-ownership-adopt-on-read-buffer ()
  "O advice do read_buffer adota o baseline; edição externa depois conflita."
  (skip-unless (require 'magent-tools nil t))
  (let* ((file (make-temp-file "magent-buffer-test" nil ".el"))
         (buf (find-file-noselect file)))
    (unwind-protect
        (progn
          (setq +carlos/magent-buffer-session nil)
          (with-current-buffer buf
            (erase-buffer)
            (insert "line1\nline2\n")
            (setq buffer-undo-list nil))
          (+carlos/magent-buffer-adopt-on-read-buffer-a #'ignore file)
          (should (assoc (buffer-name buf) +carlos/magent-buffer-session))
          (with-current-buffer buf
            (goto-char (point-max))
            (insert "extern\n"))
          (let ((out (myemacs-buffer-result-output
                      (+carlos/magent-tool-buffer-insert " X" (buffer-name buf)))))
            (should (string-match-p "buffer_conflict" out))))
      (kill-buffer buf)
      (delete-file file))))

(ert-deftest myemacs-magent-buffer-fsm-reset-clears-session ()
  "O reset da FSM (cancelamento) libera o contrato de sessão."
  (require 'custom-magent-fsm)
  (setq +carlos/magent-buffer-session (list (cons "*fake*" 42)))
  (+carlos/magent-fsm-reset)
  (should (null +carlos/magent-buffer-session)))

(ert-deftest myemacs-magent-buffer-tools-catalog-registered ()
  "Garante que as tools de buffer vivo estão registradas com permission buffer."
  (skip-unless (require 'gptel nil t))
  (skip-unless (require 'magent-tools nil t))
  (dolist (name '("buffer_insert" "buffer_replace_region" "buffer_undo"
                  "lsp_hover" "describe_elisp_symbol"))
    (let ((entry (magent-tools-catalog-entry name)))
      (should entry)
      (should (eq (plist-get entry :permission) 'buffer)))))

;; ── Fase C: Loop de Auto-Correção (buffer-driver-loop) ──────────────────

(ert-deftest myemacs-magent-buffer-driver-loop-stops-on-zero-errors ()
  "healing-step retorna 'stop quando error-count é zero."
  (let ((+carlos/magent-fsm-healing-attempts 0)
        (+carlos/magent-fsm-healing-last-error-count 5))
    (should (eq (+carlos/magent-fsm-healing-step 0) 'stop))
    (should (= +carlos/magent-fsm-healing-attempts 0))))

(ert-deftest myemacs-magent-buffer-driver-loop-stopping-condition ()
  "healing-step para após 2 tentativas sem progresso consecutivo."
  (let ((+carlos/magent-fsm-healing-attempts 0)
        (+carlos/magent-fsm-healing-last-error-count 5))
    ;; Tentativa 1: sem progresso (erros=3, anterior=5, mas 3<5 → progresso!)
    ;; Na verdade 3 < 5 é progresso → attempts reseta
    ;; Vamos usar cenário onde erros NÃO diminuem
    (let ((+carlos/magent-fsm-healing-last-error-count 3))
      ;; Tentativa 1: erros=3, anterior=3 → sem progresso, attempts=1
      (should (eq (+carlos/magent-fsm-healing-step 3) 'continue))
      (should (= +carlos/magent-fsm-healing-attempts 1))
      ;; Tentativa 2: erros=3, anterior=3 → sem progresso, attempts=2
      (should (eq (+carlos/magent-fsm-healing-step 3) 'continue))
      (should (= +carlos/magent-fsm-healing-attempts 2))
      ;; Tentativa 3: erros=3, anterior=3 → attempts>=2 → stop
      (should (eq (+carlos/magent-fsm-healing-step 3) 'stop))
      (should (= +carlos/magent-fsm-healing-attempts 0)))))

(ert-deftest myemacs-magent-buffer-driver-loop-progress-resets-counter ()
  "healing-step reseta o contador quando erros diminuem."
  (let ((+carlos/magent-fsm-healing-attempts 2)
        (+carlos/magent-fsm-healing-last-error-count 5))
    ;; Progresso: erros caíram de 5 para 1 → reseta counter, continua
    (should (eq (+carlos/magent-fsm-healing-step 1) 'continue))
    (should (= +carlos/magent-fsm-healing-attempts 0))))

(ert-deftest myemacs-magent-buffer-driver-loop-resets-on-fsm-reset ()
  "FSM reset limpa estado do loop de auto-correção."
  (let ((+carlos/magent-fsm-healing-attempts 2)
        (+carlos/magent-fsm-healing-last-error-count 3))
    (+carlos/magent-fsm-reset)
    (should (= +carlos/magent-fsm-healing-attempts 0))
    (should (null +carlos/magent-fsm-healing-last-error-count))))

(ert-deftest myemacs-magent-buffer-driver-loop-directive-present ()
  "Directiva 12 (BUFFER SELF-HEALING) existe nas directives do sistema."
  (should (string-match-p "BUFFER SELF-HEALING" +carlos/magent-system-directives))
  (should (string-match-p "buffer-driver-loop" +carlos/magent-system-directives)))

(provide 'magent-buffer-test)
;;; magent-buffer-test.el ends here
