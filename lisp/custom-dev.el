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

(use-package dape :ensure t)

(declare-function +carlos/gptel-request "custom-ai")
(defvar +carlos/gptel-quick-local-backend)
(defvar +carlos/gptel-quick-local-model)

;; ── Prompts centralizados para dev ──────────────────────────────────
(defconst +carlos/elisp-ert-prompt
  "Você é um especialista em Emacs Lisp e testes ERT. Gere uma suíte de testes ERT (`ert-deftest`) completa para a seguinte função/código Elisp.
Regras obrigatórias:
1. Nomeie os testes como `myemacs-<area>-<desc>` (ex.: `myemacs-dev-exemplo`).
2. Inclua casos de sucesso (`should`) e casos de erro/borda (`should-error`).
3. Use `cl-letf` para mocks quando necessário.
4. Retorne APENAS o código Elisp puro executável, sem marcação de markdown extra.

Código para testar:\n\n%s"
  "Prompt centralizado para geração de testes ERT via IA.")

(defconst +carlos/elisp-debug-prompt
  "O REPL do Emacs estourou este erro/backtrace ao rodar um teste Elisp. Explique o estado de memória/escopo que causou o erro e apresente a correção direta:\n\n%s"
  "Prompt centralizado para depuração de erros Elisp via IA.")

;; ── ERT runners & IA generator ──────────────────────────────────────
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

(defun +carlos/ert-generate-tests ()
  "Gera testes ERT via IA (gptel) para a região ou defun sob o ponto.
O resultado é exibido no buffer `*gptel-tests*' para revisão antes de
avaliação ou salvamento."
  (interactive)
  (let* ((beg (if (region-active-p) (region-beginning)
                (save-excursion (beginning-of-defun) (point))))
         (end (if (region-active-p) (region-end)
                (save-excursion (end-of-defun) (point))))
         (text (buffer-substring-no-properties beg end)))
    (when (string-empty-p (string-trim text))
      (user-error "Nenhum código Elisp selecionado para gerar testes"))
    (message "Gerando testes ERT via IA...")
    (when (require 'custom-ai nil t)
      (+carlos/gptel-request
       (format +carlos/elisp-ert-prompt text)
       +carlos/gptel-quick-local-backend
       +carlos/gptel-quick-local-model
       :buffer "*gptel-tests*"
       :callback (lambda (response _info)
                   (when response
                     (with-current-buffer (get-buffer-create "*gptel-tests*")
                       (emacs-lisp-mode)
                       (goto-char (point-max))
                       (insert "\n;; ── Testes gerados via IA ──────────────────────────────\n"
                               response "\n")
                       (display-buffer (current-buffer)))
                     (message "Testes ERT gerados no buffer *gptel-tests*")))))))

;; ── REPL & Scratch Helpers ──────────────────────────────────────────
(defun +carlos/ielm-open ()
  "Abre o IELM (REPL Elisp)."
  (interactive)
  (ielm))

(defun +carlos/insert-repl-block ()
  "Insere ou envolve a região/expressão em um bloco `(when nil ...)`.
Usado para teste manual inline com `C-x C-e' no REPL sem efeito colateral
no carregamento."
  (interactive)
  (if (region-active-p)
      (let ((beg (region-beginning))
            (end (region-end)))
        (goto-char end)
        (insert "\n)")
        (goto-char beg)
        (insert "(when nil ;; REPL scratch\n  ")
        (indent-region beg (point-max)))
    (insert "(when nil ;; REPL scratch\n  )\n")
    (forward-line -1)
    (end-of-line)))

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
       (format +carlos/elisp-debug-prompt text)
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
(global-set-key (kbd "C-c D e") #'+carlos/ert-generate-tests)   ; gera testes ERT via IA
(global-set-key (kbd "C-c D b") #'+carlos/insert-repl-block)    ; insere bloco (when nil ...)
(global-set-key (kbd "C-c D d") #'+carlos/toggle-debug-on-error); debug-on-error
(global-set-key (kbd "C-c D a") #'+carlos/debug-region-with-ai) ; depura com IA

;; Binds locais do emacs-lisp-mode (sem poluir o global)
(with-eval-after-load 'lisp-mode
  (define-key emacs-lisp-mode-map (kbd "C-c C-c") #'+carlos/ert-run-buffer)
  (define-key emacs-lisp-mode-map (kbd "C-c C-t") #'+carlos/ert-run-test-at-point)
  (define-key emacs-lisp-mode-map (kbd "C-c C-e") #'+carlos/ert-generate-tests)
  (define-key emacs-lisp-mode-map (kbd "C-c C-b") #'+carlos/insert-repl-block))

(provide 'custom-dev)
;;; custom-dev.el ends here
