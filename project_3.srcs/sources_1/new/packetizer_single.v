`timescale 1ns / 1ps

module packetizer_single #(
    parameter DATA_WIDTH = 32,
    parameter SAMPLES_PER_PACKET = 128,
    parameter [7:0] HEADER_TYPE  = 8'h01,
    parameter [7:0] HEADER_FLAGS = 8'h00
)(
    input  wire                  clk,
    input  wire                  rst,

    input  wire                  cfg_enable,
    input  wire                  clear_counters,
    input  wire [7:0]            cfg_stream_id,
    input  wire [7:0]            cfg_channel_id,
    // input stream
    input  wire [DATA_WIDTH-1:0] in_data,
    input  wire                  in_valid,
    output wire                  in_ready,

    // timestamps
    input  wire [31:0]           timestamp_seconds,
    input  wire [63:0]           timestamp_frac,

    // AXI stream output
    output reg  [DATA_WIDTH-1:0] out_data,
    output reg                   out_valid,
    input  wire                  out_ready,
    output reg                   out_last,

    // status
    output wire [31:0]           packet_count,
    output reg  [31:0]           sample_count_total,
    output wire                  running
);

    localparam HEADER_WORDS = 6;

    localparam S_IDLE   = 2'd0;
    localparam S_HEADER = 2'd1;
    localparam S_DATA   = 2'd2;

    reg [1:0]  state;
    reg [2:0]  header_count;
    reg [15:0] sample_count;
    reg [31:0] sequence_counter;

    wire [15:0] packet_words;
    assign packet_words = HEADER_WORDS + SAMPLES_PER_PACKET;

    assign packet_count = sequence_counter;
    assign running      = (state != S_IDLE);

    assign in_ready = (state == S_DATA) && out_ready && cfg_enable;

    always @(posedge clk) begin
        if (rst) begin
            state             <= S_IDLE;
            header_count      <= 3'd0;
            sample_count      <= 16'd0;
            sequence_counter  <= 32'd0;
            sample_count_total <= 32'd0;

            out_data  <= {DATA_WIDTH{1'b0}};
            out_valid <= 1'b0;
            out_last  <= 1'b0;
        end
        else begin
            out_valid <= 1'b0;
            out_last  <= 1'b0;

            if (clear_counters) begin
                sequence_counter   <= 32'd0;
                sample_count_total <= 32'd0;
            end

            case (state)
                S_IDLE: begin
                    header_count <= 3'd0;
                    sample_count <= 16'd0;

                    // only start packetizing if enabled
                    if (cfg_enable && in_valid && out_ready) begin
                        state <= S_HEADER;
                    end
                end

                S_HEADER: begin
                    if (out_ready) begin
                        out_valid <= 1'b1;

                        case (header_count)
                            // header word 0: type / flags / length
                            3'd0: out_data <= {HEADER_TYPE, HEADER_FLAGS, packet_words};

                            // header word 1: metadata word
                            3'd1: out_data <= {16'd0, cfg_stream_id, cfg_channel_id};

                            // header word 2: sequence counter
                            3'd2: out_data <= sequence_counter;

                            // header word 3: timestamp seconds
                            3'd3: out_data <= timestamp_seconds;

                           // header word 4: timestamp fraction upper
                            // header word 5: timestamp fraction lower
                            3'd4: out_data <= timestamp_frac[63:32];
                            3'd5: out_data <= timestamp_frac[31:0];

                            default: out_data <= 32'd0;
                        endcase

                        if (header_count == HEADER_WORDS - 1) begin
                            state        <= S_DATA;
                            sample_count <= 16'd0;
                        end

                        header_count <= header_count + 1'b1;
                    end
                end

                S_DATA: begin
                    // if disabled mid-packet, you can choose behavior.
                    // for now, finish only when valid+ready and enabled.
                    if (cfg_enable && in_valid && out_ready) begin
                        out_valid <= 1'b1;
                        out_data  <= in_data;

                        sample_count       <= sample_count + 1'b1;
                        sample_count_total <= sample_count_total + 1'b1;

                        if (sample_count == SAMPLES_PER_PACKET - 1) begin
                            out_last         <= 1'b1;
                            state            <= S_IDLE;
                            sequence_counter <= sequence_counter + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule