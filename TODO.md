# TODO — MyEmacs

## Histórico de Mudanças

### 2026-08-05 — Melhorias Visuais e Funcionais Dirvish, Org & Markdown (Inspirado no Doom)
- [x] Corrigir ícones gigantes no Dirvish (`dirvish-nerd-icons-height 0.85`)
- [x] Adicionar suporte seguro a TRAMP e switches inteligentes no Dired (`gls` fallback)
- [x] Ativar barra lateral do Dirvish (`dirvish-side`) e mapear `C-c f` globalmente
- [x] Integrar `diredfl` para colorização de sintaxe avançada em Dired/Dirvish
- [x] Integrar `org-appear` para esconder/revelar marcadores de formatação dinamicamente
- [x] Corrigir checkboxes concluídos no `org-modern` (símbolo do Doom)
- [x] Portar colorização de Tags/TODOs/Priorities para pílulas coloridas `:inverse-video t` no `org-modern`
- [x] Configurar escala LaTeX para `1.5x` no Org
- [x] Simplificar setup de fontes proporcionais (`variable-pitch-mode`) mantendo tabelas/tags alinhados (`fixed-pitch`)
- [x] Habilitar centralização de prosa com `olivetti-mode` (largura 100)
- [x] Limpar configurações redundantes e conflitos de Markdown
- [x] Validar tudo com compilação estrita zero warnings + checkdoc (`just lint`)

### 2026-08-05 — Documentação RAG e Análise de Bugs
- [x] Criar pasta `docs/` com estrutura de referência
- [x] Criar `docs/dirvish-reference.org` — API completa, extensões, pitfalls
- [x] Criar `docs/gptel-reference.org` — Backends, agent, org integration, pitfalls
- [x] Criar `docs/completion-stack.org` — Vertico, consult, corfu, marginalia, orderless, embark
- [x] Criar `docs/magit-reference.org` — Status, staging, commit, push/pull
- [x] Criar `docs/denote-reference.org` — Notes, silos, links, backlinks
- [x] Criar `docs/org-ecosystem.org` — org-modern, ob-mermaid, jupyter, pdf-tools
- [x] Criar `docs/ui-stack.org` — ef-themes, mood-line, olivetti, nerd-icons, which-key
- [x] Criar `docs/term-stack.org` — vterm, eshell, eshell-prompt-extras
- [x] Criar `AGENTS.md` — Guidelines de elisp, boas práticas, tabela de bugs conhecidos
- [x] Definir workflow de sync: repo → `~/.config/emacs-vanilla` → test

### 2026-08-05 — Reimplementação Norminette + Eglot
- [x] Criar `docs/norminette-reference.org` (905 linhas) — API completa, JSON format, error codes
- [x] Analisar integração atual flycheck-norminette (regex frágil, sem JSON, requer save)
- [x] Criar `custom-norminette.el` com parsing JSON e suporte a buffer não salvo
- [x] Adicionar hints contextuais para 20+ erros comuns
- [x] Implementar chain automático eglot → norminette
- [x] Adicionar `custom-norminette-check-buffer` (--cfile para verificar sem salvar)
- [x] Atualizar `custom-42.el` para usar novo módulo

### 2026-08-05 — Correção de 14 Bugs
- [x] Fix #1: Mover consult-history de C-c h para C-c / (liberar C-c h para stdheader)
- [x] Fix #2: Remover dirvish-default-layout 10 (inválido, válido: 0-5)
- [x] Fix #3: Mudar dirvish-nerd-icons-height de 12 para 16 (ícones gigantes)
- [x] Fix #4: Consolidar 6 blocos with-eval-after-load 'dirvish em :config
- [x] Fix #5: Remover TRAMP duplicado de custom-core.el
- [x] Fix #6: Substituir prog-mode eglot-ensure hook por hooks por modo
- [x] Fix #7: Substituir emojis em org-modern-priority por texto (terminal)
- [x] Fix #8: Guardar superchat llm.el dependency com locate-library
- [x] Fix #9: Guardar gptel-integrations require com nil t
- [x] Fix #10: Habilitar todos os bindings comentados (magit, gptel, stdheader, etc)
- [x] Fix #11: Remover binding duplicado de eshell (C-c e mantido em custom-term.el)
- [x] Fix #13: Adicionar fallback consult-fzf → consult-find no dashboard
- [x] Fix #14: Guardar magit-status com fboundp no dashboard

### 2026-08-05 — SuperChat + MCP
- [x] Adicionar `mcp.el` configuração
- [x] Adicionar `superchat` configuração
- [x] Atualizar `emacs.nix` com pacotes
- [x] Documentar comandos SuperChat/MCP

### 2026-08-05 — Dirvish Extensões
- [x] Integrar 13 extensões nativas do dirvish
- [x] Configurar quick-access, subtree, peek, emerge, vc, icons

### 2026-08-05 — AI/LLM
- [x] Configurar 5 backends gptel (Zen, Claude, Gemini, Ollama, MLX)
- [x] Configurar gptel-agent com personas 42 School
- [x] Configurar gptel-org para integração Org
- [x] Criar +carlos/gptel-agent-run sem advice bug

### 2026-08-05 — Pipeline de Lint + Zero Byte-Compile Warnings
- [x] Criar `just lint` (compile + checkdoc)
- [x] Criar `just checkdoc` (validação de docstrings)
- [x] Criar `just check-all` (check + lint)
- [x] Criar `just ci` (pipeline CI)
- [x] Adicionar `elpaca-wait` após `elpaca-use-package` no `init.el`
- [x] Corrigir variável obsoleta `epa-pinentry-mode` → `epg-pinentry-mode`
- [x] Corrigir argumento não usado em `custom-norminette--parse-json`
- [x] Corrigir docstring em `custom-term.el` (checkdoc warnings)
- [x] Corrigir docstring em `custom-git.el` (single quotes)
- [x] Adicionar forward declarations em `custom-ai.el` (10 variáveis/funções)
- [x] Adicionar forward declarations em `custom-completion.el` (corfu function)
- [x] Adicionar forward declarations em `custom-dashboard.el` (org-agenda, gptel)
- [x] Adicionar forward declarations em `custom-git.el` (vc-git-root, gptel-*)
- [x] Adicionar forward declarations em `custom-keybindings.el` (11 funções)
- [x] Adicionar forward declarations em `custom-knowledge.el` (denote-directory)
- [x] Adicionar forward declarations em `custom-writing.el` (markdown-*)
- [x] Adicionar forward declarations em `custom-term.el` (eshell/eat/vterm)
- [x] Renomear `corfu-enable-always-in-minibuffer` → `+carlos/corfu-enable-in-minibuffer`
- [x] Mover `ob-mermaid` antes do org-babel com `elpaca-wait`
- [x] Resultado: **zero warnings** no byte-compile + checkdoc

### 2026-08-05 — Dirvish: Preview Dispatchers + Extensões
- [x] Corrigir `dirvish-preview-dispatchers` (vc-log/vc-diff/vc-blame → image/gif/video/audio/epub/pdf/archive)
- [x] Adicionar `subtree-state`, `file-time`, `file-size` a `dirvish-attributes`
- [x] Adicionar keybindings: `; ? TAB o r s v N`
- [x] Corrigir `tramp-use-ssh-controlmaster-options` → `tramp-use-connection-share`
- [x] Ajustar `dirvish-large-directory-threshold` para 20000
- [x] Remover `dirvish-peek-mode` desnecessário

### 2026-08-05 — Org Mode Visual (Full Width + Hierarquia)
- [x] Remover `olivetti` (centralização em 85 colunas)
- [x] Aumentar heading sizes: H1:1.5, H2:1.3, H3:1.15, title:1.6
- [x] Buffers full-width sem centralização
- [x] Remover `org-hide-emphasis-markers` duplicado

### 2026-08-05 — UI Fixes (Which-Key + Ef-Themes)
- [x] Adicionar `(which-key-mode 1)` (faltava ativar)
- [x] Remover which-key duplicado do `init.el`
- [x] Adicionar `:demand t` ao `ef-themes` (não carregava por causa do defer)
- [x] Mover `ef-themes` settings de `:init` para `:config` (defvaralias warnings)

### 2026-08-05 — Terminal Fixes (Eshell + Eat)
- [x] Corrigir `eshell-mode-map` void variable (mover para `with-eval-after-load`)
- [x] Corrigir `eshell-path-extra` void variable (mover para hook + boundp)
- [x] Consolidar bindings de AI tools no eshell `:config`
- [x] Adicionar forward declarations (vterm-mode-map, eshell-mode-map, eat-*, vterm-*)
- [x] Mover vterm keybinding para dentro do vterm `:config`

### 2026-08-05 — Elpaca Bootstrap Fixes
- [x] Adicionar `(elpaca-wait)` após `elpaca-use-package`
- [x] Adicionar `:demand t` a vertico, marginalia, orderless, corfu
- [x] Adicionar `:demand t` a ob-mermaid (antes do org-babel)
- [x] Corrigir erro "Cannot load vertico/marginalia/orderless/corfu"
- [x] Corrigir erro "Cannot open load file: ob-mermaid"

## Bugs Conhecidos

| Bug | Severidade | Status | Notas |
|-----|------------|--------|-------|
| `compat loaded before Elpaca activation` | Baixa | ⚠️ Persistente | Pacote compat carregado como dependência antes da fila Elpaca processar. Não crítico, mas warning aparece em GUI. |
| `Cannot open load file: ob-mermaid` | Alta | 🔴 **PERSISTENTE** | Mesmo com `:demand t` + `elpaca-wait` antes do org, ob-mermaid não encontra no load-path em modo interativo. Funciona em batch. Investigar se pacote está instalado corretamente via Elpaca. |
| pdf-tools não compila macOS | Média | ⚠️ Workaround | Usar doc-view fallback |
| consult/nerd-icons não no MELPA | Alta | 🔍 Investigando | Pacotes podem estar em rebuild |
| vterm-module não compilado | Média | ℹ️ Info | Normal em batch mode, requer GUI |
| jupyter ZMQ module falhou | Baixa | ℹ️ Info | Não crítico para uso básico |
| SuperChat não no MELPA | Baixa | ℹ️ Info | Instalar via straight/manual |
| mcp.el não no ELPA | Baixa | ℹ️ Info | Instalar via Nix/manual |

## Fontes Pendentes (Nix)

Solicitar ao agente Nix adicionar:
- `space-grotesk` → Dashboard títulos
- `inter` → Dashboard corpo
- `victor-mono` → Código + Org mode (ligatures + cursive italic)

Já instalada:
- `nerd-fonts.jetbrains-mono` → Fallback ícones

## Plano de Correção — Bugs Identificados

### ✅ TODOS OS BUGS FORAM CORRIGIDOS (2026-08-05)

**CRÍTICOS (6) — ✅ Corrigidos**
| # | Bug | Arquivo | Ação |
|---|-----|---------|------|
| 1 | Keybinding conflitante `C-c h` | `custom-completion.el` | ✅ Movido para `C-c /` |
| 2 | `dirvish-default-layout 10` inválido | `custom-files.el` | ✅ Removido |
| 3 | `dirvish-nerd-icons-height 12` | `custom-files.el` | ✅ Mudado para 16 |
| 4 | 6 blocos `with-eval-after-load 'dirvish` | `custom-files.el` | ✅ Consolidados em `:config` |
| 5 | TRAMP duplicado | `custom-core.el` | ✅ Removido |
| 6 | Eglot em `prog-mode` hook | `custom-lang.el` | ✅ Hooks por modo |

**MÉDIOS (6) — ✅ Corrigidos**
| # | Bug | Arquivo | Ação |
|---|-----|---------|------|
| 7 | Emojis em `org-modern-priority` | `custom-org.el` | ✅ Texto alternativo |
| 8 | SuperChat depende de `llm.el` | `custom-ai.el` | ✅ Guard com `locate-library` |
| 9 | `gptel-integrations` require | `custom-ai.el` | ✅ Guard com `nil t` |
| 10 | Bindings comentados | `custom-keybindings.el` | ✅ Todos habilitados |
| 11 | Eshell bound 2x | `custom-term.el`, `custom-keybindings.el` | ✅ Removido duplicata |

**BAIXOS (2) — ✅ Corrigidos**
| # | Bug | Arquivo | Ação |
|---|-----|---------|------|
| 13 | `consult-fzf` pode não existir | `custom-dashboard.el` | ✅ Fallback para `consult-find` |
| 14 | `magit-status` sem check | `custom-dashboard.el` | ✅ Guard com `fboundp` |

## Plano de Ação: Melhoria Visual e Funcional de Dirvish, Org e Markdown (Refinado com Inspirações do Doom)

### 1. Enriquecer o Dirvish & Dired (Ícones, Extensões e Sidebar)
**Arquivo:** `lisp/custom-files.el` (ver: [custom-files.el](file:///Users/carlosfilho/Projects/Github/MyEmacs/lisp/custom-files.el))
- **Ação 1:** Corrigir os ícones gigantescos no Dirvish.
  - Substituir: `(dirvish-nerd-icons-height 16)` por `(dirvish-nerd-icons-height 0.85)` (escala proporcional apropriada ao `nerd-icons`).
- **Ação 2:** Adicionar suporte seguro a caminhos locais e remotos (TRAMP) nas switches do Dired, evitando telas em branco ao abrir conexões remotas.
  - No `custom-files.el`, substituir a definição de `dired-listing-switches` por:
    ```elisp
    (let ((args (list "-ahl" "-v" "--group-directories-first")))
      (when (featurep :system 'bsd)
        (if-let* ((gls (executable-find "gls")))
            (setq insert-directory-program gls)
          (setq args (list (car args)))))
      (setq dired-listing-switches (string-join args " ")))
    ```
  - E adicionar uma função/hook para conexões remotas:
    ```elisp
    (add-hook 'dired-mode-hook
              (lambda ()
                (when (file-remote-p default-directory)
                  (setq-local dired-actual-switches "-ahl"))))
    ```
- **Ação 3:** Ativar a barra lateral do Dirvish (`dirvish-side`) como substituto do Treemacs/NeoTree.
  - Configurar as variáveis do layout da sidebar em `:custom` no `dirvish`:
    ```elisp
    (dirvish-side-width 30)
    (dirvish-side-auto-expand t)
    (dirvish-side-open-file-action 'select)
    (dirvish-reuse-session 'open)
    ```
  - Adicionar atalho global em `lisp/custom-keybindings.el` (ver: [custom-keybindings.el](file:///Users/carlosfilho/Projects/Github/MyEmacs/lisp/custom-keybindings.el)):
    - Adicionar `(declare-function dirvish-side "dirvish")` no topo.
    - Configurar binding global: `(global-set-key (kbd "C-c f") #'dirvish-side)`
- **Ação 4:** Ativar o pacote `diredfl` para colorização de sintaxe avançada em dired e dirvish.
  - Adicionar o bloco:
    ```elisp
    (use-package diredfl
      :ensure t
      :hook ((dired-mode dirvish-directory-view-mode) . diredfl-mode))
    ```
- **Ação 5:** Confirmar que as extensões nativas (`dirvish-subtree`, `dirvish-history`, `dirvish-narrow`) estão corretas na lista de `dirvish-attributes`.

### 2. Melhorar Estética e Escrita de Org & Markdown (Aparência Estilo Doom)
**Arquivo:** `lisp/custom-writing.el` (ver: [custom-writing.el](file:///Users/carlosfilho/Projects/Github/MyEmacs/lisp/custom-writing.el))
- **Ação 1:** Adicionar o pacote `org-appear` para esconder/revelar marcadores de ênfase (como `*negrito*`, `/itálico/`, `=código=`) dinamicamente quando o cursor passa sobre eles.
  - Adicionar o bloco:
    ```elisp
    (use-package org-appear
      :ensure t
      :hook (org-mode . org-appear-mode))
    ```
- **Ação 2:** Corrigir os checkboxes concluídos no `org-modern` que podem ficar desalinhados ou gigantescos.
  - Em `:config` do `org-modern`, adicionar:
    ```elisp
    (setf (alist-get ?X org-modern-checkbox) #("□x" 0 2 (composition ((2)))))
    ```
- **Ação 3:** Portar a herança de faces de TODOs, Priorities e Tags para pílulas coloridas com efeito `:inverse-video t` nativo do tema.
  - Em `:config` do `org-modern`, adicionar a macro de herança de faces do Doom:
    ```elisp
    (letf! (defun new-spec (spec)
             (if (or (facep (cdr spec))
                     (not (keywordp (car-safe (cdr spec)))))
                 `(:inherit ,(cdr spec))
               (cdr spec)))
      (unless org-modern-tag-faces
        (dolist (spec org-tag-faces)
          (add-to-list 'org-modern-tag-faces `(,(car spec) :inverse-video t ,@(new-spec spec)))))
      (unless org-modern-todo-faces
        (dolist (spec org-todo-keyword-faces)
          (add-to-list 'org-modern-todo-faces `(,(car spec) :inverse-video t ,@(new-spec spec)))))
      (unless org-modern-priority-faces
        (dolist (spec org-priority-faces)
          (add-to-list 'org-modern-priority-faces `(,(car spec) :inverse-video t ,@(new-spec spec))))))
    ```
- **Ação 4:** Corrigir escala das equações matemáticas LaTeX.
  - Adicionar em `:config` do `org` no `custom-writing.el` (ou em `custom-org.el`):
    ```elisp
    (plist-put org-format-latex-options :scale 1.5)
    ```
- **Ação 5:** Corrigir a face `variable-pitch` e simplificar o setup de fontes para prosa:
  - Remover o bloco `(with-eval-after-load 'ef-themes ...)` no fim de `custom-writing.el`.
  - Remover a complexa função `+carlos/writing-setup-variable-pitch` e os hooks correspondentes.
  - Adicionar hooks nativos para ativar o modo de fonte proporcional no texto e manter tabelas/tags em fonte monoespaçada:
    ```elisp
    (add-hook 'org-mode-hook #'variable-pitch-mode)
    (add-hook 'markdown-mode-hook #'variable-pitch-mode)
    ```
  - Proteger faces críticas para que continuem usando a fonte monoespaçada (`fixed-pitch`), evitando quebra de alinhamento em tabelas, blocos de código e metadados:
    ```elisp
    (dolist (face '(org-table org-tag org-code org-block org-block-begin-line org-block-end-line org-date org-todo org-done))
      (when (facep face)
        (set-face-attribute face nil :inherit 'fixed-pitch)))
    ```
- **Ação 6:** Reintroduzir o pacote `olivetti` para centralizar buffers de prosa (Org/Markdown) em telas largas, melhorando drasticamente a legibilidade.
  - Adicionar o bloco:
    ```elisp
    (use-package olivetti
      :ensure t
      :hook ((org-mode markdown-mode) . olivetti-mode)
      :config
      (setq olivetti-body-width 100))
    ```
- **Ação 7:** Remover o bloco `(with-eval-after-load 'markdown-mode ...)` do arquivo `custom-writing.el` para evitar conflito com as configurações de `custom-markdown.el`.

### 5. Plano de Ação: Correções do UI (Which-Key) e Otimização do Dirvish
#### 1. Correção de Carregamento do `which-key` (Emacs 29)
**Arquivo:** [custom-ui.el](file:///Users/carlosfilho/Projects/Github/MyEmacs/lisp/custom-ui.el)
- **Ação:** O `which-key` é nativo apenas no Emacs 30+. No Emacs 29, ele precisa ser instalado via Elpaca.
  - Alterar `:ensure nil` para `:ensure t` no `use-package which-key` e reduzir o delay `which-key-idle-delay` para `0.4` para exibição rápida.

#### 2. Correção de Bloqueio do Dirvish (Ícones e Git sumidos)
**Arquivo:** [custom-files.el](file:///Users/carlosfilho/Projects/Github/MyEmacs/lisp/custom-files.el)
- **Ação:** Remover a linha `:after nerd-icons` da configuração do `dirvish` para liberar seu carregamento assíncrono.
  - Definir `:demand t` em `nerd-icons` para garantir que o mapeador de fontes seja carregado logo na inicialização.

#### 3. Melhorias e Extensões do Dirvish (Configuração Completa)
**Arquivo:** [custom-files.el](file:///Users/carlosfilho/Projects/Github/MyEmacs/lisp/custom-files.el)
- **Ação 1 (Sidebar Minimalista):** Garantir que `dirvish-side` tenha visual limpo e sem poluição visual.
  - Ajustar o tamanho da sidebar `dirvish-side-width` para `30`.
- **Ação 2 (Navegação Subtree):** Mapear atalho de árvore no dirvish-side.
  - Confirmar a presença de `subtree-state` em `dirvish-attributes` e mapear `"TAB"` para `dirvish-subtree-toggle`.
- **Ação 3 (Preview Dispatchers):**
  - Adicionar suporte completo a previews configurando `dirvish-preview-dispatchers` com `'(image gif video audio epub pdf archive)`.

### 3. Validação dos Ajustes
- **Ação 1:** Rodar `just check` no repositório para garantir que a sintaxe do Emacs Lisp esteja íntegra.
- **Ação 2:** Sincronizar com o ambiente de testes e testar a inicialização:
  ```bash
  emacs --init-directory ~/.config/emacs-vanilla
  ```
- **Ação 3:** Abrir o Dirvish (`dired`) para conferir se os ícones estão proporcionais e se as linhas são listadas corretamente. Abrir a barra lateral com `C-c f` para validar o comportamento da sidebar. Abrir um arquivo `.org` e `.md` para verificar o alinhamento centralizado do Olivetti, a fonte proporcional no texto de leitura e as tabelas/código em fonte monoespaçada.

### 4. Mudança de Versão
- Atualizar o `roadmap.org` e `TODO.md` ao aplicar cada passo.

## Próximos Passos

### Pendentes (investigação)
- [ ] **URGENTE**: Investigar `ob-mermaid` não encontrado em modo interativo (funciona em batch). Verificar: (1) pacote instalado via Elpaca? (2) autoloads gerados? (3) `elpaca-status` mostra instalado?
- [x] Investigar warning `compat loaded before Elpaca activation` — identificar qual pacote depende de compat e carrega antes da fila Elpaca (Corrigido gerenciando compat via Elpaca com wait)
- [ ] Investigar por que `consult` e `nerd-icons` não foram encontrados no MELPA durante `just check`
- [ ] Verificar se pacotes estão em rebuild no MELPA ou se foram removidos/renomeados
- [ ] Testar config completa em GUI (não batch) para verificar vterm-module

### Imediatos (corrigir bugs)
~~1. [ ] Fix #1: Remover `C-c h` de consult-history~~ ✅
~~2. [ ] Fix #2: Remover `dirvish-default-layout 10`~~ ✅
~~3. [ ] Fix #3: Ajustar `dirvish-nerd-icons-height`~~ ✅
~~4. [ ] Fix #4: Consolidar blocos `with-eval-after-load 'dirvish`~~ ✅
~~5. [ ] Fix #5: Remover TRAMP duplicado~~ ✅
~~6. [ ] Fix #6: Substituir `prog-mode` hook~~ ✅

### Curto Prazo (melhorias)
~~7. [ ] Fix #7: Guardar emojis~~ ✅
~~8. [ ] Fix #8: Guardar superchat~~ ✅
~~9. [ ] Fix #9: Guardar gptel-integrations~~ ✅
~~10. [ ] Fix #10: Habilitar bindings~~ ✅
~~11. [ ] Fix #11: Remover eshell duplicado~~ ✅
~~13. [ ] Fix #13: Guardar consult-fzf~~ ✅
~~14. [ ] Fix #14: Guardar magit-status~~ ✅

### Backlog (feature work - ordenado por dificuldade)
1. [ ] Testar SuperChat com fontes instaladas (Dificuldade: Muito Baixa - Validação visual)
2. [ ] Substituir o dashboard customizado atual pelo pacote `dashboard.el` usando um banner em formato de arte ASCII contendo "My Emacs" (Dificuldade: Baixa - Configuração declarativa)
3. [ ] Adicionar fontes ao Nix (space-grotesk, inter, victor-mono) (Dificuldade: Média - Edição de Home Manager externa)
4. [ ] Configurar Victor Mono com ligatures (Dificuldade: Média/Alta - Setup de composição de fontes para ligaduras no Emacs)
5. [ ] Refinar o dashboard com a tipografia nova instalada (Dificuldade: Média/Alta - Estética fina)
6. [ ] Fase 4 — Cutoff (Doom → Vanilla final) (Dificuldade: Alta - Transição e consolidação de workflows)

