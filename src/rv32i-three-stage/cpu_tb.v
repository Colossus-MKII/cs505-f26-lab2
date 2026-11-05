`timescale 1ns/1ps
`include "src/rv32i-common/params.vh"
`include "src/rv32i-memory/config.vh"
`include "src/rv32i-three-stage/params.vh"

module tb;
    `include "src/rv32i-common-tb/tb_common.vh"

    reg clock_i = 0;
    reg reset_ni = 0;
    always #5 clock_i = ~clock_i;

    wire [31:0] exception_vector;
    wire [31:0] imem_addr, dmem_addr, dmem_wdata;
    wire [3:0] dmem_wstrb;
    wire imem_req, dmem_req, dmem_wen;
    wire [31:0] imem_data, dmem_rdata;
    wire imem_valid, imem_err, dmem_valid, dmem_err;

    rv32i_three_stage dut (
        .clock_i(clock_i), .reset_ni(reset_ni),
        .exception_vector_o(exception_vector),
        .ex_valid(), .mw_is_load(),
        .imem_addr_o(imem_addr), .imem_data_i(imem_data),
        .imem_req_o(imem_req), .imem_valid_i(imem_valid),
        .imem_err_i(imem_err),
        .dmem_addr_o(dmem_addr), .dmem_rdata_i(dmem_rdata),
        .dmem_wdata_o(dmem_wdata), .dmem_wstrb_o(dmem_wstrb),
        .dmem_wen_o(dmem_wen), .dmem_req_o(dmem_req),
        .dmem_valid_i(dmem_valid), .dmem_err_i(dmem_err)
    );

    reg [31:0] memory [0:RAM_SIZE_BYTES/4-1];
    reg [1023:0] hex_filename;
    reg [2047:0] vcd_filename;
    reg [8*32-1:0] expected_exception_descriptor;
    integer expected_exception = -1, expected_result = 1;
    integer max_cycles = 5000, cycle_counter = 0;
    integer image_file, address;
    reg finished = 0, result_seen = 0, result_failed = 0;
    reg [31:0] result_code = TB_RESULT_OK;

    // The CPU sees the same RAM and immediate-response MMIO window as the SoC.
    wire [31:0] imem_offset = imem_addr - RAM_START_BYTE_ADDR;
    wire [31:0] dmem_offset = dmem_addr - RAM_START_BYTE_ADDR;
    wire imem_is_ram = (imem_addr >= RAM_START_BYTE_ADDR) &&
                       (imem_offset < RAM_SIZE_BYTES);
    wire dmem_is_ram = (dmem_addr >= RAM_START_BYTE_ADDR) &&
                       (dmem_offset < RAM_SIZE_BYTES);
    wire dmem_is_mmio = (dmem_addr >= MMIO_START_BYTE_ADDR) &&
                       ((dmem_addr - MMIO_START_BYTE_ADDR) < MMIO_SIZE_BYTES);

    assign imem_valid = reset_ni && imem_req;
    assign imem_err = imem_valid && !imem_is_ram;
    assign imem_data = imem_valid && imem_is_ram ?
                       memory[imem_offset >> 2] : 32'hdeadbeef;
    assign dmem_valid = reset_ni && dmem_req;
    assign dmem_err = dmem_valid && !(dmem_is_ram || dmem_is_mmio);
    // The SoC workload harness supplies ASCII '!' on its input port.
    assign dmem_rdata = dmem_valid && !dmem_wen ?
                        (dmem_is_mmio ? 32'h00000021 :
                         dmem_is_ram ? memory[dmem_offset >> 2] :
                         32'hdeadbeef) : 32'hdeadbeef;

    // Commit stores on the same edge on which the CPU accepts the response.
    always @(posedge clock_i) begin
        if (dmem_valid && dmem_wen && dmem_is_ram) begin
            if (dmem_wstrb[0]) memory[dmem_offset >> 2][7:0] <= dmem_wdata[7:0];
            if (dmem_wstrb[1]) memory[dmem_offset >> 2][15:8] <= dmem_wdata[15:8];
            if (dmem_wstrb[2]) memory[dmem_offset >> 2][23:16] <= dmem_wdata[23:16];
            if (dmem_wstrb[3]) memory[dmem_offset >> 2][31:24] <= dmem_wdata[31:24];
        end
    end

    task report_result(input passed, input [31:0] code);
        begin
            if (!finished) begin
                finished = 1;
                if (passed)
                    $display("TEST_RESULT PASS cycles=%0d", cycle_counter);
                else
                    $display("TEST_RESULT FAIL code=0x%08h cycles=%0d",
                             code, cycle_counter);
                $finish;
            end
        end
    endtask

    initial begin : run_test
        if ($value$plusargs("max_cycles=%d", max_cycles)) begin end
        if ($value$plusargs("expect_result=%d", expected_result)) begin end
        if ($value$plusargs("expect_exception=%s", expected_exception_descriptor))
            expected_exception = exception_descriptor_to_bit(expected_exception_descriptor);
        if (max_cycles <= 0 || expected_exception < -1 ||
            expected_result < 0 || expected_result > 255)
            report_result(0, TS_ERR_INVALID_TEST_OPTIONS);

        if (!$value$plusargs("hex=%s", hex_filename)) begin
            $display("[FAIL] missing +hex=<program.hex>");
            report_result(0, TS_ERR_MISSING_HEX_ARGUMENT);
        end
        image_file = $fopen(hex_filename, "r");
        if (image_file == 0) begin
            $display("[FAIL] cannot open %0s", hex_filename);
            report_result(0, TS_ERR_HEX_FILE_OPEN);
        end
        $fclose(image_file);
        for (address = 0; address < RAM_SIZE_BYTES/4; address = address + 1)
            memory[address] = 0;
        $readmemh(hex_filename, memory);
        repeat (5) @(negedge clock_i);

        $display("[PHASE] CPU program execution: %0s", hex_filename);
        if ($value$plusargs("vcd=%s", vcd_filename)) begin
            $dumpfile(vcd_filename);
            $dumpvars(0);
        end
        reset_ni = 1;

        while (!finished) begin
            // Match the SoC harness: sample before the CPU's nonblocking updates.
            @(posedge clock_i);
            cycle_counter = cycle_counter + 1;
            if (dmem_valid && dmem_wen && dmem_is_mmio) begin
                $display("MMIO OUT: 0x%08h", dmem_wdata);
                if (result_seen) begin
                    result_failed = 1;
                    result_code = TS_ERR_DUPLICATE_RESULT;
                end
                else if (dmem_wstrb !== 4'b1111) begin
                    result_failed = 1;
                    result_code = TS_ERR_BAD_RESULT_STROBE;
                end
                else if (dmem_wdata !== expected_result) begin
                    result_failed = 1;
                    result_code = dmem_wdata;
                end
                result_seen = 1;
            end

            if ((^exception_vector) === 1'bx)
                report_result(0, TS_ERR_UNKNOWN_EXCEPTION_VECTOR);
            else if (exception_vector != 0) begin
                $display("[INFO] exception vector=0x%08h", exception_vector);
                if (expected_exception >= 0) begin
                    if (exception_vector === (32'b1 << expected_exception))
                        report_result(1, TB_RESULT_OK);
                    else
                        report_result(0, TS_ERR_EXCEPTION_MISMATCH);
                end
                else if (exception_vector !== (32'b1 << EXCEPTION_EBREAK))
                    report_result(0, TS_ERR_UNEXPECTED_EXCEPTION);
                else if (!result_seen)
                    report_result(0, TS_ERR_MISSING_RESULT);
                else if (result_failed)
                    report_result(0, result_code);
                else
                    report_result(1, TB_RESULT_OK);
            end
            else if (cycle_counter >= max_cycles)
                report_result(0, TS_ERR_PROGRAM_TIMEOUT);
        end
    end
endmodule
