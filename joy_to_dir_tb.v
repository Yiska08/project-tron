`timescale 1ns / 1ps
// Testbench for joy_to_dir
//
// Three ways to drive the stick (all decimal, pick whichever is easiest):
//   push       (LEFT, 300)               -> direction + magnitude from center, expected result computed for you
//   move       (dx, dy, exp_valid, exp_dir)  -> signed offset from center (e.g. -300, +150)
//   move_raw   (x, y,   exp_valid, exp_dir)  -> raw 10-bit ADC values (0..1023), like the Pmod sends
//
// Every check prints one line, e.g.
//   [12] X input =  212 (dx= -300), Y input =  512 (dy=    0) | dir=11 valid=1 | result = LEFT  expected = LEFT  PASS
module joy_to_dir_tb;

    // ---------------- Encodings ----------------
    localparam [1:0] UP = 2'd0, RIGHT = 2'd1, DOWN = 2'd2, LEFT = 2'd3;
    localparam       NONE = 1'b0, VALID = 1'b1;    // expected 'valid'
    localparam integer DZ = 200;                   // must match DEADZONE below

    // ---------------- DUT signals ----------------
    reg         clk = 1'b0;
    always #5 clk = ~clk;                          // 100 MHz (DUT ignores it, but the port exists)

    reg  [39:0] jstkData = 40'd0;
    wire [1:0]  dir,   dir_inv;
    wire        valid, valid_inv;

    // Normal orientation
    joy_to_dir #(.DEADZONE(DZ)) dut (
        .clk(clk), .jstkData(jstkData), .dir(dir), .valid(valid)
    );

    // Both axes inverted (checks INVERT_X / INVERT_Y)
    joy_to_dir #(.DEADZONE(DZ), .INVERT_X(1'b1), .INVERT_Y(1'b1)) dut_inv (
        .clk(clk), .jstkData(jstkData), .dir(dir_inv), .valid(valid_inv)
    );

    integer test_num   = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // ---------------- Helpers ----------------
    function [8*5-1:0] dir_name(input [1:0] d);
        case (d)
            UP:      dir_name = "UP";
            RIGHT:   dir_name = "RIGHT";
            DOWN:    dir_name = "DOWN";
            default: dir_name = "LEFT";
        endcase
    endfunction

    // Builds the 5-byte PmodJSTK packet exactly as the SPI controller would store it:
    //   [39:32] X low | [31:24] 000000,X[9:8] | [23:16] Y low | [15:8] 000000,Y[9:8] | [7:0] buttons
    task pack(input [9:0] x, input [9:0] y);
        begin
            jstkData = {x[7:0], 6'b000000, x[9:8],
                        y[7:0], 6'b000000, y[9:8],
                        8'h00};
        end
    endtask

    // Core check: raw ADC values in, compare against expected, print one line.
    task check(input integer x_in, input integer y_in, input inv,
               input exp_valid, input [1:0] exp_dir);
        integer x, y;
        reg       got_valid;
        reg [1:0] got_dir;
        reg       ok;
        begin
            x = x_in;  y = y_in;
            if (x < 0)    begin $display("  NOTE: X=%0d clamped to 0",    x); x = 0;    end
            if (x > 1023) begin $display("  NOTE: X=%0d clamped to 1023", x); x = 1023; end
            if (y < 0)    begin $display("  NOTE: Y=%0d clamped to 0",    y); y = 0;    end
            if (y > 1023) begin $display("  NOTE: Y=%0d clamped to 1023", y); y = 1023; end

            pack(x[9:0], y[9:0]);
            #10;                                   // let combinational logic settle

            got_valid = inv ? valid_inv : valid;
            got_dir   = inv ? dir_inv   : dir;

            // dir is only meaningful when valid=1, so only compare it then
            ok = (got_valid == exp_valid) && (!exp_valid || got_dir == exp_dir);

            test_num = test_num + 1;
            if (ok) pass_count = pass_count + 1;
            else    fail_count = fail_count + 1;

            $display("[%0d]%s X input = %4d (dx=%5d), Y input = %4d (dy=%5d) | dir=%b valid=%b | result = %0s  expected = %0s  %0s",
                     test_num, inv ? " (INV)" : "",
                     x, x - 512, y, y - 512,
                     got_dir, got_valid,
                     got_valid ? dir_name(got_dir) : "NONE",
                     exp_valid ? dir_name(exp_dir) : "NONE",
                     ok ? "PASS" : "<<<<< FAIL");
        end
    endtask

    // Raw 10-bit values (0..1023)
    task move_raw(input integer x, input integer y, input exp_valid, input [1:0] exp_dir);
        check(x, y, 1'b0, exp_valid, exp_dir);
    endtask

    // Signed decimal offset from center (512)
    task move(input integer dx, input integer dy, input exp_valid, input [1:0] exp_dir);
        check(512 + dx, 512 + dy, 1'b0, exp_valid, exp_dir);
    endtask

    // Same as move, but checks the inverted DUT
    task move_inv(input integer dx, input integer dy, input exp_valid, input [1:0] exp_dir);
        check(512 + dx, 512 + dy, 1'b1, exp_valid, exp_dir);
    endtask

    // Direction + decimal magnitude. Expected result is computed automatically:
    // valid only if magnitude > DZ, and dir should equal the direction pushed.
    task push(input [1:0] d, input integer mag);
        integer dx, dy;
        begin
            dx = 0; dy = 0;
            case (d)
                UP:    dy =  mag;
                DOWN:  dy = -mag;
                RIGHT: dx =  mag;
                LEFT:  dx = -mag;
            endcase
            check(512 + dx, 512 + dy, 1'b0, (mag > DZ), d);
        end
    endtask

    // ---------------- Test sequence ----------------
    initial begin
        $display("==== joy_to_dir testbench  (DEADZONE = %0d, center = 512) ====", DZ);
        $display("dir: 00=UP 01=RIGHT 10=DOWN 11=LEFT, result=NONE when valid=0");

        $display("\n--- Centered ---");
        move(   0,    0, NONE,  UP);

        $display("\n--- Inside deadzone (should be NONE) ---");
        push(RIGHT, 150);
        push(LEFT,  150);
        push(UP,    150);
        push(DOWN,  150);
        move( 150,  150, NONE,  UP);               // diagonal, both small
        move(-199,  199, NONE,  UP);               // just under on both axes

        $display("\n--- Deadzone boundary (must be > %0d to count) ---", DZ);
        push(RIGHT, 200);                          // exactly DZ -> NONE
        push(RIGHT, 201);                          // DZ+1       -> RIGHT
        push(DOWN,  200);
        push(DOWN,  201);

        $display("\n--- Outside deadzone, straight pushes ---");
        push(LEFT,  300);
        push(UP,    300);
        push(RIGHT, 511);                          // full right (X=1023)
        push(LEFT,  512);                          // full left  (X=0)
        push(UP,    511);                          // full up    (Y=1023)
        push(DOWN,  512);                          // full down  (Y=0)

        $display("\n--- Diagonal, one axis dominant (bigger axis wins) ---");
        move( 300,  100, VALID, RIGHT);
        move(-100,  300, VALID, UP);
        move( 250, -400, VALID, DOWN);
        move( 100, -250, VALID, DOWN);             // X inside DZ, Y outside
        move( 201,  200, VALID, RIGHT);            // dominant by just 1

        $display("\n--- Equal magnitude ties (adx == ady -> Y axis wins) ---");
        move( 300,  300, VALID, UP);
        move(-300, -300, VALID, DOWN);
        move( 300, -300, VALID, DOWN);
        move(-300,  300, VALID, UP);

        $display("\n--- Physical corners (raw ADC values) ---");
        move_raw(1023, 1023, VALID, UP);           // dx=+511, dy=+511 -> tie -> UP
        move_raw(   0,    0, VALID, DOWN);         // dx=-512, dy=-512 -> tie -> DOWN
        move_raw(1023,    0, VALID, DOWN);         // |dy|=512 > |dx|=511     -> DOWN
        move_raw(   0, 1023, VALID, LEFT);         // |dx|=512 > |dy|=511     -> LEFT

        $display("\n--- INVERT_X=1, INVERT_Y=1 (same raw input, opposite result) ---");
        move_inv( 300,    0, VALID, LEFT);
        move_inv(-300,    0, VALID, RIGHT);
        move_inv(   0,  300, VALID, DOWN);
        move_inv(   0, -300, VALID, UP);
        move_inv( 150,    0, NONE,  UP);           // deadzone unaffected by inversion

        $display("\n==== DONE: %0d tests, %0d passed, %0d failed ====",
                 test_num, pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
