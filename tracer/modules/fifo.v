`timescale 1ns/1ps

module FIFO #(
    DataWidth = 32,
    Depth = 16
) (
    input clk,
    input reset,
    input [DataWidth-1:0] d,
    input push,
    output full,
    input pop,
    output [DataWidth-1:0] q,
    output empty
);

localparam awidth = $clog2(Depth);

reg [DataWidth-1:0] mem [0:Depth-1];
reg [awidth-1:0] head, tail;

assign full = (head == tail - 1) || (head == Depth-1 && tail == 0);
assign empty = (head == tail);

always @(posedge clk) begin
    if (reset) begin
        head <= 0;
        tail <= 0;
    end else begin
        if (push && !full) begin
            mem[head] <= d;
            if (head == Depth) head = 0;
            else head = head + 1;
        end
        if (pop && !empty) begin
            if (tail == Depth) tail = 0;
            else tail = tail + 1;
        end
    end
end

assign q = mem[tail];

endmodule
