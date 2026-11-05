.section .text, "ax"
.align 2

# Sum floor(sqrt(65535 + i*65537)) for i = 0..127.
# The expected sum is 248498; return zero on success.
.weak main
.type main, @function
.global sqrt_benchmark
.type sqrt_benchmark, @function
main:
sqrt_benchmark:
    li      a0, 0
    li      a1, 128
    li      a2, 65535
    li      a3, 65537
.Lsqrt_outer:
    mv      t0, a2                # Remainder.
    li      t1, 0                 # Partial root.
    li      t2, 0x40000000        # Highest power of four in a 32-bit word.
.Lsqrt_inner:
    add     t3, t1, t2
    srli    t1, t1, 1
    bltu    t0, t3, .Lsqrt_skip
    sub     t0, t0, t3
    add     t1, t1, t2
.Lsqrt_skip:
    srli    t2, t2, 2
    bnez    t2, .Lsqrt_inner
    add     a0, a0, t1
    add     a2, a2, a3
    addi    a1, a1, -1
    bnez    a1, .Lsqrt_outer
    li      t0, 248498
    sub     a0, a0, t0
    ret
