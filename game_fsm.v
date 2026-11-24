`timescale 1ns / 1ps
// game_fsm: the referee. One instance for the whole game.
//   - runs the game tick
//   - owns grid_ram port A (after grid_clear is finished)
//   - checks both next cells BEFORE painting either one, so collisions are fair
//   - paints trails and reports who crashed
// It never sees a joystick: each player module turns directions into nx/ny.
//
// One move:
//   WAIT -> (AI) -> STEP -> READ1 -> CHECK1 -> READ2 -> CHECK2 -> RESOLVE
//        -> WRITE1 -> WRITE2 -> WAIT        (or RESOLVE -> OVER on a crash)
module game_fsm #(
    parameter [23:0] TICK_DIV = 24'd8_333_333   // 100 MHz / 8,333,333 = 12 moves per second
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       go,            // 1-clk pulse: grid is cleared, start the round
    input  wire       p2_active,     // 0 = one-player mode, P2 is ignored
    input  wire       ai_mode,       // 1 = wait for the AI before each move

    // Players
    input  wire [6:0] p1_nx, p2_nx,  // cell each player wants (start cell after reset)
    input  wire [5:0] p1_ny, p2_ny,
    output wire       step,          // 1-clk pulse: compute your next cell
    output wire       commit,        // 1-clk pulse: nobody crashed, make the move

    // AI (borrows port A while it is choosing)
    output wire       ai_start,      // 1-clk pulse: choose a direction
    input  wire       ai_done,       // direction is ready
    input  wire [6:0] ai_x,          // cell the AI wants to look at
    input  wire [5:0] ai_y,

    // grid_ram port A
    output wire       we,
    output reg  [6:0] ax,
    output reg  [5:0] ay,
    output wire [1:0] din,
    input  wire [1:0] dout,

    // Status
    output wire       alive,         // a round is being played
    output reg        p1_crashed,    // both crashed = draw
    output reg        p2_crashed
);
    localparam [3:0] S_IDLE    = 4'd0,   // wait for grid_clear
                     S_SPAWN1  = 4'd1,   // paint P1's start cell
                     S_SPAWN2  = 4'd2,   // paint P2's start cell
                     S_WAIT    = 4'd3,   // wait for the game tick
                     S_AI      = 4'd4,   // AI is choosing
                     S_STEP    = 4'd5,   // players compute nx/ny
                     S_READ1   = 4'd6,   // P1's next cell is on the RAM address
                     S_CHECK1  = 4'd7,   // dout = P1's next cell
                     S_READ2   = 4'd8,   // P2's next cell is on the RAM address
                     S_CHECK2  = 4'd9,   // dout = P2's next cell
                     S_RESOLVE = 4'd10,  // who crashed?
                     S_WRITE1  = 4'd11,  // paint P1's trail
                     S_WRITE2  = 4'd12,  // paint P2's trail, commit the move
                     S_OVER    = 4'd13;  // hold the result until reset

    localparam [1:0] EMPTY    = 2'b00,
                     P1_TRAIL = 2'b01,
                     P2_TRAIL = 2'b10;

    reg [3:0] state;
    reg       p1_hit, p2_hit;

    // ---------------- game tick (1-clk pulse, TICK_DIV clks apart) ----------------
    reg [23:0] tick_cnt;
    wire game_tick = (tick_cnt == TICK_DIV - 24'd1);
    always @(posedge clk) begin
        if (reset || game_tick) tick_cnt <= 24'd0;
        else                    tick_cnt <= tick_cnt + 24'd1;
    end

    // ---------------- who crashed ----------------
    // Every P2 term is gated by p2_active so an unused P2 can't affect the game
    wire head_on  = p2_active && (p1_nx == p2_nx) && (p1_ny == p2_ny);
    wire p1_crash = p1_hit || head_on;
    wire p2_crash = p2_active && (p2_hit || head_on);

    // ---------------- main FSM ----------------
    always @(posedge clk) begin
        if (reset) begin
            state      <= S_IDLE;
            p1_hit     <= 1'b0;
            p2_hit     <= 1'b0;
            p1_crashed <= 1'b0;
            p2_crashed <= 1'b0;
        end else begin
            case (state)
                S_IDLE:    if (go) state <= S_SPAWN1;
                S_SPAWN1:  state <= S_SPAWN2;
                S_SPAWN2:  state <= S_WAIT;
                S_WAIT:    if (game_tick) state <= ai_mode ? S_AI : S_STEP;
                S_AI:      if (ai_done) state <= S_STEP;
                S_STEP:    state <= S_READ1;
                S_READ1:   state <= S_CHECK1;                // RAM answers next clk
                S_CHECK1:  begin
                               p1_hit <= (dout != EMPTY);
                               state  <= S_READ2;
                           end
                S_READ2:   state <= S_CHECK2;
                S_CHECK2:  begin
                               p2_hit <= (dout != EMPTY);
                               state  <= S_RESOLVE;
                           end
                S_RESOLVE: begin
                               p1_crashed <= p1_crash;
                               p2_crashed <= p2_crash;
                               state <= (p1_crash || p2_crash) ? S_OVER : S_WRITE1;
                           end
                S_WRITE1:  state <= S_WRITE2;
                S_WRITE2:  state <= S_WAIT;
                S_OVER:    state <= S_OVER;                  // stay until btnC
                default:   state <= S_IDLE;
            endcase
        end
    end

    // ---------------- pulses to the players and AI ----------------
    assign step     = (state == S_STEP);
    assign commit   = (state == S_WRITE2);
    assign ai_start = (state == S_WAIT) && game_tick && ai_mode;

    // ---------------- RAM port A ----------------
    wire p2_turn = (state == S_SPAWN2) || (state == S_READ2) ||
                   (state == S_CHECK2) || (state == S_WRITE2);

    always @(*) begin
        if (state == S_AI) begin
            ax = ai_x;   ay = ai_y;
        end else if (p2_turn) begin
            ax = p2_nx;  ay = p2_ny;
        end else begin
            ax = p1_nx;  ay = p1_ny;
        end
    end

    assign din = p2_turn ? P2_TRAIL : P1_TRAIL;
    assign we  = (state == S_SPAWN1) || (state == S_WRITE1) ||
                 (p2_active && (state == S_SPAWN2 || state == S_WRITE2));

    // ---------------- status ----------------
    assign alive = (state != S_IDLE) && (state != S_SPAWN1) &&
                   (state != S_SPAWN2) && (state != S_OVER);
endmodule
