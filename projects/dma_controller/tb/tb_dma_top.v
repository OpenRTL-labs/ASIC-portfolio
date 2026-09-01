
`timescale 1ns / 1ps

module dma_tb;

    //--------------------------------------------------------------------
    // Register offsets (must match dma_register_bank.v)
    //--------------------------------------------------------------------
    localparam [7:0] ADDR_SRC_ADDR  = 8'h00;
    localparam [7:0] ADDR_DST_ADDR  = 8'h04;
    localparam [7:0] ADDR_XFER_LEN  = 8'h08;
    localparam [7:0] ADDR_CTRL      = 8'h0C;
    localparam [7:0] ADDR_STATUS    = 8'h10;
    localparam [7:0] ADDR_BURST_CFG = 8'h14;
    localparam [7:0] ADDR_IRQ_CLEAR = 8'h18;

    // CTRL.MODE encodings
    localparam [1:0] MODE_MEM2MEM  = 2'b00;
    localparam [1:0] MODE_PER2MEM  = 2'b01;
    localparam [1:0] MODE_MEM2PER  = 2'b10;

    localparam MEM_WORDS = 512;   // model memory size, in 32-bit words

    
    reg clk;
    reg rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    //--------------------------------------------------------------------
    // DUT connections
    //--------------------------------------------------------------------
    reg  [7:0]  cpu_addr;
    reg  [31:0] cpu_wdata;
    wire [31:0] cpu_rdata;
    reg         cpu_wr;
    reg         cpu_rd;
    wire        cpu_ready;

    wire [31:0] src_addr;
    wire [31:0] src_rdata;
    wire        src_ren;
    wire        src_ready;

    wire [31:0] dst_addr;
    wire [31:0] dst_wdata;
    wire        dst_wen;
    wire        dst_ready;

    wire        irq;

    
    reg use_periph_src;
    reg use_periph_dst;

    dma_top #(
        .FIFO_DEPTH (16),
        .DATA_WIDTH (32)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .cpu_addr   (cpu_addr),
        .cpu_wdata  (cpu_wdata),
        .cpu_rdata  (cpu_rdata),
        .cpu_wr     (cpu_wr),
        .cpu_rd     (cpu_rd),
        .cpu_ready  (cpu_ready),
        .src_addr   (src_addr),
        .src_rdata  (src_rdata),
        .src_ren    (src_ren),
        .src_ready  (src_ready),
        .dst_addr   (dst_addr),
        .dst_wdata  (dst_wdata),
        .dst_wen    (dst_wen),
        .dst_ready  (dst_ready),
        .irq        (irq)
    );

    //--------------------------------------------------------------------
    // Memory models (zero-wait-state "memory" behavior)
    //--------------------------------------------------------------------
    wire [31:0] mem_src_rdata;
    wire        mem_src_ready;
    wire        mem_dst_ready;

    dma_read_responder #(
        .WORDS       (MEM_WORDS),
        .RANDOM_WAIT (0)
    ) u_mem_src (
        .clk    (clk),
        .rst_n  (rst_n),
        .addr   (src_addr),
        .ren    (src_ren),
        .rdata  (mem_src_rdata),
        .ready  (mem_src_ready)
    );

    dma_write_responder #(
        .WORDS       (MEM_WORDS),
        .RANDOM_WAIT (0)
    ) u_mem_dst (
        .clk    (clk),
        .rst_n  (rst_n),
        .addr   (dst_addr),
        .wdata  (dst_wdata),
        .wen    (dst_wen),
        .ready  (mem_dst_ready)
    );

    //--------------------------------------------------------------------
    // Peripheral models (streaming, address-held, random wait-states)
    //--------------------------------------------------------------------
    wire [31:0] periph_src_rdata;
    wire        periph_src_ready;
    wire        periph_dst_ready;

    dma_periph_src_model #(
        .RANDOM_WAIT (1),
        .MAX_WAIT    (3),
        .SEED        (32'hA000_0000)
    ) u_periph_src (
        .clk    (clk),
        .rst_n  (rst_n),
        .sel    (use_periph_src),
        .ren    (src_ren),
        .rdata  (periph_src_rdata),
        .ready  (periph_src_ready)
    );

    dma_periph_dst_model #(
        .RANDOM_WAIT (1),
        .MAX_WAIT    (3)
    ) u_periph_dst (
        .clk    (clk),
        .rst_n  (rst_n),
        .sel    (use_periph_dst),
        .wdata  (dst_wdata),
        .wen    (dst_wen),
        .ready  (periph_dst_ready)
    );

    //--------------------------------------------------------------------
    // Source/destination responder mux - selects which model drives the
    // DUT's external ports for the currently running test.
    //--------------------------------------------------------------------
    assign src_rdata = use_periph_src ? periph_src_rdata : mem_src_rdata;
    assign src_ready = use_periph_src ? periph_src_ready : mem_src_ready;
    assign dst_ready = use_periph_dst ? periph_dst_ready : mem_dst_ready;

    //--------------------------------------------------------------------
    // Scoreboard bookkeeping
    //--------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    integer i;

    //--------------------------------------------------------------------
    // CPU-side tasks
    //--------------------------------------------------------------------
    task cpu_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk);
            cpu_addr  <= addr;
            cpu_wdata <= data;
            cpu_wr    <= 1'b1;
            cpu_rd    <= 1'b0;
            @(posedge clk);
            cpu_wr    <= 1'b0;
        end
    endtask

    task cpu_read;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk);
            cpu_addr <= addr;
            cpu_rd   <= 1'b1;
            @(posedge clk);
            cpu_rd   <= 1'b0;
            @(posedge clk);   // allow the registered read data to settle
            data = cpu_rdata;
        end
    endtask

    // Programs all transfer registers and issues START in one call.
    task start_transfer;
        input [31:0] p_src_addr;
        input [31:0] p_dst_addr;
        input [31:0] p_xfer_len;
        input [1:0]  p_mode;
        input        p_src_hold;
        input        p_dst_hold;
        input [7:0]  p_burst_len;
        reg   [31:0] ctrl_word;
        begin
            // NOTE: SRC_ADDR/DST_ADDR registers are BYTE addresses (the
            // address generator steps by ADDR_STEP=4 bytes/beat, and the
            // memory models index with addr[31:2]). This task's p_src_addr/
            // p_dst_addr arguments - and every check_* task's src_base/
            // dst_base - are WORD indices into the behavioral mem[] arrays,
            // matching how every test in this file calls them. Convert
            // word index -> byte address here, at the single translation
            // point, so the rest of the testbench's word-indexed bookkeeping
            // stays correct.
            cpu_write(ADDR_SRC_ADDR,  p_src_addr << 2);
            cpu_write(ADDR_DST_ADDR,  p_dst_addr << 2);
            cpu_write(ADDR_XFER_LEN,  p_xfer_len);
            cpu_write(ADDR_BURST_CFG, {24'd0, p_burst_len});
            ctrl_word = 32'd0;
            ctrl_word[0]   = 1'b1;          // START
            ctrl_word[3:2] = p_mode;
            ctrl_word[4]   = p_src_hold;
            ctrl_word[5]   = p_dst_hold;
            ctrl_word[6]   = 1'b1;          // IRQ_EN
            cpu_write(ADDR_CTRL, ctrl_word);
        end
    endtask

    // Waits for the interrupt (with timeout), then clears it.
    task wait_for_irq;
        integer timeout;
        begin
            timeout = 0;
            while ((irq !== 1'b1) && (timeout < 200000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 200000) begin
                $display("[%0t] ERROR: timeout waiting for irq", $time);
                fail_count = fail_count + 1;
            end
            cpu_write(ADDR_IRQ_CLEAR, 32'h1);
            @(posedge clk);
        end
    endtask

    //--------------------------------------------------------------------
    // Checking tasks
    //--------------------------------------------------------------------

    // Memory-to-memory: compares WORDS entries starting at src_base/dst_base
    // (word indices) in the two zero-wait-state memory models.
    task check_mem_to_mem;
        input [31:0] src_base;
        input [31:0] dst_base;
        input [31:0] words;
        reg   [31:0] expected;
        reg   [31:0] actual;
        integer      k;
        integer      local_errors;
        begin
            local_errors = 0;
            for (k = 0; k < words; k = k + 1) begin
                expected = u_mem_src.mem[(src_base + k) % MEM_WORDS];
                actual   = u_mem_dst.mem[(dst_base + k) % MEM_WORDS];
                if (actual !== expected) begin
                    $display("[%0t] MISMATCH beat %0d: expected %h got %h",
                              $time, k, expected, actual);
                    local_errors = local_errors + 1;
                end
            end
            if (local_errors == 0) begin
                $display("[%0t] PASS: mem-to-mem check, %0d beats", $time, words);
                pass_count = pass_count + 1;
            end else begin
                $display("[%0t] FAIL: mem-to-mem check, %0d mismatches", $time, local_errors);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Peripheral-to-memory: destination words should equal SEED + beat_index.
    task check_periph_to_mem;
        input [31:0] dst_base;
        input [31:0] words;
        input [31:0] seed;
        reg   [31:0] expected;
        reg   [31:0] actual;
        integer      k;
        integer      local_errors;
        begin
            local_errors = 0;
            for (k = 0; k < words; k = k + 1) begin
                expected = seed + k;
                actual   = u_mem_dst.mem[(dst_base + k) % MEM_WORDS];
                if (actual !== expected) begin
                    $display("[%0t] MISMATCH beat %0d: expected %h got %h",
                              $time, k, expected, actual);
                    local_errors = local_errors + 1;
                end
            end
            if (local_errors == 0) begin
                $display("[%0t] PASS: periph-to-mem check, %0d beats", $time, words);
                pass_count = pass_count + 1;
            end else begin
                $display("[%0t] FAIL: periph-to-mem check, %0d mismatches", $time, local_errors);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Memory-to-peripheral: captured peripheral words should equal the
    // source memory words that were sent.
    task check_mem_to_periph;
        input [31:0] src_base;
        input [31:0] words;
        reg   [31:0] expected;
        reg   [31:0] actual;
        integer      k;
        integer      local_errors;
        begin
            local_errors = 0;
            for (k = 0; k < words; k = k + 1) begin
                expected = u_mem_src.mem[(src_base + k) % MEM_WORDS];
                actual   = u_periph_dst.captured[k];
                if (actual !== expected) begin
                    $display("[%0t] MISMATCH beat %0d: expected %h got %h",
                              $time, k, expected, actual);
                    local_errors = local_errors + 1;
                end
            end
            if (local_errors == 0) begin
                $display("[%0t] PASS: mem-to-periph check, %0d beats", $time, words);
                pass_count = pass_count + 1;
            end else begin
                $display("[%0t] FAIL: mem-to-periph check, %0d mismatches", $time, local_errors);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_true;
        input        condition;
        input [255:0] msg;   // ASCII message, sized generously
        begin
            if (condition) begin
                $display("[%0t] PASS: %0s", $time, msg);
                pass_count = pass_count + 1;
            end else begin
                $display("[%0t] FAIL: %0s", $time, msg);
                fail_count = fail_count + 1;
            end
        end
    endtask

    //--------------------------------------------------------------------
    // Memory initialization (deterministic pattern, source model only)
    //--------------------------------------------------------------------
    task init_src_mem_pattern;
        integer k;
        begin
            for (k = 0; k < MEM_WORDS; k = k + 1) begin
                u_mem_src.mem[k] = 32'hCAFE_0000 + k;
            end
        end
    endtask

    //--------------------------------------------------------------------
    // Main test sequence
    //--------------------------------------------------------------------
    reg [31:0] status_val;
    reg [31:0] rand_src, rand_dst, rand_len;
    reg [1:0]  rand_mode;
    reg [7:0]  rand_burst;

    initial begin
        $dumpfile("dma_tb.vcd");
        $dumpvars(0, dma_tb);

        pass_count      = 0;
        fail_count      = 0;
        cpu_addr        = 8'd0;
        cpu_wdata       = 32'd0;
        cpu_wr          = 1'b0;
        cpu_rd          = 1'b0;
        use_periph_src  = 1'b0;
        use_periph_dst  = 1'b0;
        rst_n           = 1'b0;

        init_src_mem_pattern;

        // Hold reset for several cycles.
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        //================================================================
        // Test 1: directed memory-to-memory transfer
        //================================================================
        $display("---- Test 1: directed memory-to-memory transfer ----");
        start_transfer(32'd0, 32'd100, 32'd8, MODE_MEM2MEM, 1'b0, 1'b0, 8'd4);
        wait_for_irq;
        check_mem_to_mem(32'd0, 32'd100, 32'd8);

        //================================================================
        // Test 2: zero-length transfer
        //================================================================
        $display("---- Test 2: zero-length transfer ----");
        start_transfer(32'd0, 32'd200, 32'd0, MODE_MEM2MEM, 1'b0, 1'b0, 8'd4);
        wait_for_irq;
        cpu_read(ADDR_STATUS, status_val);
        check_true((status_val[0] == 1'b0), "zero-length transfer left BUSY=0");

        //================================================================
        // Test 3: maximum-length transfer (bounded by model memory size)
        //================================================================
        $display("---- Test 3: maximum-length transfer ----");
        start_transfer(32'd0, 32'd0, MEM_WORDS, MODE_MEM2MEM, 1'b0, 1'b0, 8'd16);
        // Note: src_base == dst_base intentionally avoided in general, but
        // here both memories are separate model instances so overlapping
        // word indices in address space do not collide in storage.
        wait_for_irq;
        check_mem_to_mem(32'd0, 32'd0, MEM_WORDS);

        //================================================================
        // Test 4: burst-boundary transfer (length not a multiple of burst_len)
        //================================================================
        $display("---- Test 4: burst-boundary (non-multiple length) transfer ----");
        start_transfer(32'd10, 32'd300, 32'd13, MODE_MEM2MEM, 1'b0, 1'b0, 8'd4);
        wait_for_irq;
        check_mem_to_mem(32'd10, 32'd300, 32'd13);

        //================================================================
        // Test 5: back-to-back transfers, no idle gap
        //================================================================
        $display("---- Test 5: back-to-back transfers ----");
        start_transfer(32'd0,  32'd50, 32'd6, MODE_MEM2MEM, 1'b0, 1'b0, 8'd4);
        wait_for_irq;
        check_mem_to_mem(32'd0, 32'd50, 32'd6);
        start_transfer(32'd6,  32'd60, 32'd6, MODE_MEM2MEM, 1'b0, 1'b0, 8'd4);
        wait_for_irq;
        check_mem_to_mem(32'd6, 32'd60, 32'd6);

        //================================================================
        // Test 6: simultaneous requests - second START while busy is ignored
        //================================================================
        $display("---- Test 6: simultaneous START while busy ----");
        start_transfer(32'd0, 32'd400, 32'd32, MODE_MEM2MEM, 1'b0, 1'b0, 8'd8);
        // Immediately try to start a second, different transfer while busy.
        cpu_write(ADDR_SRC_ADDR, 32'd1);
        cpu_write(ADDR_CTRL, 32'h0000_0041); // START=1, IRQ_EN=1, MODE=00
        wait_for_irq;
        // The first transfer's parameters must be the ones that completed.
        check_mem_to_mem(32'd0, 32'd400, 32'd32);

        //================================================================
        // Test 7: Peripheral-to-Memory transfer (source address held)
        //================================================================
        $display("---- Test 7: peripheral-to-memory transfer ----");
        use_periph_src = 1'b1;
        start_transfer(32'd0, 32'd500, 32'd10, MODE_PER2MEM, 1'b1, 1'b0, 8'd4);
        wait_for_irq;
        check_periph_to_mem(32'd500, 32'd10, 32'hA000_0000);
        use_periph_src = 1'b0;

        //================================================================
        // Test 8: Memory-to-Peripheral transfer (destination address held)
        //================================================================
        $display("---- Test 8: memory-to-peripheral transfer ----");
        use_periph_dst = 1'b1;
        start_transfer(32'd20, 32'd0, 32'd10, MODE_MEM2PER, 1'b0, 1'b1, 8'd4);
        wait_for_irq;
        check_mem_to_periph(32'd20, 32'd10);
        use_periph_dst = 1'b0;

        //================================================================
        // Test 9: randomized transactions
        //================================================================
        $display("---- Test 9: randomized transactions ----");
        for (i = 0; i < 15; i = i + 1) begin
            rand_src   = ({$random} % 64);
            rand_dst   = 128 + ({$random} % 64);
            rand_len   = ({$random} % 20);          // 0..19 beats
            rand_burst = 1 + ({$random} % 8);        // 1..8
            start_transfer(rand_src, rand_dst, rand_len, MODE_MEM2MEM,
                            1'b0, 1'b0, rand_burst);
            wait_for_irq;
            if (rand_len == 0) begin
                cpu_read(ADDR_STATUS, status_val);
                check_true((status_val[0] == 1'b0), "random zero-length transfer completed");
            end else begin
                check_mem_to_mem(rand_src, rand_dst, rand_len);
            end
        end

        //================================================================
        // Summary
        //================================================================
        $display("========================================================");
        $display(" TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0) begin
            $display(" RESULT: ALL TESTS PASSED");
        end else begin
            $display(" RESULT: ONE OR MORE TESTS FAILED");
        end
        $display("========================================================");

        repeat (10) @(posedge clk);
        $finish;
    end

    //--------------------------------------------------------------------
    // Simulation watchdog: abort if nothing completes within a generous
    // absolute time bound (protects against a hang leaving the sim running
    // indefinitely in a regression environment).
    //--------------------------------------------------------------------
    initial begin
        #2_000_000;
        $display("[%0t] ERROR: global simulation watchdog timeout", $time);
        $finish;
    end

endmodule

