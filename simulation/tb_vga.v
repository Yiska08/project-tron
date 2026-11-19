`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/17/2026 03:26:57 PM
// Design Name: 
// Module Name: tb_vga
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

module tb_vga;
    // Inputs
    reg clk;
    reg reset;

    // Wires connecting clock.v -> vga_ctrl.v
    wire pix_en;
    wire spi_tick;
    wire seg_tick;
    wire debounce_tick;

    // VGA outputs
    wire V_sync;
    wire H_sync;
    wire [9:0] H_cnt;
    wire [9:0] V_cnt;
    wire Vid_on;

    // 1. Instantiate clock divider
    clock uut_clk (
        .RESET         (reset),
        .clk           (clk),
        .pix_en        (pix_en),
        .spi_tick      (spi_tick),
        .seg_tick      (seg_tick),
        .debounce_tick (debounce_tick)
    );

    // 2. Instantiate VGA controller
    vga_ctrl uut_vga (
        .clk    (clk),
        .pix_en (pix_en),
        .clear  (reset),
        .V_sync (V_sync),
        .H_sync (H_sync),
        .H_cnt  (H_cnt),
        .V_cnt  (V_cnt),
        .Vid_on (Vid_on)
    );

    // 3. Generate 100 MHz master clock (10 ns period -> toggle every 5 ns)
    initial clk = 0;
    always #5 clk = ~clk;

    // 4. Stimulus & Self-Checking
    time t_hsync_fall, t_hsync_rise;
    initial begin
        // Hold reset high for 50 ns (5 clock cycles)
        reset = 1;
        #50;
        @(posedge clk);
        reset = 0;

        // Measure one H_sync low pulse width (should be 96 * 40 ns = 3840 ns)
        @(negedge H_sync);
        t_hsync_fall = $time;
        @(posedge H_sync);
        t_hsync_rise = $time;
        $display("[CHECK] H_sync low width = %0t ns (Expected: 3840 ns)", t_hsync_rise - t_hsync_fall);

        // Wait until first visible pixel turns on (H_cnt == 144, V_cnt == 35)
        wait (Vid_on == 1'b1);
        $display("[CHECK] Vid_on asserted at H_cnt=%0d, V_cnt=%0d (Expected: 144, 35)", H_cnt, V_cnt);

        // Wait for one full frame to finish (V_cnt wraps back to 0 after 524)
        wait (V_cnt == 10'd524 && H_cnt == 10'd799 && pix_en == 1'b1);
        @(posedge clk);
        #20;
        $display("[PASS] Full 800x525 VGA frame completed at time %0t ns!", $time);
        $finish;
    end
endmodule