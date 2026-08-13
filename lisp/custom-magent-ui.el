;;; custom-magent-ui.el --- Magent UI: loop de eventos informativo (Fase C) -*- lexical-binding: t; -*-

;;; Commentary:
;; Painel de atividade do Magent (Fase C): torna o loop de eventos do chat
;; mais informativo, mostrando detalhes das ações dos modelos (tool calls,
;; reasoning) e o ciclo de vida dos subagentes.  Esqueleto — implementação
;; planejada no TODO.md §1d (sink de atividade, advice de resumo de tool
;; call, lifecycle de subagente, badge de modelo, reasoning colapsável).

;;; Code:

;; ── Sink de atividade de UI (Fase C) ───────────────────────────────
;; +carlos/magent-ui-activity-sink: consome `turn-start/end',
;; `tool-call-start/end' e `subagent-start/stop' e renderiza linhas
;; compactas timestampadas no buffer *Magent* (agent-shell-insert), com
;; faces +carlos/magent-ui-*.

(provide 'custom-magent-ui)
;;; custom-magent-ui.el ends here
