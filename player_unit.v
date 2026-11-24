`timescale 1ns / 1ps
//This is an optional wrapper unit that would simplify our top.v more
//This code is not attached to anything, but we can decide whether to use it or not during lab
// One light cycle: joystick + steering mux + player
module player_unit #(
    parameter [6:0] START_X   = 7'd10,
    parameter [5:0] START_Y   = 6'd30,
    parameter [1:0] START_DIR = 2'b01
)(
    input        clk, reset, jstk_clk, clk_poll,
    input        MISO,
    output       SS, MOSI, SCLK,
    input        use_ai,
    input  [1:0] ai_dir,
    input        ai_valid,
    input        step, commit,
    output [6:0] px, nx,
    output [5:0] py, ny,
    output [1:0] cur_dir
);
    wire [1:0] joy_dir;
    wire       joy_valid;

    PmodJSTK_Controller joy (
        .CLK(clk), .RST(reset), .jstk_clk(jstk_clk), .clk_poll(clk_poll),
        .SS(SS), .MOSI(MOSI), .MISO(MISO), .SCLK(SCLK),
        .dir(joy_dir), .valid(joy_valid)
    );

    player #(.START_X(START_X), .START_Y(START_Y), .START_DIR(START_DIR)) cycle (
        .clk(clk), .reset(reset), .step(step), .commit(commit),
        .dir_in   (use_ai ? ai_dir   : joy_dir),
        .dir_valid(use_ai ? ai_valid : joy_valid),
        .px(px), .py(py), .nx(nx), .ny(ny), .cur_dir(cur_dir)
    );
endmodule