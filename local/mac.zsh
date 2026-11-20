# Mac only. setup.sh never installs this. Source it from ~/.zshrc.
# Needs: brew install fzf jq, and `coder config-ssh` for the `Host coder.*` block.

# Keep equal to HERDR_VERSION in scripts/install-herdr.sh.
HERDR_PIN="0.9.1"

_coder_ws_list() {
  coder list --output json | jq -r '.[] | "\(.name)\t\(.latest_build.status)"'
}

_coder_ws_pick() {
  _coder_ws_list | fzf --height=40% --reverse --prompt='coder workspace > ' | cut -f1
}

# Client here, server and agents on the box. Keys come from the box's config.toml.
dev() {
  [ -n "$HERDR_ENV" ] && { print -u2 "dev: already inside Herdr"; return 1; }
  local ws="${1:-$(_coder_ws_pick)}"
  [ -n "$ws" ] && herdr --remote "coder.$ws" --remote-keybindings server
}

dev-ssh() {
  local ws="${1:-$(_coder_ws_pick)}"
  [ -n "$ws" ] && ssh "coder.$ws"
}

dev-ls() { _coder_ws_list; }

dev-pin-herdr() {
  local version="${1:-$HERDR_PIN}" arch="aarch64"
  [ "$(uname -m)" = "x86_64" ] && arch="x86_64"
  mkdir -p ~/.local/bin
  curl -fsSLo ~/.local/bin/herdr.new \
    "https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-macos-${arch}" || return 1
  chmod +x ~/.local/bin/herdr.new
  mv ~/.local/bin/herdr.new ~/.local/bin/herdr
  # Gatekeeper kills curl-downloaded binaries until the quarantine flag is gone.
  xattr -d com.apple.quarantine ~/.local/bin/herdr 2> /dev/null
  hash -r
  herdr --version
}

dev-version() {
  local ws="${1:-$(_coder_ws_pick)}"
  [ -z "$ws" ] && return
  print "pin     $HERDR_PIN"
  print "local   $(herdr --version)"
  print "remote  $(ssh "coder.$ws" '$HOME/.local/bin/herdr --version')"
}
