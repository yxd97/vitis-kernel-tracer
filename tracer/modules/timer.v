`timescale 1ns/1ps

module Timer #(
    TimestampWidth = 32
) (
    input clk,
    input reset,

    output reg [TimestampWidth-1:0] timestamp
);

always @ (posedge clk) begin
    if(reset) timestamp <= 'd0;
    else timestamp <= timestamp + 1; // increment timestamp every cycle
end
endmodule