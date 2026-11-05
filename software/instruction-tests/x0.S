.include "software/instruction-tests/test-macros.S"

.section .init, "ax"
.align 2
.global entry
entry:
    /* Preserve a known zero before attempting the architecturally ignored write. */
    addi    t1, x0, 0
    addi    x0, x0, 123
    addi    t0, x0, 0
    beq     t0, t1, 1f
    TEST_FAIL 901
1:
    /* LUI, ALU, and load writeback must also discard rd=x0. */
    lui     x0, 0x12345
    beq     x0, t1, 2f
    TEST_FAIL 902
2:
    addi    t2, x0, 5
    add     x0, t2, t2
    beq     x0, t1, 3f
    TEST_FAIL 903
3:
    la      t3, test_data
    lw      x0, 0(t3)
    beq     x0, t1, 4f
    TEST_FAIL 904
4:
    TEST_PASS

.align 2
test_data:
    .word   0x76543210


