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
### Trap handler
__mtrap:
# Swap SP and mscratch to get kernel stack
    csrrw   sp, mscratch, sp

# Save all registers on the kernel stack
    addi    sp, sp, -128
    sw      x0, 0(sp)
    sw      x1, 4(sp)
    sw      x2, 8(sp)
    sw      x3, 12(sp)
    sw      x4, 16(sp)
    sw      x5, 20(sp)
    sw      x6, 24(sp)
    sw      x7, 28(sp)
    sw      x8, 32(sp)
    sw      x9, 36(sp)
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
    sw      x25,100(sp)
    sw      x26,104(sp)
    sw      x27,108(sp)
    sw      x28,112(sp)
    sw      x29,116(sp)
    sw      x30,120(sp)
    sw      x31,124(sp)

    csrr    t0, mcause                                                        # 将 mcause 读入 t0
    slli    t0, t0, 1                                                         # 左移 1 位，把最高位移出
    srli    t0, t0, 1                                                         # 逻辑右移 1 位，填 0，从而恢复剩下的低位
    li      t1, 4                                                             # 加载常数 4 到 t1
    bne     t0, t1, fail                                                      # 如果 t0 不等于 4，则跳转到 _trap_fail
    csrr    t2, mepc                                                          # 读取 mepc 到 t2
    lw      t3, 0(t2)                                                         # 从 mepc 指向地址加载指令到 t3
    andi    t4, t3, 0x7F                                                      # 取 t3 的低 7 位
    xori    t4, t4, 0x03                                                      # 将低 7 位与 0x03 异或，若相等结果为 0
    bnez    t4, fail                                                          #若结果非 0，则跳转到 _trap_fail

    srai    t6, t3, 12
    andi    t6, t6, 0x7
    li      t5, 2
    bne     t6, t5, fail

    mv      a0, t3

    srai    a1, a0, 7
    andi    a1, a1, 0x1F
    mv      a7, a1

    csrr    t6, mtval
    andi    t1, t6, 0x3                                                       # 计算 misaligned 地址的偏移（t6 & 3）
    sub     t6, t6, t1                                                        # 计算对齐的地址（对齐到 4 字节边界）

    lw      t2, 0(t6)                                                         # 读取对齐地址的数据
    lw      t3, 4(t6)                                                         # 读取下一个对齐地址的数据（如果需要）

    beqz    t1, fix_misaligned
    li      t4, 1
    beq     t1, t4, misaligned_offset_1
    li      t4, 2
    beq     t1, t4, misaligned_offset_2
    li      t4, 3
    beq     t1, t4, misaligned_offset_3

fix_misaligned:
    mv      t0, t2                                                            # 数据已经对齐
    j       store_fixed_value

misaligned_offset_1:
    srli    t4, t2, 8                                                         # 低 8 位丢弃
    slli    t5, t3, 24                                                        # 高 24 位补上
    or      t0, t4, t5                                                        # 合并数据
    j       store_fixed_value

misaligned_offset_2:
    srli    t4, t2, 16                                                        # 低 16 位丢弃
    slli    t5, t3, 16                                                        # 高 16 位补上
    or      t0, t4, t5                                                        # 合并数据
    j       store_fixed_value

misaligned_offset_3:
    srli    t4, t2, 24                                                        # 低 24 位丢弃
    slli    t5, t3, 8                                                         # 高 8 位补上
    or      t0, t4, t5                                                        # 合并数据
    j       store_fixed_value

store_fixed_value:
    slli    a1, a7, 2                                                         # 计算目标寄存器存储地址
    add     a1, sp, a1
    sw      t0, 0(a1)                                                         # 存储修复的数据
# 合并成完整 32 位数据

# 计算目标地址：a1 = sp + (a7 << 2)
    slli    a1, a7, 2
    add     a1, sp, a1
    sw      t0, 0(a1)

# 检查 a7 是否等于 2，若等于则更新 mscratch
    li      t0, 2
    xor     t1, a7, t0                                                        # 如果 a7 == 2，则 t1 结果为 0
    bnez    t1, skip
    lw      t0, 8(sp)                                                         # 从 sp+8 处加载原始 sp
    csrw    mscratch, t0
skip:

# 增加 mepc 的值 4，跳过故障指令
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
fail:
# Restore registers
    lw      x0, 0(sp)
    lw      x1, 4(sp)
    lw      x2, 8(sp)
    lw      x3, 12(sp)
    lw      x4, 16(sp)
    lw      x5, 20(sp)
    lw      x6, 24(sp)
    lw      x7, 28(sp)
    lw      x8, 32(sp)
    lw      x9, 36(sp)
    lw      x10, 40(sp)
    lw      x11, 44(sp)
    lw      x12, 48(sp)
    lw      x13, 52(sp)
    lw      x14, 56(sp)
    lw      x15, 60(sp)
    lw      x16, 64(sp)
    lw      x17, 68(sp)
    lw      x18, 72(sp)
    lw      x19, 76(sp)
    lw      x20, 80(sp)
    lw      x21, 84(sp)
    lw      x22, 88(sp)
    lw      x23, 92(sp)
    lw      x24, 96(sp)
    lw      x25,100(sp)
    lw      x26,104(sp)
    lw      x27,108(sp)
    lw      x28,112(sp)
    lw      x29,116(sp)
    lw      x30,120(sp)
    lw      x31,124(sp)
    addi    sp, sp, 128

    csrrw   sp, mscratch, sp
    j       terminate

# Restore all registers
    lw      x0, 0(sp)
    lw      x1, 4(sp)
    lw      x2, 8(sp)
    lw      x3, 12(sp)
    lw      x4, 16(sp)
    lw      x5, 20(sp)
    lw      x6, 24(sp)
    lw      x7, 28(sp)
    lw      x8, 32(sp)
    lw      x9, 36(sp)
    lw      x10, 40(sp)
    lw      x11, 44(sp)
    lw      x12, 48(sp)
    lw      x13, 52(sp)
    lw      x14, 56(sp)
    lw      x15, 60(sp)
    lw      x16, 64(sp)
    lw      x17, 68(sp)
    lw      x18, 72(sp)
    lw      x19, 76(sp)
    lw      x20, 80(sp)
    lw      x21, 84(sp)
    lw      x22, 88(sp)
    lw      x23, 92(sp)
    lw      x24, 96(sp)
    lw      x25,100(sp)
    lw      x26,104(sp)
    lw      x27,108(sp)
    lw      x28,112(sp)
    lw      x29,116(sp)
    lw      x30,120(sp)
    lw      x31,124(sp)
    addi    sp, sp, 128

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

