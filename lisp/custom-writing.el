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
(defvar markdown-hide-markup)
(defvar markdown-hide-urls)
(defvar markdown-url-compose-char)
(defvar org-tag-faces)
(defvar org-todo-keyword-faces)
(defvar org-priority-faces)
(defvar org-modern-tag-faces)
(defvar org-modern-todo-faces)
(defvar org-modern-priority-faces)
(defvar org-format-latex-options)

;; ── Org Modern (estilização moderna para Org e Markdown) ───────────
(use-package org-modern
  :ensure t
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda))
  :init
  ;; Substituir elipse de folding padrão ("...") por seta elegante
  (setq org-modern-fold-stars " ▾")
  :config
  ;; Estrelas de heading como bullets estilizados
  (setq org-modern-star '("◉" "○" "✸" "✿" "✤" "✜" "◆" "▶")
        org-modern-replace-stars t
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
(use-package olivetti
  :ensure t
  :hook ((org-mode markdown-mode) . olivetti-mode)
  :config
  (setq olivetti-body-width 100))

;; ── Fontes Proporcionais (variable-pitch-mode) ─────────────────────
(add-hook 'org-mode-hook #'variable-pitch-mode)
(add-hook 'markdown-mode-hook #'variable-pitch-mode)

;; Proteger faces para que tabelas, tags e código fiquem monoespaçados
(with-eval-after-load 'org
  (dolist (face '(org-table org-tag org-code org-block org-block-begin-line org-block-end-line org-date org-todo org-done org-document-info-keyword org-meta-line org-checkbox))
    (when (facep face)
      (set-face-attribute face nil :inherit 'fixed-pitch))))

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

(provide 'custom-writing)
;;; custom-writing.el ends here
