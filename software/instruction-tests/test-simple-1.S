.section .init, "ax"
.align 2

# entry point
.weak entry
.global entry
entry:
    li      a0, 0x00000100 # MMIO address
    li      a1, 15
    
.loop:
    sw      a1, 4(a0)
    addi    a1, a1, -1
    bnez    a1, .loop

    ebreak