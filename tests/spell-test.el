;;; spell-test.el --- jinx + grammar AI regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifica o módulo custom-jinx.el: jinx carregado com pt_BR + en_US,
;; hooks text-mode/prog-mode registrados, binds M-$/C-M-$ ativos, comando
;; +carlos/grammar-correct-region disponível, extração JSON da resposta e
;; isenção do buffer de gramática no roteador dinâmico.
;; Guard por skip-unless quando jinx não carrega (builds parciais do repo).

;;; Code:

(require 'ert)

(defvar myemacs-spell-jinx-available
  (condition-case nil (progn (require 'jinx nil t) (featurep 'jinx))
    (error nil))
  "Non-nil quando `jinx' carrega neste ambiente.")

(ert-deftest myemacs-spell-jinx-commands ()
  (skip-unless myemacs-spell-jinx-available)
  (should (fboundp 'jinx-correct))
  (should (fboundp 'jinx-languages))
  (should (boundp 'jinx-mode-map)))

(ert-deftest myemacs-spell-jinx-languages-ptbr-enus ()
  (skip-unless myemacs-spell-jinx-available)
  (should (string-match-p "pt_BR" jinx-languages))
  (should (string-match-p "en_US" jinx-languages)))

(ert-deftest myemacs-spell-jinx-hooks ()
  "O guard `+carlos/jinx-mode-if-available' está registrado nos hooks
em vez de `jinx-mode' direto (proteção para builds sem o módulo nativo)."
  (skip-unless (fboundp '+carlos/jinx-mode-if-available))
  (should (memq '+carlos/jinx-mode-if-available text-mode-hook))
  (should (memq '+carlos/jinx-mode-if-available prog-mode-hook)))

(ert-deftest myemacs-spell-jinx-guard-when-unavailable ()
  "O guard deve retornar nil sem erro quando `jinx-mode' está indisponível
ou sinaliza erro — hooks de text/prog-mode não podem quebrar."
  (skip-unless (fboundp '+carlos/jinx-mode-if-available))
  (let ((orig (when (fboundp 'jinx-mode) (symbol-function 'jinx-mode))))
    (unwind-protect
        (progn
          (fmakunbound 'jinx-mode)
          (should-not (+carlos/jinx-mode-if-available))
          (defalias 'jinx-mode (lambda (&optional _arg)
                                 (error "native module missing")))
          (should-not (+carlos/jinx-mode-if-available)))
      (if orig
          (fset 'jinx-mode orig)
        (fmakunbound 'jinx-mode)))))

(ert-deftest myemacs-spell-jinx-mode-map-binds ()
  (skip-unless myemacs-spell-jinx-available)
  (should (eq (lookup-key jinx-mode-map (kbd "M-$")) #'jinx-correct))
  (should (eq (lookup-key jinx-mode-map (kbd "C-M-$")) #'jinx-languages)))

(ert-deftest myemacs-spell-jinx-module ()
  "Verifica o carregamento do custom-jinx sem ativar o minor-mode
(ativar compila o módulo C via pkg-config; em batch isso fica caro)."
  (skip-unless myemacs-spell-jinx-available)
  (should (fboundp '+carlos/grammar-correct-region))
  (should (eq (key-binding (kbd "C-c c g")) #'+carlos/grammar-correct-region)))

(ert-deftest myemacs-spell-grammar-vars ()
  "Backend/modelo de grammar usam o Gemini free tier (nuvem) por padrão
desde que o agente local virou impraticável em CPU (I2/2026-08-10)."
  (skip-unless (and myemacs-spell-jinx-available (boundp '+carlos/gptel-grammar-model)))
  (should (boundp '+carlos/gptel-grammar-backend))
  (should (boundp '+carlos/gptel-grammar-model))
  (should (string= +carlos/gptel-grammar-backend "Gemini"))
  (should (eq +carlos/gptel-grammar-model 'gemini-3.5-flash)))

(ert-deftest myemacs-spell-grammar-json-extraction ()
  (skip-unless (fboundp '+carlos/--grammar-extract-corrected))
  (should (string= (+carlos/--grammar-extract-corrected
                    "{\"corrected\": \"texto corrigido\"}")
                   "texto corrigido"))
  (should (string= (+carlos/--grammar-extract-corrected "texto puro")
                   "texto puro")))

(ert-deftest myemacs-spell-router-ignores-grammar-buffer ()
  (skip-unless (fboundp '+carlos/magent-managed-request-p))
  (with-temp-buffer
    (rename-buffer "*gptel-grammar*")
    (should (+carlos/magent-managed-request-p (current-buffer) nil))))

(ert-deftest myemacs-spell-grammar-schema-passthrough ()
  "`+carlos/gptel-request' deve repassar :schema a `gptel-request'.
Reproduz o bug do keyword `:response_format' (não aceito pelo &key de
`gptel-request' 0.9.9.5): o fake abaixo é um cl-defun com o mesmo &key —
um `:response_format' reintroduzido faria `apply' sinalizar erro, falhando."
  (skip-unless (and (fboundp '+carlos/gptel-request)
                    (fboundp 'gptel-get-backend)))
  (let ((captured nil)
        (orig (symbol-function 'gptel-request)))
    (unwind-protect
        (progn
          (cl-defun gptel-request
              (&optional _prompt &key callback buffer position context
                         dry-run stream in-place system schema transforms fsm)
            (ignore callback buffer position context dry-run stream
                   in-place system transforms fsm)
            (setq captured schema))
          (+carlos/gptel-request "teste" +carlos/gptel-grammar-backend
                                 +carlos/gptel-grammar-model
                                 :buffer "*gptel-grammar-test*"
                                 :schema '(:type object
                                           :properties (:corrected (:type string))))
          (should (listp captured))
          (should (memq :corrected (plist-get captured :properties))))
      (fset 'gptel-request orig))))

(provide 'spell-test)
;;; spell-test.el ends here
