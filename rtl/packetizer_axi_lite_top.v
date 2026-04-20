`timescale 1ns / 1ps

module packetizer_axi_lite_top #(
    parameter integer DATA_WIDTH = 32,
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6,
    parameter integer SAMPLES_PER_PACKET = 128
)(
    input  wire                               clk,
    input  wire                               rst,

    // input data
    input  wire [DATA_WIDTH-1:0]              in_data,
    input  wire                               in_valid,

    // AXI-Stream output
    output wire [DATA_WIDTH-1:0]              m_axis_tdata,
    output wire                               m_axis_tvalid,
    input  wire                               m_axis_tready,
    output wire                               m_axis_tlast,

    // AXI-Lite slave interface
    input  wire                               s_axi_aclk,
    input  wire                               s_axi_aresetn,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]      s_axi_awaddr,
    input  wire                               s_axi_awvalid,
    output reg                                s_axi_awready,

    input  wire [C_S_AXI_DATA_WIDTH-1:0]      s_axi_wdata,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0]    s_axi_wstrb,
    input  wire                               s_axi_wvalid,
    output reg                                s_axi_wready,

    output reg [1:0]                          s_axi_bresp,
    output reg                                s_axi_bvalid,
    input  wire                               s_axi_bready,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]      s_axi_araddr,
    input  wire                               s_axi_arvalid,
    output reg                                s_axi_arready,

    output reg [C_S_AXI_DATA_WIDTH-1:0]       s_axi_rdata,
    output reg [1:0]                          s_axi_rresp,
    output reg                                s_axi_rvalid,
    input  wire                               s_axi_rready
);

    wire in_ready;

    // -------------------------------
    // AXI-Lite registers
    // -------------------------------
    // 0x00 control
    //   bit 0 = enable
    //   bit 1 = clear_counters (self-clearing pulse)
    //
    // 0x04 config
    //   bits [7:0]   = stream_id
    //   bits [15:8]  = channel_id
    //
    // 0x08 status
    //   bit 0 = running
    //
    // 0x0C packet_count
    // 0x10 sample_count_total

    reg        cfg_enable_reg;
    reg [7:0]  cfg_stream_id_reg;
    reg [7:0]  cfg_channel_id_reg;
    reg        clear_counters_pulse;

    wire [31:0] packet_count;
    wire [31:0] sample_count_total;
    wire        running;

    wire [31:0] ts_seconds;
    wire [63:0] ts_frac;

    localparam ADDR_LSB    = 2;
    localparam REG_CONTROL = 4'h0;  // 0x00
    localparam REG_CONFIG  = 4'h1;  // 0x04
    localparam REG_STATUS  = 4'h2;  // 0x08
    localparam REG_PKT_CNT = 4'h3;  // 0x0C
    localparam REG_SMP_CNT = 4'h4;  // 0x10

    wire [3:0] axi_awaddr_word = s_axi_awaddr[ADDR_LSB +: 4];
    wire [3:0] axi_araddr_word = s_axi_araddr[ADDR_LSB +: 4];

    // -------------------------------
    // Timestamp generator
    // sample_tick asserted when input sample is accepted
    // -------------------------------
    timestamp_generator #(
        .FRAC_INCREMENT(64'd150000000000)
    ) ts_gen (
        .clk        (clk),
        .rst        (rst),
        .sample_tick(in_valid && in_ready),
        .pps        (1'b0),
        .seconds    (ts_seconds),
        .frac       (ts_frac)
    );

    // -------------------------------
    // Packetizer core
    // -------------------------------
    packetizer_single #(
        .DATA_WIDTH        (DATA_WIDTH),
        .SAMPLES_PER_PACKET(SAMPLES_PER_PACKET)
    ) pkt (
        .clk               (clk),
        .rst               (rst),

        .cfg_enable        (cfg_enable_reg),
        .clear_counters    (clear_counters_pulse),
        .cfg_stream_id     (cfg_stream_id_reg),
        .cfg_channel_id    (cfg_channel_id_reg),

        .in_data           (in_data),
        .in_valid          (in_valid),
        .in_ready          (in_ready),

        .timestamp_seconds (ts_seconds),
        .timestamp_frac    (ts_frac),

        .out_data          (m_axis_tdata),
        .out_valid         (m_axis_tvalid),
        .out_ready         (m_axis_tready),
        .out_last          (m_axis_tlast),

        .packet_count      (packet_count),
        .sample_count_total(sample_count_total),
        .running           (running)
    );

    // -------------------------------
    // AXI-Lite write channel
    // -------------------------------
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready        <= 1'b0;
            s_axi_wready         <= 1'b0;
            s_axi_bvalid         <= 1'b0;
            s_axi_bresp          <= 2'b00;

            cfg_enable_reg       <= 1'b0;
            cfg_stream_id_reg    <= 8'd0;
            cfg_channel_id_reg   <= 8'd0;
            clear_counters_pulse <= 1'b0;
        end
        else begin
            s_axi_awready        <= 1'b0;
            s_axi_wready         <= 1'b0;
            clear_counters_pulse <= 1'b0;

            if (!s_axi_bvalid && s_axi_awvalid && s_axi_wvalid) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;

                case (axi_awaddr_word)
                    REG_CONTROL: begin
                        if (s_axi_wstrb[0]) begin
                            cfg_enable_reg <= s_axi_wdata[0];
                            if (s_axi_wdata[1])
                                clear_counters_pulse <= 1'b1;
                        end
                    end

                    REG_CONFIG: begin
                        if (s_axi_wstrb[0])
                            cfg_stream_id_reg <= s_axi_wdata[7:0];
                        if (s_axi_wstrb[1])
                            cfg_channel_id_reg <= s_axi_wdata[15:8];
                    end

                    default: begin
                    end
                endcase
            end
            else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // -------------------------------
    // AXI-Lite read channel
    // -------------------------------
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= {C_S_AXI_DATA_WIDTH{1'b0}};
        end
        else begin
            s_axi_arready <= 1'b0;

            if (!s_axi_rvalid && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00;

                case (axi_araddr_word)
                    REG_CONTROL: begin
                        s_axi_rdata <= {{(C_S_AXI_DATA_WIDTH-2){1'b0}}, 1'b0, cfg_enable_reg};
                    end

                    REG_CONFIG: begin
                        s_axi_rdata <= {{(C_S_AXI_DATA_WIDTH-16){1'b0}}, cfg_channel_id_reg, cfg_stream_id_reg};
                    end

                    REG_STATUS: begin
                        s_axi_rdata <= {{(C_S_AXI_DATA_WIDTH-1){1'b0}}, running};
                    end

                    REG_PKT_CNT: begin
                        s_axi_rdata <= packet_count;
                    end

                    REG_SMP_CNT: begin
                        s_axi_rdata <= sample_count_total;
                    end

                    default: begin
                        s_axi_rdata <= {C_S_AXI_DATA_WIDTH{1'b0}};
                    end
                endcase
            end
            else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule