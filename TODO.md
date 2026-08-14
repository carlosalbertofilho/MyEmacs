# TODO — Planejamento Ativo e Backlog (MyEmacs)

> **Histórico de planos concluídos (0.5–1.0):** todos implementados, validados e
> arquivados no [roadmap.org](roadmap.org) (Linha do Tempo). Este arquivo mantém
> apenas pendências ativas, backlog futuro e decisões registradas.
> Última revisão e arquivamento: 2026-08-12.

## 0. Plano Diretor — Ambição e Pipeline de Execução (reorganizado 2026-08-12)

> **Roteamento de IA (2026-08-10, concluído):** Gemini free tier
> (`gemini-3.5-flash`) passou a ser a 1ª escolha de chat/quick/grammar em
> todos os hosts, com OpenCode Zen free (`big-pickle`/`*-free`) como 2ª e
> Local (MLX/Ollama) apenas como fallback final — ver roadmap.org.

### A Ambição (north star)

**Magent/gptel como driver do Emacs** (§1e): o agente **opera o editor** como um
parceiro de pareamento em vez de cuspir código para revisão. Em vez de escrever
uma função inteira, o modelo expande um **tempel snippet** e **preenche apenas
as lacunas** — usando o buffer vivo, flycheck/LSP para validar e corrigir em
loop, e xref para resolver símbolos reais (sem alucinar nomes).

Exemplo concreto (alvo): "adiciona um helper para X" → `lsp_navigation` resolve
o símbolo → `snippet_expand` insere o esqueleto em point → o modelo preenche só
os campos → `flycheck_errors` valida → corrige até zero erros. Nada de bloco
inteiro colado.

### Pipeline de execução (do chão até a ambição)

**Etapa A — Fundação (chão estável; itens paralelos, baixo risco):**
1. **Fluxo de dev Elisp** (§1h — CONCLUÍDO 2026-08-12) — gerador de testes ERT via IA (`C-c D e`), bloco REPL `(when nil ...)` (`C-c D b`), prompts centralizados e docs RAG (`docs/dev-workflow.org`).
2. **Robustez de infra** (§1g — decidir migrar `:ensure (:wait t)` ou arquivar;
   §1b — guard de runtime do jinx, opcional) — quick-wins de
   portabilidade/estabilidade; não bloqueiam a Etapa B.

**Etapa B — Motor (modelo + contexto sob controle; 3 antes de 4):**
3. **Modelo com tool-calling confiável** (§1c — CONCLUÍDO 2026-08-12): Benchmark executado e default configurado.
4. **Contexto sob controle (100% Automático)** (§1d — CONCLUÍDO 2026-08-12): Opção 4 Híbrida: cache de prefixo estável (zero-loss) + auto-compactação automática por threshold de 60% da janela do modelo em segundo plano.

**Etapa C — A Ambição (5 → 6 → 7; depende da Etapa B):**
5. **Fase A — Tools curadas** (§1e — CONCLUÍDO 2026-08-12) — catálogo **enxuto** (3 tools): `flycheck_errors`, `lsp_navigation`, `snippet_expand`; com testes na suíte ERT.
6. **Fase B — Driver do buffer vivo** (§1e) — `buffer_edit` + workflow snippet → lacunas → flycheck → corrigir (o "preencher só as lacunas").
7. **Fase C — Loop de auto-correção como skill/workflow** (§1e).

## 1. Backlog Ativo (Pendências e Planos Futuros)

### 1a. Magent como Driver do Emacs — Fase B & C (Operação em Buffer Vivo)

**Objetivo:** Transformar o Magent de operador estático de arquivos para operador de buffers interativos em point/região do usuário.

1. **Fase B — Driver do buffer vivo (pareamento de verdade):**
   - Implementar `buffer_edit`/`buffer_insert` operando diretamente no buffer do usuário (point/região).
   - Estabelecer um **contrato de sessão**: apenas um "dono" do buffer por vez, coordenado com `read_buffer` (estado vivo) e com cancelamento pela FSM do Magent.
   - Definir fluxo estruturado de preenchimento de lacunas: `snippet_expand` → preencher placeholders → `flycheck_errors` → corrigir.
   - **Riscos a mitigar:** Concorrência com edição manual do usuário, escopo e granulação de permissões, suporte a undo unificado, e degradação de performance sob contexto pesado.
2. **Fase C — Loop de auto-correção como skill/workflow:**
   - Criar uma skill declarativa reutilizável (em `.magent/skills/`) para formalizar o fluxo: escrever → analisar flycheck → corrigir → usar LSP/Xref para resolver símbolos.

### 1b. Validação Interativa da Stack de IA (GUI)

**Objetivo:** Validar o fluxo interativo das integrações em modo GUI no ambiente `~/.config/emacs`.

- Validar interativamente as seguintes portas de entrada de IA:
  - `C-c i` (chat gptel) em modo interativo.
  - `C-c I` (`+carlos/gptel-agent-run`) e troca dinâmica de presets.
  - `C-c C-g` no buffer de commit (Magit transient `c g`).
  - `C-c A a` / `C-c A o` (eshell agy/opencode).
  - gptel-org integrado em arquivos `.org`.
  - Troca dinâmica de backend e modelo no buffer e verificação de streaming.

### 1c. Diagnóstico e Decisões Pendentes de Infraestrutura

1. **Elpaca 0.2.0 e Ativação Síncrona (`:ensure (:wait t)`):**
   - *Status:* O plano de migrar todos os pacotes de inicialização crítica para `:ensure (:wait t)` foi adiado porque a suíte e o boot estão estáveis após as políticas de limpeza de build stale.
   - *Decisão Pendente:* Manter o plano original do §1g (substituir `(elpaca-wait)` no nível superior e usar `:ensure (:wait t)` em `treesit-auto`, `reformatter`, `flycheck`, e `apheleia`) para aumentar a robustez da ativação ou arquivar o plano se o comportamento se mantiver sem novas falhas.
2. **Guarda de Runtime para Módulo Nativo Jinx:**
   - *Status:* O plano de encapsular a inicialização do `jinx-mode` em `+carlos/jinx-mode-if-available` (evitando erro de compilação do `.dylib` em builds parciais do repo que quebram hooks de `prog-mode`) foi adiado porque o `skip-unless` nos testes mitigou o problema da suíte ERT em modo batch.
   - *Decisão Pendente:* Aplicar ou não o helper seguro `+carlos/jinx-mode-if-available` em `custom-jinx.el` para portabilidade universal ("Works anywhere").
3. **epdfinfo Nix aborta ao ser spawnado pelo Emacs no macOS:**
   - *Problema:* O binário `epdfinfo` derivado do Nix aborta com `Abort trap: 6` devido a problemas de `fork()` e glib no macOS ao ser spawnado como subprocesso directo do Emacs. Funciona normalmente via shell.
   - *Ações futuras ao abordar:*
     - Testar um wrapper em C compilado que faça `fork` e `exec` próprio.
     - Avaliar aplicar `advice` em `pdf-info-process-assert-running` para spawnar via shell.
     - Alternativamente, compilar `epdfinfo` via poppler do Homebrew.
4. **agent-shell como subagente do Magent:**
   - *Ideia:* Usar o agent-shell standalone (Aider, Cursor, Claude Code) como subagente especializado delegado pelo Magent (através de `spawn_agent` / `wait_agent`) apenas para refatorações complexas de múltiplos arquivos.
   - *Status:* Adiado. Preservar o FinOps local e o roteador de custo zero por enquanto.

### 1d. Controle de Contexto estilo opencode + Roteamento de Modelos pelo Orquestrador (2026-08-13)

**Objetivo:** Evoluir o controle de contexto dos agentes do Magent no estilo do opencode (compactação inteligente guiada por objetivo, preservando estado acionável em vez de truncar) e dar ao agente orquestrador o poder de decidir o modelo mais adequado para cada subagente/tarefa.

1. **Compactação estilo opencode:**
   - *Hoje:* `+carlos/magent-auto-compact-check-and-run` (lisp/custom-magent-context.el) dispara no `turn-end` quando `output-len` > 60% da janela (fallback 16384) e chama `magent-runtime-session-compact` com uma instrução estática de preservação.
   - *Queremos:* compactação progressiva que resuma o *prefixo antigo* mantendo os últimos N turns crus; resumo orientado a objetivo (tarefa corrente, decisões, arquivos tocados, comandos de verificação, próximos passos) e descarte de transcripts reproduzíveis (leitura de arquivos que voltam via RAG/AGENTS).
2. **Roteamento de modelos pelo orquestrador:**
   - *Hoje:* `+carlos/gptel-dynamic-router-advice` roteia estaticamente por buffer/keywords; subagentes usam perfis fixos (`explore`/`general` → Gemini 3.1 Pro).
   - *Queremos:* o orquestrador decide por tarefa (via `spawn_agent` com modelo explícito ou tool de seleção), priorizando **local (grátis) → free tier (Gemini/Zen free) → pago (Zen Claude)**, com tabela de custo/quota injetada e guardrails para não pagar quando local/free basta nem forçar modelo fraco em raciocínio profundo.
   - *Interação:* validar com os perfis fixos de subagentes e com a exclusão do roteador em requests gerenciadas (magent-managed).

**Decisões de design (2026-08-13):**
- **Mecanismo de roteamento:** decisão por *raciocínio + tool* — o orquestrador recebe um "menu de modelos" (custo/quota/disponibilidade) no system prompt e chama uma tool `select_model` que valida e retorna o modelo; o subagente herda a escolha. Guardrails no código.
- **Prioridade do resumo:** *estado do projeto* — tarefa corrente, decisões+justificativas, arquivos tocados com motivo, comandos de verificação, próximos passos; descartar transcripts reproduzíveis.
- **Gatilho da compactação:** *threshold + milestones* — medir tokens corretamente (input+output vs. janela real) e compactar também em marcos da tarefa (fim de etapa/subagente).
- **Teto por complexidade:** *complexidade primeiro* — raciocínio profundo pula para free/paid direto; "local primeiro" vale para o que o local resolve bem.

**Plano de Ação — Fase A: Roteamento de modelos pelo orquestrador (custom-magent.el) — CONCLUÍDO 2026-08-13**

- **A1. Menu de modelos (derivado em runtime, não defcustom estático):** `+carlos/magent-model-tier-config` (backends por tier: free = Gemini/OpenCode Zen; paid = Zen Claude/OpenCode Zen); `+carlos/magent-model-per-tier-max` (cap 3 por backend/tier); `+carlos/magent-model-menu-default` (fallback estático sem gptel); `+carlos/magent-classify-model` (local/free/paid via `+carlos/magent-model-cost`); `+carlos/magent-local-installed-models` (query `/v1/models` MLX ou `/api/tags` Ollama, timeout 2s); `+carlos/magent-model-menu-entries` deriva cloud de `gptel-backend-models` e local dos modelos instalados. `+carlos/magent-model-max-tier` (local|free|paid, default `paid`) como teto do usuário.
- **A2. Injeção do menu no system prompt:** função `+carlos/magent-model-menu-render` gera a tabela (tier, backend, modelo, custo, disponibilidade local via `+carlos/local-ai-server-ping-p`); inserir como nova regra **9. MODEL SELECTION** no const `+carlos/magent-system-directives` (lisp/custom-magent-tools.el), mandando o orquestrador escolher por tarefa (complexidade primeiro) e chamar `select_model` antes de `spawn_agent`. O const precisa virar função (ou concat) para refletir disponibilidade em runtime.
- **A3. Tool `select_model`:** registrar em `+carlos/magent-register-tools` (lisp/custom-magent-tools.el) via `gptel-make-tool` (nome `select_model`, args `task_description` string + `agent` string opcional + `complexity` enum opcional `simple|moderate|deep`). Handler `+carlos/magent-tool-select-model`:
  - Heurística de complexidade (se não informado): keywords de raciocínio profundo (refactor, architecture, debug, plan, schema, "review") → `deep`; senão `simple`/`moderate`.
  - Escada (complexidade primeiro): `deep` → free (Gemini → Zen free) → paid (se free indisponível); `simple`/`moderate` → local (se ping online) → free → paid. Nunca acima de `+carlos/magent-model-max-tier`.
  - Retorna JSON `{:backend B :model M :tier T :reason R}` e registra o override em `+carlos/magent-subagent-model-overrides` (alist `agent-name → (backend . model)`, transient).
- **A4. Override dinâmico no advice de perfil:** em `+carlos/magent-subagent-apply-profile` (lisp/custom-magent-subagent.el), antes de consultar `+carlos/magent-subagent-profiles`, ler o override transiente de `+carlos/magent-subagent-model-overrides` (consumir com pop); se inválido (`gptel-get-backend` nil) → log + fallback perfil estático. O advice já aplica via `cl-struct-slot-value` no request-state do filho — sem tocar sources do elpaca.
- **A5. Interação roteador dinâmico:** requests de subagente já são excluídas via `+carlos/magent-managed-request-p` (custom-ai.el:566) — apenas documentar.

**Plano de Ação — Fase B: Compactação estilo opencode (custom-magent.el) — CONCLUÍDO 2026-08-13**

- **B1. Instrução orientada a estado:** `+carlos/magent-build-compaction-instruction` (lisp/custom-magent-context.el) gera a instrução com: estado do projeto (raiz + branch/rev git), objetivo corrente (preview da sessão via `magent-runtime-session-current` → thread → `magent-thread-preview`), base estática `+carlos/magent-preservation-instruction` e regras de descarte ("não replique transcripts reproduzíveis; preserve os últimos 3 turns crus; consulte TODO.md/roadmap.org"). `+carlos/magent-compact` usa a instrução dinâmica.
- **B2. Medição correta de tokens:** eventos de lifecycle NÃO carregam `:input-len`/`:output-len` (confirmado no emit-site) e `magent-runtime-session-token-count` não existe. `+carlos/magent-turn-tokens` resolve o turno por `:turn-id` na cadeia runtime-session → magent-session → thread → `magent-thread-find-turn` e soma o `usage` real do gptel (`:input` + `:output`); fallback: estima por `magent-thread-turn-input` (chars/4). Acumula em `+carlos/magent-context-estimated-tokens`.
- **B3. Gatilho por milestones:** sink passa a despachar por `:type` — `subagent-stop` incrementa `+carlos/magent-subagent-completions-since-compact`; `turn-end` (completed) soma tokens e decide via `+carlos/magent-compaction-decision` (puro): `immediate` acima de 60% da janela, `milestone` com ≥N subagentes (default 3) E >40% da janela.
- **B4.** `C-c A p` (`+carlos/magent-compact`) usa a instrução dinâmica (B1). **Correção de bug latente:** `magent-runtime-session-compact` exige `runtime-session` posicional (antes chamado sem → erro em runtime); agora resolve via `magent-runtime-session-current` com guarda.

**Plano de Ação — Fase B.5: Gaps da compactação (modelo barato + guarda anti-crescimento + fronteira segura)** ✅ CONCLUÍDO 2026-08-13 (roadmap.org; suíte 235/228/0/7 no repo)

*Contexto (decisões do usuário 2026-08-13):* (1) compactação usa modelo local se online E tokens da sessão ≤ teto; acima do teto usa flash free da nuvem (nunca pago); (2) commit com IA passa a usar o selecionador inteligente em AMBOS os caminhos (`generate-commit-message` e `insert-commit-message`); (3) guarda anti-crescimento compara total REAL da sessão antes vs depois (tolerância 1.05), espelhando `COMPRESSION_FAILED_INFLATED_TOKEN_COUNT` do Gemini CLI.

- **B5.1. Modelo barato para compactação (routing no advice):** em `+carlos/magent-subagent-apply-profile` (custom-magent-subagent.el:43), quando `agent-name == "compaction"`, resolver via novo `+carlos/magent-resolve-cheap-model` (em custom-magent-context.el) em vez de perfil estático. A helper resolve: `local` se `+carlos/local-ai-server-ping-p` E `(+carlos/magent-session-total-tokens)` ≤ `+carlos/magent-compaction-local-max-tokens` (defcustom, default 32000) via `+carlos/magent-resolve-model 'simple t`; senão o primeiro modelo `free` da nuvem (let-binding `+carlos/magent-model-max-tier` = 'free + `+carlos/magent-resolve-model 'simple nil`) — NUNCA paid. nil sem gptel → herança normal. `declare-function` em subagent.el (context.el carrega depois). ✅
✅ **B5.2. Commit com selecionador inteligente:** `+carlos/gptel-generate-commit-message` e `+carlos/gptel-insert-commit-message` (custom-git.el:76/107) trocam `+carlos/gptel-quick-local-backend`/`-model` hardcoded por `+carlos/magent-resolve-cheap-model` (falha segura: fallback para os quick vars atuais se resolução nil). Resolve no momento da chamada (local se online, senão flash free).
✅ **B5.3. Guarda anti-crescimento (gap 2):** novo `+carlos/magent-session-total-tokens` (soma `+carlos/magent-turn-usage-tokens` de todos os turns via `magent-thread-turns`). `+carlos/magent-compact` captura `before` antes de `magent-runtime-session-compact`, passa `:on-complete (status result)`: se `completed` E `after < before*1.05` → zera contadores, seta `+carlos/magent-last-compaction-time`, limpa `+carlos/magent-last-compaction-failed`; senão seta `+carlos/magent-last-compaction-failed t` (log com before→after). Sink `+carlos/magent-auto-compact-check-and-run` NÃO compacta automaticamente enquanto o flag estiver setado (manual `C-c A p` sempre permite).
✅ **B5.4. Fronteira segura de corte (gap 3):** novo `+carlos/magent-turn-closed-p` (turno fechado = todo tool-call do turno tem seu result dentro do próprio turno, via `magent-thread-turn-items`/`magent-thread-item-*`) e `+carlos/magent-safe-compaction-boundary (thread &optional keep-count keep-ratio)` — caminha da cauda acumulando turns até `keep-count` (default 3) OU `keep-ratio` (default 0.3) dos chars de input; avança a fronteira enquanto o turno anterior não estiver fechado (nunca corta assistant-with-pending-tool-calls do result). `+carlos/magent-build-compaction-instruction` embute "resuma turns 1..N-1, preserve N..fim verbatim" + aviso de não dividir tool-calls. Fronteira é guiada por instrução (não há patch no source pinado do magent).
✅ **B5.5. Testes:** (a) `+carlos/magent-resolve-cheap-model` — local quando online e ≤ teto, free quando offline/acima (mock `+carlos/local-ai-server-ping-p` + args); (b) `+carlos/magent-session-total-tokens` — soma real de turns sintéticos (`magent-thread-turn-create` com `:usage`); (c) guarda — `:on-complete` com `after < before` zera contadores; com `after >= before` seta flag e sink pula; (d) `+carlos/magent-turn-closed-p` + boundary — turno aberto avança a fronteira (turns sintéticos com items via `magent-thread-item-create`); (e) commit — resolução escolhe local/free. Regra: usar sempre funções puras ou parâmetros opcionais (accessors de struct não são mockáveis).

**Plano de Ação — Fase C: Loop de eventos do chat mais informativo (custom-magent.el)** — EM ANDAMENTO 2026-08-14 (C1/C2/C3/C4/C5 implementados em `lisp/custom-magent-ui.el`; testes em `tests/magent-ui-test.el`; aguarda validação interativa no prod)

*Hoje:* o pipeline já emite eventos ricos, mas o buffer *Magent* mostra pouco: tool call = linha resumo conciso (agente + comando/path truncado) e resultado preview 150 chars (`magent-agent-loop-tool-result-summary`); subagente = só `:ui-visibility` summary-only (job id + status, sem tool calls do filho nem modelo usado); reasoning só entra se `magent-include-reasoning t`; sem duração/exit-code/token por tool e sem badge de modelo. Renderização: `magent-agent-loop` emite `tool-call-start/end` (magent-agent-loop.el:446/479) → `magent-acp.el:609-651` mapeia para updates do agent-shell.

*Objetivo:* transformar o *Magent* em painel de atividade ao vivo (estilo opencode): cada ação do modelo visível com o detalhe necessário e o modelo responsável, subagentes com ciclo de vida completo, sem quebrar a FSM nem inflar o contexto.

- **C1. Sink de atividade de UI `+carlos/magent-ui-activity-sink`:** registrado via `magent-lifecycle-events-add-sink`; consome `turn-start/end`, `tool-call-start/end`, `subagent-start/stop` e insere linhas compactas timestampadas no buffer *Magent* (`agent-shell-insert` se disponível; fallback `message`), com faces `+carlos/magent-ui-*` (tool ok/fail, reasoning, subagent, turn). Sink não deve lançar erro (o dispatch já captura, mas manter custo O(1) no hot path).
- **C2. Detalhe de tool call enriquecido:** advice em `magent-agent-loop-tool-call-summary` (magent-agent-loop.el:298) adicionando por tool: `bash` → cwd+comando+elapsed; `edit_file`/`write_file` → path+bytes; `grep` → pattern+path; `spawn_agent` → agent+task_name+modelo (integra Fase A); e no `tool-call-end` exibir duração (elapsed) + status (✓/✗) + exit-code (o evento já carrega `:exit-code` e `:result-summary`).
- **C3. Ciclo de vida do subagente visível:** sink nos eventos de subagente/job (`subagent-start/stop`; transições via `magent-tools--render-agent-job-event`, que hoje usa summary-only em magent-tools.el:1233) mostrando: `spawned explore (job abc) → running → completed/failed`, o **modelo efetivo** (override da Fase A / perfil estático) e um resumo do relatório final — sem vazar o transcript do filho (diretriz 8 do orquestrador).
- **C4. Badge de modelo por turno/agente:** no `turn-start`, capturar backend/modelo ativo (`gptel-backend`/`gptel-model`) e exibir `[turn N · Gemini gemini-3.5-flash]`; nos eventos de subagente, exibir o modelo do filho resolvido.
- **C5. Reasoning colapsável:** aproveitar o acumulador existente (`+carlos/magent-fsm-reasoning-accumulator-a`, lisp/custom-magent-fsm.el) e renderizar o reasoning sob um header colapsável (overlay com face) no buffer, respeitando `magent-include-reasoning`.
- **Restrições:** não modificar sources do elpaca (só advices/sinks no custom-magent.el); respeitar `:ui-visibility` (não vazar transcripts de subagente); não interferir no threshold de compactação (B3) nem na FSM.


**Testes ERT (tests/magent-test.el ou novo tests/routing-test.el)**
- `myemacs-magent-select-model-deep-skips-local` — `deep` nunca cai no local.
- `myemacs-magent-select-model-simple-prefers-local-when-online` — local online vence free.
- `myemacs-magent-select-model-free-over-paid` — free disponível nunca usa paid.
- `myemacs-magent-select-model-respects-max-tier` — teto `free` bloqueia `paid`.
- `myemacs-magent-subagent-dynamic-override-beats-static-profile` — override transiente aplica antes do perfil estático.
- `myemacs-magent-compact-instruction-contains-state-sections` — instrução gerada tem todas as seções de estado.
- `myemacs-magent-compact-milestone-triggers-at-threshold` — contador de milestones + limiar dispara compactação.
- `myemacs-magent-ui-activity-sink-format` — sink formata linha correta por tipo de evento (tool/subagent/turn) a partir de plist de evento fake.
- `myemacs-magent-ui-tool-call-detail-advice` — advice de resumo adiciona elapsed/exit-code/status e detalhe por tool (spawn_agent mostra modelo).
- `myemacs-magent-ui-subagent-lifecycle-lines` — transições spawned→running→completed/failed com modelo efetivo.
- `myemacs-magent-ui-model-badge-on-turn-start` — badge `[turn N · backend modelo]` captura backend/modelo ativos.
- Mocks (sem rede): `+carlos/local-ai-server-ping-p`, `gptel-get-backend`, registro de override, sink de eventos, `agent-shell-insert` (buffer simulado).

**Docs e Portões**
- `docs/magent-reference.org`: nova tool `select_model`, menu de modelos, seção de contexto/compactação, e seção de UI/eventos (loop informativo, subagentes, badges).
- `docs/ai-providers-reference.org`: nota sobre decisão de modelo pelo orquestrador.
- `just lint` (compile+checkdoc), `just test` prod, `just sync` + `just compile-prod` + `just check-prod`, `just test-all`.
- Atualizar roadmap.org e esta seção do TODO.md ao concluir.


## 2. Decisões Registradas

- **Fase C — Loop de eventos do chat mais informativo (2026-08-14):** Implementado o painel de atividade do Magent em `lisp/custom-magent-ui.el`: sink `+carlos/magent-ui-activity-sink` renderiza linhas timestampadas no buffer *Magent* (turn-start/end com badge de modelo, tool-call-start/end com duração+exit-code+preview, subagente com ciclo de vida completo, reasoning preview). Advice `+carlos/magent-ui-tool-call-summary-a` enriquece `spawn_agent` (modelo efetivo) e `bash` (cwd). Gotcha descoberto: accessors de `cl-defstruct` (`magent-agent-job-id`) são inlined no `.elc` → mock por `symbol-function` é inócuo; testes usam `magent-agent-job-create` real. Suíte repo: 248/241/0/7. Deploy `df524b7` + sync + gates prod (compile-prod zero-warning, check-prod OK, 248 testes) — validação interativa em andamento.

- **Orquestrador delegar edições complexas a subagentes (2026-08-14):** Durante a validação interativa da Fase C no prod, o orquestrador local (MLX) tentou editar `TODO.md` do projeto lotofacil diretamente via `edit_file` e falhou com `old_text not found` (alucinou o conteúdo do arquivo: omitiu `, as the endpoint requires authenticated access`, trocou `to maintain connectivity` por `for connectivity`). Diagnóstico: o `edit_file` do Magent exige match byte-a-byte único (`search-forward` literal) e o modelo local não reproduz conteúdo de arquivo com fidelidade. **Decisão: reforçar a delegação em vez de relaxar o match** (safety by design). Mudanças em `lisp/custom-magent-tools.el`: (1) directiva nº 8 `SUBAGENT DELEGATION` agora é HARD RULE "você só orquestra, não implementa" — qualquer edição complexa de arquivo (rewrite de documentos, planning files, refactoring, geração de conteúdo) deve ser delegada via `select_model` → `spawn_agent` (`explore`/`general`) → `wait_agent`, com instrução ao subagente de ler o alvo com `read_file` antes de editar (match exato); apenas correção de uma linha com texto recém-lido é edit direta aceitável; (2) `+carlos/magent-deep-task-keywords` ganhou verbos de edição (`edit`/`editar`/`update`/`atualiz`/`rewrite`/`reescrev`/`implement`/`planning`) para que tarefas de alteração de arquivo sejam `deep` → nunca o tier local. Testes: `myemacs-magent-directives-enforce-edit-delegation` (fsm) + `myemacs-magent-task-complexity-edit-deep` (routing). Suíte repo: 250/243/0/7.

- **Fix: Magent "travou/não respondeu" ao colar buffer de compilação (2026-08-14):** Causa-raiz encontrada com repro headless + backend real. No host agnes o Magent usa MLX Local (`gemma-4-e2b-it-4bit`) como orquestrador. Esse modelo é de raciocínio; o `mlx_lm.server` aplica default de **512 completion tokens** quando o gptel não envia `max_tokens` (`gptel-max-tokens` nil). Com o buffer de compilação colado, o reasoning consumia todo o orçamento e nunca emitia `content` → `empty-completion` (resposta vazia) → sintoma "não respondeu". Fix: `:request-params '(:max_tokens 8192)` no backend "MLX Local" (`custom-ai.el`), validado E2E (vazio 16s → análise correta 26s); teste de regressão `myemacs-ai-mlx-local-max-tokens`. Deploy `0eb2397`. Descoberta lateral: `/etc/api-keys.sh` referencia `/run/agenix/google-api` (inexistente; mount real `/run/agenix.d/1/google-api`), então chaves nunca carregam via config — ajuste é do MyMachine, não do MyEmacs.

- **Auditoria de Conformidade e Orquestração Híbrida do Agent_Smith (2026-08-13):** Executado um cenário híbrido de 4 modelos (Gemma 4 2B local como Orquestrador, Zen Claude na nuvem como Planejador, DeepSeek R1 14B local como Desenvolvedor e Big Pickle na nuvem como Revisor) para auditar o código do repositório `Agent_Smith`. O Planejador identificou desvios arquiteturais críticos no código do colega David (ausência de servidores MCP reais em `mcp_tools_*.py`, omissão de token `<end_code>` e regex XML errada no `extractor.py`, e falhas de escape de segurança por subprocessos no `executor.py`). O Desenvolvedor (DeepSeek R1) gerou a refatoração completa em Python dos 4 arquivos com as devidas correções (incluindo o uso do SDK FastMCP do MCP e a interceptação e propagação de SystemExit/KeyboardInterrupt), a qual recebeu nota PASS da avaliação do Revisor (Big Pickle).
- **Orquestração Multiagente Local e Simulação Magent no /tmp (2026-08-13):** Validado com sucesso o fluxo de orquestração local no MacBook M2. O Gemma 4 (2B) atuou como orquestrador criando um plano JSON, delegando a análise profunda ao DeepSeek R1 (14B) e a codificação de correção ao Qwen 3.5 (9B), que invocou a ferramenta `write_file_content` para corrigir erros de um arquivo no sandbox `/tmp/magent-sandbox/broken.el`, verificado via compilador local do Flycheck com zero erros. Criados helpers robustos de limpeza de dados de resposta para suportar de forma transparente tokens de raciocínio estruturados (cons cells) do gptel.
- **Benchmark de Contexto Longo (23.5k tokens) no agnes (2026-08-13):** Executado o benchmark pesado carregando o código do repositório `MyEmacs` (~30k tokens de contexto). Gemma 4 2B (e2b) completou a análise arquitetural na GPU Metal em 14.88s (15.73 tok/s), Qwen 3.5 9B em 21.05s (11.64 tok/s) e DeepSeek R1 14B em 43.14s (13.00 tok/s). Bypassado o roteador dinâmico em testes/benchmarks locais.
- **Execução do Benchmark Real do MLX no agnes (2026-08-13):** Criado e executado o script de benchmark `scratch/benchmark-mlx.el` para medir o desempenho de cada modelo local sob a stack real do gptel/Magent. Registrados os tempos reais de resposta (tok/s e duração do turno) para atualizar a tabela de referência de hardware em produção.
- **Revisão e Limpeza de Modelos MLX (2026-08-13):** Removidos modelos antigos/redundantes em disco (`Qwen2.5-7B-Instruct-4bit` e `Qwen3-14B-4bit`), liberando **11.9 GB** de armazenamento. Adicionados os novos modelos do ecossistema MLX (`mlx-community/Qwen3.5-Coder-7B-Instruct-4bit` / `14B-4bit` e `mlx-community/gemma-4-9b-it-4bit`) à lista de suporte do backend `MLX Local` no `custom-ai.el` para otimizar codificação e raciocínio local no MacBook M2 com 24GB de VRAM.
- **Correção do MLX Local em sessões batch e Benchmark no agnes (2026-08-13):** Adicionado o parâmetro `:key "any"` ao backend de MLX Local no custom-ai.el para evitar erros de API key vazia (`wrong-type-argument stringp nil`) em execuções de testes batch/CI. O teste de rede do MLX Local em agnes passou com sucesso absoluto em apenas **1.81 segundos**.
- **Causa-raiz: `Wrong type argument: stringp, nil` em subagente Gemini = GEMINI_API_KEY ausente no Emacs GUI (2026-08-13):** O erro do filho `spawn_agent(explore)` (sessão `session-20260813-183137.json`) e de todo repro batch vem de `gptel--get-api-key` (gptel-request.el:958): o key-fn do backend Gemini (`(getenv "GEMINI_API_KEY")`) retorna nil sem a env var → `(string-trim-right nil ...)` → `wrong-type-argument stringp nil`. O Emacs GUI (Emacs.app, 34 env vars, sem keys) NÃO herda o ambiente do shell — as keys só eram exportadas pelo `~/.zshrc` → `/etc/api-keys.sh` (gerado pelo agenix, MyMachine `modules/system/agenix-env.nix`). O orquestrador (gemma/MLX) funcionava porque não precisa de key; com `GEMINI_API_KEY=dummy` o erro some (confirmação batch). **Fix:** `lisp/custom-ai.el` agora carrega `/etc/api-keys.sh` no boot (`+carlos/api-keys-file` defcustom + `+carlos/--source-api-keys-from-file`, resolvendo a forma agenix `export VAR="$(cat /run/agenix/secret)"` sem sobrescrever env já definido), espelhando o `.zshrc` para processos GUI/batch/subagentes. Testes: `myemacs-ai-api-keys-source-from-sh-file` + `myemacs-ai-api-keys-does-not-override`. Nota: os segredos só existem após `darwin-rebuild switch` (agenix descriptografa para `/run/agenix/*`).
- **Suporte à Inserção Física de Snippets do Tempel (2026-08-13):** Aprimorada a ferramenta snippet_expand para suportar a ação `:action "insert"`, invocando fisicamente o tempel-insert na posição do cursor do usuário no buffer ativo. Desenvolvidos testes unitários com mocks para garantir o fluxo de listagem, inspeção e inserção de templates.
- **Remoção de cenários obsoletos e criação do live-scenario com suporte a LSP (2026-08-13):** Removidos magent-driver-demo-scenario.el e magent-driver-test-scenario.el. Criado magent-driver-live-scenario.el configurando sandboxes em Elisp e Python (Eglot/LSP) para validar a teoria do buffer vivo. Protegido lsp_navigation contra travamentos de prompts de TAGS do etags em diretórios sem arquivo TAGS físico.
- **Correção de compilação em custom-magent.el (2026-08-13):** Declaradas globalmente no topo de custom-magent.el com valor inicial nil as variáveis de ferramentas de gptel para evitar erros de compilation de símbolos livres (free variable). Lógica de registro movida para uma função unificada e executada de modo reativo para ambos os carregamentos (gptel e magent-tools).
- **Magent como Driver do Emacs (Fase C5) (2026-08-12):** Implementação e catalogação in-process de 3 ferramentas curadas e tipadas (`flycheck_errors`, `lsp_navigation`, `snippet_expand`), devidamente autorizadas sob permissões individuais e testadas via suíte ERT.
- **Gestão de Contexto Automática (2026-08-12):** Implementada a estratégia híbrida 100% autônoma de contexto: isolamento de dados dinâmicos para acionar Context Caching na nuvem (zero-loss de cache de prefixo) e auto-compactação automática por threshold (>= 60% da janela do modelo) via sink do ciclo de vida `turn-end`.
- **Benchmark de Modelos no aa102-006l (2026-08-12):** Validado o sweet-spot dos modelos locais no Ollama (hardware leve): `qwen2.5-coder:1.5b` (ultra rápido, turn em 4s) e `qwen2.5-coder:3b` (excelente balanço de codificação local, turn em 7s).
- **Consolidação de Dev Elisp (2026-08-12):** Fluxo nativo (IA → REPL → ERT) estruturado com gerador de testes ERT via IA (`C-c D e` / `C-c C-e`) e helper de blocos scratch REPL seguros (`C-c D b` / `C-c C-b`).
- **Resolução do Timeout de 120s e Resposta Vazia do Magent (2026-08-12):** Corrigido o bug crítico de aridade em streaming no gptel-gemini (redefinida `magent-llm-gptel--sanitize-after-parse-response-a` com `&rest args`), eliminada a FSM de orquestração legada e adicionado o limitador inteligente de tamanho de mensagens longas no echo area.
- **org-noter nov+djvu (2026-08-10):** instalados `nov` (MELPA, EPUB) e `djvu` (GNU ELPA) via Elpaca; `org-noter-supported-modes` fixado em `:custom` com os 4 modos (doc-view/pdf-view/nov/djvu); binários DjVuLibre providos pelo Nix do MyMachine (`djvulibre` + `djview` em `home/carlosfilho/emacs.nix`). Elimina os warnings `package not found`/`ATTENTION` do boot sem dependência morta.
- **SuperChat:** removido — código morto eliminado em 2026-08-06 (não testar visual).
- **Fase 4 — Cutoff (Doom → Vanilla final):** **manter modelo espelho** — `~/.config/emacs` continua clone sincronizado via `just sync`; NÃO converter em symlink (decisão 2026-08-09). Script `bin/cutoff-migration.sh` permanece disponível se a decisão mudar.
- **agy/copilot no Emacs (exceção a "CLIs no terminal"):** mantidos como exceção consciente — `+carlos/agy-prompt` (`C-c A g`) e `+carlos/copilot-explain-region` (`C-c A c`) (AGENTS.md §0, 2026-08-09).
- **Limpeza de artefatos de build:** política criada (2026-08-09) — `just clean`/`clean-prod` (`.elc`/`.eln` + `eln-cache/`) e `just rebuild`/`rebuild-prod`. Rebuild completo em repo e prod + `just test-all` OK. Ver AGENTS.md "Política de Limpeza de Artefatos de Build" e roadmap 2026-08-09.
- **Formato de tool call do Magent (DSML):** adicionada diretriz nº 6 em `+carlos/magent-system-directives` ensinando o formato textual parseável (`<tool_calls>`/`<invoke name=...>`/`<parameter name=...>`), injetada no system message via advice `:filter-return` em `magent-agent--compose-system-message`. Motivo: Qwen3.5-9B sob contexto pesado emitiu `<tool_call>/<function=>` (Claude-XML) como reasoning, que o parser do magent ignores (2026-08-10). Testes: `myemacs-magent-dsml-*` (150 testes, 0 falhas).
- **Magent: tool call no reasoning nunca executa (reforço do DSML, 2026-08-10):** diagnóstico — o magent só parseia DSML do stream de content (`magent-llm-gptel--emit-completed-or-textual-tool-calls`); reasoning vai direto para `magent-llm-reasoning-delta-event` e qualquer `<tool_call>` escrito lá é silenciosamente descartado. O gatilho da degradação do 9B foi um `find | head -50` → SIGPIPE (exit 141) → magent reporta tool FAILED. Reforços: diretriz 6 agora proíbe tool calls em reasoning/thinking e exige nativas no FINAL; nova diretriz 7 instrui evitar SIGPIPE (`find -maxdepth`/`rg --max-count` em vez de `| head`). Reprodução batch: contexto pesado + diretriz nova = 3/3 tool_calls nativos. Testes: `myemacs-magent-directives-reasoning-ban`, `myemacs-magent-directives-sigpipe`.
- **Magent: FSM de orquestração THINK/DECIDE/RETRY (2026-08-10, REMOVIDA 2026-08-12):** criada originalmente em 2026-08-10 para mitigar turns vazios de modelos locais. Em 2026-08-12, a FSM foi **completamente removida** por introduzir retention de eventos terminais e ser superada pela correção definitiva da aridade (`&rest args`) em `magent-llm-gptel--sanitize-after-parse-response-a`. O Magent agora opera 100% no fluxo nativo do `magent-llm-gptel`.
- **Magent: sink de log read-only (2026-08-10, fix `464e196`):** `*magent-log*` fica read-only porque `magent-log-mode` deriva de `special-mode`; o sink nativo usa `inhibit-read-only`, mas o nosso `+carlos/magent-log-context` não — 107 erros `Buffer is read-only` spammaram o log na sessão real. Fix: insert envolto em `(let ((inhibit-read-only t)) ...)` em `lisp/custom-ai.el`. Teste `myemacs-magent-log-context` atualizado para abrir o buffer via `magent-log-buffer` (aplica o modo read-only) e garantir que o sink grava mesmo assim.
- **Reorganização da Tabela de Modelos Padrões (2026-08-12):** Hierarquia de modelos estruturada em 3 Tiers baseados em hardware e propósito:
  - *Tier 1 (Novem/Chat/FinOps):* `Gemini` (`gemini-3.5-flash`) como 1ª escolha global (quota gratuita, <1s TTFT), `OpenCode Zen` (`deepseek-v4-flash-free`/`big-pickle`) como 2ª escolha free, `Zen Claude` (`claude-sonnet-5`) para agente frontier.
  - *Tier 2 (Local GPU MLX agnes):* `mlx-community/gemma-4-e2b-it-4bit` (31.4 tok/s, 11s no Magent) como default local de alta velocidade.
  - *Tier 3 (Local CPU aa102-006l Ollama):* `qwen2.5-coder:3b` (7s no Magent) e `qwen2.5-coder:1.5b` (4s no Magent) no topo da lista do Ollama devido ao consumo leve de hardware. Documentado em `docs/ai-providers-reference.org`.
- **Default local MLX: gemma-4-e2b-it-4bit (2026-08-10):** benchmark dos 5 modelos locais (ver `docs/magent-reference.org`) — gemma lidera (31.4 tok/s, 2x o Qwen3.5-9B) e completou o turn do magent em 30.3s com reasoning estruturado; Qwen2.5-7B (sem reasoning, 0c) levou 99.5s e errou tool (`read` num diretório); os 14B (Qwen3/DeepSeek-R1) são lentos demais (3.7–8 tok/s). Troca do default em `+carlos/ai-local-backend` (custom-ai.el) + testes atualizados. O Qwen3.5-9B permanece como opção no backend (lista de modelos).
- Scripts de avaliação de modelos locais (2026-08-10): salvos em `bin/magent-batch-test.el` (reprodução batch do turn do magent sem GUI, drena `*magent-log*` via `MAGENT_SIM_MODEL`/`MAGENT_SIM_TIMEOUT`/`MAGENT_SIM_PROMPT`) e `bin/bench-local-models.py` (benchmark streaming tok/s, ttft, content/reasoning para MLX agnes:8081 e Ollama aa102-006l via `--ollama`). Usar para avaliar substitutos do 14B no host aa102-006l e validar a FSM real antes de trocar default. Critério de troca documentado em `docs/magent-reference.org`.

## 3. Plano de Ação — Implementação do Loop de Eventos FSM do Magent (2026-08-13)

### Objetivos:
Implementar a FSM (Finite State Machine) assíncrona orientada a eventos para o Magent e o roteamento dinâmico de backends/modelos adaptado a cada host do usuário (`agnes.local` e `aa102-006l`).

### Passo 1: Infraestrutura da FSM e Roteador de Hosts (lisp/custom-magent.el)
1. Definir variáveis globais de controle da FSM:
   - `+carlos/magent-fsm-state` (símbolo, default `'idle`): Estado atual.
   - `+carlos/magent-fsm-session` (símbolo, default `nil`): Sessão atual ativa.
   - `+carlos/magent-fsm-retry-count` (integer, default `0`): Contador de retries do turno.
   - `+carlos/magent-fsm-reasoning-buffer` (string, default `""`): Acumulador de reasoning.
2. Implementar a detecção dinâmica de host:
   - `+carlos/magent-host-profile`: Retorna `'agnes`, `'aa102-006l` ou `'default` baseando-se em `(system-name)`.
3. Criar a lógica de roteamento automático de sessão por host:
   - Na `aa102-006l`: Define o backend de orquestração como `"Gemini"` (modelo `"gemini-2.5-flash"`) e de desenvolvimento como `"Ollama Local"` (modelo `"qwen2.5-coder:3b"`).
   - Na `agnes.local`: Mantém no backend `"MLX Local"` com os pesos corretos de GPU.

### Passo 2: Interceptador de Reasoning e Parser DSML do thinking (lisp/custom-magent.el)
1. Criar sink/advice que lê o fluxo no canal `reasoning` do gptel e o armazena em `+carlos/magent-fsm-reasoning-buffer`.
2. Implementar parser regex que varre o pensamento acumulado ao fim do reasoning. Se encontrar tags de ferramentas (`<tool_call>` ou formato XML/DSML), extrai e injeta as chamadas na fila de execução física do Magent, resolvendo o problema de descarte silencioso de tool calls no reasoning.

### Passo 3: Watchdog de Latência e Fallback de Turno (lisp/custom-magent.el)
1. Criar o timer `+carlos/magent-watchdog-timer`.
2. Em cada requisição de desenvolvimento local, inicia o timer com o limite do host (8s no M2, 15s na CPU do NixOS). Se estourar antes de receber resposta, cancela a requisição ativa e aciona o fallback automático daquele turno de desenvolvimento para a API do Gemini Flash/Sonnet na nuvem.

### Passo 4: Cobertura de Testes ERT (tests/magent-test.el)
1. Escrever testes unitários simulando a execução da FSM e atestando o funcionamento do roteamento, do parser de reasoning e do fallback sob mocks de resposta.

---
> Para o histórico cronológico detalhado de conquistas e decisões arquiteturais, consulte o [roadmap.org](roadmap.org).

## 4. Plano de Ação — FSM & Submodelos (spawn_agent/wait_agent) (2026-08-13)

### Objetivos:
Corrigir o fluxo de submodelos do Magent: o orquestrador fazia `spawn_agent` e
**encerrava o turno** sem `wait_agent`, deixando o job órfão (`running`) e sem
mecanismo de re-anexação do resultado do filho ao pai. Diagnóstico completo na
sessão `session-20260813-153757.json` (projeto Agent_Smith, host agnes).

### Implementado (lisp/custom-magent.el):
1. **Directiva SUBAGENT LIFECYCLE (HARD RULE):** proíbe terminar o turno sem
   `wait_agent(job_id)`; obriga repetir `wait_agent` em timeout; exige caminho
   absoluto no prompt do subagente (subagente não recebe anexos do pai).
2. **FSM com estados `subagent-running`/`subagent-waiting`:** detecção de jobs
   pendentes via `+carlos/magent-fsm-pending-subagent-p`
   (`magent-tools--parent-session` + `magent-session-agent-jobs`).
3. **Watchdog suprimido durante wait** (`+carlos/magent-fsm-watchdog-should-fire-p`):
   wait de subagente é trabalho legítimo de longa duração, não latência.

### Cobertura de Testes ERT (tests/magent-fsm-test.el, GRUPO 9):
`myemacs-magent-fsm-subagent-jobs-var-exists`,
`myemacs-magent-fsm-reset-clears-subagent-jobs`,
`myemacs-magent-fsm-pending-subagent-{uses-cache,session-fallback,empty-is-nil}`,
`myemacs-magent-fsm-turn-end-with-pending-subagent-waits`,
`myemacs-magent-fsm-turn-start-with-pending-subagent-runs`,
`myemacs-magent-fsm-watchdog-suppressed-while-subagent-pending`,
`myemacs-magent-directives-enforce-subagent-lifecycle`.

### Pendências (próximos passos):
- **Re-anexação automática:** quando um job de subagente completa com o turno
  do pai já encerrado, o resultado ainda não é injetado automaticamente na
  conversa pai (exigiria sink de `magent-lifecycle-events` no `agent-job`).
- **Feedback de UI durante wait_agent:** o sampling FSM fica em TOOL sem
  streaming durante o bloqueio; considerar sinalizar "aguardando subagente".

---

## 5. Plano de Ação — Subagentes com Modelo Forte (perfis por agente) (2026-08-13)

> **STATUS: IMPLEMENTADO.** Items abaixo concluídos em `lisp/custom-magent.el`,
> cobertura ERT em `tests/magent-fsm-test.el` (GRUPO 10).
>
> **Nota pós-deploy (85b4d47):** a suíte do prod reprovou 2 testes do GRUPO 10 —
> `void-function (setf magent-request-context-backend)` e `wrong-type-argument
> listp`. Causa-raiz dupla: (1) `apply` tratava o `request-state` (struct) como
> arglist final → `wrong-type-argument listp`; (2) accessors gerados da struct
> indisponíveis no compile-time (magent-runtime não carregado no compile →
> `setf` virou chamada a função vazia no `.elc`). Fix: `funcall` (aridade fixa)
> + `cl-struct-slot-value` (cl-lib, sempre disponível) no advice; testes leem
> via `cl-struct-slot-value`. Prod: 202 testes, 195 esperados, **0 unexpected**.

### Objetivos:
Orquestrador = modelo leve local (no `agnes`: `mlx-community/gemma-4-e2b-it-4bit`,
MLX, janela pequena) que **só planeja, delega e sintetiza**. Subagentes
(`spawn_agent`) rodam em **modelo forte na nuvem** (decisão do usuário:
`gemini-3.1-pro-preview`, free tier Google), com janela maior, para análise de
codebase, exploração e tarefas multi-step. Delegação **automática** dirigida por
diretiva.

### Contexto técnico (verificado no pacote magent):
- O pacote **herda** backend/modelo do pai para o filho:
  `child-request-context` copia `:model`/`:backend` do request-context do pai
  (`magent-tools--agent-job-start`, `magent-tools.el:1240-1243`).
- A herança **vence** o override do agente:
  `backend = (or inherited-backend gptel-backend)`, `model = (or inherited-model
  gptel-model)` (`magent-agent.el:331-332`). Logo, sem intervenção, subagente =
  mesmo modelo do orquestrador.
- `magent-agent-process` recebe `request-state` (o `child-request-context`) como
  11º argumento opcional; `magent-request-context` é `cl-defstruct` mutável
  (`magent-runtime.el:89-119`), accessors setf-able. → **ponto de override**.

### Decisões do usuário (questionário 2026-08-13):
1. Modelo forte dos subagentes no agnes: **gemini-3.1-pro-preview** (free tier).
2. Implementação: **advice no child-request-context** (custom-magent.el).
3. Gatilho automático de delegação: **análise/exploração + tarefas multi-step**.

### Passos de implementação:
1. **`+carlos/magent-subagent-profiles`** (defcustom): alist
   `("explore" (:backend "Gemini" :model "gemini-3.1-pro-preview"))`,
   `("general" ...idem...)` — "perfis diferentes" = mapear agentes do
   `spawn_agent` a backends/modelos distintos (fonte da verdade única).
   + `+carlos/magent-subagent-profile` (resolvedor por nome de agente).
2. **Advice `+carlos/magent-subagent-apply-profile`** em `magent-agent-process`
   (`:around`): quando `agent-info` do filho tiver perfil declarado, `setf` do
   `request-state` (`magent-request-context-backend`/`-model`) para o perfil —
   o `(or inherited ...)` passa a resolver para o modelo forte. Orquestrador
   (não listado no alist) fica intocado. Registrar o advice via
   `advice-add 'magent-agent-process :around ...`.
3. **Directiva de delegação automática** em `+carlos/magent-system-directives`:
   "SUBAGENT DELEGATION" — para exploração de codebase/análise de arquivos/
   tarefas multi-step, SEMPRE `spawn_agent` (`explore` para busca/análise de
   código, `general` para trabalho multi-step), aguardar com `wait_agent`,
   sintetizar relatório resumido no turno do pai (nunca colar o transcript
   inteiro; orquestrador mantém janela curta).
4. **Testes ERT** (GRUPO 10 em `tests/magent-fsm-test.el`):
   - default do defcustom cobre explore/general → Gemini/`gemini-3.1-pro-preview`;
   - `+carlos/magent-subagent-profile` (conhecido → plist; desconhecido → nil);
   - advice aplica backend/modelo no request-state de agente com perfil e não
     altera o de agente sem perfil (faz `setf` num `magent-request-context` real);
   - `advice-member-p` do advice em `magent-agent-process`.

### Validação:
- `just compile` (zero warnings) + `just checkdoc` (sem warnings novos) no repo.
- Suíte FSM: `EMACS_TEST_DIR="$(pwd)"` + seletor `myemacs-magent-\(fsm\|host-profile\|watchdog\|directives\|subagent\)`.
- Suíte completa ERT contra o repo.
- Docs: `docs/magent-reference.org` (perfis de subagente + seção de delegação),
  `roadmap.org` (entrada 2026-08-13).
- Deploy: commit → push → `just sync` → `just compile-prod` → `just check-prod`.

### Critério de aceite:
- No `agnes`, `spawn_agent` gera job filho com backend/modelo `gemini-3.1-pro-preview`
  (log INFO `agent=... backend=... model=...`), não mais gemma local.
- Orquestrador gemma não tenta exploração profunda; delega automaticamente e
  sintetiza o relatório resumido no turno pai.
