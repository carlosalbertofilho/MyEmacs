;;; custom-magent-context.el --- Magent contexto: auto-compactação por threshold -*- lexical-binding: t; -*-

;;; Commentary:
;; Auto-compactação da sessão do Magent por threshold de janela do modelo,
;; com instrução de preservação estruturada.  A Fase B (compactação estilo
;; opencode: resumo progressivo, milestones, estado do projeto) evoluirá
;; este módulo.

;;; Code:

(declare-function magent-runtime-session-compact "magent-runtime-api")
(declare-function magent-lifecycle-events-add-sink "magent-lifecycle-events")

;; ── Auto-Compactação Automática por Threshold (Opção 4 Híbrida) ──────
(defcustom +carlos/magent-context-compact-ratio 0.6
  "Limite (0.0 a 1.0) da janela do modelo para disparar auto-compactação.
Por padrão, 0.6 (60% da janela do modelo ativo)."
  :type 'float
  :group '+carlos/ai)

(defcustom +carlos/magent-context-window-fallback 16384
  "Janela de contexto fallback caso o modelo gptel não declare :context-window."
  :type 'integer
  :group '+carlos/ai)

(defvar +carlos/magent-preservation-instruction
  "Compactar a sessão preservando estruturadamente:
1. Arquivos modificados ou criados (caminhos completos) e a razão da mudança;
2. Nomes de funções de testes ERT associadas às alterações;
3. Decisões técnicas tomadas e suas justificativas;
4. TODOs/estado pendente (não duplicar o TODO.md nem roadmap.org — consulte-os);
5. Restrições e preferências do usuário persistentes;
6. Comandos e gates de compilação/teste válidos (`just ...`).
NÃO replicar conteúdo lido que não tenha sido alterado."
  "Instrução de preservação estruturada para a auto-compactação do Magent.")

(defun +carlos/magent-compact (&optional instruction)
  "Executa a compactação da sessão atual do Magent com INSTRUCTION estruturada."
  (interactive)
  (let ((instr (or instruction +carlos/magent-preservation-instruction)))
    (if (fboundp 'magent-runtime-session-compact)
        (progn
          (magent-runtime-session-compact :instruction instr)
          (message "[Magent Compact] Compactação de sessão iniciada com sucesso."))
      (message "[Magent Compact] magent-runtime-session-compact indisponível."))))

(global-set-key (kbd "C-c A p") #'+carlos/magent-compact)

(defun +carlos/magent-get-context-window ()
  "Retorna o tamanho da janela de contexto do modelo gptel ativo."
  (or (and (boundp 'gptel-model)
           gptel-model
           (get (intern (gptel--model-name gptel-model)) :context-window))
      +carlos/magent-context-window-fallback))

(defun +carlos/magent-auto-compact-check-and-run (event-data)
  "Sink de lifecycle que verifica a auto-compactação no `turn-end'.
EVENT-DATA é o plist do lifecycle event; compacta quando o output do turno
excede o threshold de `+carlos/magent-context-compact-ratio'."
  (when (and (plist-get event-data :status)
             (eq (plist-get event-data :status) 'completed))
    (let* ((len (or (plist-get event-data :output-len) 0))
           (cwindow (+carlos/magent-get-context-window))
           (threshold (truncate (* +carlos/magent-context-compact-ratio cwindow))))
      (when (> len threshold)
        (message "[Magent Auto-Compact] Limite de contexto atingido (%d > %d tokens). Compactando em segundo plano..."
                 len threshold)
        (+carlos/magent-compact)))))

(with-eval-after-load 'magent-lifecycle-events
  (when (fboundp 'magent-lifecycle-events-add-sink)
    (magent-lifecycle-events-add-sink #'+carlos/magent-auto-compact-check-and-run)))

(provide 'custom-magent-context)
;;; custom-magent-context.el ends here
