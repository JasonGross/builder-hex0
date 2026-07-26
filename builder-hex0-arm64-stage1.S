/* SPDX-License-Identifier: MIT
 *
 * AArch64 stage-1 builder-hex0 for QEMU's virt machine.
 *
 * Disk sector zero contains four little-endian 64-bit words:
 *   magic, source_lba, source_bytes, output_lba
 * The source is compiled to raw bytes and written back at output_lba.
 */

    .arch armv8-a
    .section .text.boot
    .globl _start

    .equ UART0,             0x09000000
    .equ VIRTIO_FIRST,      0x0a000000
    .equ VIRTIO_END,        0x0a004000
    .equ VIRTQ_DESC,        0x41000000
    .equ VIRTQ_AVAIL,       0x41001000
    .equ VIRTQ_USED,        0x41002000
    .equ VIRTIO_HEADER,     0x41003000
    .equ VIRTIO_STATUS,     0x41003010
    .equ SECTOR_BUFFER,     0x41004000
    .equ SOURCE_BUFFER,     0x42000000
    .equ OUTPUT_BUFFER,     0x43000000
    .equ STACK_TOP,         0x47fff000

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
    movz    x9, #0x47ff, lsl #16
    movk    x9, #0xf000
    mov     sp, x9
    bl      uart_init
    adrp    x0, banner
    add     x0, x0, :lo12:banner
    bl      uart_puts
    bl      virtio_init

    mov     x0, #0
    movz    x1, #0x4100, lsl #16
    add     x1, x1, #4, lsl #12
    bl      read_sector
    movz    x9, #0x4100, lsl #16
    add     x9, x9, #4, lsl #12
    ldr     x10, [x9]
    movz    x11, #0x5842
    movk    x11, #0x4448, lsl #16
    movk    x11, #0x5652, lsl #32
    movk    x11, #0x3058, lsl #48
    cmp     x10, x11
    b.ne    bad_header
    ldr     x19, [x9, #8]         /* source LBA */
    ldr     x20, [x9, #16]        /* source byte count */
    ldr     x21, [x9, #24]        /* output LBA */

    mov     x0, x19
    mov     x1, x20
    movz    x2, #0x4200, lsl #16
    bl      read_bytes

    movz    x0, #0x4200, lsl #16
    mov     x1, x20
    movz    x2, #0x4300, lsl #16
    bl      hex0_compile
    mov     x22, x0

    mov     x0, x21
    mov     x1, x22
    movz    x2, #0x4300, lsl #16
    bl      write_bytes

    adrp    x0, success
    add     x0, x0, :lo12:success
    bl      uart_puts
    mov     x0, x22
    bl      uart_puthex64
    mov     x0, #10
    bl      uart_putc
    b       poweroff

bad_header:
    adrp    x0, bad_header_msg
    add     x0, x0, :lo12:bad_header_msg
    bl      uart_puts
    b       poweroff

/* PL011 UART ------------------------------------------------------------ */
uart_init:
    ret

uart_putc:
    movz    x9, #0x0900, lsl #16
1:  ldr     w10, [x9, #0x18]
    tst     w10, #0x20            /* TX FIFO full */
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

/* virtio-mmio block device, split queue -------------------------------- */
virtio_init:
    movz    x9, #0x0a00, lsl #16
    mov     x12, x9
    add     x12, x12, #4, lsl #12
    movz    w11, #0x6976
    movk    w11, #0x7472, lsl #16 /* "virt" */
0:  cmp     x9, x12
    b.hs    no_virtio
    ldr     w10, [x9]
    cmp     w10, w11
    b.ne    9f
    ldr     w10, [x9, #8]
    cmp     w10, #2
    b.eq    8f
9:  add     x9, x9, #0x200
    b       0b
8:  mov     x28, x9               /* block transport base */

    str     wzr, [x9, #0x70]
    mov     w10, #3               /* ACKNOWLEDGE | DRIVER */
    str     w10, [x9, #0x70]

    ldr     w10, [x9, #4]
    cmp     w10, #1
    b.eq    virtio_init_legacy
    cmp     w10, #2
    b.ne    no_virtio

    mov     w10, #1
    str     w10, [x9, #0x14]      /* device feature word 1 */
    ldr     w11, [x9, #0x10]
    and     w11, w11, #1          /* VIRTIO_F_VERSION_1 */
    cbz     w11, no_virtio
    str     w10, [x9, #0x24]      /* driver feature word 1 */
    str     w11, [x9, #0x20]

    mov     w10, #11              /* + FEATURES_OK */
    str     w10, [x9, #0x70]
    ldr     w11, [x9, #0x70]
    tst     w11, #8
    b.eq    no_virtio

    str     wzr, [x9, #0x30]      /* queue 0 */
    ldr     w11, [x9, #0x34]
    cbz     w11, no_virtio
    mov     w10, #8
    cmp     w11, w10
    csel    w11, w11, w10, lo
    str     w11, [x9, #0x38]
    movz    w10, #0x4100, lsl #16
    str     w10, [x9, #0x80]
    str     wzr, [x9, #0x84]
    add     w10, w10, #1, lsl #12
    str     w10, [x9, #0x90]
    str     wzr, [x9, #0x94]
    add     w10, w10, #1, lsl #12
    str     w10, [x9, #0xa0]
    str     wzr, [x9, #0xa4]
    mov     w10, #1
    str     w10, [x9, #0x44]
    mov     w10, #15              /* + DRIVER_OK */
    str     w10, [x9, #0x70]
    movz    x25, #0x4100, lsl #16
    mov     x26, x25
    add     x26, x26, #1, lsl #12
    mov     x27, x26
    add     x27, x27, #1, lsl #12
    ret

virtio_init_legacy:
    str     wzr, [x9, #0x24]      /* driver feature word 0 */
    str     wzr, [x9, #0x20]
    mov     w10, #1
    lsl     w10, w10, #12
    str     w10, [x9, #0x28]      /* guest page size */
    str     wzr, [x9, #0x30]
    ldr     w11, [x9, #0x34]
    cbz     w11, no_virtio
    mov     w10, #8
    cmp     w11, w10
    csel    w11, w11, w10, lo
    str     w11, [x9, #0x38]
    mov     w10, #1
    lsl     w10, w10, #12
    str     w10, [x9, #0x3c]
    movz    w10, #0x1000
    movk    w10, #0x4, lsl #16
    str     w10, [x9, #0x40]      /* 0x41000000 >> 12 */
    mov     w10, #7
    str     w10, [x9, #0x70]
    movz    x25, #0x4100, lsl #16
    add     x26, x25, #128
    mov     x27, x25
    add     x27, x27, #1, lsl #12
    ret

no_virtio:
    adrp    x0, no_virtio_msg
    add     x0, x0, :lo12:no_virtio_msg
    bl      uart_puts
    b       poweroff

/* x0=sector, x1=buffer */
read_sector:
    mov     x2, #0
    b       virtio_sector

/* x0=sector, x1=buffer */
write_sector:
    mov     x2, #1

virtio_sector:
    movz    x9, #0x4100, lsl #16
    add     x9, x9, #3, lsl #12
    str     w2, [x9]
    str     wzr, [x9, #4]
    str     x0, [x9, #8]
    add     x10, x9, #16
    mov     w11, #0xff
    strb    w11, [x10]

    mov     x9, x25
    movz    x10, #0x4100, lsl #16
    add     x10, x10, #3, lsl #12
    str     x10, [x9]
    mov     w10, #16
    str     w10, [x9, #8]
    mov     w10, #1               /* NEXT */
    strh    w10, [x9, #12]
    mov     w10, #1
    strh    w10, [x9, #14]

    str     x1, [x9, #16]
    mov     w10, #512
    str     w10, [x9, #24]
    mov     w10, #1               /* NEXT */
    cbnz    x2, 1f
    orr     w10, w10, #2          /* WRITE for disk read */
1:  strh    w10, [x9, #28]
    mov     w10, #2
    strh    w10, [x9, #30]

    movz    x10, #0x4100, lsl #16
    add     x10, x10, #3, lsl #12
    add     x10, x10, #16
    str     x10, [x9, #32]
    mov     w10, #1
    str     w10, [x9, #40]
    mov     w10, #2
    strh    w10, [x9, #44]
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
2:  dmb     ish
    ldrh    w11, [x27, #2]
    cmp     w10, w11
    b.eq    2b
    movz    x9, #0x4100, lsl #16
    add     x9, x9, #3, lsl #12
    add     x9, x9, #16
    ldrb    w10, [x9]
    cbnz    w10, disk_error
    ret

disk_error:
    adrp    x0, disk_error_msg
    add     x0, x0, :lo12:disk_error_msg
    bl      uart_puts
    b       poweroff

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

/* x0=start sector, x1=byte count, x2=source */
write_bytes:
    stp     x19, x20, [sp, #-32]!
    stp     x21, x30, [sp, #16]
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
1:  cbz     x20, 2f
    mov     x0, x19
    mov     x1, x21
    bl      write_sector
    add     x19, x19, #1
    add     x21, x21, #512
    subs    x20, x20, #512
    b.gt    1b
2:  ldp     x21, x30, [sp, #16]
    ldp     x19, x20, [sp], #32
    ret

/* hex0 compiler --------------------------------------------------------- */
/* x0=source, x1=source bytes, x2=output; returns output bytes in x0 */
hex0_compile:
    mov     x3, x0                 /* input */
    add     x4, x0, x1            /* input end */
    mov     x5, x2                 /* output */
    mov     x6, #0                 /* have high nibble */
    mov     x7, #0                 /* high nibble */
    mov     x8, #0                 /* in comment */
1:  cmp     x3, x4
    b.hs    8f
    ldrb    w9, [x3], #1
    cbz     x8, 3f
    cmp     w9, #10
    b.ne    1b
    mov     x8, #0
    b       1b
3:  cmp     w9, #35               /* # */
    b.eq    7f
    cmp     w9, #59               /* ; */
    b.eq    7f
    cmp     w9, #48
    b.lo    1b
    cmp     w9, #58
    b.lo    4f
    cmp     w9, #65
    b.lo    1b
    cmp     w9, #71
    b.lo    5f
    cmp     w9, #97
    b.lo    1b
    cmp     w9, #103
    b.hs    1b
    sub     w9, w9, #87           /* a..f */
    b       6f
4:  sub     w9, w9, #48           /* 0..9 */
    b       6f
5:  sub     w9, w9, #55           /* A..F */
6:  cbnz    x6, 9f
    lsl     w7, w9, #4
    mov     x6, #1
    b       1b
9:  orr     w7, w7, w9
    strb    w7, [x5], #1
    mov     x6, #0
    b       1b
7:  mov     x8, #1
    b       1b
8:  sub     x0, x5, x2
    ret

poweroff:
    mov     w0, #8
    movk    w0, #0x8400, lsl #16  /* PSCI SYSTEM_OFF */
    hvc     #0
1:  wfe
    b       1b

    .section .rodata
banner:          .asciz "builder-hex0-arm64 stage1\n"
success:         .asciz "compiled bytes: 0x"
bad_header_msg:  .asciz "bad builder disk header\n"
no_virtio_msg:   .asciz "virtio block device unavailable\n"
disk_error_msg:  .asciz "virtio block request failed\n"
