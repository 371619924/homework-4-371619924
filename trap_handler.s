##
# Copyright (c) 1990-2023 James R. Larus.
# Copyright (c) 2023 LupLab.
#
# SPDX-License-Identifier: AGPL-3.0-only
##

# This a modified version of the default system code for VRV.

# It contains three parts:

# 1. The machine boot code, starting from global label
#    `__mstart`. This boot code sets up the trap vector, and jumps to
#    label `__user_bootstrap` in user mode.

# 2. The trap handler, which is called upon an exception (interrupts
#    are not enabled by default).
	
# 3. The small user bootstrap code, starting from global label
#    `__user_bootstrap`. This bootstrap code calls `main`, which is expected to
#     be defined by the user program. If main returns, the bootstrap code exits
#     with the value returned by main.

# You will need to modify the trap handler to:

# a) Save all registers

# b) Examine the cause to determine if it is a misaligned load word.

# c) If it IS a misaligned load word, it should patch up the
# result and resume execution at the next instruction.

# d) Otherwise, it should jump to the terminate operation
# which is the default printing routine from VRV's default
# system file.

	## Constants
.equ    PRINT_DEC  0
.equ    PRINT_HEX   1
.equ    PRINT_CHR   3
.equ    PRINT_STR   4
.equ    EXIT        20

.equ    NEWLN_CHR   '\n'
.equ    SPACE_CHR   ' '

.equ 	KSTACK_SIZE 4096
	
# YOU can add more constants here, and you probably will want to!

## System data
    .kdata
__m_exc:    .string "  Exception"
__m_int:    .string "  Interrupt"

__m_mcause: .string "\n    MCAUSE: "
__m_mepc:   .string "\n    MEPC:   "
__m_mtval:  .string "\n    MTVAL:  "

__e0:   .string " [Misaligned instruction address]"
__e1:   .string " [Instruction access fault]"
__e2:   .string " [Illegal instruction]"
__e3:   .string " [Breakpoint]"
__e4:   .string " [Misaligned load address]"
__e5:   .string " [Load access fault]"
__e6:   .string " [Misaligned store address]"
__e7:   .string " [Store access fault]"
__e8:   .string " [User-mode ecall]"
__e11:  .string " [Machine-mode ecall]"

__i3:   .string " [Software]"
__i7:   .string " [Timer]"
__i11:  .string " [External]"

__evec: .word __e0, __e1, __e2, __e3, __e4, __e5, __e6, __e7, __e8, 0, 0, __e11
__ivec: .word 0, 0, 0, __i3, 0, 0, 0, __i7, 0, 0, 0, __i11

	.align 2

	# A small stack for kernel data
kstack:  .zero   KSTACK_SIZE

## System code
    .ktext
### Boot code
    .globl __mstart
__mstart:
    la      t0, __mtrap
    csrw    mtvec, t0

	la      t0, __user_bootstrap
	csrw    mepc, t0

	# Allocates space so the trap handler has a
	# small stack and can therefore call functions
	# itself.
	la 	t0, kstack
	li	t1, KSTACK_SIZE
	add 	t0 t0 t1
	csrw   	mscratch, t0
	mret    # Enter user bootstrap

### Trap handler

### You will need to write your own trap handler functionality here.
    
__mtrap:
    # 1. 交换 sp 和 mscratch，使 sp 指向内核栈
    csrrw sp, mscratch, sp  

    # 2. 保存所有寄存器（共 72 字节）
    addi sp, sp, -72
    sw ra, 0(sp)
    sw t0, 4(sp)
    sw t1, 8(sp)
    sw t2, 12(sp)
    sw t3, 16(sp)
    sw t4, 20(sp)
    sw t5, 24(sp)
    sw t6, 28(sp)
    sw a0, 32(sp)
    sw a1, 36(sp)
    sw a2, 40(sp)
    sw a3, 44(sp)
    sw a4, 48(sp)
    sw a5, 52(sp)
    sw a6, 56(sp)
    sw a7, 60(sp)
    sw s0, 64(sp)
    sw s1, 68(sp)

    # 3. 读取 mcause，判断是否是 misaligned load (4) 或 store (6)
    csrr t0, mcause
    li t1, 4      # Misaligned Load Address
    li t2, 6      # Misaligned Store Address
    beq t0, t1, handle_misaligned_load
    beq t0, t2, handle_misaligned_store

    # 其他异常，跳转至 terminate
    j terminate

handle_misaligned_load:
    csrr t4, mtval         # t4 = 未对齐地址
    beqz t4, terminate

    csrr t0, mepc          # 获取 faulting 指令地址
    lw t1, 0(t0)           # 取出出错指令
    li t2, 0x00002003      # lw 指令标识
    and t3, t1, t2
    bne t3, t2, terminate  # 如果不是 lw，则终止

    # 模拟 lw：逐字节读取（Little-Endian）
    lbu t3, 0(t4)
    lbu t6, 1(t4)
    slli t6, t6, 8
    or t3, t3, t6
    lbu t6, 2(t4)
    slli t6, t6, 16
    or t3, t3, t6
    lbu t6, 3(t4)
    slli t6, t6, 24
    or t3, t3, t6

    # 提取出错指令的 rd 字段（bits 11:7）
    srli t5, t1, 7
    andi t5, t5, 0x1F
    beqz t5, skip_patch_load  # 如果 rd 为 0，则不需补丁

    # 计算 rd 对应的偏移（结果存入 t7）
    # 使用 t5 保存寄存器号，t7 用于存放偏移
    li t7, 0          # 默认偏移为 0
    li t8, 1
    beq t5, t8, done_offset_load  # 若 rd == 1，则 offset = 0

    li t8, 5
    blt t5, t8, done_offset_load  # 若 rd < 5，则未保存，offset 保持 0
    li t8, 7
    ble t5, t8, { 
        # 对于 x5~x7: offset = (rd - 4) * 4
        addi t7, t5, -4
        slli t7, t7, 2
        j done_offset_load
    }

    li t8, 10
    blt t5, t8, done_offset_load  # rd < 10 未保存
    li t8, 17
    ble t5, t8, { 
        # 对于 x10~x17: offset = (rd - 10 + 8) * 4 = (rd - 2) * 4
        addi t7, t5, -2
        slli t7, t7, 2
        j done_offset_load
    }

    li t8, 28
    blt t5, t8, done_offset_load  # rd < 28 未保存
    li t8, 31
    ble t5, t8, { 
        # 对于 x28~x31: offset = (rd - 28 + 4) * 4 = (rd - 24) * 4
        addi t7, t5, -24
        slli t7, t7, 2
        j done_offset_load
    }

    li t8, 8
    beq t5, t8, { li t7, 64; j done_offset_load }  # x8 (s0)
    li t8, 9
    beq t5, t8, { li t7, 68; }                   # x9 (s1)

done_offset_load:
    add t7, sp, t7        # t7 = sp + computed offset
    sw t3, 0(t7)          # 将模拟的 load 值写入 trap frame

skip_patch_load:
    csrr t0, mepc
    addi t0, t0, 4        # 跳过出错指令
    csrw mepc, t0
    j restore_registers

handle_misaligned_store:
    csrr t4, mtval         # t4 = 未对齐的有效地址
    beqz t4, terminate

    csrr t0, mepc
    lw t1, 0(t0)           # 取出出错指令
    li t2, 0x00002023      # sw 指令标识
    and t3, t1, t2
    bne t3, t2, terminate  # 如果不是 sw，则终止

    # 提取 sw 指令中的 rs2 字段（bits 24:20）
    srli t5, t1, 20
    andi t5, t5, 0x1F
    beqz t5, load_zero_for_store  # 若 rs2 为 0，使用 0

    # 计算 rs2 对应的偏移（存入 t7）
    li t7, 0
    li t8, 1
    beq t5, t8, done_offset_store
    li t8, 5
    blt t5, t8, done_offset_store
    li t8, 7
    ble t5, t8, { 
        addi t7, t5, -4
        slli t7, t7, 2
        j done_offset_store
    }

    li t8, 10
    blt t5, t8, done_offset_store
    li t8, 17
    ble t5, t8, { 
        addi t7, t5, -2
        slli t7, t7, 2
        j done_offset_store
    }

    li t8, 28
    blt t5, t8, done_offset_store
    li t8, 31
    ble t5, t8, { 
        addi t7, t5, -24
        slli t7, t7, 2
        j done_offset_store
    }

    li t8, 8
    beq t5, t8, { li t7, 64; j done_offset_store }
    li t8, 9
    beq t5, t8, { li t7, 68; }

done_offset_store:
    add t7, sp, t7        # t7 = sp + computed offset
    lw t3, 0(t7)          # 取出原来保存的值（rs2的值）
    j store_done

load_zero_for_store:
    li t3, 0

store_done:
    # 模拟 sw：逐字节写入（Little-Endian）
    sb t3, 0(t4)
    srli t3, t3, 8
    sb t3, 1(t4)
    srli t3, t3, 8
    sb t3, 2(t4)
    srli t3, t3, 8
    sb t3, 3(t4)
    
    csrr t0, mepc
    addi t0, t0, 4        # 跳过出错指令
    csrw mepc, t0
    j restore_registers

restore_registers:
    lw ra, 0(sp)
    lw t0, 4(sp)
    lw t1, 8(sp)
    lw t2, 12(sp)
    lw t3, 16(sp)
    lw t4, 20(sp)
    lw t5, 24(sp)
    lw t6, 28(sp)
    lw a0, 32(sp)
    lw a1, 36(sp)
    lw a2, 40(sp)
    lw a3, 44(sp)
    lw a4, 48(sp)
    lw a5, 52(sp)
    lw a6, 56(sp)
    lw a7, 60(sp)
    lw s0, 64(sp)
    lw s1, 68(sp)
    addi sp, sp, 72
    csrrw sp, mscratch, sp
    mret


# This code is taken from the default VRV system code.  It prints out
# a message indicating the cause of an unhandled exception.  We are
# keeping this in this form to make it easier for you to debug.

# It is allowed to trash registers (unlike the normal trap handler)
# because it never returns	
terminate:
    csrr    t0, mcause      # Get mcause CSR
    li      t1, 0x80000000
    and     t1, t0, t1      # mcause & 0x80000000
    beqz    t1, ____not_interrupt   # mcause has bit 31 set for an interrupt

    # 2a. Interrupt
    la      a0, __m_int     # Interrupt header message
    xor     t0, t0, t1      # Isolate interrupt code
    la      t1, __ivec      # Interrupt vector
    j       ____print_trap_message

    # 2b. Exception
____not_interrupt:
    la      a0, __m_exc     # Exception header message
    la      t1, __evec      # Isolate exception code

    # 3. Print header message
____print_trap_message:
    li      a7, PRINT_STR
    ecall

    # 4. Print vector entry for this exception/interrupt
    slli    a0, t0, 2       # mcause * 4
    add     a0, t1, a0      # Index in vector
    lw      a0, (a0)        # Entry from vector
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
	li a7, PRINT_STR
	ecall
	ret

