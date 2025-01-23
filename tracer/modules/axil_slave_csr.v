`timescale 1ns/1ps

// Control-State Registers (CSR) mapped to a slave AXI-Lite interface

module SlaveAXILiteCSR #(
    parameter AddrWidth = 32
) (
    // clock and reset
    input clk,
    input reset,

    // AR channel
    input [AddrWidth-1:0] araddr,
    input arvalid,
    output arready,

    // R channel
    output [31:0] rdata,
    output rvalid,
    input rready,
    output [1:0] rresp,

    // AW channel
    input [AddrWidth-1:0] awaddr,
    input awvalid,
    output awready,

    // W channel
    input [31:0] wdata,
    input [7:0] wstrb,
    input wvalid,
    output wready,

    // B channel
    output bvalid,
    input bready,
    output [1:0] bresp,

    // ap_ctrl_hs interface
    output ap_start,
    input ap_done,
    input ap_ready,
    input ap_idle,

    // CSR registers
    output [63:0] trace_dump,
    input [31:0] tracer_return_code
);

// Register address mapping
localparam CTRL    = 0;  // ap_ctrl_hs
localparam GIER    = 1;  // Global Interrupt Enable Register
localparam IP_IER  = 2;  // Interrupt Enable Register
localparam IP_ISR  = 3;  // Interrupt Status Register
localparam TDUMP_L = 4;  // Trace Dump Register
// 4-byte reserved for parameter-level control
localparam TDUMP_H = 6;  // Trace Dump Register
// 4-byte reserved for parameter-level control
localparam TRET    = 8;  // Tracer Return Code Register

reg [31:0] csrs [0:8];

endmodule