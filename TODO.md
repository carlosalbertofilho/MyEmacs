# TODO — Planejamento Ativo e Backlog (MyEmacs)

> **Histórico de planos concluídos (0.5–0.27):** todos implementados, validados e
> arquivados no [roadmap.org](roadmap.org) (Linha do Tempo). Este arquivo mantém
> apenas pendências ativas, backlog futuro e decisões registradas.
> Revisão arquivamento: 2026-08-12.

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
3. **Modelo com tool-calling confiável** (§1c Fase 1 e 3) — o driver depende de
   o modelo emitir tool calls estáveis (Fase 2 já concluída: gemma default no
   MLX). Lição de campo: Gemini cloud e Llama local são os confiáveis; validar
   candidatos 3B–9B no Ollama e decidir o timeout de 120s.
4. **Contexto sob controle** (§1d) — cache de prefixo estável + compactação por
   janela. As tools do driver (buffer, flycheck, LSP) adicionam carga de
   contexto; sem isso o modelo pequeno degrada e o timeout de 120s volta.

**Etapa C — A Ambição (5 → 6 → 7; depende da Etapa B):**
5. **Fase A — Tools curadas** (§1e) — catálogo **enxuto** (3 tools):
   `flycheck_errors`, `lsp_navigation`, `snippet_expand`; saída estruturada e
   paginada (anti-pattern "lista tudo" — lição do vídeo gptel-tools/emacs-mcp).
6. **Fase B — Driver do buffer vivo** (§1e) — `buffer_edit` + workflow
   snippet → lacunas → flycheck → corrigir (o "preencher só as lacunas").
7. **Fase C — Loop de auto-correção como skill/workflow** (§1e).

## 1. Pendências de Investigação e Diagnóstico (Bugs Resolvidos)

- [x] **Timeout de 120s e Resposta Vazia no Magent com Gemini (`Request timed out after 120 seconds` / Resposta Vazia) (2026-08-12, RESOLVIDO):**
  - **Sintoma:** Requisições do Magent no Gemini expiravam em 120s ou retornavam texto vazio instantaneamente sem nenhuma saída no `Magent Agent`.
  - **Causas Raiz:**
    1. *Aridade em `gptel--parse-response` (Resposta Vazia):* A advice `magent-llm-gptel--sanitize-after-parse-response-a` do pacote magent declarava apenas 4 argumentos `(orig-fn backend response info)`. No `gptel-gemini`, `gptel--parse-response` passa 5 argumentos (`include-text` opcional). A passagem do 5º argumento gerava um erro `Wrong number of arguments: ..., 5`, capturado silenciosamente por `condition-case nil` em `gptel-curl--parse-stream`, fazendo o parser de stream retornar `""` (string vazia) em todas as respostas streaming do Gemini.
    2. *Reinstalação do Advice pelo `magent-llm-gptel-sample`:* A função `magent-llm-gptel--install-boundary-advice` rodava a cada turno e reinstalava a versão original de 4 argumentos caso a função embutida não fosse redefinida com `&rest args`.
    3. *FSM Orchestrate Intercept & Suppress:* A advice customizada `+carlos/magent-fsm-orchestrate-a` interceptava respostas vazias e chamava `+carlos/magent--fsm-retry-empty-turn`, retornando `'completed-paused` sem invocar a `orig-fn` nem emitir eventos terminais.
  - **Ações e Correções:**
    - `lisp/custom-magent.el`: Redefinida a função `magent-llm-gptel--sanitize-after-parse-response-a` com `&rest args` em `with-eval-after-load 'magent-llm-gptel`, garantindo repasse de 5+ argumentos no Gemini.
    - `lisp/custom-magent.el`: Removida completamente a FSM de orquestração (`+carlos/magent-fsm-orchestrate-a` e seus helpers `+carlos/magent--fsm-*`).
    - `lisp/custom-magent.el`: Definido `magent-include-reasoning nil` no `:custom` do `magent` para backend Gemini.
    - `tests/magent-test.el`: Atualizada a suíte ERT para 160 testes (removidos testes da FSM legada e adicionado teste de aridade).
  - **Validação & Savepoint:**
    - Resposta streaming e interativa do Magent no buffer UI validada com sucesso pelo usuário.
    - Suíte ERT executada com `just check-all` (160/160 testes aprovados, 0 falhas).
    - Tag git criada: `savepoint-magent-streaming-fix`.

- [x] **Travamento de CPU (100% CPU em `bidi_find_bracket_pairs` / `resize_mini_window`) (2026-08-10, RESOLVIDO):**
  - **Sintoma:** O daemon do Emacs travava em 100% CPU e o `emacsclient` deixava de responder quando o Magent/GPTel logava mensagens longas contendo o plist de ferramentas com parênteses/colchetes desbalanceados no echo area/minibuffer.
  - **Causa Raiz:** O motor de redisplay C do Emacs acionava o algoritmo BPA (`bidi_find_bracket_pairs`) e a varredura do minibuffer (`resize_mini_window`) para calcular a altura da mensagem do echo area a cada ciclo de `sit-for`/timers (`wait_reading_process_output`), entrando em complexidade quadrática em C.
  - **Solução:** Aplicado `(setq bidi-inhibit-bpa t)`, `(setq-default bidi-paragraph-direction 'left-to-right)`, `(setq resize-mini-windows nil)` e `(setq max-mini-window-height 1)` em `early-init.el` e `custom-core.el`, além de limitar a profundidade de serialização Lisp com `print-length 200` e `print-level 20`.

- [x] **Timeout de 120s no Gemini Tool Calling (Simbolo vs String) (2026-08-10, RESOLVIDO):**
  - **Sintoma:** Requisições ao Gemini no Magent terminavam em `Error: Request timed out after 120 seconds` mesmo após receber `HTTP/2 200`.
  - **Causa Raiz:** O `gptel-gemini` retornava os nomes das ferramentas em `:tool-use` como símbolos Lisp (`'glob`, `'read_file`), fazendo `(equal (gptel-tool-name ts) name)` falhar ao comparar string vs símbolo (`(equal "glob" 'glob) -> nil`), definindo `tool-spec = nil` e impedindo a execução da ferramenta.
  - **Solução:** Criado a advice `+carlos/magent-sanitize-tool-use-name-a` em `lisp/custom-magent.el` que executa `(magent-llm-gptel--sanitize-info info)` antes da busca da `tool-spec`, convertendo símbolos para strings. Adicionado o teste `myemacs-magent-sanitize-tool-use-symbol-to-string` em `tests/magent-test.el`.

- [x] **Clobbering do `gptel-agent-dirs` antes do carregamento (2026-08-10, RESOLVIDO):**
  - **Causa Raiz:** `+carlos/gptel-agent-add-project-dirs` executava `(unless (boundp 'gptel-agent-dirs) (setq gptel-agent-dirs nil))` antes do `gptel-agent` ser carregado, sobrescrevendo a lista padrão de agentes do pacote.
  - **Solução:** Adicionado `(require 'gptel-agent nil t)` antes de adicionar o diretório do projeto atual.

- [x] **Inversão de prioridade no Eglot para Python (2026-08-10, RESOLVIDO):**
  - **Solução:** Reordenado em `custom-lang.el` para que `basedpyright` seja adicionado por último a `eglot-server-programs`, garantindo que fique no topo da lista e seja o servidor principal do `python-ts-mode`.

- [x] **Ativação incorreta do `corfu-popupinfo-mode` (2026-08-10, RESOLVIDO):**
  - **Solução:** Corrigido de `setq` para a chamada de função `(corfu-popupinfo-mode 1)` em `custom-completion.el`.

- [ ] **epdfinfo Nix aborta ao ser spawnado pelo Emacs no macOS (2026-08-10):** o binário `epdfinfo` derivado do nixpkgs (`emacsPackagesFor (emacs.override { withMailutils = false; })` no MyMachine `emacs.nix`) funciona no shell mas aborta (`Abort trap: 6`; stderr: `libc++abi: ... std::__1::system_error: mutex lock failed: Invalid argument`) quando o Emacs o spawna via `call-process`/`start-process` — problema clássico de `fork()`+glib com binários Nix no macOS. Fatos: `call-process-shell-command` funciona (RET=0); wrapper shebang `#!/bin/sh` sem exec também aborta; wrapper com `&`+`wait` funciona em one-shot mas perde o stdin do servidor (render do pdf-tools falha com "server quit unexpectedly"). **Decisão:** adiar; próximos passos quando abordar: (1) testar wrapper C compilado que faz `fork`+`exec` próprio; (2) avaliar `advice` em `pdf-info-process-assert-running`/`pdf-info-check-epdfinfo` para spawnar via shell; (3) ou buildar `epdfinfo` com poppler do Homebrew em vez do Nix.

## 1b. Plano de Ação — 6 falhas do `just test` no repo (jinx-mod ausente)

**Diagnóstico (2026-08-10):** as 6 falhas do `just test` no repo têm **causa-raiz
única** — o hook `prog-mode-hook → jinx-mode` (custom-jinx.el:32) tenta compilar
`jinx-mod.dylib` ao entrar em `c-mode`/`emacs-lisp-mode`. No prod
(`~/.config/emacs`) o módulo já está compilado e nada falha (152/159, 7 skipped);
no repo (build parcial, sem o `.dylib`) a compilação via `jinx--load-module`
falha e o erro propaga pelo `run-mode-hooks`, derrubando qualquer teste que crie
um buffer de `prog-mode`. Falhas afetadas:

- `myemacs-42-formatter-keybinding-in-c-mode`
- `myemacs-ai-dynamic-router`
- `myemacs-ai-show-usage-dashboard`
- `myemacs-completion-tempel-capf`
- `myemacs-dev-apheleia-inhibit-c-mode`
- `myemacs-kbd-no-collisions`

**Status (2026-08-12, ATUALIZADO):** o plano original (guard no hook de runtime)
**não foi aplicado**. A mitigação efetiva foi **test-side**: `tests/spell-test.el`
usa `skip-unless` quando o `jinx` não carrega (builds parciais do repo) — a suíte
passa, mas o hook `prog-mode-hook → #'jinx-mode` (custom-jinx.el:32) segue direto
e ainda pode errar em runtime num build parcial. **Decisão pendente:** manter como
está (testes já cobrem) ou aplicar o guard runtime abaixo (opcional, portabilidade
"Works anywhere"; o padrão `skip-unless` já é usado no vterm/custom-term.el).

Caminho opcional (não aplicado, caso se decida pela guarda de runtime):

1. Em `lisp/custom-jinx.el`, adicionar helper:

   ```elisp
   (defun +carlos/jinx-mode-if-available ()
     "Ativa `jinx-mode' somente quando o módulo nativo pode carregar.
   Em builds parciais (sem `jinx-mod.dylib' compilado) não ativa, sem
   propagar erro que quebraria o boot do major-mode."
     (when (condition-case nil
               (progn (jinx-mode) t)
             (error
              (message "Jinx: módulo nativo indisponível; spellcheck off")
              nil))
       t))
   ```

2. Trocar os hooks de `#'jinx-mode` para `#'+carlos/jinx-mode-if-available`
   (linhas 31–32).

3. **Teste de regressão** — criar `tests/spell-test.el` (prefixo
   `myemacs-spell-*`) com:
   - `myemacs-spell-jinx-hook-guard`: remover o `.dylib` (mock via
     `+carlos/jinx-module-available-p` se necessário), entrar em buffer
     `c-mode`/`emacs-lisp-mode` e garantir que o modo **ativa sem erro**
     (nenhum `error` propagado, `run-mode-hooks` completo).
   - Manter o teste de grammar/`C-c c g` existente.

4. **Gate:** `just test-all` no repo (deve passar 159/159) + `just compile`
   zero-warning (declarar `+carlos/jinx-module-available-p` se usada).

**Registros relacionados:** decisão de benchmark de modelos e scripts em
`docs/magent-reference.org`; scripts salvos em `bin/magent-batch-test.el` e
`bin/bench-local-models.py`.

## 1c. Plano de Ação — Verificação de Modelos Locais (prioridade 1)

**Objetivo (2026-08-10):** validar quais modelos locais performam melhor no
fluxo real do magent (tool-calling via FSM) e aplicar o critério de troca de
default. É a **base** das prioridades 2 e 3 (§1d contexto, §1e driver) — janela,
latência e qualidade de tool-calling dos modelos determinam o que cabe em
contexto e como as tools podem operar.

**Status (2026-08-12, CONCLUÍDO NO HOST aa102-006l):**
- **Fase 1 (Ollama aa102-006l, 2026-08-12):** Benchmark executado com sucesso para os modelos do host `aa102-006l`.
  - `qwen2.5-coder:1.5b`: **15.11 tok/s**, TTFT **4.56s**, simulador Magent em **4s** (`status=completed`). Altamente recomendado para hardware leve.
  - `qwen2.5-coder:3b`: **9.20 tok/s**, TTFT **6.34s**, simulador Magent em **7s** (`status=completed`). Excelente equilíbrio para codificação local.
  - `deepseek-r1:1.5b`: **16.82 tok/s**, TTFT **4.21s** (apenas reasoning).
  - `gemma4:e2b`: **4.63 tok/s**, TTFT **32.61s** no Ollama (raciocínio pesado ~1102c). No MLX Apple Silicon opera a 31.4 tok/s; no Ollama exige timeout expandido (~60s+).
- **Fase 2:** Default MLX em `agnes` mantido como `gemma-4-e2b-it-4bit`.
- **Fase 3:** Recomendação para fallback local no `aa102-006l`: preferir `qwen2.5-coder:3b` ou `qwen2.5-coder:1.5b` devido ao tempo de resposta super-rápido (4s-7s).

**Baseline Ollama (host aa102-006l, 2026-08-12):**

| Modelo | tok/s | TTFT | Turno Magent | Status Magent | Observações |
|--------|-------|------|--------------|---------------|-------------|
| `qwen2.5-coder:1.5b` | 15.11 | 4.56s | **4s** | ✅ completed | Ultra leve e amigável ao hardware |
| `qwen2.5-coder:3b` | 9.20 | 6.34s | **7s** | ✅ completed | Excelente para codificação local |
| `deepseek-r1:1.5b` | 16.82 | 4.21s | — | — | Raciocínio rápido (1.5B) |
| `gemma4:e2b` | 4.63 | 32.61s | ~50s | ⚠️ completed | Reasoning de alta qualidade; mais pesado |
| `mistral:latest` | 4.19 | 12.37s | >60s | ❌ timeout | Lento para o hardware do host |

**Gate:** `just test-all` + `just compile` zero-warning + docs + sync prod.

## 1d. Plano de Ação — Gestão de Contexto (cache + compactação estilo Gemini CLI)

**Objetivo (2026-08-10):** gerenciar o contexto enviado ao modelo — usando
estratégias de **cache** (prefixo estável para custo/latência) e **compactação**
(resumo estruturado) — **sem degradar a informação** que chega ao modelo.
Referências: Context Caching da Gemini API (`ai.google.dev/gemini-api/docs/caching`),
Context Compaction do gemini-cli (issue google-gemini/gemini-cli#494).

**Diagnóstico do estado atual (Magent embutido):**
- **Já existe compactação manual:** `/compact` + agente `compaction`
  (`magent-runtime-session-compact`, magent-runtime-api.el:597). Ao compactar,
  um turno `:compaction t` marca um boundary e o histórico reenviado ao LLM
  começa dele (`magent-session--turns-from-last-compaction`,
  magent-session.el:1412-1420).
- **Já existe system message estável:** reconstruído por turno mas com conteúdo
  estável (global + role + contexto + AGENTS.md + skills + runtime-policy,
  magent-agent.el:136-166) — candidato natural a cache de prefixo exato.
- **Lacunas:** (1) **sem auto-compactação** por tamanho de janela; (2) prompt de
  compactação genérico (`internal/session-compaction.org`) sem lista de
  preservação estruturada — risco de perda de decisões; (3) **sem medição de
  hit-rate de cache**; (4) contexto pesado degrada o modelo local pequeno
  (problema do timeout de 120s, §1).
- **Infra disponível para reuso:** o tracker já loga tokens `cached` por chamada
  (`+carlos/gptel-track-usage`, custom-ai.el:616-666); eventos de ciclo de vida
  do magent têm sistema de sinks registráveis (`magent-lifecycle-events-add-sink`,
  evento `turn-end`, magent-lifecycle-events.el:74-109); modelos gptel carregam
  `:context-window` no plist (leitura como gptel-transient.el:1300).

---

### Fase 1 — Instrumentação (baseline de tokens e cache hit-rate)

**Arquivo:** `lisp/custom-ai.el` + `tests/context-test.el` (novo).

1. Registrar um sink de lifecycle no magent via
   `magent-lifecycle-events-add-sink` (hook em `:config` do magent em
   `custom-magent.el`) que, para eventos `turn-end` com `:status completed`,
   loga no `*magent-log*`: turn-id, estimativa de tokens (system + prompt-list;
   heurística ~ `(/ (length text) 4)` como fallback — tokenizar real é
   desnecessário para gate), e total de turnos desde o último boundary de
   compactação.
2. No dashboard de uso (`+carlos/gptel-track-usage` + `+carlos/magent-show-usage`),
   expor **cache hit-rate** do turno: `cached / (input + cached)` já que o tracker
   grava `cached` na linha do log (custom-ai.el:621-663, campo `nth 8` na agregação
   em :731). Hit-rate alto = prefixo estável; queda = algo dinâmico entrou no prefixo.
3. **Teste:** `myemacs-context-tracker-cached-hit-rate` — mockar `last-usage` plist
   com `:cached` e conferir o cálculo; `myemacs-context-turn-end-sink-logs` — emitir
   evento `turn-end` e garantir que o sink registra sem erro.

**Gate:** baseline registrado num comentário do cabeçalho do `custom-ai.el` e no
`docs/magent-reference.org` (seção "Gestão de Contexto") antes de seguir.

### Fase 2 — Compactação estruturada manual (`+carlos/magent-compact`)

**Arquivo:** `lisp/custom-magent.el` + `tests/context-test.el`.

1. Criar `+carlos/magent-compact` que chama `magent-runtime-session-compact`
   passando `:instruction` com **lista de preservação estruturada**:
   - arquivos modificados/criados (paths) e a razão;
   - nomes de testes associados a mudanças;
   - decisões técnicas + justificativa ("e por quê");
   - TODOs/estado pendente (não duplicar — **consultar** `TODO.md`/`roadmap.org`);
   - constraints/preferências do usuário persistentes;
   - comandos/gates válidos (`just ...`) descobertos.
   Pedir explicitamente para **não** replicar conteúdo lido mas não alterado
   (estilo guidebook do Codex).
2. Bindar em keybinding `C-c A` (preferência: `C-c A c` para compact) e,
   se viável, expor como slash command reusando o workflow existente de
   `magent-action-controls--compact` (magent-action-controls.el:15-40).
3. **Teste:** `myemacs-context-compact-preservation-instruction` — mockar
   `magent-runtime-session-compact` via `cl-letf` e verificar que a `:instruction`
   contém os itens de preservação e a cláusula "consultar TODO.md, não duplicar".

### Fase 3 — Auto-compactação por threshold (janela do modelo)

**Arquivo:** `lisp/custom-magent.el` + `tests/context-test.el`.

1. No mesmo sink da Fase 1, para eventos `turn-end completed`: estimar tokens
   do payload que será reenviado (system message + prompt-list via
   `magent-session-to-gptel-prompt-list`), obter a janela do modelo ativo via
   `(get (intern (gptel--model-name gptel-model)) :context-window)` (fallback:
   variável `+carlos/magent-context-window-fallback`; `nil` desativa a feature).
2. Quando `estimativa >= 0.6 * janela` (novo defcustom
   `+carlos/magent-context-compact-ratio`, default 0.6), disparar
   `magent-runtime-session-compact` com a instrução da Fase 2 e logar
   "auto-compact at P% (E tokens / W janela)". Compactar cedo = resumo de melhor
   qualidade = menos degradação.
3. **Não** compactar em sessões cujo backend seja local se a Fase 5 estiver ativa
   (evitar gasto duplo); protetor por `+carlos/magent-compact-predicate` (default t).
4. **Teste:** `myemacs-context-auto-compact-threshold` — mockar estimativa acima
   do ratio e confirmar que `magent-runtime-session-compact` é chamado;
   `myemacs-context-auto-compact-below` — abaixo do ratio, não chama.

### Fase 4 — Higiene de cache (prefixo estável)

**Arquivo:** `lisp/custom-magent.el` (auditoria) + Fase 1 mede o resultado.

1. Auditar o system message composto (magent-agent.el:136-166) para **elementos
   dinâmicos** que quebram o prefixo exato: o `memory-message`
   (`magent-memory-system-message`) é o suspeito nº 1 (pode variar por turno);
   conferir se `context-message` (workspace) inclui timestamp/status de git.
2. O que for dinâmico: **mover para o fim** do system message ou para o último
   turno user — o prefixo estável (AGENTS.md + skills + tools) deve ficar intacto
   para cachear (Gemini/OpenCode Zen/Claude cacheiam prefixo exato automaticamente).
3. **Teste:** `myemacs-context-system-prefix-stability` — compor o system message
   duas vezes com memória diferente e garantir que o segmento estável
   (do início até o primeiro segmento dinâmico) é idêntico.

### Fase 5 — Proteção do modelo local (futuro, separado)

**Arquivo:** `lisp/custom-magent.el` + `docs/magent-reference.org`.

- Quando abordar: variante "leve" de contexto só para backend local (AGENTS.md
  reduzido via `magent-project-instruction-file-names` específico por backend,
  ou skills enxutas), endereçando a degradação do modelo pequeno + timeout de 120s.
- Não fazer nesta rodada (depende da Fase 1-4 e de decisão sobre reduzir o
  AGENTS.md principal de ~22KB).

---

**Regras do Executor:** seguir os padrões do AGENTS.md (prefixo `+carlos/`,
guards `fboundp`/`require nil t`, `with-eval-after-load` em vez de `:after` com
`use-package-expand-minimally`; **não** usar `advice-add` em funções de orquestração
que a FSM já intercepta sem necessidade). **NÃO aplicar agora:** esta seção é o
plano para o Executor; nada de `lisp/custom-*.el` deve ser alterado fora deste
fluxo sem consulta.

**Gate final:** `just test-all` (repo, deve passar sem novas falhas) + `just
compile` zero-warning + `just compile-prod`/`just check-prod` pós-`just sync`.
Atualizar `docs/magent-reference.org` (seção "Gestão de Contexto") e `roadmap.org`.

## 1e. Plano de Ação — Magent como Driver do Emacs (Tool Operator)

**Ambição (north star, refinada 2026-08-12):** transformar o magent de "gerador
de texto" para **operador de ferramentas do Emacs** — o agente atua como
parceiro de pareamento que *opera* as ferramentas locais (tempel, flycheck,
LSP/eglot) em vez de cuspir blocos de texto para revisão. Concretamente: ao
invés de escrever uma função inteira, o modelo expande um **tempel snippet** e
**preenche apenas as lacunas** em point/região do buffer vivo, validando com
flycheck/LSP e corrigindo em loop (exemplo no §0 "A Ambição"). Registrado como
planejamento após conversa com agente externo + vídeo "Emacs lisp and gptel:
building custom llm tools to call emacs functions" (NapoleonWils0n, gptel-tools/
emacs-mcp); validado contra o código real do magent embutido.

**Correção crítica de arquitetura (vs. proposta original):** a ponte **NÃO é
MCP**. O magent roda **in-process** com o Emacs (transporte `gptel-request` via
`magent-llm-gptel.el`); expor comandos via MCP adicionaria round-trip externo
desnecessário. A ponte correta é o mecanismo que **já existe**: `gptel-make-tool`
+ catálogo `magent-tools-catalog` (magent-tools.el:1981) e o filtro por permissão
`magent-tools-get-gptel-tools-for-permission`. MCP só faria sentido para dirigir o
Emacs de fora (ex.: opencode → Emacs) — projeto separado.

**O que já existe (não reconstruir):**
- `emacs_eval` (magent-tools.el:1855) — driver universal: o modelo já pode avaliar
  elisp arbitrário (tempel, flycheck, xref). `:confirm ask`, timeout em thread.
- `/doctor` (docs/magent-reference.org:333) — já coleta flycheck/flymake/eglot
  diagnostics = o loop "ler erro do linter" já existe como slash command.
- `read_buffer` (magent-tools.el:1719) — lê o buffer vivo com edits não salvos.
- FSM de orquestração (THINK/DECIDE/RETRY), sistema de permissões e audit log.

**O gap real:** não é "criar a ponte", é **disciplinar o que o `emacs_eval` faz
cru**: saída `prin1-to-string` não estruturada; ausência de tools curadas com args
tipados e descrições ricas (`flycheck_errors`, `lsp_navigation`, `snippet_expand`,
`buffer_edit`); e ausência de **driver do buffer vivo** (agente opera o disco, não
o buffer do usuário em point/região — o pulo de "gerador" → "pareamento").

**Tensão a planejar (pilar tempel):** dois modelos distintos — (A) *agente como
operador de arquivo* (atual: text-match no disco, AST-safe por natureza) e (B)
*agente como driver do buffer do usuário* (expandir snippet em point, pular
placeholders, next-error) — B introduz corrida com a edição do usuário,
permissões e cancelamento. Planejar como fases separadas.

**Lição de campo (gptel-tools/emacs-mcp, 2026-08-10):** um setup com 32 tools
de introspecção do Emacs em gptel (NapoleonWils0n) mostrou na prática que
**catálogo inchado degrada o LLM**: `list-all-bindings` (saída gigante) travou o
modelo por 15–20 min e saturou o contexto; modelos locais fracos entram em loop
com muitos tools; e a `:description` de cada tool é o que guia a seleção correta
pelo LLM. Implica no §1e:
- **começar com um catálogo enxuto** (3 tools curadas da Fase A, não 30);
  crescer só com necessidade real;
- **toda tool com saída limitada/estruturada** (paginada/truncada em
  `next_start_line` como `read_file`/`read_buffer` do magent já fazem) — nunca
  "lista tudo" crua (`list-all-bindings` é anti-pattern, ref. §1d Fase 1);
- a `:description` precisa ser tratada como prompt de seleção (já é padrão do
  catálogo magent).

**Escolha de modelo (lição do vídeo, 2026-08-12):** para tool-calling **nativo e
estável** o vídeo valida **Gemini** (cloud, já nossa 1ª escolha) e **Llama 3.1/3.2**
(local) como confiáveis; Qwen-thinking/DeepSeek/Granite degradam. Isso reforça o
§1c: ao validar candidatos no Ollama, incluir Llama; manter gemma como default
MLX (nossa FSM recupera tool calls do reasoning, validado em sessão real).

### Fase A — Tools Emacs curadas (in-process, baixo risco)

**Arquivo:** `lisp/custom-magent.el` + `tests/magent-driver-test.el` (novo).

1. Definir tools via `gptel-make-tool` (padrão de `magent-tools.el`) que **enviam
   o modelo à tool real**, com saída estruturada (JSON/plist → string) e args
   tipados:
   - `flycheck_errors` — lista erros do flycheck no buffer/projeto corrente
     (reuso da coleta do `/doctor`): arquivo, linha, coluna, mensagem, checker.
   - `lsp_navigation` — navegação por `xref-find-definitions`/`xref-backend-*`
     (eglot) para resolver símbolos reais e **matar alucinação de nomes**.
   - `snippet_expand` — expandir snippet do tempel por nome + preencher campos
     (fase B como driver; aqui versão "estática": retorna o texto expandido).
2. Inserir no catálogo e expor via permissão própria
   (`magent-enable-tools` é lista fixa em magent-config.el:81 — estender a lista
   ou o filtro `magent-tools-get-gptel-tools-for-permission` sem quebrar o gate).
3. **Testes:** `myemacs-driver-flycheck-errors-structured`, `myemacs-driver-lsp-xref-resolve`,
   `myemacs-driver-snippet-expand-name` — mockar as funções subjacentes
   (`flycheck-errors`, `xref-find-definitions`, `tempel-*`) e validar o formato
   da saída + permissão `ask`.

### Fase B — Driver do buffer vivo (pareamento de verdade)

**Arquivo:** `lisp/custom-magent.el` + testes + `docs/magent-reference.org`.

1. `buffer_edit`/`buffer_insert` operando no buffer do usuário (point/região),
   com **contrato de sessão**: apenas um "dono" do buffer por vez, coordenado com
   `read_buffer` (estado vivo) e com cancelamento da FSM.
2. Workflow "preenchimento de lacunas": `snippet_expand` → preencher placeholders
   → `flycheck_errors` → corrigir (loop que o `/doctor` já habilita).
3. **Riscos a mitigar antes de implementar:** corrida com edição do usuário,
   permissão granular, undo, e o modelo local pequeno sob contexto pesado
   (endereçado no §1d).

### Fase C — Loop de auto-correção como skill/workflow

1. Skill (`.magent/skills/`) ou workflow: escrever → flycheck → corrigir → LSP
   para resolução de símbolos, formalizando o que `/fix` faz hoje como fluxo
   declarativo reutilizável pela FSM.

---

**Regras do Executor:** mesmas do §1d (prefixo `+carlos/`, guards, `:ensure nil`/
`use-package`, `with-eval-after-load`, sem `advice-add` desnecessário em
orquestração). **NÃO aplicar agora:** faseamento discutido; decidir escopo real
(fase A primeiro) antes de qualquer mudança em `lisp/custom-*.el`.

**Gate final:** `just test-all` + `just compile` zero-warning + sync prod
(`just compile-prod`/`just check-prod`). Atualizar `docs/magent-reference.org`
(seção "Driver do Emacs") e `roadmap.org`.

## 1f. Plano de Ação — org-noter nov/djvu (CONCLUÍDO — arquivado)

> **Arquivado em 2026-08-12:** implementado e validado (ver roadmap.org
> "org-noter: pacotes opcionais nov+djvu e boot limpo"). Código em
> `lisp/custom-org.el` (`nov` MELPA `:mode "\\.epub\\'"`, `djvu` GNU ELPA,
> `org-noter-supported-modes` com os 4 modos em `:custom`), testes em
> `tests/org-test.el` (`myemacs-org-{nov-installed,djvu-installed,noter-supported-modes-full,noter-no-missing-module-warnings}`),
> binários DjVuLibre no MyMachine (`djvulibre`+`djview` em `emacs.nix`,
> commit `b8e8fb5`). Warning `jupyter-kernel-client` documentado como benigno.
> Decisão registrada no §3.

## 1g. Plano de Ação — Elpaca 0.2.0 não ativa pacotes instalados (boot travado + suíte batch quebrada)

**Status (2026-08-12, REVISAR):** o plano **não foi aplicado** — `custom-lang.el`/
`custom-42.el` seguem com `:ensure t` + `(elpaca-wait)`. Porém o problema **não
reaparece**: prod validado com 165 testes + daemon responsivo após
`just rebuild-prod` (roadmap.org "Auditoria", 2026-08-10). **Hipótese:** o
travamento era build stale, já mitigado pela política de limpeza de artefatos
(`just rebuild`/`clean-prod`). **Decisão pendente:** manter o plano como migração
futura de robustez (`:ensure (:wait t)`) ou arquivar como não-causa.

**Diagnóstico (2026-08-10, sessão com `emacs --daemon` + `just check-all`):**

O `just check-all` expôs duas falhas e a inspeção da sessão viva revelou a causa-raiz
única: **a ativação do Elpaca 0.2.0 (6530ffa) não completa para pacotes já no disco**,
tanto em `--batch` quanto no daemon interativo. Evidências:

1. **Batch (`just test` em `~/.config/emacs`):** `Error (use-package): Cannot load
   treesit-auto/reformatter/flycheck/apheleia` → `require(custom-42)` →
   `require(flycheck nil nil)` → `file-missing`. O build de `flycheck` EXISTE em
   `elpaca/builds/` mas não está no `load-path`.
2. **Daemon (`emacs --daemon`, boot 09:47):** init congela em `(require 'custom-42)`
   (init.el:158). O `(elpaca-wait)` de custom-42.el:28 **nunca retorna**. Estado
   verificado via `emacsclient`: `custom-lang/org/files = t`; `custom-42/ai/dev/jinx/
   magent/git/dashboard = nil`; `gptel/magit = nil`; `featurep 'flycheck = nil`,
   `fboundp 'flycheck-mode = nil`, `global-flycheck-mode = nil` (build no disco, não
   ativado); `elpaca--queues` com filas não processadas (org/files/completion/UI).
3. **Função órfã no keymap:** `+carlos/ai-rag-ingest` (custom-ai.el:668, interativa)
   está **void** no daemon porque `custom-ai` nunca carregou; keymap `C-c r` já o
   referencia → `*Messages*` com `Wrong type argument: commandp, +carlos/ai-rag-ingest`
   (o teste `myemacs-boot-no-lisp-errors` varreria isso se o boot terminasse).
4. **Sintomas históricos = mesma causa:** "vertico estava instalando antes" e o
   `void-variable vertico` do boot interativo anterior (a fila fica presa instalando/
   ativando e lê o símbolo antes da ativação).
5. **Mecânica do `elpaca-wait`:** elpaca.el:1539 → `elpaca-process-queues` + loop
   `(sit-for elpaca-wait-interval)`. Em `--batch`, `sit-for` retorna imediatamente sem
   despachar I/O de subprocessos → qualquer passo da fila que dependa de subprocesso
   (status git / autoloads / nativo-comp) **não progride**; no daemon a fila fica
   estagnada indefinidamente.

**Hipótese principal:** o padrão `(use-package X :ensure t :demand t)` + `(elpaca-wait)`
top-level não é o mecanismo bloqueante confiável no Elpaca 0.2.0. O manual
(`elpaca/sources/elpaca/doc/manual.md` §use-package) documenta a forma canônica:

```elisp
(use-package general :ensure (:wait t) :demand t)
```

O `:wait t` no `:ensure` faz a fila processar **síncrono antes de continuar o init**.
O `(elpaca-wait)` top-level só espera as filas atuais e depende do event loop para
avançar. **Fix previsto:** migrar os pontos de dependência dura para `:ensure (:wait t)`
e remover os `(elpaca-wait)` top-level, mantendo `:demand t`.

**Fase 1 — Isolar a causa (antes de editar):**
1. Reproduzir batch mínimo no prod e instrumentar: boot com `--eval` que imprima o
   status/estado da ordem `flycheck` dentro do `elpaca-wait` (ex.: `elpaca--process-queue`
   + `elpaca--process` em `flycheck`) para confirmar onde a fila estagna.
2. Confirmar se `sit-for` é o bloqueio em batch: rodar o mesmo boot com
   `(advice-add 'sit-for :around (lambda (f &rest a) (accept-process-output nil 0.05) (apply f a)))`
   ou equivalente — se `just check-prod` passar, o diagnóstico fecha.
3. Verificar se é regressão do 0.2.0 (git log 6530ffa) ou comportamento sempre assim.

**Fase 2 — Migrar padrão `:ensure (:wait t)` (fix principal):**
- `custom-lang.el:24` `treesit-auto` → `:ensure (:wait t)` (mantém `:demand t`).
- `custom-lang.el:89` `reformatter` → `:ensure (:wait t)`, **remover** `(elpaca-wait)`
  da linha 92.
- `custom-lang.el:146` `flycheck` → `:ensure (:wait t)`, **remover** `(elpaca-wait)`
  da linha 152.
- `custom-lang.el:171` `apheleia` → avaliar `:demand` e alinhar.
- `custom-42.el:13` `flycheck` (`:ensure nil :demand t`) → manter `:ensure nil` (evita
  duplicação na fila), remover o `(elpaca-wait)` de custom-42.el:28 **apenas se** o
  `:ensure (:wait t)` do custom-lang garantir a ativação antes do
  `(require 'custom-norminette)` — senão manter o wait e ajustar para a forma
  documentada.
- Rever demais `:demand t` sem wait (ex.: `dirvish` em custom-files, `gptel`/`magent`
  em custom-ai/custom-magent) e alinhar ao mesmo padrão.

**Fase 3 — Validação batch (portões):**
- `just check-prod` (boot), `just compile-prod` (zero-warning), `just test`
  (suíte ERT autoritativa) no prod — todos verdes.
- `just check-all` no repo.
- Se `sit-for` em batch continuar bloqueando mesmo com `:wait t`: adicionar helper de
  boot para batch no init.el (ex.: forçar `elpaca-process-queues` síncrono com
  `accept-process-output` antes do `require` de módulos que dependem de pacotes).

**Fase 4 — P2: free variables no compile do repo (custom-ai.el:618 `gptel--token-usage`,
`custom-magent.el:329` `magent-skill-directories`):**
- Se a Fase 3 destravar a ativação no repo (builds parciais), o compile passa a ver o
  pacote no load-path e o warning some (é sintoma do P1 no repo).
- Caso contrário: forward declaration pelada `(defvar gptel--token-usage)` + guarda
  `(unless (boundp 'gptel--token-usage) (setq gptel--token-usage nil))` antes do uso
  (AGENTS.md — Emacs 30: NUNCA `(defvar X nil)` em variável de pacote).

**Fase 5 — P3: `Wrong type argument: commandp, +carlos/ai-rag-ingest` no `*Messages*`:**
- É consequência do P1 (config não terminou de carregar). Após o fix, reiniciar o
  daemon e validar: `featurep 'custom-ai/custom-magent/custom-git/custom-dashboard = t`,
  `(commandp '+carlos/ai-rag-ingest) = t`, `C-c r` e `C-c A*` funcionais, `*Messages*`
  limpo (coberto por `myemacs-boot-no-lisp-errors` e `myemacs-kbd-no-collisions`).

**Fase 6 — Regressão:**
- Novo teste ERT se necessário (ex.: `myemacs-elpaca-demand-activation` que verifica
  `featurep 'flycheck` e `fboundp 'flycheck-mode` após boot).
- Reboot limpo do daemon do usuário (o atual está congelado no meio do init).

**Critérios de aceitação:**
- `just check-all` verde no repo E no prod (compile zero-warning, checkdoc OK, ERT OK).
- Daemon com todos os features carregados (custom-42/ai/dev/jinx/magent/git/dashboard)
  e `gptel`/`magit` ativos; `*Messages*` sem `Cannot load`/`Wrong type argument`.
- `just test` autoritativo (prod) sem erros de load.
- `C-c r` → `+carlos/ai-rag-ingest` com `commandp` t.

**Regras do Executor:** padrões do AGENTS.md (`:custom` em vez de `setq`; guardas
`(unless (boundp ...))`; NÃO pré-declare defcustom com nil; `just rebuild-prod` +
`just check-prod` pós-sync quando houver `.elc` stale). **NÃO aplicar agora:** este é o
plano; o Executor aplica quando acionado. Ordem de execução recomendada: Fase 1 → 2 → 3 → 5 → 6; Fase 4 sob demanda.

## 1h. Plano de Ação — Fluxo de Dev Elisp (IA → REPL → ERT) [CONCLUÍDO 2026-08-12]

**Objetivo (2026-08-12):** consolidar o ciclo de desenvolvimento Elisp (IA → REPL → ERT) para acelerar o desenvolvimento de código elisp testável.

**Ações Concluídas:**
- `lisp/custom-dev.el`: Adicionados prompts centralizados `+carlos/elisp-ert-prompt` e `+carlos/elisp-debug-prompt`.
- `lisp/custom-dev.el`: Implementado o gerador de testes ERT via IA `+carlos/ert-generate-tests` (bind `C-c D e` global e `C-c C-e` local).
- `lisp/custom-dev.el`: Implementado o helper de bloco REPL `+carlos/insert-repl-block` (`(when nil ...)` scratch, bind `C-c D b` global e `C-c C-b` local).
- `tests/dev-test.el`: Criada suíte ERT validando comandos, prompts, binds globais e locais, e o gerador de scratch.
- `docs/dev-workflow.org`: Criado documento RAG com a tabela de atalhos e fluxo de dev.
- `AGENTS.md`: Registrado `docs/dev-workflow.org` na tabela RAG Cache.

**Validação:**
- Suíte ERT executada via `just check-all`: **165/165 testes aprovados (0 falhas)**.
- Gate zero-warning e boot de produção validados.

## 2. Backlog (Planejamento Futuro, Ordenado por Dificuldade)

1. [ ] **Etapa de teste da stack de IA** (Fase 4 da revisão da stack — diagnóstico 1–3 concluído em 2026-08-06/07, ver roadmap).
   - Validar cada entrada em `~/.config/emacs`: `C-c i` (gptel chat), `C-c I` (+carlos/gptel-agent-run), `C-c C-g` / commit IA, `C-c A a`/`C-c A o` (eshell agy/opencode), gptel-org num `.org`, e troca de backend/modelo no buffer — conferindo erro de API, modelo válido e resposta streaming.
   - Backends 5/5 já validados em batch (PONG); falta a validação interativa GUI.

2. [ ] **agent-shell como subagente do Magent** (Dificuldade: Alta — em análise, **NÃO é prioridade agora**)
   - **Ideia:** em vez de o magent e o agent-shell standalone competirem, usar o agent-shell como **subagente invocado pelo magent** quando precisar de features específicas de agentes externos (Claude Code, Cursor, Aider): diff-at-point via RET (`agent-shell-diff-open-file`), activity grouping, MCP nativo, e modelos frontier para refactors pesados (Go + React/TS multi-arquivo).
   - **Contexto técnico da análise (2026-08-09):** o magent **já usa** o agent-shell como frontend ACP in-process (`magent-agent-shell.el`), mas o adapter não emite eventos `diffs`/`locations` estruturados como os CLIs externos — logo `*Magent*` não tem a navegação de diff com RET nem o activity grouping de primeira classe. O que o setup atual entrega e deve ser preservado: FinOps (custo ~zero via roteador dinâmico + `+carlos/magent-show-usage`), sanitização de tools (`+carlos/magent-system-directives` + advice-add de path/args), keybindings `C-c A*`, e skills do projeto em `.magent/skills/`.
   - **Etapas futuras (quando abordar):**
     1. Avaliar o mecanismo de spawn de subagentes do magent (`spawn_agent`/`wait_agent` — diretiva 5 de `+carlos/magent-system-directives`) e a API de registro de agentes externos.
     2. Definir contrato de passagem: magent delega ao agent-shell standalone um prompt de refactor/tarefa frontier e recebe o resultado (diff estruturado) de volta para revisão no buffer do magent.
     3. Roteamento: subagente external apenas quando o roteador dinâmico identificar tarefa "architect"/refactor pesado; manter local/free para o resto.
     4. Estender o FinOps tracker (`+carlos/gptel-track-usage`) para registrar chamadas do agente externo.
     5. Testes ERT (prefixo `myemacs-agent-shell-*`) + docs em `docs/magent-reference.org`.
   - **Registro (não abordar agora):** ideia guardada; decidir escopo de verdade quando o fluxo diário exigir modelos frontier para migração multi-arquivo.

## 3. Decisões Registradas

- **org-noter nov+djvu (2026-08-10, §1f):** instalados `nov` (MELPA, EPUB) e `djvu` (GNU ELPA) via Elpaca; `org-noter-supported-modes` fixado em `:custom` com os 4 modos (doc-view/pdf-view/nov/djvu); binários DjVuLibre providos pelo Nix do MyMachine (`djvulibre` + `djview` em `home/carlosfilho/emacs.nix`). Elimina os warnings `package not found`/`ATTENTION` do boot sem dependência morta.
- **SuperChat (item 2 do antigo backlog):** removido — código morto eliminado em 2026-08-06 (não testar visual).
- **Fase 4 — Cutoff (Doom → Vanilla final):** **manter modelo espelho** — `~/.config/emacs` continua clone sincronizado via `just sync`; NÃO converter em symlink (decisão 2026-08-09). Script `bin/cutoff-migration.sh` permanece disponível se a decisão mudar.
- **agy/copilot no Emacs (exceção a "CLIs no terminal"):** mantidos como exceção consciente — `+carlos/agy-prompt` (`C-c A g`) e `+carlos/copilot-explain-region` (`C-c A c`) (AGENTS.md §0, 2026-08-09).
- **Limpeza de artefatos de build:** política criada (2026-08-09) — `just clean`/`clean-prod` (`.elc`/`.eln` + `eln-cache/`) e `just rebuild`/`rebuild-prod`. Rebuild completo em repo e prod + `just test-all` OK (146 testes, 0 falhas). Ver AGENTS.md "Política de Limpeza de Artefatos de Build" e roadmap 2026-08-09.
- **Formato de tool call do Magent (DSML):** adicionada diretriz nº 6 em `+carlos/magent-system-directives` ensinando o formato textual parseável (`<tool_calls>`/`<invoke name=...>`/`<parameter name=...>`), injetada no system message via advice `:filter-return` em `magent-agent--compose-system-message`. Motivo: Qwen3.5-9B sob contexto pesado emitiu `<tool_call>/<function=>` (Claude-XML) como reasoning, que o parser do magent ignora (2026-08-10). Testes: `myemacs-magent-dsml-*` (150 testes, 0 falhas).
- **Magent: tool call no reasoning nunca executa (reforço do DSML, 2026-08-10):** diagnóstico — o magent só parseia DSML do stream de content (`magent-llm-gptel--emit-completed-or-textual-tool-calls`); reasoning vai direto para `magent-llm-reasoning-delta-event` e qualquer `<tool_call>` escrito lá é silenciosamente descartado. O gatilho da degradação do 9B foi um `find | head -50` → SIGPIPE (exit 141) → magent reporta tool FAILED. Reforços: diretriz 6 agora proíbe tool calls em reasoning/thinking e exige nativas no FINAL; nova diretriz 7 instrui evitar SIGPIPE (`find -maxdepth`/`rg --max-count` em vez de `| head`). Reprodução batch: contexto pesado + diretriz nova = 3/3 tool_calls nativos. Testes: `myemacs-magent-directives-reasoning-ban`, `myemacs-magent-directives-sigpipe`.
- **Magent: FSM de orquestração THINK/DECIDE/RETRY (2026-08-10, REMOVIDA 2026-08-12):** criada originalmente em 2026-08-10 para mitigar turns vazios de modelos locais. Em 2026-08-12, a FSM foi **completamente removida** por introduzir retenção de eventos terminais e ser superada pela correção definitiva da aridade (`&rest args`) em `magent-llm-gptel--sanitize-after-parse-response-a`. O Magent agora opera 100% no fluxo nativo do `magent-llm-gptel`.
- **Magent: sink de log read-only (2026-08-10, fix `464e196`):** `*magent-log*` fica read-only porque `magent-log-mode` deriva de `special-mode`; o sink nativo usa `inhibit-read-only`, mas o nosso `+carlos/magent-log-context` não — 107 erros `Buffer is read-only` spammaram o log na sessão real. Fix: insert envolto em `(let ((inhibit-read-only t)) ...)` em `lisp/custom-ai.el`. Teste `myemacs-magent-log-context` atualizado para abrir o buffer via `magent-log-buffer` (aplica o modo read-only) e garantir que o sink grava mesmo assim.
- **Reorganização da Tabela de Modelos Padrões (2026-08-12):** Hierarquia de modelos estruturada em 3 Tiers baseados em hardware e propósito:
  - *Tier 1 (Novem/Chat/FinOps):* `Gemini` (`gemini-3.5-flash`) como 1ª escolha global (quota gratuita, <1s TTFT), `OpenCode Zen` (`deepseek-v4-flash-free`/`big-pickle`) como 2ª escolha free, `Zen Claude` (`claude-sonnet-5`) para agente frontier.
  - *Tier 2 (Local GPU MLX agnes):* `mlx-community/gemma-4-e2b-it-4bit` (31.4 tok/s, 11s no Magent) como default local de alta velocidade.
  - *Tier 3 (Local CPU aa102-006l Ollama):* `qwen2.5-coder:3b` (7s no Magent) e `qwen2.5-coder:1.5b` (4s no Magent) no topo da lista do Ollama devido ao consumo leve de hardware. Documentado em `docs/ai-providers-reference.org`.
- **Default local MLX: gemma-4-e2b-it-4bit (2026-08-10):** benchmark dos 5 modelos locais (ver `docs/magent-reference.org`) — gemma lidera (31.4 tok/s, 2x o Qwen3.5-9B) e completou o turn do magent em 30.3s com reasoning estruturado; Qwen2.5-7B (sem reasoning, 0c) levou 99.5s e errou tool (`read` num diretório); os 14B (Qwen3/DeepSeek-R1) são lentos demais (3.7–8 tok/s). Troca do default em `+carlos/ai-local-backend` (custom-ai.el) + testes atualizados. O Qwen3.5-9B permanece como opção no backend (lista de modelos).
- **Scripts de avaliação de modelos locais (2026-08-10):** salvos em `bin/magent-batch-test.el` (reprodução batch do turn do magent sem GUI, drena `*magent-log*` via `MAGENT_SIM_MODEL`/`MAGENT_SIM_TIMEOUT`/`MAGENT_SIM_PROMPT`) e `bin/bench-local-models.py` (benchmark streaming tok/s, ttft, content/reasoning para MLX agnes:8081 e Ollama aa102-006l via `--ollama`). Usar para avaliar substitutos do 14B no host aa102-006l e validar a FSM real antes de trocar default. Critério de troca documentado em `docs/magent-reference.org`.

---
> Para o histórico cronológico detalhado de conquistas e decisões arquiteturais, consulte o [roadmap.org](roadmap.org).
