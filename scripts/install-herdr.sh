#!/bin/bash

# Guard the download, unlike install-claude.sh: herdr self-updates via `herdr update`,
# so re-running the vendor installer on an existing box would fight that.
command -v herdr &> /dev/null && exit 0

curl -fsSL https://herdr.dev/install.sh | sh
