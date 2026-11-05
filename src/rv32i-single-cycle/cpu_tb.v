`include "src/rv32i-common/params.vh"
`include "src/rv32i-memory/config.vh"
`include "src/rv32i-single-cycle/params.vh"

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

    wire [31:0] cpu_o_imem_addr;
    wire        cpu_o_imem_req;

    wire [31:0] cpu_o_dmem_addr;
    wire [31:0] cpu_o_dmem_wdata;
    wire  [3:0] cpu_o_dmem_wstrb;
    wire        cpu_o_dmem_wen;
    wire        cpu_o_dmem_req;

    /* MMU output wires */
    reg [31:0] mmu_o_cpu_imem_data;
    reg        mmu_o_cpu_imem_valid;
    reg        mmu_o_cpu_imem_err;

    reg [31:0] mmu_o_cpu_dmem_rdata;
    reg        mmu_o_cpu_dmem_valid;
    reg        mmu_o_cpu_dmem_err;

    /* CPU */
    rv32i_single_cycle dut
    (
        .clock_i(clock_i),
        .reset_ni(reset_ni),

        .exception_vector_o(cpu_o_exception_vector),

        // imem interface (read only)
        .imem_addr_o(cpu_o_imem_addr),
        .imem_data_i(mmu_o_cpu_imem_data),
        .imem_req_o(cpu_o_imem_req),
        .imem_valid_i(mmu_o_cpu_imem_valid),
        .imem_err_i(mmu_o_cpu_imem_err),

        // dmem interface
        .dmem_addr_o(cpu_o_dmem_addr),
        .dmem_rdata_i(mmu_o_cpu_dmem_rdata),
        .dmem_wdata_o(cpu_o_dmem_wdata),
        .dmem_wstrb_o(cpu_o_dmem_wstrb),
        .dmem_wen_o(cpu_o_dmem_wen),
        
        .dmem_req_o(cpu_o_dmem_req),
        .dmem_valid_i(mmu_o_cpu_dmem_valid),
        .dmem_err_i(mmu_o_cpu_dmem_err)
    );

    initial clock_i = 0;
    always #5 clock_i = ~clock_i;

    integer cycle_counter;
    integer max_cycles;
    reg test_reported;
    reg test_failed;
    reg [31:0] test_failure_code;
    integer expected_exception;
    reg [8*32-1:0] expected_exception_descriptor;
    reg [1023:0] hex_filename;
    // Word-addressed RAM sized by rv32i-memory/config.vh.
    localparam integer MEMORY_WORDS = `RAM_NUM_WORDS;
    localparam integer MEMORY_BYTES = RAM_SIZE_BYTES;
    reg [31:0] memory [0:MEMORY_WORDS-1];

    /* Verilog-2001-compatible reporting. Automation can look for the exact
     * "TEST_RESULT PASS" or "TEST_RESULT FAIL" marker in simulator output.
     */
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

    initial begin
        // read in hex file
        cycle_counter = 0;
        max_cycles = 1000;
        test_reported = 0;
        test_failed = 0;
        test_failure_code = 0;
        expected_exception = -1;

        if ($value$plusargs("max_cycles=%d", max_cycles)) begin end
        if (max_cycles <= 0)
        begin
            $display("[FAIL] +max_cycles must be positive");
            report_result(1'b0, SC_ERR_INVALID_TEST_OPTIONS);
        end

        if (!$value$plusargs("hex=%s", hex_filename))
        begin
            $display("[FAIL] Missing +hex=<program.hex>");
            report_result(1'b0, SC_ERR_MISSING_HEX_ARGUMENT);
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
                report_result(1'b0, SC_ERR_INVALID_TEST_OPTIONS);
            end
            $display("[INFO] expecting %0s (bit %0d)",
                expected_exception_descriptor, expected_exception);
        end
    end

    always @(negedge clock_i) begin
        if (mmu_o_cpu_dmem_valid &&
            cpu_o_dmem_wen &&
            cpu_o_dmem_addr == 32'h0000_0104) begin

            if (test_reported)
            begin
                test_failed = 1;
                test_failure_code = SC_ERR_DUPLICATE_RESULT;
                $display("[FAIL] duplicate PASS/FAIL MMIO write");
            end
            else
            begin
                test_reported = 1;

                if (cpu_o_dmem_wstrb !== 4'b1111)
                begin
                    test_failed = 1;
                    test_failure_code = SC_ERR_BAD_RESULT_STROBE;
                    $display("[FAIL] PASS/FAIL write had bad strobe %b",
                        cpu_o_dmem_wstrb);
                end
                else if (cpu_o_dmem_wdata !== 32'd1)
                begin
                    test_failed = 1;
                    test_failure_code = cpu_o_dmem_wdata;
                    $display("[FAIL] instruction test failure code 0x%08h",
                        cpu_o_dmem_wdata);
                end
            end
        end
    end

    // simulate the memory - combinational reads, sequential writes
    assign mmu_o_cpu_imem_valid = reset_ni & cpu_o_imem_req;
    wire [31:0] imem_addr_canonicalized = cpu_o_imem_addr - RESET_VECTOR;
    assign mmu_o_cpu_imem_data = mmu_o_cpu_imem_valid ? memory[imem_addr_canonicalized[`RAM_ADDR_WIDTH + 1:2]] : 32'hdeadbeef;
    assign mmu_o_cpu_imem_err = mmu_o_cpu_imem_valid && (imem_addr_canonicalized >= MEMORY_BYTES);

    wire [31:0] dmem_addr_canonicalized = cpu_o_dmem_addr - RESET_VECTOR;
    wire dmem_addr_is_ram = (cpu_o_dmem_addr >= RESET_VECTOR) &&
                            (dmem_addr_canonicalized < MEMORY_BYTES);
    wire dmem_addr_is_mmio = ((!cpu_o_dmem_wen) && (cpu_o_dmem_addr == 32'h0000_0100)) ||
                             (cpu_o_dmem_wen && (cpu_o_dmem_addr == 32'h0000_0104));
    assign mmu_o_cpu_dmem_valid = reset_ni & cpu_o_dmem_req;
    assign mmu_o_cpu_dmem_rdata = mmu_o_cpu_dmem_valid && !cpu_o_dmem_wen ?
                                  (cpu_o_dmem_addr == 32'h0000_0100 ? 32'hbaadc0de :
                                  (dmem_addr_is_ram ? memory[dmem_addr_canonicalized[`RAM_ADDR_WIDTH + 1:2]] : 32'hdeadbeef)) :
                                  32'hdeadbeef;
    assign mmu_o_cpu_dmem_err = mmu_o_cpu_dmem_valid &&
                                !(dmem_addr_is_ram || dmem_addr_is_mmio);

    always @(negedge clock_i)
    begin        
        if(mmu_o_cpu_dmem_valid)
        begin
            if(cpu_o_dmem_wen)
            begin 
                if(cpu_o_dmem_addr == 32'h0000_0104)
                    $display("MMIO OUT: 0x%h", cpu_o_dmem_wdata);
                else if(dmem_addr_is_ram)
                begin
                    if(cpu_o_dmem_wstrb[0]) memory[dmem_addr_canonicalized[`RAM_ADDR_WIDTH + 1:2]][7:0] <= cpu_o_dmem_wdata[7:0];
                    if(cpu_o_dmem_wstrb[1]) memory[dmem_addr_canonicalized[`RAM_ADDR_WIDTH + 1:2]][15:8] <= cpu_o_dmem_wdata[15:8];
                    if(cpu_o_dmem_wstrb[2]) memory[dmem_addr_canonicalized[`RAM_ADDR_WIDTH + 1:2]][23:16] <= cpu_o_dmem_wdata[23:16];
                    if(cpu_o_dmem_wstrb[3]) memory[dmem_addr_canonicalized[`RAM_ADDR_WIDTH + 1:2]][31:24] <= cpu_o_dmem_wdata[31:24];
                end
            end else begin
                if(cpu_o_dmem_addr == 32'h0000_0100)
                    $display("MMIO IN");
            end
        end
    end
    
    initial 
    begin
        // reset for five cycles
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
        if(reset_ni)
		    cycle_counter = cycle_counter + 1;
        
        if(cycle_counter > 0 && (cycle_counter % 100) == 0)
		    $display("[heartbeat] cycle count: %0d", cycle_counter);

        // if ($test$plusargs("trace")) 
        // begin
        //     $display("[INFO] cycle: %0d pc: %h inst: %h alu_out: %h", 
        //         cycle_counter, dut.cpu.pc, dut.cpu.imem_data_i, dut.cpu.alu_o_out);
		// end

        // check whether the testbench is finished
        if(cpu_o_exception_vector != 32'h0)
        begin
            $display("[INFO] Simulation halted on cycle %0d due to exception", cycle_counter);

            if(cpu_o_exception_vector[EXCEPTION_ECALL])
            begin
                $display("    > EXCEPTION_ECALL");
            end
            
            if(cpu_o_exception_vector[EXCEPTION_EBREAK])
            begin
                $display("    > EXCEPTION_EBREAK");
            end
            
            if(cpu_o_exception_vector[EXCEPTION_ILLEGAL_INSTRUCTION])
            begin
                $display("    > EXCEPTION_ILLEGAL_INSTRUCTION");
            end
            
            if(cpu_o_exception_vector[EXCEPTION_IMEM_MISALIGNMENT])
            begin
                $display("    > EXCEPTION_IMEM_MISALIGNMENT");
            end
            
            if(cpu_o_exception_vector[EXCEPTION_IMEM_BUS_ERROR])
            begin
                $display("    > EXCEPTION_IMEM_BUS_ERROR");
            end
            
            if(cpu_o_exception_vector[EXCEPTION_DMEM_BUS_ERROR])
            begin
                $display("    > EXCEPTION_DMEM_BUS_ERROR");
            end

            if (expected_exception >= 0)
            begin
                if (cpu_o_exception_vector === (32'b1 << expected_exception))
                    report_result(1'b1, TB_RESULT_OK);
                else if (test_failed)
                    report_result(1'b0, test_failure_code);
                else
                    report_result(1'b0, SC_ERR_EXCEPTION_MISMATCH);
            end
            else if (cpu_o_exception_vector === (32'b1 << EXCEPTION_EBREAK))
            begin
                if (!test_reported)
                begin
                    $display("[FAIL] EBREAK occurred before a test result was reported");
                    report_result(1'b0, SC_ERR_MISSING_RESULT);
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
                report_result(1'b0, SC_ERR_UNEXPECTED_EXCEPTION);
            end
        end
        else if (reset_ni && cycle_counter >= max_cycles)
        begin
            $display("[FAIL] Simulation timed out");
            report_result(1'b0, SC_ERR_PROGRAM_TIMEOUT);
        end    
	end
endmodule
