.section .init, "ax"
.align 2
.global entry
entry:
    /* The testbench should map this outside data memory and assert
     * EXCEPTION_DMEM_BUS_ERROR for the load.
     */
    lui     t0, 0x90000
    lw      t1, 0(t0)
    ebreak                      /* unreachable */

