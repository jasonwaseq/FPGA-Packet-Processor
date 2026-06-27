`timescale 1ns/1ps

module packet_header_parser (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [15:0] packet_len_i,
    input  logic [7:0] data_i,
    input  logic       valid_i,
    input  logic       sop_i,
    input  logic       eop_i,
    output logic       ready_o,
    output logic       hdr_valid_o,
    input  logic       hdr_ready_i,
    output logic [159:0] header_bytes_o,
    output logic [3:0] parse_error_o,
    output logic       checksum_ok_o,
    output logic [3:0] version_o,
    output logic [3:0] hdr_len_words_o,
    output logic [7:0] protocol_o,
    output logic [7:0] flags_o,
    output logic [7:0] ttl_o,
    output logic [15:0] total_length_o,
    output logic [15:0] payload_length_o,
    output logic [15:0] src_addr_o,
    output logic [15:0] dst_addr_o,
    output logic [15:0] src_port_o,
    output logic [15:0] dst_port_o,
    output logic [15:0] packet_id_o,
    output logic [7:0] payload_data_o,
    output logic       payload_valid_o,
    output logic       payload_sop_o,
    output logic       payload_eop_o,
    input  logic       payload_ready_i
);
    localparam int unsigned PACKET_HEADER_BYTES = packet_processor_pkg::PACKET_HEADER_BYTES;
    localparam logic [3:0] PARSE_ERR_NONE = packet_processor_pkg::PARSE_ERR_NONE;
    localparam logic [3:0] PARSE_ERR_SHORT = packet_processor_pkg::PARSE_ERR_SHORT;
    localparam logic [3:0] PARSE_ERR_VERSION = packet_processor_pkg::PARSE_ERR_VERSION;
    localparam logic [3:0] PARSE_ERR_HDRLEN = packet_processor_pkg::PARSE_ERR_HDRLEN;
    localparam logic [3:0] PARSE_ERR_TTL = packet_processor_pkg::PARSE_ERR_TTL;
    localparam logic [3:0] PARSE_ERR_LENGTH = packet_processor_pkg::PARSE_ERR_LENGTH;
    localparam logic [3:0] PARSE_ERR_HDR_CHECKSUM = packet_processor_pkg::PARSE_ERR_HDR_CHECKSUM;
    localparam logic [15:0] PACKET_HEADER_BYTES_U16 = 16'd20;

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

    logic [159:0] header_q;
    logic [15:0]  byte_count_q;
    logic [15:0]  checksum_sum_q;
    logic [7:0]   checksum_hi_q;
    logic         checksum_phase_q;

    // Combinational header field aliases (reflect what is already stored)
    logic [7:0] h0, h1, h2, h3;
    logic [15:0] h4_5, h6_7, h8_9, h10_11, h12_13, h14_15, h16_17;

    // Combinational: final checksum including the word currently being processed
    // (needed because the NBA for checksum_sum_q won't commit until after we sample it)
    logic [15:0] csum_final;
    logic [3:0]  parse_error_next;

    assign ready_o        = 1'b1;
    assign header_bytes_o = header_q;

    assign h0 = header_q[(0*8)+:8];
    assign h1 = header_q[(1*8)+:8];
    assign h2 = header_q[(2*8)+:8];
    assign h3 = header_q[(3*8)+:8];
    assign h4_5   = {header_q[(4*8)+:8],  header_q[(5*8)+:8]};
    assign h6_7   = {header_q[(6*8)+:8],  header_q[(7*8)+:8]};
    assign h8_9   = {header_q[(8*8)+:8],  header_q[(9*8)+:8]};
    assign h10_11 = {header_q[(10*8)+:8], header_q[(11*8)+:8]};
    assign h12_13 = {header_q[(12*8)+:8], header_q[(13*8)+:8]};
    assign h14_15 = {header_q[(14*8)+:8], header_q[(15*8)+:8]};
    assign h16_17 = {header_q[(16*8)+:8], header_q[(17*8)+:8]};

    // When processing the last header byte (byte 19), checksum_phase_q is 1 and we
    // need the sum INCLUDING that last word — but the NBA hasn't committed yet.
    // Compute it combinationally so parse_error_next and checksum_ok_o are correct.
    always @* begin
        if (checksum_phase_q && (byte_count_q == (PACKET_HEADER_BYTES_U16 - 16'd1))) begin
            csum_final = ones_add16_local(checksum_sum_q, {checksum_hi_q, data_i});
        end else begin
            csum_final = checksum_sum_q;
        end

        parse_error_next = PARSE_ERR_NONE;
        if (packet_len_i < PACKET_HEADER_BYTES_U16) begin
            parse_error_next = PARSE_ERR_SHORT;
        end else if (h0[7:4] != 4'd1) begin
            parse_error_next = PARSE_ERR_VERSION;
        end else if (h0[3:0] != 4'd5) begin
            parse_error_next = PARSE_ERR_HDRLEN;
        end else if (h3 == 8'h00) begin
            parse_error_next = PARSE_ERR_TTL;
        end else if (h4_5 != packet_len_i) begin
            parse_error_next = PARSE_ERR_LENGTH;
        end else if (h6_7 != (packet_len_i - PACKET_HEADER_BYTES_U16)) begin
            parse_error_next = PARSE_ERR_LENGTH;
        end else if (csum_final != 16'hFFFF) begin
            parse_error_next = PARSE_ERR_HDR_CHECKSUM;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            header_q          <= '0;
            byte_count_q      <= '0;
            checksum_sum_q    <= 16'h0000;
            checksum_hi_q     <= 8'h00;
            checksum_phase_q  <= 1'b0;
            hdr_valid_o       <= 1'b0;
            parse_error_o     <= PARSE_ERR_NONE;
            checksum_ok_o     <= 1'b0;
            version_o         <= 4'd0;
            hdr_len_words_o   <= 4'd0;
            protocol_o        <= 8'd0;
            flags_o           <= 8'd0;
            ttl_o             <= 8'd0;
            total_length_o    <= 16'd0;
            payload_length_o  <= 16'd0;
            src_addr_o        <= 16'd0;
            dst_addr_o        <= 16'd0;
            src_port_o        <= 16'd0;
            dst_port_o        <= 16'd0;
            packet_id_o       <= 16'd0;
            payload_data_o    <= 8'd0;
            payload_valid_o   <= 1'b0;
            payload_sop_o     <= 1'b0;
            payload_eop_o     <= 1'b0;
        end else begin
            payload_valid_o <= 1'b0;
            payload_sop_o   <= 1'b0;
            payload_eop_o   <= 1'b0;

            if (hdr_valid_o && hdr_ready_i) begin
                hdr_valid_o <= 1'b0;
            end

            if (valid_i) begin
                if (sop_i) begin
                    // Reset state and treat this byte as byte index 0.
                    header_q          <= {152'h0, data_i};
                    byte_count_q      <= 16'd1;       // next byte will be index 1
                    checksum_sum_q    <= 16'h0000;
                    checksum_hi_q     <= data_i;      // byte 0 is HI of first checksum word
                    checksum_phase_q  <= 1'b1;        // HI consumed
                    hdr_valid_o       <= 1'b0;
                    parse_error_o     <= PARSE_ERR_NONE;
                    checksum_ok_o     <= 1'b0;
                end else begin
                    // Non-SOP bytes: process with current byte_count_q
                    if (byte_count_q < PACKET_HEADER_BYTES_U16) begin
                        header_q[(byte_count_q*8)+:8] <= data_i;

                        if (!checksum_phase_q) begin
                            checksum_hi_q    <= data_i;
                            checksum_phase_q <= 1'b1;
                        end else begin
                            checksum_sum_q   <= ones_add16_local(checksum_sum_q, {checksum_hi_q, data_i});
                            checksum_phase_q <= 1'b0;
                        end
                    end else if (payload_ready_i) begin
                        payload_data_o  <= data_i;
                        payload_valid_o <= 1'b1;
                        payload_sop_o   <= (byte_count_q == PACKET_HEADER_BYTES_U16);
                        payload_eop_o   <= eop_i;
                    end

                    // Finalize header on last byte (index 19)
                    if (byte_count_q == (PACKET_HEADER_BYTES_U16 - 16'd1)) begin
                        version_o        <= h0[7:4];
                        hdr_len_words_o  <= h0[3:0];
                        protocol_o       <= h1;
                        flags_o          <= h2;
                        ttl_o            <= h3;
                        total_length_o   <= h4_5;
                        payload_length_o <= h6_7;
                        src_addr_o       <= h8_9;
                        dst_addr_o       <= h10_11;
                        src_port_o       <= h12_13;
                        dst_port_o       <= h14_15;
                        packet_id_o      <= h16_17;
                        parse_error_o    <= parse_error_next;
                        checksum_ok_o    <= (csum_final == 16'hFFFF);
                        hdr_valid_o      <= 1'b1;
                    end

                    byte_count_q <= byte_count_q + 1'b1;

                    if (eop_i && ((byte_count_q + 16'd1) < PACKET_HEADER_BYTES_U16)) begin
                        parse_error_o <= PARSE_ERR_SHORT;
                        hdr_valid_o   <= 1'b1;
                    end
                end
            end
        end
    end
endmodule
