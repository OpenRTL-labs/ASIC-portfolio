
`timescale 1ns / 1ps

module dma_read_responder #(
    parameter WORDS       = 1024,
    parameter RANDOM_WAIT = 0,
    parameter MAX_WAIT    = 3
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] addr,
    input  wire        ren,
    output reg  [31:0] rdata,
    output reg         ready
);

    reg [31:0] mem [0:WORDS-1];
    reg [7:0]  wait_left;
    reg        pending;

    always @(posedge clk) begin
        if (!rst_n) begin
            wait_left <= 8'd0;
            pending   <= 1'b0;
            ready     <= 1'b0;
        end else begin
            ready <= 1'b0;
            if (ren && !pending) begin
                if (RANDOM_WAIT) begin
                    wait_left <= ({$random} % MAX_WAIT);
                    pending   <= 1'b1;
                end else begin
                    ready <= 1'b1;
                    rdata <= mem[addr[31:2] % WORDS];
                end
            end else if (pending) begin
                if (wait_left == 8'd0) begin
                    ready   <= 1'b1;
                    rdata   <= mem[addr[31:2] % WORDS];
                    pending <= 1'b0;
                end else begin
                    wait_left <= wait_left - 8'd1;
                end
            end
        end
    end

endmodule


module dma_write_responder #(
    parameter WORDS       = 1024,
    parameter RANDOM_WAIT = 0,
    parameter MAX_WAIT    = 3
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    input  wire        wen,
    output reg         ready
);

    reg [31:0] mem [0:WORDS-1];
    reg [7:0]  wait_left;
    reg        pending;

    always @(posedge clk) begin
        if (!rst_n) begin
            wait_left <= 8'd0;
            pending   <= 1'b0;
            ready     <= 1'b0;
        end else begin
            ready <= 1'b0;
            if (wen && !pending) begin
                if (RANDOM_WAIT) begin
                    wait_left <= ({$random} % MAX_WAIT);
                    pending   <= 1'b1;
                end else begin
                    ready                    <= 1'b1;
                    mem[addr[31:2] % WORDS]  <= wdata;
                end
            end else if (pending) begin
                if (wait_left == 8'd0) begin
                    ready                    <= 1'b1;
                    mem[addr[31:2] % WORDS]  <= wdata;
                    pending                  <= 1'b0;
                end else begin
                    wait_left <= wait_left - 8'd1;
                end
            end
        end
    end

endmodule

