#!/usr/bin/env bash
set -e

PROD_DIR="${EMACS_TEST_DIR:-$HOME/.config/emacs}"
BACKUP_DIR="/tmp/emacs-factory-backup-$(date +%s)"

echo "🔄 Iniciando Factory Reset do ambiente de produção ($PROD_DIR)..."

if [ ! -d "$PROD_DIR" ]; then
    echo "❌ Diretório $PROD_DIR não existe. Nada a resetar."
    exit 1
fi

echo "📁 Criando diretório de backup temporário em $BACKUP_DIR"
mkdir -p "$BACKUP_DIR/magent"

# Lista de arquivos de estado para preservar
FILES_TO_SAVE=(
    "bookmarks"
    "recentf"
    "places"
    "history"
    "savehist"
    "custom-file.el"
)

# Fazendo backup dos arquivos soltos
for file in "${FILES_TO_SAVE[@]}"; do
    if [ -f "$PROD_DIR/$file" ]; then
        echo "   Salvando $file..."
        cp "$PROD_DIR/$file" "$BACKUP_DIR/"
    fi
done

# Fazendo backup dos diretórios
if [ -d "$PROD_DIR/magent/sessions" ]; then
    echo "   Salvando magent/sessions/..."
    cp -r "$PROD_DIR/magent/sessions" "$BACKUP_DIR/magent/"
fi

echo "🔥 Apagando completamente $PROD_DIR..."
rm -rf "$PROD_DIR"

echo "📥 Clonando repositório limpo a partir do Github..."
git clone git@github.com:carlosalbertofilho/MyEmacs.git "$PROD_DIR"

echo "♻️  Restaurando arquivos de estado no novo clone..."
for file in "${FILES_TO_SAVE[@]}"; do
    if [ -f "$BACKUP_DIR/$file" ]; then
        cp "$BACKUP_DIR/$file" "$PROD_DIR/"
    fi
done

if [ -d "$BACKUP_DIR/magent/sessions" ]; then
    mkdir -p "$PROD_DIR/magent"
    cp -r "$BACKUP_DIR/magent/sessions" "$PROD_DIR/magent/"
fi

echo "✅ Backup restaurado com sucesso."
echo "🧹 Removendo diretório temporário de backup ($BACKUP_DIR)..."
rm -rf "$BACKUP_DIR"

echo "✅ Factory reset concluído na estrutura de pastas. O Justfile vai prosseguir com o build..."
