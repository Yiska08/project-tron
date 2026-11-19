`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/17/2026 04:35:32 PM
// Design Name: 
// Module Name: grid_ram
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

// Standard Dual-Port Synchronous Block RAM (4800 x 2-bit)
// Architecture based on Xilinx Vivado BRAM inference templates / Pong P. Chu
module grid_ram (
    input  wire        clk,        // 100 MHz master clock

    // PORT A: Game Logic (Read/Write for collision checks & drawing trails)
    input  wire        we_a,       // 1 = write new cell state
    input  wire [6:0]  ax,         // Game X coordinate (0..79)
    input  wire [5:0]  ay,         // Game Y coordinate (0..59)
    input  wire [1:0]  din_a,      // 00=Empty, 01=P1 Cyan, 10=P2 Orange, 11=Wall
    output reg  [1:0]  dout_a,     // Lets game logic check if target cell is already occupied!

    // PORT B: VGA Display (Read-Only continuous scan)
    input  wire [6:0]  vx,         // VGA current tile X (cx: 0..79)
    input  wire [5:0]  vy,         // VGA current tile Y (cy: 0..59)
    output reg  [1:0]  dout_b      // Cell color code sent to RGB multiplexer
);
    // 80 * 60 = 4,800 cells, 2 bits per cell (fits inside one 18Kb Basys 3 BRAM)
    (* ram_style = "block" *) reg [1:0] mem [0:4799];

    // Linear address calculation: y * 80 + x = (y * 64) + (y * 16) + x
    wire [12:0] addr_a = ({7'd0, ay} << 6) + ({7'd0, ay} << 4) + {6'd0, ax};
    wire [12:0] addr_b = ({7'd0, vy} << 6) + ({7'd0, vy} << 4) + {6'd0, vx};

    // Port A: Game Engine Read/Write
    always @(posedge clk) begin
        if (we_a)
            mem[addr_a] <= din_a;
        dout_a <= mem[addr_a];
    end

    // Port B: VGA Continuous Read
    always @(posedge clk) begin
        dout_b <= mem[addr_b];
    end
endmodule