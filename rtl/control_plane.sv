module control_plane #(
    parameter int unsigned MAX_FRAME_PAYLOAD = packet_processor_pkg::MAX_FRAME_PAYLOAD,
    parameter int unsigned RULE_IMAGE_W = packet_processor_pkg::RULE_IMAGE_W,
    parameter int unsigned COUNTER_COUNT = packet_processor_pkg::COUNTER_COUNT,
    parameter int unsigned RULE_COUNT = packet_processor_pkg::RULE_COUNT
) (
    input  logic       clk,
    input  logic       rst_n,
    output logic       accept_ready_o,
    input  logic       cmd_start_i,
    input  logic [7:0] cmd_seq_i,
    input  logic [15:0] cmd_len_i,
    input  logic [7:0] cmd_data_i,
    input  logic       cmd_valid_i,
    input  logic       cmd_sop_i,
    input  logic       cmd_eop_i,
    output logic       cmd_ready_o,
    output logic [7:0] mode_o,
    output logic       verbose_o,
    output logic [7:0] default_action_o,
    output logic       soft_reset_o,
    output logic       clear_counters_o,
    output logic       rule_write_valid_o,
    output logic [2:0] rule_write_index_o,
    output logic [RULE_IMAGE_W-1:0] rule_write_data_o,
    output logic       rule_clear_o,
    output logic [2:0] rule_clear_index_o,
    output logic       rule_clear_all_o,
    output logic [2:0] rule_read_index_o,
    input  logic [RULE_IMAGE_W-1:0] rule_read_data_i,
    output logic [4:0] stats_read_index_o,
    input  logic [31:0] stats_read_data_i,
    input  logic [159:0] last_result_i,
    input  logic       processor_busy_i,
    output logic       resp_valid_o,
    input  logic       resp_ready_i,
    output logic [7:0] resp_seq_o,
    output logic [15:0] resp_len_o,
    output logic [(MAX_FRAME_PAYLOAD*8)-1:0] resp_payload_o
);
    localparam int unsigned MAX_PACKET_BYTES = packet_processor_pkg::MAX_PACKET_BYTES;
    localparam int unsigned RESULT_BYTES = packet_processor_pkg::RESULT_BYTES;
    localparam logic [7:0] STATUS_OK = packet_processor_pkg::STATUS_OK;
    localparam logic [7:0] STATUS_ERR_BAD_OPCODE = packet_processor_pkg::STATUS_ERR_BAD_OPCODE;
    localparam logic [7:0] STATUS_ERR_BAD_LEN = packet_processor_pkg::STATUS_ERR_BAD_LEN;
    localparam logic [7:0] STATUS_ERR_BAD_PARAM = packet_processor_pkg::STATUS_ERR_BAD_PARAM;
    localparam logic [7:0] STATUS_ERR_BUSY = packet_processor_pkg::STATUS_ERR_BUSY;
    localparam logic [7:0] STATUS_ERR_RULE_IDX = packet_processor_pkg::STATUS_ERR_RULE_IDX;
    localparam logic [7:0] STATUS_ERR_MODE = packet_processor_pkg::STATUS_ERR_MODE;
    localparam logic [7:0] CMD_PING = packet_processor_pkg::CMD_PING;
    localparam logic [7:0] CMD_GET_INFO = packet_processor_pkg::CMD_GET_INFO;
    localparam logic [7:0] CMD_SOFT_RESET = packet_processor_pkg::CMD_SOFT_RESET;
    localparam logic [7:0] CMD_CLEAR_COUNTERS = packet_processor_pkg::CMD_CLEAR_COUNTERS;
    localparam logic [7:0] CMD_SET_MODE = packet_processor_pkg::CMD_SET_MODE;
    localparam logic [7:0] CMD_GET_MODE = packet_processor_pkg::CMD_GET_MODE;
    localparam logic [7:0] CMD_WRITE_RULE = packet_processor_pkg::CMD_WRITE_RULE;
    localparam logic [7:0] CMD_CLEAR_RULE = packet_processor_pkg::CMD_CLEAR_RULE;
    localparam logic [7:0] CMD_CLEAR_ALL_RULES = packet_processor_pkg::CMD_CLEAR_ALL_RULES;
    localparam logic [7:0] CMD_READ_RULE = packet_processor_pkg::CMD_READ_RULE;
    localparam logic [7:0] CMD_SET_DEFAULT_ACTION = packet_processor_pkg::CMD_SET_DEFAULT_ACTION;
    localparam logic [7:0] CMD_SET_VERBOSE = packet_processor_pkg::CMD_SET_VERBOSE;
    localparam logic [7:0] CMD_READ_COUNTERS = packet_processor_pkg::CMD_READ_COUNTERS;
    localparam logic [7:0] CMD_READ_LAST_RESULT = packet_processor_pkg::CMD_READ_LAST_RESULT;
    localparam logic [7:0] CMD_READ_STATUS = packet_processor_pkg::CMD_READ_STATUS;
    localparam logic [7:0] MODE_INSPECT = packet_processor_pkg::MODE_INSPECT;
    localparam logic [7:0] MODE_INLINE = packet_processor_pkg::MODE_INLINE;
    localparam logic [7:0] MODE_BENCHMARK = packet_processor_pkg::MODE_BENCHMARK;
    localparam logic [7:0] ACTION_DROP = packet_processor_pkg::ACTION_DROP;
    localparam logic [7:0] ACTION_COUNT_ONLY = packet_processor_pkg::ACTION_COUNT_ONLY;

    typedef enum logic [2:0] {
        CP_IDLE,
        CP_RECV,
        CP_DECODE,
        CP_BUILD_COUNTERS,
        CP_WAIT_RESP
    } cp_state_t;

    cp_state_t state_q;
    logic [(MAX_FRAME_PAYLOAD*8)-1:0] cmd_buf_q;
    logic [(MAX_FRAME_PAYLOAD*8)-1:0] resp_buf_q;
    logic [7:0]  resp_status_q;
    logic [15:0] recv_len_q;
    logic [15:0] recv_ptr_q;
    logic [7:0]  seq_q;
    logic [7:0]  opcode_q;
    logic [4:0]  counter_idx_q;
    integer idx;

    function automatic logic [7:0] get_cmd_byte(
        input logic [(MAX_FRAME_PAYLOAD*8)-1:0] cmd_buf_i,
        input logic [15:0] idx_i
    );
        begin
            get_cmd_byte = cmd_buf_i[(idx_i*8) +: 8];
        end
    endfunction

    task automatic init_resp(
        input logic [7:0] opcode,
        input logic [7:0] status
    );
        begin
            resp_buf_q            <= '0;
            resp_buf_q[(0*8)+:8]  <= opcode;
            resp_buf_q[(1*8)+:8]  <= status;
            resp_len_o            <= 16'd2;
        end
    endtask

    assign accept_ready_o = (state_q == CP_IDLE) && !resp_valid_o;
    assign cmd_ready_o    = (state_q == CP_RECV);
    assign resp_seq_o     = seq_q;
    assign resp_payload_o = resp_buf_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q            <= CP_IDLE;
            cmd_buf_q          <= '0;
            resp_buf_q         <= '0;
            resp_status_q      <= STATUS_OK;
            recv_len_q         <= '0;
            recv_ptr_q         <= '0;
            seq_q              <= '0;
            opcode_q           <= '0;
            counter_idx_q      <= '0;
            mode_o             <= MODE_INSPECT;
            verbose_o          <= 1'b0;
            default_action_o   <= ACTION_DROP;
            soft_reset_o       <= 1'b0;
            clear_counters_o   <= 1'b0;
            rule_write_valid_o <= 1'b0;
            rule_write_index_o <= '0;
            rule_write_data_o  <= '0;
            rule_clear_o       <= 1'b0;
            rule_clear_index_o <= '0;
            rule_clear_all_o   <= 1'b0;
            rule_read_index_o  <= '0;
            stats_read_index_o <= '0;
            resp_valid_o       <= 1'b0;
            resp_len_o         <= '0;
        end else begin
            soft_reset_o       <= 1'b0;
            clear_counters_o   <= 1'b0;
            rule_write_valid_o <= 1'b0;
            rule_clear_o       <= 1'b0;
            rule_clear_all_o   <= 1'b0;

            case (state_q)
                CP_IDLE: begin
                    resp_valid_o <= 1'b0;
                    if (cmd_start_i) begin
                        recv_len_q  <= cmd_len_i;
                        recv_ptr_q  <= '0;
                        seq_q       <= cmd_seq_i;
                        cmd_buf_q   <= '0;
                        state_q     <= CP_RECV;
                    end
                end

                CP_RECV: begin
                    if (cmd_valid_i) begin
                        cmd_buf_q[(recv_ptr_q*8) +: 8] <= cmd_data_i;
                        recv_ptr_q <= recv_ptr_q + 1'b1;
                        if (cmd_eop_i) begin
                            state_q  <= CP_DECODE;
                            opcode_q <= get_cmd_byte(cmd_buf_q, 16'd0);
                        end
                    end
                end

                CP_DECODE: begin
                    opcode_q      <= get_cmd_byte(cmd_buf_q, 16'd0);
                    rule_read_index_o <= get_cmd_byte(cmd_buf_q, 16'd1);
                    init_resp(get_cmd_byte(cmd_buf_q, 16'd0), STATUS_OK);

                    unique case (get_cmd_byte(cmd_buf_q, 16'd0))
                        CMD_PING: begin
                            resp_buf_q[(2*8)+:8] <= 8'h55;
                            resp_buf_q[(3*8)+:8] <= 8'h50;
                            resp_buf_q[(4*8)+:8] <= 8'h50;
                            resp_buf_q[(5*8)+:8] <= 8'h31;
                            resp_len_o <= 16'd6;
                            state_q    <= CP_WAIT_RESP;
                        end

                        CMD_GET_INFO: begin
                            resp_buf_q[(2*8)+:8] <= 8'h01;
                            resp_buf_q[(3*8)+:8] <= RULE_COUNT;
                            resp_buf_q[(4*8)+:8] <= MAX_PACKET_BYTES[7:0];
                            resp_buf_q[(5*8)+:8] <= MAX_FRAME_PAYLOAD[7:0];
                            resp_buf_q[(6*8)+:8] <= MODE_INSPECT;
                            resp_buf_q[(7*8)+:8] <= MODE_INLINE;
                            resp_buf_q[(8*8)+:8] <= MODE_BENCHMARK;
                            resp_len_o <= 16'd9;
                            state_q    <= CP_WAIT_RESP;
                        end

                        CMD_SOFT_RESET: begin
                            soft_reset_o <= 1'b1;
                            state_q      <= CP_WAIT_RESP;
                        end

                        CMD_CLEAR_COUNTERS: begin
                            clear_counters_o <= 1'b1;
                            state_q          <= CP_WAIT_RESP;
                        end

                        CMD_SET_MODE: begin
                            if (recv_len_q != 16'd2) begin
                                init_resp(CMD_SET_MODE, STATUS_ERR_BAD_LEN);
                            end else if (get_cmd_byte(cmd_buf_q, 16'd1) > MODE_BENCHMARK) begin
                                init_resp(CMD_SET_MODE, STATUS_ERR_MODE);
                            end else begin
                                mode_o <= get_cmd_byte(cmd_buf_q, 16'd1);
                            end
                            state_q <= CP_WAIT_RESP;
                        end

                        CMD_GET_MODE: begin
                            resp_buf_q[(2*8)+:8] <= mode_o;
                            resp_buf_q[(3*8)+:8] <= {7'd0, verbose_o};
                            resp_buf_q[(4*8)+:8] <= default_action_o;
                            resp_len_o <= 16'd5;
                            state_q    <= CP_WAIT_RESP;
                        end

                        CMD_WRITE_RULE: begin
                            if (recv_len_q != 16'd26) begin
                                init_resp(CMD_WRITE_RULE, STATUS_ERR_BAD_LEN);
                            end else if (get_cmd_byte(cmd_buf_q, 16'd1) >= RULE_COUNT) begin
                                init_resp(CMD_WRITE_RULE, STATUS_ERR_RULE_IDX);
                            end else if (processor_busy_i) begin
                                init_resp(CMD_WRITE_RULE, STATUS_ERR_BUSY);
                            end else begin
                                rule_write_index_o <= get_cmd_byte(cmd_buf_q, 16'd1);
                                for (idx = 0; idx < RULE_IMAGE_W/8; idx++) begin
                                    rule_write_data_o[(idx*8)+:8] <= get_cmd_byte(cmd_buf_q, idx + 16'd2);
                                end
                                rule_write_valid_o <= 1'b1;
                            end
                            state_q <= CP_WAIT_RESP;
                        end

                        CMD_CLEAR_RULE: begin
                            if (recv_len_q != 16'd2) begin
                                init_resp(CMD_CLEAR_RULE, STATUS_ERR_BAD_LEN);
                            end else if (get_cmd_byte(cmd_buf_q, 16'd1) >= RULE_COUNT) begin
                                init_resp(CMD_CLEAR_RULE, STATUS_ERR_RULE_IDX);
                            end else if (processor_busy_i) begin
                                init_resp(CMD_CLEAR_RULE, STATUS_ERR_BUSY);
                            end else begin
                                rule_clear_o       <= 1'b1;
                                rule_clear_index_o <= get_cmd_byte(cmd_buf_q, 16'd1);
                            end
                            state_q <= CP_WAIT_RESP;
                        end

                        CMD_CLEAR_ALL_RULES: begin
                            if (recv_len_q != 16'd1) begin
                                init_resp(CMD_CLEAR_ALL_RULES, STATUS_ERR_BAD_LEN);
                            end else if (processor_busy_i) begin
                                init_resp(CMD_CLEAR_ALL_RULES, STATUS_ERR_BUSY);
                            end else begin
                                rule_clear_all_o <= 1'b1;
                            end
                            state_q <= CP_WAIT_RESP;
                        end

                        CMD_READ_RULE: begin
                            if (recv_len_q != 16'd2) begin
                                init_resp(CMD_READ_RULE, STATUS_ERR_BAD_LEN);
                            end else if (get_cmd_byte(cmd_buf_q, 16'd1) >= RULE_COUNT) begin
                                init_resp(CMD_READ_RULE, STATUS_ERR_RULE_IDX);
                            end else begin
                                resp_buf_q[(2*8)+:8] <= get_cmd_byte(cmd_buf_q, 16'd1);
                                for (idx = 0; idx < RULE_IMAGE_W/8; idx++) begin
                                    resp_buf_q[((idx + 3) * 8)+:8] <= rule_read_data_i[(idx*8)+:8];
                                end
                                resp_len_o <= 16'd27;
                            end
                            state_q <= CP_WAIT_RESP;
                        end

                        CMD_SET_DEFAULT_ACTION: begin
                            if (recv_len_q != 16'd2) begin
                                init_resp(CMD_SET_DEFAULT_ACTION, STATUS_ERR_BAD_LEN);
                            end else if (get_cmd_byte(cmd_buf_q, 16'd1) > ACTION_COUNT_ONLY) begin
                                init_resp(CMD_SET_DEFAULT_ACTION, STATUS_ERR_BAD_PARAM);
                            end else begin
                                default_action_o <= get_cmd_byte(cmd_buf_q, 16'd1);
                            end
                            state_q <= CP_WAIT_RESP;
                        end

                        CMD_SET_VERBOSE: begin
                            if (recv_len_q != 16'd2) begin
                                init_resp(CMD_SET_VERBOSE, STATUS_ERR_BAD_LEN);
                            end else begin
                                verbose_o <= (get_cmd_byte(cmd_buf_q, 16'd1) != 8'h00);
                            end
                            state_q <= CP_WAIT_RESP;
                        end

                        CMD_READ_COUNTERS: begin
                            counter_idx_q      <= '0;
                            stats_read_index_o <= '0;
                            state_q            <= CP_BUILD_COUNTERS;
                        end

                        CMD_READ_LAST_RESULT: begin
                            for (idx = 0; idx < RESULT_BYTES; idx++) begin
                                resp_buf_q[((idx + 2) * 8)+:8] <= last_result_i[(idx*8)+:8];
                            end
                            resp_len_o <= 16'd22;
                            state_q    <= CP_WAIT_RESP;
                        end

                        CMD_READ_STATUS: begin
                            resp_buf_q[(2*8)+:8] <= mode_o;
                            resp_buf_q[(3*8)+:8] <= {7'd0, verbose_o};
                            resp_buf_q[(4*8)+:8] <= default_action_o;
                            resp_buf_q[(5*8)+:8] <= {7'd0, processor_busy_i};
                            resp_len_o <= 16'd6;
                            state_q    <= CP_WAIT_RESP;
                        end

                        default: begin
                            init_resp(get_cmd_byte(cmd_buf_q, 16'd0), STATUS_ERR_BAD_OPCODE);
                            state_q <= CP_WAIT_RESP;
                        end
                    endcase
                end

                CP_BUILD_COUNTERS: begin
                    resp_buf_q[((counter_idx_q * 4 + 2) * 8)+:8] <= stats_read_data_i[31:24];
                    resp_buf_q[((counter_idx_q * 4 + 3) * 8)+:8] <= stats_read_data_i[23:16];
                    resp_buf_q[((counter_idx_q * 4 + 4) * 8)+:8] <= stats_read_data_i[15:8];
                    resp_buf_q[((counter_idx_q * 4 + 5) * 8)+:8] <= stats_read_data_i[7:0];
                    if (counter_idx_q == (COUNTER_COUNT - 1)) begin
                        resp_len_o <= 16'd2 + (COUNTER_COUNT * 16'd4);
                        state_q    <= CP_WAIT_RESP;
                    end else begin
                        counter_idx_q      <= counter_idx_q + 1'b1;
                        stats_read_index_o <= counter_idx_q + 1'b1;
                    end
                end

                CP_WAIT_RESP: begin
                    resp_valid_o <= 1'b1;
                    if (resp_valid_o && resp_ready_i) begin
                        resp_valid_o <= 1'b0;
                        state_q      <= CP_IDLE;
                    end
                end

                default: state_q <= CP_IDLE;
            endcase
        end
    end
endmodule
