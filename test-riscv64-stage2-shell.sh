#!/bin/sh
set -eu

QEMU=${QEMU:-qemu-system-riscv64}
XXD=${XXD:-xxd}
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
    exit_elf=BUILD/riscv64-exit.elf

    cut test/riscv64-exit.elf.hex0 -f1 -d'#' | cut -f1 -d';' \
        | "$XXD" -r -p > "$exit_elf"
    exit_bytes=$(wc -c < "$exit_elf")
    test "$exit_bytes" -eq 132

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
        printf 'BXHDRSV2'
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
        -M virt -m 128M -smp 1 -nographic -bios none \
        -kernel BUILD/builder-hex0-riscv64-stage2.bin \
        -drive if=none,file="$image",format=raw,id=hd0 \
        -device virtio-blk-device,drive=hd0 -no-reboot "$@" > "$log" 2>&1
    grep 'shell and flush passed' "$log"
    grep '0000000000000005' "$log"
}

EXPECTED=BUILD/builder-hex0-riscv64-stage2-shell.expected
ACTUAL=BUILD/builder-hex0-riscv64-stage2-shell.actual
IMAGE=BUILD/builder-hex0-riscv64-stage2-shell.img
printf '\000\021\252\377\042' > "$EXPECTED"

make_image "$IMAGE"
run_shell "$IMAGE" BUILD/builder-hex0-riscv64-stage2-shell-legacy.log
dd if="$IMAGE" of="$ACTUAL" bs=1 count=5 status=none
cmp "$EXPECTED" "$ACTUAL"

make_image "$IMAGE"
run_shell "$IMAGE" BUILD/builder-hex0-riscv64-stage2-shell-modern.log \
    -global virtio-mmio.force-legacy=false
dd if="$IMAGE" of="$ACTUAL" bs=1 count=5 status=none
cmp "$EXPECTED" "$ACTUAL"

printf '%s\n' 'riscv64 stage2 shell, hex0, and delayed flush tests passed'
