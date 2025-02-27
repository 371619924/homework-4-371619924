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
    # 切换 sp 与 mscratch，获得内核栈
    csrrw   sp, mscratch, sp

    # 为所有寄存器分配空间（32个寄存器 * 4字节 = 128字节）
    addi    sp, sp, -128

    # 保存所有寄存器到栈中
    sw      x0,   0(sp)
    sw      x1,   4(sp)
    sw      x2,   8(sp)
    sw      x3,   12(sp)
    sw      x4,   16(sp)
    sw      x5,   20(sp)
    sw      x6,   24(sp)
    sw      x7,   28(sp)
    sw      x8,   32(sp)
    sw      x9,   36(sp)
    sw      x10,  40(sp)
    sw      x11,  44(sp)
    sw      x12,  48(sp)
    sw      x13,  52(sp)
    sw      x14,  56(sp)
    sw      x15,  60(sp)
    sw      x16,  64(sp)
    sw      x17,  68(sp)
    sw      x18,  72(sp)
    sw      x19,  76(sp)
    sw      x20,  80(sp)
    sw      x21,  84(sp)
    sw      x22,  88(sp)
    sw      x23,  92(sp)
    sw      x24,  96(sp)
    sw      x25,  100(sp)
    sw      x26,  104(sp)
    sw      x27,  108(sp)
    sw      x28,  112(sp)
    sw      x29,  116(sp)
    sw      x30,  120(sp)
    sw      x31,  124(sp)

    # 检查 mcause 的最高位（中断标志），如果是中断则直接跳转到 terminate
    csrr    t0, mcause         # t0 = mcause
    li      t1, 0x80000000      # 中断位掩码
    and     t2, t0, t1         # t2 = mcause & 0x80000000
    bnez    t2, go_terminate    # 如果是中断，跳转至 terminate

    # 处理异常: 清除最高位得到异常码
    li      t2, 0x7FFFFFFF
    and     t0, t0, t2         # t0 = 异常码
    li      t1, 4              # misaligned load 异常码为 4
    bne     t0, t1, go_terminate  # 如果不是 misaligned load 异常，跳转 terminate

    # 新增：判断异常是否由取指引起（badjump）
    # 若异常是取指引起的，则 mepc 与 mtval 应相等
    csrr    t7, mtval          # t7 = mtval （错误发生的地址）
    csrr    t0, mepc           # t0 = mepc （出错指令地址）
    beq     t7, t0, go_terminate  # 如果 mtval == mepc，则为取指异常，直接跳转 terminate

    # 否则认为是 misaligned load 异常，继续补救处理

    # 从 mepc 取得引起异常的指令
    csrr    t0, mepc           # t0 = 出错指令地址
    lw      t1, 0(t0)          # t1 = 指令内容

    # 检查该指令是否为 lw 指令：
    # 提取 opcode（bits0-6）
    li      t2, 0x7F           # 掩码 0x7F 用于提取 opcode
    and     t3, t1, t2         # t3 = 指令 opcode
    li      t2, 0x03           # lw 指令的 opcode 为 0x03（0000011）
    bne     t3, t2, go_terminate  # 如果不是 load 指令，跳转 terminate

    # 提取 funct3（bits12-14），lw 的 funct3 为 010，即 0x2
    li      t2, 0x7000         # 掩码提取 bits12-14 (0x7000)
    and     t3, t1, t2         # t3 = 指令中 funct3 部分
    li      t2, 0x2000         # lw 指令的 funct3 为 0x2000（010 << 12）
    bne     t3, t2, go_terminate  # 如果不是 lw，跳转 terminate

    # 提取 lw 指令的目标寄存器 rd（bits7-11）
    li      t2, 0xF80          # 掩码提取 rd（bits7-11）
    and     t3, t1, t2         # t3 = rd 字段
    srli    t3, t3, 7          # 得到目标寄存器号

    # 从 mtval 取得 misaligned 数据 load 的地址
    csrr    t4, mtval          # t4 = 错误数据地址

    # 分别加载该地址处的 4 个字节并组合成一个字
    lbu     t5, 0(t4)          # 加载第0字节（最低位）
    lbu     t6, 1(t4)          # 加载第1字节
    slli    t6, t6, 8         # 左移 8 位
    or      t5, t5, t6         # 组合

    lbu     t6, 2(t4)          # 加载第2字节
    slli    t6, t6, 16        # 左移 16 位
    or      t5, t5, t6         # 组合

    lbu     t6, 3(t4)          # 加载第3字节（最高位）
    slli    t6, t6, 24        # 左移 24 位
    or      t5, t5, t6         # 完全组合

    # t5 现在包含正确加载的字

    # 计算保存目标寄存器的栈中地址：rd号 * 4 + sp
    slli    t6, t3, 2          # t6 = rd * 4
    add     t6, t6, sp         # t6 = 保存该寄存器值的栈地址

    # 将正确加载的字存入保存的目标寄存器位置
    sw      t5, 0(t6)

    # 修改 mepc，跳过 faulting 的 lw 指令（假设 lw 长度为4字节）
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0

    # 恢复所有寄存器
    lw      x1,   4(sp)
    lw      x2,   8(sp)
    lw      x3,   12(sp)
    lw      x4,   16(sp)
    lw      x5,   20(sp)
    lw      x6,   24(sp)
    lw      x7,   28(sp)
    lw      x8,   32(sp)
    lw      x9,   36(sp)
    lw      x10,  40(sp)
    lw      x11,  44(sp)
    lw      x12,  48(sp)
    lw      x13,  52(sp)
    lw      x14,  56(sp)
    lw      x15,  60(sp)
    lw      x16,  64(sp)
    lw      x17,  68(sp)
    lw      x18,  72(sp)
    lw      x19,  76(sp)
    lw      x20,  80(sp)
    lw      x21,  84(sp)
    lw      x22,  88(sp)
    lw      x23,  92(sp)
    lw      x24,  96(sp)
    lw      x25,  100(sp)
    lw      x26,  104(sp)
    lw      x27,  108(sp)
    lw      x28,  112(sp)
    lw      x29,  116(sp)
    lw      x30,  120(sp)
    lw      x31,  124(sp)

    # 释放栈空间，并切换回用户栈
    addi    sp, sp, 128
    csrrw   sp, mscratch, sp

    # 返回用户程序
    mret

go_terminate:
    # 恢复栈后跳转至默认 terminate 例程
    addi    sp, sp, 128
    csrrw   sp, mscratch, sp
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

