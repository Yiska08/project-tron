`timescale 1ns / 1ps
// grid_clear: sweeps all 80x60 cells once, writing a wall border and an empty inside.
// Pulse `start` for 1 clk -> busy goes high for 4800 clks -> `done` pulses for 1 clk.
module grid_clear (
    input            clk,
    input            reset,
    input            start,
    output reg       busy,
    output reg       done,       // 1-clk pulse when the sweep finishes
    output           we,
    output reg [6:0] x,          // 0..79
    output reg [5:0] y,          // 0..59
    output     [1:0] din
);
    assign we  = busy;
    assign din = (x == 7'd0 || x == 7'd79 || y == 6'd0 || y == 6'd59) ? 2'b11   // wall
                                                                       : 2'b00;  // empty

    always @(posedge clk) begin
        done <= 1'b0;
        if (reset) begin
            busy <= 1'b0;
            x    <= 7'd0;
            y    <= 6'd0;
        end else if (start && !busy) begin
            busy <= 1'b1;
            x    <= 7'd0;
            y    <= 6'd0;
        end else if (busy) begin
            if (x == 7'd79) begin
                x <= 7'd0;
                if (y == 6'd59) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    y <= y + 6'd1;
                end
            end else begin
                x <= x + 7'd1;
            end
        end
    end
endmodule
