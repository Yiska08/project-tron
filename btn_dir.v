`timescale 1ns / 1ps
// btn_dir: turns the 4 direction buttons into the same dir/dir_valid signals
// the joystick module will produce later (so the joystick can just replace this).
// dir encoding: 00 = UP, 01 = RIGHT, 10 = DOWN, 11 = LEFT
module btn_dir (
    input            clk,
    input            btnU, btnR, btnD, btnL,
    output reg [1:0] dir,
    output reg       dir_valid   // 1 while any direction button is held
);
    // 2-FF synchronizer (buttons are asynchronous to clk)
    reg [3:0] s1, s2;
    always @(posedge clk) begin
        s1 <= {btnL, btnD, btnR, btnU};
        s2 <= s1;
    end

    always @(*) begin
        dir_valid = |s2;
        dir       = 2'b00;
        if      (s2[0]) dir = 2'b00;   // UP
        else if (s2[1]) dir = 2'b01;   // RIGHT
        else if (s2[2]) dir = 2'b10;   // DOWN
        else if (s2[3]) dir = 2'b11;   // LEFT
    end
endmodule
