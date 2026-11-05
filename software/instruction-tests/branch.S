.include "software/instruction-tests/test-macros.S"

.section .init, "ax"
.align 2
.global entry
entry:
    li      t0, 7
    li      t1, 7
    beq     t0, t1, 1f
    TEST_FAIL 501
1:
    li      t2, 0
    bne     t0, t1, 2f
    addi    t2, t2, 1
2:
    CHECK_EQ t2, 1, 502

    li      t1, 8
    bne     t0, t1, 3f
    TEST_FAIL 503
3:
    li      t2, 0
    beq     t0, t1, 4f
    addi    t2, t2, 1
4:
    CHECK_EQ t2, 1, 504

    li      t0, -1
    li      t1, 1
    blt     t0, t1, 5f
    TEST_FAIL 505
5:
    li      t2, 0
    bge     t0, t1, 6f
    addi    t2, t2, 1
6:
    CHECK_EQ t2, 1, 506

    bge     t1, t0, 7f
    TEST_FAIL 507
7:
    li      t2, 0
    blt     t1, t0, 8f
    addi    t2, t2, 1
8:
    CHECK_EQ t2, 1, 508

    /* The same bit patterns have the opposite unsigned ordering. */
    bltu    t1, t0, 9f
    TEST_FAIL 509
9:
    li      t2, 0
    bgeu    t1, t0, 10f
    addi    t2, t2, 1
10:
    CHECK_EQ t2, 1, 510

    bgeu    t0, t1, 11f
    TEST_FAIL 511
11:
    li      t2, 0
    bltu    t0, t1, 12f
    addi    t2, t2, 1
12:
    CHECK_EQ t2, 1, 512

    /* A backward taken branch checks negative B-immediate generation. */
    li      t0, 0
    li      t1, 3
13:
    addi    t0, t0, 1
    blt     t0, t1, 13b
    CHECK_EQ t0, 3, 513

    TEST_PASS

