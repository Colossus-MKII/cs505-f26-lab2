# Complementing each stored word flips all 32 bits on every rewrite.
.section .text, "ax"
.align 2
.weak main
.type main, @function
main:
    addi    sp, sp, -16
    li      t0, 0x55555555
    not     t1, t0
    li      t2, 55
.Lswitch:
    .rept 2
    sw      t0, 0(sp)
    sw      t1, 4(sp)
    lw      t3, 0(sp)
    lw      t4, 4(sp)
    sw      t1, 0(sp)
    sw      t0, 4(sp)
    lw      t3, 0(sp)
    lw      t4, 4(sp)
    .endr
    addi    t2, t2, -1
    bnez    t2, .Lswitch

    # Fold both last readbacks into a single pass/fail result.
    xor     t3, t3, t1
    xor     t4, t4, t0
    or      a0, t3, t4
    snez    a0, a0
    addi    sp, sp, 16
    ret
