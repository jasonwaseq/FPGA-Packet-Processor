`timescale 1ns/1ps

module dut_frame_codec #(
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
    input  logic       frame_ready_i,
    input  logic       payload_ready_i,
    output logic       done_o,
    output logic       frame_valid_o,
    output logic [7:0] frame_type_o,
    output logic [7:0] frame_flags_o,
    output logic [7:0] frame_seq_o,
    output logic [15:0] frame_len_o,
    output logic [7:0] payload_data_o,
    output logic       payload_valid_o,
    output logic       payload_sop_o,
    output logic       payload_eop_o
);
    logic [7:0] enc_data;
    logic       enc_valid;

    uart_frame_encoder #(
        .MAX_FRAME_PAYLOAD(MAX_FRAME_PAYLOAD)
    ) u_enc (
        .clk(clk),
        .rst_n(rst_n),
        .start_i(start_i),
        .msg_type_i(msg_type_i),
        .flags_i(flags_i),
        .seq_i(seq_i),
        .payload_len_i(payload_len_i),
        .payload_i(payload_i),
        .ready_o(),
        .busy_o(),
        .tx_data_o(enc_data),
        .tx_valid_o(enc_valid),
        .tx_ready_i(1'b1),
        .done_o(done_o)
    );

    uart_frame_decoder #(
        .MAX_FRAME_PAYLOAD(MAX_FRAME_PAYLOAD)
    ) u_dec (
        .clk(clk),
        .rst_n(rst_n),
        .data_i(enc_data),
        .valid_i(enc_valid),
        .frame_valid_o(frame_valid_o),
        .frame_ready_i(frame_ready_i),
        .frame_type_o(frame_type_o),
        .frame_flags_o(frame_flags_o),
        .frame_seq_o(frame_seq_o),
        .frame_len_o(frame_len_o),
        .payload_data_o(payload_data_o),
        .payload_valid_o(payload_valid_o),
        .payload_sop_o(payload_sop_o),
        .payload_eop_o(payload_eop_o),
        .payload_ready_i(payload_ready_i),
        .rx_frame_ok_o(),
        .crc_error_o(),
        .length_error_o(),
        .overflow_o()
    );
endmodule
