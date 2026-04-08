module icebreaker_uart_tx_test_top #(
    parameter int unsigned UART_CLKS_PER_BIT = 104
) (
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic uart_rx_i,
    output logic uart_tx_o
);
    logic [7:0] tx_data_q;
    logic       tx_valid_q;
    logic       tx_ready;

    uart_tx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart_tx (
        .clk(clk_i),
        .rst_n(1'b1),
        .data_i(tx_data_q),
        .valid_i(tx_valid_q),
        .ready_o(tx_ready),
        .tx_o(uart_tx_o)
    );

    always_ff @(posedge clk_i) begin
        tx_valid_q <= 1'b0;
        if (tx_ready) begin
            tx_data_q  <= 8'h55;
            tx_valid_q <= 1'b1;
        end
    end

    logic unused_signals;
    assign unused_signals = rst_n_i ^ uart_rx_i;
endmodule
