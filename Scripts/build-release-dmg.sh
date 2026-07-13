#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT_ROOT="$PWD"
PROJECT_FILE="$PROJECT_ROOT/LookInside.xcodeproj"
SCHEME="LookInside"
CONFIGURATION="Release"
OUTPUT_ROOT="$PROJECT_ROOT/build/releases/manual"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/LookInsideReleaseDerivedData}"
ARCHIVE_PATH=""
DMG_PATH=""
CODE_SIGNING_ALLOWED="NO"
SKIP_INJECTOR_CHECK=false
ALLOW_MISSING_INJECTOR=false

usage() {
	cat <<'EOF'
Usage: bash Scripts/build-release-dmg.sh [options]

Options:
  --output-root <path>       Output directory. Default: build/releases/manual
  --derived-data-path <path> DerivedData directory. Default: /tmp/LookInsideReleaseDerivedData
  --archive-path <path>      Archive output path. Default: <output-root>/LookInside.xcarchive
  --dmg-path <path>          DMG output path. Default: <output-root>/LookInside.dmg
  --configuration <name>     Xcode configuration. Default: Release
  --signed                   Allow normal project code signing instead of CODE_SIGNING_ALLOWED=NO
  --skip-injector-check      Do not preflight-check ../LookInside-Injector
  --allow-missing-injector   Build without embedding LookInside-Injector when the sibling repo is missing
  --help, -h                 Show this help.
EOF
}

log() {
	echo "==> $*"
}

fail() {
	echo "Error: $*" >&2
	exit 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--output-root)
			OUTPUT_ROOT="${2:-}"
			shift 2
			;;
		--derived-data-path)
			DERIVED_DATA_PATH="${2:-}"
			shift 2
			;;
		--archive-path)
			ARCHIVE_PATH="${2:-}"
			shift 2
			;;
		--dmg-path)
			DMG_PATH="${2:-}"
			shift 2
			;;
		--configuration)
			CONFIGURATION="${2:-}"
			shift 2
			;;
		--signed)
			CODE_SIGNING_ALLOWED="YES"
			shift
			;;
		--skip-injector-check)
			SKIP_INJECTOR_CHECK=true
			shift
			;;
		--allow-missing-injector)
			ALLOW_MISSING_INJECTOR=true
			SKIP_INJECTOR_CHECK=true
			shift
			;;
		--help | -h)
			usage
			exit 0
			;;
		*)
			fail "Unknown option: $1"
			;;
		esac
	done
}

absolute_path() {
	local path="$1"
	if [[ "$path" = /* ]]; then
		printf "%s\n" "$path"
	else
		printf "%s\n" "$PROJECT_ROOT/$path"
	fi
}

preflight() {
	require_command xcodebuild
	require_command ditto
	require_command hdiutil

	[[ -d "$PROJECT_FILE" ]] || fail "Project not found at $PROJECT_FILE"

	if [[ "$CONFIGURATION" == "Release" && "$SKIP_INJECTOR_CHECK" != "true" ]]; then
		[[ -d "$PROJECT_ROOT/../LookInside-Injector" ]] || fail "Release builds require ../LookInside-Injector. Clone or place LookInside-Injector next to this repo, or pass --skip-injector-check to let xcodebuild report the project error."
	fi
}

archive_app() {
	log "Archiving $SCHEME ($CONFIGURATION)"
	rm -rf "$ARCHIVE_PATH" "$DERIVED_DATA_PATH"

	local allow_missing_injector
	allow_missing_injector=0
	[[ "$ALLOW_MISSING_INJECTOR" == "true" ]] && allow_missing_injector=1

	LOOKINSIDE_ALLOW_MISSING_INJECTOR="$allow_missing_injector" xcodebuild \
		-skipMacroValidation \
		-project "$PROJECT_FILE" \
		-scheme "$SCHEME" \
		-configuration "$CONFIGURATION" \
		-destination "generic/platform=macOS" \
		-derivedDataPath "$DERIVED_DATA_PATH" \
		-archivePath "$ARCHIVE_PATH" \
		CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
		archive
}

create_dmg() {
	local app_path="$ARCHIVE_PATH/Products/Applications/LookInside.app"
	local staging_dir="$OUTPUT_ROOT/dmg-staging"

	[[ -d "$app_path" ]] || fail "Archived app not found at $app_path"

	log "Preparing DMG staging directory"
	rm -rf "$staging_dir"
	mkdir -p "$staging_dir"
	ditto "$app_path" "$staging_dir/LookInside.app"
	ln -s /Applications "$staging_dir/Applications"

	log "Creating DMG"
	rm -f "$DMG_PATH"
	hdiutil create \
		-volname "LookInside" \
		-srcfolder "$staging_dir" \
		-ov \
		-format UDZO \
		"$DMG_PATH"

	log "DMG created: $DMG_PATH"
}

parse_args "$@"

OUTPUT_ROOT="$(absolute_path "$OUTPUT_ROOT")"
ARCHIVE_PATH="$(absolute_path "${ARCHIVE_PATH:-$OUTPUT_ROOT/LookInside.xcarchive}")"
DMG_PATH="$(absolute_path "${DMG_PATH:-$OUTPUT_ROOT/LookInside.dmg}")"

mkdir -p "$OUTPUT_ROOT"

preflight
archive_app
create_dmg
