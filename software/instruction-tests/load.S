.include "software/instruction-tests/test-macros.S"

.option norelax
.section .init, "ax"
.align 2
.global entry
entry:
    la      t0, test_data

    lb      t1, 0(t0)
    CHECK_EQ t1, 1, 701
    lb      t1, 1(t0)
    CHECK_EQ t1, 127, 702
    lb      t1, 2(t0)
    CHECK_EQ t1, -1, 703
    lb      t1, 3(t0)
    CHECK_EQ t1, -128, 704

    lbu     t1, 2(t0)
    CHECK_EQ t1, 255, 705
    lbu     t1, 3(t0)
    CHECK_EQ t1, 128, 706

    lh      t1, 0(t0)
    CHECK_EQ t1, 0x7f01, 707
    lh      t1, 2(t0)
    CHECK_EQ t1, 0xffff80ff, 708
    lhu     t1, 2(t0)
    CHECK_EQ t1, 0x80ff, 709

    lw      t1, 0(t0)
    CHECK_EQ t1, 0x80ff7f01, 710

    TEST_PASS

.align 2
test_data:
    .word 0x80ff7f01

