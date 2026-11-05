`include "src/rv32i-memory/config.vh"

module rv32i_three_stage_mmu
#(
    parameter [31:0] P_RAM_START_BYTE_ADDR = 32'h8000_0000,
    parameter [31:0] P_RAM_SIZE_BYTES = RAM_SIZE_BYTES,
    parameter [31:0] P_MMIO_START_BYTE_ADDR = 32'h0000_0100,
    parameter [31:0] P_MMIO_SIZE_BYTES = 32'd8
)
(
    input            reset_ni,
    input      [15:0] io_addr_i,
    input       [7:0] io_data_i,
    output      [7:0] io_data_o,
    input             io_wen_i,
    output            io_wen_o,
    input             io_req_i,
    output            io_valid_o,
    output            io_err_o,

    input      [31:0] cpu_imem_addr_i,
    output     [31:0] cpu_imem_data_o,
    input             cpu_imem_req_i,
    output            cpu_imem_valid_o,
    output            cpu_imem_err_o,

    input      [31:0] cpu_dmem_addr_i,
    output     [31:0] cpu_dmem_rdata_o,
    input      [31:0] cpu_dmem_wdata_i,
    input       [3:0] cpu_dmem_wstrb_i,
    input             cpu_dmem_wen_i,
    input             cpu_dmem_req_i,
    output            cpu_dmem_valid_o,
    output            cpu_dmem_err_o,

    output [`RAM_ADDR_WIDTH-1:0] ram_r0_word_addr_o,
    input      [31:0] ram_r0_data_i,
    output            ram_r0_req_o,
    input             ram_r0_valid_i,

    output [`RAM_ADDR_WIDTH-1:0] ram_rw0_word_addr_o,
    input      [31:0] ram_rw0_rdata_i,
    output     [31:0] ram_rw0_wdata_o,
    output      [3:0] ram_rw0_wstrb_o,
    output            ram_rw0_wen_o,
    output            ram_rw0_req_o,
    input             ram_rw0_valid_i
);
    wire is_imem_valid_ram_request =
        (cpu_imem_addr_i >= P_RAM_START_BYTE_ADDR) &&
        (cpu_imem_addr_i < P_RAM_START_BYTE_ADDR + P_RAM_SIZE_BYTES);
    wire is_dmem_valid_ram_request =
        (cpu_dmem_addr_i >= P_RAM_START_BYTE_ADDR) &&
        (cpu_dmem_addr_i < P_RAM_START_BYTE_ADDR + P_RAM_SIZE_BYTES);
    wire is_dmem_valid_mmio_request =
        (cpu_dmem_addr_i >= P_MMIO_START_BYTE_ADDR) &&
        (cpu_dmem_addr_i < P_MMIO_START_BYTE_ADDR + P_MMIO_SIZE_BYTES);

    wire [31:0] cpu_imem_canonicalized_ram_addr =
        cpu_imem_addr_i - P_RAM_START_BYTE_ADDR;
    wire [31:0] cpu_dmem_canonicalized_ram_addr =
        cpu_dmem_addr_i - P_RAM_START_BYTE_ADDR;
    wire [31:0] io_canonicalized_ram_addr = {16'b0, io_addr_i};
    wire io_address_is_ram = io_canonicalized_ram_addr < P_RAM_SIZE_BYTES;
    wire io_ram_request = !reset_ni && io_req_i && io_address_is_ram;
    wire cpu_ram_request =
        reset_ni && cpu_dmem_req_i && is_dmem_valid_ram_request;
    wire cpu_mmio_request =
        reset_ni && cpu_dmem_req_i && is_dmem_valid_mmio_request;
    wire cpu_mmio_output_request =
        cpu_mmio_request &&
        (cpu_dmem_addr_i >= P_MMIO_START_BYTE_ADDR + 32'd4);
    wire cpu_invalid_request =
        reset_ni && cpu_dmem_req_i &&
        !is_dmem_valid_ram_request && !is_dmem_valid_mmio_request;

    wire [31:0] io_selected_rdata =
        ram_rw0_rdata_i >> {io_canonicalized_ram_addr[1:0], 3'b000};

    assign io_valid_o = !reset_ni && io_req_i &&
                        (!io_address_is_ram || ram_rw0_valid_i);
    assign io_err_o = !reset_ni && io_req_i && !io_address_is_ram;
    assign io_data_o = reset_ni ?
        (cpu_mmio_output_request && cpu_dmem_wen_i ?
         cpu_dmem_wdata_i[7:0] : 8'b0) :
        (io_ram_request ? io_selected_rdata[7:0] : 8'b0);
    assign io_wen_o = cpu_mmio_output_request && cpu_dmem_wen_i;

    assign cpu_imem_data_o = ram_r0_data_i;
    assign cpu_imem_valid_o = reset_ni && cpu_imem_req_i &&
        (is_imem_valid_ram_request ? ram_r0_valid_i : 1'b1);
    assign cpu_imem_err_o =
        reset_ni && cpu_imem_req_i && !is_imem_valid_ram_request;

    assign cpu_dmem_rdata_o = is_dmem_valid_ram_request ? ram_rw0_rdata_i :
        is_dmem_valid_mmio_request ? {24'b0, io_data_i} : 32'hdeadbeef;
    assign cpu_dmem_valid_o = (cpu_ram_request && ram_rw0_valid_i) ||
                              cpu_mmio_request || cpu_invalid_request;
    assign cpu_dmem_err_o = cpu_invalid_request;

    assign ram_r0_word_addr_o =
        cpu_imem_canonicalized_ram_addr[`RAM_ADDR_WIDTH+1:2];
    assign ram_r0_req_o =
        reset_ni && is_imem_valid_ram_request && cpu_imem_req_i;
    assign ram_rw0_word_addr_o = reset_ni ?
        cpu_dmem_canonicalized_ram_addr[`RAM_ADDR_WIDTH+1:2] :
        io_canonicalized_ram_addr[`RAM_ADDR_WIDTH+1:2];
    assign ram_rw0_wdata_o = reset_ni ?
        cpu_dmem_wdata_i : {4{io_data_i}};
    assign ram_rw0_wstrb_o = reset_ni ? cpu_dmem_wstrb_i :
        (4'b0001 << io_canonicalized_ram_addr[1:0]);
    assign ram_rw0_wen_o = reset_ni ?
        (cpu_ram_request && cpu_dmem_wen_i) :
        (io_ram_request && io_wen_i);
    assign ram_rw0_req_o = cpu_ram_request || io_ram_request;
endmodule

module soc
(
    input         clock_i,
    input         reset_ni,
    output        cpu_exception_o,
    output [31:0] cpu_exception_vector_o,
    input  [15:0] io_addr_i,
    input   [7:0] io_data_i,
    output  [7:0] io_data_o,
    input         io_wen_i,
    output        io_wen_o,
    input         io_req_i,
    output        io_valid_o,
    output        io_err_o
);
    wire [31:0] cpu_exception_vector;
    wire [31:0] cpu_imem_addr;
    wire [31:0] cpu_imem_data;
    wire        cpu_imem_req;
    wire        cpu_imem_valid;
    wire        cpu_imem_err;
    wire [31:0] cpu_dmem_addr;
    wire [31:0] cpu_dmem_rdata;
    wire [31:0] cpu_dmem_wdata;
    wire  [3:0] cpu_dmem_wstrb;
    wire        cpu_dmem_wen;
    wire        cpu_dmem_req;
    wire        cpu_dmem_valid;
    wire        cpu_dmem_err;

    wire [`RAM_ADDR_WIDTH-1:0] ram_r0_word_addr;
    wire [31:0] ram_r0_data;
    wire        ram_r0_req;
    wire        ram_r0_valid;
    wire [`RAM_ADDR_WIDTH-1:0] ram_rw0_word_addr;
    wire [31:0] ram_rw0_rdata;
    wire [31:0] ram_rw0_wdata;
    wire  [3:0] ram_rw0_wstrb;
    wire        ram_rw0_wen;
    wire        ram_rw0_req;
    wire        ram_rw0_valid;

    rv32i_three_stage cpu
    (
        .clock_i(clock_i),
        .reset_ni(reset_ni),
        .exception_vector_o(cpu_exception_vector),
        .imem_addr_o(cpu_imem_addr),
        .imem_data_i(cpu_imem_data),
        .imem_req_o(cpu_imem_req),
        .imem_valid_i(cpu_imem_valid),
        .imem_err_i(cpu_imem_err),
        .dmem_addr_o(cpu_dmem_addr),
        .dmem_rdata_i(cpu_dmem_rdata),
        .dmem_wdata_o(cpu_dmem_wdata),
        .dmem_wstrb_o(cpu_dmem_wstrb),
        .dmem_wen_o(cpu_dmem_wen),
        .dmem_req_o(cpu_dmem_req),
        .dmem_valid_i(cpu_dmem_valid),
        .dmem_err_i(cpu_dmem_err)
    );

    rv32i_three_stage_mmu
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
        .cpu_imem_addr_i(cpu_imem_addr),
        .cpu_imem_data_o(cpu_imem_data),
        .cpu_imem_req_i(cpu_imem_req),
        .cpu_imem_valid_o(cpu_imem_valid),
        .cpu_imem_err_o(cpu_imem_err),
        .cpu_dmem_addr_i(cpu_dmem_addr),
        .cpu_dmem_rdata_o(cpu_dmem_rdata),
        .cpu_dmem_wdata_i(cpu_dmem_wdata),
        .cpu_dmem_wstrb_i(cpu_dmem_wstrb),
        .cpu_dmem_wen_i(cpu_dmem_wen),
        .cpu_dmem_req_i(cpu_dmem_req),
        .cpu_dmem_valid_o(cpu_dmem_valid),
        .cpu_dmem_err_o(cpu_dmem_err),
        .ram_r0_word_addr_o(ram_r0_word_addr),
        .ram_r0_data_i(ram_r0_data),
        .ram_r0_req_o(ram_r0_req),
        .ram_r0_valid_i(ram_r0_valid),
        .ram_rw0_word_addr_o(ram_rw0_word_addr),
        .ram_rw0_rdata_i(ram_rw0_rdata),
        .ram_rw0_wdata_o(ram_rw0_wdata),
        .ram_rw0_wstrb_o(ram_rw0_wstrb),
        .ram_rw0_wen_o(ram_rw0_wen),
        .ram_rw0_req_o(ram_rw0_req),
        .ram_rw0_valid_i(ram_rw0_valid)
    );

    mem_1r_1rw_asyncr_syncw_4x8bit
    #(
        .MEM_SIZE_BYTES(RAM_SIZE_BYTES)
    )
    ram
    (
        .clock_i(clock_i),
        .r0_word_addr_i(ram_r0_word_addr),
        .r0_data_o(ram_r0_data),
        .r0_req_i(ram_r0_req),
        .r0_valid_o(ram_r0_valid),
        .rw0_word_addr_i(ram_rw0_word_addr),
        .rw0_rdata_o(ram_rw0_rdata),
        .rw0_wdata_i(ram_rw0_wdata),
        .rw0_wstrb_i(ram_rw0_wstrb),
        .rw0_wen_i(ram_rw0_wen),
        .rw0_req_i(ram_rw0_req),
        .rw0_valid_o(ram_rw0_valid)
    );

    assign cpu_exception_o = cpu_exception_vector != 32'b0;
    assign cpu_exception_vector_o = cpu_exception_vector;
endmodule
