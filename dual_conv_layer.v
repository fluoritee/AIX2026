`timescale 1ns / 1ps

module dual_conv_layer(
    input clk,
    input rstn,

    input        start_i,
    output       done_o,

    output [14:0] in_ram_addrb,
    input  [63:0] in_ram_dob,

    output [1:0]  current_chn,
    
    input  [127:0] win_ch0, win_ch1, win_ch2, win_ch3,
    input signed [15:0] bias_ch0, bias_ch1, bias_ch2, bias_ch3,
    input [3:0] shift_ch0, shift_ch1, shift_ch2, shift_ch3,

    output [31:0] out_pixel0_32b,
    output [31:0] out_pixel1_32b,
    output        out_valid
);

    localparam ST_IDLE = 2'd0, ST_FILL = 2'd1, ST_RUN = 2'd2, ST_DONE = 2'd3;
    reg [1:0] cnn_state;
    reg [8:0] row; // 💡 0 to 256 (257 rows for pipeline flushing)
    reg [7:0] col; // 💡 0 to 128 (129 cols for pipeline flushing)
    reg [1:0] chn;
    reg shift_en;

    // ----------------------------------------------------
    // BRAM Read Logic (Out-of-bounds 방지 및 1클럭 지연 보정)
    // ----------------------------------------------------
    wire [7:0] next_col = (col == 128) ? 8'd0 : col + 1;
    wire [8:0] next_row = (col == 128) ? row + 1 : row;
    wire [8:0] fetch_row = (next_row > 255) ? 9'd255 : next_row;
    wire [7:0] fetch_col = (next_col > 127) ? 8'd127 : next_col;
    
    reg [14:0] my_read_addr;
    assign in_ram_addrb = my_read_addr;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) my_read_addr <= 0;
        else if (cnn_state == ST_IDLE) my_read_addr <= 0;
        else if (cnn_state == ST_FILL) my_read_addr <= fetch_row * 128 + fetch_col;
        else if (cnn_state == ST_RUN && shift_en) my_read_addr <= fetch_row * 128 + fetch_col;
    end

    assign current_chn = chn;
    assign done_o = (cnn_state == ST_DONE);

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            cnn_state <= ST_IDLE;
            row <= 0; col <= 0; chn <= 0; shift_en <= 0;
        end else begin
            case(cnn_state)
                ST_IDLE: if(start_i) cnn_state <= ST_FILL;
                ST_FILL: begin shift_en <= 1; cnn_state <= ST_RUN; end
                ST_RUN: begin
                    if(chn == 2) begin
                        chn <= 0; shift_en <= 1;
                        if(col == 128) begin // 💡 128까지 달려야 마지막 픽셀이 빠져나옵니다.
                            col <= 0;
                            if(row == 256) cnn_state <= ST_DONE; // 💡 256까지 돌아야 마지막 줄이 빠져나옵니다.
                            else row <= row + 1;
                        end else col <= col + 1;
                    end else begin
                        chn <= chn + 1; shift_en <= 0;
                    end
                end
                ST_DONE: if(!start_i) cnn_state <= ST_IDLE;
            endcase
        end
    end

    // ----------------------------------------------------
    // 라인 버퍼 (Line Buffers)
    // ----------------------------------------------------
    reg [31:0] line_buf0_p0 [0:127], line_buf0_p1 [0:127];
    reg [31:0] line_buf1_p0 [0:127], line_buf1_p1 [0:127];
    wire [31:0] in_pixel0 = in_ram_dob[31:0];
    wire [31:0] in_pixel1 = in_ram_dob[63:32];

    always @(posedge clk) begin
        if (shift_en && col < 128) begin
            line_buf0_p0[col] <= in_pixel0; line_buf0_p1[col] <= in_pixel1;
            line_buf1_p0[col] <= line_buf0_p0[col]; line_buf1_p1[col] <= line_buf0_p1[col];
        end
    end

    // ----------------------------------------------------
    // 💡 [가로 밀림 해결] 5-Pixel Sliding Window Pipeline
    // ----------------------------------------------------
    reg [31:0] p0_m1, p0_0, p0_1, p0_2, p0_3;
    reg [31:0] p1_m1, p1_0, p1_1, p1_2, p1_3;
    reg [31:0] p2_m1, p2_0, p2_1, p2_2, p2_3;

    always @(posedge clk) begin
        if (shift_en) begin
            // Top row (row - 2)
            p0_m1 <= p0_1;
            p0_0 <= p0_2; p0_1 <= p0_3;
            p0_2 <= (col < 128) ? line_buf1_p0[col] : 32'd0;
            p0_3 <= (col < 128) ? line_buf1_p1[col] : 32'd0;
            
            // Mid row (row - 1)
            p1_m1 <= p1_1;
            p1_0 <= p1_2; p1_1 <= p1_3;
            p1_2 <= (col < 128) ? line_buf0_p0[col] : 32'd0;
            p1_3 <= (col < 128) ? line_buf0_p1[col] : 32'd0;
            
            // Bot row (row)
            p2_m1 <= p2_1;
            p2_0 <= p2_2; p2_1 <= p2_3;
            p2_2 <= (col < 128) ? in_pixel0 : 32'd0;
            p2_3 <= (col < 128) ? in_pixel1 : 32'd0;
        end
    end

    // ----------------------------------------------------
    // 💡 [세로 밀림 해결] 1클럭 지연된 좌표계(out_row, out_col)로 패딩 매핑
    // ----------------------------------------------------
    wire pad_top = (row == 1); 
    wire pad_bot = (row == 256); 
    wire pad_l0  = (col == 1); 
    wire pad_r1  = (col == 128); 

    // MAC Inputs Mapping (정확하게 센터가 p0_0과 p0_1을 바라보게 교정됨)
    wire [7:0] w0_00 = (pad_top || pad_l0) ? 8'd0 : p0_m1[chn*8 +: 8];
    wire [7:0] w0_01 = (pad_top          ) ? 8'd0 : p0_0[chn*8 +: 8];
    wire [7:0] w0_02 = (pad_top          ) ? 8'd0 : p0_1[chn*8 +: 8];
    wire [7:0] w1_00 = (pad_top          ) ? 8'd0 : p0_0[chn*8 +: 8];
    wire [7:0] w1_01 = (pad_top          ) ? 8'd0 : p0_1[chn*8 +: 8];
    wire [7:0] w1_02 = (pad_top || pad_r1) ? 8'd0 : p0_2[chn*8 +: 8];

    wire [7:0] w0_10 = (pad_l0           ) ? 8'd0 : p1_m1[chn*8 +: 8];
    wire [7:0] w0_11 =                              p1_0[chn*8 +: 8];
    wire [7:0] w0_12 =                              p1_1[chn*8 +: 8];
    wire [7:0] w1_10 =                              p1_0[chn*8 +: 8];
    wire [7:0] w1_11 =                              p1_1[chn*8 +: 8];
    wire [7:0] w1_12 = (pad_r1           ) ? 8'd0 : p1_2[chn*8 +: 8];

    wire [7:0] w0_20 = (pad_bot || pad_l0) ? 8'd0 : p2_m1[chn*8 +: 8];
    wire [7:0] w0_21 = (pad_bot          ) ? 8'd0 : p2_0[chn*8 +: 8];
    wire [7:0] w0_22 = (pad_bot          ) ? 8'd0 : p2_1[chn*8 +: 8];
    wire [7:0] w1_20 = (pad_bot          ) ? 8'd0 : p2_0[chn*8 +: 8];
    wire [7:0] w1_21 = (pad_bot          ) ? 8'd0 : p2_1[chn*8 +: 8];
    wire [7:0] w1_22 = (pad_bot || pad_r1) ? 8'd0 : p2_2[chn*8 +: 8];

    wire [127:0] din0 = {56'd0, w0_22, w0_21, w0_20, w0_12, w0_11, w0_10, w0_02, w0_01, w0_00};
    wire [127:0] din1 = {56'd0, w1_22, w1_21, w1_20, w1_12, w1_11, w1_10, w1_02, w1_01, w1_00};

    // 💡 [유효 픽셀 보호] 쓰레기값이 계산될 땐 MAC을 강제로 끕니다.
    reg mac_vld;
    always @(posedge clk) begin
        mac_vld <= (cnn_state == ST_RUN && row >= 1 && row <= 256 && col >= 1 && col <= 128);
    end

    // 4x Dual MAC Array
    wire [19:0] acc_o0[0:3], acc_o1[0:3]; wire vld_o[0:3];
    dual_mac u_mac_0(.clk(clk), .rstn(rstn), .vld_i(mac_vld), .win(win_ch0), .din0(din0), .din1(din1), .acc_o0(acc_o0[0]), .acc_o1(acc_o1[0]), .vld_o(vld_o[0]));
    dual_mac u_mac_1(.clk(clk), .rstn(rstn), .vld_i(mac_vld), .win(win_ch1), .din0(din0), .din1(din1), .acc_o0(acc_o0[1]), .acc_o1(acc_o1[1]), .vld_o(vld_o[1]));
    dual_mac u_mac_2(.clk(clk), .rstn(rstn), .vld_i(mac_vld), .win(win_ch2), .din0(din0), .din1(din1), .acc_o0(acc_o0[2]), .acc_o1(acc_o1[2]), .vld_o(vld_o[2]));
    dual_mac u_mac_3(.clk(clk), .rstn(rstn), .vld_i(mac_vld), .win(win_ch3), .din0(din0), .din1(din1), .acc_o0(acc_o0[3]), .acc_o1(acc_o1[3]), .vld_o(vld_o[3]));

    // Accumulator
    reg [1:0] out_chn_idx; 
    always @(posedge clk or negedge rstn) begin
        if (!rstn) out_chn_idx <= 0;
        else if (vld_o[0]) out_chn_idx <= (out_chn_idx == 2) ? 0 : out_chn_idx + 1;
    end

    reg signed [31:0] final_psum0[0:3], final_psum1[0:3];
    always @(posedge clk or negedge rstn) begin 
        if (!rstn) begin
            final_psum0[0] <= 0; final_psum1[0] <= 0; final_psum0[1] <= 0; final_psum1[1] <= 0;
            final_psum0[2] <= 0; final_psum1[2] <= 0; final_psum0[3] <= 0; final_psum1[3] <= 0;
        end else if(vld_o[0]) begin 
            if(out_chn_idx == 0) begin 
                final_psum0[0] <= $signed(acc_o0[0]); final_psum1[0] <= $signed(acc_o1[0]);
                final_psum0[1] <= $signed(acc_o0[1]); final_psum1[1] <= $signed(acc_o1[1]);
                final_psum0[2] <= $signed(acc_o0[2]); final_psum1[2] <= $signed(acc_o1[2]);
                final_psum0[3] <= $signed(acc_o0[3]); final_psum1[3] <= $signed(acc_o1[3]);
            end else begin 
                final_psum0[0] <= final_psum0[0] + $signed(acc_o0[0]); final_psum1[0] <= final_psum1[0] + $signed(acc_o1[0]);
                final_psum0[1] <= final_psum0[1] + $signed(acc_o0[1]); final_psum1[1] <= final_psum1[1] + $signed(acc_o1[1]);
                final_psum0[2] <= final_psum0[2] + $signed(acc_o0[2]); final_psum1[2] <= final_psum1[2] + $signed(acc_o1[2]);
                final_psum0[3] <= final_psum0[3] + $signed(acc_o0[3]); final_psum1[3] <= final_psum1[3] + $signed(acc_o1[3]);
            end 
        end  
    end

    // Post-Processing
    reg post_process_en;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) post_process_en <= 0;
        else post_process_en <= (vld_o[0] && out_chn_idx == 2);
    end

    reg [7:0] p_out0_0, p_out0_1, p_out0_2, p_out0_3;
    reg [7:0] p_out1_0, p_out1_1, p_out1_2, p_out1_3;
    reg out_valid_reg;

    wire signed [31:0] sum0_0 = final_psum0[0] + bias_ch0; wire signed [31:0] sum1_0 = final_psum1[0] + bias_ch0;
    wire signed [31:0] sum0_1 = final_psum0[1] + bias_ch1; wire signed [31:0] sum1_1 = final_psum1[1] + bias_ch1;
    wire signed [31:0] sum0_2 = final_psum0[2] + bias_ch2; wire signed [31:0] sum1_2 = final_psum1[2] + bias_ch2;
    wire signed [31:0] sum0_3 = final_psum0[3] + bias_ch3; wire signed [31:0] sum1_3 = final_psum1[3] + bias_ch3;

    wire signed [31:0] shifted0_0 = sum0_0 >>> shift_ch0; wire signed [31:0] shifted1_0 = sum1_0 >>> shift_ch0;
    wire signed [31:0] shifted0_1 = sum0_1 >>> shift_ch1; wire signed [31:0] shifted1_1 = sum1_1 >>> shift_ch1;
    wire signed [31:0] shifted0_2 = sum0_2 >>> shift_ch2; wire signed [31:0] shifted1_2 = sum1_2 >>> shift_ch2;
    wire signed [31:0] shifted0_3 = sum0_3 >>> shift_ch3; wire signed [31:0] shifted1_3 = sum1_3 >>> shift_ch3;

    wire [7:0] relu0_0 = (shifted0_0 <= 0) ? 8'd0 : (shifted0_0 > 255) ? 8'd255 : shifted0_0[7:0];
    wire [7:0] relu1_0 = (shifted1_0 <= 0) ? 8'd0 : (shifted1_0 > 255) ? 8'd255 : shifted1_0[7:0];
    wire [7:0] relu0_1 = (shifted0_1 <= 0) ? 8'd0 : (shifted0_1 > 255) ? 8'd255 : shifted0_1[7:0];
    wire [7:0] relu1_1 = (shifted1_1 <= 0) ? 8'd0 : (shifted1_1 > 255) ? 8'd255 : shifted1_1[7:0];
    wire [7:0] relu0_2 = (shifted0_2 <= 0) ? 8'd0 : (shifted0_2 > 255) ? 8'd255 : shifted0_2[7:0];
    wire [7:0] relu1_2 = (shifted1_2 <= 0) ? 8'd0 : (shifted1_2 > 255) ? 8'd255 : shifted1_2[7:0];
    wire [7:0] relu0_3 = (shifted0_3 <= 0) ? 8'd0 : (shifted0_3 > 255) ? 8'd255 : shifted0_3[7:0];
    wire [7:0] relu1_3 = (shifted1_3 <= 0) ? 8'd0 : (shifted1_3 > 255) ? 8'd255 : shifted1_3[7:0];

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            out_valid_reg <= 0;
            p_out0_0 <= 0; p_out0_1 <= 0; p_out0_2 <= 0; p_out0_3 <= 0;
            p_out1_0 <= 0; p_out1_1 <= 0; p_out1_2 <= 0; p_out1_3 <= 0;
        end else begin
            out_valid_reg <= post_process_en;
            if (post_process_en) begin
                p_out0_0 <= relu0_0; p_out1_0 <= relu1_0;
                p_out0_1 <= relu0_1; p_out1_1 <= relu1_1;
                p_out0_2 <= relu0_2; p_out1_2 <= relu1_2;
                p_out0_3 <= relu0_3; p_out1_3 <= relu1_3;
            end
        end
    end

    assign out_valid = out_valid_reg;
    assign out_pixel0_32b = {p_out0_3, p_out0_2, p_out0_1, p_out0_0};
    assign out_pixel1_32b = {p_out1_3, p_out1_2, p_out1_1, p_out1_0};

endmodule
