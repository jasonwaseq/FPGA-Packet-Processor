module statistics_block #(
    parameter int unsigned COUNTER_COUNT = packet_processor_pkg::COUNTER_COUNT
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       clear_i,
    input  logic       busy_i,
    input  logic       rx_frame_ok_i,
    input  logic       data_packet_ok_i,
    input  logic       packet_accepted_i,
    input  logic       packet_dropped_i,
    input  logic       packet_count_only_i,
    input  logic       parse_error_i,
    input  logic       header_checksum_error_i,
    input  logic       transport_crc_error_i,
    input  logic       transport_length_error_i,
    input  logic       ingress_overflow_i,
    input  logic       transformed_packet_i,
    input  logic       bytes_processed_valid_i,
    input  logic [15:0] bytes_processed_i,
    input  logic       latency_valid_i,
    input  logic [31:0] latency_cycles_i,
    input  logic       rule_hit_valid_i,
    input  logic [2:0] rule_hit_index_i,
    input  logic [4:0] read_index_i,
    output logic [31:0] read_counter_o
);
    localparam int unsigned COUNTER_BUSY_CYCLES = packet_processor_pkg::COUNTER_BUSY_CYCLES;
    localparam int unsigned COUNTER_RX_FRAMES_OK = packet_processor_pkg::COUNTER_RX_FRAMES_OK;
    localparam int unsigned COUNTER_DATA_PACKETS_OK = packet_processor_pkg::COUNTER_DATA_PACKETS_OK;
    localparam int unsigned COUNTER_PACKETS_ACCEPTED = packet_processor_pkg::COUNTER_PACKETS_ACCEPTED;
    localparam int unsigned COUNTER_PACKETS_DROPPED = packet_processor_pkg::COUNTER_PACKETS_DROPPED;
    localparam int unsigned COUNTER_PACKETS_COUNT_ONLY = packet_processor_pkg::COUNTER_PACKETS_COUNT_ONLY;
    localparam int unsigned COUNTER_PARSE_ERRORS = packet_processor_pkg::COUNTER_PARSE_ERRORS;
    localparam int unsigned COUNTER_HDR_CHECKSUM_ERRORS = packet_processor_pkg::COUNTER_HDR_CHECKSUM_ERRORS;
    localparam int unsigned COUNTER_TRANSPORT_CRC_ERRS = packet_processor_pkg::COUNTER_TRANSPORT_CRC_ERRS;
    localparam int unsigned COUNTER_TRANSPORT_LEN_ERRS = packet_processor_pkg::COUNTER_TRANSPORT_LEN_ERRS;
    localparam int unsigned COUNTER_INGRESS_OVERFLOWS = packet_processor_pkg::COUNTER_INGRESS_OVERFLOWS;
    localparam int unsigned COUNTER_BYTES_PROCESSED = packet_processor_pkg::COUNTER_BYTES_PROCESSED;
    localparam int unsigned COUNTER_TRANSFORMED_PACKETS = packet_processor_pkg::COUNTER_TRANSFORMED_PACKETS;
    localparam int unsigned COUNTER_LAST_LATENCY = packet_processor_pkg::COUNTER_LAST_LATENCY;
    localparam int unsigned COUNTER_MAX_LATENCY = packet_processor_pkg::COUNTER_MAX_LATENCY;
    localparam int unsigned COUNTER_RULE_HIT_BASE = packet_processor_pkg::COUNTER_RULE_HIT_BASE;

    logic [31:0] counters_q [0:COUNTER_COUNT-1];
    integer idx;

    function automatic logic [31:0] sat_inc32_local(
        input logic [31:0] value,
        input logic [31:0] amount
    );
        logic [32:0] sum_ext;
        begin
            sum_ext = {1'b0, value} + {1'b0, amount};
            if (sum_ext[32]) begin
                sat_inc32_local = 32'hFFFF_FFFF;
            end else begin
                sat_inc32_local = sum_ext[31:0];
            end
        end
    endfunction

    function automatic logic [31:0] sat_set_max32_local(
        input logic [31:0] current_value,
        input logic [31:0] candidate
    );
        begin
            if (candidate > current_value) begin
                sat_set_max32_local = candidate;
            end else begin
                sat_set_max32_local = current_value;
            end
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx = 0; idx < COUNTER_COUNT; idx++) begin
                counters_q[idx] <= 32'd0;
            end
        end else begin
            if (clear_i) begin
                for (idx = 0; idx < COUNTER_COUNT; idx++) begin
                    counters_q[idx] <= 32'd0;
                end
            end else begin
                if (busy_i) begin
                    counters_q[COUNTER_BUSY_CYCLES] <= sat_inc32_local(counters_q[COUNTER_BUSY_CYCLES], 32'd1);
                end
                if (rx_frame_ok_i) begin
                    counters_q[COUNTER_RX_FRAMES_OK] <= sat_inc32_local(counters_q[COUNTER_RX_FRAMES_OK], 32'd1);
                end
                if (data_packet_ok_i) begin
                    counters_q[COUNTER_DATA_PACKETS_OK] <= sat_inc32_local(counters_q[COUNTER_DATA_PACKETS_OK], 32'd1);
                end
                if (packet_accepted_i) begin
                    counters_q[COUNTER_PACKETS_ACCEPTED] <= sat_inc32_local(counters_q[COUNTER_PACKETS_ACCEPTED], 32'd1);
                end
                if (packet_dropped_i) begin
                    counters_q[COUNTER_PACKETS_DROPPED] <= sat_inc32_local(counters_q[COUNTER_PACKETS_DROPPED], 32'd1);
                end
                if (packet_count_only_i) begin
                    counters_q[COUNTER_PACKETS_COUNT_ONLY] <= sat_inc32_local(counters_q[COUNTER_PACKETS_COUNT_ONLY], 32'd1);
                end
                if (parse_error_i) begin
                    counters_q[COUNTER_PARSE_ERRORS] <= sat_inc32_local(counters_q[COUNTER_PARSE_ERRORS], 32'd1);
                end
                if (header_checksum_error_i) begin
                    counters_q[COUNTER_HDR_CHECKSUM_ERRORS] <= sat_inc32_local(counters_q[COUNTER_HDR_CHECKSUM_ERRORS], 32'd1);
                end
                if (transport_crc_error_i) begin
                    counters_q[COUNTER_TRANSPORT_CRC_ERRS] <= sat_inc32_local(counters_q[COUNTER_TRANSPORT_CRC_ERRS], 32'd1);
                end
                if (transport_length_error_i) begin
                    counters_q[COUNTER_TRANSPORT_LEN_ERRS] <= sat_inc32_local(counters_q[COUNTER_TRANSPORT_LEN_ERRS], 32'd1);
                end
                if (ingress_overflow_i) begin
                    counters_q[COUNTER_INGRESS_OVERFLOWS] <= sat_inc32_local(counters_q[COUNTER_INGRESS_OVERFLOWS], 32'd1);
                end
                if (transformed_packet_i) begin
                    counters_q[COUNTER_TRANSFORMED_PACKETS] <= sat_inc32_local(counters_q[COUNTER_TRANSFORMED_PACKETS], 32'd1);
                end
                if (bytes_processed_valid_i) begin
                    counters_q[COUNTER_BYTES_PROCESSED] <= sat_inc32_local(counters_q[COUNTER_BYTES_PROCESSED], {16'd0, bytes_processed_i});
                end
                if (latency_valid_i) begin
                    counters_q[COUNTER_LAST_LATENCY] <= latency_cycles_i;
                    counters_q[COUNTER_MAX_LATENCY]  <= sat_set_max32_local(counters_q[COUNTER_MAX_LATENCY], latency_cycles_i);
                end
                if (rule_hit_valid_i) begin
                    counters_q[COUNTER_RULE_HIT_BASE + rule_hit_index_i] <= sat_inc32_local(
                        counters_q[COUNTER_RULE_HIT_BASE + rule_hit_index_i],
                        32'd1
                    );
                end
            end
        end
    end

    assign read_counter_o = counters_q[read_index_i];
endmodule
