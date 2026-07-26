#!/bin/sh
set -eu

CROSS_COMPILE=${CROSS_COMPILE:-aarch64-linux-gnu-}

mkdir -p BUILD
"${CROSS_COMPILE}as" -march=armv8-a \
  -o BUILD/builder-hex0-arm64-stage1-oracle.o builder-hex0-arm64-stage1.S
"${CROSS_COMPILE}ld" -T arm64-stage1.ld -nostdlib \
  -o BUILD/builder-hex0-arm64-stage1-oracle.elf \
  BUILD/builder-hex0-arm64-stage1-oracle.o
"${CROSS_COMPILE}objcopy" -O binary \
  BUILD/builder-hex0-arm64-stage1-oracle.elf \
  BUILD/builder-hex0-arm64-stage1-oracle.bin
