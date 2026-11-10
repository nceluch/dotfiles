#!/bin/bash

if ! command -v npx &> /dev/null; then
  echo "  Skipped — npx not on PATH"
  exit 0
fi

# -g installs to ~/.claude/skills so every repo gets them. -s '*' takes every skill,
# including setup-matt-pocock-skills, which the upstream README says to keep.
npx -y skills@latest add mattpocock/skills -a claude-code -s '*' -g -y
