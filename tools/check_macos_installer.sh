#!/usr/bin/env bash
# Static checks for the macOS playtest installer. No Godot required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILS=0

ok() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILS=$((FAILS + 1)); }

echo "[macos installer]"

for path in \
	"Play on Mac.command" \
	"dist/macos/install.sh" \
	"dist/macos/README.md" \
	"tools/export_macos.sh" \
	"tools/macos_export_presets.cfg" \
	".github/workflows/macos-playtest.yml"
do
	if [ -e "$ROOT/$path" ]; then
		ok "present: $path"
	else
		fail "missing: $path"
	fi
done

for path in "Play on Mac.command" "dist/macos/install.sh" "tools/export_macos.sh" "tools/check_macos_installer.sh"; do
	if [ -x "$ROOT/$path" ]; then
		ok "executable: $path"
	else
		fail "not executable: $path"
	fi
	if bash -n "$ROOT/$path"; then
		ok "bash -n: $path"
	else
		fail "bash -n failed: $path"
	fi
done

if grep -q 'rpg.neonwastes.playtest' "$ROOT/dist/macos/install.sh" \
	&& grep -q 'rpg.neonwastes.playtest' "$ROOT/tools/macos_export_presets.cfg"; then
	ok "bundle id rpg.neonwastes.playtest is consistent"
else
	fail "bundle id missing or mismatched"
fi

if grep -q 'GODOT_TAG="4.7.1-stable"' "$ROOT/dist/macos/install.sh" \
	&& grep -q 'macos.universal.zip' "$ROOT/dist/macos/install.sh"; then
	ok "installer pins Godot 4.7.1 universal"
else
	fail "installer does not pin Godot 4.7.1 universal"
fi

if grep -q 'codesign/codesign=1' "$ROOT/tools/macos_export_presets.cfg"; then
	ok "export preset uses built-in ad-hoc codesign"
else
	fail "export preset is not ad-hoc signed"
fi

if grep -q 'textures/vram_compression/import_etc2_astc=true' "$ROOT/project.godot"; then
	ok "project enables ETC2/ASTC (required for Apple Silicon export)"
else
	fail "project.godot must set rendering/textures/vram_compression/import_etc2_astc=true"
fi

echo
if [ "$FAILS" -eq 0 ]; then
	echo "INSTALLER CHECK: all checks passed."
	exit 0
fi
echo "INSTALLER CHECK: $FAILS check(s) FAILED."
exit 1
