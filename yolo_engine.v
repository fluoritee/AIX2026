`timescale 1ns / 1ps

module yolo_engine #(
    parameter AXI_WIDTH_AD = 32, parameter AXI_WIDTH_ID = 4, parameter AXI_WIDTH_DA = 32,
    parameter AXI_WIDTH_DS = AXI_WIDTH_DA/8, parameter OUT_BITS_TRANS = 18,
    parameter MEM_BASE_ADDR = 'h8000_0000, parameter MEM_DATA_BASE_ADDR = 4096
)(
    input clk, input rstn,
    input [31:0] i_ctrl_reg0, input [31:0] i_ctrl_reg1, input [31:0] i_ctrl_reg2, input [31:0] i_ctrl_reg3,
    
    output M_ARVALID, input M_ARREADY, output [AXI_WIDTH_AD-1:0] M_ARADDR, output [AXI_WIDTH_ID-1:0] M_ARID,
    output [7:0] M_ARLEN, output [2:0] M_ARSIZE, output [1:0] M_ARBURST, output [1:0] M_ARLOCK,
    output [3:0] M_ARCACHE, output [2:0] M_ARPROT, output [3:0] M_ARQOS, output [3:0] M_ARREGION, output [3:0] M_ARUSER,
    input M_RVALID, output M_RREADY, input [AXI_WIDTH_DA-1:0] M_RDATA, input M_RLAST,
    input [AXI_WIDTH_ID-1:0] M_RID, input [3:0] M_RUSER, input [1:0] M_RRESP,
       
    output M_AWVALID, input M_AWREADY, output [AXI_WIDTH_AD-1:0] M_AWADDR, output [AXI_WIDTH_ID-1:0] M_AWID,
    output [7:0] M_AWLEN, output [2:0] M_AWSIZE, output [1:0] M_AWBURST, output [1:0] M_AWLOCK,
    output [3:0] M_AWCACHE, output [2:0] M_AWPROT, output [3:0] M_AWQOS, output [3:0] M_AWREGION, output [3:0] M_AWUSER,
    output M_WVALID, input M_WREADY, output [AXI_WIDTH_DA-1:0] M_WDATA, output [AXI_WIDTH_DS-1:0] M_WSTRB,
    output M_WLAST, output [AXI_WIDTH_ID-1:0] M_WID, output [3:0] M_WUSER,
    input M_BVALID, output M_BREADY, input [1:0] M_BRESP, input [AXI_WIDTH_ID-1:0] M_BID, input M_BUSER,
    
    output reg network_done, output network_done_led,
    output [AXI_WIDTH_DA-1:0] read_data_debug, output read_data_vld_debug    
);

assign network_done_led = network_done;
wire ctrl_read; wire read_done; wire [AXI_WIDTH_AD-1:0] read_addr;
wire [AXI_WIDTH_DA-1:0] read_data; wire read_data_vld; wire [15:0] read_data_cnt;
wire [15:0] num_trans = 16; wire [15:0] max_req_blk_idx = (256*256)/16; 
assign read_data_debug = read_data; assign read_data_vld_debug = read_data_vld;

reg ap_start; reg [31:0] dram_base_addr_rd; reg [31:0] dram_base_addr_wr;
wire start_pulse = (!ap_start && i_ctrl_reg0[0]); // 💡 [핵심] 100클럭 리셋 방어용 1클럭 펄스

always @ (posedge clk or negedge rstn) begin
    if(~rstn) begin 
        ap_start <= 0; dram_base_addr_rd <= 0; dram_base_addr_wr <= 0; 
    end else begin 
        if(start_pulse) begin 
            ap_start <= 1; dram_base_addr_rd <= i_ctrl_reg1; dram_base_addr_wr <= i_ctrl_reg2; 
        end else if (ap_start && network_done) begin 
            ap_start <= 0; 
        end 
    end 
end

// 1. DMA READ 
axi_dma_ctrl #(.BIT_TRANS(16)) u_dma_ctrl(
    .clk(clk), .rstn(rstn), .i_start(start_pulse), .i_base_address_rd(dram_base_addr_rd), .i_base_address_wr(dram_base_addr_wr),
    .i_num_trans(num_trans), .i_max_req_blk_idx(max_req_blk_idx),
    .i_read_done(read_done), .o_ctrl_read(ctrl_read), .o_read_addr(read_addr),
    .i_write_done(1'b1), .i_indata_req_wr(1'b0), .o_ctrl_write(), .o_write_addr(), .o_write_data_cnt(), .o_ctrl_write_done()
);

axi_dma_rd #(.BITS_TRANS(16), .OUT_BITS_TRANS(16), .AXI_WIDTH_USER(1), .AXI_WIDTH_ID(4), .AXI_WIDTH_AD(AXI_WIDTH_AD), .AXI_WIDTH_DA(AXI_WIDTH_DA), .AXI_WIDTH_DS(AXI_WIDTH_DS)) u_dma_read(
    .M_ARVALID(M_ARVALID), .M_ARREADY(M_ARREADY), .M_ARADDR(M_ARADDR), .M_ARID(M_ARID), .M_ARLEN(M_ARLEN), .M_ARSIZE(M_ARSIZE), .M_ARBURST(M_ARBURST), .M_ARLOCK(M_ARLOCK),
    .M_ARCACHE(M_ARCACHE), .M_ARPROT(M_ARPROT), .M_ARQOS(M_ARQOS), .M_ARREGION(M_ARREGION), .M_ARUSER(M_ARUSER), .M_RVALID(M_RVALID), .M_RREADY(M_RREADY), .M_RDATA(M_RDATA), .M_RLAST(M_RLAST),
    .M_RID(M_RID), .M_RUSER(M_RUSER), .M_RRESP(M_RRESP),
    .start_dma(ctrl_read), .num_trans(num_trans), .start_addr(read_addr),
    .data_o(read_data), .data_vld_o(read_data_vld), .data_cnt_o(read_data_cnt), .done_o(read_done), .clk(clk), .rstn(rstn)
);

// 2. INPUT BRAM
reg [31:0] read_data_d; reg [63:0] dia_64; reg write_64_en; reg [14:0] addra_64;
reg pack_state; reg [16:0] total_read_cnt; 

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
        read_data_d <= 0; dia_64 <= 0; write_64_en <= 0; addra_64 <= 0; pack_state <= 0; total_read_cnt <= 0;
    end else begin
        if (start_pulse) begin // 💡 [핵심] 여기서 1클럭만 리셋하여 카운터 증발 방지
            total_read_cnt <= 0; addra_64 <= 0; pack_state <= 0; 
        end else if (read_data_vld) begin
            total_read_cnt <= total_read_cnt + 1;
            if (pack_state == 0) begin 
                read_data_d <= read_data; write_64_en <= 0; pack_state <= 1; 
            end else begin 
                dia_64 <= {read_data, read_data_d}; write_64_en <= 1; pack_state <= 0; 
            end
        end else begin
            write_64_en <= 0;
        end
        if (write_64_en) addra_64 <= addra_64 + 1;
    end
end

wire [63:0] in_ram_dob; wire [14:0] in_ram_addrb;
dpram_wrapper #(.DEPTH(32768), .AW(15), .DW(64)) u_in_ram (
    .clk(clk), .ena(1'b1), .wea(write_64_en), .addra(addra_64), .dia(dia_64),
    .enb(1'b1), .addrb(in_ram_addrb), .dob(in_ram_dob)
);

// 3. Weight ROM 
reg [31:0] filter_rom [0: 27*16 - 1]; 
integer w_i;
initial begin
    for(w_i=0; w_i<27*16; w_i=w_i+1) filter_rom[w_i] = 32'd0;
    $readmemh("C:/yolohw/sim/inout_data_sw/log_param/CONV00_param_weight.hex", filter_rom);
end

// 4. 연산 엔진
wire layer_start = (total_read_cnt == 65536);
wire layer_done;
wire [1:0] current_chn;

wire [127:0] win_ch0 = {56'd0, filter_rom[0*27+current_chn*9+8][7:0], filter_rom[0*27+current_chn*9+7][7:0], filter_rom[0*27+current_chn*9+6][7:0], filter_rom[0*27+current_chn*9+5][7:0], filter_rom[0*27+current_chn*9+4][7:0], filter_rom[0*27+current_chn*9+3][7:0], filter_rom[0*27+current_chn*9+2][7:0], filter_rom[0*27+current_chn*9+1][7:0], filter_rom[0*27+current_chn*9+0][7:0]};
wire [127:0] win_ch1 = {56'd0, filter_rom[1*27+current_chn*9+8][7:0], filter_rom[1*27+current_chn*9+7][7:0], filter_rom[1*27+current_chn*9+6][7:0], filter_rom[1*27+current_chn*9+5][7:0], filter_rom[1*27+current_chn*9+4][7:0], filter_rom[1*27+current_chn*9+3][7:0], filter_rom[1*27+current_chn*9+2][7:0], filter_rom[1*27+current_chn*9+1][7:0], filter_rom[1*27+current_chn*9+0][7:0]};
wire [127:0] win_ch2 = {56'd0, filter_rom[2*27+current_chn*9+8][7:0], filter_rom[2*27+current_chn*9+7][7:0], filter_rom[2*27+current_chn*9+6][7:0], filter_rom[2*27+current_chn*9+5][7:0], filter_rom[2*27+current_chn*9+4][7:0], filter_rom[2*27+current_chn*9+3][7:0], filter_rom[2*27+current_chn*9+2][7:0], filter_rom[2*27+current_chn*9+1][7:0], filter_rom[2*27+current_chn*9+0][7:0]};
wire [127:0] win_ch3 = {56'd0, filter_rom[3*27+current_chn*9+8][7:0], filter_rom[3*27+current_chn*9+7][7:0], filter_rom[3*27+current_chn*9+6][7:0], filter_rom[3*27+current_chn*9+5][7:0], filter_rom[3*27+current_chn*9+4][7:0], filter_rom[3*27+current_chn*9+3][7:0], filter_rom[3*27+current_chn*9+2][7:0], filter_rom[3*27+current_chn*9+1][7:0], filter_rom[3*27+current_chn*9+0][7:0]};

wire [31:0] out_pixel0, out_pixel1;
wire out_valid;

dual_conv_layer u_conv_layer(
    .clk(clk), .rstn(rstn),
    .start_i(layer_start), .done_o(layer_done),
    .in_ram_addrb(in_ram_addrb), .in_ram_dob(in_ram_dob),
    .current_chn(current_chn),
    .win_ch0(win_ch0), .win_ch1(win_ch1), .win_ch2(win_ch2), .win_ch3(win_ch3),
    .out_pixel0_32b(out_pixel0), .out_pixel1_32b(out_pixel1), .out_valid(out_valid)
);

// 5. Output Buffer & DMA Write 직렬화 로직
reg write_p1_pending; reg [15:0] out_ram_addra; reg [31:0] out_ram_dia; reg out_ram_wea;
always @(posedge clk or negedge rstn) begin
    if(!rstn) begin 
        out_ram_addra <= 0; out_ram_wea <= 0; write_p1_pending <= 0; out_ram_dia <= 0; 
    end else begin
        if (out_valid) begin
            out_ram_dia <= out_pixel0; out_ram_wea <= 1; write_p1_pending <= 1;
        end else if (write_p1_pending) begin
            out_ram_dia <= out_pixel1; out_ram_wea <= 1; write_p1_pending <= 0;
        end else begin 
            out_ram_wea <= 0; 
        end
        if (out_ram_wea) out_ram_addra <= out_ram_addra + 1; 
        if (start_pulse) out_ram_addra <= 0; 
    end
end

reg [15:0] wr_blk_idx; reg wr_start_dma; wire write_done; wire indata_req_wr; wire [31:0] write_data;
reg dma_writing; 

always @(posedge clk or negedge rstn) begin
    if (!rstn) begin 
        wr_blk_idx <= 0; wr_start_dma <= 0; network_done <= 0; dma_writing <= 0; 
    end else if (layer_done) begin 
        if (wr_blk_idx < max_req_blk_idx) begin
            if (!dma_writing) begin 
                wr_start_dma <= 1; // 💡 [핵심] 1클럭 펄스로 무한루프 방지
                dma_writing <= 1;
            end else begin
                wr_start_dma <= 0;
                if (write_done) begin 
                    wr_blk_idx <= wr_blk_idx + 1; 
                    dma_writing <= 0;
                end
            end
        end else begin
            network_done <= 1;
        end
    end else if (start_pulse) begin 
        network_done <= 0; wr_blk_idx <= 0; dma_writing <= 0;
    end
end

wire [31:0] safe_write_addr = dram_base_addr_wr + (wr_blk_idx * 16 * 4);
reg [16:0] my_write_data_cnt; 
always @(posedge clk or negedge rstn) begin
    if (!rstn) my_write_data_cnt <= 0;
    else begin
        if (wr_start_dma) my_write_data_cnt <= wr_blk_idx * 16;
        else if (indata_req_wr) my_write_data_cnt <= my_write_data_cnt + 1;
    end
end

dpram_wrapper #(.DEPTH(65536), .AW(16), .DW(32)) u_out_ram (
    .clk(clk), .ena(1'b1), .wea(out_ram_wea), .addra(out_ram_addra), .dia(out_ram_dia),
    .enb(1'b1), .addrb(my_write_data_cnt[15:0]), .dob(write_data) 
);

axi_dma_wr #(.BITS_TRANS(16), .OUT_BITS_TRANS(16), .AXI_WIDTH_USER(1), .AXI_WIDTH_ID(4), .AXI_WIDTH_AD(AXI_WIDTH_AD), .AXI_WIDTH_DA(AXI_WIDTH_DA), .AXI_WIDTH_DS(AXI_WIDTH_DS)) u_dma_write(
    .M_AWID(M_AWID), .M_AWADDR(M_AWADDR), .M_AWLEN(M_AWLEN), .M_AWSIZE(M_AWSIZE), .M_AWBURST(M_AWBURST), .M_AWLOCK(M_AWLOCK), .M_AWCACHE(M_AWCACHE), .M_AWPROT(M_AWPROT), .M_AWQOS(M_AWQOS), .M_AWREGION(M_AWREGION), .M_AWUSER(M_AWUSER), .M_AWVALID(M_AWVALID), .M_AWREADY(M_AWREADY),
    .M_WID(M_WID), .M_WDATA(M_WDATA), .M_WSTRB(M_WSTRB), .M_WLAST(M_WLAST), .M_WUSER(M_WUSER), .M_WVALID(M_WVALID), .M_WREADY(M_WREADY),
    .M_BID(M_BID), .M_BRESP(M_BRESP), .M_BUSER(M_BUSER), .M_BVALID(M_BVALID), .M_BREADY(M_BREADY),
    .start_dma(wr_start_dma), .num_trans(num_trans), .start_addr(safe_write_addr),
    .indata(write_data), .indata_req_o(indata_req_wr), .done_o(write_done), .clk(clk), .rstn(rstn)
);

endmodule
