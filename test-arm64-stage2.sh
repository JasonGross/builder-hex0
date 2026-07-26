#!/bin/sh
set -eu

QEMU=${QEMU:-qemu-system-aarch64}
TIMEOUT=${TIMEOUT:-20}
log=BUILD/builder-hex0-arm64-stage2.log

timeout "$TIMEOUT" "$QEMU" \
	-M virt -cpu cortex-a53 -m 128M -smp 1 -nographic \
	-kernel BUILD/builder-hex0-arm64-stage2.bin -no-reboot > "$log" 2>&1

cat "$log"
grep -q 'builder-hex0-arm64 stage2 EL0 svc passed' "$log"
if grep -q 'stage2 trap failure' "$log"; then
	exit 1
fi

printf '%s\n' 'arm64 stage2 privilege gate passed'
