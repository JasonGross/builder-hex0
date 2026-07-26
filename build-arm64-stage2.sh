#!/bin/sh
set -eu

AARCH64_AS=${AARCH64_AS:-aarch64-linux-gnu-as}
AARCH64_LD=${AARCH64_LD:-aarch64-linux-gnu-ld}
AARCH64_OBJCOPY=${AARCH64_OBJCOPY:-aarch64-linux-gnu-objcopy}

mkdir -p BUILD
"$AARCH64_AS" -march=armv8-a \
	-o BUILD/builder-hex0-arm64-stage2.o builder-hex0-arm64-stage2.S
"$AARCH64_LD" -T arm64-stage1.ld -nostdlib \
	-o BUILD/builder-hex0-arm64-stage2.elf \
	BUILD/builder-hex0-arm64-stage2.o
"$AARCH64_OBJCOPY" -O binary \
	BUILD/builder-hex0-arm64-stage2.elf \
	BUILD/builder-hex0-arm64-stage2.bin
