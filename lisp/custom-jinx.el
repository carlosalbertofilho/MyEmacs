;;; custom-jinx.el --- Spell checker (jinx) + grammar correction via AI -*- lexical-binding: t; -*-

;;; Commentary:
;; jinx (JIT spell checker via libenchant) com pt_BR + en_US simultâneos.
;; Ativa em text-mode e prog-mode. Correção gramatical/ortográfica profunda
;; via gptel local (Ollama/mistral) com substituição in-place da região.
;;
;; Dependências de sistema (NixOS, emacs.nix): enchant + hunspellDicts.pt_BR
;; e hunspellDicts.en_US, PKG_CONFIG_PATH para o output .dev do enchant e
;; LD_LIBRARY_PATH para libenchant-2.so.2 em runtime.

;;; Code:

;; Forward declarations para o byte-compiler
(declare-function +carlos/gptel-request "custom-ai")
(declare-function jinx-correct "jinx")
(declare-function jinx-languages "jinx")

(defvar +carlos/gptel-grammar-backend)
(defvar +carlos/gptel-grammar-model)

;; ── jinx (spell checker JIT) ─────────────────────────────────────────
(use-package jinx
  :ensure t
  :demand t
  :custom
  (jinx-languages "pt_BR en_US")
  :config
  ;; Ativa em buffers de texto e código (comentários/strings checados
  ;; automaticamente por faces via jinx-include/exclude-faces).
  (add-hook 'text-mode-hook #'jinx-mode)
  (add-hook 'prog-mode-hook #'jinx-mode)

  ;; Binds padrão do jinx, escopados ao minor-mode.
  (define-key jinx-mode-map (kbd "M-$")   #'jinx-correct)
  (define-key jinx-mode-map (kbd "C-M-$") #'jinx-languages))

;; ── +carlos/grammar-correct-region (IA local, in-place) ─────────────
;; Usa gptel com backend local (Ollama Local) e modelo mistral para
;; correção profunda de ortografia/gramática. O texto corrigido substitui
;; a região no buffer de origem (in-place).
(defun +carlos/grammar-correct-region (beg end)
  "Corrige gramática e ortografia da região BEG..END com IA local.
Usa o backend `+carlos/gptel-grammar-backend' e o modelo
`+carlos/gptel-grammar-model' (Ollama Local / mistral). O resultado
substitui a região no buffer original."
  (interactive "r")
  (let* ((text (buffer-substring-no-properties beg end))
         (beg-marker (copy-marker beg))
         (end-marker (copy-marker end))
         (prompt (format "\
Corrija os erros de ortografia, gramática, pontuação e concordância do
texto abaixo. Preserve o idioma ORIGINAL do texto (o texto pode estar em
português ou inglês), o significado, o tom e a formatação original.
Responda SOMENTE com JSON no formato: {\"corrected\": \"<texto corrigido>\"}

TEXTO:
%s"
                         text)))
    (unless (string-empty-p (string-trim text))
      (message "Jinx+AI: corrigindo região com %s..." +carlos/gptel-grammar-model)
      (+carlos/gptel-request prompt +carlos/gptel-grammar-backend
                             +carlos/gptel-grammar-model
                             :buffer "*gptel-grammar*"
                             :schema '(:type object
                                       :properties (:corrected (:type string)))
                             :callback
                             (lambda (response _info)
                               (when response
                                 (+carlos/--grammar-apply-corrected
                                  beg-marker end-marker response)))))))

(defun +carlos/--grammar-extract-corrected (response)
  "Extrai o texto corrigido de RESPONSE (JSON `corrected' ou texto puro)."
  (condition-case nil
      (let ((data (json-parse-string response :object-type 'alist)))
        (or (alist-get 'corrected data)
            (alist-get "corrected" data)))
    (error response)))

(defun +carlos/--grammar-apply-corrected (beg-marker end-marker response)
  "Substitui a região entre BEG-MARKER e END-MARKER por RESPONSE corrigido."
  (let ((beg (marker-position beg-marker))
        (end (marker-position end-marker)))
    (when (and beg end (<= beg end))
      (let ((corrected (+carlos/--grammar-extract-corrected response)))
        (when (and (stringp corrected) (not (string-empty-p corrected)))
          (with-current-buffer (marker-buffer beg-marker)
            (save-excursion
              (goto-char beg)
              (delete-region beg end)
              (insert (string-trim corrected))
              (message "Jinx+AI: região corrigida (%d chars)" (- (point) beg))))))))
  (set-marker beg-marker nil)
  (set-marker end-marker nil))

;; ── Keybinding ───────────────────────────────────────────────────────
(global-set-key (kbd "C-c c g") #'+carlos/grammar-correct-region)

(provide 'custom-jinx)
;;; custom-jinx.el ends here
