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

## 2. Decisões Registradas

- **Revisão e Limpeza de Modelos MLX (2026-08-13):** Removidos modelos antigos/redundantes em disco (`Qwen2.5-7B-Instruct-4bit` e `Qwen3-14B-4bit`), liberando **11.9 GB** de armazenamento. Adicionados os novos modelos do ecossistema MLX (`mlx-community/Qwen3.5-Coder-7B-Instruct-4bit` / `14B-4bit` e `mlx-community/gemma-4-9b-it-4bit`) à lista de suporte do backend `MLX Local` no `custom-ai.el` para otimizar codificação e raciocínio local no MacBook M2 com 24GB de VRAM.
- **Correção do MLX Local em sessões batch e Benchmark no agnes (2026-08-13):** Adicionado o parâmetro `:key "any"` ao backend de MLX Local no custom-ai.el para evitar erros de API key vazia (`wrong-type-argument stringp nil`) em execuções de testes batch/CI. O teste de rede do MLX Local em agnes passou com sucesso absoluto em apenas **1.81 segundos**.
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
- **Scripts de avaliação de modelos locais (2026-08-10):** salvos em `bin/magent-batch-test.el` (reprodução batch do turn do magent sem GUI, drena `*magent-log*` via `MAGENT_SIM_MODEL`/`MAGENT_SIM_TIMEOUT`/`MAGENT_SIM_PROMPT`) e `bin/bench-local-models.py` (benchmark streaming tok/s, ttft, content/reasoning para MLX agnes:8081 e Ollama aa102-006l via `--ollama`). Usar para avaliar substitutos do 14B no host aa102-006l e validar a FSM real antes de trocar default. Critério de troca documentado em `docs/magent-reference.org`.

---
> Para o histórico cronológico detalhado de conquistas e decisões arquiteturais, consulte o [roadmap.org](roadmap.org).
