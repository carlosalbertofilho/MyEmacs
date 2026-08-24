(require 'gptel)
(setq gptel-backend (or (gptel-get-backend "Gemini") (car gptel-backend-list)))
(setq gptel-model "gemini-2.5-pro")

(message "Iniciando teste de conectividade com a API do Gemini...")
(let ((done nil)
      (result nil))
  (condition-case err
      (gptel-request "Por favor, responda apenas com a palavra TESTE. Sem aspas ou pontuação."
                     :callback (lambda (resp info)
                                 (setq result resp)
                                 (setq done t)))
    (error (message "Erro ao engatilhar request: %S" err)
           (setq done t)))
  
  ;; Loop de espera (Timeout de 30 segundos)
  (let ((timeout 30)
        (elapsed 0))
    (while (and (not done) (< elapsed timeout))
      (sleep-for 1)
      (setq elapsed (1+ elapsed)))
    
    (if done
        (message "SUCESSO: A API respondeu -> %s" result)
      (message "FALHA: Timeout da API (30 segundos atingidos sem resposta)."))))
