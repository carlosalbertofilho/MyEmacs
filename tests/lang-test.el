;;; lang-test.el --- ERT tests for Nix and language setups -*- lexical-binding: t; -*-

;;; Commentary:
;; Testes unitários do módulo custom-lang.el (Nix, Eglot, Envrc, Apheleia, Rebuild).

;;; Code:

(require 'ert)

(ert-deftest myemacs-lang-nix-mode-hook ()
  "Valida se nix-mode-hook possui eglot-ensure configurado."
  (require 'custom-lang)
  (should (memq 'eglot-ensure (default-value 'nix-mode-hook))))

(ert-deftest myemacs-lang-envrc-global-mode ()
  "Valida se envrc-global-mode esta ativado ou disponivel."
  (require 'custom-lang)
  (should (fboundp 'envrc-global-mode)))

(ert-deftest myemacs-lang-eglot-nixd-configured ()
  "Valida se nix-mode possui nixd configurado em eglot-server-programs."
  (require 'custom-lang)
  (require 'eglot nil t)
  (when (boundp 'eglot-server-programs)
    (should (assoc 'nix-mode eglot-server-programs))))

(ert-deftest myemacs-lang-apheleia-nixfmt-configured ()
  "Valida se nix-mode possui nixfmt configurado em apheleia-mode-alist."
  (require 'custom-lang)
  (require 'apheleia nil t)
  (when (boundp 'apheleia-mode-alist)
    (should (assoc 'nix-mode apheleia-mode-alist))))

(ert-deftest myemacs-lang-nixos-rebuild-command-exists ()
  "Valida se a funcao +carlos/nixos-rebuild-switch existe."
  (require 'custom-lang)
  (should (fboundp '+carlos/nixos-rebuild-switch)))

(ert-deftest myemacs-lang-nixos-rebuild-keybinding ()
  "Valida se C-c N r esta associado a +carlos/nixos-rebuild-switch."
  (require 'custom-keybindings)
  (should (equal (key-binding (kbd "C-c N r")) #'+carlos/nixos-rebuild-switch)))

(provide 'lang-test)
;;; lang-test.el ends here
