module uart_tx #(
    parameter int unsigned CLKS_PER_BIT = 8
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] data_i,
    input  logic       valid_i,
    output logic       ready_o,
    output logic       tx_o
);
    localparam int unsigned CTR_W = (CLKS_PER_BIT <= 2) ? 1 : $clog2(CLKS_PER_BIT);
    localparam int unsigned BIT_W = 3;

    typedef enum logic [1:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_STOP
    } tx_state_t;

    tx_state_t state_q;
    logic [CTR_W-1:0] clk_ctr_q;
    logic [BIT_W-1:0] bit_ctr_q;
    logic [7:0]       shift_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q   <= TX_IDLE;
            clk_ctr_q <= '0;
            bit_ctr_q <= '0;
            shift_q   <= '0;
            ready_o   <= 1'b1;
            tx_o      <= 1'b1;
        end else begin
            case (state_q)
                TX_IDLE: begin
                    ready_o <= 1'b1;
                    tx_o    <= 1'b1;
                    if (valid_i) begin
                        shift_q   <= data_i;
                        clk_ctr_q <= CLKS_PER_BIT - 1;
                        bit_ctr_q <= '0;
                        ready_o   <= 1'b0;
                        tx_o      <= 1'b0;
                        state_q   <= TX_START;
                    end
                end

                TX_START: begin
                    if (clk_ctr_q == 0) begin
                        clk_ctr_q <= CLKS_PER_BIT - 1;
                        tx_o      <= shift_q[0];
                        state_q   <= TX_DATA;
                    end else begin
                        clk_ctr_q <= clk_ctr_q - 1'b1;
                    end
                end

                TX_DATA: begin
                    if (clk_ctr_q == 0) begin
                        clk_ctr_q <= CLKS_PER_BIT - 1;
                        if (bit_ctr_q == 3'd7) begin
                            tx_o    <= 1'b1;
                            state_q <= TX_STOP;
                        end else begin
                            bit_ctr_q <= bit_ctr_q + 1'b1;
                            tx_o      <= shift_q[bit_ctr_q + 1'b1];
                        end
                    end else begin
                        clk_ctr_q <= clk_ctr_q - 1'b1;
                    end
                end

                TX_STOP: begin
                    if (clk_ctr_q == 0) begin
                        state_q <= TX_IDLE;
                    end else begin
                        clk_ctr_q <= clk_ctr_q - 1'b1;
                    end
                end

                default: state_q <= TX_IDLE;
            endcase
        end
    end
endmodule
