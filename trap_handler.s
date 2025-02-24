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
    ########################################################################
    # 1. 切换到内核栈 (mscratch) 并保存所有 32 个通用寄存器
    ########################################################################
    # 1a) 交换 sp 与 mscratch，使 sp 指向内核栈顶
    csrrw   sp, mscratch, sp

    # 1b) 在内核栈上开辟 128 字节空间，用于保存 x0..x31
    addi    sp, sp, -128

    # 1c) 依次将 x0..x31 保存在栈中，每个寄存器占 4 字节
    #     约定: xN 存放在 [sp + 4*N] 中。
    sw      x0,   0(sp)    # x0  --恒为0，存不存都可以
    sw      x1,   4(sp)    # x1 (ra)
    sw      x2,   8(sp)    # x2 (sp)
    sw      x3,   12(sp)   # x3 (gp)
    sw      x4,   16(sp)   # x4 (tp)
    sw      x5,   20(sp)   # x5 (t0)
    sw      x6,   24(sp)   # x6 (t1)
    sw      x7,   28(sp)   # x7 (t2)
    sw      x8,   32(sp)   # x8 (s0 / fp)
    sw      x9,   36(sp)   # x9 (s1)
    sw      x10,  40(sp)   # a0
    sw      x11,  44(sp)   # a1
    sw      x12,  48(sp)   # a2
    sw      x13,  52(sp)   # a3
    sw      x14,  56(sp)   # a4
    sw      x15,  60(sp)   # a5
    sw      x16,  64(sp)   # a6
    sw      x17,  68(sp)   # a7
    sw      x18,  72(sp)   # s2
    sw      x19,  76(sp)   # s3
    sw      x20,  80(sp)   # s4
    sw      x21,  84(sp)   # s5
    sw      x22,  88(sp)   # s6
    sw      x23,  92(sp)   # s7
    sw      x24,  96(sp)   # s8
    sw      x25,  100(sp)  # s9
    sw      x26,  104(sp)  # s10
    sw      x27,  108(sp)  # s11
    sw      x28,  112(sp)  # t3
    sw      x29,  116(sp)  # t4
    sw      x30,  120(sp)  # t5
    sw      x31,  124(sp)  # t6

    ########################################################################
    # 2. 检查是否为“misaligned load address”，并且指令是否是 lw
    ########################################################################
    # 2a) 读取 mcause，若 != 4 (misaligned load), 则跳转 terminate
    csrr    t0, mcause
    li      t1, 4
    bne     t0, t1, not_misaligned_lw

    # 2b) 读取 mepc，取出所触发异常的指令
    csrr    t1, mepc        # t1 = mepc
    lw      t2, 0(t1)       # t2 = *mepc (取 32 位指令)

    # 2c) 检查 opcode（低 7 位）是否是 3 (load)，并且 funct3（位14..12）是否是 2 (lw)
    #     opcode = t2[6:0]   => (t2 & 0x7F)
    #     funct3 = t2[14:12] => ((t2 >> 12) & 0x7)
    li      t3, 0x7F
    and     t4, t2, t3      # t4 = 指令的最低7位
    li      t5, 3           # opcode for loads
    bne     t4, t5, not_misaligned_lw

    srli    t4, t2, 12      # 取出 bits[14..12]
    li      t5, 7
    and     t4, t4, t5      # t4 = funct3
    li      t6, 2           # funct3 = 2 -> lw
    bne     t4, t6, not_misaligned_lw

    ########################################################################
    # 3. 若确认为 misaligned lw，则从 mtval 取地址，拼装加载 4 个字节
    ########################################################################
    # 3a) 提取目的寄存器 rd (bits [11..7])，用于后面把结果写到相应栈区
    #     rd = (instruction >> 7) & 0x1F
    srli    t4, t2, 7
    li      t5, 0x1F
    and     t4, t4, t5      # t4 = rd

    # 3b) 读取 mtval，得到真正访问的地址
    csrr    a1, mtval       # a1 = 触发 misaligned load 的地址

    # 3c) 依次加载 4 个字节，并拼成 32 位
    #     a2 中最终放置完整 32 位数据
    lbu     a2, 0(a1)       # 第1字节(最低8位)
    lbu     t5, 1(a1)
    slli    a2, a2, 8
    or      a2, a2, t5

    lbu     t5, 2(a1)
    slli    a2, a2, 8
    or      a2, a2, t5

    lbu     t5, 3(a1)
    slli    a2, a2, 8
    or      a2, a2, t5

    # 3d) 将结果存入被保存的“rd”对应的栈位置(每个寄存器在栈的偏移 = 4*rd)
    slli    t5, t4, 2       # t5 = 4*rd
    add     t5, t5, sp
    sw      a2, 0(t5)

    # 3e) mepc += 4，让下一条指令继续执行
    csrr    t6, mepc
    addi    t6, t6, 4
    csrw    mepc, t6

    # 若成功处理，后续继续恢复寄存器并返回
    j       restore_all

not_misaligned_lw:
    # 若既不是 misaligned load，或指令不是 lw，走默认 terminate
    j       terminate

    ########################################################################
    # 4. 恢复所有寄存器，并 mret 返回到原先的程序
    ########################################################################
restore_all:
    lw      x0,   0(sp)     # x0 (无实际意义)
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

    addi    sp, sp, 128

    # 恢复原来的用户栈指针
    csrrw   sp, mscratch, sp

    # 返回到异常/中断前现场，继续执行
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

