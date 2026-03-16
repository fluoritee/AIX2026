`timescale 1ns / 1ps

module dual_conv_layer(
    input clk,
    input rstn,

    // System Control
    input        start_i,
    output       done_o,

    // Input Feature Map BRAM Interface
    output [14:0] in_ram_addrb,
    input  [63:0] in_ram_dob,

    // Weight ROM Interface (controlled by Layer)
    output [1:0]  current_chn,
    input  [127:0] win_ch0,
    input  [127:0] win_ch1,
    input  [127:0] win_ch2,
    input  [127:0] win_ch3,

    // Output Pixel Interface
    output [31:0] out_pixel0_32b,
    output [31:0] out_pixel1_32b,
    output        out_valid
);

    localparam ST_IDLE = 2'd0, ST_FILL = 2'd1, ST_RUN = 2'd2, ST_DONE = 2'd3;
    reg [1:0] cnn_state;
    reg [8:0] row;
    reg [7:0] col;
    reg [1:0] chn;
    reg shift_en;

    // 💡 [핵심 버그 수정] BRAM Latency 1클럭 보정: 항상 다음 주소를 미리 가리켜야 타이밍이 맞습니다!
    wire [7:0] next_col = (col == 127) ? 8'd0 : col + 1;
    wire [8:0] next_row = (col == 127) ? row + 1 : row;
    assign in_ram_addrb = (cnn_state == ST_IDLE) ? 15'd0 : (next_row * 128 + next_col);

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
                        if(col == 127) begin
                            col <= 0;
                            if(row == 255) cnn_state <= ST_DONE; 
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
    // 엔지니어님의 32-bit Shift Register & Padding 로직 완벽 이식
    // ----------------------------------------------------
    reg [31:0] line_buf0_p0 [0:127], line_buf0_p1 [0:127];
    reg [31:0] line_buf1_p0 [0:127], line_buf1_p1 [0:127];
    wire [31:0] in_pixel0 = in_ram_dob[31:0];
    wire [31:0] in_pixel1 = in_ram_dob[63:32];

    always @(posedge clk) begin
        if (shift_en) begin
            line_buf0_p0[col] <= in_pixel0; line_buf0_p1[col] <= in_pixel1;
            line_buf1_p0[col] <= line_buf0_p0[col]; line_buf1_p1[col] <= line_buf0_p1[col];
        end
    end

    reg [31:0] p00, p01, p02, p03, p10, p11, p12, p13, p20, p21, p22, p23;
    always @(posedge clk) begin
        if (shift_en) begin
            p00 <= p02; p01 <= p03; p02 <= line_buf1_p0[col]; p03 <= line_buf1_p1[col];
            p10 <= p12; p11 <= p13; p12 <= line_buf0_p0[col]; p13 <= line_buf0_p1[col];
            p20 <= p22; p21 <= p23; p22 <= in_pixel0;         p23 <= in_pixel1;
        end
    end

    wire pad_top = (row == 0); wire pad_bot = (row == 255);
    wire pad_l0  = (col == 0); wire pad_r1  = (col == 127);

    wire [7:0] w0_00 = (pad_top || pad_l0) ? 8'd0 : p00[chn*8 +: 8];
    wire [7:0] w0_01 = (pad_top          ) ? 8'd0 : p01[chn*8 +: 8];
    wire [7:0] w0_02 = (pad_top          ) ? 8'd0 : p02[chn*8 +: 8];
    wire [7:0] w0_10 = (pad_l0           ) ? 8'd0 : p10[chn*8 +: 8];
    wire [7:0] w0_11 =                              p11[chn*8 +: 8];
    wire [7:0] w0_12 =                              p12[chn*8 +: 8];
    wire [7:0] w0_20 = (pad_bot || pad_l0) ? 8'd0 : p20[chn*8 +: 8];
    wire [7:0] w0_21 = (pad_bot          ) ? 8'd0 : p21[chn*8 +: 8];
    wire [7:0] w0_22 = (pad_bot          ) ? 8'd0 : p22[chn*8 +: 8];

    wire [7:0] w1_00 = (pad_top          ) ? 8'd0 : p01[chn*8 +: 8];
    wire [7:0] w1_01 = (pad_top          ) ? 8'd0 : p02[chn*8 +: 8];
    wire [7:0] w1_02 = (pad_top || pad_r1) ? 8'd0 : p03[chn*8 +: 8];
    wire [7:0] w1_10 =                              p11[chn*8 +: 8];
    wire [7:0] w1_11 =                              p12[chn*8 +: 8];
    wire [7:0] w1_12 = (pad_r1           ) ? 8'd0 : p13[chn*8 +: 8];
    wire [7:0] w1_20 = (pad_bot          ) ? 8'd0 : p21[chn*8 +: 8];
    wire [7:0] w1_21 = (pad_bot          ) ? 8'd0 : p22[chn*8 +: 8];
    wire [7:0] w1_22 = (pad_bot || pad_r1) ? 8'd0 : p23[chn*8 +: 8];

    wire [127:0] din0 = {56'd0, w0_22, w0_21, w0_20, w0_12, w0_11, w0_10, w0_02, w0_01, w0_00};
    wire [127:0] din1 = {56'd0, w1_22, w1_21, w1_20, w1_12, w1_11, w1_10, w1_02, w1_01, w1_00};

    // ----------------------------------------------------
    // 4x MAC 유닛 구동 및 누산 (Accumulation)
    // ----------------------------------------------------
    reg mac_vld;
    always @(posedge clk) mac_vld <= (cnn_state == ST_RUN);

    wire [19:0] acc_o0[0:3], acc_o1[0:3]; wire vld_o[0:3];
    dual_mac u_mac_0(.clk(clk), .rstn(rstn), .vld_i(mac_vld), .win(win_ch0), .din0(din0), .din1(din1), .acc_o0(acc_o0[0]), .acc_o1(acc_o1[0]), .vld_o(vld_o[0]));
    dual_mac u_mac_1(.clk(clk), .rstn(rstn), .vld_i(mac_vld), .win(win_ch1), .din0(din0), .din1(din1), .acc_o0(acc_o0[1]), .acc_o1(acc_o1[1]), .vld_o(vld_o[1]));
    dual_mac u_mac_2(.clk(clk), .rstn(rstn), .vld_i(mac_vld), .win(win_ch2), .din0(din0), .din1(din1), .acc_o0(acc_o0[2]), .acc_o1(acc_o1[2]), .vld_o(vld_o[2]));
    dual_mac u_mac_3(.clk(clk), .rstn(rstn), .vld_i(mac_vld), .win(win_ch3), .din0(din0), .din1(din1), .acc_o0(acc_o0[3]), .acc_o1(acc_o1[3]), .vld_o(vld_o[3]));

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

    // ----------------------------------------------------
    // 엔지니어님의 스케일링/ReLU 로직 완벽 적용
    // ----------------------------------------------------
    assign out_valid = (vld_o[0] && out_chn_idx == 2);

    wire [31:0] p_act0_0 = (final_psum0[0][31]==1)?0:final_psum0[0]; wire [31:0] p_act1_0 = (final_psum1[0][31]==1)?0:final_psum1[0];
    wire [31:0] p_act0_1 = (final_psum0[1][31]==1)?0:final_psum0[1]; wire [31:0] p_act1_1 = (final_psum1[1][31]==1)?0:final_psum1[1];
    wire [31:0] p_act0_2 = (final_psum0[2][31]==1)?0:final_psum0[2]; wire [31:0] p_act1_2 = (final_psum1[2][31]==1)?0:final_psum1[2];
    wire [31:0] p_act0_3 = (final_psum0[3][31]==1)?0:final_psum0[3]; wire [31:0] p_act1_3 = (final_psum1[3][31]==1)?0:final_psum1[3];

    wire [7:0] p_out0_0 = (p_act0_0[31:7]>255)?255:p_act0_0[14:7]; wire [7:0] p_out1_0 = (p_act1_0[31:7]>255)?255:p_act1_0[14:7];
    wire [7:0] p_out0_1 = (p_act0_1[31:7]>255)?255:p_act0_1[14:7]; wire [7:0] p_out1_1 = (p_act1_1[31:7]>255)?255:p_act1_1[14:7];
    wire [7:0] p_out0_2 = (p_act0_2[31:7]>255)?255:p_act0_2[14:7]; wire [7:0] p_out1_2 = (p_act1_2[31:7]>255)?255:p_act1_2[14:7];
    wire [7:0] p_out0_3 = (p_act0_3[31:7]>255)?255:p_act0_3[14:7]; wire [7:0] p_out1_3 = (p_act1_3[31:7]>255)?255:p_act1_3[14:7];

    assign out_pixel0_32b = {p_out0_3, p_out0_2, p_out0_1, p_out0_0};
    assign out_pixel1_32b = {p_out1_3, p_out1_2, p_out1_1, p_out1_0};

endmodule