//----------------------------------------------------------------+
// Project: Deep Learning Hardware Design Contest
// Module: sram.v (32-bit Hex to 16-bit RAM Safe Loader)
//----------------------------------------------------------------+

module sram (
    clk,
    rst,
    addr,
    wdata,
    rdata,
    ena
);

  parameter FILE_NAME  = "undefined.mmap";
  parameter INST_NAME  = "SimmemSync_rp0_wp0_cp1";
  parameter SIZE       = 32'd4194304; // 22-bit address space
  parameter WL_ADDR    = 32'd22;
  parameter WL_DATA    = 32'd16;      // 💡 16-bit 메모리 유지 (sram_ctrl.v 에러 방지)
  parameter RESET_POL  = 1'b0;        

  input                clk;   
  input                rst;   
  input  [WL_ADDR-1:0] addr;  
  input  [WL_DATA-1:0] wdata; 
  output [WL_DATA-1:0] rdata; 
  input                ena;   

  `ifdef SYNTHESIS
  `else

  reg  [WL_DATA-1:0] mem[0:SIZE-1];   
  wire               intrst;          
  wire [WL_DATA-1:0] tmp_rdata;
  reg  [WL_DATA-1:0] rdata;

  assign intrst = (RESET_POL == 1'b0) ? rst : ~rst;

  // 💡 [핵심 수술 부위] 32비트 파일을 읽어서 16비트 RAM에 완벽하게 쪼개 넣기
  reg [31:0] temp_hex_array [0 : (SIZE/2)-1]; // 32비트 임시 버퍼
  integer i;
  initial begin: PROC_SimmemLoad
      $display ("Initializing and Loading memory '%s' from file: %s", INST_NAME, FILE_NAME);
      
      // 1. 메모리 초기화
      for (i = 0; i < SIZE; i = i + 1) mem[i] = 0;
      
      // 2. 32비트 파일 읽기
      if (FILE_NAME != "") begin
          $readmemh(FILE_NAME, temp_hex_array);
          // 3. 16비트로 쪼개서 넣기 (Little Endian 방식으로 순차 적재)
          for (i = 0; i < SIZE/2; i = i + 1) begin
              mem[i*2]     = temp_hex_array[i][15:0];  // 하위 16비트를 짝수 번지에
              mem[i*2 + 1] = temp_hex_array[i][31:16]; // 상위 16비트를 홀수 번지에
          end
      end
  end

  always @(posedge clk) begin: PROC_SimmemWrite
    if (ena == 1'b1) begin
      mem[addr] <= wdata;
    end
  end

  assign  tmp_rdata = mem[addr];

  always  @(posedge clk) begin
     rdata <= tmp_rdata;
  end

  always @(intrst) begin
   if (intrst == 1'b0) begin
     rdata <= 0;
    end
  end

  `endif

endmodule