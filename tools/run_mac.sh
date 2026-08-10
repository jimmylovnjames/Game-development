#!/usr/bin/env bash
# Launch NeonWastesRPG on macOS.
#
# Finds Godot whether it is on PATH or sitting in /Applications as an .app
# bundle, picks the Metal driver on Apple Silicon, and passes anything else
# straight through to the engine.
#
#   tools/run_mac.sh                    # play
#   tools/run_mac.sh --quality=potato   # force a graphics tier
#   tools/run_mac.sh --editor           # open the editor instead
#   tools/run_mac.sh --check            # run the headless test suites and exit
#
# Everything here also works by hand; this exists so there is one command to
# type rather than four flags to remember.

set -euo pipefail
cd "$(dirname "$0")/.."

find_godot() {
	if command -v godot >/dev/null 2>&1; then
		command -v godot
		return
	fi
	local candidate
	for candidate in \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot" \
		"/Applications/Godot_mono.app/Contents/MacOS/Godot"; do
		if [[ -x "$candidate" ]]; then
			echo "$candidate"
			return
		fi
	done
	return 1
}

if ! GODOT="$(find_godot)"; then
	cat >&2 <<'MSG'
Could not find Godot.

Download Godot 4.7.x (standard, not .NET) from https://godotengine.org/download/macos/
and drag it into /Applications. Then run this script again.

If you keep it elsewhere, put it on your PATH:
    sudo ln -s "/path/to/Godot.app/Contents/MacOS/Godot" /usr/local/bin/godot
MSG
	exit 1
fi

echo "godot   : $GODOT"
"$GODOT" --version 2>/dev/null | tail -1 | sed 's/^/version : /'

# Apple Silicon gets Godot's native Metal driver, which beats Vulkan through
# MoltenVK. Intel Macs have no Metal driver in Godot and must stay on Vulkan.
DRIVER_ARGS=()
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
	DRIVER_ARGS+=(--rendering-driver metal)
	echo "arch    : arm64 (Apple Silicon) — using the Metal driver"
else
	echo "arch    : $ARCH (Intel) — using the default driver"
	echo "          expect to need --quality=potato on this hardware"
fi

MODE="play"
PASSTHROUGH=()
for arg in "$@"; do
	case "$arg" in
		--editor) MODE="editor" ;;
		--check) MODE="check" ;;
		*) PASSTHROUGH+=("$arg") ;;
	esac
done

case "$MODE" in
	check)
		echo "--- import ---"
		"$GODOT" --headless --path . --import
		echo "--- verify_setup ---"
		"$GODOT" --headless --path . --script tools/verify_setup.gd
		echo "--- soak_test ---"
		"$GODOT" --headless --path . --script tools/soak_test.gd
		;;
	editor)
		exec "$GODOT" --path . --editor
		;;
	play)
		# The bare `--` separates engine flags from the game's own args, which is
		# how --quality reaches GraphicsSettings.
		if [[ ${#PASSTHROUGH[@]} -gt 0 ]]; then
			exec "$GODOT" --path . "${DRIVER_ARGS[@]}" -- "${PASSTHROUGH[@]}"
		fi
		exec "$GODOT" --path . "${DRIVER_ARGS[@]}"
		;;
esac
