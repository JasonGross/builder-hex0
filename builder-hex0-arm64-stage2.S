/* SPDX-License-Identifier: MIT
 *
 * AArch64 builder-hex0 stage-2 privilege, paging, and disk-backed ELF bring-up.
 */

    .arch armv8-a
    .section .text.boot
    .globl _start

    .equ UART0,              0x09000000
    .equ VIRTIO_FIRST,       0x0a000000
    .equ VIRTIO_END,         0x0a004000
    .equ ROOT_PAGE_TABLE,    0x41000000
    .equ LOW_PAGE_TABLE,     0x41001000
    .equ USER_ENTRY_SLOT,    0x41002000
    .equ PROCESS_BRK_SLOT,   0x41002008
    .equ PROCESS_BRK_MIN,    0x41002010
    .equ FILE_COUNT_SLOT,    0x41002018
    .equ VIRTQ_DESC,         0x41200000
    .equ VIRTQ_AVAIL,        0x41201000
    .equ VIRTQ_USED,         0x41202000
    .equ VIRTIO_HEADER,      0x41203000
    .equ VIRTIO_STATUS,      0x41203010
    .equ SECTOR_BUFFER,      0x41204000
    .equ FILE_TABLE,         0x41400000
    .equ FD_TABLE,           0x41401000
    .equ FILE_NAMES,         0x41402000
    .equ FILE_DATA,          0x41800000
    .equ FILE_RECORD_SIZE,   32
    .equ FD_RECORD_SIZE,     24
    .equ MAX_FILES,          16
    .equ MAX_FDS,            32
    .equ FILE_CAPACITY,      65536
    .equ USER_PHYS,          0x40600000
    .equ USER_VIRT,          0x00600000
    .equ USER_PHYS_OFFSET,   0x40000000
    .equ USER_HEAP_TOP,      0x02000000
    .equ USER_STACK_PHYS,    0x47e00000
    .equ USER_STACK_TOP,     0x08000000
    .equ KERNEL_STACK_TOP,   0x47dff000
    .equ ELF_SOURCE,         0x43000000
    .equ ELF_SOURCE_LIMIT,   0x44000000
    .equ DISK_HEADER_MAGIC,  0x3245415244485842 /* "BXHDRAE2" */

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

2:  ldr     x9, =USER_ENTRY_SLOT
    ldr     x10, =USER_VIRT
    str     x10, [x9]

    /* One L1 root and one low L2 table cover this stage. */
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

    /*
     * VA 0x00600000..0x01ffffff maps the user image and initial brk arena.
     * The 2 MiB blocks are EL0 R/W/X normal memory during bootstrap.
     */
    ldr     x9, =(LOW_PAGE_TABLE + 24)
    ldr     x10, =(USER_PHYS | (1 << 53) | 0x745)
    ldr     x11, =(USER_PHYS_OFFSET + USER_HEAP_TOP)
    ldr     x12, =0x00200000
    ldr     x13, =USER_PHYS
4:  str     x10, [x9], #8
    add     x10, x10, x12
    add     x13, x13, x12
    cmp     x13, x11
    b.lo    4b

    /* VA 0x07e00000 -> PA 0x47e00000, EL0 R/W and execute-never. */
    ldr     x9, =LOW_PAGE_TABLE
    ldr     x10, =(USER_STACK_PHYS | (3 << 53) | 0x745)
    str     x10, [x9, #504]

    /* EL1-only device mapping for the PL011 2 MiB window. */
    ldr     x10, =(UART0 | (3 << 53) | 0x401)
    str     x10, [x9, #576]

    /* EL1-only device mapping for all QEMU virt virtio-mmio slots. */
    ldr     x10, =(VIRTIO_FIRST | (3 << 53) | 0x401)
    str     x10, [x9, #640]

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
    bl      init_filesystem
    bl      load_disk_elf_optional
    cbz     x0, 5f
    ldr     x9, =USER_ENTRY_SLOT
    str     x0, [x9]
5:
    ldr     x9, =USER_STACK_TOP
    msr     sp_el0, x9
    ldr     x9, =USER_ENTRY_SLOT
    ldr     x9, [x9]
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

    cmp     x8, #56               /* Linux AArch64 openat */
    b.eq    syscall_openat
    cmp     x8, #57               /* Linux AArch64 close */
    b.eq    syscall_close
    cmp     x8, #62               /* Linux AArch64 lseek */
    b.eq    syscall_lseek
    cmp     x8, #63               /* Linux AArch64 read */
    b.eq    syscall_read
    cmp     x8, #64               /* Linux AArch64 write */
    b.eq    syscall_write
    cmp     x8, #214              /* Linux AArch64 brk */
    b.eq    syscall_brk
    cmp     x8, #93               /* Linux AArch64 exit */
    b.eq    syscall_exit
    cmp     x8, #94               /* Linux AArch64 exit_group */
    b.eq    syscall_exit
    mov     x0, #-38              /* -ENOSYS */
    b       trap_return

syscall_write:
    cmp     x0, #3
    b.hs    syscall_write_file
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

syscall_openat:
    mov     x19, x1               /* pathname */
    mov     x20, x2               /* flags */
    mov     x0, x19
    bl      find_file
    cbnz    x0, 1f
    tst     x20, #0x40            /* O_CREAT */
    b.eq    syscall_no_entry
    mov     x0, x19
    bl      create_file
    cbz     x0, syscall_no_space
1:  mov     x11, x0               /* file record */
    tst     x20, #0x200           /* O_TRUNC */
    b.eq    2f
    and     x12, x20, #3
    cbz     x12, 2f
    str     xzr, [x11, #16]
2:  ldr     x9, =FD_TABLE
    add     x9, x9, #(3 * FD_RECORD_SIZE)
    mov     x10, #3
3:  ldr     x12, [x9]
    cbz     x12, 4f
    add     x9, x9, #FD_RECORD_SIZE
    add     x10, x10, #1
    cmp     x10, #MAX_FDS
    b.lo    3b
    mov     x0, #-24              /* -EMFILE */
    b       trap_return
4:  str     x11, [x9]
    str     xzr, [x9, #8]
    str     x20, [x9, #16]
    mov     x0, x10
    b       trap_return

syscall_close:
    cmp     x0, #3
    b.lo    syscall_bad_fd
    cmp     x0, #MAX_FDS
    b.hs    syscall_bad_fd
    mov     x10, #FD_RECORD_SIZE
    ldr     x9, =FD_TABLE
    madd    x9, x0, x10, x9
    ldr     x10, [x9]
    cbz     x10, syscall_bad_fd
    str     xzr, [x9]
    str     xzr, [x9, #8]
    str     xzr, [x9, #16]
    mov     x0, #0
    b       trap_return

syscall_read:
    cmp     x0, #3
    b.lo    syscall_bad_fd
    cmp     x0, #MAX_FDS
    b.hs    syscall_bad_fd
    mov     x10, #FD_RECORD_SIZE
    ldr     x9, =FD_TABLE
    madd    x9, x0, x10, x9
    ldr     x10, [x9]             /* file record */
    cbz     x10, syscall_bad_fd
    ldr     x11, [x9, #16]
    and     x11, x11, #3
    cmp     x11, #1               /* O_WRONLY */
    b.eq    syscall_bad_fd
    ldr     x12, [x9, #8]         /* offset */
    ldr     x13, [x10, #16]       /* length */
    cmp     x12, x13
    b.hs    3f
    sub     x13, x13, x12
    cmp     x2, x13
    csel    x14, x2, x13, lo      /* transfer count */
    ldr     x15, [x10, #8]
    add     x15, x15, x12         /* source */
    mov     x16, x1               /* destination */
    mov     x17, x14
1:  cbz     x17, 2f
    ldrb    w10, [x15], #1
    strb    w10, [x16], #1
    sub     x17, x17, #1
    b       1b
2:  add     x12, x12, x14
    str     x12, [x9, #8]
    mov     x0, x14
    b       trap_return
3:  mov     x0, #0
    b       trap_return

syscall_write_file:
    cmp     x0, #MAX_FDS
    b.hs    syscall_bad_fd
    mov     x10, #FD_RECORD_SIZE
    ldr     x9, =FD_TABLE
    madd    x9, x0, x10, x9
    ldr     x10, [x9]             /* file record */
    cbz     x10, syscall_bad_fd
    ldr     x11, [x9, #16]
    and     x11, x11, #3
    cbz     x11, syscall_bad_fd   /* O_RDONLY */
    ldr     x12, [x9, #8]         /* offset */
    adds    x13, x12, x2
    b.cs    syscall_no_space
    ldr     x14, [x10, #24]       /* capacity */
    cmp     x13, x14
    b.hi    syscall_no_space
    ldr     x14, [x10, #8]
    add     x14, x14, x12         /* destination */
    mov     x15, x1               /* source */
    mov     x16, x2
1:  cbz     x16, 2f
    ldrb    w17, [x15], #1
    strb    w17, [x14], #1
    sub     x16, x16, #1
    b       1b
2:  str     x13, [x9, #8]
    ldr     x14, [x10, #16]
    cmp     x13, x14
    csel    x14, x13, x14, hi
    str     x14, [x10, #16]
    mov     x0, x2
    b       trap_return

syscall_lseek:
    cmp     x0, #3
    b.lo    syscall_bad_fd
    cmp     x0, #MAX_FDS
    b.hs    syscall_bad_fd
    mov     x10, #FD_RECORD_SIZE
    ldr     x9, =FD_TABLE
    madd    x9, x0, x10, x9
    ldr     x10, [x9]             /* file record */
    cbz     x10, syscall_bad_fd
    cbz     x2, 1f                /* SEEK_SET */
    cmp     x2, #1
    b.eq    2f                    /* SEEK_CUR */
    cmp     x2, #2
    b.ne    syscall_invalid
    ldr     x11, [x10, #16]       /* SEEK_END */
    b       3f
1:  mov     x11, #0
    b       3f
2:  ldr     x11, [x9, #8]
3:  adds    x11, x11, x1
    b.mi    syscall_invalid
    ldr     x12, [x10, #24]
    cmp     x11, x12
    b.hi    syscall_invalid
    str     x11, [x9, #8]
    mov     x0, x11
    b       trap_return

syscall_no_entry:
    mov     x0, #-2               /* -ENOENT */
    b       trap_return

syscall_no_space:
    mov     x0, #-28              /* -ENOSPC */
    b       trap_return

syscall_invalid:
    mov     x0, #-22              /* -EINVAL */
    b       trap_return

syscall_brk:
    ldr     x9, =PROCESS_BRK_SLOT
    ldr     x10, [x9]             /* old break */
    cbz     x0, 3f
    ldr     x11, =PROCESS_BRK_MIN
    ldr     x11, [x11]
    cmp     x0, x11
    b.lo    3f
    ldr     x11, =USER_HEAP_TOP
    cmp     x0, x11
    b.hi    3f
    cmp     x0, x10
    b.ls    2f
    ldr     x11, =USER_PHYS_OFFSET
    add     x11, x10, x11
    sub     x12, x0, x10
1:  strb    wzr, [x11], #1
    subs    x12, x12, #1
    b.ne    1b
2:  str     x0, [x9]
    b       trap_return
3:  mov     x0, x10               /* raw brk returns the old break on failure */
4:  b       trap_return

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

/* Fixed-size memory-file and descriptor tables for the stage0-posix surface. */
init_filesystem:
    ldr     x9, =FILE_TABLE
    ldr     x10, =FILE_NAMES
1:  str     xzr, [x9], #8
    cmp     x9, x10
    b.lo    1b

    ldr     x9, =FILE_TABLE
    ldr     x10, =FILE_NAMES
    str     x10, [x9]             /* name */
    ldr     x11, =FILE_DATA
    str     x11, [x9, #8]         /* data */
    adrp    x12, input_data
    add     x12, x12, :lo12:input_data
    adrp    x13, input_data_end
    add     x13, x13, :lo12:input_data_end
    sub     x14, x13, x12
    str     x14, [x9, #16]        /* length */
    ldr     x14, =FILE_CAPACITY
    str     x14, [x9, #24]        /* capacity */

    adrp    x12, input_name
    add     x12, x12, :lo12:input_name
    mov     x13, x10
2:  ldrb    w14, [x12], #1
    strb    w14, [x13], #1
    cbnz    w14, 2b

    adrp    x12, input_data
    add     x12, x12, :lo12:input_data
    adrp    x13, input_data_end
    add     x13, x13, :lo12:input_data_end
    ldr     x14, =FILE_DATA
3:  cmp     x12, x13
    b.hs    4f
    ldrb    w15, [x12], #1
    strb    w15, [x14], #1
    b       3b
4:  ldr     x9, =FILE_COUNT_SLOT
    mov     x10, #1
    str     x10, [x9]
    ret

/* x0=path, returns the newest matching file record or zero. */
find_file:
    mov     x17, x0
    ldr     x9, =FILE_COUNT_SLOT
    ldr     x10, [x9]
    ldr     x9, =FILE_TABLE
1:  cbz     x10, 4f
    ldr     x11, [x9]
    mov     x12, x17
2:  ldrb    w13, [x11], #1
    ldrb    w14, [x12], #1
    cmp     w13, w14
    b.ne    3f
    cbnz    w13, 2b
    mov     x0, x9
    ret
3:  add     x9, x9, #FILE_RECORD_SIZE
    sub     x10, x10, #1
    b       1b
4:  mov     x0, #0
    ret

/* x0=path, returns a new empty file record or zero. */
create_file:
    mov     x17, x0
    ldr     x9, =FILE_COUNT_SLOT
    ldr     x10, [x9]
    cmp     x10, #MAX_FILES
    b.hs    4f
    ldr     x11, =FILE_TABLE
    add     x11, x11, x10, lsl #5
    ldr     x12, =FILE_NAMES
    add     x12, x12, x10, lsl #7
    mov     x13, x12
    mov     x14, #0
1:  ldrb    w15, [x17], #1
    cbz     w15, 2f
    cmp     x14, #127
    b.hs    4f
    strb    w15, [x13], #1
    add     x14, x14, #1
    b       1b
2:  strb    wzr, [x13]
    str     x12, [x11]
    ldr     x12, =FILE_DATA
    add     x12, x12, x10, lsl #16
    str     x12, [x11, #8]
    str     xzr, [x11, #16]
    ldr     x12, =FILE_CAPACITY
    str     x12, [x11, #24]
    add     x10, x10, #1
    str     x10, [x9]
    mov     x0, x11
    ret
4:  mov     x0, #0
    ret

/*
 * A valid sector-zero header selects the disk-backed ELF gate:
 *   u64 magic "BXHDRAE2", u64 first sector, u64 exact ELF byte count.
 * No block device or an unrelated disk preserves the built-in fixture path.
 */
load_disk_elf_optional:
    stp     x19, x30, [sp, #-16]!
    bl      virtio_init_optional
    cbz     x0, 3f
    mov     x0, #0
    ldr     x1, =SECTOR_BUFFER
    bl      read_sector
    ldr     x9, =SECTOR_BUFFER
    ldr     x10, [x9]
    ldr     x11, =DISK_HEADER_MAGIC
    cmp     x10, x11
    b.ne    3f
    ldr     x0, [x9, #8]
    ldr     x19, [x9, #16]
    cbz     x19, elf_failure
    ldr     x10, =(ELF_SOURCE_LIMIT - ELF_SOURCE - 512)
    cmp     x19, x10
    b.hi    elf_failure
    mov     x1, x19
    ldr     x2, =ELF_SOURCE
    bl      read_bytes
    ldr     x0, =ELF_SOURCE
    mov     x1, x19
    bl      load_elf
    mov     x19, x0
    adrp    x0, disk_elf_message
    add     x0, x0, :lo12:disk_elf_message
    bl      uart_puts
    adrp    x0, disk_brk_message
    add     x0, x0, :lo12:disk_brk_message
    bl      uart_puts
    ldr     x9, =PROCESS_BRK_SLOT
    ldr     x0, [x9]
    bl      uart_puthex64
    mov     x0, #10
    bl      uart_putc
    mov     x0, x19
    b       4f
3:  mov     x0, #0
4:  ldp     x19, x30, [sp], #16
    ret

/* Optional modern or legacy virtio-mmio block device, split queue. */
virtio_init_optional:
    ldr     x9, =VIRTIO_FIRST
    ldr     x12, =VIRTIO_END
    ldr     w11, =0x74726976
0:  cmp     x9, x12
    b.hs    9f
    ldr     w10, [x9]
    cmp     w10, w11
    b.ne    8f
    ldr     w10, [x9, #8]
    cmp     w10, #2
    b.eq    7f
8:  add     x9, x9, #0x200
    b       0b
7:  mov     x28, x9

    /* Queue memory must not retain indices from an earlier bootstrap stage. */
    ldr     x10, =VIRTQ_DESC
    ldr     x11, =(VIRTQ_USED + 4096)
6:  str     xzr, [x10], #8
    cmp     x10, x11
    b.lo    6b

    str     wzr, [x9, #0x70]
    mov     w10, #3
    str     w10, [x9, #0x70]      /* ACKNOWLEDGE | DRIVER */
    ldr     w10, [x9, #4]
    cmp     w10, #1
    b.eq    virtio_init_legacy
    cmp     w10, #2
    b.ne    9f

    mov     w10, #1
    str     w10, [x9, #0x14]      /* device feature word 1 */
    ldr     w11, [x9, #0x10]
    and     w11, w11, #1          /* VIRTIO_F_VERSION_1 */
    cbz     w11, 9f
    str     w10, [x9, #0x24]      /* driver feature word 1 */
    str     w11, [x9, #0x20]
    mov     w10, #11
    str     w10, [x9, #0x70]      /* + FEATURES_OK */
    ldr     w11, [x9, #0x70]
    tst     w11, #8
    b.eq    9f

    str     wzr, [x9, #0x30]
    ldr     w11, [x9, #0x34]
    cbz     w11, 9f
    mov     w10, #8
    cmp     w11, w10
    csel    w11, w11, w10, lo
    str     w11, [x9, #0x38]
    ldr     w10, =VIRTQ_DESC
    str     w10, [x9, #0x80]
    str     wzr, [x9, #0x84]
    ldr     w10, =VIRTQ_AVAIL
    str     w10, [x9, #0x90]
    str     wzr, [x9, #0x94]
    ldr     w10, =VIRTQ_USED
    str     w10, [x9, #0xa0]
    str     wzr, [x9, #0xa4]
    mov     w10, #1
    str     w10, [x9, #0x44]
    mov     w10, #15
    str     w10, [x9, #0x70]      /* + DRIVER_OK */
    ldr     x25, =VIRTQ_DESC
    ldr     x26, =VIRTQ_AVAIL
    ldr     x27, =VIRTQ_USED
    mov     x0, #1
    ret

virtio_init_legacy:
    str     wzr, [x9, #0x24]
    str     wzr, [x9, #0x20]
    mov     w10, #4096
    str     w10, [x9, #0x28]
    str     wzr, [x9, #0x30]
    ldr     w11, [x9, #0x34]
    cbz     w11, 9f
    mov     w10, #8
    cmp     w11, w10
    csel    w11, w11, w10, lo
    str     w11, [x9, #0x38]
    mov     w10, #4096
    str     w10, [x9, #0x3c]
    ldr     w10, =(VIRTQ_DESC >> 12)
    str     w10, [x9, #0x40]
    mov     w10, #7
    str     w10, [x9, #0x70]      /* + DRIVER_OK */
    ldr     x25, =VIRTQ_DESC
    ldr     x26, =(VIRTQ_DESC + 128)
    ldr     x27, =(VIRTQ_DESC + 4096)
    mov     x0, #1
    ret
9:  mov     x0, #0
    ret

/* x0=sector, x1=buffer */
read_sector:
    mov     x2, #0

virtio_sector:
    ldr     x9, =VIRTIO_HEADER
    str     w2, [x9]
    str     wzr, [x9, #4]
    str     x0, [x9, #8]
    ldr     x10, =VIRTIO_STATUS
    mov     w11, #0xff
    strb    w11, [x10]

    mov     x9, x25
    ldr     x10, =VIRTIO_HEADER
    str     x10, [x9]
    mov     w10, #16
    str     w10, [x9, #8]
    mov     w10, #1
    strh    w10, [x9, #12]        /* NEXT */
    strh    w10, [x9, #14]
    str     x1, [x9, #16]
    mov     w10, #512
    str     w10, [x9, #24]
    mov     w10, #3               /* NEXT | WRITE */
    strh    w10, [x9, #28]
    mov     w10, #2
    strh    w10, [x9, #30]
    ldr     x10, =VIRTIO_STATUS
    str     x10, [x9, #32]
    mov     w10, #1
    str     w10, [x9, #40]
    mov     w10, #2
    strh    w10, [x9, #44]        /* WRITE */
    strh    wzr, [x9, #46]

    ldrh    w10, [x26, #2]
    and     w11, w10, #7
    add     x11, x26, x11, lsl #1
    strh    wzr, [x11, #4]
    add     w10, w10, #1
    dmb     ishst
    strh    w10, [x26, #2]
    dmb     ish

    ldrh    w10, [x27, #2]
    str     wzr, [x28, #0x50]
1:  dmb     ish
    ldrh    w11, [x27, #2]
    cmp     w10, w11
    b.eq    1b
    ldr     x9, =VIRTIO_STATUS
    ldrb    w10, [x9]
    cbnz    w10, disk_failure
    ret

/* x0=start sector, x1=byte count, x2=destination */
read_bytes:
    stp     x19, x20, [sp, #-32]!
    stp     x21, x30, [sp, #16]
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
1:  cbz     x20, 2f
    mov     x0, x19
    mov     x1, x21
    bl      read_sector
    add     x19, x19, #1
    add     x21, x21, #512
    subs    x20, x20, #512
    b.gt    1b
2:  ldp     x21, x30, [sp, #16]
    ldp     x19, x20, [sp], #32
    ret

/* x0=ELF image, x1=exact bytes; returns validated e_entry. */
load_elf:
    sub     sp, sp, #80
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    stp     x23, x24, [sp, #32]
    stp     x25, x26, [sp, #48]
    str     x30, [sp, #64]
    mov     x19, x0               /* source */
    mov     x20, x1               /* exact source bytes */
    cmp     x20, #64
    b.lo    elf_failure
    ldr     x9, [x19]
    ldr     x10, =0x00010102464c457f
    cmp     x9, x10               /* ELF64, little-endian, current version */
    b.ne    elf_failure
    ldrh    w9, [x19, #16]
    cmp     w9, #2                /* ET_EXEC */
    b.ne    elf_failure
    ldrh    w9, [x19, #18]
    cmp     w9, #183              /* EM_AARCH64 */
    b.ne    elf_failure
    ldr     w25, [x19, #20]
    cmp     w25, #1
    b.ne    elf_failure
    ldrh    w9, [x19, #52]
    cmp     w9, #64
    b.ne    elf_failure
    ldrh    w23, [x19, #54]
    cmp     w23, #56
    b.ne    elf_failure
    ldrh    w22, [x19, #56]
    cbz     x22, elf_failure
    cmp     x22, #32
    b.hi    elf_failure
    ldr     x9, [x19, #32]
    mul     x10, x22, x23
    adds    x10, x9, x10
    b.cs    elf_failure
    cmp     x10, x20
    b.hi    elf_failure
    add     x21, x19, x9          /* program-header cursor */
    ldr     x25, [x19, #24]       /* entry */
    ldr     x24, =USER_VIRT       /* highest loaded virtual address */
    mov     x26, #0               /* PT_LOAD count */

1:  ldr     w9, [x21]
    cmp     w9, #1                /* PT_LOAD */
    b.ne    5f
    ldr     x10, [x21, #16]       /* p_vaddr */
    ldr     x15, [x21, #32]       /* p_filesz */
    ldr     x11, [x21, #40]       /* p_memsz */
    cmp     x11, x15
    b.lo    elf_failure
    ldr     x9, =USER_VIRT
    cmp     x10, x9
    b.lo    elf_failure
    adds    x12, x10, x11         /* virtual segment end */
    b.cs    elf_failure
    ldr     x9, =USER_HEAP_TOP
    cmp     x12, x9
    b.hi    elf_failure
    ldr     x14, [x21, #8]        /* p_offset */
    adds    x16, x14, x15
    b.cs    elf_failure
    cmp     x16, x20
    b.hi    elf_failure
    add     x17, x19, x14         /* source bytes */
    ldr     x9, =USER_PHYS_OFFSET
    add     x13, x10, x9          /* physical destination */
    sub     x11, x11, x15         /* BSS bytes */
2:  cbz     x15, 3f
    ldrb    w9, [x17], #1
    strb    w9, [x13], #1
    sub     x15, x15, #1
    b       2b
3:  cbz     x11, 4f
    strb    wzr, [x13], #1
    sub     x11, x11, #1
    b       3b
4:  cmp     x12, x24
    csel    x24, x12, x24, hi
    add     x26, x26, #1
5:  add     x21, x21, x23
    subs    x22, x22, #1
    b.ne    1b

    cbz     x26, elf_failure
    ldr     x9, =USER_VIRT
    cmp     x25, x9
    b.lo    elf_failure
    ldr     x9, =USER_HEAP_TOP
    cmp     x25, x9
    b.hs    elf_failure
    add     x24, x24, #4095
    and     x24, x24, #0xfffffffffffff000
    ldr     x9, =PROCESS_BRK_SLOT
    str     x24, [x9]
    ldr     x9, =PROCESS_BRK_MIN
    str     x24, [x9]
    mov     x0, x25
    ldr     x30, [sp, #64]
    ldp     x25, x26, [sp, #48]
    ldp     x23, x24, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp, #0]
    add     sp, sp, #80
    ret

disk_failure:
    adrp    x0, disk_failure_message
    add     x0, x0, :lo12:disk_failure_message
    bl      uart_puts
    b       poweroff

elf_failure:
    adrp    x0, elf_failure_message
    add     x0, x0, :lo12:elf_failure_message
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

uart_puthex64:
    stp     x19, x20, [sp, #-32]!
    str     x30, [sp, #16]
    mov     x19, x0
    mov     x20, #60
1:  lsrv    x9, x19, x20
    and     x9, x9, #15
    cmp     x9, #10
    b.lo    2f
    add     x0, x9, #55
    b       3f
2:  add     x0, x9, #48
3:  bl      uart_putc
    subs    x20, x20, #4
    b.ge    1b
    ldr     x30, [sp, #16]
    ldp     x19, x20, [sp], #32
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
disk_failure_message:
    .asciz  "builder-hex0-arm64 stage2 disk request failed\n"
elf_failure_message:
    .asciz  "builder-hex0-arm64 stage2 invalid ELF64 image\n"
disk_elf_message:
    .asciz  "builder-hex0-arm64 stage2 disk ELF64 loaded\n"
disk_brk_message:
    .asciz  "builder-hex0-arm64 stage2 initial brk: 0x"
input_name:
    .asciz  "/input"
input_data:
    .ascii  "builder memory file input\n"
input_data_end:
