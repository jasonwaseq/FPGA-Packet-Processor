module frame_dispatch (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       frame_valid_i,
    output logic       frame_ready_o,
    input  logic [7:0] frame_type_i,
    input  logic [7:0] frame_flags_i,
    input  logic [7:0] frame_seq_i,
    input  logic [15:0] frame_len_i,
    input  logic [7:0] payload_data_i,
    input  logic       payload_valid_i,
    output logic       payload_ready_o,
    input  logic       payload_sop_i,
    input  logic       payload_eop_i,
    input  logic       cmd_accept_ready_i,
    output logic       cmd_start_o,
    output logic [7:0] cmd_seq_o,
    output logic [15:0] cmd_len_o,
    output logic [7:0] cmd_data_o,
    output logic       cmd_valid_o,
    output logic       cmd_sop_o,
    output logic       cmd_eop_o,
    input  logic       cmd_ready_i,
    input  logic       pkt_accept_ready_i,
    output logic       pkt_start_o,
    output logic [7:0] pkt_seq_o,
    output logic [15:0] pkt_len_o,
    output logic [7:0] pkt_data_o,
    output logic       pkt_valid_o,
    output logic       pkt_sop_o,
    output logic       pkt_eop_o,
    input  logic       pkt_ready_i
);
    localparam logic [7:0] MSG_TYPE_CMD_REQ = packet_processor_pkg::MSG_TYPE_CMD_REQ;
    localparam logic [7:0] MSG_TYPE_DATA_PACKET = packet_processor_pkg::MSG_TYPE_DATA_PACKET;

    typedef enum logic [1:0] {
        DISP_IDLE,
        DISP_CMD,
        DISP_PKT,
        DISP_DROP
    } disp_state_t;

    disp_state_t state_q;

    assign cmd_seq_o = frame_seq_i;
    assign cmd_len_o = frame_len_i;
    assign pkt_seq_o = frame_seq_i;
    assign pkt_len_o = frame_len_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q      <= DISP_IDLE;
            cmd_start_o  <= 1'b0;
            cmd_data_o   <= '0;
            cmd_valid_o  <= 1'b0;
            cmd_sop_o    <= 1'b0;
            cmd_eop_o    <= 1'b0;
            pkt_start_o  <= 1'b0;
            pkt_data_o   <= '0;
            pkt_valid_o  <= 1'b0;
            pkt_sop_o    <= 1'b0;
            pkt_eop_o    <= 1'b0;
        end else begin
            cmd_start_o <= 1'b0;
            cmd_valid_o <= 1'b0;
            cmd_sop_o   <= 1'b0;
            cmd_eop_o   <= 1'b0;
            pkt_start_o <= 1'b0;
            pkt_valid_o <= 1'b0;
            pkt_sop_o   <= 1'b0;
            pkt_eop_o   <= 1'b0;

            case (state_q)
                DISP_IDLE: begin
                    if (frame_valid_i) begin
                        if ((frame_type_i == MSG_TYPE_CMD_REQ) && cmd_accept_ready_i) begin
                            cmd_start_o <= 1'b1;
                            state_q     <= DISP_CMD;
                        end else if ((frame_type_i == MSG_TYPE_DATA_PACKET) && pkt_accept_ready_i) begin
                            pkt_start_o <= 1'b1;
                            state_q     <= DISP_PKT;
                        end else if ((frame_type_i != MSG_TYPE_CMD_REQ) && (frame_type_i != MSG_TYPE_DATA_PACKET)) begin
                            state_q <= DISP_DROP;
                        end
                    end
                end

                DISP_CMD: begin
                    if (payload_valid_i && cmd_ready_i) begin
                        cmd_data_o  <= payload_data_i;
                        cmd_valid_o <= 1'b1;
                        cmd_sop_o   <= payload_sop_i;
                        cmd_eop_o   <= payload_eop_i;
                        if (payload_eop_i) begin
                            state_q <= DISP_IDLE;
                        end
                    end
                end

                DISP_PKT: begin
                    if (payload_valid_i && pkt_ready_i) begin
                        pkt_data_o  <= payload_data_i;
                        pkt_valid_o <= 1'b1;
                        pkt_sop_o   <= payload_sop_i;
                        pkt_eop_o   <= payload_eop_i;
                        if (payload_eop_i) begin
                            state_q <= DISP_IDLE;
                        end
                    end
                end

                DISP_DROP: begin
                    if (payload_valid_i && payload_eop_i) begin
                        state_q <= DISP_IDLE;
                    end
                end

                default: state_q <= DISP_IDLE;
            endcase
        end
    end

    assign frame_ready_o  = (state_q == DISP_IDLE) &&
                            (((frame_type_i == MSG_TYPE_CMD_REQ) && cmd_accept_ready_i) ||
                             ((frame_type_i == MSG_TYPE_DATA_PACKET) && pkt_accept_ready_i) ||
                             ((frame_type_i != MSG_TYPE_CMD_REQ) && (frame_type_i != MSG_TYPE_DATA_PACKET)));
    assign payload_ready_o = ((state_q == DISP_CMD) && cmd_ready_i) ||
                             ((state_q == DISP_PKT) && pkt_ready_i) ||
                             (state_q == DISP_DROP);
endmodule
