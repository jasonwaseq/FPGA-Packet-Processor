module packet_ingress_adapter #(
    parameter int unsigned MAX_PACKET_BYTES = packet_processor_pkg::MAX_PACKET_BYTES
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] in_data_i,
    input  logic       in_valid_i,
    input  logic       in_sop_i,
    input  logic       in_eop_i,
    output logic       in_ready_o,
    output logic       packet_available_o,
    output logic [15:0] packet_len_o,
    input  logic       clear_i,
    input  logic       read_start_i,
    output logic [7:0] read_data_o,
    output logic       read_valid_o,
    output logic       read_sop_o,
    output logic       read_eop_o,
    input  logic       read_ready_i,
    output logic       read_done_o
);
    logic [7:0] packet_mem [0:MAX_PACKET_BYTES-1];
    logic [15:0] wr_ptr_q;
    logic [15:0] rd_ptr_q;
    logic        write_active_q;
    logic        read_active_q;
    logic [15:0] packet_len_q;
    logic [7:0]  read_data_q;
    logic        read_valid_q;
    logic        read_sop_q;
    logic        read_eop_q;

    assign in_ready_o          = !packet_available_o && (wr_ptr_q < MAX_PACKET_BYTES);
    assign packet_available_o  = (packet_len_q != 16'd0);
    assign packet_len_o        = packet_len_q;
    assign read_data_o         = read_data_q;
    assign read_valid_o        = read_valid_q;
    assign read_sop_o          = read_sop_q;
    assign read_eop_o          = read_eop_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr_q       <= '0;
            rd_ptr_q       <= '0;
            write_active_q <= 1'b0;
            read_active_q  <= 1'b0;
            packet_len_q   <= '0;
            read_data_q    <= '0;
            read_valid_q   <= 1'b0;
            read_sop_q     <= 1'b0;
            read_eop_q     <= 1'b0;
            read_done_o    <= 1'b0;
        end else begin
            read_valid_q <= 1'b0;
            read_sop_q   <= 1'b0;
            read_eop_q   <= 1'b0;
            read_done_o  <= 1'b0;

            if (clear_i) begin
                wr_ptr_q       <= '0;
                rd_ptr_q       <= '0;
                write_active_q <= 1'b0;
                read_active_q  <= 1'b0;
                packet_len_q   <= '0;
            end else begin
                if (in_valid_i && in_ready_o) begin
                    if (in_sop_i) begin
                        wr_ptr_q       <= 16'd0;
                        write_active_q <= 1'b1;
                    end
                    packet_mem[wr_ptr_q] <= in_data_i;
                    wr_ptr_q <= wr_ptr_q + 1'b1;
                    if (in_eop_i) begin
                        packet_len_q   <= wr_ptr_q + 1'b1;
                        write_active_q <= 1'b0;
                    end
                end

                if (read_start_i && packet_available_o) begin
                    rd_ptr_q      <= '0;
                    read_active_q <= 1'b1;
                end

                if (read_active_q && read_ready_i) begin
                    read_data_q  <= packet_mem[rd_ptr_q];
                    read_valid_q <= 1'b1;
                    read_sop_q   <= (rd_ptr_q == 16'd0);
                    read_eop_q   <= (rd_ptr_q == (packet_len_q - 1'b1));
                    if (rd_ptr_q == (packet_len_q - 1'b1)) begin
                        rd_ptr_q      <= '0;
                        read_active_q <= 1'b0;
                        read_done_o   <= 1'b1;
                    end else begin
                        rd_ptr_q <= rd_ptr_q + 1'b1;
                    end
                end
            end
        end
    end
endmodule
