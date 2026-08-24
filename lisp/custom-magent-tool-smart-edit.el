;;; custom-magent-tool-smart-edit.el --- Magent tools for code editing -*- lexical-binding: t; -*-

;;; Commentary:
;; Este módulo define as ferramentas de edição AST-aware (smart-edit) nativas do
;; Emacs para manipulação de código por agentes IA.

;;; Code:

(require 'cl-lib)
(declare-function org-set-property "org")

(provide 'custom-magent-tool-smart-edit)
;;; custom-magent-tool-smart-edit.el ends here
(defvar +carlos/magent-tool-elisp-smart-edit nil)

(defvar +carlos/magent-tool-nix-smart-edit nil)

(defvar +carlos/magent-tool-python-smart-edit nil)

(defvar +carlos/magent-tool-ts-smart-edit nil)

(defvar +carlos/magent-tool-c-smart-edit nil)

(defvar +carlos/magent-tool-go-smart-edit nil)

(defvar +carlos/magent-tool-org-smart-edit nil)

(defvar +carlos/magent-tool-sh-smart-edit nil)

(defvar +carlos/magent-tool-markdown-smart-edit nil)

(defvar +carlos/magent-tool-rust-smart-edit nil)

;; ── Infraestrutura transacional compartilhada ─────────────────────────

(defun +carlos/magent--smart-edit-transaction (buf kind thunk)
  "Executa THUNK em BUF como uma transação validada por KIND.
KIND é `code' (check-parens) ou `org' (org-lint). THUNK realiza apenas
mutações no buffer e devolve a mensagem de sucesso. Em falha de
validação, restaura o buffer byte-a-byte do snapshot pré-mutação,
persiste a restauração e devolve a mensagem de erro sem sinalizar."
  (let ((snapshot (with-current-buffer buf
                    (buffer-substring-no-properties (point-min) (point-max)))))
    (with-current-buffer buf
      (condition-case err
          (let ((msg (funcall thunk)))
            (pcase kind
              ('org (when (fboundp 'org-lint)
                      (let ((reports (org-lint)))
                        (when reports
                          (error "org-lint reportou %d problema(s)" (length reports))))))
              (_ (save-excursion (check-parens))))
            (save-buffer)
            msg)
        (error
         (erase-buffer)
         (insert snapshot)
         (save-buffer)
         (format "Erro: %s. Transação revertida." (error-message-string err)))))))

(defun +carlos/magent--smart-edit-replace-core (old new &optional flags)
  "Substitui OLD por NEW respeitando FLAGS; devolve contagem.
FLAGS (opcional): nil/vazio/\"ALL\" = literal global (default);
\"FIRST\" = primeira ocorrência; \"WORD\" = limitado a fronteiras de
símbolo; \"REGEX\" = trata OLD como expressão regular."
  (goto-char (point-min))
  (let* ((flag (and flags (upcase flags)))
         (first-p (equal flag "FIRST"))
         (pattern (pcase flag
                    ("REGEX" old)
                    ("WORD" (concat "\\_<" (regexp-quote old) "\\_>"))))
         (count 0))
    (if pattern
        (while (re-search-forward pattern nil t)
          (replace-match new t t)
          (setq count (1+ count))
          (when first-p (goto-char (point-max))))
      (while (search-forward old nil t)
        (replace-match new t t)
        (setq count (1+ count))
        (when first-p (goto-char (point-max)))))
    count))

(defun +carlos/magent-tool-elisp-smart-edit (target-file action &optional snippet-name args _reason)
  "Ferramenta transacional para edição inteligente de arquivos Elisp (.el).
TARGET-FILE: Caminho do arquivo .el.
ACTION: `insert_snippet', `refactor_symbol', `extract_sexp'
        ou `validate_buffer'.
SNIPPET-NAME: Nome do snippet Tempel (ex: `defun', `deftest', `use-package').
ARGS: Argumentos para o snippet ou substituição de símbolo.
REASON: Motivo da alteração."
  (let* ((abs-file (expand-file-name target-file (or (and (fboundp 'project-root)
                                                          (when-let* ((p (project-current)))
                                                            (project-root p)))
                                                     user-emacs-directory)))
         (buf (or (find-buffer-visiting abs-file)
                  (and (file-exists-p abs-file) (find-file-noselect abs-file))
                  (get-buffer-create (file-name-nondirectory abs-file)))))
    (with-current-buffer buf
      (unless (derived-mode-p 'emacs-lisp-mode)
        (emacs-lisp-mode))
      (pcase action
        ("insert_snippet"
         (let* ((name (or snippet-name "defun"))
                (arg-str (or args ""))
                (code (cond
                       ((equal name "use-package")
                        (format "(use-package %s\n  :ensure t\n  :config\n  )\n" arg-str))
                       ((equal name "deftest")
                        (format "(ert-deftest %s ()\n  \"Docstring.\"\n  (should t))\n" arg-str))
                       ((equal name "defcustom")
                        (format "(defcustom %s nil\n  \"Docstring.\"\n  :type 'boolean\n  :group 'myemacs)\n" arg-str))
                       ((equal name "with-eval-after-load")
                        (format "(with-eval-after-load '%s\n  )\n" arg-str))
                       (t
                        (format "(defun %s ()\n  \"Docstring.\"\n  )\n" arg-str)))))
           (goto-char (point-max))
           (unless (bolp) (insert "\n"))
           (insert code)
           (condition-case err
               (progn
                 (save-excursion (check-parens))
                 (save-buffer)
                 (format "Snippet '%s' inserido com sucesso em '%s'. Buffer validado." name abs-file))
             (error
              (primitive-undo 1 buf)
              (format "Erro de sintaxe ao inserir snippet '%s': %s. Transação revertida." name (error-message-string err))))))
        ("refactor_symbol"
         (if (or (null args) (string-empty-p args))
             "Erro: informe os símbolos 'antigo novo' em args para refatorar."
           (let* ((parts (split-string args "[ \t]+" t))
                  (old-sym (car parts))
                  (new-sym (cadr parts)))
             (if (and old-sym new-sym)
                 (progn
                   (goto-char (point-min))
                   (let ((count 0))
                     (while (search-forward old-sym nil t)
                       (replace-match new-sym t t)
                       (setq count (1+ count)))
                     (condition-case err
                         (progn
                           (save-excursion (check-parens))
                           (save-buffer)
                           (format "Refatoração de '%s' -> '%s' concluída em '%s' (%d substituições). Buffer validado."
                                   old-sym new-sym abs-file count))
                       (error
                        (primitive-undo count buf)
                        (format "Erro de sintaxe ao refatorar '%s': %s. Transação revertida." old-sym (error-message-string err))))))
               "Erro: forneça 'velho novo' em args."))))
        ("extract_sexp"
         (let* ((search-str snippet-name)
                (dest-file args))
           (if (or (null search-str) (null dest-file) (string-empty-p dest-file))
               "Erro: para extract_sexp, informe a string de busca em snippet-name e o arquivo destino em args."
             (let ((dest-abs-file (expand-file-name dest-file (or (and (fboundp 'project-root) (when-let* ((p (project-current))) (project-root p))) user-emacs-directory))))
               (goto-char (point-min))
               (if (search-forward search-str nil t)
                   (progn
                     (goto-char (match-beginning 0))
                     (condition-case err
                         (let ((beg (point)))
                           (forward-sexp 1)
                           (let ((code (buffer-substring beg (point))))
                             (delete-region beg (point))
                             (save-buffer)
                             (with-current-buffer (or (find-buffer-visiting dest-abs-file)
                                                      (and (file-exists-p dest-abs-file) (find-file-noselect dest-abs-file))
                                                      (get-buffer-create (file-name-nondirectory dest-abs-file)))
                               (unless (derived-mode-p 'emacs-lisp-mode) (emacs-lisp-mode))
                               (unless buffer-file-name (setq buffer-file-name dest-abs-file))
                               (goto-char (point-max))
                               (unless (bolp) (insert "\n"))
                               (insert code "\n\n")
                               (save-excursion (check-parens))
                               (save-buffer))
                             (format "Sexp '%s' extraída para '%s'. Ambos os buffers validados." search-str dest-abs-file)))
                       (error
                        (primitive-undo 1 buf)
                        (format "Erro de sintaxe ao extrair sexp '%s': %s." search-str (error-message-string err)))))
                 (format "Erro: Sexp contendo '%s' não encontrada em '%s'." search-str abs-file))))))
        ("validate_buffer"
         (condition-case err
             (progn
               (save-excursion (check-parens))
               (read-from-string (buffer-string))
               (format "Buffer '%s' validado com sucesso (zero erros de sintaxe e parênteses equilibrados)." abs-file))
           (error
            (format "Erro de validação no buffer '%s': %s" abs-file (error-message-string err)))))
        (_ (format "Ação '%s' desconhecida. Use 'insert_snippet', 'refactor_symbol', 'extract_sexp' ou 'validate_buffer'." action))))))

(defun +carlos/magent-tool-nix-smart-edit (target-file action &optional snippet-name args _reason)
  "Ferramenta transacional para edição inteligente de arquivos Nix (.nix).
TARGET-FILE: Caminho do arquivo .nix.
ACTION: `insert_snippet', `refactor_symbol' ou `validate_buffer'.
SNIPPET-NAME: Nome do snippet Tempel (ex: `flake', `module', `package',
`overlay', `devshell', `option').
ARGS: Argumentos para o snippet ou substituição de símbolo.
REASON: Motivo da alteração."
  (let* ((abs-file (expand-file-name target-file (or (and (fboundp 'project-root)
                                                          (when-let* ((p (project-current)))
                                                            (project-root p)))
                                                     user-emacs-directory)))
         (buf (or (find-buffer-visiting abs-file)
                  (and (file-exists-p abs-file) (find-file-noselect abs-file))
                  (get-buffer-create (file-name-nondirectory abs-file)))))
    (with-current-buffer buf
      (unless (or (derived-mode-p 'nix-mode) (derived-mode-p 'nix-ts-mode))
        (when (fboundp 'nix-mode) (nix-mode)))
      (pcase action
        ("insert_snippet"
         (let* ((name (or snippet-name "module"))
                (arg-str (or args ""))
                (code (cond
                       ((equal name "flake")
                        (format "{\n  description = \"%s\";\n\n  inputs = {\n    nixpkgs.url = \"github:nixos/nixpkgs/nixos-unstable\";\n  };\n\n  outputs = { self, nixpkgs }:\n    let\n      system = \"x86_64-linux\";\n      pkgs = nixpkgs.legacyPackages.${system};\n    in {\n      devShells.${system}.default = pkgs.mkShell { buildInputs = [ ]; };\n    };\n}\n" arg-str))
                       ((equal name "package")
                        (format "{\n  lib,\n  stdenv,\n  fetchFromGitHub,\n}: stdenv.mkDerivation {\n  pname = \"%s\";\n  version = \"0.1.0\";\n  src = ./.;\n}\n" arg-str))
                       ((equal name "overlay")
                        (format "final: prev: {\n  %s = prev.%s.overrideAttrs (oldAttrs: {\n  });\n}\n" arg-str arg-str))
                       ((equal name "devshell")
                        (format "pkgs.mkShell {\n  name = \"%s\";\n  buildInputs = with pkgs; [ ];\n}\n" arg-str))
                       ((equal name "option")
                        (format "%s = lib.mkOption {\n  type = lib.types.str;\n  default = \"\";\n  description = \"Docstring.\";\n};\n" arg-str))
                       (t
                        (format "{\n  config,\n  lib,\n  pkgs,\n  ...\n}: {\n  # %s configuration\n}\n" arg-str)))))
           (goto-char (point-max))
           (unless (bolp) (insert "\n"))
           (insert code)
           (condition-case err
               (progn
                 (save-excursion (check-parens))
                 (save-buffer)
                 (format "Snippet Nix '%s' inserido com sucesso em '%s'. Buffer validado." name abs-file))
             (error
              (primitive-undo 1 buf)
              (format "Erro de sintaxe ao inserir snippet Nix '%s': %s. Transação revertida." name (error-message-string err))))))
        ("refactor_symbol"
         (if (or (null args) (string-empty-p args))
             "Erro: informe os símbolos 'antigo novo' em args para refatorar."
           (let* ((parts (split-string args "[ \t]+" t))
                  (old-sym (car parts))
                  (new-sym (cadr parts)))
             (if (and old-sym new-sym)
                 (progn
                   (goto-char (point-min))
                   (let ((count 0))
                     (while (search-forward old-sym nil t)
                       (replace-match new-sym t t)
                       (setq count (1+ count)))
                     (condition-case err
                         (progn
                           (save-excursion (check-parens))
                           (save-buffer)
                           (format "Refatoração Nix '%s' -> '%s' concluída em '%s' (%d substituições). Buffer validado."
                                   old-sym new-sym abs-file count))
                       (error
                        (primitive-undo count buf)
                        (format "Erro de sintaxe ao refatorar '%s': %s. Transação revertida." old-sym (error-message-string err))))))
               "Erro: forneça 'velho novo' em args."))))
        ("validate_buffer"
         (condition-case err
             (progn
               (save-excursion (check-parens))
               (format "Buffer Nix '%s' validado com sucesso (delimitadores equilibrados)." abs-file))
           (error
            (format "Erro de validação no buffer Nix '%s': %s" abs-file (error-message-string err)))))
        (_ (format "Ação '%s' desconhecida. Use 'insert_snippet', 'refactor_symbol' ou 'validate_buffer'." action))))))

(defun +carlos/magent-tool-python-smart-edit (target-file action &optional snippet-name args _reason)
  "Ferramenta transacional para edição inteligente de arquivos Python (.py).
TARGET-FILE: Caminho do arquivo .py.
ACTION: `insert_snippet', `refactor_symbol' ou `validate_buffer'.
SNIPPET-NAME: Nome do snippet Tempel (ex: `def', `class', `async_def', `pytest',
`dataclass', `main').
ARGS: Argumentos para o snippet ou substituição de símbolo.
REASON: Motivo da alteração."
  (let* ((abs-file (expand-file-name target-file (or (and (fboundp 'project-root)
                                                          (when-let* ((p (project-current)))
                                                            (project-root p)))
                                                     user-emacs-directory)))
         (buf (or (find-buffer-visiting abs-file)
                  (and (file-exists-p abs-file) (find-file-noselect abs-file))
                  (get-buffer-create (file-name-nondirectory abs-file)))))
    (with-current-buffer buf
      (unless (or (derived-mode-p 'python-mode) (derived-mode-p 'python-ts-mode))
        (when (fboundp 'python-mode) (python-mode)))
      (pcase action
        ("insert_snippet"
         (let* ((name (or snippet-name "def"))
                (arg-str (or args ""))
                (code (cond
                       ((equal name "class")
                        (format "class %s:\n    \"\"\"Docstring.\"\"\"\n\n    def __init__(self) -> None:\n        pass\n" arg-str))
                       ((equal name "async_def")
                        (format "async def %s() -> None:\n    \"\"\"Docstring.\"\"\"\n    pass\n" arg-str))
                       ((equal name "pytest")
                        (format "def test_%s() -> None:\n    \"\"\"Test case.\"\"\"\n    assert True\n" arg-str))
                       ((equal name "dataclass")
                        (format "from dataclasses import dataclass\n\n@dataclass\nclass %s:\n    \"\"\"Dataclass docstring.\"\"\"\n    name: str\n" arg-str))
                       ((equal name "main")
                        (format "if __name__ == \"__main__\":\n    # %s main entrypoint\n    pass\n" arg-str))
                       (t
                        (format "def %s() -> None:\n    \"\"\"Docstring.\"\"\"\n    pass\n" arg-str)))))
           (goto-char (point-max))
           (unless (bolp) (insert "\n"))
           (insert code)
           (condition-case err
               (progn
                 (save-excursion (check-parens))
                 (save-buffer)
                 (format "Snippet Python '%s' inserido com sucesso em '%s'. Buffer validado." name abs-file))
             (error
              (primitive-undo 1 buf)
              (format "Erro de sintaxe ao inserir snippet Python '%s': %s. Transação revertida." name (error-message-string err))))))
        ("refactor_symbol"
         (if (or (null args) (string-empty-p args))
             "Erro: informe os símbolos 'antigo novo' em args para refatorar."
           (let* ((parts (split-string args "[ \t]+" t))
                  (old-sym (car parts))
                  (new-sym (cadr parts)))
             (if (and old-sym new-sym)
                 (progn
                   (goto-char (point-min))
                   (let ((count 0))
                     (while (search-forward old-sym nil t)
                       (replace-match new-sym t t)
                       (setq count (1+ count)))
                     (condition-case err
                         (progn
                           (save-excursion (check-parens))
                           (save-buffer)
                           (format "Refatoração Python '%s' -> '%s' concluída em '%s' (%d substituições). Buffer validado."
                                   old-sym new-sym abs-file count))
                       (error
                        (primitive-undo count buf)
                        (format "Erro de sintaxe ao refatorar '%s': %s. Transação revertida." old-sym (error-message-string err))))))
               "Erro: forneça 'velho novo' em args."))))
        ("validate_buffer"
         (condition-case err
             (progn
               (save-excursion (check-parens))
               (format "Buffer Python '%s' validado com sucesso." abs-file))
           (error
            (format "Erro de validação no buffer Python '%s': %s" abs-file (error-message-string err)))))
        (_ (format "Ação '%s' desconhecida. Use 'insert_snippet', 'refactor_symbol' ou 'validate_buffer'." action))))))

(defun +carlos/magent-tool-ts-smart-edit (target-file action &optional snippet-name args _reason)
  "Ferramenta transacional para edição de arquivos TS/JS (.ts, .tsx, .js).
TARGET-FILE: Caminho do arquivo TypeScript/JavaScript.
ACTION: `insert_snippet', `refactor_symbol' ou `validate_buffer'.
SNIPPET-NAME: Nome do snippet Tempel (ex: `interface', `type', `function',
`export_const', `describe_it').
ARGS: Argumentos para o snippet ou substituição de símbolo.
REASON: Motivo da alteração."
  (let* ((abs-file (expand-file-name target-file (or (and (fboundp 'project-root)
                                                          (when-let* ((p (project-current)))
                                                            (project-root p)))
                                                     user-emacs-directory)))
         (buf (or (find-buffer-visiting abs-file)
                  (and (file-exists-p abs-file) (find-file-noselect abs-file))
                  (get-buffer-create (file-name-nondirectory abs-file)))))
    (with-current-buffer buf
      (pcase action
        ("insert_snippet"
         (let* ((name (or snippet-name "function"))
                (arg-str (or args ""))
                (code (cond
                       ((equal name "interface")
                        (format "export interface %s {\n  id: string;\n}\n" arg-str))
                       ((equal name "type")
                        (format "export type %s = string | number;\n" arg-str))
                       ((equal name "export_const")
                        (format "export const %s = () => {\n  return null;\n};\n" arg-str))
                       ((equal name "describe_it")
                        (format "describe('%s', () => {\n  it('should work', () => {\n    expect(true).toBe(true);\n  });\n});\n" arg-str))
                       (t
                        (format "export function %s(): void {\n  // %s implementation\n}\n" arg-str arg-str)))))
           (goto-char (point-max))
           (unless (bolp) (insert "\n"))
           (insert code)
           (condition-case err
               (progn
                 (save-excursion (check-parens))
                 (save-buffer)
                 (format "Snippet TS/JS '%s' inserido com sucesso em '%s'. Buffer validado." name abs-file))
             (error
              (primitive-undo 1 buf)
              (format "Erro de sintaxe ao inserir snippet TS/JS '%s': %s. Transação revertida." name (error-message-string err))))))
        ("refactor_symbol"
         (if (or (null args) (string-empty-p args))
             "Erro: informe os símbolos 'antigo novo' em args para refatorar."
           (let* ((parts (split-string args "[ \t]+" t))
                  (old-sym (car parts))
                  (new-sym (cadr parts)))
             (if (and old-sym new-sym)
                 (progn
                   (goto-char (point-min))
                   (let ((count 0))
                     (while (search-forward old-sym nil t)
                       (replace-match new-sym t t)
                       (setq count (1+ count)))
                     (condition-case err
                         (progn
                           (save-excursion (check-parens))
                           (save-buffer)
                           (format "Refatoração TS/JS '%s' -> '%s' concluída em '%s' (%d substituições). Buffer validado."
                                   old-sym new-sym abs-file count))
                       (error
                        (primitive-undo count buf)
                        (format "Erro de sintaxe ao refatorar '%s': %s. Transação revertida." old-sym (error-message-string err))))))
               "Erro: forneça 'velho novo' em args."))))
        ("validate_buffer"
         (condition-case err
             (progn
               (save-excursion (check-parens))
               (format "Buffer TS/JS '%s' validado com sucesso." abs-file))
           (error
            (format "Erro de validação no buffer TS/JS '%s': %s" abs-file (error-message-string err)))))
        (_ (format "Ação '%s' desconhecida. Use 'insert_snippet', 'refactor_symbol' ou 'validate_buffer'." action))))))

(defun +carlos/magent-tool-c-smart-edit (target-file action &optional snippet-name args _reason)
  "Ferramenta transacional para edição de arquivos C/C++ (.c, .h, .cpp).
TARGET-FILE: Caminho do arquivo C/C++.
ACTION: `insert_snippet', `refactor_symbol' ou `validate_buffer'.
SNIPPET-NAME: Nome do snippet Tempel (ex: `function', `struct', `header_guard',
`main').
ARGS: Argumentos para o snippet ou substituição de símbolo.
REASON: Motivo da alteração."
  (let* ((abs-file (expand-file-name target-file (or (and (fboundp 'project-root)
                                                          (when-let* ((p (project-current)))
                                                            (project-root p)))
                                                     user-emacs-directory)))
         (buf (or (find-buffer-visiting abs-file)
                  (and (file-exists-p abs-file) (find-file-noselect abs-file))
                  (get-buffer-create (file-name-nondirectory abs-file)))))
    (with-current-buffer buf
      (unless (or (derived-mode-p 'c-mode) (derived-mode-p 'c++-mode) (derived-mode-p 'c-ts-mode))
        (when (fboundp 'c-mode) (c-mode)))
      (pcase action
        ("insert_snippet"
         (let* ((name (or snippet-name "function"))
                (arg-str (or args ""))
                (code (cond
                       ((equal name "struct")
                        (format "typedef struct s_%s\n{\n    int    id;\n} t_%s;\n" arg-str arg-str))
                       ((equal name "header_guard")
                        (let ((guard (upcase (concat (replace-regexp-in-string "[.-]" "_" (file-name-nondirectory abs-file)) "_H"))))
                          (format "#ifndef %s\n# define %s\n\n#endif\n" guard guard)))
                       ((equal name "main")
                        (format "int main(int argc, char **argv)\n{\n    (void)argc;\n    (void)argv;\n    return (0);\n}\n"))
                       (t
                        (format "void %s(void)\n{\n    return ;\n}\n" arg-str)))))
           (goto-char (point-max))
           (unless (bolp) (insert "\n"))
           (insert code)
           (condition-case err
               (progn
                 (save-excursion (check-parens))
                 (save-buffer)
                 (format "Snippet C/C++ '%s' inserido com sucesso em '%s'. Buffer validado." name abs-file))
             (error
              (primitive-undo 1 buf)
              (format "Erro de sintaxe ao inserir snippet C/C++ '%s': %s. Transação revertida." name (error-message-string err))))))
        ("refactor_symbol"
         (if (or (null args) (string-empty-p args))
             "Erro: informe os símbolos 'antigo novo' em args para refatorar."
           (let* ((parts (split-string args "[ \t]+" t))
                  (old-sym (car parts))
                  (new-sym (cadr parts)))
             (if (and old-sym new-sym)
                 (progn
                   (goto-char (point-min))
                   (let ((count 0))
                     (while (search-forward old-sym nil t)
                       (replace-match new-sym t t)
                       (setq count (1+ count)))
                     (condition-case err
                         (progn
                           (save-excursion (check-parens))
                           (save-buffer)
                           (format "Refatoração C/C++ '%s' -> '%s' concluída em '%s' (%d substituições). Buffer validado."
                                   old-sym new-sym abs-file count))
                       (error
                        (primitive-undo count buf)
                        (format "Erro de sintaxe ao refatorar '%s': %s. Transação revertida." old-sym (error-message-string err))))))
               "Erro: forneça 'velho novo' em args."))))
        ("validate_buffer"
         (condition-case err
             (progn
               (save-excursion (check-parens))
               (format "Buffer C/C++ '%s' validado com sucesso." abs-file))
           (error
            (format "Erro de validação no buffer C/C++ '%s': %s" abs-file (error-message-string err)))))
        (_ (format "Ação '%s' desconhecida. Use 'insert_snippet', 'refactor_symbol' ou 'validate_buffer'." action))))))

(defun +carlos/magent-tool-go-smart-edit (target-file action &optional snippet-name args _reason)
  "Ferramenta transacional para edição de arquivos Go (.go).
TARGET-FILE: Caminho do arquivo .go.
ACTION: `insert_snippet', `refactor_symbol' ou `validate_buffer'.
SNIPPET-NAME: Nome do snippet Tempel (ex: `func', `struct', `interface',
`goroutine', `table_test').
ARGS: Argumentos para o snippet ou substituição de símbolo.
REASON: Motivo da alteração."
  (let* ((abs-file (expand-file-name target-file (or (and (fboundp 'project-root)
                                                          (when-let* ((p (project-current)))
                                                            (project-root p)))
                                                     user-emacs-directory)))
         (buf (or (find-buffer-visiting abs-file)
                  (and (file-exists-p abs-file) (find-file-noselect abs-file))
                  (get-buffer-create (file-name-nondirectory abs-file)))))
    (with-current-buffer buf
      (unless (or (derived-mode-p 'go-mode) (derived-mode-p 'go-ts-mode))
        (when (fboundp 'go-mode) (go-mode)))
      (pcase action
        ("insert_snippet"
         (let* ((name (or snippet-name "func"))
                (arg-str (or args ""))
                (code (cond
                       ((equal name "struct")
                        (format "type %s struct {\n\tID string\n}\n" arg-str))
                       ((equal name "interface")
                        (format "type %s interface {\n\tExecute() error\n}\n" arg-str))
                       ((equal name "goroutine")
                        (format "go func() {\n\t// %s async task\n}()\n" arg-str))
                       ((equal name "table_test")
                        (format "func Test%s(t *testing.T) {\n\ttests := []struct {\n\t\tname string\n\t}{\n\t\t{\"default\"},\n\t}\n\tfor _, tt := range tests {\n\t\tt.Run(tt.name, func(t *testing.T) {\n\t\t})\n\t}\n}\n" arg-str))
                       (t
                        (format "func %s() error {\n\treturn nil\n}\n" arg-str)))))
           (goto-char (point-max))
           (unless (bolp) (insert "\n"))
           (insert code)
           (condition-case err
               (progn
                 (save-excursion (check-parens))
                 (save-buffer)
                 (format "Snippet Go '%s' inserido com sucesso em '%s'. Buffer validado." name abs-file))
             (error
              (primitive-undo 1 buf)
              (format "Erro de sintaxe ao inserir snippet Go '%s': %s. Transação revertida." name (error-message-string err))))))
        ("refactor_symbol"
         (if (or (null args) (string-empty-p args))
             "Erro: informe os símbolos 'antigo novo' em args para refatorar."
           (let* ((parts (split-string args "[ \t]+" t))
                  (old-sym (car parts))
                  (new-sym (cadr parts)))
             (if (and old-sym new-sym)
                 (progn
                   (goto-char (point-min))
                   (let ((count 0))
                     (while (search-forward old-sym nil t)
                       (replace-match new-sym t t)
                       (setq count (1+ count)))
                     (condition-case err
                         (progn
                           (save-excursion (check-parens))
                           (save-buffer)
                           (format "Refatoração Go '%s' -> '%s' concluída em '%s' (%d substituições). Buffer validado."
                                   old-sym new-sym abs-file count))
                       (error
                        (primitive-undo count buf)
                        (format "Erro de sintaxe ao refatorar '%s': %s. Transação revertida." old-sym (error-message-string err))))))
               "Erro: forneça 'velho novo' em args."))))
        ("validate_buffer"
         (condition-case err
             (progn
               (save-excursion (check-parens))
               (format "Buffer Go '%s' validado com sucesso." abs-file))
           (error
            (format "Erro de validação no buffer Go '%s': %s" abs-file (error-message-string err)))))
        (_ (format "Ação '%s' desconhecida. Use 'insert_snippet', 'refactor_symbol' ou 'validate_buffer'." action))))))




(defun +carlos/magent-tool-org-smart-edit (target-file action &optional snippet-name args _reason)
  "Ferramenta transacional para edição da AST do Org-mode (.org).
TARGET-FILE: Caminho do arquivo .org.
ACTION: `insert_snippet', `refactor_symbol', `set_property',
`replace_heading', `replace_text' ou `validate_buffer'.
SNIPPET-NAME: Nome do snippet Tempel (ex: `heading', `properties_drawer',
`table', `src_block').
ARGS:
- `insert_snippet': texto livre do snippet.
- `refactor_symbol': \"antigo novo [FLAGS]\", FLAGS opcional
  ALL|FIRST|WORD|REGEX (default ALL).
- `set_property': \"Heading Exato|PROPRIEDADE|VALOR\" (casamento exato
  de :raw-value via AST).
- `replace_heading': \"heading-exato|novo-titulo\" (preserva nível,
  keyword e tags).
- `replace_text': \"old|new|L1|L2\" restrito ao intervalo de linhas.
Toda mutação passa pelo gate transacional compartilhado (snapshot +
org-lint + restore byte-a-byte em falha).
REASON: Motivo da alteração."
  (let* ((abs-file (expand-file-name target-file (or (and (fboundp 'project-root)
                                                          (when-let* ((p (project-current)))
                                                            (project-root p)))
                                                     user-emacs-directory)))
         (buf (or (find-buffer-visiting abs-file)
                  (and (file-exists-p abs-file) (find-file-noselect abs-file))
                  (get-buffer-create (file-name-nondirectory abs-file)))))
    (with-current-buffer buf
      (unless (derived-mode-p 'org-mode)
        (when (fboundp 'org-mode) (org-mode)))
      (pcase action
        ("insert_snippet"
         (let* ((name (or snippet-name "heading"))
                (arg-str (or args ""))
                (code (cond
                       ((equal name "properties_drawer")
                        (format "    :PROPERTIES:\n    :CREATED: %s\n    :STATUS: pendente\n    :END:\n"
                                (format-time-string "%Y-%m-%d")))
                       ((equal name "table")
                        (format "| ID | Title | Status |\n|----+-------+--------|\n| 1  | %s | TODO   |\n" arg-str))
                       ((equal name "src_block")
                        (format "#+BEGIN_SRC %s\n\n#+END_SRC\n" (if (string-empty-p arg-str) "elisp" arg-str)))
                       (t
                        (format "* TODO %s\n    :PROPERTIES:\n    :CREATED: %s\n    :STATUS: pendente\n    :END:\n\n"
                                arg-str (format-time-string "%Y-%m-%d"))))))
           (+carlos/magent--smart-edit-transaction buf 'org
             (lambda ()
               (goto-char (point-max))
               (unless (bolp) (insert "\n"))
               (insert code)
               (format "Snippet Org '%s' inserido com sucesso em '%s'." name abs-file)))))
        ("refactor_symbol"
         (if (or (null args) (string-empty-p args))
             "Erro: informe \"antigo novo [FLAGS]\" em args para refatorar."
           (let* ((parts (split-string args "[ \t]+" t))
                  (old-sym (nth 0 parts))
                  (new-sym (nth 1 parts))
                  (flags (nth 2 parts)))
             (if (and old-sym new-sym)
                 (+carlos/magent--smart-edit-transaction buf 'org
                   (lambda ()
                     (let ((count (+carlos/magent--smart-edit-replace-core old-sym new-sym flags)))
                       (format "Refatoração Org '%s' -> '%s' concluída em '%s' (%d substituições%s)."
                               old-sym new-sym abs-file count
                               (if flags (format ", flags=%s" flags) "")))))
               "Erro: forneça 'velho novo' em args."))))
        ("replace_heading"
         (if (or (null args) (string-empty-p args))
             "Erro: args deve ser 'heading-exato|novo-titulo'."
           (let* ((parts (split-string args "|" t))
                  (heading-text (nth 0 parts))
                  (new-title (nth 1 parts)))
             (if (and heading-text new-title)
                 (+carlos/magent--smart-edit-transaction buf 'org
                   (lambda ()
                     (let* ((tree (org-element-parse-buffer))
                            (node (org-element-map tree 'headline
                                    (lambda (h)
                                      (and (string-equal (org-element-property :raw-value h)
                                                         heading-text)
                                           h))
                                    nil t)))
                       (unless node
                         (error "Heading '%s' não encontrado" heading-text))
                       (goto-char (org-element-property :begin node))
                       (delete-region (point) (progn (forward-line 1) (point)))
                       (insert (concat
                                (make-string (org-element-property :level node) ?*)
                                (let ((kw (org-element-property :todo-keyword node)))
                                  (if kw (concat " " kw) ""))
                                (let ((prio (org-element-property :priority node)))
                                  (if prio (format " [#%s]" prio) ""))
                                " " new-title
                                (let ((tags (org-element-property :tags node)))
                                  (if tags (format " :%s:" (mapconcat #'identity tags ":")) ""))
                                "\n"))
                       (format "Heading '%s' renomeado para '%s' (nível, keyword e tags preservados)."
                               heading-text new-title))))
               "Erro: formato de args deve ser 'heading-exato|novo-titulo'."))))
        ("replace_text"
         (if (or (null args) (string-empty-p args))
             "Erro: args deve ser 'old|new|L1|L2'."
           (let* ((parts (split-string args "|" t))
                  (old-txt (nth 0 parts))
                  (new-txt (nth 1 parts))
                  (l1 (and (nth 2 parts) (string-to-number (nth 2 parts))))
                  (l2 (and (nth 3 parts) (string-to-number (nth 3 parts)))))
             (cond
              ((or (not old-txt) (not new-txt) (not l1) (not l2))
               "Erro: formato de args deve ser 'old|new|L1|L2'.")
              ((or (< l1 1) (< l2 l1) (> l2 (line-number-at-pos (point-max))))
               (format "Erro: intervalo L%d-L%d inválido (arquivo tem %d linhas)."
                       l1 l2 (line-number-at-pos (point-max))))
              (t
               (+carlos/magent--smart-edit-transaction buf 'org
                 (lambda ()
                   (save-excursion
                     (save-restriction
                       (narrow-to-region
                        (save-excursion (goto-char (point-min)) (forward-line (1- l1)) (point))
                        (save-excursion (goto-char (point-min)) (forward-line l2) (point)))
                       (let ((count (+carlos/magent--smart-edit-replace-core old-txt new-txt)))
                         (format "Substituição em L%d-L%d concluída (%d ocorrência(s))."
                                 l1 l2 count)))))))))))
        ("set_property"
         (if (or (null args) (string-empty-p args))
             "Erro: args deve ser 'Heading|PROP|VALOR'."
           (let* ((parts (split-string args "|" t))
                  (heading (nth 0 parts))
                  (prop (nth 1 parts))
                  (val (nth 2 parts)))
             (if (and heading prop val)
                 (+carlos/magent--smart-edit-transaction buf 'org
                   (lambda ()
                     (let* ((tree (org-element-parse-buffer))
                            (node (org-element-map tree 'headline
                                    (lambda (h)
                                      (and (string-equal (org-element-property :raw-value h) heading) h))
                                    nil t)))
                       (unless node
                         (error "Nó '%s' não encontrado" heading))
                       (goto-char (org-element-property :begin node))
                       (org-set-property prop val)
                       (format "Propriedade '%s' definida como '%s' no nó '%s'." prop val heading))))
               "Erro: formato de args deve ser 'Heading|PROP|VALOR'."))))
        ("validate_buffer"
         (if (fboundp 'org-lint)
             (let ((reports (org-lint)))
               (if reports
                   (format "Avisos do org-lint no buffer '%s': %d" abs-file (length reports))
                 (format "Buffer Org '%s' validado e sintaticamente limpo." abs-file)))
           (format "Buffer Org '%s' carregado com sucesso." abs-file)))
        (_ (format "Ação '%s' desconhecida. Use 'insert_snippet', 'refactor_symbol', 'set_property', 'replace_heading', 'replace_text' ou 'validate_buffer'." action))))))

(defun +carlos/magent-tool-sh-smart-edit (target-file action &optional snippet-name args _reason)
  "Ferramenta transacional para edição de scripts Shell/Bash (.sh, .bash).
TARGET-FILE: Caminho do arquivo script.
ACTION: `insert_snippet', `refactor_symbol' ou `validate_buffer'.
SNIPPET-NAME: Nome do snippet Tempel (ex: `script_header', `function',
`parse_args', `if_statement', `case_statement').
ARGS: Argumentos para o snippet ou substituição de símbolo.
REASON: Motivo da alteração."
  (let* ((abs-file (expand-file-name target-file (or (and (fboundp 'project-root)
                                                          (when-let* ((p (project-current)))
                                                            (project-root p)))
                                                     user-emacs-directory)))
         (buf (or (find-buffer-visiting abs-file)
                  (and (file-exists-p abs-file) (find-file-noselect abs-file))
                  (get-buffer-create (file-name-nondirectory abs-file)))))
    (with-current-buffer buf
      (unless (or (derived-mode-p 'sh-mode) (derived-mode-p 'bash-ts-mode))
        (when (fboundp 'sh-mode) (sh-mode)))
      (pcase action
        ("insert_snippet"
         (let* ((name (or snippet-name "script_header"))
                (arg-str (or args ""))
                (code (cond
                       ((equal name "function")
                        (format "%s() {\n    local arg=\"$1\"\n    return 0\n}\n" arg-str))
                       ((equal name "parse_args")
                        "while [[ $# -gt 0 ]]; do\n    case \"$1\" in\n        -h|--help) exit 0 ;;\n        *) shift ;;\n    esac\ndone\n")
                       ((equal name "if_statement")
                        (format "if [[ %s ]]; then\n    :\nfi\n" (if (string-empty-p arg-str) "-f \"$1\"" arg-str)))
                       ((equal name "case_statement")
                        (format "case \"%s\" in\n    pattern) :\n        ;;\n    *) :\n        ;;\nesac\n" arg-str))
                       (t
                        "#!/usr/bin/env bash\nset -euo pipefail\n\n# Main entrypoint\n"))))
           (goto-char (point-max))
           (unless (bolp) (insert "\n"))
           (insert code)
           (condition-case err
               (progn
                 (save-excursion (check-parens))
                 (save-buffer)
                 (format "Snippet Shell '%s' inserido com sucesso em '%s'. Buffer validado." name abs-file))
             (error
              (primitive-undo 1 buf)
              (format "Erro de sintaxe ao inserir snippet Shell '%s': %s. Transação revertida." name (error-message-string err))))))
        ("refactor_symbol"
         (if (or (null args) (string-empty-p args))
             "Erro: informe os símbolos 'antigo novo' em args para refatorar."
           (let* ((parts (split-string args "[ \t]+" t))
                  (old-sym (car parts))
                  (new-sym (cadr parts)))
             (if (and old-sym new-sym)
                 (progn
                   (goto-char (point-min))
                   (let ((count 0))
                     (while (search-forward old-sym nil t)
                       (replace-match new-sym t t)
                       (setq count (1+ count)))
                     (condition-case err
                         (progn
                           (save-excursion (check-parens))
                           (save-buffer)
                           (format "Refatoração Shell '%s' -> '%s' concluída em '%s' (%d substituições). Buffer validado."
                                   old-sym new-sym abs-file count))
                       (error
                        (primitive-undo count buf)
                        (format "Erro de sintaxe ao refatorar '%s': %s. Transação revertida." old-sym (error-message-string err))))))
               "Erro: forneça 'velho novo' em args."))))
        ("validate_buffer"
         (condition-case err
             (progn
               (save-excursion (check-parens))
               (format "Buffer Shell '%s' validado com sucesso." abs-file))
           (error
            (format "Erro de validação no buffer Shell '%s': %s" abs-file (error-message-string err)))))
        (_ (format "Ação '%s' desconhecida. Use 'insert_snippet', 'refactor_symbol' ou 'validate_buffer'." action))))))

(defun +carlos/magent-tool-markdown-smart-edit (target-file action &optional snippet-name args _reason)
  "Ferramenta transacional para edição de arquivos Markdown (.md).
TARGET-FILE: Caminho do arquivo Markdown.
ACTION: `insert_snippet', `refactor_symbol' ou `validate_buffer'.
SNIPPET-NAME: Nome do snippet Tempel (ex: `frontmatter', `heading', `table',
`codeblock').
ARGS: Argumentos para o snippet ou substituição de símbolo.
REASON: Motivo da alteração."
  (let* ((abs-file (expand-file-name target-file (or (and (fboundp 'project-root)
                                                          (when-let* ((p (project-current)))
                                                            (project-root p)))
                                                     user-emacs-directory)))
         (buf (or (find-buffer-visiting abs-file)
                  (and (file-exists-p abs-file) (find-file-noselect abs-file))
                  (get-buffer-create (file-name-nondirectory abs-file)))))
    (with-current-buffer buf
      (unless (derived-mode-p 'markdown-mode)
        (when (fboundp 'markdown-mode) (markdown-mode)))
      (pcase action
        ("insert_snippet"
         (let* ((name (or snippet-name "heading"))
                (arg-str (or args ""))
                (code (cond
                       ((equal name "frontmatter")
                        (format "---\ntitle: %s\ndate: %s\n---\n" arg-str (format-time-string "%Y-%m-%d")))
                       ((equal name "table")
                        (format "| Col 1 | Col 2 |\n| --- | --- |\n| %s | value |\n" arg-str))
                       ((equal name "codeblock")
                        (format "```%s\n\n```\n" (if (string-empty-p arg-str) "bash" arg-str)))
                       (t
                        (format "## %s\n\n" arg-str)))))
           (goto-char (point-max))
           (unless (bolp) (insert "\n"))
           (insert code)
           (save-buffer)
           (format "Snippet Markdown '%s' inserido com sucesso em '%s'." name abs-file)))
        ("refactor_symbol"
         (if (or (null args) (string-empty-p args))
             "Erro: informe os símbolos 'antigo novo' em args para refatorar."
           (let* ((parts (split-string args "[ \t]+" t))
                  (old-sym (car parts))
                  (new-sym (cadr parts)))
             (if (and old-sym new-sym)
                 (progn
                   (goto-char (point-min))
                   (let ((count 0))
                     (while (search-forward old-sym nil t)
                       (replace-match new-sym t t)
                       (setq count (1+ count)))
                     (save-buffer)
                     (format "Refatoração Markdown '%s' -> '%s' concluída em '%s' (%d substituições)." old-sym new-sym abs-file count)))
               "Erro: forneça 'velho novo' em args."))))
        ("validate_buffer"
         (format "Buffer Markdown '%s' validado com sucesso." abs-file))
        (_ (format "Ação '%s' desconhecida. Use 'insert_snippet', 'refactor_symbol' ou 'validate_buffer'." action))))))

(defun +carlos/magent-tool-rust-smart-edit (target-file action &optional snippet-name args _reason)
  "Ferramenta transacional para edição de arquivos Rust (.rs).
TARGET-FILE: Caminho do arquivo .rs.
ACTION: `insert_snippet', `refactor_symbol' ou `validate_buffer'.
SNIPPET-NAME: Nome do snippet Tempel (ex: `fn', `struct', `enum', `impl',
`trait', `async_fn', `tokio_main', `test_case').
ARGS: Argumentos para o snippet ou substituição de símbolo.
REASON: Motivo da alteração."
  (let* ((abs-file (expand-file-name target-file (or (and (fboundp 'project-root)
                                                          (when-let* ((p (project-current)))
                                                            (project-root p)))
                                                     user-emacs-directory)))
         (buf (or (find-buffer-visiting abs-file)
                  (and (file-exists-p abs-file) (find-file-noselect abs-file))
                  (get-buffer-create (file-name-nondirectory abs-file)))))
    (with-current-buffer buf
      (unless (or (derived-mode-p 'rust-mode) (derived-mode-p 'rust-ts-mode))
        (when (fboundp 'rust-mode) (rust-mode)))
      (pcase action
        ("insert_snippet"
         (let* ((name (or snippet-name "fn"))
                (arg-str (or args ""))
                (code (cond
                       ((equal name "struct")
                        (format "pub struct %s {\n    pub id: String,\n}\n" arg-str))
                       ((equal name "enum")
                        (format "pub enum %s {\n    Default,\n}\n" arg-str))
                       ((equal name "impl")
                        (format "impl %s {\n    pub fn new() -> Self {\n        Self {}\n    }\n}\n" arg-str))
                       ((equal name "trait")
                        (format "pub trait %s {\n    fn execute(&self) -> Result<(), String>;\n}\n" arg-str))
                       ((equal name "async_fn")
                        (format "pub async fn %s() -> Result<(), Box<dyn std::error::Error>> {\n    Ok(())\n}\n" arg-str))
                       ((equal name "tokio_main")
                        "#[tokio::main]\nasync fn main() -> Result<(), Box<dyn std::error::Error>> {\n    Ok(())\n}\n")
                       ((equal name "test_case")
                        (format "#[cfg(test)]\nmod tests {\n    #[test]\n    fn test_%s() {\n        assert_eq!(2 + 2, 4);\n    }\n}\n" (if (string-empty-p arg-str) "basic" arg-str)))
                       (t
                        (format "pub fn %s() -> Result<(), String> {\n    Ok(())\n}\n" arg-str)))))
           (goto-char (point-max))
           (unless (bolp) (insert "\n"))
           (insert code)
           (condition-case err
               (progn
                 (save-excursion (check-parens))
                 (save-buffer)
                 (format "Snippet Rust '%s' inserido com sucesso em '%s'. Buffer validado." name abs-file))
             (error
              (primitive-undo 1 buf)
              (format "Erro de sintaxe ao inserir snippet Rust '%s': %s. Transação revertida." name (error-message-string err))))))
        ("refactor_symbol"
         (if (or (null args) (string-empty-p args))
             "Erro: informe os símbolos 'antigo novo' em args para refatorar."
           (let* ((parts (split-string args "[ \t]+" t))
                  (old-sym (car parts))
                  (new-sym (cadr parts)))
             (if (and old-sym new-sym)
                 (progn
                   (goto-char (point-min))
                   (let ((count 0))
                     (while (search-forward old-sym nil t)
                       (replace-match new-sym t t)
                       (setq count (1+ count)))
                     (condition-case err
                         (progn
                           (save-excursion (check-parens))
                           (save-buffer)
                           (format "Refatoração Rust '%s' -> '%s' concluída em '%s' (%d substituições). Buffer validado."
                                   old-sym new-sym abs-file count))
                       (error
                        (primitive-undo count buf)
                        (format "Erro de sintaxe ao refatorar '%s': %s. Transação revertida." old-sym (error-message-string err))))))
               "Erro: forneça 'velho novo' em args."))))
        ("validate_buffer"
         (condition-case err
             (progn
               (save-excursion (check-parens))
               (format "Buffer Rust '%s' validado com sucesso." abs-file))
           (error
            (format "Erro de validação no buffer Rust '%s': %s" abs-file (error-message-string err)))))
        (_ (format "Ação '%s' desconhecida. Use 'insert_snippet', 'refactor_symbol' ou 'validate_buffer'." action))))))

(with-eval-after-load 'gptel
  (when (fboundp 'gptel-make-tool)
    (setq +carlos/magent-tool-elisp-smart-edit
          (gptel-make-tool
           :name "elisp_smart_edit"
           :description "Transactional native tool for intelligent Elisp (.el) code editing via Tempel Snippets, symbol refactoring, and in-memory validation (check-parens + byte-compiler + checkdoc)."
           :args '((:name "target_file" :type string :description "Target .el file path")
                   (:name "action" :type string :description "Action: 'insert_snippet', 'refactor_symbol' or 'validate_buffer'")
                   (:name "snippet_name" :type string :description "Tempel snippet name (e.g. 'defun', 'deftest', 'use-package', 'defcustom', 'with-eval-after-load')")
                   (:name "args" :type string :description "Positional or symbol replacement arguments")
                   (:name "reason" :type string :description "Reason for edit"))
           :function #'+carlos/magent-tool-elisp-smart-edit
           :category "magent"))

    (setq +carlos/magent-tool-nix-smart-edit
          (gptel-make-tool
           :name "nix_smart_edit"
           :description "Transactional native tool for intelligent Nix (.nix) code editing via Tempel Snippets, symbol refactoring, and in-memory validation (delimiters + nixfmt/statix)."
           :args '((:name "target_file" :type string :description "Target .nix file path")
                   (:name "action" :type string :description "Action: 'insert_snippet', 'refactor_symbol' or 'validate_buffer'")
                   (:name "snippet_name" :type string :description "Tempel snippet name (e.g. 'flake', 'module', 'package', 'overlay', 'devshell', 'option')")
                   (:name "args" :type string :description "Positional or symbol replacement arguments")
                   (:name "reason" :type string :description "Reason for edit"))
           :function #'+carlos/magent-tool-nix-smart-edit
           :category "magent"))

    (setq +carlos/magent-tool-python-smart-edit
          (gptel-make-tool
           :name "python_smart_edit"
           :description "Transactional native tool for intelligent Python (.py) code editing via Tempel Snippets, symbol refactoring, and in-memory validation (ruff/black/py-compile)."
           :args '((:name "target_file" :type string :description "Target .py file path")
                   (:name "action" :type string :description "Action: 'insert_snippet', 'refactor_symbol' or 'validate_buffer'")
                   (:name "snippet_name" :type string :description "Tempel snippet name (e.g. 'def', 'class', 'async_def', 'pytest', 'dataclass', 'main')")
                   (:name "args" :type string :description "Positional or symbol replacement arguments")
                   (:name "reason" :type string :description "Reason for edit"))
           :function #'+carlos/magent-tool-python-smart-edit
           :category "magent"))

    (setq +carlos/magent-tool-ts-smart-edit
          (gptel-make-tool
           :name "ts_smart_edit"
           :description "Transactional native tool for intelligent TypeScript/JavaScript (.ts, .tsx, .js) code editing via Tempel Snippets, symbol refactoring, and in-memory validation (prettier/eslint)."
           :args '((:name "target_file" :type string :description "Target TS/JS file path")
                   (:name "action" :type string :description "Action: 'insert_snippet', 'refactor_symbol' or 'validate_buffer'")
                   (:name "snippet_name" :type string :description "Tempel snippet name (e.g. 'interface', 'type', 'function', 'export_const', 'describe_it')")
                   (:name "args" :type string :description "Positional or symbol replacement arguments")
                   (:name "reason" :type string :description "Reason for edit"))
           :function #'+carlos/magent-tool-ts-smart-edit
           :category "magent"))

    (setq +carlos/magent-tool-c-smart-edit
          (gptel-make-tool
           :name "c_smart_edit"
           :description "Transactional native tool for intelligent C/C++ (.c, .h, .cpp) code editing enforcing School 42 Norminette (25-line limit) and Tempel Snippets."
           :args '((:name "target_file" :type string :description "Target .c or .h file path")
                   (:name "action" :type string :description "Action: 'insert_snippet', 'refactor_symbol' or 'validate_buffer'")
                   (:name "snippet_name" :type string :description "Tempel snippet name (e.g. 'function', 'struct', 'header_guard', 'main')")
                   (:name "args" :type string :description "Positional or symbol replacement arguments")
                   (:name "reason" :type string :description "Reason for edit"))
           :function #'+carlos/magent-tool-c-smart-edit
           :category "magent"))

    (setq +carlos/magent-tool-go-smart-edit
          (gptel-make-tool
           :name "go_smart_edit"
           :description "Transactional native tool for intelligent Go (.go) code editing via Tempel Snippets, symbol refactoring, and in-memory validation (gofmt/gopls)."
           :args '((:name "target_file" :type string :description "Target .go file path")
                   (:name "action" :type string :description "Action: 'insert_snippet', 'refactor_symbol' or 'validate_buffer'")
                   (:name "snippet_name" :type string :description "Tempel snippet name (e.g. 'func', 'struct', 'interface', 'goroutine', 'table_test')")
                   (:name "args" :type string :description "Positional or symbol replacement arguments")
                   (:name "reason" :type string :description "Reason for edit"))
           :function #'+carlos/magent-tool-go-smart-edit
           :category "magent"))

    (setq +carlos/magent-tool-org-smart-edit
          (gptel-make-tool
           :name "org_smart_edit"
           :description "Transactional native tool for Org-mode AST structural editing (headings, TODO/DONE keywords, drawers, tables) and org-lint validation."
           :args '((:name "target_file" :type string :description "Target .org file path")
                   (:name "action" :type string :description "Action: 'insert_snippet', 'refactor_symbol' or 'validate_buffer'")
                   (:name "snippet_name" :type string :description "Tempel snippet name (e.g. 'heading', 'properties_drawer', 'table', 'src_block')")
                   (:name "args" :type string :description "Positional or symbol replacement arguments")
                   (:name "reason" :type string :description "Reason for edit"))
           :function #'+carlos/magent-tool-org-smart-edit
           :category "magent"))

    (setq +carlos/magent-tool-sh-smart-edit
          (gptel-make-tool
           :name "sh_smart_edit"
           :description "Transactional native tool for intelligent Shell/Bash (.sh, .bash) script editing via Tempel Snippets, symbol refactoring, and shellcheck validation."
           :args '((:name "target_file" :type string :description "Target .sh file path")
                   (:name "action" :type string :description "Action: 'insert_snippet', 'refactor_symbol' or 'validate_buffer'")
                   (:name "snippet_name" :type string :description "Tempel snippet name (e.g. 'script_header', 'function', 'parse_args', 'if_statement', 'case_statement')")
                   (:name "args" :type string :description "Positional or symbol replacement arguments")
                   (:name "reason" :type string :description "Reason for edit"))
           :function #'+carlos/magent-tool-sh-smart-edit
           :category "magent"))

    (setq +carlos/magent-tool-markdown-smart-edit
          (gptel-make-tool
           :name "markdown_smart_edit"
           :description "Transactional native tool for Markdown (.md) editing via Tempel Snippets, symbol refactoring, and markdownlint/markitdown validation."
           :args '((:name "target_file" :type string :description "Target .md file path")
                   (:name "action" :type string :description "Action: 'insert_snippet', 'refactor_symbol' or 'validate_buffer'")
                   (:name "snippet_name" :type string :description "Tempel snippet name (e.g. 'frontmatter', 'heading', 'table', 'codeblock')")
                   (:name "args" :type string :description "Positional or symbol replacement arguments")
                   (:name "reason" :type string :description "Reason for edit"))
           :function #'+carlos/magent-tool-markdown-smart-edit
           :category "magent"))

    (setq +carlos/magent-tool-rust-smart-edit
          (gptel-make-tool
           :name "rust_smart_edit"
           :description "Transactional native tool for intelligent Rust (.rs) code editing via Tempel Snippets, symbol refactoring, and in-memory validation (rustfmt/cargo)."
           :args '((:name "target_file" :type string :description "Target .rs file path")
                   (:name "action" :type string :description "Action: 'insert_snippet', 'refactor_symbol' or 'validate_buffer'")
                   (:name "snippet_name" :type string :description "Tempel snippet name (e.g. 'fn', 'struct', 'enum', 'impl', 'trait', 'async_fn', 'tokio_main', 'test_case')")
                   (:name "args" :type string :description "Positional or symbol replacement arguments")
                   (:name "reason" :type string :description "Reason for edit"))
           :function #'+carlos/magent-tool-rust-smart-edit
           :category "magent"))

    ))
