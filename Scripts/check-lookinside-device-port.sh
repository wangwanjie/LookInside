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

This check uses libimobiledevice's usbmux transport. A device shown as
"connected" by Xcode/CoreDevice but absent from `idevice_id -l` cannot be
probed by iproxy; the script reports that situation explicitly.
EOF
}

die() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

cleanup() {
    if [ "${#probe_pids[@]}" -gt 0 ]; then
        for probe_pid in "${probe_pids[@]}"; do
            if kill -0 "$probe_pid" 2>/dev/null; then
                kill "$probe_pid" 2>/dev/null || true
                wait "$probe_pid" 2>/dev/null || true
            fi
        done
    fi
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

for command_name in xcrun idevice_id ideviceinfo iproxy nc; do
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
coredevice_output=""
if ! coredevice_output="$(xcrun devicectl list devices --columns '*' 2>&1)"; then
    printf 'WARNING: CoreDevice query failed; continuing with usbmux discovery.\n' >&2
else
    printf '%s\n' "$coredevice_output"
fi
coredevice_connected="$(printf '%s\n' "$coredevice_output" | awk '/[[:space:]]connected([[:space:]]|$)/')"
coredevice_connected_udids="$(printf '%s\n' "$coredevice_connected" | grep -Eo '[[:xdigit:]]{8}-[[:xdigit:]]{16}' || true)"

device_ids=()
while IFS= read -r device_id; do
    [ -n "$device_id" ] && device_ids[${#device_ids[@]}]="$device_id"
done < <(idevice_id -l)

if [ "${#device_ids[@]}" -eq 0 ]; then
    if [ -n "$coredevice_connected" ]; then
        printf '%s\n' "$coredevice_connected" >&2
        die "A CoreDevice-connected iPhone was found, but it is unavailable through usbmux. This script cannot use iproxy for that device; use a usbmux-visible device or a CoreDevice-compatible port forwarder."
    fi
    die "No USB iOS device is available through usbmux."
fi

coredevice_only_udids=()
coredevice_only_count=0
while IFS= read -r coredevice_udid; do
    [ -n "$coredevice_udid" ] || continue
    found_in_usbmux=0
    for device_id in "${device_ids[@]}"; do
        [ "$device_id" = "$coredevice_udid" ] && found_in_usbmux=1
    done
    if [ "$found_in_usbmux" -eq 0 ]; then
        coredevice_only_udids[$coredevice_only_count]="$coredevice_udid"
        coredevice_only_count=$((coredevice_only_count + 1))
    fi
done <<<"$coredevice_connected_udids"

if [ -z "$requested_udid" ] && [ "$coredevice_only_count" -gt 0 ]; then
    printf 'CoreDevice-only connected device(s):\n' >&2
    printf '  %s\n' "${coredevice_only_udids[@]:0:$coredevice_only_count}" >&2
    printf 'usbmux-visible device(s):\n' >&2
    printf '  %s\n' "${device_ids[@]}" >&2
    die "Multiple devices are connected through different transports. Use --udid to select a usbmux-visible device; CoreDevice-only devices cannot be checked with iproxy."
fi

selected_udid=""
if [ -n "$requested_udid" ]; then
    for device_id in "${device_ids[@]}"; do
        if [ "$device_id" = "$requested_udid" ]; then
            selected_udid="$device_id"
            break
        fi
    done
    if [ -z "$selected_udid" ]; then
        for ((coredevice_index = 0; coredevice_index < coredevice_only_count; coredevice_index++)); do
            coredevice_udid="${coredevice_only_udids[$coredevice_index]}"
            [ "$coredevice_udid" = "$requested_udid" ] && die "Requested UDID is connected through CoreDevice only and cannot be checked with iproxy: $requested_udid"
        done
        die "Requested UDID is not available through usbmux: $requested_udid"
    fi
elif [ "${#device_ids[@]}" -eq 1 ]; then
    selected_udid="${device_ids[0]}"
else
    printf 'Multiple USB iOS devices found:\n' >&2
    printf '  %s\n' "${device_ids[@]}" >&2
    die "Use --udid to select one device."
fi

printf 'Selected USB device: %s\n' "$selected_udid"
if ! selected_device_name="$(ideviceinfo -u "$selected_udid" -k DeviceName 2>&1)"; then
    die "Selected usbmux device no longer responds: $selected_udid. It may be a stale usbmux entry; the currently connected CoreDevice device cannot be checked with iproxy."
fi
printf 'usbmux device name: %s\n' "$selected_device_name"

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
