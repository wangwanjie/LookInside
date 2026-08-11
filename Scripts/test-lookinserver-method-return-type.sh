#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")/.."

build_dir="${TMPDIR:-/tmp}/lookinside-server-tests"
binary="$build_dir/LKSMethodReturnTypeTests"

mkdir -p "$build_dir"
xcrun clang \
	-fobjc-arc \
	-fmodules \
	-fmodules-cache-path="$build_dir/module-cache" \
	-Wall \
	-Wextra \
	-Werror \
	-framework Foundation \
	-I Sources/LookinServer/Server/Connection \
	Tests/Server/LKSMethodReturnTypeTests.m \
	-o "$binary"

"$binary"
