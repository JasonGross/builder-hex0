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
    ldr     x20, =image_break
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

    /* Read the seeded file through the Linux AArch64 descriptor ABI. */
    mov     x0, #-100             /* AT_FDCWD */
    adr     x1, normalized_input_path
    mov     x2, #0               /* O_RDONLY */
    mov     x3, #0
    mov     x8, #56              /* openat */
    svc     #0
    tbnz    x0, #63, failure
    mov     x22, x0
    adrp    x1, file_buffer
    add     x1, x1, :lo12:file_buffer
    mov     x2, #64
    mov     x8, #63              /* read */
    svc     #0
    adr     x1, input_expected
    adr     x2, input_expected_end
    sub     x2, x2, x1
    cmp     x0, x2
    b.ne    failure
    adrp    x0, file_buffer
    add     x0, x0, :lo12:file_buffer
    bl      compare_bytes
    cbnz    x0, failure
    mov     x0, x22
    mov     x8, #57              /* close */
    svc     #0
    cbnz    x0, failure

    /* Create, write, rewind, and read a second memory file. */
    mov     x0, #-100
    adr     x1, output_path
    mov     x2, #0x242           /* O_RDWR | O_CREAT | O_TRUNC */
    mov     x3, #0
    mov     x8, #56
    svc     #0
    tbnz    x0, #63, failure
    mov     x22, x0
    mov     x0, x22
    adr     x1, output_data
    adr     x2, output_data_end
    sub     x2, x2, x1
    mov     x23, x2
    mov     x8, #64
    svc     #0
    cmp     x0, x23
    b.ne    failure
    mov     x0, x22
    mov     x1, #0
    mov     x2, #0               /* SEEK_SET */
    mov     x8, #62              /* lseek */
    svc     #0
    cbnz    x0, failure
    mov     x0, x22
    adrp    x1, file_buffer
    add     x1, x1, :lo12:file_buffer
    mov     x2, #64
    mov     x8, #63
    svc     #0
    cmp     x0, x23
    b.ne    failure
    adrp    x0, file_buffer
    add     x0, x0, :lo12:file_buffer
    adr     x1, output_data
    mov     x2, x23
    bl      compare_bytes
    cbnz    x0, failure
    mov     x0, x22
    mov     x8, #57
    svc     #0
    cbnz    x0, failure

    /*
     * Canonicalize a virtual working directory, then create, inspect, chmod,
     * and unlink a relative file. The final lookup also proves deleted file
     * records are skipped safely.
     */
    adr     x0, chdir_path
    mov     x8, #49              /* chdir */
    svc     #0
    cbnz    x0, failure
    mov     x0, #-100
    adr     x1, create_path
    mov     x2, #0x242           /* O_RDWR | O_CREAT | O_TRUNC */
    mov     x3, #0
    mov     x8, #56
    svc     #0
    tbnz    x0, #63, failure
    mov     x22, x0
    mov     x0, x22
    mov     x8, #57
    svc     #0
    cbnz    x0, failure
    mov     x0, #-100
    adr     x1, relative_path
    mov     x2, #0
    mov     x3, #0
    mov     x8, #48              /* faccessat */
    svc     #0
    cbnz    x0, failure
    mov     x0, #-100
    adr     x1, relative_path
    mov     x2, #0x180           /* 0600 */
    mov     x3, #0
    mov     x8, #53              /* fchmodat */
    svc     #0
    cbnz    x0, failure
    mov     x0, #-100
    adr     x1, relative_path
    mov     x2, #0
    mov     x8, #35              /* unlinkat */
    svc     #0
    cbnz    x0, failure
    mov     x0, #-100
    adr     x1, relative_path
    mov     x2, #0
    mov     x3, #0
    mov     x8, #48
    svc     #0
    mov     x9, #-2              /* -ENOENT */
    cmp     x0, x9
    b.ne    failure
    mov     x0, #-100
    adr     x1, long_path
    mov     x2, #0
    mov     x3, #0
    mov     x8, #48
    svc     #0
    mov     x9, #-36             /* -ENAMETOOLONG */
    cmp     x0, x9
    b.ne    failure

    mov     x0, #1
    adr     x1, path_message
    adr     x2, path_message_end
    sub     x2, x2, x1
    mov     x8, #64
    svc     #0

    adr     x0, invalid_exec_path
    mov     x1, #0
    mov     x2, #0
    mov     x8, #221             /* execve */
    svc     #0
    mov     x9, #-8              /* -ENOEXEC */
    cmp     x0, x9
    b.ne    failure

    /*
     * The child runs synchronously while the parent image is snapshotted.
     * execve replaces it with the embedded ELF, whose status proves argc and
     * argv survived the image replacement.
     */
    mov     x0, #17              /* SIGCHLD */
    mov     x1, #0
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    mov     x8, #220             /* clone */
    svc     #0
    cbz     x0, clone_child
    cmp     x0, #1
    b.ne    failure
    mov     x0, #1
    adrp    x1, child_status
    add     x1, x1, :lo12:child_status
    mov     x2, #0
    mov     x3, #0
    mov     x8, #260             /* wait4 */
    svc     #0
    cmp     x0, #1
    b.ne    failure
    adrp    x9, child_status
    add     x9, x9, :lo12:child_status
    ldr     w10, [x9]
    mov     w9, #0x700
    cmp     w10, w9
    b.ne    failure

    mov     x0, #1
    adr     x1, process_message
    adr     x2, process_message_end
    sub     x2, x2, x1
    mov     x8, #64
    svc     #0

    mov     x0, #1
    adr     x1, success_message
    adr     x2, success_message_end
    sub     x2, x2, x1
    mov     x8, #64
    svc     #0
    mov     x0, #0
    mov     x8, #93
    svc     #0

clone_child:
    sub     sp, sp, #32
    adr     x9, exec_path
    str     x9, [sp]
    adr     x9, child_argument
    str     x9, [sp, #8]
    str     xzr, [sp, #16]
    adr     x0, exec_path
    mov     x1, sp
    mov     x2, #0
    mov     x8, #221             /* execve */
    svc     #0
    b       failure

/* x0/x1 buffers, x2 bytes; returns zero when equal. */
compare_bytes:
1:  cbz     x2, 2f
    ldrb    w9, [x0], #1
    ldrb    w10, [x1], #1
    cmp     w9, w10
    b.ne    3f
    sub     x2, x2, #1
    b       1b
2:  mov     x0, #0
    ret
3:  mov     x0, #1
    ret

failure:
    mov     x0, #1
    mov     x8, #93
    svc     #0

success_message:
    .ascii  "builder-hex0-arm64 disk ELF64, files, and brk passed\n"
success_message_end:
bss_message:
    .ascii  "builder-hex0-arm64 disk ELF64 BSS passed\n"
bss_message_end:
brk_query_message:
    .ascii  "builder-hex0-arm64 disk ELF64 brk query passed\n"
brk_query_message_end:
normalized_input_path:
    .asciz  "///tmp/.././input"
output_path:
    .asciz  "/output"
chdir_path:
    .asciz  "/tmp/a/../work"
create_path:
    .asciz  "../work/./file"
relative_path:
    .asciz  "./file"
exec_path:
    .asciz  "/exec-target"
invalid_exec_path:
    .asciz  "/input"
child_argument:
    .asciz  "child"
long_path:
    .ascii  "/"
    .rept   127
    .ascii  "a"
    .endr
    .byte   0
input_expected:
    .ascii  "builder memory file input\n"
input_expected_end:
output_data:
    .ascii  "builder memory file roundtrip\n"
output_data_end:
path_message:
    .ascii  "builder-hex0-arm64 path syscalls passed\n"
path_message_end:
process_message:
    .ascii  "builder-hex0-arm64 process syscalls passed\n"
process_message_end:

    .section .bss
    .balign 4096
bss_probe:
    .skip   4096
child_status:
    .skip   4
file_buffer:
    .skip   64
bss_probe_end:
