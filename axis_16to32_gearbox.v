`timescale 1ns / 1ps

module axis_16to32_gearbox(
    input wire clk,
    input wire rstn,

    // ----------------------------------------------------
    // Slave Interface (Dual CNN Layer에서 16-bit 출력 받음)
    // ----------------------------------------------------
    input  wire [15:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready, 

    // ----------------------------------------------------
    // Master Interface (Write FIFO / DMA로 32-bit 데이터 보냄)
    // ----------------------------------------------------
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tvalid, 
    input  wire        m_axis_tready  
);

    reg state; // 0: 첫 번째 16-bit 대기, 1: 두 번째 16-bit 대기
    reg [15:0] lower_data_reg;

    // CNN 레이어는 상태 0이거나, 상태 1이면서 DMA가 받을 준비가 되었을 때 데이터를 보낼 수 있음
    assign s_axis_tready = (state == 1'b0) ? 1'b1 : m_axis_tready;
    
    // 출력 데이터는 먼저 들어온 16비트(하위)와 지금 들어온 16비트(상위)를 합침
    assign m_axis_tdata  = {s_axis_tdata, lower_data_reg};
    
    // 상태 1(두 번째 데이터)이면서 CNN에서 유효한 데이터가 올 때만 32비트 Valid를 띄움
    assign m_axis_tvalid = (state == 1'b1) ? s_axis_tvalid : 1'b0;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= 1'b0;
            lower_data_reg <= 16'd0;
        end else begin
            if (state == 1'b0) begin
                if (s_axis_tvalid) begin
                    lower_data_reg <= s_axis_tdata; // 첫 번째 16비트 저장
                    state <= 1'b1;                  // 다음 상태로 이동
                end
            end else begin // state == 1'b1
                if (s_axis_tvalid && m_axis_tready) begin
                    state <= 1'b0;                  // 32비트 전송 완료, 다시 처음으로!
                end
            end
        end
    end
endmodule