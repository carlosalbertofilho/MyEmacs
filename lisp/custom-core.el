;;; custom-core.el --- Core editor settings -*- lexical-binding: t; -*-

;;; Commentary:
;; Fundamentos: fontes, GPG, SSH, editor basics, display-line-numbers,
;; truncate-lines, xterm-mouse, auto-revert refinements.

;;; Code:

;; ── Fonts ───────────────────────────────────────────────────────────
(set-face-attribute 'default nil
                    :family "Victor Mono"
                    :weight 'semi-bold
                    :height 130)
(set-face-attribute 'fixed-pitch nil
                    :family "Victor Mono"
                    :weight 'semi-bold
                    :height 130)
(set-face-attribute 'variable-pitch nil
                    :family "Inter"
                    :height 140)

;; Fallback para símbolos unicode
(when (member "Symbola" (font-family-list))
  (set-fontset-font t 'unicode "Symbola" nil 'prepend))

;; ── Editor defaults ─────────────────────────────────────────────────
(setq-default truncate-lines t)
(setq-default indent-tabs-mode nil)
(setq-default tab-width 4)
(setq delete-by-moving-to-trash t)

;; Bidi & display reordering performance (desativa bidi/BPA e resize do minibuffer para evitar travamentos de CPU)
(setq-default bidi-paragraph-direction 'left-to-right)
(setq bidi-inhibit-bpa t)
(setq resize-mini-windows nil)
(setq max-mini-window-height 1)

;; Kill ring
(setq kill-ring-max 200)

;; Yes/no → y/n
(fset 'yes-or-no-p 'y-or-n-p)

;; ── Auto-revert refinements ─────────────────────────────────────────
(setopt auto-revert-use-notify t)

;; ── GPG / EPA ───────────────────────────────────────────────────────
(require 'epa-file)
(epa-file-enable)
(setq epg-pinentry-mode 'loopback)

;; ── Xterm mouse (tty) ───────────────────────────────────────────────
(when (not (display-graphic-p))
  (xterm-mouse-mode 1))

;; ── Display line numbers (ativados via prog-mode-hook no init.el) ──
(setq display-line-numbers-type 'relative)
(setq display-line-numbers-width 3)

;; ── Save place (remember cursor position per file) ──────────────────
(save-place-mode 1)

;; ── Recent files ────────────────────────────────────────────────────
(recentf-mode 1)
(setq recentf-max-menu-items 50
      recentf-max-saved-items 50)

;; ── Server mode (emacsclient) ───────────────────────────────────────
(require 'server)
(unless (server-running-p)
  (server-start))

;; ── exec-path-from-shell (macOS environment inherit) ────────────────
(use-package exec-path-from-shell
  :ensure t
  :if (memq window-system '(mac ns))
  :config
  (exec-path-from-shell-initialize))

;; ── ligature (ligaduras de código para Victor Mono) ─────────────────
(use-package ligature
  :ensure t
  :config
  ;; Habilitar as ligaduras comuns de programação para todos os prog-modes
  (ligature-set-ligatures 'prog-mode
    '("|||>" "<|||" "<==>" "<!--" "####" "~~>" "***" "||=" "||>"
      ":::" "::=" "=:=" "===" "==>" "=!=" "=>>" "=<<" "=/=" "!=="
      "!!." ">=>" ">>=" ">>>" ">>-" ">->" "->>" "-->" "---" "-<<"
      "<~~" "<~>" "<*>" "<||" "<|>" "<$>" "<==" "<=>" "<=<" "<->"
      "<--" "<-<" "<<=" "<<-" "<<<" "<+>" "</>" "###" "#_(" "..<"
      "..." "+++" "/==" "///" "_|_" "www" "&&" "^=" "~~" "~@" "~="
      "~>" "~-" "**" "*>" "*/" "||" "|}" "|]" "|=" "|>" "|-" "{|"
      "[|" "]#" "::" ":=" ":>" ":<" "$>" "==" "=>" "!=" "!!" ">:"
      ">=" ">>" ">-" "-~" "-|" "->" "--" "-<" "<~" "<*" "<|" "<:"
      "<$" "<=" "<>" "<-" "<<" "<+" "</" "#{" "#[" "#:" "#=" "#!"
      "##" "#(" "#?" "#_" "%%" ".=" ".-" ".." ".?" "+>" "++" "?:"
      "?=" "?." "??" ";;" "/*" "/=" "/>" "//" "__" "~~" "(*" "*)"
      "\\\\" "://"))
  (global-ligature-mode t))

(provide 'custom-core)
;;; custom-core.el ends here
