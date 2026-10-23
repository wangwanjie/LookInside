#!/bin/zsh

set -euo pipefail

HOST_PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_SOURCE_ROOT="${LOOKINSIDE_SERVER_SOURCE_ROOT:-$HOST_PROJECT_DIR}"

if [ ! -d "$SERVER_SOURCE_ROOT/Sources/LookinServer/Server" ] ||
	! grep -q '"LookinServerDynamic"' "$SERVER_SOURCE_ROOT/Package.swift" 2>/dev/null; then
	echo "Cannot build the Server XCFramework: runtime sources are missing from $SERVER_SOURCE_ROOT." >&2
	echo "The host repository no longer contains LookinServerDynamic or Sources/LookinServer." >&2
	echo "Set LOOKINSIDE_SERVER_SOURCE_ROOT to a Server source checkout containing Sources/LookinServer and LookInside.xcworkspace." >&2
	exit 1
fi

cd "$SERVER_SOURCE_ROOT"

PROJECT_DIR="$PWD"
WORKSPACE_PATH="$PROJECT_DIR/LookInside.xcworkspace"

if [ ! -d "$WORKSPACE_PATH" ]; then
	echo "Missing Server workspace: $WORKSPACE_PATH" >&2
	exit 1
fi
CONFIGURATION="${CONFIGURATION:-Release}"
SKIP_BUILD="${SKIP_BUILD:-0}"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-12.0}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-11.0}"
MIN_MACCATALYST_VERSION="${MIN_MACCATALYST_VERSION:-13.0}"
USE_XCBEAUTIFY="${USE_XCBEAUTIFY:-1}"
RUNTIME_VARIANT="${RUNTIME_VARIANT:-standard}"
BUILD_LIBRARY_FOR_DISTRIBUTION="${BUILD_LIBRARY_FOR_DISTRIBUTION:-YES}"

case "$RUNTIME_VARIANT" in
standard | dynamic)
	DEFAULT_SCHEME="LookinServerDynamic"
	DEFAULT_FRAMEWORK_NAME="LookinServer"
	DEFAULT_PRODUCT_NAME="LookinServerDynamic"
	DEFAULT_OUTPUT_ROOT="$PROJECT_DIR/build/lookinserver"
	DEFAULT_DERIVED_ROOT="/tmp/LookinServerDynamicDD"
	COPY_RUNTIME_HEADERS=1
	SWIFT_HEADER_TARGET="LookinServerSwift"
	;;
injected)
	DEFAULT_SCHEME="LookinServerInjected"
	DEFAULT_FRAMEWORK_NAME="LookinServerInjected"
	DEFAULT_PRODUCT_NAME="LookinServerInjected"
	DEFAULT_OUTPUT_ROOT="$PROJECT_DIR/build/lookinserver-injected"
	DEFAULT_DERIVED_ROOT="/tmp/LookinServerInjectedDD"
	COPY_RUNTIME_HEADERS=0
	SWIFT_HEADER_TARGET=""
	;;
*)
	echo "Unsupported RUNTIME_VARIANT: $RUNTIME_VARIANT" >&2
	exit 1
	;;
esac

SCHEME="${SCHEME:-$DEFAULT_SCHEME}"
FRAMEWORK_NAME="${FRAMEWORK_NAME:-$DEFAULT_FRAMEWORK_NAME}"
PRODUCT_NAME="${PRODUCT_NAME:-$DEFAULT_PRODUCT_NAME}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$DEFAULT_OUTPUT_ROOT}"
DERIVED_ROOT="${DERIVED_ROOT:-$DEFAULT_DERIVED_ROOT}"

copy_public_headers() {
	local headers_dir="$1"

	mkdir -p "$headers_dir"

	while IFS= read -r -d '' header; do
		cp "$header" "$headers_dir/$(basename "$header")"
	done < <(
		find \
			"$PROJECT_DIR/Sources/LookinServer/Shared" \
			"$PROJECT_DIR/Sources/LookinServer/Server" \
			"$PROJECT_DIR/Sources/LookinServerBase" \
			-name '*.h' -print0
	)
}

write_modulemap() {
	local modules_dir="$1"

	mkdir -p "$modules_dir"
	cat >"$modules_dir/module.modulemap" <<'EOF'
framework module LookinServer {
  umbrella "../Headers"
  export *
  module * { export * }
}
EOF
}

run_xcodebuild() {
	if [ "$USE_XCBEAUTIFY" = "1" ] && command -v xcbeautify >/dev/null 2>&1; then
		xcodebuild "$@" 2>&1 | xcbeautify
	else
		xcodebuild "$@"
	fi
}

configuration_build_directory() {
	local sdk="$1"

	# SwiftPM uses a platform suffix for iOS and Mac Catalyst products, but not for macOS ones.
	if [ "$sdk" = "macosx" ]; then
		printf '%s\n' "$CONFIGURATION"
	else
		printf '%s-%s\n' "$CONFIGURATION" "$sdk"
	fi
}

framework_contents_directory() {
	local framework_dir="$1"

	if [ -d "$framework_dir/Versions/Current" ]; then
		printf '%s\n' "$framework_dir/Versions/Current"
	else
		printf '%s\n' "$framework_dir"
	fi
}

ensure_versioned_framework_directory_link() {
	local framework_dir="$1"
	local directory_name="$2"
	local root_path="$framework_dir/$directory_name"

	if [ ! -e "$root_path" ]; then
		ln -s "Versions/Current/$directory_name" "$root_path"
	fi
}

framework_info_plist_path() {
	local framework_dir="$1"
	local root_info_plist="$framework_dir/Info.plist"
	local versioned_info_plist="$framework_dir/Versions/Current/Resources/Info.plist"

	if [ -f "$root_info_plist" ]; then
		printf '%s\n' "$root_info_plist"
	elif [ -f "$versioned_info_plist" ]; then
		printf '%s\n' "$versioned_info_plist"
	else
		echo "Missing framework Info.plist: $framework_dir" >&2
		return 1
	fi
}

stage_framework_bundle() {
	local sdk="$1"
	local derived_dir="$2"
	local configuration_dir
	configuration_dir="$(configuration_build_directory "$sdk")"
	local release_dir="$derived_dir/Build/Products/$configuration_dir"
	local source_framework="$release_dir/PackageFrameworks/$PRODUCT_NAME.framework"
	local staged_root="$OUTPUT_ROOT/$sdk"
	local staged_framework="$staged_root/$FRAMEWORK_NAME.framework"
	local staged_binary="$staged_framework/$FRAMEWORK_NAME"
	local staged_dylib="$staged_root/$FRAMEWORK_NAME.dylib"
	local framework_contents_dir
	local framework_info_plist
	local swift_header=""
	local swift_header_dir
	local candidate
	local arch

	rm -rf "$staged_framework"
	mkdir -p "$staged_root"
	cp -R "$source_framework" "$staged_framework"
	framework_info_plist="$(framework_info_plist_path "$staged_framework")"
	framework_contents_dir="$(framework_contents_directory "$staged_framework")"

	if [ "$PRODUCT_NAME" != "$FRAMEWORK_NAME" ]; then
		if [ "$framework_contents_dir" = "$staged_framework" ]; then
			mv "$staged_framework/$PRODUCT_NAME" "$staged_binary"
		else
			mv "$framework_contents_dir/$PRODUCT_NAME" "$framework_contents_dir/$FRAMEWORK_NAME"
			rm "$staged_framework/$PRODUCT_NAME"
			ln -s "Versions/Current/$FRAMEWORK_NAME" "$staged_binary"
		fi
	else
		staged_binary="$staged_framework/$PRODUCT_NAME"
	fi

	/usr/libexec/PlistBuddy \
		-c "Set :CFBundleExecutable $FRAMEWORK_NAME" \
		-c "Set :CFBundleName $FRAMEWORK_NAME" \
		-c "Set :CFBundleIdentifier lookinside.$FRAMEWORK_NAME" \
		"$framework_info_plist"

	if [ "$COPY_RUNTIME_HEADERS" = "1" ]; then
		copy_public_headers "$framework_contents_dir/Headers"

		swift_header_dir="$derived_dir/Build/Intermediates.noindex/LookInside.build/$configuration_dir/$SWIFT_HEADER_TARGET.build/Objects-normal"
		for arch in arm64 x86_64; do
			candidate="$swift_header_dir/$arch/$SWIFT_HEADER_TARGET-Swift.h"
			if [ -f "$candidate" ]; then
				swift_header="$candidate"
				break
			fi
		done
		if [ -z "$swift_header" ]; then
			echo "Missing generated Swift header for $sdk: $swift_header_dir" >&2
			return 1
		fi
		cp "$swift_header" "$framework_contents_dir/Headers/$FRAMEWORK_NAME-Swift.h"

		write_modulemap "$framework_contents_dir/Modules"

		if [ "$framework_contents_dir" != "$staged_framework" ]; then
			ensure_versioned_framework_directory_link "$staged_framework" Headers
			ensure_versioned_framework_directory_link "$staged_framework" Modules
		fi
	fi

	install_name_tool -id "@rpath/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME" "$staged_binary"

	cp "$staged_binary" "$staged_dylib"
	install_name_tool -id "@rpath/$FRAMEWORK_NAME.dylib" "$staged_dylib"
}

build_sdk() {
	local sdk="$1"
	local derived_dir="$DERIVED_ROOT/$sdk"
	local -a platform_settings
	local -a platform_selector

	case "$sdk" in
	iphoneos | iphonesimulator)
		platform_selector=(
			-sdk "$sdk"
		)
		platform_settings=(
			IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS_VERSION"
		)
		;;
	macosx)
		platform_selector=(
			-sdk "$sdk"
		)
		platform_settings=(
			MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS_VERSION"
			ARCHS="arm64 x86_64"
			ONLY_ACTIVE_ARCH=NO
		)
		;;
	maccatalyst)
		platform_selector=(
			-destination "generic/platform=macOS,variant=Mac Catalyst"
		)
		platform_settings=(
			IPHONEOS_DEPLOYMENT_TARGET="$MIN_MACCATALYST_VERSION"
			ARCHS="arm64 x86_64"
			ONLY_ACTIVE_ARCH=NO
		)
		;;
	*)
		echo "Unsupported SDK: $sdk" >&2
		return 1
		;;
	esac

	run_xcodebuild \
		-workspace "$WORKSPACE_PATH" \
		-scheme "$SCHEME" \
		-configuration "$CONFIGURATION" \
		"${platform_selector[@]}" \
		-derivedDataPath "$derived_dir" \
		CODE_SIGNING_ALLOWED=NO \
		SKIP_INSTALL=NO \
		BUILD_LIBRARY_FOR_DISTRIBUTION="$BUILD_LIBRARY_FOR_DISTRIBUTION" \
		"${platform_settings[@]}" \
		build
}

mkdir -p "$OUTPUT_ROOT"

if [ "$SKIP_BUILD" != "1" ]; then
	build_sdk iphoneos
	build_sdk iphonesimulator
	build_sdk macosx
	build_sdk maccatalyst
fi

stage_framework_bundle iphoneos "$DERIVED_ROOT/iphoneos"
stage_framework_bundle iphonesimulator "$DERIVED_ROOT/iphonesimulator"
stage_framework_bundle macosx "$DERIVED_ROOT/macosx"
stage_framework_bundle maccatalyst "$DERIVED_ROOT/maccatalyst"

rm -rf "$OUTPUT_ROOT/$FRAMEWORK_NAME.xcframework"
run_xcodebuild -create-xcframework \
	-framework "$OUTPUT_ROOT/iphoneos/$FRAMEWORK_NAME.framework" \
	-framework "$OUTPUT_ROOT/iphonesimulator/$FRAMEWORK_NAME.framework" \
	-framework "$OUTPUT_ROOT/macosx/$FRAMEWORK_NAME.framework" \
	-framework "$OUTPUT_ROOT/maccatalyst/$FRAMEWORK_NAME.framework" \
	-output "$OUTPUT_ROOT/$FRAMEWORK_NAME.xcframework"

echo "Packaged artifacts under $OUTPUT_ROOT"
