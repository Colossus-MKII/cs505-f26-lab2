`include "src/rv32i-common/params.vh"
`include "src/rv32i-memory/config.vh"
`include "src/rv32i-multi-cycle-single-bus/params.vh"

module rv32i_multi_cycle_bus_arbiter
(
    input        pcs_bus_en_i,
    input [31:0] pcs_i,

    input        pc_bus_en_i,
    input [31:0] pc_i,

    input        imm_bus_en_i,
    input [31:0] imm_i,

    input        alu_bus_en_i,
    input [31:0] alu_i,

    input        gpr_bus_en_i,
    input [31:0] gpr_i,

    input        mdr_bus_en_i,
    input [31:0] mdr_i,
    
    output [31:0] bus_o,
    output        bus_fault_multiple_drivers_o
);
    wire [5:0] drivers = {pcs_bus_en_i, pc_bus_en_i, imm_bus_en_i, alu_bus_en_i, gpr_bus_en_i, mdr_bus_en_i};
    assign bus_fault_multiple_drivers_o = (drivers & (drivers - 1)) != 0;

    // priority encoder with arbitrarily ordered inputs
    // alternatively, could consider a tri-state implementation, but FPGAs don't seem to like those
    assign bus_o = 
        pcs_bus_en_i ? pcs_i :
        pc_bus_en_i ? pc_i :
        imm_bus_en_i ? imm_i :
        alu_bus_en_i ? alu_i :
        gpr_bus_en_i ? gpr_i :
        mdr_bus_en_i ? mdr_i :
        32'hdeadbeef;
endmodule


/* microcoded state machine */
module rv32i_multi_cycle_control_logic
(
    input        clock_i,
    input        reset_ni,
    
    input [31:0] pc_i,
    input [31:0] mdr_i,
    input [31:0] ir_i,
    input        br_taken_i,
    
    /* exceptions */
    output reg [31:0] exception_vector_o,
    input             bus_fault_multiple_drivers_i,
    
    /* control signals */
    output reg       pcs_wen_o,
    output reg       pcs_bus_en_o,
    output reg       pc_src_o,
    output reg       pc_clear_lsb_o,
    output reg       pc_wen_o,
    output reg       pc_bus_en_o,
    output reg       gpr_wen_o,
    output reg [4:0] gpr_addr_o,
    output reg       gpr_bus_en_o,
    output reg       ir_wen_o,
    output reg [2:0] imm_sel_o,
    output reg       imm_bus_en_o,
    output reg       a_wen_o,
    output reg       b_wen_o,
    output reg [3:0] alu_op_o,
    output reg       alu_bus_en_o,
    output reg       mar_wen_o,
    output reg       mdr_wen_o,
    output reg       mdr_src_o,
    output reg       mdr_bus_en_o,
    output reg [2:0] br_cond_o,

    output reg       mem_req_o,
    output reg       mem_wen_o,
    output reg [2:0] mem_width_o,
    input            mem_valid_i,
    input            mem_bus_err_i
);
    // next state logic
    reg [5:0] state;
    reg [5:0] next_state;

    // During FETCH_2, MDR contains the newly fetched, registered instruction.
    // Decode it while transferring it to IR. Execution states decode IR.
    wire [31:0] decode_inst = (state == STATE_FETCH_2) ? mdr_i : ir_i;
    wire [6:0]  opcode      = decode_inst[6:0];
    wire [2:0]  funct3      = decode_inst[14:12];
    wire [6:0]  funct7      = decode_inst[31:25];
    wire [11:0] funct12     = decode_inst[31:20];
    wire [4:0]  gpr_rs1_idx = decode_inst[19:15];
    wire [4:0]  gpr_rs2_idx = decode_inst[24:20];
    wire [4:0]  gpr_rd_idx  = decode_inst[11:7];

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
    wire valid_op_imm = ((funct3 == 3'b000) ||
                         (funct3 == 3'b010) ||
                         (funct3 == 3'b011) ||
                         (funct3 == 3'b100) ||
                         (funct3 == 3'b110) ||
                         (funct3 == 3'b111)) ||
                        ((funct3 == 3'b001) && (funct7 == 7'b0000000)) ||
                        ((funct3 == 3'b101) &&
                         ((funct7 == 7'b0000000) || (funct7 == 7'b0100000)));
    wire valid_op = (funct7 == 7'b0000000) ||
                    ((funct7 == 7'b0100000) &&
                     ((funct3 == 3'b000) || (funct3 == 3'b101)));

    wire is_op     = (opcode == OPCODE_OP)      && valid_op;
    wire is_op_imm = (opcode == OPCODE_OP_IMM)  && valid_op_imm;
    wire is_jalr   = (opcode == OPCODE_JALR)    && (funct3 == 3'b000);
    wire is_load   = (opcode == OPCODE_LOAD)    && valid_load_funct3;
    wire is_system = (opcode == OPCODE_SYSTEM);
    wire is_ecall  = is_system & (funct3 == 3'b000) & (funct12 == 12'h000);
    wire is_ebreak = is_system & (funct3 == 3'b000) & (funct12 == 12'h001);
    wire is_store  = (opcode == OPCODE_STORE)   && valid_store_funct3;
    wire is_branch = (opcode == OPCODE_BRANCH)  && valid_branch_funct3;
    wire is_lui    = (opcode == OPCODE_LUI);
    wire is_auipc  = (opcode == OPCODE_AUIPC);
    wire is_jal    = (opcode == OPCODE_JAL);

    // useful signals
    wire is_sub_or_sra = (is_op & funct7[5]) | (is_op_imm & (funct3 == 3'b101) & funct7[5]);

    wire is_illegal_op = ~(is_lui | is_auipc | is_jal | is_jalr | is_branch | 
                           is_load | is_store | is_op_imm | is_op | is_ecall | is_ebreak); 

    always @(posedge clock_i) 
    begin
        state <= reset_ni && (exception_vector_o == 32'b0) ? next_state : STATE_RESET;
    end

    // exceptions
    always @(*)
    begin
        exception_vector_o = 0;

        if(reset_ni)
        begin
            if(state == STATE_FETCH_2)
            begin
                exception_vector_o[EXCEPTION_ECALL] = is_ecall;
                exception_vector_o[EXCEPTION_EBREAK] = is_ebreak;
                exception_vector_o[EXCEPTION_ILLEGAL_INSTRUCTION] = is_illegal_op;
            end
            
            exception_vector_o[EXCEPTION_MEM_MISALIGNMENT] = (pc_i[1:0] != 2'b00) && (state == STATE_FETCH_1);
            exception_vector_o[EXCEPTION_MEM_BUS_ERROR] = mem_bus_err_i && ((state == STATE_FETCH_1) || (state == STATE_LOAD_3) || (state == STATE_STORE_4));
            exception_vector_o[EXCEPTION_BUS_FAULT] = bus_fault_multiple_drivers_i; // problematic in any state
        end
    end

    // hardwired outputs

    // state updates and Moore outputs
    always @(*)
    begin
        // default assignments for the RESET state
        next_state = STATE_RESET;

        pcs_wen_o       = 0;
        pcs_bus_en_o    = 0;
        pc_src_o        = PC_SRC_BUS;
        pc_clear_lsb_o  = 0;
        pc_wen_o        = 0;
        pc_bus_en_o     = 0;
        gpr_wen_o       = 0;
        gpr_addr_o      = 5'b0;
        gpr_bus_en_o    = 0;
        ir_wen_o        = 0;
        imm_sel_o       = 3'b0;
        imm_bus_en_o    = 0;
        a_wen_o         = 0;
        b_wen_o         = 0;
        alu_op_o        = 4'b0;
        alu_bus_en_o    = 0;
        mar_wen_o       = 0;
        mdr_wen_o       = 0;
        mdr_src_o       = MDR_SRC_BUS;
        mdr_bus_en_o    = 0;
        mem_req_o       = 0;
        mem_wen_o       = 0;
        mem_width_o     = funct3;
        br_cond_o       = funct3;

        case(state)
            /************************************************************************
             * RESET
             ************************************************************************/
            STATE_RESET:
            begin
                next_state = STATE_FETCH_0;
            end

            /************************************************************************
             * FETCH
             ************************************************************************/
            STATE_FETCH_0:
            begin
                next_state = STATE_FETCH_1;

                `MAR_eq_PC;
                `PC_eq_BUS_plus_4;
                `PCS_eq_BUS;
            end

            STATE_FETCH_1:
            begin
                next_state = mem_valid_i ? STATE_FETCH_2 : STATE_FETCH_1;

                `MDR_eq_MEM_WORD_at_MAR;
            end

            STATE_FETCH_2:
            begin
                next_state = 
                    is_op ? STATE_ALU_RTYPE_0 :
                    is_op_imm ? STATE_ALU_ITYPE_0 :
                    is_jalr ? STATE_JALR_0 :
                    is_load ? STATE_LOAD_0 :
                    is_system ? STATE_SYSTEM :
                    is_store ? STATE_STORE_0 :
                    is_branch ? STATE_BRANCH_0 :
                    is_lui ? STATE_LUI :
                    is_auipc ? STATE_AUIPC_0 :
                    is_jal ? STATE_JAL_0 :
                    STATE_FETCH_2;

                `IR_eq_MDR;
            end

            /************************************************************************
             * STATE_ALU_RTYPE
             ************************************************************************/
            STATE_ALU_RTYPE_0:
            begin
                next_state = STATE_ALU_RTYPE_1;

                `A_eq_GPR_at_RS1;
            end

            STATE_ALU_RTYPE_1:
            begin
                next_state = STATE_ALU_RTYPE_2;
            
                `B_eq_GPR_at_RS2;
            end

            STATE_ALU_RTYPE_2:
            begin
                next_state = STATE_FETCH_0;
            
                `GPR_at_RD_eq_A_op_B;
            end

            /************************************************************************
             * STATE_ALU_ITYPE
             ************************************************************************/
            STATE_ALU_ITYPE_0:
            begin
                next_state = STATE_ALU_ITYPE_1;

                `A_eq_GPR_at_RS1;
            end

            STATE_ALU_ITYPE_1:
            begin
                next_state = STATE_ALU_ITYPE_2;
            
                `B_eq_SEXT_IMMI;
            end

            STATE_ALU_ITYPE_2:
            begin
                next_state = STATE_FETCH_0;
                
                `GPR_at_RD_eq_A_op_B;
            end

            /************************************************************************
             * STATE_JALR
             ************************************************************************/
            STATE_JALR_0:
            begin
                next_state = STATE_JALR_1;

                `A_eq_GPR_at_RS1;
            end

            STATE_JALR_1:
            begin
                next_state = STATE_JALR_2;
            
                `B_eq_SEXT_IMMI;
            end

            STATE_JALR_2:
            begin
                next_state = STATE_JALR_3;
            
                `GPR_at_RD_eq_PC;
            end

            STATE_JALR_3:
            begin
                next_state = STATE_FETCH_0;
            
                `PC_eq_A_plus_B_JALR;
            end

            /************************************************************************
             * STATE_LOAD
             ************************************************************************/
            STATE_LOAD_0:
            begin
                next_state = STATE_LOAD_1;

                `A_eq_GPR_at_RS1;
            end

            STATE_LOAD_1:
            begin
                next_state = STATE_LOAD_2;
            
                `B_eq_SEXT_IMMI;
            end

            STATE_LOAD_2:
            begin
                next_state = STATE_LOAD_3;
            
                `MAR_eq_A_plus_B;
            end

            STATE_LOAD_3:
            begin
                next_state =  mem_valid_i ? STATE_LOAD_4 : STATE_LOAD_3;
            
                `MDR_eq_MEM_LOAD_at_MAR;
            end

            STATE_LOAD_4:
            begin
                next_state = STATE_FETCH_0;
            
                `GPR_at_RD_eq_SEXT_MDR_FUNCT3;
            end

            /************************************************************************
             * STATE_SYSTEM
             ************************************************************************/
            STATE_SYSTEM:
            begin
                next_state = STATE_SYSTEM;
            end

            /************************************************************************
             * STATE_STORE
             ************************************************************************/
            STATE_STORE_0:
            begin
                next_state = STATE_STORE_1;

                `A_eq_GPR_at_RS1;
            end

            STATE_STORE_1:
            begin
                next_state = STATE_STORE_2;
            
                `B_eq_SEXT_IMMS;
            end

            STATE_STORE_2:
            begin
                next_state = STATE_STORE_3;
            
                `MAR_eq_A_plus_B;
            end

            STATE_STORE_3:
            begin
                next_state =  STATE_STORE_4;
            
                `MDR_eq_GPR_at_RS2;
            end

            STATE_STORE_4:
            begin
                next_state = mem_valid_i ? STATE_FETCH_0 : STATE_STORE_4;
            
                `MEM_at_MAR_eq_MDR;
            end

            /************************************************************************
             * STATE_BRANCH
             ************************************************************************/
            STATE_BRANCH_0:
            begin
                next_state = STATE_BRANCH_1;

                `A_eq_GPR_at_RS1;
            end

            STATE_BRANCH_1:
            begin
                next_state = br_taken_i ? STATE_BRANCH_2 : STATE_FETCH_0;
            
                `BUS_eq_GPR_at_RS2;
            end

            STATE_BRANCH_2:
            begin
                next_state = STATE_BRANCH_3;
            
                `A_eq_PCS;
            end

            STATE_BRANCH_3:
            begin
                next_state =  STATE_BRANCH_4;
            
                `B_eq_SEXT_IMMB;
            end

            STATE_BRANCH_4:
            begin
                next_state = STATE_FETCH_0;
            
                `PC_eq_A_plus_B;
            end

            /************************************************************************
             * STATE_LUI
             ************************************************************************/
            STATE_LUI:
            begin
                next_state = STATE_FETCH_0;
            
                `GPR_at_RD_eq_SEXT_IMMU;
            end

            /************************************************************************
             * STATE_AUIPC
             ************************************************************************/
            STATE_AUIPC_0:
            begin
                next_state = STATE_AUIPC_1;

                `A_eq_PCS;
            end

            STATE_AUIPC_1:
            begin
                next_state = STATE_AUIPC_2;
            
                `B_eq_SEXT_IMMU;
            end

            STATE_AUIPC_2:
            begin
                next_state = STATE_FETCH_0;
            
                `GPR_at_RD_eq_A_plus_B;
            end

            /************************************************************************
             * STATE_JAL
             ************************************************************************/
            STATE_JAL_0:
            begin
                next_state = STATE_JAL_1;

                `A_eq_PCS;
            end

            STATE_JAL_1:
            begin
                next_state = STATE_JAL_2;
            
                `B_eq_SEXT_IMMJ;
            end

            STATE_JAL_2:
            begin
                next_state = STATE_JAL_3;
            
                `GPR_at_RD_eq_PC;
            end

            STATE_JAL_3:
            begin
                next_state = STATE_FETCH_0;
            
                `PC_eq_A_plus_B;
            end

            default:
            begin 
                next_state = STATE_RESET;
            end
        endcase    
    end
endmodule

module rv32i_multi_cycle_mem_sext
(
    input  [31:0] rd_data_i,
    input  [2:0]  mem_width_i,

    output reg [31:0] extended_data_o
);
    always @(*)
    begin
        case (mem_width_i)
            MEM_WIDTH_LB:  extended_data_o = {{24{rd_data_i[7]}}, rd_data_i[7:0]};    
            MEM_WIDTH_LH:  extended_data_o = {{16{rd_data_i[15]}}, rd_data_i[15:0]};
            MEM_WIDTH_LW:  extended_data_o = rd_data_i;
            MEM_WIDTH_LBU: extended_data_o = {24'h000000, rd_data_i[7:0]};
            MEM_WIDTH_LHU: extended_data_o = {16'h0000, rd_data_i[15:0]};
            default:       extended_data_o = rd_data_i; 
        endcase
    end
endmodule


// the CPU module just runs code. checking memory bounds and applying address
// space offsets is done externally (ideally by the system bus, for example)
// no parameters bc the netlist cannot be parameterized
module rv32i_multi_cycle_single_bus
(
    input clock_i,
    input reset_ni,

    // CPU state and exceptions
    output    [31:0] exception_vector_o,

    // mem interface
    output [31:0] mem_addr_o,
    input  [31:0] mem_rdata_i,
    output [31:0] mem_wdata_o,
    output  [3:0] mem_wstrb_o,
    output        mem_wen_o,

    output        mem_req_o,
    input         mem_valid_i,
    input         mem_err_i
);

    /* state registers */
    reg  [31:0] pcs;
    reg  [31:0] pc;
    reg  [31:0] ir;
    reg  [31:0] A;
    reg  [31:0] B;
    reg  [31:0] mdr;
    reg  [31:0] mar;

    /* bus-inputs */        
    wire [31:0] immgen_o_imm;
    wire [31:0] alu_o_out;
    wire [31:0] gpr_o_rdata;
    wire [31:0] mem_sext_o_extended_data;

    /* bus-outputs */        
    wire [31:0] barb_o_bus;
    wire        barb_o_bus_fault_multiple_drivers;

    rv32i_multi_cycle_bus_arbiter bus_arbiter
    (
        .pcs_bus_en_i(ctl_o_pcs_bus_en),
        .pcs_i(pcs),

        .pc_bus_en_i(ctl_o_pc_bus_en),
        .pc_i(pc),

        .imm_bus_en_i(ctl_o_imm_bus_en),
        .imm_i(immgen_o_imm),

        .alu_bus_en_i(ctl_o_alu_bus_en),
        .alu_i(alu_o_out),

        .gpr_bus_en_i(ctl_o_gpr_bus_en),
        .gpr_i(gpr_o_rdata),

        .mdr_bus_en_i(ctl_o_mdr_bus_en),
        .mdr_i(mem_sext_o_extended_data),
        
        .bus_o(barb_o_bus),
        .bus_fault_multiple_drivers_o(barb_o_bus_fault_multiple_drivers)
    );

    /* control logic outputs */    
    wire        ctl_o_pcs_wen;
    wire        ctl_o_pcs_bus_en;
    wire        ctl_o_pc_src;
    wire        ctl_o_pc_clear_lsb;
    wire        ctl_o_pc_wen;
    wire        ctl_o_pc_bus_en;
    wire        ctl_o_gpr_wen;
    wire  [4:0] ctl_o_gpr_addr;
    wire        ctl_o_gpr_bus_en;
    wire        ctl_o_ir_wen;
    wire  [2:0] ctl_o_imm_sel;
    wire        ctl_o_imm_bus_en;
    wire        ctl_o_a_wen;
    wire        ctl_o_b_wen;
    wire  [3:0] ctl_o_alu_op;
    wire        ctl_o_alu_bus_en;
    wire        ctl_o_mar_wen;
    wire        ctl_o_mdr_wen;
    wire        ctl_o_mdr_src;
    wire        ctl_o_mdr_bus_en;
    wire  [2:0] ctl_o_br_cond;

    wire        ctl_o_mem_req;
    wire        ctl_o_mem_wen;
    wire  [2:0] ctl_o_mem_width;

    /* branch comparator outputs */
    wire        brc_o_br_taken;
    
    /* mem aligner + sign extender */
    wire [31:0] malign_o_rd_data_o;

    /* source muxes */
    wire [31:0] pc_src_raw = ctl_o_pc_src == PC_SRC_BUS ? barb_o_bus : barb_o_bus + 32'h4;
    wire [31:0] pc_src = ctl_o_pc_clear_lsb ? {pc_src_raw[31:1], 1'b0} : pc_src_raw;
    wire [31:0] mdr_src = ctl_o_mdr_src == MDR_SRC_BUS ? barb_o_bus : malign_o_rd_data_o;

    always @(posedge clock_i)
    begin
        if(reset_ni)
        begin
            if(ctl_o_pcs_wen) pcs <= barb_o_bus;
            if(ctl_o_pc_wen)  pc  <= pc_src;
            if(ctl_o_ir_wen)  ir  <= barb_o_bus;
            if(ctl_o_a_wen)   A   <= barb_o_bus;
            if(ctl_o_b_wen)   B   <= barb_o_bus;
            if(ctl_o_mar_wen) mar <= barb_o_bus;
            if(ctl_o_mdr_wen) mdr <= mdr_src;
        end
        else
        begin
            pcs <= 32'b0;
            pc  <= RESET_VECTOR;
            ir  <= 32'b0;
            A   <= 32'b0;
            B   <= 32'b0;
            mar <= 32'b0;
            mdr <= 32'b0;
        end
    end

    /* control logic */
    rv32i_multi_cycle_control_logic control_logic
    (
        .clock_i(clock_i),
        .reset_ni(reset_ni),
        
        .pc_i(pc),
        .mdr_i(mdr),
        .ir_i(ir),
        .br_taken_i(brc_o_br_taken),
        
        .exception_vector_o(exception_vector_o),
        .bus_fault_multiple_drivers_i(barb_o_bus_fault_multiple_drivers),
        
        .pcs_wen_o(ctl_o_pcs_wen),
        .pcs_bus_en_o(ctl_o_pcs_bus_en),
        .pc_src_o(ctl_o_pc_src),
        .pc_clear_lsb_o(ctl_o_pc_clear_lsb),
        .pc_wen_o(ctl_o_pc_wen),
        .pc_bus_en_o(ctl_o_pc_bus_en),
        .gpr_wen_o(ctl_o_gpr_wen),
        .gpr_addr_o(ctl_o_gpr_addr),
        .gpr_bus_en_o(ctl_o_gpr_bus_en),
        .ir_wen_o(ctl_o_ir_wen),
        .imm_sel_o(ctl_o_imm_sel),
        .imm_bus_en_o(ctl_o_imm_bus_en),
        .a_wen_o(ctl_o_a_wen),
        .b_wen_o(ctl_o_b_wen),
        .alu_op_o(ctl_o_alu_op),
        .alu_bus_en_o(ctl_o_alu_bus_en),
        .mar_wen_o(ctl_o_mar_wen),
        .mdr_wen_o(ctl_o_mdr_wen),
        .mdr_src_o(ctl_o_mdr_src),
        .mdr_bus_en_o(ctl_o_mdr_bus_en),
        .br_cond_o(ctl_o_br_cond),

        .mem_req_o(ctl_o_mem_req),
        .mem_wen_o(ctl_o_mem_wen),
        .mem_width_o(ctl_o_mem_width),
        .mem_valid_i(mem_valid_i),
        .mem_bus_err_i(mem_err_i)
    );

    /* immediate generation */
    rv32i_immgen immgen
    (
        .inst_i(ir),
        .imm_type_i(ctl_o_imm_sel),
        .imm_o(immgen_o_imm)
    );

    /* GPRs */
    wire [31:0] gpr_o_rdata_raw;
    assign gpr_o_rdata = (ctl_o_gpr_addr == 5'd0) ? 32'b0 : gpr_o_rdata_raw;

    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) 
        begin
            mem_1rw_asyncr_syncw_8bit 
            #(
                .MEM_SIZE_BYTES(32), // 32 registers total
                .INIT_FILENAME("")   // no initialization
            ) 
            gprs
            (
                .clock_i(clock_i),

                .rw0_addr_i(ctl_o_gpr_addr),
                .rw0_rdata_o(gpr_o_rdata_raw[i*8+7:i*8]),
                .rw0_wdata_i(barb_o_bus[i*8+7:i*8]),
                .rw0_wen_i(ctl_o_gpr_wen && (ctl_o_gpr_addr != 5'd0))
            );
        end
    endgenerate

    /* alu */
    rv32i_alu alu
    (
        .a_i(A),
        .b_i(B),
        .alu_op_i(ctl_o_alu_op),

        .out_o(alu_o_out)
    );

    /* branch comparator */
    rv32i_branch_comparator br_comp
    (
        .rs1_data_i(A),
        .rs2_data_i(barb_o_bus),
        .cond_i(ctl_o_br_cond),	

        .taken_o(brc_o_br_taken)
    );

    /* memory sign extender */
    rv32i_multi_cycle_mem_sext mem_sext
    (
        .rd_data_i(mdr),
        .mem_width_i(ctl_o_mem_width),

        .extended_data_o(mem_sext_o_extended_data)
    );

    /* DMEM address aligner */
    wire [31:0] dmem_aligner_o_mem_addr;
    wire [31:0] dmem_aligner_o_wdata;
    wire [3:0] dmem_aligner_o_wstrb;
    rv32i_single_cycle_dmem_aligner dmem_aligner
    (
        .byte_addr_i(mar),
        .byte_addr_o(dmem_aligner_o_mem_addr),

        .mem_width_i(ctl_o_mem_width),

        .rd_data_raw_i(mem_rdata_i),
        .rd_data_o(malign_o_rd_data_o), // rotated (so the byte/half is in the LSB position in the data) and sexted

        .raw_wr_data_i(mdr),
        .wr_data_o(dmem_aligner_o_wdata), // set up so that wstrb will do the right thing
        .wstrb_o(dmem_aligner_o_wstrb)
    );

    /* memory */
    assign mem_req_o = ctl_o_mem_req;
    assign mem_addr_o = dmem_aligner_o_mem_addr;
    assign mem_wdata_o = dmem_aligner_o_wdata;
    assign mem_wstrb_o = dmem_aligner_o_wstrb;
    assign mem_wen_o = ctl_o_mem_wen;
endmodule
