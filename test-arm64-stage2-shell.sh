#!/bin/sh
set -eu

QEMU=${QEMU:-qemu-system-aarch64}
AARCH64_AS=${AARCH64_AS:-aarch64-linux-gnu-as}
AARCH64_LD=${AARCH64_LD:-aarch64-linux-gnu-ld}
AARCH64_READELF=${AARCH64_READELF:-aarch64-linux-gnu-readelf}
TIMEOUT=${TIMEOUT:-20}

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

make_image()
{
	image=$1
	script=${image}.script
	header=${image}.header
	exit_elf=BUILD/arm64-exit.elf

	"$AARCH64_AS" -march=armv8-a \
		-o BUILD/arm64-exit.o test/arm64-exit.S
	"$AARCH64_LD" -T test/arm64-stage2-elf.ld -nostdlib \
		-o "$exit_elf" BUILD/arm64-exit.o
	"$AARCH64_READELF" -h "$exit_elf" | grep -q 'Machine:.*AArch64'
	exit_bytes=$(wc -c < "$exit_elf")

	{
		printf 'src %s /exit\n' "$exit_bytes"
		cat "$exit_elf"
		printf '\n/exit\n'
		printf '%s\n' 'src 25 /source'
		printf '00 11 aa FF 22 # fixture\n'
		printf '%s\n' 'hex0 /source /dev/hda' 'f' 'halt'
	} > "$script"
	script_bytes=$(wc -c < "$script")

	truncate -s 131072 "$image"
	{
		printf 'BXHDRAV2'
		write_u64_le 1
		write_u64_le "$script_bytes"
	} > "$header"
	test "$(wc -c < "$header")" -eq 24
	dd if="$header" of="$image" conv=notrunc status=none
	dd if="$script" of="$image" bs=512 seek=1 conv=notrunc status=none
}

run_shell()
{
	image=$1
	log=$2
	shift 2
	timeout "$TIMEOUT" "$QEMU" \
		-M virt -cpu cortex-a53 -m 128M -smp 1 -nographic \
		-kernel BUILD/builder-hex0-arm64-stage2.bin \
		-drive if=none,file="$image",format=raw,id=hd0 \
		-device virtio-blk-device,drive=hd0 \
		-no-reboot "$@" > "$log" 2>&1
	cat "$log"
	grep -q 'builder-hex0-arm64 shell and flush passed' "$log"
	grep -q '0000000000000005' "$log"
	if grep -Eq 'stage2 (trap failure|disk request failed)|shell failed' "$log"; then
		exit 1
	fi
}

expected=BUILD/builder-hex0-arm64-stage2-shell.expected
actual=BUILD/builder-hex0-arm64-stage2-shell.actual
image=BUILD/builder-hex0-arm64-stage2-shell.img
printf '\000\021\252\377\042' > "$expected"

make_image "$image"
run_shell "$image" BUILD/builder-hex0-arm64-stage2-shell-legacy.log
dd if="$image" of="$actual" bs=1 count=5 status=none
cmp "$expected" "$actual"

make_image "$image"
run_shell "$image" BUILD/builder-hex0-arm64-stage2-shell-modern.log \
	-global virtio-mmio.force-legacy=false
dd if="$image" of="$actual" bs=1 count=5 status=none
cmp "$expected" "$actual"

printf '%s\n' 'arm64 stage2 shell, hex0, exec, and delayed flush gates passed'
