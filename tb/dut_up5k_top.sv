`timescale 1ns/1ps

module dut_up5k_top (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       uart_rx_i,
    output logic       uart_tx_o,
    output logic [7:0] tx_data_o,
    output logic       tx_valid_o,
    output logic       tx_frame_error_o
);
    localparam int unsigned UART_CLKS_PER_BIT = 104;

    packet_processor_up5k_top u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o)
    );

    uart_rx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_tx_monitor (
        .clk(clk),
        .rst_n(rst_n),
        .rx_i(uart_tx_o),
        .data_o(tx_data_o),
        .valid_o(tx_valid_o),
        .frame_error_o(tx_frame_error_o)
    );
endmodule
