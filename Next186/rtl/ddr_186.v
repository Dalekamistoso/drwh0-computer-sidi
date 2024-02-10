//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: ddr_186.v
// Description: Part of the Next186 SoC PC project, main system, RAM interface
// Version 2.0
// Creation date: Apr2014
//
// Author: Nicolae Dumitrache 
// e-mail: ndumitrache@opencores.org
//
/////////////////////////////////////////////////////////////////////////////////
// 
// Copyright (C) 2012 Nicolae Dumitrache
// 
// This source file may be used and distributed without 
// restriction provided that this copyright statement is not 
// removed from the file and that any derivative work contains 
// the original copyright notice and the associated disclaimer.
// 
// This source file is free software; you can redistribute it 
// and/or modify it under the terms of the GNU Lesser General 
// Public License as published by the Free Software Foundation;
// either version 2.1 of the License, or (at your option) any 
// later version. 
// 
// This source is distributed in the hope that it will be 
// useful, but WITHOUT ANY WARRANTY; without even the implied 
// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR 
// PURPOSE. See the GNU Lesser General Public License for more 
// details. 
// 
// You should have received a copy of the GNU Lesser General 
// Public License along with this source; if not, download it 
// from http://www.opencores.org/lgpl.shtml 
// 
///////////////////////////////////////////////////////////////////////////////////
// Additional Comments: 
//
// 25Apr2012 - added SD card SPI support
// 15May2012 - added PIT 8253 (sound + timer INT8)
// 24May2012 - added PIC 8259  
// 28May2012 - RS232 boot loader does not depend on CPU speed anymore (uses timer0)
//	01Feb2013 - ADD 8042 PS2 Keyboard & Mouse controller
// 27Feb2013 - ADD RTC
// 04Apr2013 - ADD NMI, port 3bc for 8 leds
//
// Feb2014 - ported for SDRAM, added USB host serial communication
// 		   - added video modes 0dh, 12h
//		   - support for ModeX
// Jul2017 - high speed COM (up to 115200*8)
// Aug2017 - added Line Compare Register
// Sep2017 - VGA barrel shifter, NMI on IRQ
// Oct2017 - added VGA VDE register, improved 400/480 lines configuration based on VDE
//////////////////////////////////////////////////////////////////////////////////

/* ----------------- implemented ports -------------------
0001 - BYTE write: bit01=ComSel (00=DCE, 01=EXT, 1x=HOST), bit2=Host reset, bit43=COM divider shift right bits
	  
0002 - 32 bit CPU data port R/W, lo first
0003 - 32 bit CPU command port W
		16'b00000cvvvvvvvvvv = set r/w pointer - 256 32bit integers, 1024 instructions. c=1 for code write, 0 for data read/write
		16'b100wwwvvvvvvvvvv = run ip - 1024 instructions, 3 bit data window offs
0004 - I2C interface: W= {xxxx,cccc,dddddddd}, R={dddddddd,xxxxxxxx}
0006 - WORD write: NMIonIORQ low port address. NMI if (IORQ and PORT_ADDR >= NMIonIORQ_LO and PORT_ADDR <= NMIonIORQ_HI)
0007 - WORD write: NMIonIORQ high port address

0021 - interrupt controller master data port. R/W interrupt mask, 1disabled/0enabled (bit0=timer, bit1=keyboard, bit4=COM1) 
00a1 - interrupt controller slave data port. R/W interrupt mask, 1disabled/0enabled (bit0=RTC, bit4=mouse) 

0040-0043 - PIT 8253 ports

0x60, 0x64 - 8042 keyboard/mouse data and cfg

0061 - bits1:0 speaker on/off (write only)

0070 - RTC (16bit write only counter value). RTC is incremented with 1Mhz and at set value sends INT70h, then restart from 0
		 When set, it restarts from 0. If the set value is 0, it will send INT70h only once, if it was not already 0
			
080h-08fh - memory map: bit9:0=64 Kbytes DDRAM segment index (up to 1024 segs = 64MB), mapped over 
								PORT[3:0] 80186 addressable segment
								
0200h-020fh - joystick port (GPIO) - pullup
		WORD/BYTE r/w: bits[15:8] = 0 for input, 1 for output, bits[7:0]=data

0378 - sound port: 8bit=Covox & DSS compatible, 16bit = stereo L+R - fifo sampled at 44100Hz
		 bit4 of port 03DA is 1 when the sound queue is full. If it is 0, the queue may accept up to 1152 stereo samples (L + R), so 2304 16bit writes.

0379 - parallel port control: bit6 = 1 when DSS queue is full

0388,0389,038A,038B - Adlib ports: 0388=bank1 addr, 0389=bank1 data, 038A=bank2 addr, 038B=bank2 data

03C0 - VGA mode 
		index 00h..0Fh  = EGA palette registers
		index 10h:
			bit0 = graphic(1)/text(0)
			bit3 = text mode flash enabled(1)
			bit5 = ppm - pixel panning mode
			bit6 = vga mode 13h(1)
			bit7 = P54S - 1 to use color select 5-4 from reg 14h
		index 13h: bit[3:0] = hrz pan
		index 14h: bit[3:2] = color select 7-6, bit[1:0] = color select 5-4

03C4, 03C5 (Sequencer registers) - idx1[3] = half pixel clock, idx2[3:0] = write plane, idx4[3]=0 for planar (rw)

03C6 - DAC mask (rw)
03C7 - DAC read index (rw)
03C8 - DAC write index (rw)
03C9 - DAC color (rw)
03CB - font: write WORD = set index (8 bit), r/w BYTE = r/w font data

03CE, 03CF (Graphics registers) (rw)
	0: setres <= din[3:0];
	1: enable_setres <= din[3:0];
	2: color_compare <= din[3:0];
	3: logop <= din[4:3];
	4: rplane <= din[1:0];
	5: rwmode <= {din[3], din[1:0]};
	7: color_dont_care <= din[3:0];
	8: bitmask <= din[7:0]; (1=CPU, 0=latch)

03D9 - CGA Colour control (rw)
	5: Palette 0 - red/green/yellow 1 - magenta/cyan/white
	4: bright
	3-0: border/background/foreground color

03DA - read VGA status, bit0=1 on vblank or hblank, bit1=RS232in, bit2=i2cackerr, bit3=1 on vblank, bit4=sound queue full, bit5=DSP32 halt, bit6=i2cack, bit7=1 always, bit15:8=SD SPI byte read
		 write bit7=SD SPI MOSI bit, SPI CLK 0->1 (BYTE write only), bit8 = SD card chip select (WORD write only)
		 also reset the 3C0 port index flag

03B4, 03D4 - VGA CRT write index:  
										07h: bit1 = VDE8, bit4 = LCR8, bit6 = VDE9
										09h: bit6 = LCR9
										0Ah(bit 5 only): hide cursor
										0Ch: HI screen offset
										0Dh: LO screen offset
										0Eh: HI cursor pos
										0Fh: LO cursor pos
										12h: VDE[7:0]
										13h: scan line offset
										18h: Line Compare Register (LCR)
03B5, 03D5 - VGA CRT read/write data

03f8-03ff - COM1 ports
*/


`timescale 1ns / 1ps

module system (
	input  clk_25, // VGA
	input  clk_sdr, // SDRAM
	input  CLK14745600, // RS232 clk
 	input  clk_mpu, // MPU401 clock 
	input  clk_dsp,
	input  clk_cpu,

	input  clk_en_opl2,  // OPL2 clock enable (3.58 MHz)
	input  clk_en_44100, // COVOX/DSS clock enable

	input  fake286,
	input  adlibhide,
	input  [4:0] cpu_speed, // CPU speed control, 0 - maximum
	input  [7:0] waitstates,  // ISA Bus wait states (for Adlib), in clk_cpu periods

	output [3:0]sdr_n_CS_WE_RAS_CAS,
	output [1:0]sdr_BA,
	output [12:0]sdr_ADDR,
	inout [15:0]sdr_DATA,
	output [1:0]sdr_DQM,

	output reg [5:0]VGA_R,
	output reg [5:0]VGA_G,
	output reg [5:0]VGA_B,
	output frame_on,
	output wire VGA_HSYNC,
	output wire VGA_VSYNC,
	output reg VGA_BLANK,
	output wire VGA_VBLANK,
	input BTN_RESET,	// Reset
	input BTN_NMI,		// NMI
	output [7:0]LED,	// HALT
	input RS232_DCE_RXD,
	output RS232_DCE_TXD,
	input RS232_EXT_RXD,
	output RS232_EXT_TXD,
	input RS232_HOST_RXD,
	output RS232_HOST_TXD,
	output reg RS232_HOST_RST,
	input MPU_RX,
	output MPU_TX,

	output reg SD_n_CS = 1'b1,
	output wire SD_DI,
	output reg SD_CK = 0,
	input SD_DO,

	input [15:0] CDDA_L,
	input [15:0] CDDA_R,

	output AUD_L,
	output AUD_R,
	output [15:0] LAUDIO,
	output [15:0] RAUDIO,
	input PS2_CLK1_I,
	output PS2_CLK1_O,
	input PS2_CLK2_I,
	output PS2_CLK2_O,
	input PS2_DATA1_I,
	output PS2_DATA1_O,
	input PS2_DATA2_I,
	output PS2_DATA2_O,

	input  [7:0] GPIO_IN,
	output [7:0] GPIO_OUT,
	output [7:0] GPIO_OE,
	output reg   GPIO_WR,

	output [15:0] IDE_DAT_O,
	input  [15:0] IDE_DAT_I,
	output  [3:0] IDE_A,
	output        IDE_WE,
	output  [1:0] IDE_CS,
	input   [1:0] IDE_INT,

	output I2C_SCL,
	inout I2C_SDA,

	input [13:0] BIOS_ADDR,
	input [15:0] BIOS_DIN,
	input BIOS_WR,
	output BIOS_REQ
    );

	localparam BIOS_BASE = 20'h57000;
	initial SD_n_CS = 1'b1;

	wire [15:0]cntrl0_user_input_data;
	wire [1:0]sys_cmd_ack;
	wire sys_rd_data_valid;
	wire sys_wr_data_valid;   
	wire [15:0]sys_DOUT;	// sdr data out
	wire [31:0] DOUT;
	wire [15:0]CPU_DOUT;
	wire [15:0]PORT_ADDR;
	wire [31:0] DRAM_dout;
	wire [20:0] ADDR;
	wire LOCK;
	wire MREQ;
	wire IORQ;
	wire WR;
	wire INTA;
	wire WORD;
	wire [3:0] RAM_WMASK;
	wire hblnk;
	wire vblnk;
	wire [10:0]hcount;
	wire [7:0]hde;
	wire [9:0]vcount;
	reg [4:0]vga_hrzpan = 0;
	wire [3:0]vga_hrzpan_req;
	wire [10:0]hcount_pan = hcount + vga_hrzpan - 8'd18;
	reg FifoStart = 1'b0;	// fifo not empty
	reg fifo_clear;
	wire displ_on = !(hblnk | vblnk | !FifoStart);
	wire [17:0]DAC_COLOR;
	wire [8:0]fifo_wr_used_words;
	wire AlmostFull;
	wire AlmostEmpty;
	wire CPU_CE;	// CPU clock enable
	wire CE;
	wire CE_186;
	wire cache_ce;
	wire io_ready;
	wire ddr_rd; 
	wire ddr_wr;
	wire TIMER_OE = PORT_ADDR[15:2] == 14'b00000000010000;	//   40h..43h
	wire VGA_DAC_OE = PORT_ADDR[15:4] == 12'h03c && PORT_ADDR[3:0] <= 4'h9; // 3c0h..3c9h	
	wire LED_PORT = PORT_ADDR[15:0] == 16'h03bc;
	wire SPEAKER_PORT = PORT_ADDR[15:0] == 16'h0061;
	wire MEMORY_MAP = PORT_ADDR[15:4] == 12'h008;
	wire VGA_FONT_OE = PORT_ADDR[15:0] == 16'h03cb;
	wire AUX_OE = PORT_ADDR[15:0] == 16'h0001;
	wire I2C_SELECT = PORT_ADDR[15:0] == 16'h0004;
	wire INPUT_STATUS_OE = PORT_ADDR[15:0] == 16'h03da;
	wire VGA_CRT_OE = (PORT_ADDR[15:1] == 15'b000000111011010) || (PORT_ADDR[15:1] == 15'b000000111101010); // 3b4h, 3b5h, 3d4h, 3d5h
	wire RTC_SELECT = PORT_ADDR[15:0] == 16'h0070;
	wire CGA_CL = PORT_ADDR[15:0] == 16'h03d9;
	wire VGA_SC = PORT_ADDR[15:1] == (16'h03c4 >> 1); // 3c4h, 3c5h
	wire VGA_GC = PORT_ADDR[15:1] == (16'h03ce >> 1); // 3ceh, 3cfh
	wire PIC_OE = PORT_ADDR[15:8] == 8'h00 && PORT_ADDR[6:1] == 6'b010000;	// 20h, 21h, a0h, a1h
	wire KB_OE = PORT_ADDR[15:4] == 12'h006 && {PORT_ADDR[3], PORT_ADDR[1:0]} == 3'b000; // 60h, 64h
	wire JOYSTICK = PORT_ADDR[15:4] == 12'h020; // 0x200-0x20f
	wire PARALLEL_PORT = PORT_ADDR[15:0] == 16'h0378;
	wire PARALLEL_PORT_CTL = PORT_ADDR[15:0] == 16'h0379;
	wire CPU32_PORT = PORT_ADDR[15:1] == (16'h0002 >> 1); // port 1 for data and 3 for instructions
	wire COM1_PORT = PORT_ADDR[15:3] == (16'h03f8 >> 3);
	wire OPL2_PORT = PORT_ADDR[15:1] == (16'h0388 >> 1); // 0x388 .. 0x389
	wire NMI_IORQ_PORT = PORT_ADDR[15:1] == (16'h0006 >> 1); // 6, 7
	wire MPU_PORT = PORT_ADDR[15:1] == (16'h0330 >> 1); // 0x330, 0x331
	wire TANDY_SND_PORT = PORT_ADDR[15:3] == (16'h00c0 >> 3); // 0xc0 - 0xc7
	wire TANDY_PAGE_PORT = PORT_ADDR[15:0] == 16'h03df;
	wire IDE_PORT0 = PORT_ADDR == 16'h03f6 || PORT_ADDR[15:3] == (16'h01f0 >> 3); // 0x3f6, 0x1f0-1f7
	wire IDE_PORT1 = PORT_ADDR == 16'h0376 || PORT_ADDR[15:3] == (16'h0170 >> 3); // 0x1f6, 0x1f0-1f7

	assign IDE_CS[0] = CPU_CE & IORQ && IDE_PORT0;
	assign IDE_CS[1] = CPU_CE & IORQ && IDE_PORT1;
	assign IDE_A = {PORT_ADDR[9], PORT_ADDR[2:0]};
	assign IDE_DAT_O = CPU_DOUT;
	assign IDE_WE = WR;

	wire [7:0] TANDY_SND;
	wire TANDY_SND_RDY;
 	wire [7:0]VGA_DAC_DATA;
	wire [7:0]VGA_CRT_DATA;
	wire [7:0]VGA_SC_DATA;
	wire [7:0]VGA_GC_DATA;
	wire [15:0]PORT_IN;
	wire [7:0]TIMER_DOUT;
	wire [7:0]KB_DOUT;
	wire [7:0]PIC_DOUT;
	wire [7:0]COM1_DOUT;
	wire [7:0]CGA_CL_DATA;
	wire HALT;
	wire sq_full; // sound queue full
	wire dss_full;
	wire [15:0]cpu32_data;
	wire cpu32_halt;

	reg [1:0]cntrl0_user_command_register = 0;
	reg [16:0]vga_addr = 0;
	reg [16:0]vga_addr_r;
	reg s_prog_full;
	reg s_prog_empty;
	reg s_ddr_rd = 1'b0;
	reg s_ddr_wr = 1'b0;
	reg crw = 0;	// 1=cache read window
	reg s_RS232_DCE_RXD;
	reg s_RS232_HOST_RXD;
	reg [18:0]rstcount = 0;
	reg [19:0]s_displ_on = 0; // clk_25 delayed displ_on
	reg [1:0]vga13 = 0;       // 1 for mode 13h
	reg [1:0]vgatext = 0;     // 1 for text mode
	reg [1:0]modecomp = 0;    // CGA/Tandy compatibility line addressing mode
	wire shiftload;           // 1 for 4-bit packed pixel mode (for CGA 320x200x4)
	reg [1:0]planar = 0;
	reg [1:0]half = 0;        // half pixel clock
	reg [3:0]replncnt;
	wire vgaflashreq;
	reg flashbit = 0;
	reg [5:0]flashcount = 0;
	wire [5:0]char_row;
	wire [3:0]char_ln;
	wire [11:0]charcount = (({char_row, 4'b0000} + {char_row, 6'b000000}) >> half_s[1]) + (half_s[1] ? hcount_pan[10:4] : hcount_pan[10:3]);
	wire [31:0]fifo_dout32;
	wire [15:0]fifo_dout = ((modecompreq == 2'b01 | (vgatext_s[1] & half_s[1])) ? hcount_pan[4] : (vgatext_s[1] | modecompreq[1]) ? hcount_pan[3] : vga13_s[1] ? hcount_pan[2] : hcount_pan[1]) ? fifo_dout32[31:16] : fifo_dout32[15:0];

	reg [8:0]vga_ddr_row_count = 0;
	reg [1:0]linecnt = 0;
	reg [2:0]max_read;
	reg [4:0]col_counter;
	wire vga_end_frame = ((vga_ddr_row_count == vblank_start) || (vga_ddr_row_count == vde_adj)) && vde != 0;
	wire vga_start_fifo = (vcount == vtotal - 1'd1) || vtotal == 0;
	reg [3:0]vga_repln_count = 0; // repeat line counter
	reg [7:0]vga_lnbytecount = 0; // line byte count (multiple of 4)

	wire [4:0]vga_lnend = (modecomp[1] ? 3'd4 : // multiple of 32 (SDRAM resolution = 32)
	                       modecomp[0] ? 3'd1 :
	                       vgatext[1] ? (hde >> (4+half[1])) :
	                       (vga13[1] | planar[1]) ? (hde >> 3) :
	                       (hde >> 2))
	                       + 1'd1  // rounding up
	                       + 1'd1; // extra 32 byte fetch for panning
	reg [11:0]vga_font_counter = 0;
	reg [7:0]vga_attr;
	reg [4:0]RTCDIV25 = 0;
	reg [1:0]RTCSYNC = 0;
	reg [15:0]RTC = 0;
	reg [15:0]RTCSET = 0;
	wire RTCEND = RTC == RTCSET;
	wire RTCDIVEND = RTCDIV25 == 24;
	wire [18:0]cache_hi_addr;
	wire [8:0]memmap;
	wire [8:0]memmap_mux;
	wire [7:0]font_dout;
	wire [7:0]VGA_FONT_DATA;
	wire [3:0]replncntreq;
	wire [3:0]line_presetreq;
	wire vgatextreq;
	wire vga13req;
	wire planarreq;
	wire [1:0]modecompreq;
	wire halfreq;
	wire oncursor;
	wire [4:0]crs[1:0];
	wire [11:0]cursorpos;
	wire [15:0]scraddr;
	reg flash_on;
	reg [1:0] speaker_on = 0;
	reg [9:0]rNMI = 0;
	wire [2:0]shift = half_s[1] ? ~hcount_pan[3:1] : ~hcount_pan[2:0];
	wire [2:0]pxindex = half_s[1] ? (-hcount_pan[3:0]) >> 1 : -hcount_pan[2:0];

	reg [1:0]planar_s; // synced to CPU clock
	reg [1:0]half_s;
	reg [1:0]vgatext_s;
	reg [1:0]vga13_s;
	reg [1:0]ppm_s;
	reg [1:0]vgaflash_s;

	reg [2:0]crt_page;
	reg [2:0]cpu_page;

	reg [13:0]cga_addr;
	reg [13:0]cga_addr_r;
	reg cga_palette;
	reg cga_bright;
	reg [3:0] cga_background;
	wire [1:0]cga_index = {fifo_dout[{hcount_pan[3], ~hcount_pan[2:1], 1'b1}], {fifo_dout[{hcount_pan[3], ~hcount_pan[2:1], 1'b0}]}};
	reg [3:0]cga_color;

	always @(*) begin
		case({cga_palette, cga_bright, cga_index})
			4'b00_00: cga_color = cga_background;
			4'b00_01: cga_color = 2;
			4'b00_10: cga_color = 4;
			4'b00_11: cga_color = 6;
			4'b01_00: cga_color = cga_background;
			4'b01_01: cga_color = 10;
			4'b01_10: cga_color = 12;
			4'b01_11: cga_color = 14;
			4'b10_00: cga_color = cga_background;
			4'b10_01: cga_color = 3;
			4'b10_10: cga_color = 5;
			4'b10_11: cga_color = 7;
			4'b11_00: cga_color = cga_background;
			4'b11_01: cga_color = 11;
			4'b11_10: cga_color = 13;
			4'b11_11: cga_color = 15;
		endcase
	end

	wire [3:0]EGA_MUX = vgatext_s[1] ? (font_dout[pxindex] ^ flash_on) ? vga_attr[3:0] : {vga_attr[7] & ~vgaflash_s[1], vga_attr[6:4]} :
	                    (modecompreq[1] & ~shiftload) ? {2{fifo_dout[{hcount_pan[2], ~hcount_pan[1:0], 1'b1}], fifo_dout[{hcount_pan[2], ~hcount_pan[1:0], 1'b0}] }} :  // PCJr 640x200x4
	                    modecompreq[1] ? {fifo_dout[{hcount_pan[2], ~hcount_pan[1], 2'b11}], fifo_dout[{hcount_pan[2], ~hcount_pan[1], 2'b10}], fifo_dout[{hcount_pan[2], ~hcount_pan[1], 2'b01}],fifo_dout[{hcount_pan[2], ~hcount_pan[1], 2'b00}] } :  // PCJr 320x200x16
	                    (modecompreq[0] & ~shiftload) ? {4{fifo_dout[{hcount_pan[3], ~hcount_pan[2:0]}]}} : // CGA 640x200x2
						modecompreq[0] ? cga_color : // CGA 320x200x4
		                             {fifo_dout32[{2'b11, shift}], fifo_dout32[{2'b10, shift}], fifo_dout32[{2'b01, shift}], fifo_dout32[{2'b00, shift}]};
	wire [7:0]VGA_INDEX;
	reg [3:0]exline = 4'b0000; // extra 8 dwords (32 bytes) for screen panning
	reg [2:0]wrdcnt = 0;
	wire vrdon = s_displ_on[16-vga_hrzpan];
	wire vrden = (~vrdon & ~exline[3] & |wrdcnt) || // flush extra words left in the FIFO
		((vrdon || exline[3]) &&
		(modecompreq[1]                                ? &hcount_pan[3:0] :
		 (modecompreq[0] | (vgatext_s[1] & half_s[1])) ? &hcount_pan[4:0] :
		 (vgatext_s[1] | half_s[1])                    ? &hcount_pan[3:0] :
		 (vga13_s[1] | planar_s[1])                    ? &hcount_pan[2:0] :
		                                                 &hcount_pan[1:0]));
	reg s_vga_endline;
	reg s_vga_endscanline = 1'b0;
	reg s_vga_endframe;
	reg s_vga_start_fifo;
	reg [23:0]sdraddr;
	wire [3:0]vga_wplane;
	wire [1:0]vga_rplane;
	wire [7:0]vga_bitmask;	// write 1=CPU, 0=VGA latch
	wire [2:0]vga_rwmode;
	wire [3:0]vga_setres;
	wire [3:0]vga_enable_setres;
	wire [1:0]vga_logop;
	wire [3:0]vga_color_compare;
	wire [3:0]vga_color_dont_care;
	wire [2:0]vga_rotate_count;
	wire [7:0]vga_offset;
	wire ppmreq;        // pixel panning mode
	wire [9:0]lcr;      // line compare register
	wire [9:0]vde;      // vertical display end
	wire [9:0]vblank_start; // vertical blank start
	wire [9:0]vtotal;
	wire [9:0]vde_adj = vtotal>vde ? vde : vtotal - 1'd1;
	wire sdon = s_displ_on[18+vgatext_s[1]] & (vcount <= vde_adj);
	wire vga_in_cache;

// Com interface
	reg [1:0]ComSel = 2'b00; // 00:COM1=RS232_DCE, 01: COM1=RS232_EXT, 1x: COM1=RS232_HOST
	wire RX = ComSel[1] ? RS232_HOST_RXD : ComSel[0] ? RS232_EXT_RXD : RS232_DCE_RXD;	
	wire TX;
	assign RS232_DCE_TXD = ComSel[1:0] == 2'b00 ? TX : 1'b1;
	assign RS232_EXT_TXD = ComSel[1:0] == 2'b01 ? TX : 1'b1;
	assign RS232_HOST_TXD = ComSel[1] ? TX : 1'b1;
	reg [1:0]COMBRShift = 2'b00; 
	
// SD interface
	reg [7:0]SDI;
	assign SD_DI = CPU_DOUT[7];
	
// GPIO interface
	reg [7:0]GPIOState = 8'h00;
	reg [7:0]GPIOData;
	reg [7:0]GPIODout = 8'hff;
	assign GPIO_OUT = GPIODout;
	assign GPIO_OE = GPIOState;

// I2C interface
	reg [11:0]i2c_cd = 0;
	wire [7:0]i2cdout;
	wire i2cack;
	wire i2cackerr;

	
// opl3 interface
    wire [7:0]opl32_data;
    wire [15:0]opl3left;
    wire [15:0]opl3right;

// NMI on IORQ
	reg [15:0]NMIonIORQ_LO = 16'h0001;
	reg [15:0]NMIonIORQ_HI = 16'h0000;

	assign LED = {1'b0, !cpu32_halt, AUD_L, AUD_R, planarreq, |sys_cmd_ack, ~SD_n_CS, HALT};
	assign frame_on = s_displ_on[17+vgatext_s[1]];
	
	assign PORT_IN[15:8] = 
		({8{MEMORY_MAP}} & {7'b0000000, memmap[8]}) |
		({8{INPUT_STATUS_OE}} & SDI) |
		({8{CPU32_PORT}} & cpu32_data[15:8]) | 
		({8{JOYSTICK}} & GPIOState) |
		({8{I2C_SELECT}} & i2cdout) |
		({8{IDE_PORT0 | IDE_PORT1}} & IDE_DAT_I[15:8]);

	assign PORT_IN[7:0] = //INPUT_STATUS_OE ? {2'b1x, cpu32_halt, sq_full, vblnk, s_RS232_HOST_RXD, s_RS232_DCE_RXD, hblnk | vblnk} : CPU32_PORT ? cpu32_data[7:0] : slowportdata;
							 ({8{VGA_DAC_OE}} & VGA_DAC_DATA) |
							 ({8{VGA_FONT_OE}}& VGA_FONT_DATA) |
							 ({8{KB_OE}} & KB_DOUT) |
							 ({8{SPEAKER_PORT}} & {6'd0, speaker_on}) |
							 ({8{INPUT_STATUS_OE}} & {1'b1, i2cack, cpu32_halt, sq_full, vblnk, i2cackerr, s_RS232_DCE_RXD, hblnk | vblnk}) | 
							 ({8{VGA_CRT_OE}} & VGA_CRT_DATA) | 
							 ({8{MEMORY_MAP}} & {memmap[7:0]}) |
							 ({8{TIMER_OE}} & TIMER_DOUT) |
							 ({8{PIC_OE}} & PIC_DOUT) |
							 ({8{VGA_SC}} & VGA_SC_DATA) |
							 ({8{VGA_GC}} & VGA_GC_DATA) |
							 ({8{JOYSTICK}} & GPIOData) |
							 ({8{PARALLEL_PORT_CTL}} & {1'bx, dss_full, 6'bxxxxxx}) |
							 ({8{CPU32_PORT}} & cpu32_data[7:0]) | 
							 ({8{COM1_PORT}} & COM1_DOUT) | 
							 ({8{OPL2_PORT}} & opl32_data)  |
							 ({8{MPU_PORT}} & mpu_data) |
							 ({8{CGA_CL}} & CGA_CL_DATA) |
							 ({8{IDE_PORT0 | IDE_PORT1}} & IDE_DAT_I[7:0]);


	assign BIOS_REQ = sys_wr_data_valid;
	reg [15:0] BIOS_data;
	reg        BIOS_data_valid;

	SDRAM_16bit SDR
	(
		.sys_CLK(clk_sdr),				// clock
		.sys_CMD(cntrl0_user_command_register),					// 00=nop, 01 = write 64 bytes, 10=read 32 bytes, 11=read 64 bytes
		.sys_ADDR(sdraddr),	// word address
		.sys_DIN(BIOS_data_valid ? BIOS_data : cntrl0_user_input_data),		// data input
		.sys_DOUT(sys_DOUT),					// data output
		.sys_rd_data_valid(sys_rd_data_valid),	// data valid read
		.sys_wr_data_valid(sys_wr_data_valid),	// data valid write
		.sys_cmd_ack(sys_cmd_ack),			// command acknowledged
		
		.sdr_n_CS_WE_RAS_CAS(sdr_n_CS_WE_RAS_CAS),			// SDRAM #CS, #WE, #RAS, #CAS
		.sdr_BA(sdr_BA),					// SDRAM bank address
		.sdr_ADDR(sdr_ADDR),				// SDRAM address
		.sdr_DATA(sdr_DATA),				// SDRAM data
		.sdr_DQM(sdr_DQM)					// SDRAM DQM
	);


//	reg [4:0] vga32bytecount = 5'b0;
//	wire [16:0]vgaaddr = vga_bram_row_col + vga_lnbytecount_b;
//	
//	wire MREQ;
//   wire CACHE_EN = (ADDR[20:15] != 6'b010100);
//	wire CACHE_MREQ = MREQ & CACHE_EN;
//
//	wire TXTVRAM = (ADDR[19:16] == 4'b1011);
//	wire GFXVRAM = (ADDR[19:16] == 4'b1010);
//	wire vram_en = (TXTVRAM | GFXVRAM) & MREQ;
//	
//	wire [31:0] vram_dout;
//	wire [31:0] CPU_DIN;
//	reg s_cache_mreq;
//	assign CPU_DIN	= s_cache_mreq ? DRAM_dout : vram_dout;

	// synchronizers
	always @(posedge clk_25) begin
		planar_s <= {planar_s[0], planarreq};
		half_s <= {half_s[0], halfreq};
		vgatext_s <= {vgatext_s[0], vgatextreq};
		vga13_s <= {vga13_s[0], vga13req};
		ppm_s <= {ppm_s[0], ppmreq};
		vgaflash_s <= {vgaflash_s[0], vgaflashreq};
	end

	fifo vga_fifo 
	(
	  .wrclk(clk_sdr), // input wr_clk
	  .rdclk(clk_25), // input rd_clk
	  .aclr(fifo_clear),
	  .data(sys_DOUT), // input [15 : 0] din
	  .wrreq(!crw && sys_rd_data_valid && !col_counter[4]), // input wrreq
	  .rdreq(vrden), // input rdreq
	  .q(fifo_dout32), // output [31 : 0] dout
	  .wrusedw(fifo_wr_used_words) // output [8:0]
	);

	VGA_DAC dac 
	(
		 .CE(VGA_DAC_OE && IORQ && CPU_CE), 
		 .WR(WR), 
		 .addr(PORT_ADDR[3:0]), 
		 .din(CPU_DOUT[7:0]), 
		 .dout(VGA_DAC_DATA), 
		 .CLK(clk_cpu), 
		 .VGA_CLK(clk_25), 
		 .vga_addr((modecompreq[0] | vgatext_s[1] | (~vga13_s[1] & planar_s[1])) ? VGA_INDEX : (vga13_s[1] ? hcount_pan[1] : hcount_pan[0]) ? fifo_dout[15:8] : fifo_dout[7:0]), 
		 .color(DAC_COLOR),
		 .vgatext(vgatextreq),
		 .vga13(vga13req),
		 .vgaflash(vgaflashreq),
		 .setindex(INPUT_STATUS_OE && IORQ && CPU_CE),
		 .hrzpan(vga_hrzpan_req),
		 .ppm(ppmreq),
		 .ega_attr(EGA_MUX),
		 .ega_pal_index(VGA_INDEX)
    );

	 VGA_CRT crt
	 (
		.CE(IORQ && CPU_CE && VGA_CRT_OE),
		.WR(WR),
		.WORD(WORD),
		.din(CPU_DOUT),
		.addr(PORT_ADDR[0]),
		.dout(VGA_CRT_DATA),
		.CLK(clk_cpu),
		.oncursor(oncursor),
		.cursorstart(crs[0]),
		.cursorend(crs[1]),
		.cursorpos(cursorpos),
		.scraddr(scraddr),
		.offset(vga_offset),
		.lcr(lcr),
		.replncnt(replncntreq),
		.line_preset(line_presetreq),
		.modecomp(modecompreq),
		.hde(hde),
		.vtotal(vtotal),
		.vde(vde),
		.vblank_start(vblank_start),

		.clk_vga(clk_25),
		.ce_vga(FifoStart),

		.half(halfreq),
		.hcount(hcount),
		.hsync(VGA_HSYNC),
		.hblnk(hblnk),
		.vcount(vcount),
		.vsync(VGA_VSYNC),
		.vblnk(vblnk),
		.char_ln(char_ln),
		.char_row(char_row)
	);
	assign VGA_VBLANK = vblnk;

	VGA_SC sc
	(
		.CE(IORQ && CPU_CE && VGA_SC),	// 3c4, 3c5
		.WR(WR),
		.WORD(WORD),
		.din(CPU_DOUT),
		.dout(VGA_SC_DATA),
		.addr(PORT_ADDR[0]),
		.CLK(clk_cpu),
		.half(halfreq),
		.planarreq(planarreq),
		.wplane(vga_wplane)
    );

	VGA_GC gc
	(
		.CE(IORQ && CPU_CE && VGA_GC),
		.WR(WR),
		.WORD(WORD),
		.din(CPU_DOUT),
		.addr(PORT_ADDR[0]),
		.CLK(clk_cpu),
		.rplane(vga_rplane),
		.bitmask(vga_bitmask),
		.rwmode(vga_rwmode),
		.setres(vga_setres),
		.enable_setres(vga_enable_setres),
		.logop(vga_logop),
		.color_compare(vga_color_compare),
		.color_dont_care(vga_color_dont_care),
		.rotate_count(vga_rotate_count),
		.shiftload(shiftload),
		.dout(VGA_GC_DATA)
	);

	sr_font VGA_FONT 
	(
		.clock_a(clk_25), // input clka
		.wren_a(1'b0), // input [0 : 0] wea
		.address_a({fifo_dout[7:0], char_ln}), // input [11 : 0] addra
		.data_a(8'h00), // input [7 : 0] dina
		.q_a(font_dout), // output [7 : 0] douta
		.clock_b(clk_cpu), // input clkb
		.wren_b(WR & IORQ & VGA_FONT_OE & ~WORD & CPU_CE), // input [0 : 0] web
		.address_b(vga_font_counter), // input [11 : 0] addrb
		.data_b(CPU_DOUT[7:0]), // input [7 : 0] dinb
		.q_b(VGA_FONT_DATA) // output [7 : 0] doutb
	);

	assign CE = cache_ce & io_ready;

	cache_controller cache_ctl 
	(
		.clk(clk_cpu), 
		.addr({memmap_mux, ADDR[15:0]}),
		.dout(DRAM_dout), 
		.din(DOUT), 
		.mreq(MREQ), 
		.wmask(RAM_WMASK),
		.ce(cache_ce),
		.cpu_speed(cpu_speed),

		.vga_addr({vga_ddr_row_col_adr, 2'b00}),
		.vga_in_cache(vga_in_cache),

		.ddr_clk(clk_sdr), 
		.ddr_din(sys_DOUT), 
		.ddr_dout(cntrl0_user_input_data), 
		.ddr_rd(ddr_rd), 
		.ddr_wr(ddr_wr),
		.hiaddr(cache_hi_addr),
		.cache_write_data(crw && sys_rd_data_valid), // read DDR, write to cache
		.cache_read_data(crw && sys_wr_data_valid)
	);

	wire I_KB;
	wire I_MOUSE;
	wire KB_RST;
	KB_Mouse_8042 KB_Mouse 
	(
		 .CS(IORQ && CPU_CE && KB_OE), // 60h, 64h
		 .WR(WR), 
		 .cmd(PORT_ADDR[2]), // 64h
		 .din(CPU_DOUT[7:0]), 
		 .dout(KB_DOUT), 
		 .clk(clk_cpu), 
		 .I_KB(I_KB), 
		 .I_MOUSE(I_MOUSE), 
		 .CPU_RST(KB_RST), 
		 .PS2_CLK1_I(PS2_CLK1_I),
		 .PS2_CLK1_O(PS2_CLK1_O),
		 .PS2_CLK2_I(PS2_CLK2_I),
		 .PS2_CLK2_O(PS2_CLK2_O),
		 .PS2_DATA1_I(PS2_DATA1_I),
		 .PS2_DATA1_O(PS2_DATA1_O),
		 .PS2_DATA2_I(PS2_DATA2_I),
		 .PS2_DATA2_O(PS2_DATA2_O)
	);

	wire [7:0]PIC_IVECT;
	wire INT;
	wire timer_int;
	wire I_COM1;
	PIC_8259 PIC 
	(
		 .RST(!rstcount[18]),
		 .CS(PIC_OE && IORQ && CPU_CE), // 20h, 21h, a0h, a1h
		 .A(PORT_ADDR[0]),
		 .WR(WR), 
		 .din(CPU_DOUT[7:0]), 
		 .slave(PORT_ADDR[7]),
		 .dout(PIC_DOUT), 
		 .ivect(PIC_IVECT), 
		 .clk(clk_cpu), 
		 .INT(INT), 
		 .IACK(INTA & CPU_CE), 
		 .I({I_COM1, IDE_INT, I_MOUSE, RTCEND, I_KB, timer_int})
    );

	wire [3:0]seg_addr;
	wire vga_planar_seg;
	unit186 CPUUnit
	(
		 .FAKE286(fake286),
		 .INPORT(INTA ? {8'h00, PIC_IVECT} : PORT_IN), 
		 .DIN(DRAM_dout), 
		 .CPU_DOUT(CPU_DOUT),
		 .PORT_ADDR(PORT_ADDR),
		 .SEG_ADDR(seg_addr),
		 .DOUT(DOUT), 
		 .ADDR(ADDR), 
		 .WMASK(RAM_WMASK), 
		 .CLK(clk_cpu), 
		 .CE(CE), 
		 .CPU_CE(CPU_CE),
		 .CE_186(CE_186),
		 .INTR(INT), 
		 .NMI(rNMI[9] || (CPU_CE && IORQ && PORT_ADDR >= NMIonIORQ_LO && PORT_ADDR <= NMIonIORQ_HI)), 
		 .RST(!rstcount[18]), 
		 .INTA(INTA), 
		 .LOCK(LOCK), 
		 .HALT(HALT), 
		 .MREQ(MREQ),
		 .IORQ(IORQ),
		 .WR(WR),
		 .WORD(WORD),
		 .FASTIO(1'b1),
		 
		 .VGA_SEL(planarreq && vga_planar_seg),
		 .VGA_WPLANE(vga_wplane),
		 .VGA_RPLANE(vga_rplane),
		 .VGA_BITMASK(vga_bitmask),
		 .VGA_RWMODE(vga_rwmode),
		 .VGA_SETRES(vga_setres),
		 .VGA_ENABLE_SETRES(vga_enable_setres),
		 .VGA_LOGOP(vga_logop),
		 .VGA_COLOR_COMPARE(vga_color_compare),
		 .VGA_COLOR_DONT_CARE(vga_color_dont_care),
		 .VGA_ROTATE_COUNT(vga_rotate_count)
	);
	
	seg_map seg_mapper 
	(
		 .CLK(clk_cpu),
		 .cpuaddr(PORT_ADDR[3:0]), 
		 .cpurdata(memmap), 
		 .cpuwdata(CPU_DOUT[8:0]), 
		 .memaddr(ADDR[20:16]),
		 .memdata(memmap_mux), 
		 .WE(MEMORY_MAP & WR & WORD & IORQ & CPU_CE),
		 .seg_addr(seg_addr),
		 .vga_planar_seg(vga_planar_seg)
    );

	 wire timer_spk;
	 timer_8253 timer 
	 (
		 .CS(TIMER_OE && IORQ && CPU_CE), 
		 .WR(WR), 
		 .addr(PORT_ADDR[1:0]), 
		 .din(CPU_DOUT[7:0]), 
		 .dout(TIMER_DOUT), 
		 .CLK_25(clk_25), 
		 .clk(clk_cpu),
		 .gate2(speaker_on[0]),
		 .out0(timer_int), 
		 .out2(timer_spk)
    );

	soundwave sound_gen
	(
		.CLK(clk_cpu),
		.clk_en(clk_en_44100),
		.data(CPU_DOUT),
		.we(IORQ & CPU_CE & WR & PARALLEL_PORT),
		.word(WORD),
		.speaker(timer_spk & speaker_on[1]),
		.tandy_snd(TANDY_SND),
		.cdda_l(CDDA_L),
		.cdda_r(CDDA_R),
		.opl3left(opl3left),
		.opl3right(opl3right),
		.full(sq_full), // when not full, write max 2x1152 16bit samples
		.dss_full(dss_full),
		.laudio(LAUDIO),
		.raudio(RAUDIO),
		.AUDIO_L(AUD_L),
		.AUDIO_R(AUD_R)
	);

	// Tandy sound
	sn76489_top sn76489
	(
		.clock_i(clk_cpu),
		.clock_en_i(clk_en_opl2), // 3.579MHz
		.res_n_i(rstcount[18]),
		.ce_n_i(~(IORQ & TANDY_SND_PORT)),
		.we_n_i(~(IORQ & WR)),
		.ready_o(TANDY_SND_RDY),
		.d_i(CPU_DOUT[7:0]),
		.aout_o(TANDY_SND)
	);

	DSP32 DSP32_inst
	(
		.clkcpu(clk_cpu),
		.clkdsp(clk_dsp),
		.cmd(PORT_ADDR[0]), // port 2=data, port 3=cmd (word only)
		.ce(IORQ & CPU_CE & CPU32_PORT & WORD),
		.wr(WR),
		.din(CPU_DOUT),
		.dout(cpu32_data),
		.halt(cpu32_halt)
	);

	UART_8250 UART(
		.CLK_18432000(CLK14745600),
		.RS232_DCE_RXD(RX),
		.RS232_DCE_TXD(TX),
		.clk(clk_cpu),
		.din(CPU_DOUT[7:0]),
		.dout(COM1_DOUT),
		.cs(COM1_PORT && IORQ && CPU_CE),
		.wr(WR),
		.addr(PORT_ADDR[2:0]),
		.BRShift(COMBRShift),
		.INT(I_COM1)
    );

	reg [7:0] mpu_data;
	wire [7:0] mpu_uart_data;
	wire rx_empty, tx_full;
	reg mpu_read_ack;
	reg mpu_dumb;
	wire mpu_cs = MPU_PORT & IORQ & CPU_CE & ~PORT_ADDR[0] & ((!WR & ~mpu_read_ack) | WR);

	gh_uart_16550 #(1'b1) mpu_uart
	(
		.clk(clk_cpu),
		.BR_clk(clk_mpu),
		.rst(!rstcount[18]),
		.CS(mpu_cs),
		.WR(WR),
		.ADD(0),
		.D(CPU_DOUT[7:0]),
		.RD(mpu_uart_data),

		.sRX(MPU_RX),
		.sTX(MPU_TX),
		.RIn(1),
		.CTSn(0),
		.DSRn(0),
		.DCDn(0),

		.DIV2(1),
		.TX_Full(tx_full),
		.RX_Empty(rx_empty)
	);

	wire signed [15:0] jtopl2_snd;
	assign opl3left = jtopl2_snd;
	assign opl3right = jtopl2_snd;

	wire [7:0] jtopl2_dout;
	assign opl32_data = adlibhide ? 8'hFF : PORT_ADDR[1:0] == 2'b00 ? {jtopl2_dout[7:5], 5'd0} : 8'd0;

	wire      jtopl2_cs = IORQ & OPL2_PORT & CPU_CE;
	reg [7:0] jtopl2_ready;

	assign io_ready = (jtopl2_ready == 0 && TANDY_SND_RDY);

	always @(posedge clk_cpu) begin
		if (!rstcount[18])
			jtopl2_ready <= 0;
		else begin
			if (jtopl2_cs) jtopl2_ready <= waitstates;
			if (|jtopl2_ready) jtopl2_ready <= jtopl2_ready - 1'd1;
		end
	end

	jtopl2 jtopl2_inst
	(
		.rst(!rstcount[18]),
		.clk(clk_cpu),
		.cen(clk_en_opl2),
		.din(CPU_DOUT[7:0]),
		.dout(jtopl2_dout),
		.addr(PORT_ADDR[0]),
		.cs_n(~jtopl2_cs),
		.wr_n(~WR),
		.irq_n(),
		.snd(jtopl2_snd),
		.sample()
	);

	i2c_master_byte i2cmb
	(
		.refclk(clk_25),	// 25Mhz=100Kbps...100Mhz=400Kbps
		.din(i2c_cd[7:0]),
		.cmd(i2c_cd[11:8]),	// 01xx=wr,10xx=rd+ack, 11xx=rd+nack, xx1x=start, xxx1=stop
		.dout(i2cdout),
		.ack(i2cack),
		.noack(i2cackerr),
		.SCL(I2C_SCL),
		.SDA(I2C_SDA),
		.rst(1'b0)
	);

	// adjust for CGA odd/even line addressing mode, add framebuffer start address in physical RAM
	wire [17:0] vga_ddr_row_col_adr = modecomp[0] ? {5'b10111, modecomp[1] & linecnt[1], linecnt[0], cga_addr[12:2]} : {1'b1, vga_addr[16:13] + (vgatext[1] ? 4'b0111 : 4'b0100), vga_addr[12:0]};

	reg nop;
	reg fifo_fill = 1;
	reg fifo_req;
	always @ (posedge clk_sdr) begin
		s_prog_full <= fifo_wr_used_words > 350; // AlmostFull;
		if(fifo_wr_used_words < 64) s_prog_empty <= 1'b1; //AlmostEmpty;
		else begin
			s_prog_empty <= 1'b0;
			FifoStart <= 1'b1;
		end
		fifo_req <= fifo_fill && !vga_in_cache;
		s_ddr_rd <= ddr_rd;
		s_ddr_wr <= ddr_wr;
		s_vga_endline <= vga_repln_count == replncnt;
		s_vga_endframe <= vga_end_frame;
		s_vga_start_fifo <= vga_start_fifo;
		nop <= sys_cmd_ack == 2'b00;

		BIOS_data_valid <= BIOS_WR;
		BIOS_data <= BIOS_DIN;

		if(BIOS_WR) begin
			cntrl0_user_command_register <= 2'b01;  // write 256 byte BIOS data
			sdraddr <= BIOS_BASE + (BIOS_ADDR >> 1);
		end else if(s_prog_empty & fifo_req) begin
			cntrl0_user_command_register <= 2'b10;  // read 32 bytes VGA
			sdraddr <= vga_ddr_row_col_adr;
		end else if(s_ddr_wr) begin
			cntrl0_user_command_register <= 2'b01;  // write 256 bytes cache
			sdraddr <= {cache_hi_addr[18:0], 4'b0000};
		end else if(s_ddr_rd) begin
			cntrl0_user_command_register <= 2'b11;  // read 256 bytes cache
			sdraddr <= {cache_hi_addr[18:0], 4'b0000};
		end else if(~s_prog_full & fifo_req) begin
			cntrl0_user_command_register <= 2'b10;  // read 32 bytes VGA
			sdraddr <= vga_ddr_row_col_adr;
		end else begin
			cntrl0_user_command_register <= 2'b00;
		end

		max_read <= &sdraddr[7:3] ? ~sdraddr[2:0] : 3'b111;	// SDRAM row size = 512 words

		if(!crw && sys_rd_data_valid) col_counter <= col_counter - 1'b1;
		if(nop) case(sys_cmd_ack)
			2'b10: begin
				crw <= 1'b0;	// VGA read
				col_counter <= {1'b0, max_read, 1'b1};
				vga_lnbytecount <= vga_lnbytecount + max_read + 1'b1;
				vga_addr <= vga_addr + max_read + 1'b1;
				if (vgatext[1] | half[1] | vga13[1] | planar[1]) vga_addr[16] <= 0; // 64K/plane in normal VGA modes
				cga_addr[12:2] <= cga_addr[12:2] + max_read + 1'b1;
			end					
			2'b01, 2'b11: crw <= !BIOS_WR;	// cache read/write
		endcase

		if(s_vga_start_fifo) begin
			fifo_fill <= 1;
			if (!fifo_fill) begin
				vga_addr <= scraddr >> vgatext[1];
				vga_addr_r <= scraddr >> vgatext[1];
				cga_addr <= {scraddr[11:0], 1'b0};
				cga_addr_r <= {scraddr[11:0], 1'b0};
				vga13 <= {vga13[0], vga13req};
				vgatext <= {vgatext[0], vgatextreq};
				modecomp <= modecompreq;
				planar <= {planar[0], planarreq};
				half <= {half[0], halfreq};
				replncnt <= replncntreq;
				vga_repln_count <= line_presetreq;
			end
		end

		if(s_vga_endscanline) begin
			col_counter[3:1] <= col_counter[3:1] - vga_lnbytecount[2:0];
			vga_lnbytecount <= 0;
			s_vga_endscanline <= 1'b0;

			vga_addr <= vga_addr_r;
			if({1'b0, vga_ddr_row_count} == lcr) begin
				vga_addr <= 0;
				vga_addr_r <= 0;
			end else if(s_vga_endline) begin
				vga_addr <= vga_addr_r + (vga_offset << ~vgatext[1]);
				vga_addr_r <= vga_addr_r + (vga_offset << ~vgatext[1]);
				if (vgatext[1] | half[1] | vga13[1] | planar[1]) {vga_addr_r[16], vga_addr[16]} <= 0; // 64K/plane in normal VGA modes
			end

			cga_addr <= cga_addr_r;
			if(s_vga_endline & linecnt[0] & (!modecomp[1] | linecnt[1])) begin
				cga_addr[12:0] <= cga_addr_r[12:0] + {vga_offset, 2'b0};
				cga_addr_r[12:0] <= cga_addr_r[12:0] + {vga_offset, 2'b0};
			end

			if(s_vga_endline) begin
				vga_repln_count <= 0;
				linecnt <= linecnt + 1'd1;
			end
			else vga_repln_count <= vga_repln_count + 1'b1;
			if(s_vga_endframe) begin
				vga_ddr_row_count <= 0;
				fifo_fill <= 0;
				linecnt <= 0;
			end else vga_ddr_row_count <= vga_ddr_row_count + 1'b1; 
		end else s_vga_endscanline <= (vga_lnbytecount[7:3] == vga_lnend);
	end

	always @ (posedge clk_cpu) begin
		s_RS232_DCE_RXD <= RS232_DCE_RXD;
		s_RS232_HOST_RXD <= RS232_HOST_RXD;
		if(IORQ & CPU_CE) begin
			if(WR & AUX_OE) begin
				if(!WORD) {COMBRShift[1:0], RS232_HOST_RST, ComSel[1:0]} <= CPU_DOUT[4:0];
			end
			if(VGA_FONT_OE) vga_font_counter <= WR && WORD ? {CPU_DOUT[7:0], 4'b0000} : vga_font_counter + 1'b1; 
			if(WR & SPEAKER_PORT) speaker_on <= CPU_DOUT[1:0];
		end
// SD
		if(CPU_CE) begin
			SD_CK <= IORQ & INPUT_STATUS_OE & WR & ~WORD;
			if(IORQ & INPUT_STATUS_OE & WR) begin
				if(WORD) SD_n_CS <= ~CPU_DOUT[8]; // SD chip select
				else SDI <= {SDI[6:0], SD_DO};
			end
		end

		if(KB_RST || BTN_RESET) rstcount <= 0;
		else if(CPU_CE && ~rstcount[18]) rstcount <= rstcount + 1'b1;

// RTC		
		RTCSYNC <= {RTCSYNC[0], RTCDIVEND};
		if(IORQ && CPU_CE && WR && WORD && RTC_SELECT) begin
			RTC <= 0;
			RTCSET <= CPU_DOUT;
		end else if(RTCSYNC == 2'b01) begin
			if(RTCEND) RTC <= 0;
			else RTC <= RTC + 1'b1;
		end

// GPIO
		if(CPU_CE) begin
			GPIOData <= GPIO_IN;
			GPIO_WR <= 0;
		end
		if(IORQ && CPU_CE && WR && JOYSTICK) begin
			if(WORD) GPIOState <= CPU_DOUT[15:8];
			GPIODout <= CPU_DOUT[7:0];
			GPIO_WR <= 1;
		end
		
// NMI on IORQ
		if(IORQ && CPU_CE && WR && NMI_IORQ_PORT)
			if(PORT_ADDR[0]) NMIonIORQ_HI <= CPU_DOUT;
			else NMIonIORQ_LO <= CPU_DOUT;

// I2C
		if(CPU_CE && IORQ && WR && WORD && I2C_SELECT) i2c_cd <= CPU_DOUT[11:0];

// MPU
		//MPU starts intelligent mode but we only support UART/dumb mode
		//and a few commands to enter that mode
		//Game needs to know it can switch correctly into UART mode
		//Once in UART mode the data is passed directly to the 16550 UART
		if(!rstcount[18]) begin
			mpu_read_ack <= 0;
			mpu_dumb <= 0;
		end
		else if(MPU_PORT & IORQ) begin
			if(PORT_ADDR[0]) begin	// 0=MPU DATA PORT 330h, 1=MPU COMMAND/STATUS PORT 331h
				if(!WR) mpu_data <= {~(mpu_read_ack | ~rx_empty), tx_full, 6'd0}; // &80h read ready, &40h write ready
				if(WR) begin
					mpu_read_ack <= ~mpu_dumb;
					if(CPU_DOUT[7:0] == 8'hFF) mpu_dumb <= 0;
					if(CPU_DOUT[7:0] == 8'h3F) mpu_dumb <= 1;
				end
			end
			else if(!WR) begin
				// We never read MIDI IN so ACK any command requests even ones not supported.
				mpu_data <= 8'hFE;
				mpu_read_ack <= 0;
			end
		end

// CGA color
		if (!rstcount[18]) begin
			{cga_palette, cga_bright, cga_background} <= 0;
			{cpu_page, crt_page} <= 0;
		end else begin
			if(CPU_CE && IORQ && WR && !WORD && CGA_CL) {cga_palette, cga_bright, cga_background} <= CPU_DOUT[5:0];
			if(CPU_CE && IORQ && WR && !WORD && TANDY_PAGE_PORT) {cpu_page, crt_page} <= CPU_DOUT[5:0];
		end

	end

	assign CGA_CL_DATA = {2'b0, cga_palette, cga_bright, cga_background};

	always @ (posedge clk_25) begin
		reg vblnkD;
		s_displ_on <= {s_displ_on[18:0], displ_on};
		// 32 extra bytes at the end of the scanline, for panning
		// 16 extra bytes for CGA modes, as one line = 80 bytes, but SDRAM controller reads 3*32 = 96 bytes
		exline <= vrdon ? ((modecompreq == 2'b01 | (vgatext_s[1] & half_s[1])) ? 4'b1011 : 4'b1111) : (exline - vrden);
		if (vrden) wrdcnt <= wrdcnt - 1'd1;
		if (vblnk) wrdcnt <= 0;

		vblnkD <= vblnk;
		fifo_clear <= vblnk & ~vblnkD;

		vga_attr <= fifo_dout[15:8];		
		flash_on <= (vgaflash_s[1] & fifo_dout[15] & flashcount[5]) | (~oncursor && flashcount[4] && (charcount == cursorpos) && (char_ln >= crs[0][3:0]) && (char_ln <= crs[1][3:0]));
		
		if(!vblnk) begin
			flashbit <= 1;
		end else if(flashbit) begin
			flashcount <= flashcount + 1'b1;
			flashbit <= 0;
		end

		if(RTCDIVEND) RTCDIV25 <= 0;	// real time clock
		else RTCDIV25 <= RTCDIV25 + 1'b1;

		if(!BTN_NMI) rNMI <= 0;		// NMI
		else if(!rNMI[9] && RTCDIVEND) rNMI <= rNMI + 1'b1;	// 1Mhz increment

		if(VGA_VSYNC) vga_hrzpan <= modecompreq[0] ? {scraddr[0], 4'b0} : half_s[1] ? {1'b0, vga_hrzpan_req[2:0], 1'b0} : {2'b0, vga_hrzpan_req[2:0]};
		else if(VGA_HSYNC && ppm_s[1] && (vcount == lcr)) vga_hrzpan <= 4'b0000;

		{VGA_B, VGA_G, VGA_R} <= DAC_COLOR & {18{sdon}};
		VGA_BLANK <= ~sdon;
	end
	
endmodule
