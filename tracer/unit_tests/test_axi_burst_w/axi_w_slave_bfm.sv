`timescale 1ns/1ps
//! Note: this module is not synthesizable

module AXIWriteOnlySlaveBFM #(
    AddressWidth = 32,
    DataWidth = 32,
    IDWidth = 1,
    MaxBurstLen = 16,
    MaxOutstandingWrites = 16,
    NumMemoryWords = 0
) (
    input clk,
    input reset,

    input bit aw_random_stall,
    input real aw_stall_prob,
    input int aw_stall_min,
    input int aw_stall_max,

    input bit w_random_stall,
    input real w_stall_prob,
    input int w_stall_min,
    input int w_stall_max,

    input bit b_random_stall,
    input real b_stall_prob,
    input int b_stall_min,
    input int b_stall_max,

    input [$clog2(NumMemoryWords)-1:0] mem_peek_addr,
    output [DataWidth-1:0] mem_peek_data,

    // AR channel
    input logic [AddressWidth-1:0] araddr,
    input logic [IDWidth-1:0] arid,
    input logic [7:0] arlen,
    input logic [2:0] arsize,
    input logic [1:0] arburst,
    input logic arvalid,
    output logic arready,
    // R channel
    output logic [DataWidth-1:0] rdata,
    output logic [IDWidth-1:0] rid,
    output logic [1:0] rresp,
    output logic rlast,
    input logic rready,
    output logic rvalid,
    // AW channel
    input logic [AddressWidth-1:0] awaddr,
    input logic [IDWidth-1:0] awid,
    input logic [7:0] awlen,
    input logic [2:0] awsize,
    input logic [1:0] awburst,
    input logic awvalid,
    output logic awready,
    // W channel
    input logic [DataWidth-1:0] wdata,
    input logic [DataWidth/8-1:0] wstrb,
    input logic [IDWidth-1:0] wid,
    input logic wlast,
    input logic wvalid,
    output logic wready,
    // B channel
    output logic [IDWidth-1:0] bid,
    output logic [1:0] bresp,
    input logic bready,
    output logic bvalid
);

// disable read channels
assign arready = 0;
assign rdata = 'dx;
assign rid = 'dx;
assign rresp = 'dx;
assign rlast = 0;
assign rvalid = 0;

// initialize write channels
initial begin
    awready = 0;
    wready = 0;
    bvalid = 0;
    bid = 'dx;
    bresp = 'dx;
end

// combinational memory model
logic [DataWidth-1:0] memory [0:NumMemoryWords-1];

// memory peek
assign mem_peek_data = memory[mem_peek_addr];

// outstanding transaction queue (OTQ)
// entry format: {status, ID}
// status
localparam W_PENDING_DATA = 2'd0;
localparam W_ACTIVE = 2'd1;
localparam W_PENDING_RESP = 2'd2;
localparam OTQ_BITWIDTH = 2 + IDWidth;
logic [OTQ_BITWIDTH-1:0] otq [0:MaxOutstandingWrites-1];
int otq_size = 0;
always @(posedge clk) begin
    if (reset) otq_size <= 0;
end

// AW logic
int aw_stall_countdown = 0;
always @(posedge clk) begin
    if (aw_random_stall) begin
        if (aw_stall_countdown == 0) begin
            if ($urandom_range(0, 100) < aw_stall_prob * 100) begin
                aw_stall_countdown <= $urandom_range(aw_stall_min, aw_stall_max);
            end
        end else aw_stall_countdown <= aw_stall_countdown - 1;
    end else aw_stall_countdown <= 0;
end
assign awready = (otq_size < MaxOutstandingWrites) && (!aw_random_stall || (aw_random_stall && aw_stall_countdown == 0));
always @(posedge clk) begin
    if (awvalid & awready) begin
        otq[otq_size] <= {W_PENDING_DATA, awid};
        otq_size <= otq_size + 1;
    end
end

// W logic
int w_stall_countdown = 0;
always @(posedge clk) begin
    if (w_random_stall) begin
        if (w_stall_countdown == 0) begin
            if ($urandom_range(0, 100) < w_stall_prob * 100) begin
                w_stall_countdown <= $urandom_range(w_stall_min, w_stall_max);
            end
        end else w_stall_countdown <= w_stall_countdown - 1;
    end else w_stall_countdown <= 0;
end
assign wready = !w_random_stall || (w_random_stall && w_stall_countdown == 0);
always @(posedge clk) begin
    if (wvalid & wready) begin
        // use blocking assignment so that we can immediately peek the value
        memory[awaddr >> $clog2(DataWidth/8)] = wdata;
        if (wlast) begin
            // trun the earliest entry in OTQ that is active to pending response
            // since AXI4 does not allow write data interleaving
            for (int i = 0; i < otq_size; i = i + 1) begin
                if (otq[i][OTQ_BITWIDTH-1:IDWidth] == W_ACTIVE) begin
                    otq[i] <= {W_PENDING_RESP, otq[i][IDWidth-1:0]};
                    // optionally: check for id match
                    assert(otq[i][IDWidth-1:0] == wid);
                    break;
                end
            end
        end else begin
            // turn the earliest entry in OTQ that is pending data to active
            for (int i = 0; i < otq_size; i = i + 1) begin
                if (otq[i][OTQ_BITWIDTH-1:IDWidth] == W_PENDING_DATA) begin
                    otq[i] <= {W_ACTIVE, otq[i][IDWidth-1:0]};
                    // optionally: check for id match
                    assert(otq[i][IDWidth-1:0] == wid);
                    break;
                end
            end
        end
    end
end

// B logic
int b_stall_countdown = 0;
always @(posedge clk) begin
    if (b_random_stall) begin
        if (b_stall_countdown == 0) begin
            if ($urandom_range(0, 100) < b_stall_prob * 100) begin
                b_stall_countdown <= $urandom_range(b_stall_min, b_stall_max);
            end
        end else b_stall_countdown <= b_stall_countdown - 1;
    end else b_stall_countdown <= 0;
end
assign bvalid = (otq_size > 0) && (!b_random_stall || (b_random_stall && b_stall_countdown == 0));
assign bid = bvalid ? otq[0][IDWidth-1:0] : 'dx;
assign bresp = 0; // always return OKAY for now
always @(posedge clk) begin
    if (bready & bvalid) begin
        // move the OTQ entries up
        for (int i = 0; i < otq_size - 1; i = i + 1) begin
            otq[i] <= otq[i + 1];
        end
        otq_size <= otq_size - 1;
    end
end

endmodule
