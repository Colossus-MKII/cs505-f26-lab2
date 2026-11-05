`include "src/rv32i-memory/config.vh"

// 1 rw port
// asynchronous read on reads, synchronous writes
// word-aligned accesses
`define MEM_NUM_WORDS (MEM_SIZE_BYTES / 4)
`define ADDR_WIDTH $clog2(`MEM_NUM_WORDS)

module mem_1rw_asyncr_syncw_4x8bit
#(
	parameter [31:0] MEM_SIZE_BYTES      = RAM_SIZE_BYTES  // 4B aligned
)
(
    input                          clock_i,
	
    // port 2 (read-write only)
	input      [`ADDR_WIDTH - 1:0] rw0_word_addr_i,
    output     [31:0]              rw0_rdata_o,
	input      [31:0]              rw0_wdata_i,
	input      [3:0]               rw0_wstrb_i,
	input                          rw0_wen_i,
	input                          rw0_req_i,
	output                         rw0_valid_o
);
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) 
        begin
            localparam [1023:0] INIT_FILENAME = (i == 0) ? `SRAM_INIT_FILENAME_10 :
                                                (i == 1) ? `SRAM_INIT_FILENAME_32 :
                                                (i == 2) ? `SRAM_INIT_FILENAME_54 :
                                                           `SRAM_INIT_FILENAME_76;

            mem_1rw_asyncr_syncw_8bit 
            #(
                .MEM_SIZE_BYTES(`MEM_NUM_WORDS),
                .INIT_FILENAME(INIT_FILENAME)
            ) 
            sram
            (
                .clock_i(clock_i),

                .rw0_addr_i(rw0_word_addr_i),
                .rw0_wen_i(rw0_wstrb_i[i] & rw0_wen_i & rw0_req_i),
                .rw0_wdata_i(rw0_wdata_i[i*8+7:i*8]),
                .rw0_rdata_o(rw0_rdata_o[i*8+7:i*8])
            );
        end
    endgenerate

    // same-cycle response is OK
    assign rw0_valid_o = rw0_req_i;
endmodule
