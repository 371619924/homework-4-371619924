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
    # --- 交换 sp 和 mscratch，使用内核栈 ---
    csrr    x24, mscratch      # x24 = 内核栈指针
    csrw    mscratch, sp       # mscratch = 原始 sp
    mv      sp, x24            # sp 现在指向内核栈

    # --- 预留空间并保存所有寄存器 ---
    addi    sp, sp, -128
    sw      x0,   0(sp)
    sw      x1,   4(sp)
    sw      x2,   8(sp)
    sw      x3,  12(sp)
    sw      x4,  16(sp)
    sw      x5,  20(sp)
    sw      x6,  24(sp)
    sw      x7,  28(sp)
    sw      x8,  32(sp)
    sw      x9,  36(sp)
    sw      x10, 40(sp)
    sw      x11, 44(sp)
    sw      x12, 48(sp)
    sw      x13, 52(sp)
    sw      x14, 56(sp)
    sw      x15, 60(sp)
    sw      x16, 64(sp)
    sw      x17, 68(sp)
    sw      x18, 72(sp)
    sw      x19, 76(sp)
    sw      x20, 80(sp)
    sw      x21, 84(sp)
    sw      x22, 88(sp)
    sw      x23, 92(sp)
    sw      x24, 96(sp)
    sw      x25, 100(sp)
    sw      x26, 104(sp)
    sw      x27, 108(sp)
    sw      x28, 112(sp)
    sw      x29, 116(sp)
    sw      x30, 120(sp)
    sw      x31, 124(sp)


    # --- 读取 mcause 检查异常类型 ---
    csrr    t0, mcause        # t0 = mcause
    li      t1, 0x7FFFFFFF    # 清除最高位 (Interrupt bit)
    and     t0, t0, t1        # t0 现在只包含异常代码
    li      t1, 4             # Misaligned Load Exception (4)
    bne     t0, t1, call_terminate  # 不是 misaligned load？终止

    # --- 读取 mepc 处的指令 ---
    csrr    t2, mepc          # t2 = 触发异常的指令地址
    lw      t3, 0(t2)         # t3 = 取指令

    # --- 确保是 lw 指令 ---
    andi    t4, t3, 0x7F      # 提取 opcode (bits [6:0])
    li      t5, 0x03
    bne     t4, t5, call_terminate  # 不是 load 指令？终止

    srli    t4, t3, 12
    andi    t4, t4, 0x7       # 提取 funct3 (bits [14:12])
    li      t5, 2             # lw 的 funct3 = 2
    bne     t4, t5, call_terminate  # 不是 lw？终止

    # --- 获取 rd (目的寄存器) ---
    srli    t4, t3, 7
    andi    t4, t4, 0x1F      # t4 = 目的寄存器 rd

    # --- 读取 misaligned 地址 ---
    csrr    t6, mtval         # t6 = 访问的 misaligned 地址

    # --- 逐字节加载并拼接 ---
    lbu     t7, 0(t6)         # 低字节
    lbu     t8, 1(t6)         # 次低字节
    lbu     t9, 2(t6)         # 次高字节
    lbu     t0, 3(t6)         # 高字节

    slli    t0, t0, 24
    slli    t9, t9, 16
    slli    t8, t8, 8
    or      t7, t7, t8
    or      t7, t7, t9
    or      t7, t7, t0        # t7 现在包含完整的 32 位值

    # --- 更新目的寄存器的值 ---
    li      t5, 0
    beq     t4, t5, misaligned_done  # rd == x0？跳过
    li      t5, 2
    beq     t4, t5, misaligned_done  # rd == x2 (sp)？跳过

    # 计算 rd 在保存区的偏移量
    addi    t5, t4, -1
    slli    t5, t5, 2         # 偏移量 = (rd-1) * 4
    add     t5, sp, t5
    sw      t7, 0(t5)         # 写回保存的寄存器

misaligned_done:
    # --- 跳过 lw 指令 ---
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0

    # --- 恢复所有寄存器 ---
    lw      t6, 124(sp)
    lw      t5, 120(sp)
    lw      t4, 116(sp)
    lw      t3, 112(sp)
    lw      s11,108(sp)
    lw      s10,104(sp)
    lw      s9, 100(sp)
    lw      s8, 96(sp)
    lw      s7, 92(sp)
    lw      s6, 88(sp)
    lw      s5, 84(sp)
    lw      s4, 80(sp)
    lw      s3, 76(sp)
    lw      s2, 72(sp)
    lw      a7, 68(sp)
    lw      a6, 64(sp)
    lw      a5, 60(sp)
    lw      a4, 56(sp)
    lw      a3, 52(sp)
    lw      a2, 48(sp)
    lw      a1, 44(sp)
    lw      a0, 40(sp)
    lw      s1, 36(sp)
    lw      s0, 32(sp)
    lw      t2, 28(sp)
    lw      t1, 24(sp)
    lw      t0, 20(sp)
    lw      tp, 16(sp)
    lw      gp, 12(sp)
    lw      sp,  8(sp)
    lw      ra,  4(sp)
    lw      x0,  0(sp)
    addi    sp, sp, 128

    csrr    t8, mscratch
    csrw    mscratch, sp
    mv      sp, t8

    mret                    # 返回用户态

call_terminate:
    j       terminate



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

