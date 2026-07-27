#!/bin/sh
set -eu

mkdir -p BUILD
riscv64-linux-gnu-as -march=rv64i_zicsr -mabi=lp64 \
  -o BUILD/builder-hex0-riscv64-stage2.o builder-hex0-riscv64-stage2.S
riscv64-linux-gnu-ld -T riscv64-stage2.ld -nostdlib \
  -o BUILD/builder-hex0-riscv64-stage2.elf \
  BUILD/builder-hex0-riscv64-stage2.o
riscv64-linux-gnu-objcopy -O binary \
  BUILD/builder-hex0-riscv64-stage2.elf \
  BUILD/builder-hex0-riscv64-stage2.bin
