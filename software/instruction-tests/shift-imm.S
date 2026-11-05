.include "software/instruction-tests/test-macros.S"

.section .init, "ax"
.align 2
.global entry
entry:
    li      t0, 1
    slli    t1, t0, 0
    CHECK_EQ t1, 1, 301
    slli    t1, t0, 31
    CHECK_EQ t1, 0x80000000, 302

    /* A negative source catches accidental sign fill during SLL. */
    li      t0, 0x80000001
    slli    t1, t0, 1
    CHECK_EQ t1, 2, 303

    srli    t1, t0, 1
    CHECK_EQ t1, 0x40000000, 304
    srli    t1, t0, 31
    CHECK_EQ t1, 1, 305

    srai    t1, t0, 1
    CHECK_EQ t1, 0xc0000000, 306
    srai    t1, t0, 31
    CHECK_EQ t1, 0xffffffff, 307

    TEST_PASS

