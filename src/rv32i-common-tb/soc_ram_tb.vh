`timescale 1ns/1ps
module tb_ram;
    `include "src/rv32i-common-tb/soc_tb_io.vh"

    integer byte_offset;

    // Exercise host RAM access with the CPU held in reset; no software needed.
    initial begin : ram_test
        start_waveform;
        repeat (5) @(negedge clock_i);

        // Nonsequential writes cover each lane and a single-byte overwrite.
        write_byte(3, 8'h44);
        write_byte(0, 8'h11);
        write_byte(2, 8'h33);
        write_byte(1, 8'h22);
        write_byte(1, 8'ha5);
        check_byte(0, 8'h11);
        check_byte(1, 8'ha5);
        check_byte(2, 8'h33);
        check_byte(3, 8'h44);

        // Rejected accesses must not alias the first or last valid byte.
        write_byte(RAM_SIZE_BYTES - 1, 8'he7);
        if (RAM_SIZE_BYTES < HOST_ADDRESS_SPACE_BYTES) begin
            check_invalid_address(HOST_ADDRESS_SPACE_BYTES - 1, 8'h5a);
            check_invalid_address(RAM_SIZE_BYTES, 8'h77);
        end
        check_byte(0, 8'h11);
        check_byte(RAM_SIZE_BYTES - 1, 8'he7);

        // Cover every byte, including address bits above the low byte.
        for (byte_offset = 0; byte_offset < RAM_SIZE_BYTES; byte_offset = byte_offset + 1)
            write_byte(byte_offset, byte_offset[7:0] ^ byte_offset[15:8] ^ 8'ha5);
        for (byte_offset = 0; byte_offset < RAM_SIZE_BYTES; byte_offset = byte_offset + 1)
            check_byte(byte_offset, byte_offset[7:0] ^ byte_offset[15:8] ^ 8'ha5);
        report_result(1, TB_RESULT_OK);
    end

    task check_byte(input [31:0] address, input [7:0] expected);
        reg [7:0] actual;
        begin
            host_access(0, address, 0, 0, actual);
            if (actual !== expected) begin
                $display("[FAIL] RAM addr=%h expected=%h actual=%h", address, expected, actual);
                report_result(0, SOC_ERR_RAM_DATA_MISMATCH);
            end
        end
    endtask

    task check_invalid_address(input [31:0] address, input [7:0] write_data);
        reg [7:0] unused_read_data;
        begin
            host_access(1, address, write_data, 1, unused_read_data);
            host_access(0, address, 0, 1, unused_read_data);
        end
    endtask
endmodule
