#!/bin/sh
set -eu

QEMU=${QEMU:-qemu-system-riscv64}
STAGE0_DIR=${STAGE0_DIR:-../stage0-posix-riscv64}
TIMEOUT=${TIMEOUT:-28800}

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
    } >> "$SCRIPT"
}

test -f "$STAGE0_DIR/riscv64/mescc-tools-mini-kaem.kaem"
IMAGE=BUILD/builder-hex0-riscv64-stage2-chain.img
SCRIPT=${IMAGE}.script
HEADER=${IMAGE}.header
MINI=BUILD/builder-hex0-riscv64-stage2-mini.kaem

sed -n '1,78p' "$STAGE0_DIR/riscv64/mescc-tools-mini-kaem.kaem" > "$MINI"
printf '%s\n' \
    './riscv64/artifact/catm /dev/hda ./riscv64/artifact/M2' >> "$MINI"

: > "$SCRIPT"
append_source "$STAGE0_DIR/bootstrap-seeds/POSIX/riscv64/hex0_riscv64.hex0" \
    riscv64/hex0_riscv64.hex0
append_source "$STAGE0_DIR/riscv64/kaem-minimal.hex0" riscv64/kaem-minimal.hex0
append_source "$STAGE0_DIR/riscv64/hex1_riscv64.hex0" riscv64/hex1_riscv64.hex0
append_source "$STAGE0_DIR/riscv64/hex2_riscv64.hex1" riscv64/hex2_riscv64.hex1
append_source "$STAGE0_DIR/riscv64/catm_riscv64.hex2" riscv64/catm_riscv64.hex2
append_source "$STAGE0_DIR/riscv64/ELF-riscv64.hex2" riscv64/ELF-riscv64.hex2
append_source "$STAGE0_DIR/riscv64/M0_riscv64.hex2" riscv64/M0_riscv64.hex2
append_source "$STAGE0_DIR/riscv64/riscv64_defs.M1" riscv64/riscv64_defs.M1
append_source "$STAGE0_DIR/riscv64/cc_riscv64.M1" riscv64/cc_riscv64.M1
append_source "$STAGE0_DIR/riscv64/libc-core.M1" riscv64/libc-core.M1
append_source "$STAGE0_DIR/M2libc/riscv64/linux/bootstrap.c" M2libc/riscv64/linux/bootstrap.c
append_source "$STAGE0_DIR/M2libc/bootstrappable.c" M2libc/bootstrappable.c
append_source "$STAGE0_DIR/M2-Planet/cc.h" M2-Planet/cc.h
append_source "$STAGE0_DIR/M2-Planet/cc_globals.c" M2-Planet/cc_globals.c
append_source "$STAGE0_DIR/M2-Planet/cc_reader.c" M2-Planet/cc_reader.c
append_source "$STAGE0_DIR/M2-Planet/cc_strings.c" M2-Planet/cc_strings.c
append_source "$STAGE0_DIR/M2-Planet/cc_types.c" M2-Planet/cc_types.c
append_source "$STAGE0_DIR/M2-Planet/cc_emit.c" M2-Planet/cc_emit.c
append_source "$STAGE0_DIR/M2-Planet/cc_core.c" M2-Planet/cc_core.c
append_source "$STAGE0_DIR/M2-Planet/cc_macro.c" M2-Planet/cc_macro.c
append_source "$STAGE0_DIR/M2-Planet/cc.c" M2-Planet/cc.c
append_source "$MINI" riscv64/mini.kaem

printf '%s\n' \
    'hex0 /riscv64/hex0_riscv64.hex0 /riscv64/artifact/hex0' \
    'hex0 /riscv64/kaem-minimal.hex0 /riscv64/artifact/kaem-0' \
    '/riscv64/artifact/kaem-0 /riscv64/mini.kaem' \
    'f' \
    'halt' >> "$SCRIPT"

script_bytes=$(wc -c < "$SCRIPT")
truncate -s 4194304 "$IMAGE"
{
    printf 'BXHDRSV2'
    write_u64_le 1
    write_u64_le "$script_bytes"
} > "$HEADER"
dd if="$HEADER" of="$IMAGE" conv=notrunc status=none
dd if="$SCRIPT" of="$IMAGE" bs=512 seek=1 conv=notrunc status=none

timeout "$TIMEOUT" "$QEMU" \
    -M virt -m 128M -smp 1 -nographic -bios none \
    -kernel BUILD/builder-hex0-riscv64-stage2.bin \
    -drive if=none,file="$IMAGE",format=raw,id=hd0 \
    -device virtio-blk-device,drive=hd0 -no-reboot \
    > BUILD/builder-hex0-riscv64-stage2-chain.log 2>&1

grep 'shell and flush passed' BUILD/builder-hex0-riscv64-stage2-chain.log
length_hex=$(grep -E '^[0-9A-F]{16}$' \
    BUILD/builder-hex0-riscv64-stage2-chain.log | tail -1)
test -n "$length_hex"
length=$((0x$length_hex))
test "$length" -eq 361701
dd if="$IMAGE" of=BUILD/builder-hex0-riscv64-stage2-M2 \
    bs=1 count="$length" status=none
test "$(wc -c < BUILD/builder-hex0-riscv64-stage2-M2)" -eq "$length"
printf '%s  %s\n' \
    cbc35afec2baef4a31b5875b0b3e08c4eb03d6974e0b57c7cd905e7244b92a17 \
    BUILD/builder-hex0-riscv64-stage2-M2 | sha256sum -c -
printf 'riscv64 stage2 reached M2-Planet bootstrap (%s bytes)\n' "$length"
