# LookInside Device Port Checker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tested macOS shell script that selects one USB iPhone and reports which LookinServer port in `47175...47179` accepts a connection.

**Architecture:** A Bash 3.2-compatible entry point owns argument parsing, dependency checks, device selection, temporary `iproxy` startup, active connection probes, and cleanup. A standalone shell test runner prepends deterministic command doubles to `PATH`, exercising the real script without requiring an iPhone.

**Tech Stack:** Bash 3.2, `xcrun devicectl`, libimobiledevice `idevice_id`, libusbmuxd `iproxy`, BSD `nc`

---

### Task 1: CLI and USB device selection

**Files:**
- Create: `Scripts/check-lookinside-device-port.sh`
- Create: `Tests/Scripts/check-lookinside-device-port-tests.sh`

- [ ] **Step 1: Write failing tests for help and device selection**

Create `Tests/Scripts/check-lookinside-device-port-tests.sh` with:

```bash
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
    printf '%s' "${FAKE_DEVICE_IDS:-}"
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
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
rtk bash Tests/Scripts/check-lookinside-device-port-tests.sh
```

Expected: FAIL because `Scripts/check-lookinside-device-port.sh` does not exist.

- [ ] **Step 3: Implement the minimal CLI and device selection**

Create `Scripts/check-lookinside-device-port.sh` with:

```bash
#!/usr/bin/env bash

set -u

usage() {
    cat <<'EOF'
Usage: Scripts/check-lookinside-device-port.sh [--udid UDID] [--help]

Checks USB device discovery and LookinServer ports 47175-47179.
EOF
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

requested_udid=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --udid)
            [ "$#" -ge 2 ] || die "--udid requires a value"
            requested_udid="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

for command_name in xcrun idevice_id iproxy nc; do
    command -v "$command_name" >/dev/null 2>&1 || die "Missing required command: $command_name"
done

if ! xcrun devicectl list devices; then
    printf 'WARNING: CoreDevice query failed; continuing with usbmux discovery.\n' >&2
fi

device_ids=()
while IFS= read -r device_id; do
    [ -n "$device_id" ] && device_ids[${#device_ids[@]}]="$device_id"
done < <(idevice_id -l)

[ "${#device_ids[@]}" -gt 0 ] || die "No USB iOS device is available through usbmux."

selected_udid=""
if [ -n "$requested_udid" ]; then
    for device_id in "${device_ids[@]}"; do
        if [ "$device_id" = "$requested_udid" ]; then
            selected_udid="$device_id"
            break
        fi
    done
    [ -n "$selected_udid" ] || die "Requested UDID is not available through usbmux: $requested_udid"
elif [ "${#device_ids[@]}" -eq 1 ]; then
    selected_udid="${device_ids[0]}"
else
    printf 'Multiple USB iOS devices found:\n' >&2
    printf '  %s\n' "${device_ids[@]}" >&2
    die "Use --udid to select one device."
fi

printf 'Selected USB device: %s\n' "$selected_udid"
```

- [ ] **Step 4: Make both files executable**

Run:

```bash
rtk chmod +x Scripts/check-lookinside-device-port.sh Tests/Scripts/check-lookinside-device-port-tests.sh
```

Expected: exit status `0`.

- [ ] **Step 5: Run the tests and verify the selection tests reach GREEN**

Run:

```bash
rtk bash Tests/Scripts/check-lookinside-device-port-tests.sh
```

Expected: the four device-selection scenarios pass. The implementation may exit after printing the selected device because port probing is added in Task 2.

- [ ] **Step 6: Commit Task 1**

Run:

```bash
rtk git add Scripts/check-lookinside-device-port.sh Tests/Scripts/check-lookinside-device-port-tests.sh
rtk git commit -m "test: cover LookInside device selection"
```

Expected: one commit containing only the new script and its tests.

### Task 2: Port probing and reliable cleanup

**Files:**
- Modify: `Scripts/check-lookinside-device-port.sh`
- Modify: `Tests/Scripts/check-lookinside-device-port-tests.sh`

- [ ] **Step 1: Add failing port and cleanup tests**

Insert these functions before the test invocations in
`Tests/Scripts/check-lookinside-device-port-tests.sh`:

```bash
test_single_open_port() {
    FAKE_DEVICE_IDS="$(printf 'device-a\n')"
    FAKE_OPEN_LOCAL_PORT="58175"
    FAKE_IPROXY_PID_FILE="$TEST_TMP_ROOT/single-open-iproxy.pid"
    export FAKE_DEVICE_IDS FAKE_OPEN_LOCAL_PORT FAKE_IPROXY_PID_FILE
    run_script single-open
    assert_status 0 "$RUN_STATUS" "one open LookinServer port succeeds"
    assert_contains "$RUN_OUTPUT" "47175 OPEN" "open port is reported"
    assert_contains "$RUN_OUTPUT" "47176 CLOSED" "closed port is reported"
}

test_all_ports_closed() {
    FAKE_DEVICE_IDS="$(printf 'device-a\n')"
    FAKE_OPEN_LOCAL_PORT=""
    FAKE_IPROXY_PID_FILE="$TEST_TMP_ROOT/all-closed-iproxy.pid"
    export FAKE_DEVICE_IDS FAKE_OPEN_LOCAL_PORT FAKE_IPROXY_PID_FILE
    run_script all-closed
    assert_status 1 "$RUN_STATUS" "all closed LookinServer ports fail"
    assert_contains "$RUN_OUTPUT" "No LookinServer port accepted" "all closed ports explain failure"
}

test_explicit_udid_succeeds() {
    FAKE_DEVICE_IDS="$(printf 'device-a\ndevice-b\n')"
    FAKE_OPEN_LOCAL_PORT="58177"
    FAKE_IPROXY_PID_FILE="$TEST_TMP_ROOT/explicit-udid-iproxy.pid"
    export FAKE_DEVICE_IDS FAKE_OPEN_LOCAL_PORT FAKE_IPROXY_PID_FILE
    run_script explicit-udid --udid device-b
    assert_status 0 "$RUN_STATUS" "explicit UDID selects among multiple devices"
    assert_contains "$RUN_OUTPUT" "Selected USB device: device-b" "selected UDID is printed"
    assert_contains "$RUN_OUTPUT" "47177 OPEN" "non-first open port is supported"
}

test_coredevice_failure_is_warning() {
    FAKE_DEVICE_IDS="$(printf 'device-a\n')"
    FAKE_COREDEVICE_STATUS=1
    FAKE_OPEN_LOCAL_PORT="58175"
    FAKE_IPROXY_PID_FILE="$TEST_TMP_ROOT/coredevice-warning-iproxy.pid"
    export FAKE_DEVICE_IDS FAKE_COREDEVICE_STATUS FAKE_OPEN_LOCAL_PORT FAKE_IPROXY_PID_FILE
    run_script coredevice-warning
    assert_status 0 "$RUN_STATUS" "CoreDevice failure does not override usbmux"
    assert_contains "$RUN_OUTPUT" "WARNING: CoreDevice query failed" "CoreDevice failure is reported"
    unset FAKE_COREDEVICE_STATUS
}

test_busy_local_port_fails_without_killing_owner() {
    FAKE_DEVICE_IDS="$(printf 'device-a\n')"
    FAKE_BUSY_LOCAL_PORTS="58176"
    FAKE_OPEN_LOCAL_PORT="58175"
    export FAKE_DEVICE_IDS FAKE_BUSY_LOCAL_PORTS FAKE_OPEN_LOCAL_PORT
    run_script busy-local-port
    assert_status 1 "$RUN_STATUS" "busy local port fails before forwarding"
    assert_contains "$RUN_OUTPUT" "58176" "busy local port is identified"
    unset FAKE_BUSY_LOCAL_PORTS
}

test_iproxy_is_cleaned_up() {
    FAKE_DEVICE_IDS="$(printf 'device-a\n')"
    FAKE_OPEN_LOCAL_PORT="58175"
    FAKE_IPROXY_PID_FILE="$TEST_TMP_ROOT/cleanup-iproxy.pid"
    export FAKE_DEVICE_IDS FAKE_OPEN_LOCAL_PORT FAKE_IPROXY_PID_FILE
    run_script cleanup
    iproxy_pid="$(cat "$FAKE_IPROXY_PID_FILE")"
    if kill -0 "$iproxy_pid" 2>/dev/null; then
        fail "iproxy process is cleaned up"
        kill "$iproxy_pid" 2>/dev/null || true
    else
        pass "iproxy process is cleaned up"
    fi
}

test_iproxy_is_cleaned_up_after_failure() {
    FAKE_DEVICE_IDS="$(printf 'device-a\n')"
    FAKE_OPEN_LOCAL_PORT=""
    FAKE_IPROXY_PID_FILE="$TEST_TMP_ROOT/failure-cleanup-iproxy.pid"
    export FAKE_DEVICE_IDS FAKE_OPEN_LOCAL_PORT FAKE_IPROXY_PID_FILE
    run_script failure-cleanup
    iproxy_pid="$(cat "$FAKE_IPROXY_PID_FILE")"
    if kill -0 "$iproxy_pid" 2>/dev/null; then
        fail "iproxy process is cleaned up after failure"
        kill "$iproxy_pid" 2>/dev/null || true
    else
        pass "iproxy process is cleaned up after failure"
    fi
}
```

Add these invocations after `test_unknown_udid`:

```bash
test_single_open_port
test_all_ports_closed
test_explicit_udid_succeeds
test_coredevice_failure_is_warning
test_busy_local_port_fails_without_killing_owner
test_iproxy_is_cleaned_up
test_iproxy_is_cleaned_up_after_failure
```

- [ ] **Step 2: Run the expanded tests and verify RED**

Run:

```bash
rtk bash Tests/Scripts/check-lookinside-device-port-tests.sh
```

Expected: device-selection tests pass, while port-result and cleanup tests fail because no forwarding or probing exists.

- [ ] **Step 3: Replace the main script with the complete port checker**

Replace `Scripts/check-lookinside-device-port.sh` with:

```bash
#!/usr/bin/env bash

set -u

DEVICE_PORT_START=47175
DEVICE_PORT_END=47179
LOCAL_PORT_BASE="${LOOKINSIDE_LOCAL_PORT_BASE:-58175}"
IPROXY_STARTUP_SECONDS="${LOOKINSIDE_IPROXY_STARTUP_SECONDS:-0.3}"
PROBE_SETTLE_SECONDS="${LOOKINSIDE_PROBE_SETTLE_SECONDS:-0.4}"
PROBE_HOLD_SECONDS="${LOOKINSIDE_PROBE_HOLD_SECONDS:-2}"

tmp_dir=""
iproxy_pid=""
probe_pids=()

usage() {
    cat <<'EOF'
Usage: Scripts/check-lookinside-device-port.sh [--udid UDID] [--help]

Checks whether one USB-connected iOS device is reachable through usbmux and
which LookinServer port in 47175-47179 accepts a connection.
EOF
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

cleanup() {
    for probe_pid in "${probe_pids[@]}"; do
        if kill -0 "$probe_pid" 2>/dev/null; then
            kill "$probe_pid" 2>/dev/null || true
            wait "$probe_pid" 2>/dev/null || true
        fi
    done
    if [ -n "$iproxy_pid" ] && kill -0 "$iproxy_pid" 2>/dev/null; then
        kill "$iproxy_pid" 2>/dev/null || true
        wait "$iproxy_pid" 2>/dev/null || true
    fi
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        rm -rf "$tmp_dir"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

requested_udid=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --udid)
            [ "$#" -ge 2 ] || die "--udid requires a value"
            requested_udid="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

for command_name in xcrun idevice_id iproxy nc; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        case "$command_name" in
            idevice_id|iproxy)
                die "Missing required command: $command_name. Install Homebrew packages libimobiledevice and libusbmuxd."
                ;;
            *)
                die "Missing required command: $command_name"
                ;;
        esac
    fi
done

printf '%s\n' "CoreDevice devices:"
if ! xcrun devicectl list devices; then
    printf 'WARNING: CoreDevice query failed; continuing with usbmux discovery.\n' >&2
fi

device_ids=()
while IFS= read -r device_id; do
    [ -n "$device_id" ] && device_ids[${#device_ids[@]}]="$device_id"
done < <(idevice_id -l)

[ "${#device_ids[@]}" -gt 0 ] || die "No USB iOS device is available through usbmux."

selected_udid=""
if [ -n "$requested_udid" ]; then
    for device_id in "${device_ids[@]}"; do
        if [ "$device_id" = "$requested_udid" ]; then
            selected_udid="$device_id"
            break
        fi
    done
    [ -n "$selected_udid" ] || die "Requested UDID is not available through usbmux: $requested_udid"
elif [ "${#device_ids[@]}" -eq 1 ]; then
    selected_udid="${device_ids[0]}"
else
    printf 'Multiple USB iOS devices found:\n' >&2
    printf '  %s\n' "${device_ids[@]}" >&2
    die "Use --udid to select one device."
fi

printf 'Selected USB device: %s\n' "$selected_udid"

device_port="$DEVICE_PORT_START"
while [ "$device_port" -le "$DEVICE_PORT_END" ]; do
    local_port=$((LOCAL_PORT_BASE + device_port - DEVICE_PORT_START))
    if nc -z 127.0.0.1 "$local_port" >/dev/null 2>&1; then
        die "Local probe port is already in use: $local_port"
    fi
    device_port=$((device_port + 1))
done

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/lookinside-port-check.XXXXXX")"
iproxy_log="$tmp_dir/iproxy.log"
iproxy_args=(-d -u "$selected_udid")
device_port="$DEVICE_PORT_START"
while [ "$device_port" -le "$DEVICE_PORT_END" ]; do
    local_port=$((LOCAL_PORT_BASE + device_port - DEVICE_PORT_START))
    iproxy_args[${#iproxy_args[@]}]="$local_port:$device_port"
    device_port=$((device_port + 1))
done

iproxy "${iproxy_args[@]}" >"$iproxy_log" 2>&1 &
iproxy_pid=$!
sleep "$IPROXY_STARTUP_SECONDS"
if ! kill -0 "$iproxy_pid" 2>/dev/null; then
    cat "$iproxy_log" >&2
    die "Failed to start USB port forwarding."
fi

open_count=0
device_port="$DEVICE_PORT_START"
while [ "$device_port" -le "$DEVICE_PORT_END" ]; do
    local_port=$((LOCAL_PORT_BASE + device_port - DEVICE_PORT_START))
    (sleep "$PROBE_HOLD_SECONDS") | nc 127.0.0.1 "$local_port" >/dev/null 2>&1 &
    probe_pid=$!
    probe_pids[${#probe_pids[@]}]="$probe_pid"
    sleep "$PROBE_SETTLE_SECONDS"

    if kill -0 "$probe_pid" 2>/dev/null; then
        printf '%d OPEN\n' "$device_port"
        open_count=$((open_count + 1))
        kill "$probe_pid" 2>/dev/null || true
        wait "$probe_pid" 2>/dev/null || true
    else
        wait "$probe_pid" 2>/dev/null || true
        printf '%d CLOSED\n' "$device_port"
    fi
    device_port=$((device_port + 1))
done

[ "$open_count" -gt 0 ] || die "No LookinServer port accepted a connection in 47175-47179."
printf 'LookinServer port check passed on device %s.\n' "$selected_udid"
```

- [ ] **Step 4: Run syntax and behavior tests and verify GREEN**

Run:

```bash
rtk bash -n Scripts/check-lookinside-device-port.sh
rtk bash -n Tests/Scripts/check-lookinside-device-port-tests.sh
rtk bash Tests/Scripts/check-lookinside-device-port-tests.sh
```

Expected: both syntax checks exit `0`; all behavior and cleanup tests pass and the test runner reports `0 failed`.

- [ ] **Step 5: Commit Task 2**

Run:

```bash
rtk git add Scripts/check-lookinside-device-port.sh Tests/Scripts/check-lookinside-device-port-tests.sh
rtk git commit -m "feat: check LookInside ports on USB devices"
```

Expected: one commit containing the completed probing behavior and its tests.

### Task 3: Verify against the connected iPhone

**Files:**
- Verify: `Scripts/check-lookinside-device-port.sh`
- Verify: `Tests/Scripts/check-lookinside-device-port-tests.sh`

- [ ] **Step 1: Run the complete offline verification**

Run:

```bash
rtk bash -n Scripts/check-lookinside-device-port.sh
rtk bash -n Tests/Scripts/check-lookinside-device-port-tests.sh
rtk bash Tests/Scripts/check-lookinside-device-port-tests.sh
rtk git diff --check
```

Expected: syntax checks and tests exit `0`, tests report `0 failed`, and `git diff --check` prints no errors.

- [ ] **Step 2: Confirm usbmux still sees the intended device**

Run:

```bash
rtk idevice_id -l
```

Expected: output contains the intended physical-device UDID, such as
`00008140-000D59423C0A801C`.

- [ ] **Step 3: Run the real port check**

Run:

```bash
rtk Scripts/check-lookinside-device-port.sh --udid 00008140-000D59423C0A801C
```

Expected: exit status `0`; exactly one or more entries report `OPEN`, and the currently observed setup reports `47175 OPEN`. Entries for unused ports report `CLOSED`.

- [ ] **Step 4: Confirm cleanup**

Run:

```bash
rtk ps aux | rtk grep '[i]proxy'
```

Expected: no `iproxy` process created by the checker remains.

- [ ] **Step 5: Review repository state**

Run:

```bash
rtk git status --short
rtk git log -3 --oneline
```

Expected: the two implementation commits are present. Pre-existing user changes to
`AGENTS.md` and `.understand-anything/` remain untouched.
