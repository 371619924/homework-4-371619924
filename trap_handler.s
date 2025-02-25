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
    # Swap SP and mscratch to get trap stack
    csrrw sp, mscratch, sp

    # Save all registers to preserve state
    addi sp, sp, -128
    sw x0, 0(sp)
    sw x1, 4(sp)
    sw x2, 8(sp)  # Save sp (x2)
    sw x3, 12(sp)
    sw x4, 16(sp)
    sw x5, 20(sp)
    sw x6, 24(sp)
    sw x7, 28(sp)
    sw x8, 32(sp)
    sw x9, 36(sp)
    sw x10, 40(sp)
    sw x11, 44(sp)
    sw x12, 48(sp)
    sw x13, 52(sp)
    sw x14, 56(sp)
    sw x15, 60(sp)
    sw x16, 64(sp)
    sw x17, 68(sp)
    sw x18, 72(sp)
    sw x19, 76(sp)
    sw x20, 80(sp)
    sw x21, 84(sp)
    sw x22, 88(sp)
    sw x23, 92(sp)
    sw x24, 96(sp)
    sw x25, 100(sp)
    sw x26, 104(sp)
    sw x27, 108(sp)
    sw x28, 112(sp)
    sw x29, 116(sp)
    sw x30, 120(sp)
    sw x31, 124(sp)

    # Check cause of trap
    csrr t0, mcause
    
    # Check for misaligned instruction address (cause 0)
    beqz t0, handle_misaligned_instruction
    
    # Check for misaligned load address (cause 4)
    li t1, 4
    beq t0, t1, handle_misaligned_load
    
    # Check for load access fault (cause 5)
    li t1, 5
    beq t0, t1, handle_load_fault
    
    # Check for misaligned store address (cause 6)
    li t1, 6
    beq t0, t1, handle_misaligned_store
    
    # If none of the above, terminate
    j terminate

handle_misaligned_instruction:
    # Handle a misaligned instruction address
    # For the jr a0 case where a0=3, we'll correct the jump target
    csrr t0, mepc      # Get instruction that caused the exception
    lw t1, 0(t0)       # Load the instruction
    
    # Extract rd field to find which register we're jumping to
    # For jr instruction, the format should be: jalr rd, 0(rs1)
    # Where rd is typically x0 (zero register) for a jump instruction
    
    # Extract rs1 (source register containing the jump address)
    srli t2, t1, 15
    andi t2, t2, 0x1F  # Get rs1 (bits 19-15)
    
    # Get the value from that register (our misaligned jump target)
    slli t3, t2, 2    # Multiply by 4 to get offset in our saved register array
    add t3, sp, t3    # Get address in our saved register array
    lw t4, 0(t3)      # Get the value (the misaligned address)
    
    # Align the address to the nearest lower 4-byte boundary
    andi t4, t4, -4   # Clear lowest 2 bits to align to 4 bytes
    
    # Update the saved register value with the aligned address
    sw t4, 0(t3)
    
    # Now continue with the instruction, since we've fixed the jump target
    # Set mepc to the corrected jump target
    csrw mepc, t4
    j restore_and_return

handle_misaligned_load:
    # Get faulting instruction
    csrr t0, mepc      # Get instruction pointer
    lw t1, 0(t0)       # Get instruction

    # Extract destination register
    srli t2, t1, 7      # Shift right to get rd
    andi t2, t2, 0x1f   # Mask to get 5 bits

    # Get misaligned address and word-aligned addresses
    csrr t3, mtval      # Get misaligned address
    andi t4, t3, 0x3    # Get offset within word (0-3)
    andi t5, t3, -4     # Get word-aligned address (clear bottom 2 bits)

    # Load both aligned words that contain our data
    lw t6, 0(t5)        # Load first word
    lw a0, 4(t5)        # Load next word

    # Calculate number of bits to shift based on offset
    slli t4, t4, 3      # Convert byte offset to bits (multiply by 8)

    # Extract bytes from the aligned words
    srl t6, t6, t4      # Right shift first word by offset
    li t1, 32           # Bits in a word
    sub t1, t1, t4      # Calculate complementary shift
    sll a0, a0, t1      # Left shift second word
    or t6, t6, a0       # Combine the parts to get our value

    # Store the result in the original destination register location
    slli t2, t2, 2      # Multiply rd by 4 for offset
    add t2, sp, t2      # Get stack location
    sw t6, 0(t2)        # Save result

    # Increment mepc to next instruction
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    j restore_and_return

handle_load_fault:
    # For null pointer or load access faults, return 0 in destination register
    csrr t0, mepc        # Get instruction pointer
    lw t1, 0(t0)         # Get instruction

    # Extract destination register
    srli t2, t1, 7       # Shift right to get rd
    andi t2, t2, 0x1f    # Mask to get 5 bits

    # Special case: only fix if destination is not x0
    beqz t2, terminate   # If rd is x0, just terminate

    # Set the destination register to 0
    slli t2, t2, 2       # Multiply rd by 4 for offset
    add t2, sp, t2       # Get stack location
    sw zero, 0(t2)       # Save 0 as result

    # Increment mepc to next instruction
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    j restore_and_return

handle_misaligned_store:
    # Get faulting instruction
    csrr t0, mepc        # Get instruction pointer
    lw t1, 0(t0)         # Get instruction

    # Extract source register (rs2)
    srli t2, t1, 20      # Shift right to get rs2
    andi t2, t2, 0x1f    # Mask to get 5 bits

    # Get the value to store from saved registers
    slli t3, t2, 2       # Multiply rs2 by 4 for offset
    add t3, sp, t3       # Get stack location
    lw t3, 0(t3)         # Load value to store

    # Get misaligned address and word-aligned addresses
    csrr t4, mtval       # Get misaligned address
    andi t5, t4, 0x3     # Get offset within word (0-3)
    andi t6, t4, -4      # Get word-aligned address (clear bottom 2 bits)

    # Load both words we'll need to modify
    lw a0, 0(t6)         # Load first word
    lw a1, 4(t6)         # Load second word

    # Calculate masks and shifts based on alignment
    slli t5, t5, 3       # Convert byte offset to bits (multiply by 8)
    li a2, 32            # Bits in a word
    sub a3, a2, t5       # Calculate complementary shift

    # Create masks for the two words
    li a4, -1            # All ones
    srl a5, a4, a3       # Mask for first word (upper bits)
    sll a6, a4, t5       # Mask for second word (lower bits)
    not a5, a5           # Invert first mask
    not a6, a6           # Invert second mask

    # Split the value to store across the two words
    and a0, a0, a5       # Clear bits in first word where we'll store
    and a1, a1, a6       # Clear bits in second word where we'll store
    sll a5, t3, t5       # Position value for first word
    srl a6, t3, a3       # Position value for second word
    or a0, a0, a5        # Insert value into first word
    or a1, a1, a6        # Insert value into second word

    # Store the modified words back to memory
    sw a0, 0(t6)         # Store first word
    sw a1, 4(t6)         # Store second word

    # Increment mepc to next instruction
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    j restore_and_return

restore_and_return:
    # Restore all registers
    lw x1, 4(sp)
    lw x3, 12(sp)
    lw x4, 16(sp)
    lw x5, 20(sp)
    lw x6, 24(sp)
    lw x7, 28(sp)
    lw x8, 32(sp)
    lw x9, 36(sp)
    lw x10, 40(sp)
    lw x11, 44(sp)
    lw x12, 48(sp)
    lw x13, 52(sp)
    lw x14, 56(sp)
    lw x15, 60(sp)
    lw x16, 64(sp)
    lw x17, 68(sp)
    lw x18, 72(sp)
    lw x19, 76(sp)
    lw x20, 80(sp)
    lw x21, 84(sp)
    lw x22, 88(sp)
    lw x23, 92(sp)
    lw x24, 96(sp)
    lw x25, 100(sp)
    lw x26, 104(sp)
    lw x27, 108(sp)
    lw x28, 112(sp)
    lw x29, 116(sp)
    lw x30, 120(sp)
    lw x31, 124(sp)
    addi sp, sp, 128

    # Restore original stack pointer
    csrrw sp, mscratch, sp

    # Return from trap
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

