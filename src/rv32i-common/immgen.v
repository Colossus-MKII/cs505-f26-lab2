`include "src/rv32i-common/params.vh"

module rv32i_immgen
(
    input  [31:0] inst_i,
    input   [2:0] imm_type_i,

    output reg [31:0] imm_o
);
    always @(*) 
    begin
        case(imm_type_i)
            IMM_SEL_I: imm_o = {{20{inst_i[31]}}, inst_i[31:20]};
            IMM_SEL_S: imm_o = {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]};
            IMM_SEL_B: imm_o = {{19{inst_i[31]}}, inst_i[31], inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0};
            IMM_SEL_J: imm_o = {{11{inst_i[31]}}, inst_i[31], inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0};
            IMM_SEL_U: imm_o = {inst_i[31:12], 12'b0};
            default:   imm_o = 32'b0;
        endcase
    end
endmodule