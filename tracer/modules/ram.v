`timescale 1ns/1ps

module RAM2P_BRAM #(
    parameter DataWidth = 32,
    parameter AddrWidth = 10
) (
    input clk,
    input [AddrWidth-1:0] addr0,
    input [DataWidth-1:0] data0,
    input ce0,
    input we0,
    output reg [DataWidth-1:0] q0,
    input [AddrWidth-1:0] addr1,
    input [DataWidth-1:0] data1,
    input ce1,
    input we1,
    output reg [DataWidth-1:0] q1
);

(* ram_style = "block" *) reg [DataWidth-1:0] ram [0:2**AddrWidth-1];

always @(posedge clk) begin
    if (ce0) begin
        if (we0) begin
            ram[addr0] <= data0;
        end
        q0 <= ram[addr0];
    end
end

always @(posedge clk) begin
    if (ce1) begin
        if (we1) begin
            ram[addr1] <= data1;
        end
        q1 <= ram[addr1];
    end
end

endmodule
