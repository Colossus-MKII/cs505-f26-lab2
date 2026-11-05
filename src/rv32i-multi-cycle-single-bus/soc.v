`include "src/rv32i-memory/config.vh"


// Routes CPU requests and host byte transactions to RAM or peripheral MMIO.
module mmu_1rw
#(
    parameter [31:0] P_RAM_START_BYTE_ADDR  = 32'h8000_0000,
    parameter [31:0] P_RAM_SIZE_BYTES       = RAM_SIZE_BYTES,
    parameter [31:0] P_MMIO_START_BYTE_ADDR = 32'h0000_0100,
    parameter [31:0] P_MMIO_SIZE_BYTES      = 32'd1
)
(
    input           reset_ni,

    // Host addresses are 16-bit byte offsets into RAM. During execution,
    // mapped CPU writes produce a byte and write strobe without a handshake.
    input    [15:0] io_addr_i,
    input     [7:0] io_data_i,
    output    [7:0] io_data_o,
    input           io_wen_i,
    output          io_wen_o,
    input           io_req_i,
    output          io_valid_o,
    output          io_err_o,

    // read-write port interface from the CPU
    input    [31:0] cpu_mem_addr_i,
    output   [31:0] cpu_mem_rdata_o,
    input    [31:0] cpu_mem_wdata_i,
    input     [3:0] cpu_mem_wstrb_i,
    input           cpu_mem_wen_i,
    
    input           cpu_mem_req_i,
    output          cpu_mem_valid_o,
    output          cpu_mem_err_o,

    // read-write port interface to the RAM
    output   [`RAM_ADDR_WIDTH - 1:0] ram_rw0_word_addr_o,
    input    [31:0]                  ram_rw0_rdata_i,
    output   [31:0]                  ram_rw0_wdata_o,
    output   [3:0]                   ram_rw0_wstrb_o,
    output                           ram_rw0_wen_o,
    output                           ram_rw0_req_o,
    input                            ram_rw0_valid_i
);
    wire is_mem_valid_ram_request = (cpu_mem_addr_i >= P_RAM_START_BYTE_ADDR) && (cpu_mem_addr_i < P_RAM_START_BYTE_ADDR + P_RAM_SIZE_BYTES);
    wire is_mem_valid_mmio_request = (cpu_mem_addr_i >= P_MMIO_START_BYTE_ADDR) && (cpu_mem_addr_i < P_MMIO_START_BYTE_ADDR + P_MMIO_SIZE_BYTES);

    wire [31:0] cpu_mem_canonicalized_ram_addr = cpu_mem_addr_i - P_RAM_START_BYTE_ADDR;
    wire [31:0] io_canonicalized_ram_addr = {16'b0, io_addr_i};
    wire is_io_ram_request = io_canonicalized_ram_addr < P_RAM_SIZE_BYTES;
    wire host_ram_req = !reset_ni && io_req_i && is_io_ram_request;
    wire cpu_ram_req = reset_ni && cpu_mem_req_i && is_mem_valid_ram_request;
    wire cpu_mmio_req = reset_ni && cpu_mem_req_i && is_mem_valid_mmio_request;
    wire cpu_bad_addr = !is_mem_valid_ram_request && !is_mem_valid_mmio_request;

    // Byte addresses select an internal RAM lane; no host byte strobe is needed.
    wire [7:0] host_rdata = host_ram_req ?
        ((io_canonicalized_ram_addr[1:0] == 2'd0) ? ram_rw0_rdata_i[7:0] :
         (io_canonicalized_ram_addr[1:0] == 2'd1) ? ram_rw0_rdata_i[15:8] :
         (io_canonicalized_ram_addr[1:0] == 2'd2) ? ram_rw0_rdata_i[23:16] :
                                                 ram_rw0_rdata_i[31:24]) : 8'b0;
    assign io_err_o = !reset_ni && io_req_i && !is_io_ram_request;
    assign io_valid_o = !reset_ni && io_req_i && (io_err_o || ram_rw0_valid_i);

    /* assign CPU outputs */
    assign cpu_mem_rdata_o = is_mem_valid_ram_request ? ram_rw0_rdata_i : 
                                (is_mem_valid_mmio_request ? {24'b0, io_data_i} : 32'hdeadbeef);
    assign cpu_mem_valid_o = reset_ni && cpu_mem_req_i &&
        (cpu_bad_addr || (is_mem_valid_ram_request ? ram_rw0_valid_i : 1'b1));
    assign cpu_mem_err_o = reset_ni && cpu_mem_req_i &&
        cpu_bad_addr;

    /* assign RAM outputs */
    assign ram_rw0_word_addr_o = reset_ni ?
        cpu_mem_canonicalized_ram_addr[`RAM_ADDR_WIDTH + 1:2] :
        io_canonicalized_ram_addr[`RAM_ADDR_WIDTH + 1:2];
    assign ram_rw0_wdata_o = reset_ni ? cpu_mem_wdata_i : {4{io_data_i}};
    assign ram_rw0_wstrb_o = reset_ni ? cpu_mem_wstrb_i :
        (4'b0001 << io_canonicalized_ram_addr[1:0]);
    assign ram_rw0_wen_o = reset_ni ? (cpu_ram_req && cpu_mem_wen_i) :
        (host_ram_req && io_wen_i);
    assign ram_rw0_req_o = cpu_ram_req || host_ram_req;

    // Data pins are shared by host readback and the memory-mapped byte output.
    assign io_data_o = reset_ni ?
        (cpu_mmio_req ? cpu_mem_wdata_i[7:0] : 8'b0) : host_rdata;
    assign io_wen_o = cpu_mmio_req && cpu_mem_wen_i;
endmodule

module soc
(
    input        clock_i,
    input        reset_ni,

    output       cpu_exception_o,
    output [31:0] cpu_exception_vector_o,

    // Host input uses RAM byte offsets; CPU output is data plus a write strobe.
    input [15:0] io_addr_i,
    input  [7:0] io_data_i,
    output [7:0] io_data_o,
    input        io_wen_i,
    output       io_wen_o,
    input        io_req_i,
    output       io_valid_o,
    output       io_err_o
    
);    
    /* CPU output wires */
    wire [31:0] cpu_o_exception_vector;

    wire [31:0] cpu_o_mem_addr;
    wire [31:0] cpu_o_mem_wdata;
    wire  [3:0] cpu_o_mem_wstrb;
    wire        cpu_o_mem_wen;
    wire        cpu_o_mem_req;

    /* MMU output wires */
    wire [31:0] mmu_o_cpu_mem_rdata;
    wire        mmu_o_cpu_mem_valid;
    wire        mmu_o_cpu_mem_err;

    wire [`RAM_ADDR_WIDTH - 1:0] mmu_o_ram_rw0_word_addr;
    wire [31:0]                  mmu_o_ram_rw0_wdata;
    wire [3:0]                   mmu_o_ram_rw0_wstrb;
    wire                         mmu_o_ram_rw0_wen;
    wire                         mmu_o_ram_rw0_req;

    /* RAM outputs */
    wire [31:0] ram_o_rw0_rdata;
    wire        ram_o_rw0_valid;

    /*
     * MODULES
     */
    /* CPU */
    rv32i_multi_cycle_single_bus cpu
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

    /* MMU */
    mmu_1rw
    #(
        .P_RAM_START_BYTE_ADDR(RAM_START_BYTE_ADDR),
        .P_RAM_SIZE_BYTES(RAM_SIZE_BYTES),
        .P_MMIO_START_BYTE_ADDR(MMIO_START_BYTE_ADDR),
        .P_MMIO_SIZE_BYTES(MMIO_SIZE_BYTES)
    ) 
    mmu
    (
        .reset_ni(reset_ni),
        .io_addr_i(io_addr_i),
        .io_data_i(io_data_i),
        .io_data_o(io_data_o),
        .io_wen_i(io_wen_i),
        .io_wen_o(io_wen_o),
        .io_req_i(io_req_i),
        .io_valid_o(io_valid_o),
        .io_err_o(io_err_o),

        // read-write port interface from the CPU
        .cpu_mem_addr_i(cpu_o_mem_addr),
        .cpu_mem_rdata_o(mmu_o_cpu_mem_rdata),
        .cpu_mem_wdata_i(cpu_o_mem_wdata),
        .cpu_mem_wstrb_i(cpu_o_mem_wstrb),
        .cpu_mem_wen_i(cpu_o_mem_wen),
        
        .cpu_mem_req_i(cpu_o_mem_req),
        .cpu_mem_valid_o(mmu_o_cpu_mem_valid),
        .cpu_mem_err_o(mmu_o_cpu_mem_err),

        // read-write port interface to the RAM
        .ram_rw0_word_addr_o(mmu_o_ram_rw0_word_addr),
        .ram_rw0_rdata_i(ram_o_rw0_rdata),
        .ram_rw0_wdata_o(mmu_o_ram_rw0_wdata),
        .ram_rw0_wstrb_o(mmu_o_ram_rw0_wstrb),
        .ram_rw0_wen_o(mmu_o_ram_rw0_wen),
        .ram_rw0_req_o(mmu_o_ram_rw0_req),
        .ram_rw0_valid_i(ram_o_rw0_valid)
    );

    mem_1rw_asyncr_syncw_4x8bit
    #(
        .MEM_SIZE_BYTES(RAM_SIZE_BYTES)
    )
    ram
    (
        .clock_i(clock_i),

	    .rw0_word_addr_i(mmu_o_ram_rw0_word_addr),
        .rw0_rdata_o(ram_o_rw0_rdata),
	    .rw0_wdata_i(mmu_o_ram_rw0_wdata),
	    .rw0_wstrb_i(mmu_o_ram_rw0_wstrb),
	    .rw0_wen_i(mmu_o_ram_rw0_wen),
	    .rw0_req_i(mmu_o_ram_rw0_req),
	    .rw0_valid_o(ram_o_rw0_valid)
    );

    /* module outputs */
    assign cpu_exception_o = cpu_o_exception_vector != 32'h0;
    assign cpu_exception_vector_o = cpu_o_exception_vector;

endmodule
