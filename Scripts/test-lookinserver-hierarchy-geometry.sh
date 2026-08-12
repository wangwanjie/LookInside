#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")/.."

build_dir="${TMPDIR:-/tmp}/lookinside-server-tests"
binary="$build_dir/LKSHierarchyGeometryTests"

mkdir -p "$build_dir"
xcrun clang \
	-fobjc-arc \
	-fmodules \
	-fmodules-cache-path="$build_dir/module-cache" \
	-Wall \
	-Wextra \
	-Werror \
	-framework Foundation \
	-I Sources/LookinServer/Server/Others \
	Tests/Server/LKSHierarchyGeometryTests.m \
	-o "$binary"

"$binary"
