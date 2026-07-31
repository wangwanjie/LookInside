#!/bin/bash

set -euo pipefail

script_root="$(cd "$(dirname "$0")/.." && pwd)"
dashboard_test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/lookinside-dashboard-tests.XXXXXX")"
trap 'rm -rf "$dashboard_test_tmp"' EXIT

xcrun swiftc -parse-as-library \
    -module-cache-path "$dashboard_test_tmp/module-cache" \
    "$script_root/Tests/Dashboard/LKMCPObjectIdentifierFormatterStubs.swift" \
    "$script_root/LookInside/MCPBridge/LKMCPObjectIdentifierFormatter.swift" \
    "$script_root/Tests/Dashboard/LKMCPObjectIdentifierFormatterTests.swift" \
    -o "$dashboard_test_tmp/object-id-formatter-tests"
"$dashboard_test_tmp/object-id-formatter-tests"

xcrun swiftc -parse-as-library -framework AppKit \
    -module-cache-path "$dashboard_test_tmp/module-cache" \
    "$script_root/LookInside/Dashboard/LKDashboardObjectIDView.swift" \
    "$script_root/Tests/Dashboard/LKDashboardObjectIDViewTests.swift" \
    -o "$dashboard_test_tmp/object-id-view-tests"
"$dashboard_test_tmp/object-id-view-tests"
