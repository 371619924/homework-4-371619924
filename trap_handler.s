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
	# 交换 sp 与 mscratch：使 sp 变为内核栈指针，mscratch 保存用户 sp
	csrrw	sp, mscratch, sp

	# 分配 trap frame 空间，保存 30 个寄存器（x1, x3–x31）
	addi	sp, sp, -120

	# 按固定顺序保存寄存器
	sw	ra,   0(sp)      # x1 (ra)
	sw	gp,   4(sp)      # x3 (gp)
	sw	tp,   8(sp)      # x4 (tp)
	sw	t0,  12(sp)      # x5 (t0)
	sw	t1,  16(sp)      # x6 (t1)
	sw	t2,  20(sp)      # x7 (t2)
	sw	s0,  24(sp)      # x8 (s0)
	sw	s1,  28(sp)      # x9 (s1)
	sw	a0,  32(sp)      # x10 (a0)
	sw	a1,  36(sp)      # x11 (a1)
	sw	a2,  40(sp)      # x12 (a2)
	sw	a3,  44(sp)      # x13 (a3)
	sw	a4,  48(sp)      # x14 (a4)
	sw	a5,  52(sp)      # x15 (a5)
	sw	a6,  56(sp)      # x16 (a6)
	sw	a7,  60(sp)      # x17 (a7)
	sw	s2,  64(sp)      # x18 (s2)
	sw	s3,  68(sp)      # x19 (s3)
	sw	s4,  72(sp)      # x20 (s4)
	sw	s5,  76(sp)      # x21 (s5)
	sw	s6,  80(sp)      # x22 (s6)
	sw	s7,  84(sp)      # x23 (s7)
	sw	s8,  88(sp)      # x24 (s8)
	sw	s9,  92(sp)      # x25 (s9)
	sw	s10, 96(sp)      # x26 (s10)
	sw	s11,100(sp)      # x27 (s11)
	sw	t3, 104(sp)      # x28 (t3)
	sw	t4, 108(sp)      # x29 (t4)
	sw	t5, 112(sp)      # x30 (t5)
	sw	t6, 116(sp)      # x31 (t6)

	# 检查 mcause 是否为 4（misaligned load），否则跳转 trap_other
	csrr	t0, mcause
	li		t1, 4
	bne		t0, t1, trap_other

	# 取出 lw 指令的地址，并加载该指令
	csrr	t0, mepc         # t0 = 出错指令地址
	lw		t1, 0(t0)        # t1 = 指令字

	# 检查 opcode（低 7 位）是否为 0x03（load 指令）
	andi	t2, t1, 0x7F
	li		t3, 0x03
	bne		t2, t3, trap_other

	# 检查 funct3（位 14:12）是否为 0x2（lw 指令）
	srai	t2, t1, 12
	andi	t2, t2, 0x7
	li		t3, 0x2
	bne		t2, t3, trap_other

	# 计算 rd（目标寄存器）
	srai	t4, t1, 7
	andi	t4, t4, 0x1F
	beq		t4, zero, trap_other    # 若 rd 为 0，无需修补
	li		t2, 2
	beq		t4, t2, trap_other    # 若 rd 为 sp (x2)，不处理

	# 计算目标寄存器在 trap frame 内的偏移量
	addi	t2, t4, -2
	slli	t2, t2, 2
	add		t2, sp, t2     # t2 现在指向目标寄存器的位置
	mv		a7, t2         # 备份该地址

	# 加载 misaligned load 地址，并计算实际生效地址
	csrr	t5, mtval       # t5 = 触发异常的地址
	addi	t5, t5, 2      # 修正偏移（确保从正确的地址开始）

	# 依次加载 4 个字节（调整存储顺序为 **大端序**）
	lbu		t3, 0(t5)      # 最高位字节
	addi	t0, t5, 1
	lbu		t2, 0(t0)      # 次高位字节
	addi	t0, t5, 2
	lbu		t1, 0(t0)      # 次低位字节
	addi	t0, t5, 3
	lbu		t6, 0(t0)      # 最低位字节

	# 调整字节顺序，使得最高地址字节存到最高位（符合测试期望）
	slli	t3, t3, 24
	slli	t2, t2, 16
	slli	t1, t1, 8
	or		t6, t6, t1
	or		t6, t6, t2
	or		t6, t6, t3

	# 存入目标寄存器
	sw		t6, 0(a7)

	# 更新 mepc，跳过异常指令
	csrr	t0, mepc
	addi	t0, t0, 4
	csrw	mepc, t0

	# 恢复所有寄存器
	lw		ra,   0(sp)
	lw		gp,   4(sp)
	lw		tp,   8(sp)
	lw		t0,  12(sp)
	lw		t1,  16(sp)
	lw		t2,  20(sp)
	lw		s0,  24(sp)
	lw		s1,  28(sp)
	lw		a0,  32(sp)
	lw		a1,  36(sp)
	lw		a2,  40(sp)
	lw		a3,  44(sp)
	lw		a4,  48(sp)
	lw		a5,  52(sp)
	lw		a6,  56(sp)
	lw		a7,  60(sp)
	addi	sp, sp, 120

	# 恢复用户 sp
	csrrw	sp, mscratch, sp

	mret

trap_other:
	addi	sp, sp, 120
	csrrw	sp, mscratch, sp
	j		terminate


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

