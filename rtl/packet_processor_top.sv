module packet_processor_top #(
    parameter int unsigned UART_CLKS_PER_BIT = packet_processor_pkg::UART_CLKS_PER_BIT_DEFAULT,
    parameter int unsigned MAX_FRAME_PAYLOAD = packet_processor_pkg::MAX_FRAME_PAYLOAD,
    parameter int unsigned MAX_PACKET_BYTES = packet_processor_pkg::MAX_PACKET_BYTES,
    parameter int unsigned COUNTER_COUNT = packet_processor_pkg::COUNTER_COUNT,
    parameter int unsigned RULE_COUNT = packet_processor_pkg::RULE_COUNT,
    parameter int unsigned DECODER_QUEUE_DEPTH = 2
) (
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic uart_rx_i,
    output logic uart_tx_o
);
    localparam int unsigned RULE_IMAGE_W = packet_processor_pkg::RULE_IMAGE_W;
    localparam int unsigned RESULT_BYTES = packet_processor_pkg::RESULT_BYTES;
    localparam logic [7:0] MSG_TYPE_CMD_REQ = packet_processor_pkg::MSG_TYPE_CMD_REQ;
    localparam logic [7:0] MSG_TYPE_CMD_RESP = packet_processor_pkg::MSG_TYPE_CMD_RESP;
    localparam logic [7:0] MSG_TYPE_PKT_RESULT = packet_processor_pkg::MSG_TYPE_PKT_RESULT;
    localparam logic [7:0] MSG_TYPE_PKT_FORWARD = packet_processor_pkg::MSG_TYPE_PKT_FORWARD;
    localparam logic [7:0] MODE_INSPECT = packet_processor_pkg::MODE_INSPECT;
    localparam logic [7:0] ACTION_DROP = packet_processor_pkg::ACTION_DROP;
    localparam logic [7:0] ACTION_COUNT_ONLY = packet_processor_pkg::ACTION_COUNT_ONLY;
    localparam logic [3:0] PARSE_ERR_NONE = packet_processor_pkg::PARSE_ERR_NONE;

    typedef enum logic [2:0] {
        PROC_IDLE,
        PROC_PARSE_START,
        PROC_PARSE_WAIT,
        PROC_CLASSIFY_WAIT,
        PROC_ACTION_START,
        PROC_ACTION_WAIT,
        PROC_CLEAR
    } proc_state_t;

    logic [7:0] rx_byte;
    logic       rx_byte_valid;
    logic       rx_frame_error;

    logic       dec_frame_valid;
    logic       dec_frame_ready;
    logic [7:0] dec_frame_type;
    logic [7:0] dec_frame_flags;
    logic [7:0] dec_frame_seq;
    logic [15:0] dec_frame_len;
    logic [7:0] dec_payload_data;
    logic       dec_payload_valid;
    logic       dec_payload_sop;
    logic       dec_payload_eop;
    logic       dec_payload_ready;
    logic       stat_rx_frame_ok;
    logic       stat_crc_error;
    logic       stat_len_error;
    logic       stat_overflow;

    logic       cmd_accept_ready;
    logic       cmd_start;
    logic [7:0] cmd_seq;
    logic [15:0] cmd_len;
    logic [7:0] cmd_data;
    logic       cmd_valid;
    logic       cmd_sop;
    logic       cmd_eop;
    logic       cmd_ready;

    logic       pkt_accept_ready;
    logic       pkt_start;
    logic [7:0] pkt_seq;
    logic [15:0] pkt_len;
    logic [7:0] pkt_data;
    logic       pkt_valid;
    logic       pkt_sop;
    logic       pkt_eop;
    logic       pkt_ready;

    logic       packet_available;
    logic [15:0] packet_len;
    logic       packet_clear;
    logic       packet_read_start;
    logic [7:0] packet_read_data;
    logic       packet_read_valid;
    logic       packet_read_sop;
    logic       packet_read_eop;
    logic       packet_read_ready;
    logic       packet_read_done;

    logic       parser_hdr_valid;
    logic [3:0]  parser_error;
    logic        parser_checksum_ok;
    logic [7:0]  parser_protocol;
    logic [7:0]  parser_flags;
    logic [7:0]  parser_ttl;
    logic [15:0] parser_total_length;
    logic [15:0] parser_payload_length;
    logic [15:0] parser_src_addr;
    logic [15:0] parser_dst_addr;
    logic [15:0] parser_src_port;
    logic [15:0] parser_dst_port;
    logic [15:0] parser_packet_id;

    logic [7:0]  pkt_seq_q;
    logic [3:0]  parse_error_q;
    logic        checksum_ok_q;
    logic [7:0]  protocol_q;
    logic [7:0]  flags_q;
    logic [7:0]  ttl_q;
    logic [15:0] total_length_q;
    logic [15:0] payload_length_q;
    logic [15:0] src_addr_q;
    logic [15:0] dst_addr_q;
    logic [15:0] src_port_q;
    logic [15:0] dst_port_q;
    logic [15:0] packet_id_q;

    logic [2:0] class_lookup_idx;
    logic [RULE_IMAGE_W-1:0] class_lookup_rule;
    logic       classifier_done;
    logic       classifier_matched;
    logic [2:0] classifier_rule;
    logic [7:0] classifier_action;
    logic [3:0] classifier_rewrite_en;
    logic [7:0] classifier_rewrite_flags;
    logic [15:0] classifier_rewrite_dst_addr;
    logic [15:0] classifier_rewrite_dst_port;

    logic       action_start;
    logic       action_packet_read_start;
    logic       action_result_valid;
    logic [159:0] action_result_bytes;
    logic       action_forward_valid;
    logic [7:0] action_forward_seq;
    logic [15:0] action_forward_len;
    logic [(MAX_FRAME_PAYLOAD*8)-1:0] action_forward_payload;
    logic       action_accepted;
    logic       action_dropped;
    logic       action_count_only;
    logic       action_transformed;
    logic       action_busy;
    logic       action_done;

    logic [159:0] last_result_q;
    logic       pending_result_q;
    logic       pending_forward_q;
    logic [7:0] pending_seq_q;
    logic [15:0] pending_len_q;
    logic [(MAX_FRAME_PAYLOAD*8)-1:0] pending_payload_q;
    logic [7:0] pending_type_q;
    logic [(MAX_FRAME_PAYLOAD*8)-1:0] result_payload_flat;

    logic [7:0] control_mode;
    logic       control_verbose;
    logic [7:0] control_default_action;
    logic       control_soft_reset;
    logic       control_clear_counters;
    logic       rule_write_valid;
    logic [2:0] rule_write_index;
    logic [RULE_IMAGE_W-1:0] rule_write_data;
    logic       rule_clear;
    logic [2:0] rule_clear_index;
    logic       rule_clear_all;
    logic [2:0] rule_read_index;
    logic [RULE_IMAGE_W-1:0] rule_read_data;
    logic [4:0] stats_read_index;
    logic [31:0] stats_read_data;
    logic       control_resp_valid;
    logic       control_resp_ready;
    logic [7:0] control_resp_seq;
    logic [15:0] control_resp_len;
    logic [(MAX_FRAME_PAYLOAD*8)-1:0] control_resp_payload;

    logic       fmt_req_valid;
    logic       fmt_req_ready;
    logic [7:0] fmt_req_type;
    logic [7:0] fmt_req_flags;
    logic [7:0] fmt_req_seq;
    logic [15:0] fmt_req_len;
    logic [(MAX_FRAME_PAYLOAD*8)-1:0] fmt_req_payload;

    logic       enc_start;
    logic       enc_ready;
    logic [7:0] enc_type;
    logic [7:0] enc_flags;
    logic [7:0] enc_seq;
    logic [15:0] enc_len;
    logic [(MAX_FRAME_PAYLOAD*8)-1:0] enc_payload;
    logic       enc_done;
    logic [7:0] tx_data;
    logic       tx_valid;
    logic       tx_ready;

    logic [31:0] latency_counter_q;
    logic        parse_stream_done_q;
    logic        stat_data_packet_ok;
    logic        stat_parse_error;
    logic        stat_hdr_cksum_error;
    logic        stat_bytes_valid;
    logic [15:0] stat_bytes_processed;
    logic        stat_latency_valid;
    logic [31:0] stat_latency_cycles;
    logic        stat_rule_hit_valid;
    logic [2:0] stat_rule_hit_index;

    proc_state_t proc_state_q;

    assign pkt_accept_ready   = !packet_available && (proc_state_q == PROC_IDLE);
    assign dec_payload_ready  = (dec_frame_type == MSG_TYPE_CMD_REQ) ? cmd_ready : pkt_ready;
    assign packet_read_ready  = 1'b1;
    assign action_start       = (proc_state_q == PROC_ACTION_START);
    assign control_resp_ready = fmt_req_ready && !pending_result_q && !pending_forward_q;

    always_comb begin
        fmt_req_valid   = 1'b0;
        fmt_req_type    = MSG_TYPE_CMD_RESP;
        fmt_req_flags   = 8'h00;
        fmt_req_seq     = 8'h00;
        fmt_req_len     = 16'h0000;
        fmt_req_payload = '0;

        if (control_resp_valid) begin
            fmt_req_valid   = 1'b1;
            fmt_req_type    = MSG_TYPE_CMD_RESP;
            fmt_req_seq     = control_resp_seq;
            fmt_req_len     = control_resp_len;
            fmt_req_payload = control_resp_payload;
        end else if (pending_result_q) begin
            fmt_req_valid   = 1'b1;
            fmt_req_type    = MSG_TYPE_PKT_RESULT;
            fmt_req_seq     = pending_seq_q;
            fmt_req_len     = 16'd20;
            fmt_req_payload = pending_payload_q;
        end else if (pending_forward_q) begin
            fmt_req_valid   = 1'b1;
            fmt_req_type    = pending_type_q;
            fmt_req_seq     = pending_seq_q;
            fmt_req_len     = pending_len_q;
            fmt_req_payload = pending_payload_q;
        end
    end

    genvar g;
    generate
        for (g = 0; g < RESULT_BYTES; g++) begin : gen_result_flat
            always_comb begin
                result_payload_flat[(g*8)+:8] = action_result_bytes[(g*8)+:8];
            end
        end
    endgenerate

    uart_rx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart_rx (
        .clk(clk_i),
        .rst_n(rst_n_i),
        .rx_i(uart_rx_i),
        .data_o(rx_byte),
        .valid_o(rx_byte_valid),
        .frame_error_o(rx_frame_error)
    );

    uart_frame_decoder #(
        .MAX_FRAME_PAYLOAD(MAX_FRAME_PAYLOAD),
        .QUEUE_DEPTH(DECODER_QUEUE_DEPTH)
    ) u_frame_decoder (
        .clk(clk_i),
        .rst_n(rst_n_i),
        .data_i(rx_byte),
        .valid_i(rx_byte_valid),
        .frame_valid_o(dec_frame_valid),
        .frame_ready_i(dec_frame_ready),
        .frame_type_o(dec_frame_type),
        .frame_flags_o(dec_frame_flags),
        .frame_seq_o(dec_frame_seq),
        .frame_len_o(dec_frame_len),
        .payload_data_o(dec_payload_data),
        .payload_valid_o(dec_payload_valid),
        .payload_sop_o(dec_payload_sop),
        .payload_eop_o(dec_payload_eop),
        .payload_ready_i(dec_payload_ready),
        .rx_frame_ok_o(stat_rx_frame_ok),
        .crc_error_o(stat_crc_error),
        .length_error_o(stat_len_error),
        .overflow_o(stat_overflow)
    );

    frame_dispatch u_frame_dispatch (
        .clk(clk_i),
        .rst_n(rst_n_i),
        .frame_valid_i(dec_frame_valid),
        .frame_ready_o(dec_frame_ready),
        .frame_type_i(dec_frame_type),
        .frame_flags_i(dec_frame_flags),
        .frame_seq_i(dec_frame_seq),
        .frame_len_i(dec_frame_len),
        .payload_data_i(dec_payload_data),
        .payload_valid_i(dec_payload_valid),
        .payload_ready_o(dec_payload_ready),
        .payload_sop_i(dec_payload_sop),
        .payload_eop_i(dec_payload_eop),
        .cmd_accept_ready_i(cmd_accept_ready),
        .cmd_start_o(cmd_start),
        .cmd_seq_o(cmd_seq),
        .cmd_len_o(cmd_len),
        .cmd_data_o(cmd_data),
        .cmd_valid_o(cmd_valid),
        .cmd_sop_o(cmd_sop),
        .cmd_eop_o(cmd_eop),
        .cmd_ready_i(cmd_ready),
        .pkt_accept_ready_i(pkt_accept_ready),
        .pkt_start_o(pkt_start),
        .pkt_seq_o(pkt_seq),
        .pkt_len_o(pkt_len),
        .pkt_data_o(pkt_data),
        .pkt_valid_o(pkt_valid),
        .pkt_sop_o(pkt_sop),
        .pkt_eop_o(pkt_eop),
        .pkt_ready_i(pkt_ready)
    );

    packet_ingress_adapter #(
        .MAX_PACKET_BYTES(MAX_PACKET_BYTES)
    ) u_packet_ingress (
        .clk(clk_i),
        .rst_n(rst_n_i && !control_soft_reset),
        .in_data_i(pkt_data),
        .in_valid_i(pkt_valid),
        .in_sop_i(pkt_sop),
        .in_eop_i(pkt_eop),
        .in_ready_o(pkt_ready),
        .packet_available_o(packet_available),
        .packet_len_o(packet_len),
        .clear_i(packet_clear || control_soft_reset),
        .read_start_i(packet_read_start || action_packet_read_start),
        .read_data_o(packet_read_data),
        .read_valid_o(packet_read_valid),
        .read_sop_o(packet_read_sop),
        .read_eop_o(packet_read_eop),
        .read_ready_i(packet_read_ready),
        .read_done_o(packet_read_done)
    );

    packet_header_parser u_packet_parser (
        .clk(clk_i),
        .rst_n(rst_n_i),
        .packet_len_i(packet_len),
        .data_i(packet_read_data),
        .valid_i(packet_read_valid && ((proc_state_q == PROC_PARSE_WAIT) || (proc_state_q == PROC_CLASSIFY_WAIT))),
        .sop_i(packet_read_sop && (proc_state_q == PROC_PARSE_WAIT)),
        .eop_i(packet_read_eop && ((proc_state_q == PROC_PARSE_WAIT) || (proc_state_q == PROC_CLASSIFY_WAIT))),
        .ready_o(),
        .hdr_valid_o(parser_hdr_valid),
        .hdr_ready_i(1'b1),
        .header_bytes_o(),
        .parse_error_o(parser_error),
        .checksum_ok_o(parser_checksum_ok),
        .version_o(),
        .hdr_len_words_o(),
        .protocol_o(parser_protocol),
        .flags_o(parser_flags),
        .ttl_o(parser_ttl),
        .total_length_o(parser_total_length),
        .payload_length_o(parser_payload_length),
        .src_addr_o(parser_src_addr),
        .dst_addr_o(parser_dst_addr),
        .src_port_o(parser_src_port),
        .dst_port_o(parser_dst_port),
        .packet_id_o(parser_packet_id),
        .payload_data_o(),
        .payload_valid_o(),
        .payload_sop_o(),
        .payload_eop_o(),
        .payload_ready_i(1'b1)
    );

    rule_table #(
        .RULE_COUNT(RULE_COUNT)
    ) u_rule_table (
        .clk(clk_i),
        .rst_n(rst_n_i),
        .write_valid_i(rule_write_valid),
        .write_index_i(rule_write_index),
        .write_rule_i(rule_write_data),
        .clear_rule_i(rule_clear),
        .clear_rule_index_i(rule_clear_index),
        .clear_all_i(rule_clear_all),
        .lookup_index_i(class_lookup_idx),
        .lookup_rule_o(class_lookup_rule),
        .read_index_i(rule_read_index),
        .read_rule_o(rule_read_data)
    );

    classifier_engine #(
        .RULE_COUNT(RULE_COUNT)
    ) u_classifier (
        .clk(clk_i),
        .rst_n(rst_n_i),
        .start_i(parser_hdr_valid && (proc_state_q == PROC_PARSE_WAIT)),
        .protocol_i(parser_protocol),
        .src_addr_i(parser_src_addr),
        .dst_addr_i(parser_dst_addr),
        .src_port_i(parser_src_port),
        .dst_port_i(parser_dst_port),
        .lookup_index_o(class_lookup_idx),
        .lookup_rule_i(class_lookup_rule),
        .default_action_i(control_default_action),
        .done_o(classifier_done),
        .matched_o(classifier_matched),
        .matched_rule_o(classifier_rule),
        .action_o(classifier_action),
        .rewrite_en_o(classifier_rewrite_en),
        .rewrite_flags_o(classifier_rewrite_flags),
        .rewrite_dst_addr_o(classifier_rewrite_dst_addr),
        .rewrite_dst_port_o(classifier_rewrite_dst_port)
    );

    action_engine #(
        .MAX_PACKET_BYTES(MAX_PACKET_BYTES),
        .MAX_FRAME_PAYLOAD(MAX_FRAME_PAYLOAD)
    ) u_action (
        .clk(clk_i),
        .rst_n(rst_n_i),
        .start_i(action_start),
        .seq_i(pkt_seq_q),
        .mode_i(control_mode),
        .verbose_i(control_verbose),
        .packet_len_i(packet_len),
        .parse_error_i(parse_error_q),
        .checksum_ok_i(checksum_ok_q),
        .matched_i(classifier_matched),
        .matched_rule_i(classifier_rule),
        .action_i(classifier_action),
        .rewrite_en_i(classifier_rewrite_en),
        .rewrite_flags_i(classifier_rewrite_flags),
        .rewrite_dst_addr_i(classifier_rewrite_dst_addr),
        .rewrite_dst_port_i(classifier_rewrite_dst_port),
        .protocol_i(protocol_q),
        .flags_i(flags_q),
        .ttl_i(ttl_q),
        .total_length_i(total_length_q),
        .payload_length_i(payload_length_q),
        .src_addr_i(src_addr_q),
        .dst_addr_i(dst_addr_q),
        .src_port_i(src_port_q),
        .dst_port_i(dst_port_q),
        .packet_id_i(packet_id_q),
        .packet_read_start_o(action_packet_read_start),
        .packet_data_i(packet_read_data),
        .packet_valid_i(packet_read_valid && (proc_state_q == PROC_ACTION_WAIT)),
        .packet_ready_o(),
        .packet_eop_i(packet_read_eop && (proc_state_q == PROC_ACTION_WAIT)),
        .result_valid_o(action_result_valid),
        .result_bytes_o(action_result_bytes),
        .forward_valid_o(action_forward_valid),
        .forward_seq_o(action_forward_seq),
        .forward_len_o(action_forward_len),
        .forward_payload_o(action_forward_payload),
        .accepted_o(action_accepted),
        .dropped_o(action_dropped),
        .count_only_o(action_count_only),
        .transformed_o(action_transformed),
        .busy_o(action_busy),
        .done_o(action_done)
    );

    control_plane #(
        .MAX_FRAME_PAYLOAD(MAX_FRAME_PAYLOAD),
        .COUNTER_COUNT(COUNTER_COUNT),
        .RULE_COUNT(RULE_COUNT)
    ) u_control_plane (
        .clk(clk_i),
        .rst_n(rst_n_i),
        .accept_ready_o(cmd_accept_ready),
        .cmd_start_i(cmd_start),
        .cmd_seq_i(cmd_seq),
        .cmd_len_i(cmd_len),
        .cmd_data_i(cmd_data),
        .cmd_valid_i(cmd_valid),
        .cmd_sop_i(cmd_sop),
        .cmd_eop_i(cmd_eop),
        .cmd_ready_o(cmd_ready),
        .mode_o(control_mode),
        .verbose_o(control_verbose),
        .default_action_o(control_default_action),
        .soft_reset_o(control_soft_reset),
        .clear_counters_o(control_clear_counters),
        .rule_write_valid_o(rule_write_valid),
        .rule_write_index_o(rule_write_index),
        .rule_write_data_o(rule_write_data),
        .rule_clear_o(rule_clear),
        .rule_clear_index_o(rule_clear_index),
        .rule_clear_all_o(rule_clear_all),
        .rule_read_index_o(rule_read_index),
        .rule_read_data_i(rule_read_data),
        .stats_read_index_o(stats_read_index),
        .stats_read_data_i(stats_read_data),
        .last_result_i(last_result_q),
        .processor_busy_i(proc_state_q != PROC_IDLE),
        .resp_valid_o(control_resp_valid),
        .resp_ready_i(control_resp_ready),
        .resp_seq_o(control_resp_seq),
        .resp_len_o(control_resp_len),
        .resp_payload_o(control_resp_payload)
    );

    response_formatter #(
        .MAX_FRAME_PAYLOAD(MAX_FRAME_PAYLOAD)
    ) u_response_formatter (
        .clk(clk_i),
        .rst_n(rst_n_i),
        .req_valid_i(fmt_req_valid),
        .req_ready_o(fmt_req_ready),
        .req_type_i(fmt_req_type),
        .req_flags_i(fmt_req_flags),
        .req_seq_i(fmt_req_seq),
        .req_len_i(fmt_req_len),
        .req_payload_i(fmt_req_payload),
        .enc_start_o(enc_start),
        .enc_ready_i(enc_ready),
        .enc_type_o(enc_type),
        .enc_flags_o(enc_flags),
        .enc_seq_o(enc_seq),
        .enc_len_o(enc_len),
        .enc_payload_o(enc_payload),
        .enc_done_i(enc_done),
        .busy_o()
    );

    uart_frame_encoder #(
        .MAX_FRAME_PAYLOAD(MAX_FRAME_PAYLOAD)
    ) u_frame_encoder (
        .clk(clk_i),
        .rst_n(rst_n_i),
        .start_i(enc_start),
        .msg_type_i(enc_type),
        .flags_i(enc_flags),
        .seq_i(enc_seq),
        .payload_len_i(enc_len),
        .payload_i(enc_payload),
        .ready_o(enc_ready),
        .busy_o(),
        .tx_data_o(tx_data),
        .tx_valid_o(tx_valid),
        .tx_ready_i(tx_ready),
        .done_o(enc_done)
    );

    uart_tx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart_tx (
        .clk(clk_i),
        .rst_n(rst_n_i),
        .data_i(tx_data),
        .valid_i(tx_valid),
        .ready_o(tx_ready),
        .tx_o(uart_tx_o)
    );

    statistics_block #(
        .COUNTER_COUNT(COUNTER_COUNT)
    ) u_stats (
        .clk(clk_i),
        .rst_n(rst_n_i),
        .clear_i(control_clear_counters || control_soft_reset),
        .busy_i(proc_state_q != PROC_IDLE),
        .rx_frame_ok_i(stat_rx_frame_ok),
        .data_packet_ok_i(stat_data_packet_ok),
        .packet_accepted_i(action_accepted),
        .packet_dropped_i(action_dropped),
        .packet_count_only_i(action_count_only),
        .parse_error_i(stat_parse_error),
        .header_checksum_error_i(stat_hdr_cksum_error),
        .transport_crc_error_i(stat_crc_error),
        .transport_length_error_i(stat_len_error),
        .ingress_overflow_i(stat_overflow),
        .transformed_packet_i(action_transformed),
        .bytes_processed_valid_i(stat_bytes_valid),
        .bytes_processed_i(stat_bytes_processed),
        .latency_valid_i(stat_latency_valid),
        .latency_cycles_i(stat_latency_cycles),
        .rule_hit_valid_i(stat_rule_hit_valid),
        .rule_hit_index_i(stat_rule_hit_index),
        .read_index_i(stats_read_index),
        .read_counter_o(stats_read_data)
    );

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            proc_state_q        <= PROC_IDLE;
            packet_read_start   <= 1'b0;
            packet_clear        <= 1'b0;
            pkt_seq_q           <= '0;
            parse_error_q       <= PARSE_ERR_NONE;
            checksum_ok_q       <= 1'b0;
            protocol_q          <= '0;
            flags_q             <= '0;
            ttl_q               <= '0;
            total_length_q      <= '0;
            payload_length_q    <= '0;
            src_addr_q          <= '0;
            dst_addr_q          <= '0;
            src_port_q          <= '0;
            dst_port_q          <= '0;
            packet_id_q         <= '0;
            latency_counter_q   <= '0;
            parse_stream_done_q <= 1'b0;
            pending_result_q    <= 1'b0;
            pending_forward_q   <= 1'b0;
            pending_seq_q       <= '0;
            pending_len_q       <= '0;
            pending_payload_q   <= '0;
            pending_type_q      <= '0;
            last_result_q       <= '0;
            stat_data_packet_ok <= 1'b0;
            stat_parse_error    <= 1'b0;
            stat_hdr_cksum_error<= 1'b0;
            stat_bytes_valid    <= 1'b0;
            stat_bytes_processed<= '0;
            stat_latency_valid  <= 1'b0;
            stat_latency_cycles <= '0;
            stat_rule_hit_valid <= 1'b0;
            stat_rule_hit_index <= '0;
        end else begin
            packet_read_start    <= 1'b0;
            packet_clear         <= 1'b0;
            stat_data_packet_ok  <= 1'b0;
            stat_parse_error     <= 1'b0;
            stat_hdr_cksum_error <= 1'b0;
            stat_bytes_valid     <= 1'b0;
            stat_latency_valid   <= 1'b0;
            stat_rule_hit_valid  <= 1'b0;

            if (((proc_state_q == PROC_PARSE_WAIT) || (proc_state_q == PROC_CLASSIFY_WAIT)) && packet_read_done) begin
                parse_stream_done_q <= 1'b1;
            end

            if (proc_state_q != PROC_IDLE) begin
                latency_counter_q <= latency_counter_q + 1'b1;
            end

            if (fmt_req_valid && fmt_req_ready && pending_result_q && !control_resp_valid) begin
                pending_result_q <= 1'b0;
            end
            if (fmt_req_valid && fmt_req_ready && pending_forward_q && !control_resp_valid && !pending_result_q) begin
                pending_forward_q <= 1'b0;
            end

            if (pkt_start) begin
                pkt_seq_q <= pkt_seq;
            end

            case (proc_state_q)
                PROC_IDLE: begin
                    latency_counter_q <= 32'd0;
                    parse_stream_done_q <= 1'b0;
                    if (packet_available) begin
                        packet_read_start <= 1'b1;
                        proc_state_q      <= PROC_PARSE_WAIT;
                        stat_data_packet_ok <= 1'b1;
                        stat_bytes_valid    <= 1'b1;
                        stat_bytes_processed<= packet_len;
                    end
                end

                PROC_PARSE_WAIT: begin
                    if (parser_hdr_valid) begin
                        parse_error_q    <= parser_error;
                        checksum_ok_q    <= parser_checksum_ok;
                        protocol_q       <= parser_protocol;
                        flags_q          <= parser_flags;
                        ttl_q            <= parser_ttl;
                        total_length_q   <= parser_total_length;
                        payload_length_q <= parser_payload_length;
                        src_addr_q       <= parser_src_addr;
                        dst_addr_q       <= parser_dst_addr;
                        src_port_q       <= parser_src_port;
                        dst_port_q       <= parser_dst_port;
                        packet_id_q      <= parser_packet_id;
                        proc_state_q     <= PROC_CLASSIFY_WAIT;
                    end
                end

                PROC_CLASSIFY_WAIT: begin
                    if (classifier_done && parse_stream_done_q) begin
                        if (classifier_matched) begin
                            stat_rule_hit_valid <= 1'b1;
                            stat_rule_hit_index <= classifier_rule;
                        end
                        if (parse_error_q != PARSE_ERR_NONE) begin
                            stat_parse_error <= 1'b1;
                        end
                        if (!checksum_ok_q) begin
                            stat_hdr_cksum_error <= 1'b1;
                        end
                        proc_state_q <= PROC_ACTION_START;
                    end
                end

                PROC_ACTION_START: begin
                    proc_state_q <= PROC_ACTION_WAIT;
                end

                PROC_ACTION_WAIT: begin
                    if (action_result_valid) begin
                        last_result_q <= action_result_bytes;
                        pending_seq_q <= pkt_seq_q;
                        pending_payload_q <= '0;
                        pending_payload_q[(RESULT_BYTES*8)-1:0] <= action_result_bytes;
                        if ((control_mode == MODE_INSPECT) ||
                            ((parse_error_q != PARSE_ERR_NONE) || !checksum_ok_q) ||
                            (classifier_action == ACTION_DROP) ||
                            (classifier_action == ACTION_COUNT_ONLY) ||
                            control_verbose) begin
                            pending_result_q <= 1'b1;
                        end
                    end
                    if (action_forward_valid) begin
                        pending_seq_q     <= action_forward_seq;
                        pending_len_q     <= action_forward_len;
                        pending_payload_q <= action_forward_payload;
                        pending_type_q    <= MSG_TYPE_PKT_FORWARD;
                        pending_forward_q <= 1'b1;
                    end
                    if (action_done) begin
                        stat_latency_valid  <= 1'b1;
                        stat_latency_cycles <= latency_counter_q;
                        proc_state_q        <= PROC_CLEAR;
                    end
                end

                PROC_CLEAR: begin
                    packet_clear <= 1'b1;
                    proc_state_q <= PROC_IDLE;
                end

                default: proc_state_q <= PROC_IDLE;
            endcase
        end
    end
endmodule
