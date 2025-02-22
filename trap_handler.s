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
	# 交换 sp 与 mscratch，使 sp 成为内核栈，mscratch 保存用户 sp
	csrrw   sp, mscratch, sp
	# 为 trap frame 分配 120 字节空间（保存 x1, x3–x31，共 30 个寄存器）
	addi    sp, sp, -120
	# 按规定顺序保存寄存器
	sw      ra,   0(sp)      # x1 (ra)
	sw      gp,   4(sp)      # x3 (gp)
	sw      tp,   8(sp)      # x4 (tp)
	sw      t0,  12(sp)     # x5 (t0)
	sw      t1,  16(sp)     # x6 (t1)
	sw      t2,  20(sp)     # x7 (t2)
	sw      s0,  24(sp)     # x8 (s0)
	sw      s1,  28(sp)     # x9 (s1)
	sw      a0,  32(sp)     # x10 (a0)
	sw      a1,  36(sp)     # x11 (a1)
	sw      a2,  40(sp)     # x12 (a2)
	sw      a3,  44(sp)     # x13 (a3)
	sw      a4,  48(sp)     # x14 (a4)
	sw      a5,  52(sp)     # x15 (a5)
	sw      a6,  56(sp)     # x16 (a6)
	sw      a7,  60(sp)     # x17 (a7)
	sw      s2,  64(sp)     # x18 (s2)
	sw      s3,  68(sp)     # x19 (s3)
	sw      s4,  72(sp)     # x20 (s4)
	sw      s5,  76(sp)     # x21 (s5)
	sw      s6,  80(sp)     # x22 (s6)
	sw      s7,  84(sp)     # x23 (s7)
	sw      s8,  88(sp)     # x24 (s8)
	sw      s9,  92(sp)     # x25 (s9)
	sw      s10, 96(sp)     # x26 (s10)
	sw      s11,100(sp)     # x27 (s11)
	sw      t3,104(sp)      # x28 (t3)
	sw      t4,108(sp)      # x29 (t4)
	sw      t5,112(sp)      # x30 (t5)
	sw      t6,116(sp)      # x31 (t6)

	# 根据 mcause 判断异常类型：
	csrr    t0, mcause
	li      t1, 4
	beq     t0, t1, handle_load    # misaligned load
	li      t1, 6
	beq     t0, t1, handle_store   # misaligned store
	li      t1, 0
	beq     t0, t1, handle_fetch   # instruction address misaligned
	j       trap_other             # 其他异常，直接终止

;=======================
; 处理 misaligned load (lw) 补丁
handle_load:
	# 从 mepc 取得触发异常的 lw 指令
	csrr    t0, mepc
	lw      t1, 0(t0)
	# 检查 opcode 是否为 0x03 (load)
	andi    t2, t1, 0x7F
	li      t3, 0x03
	bne     t2, t3, trap_other
	# 检查 funct3 是否为 0x2 (lw)
	srai    t2, t1, 12
	andi    t2, t2, 0x7
	li      t3, 0x2
	bne     t2, t3, trap_other
	# 提取目标寄存器 rd (位 11:7)
	srai    t4, t1, 7
	andi    t4, t4, 0x1F
	# 不对 sp (x2) 补丁
	li      t2, 2
	beq     t4, t2, trap_other
	# 如果 rd != 0 则补丁；若 rd==0（写入 x0，无效，但仍应跳过出错指令）
	bnez    t4, patch_load
	j       skip_load_patch
patch_load:
	# 计算 trap frame 中对应寄存器的偏移：x1 在偏移 0，其余为 (rd-2)*4
	li      t2, 1
	beq     t4, t2, set_offset_load_zero
	addi    t2, t4, -2
	slli    t2, t2, 2
	j       done_load_offset
set_offset_load_zero:
	li      t2, 0
done_load_offset:
	add     t2, sp, t2
	mv      a7, t2
	# 从 mtval（故障地址）重构 32 位数据（使用 lbu 取 4 字节）
	csrr    t5, mtval
	lbu     t6, 0(t5)
	addi    t0, t5, 1
	lbu     t1, 0(t0)
	addi    t0, t5, 2
	lbu     t2, 0(t0)
	addi    t0, t5, 3
	lbu     t3, 0(t0)
	slli    t1, t1, 8
	slli    t2, t2, 16
	slli    t3, t3, 24
	or      t6, t6, t1
	or      t6, t6, t2
	or      t6, t6, t3
	# 将补丁数据写入 trap frame 对应位置
	sw      t6, 0(a7)
skip_load_patch:
	# 更新 mepc（跳过出错指令 4 字节）
	csrr    t0, mepc
	addi    t0, t0, 4
	csrw    mepc, t0
	j       common_restore

;=======================
; 处理 misaligned store (sw) 补丁
handle_store:
	csrr    t0, mepc
	lw      t1, 0(t0)
	# 检查 opcode 是否为 0x23 (store)
	andi    t2, t1, 0x7F
	li      t3, 0x23
	bne     t2, t3, trap_other
	# 检查 funct3 是否为 0x2 (sw)
	srai    t2, t1, 12
	andi    t2, t2, 0x7
	li      t3, 0x2
	bne     t2, t3, trap_other
	# 提取源寄存器 rs2 (位 24:20)
	srai    t4, t1, 20
	andi    t4, t4, 0x1F
	# 若 rs2 为 sp (x2) 则不补丁
	li      t5, 2
	beq     t4, t5, trap_other
	# 若 rs2 非 0，则从 trap frame 取出存储值；若 rs2==0，则值为 0
	bnez    t4, store_patch
	li      t6, 0
	j       do_store_patch
store_patch:
	li      t5, 1
	beq     t4, t5, set_offset_store_zero
	addi    t5, t4, -2
	slli    t5, t5, 2
	j       done_store_offset
set_offset_store_zero:
	li      t5, 0
done_store_offset:
	add     t5, sp, t5
	lw      t6, 0(t5)
do_store_patch:
	# 从 mtval 得到出错的存储地址
	csrr    t7, mtval
	# 将 t6 的 32 位数据拆分为 4 个字节，并用 sb 存入
	andi    t1, t6, 0xFF       # byte0
	srli    t2, t6, 8
	andi    t2, t2, 0xFF       # byte1
	srli    t3, t6, 16
	andi    t3, t3, 0xFF       # byte2
	srli    t4, t6, 24
	andi    t4, t4, 0xFF       # byte3
	sb      t1, 0(t7)
	addi    t7, t7, 1
	sb      t2, 0(t7)
	addi    t7, t7, 1
	sb      t3, 0(t7)
	addi    t7, t7, 1
	sb      t4, 0(t7)
	# 更新 mepc，跳过存储指令
	csrr    t0, mepc
	addi    t0, t0, 4
	csrw    mepc, t0
	j       common_restore

;=======================
; 处理取指不对齐（bad jump）补丁：对 instruction fetch misaligned (mcause==0)
handle_fetch:
	csrr    t0, mtval         # 取故障取指地址
	lbu     t1, 0(t0)
	addi    t0, t0, 1
	lbu     t2, 0(t0)
	addi    t0, t0, 1
	lbu     t3, 0(t0)
	addi    t0, t0, 1
	lbu     t4, 0(t0)
	slli    t2, t2, 8
	slli    t3, t3, 16
	slli    t4, t4, 24
	or      t1, t1, t2
	or      t1, t1, t3
	or      t1, t1, t4
	# 将补救后的指令写回内存（假设代码段可写）
	csrr    t0, mepc
	sw      t1, 0(t0)
	# 更新 mepc 跳过故障指令
	addi    t0, t0, 4
	csrw    mepc, t0
	j       common_restore

;=======================
; 其他异常，直接恢复现场后跳转至 terminate（terminate 在 utils.s 中定义）
trap_other:
	addi    sp, sp, 120
	csrrw   sp, mscratch, sp
	j       terminate

;=======================
; 恢复保存的寄存器并返回用户模式
common_restore:
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

