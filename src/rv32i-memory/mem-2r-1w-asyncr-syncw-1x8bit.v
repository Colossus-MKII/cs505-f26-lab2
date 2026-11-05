// 2 read port, 1 w port
// asynchronous read on reads, synchronous writes
module mem_2r_1w_asyncr_syncw_8bit
#(
	parameter [31:0]   MEM_SIZE_BYTES = 32, // default - 32-byte memory (e.g., regfile)
    parameter [1023:0] INIT_FILENAME  = ""
)
(
    input                       clock_i,

    // port 1 (read)
	input      [$clog2(MEM_SIZE_BYTES)-1:0] r0_addr_i,
	output     [7:0]                        r0_data_o,

    // port 2 (read)
	input      [$clog2(MEM_SIZE_BYTES)-1:0] r1_addr_i,
	output     [7:0]                        r1_data_o,

    // port 2 (write)
	input      [$clog2(MEM_SIZE_BYTES)-1:0] w0_addr_i,
	input                                   w0_wen_i,
	input      [7:0]                        w0_wdata_i
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
    assign r0_data_o = memory[r0_addr_i];
    assign r1_data_o = memory[r1_addr_i]; 

    // sequential write
	always @(posedge clock_i) 
    begin
        if(w0_wen_i) 
            memory[w0_addr_i] <= w0_wdata_i;
    end
endmodule