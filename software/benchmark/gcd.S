.section .text, "ax"
.align 2

# a0 == 0 is pass
.weak main
.type main, @function
main:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    li      a0, 3221225472
    li      a1, 2147483648
    call    gcd
    li      a1, 1073741824
    sub     a0, a0, a1
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

# initialization:
#    input: a0 and a1 (numbers to take gcd of)
#    output: a0 (result)
.global gcd
.type gcd, @function
gcd:
    mv      a5, a0
    mv      a0, a1
    beq     a5, zero, .Lgcd_early_exit_0
    bne     a1, zero, .Lgcd_early_exit_1
    mv      a0, a5
.Lgcd_early_exit_0:
    ret
.Lgcd_loop_1:
    bleu    a5, a0, .Lgcd_loop_0
    sub     a5, a5, a0
.Lgcd_early_exit_1:
    bne     a5, a0, .Lgcd_loop_1
    ret
.Lgcd_loop_0:
    sub     a0, a0, a5
    j       .Lgcd_early_exit_1
