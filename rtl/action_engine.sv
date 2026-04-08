module action_engine #(
    parameter int unsigned MAX_PACKET_BYTES = packet_processor_pkg::MAX_PACKET_BYTES,
    parameter int unsigned MAX_FRAME_PAYLOAD = packet_processor_pkg::MAX_FRAME_PAYLOAD
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start_i,
    input  logic [7:0] seq_i,
    input  logic [7:0] mode_i,
    input  logic       verbose_i,
    input  logic [15:0] packet_len_i,
    input  logic [3:0] parse_error_i,
    input  logic       checksum_ok_i,
    input  logic       matched_i,
    input  logic [2:0] matched_rule_i,
    input  logic [7:0] action_i,
    input  logic [3:0] rewrite_en_i,
    input  logic [7:0] rewrite_flags_i,
    input  logic [15:0] rewrite_dst_addr_i,
    input  logic [15:0] rewrite_dst_port_i,
    input  logic [7:0] protocol_i,
    input  logic [7:0] flags_i,
    input  logic [7:0] ttl_i,
    input  logic [15:0] total_length_i,
    input  logic [15:0] payload_length_i,
    input  logic [15:0] src_addr_i,
    input  logic [15:0] dst_addr_i,
    input  logic [15:0] src_port_i,
    input  logic [15:0] dst_port_i,
    input  logic [15:0] packet_id_i,
    output logic       packet_read_start_o,
    input  logic [7:0] packet_data_i,
    input  logic       packet_valid_i,
    output logic       packet_ready_o,
    input  logic       packet_eop_i,
    output logic       result_valid_o,
    output logic [159:0] result_bytes_o,
    output logic       forward_valid_o,
    output logic [7:0] forward_seq_o,
    output logic [15:0] forward_len_o,
    output logic [(MAX_FRAME_PAYLOAD*8)-1:0] forward_payload_o,
    output logic       accepted_o,
    output logic       dropped_o,
    output logic       count_only_o,
    output logic       transformed_o,
    output logic       busy_o,
    output logic       done_o
);
    localparam int unsigned PACKET_HEADER_BYTES = packet_processor_pkg::PACKET_HEADER_BYTES;
    localparam logic [3:0] PARSE_ERR_NONE = packet_processor_pkg::PARSE_ERR_NONE;
    localparam logic [7:0] MODE_INSPECT = packet_processor_pkg::MODE_INSPECT;
    localparam logic [7:0] MODE_BENCHMARK = packet_processor_pkg::MODE_BENCHMARK;
    localparam logic [7:0] ACTION_DROP = packet_processor_pkg::ACTION_DROP;
    localparam logic [7:0] ACTION_ACCEPT = packet_processor_pkg::ACTION_ACCEPT;
    localparam logic [7:0] ACTION_COUNT_ONLY = packet_processor_pkg::ACTION_COUNT_ONLY;
    localparam logic [7:0] ACTION_REWRITE = packet_processor_pkg::ACTION_REWRITE;
    localparam logic [7:0] RESULT_FLAG_PARSE_OK = packet_processor_pkg::RESULT_FLAG_PARSE_OK;
    localparam logic [7:0] RESULT_FLAG_MATCHED = packet_processor_pkg::RESULT_FLAG_MATCHED;
    localparam logic [7:0] RESULT_FLAG_DROPPED = packet_processor_pkg::RESULT_FLAG_DROPPED;
    localparam logic [7:0] RESULT_FLAG_REWRITTEN = packet_processor_pkg::RESULT_FLAG_REWRITTEN;
    localparam logic [7:0] RESULT_FLAG_CHECKSUM_OK = packet_processor_pkg::RESULT_FLAG_CHECKSUM_OK;
    localparam logic [7:0] RESULT_FLAG_DEFAULT_ACTION = packet_processor_pkg::RESULT_FLAG_DEFAULT_ACTION;
    localparam logic [7:0] RESULT_FLAG_VERBOSE = packet_processor_pkg::RESULT_FLAG_VERBOSE;

    function automatic logic [15:0] ones_add16_local(
        input logic [15:0] a,
        input logic [15:0] b
    );
        logic [16:0] tmp;
        begin
            tmp = a + b;
            ones_add16_local = tmp[15:0] + tmp[16];
        end
    endfunction

    typedef enum logic [1:0] {
        ACT_IDLE,
        ACT_PREPARE,
        ACT_BUILD_FORWARD,
        ACT_DONE
    } act_state_t;

    function automatic logic [15:0] compute_checksum(
        input logic [7:0] b0,
        input logic [7:0] b1,
        input logic [7:0] b2,
        input logic [7:0] b3,
        input logic [15:0] total_length,
        input logic [15:0] payload_length,
        input logic [15:0] src_addr,
        input logic [15:0] dst_addr,
        input logic [15:0] src_port,
        input logic [15:0] dst_port,
        input logic [15:0] packet_id
    );
        logic [15:0] sum;
        begin
            sum = 16'h0000;
            sum = ones_add16_local(sum, {b0, b1});
            sum = ones_add16_local(sum, {b2, b3});
            sum = ones_add16_local(sum, total_length);
            sum = ones_add16_local(sum, payload_length);
            sum = ones_add16_local(sum, src_addr);
            sum = ones_add16_local(sum, dst_addr);
            sum = ones_add16_local(sum, src_port);
            sum = ones_add16_local(sum, dst_port);
            sum = ones_add16_local(sum, packet_id);
            compute_checksum = ~sum;
        end
    endfunction

    act_state_t state_q;
    logic [7:0] result_flags_q;
    logic [7:0] effective_action_q;
    logic [7:0] final_flags_q;
    logic [7:0] final_ttl_q;
    logic [15:0] final_dst_addr_q;
    logic [15:0] final_dst_port_q;
    logic [15:0] final_checksum_q;
    logic [159:0] result_bytes_q;
    logic [(MAX_FRAME_PAYLOAD*8)-1:0] forward_payload_q;
    logic [15:0] forward_len_q;
    logic [15:0] pkt_index_q;
    logic        forward_required_q;
    logic [7:0]  header_byte;
    logic [15:0] final_total_length_q;
    logic [15:0] final_payload_length_q;
    logic [7:0]  next_result_flags;

    always_comb begin
        case (pkt_index_q)
            16'd0:  header_byte = 8'h15;
            16'd1:  header_byte = protocol_i;
            16'd2:  header_byte = final_flags_q;
            16'd3:  header_byte = final_ttl_q;
            16'd4:  header_byte = final_total_length_q[15:8];
            16'd5:  header_byte = final_total_length_q[7:0];
            16'd6:  header_byte = final_payload_length_q[15:8];
            16'd7:  header_byte = final_payload_length_q[7:0];
            16'd8:  header_byte = src_addr_i[15:8];
            16'd9:  header_byte = src_addr_i[7:0];
            16'd10: header_byte = final_dst_addr_q[15:8];
            16'd11: header_byte = final_dst_addr_q[7:0];
            16'd12: header_byte = src_port_i[15:8];
            16'd13: header_byte = src_port_i[7:0];
            16'd14: header_byte = final_dst_port_q[15:8];
            16'd15: header_byte = final_dst_port_q[7:0];
            16'd16: header_byte = packet_id_i[15:8];
            16'd17: header_byte = packet_id_i[7:0];
            16'd18: header_byte = final_checksum_q[15:8];
            16'd19: header_byte = final_checksum_q[7:0];
            default: header_byte = packet_data_i;
        endcase
    end

    assign result_bytes_o   = result_bytes_q;
    assign forward_payload_o = forward_payload_q;
    assign forward_len_o    = forward_len_q;
    assign forward_seq_o    = seq_i;
    assign packet_ready_o   = (state_q == ACT_BUILD_FORWARD);
    assign busy_o           = (state_q != ACT_IDLE);
    assign next_result_flags =
        ((parse_error_i == PARSE_ERR_NONE) ? RESULT_FLAG_PARSE_OK : 8'h00) |
        (matched_i ? RESULT_FLAG_MATCHED : 8'h00) |
        (((parse_error_i != PARSE_ERR_NONE) || (effective_action_q == ACTION_DROP)) ? RESULT_FLAG_DROPPED : 8'h00) |
        ((effective_action_q == ACTION_REWRITE) ? RESULT_FLAG_REWRITTEN : 8'h00) |
        (checksum_ok_i ? RESULT_FLAG_CHECKSUM_OK : 8'h00) |
        (!matched_i ? RESULT_FLAG_DEFAULT_ACTION : 8'h00) |
        (verbose_i ? RESULT_FLAG_VERBOSE : 8'h00);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q            <= ACT_IDLE;
            result_flags_q     <= '0;
            effective_action_q <= ACTION_DROP;
            final_flags_q      <= '0;
            final_ttl_q        <= '0;
            final_dst_addr_q   <= '0;
            final_dst_port_q   <= '0;
            final_total_length_q <= '0;
            final_payload_length_q <= '0;
            final_checksum_q   <= '0;
            result_bytes_q     <= '0;
            forward_payload_q  <= '0;
            forward_len_q      <= '0;
            pkt_index_q        <= '0;
            forward_required_q <= 1'b0;
            packet_read_start_o <= 1'b0;
            result_valid_o     <= 1'b0;
            forward_valid_o    <= 1'b0;
            accepted_o         <= 1'b0;
            dropped_o          <= 1'b0;
            count_only_o       <= 1'b0;
            transformed_o      <= 1'b0;
            done_o             <= 1'b0;
        end else begin
            packet_read_start_o <= 1'b0;
            result_valid_o      <= 1'b0;
            forward_valid_o     <= 1'b0;
            accepted_o          <= 1'b0;
            dropped_o           <= 1'b0;
            count_only_o        <= 1'b0;
            transformed_o       <= 1'b0;
            done_o              <= 1'b0;

            case (state_q)
                ACT_IDLE: begin
                    if (start_i) begin
                        forward_payload_q    <= '0;
                        forward_len_q        <= '0;
                        pkt_index_q          <= '0;
                        final_total_length_q <= total_length_i;
                        final_payload_length_q <= payload_length_i;
                        final_flags_q        <= ((action_i == ACTION_REWRITE) && rewrite_en_i[1]) ? rewrite_flags_i : flags_i;
                        final_ttl_q          <= ((action_i == ACTION_REWRITE) && rewrite_en_i[0]) ? (ttl_i - 1'b1) : ttl_i;
                        final_dst_addr_q     <= ((action_i == ACTION_REWRITE) && rewrite_en_i[3]) ? rewrite_dst_addr_i : dst_addr_i;
                        final_dst_port_q     <= ((action_i == ACTION_REWRITE) && rewrite_en_i[2]) ? rewrite_dst_port_i : dst_port_i;
                        if ((parse_error_i != PARSE_ERR_NONE) || !checksum_ok_i) begin
                            effective_action_q <= ACTION_DROP;
                        end else begin
                            effective_action_q <= action_i;
                        end
                        state_q <= ACT_PREPARE;
                    end
                end

                ACT_PREPARE: begin
                    final_checksum_q <= compute_checksum(
                        8'h15,
                        protocol_i,
                        final_flags_q,
                        final_ttl_q,
                        final_total_length_q,
                        final_payload_length_q,
                        src_addr_i,
                        final_dst_addr_q,
                        src_port_i,
                        final_dst_port_q,
                        packet_id_i
                    );

                    result_flags_q <= next_result_flags;

                    result_bytes_q[(0*8)+:8]   <= next_result_flags;
                    result_bytes_q[(1*8)+:8]   <= mode_i;
                    result_bytes_q[(2*8)+:8]   <= matched_i ? {5'd0, matched_rule_i} : 8'hFF;
                    result_bytes_q[(3*8)+:8]   <= effective_action_q;
                    result_bytes_q[(4*8)+:8]   <= {4'd0, parse_error_i};
                    result_bytes_q[(5*8)+:8]   <= protocol_i;
                    result_bytes_q[(6*8)+:8]   <= packet_id_i[15:8];
                    result_bytes_q[(7*8)+:8]   <= packet_id_i[7:0];
                    result_bytes_q[(8*8)+:8]   <= src_addr_i[15:8];
                    result_bytes_q[(9*8)+:8]   <= src_addr_i[7:0];
                    result_bytes_q[(10*8)+:8]  <= final_dst_addr_q[15:8];
                    result_bytes_q[(11*8)+:8]  <= final_dst_addr_q[7:0];
                    result_bytes_q[(12*8)+:8]  <= src_port_i[15:8];
                    result_bytes_q[(13*8)+:8]  <= src_port_i[7:0];
                    result_bytes_q[(14*8)+:8]  <= final_dst_port_q[15:8];
                    result_bytes_q[(15*8)+:8]  <= final_dst_port_q[7:0];
                    result_bytes_q[(16*8)+:8]  <= final_total_length_q[15:8];
                    result_bytes_q[(17*8)+:8]  <= final_total_length_q[7:0];
                    result_bytes_q[(18*8)+:8]  <= final_payload_length_q[15:8];
                    result_bytes_q[(19*8)+:8]  <= final_payload_length_q[7:0];
                    result_valid_o             <= 1'b1;

                    if ((parse_error_i != PARSE_ERR_NONE) || !checksum_ok_i || (mode_i == MODE_INSPECT)) begin
                        if ((parse_error_i != PARSE_ERR_NONE) || (effective_action_q == ACTION_DROP)) begin
                            dropped_o <= 1'b1;
                        end else if (effective_action_q == ACTION_COUNT_ONLY) begin
                            count_only_o <= 1'b1;
                        end else begin
                            accepted_o <= 1'b1;
                        end
                        if (effective_action_q == ACTION_REWRITE) begin
                            transformed_o <= 1'b1;
                        end
                        done_o  <= 1'b1;
                        state_q <= ACT_DONE;
                    end else if (mode_i == MODE_BENCHMARK) begin
                        if (effective_action_q == ACTION_ACCEPT) begin
                            accepted_o <= 1'b1;
                        end else if (effective_action_q == ACTION_COUNT_ONLY) begin
                            count_only_o <= 1'b1;
                        end else if (effective_action_q == ACTION_REWRITE) begin
                            accepted_o   <= 1'b1;
                            transformed_o <= 1'b1;
                        end else begin
                            dropped_o <= 1'b1;
                        end
                        done_o  <= 1'b1;
                        state_q <= ACT_DONE;
                    end else if ((effective_action_q == ACTION_ACCEPT) || (effective_action_q == ACTION_REWRITE)) begin
                        forward_required_q                <= 1'b1;
                        forward_payload_q[(0*8)+:8]      <= next_result_flags;
                        forward_payload_q[(1*8)+:8]      <= matched_i ? {5'd0, matched_rule_i} : 8'hFF;
                        forward_payload_q[(2*8)+:8]      <= effective_action_q;
                        forward_payload_q[(3*8)+:8]      <= {4'd0, parse_error_i};
                        packet_read_start_o              <= 1'b1;
                        pkt_index_q                      <= 16'd0;
                        state_q                          <= ACT_BUILD_FORWARD;
                    end else begin
                        if (effective_action_q == ACTION_COUNT_ONLY) begin
                            count_only_o <= 1'b1;
                        end else begin
                            dropped_o <= 1'b1;
                        end
                        done_o  <= 1'b1;
                        state_q <= ACT_DONE;
                    end
                end

                ACT_BUILD_FORWARD: begin
                    if (packet_valid_i) begin
                        if (pkt_index_q < PACKET_HEADER_BYTES) begin
                            forward_payload_q[((pkt_index_q + 16'd4) * 8) +: 8] <= header_byte;
                        end else begin
                            forward_payload_q[((pkt_index_q + 16'd4) * 8) +: 8] <= packet_data_i;
                        end

                        if (packet_eop_i) begin
                            forward_len_q   <= packet_len_i + 16'd4;
                            forward_valid_o <= 1'b1;
                            accepted_o      <= 1'b1;
                            if (effective_action_q == ACTION_REWRITE) begin
                                transformed_o <= 1'b1;
                            end
                            done_o  <= 1'b1;
                            state_q <= ACT_DONE;
                        end
                        pkt_index_q <= pkt_index_q + 1'b1;
                    end
                end

                ACT_DONE: begin
                    state_q <= ACT_IDLE;
                end

                default: state_q <= ACT_IDLE;
            endcase
        end
    end
endmodule
