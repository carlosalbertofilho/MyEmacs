;;; custom-magent-prompts.el --- Text formatting and system prompts for Magent -*- lexical-binding: t; -*-

;;; Commentary:
;; Este módulo isola as regras de negócio de formatação de texto e injeção de
;; contexto do Magent.

;;; Code:

(defun +carlos/magent-prompts-format-subagent-resume (names)
  "Formata a mensagem de auto-resume do orquestrador após subagentes."
  (if names
      (format "[System] Subagentes concluídos: %s. Sintetize os resultados para o usuário."
              (mapconcat #'identity names ", "))
    "[System] Subagente concluído. Sintetize o resultado para o usuário."))

(defun +carlos/magent-prompts-format-subagent-result (agent-name status result error-msg)
  "Formata a string de injeção de contexto com o resultado de um subagente."
  (if (eq status 'failed)
      (format "[Subagent %s (failed)] %s"
              (or agent-name "unknown")
              (or error-msg "Unknown error"))
    (format "[Subagent %s (completed)] %s"
            (or agent-name "unknown")
            (or result "No result"))))

(defvar +carlos/magent-preservation-instruction
  "Compactar a sessão preservando estruturadamente:
1. Arquivos modificados ou criados (caminhos completos) e a razão da mudança;
2. Nomes de funções de testes ERT associadas às alterações;
3. Decisões técnicas tomadas e suas justificativas;
4. TODOs/estado pendente (não duplicar o TODO.org nem roadmap.org — consulte-os);
5. Restrições e preferências do usuário persistentes;
6. Comandos e gates de compilação/teste válidos (`just ...`).
NÃO replicar conteúdo lido que não tenha sido alterado."
  "Base de preservação estruturada para a auto-compactação do Magent.")

(provide 'custom-magent-prompts)
;;; custom-magent-prompts.el ends here
