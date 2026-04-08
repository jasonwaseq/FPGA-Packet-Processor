module classifier_engine #(
    parameter int unsigned RULE_COUNT = packet_processor_pkg::RULE_COUNT
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start_i,
    input  logic [7:0] protocol_i,
    input  logic [15:0] src_addr_i,
    input  logic [15:0] dst_addr_i,
    input  logic [15:0] src_port_i,
    input  logic [15:0] dst_port_i,
    output logic [2:0] lookup_index_o,
    input  logic [packet_processor_pkg::RULE_IMAGE_W-1:0] lookup_rule_i,
    input  logic [7:0] default_action_i,
    output logic       done_o,
    output logic       matched_o,
    output logic [2:0] matched_rule_o,
    output logic [7:0] action_o,
    output logic [3:0] rewrite_en_o,
    output logic [7:0] rewrite_flags_o,
    output logic [15:0] rewrite_dst_addr_o,
    output logic [15:0] rewrite_dst_port_o
);
    localparam int unsigned RULE_IMAGE_W = packet_processor_pkg::RULE_IMAGE_W;
    localparam logic [7:0] ACTION_DROP = packet_processor_pkg::ACTION_DROP;

    typedef enum logic [1:0] {
        CL_IDLE,
        CL_COMPARE,
        CL_DONE
    } cl_state_t;

    cl_state_t state_q;
    logic [2:0] rule_idx_q;
    logic       matched_q;
    logic [2:0] matched_rule_q;
    logic [7:0] action_q;
    logic [3:0] rewrite_en_q;
    logic [7:0] rewrite_flags_q;
    logic [15:0] rewrite_dst_addr_q;
    logic [15:0] rewrite_dst_port_q;

    logic        rule_valid;
    logic [4:0]  match_en;
    logic [7:0]  rule_action;
    logic [3:0]  rule_rewrite_en;
    logic [15:0] src_addr_value;
    logic [15:0] src_addr_mask;
    logic [15:0] dst_addr_value;
    logic [15:0] dst_addr_mask;
    logic [15:0] src_port_value;
    logic [15:0] dst_port_value;
    logic [7:0]  protocol_value;
    logic [7:0]  rewrite_flags_value;
    logic [15:0] rewrite_dst_addr_value;
    logic [15:0] rewrite_dst_port_value;
    logic [7:0]  rule_valid_byte;
    logic [7:0]  match_en_byte;
    logic [7:0]  rewrite_en_byte;
    logic        rule_hit;

    function automatic logic [7:0] rule_byte(input logic [RULE_IMAGE_W-1:0] rule, input int unsigned byte_idx);
        begin
            rule_byte = rule[(byte_idx * 8) +: 8];
        end
    endfunction

    function automatic logic [15:0] rule_be16(input logic [RULE_IMAGE_W-1:0] rule, input int unsigned byte_idx);
        begin
            rule_be16 = {rule_byte(rule, byte_idx), rule_byte(rule, byte_idx + 1)};
        end
    endfunction

    assign rule_valid_byte        = rule_byte(lookup_rule_i, 0);
    assign match_en_byte          = rule_byte(lookup_rule_i, 1);
    assign rewrite_en_byte        = rule_byte(lookup_rule_i, 3);
    assign rule_valid             = |rule_valid_byte;
    assign match_en               = match_en_byte[4:0];
    assign rule_action            = rule_byte(lookup_rule_i, 2);
    assign rule_rewrite_en        = rewrite_en_byte[3:0];
    assign src_addr_value         = rule_be16(lookup_rule_i, 4);
    assign src_addr_mask          = rule_be16(lookup_rule_i, 6);
    assign dst_addr_value         = rule_be16(lookup_rule_i, 8);
    assign dst_addr_mask          = rule_be16(lookup_rule_i, 10);
    assign src_port_value         = rule_be16(lookup_rule_i, 12);
    assign dst_port_value         = rule_be16(lookup_rule_i, 14);
    assign protocol_value         = rule_byte(lookup_rule_i, 16);
    assign rewrite_flags_value    = rule_byte(lookup_rule_i, 17);
    assign rewrite_dst_addr_value = rule_be16(lookup_rule_i, 18);
    assign rewrite_dst_port_value = rule_be16(lookup_rule_i, 20);

    assign rule_hit =
        rule_valid &&
        (!match_en[4] || (protocol_i == protocol_value)) &&
        (!match_en[3] || (dst_port_i == dst_port_value)) &&
        (!match_en[2] || (src_port_i == src_port_value)) &&
        (!match_en[1] || ((dst_addr_i & dst_addr_mask) == (dst_addr_value & dst_addr_mask))) &&
        (!match_en[0] || ((src_addr_i & src_addr_mask) == (src_addr_value & src_addr_mask)));

    assign lookup_index_o = rule_idx_q;
    assign done_o         = (state_q == CL_DONE);
    assign matched_o      = matched_q;
    assign matched_rule_o = matched_rule_q;
    assign action_o       = action_q;
    assign rewrite_en_o   = rewrite_en_q;
    assign rewrite_flags_o = rewrite_flags_q;
    assign rewrite_dst_addr_o = rewrite_dst_addr_q;
    assign rewrite_dst_port_o = rewrite_dst_port_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q             <= CL_IDLE;
            rule_idx_q          <= '0;
            matched_q           <= 1'b0;
            matched_rule_q      <= 3'h0;
            action_q            <= ACTION_DROP;
            rewrite_en_q        <= '0;
            rewrite_flags_q     <= '0;
            rewrite_dst_addr_q  <= '0;
            rewrite_dst_port_q  <= '0;
        end else begin
            case (state_q)
                CL_IDLE: begin
                    if (start_i) begin
                        rule_idx_q         <= '0;
                        matched_q          <= 1'b0;
                        matched_rule_q     <= 3'h0;
                        action_q           <= default_action_i;
                        rewrite_en_q       <= '0;
                        rewrite_flags_q    <= '0;
                        rewrite_dst_addr_q <= '0;
                        rewrite_dst_port_q <= '0;
                        state_q            <= CL_COMPARE;
                    end
                end

                CL_COMPARE: begin
                    if (rule_hit) begin
                        matched_q          <= 1'b1;
                        matched_rule_q     <= rule_idx_q;
                        action_q           <= rule_action;
                        rewrite_en_q       <= rule_rewrite_en;
                        rewrite_flags_q    <= rewrite_flags_value;
                        rewrite_dst_addr_q <= rewrite_dst_addr_value;
                        rewrite_dst_port_q <= rewrite_dst_port_value;
                        state_q            <= CL_DONE;
                    end else if (rule_idx_q == (RULE_COUNT - 1)) begin
                        state_q <= CL_DONE;
                    end else begin
                        rule_idx_q <= rule_idx_q + 1'b1;
                    end
                end

                CL_DONE: begin
                    state_q <= CL_IDLE;
                end

                default: state_q <= CL_IDLE;
            endcase
        end
    end
endmodule
