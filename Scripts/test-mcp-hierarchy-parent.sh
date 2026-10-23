#!/bin/bash

set -euo pipefail

script_root="$(cd "$(dirname "$0")/.." && pwd)"
test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/lookinside-mcp-parent-tests.XXXXXX")"
trap 'rm -rf "$test_tmp"' EXIT

xcrun swiftc -parse-as-library \
    -module-cache-path "$test_tmp/module-cache" \
    "$script_root/Tests/MCP/LKMCPHierarchyParentWiringTests.swift" \
    -o "$test_tmp/mcp-hierarchy-parent-wiring-tests"

"$test_tmp/mcp-hierarchy-parent-wiring-tests" "$script_root"
