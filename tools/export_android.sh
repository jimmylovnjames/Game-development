#!/usr/bin/env bash
# Headless Android APK export for NeonWastesRPG.
#
# Usage:
#   GODOT=godot ./tools/export_android.sh
#
# Writes a debug-signed playtest APK to build/android/NeonWastesRPG.apk.
# Copies tools/android_export_presets.cfg over export_presets.cfg for the
# duration of the export so keystore paths never have to live in git.
#
# Requires:
#   - Godot 4.7.1 with Android export templates
#   - Android SDK (ANDROID_HOME or ANDROID_SDK_ROOT) with build-tools
#   - A debug keystore (generated automatically if missing)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT:-godot}"
OUT_DIR="$ROOT/build/android"
OUT_APK="$OUT_DIR/NeonWastesRPG.apk"
PRESET_SRC="$ROOT/tools/android_export_presets.cfg"
PRESET_DST="$ROOT/export_presets.cfg"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [ ! -x "$GODOT_BIN" ]; then
	echo "ERROR: Godot binary not found (set GODOT=...)." >&2
	exit 1
fi

ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${ANDROID_SDK:-}}}"
if [ -z "$ANDROID_SDK" ]; then
	for candidate in \
		"$HOME/Android/Sdk" \
		"$HOME/Library/Android/sdk" \
		"/usr/lib/android-sdk"
	do
		if [ -d "$candidate/platform-tools" ]; then
			ANDROID_SDK="$candidate"
			break
		fi
	done
fi
if [ -z "$ANDROID_SDK" ] || [ ! -d "$ANDROID_SDK/platform-tools" ]; then
	echo "ERROR: Android SDK not found. Set ANDROID_HOME to a SDK with platform-tools." >&2
	exit 1
fi

JAVA_HOME_RESOLVED="${JAVA_HOME:-}"
if [ -z "$JAVA_HOME_RESOLVED" ]; then
	if command -v /usr/libexec/java_home >/dev/null 2>&1; then
		JAVA_HOME_RESOLVED="$(/usr/libexec/java_home 2>/dev/null || true)"
	fi
	if [ -z "$JAVA_HOME_RESOLVED" ]; then
		for candidate in \
			/usr/lib/jvm/java-17-openjdk-amd64 \
			/usr/lib/jvm/java-21-openjdk-amd64 \
			/usr/lib/jvm/default-java
		do
			if [ -x "$candidate/bin/java" ]; then
				JAVA_HOME_RESOLVED="$candidate"
				break
			fi
		done
	fi
fi
if [ -z "$JAVA_HOME_RESOLVED" ]; then
	echo "ERROR: JAVA_HOME not set and no JDK found." >&2
	exit 1
fi

DEBUG_KEYSTORE="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-$HOME/.android/debug.keystore}"
if [ ! -f "$DEBUG_KEYSTORE" ]; then
	mkdir -p "$(dirname "$DEBUG_KEYSTORE")"
	keytool -genkeypair -alias androiddebugkey -keyalg RSA -keysize 2048 \
		-validity 10000 -keystore "$DEBUG_KEYSTORE" \
		-storepass android -keypass android \
		-dname "CN=Android Debug,O=Android,C=US"
fi
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$DEBUG_KEYSTORE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-androiddebugkey}"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-android}"

# Editor settings live outside the project; write the SDK paths Godot needs.
GODOT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
mkdir -p "$GODOT_CONFIG_DIR"
SETTINGS="$GODOT_CONFIG_DIR/editor_settings-4.5.tres"
# 4.7 still reads editor_settings-4.5.tres; also write a 4.7-named copy.
for settings_file in \
	"$GODOT_CONFIG_DIR/editor_settings-4.5.tres" \
	"$GODOT_CONFIG_DIR/editor_settings-4.4.tres" \
	"$GODOT_CONFIG_DIR/editor_settings-4.tres"
do
	if [ ! -f "$settings_file" ]; then
		cat > "$settings_file" <<EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "$JAVA_HOME_RESOLVED"
export/android/android_sdk_path = "$ANDROID_SDK"
export/android/debug_keystore = "$DEBUG_KEYSTORE"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF
	else
		python3 - "$settings_file" "$JAVA_HOME_RESOLVED" "$ANDROID_SDK" "$DEBUG_KEYSTORE" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
java, sdk, keystore = sys.argv[2], sys.argv[3], sys.argv[4]
text = path.read_text()
replacements = {
	"export/android/java_sdk_path": java,
	"export/android/android_sdk_path": sdk,
	"export/android/debug_keystore": keystore,
	"export/android/debug_keystore_user": "androiddebugkey",
	"export/android/debug_keystore_pass": "android",
}
lines = text.splitlines()
keys_seen = set()
out = []
for line in lines:
	written = False
	for key, value in replacements.items():
		if line.startswith(key + " =") or line.startswith(key + "="):
			out.append(f'{key} = "{value}"')
			keys_seen.add(key)
			written = True
			break
	if not written:
		out.append(line)
if "[resource]" in text:
	missing = [k for k in replacements if k not in keys_seen]
	if missing:
		patched = []
		for line in out:
			patched.append(line)
			if line.strip() == "[resource]":
				for key in missing:
					patched.append(f'{key} = "{replacements[key]}"')
		out = patched
path.write_text("\n".join(out) + "\n")
PY
	fi
done

mkdir -p "$OUT_DIR"
rm -f "$OUT_APK"

cp "$PRESET_SRC" "$PRESET_DST"
cleanup() {
	rm -f "$PRESET_DST"
}
trap cleanup EXIT

echo "==> import"
"$GODOT_BIN" --headless --path "$ROOT" --import

echo "==> export-debug Android -> $OUT_APK"
"$GODOT_BIN" --headless --path "$ROOT" --export-debug "Android" "$OUT_APK"

if [ ! -f "$OUT_APK" ]; then
	echo "ERROR: export did not produce $OUT_APK" >&2
	exit 1
fi

echo "==> $OUT_APK ($(wc -c <"$OUT_APK") bytes)"
file "$OUT_APK" || true
