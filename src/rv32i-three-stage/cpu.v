`include "src/rv32i-common/params.vh"
`include "src/rv32i-memory/config.vh"
`include "src/rv32i-three-stage/params.vh"

module rv32i_three_stage_control_logic
(
    input            reset_ni,
    input            ex_valid_i,
    input     [31:0] inst_i,
    input            br_taken_i,

    output     [1:0] pc_sel_o,
    output           gpr_wen_o,
    output     [4:0] gpr_rs1_idx_o,
    output     [4:0] gpr_rs2_idx_o,
    output     [4:0] gpr_rd_idx_o,
    output     [2:0] imm_sel_o,
    output           a_sel_o,
    output           b_sel_o,
    output     [2:0] br_cond_o,
    output     [3:0] alu_op_o,
    output     [1:0] wb_sel_o,
    output           dmem_req_o,
    output           dmem_wen_o,
    output     [2:0] mem_width_o,
    output           exception_o,
    output    [31:0] exception_vector_o
);
    wire [6:0]  opcode  = inst_i[6:0];
    wire [2:0]  funct3  = inst_i[14:12];
    wire [6:0]  funct7  = inst_i[31:25];
    wire        active  = reset_ni && ex_valid_i;

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
    wire valid_op_imm = (funct3 == 3'b000) ||
                        (funct3 == 3'b010) ||
                        (funct3 == 3'b011) ||
                        (funct3 == 3'b100) ||
                        (funct3 == 3'b110) ||
                        (funct3 == 3'b111) ||
                        ((funct3 == 3'b001) && (funct7 == 7'b0000000)) ||
                        ((funct3 == 3'b101) &&
                         ((funct7 == 7'b0000000) ||
                          (funct7 == 7'b0100000)));
    wire valid_op = (funct7 == 7'b0000000) ||
                    ((funct7 == 7'b0100000) &&
                     ((funct3 == 3'b000) || (funct3 == 3'b101)));

    wire is_lui    = opcode == OPCODE_LUI;
    wire is_auipc  = opcode == OPCODE_AUIPC;
    wire is_jal    = opcode == OPCODE_JAL;
    wire is_jalr   = (opcode == OPCODE_JALR) && (funct3 == 3'b000);
    wire is_branch = (opcode == OPCODE_BRANCH) && valid_branch_funct3;
    wire is_load   = (opcode == OPCODE_LOAD) && valid_load_funct3;
    wire is_store  = (opcode == OPCODE_STORE) && valid_store_funct3;
    wire is_op_imm = (opcode == OPCODE_OP_IMM) && valid_op_imm;
    wire is_op     = (opcode == OPCODE_OP) && valid_op;
    wire is_ecall  = inst_i == 32'h00000073;
    wire is_ebreak = inst_i == 32'h00100073;
    wire is_legal = is_lui || is_auipc || is_jal || is_jalr ||
                    is_branch || is_load || is_store || is_op_imm ||
                    is_op || is_ecall || is_ebreak;

    assign pc_sel_o = !active ? PC_SEL_SEQUENTIAL :
                      is_jalr ? PC_SEL_JALR :
                      (is_jal || (is_branch && br_taken_i)) ?
                      PC_SEL_BRANCH : PC_SEL_SEQUENTIAL;
    assign gpr_wen_o = active &&
                       (is_lui || is_auipc || is_jal || is_jalr ||
                        is_op_imm || is_op || is_load);
    assign gpr_rs1_idx_o = inst_i[19:15];
    assign gpr_rs2_idx_o = inst_i[24:20];
    assign gpr_rd_idx_o  = inst_i[11:7];

    assign imm_sel_o = !active ? IMM_SEL_I :
                       is_store ? IMM_SEL_S :
                       is_branch ? IMM_SEL_B :
                       (is_lui || is_auipc) ? IMM_SEL_U :
                       is_jal ? IMM_SEL_J : IMM_SEL_I;
    assign a_sel_o = active && (is_auipc || is_jal || is_branch) ?
                     ASEL_MUX_PC : ASEL_MUX_RS1;
    assign b_sel_o = active && is_op ?
                     BSEL_MUX_RS2 : BSEL_MUX_IMM;
    assign br_cond_o = funct3;
    wire is_sub_or_sra = (is_op && funct7[5]) ||
                         (is_op_imm && (funct3 == 3'b101) && funct7[5]);
    assign alu_op_o = active && (is_op || is_op_imm) ?
                      {is_sub_or_sra, funct3} : ALU_OP_ADD;
    assign wb_sel_o = is_load ? WB_MUX_MEM_DATA :
                      (is_jal || is_jalr) ? WB_MUX_PC_PLUS4 :
                      is_lui ? WB_MUX_IMMEDIATE : WB_MUX_ALU_RESULT;
    assign dmem_req_o = active && (is_load || is_store);
    assign dmem_wen_o = active && is_store;
    assign mem_width_o = funct3;

    assign exception_o = active && (is_ecall || is_ebreak || !is_legal);
    assign exception_vector_o = !exception_o ? 32'b0 :
        (32'b1 << (is_ecall ? EXCEPTION_ECALL :
                   is_ebreak ? EXCEPTION_EBREAK :
                   EXCEPTION_ILLEGAL_INSTRUCTION));
endmodule

module rv32i_three_stage
(
    input            clock_i,
    input            reset_ni,

    output    [31:0] exception_vector_o,
    output reg       ex_valid,
    output           mw_is_load,

    output    [31:0] imem_addr_o,
    input     [31:0] imem_data_i,
    output           imem_req_o,
    input            imem_valid_i,
    input            imem_err_i,

    output    [31:0] dmem_addr_o,
    input     [31:0] dmem_rdata_i,
    output    [31:0] dmem_wdata_o,
    output     [3:0] dmem_wstrb_o,
    output           dmem_wen_o,
    output           dmem_req_o,
    input            dmem_valid_i,
    input            dmem_err_i
);
    reg [31:0] pc;

    reg [31:0] ex_pc;
    reg [31:0] ex_inst;

    reg        mw_valid;
    reg [31:0] mw_result;
    reg [31:0] mw_mem_addr;
    reg [31:0] mw_store_data;
    reg [4:0]  mw_rd;
    reg        mw_reg_write;
    reg [1:0]  mw_wb_sel;
    reg        mw_dmem_req;
    reg        mw_dmem_wen;
    reg [2:0]  mw_mem_width;

    reg        halted;
    reg [31:0] exception_vector;
    reg        pending_exception;
    reg [31:0] pending_exception_vector;
    reg [31:0] regfile [0:31];

    wire [1:0] ctl_pc_sel;
    wire ctl_gpr_wen;
    wire [4:0] rs1_idx;
    wire [4:0] rs2_idx;
    wire [4:0] rd_idx;
    wire [2:0] ctl_imm_sel;
    wire ctl_a_sel;
    wire ctl_b_sel;
    wire [2:0] ctl_br_cond;
    wire [3:0] ctl_alu_op;
    wire [1:0] ctl_wb_sel;
    wire ctl_dmem_req;
    wire ctl_dmem_wen;
    wire [2:0] ctl_mem_width;
    wire ex_exception;
    wire [31:0] ex_exception_vector;

    rv32i_three_stage_control_logic control_logic
    (
        .reset_ni(reset_ni),
        .ex_valid_i(ex_valid),
        .inst_i(ex_inst),
        .br_taken_i(br_compare_taken),
        .pc_sel_o(ctl_pc_sel),
        .gpr_wen_o(ctl_gpr_wen),
        .gpr_rs1_idx_o(rs1_idx),
        .gpr_rs2_idx_o(rs2_idx),
        .gpr_rd_idx_o(rd_idx),
        .imm_sel_o(ctl_imm_sel),
        .a_sel_o(ctl_a_sel),
        .b_sel_o(ctl_b_sel),
        .br_cond_o(ctl_br_cond),
        .alu_op_o(ctl_alu_op),
        .wb_sel_o(ctl_wb_sel),
        .dmem_req_o(ctl_dmem_req),
        .dmem_wen_o(ctl_dmem_wen),
        .mem_width_o(ctl_mem_width),
        .exception_o(ex_exception),
        .exception_vector_o(ex_exception_vector)
    );

    wire [31:0] imm;
    rv32i_immgen immgen
    (
        .inst_i(ex_inst),
        .imm_type_i(ctl_imm_sel),
        .imm_o(imm)
    );

    wire [31:0] reg_rs1 = (rs1_idx == 5'd0) ? 32'b0 : regfile[rs1_idx];
    wire [31:0] reg_rs2 = (rs2_idx == 5'd0) ? 32'b0 : regfile[rs2_idx];
    assign mw_is_load = mw_wb_sel == WB_MUX_MEM_DATA;
    wire [31:0] mw_forward_value = mw_is_load ? dmem_read_data : mw_result;
    wire mw_load_complete = !mw_is_load || dmem_valid_i;
    wire [31:0] rs1_val =
        (mw_valid && mw_reg_write && mw_load_complete &&
         (mw_rd != 5'd0) && (mw_rd == rs1_idx)) ?
        mw_forward_value : reg_rs1;
    wire [31:0] rs2_val =
        (mw_valid && mw_reg_write && mw_load_complete &&
         (mw_rd != 5'd0) && (mw_rd == rs2_idx)) ?
        mw_forward_value : reg_rs2;

    wire [31:0] alu_a = ctl_a_sel == ASEL_MUX_PC ? ex_pc : rs1_val;
    wire [31:0] alu_b = ctl_b_sel == BSEL_MUX_RS2 ? rs2_val : imm;
    wire [31:0] alu_out;
    rv32i_alu alu
    (
        .a_i(alu_a),
        .b_i(alu_b),
        .alu_op_i(ctl_alu_op),
        .out_o(alu_out)
    );

    wire br_compare_taken;
    rv32i_branch_comparator branch_comparator
    (
        .rs1_data_i(rs1_val),
        .rs2_data_i(rs2_val),
        .cond_i(ctl_br_cond),
        .taken_o(br_compare_taken)
    );
    wire ex_redirect = ex_valid && !ex_exception &&
                       (ctl_pc_sel != PC_SEL_SEQUENTIAL);
    wire [31:0] redirect_pc = ctl_pc_sel == PC_SEL_JALR ?
                              ((rs1_val + imm) & 32'hffff_fffe) :
                              (ex_pc + imm);
    wire [31:0] ex_result = ctl_wb_sel == WB_MUX_IMMEDIATE ? imm :
                            ctl_wb_sel == WB_MUX_PC_PLUS4 ?
                            (ex_pc + 32'd4) : alu_out;

    wire [31:0] dmem_aligned_addr;
    wire [31:0] dmem_read_data;
    wire [31:0] dmem_write_data;
    wire [3:0] dmem_wstrb;
    rv32i_single_cycle_dmem_aligner dmem_aligner
    (
        .byte_addr_i(mw_mem_addr),
        .byte_addr_o(dmem_aligned_addr),
        .mem_width_i(mw_mem_width),
        .rd_data_raw_i(dmem_rdata_i),
        .rd_data_o(dmem_read_data),
        .raw_wr_data_i(mw_store_data),
        .wr_data_o(dmem_write_data),
        .wstrb_o(dmem_wstrb)
    );

    wire mw_done = !mw_valid || !mw_dmem_req ||
                   dmem_valid_i || dmem_err_i;
    wire pipeline_advance = mw_done;
    wire fetch_enable = reset_ni && !halted && pipeline_advance &&
                        !pending_exception && !ex_exception && !ex_redirect;

    assign exception_vector_o = exception_vector;
    assign imem_addr_o = pc;
    assign imem_req_o = fetch_enable;
    assign dmem_addr_o = dmem_aligned_addr;
    assign dmem_wdata_o = dmem_write_data;
    assign dmem_wstrb_o = dmem_wstrb;
    assign dmem_wen_o = reset_ni && mw_valid && mw_dmem_wen && !halted;
    assign dmem_req_o = reset_ni && mw_valid && mw_dmem_req && !halted;

    always @(posedge clock_i)
    begin
        if (!reset_ni)
        begin
            pc <= RESET_VECTOR;
            ex_valid <= 1'b0;
            ex_pc <= RESET_VECTOR;
            ex_inst <= 32'b0;
            mw_valid <= 1'b0;
            mw_result <= 32'b0;
            mw_mem_addr <= 32'b0;
            mw_store_data <= 32'b0;
            mw_rd <= 5'b0;
            mw_reg_write <= 1'b0;
            mw_wb_sel <= WB_MUX_ALU_RESULT;
            mw_dmem_req <= 1'b0;
            mw_dmem_wen <= 1'b0;
            mw_mem_width <= 3'b010;
            halted <= 1'b0;
            exception_vector <= 32'b0;
            pending_exception <= 1'b0;
            pending_exception_vector <= 32'b0;
            for (integer idx = 0; idx < 32; idx = idx + 1)
                regfile[idx] <= 32'b0;
        end
        else if (!halted)
        begin
            if (mw_valid && mw_reg_write && mw_load_complete &&
                !(mw_dmem_req && dmem_err_i) && (mw_rd != 5'd0))
                regfile[mw_rd] <= mw_forward_value;

            if (mw_valid && mw_dmem_req && dmem_err_i)
            begin
                halted <= 1'b1;
                exception_vector <= 32'b1 << EXCEPTION_DMEM_BUS_ERROR;
                pending_exception <= 1'b0;
                ex_valid <= 1'b0;
                mw_valid <= 1'b0;
            end
            else if (!mw_done)
            begin
                // Hold EX while MEM/WB waits for its memory response.
            end
            else
            begin
                mw_valid <= ex_valid && !ex_exception;
                if (ex_valid && !ex_exception)
                begin
                    mw_result <= ex_result;
                    mw_mem_addr <= alu_out;
                    mw_store_data <= rs2_val;
                    mw_rd <= rd_idx;
                    mw_reg_write <= ctl_gpr_wen;
                    mw_wb_sel <= ctl_wb_sel;
                    mw_dmem_req <= ctl_dmem_req;
                    mw_dmem_wen <= ctl_dmem_wen;
                    mw_mem_width <= ctl_mem_width;
                end

                if (ex_exception)
                begin
                    halted <= 1'b1;
                    exception_vector <= ex_exception_vector;
                    pending_exception <= 1'b0;
                    ex_valid <= 1'b0;
                end
                else if (ex_redirect)
                begin
                    pc <= redirect_pc;
                    pending_exception <= 1'b0;
                    ex_valid <= 1'b0;
                end
                else if (imem_req_o && (pc[1:0] != 2'b00))
                begin
                    pending_exception <= 1'b1;
                    pending_exception_vector <=
                        32'b1 << EXCEPTION_IMEM_MISALIGNMENT;
                    ex_valid <= 1'b0;
                end
                else if (imem_req_o && imem_err_i)
                begin
                    pending_exception <= 1'b1;
                    pending_exception_vector <=
                        32'b1 << EXCEPTION_IMEM_BUS_ERROR;
                    ex_valid <= 1'b0;
                end
                else if (imem_req_o && imem_valid_i)
                begin
                    ex_inst <= imem_data_i;
                    ex_pc <= pc;
                    ex_valid <= 1'b1;
                    pc <= pc + 32'd4;
                end
                else
                    ex_valid <= 1'b0;
            end

            if (pending_exception && !ex_valid && mw_done && !ex_exception)
            begin
                halted <= 1'b1;
                exception_vector <= pending_exception_vector;
                pending_exception <= 1'b0;
            end
        end
    end
endmodule
