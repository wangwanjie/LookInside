#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")/.."

build_dir="${TMPDIR:-/tmp}/lookinside-server-tests"
binary="$build_dir/LKSObjectRegistrySnapshotTests"

mkdir -p "$build_dir"
xcrun clang \
	-fobjc-arc \
	-fmodules \
	-fmodules-cache-path="$build_dir/module-cache" \
	-Wall \
	-Wextra \
	-Werror \
	-DSHOULD_COMPILE_LOOKIN_SERVER=1 \
	-framework Foundation \
	-I Sources/LookinServer/Server/Others \
	Tests/Server/LKSObjectRegistrySnapshotTests.m \
	Sources/LookinServer/Server/Others/LKS_ObjectRegistry.m \
	-o "$binary"

"$binary"
