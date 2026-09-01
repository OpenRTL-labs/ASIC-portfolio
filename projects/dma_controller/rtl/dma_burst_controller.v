
`timescale 1ns / 1ps

module dma_burst_controller (
    input  wire       clk,
    input  wire       rst_n,          // synchronous active-low reset

    input  wire       burst_start,    // pulse: begin counting a new burst
    input  wire [7:0] cfg_burst_len,
    input  wire       beat_done,      // pulse: one beat completed
    input  wire       counter_done,   // overall transfer already fully drained

    output reg        burst_done,     // pulse: this burst's quota reached
    output reg        burst_active
);

    reg [7:0] beat_count;

    always @(posedge clk) begin
        if (!rst_n) begin
            beat_count   <= 8'd0;
            burst_active <= 1'b0;
            burst_done   <= 1'b0;
        end else begin
            burst_done <= 1'b0;   // default: pulse deasserts

            if (burst_start) begin
                beat_count   <= 8'd0;
                burst_active <= 1'b1;
            end else if (counter_done) begin
                // Overall transfer already complete; nothing further to count.
                burst_active <= 1'b0;
            end else if (burst_active && beat_done) begin
                if ((beat_count + 8'd1) >= cfg_burst_len) begin
                    burst_done   <= 1'b1;
                    burst_active <= 1'b0;
                    beat_count   <= 8'd0;
                end else begin
                    beat_count <= beat_count + 8'd1;
                end
            end
        end
    end

endmodule

