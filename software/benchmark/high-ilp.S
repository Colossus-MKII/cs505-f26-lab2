# The eight add instructions within one iteration have independent results.
.section .text, "ax"
.align 2
.weak main
.type main, @function
main:
    .irp reg,t0,t1,t2,t3,t4,t5,t6,a1
    li      \reg, 0
    .endr
    li      a2, 98
.Lchains:
    .irp reg,t0,t1,t2,t3,t4,t5,t6,a1
    addi    \reg, \reg, 1
    .endr
    addi    a2, a2, -1
    bnez    a2, .Lchains

    li      a2, 98
    .irp reg,t0,t1,t2,t3,t4,t5,t6,a1
    bne     \reg, a2, .Lfail
    .endr
    li      a0, 0
    ret
.Lfail:
    li      a0, 1
    ret
