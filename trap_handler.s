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
    csrrw sp, mscratch, sp       # Swap to kernel stack
    addi sp, sp, -(31*4)         # Allocate space for x1-x31

    # Save all registers x1 to x31
    sw x1, 0*4(sp)
    sw x2, 1*4(sp)
    sw x3, 2*4(sp)
    sw x4, 3*4(sp)
    sw x5, 4*4(sp)
    sw x6, 5*4(sp)
    sw x7, 6*4(sp)
    sw x8, 7*4(sp)
    sw x9, 8*4(sp)
    sw x10, 9*4(sp)
    sw x11, 10*4(sp)
    sw x12, 11*4(sp)
    sw x13, 12*4(sp)
    sw x14, 13*4(sp)
    sw x15, 14*4(sp)
    sw x16, 15*4(sp)
    sw x17, 16*4(sp)
    sw x18, 17*4(sp)
    sw x19, 18*4(sp)
    sw x20, 19*4(sp)
    sw x21, 20*4(sp)
    sw x22, 21*4(sp)
    sw x23, 22*4(sp)
    sw x24, 23*4(sp)
    sw x25, 24*4(sp)
    sw x26, 25*4(sp)
    sw x27, 26*4(sp)
    sw x28, 27*4(sp)
    sw x29, 28*4(sp)
    sw x30, 29*4(sp)
    sw x31, 30*4(sp)

    csrr t0, mcause              # Check exception cause
    li t1, 4
    bne t0, t1, terminate       # Not misaligned load

    csrr a0, mepc               # Load faulting instruction
    lw t0, 0(a0)
    andi t1, t0, 0x7F          # Check opcode
    li t2, 0x03
    bne t1, t2, terminate       # Not a load instruction
    srli t1, t0, 12
    andi t1, t1, 0x7           # Check funct3
    li t2, 0x2
    bne t1, t2, terminate       # Not lw

    srli t1, t0, 7             # Extract rd
    andi t1, t1, 0x1F

    csrr a0, mtval              # Faulting address
    lbu t2, 0(a0)              # Load bytes
    lbu t3, 1(a0)
    lbu t4, 2(a0)
    lbu t5, 3(a0)

    slli t5, t5, 24            # Combine bytes
    slli t4, t4, 16
    or t5, t5, t4
    slli t3, t3, 8
    or t5, t5, t3
    or t5, t5, t2

    addi t1, t1, -1            # Calculate offset
    slli t1, t1, 2
    add t1, sp, t1
    sw t5, 0(t1)               # Update saved register

    csrr t0, mepc              # Increment mepc
    addi t0, t0, 4
    csrw mepc, t0

restore_registers:
    # Restore all registers
    lw x1, 0*4(sp)
    lw x2, 1*4(sp)
    lw x3, 2*4(sp)
    lw x4, 3*4(sp)
    lw x5, 4*4(sp)
    lw x6, 5*4(sp)
    lw x7, 6*4(sp)
    lw x8, 7*4(sp)
    lw x9, 8*4(sp)
    lw x10, 9*4(sp)
    lw x11, 10*4(sp)
    lw x12, 11*4(sp)
    lw x13, 12*4(sp)
    lw x14, 13*4(sp)
    lw x15, 14*4(sp)
    lw x16, 15*4(sp)
    lw x17, 16*4(sp)
    lw x18, 17*4(sp)
    lw x19, 18*4(sp)
    lw x20, 19*4(sp)
    lw x21, 20*4(sp)
    lw x22, 21*4(sp)
    lw x23, 22*4(sp)
    lw x24, 23*4(sp)
    lw x25, 24*4(sp)
    lw x26, 25*4(sp)
    lw x27, 26*4(sp)
    lw x28, 27*4(sp)
    lw x29, 28*4(sp)
    lw x30, 29*4(sp)
    lw x31, 30*4(sp)

    addi sp, sp, 31*4          # Deallocate stack
    csrrw sp, mscratch, sp     # Swap back to user stack
    mret

	
	
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

