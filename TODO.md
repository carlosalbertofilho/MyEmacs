# TODO — Planejamento Ativo e Backlog (MyEmacs)

## 1. Planejamento Corrente (Ações Atuais)

- [x] **Ajuste de Truncamento do `dirvish-side`:**
  - Configurar atributos minimalistas (`vc-state`, `nerd-icons`, `collapse`, `subtree-state`) na sidebar para evitar quebra de colunas em 30 de largura.
  - Ocultar a modeline e simplificar o cabeçalho no buffer da sidebar.
  - Sincronizar e validar visualmente no Emacs Vanilla.

## 2. Bugs Conhecidos e Pendências (Investigação)

- [ ] **URGENTE**: Investigar `ob-mermaid` não encontrado em modo interativo (funciona em batch). Verificar:
  - (1) pacote instalado via Elpaca?
  - (2) autoloads gerados?
  - (3) `elpaca-status` mostra instalado?
- [ ] Investigar por que `consult` e `nerd-icons` não foram encontrados no MELPA durante `just check`.
- [ ] Verificar se pacotes estão em rebuild no MELPA ou se foram removidos/renomeados.
- [ ] Testar config completa em GUI (não batch) para verificar compilação do `vterm-module`.

## 3. Planejamento Futuro / Backlog (Ordenado por Dificuldade)

1. [ ] **Testar SuperChat com fontes instaladas** (Dificuldade: Muito Baixa - Validação visual)
2. [ ] **Substituir o dashboard customizado atual por `dashboard.el`** (Dificuldade: Baixa - Configuração declarativa)
   - Exibir um banner em formato de arte ASCII contendo "My Emacs".
3. [ ] **Configurar Victor Mono com ligatures** (Dificuldade: Média/Alta - Setup de composição de fontes para ligaduras no Emacs)
4. [ ] **Refinar o dashboard com a tipografia nova instalada** (Dificuldade: Média/Alta - Estética fina)
5. [ ] **Fase 4 — Cutoff (Doom → Vanilla final)** (Dificuldade: Alta - Transição e consolidação de workflows)

## 4. Plano de Ação e Implementação Detalhado (Opus)

### 1. Bug Investigation: `ob-mermaid` em modo interativo
**Problema:** Em sessões interativas, o `ob-mermaid` falha ao carregar, enquanto funciona em batch mode. O problema é de assincronicidade com o Elpaca ou falta de autoloads no load de linguagens do Org.
**Ações para o Executor:**
- Editar o arquivo de configuração onde o `ob-mermaid` é declarado (provavelmente `custom-org.el`).
- Mudar a configuração do pacote para ser carregado `:after org` e fazer o registro da linguagem dinamicamente no `:config` após o pacote estar garantido.
```elisp
(use-package ob-mermaid
  :ensure t
  :after org
  :config
  (setq ob-mermaid-cli-path "mmdc")
  ;; Registrar explicitamente após o pacote carregar
  (add-to-list 'org-babel-load-languages '(mermaid . t))
  (org-babel-do-load-languages 'org-babel-load-languages org-babel-load-languages))
```
- Se o comando `mmdc` não estiver no `exec-path` do Emacs no MacOS em modo GUI, adicione o pacote `exec-path-from-shell` (no `custom-core.el`) para herdar o `$PATH` do terminal.

### 2. Substituição por `dashboard.el`
**Problema:** Substituir o dashboard customizado pelo oficial `dashboard` com banner ASCII "My Emacs".
**Ações para o Executor:**
- Editar `custom-dashboard.el` e substituir completamente o conteúdo antigo por:
```elisp
(use-package dashboard
  :ensure t
  :config
  (dashboard-setup-startup-hook)
  (setq dashboard-banner-logo-title "My Emacs")
  (setq dashboard-startup-banner 'logo) ;; Para banner ASCII, aponte para um arquivo de texto com o caminho em vez de 'logo, ex: "~/.config/emacs-vanilla/banner.txt"
  (setq dashboard-center-content t)
  (setq dashboard-show-shortcuts nil)
  (setq dashboard-items '((recents  . 5)
                          (projects . 5)))
  (setq dashboard-set-heading-icons t)
  (setq dashboard-set-file-icons t)
  (setq dashboard-display-icons-p t)
  (setq dashboard-icon-type 'nerd-icons))
```

### 3. Ligaturas com Victor Mono
**Problema:** Ativar ligaduras (ex: `==`, `->`, `!=`) e suporte à itálico cursivo na fonte Victor Mono.
**Ações para o Executor:**
- No arquivo de fontes (ex: `custom-core.el`), garanta que a fonte seja setada:
  `(set-face-attribute 'default nil :family "Victor Mono" :weight 'semi-bold)`
- Instalar e configurar o pacote `ligature`:
```elisp
(use-package ligature
  :ensure t
  :config
  ;; Habilitar as ligaduras comuns de programação para todos os prog-modes
  (ligature-set-ligatures 'prog-mode
    '("|||>" "<|||" "<==>" "<!--" "####" "~~>" "***" "||=" "||>"
      ":::" "::=" "=:=" "===" "==>" "=!=" "=>>" "=<<" "=/=" "!=="
      "!!." ">=>" ">>=" ">>>" ">>-" ">->" "->>" "-->" "---" "-<<"
      "<~~" "<~>" "<*>" "<||" "<|>" "<$>" "<==" "<=>" "<=<" "<->"
      "<--" "<-<" "<<=" "<<-" "<<<" "<+>" "</>" "###" "#_(" "..<"
      "..." "+++" "/==" "///" "_|_" "www" "&&" "^=" "~~" "~@" "~="
      "~>" "~-" "**" "*>" "*/" "||" "|}" "|]" "|=" "|>" "|-" "{|"
      "[|" "]#" "::" ":=" ":>" ":<" "$>" "==" "=>" "!=" "!!" ">:"
      ">=" ">>" ">-" "-~" "-|" "->" "--" "-<" "<~" "<*" "<|" "<:"
      "<$" "<=" "<>" "<-" "<<" "<+" "</" "#{" "#[" "#:" "#=" "#!"
      "##" "#(" "#?" "#_" "%%" ".=" ".-" ".." ".?" "+>" "++" "?:"
      "?=" "?." "??" ";;" "/*" "/=" "/>" "//" "__" "~~" "(*" "*)"
      "\\\\" "://"))
  (global-ligature-mode t))
```
- A Victor Mono já usa cursiva automática em itálicos (ex: em comentários) quando suportado pelo Emacs.

### 4. Refinamento de Tipografia do Dashboard
**Problema:** Estilizar os títulos e entradas do `dashboard.el` usando `Space Grotesk` e `Inter`.
**Ações para o Executor:**
- Adicionar ao `:config` do pacote `dashboard` no arquivo `custom-dashboard.el`:
```elisp
(custom-set-faces
  '(dashboard-heading ((t (:family "Space Grotesk" :weight bold :height 1.2))))
  '(dashboard-items-face ((t (:family "Inter" :weight normal)))))
```

### 5. Fase 4 — Cutoff Final (Doom → Vanilla)
**Problema:** Consolidação do workflow no diretório padrão do Emacs.
**Ações para o Executor:**
- Escrever um script (ou instrução final) que irá:
  1. Fazer backup da instalação atual: `mv ~/.config/emacs ~/.config/emacs.bak` e `mv ~/.config/doom ~/.config/doom.bak`
  2. Sincronizar (ou linkar) a configuração atual oficial: `ln -s ~/Projects/Github/MyEmacs ~/.config/emacs`
  3. Validar a compilação no novo path, garantindo que não restem caminhos hardcoded para `~/.config/emacs-vanilla`.

---
> Para o histórico cronológico detalhado de conquistas e decisões arquiteturais do projeto, consulte o [roadmap.org](file:///Users/carlosfilho/Projects/Github/MyEmacs/roadmap.org).
