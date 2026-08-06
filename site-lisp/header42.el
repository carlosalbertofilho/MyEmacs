;;; header42.el --- Header padrão da 42 School -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2025 Carlos Filho
;;
;; Author: Carlos Filho
;; Version: 1.0
;; Package-Requires: ((emacs "24.3"))
;; Keywords: 42, header, convenience
;;
;; Este arquivo implementa o header padrão da 42 School com atualização automática.

;;; Commentary:
;;
;; Fornece funções para inserir e atualizar automaticamente o header padrão
;; da 42 School em arquivos de código.
;;
;; Uso:
;;   - Pressione F1 para inserir/atualizar o header
;;   - O header é atualizado automaticamente ao salvar o arquivo
;;
;; Configuração:
;;   - Define header-42-login para o login da 42 (default: csilva-d)
;;   - Fallback: FT_LOGIN ou USER no ambiente

;;; Code:

;; =============================================================================
;; CONFIGURAÇÃO
;; =============================================================================

(defgroup header42 nil
  "Header padrão da 42 School."
  :group 'convenience)

(defcustom header-42-login "csilva-d"
  "Login da 42 School usado no header.
Tem precedência sobre as variáveis de ambiente FT_LOGIN e USER."
  :type 'string
  :group 'header42)

;; =============================================================================
;; CONSTANTES
;; =============================================================================

(defconst header-42-ascii-art
  '("       :::      ::::::::"
    "     :+:      :+:    :+:"
    "   +:+ +:+         +:+  "
    " +#+  +:+       +#+     "
    "+#+#+#+#+#+   +#+        "
    "    #+#    #+#          "
    "   ###   ########.fr    ")
  "ASCII art do logo 42.")

(defconst header-42-length 80
  "Comprimento total de cada linha do header.")

(defconst header-42-margin 5
  "Margem lateral do header.")

;; =============================================================================
;; FUNÇÕES AUXILIARES
;; =============================================================================

(defun header-42-get-user ()
  "Retorna o login do usuário (header-42-login, FT_LOGIN, USER ou fallback)."
  (or header-42-login
      (getenv "FT_LOGIN")
      (getenv "USER")
      "marvin"))

(defun header-42-get-mail ()
  "Retorna o email do usuário."
  (let ((user (header-42-get-user)))
    (format "%s@student.42.fr" user)))

(defun header-42-get-filename ()
  "Retorna o nome do arquivo ou '< new >' se não existir."
  (if (buffer-file-name)
      (file-name-nondirectory (buffer-file-name))
    "< new >"))

(defun header-42-get-date ()
  "Retorna a data/hora atual no formato do header 42."
  (format-time-string "%Y/%m/%d %H:%M:%S"))

(defun header-42-make-line (left right)
  "Cria uma linha do header com LEFT à esquerda e RIGHT à direita."
  (let* ((left-str (substring left 0 (min (length left)
                                           (- header-42-length
                                              (* 2 header-42-margin)
                                              (length right)))))
         (right-str right)
         (spaces-needed (- header-42-length
                          (* 2 header-42-margin)
                          (length left-str)
                          (length right-str)))
         (spaces (if (< spaces-needed 0) 0 spaces-needed))
         (start-margin (make-string (- header-42-margin 2) ?\s))
         (end-margin (make-string (- header-42-margin 2) ?\s)))
    (format "/*%s%s%s%s%s*/"
            start-margin
            left-str
            (make-string spaces ?\s)
            right-str
            end-margin)))

(defun header-42-get-ascii (line-number)
  "Retorna a linha LINE-NUMBER do ASCII art (1-indexed)."
  (if (and (>= line-number 1) (<= line-number 7))
      (nth (- line-number 1) header-42-ascii-art)
    ""))

(defun header-42-generate-line (n)
  "Gera a linha N do header (1-11)."
  (cond
   ;; Linha 1: borda superior
   ((= n 1)
    (format "/* %s */"
            (make-string (- header-42-length 6) ?*)))
   
   ;; Linha 2: linha vazia
   ((= n 2)
    (header-42-make-line "" ""))
   
   ;; Linha 3: ASCII art vazio
   ((= n 3)
    (header-42-make-line "" (header-42-get-ascii 1)))
   
   ;; Linha 4: nome do arquivo
   ((= n 4)
    (header-42-make-line (header-42-get-filename) (header-42-get-ascii 2)))
   
   ;; Linha 5: ASCII art vazio
   ((= n 5)
    (header-42-make-line "" (header-42-get-ascii 3)))
   
   ;; Linha 6: autor
   ((= n 6)
    (header-42-make-line (format "By: %s <%s>"
                                 (header-42-get-user)
                                 (header-42-get-mail))
                        (header-42-get-ascii 4)))
   
   ;; Linha 7: ASCII art vazio
   ((= n 7)
    (header-42-make-line "" (header-42-get-ascii 5)))
   
   ;; Linha 8: Created
   ((= n 8)
    (header-42-make-line (format "Created: %s by %s"
                                 (header-42-get-date)
                                 (header-42-get-user))
                        (header-42-get-ascii 6)))
   
   ;; Linha 9: Updated
   ((= n 9)
    (header-42-make-line (format "Updated: %s by %s"
                                 (header-42-get-date)
                                 (header-42-get-user))
                        (header-42-get-ascii 7)))
   
   ;; Linha 10: linha vazia
   ((= n 10)
    (header-42-make-line "" ""))
   
   ;; Linha 11: borda inferior
   ((= n 11)
    (format "/* %s */"
            (make-string (- header-42-length 6) ?*)))))

;; =============================================================================
;; FUNÇÕES PRINCIPAIS
;; =============================================================================

(defun header-42-insert ()
  "Insere o header 42 no início do arquivo."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    ;; Insere linha vazia após o header
    (insert "\n")
    ;; Insere as 11 linhas do header de baixo para cima
    (let ((line 11))
      (while (> line 0)
        (goto-char (point-min))
        (insert (header-42-generate-line line) "\n")
        (setq line (1- line))))))

(defun header-42-update ()
  "Atualiza as linhas Updated: e filename do header 42 se existir."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    ;; Verifica se existe um header 42 (procura por "Updated:" na linha 9)
    (when (and (>= (count-lines (point-min) (point-max)) 11)
               (progn
                 (goto-char (point-min))
                 (forward-line 8)
                 (beginning-of-line)
                 (looking-at "^/\\*   Updated: ")))
      ;; Atualiza a linha 9 (Updated)
      (delete-region (line-beginning-position) (line-end-position))
      (insert (header-42-generate-line 9))
      ;; Atualiza a linha 4 (filename) - caso o arquivo tenha sido renomeado
      (goto-char (point-min))
      (forward-line 3)
      (beginning-of-line)
      (delete-region (line-beginning-position) (line-end-position))
      (insert (header-42-generate-line 4)))))

;;;###autoload
(defun stdheader ()
  "Insere ou atualiza o header 42."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (if (and (>= (count-lines (point-min) (point-max)) 11)
             (progn
               (goto-char (point-min))
               (forward-line 8)
               (beginning-of-line)
               (looking-at "^/\\*   Updated: ")))
        (header-42-update)
      (header-42-insert))))

;; =============================================================================
;; CONFIGURAÇÃO DE HOOKS E ATALHOS
;; =============================================================================

;;;###autoload
(defun header-42-enable ()
  "Enable 42 header with automatic update on save."
  (interactive)
  ;; Add hook to automatically update header on save for C/C++ buffers
  (add-hook 'c-mode-hook #'header-42-update t)
  (add-hook 'c++-mode-hook #'header-42-update t)
  ;; Set up keybinding using Doom's map! macro
  ;; SPC c h -> insert/update 42 header (mnemonic: code header)
  (if (fboundp 'map!)
      (map! :leader
            (:prefix ("c" . "code")
             :desc "Insert/update 42 header" "h" #'stdheader))
    ;; Fallback to global-set-key for non-Doom environments
    (global-set-key (kbd "C-c h") 'stdheader))
  (message "42 header enabled! Use SPC c h to insert/update header."))

;;;###autoload
(defun header-42-disable ()
  "Disable 42 header automatic update."
  (interactive)
  ;; Remove the hooks from C/C++ mode hooks
  (remove-hook 'c-mode-hook 'header-42-update t)
  (remove-hook 'c++-mode-hook 'header-42-update t)
  ;; Remove keybinding
  (if (fboundp 'map!)
      (map! :leader
            (:prefix "c"
             "h" nil))
    (global-set-key (kbd "C-c h") nil))
  (message "42 header disabled."))

(provide 'header42)
;;; header42.el ends here
