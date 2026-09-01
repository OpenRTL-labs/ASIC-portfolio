
`timescale 1ns / 1ps

module dma_register_bank (
    input  wire        clk,
    input  wire        rst_n,                  // synchronous active-low reset

    // CPU interface
    input  wire [7:0]  cpu_addr,
    input  wire [31:0] cpu_wdata,
    output reg  [31:0] cpu_rdata,
    input  wire        cpu_wr,
    input  wire        cpu_rd,
    output wire        cpu_ready,

    // Status inputs from dma_status_register
    input  wire        status_busy,
    input  wire        status_done,
    input  wire        status_error,
    input  wire [15:0] status_beats_remaining,

    // Configuration outputs to the rest of the DMA
    output reg  [31:0] cfg_src_addr,
    output reg  [31:0] cfg_dst_addr,
    output reg  [31:0] cfg_xfer_len,
    output reg  [1:0]  cfg_mode,
    output reg         cfg_src_addr_hold,
    output reg         cfg_dst_addr_hold,
    output reg         cfg_irq_en,
    output reg  [7:0]  cfg_burst_len,

    // Self-clearing control pulses
    output reg         start_pulse,
    output reg         soft_reset_pulse,
    output reg         irq_clear_pulse
);

    // Register offsets
    localparam [7:0] ADDR_SRC_ADDR  = 8'h00;
    localparam [7:0] ADDR_DST_ADDR  = 8'h04;
    localparam [7:0] ADDR_XFER_LEN  = 8'h08;
    localparam [7:0] ADDR_CTRL      = 8'h0C;
    localparam [7:0] ADDR_STATUS    = 8'h10;
    localparam [7:0] ADDR_BURST_CFG = 8'h14;
    localparam [7:0] ADDR_IRQ_CLEAR = 8'h18;

    // No wait states in this simplified interface.
    assign cpu_ready = 1'b1;

    //--------------------------------------------------------------------
    // Write path + pulse generation
    //--------------------------------------------------------------------
    always @(posedge clk) begin
	    start_pulse      <= 1'b0;
            soft_reset_pulse <= 1'b0;
            irq_clear_pulse  <= 1'b0;
        if (!rst_n) begin
            cfg_src_addr      <= 32'd0;
            cfg_dst_addr      <= 32'd0;
            cfg_xfer_len      <= 32'd0;
            cfg_mode          <= 2'd0;
            cfg_src_addr_hold <= 1'b0;
            cfg_dst_addr_hold <= 1'b0;
            cfg_irq_en        <= 1'b0;
            cfg_burst_len     <= 8'd1;
           /* start_pulse       <= 1'b0;
            soft_reset_pulse  <= 1'b0;
            irq_clear_pulse   <= 1'b0;*/
        end else begin
            // Pulses default low every cycle; a matching write re-asserts
            // them for exactly one cycle.
           

            if (cpu_wr) begin
                case (cpu_addr)
                    ADDR_SRC_ADDR: cfg_src_addr <= cpu_wdata;
                    ADDR_DST_ADDR: cfg_dst_addr <= cpu_wdata;
                    ADDR_XFER_LEN: cfg_xfer_len <= cpu_wdata;

                    ADDR_CTRL: begin
                        cfg_mode          <= cpu_wdata[3:2];
                        cfg_src_addr_hold <= cpu_wdata[4];
                        cfg_dst_addr_hold <= cpu_wdata[5];
                        cfg_irq_en        <= cpu_wdata[6];
                        // START is ignored while a transfer is already busy.
                        if (cpu_wdata[0] && !status_busy) begin
                            start_pulse <= 1'b1;
                        end
                        if (cpu_wdata[1]) begin
                            soft_reset_pulse <= 1'b1;
                        end
                    end

                    ADDR_BURST_CFG: cfg_burst_len <= cpu_wdata[7:0];

                    ADDR_IRQ_CLEAR: begin
                        if (cpu_wdata[0]) begin
                            irq_clear_pulse <= 1'b1;
                        end
                    end

                    default: begin
                        // Unmapped address: write has no effect.
                    end
                endcase
            end
        end
    end

    //--------------------------------------------------------------------
    // Read path - registered, one cycle of latency (cpu_rdata valid the
    // cycle after cpu_rd)
    //--------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            cpu_rdata <= 32'd0;
        end else if (cpu_rd) begin
            case (cpu_addr)
                ADDR_SRC_ADDR:  cpu_rdata <= cfg_src_addr;
                ADDR_DST_ADDR:  cpu_rdata <= cfg_dst_addr;
                ADDR_XFER_LEN:  cpu_rdata <= cfg_xfer_len;

                ADDR_CTRL: cpu_rdata <= {25'd0, cfg_irq_en, cfg_dst_addr_hold,
                                          cfg_src_addr_hold, cfg_mode, 2'b00};

                ADDR_STATUS: cpu_rdata <= {status_beats_remaining, 13'd0,
                                            status_error, status_done, status_busy};

                ADDR_BURST_CFG: cpu_rdata <= {24'd0, cfg_burst_len};

                ADDR_IRQ_CLEAR: cpu_rdata <= 32'd0; // write-only, reads as 0

                default: cpu_rdata <= 32'd0;
            endcase
        end
    end

endmodule

