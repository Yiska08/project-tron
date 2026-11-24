`timescale 1ns / 1ps
// Converts PmodJSTK 10-bit X/Y (0..1023, center ~512) into a Tron direction.
// dir: 00=Up 01=Right 10=Down 11=Left    valid=1 only when stick is pushed past dead zone
module joy_to_dir #(
    parameter DEADZONE = 11'd200,   // how far from center before it counts
    parameter INVERT_Y = 1'b0,       // set to 1 if up/down come out swapped
    parameter INVERT_X = 1'b0       // set to 1 to swap directions, THESE are only for ease of swapping directions
)(
    input  wire       clk,

    input wire  [39:0] jstkData,
    output wire  [1:0] dir,
    output wire        valid
);

    // Sliced 			 // assign posData = (SW[0] == 1'b1) ? {jstkData[9:8], jstkData[23:16]} : {jstkData[25:24], jstkData[39:32]};
    wire [9:0] joy_x = {jstkData[25:24], jstkData[39:32]};
    wire [9:0] joy_y = {jstkData[9:8],   jstkData[23:16]};
    // X data is sent in two different bytes, forex 1st byte is 39:32 and next 2 bits is at 25:24

    // Signed offset from center
    wire signed [10:0] dx_raw = $signed({1'b0, joy_x}) - 11'sd512;
    wire signed [10:0] dy_raw = $signed({1'b0, joy_y}) - 11'sd512;
    wire signed [10:0] dy = INVERT_Y ? -dy_raw : dy_raw;
    wire signed [10:0] dx = INVERT_X ? -dx_raw : dx_raw;


    // Magnitudes, converts signed
    wire [10:0] adx = dx[10] ? -dx : dx;
    wire [10:0] ady = dy[10] ? -dy : dy;

    assign valid = (adx > DEADZONE) || (ady > DEADZONE);
    assign dir   = (adx > ady) ? (dx[10] ? 2'd3 : 2'd1) : (dy[10] ? 2'd2 : 2'd0);   // Down : Up

endmodule