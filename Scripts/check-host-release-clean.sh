#!/bin/bash
#
# Fails when a LookInside app build still carries DEBUG-only activation
# overrides, the DEBUG end-to-end dump, or a private key.
#
# Usage:
#   Scripts/check-host-release-clean.sh [--release-strict | --local-build] <LookInside.app|.xcarchive|.zip|.tar.gz|dir>...
#
# DEBUG builds of the activation package compile ActivationDebugOverrides,
# which reads LOOKINSIDE_ACTIVATION_API_BASE_URL (a different activation
# service) and LOOKINSIDE_ACTIVATION_TEST_ROOT_ID /
# LOOKINSIDE_ACTIVATION_TEST_ROOT_PUBLIC_KEY_PEM (an extra trusted root) from
# the environment, and the end-to-end dump (DebugE2E/: LKDebugE2EDump,
# LookinSnapshotNormalizer) reads LOOKINSIDE_DEBUG_E2E_*, and the UI
# snapshots (DebugE2E/: LKDebugUISnapshots, LKDebugWindowImage) read
# LOOKINSIDE_DEBUG_UI_SNAPSHOT_*. A Release build
# compiles them out; this check proves it on the shipped bundle.
#
# A path fails when any of the following holds:
#   - a file in it contains ActivationDebugOverrides, any
#     LOOKINSIDE_ACTIVATION_*, LOOKINSIDE_DEBUG_E2E_* or
#     LOOKINSIDE_DEBUG_UI_SNAPSHOT_* string, the LKDebugE2EDump,
#     LKDebugUISnapshots, LKDebugWindowImage or LookinSnapshotNormalizer
#     name, or a LookinServer
#     license test-hook
#     marker (test_setOverrideRootCertificateDER, sLKSTestOverrideRoot,
#     LOOKINSIDE_ENABLE_LICENSE_TEST_HOOKS); every byte of every file is
#     searched, so all architecture slices of the app binary, its frameworks,
#     helpers and resources are covered;
#   - the demangled symbol table of a Mach-O file names ActivationDebugOverrides
#     (Swift mangling can split the name, so the raw search alone is not enough);
#   - Scripts/scan-private-keys.sh finds a private key;
# --release-strict and --local-build are accepted for caller compatibility.
# A .zip or .tar.gz is unpacked into a temporary directory under
# CHECK_HOST_RELEASE_SCRATCH (default: $TMPDIR).
#
# Exit status: 0 clean, 1 an override or key was
# found, 2 on a usage error or when a path holds no Mach-O file to check.

set -uo pipefail

usage() {
	sed -n '2,41p' "$0" >&2
	exit 2
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	--release-strict) ;;
	--local-build) ;;
	-h | --help) usage ;;
	--)
		shift
		break
		;;
	-*)
		echo "Unknown option: $1" >&2
		usage
		;;
	*) break ;;
	esac
	shift
done
[ "$#" -gt 0 ] || usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/scan-private-keys.sh"
[ -f "$SCANNER" ] || {
	echo "Missing $SCANNER" >&2
	exit 2
}

SCRATCH_PARENT="${CHECK_HOST_RELEASE_SCRATCH:-${TMPDIR:-/tmp}}"
SCRATCH_PARENT="${SCRATCH_PARENT%/}"
mkdir -p "$SCRATCH_PARENT" || exit 2
WORK_DIR="$(mktemp -d "$SCRATCH_PARENT/check-host-release-clean.XXXXXX")" || exit 2
trap 'rm -rf "$WORK_DIR"' EXIT

MARKERS_RE='ActivationDebugOverrides|LOOKINSIDE_ACTIVATION_[A-Z0-9_]+|LOOKINSIDE_DEBUG_E2E_[A-Z0-9_]+|LOOKINSIDE_DEBUG_UI_SNAPSHOT_[A-Z0-9_]+|LKDebugE2EDump|LKDebugUISnapshots|LKDebugWindowImage|LookinSnapshotNormalizer|test_setOverrideRootCertificateDER|sLKSTestOverrideRoot|LOOKINSIDE_ENABLE_LICENSE_TEST_HOOKS'
SYMBOL_RE='ActivationDebugOverrides|LKDebugE2EDump|LKDebugUISnapshots|LKDebugWindowImage|LookinSnapshotNormalizer'

findings=0
usage_errors=0

report() {
	echo "FAIL: $1"
	findings=$((findings + 1))
}

demangle() {
	if xcrun --find swift-demangle >/dev/null 2>&1; then
		xcrun swift-demangle
	else
		cat
	fi
}

check_tree() {
	local root="$1" label="$2"
	local machos=0 file relative hits

	while IFS= read -r -d '' file; do
		relative="${file#"$root"/}"
		[ "$relative" = "$file" ] && relative="$(basename "$file")"

		hits="$(LC_ALL=C grep -a -o -E "$MARKERS_RE" "$file" 2>/dev/null | sort -u | tr '\n' ' ')"
		if [ -n "$hits" ]; then
			report "$label!$relative: contains ${hits% }"
		fi

		case "$(file -b "$file" 2>/dev/null)" in
		*Mach-O*) ;;
		*) continue ;;
		esac
		machos=$((machos + 1))
		hits="$(nm -a "$file" 2>/dev/null | demangle | grep -E -o "[^ ]*${SYMBOL_RE}[^ ]*" | sort -u | head -n 5 | tr '\n' ' ')"
		if [ -n "$hits" ]; then
			report "$label!$relative: symbols name ${hits% }"
		fi
	done < <(find "$root" -type f -print0)

	if [ "$machos" -eq 0 ]; then
		echo "ERROR: $label holds no Mach-O file to check" >&2
		usage_errors=$((usage_errors + 1))
		return
	fi
	echo "checked $machos Mach-O file(s) in $label"

	if ! bash "$SCANNER" "$root"; then
		report "$label: private key scan failed"
	fi

}

index=0
for path in "$@"; do
	index=$((index + 1))
	if [ -d "$path" ]; then
		check_tree "${path%/}" "$path"
		continue
	fi
	if [ ! -f "$path" ]; then
		echo "ERROR: $path does not exist" >&2
		usage_errors=$((usage_errors + 1))
		continue
	fi
	unpacked="$WORK_DIR/$index"
	mkdir -p "$unpacked"
	case "$path" in
	*.zip) ditto -x -k "$path" "$unpacked" ;;
	*.tar.gz | *.tgz) tar -xzf "$path" -C "$unpacked" ;;
	*)
		echo "ERROR: $path is not a directory, .zip or .tar.gz" >&2
		usage_errors=$((usage_errors + 1))
		continue
		;;
	esac || {
		report "$path: cannot unpack"
		continue
	}
	check_tree "$unpacked" "$path"
done

if [ "$findings" -gt 0 ]; then
	echo "host release check failed: $findings finding(s)"
	exit 1
fi
if [ "$usage_errors" -gt 0 ]; then
	exit 2
fi
echo "host release check passed: $*"
