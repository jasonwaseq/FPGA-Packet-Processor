module icebreaker_bringup_top #(
    parameter int unsigned UART_CLKS_PER_BIT = 104
) (
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic uart_rx_i,
    output logic uart_tx_o
);
    // Minimal electrical loopback for hardware bring-up validation.
    // This bypasses UART decoding/encoding so failures are easier to localize.
    assign uart_tx_o = uart_rx_i;

    // Keep these ports for a shared top-level pinout.
    logic unused_signals;
    assign unused_signals = clk_i ^ rst_n_i ^ UART_CLKS_PER_BIT[0];
endmodule
