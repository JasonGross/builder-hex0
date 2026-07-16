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

The stage-2 kernel and builder shell are implemented. M-mode establishes PMP and
Sv39, then enters U-mode through an S-mode kernel. A privilege smoke test
exercises Linux riscv64 `write` and `exit`; a second test loads and executes
the existing 392-byte riscv64 stage0-posix `hex0-seed` at its linked virtual
address and checks a parser fixture. The third gives that seed the complete
8,065-byte `hex0_riscv64.hex0` source and proves it reproduces its own ELF byte
for byte. The fourth replaces the fixed input/output descriptors used during
ABI bring-up with path lookup, a memory-file table, per-open offsets, and
`close`. The fifth implements the complete syscall set observed in the
riscv64 stage0-posix chain: `brk`, `clone`, `execve`, `wait4`, `exit`,
`openat`, `close`, `read`, `write`, `lseek`, `unlinkat`, `fchmodat`,
`faccessat`, and `chdir`. The internal shell streams source files from disk,
compiles hex0 in memory, launches stage0 ELF programs, resumes after process
exit, and writes `/dev/hda` through the same legacy-or-modern virtio transport.

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

Stage 2 selects shell mode when sector zero starts with this 24-byte control
block:

| Offset | Value |
| ---: | --- |
| `0x00` | ASCII magic `BXHDRSV2` |
| `0x08` | first script sector, little-endian `u64` |
| `0x10` | exact script length, little-endian `u64` |

The script supports `src LENGTH PATH`, `hex0 INPUT OUTPUT`, `f`, `halt`, and
an executable path with one optional argument. `src` consumes exactly LENGTH
following bytes, including newlines and NULs. As in the x86 builder, `f` marks
`/dev/hda` for a delayed flush: it is written before the next external command
or when the shell halts.

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
make test-riscv64-stage2-shell
make test-riscv64-stage2-stage0 \
  STAGE0_HEX0_SEED=/path/to/riscv64/hex0-seed
make test-riscv64-stage2-stage0-selfhost \
  STAGE0_HEX0_SEED=/path/to/riscv64/hex0-seed \
  STAGE0_HEX0_SOURCE=/path/to/riscv64/hex0_riscv64.hex0
make test-riscv64-stage2-chain \
  STAGE0_DIR=/path/to/stage0-posix
```

The focused emulator gates default to a 20-second limit. Set `TIMEOUT` to a
larger value on a loaded emulation host; the canonical chain has a separate
eight-hour default because M0 and M2-Planet are substantially more expensive.

The stage-1 tests cover mixed-case digits, both comment syntaxes, sector reads
and writes, legacy and modern virtio transports, and byte-identical
self-building. Stage 1 also compiles the checked-in stage-2 hex0 and compares it
with the independent assembler image. The stage-2 tests cover complete U-mode
register preservation, heap movement, descriptor and path operations,
clone/exec/exit/wait sequencing, U-mode trap entry, execution of the real
stage0-posix seed against a deterministic parser fixture, and byte-identical
reconstruction of that seed from its canonical hex0 source.
`test-riscv64-stage2-shell` additionally covers binary `src` input, internal
hex0 compilation, external ELF launch and return, exact `/dev/hda` length,
delayed flushing, and both virtio-mmio transport versions. The chain gate uses
the canonical stage0-posix sources rather than reduced fixtures.

## Stage-2 plan

1. **Complete:** implement the Linux riscv64 syscall ABI: number in `a7`,
   arguments in `a0..a5`, result in `a0`.
2. **Complete:** establish Sv39 process mappings, load fixed-address ELF64
   little-endian stage0 programs, construct their entry stack, and dispatch
   user `ecall` traps in supervisor mode. The loader walks every `PT_LOAD`
   segment, copies its file bytes, zeroes BSS, and derives the initial break.
3. **Complete:** provide lexical path normalization, memory-file records,
   descriptor offsets, clone/exec/exit/wait process sequencing, and the exact
   syscall surface used by stage0-posix.
4. **Complete:** port the internal shell and hex0 command, then launch the first
   user process from that shell instead of a test fixture.
5. **Complete:** port delayed `/dev/hda` flushing to the virtio block driver.
6. **Validation in progress:** build the canonical riscv64 stage0 sequence
   through M2-Planet and compare its output with an independently produced
   native-chain artifact.

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
- The real seed gate initially used hard-coded descriptor numbers and buffers
  for `/input` and `/output`. That proved the ELF loader but was not a usable
  filesystem contract. Stage 2 now resolves paths through newest-first file
  records, allocates per-open descriptors with independent offsets, bounds
  writes by available RAM, and finalizes the data bump pointer on `close`.
  The test input is merely the first read-only file seeded into that table.
  The shell and persistence work remain separate completion gates.
- A five-byte parser fixture was useful for ABI bring-up but did not prove the
  compiler against its real source. The self-host gate now loads
  `hex0_riscv64.hex0`, supplies an independent copy of the expected seed, and
  compares all 392 output bytes in the supervisor kernel before reporting
  success.
- A single-process kernel still needs Unix fork semantics for the sequential
  stage0 chain. `clone` therefore snapshots the parent trap frame, descriptor
  table, heap break, process image, and 2 MiB user stack into reserved high
  RAM. Child `exit` restores that snapshot and returns child PID 1 to the
  parent; `wait4` then completes immediately. This intentionally supports one
  child at a time and does not imply a scheduler.
- File payloads grow upward from `0x83000000`; parent snapshots occupy
  `0x86000000` and above. The file allocator is capped at the snapshot base so
  user-controlled writes cannot corrupt process restoration state. User
  virtual mappings cover `0x600000..0x1fffffff`, including the stage0 heap and
  stack, while kernel scratch buffers remain outside that range.
- `execve` first stages argument strings in kernel memory because loading the
  next ELF may overwrite the caller's image. It then walks all ELF64
  `PT_LOAD` headers, validates physical bounds, copies file-backed bytes,
  zero-fills BSS, rebuilds `argc`/`argv`/`envp` below the user stack, and uses
  the highest loaded address as the initial aligned break.
- Paths are normalized lexically before lookup. Absolute and relative names,
  repeated separators, `.`, and `..` therefore name the same record, while
  deleted newest-first records are ignored. The smoke test changes directory,
  accesses and changes mode through equivalent spellings, unlinks the file,
  and verifies the subsequent lookup fails.
- The syscall smoke test originally printed its success marker before its
  final checks. Since the Make target only grepped that marker, a later
  failure could be reported as success. The marker now follows every check,
  including clone/exec/wait and path mutation.
- The assembly-to-hex0 converter originally consumed every whitespace token
  on an `objdump -s` line. When the ASCII rendering began with `64`, it treated
  those characters as a fifth hex column and inserted a byte into the seed.
  Both section converters now consume exactly the four documented byte
  columns, and the byte-for-byte oracle caught and covers this case.
- Stage 2 initially existed only as GNU assembly, which left the stage-1 trust
  handoff untested. It now has a 20,346-byte checked-in hex0 source. The
  assembler oracle and stage-1-built output both produce the same 5,848-byte
  image (SHA-256
  `cd44e0e1490bffd90f8e1b3626682709354797ede78260d6bf8a1102be128de1`).
- Shell process launch originally reused the shell's supervisor stack as the
  user-trap stack. The user trap frame then overwrote the suspended shell
  return address: the command exited successfully, but the shell hung while
  returning. External shell commands now use a dedicated trap stack and
  restore the suspended supervisor stack only after user exit.
- `wait4` initially reported every child as successful. This hid the first
  failing command in a `kaem` chain and let later diagnostics point at the
  wrong file. Child exit now records the status and `wait4` returns the normal
  wait status (`exit_code << 8`) to the parent.
- The memory-file bump pointer originally advanced only on `close`. Canonical
  stage0 tools terminate without closing their output descriptors, so the next
  file reused and overwrote the previous executable. Every successful file
  write now advances the aligned allocation frontier; `close` remains an
  idempotent finalization path.
- The focused tests originally hard-coded a 20-second emulator timeout. A
  concurrent canonical chain could make a correct stage-1 build exceed that
  wall clock after emitting its success marker. The gates retain 20 seconds as
  their default but now honor a `TIMEOUT` override.
