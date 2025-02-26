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
    # 1) 交换栈指针，让内核使用自己的栈
    csrrw   sp, mscratch, sp

    # 2) 保存所有 32 个寄存器到内核栈 (128 字节 = 32 * 4)
    addi    sp, sp, -128
    sw      x0, 0(sp)
    sw      x1, 4(sp)
    sw      x2, 8(sp)     # 保存原用户栈指针 x2
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
    sw      x25, 100(sp)
    sw      x26, 104(sp)
    sw      x27, 108(sp)
    sw      x28, 112(sp)
    sw      x29, 116(sp)
    sw      x30, 120(sp)
    sw      x31, 124(sp)

    # 3) 判断是否中断 (mcause 最高位是否为 1)
    csrr    t0, mcause
    li      t1, 0x80000000        # 最高位掩码
    and     t2, t0, t1
    bne     t2, zero, terminate   # 若最高位不为 0，则是中断，直接终止

    # 4) 取出异常码（清除最高位）
    li      t1, 0x7FFFFFFF
    and     t0, t0, t1
    li      t1, 4    # 4 = misaligned load
    bne     t0, t1, terminate     # 如果不是 4，终止

    # 5) 检查指令是否真的为 lw
    csrr    t0, mepc
    lw      t1, 0(t0)             # 取出故障指令

    # opcode == 0x03 ?
    andi    t2, t1, 0x7F
    li      t3, 0x03
    bne     t2, t3, terminate

    # funct3 == 2 (lw) ?
    srli    t2, t1, 12            # 取 bits[14:12]
    andi    t2, t2, 0x7
    li      t3, 2
    bne     t2, t3, terminate

    # 6) (关键修改) 比较 mepc 和 mtval 高 30 位
    #    若相同，则说明这是在加载“与指令同址”的地方（通常是跳转失败），无法修复 → 终止
    csrr    t2, mepc
    csrr    t3, mtval
    srli    t4, t2, 2             # 忽略低 2 位
    srli    t5, t3, 2
    beq     t4, t5, terminate

    # 7) 执行未对齐的 lw：逐字节读取，合成为 32 位
    csrr    t3, mtval
    lbu     t4, 0(t3)
    lbu     t5, 1(t3)
    slli    t5, t5, 8
    or      t4, t4, t5

    lbu     t5, 2(t3)
    slli    t5, t5, 16
    or      t4, t4, t5

    lbu     t5, 3(t3)
    slli    t5, t5, 24
    or      t4, t4, t5

    # 提取 rd（目的寄存器）
    srli    t2, t1, 7
    andi    t2, t2, 0x1F

    # 写回到内核栈上保存的寄存器槽中
    slli    t2, t2, 2
    add     t2, sp, t2
    sw      t4, 0(t2)

    # 若目标寄存器是 sp (x2)，则还需更新 mscratch 中保存的内核栈指针
    srli    t0, t1, 7
    andi    t0, t0, 0x1F
    li      t6, 2
    bne     t0, t6, skip_sp_update
    lw      t0, 8(sp)           # 原 sp
    csrw    mscratch, t0
skip_sp_update:

    # 8) mepc 指向下一条指令
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0

    # 恢复寄存器并返回用户态
    lw      x1, 4(sp)
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
    lw      x25, 100(sp)
    lw      x26, 104(sp)
    lw      x27, 108(sp)
    lw      x28, 112(sp)
    lw      x29, 116(sp)
    lw      x30, 120(sp)
    lw      x31, 124(sp)

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

