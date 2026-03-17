`timescale 1ns / 1ps

module dual_line_buffer_tb;

    reg clk;
    reg rstn;
    reg vld_i;
    reg [11:0] row;
    reg [11:0] col;
    reg [15:0] din;
    
    wire [71:0] win_data0;
    wire [71:0] win_data1;
    wire vld_o;

    //-------------------------------------------------
    // DUT 인스턴스화
    //-------------------------------------------------
    dual_line_buffer u_dut(
        .clk(clk),
        .rstn(rstn),
        .vld_i(vld_i),
        .row(row),
        .col(col),
        .din(din),
        .win_data0(win_data0),
        .win_data1(win_data1),
        .vld_o(vld_o)
    );

    // 100MHz 클럭 생성
    parameter CLK_PERIOD = 10;
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    integer r, c;

    //-------------------------------------------------
    // 시나리오 테스트
    //-------------------------------------------------
    initial begin
        rstn = 1'b0;
        vld_i = 1'b0;
        row = 0;
        col = 0;
        din = 0;
        
        #(4*CLK_PERIOD) rstn = 1'b1; // 리셋 해제
        #(2*CLK_PERIOD);
        
        // 4줄(Row 0 ~ 3)의 가상 이미지를 입력 (가로 너비는 16픽셀로 가정)
        for (r = 0; r < 4; r = r + 1) begin
            // 2픽셀씩 입력하므로 col은 0, 2, 4 ... 14까지 증가
            for (c = 0; c < 16; c = c + 2) begin
                @(posedge clk);
                vld_i <= 1'b1;
                row <= r;
                col <= c;
                // 파형에서 보기 쉽게 데이터를 만듦 (16진수)
                // 상위 8비트(Pixel 1): {Row, Col+1}
                // 하위 8비트(Pixel 0): {Row, Col}
                // 예: Row=2, Col=4일 때 -> din = 16'h2524
                din <= { {r[3:0], c[3:0] + 4'd1}, {r[3:0], c[3:0]} };
            end
            
            // 한 줄 입력이 끝나면 HSYNC(가로 동기화) 구간처럼 잠시 대기
            @(posedge clk);
            vld_i <= 1'b0;
            #(10*CLK_PERIOD); 
        end

        #(20*CLK_PERIOD);
        $display("Line Buffer Test Finished!");
        $stop;
    end

endmodule