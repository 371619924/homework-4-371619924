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

__mtrap:
    # Swap stack pointer with mscratch
    mv t0, sp                # Save sp in t0
    csrr    sp, mscratch      # Load mscratch into sp
    csrw    mscratch, t0      # Store original sp into mscratch
    
    # Save registers (x0-x31)
    addi    sp, sp, -128      # Allocate space on the stack for saving registers
    sw      ra, 0(sp)
    sw      s0, 4(sp)
    sw      s1, 8(sp)
    sw      s2, 12(sp)
    sw      s3, 16(sp)
    sw      s4, 20(sp)
    sw      s5, 24(sp)
    sw      s6, 28(sp)
    sw      s7, 32(sp)
    sw      s8, 36(sp)
    sw      s9, 40(sp)
    sw      s10, 44(sp)
    sw      s11, 48(sp)
    sw      t0, 52(sp)
    sw      t1, 56(sp)
    sw      t2, 60(sp)
    sw      t3, 64(sp)
    sw      t4, 68(sp)
    sw      t5, 72(sp)
    sw      t6, 76(sp)
    sw      a0, 80(sp)
    sw      a1, 84(sp)
    sw      a2, 88(sp)
    sw      a3, 92(sp)
    sw      a4, 96(sp)
    sw      a5, 100(sp)
    sw      a6, 104(sp)
    sw      a7, 108(sp)
    
    # Check the exception type
    csrr    t0, mcause          # Load the cause into t0
    li      t1, 0x04            # Misaligned load word cause
    li      t2, 0x05            # Load access fault cause
    li      t3, 0x06            # Misaligned store cause

    beq     t0, t1, handle_misaligned_load    # Misaligned load
    beq     t0, t2, handle_load_access_fault  # Load access fault
    beq     t0, t3, handle_misaligned_store   # Misaligned store
    
    # If it's not any of these, jump to terminate function
    j       terminate

handle_misaligned_load:
    # Misaligned load handling (same as before)
    csrr    t0, mtval           # Load the misaligned address into t0
    lb      t1, 0(t0)           # Load byte 0
    lb      t2, 1(t0)           # Load byte 1
    lb      t3, 2(t0)           # Load byte 2
    lb      t4, 3(t0)           # Load byte 3
    
    # Shift and combine the bytes into a single word
    slli    t2, t2, 8           # Shift byte 1 by 8 bits
    or      t1, t1, t2           # Combine byte 0 and byte 1
    slli    t3, t3, 16          # Shift byte 2 by 16 bits
    or      t1, t1, t3           # Combine byte 0+1 and byte 2
    slli    t4, t4, 24          # Shift byte 3 by 24 bits
    or      t1, t1, t4           # Combine byte 0+1+2 and byte 3
    
    # Store the result in a0 (destination register)
    csrr    t0, mepc            # Load mepc into t0 (current instruction address)
    slli    t0, t0, 2           # Multiply by 4 to get the word offset
    lw      t5, 0(sp)           # Load destination register index (a0)
    sw      t1, 0(t5)           # Store the result into the destination register
    
    # Increment mepc to the next instruction
    addi    t0, t0, 4
    csrw    mepc, t0            # Set mepc to the next instruction
    
    # Restore registers and return to interrupted instruction
    j       restore_and_return

handle_load_access_fault:
    # Handle Load Access Fault (0x05)
    la      a0, __e5            # Load the error message for Load Access Fault
    li      a7, PRINT_STR
    ecall
    j       terminate

handle_misaligned_store:
    # Handle Misaligned Store (0x06)
    la      a0, __e6            # Load the error message for Misaligned Store
    li      a7, PRINT_STR
    ecall
    j       terminate

restore_and_return:
    # Restore registers
    lw      ra, 0(sp)
    lw      s0, 4(sp)
    lw      s1, 8(sp)
    lw      s2, 12(sp)
    lw      s3, 16(sp)
    lw      s4, 20(sp)
    lw      s5, 24(sp)
    lw      s6, 28(sp)
    lw      s7, 32(sp)
    lw      s8, 36(sp)
    lw      s9, 40(sp)
    lw      s10, 44(sp)
    lw      s11, 48(sp)
    lw      t0, 52(sp)
    lw      t1, 56(sp)
    lw      t2, 60(sp)
    lw      t3, 64(sp)
    lw      t4, 68(sp)
    lw      t5, 72(sp)
    lw      t6, 76(sp)
    lw      a0, 80(sp)
    lw      a1, 84(sp)
    lw      a2, 88(sp)
    lw      a3, 92(sp)
    lw      a4, 96(sp)
    lw      a5, 100(sp)
    lw      a6, 104(sp)
    lw      a7, 108(sp)
    addi    sp, sp, 128         # Restore stack pointer
    
    # Return to the interrupted instruction
    mret

	
  	

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

