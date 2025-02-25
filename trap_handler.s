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
    # 交换内核栈与当前栈
    csrrw   sp, mscratch, sp
    
    # 分配栈空间
    addi    sp, sp, -128
    
    # 保存所有寄存器
    sw      zero, 0(sp)
    sw      ra,   4(sp)  # x1
    sw      sp,   8(sp)  # x2
    sw      gp,  12(sp)  # x3
    sw      tp,  16(sp)  # x4
    sw      t0,  20(sp)  # x5
    sw      t1,  24(sp)  # x6
    sw      t2,  28(sp)  # x7
    sw      s0,  32(sp)  # x8/fp
    sw      s1,  36(sp)  # x9
    sw      a0,  40(sp)  # x10
    sw      a1,  44(sp)  # x11
    sw      a2,  48(sp)  # x12
    sw      a3,  52(sp)  # x13
    sw      a4,  56(sp)  # x14
    sw      a5,  60(sp)  # x15
    sw      a6,  64(sp)  # x16
    sw      a7,  68(sp)  # x17
    sw      s2,  72(sp)  # x18
    sw      s3,  76(sp)  # x19
    sw      s4,  80(sp)  # x20
    sw      s5,  84(sp)  # x21
    sw      s6,  88(sp)  # x22
    sw      s7,  92(sp)  # x23
    sw      s8,  96(sp)  # x24
    sw      s9, 100(sp)  # x25
    sw      s10,104(sp)  # x26
    sw      s11,108(sp)  # x27
    sw      t3, 112(sp)  # x28
    sw      t4, 116(sp)  # x29
    sw      t5, 120(sp)  # x30
    sw      t6, 124(sp)  # x31
    
    # 检查中断/异常原因
    csrr    a0, mcause
    srli    a1, a0, 31        # 检查最高位（中断vs异常）
    bnez    a1, handle_interrupt
    
    # 处理异常情况
    li      a2, 4             # 加载地址不对齐/错误代码
    bne     a0, a2, exception_error
    
    # 解析触发异常的指令
    csrr    a3, mepc          # 获取触发异常的指令地址
    lw      a4, 0(a3)         # 加载该指令
    
    # 验证opcode是否为load指令(0x03)
    li      a5, 0x7F
    and     a6, a4, a5
    li      a5, 0x03
    bne     a6, a5, exception_error
    
    # 提取funct3字段（bits 12-14）验证是否为lw指令
    srli    a6, a4, 12
    andi    a6, a6, 0x7
    li      a5, 2             # lw指令的funct3值
    bne     a6, a5, exception_error
    
    # 提取目标寄存器rd（bits 7-11）
    srli    t0, a4, 7
    andi    t0, t0, 0x1F      # 寄存器编号（0-31）
    mv      t6, t0            # 保存目标寄存器编号
    
    # 从mtval获取实际加载地址
    csrr    t1, mtval
    
    # 手动执行加载操作（4字节）
    lb      t2, 0(t1)
    lb      t3, 1(t1)
    lb      t4, 2(t1)
    lb      t5, 3(t1)
    
    # 组合字节为一个字
    mv      a2, t2
    slli    t3, t3, 8
    or      a2, a2, t3
    slli    t4, t4, 16
    or      a2, a2, t4
    slli    t5, t5, 24
    or      a2, a2, t5
    
    # 将结果存入目标寄存器的保存位置
    slli    t3, t6, 2
    add     t3, sp, t3
    sw      a2, 0(t3)
    
    # 如果目标是sp(x2)，则更新mscratch
    li      t4, 2
    bne     t6, t4, skip_mscratch
    lw      t4, 8(sp)        # 获取原始sp值
    csrw    mscratch, t4     # 更新mscratch
    
skip_mscratch:
    # 指令指针前进到下一条指令
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    j       restore_exit

handle_interrupt:
    # 这里可以处理中断，但当前实现不处理
    j       restore_exit

exception_error:
    # 处理不支持的异常类型
    j       restore_exit
    
restore_exit:
    # 恢复所有寄存器
    lw      ra,   4(sp)  # x1
    # 不立即恢复sp(x2)
    lw      gp,  12(sp)  # x3
    lw      tp,  16(sp)  # x4
    lw      t0,  20(sp)  # x5
    lw      t1,  24(sp)  # x6
    lw      t2,  28(sp)  # x7
    lw      s0,  32(sp)  # x8
    lw      s1,  36(sp)  # x9
    lw      a0,  40(sp)  # x10
    lw      a1,  44(sp)  # x11
    lw      a2,  48(sp)  # x12
    lw      a3,  52(sp)  # x13
    lw      a4,  56(sp)  # x14
    lw      a5,  60(sp)  # x15
    lw      a6,  64(sp)  # x16
    lw      a7,  68(sp)  # x17
    lw      s2,  72(sp)  # x18
    lw      s3,  76(sp)  # x19
    lw      s4,  80(sp)  # x20
    lw      s5,  84(sp)  # x21
    lw      s6,  88(sp)  # x22
    lw      s7,  92(sp)  # x23
    lw      s8,  96(sp)  # x24
    lw      s9, 100(sp)  # x25
    lw      s10,104(sp)  # x26
    lw      s11,108(sp)  # x27
    lw      t3, 112(sp)  # x28
    lw      t4, 116(sp)  # x29
    lw      t5, 120(sp)  # x30
    lw      t6, 124(sp)  # x31
    
    # 释放栈空间
    addi    sp, sp, 128
    
    # 恢复原始堆栈指针并返回
    csrrw   sp, mscratch, sp
    mret

program_end:
    # 程序终止点
    j       program_end
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

