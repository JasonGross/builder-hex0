# builder-hex0 on ARM

## Goal and architecture boundary

The ARM bootstrap already has a complete AArch64 stage0 seed, while GNU Mes
and the C-only GCC ladder continue in ARMv7 AArch32. The builder port therefore
uses the same boundary instead of inventing an unreviewed ARMv7 seed:

1. firmware-free AArch64 builder stages run the canonical AArch64 stage0
   inputs;
2. AArch64 M2-Planet emits the existing ARMv7 compiler boundary; and
3. the later builder shell transfers control to AArch32 before Mes.

Fiwix is a separate ARMv7 target. It starts after this pivot and will consume
the same ARMv7 executables proven by the existing user-mode chain. Calling
both halves simply "ARM" must not hide this ISA transition in tests or
artifact names.

The reference machine is QEMU `virt` with a Cortex-A53, 128 MiB or more of
RAM, PL011 at `0x09000000`, and a virtio-mmio block device in the standard
`0x0a000000..0x0a004000` window. QEMU's direct AArch64 kernel loader places
the firmware-free image at `0x40080000`. Stage 1 accepts entry at EL1 or EL2
and normalizes EL2 entry to EL1h without relying on an external firmware.

## Milestones and acceptance

1. **Stage 1:** compile hex0 from a disk control block, support modern and
   legacy virtio-mmio, and reproduce the checked-in stage-1 image byte for
   byte.
2. **Stage 2 ABI:** establish AArch64 EL0 execution, an ELF64 loader, and the
   Linux AArch64 syscall surface used by stage0-posix.
3. **Builder shell:** add memory files, process sequencing, delayed disk
   flush, and the canonical AArch64 stage0 chain through M2-Planet.
4. **AArch32 pivot:** load the ARMv7 M2-Planet output, enter AArch32 at the
   documented boundary, and continue into the already-proven Mes/TinyCC
   bootstrap.

Booting a custom fixture is evidence for a milestone, not completion of the
whole port. The final gate must use pinned stage0 inputs and compare generated
artifacts with the independent ARM pivot chain.

## Stage-1 disk contract

Sector zero contains four little-endian 64-bit words:

| Offset | Value |
| ---: | --- |
| `0x00` | magic `0x3058565244485842` (`BXHDRVX0`) |
| `0x08` | first source sector |
| `0x10` | exact source byte count |
| `0x18` | first output sector |

Stage 1 reads exactly the declared source, accepts mixed-case hexadecimal and
`#`/`;` line comments, and writes compiled bytes at the output sector.

## Build and test

The executable specification requires GNU AArch64 binutils. The emulator gate
requires `qemu-system-aarch64`.

```sh
make arm64-stage1-oracle
make test-arm64-stage1
```

The oracle regenerates the commented hex0 source and requires it to match the
checked-in seed exactly. The emulator gate checks parser output with modern
and legacy virtio-mmio, then has stage 1 rebuild itself and compares every
byte.

Stage 1 currently produces a 1,469-byte image with SHA-256
`93484544839ab46999c956798c9da672ab3c3729aac67ea4bba41c30c0c3f882`.
The oracle and both emulator transports pass.

Stage 2 establishes 39-bit translation tables, gives EL1 an identity-mapped
kernel/device address space, maps separate EL0 image and stack regions, and
enters an AArch64 executable through `eret`. With no block device it retains a
built-in privilege fixture. A disk with the stage-2 header below instead loads
and validates an ELF64/AArch64 `ET_EXEC`, copies every `PT_LOAD` segment,
clears BSS, and initializes the process break. The lower-EL synchronous vector
preserves all 31 general registers and implements raw Linux AArch64
`openat`/`close`/`lseek`/`read`/`write`/`brk`/`exit`/`exit_group` calls through
`svc`. A fixed-size bootstrap filesystem supplies `/input` and supports file
creation, truncation, rewinding, and bounded reads and writes.

| Offset | Value |
| ---: | --- |
| `0x00` | magic `BXHDRAE2` |
| `0x08` | first ELF sector |
| `0x10` | exact ELF byte count |

The checked hex0 reconstructs the 7,382-byte oracle image exactly; the current
SHA-256 is
`0f16757a7a4fd237b82f3a7270d95a36f74045f098ec7129dc194732ec2534a1`.
Run all three paths with:

```sh
make test-arm64-stage2
```

The gate runs the built-in fixture and the same disk ELF over legacy and modern
virtio-mmio. It pre-dirties BSS and heap pages, then proves that the ELF loader
and `brk` clear them. The `brk` growth crosses a 2 MiB block boundary, so the
test also covers every initial user mapping needed by the fixture. The
external process reads the seeded `/input`, creates and truncates `/output`,
writes it, seeks to the beginning, reads it back, and closes both descriptors.
Path normalization, unlink/access/chdir operations, process sequencing, and
the remaining stage0-posix syscall surface are the next stage-2 increments.

## Design and bug log

- The port deliberately starts in AArch64 rather than fabricating an ARMv7
  lower seed. This follows the chain's proven AArch64-to-AArch32 pivot and
  keeps seed provenance explicit.
- The image supports both EL2 and EL1 entry because QEMU and physical ARMv8
  boot environments do not share one reset exception level. EL2 entry is
  reduced to EL1h with AArch64 enabled for EL1.
- Virtio transports are discovered by device ID rather than fixed to the first
  slot. QEMU assigns the slot according to device construction order.
- Queue size is bounded by the eight descriptors reserved by the seed.
- Modern and legacy split queues use different address-registration layouts;
  each is an independent emulator gate.
- QEMU ARM does not implement RISC-V's `-bios none` spelling: it treats
  `none` as a ROM filename and aborts. The ARM harness omits `-bios` and uses
  QEMU's direct kernel handoff, which does not load an external firmware.
- The first legacy queue encoded `0x41000000 >> 12` as `0x4100` instead of
  `0x41000`. Modern virtio passed because it receives full addresses, while
  legacy waited forever on rings at the wrong physical address. The
  dual-transport parser gate exposed and now covers the PFN calculation.
- Stage 2 uses a 39-bit TTBR0 layout with a supervisor-only 1 GiB identity
  block and explicit low user mappings. This keeps the initial table small
  while ensuring EL0 cannot access the identity-mapped kernel, PL011, or
  virtio windows.
- The exception frame saves every AArch64 general register before syscall
  dispatch. Later disk and process code can extend the frame without changing
  the EL0 ABI already covered by the privilege gate.
- AArch64 writes the address after `svc` to `ELR_EL1`; it must not receive the
  explicit four-byte advance required by RISC-V `ecall`. The first gate copied
  that behavior, skipped the fixture's zero exit status, and entered the
  negative path after a successful `write`.
- The disk format records an exact ELF byte count rather than trusting whole
  sectors. The loader bounds the program-header table and every file and
  memory range against that count, the 16 MiB staging area, and the mapped
  user arena. Dynamic linking and PIE remain outside this bootstrap stage.
- The first memory-file increment uses 16 fixed file records, 32 descriptor
  records, 128-byte names, and 64 KiB payload slots. Those bounds keep the
  seed allocator-free while making exhaustion deterministic; later shell work
  can replace the fixed payload layout without changing the covered syscall
  ABI.
- Raw Linux `brk(0)` returns the current break. The first implementation
  branched directly to trap return and left the query argument (`0`) in `x0`;
  the disk ELF gate exposed this even though the stored break was correct.
- User block descriptors include high execute-never permission bits. The
  initial map loop compared that descriptor value with a physical endpoint
  and stopped after one block. A separate physical cursor now controls the
  loop, and the gate grows and reads the heap beyond the first 2 MiB mapping.
