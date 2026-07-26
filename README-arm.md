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
The oracle and both emulator transports pass. Stage 2 has not yet been
implemented.

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
