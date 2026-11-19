// Clock Divider (tick generator)
// Master Clock Input (100 MHz) --> Clock Module --> Output: pix_en       25 MHz  (VGA pixel enable)
//                                                     -->   spi_tick    200 kHz  (SPI half-period -> 100 kHz SCLK)
//                                                     -->   seg_tick      1 kHz  (7-seg digit refresh)
//                                                     -->   debounce_tick 1 kHz  (button/joystick sampling)
//
// All outputs are ONE-CYCLE pulses (enables), not clocks.
// Use them as:  always @(posedge clk) if (pix_en) ...
// Never use them as:  always @(posedge pix_en)
// Tick rate = 100 MHz / dv
`timescale 1ns / 1ps

module clock(
    input      RESET,           // synchronous, active high (synchronize the button first)
    input      clk,             // 100 MHz master clock
    output reg pix_en,          // 25 MHz  -> VGA pixel enable
    output reg jstk_clk      = 0,   // 66.67 kHz square wave -> Digilent PmodJSTK clock
    output reg seg_tick,        // 1 kHz   -> 7-seg display multiplexing/refresh
    output reg debounce_tick,    // 1 kHz   -> button/joystick debounce sampling
    output reg clk_5hz
);


// 25 MHz pixel enable
reg [1:0] ctrp = 0;
parameter dvp = 4;
//parameter dvp = 3'd4;         // same in simulation

//66.67 Khz
reg [9:0] ctrs = 0;
parameter dvs = 750;

// 7-seg refresh (1 kHz)
reg [16:0] ctrg = 0;
parameter dvg = 100_000;
//parameter dvg = 17'd10;       // fast, for simulation

// Debounce sampling (1 kHz)
reg [16:0] ctrd = 0;
parameter dvd = 100_000;
//parameter dvd = 17'd10;       // fast, for simulation


//100 MHz -> 25 MHz pixel enable
always @(posedge clk) begin
    if (RESET) begin
        ctrp   <= 0;
        pix_en <= 0;
    end else if (ctrp == dvp - 1) begin
        ctrp   <= 0;
        pix_en <= 1;
    end else begin
        ctrp   <= ctrp + 1;
        pix_en <= 0;
    end
end
// Value to toggle output clock at
    parameter cntEndVal = 24'h989680;
    // Current count
    reg [23:0] clkCount = 24'h000000;
    //-------------------------------------------------
    //  5Hz Clock Divider Generates Send/Receive signal
    //-------------------------------------------------
    always @(posedge clk) begin

            // Reset clock
            if(RESET == 1'b1) begin
                    clk_5hz <= 1'b0;
                    clkCount <= 24'h000000;
            end
            else begin

                    if(clkCount == cntEndVal) begin
                            clk_5hz <= ~clk_5hz;
                            clkCount <= 24'h000000;
                    end
                    else begin
                            clkCount <= clkCount + 1'b1;
                    end

            end

    end



//jstk_clk
always @(posedge clk) begin
    if (RESET) begin
        ctrs     <= 0;
        jstk_clk <= 0;
    end else if (ctrs == dvs - 1) begin
        ctrs     <= 0;
        jstk_clk <= ~jstk_clk;
    end else begin
        ctrs     <= ctrs + 1;
    end
end


//100 MHz -> 1 kHz 7-seg refresh tick
always @(posedge clk) begin
    if (RESET) begin
        ctrg     <= 0;
        seg_tick <= 0;
    end else if (ctrg == dvg - 1) begin
        ctrg     <= 0;
        seg_tick <= 1;
    end else begin
        ctrg     <= ctrg + 1;
        seg_tick <= 0;
    end
end


//100 MHz -> 1 kHz debounce tick
always @(posedge clk) begin
    if (RESET) begin
        ctrd          <= 0;
        debounce_tick <= 0;
    end else if (ctrd == dvd - 1) begin
        ctrd          <= 0;
        debounce_tick <= 1;
    end else begin
        ctrd          <= ctrd + 1;
        debounce_tick <= 0;
    end
end

endmodule