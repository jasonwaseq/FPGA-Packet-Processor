`timescale 1ns/1ps

module dut_uart_loopback (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_data_i,
    input  logic       tx_valid_i,
    output logic       tx_ready_o,
    output logic [7:0] rx_data_o,
    output logic       rx_valid_o,
    output logic       frame_error_o
);
    logic serial_w;

    uart_tx #(.CLKS_PER_BIT(8)) u_tx (
        .clk(clk),
        .rst_n(rst_n),
        .data_i(tx_data_i),
        .valid_i(tx_valid_i),
        .ready_o(tx_ready_o),
        .tx_o(serial_w)
    );

    uart_rx #(.CLKS_PER_BIT(8)) u_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx_i(serial_w),
        .data_o(rx_data_o),
        .valid_o(rx_valid_o),
        .frame_error_o(frame_error_o)
    );
endmodule
