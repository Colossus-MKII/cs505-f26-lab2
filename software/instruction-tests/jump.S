.include "software/instruction-tests/test-macros.S"

.option norelax
.section .init, "ax"
.align 2
.global entry
entry:
    /* The JAL instruction is four bytes after the AUIPC, so its link is P+8. */
    auipc   t2, 0
    jal     t0, 1f
    TEST_FAIL 601
1:
    addi    t2, t2, 8
    beq     t0, t2, 2f
    TEST_FAIL 602
2:
    /* Exercise a backward JAL and verify its link address. */
    jal     x0, 4f
3:
    jal     x0, 5f
4:
    jal     t0, 3b
5:
    la      t1, 5b
    beq     t0, t1, 6f
    TEST_FAIL 603
6:
    /* JALR must clear bit zero of the computed target. */
    la      t1, 8f
    addi    t1, t1, 1
    jalr    t0, 0(t1)
7:
    TEST_FAIL 604
8:
    la      t2, 7b
    beq     t0, t2, 9f
    TEST_FAIL 605
9:
    TEST_PASS

