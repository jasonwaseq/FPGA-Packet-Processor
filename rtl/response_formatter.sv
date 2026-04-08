module response_formatter #(
    parameter int unsigned MAX_FRAME_PAYLOAD = packet_processor_pkg::MAX_FRAME_PAYLOAD
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       req_valid_i,
    output logic       req_ready_o,
    input  logic [7:0] req_type_i,
    input  logic [7:0] req_flags_i,
    input  logic [7:0] req_seq_i,
    input  logic [15:0] req_len_i,
    input  logic [(MAX_FRAME_PAYLOAD*8)-1:0] req_payload_i,
    output logic       enc_start_o,
    input  logic       enc_ready_i,
    output logic [7:0] enc_type_o,
    output logic [7:0] enc_flags_o,
    output logic [7:0] enc_seq_o,
    output logic [15:0] enc_len_o,
    output logic [(MAX_FRAME_PAYLOAD*8)-1:0] enc_payload_o,
    input  logic       enc_done_i,
    output logic       busy_o
);
    logic        pending_q;
    logic [7:0]  type_q;
    logic [7:0]  flags_q;
    logic [7:0]  seq_q;
    logic [15:0] len_q;
    logic [(MAX_FRAME_PAYLOAD*8)-1:0] payload_q;
    logic        start_sent_q;

    assign req_ready_o   = !pending_q;
    assign enc_type_o    = type_q;
    assign enc_flags_o   = flags_q;
    assign enc_seq_o     = seq_q;
    assign enc_len_o     = len_q;
    assign enc_payload_o = payload_q;
    assign busy_o        = pending_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_q    <= 1'b0;
            type_q       <= '0;
            flags_q      <= '0;
            seq_q        <= '0;
            len_q        <= '0;
            payload_q    <= '0;
            enc_start_o  <= 1'b0;
            start_sent_q <= 1'b0;
        end else begin
            enc_start_o <= 1'b0;

            if (req_valid_i && req_ready_o) begin
                pending_q    <= 1'b1;
                type_q       <= req_type_i;
                flags_q      <= req_flags_i;
                seq_q        <= req_seq_i;
                len_q        <= req_len_i;
                payload_q    <= req_payload_i;
                start_sent_q <= 1'b0;
            end

            if (pending_q && enc_ready_i && !start_sent_q) begin
                enc_start_o  <= 1'b1;
                start_sent_q <= 1'b1;
            end

            if (pending_q && enc_done_i) begin
                pending_q    <= 1'b0;
                start_sent_q <= 1'b0;
            end
        end
    end
endmodule
