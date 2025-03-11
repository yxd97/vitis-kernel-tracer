`timescale 1ns/1ps

module testbench;

//==============================================================================
// config
//==============================================================================

localparam AXIAddrWidth = 32;
localparam AXIDataWidth = 32;
localparam TimestampWidth = 32;

//==============================================================================
// clock
//==============================================================================

localparam ClockPeriod = 10.0; // ns
logic clk = 1'b0;

always begin
    #(ClockPeriod/2) clk = ~clk;
end

task tick (int cycles);
    #(cycles * ClockPeriod);
endtask

logic reset;

//==============================================================================
// Timer instance
//==============================================================================
logic [TimestampWidth-1:0] timestamp;
Timer #(
    .TimestampWidth(TimestampWidth)
) timer (
    .clk(clk),
    .reset(reset),
    .timestamp(timestamp)
);

//==============================================================================
// Trace Formatter instance
//==============================================================================
logic [AXIAddrWidth-1:0] awaddr;
logic awvalid, awready;

logic [AXIAddrWidth-1:0] awaddr_out;
logic [TimestampWidth-1:0] awtimestamp_out;
logic awtrace_valid;

TraceFormatter #(
    .AXIAddrWidth(AXIAddrWidth),
    .AXIDataWidth(AXIDataWidth),
    .TimestampWidth(TimestampWidth)
) tracer (
    .clk(clk),
    .reset(reset),

    .awaddr(awaddr),
    .awvalid(awvalid),
    .awready(awready),

    .timestamp(timestamp),
    .awaddr_out(awaddr_out),
    .awtimestamp_out(awtimestamp_out),
    .awtrace_valid(awtrace_valid)
);

//==============================================================================
// Test functions
//==============================================================================

task automatic generate_aw_event(logic [AXIAddrWidth-1:0] input_addr);
    $display("AW event at address: 0x%h", input_addr);

    reset = 1;
    tick(2);
    reset = 0;

    awaddr = input_addr;

    // AWevent
    tick(1);
    awvalid = 1;
    awready = 1;

    // tick(3);
    @(posedge clk);
    @(posedge clk);

    assert (awtrace_valid)
    else $fatal("ERROR: awtrace_valid not asserted despite handshake");

    assert(awaddr_out == input_addr) 
    else $fatal("ERROR: Address mismatch! Expected: %h, Got: %h", input_addr, awaddr_out);

    // Deassert
    awvalid = 0;
    awready = 0;
    tick(3);

    assert (!awtrace_valid)
    else $fatal("ERROR: awtrace_valid not deasserted after both are set to zero");

endtask

//==============================================================================
// Test
//==============================================================================
initial begin
    reset = 1;

    $display("=====AW Trace Formatter test=====");

    generate_aw_event('hABCDABCD);
    tick(5);
    
    generate_aw_event('h1234);
    tick(5);

    generate_aw_event('hFFFFFFFF);
    tick(5);

    $display("All tests passed");
end

endmodule