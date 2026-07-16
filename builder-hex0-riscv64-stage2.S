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

_start:
    li      sp, KERNEL_STACK_TOP
    li      t0, UART0
    li      t1, 3
    sb      t1, 3(t0)              /* 8n1 */

    /* Copy the position-independent user fixture to its physical page. */
    la      t0, user_start
    la      t1, user_end
    li      t2, USER_PHYS
1:  bgeu    t0, t1, 2f
    lbu     t3, 0(t0)
    sb      t3, 0(t2)
    addi    t0, t0, 1
    addi    t2, t2, 1
    j       1b

2:  /* Zero both page-table pages. */
    li      t0, ROOT_PAGE_TABLE
    li      t1, LOW_PAGE_TABLE + 4096
3:  sd      zero, 0(t0)
    addi    t0, t0, 8
    bltu    t0, t1, 3b

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
    li      t0, USER_VIRT
    csrw    sepc, t0
    csrr    t0, sstatus
    li      t1, ~(1 << 8)          /* SPP = U */
    and     t0, t0, t1
    li      t1, (1 << 5) | (1 << 18) /* SPIE | SUM */
    or      t0, t0, t1
    csrw    sstatus, t0
    li      sp, USER_STACK_TOP
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
    li      t0, 93                 /* Linux riscv64 exit */
    beq     a7, t0, syscall_exit
    li      a0, -38                /* -ENOSYS */
    j       trap_return

syscall_write:
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

syscall_exit:
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
