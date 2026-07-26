#!/bin/sh
set -eu

OBJDUMP=${OBJDUMP:-aarch64-linux-gnu-objdump}
ELF=${1:-BUILD/builder-hex0-arm64-stage1-oracle.elf}
OUTPUT=${2:-builder-hex0-arm64-stage1.hex0}
TMP=${OUTPUT}.tmp

{
    printf '%s\n' '# SPDX-License-Identifier: MIT'
    printf '%s\n' '# builder-hex0 arm64 stage 1, linked at 0x40080000'
    printf '%s\n' '# A64 instruction words and data are encoded little-endian.'
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

    printf '\n%s\n' '# read-only data'
    "$OBJDUMP" -s -j .rodata "$ELF" | awk '
        /^[[:space:]]*[0-9a-f]+[[:space:]]/ {
            for (i = 2; i <= 5 && i <= NF; i++) {
                if ($i ~ /[^0-9a-f]/ || length($i) > 8 || length($i) % 2) break
                for (j = 1; j <= length($i); j += 2) printf "%s ", substr($i, j, 2)
            }
            printf "# data\n"
        }
    '
} > "$TMP"

mv "$TMP" "$OUTPUT"
