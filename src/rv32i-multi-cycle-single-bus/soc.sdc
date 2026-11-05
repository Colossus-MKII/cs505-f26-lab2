create_clock -name clk -period ${CLOCK_PERIOD} {clock_i}

set_input_delay 0.0 -clock clk {reset_ni}

set_output_delay 0.0 -clock clk [get_ports cpu_exception_o]
set_output_delay 0.0 -clock clk [get_ports cpu_exception_vector_o]

set_input_delay 0.0 -clock clk [get_ports io_addr_i]
set_input_delay 0.0 -clock clk [get_ports io_data_i]
set_output_delay 0.0 -clock clk [get_ports io_data_o]
set_input_delay 0.0 -clock clk [get_ports io_wen_i]
set_output_delay 0.0 -clock clk [get_ports io_wen_o]
set_input_delay 0.0 -clock clk [get_ports io_req_i]
set_output_delay 0.0 -clock clk [get_ports io_valid_o]
set_output_delay 0.0 -clock clk [get_ports io_err_o]
