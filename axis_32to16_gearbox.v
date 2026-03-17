`timescale 1ns / 1ps

module axis_32to16_gearbox (
    input wire clk,
    input wire rstn,

    // ----------------------------------------------------
    // Slave Interface (DMA / FIFO에서 32-bit 데이터를 받음)
    // ----------------------------------------------------
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready, // 우리가 받을 준비가 되었음을 DMA에 알림

    // ----------------------------------------------------
    // Master Interface (Dual CNN Layer로 16-bit 데이터를 보냄)
    // ----------------------------------------------------
    output wire [15:0] m_axis_tdata,
    output wire        m_axis_tvalid, // 우리가 보내는 데이터가 유효함을 알림
    input  wire        m_axis_tready  // CNN 제어기가 받을 준비가 되었는지 확인
);

    // FSM State 정의
    localparam SEL_LOWER = 1'b0; // 하위 16비트 처리 상태
    localparam SEL_UPPER = 1'b1; // 상위 16비트 처리 상태

    reg state;
    reg [15:0] upper_data_reg; // 상위 16비트를 임시로 담아둘 보관소

    // ----------------------------------------------------
    // 1. Ready 신호 생성 (Slave Ready)
    // ----------------------------------------------------
    // 하위 16비트를 처리하는 상태(SEL_LOWER)이고, CNN(Master)이 받을 준비가 
    // 되어있을 때만 DMA(Slave)로부터 새로운 32-bit 데이터를 받습니다.
    assign s_axis_tready = (state == SEL_LOWER) ? m_axis_tready : 1'b0;

    // ----------------------------------------------------
    // 2. Data 및 Valid 신호 생성 (Master Data & Valid)
    // ----------------------------------------------------
    // 상태에 따라 하위 16비트는 그대로 통과시키고, 상위 16비트는 레지스터에서 꺼냅니다.
    assign m_axis_tdata  = (state == SEL_LOWER) ? s_axis_tdata[15:0] : upper_data_reg;
    
    // SEL_LOWER일 때는 입력 valid를 그대로 따르고, SEL_UPPER일 때는 항상 유효합니다(이미 데이터를 물고 있으므로).
    assign m_axis_tvalid = (state == SEL_LOWER) ? s_axis_tvalid : 1'b1;

    // ----------------------------------------------------
    // 3. FSM 및 데이터 래치(Latch) 로직
    // ----------------------------------------------------
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= SEL_LOWER;
            upper_data_reg <= 16'd0;
        end else begin
            if (state == SEL_LOWER) begin
                // DMA에서 유효한 데이터가 들어오고, CNN이 받을 준비가 되었다면 (Handshake 성공)
                if (s_axis_tvalid && m_axis_tready) begin
                    // 하위 16비트는 이미 조합회로(assign)로 날아갔음.
                    // 상위 16비트를 다음 클럭에 쏘기 위해 안전하게 레지스터에 보관!
                    upper_data_reg <= s_axis_tdata[31:16];
                    state <= SEL_UPPER; // 다음 클럭엔 상위 16비트를 쏜다!
                end
            end else begin // state == SEL_UPPER
                // CNN이 상위 16비트를 성공적으로 받아갔다면 (Handshake 성공)
                if (m_axis_tready) begin
                    state <= SEL_LOWER; // 다시 새로운 32-bit를 받으러 돌아감!
                end
            end
        end
    end

endmodule