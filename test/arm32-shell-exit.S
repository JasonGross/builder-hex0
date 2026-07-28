/* SPDX-License-Identifier: MIT */

    .syntax unified
    .arch armv7-a
    .arm
    .section .text
    .globl _start

_start:
    ldr     r0, [sp]
    cmp     r0, #2
    bne     failure
    ldr     r0, [sp, #4]
    ldr     r1, =expected_command
    bl      compare_string
    cmp     r0, #0
    bne     failure
    ldr     r0, [sp, #8]
    ldr     r1, =expected_argument
    bl      compare_string
    cmp     r0, #0
    bne     failure
    ldr     r0, [sp, #12]
    cmp     r0, #0
    bne     failure
    ldr     r0, [sp, #16]
    cmp     r0, #0
    bne     failure

    mov     r0, #1
    ldr     r1, =success_message
    ldr     r2, =success_message_end
    sub     r2, r2, r1
    mov     r7, #4
    svc     #0
    mov     r0, #0
    mov     r7, #1
    svc     #0

compare_string:
1:  ldrb    r2, [r0], #1
    ldrb    r3, [r1], #1
    cmp     r2, r3
    bne     2f
    cmp     r2, #0
    bne     1b
    mov     r0, #0
    bx      lr
2:  mov     r0, #1
    bx      lr

failure:
    mov     r0, #1
    mov     r7, #1
    svc     #0

expected_command:
    .asciz  "/arm32-exit"
expected_argument:
    .asciz  "pivot"
success_message:
    .ascii  "builder-hex0-arm64 AArch32 shell argv passed\n"
success_message_end:

    .section .data
    .byte   0
