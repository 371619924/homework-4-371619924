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
    # 使用另一种方式交换栈指针
    mv t0, sp           # 保存用户栈指针到临时寄存器
    csrr sp, mscratch   # 加载内核栈指针
    csrw mscratch, t0   # 将用户栈指针存入mscratch
    
    # 为寄存器分配栈空间
    addi sp, sp, -128
    
    # 以递增顺序保存所有寄存器
    sw x0, 0(sp)
    sw x1, 4(sp)
    sw x2, 8(sp)
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
    
    # 使用不同技术检查异常类型
    csrr a0, mcause      # 读取mcause到a0
    li a1, 0x80000000    # 中断位掩码
    and a2, a0, a1       # 提取中断位
    bnez a2, non_load_handler # 如果是中断，转到非load处理
    
    # 检查异常码部分
    not a1, a1           # 反转掩码为0x7FFFFFFF
    and a0, a0, a1       # 清除中断位，保留异常码
    li a1, 4             # 未对齐load异常码
    bne a0, a1, non_load_handler
    
    # 获取并检查出错指令
    csrr a3, mepc        # 获取指令地址
    csrr a4, mtval       # 获取未对齐地址
    
    # 检查地址是否相同（指令获取异常）
    beq a3, a4, non_load_handler
    
    # 读取出错指令
    lw a0, 0(a3)
    
    # 分析指令 - 使用不同方法来提取opcode和funct3
    # 先将指令右移25位，然后左移25位，再右移25位得到opcode
    srli a1, a0, 25
    slli a1, a1, 25
    srli a1, a0, 25
    xori a1, a1, 0x03    # 应为LOAD opcode (0x03)
    bnez a1, non_load_handler
    
    # 提取funct3 - 先将指令左移17位，再右移29位
    slli a1, a0, 17
    srli a1, a1, 29
    li a2, 2             # lw的funct3
    bne a1, a2, non_load_handler
    
    # 提取目标寄存器 - 先右移7位，再与0x1F相与
    srli a2, a0, 7
    andi a2, a2, 0x1F    # a2 = 目标寄存器rd
    
    # 使用不同方法读取未对齐内存
    li a5, 0             # 初始化结果为0
    
    # 一次读取一个字节并按位置组合
    li a6, 0xFF          # 字节掩码
    lb a7, 0(a4)         # 读取第1个字节
    and a7, a7, a6
    or a5, a5, a7        # 添加到结果
    
    lb a7, 1(a4)         # 读取第2个字节
    and a7, a7, a6
    slli a7, a7, 8
    or a5, a5, a7        # 添加到结果
    
    lb a7, 2(a4)         # 读取第3个字节
    and a7, a7, a6
    slli a7, a7, 16
    or a5, a5, a7        # 添加到结果
    
    lb a7, 3(a4)         # 读取第4个字节
    and a7, a7, a6
    slli a7, a7, 24
    or a5, a5, a7        # a5现在包含完整值
    
    # 计算保存位置的另一种方法
    li a6, 4
    mul a7, a2, a6       # a7 = rd * 4
    add a7, sp, a7       # a7指向保存位置
    sw a5, 0(a7)         # 存储加载的值
    
    # 特殊处理SP寄存器的情况
    li a6, 2             # SP寄存器编号
    beq a2, a6, update_sp
    j skip_sp_update
    
update_sp:
    lw a5, 8(sp)         # 从保存区加载原始SP值
    csrw mscratch, a5    # 更新mscratch
    
skip_sp_update:
    # 修改返回地址
    addi a3, a3, 4       # 增加指令指针
    csrw mepc, a3        # 更新mepc
    
    # 恢复寄存器并返回
    j restore_all
    
non_load_handler:
    # 传递给默认处理程序
    j clean_and_terminate
    
restore_all:
    # 恢复所有寄存器（顺序不同于保存顺序）
    lw x31, 124(sp)
    lw x30, 120(sp)
    lw x29, 116(sp)
    lw x28, 112(sp)
    lw x27, 108(sp)
    lw x26, 104(sp)
    lw x25, 100(sp)
    lw x24, 96(sp)
    lw x23, 92(sp)
    lw x22, 88(sp)
    lw x21, 84(sp)
    lw x20, 80(sp)
    lw x19, 76(sp)
    lw x18, 72(sp)
    lw x17, 68(sp)
    lw x16, 64(sp)
    lw x15, 60(sp)
    lw x14, 56(sp)
    lw x13, 52(sp)
    lw x12, 48(sp)
    lw x11, 44(sp)
    lw x10, 40(sp)
    lw x9, 36(sp)
    lw x8, 32(sp)
    lw x7, 28(sp)
    lw x6, 24(sp)
    lw x5, 20(sp)
    lw x4, 16(sp)
    lw x3, 12(sp)
    lw x1, 4(sp)
    
    # 释放栈空间
    addi sp, sp, 128
    
    # 恢复用户栈
    csrr t0, mscratch    # 获取保存的用户栈
    csrw mscratch, sp    # 保存内核栈
    mv sp, t0           # 恢复用户栈
    
    # 返回用户代码
    mret
    
clean_and_terminate:
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
    addi sp, sp, 128
    
    # 恢复用户栈
    csrr t0, mscratch
    csrw mscratch, sp
    mv sp, t0
    
    # 跳转到终止处理程序
    j terminate

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

