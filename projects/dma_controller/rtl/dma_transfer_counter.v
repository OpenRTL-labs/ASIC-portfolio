
`timescale 1ns / 1ps

module dma_transfer_counter (
    input  wire        clk,
    input  wire        rst_n,          // synchronous active-low reset

    input  wire        load,           // xfer_start_pulse: latch transfer length
    input  wire [31:0] cfg_xfer_len,
    input  wire        decrement,      // pulse: one beat drained to destination

    output reg  [31:0] beats_remaining,
    output wire        counter_done
);

    assign counter_done = (beats_remaining == 32'd0);

    always @(posedge clk) begin
        if (!rst_n) begin
            beats_remaining <= 32'd0;
        end else if (load) begin
            beats_remaining <= cfg_xfer_len;
        end else if (decrement && (beats_remaining != 32'd0)) begin
            // Guard against underflow; in normal operation decrement is
            // never asserted once beats_remaining has already reached 0.
            beats_remaining <= beats_remaining - 32'd1;
        end
    end

endmodule

