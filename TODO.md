# TODO — Planejamento Ativo e Backlog (MyEmacs)

> **Histórico de planos concluídos (0.5–0.27):** todos implementados, validados e
> arquivados no [roadmap.org](roadmap.org) (Linha do Tempo). Este arquivo mantém
> apenas pendências ativas, backlog futuro e decisões registradas.
> Revisão arquivamento: 2026-08-09.

## 0. Prioridade de Execução (2026-08-10)

Ordem deliberada dos planos de ação — trabalhar nesta sequência:

1. **Verificação de Modelos Locais** (§1c) — benchmark com os scripts salvos
   (`bin/bench-local-models.py` + `bin/magent-batch-test.el`), validar candidatos
   3B–9B no MLX/Ollama com a FSM real e aplicar o critério de troca de default
   (docs/magent-reference.org:194-197). Base para tudo que vem depois.
2. **Gestão de Contexto** (§1d) — cache (prefixo estável) + compactação
   estruturada (cache + auto-compact por janela). Depende do §1c: modelos
   diferentes têm janelas e limites de contexto diferentes.
3. **Magent como Driver do Emacs** (§1e) — tools Emacs curadas
   (flycheck/lsp/snippet), depois driver do buffer vivo. Depende do §1d
   (contexto sob controle antes de adicionar mais tools).

## 1. Pendências de Investigação (Bugs)

- [ ] **epdfinfo Nix aborta ao ser spawnado pelo Emacs no macOS (2026-08-10):** o binário `epdfinfo` derivado do nixpkgs (`emacsPackagesFor (emacs.override { withMailutils = false; })` no MyMachine `emacs.nix`) funciona no shell mas aborta (`Abort trap: 6`; stderr: `libc++abi: ... std::__1::system_error: mutex lock failed: Invalid argument`) quando o Emacs o spawna via `call-process`/`start-process` — problema clássico de `fork()`+glib com binários Nix no macOS. Fatos: `call-process-shell-command` funciona (RET=0); wrapper shebang `#!/bin/sh` sem exec também aborta; wrapper com `&`+`wait` funciona em one-shot mas perde o stdin do servidor (render do pdf-tools falha com "server quit unexpectedly"). **Decisão:** adiar; próximos passos quando abordar: (1) testar wrapper C compilado que faz `fork`+`exec` próprio; (2) avaliar `advice` em `pdf-info-process-assert-running`/`pdf-info-check-epdfinfo` para spawnar via shell; (3) ou buildar `epdfinfo` com poppler do Homebrew em vez do Nix.
- [ ] **Testar config completa em GUI** (não batch) para verificar compilação do `vterm-module`.
- [ ] **Timeout de 120s no magent em sessão real** (2026-08-10): sessão com contexto pesado (AGENTS.md ~22KB ≈ 7K tokens + skills + transcript) terminou em `Error: Request timed out after 120 seconds` — é o default `magent-request-timeout 120` (`magent-config.el:119`, dispara quando nenhum evento do provider sai em 120s). Não é bug da FSM; decidir: subir o timeout (ex.: 300s) via `:custom`, trocar para `Qwen3-14B-4bit` (mais rápido por token) e/ou reduzir o contexto (AGENTS.md menor, skills mais enxutas). Nota: o mesmo 9B emitiu `find | head -50` de novo no transcript (diretriz 7 não seguiu), ficou `pending` aguardando permissão.
- [ ] Investigar por que `consult` e `nerd-icons` não foram encontrados no MELPA durante `just check` (se persistente nas primeiras instalações do usuário).
- [ ] Verificar se pacotes estão em rebuild no MELPA ou se foram removidos/renomeados.

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

**Ação — tornar o hook do jinx resiliente a builds parciais (não é só mascarar):**
melhora legítima de portabilidade (AGENTS.md: "Works anywhere"). O padrão de
guarda para módulo nativo já é usado em `custom-term.el` (vterm) via
`skip-unless` nos testes; aqui a guarda vai no hook de runtime.

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

**Ferramentas já prontas (2026-08-10, ver docs/magent-reference.org:151-197):**
- `bin/bench-local-models.py` — benchmark streaming (tok/s, ttft, content/reasoning)
  para MLX (agnes:8081) e Ollama (`--ollama`, aa102-006l:11434). Prompt default
  idêntico ao do magent-batch-test para comparabilidade.
- `bin/magent-batch-test.el` — reprodução batch do turn do magent sem GUI,
  drena `*magent-log*` (FSM real) via `MAGENT_SIM_MODEL`/`MAGENT_SIM_TIMEOUT`/
  `MAGENT_SIM_PROMPT`.

**Baseline (agnes M2, 2026-08-10):**

| Modelo | tok/s | ttft | total | content | reasoning |
|--------|-------|------|-------|---------|-----------|
| gemma-4-e2b-it-4bit (default atual) | 31.4 | 3.2s | 11.2s | 296c | 1103c |
| Qwen3.5-9B-MLX-4bit (antigo default) | 15.9 | 1.1s | 15.9s | 459c | 648c |
| Qwen2.5-7B-Instruct-4bit | 15.1 | 4.1s | 16.9s | 923c | 0c |
| Qwen3-14B-4bit | 8.1 | 7.1s | 37.8s | 266c | 1187c |
| DeepSeek-R1-Distill-Qwen-14B-4bit | 3.7 | 25.9s | 41.0s | 325c | 347c |

**Critério de troca de default (docs/magent-reference.org:194-197):** (a) >20
tok/s no MLX; (b) reasoning estruturado presente; (c) turn completo <60s no
magent-batch-test; (d) zero tool-call no reasoning em 3/3 runs.

**Lição de campo (gptel-tools/emacs-mcp, 2026-08-10):** modelos locais têm
**suporte desigual a tool-calling** — Llama 3.1/3.2 bons; Qwen-thinking e
Gemma entram em loop ("quer simular a tool call"), DeepSeek tem suporte
"bolado"; e modelos fracos com 32 tools travam/saturaram o contexto. Implica:
- **mais um critério de troca (e):** tool-calling **nativo e estável** no
  magent-batch-test (o FSM recupera do thinking, mas um modelo que não emite
  tool-call nativo ainda degrada) — validar com a suite real, não só tok/s;
- evitar catálogo de tools inchado ao validar candidatos (ver §1e, lição 1).

**Fase 1 — Validar candidatos no host aa102-006l (Ollama):**
1. Rodar `python3 bin/bench-local-models.py --ollama --models qwen2.5-coder:3b qwen3:0.6b` (e outros candidatos locais do Ollama).
2. Comparar tok/s/ttft com o baseline MLX; Ollama e MLX têm tokenizers/APIs de reasoning diferentes — só o magent-batch-test valida a FSM real.
3. Para cada candidato com tok/s competitivo: `MAGENT_SIM_MODEL=<model> just run magent-batch-test` (ou equivalente em batch) — medir turn completo, tool-call nativo no FINAL, zero tool-call no reasoning.

**Fase 2 — Revalidar modelos 3B–9B no MLX (agnes):**
1. Re-rodar `bin/bench-local-models.py` (MLX) para gemma-4-e2b-it-4bit, Qwen3.5-9B, Qwen2.5-7B com o prompt do magent — confirmar o baseline não degrau.
2. Aplicar o critério (a)-(d); se outro modelo vencer o gemma atual, trocar o default em `+carlos/ai-local-backend` (custom-ai.el) + atualizar testes `myemacs-ai-*` e docs.

**Fase 3 — Tratar o timeout de 120s (bug §1) na sequência:**
1. Uma vez escolhido o modelo, decidir se `magent-request-timeout 120` (magent-config.el:119) precisa subir (ex.: 300s) via `:custom` — com o modelo certo, o turn <60s não deve estourar o default.
2. Registrar decisão final (modelo + timeout) no §3 e docs.

**Gate:** `just test-all` + `just compile` zero-warning + docs (`docs/magent-reference.org` benchmark atualizado) + sync prod.

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

**Ambição (2026-08-10):** transformar o magent de "gerador de texto" para
**operador de ferramentas do Emacs** — o agente atua como parceiro de pareamento
que *opera* as ferramentas locais (tempel, flycheck, LSP/eglot) em vez de cuspir
blocos de texto para revisão. Registrado como planejamento após conversa com
agente externo; validado contra o código real do magent embutido.

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

- **SuperChat (item 2 do antigo backlog):** removido — código morto eliminado em 2026-08-06 (não testar visual).
- **Fase 4 — Cutoff (Doom → Vanilla final):** **manter modelo espelho** — `~/.config/emacs` continua clone sincronizado via `just sync`; NÃO converter em symlink (decisão 2026-08-09). Script `bin/cutoff-migration.sh` permanece disponível se a decisão mudar.
- **agy/copilot no Emacs (exceção a "CLIs no terminal"):** mantidos como exceção consciente — `+carlos/agy-prompt` (`C-c A g`) e `+carlos/copilot-explain-region` (`C-c A c`) (AGENTS.md §0, 2026-08-09).
- **Limpeza de artefatos de build:** política criada (2026-08-09) — `just clean`/`clean-prod` (`.elc`/`.eln` + `eln-cache/`) e `just rebuild`/`rebuild-prod`. Rebuild completo em repo e prod + `just test-all` OK (146 testes, 0 falhas). Ver AGENTS.md "Política de Limpeza de Artefatos de Build" e roadmap 2026-08-09.
- **Formato de tool call do Magent (DSML):** adicionada diretriz nº 6 em `+carlos/magent-system-directives` ensinando o formato textual parseável (`<tool_calls>`/`<invoke name=...>`/`<parameter name=...>`), injetada no system message via advice `:filter-return` em `magent-agent--compose-system-message`. Motivo: Qwen3.5-9B sob contexto pesado emitiu `<tool_call>/<function=>` (Claude-XML) como reasoning, que o parser do magent ignora (2026-08-10). Testes: `myemacs-magent-dsml-*` (150 testes, 0 falhas).
- **Magent: tool call no reasoning nunca executa (reforço do DSML, 2026-08-10):** diagnóstico — o magent só parseia DSML do stream de content (`magent-llm-gptel--emit-completed-or-textual-tool-calls`); reasoning vai direto para `magent-llm-reasoning-delta-event` e qualquer `<tool_call>` escrito lá é silenciosamente descartado. O gatilho da degradação do 9B foi um `find | head -50` → SIGPIPE (exit 141) → magent reporta tool FAILED. Reforços: diretriz 6 agora proíbe tool calls em reasoning/thinking e exige nativas no FINAL; nova diretriz 7 instrui evitar SIGPIPE (`find -maxdepth`/`rg --max-count` em vez de `| head`). Reprodução batch: contexto pesado + diretriz nova = 3/3 tool_calls nativos. Testes: `myemacs-magent-directives-reasoning-ban`, `myemacs-magent-directives-sigpipe`.
- **Magent: FSM de orquestração THINK/DECIDE/RETRY (2026-08-10):** prompt sozinho é probabilístico — nova sessão real falhou de novo (tool call Claude-XML no Thinking). Solução estrutural em `lisp/custom-magent.el`: advice `:around` em `magent-llm-gptel--emit-completed-or-textual-tool-calls` (o único choke point por onde passa todo turn vazio). THINK: reasoning acumulado em `:reasoning-chunks`; DECIDE: content vazio → parseia reasoning (DSML nativo `magent-llm-gptel--parse-dsml-tool-calls` + parser próprio Claude-XML `+carlos/magent--fsm-parse-claude-xml-tool-calls`) → emite eventos com `:source textual-dsml` (dispara normalização de args por schema); RETRY: sem call recuperável, `+carlos/magent--fsm-retry-empty-turn` re-dispara 1x via `magent-llm-gptel--continue-with-user-message` com forçagem nativa. Controle de logits descartado (API OpenAI-compatível do MLX não expõe logits). **Validada em sessão real (2026-08-10):** transcript `.agent-shell/transcripts/2026-08-10-02-34-17.md` mostra tool calls `<tool_call><function=bash>` e `<tool_call><function=read_file>` no Thinking recuperadas pela FSM e executadas (`[completed]`). Testes: `myemacs-magent-fsm-*` (7/7 no repo; prod autoritativo 159 testes, 0 falhas, 7 skipped).
- **Magent: sink de log read-only (2026-08-10, fix `464e196`):** `*magent-log*` fica read-only porque `magent-log-mode` deriva de `special-mode`; o sink nativo usa `inhibit-read-only`, mas o nosso `+carlos/magent-log-context` não — 107 erros `Buffer is read-only` spammaram o log na sessão real. Fix: insert envolto em `(let ((inhibit-read-only t)) ...)` em `lisp/custom-ai.el`. Teste `myemacs-magent-log-context` atualizado para abrir o buffer via `magent-log-buffer` (aplica o modo read-only) e garantir que o sink grava mesmo assim.
- **Default local MLX: gemma-4-e2b-it-4bit (2026-08-10):** benchmark dos 5 modelos locais (ver `docs/magent-reference.org`) — gemma lidera (31.4 tok/s, 2x o Qwen3.5-9B) e completou o turn do magent em 30.3s com reasoning estruturado; Qwen2.5-7B (sem reasoning, 0c) levou 99.5s e errou tool (`read` num diretório); os 14B (Qwen3/DeepSeek-R1) são lentos demais (3.7–8 tok/s). Troca do default em `+carlos/ai-local-backend` (custom-ai.el) + testes atualizados. O Qwen3.5-9B permanece como opção no backend (lista de modelos).
- **Scripts de avaliação de modelos locais (2026-08-10):** salvos em `bin/magent-batch-test.el` (reprodução batch do turn do magent sem GUI, drena `*magent-log*` via `MAGENT_SIM_MODEL`/`MAGENT_SIM_TIMEOUT`/`MAGENT_SIM_PROMPT`) e `bin/bench-local-models.py` (benchmark streaming tok/s, ttft, content/reasoning para MLX agnes:8081 e Ollama aa102-006l via `--ollama`). Usar para avaliar substitutos do 14B no host aa102-006l e validar a FSM real antes de trocar default. Critério de troca documentado em `docs/magent-reference.org`.

---
> Para o histórico cronológico detalhado de conquistas e decisões arquiteturais, consulte o [roadmap.org](roadmap.org).
