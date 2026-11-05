// Standalone RTL pipeline/decode regression; select this file instead of cpu_tb.v.
`include "src/rv32i-common/params.vh"
`include "src/rv32i-memory/config.vh"
`include "src/rv32i-three-stage/params.vh"

module tb;
    reg clock_i = 1'b0;
    reg reset_ni = 1'b0;
    wire [31:0] exception_vector;
    wire [31:0] imem_addr;
    wire        imem_req;
    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_wen;
    wire        dmem_req;

    reg [31:0] memory [0:`RAM_NUM_WORDS-1];
    wire [31:0] dmem_rdata;
    wire        dmem_valid;
    reg        dmem_err;
    reg        imem_valid;
    reg        imem_err;
    integer idx;
    integer overlap_cycles;
    integer full_pipeline_cycles;
    integer stalled_overlap_cycles;
    integer delayed_load_cycles;
    // Count active CPU cycles across the pipeline and decode tests.
    integer cycle_counter = 0;
    reg [32*255:0] vcd_name;

    rv32i_three_stage dut
    (
        .clock_i(clock_i),
        .reset_ni(reset_ni),
        .exception_vector_o(exception_vector),
        .imem_addr_o(imem_addr),
        .imem_data_i(memory[(imem_addr - RESET_VECTOR) >> 2]),
        .imem_req_o(imem_req),
        .imem_valid_i(imem_valid),
        .imem_err_i(imem_err),
        .dmem_addr_o(dmem_addr),
        .dmem_rdata_i(dmem_rdata),
        .dmem_wdata_o(dmem_wdata),
        .dmem_wstrb_o(dmem_wstrb),
        .dmem_wen_o(dmem_wen),
        .dmem_req_o(dmem_req),
        .dmem_valid_i(dmem_valid),
        .dmem_err_i(dmem_err)
    );

    assign dmem_valid = dmem_req &&
                        ((dmem_addr != 32'h80000080) || dmem_wen ||
                         (delayed_load_cycles >= 3));
    assign dmem_rdata = memory[(dmem_addr - RESET_VECTOR) >> 2];

    always #5 clock_i = ~clock_i;

    initial begin
        for (idx = 0; idx < `RAM_NUM_WORDS; idx = idx + 1)
            memory[idx] = 32'h00000013;

        memory[0] = 32'h800000b7; // lui x1, 0x80000 ; x1 = RAM_START
        memory[1] = 32'h00700513; // addi x10, x0, 7
        memory[2] = 32'h00500593; // addi x11, x0, 5
        memory[3] = 32'h00a58633; // add x12, x11, x10
        memory[4] = 32'h08c0a023; // sw x12, 0x80(x1)
        memory[5] = 32'h0800a103; // lw x2, 0x80(x1)
        memory[6] = 32'h00c10463; // beq x2, x12, +8
        memory[7] = 32'h00100693; // addi x13, x0, 1 ; skipped by branch
        memory[8] = 32'h008001ef; // jal x3, +8
        memory[9] = 32'h00200693; // addi x13, x0, 2 ; skipped by jump
        memory[10] = 32'h08d0a223; // sw x13, 0x84(x1)
        memory[11] = 32'h0830a423; // sw x3, 0x88(x1)
        memory[12] = 32'h00100073; // ebreak

        dmem_err = 1'b0;
        imem_valid = 1'b0;
        imem_err = 1'b0;
        overlap_cycles = 0;
        full_pipeline_cycles = 0;
        stalled_overlap_cycles = 0;
        delayed_load_cycles = 0;
        repeat (5) @(negedge clock_i);
        reset_ni = 1'b1;

        // Skip initial reset; retain later resets used by the decode tests.
        if ($test$plusargs("vcd") && $value$plusargs("vcd=%s", vcd_name)) begin
            $display("Dumping VCD: %0s", vcd_name);
            $dumpfile(vcd_name);
            $dumpvars(0);
        end
    end

    always @(posedge clock_i)
    begin
        // Include the current active edge, as in the workload testbenches.
        if (reset_ni)
            cycle_counter = cycle_counter + 1;

        if (reset_ni && dut.ex_valid && dut.mw_valid)
            overlap_cycles <= overlap_cycles + 1;
        if (reset_ni && dut.ex_valid && dut.mw_valid && imem_req)
            full_pipeline_cycles <= full_pipeline_cycles + 1;
        if (reset_ni && dut.ex_valid && dut.mw_valid &&
            dut.mw_is_load && !dmem_valid)
            stalled_overlap_cycles <= stalled_overlap_cycles + 1;

        if (reset_ni && dmem_req && !dmem_wen &&
            (dmem_addr == 32'h80000080) && (delayed_load_cycles < 3))
            delayed_load_cycles <= delayed_load_cycles + 1;

        if (reset_ni && imem_req)
        begin
            imem_valid <= 1'b1;
            imem_err <= 1'b0;
        end
        else begin
            imem_valid <= 1'b0;
            imem_err <= 1'b0;
        end

        if (dmem_req && dmem_wen)
        begin
            if (dmem_wstrb == 4'b1111)
                memory[(dmem_addr - RESET_VECTOR) >> 2] <= dmem_wdata;
        end
    end

    initial begin
        #10000;
        $fatal(1, "pipeline test timed out");
    end

    initial begin
        wait (exception_vector != 32'b0);
        #2;
        if (exception_vector !== (32'b1 << EXCEPTION_EBREAK))
            $fatal(1, "unexpected exception vector: %h", exception_vector);
        if (memory[32] !== 32'd12)
            $fatal(1, "memory store result mismatch: %h", memory[32]);
        if (memory[33] !== 32'b0)
            $fatal(1, "branch or jump immediate mismatch: x13=%h",
                   memory[33]);
        if (memory[34] !== (RESET_VECTOR + 32'd36))
            $fatal(1, "JAL link result mismatch: x3=%h", memory[34]);
        if (overlap_cycles < 2)
            $fatal(1, "pipeline stages did not overlap repeatedly");
        if (full_pipeline_cycles == 0)
            $fatal(1, "all three pipeline stages were never occupied");
        if (stalled_overlap_cycles == 0)
            $fatal(1, "EX did not remain occupied during the delayed load");
        if (delayed_load_cycles != 3)
            $fatal(1, "load response was not delayed as expected");

        check_illegal_instruction(32'h02001093);
        check_illegal_instruction(32'h020000b3);
        check_illegal_instruction(32'h00002063);
        check_illegal_instruction(32'h000000f3);
        $display("[PASS] illegal instruction decode tests");
        $display("[PASS] three-stage RV32I pipeline test");
        $display("TEST_RESULT PASS cycles=%0d", cycle_counter);
        $finish;
    end

    task check_illegal_instruction;
        input [31:0] instruction;
        begin
            @(negedge clock_i);
            reset_ni = 1'b0;
            memory[0] = instruction;
            @(negedge clock_i);
            reset_ni = 1'b1;
            wait (exception_vector != 32'b0);
            #2;
            if (exception_vector !==
                (32'b1 << EXCEPTION_ILLEGAL_INSTRUCTION))
                $fatal(1, "instruction %h had wrong exception vector: %h",
                       instruction, exception_vector);
        end
    endtask
endmodule
