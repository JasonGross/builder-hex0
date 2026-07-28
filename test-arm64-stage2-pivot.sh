#!/bin/sh
set -eu

QEMU=${QEMU:-qemu-system-aarch64}
STAGE0_DIR=${STAGE0_DIR:-../stage0-posix-aarch64}
ARMV7_M2=${ARMV7_M2:-"$STAGE0_DIR/M2-Planet-armv7l"}
TIMEOUT=${TIMEOUT:-300}
EXPECTED_BYTES=376490
EXPECTED_SHA256=9c3a8e2878c673b074a51157704fd84c8f92f96b0506c93a390e469b9f8cc543

write_u64_le()
{
	value=$1
	count=0
	while [ "$count" -lt 8 ]; do
		octet=$(printf '%03o' "$((value & 255))")
		printf '%b' "\\$octet"
		value=$((value >> 8))
		count=$((count + 1))
	done
}

append_source()
{
	source=$1
	target=$2
	bytes=$(wc -c < "$source")
	{
		printf 'src %s /%s\n' "$bytes" "$target"
		cat "$source"
		printf '\n'
	} >> "$script"
}

test -x "$ARMV7_M2"
test -f "$STAGE0_DIR/M2libc/armv7l/linux/unistd.c"

image=BUILD/builder-hex0-arm64-stage2-pivot.img
script=${image}.script
header=${image}.header

: > "$script"
append_source "$ARMV7_M2" M2-Planet-armv7l
append_source "$STAGE0_DIR/M2libc/sys/types.h" M2libc/sys/types.h
append_source "$STAGE0_DIR/M2libc/stddef.h" M2libc/stddef.h
append_source "$STAGE0_DIR/M2libc/armv7l/linux/unistd.c" \
	M2libc/armv7l/linux/unistd.c
append_source "$STAGE0_DIR/M2libc/armv7l/linux/fcntl.c" \
	M2libc/armv7l/linux/fcntl.c
append_source "$STAGE0_DIR/M2libc/fcntl.c" M2libc/fcntl.c
append_source "$STAGE0_DIR/M2libc/stdarg.h" M2libc/stdarg.h
append_source "$STAGE0_DIR/M2libc/string.c" M2libc/string.c
append_source "$STAGE0_DIR/M2libc/ctype.c" M2libc/ctype.c
append_source "$STAGE0_DIR/M2libc/stdlib.c" M2libc/stdlib.c
append_source "$STAGE0_DIR/M2libc/stdio.h" M2libc/stdio.h
append_source "$STAGE0_DIR/M2libc/stdio.c" M2libc/stdio.c
append_source "$STAGE0_DIR/M2libc/bootstrappable.c" \
	M2libc/bootstrappable.c
append_source test/arm32-pivot-hello.c arm32-pivot-hello.c

printf '%s\n' \
	'src 0 /dev/hda' \
	'' \
	'/M2-Planet-armv7l --architecture armv7l -f /M2libc/sys/types.h -f /M2libc/stddef.h -f /M2libc/armv7l/linux/unistd.c -f /M2libc/armv7l/linux/fcntl.c -f /M2libc/fcntl.c -f /M2libc/stdarg.h -f /M2libc/string.c -f /M2libc/ctype.c -f /M2libc/stdlib.c -f /M2libc/stdio.h -f /M2libc/stdio.c -f /M2libc/bootstrappable.c -f /arm32-pivot-hello.c -o /dev/hda' \
	'f' \
	'halt' >> "$script"

script_bytes=$(wc -c < "$script")
{
	printf 'BXHDRAV2'
	write_u64_le 1
	write_u64_le "$script_bytes"
} > "$header"
test "$(wc -c < "$header")" -eq 24

run_pivot()
{
	transport=$1
	shift
	truncate -s 4194304 "$image"
	dd if="$header" of="$image" conv=notrunc status=none
	dd if="$script" of="$image" bs=512 seek=1 conv=notrunc status=none
	log=BUILD/builder-hex0-arm64-stage2-pivot-${transport}.log
	timeout "$TIMEOUT" "$QEMU" \
		-M virt -cpu cortex-a53 -m 128M -smp 1 -nographic \
		-kernel BUILD/builder-hex0-arm64-stage2.bin \
		-drive if=none,file="$image",format=raw,id=hd0 \
		-device virtio-blk-device,drive=hd0 \
		-no-reboot "$@" > "$log" 2>&1
	cat "$log"
	grep -q 'builder-hex0-arm64 shell and flush passed' "$log"
	if grep -Eq 'builder-hex0-arm64 (shell failed|stage2 trap failure)' "$log"; then
		exit 1
	fi
	length_hex=$(grep -E '^[0-9A-F]{16}$' "$log" | tail -1)
	test -n "$length_hex"
	length=$((0x$length_hex))
	test "$length" -eq "$EXPECTED_BYTES"
	output=BUILD/builder-hex0-arm64-stage2-pivot-${transport}.M1
	dd if="$image" of="$output" bs=1 count="$length" status=none
	printf '%s  %s\n' "$EXPECTED_SHA256" "$output" | sha256sum -c -
}

run_pivot legacy
run_pivot modern -global virtio-mmio.force-legacy=false

printf '%s\n' \
	'arm64 builder executed ARMv7 M2-Planet and reproduced its M1 output'
