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
    # Exchange user stack pointer with kernel stack pointer
    csrrw a0, mscratch, a0

    # Allocate space on kernel stack for all registers
    addi a0, a0, -128
    
    # Store all registers to kernel stack
    sw x0, 0(a0)
    sw x1, 4(a0)
    sw x2, 8(a0)
    sw x3, 12(a0)
    sw x4, 16(a0)
    sw x5, 20(a0)
    sw x6, 24(a0)
    sw x7, 28(a0)
    sw x8, 32(a0)
    sw x9, 36(a0)
    sw x10, 40(a0)
    sw x11, 44(a0)
    sw x12, 48(a0)
    sw x13, 52(a0)
    sw x14, 56(a0)
    sw x15, 60(a0)
    sw x16, 64(a0)
    sw x17, 68(a0)
    sw x18, 72(a0)
    sw x19, 76(a0)
    sw x20, 80(a0)
    sw x21, 84(a0)
    sw x22, 88(a0)
    sw x23, 92(a0)
    sw x24, 96(a0)
    sw x25, 100(a0)
    sw x26, 104(a0)
    sw x27, 108(a0)
    sw x28, 112(a0)
    sw x29, 116(a0)
    sw x30, 120(a0)
    sw x31, 124(a0)
    
    # Examine trap cause
    csrr s1, mcause
    srli s2, s1, 31     # Extract interrupt bit
    bnez s2, abort_handler
    
    # Check if trap is a misaligned load (code 4)
    andi s1, s1, 0x7F
    li s2, 4
    bne s1, s2, abort_handler
    
    # Get faulting instruction
    csrr s3, mepc
    csrr s4, mtval      # Get misaligned address
    
    # Check if this is an instruction fetch issue
    beq s3, s4, abort_handler
    
    # Load the faulting instruction
    lw s5, 0(s3)
    
    # Check if it's an lw instruction
    # Check opcode (bits 0-6)
    andi s6, s5, 0x7F
    li s7, 0x03         # LOAD opcode
    bne s6, s7, abort_handler
    
    # Check function code (bits 12-14)
    srli s6, s5, 12
    andi s6, s6, 0x7
    li s7, 2            # lw funct3
    bne s6, s7, abort_handler
    
    # Extract destination register (rd) - bits 7-11
    srli s6, s5, 7
    andi s6, s6, 0x1F
    
    # Read 4 bytes sequentially from misaligned address
    lbu s7, 0(s4)       # First byte (LSB)
    lbu s8, 1(s4)       # Second byte
    slli s8, s8, 8
    or s7, s7, s8
    lbu s8, 2(s4)       # Third byte
    slli s8, s8, 16
    or s7, s7, s8
    lbu s8, 3(s4)       # Fourth byte (MSB)
    slli s8, s8, 24
    or s7, s7, s8       # s7 now contains the 32-bit value
    
    # Compute address in register save area and store value
    slli s8, s6, 2      # s8 = rd * 4
    add s8, a0, s8      # s8 = stack + offset
    sw s7, 0(s8)        # Store to register save area
    
    # Special handling for SP register (x2)
    li s9, 2
    bne s6, s9, skip_sp_adjustment
    lw s9, 8(a0)        # Load original SP value from save area
    csrw mscratch, s9   # Update mscratch
skip_sp_adjustment:
    
    # Advance program counter past the faulting instruction
    addi s3, s3, 4
    csrw mepc, s3
    
    j restore_regs
    
abort_handler:
    # Pass to default exception handler
    lw x1, 4(a0)
    lw x3, 12(a0)
    lw x4, 16(a0)
    lw x5, 20(a0)
    lw x6, 24(a0)
    lw x7, 28(a0)
    lw x8, 32(a0)
    lw x9, 36(a0)
    lw x10, 40(a0)
    lw x11, 44(a0)
    lw x12, 48(a0)
    lw x13, 52(a0)
    lw x14, 56(a0)
    lw x15, 60(a0)
    lw x16, 64(a0)
    lw x17, 68(a0)
    lw x18, 72(a0)
    lw x19, 76(a0)
    lw x20, 80(a0)
    lw x21, 84(a0)
    lw x22, 88(a0)
    lw x23, 92(a0)
    lw x24, 96(a0)
    lw x25, 100(a0)
    lw x26, 104(a0)
    lw x27, 108(a0)
    lw x28, 112(a0)
    lw x29, 116(a0)
    lw x30, 120(a0)
    lw x31, 124(a0)
    addi a0, a0, 128
    csrrw a0, mscratch, a0
    j terminate

restore_regs:
    # Restore all registers
    lw x1, 4(a0)
    lw x3, 12(a0)
    lw x4, 16(a0)
    lw x5, 20(a0)
    lw x6, 24(a0)
    lw x7, 28(a0)
    lw x8, 32(a0)
    lw x9, 36(a0)
    lw x10, 40(a0)
    lw x11, 44(a0)
    lw x12, 48(a0)
    lw x13, 52(a0)
    lw x14, 56(a0)
    lw x15, 60(a0)
    lw x16, 64(a0)
    lw x17, 68(a0)
    lw x18, 72(a0)
    lw x19, 76(a0)
    lw x20, 80(a0)
    lw x21, 84(a0)
    lw x22, 88(a0)
    lw x23, 92(a0)
    lw x24, 96(a0)
    lw x25, 100(a0)
    lw x26, 104(a0)
    lw x27, 108(a0)
    lw x28, 112(a0)
    lw x29, 116(a0)
    lw x30, 120(a0)
    lw x31, 124(a0)
    addi a0, a0, 128
    
    # Restore original stack pointer
    csrrw a0, mscratch, a0
    
    # Return from exception
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

