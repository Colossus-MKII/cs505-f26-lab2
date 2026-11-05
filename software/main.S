.section .init, "ax"
.align 2

# entry point
.global entry
entry:
    la      sp, stack_hi
    call    main
    la      a1, 0x00000100 # MMIO address
    # main returns zero on success; report 1 for pass and 0 for fail.
    seqz    a0, a0
    sw      a0, 4(a1)
    ebreak

.section .fini, "ax"
.align 2

# should be unreachable
death_loop:
    j death_loop

# 32 bytes of stack
.align 4
stack_lo:
.rept 8
    nop
.endr
stack_hi:
