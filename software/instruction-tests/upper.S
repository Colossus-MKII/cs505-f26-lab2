.include "software/instruction-tests/test-macros.S"

.section .init, "ax"
.align 2
.global entry
entry:
    lui     t0, 0x12345
    CHECK_EQ t0, 0x12345000, 101

    lui     t0, 0x80000
    CHECK_EQ t0, 0x80000000, 102

    /* AUIPC with a zero immediate must return its own PC. */
    auipc   t0, 0
    auipc   t1, 0
    addi    t1, t1, -4
    beq     t0, t1, 1f
    TEST_FAIL 103
1:
    /* Check that AUIPC adds the complete U-immediate to the instruction PC. */
    auipc   t0, 0x12345
    auipc   t1, 0
    addi    t1, t1, -4
    lui     t2, 0x12345
    add     t1, t1, t2
    beq     t0, t1, 2f
    TEST_FAIL 104
2:
    TEST_PASS

