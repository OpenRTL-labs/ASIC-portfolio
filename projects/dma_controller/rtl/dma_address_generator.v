
`timescale 1ns / 1ps

module dma_address_generator (
    input  wire        clk,
    input  wire        rst_n,             // synchronous active-low reset

    input  wire        load,              // xfer_start_pulse: latch start addresses
    input  wire [31:0] cfg_src_addr,
    input  wire [31:0] cfg_dst_addr,
    input  wire        cfg_src_addr_hold, // 1 = hold source address constant
    input  wire        cfg_dst_addr_hold, // 1 = hold destination address constant

    input  wire        advance_src,       // pulse: one source beat completed
    input  wire        advance_dst,       // pulse: one destination beat completed

    output reg  [31:0] src_addr_cur,
    output reg  [31:0] dst_addr_cur
);

    // Address step per beat: 4 bytes (one 32-bit word).
    localparam [31:0] ADDR_STEP = 32'd4;

    //--------------------------------------------------------------------
    // Source address sequencing
    //--------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            src_addr_cur <= 32'd0;
        end else if (load) begin
            src_addr_cur <= cfg_src_addr;
        end else if (advance_src && !cfg_src_addr_hold) begin
            src_addr_cur <= src_addr_cur + ADDR_STEP;
        end
        // else: hold mode or no advance this cycle - retain current value.
    end

    //--------------------------------------------------------------------
    // Destination address sequencing
    //--------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            dst_addr_cur <= 32'd0;
        end else if (load) begin
            dst_addr_cur <= cfg_dst_addr;
        end else if (advance_dst && !cfg_dst_addr_hold) begin
            dst_addr_cur <= dst_addr_cur + ADDR_STEP;
        end
        // else: hold mode or no advance this cycle - retain current value.
    end

endmodule

