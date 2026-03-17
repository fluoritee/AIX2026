`timescale 1ns / 1ps

module dual_line_buffer(
    input clk,
    input rstn,
    input vld_i,
    input [11:0] row,
    input [11:0] col,
    input [15:0] din,
    
    output [71:0] win_data0, 
    output [71:0] win_data1,
    output vld_o            
);

    //----------------------------------------------------------------
    // 1. BRAM Bank 제어 로직 (Row % 3)
    //----------------------------------------------------------------
    reg [1:0] r_mod;
    reg [11:0] row_prev;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            r_mod <= 0;
            row_prev <= 0;
        end else if (vld_i) begin
            row_prev <= row;
            if (row != row_prev) begin
                r_mod <= (r_mod == 2) ? 0 : r_mod + 1;
            end
        end
    end

    wire [10:0] addr = col[11:1]; 
    wire we0 = (r_mod == 0) & vld_i;
    wire we1 = (r_mod == 1) & vld_i;
    wire we2 = (r_mod == 2) & vld_i;

    //----------------------------------------------------------------
    // 2. 🚀 네이티브 BRAM 자동 합성 (IP 의존성 완벽 제거!)
    //----------------------------------------------------------------
    // Vivado가 이 2차원 배열을 인식하여 진짜 BRAM으로 구워줍니다.
    reg [15:0] ram0 [0:2047];
    reg [15:0] ram1 [0:2047];
    reg [15:0] ram2 [0:2047];
    
    reg [15:0] dob0, dob1, dob2;

    // 시뮬레이션 시 'X' (빨간줄) 방지를 위한 초기화
    integer k;
    initial begin
        for(k=0; k<2048; k=k+1) begin
            ram0[k] = 16'd0; ram1[k] = 16'd0; ram2[k] = 16'd0;
        end
    end

    always @(posedge clk) begin
        if (vld_i) begin
            // Bank 0 쓰기 및 읽기
            if (we0) ram0[addr] <= din;
            dob0 <= ram0[addr];
            
            // Bank 1 쓰기 및 읽기
            if (we1) ram1[addr] <= din;
            dob1 <= ram1[addr];
            
            // Bank 2 쓰기 및 읽기
            if (we2) ram2[addr] <= din;
            dob2 <= ram2[addr];
        end
    end

    //----------------------------------------------------------------
    // 3. 파이프라인 딜레이 (BRAM Read Latency 1클럭 보정)
    //----------------------------------------------------------------
    reg [1:0] r_mod_d1;
    reg [15:0] din_d1;
    reg vld_i_d1, vld_i_d2;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            r_mod_d1 <= 0;
            din_d1   <= 0;
            vld_i_d1 <= 0;
            vld_i_d2 <= 0;
        end else begin
            r_mod_d1 <= r_mod;
            din_d1   <= din;
            vld_i_d1 <= vld_i;
            vld_i_d2 <= vld_i_d1;
        end
    end

    //----------------------------------------------------------------
    // 4. Row 데이터 정렬 MUX (가장 오래된 줄 ~ 최신 줄)
    //----------------------------------------------------------------
    reg [15:0] row_oldest, row_middle, row_newest;
    always @(*) begin
        case(r_mod_d1)
            0: begin row_oldest = dob1; row_middle = dob2; row_newest = din_d1; end
            1: begin row_oldest = dob2; row_middle = dob0; row_newest = din_d1; end
            2: begin row_oldest = dob0; row_middle = dob1; row_newest = din_d1; end
            default: begin row_oldest = 0; row_middle = 0; row_newest = 0; end
        endcase
    end

    //----------------------------------------------------------------
    // 5. 🚀 3x4 듀얼 슬라이딩 윈도우 (Shift Register Matrix)
    //----------------------------------------------------------------
    reg [7:0] win [0:2][0:3]; 
    integer i;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for(i=0; i<3; i=i+1) begin
                win[i][0] <= 0; win[i][1] <= 0; 
                win[i][2] <= 0; win[i][3] <= 0;
            end
        end else if (vld_i_d1) begin
            // 2칸씩 좌측으로 Shift
            for(i=0; i<3; i=i+1) begin
                win[i][0] <= win[i][2];
                win[i][1] <= win[i][3];
            end
            
            // 새 데이터 2픽셀(16비트) 삽입
            win[0][2] <= row_oldest[7:0];  win[0][3] <= row_oldest[15:8];
            win[1][2] <= row_middle[7:0];  win[1][3] <= row_middle[15:8];
            win[2][2] <= row_newest[7:0];  win[2][3] <= row_newest[15:8];
        end
    end

    //----------------------------------------------------------------
    // 6. 듀얼 MAC을 위한 출력 배선
    //----------------------------------------------------------------
    assign win_data0 = {
        win[2][2], win[2][1], win[2][0], // Bot
        win[1][2], win[1][1], win[1][0], // Mid
        win[0][2], win[0][1], win[0][0]  // Top
    };

    assign win_data1 = {
        win[2][3], win[2][2], win[2][1], // Bot
        win[1][3], win[1][2], win[1][1], // Mid
        win[0][3], win[0][2], win[0][1]  // Top
    };

    assign vld_o = vld_i_d2; 

endmodule