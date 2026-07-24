#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="$ROOT_DIR/Scripts/check-lookinside-device-port.sh"
TEST_TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lookinside-port-tests.XXXXXX")"
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
    rm -rf "$TEST_TMP_ROOT"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    printf 'PASS: %s\n' "$1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

assert_status() {
    expected="$1"
    actual="$2"
    name="$3"
    if [ "$actual" -eq "$expected" ]; then
        pass "$name"
    else
        fail "$name (expected status $expected, got $actual)"
    fi
}

assert_contains() {
    haystack="$1"
    needle="$2"
    name="$3"
    case "$haystack" in
        *"$needle"*) pass "$name" ;;
        *) fail "$name (missing: $needle)" ;;
    esac
}

make_fake_bin() {
    case_dir="$1"
    fake_bin="$case_dir/bin"
    mkdir -p "$fake_bin"

    cat >"$fake_bin/idevice_id" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-l" ]; then
    printf '%s\n' "${FAKE_DEVICE_IDS:-}"
    exit "${FAKE_IDEVICE_STATUS:-0}"
fi
exit 2
EOF

    cat >"$fake_bin/xcrun" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_COREDEVICE_OUTPUT:-CoreDevice fixture}"
exit "${FAKE_COREDEVICE_STATUS:-0}"
EOF

    cat >"$fake_bin/iproxy" <<'EOF'
#!/usr/bin/env bash
if [ -n "${FAKE_IPROXY_PID_FILE:-}" ]; then
    printf '%s\n' "$$" >"$FAKE_IPROXY_PID_FILE"
fi
trap 'exit 0' INT TERM
while :; do
    /bin/sleep 1
done
EOF

    cat >"$fake_bin/nc" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-z" ]; then
    case ",${FAKE_BUSY_LOCAL_PORTS:-}," in
        *",${3:-},"*) exit 0 ;;
        *) exit 1 ;;
    esac
fi
local_port="${2:-}"
if [ "$local_port" = "${FAKE_OPEN_LOCAL_PORT:-}" ]; then
    /bin/sleep "${FAKE_NC_HOLD_SECONDS:-1}"
    exit 0
fi
exit 1
EOF

    chmod +x "$fake_bin/idevice_id" "$fake_bin/xcrun" "$fake_bin/iproxy" "$fake_bin/nc"
    printf '%s\n' "$fake_bin"
}

run_script() {
    case_name="$1"
    shift
    case_dir="$TEST_TMP_ROOT/$case_name"
    mkdir -p "$case_dir"
    fake_bin="$(make_fake_bin "$case_dir")"
    output_file="$case_dir/output"

    set +e
    PATH="$fake_bin:/usr/bin:/bin" \
        LOOKINSIDE_IPROXY_STARTUP_SECONDS=0.01 \
        LOOKINSIDE_PROBE_SETTLE_SECONDS=0.05 \
        LOOKINSIDE_PROBE_HOLD_SECONDS=1 \
        "$SCRIPT_PATH" "$@" >"$output_file" 2>&1
    RUN_STATUS=$?
    set -e
    RUN_OUTPUT="$(cat "$output_file")"
}

test_help() {
    FAKE_DEVICE_IDS=""
    export FAKE_DEVICE_IDS
    run_script help --help
    assert_status 0 "$RUN_STATUS" "help exits successfully"
    assert_contains "$RUN_OUTPUT" "Usage:" "help prints usage"
}

test_no_device() {
    FAKE_DEVICE_IDS=""
    export FAKE_DEVICE_IDS
    run_script no-device
    assert_status 1 "$RUN_STATUS" "no USB device fails"
    assert_contains "$RUN_OUTPUT" "No USB iOS device" "no USB device explains failure"
}

test_multiple_devices_require_udid() {
    FAKE_DEVICE_IDS="$(printf 'device-a\ndevice-b\n')"
    export FAKE_DEVICE_IDS
    run_script multiple-devices
    assert_status 1 "$RUN_STATUS" "multiple devices fail without UDID"
    assert_contains "$RUN_OUTPUT" "--udid" "multiple devices request explicit UDID"
}

test_unknown_udid() {
    FAKE_DEVICE_IDS="$(printf 'device-a\n')"
    export FAKE_DEVICE_IDS
    run_script unknown-udid --udid device-b
    assert_status 1 "$RUN_STATUS" "unknown UDID fails"
    assert_contains "$RUN_OUTPUT" "device-b" "unknown UDID is reported"
}

test_help
test_no_device
test_multiple_devices_require_udid
test_unknown_udid

printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]
