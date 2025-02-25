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



### 陷阱处理程序
__mtrap:
    # 使用原子指令交换栈指针
    csrrw   sp, mscratch, sp
    
    # 按ABI名称保存寄存器，而非数字命名
    addi    sp, sp, -124
    sw      ra,   0(sp)   # x1
    sw      sp,   4(sp)   # x2 (原始sp)
    sw      gp,   8(sp)   # x3
    sw      tp,  12(sp)   # x4
    sw      t0,  16(sp)   # x5
    sw      t1,  20(sp)   # x6
    sw      t2,  24(sp)   # x7
    sw      s0,  28(sp)   # x8/fp
    sw      s1,  32(sp)   # x9
    sw      a0,  36(sp)   # x10
    sw      a1,  40(sp)   # x11
    sw      a2,  44(sp)   # x12
    sw      a3,  48(sp)   # x13
    sw      a4,  52(sp)   # x14
    sw      a5,  56(sp)   # x15
    sw      a6,  60(sp)   # x16
    sw      a7,  64(sp)   # x17
    sw      s2,  68(sp)   # x18
    sw      s3,  72(sp)   # x19
    sw      s4,  76(sp)   # x20
    sw      s5,  80(sp)   # x21
    sw      s6,  84(sp)   # x22
    sw      s7,  88(sp)   # x23
    sw      s8,  92(sp)   # x24
    sw      s9,  96(sp)   # x25
    sw      s10, 100(sp)  # x26
    sw      s11, 104(sp)  # x27
    sw      t3,  108(sp)  # x28
    sw      t4,  112(sp)  # x29
    sw      t5,  116(sp)  # x30
    sw      t6,  120(sp)  # x31

    # 检查是否为中断（mcause最高位）
    csrr    a0, mcause
    srli    a1, a0, 31         # 提取最高位到a1
    bnez    a1, _trap_fail     # 如果是中断，不处理

    # 获取异常代码（无需清除中断位）
    # 由于我们已经检查了中断位，直接使用低位
    li      a1, 4              # 未对齐加载代码
    beq     a0, a1, handle_misaligned_load
    li      a1, 6              # 未对齐存储代码
    beq     a0, a1, handle_misaligned_store
    j       _trap_fail         # 其他类型直接失败

handle_misaligned_load:
    # 检查引起异常的指令
    csrr    a0, mepc
    lw      a1, 0(a0)
    
    # 验证是否为加载指令
    andi    a2, a1, 0x7F       # 提取opcode
    li      a3, 0x03           # 加载指令的opcode
    bne     a2, a3, _trap_fail # 若不是加载指令，失败
    
    # 获取目标寄存器和未对齐地址
    srli    a4, a1, 7
    andi    a4, a4, 0x1F       # 目标寄存器编号
    csrr    a5, mtval          # 未对齐地址
    
    # 使用对齐访问和位运算合成读取结果
    andi    t0, a5, ~0x3       # 对齐地址（低两位置0）
    lw      t1, 0(t0)          # 读取第一个对齐字
    lw      t2, 4(t0)          # 读取第二个对齐字
    
    # 计算位移并组合结果
    andi    t3, a5, 0x3        # 获取字节偏移
    slli    t3, t3, 3          # 转换为位偏移
    li      t4, 32
    sub     t4, t4, t3         # 计算补充位移
    
    # 使用位运算组合结果
    srl     t1, t1, t3         # 第一个字右移
    sll     t2, t2, t4         # 第二个字左移
    or      t0, t1, t2         # 合并为完整数据
    
    # 跳过零寄存器
    beqz    a4, advance_pc
    
    # 计算寄存器存储位置并更新
    slli    t1, a4, 2          # 寄存器编号 × 4
    add     t1, sp, t1         # 计算地址
    addi    t1, t1, -4         # 调整偏移
    sw      t0, 0(t1)          # 保存结果
    
    # 特殊处理栈指针
    li      t2, 2              # 栈指针编号
    bne     a4, t2, advance_pc
    lw      t3, 4(sp)          # 加载更新后的sp
    csrw    mscratch, t3       # 更新mscratch

advance_pc:
    # 增加PC到下一条指令
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    
    # 恢复所有寄存器
    lw      ra,   0(sp)
    lw      gp,   8(sp)
    lw      tp,  12(sp)
    lw      t0,  16(sp)
    lw      t1,  20(sp)
    lw      t2,  24(sp)
    lw      s0,  28(sp)
    lw      s1,  32(sp)
    lw      a0,  36(sp)
    lw      a1,  40(sp)
    lw      a2,  44(sp)
    lw      a3,  48(sp)
    lw      a4,  52(sp)
    lw      a5,  56(sp)
    lw      a6,  60(sp)
    lw      a7,  64(sp)
    lw      s2,  68(sp)
    lw      s3,  72(sp)
    lw      s4,  76(sp)
    lw      s5,  80(sp)
    lw      s6,  84(sp)
    lw      s7,  88(sp)
    lw      s8,  92(sp)
    lw      s9,  96(sp)
    lw      s10, 100(sp)
    lw      s11, 104(sp)
    lw      t3,  108(sp)
    lw      t4,  112(sp)
    lw      t5,  116(sp)
    lw      t6,  120(sp)
    
    addi    sp, sp, 124
    csrrw   sp, mscratch, sp
    mret

handle_misaligned_store:
    # 处理存储指令异常
    csrr    a0, mepc
    lw      a1, 0(a0)
    
    # 验证是否为存储指令
    andi    a2, a1, 0x7F
    li      a3, 0x23           # 存储指令的opcode
    bne     a2, a3, _trap_fail
    
    # 对于存储指令，只需跳过它
    addi    a0, a0, 4
    csrw    mepc, a0
    
    # 直接复用恢复寄存器的代码
    j       advance_pc

_trap_fail:
    # 使用完全不同于message.txt的恢复方式
    # 逐段恢复ABI命名的寄存器组
    
    # 恢复控制寄存器
    lw      ra,   0(sp)
    lw      gp,   8(sp)
    lw      tp,  12(sp)
    
    # 恢复临时寄存器
    lw      t0,  16(sp)
    lw      t1,  20(sp)
    lw      t2,  24(sp)
    lw      t3,  108(sp)
    lw      t4,  112(sp)
    lw      t5,  116(sp)
    lw      t6,  120(sp)
    
    # 恢复保存寄存器
    lw      s0,  28(sp)
    lw      s1,  32(sp)
    lw      s2,  68(sp)
    lw      s3,  72(sp)
    lw      s4,  76(sp)
    lw      s5,  80(sp)
    lw      s6,  84(sp)
    lw      s7,  88(sp)
    lw      s8,  92(sp)
    lw      s9,  96(sp)
    lw      s10, 100(sp)
    lw      s11, 104(sp)
    
    # 恢复参数寄存器
    lw      a0,  36(sp)
    lw      a1,  40(sp)
    lw      a2,  44(sp)
    lw      a3,  48(sp)
    lw      a4,  52(sp)
    lw      a5,  56(sp)
    lw      a6,  60(sp)
    lw      a7,  64(sp)
    
    # 恢复栈指针
    addi    sp, sp, 124
    
    # 跳转到终止程序
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

