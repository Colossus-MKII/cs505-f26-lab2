/* Shared test protocol.
 *
 * A word store of 1 to MMIO address 0x104 means PASS. Any other word is a
 * failure code. Tests terminate with EBREAK after reporting their result.
 * LUI+ADDI is used for the MMIO address so the protocol still works after a
 * test intentionally attempts to corrupt x0.
 */

.macro TEST_FAIL code
    lui     t5, 0
    addi    t5, t5, 0x104
    lui     t6, 0
    addi    t6, t6, \code
    sw      t6, 0(t5)
    ebreak
.endm

.macro TEST_PASS
    lui     t5, 0
    addi    t5, t5, 0x104
    lui     t6, 0
    addi    t6, t6, 1
    sw      t6, 0(t5)
    ebreak
.endm

/* t4 is scratch. Keep failure codes in the signed 12-bit ADDI range. */
.macro CHECK_EQ reg, expected, code
    li      t4, \expected
    beq     \reg, t4, 99f
    TEST_FAIL \code
99:
.endm

