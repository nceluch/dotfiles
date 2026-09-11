#!/bin/bash

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

./scripts/install-claude.sh
./scripts/install-herdr.sh

[ ! -f "$HOME/.claude/settings.json" ] && cp "$DOTFILES_DIR/.claude/settings.json" "$HOME/.claude/settings.json"
[ ! -f "$HOME/.claude/CLAUDE.md" ] && cp "$DOTFILES_DIR/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
echo "  Claude Code configured"

# --- Claude Code output style ---
# Symlink rather than copy, for the reason in 046b0fc: a cp goes stale silently, so an
# edit to the style in this repo would never reach the box. mkdir -p first — without an
# existing directory, `ln -sf` creates a *file* named output-styles pointing at the
# style, and Claude Code then finds no styles at all.
echo ""
echo "Installing Claude Code output style..."
mkdir -p "$HOME/.claude/output-styles"
ln -sf "$DOTFILES_DIR/.claude/output-styles/intuitive.md" \
  "$HOME/.claude/output-styles/intuitive.md"

# Activation lives in settings.json, which the copy above skips on any box that already
# has one — so merge the single key instead of copying the file. Same merge-don't-clobber
# approach `herdr integration install claude` uses on this file below. The value must
# match the style's frontmatter `name:` byte for byte.
if [ -f "$HOME/.claude/settings.json" ] && command -v jq &> /dev/null; then
  # A literal path, not `$(mktemp)` — a bare `VAR=$(...)` that exits non-zero aborts the
  # whole install under `set -e` (see the fzf block). Beside the target on
  # purpose: same filesystem, so the `mv` below is atomic.
  SETTINGS_TMP="$HOME/.claude/settings.json.tmp"
  if jq '.outputStyle = "intuitive"' "$HOME/.claude/settings.json" > "$SETTINGS_TMP"; then
    mv "$SETTINGS_TMP" "$HOME/.claude/settings.json"
    echo "  Output style set to 'intuitive'"
  else
    rm -f "$SETTINGS_TMP"
    echo "  Skipped activation — ~/.claude/settings.json is not valid JSON"
  fi
else
  echo "  Skipped activation — no settings.json or no jq"
fi

# --- herdr Claude integration ---
# Runs last, after the settings.json copy: the integration writes a hook into
# ~/.claude/settings.json, which would flip that copy's `[ ! -f ]` guard and leave a
# fresh box without the dotfiles settings. It merges its key rather than clobbering,
# so the outputStyle written above survives.
echo ""
echo "Installing herdr Claude integration..."
# install.sh drops the binary here, and this shell never sourced a profile.
export PATH="$HOME/.local/bin:$PATH"
if command -v herdr &> /dev/null; then
  herdr integration install claude
else
  echo "  Skipped — herdr not on PATH"
fi
