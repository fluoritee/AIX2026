`timescale 1ns / 1ps

module dual_cnn_ctrl_tb;

    parameter W_SIZE  = 12;                 
    parameter W_FRAME_SIZE  = 2 * W_SIZE + 1;   
    parameter W_DELAY = 12;
    parameter WIDTH     = 256;
    parameter HEIGHT    = 256;
    parameter FRAME_SIZE = WIDTH * HEIGHT;
    
    // 🚀 시뮬레이션을 빨리 보기 위해 Delay를 100 -> 10으로 확 줄였습니다!
    parameter VSYNC_DELAY = 10; 
    parameter HSYNC_DELAY = 10; 
        
    reg clk, rstn;
    reg [W_SIZE-1 :0] q_width;
    reg [W_SIZE-1 :0] q_height;
    reg [W_DELAY-1:0] q_vsync_delay;
    reg [W_DELAY-1:0] q_hsync_delay;
    reg [W_FRAME_SIZE-1:0] q_frame_size;
    reg q_start;

    wire                 ctrl_vsync_run;
    wire [W_DELAY-1:0]   ctrl_vsync_cnt;
    wire                 ctrl_hsync_run;
    wire [W_DELAY-1:0]   ctrl_hsync_cnt;
    wire                 ctrl_data_run;
    wire [W_SIZE-1:0]    row;
    wire [W_SIZE-1:0]    col;
    wire [W_FRAME_SIZE-1:0] data_count;
    wire end_frame;
    wire bank_sel;

    //-------------------------------------------------
    // DUT (새로 만든 2배속 제어기 연결)
    //-------------------------------------------------
    dual_cnn_ctrl u_cnn_ctrl (
        .clk            (clk            ),
        .rstn           (rstn           ),
        .q_width        (q_width        ),
        .q_height       (q_height       ),
        .q_vsync_delay  (q_vsync_delay  ),
        .q_hsync_delay  (q_hsync_delay  ),
        .q_frame_size   (q_frame_size   ),
        .q_start        (q_start        ),
        .o_ctrl_vsync_run(ctrl_vsync_run),
        .o_ctrl_vsync_cnt(ctrl_vsync_cnt),
        .o_ctrl_hsync_run(ctrl_hsync_run),
        .o_ctrl_hsync_cnt(ctrl_hsync_cnt),
        .o_ctrl_data_run (ctrl_data_run ),
        .o_row          (row            ),
        .o_col          (col            ),
        .o_data_count   (data_count     ),
        .o_end_frame    (end_frame      ),
        .o_bank_sel     (bank_sel       )
    );

    // 100MHz Clock
    parameter CLK_PERIOD = 10;  
    initial begin
        clk = 1'b1;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //-------------------------------------------------
    // 테스트 시나리오
    //-------------------------------------------------
    initial begin
        rstn = 1'b0;            
        q_width         = WIDTH;
        q_height        = HEIGHT;
        q_vsync_delay   = VSYNC_DELAY;
        q_hsync_delay   = HSYNC_DELAY;      
        q_frame_size    = FRAME_SIZE;
        q_start         = 1'b0; 
        
        #(4*CLK_PERIOD) rstn = 1'b1;
        
        // 시작 대기 시간도 100 클럭에서 10 클럭으로 단축!
        #(10*CLK_PERIOD) 
        @(posedge clk) q_start = 1'b1; // 연산 시작!
        
        #(4*CLK_PERIOD) 
        @(posedge clk) q_start = 1'b0;
        
        // 🚀 충분한 시간(약 10만 클럭 = 1ms)을 시뮬레이션 돌린 후 자동으로 멈춤($stop)
        #(100000 * CLK_PERIOD);
        $display("Simulation Finished!");
        $stop; 
    end

endmodule