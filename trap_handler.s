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
# 1) Swap stack pointer (sp) with mscratch, so kernel uses its own stack
    csrrw   sp, mscratch, sp

# 2) Save all registers to kernel stack (128 bytes = 32 registers * 4 bytes)
    addi    sp, sp, -128
    sw      x0, 0(sp)
    sw      x1, 4(sp)
    sw      x2, 8(sp)                                                         # Save sp (x2)
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

# 3) Check trap cause (mcause)
# If not "misaligned load", go to terminate
    csrr    t0, mcause
    li      t1, 4                                                             # 4 = misaligned load
    bne     t0, t1, fail
    li      t1, 6             # 6 = misaligned store
    beq     t0, t1, handle_misaligned_store


# 4) Handle misaligned load:
# Read faulting instruction to get rd
# Get misaligned address from mtval
# Use lb+andi to read 4 bytes and assemble 32-bit value
# Write back to corresponding register save area
# mepc += 4 to skip faulting instruction

# 4a) Read faulting instruction, get rd
    csrr    t0, mepc                                                          # t0 = instruction address
    lw      t1, 0(t0)                                                         # t1 = faulting instruction (lw)
# lw format: opcode[6: 0] | rd[11: 7] | rs1[19: 15] | imm[31: 20] ...
# rd = (instruction >> 7) & 0x1F
    srli    t2, t1, 7
    andi    t2, t2, 0x1F                                                      # t2 now holds rd

# 4b) Get misaligned address
    csrr    t3, mtval                                                         # t3 = misaligned address

# 4c) Read 4 bytes sequentially (using lb+andi to zero-extend)
    lb      t4, 0(t3)                                                         # byte0 (lowest)
    andi    t4, t4, 0xFF

    lb      t5, 1(t3)                                                         # byte1
    andi    t5, t5, 0xFF
    slli    t5, t5, 8
    or      t4, t4, t5

    lb      t5, 2(t3)                                                         # byte2
    andi    t5, t5, 0xFF
    slli    t5, t5, 16
    or      t4, t4, t5

    lb      t5, 3(t3)                                                         # byte3 (highest)
    andi    t5, t5, 0xFF
    slli    t5, t5, 24
    or      t4, t4, t5

# 4d) Write back to save area
# Save area starts at sp, each register is 4 bytes, offset = rd*4
    slli    t2, t2, 2
    add     t2, sp, t2
    sw      t4, 0(t2)

# 4e) Skip faulting instruction (mepc += 4)
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0

# 5) Restore all registers, then mret return
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

# Restore original stack pointer
    csrrw   sp, mscratch, sp

# Return from trap
    mret

fail:

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
    
handle_misaligned_store:
    csrr    t0, mepc          # 读取 faulting 指令地址
    lw      t1, 0(t0)         # 读取 faulting 指令 (sw/sh/sb)
    csrr    t3, mtval         # 读取 misaligned 地址

    # 解析 store 指令，找到 rs2 (source register)
    srli    t2, t1, 20        # rs2 在 bit [24:20]
    andi    t2, t2, 0x1F      # t2 = rs2

    # 计算 rs2 在保存区域的偏移 (sp + rs2*4)
    slli    t2, t2, 2
    add     t2, sp, t2
    lw      t4, 0(t2)         # t4 = 要存储的值 (rs2 的值)

    # 逐字节写入目标地址
    sb      t4, 0(t3)
    srli    t4, t4, 8
    sb      t4, 1(t3)
    srli    t4, t4, 8
    sb      t4, 2(t3)
    srli    t4, t4, 8
    sb      t4, 3(t3)

    # 跳过 faulting 指令 (mepc += 4)
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0

    j       restore_registers








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

