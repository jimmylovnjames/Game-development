#!/bin/bash
# NeonWastesRPG — macOS playtest installer (bash 3.2, the macOS system shell).
#
# Double-click "Play on Mac.command" in the repo, or run:
#   /bin/bash dist/macos/install.sh
#
# One-liner if you do not have the repo yet:
#   curl -fsSL https://raw.githubusercontent.com/jimmylovnjames/Game-development/claude/godot-cyberpunk-rpg-setup-xqy75h/dist/macos/install.sh | /bin/bash
#
# This downloads the official Godot 4.7.1 universal editor, imports this
# project, and installs ~/Applications/NeonWastesRPG.app so you can play.
# No Apple Developer ID is required; the launcher is ad-hoc signed on this Mac.
set -euo pipefail

GODOT_VERSION="4.7.1"
GODOT_TAG="4.7.1-stable"
GODOT_ZIP="Godot_v${GODOT_TAG}_macos.universal.zip"
GODOT_URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_TAG}/${GODOT_ZIP}"
GODOT_SHA512="a5c6443e193829de9a3237b57ef5e01c23839888900e241543da0dd4bac1050125e19469f0cca9a9958ac346070d98cab8e5d6aee16b181c6d06cda86bd07224"

REPO_URL="${NEONWASTES_REPO:-https://github.com/jimmylovnjames/Game-development.git}"
REPO_REF="${NEONWASTES_REF:-claude/godot-cyberpunk-rpg-setup-xqy75h}"

HOME_DIR="${HOME}"
INSTALL_ROOT="${NEONWASTES_HOME:-$HOME_DIR/Games/NeonWastesRPG}"
ENGINE_DIR="$INSTALL_ROOT/engine"
CACHE_DIR="$INSTALL_ROOT/cache"
APP_DIR="$HOME_DIR/Applications/NeonWastesRPG.app"
LOG_DIR="$HOME_DIR/Library/Logs"
LOG_FILE="$LOG_DIR/NeonWastesRPG.log"

DO_LAUNCH=1
DO_EDITOR=0
DO_REINSTALL=0
DO_UNINSTALL=0
SKIP_VERIFY=0

usage() {
	cat <<'EOF'
NeonWastesRPG macOS playtest installer

Usage: install.sh [options]

  --editor         Open the Godot editor instead of playing
  --skip-launch    Install / update, then exit without opening the game
  --reinstall      Re-download Godot 4.7.1 even if it is already cached
  --uninstall      Remove the playtest app, engine cache, and launcher
  --skip-verify    Do not run tools/verify_setup.gd after import
  -h, --help       Show this help

Environment:
  NEONWASTES_HOME  Install prefix (default: ~/Games/NeonWastesRPG)
  NEONWASTES_REPO  Git URL used when this script is not run from a checkout
  NEONWASTES_REF   Git branch / tag to clone (default: the project's main branch)
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--editor) DO_EDITOR=1 ;;
		--skip-launch) DO_LAUNCH=0 ;;
		--reinstall) DO_REINSTALL=1 ;;
		--uninstall) DO_UNINSTALL=1 ;;
		--skip-verify) SKIP_VERIFY=1 ;;
		-h|--help) usage; exit 0 ;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 2
			;;
	esac
	shift
done

say() { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Piped `curl | bash` has no script file on disk.
script_path=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
	script_path="${BASH_SOURCE[0]}"
elif [ -f "$0" ]; then
	script_path="$0"
fi

find_checkout() {
	local dir
	if [ -n "$script_path" ]; then
		dir=$(cd "$(dirname "$script_path")" && pwd)
		while [ "$dir" != "/" ]; do
			if [ -f "$dir/project.godot" ]; then
				printf '%s\n' "$dir"
				return 0
			fi
			dir=$(dirname "$dir")
		done
	fi
	if [ -f "$PWD/project.godot" ]; then
		pwd
		return 0
	fi
	return 1
}

macos_major() {
	sw_vers -productVersion | awk -F. '{ print $1 }'
}

remove_quarantine() {
	local target="$1"
	if command -v xattr >/dev/null 2>&1; then
		xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
	fi
}

adhoc_sign() {
	local target="$1"
	if command -v codesign >/dev/null 2>&1; then
		codesign --force --deep --sign - "$target" >/dev/null 2>&1 || true
	fi
}

uninstall_playtest() {
	step "Removing NeonWastesRPG playtest"
	rm -rf "$APP_DIR"
	rm -rf "$INSTALL_ROOT"
	say "Removed $APP_DIR"
	say "Removed $INSTALL_ROOT"
	say "The project checkout was left in place if you cloned it yourself."
}

write_launcher_app() {
	local project_dir="$1"
	local godot_bin="$2"
	local macos_dir plist launcher conf icon_src

	mkdir -p "$HOME_DIR/Applications"
	rm -rf "$APP_DIR"
	macos_dir="$APP_DIR/Contents/MacOS"
	mkdir -p "$macos_dir" "$APP_DIR/Contents/Resources"

	plist="$APP_DIR/Contents/Info.plist"
	cat >"$plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>NeonWastesRPG</string>
	<key>CFBundleIdentifier</key>
	<string>rpg.neonwastes.playtest</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>NeonWastesRPG</string>
	<key>CFBundleDisplayName</key>
	<string>NeonWastesRPG</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>0.1.0</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.games</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST
	printf 'APPL????' >"$APP_DIR/Contents/PkgInfo"

	conf="$APP_DIR/Contents/Resources/install.conf"
	{
		printf 'GODOT_BIN=%q\n' "$godot_bin"
		printf 'PROJECT_DIR=%q\n' "$project_dir"
	} >"$conf"

	icon_src="$(dirname "$godot_bin")/../Resources/Godot.icns"
	if [ -f "$icon_src" ]; then
		cp "$icon_src" "$APP_DIR/Contents/Resources/AppIcon.icns"
		# CFBundleIconFile is optional; Finder picks AppIcon.icns by convention
		# once we declare it.
		plutil -replace CFBundleIconFile -string AppIcon "$plist" 2>/dev/null || true
	fi

	launcher="$macos_dir/NeonWastesRPG"
	cat >"$launcher" <<'LAUNCH'
#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/Resources/install.conf"
mkdir -p "$HOME/Library/Logs"
LOG="$HOME/Library/Logs/NeonWastesRPG.log"
{
	echo "---- $(date) ----"
	echo "godot   $GODOT_BIN"
	echo "project $PROJECT_DIR"
} >>"$LOG"

if [ ! -x "$GODOT_BIN" ]; then
	osascript -e 'display alert "NeonWastesRPG" message "Godot is missing. Run Play on Mac.command again to reinstall." as critical' >/dev/null 2>&1 || true
	exit 1
fi
if [ ! -f "$PROJECT_DIR/project.godot" ]; then
	osascript -e 'display alert "NeonWastesRPG" message "The game project folder moved. Run Play on Mac.command from the repo to repair the launcher." as critical' >/dev/null 2>&1 || true
	exit 1
fi

if [ ! -d "$PROJECT_DIR/.godot" ]; then
	"$GODOT_BIN" --headless --path "$PROJECT_DIR" --import >>"$LOG" 2>&1 || true
fi

# Windowed + maximised so a 13-inch Air does not spawn a 1080p window off-screen.
# Extra args come from `open NeonWastesRPG.app --args --editor`.
exec "$GODOT_BIN" --path "$PROJECT_DIR" --windowed --maximized "$@" >>"$LOG" 2>&1
LAUNCH
	chmod +x "$launcher"

	remove_quarantine "$APP_DIR"
	adhoc_sign "$APP_DIR"
}

# ---------------------------------------------------------------------------

if [ "$(uname -s)" != "Darwin" ]; then
	die "This installer is for macOS. On this machine, use Godot 4.7.1 from the project README."
fi

if [ "$(macos_major)" -lt 11 ]; then
	die "macOS 11 (Big Sur) or newer is required for Godot 4.7."
fi

if [ "$DO_UNINSTALL" -eq 1 ]; then
	uninstall_playtest
	exit 0
fi

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v unzip >/dev/null 2>&1 || die "unzip is required"
command -v shasum >/dev/null 2>&1 || die "shasum is required"

step "NeonWastesRPG playtest for MacBook"
say "Godot $GODOT_VERSION universal (Apple Silicon + Intel)"
say "Install root: $INSTALL_ROOT"

PROJECT_DIR=""
if PROJECT_DIR=$(find_checkout); then
	say "Using existing project: $PROJECT_DIR"
else
	step "Fetching the game source"
	mkdir -p "$INSTALL_ROOT"
	PROJECT_DIR="$INSTALL_ROOT/game"
	if command -v git >/dev/null 2>&1; then
		if [ -d "$PROJECT_DIR/.git" ]; then
			git -C "$PROJECT_DIR" fetch --depth 1 origin "$REPO_REF"
			git -C "$PROJECT_DIR" checkout --force "FETCH_HEAD"
		else
			rm -rf "$PROJECT_DIR"
			git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$PROJECT_DIR"
		fi
	else
		say "git not found; downloading a source zip from GitHub"
		mkdir -p "$CACHE_DIR"
		zipball="$CACHE_DIR/game.zip"
		rm -rf "$CACHE_DIR/game-unpack"
		curl -fL --progress-bar -o "$zipball" \
			"https://codeload.github.com/jimmylovnjames/Game-development/zip/refs/heads/${REPO_REF}"
		unzip -q "$zipball" -d "$CACHE_DIR/game-unpack"
		extracted=""
		for candidate in "$CACHE_DIR/game-unpack"/*; do
			if [ -d "$candidate" ]; then
				extracted="$candidate"
				break
			fi
		done
		[ -n "$extracted" ] || die "could not unpack the GitHub zipball"
		rm -rf "$PROJECT_DIR"
		mv "$extracted" "$PROJECT_DIR"
		rm -rf "$CACHE_DIR/game-unpack"
	fi
	[ -f "$PROJECT_DIR/project.godot" ] || die "project.godot missing after fetch"
fi

GODOT_APP="$ENGINE_DIR/Godot.app"
GODOT_BIN="$GODOT_APP/Contents/MacOS/Godot"

need_godot=0
if [ "$DO_REINSTALL" -eq 1 ]; then
	need_godot=1
elif [ ! -x "$GODOT_BIN" ]; then
	need_godot=1
else
	ver=$("$GODOT_BIN" --version 2>/dev/null || true)
	case "$ver" in
		${GODOT_VERSION}*) ;;
		*) need_godot=1 ;;
	esac
fi

if [ "$need_godot" -eq 1 ]; then
	step "Downloading Godot ${GODOT_VERSION} (about 160 MB, once)"
	mkdir -p "$CACHE_DIR" "$ENGINE_DIR"
	zip_path="$CACHE_DIR/$GODOT_ZIP"
	curl -fL --progress-bar -o "$zip_path" "$GODOT_URL"
	actual=$(shasum -a 512 "$zip_path" | awk '{ print $1 }')
	if [ "$actual" != "$GODOT_SHA512" ]; then
		rm -f "$zip_path"
		die "Godot zip checksum mismatch (got $actual)"
	fi
	rm -rf "$GODOT_APP" "$ENGINE_DIR/unpack"
	mkdir -p "$ENGINE_DIR/unpack"
	unzip -q "$zip_path" -d "$ENGINE_DIR/unpack"
	found_app=""
	if [ -d "$ENGINE_DIR/unpack/Godot.app" ]; then
		found_app="$ENGINE_DIR/unpack/Godot.app"
	else
		for candidate in "$ENGINE_DIR/unpack"/*.app; do
			if [ -d "$candidate" ]; then
				found_app="$candidate"
				break
			fi
		done
	fi
	[ -n "$found_app" ] || die "Godot.app missing from the official zip"
	mv "$found_app" "$GODOT_APP"
	rm -rf "$ENGINE_DIR/unpack"
	remove_quarantine "$GODOT_APP"
	adhoc_sign "$GODOT_APP"
	chmod +x "$GODOT_BIN"
fi

[ -x "$GODOT_BIN" ] || die "Godot binary not executable at $GODOT_BIN"
say "Godot $($GODOT_BIN --version 2>/dev/null || echo "$GODOT_VERSION")"

step "Importing the project (first run compiles shaders and the class cache)"
"$GODOT_BIN" --headless --path "$PROJECT_DIR" --import

if [ "$SKIP_VERIFY" -eq 0 ] && [ -f "$PROJECT_DIR/tools/verify_setup.gd" ]; then
	step "Running the headless setup check"
	if ! "$GODOT_BIN" --headless --path "$PROJECT_DIR" --script "$PROJECT_DIR/tools/verify_setup.gd"; then
		say "Setup check reported problems. Launching anyway so you can see the game."
	fi
fi

step "Installing ~/Applications/NeonWastesRPG.app"
write_launcher_app "$PROJECT_DIR" "$GODOT_BIN"

say ""
say "Installed."
say "  App     $APP_DIR"
say "  Project $PROJECT_DIR"
say "  Log     $LOG_FILE"
say ""
say "Controls: WASD move · Shift sprint · Ctrl crouch · Space jump"
say "          E interact · F flashlight · T toggle daytime · RMB aim · Esc release mouse · F3 debug"
say ""
say "If macOS says the app cannot be opened: right-click NeonWastesRPG.app → Open."
say "On a MacBook Air the first shader compile can hitch; it settles after a minute."

if [ "$DO_LAUNCH" -eq 1 ]; then
	step "Launching"
	if [ "$DO_EDITOR" -eq 1 ]; then
		open "$APP_DIR" --args --editor
	else
		open "$APP_DIR"
	fi
	open -R "$APP_DIR" >/dev/null 2>&1 || true
fi
