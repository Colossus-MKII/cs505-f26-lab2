# Eight dependent ALU instructions per iteration form one long recurrence.
.section .text, "ax"
.align 2
.weak main
.type main, @function
main:
    li      t0, 0
    li      a2, 98
.Lchain:
    .rept 8
    addi    t0, t0, 1
    .endr
    addi    a2, a2, -1
    bnez    a2, .Lchain

    # With 98 passes, the last value of the chain must be 784.
    addi    t0, t0, -784
    snez    a0, t0
    ret
