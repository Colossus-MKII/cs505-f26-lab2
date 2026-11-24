# Identical instruction words keep source, result and destination data constant.
.section .text, "ax"
.align 2
.weak main
.type main, @function
main:
    li      a0, 0
    li      t0, 49
.Lquiet:
    .rept 18
    addi    a0, a0, 0
    .endr
    addi    t0, t0, -1
    bnez    t0, .Lquiet

    # The accumulator must still hold zero.
    snez    a0, a0
    ret
