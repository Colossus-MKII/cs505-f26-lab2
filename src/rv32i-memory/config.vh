`ifndef RV32I_MEMORY__CONFIG_VH
`define RV32I_MEMORY__CONFIG_VH

/* our own SOC RAM address map */
localparam [31:0] RAM_START_BYTE_ADDR  = 32'h8000_0000;   // 4B aligned
localparam [31:0] RAM_SIZE_BYTES       = 256;             // 4B aligned (and Po2)
localparam [31:0] MMIO_START_BYTE_ADDR = 32'h0000_0100;   // MUST be word aligned
localparam [31:0] MMIO_SIZE_BYTES      = 32'd8;           // input at 0x100, result at 0x104

`define RAM_NUM_WORDS (RAM_SIZE_BYTES / 4)
`define RAM_ADDR_WIDTH $clog2(`RAM_NUM_WORDS)

localparam [31:0] RESET_VECTOR        = RAM_START_BYTE_ADDR;

`define SRAM_INIT_FILENAME_10 ""
`define SRAM_INIT_FILENAME_32 ""
`define SRAM_INIT_FILENAME_54 ""
`define SRAM_INIT_FILENAME_76 ""

`endif /* RV32I_MEMORY__CONFIG_VH */
