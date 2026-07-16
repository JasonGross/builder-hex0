/* SPDX-License-Identifier: MIT
 *
 * RISC-V 64 builder-hex0 stage-2 privilege and paging bring-up.
 * This currently proves the process address-space and ecall boundary.  Disk,
 * filesystem, shell, and ELF loading are added after this gate.
 */

    .option norvc
    .section .text.boot
    .globl _start

    .equ UART0,              0x10000000
    .equ TEST_FINISHER,      0x00100000
    .equ ROOT_PAGE_TABLE,    0x81000000
    .equ LOW_PAGE_TABLE,     0x81001000
    .equ USER_PHYS,          0x80600000
    .equ USER_VIRT,          0x00600000
    .equ USER_STACK_PHYS,    0x87e00000
    .equ USER_STACK_TOP,     0x08000000
    .equ KERNEL_STACK_TOP,   0x87dff000
    .equ ELF_SOURCE,         0x82000000
    .equ INPUT_SOURCE,       0x82200000
    .equ OUTPUT_FILE,        0x82400000

_start:
    li      sp, KERNEL_STACK_TOP
    li      t0, UART0
    li      t1, 3
    sb      t1, 3(t0)              /* 8n1 */

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

    /* VA 0x600000 -> PA 0x80600000, user R/W/X. */
    li      t1, USER_PHYS
    srli    t1, t1, 2
    ori     t1, t1, 0xdf           /* V R W X U A D */
    sd      t1, 24(t0)             /* level-1 index 3 */

    /* VA 0x07e00000 -> PA 0x87e00000, user stack. */
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
    li      sp, USER_STACK_TOP - 4096
    sret

supervisor_trap:
    csrrw   sp, sscratch, sp
    addi    sp, sp, -128
    sd      ra, 0(sp)
    sd      t0, 8(sp)
    sd      t1, 16(sp)
    sd      t2, 24(sp)
    sd      a0, 32(sp)
    sd      a1, 40(sp)
    sd      a2, 48(sp)
    sd      a3, 56(sp)
    sd      a4, 64(sp)
    sd      a5, 72(sp)
    sd      a6, 80(sp)
    sd      a7, 88(sp)

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
    li      t0, 93                 /* Linux riscv64 exit */
    beq     a7, t0, syscall_exit
    li      a0, -38                /* -ENOSYS */
    j       trap_return

syscall_write:
    li      t0, 5
    beq     a0, t0, syscall_write_file
    li      t0, 1
    beq     a0, t0, 1f
    li      t0, 2
    bne     a0, t0, syscall_bad_fd
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
    la      t0, next_fd
    ld      a0, 0(t0)
    addi    t1, a0, 1
    sd      t1, 0(t0)
    j       trap_return

syscall_read:
    li      t0, 4
    bne     a0, t0, syscall_bad_fd
    la      t0, input_offset
    ld      t1, 0(t0)
    la      t2, input_length
    ld      t2, 0(t2)
    bgeu    t1, t2, syscall_read_eof
    sub     t2, t2, t1
    bleu    a2, t2, 1f
    mv      a2, t2
1:  li      t2, INPUT_SOURCE
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
3:  sd      t1, 0(t0)
    j       trap_return
syscall_read_eof:
    li      a0, 0
    j       trap_return

syscall_write_file:
    la      t0, output_length
    ld      t1, 0(t0)
    li      t2, OUTPUT_FILE
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
2:  sd      t1, 0(t0)
    j       trap_return

syscall_exit:
    la      t0, external_elf
    ld      t0, 0(t0)
    beqz    t0, syscall_exit_finish
    call    validate_hex0_output
    bnez    a0, trap_failure
    la      t0, stage0_success
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
1:  li      t1, 0x5555
    sw      t1, 0(t0)
    j       trap_halt

trap_failure:
    li      t0, TEST_FINISHER
    li      t1, 0x13333
    sw      t1, 0(t0)
trap_halt:
    wfi
    j       trap_halt

trap_return:
    ld      ra, 0(sp)
    ld      t0, 8(sp)
    ld      t1, 16(sp)
    ld      t2, 24(sp)
    ld      a1, 40(sp)
    ld      a2, 48(sp)
    ld      a3, 56(sp)
    ld      a4, 64(sp)
    ld      a5, 72(sp)
    ld      a6, 80(sp)
    ld      a7, 88(sp)
    addi    sp, sp, 128
    csrrw   sp, sscratch, sp
    sret

/* Load the first ELF64 PT_LOAD segment from ELF_SOURCE. */
load_test_elf:
    li      t0, ELF_SOURCE
    ld      t1, 32(t0)             /* e_phoff */
    add     t1, t1, t0
    ld      t2, 8(t1)              /* p_offset */
    add     t2, t2, t0
    ld      t3, 16(t1)             /* p_vaddr */
    ld      t4, 32(t1)             /* p_filesz */
    li      t5, USER_PHYS - USER_VIRT
    add     t5, t5, t3
1:  beqz    t4, 2f
    lbu     t6, 0(t2)
    sb      t6, 0(t5)
    addi    t2, t2, 1
    addi    t5, t5, 1
    addi    t4, t4, -1
    j       1b
2:  ld      t1, 24(t0)             /* e_entry */
    la      t2, user_entry_address
    sd      t1, 0(t2)
    ret

/* t0=destination, t1=NUL-terminated source */
copy_string:
1:  lbu     t2, 0(t1)
    sb      t2, 0(t0)
    addi    t0, t0, 1
    addi    t1, t1, 1
    bnez    t2, 1b
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

validate_hex0_output:
    la      t0, output_length
    ld      t0, 0(t0)
    li      t1, 5
    bne     t0, t1, 2f
    li      t0, OUTPUT_FILE
    ld      t1, 0(t0)
    li      t2, 0x22ffaa1100
    bne     t1, t2, 2f
    li      a0, 0
    ret
2:  li      a0, 1
    ret

/* Position-independent user fixture copied to virtual 0x600000. */
user_start:
    li      a0, 1
    la      a1, user_message
    la      a2, user_message_end
    sub     a2, a2, a1
    li      a7, 64
    ecall
    li      a0, 0
    li      a7, 93
    ecall
user_message:
    .ascii  "builder-hex0-riscv64 stage2 user ecall passed\n"
user_message_end:
user_end:

    .section .rodata
process_name:    .asciz "hex0-seed"
input_name:      .asciz "/input"
output_name:     .asciz "/output"
stage0_success:  .asciz "builder-hex0-riscv64 real stage0 hex0-seed passed\n"

    .section .data
    .balign 8
user_entry_address: .dword USER_VIRT
external_elf:       .dword 0
next_fd:            .dword 4
input_offset:       .dword 0
input_length:       .dword 0
output_length:      .dword 0
