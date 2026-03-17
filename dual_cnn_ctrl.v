`timescale 1ns / 1ps

module dual_cnn_ctrl(
    input clk,
    input rstn,
    // Inputs
    input [11:0] q_width,
    input [11:0] q_height,
    input [11:0] q_vsync_delay,
    input [11:0] q_hsync_delay,
    input [24:0] q_frame_size,
    input q_start,
    // Outputs
    output o_ctrl_vsync_run,
    output [11:0] o_ctrl_vsync_cnt,
    output o_ctrl_hsync_run,
    output [11:0] o_ctrl_hsync_cnt,
    output o_ctrl_data_run,
    output [11:0] o_row,
    output [11:0] o_col,
    output [24:0] o_data_count,
    output o_end_frame,
    output o_bank_sel // ⭐ 핑퐁 버퍼 스위치 신호
);

    parameter W_SIZE  = 12;                 
    parameter W_FRAME_SIZE  = 2 * W_SIZE + 1;   
    parameter W_DELAY = 12;

    // FSM 상태 선언 (주최측과 동일)
    localparam  ST_IDLE     = 2'b00,
                ST_VSYNC    = 2'b01,
                ST_HSYNC    = 2'b10,
                ST_DATA     = 2'b11;

    reg [1:0] cstate, nstate;
    reg                 ctrl_vsync_run;
    reg [W_DELAY-1:0]   ctrl_vsync_cnt;
    reg                 ctrl_hsync_run;
    reg [W_DELAY-1:0]   ctrl_hsync_cnt;
    reg                 ctrl_data_run;
    reg [W_SIZE-1:0]    row;
    reg [W_SIZE-1:0]    col;
    reg [W_FRAME_SIZE-1:0] data_count;
    wire end_frame;
    reg bank_sel; // ⭐ 내부 스위치 플립플롭

    //-------------------------------------------------
    // 1. FSM State Update
    //-------------------------------------------------
    always@(posedge clk, negedge rstn) begin
        if(!rstn) cstate <= ST_IDLE;
        else      cstate <= nstate;
    end

    //-------------------------------------------------
    // 2. Next State Logic
    //-------------------------------------------------
    always @(*) begin
        case(cstate)
            ST_IDLE: begin
                if(q_start) nstate = ST_VSYNC;
                else        nstate = ST_IDLE;
            end     
            ST_VSYNC: begin
                if(ctrl_vsync_cnt == q_vsync_delay) nstate = ST_HSYNC;
                else                                nstate = ST_VSYNC;
            end 
            ST_HSYNC: begin
                if(ctrl_hsync_cnt == q_hsync_delay) nstate = ST_DATA;
                else                                nstate = ST_HSYNC;
            end     
            ST_DATA: begin
                if(end_frame)       // 프레임 끝이면 IDLE로
                    nstate = ST_IDLE;
                else begin
                    // 🚀 [핵심 개조] 2픽셀씩 처리하므로 q_width-2에 도달하면 다음 줄(HSYNC)로 넘어감!
                    if(col >= q_width - 2) nstate = ST_HSYNC;
                    else                   nstate = ST_DATA;
                end
            end
            default: nstate = ST_IDLE;
        endcase
    end

    //-------------------------------------------------
    // 3. Output Logic (상태에 따른 Run 신호 켜기)
    //-------------------------------------------------
    always @(*) begin
        ctrl_vsync_run = 0;
        ctrl_hsync_run = 0;
        ctrl_data_run  = 0;
        case(cstate)
            ST_VSYNC: begin ctrl_vsync_run = 1; end
            ST_HSYNC: begin ctrl_hsync_run = 1; end
            ST_DATA:  begin ctrl_data_run  = 1; end
        endcase
    end

    //-------------------------------------------------
    // 4. Sync Counters (VSYNC / HSYNC 딜레이 카운터)
    //-------------------------------------------------
    always@(posedge clk, negedge rstn) begin
        if(!rstn) begin
            ctrl_vsync_cnt <= 0;
            ctrl_hsync_cnt <= 0;
        end
        else begin
            if(ctrl_vsync_run) ctrl_vsync_cnt <= ctrl_vsync_cnt + 1;
            else               ctrl_vsync_cnt <= 0;
                
            if(ctrl_hsync_run) ctrl_hsync_cnt <= ctrl_hsync_cnt + 1;            
            else               ctrl_hsync_cnt <= 0;
        end
    end

    //-------------------------------------------------
    // 5. 🚀 [핵심 마개조] Row & Column Counter (2배속)
    //-------------------------------------------------
    always@(posedge clk, negedge rstn) begin
        if(!rstn) begin
            row <= 0;
            col <= 0;
        end
        else begin
            if(ctrl_data_run) begin
                // 한 줄의 끝에 도달했을 때 (2픽셀 단위이므로 q_width-2)
                if(col >= q_width - 2) begin
                    if(end_frame) row <= 0;         
                    else          row <= row + 1; // 다음 줄로
                end
                
                // Column 증가 로직: 1칸이 아니라 2칸씩 뜁니다!
                if(col >= q_width - 2) col <= 0;
                else                   col <= col + 2; 
            end
        end
    end

    //-------------------------------------------------
    // 6. 🚀 [핵심 마개조] Data Counter (2배속)
    //-------------------------------------------------
    always@(posedge clk, negedge rstn) begin
        if(!rstn) begin
            data_count <= 0;
        end
        else begin
            if(ctrl_data_run) begin
                if(!end_frame) data_count <= data_count + 2; // 데이터도 2개씩 쌓임!
                else           data_count <= 0;
            end
        end
    end
    
    // 종료 조건: 마지막 픽셀 쌍에 도달했을 때 (-1이 아닌 -2)
    assign end_frame = (data_count >= q_frame_size - 2) ? 1'b1 : 1'b0;          

    //-------------------------------------------------
    // 7. ⭐ 핑퐁 버퍼 뱅크 스위치 (Bank Select)
    //-------------------------------------------------
    always @(posedge clk, negedge rstn) begin
        if(!rstn) begin
            bank_sel <= 1'b0; 
        end
        else begin
            // 한 줄(Row)의 읽기가 완전히 끝날 때마다 뱅크를 토글(Toggle)
            if(ctrl_data_run && (col >= q_width - 2)) begin
                bank_sel <= ~bank_sel; 
            end
        end
    end

    //-------------------------------------------------
    // Outputs 연결
    //-------------------------------------------------
    assign o_ctrl_vsync_run = ctrl_vsync_run;
    assign o_ctrl_vsync_cnt = ctrl_vsync_cnt;
    assign o_ctrl_hsync_run = ctrl_hsync_run;
    assign o_ctrl_hsync_cnt = ctrl_hsync_cnt;
    assign o_ctrl_data_run  = ctrl_data_run ;
    assign o_row = row;
    assign o_col = col;
    assign o_data_count = data_count;
    assign o_end_frame = end_frame;
    assign o_bank_sel = bank_sel;

endmodule