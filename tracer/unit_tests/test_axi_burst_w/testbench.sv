`timescale 1ns/1ps

module testbench;

//==============================================================================
// config
//==============================================================================

localparam AXIAddrWdith = 32;
localparam AXIDataWidth = 32;
localparam AXIIDWidth = 1;
localparam AXIMaxBurstLen = 16;
localparam AXIMaxOutstandingWrites = 1;
localparam AXINumMemoryWords = 1024; // 4 KB address space
localparam DataBufferAddrWidth = 8; // 256 words (1 KB)
localparam DataBufferDataWidth = 32;

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
// AXI Slave Write-only BFM
//==============================================================================

bit aw_random_stall;
real aw_stall_prob;
int aw_stall_min;
int aw_stall_max;

bit w_random_stall;
real w_stall_prob;
int w_stall_min;
int w_stall_max;

bit b_random_stall;
real b_stall_prob;
int b_stall_min;
int b_stall_max;

logic [$clog2(AXINumMemoryWords)-1:0] mem_peek_addr;
logic [AXIDataWidth-1:0] mem_peek_data;

// AR channel signals
logic [AXIAddrWdith-1:0] araddr;
logic [AXIIDWidth-1:0] arid;
logic [7:0] arlen;
logic [2:0] arsize;
logic [1:0] arburst;
logic arvalid;
logic arready;
// R channel
logic [AXIDataWidth-1:0] rdata;
logic [AXIIDWidth-1:0] rid;
logic [1:0] rresp;
logic rlast;
logic rready;
logic rvalid;
// AW channel
logic [AXIAddrWdith-1:0] awaddr;
logic [AXIIDWidth-1:0] awid;
logic [7:0] awlen;
logic [2:0] awsize;
logic [1:0] awburst;
logic awvalid;
logic awready;
// W channel
logic [AXIDataWidth-1:0] wdata;
logic [AXIDataWidth/8-1:0] wstrb;
logic [AXIIDWidth-1:0] wid;
logic wlast;
logic wvalid;
logic wready;
// B channel
logic [AXIIDWidth-1:0] bid;
logic [1:0] bresp;
logic bready;
logic bvalid;

AXIWriteOnlySlaveBFM #(
    .AddressWidth(AXIAddrWdith),
    .DataWidth(AXIDataWidth),
    .IDWidth(AXIIDWidth),
    .MaxBurstLen(AXIMaxBurstLen),
    .MaxOutstandingWrites(AXIMaxOutstandingWrites),
    .NumMemoryWords(AXINumMemoryWords)
) bfm (
    .*
);

//==============================================================================
// Data Buffer: contains the data to be written to the AXI memory
//==============================================================================
logic [DataBufferDataWidth-1:0] src_buffer [0:2**DataBufferAddrWidth-1];
logic [DataBufferAddrWidth-1:0] src_buffer_addr;
logic [DataBufferDataWidth-1:0] src_buffer_data;
logic src_buffer_ce, src_buffer_we;
always @(posedge clk) begin
    if (src_buffer_ce) begin
        assert(!src_buffer_we)
        else $fatal("src_buffer is read only, we should not be 1");
        if (!src_buffer_we) begin
            src_buffer_data <= src_buffer[src_buffer_addr];
        end
    end
end

//==============================================================================
// AXI Burst Write Engine (DUT)
//==============================================================================
logic dut_start_valid, dut_start_ready;
logic dut_done_valid, dut_done_ready;
logic [DataBufferAddrWidth-1:0] dut_src_ptr;
logic [DataBufferAddrWidth-1:0] dut_data_len;
logic [AXIAddrWdith-1:0] dut_dst_ptr;
AXIBurstWriteEngine #(
    .BufferDataWidth(DataBufferDataWidth),
    .BufferAddrWidth(DataBufferAddrWidth),
    .AXIAddrWidth(AXIAddrWdith),
    .AXIDataWidth(AXIDataWidth),
    .AXIMaxBurstLen(AXIMaxBurstLen)
) dut (
    .start_valid(dut_start_valid),
    .start_ready(dut_start_ready),
    .done_valid(dut_done_valid),
    .done_ready(dut_done_ready),
    .data_ptr(dut_src_ptr),
    .data_size(dut_data_len),
    .axi_offset(dut_dst_ptr),

    .buffer_addr(src_buffer_addr),
    .buffer_data(src_buffer_data),
    .buffer_ce(src_buffer_ce),
    .buffer_we(src_buffer_we),

    .*
);

//==============================================================================
// Helper Functions & Tasks
//==============================================================================

function logic[AXIDataWidth-1:0] peek_axi_memory (logic[AXIAddrWdith-1:0] addr);
    mem_peek_addr = addr >> $clog2(AXIDataWidth/8);
    return bfm.memory[mem_peek_addr];
    //return mem_peek_data;
endfunction

// functions to update the bfm/dut configurations. They MUST only be called when reset is asserted.
function void enable_bfm_aw_stall (real stall_prob, int stall_min, int stall_max);
    assert(reset)
    else $fatal("enable_bfm_aw_stall() must be called when reset is asserted");
    aw_random_stall = 1;
    aw_stall_prob = stall_prob;
    aw_stall_min = stall_min;
    aw_stall_max = stall_max;
endfunction

function void enable_bfm_w_stall (real stall_prob, int stall_min, int stall_max);
    assert(reset)
    else $fatal("enable_bfm_w_stall() must be called when reset is asserted");
    w_random_stall = 1;
    w_stall_prob = stall_prob;
    w_stall_min = stall_min;
    w_stall_max = stall_max;
endfunction

function void enable_bfm_b_stall (real stall_prob, int stall_min, int stall_max);
    assert(reset)
    else $fatal("enable_bfm_b_stall() must be called when reset is asserted");
    b_random_stall = 1;
    b_stall_prob = stall_prob;
    b_stall_min = stall_min;
    b_stall_max = stall_max;
endfunction

function void disable_bfm_aw_stall ();
    assert(reset)
    else $fatal("disable_bfm_aw_stall() must be called when reset is asserted");
    aw_random_stall = 0;
endfunction

function void disable_bfm_w_stall ();
    assert(reset)
    else $fatal("disable_bfm_w_stall() must be called when reset is asserted");
    w_random_stall = 0;
endfunction

function void disable_bfm_b_stall ();
    assert(reset)
    else $fatal("disable_bfm_b_stall() must be called when reset is asserted");
    b_random_stall = 0;
endfunction

function void init_src_buffer ();
    assert (reset)
    else  $fatal("init_src_buffer() must be called when reset is asserted");
    for (int i = 0; i < 2**DataBufferAddrWidth; i++) begin
        src_buffer[i] = $random;
    end
endfunction

function void set_dut_args(
    logic [DataBufferAddrWidth-1:0] src_addr,
    logic [AXIAddrWdith-1:0] dst_addr,
    logic [DataBufferAddrWidth-1:0] data_len
);
    dut_src_ptr = src_addr;
    dut_dst_ptr = dst_addr;
    dut_data_len = data_len;
endfunction

// wait on a signal to go high
task automatic wait_for(ref logic signal, input int timeout, input string msg="");
    int i = 0;
    do begin
        tick(1);
        i++;
        if (i > timeout) begin
            if (msg != "") begin
                $fatal(msg);
            end else begin
                $fatal("Timeout waiting for signal to go high");
            end
        end
    end while (!signal);
endtask

//==============================================================================
// Test Cases
//==============================================================================
task automatic test_single_write (
    logic [DataBufferAddrWidth-1:0] src_addr,
    logic [AXIAddrWdith-1:0] dst_addr
);
    $display("======= Test Single Write =======");
    $display("Moving %0d words from src_addr: 0x%h to dst_addr: 0x%h", 1, src_addr, dst_addr);

    // print initial src_buffer value
    //$display("SRC Buffer: Addr 0x%h -> Data 0x%h", src_addr, src_buffer[src_addr]);
    // initialization of test case
    reset = 1;
    dut_start_valid = 0;
    dut_done_ready = 0;
    // disable BFM stalls
    disable_bfm_aw_stall();
    disable_bfm_w_stall();
    disable_bfm_b_stall();
    tick(1);

    // release reset
    reset = 0;

    // set dut input arguments
    set_dut_args(src_addr, dst_addr, 1);
    // signal start and wait for ready
    dut_start_valid = 1;
    if(!dut_start_ready)
        wait_for(dut_start_ready, 1000, "Timeout waiting for dut_start_ready");

    // wait for done
    dut_done_ready = 1;
    wait_for(dut_done_valid, 1000, "Timeout waiting for dut_done_valid");

    // check results
    assert(peek_axi_memory(dst_addr) == src_buffer[src_addr])
    else begin
        $fatal(
            "Result mismatch! Expected: 0x%h, Got: 0x%h",
            src_buffer[src_addr], peek_axi_memory(dst_addr)
        );
    end

    $display("======= Test Single Write: PASSED");
endtask

task automatic test_burst_write (
    logic [DataBufferAddrWidth-1:0] src_addr,
    logic [AXIAddrWdith-1:0] dst_addr,
    int size
);
    $display("======= Test Burst Write =======");
    $display("Moving %0d words from src_addr: 0x%h to dst_addr: 0x%h", size, src_addr, dst_addr);

    // print initial src_buffer value
    //$display("SRC Buffer: Addr 0x%h -> Data 0x%h", src_addr, src_buffer[src_addr]);
    // initialization of test case
    reset = 1;
    dut_start_valid = 0;
    dut_done_ready = 0;
    // disable BFM stalls
    disable_bfm_aw_stall();
    disable_bfm_w_stall();
    disable_bfm_b_stall();
    tick(1);

    // release reset
    reset = 0;

    // set dut input arguments
    set_dut_args(src_addr, dst_addr, size);
    // signal start and wait for ready
    dut_start_valid = 1;
    if(!dut_start_ready)
        wait_for(dut_start_ready, 1000, "Timeout waiting for dut_start_ready");

    // wait for done
    dut_done_ready = 1;
    wait_for(dut_done_valid, 1000, "Timeout waiting for dut_done_valid");

    // check results
    for (int i = 0; i < size; i++) begin
        assert(peek_axi_memory(dst_addr + i) == src_buffer[src_addr + i])
        else begin
            $fatal(
                "Result mismatch at index %0d! Expected: 0x%h, Got: 0x%h",
                i, src_buffer[src_addr + i], peek_axi_memory(dst_addr + i)
            );
        end
    end

    $display("======= Test Burst Write: PASSED");
endtask



//==============================================================================
// Test Harness
//==============================================================================

initial begin
    reset = 1;
    init_src_buffer();
    tick(1);
    reset = 0;

    test_single_write(0, 0);

    /**************************************************************************
        TODO: test_burst_write is failing due to data mismatch.
        Please fix it.
    **************************************************************************/
    test_burst_write(0, 0, 32);

    reset = 1;
    enable_bfm_aw_stall(0.5, 1, 10);
    tick(1);
    reset = 0;
    for (int i = 0; i < 20; i = i + 1) begin
        test_single_write(0, 0);
    end
    for (int i = 0; i < 20; i = i + 1) begin
        test_burst_write(0, 0, 32);
    end
    reset = 1;
    disable_bfm_aw_stall();

    /**************************************************************************
        TODO: add tests for writes with other kinds of random stalls
        use functions at lines 162 ~ 205 to enable/disable stalls
        Note: the stall functions must be called when reset is asserted
    **************************************************************************/


    $display("All tests passed!");
    $finish;
end

endmodule