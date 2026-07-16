/* SPDX-License-Identifier: MIT
 *
 * RISC-V 64 builder-hex0 stage-2 kernel and internal builder shell.
 */

    .option norvc
    .section .text.boot
    .globl _start

    .equ UART0,              0x10000000
    .equ TEST_FINISHER,      0x00100000
    .equ VIRTIO_FIRST,       0x10001000
    .equ VIRTIO_END,         0x10009000
    .equ ROOT_PAGE_TABLE,    0x81000000
    .equ LOW_PAGE_TABLE,     0x81001000
    .equ USER_PHYS,          0x80600000
    .equ USER_VIRT,          0x00600000
    .equ USER_HEAP_TOP,      0x02000000
    .equ USER_STACK_PHYS,    0x87e00000
    .equ USER_STACK_TOP,     0x08000000
    .equ KERNEL_STACK_TOP,   0x87dff000
    .equ ELF_SOURCE,         0x82000000
    .equ INPUT_SOURCE,       0x82200000
    .equ OUTPUT_FILE,        0x82400000
    .equ EXPECTED_SOURCE,    0x82600000
    .equ EXPECTED_LENGTH,    0x82800000
    .equ FILE_TABLE,         0x83000000
    .equ FD_TABLE,           0x83010000
    .equ VIRTQ_DESC,         0x83800000
    .equ VIRTQ_AVAIL,        0x83801000
    .equ VIRTQ_USED,         0x83802000
    .equ VIRTIO_HEADER,      0x83803000
    .equ VIRTIO_STATUS,      0x83803010
    .equ SECTOR_BUFFER,      0x83804000
    .equ FILE_DATA,          0x84000000
    .equ PARENT_FDS,         0x83f00000
    .equ PARENT_FRAME,       0x83f02000
    .equ EXEC_ARGV,          0x83f04000
    .equ EXEC_STRINGS,       0x83f05000
    .equ PATH_BUFFER,        0x83f07000
    .equ CWD_BUFFER,         0x83f08000
    .equ SHELL_LINE_BUFFER,  0x83f09000
    .equ SHELL_TRAP_STACK,   0x83f0c000
    .equ PARENT_PROCESS,     0x86000000
    .equ PARENT_STACK,       0x87a00000
    .equ FILE_RECORD_SIZE,   32
    .equ FD_RECORD_SIZE,     24
    .equ SHELL_HEADER_MAGIC, 0x3256535244485842

_start:
    li      sp, KERNEL_STACK_TOP
    li      t0, UART0
    li      t1, 3
    sb      t1, 3(t0)              /* 8n1 */

    /* A valid block header selects the internal-shell boot path. */
    call    virtio_init_optional
    beqz    a0, 1f
    li      a0, 0
    li      a1, SECTOR_BUFFER
    call    read_sector
    li      t0, SECTOR_BUFFER
    ld      t1, 0(t0)
    li      t2, SHELL_HEADER_MAGIC
    bne     t1, t2, 1f
    la      t2, shell_mode
    li      t3, 1
    sd      t3, 0(t2)
    ld      t1, 8(t0)
    la      t2, shell_lba
    sd      t1, 0(t2)
    ld      t1, 16(t0)
    la      t2, shell_remaining
    sd      t1, 0(t2)
1:

    la      t0, shell_mode
    ld      t0, 0(t0)
    bnez    t0, load_shell

    /* Prefer an ELF supplied in reserved RAM; otherwise use the smoke fixture. */
    li      t0, ELF_SOURCE
    lwu     t1, 0(t0)
    li      t2, 0x464c457f
    bne     t1, t2, load_smoke_fixture
    call    load_test_elf
    li      t0, 1
    la      t1, external_elf
    sd      t0, 0(t1)
    j       image_loaded

load_shell:
    la      t0, user_entry_address
    sd      zero, 0(t0)
    j       image_loaded

load_smoke_fixture:
    la      t0, user_start
    la      t1, user_end
    li      t2, USER_PHYS
1:  bgeu    t0, t1, 2f
    lbu     t3, 0(t0)
    sb      t3, 0(t2)
    addi    t0, t0, 1
    addi    t2, t2, 1
    j       1b

2:  li      t0, USER_VIRT
    la      t1, user_entry_address
    sd      t0, 0(t1)

image_loaded:
    la      t0, shell_mode
    ld      t0, 0(t0)
    bnez    t0, init_empty_filesystem

    /* Determine the NUL-terminated test input length. */
    li      t0, INPUT_SOURCE
    mv      t1, t0
4:  lbu     t2, 0(t1)
    beqz    t2, 5f
    addi    t1, t1, 1
    j       4b
5:  sub     t1, t1, t0
    la      t2, input_length
    sd      t1, 0(t2)

    /* Seed the memory filesystem with the test's read-only /input file. */
    li      t2, FILE_TABLE
    la      t3, input_name
    sd      t3, 0(t2)              /* name */
    li      t3, INPUT_SOURCE
    sd      t3, 8(t2)              /* data */
    sd      t1, 16(t2)             /* length */
    sd      t1, 24(t2)             /* capacity */
    addi    t2, t2, FILE_RECORD_SIZE
    la      t3, exec_target_name
    sd      t3, 0(t2)
    la      t3, builtin_exec_elf
    sd      t3, 8(t2)
    la      t4, builtin_exec_elf_end
    sub     t4, t4, t3
    sd      t4, 16(t2)
    sd      t4, 24(t2)
    la      t2, file_count
    li      t3, 2
    sd      t3, 0(t2)
    j       init_filesystem_common

init_empty_filesystem:
    la      t2, file_count
    sd      zero, 0(t2)

init_filesystem_common:
    la      t2, next_file_data
    li      t3, FILE_DATA
    sd      t3, 0(t2)
    li      t0, CWD_BUFFER
    li      t1, '/'
    sb      t1, 0(t0)
    sb      zero, 1(t0)

    /* Build argc/argv at user VA 0x07fff000 (PA 0x87fff000). */
    li      t0, 0x87fff000
    li      t1, 3
    sd      t1, 0(t0)
    li      t1, 0x07fff100
    sd      t1, 8(t0)
    li      t1, 0x07fff110
    sd      t1, 16(t0)
    li      t1, 0x07fff120
    sd      t1, 24(t0)
    sd      zero, 32(t0)
    sd      zero, 40(t0)
    la      t1, process_name
    addi    t0, t0, 0x100
    call    copy_string
    la      t1, input_name
    li      t0, 0x87fff110
    call    copy_string
    la      t1, output_name
    li      t0, 0x87fff120
    call    copy_string

    /* Zero both page-table pages. */
    li      t0, ROOT_PAGE_TABLE
    li      t1, LOW_PAGE_TABLE + 4096
6:  sd      zero, 0(t0)
    addi    t0, t0, 8
    bltu    t0, t1, 6b

    /* root[0] -> low level-1 table */
    li      t0, ROOT_PAGE_TABLE
    li      t1, LOW_PAGE_TABLE
    srli    t1, t1, 2
    ori     t1, t1, 1
    sd      t1, 0(t0)

    /* root[2]: identity-map kernel's 0x80000000..0xbfffffff. */
    li      t1, 0x80000000
    srli    t1, t1, 2
    ori     t1, t1, 0xcf           /* V R W X A D */
    sd      t1, 16(t0)

    li      t0, LOW_PAGE_TABLE
    li      t1, 0xcf
    sd      t1, 0(t0)              /* VA 0..2 MiB identity: finisher */

    /* VA 0x600000..0x1fffffff -> PA 0x80600000..., user R/W/X. */
    li      t1, USER_PHYS
    addi    t0, t0, 24             /* level-1 index 3 */
    li      t2, 13                 /* thirteen 2 MiB leaves */
7:  srli    t3, t1, 2
    ori     t3, t3, 0xdf           /* V R W X U A D */
    sd      t3, 0(t0)
    addi    t0, t0, 8
    li      t3, 0x200000
    add     t1, t1, t3
    addi    t2, t2, -1
    bnez    t2, 7b

    /* VA 0x07e00000 -> PA 0x87e00000, user stack. */
    li      t0, LOW_PAGE_TABLE
    li      t1, USER_STACK_PHYS
    srli    t1, t1, 2
    ori     t1, t1, 0xd7           /* V R W U A D */
    sd      t1, 504(t0)            /* level-1 index 63 */

    /* VA 0x10000000 -> PA 0x10000000, supervisor MMIO. */
    li      t1, UART0
    srli    t1, t1, 2
    ori     t1, t1, 0xcf
    sd      t1, 1024(t0)           /* level-1 index 128 */

    /* Give S/U modes access to all physical addresses. */
    li      t0, -1
    csrw    pmpaddr0, t0
    li      t0, 0x0f               /* TOR, R/W/X */
    csrw    pmpcfg0, t0

    /* Delegate user ecalls to supervisor mode and enter S mode. */
    li      t0, 1 << 8
    csrw    medeleg, t0
    csrw    mideleg, zero
    csrr    t0, mstatus
    li      t1, ~(3 << 11)
    and     t0, t0, t1
    li      t1, 1 << 11            /* MPP = S */
    or      t0, t0, t1
    csrw    mstatus, t0
    la      t0, supervisor_entry
    csrw    mepc, t0
    mret

supervisor_entry:
    li      t0, ROOT_PAGE_TABLE
    srli    t0, t0, 12
    li      t1, 8
    slli    t1, t1, 60             /* Sv39 */
    or      t0, t0, t1
    csrw    satp, t0
    sfence.vma

    la      t0, supervisor_trap
    csrw    stvec, t0
    li      t0, KERNEL_STACK_TOP
    csrw    sscratch, t0
    la      t0, user_entry_address
    ld      t0, 0(t0)
    csrw    sepc, t0
    csrr    t0, sstatus
    li      t1, ~(1 << 8)          /* SPP = U */
    and     t0, t0, t1
    li      t1, (1 << 5) | (1 << 18) /* SPIE | SUM */
    or      t0, t0, t1
    csrw    sstatus, t0
    la      t0, shell_mode
    ld      t0, 0(t0)
    bnez    t0, supervisor_shell
    li      sp, USER_STACK_TOP - 4096
    sret

supervisor_shell:
    li      sp, KERNEL_STACK_TOP
    call    internal_shell
    j       syscall_exit_finish

supervisor_trap:
    csrrw   sp, sscratch, sp
    addi    sp, sp, -256
    sd      ra, 0(sp)
    sd      gp, 8(sp)
    sd      tp, 16(sp)
    sd      t0, 24(sp)
    sd      t1, 32(sp)
    sd      t2, 40(sp)
    sd      s0, 48(sp)
    sd      s1, 56(sp)
    sd      a0, 64(sp)
    sd      a1, 72(sp)
    sd      a2, 80(sp)
    sd      a3, 88(sp)
    sd      a4, 96(sp)
    sd      a5, 104(sp)
    sd      a6, 112(sp)
    sd      a7, 120(sp)
    sd      s2, 128(sp)
    sd      s3, 136(sp)
    sd      s4, 144(sp)
    sd      s5, 152(sp)
    sd      s6, 160(sp)
    sd      s7, 168(sp)
    sd      s8, 176(sp)
    sd      s9, 184(sp)
    sd      s10, 192(sp)
    sd      s11, 200(sp)
    sd      t3, 208(sp)
    sd      t4, 216(sp)
    sd      t5, 224(sp)
    sd      t6, 232(sp)

    csrr    t0, scause
    li      t1, 8                  /* ecall from U mode */
    bne     t0, t1, trap_failure
    csrr    t0, sepc
    addi    t0, t0, 4
    csrw    sepc, t0

    li      t0, 64                 /* Linux riscv64 write */
    beq     a7, t0, syscall_write
    li      t0, 56                 /* Linux riscv64 openat */
    beq     a7, t0, syscall_openat
    li      t0, 63                 /* Linux riscv64 read */
    beq     a7, t0, syscall_read
    li      t0, 57                 /* Linux riscv64 close */
    beq     a7, t0, syscall_close
    li      t0, 35                 /* Linux riscv64 unlinkat */
    beq     a7, t0, syscall_unlinkat
    li      t0, 48                 /* Linux riscv64 faccessat */
    beq     a7, t0, syscall_faccessat
    li      t0, 49                 /* Linux riscv64 chdir */
    beq     a7, t0, syscall_chdir
    li      t0, 53                 /* Linux riscv64 fchmodat */
    beq     a7, t0, syscall_fchmodat
    li      t0, 62                 /* Linux riscv64 lseek */
    beq     a7, t0, syscall_lseek
    li      t0, 214                /* Linux riscv64 brk */
    beq     a7, t0, syscall_brk
    li      t0, 220                /* Linux riscv64 clone */
    beq     a7, t0, syscall_clone
    li      t0, 221                /* Linux riscv64 execve */
    beq     a7, t0, syscall_execve
    li      t0, 260                /* Linux riscv64 wait4 */
    beq     a7, t0, syscall_wait4
    li      t0, 93                 /* Linux riscv64 exit */
    beq     a7, t0, syscall_exit
    li      a0, -38                /* -ENOSYS */
    j       trap_return

syscall_write:
    li      t0, 1
    beq     a0, t0, 1f
    li      t0, 2
    beq     a0, t0, 1f
    j       syscall_write_file
1:  mv      t0, a1
    mv      t1, a2
    li      a0, 0
2:  beqz    t1, trap_return
    lbu     a3, 0(t0)
    li      t2, UART0
3:  lbu     a4, 5(t2)
    andi    a4, a4, 0x20
    beqz    a4, 3b
    sb      a3, 0(t2)
    addi    t0, t0, 1
    addi    t1, t1, -1
    addi    a0, a0, 1
    j       2b

syscall_bad_fd:
    li      a0, -9                 /* -EBADF */
    j       trap_return

syscall_openat:
    mv      a0, a1
    li      a1, PATH_BUFFER
    call    normalize_path
    beqz    a0, syscall_name_too_long
    mv      s0, a0                 /* canonical pathname */
    mv      s1, a2                 /* flags */
    mv      a0, s0
    call    find_file
    beqz    a0, 1f
    beqz    s1, 2f                 /* read-only open of existing file */
    /* A writable open creates a new empty version of the same path. */
1:  beqz    s1, syscall_no_entry
    mv      a0, s0
    call    create_file
    beqz    a0, syscall_no_space
2:  mv      s2, a0                 /* file record */
    la      t0, next_fd
    ld      a0, 0(t0)
    addi    t1, a0, 1
    sd      t1, 0(t0)
    li      t0, FD_TABLE
    slli    t1, a0, 4
    slli    t2, a0, 3
    add     t1, t1, t2
    add     t0, t0, t1
    sd      s2, 0(t0)
    sd      zero, 8(t0)
    sd      s1, 16(t0)
    j       trap_return

syscall_read:
    li      t0, FD_TABLE
    slli    t1, a0, 4
    slli    t2, a0, 3
    add     t1, t1, t2
    add     t0, t0, t1
    ld      t3, 0(t0)              /* file record */
    beqz    t3, syscall_bad_fd
    ld      t1, 8(t0)              /* offset */
    ld      t2, 16(t3)             /* file length */
    bgeu    t1, t2, syscall_read_eof
    sub     t2, t2, t1
    bleu    a2, t2, 1f
    mv      a2, t2
1:  ld      t2, 8(t3)              /* file data */
    add     t2, t2, t1
    mv      a0, a2
2:  beqz    a2, 3f
    lbu     a3, 0(t2)
    sb      a3, 0(a1)
    addi    t2, t2, 1
    addi    a1, a1, 1
    addi    a2, a2, -1
    addi    t1, t1, 1
    j       2b
3:  sd      t1, 8(t0)
    j       trap_return
syscall_read_eof:
    li      a0, 0
    j       trap_return

syscall_write_file:
    li      t0, FD_TABLE
    slli    t1, a0, 4
    slli    t2, a0, 3
    add     t1, t1, t2
    add     t0, t0, t1
    ld      t3, 0(t0)              /* file record */
    beqz    t3, syscall_bad_fd
    ld      t1, 8(t0)              /* offset */
    ld      t2, 24(t3)             /* capacity */
    sub     t2, t2, t1
    bgtu    a2, t2, syscall_no_space
    ld      t2, 8(t3)              /* file data */
    add     t2, t2, t1
    mv      a0, a2
1:  beqz    a2, 2f
    lbu     a3, 0(a1)
    sb      a3, 0(t2)
    addi    a1, a1, 1
    addi    t2, t2, 1
    addi    a2, a2, -1
    addi    t1, t1, 1
    j       1b
2:  sd      t1, 8(t0)
    ld      t2, 16(t3)
    bleu    t1, t2, 3f
    sd      t1, 16(t3)
3:  ld      t1, 8(t3)
    ld      t2, 16(t3)
    add     t1, t1, t2
    addi    t1, t1, 15
    li      t2, -16
    and     t1, t1, t2
    la      t2, next_file_data
    ld      t4, 0(t2)
    bleu    t1, t4, 4f
    sd      t1, 0(t2)
4:
    j       trap_return

syscall_close:
    li      t0, FD_TABLE
    slli    t1, a0, 4
    slli    t2, a0, 3
    add     t1, t1, t2
    add     t0, t0, t1
    ld      t1, 0(t0)
    beqz    t1, syscall_bad_fd
    ld      t2, 8(t1)
    ld      t3, 16(t1)
    add     t2, t2, t3
    addi    t2, t2, 15
    li      t3, -16
    and     t2, t2, t3
    la      t3, next_file_data
    ld      t4, 0(t3)
    bleu    t2, t4, 1f
    sd      t2, 0(t3)
1:
    sd      zero, 0(t0)
    li      a0, 0
    j       trap_return

syscall_unlinkat:
    mv      a0, a1
    li      a1, PATH_BUFFER
    call    normalize_path
    beqz    a0, syscall_name_too_long
    call    find_file
    beqz    a0, syscall_no_entry
    sd      zero, 0(a0)
    li      a0, 0
    j       trap_return

syscall_faccessat:
syscall_fchmodat:
    mv      a0, a1
    li      a1, PATH_BUFFER
    call    normalize_path
    beqz    a0, syscall_name_too_long
    call    find_file
    beqz    a0, syscall_no_entry
    li      a0, 0
    j       trap_return

syscall_chdir:
    li      a1, PATH_BUFFER
    call    normalize_path
    beqz    a0, syscall_name_too_long
    mv      t1, a0
    li      t0, CWD_BUFFER
    call    copy_string
    li      a0, 0
    j       trap_return

syscall_lseek:
    li      t0, FD_TABLE
    slli    t1, a0, 4
    slli    t2, a0, 3
    add     t1, t1, t2
    add     t0, t0, t1
    ld      t1, 0(t0)
    beqz    t1, syscall_bad_fd
    beqz    a2, 1f                 /* SEEK_SET */
    li      t2, 1
    beq     a2, t2, 2f             /* SEEK_CUR */
    li      t2, 2
    bne     a2, t2, syscall_invalid
    ld      t2, 16(t1)             /* SEEK_END */
    add     a1, t2, a1
    j       1f
2:  ld      t2, 8(t0)
    add     a1, t2, a1
1:  bltz    a1, syscall_invalid
    sd      a1, 8(t0)
    mv      a0, a1
    j       trap_return

syscall_brk:
    la      t0, process_brk
    beqz    a0, 1f
    li      t1, USER_VIRT
    bltu    a0, t1, 1f
    li      t1, USER_HEAP_TOP
    bgeu    a0, t1, 1f
    sd      a0, 0(t0)
1:  ld      a0, 0(t0)
    j       trap_return

syscall_clone:
    la      t0, child_process
    ld      t1, 0(t0)
    bnez    t1, syscall_try_again

    /* Preserve the parent trap frame and process control values. */
    mv      t0, sp
    li      t1, PARENT_FRAME
    li      t2, 32
1:  ld      t3, 0(t0)
    sd      t3, 0(t1)
    addi    t0, t0, 8
    addi    t1, t1, 8
    addi    t2, t2, -1
    bnez    t2, 1b
    csrr    t0, sepc
    la      t1, parent_sepc
    sd      t0, 0(t1)
    csrr    t0, sscratch
    la      t1, parent_user_sp
    sd      t0, 0(t1)
    la      t0, process_brk
    ld      t0, 0(t0)
    la      t1, parent_brk
    sd      t0, 0(t1)
    la      t0, next_fd
    ld      t0, 0(t0)
    la      t1, parent_next_fd
    sd      t0, 0(t1)

    /* Snapshot used process memory, the complete user stack, and fd table. */
    la      t0, process_brk
    ld      t2, 0(t0)
    li      t0, USER_VIRT
    sub     t2, t2, t0
    addi    t2, t2, 7
    srli    t2, t2, 3
    la      t0, parent_process_words
    sd      t2, 0(t0)
    li      t0, USER_PHYS
    li      t1, PARENT_PROCESS
    call    copy_words
    li      t0, USER_STACK_PHYS
    li      t1, PARENT_STACK
    li      t2, 0x40000            /* 2 MiB / 8 */
    call    copy_words
    li      t0, FD_TABLE
    li      t1, PARENT_FDS
    li      t2, 768                /* 256 records * 24 bytes / 8 */
    call    copy_words

    la      t0, child_process
    li      t1, 1
    sd      t1, 0(t0)
    li      a0, 0                  /* child return */
    j       trap_return

syscall_execve:
    mv      s1, a1                 /* argv */
    li      a1, PATH_BUFFER
    call    normalize_path
    beqz    a0, syscall_name_too_long
    mv      s0, a0                 /* canonical pathname */
    call    find_file
    beqz    a0, syscall_no_entry
    ld      s2, 8(a0)              /* ELF image */
    lwu     t0, 0(s2)
    li      t1, 0x464c457f
    bne     t0, t1, syscall_exec_format

    /* Copy argv out of the old image before PT_LOAD overwrites it. */
    li      t0, EXEC_ARGV
    li      t1, EXEC_STRINGS
    li      s4, 0
1:  beqz    s1, 4f
    ld      t2, 0(s1)
    beqz    t2, 4f
    li      t3, 31
    bgeu    s4, t3, syscall_arg_too_big
    sd      t1, 0(t0)
2:  li      t3, EXEC_STRINGS + 0xc00
    bgeu    t1, t3, syscall_arg_too_big
    lbu     t3, 0(t2)
    sb      t3, 0(t1)
    addi    t1, t1, 1
    addi    t2, t2, 1
    bnez    t3, 2b
    addi    t0, t0, 8
    addi    s1, s1, 8
    addi    s4, s4, 1
    j       1b
4:
    mv      a0, s2
    call    load_elf
    mv      s3, a0                 /* entry */

    /* Construct argc/argv/envp in the top user-stack page. */
    li      s0, 0x87fff000
    sd      s4, 0(s0)
    addi    s1, s0, 8              /* argv pointer slots */
    li      s2, 0x87fff400          /* copied strings */
    li      t0, EXEC_ARGV
    li      t1, 0
5:  bgeu    t1, s4, 6f
    li      t2, 0x80000000
    sub     t2, s2, t2             /* physical stack address -> user VA */
    sd      t2, 0(s1)
    ld      t2, 0(t0)
    mv      t3, s2
7:  lbu     t4, 0(t2)
    sb      t4, 0(t3)
    addi    t2, t2, 1
    addi    t3, t3, 1
    bnez    t4, 7b
    mv      s2, t3
    addi    s1, s1, 8
    addi    t0, t0, 8
    addi    t1, t1, 1
    j       5b
6:  sd      zero, 0(s1)            /* argv[argc] */
    sd      zero, 8(s1)            /* envp[0] */
    li      t0, USER_STACK_TOP - 4096
    csrw    sscratch, t0
    csrw    sepc, s3
    li      a0, 0
    j       trap_return

syscall_exec_format:
    li      a0, -8                 /* -ENOEXEC */
    j       trap_return
syscall_arg_too_big:
    li      a0, -7                 /* -E2BIG */
    j       trap_return

syscall_wait4:
    la      t0, child_process
    ld      t0, 0(t0)
    bnez    t0, syscall_try_again
    beqz    a1, 1f
    la      t0, child_exit_status
    ld      t0, 0(t0)
    slli    t0, t0, 8
    sw      t0, 0(a1)
1:  li      a0, 1
    j       trap_return

syscall_try_again:
    li      a0, -11                /* -EAGAIN */
    j       trap_return

syscall_no_entry:
    li      a0, -2                 /* -ENOENT */
    j       trap_return
syscall_no_space:
    li      a0, -28                /* -ENOSPC */
    j       trap_return
syscall_invalid:
    li      a0, -22                /* -EINVAL */
    j       trap_return
syscall_name_too_long:
    li      a0, -36                /* -ENAMETOOLONG */
    j       trap_return

syscall_exit:
    la      t0, child_process
    ld      t0, 0(t0)
    bnez    t0, restore_parent
    la      t0, shell_process_active
    ld      t1, 0(t0)
    bnez    t1, restore_shell
    la      t0, external_elf
    ld      t0, 0(t0)
    beqz    t0, syscall_exit_finish
    call    validate_hex0_output
    bnez    a0, trap_failure
    la      t0, stage0_success
    li      t1, EXPECTED_LENGTH
    ld      t1, 0(t1)
    beqz    t1, 1f
    la      t0, stage0_selfhost_success
1:
    call    kernel_puts
    li      a0, 0
syscall_exit_finish:
    li      t0, TEST_FINISHER
    beqz    a0, 1f
    slli    a0, a0, 16
    li      t1, 0x3333
    or      a0, a0, t1
    sw      a0, 0(t0)
    j       trap_halt

restore_shell:
    sd      zero, 0(t0)
    mv      t2, a0
    la      t0, shell_resume_sp
    ld      sp, 0(t0)
    la      t0, shell_resume_ra
    ld      t0, 0(t0)
    mv      a0, t2
    jr      t0
1:  li      t1, 0x5555
    sw      t1, 0(t0)
    j       trap_halt

restore_parent:
    /* Restore shared process state before replacing the active trap frame. */
    la      t0, child_exit_status
    sd      a0, 0(t0)
    li      t0, PARENT_PROCESS
    li      t1, USER_PHYS
    la      t2, parent_process_words
    ld      t2, 0(t2)
    call    copy_words
    li      t0, PARENT_STACK
    li      t1, USER_STACK_PHYS
    li      t2, 0x40000
    call    copy_words
    li      t0, PARENT_FDS
    li      t1, FD_TABLE
    li      t2, 768
    call    copy_words
    la      t0, parent_brk
    ld      t1, 0(t0)
    la      t0, process_brk
    sd      t1, 0(t0)
    la      t0, parent_next_fd
    ld      t1, 0(t0)
    la      t0, next_fd
    sd      t1, 0(t0)
    la      t0, parent_sepc
    ld      t0, 0(t0)
    csrw    sepc, t0
    la      t0, parent_user_sp
    ld      t0, 0(t0)
    csrw    sscratch, t0
    li      t0, PARENT_FRAME
    mv      t1, sp
    li      t2, 32
1:  ld      t3, 0(t0)
    sd      t3, 0(t1)
    addi    t0, t0, 8
    addi    t1, t1, 8
    addi    t2, t2, -1
    bnez    t2, 1b
    la      t0, child_process
    sd      zero, 0(t0)
    li      a0, 1                  /* parent clone return */
    j       trap_return

trap_failure:
    li      t0, TEST_FINISHER
    li      t1, 0x13333
    sw      t1, 0(t0)
trap_halt:
    wfi
    j       trap_halt

trap_return:
    ld      ra, 0(sp)
    ld      gp, 8(sp)
    ld      tp, 16(sp)
    ld      t0, 24(sp)
    ld      t1, 32(sp)
    ld      t2, 40(sp)
    ld      s0, 48(sp)
    ld      s1, 56(sp)
    ld      a1, 72(sp)
    ld      a2, 80(sp)
    ld      a3, 88(sp)
    ld      a4, 96(sp)
    ld      a5, 104(sp)
    ld      a6, 112(sp)
    ld      a7, 120(sp)
    ld      s2, 128(sp)
    ld      s3, 136(sp)
    ld      s4, 144(sp)
    ld      s5, 152(sp)
    ld      s6, 160(sp)
    ld      s7, 168(sp)
    ld      s8, 176(sp)
    ld      s9, 184(sp)
    ld      s10, 192(sp)
    ld      s11, 200(sp)
    ld      t3, 208(sp)
    ld      t4, 216(sp)
    ld      t5, 224(sp)
    ld      t6, 232(sp)
    addi    sp, sp, 256
    csrrw   sp, sscratch, sp
    sret

/* Optional virtio-mmio block device, split queue. */
virtio_init_optional:
    li      t0, VIRTIO_FIRST
    li      t3, VIRTIO_END
1:  bgeu    t0, t3, 9f
    lw      t1, 0(t0)
    li      t2, 0x74726976
    bne     t1, t2, 8f
    lw      t1, 8(t0)
    li      t2, 2
    beq     t1, t2, 2f
8:  li      t4, 0x1000
    add     t0, t0, t4
    j       1b
2:  la      t1, virtio_base
    sd      t0, 0(t1)
    sw      zero, 0x70(t0)
    li      t1, 3
    sw      t1, 0x70(t0)            /* ACKNOWLEDGE | DRIVER */
    lw      t1, 4(t0)
    li      t2, 1
    beq     t1, t2, virtio_init_legacy
    li      t2, 2
    bne     t1, t2, 9f

    li      t1, 1
    sw      t1, 0x14(t0)
    lw      t2, 0x10(t0)
    andi    t2, t2, 1               /* VIRTIO_F_VERSION_1 */
    beqz    t2, 9f
    sw      t1, 0x24(t0)
    sw      t2, 0x20(t0)
    li      t1, 11
    sw      t1, 0x70(t0)            /* + FEATURES_OK */
    lw      t2, 0x70(t0)
    andi    t2, t2, 8
    beqz    t2, 9f
    sw      zero, 0x30(t0)
    lw      t2, 0x34(t0)
    beqz    t2, 9f
    li      t1, 8
    bgeu    t1, t2, 3f
    mv      t2, t1
3:  sw      t2, 0x38(t0)
    li      t1, VIRTQ_DESC
    sw      t1, 0x80(t0)
    sw      zero, 0x84(t0)
    li      t1, VIRTQ_AVAIL
    sw      t1, 0x90(t0)
    sw      zero, 0x94(t0)
    li      t1, VIRTQ_USED
    sw      t1, 0xa0(t0)
    sw      zero, 0xa4(t0)
    li      t1, 1
    sw      t1, 0x44(t0)
    li      t1, 15
    sw      t1, 0x70(t0)            /* + DRIVER_OK */
    li      t0, VIRTQ_DESC
    la      t1, virtq_desc
    sd      t0, 0(t1)
    li      t0, VIRTQ_AVAIL
    la      t1, virtq_avail
    sd      t0, 0(t1)
    li      t0, VIRTQ_USED
    la      t1, virtq_used
    sd      t0, 0(t1)
    li      a0, 1
    ret

virtio_init_legacy:
    sw      zero, 0x24(t0)
    sw      zero, 0x20(t0)
    li      t1, 4096
    sw      t1, 0x28(t0)
    sw      zero, 0x30(t0)
    lw      t2, 0x34(t0)
    beqz    t2, 9f
    li      t1, 8
    bgeu    t1, t2, 4f
    mv      t2, t1
4:  sw      t2, 0x38(t0)
    li      t1, 4096
    sw      t1, 0x3c(t0)
    li      t1, VIRTQ_DESC
    srli    t1, t1, 12
    sw      t1, 0x40(t0)
    li      t1, 7
    sw      t1, 0x70(t0)            /* + DRIVER_OK */
    li      t0, VIRTQ_DESC
    la      t1, virtq_desc
    sd      t0, 0(t1)
    li      t0, VIRTQ_DESC + 128
    la      t1, virtq_avail
    sd      t0, 0(t1)
    li      t0, VIRTQ_DESC + 4096
    la      t1, virtq_used
    sd      t0, 0(t1)
    li      a0, 1
    ret
9:  li      a0, 0
    ret

/* a0=sector, a1=buffer. */
read_sector:
    li      a2, 0
    j       virtio_sector
write_sector:
    li      a2, 1
virtio_sector:
    li      t0, VIRTIO_HEADER
    sw      a2, 0(t0)
    sw      zero, 4(t0)
    sd      a0, 8(t0)
    li      t1, VIRTIO_STATUS
    li      t2, 0xff
    sb      t2, 0(t1)

    la      t0, virtq_desc
    ld      t0, 0(t0)
    li      t1, VIRTIO_HEADER
    sd      t1, 0(t0)
    li      t1, 16
    sw      t1, 8(t0)
    li      t1, 1
    sh      t1, 12(t0)              /* NEXT */
    li      t1, 1
    sh      t1, 14(t0)
    sd      a1, 16(t0)
    li      t1, 512
    sw      t1, 24(t0)
    li      t1, 1
    bnez    a2, 5f
    ori     t1, t1, 2               /* device writes on disk read */
5:  sh      t1, 28(t0)
    li      t1, 2
    sh      t1, 30(t0)
    li      t1, VIRTIO_STATUS
    sd      t1, 32(t0)
    li      t1, 1
    sw      t1, 40(t0)
    li      t1, 2
    sh      t1, 44(t0)              /* WRITE */
    sh      zero, 46(t0)

    la      t0, virtq_avail
    ld      t0, 0(t0)
    lhu     t1, 2(t0)
    andi    t2, t1, 7
    slli    t2, t2, 1
    addi    t2, t2, 4
    add     t2, t2, t0
    sh      zero, 0(t2)
    addi    t1, t1, 1
    fence   w, w
    sh      t1, 2(t0)
    fence   rw, rw

    la      t0, virtq_used
    ld      t0, 0(t0)
    lhu     t1, 2(t0)
    la      t2, virtio_base
    ld      t2, 0(t2)
    sw      zero, 0x50(t2)
6:  fence   r, r
    lhu     t2, 2(t0)
    beq     t1, t2, 6b
    li      t0, VIRTIO_STATUS
    lbu     t1, 0(t0)
    bnez    t1, disk_failure
    ret

disk_failure:
    la      t0, disk_failure_message
    call    kernel_puts
    li      a0, 3
    j       syscall_exit_finish

/* Load the test ELF and publish its entry point. */
load_test_elf:
    addi    sp, sp, -16
    sd      ra, 0(sp)
    li      a0, ELF_SOURCE
    call    load_elf
    la      t0, user_entry_address
    sd      a0, 0(t0)
    ld      ra, 0(sp)
    addi    sp, sp, 16
    ret

/* a0=ELF image, returns e_entry after loading every PT_LOAD segment. */
load_elf:
    addi    sp, sp, -64
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    sd      s1, 16(sp)
    sd      s2, 24(sp)
    sd      s3, 32(sp)
    sd      s4, 40(sp)
    sd      s5, 48(sp)
    mv      s0, a0
    li      s5, USER_VIRT
    lhu     s1, 56(s0)             /* e_phnum */
    lhu     s2, 54(s0)             /* e_phentsize */
    ld      s3, 32(s0)             /* e_phoff */
    add     s3, s3, s0
1:  beqz    s1, 6f
    lwu     t0, 0(s3)              /* p_type */
    li      t1, 1                  /* PT_LOAD */
    bne     t0, t1, 5f
    ld      t0, 16(s3)             /* p_vaddr */
    li      t1, USER_VIRT
    bltu    t0, t1, trap_failure
    li      t1, USER_HEAP_TOP
    bgeu    t0, t1, trap_failure
    li      t1, USER_PHYS - USER_VIRT
    add     s4, t0, t1             /* physical destination */
    ld      t0, 8(s3)              /* p_offset */
    add     t0, t0, s0             /* source */
    ld      t1, 32(s3)             /* p_filesz */
    ld      t2, 40(s3)             /* p_memsz */
    bltu    t2, t1, trap_failure
    add     t3, s4, t2
    bltu    t3, s4, trap_failure
    li      t4, 0x82000000
    bgtu    t3, t4, trap_failure
    li      t4, USER_PHYS - USER_VIRT
    sub     t5, t3, t4             /* virtual segment end */
    bleu    t5, s5, 7f
    mv      s5, t5
7:
    sub     t2, t2, t1             /* BSS bytes */
2:  beqz    t1, 3f
    lbu     t3, 0(t0)
    sb      t3, 0(s4)
    addi    t0, t0, 1
    addi    s4, s4, 1
    addi    t1, t1, -1
    j       2b
3:  beqz    t2, 5f
4:  sb      zero, 0(s4)
    addi    s4, s4, 1
    addi    t2, t2, -1
    bnez    t2, 4b
5:  add     s3, s3, s2
    addi    s1, s1, -1
    j       1b
6:  li      t0, 4095
    add     s5, s5, t0
    li      t0, -4096
    and     s5, s5, t0
    la      t0, process_brk
    sd      s5, 0(t0)
    ld      a0, 24(s0)             /* e_entry */
    ld      ra, 0(sp)
    ld      s0, 8(sp)
    ld      s1, 16(sp)
    ld      s2, 24(sp)
    ld      s3, 32(sp)
    ld      s4, 40(sp)
    ld      s5, 48(sp)
    addi    sp, sp, 64
    ret

/* t0=destination, t1=NUL-terminated source */
copy_string:
1:  lbu     t2, 0(t1)
    sb      t2, 0(t0)
    addi    t0, t0, 1
    addi    t1, t1, 1
    bnez    t2, 1b
    ret

kernel_putc:
    li      t0, UART0
1:  lbu     t1, 5(t0)
    andi    t1, t1, 0x20
    beqz    t1, 1b
    sb      a0, 0(t0)
    ret

kernel_puthex64:
    addi    sp, sp, -32
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    sd      s1, 16(sp)
    mv      s0, a0
    li      s1, 60
1:  srl     t0, s0, s1
    andi    t0, t0, 15
    li      t1, 10
    bltu    t0, t1, 2f
    addi    a0, t0, 55
    j       3f
2:  addi    a0, t0, 48
3:  call    kernel_putc
    addi    s1, s1, -4
    bgez    s1, 1b
    ld      ra, 0(sp)
    ld      s0, 8(sp)
    ld      s1, 16(sp)
    addi    sp, sp, 32
    ret

kernel_puts:
1:  lbu     t1, 0(t0)
    beqz    t1, 3f
    li      t2, UART0
2:  lbu     t3, 5(t2)
    andi    t3, t3, 0x20
    beqz    t3, 2b
    sb      t1, 0(t2)
    addi    t0, t0, 1
    j       1b
3:  ret

/* t0=source, t1=destination, t2=64-bit word count */
copy_words:
1:  beqz    t2, 2f
    ld      t3, 0(t0)
    sd      t3, 0(t1)
    addi    t0, t0, 8
    addi    t1, t1, 8
    addi    t2, t2, -1
    j       1b
2:  ret

/* a0=input path, a1=destination; returns a canonical absolute path. */
normalize_path:
    mv      t1, a0
    mv      t0, a1
    mv      t6, a1
    lbu     t2, 0(t1)
    li      t3, '/'
    beq     t2, t3, 2f
    li      t4, CWD_BUFFER
1:  lbu     t2, 0(t4)
    beqz    t2, 3f
    sb      t2, 0(t0)
    addi    t0, t0, 1
    addi    t4, t4, 1
    j       1b
2:  sb      t3, 0(t0)
    addi    t0, t0, 1
4:  addi    t1, t1, 1
    lbu     t2, 0(t1)
    beq     t2, t3, 4b
3:
    /* Skip separators, then classify dot components. */
5:  lbu     t2, 0(t1)
    beqz    t2, 12f
    beq     t2, t3, 11f
    li      t4, '.'
    bne     t2, t4, 8f
    lbu     t2, 1(t1)
    beqz    t2, 6f
    beq     t2, t3, 6f
    bne     t2, t4, 8f
    lbu     t2, 2(t1)
    beqz    t2, 7f
    bne     t2, t3, 8f
7:  addi    t1, t1, 2              /* parent component */
9:  addi    t4, t6, 1
    bleu    t0, t4, 5b
    addi    t0, t0, -1
    lbu     t2, 0(t0)
    li      t4, '/'
    bne     t2, t4, 9b
    j       5b
6:  addi    t1, t1, 1              /* current component */
    j       5b

8:  addi    t4, t6, 1
    bleu    t0, t4, 10f
    li      t2, PATH_BUFFER + 4095
    bgeu    t0, t2, 13f
    li      t2, '/'
    sb      t2, 0(t0)
    addi    t0, t0, 1
10: lbu     t2, 0(t1)
    beqz    t2, 5b
    li      t3, '/'
    beq     t2, t3, 5b
    li      t4, PATH_BUFFER + 4095
    bgeu    t0, t4, 13f
    sb      t2, 0(t0)
    addi    t0, t0, 1
    addi    t1, t1, 1
    j       10b
11: addi    t1, t1, 1
    j       5b
12: sb      zero, 0(t0)
    mv      a0, t6
    ret
13: li      a0, 0
    ret

/* a0=path, returns the newest matching file record or zero. */
find_file:
    addi    sp, sp, -32
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    sd      s1, 16(sp)
    sd      s2, 24(sp)
    mv      s0, a0
    la      t0, file_count
    ld      s1, 0(t0)
1:  beqz    s1, 3f
    addi    s1, s1, -1
    slli    t0, s1, 5
    li      s2, FILE_TABLE
    add     s2, s2, t0
    mv      a0, s0
    ld      a1, 0(s2)
    beqz    a1, 1b
    call    strings_equal
    beqz    a0, 1b
    mv      a0, s2
    j       4f
3:  li      a0, 0
4:  ld      ra, 0(sp)
    ld      s0, 8(sp)
    ld      s1, 16(sp)
    ld      s2, 24(sp)
    addi    sp, sp, 32
    ret

/* a0/a1=NUL-terminated strings, returns one when equal. */
strings_equal:
1:  lbu     t0, 0(a0)
    lbu     t1, 0(a1)
    bne     t0, t1, 2f
    beqz    t0, 3f
    addi    a0, a0, 1
    addi    a1, a1, 1
    j       1b
2:  li      a0, 0
    ret
3:  li      a0, 1
    ret

/* a0=path, returns a new empty file record or zero. */
create_file:
    addi    sp, sp, -32
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    sd      s1, 16(sp)
    sd      s2, 24(sp)
    mv      s0, a0
    la      t0, file_count
    ld      s1, 0(t0)
    li      t1, 256
    bgeu    s1, t1, 3f
    slli    t1, s1, 5
    li      s2, FILE_TABLE
    add     s2, s2, t1

    la      t1, next_file_name
    ld      t0, 0(t1)
    beqz    t0, 1f
    j       2f
1:  li      t0, 0x83100000
2:  sd      t0, 0(s2)
4:  lbu     t2, 0(s0)
    sb      t2, 0(t0)
    addi    s0, s0, 1
    addi    t0, t0, 1
    bnez    t2, 4b
    sd      t0, 0(t1)

    la      t0, next_file_data
    ld      t1, 0(t0)
    li      t2, PARENT_PROCESS
    bgeu    t1, t2, 3f
    sd      t1, 8(s2)
    sd      zero, 16(s2)
    sub     t2, t2, t1
    sd      t2, 24(s2)
    addi    s1, s1, 1
    la      t0, file_count
    sd      s1, 0(t0)
    mv      a0, s2
    j       5f
3:  li      a0, 0
5:  ld      ra, 0(sp)
    ld      s0, 8(sp)
    ld      s1, 16(sp)
    ld      s2, 24(sp)
    addi    sp, sp, 32
    ret

/* Advance the file-data allocator past a0's payload. */
finalize_file:
    ld      t0, 8(a0)
    ld      t1, 16(a0)
    add     t0, t0, t1
    addi    t0, t0, 15
    li      t1, -16
    and     t0, t0, t1
    la      t1, next_file_data
    ld      t2, 0(t1)
    bleu    t0, t2, 1f
    sd      t0, 0(t1)
1:  ret

/* Stream one command byte from the disk script; -1 marks exact-length EOF. */
shell_getc:
    addi    sp, sp, -16
    sd      ra, 0(sp)
    la      t0, shell_remaining
    ld      t1, 0(t0)
    beqz    t1, 3f
    la      t2, shell_sector_pos
    ld      t3, 0(t2)
    li      t4, 512
    bltu    t3, t4, 1f
    la      t3, shell_lba
    ld      a0, 0(t3)
    li      a1, SECTOR_BUFFER
    call    read_sector
    la      t3, shell_lba
    ld      t4, 0(t3)
    addi    t4, t4, 1
    sd      t4, 0(t3)
    la      t2, shell_sector_pos
    li      t3, 0
1:  li      t4, SECTOR_BUFFER
    add     t4, t4, t3
    lbu     a0, 0(t4)
    addi    t3, t3, 1
    sd      t3, 0(t2)
    la      t0, shell_remaining
    ld      t1, 0(t0)
    addi    t1, t1, -1
    sd      t1, 0(t0)
    j       4f
3:  li      a0, -1
4:  ld      ra, 0(sp)
    addi    sp, sp, 16
    ret

/* Read one command line into the fixed 4 KiB buffer. */
shell_getline:
    addi    sp, sp, -32
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    sd      s1, 16(sp)
    li      s0, SHELL_LINE_BUFFER
    mv      s1, s0
1:  call    shell_getc
    bltz    a0, 3f
    li      t0, 10
    beq     a0, t0, 2f
    li      t0, SHELL_LINE_BUFFER + 4095
    bgeu    s0, t0, 4f
    sb      a0, 0(s0)
    addi    s0, s0, 1
    j       1b
2:  sb      zero, 0(s0)
    mv      a0, s1
    j       5f
3:  beq     s0, s1, 5f
    sb      zero, 0(s0)
    mv      a0, s1
    j       5f
4:  li      a0, -2
5:  ld      ra, 0(sp)
    ld      s0, 8(sp)
    ld      s1, 16(sp)
    addi    sp, sp, 32
    ret

/* a0=cursor; returns token in a0 and following cursor in a1. */
next_token:
1:  lbu     t0, 0(a0)
    li      t1, ' '
    beq     t0, t1, 2f
    li      t1, 9
    bne     t0, t1, 3f
2:  addi    a0, a0, 1
    j       1b
3:  mv      a1, a0
4:  lbu     t0, 0(a1)
    beqz    t0, 6f
    li      t1, ' '
    beq     t0, t1, 5f
    li      t1, 9
    beq     t0, t1, 5f
    addi    a1, a1, 1
    j       4b
5:  sb      zero, 0(a1)
    addi    a1, a1, 1
6:  ret

/* a0=unsigned decimal string, returns value or -1 for malformed input. */
parse_decimal:
    mv      t0, a0
    li      a0, 0
    li      t3, 0
1:  lbu     t1, 0(t0)
    beqz    t1, 3f
    li      t2, '0'
    bltu    t1, t2, 4f
    li      t2, '9' + 1
    bgeu    t1, t2, 4f
    addi    t1, t1, -48
    slli    t2, a0, 3
    slli    a0, a0, 1
    add     a0, a0, t2
    add     a0, a0, t1
    addi    t0, t0, 1
    li      t3, 1
    j       1b
3:  beqz    t3, 4f
    ret
4:  li      a0, -1
    ret

/* src N PATH */
shell_src:
    addi    sp, sp, -64
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    sd      s1, 16(sp)
    sd      s2, 24(sp)
    sd      s3, 32(sp)
    sd      s4, 40(sp)
    call    next_token
    mv      s0, a1
    call    parse_decimal
    bltz    a0, 4f
    mv      s1, a0
    mv      a0, s0
    call    next_token
    lbu     t0, 0(a0)
    beqz    t0, 4f
    li      a1, PATH_BUFFER
    call    normalize_path
    beqz    a0, 4f
    call    create_file
    beqz    a0, 4f
    mv      s2, a0
    ld      t0, 24(s2)
    bgtu    s1, t0, 4f
    ld      s3, 8(s2)
    mv      s4, s1
1:  beqz    s4, 2f
    call    shell_getc
    bltz    a0, 4f
    sb      a0, 0(s3)
    addi    s3, s3, 1
    addi    s4, s4, -1
    j       1b
2:  sd      s1, 16(s2)
    mv      a0, s2
    call    finalize_file
    li      a0, 0
    j       5f
4:  li      a0, -1
5:  ld      ra, 0(sp)
    ld      s0, 8(sp)
    ld      s1, 16(sp)
    ld      s2, 24(sp)
    ld      s3, 32(sp)
    ld      s4, 40(sp)
    addi    sp, sp, 64
    ret

/* a0=source, a1=source bytes, a2=output; returns output bytes. */
hex0_compile_memory:
    mv      t0, a0
    add     t1, a0, a1
    mv      t2, a2
    li      t3, 0
    li      t4, 0
    li      t5, 0
1:  bgeu    t0, t1, 8f
    lbu     a3, 0(t0)
    addi    t0, t0, 1
    beqz    t5, 3f
    li      a4, 10
    bne     a3, a4, 1b
    li      t5, 0
    j       1b
3:  li      a4, '#'
    beq     a3, a4, 7f
    li      a4, ';'
    beq     a3, a4, 7f
    li      a4, '0'
    bltu    a3, a4, 1b
    li      a5, '9' + 1
    bltu    a3, a5, 4f
    li      a4, 'A'
    bltu    a3, a4, 1b
    li      a5, 'F' + 1
    bltu    a3, a5, 5f
    li      a4, 'a'
    bltu    a3, a4, 1b
    li      a5, 'f' + 1
    bgeu    a3, a5, 1b
    addi    a3, a3, -87
    j       6f
4:  addi    a3, a3, -48
    j       6f
5:  addi    a3, a3, -55
6:  bnez    t3, 9f
    slli    t4, a3, 4
    li      t3, 1
    j       1b
9:  or      t4, t4, a3
    sb      t4, 0(t2)
    addi    t2, t2, 1
    li      t3, 0
    j       1b
7:  li      t5, 1
    j       1b
8:  sub     a0, t2, a2
    ret

/* hex0 INPUT OUTPUT */
shell_hex0:
    addi    sp, sp, -48
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    sd      s1, 16(sp)
    sd      s2, 24(sp)
    call    next_token
    mv      s0, a1
    lbu     t0, 0(a0)
    beqz    t0, 4f
    li      a1, PATH_BUFFER
    call    normalize_path
    beqz    a0, 4f
    call    find_file
    beqz    a0, 4f
    mv      s1, a0
    mv      a0, s0
    call    next_token
    lbu     t0, 0(a0)
    beqz    t0, 4f
    li      a1, PATH_BUFFER
    call    normalize_path
    beqz    a0, 4f
    call    create_file
    beqz    a0, 4f
    mv      s2, a0
    ld      a0, 8(s1)
    ld      a1, 16(s1)
    ld      a2, 8(s2)
    call    hex0_compile_memory
    ld      t0, 24(s2)
    bgtu    a0, t0, 4f
    sd      a0, 16(s2)
    mv      a0, s2
    call    finalize_file
    li      a0, 0
    j       5f
4:  li      a0, -1
5:  ld      ra, 0(sp)
    ld      s0, 8(sp)
    ld      s1, 16(sp)
    ld      s2, 24(sp)
    addi    sp, sp, 48
    ret

/* Write the newest /dev/hda memory file over the block device. */
flush_disk:
    addi    sp, sp, -64
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    sd      s1, 16(sp)
    sd      s2, 24(sp)
    sd      s3, 32(sp)
    la      a0, dev_hda_name
    call    find_file
    beqz    a0, 5f
    ld      s0, 8(a0)
    ld      s1, 16(a0)
    mv      a0, s1
    call    kernel_puthex64
    li      a0, 10
    call    kernel_putc
    li      s2, 0
1:  beqz    s1, 4f
    li      t0, SECTOR_BUFFER
    li      t1, 64
2:  sd      zero, 0(t0)
    addi    t0, t0, 8
    addi    t1, t1, -1
    bnez    t1, 2b
    li      s3, 512
    bgeu    s1, s3, 3f
    mv      s3, s1
3:  mv      t0, s0
    li      t1, SECTOR_BUFFER
    mv      t2, s3
6:  beqz    t2, 7f
    lbu     t3, 0(t0)
    sb      t3, 0(t1)
    addi    t0, t0, 1
    addi    t1, t1, 1
    addi    t2, t2, -1
    j       6b
7:  mv      a0, s2
    li      a1, SECTOR_BUFFER
    call    write_sector
    add     s0, s0, s3
    sub     s1, s1, s3
    addi    s2, s2, 1
    j       1b
4:  li      a0, 0
    j       8f
5:  li      a0, -1
8:  ld      ra, 0(sp)
    ld      s0, 8(sp)
    ld      s1, 16(sp)
    ld      s2, 24(sp)
    ld      s3, 32(sp)
    addi    sp, sp, 64
    ret

shell_maybe_flush:
    addi    sp, sp, -16
    sd      ra, 0(sp)
    la      t0, shell_flush_pending
    ld      t1, 0(t0)
    beqz    t1, 1f
    sd      zero, 0(t0)
    call    flush_disk
    j       2f
1:  li      a0, 0
2:  ld      ra, 0(sp)
    addi    sp, sp, 16
    ret

/* a0=file record, a1=argv[0], a2=optional argv[1]. Does not return normally. */
launch_shell_process:
    la      t0, shell_resume_sp
    sd      sp, 0(t0)
    la      t0, shell_resume_ra
    sd      ra, 0(t0)
    la      t0, shell_command_ptr
    sd      a1, 0(t0)
    la      t0, shell_argument_ptr
    sd      a2, 0(t0)
    ld      a0, 8(a0)
    call    load_elf
    mv      s0, a0

    li      t0, 0x87fff000
    li      t1, 1
    la      t2, shell_argument_ptr
    ld      t2, 0(t2)
    beqz    t2, 1f
    lbu     t3, 0(t2)
    beqz    t3, 1f
    li      t1, 2
1:  sd      t1, 0(t0)
    li      t1, 0x07fff400
    sd      t1, 8(t0)
    li      t3, 0x87fff400
    la      t1, shell_command_ptr
    ld      t1, 0(t1)
    mv      t0, t3
    call    copy_string
    mv      t3, t0
    la      t2, shell_argument_ptr
    ld      t2, 0(t2)
    beqz    t2, 2f
    lbu     t4, 0(t2)
    beqz    t4, 2f
    li      t0, 0x87fff000
    li      t1, 0x80000000
    sub     t1, t3, t1
    sd      t1, 16(t0)
    mv      t0, t3
    mv      t1, t2
    call    copy_string
    li      t0, 0x87fff000
    sd      zero, 24(t0)
    sd      zero, 32(t0)
    j       3f
2:  li      t0, 0x87fff000
    sd      zero, 16(t0)
    sd      zero, 24(t0)
3:
    la      t0, shell_process_active
    li      t1, 1
    sd      t1, 0(t0)
    csrw    sepc, s0
    csrr    t0, sstatus
    li      t1, ~(1 << 8)
    and     t0, t0, t1
    li      t1, (1 << 5) | (1 << 18)
    or      t0, t0, t1
    csrw    sstatus, t0
    li      t0, SHELL_TRAP_STACK
    csrw    sscratch, t0
    li      sp, USER_STACK_TOP - 4096
    sret

internal_shell:
    addi    sp, sp, -64
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    sd      s1, 16(sp)
    sd      s2, 24(sp)
1:  call    shell_getline
    li      t0, -1
    beq     a0, t0, shell_finish
    bltz    a0, shell_error
    call    next_token
    mv      s0, a0
    mv      s1, a1
    lbu     t0, 0(s0)
    beqz    t0, 1b

    mv      a0, s0
    la      a1, command_src
    call    strings_equal
    bnez    a0, shell_handle_src
    mv      a0, s0
    la      a1, command_hex0
    call    strings_equal
    bnez    a0, shell_handle_hex0
    mv      a0, s0
    la      a1, command_flush
    call    strings_equal
    bnez    a0, shell_handle_flush
    mv      a0, s0
    la      a1, command_halt
    call    strings_equal
    bnez    a0, shell_finish

    /* An external command is completely buffered before a delayed flush. */
    call    shell_maybe_flush
    bnez    a0, shell_error
    mv      a0, s0
    li      a1, PATH_BUFFER
    call    normalize_path
    beqz    a0, shell_error
    call    find_file
    beqz    a0, shell_error
    mv      s2, a0
    mv      a0, s1
    call    next_token
    mv      a2, a0
    mv      a1, s0
    mv      a0, s2
    call    launch_shell_process
    j       1b                       /* resume target after process exit */

shell_handle_src:
    mv      a0, s1
    call    shell_src
    bnez    a0, shell_error
    j       1b
shell_handle_hex0:
    mv      a0, s1
    call    shell_hex0
    bnez    a0, shell_error
    j       1b
shell_handle_flush:
    la      t0, shell_flush_pending
    li      t1, 1
    sd      t1, 0(t0)
    j       1b

shell_finish:
    call    flush_disk
    bnez    a0, shell_error
    la      t0, shell_success_message
    call    kernel_puts
    li      a0, 0
    j       shell_return
shell_error:
    la      t0, shell_failure_message
    call    kernel_puts
    li      a0, 1
shell_return:
    ld      ra, 0(sp)
    ld      s0, 8(sp)
    ld      s1, 16(sp)
    ld      s2, 24(sp)
    addi    sp, sp, 64
    ret

validate_hex0_output:
    addi    sp, sp, -16
    sd      ra, 0(sp)
    sd      s0, 8(sp)
    la      a0, output_name
    call    find_file
    beqz    a0, validate_output_failure
    mv      s0, a0
    ld      t0, 16(s0)
    li      t1, EXPECTED_LENGTH
    ld      t1, 0(t1)
    beqz    t1, validate_parser_fixture
    bne     t0, t1, validate_output_failure
    ld      t0, 8(s0)
    li      t2, EXPECTED_SOURCE
1:  beqz    t1, validate_output_success
    lbu     t3, 0(t0)
    lbu     t4, 0(t2)
    bne     t3, t4, validate_output_failure
    addi    t0, t0, 1
    addi    t2, t2, 1
    addi    t1, t1, -1
    j       1b

validate_parser_fixture:
    li      t1, 5
    bne     t0, t1, validate_output_failure
    ld      t0, 8(s0)
    ld      t1, 0(t0)
    li      t2, 0x22ffaa1100
    bne     t1, t2, validate_output_failure
validate_output_success:
    li      a0, 0
    j       validate_output_return
validate_output_failure:
    li      a0, 1
validate_output_return:
    ld      ra, 0(sp)
    ld      s0, 8(sp)
    addi    sp, sp, 16
    ret

/* Position-independent user fixture copied to virtual 0x600000. */
user_start:
    li      gp, 3
    li      tp, 4
    li      t0, 5
    li      t1, 6
    li      t2, 7
    li      s0, 8
    li      s1, 9
    li      s2, 18
    li      s3, 19
    li      s4, 20
    li      s5, 21
    li      s6, 22
    li      s7, 23
    li      s8, 24
    li      s9, 25
    li      s10, 26
    li      s11, 27
    li      t3, 28
    li      t4, 29
    li      t5, 30
    li      t6, 31
    li      a0, 1
    la      a1, user_message
    la      a2, user_message_end
    sub     a2, a2, a1
    li      a3, 13
    li      a4, 14
    li      a5, 15
    li      a6, 16
    li      a7, 64
    ecall

    li      a0, 3
    bne     gp, a0, user_register_failure
    li      a0, 4
    bne     tp, a0, user_register_failure
    li      a0, 5
    bne     t0, a0, user_register_failure
    li      a0, 6
    bne     t1, a0, user_register_failure
    li      a0, 7
    bne     t2, a0, user_register_failure
    li      a0, 8
    bne     s0, a0, user_register_failure
    li      a0, 9
    bne     s1, a0, user_register_failure
    li      a0, 18
    bne     s2, a0, user_register_failure
    li      a0, 19
    bne     s3, a0, user_register_failure
    li      a0, 20
    bne     s4, a0, user_register_failure
    li      a0, 21
    bne     s5, a0, user_register_failure
    li      a0, 22
    bne     s6, a0, user_register_failure
    li      a0, 23
    bne     s7, a0, user_register_failure
    li      a0, 24
    bne     s8, a0, user_register_failure
    li      a0, 25
    bne     s9, a0, user_register_failure
    li      a0, 26
    bne     s10, a0, user_register_failure
    li      a0, 27
    bne     s11, a0, user_register_failure
    li      a0, 28
    bne     t3, a0, user_register_failure
    li      a0, 29
    bne     t4, a0, user_register_failure
    li      a0, 30
    bne     t5, a0, user_register_failure
    li      a0, 31
    bne     t6, a0, user_register_failure
    la      a0, user_message
    bne     a1, a0, user_register_failure
    la      a0, user_message_end
    la      a1, user_message
    sub     a0, a0, a1
    bne     a2, a0, user_register_failure
    li      a0, 13
    bne     a3, a0, user_register_failure
    li      a0, 14
    bne     a4, a0, user_register_failure
    li      a0, 15
    bne     a5, a0, user_register_failure
    li      a0, 16
    bne     a6, a0, user_register_failure
    li      a0, 64
    bne     a7, a0, user_register_failure

    li      a0, 0
    li      a7, 214
    ecall
    li      a1, 0x00800000
    bne     a0, a1, user_register_failure
    li      a0, 0x00900000
    li      a7, 214
    ecall
    li      a1, 0x00900000
    bne     a0, a1, user_register_failure
    li      a0, 99
    li      a1, 0
    li      a2, 0
    li      a7, 62
    ecall
    li      a1, -9
    bne     a0, a1, user_register_failure

    li      a0, -100
    la      a1, user_input_name
    li      a2, 0
    li      a7, 56
    ecall
    li      a1, 4
    bne     a0, a1, user_register_failure
    li      a1, 0
    li      a2, 0
    li      a7, 62
    ecall
    bnez    a0, user_register_failure
    li      a0, 4
    li      a7, 57
    ecall
    bnez    a0, user_register_failure

    la      a0, user_chdir_name
    li      a7, 49
    ecall
    bnez    a0, user_register_failure
    li      a0, -100
    la      a1, user_create_name
    li      a2, 577
    li      a3, 384
    li      a7, 56
    ecall
    li      a1, 5
    bne     a0, a1, user_register_failure
    li      a0, 5
    li      a7, 57
    ecall
    bnez    a0, user_register_failure
    li      a0, -100
    la      a1, user_relative_name
    li      a2, 0
    li      a3, 0
    li      a7, 48
    ecall
    bnez    a0, user_register_failure
    li      a0, -100
    la      a1, user_relative_name
    li      a2, 384
    li      a3, 0
    li      a7, 53
    ecall
    bnez    a0, user_register_failure
    li      a0, -100
    la      a1, user_relative_name
    li      a2, 0
    li      a7, 35
    ecall
    bnez    a0, user_register_failure
    li      a0, -100
    la      a1, user_relative_name
    li      a2, 0
    li      a3, 0
    li      a7, 48
    ecall
    li      a1, -2
    bne     a0, a1, user_register_failure

    li      a0, 17
    li      a1, 0
    li      a2, 0
    li      a3, 0
    li      a4, 0
    li      a7, 220
    ecall
    beqz    a0, user_clone_child
    li      a1, 1
    bne     a0, a1, user_register_failure
    li      a0, 1
    li      a1, 0
    li      a2, 0
    li      a3, 0
    li      a7, 260
    ecall
    li      a1, 1
    bne     a0, a1, user_register_failure

    li      a0, 1
    la      a1, user_success_message
    la      a2, user_success_message_end
    sub     a2, a2, a1
    li      a7, 64
    ecall

    li      a0, 0
    li      a7, 93
    ecall
user_clone_child:
    addi    sp, sp, -16
    la      a0, user_exec_name
    sd      a0, 0(sp)
    sd      zero, 8(sp)
    mv      a1, sp
    li      a2, 0
    li      a7, 221
    ecall
    j       user_register_failure
user_register_failure:
    li      a0, 1
    li      a7, 93
    ecall
user_message:
    .ascii  "builder-hex0-riscv64 register context ecall\n"
user_message_end:
user_success_message:
    .ascii  "builder-hex0-riscv64 stage2 user ecall passed\n"
user_success_message_end:
user_input_name:
    .asciz  "/input"
user_exec_name:
    .asciz  "/exec-target"
user_chdir_name:
    .asciz  "/tmp/a/../work"
user_create_name:
    .asciz  "../work/./file"
user_relative_name:
    .asciz  "./file"
user_end:

    .section .rodata
process_name:    .asciz "hex0-seed"
input_name:      .asciz "/input"
output_name:     .asciz "/output"
exec_target_name: .asciz "/exec-target"
dev_hda_name:     .asciz "/dev/hda"
command_src:      .asciz "src"
command_hex0:     .asciz "hex0"
command_flush:    .asciz "f"
command_halt:     .asciz "halt"
disk_failure_message: .asciz "builder-hex0-riscv64 disk request failed\n"
shell_failure_message: .asciz "builder-hex0-riscv64 shell failed\n"
shell_success_message: .asciz "builder-hex0-riscv64 shell and flush passed\n"
stage0_success:  .asciz "builder-hex0-riscv64 real stage0 hex0-seed passed\n"
stage0_selfhost_success:
    .asciz "builder-hex0-riscv64 stage0 hex0-seed self-build passed\n"

    .balign 8
builtin_exec_elf:
    .byte   0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0
    .byte   0, 0, 0, 0, 0, 0, 0, 0
    .half   2                      /* ET_EXEC */
    .half   243                    /* EM_RISCV */
    .word   1
    .dword  0x00600078             /* e_entry */
    .dword  64                     /* e_phoff */
    .dword  0
    .word   0
    .half   64
    .half   56
    .half   1
    .half   0
    .half   0
    .half   0
    .word   1                      /* PT_LOAD */
    .word   7                      /* PF_R | PF_W | PF_X */
    .dword  0
    .dword  0x00600000
    .dword  0x00600000
    .dword  builtin_exec_elf_end - builtin_exec_elf
    .dword  builtin_exec_elf_end - builtin_exec_elf
    .dword  4096
    .word   0x00000513             /* li a0, 0 */
    .word   0x05d00893             /* li a7, 93 */
    .word   0x00000073             /* ecall */
builtin_exec_elf_end:
    /* Keep the following data section contiguous in the raw image. */
    .balign 8

    .section .data
    .balign 8
user_entry_address: .dword USER_VIRT
external_elf:       .dword 0
next_fd:            .dword 4
input_offset:       .dword 0
input_length:       .dword 0
output_length:      .dword 0
file_count:         .dword 0
next_file_name:     .dword 0
next_file_data:     .dword FILE_DATA
process_brk:        .dword 0x00800000
child_process:      .dword 0
child_exit_status:  .dword 0
parent_sepc:        .dword 0
parent_user_sp:     .dword 0
parent_brk:         .dword 0
parent_next_fd:     .dword 0
parent_process_words: .dword 0
virtio_base:        .dword 0
virtq_desc:         .dword 0
virtq_avail:        .dword 0
virtq_used:         .dword 0
shell_mode:         .dword 0
shell_lba:          .dword 0
shell_remaining:    .dword 0
shell_sector_pos:   .dword 512
shell_flush_pending: .dword 0
shell_process_active: .dword 0
shell_resume_sp:    .dword 0
shell_resume_ra:    .dword 0
shell_command_ptr:  .dword 0
shell_argument_ptr: .dword 0
