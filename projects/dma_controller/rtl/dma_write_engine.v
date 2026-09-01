
`timescale 1ns / 1ps

module dma_write_engine (
    input  wire        clk,
    input  wire        rst_n,          // synchronous active-low reset

    // From control FSM
    input  wire        write_req,      // level: engine may drain the next beat

    // From address generator
    input  wire [31:0] dst_addr_cur,

    // Destination-side external port
    output reg  [31:0] dst_addr,
    output reg  [31:0] dst_wdata,
    output reg          dst_wen,
    input  wire         dst_ready,

    // From FIFO (first-word-fall-through read interface)
    input  wire         fifo_empty,
    input  wire [31:0]  fifo_rdata,
    output reg           fifo_rd_en,

    // To control FSM / address generator / transfer counter
    output reg           write_done      // one-cycle pulse: one beat drained
);

    localparam [1:0] S_IDLE = 2'b00;   // waiting for write_req
    localparam [1:0] S_REQ  = 2'b01;   // wen/addr/wdata asserted, waiting for ready
    localparam [1:0] S_GAP  = 2'b10;   // one bubble cycle after completion

    reg [1:0] state;

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            dst_addr   <= 32'd0;
            dst_wdata  <= 32'd0;
            dst_wen    <= 1'b0;
            fifo_rd_en <= 1'b0;
            write_done <= 1'b0;
        end else begin
	    fifo_rd_en <= 1'b0;
            write_done <= 1'b0;

            case (state)
                //----------------------------------------------------
                S_IDLE: begin
                    dst_wen <= 1'b0;
                    if (write_req && !fifo_empty) begin
                        dst_addr  <= dst_addr_cur;
                        dst_wdata <= fifo_rdata;   // capture current FIFO head
                        dst_wen   <= 1'b1;
                        state     <= S_REQ;
                    end
                end

                //----------------------------------------------------
                S_REQ: begin
                    if (dst_ready) begin
                        fifo_rd_en <= 1'b1;   // pop the entry already latched
                        write_done <= 1'b1;
                        dst_wen    <= 1'b0;
                        state      <= S_GAP;
                    end
                end

                //----------------------------------------------------
                S_GAP: begin
                    state <= S_IDLE;
                end

                //----------------------------------------------------
                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

