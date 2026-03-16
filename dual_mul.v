`timescale 1ns / 1ps

module dual_mul(
    input clk,
    input [7:0] w,   // Signed Weight (int8)
    input [7:0] x0,  // Unsigned Activation 0 (uint8) - 첫 번째 픽셀
    input [7:0] x1,  // Unsigned Activation 1 (uint8) - 두 번째 픽셀
    output reg signed [15:0] y0, // 결과: w * x0
    output reg signed [15:0] y1  // 결과: w * x1
);

    // DSP48E1 내부 파이프라인 레지스터 추론을 위한 선언
    reg signed [24:0] dsp_A;
    reg signed [17:0] dsp_B;
    reg signed [42:0] dsp_M;

    always @(posedge clk) begin
        // Stage 1: 입력 패킹 (A & B Registers)
        // x1과 x0 사이에 8비트 공간을 둠 (총 25비트)
        dsp_A <= {1'b0, x1, 8'd0, x0};
        
        // 가중치는 18비트로 부호 확장 (Sign Extension)
        dsp_B <= {{10{w[7]}}, w};
        
        // Stage 2: 곱셈 (M Register)
        dsp_M <= dsp_A * dsp_B;
        
        // Stage 3: 결과 추출 및 음수 보정 (P Register & Post-adder)
        y0 <= dsp_M[15:0];
        
        // 하위 16비트의 부호비트(dsp_M[15])를 더해Borrow 현상 보정
        y1 <= dsp_M[31:16] + dsp_M[15]; 
    end

endmodule