# Makefile for the builder-hex0 project
#
# This makefile is provided for convenience for those who are using a
# virtual machine and do not want to construct and launch the initial
# disk image by hand.
#
# Providing steps for constructing the initial disk image for every
# possible machine is outside the scope of this project.
#
# To address criticism that "using a makefile to automate a bootstrap
# process is cheating", this is only provided for convenience
# for those who want to "cheat".
#
#
# * Files with .hex0 extension is source code to be compiled
# * Files with .src extension are build scripts with source code included.
#
# * Files with .bin extension consist of the bootable/executable part of a
#   hard disk image. They are not functional by themselves.
# * Files with .img extension are hard disk images that consist of the .bin
#   bootable/executable with a .src (for full builds) or .hex0 (for mini builds)
#   file appended to it, making it ready to build.
#
#
# The "mini" builder takes .hex0 files and can build itself and can also
# build the full builder.
#
# The "full" builder takes .src files which are primitive shell scripts and
# can build itself and other compilers.

QEMU ?= qemu-system-riscv64
QEMU_ARM64 ?= qemu-system-aarch64
XXD ?= xxd
TIMEOUT ?= 20

all: BUILD/builder-hex0-self-built.bin BUILD/builder-hex0-x86-stage1.img

riscv64-stage1: BUILD/builder-hex0-riscv64-stage1.bin

arm64-stage1: BUILD/builder-hex0-arm64-stage1.bin

arm64-stage2: arm64-stage2-oracle

arm64-stage2-oracle:
	./build-arm64-stage2.sh
	TITLE='builder-hex0 arm64 stage 2' DATA_TITLE='non-executable data' RAW_TEXT=1 \
		./arm64-stage1-to-hex0.sh \
		BUILD/builder-hex0-arm64-stage2.elf \
		BUILD/builder-hex0-arm64-stage2-generated.hex0
	diff builder-hex0-arm64-stage2.hex0 BUILD/builder-hex0-arm64-stage2-generated.hex0
	cut builder-hex0-arm64-stage2.hex0 -f1 -d'#' | cut -f1 -d';' | $(XXD) -r -p \
		> BUILD/builder-hex0-arm64-stage2-from-hex0.bin
	cmp BUILD/builder-hex0-arm64-stage2.bin BUILD/builder-hex0-arm64-stage2-from-hex0.bin

BUILD/builder-hex0-arm64-stage1.bin: builder-hex0-arm64-stage1.hex0 | BUILD
	cut builder-hex0-arm64-stage1.hex0 -f1 -d'#' | cut -f1 -d';' | $(XXD) -r -p > $@

arm64-stage1-oracle: arm64-stage1
	./build-arm64-stage1.sh
	./arm64-stage1-to-hex0.sh BUILD/builder-hex0-arm64-stage1-oracle.elf BUILD/builder-hex0-arm64-stage1-generated.hex0
	diff builder-hex0-arm64-stage1.hex0 BUILD/builder-hex0-arm64-stage1-generated.hex0
	cmp BUILD/builder-hex0-arm64-stage1.bin BUILD/builder-hex0-arm64-stage1-oracle.bin

test-arm64-stage1: arm64-stage1-oracle
	QEMU=$(QEMU_ARM64) TIMEOUT=$(TIMEOUT) ./test-arm64-stage1.sh

test-arm64-stage2: arm64-stage2
	QEMU=$(QEMU_ARM64) TIMEOUT=$(TIMEOUT) ./test-arm64-stage2.sh

test-arm64-stage2-shell: arm64-stage2
	QEMU=$(QEMU_ARM64) TIMEOUT=$(TIMEOUT) ./test-arm64-stage2-shell.sh

BUILD/builder-hex0-riscv64-stage1.bin: builder-hex0-riscv64-stage1.hex0 | BUILD
	cut builder-hex0-riscv64-stage1.hex0 -f1 -d'#' | cut -f1 -d';' | $(XXD) -r -p > $@

riscv64-stage1-oracle: riscv64-stage1
	./build-riscv64-stage1.sh
	./riscv64-stage1-to-hex0.sh BUILD/builder-hex0-riscv64-stage1-oracle.elf BUILD/builder-hex0-riscv64-stage1-generated.hex0
	diff builder-hex0-riscv64-stage1.hex0 BUILD/builder-hex0-riscv64-stage1-generated.hex0
	cmp BUILD/builder-hex0-riscv64-stage1.bin BUILD/builder-hex0-riscv64-stage1-oracle.bin

riscv64-stage2-oracle:
	./build-riscv64-stage2.sh
	TITLE='builder-hex0 riscv64 stage 2' DATA_TITLE='non-executable data' RAW_TEXT=1 \
		./riscv64-stage1-to-hex0.sh \
		BUILD/builder-hex0-riscv64-stage2.elf \
		BUILD/builder-hex0-riscv64-stage2-generated.hex0
	diff builder-hex0-riscv64-stage2.hex0 BUILD/builder-hex0-riscv64-stage2-generated.hex0
	cut builder-hex0-riscv64-stage2.hex0 -f1 -d'#' | cut -f1 -d';' | $(XXD) -r -p \
		> BUILD/builder-hex0-riscv64-stage2-from-hex0.bin
	cmp BUILD/builder-hex0-riscv64-stage2.bin BUILD/builder-hex0-riscv64-stage2-from-hex0.bin

riscv64-tinyemu-stage1: BUILD/builder-hex0-riscv64-tinyemu-stage1.bin

BUILD/builder-hex0-riscv64-tinyemu-stage1.bin: builder-hex0-riscv64-tinyemu-stage1.hex0 | BUILD
	cut builder-hex0-riscv64-tinyemu-stage1.hex0 -f1 -d'#' | cut -f1 -d';' | $(XXD) -r -p > $@

riscv64-tinyemu-stage1-oracle: riscv64-tinyemu-stage1
	SEED=builder-hex0-riscv64-tinyemu-stage1 ./build-riscv64-stage1.sh
	./riscv64-stage1-to-hex0.sh \
		BUILD/builder-hex0-riscv64-tinyemu-stage1-oracle.elf \
		BUILD/builder-hex0-riscv64-tinyemu-stage1-generated.hex0
	diff builder-hex0-riscv64-tinyemu-stage1.hex0 BUILD/builder-hex0-riscv64-tinyemu-stage1-generated.hex0
	cmp BUILD/builder-hex0-riscv64-tinyemu-stage1.bin BUILD/builder-hex0-riscv64-tinyemu-stage1-oracle.bin

riscv64-tinyemu-stage2-oracle:
	SEED=builder-hex0-riscv64-tinyemu-stage2 ./build-riscv64-stage2.sh
	TITLE='builder-hex0 riscv64 stage 2' DATA_TITLE='non-executable data' RAW_TEXT=1 \
		./riscv64-stage1-to-hex0.sh \
		BUILD/builder-hex0-riscv64-tinyemu-stage2.elf \
		BUILD/builder-hex0-riscv64-tinyemu-stage2-generated.hex0
	diff builder-hex0-riscv64-tinyemu-stage2.hex0 BUILD/builder-hex0-riscv64-tinyemu-stage2-generated.hex0
	cut builder-hex0-riscv64-tinyemu-stage2.hex0 -f1 -d'#' | cut -f1 -d';' | $(XXD) -r -p \
		> BUILD/builder-hex0-riscv64-tinyemu-stage2-from-hex0.bin
	cmp BUILD/builder-hex0-riscv64-tinyemu-stage2.bin BUILD/builder-hex0-riscv64-tinyemu-stage2-from-hex0.bin

test-riscv64-tinyemu: riscv64-tinyemu-stage1-oracle riscv64-tinyemu-stage2-oracle

test-riscv64-stage1: riscv64-stage1-oracle riscv64-stage2-oracle
	./test-riscv64-stage1.sh

test-riscv64-stage2:
	./build-riscv64-stage2.sh
	timeout $(TIMEOUT) $(QEMU) -M virt -m 128M -smp 1 -nographic \
		-bios none -kernel BUILD/builder-hex0-riscv64-stage2.bin -no-reboot \
		| tee BUILD/builder-hex0-riscv64-stage2.log
	grep 'stage2 user ecall passed' BUILD/builder-hex0-riscv64-stage2.log

test-riscv64-stage2-shell:
	./build-riscv64-stage2.sh
	./test-riscv64-stage2-shell.sh

test-riscv64-stage2-chain:
	./build-riscv64-stage2.sh
	./test-riscv64-stage2-chain.sh

test-riscv64-stage2-stage0:
	test -n "$(STAGE0_HEX0_SEED)"
	./build-riscv64-stage2.sh
	timeout $(TIMEOUT) $(QEMU) -M virt -m 128M -smp 1 -nographic \
		-bios none -kernel BUILD/builder-hex0-riscv64-stage2.bin -no-reboot \
		-device loader,file=$(STAGE0_HEX0_SEED),addr=0x82000000,force-raw=on \
		-device loader,file=test/hex0-parser.hex0,addr=0x82200000,force-raw=on \
		| tee BUILD/builder-hex0-riscv64-stage2-stage0.log
	grep 'real stage0 hex0-seed passed' BUILD/builder-hex0-riscv64-stage2-stage0.log

test-riscv64-stage2-stage0-selfhost:
	test -n "$(STAGE0_HEX0_SEED)"
	test -n "$(STAGE0_HEX0_SOURCE)"
	./build-riscv64-stage2.sh
	timeout $(TIMEOUT) $(QEMU) -M virt -m 128M -smp 1 -nographic \
		-bios none -kernel BUILD/builder-hex0-riscv64-stage2.bin -no-reboot \
		-device loader,file=$(STAGE0_HEX0_SEED),addr=0x82000000,force-raw=on \
		-device loader,file=$(STAGE0_HEX0_SOURCE),addr=0x82200000,force-raw=on \
		-device loader,file=$(STAGE0_HEX0_SEED),addr=0x82600000,force-raw=on \
		-device loader,data=0x188,addr=0x82800000,data-len=8 \
		| tee BUILD/builder-hex0-riscv64-stage2-stage0-selfhost.log
	grep 'stage0 hex0-seed self-build passed' BUILD/builder-hex0-riscv64-stage2-stage0-selfhost.log

# The (full) builder-hex0 built by a (full) builder-hex0 (built by the mini builder)
BUILD/builder-hex0-self-built.bin: BUILD/builder-hex0-mini-built.bin BUILD/builder-hex0.src build.sh | BUILD
	echo "Build the (full) builder-hex0 by a (full) builder-hex0 (built by the mini builder)"
	# params: boot sectors to use, shell source to append, name of binary to extract
	(cd BUILD && ../build.sh builder-hex0-mini-built.bin builder-hex0.src builder-hex0-self-built.bin)
	# verify that the self-built binary is the same as the mini-built binary
	(cd BUILD && diff builder-hex0-self-built.bin builder-hex0-mini-built.bin)

BUILD/builder-hex0.src: builder-hex0.hex0 hex0-to-src.sh | BUILD
	# create directory so we can write into it
	echo "src 0 /dev" > $@
	./hex0-to-src.sh ./builder-hex0.hex0 >> $@


# The "full" builder-hex0 built by the self-built mini builder
BUILD/builder-hex0-mini-built.bin: BUILD/builder-hex0-mini-self-built.bin builder-hex0.hex0 build-mini.sh BUILD/builder-hex0-seed.bin | BUILD
	echo "Build The full builder-hex0 by the self-built mini builder"
	# params: boot sectors to use, source to append, size of binary to extract, name of extracted binary
	(cd BUILD && ../build-mini.sh builder-hex0-mini-self-built.bin ../builder-hex0.hex0 4096 builder-hex0-mini-built.bin)
	# verify that it matches the seed
	(cd BUILD && diff builder-hex0-seed.bin builder-hex0-mini-built.bin)


# builder-hex0-mini built by the mini builder built by the seed mini bulder
BUILD/builder-hex0-mini-self-built.bin: BUILD/builder-hex0-mini-seed-built.bin builder-hex0-mini.hex0 build-mini.sh | BUILD
	echo "Build builder-hex0-mini by the mini builder built by the seed mini bulder"
	# params: boot sectors to use, source to append, size of binary to extract, name of extracted binary
	(cd BUILD && ../build-mini.sh builder-hex0-mini-seed-built.bin ../builder-hex0-mini.hex0 512 builder-hex0-mini-self-built.bin)
	# verify that the self-built mini builder is the same as the seed-built binary
	(cd BUILD && diff builder-hex0-mini-seed-built.bin builder-hex0-mini-self-built.bin)


# builder-hex0-mini built by the seed mini builder
BUILD/builder-hex0-mini-seed-built.bin: BUILD/builder-hex0-mini-seed.bin builder-hex0-mini.hex0 build-mini.sh | BUILD
	echo "Build builder-hex0-mini with the seed mini builder"
	# params: boot sectors to use, source to append, size of binary to extract, name of binary to extract
	(cd BUILD && ../build-mini.sh builder-hex0-mini-seed.bin ../builder-hex0-mini.hex0 512 builder-hex0-mini-seed-built.bin)
	# verify that the binary built by the seed binary is the same as the seed binary
	(cd BUILD && diff builder-hex0-mini-seed.bin builder-hex0-mini-seed-built.bin)


# builder-hex0-mini seed built using command line utilities
BUILD/builder-hex0-mini-seed.bin: builder-hex0-mini.hex0 | BUILD
	# uses cut to strip comments starting with pound or semicolon.
	# uses xxd to convert hex to binary
	cut builder-hex0-mini.hex0 -f1 -d'#' | cut -f1 -d';' | xxd -r -p > BUILD/builder-hex0-mini-seed.bin

# builder-hex0 seed built using command line utilities
BUILD/builder-hex0-seed.bin: builder-hex0.hex0 | BUILD
	# uses cut to strip comments starting with pound or semicolon.
	# uses xxd to convert hex to binary
	cut builder-hex0.hex0 -f1 -d'#' | cut -f1 -d';' | xxd -r -p > BUILD/builder-hex0-seed.bin

# stage1 has an img extension to match other files in https://github.com/oriansj/bootstrap-seeds/tree/master/NATIVE/x86
BUILD/builder-hex0-x86-stage1.img: builder-hex0-x86-stage1.hex0 | BUILD
	cut builder-hex0-x86-stage1.hex0 -f1 -d'#' | cut -f1 -d';' | xxd -r -p > BUILD/builder-hex0-x86-stage1.img

BUILD:
	mkdir BUILD

test:
	./test-stages.sh

clean:
	rm -rf BUILD
	make -C hex2 clean

# Make does not check whether PHONY targets already exist as files or dirs.
# It just invokes their recipes when they are targeted, no questions asked.
.PHONY: clean arm64-stage1 arm64-stage1-oracle arm64-stage2 arm64-stage2-oracle test-arm64-stage1 test-arm64-stage2 test-arm64-stage2-shell riscv64-stage1 riscv64-stage1-oracle riscv64-stage2-oracle test-riscv64-stage1 test-riscv64-stage2 test-riscv64-stage2-shell test-riscv64-stage2-chain test-riscv64-stage2-stage0 test-riscv64-stage2-stage0-selfhost riscv64-tinyemu-stage1 riscv64-tinyemu-stage1-oracle riscv64-tinyemu-stage2-oracle test-riscv64-tinyemu
