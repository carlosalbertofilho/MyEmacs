# TODO — Planejamento Ativo e Backlog (MyEmacs)

## 0.26. Plano de Ação — Limpeza Definitiva do `~/.config/emacs` via Clone do Repo + Verificação do Enchant (Concluído)

> **Autor:** Agente Executor/Auditor. Aplicado e validado.

1. [x] **Contexto:** o `~/.config/emacs` (ambiente oficial de testes) acumulava lixo
   residual da migração Doom→Vanilla (`.doom/`, `.local/`, `modules/`, `static/`,
   `elpa/`, `profiles/`, `.dir-locals.el`, `README.md`, `shell.nix`). O diretório
   deixou de ser um espelho fiel do repo.
2. [x] **Limpeza via clone:** backup do estado runtime preservado em
   `/tmp/opencode/emacs-preserve`, `rm -rf` do diretório, e clone limpo de
   `git@github.com:carlosalbertofilho/MyEmacs.git` (commit `68fee0c`) em
   `~/.config/emacs` — sem cruft Doom, `git status` limpo.
3. [x] **Restauração do estado runtime (não trackeado):** `elpaca/`, `tree-sitter/`,
   `eln-cache/`, `agent/`, `.agent-shell/`, `magent/sessions`, `recentf`, `places`,
   `bookmarks`, `auto-save-list`, `transient`. `.gitignore` do repo já cobre os
   caches (elpaca, tree-sitter, eln-cache, elpa, recentf, places, auto-save-list).
4. [x] **Verificação:** `emacs --init-directory ~/.config/emacs --batch -l init.el`
   → `CONFIG OK`; boot sem warnings.
5. [x] **Nix (enchant/jinx):** confirmado que `emacs.nix` já estava aplicado
   (`nix flake check` OK; rebuild gerou o mesmo store path `d4ngd9avlnbv`). As
   sessionVariables `PKG_CONFIG_PATH`/`LD_LIBRARY_PATH` do enchant-2.6.9 estão no
   `hm-session-vars.sh` ativo (`/etc/profiles/per-user/carlosfilho/etc/profile.d/`,
   store `vcjd51aapq...-home-manager-path`). `pkg-config --cflags --libs enchant-2`
   resolve; `jinx` carrega (`JINX LOADED: jinx.el`).
6. [x] **Docs:** `TODO.md` §0.26 e `roadmap.org` (2026-08-08).

## 0.25. Plano de Ação — REPL Nativo (IELM + eval inline) + Dinâmica de Testes ERT com IA (Plano)

> **Autor:** Agente Planejador (modelo Pro/Opus). Plano EXECUTÁVEL para o Agente Executor. **Nada aplicado ainda.**

### Contexto

Fluxo de desenvolvimento assistido por IA (gptel) integrado ao REPL nativo do Emacs
para Elisp: IA gera → REPL valida instantaneamente (sem reiniciar o processo) → ERT
fixa. O Emacs é o próprio ambiente de execução, então não há processo externo — a
"memória do código" e o REPL são o mesmo processo (IELM + `C-x C-e` avaliam no Emacs
vivo).

Fatos verificados no ambiente (Emacs 30.2, `--batch -Q`):

| Binding | Estado | Observação |
|---------|--------|------------|
| `C-x C-e` | **já global** → `eval-last-sexp` | Nada a fazer (default nativo) |
| `C-c C-e` (emacs-lisp-mode) | **já** → `elisp-eval-region-or-buffer` | Built-in Emacs 30 |
| `C-c C-k` / `C-c C-c` / `C-c C-t` (emacs-lisp-mode) | livres (nil) | Disponíveis para binds locais |
| `C-c D` (global) | livre (nil) | Prefixo escolhido p/ Dev |
| `ert-run-test-at-point` | **NÃO existe** (nil) | Implementar `+carlos/ert-run-test-at-point` |
| `ert-run-tests-interactively` | existe (t) | API built-in para o runner |

Colisões do plano original da conversa que **devem ser evitadas** (já ocupadas e
protegidas por testes): `C-c r` (RAG ingest), `C-c t` (vterm), `C-c c t` (gerar
teste IA) → usar prefixo dedicado `C-c D`.

### Fase 1 — `lisp/custom-dev.el` (novo módulo)

Criar módulo com helpers de REPL/teste + keybindings, seguindo o template do AGENTS.md
(header `;;; custom-dev.el --- ... -*- lexical-binding: t; -*-`, Commentary, `:Code:`,
`(provide 'custom-dev)`). Sem dependências externas (só built-ins: `ert`, `ielm`).

```elisp
;;; custom-dev.el --- Interactive dev loop: IELM + inline eval + ERT runner -*- lexical-binding: t; -*-

;;; Commentary:
;; Ciclo IA → REPL → ERT para Elisp. Avalia expressões inline (C-x C-e, já
;; global), inspeciona estado no IELM, roda testes ERT do buffer com feedback
;; visual (verde/vermelho) e depura backtrace com IA via gptel.
;; Prefixo global: C-c D (Dev).

;;; Code:

(defun +carlos/ert-run-buffer ()
  "Avalia o buffer atual e roda apenas os testes ERT definidos nele.
Usa um selector ERT baseado no nome do arquivo (tests/<area>-test.el ⇒
selector `myemacs-<area>-'), exibindo o resultado no buffer de resultados
do ERT com cores (passou/falhou)."
  (interactive)
  (let ((file (buffer-file-name)))
    (unless (and file (string-match-p "-test\\.el\\'" file))
      (user-error "Buffer não é um arquivo de teste (*-test.el)"))
    (eval-buffer)
    (let* ((area (replace-regexp-in-string "-test\\.el\\'" "" (file-name-base file)))
           (selector (format "myemacs-%s-" area)))
      (ert selector))))

(defun +carlos/ert-run-test-at-point ()
  "Roda o teste ERT sob o ponto (dentro de um `ert-deftest')."
  (interactive)
  (let* ((beg (save-excursion
                (or (search-backward-regexp "^(ert-deftest " nil t) (point-min))))
         (test-name (save-excursion
                      (when (search-backward-regexp "^(ert-deftest +\\\([-[:alnum:]]+\\\)" nil t)
                        (string-to-symbol (match-string-no-properties 1))))))
    (if test-name
        (ert test-name)
      (user-error "Não há `ert-deftest' antes do ponto"))))

(defun +carlos/ielm-open ()
  "Abre o IELM (REPL Elisp)."
  (interactive)
  (ielm))

(defun +carlos/toggle-debug-on-error ()
  "Alterna `debug-on-error' com feedback no minibuffer."
  (interactive)
  (setq debug-on-error (not debug-on-error))
  (message "debug-on-error: %s" (if debug-on-error "ON (backtrace ao errar)" "OFF")))

;; ── Depuração com IA (gptel) ────────────────────────────────────────
(declare-function +carlos/gptel-request "custom-ai")

(defun +carlos/debug-region-with-ai ()
  "Envia o backtrace/região selecionada + código ao gptel para diagnóstico.
O prompt pede explicação do estado de memória/escopo que causou o erro e a
correção, seguindo o fluxo 'pós-morte' do REPL."
  (interactive)
  (let* ((beg (if (region-active-p) (region-beginning) (point-min)))
         (end (if (region-active-p) (region-end) (point-max)))
         (text (buffer-substring-no-properties beg end)))
    (when (require 'custom-ai nil t)
      (+carlos/gptel-request
       (format "O REPL do Emacs estourou este erro/backtrace ao rodar meu teste Elisp. Explique o estado de memória/escopo que causou e dê a correção:\n\n%s" text)
       +carlos/gptel-quick-local-backend
       +carlos/gptel-quick-local-model
       :buffer "*gptel-debug*"
       :callback (lambda (response _info)
                   (when response
                     (with-current-buffer (get-buffer-create "*debug-ai*")
                       (goto-char (point-max))
                       (insert response "\n"))))))))

;; ── Keybindings ─────────────────────────────────────────────────────
(global-set-key (kbd "C-c D r") #'+carlos/ielm-open)            ; REPL dedicado
(global-set-key (kbd "C-c D t") #'+carlos/ert-run-buffer)       ; roda testes do buffer
(global-set-key (kbd "C-c D T") #'+carlos/ert-run-test-at-point); teste sob o ponto
(global-set-key (kbd "C-c D d") #'+carlos/toggle-debug-on-error); debug-on-error
(global-set-key (kbd "C-c D a") #'+carlos/debug-region-with-ai) ; depura com IA
(global-set-key (kbd "C-c C-k") #'eval-buffer)                  ; avalia arquivo inteiro

;; Binds locais do emacs-lisp-mode (sem poluir o global)
(with-eval-after-load 'emacs-lisp-mode
  (define-key emacs-lisp-mode-map (kbd "C-c C-c") #'+carlos/ert-run-buffer)
  (define-key emacs-lisp-mode-map (kbd "C-c C-t") #'+carlos/ert-run-test-at-point))

(provide 'custom-dev)
;;; custom-dev.el ends here
```

**Notas de implementação:**
- `+carlos/ert-run-buffer` avalia o arquivo de teste (`eval-buffer`) e roda só os
  testes daquela área via selector `myemacs-<area>-`; o buffer de resultados do ERT
  mostra passou/falhou com cores.
- `+carlos/gptel-request` já aceita `:buffer` (Fase jinx concluída); o helper usa
  backend local rápido (`+carlos/gptel-quick-local-backend`), sem custo de nuvem.
- `declare-function` para `+carlos/gptel-request`; `+carlos/gptel-quick-local-backend`
  é `defvar` global (declarado em custom-ai.el).

### Fase 2 — Registro no `init.el`

Adicionar `(require 'custom-dev)` **após** `custom-ai` (usa `+carlos/gptel-request` e
o quick backend de custom-ai) e **antes** de `custom-jinx`/`custom-magent`, ou no fim
junto de `custom-git`/`custom-dashboard` — requer apenas `custom-ai`:

```elisp
(require 'custom-ai)
(require 'custom-dev)   ; ← novo
(require 'custom-jinx)
```

### Fase 3 — Testes ERT (`tests/dev-test.el`, prefixo `myemacs-dev-*`)

| Teste | Verifica |
|-------|----------|
| `myemacs-dev-ielm-bind` | `C-c D r` → `+carlos/ielm-open`; `commandp` |
| `myemacs-dev-ert-runner-bind` | `C-c D t` → `+carlos/ert-run-buffer`; `commandp` |
| `myemacs-dev-ert-test-at-point-bind` | `C-c D T` → `+carlos/ert-run-test-at-point` |
| `myemacs-dev-toggle-debug-bind` | `C-c D d` → `+carlos/toggle-debug-on-error` |
| `myemacs-dev-debug-ai-bind` | `C-c D a` → `+carlos/debug-region-with-ai` |
| `myemacs-dev-eval-buffer-bind` | `C-c C-k` → `eval-buffer` |
| `myemacs-dev-ert-runner-selects-buffer` | selector `myemacs-<area>-` a partir do nome do arquivo `*-test.el` (mock de `buffer-file-name`) |
| `myemacs-dev-ert-test-at-point-finds-test` | `ert-deftest` sob o ponto é encontrado (buffer temp) |
| `myemacs-dev-no-collisions` | em `emacs-lisp-mode`, `C-c D*` continua apontando para os comandos `+carlos/dev-*`; `C-c r`/`C-c t`/`C-c c t` **intactos** (regressão das fases anteriores) |

**Importante:** adicionar `C-c D r/t/T/d/a` e `C-c C-k` à lista `critical-bindings` do
teste existente `myemacs-kbd-no-collisions` (`tests/keybindings-test.el`) para o portão
de colisão cobrir o novo prefixo também.

### Fase 4 — Docs

1. **`docs/testing-suite.org`:** nova seção "Fluxo Interativo (REPL/ERT com IA)"
   documentando o ciclo IA → REPL → ERT, os atalhos `C-c D*`, `C-x C-e` (inline),
   `C-c C-e` (região/buffer), `M-x ielm`, e o fluxo de depuração `C-c D d` +
   `C-c D a` (backtrace → gptel).
2. **`AGENTS.md`:** atualizar a árvore (`custom-dev.el ← REPL/ERT + depuração IA`),
   a ordem de carga, e a tabela de docs (novo `docs/dev-repl.org` OU seção no
   testing-suite — decisão do executor: manter tudo em testing-suite.org é mais leve).

### Fase 5 — Validação (portões)

1. `just compile` (zero warnings — `byte-compile-error-on-warn t`; custom-dev.el deve
   compilar limpo; erro pré-existente `gptel--token-usage`/`agent-smith` no repo é
   conhecido e fora do escopo).
2. `just checkdoc` OK.
3. `just test-batch EMACS_TEST_DIR="$(pwd)"` no repo e `just test-all` no
   `~/.config/emacs` autoritativo (com env vars do jinx exportadas se necessário).
4. `just sync` + boot interativo `emacs --init-directory ~/.config/emacs`: testar
   manualmente `C-c D r`, `C-c D t` num `*-test.el`, `C-x C-e` numa expressão, e
   `C-c D a` com um backtrace falso.

### Critérios de aceite

- `C-c D r` abre IELM; `C-c D t` num `tests/*-test.el` roda só aqueles testes com
  feedback colorido; `C-c C-k` avalia o buffer; `C-c D d` alterna `debug-on-error`.
- `C-c D a` envia a região ao gptel local e exibe o diagnóstico em `*debug-ai*`.
- Nenhuma colisão nova: `myemacs-kbd-no-collisions` + novos `myemacs-dev-*` verdes.
- Zero warnings de boot (`myemacs-boot-no-custom-warnings`).

### Riscos e mitigação

- `+carlos/ert-run-buffer` com arquivos que não são `*-test.el` → `user-error`
  (guard de filename).
- `eval-buffer` pode avaliar `provide`/`require` múltiplas vezes → benigno no
  desenvolvimento interativo; suíte batch não roda `eval-buffer` (só verifica binds).
- Testes que exigem `ert-run-test-at-point` (built-in inexistente no 30.2) → nossa
  implementação `+carlos/ert-run-test-at-point` cobre; teste usa buffer temp com um
  `ert-deftest` real para validar o regex.

## 0.24. Plano de Ação — Jinx (spellcheck pt_BR/en_US) + Correção Gramatical via IA (Concluído)

> **Autor:** Agente Executor/Auditor. Aplicado e validado com `just test-all` (139 testes, 0 falhas) + E2E real contra Ollama/mistral.

1. [x] **Contexto:** substituir o aspell por um corretor JIT com dicionários pt_BR + en_US simultâneos; correção gramatical profunda via IA local (gptel + Ollama/mistral) com substituição in-place.
2. [x] **Nix (`~/Projetos/Nixos/MyMachine/home/carlosfilho/emacs.nix`):**
   - `home.file.".config/enchant/enchant.ordering"` = `pt_BR:hunspell` / `en_US:hunspell` (força o provider hunspell; antes era aspell).
   - Rebuild OK; `enchant-lsmod-2 -list-dicts` mostra `en_US (hunspell)` e `pt_BR (hunspell)`; runtime `enchant-2 -a -d <lang>` validado.
3. [x] **`lisp/custom-jinx.el` (novo):**
   - `use-package jinx` (`:ensure t :demand t`), `jinx-languages "pt_BR en_US"`, hooks `text-mode-hook`/`prog-mode-hook`, binds `M-$`→`jinx-correct` e `C-M-$`→`jinx-languages` no `jinx-mode-map`.
   - `+carlos/grammar-correct-region` (interactive "r"; `C-c c g`): prompt JSON `{"corrected": ...}`, chama `+carlos/gptel-request` com `:buffer "*gptel-grammar*"` e `:schema '(:type object :properties (:corrected (:type string)))`, substitui a região in-place via markers.
   - Helpers `+carlos/--grammar-extract-corrected` (json-parse-string alist com fallback) e `+carlos/--grammar-apply-corrected`.
4. [x] **`lisp/custom-ai.el`:**
   - Modelo `mistral` adicionado ao backend "Ollama Local"; defvars `+carlos/gptel-grammar-backend`/"model".
   - `+carlos/gptel-request` agora aceita `:buffer` (remove a key dos args com `cl-loop`).
   - **Bug fix:** repassava `:response_format` (keyword inexistente no `&key` do gptel 0.9.9.5) — quebrava TODA chamada Ollama/MLX. Removido; JSON agora só via `:schema` quando o caller precisa.
   - Roteador dinâmico ignora buffers `*gptel-grammar*` (modelo fixo em mistral, REGRA 3 não sobrescreve).
5. [x] **`init.el`:** `(require 'custom-jinx)` após `custom-ai`.
6. [x] **Testes (`tests/spell-test.el`, 9 testes `myemacs-spell-*`):** commands, languages, hooks, mode-map, module/C-c c g, grammar vars, json extraction, router skip, e `myemacs-spell-grammar-schema-passthrough` (regressão do bug `:response_format` via fake `cl-defun`).
7. [x] **Docs:** `docs/spell-stack.org` (novo) e AGENTS.md (árvore, ordem de carga, tabela docs, external tools).
8. [x] **Validação:** `just test-all` 139 testes 0 falhas; E2E `/tmp/opencode/grammar-e2e.el` → "Eles vao para a escola amanha." → "Eles vão para a escola amanhã."; `just sync` aplicado.

## 0.22. Plano de Ação — Fix Roteador Dinâmico: Magent não é mais sequestrado + Análise do Agent_Smith com caminho real

> **Autor:** Agente Executor/Auditor. Aplicado e validado com `just test-all` (125 testes, 0 falhas).

1. [x] **Diagnóstico:** o `+carlos/gptel-dynamic-router-advice` sobrescrevia o backend/modelo escolhidos pelo Magent. Magent registra um backend temporário **sem nome** (`(car gptel--known-backends)` → prefixo ` *magent-llm-gptel-request*`) e envia o contexto `:magent-llm-gptel`; o roteador virava a requisição para Gemini Cloud → resposta vazia (`stop unknown reason`) com o modelo local qwen2.5-coder:3b (bug persistente do plano 0.21).
2. [x] **Correção (`lisp/custom-ai.el`):**
   - Criado o predicado `+carlos/magent-managed-request-p` (buffer prefixo ` *magent-llm-gptel-request*` OU contexto `:magent-llm-gptel`).
   - No início de `+carlos/gptel-dynamic-router-advice`, requisições gerenciadas pelo Magent agora **retornam imediatamente** (preservando `gptel-backend`/`gptel-model` locais do Magent).
   - `+carlos/magent-agent-smith-dir` agora é `defcustom` com o caminho real `~/Projetos/42rio/CommonCore/Rank05/Agent_Smith`; `+carlos/magent-analyze-agent-smith` valida o diretório e informa o caminho ao agente no prompt.
3. [x] **Testes ERT:**
   - `myemacs-ai-dynamic-router-skips-magent` (`tests/ai-test.el`): requisição em buffer ` *magent-llm-gptel-request*` e com contexto `:magent-llm-gptel` **mantêm** `Ollama Local`/`qwen2.5-coder:3b`; roteamento `/plan` normal continua intacto.
   - `myemacs-magent-analyze-agent-smith-target` (`tests/magent-test.el`): valida o `defcustom` com `~/Projetos/42rio/CommonCore/Rank05/Agent_Smith`, que o diretório existe e que o prompt enviado ao `magent-start` (mockado) contém o caminho.
4. [x] **Portões de qualidade:** `just test-all` (compile + checkdoc + 125 testes ERT) 100% verde; `just sync` aplicado.

## 0.23. Plano de Ação — Tempel: Snippets Elisp Nativos (tempel + tempel-collection + eglot-tempel)

> **Autor:** Agente Arquiteto (modelo Pro/Opus). Plano EXECUTÁVEL para o Agente Executor. **Nada aplicado ainda.**

### Contexto

O MyEmacs migrou do Doom (que embarcava YASnippet) para Vanilla sem um sistema de
snippets. O Tempel (minad, GNU ELPA) é o substituto leve: usa a sintaxe Tempo,
integra-se com o **Corfu** (já usado em `custom-completion.el`) via o mecanismo
padrão `completion-at-point-functions` (Capf). Três fontes de templates:

1. **`tempel-collection`** (Crandel, MELPA) — coleção estática comunitária,
   arquivos `.eld` organizados por major mode (`python-mode.eld`, `org-mode.eld`,
   `sh-mode.eld`) na pasta `templates/`.
2. **`minad/tempel`** — repo oficial; templates de referência no README/manual
   (prog-mode, text-mode, latex-mode, org-mode).
3. **`fejfighter/eglot-tempel`** — ponte dinâmica: captura os snippets que o
   servidor LSP fornece via Eglot e os converte em runtime para o formato nativo
   do Tempel (elimina arquivos estáticos para linguagens modernas).

### Fase 1 — Instalação e configuração do `tempel` (`lisp/custom-completion.el`)

Adicionar após o bloco `nerd-icons-corfu` (fim do arquivo), seguindo o padrão do
arquivo (`use-package` + Elpaca `:ensure t`; `tempel` não precisa de boot
síncrono, pode ser deferido):

```elisp
;; ── tempel ─────────────────────────────────────────────────────────
(use-package tempel
  :ensure t
  :bind (("M-+" . tempel-complete)     ; Corfu mostra o popup com os templates
         ("M-*" . tempel-insert))
  :config
  ;; Inserir o Capf ANTES dos Capfs de prog-mode (tempel-expand só dispara em
  ;; match exato, então não rouba a completion do Eglot/LSP).
  (defun +carlos/tempel-setup-capf ()
    (setq-local completion-at-point-functions
                (cons #'tempel-expand completion-at-point-functions)))
  (add-hook 'prog-mode-hook #'+carlos/tempel-setup-capf)
  (add-hook 'text-mode-hook #'+carlos/tempel-setup-capf)
  (add-hook 'conf-mode-hook #'+carlos/tempel-setup-capf))
```

- Navegação entre campos do template: `M-{` / `M-}` (ou `C-up`/`C-down`), que o
  Tempel remapeia temporariamente para `tempel-next`/`tempel-previous` (mapa
  `tempel-map`).
- Templates próprios: `tempel-path` aponta por padrão para `~/.config/emacs/templates`
  (arquivo lisp-data agrupado por major mode). **Opcional:** criar `templates/`
  no repo com snippets 42/org e sincronizá-lo via `just sync`.

### Fase 2 — `tempel-collection` (templates estáticos)

```elisp
;; ── tempel-collection ───────────────────────────────────────────────
(use-package tempel-collection
  :ensure t
  :after tempel
  :config
  ;; ⚠️ Verificar a API real do pacote instalado (regra do AGENTS.md: não
  ;; assumir). Ativação típica: `(tempel-collection--load)` ou hook em
  ;; `tempel--update-hook`; o README oficial sugere apenas o use-package.
  )
```

### Fase 3 — `eglot-tempel` (snippets dinâmicos do LSP)

```elisp
;; ── eglot-tempel ────────────────────────────────────────────────────
(use-package eglot-tempel
  :ensure t
  :after eglot
  :config
  ;; ⚠️ Verificar a API real (README do fejfighter/eglot-tempel): adicionar o
  ;; Capf `eglot-tempel-capf` aos `completion-at-point-functions` dos buffers
  ;; gerenciados pelo Eglot (geralmente via `eglot-managed-mode-hook`).
  )
```

### Fase 4 — Testes ERT (`tests/completion-test.el` — arquivo NOVO)

1. Criar `tests/completion-test.el` (naming `myemacs-completion-*`; o loader
   `tests/load-tests.el` já carrega automaticamente via `directory-files`):
   - `myemacs-completion-tempel-commands`: `fboundp` de `tempel-expand`,
     `tempel-complete`, `tempel-insert`.
   - `myemacs-completion-tempel-binds`: `(key-binding (kbd "M-+"))` =
     `#'tempel-complete` e `M-*` = `#'tempel-insert` (usar `key-binding` para
     pegar conflitos reais de minor modes).
   - `myemacs-completion-tempel-capf`: em buffer `emacs-lisp-mode` (deriva de
     prog-mode), `completion-at-point-functions` contém `tempel-expand`.
   - `myemacs-completion-tempel-collection`: `(featurep 'tempel-collection)` ou
     `tempel-templates` populado (guard `skip-unless` se o pacote não carregar
     em builds parciais do repo).
   - `myemacs-completion-eglot-tempel`: `fboundp` do Capf do eglot-tempel
     (`skip-unless` quando eglot não estiver ativo no ambiente).
2. Adicionar `(require 'completion-test)` explícito em `tests/load-tests.el` se
   o teste não for descoberto (padrão dos outros arquivos).

### Fase 5 — Documentação

- Adicionar seção "Snippets: Tempel" em `docs/completion-stack.org` (tabela de
  packages + pitfalls: competição com Capf LSP, `corfu-auto-trigger` opcional).
- Atualizar a tabela de Package Reference Docs no `AGENTS.md` com o novo doc.

### Riscos

| Risco | Mitigação |
|-------|-----------|
| `M-+`/`M-*` colidirem com binds de major modes | Teste `key-binding` no ERT + `which-key` |
| Capf do tempel competir com o Capf do Eglot/LSP | `tempel-expand` ANTES dos demais (só match exato) |
| `tempel-collection` mudar API de ativação | Executor valida a API real do pacote instalado (AGENTS.md) |
| `eglot-tempel` exigir versão específica do eglot | `:after eglot` + guard `(require 'eglot-tempel nil t)` |
| Build parcial do repo sem os pacotes | `skip-unless` nos testes |

### Critérios de aceite

1. `just test-all` 100% verde (compile + checkdoc + ERT, zero warnings).
2. `M-+` expande templates com popup do Corfu em `emacs-lisp-mode` e `org-mode`.
3. Snippets do `tempel-collection` disponíveis por major mode.
4. Em buffers gerenciados pelo Eglot, snippets do servidor aparecem via
   `eglot-tempel` sem arquivos estáticos.
5. `just sync` aplicado e boot em `~/.config/emacs` sem warnings (`myemacs-boot-no-custom-warnings`).

### ✅ EXECUÇÃO CONCLUÍDA (2026-08-08)

| Fase | Resultado |
|------|-----------|
| 1 (tempel) | ✅ `lisp/custom-completion.el`: use-package `:ensure nil :demand t`, binds `M-+`/`M-*` em global-map, Capf `+carlos/tempel-setup-capf` em prog/text/conf-mode-hook. Filas explícitas `(elpaca tempel)` antes do `elpaca-wait`. |
| 2 (tempel-collection) | ✅ `:ensure nil :demand t` (API real: `require` do arquivo gerado `tempel-collection-templates` — sem hook extra necessário). |
| 3 (eglot-tempel) | ✅ `eglot-tempel-mode 1` em `:config`. API real verificada na fonte: minor mode GLOBAL (não Capf por-buffer como o plano supôs) que faz `advice-add :override` em `eglot--snippet-expansion-fn`. |
| 4 (testes) | ✅ `tests/completion-test.el` criado (5 testes `myemacs-completion-*`). O loader `directory-files` descobre automaticamente — sem editar `load-tests.el`. |
| 5 (docs) | ✅ Seção "Tempel (Snippets)" em `docs/completion-stack.org` + tabelas Package Summary/Essential Variables/Notes; linha do AGENTS.md atualizada. |

**Desvios do plano (justificados):**
- Planos usavam `:after tempel`/`:after eglot`, mas `use-package-expand-minimally t` **ignora** `:after` (regra do AGENTS.md). Substituído por fila elpaca explícita + `:demand t` na ordem tempel → tempel-collection → eglot-tempel.
- Plano previa `:ensure t` deferido; adotado `:demand t` para registrar o Capf no boot (padrão do arquivo).

**Validação:**
- `just sync` → `emacs --init-directory ~/.config/emacs` boot OK, tempel/tempel-collection/eglot-tempel instalados via elpaca.
- 5 testes de completion passam; suíte completa: 121 pass, 1 fail **pré-existente** (`myemacs-local-ai-skills-exist` — `magent/skills/` não é sincronizado pelo `just sync`; falha no HEAD sem as mudanças), 8 skipped (rede).

## 0.20. Plano de Ação — Fortalecimento de Contexto e Sanitizador Nativo das 15 Ferramentas do Magent
## 0.21. Plano de Ação — Corrigir erro persistente do Magent ao usar modelo local qwen2.5-coder:3b

### Tópicos do Plano:

1. **Diagnóstico aprofundado**  
   - Inspecionar o buffer `*magent-log*` para identificar se a resposta do modelo contém texto ou chamadas de ferramenta vazias.  
   - Verificar o payload enviado ao backend OpenAI (`gptel-make-openai`) para garantir que o parâmetro `response_format` está definido como `json` quando necessário.

2. **Ajustes de configuração**  
   - Garantir que `gptel-model` está definido como a string `"qwen2.5-coder:3b"` em `custom-ai.el`.  
   - Atualizar `+carlos/gptel-request` para incluir `:response_format "json"` quando o modelo for local e a ferramenta exigir saída estruturada.  
   - Remover/adaptar quaisquer conselhos de roteador dinâmico que possam redirecionar solicitações para backends remotos.

3. **Validação de Ferramentas**  
   - Testar cada uma das 15 ferramentas nativas do Magent individualmente com um prompt simples (`M-x magent-tool-test`) para confirmar que retornam chamadas válidas.  
   - Criar teste ERT em `tests/magent-test.el` que simula uma resposta vazia do modelo e verifica que o Magent gera um erro controlado e não aborta a sessão.

4. **Monitoramento e Feedback**  
   - Implementar função `+carlos/magent-log-context` que grava no buffer `*magent-log*` o request/response completo para depuração futura.  
   - Exibir aviso visual (`message`) ao usuário quando a resposta do modelo não contiver texto nem chamadas de ferramenta.

5. **Rollout**  
   - Aplicar as mudanças, executar `just test-all` e validar que todos os testes passam sem warnings.  
   - Commitar as alterações com mensagem `fix(magent): resolves stop unknown reason error with qwen2.5-coder:3b`.  
   - Sincronizar para `~/.config/emacs` e comunicar que o problema está resolvido.

> **Autor:** Agente Arquiteto (modelo Pro/Opus). Plano EXECUTÁVEL para o Agente Executor.

### Tópicos do Plano:

1. [x] **Fase 1: Injeção de Diretivas Nativas de Ferramentas (`lisp/custom-magent.el`)**
   - [x] Criada a constante `+carlos/magent-system-directives` em `lisp/custom-magent.el` com regras de uso estrito das 15 ferramentas nativas (caminhos absolutos obrigatórios, argumentos não-vazios, preferência por ferramentas nativas em vez de shell `bash`).

2. [x] **Fase 2: Auto-Sanitizador de Caminhos e Validador de Argumentos em Elisp (`lisp/custom-magent.el`)**
   - [x] Criado o conselho `+carlos/magent-resolve-path-advice` que expande automaticamente qualquer caminho relativo contra `default-directory` (ex: navegando em subpastas ou via `/set-workdir`).
   - [x] Criados os conselhos `+carlos/magent-write-file-advice` e `+carlos/magent-edit-file-advice` validando argumentos obrigatórios (`content`, `old_text`) e retornando mensagens de erro instrutivas.

3. [x] **Fase 3: Testes de Regressão ERT em `tests/magent-test.el`**
   - [x] Adicionado o teste ERT `myemacs-magent-tool-sanitizers` em `tests/magent-test.el` validadas as resoluções de caminho.
   - [x] 100% de aprovação na suíte `just test-all` (123 testes verdes).

## 0.19. Plano de Ação — Roteamento Inteligente com Chat Local Default, Saúde do Servidor e Observador de Latência

> **Autor:** Agente Arquiteto (modelo Pro/Opus). Plano EXECUTÁVEL para o Agente Executor.

### Tópicos do Plano:

1. [x] **Fase 1: Verificação e Saúde do Servidor de IA Local (NixOS / macOS)**
   - [x] Criada a função `+carlos/local-ai-server-ping-p` em `lisp/custom-ai.el` para checar a conectividade do servidor local (Ollama em `http://localhost:11434/api/tags` ou MLX em `http://localhost:8081`).
   - [x] Integrado com os serviços configurados via Nix (`services.ollama` no NixOS EliteDesk e `launchd.agents.ollama` no macOS `agnes`).
   - [x] Caso o servidor local não responda, efetuado fallback gracioso para o **Nível 2 (Google AI Studio Gemini 2.5 Flash)** com notificação no minibuffer.

2. [x] **Fase 2: Chat Inicial 100% Local (Default Boot)**
   - [x] Ajustada a função `+carlos/gptel-setup-defaults-by-host` em `lisp/custom-ai.el` para boot local por padrão (Ollama `qwen2.5-coder:3b` no EliteDesk / MLX `Qwen 3.5 9B` no Mac).
   - [x] Consumo zero de tokens de nuvem na inicialização.

3. [x] **Fase 3: Hierarquia de Cotas e Roteamento por Tarefa (`lisp/custom-ai.el`)**
   - [x] Atualizado o Roteador Dinâmico (`+carlos/gptel-dynamic-router-advice`) com a hierarquia estrita de 4 níveis.
   - [x] Tarefa `/plan` / `architect`: Roteada para Zen Claude (Sonnet 3.5 / Opus) ou Gemini Pro.
   - [x] Tarefa `build` / `revisor`: Roteada para Local AI ou OpenCode Zen `big-pickle`.

4. [x] **Fase 4: Observador de Latência Dinâmico (`+carlos/gptel-latency-watchdog`)**
   - [x] Criada a função de monitoramento de latência `+carlos/gptel-latency-watchdog` com limite de 8s. Se o modelo gratuito/zen atrasar a resposta, cancela e migra automaticamente para Zen Claude com aviso visual.

5. [x] **Fase 5: Testes ERT em `tests/ai-test.el`**
   - [x] Adicionados testes verificando a checagem de saúde do servidor local, boot local por padrão, a hierarquia de cotas e o observador de latência (100% verdes).

## 0.18. Plano de Ação — Slash Commands de Diretório e Quota no Chat do Magent

> **Autor:** Agente Arquiteto (modelo Pro/Opus). Plano EXECUTÁVEL para o Agente Executor.

### Tópicos do Plano:

1. [x] **Fase 1: Registro das Ações de Diretório (`/set-workdir`, `/add-dir`, `/list-dirs`)**
   - [x] Registradas as funções e slash commands `+carlos/magent-set-workdir` (`C-c M w`), `+carlos/magent-add-dir` (`C-c M a`), e `+carlos/magent-list-dirs` (`C-c M L`).
   - [x] Suporte ao interceptor de slash commands no prompt do Magent (`+carlos/magent-slash-interceptor`).

2. [x] **Fase 2: Registro do Slash Command `/usage` com Barra Visual de Cota**
   - [x] Registrado o slash command `/usage` chamando `+carlos/magent-render-usage-chat`.
   - [x] Renderização da barra de progresso ASCII (`[████████░░] 80%`) e consumo acumulado FinOps.

3. [x] **Fase 3: Testes de Regressão e Validação em `tests/magent-test.el`**
   - [x] Criados testes ERT em `tests/magent-test.el` validadas as execuções dos 4 slash commands e do interceptor.

## 0.17. Correção de Sync e Byte-Compile sem Avisos/Erros

- [x] **1. Purga de arquivos residuais no `just sync` (`Justfile`)**
  - Alterada a sincronização do `Justfile` de `cp -r` para `rsync -a --delete` em `lisp/`, `site-lisp/`, `tests/`, `docs/` e `bin/`.
  - Motivo: `cp -r` deixava arquivos residuais legados do Doom Emacs em `~/.config/emacs/lisp/` (`doom-cli.el`, `doom-lib.el`, `cli/`, `lib/`), fazendo o `byte-recompile-directory` falhar.
- [x] **2. Correção de warnings/erros do byte-compiler (`lisp/custom-ai.el`)**
  - [x] Reduzido o tamanho de linhas de docstrings de mais de 80 caracteres para suprimir `docstring wider than 80 characters` (`+carlos/agy-prompt`, `+carlos/gptel-emergency-fallback`, `+carlos/gptel-dynamic-router-advice`, `+carlos/gptel-tracker-file-override`, `+carlos/magent-show-usage`).
  - [x] Adicionadas forward declarations `(defvar url-connection-timeout)` e `(defvar url-queue-timeout)`.
  - [x] Renomeados argumentos não utilizados `beg` e `end` para `_beg` e `_end` em `+carlos/gptel-track-usage` (suprimindo warning de lexical binding).
- [x] **3. Validação dos Portões de Qualidade**
  - Executados `just compile`, `just checkdoc` e `just sync` com 100% de sucesso sem avisos nem erros.

## 0.16. Plano de Ação — Dashboard de Consumo e Rastreamento por Agente

> **Autor:** Agente Arquiteto (modelo Pro/Opus). Plano EXECUTÁVEL para o Agente Executor.

### Tópicos do Plano:

1. [x] **Fase 1: Atualização do Layout da Tabela de Consumo (`docs/ai-usage-tracker.org`)**
   - [x] Inserir a nova coluna 'Agent' na tabela existente para rastrear qual persona/agente do Magent realizou a chamada de IA (ou 'No Agent (gptel)' para requisições diretas).

2. [x] **Fase 2: Forward Declarations e Adaptação do Tracker (`lisp/custom-ai.el`)**
   - [x] Adicionar as declarações `(defvar magent--current-session)` e `(declare-function magent-session-agent "magent")`, além de `(declare-function magent-agent-info-name "magent")` para evitar warnings do byte-compiler.
   - [x] Atualizar a função `+carlos/gptel-track-usage` para:
     - [x] Identificar o agente ativo consultando `(magent-session-agent magent--current-session)` e obtendo seu nome via `magent-agent-info-name` (se aplicável).
     - [x] Injetar o nome do agente (ou fallback 'No Agent (gptel)') na nova coluna da tabela.
     - [x] Estimar o custo financeiro aproximado de mercado para modelos como Claude (Sonnet 3.5/Opus 5) e Gemini (Pro/Flash) com base em taxas padrão por milhão de tokens.

3. [x] **Fase 3: Criar o Dashboard Visual Interativo (`+carlos/magent-show-usage`)**
   - [x] Criar uma nova função interativa `+carlos/magent-show-usage` em um local apropriado.
   - [x] Fazer o parse da tabela Org em `docs/ai-usage-tracker.org`.
   - [x] Agrupar os dados por agente, somar os tokens (input, output, cached) e calcular totais.
   - [x] Exibir uma tabela resumida de custos e tokens em um buffer temporário `*Magent Usage Summary*` no modo Org.

4. [x] **Fase 4: Configuração de Atalhos (`lisp/custom-keybindings.el`)**
   - [x] Associar o comando `+carlos/magent-show-usage` ao atalho global `C-c d u` (Usage/Uso).

## 0.15. Plano de Ação — Conversor de Skills para o Magent

> **Autor:** Agente Arquiteto (modelo Pro/Opus). Plano EXECUTÁVEL para o Agente Executor.

### Tópicos do Plano:

1. [x] **Fase 1: Estrutura do CLI e Setup (`bin/skill-convert`)**
   - [x] Criar o script Python executável `bin/skill-convert`.
   - [x] Implementar um parser de argumentos (via `argparse`) que defina origens padrão (`~/.agents/skills/`, `~/.gemini/config/plugins/`) e destino (`magent/skills/`).
   - [x] Configurar logging para registrar o andamento da conversão e possíveis erros.

2. [x] **Fase 2: Parsing e Tratamento de Frontmatter**
   - [x] Desenvolver lógica para varrer os diretórios de origem e identificar arquivos de skills válidos (`SKILL.md` ou similares).
   - [x] Ler o conteúdo e extrair o frontmatter YAML e o corpo do texto original.
   - [x] Criar a estrutura base do novo frontmatter para o Magent, garantindo a presença das chaves obrigatórias (`type: instruction` e `capability: true`).

3. [x] **Fase 3: Detecção de Backend e Prompting IA**
   - [x] Implementar um verificador de conectividade que faça ping no MLX Local (`http://localhost:8081`).
   - [x] Caso o MLX não esteja disponível, efetuar fallback automático para o Ollama (`http://localhost:11434`).
   - [x] Desenvolver o *system prompt* instruindo a IA a reestruturar e adaptar as instruções originais para o formato compatível com o Magent.
   - [x] Fazer as requisições HTTP (usando `urllib`) repassando o conteúdo original da skill e recuperando o markdown adaptado pela IA.

4. [x] **Fase 4: Geração de Arquivos**
   - [x] Para cada skill processada, garantir a criação do diretório de destino: `magent/skills/<nome_da_skill>/`.
   - [x] Realizar o merge do novo frontmatter (em YAML) com a saída da IA.
   - [x] Escrever o resultado final em `magent/skills/<nome_da_skill>/SKILL.md`.

## 0.14. Plano de Ação — Importação de Skills do Cursor e Servidores MCP (Futuro)

### Tópicos do Plano:

1. [ ] **Fase 1: Analisar os repositórios clonados de regras de IA**
   - [ ] **1.1. Inspecionar `awesome-cursorrules`** e selecionar regras de interesse (NixOS, Python, TypeScript).
     Aqui está o catálogo de regras clonadas, organizadas por foco (expanda para visualizar):
     <details>
     <summary>📦 Frontend (React, Next.js, Vue, Svelte, Angular, HTMX, Tailwind) (91 regras)</summary>

       - [ ] `angular-novo-elements-cursorrules-prompt-file.mdc`
       - [ ] `angular-typescript-cursorrules-prompt-file.mdc`
       - [ ] `astro-typescript-cursorrules-prompt-file.mdc`
       - [ ] `cloudflare-workers-hono-angular-saas-cursorrules-prompt-file.mdc`
       - [ ] `cursor-ai-react-typescript-shadcn-ui-cursorrules-p.mdc`
       - [ ] `cursorrules-cursor-ai-nextjs-14-tailwind-seo-setup.mdc`
       - [ ] `html-tailwind-css-javascript-cursorrules-prompt-fi.mdc`
       - [ ] `htmx-basic-cursorrules-prompt-file.mdc`
       - [ ] `htmx-django-cursorrules-prompt-file.mdc`
       - [ ] `htmx-flask-cursorrules-prompt-file.mdc`
       - [ ] `htmx-go-basic-cursorrules-prompt-file.mdc`
       - [ ] `htmx-go-fiber-cursorrules-prompt-file.mdc`
       - [ ] `javascript-astro-tailwind-css-cursorrules-prompt-f.mdc`
       - [ ] `landing-page-image-quality-cursorrules-prompt-file.mdc`
       - [ ] `nextjs-app-router-cursorrules-prompt-file.mdc`
       - [ ] `nextjs-material-ui-tailwind-css-cursorrules-prompt.mdc`
       - [ ] `nextjs-react-tailwind-cursorrules-prompt-file.mdc`
       - [ ] `nextjs-react-typescript-cursorrules-prompt-file.mdc`
       - [ ] `nextjs-seo-dev-cursorrules-prompt-file.mdc`
       - [ ] `nextjs-supabase-shadcn-pwa-cursorrules-prompt-file.mdc`
       - [ ] `nextjs-supabase-todo-app-cursorrules-prompt-file.mdc`
       - [ ] `nextjs-tailwind-typescript-apps-cursorrules-prompt.mdc`
       - [ ] `nextjs-tanstack-query-cursorrules-prompt-file.mdc`
       - [ ] `nextjs-tanstack-query.mdc`
       - [ ] `nextjs-typescript-app-cursorrules-prompt-file.mdc`
       - [ ] `nextjs-typescript-cursorrules-prompt-file.mdc`
       - [ ] `nextjs-typescript-tailwind-cursorrules-prompt-file.mdc`
       - [ ] `nextjs-vercel-supabase-cursorrules-prompt-file.mdc`
       - [ ] `nextjs-vercel-typescript-cursorrules-prompt-file.mdc`
       - [ ] `nextjs.mdc`
       - [ ] `nextjs15-react19-vercelai-tailwind-cursorrules-prompt-file.mdc`
       - [ ] `nextjs15-supabase-cursorrules-prompt-file.mdc`
       - [ ] `nodejs-mongodb-jwt-express-react-cursorrules-promp.mdc`
       - [ ] `qwik-basic-cursorrules-prompt-file.mdc`
       - [ ] `qwik-tailwind-cursorrules-prompt-file.mdc`
       - [ ] `react-chakra-ui-cursorrules-prompt-file.mdc`
       - [ ] `react-components-creation-cursorrules-prompt-file.mdc`
       - [ ] `react-formengine-ai-form-builder-cursorrules-prompt-file.mdc`
       - [ ] `react-graphql-apollo-client-cursorrules-prompt-file.mdc`
       - [ ] `react-mobx-cursorrules-prompt-file.mdc`
       - [ ] `react-native-expo-cursorrules-prompt-file.mdc`
       - [ ] `react-native-expo-router-typescript-windows-cursorrules-prompt-file.mdc`
       - [ ] `react-nextjs-ui-development-cursorrules-prompt-fil.mdc`
       - [ ] `react-query-cursorrules-prompt-file.mdc`
       - [ ] `react-redux-typescript-cursorrules-prompt-file.mdc`
       - [ ] `react-router-v7.mdc`
       - [ ] `react-styled-components-cursorrules-prompt-file.mdc`
       - [ ] `react-tanstack-router-query-cursorrules-prompt-file.mdc`
       - [ ] `react-tanstack-router-query.mdc`
       - [ ] `react-typescript-nextjs-nodejs-cursorrules-prompt-.mdc`
       - [ ] `react-typescript-symfony-cursorrules-prompt-file.mdc`
       - [ ] `react-zustand-cursorrules-prompt-file.mdc`
       - [ ] `react.mdc`
       - [ ] `semiotic-react-dataviz-cursorrules-prompt-file.mdc`
       - [ ] `solidity-react-blockchain-apps-cursorrules-prompt-.mdc`
       - [ ] `solidjs-basic-cursorrules-prompt-file.mdc`
       - [ ] `solidjs-tailwind-cursorrules-prompt-file.mdc`
       - [ ] `solidjs-typescript-cursorrules-prompt-file.mdc`
       - [ ] `svelte-5-vs-svelte-4-cursorrules-prompt-file.mdc`
       - [ ] `svelte.mdc`
       - [ ] `sveltekit-restful-api-tailwind-css-cursorrules-pro.mdc`
       - [ ] `sveltekit-tailwindcss-typescript-cursorrules-promp.mdc`
       - [ ] `sveltekit-typescript-guide-cursorrules-prompt-file.mdc`
       - [ ] `tailwind-css-nextjs-guide-cursorrules-prompt-file.mdc`
       - [ ] `tailwind-react-firebase-cursorrules-prompt-file.mdc`
       - [ ] `tailwind-shadcn-ui-integration-cursorrules-prompt-.mdc`
       - [ ] `tailwind.mdc`
       - [ ] `tanstack-router-react-cursorrules-prompt-file.mdc`
       - [ ] `tauri-svelte-typescript-guide-cursorrules-prompt-f.mdc`
       - [ ] `toss-style-design-system.mdc`
       - [ ] `typescript-nextjs-cursorrules-prompt-file.mdc`
       - [ ] `typescript-nextjs-react-cursorrules-prompt-file.mdc`
       - [ ] `typescript-nextjs-react-tailwind-supabase-cursorru.mdc`
       - [ ] `typescript-nextjs-supabase-cursorrules-prompt-file.mdc`
       - [ ] `typescript-nodejs-nextjs-ai-cursorrules-prompt-fil.mdc`
       - [ ] `typescript-nodejs-nextjs-app-cursorrules-prompt-fi.mdc`
       - [ ] `typescript-nodejs-nextjs-react-ui-css-cursorrules-.mdc`
       - [ ] `typescript-nodejs-react-vite-cursorrules-prompt-fi.mdc`
       - [ ] `typescript-react-cursorrules-prompt-file.mdc`
       - [ ] `typescript-react-nextjs-cloudflare-cursorrules-pro.mdc`
       - [ ] `typescript-react-nextui-supabase-cursorrules-promp.mdc`
       - [ ] `typescript-shadcn-ui-nextjs-cursorrules-prompt-fil.mdc`
       - [ ] `typescript-vite-tailwind-cursorrules-prompt-file.mdc`
       - [ ] `typescript-vuejs-cursorrules-prompt-file.mdc`
       - [ ] `typescript-zod-tailwind-nextjs-cursorrules-prompt-.mdc`
       - [ ] `vue-3-nuxt-3-development-cursorrules-prompt-file.mdc`
       - [ ] `vue-3-nuxt-3-typescript-cursorrules-prompt-file.mdc`
       - [ ] `vue-claude-stack.mdc`
       - [ ] `vue-pinia-cursorrules-prompt-file.mdc`
       - [ ] `vue.mdc`
       - [ ] `vue3-composition-api-cursorrules-prompt-file.mdc`
     </details>
     <details>
     <summary>📦 Linguagens & Ambientes Core (C/C++, Go, Rust, TypeScript, Node) (30 regras)</summary>

       - [ ] `beefreeSDK-nocode-content-editor-cursorrules-prompt-file.mdc`
       - [ ] `chrome-extension-dev-js-typescript-cursorrules-pro.mdc`
       - [ ] `cpp-programming-guidelines-cursorrules-prompt-file.mdc`
       - [ ] `cpp.mdc`
       - [ ] `deno-integration-techniques-cursorrules-prompt-fil.mdc`
       - [ ] `dragonruby-best-practices-cursorrules-prompt-file.mdc`
       - [ ] `elixir-engineer-guidelines-cursorrules-prompt-file.mdc`
       - [ ] `elixir-phoenix-docker-setup-cursorrules-prompt-fil.mdc`
       - [ ] `es-module-nodejs-guidelines-cursorrules-prompt-fil.mdc`
       - [ ] `fortran.mdc`
       - [ ] `go-backend-scalability-cursorrules-prompt-file.mdc`
       - [ ] `go-servemux-rest-api-cursorrules-prompt-file.mdc`
       - [ ] `go-temporal-dsl-prompt-file.mdc`
       - [ ] `go.mdc`
       - [ ] `google-adk.mdc`
       - [ ] `hol-hedera-typescript-cursorrules-prompt-file.mdc`
       - [ ] `javascript-typescript-code-quality-cursorrules-pro.mdc`
       - [ ] `node-express.mdc`
       - [ ] `nodejs-mongodb-cursorrules-prompt-file-tutorial.mdc`
       - [ ] `r-cursorrules-prompt-file-best-practices.mdc`
       - [ ] `rust-general.mdc`
       - [ ] `rust.mdc`
       - [ ] `scala-kafka-cursorrules-prompt-file.mdc`
       - [ ] `typescript-axios-cursorrules-prompt-file.mdc`
       - [ ] `typescript-clasp-cursorrules-prompt-file.mdc`
       - [ ] `typescript-code-convention-cursorrules-prompt-file.mdc`
       - [ ] `typescript-llm-tech-stack-cursorrules-prompt-file.mdc`
       - [ ] `typescript-nestjs-best-practices-cursorrules-promp.mdc`
       - [ ] `typescript.mdc`
       - [ ] `vscode-extension-dev-typescript-cursorrules-prompt-file.mdc`
     </details>
     <details>
     <summary>📦 Python, IA, Machine Learning & Data Science (25 regras)</summary>

       - [ ] `automl-hyperparameter-optimization.mdc`
       - [ ] `blender-python-addon.mdc`
       - [ ] `fastapi-production-architecture-cursorrules-prompt-file.mdc`
       - [ ] `fastapi.mdc`
       - [ ] `linux-nvidia-cuda-python-cursorrules-prompt-file.mdc`
       - [ ] `pandas-scikit-learn-guide-cursorrules-prompt-file.mdc`
       - [ ] `pyqt6-eeg-processing-cursorrules-prompt-file.mdc`
       - [ ] `pyspark-etl-best-practices-cursorrules-prompt-file.mdc`
       - [ ] `python--typescript-guide-cursorrules-prompt-file.mdc`
       - [ ] `python-312-fastapi-best-practices-cursorrules-prom.mdc`
       - [ ] `python-containerization-cursorrules-prompt-file.mdc`
       - [ ] `python-cursorrules-prompt-file-best-practices.mdc`
       - [ ] `python-developer-cursorrules-prompt-file.mdc`
       - [ ] `python-django-best-practices-cursorrules-prompt-fi.mdc`
       - [ ] `python-fastapi-best-practices-cursorrules-prompt-f.mdc`
       - [ ] `python-fastapi-cursorrules-prompt-file.mdc`
       - [ ] `python-fastapi-scalable-api-cursorrules-prompt-fil.mdc`
       - [ ] `python-flask-json-guide-cursorrules-prompt-file.mdc`
       - [ ] `python-github-setup-cursorrules-prompt-file.mdc`
       - [ ] `python-llm-ml-workflow-cursorrules-prompt-file.mdc`
       - [ ] `python-projects-guide-cursorrules-prompt-file.mdc`
       - [ ] `python.mdc`
       - [ ] `pytorch-scikit-learn-cursorrules-prompt-file.mdc`
       - [ ] `temporal-python-cursorrules.mdc`
       - [ ] `tensorflow-deep-learning.mdc`
     </details>
     <details>
     <summary>📦 Mobile (Flutter, Android, React Native) (6 regras)</summary>

       - [ ] `android-jetpack-compose-cursorrules-prompt-file.mdc`
       - [ ] `flutter-app-expert-cursorrules-prompt-file.mdc`
       - [ ] `flutter-development-guidelines-cursorrules-prompt-file.mdc`
       - [ ] `flutter-riverpod-cursorrules-prompt-file.mdc`
       - [ ] `nativescript-cursorrules-prompt-file.mdc`
       - [ ] `nativescript.mdc`
     </details>
     <details>
     <summary>📦 Banco de Dados, Cloud, DevOps & Smart Contracts (17 regras)</summary>

       - [ ] `convex-cursorrules-prompt-file.mdc`
       - [ ] `database.mdc`
       - [ ] `docker.mdc`
       - [ ] `knative-istio-typesense-gpu-cursorrules-prompt-fil.mdc`
       - [ ] `kubernetes-mkdocs-documentation-cursorrules-prompt.mdc`
       - [ ] `netlify-official-cursorrules-prompt-file.mdc`
       - [ ] `optimize-rell-blockchain-code-cursorrules-prompt-f.mdc`
       - [ ] `postgresql.mdc`
       - [ ] `snowflake-cortex-ai-cursorrules-prompt-file.mdc`
       - [ ] `snowflake-data-engineering-cursorrules-prompt-file.mdc`
       - [ ] `snowflake-snowpark-dbt-cursorrules-prompt-file.mdc`
       - [ ] `solana-wallet-aware.mdc`
       - [ ] `solidity-foundry-cursorrules-prompt-file.mdc`
       - [ ] `solidity-hardhat-cursorrules-prompt-file.mdc`
       - [ ] `vercel-deployment-cursorrules-prompt-file.mdc`
       - [ ] `vercel-deployment.mdc`
       - [ ] `xian-smart-contracts-cursor-rules-prompt-file.mdc`
     </details>
     <details>
     <summary>📦 QA, Testes, Commits & Padrões de Qualidade (28 regras)</summary>

       - [ ] `anti-overengineering.mdc`
       - [ ] `anti-sycophancy-code-discipline-cursorrules-prompt-file.mdc`
       - [ ] `clean-code.mdc`
       - [ ] `code-style-consistency-cursorrules-prompt-file.mdc`
       - [ ] `codequality.mdc`
       - [ ] `cypress-accessibility-testing-cursorrules-prompt-file.mdc`
       - [ ] `cypress-api-testing-cursorrules-prompt-file.mdc`
       - [ ] `cypress-defect-tracking-cursorrules-prompt-file.mdc`
       - [ ] `cypress-e2e-testing-cursorrules-prompt-file.mdc`
       - [ ] `cypress-integration-testing-cursorrules-prompt-file.mdc`
       - [ ] `gherkin-style-testing-cursorrules-prompt-file.mdc`
       - [ ] `git-conventional-commit-messages.mdc`
       - [ ] `gitflow.mdc`
       - [ ] `jest-unit-testing-cursorrules-prompt-file.mdc`
       - [ ] `optimize-dry-solid-principles-cursorrules-prompt-f.mdc`
       - [ ] `playwright-accessibility-testing-cursorrules-prompt-file.mdc`
       - [ ] `playwright-api-testing-cursorrules-prompt-file.mdc`
       - [ ] `playwright-defect-tracking-cursorrules-prompt-file.mdc`
       - [ ] `playwright-e2e-testing-cursorrules-prompt-file.mdc`
       - [ ] `playwright-integration-testing-cursorrules-prompt-file.mdc`
       - [ ] `pr-review-cursorrules-prompt-file.mdc`
       - [ ] `pr-template-cursorrules-prompt-file.mdc`
       - [ ] `qa-bug-report-cursorrules-prompt-file.mdc`
       - [ ] `readme-best-practices-cursorrules-prompt-file.mdc`
       - [ ] `testrail-test-case-cursorrules-prompt-file.mdc`
       - [ ] `typescript-expo-jest-detox-cursorrules-prompt-file.mdc`
       - [ ] `vitest-unit-testing-cursorrules-prompt-file.mdc`
       - [ ] `xray-test-case-cursorrules-prompt-file.mdc`
     </details>
     <details>
     <summary>📦 Outros / Jogos / CMS / Específicos (60 regras)</summary>

       - [ ] `ai-agent-specialist.mdc`
       - [ ] `alpha-skills-quant-factor-research.mdc`
       - [ ] `ankra-cli.mdc`
       - [ ] `ascii-simulation-game-cursorrules-prompt-file.mdc`
       - [ ] `aspnet-abp-cursorrules-prompt-file.mdc`
       - [ ] `beefreeSDK.mdc`
       - [ ] `cloudflare-email-telegram-cursorrules-prompt-file.mdc`
       - [ ] `code-guidelines-cursorrules-prompt-file.mdc`
       - [ ] `code-pair-interviews.mdc`
       - [ ] `cursor-rules-pack-v2-cursorrules-prompt-file.mdc`
       - [ ] `cursorrules-cursor-ai-wordpress-draft-macos-prompt.mdc`
       - [ ] `drupal-11-cursorrules-prompt-file.mdc`
       - [ ] `embedded-stm32-hal.mdc`
       - [ ] `engineering-ticket-template-cursorrules-prompt-file.mdc`
       - [ ] `gamemaker-gml.mdc`
       - [ ] `github-code-quality-cursorrules-prompt-file.mdc`
       - [ ] `github-cursorrules-prompt-file-instructions.mdc`
       - [ ] `graphical-apps-development-cursorrules-prompt-file.mdc`
       - [ ] `harmony-arkts.mdc`
       - [ ] `helium-mcp-cursorrules-prompt-file.mdc`
       - [ ] `how-to-documentation-cursorrules-prompt-file.mdc`
       - [ ] `java-general-purpose-cursorrules-prompt-file.mdc`
       - [ ] `java-springboot-jpa-cursorrules-prompt-file.mdc`
       - [ ] `javascript-chrome-apis-cursorrules-prompt-file.mdc`
       - [ ] `kotlin-ktor-development-cursorrules-prompt-file.mdc`
       - [ ] `kotlin-springboot-best-practices-cursorrules-prompt-file.mdc`
       - [ ] `kubestellar-console.mdc`
       - [ ] `laravel-php-83-cursorrules-prompt-file.mdc`
       - [ ] `laravel-tall-stack-best-practices-cursorrules-prom.mdc`
       - [ ] `manifest-yaml-cursorrules-prompt-file.mdc`
       - [ ] `medusa-cursorrules.mdc`
       - [ ] `medusa.mdc`
       - [ ] `momen-cursurrules-prompt-file.mdc`
       - [ ] `nestjs-anti-hallucination-cursorrules-prompt-file.mdc`
       - [ ] `network-troubleshoot.mdc`
       - [ ] `next-type-llm.mdc`
       - [ ] `plasticode-telegram-api-cursorrules-prompt-file.mdc`
       - [ ] `project-epic-template-cursorrules-prompt-file.mdc`
       - [ ] `py-fast-api.mdc`
       - [ ] `rails-cursorrules-prompt-file.mdc`
       - [ ] `ros-ros2.mdc`
       - [ ] `rtl-right-to-left-i18n-cursorrules-prompt-file.mdc`
       - [ ] `salesforce-apex-cursorrules-prompt-file.mdc`
       - [ ] `security-devsecops-ssdls-appsec.mdc`
       - [ ] `shopify-theme-dev-liquid.mdc`
       - [ ] `swift-uikit-cursorrules-prompt-file.mdc`
       - [ ] `swiftui-guidelines-cursorrules-prompt-file.mdc`
       - [ ] `tanstack-query-v5-cursorrules-prompt-file.mdc`
       - [ ] `tanstack-query.mdc`
       - [ ] `tanstack-router.mdc`
       - [ ] `tanstack-start-cursorrules-prompt-file.mdc`
       - [ ] `tanstack-start.mdc`
       - [ ] `tokrepo-agent-discovery-cursorrules-prompt-file.mdc`
       - [ ] `typo3cms-extension-cursorrules-prompt-file.mdc`
       - [ ] `uikit-guidelines-cursorrules-prompt-file.mdc`
       - [ ] `unity-cursor-ai-c-cursorrules-prompt-file.mdc`
       - [ ] `web-app-optimization-cursorrules-prompt-file.mdc`
       - [ ] `webassembly-z80-cellular-automata-cursorrules-prom.mdc`
       - [ ] `wordpress-claude-stack.mdc`
       - [ ] `wordpress-php-guzzle-gutenberg-cursorrules-prompt-.mdc`
     </details>
   - [x] **1.2. Adaptar regras para o formato de skills do Magent**:
     - Clonado o repositório `awesome-cursorrules` em `~/Projetos/Github/awesome-cursorrules`.
     - Convertidas as 9 regras prioritárias (`cpp-programming-guidelines`, `clean-code`, `python-fastapi-scalable-api`, `pytorch-scikit-learn`, `python-312-fastapi-best-practices`, `javascript-typescript-code-quality`, `nextjs-typescript-tailwind`, `git-conventional-commit-messages`, `anti-overengineering`) para `magent/skills/` com o script `bin/skill-convert`. Total de 21 skills ativas.
2. [x] **Fase 2: Conectar o Magent a servidores MCP locais**
   - [x] **2.1. Configurar scripts CLI de bridge** para servidores MCP:
     - **Servidores Alvo:** Chrome DevTools e Figma/Stitch.
     - **Abordagem:** Criar um script executável (`bin/mcp-bridge`) em Node.js ou Python que instancie o cliente MCP e exponha comandos via CLI (ex: `bin/mcp-bridge chrome --inspect <url>`).
     - **Integração no Magent:** O Magent utilizará sua tool nativa `run_command` para invocar o `bin/mcp-bridge`, recebendo as respostas do servidor MCP no `stdout` do shell e interpretando-as no loop de ação.

---

## 0.13. Plano de Ação — Adaptação de Skills da Plataforma & Agentes do OpenCode

### Tópicos do Plano:

1. [x] **Fase 1: Criar Personas/Agentes em `gptel-directives` (custom-ai.el)**
   - [x] **1.1. Adicionar os Agentes do OpenCode** (`hephaestus`, `architect`, `revisor`) no `custom-ai.el` em `gptel-directives`.

2. [x] **Fase 2: Adaptar as Skills para o Magent**
   - [x] **2.1. Criar as Skills no formato do Magent** em `magent/skills/` (mapeadas dinamicamente):
     - [x] `architect`: Instruções de arquitetura de software e design de sistemas baseadas no oh-my-openagent.
     - [x] `revisor`: Lógica de code-review automatizado para o Magent.
     - [x] `librarian`: Pesquisa e análise de documentação RAG estruturada em formato Org local.
     - [x] `modern-web-guidance`: Boas práticas de CSS moderno, layout responsivo e UI premium do Antigravity.
     - [x] `a11y-debugging`: Auditoria e correção de acessibilidade baseada no web.dev.
     - [x] `memory-leak-debugging`: Diagnóstico de vazamento de memória e heap dumps em JS/Node.
   - [x] **2.2. Clonar bibliotecas de referência de IA** na pasta `~/Projects/Github` (`awesome-cursorrules`, `awesome-mcp-servers`, `awesome-mcp`) para análise e futuras importações.
   
3. [x] **Fase 3: Criar Testes Unitários de Regressão em `tests/magent-test.el`**
   - [x] **3.1. Validar se as novas skills** estão presentes e expostas corretamente (teste `myemacs-local-ai-skills-exist` estendido e validado).

---

## 0.12. Plano de Ação — Roteador de Agentes, RAG MarkItDown e FinOps

### Tópicos do Plano:

1. [x] **Fase 1: Roteador Dinâmico baseado em Hooks (Proposta A)**
   - [x] **1.1. Criar a função `+carlos/gptel-dynamic-router-hook`** (implementado como `+carlos/gptel-dynamic-router-advice` `:before` `gptel-request`).
   - [x] **1.2. Implementar a lógica de roteamento por contexto/buffer/prompt** (Magent ➜ Claude; Local Prog ➜ MLX Qwen 9B; Geral ➜ Gemini Cloud).
   - [x] **1.3. Criar testes unitários em `tests/ai-test.el`** (teste `myemacs-ai-dynamic-router` mockando buffers e system-name passou 100% verde).

2. [x] **Fase 2: FinOps - Sistema de Rastreamento de Tokens e Custos (`custom-ai-tracker`)**
   - [x] **2.1. Criar a função `+carlos/gptel-track-usage`** em `custom-ai.el` conectada a `gptel-post-response-functions`.
   - [x] **2.2. Ler a variável local do buffer `gptel--token-usage`** após a requisição.
   - [x] **2.3. Salvar os logs** formatados como tabela Org no arquivo `docs/ai-usage-tracker.org`.

3. [x] **Fase 3: Structured Outputs nos Scripts Locais (JSON / FSM)**
   - [x] **3.1. Adaptar `bin/rag-convert` e `bin/log-triage`** para injeção de `response_format`:
     - Para Ollama: Adicionar `"format": "json"` no payload da API.
     - Para MLX Local (compatível com OpenAI): Incluir o parâmetro `"response_format"` contendo o JSON Schema exigido.
     - **Schema Exemplo para RAG/Triage:**
       ```json
       {
         "type": "json_schema",
         "json_schema": {
           "name": "triage_result",
           "schema": {
             "type": "object",
             "properties": {
               "summary": { "type": "string" },
               "error_count": { "type": "integer" },
               "recommendations": { "type": "array", "items": { "type": "string" } }
             },
             "required": ["summary", "error_count", "recommendations"]
           }
         }
       }
       ```

4. [x] **Fase 4: Pipeline de RAG Universal com MarkItDown**
   - [x] **4.1. Criar o comando `+carlos/ai-rag-ingest`** em `lisp/custom-ai.el`:
     - Solicitar arquivo ou URL interativamente: `(read-file-name "Arquivo/URL para ingestão: ")`.
     - Executar assincronamente: usar `make-process` ou `async-shell-command` chamando `bin/rag-convert <caminho>`.
     - Exibição: Adicionar sentinel ao processo para, no sucesso, abrir o buffer com o arquivo `.org` resultante (`find-file`).
     - **Código Base Sugerido:**
       ```elisp
       (defun +carlos/ai-rag-ingest (target)
         "Ingere um arquivo ou URL via MarkItDown e RAG converter."
         (interactive "fArquivo/URL para ingestão: ")
         (message "Iniciando ingestão de %s..." target)
         (make-process
          :name "rag-ingest"
          :buffer "*rag-ingest*"
          :command (list (expand-file-name "bin/rag-convert" user-emacs-directory) target)
          :sentinel (lambda (proc event)
                      (when (string= event "finished\n")
                        (message "Ingestão concluída!")
                        (find-file (concat target ".org")))))) ;; Ajustar caminho conforme saída real
       ```

---

## 0.11. Plano de Ação — Migração Definitiva Doom Emacs → Vanilla MyEmacs

> **Autor:** Agente Arquiteto (modelo Pro/Opus). Plano EXECUTÁVEL para o Agente Executor e Auditor.

### Tópicos do Plano:

1. [x] **Fase 1: Snapshot e Backup do Doom Emacs Legado**
   - Criar diretório de backup `~/.config/doom-emacs-backup-$(date +%Y%m%d)` contendo cópia integral de `~/.config/doom` e `~/.config/emacs` antigos antes de qualquer remoção.
   - Código sugerido:
     ```bash
     BACKUP_DIR=~/.config/doom-emacs-backup-$(date +%Y%m%d)
     mkdir -p $BACKUP_DIR
     cp -R ~/.config/doom $BACKUP_DIR/doom 2>/dev/null || true
     cp -R ~/.config/emacs $BACKUP_DIR/emacs 2>/dev/null || true
     ```

2. [x] **Fase 2: Substituição Autoritativa de `~/.config/emacs`**
   - Remover os links/diretórios antigos de `~/.config/emacs` (Doom) e `~/.config/emacs-vanilla`.
   - Copiar/sincronizar o repositório autoritativo `MyEmacs` (`~/Projetos/emacsConfig/MyEmacs`) diretamente para `~/.config/emacs` (ou criar o link simbólico correto se desejado, mantendo a regra de sync do Justfile).
   - Atualizar o `Justfile` para que o alvo `sync` sincronize para `~/.config/emacs` (oficial) em vez de `~/.config/emacs-vanilla`.
   - Código sugerido:
     ```bash
     rm -rf ~/.config/emacs ~/.config/emacs-vanilla
     # A sincronização inicial (se for cópia)
     cp -R ~/Projetos/emacsConfig/MyEmacs ~/.config/emacs
     ```
     - No `Justfile`, alterar referências de `~/.config/emacs-vanilla/` para `~/.config/emacs/`.

3. [x] **Fase 3: Remoção Completa do Doom Emacs e Caches Legados**
   - Remover a pasta `~/.config/doom`.
   - Remover a pasta `~/.local/share/doom` e `~/.emacs.d` (se existirem).
   - Remover alias ou wrappers legados que apontavam para `doom`.
   - Código sugerido:
     ```bash
     rm -rf ~/.config/doom ~/.local/share/doom ~/.emacs.d
     # Remover wrappers se houver, ex: ~/.local/bin/doom
     ```

4. [x] **Fase 4: Validação Total de Inicialização Nativa & Suíte ERT**
   - Executar `just check-all` apontando para o novo ambiente padrão `~/.config/emacs`.
   - Testar lançamento nativo via terminal: `emacs --batch -l init.el`.
   - Garantir 100% de passagem dos 111 testes ERT.
   - Código sugerido:
     ```bash
     cd ~/Projetos/emacsConfig/MyEmacs
     just check-all
     emacs --init-directory ~/.config/emacs --batch -l init.el --eval '(message "OK")'
     ```

5. [x] **Fase 5: Atualização da Documentação (`AGENTS.md`, `TODO.md`, `roadmap.org`)**
   - Atualizar `AGENTS.md` refletindo que `~/.config/emacs` agora é o ambiente oficial de execução de testes e uso produtivo do usuário (removendo a referência temporária a `emacs-vanilla`).
   - Atualizar o changelog no `roadmap.org`.

## 0.10. Plano de Ação — Integração Magit Transient Commit IA & Fix Void Magent / Warnings

> **Autor:** Agente Arquiteto (modelo Pro/Opus). Plano EXECUTÁVEL para o Agente Executor e Auditor.

### Tópicos do Plano:

1. [x] **Fix `magent-start` Void Function (`lisp/custom-magent.el`):**
   - Adicionar autoloads explícitos em `custom-magent.el` para `magent-start`, `magent-agent-shell-interrupt` e `magent-agent-shell-prompt-region`.

2. [x] **Eliminar os 11 Avisos de Compilação Nativa (`declare-function`):**
   - `custom-term.el`: `(declare-function popper-echo-mode "popper")` e `(declare-function project-root "project")`.
   - `custom-42.el`: `(declare-function elpaca-wait "elpaca")`.
   - `custom-ai.el`: `(declare-function gptel-make-openai "gptel-openai")`, `(declare-function gptel-make-anthropic "gptel-anthropic")`, `(declare-function gptel-make-gemini "gptel-gemini")` e `(declare-function gptel-make-ollama "gptel-ollama")`.
   - `custom-knowledge.el`: `(declare-function denote-link-dired "denote")`.
   - `custom-git.el`: `(declare-function justl-compile "justl")`.
   - `custom-files.el`: `(declare-function dirvish-peek-mode "dirvish-peek")` e `(declare-function dirvish-side-follow-mode "dirvish-side")`.

3. [x] **Integração do Magit Transient Commit IA (`lisp/custom-git.el`):**
   - Adicionar o sulfixo `g` no menu de commit do Magit (`magit-commit` transient): `c g` no Magit Status dispara a geração de commit IA offline via Ollama local.

4. [x] **Testes ERT (`tests/git-test.el` e `tests/magent-test.el`):**
   - Adicionado teste ERT `myemacs-git-magit-commit-ia-transient` (108 testes ERT verdes).

## 0.9. Plano de Ação — Automação com Modelos Locais (Ollama CPU Pipeline)

> **Autor:** Agente Arquiteto (modelo Pro/Opus). Plano EXECUTÁVEL para automação local sem custo de tokens de nuvem.

### Tópicos do Plano:

1. [x] **Commit IA Local Sincrônico (`qwen2.5-coder:1.5b`):**
   - Atualizar `+carlos/gptel-generate-commit-message` em `lisp/custom-git.el` para usar por padrão `"Ollama Local"` com `'qwen2.5-coder:1.5b` (resposta instantânea em <0.5s no `aa102-006l`).

2. [x] **Pipeline RAG Document Converter (`markitdown` → `Org-Mode` Padronizado):**
   - Criar script utilitário `bin/rag-convert` (Python/CLI) que executa `markitdown` no arquivo de origem (PDF/HTML/MD) e invoca o Ollama local (`qwen2.5-coder:3b`) para estruturar a saída em `.org` padronizado para a pasta `docs/`.
   - Criar skill `.magent/skills/rag-converter/SKILL.md`.

3. [x] **Pipeline de Triagem de Erros de Testes (`just triage` & `test-triage`):**
   - Adicionar o alvo `triage` no `Justfile`.
   - Executa `just check-all`, captura logs de erros/warnings e invoca o Ollama local (`qwen2.5-coder:1.5b` ou `3b`) para resumir logs extensos em um relatório sintético de 15 linhas no formato Org/Markdown RAG.
   - Criar a skill `.magent/skills/test-triage/SKILL.md`.

4. [x] **Gerador Local de Docstrings e Esqueletos de Testes (`C-c c d` / `C-c c t`):**
   - Adicionar funções em `lisp/custom-lang.el` (`+carlos/generate-docstring-at-point` e `+carlos/generate-test-at-point`) usando `"Ollama Local"` / `'qwen2.5-coder:3b`.

5. [x] **Testes ERT (`tests/local-ai-automation-test.el`):**
   - Testes de regressão para verificar os comandos e a presença das skills locais (107 testes ERT verdes).

## 0. Checkpoint de Rollback (baseline)

> **Commit de referência (SAVE POINT ATUAL):** `2281840` — `fix(ai,magent): set :demand t and global defaults for gptel backends to ensure valid LLM transport in Magent`
> **Estado (aprovado pelo usuário: "estou bem satisfeito, registre o commit atual como savepoint"):**
> - **Magent Native Coding Agent (`50ef707`):** 15 ferramentas nativas, `agent-shell` ACP frontend, suporte a skills (`.magent/skills/`), ledger por projeto e integração automática com `AGENTS.md`.
> - **Atalhos Magent & Org:** Prefixo `C-c A` (`C-c A m` / `C-c A i` / `C-c A r`). `C-c a` preservado para `org-agenda` nativo.
> - **Magit IA Commit Transient (`c g`):** Menu de commit do Magit estendido com `g` disparando IA Commit local via Ollama (`qwen2.5-coder:1.5b`).
> - **Automação IA Local:** `bin/rag-convert`, `bin/log-triage` (`just triage`), `+carlos/generate-docstring-at-point` (`C-c c d`) e `+carlos/generate-test-at-point` (`C-c c t`).
> - **Dev Environment Vanilla:** `dirvish-side` MRU open action, Flycheck wave faces, `nerd-icons-corfu`, `eldoc-box`, `apheleia`, `makefile-executor` (`C-c m m`), `indent-bars`, `rainbow-delimiters`.
> - **Suíte de Testes & Qualidade:** **109 testes ERT 100% verdes**, 0 warnings no byte-compiler, checkdoc limpo, sincronizado com `~/.config/emacs-vanilla`.
> **Reverter:** `git revert 2281840` (preserva histórico) ou `git reset --hard 2281840` em `~/Projects/Github/MyEmacs`, depois `just sync`.
> **SAVE POINT ANTERIOR:** `4679a26` — `fix(elpaca): remove duplicate transient declaration causing 'Duplicate item ID queued'`

> **SAVE POINT ANTERIOR:** `29d7dab` — `docs: record dirvish emerge/peek/git-msg activation in TODO and roadmap`
> **Estado (aprovado pelo usuário: "ficou perfeito"):** dirvish refatorado (ícones/sidebar/hooks corretos), olivetti responsivo `0.85`, Zen reading, RAG de extensões atualizado e extensões dirvish ativas — `git-msg` no painel principal, `E` → `dirvish-emerge-mode` com 6 grupos padrão, `dirvish-peek-mode` global com debounce 0.5. Emacs de teste (`~/.config/emacs-vanilla`) abre sem erros, sincronizado com `origin/main`.
> **Reverter:** `git revert 29d7dab` (preserva histórico) ou `git reset --hard 29d7dab` (destrói commits seguintes) em `~/Projects/Github/MyEmacs`, depois `cd ~/.config/emacs-vanilla && git stash && git pull && git stash pop`.
> **Anterior:** `aad799c` (RAG extensions) — útil como ponto anterior ao experimento das extensões.

- [x] **Correção completa da stack de IA (gptel 0.9.9.5):**
  - **Backends Zen corrigidos:** `zen.opencode.ai` era **NXDOMAIN** — hosts reais: `opencode.ai` + `:endpoint "/zen/v1/chat/completions"` (OpenAI) e `"/zen/v1/messages"` (Anthropic). Keys via `(getenv "OPENCODE_ZEN_API_KEY")` / `(or (getenv "GEMINI_API_KEY") (getenv "GOOGLE_API_KEY"))` (exportadas por `/etc/api-keys.sh` do agenix).
  - **Ollama corrigido (CPU/Linux):** modelos `qwen2.5-coder:3b` (padrão de alto desempenho), `qwen2.5-coder:1.5b` (ultrarrápido) e `deepseek-r1:1.5b` (raciocínio/reasoning) instalados e validados no `aa102-006l`. Modelo antigo `qwen3.5:latest` desinstalado por ser muito pesado em CPU.
  - **API do gptel-request corrigida:** 0.9.9.5 NÃO aceita `:backend`/`:model` (keywords reais: `:callback :buffer :position :context :system :stream :schema :transforms :fsm`). Criado helper `+carlos/gptel-request` (buffer `*gptel-request*` + `gptel-backend`/`gptel-model` buffer-local) e o commit IA em `custom-git.el` reescrito para usá-lo (antes: erro de keyword).
  - **gptel-org eliminado:** não existe `gptel-org-mode` em 0.9.9.5 — integração Org é automática (`derived-mode-p`). Removido bloco no-op.
  - **Código morto removido:** `mcp` e `superchat` (não instalados, `:if` silencioso) + display rule do superchat. `gptel-agent` mantido (registra researcher/introspector/gptel-plan/gptel-agent/executor).
  - **Novo keybinding:** `C-c C-g` (e hook `git-commit-mode`) → `+carlos/gptel-insert-commit-message`.
  - **Validado ponta-a-ponta (batch vanilla):** 5/5 backends respondem PONG (Zen OpenAI, Zen Claude, Gemini, Ollama, MLX); helper e agentes OK; `just compile` zero warnings + checkdoc OK.
  - **Docs:** `docs/gptel-reference.org` e `docs/magit-reference.org` atualizados (API real, hosts Zen, remoção de `gptel-org-mode`/`:backend`/`:model`).
- [x] **Fix: `void-variable gptel-agent-dirs` (gotcha `defvar` do Emacs 30):**
  - Emacs 30: `(defvar X)` sem INITVALUE NÃO liga a variável → forward declarations peladas eram void no runtime. `gptel-agent-dirs`/`gptel-directives` corrigidas com forma pelada + guarda `boundp` (não clobberar defaults não-nil dos defcustoms); demais (`gptel-backend`/`model`, maps do vterm/eshell, `dirvish-emerge--group-overlays`, faces org) com `nil`.
  - `use-package :after` é ignorado com `use-package-expand-minimally t` → gptel-agent agora carrega via `with-eval-after-load 'gptel` (agents + presets registrados).
  - `C-c C-g` agora é global (gera commit IA); dentro do buffer de commit insere direto.
  - Validado: 16/16 arquivos compilados zero warnings, checkdoc OK, regressão batch completa verde. Commit `90e3921`.
- [x] **Suíte de testes ERT (tests/) + política de regressão:**
  - **Decisão:** ERT (nativo, zero dependência, exit code via `ert-run-tests-batch-and-exit`) em vez de Buttercup (BDD de terceiros exigiria instalação e não roda "boot completo" de forma natural).
  - **Infra:** `tests/load-tests.el` (carrega `tests/*-test.el` após o `init.el`); targets no Justfile — `test-batch`, `test-ai` (selector `myemacs-ai`), `test-network` (opt-in `EMACS_TEST_NETWORK=1`), `test-all` (= compile + checkdoc + test-batch); `check-all` agora inclui a suíte.
  - **Arquivos:** boot, keybindings, ai, ai-network (skip-unless rede), files, term, git, org, dashboard — 54 testes, 0 falhas, 6 skipped (rede/vterm).
  - **Bugs reais descobertos pela suíte (corrigidos):** `C-c i` (gptel) sombreado por consult-imenu → imenu movido para `M-s i`; `+carlos/dashboard-open`/`-refresh` declarados mas nunca definidos (void-function `C-c d d`/`C-c d r`) → wrappers de `dashboard-open`/`dashboard-refresh-buffer`; `git-commit` `C-c C-g` via hook (não aplicava em batch) → `define-key` direto no `git-commit-mode-map`.
  - **Outros:** removidos `.elc` stale do repo (usavam código antigo do `defvar nil`); rebuild do `gptel-autoloads.el` no repo (faltava → "Config Error gptel"); documentada a regra "`--eval` avalia só a primeira forma" no AGENTS.md.
- [x] **Header 42 School: login customizado + integração norminette/eglot (16 testes):**
  - **Login 42 (`site-lisp/header42.el`):** `defgroup header42` + `defcustom header-42-login "csilva-d"`; `header-42-get-user` prioriza `header-42-login` → `FT_LOGIN` → `USER` → `"marvin"`.
  - **Bug corrigido:** `header-42-get-filename` chamava `file-name-nondirectory` com `buffer-file-name` nil (erro antes do fallback `"< new >"`) → virou `if`.
  - **Bug corrigido (chain eglot→norminette, `lisp/custom-norminette.el`):** flycheck moderno não tem checker `eglot` (só `eglot-check` bridge) → `custom-norminette-setup` usa `eglot-check` com fallback `eglot`.
  - **Bug corrigido (parser JSON 1/3):** `json-read-from-string` removido no Emacs 30 → substituído por `json-parse-string` com `:array-type 'list`.
  - **Bug corrigido (parser JSON 2/3):** flycheck 39 exige error-parser com 3 args `(output checker buffer)` → wrapper `custom-norminette--flycheck-parser`.
  - **Bug corrigido (parser JSON 3/3):** norminette imprime `"Setting locale to en_US"` antes do JSON → strip prefix com `string-match-p "[{\\[]"`.
  - **`tests/42-test.el`:** 16 testes (login, estrutura do header, idempotência, parser JSON OK/erro/locale-prefix, checker flycheck, parser 3-args, hints, predicate, chain eglot). Suíte completa: 70 tests, 65 expected, 0 unexpected, 5 skipped (vterm/network); checkdoc limpo.
  - **Roadmap:** entrada `** 2026-08-06 — Header 42 School...` atualizada com 3 bugs norminette.
- [x] **c_formatter_42 integration (reformatter.el):**
  - **Package:** `reformatter.el` (MELPA) em `custom-lang.el` — wrapper genérico para CLI reformatters stdin→stdout.
  - **Formatter:** `defgroup +carlos/c-formatter-42` + `defcustom` (executable, format-on-save); `reformatter-define +carlos/c-formatter-42` com `executable-find` guard (zero erro se não instalado).
  - **Keybinding:** `C-c C-f` em buffers C (local-set-key via `my-c-42-style`) — evita conflito com `dirvish-side` em `C-c f`.
  - **Format-on-save:** off por default (42 submete código auto-avaliado); toggle via `+carlos/c-formatter-42-format-on-save` ou `.dir-locals.el`.
  - **Pipeline format-then-check:** `+carlos/norminette-format-and-check` (formata → verifica norminette).
  - **`tests/42-test.el`:** +8 testes (executable custom, format-on-save default, commands exist, keybinding C-c C-f, keybinding não global, group, format-and-check exists, format-and-check error). Suíte completa: **78 tests, 73 expected, 0 unexpected, 5 skipped**.
  - **Commits:** 4 commits no total (feat + 2 fixes de reformatter keywords + fix test group property).

- [x] Registro do planejamento de migração para Magent no TODO.md
## 0.5. Plano de Ação — Migração para Magent (Agente Planejador)

> **Autor:** Agente Planejador/Arquiteto (alta performance). Plano EXECUTÁVEL para o Agente Executor (aplicar) e para o Agente Auditor (validar). **NÃO foi aplicado nada ainda.**
> **SAVE POINT:** `1d7ca9e` — `test: add ERT regression suite (tests/) + fix conflicts it found`
> **Fonte de referência:** Magent commit `50ef707` (MELPA-reviewed, `fix: address MELPA review feedback`) — repo clonado em `/var/folders/p6/jvskwtqn1tl1d75kgr4p32g00000gn/T/opencode/magent`; docs convertidas via markitdown em `.../magent-md/` (README, ARCHITECTURE, AGENT_WORKFLOW, agent/agent-loop/skill-manager); catálogo de tools/permisssões no `AGENTS.md` do Magent.
> **Dependências verificadas no MELPA (archive-contents 2026-08-06):** `magent` **NÃO está no MELPA** → instalar via git. `acp` (20260803), `agent-shell` (20260805), `yaml` (20260605), `shell-maker` (20260805), `cond-let` (20260701) — todos **presentes no MELPA**. `compat` vem do GNU ELPA (já instalado cedo no init.el).

### Contexto e decisão arquitetural

- **O que Magent substitui:** o helper `+carlos/gptel-agent-run` (`C-c I`, gptel-agent) como *agente de codificação* e os CLIs externos `opencode`/`agy` rodando via eshell (`C-c A a` / `C-c A o`, aliases `oc`/`ai`/`aif`/`aireview`/`agy`/`gemini`). Magent é um agente Emacs-Lisp nativo com 15 tools, permissões por agente, sessões por projeto (ledger thread→turn→item), skills, capabilities e child agents — tudo dentro do Emacs, com frontend **agent-shell** (via adaptador ACP in-process; único frontend suportado).
- **O que permanece INTOCADO (transporte e integrações já maduras):**
  - **gptel como transporte único** — Magent usa `gptel-request` por baixo (`magent-llm-gptel.el`). Os 5 backends de `custom-ai.el` (OpenCode Zen, Zen Claude, Gemini, Ollama Local, MLX Local) e o helper `+carlos/gptel-request` continuam.
  - **Chat gptel `C-c i`** e as **personas/diretivas** `c-42`/`cpp-42`/`python` de `gptel-directives` (ficam como estão; as versões Magent são *skills* — ver Fase 3).
  - **Commit IA** `C-c C-g` / `+carlos/gptel-insert-commit-message` (gptel helper em `custom-git.el`).
  - Aliases eshell e binds `C-c A a`/`C-c A o` (mantidos como fallback para fluxos de terminal).
- **Decisão recomendada:** Magent passa a ser o agente de codificação principal (`C-c M m`); `gptel-agent-run` (`C-c I`) e os CLIs eshell ficam como fallback nesta primeira fase (removíveis numa fase futura após período de avaliação).

### Riscos

| Risco | Impacto | Mitigação |
|-------|---------|-----------|
| `magent` fora do MELPA | Instalação não é `:ensure t` simples | Receita git Elpaca com `:ref "50ef707"` pin (mesma receita do melpazoid) |
| `acp`/`agent-shell`/`shell-maker` recém-publicados no MELPA (ago/2026) | API pode mudar / versão mínima não atendida | Versões atuais (20260803/05) satisfazem os mínimos (acp 0.13.1+, agent-shell 0.66.1+); elpaca-lock pina; se quebrar, `:ref` do magent + versões do lock fazem rollback |
| Frontend único (agent-shell + ACP in-process) | Sem fallback de UI se o frontend quebrar | Sempre manter gptel chat (`C-c i`) e `C-c I` como canais alternativos |
| 43 módulos elisp novos do magent | `just compile` pode gerar warnings | Zero warnings obrigatório; forward declarations peladas + guards (padrão do projeto) |
| Conflito de keybinding `C-c M m` | Sobrescrever bind existente | Verificado: nenhum bind `C-c M*` no repo; coberto por `tests/magent-test.el` |
| `use-package-expand-minimally t` ignora `:after` | `:after agent-shell gptel` não funciona | Usar `with-eval-after-load 'magent` (padrão já usado para gptel-agent) |
| Emacs 30 `defvar` gotcha | Forward declaration com `nil` clobberaria defaults não-nil (ex.: `magent-skill-directories` = `~/.emacs.d/magent/skills`) | Forma pelada `(defvar X)` + guardas `boundp`; preferir `:custom` (símbolo quotado, sem free-var warning) |
| `just check`/`just test-all` no repo (builds parciais) | Falha se magent não instalado | `:ensure` enfileira instalação; `(elpaca-wait)` no fim do init.el garante build antes do final do batch (padrão atual) |

### Fase 0 — Decisão e avaliação de riscos (checklist)

- [x] Confirmar com o usuário a decisão: **Magent = agente principal; `C-c I` e eshell CLIs ficam como fallback** (decisão do usuário em 2026-08-06: manter `C-c I` e os aliases `agy`/`opencode`; **backend/modelo decididos pelo picker do agent-shell**, sem agente custom fixo).
- [x] Registrar a decisão no `roadmap.org` (entrada `** 2026-08-06 — Migração para Magent (Agente de Codificação Nativo)`).
- [x] Anotar os riscos da tabela acima no AGENTS.md e no `docs/magent-reference.org`.

### Fase 1 — Instalação (depende da Fase 0)

**Arquivo: `lisp/custom-magent.el` (novo) + `init.el` (1 linha).**

1. **Declaração Elpaca exata** (receita git, pin `50ef707`, `:files` idêntico à receita melpazoid do repo):

```elisp
(use-package magent
  :ensure (magent :repo "Jamie-Cui/magent"
                  :ref "50ef707"
                  :files ("lisp/magent*.el" "prompts" "skills" "capabilities"))
  :custom
  (magent-default-agent "build")
  (magent-enable-audit-log t)
  (magent-project-instruction-file-names '("AGENTS.md"))
  :config
  (with-eval-after-load 'magent
    (magent-agent-shell-ensure-config)))
```

   - `:files` cobre os 43 módulos (`lisp/magent*.el`) + os dados de runtime `prompts/`, `skills/`, `capabilities/` — a receita do melpazoid é `(magent :fetcher github :repo "Jamie-Cui/magent" :files ("lisp/magent*.el" "prompts" "skills" "capabilities"))`. A Elpaca achata `lisp/*.el` para a raiz do build (mesmo layout do MELPA), e o `magent-skills.el:451` já tenta o caminho irmão primeiro — funciona.
   - **Dependências resolvidas automaticamente pela Elpaca** a partir do header `Package-Requires` do `magent.el` (`(emacs "29.1") (gptel "0.9.8") (yaml "1.0.0") (compat "30.1.0.0") (acp "0.13.1") (agent-shell "0.66.1")`): `gptel` e `compat` já instalados; `yaml`, `acp`, `agent-shell` vêm do MELPA (`agent-shell` puxa `shell-maker` + `acp`; `shell-maker` puxa `cond-let`). **NÃO** declarar um segundo `:ensure t` para `acp`/`agent-shell`/`yaml` em outro arquivo — repete o bug "Duplicate item ID queued" do transient.
2. **Load order no `init.el`:** adicionar `(require 'custom-magent)` **imediatamente após** `(require 'custom-ai)` (linha 159) — Magent depende do gptel carregado/backends registrados. A ordem fica: `custom-ai → custom-magent → custom-knowledge → custom-git → custom-dashboard`.
3. **Nova dependência de sistema (Nix):** nenhuma — `rg` já está no ambiente (Magent usa `magent-grep-program "rg"`). Se quiser o tool `web_search`, o Emacs precisa de `--with-xml2` (verificar `(featurep 'xml)`).
4. **Config mínima para `magent-start` funcionar:** basta o bloco acima + `(magent-agent-shell-ensure-config)` (registra o config no agent-shell). O primeiro `M-x magent-start` dispara o autoload → `(require 'magent)` → `magent--ensure-initialized` (runtime lazy). **Não** usar `:demand t` (contraria a filosofia `use-package-always-defer t` do projeto e carrega agent-shell+acp no boot).
5. **Verificação:** `just check` + `just compile` (zero warnings) + `M-x magent-start` no vanilla.

### Fase 2 — Configuração mínima (`lisp/custom-magent.el`, depende da Fase 1)

Criar `lisp/custom-magent.el` seguindo o template do AGENTS.md:

```elisp
;;; custom-magent.el --- Magent (AI coding agent nativo) -*- lexical-binding: t; -*-

;;; Commentary:
;; Magent: agente de codificação Emacs-Lisp com 15 tools, permissões por
;; agente, sessões por projeto (ledger), skills e capabilities. Frontend
;; agent-shell (ACP in-process). Transporte continua sendo gptel-request.
;; Instalado via receita git Elpaca pinada em 50ef707 (não está no MELPA).

;;; Code:

;; Forward declarations (defvar PELADA + guarda boundp — gotcha Emacs 30):
;; defaults de defcustom NÃO-nil não podem ser clobberados com nil.
(defvar magent-system-prompt)
(defvar magent-skill-directories)
(defvar magent-project-instruction-file-names)
(declare-function magent-agent-shell-ensure-config "magent-agent-shell")
(declare-function magent-agent-shell-interrupt "magent-agent-shell")
(declare-function magent-agent-shell-prompt-region "magent-agent-shell")

;; ── magent ──────────────────────────────────────────────────────────
(use-package magent
  :ensure (magent :repo "Jamie-Cui/magent"
                  :ref "50ef707"
                  :files ("lisp/magent*.el" "prompts" "skills" "capabilities"))
  :custom
  (magent-default-agent "build")
  (magent-enable-audit-log t)
  (magent-project-instruction-file-names '("AGENTS.md"))
  (magent-include-reasoning t))

(with-eval-after-load 'magent
  (magent-agent-shell-ensure-config))

;; ── Display rules ──────────────────────────────────────────────────
(add-to-list 'display-buffer-alist
             '("\\*Magent"
               (display-buffer-in-direction)
               (direction . bottom)
               (window-height . 0.5)))

(provide 'custom-magent)
;;; custom-magent.el ends here
```

- **`magent-system-prompt`/defaults via `:custom`** (não `setq` — regra do projeto). O default do system prompt embutido é bom; só sobrescrever se o usuário quiser.
- **ef-themes / dashboard / mood-line não são afetados** — Magent só adiciona o buffer `*Magent*`; a display rule usa o padrão `display-buffer-in-direction` já usado para gptel/term.
- **Keybindings novos (sem conflito — verificado: não existe `C-c M*` no repo):**
  - `C-c M m` → `magent-start` (abrir/reusar sessão do projeto)
  - `C-c M i` → `magent-agent-shell-interrupt` (interromper request ativo)
  - `C-c M r` → `magent-agent-shell-prompt-region` (enviar região)
- **Arquivo: `lisp/custom-keybindings.el`** — adicionar sob a seção "AI (gptel)" (ou nova seção "Magent"):
```elisp
(declare-function magent-start "magent-agent-shell")
(declare-function magent-agent-shell-interrupt "magent-agent-shell")
(declare-function magent-agent-shell-prompt-region "magent-agent-shell")
(global-set-key (kbd "C-c M m") #'magent-start)
(global-set-key (kbd "C-c M i") #'magent-agent-shell-interrupt)
(global-set-key (kbd "C-c M r") #'magent-agent-shell-prompt-region)
```
- **Nota:** o nome real do buffer deve ser confirmado em runtime (`buffer-name`) — `:buffer-name "Magent"` no `agent-shell-make-agent-config` sugere `*Magent*`; ajustar a regex da display rule se necessário.

### Fase 3 — Personas/diretivas 42 + backends (depende da Fase 2)

**Recomendação: converter as 3 diretivas gptel em SKILLS Magent** (instruções só-texto; são o tipo de conteúdo que o Magent espera — nunca viram código executável):

1. Criar `.magent/skills/c-42/SKILL.md`, `.magent/skills/cpp-42/SKILL.md`, `.magent/skills/python/SKILL.md` no repo (projeto-local; auto-descobertas e versionadas):

```markdown
---
name: c-42
description: C tutor at 42 School — Norm v4.1 (tabs, 25 linhas, 80 cols, 5 vars)
type: instruction
---

You are an expert C tutor at 42 School conforming strictly to Norm v4.1.
CRITICAL RULES (Violating these fails the project):
1. FORBIDDEN SYNTAX: No `for`, `do...while`, `switch`, `case`, `goto`, ternary operators, or VLAs.
2. FORMATTING: REAL TABS (width 4). Max 25 lines per function, max 80 columns, max 5 variables.
3. STRUCTURE: Declarations at the top, separated from code by one empty line. No inline initializations (e.g. `int i = 0;` is ILLEGAL).
4. Code must compile with `-Wall -Wextra -Werror`.
```
   (idem `cpp-42` com C++98/Orthodox Canonical Form e `python` com PEP8/type hints/3.10+.)
2. **Backends continuam no gptel** — Magent lê `gptel-backend`/`gptel-model` da sessão (`magent-agent.el:378-382`). **Decisão do usuário (2026-08-06): deixar o picker do agent-shell decidir** backend/modelo por sessão (session options do agent-shell). Opcional futuro: um agente custom `.magent/agent/zen-build.md` fixando `model: claude-sonnet-5` — NÃO necessário agora:
```markdown
---
description: Build agent with Zen Claude sonnet-5
mode: primary
model: claude-sonnet-5
permissions:
  read: allow
  write: ask
  bash: ask
  grep: allow
  glob: allow
---

You are a senior software engineer working on the MyEmacs project.
```
   - Frontmatter suporta: `description`, `mode` (primary/subagent/all), `hidden`, `temperature`, `effort` (auto..xhigh), `model`, `permissions` (allow/deny/ask ou regras por padrão de arquivo com glob; primeira correspondência vence, wildcard `*` no fim).
   - `.magent/agent/*.md` é auto-carregado (`magent-load-custom-agents t` default).
3. **Skills/agentes de 42 fora deste repo:** usar `M-x magent-install-skill` (aceita diretório local) ou `magent-skill-directories` apontando para o repo. **Não** usar o `~/.agents/gptel/` (continua exclusivo do gptel-agent).

### Fase 3.5 — Compatibilidade de skills com o opencode (verificado 2026-08-06)

> **Resposta à pergunta do usuário:** *"magent suporta as skills do opencode? e quando a LSP tem suporte?"* — **NÃO suporta diretamente** (formato incompatível); **LSP é indireto** via skill + `emacs_eval`.

- **Formato incompatível (opencode vs magent):**

| | opencode (`~/.agents/skills/`, `~/.config/opencode/skills`) | magent |
|---|---|---|
| Frontmatter | `name`, `description`, `allowed-tools` | `name`, `description`, **`type: instruction`**, `tools` |
| Executáveis | **Sim** — scripts/companion (ex.: stitch-loop tem `resources/`, scripts) | **Não** — `type: instruction` é o único; código junto ao `SKILL.md` nunca é carregado |
| Instalação | mecanismo do opencode | `magent-install-skill` **rejeita** skill com scripts/código (`contains-code`) |

- **Portáveis (100% instrução):** copiar o `SKILL.md`, adicionar `type: instruction` + `tools`, colocar em `.magent/skills/<nome>/`. Ex.: `find-skills` do `~/.agents/skills/`.
- **NÃO portáveis (com código):** `react-components`, `remotion`, `shadcn-ui`, `stitch-*`, `enhance-prompt`(com design-md), `taste-design` — o equivalente magent seria um `magent-action` (Elisp) ou tool no catálogo; decidir caso a caso, fora do escopo desta migração.
- **LSP (quando tem suporte):** sem tool nativo `lsp_*` no catálogo de 15 tools. Suporte **indireto** via:
  - Skill built-in `lsp-workspace-workflow` (`capability: true`, `features: lsp-mode, eglot`, `modes: prog-mode`) — auto-ativa pelo resolver de capabilities em contexto de programação/LSP; instrui o modelo a usar o workspace LSP/Eglot ativo via `emacs_eval`/`read_buffer`/`grep` (diagnostics, definitions, references, rename, code actions).
  - `/doctor` coleta diagnostics do flymake/flycheck/eglot (`magent-doctor.el:365`).
  - **Para nós funciona:** usamos eglot (a skill declara suporte). Nenhuma integração LSP nova é necessária na migração — registrar como skill/nota, não como integração dedicada.

### Fase 4 — Permissões e segurança (paralela à Fase 2)

- **Política inicial:** manter o default do agente `build` — **`ask`** para `bash`, `emacs_eval` e escritas gerais; leitura/glob/grep permitidos. `magent-bypass-permission` permanece **`nil`** (o `:custom` já deixa explícito). Só ligar via `M-x magent-toggle-bypass-permission` se o usuário quiser agilidade pontual.
- **Auditoria:** `magent-enable-audit-log t` (default) → JSONL diário em `magent-session-directory/audit/`. Sessões ficam em `~/.config/emacs-vanilla/magent/sessions/` (base `user-emacs-directory`) e `projects/<sha1(project-root)>/` por projeto — fora do repo (não commitar).
- **Documentar no AGENTS.md:** "Magent permissions = controle de fluxo de trabalho + audit, NÃO sandbox de segurança (Codex seatbelt/bubblewrap está fora de escopo)".
- **Hardening opcional:** agentes custom com `permissions:` restritas (ex.: agente `42-write` com `write: allow` só em padrões do projeto 42 e `bash: ask`).

### Fase 5 — Integração com o fluxo existente (depende da Fase 3)

- **eshell aliases:** manter `oc`/`ai`/`aif`/`aireview`/`agy`/`gemini` e `C-c A a`/`C-c A o` como fallback para workflows de terminal — **não mexer** (coberto por `tests/term-test.el`). Adicionar ao `docs/term-stack.org` nota "Magent substitui agy/opencode como agente de codificação; CLIs permanecem no terminal".
- **Commit IA:** manter `C-c C-g`/`+carlos/gptel-insert-commit-message` (gptel helper). Magent tem `/summarize` (PR-style) e `/review` — documentar como alternativa, mas não substituir.
- **`C-c I` (gptel-agent-run):** manter nesta fase (fallback). Decisão de descontinuar fica para avaliação pós-uso de Magent.
- **Docs RAG — novo `docs/magent-reference.org`:** instalação (receita Elpaca git), frontend agent-shell, entry points (`magent-start`, `magent-agent-shell-*`), 15 tools + permission keys, built-in agents (build/plan/explore/general/compaction/title/summary), slash commands (`/explain /fix /init /review /summarize /test /compact /skills /doctor /memory-*`), skills (`SKILL.md` frontmatter), agents custom (`.magent/agent/*.md`), sessions/audit dirs, display rule `*Magent*`, pitfalls (frontend único, `:after` ignorado, defvar gotcha).
- **AGENTS.md (projeto):** adicionar `lisp/custom-magent.el` à árvore de módulos, atualizar "Module Loading Order" (custom-magent após custom-ai), registrar os novos keybindings e a decisão da Fase 0, e apontar para `docs/magent-reference.org` na tabela de Package Reference Docs.

### Fase 6 — Testes de regressão ERT (depende da Fase 2)

Criar `tests/magent-test.el` (prefixo `myemacs-magent-*`; roda no `test-batch` completo; rede é opt-in — nada de rede aqui; módulos não disponíveis → `skip-unless`, padrão do vterm):

```elisp
;;; magent-test.el --- Magent regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Verifica: pacote carrega, comandos existem, bind C-c M m sem conflito,
;; configs (skills dir, project instructions) e registro no agent-shell.
;; Magent pode não estar instalado no repo (builds parciais) — guard.

;;; Code:
(require 'ert)

(defvar myemacs-magent-available
  (condition-case nil (require 'magent) (error nil))
  "Non-nil quando o pacote magent carrega neste ambiente.")

(ert-deftest myemacs-magent-package-loads ()
  (skip-unless myemacs-magent-available)
  (should (featurep 'magent)))

(ert-deftest myemacs-magent-commands-exist ()
  (skip-unless myemacs-magent-available)
  (should (commandp 'magent-start))
  (should (commandp 'magent-agent-shell-interrupt))
  (should (commandp 'magent-agent-shell-prompt-region)))

(ert-deftest myemacs-magent-kbd-bind ()
  (skip-unless myemacs-magent-available)
  (should (eq (key-binding (kbd "C-c M m")) 'magent-start)))

(ert-deftest myemacs-magent-skill-dirs ()
  (skip-unless myemacs-magent-available)
  (should magent-skill-directories)
  (should (cl-some (lambda (d) (string-suffix-p "magent/skills" d))
                   magent-skill-directories)))

(ert-deftest myemacs-magent-project-instructions ()
  (skip-unless myemacs-magent-available)
  (should (member "AGENTS.md" magent-project-instruction-file-names)))

(ert-deftest myemacs-magent-agent-shell-config ()
  (skip-unless myemacs-magent-available)
  (magent-agent-shell-ensure-config)
  (should (memq #'magent-agent-shell-make-config agent-shell-agent-configs)))

(ert-deftest myemacs-magent-ai-fallback-kept ()
  (should (eq (key-binding (kbd "C-c I")) '+carlos/gptel-agent-run))
  (should (eq (key-binding (kbd "C-c C-g")) '+carlos/gptel-generate-commit-message)))

(provide 'magent-test)
;;; magent-test.el ends here
```

- **Regras:** `key-binding` resolve minor-mode maps e use-package `:bind` de pacotes deferidos (padrão já documentado). Novos bugs → novo teste (política do AGENTS.md).
- **Confirmações adicionais no `tests/keybindings-test.el`:** manter os testes atuais intactos (nenhum bind existente muda).

### Fase 7 — Validação e rollback (final; depende de todas)

1. **Portão de compilação:** `just compile` — zero warnings (inclui `custom-magent.el`; usar `declare-function` para todos os símbolos do magent).
2. **Portão de docs:** `just checkdoc` OK; `docs/magent-reference.org` criado.
3. **Portão de regressão:** `just test-all` — 54 testes existentes + novos magent, 0 falhas (6 skipped de sempre).
4. **Teste autoritativo:** `just sync` → `emacs --init-directory ~/.config/emacs-vanilla` (primeiro boot instala magent+deps via `:ensure`+`elpaca-wait`); smoke test GUI: `C-c M m` abre `*Magent*`, digitar prompt, ver resposta streaming e permission prompt (ask) para `bash`.
5. **Smoke test de não-regressão GUI:** `C-c i` (gptel), `C-c C-g` (commit IA), `C-c I` (gptel-agent), `C-c A a`/`C-c A o` (eshell CLIs), dirvish/org/dashboard — nada quebrado.
6. **Rollback:** `git revert <commit da migração>` (preserva histórico) ou `git reset --hard 1d7ca9e` (destrói commits seguintes) no repo; remover `(use-package magent ...)`/`(require 'custom-magent)` e `.magent/` se desejado; depois `just sync` no vanilla. As sessões/auditoria do Magent ficam fora do git — não atrapalham o rollback.

### Critérios de aceite (checklist final)

- [x] `just compile` zero warnings + `just checkdoc` OK + `just test-all` verde (54 + novos).
- [x] `M-x magent-start` / `C-c M m` abre `*Magent*` e responde no vanilla (rede: Zen Claude ou MLX local).
- [x] `C-c M m`/`C-c M i`/`C-c M r` sem conflito (coberto por teste).
- [x] Backends gptel 5/5 intactos (`myemacs-ai-backends-registered`), diretivas 42 intactas, commit IA intacto (`myemacs-kbd-ai-commit-global`).
- [x] Skills `.magent/skills/{c-42,cpp-42,python}` e agentes custom `.magent/agent/*.md` carregando (aparecem em `/skills` e na seleção de agente).
- [x] AGENTS.md do repo injetado automaticamente nos prompts (default `magent-project-instruction-file-names = ("AGENTS.md")`) — verificar via `*magent-log*`.
- [x] `docs/magent-reference.org`, TODO.md e roadmap.org atualizados.
- [x] Sessões/auditoria fora do git; rollback documentado e testado (`git revert`).

### Ordem de execução e dependências

```
Fase 0 (decisão) → Fase 1 (instalação) → Fase 2 (custom-magent + binds)
  ├─ Fase 4 (permissões; pode ser junto da Fase 2)
  └─ Fase 6 (testes; após a Fase 2)
Fase 3 (skills/agentes) → Fase 5 (integração/docs) → Fase 7 (validação/rollback)
```

## 0.6. Plano de Ação — Ambiente de Desenvolvimento Vanilla & Fix Dirvish Side (Concluído)

> **Autor:** Agente Arquiteto (planejamento) + Agente Executor (aplicação) + Agente Auditor (validação). **100% APLICADO E VALIDADO.**
> **Suíte ERT:** 89 testes (80 expected, 0 unexpected, 9 skipped). `just compile` zero warnings + checkdoc OK.

### 1. Fix do `dirvish-side` (Navegação e Janela Destino)

**Arquivos alvo:** `lisp/custom-files.el`

**Ação:** O `dirvish-side-open-file-action` precisa garantir que o arquivo não abra em cima da própria sidebar ou de gavetas (ex: vterm, eshell). 

**Trechos de Código (Executor):**
```elisp
;; Em lisp/custom-files.el, definir a função customizada
(defun +carlos/dirvish-side-open-action (file)
  "Abre o FILE na última janela ativa (MRU), ignorando popups, sidebars e minibufer."
  (if-let* ((win (get-mru-window nil nil t)))
      (with-selected-window win
        (find-file file))
    (find-file-other-window file)))

;; Na declaração do dirvish (bloco :custom)
(use-package dirvish
  :ensure t
  :custom
  ;; Configurar action customizada ou `'reuse`
  (dirvish-side-open-file-action #'+carlos/dirvish-side-open-action)
  ;; ...resto do config do dirvish...
  )
```

**Passos:**
1. Definir a função `+carlos/dirvish-side-open-action` em `lisp/custom-files.el`.
2. No bloco `:custom` do `dirvish`, configurar `dirvish-side-open-file-action` para utilizar essa função.
3. **Testes ERT (`tests/dev-env-test.el`)**: `myemacs-dev-dirvish-side-open-action-exists` (verifica se `+carlos/dirvish-side-open-action` é função), `myemacs-dev-dirvish-side-open-action-configured` (verifica se `dirvish-side-open-file-action` está configurado para a função).

### 2. Diagnósticos Inline no Estilo VS Code (Flycheck + Eglot)

**Arquivos alvo:** `lisp/custom-ui.el` (faces) e `lisp/custom-lang.el` (flycheck)

**Ação:** Customizar as faces de erro para usar sublinhado ondulado e exibir erros no fim da linha atual, além de marcadores discretos nas margens.

**Trechos de Código (Executor):**
```elisp
;; Em lisp/custom-ui.el, nas customizações globais de faces:
(custom-set-faces
 '(flycheck-error ((t (:underline (:style wave :color "#ff5555")))))
 '(flycheck-warning ((t (:underline (:style wave :color "#f1fa8c")))))
 '(flycheck-info ((t (:underline (:style wave :color "#8be9fd"))))))

;; Em lisp/custom-lang.el (no bloco do flycheck já existente)
(use-package flycheck
  :ensure t
  :custom
  (flycheck-indication-mode 'left-fringe) ;; Habilitar left-fringe
  :bind (("M-g n" . flycheck-next-error)
         ("M-g p" . flycheck-previous-error)
         ("C-c ! l" . consult-flycheck)))

;; Em lisp/custom-lang.el (novo pacote flycheck-inline)
(use-package flycheck-inline
  :ensure t
  :after flycheck
  :hook (flycheck-mode . flycheck-inline-mode))
```

**Passos:**
1. Inserir `custom-set-faces` em `lisp/custom-ui.el`.
2. Ajustar a declaração `flycheck` em `lisp/custom-lang.el` com as `:custom` e `:bind`.
3. Adicionar pacote `flycheck-inline`.
4. **Testes ERT (`tests/dev-env-test.el`)**: `myemacs-dev-flycheck-wave-faces` (verifica estilo `:underline` nas faces `flycheck-error`/`warning`/`info`), `myemacs-dev-flycheck-inline-mode` (verifica se `flycheck-inline` está disponível e pode ser ativado), `myemacs-dev-flycheck-fringe-mode` (verifica `flycheck-indication-mode`), `myemacs-dev-flycheck-keybindings` (verifica `M-g n`, `M-g p`, `C-c ! l`).

### 3. Popups de Sugestões (Autocomplete) & Documentação (Hover)

**Arquivos alvo:** `lisp/custom-completion.el` e `lisp/custom-lang.el`

**Ação:** Incrementar o Corfu com ícones (`nerd-icons-corfu`) e adicionar o `eldoc-box` para hover de documentação.

**Trechos de Código (Executor):**
```elisp
;; Em lisp/custom-completion.el (logo após a declaração do corfu)
(use-package nerd-icons-corfu
  :ensure t
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))
;; NOTA: Garantir que `corfu-popupinfo-mode` esteja ativo no bloco do corfu.

;; Em lisp/custom-lang.el (novo pacote)
(use-package eldoc-box
  :ensure t
  :hook (eglot-managed-mode . eldoc-box-hover-at-point-mode)
  :bind ("C-c c d" . eldoc-box-help-at-point))
```

**Passos:**
1. Adicionar `nerd-icons-corfu` garantindo o require do `corfu`.
2. Adicionar `eldoc-box` para documentação via hover integrado ao Eglot.
3. **Testes ERT (`tests/dev-env-test.el`)**: `myemacs-dev-corfu-nerd-icons-formatter` (verifica se `nerd-icons-corfu-formatter` está presente em `corfu-margin-formatters`), `myemacs-dev-eldoc-box-commands` (verifica se `eldoc-box-hover-at-point-mode` e `eldoc-box-help-at-point` existem).

### 4. Stacks de Linguagens & Popups Nativos (`display-buffer-alist`)

**Arquivos alvo:** `lisp/custom-lang.el`, `lisp/custom-ui.el` e `tests/dev-env-test.el`

**Ação:** Padronizar as gavetas inferiores de popups no Emacs e usar o Apheleia.

**Trechos de Código (Executor):**
```elisp
;; Em lisp/custom-ui.el (regras centralizadas de display-buffer-alist)
(add-to-list 'display-buffer-alist
             '("\\*\\(compilation\\|eglot events\\|magit.*\\|vterm.*\\|eshell\\|gptel.*\\)\\*"
               (display-buffer-in-direction)
               (direction . bottom)
               (window-height . 0.3)))

;; Em lisp/custom-lang.el (Formatador Apheleia)
(use-package apheleia
  :ensure t
  :config
  (apheleia-global-mode +1)
  ;; Ignorar o C para não conflitar com c_formatter_42
  (add-to-list 'apheleia-inhibit-functions
               (lambda () (derived-mode-p 'c-mode 'c-ts-mode))))
```

**Passos:**
1. Em `lisp/custom-ui.el`, centralizar as regras do `display-buffer-alist`.
2. Em `lisp/custom-lang.el`, inicializar `apheleia-global-mode` evitando o conflito com C.
3. Criar `tests/dev-env-test.el` e registrar em `tests/load-tests.el` com `(require 'dev-env-test)`. Implementar a suíte ERT utilizando `skip-unless` caso os pacotes externos não estejam carregados/disponíveis no ambiente de teste parcial.
4. **Testes ERT (`tests/dev-env-test.el`)**: `myemacs-dev-apheleia-global-mode` (verifica se `apheleia-global-mode` está habilitado), `myemacs-dev-apheleia-inhibit-c-mode` (verifica se a função de inibição para C/C++ retorna `t` em `c-mode`), `myemacs-dev-display-buffer-alist-drawer-rules` (verifica a regra de gavetas inferiores para `compilation`, `vterm`, `eshell`, `magit`, `gptel`).

## 1. Planejamento Corrente (Ações Atuais)

- [x] **Refatoração final do Dirvish (ícones, sidebar e hooks):**
  - Layout oficial de 3 painéis `(1 0.11 0.55)` e atributos `(vc-state subtree-state nerd-icons collapse file-time file-size)`.
  - Corrigir valores inválidos da API 2.3.0: `dirvish-nerd-icons-offset` (`-2` → `0.00`, é `:v-adjust` float), `dirvish-subtree-state-style` (string `"arrow"` → símbolo `'chevron`), `dirvish-subtree-icon-scale-factor` (`1.0` → cons `(0.85 . 0.10)`).
  - Corrigir `dirvish-side-open-file-action` (`'select` inválido → `nil`) e remover `dirvish-side-display-mode-line` (custom inexistente).
  - Substituir hooks inexistentes (`dirvish-mode-hook`, `dirvish-side-mode-hook`) por `dirvish-directory-view-mode-hook` + `dirvish-setup-hook`; `dired-omit-mode` agora aplica de fato em buffers dirvish.
  - Remover `diredfl`; corrigir detecção macOS no dired base (`(featurep :system 'bsd)` nunca era verdadeiro → `(memq system-type '(darwin berkeley-unix))`).
  - Remover `global-display-line-numbers-mode` (números de linha apenas em `prog-mode` via init.el).
  - Zen reading: `line-spacing 0.15` + sem line numbers em org/markdown.
  - Validado com `just check` + `just compile` (zero warnings) + teste no `~/.config/emacs-vanilla`.
- [x] **Ajuste de Truncamento do `dirvish-side`:**
  - Configurar atributos minimalistas (`vc-state`, `nerd-icons`, `collapse`, `subtree-state`) na sidebar para evitar quebra de colunas em 30 de largura.
  - Ocultar a modeline e simplificar o cabeçalho no buffer da sidebar.
  - Sincronizar e validar visualmente no Emacs Vanilla.
- [x] **Ativação das extensões Dirvish (emerge, peek, git-msg):**
  - `git-msg` adicionado a `dirvish-attributes` (só no painel principal; sidebar mantém attrs limpos `(nerd-icons collapse subtree-state)`).
  - `dirvish-emerge-groups` com 6 grupos padrão (`recent-files-2h`, `extensions` de documentos/vídeo/imagens/áudio/arquivos) + toggle `E` → `dirvish-emerge-mode` em `dirvish-mode-map` (verificado: `lookup-key` = `dirvish-emerge-mode`).
  - `dirvish-peek-mode 1` global com `dirvish-peek-key '(list :debounce 0.5 'any)` (preview no minibuffer/vertico com debounce).
  - Validado: `just check` + `just compile` (zero warnings) + batch runtime (atributos/grupos/key/mode corretos). Commit `dbc8a0b`.
- [x] **Habilitar `dirvish-ls` (ls switches on the fly):**
  - `S` → `dirvish-ls-switches-menu` (transient completo: options/toggles/actions) e `s` → `dirvish-quicksort` já existente.
  - Detecção GNU melhorada: `+carlos/gnu-ls-p` checa `ls --version` (GNU coreutils) — o `ls` do Nix no macOS é GNU mas não se chama `gls`; agora o default é `-ahl -v --group-directories-first` em vez do fallback BSD `-ahl`.
  - Testado funcional: quicksort gera `-ahl -v --group-directories-first --sort=size` sem erro de switch. RAG (`docs/dirvish-reference.org`) atualizado com todas as teclas do menu/quicksort.
- [x] **Iteração do dirvish-emerge (validação + navegação + grupos):**
  - **Validação em batch (descobertas):** o buffer principal do dirvish é `dired-mode` com `dirvish-mode-map` (o `dirvish-directory-view-mode`/special-mode é só para buffers auxiliares) — portanto o escopo `dired-mode` do `w` em `.dir-locals.el` **é lido** de volta em buffers dirvish reais; escopo `nil` também funciona. O `w` upstream deixa o buffer `.dir-locals.el` **modificado sem salvar** (Emacs 30.2 não chama `save-buffer` em `modify-dir-local-variable`) — gravar com C-x C-s após `w`. O menu `dirvish-emerge-menu` abre; grupos aplicam (8 overlays com Directories).
  - **Fix de navegação:** `dirvish-emerge-next-group` upstream crasheia (`+ nil 1`) com ponto fora de overlay de grupo (ex.: header). Criados `+carlos/dirvish-emerge-next-group`/`previous-group`/`goto-group` com guard (`ignore-errors` + fallback para `point-min`) e binds `[`/`]` em `dirvish-mode-map` (comentado: `n`/`p` são herdados do dired).
  - **Grupos globais refinados:** novo grupo `Directories` (predicate `directories`) primeiro na ordem — predicados antes de extensões (primeira correspondência vence). Ordem: Directories → Recent files → Documents → Video → Pictures → Audio → Archives.
  - Validado: `just check` + `just compile` (zero warnings) + batch runtime (binds `[`/`]`, guard sem crash em header/grupo/inativo, grupos carregados) + smoke test GUI. Commit `35a2042`.
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

- [x] **Warning "transient loaded before Elpaca activation":** corrida entre a ativação assíncrona da Elpaca e o `:demand t` de `transient` (custom-git.el) — agravado porque `gptel` declara `transient` como Package-Requires (custom-ai carrega antes de custom-git). **Fix:** garantir `transient` cedo no `init.el` com `(use-package transient :ensure t)` + `(elpaca-wait)` (após `use-package-always-defer`), mesmo padrão do `compat`. Com a ativação precoce, o status vira `finished` e `elpaca-continue` (elpaca.el:793) não re-ativa → warn nunca dispara. Validado em batch + cold starts GUI.
- [x] **"Duplicate item ID queued: transient" (erro no boot):** o fix acima duplicou a declaração de `transient` — `init.el:78` + `custom-git.el:15`. Com dois `:ensure t` antes do `after-init-time`, o segundo `elpaca--enqueue` (elpaca.el:842) encontra o item já enfileirado e warn/erra ("Duplicate item ID queued"), que no boot virava `Wrong type argument: elpaca, ((emacs Duplicate item ID queued: transient nil nil))`. **Fix:** remover o bloco `(use-package transient :ensure t :demand t)` de `custom-git.el` — o `init.el` já instala/ativa o transient cedo; `magit` mantém `:after transient` e `transient` é carregado no require. Validado: 3/3 cold starts batch limpos (`transient-loaded=t`, `magit-loaded=nil`, sem duplicado). `just check` + `just compile` (zero warnings).
- [x] **Aplicar gaps do zzamboni (Beautifying Org Mode in Emacs):**
  - Verificado contra https://zzamboni.org/post/beautifying-org-mode-in-emacs/ (via markitdown): seguíamos a maioria; aplicados os gaps em `custom-writing.el` — face `org-indent` herdando `(org-hide fixed-pitch)` (com `with-eval-after-load 'org-indent`, senão o defface sobrescreve), faces `org-property-value`/`org-special-keyword`/`org-verbatim`/`org-document-info` em fixed-pitch, e bullet de lista `-` → `•` via font-lock+compose-region. Não aplicado de propósito: `org-bullets` (temos org-modern) e cores hardcoded (tema ef-themes decide).
  - Validado: batch (faces + bullet composto) + `just check` + `just compile` (zero warnings).
- [x] **`eshell` falha ao abrir — `Symbol's value as variable is void: eshell-mode-map` (e `kmacro-end-and-call-macro: No kbd macro has been defined` no GUI):**
  - **Causa-raiz única (confirmada por backtrace):** o bloco `(with-eval-after-load 'eshell ... (define-key eshell-mode-map ...))` em `custom-term.el:134` rodava quando o `eshell.elc` era carregado, mas no Emacs 30 o `eshell-mode-map` só existe após o `esh-mode` carregar (módulos do eshell carregam lazy) — `(require 'eshell)` NÃO define `eshell-mode-map` (`boundp` = nil; verificado: só `(require 'esh-mode)` o define). O `(defvar eshell-mode-map)` forward-declaration em custom-term.el:19 não liga a variável em runtime (`defvar` sem valor deixa void).
  - **Efeito colateral:** o mesmo erro quebrava o `justl` no `just check` ("Cannot load justl: (void-variable eshell-mode-map)") porque `justl.el:76` faz `(require 'eshell)` → disparava o `with-eval-after-load` prematuro.
  - **Fix:** `with-eval-after-load 'eshell` → `with-eval-after-load 'esh-mode` (mapa é definido em `esh-mode.el`); esh-mode carrega quando `eshell` abre o buffer. Guard do byte-compiler (`(defvar eshell-mode-map)`) mantido.
  - Validado: batch `eshell` abre (`major-mode=eshell-mode`, `map-bound=t`), 3 keys ligadas (`C-c C-q` → `eat-toggle-char-mode`, `C-c A a`/`C-c A o` → runners), `justl` carrega OK, `just check` + `just compile` (zero warnings novos).
- [ ] **Testar config completa em GUI** (não batch) para verificar compilação do `vterm-module`.
- [x] **Org mode monocromático / sem fontes personalizadas (vs Markdown OK):** **Duas causas-raiz empilhadas em `custom-writing.el`:**
  - **(1) `org-modern-replace-stars t` inválido:** nesta versão do org-modern, `org-modern-star` é um símbolo (`'fold`/`'replace`/nil) e `org-modern-replace-stars` é string/lista de strings. Com `t`, o `org-modern-mode` explodia com `(wrong-type-argument sequencep t)` → `mapcar(org-modern--symbol t)` (org-modern.el:858) → `run-hooks` abortava o `org-mode-hook` → **`variable-pitch-mode` e o zen lambda (line-spacing) nunca rodavam** em buffers org. Fix: `org-modern-star 'replace` + `org-modern-replace-stars '("◉" "○" "✸" "✿" "✤" "✜" "◆" "▶")`.
  - **(2) `(add-hook 'org-mode-hook #'variable-pitch-mode)` era no-op no Emacs 30:** `variable-pitch-mode` é um `defalias` para `buffer-face-mode-invoke` (face-remap.el); chamado sem argumento (como hook cru) o bytecode retorna sem fazer nada (`goto-if-nil → return`). Fix: envolver em lambda `(lambda () (variable-pitch-mode 1))`. Markdown "funcionava" porque não usa org-modern (não abortava o hook) e tem `markdown-header-scaling` próprio.
  - Validado em batch: org sem "File mode specification error", `org-modern-mode=t`, remap `(default variable-pitch default)` aplicado, `line-spacing=0.15`, headings fontificados (`org-level-1`, etc.). `just check` + `just compile` (zero warnings).
- [ ] Investigar por que `consult` e `nerd-icons` não foram encontrados no MELPA durante `just check` (Se persistente nas primeiras instalações do usuário).
- [ ] Verificar se pacotes estão em rebuild no MELPA ou se foram removidos/renomeados.

## 3. Planejamento Futuro / Backlog (Ordenado por Dificuldade)

1. [x] **Revisar stack de IA (gptel + gptel-agent)** (Dificuldade: Média — listar o que está implementado, diagnosticar integrações frágeis `superchat`/`mcp`/`gptel-integrations`, alinhar agentes com a política de multiagentes e decidir o estado-alvo)
    - Etapas:
      1. [x] Listar o que está implementado (backends, agentes, gptel-org, personas, display rules) — feito parcialmente, ver resumo da conversa
      2. [x] Diagnosticar gaps e integrações frágeis (`superchat`/`llm.el`, `mcp`, código morto `+carlos/gptel-agent-project-dirs`, `~/.agents/gptel/` vazio)
      3. [x] Decidir estado-alvo e aplicar ajustes (remover código morto, ativar/remover superchat+mcp, definir agentes por projeto)
      4. [ ] **Etapa de teste da stack de IA:** validar em `~/.config/emacs-vanilla` cada entrada — `C-c i` (gptel chat), `C-c I` (+carlos/gptel-agent-run), `C-c C-g` / commit IA, `C-c A a`/`C-c A o` (eshell agy/opencode), gptel-org num `.org`, e troca de backend/modelo no buffer — conferindo erro de API, modelo válido e resposta streaming
2. [ ] **Testar SuperChat com fontes instaladas** (Dificuldade: Muito Baixa - Validação visual)
3. [x] **Substituir o dashboard customizado atual por `dashboard.el`** (Dificuldade: Baixa - Concluído!)
3. [x] **Configurar Victor Mono com ligatures** (Dificuldade: Média/Alta - Concluído!)
4. [x] **Substituir o dashboard customizado atual por `dashboard.el`** (Dificuldade: Baixa - Concluído!)
5. [x] **Configurar Victor Mono com ligatures** (Dificuldade: Média/Alta - Concluído!)
6. [x] **Refinar o dashboard com a tipografia nova instalada** (Dificuldade: Média/Alta - Concluído!)
7. [ ] **Fase 4 — Cutoff (Doom → Vanilla final)** (Dificuldade: Alta - Script `bin/cutoff-migration.sh` pronto, pendente execução pelo usuário)

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

## 6. Plano de Aprimoramento da Sidebar Dirvish (Opus)

### Regra 1: Ocultar entradas especiais e arquivos indesejados
1. **Configurar atributos de exibição:**
   - Configurar `dirvish-attributes` para as views padrão do dired contendo apenas `(nerd-icons file-time file-size collapse)`.
   - Limpar o `dirvish-side-attributes` para ficar mais minimalista, utilizando `(nerd-icons collapse)` ou `(nerd-icons collapse subtree-state)`.
2. **Ocultar dotfiles e temporários:**
   - Habilitar o `dired-omit-mode` nos buffers da sidebar.
   - Configurar a variável `dired-omit-files` com um regex abrangente para combinar com dotfiles (`^\\..*`), arquivos de backup (`~+$` ou `\\~+$`) e marcações indesejadas (`^#.*#$`).
3. **Ocultar diretórios `.` e `..`:**
   - Incluir os diretórios corrente e pai (`^\\.$` e `^\\.\\.$`) no regex do `dired-omit-files` ou configurar uma variável nativa do Dirvish que lide com isso se aplicável.

### Regra 2: Desativar números de linha na Sidebar e Dired
1. **Hooks de Modo:**
   - Desabilitar a exibição de linhas (`display-line-numbers-mode -1`) de maneira explícita dentro dos buffers.
   - Adicionar essa configuração em `dired-mode-hook` ou no mais específico `dirvish-directory-view-mode-hook`.

### Regra 3: Ajustar Estilo do Buffer e Largura
1. **Configurar a Largura da Sidebar:**
   - Definir `dirvish-side-width` para um tamanho confortável, como `30` ou `35`.
2. **Limpar Interface Visual (Cabeçalho e Rodapé):**
   - Configurar `dirvish-side-header-line-format` como `nil`.
   - Configurar `dirvish-side-mode-line-format` como `nil`.
3. **Ocultar Cursor da Sidebar:**
   - Configurar `dirvish-hide-cursor` para `t`, resultando em um visual mais próximo a uma "árvore de arquivos" (file tree) típica.

## 0.7. Plano de Ação — Integração Makefile Executor (semelhante ao Justl)

> **Autor:** Agente Planejador/Arquiteto (modelo Pro/Opus). Plano EXECUTÁVEL para o Agente Executor (aplicar) e para o Agente Auditor (validar). **NÃO foi aplicado nada ainda.**

### 1. Instalação e Configuração do `makefile-executor`

**Arquivos alvo:** `lisp/custom-lang.el`

**Ação:** Instalar `makefile-executor` via Elpaca, ativar no modo Makefile e configurar os atalhos globais (como solicitado).

**Trechos de Código (Executor):**
```elisp
;; Adicionar em lisp/custom-lang.el

(declare-function makefile-executor-execute-project-target "makefile-executor")
(declare-function makefile-executor-execute-last "makefile-executor")

(use-package makefile-executor
  :ensure t
  :hook (makefile-mode . makefile-executor-mode)
  :bind (("C-c m" . makefile-executor-execute-project-target)
         ("C-c M" . makefile-executor-execute-last)))
```

**Passos:**
1. Adicionar as forward declarations `declare-function` para `makefile-executor-execute-project-target` e `makefile-executor-execute-last` para evitar avisos no byte-compiler.
2. Adicionar o pacote `makefile-executor` em `lisp/custom-lang.el` com `:ensure t`.
3. Ativar `makefile-executor-mode` via hook em `makefile-mode-hook`.
4. Atribuir os keybindings globais: `C-c m` e `C-c M`.

### 2. Testes ERT (`tests/dev-env-test.el`)

**Arquivos alvo:** `tests/dev-env-test.el`

**Ação:** Criar testes para validar a existência dos comandos e keybindings, conforme a política de regressão (Quality Gates) de `AGENTS.md`.

**Trechos de Código (Executor):**
```elisp
;; Adicionar em tests/dev-env-test.el

(defvar myemacs-dev-makefile-executor-available
  (condition-case nil (require 'makefile-executor) (error nil))
  "Non-nil quando o pacote makefile-executor carrega neste ambiente.")

(ert-deftest myemacs-dev-makefile-executor-commands ()
  (skip-unless myemacs-dev-makefile-executor-available)
  (should (commandp 'makefile-executor-execute-project-target))
  (should (commandp 'makefile-executor-execute-last)))

(ert-deftest myemacs-dev-makefile-executor-keybindings ()
  (skip-unless myemacs-dev-makefile-executor-available)
  (should (eq (key-binding (kbd "C-c m")) 'makefile-executor-execute-project-target))
  (should (eq (key-binding (kbd "C-c M")) 'makefile-executor-execute-last)))
```

**Passos:**
1. Adicionar o teste `myemacs-dev-makefile-executor-commands`.
2. Adicionar o teste `myemacs-dev-makefile-executor-keybindings`.
3. Após aplicar, garantir execução dos testes, `just compile` para check de warnings (zero admitidos), e `just checkdoc`.

## 0.8. Plano de Ação — Visualização Avançada de Código (indent-bars + rainbow-delimiters + hl-line + whitespace-mode)

> **Autor:** Agente Planejador/Arquiteto (modelo Pro/Opus). Plano EXECUTÁVEL para o Agente Executor (aplicar) e para o Agente Auditor (validar). **NÃO foi aplicado nada ainda.**

### 1. `indent-bars` (Guias de Indentação Modernas com Tree-Sitter)

**Arquivos alvo:** `lisp/custom-ui.el`

**Ação:** Configurar `indent-bars` para exibir guias de indentação elegantes com suporte a Tree-Sitter e destaque baseado na profundidade.

**Trechos de Código (Executor):**
```elisp
;; Adicionar em lisp/custom-ui.el (após as declarações iniciais)
(declare-function indent-bars-mode "indent-bars")

(use-package indent-bars
  :ensure t
  :hook (prog-mode . indent-bars-mode)
  :custom
  (indent-bars-treesitter-support t)
  (indent-bars-width 0.2)
  (indent-bars-pad 0.1)
  (indent-bars-color-by-depth '(:regexp "outline-\\([0-9]+\\)" :blend 1)))
```

### 2. `rainbow-delimiters` (Colorização de Parênteses e Aninhamento)

**Arquivos alvo:** `lisp/custom-ui.el`

**Ação:** Colorizar parênteses, chaves e colchetes aninhados.

**Trechos de Código (Executor):**
```elisp
;; Adicionar em lisp/custom-ui.el
(declare-function rainbow-delimiters-mode "rainbow-delimiters")

(use-package rainbow-delimiters
  :ensure t
  :hook (prog-mode . rainbow-delimiters-mode))
```

### 3. `hl-line-mode` (Destaque da Linha Atual Nativo) e 4. `whitespace-mode` Sutil

**Arquivos alvo:** `lisp/custom-ui.el`

**Ação:** Destacar a linha onde o cursor está e exibir espaços/tabs de maneira não poluente no final das linhas.

**Trechos de Código (Executor):**
```elisp
;; Adicionar em lisp/custom-ui.el
(declare-function hl-line-mode "hl-line")
(declare-function whitespace-mode "whitespace")

(use-package hl-line
  :ensure nil
  :hook (prog-mode . hl-line-mode))

(use-package whitespace
  :ensure nil
  :hook (prog-mode . whitespace-mode)
  :custom
  (whitespace-style '(face trailing tabs tab-mark)))
```

### 5. Suíte ERT (`tests/dev-env-test.el`)

**Arquivos alvo:** `tests/dev-env-test.el`

**Ação:** Adicionar os testes garantindo a disponibilidade das funcionalidades visuais no ambiente de testes batch.

**Trechos de Código (Executor):**
```elisp
;; Adicionar em tests/dev-env-test.el

(defvar myemacs-dev-indent-bars-available
  (condition-case nil (require 'indent-bars) (error nil))
  "Non-nil quando indent-bars está disponível.")

(ert-deftest myemacs-dev-indent-bars-available ()
  (skip-unless myemacs-dev-indent-bars-available)
  (should (featurep 'indent-bars)))

(defvar myemacs-dev-rainbow-delimiters-available
  (condition-case nil (require 'rainbow-delimiters) (error nil))
  "Non-nil quando rainbow-delimiters está disponível.")

(ert-deftest myemacs-dev-rainbow-delimiters-available ()
  (skip-unless myemacs-dev-rainbow-delimiters-available)
  (should (featurep 'rainbow-delimiters)))

(ert-deftest myemacs-dev-hl-line-in-prog-mode ()
  "Verifica se hl-line-mode está no prog-mode-hook."
  (should (memq 'hl-line-mode prog-mode-hook)))

(ert-deftest myemacs-dev-whitespace-prog-mode ()
  "Verifica se whitespace-mode está no prog-mode-hook e o style correto."
  (should (memq 'whitespace-mode prog-mode-hook))
  (should (equal whitespace-style '(face trailing tabs tab-mark))))
```
## Plan: Fix `myemacs-ai-host-detection` test failure

- **Goal:** Ensure the test passes by using symbols for model identifiers.
- **Steps:**
  1. Open `lisp/custom-ai.el` and change the definition of `+carlos/gptel-quick-local-model` from a string to a symbol:
     ```elisp
     (defvar +carlos/gptel-quick-local-model 'qwen2.5-coder:3b
       "Modelo usado para tarefas locais rápidas como docstrings e testes.")
     ```
  2. Ensure `+carlos/gptel-quick-local-backend` is also a symbol if used in comparisons.
  3. In `+carlos/gptel-setup-defaults-by-host` (function defined later in the file), replace any `setq` that assigns a string to `gptel-model` with a quoted symbol, e.g.:
     ```elisp
     (setq gptel-model 'qwen2.5-coder:3b)
     ```
  4. Run the full test suite:
     ```bash
     just test-all
     ```
     Verify that `myemacs-ai-host-detection` now passes.
  5. Run `just compile` and `just checkdoc` to confirm no new warnings.
  6. Commit and push:
     ```bash
     git add lisp/custom-ai.el TODO.md tests/ai-test.el
     git commit -m "fix(ai): use symbols for model identifiers in host detection"
     git push
     ```
  7. Sync to the official Emacs config and run a quick sanity check:
     ```bash
     just sync
     just run
     ```

*Status:* Planned – awaiting execution.
