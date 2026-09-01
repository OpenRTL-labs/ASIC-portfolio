
`timescale 1ns / 1ps

module dma_status_register (
    input  wire        clk,
    input  wire        rst_n,             // synchronous active-low reset

    input  wire        fsm_busy,
    input  wire        fsm_done,
    input  wire        fsm_error,
    input  wire [31:0] beats_remaining,

    output reg          status_busy,
    output reg          status_done,
    output reg          status_error,
    output reg  [15:0]  status_beats_remaining
);

    reg fsm_busy_prev;   // for rising-edge detection (new transfer started)

    always @(posedge clk) begin
        if (!rst_n) begin
            fsm_busy_prev          <= 1'b0;
            status_busy            <= 1'b0;
            status_done            <= 1'b0;
            status_error           <= 1'b0;
            status_beats_remaining <= 16'd0;
        end else begin
            fsm_busy_prev          <= fsm_busy;
            status_busy            <= fsm_busy;
            status_error           <= fsm_error;
            status_beats_remaining <= beats_remaining[15:0];

            if (fsm_busy && !fsm_busy_prev) begin
                // A new transfer has just started: clear the sticky DONE bit.
                status_done <= 1'b0;
            end else if (fsm_done) begin
                status_done <= 1'b1;
            end
        end
    end

endmodule

