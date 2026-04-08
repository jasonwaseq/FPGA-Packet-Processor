module uart_frame_decoder #(
    parameter int unsigned MAX_FRAME_PAYLOAD = packet_processor_pkg::MAX_FRAME_PAYLOAD,
    parameter int unsigned QUEUE_DEPTH = 2
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] data_i,
    input  logic       valid_i,
    output logic       frame_valid_o,
    input  logic       frame_ready_i,
    output logic [7:0] frame_type_o,
    output logic [7:0] frame_flags_o,
    output logic [7:0] frame_seq_o,
    output logic [15:0] frame_len_o,
    output logic [7:0] payload_data_o,
    output logic       payload_valid_o,
    output logic       payload_sop_o,
    output logic       payload_eop_o,
    input  logic       payload_ready_i,
    output logic       rx_frame_ok_o,
    output logic       crc_error_o,
    output logic       length_error_o,
    output logic       overflow_o
);
    localparam logic [7:0] FRAME_FLAG = packet_processor_pkg::FRAME_FLAG;
    localparam logic [7:0] FRAME_ESCAPE = packet_processor_pkg::FRAME_ESCAPE;
    localparam logic [7:0] PROTOCOL_VERSION = packet_processor_pkg::PROTOCOL_VERSION;

    localparam int unsigned MAX_STORED_BYTES = MAX_FRAME_PAYLOAD + 8;
    localparam int unsigned PTR_W = $clog2(MAX_STORED_BYTES + 1);

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

    typedef enum logic [1:0] {
        RX_SEARCH,
        RX_COLLECT,
        RX_ESCAPED,
        RX_DROP
    } rx_state_t;

    typedef enum logic {
        OUT_IDLE,
        OUT_STREAM
    } out_state_t;

    logic [7:0] frame_mem [0:QUEUE_DEPTH-1][0:MAX_STORED_BYTES-1];
    logic [7:0] frame_type_q [0:QUEUE_DEPTH-1];
    logic [7:0] frame_flags_q[0:QUEUE_DEPTH-1];
    logic [7:0] frame_seq_q  [0:QUEUE_DEPTH-1];
    logic [15:0] frame_len_q [0:QUEUE_DEPTH-1];
    logic        slot_valid_q[0:QUEUE_DEPTH-1];
    logic        queue_slot_q[0:QUEUE_DEPTH-1];

    rx_state_t rx_state_q;
    out_state_t out_state_q;
    logic       collect_slot_q;
    logic [PTR_W-1:0] collect_count_q;
    logic [15:0] expected_total_q;
    logic       length_known_q;
    logic [15:0] crc_calc_q;
    logic [7:0]  head_ptr_q;
    logic [7:0]  tail_ptr_q;
    logic [1:0]  queue_count_q;
    logic [15:0] payload_index_q;
    logic [7:0]  current_slot;
    logic [7:0]  alloc_slot;
    logic        alloc_valid;
    integer idx;

    function automatic logic slot_in_use(input int unsigned slot_idx);
        begin
            slot_in_use = slot_valid_q[slot_idx] ||
                          (((rx_state_q == RX_COLLECT) || (rx_state_q == RX_ESCAPED)) && (collect_slot_q == slot_idx));
        end
    endfunction

    always_comb begin
        if (!slot_in_use(0)) begin
            alloc_valid = 1'b1;
            alloc_slot  = 8'd0;
        end else if (!slot_in_use(1)) begin
            alloc_valid = 1'b1;
            alloc_slot  = 8'd1;
        end else begin
            alloc_valid = 1'b0;
            alloc_slot  = 8'd0;
        end
    end

    assign current_slot   = queue_slot_q[head_ptr_q[0]];
    assign frame_valid_o   = (out_state_q == OUT_IDLE) && (queue_count_q != 0);
    assign frame_type_o    = frame_type_q[current_slot];
    assign frame_flags_o   = frame_flags_q[current_slot];
    assign frame_seq_o     = frame_seq_q[current_slot];
    assign frame_len_o     = frame_len_q[current_slot];
    assign payload_valid_o = (out_state_q == OUT_STREAM);
    assign payload_data_o  = frame_mem[current_slot][payload_index_q + 16'd6];
    assign payload_sop_o   = (payload_index_q == 16'd0);
    assign payload_eop_o   = (payload_index_q == (frame_len_q[current_slot] - 1'b1));

    task automatic start_collection;
        begin
            collect_count_q  <= '0;
            expected_total_q <= 16'd0;
            length_known_q   <= 1'b0;
            crc_calc_q       <= 16'hFFFF;
            if (alloc_valid) begin
                collect_slot_q <= alloc_slot[0];
                rx_state_q     <= RX_COLLECT;
            end else begin
                rx_state_q     <= RX_DROP;
                overflow_o     <= 1'b1;
            end
        end
    endtask

    task automatic commit_frame;
        logic [15:0] received_crc;
        logic [15:0] payload_len;
        begin
            if (!length_known_q || (collect_count_q < 8) || (collect_count_q != expected_total_q)) begin
                length_error_o <= 1'b1;
            end else begin
                payload_len   = {frame_mem[collect_slot_q][4], frame_mem[collect_slot_q][5]};
                received_crc  = {frame_mem[collect_slot_q][collect_count_q - 2], frame_mem[collect_slot_q][collect_count_q - 1]};
                if (frame_mem[collect_slot_q][0] != PROTOCOL_VERSION) begin
                    length_error_o <= 1'b1;
                end else if (received_crc != crc_calc_q) begin
                    crc_error_o <= 1'b1;
                end else begin
                    frame_type_q[collect_slot_q]  <= frame_mem[collect_slot_q][1];
                    frame_flags_q[collect_slot_q] <= frame_mem[collect_slot_q][2];
                    frame_seq_q[collect_slot_q]   <= frame_mem[collect_slot_q][3];
                    frame_len_q[collect_slot_q]   <= payload_len;
                    slot_valid_q[collect_slot_q]  <= 1'b1;
                    queue_slot_q[tail_ptr_q[0]]   <= collect_slot_q;
                    tail_ptr_q                    <= tail_ptr_q + 1'b1;
                    queue_count_q                 <= queue_count_q + 1'b1;
                    rx_frame_ok_o                 <= 1'b1;
                end
            end
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state_q      <= RX_SEARCH;
            out_state_q     <= OUT_IDLE;
            collect_slot_q  <= 1'b0;
            collect_count_q <= '0;
            expected_total_q<= '0;
            length_known_q  <= 1'b0;
            crc_calc_q      <= 16'hFFFF;
            head_ptr_q      <= '0;
            tail_ptr_q      <= '0;
            queue_count_q   <= '0;
            payload_index_q <= '0;
            rx_frame_ok_o   <= 1'b0;
            crc_error_o     <= 1'b0;
            length_error_o  <= 1'b0;
            overflow_o      <= 1'b0;
            for (idx = 0; idx < QUEUE_DEPTH; idx++) begin
                slot_valid_q[idx] <= 1'b0;
                queue_slot_q[idx] <= 1'b0;
                frame_type_q[idx] <= 8'h00;
                frame_flags_q[idx]<= 8'h00;
                frame_seq_q[idx]  <= 8'h00;
                frame_len_q[idx]  <= 16'h0000;
            end
        end else begin
            rx_frame_ok_o  <= 1'b0;
            crc_error_o    <= 1'b0;
            length_error_o <= 1'b0;
            overflow_o     <= 1'b0;

            if (valid_i) begin
                case (rx_state_q)
                    RX_SEARCH: begin
                        if (data_i == FRAME_FLAG) begin
                            start_collection();
                        end
                    end

                    RX_COLLECT: begin
                        if (data_i == FRAME_FLAG) begin
                            if (collect_count_q != 0) begin
                                commit_frame();
                            end
                            start_collection();
                        end else if (data_i == FRAME_ESCAPE) begin
                            rx_state_q <= RX_ESCAPED;
                        end else begin
                            if (collect_count_q >= MAX_STORED_BYTES) begin
                                length_error_o <= 1'b1;
                                rx_state_q     <= RX_DROP;
                            end else begin
                                frame_mem[collect_slot_q][collect_count_q] <= data_i;
                                if ((collect_count_q < 6) ||
                                    (length_known_q && (collect_count_q < (expected_total_q - 16'd2)))) begin
                                    crc_calc_q <= crc16_ccitt_next_local(crc_calc_q, data_i);
                                end
                                if (collect_count_q == 5) begin
                                    expected_total_q <= {frame_mem[collect_slot_q][4], data_i} + 16'd8;
                                    length_known_q   <= ({frame_mem[collect_slot_q][4], data_i} <= MAX_FRAME_PAYLOAD);
                                end
                                collect_count_q <= collect_count_q + 1'b1;
                            end
                        end
                    end

                    RX_ESCAPED: begin
                        if (collect_count_q >= MAX_STORED_BYTES) begin
                            length_error_o <= 1'b1;
                            rx_state_q     <= RX_DROP;
                        end else begin
                            frame_mem[collect_slot_q][collect_count_q] <= data_i ^ 8'h20;
                            if ((collect_count_q < 6) ||
                                (length_known_q && (collect_count_q < (expected_total_q - 16'd2)))) begin
                                crc_calc_q <= crc16_ccitt_next_local(crc_calc_q, data_i ^ 8'h20);
                            end
                            if (collect_count_q == 5) begin
                                expected_total_q <= {frame_mem[collect_slot_q][4], (data_i ^ 8'h20)} + 16'd8;
                                length_known_q   <= ({frame_mem[collect_slot_q][4], (data_i ^ 8'h20)} <= MAX_FRAME_PAYLOAD);
                            end
                            collect_count_q <= collect_count_q + 1'b1;
                            rx_state_q      <= RX_COLLECT;
                        end
                    end

                    RX_DROP: begin
                        if (data_i == FRAME_FLAG) begin
                            start_collection();
                        end
                    end

                    default: rx_state_q <= RX_SEARCH;
                endcase
            end

            case (out_state_q)
                OUT_IDLE: begin
                    if (frame_valid_o && frame_ready_i) begin
                        if (frame_len_q[current_slot] == 16'd0) begin
                            slot_valid_q[current_slot] <= 1'b0;
                            head_ptr_q  <= head_ptr_q + 1'b1;
                            queue_count_q <= queue_count_q - 1'b1;
                        end else begin
                            payload_index_q <= 16'd0;
                            out_state_q     <= OUT_STREAM;
                        end
                    end
                end

                OUT_STREAM: begin
                    if (payload_ready_i) begin
                        if (payload_index_q == (frame_len_q[current_slot] - 1'b1)) begin
                            slot_valid_q[current_slot] <= 1'b0;
                            head_ptr_q    <= head_ptr_q + 1'b1;
                            queue_count_q <= queue_count_q - 1'b1;
                            payload_index_q <= '0;
                            out_state_q   <= OUT_IDLE;
                        end else begin
                            payload_index_q <= payload_index_q + 1'b1;
                        end
                    end
                end

                default: out_state_q <= OUT_IDLE;
            endcase
        end
    end
endmodule
