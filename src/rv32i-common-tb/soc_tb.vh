`timescale 1ns/1ps
module tb;
    `include "src/rv32i-common-tb/soc_tb_io.vh"


    reg [31:0] program_image [0:RAM_SIZE_BYTES/4-1];
    reg [1023:0] hex_filename;
    reg [8*32-1:0] expected_exception_descriptor;
    integer expected_exception = -1, expected_result = 1;
    integer image_file, address;
    reg result_seen = 0, result_failed = 0;
    reg [7:0] result_code = 0;

    initial begin : run_test
        max_cycles = 5000;
        if ($value$plusargs("max_cycles=%d", max_cycles)) begin end
        if ($value$plusargs("expect_exception=%s", expected_exception_descriptor))
            expected_exception = exception_descriptor_to_bit(expected_exception_descriptor);
        if ($value$plusargs("expect_result=%d", expected_result)) begin end
        if (max_cycles <= 0 || expected_exception < -1 || expected_exception > 31 ||
            expected_result < 0 || expected_result > 255)
            report_result(0, SOC_ERR_INVALID_TEST_OPTIONS);
        if (!$value$plusargs("hex=%s", hex_filename)) begin
            $display("[FAIL] missing +hex=<program.hex>");
            report_result(0, SOC_ERR_MISSING_HEX_ARGUMENT);
        end
        image_file = $fopen(hex_filename, "r");
        if (image_file == 0) begin
            $display("[FAIL] cannot open %0s", hex_filename);
            report_result(0, SOC_ERR_HEX_FILE_OPEN);
        end
        $fclose(image_file);

        // Pad unused RAM, then load little-endian bytes through the host port.
        for (address = 0; address < RAM_SIZE_BYTES/4; address = address + 1)
            program_image[address] = 0;
        $readmemh(hex_filename, program_image);
        repeat (5) @(negedge clock_i);
        $display("[PHASE] Loading program: %0s", hex_filename);
        for (address = 0; address < RAM_SIZE_BYTES; address = address + 1)
            write_byte(address, program_image[address/4][8*(address%4) +: 8]);

        $display("[PHASE] CPU program execution");
        @(negedge clock_i);
        // Leave a stale host request asserted to test runtime isolation.
        io_addr = 0;
        io_wdata = 8'hff;
        io_wen = 1;
        io_req = 1;
        cycle_counter = 0;
        reset_ni = 1;
        start_waveform;

        while (!finished) begin
            // Sample before CPU nonblocking updates, including single-cycle exceptions.
            @(posedge clock_i);
            cycle_counter = cycle_counter + 1;
            if (io_valid !== 1'b0 || io_err !== 1'b0)
                report_result(0, SOC_ERR_HOST_RESPONSE_DURING_EXECUTION);
            if (io_wen_o) begin
                if (result_seen || io_data_o !== expected_result[7:0])
                    result_failed = 1;
                result_seen = 1;
                result_code = io_data_o;
            end

            if ((^exception_vector) === 1'bx)
                report_result(0, SOC_ERR_UNKNOWN_EXCEPTION_VECTOR);
            else if (cpu_exception) begin
                $display("[INFO] exception vector=0x%08h", exception_vector);
                if (expected_exception >= 0)
                    report_result(exception_vector === (32'b1 << expected_exception), exception_vector);
                else if (exception_vector !== (32'b1 << EXCEPTION_EBREAK))
                    report_result(0, exception_vector);
                else if (!result_seen || result_failed)
                    report_result(0, {24'b0, result_code});
                else
                    report_result(1, TB_RESULT_OK);
            end
            else if (cycle_counter >= max_cycles)
                report_result(0, SOC_ERR_PROGRAM_TIMEOUT);
        end
    end
endmodule
