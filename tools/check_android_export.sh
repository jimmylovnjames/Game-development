#!/usr/bin/env bash
# Static checks for the Android playtest export. No Godot required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILS=0

ok() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILS=$((FAILS + 1)); }

echo "[android export]"

for path in \
	"tools/export_android.sh" \
	"tools/android_export_presets.cfg" \
	"tools/check_android_export.sh" \
	".github/workflows/android-playtest.yml" \
	"dist/android/README.md" \
	"scenes/ui/touch_controls.tscn" \
	"scripts/ui/touch_controls.gd" \
	"assets/icons/android/icon_192.png" \
	"assets/icons/android/adaptive_fg_432.png" \
	"assets/icons/android/adaptive_bg_432.png"
do
	if [ -e "$ROOT/$path" ]; then
		ok "present: $path"
	else
		fail "missing: $path"
	fi
done

for path in "tools/export_android.sh" "tools/check_android_export.sh"; do
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

if grep -q 'rpg.neonwastes.playtest' "$ROOT/tools/android_export_presets.cfg"; then
	ok "package rpg.neonwastes.playtest is set"
else
	fail "package unique_name missing"
fi

if grep -q 'gradle_build/use_gradle_build=false' "$ROOT/tools/android_export_presets.cfg" \
	&& grep -q 'gradle_build/min_sdk=""' "$ROOT/tools/android_export_presets.cfg"; then
	ok "uses prebuilt Android export templates (no Gradle project in-tree)"
else
	fail "expected gradle_build/use_gradle_build=false and empty min_sdk override"
fi

if grep -q 'architectures/arm64-v8a=true' "$ROOT/tools/android_export_presets.cfg"; then
	ok "exports arm64-v8a"
else
	fail "arm64-v8a is not enabled"
fi

if grep -q 'window/handheld/orientation=4' "$ROOT/project.godot"; then
	ok "project is sensor-landscape for phones"
else
	fail "project.godot must set display/window/handheld/orientation=4"
fi

if grep -q 'textures/vram_compression/import_etc2_astc=true' "$ROOT/project.godot"; then
	ok "project enables ETC2/ASTC (required for Android)"
else
	fail "project.godot must set rendering/textures/vram_compression/import_etc2_astc=true"
fi

if grep -q 'class_name TouchControls' "$ROOT/scripts/ui/touch_controls.gd"; then
	ok "TouchControls script is present"
else
	fail "TouchControls class missing"
fi

if grep -q 'touch_controls.tscn' "$ROOT/scenes/main.tscn"; then
	ok "main scene instances the touch HUD"
else
	fail "main.tscn does not instance touch_controls.tscn"
fi

echo
if [ "$FAILS" -eq 0 ]; then
	echo "ANDROID CHECK: all checks passed."
	exit 0
fi
echo "ANDROID CHECK: $FAILS check(s) FAILED."
exit 1
