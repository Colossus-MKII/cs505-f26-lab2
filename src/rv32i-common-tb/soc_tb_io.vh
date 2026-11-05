// Shared SoC harness; include inside either testbench module.
    `include "src/rv32i-common-tb/tb_common.vh"
    localparam integer HOST_ADDRESS_SPACE_BYTES = 65536;
    localparam integer HOST_TIMEOUT_CYCLES = 32;

    reg clock_i = 0;
    always #5 clock_i = ~clock_i;
    reg reset_ni = 0;
    reg [15:0] io_addr = 0;
    reg [7:0] io_wdata = 0;
    reg io_wen = 0, io_req = 0;
    wire cpu_exception;
    wire [31:0] exception_vector;
    wire [7:0] io_data_o;
    wire io_valid, io_err, io_wen_o;
    // Supply RAM write data during reset and ASCII '!' during execution.
    wire [7:0] io_data_i = reset_ni ? 8'h21 : io_wdata;

    soc dut (
        .clock_i(clock_i), .reset_ni(reset_ni),
        .cpu_exception_o(cpu_exception),
        .cpu_exception_vector_o(exception_vector),
        .io_addr_i(io_addr), .io_data_i(io_data_i), .io_data_o(io_data_o),
        .io_wen_i(io_wen), .io_wen_o(io_wen_o),
        .io_req_i(io_req), .io_valid_o(io_valid), .io_err_o(io_err)
    );

    reg finished = 0;
    integer max_cycles = 0;
    integer cycle_counter = -1; // No workload cycles until CPU reset is released.
    reg [2047:0] vcd_filename;

    task start_waveform;
        begin
            if ($value$plusargs("vcd=%s", vcd_filename)) begin
                $dumpfile(vcd_filename);
                $dumpvars(0);
            end
        end
    endtask

    task report_result(input passed, input [31:0] code);
        begin
            if (!finished) begin
                finished = 1;
                if (passed) $write("TEST_RESULT PASS");
                else $write("TEST_RESULT FAIL code=0x%08h", code);
                if (cycle_counter >= 0) $write(" cycles=%0d", cycle_counter);
                $display("");
                $finish;
            end
        end
    endtask

    initial begin : watchdog
        if (RAM_SIZE_BYTES <= 0 || RAM_SIZE_BYTES > HOST_ADDRESS_SPACE_BYTES)
            report_result(0, SOC_ERR_INVALID_TEST_OPTIONS);
        #1; // Let the workload bench read +max_cycles first.
        repeat (4 * RAM_SIZE_BYTES + max_cycles + 10000) @(posedge clock_i);
        report_result(0, SOC_ERR_WATCHDOG_TIMEOUT);
    end

    task write_byte(input [31:0] address, input [7:0] data);
        reg [7:0] unused_read_data;
        begin
            host_access(1, address, data, 0, unused_read_data);
        end
    endtask

    task host_access(input write_enable, input [31:0] address,
                     input [7:0] data, input expect_error, output [7:0] read_data);
        integer wait_cycles;
        begin
            if (address >= HOST_ADDRESS_SPACE_BYTES)
                report_result(0, SOC_ERR_HOST_ADDRESS_TOO_WIDE);

            // Drive on a falling edge; hold through the accepting rising edge.
            @(negedge clock_i);
            io_addr = address[15:0];
            io_wdata = data;
            io_wen = write_enable;
            io_req = 1;
            wait_cycles = 0;
            #1;
            while (!io_valid && wait_cycles < HOST_TIMEOUT_CYCLES) begin
                @(negedge clock_i);
                wait_cycles = wait_cycles + 1;
                #1;
            end
            if (io_valid !== 1'b1 || io_err !== expect_error) begin
                $display("[FAIL] host addr=%h valid=%b err=%b expected_err=%b",
                    address, io_valid, io_err, expect_error);
                report_result(0, SOC_ERR_HOST_RESPONSE);
            end
            if (io_wen_o !== 1'b0)
                report_result(0, SOC_ERR_CPU_OUTPUT_DURING_RESET);
            read_data = io_data_o;
            @(posedge clock_i);
            #1;
            @(negedge clock_i);
            io_req = 0;
            io_wen = 0;
        end
    endtask
