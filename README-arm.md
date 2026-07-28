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
enters an AArch64 or AArch32 executable through `eret`. With no block device
it retains a built-in AArch64 privilege fixture. A disk with the stage-2
header below instead loads and validates an ELF64/AArch64 or ELF32/ARM
`ET_EXEC`, copies every `PT_LOAD` segment, clears BSS, and initializes the
process break. The lower-EL synchronous vectors preserve the mapped general
registers and implement raw Linux AArch64
`unlinkat`/`faccessat`/`chdir`/`fchmodat`/`openat`/`close`/`lseek`/`read`/
`write`/`brk`/`clone`/`execve`/`wait4`/`exit`/`exit_group` calls through `svc`.
The AArch32 vector translates the ARM EABI
`open`/`close`/`unlink`/`access`/`chdir`/`lseek`/`read`/`write`/`brk`/`fork`/
`execve`/`wait4`/`exit`/`exit_group` numbers onto the same implementation.
A fixed-size bootstrap filesystem supplies `/input`, canonicalizes absolute
and cwd-relative paths, and supports file creation, truncation, lookup,
unlink, rewinding, and bounded reads and writes.

| Offset | Value |
| ---: | --- |
| `0x00` | magic `BXHDRAE2` |
| `0x08` | first ELF sector |
| `0x10` | exact ELF byte count |

The checked hex0 reconstructs the 13,032-byte oracle image exactly; the current
SHA-256 is
`2db5734815c8d220c849e531235c2d190c1296324acd20f428443813b506ad44`.
Run the covered paths with:

```sh
make test-arm64-stage2
make test-arm64-stage2-aarch32
make test-arm64-stage2-shell
STAGE0_DIR=/path/to/stage0 make test-arm64-stage2-chain
STAGE0_DIR=/path/to/completed/arm-pivot make test-arm64-stage2-pivot
```

The gates run the built-in fixture and disk ELFs over legacy and modern
virtio-mmio. They pre-dirty BSS and heap pages, then prove that both ELF
loaders and `brk` clear them. The AArch64 `brk` growth crosses a 2 MiB block
boundary, so the test also covers every initial user mapping needed by the
fixture. The external processes read the seeded `/input`, create and truncate
an output, write it, and close their descriptors.
It also canonicalizes repeated separators and dot components, changes its
virtual cwd, creates and finds a relative path, checks access, applies the
bootstrap chmod no-op, unlinks it, and verifies that a later lookup returns
`ENOENT`. Finally, it rejects a non-ELF exec, snapshots a parent with `clone`,
replaces the child through `execve`, restores the parent on child exit, and
checks the child's argv-dependent status through `wait4`. The AArch32 gate
also forks an ARM parent, execs the embedded AArch64 child, checks status
`0x700`, and proves that the parent's 32-bit registers, stack, process image,
and low virtual mappings are restored. Canonical stage0 inputs and any syscall
gaps they expose are the next increments.

The internal shell uses a separate sector-zero contract:

| Offset | Value |
| ---: | --- |
| `0x00` | magic `BXHDRAV2` |
| `0x08` | first script sector |
| `0x10` | exact script byte count |

It streams `src N PATH` payloads without loading the script into RAM, compiles
`hex0 INPUT OUTPUT`, launches AArch64 or AArch32 ELF commands with up to 31
arguments, delays an `f` request until the next external command, and writes
the newest `/dev/hda` at `halt`. It emits LP64 or ILP32 startup pointers to
match the loaded ELF. The focused gate streams a 66 KiB ELF, executes it,
compiles a mixed-case/commented hex0 fixture, flushes five exact bytes to
sector zero, and checks both virtio transports. Running the canonical
AArch64 stage0 inputs through M2-Planet is the acceptance boundary for
milestone 3.

That boundary now passes. The chain gate streams the source set used by the
independent ARM pivot, builds AArch64 hex0, hex1, catm, M0, cc_aarch64, and
M2-Planet, then flushes the final 422,501-byte M2 ELF. Legacy and modern
virtio both reproduce SHA-256
`fa8db2bf931ac933157621e0894b4dddf15fb2bf585e4f6a5d32f20a058f1bef`,
matching the user-mode pivot artifact byte for byte. The AArch32 execution
pivot now has a focused gate: an ELF32/ARM image enters AArch32 EL0, exercises
the ARM EABI and BSS/stack contract, returns to the AArch64 builder shell, and
validates 32-bit `argc`/`argv`/`envp`. The gate passes both virtio transports.
The pivot gate then runs the ARMv7 M2-Planet produced by the independent
user-mode pivot with its real 31-entry argument vector. Both transports
produce the same 376,490-byte M1 output, SHA-256
`9c3a8e2878c673b074a51157704fd84c8f92f96b0506c93a390e469b9f8cc543`.
This completes the builder's AArch64-to-AArch32 execution handoff; deriving
the ARMv7 M2-Planet inside the builder, instead of supplying the independently
checked artifact, remains an end-to-end provenance improvement.

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
- Files must be stored under one canonical absolute name. Normalization now
  collapses repeated separators, removes `.` components, resolves `..`
  without escaping root, and rejects names that exceed the fixed 128-byte
  representation before lookup or creation.
- Unlink leaves a tombstone in the append-only bootstrap file table so open
  descriptors remain valid. The first lookup loop dereferenced that zero name
  pointer; it now skips tombstones, and the fixture performs a lookup after
  unlink to cover the failure mode.
- Process sequencing deliberately permits one synchronous child. `clone`
  saves the parent trap frame, used image bytes, full 2 MiB stack, descriptor
  table, cwd, and break state in fixed EL1-only regions. Child exit restores
  that state before returning `1` from the parent's original clone call.
- `execve` must preserve argv before loading `PT_LOAD` segments over the old
  process. It copies at most 31 arguments and 3 KiB of strings to EL1-only
  scratch, rebuilds the Linux AArch64 startup stack, and clears the new
  register frame. An embedded ELF validates argc, both arguments, and the
  null terminator before exiting with the status checked by `wait4`.
- The original 16 fixed 64 KiB payload slots could not ingest a 66 KiB test
  ELF and occupied physical pages inside the permitted user heap. Shell files
  now use 256 fixed metadata/name records and a checked 24 MiB monotonic
  payload arena immediately above user memory and below ELF staging.
- Append-only versions require newest-first lookup. The first ARM table walk
  scanned from record zero and would have returned stale output after a path
  was recreated; lookup now walks backward and still skips unlink tombstones.
- Virtio write descriptors invert the data-buffer direction used by reads.
  The shared request path now sets request type and descriptor flags from an
  explicit direction, while the dual-transport shell gate checks the mutated
  disk bytes after QEMU exits.
- The first shell exit fixture had an empty second `PT_LOAD` at virtual
  address zero because the shared linker script advertised an empty data
  segment. Adding one real data byte makes the segment valid and keeps the
  kernel's low-address ELF rejection covered.
- The ELF identification check compared eight bytes at once and accidentally
  required System V OSABI 0. Canonical stage0 uses valid GNU/Linux OSABI 3;
  the loader now checks only magic, class, endianness, and identification
  version.
- Canonical `hex2-0` advertises 148 final `PT_LOAD` bytes beyond the physical
  end of its file, relying on the zeroed final page accepted by Linux. The
  loader permits only a final short tail of at most 4,095 bytes and zero-fills
  it; offsets outside the file and larger truncations remain fatal.
- The first 26 MiB user arena physically crossed the stage-2 page tables and
  virtqueue pages. M0's 18 MiB break request zeroed the page tables and caused
  a recursive EL1 fault. All kernel control pages now live below the user
  arena, with compile-time checks around every later fixed region.
- cc_aarch64 needs more than the initial 2 MiB stack, and M0 needs more than
  the initial 26 MiB process arena when assembling M2. Stage 2 now maps and
  snapshots an 8 MiB stack and provides a compacted 32 MiB process arena
  without increasing the 128 MiB machine requirement.
- Trap failures now report `ESR_EL1`, `ELR_EL1`, and `FAR_EL1`. Those
  diagnostics identified both the page-table overwrite and exact stack/heap
  boundaries; the success gates reject any occurrence of the failure marker.
- Returning to an AArch32 lower EL requires an AArch32 CPSR value, not the
  numerically similar AArch64 PSTATE mask. The first pivot used `0x3d0`;
  AArch32 interprets bit 9 as the data-endianness bit, so user instructions
  ran but literal loads were byte-swapped. The corrected `0x1d0` selects
  little-endian ARM user mode with asynchronous exceptions masked.
- AArch32 user registers map onto the low halves of the AArch64 register bank.
  The SVC32 vector saves the complete bank first, then explicitly zero-extends
  R0-R7 before shared pointer arithmetic because their upper halves are
  architecturally unknown.
- The focused ELF32 fixture initially hid a layout mismatch by linking at the
  AArch64 seed's `0x00600000` base. Canonical ARMv7 stage0 links at
  `0x00010000`. The loader now remaps the same 32 MiB physical process arena
  to `0x00600000..0x02600000` for AArch64 or
  `0x00000000..0x02000000` for AArch32 and invalidates stale translations
  whenever an ELF changes the execution state.
- A child can change execution state during `execve`, so restoring only its
  parent's memory and AArch64 trap frame is insufficient. `clone` now also
  saves the parent's ABI and `SPSR_EL1`, computes snapshot length from the
  ABI-specific virtual base, and `exit` reinstalls the matching page map and
  exception-return state. `execve` reads the old argv using 32- or 64-bit
  pointers and independently constructs the new ELF's ILP32 or LP64 stack.
