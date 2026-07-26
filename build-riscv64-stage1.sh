#!/bin/sh
set -eu

# SEED selects the machine target: the default is the QEMU virt seed; set
# SEED=builder-hex0-riscv64-tinyemu-stage1 for the TinyEMU one.
SEED=${SEED:-builder-hex0-riscv64-stage1}

mkdir -p BUILD
riscv64-linux-gnu-as -march=rv64i -mabi=lp64 \
  -o "BUILD/$SEED-oracle.o" "$SEED.S"
riscv64-linux-gnu-ld -T riscv64-stage1.ld -nostdlib \
  -o "BUILD/$SEED-oracle.elf" \
  "BUILD/$SEED-oracle.o"
riscv64-linux-gnu-objcopy -O binary \
  "BUILD/$SEED-oracle.elf" \
  "BUILD/$SEED-oracle.bin"
