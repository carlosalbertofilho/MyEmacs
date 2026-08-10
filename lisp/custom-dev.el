;;; custom-dev.el --- Interactive dev loop: IELM + inline eval + ERT runner -*- lexical-binding: t; -*-

;;; Commentary:
;; Ciclo IA → REPL → ERT para Elisp. Avalia expressões inline (C-x C-e, já
;; global), inspeciona estado no IELM, roda testes ERT do buffer com feedback
;; visual (verde/vermelho) e depura backtrace com IA via gptel.
;; Prefixo global: C-c D (Dev).
;; Nota: `C-c C-k' global é EVITADO (org-mode já o usa para
;; `org-kill-note-or-show-branches' — portão `myemacs-kbd-no-collisions').

;;; Code:

(require 'ert)
(require 'ielm)

(declare-function +carlos/gptel-request "custom-ai")
(defvar +carlos/gptel-quick-local-backend)
(defvar +carlos/gptel-quick-local-model)

;; ── ERT runners ─────────────────────────────────────────────────────
(defun +carlos/ert-selector-for-file (file)
  "Retorna o selector ERT para FILE (arquivo de teste `*-test.el')."
  (format "myemacs-%s-"
          (replace-regexp-in-string "-test\\'" ""
                                    (file-name-base file))))

(defun +carlos/ert-test-at-point ()
  "Retorna o nome do teste ERT sob o ponto, ou nil."
  (save-excursion
    (when (search-backward-regexp "(ert-deftest +\\([-[:alnum:]]+\\)" nil t)
      (intern (match-string-no-properties 1)))))

(defun +carlos/ert-run-buffer ()
  "Avalia o buffer atual e roda apenas os testes ERT definidos nele.
Usa um selector ERT baseado no nome do arquivo (tests/<area>-test.el ⇒
selector `myemacs-<area>-'), exibindo o resultado no buffer de resultados
do ERT com cores (passou/falhou)."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless (and file (string-match-p "-test\\.el\\'" file))
      (user-error "Buffer não é um arquivo de teste (*-test.el)"))
    (eval-buffer)
    (ert (+carlos/ert-selector-for-file file))))

(defun +carlos/ert-run-test-at-point ()
  "Roda o teste ERT sob o ponto (dentro de um `ert-deftest')."
  (interactive)
  (let ((test-name (+carlos/ert-test-at-point)))
    (if test-name
        (ert test-name)
      (user-error "Não há `ert-deftest' antes do ponto"))))

;; ── REPL ────────────────────────────────────────────────────────────
(defun +carlos/ielm-open ()
  "Abre o IELM (REPL Elisp)."
  (interactive)
  (ielm))

(defun +carlos/toggle-debug-on-error ()
  "Alterna `debug-on-error' com feedback no minibuffer."
  (interactive)
  (setq debug-on-error (not debug-on-error))
  (message "debug-on-error: %s" (if debug-on-error "ON (backtrace ao errar)" "OFF")))

;; ── Depuração com IA (gptel) ────────────────────────────────────────
(defun +carlos/debug-region-with-ai ()
  "Envia o backtrace/região selecionada + código ao gptel para diagnóstico.
O prompt pede explicação do estado de memória/escopo que causou o erro e a
correção, seguindo o fluxo de depuração pós-erro do REPL."
  (interactive)
  (let* ((beg (if (region-active-p) (region-beginning) (point-min)))
         (end (if (region-active-p) (region-end) (point-max)))
         (text (buffer-substring-no-properties beg end)))
    (when (require 'custom-ai nil t)
      (+carlos/gptel-request
       (format "O REPL do Emacs estourou este erro/backtrace ao rodar meu teste Elisp. Explique o estado de memória/escopo que causou e dê a correção:\n\n%s" text)
       +carlos/gptel-quick-local-backend
       +carlos/gptel-quick-local-model
       :buffer "*gptel-debug*"
       :callback (lambda (response _info)
                   (when response
                     (with-current-buffer (get-buffer-create "*debug-ai*")
                       (goto-char (point-max))
                       (insert response "\n"))))))))

;; ── Keybindings ─────────────────────────────────────────────────────
(global-set-key (kbd "C-c D r") #'+carlos/ielm-open)            ; REPL dedicado
(global-set-key (kbd "C-c D t") #'+carlos/ert-run-buffer)       ; roda testes do buffer
(global-set-key (kbd "C-c D T") #'+carlos/ert-run-test-at-point); teste sob o ponto
(global-set-key (kbd "C-c D d") #'+carlos/toggle-debug-on-error); debug-on-error
(global-set-key (kbd "C-c D a") #'+carlos/debug-region-with-ai) ; depura com IA

;; Binds locais do emacs-lisp-mode (sem poluir o global)
(with-eval-after-load 'lisp-mode
  (define-key emacs-lisp-mode-map (kbd "C-c C-c") #'+carlos/ert-run-buffer)
  (define-key emacs-lisp-mode-map (kbd "C-c C-t") #'+carlos/ert-run-test-at-point))

(provide 'custom-dev)
;;; custom-dev.el ends here
