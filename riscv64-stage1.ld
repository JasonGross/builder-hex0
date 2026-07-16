OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text : { *(.text.boot) *(.text*) }
  .rodata : { *(.rodata*) }
  /DISCARD/ : { *(.comment) *(.note*) *(.riscv.attributes) }
}
