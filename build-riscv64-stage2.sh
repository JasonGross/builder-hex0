#!/bin/sh
set -eu

# SEED selects the machine target: the default is the QEMU virt seed; set
# SEED=builder-hex0-riscv64-tinyemu-stage2 for the TinyEMU one.
SEED=${SEED:-builder-hex0-riscv64-stage2}

mkdir -p BUILD
riscv64-linux-gnu-as -march=rv64i_zicsr -mabi=lp64 \
  -o "BUILD/$SEED.o" "$SEED.S"
riscv64-linux-gnu-ld -T riscv64-stage2.ld -nostdlib \
  -o "BUILD/$SEED.elf" \
  "BUILD/$SEED.o"
riscv64-linux-gnu-objcopy -O binary \
  "BUILD/$SEED.elf" \
  "BUILD/$SEED.bin"
