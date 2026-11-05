`include "src/rv32i-common/params.vh"

module rv32i_branch_comparator
(
    input  [31:0] rs1_data_i,
    input  [31:0] rs2_data_i,
    input   [2:0] cond_i,	

    output reg    taken_o
);
    always @(*) 
    begin
        case(cond_i)
            BR_COND_BEQ:  taken_o = (rs1_data_i == rs2_data_i);
            BR_COND_BNE:  taken_o = (rs1_data_i != rs2_data_i);
            BR_COND_BLT:  taken_o = ($signed(rs1_data_i) < $signed(rs2_data_i));
            BR_COND_BGE:  taken_o = ($signed(rs1_data_i) >= $signed(rs2_data_i));
            BR_COND_BLTU: taken_o = (rs1_data_i < rs2_data_i);
            BR_COND_BGEU: taken_o = (rs1_data_i >= rs2_data_i);
            default: taken_o = 1'b0;
        endcase
    end
endmodule