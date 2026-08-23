;;; custom-magent-tool-pkg.el --- Ferramentas Magent para Elpaca -*- lexical-binding: t; -*-

;;; Commentary:
;; Domínio exclusivo para gerenciamento de dependências e pacotes.
;; Permite ao agente Magent instalar e verificar pacotes dinamicamente.

;;; Code:

(require 'custom-magent-tools)
;; Declarations to avoid byte-compiler warnings if Elpaca is not loaded at compile-time
(declare-function elpaca-status "elpaca")
(declare-function elpaca--queued "elpaca")
(declare-function elpaca-process-queues "elpaca")

(defun +carlos/magent-tool-elpaca (action package-name &rest args)
  "Gerencia pacotes usando o Elpaca via Magent.
ACTION: `install' ou `status'.
PACKAGE-NAME: nome do pacote (string ou symbol).
ARGS pode conter :recipe (string Lisp como
\"(package :host github :repo \\\"...\\\")\")."
  (unless (featurep 'elpaca)
    (error "Elpaca não está carregado neste Emacs"))
  (let ((pkg (if (stringp package-name) (intern package-name) package-name))
        (action-sym (if (stringp action) (intern action) action)))
    (pcase action-sym
      ('status
       (let ((order (elpaca--queued pkg)))
         (if order
             (format "Status de %s no Elpaca: %s" pkg (elpaca-status order))
           (if (featurep pkg)
               (format "Pacote %s está carregado no Emacs (built-in ou instalado pré-Magent)." pkg)
             (format "Pacote %s NÃO está na fila do Elpaca e NÃO está carregado." pkg)))))
      ('install
       (let* ((recipe-str (plist-get args :recipe))
              (recipe (if (and recipe-str (not (string-empty-p recipe-str)))
                          (car (read-from-string recipe-str))
                        pkg)))
         (eval `(elpaca ,recipe
                  (lambda (e) (message "[Magent] Elpaca terminou o callback para: %S" e)))
               t)
         (elpaca-process-queues)
         (let ((timeout 45)
               (start (float-time)))
           (while (and (elpaca--queued pkg)
                       ;; Se o status for nil, failed, ou installed, sai do loop
                       (let ((st (elpaca-status (elpaca--queued pkg))))
                         (and st (not (memq st '(installed failed)))))
                       (< (- (float-time) start) timeout))
             (accept-process-output nil 0.5))
           (let ((order (elpaca--queued pkg)))
             (if (and order (eq (elpaca-status order) 'installed))
                 (progn
                   (ignore-errors (require pkg nil t))
                   (format "Pacote %s instalado e carregado com sucesso!" pkg))
               (format "Falha ou timeout (45s) ao instalar %s. Status atual: %s"
                       pkg (if order (elpaca-status order) "desconhecido")))))))
      (_ (error "Ação '%s' desconhecida.  Use 'install' ou 'status'" action)))))

;; Registra a ferramenta no ecossistema
(with-eval-after-load 'gptel
  (when (fboundp '+carlos/magent-tool-elpaca)
    (setq gptel-tools
          (append gptel-tools
                  `((:name "magent_elpaca"
                     :tool ,#'+carlos/magent-tool-elpaca
                     :permission magent_elpaca
                     :description "Gerencia dependências e pacotes via Elpaca diretamente no Emacs ativo.
Ideal para instalar ferramentas ausentes sem precisar pedir para o usuário reiniciar.
Ações: 'install' (baixa e instala), 'status' (verifica se existe).
Para 'install', você pode fornecer um recipe Elpaca em string Lisp, ex: \"(nome :host github :repo \\\"user/repo\\\")\"."
                     :args (("action" :type string :description "'install' ou 'status'")
                            ("package-name" :type string :description "Nome do pacote")
                            ("recipe" :type string :description "Opcional: Recipe Lisp em formato de string. Se vazio, instala pelo nome padrão."))))))))

(provide 'custom-magent-tool-pkg)
;;; custom-magent-tool-pkg.el ends here
