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
	# 交换 sp 与 mscratch，使 sp 变为内核栈指针，mscratch 保存用户 sp
	csrrw	sp, mscratch, sp

	# 分配 trap frame 空间，保存 30 个寄存器（x1, x3–x31）共 30×4 = 120 字节
	addi	sp, sp, -120

	# 按固定顺序保存寄存器
	sw	ra,   0(sp)		# 保存 ra (x1)
	sw	gp,   4(sp)		# 保存 gp (x3)
	sw	tp,   8(sp)		# 保存 tp (x4)
	sw	t0,  12(sp)		# 保存 t0 (x5)
	sw	t1,  16(sp)		# 保存 t1 (x6)
	sw	t2,  20(sp)		# 保存 t2 (x7)
	sw	t3,  24(sp)		# 保存 t3 (x8 / s0)
	sw	t4,  28(sp)		# 保存 t4 (x9 / s1)
	sw	t5,  32(sp)		# 保存 t5 (x10 / a0)
	sw	t6,  36(sp)		# 保存 t6 (x11 / a1)
	sw	a0,  40(sp)		# 保存 a0 (x12 / a2)
	sw	a1,  44(sp)		# 保存 a1 (x13 / a3)
	sw	a2,  48(sp)		# 保存 a2 (x14 / a4)
	sw	a3,  52(sp)		# 保存 a3 (x15 / a5)
	sw	a4,  56(sp)		# 保存 a4 (x16 / a6)
	sw	a5,  60(sp)		# 保存 a5 (x17 / a7)
	sw	a6,  64(sp)		# 保存 a6 (x18 / s2)
	sw	a7,  68(sp)		# 保存 a7 (x19 / s3)
	sw	s0,  72(sp)		# 保存 s0 (x20 / s4)
	sw	s1,  76(sp)		# 保存 s1 (x21 / s5)
	sw	s2,  80(sp)		# 保存 s2 (x22 / s6)
	sw	s3,  84(sp)		# 保存 s3 (x23 / s7)
	sw	s4,  88(sp)		# 保存 s4 (x24 / s8)
	sw	s5,  92(sp)		# 保存 s5 (x25 / s9)
	sw	s6,  96(sp)		# 保存 s6 (x26 / s10)
	sw	s7, 100(sp)		# 保存 s7 (x27 / s11)
	sw	s8, 104(sp)		# 保存 s8 (x28 / t3)
	sw	s9, 108(sp)		# 保存 s9 (x29 / t4)
	sw	s10,112(sp)		# 保存 s10 (x30 / t5)
	sw	s11,116(sp)		# 保存 s11 (x31 / t6)

	# 检查 mcause 是否为 4（misaligned load），否则跳转 trap_other
	csrr	t0, mcause
	li		t1, 4
	bne		t0, t1, trap_other

	# 从 mepc 取出导致异常的 lw 指令地址，并加载指令字
	csrr	t0, mepc		# t0 = 出错指令地址
	lw		t1, 0(t0)		# t1 = 指令字

	# 检查 opcode（低 7 位）是否为 0x03（load 指令）
	andi	t2, t1, 0x7F
	li		t3, 0x03
	bne		t2, t3, trap_other

	# 检查 funct3（位 [14:12]）是否为 0x2（lw 指令）
	srai	t2, t1, 12
	andi	t2, t2, 0x7
	li		t3, 0x2
	bne		t2, t3, trap_other

	# 提取目标寄存器号 rd（位 [11:7]）
	srai	t4, t1, 7
	andi	t4, t4, 0x1F	# t4 = rd
	beq		t4, zero, trap_other	# 若 rd 为 0，则无须补丁
	li		t2, 2
	beq		t4, t2, trap_other	# 若 rd 为 sp (x2)，不处理
	# 若 rd == 1，则补丁偏移为 0；否则，偏移 = (rd - 2) * 4
	li		t2, 1
	beq		t4, t2, update_reg_offset
	addi	t2, t4, -2
	slli	t2, t2, 2
	j		update_reg_done
update_reg_offset:
	li		t2, 0
update_reg_done:
	# 计算 trap frame 中对应保存目标寄存器的位置
	add		t2, sp, t2
	# 将该地址保存到 a7（后续用来写入修补数据）
	mv		a7, t2

	# 重构 misaligned load 数据：依次加载 4 个字节
	csrr	t5, mtval		# t5 = 触发异常的内存地址（应为 s0+2）
	lbu		t6, 0(t5)		# 加载字节0
	addi	t0, t5, 1		# 计算字节1的地址
	lbu		t1, 0(t0)		# 加载字节1
	addi	t0, t5, 2		# 计算字节2的地址
	lbu		t2, 0(t0)		# 加载字节2
	addi	t0, t5, 3		# 计算字节3的地址
	lbu		t3, 0(t0)		# 加载字节3

	# 将各字节移位并组合成 32 位数据
	slli	t1, t1, 8
	slli	t2, t2, 16
	slli	t3, t3, 24
	or		t6, t6, t1
	or		t6, t6, t2
	or		t6, t6, t3

	# 将修补后的数据写入 trap frame 中目标寄存器对应位置
	sw		t6, 0(a7)

	# 更新 mepc（跳过出错指令，+4 字节）
	csrr	t0, mepc
	addi	t0, t0, 4
	csrw	mepc, t0

	# 从 trap frame 中恢复所有寄存器
	lw		ra,   0(sp)
	lw		gp,   4(sp)
	lw		tp,   8(sp)
	lw		t0,  12(sp)
	lw		t1,  16(sp)
	lw		t2,  20(sp)
	lw		t3,  24(sp)
	lw		t4,  28(sp)
	lw		t5,  32(sp)
	lw		t6,  36(sp)
	lw		a0,  40(sp)
	lw		a1,  44(sp)
	lw		a2,  48(sp)
	lw		a3,  52(sp)
	lw		a4,  56(sp)
	lw		a5,  60(sp)
	lw		a6,  64(sp)
	lw		a7,  68(sp)
	lw		s0,  72(sp)
	lw		s1,  76(sp)
	lw		s2,  80(sp)
	lw		s3,  84(sp)
	lw		s4,  88(sp)
	lw		s5,  92(sp)
	lw		s6,  96(sp)
	lw		s7, 100(sp)
	lw		s8, 104(sp)
	lw		s9, 108(sp)
	lw		s10,112(sp)
	lw		s11,116(sp)
	addi	sp, sp, 120

	# 恢复用户 sp：将 mscratch 中的用户 sp 换回 sp
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

