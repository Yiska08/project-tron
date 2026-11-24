`timescale 1ns / 1ps
// move_fsm (Mode 1, one cycle): every game tick, move one cell in the current
// direction. If the next cell is not empty -> crash. Otherwise paint it as P1 trail.
//
// States:  IDLE  -> wait for grid_clear to finish, paint the start cell
//          WAIT  -> wait for a game tick, compute the next cell
//          READ  -> next-cell address is on the RAM port (RAM needs 1 clk to answer)
//          CHECK -> look at what is in the next cell: empty = move + paint, else crash
//          DEAD  -> stop until reset (btnC)
module move_fsm #(
    parameter TICK_DIV = 24'd8_333_333   // 100 MHz / 8,333,333 = 12 moves per second
)(
    input            clk,
    input            reset,
    input            go,          // 1-clk pulse: grid is cleared, start the round
    input      [1:0] dir_in,      // from btn_dir (later: joystick)
    input            dir_valid,
    // grid_ram port A
    output           we,
    output     [6:0] ax,
    output     [5:0] ay,
    output     [1:0] din,
    input      [1:0] dout,
    // status
    output           alive,
    output           crashed
);
    localparam S_IDLE  = 3'd0,
               S_WAIT  = 3'd1,
               S_READ  = 3'd2,
               S_CHECK = 3'd3,
               S_DEAD  = 3'd4;

    reg [2:0] state;
    reg [6:0] px, nx;          // current / next X
    reg [5:0] py, ny;          // current / next Y
    reg [1:0] cur_dir;         // direction we actually moved last tick
    reg [1:0] next_dir;        // direction requested for the next tick

    // ---------------- game tick (1-clk pulse, TICK_DIV clks apart) ----------------
    reg [23:0] tick_cnt;
    wire game_tick = (tick_cnt == TICK_DIV - 1);
    always @(posedge clk) begin
        if (reset || game_tick) tick_cnt <= 24'd0;
        else                    tick_cnt <= tick_cnt + 24'd1;
    end

    // ---------------- direction latch with no-reverse rule ----------------
    // Opposite direction = flip the top bit (UP 00 <-> DOWN 10, RIGHT 01 <-> LEFT 11)
    always @(posedge clk) begin
        if (reset)
            next_dir <= 2'b01;                                   // start heading RIGHT
        else if (dir_valid && dir_in != (cur_dir ^ 2'b10))
            next_dir <= dir_in;
    end

    // ---------------- main FSM ----------------
    always @(posedge clk) begin
        if (reset) begin
            state   <= S_IDLE;
            px      <= 7'd10;                                    // start position
            py      <= 6'd30;
            nx      <= 7'd10;
            ny      <= 6'd30;
            cur_dir <= 2'b01;
        end else begin
            case (state)
                S_IDLE:  if (go) state <= S_WAIT;                // start cell painted below
                S_WAIT:  if (game_tick) begin
                             cur_dir <= next_dir;
                             case (next_dir)
                                 2'b00: begin nx <= px;         ny <= py - 6'd1; end
                                 2'b01: begin nx <= px + 7'd1;  ny <= py;        end
                                 2'b10: begin nx <= px;         ny <= py + 6'd1; end
                                 2'b11: begin nx <= px - 7'd1;  ny <= py;        end
                             endcase
                             state <= S_READ;
                         end
                S_READ:  state <= S_CHECK;                       // RAM answers next clk
                S_CHECK: if (dout != 2'b00) state <= S_DEAD;     // wall or trail -> crash
                         else begin
                             px    <= nx;                        // move (cell painted below)
                             py    <= ny;
                             state <= S_WAIT;
                         end
                S_DEAD:  state <= S_DEAD;                        // stay until btnC
                default: state <= S_IDLE;
            endcase
        end
    end

    // ---------------- RAM port A outputs ----------------
    assign ax  = (state == S_IDLE) ? px : nx;
    assign ay  = (state == S_IDLE) ? py : ny;
    assign din = 2'b01;                                          // P1 trail (cyan)
    assign we  = (state == S_IDLE  && go) ||                     // paint start cell
                 (state == S_CHECK && dout == 2'b00);            // paint new cell

    assign alive   = (state == S_WAIT) || (state == S_READ) || (state == S_CHECK);
    assign crashed = (state == S_DEAD);
endmodule
