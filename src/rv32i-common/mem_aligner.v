`include "src/rv32i-common/params.vh"

module rv32i_single_cycle_dmem_aligner
(
    input      [31:0] byte_addr_i,
    output     [31:0] byte_addr_o,
    
    input      [2:0]  mem_width_i,

    input      [31:0] rd_data_raw_i,
    output reg [31:0] rd_data_o, // rotated so the byte/half is in the LSB position in the data

    input      [31:0] raw_wr_data_i,
    output     [31:0] wr_data_o, // set up so that wstrb will do the right thing
    output     [3:0]  wstrb_o
);
    // read
    wire [1:0]  byte_in_word = byte_addr_i[1:0];
    assign byte_addr_o = {byte_addr_i[31:2], 2'b0};
    wire [31:0] rd_data_aligned = 
            (byte_in_word == 2'b00) ? rd_data_raw_i :
            (byte_in_word == 2'b01) ? {8'h00,  rd_data_raw_i[31:8]} :
            (byte_in_word == 2'b10) ? {16'h00, rd_data_raw_i[31:16]} :
                                      {24'h00, rd_data_raw_i[31:24]};
    always @(*)
    begin
        case (mem_width_i)
            MEM_WIDTH_LB:  rd_data_o = {{24{rd_data_aligned[7]}}, rd_data_aligned[7:0]};    
            MEM_WIDTH_LH:  rd_data_o = {{16{rd_data_aligned[15]}}, rd_data_aligned[15:0]};
            MEM_WIDTH_LW:  rd_data_o = rd_data_aligned;
            MEM_WIDTH_LBU: rd_data_o = {24'h000000, rd_data_aligned[7:0]};
            MEM_WIDTH_LHU: rd_data_o = {16'h0000, rd_data_aligned[15:0]};
            default:       rd_data_o = rd_data_aligned; 
        endcase
    end

    // write
    assign wstrb_o = 
            (mem_width_i == MEM_WIDTH_LB || mem_width_i == MEM_WIDTH_LBU) ? (4'b0001 << byte_in_word) :
            (mem_width_i == MEM_WIDTH_LH || mem_width_i == MEM_WIDTH_LHU) ? (byte_in_word[1] ? 4'b1100 : 4'b0011) :
            (mem_width_i == MEM_WIDTH_LW)                                 ? 4'b1111 :
                                                                            4'b0000; 
    assign wr_data_o = 
            ((mem_width_i == MEM_WIDTH_LB) || (mem_width_i == MEM_WIDTH_LBU)) ? {4{raw_wr_data_i[7:0]}} :
            ((mem_width_i == MEM_WIDTH_LH) || (mem_width_i == MEM_WIDTH_LHU)) ? {2{raw_wr_data_i[15:0]}} :
                                                                                raw_wr_data_i;
endmodule