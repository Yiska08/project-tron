`timescale 1ns / 1ps

module player #(
    parameter [6:0] START_X   = 7'd10,
    parameter [5:0] START_Y   = 6'd30,
    parameter [1:0] START_DIR = 2'b01
)(
    input            clk, reset,
    input            step,      // 1-clk: compute next cell
    input            commit,    // 1-clk: accept the move
    input      [1:0] dir_in,
    input            dir_valid,
    output reg [6:0] px, nx,    // px = present x , n = next x
    output reg [5:0] py, ny, 
    output reg [1:0] cur_dir
);
    reg [1:0] next_dir;
    always @(posedge clk) begin
        if (reset) begin
            px <= START_X;  nx <= START_X;
            py <= START_Y;  ny <= START_Y;
            cur_dir <= START_DIR;  next_dir <= START_DIR;
        end else begin
            if (step) begin
                cur_dir <= next_dir;
                nx <= px;  ny <= py;
                case (next_dir)
                    2'b00: ny <= py - 6'd1;
                    2'b01: nx <= px + 7'd1;
                    2'b10: ny <= py + 6'd1;
                    2'b11: nx <= px - 7'd1;
                endcase
            end else if (dir_valid && dir_in != (cur_dir ^ 2'b10))
                next_dir <= dir_in;
            if (commit) begin px <= nx;  py <= ny; end
        end
    end
endmodule