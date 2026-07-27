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

run_disk_gate()
{
	log=$1
	shift
	timeout "$TIMEOUT" "$QEMU" \
		-M virt -cpu cortex-a53 -m 128M -smp 1 -nographic \
		-kernel BUILD/builder-hex0-arm64-stage2.bin \
		-drive if=none,file="$image",format=raw,id=hd0 \
		-device virtio-blk-device,drive=hd0 \
		-device loader,data=0x5a,addr=0x40601000,data-len=1 \
		-device loader,data=0x5a,addr=0x40601fff,data-len=1 \
		-device loader,data=0x5a,addr=0x40602000,data-len=1 \
		-device loader,data=0x5a,addr=0x40800000,data-len=1 \
		-no-reboot "$@" > "$log" 2>&1

	cat "$log"
	grep -q 'builder-hex0-arm64 stage2 disk ELF64 loaded' "$log"
	grep -q 'builder-hex0-arm64 disk ELF64 and brk passed' "$log"
	if grep -Eq 'stage2 (trap failure|disk request failed|invalid ELF64 image)' "$log"; then
		exit 1
	fi
}

fixture=BUILD/arm64-stage2-elf
"$AARCH64_AS" -march=armv8-a -o "$fixture.o" test/arm64-stage2-elf.S
"$AARCH64_LD" -T test/arm64-stage2-elf.ld -nostdlib \
	-o "$fixture.elf" "$fixture.o"
"$AARCH64_READELF" -h "$fixture.elf" | grep -q 'Class:.*ELF64'
"$AARCH64_READELF" -h "$fixture.elf" | grep -q 'Machine:.*AArch64'
test "$("$AARCH64_READELF" -lW "$fixture.elf" | grep -c ' LOAD ')" -eq 2

elf_bytes=$(wc -c < "$fixture.elf")
header=BUILD/builder-hex0-arm64-stage2.header
image=BUILD/builder-hex0-arm64-stage2.img
{
	printf 'BXHDRAE2'
	write_u64_le 1
	write_u64_le "$elf_bytes"
} > "$header"
test "$(wc -c < "$header")" -eq 24
truncate -s 131072 "$image"
dd if="$header" of="$image" conv=notrunc status=none
dd if="$fixture.elf" of="$image" bs=512 seek=1 conv=notrunc status=none

log=BUILD/builder-hex0-arm64-stage2.log
timeout "$TIMEOUT" "$QEMU" \
	-M virt -cpu cortex-a53 -m 128M -smp 1 -nographic \
	-kernel BUILD/builder-hex0-arm64-stage2.bin -no-reboot > "$log" 2>&1
cat "$log"
grep -q 'builder-hex0-arm64 stage2 EL0 svc passed' "$log"
if grep -q 'stage2 trap failure' "$log"; then
	exit 1
fi

run_disk_gate BUILD/builder-hex0-arm64-stage2-legacy.log
run_disk_gate BUILD/builder-hex0-arm64-stage2-modern.log \
	-global virtio-mmio.force-legacy=false

printf '%s\n' 'arm64 stage2 privilege, ELF64, and brk gates passed'
