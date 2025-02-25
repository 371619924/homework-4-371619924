##
# Copyright (c) 1990-2023 James R. Larus.
# Copyright (c) 2023 LupLab.
#
# SPDX-License-Identifier: AGPL-3.0-only
##

# This a modified version of the default system code for VRV.

# It contains three parts:

# 1. The machine boot code, starting from global label
# `__mstart`. This boot code sets up the trap vector, and jumps to
# label `__user_bootstrap` in user mode.

# 2. The trap handler, which is called upon an exception (interrupts
# are not enabled by default).

# 3. The small user bootstrap code, starting from global label
# `__user_bootstrap`. This bootstrap code calls `main`, which is expected to
# be defined by the user program. If main returns, the bootstrap code exits
# with the value returned by main.

# You will need to modify the trap handler to:

# a) Save all registers

# b) Examine the cause to determine if it is a misaligned load word.

# c) If it IS a misaligned load word, it should patch up the
# result and resume execution at the next instruction.

# d) Otherwise, it should jump to the terminate operation
# which is the default printing routine from VRV's default
# system file.

## Constants
    .equ    PRINT_DEC 0
    .equ    PRINT_HEX 1
    .equ    PRINT_CHR 3
    .equ    PRINT_STR 4
    .equ    EXIT 20

    .equ    NEWLN_CHR '\n'
    .equ    SPACE_CHR ' '

    .equ    KSTACK_SIZE 4096

# YOU can add more constants here, and you probably will want to!

## System data
    .kdata
__m_exc:
    .string " Exception"
__m_int:
    .string " Interrupt"

__m_mcause:
.string "\n MCAUSE:
    "
__m_mepc:
.string "\n MEPC:
    "
__m_mtval:
.string "\n MTVAL:
    "

__e0:
    .string " [Misaligned instruction address]"
__e1:
    .string " [Instruction access fault]"
__e2:
    .string " [Illegal instruction]"
__e3:
    .string " [Breakpoint]"
__e4:
    .string " [Misaligned load address]"
__e5:
    .string " [Load access fault]"
__e6:
    .string " [Misaligned store address]"
__e7:
    .string " [Store access fault]"
__e8:
    .string " [User-mode ecall]"
__e11:
    .string " [Machine-mode ecall]"

__i3:
    .string " [Software]"
__i7:
    .string " [Timer]"
__i11:
    .string " [External]"

__evec:
    .word   __e0, __e1, __e2, __e3, __e4, __e5, __e6, __e7, __e8, 0, 0, __e11
__ivec:
    .word   0, 0, 0, __i3, 0, 0, 0, __i7, 0, 0, 0, __i11

    .align  2

# A small stack for kernel data
kstack:
    .zero   KSTACK_SIZE

## System code
    .ktext
### Boot code
    .globl  __mstart
__mstart:
    la      t0, __mtrap
    csrw    mtvec, t0

    la      t0, __user_bootstrap
    csrw    mepc, t0

# Allocates space so the trap handler has a
# small stack and can therefore call functions
# itself.
    la      t0, kstack
    li      t1, KSTACK_SIZE
    add     t0 t0 t1
    csrw    mscratch, t0
    mret                                                                      # Enter user bootstrap

### Trap handler

### You will need to write your own trap handler functionality here.
# Trap handler for misaligned load word exceptions
__mtrap:
    # Exchange user and kernel stacks using temporary registers
    csrr    t0, mscratch      # Get kernel stack pointer from mscratch
    mv      t1, sp           # Save user stack pointer to t1
    mv      sp, t0           # Set sp to kernel stack
    csrw    mscratch, t1     # Save user stack pointer to mscratch

    # Allocate space and save all registers
    addi    sp, sp, -124     # Adjust stack pointer for 31 registers (31*4=124)
    # Save registers x1-x31 to stack
    sw      x1,  0(sp)
    sw      x2,  4(sp)
    sw      x3,  8(sp)
    sw      x4,  12(sp)
    sw      x5,  16(sp)
    sw      x6,  20(sp)
    sw      x7,  24(sp)
    sw      x8,  28(sp)
    sw      x9,  32(sp)
    sw      x10, 36(sp)
    sw      x11, 40(sp)
    sw      x12, 44(sp)
    sw      x13, 48(sp)
    sw      x14, 52(sp)
    sw      x15, 56(sp)
    sw      x16, 60(sp)
    sw      x17, 64(sp)
    sw      x18, 68(sp)
    sw      x19, 72(sp)
    sw      x20, 76(sp)
    sw      x21, 80(sp)
    sw      x22, 84(sp)
    sw      x23, 88(sp)
    sw      x24, 92(sp)
    sw      x25, 96(sp)
    sw      x26, 100(sp)
    sw      x27, 104(sp)
    sw      x28, 108(sp)
    sw      x29, 112(sp)
    sw      x30, 116(sp)
    sw      x31, 120(sp)

    # Alternative approach to check if this is a misaligned load exception
    # First check if interrupt bit (MSB) is clear - meaning it's an exception
    csrr    a7, mcause       # Load mcause value
    srai    a6, a7, 31       # Get the MSB (sign bit)
    bnez    a6, _trap_fail   # If MSB set, not an exception, go to fail
    
    # Then check if exception code is 4 (load address misaligned)
    andi    a7, a7, 0xF      # Mask to get exception code (lower bits)
    li      a6, 4            # Load address misaligned exception code
    bne     a7, a6, _trap_fail # If not load misaligned, go to fail

    # Check instruction to confirm it's a load word (lw)
    csrr    a4, mepc         # Get address of instruction that caused exception
    lw      a5, 0(a4)        # Load the instruction

    # Verify it's an lw instruction by checking opcode and funct3
    # Check opcode bits [6:0] == 0000011 (load)
    andi    a3, a5, 0x7F     # Extract opcode
    li      a2, 0x03         # Load opcode
    bne     a3, a2, _trap_fail # If not a load, go to fail
    
    # Check funct3 bits [14:12] == 010 (word)
    srli    a3, a5, 12
    andi    a3, a3, 0x7
    li      a2, 2            # Word size (lw)
    bne     a3, a2, _trap_fail # If not a word load, go to fail

    # Handle the misaligned load by manually loading bytes
    csrr    t3, mtval        # Get faulting address from mtval
    
    # Load individual bytes and combine them
    lb      t4, 0(t3)        # Byte 0 (LSB)
    lb      t5, 1(t3)        # Byte 1
    lb      t6, 2(t3)        # Byte 2
    lb      a0, 3(t3)        # Byte 3 (MSB)
    
    # Combine bytes into a word with shifting
    andi    t4, t4, 0xFF     # Ensure only 8 bits
    andi    t5, t5, 0xFF
    andi    t6, t6, 0xFF
    andi    a0, a0, 0xFF
    
    # Shift bytes to their proper positions
    slli    t5, t5, 8        # Shift byte 1 to bits 8-15
    slli    t6, t6, 16       # Shift byte 2 to bits 16-23
    slli    a0, a0, 24       # Shift byte 3 to bits 24-31
    
    # Combine the bytes
    or      a1, t4, t5       # Combine byte 0 and 1
    or      a1, a1, t6       # Add byte 2
    or      a1, a1, a0       # Add byte 3 to get full word

    # Extract destination register from instruction
    srli    t2, a5, 7
    andi    t2, t2, 0x1F     # Get rd field (bits [11:7])
    
    # Skip update if destination is x0 (zero register)
    beqz    t2, skip_patch   # If rd is x0, skip storing result
    
    # Alternative approach to register update using relative addressing
    addi    t0, sp, 0        # Start at stack base
    slli    t1, t2, 2        # Convert register number to offset (reg * 4)
    add     t0, t0, t1       # Calculate address on stack
    sw      a1, 0(t0)        # Store result to register's saved location

    # Special handling for stack pointer (x2)
    li      t1, 2
    bne     t2, t1, skip_mscratch_update
    lw      t0, 4(sp)        # Load updated sp value
    csrw    mscratch, t0     # Update mscratch with new sp value
skip_mscratch_update:

skip_patch:
    # Increment mepc to move past the faulting instruction
    csrr    t0, mepc
    addi    t0, t0, 4        # Increment by 4 bytes (one instruction)
    csrw    mepc, t0         # Update mepc to return to next instruction

    # Restore all registers from stack
    lw      x1,  0(sp)
    lw      x2,  4(sp)
    lw      x3,  8(sp)
    lw      x4,  12(sp)
    lw      x5,  16(sp)
    lw      x6,  20(sp)
    lw      x7,  24(sp)
    lw      x8,  28(sp)
    lw      x9,  32(sp)
    lw      x10, 36(sp)
    lw      x11, 40(sp)
    lw      x12, 44(sp)
    lw      x13, 48(sp)
    lw      x14, 52(sp)
    lw      x15, 56(sp)
    lw      x16, 60(sp)
    lw      x17, 64(sp)
    lw      x18, 68(sp)
    lw      x19, 72(sp)
    lw      x20, 76(sp)
    lw      x21, 80(sp)
    lw      x22, 84(sp)
    lw      x23, 88(sp)
    lw      x24, 92(sp)
    lw      x25, 96(sp)
    lw      x26, 100(sp)
    lw      x27, 104(sp)
    lw      x28, 108(sp)
    lw      x29, 112(sp)
    lw      x30, 116(sp)
    lw      x31, 120(sp)
    addi    sp, sp, 124     # Restore stack pointer

    # Restore user stack 
    csrr    t0, mscratch    # Get saved user stack pointer
    mv      t1, sp          # Save kernel stack pointer to t1
    csrw    mscratch, t1    # Save kernel stack pointer to mscratch
    mv      sp, t0          # Restore user stack pointer

    mret                    # Return from trap

_trap_fail:
    # Restore all registers
    lw      x1,  0(sp)
    lw      x2,  4(sp)
    lw      x3,  8(sp)
    lw      x4,  12(sp)
    lw      x5,  16(sp)
    lw      x6,  20(sp)
    lw      x7,  24(sp)
    lw      x8,  28(sp)
    lw      x9,  32(sp)
    lw      x10, 36(sp)
    lw      x11, 40(sp)
    lw      x12, 44(sp)
    lw      x13, 48(sp)
    lw      x14, 52(sp)
    lw      x15, 56(sp)
    lw      x16, 60(sp)
    lw      x17, 64(sp)
    lw      x18, 68(sp)
    lw      x19, 72(sp)
    lw      x20, 76(sp)
    lw      x21, 80(sp)
    lw      x22, 84(sp)
    lw      x23, 88(sp)
    lw      x24, 92(sp)
    lw      x25, 96(sp)
    lw      x26, 100(sp)
    lw      x27, 104(sp)
    lw      x28, 108(sp)
    lw      x29, 112(sp)
    lw      x30, 116(sp)
    lw      x31, 120(sp)
    addi    sp, sp, 124
    j       terminate      # Jump to terminate routine


# This code is taken from the default VRV system code. It prints out
# a message indicating the cause of an unhandled exception. We are
# keeping this in this form to make it easier for you to debug.

# It is allowed to trash registers (unlike the normal trap handler)
# because it never returns
terminate:
    csrr    t0, mcause                                                        # Get mcause CSR
    li      t1, 0x80000000
    and     t1, t0, t1                                                        # mcause & 0x80000000
    beqz    t1, ____not_interrupt                                             # mcause has bit 31 set for an interrupt

# 2a. Interrupt
    la      a0, __m_int                                                       # Interrupt header message
    xor     t0, t0, t1                                                        # Isolate interrupt code
    la      t1, __ivec                                                        # Interrupt vector
    j       ____print_trap_message

# 2b. Exception
____not_interrupt:
    la      a0, __m_exc                                                       # Exception header message
    la      t1, __evec                                                        # Isolate exception code

# 3. Print header message
____print_trap_message:
    li      a7, PRINT_STR
    ecall

# 4. Print vector entry for this exception/interrupt
    slli    a0, t0, 2                                                         # mcause * 4
    add     a0, t1, a0                                                        # Index in vector
    lw      a0, (a0)                                                          # Entry from vector
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
    li      a7, PRINT_STR
    ecall
    ret

