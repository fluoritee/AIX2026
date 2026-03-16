`timescale 1ns / 1ps

module dual_mac_tb;
    reg clk;
    reg rstn;
    reg vld_i;
    reg [127:0] win, din0, din1;
    wire [19:0] acc_o0, acc_o1;
    wire        vld_o;

    // DUT (Device Under Test) 인스턴스화
    dual_mac u_mac(
        .clk(clk), 
        .rstn(rstn), 
        .vld_i(vld_i), 
        .win(win), 
        .din0(din0), 
        .din1(din1),
        .acc_o0(acc_o0), 
        .acc_o1(acc_o1), 
        .vld_o(vld_o)
    );

    // 100MHz 클럭 생성
    parameter CLK_PERIOD = 10;
    initial begin
        clk = 1'b1;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    integer i;

    initial begin
        // 초기화
        rstn = 1'b0;    
        vld_i = 0;
        win = 0;
        din0 = 0;
        din1 = 0;
        
        #(4*CLK_PERIOD) rstn = 1'b1;
        #(4*CLK_PERIOD);
        
        // --- Test Case 1: 양수 가중치 (Weight = 3) ---
        // din0에는 모두 10을, din1에는 모두 20을 넣습니다.
        // 예상 결과: acc_o0 = 16 * (3 * 10) = 480
        // 예상 결과: acc_o1 = 16 * (3 * 20) = 960
        @(posedge clk);
        vld_i = 1'b1;
        for(i = 0; i < 16; i = i + 1) begin
            win[i*8 +: 8]  = 8'd3;   // Weight = 3
            din0[i*8 +: 8] = 8'd10;  // Pixel 0 = 10
            din1[i*8 +: 8] = 8'd20;  // Pixel 1 = 20
        end
        
        // --- Test Case 2: 음수 가중치 (Weight = -2) ---
        // 하드웨어 패킹 시 음수 보정이 잘 되는지 확인!
        // 예상 결과: acc_o0 = 16 * (-2 * 10) = -320
        // 예상 결과: acc_o1 = 16 * (-2 * 20) = -640
        @(posedge clk);
        for(i = 0; i < 16; i = i + 1) begin
            win[i*8 +: 8]  = 8'hFE;  // Weight = -2 (2의 보수)
            din0[i*8 +: 8] = 8'd10;
            din1[i*8 +: 8] = 8'd20;
        end
        
        @(posedge clk);
        vld_i = 1'b0;
        
        // 결과가 나올 때까지 대기 (파이프라인 딜레이 5~6클럭)
        #(10*CLK_PERIOD);
        $stop;
    end
endmodule