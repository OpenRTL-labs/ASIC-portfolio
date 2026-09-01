
`timescale 1ns / 1ps

module dma_fifo_buffer #(
    parameter DEPTH = 16,
    parameter WIDTH = 32
) (
    input  wire             clk,
    input  wire             rst_n,     // synchronous active-low reset

    input  wire              wr_en,
    input  wire [WIDTH-1:0]  wr_data,

    input  wire              rd_en,
    output wire [WIDTH-1:0]  rd_data,

    output wire              full,
    output wire              empty
);

    //--------------------------------------------------------------------
    // Verilog-2001-legal ceiling-log2 function (no $clog2 dependency)
    //--------------------------------------------------------------------
    function integer clogb2;
        input integer value;
        integer temp;
        begin
            temp = value;
            clogb2 = 0;
            while (temp > 0) begin
                clogb2 = clogb2 + 1;
                temp   = temp >> 1;
            end
        end
    endfunction

    localparam ADDR_WIDTH = clogb2(DEPTH - 1);

    reg [WIDTH-1:0]      mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0]   count;   // one extra bit: range 0..DEPTH inclusive

    assign full    = (count == DEPTH);
    assign empty   = (count == {(ADDR_WIDTH+1){1'b0}});
    assign rd_data = mem[rd_ptr];   // FWFT: combinational head-of-queue

    wire do_write = wr_en && !full;
    wire do_read  = rd_en && !empty;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
            rd_ptr <= {ADDR_WIDTH{1'b0}};
            count  <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            case ({do_write, do_read})
                2'b10: begin
                    // Write only
                    mem[wr_ptr] <= wr_data;
                    wr_ptr      <= wr_ptr + 1'b1;
                    count       <= count + 1'b1;
                end
                2'b01: begin
                    // Read only
                    rd_ptr <= rd_ptr + 1'b1;
                    count  <= count - 1'b1;
                end
                2'b11: begin
                    // Simultaneous write and read: count unchanged
                    mem[wr_ptr] <= wr_data;
                    wr_ptr      <= wr_ptr + 1'b1;
                    rd_ptr      <= rd_ptr + 1'b1;
                end
                default: begin
                    // No operation
                end
            endcase
        end
    end

endmodule

