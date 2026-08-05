# Justfile for MyEmacs (Vanilla Emacs Configuration)

default:
    @just --list

# Launch Emacs with this config
run:
    emacs --init-directory "$(pwd)"

# Install/refresh packages (non-interactive)
install:
    emacs --init-directory "$(pwd)" --batch -l init.el --eval '(message "Packages installed.")'

# Byte-compile lisp directory
compile:
    emacs --init-directory "$(pwd)" --batch -l init.el \
      --eval '(byte-recompile-directory (expand-file-name "lisp" user-emacs-directory) 0)'

# Check config loads without errors
check:
    emacs --init-directory "$(pwd)" --batch -l init.el \
      --eval '(message "Config loaded OK.")' && echo "✅ OK" || echo "❌ FAIL"
