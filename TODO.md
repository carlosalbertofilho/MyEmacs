# TODO — Planejamento Ativo e Backlog (MyEmacs)

> **Histórico de planos concluídos (0.5–0.27):** todos implementados, validados e
> arquivados no [roadmap.org](roadmap.org) (Linha do Tempo). Este arquivo mantém
> apenas pendências ativas, backlog futuro e decisões registradas.
> Revisão arquivamento: 2026-08-09.

## 1. Pendências de Investigação (Bugs)

- [ ] **Testar config completa em GUI** (não batch) para verificar compilação do `vterm-module`.
- [ ] **Validar fix DSML reforçado do Magent em sessão real** (2026-08-10): em sessão real o Qwen3.5-9B ainda emitiu tool call no stream de **reasoning** (`<tool_call><function=bash>`), que o magent **nunca executa** (só o content é parseado, magent-llm-gptel.el:760–770 vs 776–793). Reforços aplicados: diretriz 6 proíbe tool calls em reasoning/thinking e exige chamadas nativas no FINAL; diretriz 7 nova evita `find | head` (SIGPIPE exit 141 que o magent marca como tool FAILED e desestabiliza o modelo). Reprodução batch com contexto pesado (AGENTS.md + 9 tools + histórico de 141): **3/3 tool_calls nativos**. Falta confirmar numa sessão real de vários turns.
- [ ] Investigar por que `consult` e `nerd-icons` não foram encontrados no MELPA durante `just check` (se persistente nas primeiras instalações do usuário).
- [ ] Verificar se pacotes estão em rebuild no MELPA ou se foram removidos/renomeados.

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

---
> Para o histórico cronológico detalhado de conquistas e decisões arquiteturais, consulte o [roadmap.org](roadmap.org).
