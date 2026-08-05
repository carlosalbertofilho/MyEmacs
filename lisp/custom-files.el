;;; custom-files.el --- File management and remote -*- lexical-binding: t; -*-

;;; Commentary:
;; dirvish com todas as extensões nativas, ibuffer, TRAMP optimization.

;;; Code:

;; ── dired base ──────────────────────────────────────────────────────
(setq dired-listing-switches "-alh --group-directories-first"
      dired-dwim-target t)

;; ── nerd-icons (ícones para dirvish, dashboard, etc) ───────────────
(use-package nerd-icons
  :ensure t
  :config
  ;; Instala ícones na primeira execução se necessário
  (unless (file-directory-p (expand-file-name "nerd-icons/fonts" user-emacs-directory))
    (nerd-icons-install-fonts t)))

;; ── dirvish core ────────────────────────────────────────────────────
(use-package dirvish
  :after nerd-icons
  :config
  (dirvish-override-dired-mode 1)
  (setq dirvish-attributes
        '(vc-state git-msg nerd-icons collapse file-size file-time)
        dirvish-side-width 30
        dirvish-window-size 0.5
        dirvish-large-directory-threshold 1000)

  ;; Layout padrão
  (setq dirvish-default-layout 10)

  ;; Hooks
  ;; extensões são carregadas on-demand pelo dirvish
  )

;; ── dirvish-yank: copy/paste em 2 estágios (assíncrono) ────────────
;; Fornece: dirvish-yank, dirvish-move, dirvish-symlink, dirvish-hardlink
;; Todos executados de forma assíncrona.

;; ── dirvish-rsync: integração com rsync ─────────────────────────────
;; Fornece: dirvish-rsync, dirvish-rsync-switches-menu
;; Menu transient para ajustar switches do rsync.

;; ── dirvish-emerge: agrupamento de arquivos por critérios ──────────
;; Agrupa como ibuffer: recentes, documentos, vídeos, imagens, etc.
;; Colapsável com TAB. Configurado via dirvish-emerge-menu (transient).
;; Ativado via dirvish-setup-hook acima.

;; ── dirvish-peek: preview no minibuffer ─────────────────────────────
;; Preview de arquivos enquanto navega candidatos no minibuffer.
;; Funciona com vertico, ivy, icomplete.
;; (Carregado on-demand pelo dirvish)
(with-eval-after-load 'dirvish
  (dirvish-peek-mode 1)
  ;; Preview imediato ao mudar candidato
  (setq dirvish-peek-key 'any))

;; ── dirvish-vc: integração Git ──────────────────────────────────────
;; Fornece: vc-state (bitmap), git-msg, vc-log/diff/blame preview.
;; Menu transient: ? v no dirvish. (Carregado on-demand)
(with-eval-after-load 'dirvish
  ;; Colocar vc dispatchers no início para priorizar
  (setq dirvish-preview-dispatchers
        '(vc-log vc-diff vc-blame)))

;; ── dirvish-icons: ícones nos arquivos ──────────────────────────────
;; Suporta: nerd-icons, all-the-icons, vscode-icon
;; Já temos nerd-icons instalado via Nix. (Carregado on-demand)
(with-eval-after-load 'dirvish
  (setq dirvish-nerd-icons-height 16
        dirvish-nerd-icons-offset 0))

;; ── dirvish-side: sidebar tipo treemacs ─────────────────────────────
;; Toggle com M-x dirvish-side. Follow mode rastreia buffer atual.
;; (Carregado on-demand pelo dirvish)
(with-eval-after-load 'dirvish
  (setq dirvish-side-width 30
        dirvish-side-auto-expand t
        dirvish-side-open-file-action 'select))

;; ── dirvish-ls: menu transient para switches do ls ─────────────────
;; M-x dirvish-ls-switches-menu para trocar switches rapidamente.

;; ── dirvish-subtree: tree browser inline ────────────────────────────
;; Expande diretórios como árvore inline. (Carregado on-demand)
(with-eval-after-load 'dirvish
  (setq dirvish-subtree-always-show-state nil
        dirvish-subtree-state-style "arrow"
        dirvish-subtree-icon-scale-factor 1.0))

;; ── dirvish-history: navegação por histórico ────────────────────────
;; Fornece: dirvish-history-jump, dirvish-history-go-forward/backward
;; Navega por diretórios visitados recentemente.

;; ── dirvish-quick-access: atalhos rápidos ───────────────────────────
;; Acesso a lugares frequentes com 2 keystrokes. (Carregado on-demand)
(with-eval-after-load 'dirvish
  (setq dirvish-quick-access-entries
        `(("h"  "~/"                    "Home")
          ("d"  "~/Downloads/"          "Downloads")
          ("p"  ,(expand-file-name "~/Projects/") "Projects")
          ("c"  ,(expand-file-name "~/.config/")  "Config")
          ("n"  ,(expand-file-name "~/org/notes") "Notes")
          ("e"  ,(expand-file-name "~/.config/emacs-vanilla/") "Emacs"))))

;; ── dirvish-collapse: colapsa caminhos nested únicos ───────────────
;; Remove diretórios "vazios" desnecessários da visualização.

;; ── dirvish-narrow: filtro live no buffer ──────────────────────────
;; Filtra arquivos em tempo real enquanto digita.
;; Suporta orderless e fd para dois níveis de filtro.
;; (Carregado on-demand pelo dirvish)

;; ── dirvish dispatch: menu de ajuda/cheatsheet ─────────────────────
;; M-x dirvish-dispatch → menu transient com todos os comandos.

;; ── ibuffer ─────────────────────────────────────────────────────────
(use-package ibuffer
  :bind
  (("C-x C-b" . ibuffer))
  :config
  (setq ibuffer-sorting-mode 'alphabetic
        ibuffer-expert t))

;; ── TRAMP optimization ──────────────────────────────────────────────
(setq tramp-default-method "ssh"
      tramp-ssh-controlmaster-options
      "-o ControlMaster=auto -o ControlPath='~/.ssh/controlmasters/%r@%h:%p' -o ControlPersist=600"
      tramp-use-ssh-controlmaster-options t)

;; Ensure controlmasters directory exists
(let ((cm-dir (expand-file-name "~/.ssh/controlmasters")))
  (unless (file-directory-p cm-dir)
    (make-directory cm-dir t)))

;; ── Project ─────────────────────────────────────────────────────────
(use-package project
  :config
  (setq project-switch-commands
        '((project-find-file "Find file")
          (project-find-regexp "Find regexp")
          (project-dired "Dired")
          (project-eshell "Eshell")
          (project-compile "Compile"))))

(provide 'custom-files)
;;; custom-files.el ends here
