`timescale 1ns / 1ps

module top(
    input         clk,              // 100 MHz master clock
    input         btnC,             // Center button: reset + new round
    // input         btnU, btnD, btnL, btnR,   // Direction buttons (stand-in for joystick)
    input  [15:0] sw,               // Switches (unused for now)
    output [15:0] led,              // led[0] = alive, led[1] = crashed
    output [3:0]  vgaRed, vgaGreen, vgaBlue,
    output        Hsync, Vsync,
    //Joystick Control pins
    output JA_SS, JA_MOSI, JA_SCLK,
    input  JA_MISO,
    output JB_SS, JB_MOSI, JB_SCLK,
    input  JB_MISO
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
    
        //Mode select Sw0 and Sw 1 
    // 00 -> 1 Player 01 -> two player 10 -> Ai mode
    // 11 unused? maybe optional mode

    // Synchronize the switches, then load the mode only during reset
    reg [1:0] sw_s1 = 2'b00, sw_s2 = 2'b00;
    reg [1:0] mode_sw = 2'b00;               // defaults to one player at power-up

    always @(posedge clk) begin
        sw_s1 <= sw[1:0];
        sw_s2 <= sw_s1;
        if (reset) mode_sw <= sw_s2;         // locked while a round is running
    end

    wire ai_mode   = (mode_sw == 2'b10);
    wire p2_active = (mode_sw == 2'b01) || ai_mode;


    //Same setup as with buttons, direction + valid direction
    wire [1:0] player1_dir;
    wire [1:0] player2_dir;
    wire player1_valid,player2_valid;

        // AI outputs (tied off until ai_player exists)
    wire [1:0] ai_dir   = 2'b00;
    wire       ai_valid = 1'b0;

    // P2 steering mux
    wire [1:0] p2_dir   = ai_mode ? ai_dir   : player2_dir;
    wire       p2_valid = ai_mode ? ai_valid : player2_valid;

    //Player 1, hook up to joystick 1 
    PmodJSTK_Controller joy1 (
    .CLK(clk), .RST(reset),
    .jstk_clk(jstk_clk), .clk_poll(clk_poll),

    // To/from the physical joystick: top-level ports with XDC pins
    .SS(JA_SS), .MOSI(JA_MOSI), .MISO(JA_MISO), .SCLK(JA_SCLK),

    // To the game: internal wires
    .dir(player1_dir), .valid(player1_valid)
);

    //Player 2 
    PmodJSTK_Controller joy2 (
    .CLK(clk), .RST(reset),
    .jstk_clk(jstk_clk), .clk_poll(clk_poll),

    // To/from the physical joystick: top-level ports with XDC pins
    .SS(JB_SS), .MOSI(JB_MOSI), .MISO(JB_MISO), .SCLK(JB_SCLK),

    // To the game: internal wires
    .dir(player2_dir), .valid(player2_valid)
);

    // move_fsm split into game_fsm and player
    //  Renamed 
    //   game_fsm: game timing, RAM access, collisions, and crashed/alive/winner
    //   player:   legal direction, current position, and next position
    // Player outputs
    wire [6:0] p1_px, p1_nx, p2_px, p2_nx;       // X: 7 bits (0..79)
    wire [5:0] p1_py, p1_ny, p2_py, p2_ny;       // Y: 6 bits (0..59)
    wire [1:0] p1_cur_dir, p2_cur_dir;

    // From game_fsm to both players
    wire step, commit;
    // P1 uses the defaults: (10, 30), heading RIGHT
    player p1 (
        .clk(clk), .reset(reset), .step(step), .commit(commit),
        .dir_in(player1_dir), .dir_valid(player1_valid),
        .px(p1_px), .py(p1_py), .nx(p1_nx), .ny(p1_ny), .cur_dir(p1_cur_dir)
    );

    // P2: same module, different starting values
    // P2; should start opposing to player 1
    player #(.START_X(7'd69), .START_Y(6'd30), .START_DIR(2'b11)) p2 (
        .clk(clk), .reset(reset), .step(step), .commit(commit),
        .dir_in(p2_dir), .dir_valid(p2_valid),
        .px(p2_px), .py(p2_py), .nx(p2_nx), .ny(p2_ny), .cur_dir(p2_cur_dir)
    );
    // 8. game_fsm
    wire       mv_we, alive, p1_crashed, p2_crashed;
    wire [6:0] mv_x;
    wire [5:0] mv_y;
    wire [1:0] mv_din, ram_dout_a;

    // Tied off until ai_player exists
    wire       ai_start;
    wire       ai_done = 1'b1;       // must be 1, or AI mode freezes
    wire [6:0] ai_x    = 7'd0;
    wire [5:0] ai_y    = 6'd0;
    

    game_fsm referee (
        .clk(clk), .reset(reset), .go(clr_done),
        .p2_active(p2_active), .ai_mode(ai_mode),

        .p1_nx(p1_nx), .p1_ny(p1_ny),
        .p2_nx(p2_nx), .p2_ny(p2_ny),
        .step(step), .commit(commit),

        .ai_start(ai_start), .ai_done(ai_done),
        .ai_x(ai_x), .ai_y(ai_y),

        .we(mv_we), .ax(mv_x), .ay(mv_y),
        .din(mv_din), .dout(ram_dout_a),

        .alive(alive), .p1_crashed(p1_crashed), .p2_crashed(p2_crashed)
    );

    wire crashed = p1_crashed || p2_crashed;   // keeps your red walls and LED working

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
