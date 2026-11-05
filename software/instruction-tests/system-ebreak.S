.include "software/instruction-tests/test-macros.S"

.section .init, "ax"
.align 2
.global entry
entry:
    /* Report success first; the normal testbench should then accept EBREAK. */
    TEST_PASS

