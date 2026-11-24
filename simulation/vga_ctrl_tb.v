`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/12/2026 03:53:23 PM
// Design Name: 
// Module Name: vga_ctrl_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module vga_ctrl_tb;
    reg  clk_pix = 0;
    reg  clear   = 1;
    wire V_sync, H_sync, Vid_on;
    wire [9:0] H_cnt, V_cnt;

    vga_ctrl dut(.clk_pix(clk_pix), .clear(clear),
                 .V_sync(V_sync), .H_sync(H_sync),
                 .H_cnt(H_cnt), .V_cnt(V_cnt), .Vid_on(Vid_on));

    always #20 clk_pix = ~clk_pix;            // 25 MHz

    integer clk_count = 0, on_count = 0, hs_low = 0, vs_low = 0;
    integer frames = 0, errors = 0;

    initial #110 clear = 0;

    always @(posedge clk_pix) if (!clear) begin
        clk_count = clk_count + 1;
        if (Vid_on)                  on_count = on_count + 1;
        if (!H_sync && V_cnt == 100) hs_low   = hs_low + 1;   // sync width on one line
        if (!V_sync)                 vs_low   = vs_low + 1;

        if (H_cnt == 799 && V_cnt == 524) begin               // last clock of a frame
            frames = frames + 1;
            if (clk_count != 420000) begin
                $display("FAIL frame %0d: %0d clocks per frame (want 420000)", frames, clk_count);
                errors = errors + 1;
            end
            if (on_count != 307200) begin
                $display("FAIL frame %0d: %0d visible pixels (want 307200)", frames, on_count);
                errors = errors + 1;
            end
            if (hs_low != 96) begin
                $display("FAIL frame %0d: hsync low for %0d clocks (want 96)", frames, hs_low);
                errors = errors + 1;
            end
            if (vs_low != 1600) begin
                $display("FAIL frame %0d: vsync low for %0d clocks (want 1600)", frames, vs_low);
                errors = errors + 1;
            end
            clk_count = 0; on_count = 0; hs_low = 0; vs_low = 0;
        end
    end

    initial begin
        #36_000_000;                                           // a little over 2 frames
        if (errors == 0 && frames >= 2) $display("PASS: %0d frames checked", frames);
        else                            $display("FAIL: %0d errors, %0d frames", errors, frames);
        $finish;
    end
endmodule