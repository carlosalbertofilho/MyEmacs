;;; custom-writing.el --- Writing experience (Org + Markdown) -*- lexical-binding: t; -*-

;;; Commentary:
;; Visual improvements for Org-mode and Markdown:
;; - org-modern for both modes (modern styling)
;; - variable-pitch for body text, fixed-pitch for code/tables/tags
;; - ef-themes mixed fonts with hierarchical heading sizes
;; - Full-width buffers (no olivetti centering)
;; - Hide emphasis markers (asterisks, link markup)

;;; Code:

(require 'subr-x)
(require 'cl-lib)

;; Forward declarations for byte-compiler
;; Emacs 30: `defvar' sem INITVALUE NÃO liga a variável — sempre forneça nil.
(defvar markdown-hide-markup nil)
(defvar markdown-hide-urls nil)
(defvar markdown-url-compose-char nil)
(defvar org-tag-faces nil)
(defvar org-todo-keyword-faces nil)
(defvar org-priority-faces nil)
(defvar org-modern-tag-faces nil)
(defvar org-modern-todo-faces nil)
(defvar org-modern-priority-faces nil)
(defvar org-format-latex-options nil)

;; ── Org Modern (estilização moderna para Org e Markdown) ───────────
(use-package org-modern
  :ensure t
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  :init
  ;; Substituir elipse de folding padrão ("...") por seta elegante
  (setq org-modern-fold-stars " ▾")
  :config
  ;; Estrelas de heading como bullets estilizados.
  ;; Nesta versão do org-modern, `org-modern-star' é um símbolo
  ;; ('fold/'replace/nil) e `org-modern-replace-stars' é string/lista de
  ;; strings. Configurar `org-modern-replace-stars' como `t' quebra o
  ;; org-modern-mode com "wrong-type-argument sequencep t", aborta o
  ;; org-mode-hook e impede o variable-pitch-mode de rodar.
  (setq org-modern-star 'replace
        org-modern-replace-stars '("◉" "○" "✸" "✿" "✤" "✜" "◆" "▶")
        ;; Tags como labels com borda
        org-modern-tag-face t
        org-modern-label-border 0.5
        ;; Timestamps estilizados
        org-modern-timestamp t
        ;; Priority com símbolos de texto (compatível com terminal)
        org-modern-priority
        '((?A . "[!A]")   ; was "🔴"
          (?B . "[~B]")   ; was "🟡"
          (?C . "[iC]"))  ; was "🟢"
        ;; Checklist estilizado
        org-modern-checkbox
        '((unordered . "•")
          (ordered   . "✓")
          (transcoded . "✗"))
        ;; Tabelas com estilo moderno
        org-modern-table t
        ;; Progress bars
        org-modern-progress t
        ;; Targets internos estilizados
        org-modern-target t
        ;; Nomes de blocos estilizados
        org-modern-block-name
        '((src . "⟨")
          (example . "⟨")
          (quote . "❝")
          (verse . "❞")
          (center . "◇"))
        ;; Barra lateral elegante nos blocos de código
        org-modern-block-fringe t
        ;; Linha horizontal decorativa
        org-modern-horizontal-line (make-string 40 ?─))

  ;; Fix para checkboxes concluídos ficarem normais
  (setf (alist-get ?X org-modern-checkbox) #("□x" 0 2 (composition ((2)))))

  ;; Gerar pílulas coloridas (:inverse-video t) para tags, priorities e todos
  (cl-flet ((new-spec (spec)
                      (if (or (facep (cdr spec))
                              (not (keywordp (car-safe (cdr spec)))))
                          `(:inherit ,(cdr spec))
                        (cdr spec))))
    (when (boundp 'org-tag-faces)
      (unless org-modern-tag-faces
        (dolist (spec org-tag-faces)
          (add-to-list 'org-modern-tag-faces `(,(car spec) :inverse-video t ,@(new-spec spec))))))
    (when (boundp 'org-todo-keyword-faces)
      (unless org-modern-todo-faces
        (dolist (spec org-todo-keyword-faces)
          (add-to-list 'org-modern-todo-faces `(,(car spec) :inverse-video t ,@(new-spec spec))))))
    (when (boundp 'org-priority-faces)
      (unless org-modern-priority-faces
        (dolist (spec org-priority-faces)
          (add-to-list 'org-modern-priority-faces `(,(car spec) :inverse-video t ,@(new-spec spec))))))))

;; ── Org-appear (esconder/mostrar formatação dinamicamente) ────────
(use-package org-appear
  :ensure t
  :hook (org-mode . org-appear-mode))

;; ── Olivetti (centralização e foco de escrita) ─────────────────────
;; Largura float: prosa = fração da janela, ajusta automaticamente no
;; resize (via window-configuration-change-hook / window-size-change-functions).
(use-package olivetti
  :ensure t
  :hook ((org-mode markdown-mode) . olivetti-mode)
  :custom
  (olivetti-body-width 0.85))

;; ── Fontes Proporcionais (variable-pitch-mode) ─────────────────────
;; Em Emacs 30, `variable-pitch-mode' é um defalias para buffer-face-mode:
;; chamado sem argumento (como hook cru) é um no-op. Envolver em lambda.
(add-hook 'org-mode-hook (lambda () (variable-pitch-mode 1)))
(add-hook 'markdown-mode-hook (lambda () (variable-pitch-mode 1)))

;; Proteger faces para que tabelas, tags e código fiquem monoespaçados.
;; Faces adicionais seguindo as dicas de https://zzamboni.org/post/beautifying-org-mode-in-emacs/.
(with-eval-after-load 'org
  (dolist (face '(org-table org-tag org-code org-block org-block-begin-line org-block-end-line org-date org-todo org-done org-document-info org-document-info-keyword org-meta-line org-checkbox org-property-value org-special-keyword org-verbatim))
    (when (facep face)
      (set-face-attribute face nil :inherit 'fixed-pitch)))
  ;; org-indent: herdar fixed-pitch (junto com org-hide) evita o aumento
  ;; de espaçamento vertical nos blocos em variable-pitch-mode. A face é
  ;; defface em org-indent.el (carregado pelo org-indent-mode), por isso
  ;; o set precisa acontecer após esse load, senão o defface o sobrescreve.
  (with-eval-after-load 'org-indent
    (when (facep 'org-indent)
      (set-face-attribute 'org-indent nil :inherit '(org-hide fixed-pitch))))
  ;; Substituir o bullet "-" de listas por "•" via font-lock
  (font-lock-add-keywords
   'org-mode
   '(("^ *\\([-]\\) "
      (0 (prog1 () (compose-region (match-beginning 1) (match-end 1) "•")))))))

(with-eval-after-load 'markdown-mode
  (dolist (face '(markdown-code-face markdown-inline-code-face markdown-markup-face))
    (when (facep face)
      (set-face-attribute face nil :inherit 'fixed-pitch))))

;; ── Org-mode: ocultar marcadores de ênfase + LaTeX scaling ─────────
(use-package org
  :ensure nil
  :custom
  ;; Ocultar asteriscos de negrito/itálico (mostra apenas o texto)
  (org-hide-emphasis-markers t)
  ;; Indentação visual nos subtítulos
  (org-startup-indented t)
  ;; Imagens inline ao abrir
  (org-startup-with-inline-images t)
  ;; Sem truncamento
  (org-startup-truncated nil)
  :config
  ;; Escala de LaTeX de 1.5x
  (plist-put org-format-latex-options :scale 1.5))

;; ── Zen Reading (Org + Markdown) ───────────────────────────────────
;; Modo de leitura: sem números de linha e com espaçamento confortável.
(defvar +carlos/zen-line-spacing 0.15
  "Line spacing for reading modes (Org/Markdown).")
(dolist (hook '(org-mode-hook markdown-mode-hook))
  (add-hook hook
            (lambda ()
              (display-line-numbers-mode -1)
              (setq-local line-spacing +carlos/zen-line-spacing))))

(provide 'custom-writing)
;;; custom-writing.el ends here
