import re

with open("TODO.org", "r") as f:
    todo_content = f.read()

roadmap_entries = """** 2026-08-22 — [CONCLUÍDO] Factory Reset do Ambiente Oficial (just factory-reset)
   - Script `bin/factory-reset.sh` com nuke + clone fresco preservando estado em backup temporário em `/tmp`.
   - Receita `just factory-reset` completa (script + install + compile-prod + check-prod).
   - Testes estruturais em `factory-reset-test.el` e documentação atualizada em `AGENTS.md` e `docs/dev-workflow.org`.

** 2026-08-22 — [CONCLUÍDO] Refatoração Arquitetural e Governança do Magent (D5)
   - Política Estrita de Documentação e RAG: regra inegociável no `AGENTS.md`.
   - Desmembramento do `custom-magent-subagent.el` (movendo contexto para `context.el` e ciclo de vida para `fsm.el`).
   - Documentação RAG atualizada em `docs/magent-reference.org` (Arquitetura D5, APIs de Jobs e injeção de parent_context).

** 2026-08-21 — [CONCLUÍDO] Resolver 4 problemas de configuração (Jinx, Electric Pair, Cape, Indent-bars)
   - Resolução de dicionários do Jinx (macOS + Nix) corrigida em `custom-core.el`.
   - Auto-fechamento de pares ativado (`electric-pair-mode`).
   - Autocomplete e Snippets unificados via Cape (`cape-super-capf`).
   - Fallback visual para o Indent-bars configurado em `custom-ui.el`.
   - Buffer de testes (`*ert*`) ancorado no rodapé via regex corrigida.

** 2026-08-20 — [CONCLUÍDO] Permissoes e UI
   - Centralização de aprovações no `magent-approval.el`.
   - Integração de ACP visual no chat com botões visuais `[ Allow ] [ Deny ]` através do `magent-acp.el`.

** 2026-08-20 — [CONCLUÍDO] Integracao do Forge (Magit) e Ferramentas Git/Forge
   - Configuração do Forge no Emacs habilitada.
   - Ferramentas curadas implementadas: `forge_read_issue` e `forge_list_pull_requests`.
   - Permissões na equipe configuradas (`coder`, `tech-writer`, `qa`).
   - Suíte de Testes Forge adicionada (`git-test.el`).

** 2026-08-18 — [CONCLUÍDO] D5. Context Sharing Dinamico e Estruturas Duraveis
   - Persistência de Jobs de Subagente via `magent-agent-job`.
   - Integração do `magent-ledger` ligando `tool-call` e `tool-output`.
   - Parser de regras locais (AGENTS.md) integrado.
   - Extração de contexto pai injetado com `<parent_context>`.
"""

# Extract the block to delete (lines 30 to 86)
# and the block to delete (lines 147 to 233)
with open("TODO.org", "r") as f:
    lines = f.readlines()

new_lines = lines[:29] + lines[86:146] + lines[233:]

with open("TODO.org", "w") as f:
    f.writelines(new_lines)

with open("roadmap.org", "r") as f:
    roadmap_lines = f.readlines()

for i, line in enumerate(roadmap_lines):
    if line.startswith("* Linha do Tempo"):
        roadmap_lines.insert(i + 2, roadmap_entries + "\n")
        break

with open("roadmap.org", "w") as f:
    f.writelines(roadmap_lines)

print("Done")
