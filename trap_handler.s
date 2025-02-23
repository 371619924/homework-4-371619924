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

	
  	
    
.globl __mtrap
__mtrap:
    csrrw   sp, mscratch, sp         # 使用内核栈
    addi    sp, sp, -120             # 分配陷阱帧
    # 保存所有寄存器（保持原有逻辑）
    sw      ra, 0(sp)
    sw      gp, 4(sp)
    sw      tp, 8(sp)
    sw      t0, 12(sp)
    sw      t1, 16(sp)
    sw      t2, 20(sp)
    sw      s0, 24(sp)
    sw      s1, 28(sp)
    sw      a0, 32(sp)
    sw      a1, 36(sp)
    sw      a2, 40(sp)
    sw      a3, 44(sp)
    sw      a4, 48(sp)
    sw      a5, 52(sp)
    sw      a6, 56(sp)
    sw      a7, 60(sp)
    sw      s2, 64(sp)
    sw      s3, 68(sp)
    sw      s4, 72(sp)
    sw      s5, 76(sp)
    sw      s6, 80(sp)
    sw      s7, 84(sp)
    sw      s8, 88(sp)
    sw      s9, 92(sp)
    sw      s10, 96(sp)
    sw      s11,100(sp)
    sw      t3,104(sp)
    sw      t4,108(sp)
    sw      t5,112(sp)
    sw      t6,116(sp)

    csrr    t0, mcause
    li      t1, 4
    beq     t0, t1, handle_load_misalign
    li      t1, 6
    beq     t0, t1, handle_store_misalign
    j       trap_other

# 处理加载未对齐（原有逻辑，移除对sp的检查）
handle_load_misalign:
    csrr    t0, mepc
    lw      t1, 0(t0)
    andi    t2, t1, 0x7F
    li      t3, 0x03
    bne     t2, t3, trap_other
    srli    t2, t1, 12
    andi    t2, t2, 0x7
    li      t3, 2
    bne     t2, t3, trap_other

    srai    t4, t1, 7
    andi    t4, t4, 0x1F
    beq     t4, zero, trap_other      # 跳过x0

    # ... 原有数据重组逻辑 ...
    j       restore_registers

# 处理存储未对齐（新增完整case标签）
handle_store_misalign:
    csrr    t0, mepc
    lw      t1, 0(t0)
    andi    t2, t1, 0x7F
    li      t3, 0x23                  # sw的opcode
    bne     t2, t3, trap_other
    srli    t2, t1, 12
    andi    t2, t2, 0x7
    li      t3, 0x2                   # sw的funct3
    bne     t2, t3, trap_other

    # 提取rs2的值（从陷阱帧中获取）
    srli    t4, t1, 20                # rs2字段位置
    andi    t4, t4, 0x1F              # rs2寄存器号
    slli    t4, t4, 2                 # 转换为偏移（每个寄存器占4字节）
    add     t4, sp, t4                # 陷阱帧中的寄存器位置
    lw      t5, 0(t4)                 # t5 = 要存储的值

    csrr    t0, mtval                 # 故障地址
    andi    t1, t0, 0x3               # 计算偏移量（0-3）
    andi    t2, t0, -4                # 对齐后的地址

    # 读取原始内存内容
    lw      t3, 0(t2)                 # 低地址对齐字
    lw      t4, 4(t2)                 # 高地址对齐字

    # 根据偏移量合并数据
    beqz    t1, sw_case0              # 偏移0
    li      a7, 1
    beq     t1, a7, sw_case1          # 偏移1
    li      a7, 2
    beq     t1, a7, sw_case2          # 偏移2
    li      a7, 3
    beq     t1, a7, sw_case3          # 偏移3

sw_case0:                             # 对齐，无需处理
    sw      t5, 0(t2)
    j       sw_done

sw_case1:                             # 偏移1：拆分到两个字
    slli    t6, t5, 8                 # 高24位
    srli    t5, t5, 24                # 低8位
    or      t3, t3, t6                # 合并到低字
    slli    t5, t5, 24                # 对齐到高字
    or      t4, t4, t5
    j       sw_write

sw_case2:                             # 偏移2：拆分到两个字
    slli    t6, t5, 16                # 高16位
    srli    t5, t5, 16                # 低16位
    or      t3, t3, t6
    slli    t5, t5, 16
    or      t4, t4, t5
    j       sw_write

sw_case3:                             # 偏移3：拆分到两个字
    slli    t6, t5, 24                # 高8位
    srli    t5, t5, 8                 # 低24位
    or      t3, t3, t6
    slli    t5, t5, 8
    or      t4, t4, t5

sw_write:
    sw      t3, 0(t2)                 # 写入低字
    sw      t4, 4(t2)                 # 写入高字

sw_done:
    csrr    t0, mepc
    addi    t0, t0, 4                 # 跳过当前指令
    csrw    mepc, t0

restore_registers:
    # 恢复所有寄存器（原有逻辑）
    lw      ra, 0(sp)
    lw      gp, 4(sp)
    # ... 其他寄存器的恢复 ...
    csrrw   sp, mscratch, sp
    mret

trap_other:
    addi    sp, sp, 120
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

