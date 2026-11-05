.include "software/instruction-tests/test-macros.S"

.section .init, "ax"
.align 2
.global entry
entry:
    li      t0, 0x7fffffff
    li      t1, 1
    add     t2, t0, t1
    CHECK_EQ t2, 0x80000000, 401
    sub     t2, t1, t0
    CHECK_EQ t2, 0x80000002, 402

    li      t0, -1
    li      t1, 1
    slt     t2, t0, t1
    CHECK_EQ t2, 1, 403
    sltu    t2, t0, t1
    CHECK_EQ t2, 0, 404

    li      t0, 0x55aa55aa
    li      t1, 0x0ff00ff0
    xor     t2, t0, t1
    CHECK_EQ t2, 0x5a5a5a5a, 405
    or      t2, t0, t1
    CHECK_EQ t2, 0x5ffa5ffa, 406
    and     t2, t0, t1
    CHECK_EQ t2, 0x05a005a0, 407

    /* Register shifts must use only rs2[4:0]; 33 therefore means 1. */
    li      t0, 0x80000001
    li      t1, 33
    sll     t2, t0, t1
    CHECK_EQ t2, 2, 408
    srl     t2, t0, t1
    CHECK_EQ t2, 0x40000000, 409
    sra     t2, t0, t1
    CHECK_EQ t2, 0xc0000000, 410

    TEST_PASS

