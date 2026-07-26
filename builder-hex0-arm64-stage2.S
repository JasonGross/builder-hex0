/* SPDX-License-Identifier: MIT
 *
 * AArch64 builder-hex0 stage-2 privilege and paging bring-up.
 * This proves EL0 execution and the Linux AArch64 svc boundary before the
 * disk, ELF, filesystem, and shell layers are added.
 */

    .arch armv8-a
    .section .text.boot
    .globl _start

    .equ UART0,              0x09000000
    .equ ROOT_PAGE_TABLE,    0x41000000
    .equ LOW_PAGE_TABLE,     0x41001000
    .equ USER_PHYS,          0x40600000
    .equ USER_VIRT,          0x00600000
    .equ USER_STACK_PHYS,    0x47e00000
    .equ USER_STACK_TOP,     0x08000000
    .equ KERNEL_STACK_TOP,   0x47dff000

_start:
    mrs     x9, CurrentEL
    lsr     x9, x9, #2
    cmp     x9, #2
    b.eq    drop_el2
    cmp     x9, #1
    b.eq    el1_entry
1:  wfe
    b       1b

drop_el2:
    movz    x9, #0x8000, lsl #16  /* HCR_EL2.RW: EL1 is AArch64 */
    msr     hcr_el2, x9
    mov     x9, #0x3c5            /* EL1h with DAIF masked */
    msr     spsr_el2, x9
    adr     x9, el1_entry
    msr     elr_el2, x9
    eret

el1_entry:
    msr     spsel, #1
    ldr     x9, =KERNEL_STACK_TOP
    mov     sp, x9

    /* Copy the position-independent EL0 fixture before enabling the MMU. */
    adr     x9, user_start
    adr     x10, user_end
    ldr     x11, =USER_PHYS
1:  cmp     x9, x10
    b.hs    2f
    ldrb    w12, [x9], #1
    strb    w12, [x11], #1
    b       1b

2:  /* One L1 root and one low L2 table cover this gate. */
    ldr     x9, =ROOT_PAGE_TABLE
    ldr     x10, =(LOW_PAGE_TABLE + 4096)
3:  str     xzr, [x9], #8
    cmp     x9, x10
    b.lo    3b

    ldr     x9, =ROOT_PAGE_TABLE
    ldr     x10, =(LOW_PAGE_TABLE | 3)
    str     x10, [x9]             /* L1[0] -> low L2 */

    /*
     * L1[1] maps 0x40000000..0x7fffffff for EL1. Attr1 is normal WB,
     * inner-shareable and accessed; UXN prevents EL0 execution.
     */
    ldr     x10, =(0x40000000 | (1 << 54) | 0x705)
    str     x10, [x9, #8]

    ldr     x9, =LOW_PAGE_TABLE
    /* VA 0x00600000 -> PA 0x40600000, EL0 R/W/X normal memory. */
    ldr     x10, =(USER_PHYS | (1 << 53) | 0x745)
    str     x10, [x9, #24]

    /* VA 0x07e00000 -> PA 0x47e00000, EL0 R/W and execute-never. */
    ldr     x10, =(USER_STACK_PHYS | (3 << 53) | 0x745)
    str     x10, [x9, #504]

    /* EL1-only device mapping for the PL011 2 MiB window. */
    ldr     x10, =(UART0 | (3 << 53) | 0x401)
    str     x10, [x9, #576]

    mov     x9, #0xff00           /* MAIR Attr1: normal WB; Attr0: device */
    msr     mair_el1, x9
    ldr     x9, =0x00803519       /* 39-bit TTBR0, 4 KiB, WB, EPD1 */
    msr     tcr_el1, x9
    ldr     x9, =ROOT_PAGE_TABLE
    msr     ttbr0_el1, x9
    dsb     sy
    isb
    tlbi    vmalle1
    dsb     sy
    isb

    mrs     x9, sctlr_el1
    orr     x9, x9, #1            /* MMU */
    orr     x9, x9, #4            /* data cache */
    orr     x9, x9, #0x1000       /* instruction cache */
    msr     sctlr_el1, x9
    isb

    adrp    x9, vector_table
    add     x9, x9, :lo12:vector_table
    msr     vbar_el1, x9
    ldr     x9, =USER_STACK_TOP
    msr     sp_el0, x9
    ldr     x9, =USER_VIRT
    msr     elr_el1, x9
    mov     x9, #0x3c0            /* EL0t with DAIF masked */
    msr     spsr_el1, x9
    eret

    .align 11
vector_table:
    b       trap_failure          /* current EL, SP0: sync */
    .balign 128
    b       trap_failure          /* current EL, SP0: IRQ */
    .balign 128
    b       trap_failure          /* current EL, SP0: FIQ */
    .balign 128
    b       trap_failure          /* current EL, SP0: SError */
    .balign 128
    b       trap_failure          /* current EL, SPx: sync */
    .balign 128
    b       trap_failure          /* current EL, SPx: IRQ */
    .balign 128
    b       trap_failure          /* current EL, SPx: FIQ */
    .balign 128
    b       trap_failure          /* current EL, SPx: SError */
    .balign 128
    b       lower_a64_sync        /* lower EL, AArch64: sync */
    .balign 128
    b       trap_failure          /* lower EL, AArch64: IRQ */
    .balign 128
    b       trap_failure          /* lower EL, AArch64: FIQ */
    .balign 128
    b       trap_failure          /* lower EL, AArch64: SError */
    .balign 128
    b       trap_failure          /* lower EL, AArch32: sync */
    .balign 128
    b       trap_failure          /* lower EL, AArch32: IRQ */
    .balign 128
    b       trap_failure          /* lower EL, AArch32: FIQ */
    .balign 128
    b       trap_failure          /* lower EL, AArch32: SError */

lower_a64_sync:
    sub     sp, sp, #256
    stp     x0, x1, [sp, #0]
    stp     x2, x3, [sp, #16]
    stp     x4, x5, [sp, #32]
    stp     x6, x7, [sp, #48]
    stp     x8, x9, [sp, #64]
    stp     x10, x11, [sp, #80]
    stp     x12, x13, [sp, #96]
    stp     x14, x15, [sp, #112]
    stp     x16, x17, [sp, #128]
    stp     x18, x19, [sp, #144]
    stp     x20, x21, [sp, #160]
    stp     x22, x23, [sp, #176]
    stp     x24, x25, [sp, #192]
    stp     x26, x27, [sp, #208]
    stp     x28, x29, [sp, #224]
    str     x30, [sp, #240]

    mrs     x9, esr_el1
    lsr     x9, x9, #26
    cmp     x9, #0x15             /* SVC from AArch64 */
    b.ne    trap_failure

    cmp     x8, #64               /* Linux AArch64 write */
    b.eq    syscall_write
    cmp     x8, #93               /* Linux AArch64 exit */
    b.eq    syscall_exit
    mov     x0, #-38              /* -ENOSYS */
    b       trap_return

syscall_write:
    cmp     x0, #1
    b.eq    1f
    cmp     x0, #2
    b.ne    syscall_bad_fd
1:  mov     x9, x1
    mov     x10, x2
    mov     x0, #0
2:  cbz     x10, trap_return
    ldrb    w11, [x9], #1
    ldr     x12, =UART0
3:  ldr     w13, [x12, #0x18]
    tst     w13, #0x20
    b.ne    3b
    strb    w11, [x12]
    sub     x10, x10, #1
    add     x0, x0, #1
    b       2b

syscall_bad_fd:
    mov     x0, #-9               /* -EBADF */
    b       trap_return

syscall_exit:
    cbnz    x0, trap_failure
    b       poweroff

trap_return:
    str     x0, [sp]
    ldp     x0, x1, [sp, #0]
    ldp     x2, x3, [sp, #16]
    ldp     x4, x5, [sp, #32]
    ldp     x6, x7, [sp, #48]
    ldp     x8, x9, [sp, #64]
    ldp     x10, x11, [sp, #80]
    ldp     x12, x13, [sp, #96]
    ldp     x14, x15, [sp, #112]
    ldp     x16, x17, [sp, #128]
    ldp     x18, x19, [sp, #144]
    ldp     x20, x21, [sp, #160]
    ldp     x22, x23, [sp, #176]
    ldp     x24, x25, [sp, #192]
    ldp     x26, x27, [sp, #208]
    ldp     x28, x29, [sp, #224]
    ldr     x30, [sp, #240]
    add     sp, sp, #256
    eret

trap_failure:
    adrp    x0, trap_failure_message
    add     x0, x0, :lo12:trap_failure_message
    bl      uart_puts
    b       poweroff

uart_putc:
    ldr     x9, =UART0
1:  ldr     w10, [x9, #0x18]
    tst     w10, #0x20
    b.ne    1b
    strb    w0, [x9]
    ret

uart_puts:
    stp     x19, x30, [sp, #-16]!
    mov     x19, x0
1:  ldrb    w0, [x19], #1
    cbz     w0, 2f
    bl      uart_putc
    b       1b
2:  ldp     x19, x30, [sp], #16
    ret

poweroff:
    mov     w0, #8
    movk    w0, #0x8400, lsl #16  /* PSCI SYSTEM_OFF */
    hvc     #0
1:  wfe
    b       1b

/* Position-independent fixture copied to EL0 virtual address 0x00600000. */
user_start:
    mov     x0, #1
    adr     x1, user_message
    adr     x2, user_message_end
    sub     x2, x2, x1
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0
user_message:
    .ascii  "builder-hex0-arm64 stage2 EL0 svc passed\n"
user_message_end:
user_end:

    .section .rodata
trap_failure_message:
    .asciz  "builder-hex0-arm64 stage2 trap failure\n"
