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
    csrrw sp, mscratch, sp  
    addi sp, sp, -72
    sw ra, 0(sp)
    ...
    csrr t0, mcause
    li t1, 4  # Misaligned Load Address
    li t2, 6  # Misaligned Store Address
    beq t0, t1, misaligned_access
    beq t0, t2, misaligned_access
    j terminate

misaligned_access:
    csrr t4, mtval  # 获取未对齐地址
    csrr t0, mepc   # 获取指令地址
    lw t1, 0(t0)    # 读取指令

    # 解析 opcode 判断是 lw 还是 sw
    li t2, 0x00002003
    and t3, t1, t2
    beq t3, t2, handle_lw

    li t2, 0x00002023
    and t3, t1, t2
    beq t3, t2, handle_sw

    j terminate  # 不是 lw/sw，终止

handle_lw:
    # 解析 rs1, rd, 计算目标地址
    srli t5, t1, 7  # rd
    andi t5, t5, 0x1F
    srli t6, t1, 15 # rs1
    andi t6, t6, 0x1F
    add t6, t6, t4  # rs1 + 偏移

    # 处理未对齐加载
    lbu t3, 0(t6)
    lbu t4, 1(t6)
    slli t4, t4, 8
    or t3, t3, t4
    lbu t4, 2(t6)
    slli t4, t4, 16
    or t3, t3, t4
    lbu t4, 3(t6)
    slli t4, t4, 24
    or t3, t3, t4

    # 存入 rd
    addi t5, t5, 32
    add t5, sp, t5
    sw t3, 0(t5)

    j resume_execution

handle_sw:
    # 解析 rs1, rs2, 计算目标地址
    srli t6, t1, 15 # rs1
    andi t6, t6, 0x1F
    srli t5, t1, 20 # rs2
    andi t5, t5, 0x1F
    add t6, t6, t4  # rs1 + 偏移

    # 从 rs2 获取值
    addi t5, t5, 32
    add t5, sp, t5
    lw t3, 0(t5)

    # 处理未对齐存储
    sb t3, 0(t6)
    srli t3, t3, 8
    sb t3, 1(t6)
    srli t3, t3, 8
    sb t3, 2(t6)
    srli t3, t3, 8
    sb t3, 3(t6)

resume_execution:
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0

    # 恢复寄存器
    lw ra, 0(sp)
    lw t0, 4(sp)
    ...
    addi sp, sp, 72
    csrrw sp, mscratch, sp
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

