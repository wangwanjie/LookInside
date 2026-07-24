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
