`timescale 1ns / 1ns

module dual_conv_layer_tb;

// ====================================================================
// 💡 경로 에러 원천 차단: define.v 파라미터 직접 선언
// ====================================================================
parameter IFM_WIDTH         = 256;
parameter IFM_HEIGHT        = 256;
parameter IFM_CHANNEL       = 3;
parameter IFM_DATA_SIZE_32  = IFM_HEIGHT * IFM_WIDTH;
parameter IFM_WORD_SIZE_32  = 32;

parameter Fx = 3, Fy = 3;
parameter Ni = 3, No = 16; 
parameter WGT_DATA_SIZE     = Fx * Fy * Ni * No;

// 파일 경로 (본인 PC 환경에 맞게 유지)
parameter IFM_FILE_32       = "C:/yolohw/sim/inout_data_sw/log_feamap/CONV00_input_32b.hex"; 
parameter WGT_FILE          = "C:/yolohw/sim/inout_data_sw/log_param/CONV00_param_weight.hex"; 

parameter CONV_INPUT_IMG00  = "C:/yolohw/sim/inout_data_hw/CONV00_input_ch00.bmp"; 
parameter CONV_INPUT_IMG01  = "C:/yolohw/sim/inout_data_hw/CONV00_input_ch01.bmp"; 
parameter CONV_INPUT_IMG02  = "C:/yolohw/sim/inout_data_hw/CONV00_input_ch02.bmp"; 
parameter CONV_INPUT_IMG03  = "C:/yolohw/sim/inout_data_hw/CONV00_input_ch03.bmp"; 

parameter CONV_OUTPUT_IMG00 = "C:/yolohw/sim/inout_data_hw/CONV00_output_ch00.bmp"; 
parameter CONV_OUTPUT_IMG01 = "C:/yolohw/sim/inout_data_hw/CONV00_output_ch01.bmp"; 
parameter CONV_OUTPUT_IMG02 = "C:/yolohw/sim/inout_data_hw/CONV00_output_ch02.bmp"; 
parameter CONV_OUTPUT_IMG03 = "C:/yolohw/sim/inout_data_hw/CONV00_output_ch03.bmp"; 
// ====================================================================

// Clock
parameter CLK_PERIOD = 10;   //100MHz
reg clk;
reg rstn;

reg         ctrl_data_run;
reg         vld_i;
reg [127:0] win[0:3];
reg [127:0] din0, din1;  // 🚀 듀얼 코어 데이터 버스
wire[ 19:0] acc_o0[0:3]; 
wire[ 19:0] acc_o1[0:3]; 
wire        vld_o[0:3];

initial begin
   clk = 1'b1;
   forever #(CLK_PERIOD/2) clk = ~clk;
end

reg  [IFM_WORD_SIZE_32-1:0] in_img[0:IFM_DATA_SIZE_32-1];  
reg  [IFM_WORD_SIZE_32-1:0] filter[0:WGT_DATA_SIZE   -1];  
reg  preload;

integer i,j,k;
initial begin: PROC_SimmemLoad
    for (i = 0; i< IFM_DATA_SIZE_32; i=i+1) in_img[i] = 0;
    $display ("Loading input feature maps from file: %s", IFM_FILE_32);
    $readmemh(IFM_FILE_32, in_img);
    
    for (i = 0; i< WGT_DATA_SIZE; i=i+1) filter[i] = 0;
    $display ("Loading weights from file: %s", WGT_FILE);
    $readmemh(WGT_FILE, filter);    
end

integer row, col, chn;
initial begin
    rstn = 1'b0;        
    preload = 1'b0;
    ctrl_data_run  = 1'b0;  
    row = 0; col = 0; chn = 0;
    
    #(4*CLK_PERIOD) rstn = 1'b1; 
    #(100*CLK_PERIOD) @(posedge clk) preload = 1'b1;
    #(100*CLK_PERIOD) @(posedge clk) preload = 1'b0;      
            
    #(100*CLK_PERIOD) 
        for(row = 0; row < IFM_HEIGHT; row = row + 1) begin 
            @(posedge clk) ctrl_data_run  = 0;
            #(100*CLK_PERIOD) @(posedge clk);
            ctrl_data_run  = 1; 
            
            // 🚀 핵심 마개조: 한 번에 2픽셀씩 점프! (처리 속도 2배)
            for (col = 0; col < IFM_WIDTH; col = col + 2) begin                 
                for (chn = 0; chn < IFM_CHANNEL; chn = chn + 1) begin                 
                    @(posedge clk) begin 
                        if((col >= IFM_WIDTH-2) && (chn == IFM_CHANNEL-1))
                            ctrl_data_run = 0;
                    end 
                end
            end 
        end
    @(posedge clk) ctrl_data_run = 1'b0;            
    #(100*CLK_PERIOD) 
        $display("Layer done !!!");
        $stop;      
end

wire is_first_row = (row == 0);
wire is_last_row  = (row == IFM_HEIGHT-1);

wire is_first_col0 = (col == 0);
wire is_last_col0  = (col == IFM_WIDTH-1);
wire is_first_col1 = (col+1 == 0);
wire is_last_col1  = (col+1 >= IFM_WIDTH-1);

always@(*) begin
    vld_i = 0;
    din0 = 128'd0; din1 = 128'd0;
    win[0] = 0; win[1] = 0; win[2] = 0; win[3] = 0;
    
    if(ctrl_data_run) begin
        vld_i = 1;
        // --- Pixel 0 (col) ---
        din0[ 7: 0] = (is_first_row || is_first_col0) ? 8'd0 : in_img[(row-1)*IFM_WIDTH + col-1][chn*8+:8];
        din0[15: 8] = (is_first_row                 ) ? 8'd0 : in_img[(row-1)*IFM_WIDTH + col  ][chn*8+:8];
        din0[23:16] = (is_first_row || is_last_col0 ) ? 8'd0 : in_img[(row-1)*IFM_WIDTH + col+1][chn*8+:8];
        din0[31:24] = (                is_first_col0) ? 8'd0 : in_img[ row   *IFM_WIDTH + col-1][chn*8+:8];
        din0[39:32] =                                          in_img[ row   *IFM_WIDTH + col  ][chn*8+:8];
        din0[47:40] = (                is_last_col0 ) ? 8'd0 : in_img[ row   *IFM_WIDTH + col+1][chn*8+:8];
        din0[55:48] = (is_last_row  || is_first_col0) ? 8'd0 : in_img[(row+1)*IFM_WIDTH + col-1][chn*8+:8];
        din0[63:56] = (is_last_row                  ) ? 8'd0 : in_img[(row+1)*IFM_WIDTH + col  ][chn*8+:8];
        din0[71:64] = (is_last_row  || is_last_col0 ) ? 8'd0 : in_img[(row+1)*IFM_WIDTH + col+1][chn*8+:8];

        // --- Pixel 1 (col+1) ---
        din1[ 7: 0] = (is_first_row || is_first_col1) ? 8'd0 : in_img[(row-1)*IFM_WIDTH + col  ][chn*8+:8];
        din1[15: 8] = (is_first_row                 ) ? 8'd0 : in_img[(row-1)*IFM_WIDTH + col+1][chn*8+:8];
        din1[23:16] = (is_first_row || is_last_col1 ) ? 8'd0 : in_img[(row-1)*IFM_WIDTH + col+2][chn*8+:8];
        din1[31:24] = (                is_first_col1) ? 8'd0 : in_img[ row   *IFM_WIDTH + col  ][chn*8+:8];
        din1[39:32] =                                          in_img[ row   *IFM_WIDTH + col+1][chn*8+:8];
        din1[47:40] = (                is_last_col1 ) ? 8'd0 : in_img[ row   *IFM_WIDTH + col+2][chn*8+:8];
        din1[55:48] = (is_last_row  || is_first_col1) ? 8'd0 : in_img[(row+1)*IFM_WIDTH + col  ][chn*8+:8];
        din1[63:56] = (is_last_row                  ) ? 8'd0 : in_img[(row+1)*IFM_WIDTH + col+1][chn*8+:8];
        din1[71:64] = (is_last_row  || is_last_col1 ) ? 8'd0 : in_img[(row+1)*IFM_WIDTH + col+2][chn*8+:8];

        // Filters
        for(j = 0; j < 4; j=j+1) begin  
            win[j][ 7: 0] = filter[(j*Fx*Fy*Ni) + chn*9    ][7:0];
            win[j][15: 8] = filter[(j*Fx*Fy*Ni) + chn*9 + 1][7:0];
            win[j][23:16] = filter[(j*Fx*Fy*Ni) + chn*9 + 2][7:0];          
            win[j][31:24] = filter[(j*Fx*Fy*Ni) + chn*9 + 3][7:0];
            win[j][39:32] = filter[(j*Fx*Fy*Ni) + chn*9 + 4][7:0];
            win[j][47:40] = filter[(j*Fx*Fy*Ni) + chn*9 + 5][7:0];          
            win[j][55:48] = filter[(j*Fx*Fy*Ni) + chn*9 + 6][7:0];
            win[j][63:56] = filter[(j*Fx*Fy*Ni) + chn*9 + 7][7:0];
            win[j][71:64] = filter[(j*Fx*Fy*Ni) + chn*9 + 8][7:0];          
        end 
    end    
end 

//-------------------------------------------
// 🚀 DUT: DUAL MACs (우리가 만든 V8 엔진!)
//-------------------------------------------
dual_mac u_mac_00(
    .clk(clk), .rstn(rstn), .vld_i(vld_i), .win(win[0]), 
    .din0(din0), .din1(din1), 
    .acc_o0(acc_o0[0]), .acc_o1(acc_o1[0]), .vld_o(vld_o[0])
);
dual_mac u_mac_01(
    .clk(clk), .rstn(rstn), .vld_i(vld_i), .win(win[1]), 
    .din0(din0), .din1(din1), 
    .acc_o0(acc_o0[1]), .acc_o1(acc_o1[1]), .vld_o(vld_o[1])
);
dual_mac u_mac_02(
    .clk(clk), .rstn(rstn), .vld_i(vld_i), .win(win[2]), 
    .din0(din0), .din1(din1), 
    .acc_o0(acc_o0[2]), .acc_o1(acc_o1[2]), .vld_o(vld_o[2])
);
dual_mac u_mac_03(
    .clk(clk), .rstn(rstn), .vld_i(vld_i), .win(win[3]), 
    .din0(din0), .din1(din1), 
    .acc_o0(acc_o0[3]), .acc_o1(acc_o1[3]), .vld_o(vld_o[3])
);

//-------------------------------------------
// 🚀 Dual Channel Accumulation (RGB 3채널 누산)
//-------------------------------------------
reg [15:0] chn_idx;
reg signed [31:0] psum0[0:3], psum1[0:3];
wire valid_out = vld_o[0];

always@(posedge clk, negedge rstn) begin 
    if(!rstn) chn_idx <= 0;      
    else if(valid_out) begin 
        if(chn_idx == IFM_CHANNEL-1) chn_idx <= 0;
        else chn_idx <= chn_idx + 1;            
    end  
end 

reg signed [31:0] final_psum0[0:3], final_psum1[0:3];
always@(posedge clk, negedge rstn) begin 
    if(!rstn) begin 
        psum0[0]<=0; psum0[1]<=0; psum0[2]<=0; psum0[3]<=0;
        psum1[0]<=0; psum1[1]<=0; psum1[2]<=0; psum1[3]<=0;
    end 
    else if(valid_out) begin 
        if(chn_idx == 0) begin 
            psum0[0] <= $signed(acc_o0[0]); psum1[0] <= $signed(acc_o1[0]);
            psum0[1] <= $signed(acc_o0[1]); psum1[1] <= $signed(acc_o1[1]);
            psum0[2] <= $signed(acc_o0[2]); psum1[2] <= $signed(acc_o1[2]);
            psum0[3] <= $signed(acc_o0[3]); psum1[3] <= $signed(acc_o1[3]);
        end else begin 
            psum0[0] <= psum0[0] + $signed(acc_o0[0]); psum1[0] <= psum1[0] + $signed(acc_o1[0]);
            psum0[1] <= psum0[1] + $signed(acc_o0[1]); psum1[1] <= psum1[1] + $signed(acc_o1[1]);
            psum0[2] <= psum0[2] + $signed(acc_o0[2]); psum1[2] <= psum1[2] + $signed(acc_o1[2]);
            psum0[3] <= psum0[3] + $signed(acc_o0[3]); psum1[3] <= psum1[3] + $signed(acc_o1[3]);
        end 

        if(chn_idx == IFM_CHANNEL-1) begin
            final_psum0[0] <= psum0[0] + $signed(acc_o0[0]); final_psum1[0] <= psum1[0] + $signed(acc_o1[0]);
            final_psum0[1] <= psum0[1] + $signed(acc_o0[1]); final_psum1[1] <= psum1[1] + $signed(acc_o1[1]);
            final_psum0[2] <= psum0[2] + $signed(acc_o0[2]); final_psum1[2] <= psum1[2] + $signed(acc_o1[2]);
            final_psum0[3] <= psum0[3] + $signed(acc_o0[3]); final_psum1[3] <= psum1[3] + $signed(acc_o1[3]);
        end
    end  
end

//--------------------------------------------------------------------
// 🚀 Serialization Magic: 2픽셀을 1클럭 간격으로 출력!
//--------------------------------------------------------------------
reg write_p0, write_p1;
always @(posedge clk, negedge rstn) begin
    if(!rstn) begin
        write_p0 <= 0;
        write_p1 <= 0;
    end else begin
        write_p0 <= (valid_out && chn_idx == IFM_CHANNEL-1);
        write_p1 <= write_p0;
    end
end

// ReLU
wire [31:0] p_act0_0 = (final_psum0[0][31]==1) ? 0 : final_psum0[0]; wire [31:0] p_act1_0 = (final_psum1[0][31]==1) ? 0 : final_psum1[0];
wire [31:0] p_act0_1 = (final_psum0[1][31]==1) ? 0 : final_psum0[1]; wire [31:0] p_act1_1 = (final_psum1[1][31]==1) ? 0 : final_psum1[1];
wire [31:0] p_act0_2 = (final_psum0[2][31]==1) ? 0 : final_psum0[2]; wire [31:0] p_act1_2 = (final_psum1[2][31]==1) ? 0 : final_psum1[2];
wire [31:0] p_act0_3 = (final_psum0[3][31]==1) ? 0 : final_psum0[3]; wire [31:0] p_act1_3 = (final_psum1[3][31]==1) ? 0 : final_psum1[3];

// Quantization (Descaling >> 11) -> 주최측 스케일링 복원
wire [7:0] p_out0_0 = (p_act0_0[31:7]>255) ? 255 : p_act0_0[14:7]; wire [7:0] p_out1_0 = (p_act1_0[31:7]>255) ? 255 : p_act1_0[14:7];
wire [7:0] p_out0_1 = (p_act0_1[31:7]>255) ? 255 : p_act0_1[14:7]; wire [7:0] p_out1_1 = (p_act1_1[31:7]>255) ? 255 : p_act1_1[14:7];
wire [7:0] p_out0_2 = (p_act0_2[31:7]>255) ? 255 : p_act0_2[14:7]; wire [7:0] p_out1_2 = (p_act1_2[31:7]>255) ? 255 : p_act1_2[14:7];
wire [7:0] p_out0_3 = (p_act0_3[31:7]>255) ? 255 : p_act0_3[14:7]; wire [7:0] p_out1_3 = (p_act1_3[31:7]>255) ? 255 : p_act1_3[14:7];

// MUX
wire [7:0] conv_out_ch00 = write_p0 ? p_out0_0 : (write_p1 ? p_out1_0 : 0);
wire [7:0] conv_out_ch01 = write_p0 ? p_out0_1 : (write_p1 ? p_out1_1 : 0);
wire [7:0] conv_out_ch02 = write_p0 ? p_out0_2 : (write_p1 ? p_out1_2 : 0);
wire [7:0] conv_out_ch03 = write_p0 ? p_out0_3 : (write_p1 ? p_out1_3 : 0);

wire write_pixel_ena = write_p0 | write_p1;

// Output BMP Writers
bmp_image_writer #(.OUTFILE(CONV_OUTPUT_IMG00),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
u_acc_img_ch0(.clk(clk), .rstn(rstn), .din(conv_out_ch00), .vld(write_pixel_ena), .frame_done());

bmp_image_writer #(.OUTFILE(CONV_OUTPUT_IMG01),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
u_acc_img_ch1(.clk(clk), .rstn(rstn), .din(conv_out_ch01), .vld(write_pixel_ena), .frame_done());

bmp_image_writer #(.OUTFILE(CONV_OUTPUT_IMG02),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
u_acc_img_ch2(.clk(clk), .rstn(rstn), .din(conv_out_ch02), .vld(write_pixel_ena), .frame_done());

bmp_image_writer #(.OUTFILE(CONV_OUTPUT_IMG03),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
u_acc_img_ch3(.clk(clk), .rstn(rstn), .din(conv_out_ch03), .vld(write_pixel_ena), .frame_done());

//======================================================================
// 💡 [복구 완료] 원본 이미지 재현 (디버깅용 INPUT IMAGES)
//======================================================================
reg         dbg_write_image;
reg         dbg_write_image_done;
reg [31:0]  dbg_pix_idx;
always @(posedge clk, negedge rstn) begin
    if(!rstn) begin
        dbg_write_image         <= 0;
        dbg_write_image_done    <= 0;
        dbg_pix_idx             <= 0;
    end 
    else begin 
        if(dbg_write_image) begin 
            if(dbg_pix_idx < IFM_DATA_SIZE_32) begin 
                if(dbg_pix_idx == IFM_DATA_SIZE_32 - 1) begin 
                    dbg_write_image         <= 0;
                    dbg_write_image_done    <= 1;
                    dbg_pix_idx             <= 0;       
                end 
                else 
                    dbg_pix_idx <= dbg_pix_idx + 1;
            end 
        end 
        else if(preload) begin
            dbg_write_image         <= 1;
            dbg_write_image_done    <= 0;
            dbg_pix_idx             <= 0;           
        end
    end 
end

bmp_image_writer #(.OUTFILE(CONV_INPUT_IMG00),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
u_ifm_img_ch0(.clk(clk), .rstn(rstn), .din(in_img[dbg_pix_idx][7:0]), .vld(dbg_write_image), .frame_done());

bmp_image_writer #(.OUTFILE(CONV_INPUT_IMG01),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
u_ifm_img_ch1(.clk(clk), .rstn(rstn), .din(in_img[dbg_pix_idx][15:8]), .vld(dbg_write_image), .frame_done());

bmp_image_writer #(.OUTFILE(CONV_INPUT_IMG02),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
u_ifm_img_ch2(.clk(clk), .rstn(rstn), .din(in_img[dbg_pix_idx][23:16]), .vld(dbg_write_image), .frame_done());

bmp_image_writer #(.OUTFILE(CONV_INPUT_IMG03),.WIDTH(IFM_WIDTH),.HEIGHT(IFM_HEIGHT))
u_ifm_img_ch3(.clk(clk), .rstn(rstn), .din(in_img[dbg_pix_idx][31:24]), .vld(dbg_write_image), .frame_done());
//======================================================================

endmodule