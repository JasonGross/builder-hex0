/* SPDX-License-Identifier: MIT
 *
 * RISC-V 64 stage-1 builder-hex0 prototype for QEMU's virt machine.
 * Uses RV64I only.  The final bootstrap source is emitted as commented hex0;
 * this assembly file is the executable specification used during bring-up.
 *
 * Disk sector zero contains four little-endian 64-bit words:
 *   magic, source_lba, source_bytes, output_lba
 * The source is compiled to raw bytes and written back at output_lba.
 */

    .option norvc
    .section .text.boot
    .globl _start

    .equ UART0,             0x10000000
    .equ TEST_FINISHER,     0x00100000
    .equ VIRTIO_FIRST,      0x10001000
    .equ VIRTIO_END,        0x10009000
    .equ VIRTQ_DESC,        0x81000000
    .equ VIRTQ_AVAIL,       0x81001000
    .equ VIRTQ_USED,        0x81002000
    .equ VIRTIO_HEADER,     0x81003000
    .equ VIRTIO_STATUS,     0x81003010
    .equ SECTOR_BUFFER,     0x81004000
    .equ SOURCE_BUFFER,     0x82000000
    .equ OUTPUT_BUFFER,     0x83000000
    .equ STACK_TOP,         0x87fff000
    .equ HEADER_MAGIC,      0x3058565244485842

_start:
    li      sp, STACK_TOP
    call    uart_init
    la      a0, banner
    call    uart_puts
    call    virtio_init

    li      a0, 0
    li      a1, SECTOR_BUFFER
    call    read_sector
    li      t0, SECTOR_BUFFER
    ld      t1, 0(t0)
    li      t2, HEADER_MAGIC
    bne     t1, t2, bad_header
    ld      s0, 8(t0)              /* source LBA */
    ld      s1, 16(t0)             /* source byte count */
    ld      s2, 24(t0)             /* output LBA */

    mv      a0, s0
    mv      a1, s1
    li      a2, SOURCE_BUFFER
    call    read_bytes

    li      a0, SOURCE_BUFFER
    mv      a1, s1
    li      a2, OUTPUT_BUFFER
    call    hex0_compile
    mv      s3, a0                  /* output byte count */

    mv      a0, s2
    mv      a1, s3
    li      a2, OUTPUT_BUFFER
    call    write_bytes

    la      a0, success
    call    uart_puts
    mv      a0, s3
    call    uart_puthex64
    li      a0, 10
    call    uart_putc
    j       poweroff

bad_header:
    la      a0, bad_header_msg
    call    uart_puts
    li      a0, 1
    j       poweroff_code

/* 16550 UART ------------------------------------------------------------- */
uart_init:
    li      t0, UART0
    li      t1, 3
    sb      t1, 3(t0)              /* 8n1 */
    ret

uart_putc:
    li      t0, UART0
1:  lbu     t1, 5(t0)
    andi    t1, t1, 0x20
    beqz    t1, 1b
    sb      a0, 0(t0)
    ret

uart_puts:
    addi    sp, sp, -16
    sd      ra, 8(sp)
    sd      s0, 0(sp)
    mv      s0, a0
1:  lbu     a0, 0(s0)
    beqz    a0, 2f
    call    uart_putc
    addi    s0, s0, 1
    j       1b
2:  ld      s0, 0(sp)
    ld      ra, 8(sp)
    addi    sp, sp, 16
    ret

uart_puthex64:
    addi    sp, sp, -32
    sd      ra, 24(sp)
    sd      s0, 16(sp)
    sd      s1, 8(sp)
    mv      s0, a0
    li      s1, 60
1:  srl     t0, s0, s1
    andi    t0, t0, 15
    li      t1, 10
    bltu    t0, t1, 2f
    addi    a0, t0, 55
    j       3f
2:  addi    a0, t0, 48
3:  call    uart_putc
    addi    s1, s1, -4
    bgez    s1, 1b
    ld      s1, 8(sp)
    ld      s0, 16(sp)
    ld      ra, 24(sp)
    addi    sp, sp, 32
    ret

/* virtio-mmio block device, split queue --------------------------------- */
virtio_init:
    li      t0, VIRTIO_FIRST
    li      t3, VIRTIO_END
0:  bgeu    t0, t3, no_virtio
    lw      t1, 0(t0)
    li      t2, 0x74726976
    bne     t1, t2, 9f
    lw      t1, 8(t0)
    li      t2, 2
    beq     t1, t2, 8f
9:  li      t4, 0x1000
    add     t0, t0, t4
    j       0b
8:  mv      s11, t0                 /* block transport base */

    sw      zero, 0x70(t0)
    li      t1, 3                  /* ACKNOWLEDGE | DRIVER */
    sw      t1, 0x70(t0)

    lw      t1, 4(t0)
    li      t2, 1
    beq     t1, t2, virtio_init_legacy
    li      t2, 2
    bne     t1, t2, no_virtio

    li      t1, 1
    sw      t1, 0x14(t0)           /* device feature word 1 */
    lw      t2, 0x10(t0)
    andi    t2, t2, 1              /* VIRTIO_F_VERSION_1 */
    beqz    t2, no_virtio
    sw      t1, 0x24(t0)           /* driver feature word 1 */
    sw      t2, 0x20(t0)

    li      t1, 11                 /* + FEATURES_OK */
    sw      t1, 0x70(t0)
    lw      t2, 0x70(t0)
    andi    t2, t2, 8
    beqz    t2, no_virtio

    sw      zero, 0x30(t0)         /* queue 0 */
    lw      t2, 0x34(t0)
    beqz    t2, no_virtio
    li      t1, 8
    bgeu    t1, t2, 1f
    mv      t2, t1
1:  sw      t2, 0x38(t0)
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
    li      t1, 15                 /* + DRIVER_OK */
    sw      t1, 0x70(t0)
    li      s8, VIRTQ_DESC
    li      s9, VIRTQ_AVAIL
    li      s10, VIRTQ_USED
    ret

virtio_init_legacy:
    /* Legacy virtio-mmio uses one contiguous, page-aligned queue. */
    sw      zero, 0x24(t0)         /* driver feature word 0 */
    sw      zero, 0x20(t0)         /* accept no optional features */
    li      t1, 4096
    sw      t1, 0x28(t0)           /* guest page size */
    sw      zero, 0x30(t0)         /* queue 0 */
    lw      t2, 0x34(t0)
    beqz    t2, no_virtio
    li      t1, 8
    bgeu    t1, t2, 1f
    mv      t2, t1
1:  sw      t2, 0x38(t0)
    li      t1, 4096
    sw      t1, 0x3c(t0)           /* used-ring alignment */
    li      t1, VIRTQ_DESC
    srli    t1, t1, 12
    sw      t1, 0x40(t0)           /* queue page frame */
    li      t1, 7                  /* + DRIVER_OK (no FEATURES_OK) */
    sw      t1, 0x70(t0)
    li      s8, VIRTQ_DESC
    li      s9, VIRTQ_DESC + 128   /* 8 descriptors */
    li      s10, VIRTQ_DESC + 4096 /* page-aligned used ring */
    ret

no_virtio:
    la      a0, no_virtio_msg
    call    uart_puts
    li      a0, 2
    j       poweroff_code

/* a0=sector, a1=buffer */
read_sector:
    li      a2, 0                  /* VIRTIO_BLK_T_IN */
    j       virtio_sector

/* a0=sector, a1=buffer */
write_sector:
    li      a2, 1                  /* VIRTIO_BLK_T_OUT */

virtio_sector:
    li      t0, VIRTIO_HEADER
    sw      a2, 0(t0)
    sw      zero, 4(t0)
    sd      a0, 8(t0)
    li      t1, VIRTIO_STATUS
    li      t2, 0xff
    sb      t2, 0(t1)

    mv      t0, s8
    li      t1, VIRTIO_HEADER
    sd      t1, 0(t0)
    li      t1, 16
    sw      t1, 8(t0)
    li      t1, 1                  /* NEXT */
    sh      t1, 12(t0)
    li      t1, 1
    sh      t1, 14(t0)

    sd      a1, 16(t0)
    li      t1, 512
    sw      t1, 24(t0)
    li      t1, 1                  /* NEXT; add WRITE for disk read */
    bnez    a2, 1f
    ori     t1, t1, 2
1:  sh      t1, 28(t0)
    li      t1, 2
    sh      t1, 30(t0)

    li      t1, VIRTIO_STATUS
    sd      t1, 32(t0)
    li      t1, 1
    sw      t1, 40(t0)
    li      t1, 2                  /* WRITE */
    sh      t1, 44(t0)
    sh      zero, 46(t0)

    mv      t0, s9
    lhu     t1, 2(t0)
    andi    t2, t1, 7
    slli    t2, t2, 1
    addi    t2, t2, 4
    add     t2, t2, t0
    sh      zero, 0(t2)            /* descriptor chain starts at 0 */
    addi    t1, t1, 1
    fence   w, w
    sh      t1, 2(t0)
    fence   rw, rw

    mv      t0, s10
    lhu     t1, 2(t0)
    mv      t2, s11
    sw      zero, 0x50(t2)
1:  fence   r, r
    lhu     t2, 2(t0)
    beq     t1, t2, 1b
    li      t0, VIRTIO_STATUS
    lbu     t1, 0(t0)
    bnez    t1, disk_error
    ret

disk_error:
    la      a0, disk_error_msg
    call    uart_puts
    li      a0, 3
    j       poweroff_code

/* a0=start sector, a1=byte count, a2=destination */
read_bytes:
    addi    sp, sp, -48
    sd      ra, 40(sp)
    sd      s0, 32(sp)
    sd      s1, 24(sp)
    sd      s2, 16(sp)
    mv      s0, a0
    mv      s1, a1
    mv      s2, a2
1:  beqz    s1, 2f
    mv      a0, s0
    mv      a1, s2
    call    read_sector
    addi    s0, s0, 1
    addi    s2, s2, 512
    addi    s1, s1, -512
    bgtz    s1, 1b
2:  ld      s2, 16(sp)
    ld      s1, 24(sp)
    ld      s0, 32(sp)
    ld      ra, 40(sp)
    addi    sp, sp, 48
    ret

/* a0=start sector, a1=byte count, a2=source */
write_bytes:
    addi    sp, sp, -48
    sd      ra, 40(sp)
    sd      s0, 32(sp)
    sd      s1, 24(sp)
    sd      s2, 16(sp)
    mv      s0, a0
    mv      s1, a1
    mv      s2, a2
1:  beqz    s1, 2f
    mv      a0, s0
    mv      a1, s2
    call    write_sector
    addi    s0, s0, 1
    addi    s2, s2, 512
    addi    s1, s1, -512
    bgtz    s1, 1b
2:  ld      s2, 16(sp)
    ld      s1, 24(sp)
    ld      s0, 32(sp)
    ld      ra, 40(sp)
    addi    sp, sp, 48
    ret

/* hex0 compiler --------------------------------------------------------- */
/* a0=source, a1=source bytes, a2=output; returns output bytes in a0 */
hex0_compile:
    mv      t0, a0                  /* input */
    add     t1, a0, a1             /* input end */
    mv      t2, a2                  /* output */
    li      t3, 0                   /* have high nibble */
    li      t4, 0                   /* high nibble */
    li      t5, 0                   /* in comment */
1:  bgeu    t0, t1, 8f
    lbu     a3, 0(t0)
    addi    t0, t0, 1
    beqz    t5, 3f
    li      a4, 10
    bne     a3, a4, 1b
    li      t5, 0
    j       1b
3:  li      a4, 35                 /* # */
    beq     a3, a4, 7f
    li      a4, 59                 /* ; */
    beq     a3, a4, 7f
    li      a4, 48
    bltu    a3, a4, 1b
    li      a5, 58
    bltu    a3, a5, 4f
    li      a4, 65
    bltu    a3, a4, 1b
    li      a5, 71
    bltu    a3, a5, 5f
    li      a4, 97
    bltu    a3, a4, 1b
    li      a5, 103
    bgeu    a3, a5, 1b
    addi    a3, a3, -87            /* a..f */
    j       6f
4:  addi    a3, a3, -48            /* 0..9 */
    j       6f
5:  addi    a3, a3, -55            /* A..F */
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

poweroff:
    li      t0, TEST_FINISHER
    li      t1, 0x5555
    sw      t1, 0(t0)
1:  wfi
    j       1b
poweroff_code:
    li      t0, TEST_FINISHER
    slli    a0, a0, 16
    li      t1, 0x3333
    or      a0, a0, t1
    sw      a0, 0(t0)
2:  wfi
    j       2b

    .section .rodata
banner:          .asciz "builder-hex0-riscv64 stage1\n"
success:         .asciz "compiled bytes: 0x"
bad_header_msg:  .asciz "bad builder disk header\n"
no_virtio_msg:   .asciz "virtio block device unavailable\n"
disk_error_msg:  .asciz "virtio block request failed\n"
