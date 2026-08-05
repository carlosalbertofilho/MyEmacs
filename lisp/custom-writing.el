;;; custom-writing.el --- Writing experience (Org + Markdown) -*- lexical-binding: t; -*-

;;; Commentary:
;; Visual improvements for Org-mode and Markdown:
;; - org-modern for both modes (modern styling)
;; - variable-pitch for body text, fixed-pitch for code/tables/tags
;; - Hide emphasis markers (asterisks, link markup)
;; - Olivetti centering (85 columns)
;; - Custom fold ellipsis (" ▾" instead of "...")
;; Full compatibility with ef-themes.

;;; Code:

(require 'subr-x)

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
        ;; Linha horizontal decorativa
        org-modern-horizontal-line (make-string 40 ?─)))

;; ── Variável pitch-mode (fontes proporcionais para texto) ──────────
;; Hook personalizado que aplica variable-pitch no corpo do texto
;; mas mantém fixed-pitch em blocos de código, tabelas e marcações inline.

(defun +carlos/writing-setup-variable-pitch ()
  "Ativar variable-pitch no buffer atual, mantendo fixed-pitch em código e tabelas."
  (variable-pitch-mode 1)
  ;; Garantir que faces de código usem fonte monoespaçada
  (dolist (face '(org-code org-verbatim org-block
                  markdown-code markdown-html-attr-value
                  markdown-markup-face))
    (when (facep face)
      (set-face-attribute face nil :inherit 'fixed-pitch)))
  ;; Tabelas e tags devem permanecer monoespaçadas para alinhamento
  (dolist (face '(org-table org-tag org-block-begin-line org-block-end-line))
    (when (facep face)
      (set-face-attribute face nil :inherit 'fixed-pitch))))

;; ── Olivetti (centralização de texto, 85 colunas) ──────────────────
(use-package olivetti
  :ensure t
  :hook ((org-mode . olivetti-mode)
         (markdown-mode . olivetti-mode))
  :init
  (setq olivetti-body-width 85                    ; 85 colunas de largura
        olivetti-minimum-body-width 85)           ; mínimo também 85
  :config
  ;; Aplicar variable-pitch quando olivetti ativa
  (add-hook 'olivetti-mode-hook #'+carlos/writing-setup-variable-pitch))

;; ── Org-mode: ocultar marcadores de ênfase ─────────────────────────
(use-package org
  :ensure nil
  :custom
  ;; Ocultar asteriscos de negrito/itálico (mostra apenas o texto)
  (org-hide-emphasis-markers t)
  ;; Indentação visual nos subtítulos
  (org-startup-indented t)
  ;; Imagens inline ao abrir
  (org-startup-with-inline-images t)
  ;; Esconder marcadores de ênfase
  (org-hide-emphasis-markers t))

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
