;;; magent-driver-live-scenario.el --- Unified Live Scenario validation for Magent Driver -*- lexical-binding: t; -*-

;;; Commentary:
;; Script unificado e melhorado para testar e demonstrar a "Teoria do Buffer Vivo"
;; para o Agente IA (Magent Driver).
;;
;; Este script cria uma sandbox ativa chamada `*Magent-Driver-Live-Sandbox*`
;; e executa as 3 ferramentas do driver (flycheck_errors, lsp_navigation, snippet_expand)
;; com proteções defensivas aprimoradas para garantir que o Emacs NUNCA trave
;; (mesmo sem arquivos TAGS ou servidores LSP ativos).
;;
;; Como Executar:
;;   M-x load-file RET bin/magent-driver-live-scenario.el
;;   Ou via terminal:
;;   just run --eval '(load-file "bin/magent-driver-live-scenario.el")'

;;; Code:

(require 'cl-lib)
(require 'custom-ai)
(require 'custom-magent)

(defun +carlos/magent-live-log (msg &rest args)
  "Exibe uma mensagem formatada de log no buffer de mensagens e na minibuffer."
  (let ((formatted (apply #'format msg args)))
    (message "🎨 [Magent Live] %s" formatted)))

(defun +carlos/magent-run-live-scenario ()
  "Executa o cenário unificado de validação do buffer vivo."
  (interactive)
  (let ((report-buf (get-buffer-create "*Magent-Live-Analysis*"))
        (demo-buf (get-buffer-create "*Magent-Driver-Live-Sandbox*")))

    ;; --- FASE 1: PREPARAÇÃO DA SANDBOX DO BUFFER VIVO ---
    (+carlos/magent-live-log "Preparando buffer vivo temporário com erros propositais...")
    (with-current-buffer demo-buf
      (erase-buffer)
      (emacs-lisp-mode)
      (insert ";;; live-sandbox.el --- Sandbox buffer para pareamento de IA -*- lexical-binding: t; -*-\n\n")
      (insert "(defun +live/calculadora-quebrada (x y)\n")
      (insert "  \"Soma x e y, mas contém um erro semântico de variável livre.\"\n")
      (insert "  (let ((total (+ x y)))\n")
      (insert "    (message \"Total calculado: %d\" total-inexistente)\n") ; total-inexistente é variável livre
      (insert "    total))\n\n")
      (insert "(defun +live/sintaxe-quebrada ()\n")
      (insert "  \"Função com erro de parêntese desbalanceado.\"\n")
      (insert "  (message \"Início de teste\"\n") ; Parêntese do message não foi fechado
      (insert "  (message \"Fim\"))\n")

      ;; Ativação segura do Flycheck
      (if (not (fboundp 'flycheck-mode))
          (+carlos/magent-live-log "-> Flycheck-mode não está instalado no Emacs.")
        (flycheck-mode 1)
        (+carlos/magent-live-log "-> Flycheck-mode ativado no buffer *Magent-Driver-Live-Sandbox*.")
        (condition-case err
            (progn
              (+carlos/magent-live-log "-> Executando verificação de sintaxe de forma segura...")
              (flycheck-buffer))
          (error (+carlos/magent-live-log "-> Aviso: Flycheck executado em batch ou com warnings: %S" err)))))

    ;; --- FASE 2: EXECUÇÃO E ANÁLISE DAS FERRAMENTAS DO DRIVER ---
    (with-current-buffer report-buf
      (read-only-mode -1)
      (erase-buffer)
      (org-mode)
      (insert "#+TITLE: Relatório de Validação do Magent Driver\n")
      (insert "#+AUTHOR: Antigravity AI\n")
      (insert "#+DATE: " (format-time-string "%Y-%m-%d %H:%M:%S") "\n\n")
      (insert "* 1. Ferramenta: =flycheck_errors=\n")
      (insert "Coleta de problemas sintáticos/semânticos estruturados diretamente do buffer vivo.\n\n")

      (let ((res (+carlos/magent-tool-flycheck-errors '(:path "*Magent-Driver-Live-Sandbox*" :reason "Coletar erros para a IA analisar"))))
        (insert (format "  - *Status:* %s\n" (plist-get res :status)))
        (insert (format "  - *Buffer:* %s\n" (plist-get res :buffer)))
        (insert (format "  - *Total de Erros:* %d\n" (or (plist-get res :total_errors) 0)))
        (insert "  - *Detalhes dos Erros encontrados:*\n")
        (let ((errors (plist-get res :errors)))
          (if (not errors)
              (insert "    /Nenhum erro reportado pelo flycheck (pode ocorrer se rodado fora do modo GUI ou sem linter configurado)./\n")
            (dolist (err errors)
              (insert (format "    - Linha %d, Coluna %d [%s]: =%s= (Checker: %s)\n"
                              (plist-get err :line)
                              (plist-get err :column)
                              (plist-get err :level)
                              (plist-get err :message)
                              (plist-get err :checker)))))))

      (insert "\n* 2. Ferramenta: =lsp_navigation=\n")
      (insert "Navegação e resolução de símbolos (eglot/xref) sem risco de congelamento/travamento do Emacs.\n\n")
      
      ;; Nota: Graças à proteção que implementamos, o xref-find-backend para etags sem TAGS file
      ;; não perguntará mais nada ao usuário nem travará o minibuffer.
      (let ((res (+carlos/magent-tool-lsp-navigation '(:symbol "+carlos/gptel-cache-hit-rate" :action "definition" :reason "Validar lookup seguro"))))
        (insert (format "  - *Status:* %s\n" (plist-get res :status)))
        (insert (format "  - *Símbolo pesquisado:* =%s=\n" (plist-get res :symbol)))
        (insert (format "  - *Mensagem do Handler:* %s\n" (or (plist-get res :message) "Símbolo resolvido com sucesso.")))
        (let ((results (plist-get res :results)))
          (if (not results)
              (insert "    /Nenhum resultado de definição retornado (esperado se não houver LSP ativo ou arquivo TAGS)./\n")
            (dolist (item results)
              (insert (format "    - Encontrado em: =%s= na linha %s\n"
                              (plist-get item :file)
                              (plist-get item :line)))))))

      (insert "\n* 3. Ferramenta: =snippet_expand=\n")
      (insert "Listagem e expansão de placeholders para inserções precisas em buffers ativos.\n\n")
      
      (let ((res (+carlos/magent-tool-snippet-expand '(:name "deftest" :mode "emacs-lisp-mode" :reason "Demonstrar placeholders"))))
        (insert (format "  - *Status:* %s\n" (plist-get res :status)))
        (insert (format "  - *Snippet:* =%s=\n" (plist-get res :name)))
        (insert (format "  - *Estrutura do Template:* =%s=\n" (or (plist-get res :template) "indisponível")))
        
        ;; Exibir apenas uma prévia limitada de snippets disponíveis para evitar lag de redisplay por strings massivas
        (let* ((all-res (+carlos/magent-tool-snippet-expand '(:mode "emacs-lisp-mode" :reason "Listar todos")))
               (snippets (or (plist-get all-res :snippets) nil))
               (total (or (plist-get all-res :total) 0))
               (preview (seq-take snippets 10)))
          (insert (format "  - *Total de Snippets no modo:* %d\n" total))
          (insert (format "  - *Amostra dos 10 primeiros:* %S\n" preview))))

      (insert "\n* 4. Como testar a Teoria do Buffer Vivo com a IA (Magent):\n")
      (insert "Para ver a IA atuando neste buffer vivo de testes:\n")
      (insert "1. Mude para o buffer =*Magent-Driver-Live-Sandbox*=\n")
      (insert "2. Chame a IA para resolver os problemas nele: =C-c I= ou =M-x +carlos/gptel-agent-run=\n")
      (insert "3. Peça no prompt: \"/explain os erros de flycheck deste buffer e use snippet_expand deftest para escrever um teste para calculadora-quebrada corrigindo os erros.\"\n")
      (insert "4. Observe as ferramentas rodando e a IA editando/propondo código dinamicamente no buffer sandbox!\n")
      
      (goto-char (point-min))
      (read-only-mode 1))

    ;; Mostrar o relatório na tela
    (display-buffer report-buf)
    (+carlos/magent-live-log "Cenário de teste de buffer vivo concluído. Veja os resultados no buffer *Magent-Live-Analysis*!")))

;; Executar o cenário imediatamente após o load
(+carlos/magent-run-live-scenario)

(provide 'magent-driver-live-scenario)
;;; magent-driver-live-scenario.el ends here
