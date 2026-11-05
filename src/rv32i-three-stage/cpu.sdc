create_clock -name clk -period ${CLOCK_PERIOD} {clock_i}

set_input_delay 0.0 -clock clk {reset_ni}

set_output_delay 0.0 -clock clk [get_ports exception_vector_o]

set_input_delay 0.0 -clock clk [get_ports imem_data_i]
set_input_delay 0.0 -clock clk [get_ports imem_valid_i]
set_input_delay 0.0 -clock clk [get_ports imem_err_i]
set_output_delay 0.0 -clock clk [get_ports imem_addr_o]
set_output_delay 0.0 -clock clk [get_ports imem_req_o]

set_input_delay 0.0 -clock clk [get_ports dmem_rdata_i]
set_input_delay 0.0 -clock clk [get_ports dmem_valid_i]
set_input_delay 0.0 -clock clk [get_ports dmem_err_i]
set_output_delay 0.0 -clock clk [get_ports dmem_addr_o]
set_output_delay 0.0 -clock clk [get_ports dmem_wdata_o]
set_output_delay 0.0 -clock clk [get_ports dmem_wstrb_o]
set_output_delay 0.0 -clock clk [get_ports dmem_wen_o]
set_output_delay 0.0 -clock clk [get_ports dmem_req_o]
