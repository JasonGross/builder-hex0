#!/bin/sh
set -eu

mkdir -p BUILD
riscv64-linux-gnu-as -march=rv64i -mabi=lp64 \
  -o BUILD/builder-hex0-riscv64-stage1-oracle.o builder-hex0-riscv64-stage1.S
riscv64-linux-gnu-ld -T riscv64-stage1.ld -nostdlib \
  -o BUILD/builder-hex0-riscv64-stage1-oracle.elf \
  BUILD/builder-hex0-riscv64-stage1-oracle.o
riscv64-linux-gnu-objcopy -O binary \
  BUILD/builder-hex0-riscv64-stage1-oracle.elf \
  BUILD/builder-hex0-riscv64-stage1-oracle.bin
