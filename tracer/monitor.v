`timescale 1ns/1ps

module ValRdyMonitor #(
    TargetDataWidth = 32,
    BufferDataWidth = 32,
    BufferAddrWidth = 10
) (
    input clk,
    input reset,

    // interface being monitored
    input [TargetDataWidth-1:0] target_data,
    input target_valid,
    output target_ready,

    // interface to write to trace buffer
    output [BufferAddrWidth-1:0] buffer_addr,
    output [BufferDataWidth-1:0] buffer_data,
    output buffer_ce,
    output buffer_we,

    // interface to ping-pong control fifos
    // aquiring free blocks
    output monitor_aquire_valid,
    input monitor_aquire_ready,
    // submitting occupied blocks
    output monitor_submit_valid,
    input monitor_submit_ready,
    output [BufferAddrWidth-1:0] monitor_submit_size
);

endmodule