`ifndef RV32I_MULTI_CYCLE_SINGLE_BUS__PARAMS_VH
`define RV32I_MULTI_CYCLE_SINGLE_BUS__PARAMS_VH

/*
 * mux select signals 
 */
// PC mux
localparam PC_SRC_BUSPLUS4 = 1'b0;
localparam PC_SRC_BUS      = 1'b1;

// MDR select
localparam MDR_SRC_MEM = 1'b0;
localparam MDR_SRC_BUS = 1'b1;

/*
 * state machine states
 */
localparam [5:0] STATE_RESET       = 6'd0;

localparam [5:0] STATE_FETCH_0     = 6'd1;
localparam [5:0] STATE_FETCH_1     = 6'd2;
localparam [5:0] STATE_FETCH_2     = 6'd3;

localparam [5:0] STATE_ALU_RTYPE_0 = 6'd4;
localparam [5:0] STATE_ALU_RTYPE_1 = 6'd5;
localparam [5:0] STATE_ALU_RTYPE_2 = 6'd6;

localparam [5:0] STATE_ALU_ITYPE_0 = 6'd7;
localparam [5:0] STATE_ALU_ITYPE_1 = 6'd8;
localparam [5:0] STATE_ALU_ITYPE_2 = 6'd9;

localparam [5:0] STATE_JALR_0      = 6'd10;
localparam [5:0] STATE_JALR_1      = 6'd11;
localparam [5:0] STATE_JALR_2      = 6'd12;
localparam [5:0] STATE_JALR_3      = 6'd13;

localparam [5:0] STATE_LOAD_0      = 6'd14;
localparam [5:0] STATE_LOAD_1      = 6'd15;
localparam [5:0] STATE_LOAD_2      = 6'd16;
localparam [5:0] STATE_LOAD_3      = 6'd17;
localparam [5:0] STATE_LOAD_4      = 6'd18;

localparam [5:0] STATE_SYSTEM      = 6'd19;

localparam [5:0] STATE_STORE_0     = 6'd20;
localparam [5:0] STATE_STORE_1     = 6'd21;
localparam [5:0] STATE_STORE_2     = 6'd22;
localparam [5:0] STATE_STORE_3     = 6'd23;
localparam [5:0] STATE_STORE_4     = 6'd24;

localparam [5:0] STATE_BRANCH_0    = 6'd25;
localparam [5:0] STATE_BRANCH_1    = 6'd26;
localparam [5:0] STATE_BRANCH_2    = 6'd27;
localparam [5:0] STATE_BRANCH_3    = 6'd28;
localparam [5:0] STATE_BRANCH_4    = 6'd29;

localparam [5:0] STATE_LUI         = 6'd30;

localparam [5:0] STATE_AUIPC_0     = 6'd31;
localparam [5:0] STATE_AUIPC_1     = 6'd32;
localparam [5:0] STATE_AUIPC_2     = 6'd33;

localparam [5:0] STATE_JAL_0       = 6'd34;
localparam [5:0] STATE_JAL_1       = 6'd35;
localparam [5:0] STATE_JAL_2       = 6'd36;
localparam [5:0] STATE_JAL_3       = 6'd37;

/*
 * Exceptions
 */
localparam integer EXCEPTION_ECALL = 0;
localparam integer EXCEPTION_EBREAK = 1;
localparam integer EXCEPTION_ILLEGAL_INSTRUCTION = 2;
localparam integer EXCEPTION_MEM_MISALIGNMENT = 3;
localparam integer EXCEPTION_MEM_BUS_ERROR = 4;
localparam integer EXCEPTION_BUS_FAULT = 5;

/*
 * microop macros
 */
// MAR = PC
`define MAR_eq_PC \
    mar_wen_o    = 1; \
    pc_bus_en_o  = 1

// MAR = A + B
`define MAR_eq_A_plus_B \
    mar_wen_o    = 1; \
    alu_bus_en_o = 1; \
    alu_op_o     = ALU_OP_ADD

// PC = BUS + 4
`define PC_eq_BUS_plus_4 \
    pc_wen_o     = 1; \
    pc_src_o     = PC_SRC_BUSPLUS4

// PCS = BUS
`define PCS_eq_BUS \
    pcs_wen_o    = 1

// MDR = a complete instruction word from MEM[MAR]
`define MDR_eq_MEM_WORD_at_MAR \
    mem_req_o = 1; \
    mdr_wen_o = mem_valid_i; \
    mem_width_o = MEM_WIDTH_LW; \
    mdr_src_o = MDR_SRC_MEM

// MDR = an aligned and extended load value from MEM[MAR]
`define MDR_eq_MEM_LOAD_at_MAR \
    mem_req_o = 1; \
    mdr_wen_o = mem_valid_i; \
    mem_width_o = funct3; \
    mdr_src_o = MDR_SRC_MEM

// MDR = GPR[rs2]
`define MDR_eq_GPR_at_RS2 \
    gpr_bus_en_o = 1; \
    gpr_addr_o = gpr_rs2_idx; \
    mdr_wen_o = 1; \
    mdr_src_o = MDR_SRC_BUS

// MEM[MAR] = MDR
`define MEM_at_MAR_eq_MDR \
    mem_req_o = 1; \
    mem_wen_o = 1

// IR = MDR
`define IR_eq_MDR \
    ir_wen_o        = 1; \
    mdr_bus_en_o    = 1; \
    mem_width_o     = MEM_WIDTH_LW

// A = GPR[rs1]
`define A_eq_GPR_at_RS1 \
    a_wen_o      = 1; \
    gpr_bus_en_o = 1; \
    gpr_addr_o   = gpr_rs1_idx

// A = PCS
`define A_eq_PCS \
    a_wen_o      = 1; \
    pcs_bus_en_o = 1

// B = GPR[rs2]
`define B_eq_GPR_at_RS2 \
    b_wen_o      = 1; \
    gpr_bus_en_o = 1; \
    gpr_addr_o   = gpr_rs2_idx

// B = sext(immI)
`define B_eq_SEXT_IMMI \
    b_wen_o      = 1; \
    imm_bus_en_o = 1; \
    imm_sel_o    = IMM_SEL_I

// B = sext(immS)
`define B_eq_SEXT_IMMS \
    b_wen_o      = 1; \
    imm_bus_en_o = 1; \
    imm_sel_o    = IMM_SEL_S

// B = sext(immB)
`define B_eq_SEXT_IMMB \
    b_wen_o      = 1; \
    imm_bus_en_o = 1; \
    imm_sel_o    = IMM_SEL_B

// B = sext(immU)
`define B_eq_SEXT_IMMU \
    b_wen_o      = 1; \
    imm_bus_en_o = 1; \
    imm_sel_o    = IMM_SEL_U

// B = sext(immJ)
`define B_eq_SEXT_IMMJ \
    b_wen_o      = 1; \
    imm_bus_en_o = 1; \
    imm_sel_o    = IMM_SEL_J

// BUS = GPR[rs2]
`define BUS_eq_GPR_at_RS2 \
    gpr_bus_en_o = 1; \
    gpr_addr_o   = gpr_rs2_idx

// GPR[rd] = A + B
`define GPR_at_RD_eq_A_plus_B \
    alu_bus_en_o = 1; \
    alu_op_o     = ALU_OP_ADD; \
    gpr_wen_o    = 1; \
    gpr_addr_o   = gpr_rd_idx

// GPR[rd] = A (op) B
`define GPR_at_RD_eq_A_op_B \
    alu_bus_en_o = 1; \
    alu_op_o     = {is_sub_or_sra, funct3}; \
    gpr_wen_o    = 1; \
    gpr_addr_o   = gpr_rd_idx

// GPR[rd] = PC
`define GPR_at_RD_eq_PC \
    pc_bus_en_o = 1; \
    gpr_wen_o   = 1; \
    gpr_addr_o  = gpr_rd_idx

// GPR[rd] = sext(MDR)
`define GPR_at_RD_eq_SEXT_MDR_FUNCT3 \
    mdr_bus_en_o = 1; \
    mem_width_o  = funct3; \
    gpr_wen_o    = 1; \
    gpr_addr_o   = gpr_rd_idx

// GPR[rd] = sext(immU)
`define GPR_at_RD_eq_SEXT_IMMU \
    imm_bus_en_o = 1; \
    imm_sel_o    = IMM_SEL_U; \
    gpr_wen_o    = 1; \
    gpr_addr_o   = gpr_rd_idx

// PC = A + B
`define PC_eq_A_plus_B \
    pc_src_o     = PC_SRC_BUS; \
    pc_wen_o     = 1; \
    alu_bus_en_o = 1; \
    alu_op_o     = ALU_OP_ADD

// PC = (A + B) & ~1, as required by JALR
`define PC_eq_A_plus_B_JALR \
    pc_src_o       = PC_SRC_BUS; \
    pc_clear_lsb_o = 1; \
    pc_wen_o       = 1; \
    alu_bus_en_o   = 1; \
    alu_op_o       = ALU_OP_ADD

`endif /* RV32I_MULTI_CYCLE_SINGLE_BUS__PARAMS_VH */
