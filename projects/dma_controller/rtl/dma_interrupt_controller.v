
`timescale 1ns / 1ps

module dma_interrupt_controller (
    input  wire clk,
    input  wire rst_n,          // synchronous active-low reset

    input  wire fsm_done,       // one-cycle pulse from control FSM
    input  wire cfg_irq_en,
    input  wire irq_clear_pulse,

    output reg  irq
);

    always @(posedge clk) begin
        if (!rst_n) begin
            irq <= 1'b0;
        end else if (irq_clear_pulse) begin
            // Explicit clear takes priority over a same-cycle set, though in
            // normal operation the two are never asserted simultaneously.
            irq <= 1'b0;
        end else if (fsm_done && cfg_irq_en) begin
            irq <= 1'b1;
        end
    end

endmodule

