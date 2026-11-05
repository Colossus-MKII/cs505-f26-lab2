.include "software/instruction-tests/test-macros.S"

.section .init, "ax"
.align 2
.global entry
entry:
    /* MUL encoding: legal only with the unsupported M extension.
     * Expected result: EXCEPTION_ILLEGAL_INSTRUCTION, with no MMIO write.
     */
    .word   0x021080b3
    TEST_FAIL 1001

