;;; magent-driver-live-scenario.el --- Unified Live Scenario validation for Magent Driver -*- lexical-binding: t; -*-

;;; Commentary:
;; Script unificado e melhorado para testar e demonstrar a "Teoria do Buffer Vivo"
;; para o Agente IA (Magent Driver) usando tanto Emacs Lisp (bytecode checker)
;; quanto Python (LSP/Eglot checker) como fontes de diagnóstico para o Flycheck.
;;
;; Este script cria duas sandboxes ativas:
;;   - `*Magent-ELisp-Sandbox*`
;;   - `*Magent-Python-Sandbox*` (com Eglot/LSP)
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
        (elisp-buf (get-buffer-create "*Magent-ELisp-Sandbox*"))
        (python-buf (get-buffer-create "*Magent-Python-Sandbox*")))

    ;; --- FASE 1A: PREPARAÇÃO DA SANDBOX ELISP ---
    (+carlos/magent-live-log "Preparando buffer sandbox Emacs Lisp...")
    (with-current-buffer elisp-buf
      (erase-buffer)
      (emacs-lisp-mode)
      (insert ";;; live-elisp-sandbox.el --- Sandbox buffer para Emacs Lisp -*- lexical-binding: t; -*-\n\n")
      (insert "(defun +live/calculadora-quebrada (x y)\n")
      (insert "  \"Soma x e y, mas contém um erro semântico de variável livre.\"\n")
      (insert "  (let ((total (+ x y)))\n")
      (insert "    (message \"Total calculado: %d\" total-inexistente)\n") ; total-inexistente é variável livre
      (insert "    total))\n\n")
      (insert "(defun +live/sintaxe-quebrada ()\n")
      (insert "  \"Função com erro de parêntese desbalanceado.\"\n")
      (insert "  (message \"Início de teste\"\n") ; Parêntese do message não foi fechado
      (insert "  (message \"Fim\"))\n")

      ;; Ativação do Flycheck
      (when (fboundp 'flycheck-mode)
        (flycheck-mode 1)
        (condition-case nil
            (flycheck-buffer)
          (error nil))))

    ;; --- FASE 1B: PREPARAÇÃO DA SANDBOX PYTHON (LSP) ---
    (+carlos/magent-live-log "Preparando buffer sandbox Python...")
    (with-current-buffer python-buf
      (erase-buffer)
      (if (fboundp 'python-ts-mode)
          (python-ts-mode)
        (python-mode))
      
      (insert "# -*- coding: utf-8 -*-\n")
      (insert "def calcular_soma(a: int, b: int) -> int:\n")
      (insert "    \"\"\"Soma dois inteiros.\"\"\"\n")
      (insert "    return a + b\n\n")
      (insert "# Erro semântico do LSP: passando string onde espera int\n")
      (insert "resultado = calcular_soma(10, \"texto_invalido\")\n\n")
      (insert "# Erro de sintaxe (parêntese aberto)\n")
      (insert "print(\"Falta fechar o parentese\"\n")

      ;; Ativar Flycheck
      (when (fboundp 'flycheck-mode)
        (flycheck-mode 1)
        (condition-case nil
            (flycheck-buffer)
          (error nil)))
      
      ;; Iniciar Eglot de forma segura e não-bloqueante (eglot-ensure usará basepyright se ativo)
      (when (fboundp 'eglot-ensure)
        (condition-case err
            (eglot-ensure)
          (error (+carlos/magent-live-log "-> Eglot-ensure avisou: %S" err)))))

    ;; --- FASE 2: EXECUÇÃO E ANÁLISE DAS FERRAMENTAS DO DRIVER ---
    (with-current-buffer report-buf
      (read-only-mode -1)
      (erase-buffer)
      (org-mode)
      (insert "#+TITLE: Relatório de Validação do Magent Driver (Buffer Vivo & LSP)\n")
      (insert "#+AUTHOR: Antigravity AI\n")
      (insert "#+DATE: " (format-time-string "%Y-%m-%d %H:%M:%S") "\n\n")
      (insert "Este relatório valida as ferramentas de pareamento do Magent atuando em buffers vivos.\n")
      (insert "Tanto o interpretador do Emacs Lisp quanto o servidor LSP de Python (Eglot) servem como geradores de erros no Flycheck.\n\n")

      (insert "* 1. Análise do Buffer: =*Magent-ELisp-Sandbox*=\n")
      (insert "Erros capturados via Flycheck Lisp nativo:\n\n")
      (let ((res (+carlos/magent-tool-flycheck-errors '(:path "*Magent-ELisp-Sandbox*" :reason "Análise sintática do Lisp"))))
        (insert (format "  - *Status:* %s\n" (plist-get res :status)))
        (insert (format "  - *Total de Erros:* %d\n" (or (plist-get res :total_errors) 0)))
        (let ((errors (plist-get res :errors)))
          (if (not errors)
              (insert "    /Nenhum erro reportado./\n")
            (dolist (err errors)
              (insert (format "    - Linha %d, Coluna %d [%s]: =%s= (Checker: %s)\n"
                              (plist-get err :line)
                              (plist-get err :column)
                              (plist-get err :level)
                              (plist-get err :message)
                              (plist-get err :checker)))))))

      (insert "\n* 2. Análise do Buffer: =*Magent-Python-Sandbox*=\n")
      (insert "Erros capturados via Flycheck + LSP (Eglot):\n\n")
      (let ((res (+carlos/magent-tool-flycheck-errors '(:path "*Magent-Python-Sandbox*" :reason "Análise semântica/LSP de Python"))))
        (insert (format "  - *Status:* %s\n" (plist-get res :status)))
        (insert (format "  - *Total de Erros:* %d\n" (or (plist-get res :total_errors) 0)))
        (insert "  - *Detalhes dos Erros encontrados (inclui diagnósticos do LSP se conectado):*\n")
        (let ((errors (plist-get res :errors)))
          (if (not errors)
              (insert "    /Nenhum erro reportado pelo flycheck (pode ser necessário sit-for de alguns segundos para o Eglot iniciar)./\n")
            (dolist (err errors)
              (insert (format "    - Linha %d, Coluna %d [%s]: =%s= (Checker: %s)\n"
                              (plist-get err :line)
                              (plist-get err :column)
                              (plist-get err :level)
                              (plist-get err :message)
                              (plist-get err :checker)))))))

      (insert "\n* 3. Navegação LSP Segura (=lsp_navigation=):\n")
      (let ((res (+carlos/magent-tool-lsp-navigation '(:symbol "+carlos/gptel-cache-hit-rate" :action "definition" :reason "Validar lookup seguro"))))
        (insert (format "  - *Lookup de Símbolo:* %s\n" (plist-get res :symbol)))
        (insert (format "  - *Mensagem/Status:* [%s] %s\n" (plist-get res :status) (or (plist-get res :message) "Lookup resolvido.")))
        (let ((results (plist-get res :results)))
          (when results
            (dolist (item results)
              (insert (format "    - Encontrado em: =%s= na linha %s\n" (plist-get item :file) (plist-get item :line)))))))

      (insert "\n* 4. Snippets do Tempel (=snippet_expand=):\n")
      (let ((res-list (+carlos/magent-tool-snippet-expand '(:reason "Listar snippets para validação")))
            (res-inspect (+carlos/magent-tool-snippet-expand '(:name "deftest" :action "inspect" :reason "Inspecionar deftest"))))
        (insert (format "  - *Listagem de Snippets:* Encontrados %d snippets registrados.\n" (or (plist-get res-list :total) 0)))
        (insert (format "  - *Inspeção do snippet 'deftest':* %s\n" 
                        (if (string= (plist-get res-inspect :status) "success")
                            (format "Estrutura: =%s=" (plist-get res-inspect :template))
                          "Snippet 'deftest' não encontrado (não há templates carregados na sessão atual).")))
        (insert "  - *Nota:* O agente de IA usa esta ferramenta para entender a estrutura sintática padrão local do usuário antes de escrever código, garantindo que ele reutilize templates em vez de reinventá-los.\n"))

      (insert "\n* 5. Como testar a Teoria do Buffer Vivo com a IA (Magent):\n")
      (insert "Para ver a IA atuando no buffer Python alimentado pelo LSP:\n")
      (insert "1. Mude para o buffer =*Magent-Python-Sandbox*=\n")
      (insert "2. Certifique-se de que o Eglot conectou (aparecerá =[eglot:basedpyright]= na modeline).\n")
      (insert "3. Chame a IA para operar nesse buffer usando =C-c I= (gptel-agent-run).\n")
      (insert "4. Peça no prompt: \"/explain os erros de flycheck deste buffer e modifique a chamada de calcular_soma corrigindo o erro de tipos do Python apontado pelo LSP.\"\n")
      (insert "5. O Magent usará a ferramenta =flycheck_errors= e =snippet_expand= para atuar diretamente no buffer de forma rápida e segura!\n")
      
      (goto-char (point-min))
      (read-only-mode 1))

    ;; Mostrar o relatório na tela
    (display-buffer report-buf)
    (+carlos/magent-live-log "Cenário de teste de buffer vivo com LSP concluído. Veja *Magent-Live-Analysis*!")))

;; Executar o cenário imediatamente após o load
(+carlos/magent-run-live-scenario)

(provide 'magent-driver-live-scenario)
;;; magent-driver-live-scenario.el ends here
