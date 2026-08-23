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
  :custom
  (exec-path-from-shell-variables '("PATH" "MANPATH" "DICPATH" "XDG_DATA_DIRS"))
  :config
  (exec-path-from-shell-initialize))

;; ── Auto-fechamento de pares (electric-pair) ────────────────────────
(electric-pair-mode 1)

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


(defcustom +carlos/api-keys-file "/etc/api-keys.sh"
  "Arquivo shell que exporta chaves de API como `export NOME=valor'.
Formatos suportados: literal (`export NOME=\"chave\"') e agenix
(`export NOME=\"$(cat CAMINHO)\"'). `nil' desativa o carregamento."
  :type '(choice (const :tag "Nenhum" nil) file)
  :group '+carlos/ai)

(defun +carlos/--source-api-keys-from-file (file)
  "Carrega chaves de API ausentes do ambiente a partir do arquivo shell FILE.
Lê linhas `export VAR=valor' (resolvidas por
`+carlos/--api-key-value-from-sh') e chama `setenv' apenas para
variáveis ainda não definidas — nunca sobrescreve o ambiente."
  (when (and file (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (while (re-search-forward
              "^[[:space:]]*export[[:space:]]+\\([A-Za-z_][A-Za-z0-9_]*\\)=\\([^\n]*\\)"
              nil t)
        (let* ((var (match-string-no-properties 1))
               (value (+carlos/--api-key-value-from-sh
                       (match-string-no-properties 2))))
          (when (and (not (getenv var)) value)
            (setenv var value)))))))


(defun +carlos/--api-key-value-from-sh (raw)
  "Resolve o valor da chave a partir da string shell RAW.
Suporta literais com aspas simples/duplas e a forma agenix
`\"$(cat CAMINHO)\"', lendo o conteúdo de CAMINHO (trim de \\n final)."
  (let ((trimmed (string-trim raw)))
    (if (string-match "\\`[\"']?\\$(cat[[:space:]]+\\([^)\"']+\\))[\"']?\\'"
                      trimmed)
        (let* ((secret (match-string-no-properties 1 trimmed))
               (macos-secret (if (string-prefix-p "/run/agenix/" secret)
                                 (concat "/run/agenix.d/1/" (file-name-nondirectory secret))
                               nil))
               (actual-secret (cond
                               ((and (file-readable-p secret) (not (file-directory-p secret))) secret)
                               ((and macos-secret (file-readable-p macos-secret) (not (file-directory-p macos-secret))) macos-secret)
                               (t nil))))
          (when actual-secret
            (string-trim-right
             (with-temp-buffer
               (insert-file-contents actual-secret)
               (buffer-substring-no-properties (point-min) (point-max))))))
      ;; Remove aspas delimitadoras simples/duplas manualmente
      ;; (string-trim nativo do Emacs 30 não respeita charset multi-char).
      (let ((value trimmed))
        (when (and (> (length value) 1)
                   (memq (aref value 0) '(?\" ?'))
                   (eq (aref value (1- (length value))) (aref value 0)))
          (setq value (substring value 1 -1)))
        value))))

(+carlos/--source-api-keys-from-file +carlos/api-keys-file)

(provide 'custom-core)
;;; custom-core.el ends here
