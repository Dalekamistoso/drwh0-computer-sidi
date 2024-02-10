//////////////////////////////////////////////////////////////////////////////////
//
// This file is part of the Next186 Soc PC project
// http://opencores.org/project,next186
//
// Filename: vga.v
// Description: Part of the Next186 SoC PC project, VGA module
//		customized VGA, only modes 3 (25x80x256 text), 13h (320x200x256 graphic) 
//		and VESA 101h (640x480x256) implemented
// Version 1.0
// Creation date: Jan2012
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
//////////////////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module VGA_DAC(
	input CE,
	input WR,
	input [3:0]addr,
	input [7:0]din,
	output [7:0]dout,
	input CLK,
	input VGA_CLK,
	input [7:0]vga_addr,
	input setindex,
	output [17:0]color,
	output reg vgatext = 1'b1,
	output reg vga13 = 1'b1,
	output reg vgaflash = 0,
	output reg [3:0]hrzpan = 0,
	output reg ppm = 0, // pixel panning mode
	input [3:0]ega_attr,
	output [7:0]ega_pal_index
	);

	initial vgatext = 1'b1;
	initial vga13 = 1'b1;
	
	reg [7:0]mask = 8'hff;
	reg [9:0]index = 0;
	reg mode = 0;
	reg [4:0]a0index = 0;
	reg a0data = 0;
	wire [7:0]pal_dout;
	wire [31:0]pal_out;
	wire addr6 = addr == 6;
	wire addr7 = addr == 7;
	wire addr8 = addr == 8;
	wire addr9 = addr == 9;
	wire addr0 = addr == 0;
	reg [5:0]egapal[15:0];
	initial $readmemh("egapal.mem", egapal);
	reg p54s = 1'b0;
	reg [3:0]colsel = 4'b0000;
	wire [5:0]egacolor = egapal[ega_attr]; 
	assign ega_pal_index = {colsel[3:2], p54s ? colsel[1:0] : egacolor[5:4], egacolor[3:0]};
	reg [7:0]regs[4'h4:0];
	reg [7:0]attrib;

	DAC_SRAM vga_dac 
	(
	  .clock_a(CLK), // input clka
	  .wren_a(CE & WR & addr9), // input [0 : 0] wea
	  .address_a(index), // input [9 : 0] addra
	  .data_a(din), // input [7 : 0] dina
	  .q_a(pal_dout), // output [7 : 0] douta
	  .clock_b(VGA_CLK), // input clkb
	  .wren_b(1'b0), // input [0 : 0] web
	  .address_b(vga_addr & mask), // input [7 : 0] addrb
	  .data_b(32'h00000000), // input [31 : 0] dinb
	  .q_b(pal_out) // output [31 : 0] doutb
	);

	assign color = {pal_out[21:16], pal_out[13:8], pal_out[5:0]};
	assign dout = addr6 ? mask : addr7 ? {6'bxxxxxx, mode, mode} : addr8 ? index[9:2] : addr9 ? pal_dout : attrib;

	always @(*) begin
		{p54s, vga13, ppm, vgaflash, vgatext} = {regs[4'h0][7:5], regs[4'h0][3], ~regs[4'h0][0]};
		hrzpan = regs[4'h3][3:0];
		colsel = regs[4'h4][3:0];
	end

	always @(posedge CLK) begin

		if(setindex) a0data <= 0;
		else if(CE && addr0 && WR) a0data <= ~a0data;

		if(CE) begin
			if(addr0) begin
				if(WR) begin					
					if(a0data) begin
						if(!a0index[4]) egapal[a0index[3:0]] <= din[5:0];
						else regs[a0index[3:0]] <= din;
					end else begin
						a0index <= din[4:0];
						attrib <= din[4] ? regs[din[3:0]] : egapal[din[3:0]];
					end
				end
			end
			if(addr6 && WR) mask <= din;
			if(addr7 | addr8) begin
				if(WR) index <= {din, 2'b00};
				mode <= addr8;
			end else if(addr9) index <= index + (index[1:0] == 2'b10 ? 2 : 1);
		end
	end

endmodule


module VGA_CRT(
	input CE,
	input WR,
	input WORD,
	input [15:0]din,
	input addr,
	output [7:0]dout,
	input CLK,
	output reg oncursor,
	output reg [4:0]cursorstart,
	output reg [4:0]cursorend,
	output reg [11:0]cursorpos,
	output reg [15:0]scraddr,
	output reg [7:0]offset = 8'h28,
	output reg [9:0]lcr = 10'h3ff, // line compare register
	output reg [3:0]replncnt,      // line repeat count
	output reg [4:0]line_preset,
	output reg [9:0]vde = 10'h0c7, // last display visible scan line (i.e. 199 in text mode)
	output reg [7:0]hde = 8'd79,
	output reg [9:0]vblank_start,
	output reg [9:0]vtotal,
	output reg [1:0]modecomp, // CGA/Tandy compatible addressing (odd/even lines)

	input               half,

	output reg [10:0]	hcount = 0,
	output reg			hsync,
	output reg			hblnk = 0,

	output reg	[9:0]	vcount = 0,
	output reg			vsync,
	output reg			vblnk = 0,
	output reg  [3:0]   char_ln,
	output reg  [5:0]   char_row,

	input  wire			clk_vga,
	input  wire			ce_vga
	);

	initial offset = 8'h28;
	initial lcr = 10'h3ff;
	initial vde = 10'h0c7;	// 200 lines

	reg [7:0] htotal = 8'h5b;
	reg [7:0] hsync_start = 8'h51;
	reg [7:0] hsync_end;
	reg [7:0] hblank_start; // not used, overscan is blanked
	reg [7:0] hblank_end;

	reg [9:0] vsync_start;

	reg [4:0]idx_buf = 0;
	reg [7:0]regs[5'h18:0];
	reg protect = 0;
	wire [4:0]index = addr ? idx_buf : din[4:0];
	wire [7:0]data = addr ? din[7:0] : din[15:8];
	reg [7:0]dout1;
	assign dout = addr ? dout1 : {3'b000, idx_buf};

	always @(*) begin
		htotal = regs[5'h0];
		hde = regs[5'h1];
		hblank_start = regs[5'h2];
		hblank_end = {regs[5'h2][7:6], regs[5'h5][7], regs[5'h3][4:0]};
		hsync_start = regs[5'h4];
		hsync_end = {regs[5'h4][7:5], regs[5'h5][4:0]};
		vtotal = {regs[5'h7][5], regs[5'h7][0], regs[5'h6]};
		vde = {regs[5'h7][6], regs[5'h7][1], regs[5'h12]};
		line_preset = regs[5'h8][4:0];
		lcr = {regs[5'h9][6], regs[5'h7][4], regs[5'h18]};
		replncnt = {regs[5'h9][3:1], regs[5'h9][0] | regs[5'h9][7]};
		{oncursor, cursorstart} = regs[5'ha][5:0];
		cursorend = regs[5'hb][4:0];
		cursorpos = {regs[5'he][3:0], regs[5'hf]};
		scraddr = {regs[5'hc], regs[5'hd]};
		vsync_start = {regs[5'h7][7], regs[5'h7][2], regs[5'h10]};
		vblank_start = {regs[5'h9][5], regs[5'h7][3], regs[5'h15]};
		protect = regs[5'h11][7];
		offset = regs[5'h13];
		modecomp = ~regs[5'h17][1:0];
	end

	always @(posedge CLK) begin
		if(CE && WR) begin
			if(!addr) idx_buf <= din[4:0];
			if(addr || WORD) begin
				if (!protect || (index > 5'h7 && index != 5'h10)) // protect vsync, too for Defender of the Crown CGA
					regs[index] <= data;
				else if (index == 5'h7)
					regs[5'h7][4] <= data[4]; // LCR bit 8 is not protected
			end
		end
		dout1 <= regs[idx_buf];
	end

	// Synchronizers
	reg [1:0] half_s;
	always @(posedge clk_vga) half_s <= {half_s[0], half};

	//******************************************************************//
	// This logic describes a 11-bit horizontal position counter.       //
	//******************************************************************//
	wire [8:0] hchar = half_s[1] ? hcount[10:4] : hcount[9:3];
	wire       hch_en = half_s[1] ? hcount[3:0] == 4'b1111 : hcount[2:0] == 3'b111;

	always @(posedge clk_vga)
		if(ce_vga) begin
			hcount <= hcount + 1'd1;
			if (hch_en) begin
				if (hchar == htotal + 4'd5) begin
					hcount <= 0;
					hblnk <= 0;
					hsync <= 0;
				end
				if (hchar == hde) hblnk <= 1;
				if (hchar == hsync_start) hsync <= 1;
				if (hchar == hsync_end) hsync <= 0;
			end
		end

	//******************************************************************//
	// This logic describes a 10-bit vertical position counter.         //
	//******************************************************************//
	always @(posedge clk_vga)
		if(ce_vga && hch_en && hchar == htotal + 4'd5) begin
			vcount <= vcount + 1'd1;
			char_ln <= char_ln + 1'd1;
			if (char_ln == replncnt) begin
				char_ln <= 0;
				char_row <= char_row + 1'd1;
			end
			if (vcount == vtotal) begin
				char_ln <= line_preset;
				vcount <= 0;
				vblnk <= 0;
				vsync <= 0;
				char_row <= 0;
			end
			if (vcount == vde || vcount == vblank_start) vblnk <= 1; // overscan is not implemented
			if (vcount == vsync_start) vsync <= 1;
			if (vcount == vsync_start + 2'd2) vsync <= 0;
		end

endmodule

module VGA_SC(
	input CE,
	input WR,
	input WORD,
	input [15:0]din,
	output [7:0]dout,
	input addr,
	input CLK,
	output reg half,
	output reg oddeven,
	output reg planarreq,
	output reg[3:0]wplane
	);

	reg [2:0]idx_buf = 0;
	reg [7:0]regs[4:0];
	wire [2:0]index = addr ? idx_buf : din[2:0];
	wire [7:0]data = addr ? din[7:0] : din[15:8];
	reg [7:0]dout1;
	assign dout = addr ? dout1 : {5'b00000, idx_buf};

	always @(*) begin
		half = regs[1][3];
		wplane = regs[2][3:0];
		oddeven = ~regs[4][2];
		planarreq = ~regs[4][3];
	end

	always @(posedge CLK) begin 
		if(CE && WR) begin
			if(!addr) idx_buf <= din[2:0];
			if(addr || WORD) begin
				regs[index] <= data;
			end
		end
		dout1 <= regs[idx_buf];
	end
endmodule


module VGA_GC(
	input CE,
	input WR,
	input WORD,
	input [15:0]din,
	output [7:0]dout,
	input addr,
	input CLK,
	output reg [1:0]rplane = 2'b00,
	output reg[7:0]bitmask = 8'b11111111,
	output reg [2:0]rwmode = 3'b000,
	output reg [3:0]setres = 4'b0000,
	output reg [3:0]enable_setres = 4'b0000,
	output reg [1:0]logop = 2'b00,
	output reg [3:0]color_compare = 4'b0000,
	output reg [3:0]color_dont_care = 4'b1111,
	output reg [2:0]rotate_count = 3'b000,
	output reg shiftload
	);

	initial bitmask = 8'b11111111;
	initial color_dont_care = 4'b1111;
	
	reg [3:0]idx_buf = 0;
	reg [7:0]regs[8:0];
	wire [3:0]index = addr ? idx_buf : din[3:0];
	wire [7:0]data = addr ? din[7:0] : din[15:8];
	reg [7:0]dout1;
	assign dout = addr ? dout1 : {4'b0000, idx_buf};

	always @(*) begin
		setres = regs[5'h0][3:0];
		enable_setres = regs[5'h1][3:0];
		color_compare = regs[5'h2][3:0];
		{logop, rotate_count} = regs[5'h3][4:0];
		rplane = regs[5'h4][1:0];
		rwmode = {regs[5'h5][3], regs[5'h5][1:0]};
		shiftload = regs[5'h5][5];
		color_dont_care = regs[5'h7][3:0];
		bitmask = regs[5'h8];
	end

	always @(posedge CLK) begin
		if(CE && WR) begin
			if(!addr) idx_buf <= din[3:0];
			if(addr || WORD) begin
				regs[index] <= data;
			end
		end
		dout1 <= regs[idx_buf];
	end
endmodule
