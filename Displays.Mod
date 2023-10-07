(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE Displays;	(* pjm *)

IMPORT P := ObxPal;

CONST
		(** formats for Transfer.  value = bytes per pixel. *)
	index8* = 1; color565* = 2; color888* = 3; color8888* = 4;

		(** operations for Transfer. *)
	get* = 0; set* = 1;
	
		(** color components. *)
	red* = 00FF0000H; green* = 0000FF00H; blue* = 000000FFH;
	
	trans* = SHORT(80000000H);	(** transparency for Mask. *)
	invert* = 40000000H;	(** inverting. *)
(*
	alpha = 0C0000000H;	(** alpha blending. *)
*)

	BufSize = 65536;
	
TYPE
  FrameBuffer* = POINTER TO ARRAY OF BYTE;
  Pattern* = POINTER TO ARRAY OF CHAR; // w = buf[0], h = buf[1], pixmap = buf[2..]
  Display* = POINTER TO RECORD
			width*, height*: LONGINT;	(** dimensions of visible display. *)
			offscreen*: LONGINT;	(** number of non-visible lines at the bottom of the display. *)
			format*: LONGINT;	(** format for Transfer. *)
			unit*: LONGINT;	(** approximate square pixel size = unit/36000 mm. *)
			fb*: FrameBuffer;
			fbstride: LONGINT;
  		END;
  		
  	PROCEDURE Move*( IN from: ARRAY OF CHAR; fromoff: LONGINT; VAR to: ARRAY OF CHAR; tooff, w: LONGINT);
  	VAR i, lf: LONGINT;
  	BEGIN
  	  lf := LEN(from);
      FOR i := 0 TO w-1 DO
        IF fromoff+i >= lf THEN 
          to[tooff+i] := 0X
        ELSE
          to[tooff+i] := from[fromoff+i];
        END
      END
  	END Move;
  	
  	PROCEDURE Move2( IN from: ARRAY OF CHAR; fromoff: LONGINT; VAR to: ARRAY OF BYTE; tooff, w: LONGINT);
  	VAR i: LONGINT;
  	BEGIN
      FOR i := 0 TO w-1 DO
        to[tooff+i] := ORD(from[fromoff+i]);
      END;
  	END Move2;
  	
  	PROCEDURE Move3( IN from: ARRAY OF BYTE; fromoff: LONGINT; VAR to: ARRAY OF CHAR; tooff, w: LONGINT);
  	VAR i: LONGINT;
  	BEGIN
      FOR i := 0 TO w-1 DO
        to[tooff+i] := CHR(from[fromoff+i]);
      END;
  	END Move3;
  	
		(** Transfer a block of pixels in "raw" display format to (op = set) or from (op = get) the display.  
		Pixels in the rectangular area are transferred from left to right and top to bottom.  The pixels are 
		transferred to or from "buf", starting at "ofs".  The line byte increment is "stride", which may be 
		positive, negative or zero. *)
		PROCEDURE (SELF: Display) Transfer*(VAR buf: ARRAY OF CHAR; ofs, stride, x, y, w, h, op: LONGINT);
		VAR dispidx, i, w0, h0: LONGINT;
		BEGIN
			IF w > 0 THEN
				ASSERT(SELF.fb # NIL);
				w0 := w; h0 := h;
				w := w * SELF.format;	(* convert to bytes *)
				dispidx := ((y*SELF.width)+x)*SELF.format;
				CASE op OF
					set:
            WHILE h > 0 DO
              ASSERT((dispidx >= 0) & (dispidx+w <= LEN(SELF.fb)));	(* index check *)
              Move2(buf, ofs, SELF.fb, dispidx, w);
              INC(ofs, stride); INC(dispidx, SELF.fbstride);
              DEC(h)
            END
            P.update(x,y,w0,h0);
					|get:
						WHILE h > 0 DO
							ASSERT((ofs >= 0) & (ofs+w <= LEN(buf)));	(* index check *)
							Move3(SELF.fb, dispidx, buf, ofs, w);
							INC(ofs, stride); INC(dispidx, SELF.fbstride);
							DEC(h)
						END
					ELSE (* skip *)
				END
			END
		END Transfer;
		
		(** Fill a rectangle in color "col". *)
		PROCEDURE (SELF: Display) Fill*(col, x, y, w, h: LONGINT);
		BEGIN
			Fill0(SELF, col, x, y, w, h)
		END Fill;
		
		(** Equivalent to Fill(col, x, y, 1, 1). *)
		PROCEDURE (SELF: Display) Dot*(col, x, y: LONGINT);
		VAR t, c: SET; buf: ARRAY 4 OF CHAR;
		BEGIN (*{EXCLUSIVE}*)
			IF col >= 0 THEN	(* opaque or invert *)
				CASE SELF.format OF
					index8:
						c := BITS(SELF.ColorToIndex(col))
					|color565:
						c := BITS(ASH(col, 15-23)) * {11..15} +
								 BITS(ASH(col, 10-15)) * {5..10} +
								 BITS(ASH(col, 4-7)) * {0..4}
					|color888, color8888:
						c := BITS(col MOD 1000000H) // restrict col to lower three bytes
				END;
				IF ASH(col, 1) < 0 THEN	(* invert *)
					IF c = {} THEN c := {0..31} END;
					SELF.Transfer(buf, 0, SELF.format, x, y, 1, 1, get);
					NUMBER(t,buf);
					c := t / c
				END;
				BYTES(buf,c);
				SELF.Transfer(buf, 0, SELF.format, x, y, 1, 1, set)
			END
		END Dot;
		
		(** Transfer a block of pixels from a 1-bit mask to the display.  Pixels in the rectangular 
		    area are transferred from left to right and top to bottom.  The pixels are transferred from 
		    "pat", starting at bit offset "bitofs".  The line byte increment is "stride", which may be 
		    positive, negative or zero. "fg" and "bg" specify the colors for value 1 and 0 pixels 
		    respectively. "bitofs" already includes the 16 bits of the first w/h bytes. *)
		PROCEDURE (SELF: Display) Mask*(VAR pat: Pattern; bitofs, stride, fg, bg, x, y, w, h: LONGINT);
		VAR patoff, i: LONGINT; s, fgc, bgc, t: SET; b: ARRAY 4 OF CHAR;
		BEGIN
			IF (w > 0) & (h > 0) THEN
				CASE SELF.format OF
					index8:
						IF fg >= 0 THEN fgc := BITS(SELF.ColorToIndex(fg)) END;
						IF bg >= 0 THEN bgc := BITS(SELF.ColorToIndex(bg)) END
					|color565:
						fgc := BITS(ASH(fg, 15-23)) * {11..15} +
								BITS(ASH(fg, 10-15)) * {5..10} +
								BITS(ASH(fg, 4-7)) * {0..4};
						bgc := BITS(ASH(bg, 15-23)) * {11..15} +
								BITS(ASH(bg, 10-15)) * {5..10} +
								BITS(ASH(bg, 4-7)) * {0..4}
					|color888, color8888:
						fgc := BITS(fg MOD 1000000H);
						bgc := BITS(bg MOD 1000000H)
				END;
				IF (ASH(fg, 1) < 0) & (fgc = {}) THEN fgc := {0..31} END;	(* invert special *)
				IF (ASH(bg, 1) < 0) & (bgc = {}) THEN bgc := {0..31} END;	(* invert special *)
				patoff := bitofs DIV 32 * 4;	 // offset to pat param, rounded to the byte in which bitofs points
				bitofs := bitofs MOD 32; stride := stride*8;
				LOOP
          Move(pat, patoff, b, 0, 4); NUMBER(s,b); i := bitofs;
					LOOP
						IF (i MOD 32) IN s THEN
							IF fg >= 0 THEN
								IF ASH(fg, 1) < 0 THEN	(* invert *)
									SELF.Transfer(b, 0, SELF.format, x+i-bitofs, y, 1, 1, get);
									NUMBER(t,b);
									t := t / fgc
								ELSE
									t := fgc
								END;
								BYTES(b,t);
								SELF.Transfer(b, 0, SELF.format, x+i-bitofs, y, 1, 1, set)
							END
						ELSE
							IF bg >= 0 THEN
								IF ASH(bg, 1) < 0 THEN	(* invert *)
									SELF.Transfer(b, 0, SELF.format, x+i-bitofs, y, 1, 1, get);
									NUMBER(t,b);
									t := t / bgc
								ELSE
									t := bgc
								END;
								BYTES(b,t);
								SELF.Transfer(b, 0, SELF.format, x+i-bitofs, y, 1, 1, set)
							END
						END;
						INC(i);
						IF i-bitofs = w THEN EXIT END;
						IF i MOD 32 = 0 THEN Move(pat, patoff+i DIV 8, b, 0, 4); NUMBER(s,b) END
					END; // inner LOOP
					DEC(h);
					IF h = 0 THEN EXIT END;
					INC(y); INC(bitofs, stride);
					IF (bitofs >= 32) OR (bitofs < 0) THEN	(* moved outside s *)
						INC(patoff, bitofs DIV 32 * 4); bitofs := bitofs MOD 32
					END
				END // outer LOOP
			END // IF w,h > 0
		END Mask;
		
		(** Copy source block sx, sy, w, h to destination dx, dy.  Overlap is allowed. *)
		PROCEDURE (SELF: Display) Copy*(sx, sy, w, h, dx, dy: LONGINT);
		BEGIN
			Copy0(SELF, sx, sy, w, h, dx, dy)
		END Copy;
		
		(** Map a color value to an 8-bit CLUT index.  Only used if format = index8. *)
		PROCEDURE (SELF: Display) ColorToIndex*(col: LONGINT): LONGINT;
		BEGIN
				(* default implementation is not very useful and should be overridden. *)
			RETURN ORD( 
					BITS(ASH(col, 7-23)) * {5..7} +
					BITS(ASH(col, 4-15)) * {2..4} +
					BITS(ASH(col, 1-7)) * {0..1})
		END ColorToIndex;
		
		(** Map an 8-bit CLUT index to a color value.  Only used if format = index8. *)
		PROCEDURE (SELF: Display) IndexToColor*(index: LONGINT): LONGINT;
		BEGIN
				(* default implementation is not very useful and should be overridden. *)
			RETURN
					ASH(ORD(BITS(index) * {5..7}), 23-7) +
					ASH(ORD(BITS(index) * {2..4}), 15-4) +
					ASH(ORD(BITS(index) * {0..1}), 7-1)
		END IndexToColor;
		
		(** Initialize a linear frame buffer for Transfer. *)
		PROCEDURE (SELF: Display) InitFrameBuffer*(buf: FrameBuffer);
		BEGIN
			ASSERT(SELF.width*(SELF.height+SELF.offscreen)*SELF.format <= LEN(buf));
			SELF.fb := buf; SELF.fbstride := SELF.width*SELF.format;
			// ASSERT(ASH(SELF.fblow, -31) = ASH(SELF.fbhigh, -31), 100)	(* same sign, for index check in Transfer *)
		END InitFrameBuffer;
				

VAR
	main*: Display;
	buf: POINTER TO ARRAY OF CHAR;

PROCEDURE Fill0(d: Display; col, x, y, w, h: LONGINT);
VAR j, bufoff, w0, h0, s: LONGINT; t, c: SET; invert: BOOLEAN; b: ARRAY 4 OF CHAR;
BEGIN (*{EXCLUSIVE}*)
	IF (w > 0) & (h > 0) & (col >= 0) THEN	(* opaque or invert *)
		invert := ASH(col, 1) < 0;
		IF buf = NIL THEN NEW(buf, BufSize) END;
		CASE d.format OF
			index8:
				s := 4; col := d.ColorToIndex(col);
				c := BITS(ASH(col, 24) + ASH(col, 16) + ASH(col, 8) + col)
			|color565:
				s := 4;
				col := ORD( 
						BITS(ASH(col, 15-23)) * {11..15} +
						BITS(ASH(col, 10-15)) * {5..10} +
						BITS(ASH(col, 4-7)) * {0..4});
				c := BITS(ASH(col, 16) + col MOD 10000H)
			|color888:
				s := 3; c := BITS(col MOD 1000000H)
			|color8888:
				s := 4; c := BITS(col MOD 1000000H)
		END;
		w0 := w*d.format; h0 := (LEN(buf^)-3) DIV w0;	(* -3 for 32-bit loops below *)
		ASSERT(h0 > 0);
		IF h < h0 THEN h0 := h END;
		IF ~invert THEN
			bufoff := 0;
			BYTES(b,c); 
			FOR j := 0 TO (w0*h0-1) DIV s DO 
  			Move(b,0,buf,bufoff,4); 
  			INC(bufoff, s) 
  		END
		ELSE
			IF c = {} THEN c := {0..31} END
		END;
		LOOP
			IF invert THEN
				d.Transfer(buf^, 0, w0, x, y, w, h0, get);
				bufoff := 0;
				FOR j := 0 TO (w0*h0-1) DIV s DO
  				Move(buf,bufoff,b,0,4); NUMBER(t,b);
  				BYTES(b, t/c); Move(b,0,buf,bufoff,4); INC(bufoff, s)
				END
			END;
			d.Transfer(buf^, 0, w0, x, y, w, h0, set);
			DEC(h, h0);
			IF h <= 0 THEN EXIT END;
			INC(y, h0);
			IF h < h0 THEN h0 := h END
		END
	END
END Fill0;

PROCEDURE Copy0(d: Display; sx, sy, w, h, dx, dy: LONGINT);
VAR w0, h0, s: LONGINT;
BEGIN (*{EXCLUSIVE}*)
	IF (w > 0) & (h > 0) THEN
		IF buf = NIL THEN NEW(buf, BufSize) END;
		w0 := w*d.format; h0 := LEN(buf^) DIV w0;
		ASSERT(h0 > 0);
		IF (sy >= dy) OR (h <= h0) THEN
			s := 1
		ELSE
			s := -1; INC(sy, h-h0); INC(dy, h-h0)
		END;
		LOOP
			IF h < h0 THEN
				IF s = -1 THEN INC(sy, h0-h); INC(dy, h0-h) END;
				h0 := h
			END;
			d.Transfer(buf^, 0, w0, sx, sy, w, h0, get);
			d.Transfer(buf^, 0, w0, dx, dy, w, h0, set);
			DEC(h, h0);
			IF h <= 0 THEN EXIT END;
			INC(sy, s*h0); INC(dy, s*h0)
		END
	END
END Copy0;

BEGIN
	buf := NIL
END Displays.

(**
o The display origin (0,0) is at the top left.
o The display is "width" pixels wide and "height" pixels high.
o The offscreen area is a possibly empty extension below the visible display.  Its height is "offscreen" pixels.
o Rectangles are specified with the top left corner as pinpoint.
o No clipping is performed.
o The offset and stride parameters must always specify values inside the supplied buffer (otherwise results undefined).
o Accessing coordinates outside the display space (including offscreen) is undefined.
o "Undefined" in this case means a trap could occur, or garbage can be displayed, but memory will never be corrupted.
o Colors are 888 truecolor values represented in RGB order with B in the least significant byte.  The top 2 bits of a 32-bit color value are used for flags.  The other bits are reserved.
o The "invert" flag means the destination color is inverted with the given color.  The effect is implementation-defined, but must be reversible with the same color.  Usually an XOR operation is performed.
o The "trans" flag means the color is transparent and drawing in this color has no effect.  It is defined for Mask only.
o The transfer "format" should be chosen close to the native framebuffer format for efficiency.
o Transfer uses raw framebuffer values, and does not support color flags.
o A concrete Display must implement at least the Transfer function, or initialize a linear frame buffer and call the InitFrameBuffer method.
o An optimized Display driver should override all the primitives with accellerated versions.
o An "index8" display uses a fixed palette and map a truecolor value to an equivalent color in the palette.
o The palette can be chosen freely by a concrete 8-bit Display, which should override the ColorToIndex and IndexToColor methods.  These methods are not defined for other formats.
o The default ColorToIndex method assumes a direct-mapped palette with 3 bits each for red and green, and 2 bits for blue.
o Palette animation is not supported.
*)

(*
to do:
1 ReplMask
1 include OGLDisplay functionality (state abstraction)
1 include other primitives: Line, ReplMask, etc.
2 window manager and cursor?
2 pan to offscreen area
3 how to write a new driver
*)
