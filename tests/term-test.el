;;; term-test.el --- Terminal (vterm/eshell) regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Garante que os keymaps de eshell/vterm não foram clobbered pelo gotcha
;; do Emacs 30 (`(defvar X nil)` sobrescreve o keymap não-nil carregado).
;; Bug real: `eshell-mode-map' ficava nil e os binds C-c A a/o sumiam.
;;
;; Os testes do vterm dependem do módulo nativo compilado (vterm-module).
;; Sem ele (ex.: repo sem `just install`/make), os testes são pulados.

;;; Code:

(require 'ert)
(require 'esh-mode)

(defvar myemacs-term-vterm-available nil
  "Non-nil quando o vterm (com módulo nativo) carrega neste ambiente.")

(condition-case nil
    (progn
      (require 'vterm)
      (setq myemacs-term-vterm-available t))
  (error (setq myemacs-term-vterm-available nil)))

(ert-deftest myemacs-term-eshell-map-keymapp ()
  (should (keymapp eshell-mode-map)))

(ert-deftest myemacs-term-eshell-agy-bind ()
  (should (eq (lookup-key eshell-mode-map (kbd "C-c A a"))
              '+carlos/eshell-run-agy)))

(ert-deftest myemacs-term-eshell-opencode-bind ()
  (should (eq (lookup-key eshell-mode-map (kbd "C-c A o"))
              '+carlos/eshell-run-opencode)))

(ert-deftest myemacs-term-eshell-ai-aliases ()
  (should (fboundp '+carlos/eshell-ai-aliases)))

(ert-deftest myemacs-term-vterm-module-and-binds ()
  (skip-unless myemacs-term-vterm-available)
  (should (keymapp vterm-mode-map))
  (should (eq (lookup-key vterm-mode-map (kbd "C-c C-e"))
              '+carlos/vterm-write-multiline-prompt)))

(provide 'term-test)
;;; term-test.el ends here
