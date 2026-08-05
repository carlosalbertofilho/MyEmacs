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

;; Forward declarations for byte-compiler
(defvar markdown-hide-markup)
(defvar markdown-hide-urls)
(defvar markdown-url-compose-char)

;; ── Org Modern (estilização moderna para Org e Markdown) ───────────
(use-package org-modern
  :ensure t
  :hook ((org-mode . org-modern-mode)
         (org-agenda-finalize . org-modern-agenda)
         (markdown-mode . org-modern-markdown))
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
        org-modern-horizontal-line (make-string 40 ?─)))

;; ── Variável pitch-mode (fontes proporcionais para texto) ──────────
;; Hook personalizado que aplica variable-pitch no corpo do texto
;; mas mantém fixed-pitch em blocos de código, tabelas e marcações inline.

(defun +carlos/writing-setup-variable-pitch ()
  "Ativar variable-pitch no buffer atual, mantendo fixed-pitch em código e tabelas."
  (variable-pitch-mode 1)
  ;; Hierarchical heading sizes with variable-pitch (larger for better visibility)
  (dolist (face-spec '((org-level-1 :height 1.5 :weight bold)
                       (org-level-2 :height 1.3 :weight bold)
                       (org-level-3 :height 1.15 :weight bold)
                       (org-level-4 :height 1.05 :weight bold)
                       (org-level-5 :height 1.0 :weight bold)
                       (org-level-6 :height 1.0 :weight bold)
                       (org-level-7 :height 1.0 :weight bold)
                       (org-level-8 :height 1.0 :weight bold)
                       (org-document-title :height 1.6 :weight bold)))
    (when (facep (car face-spec))
      (apply #'set-face-attribute (car face-spec) nil (cdr face-spec))))
  ;; Garantir que faces de código usem fonte monoespaçada
  (dolist (face '(org-code org-verbatim org-block org-block-begin-line org-block-end-line
                  markdown-code markdown-html-attr-value
                  markdown-markup-face))
    (when (facep face)
      (set-face-attribute face nil :inherit 'fixed-pitch)))
  ;; Tabelas e tags devem permanecer monoespaçadas para alinhamento
  (dolist (face '(org-table org-tag))
    (when (facep face)
      (set-face-attribute face nil :inherit 'fixed-pitch))))

;; Auto-enable variable-pitch in Org and Markdown
(add-hook 'org-mode-hook #'+carlos/writing-setup-variable-pitch)
(add-hook 'markdown-mode-hook #'+carlos/writing-setup-variable-pitch)

;; ── Org-mode: ocultar marcadores de ênfase + full width ────────────
(use-package org
  :ensure nil
  :custom
  ;; Ocultar asteriscos de negrito/itálico (mostra apenas o texto)
  (org-hide-emphasis-markers t)
  ;; Indentação visual nos subtítulos
  (org-startup-indented t)
  ;; Imagens inline ao abrir
  (org-startup-with-inline-images t)
  ;; Full width (no olivetti centering)
  (org-startup-truncated nil))

;; ── Markdown-mode: ocultar markup visualmente ──────────────────────
(with-eval-after-load 'markdown-mode
  ;; Ocultar todo o markup (asteriscos, colchetes, URLs)
  (setq markdown-hide-markup t)
  ;; Ocultar URLs em links (mostra "∞" no lugar)
  (setq markdown-hide-urls t)
  ;; Caractere placeholder para URLs escondidas
  (setq markdown-url-compose-char "∞"))

;; ── Ef-themes: compatibilidade com writing modes ───────────────────
;; Ef-themes já configura faces corretamente, mas garantimos que
;; variable-pitch e fixed-pitch herdem as cores do tema ativo.
(with-eval-after-load 'ef-themes
  ;; Garantir que a face variable-pitch use cores do tema
  (set-face-attribute 'variable-pitch nil
                      :inherit 'default)
  ;; Fixed-pitch herda do tema para blocos de código
  (set-face-attribute 'fixed-pitch nil
                      :inherit 'default))

(provide 'custom-writing)
;;; custom-writing.el ends here
