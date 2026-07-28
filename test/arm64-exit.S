/* SPDX-License-Identifier: MIT */

    .arch armv8-a
    .section .text
    .globl _start

_start:
    mov     x0, #0
    mov     x8, #93
    svc     #0

    .section .data
    .byte   0
