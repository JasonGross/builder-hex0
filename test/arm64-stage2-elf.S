/* SPDX-License-Identifier: MIT */

    .arch armv8-a
    .section .text
    .globl _start

_start:
    /* The loader must clear the complete file-backed BSS segment. */
    adrp    x19, bss_probe
    add     x19, x19, :lo12:bss_probe
    ldrb    w9, [x19]
    cbnz    w9, failure
    adrp    x19, bss_probe_end
    add     x19, x19, :lo12:bss_probe_end
    sub     x19, x19, #1
    ldrb    w9, [x19]
    cbnz    w9, failure
    mov     x0, #1
    adr     x1, bss_message
    adr     x2, bss_message_end
    sub     x2, x2, x1
    mov     x8, #64
    svc     #0

    /* Raw Linux brk returns the current break when called with zero. */
    mov     x0, #0
    mov     x8, #214
    svc     #0
    mov     x19, x0
    ldr     x20, =bss_probe_end
    cmp     x19, x20
    b.ne    failure
    mov     x0, #1
    adr     x1, brk_query_message
    adr     x2, brk_query_message_end
    sub     x2, x2, x1
    mov     x8, #64
    svc     #0

    /* Grow across a 2 MiB block boundary to cover every initial user map. */
    ldr     x21, =0x00803000
    mov     x0, x21
    mov     x8, #214
    svc     #0
    cmp     x0, x21
    b.ne    failure
    ldr     x19, =0x00800000
    ldrb    w9, [x19]
    cbnz    w9, failure

    mov     x0, #1
    adr     x1, success_message
    adr     x2, success_message_end
    sub     x2, x2, x1
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0

failure:
    mov     x0, #1
    mov     x8, #93
    svc     #0

success_message:
    .ascii  "builder-hex0-arm64 disk ELF64 and brk passed\n"
success_message_end:
bss_message:
    .ascii  "builder-hex0-arm64 disk ELF64 BSS passed\n"
bss_message_end:
brk_query_message:
    .ascii  "builder-hex0-arm64 disk ELF64 brk query passed\n"
brk_query_message_end:

    .section .bss
    .balign 4096
bss_probe:
    .skip   4096
bss_probe_end:
