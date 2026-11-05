`include "src/rv32i-common/params.vh"
`include "src/rv32i-memory/config.vh"
`include "src/rv32i-single-cycle/params.vh"

/* purely combinational */
module rv32i_single_cycle_control_logic
(
    input        reset_ni,
    
    input [31:0] inst_i,
    input        br_taken_i,
    
    /* exceptions */
    output reg [31:0] exception_vector_o,
    
    /* control signals */
    output       pc_sel_o,
    output       pc_wen_o,
    output       gpr_wen_o,
    output [4:0] gpr_rs1_idx_o,
    output [4:0] gpr_rs2_idx_o,
    output [4:0] gpr_rd_idx_o,
    output [2:0] imm_sel_o,
    output       a_sel_o,
    output       b_sel_o,
    output [2:0] br_cond_o,
    output [3:0] alu_op_o,
    output [1:0] wb_sel_o,

    /* memory interfaces */
    output       imem_req_o,
    input        imem_valid_i,
    input        imem_faulty_alignment_i,
    input        imem_bus_err_i,

    output       dmem_req_o,
    output       dmem_wen_o,
    output [2:0] dmem_width_o,
    input        dmem_valid_i,
    input        dmem_bus_err_i
);
    wire [6:0]  opcode  = inst_i[6:0];
    wire [2:0]  funct3  = inst_i[14:12];
    wire [6:0]  funct7  = inst_i[31:25];
    wire [11:0] funct12 = inst_i[31:20];

    wire valid_branch_funct3 = (funct3 == BR_COND_BEQ)  ||
                               (funct3 == BR_COND_BNE)  ||
                               (funct3 == BR_COND_BLT)  ||
                               (funct3 == BR_COND_BGE)  ||
                               (funct3 == BR_COND_BLTU) ||
                               (funct3 == BR_COND_BGEU);
    wire valid_load_funct3 = (funct3 == MEM_WIDTH_LB)  ||
                             (funct3 == MEM_WIDTH_LH)  ||
                             (funct3 == MEM_WIDTH_LW)  ||
                             (funct3 == MEM_WIDTH_LBU) ||
                             (funct3 == MEM_WIDTH_LHU);
    wire valid_store_funct3 = (funct3 == MEM_WIDTH_LB) ||
                              (funct3 == MEM_WIDTH_LH) ||
                              (funct3 == MEM_WIDTH_LW);

    wire valid_op_imm = ((funct3 == 3'b000) ||  // ADDI
                         (funct3 == 3'b010) ||  // SLTI
                         (funct3 == 3'b011) ||  // SLTIU
                         (funct3 == 3'b100) ||  // XORI
                         (funct3 == 3'b110) ||  // ORI
                         (funct3 == 3'b111)) || // ANDI
                        ((funct3 == 3'b001) && (funct7 == 7'b0000000)) || // SLLI
                        ((funct3 == 3'b101) &&
                         ((funct7 == 7'b0000000) || (funct7 == 7'b0100000))); // SRLI/SRAI

    wire valid_op = (funct7 == 7'b0000000) ||
                    ((funct7 == 7'b0100000) &&
                     ((funct3 == 3'b000) || (funct3 == 3'b101))); // SUB/SRA

    wire is_lui    = (opcode == OPCODE_LUI);
    wire is_auipc  = (opcode == OPCODE_AUIPC);
    wire is_jal    = (opcode == OPCODE_JAL);
    wire is_jalr   = (opcode == OPCODE_JALR)   && (funct3 == 3'b000);
    wire is_branch = (opcode == OPCODE_BRANCH) && valid_branch_funct3;
    wire is_load   = (opcode == OPCODE_LOAD)   && valid_load_funct3;
    wire is_store  = (opcode == OPCODE_STORE)  && valid_store_funct3;
    wire is_op_imm = (opcode == OPCODE_OP_IMM) && valid_op_imm;
    wire is_op     = (opcode == OPCODE_OP)      && valid_op;
    wire is_ecall  = (opcode == OPCODE_SYSTEM) & (funct3 == 3'b000) & (funct12 == 12'h000);
    wire is_ebreak = (opcode == OPCODE_SYSTEM) & (funct3 == 3'b000) & (funct12 == 12'h001);

    assign pc_sel_o = (is_jal | is_jalr | (is_branch & br_taken_i)) ? PC_MUX_ALU : PC_MUX_PCPLUS4;

    // pc_wen_o: always writing for a single-cycle CPU (unless stalled for some reason)
    assign pc_wen_o = reset_ni & imem_valid_i;

    // all operations write to GPRs except store/branch
    assign gpr_wen_o     = reset_ni & ((is_lui | is_auipc | is_jal | is_jalr | is_op_imm | is_op) 
                            | (is_load & dmem_valid_i));
    assign gpr_rs1_idx_o = inst_i[19:15];
    assign gpr_rs2_idx_o = inst_i[24:20];
    assign gpr_rd_idx_o  = inst_i[11:7];

    assign imm_sel_o     = is_store            ? IMM_SEL_S :
                           is_branch           ? IMM_SEL_B :
                           (is_lui | is_auipc) ? IMM_SEL_U :
                           is_jal              ? IMM_SEL_J :
                                                 IMM_SEL_I ;
    assign a_sel_o = (is_auipc | is_jal | is_branch) ? ASEL_MUX_PC : ASEL_MUX_RS1;
    assign b_sel_o = is_op ? BSEL_MUX_RS2 : BSEL_MUX_IMM;

    assign br_cond_o = funct3;

    // alu_op_o: {is_sub_or_sra, funct3} 
    wire is_sub_or_sra = (is_op & funct7[5]) | (is_op_imm & (funct3 == 3'b101) & funct7[5]);
    assign alu_op_o    = (is_op | is_op_imm) ? {is_sub_or_sra, funct3} : ALU_OP_ADD;


    assign wb_sel_o = is_load            ? WB_MUX_MEM_DATA  :
                      (is_jal | is_jalr) ? WB_MUX_PC_PLUS4  :
                      is_lui             ? WB_MUX_IMMEDIATE :
                                           WB_MUX_ALU_RESULT;

    // memories - req/valid don't mean much for a single-cycle CPU
    assign imem_req_o = reset_ni;
    assign dmem_req_o = reset_ni & (is_load | is_store);
    assign dmem_width_o = funct3;
    assign dmem_wen_o = is_store & reset_ni;
    
    // exceptions
    always @(*)
    begin
        exception_vector_o = 0;

        if(reset_ni)
        begin
            exception_vector_o[EXCEPTION_ECALL] = is_ecall;
            exception_vector_o[EXCEPTION_EBREAK] = is_ebreak;
            exception_vector_o[EXCEPTION_ILLEGAL_INSTRUCTION] = ~(is_lui | is_auipc | is_jal | is_jalr | is_branch |
                                                                is_load | is_store | is_op_imm | is_op | is_ecall | is_ebreak);
            exception_vector_o[EXCEPTION_IMEM_MISALIGNMENT]   = imem_req_o & imem_faulty_alignment_i;
            exception_vector_o[EXCEPTION_IMEM_BUS_ERROR]      = imem_req_o & imem_bus_err_i;
            exception_vector_o[EXCEPTION_DMEM_BUS_ERROR]      = dmem_req_o & dmem_bus_err_i;
        end
    end
endmodule

// the CPU module just runs code. checking memory bounds and applying address
// space offsets is done externally (ideally by the system bus, for example)
// no parameters bc the netlist cannot be parameterized
module rv32i_single_cycle 
(
    input            clock_i,
    input            reset_ni,

    // CPU state and exceptions
    output    [31:0] exception_vector_o,

    // imem interface (read only)
	output    [31:0] imem_addr_o,
	input     [31:0] imem_data_i,

    output           imem_req_o,          // request-valid-error interface
    input            imem_valid_i,
    input            imem_err_i,          
	
    // dmem interface (read-write)
	output    [31:0] dmem_addr_o,
    input     [31:0] dmem_rdata_i,
	output    [31:0] dmem_wdata_o,
    output     [3:0] dmem_wstrb_o,
    output           dmem_wen_o,

    output           dmem_req_o,          // request-valid-error interface
    input            dmem_valid_i,
    input            dmem_err_i          
);
    /* control logic I/O */
    wire        ctl_i_imem_faulty_alignment;

    wire        ctl_o_pc_sel;
    wire        ctl_o_pc_wen;
    wire        ctl_o_gpr_wen;
    wire  [4:0] ctl_o_rs1_idx;
    wire  [4:0] ctl_o_rs2_idx;
    wire  [4:0] ctl_o_rd_idx;
    wire  [2:0] ctl_o_imm_sel;
    wire        ctl_o_a_sel;
    wire        ctl_o_b_sel;
    wire  [2:0] ctl_o_br_cond;
    wire  [3:0] ctl_o_alu_op;
    wire  [2:0] ctl_o_mem_width;
    wire        ctl_o_dmem_wen;
    wire  [1:0] ctl_o_wb_sel;

    /* branch comparator outputs */
    wire        brc_o_br_taken;
    
    /* ALU outputs */
    wire [31:0] alu_o_out;

    /* PC updates */
    reg  [31:0] pc;
    
    wire [31:0] pc_plus_four = pc + 32'd4;
    wire [31:0] branch_target = {alu_o_out[31:1], 1'b0};
    wire [31:0] pc_next = ctl_o_pc_sel == PC_MUX_PCPLUS4 ? pc_plus_four : branch_target;

    always @(posedge clock_i)
    begin
        if(!reset_ni)
            pc <= RESET_VECTOR;
        else if(ctl_o_pc_wen)
            pc <= pc_next;
    end

    /* control logic */
    rv32i_single_cycle_control_logic control_logic
    (
        .reset_ni(reset_ni),

        .inst_i(imem_data_i),
        .br_taken_i(brc_o_br_taken),

        .exception_vector_o(exception_vector_o),

        .pc_sel_o(ctl_o_pc_sel),
        .pc_wen_o(ctl_o_pc_wen),
        .gpr_wen_o(ctl_o_gpr_wen),
        .gpr_rs1_idx_o(ctl_o_rs1_idx),
        .gpr_rs2_idx_o(ctl_o_rs2_idx),
        .gpr_rd_idx_o(ctl_o_rd_idx),
        .imm_sel_o(ctl_o_imm_sel),
        .a_sel_o(ctl_o_a_sel),
        .b_sel_o(ctl_o_b_sel),
        .br_cond_o(ctl_o_br_cond),
        .alu_op_o(ctl_o_alu_op),
        .wb_sel_o(ctl_o_wb_sel),

        .imem_req_o(imem_req_o),
        .imem_valid_i(imem_valid_i),
        .imem_faulty_alignment_i(ctl_i_imem_faulty_alignment),
        .imem_bus_err_i(imem_err_i),

        .dmem_req_o(dmem_req_o),
        .dmem_wen_o(ctl_o_dmem_wen),
        .dmem_width_o(ctl_o_mem_width),
        .dmem_valid_i(dmem_valid_i),
        .dmem_bus_err_i(dmem_err_i)
    );

    /* immediate generation */
    wire [31:0] img_o_imm;

    rv32i_immgen immgen
    (
        .inst_i(imem_data_i),
        .imm_type_i(ctl_o_imm_sel),
        .imm_o(img_o_imm)
    );

    /* GPRs */
    wire [31:0] gpr_o_rs1_raw;
    wire [31:0] gpr_o_rs2_raw;
    wire [31:0] gpr_o_rs1 = (ctl_o_rs1_idx == 5'd0) ? 32'b0 : gpr_o_rs1_raw;
    wire [31:0] gpr_o_rs2 = (ctl_o_rs2_idx == 5'd0) ? 32'b0 : gpr_o_rs2_raw;
    wire [31:0] gpr_i_rd;

    /* dmem sign extender */
    wire [31:0] dmem_aligner_o_rd_data;

    assign gpr_i_rd 
        = (ctl_o_wb_sel == WB_MUX_ALU_RESULT) ? alu_o_out 
        : (ctl_o_wb_sel == WB_MUX_MEM_DATA)   ? dmem_aligner_o_rd_data
        : (ctl_o_wb_sel == WB_MUX_IMMEDIATE)  ? img_o_imm
        : (ctl_o_wb_sel == WB_MUX_PC_PLUS4)   ? pc_plus_four 
        :                                       32'b0; 

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) 
        begin
            mem_2r_1w_asyncr_syncw_8bit 
            #(
                .MEM_SIZE_BYTES(32), // 32 registers total
                .INIT_FILENAME("")   // no initialization
            ) 
            gprs
            (
                .clock_i(clock_i),

                .r0_addr_i(ctl_o_rs1_idx),
                .r0_data_o(gpr_o_rs1_raw[i*8+7:i*8]),

                .r1_addr_i(ctl_o_rs2_idx),
                .r1_data_o(gpr_o_rs2_raw[i*8+7:i*8]),

                .w0_addr_i(ctl_o_rd_idx),
                .w0_wen_i(ctl_o_gpr_wen && (ctl_o_rd_idx != 5'd0)),
                .w0_wdata_i(gpr_i_rd[i*8+7:i*8])
            );
        end
    endgenerate

    /* alu */
    wire [31:0] alu_i_A;
    wire [31:0] alu_i_B;

    assign alu_i_A = (ctl_o_a_sel == ASEL_MUX_RS1) ? gpr_o_rs1 : pc;
    assign alu_i_B = (ctl_o_b_sel == BSEL_MUX_RS2) ? gpr_o_rs2 : img_o_imm;

    rv32i_alu alu
    (
        .a_i(alu_i_A),
        .b_i(alu_i_B),
        .alu_op_i(ctl_o_alu_op),

        .out_o(alu_o_out)
    );

    /* branch comparator */
    rv32i_branch_comparator br_comp
    (
        .rs1_data_i(gpr_o_rs1),
        .rs2_data_i(gpr_o_rs2),
        .cond_i(ctl_o_br_cond),	

        .taken_o(brc_o_br_taken)
    );
    
    /* DMEM address aligner */
    wire [31:0] dmem_aligner_o_dmem_addr;
    wire [31:0] dmem_aligner_o_wr_data;
    wire [3:0] dmem_aligner_o_wstrb;
    rv32i_single_cycle_dmem_aligner dmem_aligner
    (
        .byte_addr_i(alu_o_out),
        .byte_addr_o(dmem_aligner_o_dmem_addr),

        .mem_width_i(ctl_o_mem_width),

        .rd_data_raw_i(dmem_rdata_i),
        .rd_data_o(dmem_aligner_o_rd_data), // rotated (so the byte/half is in the LSB position in the data) and sexted

        .raw_wr_data_i(gpr_o_rs2),
        .wr_data_o(dmem_aligner_o_wr_data), // set up so that wstrb will do the right thing
        .wstrb_o(dmem_aligner_o_wstrb)
    );

    /* IMEM/DMEM addresses */
    assign dmem_addr_o = dmem_aligner_o_dmem_addr;
    assign dmem_wdata_o = dmem_aligner_o_wr_data;
    assign dmem_wstrb_o = dmem_aligner_o_wstrb;
    assign dmem_wen_o = ctl_o_dmem_wen;

    assign imem_addr_o = {pc[31:2], 2'b00};
    assign ctl_i_imem_faulty_alignment = pc[1:0] != 2'b00;
endmodule
