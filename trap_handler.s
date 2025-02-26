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
### Trap handler


    .equ FRAME_SIZE, 112         # Total bytes for 28 registers (ra, t0-t6, s0-s11, a0-a7)

__mtrap:
    # Save all registers
    addi   sp, sp, -FRAME_SIZE
    sw     ra,   0(sp)
    sw     t0,   4(sp)
    sw     t1,   8(sp)
    sw     t2,  12(sp)
    sw     t3,  16(sp)
    sw     t4,  20(sp)
    sw     t5,  24(sp)
    sw     t6,  28(sp)
    sw     s0,  32(sp)
    sw     s1,  36(sp)
    sw     s2,  40(sp)
    sw     s3,  44(sp)
    sw     s4,  48(sp)
    sw     s5,  52(sp)
    sw     s6,  56(sp)
    sw     s7,  60(sp)
    sw     s8,  64(sp)
    sw     s9,  68(sp)
    sw     s10, 72(sp)
    sw     s11, 76(sp)
    sw     a0,  80(sp)
    sw     a1,  84(sp)
    sw     a2,  88(sp)
    sw     a3,  92(sp)
    sw     a4,  96(sp)
    sw     a5, 100(sp)
    sw     a6, 104(sp)
    sw     a7, 108(sp)

    # Examine the cause of the trap.
    csrr   t0, mcause
    li     t1, 4             # Use the literal 4 for misaligned load word exception
    beq    t0, t1, handle_misaligned_load

    # Not a misaligned load word – jump to the default terminate routine.
    j terminate

handle_misaligned_load:
    # Read the faulting address from mtval.
    csrr   t1, mtval
    # Compute offset = fault_addr mod 4 (i.e. the lower 2 bits)
    andi   t2, t1, 3
    # Compute the aligned address: t3 = fault_addr - offset
    add    t3, t1, zero
    sub    t3, t3, t2

    # Load the two adjacent aligned words.
    lw     t4, 0(t3)     # lower aligned word
    lw     t5, 4(t3)     # upper aligned word

    # Patch the misaligned load result based on offset.
    beq    t2, zero, misaligned_case0
    li     t7, 1
    beq    t2, t7, misaligned_case1
    li     t7, 2
    beq    t2, t7, misaligned_case2
    li     t7, 3
    beq    t2, t7, misaligned_case3

misaligned_case0:
    mv     t6, t4
    j      misaligned_finish

misaligned_case1:
    # For offset = 1: result = (t4 >> 8) | (t5 << 24)
    srl    t6, t4, 8
    sll    t7, t5, 24
    or     t6, t6, t7
    j      misaligned_finish

misaligned_case2:
    # For offset = 2: result = (t4 >> 16) | (t5 << 16)
    srl    t6, t4, 16
    sll    t7, t5, 16
    or     t6, t6, t7
    j      misaligned_finish

misaligned_case3:
    # For offset = 3: result = (t4 >> 24) | (t5 << 8)
    srl    t6, t4, 24
    sll    t7, t5, 8
    or     t6, t6, t7

misaligned_finish:
    # Write the patched result back into the saved a0 slot (offset 80 from sp).
    sw     t6, 80(sp)

    # Increment mepc to resume execution at the next instruction.
    csrr   t0, mepc
    addi   t0, t0, 4
    csrw   mepc, t0

    # Restore all registers
    lw     ra,   0(sp)
    lw     t0,   4(sp)
    lw     t1,   8(sp)
    lw     t2,  12(sp)
    lw     t3,  16(sp)
    lw     t4,  20(sp)
    lw     t5,  24(sp)
    lw     t6,  28(sp)
    lw     s0,  32(sp)
    lw     s1,  36(sp)
    lw     s2,  40(sp)
    lw     s3,  44(sp)
    lw     s4,  48(sp)
    lw     s5,  52(sp)
    lw     s6,  56(sp)
    lw     s7,  60(sp)
    lw     s8,  64(sp)
    lw     s9,  68(sp)
    lw     s10, 72(sp)
    lw     s11, 76(sp)
    lw     a0,  80(sp)
    lw     a1,  84(sp)
    lw     a2,  88(sp)
    lw     a3,  92(sp)
    lw     a4,  96(sp)
    lw     a5, 100(sp)
    lw     a6, 104(sp)
    lw     a7, 108(sp)
    addi   sp, sp, FRAME_SIZE

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

