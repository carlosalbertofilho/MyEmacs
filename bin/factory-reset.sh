#!/usr/bin/env bash
set -euo pipefail

# Factory reset do ambiente oficial de Emacs (~/.config/emacs por default).
# Fluxo: backup do estado -> nuke -> clone fresco (origin/main) -> restore.
#
# Seguranças:
#   - Pede confirmação interativa (escape p/ automação: FORCE=1).
#   - Aborta se o prod tiver alterações TRACKED não-commitadas (FORCE=1 ignora).
#   - Em falha após o nuke, o backup permanece em $BACKUP_DIR e o caminho
#     é impresso no erro.

PROD_DIR="${EMACS_TEST_DIR:-$HOME/.config/emacs}"
DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_URL="$(git -C "$DEV_DIR" remote get-url origin)"
BRANCH="main"
BACKUP_DIR="/tmp/emacs-factory-backup-$(date +%s)"
NUKED=0

trap 'if [ "$NUKED" = "1" ]; then echo "❌ Falha depois do nuke. Backup preservado em: $BACKUP_DIR"; fi' ERR

echo "🔄 Iniciando Factory Reset do ambiente de produção ($PROD_DIR)..."

if [ ! -d "$PROD_DIR" ]; then
    echo "❌ Diretório $PROD_DIR não existe. Nada a resetar."
    exit 1
fi

# ── Guard 1: alterações tracked não-commitadas no prod ────────────────
if [ -d "$PROD_DIR/.git" ] && [ "${FORCE:-0}" != "1" ]; then
    DIRTY="$(git -C "$PROD_DIR" status --porcelain --untracked-files=no || true)"
    if [ -n "$DIRTY" ]; then
        echo "❌ $PROD_DIR tem alterações trackeadas não-commitadas:"
        echo "$DIRTY"
        echo "   Faça commit + 'just sync' antes, ou rode com FORCE=1 para descartar."
        exit 1
    fi
fi

# ── Guard 2: confirmação interativa (FORCE=1 pula) ────────────────────
if [ "${FORCE:-0}" != "1" ]; then
    read -r -p "⚠️  $PROD_DIR será APAGADO e reclonado de origin/$BRANCH. Continuar? [y/N] " REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        echo "Abortado. Nada foi modificado."
        exit 1
    fi
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

for file in "${FILES_TO_SAVE[@]}"; do
    if [ -f "$PROD_DIR/$file" ]; then
        echo "   Salvando $file..."
        cp "$PROD_DIR/$file" "$BACKUP_DIR/"
    fi
done

if [ -d "$PROD_DIR/magent/sessions" ]; then
    echo "   Salvando magent/sessions/..."
    cp -r "$PROD_DIR/magent/sessions" "$BACKUP_DIR/magent/"
fi

echo "🔥 Apagando completamente $PROD_DIR..."
rm -rf "$PROD_DIR"
NUKED=1

echo "📥 Clonando $REMOTE_URL (branch $BRANCH)..."
git clone -b "$BRANCH" "$REMOTE_URL" "$PROD_DIR"

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

NUKED=0
echo "✅ Backup restaurado com sucesso."
echo "🧹 Cópia de segurança mantida em $BACKUP_DIR (apague quando quiser)."
echo "✅ Factory reset concluído na estrutura de pastas. O Justfile vai prosseguir com o build..."
