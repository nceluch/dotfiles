#!/bin/bash

# Keep equal to HERDR_PIN in local/mac.zsh. `herdr --remote` replaces the box's
# binary with the client's version on attach, which kills running panes.
HERDR_VERSION="0.9.1"
DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HERDR="$HOME/.local/bin/herdr"

case "$(uname -m)" in
  aarch64|arm64) ARCH="aarch64" ;;
  *)             ARCH="x86_64" ;;
esac

if [ "$("$HERDR" --version 2> /dev/null | awk '{print $2}')" != "$HERDR_VERSION" ]; then
  mkdir -p "$HOME/.local/bin"
  # Rename instead of overwrite: works while a running server holds the old binary.
  curl -fsSLo "$HERDR.new" \
    "https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-${ARCH}"
  chmod +x "$HERDR.new"
  mv "$HERDR.new" "$HERDR"
fi

# Copy only the config file. The directory also holds session.json.
mkdir -p "$HOME/.config/herdr"
cp "$DOTFILES_DIR/.config/herdr/config.toml" "$HOME/.config/herdr/config.toml"

"$HERDR" integration install claude
"$HERDR" server reload-config > /dev/null 2>&1 || true
echo "  Herdr $HERDR_VERSION configured"
