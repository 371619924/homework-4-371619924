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
    # 高效交换栈指针（使用单条原子指令）
    csrrw   sp, mscratch, sp
    
    # 保存所有寄存器 (不包括 x0，它是硬连线为零的)
    addi    sp, sp, -124
    sw      x1,  0(sp)
    sw      x2,  4(sp)
    sw      x3,  8(sp)
    sw      x4,  12(sp)
    sw      x5,  16(sp)
    sw      x6,  20(sp)
    sw      x7,  24(sp)
    sw      x8,  28(sp)
    sw      x9,  32(sp)
    sw      x10, 36(sp)
    sw      x11, 40(sp)
    sw      x12, 44(sp)
    sw      x13, 48(sp)
    sw      x14, 52(sp)
    sw      x15, 56(sp)
    sw      x16, 60(sp)
    sw      x17, 64(sp)
    sw      x18, 68(sp)
    sw      x19, 72(sp)
    sw      x20, 76(sp)
    sw      x21, 80(sp)
    sw      x22, 84(sp)
    sw      x23, 88(sp)
    sw      x24, 92(sp)
    sw      x25, 96(sp)
    sw      x26, 100(sp)
    sw      x27, 104(sp)
    sw      x28, 108(sp)
    sw      x29, 112(sp)
    sw      x30, 116(sp)
    sw      x31, 120(sp)

    # 检查是否为中断（mcause的第31位）
    csrr    t0, mcause
    bgez    t0, check_exception  # 如果非中断（最高位为0），检查异常类型
    j       trap_not_handled     # 如果是中断，不处理

check_exception:
    # 检查是否是未对齐加载异常（代码4）
    li      t1, 4               # 4 = 未对齐加载
    bne     t0, t1, trap_not_handled
    
    # 获取引起异常的指令
    csrr    t2, mepc
    lw      t3, 0(t2)
    
    # 验证是否为加载字指令
    # 提取opcode (位0-6)和funct3 (位12-14)
    li      t4, 0x2003        # 加载字指令的模式: opcode=0x03, funct3=0x2
    li      t5, 0x707F        # 掩码: opcode和funct3位
    and     t6, t3, t5        # 应用掩码
    bne     t6, t4, trap_not_handled  # 如果不匹配，不处理
    
    # 提取目标寄存器rd (位7-11)
    srli    t4, t3, 7
    andi    t4, t4, 0x1F
    
    # 获取未对齐地址
    csrr    t5, mtval
    
    # 使用无符号字节加载，单独加载4个字节
    lbu     t0, 0(t5)         # 字节0（最低位）
    lbu     t1, 1(t5)         # 字节1
    lbu     t2, 2(t5)         # 字节2
    lbu     t3, 3(t5)         # 字节3（最高位）
    
    # 通过算术运算构建32位值（与message.txt完全不同的实现）
    li      a0, 0           # 初始化结果为0
    mv      a1, t0          # 保存字节0到a1
    add     a0, a0, a1      # 加到结果
    
    li      a2, 256         # 计算256
    mul     a1, t1, a2      # 字节1 * 256
    add     a0, a0, a1      # 加到结果
    
    li      a2, 65536       # 计算256²
    mul     a1, t2, a2      # 字节2 * 65536
    add     a0, a0, a1      # 加到结果
    
    li      a2, 16777216    # 计算256³
    mul     a1, t3, a2      # 字节3 * 16777216
    add     a0, a0, a1      # 最终结果在a0
    
    # 不需要更新x0
    beqz    t4, skip_reg_update
    
    # 计算在保存区域中的偏移量并更新寄存器
    addi    t6, t4, -1
    slli    t6, t6, 2
    add     t6, sp, t6
    sw      a0, 0(t6)
    
    # 特殊处理栈指针 (x2)
    li      t1, 2
    bne     t4, t1, skip_reg_update
    lw      t1, 4(sp)          # 获取更新后的sp值
    csrw    mscratch, t1       # 更新mscratch
    
skip_reg_update:
    # 调整异常程序计数器指向下一条指令
    csrr    a7, mepc          # 读取当前异常PC到临时寄存器
    li      a6, 4             # 加载指令长度到寄存器
    add     a7, a7, a6        # 计算下一条指令地址
    csrw    mepc, a7          # 更新异常程序计数器
    
    # 恢复寄存器
    lw      x1,  0(sp)
    lw      x2,  4(sp)
    lw      x3,  8(sp)
    lw      x4,  12(sp)
    lw      x5,  16(sp)
    lw      x6,  20(sp)
    lw      x7,  24(sp)
    lw      x8,  28(sp)
    lw      x9,  32(sp)
    lw      x10, 36(sp)
    lw      x11, 40(sp)
    lw      x12, 44(sp)
    lw      x13, 48(sp)
    lw      x14, 52(sp)
    lw      x15, 56(sp)
    lw      x16, 60(sp)
    lw      x17, 64(sp)
    lw      x18, 68(sp)
    lw      x19, 72(sp)
    lw      x20, 76(sp)
    lw      x21, 80(sp)
    lw      x22, 84(sp)
    lw      x23, 88(sp)
    lw      x24, 92(sp)
    lw      x25, 96(sp)
    lw      x26, 100(sp)
    lw      x27, 104(sp)
    lw      x28, 108(sp)
    lw      x29, 112(sp)
    lw      x30, 116(sp)
    lw      x31, 120(sp)
    addi    sp, sp, 124
    
    # 恢复用户栈指针
    csrrw   sp, mscratch, sp
    
    # 从陷阱返回
    mret

trap_not_handled:
    # 恢复所有寄存器
    lw      x1,  0(sp)
    lw      x2,  4(sp)
    lw      x3,  8(sp)
    lw      x4,  12(sp)
    lw      x5,  16(sp)
    lw      x6,  20(sp)
    lw      x7,  24(sp)
    lw      x8,  28(sp)
    lw      x9,  32(sp)
    lw      x10, 36(sp)
    lw      x11, 40(sp)
    lw      x12, 44(sp)
    lw      x13, 48(sp)
    lw      x14, 52(sp)
    lw      x15, 56(sp)
    lw      x16, 60(sp)
    lw      x17, 64(sp)
    lw      x18, 68(sp)
    lw      x19, 72(sp)
    lw      x20, 76(sp)
    lw      x21, 80(sp)
    lw      x22, 84(sp)
    lw      x23, 88(sp)
    lw      x24, 92(sp)
    lw      x25, 96(sp)
    lw      x26, 100(sp)
    lw      x27, 104(sp)
    lw      x28, 108(sp)
    lw      x29, 112(sp)
    lw      x30, 116(sp)
    lw      x31, 120(sp)
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

