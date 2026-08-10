# TODO — Planejamento Ativo e Backlog (MyEmacs)

> **Histórico de planos concluídos (0.5–0.27):** todos implementados, validados e
> arquivados no [roadmap.org](roadmap.org) (Linha do Tempo). Este arquivo mantém
> apenas pendências ativas, backlog futuro e decisões registradas.
> Revisão arquivamento: 2026-08-09.

## 1. Pendências de Investigação (Bugs)

- [ ] **Testar config completa em GUI** (não batch) para verificar compilação do `vterm-module`.
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

---
> Para o histórico cronológico detalhado de conquistas e decisões arquiteturais, consulte o [roadmap.org](roadmap.org).
