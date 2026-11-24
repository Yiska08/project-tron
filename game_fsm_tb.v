`timescale 1ns / 1ps
// Testbench for game_fsm + two players + grid_ram (no VGA, joystick or grid_clear needed).
// Uses a short TICK_DIV so a whole round simulates quickly.
module game_fsm_tb;
    localparam [1:0] UP = 2'd0, RIGHT = 2'd1, DOWN = 2'd2, LEFT = 2'd3;
    localparam TICK = 40;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg        reset = 1'b1, go = 1'b0, p2_active = 1'b0, ai_mode = 1'b0;
    reg  [1:0] d1 = 0, d2 = 0;
    reg        v1 = 0, v2 = 0;
    reg        ai_done = 1'b1;
    reg  [6:0] ai_x = 0;
    reg  [5:0] ai_y = 0;

    // Simple stand-in for grid_clear
    reg        clr = 1'b0;
    reg  [6:0] clr_x = 0;
    reg  [5:0] clr_y = 0;
    wire [1:0] clr_din = (clr_x <= 1 || clr_x >= 78 || clr_y <= 1 || clr_y >= 58) ? 2'b11 : 2'b00;

    // Two copies of the game. A: P2 starts at X=69 (like top). B: P2 starts at X=70,
    // which lets both heads reach the SAME cell.
    genvar g;
    generate for (g = 0; g < 2; g = g + 1) begin : game
        wire       step, commit, ai_start, we, alive, c1, c2;
        wire [6:0] ax, p1x, p1nx, p2x, p2nx;
        wire [5:0] ay, p1y, p1ny, p2y, p2ny;
        wire [1:0] din, dout, dir1, dir2, unused_b;
        player p1 (.clk(clk), .reset(reset), .step(step), .commit(commit),
                   .dir_in(d1), .dir_valid(v1),
                   .px(p1x), .py(p1y), .nx(p1nx), .ny(p1ny), .cur_dir(dir1));
        player #(.START_X(g == 0 ? 7'd69 : 7'd70), .START_Y(6'd30), .START_DIR(2'b11))
               p2 (.clk(clk), .reset(reset), .step(step), .commit(commit),
                   .dir_in(d2), .dir_valid(v2),
                   .px(p2x), .py(p2y), .nx(p2nx), .ny(p2ny), .cur_dir(dir2));
        game_fsm #(.TICK_DIV(TICK)) fsm (
            .clk(clk), .reset(reset), .go(go), .p2_active(p2_active), .ai_mode(ai_mode),
            .p1_nx(p1nx), .p2_nx(p2nx), .p1_ny(p1ny), .p2_ny(p2ny),
            .step(step), .commit(commit),
            .ai_start(ai_start), .ai_done(ai_done), .ai_x(ai_x), .ai_y(ai_y),
            .we(we), .ax(ax), .ay(ay), .din(din), .dout(dout),
            .alive(alive), .p1_crashed(c1), .p2_crashed(c2));
        grid_ram ram (.clk(clk), .we_a(clr | we), .ax(clr ? clr_x : ax), .ay(clr ? clr_y : ay),
                      .din_a(clr ? clr_din : din), .dout_a(dout),
                      .vx(7'd0), .vy(6'd0), .dout_b(unused_b));
    end endgenerate

    integer tests = 0, fails = 0, i, n, gap;

    task check(input ok, input [8*60-1:0] name);
        begin
            tests = tests + 1;
            if (!ok) fails = fails + 1;
            $display("  %0s  %0s", ok ? "PASS" : "<<<< FAIL", name);
        end
    endtask

    function [1:0] cellA(input integer x, input integer y); cellA = game[0].ram.mem[y*80 + x]; endfunction
    function [1:0] cellB(input integer x, input integer y); cellB = game[1].ram.mem[y*80 + x]; endfunction

    // Count cells holding a given code in game A
    function integer countA(input [1:0] code);
        integer k;
        begin
            countA = 0;
            for (k = 0; k < 4800; k = k + 1)
                if (game[0].ram.mem[k] == code) countA = countA + 1;
        end
    endfunction

    // Reset, clear the grid, pulse go. Inputs change on negedge so there are no races.
    task new_round(input active, input ai);
        begin
            @(negedge clk);
            reset = 1; go = 0; v1 = 0; v2 = 0; p2_active = active; ai_mode = ai;
            ai_done = 1; ai_x = 0; ai_y = 0;
            repeat (3) @(negedge clk);
            reset = 0; clr = 1;
            for (i = 0; i < 4800; i = i + 1) begin
                clr_x = i % 80; clr_y = i / 80;
                @(negedge clk);
            end
            clr = 0; go = 1;
            @(negedge clk);
            go = 0;
            repeat (3) @(negedge clk);
        end
    endtask

    // Hold a stick for a few clocks between moves, then let go
    task stick1(input [1:0] d); begin d1 = d; v1 = 1; repeat (3) @(negedge clk); v1 = 0; end endtask
    task stick2(input [1:0] d); begin d2 = d; v2 = 1; repeat (3) @(negedge clk); v2 = 0; end endtask

    // Wait for a move in game A to finish (or for the round to end / time out)
    task one_move;
        begin
            n = 0;
            while (!game[0].commit && game[0].alive && n < 500) begin @(negedge clk); n = n + 1; end
            @(negedge clk);
        end
    endtask

    task run_to_end;                      // game A
        begin
            n = 0;
            while (game[0].alive && n < 100*TICK) begin @(negedge clk); n = n + 1; end
            repeat (5) @(negedge clk);
        end
    endtask

    task run_to_endB;
        begin
            n = 0;
            while (game[1].alive && n < 100*TICK) begin @(negedge clk); n = n + 1; end
            repeat (5) @(negedge clk);
        end
    endtask

    // Watchdog: a broken game could otherwise wait forever for a pulse
    initial begin
        #3_000_000;
        $display("<<<< FAIL  TIMEOUT: waited for something that never happened");
        $finish;
    end

    initial begin
        $display("--- One player: straight into the right wall ---");
        new_round(0, 0);
        check(cellA(10,30) == 1, "P1 start cell painted");
        check(cellA(69,30) == 0, "P2 start cell NOT painted");
        run_to_end;
        check(game[0].c1 && !game[0].c2, "only P1 crashed");
        check(cellA(77,30) == 1 && cellA(78,30) == 3, "trail reaches the wall, wall intact");
        check(countA(1) == 68, "P1 trail is exactly 68 cells");
        check(countA(2) == 0, "no P2 trail anywhere");
        run_to_endB;
        check(game[1].c1 && cellB(77,30) == 1, "passes through invisible P2 (head-on ignored)");

        $display("--- One player: turning ---");
        new_round(0, 0);
        one_move;
        check(game[0].p1x == 11 && game[0].p1y == 30, "moved right one cell");
        stick1(LEFT);  one_move;
        check(game[0].p1x == 12 && game[0].p1y == 30, "reversal rejected");
        stick1(UP);    one_move;
        check(game[0].p1x == 12 && game[0].p1y == 29, "turned up");
        stick1(LEFT);  one_move;
        check(game[0].p1x == 11 && game[0].p1y == 29, "turned left");
        stick1(DOWN);  one_move;
        check(game[0].c1 && game[0].p1x == 11 && game[0].p1y == 29, "hit own trail, did not move into it");

        $display("--- Direction change exactly on the step cycle ---");
        new_round(0, 0);
        one_move;
        stick1(UP);
        while (!game[0].step) @(negedge clk);
        d1 = DOWN; v1 = 1; @(negedge clk); v1 = 0;      // legal vs RIGHT, reversal vs UP
        one_move; one_move;
        check(game[0].p1x == 11 && game[0].p1y == 28 && game[0].alive, "late reversal ignored, kept going up");

        $display("--- Stick moved mid-move ---");
        new_round(0, 0);
        one_move;
        while (!game[0].step) @(negedge clk);
        @(negedge clk);
        d1 = UP; v1 = 1; @(negedge clk); v1 = 0;
        one_move;
        check(game[0].p1x == 12 && game[0].p1y == 30, "current move unchanged");
        one_move;
        check(game[0].p1x == 12 && game[0].p1y == 29, "turn happens on the next move");

        $display("--- Two players: both straight ---");
        new_round(1, 0);
        check(cellA(10,30) == 1 && cellA(69,30) == 2, "both start cells painted");
        run_to_end;
        check(game[0].c1 && game[0].c2, "swap head-on is a draw");
        check(countA(1) == 30 && countA(2) == 30, "equal trail lengths");
        run_to_endB;
        check(game[1].c1 && game[1].c2, "same-cell head-on is a draw");
        check(cellB(39,30) == 1 && cellB(40,30) == 0 && cellB(41,30) == 2, "contested cell stays empty");

        $display("--- Two players: one crashes ---");
        new_round(1, 0);
        stick1(UP); run_to_end;
        check(game[0].c1 && !game[0].c2, "P1 hits top wall, P2 wins");
        new_round(1, 0);
        stick2(UP); run_to_end;
        check(!game[0].c1 && game[0].c2, "P2 hits top wall, P1 wins");
        i = game[0].p1x;
        repeat (5*TICK) @(negedge clk);
        check(game[0].p1x == i && !game[0].alive, "survivor stops after game over");
        new_round(1, 0);
        check(!game[0].c1 && !game[0].c2 && game[0].alive && countA(1) == 1 && countA(2) == 1,
              "reset starts a clean new round");

        $display("--- Two players: hitting the other trail ---");
        new_round(1, 0);
        // P2 turns up 1 cell then keeps going; P1 runs along row 30 into P2's old trail
        for (i = 0; i < 20; i = i + 1) one_move;
        stick2(UP);
        run_to_end;
        check(game[0].c1 && !game[0].c2 && game[0].p1x == 48, "P1 hit P2's trail at (49,30), P2 wins");

        $display("--- Player vs AI handshake ---");
        new_round(1, 1);
        ai_done = 0; ai_x = 0; ai_y = 30;
        n = 0;
        while (!game[0].ai_start && n < 200) begin @(negedge clk); n = n + 1; end
        check(game[0].ai_start, "ai_start pulses on the tick");
        gap = 0;
        for (i = 0; i < 10; i = i + 1) begin @(negedge clk); if (game[0].step || game[0].we) gap = gap + 1; end
        check(gap == 0, "no step or write while the AI is choosing");
        check(game[0].dout == 3, "AI can read a wall cell through port A");
        ai_x = 10; repeat (2) @(negedge clk);
        check(game[0].dout == 1, "AI can read a trail cell through port A");
        d2 = UP; v2 = 1; ai_done = 1; @(negedge clk); v2 = 0; ai_done = 0;
        n = 0;
        while (!game[0].commit && n < 50) begin @(negedge clk); n = n + 1; end
        @(negedge clk);
        check(game[0].p2x == 69 && game[0].p2y == 29, "AI choice used on that same move");
        new_round(1, 1);                                // ai_done tied to 1, no AI yet
        run_to_end;
        check(game[0].c1 && game[0].c2, "ai_done tied high: P2 drives straight, no hang");

        $display("--- Timing ---");
        new_round(1, 0);
        while (!game[0].step) @(negedge clk);
        gap = 0; @(negedge clk);
        while (!game[0].step) begin @(negedge clk); gap = gap + 1; end
        check(gap + 1 == TICK, "moves are exactly TICK_DIV clocks apart");

        $display("==== %0d checks, %0d failed ====", tests, fails);
        $finish;
    end
endmodule
