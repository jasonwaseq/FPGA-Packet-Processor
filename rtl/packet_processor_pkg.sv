package packet_processor_pkg;
    localparam int unsigned CLK_HZ = 12_000_000;
    localparam int unsigned UART_BAUD_DEFAULT = 1_500_000;
    localparam int unsigned UART_CLKS_PER_BIT_DEFAULT = 8;

    localparam int unsigned MAX_FRAME_PAYLOAD = 252;
    localparam int unsigned MAX_PACKET_BYTES = 240;
    localparam int unsigned PACKET_HEADER_BYTES = 20;
    localparam int unsigned RULE_COUNT = 8;
    localparam int unsigned RULE_IMAGE_BYTES = 24;
    localparam int unsigned RULE_IMAGE_W = RULE_IMAGE_BYTES * 8;
    localparam int unsigned RESULT_BYTES = 20;
    localparam int unsigned COUNTER_COUNT = 23;

    localparam logic [7:0] FRAME_FLAG = 8'h7E;
    localparam logic [7:0] FRAME_ESCAPE = 8'h7D;
    localparam logic [7:0] PROTOCOL_VERSION = 8'h01;

    localparam logic [7:0] MSG_TYPE_CMD_REQ     = 8'h01;
    localparam logic [7:0] MSG_TYPE_CMD_RESP    = 8'h02;
    localparam logic [7:0] MSG_TYPE_DATA_PACKET = 8'h10;
    localparam logic [7:0] MSG_TYPE_PKT_RESULT  = 8'h11;
    localparam logic [7:0] MSG_TYPE_PKT_FORWARD = 8'h12;
    localparam logic [7:0] MSG_TYPE_EVENT       = 8'h13;

    localparam logic [7:0] MODE_INSPECT   = 8'd0;
    localparam logic [7:0] MODE_INLINE    = 8'd1;
    localparam logic [7:0] MODE_BENCHMARK = 8'd2;

    localparam logic [7:0] ACTION_DROP       = 8'd0;
    localparam logic [7:0] ACTION_ACCEPT     = 8'd1;
    localparam logic [7:0] ACTION_COUNT_ONLY = 8'd2;
    localparam logic [7:0] ACTION_REWRITE    = 8'd3;

    localparam logic [7:0] STATUS_OK            = 8'd0;
    localparam logic [7:0] STATUS_ERR_BAD_OPCODE= 8'd1;
    localparam logic [7:0] STATUS_ERR_BAD_LEN   = 8'd2;
    localparam logic [7:0] STATUS_ERR_BAD_PARAM = 8'd3;
    localparam logic [7:0] STATUS_ERR_BUSY      = 8'd4;
    localparam logic [7:0] STATUS_ERR_RULE_IDX  = 8'd5;
    localparam logic [7:0] STATUS_ERR_MODE      = 8'd6;
    localparam logic [7:0] STATUS_ERR_INTERNAL  = 8'd7;

    localparam logic [7:0] CMD_PING               = 8'h00;
    localparam logic [7:0] CMD_GET_INFO           = 8'h01;
    localparam logic [7:0] CMD_SOFT_RESET         = 8'h02;
    localparam logic [7:0] CMD_CLEAR_COUNTERS     = 8'h03;
    localparam logic [7:0] CMD_SET_MODE           = 8'h04;
    localparam logic [7:0] CMD_GET_MODE           = 8'h05;
    localparam logic [7:0] CMD_WRITE_RULE         = 8'h10;
    localparam logic [7:0] CMD_CLEAR_RULE         = 8'h11;
    localparam logic [7:0] CMD_CLEAR_ALL_RULES    = 8'h12;
    localparam logic [7:0] CMD_READ_RULE          = 8'h13;
    localparam logic [7:0] CMD_SET_DEFAULT_ACTION = 8'h14;
    localparam logic [7:0] CMD_SET_VERBOSE        = 8'h15;
    localparam logic [7:0] CMD_READ_COUNTERS      = 8'h20;
    localparam logic [7:0] CMD_READ_LAST_RESULT   = 8'h21;
    localparam logic [7:0] CMD_READ_STATUS        = 8'h22;

    localparam logic [3:0] PARSE_ERR_NONE          = 4'd0;
    localparam logic [3:0] PARSE_ERR_SHORT         = 4'd1;
    localparam logic [3:0] PARSE_ERR_VERSION       = 4'd2;
    localparam logic [3:0] PARSE_ERR_HDRLEN        = 4'd3;
    localparam logic [3:0] PARSE_ERR_TTL           = 4'd4;
    localparam logic [3:0] PARSE_ERR_LENGTH        = 4'd5;
    localparam logic [3:0] PARSE_ERR_HDR_CHECKSUM  = 4'd6;

    localparam logic [7:0] RESULT_FLAG_PARSE_OK       = 8'h01;
    localparam logic [7:0] RESULT_FLAG_MATCHED        = 8'h02;
    localparam logic [7:0] RESULT_FLAG_DROPPED        = 8'h04;
    localparam logic [7:0] RESULT_FLAG_REWRITTEN      = 8'h08;
    localparam logic [7:0] RESULT_FLAG_CHECKSUM_OK    = 8'h10;
    localparam logic [7:0] RESULT_FLAG_DEFAULT_ACTION = 8'h20;
    localparam logic [7:0] RESULT_FLAG_VERBOSE        = 8'h40;

    localparam int unsigned COUNTER_RX_FRAMES_OK        = 0;
    localparam int unsigned COUNTER_DATA_PACKETS_OK     = 1;
    localparam int unsigned COUNTER_PACKETS_ACCEPTED    = 2;
    localparam int unsigned COUNTER_PACKETS_DROPPED     = 3;
    localparam int unsigned COUNTER_PACKETS_COUNT_ONLY  = 4;
    localparam int unsigned COUNTER_PARSE_ERRORS        = 5;
    localparam int unsigned COUNTER_HDR_CHECKSUM_ERRORS = 6;
    localparam int unsigned COUNTER_TRANSPORT_CRC_ERRS  = 7;
    localparam int unsigned COUNTER_TRANSPORT_LEN_ERRS  = 8;
    localparam int unsigned COUNTER_INGRESS_OVERFLOWS   = 9;
    localparam int unsigned COUNTER_BYTES_PROCESSED     = 10;
    localparam int unsigned COUNTER_TRANSFORMED_PACKETS = 11;
    localparam int unsigned COUNTER_LAST_LATENCY        = 12;
    localparam int unsigned COUNTER_MAX_LATENCY         = 13;
    localparam int unsigned COUNTER_BUSY_CYCLES         = 14;
    localparam int unsigned COUNTER_RULE_HIT_BASE       = 15;

    function automatic logic [15:0] crc16_ccitt_next(
        input logic [15:0] crc_in,
        input logic [7:0]  data_in
    );
        logic [15:0] crc;
        int i;
        begin
            crc = crc_in ^ {data_in, 8'h00};
            for (i = 0; i < 8; i++) begin
                if (crc[15]) begin
                    crc = (crc << 1) ^ 16'h1021;
                end else begin
                    crc = (crc << 1);
                end
            end
            crc16_ccitt_next = crc;
        end
    endfunction

    function automatic logic [15:0] ones_add16(
        input logic [15:0] a,
        input logic [15:0] b
    );
        logic [16:0] tmp;
        begin
            tmp = a + b;
            ones_add16 = tmp[15:0] + tmp[16];
        end
    endfunction

    function automatic logic [31:0] sat_inc32(
        input logic [31:0] value,
        input logic [31:0] amount
    );
        logic [32:0] sum_ext;
        begin
            sum_ext = {1'b0, value} + {1'b0, amount};
            if (sum_ext[32]) begin
                sat_inc32 = 32'hFFFF_FFFF;
            end else begin
                sat_inc32 = sum_ext[31:0];
            end
        end
    endfunction

    function automatic logic [31:0] sat_set_max32(
        input logic [31:0] current_value,
        input logic [31:0] candidate
    );
        begin
            if (candidate > current_value) begin
                sat_set_max32 = candidate;
            end else begin
                sat_set_max32 = current_value;
            end
        end
    endfunction

    function automatic logic [RULE_IMAGE_W-1:0] rule_clear_image();
        begin
            rule_clear_image = '0;
        end
    endfunction
endpackage
