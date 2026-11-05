.section .text, "ax"
.align 2

# a0 == 0 is pass
.weak main
.type main, @function
main:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    li      a0, 0xac42b134
    call    popcount
    addi    a0, a0, -13
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

# initialization:
#    input: a0 (number to take popcount of)
#    output: a0 (result)
.global popcount
.type popcount, @function
popcount:
    li      t0, 0x55555555
    srli    t1, a0, 1
    and     t1, t1, t0
    sub     a0, a0, t1

    li      t0, 0x33333333
    srli    t1, a0, 2
    and     t1, t1, t0
    and     a0, a0, t0
    add     a0, a0, t1

    srli    t1, a0, 4
    add     a0, a0, t1
    li      t0, 0x0f0f0f0f
    and     a0, a0, t0

    srli    t1, a0, 16
    add     a0, a0, t1
    srli    t1, a0, 8
    add     a0, a0, t1
    andi    a0, a0, 63
    ret
