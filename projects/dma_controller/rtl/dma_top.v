
// Register map (word-addressed, byte offsets) - programmed via
// cpu_addr/cpu_wdata/cpu_wr/cpu_rd on dma_top:
//   0x00 SRC_ADDR   R/W  source start address
//   0x04 DST_ADDR   R/W  destination start address
//   0x08 XFER_LEN   R/W  transfer length in beats
//   0x0C CTRL       R/W  [0]=START [1]=SOFT_RESET [3:2]=MODE
//                        [4]=SRC_ADDR_HOLD [5]=DST_ADDR_HOLD [6]=IRQ_EN
//   0x10 STATUS     RO   [0]=BUSY [1]=DONE [2]=ERROR [31:16]=BEATS_REMAINING
//   0x14 BURST_CFG  R/W  [7:0]=BURST_LEN
//   0x18 IRQ_CLEAR  WO   write 1 to bit 0 to clear the interrupt

`timescale 1ns / 1ps

module dma_top #(
    parameter FIFO_DEPTH = 16,   // Internal FIFO depth, in 32-bit words
    parameter DATA_WIDTH = 32    // Datapath width
) (
    // Clock / Reset
    input  wire        clk,
    input  wire        rst_n,       // synchronous active-low reset

    // CPU / register programming interface
    input  wire [7:0]  cpu_addr,
    input  wire [31:0] cpu_wdata,
    output wire [31:0] cpu_rdata,
    input  wire        cpu_wr,
    input  wire        cpu_rd,
    output wire        cpu_ready,

    // Source (memory/peripheral) port - driven by read engine
    output wire [31:0] src_addr,
    input  wire [31:0] src_rdata,
    output wire        src_ren,
    input  wire        src_ready,

    // Destination (memory/peripheral) port - driven by write engine
    output wire [31:0] dst_addr,
    output wire [31:0] dst_wdata,
    output wire        dst_wen,
    input  wire        dst_ready,

    // Interrupt
    output wire        irq
);

    //--------------------------------------------------------------------
    // Internal signal declarations, grouped by the sub-block that drives
    // them.
    //--------------------------------------------------------------------

    // Configuration bus, driven by dma_register_bank
    wire [31:0] cfg_src_addr;
    wire [31:0] cfg_dst_addr;
    wire [31:0] cfg_xfer_len;
    wire [1:0]  cfg_mode;
    wire        cfg_src_addr_hold;
    wire        cfg_dst_addr_hold;
    wire        cfg_irq_en;
    wire [7:0]  cfg_burst_len;
    wire        start_pulse;
    wire        soft_reset_pulse;
    wire        irq_clear_pulse;

    // Status feedback into register bank
    wire        status_busy;
    wire        status_done;
    wire        status_error;
    wire [15:0] status_beats_remaining;

    // Control FSM outputs
    wire        fsm_busy;
    wire        fsm_done;
    wire        fsm_error;
    wire        read_req;
    wire        write_req;
    wire        addr_advance_src;
    wire        addr_advance_dst;
    wire        counter_decrement;
    wire        xfer_start_pulse;
    wire        burst_start;
    wire        burst_beat_done;

    // Address generator outputs
    wire [31:0] src_addr_cur;
    wire [31:0] dst_addr_cur;

    // Transfer counter outputs
    wire [31:0] beats_remaining;
    wire        counter_done;

    // Burst controller outputs
    wire        burst_done;
    wire        burst_active;

    // Read engine outputs
    wire        read_done;
    wire        fifo_wr_en;
    wire [31:0] fifo_wdata;

    // Write engine outputs
    wire        write_done;
    wire        fifo_rd_en;

    // FIFO outputs
    wire [31:0] fifo_rdata;
    wire        fifo_full;
    wire        fifo_empty;

    // burst_active is a status-only observation point (not consumed
    // elsewhere in this design); tie off explicitly so lint tools do not
    // flag it as an unused/dangling net.
    wire unused_burst_active = burst_active;

    //--------------------------------------------------------------------
    // dma_register_bank : CPU-facing configuration/status registers
    //--------------------------------------------------------------------
    dma_register_bank u_register_bank (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .cpu_addr               (cpu_addr),
        .cpu_wdata              (cpu_wdata),
        .cpu_rdata              (cpu_rdata),
        .cpu_wr                 (cpu_wr),
        .cpu_rd                 (cpu_rd),
        .cpu_ready              (cpu_ready),
        .status_busy            (status_busy),
        .status_done            (status_done),
        .status_error           (status_error),
        .status_beats_remaining (status_beats_remaining),
        .cfg_src_addr           (cfg_src_addr),
        .cfg_dst_addr           (cfg_dst_addr),
        .cfg_xfer_len           (cfg_xfer_len),
        .cfg_mode               (cfg_mode),
        .cfg_src_addr_hold      (cfg_src_addr_hold),
        .cfg_dst_addr_hold      (cfg_dst_addr_hold),
        .cfg_irq_en             (cfg_irq_en),
        .cfg_burst_len          (cfg_burst_len),
        .start_pulse            (start_pulse),
        .soft_reset_pulse       (soft_reset_pulse),
        .irq_clear_pulse        (irq_clear_pulse)
    );

    //--------------------------------------------------------------------
    // dma_control_fsm : master sequencing state machine
    //--------------------------------------------------------------------
    dma_control_fsm u_control_fsm (
        .clk                (clk),
        .rst_n              (rst_n),
        .start_pulse        (start_pulse),
        .soft_reset_pulse   (soft_reset_pulse),
        .cfg_mode           (cfg_mode),
        .cfg_xfer_len       (cfg_xfer_len),
        .fifo_full          (fifo_full),
        .fifo_empty         (fifo_empty),
        .src_ready          (src_ready),
        .dst_ready          (dst_ready),
        .read_done          (read_done),
        .write_done         (write_done),
        .burst_done         (burst_done),
        .counter_done       (counter_done),
        .fsm_busy           (fsm_busy),
        .fsm_done           (fsm_done),
        .fsm_error          (fsm_error),
        .read_req           (read_req),
        .write_req          (write_req),
        .addr_advance_src   (addr_advance_src),
        .addr_advance_dst   (addr_advance_dst),
        .counter_decrement  (counter_decrement),
        .xfer_start_pulse   (xfer_start_pulse),
        .burst_start        (burst_start),
        .burst_beat_done    (burst_beat_done)
    );

    //--------------------------------------------------------------------
    // dma_address_generator : source/destination address sequencing
    //--------------------------------------------------------------------
    dma_address_generator u_address_generator (
        .clk                (clk),
        .rst_n              (rst_n),
        .load               (xfer_start_pulse),
        .cfg_src_addr       (cfg_src_addr),
        .cfg_dst_addr       (cfg_dst_addr),
        .cfg_src_addr_hold  (cfg_src_addr_hold),
        .cfg_dst_addr_hold  (cfg_dst_addr_hold),
        .advance_src        (addr_advance_src),
        .advance_dst        (addr_advance_dst),
        .src_addr_cur       (src_addr_cur),
        .dst_addr_cur       (dst_addr_cur)
    );

    //--------------------------------------------------------------------
    // dma_transfer_counter : remaining-beats tracking
    //--------------------------------------------------------------------
    dma_transfer_counter u_transfer_counter (
        .clk             (clk),
        .rst_n           (rst_n),
        .load            (xfer_start_pulse),
        .cfg_xfer_len    (cfg_xfer_len),
        .decrement       (counter_decrement),
        .beats_remaining (beats_remaining),
        .counter_done    (counter_done)
    );

    //--------------------------------------------------------------------
    // dma_burst_controller : groups beats into bursts
    //--------------------------------------------------------------------
    dma_burst_controller u_burst_controller (
        .clk            (clk),
        .rst_n          (rst_n),
        .burst_start    (burst_start),
        .cfg_burst_len  (cfg_burst_len),
        .beat_done      (burst_beat_done),
        .counter_done   (counter_done),
        .burst_done     (burst_done),
        .burst_active   (burst_active)
    );

    //--------------------------------------------------------------------
    // dma_read_engine : drives the source-side memory interface
    //--------------------------------------------------------------------
    dma_read_engine u_read_engine (
        .clk            (clk),
        .rst_n          (rst_n),
        .read_req       (read_req),
        .src_addr_cur   (src_addr_cur),
        .src_addr       (src_addr),
        .src_rdata      (src_rdata),
        .src_ren        (src_ren),
        .src_ready      (src_ready),
        .fifo_full      (fifo_full),
        .fifo_wr_en     (fifo_wr_en),
        .fifo_wdata     (fifo_wdata),
        .read_done      (read_done)
    );

    //--------------------------------------------------------------------
    // dma_write_engine : drives the destination-side memory interface
    //--------------------------------------------------------------------
    dma_write_engine u_write_engine (
        .clk            (clk),
        .rst_n          (rst_n),
        .write_req      (write_req),
        .dst_addr_cur   (dst_addr_cur),
        .dst_addr       (dst_addr),
        .dst_wdata      (dst_wdata),
        .dst_wen        (dst_wen),
        .dst_ready      (dst_ready),
        .fifo_empty     (fifo_empty),
        .fifo_rdata     (fifo_rdata),
        .fifo_rd_en     (fifo_rd_en),
        .write_done     (write_done)
    );

    //--------------------------------------------------------------------
    // dma_fifo_buffer : decouples read engine (producer) from write engine
    // (consumer), single clock domain synchronous FIFO
    //--------------------------------------------------------------------
    dma_fifo_buffer #(
        .DEPTH (FIFO_DEPTH),
        .WIDTH (DATA_WIDTH)
    ) u_fifo_buffer (
        .clk      (clk),
        .rst_n    (rst_n),
        .wr_en    (fifo_wr_en),
        .wr_data  (fifo_wdata),
        .rd_en    (fifo_rd_en),
        .rd_data  (fifo_rdata),
        .full     (fifo_full),
        .empty    (fifo_empty)
    );

    //--------------------------------------------------------------------
    // dma_interrupt_controller : latches completion event, drives irq
    //--------------------------------------------------------------------
    dma_interrupt_controller u_interrupt_controller (
        .clk              (clk),
        .rst_n            (rst_n),
        .fsm_done         (fsm_done),
        .cfg_irq_en       (cfg_irq_en),
        .irq_clear_pulse  (irq_clear_pulse),
        .irq              (irq)
    );

    //--------------------------------------------------------------------
    // dma_status_register : registers busy/done/error/beats_remaining for
    // the CPU-visible STATUS register (also aids floorplanning by giving
    // the CPU-facing side a dedicated, timing-isolated register stage)
    //--------------------------------------------------------------------
    dma_status_register u_status_register (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .fsm_busy               (fsm_busy),
        .fsm_done               (fsm_done),
        .fsm_error              (fsm_error),
        .beats_remaining        (beats_remaining),
        .status_busy            (status_busy),
        .status_done            (status_done),
        .status_error           (status_error),
        .status_beats_remaining (status_beats_remaining)
    );

endmodule

