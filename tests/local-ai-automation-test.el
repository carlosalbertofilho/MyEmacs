;;; local-ai-automation-test.el --- Local AI automation regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Testes ERT para a Seção 0.9 (Ollama CPU Pipeline):
;; - Comandos +carlos/generate-docstring-at-point e +carlos/generate-test-at-point
;; - Atalhos de teclado C-c c d e C-c c t
;; - Presença e integridade dos scripts bin/rag-convert e bin/log-triage
;; - Presença das skills local-AI (.magent/skills/rag-converter, test-triage)

;;; Code:

(require 'ert)
(require 'custom-lang)
(require 'custom-git)

(defun myemacs-local-ai--root ()
  "Retorna a raiz do projeto ou user-emacs-directory."
  (if-let* ((proj (project-current))
            (root (project-root proj)))
      root
    user-emacs-directory))

(ert-deftest myemacs-local-ai-commands-exist ()
  "Verifica se os comandos de geração local de docstring e teste existem."
  :tags '(ai)
  (require 'custom-lang)
  (should (fboundp '+carlos/generate-docstring-at-point))
  (should (fboundp '+carlos/generate-test-at-point))
  (should (commandp '+carlos/generate-docstring-at-point))
  (should (commandp '+carlos/generate-test-at-point)))

(ert-deftest myemacs-local-ai-keybindings ()
  "Verifica se C-c c d e C-c c t estão associados às funções corretas."
  :tags '(ai)
  (require 'custom-lang)
  (should (eq (key-binding (kbd "C-c c d")) #'+carlos/generate-docstring-at-point))
  (should (eq (key-binding (kbd "C-c c t")) #'+carlos/generate-test-at-point)))

(ert-deftest myemacs-local-ai-scripts-exist ()
  "Verifica se os scripts utilitários bin/rag-convert e bin/log-triage existem."
  :tags '(ai)
  (let ((root (myemacs-local-ai--root)))
    (should (file-exists-p (expand-file-name "bin/rag-convert" root)))
    (should (file-exists-p (expand-file-name "bin/log-triage" root)))))

(ert-deftest myemacs-local-ai-skills-exist ()
  "Verifica se as skills .magent/skills/rag-converter e test-triage existem."
  :tags '(ai)
  (let ((root (myemacs-local-ai--root)))
    (should (file-exists-p (expand-file-name ".magent/skills/rag-converter/SKILL.md" root)))
    (should (file-exists-p (expand-file-name ".magent/skills/test-triage/SKILL.md" root)))))

(provide 'local-ai-automation-test)
;;; local-ai-automation-test.el ends here
