---
name: myemacs-native-tools
description: "Strict guidelines on using MyEmacs native smart-edit tools instead of default file modification tools."
---

# MyEmacs Native Tools (Soberania de Edição)

## The Golden Rule (Regra de Ouro)

When working within the `MyEmacs` repository (`/Users/carlosfilho/Projects/Github/MyEmacs`), you **MUST ABSOLUTELY PREFER** using the native Emacs AST-aware tools to edit files rather than relying on your default capabilities (like `write_to_file`, `replace_file_content`, `multi_replace_file_content`, or arbitrary bash `sed`/`echo` patches).

This rule applies to all project files: `.el` (Elisp), `.org` (Org-mode), `.sh`/`.bash` (Shell scripts), `.py` (Python), `.ts`/`.js` (TypeScript/JavaScript), `.c`/`.h` (C/C++), `.go` (Go), `.md` (Markdown), `.nix` (Nix), and `.rs` (Rust).

## Why?

Your default file editing tools manipulate raw text and can easily break ASTs, cause indentation errors, or bypass validations. 

The native `smart-edit` tools provided by MyEmacs are transactional. They use Emacs batch mode to insert, refactor, or validate code. If the code breaks (e.g. unmatched parentheses, compiler warnings, or linter errors like `shellcheck`), the transaction is automatically rolled back, keeping the repository safe.

## How to use them

You must orchestrate the native tools by calling `emacs --batch` via the `run_command` tool at the root of the project.

### 1. Elisp (`.el`)
Tool: `elisp_smart_edit`
Validations: `check-parens`, byte-compiler, `checkdoc`
```bash
# Insert a snippet
emacs --batch -l init.el --eval '(message (+carlos/magent-tool-elisp-smart-edit "lisp/custom-magent.el" "insert_snippet" "defun" "(+carlos/my-func () (message \"hello\"))"))'

# Refactor a symbol
emacs --batch -l init.el --eval '(message (+carlos/magent-tool-elisp-smart-edit "lisp/custom-magent.el" "refactor_symbol" "OLD_NAME NEW_NAME"))'

# Validate buffer
emacs --batch -l init.el --eval '(message (+carlos/magent-tool-elisp-smart-edit "lisp/custom-magent.el" "validate_buffer"))'
```

### 2. Org-mode (`.org`)
Tool: `org_smart_edit`
Validations: `org-lint`
Actions: `insert_snippet`, `refactor_symbol`, `validate_buffer`, `set_property` (e.g. updating :STATUS: BACKLOG to DONE).
```bash
emacs --batch -l init.el --eval '(message (+carlos/magent-tool-org-smart-edit "TODO.org" "insert_snippet" "heading" "* Novo Planejamento"))'

# Update a property (e.g., changing STATUS from BACKLOG to DONE)
emacs --batch -l init.el --eval '(message (+carlos/magent-tool-org-smart-edit "TODO.org" "set_property" "heading_name_or_regex" "STATUS" "DONE"))'
```

### 3. Shell Scripts (`.sh`, `.bash`)
Tool: `sh_smart_edit`
Validations: `shellcheck`
Snippets: `script_header`, `function`, `parse_args`, `if_statement`, `case_statement`
```bash
emacs --batch -l init.el --eval '(message (+carlos/magent-tool-sh-smart-edit "bin/my-script.sh" "insert_snippet" "script_header" "#!/bin/bash\nset -e"))'
```

### Other Languages
- Python: `python_smart_edit` (ruff/black/py-compile)
- TypeScript: `ts_smart_edit` (prettier/eslint)
- C/C++: `c_smart_edit` (Norminette 42)
- Go: `go_smart_edit` (gofmt/gopls)
- Nix: `nix_smart_edit` (nixfmt/statix)
- Markdown: `markdown_smart_edit` (markdownlint/markitdown)
- Rust: `rust_smart_edit` (rustfmt/cargo)

## 4. Advanced Native Tools (Omniscience & DevOps)

MyEmacs provides advanced introspection and testing tools. You should prefer these over standard bash commands like `grep`, `find`, or invoking `pytest`/`ert` manually.

- **AST Search (`magent-tool-treesit-query`)**: Uses Tree-sitter for structural code queries (functions, classes) saving thousands of tokens compared to `view_file`.
```bash
emacs --batch -l init.el --eval '(require '\''custom-magent-tools)' --eval '(message (+carlos/magent-tool-treesit-query "python" "(function_definition name: (identifier) @name)" "path/to/file.py"))'
```

- **Test Runner (`magent-tool-ert-runner`)**: Runs ERT tests isolated and captures smart stack traces upon failure.
```bash
emacs --batch -l init.el --eval '(require '\''custom-magent-tools)' --eval '(message (+carlos/magent-tool-ert-runner "my-test-selector"))'
```

- **Package Manager (`magent-tool-elpaca`)**: Manages and queries Elpaca dependencies.
```bash
emacs --batch -l init.el --eval '(require '\''custom-magent-tools)' --eval '(message (+carlos/magent-tool-elpaca "status" "magit"))'
```

## Exceptions
- If you are creating a temporary, "throwaway" script outside the project scope (e.g., in `/tmp/`), you may use your standard `write_to_file` tool to save tokens and time. 
- However, if the user explicitly asks you to be rigorous even with temporary files, use `sh_smart_edit` to initialize them.
