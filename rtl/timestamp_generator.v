`timescale 1ns / 1ps

module timestamp_generator #(
    parameter FRAC_INCREMENT = 64'd150000000000
)(
    input  wire clk,
    input  wire rst,

    input  wire sample_tick,   // increment time when sample accepted
    input  wire pps,

    output reg [31:0] seconds,
    output reg [63:0] frac
);

    always @(posedge clk) begin
    
        if (rst) begin
            seconds <= 0;
            frac <= 0;
        end
    
        else begin
    
            // PPS synchronization (optional)
            if (pps) begin
                seconds <= seconds + 1;
                frac <= 0;
            end
    
            // advance timestamp by one sample period
            else if (sample_tick) begin
                {seconds, frac} <= {seconds, frac} + {32'd0, FRAC_INCREMENT};
            end
    
        end
    
    end

endmodule