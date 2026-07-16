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

The first three stage-2 gates are implemented. M-mode establishes PMP and
Sv39, then enters U-mode through an S-mode kernel. A privilege smoke test
exercises Linux riscv64 `write` and `exit`; a second test loads and executes
the existing 392-byte riscv64 stage0-posix `hex0-seed` at its linked virtual
address and checks a parser fixture. The third gives that seed the complete
8,065-byte `hex0_riscv64.hex0` source and proves it reproduces its own ELF byte
for byte. This is an executable ELF/ABI and first self-hosting foundation, not
yet the full builder environment.

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
make riscv64-stage2-oracle
```

That target assembles `builder-hex0-riscv64-stage1.S`, regenerates the
commented hex0 source, and proves both produce identical bytes. The assembly is
an executable specification and review aid; the checked-in hex0 is the seed.
The stage-2 oracle does the same for `builder-hex0-riscv64-stage2.S` and its
checked-in hex0 image.

Run the emulator tests with:

```sh
make test-riscv64-stage1
make test-riscv64-stage2
make test-riscv64-stage2-stage0 \
  STAGE0_HEX0_SEED=/path/to/riscv64/hex0-seed
make test-riscv64-stage2-stage0-selfhost \
  STAGE0_HEX0_SEED=/path/to/riscv64/hex0-seed \
  STAGE0_HEX0_SOURCE=/path/to/riscv64/hex0_riscv64.hex0
```

The stage-1 tests cover mixed-case digits, both comment syntaxes, sector reads
and writes, legacy and modern virtio transports, and byte-identical
self-building. Stage 1 also compiles the checked-in stage-2 hex0 and compares it
with the independent assembler image. The stage-2 tests cover U-mode trap
entry, execution of the real stage0-posix seed against a deterministic parser
fixture, and byte-identical reconstruction of that seed from its canonical
hex0 source.

## Stage-2 plan

1. Port the internal shell, hex0 command, path handling, and memory filesystem.
2. Port delayed `/dev/hda` flushing to the virtio block driver.
3. Implement the Linux riscv64 syscall ABI: number in `a7`, arguments in
   `a0..a5`, result in `a0`.
4. Establish Sv39 process mappings, load fixed-address ELF64 little-endian
   stage0 programs, construct their entry stack, and dispatch user `ecall`
   traps in supervisor mode. This gate is complete for the first `hex0-seed`,
   which is fixed at `0x600000`, below QEMU `virt` physical RAM; relocating it
   is not a valid substitute.
5. Build the riscv64 `hex0-seed`, continue through M2-Planet, and compare the
   outputs with the existing native stage0-posix chain. The `hex0-seed`
   self-build is complete; the later tools remain pending.

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
- The first supervisor syscall handler faulted while reading a user buffer.
  RISC-V deliberately blocks S-mode data access to U pages unless
  `sstatus.SUM` is set. Enabling SUM at supervisor entry fixed the trap and the
  test now proves U-mode `write` followed by `exit` through the S-mode handler.
- The initial trap frame saved only the temporary and argument registers used
  by `hex0-seed`. That was sufficient for the first gate but violated the
  process ABI as soon as the kernel grew enough to use saved registers itself.
  The frame now preserves every user integer register except `a0`, which holds
  the syscall result, and `sp`, which remains in `sscratch`. The U-mode smoke
  fixture primes and verifies all preserved register classes across `write`.
- A stage-2 test that copied the seed to convenient physical RAM would not
  validate its actual contract: the existing ELF is linked at virtual
  `0x600000`, outside QEMU `virt` RAM. Stage 2 now reads the ELF64 program
  header, maps the load address with Sv39, constructs `argc`/`argv`, and enters
  at ELF `e_entry`.
- The real seed gate deliberately uses a small in-memory file shim for
  `/input` and `/output`. This proves the ELF loader and Linux syscall ABI
  before those paths are connected to the builder memory filesystem; it is
  not counted as completion of the shell or persistence work.
- A five-byte parser fixture was useful for ABI bring-up but did not prove the
  compiler against its real source. The self-host gate now loads
  `hex0_riscv64.hex0`, supplies an independent copy of the expected seed, and
  compares all 392 output bytes in the supervisor kernel before reporting
  success.
- Stage 2 initially existed only as GNU assembly, which left the stage-1 trust
  handoff untested. It now has an 8,270-byte checked-in hex0 source. The
  assembler oracle and stage-1-built output both produce the same 2,336-byte
  image (SHA-256
  `c2595146c61ccd1ca04e97b02b7a6baa738c4d295202279e341f6a4f77b7f57d`).
