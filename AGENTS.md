# AGENTS.md — MyEmacs Configuration Guidelines

> **Purpose:** Authoritative guide for AI agents working on this Emacs configuration project.
> **Project:** Vanilla Emacs migration from Doom Emacs using Emacs Bedrock template.
> **Workflow:** Work in `~/Projects/Github/MyEmacs` → commit/push → `just sync` → test.

---

## Quick Sync Commands

```bash
# In ~/Projects/Github/MyEmacs (this repo)
git add -A && git commit -m "feat: description" && git push

# In ~/.config/emacs (official environment) — via Justfile (não usar git stash/pull manual)
just sync                # fetch + reset --hard origin/main (deixa o prod espelhando o remote)

# Teste o ambiente oficial
just test-run            # Emacs interativo no prod
just compile-prod        # byte-compile no prod (gate zero-warning, saída filtrada)
just check-prod          # boot batch no prod (verificação pós-sync)
```

---

## Justfile Commands

Todo o fluxo de dev/teste/sync é orquestrado pelo `Justfile`. **Prefira `just`
a comandos manuais.** O diretório-alvo de teste/sync é `~/.config/emacs`
(override via `EMACS_TEST_DIR`).

| Recipe | O que faz | Quando usar |
|--------|-----------|-------------|
| `just run` | Abre o Emacs com a config do repo (dev) | Desenvolver/depurar neste diretório |
| `just test-run` | Abre o Emacs no prod (`~/.config/emacs`) | Verificar interativamente o ambiente oficial |
| `just install` | Instala/atualiza pacotes (batch) | Primeira vez ou após trocar de máquina |
| `just install-prod` | Idem no prod (`{{prod_dir}}`) | Instalação no ambiente oficial |
| `just check` | Boot rápido da config do repo (smoke) | Smoke test no dev |
| `just check-daemon` | Boot do daemon com `--debug-init` + coleta de warnings (prod) | Detectar erros de inicialização do daemon |
| `just check-prod` | `check-daemon` + boot batch do prod (smoke) | Smoke test pós-sync |
| `just clean` | Remove `.elc`/`.eln` stale + `eln-cache/` do repo | Artefatos de build antigos causando erro |
| `just clean-prod` | Remove `.elc`/`.eln` stale + `eln-cache/` do prod | Idem no ambiente oficial |
| `just clean-all` | `clean` + apaga `elpaca/builds` do repo | Limpeza total do dev |
| `just clean-all-prod` | `clean-prod` + apaga `elpaca/builds` do prod | Limpeza total do prod |
| `just rebuild` | `clean` + `compile` no repo (recompila tudo) | Rebuild limpo do dev |
| `just rebuild-prod` | `clean-prod` + `compile-prod` (recompila tudo) | Rebuild limpo do prod |
| `just compile-modules` | Compila módulos nativos (vterm, tree-sitter) no repo | Após trocar de máquina |
| `just compile-modules-prod` | Idem no prod | Corrige gramáticas/autoloads quebrados no prod |
| `just compile` | `compile-modules` + byte-compila `lisp/` do repo (warnings = erro, saída filtrada) | Portão de compilação pré-commit |
| `just compile-prod` | `compile-modules-prod` + byte-compila `lisp/` do prod (warnings = erro, saída filtrada) | Gate autoritativo pós-sync |
| `just checkdoc` | Valida docstrings | Portão de documentação |
| `just org-lint` | Valida balanceamento BEGIN/END, headings e referências a `TODO.org` | Portão de docs org |
| `just lint-native` | Linters nativos (`defun-parens` + `arity`) | Portão de AST/aridade dos `.el` |
| `just lint` | `compile` + `checkdoc` + `org-lint` + `lint-native` | Portão rápido completo |
| `just test` | Suíte ERT completa em batch (canônico) | Suíte de regressão |
| `just test-prod` | Suíte ERT completa contra o prod (`{{prod_dir}}`) | Regressão no ambiente oficial |
| `just test-batch` | Alias de `test` (compatibilidade) | Comandos documentados antigos |
| `just test-ai` | Testes de IA (offline; rede fica skipped) | Regressão de IA |
| `just test-network` | Testes de rede ao vivo (opt-in) | Validar backends reais |
| `just download-dicts` | Baixa dicionários Hunspell pt_BR/en_US para o Jinx | Primeira vez no macOS |
| `just test-all` | `lint` + `test` | Portão completo |
| `just check-all` | `check` + `test-all` | Bateria completa antes de commit |
| `just triage` | `check-all` + resumo IA dos erros | Investigar falhas na suíte |
| `just sync` | `fetch` + `reset --hard origin/main` no prod | Publicar alterações no prod |
| `just deploy "msg"` | `check-all` → commit → push → `sync` → `compile-prod` → `check-prod` | Deploy em um comando |
| `just ci` | `check-all` | Pipeline de CI |
| `just promote` | Migração Doom→Vanilla (legado) | Raramente |
| `just factory-reset` | Nuke + clone fresco do prod (estado preservado em `/tmp`) + `install-prod` + `download-dicts` + `compile-prod` + `check-prod` | Reset total do ambiente oficial (emergência) |

**`just sync` é destrutivo por design:** faz hard reset do prod para
`origin/main`, descartando quaisquer modificações locais em arquivos trackeados
(presume-se que sejam redundantes com o que já foi commitado). Arquivos de
runtime não-trackeados (`elpaca/`, `tree-sitter/`, `agent/`, `bookmarks`,
`magent/sessions/`, `recentf`, etc.) **não são tocados**.

**`just factory-reset` vai além:** apaga o prod inteiro e reclona de
`origin/main`, preservando apenas os arquivos de estado essenciais
(`bookmarks`, `recentf`, `places`, `history`, `savehist`, `custom-file.el`,
`magent/sessions/`) em backup temporário em `/tmp`. Pede confirmação
interativa e aborta com alterações trackeadas não-commitadas; `FORCE=1`
pula as guardas. Detalhes em `docs/dev-workflow.org`.

---

## Política de Limpeza de Artefatos de Build

Artefatos de build antigos (`.elc`, `eln-cache/`) podem causar erros
(`void-function`, `void-variable`, comportamento divergente) quando o fonte
`.el` muda mas o objeto compilado stale permanece. Política:

- **Sempre preferir `.el` mais novo que `.elc`:** `load-prefer-newer-source t`
  já está em `early-init.el`; em caso de dúvida, limpe e recompile.
- **Suspeitar de artefato stale quando:** erro que some após `just rebuild-prod`
  + `just check-prod`, ou warning de `load` de `.elc` antigo no boot.
- **Ao mudar um `lisp/custom-*.el`:** rode `just rebuild` (repo) antes do
  commit para garantir que o `.elc` local não esconda o fonte novo.
- **Pós-sync no prod:** `just rebuild-prod` (limpa + recompila) antes de
  `just check-prod` quando houver indício de build stale.
- **Escopo:** limpa apenas `.elc`/`.eln` e `eln-cache/` (rápido, sem rede).
  Para limpeza total (`tree-sitter/`, `vterm-module.so`, reinstall elpaca) use
  `just clean-prod` manualmente + `just compile-modules` + `just install`.
- **`eln-cache/` é regenerável** a partir dos `.el`/`.elc` — nunca é preciso
  manter manualmente; pode ser apagado a qualquer momento.

---

## Project Architecture

```
~/.config/emacs/                  ← EMACSDIR
├── early-init.el                 ← Native-comp optimization, GC threshold
├── init.el                       ← Elpaca bootstrap, load-path, require modules
├── custom-file.el                ← Generated by M-x customize (auto-managed)
├── lisp/
│   ├── custom-core.el            ← Fonts, GPG, SSH, API keys, editor defaults, line numbers
│   ├── custom-ui.el              ← ef-themes, mood-line, which-key
│   ├── custom-writing.el         ← olivetti, org-modern (escrita)
│   ├── custom-completion.el      ← vertico, consult, corfu, marginalia, orderless, embark, tempel
│   ├── custom-files.el           ← dirvish, ibuffer, TRAMP, project, rfc-mode
│   ├── custom-term.el            ← vterm, eshell, eshell-git-prompt
│   ├── custom-keybindings.el     ← C-c prefix keybindings
│   ├── custom-lang.el            ← eglot, treesit-auto, languages (go/ts/python/cc/nix/rust)
│   ├── custom-markdown.el        ← markdown-mode
│   ├── custom-norminette.el      ← Norminette setup (JSON-based, flycheck; carregado via custom-42)
│   ├── custom-org.el             ← org-mode, babel, jupyter, pdf-tools, table fit-to-window
│   ├── custom-42.el              ← 42 School: header42, flycheck-norminette, C style
│   ├── custom-ai.el              ← gptel backends/dynamic-router, cascata de cotas, gptel-request
│   ├── custom-ai-schema.el       ← Schemas JSON compartilhados (gptel/gramática)
│   ├── custom-dev.el             ← Dev env + ERT/REPL tools (`C-c D`, gerador de testes)
│   ├── custom-jinx.el            ← jinx spellcheck (enchant) + grammar correction via AI
│   ├── custom-magent.el          ← Magent native coding agent (fachada, agent-shell)
│   ├── custom-magent-commands.el ← Magent transient/commands (`C-c A m`)
│   ├── custom-magent-context.el  ← Magent context (projeto, per-file, compactação, <parent_context>)
│   ├── custom-magent-fsm.el      ← Magent FSM de orquestração (15 tools, watchdog, jobs duráveis, ledger call-id↔job, reconciliação stale pós-restart, Circuit Breaker)
│   ├── custom-magent-tools.el    ← Magent curated tools (flycheck_errors, lsp_navigation, snippet_expand) + ferramentas nativas
│   ├── custom-magent-subagent.el ← Magent subagent perfis + roteamento de modelo + apply-profile/spawn (ocultação de tools do orquestrador)
│   ├── custom-magent-ui.el       ← Magent UI (transient, sessões, painel de atividade, spinner)
│   ├── custom-magent-infra.el    ← Infra base (Circuit Breaker, sanitizadores, project-root, helpers batch-safe)
│   ├── custom-magent-prompts.el  ← Prompts/diretivas do Magent (separados do FSM)
│   ├── custom-magent-buffer.el   ← Operação em buffer vivo (buffer_insert/replace/undo, lsp_hover, describe_elisp_symbol)
│   ├── custom-magent-team.el     ← Equipe de especialistas (coder, sysadmin, planner, tech-writer, auditor, sec-ops, qa)
│   ├── custom-magent-run.el      ← `magent-cli run` — launcher batch UI-neutral (magent-runtime-submit)
│   ├── custom-magent-proxy.el    ← Lifecycle do proxy AGY (auto-start, 3-tier fallback)
│   ├── custom-magent-lint.el     ← Linters nativos (defun-parens + arity)
│   ├── custom-magent-tool-*.el   ← Tools Magent por domínio (git, devops, rfc, smart-edit, ast, debug, lsp, pkg, test)
│   ├── custom-knowledge.el       ← Denote (Zettelkasten)
│   ├── custom-git.el             ← magit, justl, commit message with IA
│   └── custom-dashboard.el       ← Nano-style dashboard
├── site-lisp/
│   ├── header42.el               ← 42 School header (copied from Doom)
│   └── flycheck-norminette.el    ← Norminette checker (copied from Doom)
├── lib/
│   └── agy_proxy/                ← Proxy HTTP local OpenAI-compatible (router, upstream, quota, tool_bridge)
├── tests/                        ← Suíte ERT por área (load-tests.el carrega tudo)
├── docs/                         ← RAG reference docs for each package
├── bin/                          ← Wrapper scripts (magent-cli, org-lint, factory-reset, bench-, rag/log/skill-convert)
└── elpaca/                       ← Package manager (git-cloned, NOT committed)
```

---

## Elisp Coding Standards

### 0. Exceções conscientes

Decisões de produto do usuário que sobrepõem diretrizes genéricas (2026-08-09):

- **agy/copilot no Emacs (exceção a "CLIs no terminal"):** manter
  `+carlos/agy-prompt` (`C-c A g`) e `+carlos/copilot-explain-region`
  (`C-c A c`) como atalhos convenientes, apesar da diretriz de usar CLIs fora
  do Emacs. Não remover sem perguntar.
- **Savepoint v1.0 — FSM Resilience & FinOps $0.00 (Commit `267645d` / Tag `savepoint` / `savepoint-v1.0-fsm-resilience`):**
  - **Motor FSM & Resiliência:** 3 Pilares implementados (Circuit Breaker stateful, Sanitizador ANSI/XML `+carlos/magent-sanitize-string`, Dynamic GC 100MB e Auto-Resync de `buffer_conflict`).
  - **Matriz de Roteamento Híbrida (FinOps $0.00 + Performance):** Topologia sensível ao Host:
    - **agnes (Mac M2):** `gemma4` local (Orquestrador, GPU Metal) / `agy` via Proxy Gemini (Planejamento/QA) / `big-pickle` local (Editor Especialista).
    - **aa102-006l (EliteDesk):** `gemini-2.5-flash` nuvem (Orquestrador, poupa CPU) / `agy` via Proxy Gemini (Planejamento/QA) / `big-pickle` local (Editor).
  - **Bateria de Delegação:** 12 Rounds executados e validados com 100% de sucesso (12/12 PASSED).
  - **Suíte de Testes ERT:** 422/422 testes passados (0 falhas) e compilação `compile-prod` com 0 Warnings.

### 1. File Structure

Every `custom-*.el` file MUST follow this template:

```elisp
;;; custom-NAME.el --- Description -*- lexical-binding: t; -*-

;;; Commentary:
;; Brief description of what this file does.

;;; Code:

;; ── Section ──────────────────────────────────────────────────────────
;; Package config here

(provide 'custom-NAME)
;;; custom-NAME.el ends here
```

### 2. Package Configuration

**ALWAYS use `use-package` with Elpaca:**

```elisp
;; Built-in packages: :ensure nil
(use-package org :ensure nil :config ...)

;; External packages: :ensure t (Elpaca installs from git)
(use-package vertico :ensure t :config (vertico-mode 1))

;; Packages with hard requires (boot-critical, :demand t): use a SCOPED wait
;; (:ensure (:wait t)) instead of a global (elpaca-wait) — blocks only until
;; that package activates, avoiding the fragile global-barrier ordering.
(use-package flycheck :ensure (:wait t) :demand t)
(require 'something-that-needs-flycheck)
```

**Política de waits do Elpaca (2026-08-16):** prefira `:ensure (:wait t)` para
pacotes carregados sincronamente no boot (`:demand t`). Evite `(elpaca-wait)`
espalhado: cada chamada é uma *barreira global* (espera a fila inteira).
Waits globais mantidos por design: bootstrap do `elpaca-use-package`
(init.el:64), grupo de completion (custom-completion.el:30, pacotes que
carregam juntos) e o catch-all final (init.el:182, rede de segurança). Não
migre pacotes **deferidos** (sem `:demand`) para `:wait t` — só adicionaria
bloqueio sem ganho.

**Load order:** Use `:after` for dependencies:

```elisp
(use-package dirvish
  :ensure t
  :after nerd-icons
  :config ...)
```

**Consolidate `with-eval-after-load`:** Don't scatter multiple blocks. Put them in `:config` or use a single block.

### 3. Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Custom functions | `+carlos/function-name` | `+carlos/gptel-agent-run` |
| Custom variables | `+carlos/variable-name` | `+carlos/dashboard-buffer-name` |
| Internal helpers | `+carlos/--helper` | `+carlos/denote-silo--with-dir` |
| Faces | `+carlos/face-name` | `+carlos/dashboard-title` |

### 4. Safe Patterns

**Guard against missing functions:**
```elisp
(when (fboundp 'some-function)
  (some-function))
```

**Safe require:**
```elisp
(when (require 'some-package nil t)
  ;; package loaded
)
```

**Guard package-specific modes:**
```elisp
(with-eval-after-load 'gptel
  (when (require 'gptel-org nil t)
    (when (fboundp 'gptel-org-mode)
      (gptel-org-mode 1))))
```

**Use `when-let*` for chained conditions:**
```elisp
(when-let* ((proj (project-current))
            (root (project-root proj))
            (dir (expand-file-name ".agents/gptel/" root))
            (file-directory-p dir))
  (add-to-list 'gptel-agent-dirs dir))
```

**Ferramenta Nativa para Edição de Lisp (`elisp_smart_edit`):** Para inserir snippets, criar novas definições (`defun`, `use-package`, `deftest`, `defcustom`, `with-eval-after-load`), refatorar símbolos ou validar arquivos `.el`, os agentes DEVEM SEMPRE PREFERIR utilizar a ferramenta nativa `elisp_smart_edit` (`+carlos/magent-tool-elisp-smart-edit` em `lisp/custom-magent-tools.el`). Ela garante pareamento perfeito de parênteses com rollback transacional em caso de erro sintático e consumo mínimo de tokens (~30 tokens).

**Emacs 30 gotcha — `defvar` sem INITVALUE NÃO liga a variável:**
Desde o Emacs 30, `(defvar X)` sem valor inicial deixa X **void** (só marca a
variável como special para o byte-compiler). Consequências:
- `(defvar gptel-agent-dirs)` como forward declaration → `void-variable` em
  runtime quando lida antes do pacote carregar.
- `(defvar gptel-agent-dirs nil)` **clobbera o default de `defcustom`s** com
  valor não-nil (ex.: `gptel-agent-dirs` do gptel-agent aponta para o diretório
  de agentes embutido; `gptel-directives` do gptel tem 4 diretivas padrão).

Regras:
- Forward declarations que **só** suprimem warning do byte-compiler → forma
  pelada `(defvar X)` e use guards (`unless (boundp 'X) (setq X nil)`) antes de
  ler/escrever antes do pacote dono carregar.
- Variáveis cujo default não-nil importa (defcustom de pacote) → NUNCA
  pré-declare com `nil`; guarde o runtime.
- `use-package :after X` é **ignorado** com `use-package-expand-minimally t`
  (init.el). Use `with-eval-after-load 'X` explícito para carregar/configurar
  pacotes dependentes.

### 5. Anti-Patterns (NEVER DO)

| Anti-Pattern | Why | Correct Approach |
|-------------|-----|-----------------|
| `advice-add` on gptel-agent functions | Causes "Wrong number of arguments" bug | Call functions directly |
| Multiple `with-eval-after-load` for same package | Scattered, hard to maintain | Consolidate in `:config` |
| `setq` on custom options | Doesn't trigger customization hooks | Use `setq` only for non-custom vars; `:custom` in use-package |
| Missing `:ensure nil` for built-in packages | Unnecessary MELPA lookup | Always add `:ensure nil` |
| Hardcoded paths | Not portable | Use `expand-file-name` with `~` or variables |
| `magit-git-string` without magit loaded | Void function | Use `shell-command-to-string` or `vc-git-*` |
| Generic Bash/Sed edits by External CLIs | Breaks AST and bypasses validations | **External agents (AGY, Aider, etc.) MUST ALWAYS prefer Emacs native tools** (like `elisp_smart_edit`, `org_smart_edit`) or call Emacs in `--batch` to mutate project files. Utilize the `bin/magent-cli` wrapper to easily bridge external CLIs to Emacs native FSM tools. | Além disso, agentes rodando sob a engine Antigravity/AGY DEVEM habilitar a skill `myemacs-native-tools` e segui-la religiosamente.

### 6. SOLID Architecture & Domain Isolation (STRICT RULE)

O ecossistema do Magent e de IA do MyEmacs deve **OBRIGATORIAMENTE** seguir os princípios SOLID (especialmente Responsabilidade Única - SRP e Inversão de Dependência - DIP):
- **Evite "God Files":** Não agrupe ferramentas não relacionadas no mesmo arquivo. Separe ferramentas por domínio (ex: `custom-magent-tool-git.el`, `custom-magent-tool-devops.el`).
- **Isole a Infraestrutura Base:** Código que conserta aridades, lida com sanitização de texto, ou implementa padrões de infraestrutura (como Circuit Breaker) deve ficar isolado (ex: `custom-magent-infra.el`).
- **Isole a Configuração do Ambiente:** A extração de variáveis de ambiente/API keys (`/etc/api-keys.sh`) é responsabilidade primária do sistema (ex: `custom-core.el` ou módulo de auth), não da configuração dos clientes de IA.
- **FSM Pura e Inversão de Dependência:** Máquinas de Estado (`custom-magent-fsm.el`) NÃO devem injetar prompts, formatar strings de contexto, ou controlar UI (spinners) diretamente. Elas devem apenas transicionar estados e disparar Hooks (`run-hooks`), deixando a UI ou gerenciadores de prompt assinarem e reagirem a essas mudanças de estado de forma passiva.
- **Não solde regras de negócio ao gerenciamento de contexto:** Se um módulo é responsável por contar tokens, ele não deve possuir chamadas de shell imperativas como `git rev-parse HEAD` soldadas à sua lógica contábil, e os prompts em texto cru devem ficar em módulos separados.
- **Avalie a coesão antes de estender arquivos:** Sempre planeje a arquitetura do código antes de implementar novas funcionalidades, garantindo que o módulo modificado mantenha seu domínio estritamente focado.

---

## Org Documentation Standards

> Todos os arquivos `.org` do repo (TODO.org, roadmap.org, docs/*.org,
> README.org) devem ser **Org válido e lint-clean**. O portão `just org-lint`
> (parte de `just lint`) verifica balanceamento de `#+BEGIN_*`/`#+END_*`,
> ausência de headings malformados (espaço antes de `*`) e ausência de
> referências ao nome antigo `TODO.md` (o arquivo é `TODO.org`).

### 1. Nome canônico

- O arquivo de planejamento é **`TODO.org`** — nunca `TODO.md`.
- Referências a ele em qualquer `.org`/`.md` devem usar `TODO.org` (o org-lint
  falha se aparecer `TODO.md`).

### 2. Header canônico (todo arquivo `.org`)

```org
#+TITLE: <Título>
#+AUTHOR: Carlos Filho
#+DATE: <criação: AAAA-MM-DD>
#+LAST_MODIFIED: <última edição: AAAA-MM-DD>
#+DESCRIPTION: <uma linha sobre o escopo>        ; opcional (docs/ recomendado)
#+FILETAGS: :PLANNING:                           ; TODO.org/roadmap.org
#+FILETAGS: :RAG:DOCS:                            ; docs/*.org
#+OPTIONS: toc:2 num:t                            ; numeração automática, sem números manuais
```

Não misture `#+title` com `#+TITLE` — use o case `#+TITLE` (keyword case é
insensível no Org, mas a consistência facilita o parsing/regex).

### 3. AST org nativa para planejamento (regra de ouro)

- `TODO.org` e `roadmap.org` usam **somente** AST org: headings (`*`, `**`,
  `***`), keywords `TODO`/`DONE`/`CANCELLED`/`BLOCKED` e gavetas `:PROPERTIES:`
  (`:CREATED:`, `:STATUS:`, `:ASSIGNEE:`).
- Nada de Markdown em arquivos org: sem `- [ ]`, sem `~~strikethrough~~`, sem
  headings `#`.
- Não numerar headings manualmente (`** 1. X`): a numeração vem de
  `#+OPTIONS: num:t`.
- Estado de progresso em `:PROPERTIES:` ou keyword `TODO` — **sem emojis**
  (✅/⚠️/🔲/🏆/📝/⏸️) e sem rótulos soltos como `**STATUS: X.**`.

### 4. Inline code e destaque

- Inline code sempre com `=code=`. Evitar backticks ``` ` ``` e `~...~` em
  prosa org (o `~` colide com o syntax highlight de ênfase do Org).
- Destaque forte com `*texto*`; código em bloco com `#+begin_src`/`#+end_src`.

### 5. Blocos sempre balanceados

- Todo `#+BEGIN_*` precisa do `#+END_*` correspondente (o org-lint falha).
- Prefira blocos completos e fechados; blocos quebrados quebram o parser e o
  chunking do RAG.

### 6. Status padronizados (sem emoji)

| Rótulo | Uso |
|--------|-----|
| `DONE` | concluído |
| `EM ANDAMENTO` | em execução |
| `BACKLOG` | planejado, não iniciado |
| `PLANO APROVADO` | plano validado, pronto para executor |
| `PENDENTE` | precisa correção |
| `DECIDIDO` | decisão registrada |
| `ARQUIVADO` | movido para histórico (roadmap.org) |

### 7. Arquivos de referência (docs/*.org) e RAG (Política de Ouro)

- **Regra inegociável:** `TODO.org` e `roadmap.org` são ESTRITAMENTE trackers e changelogs. Eles NÃO servem como documentação de API ou arquitetura.
- **Toda alteração arquitetural, nova API, FSM ou mudança de comportamento (especialmente no pacote `magent`) DEVE OBRIGATORIAMENTE ser refletida no respectivo arquivo de referência `.org` em `docs/` (ex: `docs/magent-reference.org`).** Isso garante que os próximos agentes tenham acesso ao contexto técnico no cache RAG.
- Nenhuma tarefa de refatoração ou criação de feature no `magent` pode ser considerada DONE sem que as APIs sejam documentadas no `docs/`.
- Docs de referência de pacote ficam em `docs/` com `#+FILETAGS: :RAG:DOCS:` e
  header canônico (TITLE/AUTHOR/DATE/LAST_MODIFIED/DESCRIPTION/OPTIONS).
- Cada arquivo tem um `* Visão Geral` no topo descrevendo o escopo.
- **Ferramenta Nativa de Introspecção RAG (`rag_create_doc`):** Para criar ou atualizar arquivos de referência `.org` sob `docs/`, os agentes DEVEM SEMPRE PREFERIR usar a ferramenta nativa `rag_create_doc` (`+carlos/magent-tool-rag-create-doc` em `lisp/custom-magent-tools.el`). Ela extrai assinaturas e docstrings nativas fisicamente instaladas no Emacs via introspecção Elisp (`documentation`, `help-function-arglist`), gerando documentos `.org` com o header canônico e tags `:RAG:DOCS:` com **custo zero de rede e consumo mínimo de tokens (~40 tokens)**.
- **Ferramenta Nativa de Busca de Contexto (`context_search`):** Busca rapidamente em arquivos `.org` e `.el` por símbolos, cabeçalhos ou docstrings usando RAG internamente. Disponível como `+carlos/magent-tool-context_search` em `lisp/custom-magent-tools.el`. Retorna lista de resultados com cabeçalhos e links.

---

## Known Bugs & Fixes

> Todas as regressões abaixo foram **resolvidas** e estão cobertas pela suíte
> ERT em `tests/`. Ao alterar config que mexa nesses pontos, os testes devem
> continuar passando (`just test-all`).

### Resolved (regression-guarded by tests)

| # | Bug (resolvido) | Onde o teste protege |
|---|-----------------|----------------------|
| 1 | `C-c h` conflito consult-history × stdheader → consult-history movido para `C-c /` | `tests/keybindings-test.el` |
| 2 | `dirvish-nerd-icons-height 12` (ícones pequenos) → `0.85` | `tests/files-test.el` |
| 3 | `dirvish-default-layout 10` inválido → `(1 0.11 0.55)` | `tests/files-test.el` |
| 4 | TRAMP duplicado → apenas `custom-files.el` | — |
| 5 | `eglot-ensure` em todos os prog-modes → hooks por-mode | — |
| 6 | Múltiplos `with-eval-after-load 'dirvish'` → consolidado em `:config` | — |
| 7 | Emojis em `org-modern-priority` → alternativas de texto | `tests/org-test.el` |
| 8 | `superchat`/`llm.el` → removidos | — |
| 9 | `gptel-integrations` sem guarda → `(require ... nil t)` | — |
| 10 | Binds comentados em `custom-keybindings.el` → removidos | — |
| 11/12 | `C-c e` duplicado → só em `custom-term.el` | `tests/term-test.el` |
| 13/14 | Dashboard referenciava `consult-fzf`/`magit` → dashboard nano reescrito | `tests/dashboard-test.el` |
| 15 | Submodelos: orquestrador fazia `spawn_agent` e encerrava o turno sem `wait_agent` → job órfão e FSM sem estados para subagente | hard rule na diretiva SUBAGENT LIFECYCLE + estados `subagent-running`/`subagent-waiting` + watchdog suprimido no wait | `tests/magent-fsm-test.el` (GRUPO 9) |

### Encontrados pela suíte (2026-08-06)

| Bug | Fix | Teste |
|-----|-----|-------|
| `C-c i` (gptel) sombreado por consult-imenu (use-package `:bind` de pacote deferido reaplica depois) | consult-imenu → `M-s i` | `myemacs-kbd-imenu-consult` |
| `+carlos/dashboard-open`/`-refresh` declarados e bindados mas **nunca definidos** (void-function em `C-c d d`/`C-c d r`) | definidos como wrappers de `dashboard-open`/`dashboard-refresh-buffer` | `myemacs-dashboard-commands-exist` |
| `git-commit` `C-c C-g` via hook (só aplicava em buffer real) | `define-key` direto no `git-commit-mode-map` via `with-eval-after-load 'git-commit` | `myemacs-git-commit-mode-map-bind` |

### Encontrados pela suíte (2026-08-07)

| Bug | Fix | Teste |
|-----|-----|-------|
| `custom-42.el:61: Error: reference to free variable ‘+carlos/c-formatter-42’` (macro `reformatter-define` expandida como função na ausência de reformatter em batch compile) | `reformatter` carregado síncronamente via `:demand t` e `(elpaca-wait)` no `custom-lang.el` | `just compile` |
| `void-variable +carlos/gptel-quick-local-backend` no boot-test e ai-test (falha ao testar dinâmicas de host) | Variáveis declaradas globalmente e testadas via mock unitário de `system-name` | `myemacs-ai-host-detection` |

### Encontrados pela suíte (2026-08-08)

| Bug | Fix | Teste |
|-----|-----|-------|
| `+carlos/gptel-request` repassava `:response_format (:type "json_object")` a `gptel-request`, keyword que não existe no `&key` do gptel 0.9.9.5 (erro "Keyword argument :response_format not one of (...)") — quebrava TODA chamada Ollama/MLX | JSON forçado via `:schema` (único mecanismo do gptel 0.9.9.5); o helper não força mais nada e `:schema (:type object)` isolado produz `{}` — o caller (gramática) passa `:schema (:type object :properties (:corrected (:type string)))` explícito | `myemacs-spell-grammar-schema-passthrough` (fake `cl-defun` com o mesmo `&key` reproduz o erro) |

### Encontrados pela suíte (2026-08-16)

| Bug | Fix | Teste |
|-----|-----|-------|
| `org-startup-with-latex-preview t` incondicional (custom-org.el) — abrir `.org` com fragmento LaTeX levantava `File mode specification error: (error Can't find 'latex' ...)` quando `latex`/`dvipng` não estão instalados | Guard no valor: `org-startup-with-latex-preview` só é `t` quando `(and (executable-find "latex") (executable-find "dvipng"))` — preserva preview onde o toolchain existe, silencia onde não há | `myemacs-org-latex-preview-guarded-by-toolchain` + `myemacs-org-open-with-latex-fragment-no-error` (tests/org-test.el) |
| `custom-magent-context.el:251:16: Error: Unused lexical variable ‘+carlos/magent-model-max-tier’` intermitente no `just compile`/`compile-prod` — `let` bindava a defcustom de custom-magent-tools (`.elc` stale no boot fazia o cconv do Emacs 30 tratá-la como lexical → warning→erro no gate) | Forward declaration `(defvar +carlos/magent-model-max-tier 'paid)` (default real, nunca `nil`) no bloco de declarações do context.el + `declare-function` para `gptel--model-name`/`project-root` — compile determinístico em qualquer estado de build parcial | `myemacs-magent-context-compiles-isolated` (tests/context-test.el; skip pré-sync) |

### Encontrados pela suíte (2026-08-21)

| Bug | Fix | Teste |
|-----|-----|-------|
| `+carlos/magent-render-parent-context` renderizava bloco `<parent_context>` com apenas `messages: 0` quando o contexto coletado era `nil` (injeção vazia e inútil no system prompt do subagente) | Guard `when-let* ((context context))` na renderização — contexto sem conteúdo → `nil`, nada é injetado | `myemacs-magent-subagent-render-parent-context-block` |
| Ledger call-id↔job atualizava entradas com `append` → chave duplicada no plist e `plist-get` devolvia sempre o valor antigo (`running` em vez de `completed` após `tool-call-end`) | Atualizações com `plist-put` sobre `copy-sequence` (substituição in-place da chave) | `myemacs-magent-subagent-ledger-tracks-spawn-and-wait` |
| Item "Validar a regra com um teste" (âncora do buffer `*ert*` no rodapé) marcado DONE sem teste criado | `tests/ui-test.el`: `myemacs-ui-ert-buffer-display-bottom` valida regex + `direction . bottom` | `myemacs-ui-ert-buffer-display-bottom` |

### Encontrados pela suíte (2026-08-27/28)

| Bug | Fix | Teste |
|-----|-----|-------|
| `Wrong type argument: gptel-tool` no `gptel-request` batch — 5 arquivos injetavam **plists cruas** em `gptel-tools` (`custom-magent-tool-{test,ast,lsp,pkg,debug}.el`), mas o gptel moderno exige **structs `gptel-tool`** (via `gptel-make-tool`, `gptel-request.el:1597`) | Cada tool: cria struct `gptel-make-tool` (`:args` no formato `(:name ... :type ...)`), registra entry (`:name ... :tool <struct> :permission ...`) em `magent-tools-catalog` e habilita permissão em `magent-enable-tools`. Hang do `--batch` era este erro fatal disfarçado | `just compile` zero-warning + repro `magent-cli run` sem `Wrong type argument` |
| Hang real do `magent-cli run` batch: fallback de aprovação invocava `read-char-choice` (prompt interativo síncrono) sem TTY, congelando a Lisp Thread segurando o polling | Provider lambda de `allow` injetado no `+carlos/magent-run-execute` (em `lisp/custom-magent-run.el`) na chamada `magent-runtime-submit` (transpõe o `read-char-choice` em execuções batch) | `tests/magent-run-test.el` (9 ERTs) + probe batch |
| `wrong-type-argument gptel-backend` em 2 testes `magent-*` — commit `f893090` (coder-lite) chamava `gptel-backend-name` incondicional em `+carlos/magent-subagent-apply-profile` com backend plist `(:name ...)`/string | Helper função-total `+carlos/--magent-backend-name` (`lisp/custom-magent-subagent.el:32`, guard `gptel-backend-p`) no lugar da expansão inline antiga de `gptel-backend-name` (verificado 2026-08-30 no `a0bea74`) | `myemacs-magent-subagent-override-consumed` + `myemacs-magent-subagent-apply-profile-unknown-agent` (2/2 passando) |

### Encontrados pela suíte (2026-08-30)

| Bug | Fix | Teste |
|-----|-----|-------|
| `magent-cli run` batch → timeout com `turns:0` (mesmo com MLX Local saudável e streaming gptel→MLX OK): `magent` é deferido (só comandos interativos fazem `(require 'magent)`) e `--batch --init-directory` NÃO carrega `early-init.el` neste Emacs 30.2 (`load-prefer-newer-source` nil) — os guards `fboundp` em `+carlos/magent-run-execute` pulavam silenciosamente `magent-runtime-api`/submit | `+carlos/magent-run-ensure-runtime` (`lisp/custom-magent-run.el`): `(require 'magent)` explícito + `(magent-runtime-ensure-initialized)` antes de resolver modelo/submeter; erro claro se o pacote faltar (não mais timeout silencioso). Obs.: `.elc` stale prevalece em batch — `just clean`/`just rebuild` antes de re-testar mudanças em `lisp/` | `myemacs-run-ensure-runtime-batch` + `myemacs-run-ensure-runtime-idempotent` (tests/magent-run-test.el) + smoke `magent-cli run` → `completed`/`turns:1`/`24s` |

### Pendências de regressão (não resolvidas — rastrear)

- **2026-08-27 (prod, pós factory-reset):** `envrc--direnv-export: Invalid function: envrc--with-required-current-en` ao entrar em diretórios com `direnv` (~/Projects/42rio/). Provável problema de `direnv.el`/`envrc` no ambiente oficial.
- **2026-08-28 (prod):** GUI fecha imediatamente no modo daemon (`emacsclient -c`) — limitação PGTK/GTK3 Wayland + hook `+carlos/dashboard-open-on-server-frame` sem `with-demoted-errors`. Plano de correção registrado no TODO.org.
- **2026-08-28 (prod):** arquivo `.py` abre em `Fundamental` (python-mode/treesit não ativando) — suspeita de gramáticas/autoloads pós factory-reset.

---

## Testing (ERT Suite)

A suíte de regressão usa **ERT** (nativo do Emacs, sem dependências) em modo
batch. Roda contra o ambiente autoritativo `~/.config/emacs` (builds
elpaca completos); o repo pode ter builds parciais (ex.: falta
`gptel-autoloads.el`), então os testes de IA só rodam no vanilla.

```bash
# Suíte completa (structural + offline AI), exit != 0 em falha
just test-all          # = lint (compile + checkdoc) + test (suíte ERT)

# Suíte ERT completa em batch (canônico; `test-batch` é alias)
just test

# Apenas testes de IA (offline; rede fica skipped)
just test-ai

# Testes de REDE ao vivo (requer EMACS_TEST_NETWORK=1 — opt-in)
EMACS_TEST_NETWORK=1 just test

# Roda contra outro diretório (ex.: repo)
just test EMACS_TEST_DIR="$(pwd)"
```

### Como adicionar um teste

1. Crie `tests/<area>-test.el` com `(require 'ert)` e `ert-deftest`.
2. Nomeie `myemacs-<area>-<desc>` — o prefixo `myemacs-ai` é usado como
   selector de `just test-ai`.
3. Testes de rede: adicione `:tags '(ai network)` e `(skip-unless (getenv
   "EMACS_TEST_NETWORK"))` (sem a envvar aparecem como skipped, não falham).
4. Testes que dependem de módulo nativo (vterm) devem fazer `skip-unless`
   quando o módulo não carrega, para a suíte passar em qualquer ambiente.
5. Regra: cada bug corrigido ganha um teste que reproduziria o bug.

### Regras dos testes

- Testes **não** fazem rede por padrão (CI-friendly); rede é opt-in.
- `key-binding`/`lookup-key` resolvem maps de minor modes e use-package
  `:bind` de pacotes deferidos — use-os para pegar conflitos reais.
- Em `--batch`, `--eval` avalia **apenas a primeira forma**; use `-l` com
  arquivo ou múltiplos `--eval` para scripts de verificação.

### Portões de Qualidade e Prevenção de Regressões (Rigorosos)

Todo agente que realizar alterações na configuração deve obrigatoriamente garantir que a suíte passe de forma limpa, respeitando os seguintes portões de qualidade:
- **Zero Warnings de Configuração**: O teste `myemacs-boot-no-custom-warnings` proíbe warnings relacionados ao nosso código (`custom-*` ou `+carlos/*`) no boot.
- **Zero Lisp Errors Silenciosos**: O teste `myemacs-boot-no-lisp-errors` varre `*Messages*` por falhas ocultas (`void-variable`, `void-function`) em hooks de inicialização.
- **Zero Colisões de Keybindings**: O teste `myemacs-kbd-no-collisions` garante que os atalhos globais críticos (como prefixos `C-c` de IA, terminal, denote, e Git) permaneçam mapeados para os comandos corretos mesmo dentro de major-modes principais (`org-mode`, `dired-mode`, `c-mode`, `emacs-lisp-mode`). Qualquer colisão introduzida falhará o teste.

---

## Package Reference Docs (RAG Cache)

All package APIs are documented in `docs/`. Reference these files before making changes:

| Package | Doc File | Key Topics |
|---------|----------|------------|
| Dirvish | `docs/dirvish-reference.org` | Attributes, extensions, quick-access, peek, vc, subtree |
| GPTel | `docs/gptel-reference.org` | Backends, gptel-request, gptel-agent, gptel-org, tools |
| Magent | `docs/magent-reference.org` | Native agent, 15 tools, agent-shell, permissions, skills, **streaming pipeline (content vs reasoning), formato DSML, modos de falha (tool call no reasoning, SIGPIPE 141), proposta de FSM de orquestração** |
| Completion | `docs/completion-stack.org` | Vertico, consult, corfu, marginalia, orderless, embark, tempel |
| Magit | `docs/magit-reference.org` | Status, staging, commit, push/pull, log |
| Denote | `docs/denote-reference.org` | Notes, silos, links, backlinks, keywords |
| Org Ecosystem | `docs/org-ecosystem.org` | org-modern, ob-mermaid, jupyter, pdf-tools, org-noter |
| UI Stack | `docs/ui-stack.org` | ef-themes, mood-line, olivetti, nerd-icons, which-key |
| Terminal | `docs/term-stack.org` | vterm, eshell, eshell-git-prompt, display-buffer |
| Jinx/Spell | `docs/spell-stack.org` | jinx, libenchant, dicionários pt_BR/en_US, correção gramatical IA |
| Doom Inspiration | `docs/doom-inspiration.org` | Doom Emacs configurations for Dirvish, Dired, Org aesthetics, fonts, and slides |
| Testing Suite | `docs/testing-suite.org` | Testes ERT, detecção de colisões de teclas, portões de qualidade, warnings e erros de Lisp |
| Dev Workflow | `docs/dev-workflow.org` | Ciclo IA → REPL → ERT, gerador de testes ERT (`C-c D e`), scratch blocks `(when nil ...)` (`C-c D b`) |
| AI Providers | `docs/ai-providers-reference.org` | Detalhamento de quotas, modelos e segurança do Google AI Studio e OpenCode Zen |
| Awesome Cursorrules | `docs/awesome-cursorrules-catalog.org` | Catálogo de 257 regras do awesome-cursorrules (extraído do roadmap.org, Plano 0.14) |

**ALWAYS read the relevant doc file before modifying a package's configuration.**

---

## Workflow Rules

### Before Making Changes

1. Read the relevant `docs/*.org` file for the package
2. Check the "Known Bugs & Fixes" table above
3. Verify the package API matches the documentation (not assumptions)

### After Making Changes

1. Run `just test-all` (compile + checkdoc + ERT suite) to verify config loads and no regressions
2. Sincronizar obrigatoriamente as alterações com a pasta `~/.config/emacs` via `just sync` e validar no ambiente oficial de testes do usuário com `just compile-prod` (gate zero-warning) + `just check-prod` (boot batch, equivale a `emacs --init-directory ~/.config/emacs`)
3. Update `TODO.org` with the change
4. Update `roadmap.org` with the action taken

### Commit Messages

Follow conventional commits:

```
fix(dirvish): consolidate with-eval-after-load blocks
feat(dashboard): add consult-fzf fallback
chore(docs): add gptel reference documentation
refactor(ai): remove advice-add from gptel-agent-run
```

---

## Multi-Agent Assisted Workflow (Política de Multiagentes)

Este projeto adota uma arquitetura de trabalho assistido entre agentes com diferentes perfis de custo e performance (Pro/Opus, Medium/Flash, Lite) para maximizar a precisão e otimizar recursos:

### 1. Papéis dos Agentes

* **Agente Planejador / Arquiteto (Alta Performance - Modelo Pro/Opus)**
  * **Responsabilidade:** Realizar diagnósticos de causa-raiz, leitura e análise de referências RAG complexas, e tomada de decisões estruturais.
  * **Planejamento Estrutural e RAG (A Regra de Ouro):** O planejamento NUNCA deve ser escrito como Markdown livre ou listas (`- [ ]`). O artefato único de planejamento é o arquivo [TODO.org](file:///Users/carlosfilho/Projects/Github/MyEmacs/TODO.org). O Planejador deve manipular a Árvore Sintática (AST) do Org-mode, utilizando cabeçalhos (`*`, `**`), metadados `TODO`, `DONE` e gavetas de propriedades (`:PROPERTIES:`).
  * **Entregável:** Adicionar ou atualizar nós no `TODO.org` com o plano de implementação detalhado (indicando quais arquivos/linhas tocar), mantendo o arquivo perfeitamente legível para o mecanismo de *chunking* do RAG. *Não deve aplicar as alterações de código diretamente.*

* **Agente Executor (Rápido/Cheaper - Modelo Flash/Lite)**
  * **Responsabilidade:** Consumir o plano detalhado no nó específico do `TODO.org` e aplicar as alterações nos arquivos `.el` de destino.
  * **Diretriz:** Seguir estritamente o código e as regras de elisp recomendadas no plano de ação, tratando erros sintáticos simples locais. O agente deve preferencialmente consultar apenas o subtree pertinente do plano.

* **Agente Auditor / Validador (Modelo Mediano/Audit - Modelo Medium/Flash)**
  * **Responsabilidade:** Auditar e certificar o trabalho do Executor.
  * **Ações Obrigatórias:**
    1. Rodar os testes estritos de carga, compilação e regressão (`just check-all`, que executa `check` + `test-all` = compile + checkdoc + suíte ERT).
    2. Garantir **zero warnings** na compilação (`byte-compile-error-on-warn t`).
    3. Atualizar o histórico de mudanças no [TODO.org](file:///Users/carlosfilho/Projects/Github/MyEmacs/TODO.org) (mudando estado de `TODO` para `DONE`) e [roadmap.org](file:///Users/carlosfilho/Projects/Github/MyEmacs/roadmap.org).

### 2. Portões de Qualidade (Quality Gates)

1. **Portão de Compilação:** Nenhuma alteração pode ser integrada se gerar warnings no compilador de Emacs Lisp. O comando `just compile` trata avisos como erros críticos.
2. **Portão de Documentação:** Todo novo recurso ou mudança estrutural deve estar documentado em `docs/` ou no changelog antes da conclusão da tarefa.
3. **Portão de Regras:** Verificar se o Executor não introduziu anti-padrões como `setq` em opções de customização globais, requires sem guardas (`nil t`), ou funções duplicadas.

---

## Module Loading Order

The loading order in `init.el` is intentional. Do NOT change it without understanding dependencies:

```
custom-core       ← Foundation (fonts, GPG, editor defaults)
custom-ui         ← Visual (themes, mode-line, which-key)
custom-writing    ← Escrita (olivetti, org-modern)
custom-completion ← Minibuffer (vertico, consult, corfu)
custom-files      ← File management (dirvish, ibuffer, TRAMP)
custom-term       ← Terminal (vterm, eshell)
custom-keybindings ← All keybindings (depends on above being loaded)
custom-lang       ← Languages (eglot, treesit)
custom-markdown   ← Markdown (markdown-mode)
custom-org        ← Org mode (babel, jupyter, pdf)
custom-42         ← 42 School (depends on flycheck, header42, norminette)
custom-ai         ← AI (gptel, depends on core being loaded)
custom-dev        ← Dev env + ERT/REPL tools (depends on custom-ai)
custom-jinx       ← Spell (jinx + grammar IA, depends on custom-ai)
custom-magent     ← Magent (native coding agent, depends on custom-ai; carrega os 6 submódulos custom-magent-*)
custom-magent-run ← `magent-cli run` — launcher batch UI-neutral (depends on custom-magent)
custom-knowledge  ← Denote (knowledge management)
custom-git        ← Git (magit, justl)
custom-dashboard  ← Dashboard (depends on many modules)
```

---

## Environment

- **Emacs:** 29+ (Emacs Bedrock template)
- **OS:** macOS (NixOS via Home Manager)
- **Package manager:** Elpaca (git-based, async, native-comp)
- **Nix role:** System deps only (rg, fd, mmdc, fonts, Python, LSP servers)
- **Portability:** Works anywhere with Emacs 29+ and git (no Nix required for elisp)
- **External tools:** ripgrep, fd, clangd, gopls, basedpyright, ruff, norminette, mmdc, pkg-config, enchant (jinx)

---

## Test Commands

```bash
# Check config loads
just check

# Byte-compile
just compile

# Launch Emacs
just run          # dev (repo)
just test-run     # prod (~/.config/emacs)

# Boot batch no ambiente oficial (pós-sync)
just check-prod
```

### 7. Otimizações de FinOps e Performance

**Coder Lite (Diet Tooling):** Modelos locais (MLX/Ollama) recebem um payload reduzido de ferramentas (apenas `read_file`, `replace_file_content`, `run_command`, `context_search` e `*_smart_edit`) para evitar hangs no *time-to-first-token* causados por prompts gigantes.
