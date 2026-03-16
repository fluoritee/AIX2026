`timescale 1ns / 1ps

module dual_post_process(
    input clk,
    input rstn,
    input vld_i,
    
    input signed [19:0] acc_in0, // MAC 0 누산 결과
    input signed [19:0] acc_in1, // MAC 1 누산 결과
    
    input signed [15:0] bias_in, // 현재 채널(필터)의 Bias 값
    input [3:0] shift_in,        // C 코드에서 구했던 Scale 값 (우측 Shift 횟수)
    
    output reg [7:0] out_pixel0, // 8-bit 최종 출력 0
    output reg [7:0] out_pixel1, // 8-bit 최종 출력 1
    output reg vld_o
);

    // 파이프라인 Stage 1: Bias 덧셈 (20-bit + 16-bit)
    reg signed [20:0] sum0, sum1;
    reg vld_d1;
    
    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            sum0 <= 0;
            sum1 <= 0;
            vld_d1 <= 0;
        end else begin
            // 20비트 MAC 결과에 16비트 Bias를 부호 확장하여 더함
            sum0 <= acc_in0 + {{4{bias_in[15]}}, bias_in};
            sum1 <= acc_in1 + {{4{bias_in[15]}}, bias_in};
            vld_d1 <= vld_i;
        end
    end

    // 파이프라인 Stage 2: 양자화(비트 시프트) 및 ReLU(Clipping)
    wire signed [20:0] shifted0 = sum0 >>> shift_in; // 산술 우측 시프트
    wire signed [20:0] shifted1 = sum1 >>> shift_in;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            out_pixel0 <= 0;
            out_pixel1 <= 0;
            vld_o <= 0;
        end else begin
            // ReLU 및 8-bit Clipping 처리 (Pixel 0)
            if (shifted0 <= 0) 
                out_pixel0 <= 8'd0;         // 음수는 0 (ReLU)
            else if (shifted0 > 255) 
                out_pixel0 <= 8'd255;       // 255 초과는 255로 클리핑 (Saturation)
            else 
                out_pixel0 <= shifted0[7:0]; // 정상 범위

            // ReLU 및 8-bit Clipping 처리 (Pixel 1)
            if (shifted1 <= 0) 
                out_pixel1 <= 8'd0;
            else if (shifted1 > 255) 
                out_pixel1 <= 8'd255;
            else 
                out_pixel1 <= shifted1[7:0];
                
            vld_o <= vld_d1;
        end
    end

endmodule