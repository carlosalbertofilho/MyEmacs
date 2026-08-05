# TODO — MyEmacs

## Histórico de Mudanças

### 2026-08-05 — Dashboard + Tipografia + Fixes
- [x] Criar `custom-dashboard.el` (estilo Nano Emacs)
- [x] Adicionar splash screen com fade-out
- [x] Adicionar widgets: quick actions, recent files, projects, agenda
- [x] Adicionar keybindings `C-c d d` / `C-c d r`
- [x] Integrar ao `init.el` com setup hook
- [x] Documentar em `guia_emacs.org`
- [x] Fix: `ob-gptel` void function (removido registro babel)
- [x] Fix: `gptel-org-mode` void function (adicionado fboundp guard)
- [x] Fix: `org-agenda-get-day-entries` wrong type argument (iterar org-agenda-files)
- [x] Fix: `nerd-icons-icon-for-dir` void function (adicionado :after nerd-icons)
- [x] Fix: Dirvish linhas largas (removido file-size/file-time, truncate-lines)
- [ ] Fix: Dirvish ícones gigantes (ajustado height 12, offset -2 — testar)
- [x] Adicionar tipografia premium ao dashboard (Space Grotesk + Inter)
- [ ] Adicionar Victor Mono para código/org (aguardando fontes no Nix)

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

## Bugs Conhecidos

| Bug | Severidade | Status | Notas |
|-----|------------|--------|-------|
| pdf-tools não compila macOS | Média | ⚠️ Workaround | Usar doc-view fallback |
| Dirvish ícones gigantes | Baixa | 🔧 Testing | height=12, offset=-2 |
| SuperChat não no MELPA | Baixa | ℹ️ Info | Instalar via straight/manual |
| mcp.el não no ELPA | Baixa | ℹ️ Info | Instalar via Nix/manual |

## Fontes Pendentes (Nix)

Solicitar ao agente Nix adicionar:
- `space-grotesk` → Dashboard títulos
- `inter` → Dashboard corpo
- `victor-mono` → Código + Org mode (ligatures + cursive italic)

Já instalada:
- `nerd-fonts.jetbrains-mono` → Fallback ícones

## Próximos Passos

1. [ ] Testar ícones dirvish com height=12
2. [ ] Adicionar fontes ao Nix
3. [ ] Configurar Victor Mono com ligatures
4. [ ] Testar SuperChat com fontes instaladas
5. [ ] Refinar dashboard com tipografia nova
6. [ ] Fase 4 — Cutoff
