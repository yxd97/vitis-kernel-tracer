`timescale 1ns/1ps

module TraceFormatter #(
    AXIAddrWidth = 64,
    AXIDataWidth = 32,
    TimestampWidth = 32
) (
    input clk,
    input reset,

    // AXI AW signals
    input [AXIAddrWidth-1:0] awaddr,
    input awvalid,
    input awready,

    input [TimestampWidth-1:0] timestamp, 

    // Outputs
    output reg [AXIAddrWidth-1:0] awaddr_out,
    output reg [TimestampWidth-1:0] awtimestamp_out,
    output reg awtrace_valid
);

wire awevent = awvalid & awready;

always @ (posedge clk) begin
    if (reset) begin
        awtimestamp_out <= 'd0;
        awtrace_valid <= 'd0;
        awaddr_out <= 'dx;
    end else if (awevent) begin
        awaddr_out <= awaddr;
        awtimestamp_out <= timestamp;
        awtrace_valid <= 'd1; 
    end else awtrace_valid <= 'd0; // Deasserts on next clock edge if no handshake
end
endmodule