# Light Cycle (Tron) on the Basys 3

A hardware version of the Tron light-cycle game, written in Verilog for the Digilent Basys 3 (Artix-7) FPGA and shown on a VGA monitor at 640 x 480, 60 Hz.

CS M152A Lab 4 final project by Chatwin Ho and Graciela Yiska Anastasia.

## The game

Each player steers a light cycle that moves one cell per game tick and leaves a permanent trail. A cycle crashes when its next cell is a wall or any trail. The playfield is a 40 x 30 grid of 16 x 16-pixel cells with a wall border.

| Mode | SW1 SW0 | Description |
| --- | --- | --- |
| 1: Single-player | `00` | Survive as long as possible. The game speeds up over time. Score = ticks survived. |
| 2: Two-player | `01` | Two joysticks, last cycle moving wins the round. First to 5 round wins takes the match. |
| 3: Player vs. AI (optional) | `10` | Player 2 is a hardware AI. SW2 selects Easy (0) or Hard (1). |

Rules:

- A cycle can never reverse directly.
- If both cycles crash on the same tick, including moving into the same empty cell, the round is a draw and nobody scores.
- The grid clears after every round. Press BTNC to start the next one.

## Controls and outputs

| Board item | Use |
| --- | --- |
| Pmod joystick on JA | Player 1 direction (SPI) |
| Pmod joystick on JB | Player 2 direction (Mode 2) |
| BTNU, BTND, BTNL, BTNR | Backup direction input for Player 1 |
| BTNC | Start the round / next round |
| SW1, SW0 | Mode select |
| SW2 | AI difficulty (Mode 3) |
| SW15 | Reset scores and match |
| VGA port | Game display |
| Seven-segment display | Mode 1: ticks survived. Modes 2 and 3: P1 score (left two digits), P2 or AI score (right two digits) |
| LEDs | Mode, round result, match winner |

## Hardware and software

- Digilent Basys 3 board and micro-USB cable
- Monitor with a VGA input and a VGA cable (an HDMI-only monitor needs an active VGA-to-HDMI converter)
- Two Digilent Pmod JSTK2 joysticks (one is enough for Mode 1)
- Xilinx Vivado with its built-in simulator
- Digilent `Basys-3-Master.xdc` constraints file

## Module overview

| Module | Role | Logic type |
| --- | --- | --- |
| `top` | Connects all modules to the board pins | Structural |
| `pixel_clk_en` | One-cycle pulse every 4th 100 MHz clock (25 MHz pixel enable) | Sequential |
| `vga_sync` | hcount (0-799), vcount (0-524), HSYNC, VSYNC, video_on | Sequential counters, combinational decode |
| `grid_ram` | 1,200 cells x 2 bits, dual port (renderer reads, game reads and writes) | Sequential |
| `renderer` | Maps the current pixel to a cell and outputs its 12-bit color | Combinational with output registers |
| `grid_clear` | Writes walls on the border and empty inside between rounds | Sequential FSM |
| `tick_gen` | Game tick (8 per second at start), speeds up in Mode 1 | Sequential |
| `spi_master` (x2) | Reads X/Y from each joystick | Sequential FSM |
| `joy_decode` | X/Y to a direction with a dead zone | Combinational |
| `input_ctrl` | Synchronizes and debounces buttons and switches | Sequential |
| `move_fsm` | Next cells, crash and draw resolution, trail writes | Sequential FSM |
| `game_fsm` | Mode, round state, scores, match winner | Sequential FSM |
| `ai_ctrl` (optional) | Lookahead AI that drives Player 2 in Mode 3 | Sequential FSM |
| `seg_display` | Seven-segment multiplexing (reused from Lab 3) | Sequential and combinational |

### Grid cell encoding

| Code | Meaning | Color |
| --- | --- | --- |
| `00` | Empty | Black |
| `01` | Player 1 trail | Cyan |
| `10` | Player 2 / AI trail | Orange |
| `11` | Wall | White |

Cell address = `cell_y * 40 + cell_x`, where `cell_x = hcount[9:4]` and `cell_y = vcount[9:4]`.

## VGA timing (640 x 480 at 60 Hz, 25 MHz pixel rate)

| Counter | Visible | Front porch | Sync pulse | Back porch | Total |
| --- | --- | --- | --- | --- | --- |
| hcount | 0-639 | 640-655 | 656-751 (low) | 752-799 | 800 |
| vcount | 0-479 | 480-489 | 490-491 (low) | 492-524 | 525 |

The color output must be black whenever `video_on` is low. Expected periods in simulation: HSYNC every 32 µs, VSYNC every 16.8 ms.

## Joystick (Pmod JSTK2) SPI

- SPI mode 0, 1 MHz, MSB first, CS active low
- 5-byte packet: send `0x00` and four dummy bytes; X and Y each come back as 10-bit values (0 to 1023, center near 512)
- Wait at least 15 µs after CS goes low, 10 µs between bytes, 25 µs after CS goes high
- Plugs into pins 1-6 of JA or JB: CS, MOSI, MISO, SCK, GND, 3.3 V

## Build and run

1. Create a Vivado RTL project for part `xc7a35tcpg236-1` (Basys 3).
2. Add the Verilog sources and the XDC. In the XDC, uncomment the clock, switches, buttons, LEDs, seven-segment, VGA and JA/JB lines. Port names in `top` must match the XDC.
3. Simulate each module with its testbench before building.
4. Run Synthesis, Implementation and Generate Bitstream. Read every critical warning.
5. Open Hardware Manager, connect to the board and program the `.bit` file.
6. Connect the monitor and joysticks, choose a mode on SW1/SW0, and press BTNC.

## Project status

| Milestone | Rubric part | Status |
| --- | --- | --- |
| VGA output, grid rendering, clear | Part 1 (40%) | Not started |
| Joystick input and single-player | Part 2 (40%) | Not started |
| Two-player mode | Part 3 (20%) | Not started |
| Player vs. AI | Part 4 (0%, optional) | Not started |

## References

- Digilent Basys 3 Reference Manual (VGA port, Pmod pinout)
- Digilent Pmod JSTK2 Reference Manual (SPI protocol)
- Any externally sourced code is cited in the project report.
