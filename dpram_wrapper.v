`timescale 1ns/1ns

module dpram_wrapper #(
    parameter DW = 64,          
    parameter AW = 8,           
    parameter DEPTH = 256,      
    parameter N_DELAY = 1      
)(  
    input                   clk,
    input                   ena,
    input [AW-1 : 0]        addra,  
    input                   wea,    
    input [DW-1 : 0]        dia,    
    input                   enb,
    input [AW-1 : 0]        addrb,  
    output [DW-1 : 0]       dob    
);

// 💡 Vivado BRAM 자동 추론 속성
(* ram_style = "block" *) reg [DW-1 : 0] ram [0 : DEPTH-1];

// Port A: Write
always @(posedge clk) begin
    if(ena && wea) begin
        ram[addra] <= dia;
    end
end 

// Port B: Read
generate 
    if(N_DELAY == 1) begin: delay_1
        reg [DW-1:0] rdata; 
        always @(posedge clk) begin: read
            if(enb) rdata <= ram[addrb];
        end
        assign dob = rdata;
    end
    else begin: delay_n
        reg [N_DELAY*DW-1:0] rdata_r;
        always @(posedge clk) begin: read
            if(enb) rdata_r[0 +: DW] <= ram[addrb];
        end
        always @(posedge clk) begin: delay
            integer i;
            for(i = 0; i < N_DELAY-1; i = i+1) begin
                if(enb) rdata_r[(i+1)*DW +: DW] <= rdata_r[i*DW +: DW];
            end
        end
        assign dob = rdata_r[(N_DELAY-1)*DW +: DW];
    end
endgenerate

endmodule