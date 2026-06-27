module packet_processor_up5k_top (
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic uart_rx_i,
    output logic uart_tx_o
);
    localparam int unsigned UART_CLKS_PER_BIT = 104; // 12 MHz / 104 ~= 115200 baud
    localparam int unsigned MAX_FRAME_PAYLOAD = 22;
    localparam int unsigned MAX_PACKET_BYTES = 20;
    localparam int unsigned RESULT_BYTES = packet_processor_pkg::RESULT_BYTES;
    localparam logic [15:0] RESULT_BYTES_U16 = 16'd20;

    localparam logic [7:0] MSG_TYPE_DATA_PACKET = packet_processor_pkg::MSG_TYPE_DATA_PACKET;
    localparam logic [7:0] MSG_TYPE_PKT_RESULT = packet_processor_pkg::MSG_TYPE_PKT_RESULT;
    localparam logic [7:0] MODE_INSPECT = packet_processor_pkg::MODE_INSPECT;
    localparam logic [7:0] ACTION_DROP = packet_processor_pkg::ACTION_DROP;
    localparam logic [7:0] ACTION_ACCEPT = packet_processor_pkg::ACTION_ACCEPT;
    localparam logic [7:0] ACTION_COUNT_ONLY = packet_processor_pkg::ACTION_COUNT_ONLY;
    localparam logic [7:0] ACTION_REWRITE = packet_processor_pkg::ACTION_REWRITE;
    localparam logic [3:0] PARSE_ERR_NONE = packet_processor_pkg::PARSE_ERR_NONE;
    localparam logic [7:0] RESULT_FLAG_PARSE_OK = packet_processor_pkg::RESULT_FLAG_PARSE_OK;
    localparam logic [7:0] RESULT_FLAG_MATCHED = packet_processor_pkg::RESULT_FLAG_MATCHED;
    localparam logic [7:0] RESULT_FLAG_DROPPED = packet_processor_pkg::RESULT_FLAG_DROPPED;
    localparam logic [7:0] RESULT_FLAG_REWRITTEN = packet_processor_pkg::RESULT_FLAG_REWRITTEN;
    localparam logic [7:0] RESULT_FLAG_CHECKSUM_OK = packet_processor_pkg::RESULT_FLAG_CHECKSUM_OK;
    localparam logic [7:0] RESULT_FLAG_DEFAULT_ACTION = packet_processor_pkg::RESULT_FLAG_DEFAULT_ACTION;

    logic [7:0] uart_rx_data;
    logic       uart_rx_valid;
    logic [7:0] uart_tx_data;
    logic       uart_tx_valid;
    logic       uart_tx_ready;

    logic       frame_valid;
    logic       frame_ready;
    logic [7:0] frame_type;
    logic [7:0] frame_seq;
    logic [15:0] frame_len;
    logic [7:0] frame_payload_data;
    logic       frame_payload_valid;
    logic       frame_payload_sop;
    logic       frame_payload_eop;
    logic       frame_payload_ready;

    logic ingest_in_ready;
    logic packet_available;
    logic [15:0] packet_len;
    logic packet_clear;
    logic ingest_read_start;
    logic [7:0] ingest_data;
    logic ingest_valid;
    logic ingest_sop;
    logic ingest_eop;
    logic ingest_read_done;

    logic parser_hdr_valid;
    logic [3:0] parser_error;
    logic parser_checksum_ok;
    logic [7:0] parser_protocol;
    logic [15:0] parser_packet_id;
    logic [15:0] parser_src_addr;
    logic [15:0] parser_dst_addr;
    logic [15:0] parser_src_port;
    logic [15:0] parser_dst_port;
    logic [15:0] parser_total_len;
    logic [15:0] parser_payload_len;

    logic [7:0] rx_seq_q;
    logic parser_busy_q;
    logic result_pending_q;
    logic [7:0] result_seq_q;
    logic [(MAX_FRAME_PAYLOAD*8)-1:0] result_payload_q;

    logic enc_start;
    logic enc_ready;
    logic enc_done;

    logic [7:0] result_flags;
    logic [7:0] result_rule_id;
    logic [7:0] result_action;
    logic [3:0] result_error;
    logic [15:0] result_dst_addr;
    logic [15:0] result_dst_port;
    logic is_drop_rule;
    logic is_count_rule;
    logic is_rewrite_rule;
    logic parse_ok;
    logic rst_n;
    logic [7:0] por_count_q = 8'd0;

    // Internal POR so sequential logic reaches a deterministic state even if external reset wiring is unavailable.
    assign rst_n = &por_count_q;

    always_ff @(posedge clk_i) begin
        if (!rst_n) begin
            por_count_q <= por_count_q + 1'b1;
        end
    end

    assign frame_ready = !packet_available && !parser_busy_q;
    assign frame_payload_ready = 1'b1;
    assign ingest_read_start = packet_available && !parser_busy_q;
    assign packet_clear = 1'b0;

    assign parse_ok = (parser_error == PARSE_ERR_NONE);
    assign is_drop_rule = parse_ok && (parser_protocol == 8'h11) && (parser_dst_port == 16'h9001);
    assign is_count_rule = parse_ok && !is_drop_rule && (parser_src_addr == 16'h3333);
    assign is_rewrite_rule = parse_ok && !is_drop_rule && !is_count_rule && (parser_protocol == 8'h11) && (parser_dst_addr == 16'h2222);

    always_comb begin
        result_flags = 8'h00;
        if (parse_ok) result_flags = result_flags | RESULT_FLAG_PARSE_OK;
        if (parser_checksum_ok) result_flags = result_flags | RESULT_FLAG_CHECKSUM_OK;

        result_rule_id = 8'hFF;
        result_action = ACTION_ACCEPT;
        result_error = parser_error;
        result_dst_addr = parser_dst_addr;
        result_dst_port = parser_dst_port;

        if (!parse_ok) begin
            result_action = ACTION_DROP;
            result_flags = result_flags | RESULT_FLAG_DROPPED;
        end else if (is_drop_rule) begin
            result_rule_id = 8'd0;
            result_action = ACTION_DROP;
            result_flags = result_flags | RESULT_FLAG_MATCHED | RESULT_FLAG_DROPPED;
        end else if (is_count_rule) begin
            result_rule_id = 8'd1;
            result_action = ACTION_COUNT_ONLY;
            result_flags = result_flags | RESULT_FLAG_MATCHED;
        end else if (is_rewrite_rule) begin
            result_rule_id = 8'd2;
            result_action = ACTION_REWRITE;
            result_dst_addr = 16'hCAFE;
            result_dst_port = 16'hBEEF;
            result_flags = result_flags | RESULT_FLAG_MATCHED | RESULT_FLAG_REWRITTEN;
        end else begin
            result_flags = result_flags | RESULT_FLAG_DEFAULT_ACTION;
        end
    end

    always_ff @(posedge clk_i or negedge rst_n) begin
        if (!rst_n) begin
            rx_seq_q <= 8'd0;
            parser_busy_q <= 1'b0;
            result_pending_q <= 1'b0;
            result_seq_q <= 8'd0;
            result_payload_q <= '0;
        end else begin
            if (frame_valid && frame_ready) begin
                rx_seq_q <= frame_seq;
            end

            if (ingest_read_start) begin
                parser_busy_q <= 1'b1;
            end
            if (ingest_read_done) begin
                parser_busy_q <= 1'b0;
            end

            if (parser_hdr_valid && !result_pending_q) begin
                result_pending_q <= 1'b1;
                result_seq_q     <= rx_seq_q;
                // Single concatenation avoids overlapping-NBA synthesis issues in Yosys.
                // Bits [175:160] = padding (2 unused bytes of the 22-byte max-payload slot).
                // Bytes are packed LSB-first: byte N occupies bits [(N*8)+7:(N*8)].
                result_payload_q <= {
                    16'h0000,                    // bits[175:160] padding (bytes 20-21)
                    parser_payload_len[7:0],     // bits[159:152] byte 19
                    parser_payload_len[15:8],    // bits[151:144] byte 18
                    parser_total_len[7:0],       // bits[143:136] byte 17
                    parser_total_len[15:8],      // bits[135:128] byte 16
                    result_dst_port[7:0],        // bits[127:120] byte 15
                    result_dst_port[15:8],       // bits[119:112] byte 14
                    parser_src_port[7:0],        // bits[111:104] byte 13
                    parser_src_port[15:8],       // bits[103: 96] byte 12
                    result_dst_addr[7:0],        // bits[ 95: 88] byte 11
                    result_dst_addr[15:8],       // bits[ 87: 80] byte 10
                    parser_src_addr[7:0],        // bits[ 79: 72] byte 9
                    parser_src_addr[15:8],       // bits[ 71: 64] byte 8
                    parser_packet_id[7:0],       // bits[ 63: 56] byte 7
                    parser_packet_id[15:8],      // bits[ 55: 48] byte 6
                    parser_protocol,             // bits[ 47: 40] byte 5
                    {4'd0, result_error},        // bits[ 39: 32] byte 4
                    result_action,               // bits[ 31: 24] byte 3
                    result_rule_id,             // bits[ 23: 16] byte 2
                    MODE_INSPECT,                // bits[ 15:  8] byte 1
                    result_flags                 // bits[  7:  0] byte 0
                };
            end

            if (enc_start) begin
                result_pending_q <= 1'b0;
            end
        end
    end

    assign enc_start = result_pending_q && enc_ready;

    uart_rx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart_rx (
        .clk(clk_i),
        .rst_n(rst_n),
        .rx_i(uart_rx_i),
        .data_o(uart_rx_data),
        .valid_o(uart_rx_valid)
    );

    uart_tx #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT)
    ) u_uart_tx (
        .clk(clk_i),
        .rst_n(rst_n),
        .data_i(uart_tx_data),
        .valid_i(uart_tx_valid),
        .ready_o(uart_tx_ready),
        .tx_o(uart_tx_o)
    );

    uart_frame_decoder #(
        .MAX_FRAME_PAYLOAD(MAX_FRAME_PAYLOAD),
        .QUEUE_DEPTH(2)
    ) u_frame_decoder (
        .clk(clk_i),
        .rst_n(rst_n),
        .data_i(uart_rx_data),
        .valid_i(uart_rx_valid),
        .frame_valid_o(frame_valid),
        .frame_ready_i(frame_ready),
        .frame_type_o(frame_type),
        .frame_flags_o(),
        .frame_seq_o(frame_seq),
        .frame_len_o(frame_len),
        .payload_data_o(frame_payload_data),
        .payload_valid_o(frame_payload_valid),
        .payload_sop_o(frame_payload_sop),
        .payload_eop_o(frame_payload_eop),
        .payload_ready_i(frame_payload_ready),
        .rx_frame_ok_o(),
        .crc_error_o(),
        .length_error_o(),
        .overflow_o()
    );

    packet_ingress_adapter #(
        .MAX_PACKET_BYTES(MAX_PACKET_BYTES)
    ) u_ingress (
        .clk(clk_i),
        .rst_n(rst_n),
        .in_data_i(frame_payload_data),
        .in_valid_i(frame_payload_valid && (frame_type == MSG_TYPE_DATA_PACKET) && (frame_len <= MAX_PACKET_BYTES)),
        .in_sop_i(frame_payload_sop),
        .in_eop_i(frame_payload_eop),
        .in_ready_o(ingest_in_ready),
        .packet_available_o(packet_available),
        .packet_len_o(packet_len),
        .clear_i(packet_clear),
        .read_start_i(ingest_read_start),
        .read_data_o(ingest_data),
        .read_valid_o(ingest_valid),
        .read_sop_o(ingest_sop),
        .read_eop_o(ingest_eop),
        .read_ready_i(1'b1),
        .read_done_o(ingest_read_done)
    );

    packet_header_parser u_parser (
        .clk(clk_i),
        .rst_n(rst_n),
        .packet_len_i(packet_len),
        .data_i(ingest_data),
        .valid_i(ingest_valid),
        .sop_i(ingest_sop),
        .eop_i(ingest_eop),
        .ready_o(),
        .hdr_valid_o(parser_hdr_valid),
        .hdr_ready_i(1'b1),
        .header_bytes_o(),
        .parse_error_o(parser_error),
        .checksum_ok_o(parser_checksum_ok),
        .version_o(),
        .hdr_len_words_o(),
        .protocol_o(parser_protocol),
        .flags_o(),
        .ttl_o(),
        .total_length_o(parser_total_len),
        .payload_length_o(parser_payload_len),
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

    uart_frame_encoder #(
        .MAX_FRAME_PAYLOAD(MAX_FRAME_PAYLOAD)
    ) u_frame_encoder (
        .clk(clk_i),
        .rst_n(rst_n),
        .start_i(enc_start),
        .msg_type_i(MSG_TYPE_PKT_RESULT),
        .flags_i(8'h00),
        .seq_i(result_seq_q),
        .payload_len_i(RESULT_BYTES_U16),
        .payload_i(result_payload_q),
        .ready_o(enc_ready),
        .busy_o(),
        .tx_data_o(uart_tx_data),
        .tx_valid_o(uart_tx_valid),
        .tx_ready_i(uart_tx_ready),
        .done_o(enc_done)
    );
endmodule
