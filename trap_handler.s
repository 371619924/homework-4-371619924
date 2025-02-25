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
    # Save kernel SP and use it instead of user SP
    csrrw a1, mscratch, a1
    
    # Allocate space on kernel stack
    addi a1, a1, -128
    
    # Store each register to its allocated space
    sw x0, 0(a1)
    sw x1, 4(a1)
    sw x2, 8(a1)
    sw x3, 12(a1)
    sw x4, 16(a1)
    sw x5, 20(a1)
    sw x6, 24(a1)
    sw x7, 28(a1)
    sw x8, 32(a1)
    sw x9, 36(a1)
    sw x10, 40(a1)
    sw x11, 44(a1)
    sw x12, 48(a1)
    sw x13, 52(a1)
    sw x14, 56(a1)
    sw x15, 60(a1)
    sw x16, 64(a1)
    sw x17, 68(a1)
    sw x18, 72(a1)
    sw x19, 76(a1)
    sw x20, 80(a1)
    sw x21, 84(a1)
    sw x22, 88(a1)
    sw x23, 92(a1)
    sw x24, 96(a1)
    sw x25, 100(a1)
    sw x26, 104(a1)
    sw x27, 108(a1)
    sw x28, 112(a1)
    sw x29, 116(a1)
    sw x30, 120(a1)
    sw x31, 124(a1)
    
    # Identify exception type from mcause
    csrr s1, mcause
    srli s2, s1, 31      # Extract interrupt flag
    bnez s2, not_load_exception
    andi s1, s1, 0x1F    # Extract exception code
    li s2, 4             # Code 4 = misaligned load
    bne s1, s2, not_load_exception
    
    # Now we know this is a misaligned load exception
    # Get the faulting instruction address and the bad address
    csrr s3, mepc        # s3 = instruction pointer
    csrr s4, mtval       # s4 = faulting address
    
    # Load the instruction that caused the fault
    lw s5, 0(s3)
    
    # Extract and check opcode (bits 0-6)
    li s6, 0x7F
    and s6, s5, s6       # s6 = opcode
    li s7, 0x03          # 0x03 = LOAD opcode
    bne s6, s7, not_load_exception
    
    # Extract and check function code (bits 12-14)
    srli s6, s5, 12
    andi s6, s6, 0x7     # s6 = funct3
    li s7, 2             # 2 = lw function code
    bne s6, s7, not_load_exception
    
    # Find destination register (bits 7-11)
    srli s6, s5, 7
    andi s6, s6, 0x1F    # s6 = rd
    
    # Manually load bytes from misaligned address
    # Use byte-by-byte loading and shifting
    li s7, 0             # Will hold final value
    lbu s8, 0(s4)        # First byte
    or s7, s7, s8
    lbu s8, 1(s4)        # Second byte
    slli s8, s8, 8
    or s7, s7, s8
    lbu s8, 2(s4)        # Third byte
    slli s8, s8, 16
    or s7, s7, s8
    lbu s8, 3(s4)        # Fourth byte
    slli s8, s8, 24
    or s7, s7, s8        # s7 now contains all 4 bytes
    
    # Calculate register save location and store value
    # s6 = rd (destination register number)
    li s8, 4
    mul s8, s6, s8       # s8 = rd * 4 (offset in save area)
    add s8, a1, s8       # s8 = save address
    sw s7, 0(s8)         # Store assembled value
    
    # Handle SP register (x2) specially
    li s9, 2
    bne s6, s9, standard_reg
    # If rd is sp (x2), update mscratch with original sp value
    lw s9, 8(a1)         # Load saved sp from register area
    csrw mscratch, s9    # Update mscratch
standard_reg:
    
    # Advance PC past this instruction
    addi s3, s3, 4
    csrw mepc, s3
    
    # Restore registers and return
    j complete_trap
    
not_load_exception:
    # Fall through to default exception handler
    lw x1, 4(a1)
    lw x3, 12(a1)
    lw x4, 16(a1)
    lw x5, 20(a1)
    lw x6, 24(a1)
    lw x7, 28(a1)
    lw x8, 32(a1)
    lw x9, 36(a1)
    lw x10, 40(a1)
    lw x11, 44(a1)
    lw x12, 48(a1)
    lw x13, 52(a1)
    lw x14, 56(a1)
    lw x15, 60(a1)
    lw x16, 64(a1)
    lw x17, 68(a1)
    lw x18, 72(a1)
    lw x19, 76(a1)
    lw x20, 80(a1)
    lw x21, 84(a1)
    lw x22, 88(a1)
    lw x23, 92(a1)
    lw x24, 96(a1)
    lw x25, 100(a1)
    lw x26, 104(a1)
    lw x27, 108(a1)
    lw x28, 112(a1)
    lw x29, 116(a1)
    lw x30, 120(a1)
    lw x31, 124(a1)
    addi a1, a1, 128
    csrrw a1, mscratch, a1
    j terminate

complete_trap:
    # Restore all registers from save area
    lw x1, 4(a1)
    lw x3, 12(a1)
    lw x4, 16(a1)
    lw x5, 20(a1)
    lw x6, 24(a1)
    lw x7, 28(a1)
    lw x8, 32(a1)
    lw x9, 36(a1)
    lw x10, 40(a1)
    lw x11, 44(a1)
    lw x12, 48(a1)
    lw x13, 52(a1)
    lw x14, 56(a1)
    lw x15, 60(a1)
    lw x16, 64(a1)
    lw x17, 68(a1)
    lw x18, 72(a1)
    lw x19, 76(a1)
    lw x20, 80(a1)
    lw x21, 84(a1)
    lw x22, 88(a1)
    lw x23, 92(a1)
    lw x24, 96(a1)
    lw x25, 100(a1)
    lw x26, 104(a1)
    lw x27, 108(a1)
    lw x28, 112(a1)
    lw x29, 116(a1)
    lw x30, 120(a1)
    lw x31, 124(a1)
    addi a1, a1, 128
    
    # Restore user stack pointer
    csrrw a1, mscratch, a1
    
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

