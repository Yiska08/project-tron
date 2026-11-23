`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Digilent Inc.
// Engineer: Josh Sackos
// 
// Create Date:    07/11/2012
// Module Name:    PmodJSTK_Controller
// Project Name: 	 PmodJSTK_Controller
// Target Devices: Nexys3
// Tool versions:  ISE 14.1
// Description: This is a demo for the Digilent PmodJSTK modified for Tron game use. Data is sent and received
//					 to and from the PmodJSTK at a frequency of 100 Hz. The positional
//					 data of the joystick ranges from 0 to 1023 in both the X and Y
//					 directions. There is then a joy_to_dir module that will apply dead zones and 
//				     convert the joystick ranges to the actual directions used for the game.
//
//				
// dir: 00=Up 01=Right 10=Down 11=Left    valid=1 only when stick is pushed past dead zone
// Valid bit: If direction is valid -> game should decide to switch if not game should do same direction
//
// Revision History: 
// 						Revision 0.01 - File Created (Josh Sackos)
//						Revision 0.02 - Renamed File and using the Demo for tron light cycle project (Chatwin Ho)
//////////////////////////////////////////////////////////////////////////////////


// ============================================================================== 
// 										  Define Module
// ==============================================================================
module PmodJSTK_Controller(
    CLK,
	clk_poll,
	jstk_clk,
    RST,
    MISO,
    SS,
    MOSI,
    SCLK,
	dir,
	valid
    );

	// ===========================================================================
	// 										Port Declarations
	// ===========================================================================
			input clk_poll;
			input jstk_clk;
			//Tron game Additions

			input CLK;					// 100Mhz onboard clock
			input RST;					// RST
			input MISO;					// Master In Slave Out, Dependent on player Pmod
			output SS;					// Slave Select, 
			output MOSI;				// Master Out Slave 
			output SCLK;				// Serial Clock, 
			//Added directional output
			output [1:0] dir; //Direction of joystick
			output valid; //give to game whether joystick command is valid. 


	// ===========================================================================
	// 							  Parameters, Regsiters, and Wires
	// ===========================================================================
			wire SS;						// Active low
			wire MOSI;					// Data transfer from master to slave
			wire SCLK;					// Serial clock that controls communication

			// Signal to send/receive data to/from PmodJSTK

			wire sndRec = clk_poll; // TRON Updated to receive clock from clock.v

			// Data read from PmodJSTK
			wire [39:0] jstkData;
			wire [7:0]  sndData = 8'b1000_0000;   // first byte: joystick LEDs off
	// ===========================================================================
	// 										Implementation
	// ===========================================================================


			//-----------------------------------------------
			//  	  			PmodJSTK Interface
			//-----------------------------------------------
			PmodJSTK PmodJSTK_Int(
					.CLK(CLK),
					.jstk_clk(jstk_clk),
					.RST(RST),
					.sndRec(sndRec),
					.DIN(sndData),
					.MISO(MISO),
					.SS(SS),
					.SCLK(SCLK),
					.MOSI(MOSI),
					.DOUT(jstkData)
			);
			


			
			joy_to_dir JoyCtrl(
				.clk(CLK),
				.jstkData(jstkData),
				.dir(dir),
		        .valid(valid)
			);

endmodule
