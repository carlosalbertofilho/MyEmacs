;;; magent-driver-test-scenario.el --- Batch scenario test for Magent Driver tools -*- lexical-binding: t; -*-

;;; Commentary:
;; Script de validação empírica das 3 ferramentas curadas (flycheck_errors,
;; lsp_navigation, snippet_expand) e do motor de auto-compactação automática.

;;; Code:

(require 'custom-ai)
(require 'custom-magent)

(message "=== INICIANDO VALIDAÇÃO DO NOVO FLUXO (MAGENT DRIVER) ===")

;; 1. Validação da ferramenta flycheck_errors
(message "\n[Teste 1/4] Executando 'flycheck_errors' no buffer atual (%s)..." (buffer-name))
(let ((res (+carlos/magent-tool-flycheck-errors nil)))
  (message "-> Status: %s | Total Erros: %s"
           (plist-get res :status)
           (or (plist-get res :total_errors) 0))
  (message "-> Resposta: %S" res))

;; 2. Validação da ferramenta lsp_navigation
(message "\n[Teste 2/4] Executando 'lsp_navigation' para o símbolo '+carlos/gptel-cache-hit-rate'...")
(let ((res (+carlos/magent-tool-lsp-navigation '(:symbol "+carlos/gptel-cache-hit-rate" :action "definition"))))
  (message "-> Status: %s | Total Resultados: %s"
           (plist-get res :status)
           (or (plist-get res :total) 0))
  (message "-> Resposta: %S" res))

;; 3. Validação da ferramenta snippet_expand
(message "\n[Teste 3/4] Executando 'snippet_expand' para listar snippets do Tempel...")
(let ((res (+carlos/magent-tool-snippet-expand nil)))
  (message "-> Status: %s | Total Snippets: %s"
           (plist-get res :status)
           (or (plist-get res :total) 0))
  (message "-> Resposta parcial: %S" (seq-take (or (plist-get res :snippets) nil) 5)))

;; 4. Validação da Auto-Compactação Automática e Cálculo de Cache Hit %
(message "\n[Teste 4/4] Validando cálculo de Cache Hit %% e disparo do Sink de Auto-Compactação...")
(let ((hit (+carlos/gptel-cache-hit-rate 100 900)))
  (message "-> Cache Hit Rate (100 input / 900 cached): %0.1f%%" hit))

(let ((fake-event '(:status completed :output-len 20000)))
  (message "-> Simulando evento turn-end com 20,000 chars (> 60%% da janela fallback)...")
  (+carlos/magent-auto-compact-check-and-run fake-event))

(message "\n=== VALIDAÇÃO DO CENÁRIO CONCLUÍDA COM SUCESSO! ===")
