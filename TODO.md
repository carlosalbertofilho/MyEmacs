# TODO — Planejamento Ativo e Backlog (MyEmacs)

## 1. Planejamento Corrente (Ações Atuais)

- [x] **Ajuste de Truncamento do `dirvish-side`:**
  - Configurar atributos minimalistas (`vc-state`, `nerd-icons`, `collapse`, `subtree-state`) na sidebar para evitar quebra de colunas em 30 de largura.
  - Ocultar a modeline e simplificar o cabeçalho no buffer da sidebar.
  - Sincronizar e validar visualmente no Emacs Vanilla.
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

- [ ] **Testar config completa em GUI** (não batch) para verificar compilação do `vterm-module`.
- [ ] Investigar por que `consult` e `nerd-icons` não foram encontrados no MELPA durante `just check` (Se persistente nas primeiras instalações do usuário).
- [ ] Verificar se pacotes estão em rebuild no MELPA ou se foram removidos/renomeados.

## 3. Planejamento Futuro / Backlog (Ordenado por Dificuldade)

1. [ ] **Testar SuperChat com fontes instaladas** (Dificuldade: Muito Baixa - Validação visual)
2. [x] **Substituir o dashboard customizado atual por `dashboard.el`** (Dificuldade: Baixa - Concluído!)
3. [x] **Configurar Victor Mono com ligatures** (Dificuldade: Média/Alta - Concluído!)
4. [x] **Refinar o dashboard com a tipografia nova instalada** (Dificuldade: Média/Alta - Concluído!)
5. [ ] **Fase 4 — Cutoff (Doom → Vanilla final)** (Dificuldade: Alta - Script `bin/cutoff-migration.sh` pronto, pendente execução pelo usuário)

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
