.section .text, "ax"
.align 2

# a0 == 0 is pass
.weak main
.type main, @function
main:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    la      a0, .Lcrc_input
    li      a1, 9
    call    crc32
    li      t0, 0xcbf43926
    xor     a0, a0, t0
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

# CRC-32/ISO-HDLC, using the reflected polynomial 0xedb88320.
# input: a0 = byte-array address, a1 = byte count
# output: a0 = checksum
.global crc32
.type crc32, @function
crc32:
    mv      a2, a0
    li      a0, -1
    li      t0, 0xedb88320
    beqz    a1, .Lcrc_done
.Lcrc_byte:
    lbu     t1, 0(a2)
    xor     a0, a0, t1
    li      t2, 8
.Lcrc_bit:
    # Turn the low bit into a mask to select the polynomial without a branch.
    andi    t3, a0, 1
    neg     t3, t3
    and     t3, t3, t0
    srli    a0, a0, 1
    xor     a0, a0, t3
    addi    t2, t2, -1
    bnez    t2, .Lcrc_bit
    addi    a2, a2, 1
    addi    a1, a1, -1
    bnez    a1, .Lcrc_byte
.Lcrc_done:
    not     a0, a0
    ret

.align 2
.Lcrc_input:
    .ascii "123456789"