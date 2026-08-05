# TODO — Planejamento Ativo e Backlog (MyEmacs)

## 1. Planejamento Corrente (Ações Atuais)

- [x] **Ajuste de Truncamento do `dirvish-side`:**
  - Configurar atributos minimalistas (`vc-state`, `nerd-icons`, `collapse`, `subtree-state`) na sidebar para evitar quebra de colunas em 30 de largura.
  - Ocultar a modeline e simplificar o cabeçalho no buffer da sidebar.
  - Sincronizar e validar visualmente no Emacs Vanilla.

## 2. Bugs Conhecidos e Pendências (Investigação)

- [ ] **URGENTE**: Investigar `ob-mermaid` não encontrado em modo interativo (funciona em batch). Verificar:
  - (1) pacote instalado via Elpaca?
  - (2) autoloads gerados?
  - (3) `elpaca-status` mostra instalado?
- [ ] Investigar por que `consult` e `nerd-icons` não foram encontrados no MELPA durante `just check`.
- [ ] Verificar se pacotes estão em rebuild no MELPA ou se foram removidos/renomeados.
- [ ] Testar config completa em GUI (não batch) para verificar compilação do `vterm-module`.

## 3. Planejamento Futuro / Backlog (Ordenado por Dificuldade)

1. [ ] **Testar SuperChat com fontes instaladas** (Dificuldade: Muito Baixa - Validação visual)
2. [ ] **Substituir o dashboard customizado atual por `dashboard.el`** (Dificuldade: Baixa - Configuração declarativa)
   - Exibir um banner em formato de arte ASCII contendo "My Emacs".
3. [ ] **Configurar Victor Mono com ligatures** (Dificuldade: Média/Alta - Setup de composição de fontes para ligaduras no Emacs)
4. [ ] **Refinar o dashboard com a tipografia nova instalada** (Dificuldade: Média/Alta - Estética fina)
5. [ ] **Fase 4 — Cutoff (Doom → Vanilla final)** (Dificuldade: Alta - Transição e consolidação de workflows)

---
> Para o histórico cronológico detalhado de conquistas e decisões arquiteturais do projeto, consulte o [roadmap.org](file:///Users/carlosfilho/Projects/Github/MyEmacs/roadmap.org).
