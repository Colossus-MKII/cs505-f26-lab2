`include "src/rv32i-common/params.vh"
`include "src/rv32i-memory/config.vh"
`include "src/rv32i-multi-cycle-single-bus/params.vh"

module tb
();
    `include "src/rv32i-common-tb/tb_common.vh"

    // testbench specific
    reg [32*255:0] vcd_name;

    // top-level
	reg         clock_i;
	reg         reset_ni;

    /* CPU output wires */
    wire [31:0] cpu_o_exception_vector;

    wire [31:0] cpu_o_mem_addr;
    wire [31:0] cpu_o_mem_wdata;
    wire  [3:0] cpu_o_mem_wstrb;
    wire        cpu_o_mem_wen;
    wire        cpu_o_mem_req;

    /* MMU output wires */
    reg [31:0] mmu_o_cpu_mem_rdata;
    reg        mmu_o_cpu_mem_valid;
    reg        mmu_o_cpu_mem_err;

    /* CPU */
    rv32i_multi_cycle_single_bus dut
    (
        .clock_i(clock_i),
        .reset_ni(reset_ni),

        .exception_vector_o(cpu_o_exception_vector),

        // mem interface
        .mem_addr_o(cpu_o_mem_addr),
        .mem_rdata_i(mmu_o_cpu_mem_rdata),
        .mem_wdata_o(cpu_o_mem_wdata),
        .mem_wstrb_o(cpu_o_mem_wstrb),
        .mem_wen_o(cpu_o_mem_wen),
        
        .mem_req_o(cpu_o_mem_req),
        .mem_valid_i(mmu_o_cpu_mem_valid),
        .mem_err_i(mmu_o_cpu_mem_err)
    );

    initial clock_i = 0;
    always #5 clock_i = ~clock_i;

    localparam integer MEMORY_WORDS = `RAM_NUM_WORDS;
    localparam integer MEMORY_BYTES = RAM_SIZE_BYTES;

    reg [31:0] memory [0:MEMORY_WORDS-1];
    reg [1023:0] hex_filename;

    integer cycle_counter;
    integer max_cycles;
    integer expected_exception;
    reg [8*32-1:0] expected_exception_descriptor;
    integer mem_wait_cycles;
    integer mem_wait_count;
    integer memory_index;

    reg test_reported;
    reg test_failed;
    reg [31:0] test_failure_code;

    reg pending_request;
    reg [31:0] pending_addr;
    reg [31:0] pending_wdata;
    reg  [3:0] pending_wstrb;
    reg        pending_wen;

    function address_is_ram;
        input [31:0] address;
        begin
            address_is_ram = (address >= RESET_VECTOR) &&
                             ((address - RESET_VECTOR) < MEMORY_BYTES);
        end
    endfunction

    task report_result;
        input        passed;
        input [31:0] code;
        begin
            if (passed)
                $display("TEST_RESULT PASS cycles=%0d", cycle_counter);
            else
                $display("TEST_RESULT FAIL code=0x%08h cycles=%0d", code,
                    cycle_counter);
            $finish;
        end
    endtask

    task record_mmio_result;
        input [31:0] data;
        input  [3:0] strobe;
        begin
            $display("MMIO OUT: 0x%08h", data);

            if (test_reported)
            begin
                test_failed = 1;
                test_failure_code = MC_ERR_DUPLICATE_RESULT;
                $display("[FAIL] duplicate PASS/FAIL MMIO write");
            end
            else
            begin
                test_reported = 1;

                if (strobe !== 4'b1111)
                begin
                    test_failed = 1;
                    test_failure_code = MC_ERR_BAD_RESULT_STROBE;
                    $display("[FAIL] PASS/FAIL write had bad strobe %b", strobe);
                end
                else if (data !== 32'd1)
                begin
                    test_failed = 1;
                    test_failure_code = data;
                    $display("[FAIL] instruction test failure code 0x%08h", data);
                end
            end
        end
    endtask

    task complete_memory_request;
        reg [31:0] canonical_address;
        begin
            canonical_address = pending_addr - RESET_VECTOR;
            mmu_o_cpu_mem_valid = 1;
            mmu_o_cpu_mem_err = 0;
            mmu_o_cpu_mem_rdata = 32'hdeadbeef;

            if (pending_wen)
            begin
                if (pending_addr == 32'h0000_0104)
                    record_mmio_result(pending_wdata, pending_wstrb);
                else if (address_is_ram(pending_addr))
                begin
                    if (pending_wstrb[0]) memory[canonical_address[`RAM_ADDR_WIDTH + 1:2]][7:0] = pending_wdata[7:0];
                    if (pending_wstrb[1]) memory[canonical_address[`RAM_ADDR_WIDTH + 1:2]][15:8] = pending_wdata[15:8];
                    if (pending_wstrb[2]) memory[canonical_address[`RAM_ADDR_WIDTH + 1:2]][23:16] = pending_wdata[23:16];
                    if (pending_wstrb[3]) memory[canonical_address[`RAM_ADDR_WIDTH + 1:2]][31:24] = pending_wdata[31:24];
                end
                else
                    mmu_o_cpu_mem_err = 1;
            end
            else
            begin
                if (pending_addr == 32'h0000_0100)
                begin
                    mmu_o_cpu_mem_rdata = 32'hbaadc0de;
                    $display("MMIO IN");
                end
                else if (address_is_ram(pending_addr))
                    mmu_o_cpu_mem_rdata = memory[canonical_address[`RAM_ADDR_WIDTH + 1:2]];
                else
                    mmu_o_cpu_mem_err = 1;
            end

            pending_request = 0;
        end
    endtask

    initial
    begin
        cycle_counter = 0;
        max_cycles = 5000;
        expected_exception = -1;
        mem_wait_cycles = 0;
        mem_wait_count = 0;
        test_reported = 0;
        test_failed = 0;
        test_failure_code = 0;
        pending_request = 0;
        mmu_o_cpu_mem_rdata = 32'hdeadbeef;
        mmu_o_cpu_mem_valid = 0;
        mmu_o_cpu_mem_err = 0;

        if ($value$plusargs("max_cycles=%d", max_cycles)) begin end
        if (max_cycles <= 0)
        begin
            $display("[FAIL] +max_cycles must be positive");
            report_result(1'b0, MC_ERR_INVALID_TEST_OPTIONS);
        end

        for (memory_index = 0; memory_index < MEMORY_WORDS; memory_index = memory_index + 1)
            memory[memory_index] = 32'hdeadbeef;

        if (!$value$plusargs("hex=%s", hex_filename))
        begin
            $display("[FAIL] Missing +hex=<program.hex>");
            report_result(1'b0, MC_ERR_MISSING_HEX_ARGUMENT);
        end
        else
            $readmemh(hex_filename, memory);

        if ($value$plusargs("expect_exception=%s", expected_exception_descriptor))
        begin
            expected_exception = exception_descriptor_to_bit(expected_exception_descriptor);
            if (expected_exception < 0)
            begin
                $display("[FAIL] unknown exception descriptor: %0s",
                    expected_exception_descriptor);
                report_result(1'b0, MC_ERR_INVALID_TEST_OPTIONS);
            end
            $display("[INFO] expecting %0s (bit %0d)",
                expected_exception_descriptor, expected_exception);
        end

        if ($value$plusargs("mem_wait=%d", mem_wait_cycles))
        begin
            if (mem_wait_cycles < 0)
                mem_wait_cycles = 0;
        end
        $display("[INFO] memory wait cycles: %0d", mem_wait_cycles);
    end

    /* Stateful single-bus memory model. The CPU must hold the request and all
     * relevant request fields until valid is asserted. +mem_wait=N inserts N
     * additional wait cycles before each response.
     */
    always @(negedge clock_i)
    begin
        mmu_o_cpu_mem_valid = 0;
        mmu_o_cpu_mem_err = 0;

        if (!reset_ni)
        begin
            pending_request = 0;
            mem_wait_count = 0;
        end
        else if (pending_request)
        begin
            if (!cpu_o_mem_req ||
                (cpu_o_mem_addr !== pending_addr) ||
                (cpu_o_mem_wen !== pending_wen) ||
                (pending_wen && ((cpu_o_mem_wdata !== pending_wdata) ||
                                 (cpu_o_mem_wstrb !== pending_wstrb))))
            begin
                $display("[FAIL] memory request changed before valid");
                report_result(1'b0, MC_ERR_MEMORY_REQUEST_CHANGED);
            end

            if (mem_wait_count <= 1)
                complete_memory_request;
            else
                mem_wait_count = mem_wait_count - 1;
        end
        else if (cpu_o_mem_req)
        begin
            pending_addr = cpu_o_mem_addr;
            pending_wdata = cpu_o_mem_wdata;
            pending_wstrb = cpu_o_mem_wstrb;
            pending_wen = cpu_o_mem_wen;

            if (mem_wait_cycles == 0)
                complete_memory_request;
            else
            begin
                pending_request = 1;
                mem_wait_count = mem_wait_cycles;
            end
        end
    end

    initial
    begin
        reset_ni = 0;
        repeat (5) @(negedge clock_i);
        reset_ni = 1;
        $display("[INFO] reset complete");

        // Record execution only, starting before the first active CPU edge.
        if ($test$plusargs("vcd"))
        begin
            if ($value$plusargs("vcd=%s", vcd_name))
            begin
                $display("Dumping VCD: %0s", vcd_name);
                $dumpfile(vcd_name);
                $dumpvars(0);
            end
        end
    end

    always @(posedge clock_i)
    begin
        // Match the SoC bench: count this active edge before checking results.
        if (reset_ni)
            cycle_counter = cycle_counter + 1;

        if ((cycle_counter > 0) && ((cycle_counter % 500) == 0))
            $display("[heartbeat] cycle count: %0d", cycle_counter);

        if (reset_ni && (^cpu_o_exception_vector === 1'bx))
        begin
            $display("[FAIL] exception vector contains an unknown value");
            report_result(1'b0, MC_ERR_UNKNOWN_EXCEPTION_VECTOR);
        end
        else if (cpu_o_exception_vector != 32'h0)
        begin
            $display("[INFO] Simulation halted on cycle %0d due to exception",
                cycle_counter);

            if (cpu_o_exception_vector[EXCEPTION_ECALL])
                $display("    > EXCEPTION_ECALL");
            if (cpu_o_exception_vector[EXCEPTION_EBREAK])
                $display("    > EXCEPTION_EBREAK");
            if (cpu_o_exception_vector[EXCEPTION_ILLEGAL_INSTRUCTION])
                $display("    > EXCEPTION_ILLEGAL_INSTRUCTION");
            if (cpu_o_exception_vector[EXCEPTION_MEM_MISALIGNMENT])
                $display("    > EXCEPTION_MEM_MISALIGNMENT");
            if (cpu_o_exception_vector[EXCEPTION_MEM_BUS_ERROR])
                $display("    > EXCEPTION_MEM_BUS_ERROR");
            if (cpu_o_exception_vector[EXCEPTION_BUS_FAULT])
                $display("    > EXCEPTION_BUS_FAULT");

            if (expected_exception >= 0)
            begin
                if (cpu_o_exception_vector === (32'b1 << expected_exception))
                    report_result(1'b1, TB_RESULT_OK);
                else if (test_failed)
                    report_result(1'b0, test_failure_code);
                else
                    report_result(1'b0, MC_ERR_EXCEPTION_MISMATCH);
            end
            else if (cpu_o_exception_vector === (32'b1 << EXCEPTION_EBREAK))
            begin
                if (!test_reported)
                begin
                    $display("[FAIL] EBREAK occurred before a test result was reported");
                    report_result(1'b0, MC_ERR_MISSING_RESULT);
                end
                else if (test_failed)
                    report_result(1'b0, test_failure_code);
                else
                    report_result(1'b1, TB_RESULT_OK);
            end
            else
            begin
                $display("[FAIL] unexpected exception vector 0x%08h",
                    cpu_o_exception_vector);
                report_result(1'b0, MC_ERR_UNEXPECTED_EXCEPTION);
            end
        end
        else if (reset_ni && cycle_counter >= max_cycles)
        begin
            $display("[FAIL] Simulation timed out");
            report_result(1'b0, MC_ERR_PROGRAM_TIMEOUT);
        end
    end
endmodule
