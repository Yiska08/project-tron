`timescale 1ns / 1ps

module top(
    input         clk,              // 100 MHz master clock
    input         btnC,             // Center button (synchronous reset)
    input  [15:0] sw,               // Switches (available for game speed / start / mode)
    output [3:0]  vgaRed, vgaGreen, vgaBlue,
    output        Hsync, Vsync
);
    // 1. 2-FF synchronizer for pushbutton reset
    reg rst_sync1, rst_sync2;
    always @(posedge clk) begin
        rst_sync1 <= btnC;
        rst_sync2 <= rst_sync1;
    end
    wire reset = rst_sync2;

    reg jstk_clk;
    reg clk_poll;
    // 2. Clock divider (100 MHz -> 25 MHz VGA enable ticks)
    wire pix_en, spi_tick, seg_tick, debounce_tick;
    clock tick_gen (
        .RESET         (reset),
        .clk           (clk),
        .pix_en        (pix_en),
        
        .seg_tick      (seg_tick),
        .debounce_tick (debounce_tick),

        //For jmodcontroller
        .spi_tick      (spi_tick),
        .jstk_clk(jstk_clk),
        .clk_poll(clk_poll)
    );

    // 3. VGA timing controller
    wire [9:0] H_cnt, V_cnt;
    wire Vid_on;
    vga_ctrl vga (
        .clk    (clk),
        .pix_en (pix_en),
        .clear  (reset),
        .V_sync (Vsync),
        .H_sync (Hsync),
        .H_cnt  (H_cnt),
        .V_cnt  (V_cnt),
        .Vid_on (Vid_on)
    );

    // 4. Screen coordinates -> 80x60 grid (8x8 pixel tiles)
    wire [9:0] x  = H_cnt - 10'd144;     // 0..639
    wire [9:0] y  = V_cnt - 10'd35;      // 0..479
    wire [6:0] cx = x[9:3];              // 0..79 (80 columns)
    wire [5:0] cy = y[8:3];              // 0..59 (60 rows)

    wire is_grid_line = (x[2:0] == 3'd0) || (y[2:0] == 3'd0);
    wire is_border    = (cx <= 7'd1) || (cx >= 7'd78) || (cy <= 6'd1) || (cy >= 6'd58);

    // 5. Temporary BRAM Scene Loader (sweeps 80x60 cells on startup/reset)
        // Replace this block with your Tron game FSM once ready!
        reg        init_done = 1'b0;
        reg [6:0]  init_x    = 7'd0;
        reg [5:0]  init_y    = 6'd0;
        reg        game_we;
        reg [1:0]  game_din;
    
        always @(posedge clk) begin
            if (reset) begin
                init_done <= 1'b0;
                init_x    <= 7'd0;
                init_y    <= 6'd0;
            end else if (!init_done) begin
                if (init_x == 7'd79) begin
                    init_x <= 7'd0;
                    if (init_y == 6'd59)
                        init_done <= 1'b1;
                    else
                        init_y <= init_y + 6'd1;
                end else begin
                    init_x <= init_x + 7'd1;
                end
            end
        end
    
        // Decide what sample pattern to write into each cell of BRAM
        always @(*) begin
            game_we = !init_done;
            if (init_x <= 7'd1 || init_x >= 7'd78 || init_y <= 6'd1 || init_y >= 6'd58)
                game_din = 2'b11;                                       // Gray border wall
            else if ((init_y == 6'd30 && init_x >= 7'd15 && init_x <= 7'd25) ||
                     (init_x == 7'd25 && init_y >= 6'd20 && init_y <= 6'd30))
                game_din = 2'b01;                                       // Sample Cyan P1 trail
            else if ((init_y == 6'd30 && init_x >= 7'd55 && init_x <= 7'd65) ||
                     (init_x == 7'd55 && init_y >= 6'd30 && init_y <= 6'd40))
                game_din = 2'b10;                                       // Sample Orange P2 trail
            else
                game_din = 2'b00;                                       // Empty grid cell
        end
    
        // 6. Dual-Port Block RAM Framebuffer (80x60 = 4,800 cells)
        wire [1:0] cell_state;
        wire [1:0] unused_dout_a;
    
        grid_ram arena_ram (
            .clk    (clk),
            // Port A: Temporary Scene Loader (later: Tron Game FSM)
            .we_a   (game_we),
            .ax     (init_x),
            .ay     (init_y),
            .din_a  (game_din),
            .dout_a (unused_dout_a),
            // Port B: VGA Display Scan
            .vx     (cx),
            .vy     (cy),
            .dout_b (cell_state)
        );
    
        // 7. Tron Color Renderer (reads purely from BRAM dout_b)
        reg [11:0] rgb;
        always @(*) begin
            case (cell_state)
                2'b01:   rgb = 12'h0FF;                                 // Player 1 trail (Cyan)
                2'b10:   rgb = 12'hF80;                                 // Player 2 trail (Orange)
                2'b11:   rgb = 12'hAAA;                                 // Arena border/wall (Gray)
                default: rgb = is_grid_line ? 12'h113 : 12'h001;        // Empty grid cell
            endcase
        end
    
        assign {vgaRed, vgaGreen, vgaBlue} = Vid_on ? rgb : 12'h000;
    endmodule