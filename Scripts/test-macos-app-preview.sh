#!/bin/bash

set -euo pipefail

script_root="$(cd "$(dirname "$0")/.." && pwd)"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/lookinside-macos-preview-tests.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT

xcrun swiftc -parse-as-library \
    -module-cache-path "$test_tmp/module-cache" \
    "$script_root/Tests/Scripts/LookinAppInfoMacScreenshotTests.swift" \
    -o "$test_tmp/lookinside-macos-preview-tests"
"$test_tmp/lookinside-macos-preview-tests" "$script_root"
