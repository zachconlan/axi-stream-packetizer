`timescale 1ns / 1ps

module tb_packetizer_axi_lite_top;

    // -------------------------
    // Parameters
    // -------------------------
    localparam DATA_WIDTH          = 32;
    localparam C_S_AXI_DATA_WIDTH  = 32;
    localparam C_S_AXI_ADDR_WIDTH  = 6;
    localparam SAMPLES_PER_PACKET  = 16;

    // -------------------------
    // Clocks / resets
    // -------------------------
    reg clk = 0;
    reg rst = 1;

    reg s_axi_aclk = 0;
    reg s_axi_aresetn = 0;

    always #5 clk = ~clk;          // 100 MHz data clock
    always #5 s_axi_aclk = ~s_axi_aclk;  // 100 MHz AXI-Lite clock

    // -------------------------
    // DUT input stream
    // -------------------------
    reg  [DATA_WIDTH-1:0] in_data;
    reg                   in_valid;

    // -------------------------
    // DUT AXI-Stream output
    // -------------------------
    wire [DATA_WIDTH-1:0] m_axis_tdata;
    wire                  m_axis_tvalid;
    reg                   m_axis_tready;
    wire                  m_axis_tlast;

    // -------------------------
    // AXI-Lite interface
    // -------------------------
    reg  [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    reg                           s_axi_awvalid;
    wire                          s_axi_awready;

    reg  [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata;
    reg  [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb;
    reg                           s_axi_wvalid;
    wire                          s_axi_wready;

    wire [1:0]                    s_axi_bresp;
    wire                          s_axi_bvalid;
    reg                           s_axi_bready;

    reg  [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    reg                           s_axi_arvalid;
    wire                          s_axi_arready;

    wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata;
    wire [1:0]                    s_axi_rresp;
    wire                          s_axi_rvalid;
    reg                           s_axi_rready;

    // -------------------------
    // Bookkeeping
    // -------------------------
    integer word_count = 0;
    integer packet_count_seen = 0;
    integer f_bin;

    // -------------------------
    // DUT
    // -------------------------
    packetizer_axi_lite_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .SAMPLES_PER_PACKET(SAMPLES_PER_PACKET)
    ) dut (
        .clk(clk),
        .rst(rst),

        .in_data(in_data),
        .in_valid(in_valid),

        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),

        .s_axi_aclk(s_axi_aclk),
        .s_axi_aresetn(s_axi_aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),

        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),

        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),

        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),

        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready)
    );

    // -------------------------
    // AXI-Lite write task
    // -------------------------
    task axi_write;
        input [C_S_AXI_ADDR_WIDTH-1:0] addr;
        input [C_S_AXI_DATA_WIDTH-1:0] data;
        begin
            @(posedge s_axi_aclk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wstrb   <= {C_S_AXI_DATA_WIDTH/8{1'b1}};
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;

            wait (s_axi_awready && s_axi_wready);
            @(posedge s_axi_aclk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;

            wait (s_axi_bvalid);
            @(posedge s_axi_aclk);
            s_axi_bready <= 1'b0;
        end
    endtask

    // -------------------------
    // AXI-Lite read task
    // -------------------------
    task axi_read;
        input  [C_S_AXI_ADDR_WIDTH-1:0] addr;
        begin
            @(posedge s_axi_aclk);
            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;

            wait (s_axi_arready);
            @(posedge s_axi_aclk);
            s_axi_arvalid <= 1'b0;

            wait (s_axi_rvalid);
            $display("AXI READ  addr=%h data=%h", addr, s_axi_rdata);
            @(posedge s_axi_aclk);
            s_axi_rready <= 1'b0;
        end
    endtask

    // -------------------------
    // Initial setup
    // -------------------------
    initial begin
        in_data       = 0;
        in_valid      = 0;
        m_axis_tready = 1'b1;

        s_axi_awaddr  = 0;
        s_axi_awvalid = 0;
        s_axi_wdata   = 0;
        s_axi_wstrb   = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 0;
        s_axi_araddr  = 0;
        s_axi_arvalid = 0;
        s_axi_rready  = 0;

        f_bin = $fopen("axi_packetizer_dump.bin", "wb");
        if (f_bin == 0) begin
            $display("ERROR: could not open axi_packetizer_dump.bin");
            $finish;
        end

        #40;
        rst = 0;
        s_axi_aresetn = 1;

        // configure stream_id/channel_id
        // REG_CONFIG = 0x04
        axi_write(6'h04, 32'h0000_0201); // channel_id=0x02, stream_id=0x01

        // enable packetizer
        // REG_CONTROL = 0x00, bit0 = enable
        axi_write(6'h00, 32'h0000_0001);

        // read back config/status
        axi_read(6'h04);
        axi_read(6'h08);

        // start driving input samples
        @(posedge clk);
        in_valid <= 1'b1;
    end

    // -------------------------
    // Input sample generator
    // -------------------------
       always @(posedge clk) begin
        if (rst) begin
            in_data  <= 0;
            in_valid <= 0;
        end
        else begin
            in_valid <= 1'b1;
    
            if (in_valid && dut.in_ready) begin
                in_data <= in_data + 1;
            end
        end
    end

    // -------------------------
    // Output monitor / logger
    // -------------------------
    always @(posedge clk) begin
        if (!rst && m_axis_tvalid && m_axis_tready) begin
            $display("word=%0d data=%h last=%b", word_count, m_axis_tdata, m_axis_tlast);

            $fwrite(f_bin, "%c%c%c%c",
                m_axis_tdata[31:24],
                m_axis_tdata[23:16],
                m_axis_tdata[15:8],
                m_axis_tdata[7:0]
            );

            word_count = word_count + 1;

            if (m_axis_tlast) begin
                packet_count_seen = packet_count_seen + 1;
                $display("---- end of packet %0d ----", packet_count_seen);
            end
        end
    end

    // -------------------------
    // Stop after a few packets
    // -------------------------
    always @(posedge clk) begin
        if (!rst && packet_count_seen >= 5) begin
            $display("Simulation finished");
            $fclose(f_bin);
            $finish;
        end
    end

endmodule
