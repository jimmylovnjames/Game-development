#!/bin/bash
# Double-click this file in Finder to install and play NeonWastesRPG.
# If macOS blocks it: right-click → Open → Open.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "$DIR/dist/macos/install.sh" "$@"
