// Shared testbench definitions; include once inside each testbench module.
// Keep result code values stable for scripts that consume simulation logs.
localparam [31:0] TB_RESULT_OK = 32'b0;

// Single-cycle CPU harness errors (0xf0xxxxxx).
localparam [31:0] SC_ERR_MISSING_HEX_ARGUMENT  = 32'hf0000001;
localparam [31:0] SC_ERR_DUPLICATE_RESULT      = 32'hf0000002;
localparam [31:0] SC_ERR_BAD_RESULT_STROBE     = 32'hf0000003;
localparam [31:0] SC_ERR_EXCEPTION_MISMATCH    = 32'hf0000004;
localparam [31:0] SC_ERR_MISSING_RESULT        = 32'hf0000005;
localparam [31:0] SC_ERR_UNEXPECTED_EXCEPTION  = 32'hf0000006;
localparam [31:0] SC_ERR_PROGRAM_TIMEOUT       = 32'hf0000007;
localparam [31:0] SC_ERR_INVALID_TEST_OPTIONS  = 32'hf0000008;

// Multi-cycle CPU harness errors (0xf1xxxxxx).
localparam [31:0] MC_ERR_DUPLICATE_RESULT      = 32'hf1000001;
localparam [31:0] MC_ERR_BAD_RESULT_STROBE     = 32'hf1000002;
localparam [31:0] MC_ERR_MISSING_HEX_ARGUMENT  = 32'hf1000003;
localparam [31:0] MC_ERR_MEMORY_REQUEST_CHANGED = 32'hf1000004;
localparam [31:0] MC_ERR_UNKNOWN_EXCEPTION_VECTOR = 32'hf1000005;
localparam [31:0] MC_ERR_EXCEPTION_MISMATCH    = 32'hf1000006;
localparam [31:0] MC_ERR_MISSING_RESULT        = 32'hf1000007;
localparam [31:0] MC_ERR_UNEXPECTED_EXCEPTION  = 32'hf1000008;
localparam [31:0] MC_ERR_PROGRAM_TIMEOUT       = 32'hf1000009;
localparam [31:0] MC_ERR_INVALID_TEST_OPTIONS  = 32'hf100000a;

// Shared SoC workload and RAM harness errors (0xf2xxxxxx).
localparam [31:0] SOC_ERR_HOST_RESPONSE           = 32'hf2000001;
localparam [31:0] SOC_ERR_RAM_DATA_MISMATCH       = 32'hf2000002;
localparam [31:0] SOC_ERR_INVALID_TEST_OPTIONS    = 32'hf2000003;
localparam [31:0] SOC_ERR_MISSING_HEX_ARGUMENT    = 32'hf2000004;
localparam [31:0] SOC_ERR_HEX_FILE_OPEN           = 32'hf2000005;
localparam [31:0] SOC_ERR_UNKNOWN_EXCEPTION_VECTOR = 32'hf2000006;
localparam [31:0] SOC_ERR_PROGRAM_TIMEOUT         = 32'hf2000007;
localparam [31:0] SOC_ERR_WATCHDOG_TIMEOUT        = 32'hf2000008;
localparam [31:0] SOC_ERR_CPU_OUTPUT_DURING_RESET = 32'hf2000009;
localparam [31:0] SOC_ERR_HOST_RESPONSE_DURING_EXECUTION = 32'hf200000a;
localparam [31:0] SOC_ERR_HOST_ADDRESS_TOO_WIDE   = 32'hf200000b;

// Three-stage CPU workload harness errors (0xf3xxxxxx).
localparam [31:0] TS_ERR_MISSING_HEX_ARGUMENT = 32'hf3000001;
localparam [31:0] TS_ERR_HEX_FILE_OPEN = 32'hf3000002;
localparam [31:0] TS_ERR_INVALID_TEST_OPTIONS = 32'hf3000003;
localparam [31:0] TS_ERR_DUPLICATE_RESULT = 32'hf3000004;
localparam [31:0] TS_ERR_BAD_RESULT_STROBE = 32'hf3000005;
localparam [31:0] TS_ERR_UNKNOWN_EXCEPTION_VECTOR = 32'hf3000006;
localparam [31:0] TS_ERR_EXCEPTION_MISMATCH = 32'hf3000007;
localparam [31:0] TS_ERR_UNEXPECTED_EXCEPTION = 32'hf3000008;
localparam [31:0] TS_ERR_MISSING_RESULT = 32'hf3000009;
localparam [31:0] TS_ERR_PROGRAM_TIMEOUT = 32'hf300000a;

// Descriptors for +expect_exception mirror the CPU exception names.
function integer exception_descriptor_to_bit;
    input [8*32-1:0] descriptor;
    begin
        if (descriptor == "EXCEPTION_ECALL")
            exception_descriptor_to_bit = 0;
        else if (descriptor == "EXCEPTION_EBREAK")
            exception_descriptor_to_bit = 1;
        else if (descriptor == "EXCEPTION_ILLEGAL_INSTRUCTION")
            exception_descriptor_to_bit = 2;
        else if (descriptor == "EXCEPTION_IMEM_MISALIGNMENT")
            exception_descriptor_to_bit = 3;
        else if (descriptor == "EXCEPTION_IMEM_BUS_ERROR")
            exception_descriptor_to_bit = 4;
        else if (descriptor == "EXCEPTION_DMEM_BUS_ERROR")
            exception_descriptor_to_bit = 5;
        else
            exception_descriptor_to_bit = -2;
    end
endfunction
