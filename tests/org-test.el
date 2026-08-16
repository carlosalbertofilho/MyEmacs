;;; org-test.el --- Org/org-modern regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifica as estilizações do org-modern que já quebraram (ex. setar
;; `org-modern-replace-stars' como t aborta o org-mode-hook com
;; wrong-type-argument sequencep t).

;;; Code:

(require 'ert)
(require 'org)
(require 'org-modern)

(ert-deftest myemacs-org-modern-star-symbol ()
  (should (eq org-modern-star 'replace)))

(ert-deftest myemacs-org-modern-replace-stars-list ()
  (should (listp org-modern-replace-stars))
  (should (>= (length org-modern-replace-stars) 5)))

(ert-deftest myemacs-org-babel-languages ()
  (should (assq 'python org-babel-load-languages))
  (should (assq 'shell org-babel-load-languages)))

(ert-deftest myemacs-org-hide-emphasis ()
  (should (bound-and-true-p org-hide-emphasis-markers)))

(ert-deftest myemacs-org-agenda-keybinding ()
  (should (eq (key-binding (kbd "C-c a")) 'org-agenda)))

(ert-deftest myemacs-org-nov-installed ()
  "nov (leitor de EPUB) instalado e visível no load-path."
  (should (or (featurep 'nov) (locate-library "nov"))))

(ert-deftest myemacs-org-djvu-installed ()
  "djvu (DJVU) instalado e visível no load-path."
  (should (or (featurep 'djvu) (locate-library "djvu"))))

(ert-deftest myemacs-org-noter-supported-modes-full ()
  "org-noter suporta PDF, doc-view, nov (EPUB) e djvu sem warnings."
  (require 'org-noter nil t)
  (should (memq 'nov-mode org-noter-supported-modes))
  (should (memq 'djvu-read-mode org-noter-supported-modes)))

(ert-deftest myemacs-org-noter-no-missing-module-warnings ()
  "Boot sem warnings de módulos ausentes do org-noter (nov/djvu)."
  (with-current-buffer "*Messages*"
    (save-excursion
      (goto-char (point-min))
      (should-not (re-search-forward "package not found\\|needs the package" nil t)))))

(ert-deftest myemacs-org-latex-preview-guarded-by-toolchain ()
  "org-startup-with-latex-preview so fica t quando latex/dvipng existem.
Regressao: a config era `t' incondicional, causando \"File mode
specification error\" ao abrir .org quando o toolchain LaTeX nao esta
instalado (org-mode tentava criar previews de fragmentos no startup)."
  (should (eq org-startup-with-latex-preview
              (and (executable-find "latex") (executable-find "dvipng")))))

(ert-deftest myemacs-org-open-with-latex-fragment-no-error ()
  "Abrir buffer org com fragmento LaTeX nao levanta erro no org-mode.
Quando o toolchain LaTeX esta ausente, o startup nao tenta criar previews."
  (skip-unless (not (and (executable-find "latex") (executable-find "dvipng"))))
  (let ((buf (get-buffer-create " *org-latex-preview-guard*")))
    (unwind-protect
        (with-current-buffer buf
          (erase-buffer)
          (insert "* Heading\n\nA formula $x^2 + y^2$ here.\n")
          (should-not (condition-case _e
                          (progn (org-mode) nil)
                        (error (list 'erro _e)))))
      (kill-buffer buf))))

(ert-deftest myemacs-org-table-fit-window ()
  "org-table-fit-window emula AutoFit-to-window: reduz a tabela larga
para caber na largura da janela, preservando todas as palavras."
  (skip-unless (fboundp '+carlos/org-table-fit-window))
  (let ((buf (get-buffer-create " *org-table-fit*"))
        (window-width 25)
        words-before words-after)
    (unwind-protect
        (with-current-buffer buf
          (erase-buffer)
          (insert "| N | Description | X |\n"
                  "| 1 | alpha beta gamma delta epsilon | a |\n"
                  "| 2 | zeta eta theta | b |\n")
          (org-mode)
          (org-table-align)
          (setq words-before
                (sort (split-string (buffer-substring-no-properties
                                     (point-min) (point-max))
                                    "[| \t\n+]+" t)
                      #'string<))
          (goto-char (point-min))
          (cl-letf (((symbol-function 'window-text-width)
                     (lambda (&optional _win) window-width)))
            (+carlos/org-table-fit-window))
          (let ((final (+carlos/org-table--measure)))
            (should (<= (nth 2 final) window-width)))
          (setq words-after
                (sort (split-string (buffer-substring-no-properties
                                     (point-min) (point-max))
                                    "[| \t\n+]+" t)
                      #'string<))
          (should (equal words-before words-after)))
      (kill-buffer buf))))

(ert-deftest myemacs-org-table-fit-window-idempotent ()
  "Rodar fit-window de novo nao modifica a tabela ja ajustada."
  (skip-unless (fboundp '+carlos/org-table-fit-window))
  (let ((buf (get-buffer-create " *org-table-fit-idem*"))
        (window-width 25))
    (unwind-protect
        (with-current-buffer buf
          (erase-buffer)
          (insert "| N | Description | X |\n"
                  "| 1 | alpha beta gamma delta epsilon | a |\n"
                  "| 2 | zeta eta theta | b |\n")
          (org-mode)
          (org-table-align)
          (goto-char (point-min))
          (cl-letf (((symbol-function 'window-text-width)
                     (lambda (&optional _win) window-width)))
            (+carlos/org-table-fit-window))
          (let ((after-first (buffer-string)))
            (cl-letf (((symbol-function 'window-text-width)
                       (lambda (&optional _win) window-width)))
              (+carlos/org-table-fit-window))
            (should (equal after-first (buffer-string)))))
      (kill-buffer buf))))

(ert-deftest myemacs-org-table-fit-window-no-op-when-fits ()
  "Tabela menor que a janela nao e modificada pelo comando."
  (skip-unless (fboundp '+carlos/org-table-fit-window))
  (let ((buf (get-buffer-create " *org-table-fit-noop*")))
    (unwind-protect
        (with-current-buffer buf
          (erase-buffer)
          (insert "| N | Description | X |\n"
                  "| 1 | alpha | a |\n")
          (org-mode)
          (org-table-align)
          (let ((baseline (buffer-string)))
            (goto-char (point-min))
            (cl-letf (((symbol-function 'window-text-width)
                       (lambda (&optional _win) 80)))
              (+carlos/org-table-fit-window))
            (should (equal baseline (buffer-string)))))
      (kill-buffer buf))))

(provide 'org-test)
;;; org-test.el ends here
