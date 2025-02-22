##
# Copyright (c) 1990-2023 James R. Larus.
# Copyright (c) 2023 LupLab.
#
# SPDX-License-Identifier: AGPL-3.0-only
##

# This a modified version of the default system code for VRV.

# It contains three parts:

# 1. The machine boot code, starting from global label
#    `__mstart`. This boot code sets up the trap vector, and jumps to
#    label `__user_bootstrap` in user mode.

# 2. The trap handler, which is called upon an exception (interrupts
#    are not enabled by default).
	
# 3. The small user bootstrap code, starting from global label
#    `__user_bootstrap`. This bootstrap code calls `main`, which is expected to
#     be defined by the user program. If main returns, the bootstrap code exits
#     with the value returned by main.

# You will need to modify the trap handler to:

# a) Save all registers

# b) Examine the cause to determine if it is a misaligned load word.

# c) If it IS a misaligned load word, it should patch up the
# result and resume execution at the next instruction.

# d) Otherwise, it should jump to the terminate operation
# which is the default printing routine from VRV's default
# system file.

	## Constants
.equ    PRINT_DEC  0
.equ    PRINT_HEX   1
.equ    PRINT_CHR   3
.equ    PRINT_STR   4
.equ    EXIT        20

.equ    NEWLN_CHR   '\n'
.equ    SPACE_CHR   ' '

.equ 	KSTACK_SIZE 4096
	
# YOU can add more constants here, and you probably will want to!

## System data
    .kdata
__m_exc:    .string "  Exception"
__m_int:    .string "  Interrupt"

__m_mcause: .string "\n    MCAUSE: "
__m_mepc:   .string "\n    MEPC:   "
__m_mtval:  .string "\n    MTVAL:  "

__e0:   .string " [Misaligned instruction address]"
__e1:   .string " [Instruction access fault]"
__e2:   .string " [Illegal instruction]"
__e3:   .string " [Breakpoint]"
__e4:   .string " [Misaligned load address]"
__e5:   .string " [Load access fault]"
__e6:   .string " [Misaligned store address]"
__e7:   .string " [Store access fault]"
__e8:   .string " [User-mode ecall]"
__e11:  .string " [Machine-mode ecall]"

__i3:   .string " [Software]"
__i7:   .string " [Timer]"
__i11:  .string " [External]"

__evec: .word __e0, __e1, __e2, __e3, __e4, __e5, __e6, __e7, __e8, 0, 0, __e11
__ivec: .word 0, 0, 0, __i3, 0, 0, 0, __i7, 0, 0, 0, __i11

	.align 2

	# A small stack for kernel data
kstack:  .zero   KSTACK_SIZE

## System code
    .ktext
### Boot code
    .globl __mstart
__mstart:
    la      t0, __mtrap
    csrw    mtvec, t0

	la      t0, __user_bootstrap
	csrw    mepc, t0

	# Allocates space so the trap handler has a
	# small stack and can therefore call functions
	# itself.
	la 	t0, kstack
	li	t1, KSTACK_SIZE
	add 	t0 t0 t1
	csrw   	mscratch, t0
	mret    # Enter user bootstrap

### Trap handler

### You will need to write your own trap handler functionality here.
    
__mtrap:
    # 1. Swap sp and mscratch so sp points to kernel stack
    csrrw sp, mscratch, sp  

    # 2. Save all registers (72 bytes total)
    addi sp, sp, -72
    sw ra, 0(sp)
    sw t0, 4(sp)
    sw t1, 8(sp)
    sw t2, 12(sp)
    sw t3, 16(sp)
    sw t4, 20(sp)
    sw t5, 24(sp)
    sw t6, 28(sp)
    sw a0, 32(sp)
    sw a1, 36(sp)
    sw a2, 40(sp)
    sw a3, 44(sp)
    sw a4, 48(sp)
    sw a5, 52(sp)
    sw a6, 56(sp)
    sw a7, 60(sp)
    sw s0, 64(sp)
    sw s1, 68(sp)

    # 3. Read mcause and check for misaligned load (4) or store (6)
    csrr t0, mcause
    li t1, 4      # Misaligned Load Address
    li t2, 6      # Misaligned Store Address
    beq t0, t1, handle_misaligned_load
    beq t0, t2, handle_misaligned_store

    # Other exceptions: jump to terminate routine
    j terminate

handle_misaligned_load:
    csrr t4, mtval         # t4 = misaligned address
    beqz t4, terminate

    csrr t0, mepc          # get faulting instruction address
    lw t1, 0(t0)           # fetch faulting instruction
    li t2, 0x00002003      # constant for lw (opcode 0x03 with proper funct3 bits)
    and t3, t1, t2
    bne t3, t2, terminate  # if not an lw, terminate

    # Emulate lw by reading four bytes (little-endian)
    lbu t3, 0(t4)
    lbu t6, 1(t4)
    slli t6, t6, 8
    or t3, t3, t6
    lbu t6, 2(t4)
    slli t6, t6, 16
    or t3, t3, t6
    lbu t6, 3(t4)
    slli t6, t6, 24
    or t3, t3, t6

    # Extract destination register (rd) from instruction (bits 11:7)
    srli t5, t1, 7
    andi t5, t5, 0x1F
    bnez t5, patch_load_rd   # if rd != x0, patch the saved register
    j skip_patch_load        # if rd == 0, do nothing
patch_load_rd:
    la t7, load_table        # t7 = address of lookup table
    slli t5, t5, 2           # multiply register number by 4 (word offset)
    add t7, t7, t5           # t7 now points to the proper offset in the table
    sw t3, 0(t7)           # write the emulated load result into the trap frame
skip_patch_load:
    csrr t0, mepc
    addi t0, t0, 4         # skip over the faulting instruction
    csrw mepc, t0
    j restore_registers

handle_misaligned_store:
    csrr t4, mtval         # t4 = misaligned effective address
    beqz t4, terminate

    csrr t0, mepc
    lw t1, 0(t0)           # fetch faulting instruction
    li t2, 0x00002023      # constant for sw (opcode 0x23 with proper funct3 bits)
    and t3, t1, t2
    bne t3, t2, terminate  # if not an sw, terminate

    # Extract rs2 (source register for store) from instruction (bits 24:20)
    srli t5, t1, 20
    andi t5, t5, 0x1F
    beqz t5, load_zero_for_store  # if rs2 is x0, use 0
    la t7, load_table        # use same table for lookup
    slli t5, t5, 2
    add t7, t7, t5
    lw t3, 0(t7)           # t3 now holds the value to be stored
    j store_value
load_zero_for_store:
    li t3, 0
store_value:
    # Emulate sw by storing the word byte-by-byte (little-endian)
    sb t3, 0(t4)
    srli t3, t3, 8
    sb t3, 1(t4)
    srli t3, t3, 8
    sb t3, 2(t4)
    srli t3, t3, 8
    sb t3, 3(t4)
    
    csrr t0, mepc
    addi t0, t0, 4         # advance past the faulting instruction
    csrw mepc, t0
    j restore_registers

restore_registers:
    lw ra, 0(sp)
    lw t0, 4(sp)
    lw t1, 8(sp)
    lw t2, 12(sp)
    lw t3, 16(sp)
    lw t4, 20(sp)
    lw t5, 24(sp)
    lw t6, 28(sp)
    lw a0, 32(sp)
    lw a1, 36(sp)
    lw a2, 40(sp)
    lw a3, 44(sp)
    lw a4, 48(sp)
    lw a5, 52(sp)
    lw a6, 56(sp)
    lw a7, 60(sp)
    lw s0, 64(sp)
    lw s1, 68(sp)
    addi sp, sp, 72
    csrrw sp, mscratch, sp
    mret

    .align 2
load_table:
    # Table mapping register number -> offset in saved trap frame
    # (only registers that were saved are nonzero; writes to x0 are ignored)
    .word 0      #  x0 (not saved)
    .word 0      #  x1 (ra)  offset 0
    .word 0      #  x2 (not saved)
    .word 0      #  x3 (not saved)
    .word 0      #  x4 (not saved)
    .word 4      #  x5 (t0)  offset 4
    .word 8      #  x6 (t1)  offset 8
    .word 12     #  x7 (t2)  offset 12
    .word 64     #  x8 (s0)  offset 64
    .word 68     #  x9 (s1)  offset 68
    .word 32     #  x10 (a0) offset 32
    .word 36     #  x11 (a1) offset 36
    .word 40     #  x12 (a2) offset 40
    .word 44     #  x13 (a3) offset 44
    .word 48     #  x14 (a4) offset 48
    .word 52     #  x15 (a5) offset 52
    .word 56     #  x16 (a6) offset 56
    .word 60     #  x17 (a7) offset 60
    .word 0      #  x18 (not saved)
    .word 0      #  x19 (not saved)
    .word 0      #  x20 (not saved)
    .word 0      #  x21 (not saved)
    .word 0      #  x22 (not saved)
    .word 0      #  x23 (not saved)
    .word 0      #  x24 (not saved)
    .word 0      #  x25 (not saved)
    .word 0      #  x26 (not saved)
    .word 0      #  x27 (not saved)
    .word 16     #  x28 (t3)  offset 16
    .word 20     #  x29 (t4)  offset 20
    .word 24     #  x30 (t5)  offset 24
    .word 28     #  x31 (t6)  offset 28



# This code is taken from the default VRV system code.  It prints out
# a message indicating the cause of an unhandled exception.  We are
# keeping this in this form to make it easier for you to debug.

# It is allowed to trash registers (unlike the normal trap handler)
# because it never returns	
terminate:
    csrr    t0, mcause      # Get mcause CSR
    li      t1, 0x80000000
    and     t1, t0, t1      # mcause & 0x80000000
    beqz    t1, ____not_interrupt   # mcause has bit 31 set for an interrupt

    # 2a. Interrupt
    la      a0, __m_int     # Interrupt header message
    xor     t0, t0, t1      # Isolate interrupt code
    la      t1, __ivec      # Interrupt vector
    j       ____print_trap_message

    # 2b. Exception
____not_interrupt:
    la      a0, __m_exc     # Exception header message
    la      t1, __evec      # Isolate exception code

    # 3. Print header message
____print_trap_message:
    li      a7, PRINT_STR
    ecall

    # 4. Print vector entry for this exception/interrupt
    slli    a0, t0, 2       # mcause * 4
    add     a0, t1, a0      # Index in vector
    lw      a0, (a0)        # Entry from vector
    ecall

    # 5. Print mcause
    la      a0, __m_mcause
    ecall
    csrr    a0, mcause
    li      a7, PRINT_HEX
    ecall

    # 6. Print mepc
    la      a0, __m_mepc
    li      a7, PRINT_STR
    ecall
    csrr    a0, mepc
    li      a7, PRINT_HEX
    ecall

    # 7. Print mtval
    la      a0, __m_mtval
    li      a7, PRINT_STR
    ecall
    csrr    a0, mtval
    li      a7, PRINT_HEX
    ecall
    li      a0, NEWLN_CHR
    li      a7, PRINT_CHR
    ecall

    # Exit with code -1
    li      a0, -1
    li      a7, EXIT
    ecall



## User boot code
    .text
__user_bootstrap:
    # exit(main())
    jal     main
    li      a7, EXIT
    ecall

# Useful utility function
kprintstr:
	li a7, PRINT_STR
	ecall
	ret

