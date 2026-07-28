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
    .equ CHILD_PROCESS_SLOT, 0x41002020
    .equ CHILD_EXIT_STATUS,  0x41002028
    .equ PARENT_ELR_SLOT,    0x41002030
    .equ PARENT_SP_SLOT,     0x41002038
    .equ PARENT_BRK_SLOT,    0x41002040
    .equ PARENT_BRK_MIN_SLOT, 0x41002048
    .equ PARENT_PROCESS_WORDS, 0x41002050
    .equ NEXT_FILE_DATA_SLOT, 0x41002058
    .equ SHELL_LBA_SLOT,     0x41002060
    .equ SHELL_REMAINING_SLOT, 0x41002068
    .equ SHELL_SECTOR_POS,   0x41002070
    .equ SHELL_FLUSH_PENDING, 0x41002078
    .equ SHELL_PROCESS_ACTIVE, 0x41002080
    .equ SHELL_RESUME_SP,    0x41002088
    .equ SHELL_RESUME_X30,   0x41002090
    .equ SHELL_COMMAND_PTR,  0x41002098
    .equ SHELL_ARGUMENT_PTR, 0x410020a0
    .equ VIRTQ_DESC,         0x41200000
    .equ VIRTQ_AVAIL,        0x41201000
    .equ VIRTQ_USED,         0x41202000
    .equ VIRTIO_HEADER,      0x41203000
    .equ VIRTIO_STATUS,      0x41203010
    .equ SECTOR_BUFFER,      0x41204000
    .equ FILE_TABLE,         0x45d00000
    .equ FD_TABLE,           0x45d02000
    .equ FILE_NAMES,         0x45d03000
    .equ CWD_BUFFER,         0x45d0b000
    .equ PATH_BUFFER,        0x45d0c000
    .equ SHELL_LINE_BUFFER,  0x45d0d000
    .equ FILE_DATA,          0x42000000
    .equ FILE_DATA_TOP,      0x43800000
    .equ FILE_RECORD_SIZE,   32
    .equ FD_RECORD_SIZE,     24
    .equ MAX_FILES,          256
    .equ MAX_FDS,            32
    .equ USER_PHYS,          0x40600000
    .equ USER_VIRT,          0x00600000
    .equ USER_PHYS_OFFSET,   0x40000000
    .equ USER_HEAP_TOP,      0x02000000
    .equ USER_STACK_PHYS,    0x47e00000
    .equ USER_STACK_TOP,     0x08000000
    .equ USER_STACK_SIZE,    0x00200000
    .equ KERNEL_STACK_TOP,   0x47dff000
    .equ ELF_SOURCE,         0x43800000
    .equ ELF_SOURCE_LIMIT,   0x44000000
    .equ PARENT_PROCESS,     0x44000000
    .equ PARENT_STACK,       0x45a00000
    .equ PARENT_FDS,         0x45c00000
    .equ PARENT_FRAME,       0x45c01000
    .equ EXEC_ARGV,          0x45c02000
    .equ EXEC_STRINGS,       0x45c03000
    .equ PARENT_CWD,         0x45c04000
    .equ DISK_HEADER_MAGIC,  0x3245415244485842 /* "BXHDRAE2" */
    .equ SHELL_HEADER_MAGIC, 0x3256415244485842 /* "BXHDRAV2" */

    .if PARENT_PROCESS + (USER_HEAP_TOP - USER_VIRT) > PARENT_STACK
    .error "parent process snapshot overlaps parent stack"
    .endif
    .if PARENT_STACK + USER_STACK_SIZE > PARENT_FDS
    .error "parent stack snapshot overlaps process metadata"
    .endif
    .if EXEC_STRINGS + 0xc00 > PARENT_CWD
    .error "exec string scratch overlaps parent cwd"
    .endif
    .if FILE_DATA_TOP > ELF_SOURCE
    .error "memory-file payloads overlap the disk ELF staging area"
    .endif
    .if FILE_NAMES + (MAX_FILES * 128) > CWD_BUFFER
    .error "file names overlap cwd state"
    .endif
    .if SHELL_LINE_BUFFER + 4096 > KERNEL_STACK_TOP
    .error "shell line buffer overlaps the kernel stack"
    .endif

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
    cmp     x8, #35               /* Linux AArch64 unlinkat */
    b.eq    syscall_unlinkat
    cmp     x8, #48               /* Linux AArch64 faccessat */
    b.eq    syscall_faccessat
    cmp     x8, #49               /* Linux AArch64 chdir */
    b.eq    syscall_chdir
    cmp     x8, #53               /* Linux AArch64 fchmodat */
    b.eq    syscall_fchmodat
    cmp     x8, #62               /* Linux AArch64 lseek */
    b.eq    syscall_lseek
    cmp     x8, #63               /* Linux AArch64 read */
    b.eq    syscall_read
    cmp     x8, #64               /* Linux AArch64 write */
    b.eq    syscall_write
    cmp     x8, #214              /* Linux AArch64 brk */
    b.eq    syscall_brk
    cmp     x8, #220              /* Linux AArch64 clone */
    b.eq    syscall_clone
    cmp     x8, #221              /* Linux AArch64 execve */
    b.eq    syscall_execve
    cmp     x8, #260              /* Linux AArch64 wait4 */
    b.eq    syscall_wait4
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
    mov     x20, x2               /* flags */
    mov     x0, x1
    ldr     x1, =PATH_BUFFER
    bl      normalize_path
    cbz     x0, syscall_name_too_long
    mov     x19, x0               /* canonical pathname */
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

syscall_unlinkat:
    mov     x0, x1
    ldr     x1, =PATH_BUFFER
    bl      normalize_path
    cbz     x0, syscall_name_too_long
    bl      find_file
    cbz     x0, syscall_no_entry
    str     xzr, [x0]
    mov     x0, #0
    b       trap_return

syscall_faccessat:
syscall_fchmodat:
    mov     x0, x1
    ldr     x1, =PATH_BUFFER
    bl      normalize_path
    cbz     x0, syscall_name_too_long
    bl      find_file
    cbz     x0, syscall_no_entry
    mov     x0, #0
    b       trap_return

syscall_chdir:
    ldr     x1, =PATH_BUFFER
    bl      normalize_path
    cbz     x0, syscall_name_too_long
    ldr     x1, =CWD_BUFFER
    bl      copy_string
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
    mov     x0, x10
    bl      finalize_file
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

syscall_name_too_long:
    mov     x0, #-36              /* -ENAMETOOLONG */
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

syscall_clone:
    ldr     x9, =CHILD_PROCESS_SLOT
    ldr     x10, [x9]
    cbnz    x10, syscall_try_again

    /* Preserve the parent trap frame and process control values. */
    mov     x0, sp
    ldr     x1, =PARENT_FRAME
    mov     x2, #32
    bl      copy_words
    mrs     x9, elr_el1
    ldr     x10, =PARENT_ELR_SLOT
    str     x9, [x10]
    mrs     x9, sp_el0
    ldr     x10, =PARENT_SP_SLOT
    str     x9, [x10]
    ldr     x9, =PROCESS_BRK_SLOT
    ldr     x9, [x9]
    ldr     x10, =PARENT_BRK_SLOT
    str     x9, [x10]
    ldr     x9, =PROCESS_BRK_MIN
    ldr     x9, [x9]
    ldr     x10, =PARENT_BRK_MIN_SLOT
    str     x9, [x10]

    /* Snapshot used process memory, the full user stack, fds, and cwd. */
    ldr     x9, =PROCESS_BRK_SLOT
    ldr     x2, [x9]
    ldr     x9, =USER_VIRT
    sub     x2, x2, x9
    add     x2, x2, #7
    lsr     x2, x2, #3
    ldr     x9, =PARENT_PROCESS_WORDS
    str     x2, [x9]
    ldr     x0, =USER_PHYS
    ldr     x1, =PARENT_PROCESS
    bl      copy_words
    ldr     x0, =USER_STACK_PHYS
    ldr     x1, =PARENT_STACK
    ldr     x2, =(USER_STACK_SIZE / 8)
    bl      copy_words
    ldr     x0, =FD_TABLE
    ldr     x1, =PARENT_FDS
    mov     x2, #96               /* 32 records * 24 bytes / 8 */
    bl      copy_words
    ldr     x0, =CWD_BUFFER
    ldr     x1, =PARENT_CWD
    mov     x2, #16
    bl      copy_words

    ldr     x9, =CHILD_PROCESS_SLOT
    mov     x10, #1
    str     x10, [x9]
    mov     x0, #0                /* child return */
    b       trap_return

syscall_execve:
    mov     x19, x1               /* argv in the old image */
    ldr     x1, =PATH_BUFFER
    bl      normalize_path
    cbz     x0, syscall_name_too_long
    bl      find_file
    cbz     x0, syscall_no_entry
    ldr     x20, [x0, #8]         /* ELF image */
    ldr     x21, [x0, #16]        /* exact image bytes */
    cmp     x21, #4
    b.lo    syscall_exec_format
    ldr     w9, [x20]
    ldr     w10, =0x464c457f
    cmp     w9, w10
    b.ne    syscall_exec_format

    /* Copy argv out before PT_LOAD overwrites the old process image. */
    ldr     x9, =EXEC_ARGV
    ldr     x10, =EXEC_STRINGS
    mov     x22, #0               /* argc */
1:  cbz     x19, 4f
    ldr     x11, [x19], #8
    cbz     x11, 4f
    cmp     x22, #31
    b.hs    syscall_arg_too_big
    str     x10, [x9], #8
2:  ldr     x12, =(EXEC_STRINGS + 0xc00)
    cmp     x10, x12
    b.hs    syscall_arg_too_big
    ldrb    w12, [x11], #1
    strb    w12, [x10], #1
    cbnz    w12, 2b
    add     x22, x22, #1
    b       1b

4:  mov     x0, x20
    mov     x1, x21
    bl      load_elf
    mov     x23, x0               /* new entry */

    /* Construct argc/argv/envp in the top page of the user stack. */
    ldr     x24, =(USER_STACK_PHYS + USER_STACK_SIZE - 4096)
    str     x22, [x24]
    add     x25, x24, #8          /* user argv slots */
    add     x26, x24, #0x400      /* user strings */
    ldr     x9, =EXEC_ARGV
    mov     x10, #0
5:  cmp     x10, x22
    b.hs    6f
    ldr     x11, =USER_PHYS_OFFSET
    sub     x11, x26, x11
    str     x11, [x25], #8
    ldr     x11, [x9], #8
7:  ldrb    w12, [x11], #1
    strb    w12, [x26], #1
    cbnz    w12, 7b
    add     x10, x10, #1
    b       5b
6:  str     xzr, [x25], #8        /* argv[argc] */
    str     xzr, [x25]            /* envp[0] */
    ldr     x9, =(USER_STACK_TOP - 4096)
    msr     sp_el0, x9
    msr     elr_el1, x23

    /* Successful exec starts with a clean register frame. */
    mov     x9, sp
    add     x10, sp, #256
8:  str     xzr, [x9], #8
    cmp     x9, x10
    b.lo    8b
    mov     x0, #0
    b       trap_return

syscall_exec_format:
    mov     x0, #-8               /* -ENOEXEC */
    b       trap_return

syscall_arg_too_big:
    mov     x0, #-7               /* -E2BIG */
    b       trap_return

syscall_wait4:
    ldr     x9, =CHILD_PROCESS_SLOT
    ldr     x9, [x9]
    cbnz    x9, syscall_try_again
    cbz     x1, 1f
    ldr     x9, =CHILD_EXIT_STATUS
    ldr     x9, [x9]
    lsl     x9, x9, #8
    str     w9, [x1]
1:  mov     x0, #1
    b       trap_return

syscall_try_again:
    mov     x0, #-11              /* -EAGAIN */
    b       trap_return

syscall_exit:
    ldr     x9, =CHILD_PROCESS_SLOT
    ldr     x9, [x9]
    cbnz    x9, restore_parent
    ldr     x9, =SHELL_PROCESS_ACTIVE
    ldr     x9, [x9]
    cbnz    x9, restore_shell
    cbnz    x0, trap_failure
    b       poweroff

restore_shell:
    mov     x10, x0
    ldr     x9, =SHELL_PROCESS_ACTIVE
    str     xzr, [x9]
    ldr     x9, =SHELL_RESUME_SP
    ldr     x9, [x9]
    mov     sp, x9
    ldr     x9, =SHELL_RESUME_X30
    ldr     x30, [x9]
    mov     x0, x10
    ret

restore_parent:
    ldr     x9, =CHILD_EXIT_STATUS
    str     x0, [x9]
    ldr     x9, =PARENT_PROCESS_WORDS
    ldr     x2, [x9]
    ldr     x0, =PARENT_PROCESS
    ldr     x1, =USER_PHYS
    bl      copy_words
    ldr     x0, =PARENT_STACK
    ldr     x1, =USER_STACK_PHYS
    ldr     x2, =(USER_STACK_SIZE / 8)
    bl      copy_words
    ldr     x0, =PARENT_FDS
    ldr     x1, =FD_TABLE
    mov     x2, #96
    bl      copy_words
    ldr     x0, =PARENT_CWD
    ldr     x1, =CWD_BUFFER
    mov     x2, #16
    bl      copy_words
    ldr     x9, =PARENT_BRK_SLOT
    ldr     x9, [x9]
    ldr     x10, =PROCESS_BRK_SLOT
    str     x9, [x10]
    ldr     x9, =PARENT_BRK_MIN_SLOT
    ldr     x9, [x9]
    ldr     x10, =PROCESS_BRK_MIN
    str     x9, [x10]
    ldr     x9, =PARENT_ELR_SLOT
    ldr     x9, [x9]
    msr     elr_el1, x9
    ldr     x9, =PARENT_SP_SLOT
    ldr     x9, [x9]
    msr     sp_el0, x9
    ldr     x9, =CHILD_PROCESS_SLOT
    str     xzr, [x9]
    ldr     x0, =PARENT_FRAME
    mov     x1, sp
    mov     x2, #32
    bl      copy_words
    mov     x0, #1                /* parent clone return */
    b       trap_return

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
4:  ldr     x9, =(FILE_TABLE + FILE_RECORD_SIZE)
    adrp    x10, exec_target_name
    add     x10, x10, :lo12:exec_target_name
    str     x10, [x9]
    adrp    x10, builtin_exec_elf
    add     x10, x10, :lo12:builtin_exec_elf
    str     x10, [x9, #8]
    adrp    x11, builtin_exec_elf_end
    add     x11, x11, :lo12:builtin_exec_elf_end
    sub     x11, x11, x10
    str     x11, [x9, #16]
    str     x11, [x9, #24]

    ldr     x9, =FILE_COUNT_SLOT
    mov     x10, #2
    str     x10, [x9]
    ldr     x9, =CWD_BUFFER
    mov     w10, #'/'
    strb    w10, [x9]
    strb    wzr, [x9, #1]
    ldr     x9, =CHILD_PROCESS_SLOT
    str     xzr, [x9]
    str     xzr, [x9, #8]
    ldr     x9, =NEXT_FILE_DATA_SLOT
    ldr     x10, =(FILE_DATA + 32)
    str     x10, [x9]
    ret

init_empty_filesystem:
    ldr     x9, =FILE_COUNT_SLOT
    str     xzr, [x9]
    ldr     x9, =NEXT_FILE_DATA_SLOT
    ldr     x10, =FILE_DATA
    str     x10, [x9]
    ldr     x9, =CWD_BUFFER
    mov     w10, #'/'
    strb    w10, [x9]
    strb    wzr, [x9, #1]
    ldr     x9, =CHILD_PROCESS_SLOT
    str     xzr, [x9]
    str     xzr, [x9, #8]
    ret

/* x0=source and x1=destination NUL-terminated strings. */
copy_string:
1:  ldrb    w9, [x0], #1
    strb    w9, [x1], #1
    cbnz    w9, 1b
    ret

/* x0=source, x1=destination, and x2=64-bit word count. */
copy_words:
1:  cbz     x2, 2f
    ldr     x9, [x0], #8
    str     x9, [x1], #8
    sub     x2, x2, #1
    b       1b
2:  ret

/*
 * x0=input path and x1=destination. Return a canonical absolute path, or
 * zero when the fixed 128-byte file-name representation would overflow.
 */
normalize_path:
    mov     x9, x0                /* input cursor */
    mov     x10, x1               /* output cursor */
    mov     x16, x1               /* output base */
    ldrb    w11, [x9]
    mov     w12, #'/'
    cmp     w11, w12
    b.eq    2f
    ldr     x13, =CWD_BUFFER
1:  ldrb    w11, [x13], #1
    cbz     w11, 3f
    strb    w11, [x10], #1
    b       1b
2:  strb    w12, [x10], #1
4:  add     x9, x9, #1
    ldrb    w11, [x9]
    cmp     w11, w12
    b.eq    4b
3:
    /* Skip separators, then classify "." and ".." components. */
5:  ldrb    w11, [x9]
    cbz     w11, 12f
    cmp     w11, w12
    b.eq    11f
    mov     w13, #'.'
    cmp     w11, w13
    b.ne    8f
    ldrb    w11, [x9, #1]
    cbz     w11, 6f
    cmp     w11, w12
    b.eq    6f
    cmp     w11, w13
    b.ne    8f
    ldrb    w11, [x9, #2]
    cbz     w11, 7f
    cmp     w11, w12
    b.ne    8f
7:  add     x9, x9, #2           /* parent component */
9:  add     x13, x16, #1
    cmp     x10, x13
    b.ls    5b
    sub     x10, x10, #1
    ldrb    w11, [x10]
    cmp     w11, w12
    b.ne    9b
    b       5b
6:  add     x9, x9, #1           /* current component */
    b       5b

8:  add     x13, x16, #1
    cmp     x10, x13
    b.ls    10f
    add     x14, x16, #127
    cmp     x10, x14
    b.hs    13f
    strb    w12, [x10], #1
10: ldrb    w11, [x9]
    cbz     w11, 5b
    cmp     w11, w12
    b.eq    5b
    add     x14, x16, #127
    cmp     x10, x14
    b.hs    13f
    strb    w11, [x10], #1
    add     x9, x9, #1
    b       10b
11: add     x9, x9, #1
    b       5b
12: strb    wzr, [x10]
    mov     x0, x16
    ret
13: mov     x0, #0
    ret

/* x0=path, returns the newest matching file record or zero. */
find_file:
    mov     x17, x0
    ldr     x9, =FILE_COUNT_SLOT
    ldr     x10, [x9]
    cbz     x10, 4f
    sub     x10, x10, #1
    ldr     x9, =FILE_TABLE
    add     x9, x9, x10, lsl #5
1:
    ldr     x11, [x9]
    cbz     x11, 3f
    mov     x12, x17
2:  ldrb    w13, [x11], #1
    ldrb    w14, [x12], #1
    cmp     w13, w14
    b.ne    3f
    cbnz    w13, 2b
    mov     x0, x9
    ret
3:  cbz     x10, 4f
    sub     x10, x10, #1
    sub     x9, x9, #FILE_RECORD_SIZE
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
    ldr     x12, =NEXT_FILE_DATA_SLOT
    ldr     x12, [x12]
    ldr     x13, =FILE_DATA_TOP
    cmp     x12, x13
    b.hs    4f
    str     x12, [x11, #8]
    str     xzr, [x11, #16]
    sub     x13, x13, x12
    str     x13, [x11, #24]
    add     x10, x10, #1
    str     x10, [x9]
    mov     x0, x11
    ret
4:  mov     x0, #0
    ret

/* Advance the monotonic payload allocator past x0's current file length. */
finalize_file:
    ldr     x9, [x0, #8]
    ldr     x10, [x0, #16]
    add     x9, x9, x10
    add     x9, x9, #15
    and     x9, x9, #0xfffffffffffffff0
    ldr     x10, =NEXT_FILE_DATA_SLOT
    ldr     x11, [x10]
    cmp     x9, x11
    b.ls    1f
    str     x9, [x10]
1:  ret

/* x0/x1=NUL-terminated strings; return one when equal. */
strings_equal:
1:  ldrb    w9, [x0], #1
    ldrb    w10, [x1], #1
    cmp     w9, w10
    b.ne    2f
    cbnz    w9, 1b
    mov     x0, #1
    ret
2:  mov     x0, #0
    ret

/* Stream one command byte from the disk script; -1 marks exact-length EOF. */
shell_getc:
    str     x30, [sp, #-16]!
    ldr     x9, =SHELL_REMAINING_SLOT
    ldr     x10, [x9]
    cbz     x10, 3f
    ldr     x11, =SHELL_SECTOR_POS
    ldr     x12, [x11]
    cmp     x12, #512
    b.lo    1f
    ldr     x13, =SHELL_LBA_SLOT
    ldr     x0, [x13]
    ldr     x1, =SECTOR_BUFFER
    bl      read_sector
    ldr     x13, =SHELL_LBA_SLOT
    ldr     x14, [x13]
    add     x14, x14, #1
    str     x14, [x13]
    ldr     x11, =SHELL_SECTOR_POS
    mov     x12, #0
1:  ldr     x13, =SECTOR_BUFFER
    ldrb    w0, [x13, x12]
    add     x12, x12, #1
    str     x12, [x11]
    ldr     x9, =SHELL_REMAINING_SLOT
    ldr     x10, [x9]
    sub     x10, x10, #1
    str     x10, [x9]
    b       4f
3:  mov     x0, #-1
4:  ldr     x30, [sp], #16
    ret

/* Read one command line into the fixed 4 KiB buffer. */
shell_getline:
    stp     x19, x20, [sp, #-32]!
    str     x30, [sp, #16]
    ldr     x19, =SHELL_LINE_BUFFER
    mov     x20, x19
1:  bl      shell_getc
    tbnz    x0, #63, 3f
    cmp     x0, #10
    b.eq    2f
    ldr     x9, =(SHELL_LINE_BUFFER + 4095)
    cmp     x19, x9
    b.hs    4f
    strb    w0, [x19], #1
    b       1b
2:  strb    wzr, [x19]
    mov     x0, x20
    b       5f
3:  cmp     x19, x20
    b.eq    5f
    strb    wzr, [x19]
    mov     x0, x20
    b       5f
4:  mov     x0, #-2
5:  ldr     x30, [sp, #16]
    ldp     x19, x20, [sp], #32
    ret

/* x0=cursor; return token in x0 and following cursor in x1. */
next_token:
1:  ldrb    w9, [x0]
    cmp     w9, #32
    b.eq    2f
    cmp     w9, #9
    b.ne    3f
2:  add     x0, x0, #1
    b       1b
3:  mov     x1, x0
4:  ldrb    w9, [x1]
    cbz     w9, 6f
    cmp     w9, #32
    b.eq    5f
    cmp     w9, #9
    b.eq    5f
    add     x1, x1, #1
    b       4b
5:  strb    wzr, [x1], #1
6:  ret

/* x0=unsigned decimal string; return the value or -1 when malformed. */
parse_decimal:
    mov     x9, x0
    mov     x0, #0
    mov     x12, #0
1:  ldrb    w10, [x9], #1
    cbz     w10, 3f
    cmp     w10, #'0'
    b.lo    4f
    cmp     w10, #('9' + 1)
    b.hs    4f
    sub     w10, w10, #'0'
    lsl     x11, x0, #3
    add     x0, x11, x0, lsl #1
    add     x0, x0, x10
    mov     x12, #1
    b       1b
3:  cbz     x12, 4f
    ret
4:  mov     x0, #-1
    ret

/* src N PATH */
shell_src:
    sub     sp, sp, #64
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]
    bl      next_token
    mov     x19, x1
    bl      parse_decimal
    tbnz    x0, #63, 4f
    mov     x20, x0
    mov     x0, x19
    bl      next_token
    ldrb    w9, [x0]
    cbz     w9, 4f
    ldr     x1, =PATH_BUFFER
    bl      normalize_path
    cbz     x0, 4f
    bl      create_file
    cbz     x0, 4f
    mov     x21, x0
    ldr     x9, [x21, #24]
    cmp     x20, x9
    b.hi    4f
    ldr     x22, [x21, #8]
    mov     x23, x20
1:  cbz     x23, 2f
    bl      shell_getc
    tbnz    x0, #63, 4f
    strb    w0, [x22], #1
    sub     x23, x23, #1
    b       1b
2:  str     x20, [x21, #16]
    mov     x0, x21
    bl      finalize_file
    mov     x0, #0
    b       5f
4:  mov     x0, #-1
5:  ldp     x23, x30, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp, #0]
    add     sp, sp, #64
    ret

/* x0=source, x1=source bytes, x2=output; return output bytes. */
hex0_compile_memory:
    mov     x9, x0
    add     x10, x0, x1
    mov     x11, x2
    mov     x12, #0               /* have high nibble */
    mov     x13, #0               /* high nibble */
    mov     x14, #0               /* in line comment */
1:  cmp     x9, x10
    b.hs    8f
    ldrb    w15, [x9], #1
    cbz     x14, 3f
    cmp     w15, #10
    b.ne    1b
    mov     x14, #0
    b       1b
3:  cmp     w15, #'#'
    b.eq    7f
    cmp     w15, #';'
    b.eq    7f
    cmp     w15, #'0'
    b.lo    1b
    cmp     w15, #('9' + 1)
    b.lo    4f
    cmp     w15, #'A'
    b.lo    1b
    cmp     w15, #('F' + 1)
    b.lo    5f
    cmp     w15, #'a'
    b.lo    1b
    cmp     w15, #('f' + 1)
    b.hs    1b
    sub     w15, w15, #('a' - 10)
    b       6f
4:  sub     w15, w15, #'0'
    b       6f
5:  sub     w15, w15, #('A' - 10)
6:  cbnz    x12, 9f
    lsl     w13, w15, #4
    mov     x12, #1
    b       1b
9:  orr     w13, w13, w15
    strb    w13, [x11], #1
    mov     x12, #0
    b       1b
7:  mov     x14, #1
    b       1b
8:  sub     x0, x11, x2
    ret

/* hex0 INPUT OUTPUT */
shell_hex0:
    sub     sp, sp, #32
    stp     x19, x20, [sp, #0]
    stp     x21, x30, [sp, #16]
    bl      next_token
    mov     x19, x1
    ldrb    w9, [x0]
    cbz     w9, 4f
    ldr     x1, =PATH_BUFFER
    bl      normalize_path
    cbz     x0, 4f
    bl      find_file
    cbz     x0, 4f
    mov     x20, x0
    mov     x0, x19
    bl      next_token
    ldrb    w9, [x0]
    cbz     w9, 4f
    ldr     x1, =PATH_BUFFER
    bl      normalize_path
    cbz     x0, 4f
    bl      create_file
    cbz     x0, 4f
    mov     x21, x0
    ldr     x0, [x20, #8]
    ldr     x1, [x20, #16]
    ldr     x9, [x21, #24]
    add     x10, x1, #1
    lsr     x10, x10, #1
    cmp     x10, x9               /* worst case: every source byte is hex */
    b.hi    4f
    ldr     x2, [x21, #8]
    bl      hex0_compile_memory
    ldr     x9, [x21, #24]
    cmp     x0, x9
    b.hi    4f
    str     x0, [x21, #16]
    mov     x0, x21
    bl      finalize_file
    mov     x0, #0
    b       5f
4:  mov     x0, #-1
5:  ldp     x21, x30, [sp, #16]
    ldp     x19, x20, [sp, #0]
    add     sp, sp, #32
    ret

/* Write the newest /dev/hda memory file over the block device. */
flush_disk:
    sub     sp, sp, #48
    stp     x19, x20, [sp, #0]
    stp     x21, x22, [sp, #16]
    str     x30, [sp, #32]
    adrp    x0, dev_hda_name
    add     x0, x0, :lo12:dev_hda_name
    bl      find_file
    cbz     x0, 5f
    ldr     x19, [x0, #8]
    ldr     x20, [x0, #16]
    mov     x0, x20
    bl      uart_puthex64
    mov     x0, #10
    bl      uart_putc
    mov     x21, #0
1:  cbz     x20, 4f
    ldr     x9, =SECTOR_BUFFER
    add     x10, x9, #512
2:  str     xzr, [x9], #8
    cmp     x9, x10
    b.lo    2b
    mov     x22, #512
    cmp     x20, x22
    csel    x22, x20, x22, lo
    mov     x9, x19
    ldr     x10, =SECTOR_BUFFER
    mov     x11, x22
6:  cbz     x11, 7f
    ldrb    w12, [x9], #1
    strb    w12, [x10], #1
    sub     x11, x11, #1
    b       6b
7:  mov     x0, x21
    ldr     x1, =SECTOR_BUFFER
    bl      write_sector
    add     x19, x19, x22
    sub     x20, x20, x22
    add     x21, x21, #1
    b       1b
4:  mov     x0, #0
    b       8f
5:  mov     x0, #-1
8:  ldr     x30, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp, #0]
    add     sp, sp, #48
    ret

shell_maybe_flush:
    str     x30, [sp, #-16]!
    ldr     x9, =SHELL_FLUSH_PENDING
    ldr     x10, [x9]
    cbz     x10, 1f
    str     xzr, [x9]
    bl      flush_disk
    b       2f
1:  mov     x0, #0
2:  ldr     x30, [sp], #16
    ret

/* x0=file record, x1=argv[0], x2=optional argv[1]. */
launch_shell_process:
    mov     x9, x1
    mov     x10, #0
0:  ldrb    w11, [x9], #1
    add     x10, x10, #1
    cbnz    w11, 0b
    cbz     x2, 4f
    mov     x9, x2
0:  ldrb    w11, [x9], #1
    add     x10, x10, #1
    cbnz    w11, 0b
4:  cmp     x10, #0xc00
    b.hi    launch_shell_too_big

    ldr     x9, =SHELL_RESUME_SP
    mov     x10, sp
    str     x10, [x9]
    ldr     x9, =SHELL_RESUME_X30
    str     x30, [x9]
    ldr     x9, =SHELL_COMMAND_PTR
    str     x1, [x9]
    ldr     x9, =SHELL_ARGUMENT_PTR
    str     x2, [x9]
    ldr     x1, [x0, #16]
    ldr     x0, [x0, #8]
    bl      load_elf
    ldr     x9, =USER_ENTRY_SLOT
    str     x0, [x9]

    ldr     x9, =(USER_STACK_PHYS + USER_STACK_SIZE - 4096)
    mov     x10, #1
    ldr     x11, =SHELL_ARGUMENT_PTR
    ldr     x11, [x11]
    cbz     x11, 1f
    ldrb    w12, [x11]
    cbz     w12, 1f
    mov     x10, #2
1:  str     x10, [x9]
    ldr     x10, =(USER_STACK_TOP - 4096 + 0x400)
    str     x10, [x9, #8]
    ldr     x0, =SHELL_COMMAND_PTR
    ldr     x0, [x0]
    add     x1, x9, #0x400
    bl      copy_string
    mov     x10, x1
    ldr     x11, =SHELL_ARGUMENT_PTR
    ldr     x11, [x11]
    cbz     x11, 2f
    ldrb    w12, [x11]
    cbz     w12, 2f
    ldr     x9, =(USER_STACK_PHYS + USER_STACK_SIZE - 4096)
    ldr     x12, =USER_PHYS_OFFSET
    sub     x12, x10, x12
    str     x12, [x9, #16]
    mov     x0, x11
    mov     x1, x10
    bl      copy_string
    ldr     x9, =(USER_STACK_PHYS + USER_STACK_SIZE - 4096)
    str     xzr, [x9, #24]
    str     xzr, [x9, #32]
    b       3f
2:  ldr     x9, =(USER_STACK_PHYS + USER_STACK_SIZE - 4096)
    str     xzr, [x9, #16]
    str     xzr, [x9, #24]
3:  ldr     x9, =SHELL_PROCESS_ACTIVE
    mov     x10, #1
    str     x10, [x9]
    ldr     x9, =(USER_STACK_TOP - 4096)
    msr     sp_el0, x9
    ldr     x9, =USER_ENTRY_SLOT
    ldr     x9, [x9]
    msr     elr_el1, x9
    mov     x9, #0x3c0
    msr     spsr_el1, x9
    eret

launch_shell_too_big:
    mov     x0, #-7               /* -E2BIG */
    ret

internal_shell:
    sub     sp, sp, #64
    stp     x19, x20, [sp, #0]
    stp     x21, x30, [sp, #16]
1:  bl      shell_getline
    cmp     x0, #-1
    b.eq    shell_finish
    tbnz    x0, #63, shell_error
    bl      next_token
    mov     x19, x0
    mov     x20, x1
    ldrb    w9, [x19]
    cbz     w9, 1b

    mov     x0, x19
    adrp    x1, command_src
    add     x1, x1, :lo12:command_src
    bl      strings_equal
    cbnz    x0, shell_handle_src
    mov     x0, x19
    adrp    x1, command_hex0
    add     x1, x1, :lo12:command_hex0
    bl      strings_equal
    cbnz    x0, shell_handle_hex0
    mov     x0, x19
    adrp    x1, command_flush
    add     x1, x1, :lo12:command_flush
    bl      strings_equal
    cbnz    x0, shell_handle_flush
    mov     x0, x19
    adrp    x1, command_halt
    add     x1, x1, :lo12:command_halt
    bl      strings_equal
    cbnz    x0, shell_finish

    bl      shell_maybe_flush
    cbnz    x0, shell_error
    mov     x0, x19
    ldr     x1, =PATH_BUFFER
    bl      normalize_path
    cbz     x0, shell_error
    bl      find_file
    cbz     x0, shell_error
    mov     x21, x0
    mov     x0, x20
    bl      next_token
    mov     x2, x0
    mov     x1, x19
    mov     x0, x21
    bl      launch_shell_process
    cbnz    x0, shell_error
    b       1b

shell_handle_src:
    mov     x0, x20
    bl      shell_src
    cbnz    x0, shell_error
    b       1b

shell_handle_hex0:
    mov     x0, x20
    bl      shell_hex0
    cbnz    x0, shell_error
    b       1b

shell_handle_flush:
    ldr     x9, =SHELL_FLUSH_PENDING
    mov     x10, #1
    str     x10, [x9]
    b       1b

shell_finish:
    bl      flush_disk
    cbnz    x0, shell_error
    adrp    x0, shell_success_message
    add     x0, x0, :lo12:shell_success_message
    bl      uart_puts
    mov     x0, #0
    b       shell_return

shell_error:
    adrp    x0, shell_failure_message
    add     x0, x0, :lo12:shell_failure_message
    bl      uart_puts
    mov     x0, #1

shell_return:
    ldp     x21, x30, [sp, #16]
    ldp     x19, x20, [sp, #0]
    add     sp, sp, #64
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
    b.eq    1f
    ldr     x11, =SHELL_HEADER_MAGIC
    cmp     x10, x11
    b.ne    3f
    ldr     x10, [x9, #8]
    ldr     x11, =SHELL_LBA_SLOT
    str     x10, [x11]
    ldr     x10, [x9, #16]
    ldr     x11, =SHELL_REMAINING_SLOT
    str     x10, [x11]
    ldr     x11, =SHELL_SECTOR_POS
    mov     x10, #512
    str     x10, [x11]
    ldr     x11, =SHELL_FLUSH_PENDING
    str     xzr, [x11]
    str     xzr, [x11, #8]
    bl      init_empty_filesystem
    bl      internal_shell
    cbnz    x0, trap_failure
    b       poweroff
1:
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
    b       virtio_sector

write_sector:
    mov     x2, #1

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
    mov     w10, #1               /* NEXT */
    cbnz    x2, 5f
    orr     w10, w10, #2          /* device writes on disk read */
5:
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
shell_failure_message:
    .asciz  "builder-hex0-arm64 shell failed\n"
shell_success_message:
    .asciz  "builder-hex0-arm64 shell and flush passed\n"
command_src:
    .asciz  "src"
command_hex0:
    .asciz  "hex0"
command_flush:
    .asciz  "f"
command_halt:
    .asciz  "halt"
dev_hda_name:
    .asciz  "/dev/hda"
input_name:
    .asciz  "/input"
exec_target_name:
    .asciz  "/exec-target"
input_data:
    .ascii  "builder memory file input\n"
input_data_end:

    .balign 8
builtin_exec_elf:
    .byte   0x7f, 0x45, 0x4c, 0x46, 2, 1, 1, 0
    .byte   0, 0, 0, 0, 0, 0, 0, 0
    .hword  2                      /* ET_EXEC */
    .hword  183                    /* EM_AARCH64 */
    .word   1
    .dword  USER_VIRT + (builtin_exec_entry - builtin_exec_elf)
    .dword  64                     /* e_phoff */
    .dword  0
    .word   0
    .hword  64
    .hword  56
    .hword  1
    .hword  0
    .hword  0
    .hword  0
    .word   1                      /* PT_LOAD */
    .word   7                      /* PF_R | PF_W | PF_X */
    .dword  0
    .dword  USER_VIRT
    .dword  USER_VIRT
    .dword  builtin_exec_elf_end - builtin_exec_elf
    .dword  builtin_exec_elf_end - builtin_exec_elf
    .dword  4096
builtin_exec_entry:
    ldr     x9, [sp]
    cmp     x9, #2
    b.ne    builtin_exec_bad
    ldr     x9, [sp, #8]
    ldrb    w9, [x9]
    cmp     w9, #47               /* '/' */
    b.ne    builtin_exec_bad
    ldr     x9, [sp, #16]
    ldrb    w9, [x9]
    cmp     w9, #99               /* 'c' */
    b.ne    builtin_exec_bad
    ldr     x9, [sp, #24]
    cbnz    x9, builtin_exec_bad
    mov     x0, #7
    b       builtin_exec_exit
builtin_exec_bad:
    mov     x0, #9
builtin_exec_exit:
    mov     x8, #93
    svc     #0
builtin_exec_elf_end:
