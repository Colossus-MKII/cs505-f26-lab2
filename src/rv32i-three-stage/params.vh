`ifndef RV32I_THREE_STAGE__PARAMS_VH
`define RV32I_THREE_STAGE__PARAMS_VH

localparam integer EXCEPTION_ECALL = 0;
localparam integer EXCEPTION_EBREAK = 1;
localparam integer EXCEPTION_ILLEGAL_INSTRUCTION = 2;
localparam integer EXCEPTION_IMEM_MISALIGNMENT = 3;
localparam integer EXCEPTION_IMEM_BUS_ERROR = 4;
localparam integer EXCEPTION_DMEM_BUS_ERROR = 5;

localparam [1:0] PC_SEL_SEQUENTIAL = 2'd0;
localparam [1:0] PC_SEL_BRANCH    = 2'd1;
localparam [1:0] PC_SEL_JALR      = 2'd2;

localparam ASEL_MUX_RS1 = 1'b0;
localparam ASEL_MUX_PC  = 1'b1;
localparam BSEL_MUX_RS2 = 1'b0;
localparam BSEL_MUX_IMM = 1'b1;

localparam [1:0] WB_MUX_ALU_RESULT = 2'd0;
localparam [1:0] WB_MUX_MEM_DATA   = 2'd1;
localparam [1:0] WB_MUX_IMMEDIATE  = 2'd2;
localparam [1:0] WB_MUX_PC_PLUS4   = 2'd3;

`endif /* RV32I_THREE_STAGE__PARAMS_VH */
