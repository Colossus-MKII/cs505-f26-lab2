.section .text, "ax"
.align 2

# a0 == 0 is pass
.weak main
.type main, @function
main:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    li      a0, 47
    call    get_nth_fibonacci
    li      a1, 0xb11924e1
    sub     a0, a0, a1
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

# initialization:
#    input: a0 (number to take fib of)
#    output: a0 (result)
.global get_nth_fibonacci
.type get_nth_fibonacci, @function
get_nth_fibonacci:
    addi    sp, sp, -16
    sw      a0, 12(sp)
    lw      a4, 12(sp)
    li      a5, 1
    bgtu    a4, a5, .Lget_nth_fibonacci_init
    lw      a0, 12(sp)
.Lget_nth_fibonacci_done:
    addi    sp, sp, 16
    jr      ra
.Lget_nth_fibonacci_loop:
    add     a0, a3, a5
    addi    a4, a4, 1
    mv      a3, a5
    mv      a5, a0
.Lget_nth_fibonacci_begin_loop:
    lw      a2, 12(sp)
    bgeu    a2, a4, .Lget_nth_fibonacci_loop
    j       .Lget_nth_fibonacci_done
.Lget_nth_fibonacci_init:
    li      a4, 2
    li      a0, 0
    li      a3, 0
    j       .Lget_nth_fibonacci_begin_loop