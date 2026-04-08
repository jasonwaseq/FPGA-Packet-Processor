`timescale 1ns/1ps

module dut_classifier_engine #(
    parameter int unsigned RULE_IMAGE_W = packet_processor_pkg::RULE_IMAGE_W
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       write_valid_i,
    input  logic [2:0] write_index_i,
    input  logic [RULE_IMAGE_W-1:0] write_rule_i,
    input  logic       start_i,
    input  logic [7:0] protocol_i,
    input  logic [15:0] src_addr_i,
    input  logic [15:0] dst_addr_i,
    input  logic [15:0] src_port_i,
    input  logic [15:0] dst_port_i,
    input  logic [7:0] default_action_i,
    output logic       done_o,
    output logic       matched_o,
    output logic [2:0] matched_rule_o,
    output logic [7:0] action_o,
    output logic [3:0] rewrite_en_o,
    output logic [7:0] rewrite_flags_o,
    output logic [15:0] rewrite_dst_addr_o,
    output logic [15:0] rewrite_dst_port_o
);
    logic [2:0] lookup_index;
    logic [RULE_IMAGE_W-1:0] lookup_rule;

    rule_table u_rules (
        .clk(clk),
        .rst_n(rst_n),
        .write_valid_i(write_valid_i),
        .write_index_i(write_index_i),
        .write_rule_i(write_rule_i),
        .clear_rule_i(1'b0),
        .clear_rule_index_i('0),
        .clear_all_i(1'b0),
        .lookup_index_i(lookup_index),
        .lookup_rule_o(lookup_rule),
        .read_index_i('0),
        .read_rule_o()
    );

    classifier_engine u_classifier (
        .clk(clk),
        .rst_n(rst_n),
        .start_i(start_i),
        .protocol_i(protocol_i),
        .src_addr_i(src_addr_i),
        .dst_addr_i(dst_addr_i),
        .src_port_i(src_port_i),
        .dst_port_i(dst_port_i),
        .lookup_index_o(lookup_index),
        .lookup_rule_i(lookup_rule),
        .default_action_i(default_action_i),
        .done_o(done_o),
        .matched_o(matched_o),
        .matched_rule_o(matched_rule_o),
        .action_o(action_o),
        .rewrite_en_o(rewrite_en_o),
        .rewrite_flags_o(rewrite_flags_o),
        .rewrite_dst_addr_o(rewrite_dst_addr_o),
        .rewrite_dst_port_o(rewrite_dst_port_o)
    );
endmodule
