# builder-hex0 on riscv64

## Objective

The riscv64 port provides a native path from an auditable hex0 machine-code
seed into riscv64 stage0-posix. It is split into two reviewable stages:

1. an RV64I hex0 compiler with UART and block I/O; and
2. the builder shell, memory filesystem, syscall dispatcher, and ELF64 loader.

Stage 1 is complete when it builds itself byte for byte. Stage 2 is complete
when it can execute the existing riscv64 stage0-posix inputs and persist the
resulting `/dev/hda` image. Merely booting or running a custom payload is not a
completion criterion.

## Machine interface

The reference platform is QEMU `virt`, one hart, 128 MiB or more of RAM, and a
virtio-mmio block device. QEMU's firmware-free reset stub enters the seed at
`0x80000000`. The seed uses only RV64I instructions and does not require
OpenSBI.

The hardware interfaces are:

- 16550 UART at `0x10000000`;
- virtio block device discovered in the standard
  `0x10001000..0x10008000` MMIO window;
- legacy virtio-mmio version 1 and modern version 2 split queues; and
- QEMU test finisher at `0x00100000` for deterministic tests.

RISC-V has no PC-compatible MBR/BIOS boot-sector contract. Loading the small
seed through QEMU's standard `-kernel` interface is the native equivalent of
loading the x86 stage-1 seed through a BIOS. Console and disk operations remain
inside the auditable seed rather than depending on firmware services.

## Disk control block

Stage 1 reads sector zero as four little-endian 64-bit words:

| Offset | Value |
| ---: | --- |
| `0x00` | magic `0x3058565244485842` |
| `0x08` | first source sector |
| `0x10` | exact source length |
| `0x18` | first output sector |

It compiles exactly the declared source bytes and writes the result at the
output sector. This control block is the stage-1 composition interface, not a
replacement for the stage-2 memory filesystem.

## Build and test

Build the checked-in hex0 seed:

```sh
make riscv64-stage1
```

The independent oracle additionally requires a riscv64 GNU binutils toolchain:

```sh
make riscv64-stage1-oracle
```

That target assembles `builder-hex0-riscv64-stage1.S`, regenerates the
commented hex0 source, and proves both produce identical bytes. The assembly is
an executable specification and review aid; the checked-in hex0 is the seed.

Run the emulator tests with:

```sh
make test-riscv64-stage1
```

The tests cover mixed-case digits, both comment syntaxes, sector reads and
writes, legacy and modern virtio transports, and byte-identical self-building.

## Stage-2 plan

1. Port the internal shell, hex0 command, path handling, and memory filesystem.
2. Port delayed `/dev/hda` flushing to the virtio block driver.
3. Implement the Linux riscv64 syscall ABI: number in `a7`, arguments in
   `a0..a5`, result in `a0`.
4. Establish Sv39 process mappings, load fixed-address ELF64 little-endian
   stage0 programs, construct their entry stack, and dispatch user `ecall`
   traps in supervisor mode. The first stage0 seed is fixed at `0x600000`,
   below QEMU `virt` physical RAM, so relocating it is not a valid substitute.
5. Build the riscv64 `hex0-seed`, continue through M2-Planet, and compare the
   outputs with the existing native stage0-posix chain.

## Design and bug log

- The first prototype linked at the conventional OpenSBI payload address
  `0x80200000`. A reset trace showed that `-bios none` jumps to `0x80000000`,
  so the seed now uses the actual firmware-free entry address.
- The first virtio prototype assumed the block transport was always at
  `0x10001000`. QEMU assigns MMIO slots according to device ordering; the seed
  now scans the standard window for block device ID 2.
- QEMU 7.2 exposes legacy virtio-mmio by default. Requiring
  `force-legacy=false` would make the seed unnecessarily version-sensitive,
  so both queue layouts are implemented and tested.
- Queue setup initially selected the device maximum even when it exceeded the
  local eight-descriptor allocation. It now uses `min(device_max, 8)`.
- A bring-up fixture accidentally wrote its source-LBA word twice. The test
  harness now checks that every generated control block is exactly 32 bytes.
