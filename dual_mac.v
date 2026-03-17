`timescale 1ns / 1ps

module dual_mac(
    input clk, 
    input rstn, 
    input vld_i, 
    input [127:0] win,   // 16개의 Weights (128-bit)
    input [127:0] din0,  // Pixel 0를 위한 16개의 Activations
    input [127:0] din1,  // Pixel 1을 위한 16개의 Activations
    output [19:0] acc_o0, // Pixel 0의 MAC 누산 결과
    output [19:0] acc_o1, // Pixel 1의 MAC 누산 결과
    output        vld_o   // Valid 신호 출력
);

    // 16쌍의 듀얼 곱셈기 출력 와이어
    wire [15:0] y0_00, y1_00; wire [15:0] y0_01, y1_01;
    wire [15:0] y0_02, y1_02; wire [15:0] y0_03, y1_03;
    wire [15:0] y0_04, y1_04; wire [15:0] y0_05, y1_05;
    wire [15:0] y0_06, y1_06; wire [15:0] y0_07, y1_07;
    wire [15:0] y0_08, y1_08; wire [15:0] y0_09, y1_09;
    wire [15:0] y0_10, y1_10; wire [15:0] y0_11, y1_11;
    wire [15:0] y0_12, y1_12; wire [15:0] y0_13, y1_13;
    wire [15:0] y0_14, y1_14; wire [15:0] y0_15, y1_15;

    // dual_mul 모듈 내부에서 곱셈 3클럭 지연이 발생하므로 vld_i도 3클럭 지연
    reg vld_i_d0, vld_i_d1, vld_i_d2;

    always @(posedge clk or negedge rstn) begin
        if(!rstn) begin
            vld_i_d0 <= 1'b0;
            vld_i_d1 <= 1'b0;
            vld_i_d2 <= 1'b0;
        end else begin 
            vld_i_d0 <= vld_i;
            vld_i_d1 <= vld_i_d0;
            vld_i_d2 <= vld_i_d1;
        end
    end

    // 16개의 듀얼 곱셈기 인스턴스화 (DSP 16개만 사용)
    dual_mul u_mul_00(.clk(clk), .w(win[7:0]),     .x0(din0[7:0]),     .x1(din1[7:0]),     .y0(y0_00), .y1(y1_00));
    dual_mul u_mul_01(.clk(clk), .w(win[15:8]),    .x0(din0[15:8]),    .x1(din1[15:8]),    .y0(y0_01), .y1(y1_01));
    dual_mul u_mul_02(.clk(clk), .w(win[23:16]),   .x0(din0[23:16]),   .x1(din1[23:16]),   .y0(y0_02), .y1(y1_02));
    dual_mul u_mul_03(.clk(clk), .w(win[31:24]),   .x0(din0[31:24]),   .x1(din1[31:24]),   .y0(y0_03), .y1(y1_03));
    dual_mul u_mul_04(.clk(clk), .w(win[39:32]),   .x0(din0[39:32]),   .x1(din1[39:32]),   .y0(y0_04), .y1(y1_04));
    dual_mul u_mul_05(.clk(clk), .w(win[47:40]),   .x0(din0[47:40]),   .x1(din1[47:40]),   .y0(y0_05), .y1(y1_05));
    dual_mul u_mul_06(.clk(clk), .w(win[55:48]),   .x0(din0[55:48]),   .x1(din1[55:48]),   .y0(y0_06), .y1(y1_06));
    dual_mul u_mul_07(.clk(clk), .w(win[63:56]),   .x0(din0[63:56]),   .x1(din1[63:56]),   .y0(y0_07), .y1(y1_07));
    dual_mul u_mul_08(.clk(clk), .w(win[71:64]),   .x0(din0[71:64]),   .x1(din1[71:64]),   .y0(y0_08), .y1(y1_08));
    dual_mul u_mul_09(.clk(clk), .w(win[79:72]),   .x0(din0[79:72]),   .x1(din1[79:72]),   .y0(y0_09), .y1(y1_09));
    dual_mul u_mul_10(.clk(clk), .w(win[87:80]),   .x0(din0[87:80]),   .x1(din1[87:80]),   .y0(y0_10), .y1(y1_10));
    dual_mul u_mul_11(.clk(clk), .w(win[95:88]),   .x0(din0[95:88]),   .x1(din1[95:88]),   .y0(y0_11), .y1(y1_11));
    dual_mul u_mul_12(.clk(clk), .w(win[103:96]),  .x0(din0[103:96]),  .x1(din1[103:96]),  .y0(y0_12), .y1(y1_12));
    dual_mul u_mul_13(.clk(clk), .w(win[111:104]), .x0(din0[111:104]), .x1(din1[111:104]), .y0(y0_13), .y1(y1_13));
    dual_mul u_mul_14(.clk(clk), .w(win[119:112]), .x0(din0[119:112]), .x1(din1[119:112]), .y0(y0_14), .y1(y1_14));
    dual_mul u_mul_15(.clk(clk), .w(win[127:120]), .x0(din0[127:120]), .x1(din1[127:120]), .y0(y0_15), .y1(y1_15));

    // Pixel 0 누산을 위한 Adder Tree
    adder_tree u_adder_tree0(
        .clk(clk), .rstn(rstn), .vld_i(vld_i_d2),
        .mul_00(y0_00), .mul_01(y0_01), .mul_02(y0_02), .mul_03(y0_03),
        .mul_04(y0_04), .mul_05(y0_05), .mul_06(y0_06), .mul_07(y0_07),
        .mul_08(y0_08), .mul_09(y0_09), .mul_10(y0_10), .mul_11(y0_11),
        .mul_12(y0_12), .mul_13(y0_13), .mul_14(y0_14), .mul_15(y0_15),
        .acc_o(acc_o0), .vld_o(vld_o) // 최종 출력 vld_o는 여기서 뽑습니다
    );

    // Pixel 1 누산을 위한 Adder Tree (주최측이 제공한 adder_tree.v 재사용)
    adder_tree u_adder_tree1(
        .clk(clk), .rstn(rstn), .vld_i(vld_i_d2),
        .mul_00(y1_00), .mul_01(y1_01), .mul_02(y1_02), .mul_03(y1_03),
        .mul_04(y1_04), .mul_05(y1_05), .mul_06(y1_06), .mul_07(y1_07),
        .mul_08(y1_08), .mul_09(y1_09), .mul_10(y1_10), .mul_11(y1_11),
        .mul_12(y1_12), .mul_13(y1_13), .mul_14(y1_14), .mul_15(y1_15),
        .acc_o(acc_o1), .vld_o() // vld_o는 tree0과 동일하게 나오므로 연결 안 함(Floating)
    );

endmodule