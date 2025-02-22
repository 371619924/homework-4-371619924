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
    csrrw   t0, mscratch, sp
    mv      sp, t0
    addi    sp, sp, -124
    sw      ra,   0(sp)
    csrr    t1, mscratch
    sw      t1,   4(sp)
    sw      gp,   8(sp)
    sw      tp,  12(sp)
    sw      t0,  16(sp)
    sw      t1,  20(sp)
    sw      t2,  24(sp)
    sw      s0,  28(sp)
    sw      s1,  32(sp)
    sw      a0,  36(sp)
    sw      a1,  40(sp)
    sw      a2,  44(sp)
    sw      a3,  48(sp)
    sw      a4,  52(sp)
    sw      a5,  56(sp)
    sw      a6,  60(sp)
    sw      a7,  64(sp)
    sw      s2,  68(sp)
    sw      s3,  72(sp)
    sw      s4,  76(sp)
    sw      s5,  80(sp)
    sw      s6,  84(sp)
    sw      s7,  88(sp)
    sw      s8,  92(sp)
    sw      s9,  96(sp)
    sw      s10, 100(sp)
    sw      s11, 104(sp)
    sw      t3, 108(sp)
    sw      t4, 112(sp)
    sw      t5, 116(sp)
    sw      t6, 120(sp)
    csrr    t3, mcause
    li      t4, 4
    bne     t3, t4, trap_unhandled
    csrr    t5, mepc
    lw      t6, 0(t5)
    andi    t7, t6, 0x7F
    li      t0, 0x03
    bne     t7, t0, trap_unhandled
    srli    t7, t6, 12
    andi    t7, t7, 0x7
    li      t0, 0x2
    bne     t7, t0, trap_unhandled
    csrr    t8, mtval
    lbu     t9, 0(t8)
    lbu     t10, 1(t8)
    lbu     t11, 2(t8)
    lbu     t12, 3(t8)
    slli    t10, t10, 8
    slli    t11, t11, 16
    slli    t12, t12, 24
    or      t9, t9, t10
    or      t9, t9, t11
    or      t9, t9, t12
    srli    t7, t6, 7
    andi    t7, t7, 0x1F
    beqz    t7, misaligned_done
    li      t0, 2
    beq     t7, t0, update_x2
    addi    t0, t7, -1
    slli    t0, t0, 2
    add     t0, sp, t0
    sw      t9, 0(t0)
    j       misaligned_done
update_x2:
    sw      t9, 4(sp)
misaligned_done:
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    lw      t6, 120(sp)
    lw      t5, 116(sp)
    lw      t4, 112(sp)
    lw      t3, 108(sp)
    lw      s11, 104(sp)
    lw      s10, 100(sp)
    lw      s9,  96(sp)
    lw      s8,  92(sp)
    lw      s7,  88(sp)
    lw      s6,  84(sp)
    lw      s5,  80(sp)
    lw      s4,  76(sp)
    lw      s3,  72(sp)
    lw      s2,  68(sp)
    lw      a7,  64(sp)
    lw      a6,  60(sp)
    lw      a5,  56(sp)
    lw      a4,  52(sp)
    lw      a3,  48(sp)
    lw      a2,  44(sp)
    lw      a1,  40(sp)
    lw      a0,  36(sp)
    lw      s1,  32(sp)
    lw      s0,  28(sp)
    lw      t2,  24(sp)
    lw      t1,  20(sp)
    lw      t0,  16(sp)
    lw      tp,  12(sp)
    lw      gp,   8(sp)
    lw      t1,   4(sp)
    lw      ra,   0(sp)
    addi    sp, sp, 124
    csrrw   t0, mscratch, sp
    mv      sp, t0
    mret
trap_unhandled:
    addi    sp, sp, 124
    j       terminate


	
	
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

