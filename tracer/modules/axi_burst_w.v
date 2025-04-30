`timescale 1ns/1ps

module AXIBurstWriteEngine #(
    BufferDataWidth = 32,
    BufferAddrWidth = 10,
    AXIAddrWidth = 64,
    AXIDataWidth = 32,
    AXIIDWdith = 4,
    AXIMaxBurstLen = 64 // unlike AxLEN, this is 0-based
) (
    input clk,
    input reset,

    // simple control interface
    input start_valid,
    output start_ready,
    output done_valid,
    input done_ready,

    // accepting burst parameters
    input [BufferAddrWidth-1:0] data_ptr,
    input [BufferAddrWidth-1:0] data_size,
    input [AXIAddrWidth-1:0] axi_offset,

    // interface to read from data buffer
    output [BufferAddrWidth-1:0] buffer_addr,
    input [BufferDataWidth-1:0] buffer_data,
    output buffer_ce,
    output buffer_we,

    // interface to write to AXI
    // AR channel
    output [AXIAddrWidth-1:0] araddr,
    output [AXIIDWdith-1:0] arid,
    output [7:0] arlen,
    output [2:0] arsize,
    output [1:0] arburst,
    output arvalid,
    input arready,
    // R channel
    input [AXIDataWidth-1:0] rdata,
    input [AXIIDWdith-1:0] rid,
    input rlast,
    input rvalid,
    output rready,
    input [1:0] rresp,
    // AW channel
    output [AXIAddrWidth-1:0] awaddr,
    output [AXIIDWdith-1:0] awid,
    output [7:0] awlen,
    output [2:0] awsize,
    output [1:0] awburst,
    output awvalid,
    input awready,
    // W channel
    output [AXIDataWidth-1:0] wdata,
    output [AXIDataWidth/8-1:0] wstrb,
    output [AXIIDWdith-1:0] wid,
    output wlast,
    output wvalid,
    input wready,
    // B channel
    input [AXIIDWdith-1:0] bid,
    input bvalid,
    output bready,
    input [1:0] bresp
);

//==============================================================================
// Constants
//==============================================================================
localparam AXI_BURST_INCR = 2'b01;
localparam AXI_BURST_SIZE = AXIDataWidth / 8; // full-word

//==============================================================================
// Datapath
//==============================================================================
// input registers
reg [BufferAddrWidth-1:0] data_ptr_reg;
reg [BufferAddrWidth-1:0] data_size_reg;
reg [AXIAddrWidth-1:0] axi_offset_reg;

always @(posedge clk) begin
    if (reset) begin
        data_ptr_reg <= 0;
        data_size_reg <= 0;
        axi_offset_reg <= 0;
    end else if (start_ready & start_valid) begin
        data_ptr_reg <= data_ptr;
        data_size_reg <= data_size;
        axi_offset_reg <= axi_offset;
    end
end

// execution schedule registers
reg [7:0] num_batches;
reg [8:0] last_batch_size;
wire calc_num_batches;
wire calc_last_batch_size;

always @(posedge clk) begin
    if (reset) num_batches <= 0;
    else if (calc_num_batches)
        num_batches <= (data_size_reg + AXIMaxBurstLen - 1) / AXIMaxBurstLen;
end

always @(posedge clk) begin
    if (reset) last_batch_size <= 0;
    else if (calc_last_batch_size)
        last_batch_size <=
            (data_size_reg % AXIMaxBurstLen) ?
            (data_size_reg % AXIMaxBurstLen) : AXIMaxBurstLen;
end

// progress counters
reg [7:0] batch_counter;
reg [8:0] burst_counter;
wire clear_batch_counter;
wire clear_burst_counter;
wire incr_batch_counter;
wire incr_burst_counter;

always @(posedge clk) begin
    if (reset) begin
        batch_counter <= 0;
        burst_counter <= 0;
    end else begin
        if (clear_batch_counter) batch_counter <= 0;
        else if (incr_batch_counter) batch_counter <= batch_counter + 1;
        if (clear_burst_counter) burst_counter <= 0;
        else if (incr_burst_counter) burst_counter <= burst_counter + 1;
    end
end

// axi aw channel signal registers
reg [AXIAddrWidth-1:0] awaddr_reg;
reg [AXIIDWdith-1:0] awid_reg; // always 0
reg [7:0] awlen_reg; 
wire init_awaddr_reg;
wire incr_awaddr_reg;
wire update_awlen_reg;

always @(posedge clk) begin
    if (reset) begin
        awaddr_reg <= 0;
        awid_reg <= 0;
        awlen_reg <= 0;
    end else begin
        if (init_awaddr_reg)
            awaddr_reg <= axi_offset_reg;
        else if (incr_awaddr_reg)
            awaddr_reg <= awaddr_reg + AXIMaxBurstLen * AXIDataWidth / 8;
        if (update_awlen_reg)
            awlen_reg <=
                (batch_counter == num_batches - 1) ?
                last_batch_size - 1 : AXIMaxBurstLen - 1;
    end
end


//==============================================================================
// Control FSM
//==============================================================================

// states
localparam
    IDLE   = 4'd0,
    PREP   = 4'd1, // calculate number of batches and last batch size
    PRE_AW = 4'd2, // calculate awaddr and awlen
    AW     = 4'd3, // issue write transaction
    W1     = 4'd4, // load the first data from buffer
    W2     = 4'd5, // write pipeline fully loaded
    W3     = 4'd6, // waiting for AXI write to complete
    B      = 4'd7, // wait for response
    DONE   = 4'd8; // done

// Note: RAM-AXI write pipeline
/*
 === Write pipeline ===
        |            Stage R           |   Stage A   |
 [burst_counter] -(+data_ptr_reg)-> [buffer] --> [AXI WDATA]

 There are three possible states for the write pipeline:
 1: only the R stage is active. Happens when the pipeline is starting up.
 2: both R and A stages are active. Happens when the pipeline is fully loaded.
 3: only the A stage is active. Happens when the pipeline is emptying or stalled by AXI back pressure (i.e. wready == 0).

 Example:
 1|2|2|3|3|3|2|3
 R|A
   R|A
     R|A|A|A|A
             R|A

 === Transitions ===
         ┌────┐
         V    |
 -> 1 -> 2 -> 3 ->
    |         ^
    └─────────┘

 1 -> 2: wready == 1
 1 -> 3: wready == 0
 2 -> 3: wready == 0
 3 -> 2: wready == 1 && burst_counter < awlen_reg
 3 ->  : wready == 1 && burst_counter == awlen_reg

 === Outputs ===
 wvalid: state == 2 || state == 3
 incr_burst_counter: wready & wvalid
*/

reg [3:0] state, next_state;

always @(posedge clk) begin
    if (reset) state <= IDLE;
    else state <= next_state;
end

// state transition logic
always @(*) begin
    case (state)
        IDLE:
            next_state = start_valid ? PREP : IDLE;
        PREP:
            next_state = PRE_AW;
        PRE_AW:
            next_state = AW;
        AW:
            next_state = awready ? W1 : AW;
        W1:
            next_state = wready ? W2 : W3;
        W2:
            next_state = (wready == 0) || (burst_counter == awlen_reg) ? W3 : W2;
        W3:
            next_state = wready ?
                            (burst_counter == awlen_reg) ?
                            B : W2
                         : W3;
        B:
            next_state = bvalid ?
                            (batch_counter == num_batches - 1) ?
                            DONE : PRE_AW
                         : B;
        DONE:
            next_state = done_ready ? IDLE : DONE;
        default: 
            next_state = IDLE;
    endcase
end

// fsm output control signals
assign start_ready = (state == IDLE);
assign done_valid = (state == DONE);
assign calc_last_batch_size = (state == PREP);
assign calc_num_batches = (state == PREP);
assign clear_batch_counter = (state == PREP);
assign clear_burst_counter = (state == AW);
assign incr_batch_counter = (state == B & bvalid & bready);
assign incr_burst_counter = wvalid & wready & (burst_counter < awlen_reg);
assign init_awaddr_reg = (state == PRE_AW) && batch_counter == 0;
assign incr_awaddr_reg = (state == AW & awvalid & awready);
assign update_awlen_reg = (state == PRE_AW);
assign buffer_addr = data_ptr_reg + batch_counter * AXIMaxBurstLen + (burst_counter + (state == W2 ? 1 : 0));
assign buffer_ce = (state == W1 || state == W2);
assign buffer_we = 1'b0;

assign araddr = 'dx;
assign arid = 'dx;
assign arlen = 'dx;
assign arsize = 'dx;
assign arburst = 'dx;
assign arvalid = 1'b0;
assign rready = 1'b0;

assign awaddr = awaddr_reg;
assign awid = 'd0;
assign awlen = awlen_reg;
assign awsize = AXI_BURST_SIZE;
assign awburst = AXI_BURST_INCR;
assign awvalid = (state == AW);

assign wdata = buffer_data;
assign wstrb = {AXIDataWidth/8{1'b1}};
assign wid = 'd0;
assign wvalid = (state == W2);
assign wlast = (burst_counter == awlen_reg);

assign bready = (state == B);

endmodule