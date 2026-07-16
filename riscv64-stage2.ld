OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  /* One load section makes every alignment byte visible in the hex0 source. */
  .text : { *(.text.boot) *(.text*) *(.rodata*) *(.data*) }
  /DISCARD/ : { *(.comment) *(.note*) *(.riscv.attributes) }
}
