# TODO — MyEmacs

## Histórico de Mudanças

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

## Plano de Correção — Bugs Identificados

### CRÍTICOS (corrigir antes de usar em produção)

| # | Bug | Arquivo | Linha | Ação |
|---|-----|---------|-------|------|
| 1 | **Keybinding conflitante `C-c h`**: consult-history vs stdheader | `custom-completion.el`, `custom-keybindings.el` | 32, 28 | Remover `C-c h` de consult, usar `C-c M-h` ou `C-c /` para consult-history |
| 2 | **Dirvish `dirvish-default-layout 10`**: valor inválido (0-5) | `custom-files.el` | 30 | Remover ou usar valor válido |
| 3 | **Dirvish ícones gigantes**: `dirvish-nerd-icons-height 12` (muito pequeno, causa ícones grandes) | `custom-files.el` | 75 | Mudar para 16-18 |
| 4 | **Múltiplos `with-eval-after-load 'dirvish`**: 6 blocos dispersos | `custom-files.el` | 58-109 | Consolidar em `:config` do `use-package` |
| 5 | **TRAMP duplicado**: settings em `custom-core.el` E `custom-files.el` | `custom-core.el:45`, `custom-files.el:131` | - | Manter apenas em `custom-files.el` |
| 6 | **Eglot em `prog-mode`**: `eglot-ensure` hook global causa lentidão | `custom-lang.el` | 16 | Usar hooks por modo específico |

### MÉDIOS (corrigir em breve)

| # | Bug | Arquivo | Linha | Ação |
|---|-----|---------|-------|------|
| 7 | **Emojis em `org-modern-priority`**: podem não renderizar em terminal | `custom-org.el` | 95-98 | Usar texto alternativo ou guardar com `fboundp` |
| 8 | **`superchat` depende de `llm.el`**: pode não existir | `custom-ai.el` | 172 | Guardar com `locate-library` ou `featurep` |
| 9 | **`gptel-integrations` require**: sem verificação | `custom-ai.el` | 157 | Usar `(require 'gptel-integrations nil t)` |
| 10 | **`custom-keybindings.el` com bindings comentados**: placeholders | `custom-keybindings.el` | 21-37 | Habilitar ou remover |
| 11 | **Eshell bound 2x**: `C-c e` em `custom-term.el` e `custom-keybindings.el` | `custom-term.el:39`, `custom-keybindings.el:47` | - | Remover duplicata |
| 12 | **`C-c E` para eshell**: capital E pode conflitar | `custom-keybindings.el` | 47 | Considerar binding diferente |

### BAIXOS (nice to fix)

| # | Bug | Arquivo | Linha | Ação |
|---|-----|---------|-------|------|
| 13 | **Dashboard usa `consult-fzf`**: pode não estar instalado | `custom-dashboard.el` | 276,422 | Guardar com `fboundp` ou fallback para `consult-find` |
| 14 | **Dashboard usa `magit-status`**: sem check se magit está carregado | `custom-dashboard.el` | 283,425 | Guardar com `fboundp` |

## Próximos Passos

### Imediatos (corrigir bugs)

1. [ ] **Fix #1**: Remover `C-c h` de consult-history, usar binding alternativo
2. [ ] **Fix #2**: Remover `dirvish-default-layout 10` ou usar valor válido
3. [ ] **Fix #3**: Ajustar `dirvish-nerd-icons-height` para 16-18
4. [ ] **Fix #4**: Consolidar 6 blocos `with-eval-after-load 'dirvish` em `:config`
5. [ ] **Fix #5**: Remover TRAMP duplicado de `custom-core.el`
6. [ ] **Fix #6**: Substituir `prog-mode` hook por hooks específicos em eglot

### Curto Prazo (melhorias)

7. [ ] **Fix #7**: Guardar emojis em org-modern-priority ou usar texto
8. [ ] **Fix #8**: Guardar superchat llm.el dependency
9. [ ] **Fix #9**: Guardar gptel-integrations require
10. [ ] **Fix #10**: Habilitar ou remover bindings comentados
11. [ ] **Fix #11**: Remover binding duplicado de eshell
12. [ ] **Fix #13**: Guardar consult-fzf no dashboard
13. [ ] **Fix #14**: Guardar magit-status no dashboard

### Backlog (feature work)

14. [ ] Adicionar fontes ao Nix (space-grotesk, inter, victor-mono)
15. [ ] Configurar Victor Mono com ligatures
16. [ ] Refinar dashboard com tipografia nova
17. [ ] Testar SuperChat com fontes instaladas
18. [ ] Fase 4 — Cutoff (Doom → Vanilla final)
