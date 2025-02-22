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
    # 交换 sp 与 mscratch：让 sp 成为内核栈指针，mscratch 保存用户 sp
    csrrw   sp, mscratch, sp

    # 如果异常类型不是 misaligned load（mcause ≠ 4），则直接恢复用户 sp 并转到 terminate
    csrr    t0, mcause
    li      t1, 4
    bne     t0, t1, trap_other_no_save

    # 在内核栈上分配空间保存 30 个寄存器（顺序必须严格为 x1, x3, x4, x5, …, x31）
    addi    sp, sp, -120
    sw      ra,   0(sp)      # x1 (ra)
    sw      gp,   4(sp)      # x3 (gp)
    sw      tp,   8(sp)      # x4 (tp)
    sw      t0,  12(sp)      # x5 (t0) –（此 t0 后续不再使用）
    sw      t1,  16(sp)      # x6 (t1)
    sw      t2,  20(sp)      # x7 (t2)
    sw      s0,  24(sp)      # x8 (s0)
    sw      s1,  28(sp)      # x9 (s1)
    sw      a0,  32(sp)      # x10 (a0)
    sw      a1,  36(sp)      # x11 (a1)
    sw      a2,  40(sp)      # x12 (a2)
    sw      a3,  44(sp)      # x13 (a3)
    sw      a4,  48(sp)      # x14 (a4)
    sw      a5,  52(sp)      # x15 (a5)
    sw      a6,  56(sp)      # x16 (a6)
    sw      a7,  60(sp)      # x17 (a7)
    sw      s2,  64(sp)      # x18 (s2)
    sw      s3,  68(sp)      # x19 (s3)
    sw      s4,  72(sp)      # x20 (s4)
    sw      s5,  76(sp)      # x21 (s5)
    sw      s6,  80(sp)      # x22 (s6)
    sw      s7,  84(sp)      # x23 (s7)
    sw      s8,  88(sp)      # x24 (s8)
    sw      s9,  92(sp)      # x25 (s9)
    sw      s10, 96(sp)      # x26 (s10)
    sw      s11,100(sp)      # x27 (s11)
    sw      t3,104(sp)       # x28 (t3)
    sw      t4,108(sp)       # x29 (t4)
    sw      t5,112(sp)       # x30 (t5)
    sw      t6,116(sp)       # x31 (t6)

    # --- 开始修补 misaligned lw ---
    # 取得引发异常的 lw 指令地址及其指令字
    csrr    t0, mepc         # t0 = faulting instruction address
    lw      t1, 0(t0)        # t1 = instruction word

    # 检查指令是否为 lw：opcode（低 7 位）应为 0x03
    andi    t2, t1, 0x7F
    li      t3, 0x03
    bne     t2, t3, patch_fail
    # 检查 funct3（位 14:12）应为 0x2
    srai    t2, t1, 12
    andi    t2, t2, 0x7
    li      t3, 0x2
    bne     t2, t3, patch_fail
    # 提取目标寄存器号 rd（位 11:7）
    srai    t4, t1, 7
    andi    t4, t4, 0x1F
    beq     t4, zero, patch_fail    # 若 rd==0，不做修补
    li      t2, 2
    beq     t4, t2, patch_fail      # 若 rd 为 sp (x2)，不修补
    # 计算目标寄存器在 trap frame 中的偏移：对于 rd≠1，offset = (rd – 2)×4；若 rd==1，offset = 0
    li      t2, 1
    beq     t4, t2, set_offset_zero
    addi    t2, t4, -2
    slli    t2, t2, 2
    j       done_offset
set_offset_zero:
    li      t2, 0
done_offset:
    add     t2, sp, t2     # t2 指向 trap frame 中目标寄存器槽
    mv      a7, t2         # 保存到 a7，后续用于写入修补数据

    # 采用“跨 2 个对齐字”方法重构 lw 数据：
    # 计算：offset = mtval mod 4，aligned = mtval – offset
    csrr    t5, mtval         # t5 = 触发异常的有效地址
    andi    t7, t5, 3         # t7 = offset = mtval mod 4
    sub     t5, t5, t7        # t5 = aligned address

    # 从 aligned 地址加载低 32 位（用 4 次 lb 模拟 lw）
    lbu     t0, 0(t5)         # 低字节0
    addi    t1, t5, 1
    lbu     t1, 0(t1)         # 低字节1
    addi    t2, t5, 2
    lbu     t2, 0(t2)         # 低字节2
    addi    t3, t5, 3
    lbu     t3, 0(t3)         # 低字节3
    slli    t1, t1, 8
    slli    t2, t2, 16
    slli    t3, t3, 24
    or      t0, t0, t1        # low_word 放在 t0
    or      t0, t0, t2
    or      t0, t0, t3

    # 从 aligned+4 地址加载高 32 位
    addi    t4, t5, 4         # t4 = aligned address + 4
    lbu     t1, 0(t4)         # high 字节0
    addi    t2, t4, 1
    lbu     t2, 0(t2)         # high 字节1
    addi    t3, t4, 2
    lbu     t3, 0(t3)         # high 字节2
    addi    t8, t4, 3         # 用 t8 取 high 字节3
    lbu     t8, 0(t8)         # high 字节3
    slli    t2, t2, 8
    slli    t3, t3, 16
    slli    t8, t8, 24
    or      t1, t1, t2        # high_word 放在 t1
    or      t1, t1, t3
    or      t1, t1, t8

    # 计算移位量：shift = offset × 8
    slli    t7, t7, 3         # t7 = shift (0, 8, 16, or 24)
    # 低部分：low_word >> shift
    srl     t0, t0, t7        # t0 = low_part
    # 高部分：high_word << (32 – shift)
    li      t8, 32
    sub     t8, t8, t7        # t8 = 32 – shift
    sll     t1, t1, t8        # t1 = high_part
    or      t0, t0, t1        # result = low_part | high_part

    sw      t0, 0(a7)         # 将修补结果写入目标寄存器对应槽

    # 更新 mepc，跳过出错指令（+4 字节）
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0

    # 恢复所有寄存器（顺序须与保存时一致）
    lw      ra,   0(sp)
    lw      gp,   4(sp)
    lw      tp,   8(sp)
    lw      t0,  12(sp)
    lw      t1,  16(sp)
    lw      t2,  20(sp)
    lw      s0,  24(sp)
    lw      s1,  28(sp)
    lw      a0,  32(sp)
    lw      a1,  36(sp)
    lw      a2,  40(sp)
    lw      a3,  44(sp)
    lw      a4,  48(sp)
    lw      a5,  52(sp)
    lw      a6,  56(sp)
    lw      a7,  60(sp)
    lw      s2,  64(sp)
    lw      s3,  68(sp)
    lw      s4,  72(sp)
    lw      s5,  76(sp)
    lw      s6,  80(sp)
    lw      s7,  84(sp)
    lw      s8,  88(sp)
    lw      s9,  92(sp)
    lw      s10, 96(sp)
    lw      s11,100(sp)
    lw      t3,104(sp)
    lw      t4,108(sp)
    lw      t5,112(sp)
    lw      t6,116(sp)
    addi    sp, sp, 120
    csrrw   sp, mscratch, sp    # 恢复用户 sp
    mret

patch_fail:
    addi    sp, sp, 120
    csrrw   sp, mscratch, sp
    j       terminate

trap_other_no_save:
    csrrw   sp, mscratch, sp
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

