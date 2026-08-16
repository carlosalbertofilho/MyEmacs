;;; custom-org.el --- Org mode and literate programming -*- lexical-binding: t; -*-

;;; Commentary:
;; org-mode, org-babel (python, shell, emacs-lisp, mermaid, gptel),
;; emacs-jupyter, pdf-tools (opcional), LaTeX preview, org-fragtog.

;;; Code:

;; ── ob-mermaid ──────────────────────────────────────────────────────
(use-package ob-mermaid
  :ensure t
  :after org
  :config
  (setq ob-mermaid-cli-path "mmdc")
  ;; Registrar a linguagem mermaid dinamicamente após o carregamento
  (add-to-list 'org-babel-load-languages '(mermaid . t))
  (org-babel-do-load-languages 'org-babel-load-languages org-babel-load-languages))

;; ── org-mode ────────────────────────────────────────────────────────
(use-package org
  :ensure nil
  :config
  (setq org-directory "~/org"
        org-confirm-babel-evaluate nil
        org-startup-indented t
        org-startup-with-inline-images t
        org-startup-with-latex-preview (and (executable-find "latex")
                                            (executable-find "dvipng"))
        ;; Preview LaTeX fragments on open only when the toolchain exists
        ;; (guarda evita "File mode specification error" quando latex/dvipng
        ;; nao estao instalados)
        org-hide-emphasis-markers t
        org-edit-src-content-indentation 2)
  ;; LaTeX fragment rendering scale
  (setq org-format-latex-options
        (plist-put org-format-latex-options :scale 1.5))
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((python . t)
     (shell . t)
     (emacs-lisp . t)))
  :bind
  (("C-c a" . org-agenda)))

;; ── org-table fit-to-window (AutoFit à janela) ─────────────────────
;; O org-table não tem `org-table-fit-window' (verificado no fonte
;; org-table.el do Emacs 30). Este comando emula o "AutoFit to Window"
;; do Word: faz word-wrap das colunas mais largas (sem quebrar palavras)
;; até a tabela caber na largura da janela.
(when (require 'org-table nil t)

  (defun +carlos/org-table--continuation-p (col ncols)
    "Non-nil when the current data line is a continuation of column COL.
A continuation line only has content in column COL (empty everywhere
else), as produced when a wrapped cell spans multiple table lines."
    (and (not (string-blank-p (org-table-get-field col)))
         (cl-loop for k from 1 to ncols
                  unless (= k col)
                  always (string-blank-p (org-table-get-field k)))))

  (defun +carlos/org-table--cell-wrapped-p (col ncols)
    "Non-nil when the cell at point in column COL is part of a wrapped cell.
Detects both continuation lines and the head of a multi-line cell, so
re-running the fit command never rewraps an already wrapped cell."
    (or (+carlos/org-table--continuation-p col ncols)
        (save-excursion
          (let ((dline (org-table-current-line)))
            (and (org-table-goto-line (1+ dline))
                 (+carlos/org-table--continuation-p col ncols))))))

  (defun +carlos/org-table--insert-row-below (dline n)
    "Insert N clean data rows below data line DLINE of the table at point.
Preserves `#' and `$' first-column markers, if any, so formulas keep
working after the insertion."
    (org-table-goto-line dline)
    (let* ((line (buffer-substring (line-beginning-position)
                                   (line-end-position)))
           (new (org-table-clean-line line)))
      (when (string-match "^[ \t]*| *[#$] *|" line)
        (setq new (replace-match (match-string 0 line) t t new)))
      (goto-char (line-beginning-position))
      (forward-line 1)
      (let (org-table-may-need-update)
        (insert-before-markers
         (apply #'concat (make-list n (concat new "\n")))))))

  (defun +carlos/org-table--wrap-column (col width ncols)
    "Word-wrap every cell of column COL (1-based) of the table at point.
Cells are wrapped to WIDTH characters; words are never split (org-wrap
semantics).  Empty cells and cells that are already wrapped are left
untouched.  Return the number of cells that were wrapped."
    (let ((dline 1)
          (changed 0)
          (more t))
      (while (and more (org-table-goto-line dline))
        (goto-char (line-beginning-position))
        (org-table-goto-column col nil 'force)
        (let ((cell (org-table-get-field)))
          (if (or (string-blank-p cell)
                  (+carlos/org-table--cell-wrapped-p col ncols))
              (setq dline (1+ dline))
            (let* ((wrapped (org-wrap cell width nil))
                   (n (length wrapped)))
              (if (= n 1)
                  (setq dline (1+ dline))
                (org-table-goto-column col nil 'force)
                (skip-chars-backward "^|\n")
                (org-table-copy-region (point) (point) 'cut)
                (setq org-table-clip (mapcar (lambda (l) (list l)) wrapped))
                (+carlos/org-table--insert-row-below dline (1- n))
                (org-table-goto-line dline)
                (goto-char (line-beginning-position))
                (org-table-goto-column col nil 'force)
                (skip-chars-backward "^|\n")
                (org-table-paste-rectangle)
                (setq changed (1+ changed)
                      dline (+ dline n)))))))
      changed))

  (defun +carlos/org-table--measure ()
    "Measure the org table at point.
Return the list (NCOLS WIDTHS TABLE-WIDTH) where NCOLS is the number
of columns, WIDTHS the maximum display width per column and
TABLE-WIDTH the display width of the widest table line (separators
included).  The caller must ensure point is on a table line."
    (save-excursion
      (let* ((begin (org-table-begin))
             (end (org-table-end))
             (first-line (buffer-substring-no-properties
                          (line-beginning-position)
                          (line-end-position)))
             (ncols (- (cl-count-if (lambda (c) (memq c '(?| ?+)))
                                    first-line)
                       1))
             (widths (make-list ncols 0))
             (table-width 0))
        (goto-char begin)
        (while (< (point) end)
          (when (org-at-table-p)
            (setq table-width
                  (max table-width
                       (string-width
                        (buffer-substring-no-properties
                         (line-beginning-position)
                         (line-end-position)))))
            (unless (org-at-table-hline-p)
              (cl-loop for k from 1 to ncols do
                       (let ((w (string-width
                                 (string-trim (org-table-get-field k)))))
                         (when (> w (nth (1- k) widths))
                           (setf (nth (1- k) widths) w))))))
          (forward-line))
        (list ncols widths table-width))))

  (defun +carlos/org-table-fit-window ()
    "Fit the org table at point to the window width.

Word-wraps the widest columns (from widest to narrowest) until the
table no longer exceeds the window text width, mimicking Word's
AutoFit-to-window for org tables.  Empty cells, cells that are already
wrapped, and single words longer than the target width are left
untouched; words are never split.  Point is preserved.

No-op with a status message when the table already fits.  When the
table still overflows after wrapping (long words or minimum column
width), a message suggests narrowing the window manually."
    (interactive)
    (unless (org-at-table-p)
      (user-error "Not at a table"))
    (org-table-align)
    (let* ((point-before (point))
           (available (window-text-width))
           (min-width 3)
           (measure (+carlos/org-table--measure))
           (ncols (nth 0 measure))
           (widths (nth 1 measure))
           (table-width (nth 2 measure))
           (excess (- table-width available))
           (target-widths (copy-sequence widths))
           (order (cl-loop for c below ncols collect c))
           (changed 0))
      (if (<= excess 0)
          (message "Table already fits (%d chars; window %d)"
                   table-width available)
        (setq order
              (sort order (lambda (a b) (> (nth a widths) (nth b widths)))))
        (dolist (c order)
          (when (> excess 0)
            (let ((reduction (min excess (- (nth c widths) min-width))))
              (when (> reduction 0)
                (setf (nth c target-widths) (- (nth c target-widths) reduction))
                (setq excess (- excess reduction))))))
        (cl-loop for c below ncols
                 when (< (nth c target-widths) (nth c widths))
                 do (setq changed
                          (+ changed (+carlos/org-table--wrap-column
                                      (1+ c) (nth c target-widths) ncols))))
        (org-table-align)
        (goto-char (min point-before (point-max)))
        (let ((final (+carlos/org-table--measure)))
          (if (<= (nth 2 final) available)
              (message "Table fitted: %d cells wrapped to %d chars wide"
                       changed (nth 2 final))
            (message (concat "Table reduced but still %d chars wide "
                             "(long words or min width); window is %d")
                     (nth 2 final) available)))))))

;; ── org-fragtog: auto-render LaTeX when cursor leaves ───────────────
(use-package org-fragtog
  :ensure t
  :hook (org-mode . org-fragtog-mode))

;; ── emacs-jupyter ───────────────────────────────────────────────────
;; Repo: https://github.com/jupyter/emacs-jupyter
;; Kernels provided by Python env (pip/nix).
;; `ob-jupyter' não é autoloaded e não require org — precisa dos dois
;; para definir `org-babel-execute:jupyter' e `org-babel-load-languages'.
(use-package jupyter
  :ensure t
  :catch t
  :config
  (require 'org)
  (when (require 'ob-jupyter nil t)
    (add-to-list 'org-babel-load-languages '(jupyter . t))))

;; ── pdf-tools ───────────────────────────────────────────────────────
;; macOS: o configure nao detecta `getline' (ac_cv_func_getline=no) e o
;; gcc do Nix nao enxerga o SDK, entao `pdf-tools-install' nao consegue
;; rebuildar. Em vez de compilar a mao, o MyMachine (Nix) provê o binario
;; `epdfinfo' (mesmo commit do elpaca, patch de getline do nixpkgs) no PATH
;; via home.packages. Aqui priorizamos `executable-find "epdfinfo"' e
;; deixamos o fallback manual (build/server/epdfinfo) para ambientes sem Nix.
(use-package pdf-tools
  :ensure t
  :config
  (let ((bin (or (executable-find "epdfinfo")
                 (expand-file-name "build/server/epdfinfo" pdf-tools-directory))))
    (when (and bin (file-executable-p bin))
      (setq pdf-info-epdfinfo-program bin)))
  (unless noninteractive
    (pdf-tools-install :no-query))
  (setq pdf-view-display-size 'fit-width)
  ;; Dark mode: invert PDF colors to match dark ef-themes
  (add-hook 'pdf-view-mode-hook #'pdf-view-midnight-minor-mode))

;; Fallback: DocView (built-in) apenas se pdf-tools nao estiver disponivel
(unless (featurep 'pdf-view)
  (use-package doc-view
    :ensure nil
    :config
    (setq doc-view-resolution 300)))

;; ── nov: leitura de EPUB (dependência opcional do org-noter) ──────
(use-package nov
  :ensure t
  :mode "\\.epub\\'")

;; ── djvu: leitura/edição de DjVu (dependência opcional do org-noter) ─
;; Binários DjVuLibre (djvused/ddjvu/djvm/djview) providos pelo Nix do
;; MyMachine (home/carlosfilho/emacs.nix).
(use-package djvu
  :ensure t)

;; ── org-noter (opcional, leitura de PDF com notas) ─────────────────
(use-package org-noter
  :ensure t
  :after org
  :custom
  (org-noter-supported-modes '(doc-view-mode pdf-view-mode nov-mode djvu-read-mode))
  :config
  (setq org-noter-notes-search-path '("~/org/notes")))

(provide 'custom-org)
;;; custom-org.el ends here
