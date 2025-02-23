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
    csrrw   sp, mscratch, sp         # 进入内核栈
    addi    sp, sp, -120             # 预留栈空间

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

    # 读取 mcause
    csrr    t0, mcause
    li      t1, 4
    beq     t0, t1, handle_misaligned_lw
    li      t1, 6
    beq     t0, t1, handle_misaligned_sw
    j       trap_other

handle_misaligned_lw:
    csrr    t0, mepc
    lw      t1, 0(t0)
    andi    t2, t1, 0x7F
    li      t3, 0x03
    bne     t2, t3, trap_other
    srai    t2, t1, 12
    andi    t2, t2, 0x7

    # 仅处理 `lw` 指令
    li      t3, 2
    bne     t2, t3, trap_other

    # 获取错误地址
    csrr    t5, mtval
    andi    t2, t5, 3
    sub     t5, t5, t2
    lw      t0, 0(t5)
    lw      t1, 4(t5)

    # 组合正确的值
    li      t3, 1
    beq     t2, t3, lw_case1
    li      t3, 2
    beq     t2, t3, lw_case2
    li      t3, 3
    beq     t2, t3, lw_case3
    j       lw_case0
lw_case0:
    mv      t6, t0
    j       store_lw
lw_case1:
    srli    t2, t0, 8
    slli    t3, t1, 24
    or      t6, t2, t3
    j       store_lw
lw_case2:
    srli    t2, t0, 16
    slli    t3, t1, 16
    or      t6, t2, t3
    j       store_lw
lw_case3:
    srli    t2, t0, 24
    slli    t3, t1, 8
    or      t6, t2, t3
store_lw:
    sw      t6, 32(sp)  # 存入 `a0`
    j       advance_pc

handle_misaligned_sw:
    csrr    t0, mepc
    lw      t1, 0(t0)
    andi    t2, t1, 0x7F
    li      t3, 0x23
    bne     t2, t3, trap_other

    srai    t2, t1, 12
    andi    t2, t2, 0x7
    li      t3, 2
    bne     t2, t3, trap_other

    # 获取错误地址
    csrr    t5, mtval
    andi    t2, t5, 3
    sub     t5, t5, t2

    # 获取需要存储的值
    lw      t6, 32(sp)

    # 修复并存储
    beq     t2, zero, sw_case0
    li      t3, 1
    beq     t2, t3, sw_case1
    li      t3, 2
    beq     t2, t3, sw_case2
    li      t3, 3
    beq     t2, t3, sw_case3
sw_case0:
    sw      t6, 0(t5)
    j       store_done
sw_case1:
    srli    t3, t6, 8
    sb      t3, 1(t5)
    srli    t3, t6, 16
    sb      t3, 2(t5)
    srli    t3, t6, 24
    sb      t3, 3(t5)
    j       store_done
sw_case2:
    srli    t3, t6, 16
    sh      t3, 2(t5)
    j       store_done
sw_case3:
    sb      t6, 3(t5)
    j       store_done

store_done:
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    j       restore_registers

advance_pc:
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    j       restore_registers

trap_other:
    csrr    t0, mtval
    beqz    t0, terminate  # 解决 `badjump.s` 的问题
    addi    sp, sp, 120
    csrrw   sp, mscratch, sp
    j       terminate

restore_registers:
    lw      a0, 32(sp)  # 恢复 `a0`
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

