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

    # 2. 保存所有寄存器
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

    # 3. 读取 mcause，检查是否是 Misaligned Load / Store 或 Load access fault
    csrr t0, mcause
    li t1, 4   # Misaligned Load Address
    li t2, 6   # Misaligned Store Address
    li t3, 5   # Load Access Fault
    li t4, 7   # Store Access Fault
    beq t0, t1, handle_misaligned_load
    beq t0, t2, handle_misaligned_store
    beq t0, t3, handle_load_access_fault
    beq t0, t4, handle_store_access_fault

    # 其他异常，终止
    j terminate

handle_misaligned_load:
    csrr t4, mtval  # 获取未对齐地址
    beqz t4, terminate  # mtval 不能是 0，否则终止

    # 解析指令
    csrr t0, mepc
    lhu t1, 0(t0)   
    lhu t2, 2(t0)
    slli t2, t2, 16
    or t1, t1, t2

    # 确保是 `lw` 指令
    andi t3, t1, 0x7F
    li t4, 0x03
    bne t3, t4, terminate

    # 解析 rd
    srli t5, t1, 7  
    andi t5, t5, 0x1F

    # 检查 mtval 是否是合法地址
    bgeu t4, zero, load_ok
    j terminate
load_ok:

    # 逐字节读取
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

    # 存入 rd
    sw t3, 32(sp)  

    # 跳过错误指令
    addi t0, t0, 4
    csrw mepc, t0
    j restore_registers

handle_misaligned_store:
    csrr t4, mtval
    beqz t4, terminate  

    # 解析指令
    csrr t0, mepc
    lhu t1, 0(t0)   
    lhu t2, 2(t0)
    slli t2, t2, 16
    or t1, t1, t2

    # 确保是 `sw` 指令
    andi t3, t1, 0x7F
    li t4, 0x23
    bne t3, t4, terminate  

    # 解析 rs2
    srli t5, t1, 20  
    andi t5, t5, 0x1F

    # 读取 rs2 值
    lw t3, 32(sp)  

    # 逐字节存储
    sb t3, 0(t4)
    srli t3, t3, 8
    sb t3, 1(t4)
    srli t3, t3, 8
    sb t3, 2(t4)
    srli t3, t3, 8
    sb t3, 3(t4)

    # 跳过错误指令
    addi t0, t0, 4
    csrw mepc, t0
    j restore_registers

handle_load_access_fault:
    csrr t4, mtval
    beqz t4, terminate  

    # 记录错误并终止
    j terminate

handle_store_access_fault:
    csrr t4, mtval
    beqz t4, terminate  

    # 记录错误并终止
    j terminate

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

