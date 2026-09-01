
`timescale 1ns / 1ps

module dma_control_fsm (
    input  wire        clk,
    input  wire        rst_n,             // synchronous active-low reset

    // From register bank
    input  wire        start_pulse,
    input  wire        soft_reset_pulse,
    input  wire [1:0]  cfg_mode,
    input  wire [31:0] cfg_xfer_len,

    // From FIFO
    input  wire        fifo_full,
    input  wire        fifo_empty,

    // From external ports (reserved for future FSM-level stall/error
    // extensions; engines handle the per-beat ready handshake internally)
    input  wire        src_ready,
    input  wire        dst_ready,

    // From read/write engines
    input  wire        read_done,         // one beat fetched into FIFO
    input  wire        write_done,        // one beat drained to destination

    // From burst controller / transfer counter
    input  wire        burst_done,        // current burst's read quota reached
    input  wire        counter_done,      // all beats drained (transfer complete)

    // Status outputs
    output reg         fsm_busy,
    output reg         fsm_done,          // one-cycle pulse on completion
    output reg         fsm_error,

    // Engine enables
    output wire        read_req,
    output wire        write_req,

    // Address generator / transfer counter pulses
    output wire        addr_advance_src,
    output wire        addr_advance_dst,
    output wire        counter_decrement,
    output reg         xfer_start_pulse,  // loads address gen + transfer counter

    // Burst controller pulses
    output reg         burst_start,
    output wire        burst_beat_done
);

    // State encoding: compact binary, 7 states in 3 bits (1 reserved code)
    localparam [2:0] ST_IDLE        = 3'b000;
    localparam [2:0] ST_SETUP       = 3'b001;
    localparam [2:0] ST_BURST_READ  = 3'b010;
    localparam [2:0] ST_BURST_WRITE = 3'b011;
    localparam [2:0] ST_CHECK_DONE  = 3'b100;
    localparam [2:0] ST_COMPLETE    = 3'b101;
    localparam [2:0] ST_ERROR       = 3'b110;

    reg [2:0]  state;
    reg [31:0] fetch_remaining;   // beats not yet fetched by the read engine

    // Unused inputs kept in the port list to preserve the interface contract
    // for future stall/error extensions; explicitly referenced here so lint
    // tools do not flag them as dangling.
    wire unused_ok = src_ready & dst_ready;

    //--------------------------------------------------------------------
    // Combinational engine-enable outputs, gated strictly by current state
    // so read and write phases never overlap.
    //--------------------------------------------------------------------
    assign read_req          = (state == ST_BURST_READ)  && (fetch_remaining != 32'd0) && !fifo_full;
    assign write_req         = (state == ST_BURST_WRITE) && !fifo_empty;
    assign addr_advance_src  = read_done;
    assign addr_advance_dst  = write_done;
    assign counter_decrement = write_done;
    assign burst_beat_done   = read_done;

    //--------------------------------------------------------------------
    // Main sequential state machine
    //--------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            fetch_remaining  <= 32'd0;
            fsm_busy         <= 1'b0;
            fsm_done         <= 1'b0;
            fsm_error        <= 1'b0;
            xfer_start_pulse <= 1'b0;
            burst_start      <= 1'b0;
        end else if (soft_reset_pulse) begin
            // Soft reset returns the FSM to IDLE without a full chip reset.
            state            <= ST_IDLE;
            fetch_remaining  <= 32'd0;
            fsm_busy         <= 1'b0;
            fsm_done         <= 1'b0;
            fsm_error        <= 1'b0;
            xfer_start_pulse <= 1'b0;
            burst_start      <= 1'b0;
        end else begin
            // Single-cycle pulses default low unless asserted below.
            xfer_start_pulse <= 1'b0;
            burst_start      <= 1'b0;
            fsm_done         <= 1'b0;

            case (state)
                //--------------------------------------------------------
                ST_IDLE: begin
                    fsm_busy <= 1'b0;
                    if (start_pulse) begin
                        if (cfg_mode == 2'b11) begin
                            // Reserved mode value: flag error, do not start.
                            state     <= ST_ERROR;
                            fsm_error <= 1'b1;
                        end else begin
                            fetch_remaining  <= cfg_xfer_len;
                            xfer_start_pulse <= 1'b1;
                            fsm_busy         <= 1'b1;
                            state            <= ST_SETUP;
                        end
                    end
                end

                //--------------------------------------------------------
                ST_SETUP: begin
                    if (cfg_xfer_len == 32'd0) begin
                        // Zero-length transfer: nothing to move, complete
                        // immediately.
                        state <= ST_COMPLETE;
                    end else begin
                        burst_start <= 1'b1;
                        state       <= ST_BURST_READ;
                    end
                end

                //--------------------------------------------------------
                ST_BURST_READ: begin
                    if (read_done) begin
                        fetch_remaining <= fetch_remaining - 32'd1;
                    end
                    // Move to the write phase once this burst's read quota
                    // is satisfied, or once no beats remain to fetch at all
                    // (final, possibly short, burst of the transfer).
                    if (burst_done || (fetch_remaining == 32'd0)) begin
                        state <= ST_BURST_WRITE;
                    end
                end

                //--------------------------------------------------------
                ST_BURST_WRITE: begin
                    if (fifo_empty) begin
                        state <= ST_CHECK_DONE;
                    end
                end

                //--------------------------------------------------------
                ST_CHECK_DONE: begin
                    if (counter_done) begin
                        state <= ST_COMPLETE;
                    end else begin
                        burst_start <= 1'b1;
                        state       <= ST_BURST_READ;
                    end
                end

                //--------------------------------------------------------
                ST_COMPLETE: begin
                    fsm_done <= 1'b1;
                    fsm_busy <= 1'b0;
                    state    <= ST_IDLE;
                end

                //--------------------------------------------------------
                ST_ERROR: begin
                    // Held here until soft_reset_pulse or a chip reset clears it.
                    fsm_busy <= 1'b0;
                end

                //--------------------------------------------------------
                default: begin
                    // Unreachable code point (3'b111) - recover to IDLE
                    // rather than leaving state undefined.
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule

