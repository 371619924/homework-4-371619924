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
	# --- Swap sp and mscratch so that we use the kernel stack ---
    csrr    t8, mscratch      # t8 = kernel stack pointer
    csrw    mscratch, sp      # mscratch gets original sp
    mv      sp, t8           # sp now points to kernel stack
    
    addi    sp, sp, -120

    sw      ra,   0(sp)
    sw      gp,   4(sp)
    sw      tp,   8(sp)
    sw      t0,  12(sp)
    sw      t1,  16(sp)
    sw      t2,  20(sp)
    sw      s0,  24(sp)
    sw      s1,  28(sp)
    sw      a0,  32(sp)
    sw      a1,  36(sp)
    sw      a2,  40(sp)
    sw      a3,  44(sp)
    sw      a4,  48(sp)
    sw      a5,  52(sp)
    sw      a6,  56(sp)
    sw      a7,  60(sp)
    sw      s2,  64(sp)
    sw      s3,  68(sp)
    sw      s4,  72(sp)
    sw      s5,  76(sp)
    sw      s6,  80(sp)
    sw      s7,  84(sp)
    sw      s8,  88(sp)
    sw      s9,  92(sp)
    sw      s10, 96(sp)
    sw      s11,100(sp)
    sw      t3, 104(sp)
    sw      t4, 108(sp)
    sw      t5, 112(sp)
    sw      t6, 116(sp)

    # --- Examine the exception ---
    csrr    t0, mcause          # t0 = mcause
    li      t1, 0x7FFFFFFF      # Mask to clear interrupt bit
    and     t0, t0, t1          # t0 now holds the exception code
    li      t1, 4             # Misaligned load exception code (4)
    bne     t0, t1, call_terminate  # Not misaligned load? Jump to terminate

    # --- Check that the faulting instruction is an lw ---
    csrr    t2, mepc          # t2 = address of faulting instruction
    lw      t3, 0(t2)         # t3 = faulting instruction word

    # Check opcode (bits [6:0] should be 0x03 for load instructions)
    andi    t4, t3, 0x7F
    li      t5, 0x03
    bne     t4, t5, call_terminate

    # Check funct3 field (bits [14:12] should equal 2 for lw)
    srli    t4, t3, 12
    andi    t4, t4, 0x7
    li      t5, 2
    bne     t4, t5, call_terminate

    # --- We have a misaligned lw. Determine the destination register ---
    # (rd is in bits [11:7])
    srli    t4, t3, 7
    andi    t4, t4, 0x1F     # t4 = destination register (rd)
    # If rd is 0 (or 2, which is sp and not saved), we do nothing.
    beqz    t4, misaligned_done
    li      t5, 2
    beq     t4, t5, misaligned_done

    # Compute offset into saved register block.
    # Our saved order: x1 (rd==1) is at offset 0; for registers >2, use: offset = (rd - 2)*4.
    addi    t5, t4, -2       # t5 = rd - 2
    slli    t5, t5, 2        # t5 = (rd - 2) * 4

misaligned_done:
    # --- Perform misaligned load as 4 separate byte loads ---
    csrr    t6, mtval         # t6 = faulting memory address (misaligned)
    lbu     t7, 0(t6)         # Load byte 0 (LSB)
    lbu     t8, 1(t6)         # Load byte 1
    lbu     t9, 2(t6)         # Load byte 2
    lbu     t0, 3(t6)         # Load byte 3 (MSB)

    slli    t0, t0, 24       # Shift byte3 to bits 31:24
    slli    t9, t9, 16       # Shift byte2 to bits 23:16
    slli    t8, t8, 8        # Shift byte1 to bits 15:8
    or      t7, t7, t8       # t7 = byte0 | (byte1 << 8)
    or      t7, t7, t9       # t7 |= (byte2 << 16)
    or      t7, t7, t0       # t7 now holds the assembled 32-bit word

    # --- Patch the destination register in our saved register block ---
    # Only update if rd was not 0 or 2.
    bnez    t4, update_reg
    j       skip_update_reg
update_reg:
    add     t5, sp, t5       # Compute address of saved register in our block
    sw      t7, 0(t5)        # Overwrite saved value with our loaded word
skip_update_reg:

    # --- Advance mepc by 4 so that the faulting lw is skipped ---
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0

    # --- Restore registers and return via mret ---
restore_and_return:
    lw      t6, 116(sp)      # Restore registers in reverse order:
    lw      t5, 112(sp)
    lw      t4, 108(sp)
    lw      t3, 104(sp)
    lw      s11,100(sp)
    lw      s10, 96(sp)
    lw      s9,  92(sp)
    lw      s8,  88(sp)
    lw      s7,  84(sp)
    lw      s6,  80(sp)
    lw      s5,  76(sp)
    lw      s4,  72(sp)
    lw      s3,  68(sp)
    lw      s2,  64(sp)
    lw      a7,  60(sp)
    lw      a6,  56(sp)
    lw      a5,  52(sp)
    lw      a4,  48(sp)
    lw      a3,  44(sp)
    lw      a2,  40(sp)
    lw      a1,  36(sp)
    lw      a0,  32(sp)
    lw      s1,  28(sp)
    lw      s0,  24(sp)
    lw      t2,  20(sp)
    lw      t1,  16(sp)
    lw      t0,  12(sp)
    lw      tp,   8(sp)
    lw      gp,   4(sp)
    lw      ra,   0(sp)
    addi    sp,   sp, 120

    # Swap back sp and mscratch
    csrr    t8, mscratch
    csrw    mscratch, sp
    mv      sp, t8

    mret                    # Return to faulting program

    # --- If not a misaligned lw, jump to the terminate routine ---
call_terminate:
    lw      t6, 116(sp)
    lw      t5, 112(sp)
    lw      t4, 108(sp)
    lw      t3, 104(sp)
    lw      s11,100(sp)
    lw      s10, 96(sp)
    lw      s9,  92(sp)
    lw      s8,  88(sp)
    lw      s7,  84(sp)
    lw      s6,  80(sp)
    lw      s5,  76(sp)
    lw      s4,  72(sp)
    lw      s3,  68(sp)
    lw      s2,  64(sp)
    lw      a7,  60(sp)
    lw      a6,  56(sp)
    lw      a5,  52(sp)
    lw      a4,  48(sp)
    lw      a3,  44(sp)
    lw      a2,  40(sp)
    lw      a1,  36(sp)
    lw      a0,  32(sp)
    lw      s1,  28(sp)
    lw      s0,  24(sp)
    lw      t2,  20(sp)
    lw      t1,  16(sp)
    lw      t0,  12(sp)
    lw      tp,   8(sp)
    lw      gp,   4(sp)
    lw      ra,   0(sp)
    addi    sp,   sp, 120

    csrr    t8, mscratch
    csrw    mscratch, sp
    mv      sp, t8

    j       terminate         # Jump to the default terminate routine

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

