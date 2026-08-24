(require 'custom-magent-tool-debug)
(require 'custom-magent-tool-ast nil t)

(let ((default-directory "/Users/carlosfilho/Projects/HUPE/SIGER/V1"))
  (message "=== INICIANDO TESTE DO DEPURADOR VIVO (MAGENT-TOOL-DEBUG) no SIGER ===")
  (condition-case err
      (progn
        ;; 1. Iniciar dape com dlv (Go)
        (message "Iniciando sessão DAP (dlv)...")
        ;; Nota: dape usa 'dlv para golang
        (message "Resultado: %s" (+carlos/magent-tool-debug "start" "dlv"))
        (sleep-for 3)
        
        ;; 2. Colocar breakpoint em backend/cmd/api/main.go na linha 15 (exemplo)
        (message "Colocando Breakpoint em backend/cmd/api/main.go:15 ...")
        (message "Resultado: %s" (+carlos/magent-tool-debug "breakpoint" "backend/cmd/api/main.go" "15"))
        (sleep-for 2)
        
        ;; 3. Parar
        (message "Parando sessão DAP...")
        (message "Resultado: %s" (+carlos/magent-tool-debug "stop"))
        (message "=== TESTE CONCLUÍDO COM SUCESSO ===")
        )
    (error (message "ERRO DURANTE O TESTE DO DEBUGGER: %S" err))))
