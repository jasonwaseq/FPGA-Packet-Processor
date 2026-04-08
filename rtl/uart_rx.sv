module uart_rx #(
    parameter int unsigned CLKS_PER_BIT = 8
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rx_i,
    output logic [7:0] data_o,
    output logic       valid_o,
    output logic       frame_error_o
);
    localparam int unsigned CTR_W = (CLKS_PER_BIT <= 2) ? 1 : $clog2(CLKS_PER_BIT);
    localparam int unsigned BIT_W = 3;

    typedef enum logic [1:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_STOP
    } rx_state_t;

    rx_state_t state_q;
    logic [CTR_W-1:0] clk_ctr_q;
    logic [BIT_W-1:0] bit_ctr_q;
    logic [7:0]       shift_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q       <= RX_IDLE;
            clk_ctr_q     <= '0;
            bit_ctr_q     <= '0;
            shift_q       <= '0;
            data_o        <= '0;
            valid_o       <= 1'b0;
            frame_error_o <= 1'b0;
        end else begin
            valid_o       <= 1'b0;
            frame_error_o <= 1'b0;

            case (state_q)
                RX_IDLE: begin
                    clk_ctr_q <= '0;
                    bit_ctr_q <= '0;
                    if (!rx_i) begin
                        state_q   <= RX_START;
                        clk_ctr_q <= CLKS_PER_BIT[CTR_W-1:0] >> 1;
                    end
                end

                RX_START: begin
                    if (clk_ctr_q == 0) begin
                        if (!rx_i) begin
                            state_q   <= RX_DATA;
                            clk_ctr_q <= CLKS_PER_BIT - 1;
                            bit_ctr_q <= '0;
                        end else begin
                            state_q <= RX_IDLE;
                        end
                    end else begin
                        clk_ctr_q <= clk_ctr_q - 1'b1;
                    end
                end

                RX_DATA: begin
                    if (clk_ctr_q == 0) begin
                        shift_q[bit_ctr_q] <= rx_i;
                        clk_ctr_q <= CLKS_PER_BIT - 1;
                        if (bit_ctr_q == 3'd7) begin
                            state_q <= RX_STOP;
                        end
                        bit_ctr_q <= bit_ctr_q + 1'b1;
                    end else begin
                        clk_ctr_q <= clk_ctr_q - 1'b1;
                    end
                end

                RX_STOP: begin
                    if (clk_ctr_q == 0) begin
                        data_o  <= shift_q;
                        valid_o <= rx_i;
                        frame_error_o <= !rx_i;
                        state_q <= RX_IDLE;
                    end else begin
                        clk_ctr_q <= clk_ctr_q - 1'b1;
                    end
                end

                default: state_q <= RX_IDLE;
            endcase
        end
    end
endmodule
