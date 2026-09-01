
`timescale 1ns / 1ps

module dma_read_engine (
    input  wire        clk,
    input  wire        rst_n,          // synchronous active-low reset

    // From control FSM
    input  wire        read_req,       // level: engine may fetch the next beat

    // From address generator
    input  wire [31:0] src_addr_cur,

    // Source-side external port
    output reg  [31:0] src_addr,
    input  wire [31:0] src_rdata,
    output reg          src_ren,
    input  wire         src_ready,

    // To FIFO
    input  wire         fifo_full,
    output reg           fifo_wr_en,
    output reg  [31:0]   fifo_wdata,

    // To control FSM / address generator / transfer counter
    output reg           read_done       // one-cycle pulse: one beat fetched
);

    localparam [1:0] S_IDLE = 2'b00;   // waiting for read_req
    localparam [1:0] S_REQ  = 2'b01;   // ren/addr asserted, waiting for ready
    localparam [1:0] S_GAP  = 2'b10;   // one bubble cycle after completion

    reg [1:0] state;

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            src_ren    <= 1'b0;
            src_addr   <= 32'd0;
            fifo_wr_en <= 1'b0;
            fifo_wdata <= 32'd0;
            read_done  <= 1'b0;
        end else begin
            // Pulses default low every cycle.
            fifo_wr_en <= 1'b0;
            read_done  <= 1'b0;

            case (state)
                //----------------------------------------------------
                S_IDLE: begin
                    src_ren <= 1'b0;
                    if (read_req && !fifo_full) begin
                        src_ren  <= 1'b1;
                        src_addr <= src_addr_cur;
                        state    <= S_REQ;
                    end
                end

                //----------------------------------------------------
                S_REQ: begin
                    // src_ren/src_addr already hold their values from the
                    // previous cycle; keep asserting until the source
                    // responds with ready (it may take multiple cycles).
                    if (src_ready) begin
                        fifo_wdata <= src_rdata;
                        fifo_wr_en <= 1'b1;
                        read_done  <= 1'b1;
                        src_ren    <= 1'b0;
                        state      <= S_GAP;
                    end
                end

                //----------------------------------------------------
                S_GAP: begin
                    // Bubble cycle: lets addr_advance_src / counter_decrement
                    // (driven from read_done, one cycle behind) settle in
                    // the address generator / transfer counter before the
                    // next request samples src_addr_cur again.
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

