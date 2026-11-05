.section .text, "ax"
.align 2

# Count the 31 primes through 127. Return zero on success.
.weak main
.type main, @function
.global sieve127_benchmark
.type sieve127_benchmark, @function
main:
sieve127_benchmark:
    # Each byte represents an odd candidate: 3, 5, ..., 127.
    la      t0, .Lsieve_flags
    addi    t1, t0, 63
    mv      t2, t0
    li      t3, 1
.Lsieve_init:
    sb      t3, 0(t2)
    addi    t2, t2, 1
    bne     t2, t1, .Lsieve_init

    li      a0, 1                 # Include the even prime, 2.
    mv      t2, t0
    li      t3, 3
.Lsieve_outer:
    lbu     t4, 0(t2)
    beqz    t4, .Lsieve_next
    addi    a0, a0, 1

    # Start at 3*p; a byte stride of p advances the candidate by 2*p.
    add     t4, t2, t3
    bgeu    t4, t1, .Lsieve_next
.Lsieve_mark:
    sb      zero, 0(t4)
    add     t4, t4, t3
    bltu    t4, t1, .Lsieve_mark
.Lsieve_next:
    addi    t2, t2, 1
    addi    t3, t3, 2
    bne     t2, t1, .Lsieve_outer
    addi    a0, a0, -31
    ret

#ifdef QEMU_SANITY_CHECK
# Linux maps code read-only; keep the QEMU flags in writable storage.
.section .data
#endif
.align 2
.global sieve127_flags
.type sieve127_flags, @object
sieve127_flags:
.Lsieve_flags:
    .zero 64
.size sieve127_flags, 64
