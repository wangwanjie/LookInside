#!/bin/zsh

set -euo pipefail

cd "$(dirname "$0")/.."

export FRAMEWORK_NAME="${LOOKINSIDE_SERVER_FRAMEWORK_NAME:-LookInsideServer}"
export SCHEME="${LOOKINSIDE_SERVER_SCHEME:-LookinServerDynamic}"
export PRODUCT_NAME="${LOOKINSIDE_SERVER_PRODUCT_NAME:-LookinServerDynamic}"
export OUTPUT_ROOT="${OUTPUT_ROOT:-$PWD/build/lookinside-server}"
export DERIVED_ROOT="${DERIVED_ROOT:-/tmp/LookInsideServerDD}"
export BUILD_LIBRARY_FOR_DISTRIBUTION="${BUILD_LIBRARY_FOR_DISTRIBUTION:-NO}"

zsh Scripts/package-lookinserver.sh

rm -rf "$PWD/LookInsideServer.xcframework"
cp -R "$OUTPUT_ROOT/LookInsideServer.xcframework" "$PWD/LookInsideServer.xcframework"

echo "Copied LookInsideServer.xcframework to $PWD/LookInsideServer.xcframework"
