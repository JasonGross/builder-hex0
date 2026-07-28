/* SPDX-License-Identifier: MIT */

    .syntax unified
    .arch armv7-a
    .arm
    .section .text
    .globl _start

_start:
    ldr     r9, =0x08000000
    cmp     sp, r9
    bne     failure

    ldr     r9, =bss_probe
    ldrb    r10, [r9]
    cmp     r10, #0
    bne     failure
    ldr     r9, =bss_probe_end - 1
    ldrb    r10, [r9]
    cmp     r10, #0
    bne     failure

    mov     r0, #1
    ldr     r1, =entry_message
    ldr     r2, =entry_message_end
    sub     r2, r2, r1
    mov     r7, #4               /* write */
    svc     #0

    mov     r0, #0
    mov     r7, #45              /* brk */
    svc     #0
    ldr     r9, =image_break
    cmp     r0, r9
    bne     failure

    ldr     r0, =input_path
    mov     r1, #0               /* O_RDONLY */
    mov     r2, #0
    mov     r7, #5               /* open */
    svc     #0
    cmp     r0, #0
    blt     failure
    mov     r8, r0
    mov     r0, r8
    ldr     r1, =file_buffer
    mov     r2, #64
    mov     r7, #3               /* read */
    svc     #0
    ldr     r10, =input_expected_end
    ldr     r9, =input_expected
    sub     r10, r10, r9
    cmp     r0, r10
    bne     failure
    ldr     r0, =file_buffer
    ldr     r1, =input_expected
    mov     r2, r10
    bl      compare_bytes
    cmp     r0, #0
    bne     failure
    mov     r0, r8
    mov     r7, #6               /* close */
    svc     #0
    cmp     r0, #0
    bne     failure

    ldr     r0, =output_path
    ldr     r1, =0x242           /* O_RDWR | O_CREAT | O_TRUNC */
    mov     r2, #0
    mov     r7, #5
    svc     #0
    cmp     r0, #0
    blt     failure
    mov     r8, r0
    mov     r0, r8
    ldr     r1, =output_data
    ldr     r2, =output_data_end
    sub     r2, r2, r1
    mov     r10, r2
    mov     r7, #4
    svc     #0
    cmp     r0, r10
    bne     failure
    mov     r0, r8
    mov     r7, #6
    svc     #0
    cmp     r0, #0
    bne     failure

    ldr     r0, =output_path
    mov     r1, #0
    mov     r7, #33              /* access */
    svc     #0
    cmp     r0, #0
    bne     failure
    ldr     r0, =output_path
    mov     r7, #10              /* unlink */
    svc     #0
    cmp     r0, #0
    bne     failure
    ldr     r0, =output_path
    mov     r1, #0
    mov     r7, #33
    svc     #0
    mvn     r9, #1               /* -ENOENT */
    cmp     r0, r9
    bne     failure

    mov     r0, #1
    ldr     r1, =success_message
    ldr     r2, =success_message_end
    sub     r2, r2, r1
    mov     r7, #4
    svc     #0
    mov     r0, #0
    mov     r7, #1               /* exit */
    svc     #0

/* r0/r1 buffers, r2 bytes; returns zero when equal. */
compare_bytes:
1:  cmp     r2, #0
    beq     2f
    ldrb    r9, [r0], #1
    ldrb    r10, [r1], #1
    cmp     r9, r10
    bne     3f
    sub     r2, r2, #1
    b       1b
2:  mov     r0, #0
    bx      lr
3:  mov     r0, #1
    bx      lr

failure:
    mov     r0, #1
    mov     r7, #1
    svc     #0

entry_message:
    .ascii  "builder-hex0-arm64 entered AArch32 EL0\n"
entry_message_end:
success_message:
    .ascii  "builder-hex0-arm64 ELF32 and ARM EABI passed\n"
success_message_end:
input_path:
    .asciz  "/input"
output_path:
    .asciz  "/arm32-output"
input_expected:
    .ascii  "builder memory file input\n"
input_expected_end:
output_data:
    .ascii  "AArch32 memory file output\n"
output_data_end:

    .section .data
    .byte   0

    .section .bss
    .balign 4096
bss_probe:
    .skip   4096
file_buffer:
    .skip   64
bss_probe_end:
