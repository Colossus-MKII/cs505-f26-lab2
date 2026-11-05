.section .init, "ax"
.align 2
.global entry
entry:
    /* Expected result: exception_vector[EXCEPTION_ECALL] is asserted. */
    ecall
    ebreak                      /* unreachable if ECALL is handled correctly */

