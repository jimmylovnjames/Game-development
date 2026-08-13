#!/usr/bin/env bash
# Headless macOS export for NeonWastesRPG.
#
# Usage:
#   GODOT=godot ./tools/export_macos.sh
#
# Writes build/macos/NeonWastesRPG.zip (universal .app inside). Copies
# tools/macos_export_presets.cfg over export_presets.cfg for the duration of
# the export so signing secrets never have to live in git.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT:-godot}"
GODOT_VERSION_EXPECTED="${GODOT_VERSION_EXPECTED:-4.7.1}"
OUT_DIR="$ROOT/build/macos"
OUT_ZIP="$OUT_DIR/NeonWastesRPG.zip"
PRESET_SRC="$ROOT/tools/macos_export_presets.cfg"
PRESET_DST="$ROOT/export_presets.cfg"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [ ! -x "$GODOT_BIN" ]; then
	echo "ERROR: Godot binary not found (set GODOT=...)." >&2
	exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_ZIP"

cp "$PRESET_SRC" "$PRESET_DST"
cleanup() {
	rm -f "$PRESET_DST"
}
trap cleanup EXIT

echo "==> import"
"$GODOT_BIN" --headless --path "$ROOT" --import

echo "==> export-release macOS -> $OUT_ZIP"
"$GODOT_BIN" --headless --path "$ROOT" --export-release "macOS" "$OUT_ZIP"

if [ ! -f "$OUT_ZIP" ]; then
	echo "ERROR: export did not produce $OUT_ZIP" >&2
	exit 1
fi

echo "==> $OUT_ZIP ($(wc -c <"$OUT_ZIP") bytes)"
unzip -l "$OUT_ZIP" | sed -n '1,40p'
