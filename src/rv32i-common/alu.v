`include "src/rv32i-common/params.vh"

`define SHIFT_TYPE_ARITHMETIC 1'b0
`define SHIFT_TYPE_LOGICAL 1'b1

`define SHIFT_DIRECTION_RIGHT 1'b0
`define SHIFT_DIRECTION_LEFT 1'b1

module rv32i_barrel_shifter
(
    input [31:0] in_i,
    input [4:0] shamt_i,
    input       shift_type_i,
    input       direction_i,
    output [31:0] out_o
);
    // 32-bit arithmetic barrel shifter
    wire [31:0] stage0;
    wire [31:0] stage1;
    wire [31:0] stage2;
    wire [31:0] stage3;
    
    wire [31:0] in_reversed;
    wire [31:0] out_reversed;
    wire [31:0] data_in;
    wire [31:0] data_out;
    
    genvar i;
    generate
        for (i = 0; i < 32; i = i + 1) 
        begin : gen_reverse
            assign in_reversed[i] = in_i[31 - i];
            assign out_reversed[i] = data_out[31 - i];
        end
    endgenerate

    // shifting logic
    wire msb = (shift_type_i == `SHIFT_TYPE_ARITHMETIC) ? in_i[31] : 1'b0;
    assign data_in = (direction_i == `SHIFT_DIRECTION_RIGHT) ? in_i : in_reversed;

    assign stage0   = shamt_i[0] ? {{1{msb}},  data_in[31:1]} : data_in;
    assign stage1   = shamt_i[1] ? {{2{msb}},  stage0[31:2]}  : stage0;
    assign stage2   = shamt_i[2] ? {{4{msb}},  stage1[31:4]}  : stage1;
    assign stage3   = shamt_i[3] ? {{8{msb}},  stage2[31:8]}  : stage2;
    assign data_out = shamt_i[4] ? {{16{msb}}, stage3[31:16]} : stage3;

    assign out_o = (direction_i == `SHIFT_DIRECTION_RIGHT) ? data_out : out_reversed;
endmodule

module rv32i_alu
(
    input  [31:0] a_i,
    input  [31:0] b_i,
    input   [3:0] alu_op_i,	

    output reg [31:0] out_o
);
    reg         shifter_i_type;
    reg         shifter_i_direction;
    wire [31:0] shifter_o_out;
    always @(*) 
    begin
        shifter_i_type = `SHIFT_TYPE_LOGICAL;
        shifter_i_direction = `SHIFT_DIRECTION_RIGHT;

        case(alu_op_i)
            ALU_OP_ADD:  out_o = a_i + b_i;
            ALU_OP_SLL:  
            begin
                out_o =  shifter_o_out;
                shifter_i_direction = `SHIFT_DIRECTION_LEFT;
            end
            ALU_OP_SLT:  out_o = ($signed(a_i) < $signed(b_i)) ? 32'd1 : 32'd0;
            ALU_OP_SLTU: out_o = (a_i < b_i) ? 32'd1 : 32'd0;
            ALU_OP_XOR:  out_o = a_i ^ b_i;
            ALU_OP_SRL:  out_o = shifter_o_out;
            ALU_OP_OR:   out_o = a_i | b_i;
            ALU_OP_AND:  out_o = a_i & b_i;
            ALU_OP_SUB:  out_o = a_i - b_i;
            ALU_OP_SRA:  
            begin
                out_o = shifter_o_out;
                shifter_i_type = `SHIFT_TYPE_ARITHMETIC;
            end
            default:     out_o = 32'b0;
        endcase
    end

    // avoid using signed/unsigned datatypes; yosys emits them into the netlist
    rv32i_barrel_shifter shifter
    (
        .in_i(a_i),
        .shamt_i(b_i[4:0]),
        .shift_type_i(shifter_i_type),
        .direction_i(shifter_i_direction),
        .out_o(shifter_o_out)
    );
endmodule
