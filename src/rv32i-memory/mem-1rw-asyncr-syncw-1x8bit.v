// 1 read/write port
// asynchronous read on reads, synchronous writes
module mem_1rw_asyncr_syncw_8bit
#(
	parameter [31:0]   MEM_SIZE_BYTES = 32, // default - 32-byte memory (e.g., regfile)
    parameter [1023:0] INIT_FILENAME  = ""
)
(
    input                       clock_i,

    // port 1 (read/write)
	input      [$clog2(MEM_SIZE_BYTES)-1:0] rw0_addr_i,
	output     [7:0]                        rw0_rdata_o,
	input      [7:0]                        rw0_wdata_i,
	input                                   rw0_wen_i
);
    reg [7:0] memory [0:MEM_SIZE_BYTES-1];

    // initialize the memory based on parameter provided or not
    initial
    begin
        if (INIT_FILENAME != "")
        begin
            $readmemh(INIT_FILENAME, memory);    
        end
    end
    
    // combinatorial reads
    assign rw0_rdata_o = memory[rw0_addr_i];

    // sequential write
	always @(posedge clock_i) 
    begin
        if(rw0_wen_i) 
            memory[rw0_addr_i] <= rw0_wdata_i;
    end
endmodule