create_clock -name clk -period ${CLOCK_PERIOD} {clock_i}

set_input_delay 0.0 -clock clk {reset_ni}

set_output_delay 0.0 -clock clk [get_ports exception_vector_o]

set_output_delay 0.0 -clock clk [get_ports mem_addr_o]
set_input_delay 0.0 -clock clk [get_ports mem_rdata_i]
set_output_delay 0.0 -clock clk [get_ports mem_wdata_o]
set_output_delay 0.0 -clock clk [get_ports mem_wstrb_o]
set_output_delay 0.0 -clock clk [get_ports mem_wen_o]

set_output_delay 0.0 -clock clk [get_ports mem_req_o]
set_input_delay 0.0 -clock clk [get_ports mem_valid_i]
set_input_delay 0.0 -clock clk [get_ports mem_err_i]