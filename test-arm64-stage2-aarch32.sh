#!/bin/sh
set -eu

QEMU=${QEMU:-qemu-system-aarch64}
ARM_AS=${ARM_AS:-arm-linux-gnueabihf-as}
ARM_LD=${ARM_LD:-arm-linux-gnueabihf-ld}
ARM_READELF=${ARM_READELF:-arm-linux-gnueabihf-readelf}
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

fixture=BUILD/arm32-stage2-elf
"$ARM_AS" -march=armv7-a -o "$fixture.o" test/arm32-stage2-elf.S
"$ARM_LD" -T test/arm64-stage2-elf.ld -nostdlib \
	-o "$fixture.elf" "$fixture.o"
"$ARM_READELF" -h "$fixture.elf" | grep -q 'Class:.*ELF32'
"$ARM_READELF" -h "$fixture.elf" | grep -q 'Machine:.*ARM'
test "$("$ARM_READELF" -lW "$fixture.elf" | grep -c ' LOAD ')" -eq 2

elf_bytes=$(wc -c < "$fixture.elf")
header=BUILD/builder-hex0-arm64-stage2-aarch32.header
image=BUILD/builder-hex0-arm64-stage2-aarch32.img
{
	printf 'BXHDRAE2'
	write_u64_le 1
	write_u64_le "$elf_bytes"
} > "$header"
test "$(wc -c < "$header")" -eq 24
truncate -s 131072 "$image"
dd if="$header" of="$image" conv=notrunc status=none
dd if="$fixture.elf" of="$image" bs=512 seek=1 conv=notrunc status=none

run_gate()
{
	transport=$1
	shift
	log=BUILD/builder-hex0-arm64-stage2-aarch32-${transport}.log
	timeout "$TIMEOUT" "$QEMU" \
		-M virt -cpu cortex-a53 -m 128M -smp 1 -nographic \
		-kernel BUILD/builder-hex0-arm64-stage2.bin \
		-drive if=none,file="$image",format=raw,id=hd0 \
		-device virtio-blk-device,drive=hd0 \
		-no-reboot "$@" > "$log" 2>&1
	cat "$log"
	grep -q 'builder-hex0-arm64 stage2 disk ELF32 loaded' "$log"
	grep -q 'builder-hex0-arm64 entered AArch32 EL0' "$log"
	grep -q 'builder-hex0-arm64 cross-ABI process sequencing passed' "$log"
	grep -q 'builder-hex0-arm64 ELF32 and ARM EABI passed' "$log"
	if grep -Eq 'stage2 (trap failure|disk request failed|invalid ELF image)' "$log"; then
		exit 1
	fi
}

run_gate legacy
run_gate modern -global virtio-mmio.force-legacy=false

shell_fixture=BUILD/arm32-shell-exit
"$ARM_AS" -march=armv7-a -o "$shell_fixture.o" test/arm32-shell-exit.S
"$ARM_LD" -T test/arm64-stage2-elf.ld -nostdlib \
	-o "$shell_fixture.elf" "$shell_fixture.o"
shell_elf_bytes=$(wc -c < "$shell_fixture.elf")
shell_script=BUILD/builder-hex0-arm64-stage2-aarch32-shell.script
shell_header=BUILD/builder-hex0-arm64-stage2-aarch32-shell.header
shell_image=BUILD/builder-hex0-arm64-stage2-aarch32-shell.img
{
	printf 'src 0 /dev/hda\n\n'
	printf 'src %s /arm32-exit\n' "$shell_elf_bytes"
	cat "$shell_fixture.elf"
	printf '\n/arm32-exit pivot\nhalt\n'
} > "$shell_script"
shell_script_bytes=$(wc -c < "$shell_script")
{
	printf 'BXHDRAV2'
	write_u64_le 1
	write_u64_le "$shell_script_bytes"
} > "$shell_header"
test "$(wc -c < "$shell_header")" -eq 24

run_shell_gate()
{
	transport=$1
	shift
	truncate -s 131072 "$shell_image"
	dd if="$shell_header" of="$shell_image" conv=notrunc status=none
	dd if="$shell_script" of="$shell_image" bs=512 seek=1 \
		conv=notrunc status=none
	log=BUILD/builder-hex0-arm64-stage2-aarch32-shell-${transport}.log
	timeout "$TIMEOUT" "$QEMU" \
		-M virt -cpu cortex-a53 -m 128M -smp 1 -nographic \
		-kernel BUILD/builder-hex0-arm64-stage2.bin \
		-drive if=none,file="$shell_image",format=raw,id=hd0 \
		-device virtio-blk-device,drive=hd0 \
		-no-reboot "$@" > "$log" 2>&1
	cat "$log"
	grep -q 'builder-hex0-arm64 AArch32 shell argv passed' "$log"
	grep -q 'builder-hex0-arm64 shell and flush passed' "$log"
	if grep -q 'builder-hex0-arm64 shell failed' "$log"; then
		exit 1
	fi
}

run_shell_gate legacy
run_shell_gate modern -global virtio-mmio.force-legacy=false

printf '%s\n' \
	'arm64 stage2 ELF32, AArch32 EL0, ARM EABI, and shell argv gates passed'
