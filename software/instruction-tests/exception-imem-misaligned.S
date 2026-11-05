.section .init, "ax"
.align 2
.global entry
entry:
    /* JALR clears bit zero, but bit one remains set. The next fetch must
     * assert EXCEPTION_IMEM_MISALIGNMENT.
     */
    auipc   t0, 0
    addi    t0, t0, 10
    jalr    x0, 0(t0)
    ebreak                      /* unreachable */

