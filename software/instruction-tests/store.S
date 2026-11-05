.include "software/instruction-tests/test-macros.S"

.option norelax
.section .init, "ax"
.align 2
.global entry
entry:
    la      t0, test_data

    li      t1, 0xaa
    sb      t1, 1(t0)
    lw      t2, 0(t0)
    CHECK_EQ t2, 0x1122aa44, 801

    li      t1, 0xbbcc
    sh      t1, 2(t0)
    lw      t2, 0(t0)
    CHECK_EQ t2, 0xbbccaa44, 802

    li      t1, 0xdeadbeef
    sw      t1, 0(t0)
    lw      t2, 0(t0)
    CHECK_EQ t2, 0xdeadbeef, 803

    /* Exercise the other byte lanes without disturbing their neighbors. */
    li      t1, 0x55
    sb      t1, 0(t0)
    sb      t1, 2(t0)
    sb      t1, 3(t0)
    lw      t2, 0(t0)
    CHECK_EQ t2, 0x5555be55, 804

    TEST_PASS

.align 2
test_data:
    .word 0x11223344

