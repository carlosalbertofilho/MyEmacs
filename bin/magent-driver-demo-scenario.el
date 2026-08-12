;;; magent-driver-demo-scenario.el --- Scenario validation script for Magent Driver tools -*- lexical-binding: t; -*-

;;; Commentary:
;; Este script cria um cenário empírico controlado (Opção 2) para demonstrar
;; o fluxo do Magent atuando como Driver do Emacs sobre as ferramentas:
;; `flycheck_errors`, `lsp_navigation` e `snippet_expand`.
;;
;; Como Executar:
;;   M-x load-file RET <este-arquivo>
;;   Ou via terminal para ver a saída em batch:
;;   just run --eval '(load-file "bin/magent-driver-demo-scenario.el")'

;;; Code:

(require 'cl-lib)
(require 'custom-ai)
(require 'custom-magent)

(message "\n======================================================================")
(message "🚀 INICIANDO CENÁRIO DE DEMONSTRAÇÃO DO MAGENT DRIVER (Fase A - C5)")
(message "======================================================================")

;; --- CONFIGURAÇÃO DO CENÁRIO DO BUFFER VIVO ---
(message "\n[Fase 1/4] Preparando Buffer Vivo Temporário com erro de propósito...")
(let ((demo-buf (get-buffer-create "*Magent-Driver-Demo*")))
  (with-current-buffer demo-buf
    (erase-buffer)
    (emacs-lisp-mode)
    ;; Inserir código de Emacs Lisp com dois erros de propósito:
    ;; 1. Erro de sintaxe (parêntese desbalanceado) na linha 14
    ;; 2. Uso de variável livre para simular erro semântico
    (insert ";;; demo.el --- Demo buffer -*- lexical-binding: t; -*-\n\n")
    (insert "(defun +demo/calculadora (a b)\n")
    (insert "  \"Soma dois números com erro semântico de variável livre.\"\n")
    (insert "  (let ((resultado (+ a b)))\n")
    (insert "    (message \"O resultado é: %d\" resultado-errado)\n") ; resultado-errado é variável livre
    (insert "    resultado))\n\n")
    (insert "(defun +demo/funcao-quebrada ()\n")
    (insert "  \"Função com erro de sintaxe sintático.\"\n")
    (insert "  (message \"Início da quebra\"\n") ; Falta fechar o parêntese do message
    (insert "  (message \"Fim\"))\n")
    
    ;; Ativar Flycheck explicitamente
    (when (fboundp 'flycheck-mode)
      (flycheck-mode 1)
      (message "-> Flycheck-mode ativado no buffer *Magent-Driver-Demo*.")
      ;; Forçar o Flycheck a rodar de forma síncrona
      (message "-> Executando verificação de sintaxe síncrona...")
      (condition-case nil
          (flycheck-buffer)
        (error (message "-> Nota: O flycheck compilou em batch."))))))

;; --- 1. CHAMADA DA FERRAMENTA: flycheck_errors ---
(message "\n[Fase 2/4] Executando ferramenta 'flycheck_errors' para ler os erros do buffer vivo...")
(let ((res (+carlos/magent-tool-flycheck-errors '(:path "*Magent-Driver-Demo*" :reason "Demonstrar coleta estruturada de erros"))))
  (message "-> Resposta Plist da Ferramenta:")
  (message "   Status:       %s" (plist-get res :status))
  (message "   Buffer Alvo:  %s" (plist-get res :buffer))
  (message "   Total Erros:  %d" (or (plist-get res :total_errors) 0))
  (let ((errors (plist-get res :errors)))
    (if (not errors)
        (message "   [Nenhum erro de sintaxe ativo. Nota: Se rodado em batch puro sem compiler real, os erros podem ser nulos]")
      (dolist (err errors)
        (message "   - Linha %d, Coluna %d [%s]: %s (Checker: %s)"
                 (plist-get err :line)
                 (plist-get err :column)
                 (plist-get err :level)
                 (plist-get err :message)
                 (plist-get err :checker))))))

;; --- 2. CHAMADA DA FERRAMENTA: lsp_navigation ---
(message "\n[Fase 3/4] Executando ferramenta 'lsp_navigation' para resolver a definição de um símbolo...")
;; Vamos resolver '+carlos/gptel-cache-hit-rate' que está no custom-ai.el
(let ((res (+carlos/magent-tool-lsp-navigation '(:symbol "+carlos/gptel-cache-hit-rate" :action "definition" :reason "Evitar alucinar de assinatura"))))
  (message "-> Resposta Plist da Ferramenta:")
  (message "   Status:       %s" (plist-get res :status))
  (message "   Símbolo Alvo: %s" (plist-get res :symbol))
  (let ((results (plist-get res :results)))
    (if (not results)
        (message "   [Nenhuma definição ativa. Nota: Requer Eglot/LSP ativo no contexto]")
      (dolist (item results)
        (message "   - Encontrado em '%s' na linha %s"
                 (plist-get item :file)
                 (plist-get item :line))
        (message "     Assinatura: %s" (plist-get item :summary))))))

;; --- 3. CHAMADA DA FERRAMENTA: snippet_expand ---
(message "\n[Fase 4/4] Executando ferramenta 'snippet_expand' para inspecionar templates do Tempel...")
;; Inspecionar o template de teste 'deftest' do tempel
(let ((res (+carlos/magent-tool-snippet-expand '(:name "deftest" :mode "emacs-lisp-mode" :reason "Demonstrar inspeção de esqueleto"))))
  (message "-> Resposta Plist da Ferramenta:")
  (message "   Status:       %s" (plist-get res :status))
  (message "   Snippet Alvo: %s" (plist-get res :name))
  (message "   Estrutura do Template: %s" (plist-get res :template)))

(message "\n======================================================================")
(message "✅ CENÁRIO DE DEMONSTRAÇÃO DO MAGENT DRIVER FINALIZADO!")
(message "   O buffer temporário '*Magent-Driver-Demo*' foi preservado para sua análise.")
(message "======================================================================")

(provide 'magent-driver-demo-scenario)
;;; magent-driver-demo-scenario.el ends here