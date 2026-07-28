#!/bin/sh
set -eu

QEMU=${QEMU:-qemu-system-aarch64}
STAGE0_DIR=${STAGE0_DIR:-../stage0-posix-aarch64}
TIMEOUT=${TIMEOUT:-300}

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

test -f "$STAGE0_DIR/AArch64/mescc-tools-mini-kaem.kaem"
image=BUILD/builder-hex0-arm64-stage2-chain.img
script=${image}.script
header=${image}.header
mini=BUILD/builder-hex0-arm64-stage2-mini.kaem

sed -n '1,85p' "$STAGE0_DIR/AArch64/mescc-tools-mini-kaem.kaem" \
	> "$mini"
printf '%s\n' \
	'./AArch64/artifact/catm /dev/hda ./AArch64/artifact/M2' >> "$mini"

: > "$script"
append_source "$STAGE0_DIR/AArch64/hex0_AArch64.hex0" \
	AArch64/hex0_AArch64.hex0
append_source "$STAGE0_DIR/AArch64/kaem-minimal.hex0" \
	AArch64/kaem-minimal.hex0
append_source "$STAGE0_DIR/AArch64/hex1_AArch64.hex0" \
	AArch64/hex1_AArch64.hex0
append_source "$STAGE0_DIR/AArch64/hex2_AArch64.hex1" \
	AArch64/hex2_AArch64.hex1
append_source "$STAGE0_DIR/AArch64/catm_AArch64.hex1" \
	AArch64/catm_AArch64.hex1
append_source "$STAGE0_DIR/AArch64/ELF-aarch64.hex2" \
	AArch64/ELF-aarch64.hex2
append_source "$STAGE0_DIR/AArch64/M0_AArch64.hex2" \
	AArch64/M0_AArch64.hex2
append_source "$STAGE0_DIR/AArch64/aarch64_defs.M1" \
	AArch64/aarch64_defs.M1
append_source "$STAGE0_DIR/AArch64/cc_aarch64.M1" \
	AArch64/cc_aarch64.M1
append_source "$STAGE0_DIR/AArch64/libc-core.M1" \
	AArch64/libc-core.M1
append_source "$STAGE0_DIR/M2libc/aarch64/linux/bootstrap.c" \
	M2libc/aarch64/linux/bootstrap.c
append_source "$STAGE0_DIR/M2libc/bootstrappable.c" \
	M2libc/bootstrappable.c
append_source "$STAGE0_DIR/M2-Planet/cc.h" M2-Planet/cc.h
append_source "$STAGE0_DIR/M2-Planet/cc_globals.c" M2-Planet/cc_globals.c
append_source "$STAGE0_DIR/M2-Planet/cc_reader.c" M2-Planet/cc_reader.c
append_source "$STAGE0_DIR/M2-Planet/cc_strings.c" M2-Planet/cc_strings.c
append_source "$STAGE0_DIR/M2-Planet/cc_types.c" M2-Planet/cc_types.c
append_source "$STAGE0_DIR/M2-Planet/cc_emit.c" M2-Planet/cc_emit.c
append_source "$STAGE0_DIR/M2-Planet/cc_core.c" M2-Planet/cc_core.c
append_source "$STAGE0_DIR/M2-Planet/cc_macro.c" M2-Planet/cc_macro.c
append_source "$STAGE0_DIR/M2-Planet/cc.c" M2-Planet/cc.c
append_source "$mini" AArch64/mini.kaem

printf '%s\n' \
	'hex0 /AArch64/hex0_AArch64.hex0 /AArch64/artifact/hex0' \
	'hex0 /AArch64/kaem-minimal.hex0 /AArch64/artifact/kaem-0' \
	'/AArch64/artifact/kaem-0 /AArch64/mini.kaem' \
	'f' \
	'halt' >> "$script"

script_bytes=$(wc -c < "$script")
truncate -s 8388608 "$image"
{
	printf 'BXHDRAV2'
	write_u64_le 1
	write_u64_le "$script_bytes"
} > "$header"
test "$(wc -c < "$header")" -eq 24
dd if="$header" of="$image" conv=notrunc status=none
dd if="$script" of="$image" bs=512 seek=1 conv=notrunc status=none

run_chain()
{
	transport=$1
	shift
	log=BUILD/builder-hex0-arm64-stage2-chain-${transport}.log
	timeout "$TIMEOUT" "$QEMU" \
		-M virt -cpu cortex-a53 -m 128M -smp 1 -nographic \
		-kernel BUILD/builder-hex0-arm64-stage2.bin \
		-drive if=none,file="$image",format=raw,id=hd0 \
		-device virtio-blk-device,drive=hd0 \
		-no-reboot "$@" > "$log" 2>&1
	cat "$log"
	grep -q 'builder-hex0-arm64 shell and flush passed' "$log"
	length_hex=$(grep -E '^[0-9A-F]{16}$' "$log" | tail -1)
	test -n "$length_hex"
	length=$((0x$length_hex))
	test "$length" -eq 422501
	output=BUILD/builder-hex0-arm64-stage2-M2-${transport}
	dd if="$image" of="$output" bs=1 count="$length" status=none
	printf '%s  %s\n' \
		fa8db2bf931ac933157621e0894b4dddf15fb2bf585e4f6a5d32f20a058f1bef \
		"$output" | sha256sum -c -
}

run_chain legacy

# Rebuild the script image before the second transport mutates sector zero.
dd if="$header" of="$image" conv=notrunc status=none
dd if="$script" of="$image" bs=512 seek=1 conv=notrunc status=none
run_chain modern -global virtio-mmio.force-legacy=false

printf '%s\n' \
	'arm64 stage2 reached canonical AArch64 M2-Planet on both transports'
