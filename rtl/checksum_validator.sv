module checksum_validator (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start_i,
    input  logic       valid_i,
    input  logic       last_i,
    input  logic [7:0] data_i,
    output logic [15:0] sum_o,
    output logic       done_o,
    output logic       checksum_ok_o
);
    logic [15:0] sum_q;
    logic        byte_phase_q;
    logic [7:0]  high_byte_q;

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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_q         <= 16'h0000;
            byte_phase_q  <= 1'b0;
            high_byte_q   <= 8'h00;
            done_o        <= 1'b0;
            checksum_ok_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (start_i) begin
                sum_q         <= 16'h0000;
                byte_phase_q  <= 1'b0;
                high_byte_q   <= 8'h00;
                checksum_ok_o <= 1'b0;
            end

            if (valid_i) begin
                if (!byte_phase_q) begin
                    high_byte_q  <= data_i;
                    byte_phase_q <= 1'b1;
                    if (last_i) begin
                        done_o        <= 1'b1;
                        checksum_ok_o <= (ones_add16_local(sum_q, {data_i, 8'h00}) == 16'hFFFF);
                        byte_phase_q  <= 1'b0;
                    end
                end else begin
                    sum_q        <= ones_add16_local(sum_q, {high_byte_q, data_i});
                    byte_phase_q <= 1'b0;
                    if (last_i) begin
                        done_o        <= 1'b1;
                        checksum_ok_o <= (ones_add16_local(sum_q, {high_byte_q, data_i}) == 16'hFFFF);
                    end
                end
            end
        end
    end

    assign sum_o = sum_q;
endmodule
