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
    csrrw   sp, mscratch, sp        # 交换 sp 和 mscratch
    addi    sp, sp, -120            # 分配 trap frame 空间

    # 保存所有寄存器
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
    sw      t3,104(sp)
    sw      t4,108(sp)
    sw      t5,112(sp)
    sw      t6,116(sp)

    # 获取异常类型
    csrr    t0, mcause              # 获取异常原因
    li      t1, 4                   # misaligned load 异常为 4
    beq     t0, t1, handle_misaligned_load  # 处理 misaligned load

    li      t1, 6                   # misaligned store 异常为 6
    beq     t0, t1, handle_misaligned_store # 处理 misaligned store

    li      t1, 5                   # store access fault 异常为 5
    beq     t0, t1, handle_store_access_fault # 处理 store access fault

    li      t1, 7                   # load access fault 异常为 7
    beq     t0, t1, handle_load_access_fault # 处理 load access fault

trap_other:
    j       terminate  # 处理其他异常

# 处理 misaligned load 异常
handle_misaligned_load:
    csrr    t5, mtval            # 获取 misaligned 地址
    bnez    t5, load_valid_addr  # 确保地址有效
    j       trap_other           # 如果无效，处理为其他异常

load_valid_addr:
    csrr    t0, mepc             # 获取当前指令地址
    lw      t1, 0(t0)            # 获取指令
    andi    t2, t1, 0x7F         # 检查是否是有效的 load 操作
    li      t3, 0x03
    bne     t2, t3, trap_other   # 如果不是 load，跳转到其他异常处理

    srai    t2, t1, 12           # 提取 funct3 (load 类型)
    andi    t2, t2, 0x7
    li      t3, 0x2              # 检查是否是 lw（load word）
    bne     t2, t3, trap_other   # 如果不是 lw，处理其他异常

    # 提取寄存器和地址，确保对齐
    srai    t4, t1, 7
    andi    t4, t4, 0x1F
    addi    t2, sp, 32
    add     t2, t2, t4

    lbu     t6, 0(t5)            # 以字节方式加载并调整对齐
    addi    t5, t5, 1
    lbu     t1, 0(t5)
    addi    t5, t5, 1
    lbu     t2, 0(t5)
    addi    t5, t5, 1
    lbu     t3, 0(t5)

    # 将字节合并成一个字（32位）
    slli    t1, t1, 8
    slli    t2, t2, 16
    slli    t3, t3, 24
    or      t6, t6, t1
    or      t6, t6, t2
    or      t6, t6, t3

    sw      t6, 0(t2)            # 将对齐的数据存回
    csrr    t0, mepc
    addi    t0, t0, 4            # 跳到下一条指令
    csrw    mepc, t0
    j       restore_and_return   # 恢复寄存器并返回用户代码

# 处理 misaligned store 异常
handle_misaligned_store:
    csrr    t5, mtval            # 获取 misaligned store 地址
    bnez    t5, store_valid_addr # 确保地址有效
    j       trap_other           # 如果无效，处理为其他异常

store_valid_addr:
    csrr    t0, mepc             # 获取当前指令地址
    lw      t1, 0(t0)            # 获取指令
    andi    t2, t1, 0x7F         # 检查是否是有效的 store 操作
    li      t3, 0x23
    bne     t2, t3, trap_other   # 如果不是 store，跳转到其他异常处理

    # 提取 funct3 (store 类型)
    srai    t2, t1, 12
    andi    t2, t2, 0x7
    li      t3, 0x2              # 检查是否是 sw（store word）
    bne     t2, t3, trap_other   # 如果不是 sw，处理其他异常

    srai    t4, t1, 20           # 提取源寄存器（rs2）
    andi    t4, t4, 0x1F
    addi    t2, sp, 32
    add     t2, t2, t4
    lw      t6, 0(t2)            # 获取要存储的值

    sb      t6, 0(t5)            # 以字节方式存储（逐字节存储）
    srli    t6, t6, 8
    addi    t5, t5, 1
    sb      t6, 0(t5)
    srli    t6, t6, 8
    addi    t5, t5, 1
    sb      t6, 0(t5)
    srli    t6, t6, 8
    addi    t5, t5, 1
    sb      t6, 0(t5)

    csrr    t0, mepc
    addi    t0, t0, 4            # 跳到下一条指令
    csrw    mepc, t0
    j       restore_and_return   # 恢复寄存器并返回用户代码

# 处理 store access fault
handle_store_access_fault:
    j       trap_other           # 处理为其他异常

# 处理 load access fault
handle_load_access_fault:
    j       trap_other           # 处理为其他异常

restore_and_return:
    # 恢复所有寄存器
    lw      ra,   0(sp)
    lw      gp,   4(sp)
    lw      tp,   8(sp)
    lw      t0,  12(sp)
    lw      t1,  16(sp)
    lw      t2,  20(sp)
    lw      s0,  24(sp)
    lw      s1,  28(sp)
    addi    sp, sp, 120
    csrrw   sp, mscratch, sp
    mret




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

