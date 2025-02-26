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
    # 交换 sp 和 mscratch，切换到内核栈
    csrrw sp, mscratch, sp
    
    # 分配栈空间保存所有寄存器（32 * 4 bytes = 128 bytes）
    addi sp, sp, -128

    # 保存所有寄存器到栈
    sw x0, 0(sp)
    sw x1, 4(sp)
    sw x2, 8(sp)  # 原始用户栈指针
    sw x3, 12(sp)
    sw x4, 16(sp)
    sw x5, 20(sp)
    sw x6, 24(sp)
    sw x7, 28(sp)
    sw x8, 32(sp)
    sw x9, 36(sp)
    sw x10, 40(sp)
    sw x11, 44(sp)
    sw x12, 48(sp)
    sw x13, 52(sp)
    sw x14, 56(sp)
    sw x15, 60(sp)
    sw x16, 64(sp)
    sw x17, 68(sp)
    sw x18, 72(sp)
    sw x19, 76(sp)
    sw x20, 80(sp)
    sw x21, 84(sp)
    sw x22, 88(sp)
    sw x23, 92(sp)
    sw x24, 96(sp)
    sw x25, 100(sp)
    sw x26, 104(sp)
    sw x27, 108(sp)
    sw x28, 112(sp)
    sw x29, 116(sp)
    sw x30, 120(sp)
    sw x31, 124(sp)
    
    # 获取 mcause，检查是否是异常还是中断
    csrr t0, mcause
    li t1, 0x80000000    # 最高位掩码
    and t2, t0, t1
    bnez t2, go_terminate  # 如果是中断，直接终止

    # 取 mcause 低 31 位
    li t2, 0x7FFFFFFF  # 掩码清除最高位
    and t0, t0, t2      # 取得异常代码

    # 检查是否是取指令 misaligned
    li t1, 0x0          # 取指令地址未对齐异常代码
    beq t0, t1, go_terminate  # 如果是取指令异常，终止

    # 检查是否是 load misaligned
    li t1, 4            # Load Address Misaligned 异常代码
    bne t0, t1, go_terminate  # 不是 load misaligned 直接终止

    # 通过 mepc 和 mtval 区分是取指令异常还是 lw
    csrr t3, mepc      # 获取 mepc（导致异常的 PC）
    csrr t4, mtval     # 获取 mtval（发生错误的地址）
    beq t3, t4, go_terminate  # 如果 mepc == mtval，说明是取指令异常，终止

    # 读取导致异常的指令
    lw t1, 0(t3)       # t1 = 指令值

    # 检查是否是 lw 指令
    li t2, 0x7F        # Opcode 掩码（bits 0-6）
    and t3, t1, t2     # 提取 opcode
    li t2, 0x03        # Load opcode（0000011）
    bne t3, t2, go_terminate  # 不是 load 指令，终止

    li t2, 0x7000      # Funct3 掩码（bits 12-14）
    and t3, t1, t2     # 提取 funct3
    li t2, 0x2000      # Funct3 = 010（lw）
    bne t3, t2, go_terminate  # 不是 lw（可能是 lb, lh 等），终止

    # 提取目的寄存器（rd），bits 7-11
    li t2, 0xF80       # rd 掩码
    and t3, t1, t2
    srli t3, t3, 7     # 右移得到寄存器编号

    # 获取未对齐的加载地址
    csrr t4, mtval     # t4 = 触发异常的地址

    # 逐字节读取并拼接为 32-bit
    lbu t5, 0(t4)      # 低 8 位
    lbu t6, 1(t4)      # 次低 8 位
    slli t6, t6, 8
    or t5, t5, t6

    lbu t6, 2(t4)      # 次高 8 位
    slli t6, t6, 16
    or t5, t5, t6

    lbu t6, 3(t4)      # 高 8 位
    slli t6, t6, 24
    or t5, t5, t6

    # 计算 rd 在栈中的位置
    slli t6, t3, 2     # t6 = rd * 4
    add t6, t6, sp     # t6 = 栈中 rd 位置

    # 存入 rd 在栈中的值
    sw t5, 0(t6)

    # 修正 mepc，跳过导致异常的指令
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0

    # 恢复所有寄存器
    lw x1, 4(sp)
    lw x3, 12(sp)
    lw x4, 16(sp)
    lw x5, 20(sp)
    lw x6, 24(sp)
    lw x7, 28(sp)
    lw x8, 32(sp)
    lw x9, 36(sp)
    lw x10, 40(sp)
    lw x11, 44(sp)
    lw x12, 48(sp)
    lw x13, 52(sp)
    lw x14, 56(sp)
    lw x15, 60(sp)
    lw x16, 64(sp)
    lw x17, 68(sp)
    lw x18, 72(sp)
    lw x19, 76(sp)
    lw x20, 80(sp)
    lw x21, 84(sp)
    lw x22, 88(sp)
    lw x23, 92(sp)
    lw x24, 96(sp)
    lw x25, 100(sp)
    lw x26, 104(sp)
    lw x27, 108(sp)
    lw x28, 112(sp)
    lw x29, 116(sp)
    lw x30, 120(sp)
    lw x31, 124(sp)

    # 释放栈空间并恢复用户栈
    addi sp, sp, 128
    csrrw sp, mscratch, sp

    # 从 trap 返回
    mret

go_terminate:
    # 恢复栈并终止
    addi sp, sp, 128
    csrrw sp, mscratch, sp
    j terminate




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

