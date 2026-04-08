module rule_table #(
    parameter int unsigned RULE_COUNT = packet_processor_pkg::RULE_COUNT,
    parameter int unsigned RULE_IMAGE_W = packet_processor_pkg::RULE_IMAGE_W
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       write_valid_i,
    input  logic [2:0] write_index_i,
    input  logic [RULE_IMAGE_W-1:0] write_rule_i,
    input  logic       clear_rule_i,
    input  logic [2:0] clear_rule_index_i,
    input  logic       clear_all_i,
    input  logic [2:0] lookup_index_i,
    output logic [RULE_IMAGE_W-1:0] lookup_rule_o,
    input  logic [2:0] read_index_i,
    output logic [RULE_IMAGE_W-1:0] read_rule_o
);

    logic [RULE_IMAGE_W-1:0] rules_q [0:RULE_COUNT-1];
    integer idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx = 0; idx < RULE_COUNT; idx++) begin
                rules_q[idx] <= '0;
            end
        end else begin
            if (clear_all_i) begin
                for (idx = 0; idx < RULE_COUNT; idx++) begin
                    rules_q[idx] <= '0;
                end
            end
            if (clear_rule_i) begin
                rules_q[clear_rule_index_i] <= '0;
            end
            if (write_valid_i) begin
                rules_q[write_index_i] <= write_rule_i;
            end
        end
    end

    assign lookup_rule_o = rules_q[lookup_index_i];
    assign read_rule_o   = rules_q[read_index_i];
endmodule
