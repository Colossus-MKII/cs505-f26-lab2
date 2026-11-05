.include "software/instruction-tests/test-macros.S"

.section .init, "ax"
.align 2
.global entry
entry:
    addi    t0, x0, 2047
    CHECK_EQ t0, 2047, 201
    addi    t0, x0, -2048
    CHECK_EQ t0, 0xfffff800, 202
    addi    t1, t0, -1
    CHECK_EQ t1, 0xfffff7ff, 203

    li      t0, -5
    slti    t1, t0, -4
    CHECK_EQ t1, 1, 204
    slti    t1, t0, -6
    CHECK_EQ t1, 0, 205

    li      t0, 0
    sltiu   t1, t0, -1
    CHECK_EQ t1, 1, 206
    li      t0, -1
    sltiu   t1, t0, -1
    CHECK_EQ t1, 0, 207

    li      t0, 0x55aa55aa
    xori    t1, t0, -1
    CHECK_EQ t1, 0xaa55aa55, 208
    ori     t1, t0, 0x0f0
    CHECK_EQ t1, 0x55aa55fa, 209
    andi    t1, t0, 0x0ff
    CHECK_EQ t1, 0x000000aa, 210

    TEST_PASS

