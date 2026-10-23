#!/bin/bash

set -euo pipefail

script_root="$(cd "$(dirname "$0")/.." && pwd)"
reload_test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/lookinside-mcp-reload-tests.XXXXXX")"
trap 'rm -rf "$reload_test_tmp"' EXIT

mode="${1:-all}"

run_wiring_test() {
    local wiring_mode="$1"
    xcrun swiftc -parse-as-library \
        -module-cache-path "$reload_test_tmp/module-cache" \
        "$script_root/Tests/MCP/LKMCPHierarchyReloadWiringTests.swift" \
        -o "$reload_test_tmp/mcp-hierarchy-reload-wiring-tests"
    "$reload_test_tmp/mcp-hierarchy-reload-wiring-tests" "$script_root" "$wiring_mode"
}

case "$mode" in
    controller)
        run_wiring_test controller
        ;;
    bridge)
        run_wiring_test bridge
        ;;
    shim)
        node "$script_root/Tests/MCP/lookinside-mcp-shim-reload-tests.mjs" "$script_root"
        ;;
    *)
        echo "Unknown mode: $mode" >&2
        exit 2
        ;;
esac
