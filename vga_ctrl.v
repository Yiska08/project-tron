`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/12/2026 03:50:34 PM
// Design Name: 
// Module Name: vga_ctrl
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

module vga_ctrl(
    input        clk,           // 100 MHz master clock
    input        pix_en,        // 25 MHz 1-cycle pixel enable pulse
    input        clear,         // Synchronous active-high reset
    output reg   V_sync,        // Vertical sync pulse (active low, once per frame)
    output reg   H_sync,        // Horizontal sync pulse (active low, once per line)
    output [9:0] H_cnt,         // Current horizontal pixel position (0..799)
    output [9:0] V_cnt,         // Current vertical line position (0..524)
    output reg   Vid_on         // 1 = inside visible 640x480 screen; 0 = blanking area (must output black)
);
    // 640x480 @ 60 Hz VGA Timing Constants (25 MHz pixel rate)
    parameter HPIXELS = 800;    // Total horizontal pixels per line (96 sync + 48 back + 640 active + 16 front)
    parameter VLINES  = 525;    // Total vertical lines per frame (2 sync + 33 back + 480 active + 10 front)
    parameter HSP = 96;         // Horizontal sync pulse width
    parameter HBP = 144;        // Active video start X (96 + 48)
    parameter HFP = 784;        // Active video end X   (144 + 640)
    parameter VSP = 2;          // Vertical sync pulse width
    parameter VBP = 35;         // Active video start Y (2 + 33)
    parameter VFP = 515;        // Active video end Y   (35 + 480)

    reg [9:0] H_count_reg, H_count_next;
    reg [9:0] V_count_reg, V_count_next;

    // Update pixel/line counters on 100 MHz clock, gated by 25 MHz pix_en
    always @(posedge clk) begin
        if (clear) begin
            H_count_reg <= 10'd0;
            V_count_reg <= 10'd0;
        end else if (pix_en) begin
            H_count_reg <= H_count_next;
            V_count_reg <= V_count_next;
        end
    end

    // Horizontal counter: counts 0..799 across a scanline, then wraps
    always @(*) begin
        if (H_count_reg == HPIXELS-1) H_count_next = 10'd0;
        else                          H_count_next = H_count_reg + 1'b1;
    end

    // Vertical counter: increments once at the end of every horizontal line (0..524)
    wire V_count_en = (H_count_reg == HPIXELS-1);
    always @(*) begin
        V_count_next = V_count_reg;
        if (V_count_en) begin
            if (V_count_reg == VLINES-1) V_count_next = 10'd0;
            else                         V_count_next = V_count_reg + 1'b1;
        end
    end

    assign H_cnt = H_count_reg;
    assign V_cnt = V_count_reg;

    // Generate active-low sync pulses during the start of each line/frame
    always @(*) H_sync = (H_count_reg < HSP) ? 1'b0 : 1'b1;
    always @(*) V_sync = (V_count_reg < VSP) ? 1'b0 : 1'b1;

    // Vid_on (Video Enable / Active Display Region):
    // High ONLY when the electron beam/scan is inside the visible 640x480 screen
    // (H_cnt: 144..783, V_cnt: 35..514). Outside this window is the invisible "blanking"
    // region (sync + porches), where RGB outputs MUST be forced to 0V (black) so the
    // monitor can properly calibrate its black level and lock onto the signal.
    always @(*) begin
        if (H_count_reg >= HBP && H_count_reg < HFP &&
            V_count_reg >= VBP && V_count_reg < VFP)
            Vid_on = 1'b1;
        else
            Vid_on = 1'b0;
    end
endmodule
           