`ifndef RV32I_COMMON__PARAMS_VH
`define RV32I_COMMON__PARAMS_VH

/*
 * RISC-V defines
 */
localparam [6:0] OPCODE_LUI    = 7'b0110111;
localparam [6:0] OPCODE_AUIPC  = 7'b0010111;
localparam [6:0] OPCODE_JAL    = 7'b1101111;
localparam [6:0] OPCODE_JALR   = 7'b1100111;
localparam [6:0] OPCODE_BRANCH = 7'b1100011;
localparam [6:0] OPCODE_LOAD   = 7'b0000011;
localparam [6:0] OPCODE_STORE  = 7'b0100011;
localparam [6:0] OPCODE_OP_IMM = 7'b0010011;
localparam [6:0] OPCODE_OP     = 7'b0110011;
localparam [6:0] OPCODE_SYSTEM = 7'b1110011;

// ALU Operations {is_sub|is_sra, funct3}
localparam [3:0] ALU_OP_ADD  = 4'b0000;
localparam [3:0] ALU_OP_SLL  = 4'b0001;
localparam [3:0] ALU_OP_SLT  = 4'b0010;
localparam [3:0] ALU_OP_SLTU = 4'b0011;
localparam [3:0] ALU_OP_XOR  = 4'b0100;
localparam [3:0] ALU_OP_SRL  = 4'b0101;
localparam [3:0] ALU_OP_OR   = 4'b0110;
localparam [3:0] ALU_OP_AND  = 4'b0111;
localparam [3:0] ALU_OP_SUB  = 4'b1000;
localparam [3:0] ALU_OP_SRA  = 4'b1101;

// branch conditions {funct3}
localparam [2:0] BR_COND_BEQ  = 3'b000;
localparam [2:0] BR_COND_BNE  = 3'b001;
localparam [2:0] BR_COND_BLT  = 3'b100;
localparam [2:0] BR_COND_BGE  = 3'b101;
localparam [2:0] BR_COND_BLTU = 3'b110;
localparam [2:0] BR_COND_BGEU = 3'b111;

// memory access widths {funct3}
localparam [2:0] MEM_WIDTH_LB  = 3'b000;
localparam [2:0] MEM_WIDTH_LH  = 3'b001;
localparam [2:0] MEM_WIDTH_LW  = 3'b010;
localparam [2:0] MEM_WIDTH_LBU = 3'b100;
localparam [2:0] MEM_WIDTH_LHU = 3'b101;

// immediate types (arbitrary encoding, but this is what I choose)
localparam [2:0] IMM_SEL_I = 3'd0;
localparam [2:0] IMM_SEL_S = 3'd1;
localparam [2:0] IMM_SEL_B = 3'd2;
localparam [2:0] IMM_SEL_U = 3'd3;
localparam [2:0] IMM_SEL_J = 3'd4;

`endif /* RV32I_COMMON__PARAMS_VH */
