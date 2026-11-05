.section .text, "ax"
.align 2

# Count 704 xorshift32 samples in eight bins, then check the bin checksum.
# Re-running would require explicitly zeroing the data at Lhistogram_bins
.weak main
.type main, @function
.global histogram_benchmark
.type histogram_benchmark, @function
main:
histogram_benchmark:
    li      a1, 0x12345678
    li      a2, 704
    la      a3, .Lhistogram_bins
.Lhistogram_sample:
    slli    t0, a1, 13
    xor     a1, a1, t0
    srli    t0, a1, 17
    xor     a1, a1, t0
    slli    t0, a1, 5
    xor     a1, a1, t0

    # Select a counter using the low three bits of the generated sample.
    andi    t0, a1, 7
    slli    t0, t0, 2
    add     t0, a3, t0
    lw      t1, 0(t0)
    addi    t1, t1, 1
    sw      t1, 0(t0)
    addi    a2, a2, -1
    bnez    a2, .Lhistogram_sample

    # Fold every counter into hash = (33*hash) XOR counter, modulo 2^32.
    li      a0, 0
    addi    a4, a3, 32
.Lhistogram_hash:
    lw      t0, 0(a3)
    slli    t1, a0, 5
    add     a0, a0, t1
    xor     a0, a0, t0
    addi    a3, a3, 4
    bne     a3, a4, .Lhistogram_hash

    # Expected counters: 82, 98, 76, 89, 90, 91, 89, 89.
    li      t0, 0x7ac41d04
    sub     a0, a0, t0
    ret

#ifdef QEMU_SANITY_CHECK
# Linux maps code read-only; keep the QEMU counters in writable storage.
.section .data
#endif
.align 2
.global histogram_bins
.type histogram_bins, @object
histogram_bins:
.Lhistogram_bins:
    .zero 32
.size histogram_bins, 32
