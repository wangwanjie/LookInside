#!/bin/sh
set -eu

# Host-side MCPBridge tests.
#
# Same shape as test-security-gates.sh: compile the unit under test
# together with its test file into a standalone binary and run it. Only
# units that depend on Darwin / Foundation alone can be covered this
# way -- the routing services pull in AppKit, NSDocumentController and
# the inspector's documents, so they are exercised end to end against a
# running Host instead (see docs/mcp.md).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="${TMPDIR:-/tmp}/lookinside-mcp-bridge-tests.$$"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

LISTEN_SOCKET="$ROOT/LookInside/MCPBridge/MCPBridgeListenSocket.swift"
LISTEN_SOCKET_TEST="$ROOT/Tests/MCPBridge/MCPBridgeListenSocketTests.swift"

swiftc -parse-as-library "$LISTEN_SOCKET" "$LISTEN_SOCKET_TEST" -o "$TMPDIR/listen-socket-test"
"$TMPDIR/listen-socket-test"

SEARCH_QUERY="$ROOT/LookInside/MCPBridge/MCPBridgeSearchQuery.swift"
SEARCH_QUERY_TEST="$ROOT/Tests/MCPBridge/MCPBridgeSearchQueryTests.swift"

swiftc -parse-as-library "$SEARCH_QUERY" "$SEARCH_QUERY_TEST" -o "$TMPDIR/search-query-test"
"$TMPDIR/search-query-test"

node "$ROOT/Tests/MCP/lookinside-mcp-shim-search-tests.mjs" "$ROOT"
node "$ROOT/Tests/MCP/lookinside-mcp-shim-screenshot-tests.mjs" "$ROOT"
node "$ROOT/Tests/MCP/lookinside-mcp-shim-selectors-tests.mjs" "$ROOT"

# The identifier list needs MCPBridgeFrame.swift alongside it for
# MCPBridgeJSONValue; that file is Foundation-only, so it compiles here.
FRAME="$ROOT/LookInside/MCPBridge/MCPBridgeFrame.swift"
OBJECT_IDENTIFIER_LIST="$ROOT/LookInside/MCPBridge/MCPBridgeObjectIdentifierList.swift"
OBJECT_IDENTIFIER_LIST_TEST="$ROOT/Tests/MCPBridge/MCPBridgeObjectIdentifierListTests.swift"

swiftc -parse-as-library "$FRAME" "$OBJECT_IDENTIFIER_LIST" "$OBJECT_IDENTIFIER_LIST_TEST" -o "$TMPDIR/object-identifier-list-test"
"$TMPDIR/object-identifier-list-test"

RECOVERY_HINT="$ROOT/LookInside/MCPBridge/MCPBridgeRecoveryHint.swift"
RECOVERY_HINT_TEST="$ROOT/Tests/MCPBridge/MCPBridgeRecoveryHintTests.swift"

swiftc -parse-as-library "$RECOVERY_HINT" "$RECOVERY_HINT_TEST" -o "$TMPDIR/recovery-hint-test"
"$TMPDIR/recovery-hint-test"

DETAIL_OBJECT_IDENTIFIER_SELECTOR="$ROOT/LookInside/MCPBridge/LKMCPBridgeDetailObjectIdentifierSelector.swift"
DETAIL_OBJECT_IDENTIFIER_SELECTOR_TEST="$ROOT/Tests/MCPBridge/LKMCPBridgeDetailObjectIdentifierSelectorTests.swift"

swiftc -parse-as-library "$DETAIL_OBJECT_IDENTIFIER_SELECTOR" "$DETAIL_OBJECT_IDENTIFIER_SELECTOR_TEST" -o "$TMPDIR/detail-object-identifier-selector-test"
"$TMPDIR/detail-object-identifier-selector-test"

# Both RPC 203 routes must use the transport OID selector instead of the
# display OID exposed on the MCP wire.
for service in "$ROOT/LookInside/MCPBridge/MCPBridgeDetailsService.swift" "$ROOT/LookInside/MCPBridge/MCPBridgeScreenshotService.swift"; do
    if ! grep -Fq "hierarchyDetailsObjectIdentifier" "$service"; then
        echo "FAIL: $(basename "$service") must select an RPC 203-compatible object identifier" >&2
        exit 1
    fi
done

echo "MCPBridge tests passed"
