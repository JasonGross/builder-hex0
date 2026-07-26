#!/bin/sh
set -eu

QEMU=${QEMU:-qemu-system-aarch64}
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
    source=$2
    output_lba=$3
    header=${image}.header
    source_bytes=$(wc -c < "$source")

    truncate -s 131072 "$image"
    {
        printf 'BXHDRVX0'
        write_u64_le 1
        write_u64_le "$source_bytes"
        write_u64_le "$output_lba"
    } > "$header"
    test "$(wc -c < "$header")" -eq 32
    dd if="$header" of="$image" conv=notrunc status=none
    dd if="$source" of="$image" bs=512 seek=1 conv=notrunc status=none
}

run_builder()
{
    image=$1
    log=$2
    shift 2
    timeout "$TIMEOUT" "$QEMU" \
        -M virt -cpu cortex-a53 -m 128M -smp 1 -nographic \
        -kernel BUILD/builder-hex0-arm64-stage1.bin \
        -drive if=none,file="$image",format=raw,id=hd0 \
        -device virtio-blk-device,drive=hd0 -no-reboot "$@" > "$log" 2>&1
}

PARSER_IMAGE=BUILD/builder-hex0-arm64-stage1-parser.img
PARSER_ACTUAL=BUILD/builder-hex0-arm64-stage1-parser.actual
PARSER_EXPECTED=BUILD/builder-hex0-arm64-stage1-parser.expected
printf '\000\021\252\377\042' > "$PARSER_EXPECTED"

make_image "$PARSER_IMAGE" test/hex0-parser.hex0 8
run_builder "$PARSER_IMAGE" BUILD/builder-hex0-arm64-stage1-modern.log \
    -global virtio-mmio.force-legacy=false
dd if="$PARSER_IMAGE" of="$PARSER_ACTUAL" bs=1 skip=4096 count=5 status=none
cmp "$PARSER_EXPECTED" "$PARSER_ACTUAL"
grep 'compiled bytes: 0x0000000000000005' \
    BUILD/builder-hex0-arm64-stage1-modern.log

make_image "$PARSER_IMAGE" test/hex0-parser.hex0 8
run_builder "$PARSER_IMAGE" BUILD/builder-hex0-arm64-stage1-legacy.log \
    -global virtio-mmio.force-legacy=true
dd if="$PARSER_IMAGE" of="$PARSER_ACTUAL" bs=1 skip=4096 count=5 status=none
cmp "$PARSER_EXPECTED" "$PARSER_ACTUAL"

SELF_IMAGE=BUILD/builder-hex0-arm64-stage1-self.img
SELF_ACTUAL=BUILD/builder-hex0-arm64-stage1-self.bin
make_image "$SELF_IMAGE" builder-hex0-arm64-stage1.hex0 64
run_builder "$SELF_IMAGE" BUILD/builder-hex0-arm64-stage1-self.log \
    -global virtio-mmio.force-legacy=false
oracle_bytes=$(wc -c < BUILD/builder-hex0-arm64-stage1.bin)
dd if="$SELF_IMAGE" of="$SELF_ACTUAL" bs=1 skip=32768 \
    count="$oracle_bytes" status=none
cmp BUILD/builder-hex0-arm64-stage1.bin "$SELF_ACTUAL"

printf '%s\n' 'arm64 stage1 parser, virtio, and self-build tests passed'
