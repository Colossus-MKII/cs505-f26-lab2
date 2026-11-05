`ifndef RV32I__SINGLE_CYCLE__PARAMS_VH
`define RV32I__SINGLE_CYCLE__PARAMS_VH

/*
 * mux select signals 
 */
// PC mux
localparam PC_MUX_PCPLUS4 = 1'b0;
localparam PC_MUX_ALU     = 1'b1;

// A select
localparam ASEL_MUX_RS1 = 1'b0;
localparam ASEL_MUX_PC  = 1'b1;

// B select
localparam BSEL_MUX_RS2 = 1'b0;
localparam BSEL_MUX_IMM = 1'b1;

// writeback mux
localparam [1:0] WB_MUX_ALU_RESULT = 2'd0;
localparam [1:0] WB_MUX_MEM_DATA   = 2'd1;
localparam [1:0] WB_MUX_IMMEDIATE  = 2'd2;
localparam [1:0] WB_MUX_PC_PLUS4   = 2'd3;

/*
 * Exceptions
 */
localparam integer EXCEPTION_ECALL = 0;
localparam integer EXCEPTION_EBREAK = 1;
localparam integer EXCEPTION_ILLEGAL_INSTRUCTION = 2;
localparam integer EXCEPTION_IMEM_MISALIGNMENT = 3;
localparam integer EXCEPTION_IMEM_BUS_ERROR = 4;
localparam integer EXCEPTION_DMEM_BUS_ERROR = 5;

`endif /* RV32I__SINGLE_CYCLE__PARAMS_VH */
