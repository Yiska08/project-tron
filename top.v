`timescale 1ns / 1ps

module top(
    input         clk,              // 100 MHz master clock
    input         btnC,             // Center button: reset + new round
    input         btnU, btnD, btnL, btnR,   // Direction buttons (stand-in for joystick)
    input  [15:0] sw,               // Switches (unused for now)
    output [15:0] led,              // led[0] = alive, led[1] = crashed
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


    // 2. Clock divider (100 MHz -> 25 MHz VGA enable ticks)
    wire pix_en, jstk_clk, clk_poll, seg_tick, debounce_tick;
    clock tick_gen (
        .RESET         (reset),
        .clk           (clk),
        .pix_en        (pix_en),
        
        .seg_tick      (seg_tick),
        .debounce_tick (debounce_tick),

        //For jmodcontroller
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
    wire [6:0] cx = x[9:3];              // 0..79
    wire [5:0] cy = y[8:3];              // 0..59
    wire is_grid_line = (x[2:0] == 3'd0) || (y[2:0] == 3'd0);

    // 5. Start a grid clear right after reset is released (1-clk pulse)
    reg started;
    always @(posedge clk) begin
        if (reset) started <= 1'b0;
        else       started <= 1'b1;
    end
    wire clear_start = !reset && !started;

    // 6. grid_clear: writes border walls + empty interior
    wire       clr_busy, clr_done, clr_we;
    wire [6:0] clr_x;
    wire [5:0] clr_y;
    wire [1:0] clr_din;
    grid_clear clr (
        .clk   (clk),
        .reset (reset),
        .start (clear_start),
        .busy  (clr_busy),
        .done  (clr_done),
        .we    (clr_we),
        .x     (clr_x),
        .y     (clr_y),
        .din   (clr_din)
    );

    // 7. Buttons -> direction (later: replace with joystick module)
    wire [1:0] dir;
    wire       dir_valid;
    btn_dir buttons (
        .clk       (clk),
        .btnU      (btnU),
        .btnR      (btnR),
        .btnD      (btnD),
        .btnL      (btnL),
        .dir       (dir),
        .dir_valid (dir_valid)
    );

    // 8. move_fsm: one light cycle (Mode 1)
    wire       mv_we, alive, crashed;
    wire [6:0] mv_x;
    wire [5:0] mv_y;
    wire [1:0] mv_din;
    wire [1:0] ram_dout_a;
    move_fsm mover (
        .clk       (clk),
        .reset     (reset),
        .go        (clr_done),
        .dir_in    (dir),
        .dir_valid (dir_valid),
        .we        (mv_we),
        .ax        (mv_x),
        .ay        (mv_y),
        .din       (mv_din),
        .dout      (ram_dout_a),
        .alive     (alive),
        .crashed   (crashed)
    );

    // 9. Port A mux: grid_clear owns the RAM while clearing, move_fsm otherwise
    wire       a_we  = clr_busy ? clr_we  : mv_we;
    wire [6:0] a_x   = clr_busy ? clr_x   : mv_x;
    wire [5:0] a_y   = clr_busy ? clr_y   : mv_y;
    wire [1:0] a_din = clr_busy ? clr_din : mv_din;

    // 10. Dual-port grid RAM (80x60 = 4,800 cells)
    wire [1:0] cell_state;
    grid_ram arena_ram (
        .clk    (clk),
        .we_a   (a_we),
        .ax     (a_x),
        .ay     (a_y),
        .din_a  (a_din),
        .dout_a (ram_dout_a),
        .vx     (cx),
        .vy     (cy),
        .dout_b (cell_state)
    );

    // 11. Renderer: cell code -> color
    reg [11:0] rgb;
    always @(*) begin
        case (cell_state)
            2'b01:   rgb = 12'h0FF;                              // P1 trail (cyan)
            2'b10:   rgb = 12'hF80;                              // P2 trail (orange)
            2'b11:   rgb = crashed ? 12'hF00 : 12'hAAA;          // wall: gray, red after crash
            default: rgb = is_grid_line ? 12'h113 : 12'h001;     // empty cell
        endcase
    end
    assign {vgaRed, vgaGreen, vgaBlue} = Vid_on ? rgb : 12'h000;

    // 12. Status LEDs
    assign led = {14'd0, crashed, alive};
endmodule
