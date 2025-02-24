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
    ################################################################################
    # 1. 交换 sp 和 mscratch，让 trap handler 有独立的内核栈可用
    ################################################################################
    csrrw   sp, mscratch, sp
    addi    sp, sp, -124    # 预留 31 个通用寄存器存储空间

    # 保存 x1..x31 到 [sp + 4*N]（x0 无需存）
    li      t0, 1

save_registers:
    addi    t1, t0, -1       # t1 = t0 - 1
    slli    t1, t1, 2        # t1 = (t0-1) * 4
    sw      x1, t1(sp)       # 存储寄存器 x1..x31
    addi    t0, t0, 1
    bne     t0, 32, save_registers


    ################################################################################
    # 2. 判断是否是 mcause=4 => misaligned load address
    ################################################################################
    csrr    t0, mcause
    li      t1, 4
    bne     t0, t1, not_misaligned_load

    # 2.1 取出 mepc, 读出触发异常的指令
    csrr    t2, mepc
    lw      t3, 0(t2)      # t3 = 32位指令码

    # 2.2 解析 opcode（bits[6:0]），必须是 3（LOAD 指令）
    li      t4, 0x7F
    and     t4, t3, t4
    li      t5, 3
    bne     t4, t5, not_misaligned_load

    # 2.3 提取 funct3（bits[14:12]）
    srli    t6, t3, 12
    li      t5, 7
    and     t6, t6, t5

    # 2.4 确定 LOAD 类型
    li      t5, 2  # lw
    beq     t6, t5, do_misaligned_lw

    li      t5, 1  # lh
    beq     t6, t5, do_misaligned_lh

    li      t5, 5  # lhu
    beq     t6, t5, do_misaligned_lhu

    # 如果是 LOAD 但不是 lw/lh/lhu，就不处理
    j       not_misaligned_load


################################################################################
# 2A. 处理 Misaligned LW
################################################################################
do_misaligned_lw:
    # 解析目标寄存器 rd（bits[11:7]）
    srli    t4, t3, 7
    li      t5, 0x1F
    and     t4, t4, t5      # t4 = rd

    # 获取未对齐地址
    csrr    a1, mtval

    # 读取 4 字节（小端序） => a2
    lbu     a2, 0(a1)
    lbu     t5, 1(a1)
    slli    t5, t5, 8
    or      a2, a2, t5

    lbu     t5, 2(a1)
    slli    t5, t5, 16
    or      a2, a2, t5

    lbu     t5, 3(a1)
    slli    t5, t5, 24
    or      a2, a2, t5

    # 存储回目标寄存器
    slli    t5, t4, 2
    add     t5, t5, sp
    sw      a2, 0(t5)

    # mepc += 4，跳过已修复的指令
    csrr    t6, mepc
    addi    t6, t6, 4
    csrw    mepc, t6

    # 恢复寄存器并返回
    j       restore_all


################################################################################
# 2B. 处理 Misaligned LH
################################################################################
do_misaligned_lh:
    srli    t4, t3, 7
    li      t5, 0x1F
    and     t4, t4, t5      

    csrr    a1, mtval       

    # 读取 2 字节（小端序）
    lbu     a2, 0(a1)
    lbu     t5, 1(a1)
    slli    t5, t5, 8
    or      a2, a2, t5      

    # 符号扩展
    slli    a2, a2, 16
    srai    a2, a2, 16      

    # 存储回目标寄存器
    slli    t5, t4, 2
    add     t5, t5, sp
    sw      a2, 0(t5)

    # mepc += 4，跳过修复的指令
    csrr    t6, mepc
    addi    t6, t6, 4
    csrw    mepc, t6

    # 恢复寄存器并返回
    j       restore_all


################################################################################
# 2C. 处理 Misaligned LHU
################################################################################
do_misaligned_lhu:
    srli    t4, t3, 7
    li      t5, 0x1F
    and     t4, t4, t5      

    csrr    a1, mtval       

    # 读取 2 字节（小端序）
    lbu     a2, 0(a1)
    lbu     t5, 1(a1)
    slli    t5, t5, 8
    or      a2, a2, t5      

    # 存储回目标寄存器
    slli    t5, t4, 2
    add     t5, t5, sp
    sw      a2, 0(t5)

    # mepc += 4，跳过修复的指令
    csrr    t6, mepc
    addi    t6, t6, 4
    csrw    mepc, t6

    # 恢复寄存器并返回
    j       restore_all


################################################################################
# 3. 无法处理的异常，跳转到 terminate
################################################################################
not_misaligned_load:
    j       terminate

################################################################################
# 4. 恢复所有寄存器并返回
################################################################################
restore_all:
    li      t0, 1                # t0 = 1（用于计算索引）
restore_loop:
    addi    t1, t0, -1           # t1 = t0 - 1
    slli    t1, t1, 2            # t1 = (t0 - 1) * 4，计算偏移量
    add     t1, t1, sp           # 计算 sp + 偏移量
    lw      x1, 0(t1)            # 读取栈中的值恢复到 x1（循环时变换目标寄存器）
    addi    t0, t0, 1            # t0 += 1
    bne     t0, 32, restore_loop # 继续循环直到所有寄存器恢复完毕

    addi    sp, sp, 128          # 释放栈空间（之前分配了 128 字节）
    csrrw   sp, mscratch, sp     # 恢复原始 sp
    mret                          # 返回用户态



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

