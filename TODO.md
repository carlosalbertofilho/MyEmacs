# TODO — Planejamento Ativo e Backlog (MyEmacs)

## 0. Checkpoint de Rollback (baseline)

> **Commit de referência (SAVE POINT):** `4679a26` — `fix(elpaca): remove duplicate transient declaration causing 'Duplicate item ID queued'`
> **Estado (aprovado pelo usuário: "deu certo, ficou lindo!"):** boot limpo sem erros; org-mode com fontes personalizadas (variable-pitch Inter + headings hierárquicos via ef-themes) e sem o bug monocromático; dirvish-emerge iterado (navegação `[`/`]` com guard, grupo Directories, per-dir via `.dir-locals.el`); transient carregado cedo sem "Duplicate item ID queued"; vanilla sincronizado com `origin/main`.
> **Reverter:** `git revert 4679a26` (preserva histórico) ou `git reset --hard 4679a26` (destrói commits seguintes) em `~/Projects/Github/MyEmacs`, depois `cd ~/.config/emacs-vanilla && git stash && git pull && git stash pop`.
> **Anterior:** `29d7dab` — ponto do dirvish refatorado (extensões ativas, olivetti 0.85, Zen reading).

> **SAVE POINT ANTERIOR:** `29d7dab` — `docs: record dirvish emerge/peek/git-msg activation in TODO and roadmap`
> **Estado (aprovado pelo usuário: "ficou perfeito"):** dirvish refatorado (ícones/sidebar/hooks corretos), olivetti responsivo `0.85`, Zen reading, RAG de extensões atualizado e extensões dirvish ativas — `git-msg` no painel principal, `E` → `dirvish-emerge-mode` com 6 grupos padrão, `dirvish-peek-mode` global com debounce 0.5. Emacs de teste (`~/.config/emacs-vanilla`) abre sem erros, sincronizado com `origin/main`.
> **Reverter:** `git revert 29d7dab` (preserva histórico) ou `git reset --hard 29d7dab` (destrói commits seguintes) em `~/Projects/Github/MyEmacs`, depois `cd ~/.config/emacs-vanilla && git stash && git pull && git stash pop`.
> **Anterior:** `aad799c` (RAG extensions) — útil como ponto anterior ao experimento das extensões.

- [x] **Correção completa da stack de IA (gptel 0.9.9.5):**
  - **Backends Zen corrigidos:** `zen.opencode.ai` era **NXDOMAIN** — hosts reais: `opencode.ai` + `:endpoint "/zen/v1/chat/completions"` (OpenAI) e `"/zen/v1/messages"` (Anthropic). Keys via `(getenv "OPENCODE_ZEN_API_KEY")` / `(or (getenv "GEMINI_API_KEY") (getenv "GOOGLE_API_KEY"))` (exportadas por `/etc/api-keys.sh` do agenix).
  - **Ollama corrigido:** modelo `qwen3.5:latest` não existe → `qwen3:0.6b` (modelo real instalado).
  - **API do gptel-request corrigida:** 0.9.9.5 NÃO aceita `:backend`/`:model` (keywords reais: `:callback :buffer :position :context :system :stream :schema :transforms :fsm`). Criado helper `+carlos/gptel-request` (buffer `*gptel-request*` + `gptel-backend`/`gptel-model` buffer-local) e o commit IA em `custom-git.el` reescrito para usá-lo (antes: erro de keyword).
  - **gptel-org eliminado:** não existe `gptel-org-mode` em 0.9.9.5 — integração Org é automática (`derived-mode-p`). Removido bloco no-op.
  - **Código morto removido:** `mcp` e `superchat` (não instalados, `:if` silencioso) + display rule do superchat. `gptel-agent` mantido (registra researcher/introspector/gptel-plan/gptel-agent/executor).
  - **Novo keybinding:** `C-c C-g` (e hook `git-commit-mode`) → `+carlos/gptel-insert-commit-message`.
  - **Validado ponta-a-ponta (batch vanilla):** 5/5 backends respondem PONG (Zen OpenAI, Zen Claude, Gemini, Ollama, MLX); helper e agentes OK; `just compile` zero warnings + checkdoc OK.
  - **Docs:** `docs/gptel-reference.org` e `docs/magit-reference.org` atualizados (API real, hosts Zen, remoção de `gptel-org-mode`/`:backend`/`:model`).
- [x] **Fix: `void-variable gptel-agent-dirs` (gotcha `defvar` do Emacs 30):**
  - Emacs 30: `(defvar X)` sem INITVALUE NÃO liga a variável → forward declarations peladas eram void no runtime. `gptel-agent-dirs`/`gptel-directives` corrigidas com forma pelada + guarda `boundp` (não clobberar defaults não-nil dos defcustoms); demais (`gptel-backend`/`model`, maps do vterm/eshell, `dirvish-emerge--group-overlays`, faces org) com `nil`.
  - `use-package :after` é ignorado com `use-package-expand-minimally t` → gptel-agent agora carrega via `with-eval-after-load 'gptel` (agents + presets registrados).
  - `C-c C-g` agora é global (gera commit IA); dentro do buffer de commit insere direto.
  - Validado: 16/16 arquivos compilados zero warnings, checkdoc OK, regressão batch completa verde. Commit `90e3921`.
- [x] **Suíte de testes ERT (tests/) + política de regressão:**
  - **Decisão:** ERT (nativo, zero dependência, exit code via `ert-run-tests-batch-and-exit`) em vez de Buttercup (BDD de terceiros exigiria instalação e não roda "boot completo" de forma natural).
  - **Infra:** `tests/load-tests.el` (carrega `tests/*-test.el` após o `init.el`); targets no Justfile — `test-batch`, `test-ai` (selector `myemacs-ai`), `test-network` (opt-in `EMACS_TEST_NETWORK=1`), `test-all` (= compile + checkdoc + test-batch); `check-all` agora inclui a suíte.
  - **Arquivos:** boot, keybindings, ai, ai-network (skip-unless rede), files, term, git, org, dashboard — 54 testes, 0 falhas, 6 skipped (rede/vterm).
  - **Bugs reais descobertos pela suíte (corrigidos):** `C-c i` (gptel) sombreado por consult-imenu → imenu movido para `M-s i`; `+carlos/dashboard-open`/`-refresh` declarados mas nunca definidos (void-function `C-c d d`/`C-c d r`) → wrappers de `dashboard-open`/`dashboard-refresh-buffer`; `git-commit` `C-c C-g` via hook (não aplicava em batch) → `define-key` direto no `git-commit-mode-map`.
  - **Outros:** removidos `.elc` stale do repo (usavam código antigo do `defvar nil`); rebuild do `gptel-autoloads.el` no repo (faltava → "Config Error gptel"); documentada a regra "`--eval` avalia só a primeira forma" no AGENTS.md.

## 1. Planejamento Corrente (Ações Atuais)

- [x] **Refatoração final do Dirvish (ícones, sidebar e hooks):**
  - Layout oficial de 3 painéis `(1 0.11 0.55)` e atributos `(vc-state subtree-state nerd-icons collapse file-time file-size)`.
  - Corrigir valores inválidos da API 2.3.0: `dirvish-nerd-icons-offset` (`-2` → `0.00`, é `:v-adjust` float), `dirvish-subtree-state-style` (string `"arrow"` → símbolo `'chevron`), `dirvish-subtree-icon-scale-factor` (`1.0` → cons `(0.85 . 0.10)`).
  - Corrigir `dirvish-side-open-file-action` (`'select` inválido → `nil`) e remover `dirvish-side-display-mode-line` (custom inexistente).
  - Substituir hooks inexistentes (`dirvish-mode-hook`, `dirvish-side-mode-hook`) por `dirvish-directory-view-mode-hook` + `dirvish-setup-hook`; `dired-omit-mode` agora aplica de fato em buffers dirvish.
  - Remover `diredfl`; corrigir detecção macOS no dired base (`(featurep :system 'bsd)` nunca era verdadeiro → `(memq system-type '(darwin berkeley-unix))`).
  - Remover `global-display-line-numbers-mode` (números de linha apenas em `prog-mode` via init.el).
  - Zen reading: `line-spacing 0.15` + sem line numbers em org/markdown.
  - Validado com `just check` + `just compile` (zero warnings) + teste no `~/.config/emacs-vanilla`.
- [x] **Ajuste de Truncamento do `dirvish-side`:**
  - Configurar atributos minimalistas (`vc-state`, `nerd-icons`, `collapse`, `subtree-state`) na sidebar para evitar quebra de colunas em 30 de largura.
  - Ocultar a modeline e simplificar o cabeçalho no buffer da sidebar.
  - Sincronizar e validar visualmente no Emacs Vanilla.
- [x] **Ativação das extensões Dirvish (emerge, peek, git-msg):**
  - `git-msg` adicionado a `dirvish-attributes` (só no painel principal; sidebar mantém attrs limpos `(nerd-icons collapse subtree-state)`).
  - `dirvish-emerge-groups` com 6 grupos padrão (`recent-files-2h`, `extensions` de documentos/vídeo/imagens/áudio/arquivos) + toggle `E` → `dirvish-emerge-mode` em `dirvish-mode-map` (verificado: `lookup-key` = `dirvish-emerge-mode`).
  - `dirvish-peek-mode 1` global com `dirvish-peek-key '(list :debounce 0.5 'any)` (preview no minibuffer/vertico com debounce).
  - Validado: `just check` + `just compile` (zero warnings) + batch runtime (atributos/grupos/key/mode corretos). Commit `dbc8a0b`.
- [x] **Habilitar `dirvish-ls` (ls switches on the fly):**
  - `S` → `dirvish-ls-switches-menu` (transient completo: options/toggles/actions) e `s` → `dirvish-quicksort` já existente.
  - Detecção GNU melhorada: `+carlos/gnu-ls-p` checa `ls --version` (GNU coreutils) — o `ls` do Nix no macOS é GNU mas não se chama `gls`; agora o default é `-ahl -v --group-directories-first` em vez do fallback BSD `-ahl`.
  - Testado funcional: quicksort gera `-ahl -v --group-directories-first --sort=size` sem erro de switch. RAG (`docs/dirvish-reference.org`) atualizado com todas as teclas do menu/quicksort.
- [x] **Iteração do dirvish-emerge (validação + navegação + grupos):**
  - **Validação em batch (descobertas):** o buffer principal do dirvish é `dired-mode` com `dirvish-mode-map` (o `dirvish-directory-view-mode`/special-mode é só para buffers auxiliares) — portanto o escopo `dired-mode` do `w` em `.dir-locals.el` **é lido** de volta em buffers dirvish reais; escopo `nil` também funciona. O `w` upstream deixa o buffer `.dir-locals.el` **modificado sem salvar** (Emacs 30.2 não chama `save-buffer` em `modify-dir-local-variable`) — gravar com C-x C-s após `w`. O menu `dirvish-emerge-menu` abre; grupos aplicam (8 overlays com Directories).
  - **Fix de navegação:** `dirvish-emerge-next-group` upstream crasheia (`+ nil 1`) com ponto fora de overlay de grupo (ex.: header). Criados `+carlos/dirvish-emerge-next-group`/`previous-group`/`goto-group` com guard (`ignore-errors` + fallback para `point-min`) e binds `[`/`]` em `dirvish-mode-map` (comentado: `n`/`p` são herdados do dired).
  - **Grupos globais refinados:** novo grupo `Directories` (predicate `directories`) primeiro na ordem — predicados antes de extensões (primeira correspondência vence). Ordem: Directories → Recent files → Documents → Video → Pictures → Audio → Archives.
  - Validado: `just check` + `just compile` (zero warnings) + batch runtime (binds `[`/`]`, guard sem crash em header/grupo/inativo, grupos carregados) + smoke test GUI. Commit `35a2042`.
- [x] **Bug do `ob-mermaid` resolvido:**
  - Desacoplado da inicialização do Org core e ativado dinamicamente via `:after org` no `:config`.
  - Adicionado `exec-path-from-shell` para garantir herança de caminhos Nix/npm em modo GUI no macOS.
- [x] **Substituição do Dashboard pelo `dashboard.el`:**
  - Integrado o pacote `dashboard` oficial com banner ASCII `banner.txt` e itens rápidos.
  - Configurado para carregar no boot de forma imediata via `:demand t`.
- [x] **Victor Mono com Ligaturas:**
  - Configurado o pacote `ligature` com regras completas de glifos de programação em `prog-mode`.
- [x] **Refinamento do Dashboard:**
  - Títulos estilizados em `Space Grotesk` e listagens em `Inter`.
- [x] **Fase 4 — Preparação do Cutoff:**
  - Criado o script `bin/cutoff-migration.sh` para automatizar o backup do Doom e o link simbólico definitivo.
- [x] **Ativação imediata do `which-key`:**
  - Adicionada a flag `:demand t` ao `use-package which-key` para carregar e ativar o `which-key-mode` no startup, corrigindo a inatividade em sessões interativas.
- [x] **Refatoração do Eshell (Auditoria do Opus):**
  - Removidos caminhos temporários hardcoded e de perfil Nix.
  - Aliases de IA (`oc`, `ai`, `aif`, `agy`, etc.) simplificados para invocar as ferramentas via PATH do sistema (que é importado com sucesso via `exec-path-from-shell`).
  - Atalhos de disparo rápido (`C-c A a` / `C-c A o`) simplificados utilizando a API de buffer do Eshell, deixando a alternância automática de `char-mode` sob responsabilidade do interceptor de TUI do `eat`.

## 2. Bugs Conhecidos e Pendências (Investigação)

- [x] **Warning "transient loaded before Elpaca activation":** corrida entre a ativação assíncrona da Elpaca e o `:demand t` de `transient` (custom-git.el) — agravado porque `gptel` declara `transient` como Package-Requires (custom-ai carrega antes de custom-git). **Fix:** garantir `transient` cedo no `init.el` com `(use-package transient :ensure t)` + `(elpaca-wait)` (após `use-package-always-defer`), mesmo padrão do `compat`. Com a ativação precoce, o status vira `finished` e `elpaca-continue` (elpaca.el:793) não re-ativa → warn nunca dispara. Validado em batch + cold starts GUI.
- [x] **"Duplicate item ID queued: transient" (erro no boot):** o fix acima duplicou a declaração de `transient` — `init.el:78` + `custom-git.el:15`. Com dois `:ensure t` antes do `after-init-time`, o segundo `elpaca--enqueue` (elpaca.el:842) encontra o item já enfileirado e warn/erra ("Duplicate item ID queued"), que no boot virava `Wrong type argument: elpaca, ((emacs Duplicate item ID queued: transient nil nil))`. **Fix:** remover o bloco `(use-package transient :ensure t :demand t)` de `custom-git.el` — o `init.el` já instala/ativa o transient cedo; `magit` mantém `:after transient` e `transient` é carregado no require. Validado: 3/3 cold starts batch limpos (`transient-loaded=t`, `magit-loaded=nil`, sem duplicado). `just check` + `just compile` (zero warnings).
- [x] **Aplicar gaps do zzamboni (Beautifying Org Mode in Emacs):**
  - Verificado contra https://zzamboni.org/post/beautifying-org-mode-in-emacs/ (via markitdown): seguíamos a maioria; aplicados os gaps em `custom-writing.el` — face `org-indent` herdando `(org-hide fixed-pitch)` (com `with-eval-after-load 'org-indent`, senão o defface sobrescreve), faces `org-property-value`/`org-special-keyword`/`org-verbatim`/`org-document-info` em fixed-pitch, e bullet de lista `-` → `•` via font-lock+compose-region. Não aplicado de propósito: `org-bullets` (temos org-modern) e cores hardcoded (tema ef-themes decide).
  - Validado: batch (faces + bullet composto) + `just check` + `just compile` (zero warnings).
- [x] **`eshell` falha ao abrir — `Symbol's value as variable is void: eshell-mode-map` (e `kmacro-end-and-call-macro: No kbd macro has been defined` no GUI):**
  - **Causa-raiz única (confirmada por backtrace):** o bloco `(with-eval-after-load 'eshell ... (define-key eshell-mode-map ...))` em `custom-term.el:134` rodava quando o `eshell.elc` era carregado, mas no Emacs 30 o `eshell-mode-map` só existe após o `esh-mode` carregar (módulos do eshell carregam lazy) — `(require 'eshell)` NÃO define `eshell-mode-map` (`boundp` = nil; verificado: só `(require 'esh-mode)` o define). O `(defvar eshell-mode-map)` forward-declaration em custom-term.el:19 não liga a variável em runtime (`defvar` sem valor deixa void).
  - **Efeito colateral:** o mesmo erro quebrava o `justl` no `just check` ("Cannot load justl: (void-variable eshell-mode-map)") porque `justl.el:76` faz `(require 'eshell)` → disparava o `with-eval-after-load` prematuro.
  - **Fix:** `with-eval-after-load 'eshell` → `with-eval-after-load 'esh-mode` (mapa é definido em `esh-mode.el`); esh-mode carrega quando `eshell` abre o buffer. Guard do byte-compiler (`(defvar eshell-mode-map)`) mantido.
  - Validado: batch `eshell` abre (`major-mode=eshell-mode`, `map-bound=t`), 3 keys ligadas (`C-c C-q` → `eat-toggle-char-mode`, `C-c A a`/`C-c A o` → runners), `justl` carrega OK, `just check` + `just compile` (zero warnings novos).
- [ ] **Testar config completa em GUI** (não batch) para verificar compilação do `vterm-module`.
- [x] **Org mode monocromático / sem fontes personalizadas (vs Markdown OK):** **Duas causas-raiz empilhadas em `custom-writing.el`:**
  - **(1) `org-modern-replace-stars t` inválido:** nesta versão do org-modern, `org-modern-star` é um símbolo (`'fold`/`'replace`/nil) e `org-modern-replace-stars` é string/lista de strings. Com `t`, o `org-modern-mode` explodia com `(wrong-type-argument sequencep t)` → `mapcar(org-modern--symbol t)` (org-modern.el:858) → `run-hooks` abortava o `org-mode-hook` → **`variable-pitch-mode` e o zen lambda (line-spacing) nunca rodavam** em buffers org. Fix: `org-modern-star 'replace` + `org-modern-replace-stars '("◉" "○" "✸" "✿" "✤" "✜" "◆" "▶")`.
  - **(2) `(add-hook 'org-mode-hook #'variable-pitch-mode)` era no-op no Emacs 30:** `variable-pitch-mode` é um `defalias` para `buffer-face-mode-invoke` (face-remap.el); chamado sem argumento (como hook cru) o bytecode retorna sem fazer nada (`goto-if-nil → return`). Fix: envolver em lambda `(lambda () (variable-pitch-mode 1))`. Markdown "funcionava" porque não usa org-modern (não abortava o hook) e tem `markdown-header-scaling` próprio.
  - Validado em batch: org sem "File mode specification error", `org-modern-mode=t`, remap `(default variable-pitch default)` aplicado, `line-spacing=0.15`, headings fontificados (`org-level-1`, etc.). `just check` + `just compile` (zero warnings).
- [ ] Investigar por que `consult` e `nerd-icons` não foram encontrados no MELPA durante `just check` (Se persistente nas primeiras instalações do usuário).
- [ ] Verificar se pacotes estão em rebuild no MELPA ou se foram removidos/renomeados.

## 3. Planejamento Futuro / Backlog (Ordenado por Dificuldade)

1. [x] **Revisar stack de IA (gptel + gptel-agent)** (Dificuldade: Média — listar o que está implementado, diagnosticar integrações frágeis `superchat`/`mcp`/`gptel-integrations`, alinhar agentes com a política de multiagentes e decidir o estado-alvo)
    - Etapas:
      1. [x] Listar o que está implementado (backends, agentes, gptel-org, personas, display rules) — feito parcialmente, ver resumo da conversa
      2. [x] Diagnosticar gaps e integrações frágeis (`superchat`/`llm.el`, `mcp`, código morto `+carlos/gptel-agent-project-dirs`, `~/.agents/gptel/` vazio)
      3. [x] Decidir estado-alvo e aplicar ajustes (remover código morto, ativar/remover superchat+mcp, definir agentes por projeto)
      4. [ ] **Etapa de teste da stack de IA:** validar em `~/.config/emacs-vanilla` cada entrada — `C-c i` (gptel chat), `C-c I` (+carlos/gptel-agent-run), `C-c C-g` / commit IA, `C-c A a`/`C-c A o` (eshell agy/opencode), gptel-org num `.org`, e troca de backend/modelo no buffer — conferindo erro de API, modelo válido e resposta streaming
2. [ ] **Testar SuperChat com fontes instaladas** (Dificuldade: Muito Baixa - Validação visual)
3. [x] **Substituir o dashboard customizado atual por `dashboard.el`** (Dificuldade: Baixa - Concluído!)
3. [x] **Configurar Victor Mono com ligatures** (Dificuldade: Média/Alta - Concluído!)
4. [x] **Substituir o dashboard customizado atual por `dashboard.el`** (Dificuldade: Baixa - Concluído!)
5. [x] **Configurar Victor Mono com ligatures** (Dificuldade: Média/Alta - Concluído!)
6. [x] **Refinar o dashboard com a tipografia nova instalada** (Dificuldade: Média/Alta - Concluído!)
7. [ ] **Fase 4 — Cutoff (Doom → Vanilla final)** (Dificuldade: Alta - Script `bin/cutoff-migration.sh` pronto, pendente execução pelo usuário)

---
> Para o histórico cronológico detalhado de conquistas e decisões arquiteturais do projeto, consulte o [roadmap.org](file:///Users/carlosfilho/Projects/Github/MyEmacs/roadmap.org).

## 5. Auditoria e Plano Eshell, agy & opencode (Opus)

### Diagnóstico (Auditoria de `custom-term.el`)
1. **Caminhos Hardcoded (Frágeis):** A configuração antiga inseria caminhos no `eshell-path-extra` e aliases temporários do `bunx` do macOS que quebravam após reinicializações.
2. **Herança de Variáveis de Ambiente:** Corrigido. Com a inclusão global do `exec-path-from-shell`, o Emacs GUI e daemon no macOS herdam fielmente os caminhos do terminal do usuário (Nix, Homebrew, Node).
3. **Integração do `eat` (TUI):** As simulações de inputs baseadas em timers e injeção de texto foram removidas. Agora o Eshell envia a execução limpa de comandos de IA e o `eat` se encarrega de chavear o modo de caracteres para as TUIs interativas.

### Plano de Ação Recomendado (Agente Executor)
- [x] **1. Implementar `exec-path-from-shell` Globalmente** (Feito em `custom-core.el`)
- [x] **2. Refatorar Aliases de IA (Remover Hardcodes)** (Feito em `custom-term.el`)
- [x] **3. Otimizar os Atalhos de Teclado (`C-c A a` e `C-c A o`)** (Feito em `custom-term.el`)
- [x] **4. Teste e Validação** (Feito com `just lint`)

## 6. Plano de Aprimoramento da Sidebar Dirvish (Opus)

### Regra 1: Ocultar entradas especiais e arquivos indesejados
1. **Configurar atributos de exibição:**
   - Configurar `dirvish-attributes` para as views padrão do dired contendo apenas `(nerd-icons file-time file-size collapse)`.
   - Limpar o `dirvish-side-attributes` para ficar mais minimalista, utilizando `(nerd-icons collapse)` ou `(nerd-icons collapse subtree-state)`.
2. **Ocultar dotfiles e temporários:**
   - Habilitar o `dired-omit-mode` nos buffers da sidebar.
   - Configurar a variável `dired-omit-files` com um regex abrangente para combinar com dotfiles (`^\\..*`), arquivos de backup (`~+$` ou `\\~+$`) e marcações indesejadas (`^#.*#$`).
3. **Ocultar diretórios `.` e `..`:**
   - Incluir os diretórios corrente e pai (`^\\.$` e `^\\.\\.$`) no regex do `dired-omit-files` ou configurar uma variável nativa do Dirvish que lide com isso se aplicável.

### Regra 2: Desativar números de linha na Sidebar e Dired
1. **Hooks de Modo:**
   - Desabilitar a exibição de linhas (`display-line-numbers-mode -1`) de maneira explícita dentro dos buffers.
   - Adicionar essa configuração em `dired-mode-hook` ou no mais específico `dirvish-directory-view-mode-hook`.

### Regra 3: Ajustar Estilo do Buffer e Largura
1. **Configurar a Largura da Sidebar:**
   - Definir `dirvish-side-width` para um tamanho confortável, como `30` ou `35`.
2. **Limpar Interface Visual (Cabeçalho e Rodapé):**
   - Configurar `dirvish-side-header-line-format` como `nil`.
   - Configurar `dirvish-side-mode-line-format` como `nil`.
3. **Ocultar Cursor da Sidebar:**
   - Configurar `dirvish-hide-cursor` para `t`, resultando em um visual mais próximo a uma "árvore de arquivos" (file tree) típica.
