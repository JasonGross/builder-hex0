#!/bin/sh
set -eu

OBJDUMP=${OBJDUMP:-riscv64-linux-gnu-objdump}
ELF=${1:-BUILD/builder-hex0-riscv64-stage1.elf}
OUTPUT=${2:-builder-hex0-riscv64-stage1.hex0}
TMP=${OUTPUT}.tmp

{
    printf '%s\n' '# SPDX-License-Identifier: MIT'
    printf '%s\n' '# builder-hex0 riscv64 stage 1, linked at 0x80000000'
    printf '%s\n' '# RV64I instruction bytes are little-endian; disassembly is commentary.'
    printf '\n'

    "$OBJDUMP" -d "$ELF" | awk '
        /^[0-9a-f]+ <[^>]+>:/ {
            label = $2
            gsub(/[<>:]/, "", label)
            printf "\n# %s\n", label
            next
        }
        $1 ~ /^[0-9a-f]+:$/ && length($2) == 8 && $2 !~ /[^0-9a-f]/ {
            word = $2
            printf "%s %s %s %s #", substr(word, 7, 2), substr(word, 5, 2), substr(word, 3, 2), substr(word, 1, 2)
            for (i = 3; i <= NF; i++) printf " %s", $i
            printf "\n"
        }
    '

    printf '\n%s\n' '# rodata'
    "$OBJDUMP" -s -j .rodata "$ELF" | awk '
        /^[[:space:]]*[0-9a-f]+[[:space:]]/ {
            printf ""
            for (i = 2; i <= NF; i++) {
                if ($i ~ /[^0-9a-f]/ || length($i) > 8 || length($i) % 2) break
                for (j = 1; j <= length($i); j += 2) printf "%s ", substr($i, j, 2)
            }
            printf "# data\n"
        }
    '
} > "$TMP"

mv "$TMP" "$OUTPUT"
