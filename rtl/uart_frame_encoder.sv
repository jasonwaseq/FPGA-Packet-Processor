module uart_frame_encoder #(
    parameter int unsigned MAX_FRAME_PAYLOAD = packet_processor_pkg::MAX_FRAME_PAYLOAD
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start_i,
    input  logic [7:0] msg_type_i,
    input  logic [7:0] flags_i,
    input  logic [7:0] seq_i,
    input  logic [15:0] payload_len_i,
    input  logic [(MAX_FRAME_PAYLOAD*8)-1:0] payload_i,
    output logic       ready_o,
    output logic       busy_o,
    output logic [7:0] tx_data_o,
    output logic       tx_valid_o,
    input  logic       tx_ready_i,
    output logic       done_o
);
    localparam logic [7:0] FRAME_FLAG = packet_processor_pkg::FRAME_FLAG;
    localparam logic [7:0] FRAME_ESCAPE = packet_processor_pkg::FRAME_ESCAPE;
    localparam logic [7:0] PROTOCOL_VERSION = packet_processor_pkg::PROTOCOL_VERSION;

    function automatic logic [15:0] crc16_ccitt_next_local(
        input logic [15:0] crc_in,
        input logic [7:0]  data_in
    );
        logic [15:0] crc;
        integer i;
        begin
            crc = crc_in ^ {data_in, 8'h00};
            for (i = 0; i < 8; i = i + 1) begin
                if (crc[15]) begin
                    crc = (crc << 1) ^ 16'h1021;
                end else begin
                    crc = (crc << 1);
                end
            end
            crc16_ccitt_next_local = crc;
        end
    endfunction

    typedef enum logic [2:0] {
        ENC_IDLE,
        ENC_FLAG_START,
        ENC_BODY,
        ENC_CRC_HI,
        ENC_CRC_LO,
        ENC_FLAG_END
    } enc_state_t;

    enc_state_t state_q;
    logic [7:0]  msg_type_q;
    logic [7:0]  flags_q;
    logic [7:0]  seq_q;
    logic [15:0] payload_len_q;
    logic [(MAX_FRAME_PAYLOAD*8)-1:0] payload_q;
    logic [15:0] body_index_q;
    logic [15:0] crc_q;
    logic        escape_pending_q;
    logic [7:0]  escape_byte_q;
    logic [7:0]  current_raw_byte;

    function automatic logic [7:0] get_payload_byte(
        input logic [(MAX_FRAME_PAYLOAD*8)-1:0] payload,
        input logic [15:0] idx
    );
        begin
            get_payload_byte = payload[(idx*8) +: 8];
        end
    endfunction

    always_comb begin
        if (body_index_q == 16'd0) begin
            current_raw_byte = PROTOCOL_VERSION;
        end else if (body_index_q == 16'd1) begin
            current_raw_byte = msg_type_q;
        end else if (body_index_q == 16'd2) begin
            current_raw_byte = flags_q;
        end else if (body_index_q == 16'd3) begin
            current_raw_byte = seq_q;
        end else if (body_index_q == 16'd4) begin
            current_raw_byte = payload_len_q[15:8];
        end else if (body_index_q == 16'd5) begin
            current_raw_byte = payload_len_q[7:0];
        end else begin
            current_raw_byte = get_payload_byte(payload_q, body_index_q - 16'd6);
        end
    end

    assign ready_o = (state_q == ENC_IDLE);
    assign busy_o  = (state_q != ENC_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q           <= ENC_IDLE;
            msg_type_q        <= '0;
            flags_q           <= '0;
            seq_q             <= '0;
            payload_len_q     <= '0;
            payload_q         <= '0;
            body_index_q      <= '0;
            crc_q             <= 16'hFFFF;
            escape_pending_q  <= 1'b0;
            escape_byte_q     <= '0;
            tx_data_o         <= 8'h00;
            tx_valid_o        <= 1'b0;
            done_o            <= 1'b0;
        end else begin
            tx_valid_o <= 1'b0;
            done_o     <= 1'b0;

            case (state_q)
                ENC_IDLE: begin
                    if (start_i) begin
                        msg_type_q       <= msg_type_i;
                        flags_q          <= flags_i;
                        seq_q            <= seq_i;
                        payload_len_q    <= payload_len_i;
                        payload_q        <= payload_i;
                        body_index_q     <= '0;
                        crc_q            <= 16'hFFFF;
                        escape_pending_q <= 1'b0;
                        state_q          <= ENC_FLAG_START;
                    end
                end

                ENC_FLAG_START: begin
                    if (tx_ready_i) begin
                        tx_data_o  <= FRAME_FLAG;
                        tx_valid_o <= 1'b1;
                        state_q    <= ENC_BODY;
                    end
                end

                ENC_BODY: begin
                    if (tx_ready_i) begin
                        if (escape_pending_q) begin
                            tx_data_o         <= escape_byte_q;
                            tx_valid_o        <= 1'b1;
                            escape_pending_q  <= 1'b0;
                            body_index_q      <= body_index_q + 1'b1;
                            if (body_index_q == (payload_len_q + 16'd5)) begin
                                state_q <= ENC_CRC_HI;
                            end
                        end else if ((current_raw_byte == FRAME_FLAG) || (current_raw_byte == FRAME_ESCAPE)) begin
                            tx_data_o         <= FRAME_ESCAPE;
                            tx_valid_o        <= 1'b1;
                            escape_pending_q  <= 1'b1;
                            escape_byte_q     <= current_raw_byte ^ 8'h20;
                            crc_q             <= crc16_ccitt_next_local(crc_q, current_raw_byte);
                        end else begin
                            tx_data_o    <= current_raw_byte;
                            tx_valid_o   <= 1'b1;
                            crc_q        <= crc16_ccitt_next_local(crc_q, current_raw_byte);
                            body_index_q <= body_index_q + 1'b1;
                            if (body_index_q == (payload_len_q + 16'd5)) begin
                                state_q <= ENC_CRC_HI;
                            end
                        end
                    end
                end

                ENC_CRC_HI: begin
                    if (tx_ready_i) begin
                        if (!escape_pending_q) begin
                            if ((crc_q[15:8] == FRAME_FLAG) || (crc_q[15:8] == FRAME_ESCAPE)) begin
                                tx_data_o        <= FRAME_ESCAPE;
                                tx_valid_o       <= 1'b1;
                                escape_pending_q <= 1'b1;
                                escape_byte_q    <= crc_q[15:8] ^ 8'h20;
                            end else begin
                                tx_data_o  <= crc_q[15:8];
                                tx_valid_o <= 1'b1;
                                state_q    <= ENC_CRC_LO;
                            end
                        end else begin
                            tx_data_o        <= escape_byte_q;
                            tx_valid_o       <= 1'b1;
                            escape_pending_q <= 1'b0;
                            state_q          <= ENC_CRC_LO;
                        end
                    end
                end

                ENC_CRC_LO: begin
                    if (tx_ready_i) begin
                        if (!escape_pending_q) begin
                            if ((crc_q[7:0] == FRAME_FLAG) || (crc_q[7:0] == FRAME_ESCAPE)) begin
                                tx_data_o        <= FRAME_ESCAPE;
                                tx_valid_o       <= 1'b1;
                                escape_pending_q <= 1'b1;
                                escape_byte_q    <= crc_q[7:0] ^ 8'h20;
                            end else begin
                                tx_data_o  <= crc_q[7:0];
                                tx_valid_o <= 1'b1;
                                state_q    <= ENC_FLAG_END;
                            end
                        end else begin
                            tx_data_o        <= escape_byte_q;
                            tx_valid_o       <= 1'b1;
                            escape_pending_q <= 1'b0;
                            state_q          <= ENC_FLAG_END;
                        end
                    end
                end

                ENC_FLAG_END: begin
                    if (tx_ready_i) begin
                        tx_data_o  <= FRAME_FLAG;
                        tx_valid_o <= 1'b1;
                        done_o     <= 1'b1;
                        state_q    <= ENC_IDLE;
                    end
                end

                default: state_q <= ENC_IDLE;
            endcase
        end
    end
endmodule
