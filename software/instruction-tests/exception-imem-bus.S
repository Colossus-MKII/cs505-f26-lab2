.section .init, "ax"
.align 2
.global entry
entry:
    /* The testbench should map this outside instruction memory and assert
     * EXCEPTION_IMEM_BUS_ERROR on the next fetch.
     */
    lui     t0, 0x90000
    jalr    x0, 0(t0)
    ebreak                      /* unreachable */

