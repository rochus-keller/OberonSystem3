(* OBERON System 3, Release 2.2.

Copyright 1997 Team of the Institute of Computer Systems of ETH Zuerich,
ETH Center, CH-8092 Zuerich, e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract.  The full text can be requested from the 
above-mentioned address, or downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE Display;	(* pjm *)

(* Native Oberon SVGA display driver, pjm 20.04.98
    Hicolor version PDR 7.5.99 *)

IMPORT SYSTEM, Objects, Kernel;

CONST
	BG* = 0; FG* = 15;
	
	replace* = 0;	(** replace destination. *)
	paint* = 1;	(** paint over destination.  *)
	invert* = 2;	(** invert destination. *)
	
	remove* = 0; suspend* = 1; restore* = 2; newprinter* = 3; (** ControlMsg id. *)
	reduce* = 0; extend* = 1; move* = 2; (** ModifyMsg id. *)
	display* = 0; state* = 1; (** ModifyMsg mode. *)
	screen* = 0; printer* = 1; (** DisplayMsg device *)
	full* = 0; area* = 1; contents* = 2; (** DisplayMsg id. *)
	get* = 0; set* = 1; reset* = 2; (** SelectMsg id. *)
	drop* = 0; integrate* = 1; (** ConsumeMsg id. *)
	
	unknown* = 0; index8* = 8; color555* = 16; color565* = 17; color664* = 18; color888* = 24; color8888* = 32;

	WinSize = 10000H;
	BufSize = 10000H;
	
	VesaAdr = 0E0000000H;	(* where MapVesa=1 maps *)
	LinearSize = 4*1024*1024;	(* amount to map in *)

TYPE
	Color* = LONGINT;
	
	Pattern* = LONGINT;
	PatternPtr = POINTER TO RECORD
		w, h: CHAR;
		pixmap: ARRAY 8192 OF CHAR
	END;
	List = POINTER TO ListDesc;
	ListDesc = RECORD
		next: List;
		pat: PatternPtr
	END;

	Frame* = POINTER TO FrameDesc;	(** Base type of all displayable objects. *)
	FrameDesc* = RECORD (Objects.ObjDesc)
		next*, dsc*: Frame;	(** Sibling, child pointers. *)
		X*, Y*, W*, H*: INTEGER	(** Coordinates. *)
	END;

	FrameMsg* = RECORD (Objects.ObjMsg)	(** Base type of messages sent to frames. *)
		F*: Frame; (*target*)	(** Message target, NIL for broadcast. *)
		x*, y*: INTEGER;	(** Message origin. *)
		res*: INTEGER	(** Result code: <0 = error or no response, >=0 response. *)
	END;

	ControlMsg* = RECORD (FrameMsg)
		id*: INTEGER	(** remove, suspend, restore. *)
	END;

	ModifyMsg* = RECORD (FrameMsg)	(** Change coordinates in container frame. *)
		id*: INTEGER;	(** reduce, extend, move. *)
		mode*: INTEGER;	(** Modes display, state. *)
		dX*, dY*, dW*, dH*: INTEGER;	(** Change from old coordinates (delta). *)
		X*, Y*, W*, H*: INTEGER	(** New coordinates. *)
	END;

	DisplayMsg* = RECORD (FrameMsg)	(** Display a frame, a part of it or its contents. *)
		device*: INTEGER;	(** screen, printer *)
		id*: INTEGER;	(** full, area, contents. *)
		u*, v*, w*, h*: INTEGER	(** Area to be restored. *)
	END;

	LocateMsg* = RECORD (FrameMsg)	(** Locate frame in display space. *)
		loc*: Frame;	(** Result. *)
		X*, Y*: INTEGER;	(** Absolute location. *)
		u*, v*: INTEGER	(** Relative coordinates in loc. *)
	END;

	SelectMsg* = RECORD (FrameMsg)	(** Selection control. *)
		id*: INTEGER;	(** get, set, reset. *)
		time*: LONGINT;	(** Time of selection. *)
		sel*: Frame;	(** Parent of selection. *)
		obj*: Objects.Object	(** List of objects involved, linked with slink. *)
	END;

	ConsumeMsg* = RECORD (FrameMsg)	(** Drop, integrate frames. *)
		id*: INTEGER;	(** drop, integrate. *)
		u*, v*: INTEGER;	(** Relative coordinates in destination when drop. *)
		obj*: Objects.Object	(** List of objects to be consumed, linked with slink. *)
	END;

	MsgProc* = PROCEDURE (VAR M: FrameMsg);

	SwitchProc = PROCEDURE (bank: LONGINT);
	
	Buffer = RECORD bytes: ARRAY BufSize OF CHAR END;
	
VAR
	Unit*: LONGINT; (** RasterUnit = Unit/36000 mm *)
	
	Left*, (** Left margin of black-and-white screen. *)
	ColLeft*, (** Left margin of secondary display, often same as Left. *)
	Bottom*, (** Bottom of primary map. *)
	UBottom*, (** Bottom of offscreen area (negative), 0 if not supported. *)
	Width*, (** Display width. *)
	Height*: INTEGER; (** Display height. *)
	arrow*, 	(** Oberon cursor. *)
	star*, 	(** Star marker to mark documents and viewers. *)
	cross*, 	(** Insertion marker. *)
	downArrow*, 	(** Marker to indicate disk operation. *)
	hook*,	(** Text caret pattern. *)
	grey0*, grey1*, grey2*, ticks*, solid*: Pattern;	(** Simulated grey levels. *)
	Broadcast*: MsgProc;	(** Message broadcast to all frames in the display space. *)
	
	palette: ARRAY 256 OF LONGINT;
	depth: LONGINT;
	displayWidth, displayHeight, displayHeight1, maxY: LONGINT;
	clipX1, clipY1, clipX2, clipY2: LONGINT;	(* bottom left corner & top right corner, in Oberon coordinates *)
	pattern: List;
	buffer: POINTER TO Buffer;
	curBank: LONGINT;
	switch: SwitchProc;	(* switch to window "bank". *)
	base, linearbase: LONGINT;

	(*PDR:*)
	truecol: LONGINT;
	colmap: ARRAY 256 OF LONGINT;	(* identity mapping (256-color) or soft palette (hicolor, truecolor) *)
	bytesPerScan, bytesPerPixel: LONGINT;

(* Switch procedures. *)

(* SwitchS3Aurora64V - Aurora64V+ in Compaq laptop & Trio64V+ in STB PowerGraph 64 *)

PROCEDURE SwitchS3Aurora64V(bank: LONGINT);
VAR b: SET;  p: LONGINT;
BEGIN
	curBank := bank;
	SYSTEM.PORTOUT(3C4H, 4X);
	SYSTEM.PORTIN(3C5H, SYSTEM.VAL(CHAR, b));
	IF ~(3 IN b) THEN bank := bank*4 END;
	
	SYSTEM.PORTIN(3CCH, SYSTEM.VAL(CHAR, b));
	IF 0 IN b THEN p := 3D4H ELSE p := 3B4H END;
	
	SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 4838H));
	SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, 0A539H));

	SYSTEM.PORTIN(3CCH, SYSTEM.VAL(CHAR, b));
	IF 0 IN b THEN p := 3D4H ELSE p := 3B4H END;

	SYSTEM.PORTOUT(p, 6AX);
	SYSTEM.PORTIN(p+1, SYSTEM.VAL(CHAR, b));
	b := SYSTEM.LSH((b * {6,7}) + SYSTEM.VAL(SET, bank), 8) + SYSTEM.VAL(SET, 6AH);
	SYSTEM.PORTOUT(p, SYSTEM.VAL(INTEGER, b))
END SwitchS3Aurora64V;

(* SwitchET4000 - ET4000 (vgadoc) *)

PROCEDURE SwitchET4000(bank: LONGINT);
BEGIN
	curBank := bank;
	SYSTEM.PORTOUT(3CDH, CHR(bank MOD 16 * 16 + bank MOD 16))	(* 64k r/w bank *)
END SwitchET4000;

(* SwitchS3801 - S3 801/5 & 928 (vgadoc) *)

PROCEDURE SwitchS3801(bank: LONGINT);
VAR s: SET;
BEGIN
	curBank := bank;
	SYSTEM.PORTOUT(3D4H, 35X);
	SYSTEM.PORTIN(3D5H, SYSTEM.VAL(CHAR, s));
	SYSTEM.PORTOUT(3D4H, SYSTEM.VAL(INTEGER, SYSTEM.LSH(s * {4..7} + 
		SYSTEM.VAL(SET, bank MOD 16), 8) + SYSTEM.VAL(SET, 35H)));
	SYSTEM.PORTOUT(3D4H, 51X);
	SYSTEM.PORTIN(3D5H, SYSTEM.VAL(CHAR, s));
	SYSTEM.PORTOUT(3D4H, SYSTEM.VAL(INTEGER, SYSTEM.LSH(s * {0..1, 4..7} + 
		SYSTEM.VAL(SET, ASH(bank DIV 16, 2)), 8) + SYSTEM.VAL(SET, 51H)))
END SwitchS3801;

(* SwitchFireGL - Diamond FireGL (512k only). *)

PROCEDURE SwitchFireGL(bank: LONGINT);
VAR s: SET;  save: CHAR;
BEGIN
	curBank := bank;
	SYSTEM.PORTIN(3CEH, save);
	SYSTEM.PORTOUT(3CEH, 9X);
	SYSTEM.PORTIN(3CFH, SYSTEM.VAL(CHAR, s));
	SYSTEM.PORTOUT(3CFH, SYSTEM.VAL(CHAR, s - {0..2} + SYSTEM.VAL(SET, bank) * {0..2}));
	SYSTEM.PORTOUT(3CEH, save)
END SwitchFireGL;

(* SwitchGD542x - Cirrus Logic 542x (Gitsels' machine). *)

PROCEDURE SwitchGD542x(bank: LONGINT);
VAR a: ARRAY 5 OF CHAR;
BEGIN
	curBank := bank;
	SYSTEM.PORTIN(3C4H, a[0]);  SYSTEM.PORTIN(3D4H, a[1]);
	SYSTEM.PORTIN(3B4H, a[2]);  SYSTEM.PORTIN(3CEH, a[3]);
	
	SYSTEM.PORTIN(3CEH, a[4]);
	SYSTEM.PORTOUT(3CEH, SHORT(ASH(16*bank, 8) + 9));
	SYSTEM.PORTOUT(3CEH, a[4]);
	
	SYSTEM.PORTIN(3CEH, a[3]);  SYSTEM.PORTIN(3B4H, a[2]);
	SYSTEM.PORTIN(3D4H, a[1]);  SYSTEM.PORTIN(3C4H, a[0])
END SwitchGD542x;

(* SwitchMach32 - ATI Mach32 family. *)

PROCEDURE SwitchMach32(bank: LONGINT);
VAR s: SET;
BEGIN
	curBank := bank;
	s := SYSTEM.VAL(SET, (bank MOD 16) * 22H);
	SYSTEM.PORTOUT(1CEH, 0B2X);
	SYSTEM.PORTOUT(1CFH, SYSTEM.VAL(CHAR, SYSTEM.LSH(s, -8) + (s * {0..7})));
	SYSTEM.PORTOUT(1CEH, 0AEX);
	SYSTEM.PORTIN(1CFH, SYSTEM.VAL(CHAR, s));
	SYSTEM.PORTOUT(1CEH, 0AEX);
	SYSTEM.PORTOUT(1CFH, SYSTEM.VAL(CHAR, (s * {4..7}) + SYSTEM.VAL(SET, ASH(bank, -4)*5)))
END SwitchMach32;

(* SwitchTrident9xxx - Switch to Trident 9xxx family - 9000C and higher 
	Harold L. Weaver <hweaver@pdx.oneworld.com> 
	Tested on IBM Thinkpad 760ED with a Trident Cyber9385 *)

PROCEDURE SwitchTrident9xxx(bank: LONGINT);
BEGIN
	curBank := bank;
	SYSTEM.PORTOUT(3D8H, CHR(bank));
	SYSTEM.PORTOUT(3D9H, CHR(bank))
END SwitchTrident9xxx;

(* SwitchLinear - Switch to fixed linear aperture *)

PROCEDURE SwitchLinear(bank: LONGINT);
BEGIN
	curBank := bank;
	base := linearbase + WinSize*bank
END SwitchLinear;

(*PDR:*)
PROCEDURE SetColor*(col: Color; red, green, blue: LONGINT);	(* 0 <= col, red, green, blue < 256 *)
VAR ch: CHAR;
BEGIN
	palette[col] := ASH(ASH(red, 8) + green, 8) + blue;
	CASE truecol OF
		0:	(* indexed *)
			colmap[col] := col;
			IF (col = 0) OR (col = 15) THEN	(* either 0 or 15 must be black.  set the border to black. *)
					(* note: the S3 uses the palette for the border colour too *)
				SYSTEM.PORTIN(3DAH, ch);
				SYSTEM.PORTOUT(3C0H, 11X);
				IF (red = 0) & (green = 0) & (blue = 0) THEN SYSTEM.PORTOUT(3C0H, CHR(col))
				ELSE SYSTEM.PORTOUT(3C0H, CHR(15-col))
				END;
				SYSTEM.PORTOUT(3C0H, 20X)
			END;
			SYSTEM.PORTOUT(3C8H, CHR(col));
			SYSTEM.PORTOUT(3C9H, CHR(red DIV 4));
			SYSTEM.PORTOUT(3C9H, CHR(green DIV 4));
			SYSTEM.PORTOUT(3C9H, CHR(blue DIV 4))
		|1:	(* 565 hicolor *)
			colmap[col] := ASH(ASH(ASH(red, -3), 6) + ASH(green, -2), 5) + ASH(blue, -3)
		|2:	(* 888 truecolor *)
			colmap[col] := ASH(ASH(red, 8) + green, 8) + blue
	END
END SetColor;

(** Retrieve color palette entry or color components. 0 <= red, green, blue < 256. *)
PROCEDURE GetColor*(col: Color; VAR red, green, blue: INTEGER);
BEGIN
	IF col >= 0 THEN col := palette[col] END;
	red := SHORT(ASH(col, -16) MOD 256);
	green := SHORT(ASH(col, -8) MOD 256);
	blue := SHORT(col MOD 256)
END GetColor;

(** Return color with specified components. 0 <= red, green, blue < 256. *)
PROCEDURE RGB*(red, green, blue: LONGINT): Color;
BEGIN
	RETURN MIN(LONGINT) + ASH(red, 16) + ASH(green, 8) + blue
END RGB;

(** Returns the number of bits per pixel for the given x coordinate. Typical values are 1, 4, 8, 24. *)
PROCEDURE Depth*(x: LONGINT): INTEGER;
BEGIN
	RETURN SHORT(depth)
END Depth;

PROCEDURE TrueColor*(x: LONGINT): BOOLEAN;
BEGIN
	RETURN TRUE
END TrueColor;

(** Get the current clip rectangle. *)
PROCEDURE GetClip*(VAR x, y, w, h: INTEGER);
BEGIN
	x := SHORT(clipX1);  y := SHORT(clipY1);
	w := SHORT(clipX2-clipX1+1);  h := SHORT(clipY2-clipY1+1)
END GetClip;

(** Set the new clipping rectangle. *)
PROCEDURE SetClip*(x, y, w, h: LONGINT);
BEGIN
	clipX1 := x;  clipY1 := y;
	clipX2 := clipX1+w-1;  clipY2 := clipY1+h-1
END SetClip;
	
(** Intersect with current clip rectangle resulting in a new clip rectangle. *)
PROCEDURE AdjustClip*(x, y, w, h: LONGINT);
VAR x2, y2: LONGINT;
BEGIN
	x2 := x + w - 1;  y2 := y + h - 1;
	IF x > clipX1 THEN clipX1 := x END;
	IF y > clipY1 THEN clipY1 := y END;
	IF x2 < clipX2 THEN clipX2 := x2 END;
	IF y2 < clipY2 THEN clipY2 := y2 END
END AdjustClip;

(** Reset the current clipping rectangle to the whole display, including offscreen area. *)
PROCEDURE ResetClip*;
BEGIN
	clipX1 := 0;  clipY1 := UBottom;
	clipX2 := displayWidth-1;  clipY2 := maxY
END ResetClip;
	
(*PDR:
	Translate a Color value 

	col >= 0 => index through colmap
	col < 0 & truecol = 0 => undefined
	col < 0 & truecol = 1 => translate 888 to 565
	col < 0 & truecol = 2 => keep lower 24 bits
	
	Note: when mode = invert & truecol # 0 & col = FG, the caller sets col to 80FFFFFFH.
	This is a special case for backward compatability with older viewers to invert using FG.
*)

PROCEDURE -TransColor(col: Color): LONGINT;
CODE {SYSTEM.i386}
	POP EAX
	CMP EAX, 0
	JGE index
	AND EAX, 0FFFFFFH
	CMP truecol, 1
	JNE end
	MOV EBX, EAX
	MOV ECX, EAX
	SHR EAX, 8	; 23..19 -> 15..11
	SHR EBX, 5	; 15..10 -> 10..5
	SHR ECX, 3	; 7..3 -> 4..0
	AND EAX, 0F800H	; 15..11
	AND EBX, 007E0H	; 10..5
	AND ECX, 0001FH	; 4..0
	OR EAX, EBX
	OR EAX, ECX
	JMP end
index:
	AND EAX, 0FFH
	LEA EBX, colmap
	MOV EAX, [EBX][EAX*4]
end:
END TransColor;

(* CopyAlignDst - Like SYSTEM.MOVE, but aligns destination 4-byte values in inner loop. *)

PROCEDURE CopyAlignDst(src, dst, size: LONGINT);
CODE {SYSTEM.i386}
	MOV ESI, src[EBP]
	MOV EDI, dst[EBP]
	MOV ECX, size[EBP]
	CLD
	TEST ECX, ECX
	JZ exit
	
	TEST EDI, 4
	JZ ok
	MOVSB
	DEC ECX
	JZ exit
	
	TEST EDI, 4
	JZ ok
	MOVSB
	DEC ECX
	JZ exit
	
	TEST EDI, 4
	JZ ok
	MOVSB
	DEC ECX
	JZ exit
	
ok:
	MOV EAX, ECX
	SHR ECX, 2	; size DIV 4
	AND EAX, 3	; size MOD 4
	REP MOVSD
	
	MOV ECX, EAX
	REP MOVSB
exit:
END CopyAlignDst;

(* CopyAlignSrc - Like SYSTEM.MOVE, but aligns source to 4-byte values in inner loop. *)

PROCEDURE CopyAlignSrc(src, dst, size: LONGINT);
CODE {SYSTEM.i386}
	MOV ESI, src[EBP]
	MOV EDI, dst[EBP]
	MOV ECX, size[EBP]
	CLD
	TEST ECX, ECX
	JZ exit
	
	TEST ESI, 4
	JZ ok
	MOVSB
	DEC ECX
	JZ exit
	
	TEST ESI, 4
	JZ ok
	MOVSB
	DEC ECX
	JZ exit
	
	TEST ESI, 4
	JZ ok
	MOVSB
	DEC ECX
	JZ exit
	
ok:
	MOV EAX, ECX
	SHR ECX, 2	; size DIV 4
	AND EAX, 3	; size MOD 4
	REP MOVSD
	
	MOV ECX, EAX
	REP MOVSB
exit:
END CopyAlignSrc;

PROCEDURE CopyBlock0(n, w, adr, buf: LONGINT;  from: BOOLEAN);
VAR bank, ofs, left, h0: LONGINT;
BEGIN
	REPEAT
		bank := adr DIV WinSize;
		ofs := adr MOD WinSize;
		IF bank # curBank THEN switch(bank) END;
		(*PDR:*)
		left := (WinSize - ofs) DIV bytesPerPixel;
		h0 := left DIV displayWidth;	(* h0 = lines that will fit in window *)
		IF h0 > n THEN h0 := n
		ELSIF (h0 = 0) & (left >= w) THEN h0 := 1
		END;
		INC(ofs, base);
		IF h0 # 0 THEN
			(*PDR:*)
			INC(adr, h0*bytesPerScan);  DEC(n, h0);
			REPEAT
				(*PDR:*)
				IF from THEN CopyAlignSrc(ofs, buf, w*bytesPerPixel)
				ELSE CopyAlignDst(buf, ofs, w*bytesPerPixel)
				END;
				DEC(h0);  INC(ofs, bytesPerScan);  INC(buf, w*bytesPerPixel)
			UNTIL h0 = 0
		ELSE	(* h0 = 0 *)
			(*PDR:*)
			INC(adr, bytesPerScan);  DEC(n);
			IF from THEN CopyAlignSrc(ofs, buf, left*bytesPerPixel)
			ELSE CopyAlignDst(buf, ofs, left*bytesPerPixel)
			END;
			switch(bank+1);
			IF from THEN CopyAlignSrc(base, buf+left*bytesPerPixel, (w-left)*bytesPerPixel)
			ELSE CopyAlignDst(buf+left*bytesPerPixel, base, (w-left)*bytesPerPixel)
			END;
			INC(buf, w*bytesPerPixel)
		END
	UNTIL n = 0
END CopyBlock0;

(** Copy source block sx, sy, w, h to destination dx, dy using operation mode. A block is given by its lower left corner sx, sy and its dimension w, h. Some drivers only implement mode = replace. *)
PROCEDURE CopyBlock*(sx, sy, w, h, dx, dy, mode: LONGINT);
VAR w0, h0, dx0, dy0, src, dst, n, bufLines: LONGINT;
BEGIN	(* only the destination block is clipped *)
	w0 := w;  h0 := h;  dx0 := dx;  dy0 := dy;
	IF dx < clipX1 THEN dx := clipX1;  DEC(w, dx-dx0) END;
	IF dy < clipY1 THEN dy := clipY1;  DEC(h, dy-dy0) END;
	IF (w > 0) & (h > 0) & (w <= w0) & (h <= h0) THEN
		IF dx+w-1 > clipX2 THEN DEC(w, dx+w-1 - clipX2) END;
		IF dy+h-1 > clipY2 THEN DEC(h, dy+h-1 - clipY2) END;
		IF (w > 0) & (h > 0) & (w <= w0) & (h <= h0) THEN
			sy := maxY-sy-h+1;  dy := maxY-dy-h+1;	(* convert to screen coordinates *)
			(*PDR:*)
			src := sy*bytesPerScan + sx * bytesPerPixel;
			dst := dy*bytesPerScan + dx * bytesPerPixel;
			bufLines := BufSize DIV w DIV bytesPerPixel;	(* lines to copy at a time *)
			IF bufLines > h THEN bufLines := h END;
				(* adjust direction for overlap *)
			IF (dy-h+1 < sy) & (sy < dy) THEN	(* start at bottom *)
				(*PDR:*)
				n := bytesPerScan*(h-bufLines);
				INC(src, n);  INC(dst, n);
				REPEAT
					CopyBlock0(bufLines, w, src, SYSTEM.ADR(buffer.bytes[0]), TRUE);
					CopyBlock0(bufLines, w, dst, SYSTEM.ADR(buffer.bytes[0]), FALSE);
					DEC(h, bufLines);
					IF bufLines > h THEN bufLines := h END;
					(*PDR:*)
					n := bufLines*bytesPerScan;
					DEC(src, n);  DEC(dst, n)
				UNTIL h = 0
			ELSE	(* start at top *)
				REPEAT
					CopyBlock0(bufLines, w, src, SYSTEM.ADR(buffer.bytes[0]), TRUE);
					CopyBlock0(bufLines, w, dst, SYSTEM.ADR(buffer.bytes[0]), FALSE);
					(*PDR:*)
					n := bufLines*bytesPerScan;
					INC(src, n);  INC(dst, n);
					DEC(h, bufLines);
					IF bufLines > h THEN bufLines := h END
				UNTIL h = 0
			END
		END
	END
END CopyBlock;
	
(* CopyPattern0 - Copy pixels from src to dst, with no clipping.  ofs is the pixel offset to start at (max 7).  src is the 
pattern source address.  dst is the screen destination address.  w is the number of pixels to copy (max pat.w).  
col & mode are the colour and mode respectively. *)

PROCEDURE CopyPattern0(ofs, src, dst, w, cols, mode: LONGINT);
VAR ch: CHAR;  m, i: LONGINT;  s: SET; bg: INTEGER;
BEGIN
	IF mode = replace THEN bg := SHORT(TransColor(BG)) END;
	REPEAT	(* loop over w pixels *)
		SYSTEM.GET(src, ch);
		i := ofs;	(* start bit *)
		m := 8;	(* stop bit *)
		IF m > ofs+w THEN m := ofs+w END;
		REPEAT	(* loop over bits *)
			(*ASSERT((base # 0A0000H) OR (dst >= 0A0000H) & (dst < 0B0000H));*)
			IF ODD(ASH(ORD(ch), -i)) THEN	(* pixel on *)
				(*PDR:*)
				IF mode = invert THEN
					SYSTEM.GET(dst, SYSTEM.VAL(INTEGER, s));
					SYSTEM.PUT(dst, SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, cols) / s))
				ELSE	(* paint & replace *)
					SYSTEM.PUT(dst, SHORT(cols))
				END
			ELSIF mode = replace THEN	(* pixel off *)
				SYSTEM.PUT(dst, bg)
			ELSE (* skip *)
			END;
			INC(dst, 2);  INC(i)
		UNTIL i = m;
		INC(src);  DEC(w, m-ofs);  ofs := 0
	UNTIL w = 0
END CopyPattern0;

(* CopyPattern1 - Copy pixels from src (x,y), with full clipping.  Slower version of CopyPattern0, with individual clipping
of every pixel.  ofs is always 0.  (x,y) is the screen destination. *)

PROCEDURE CopyPattern1(src, x, y, w, col, mode: LONGINT);
VAR ch: CHAR;  m, i: LONGINT;
BEGIN
	REPEAT	(* loop over w pixels *)
		SYSTEM.GET(src, ch);
		i := 0;	(* start bit *)
		m := 8;	(* stop bit *)
		IF m > w THEN m := w END;
		REPEAT	(* loop over bits *)
			IF ODD(ASH(ORD(ch), -i)) THEN	(* pixel on *)
				Dot(SHORT(col), SHORT(x), SHORT(y), SHORT(mode))
			ELSIF mode = replace THEN	(* pixel off *)
				Dot(BG, SHORT(x), SHORT(y), replace)
			ELSE (* skip *)
			END;
			INC(x);  INC(i)
		UNTIL i = m;
		INC(src);  DEC(w, m)
	UNTIL w = 0
END CopyPattern1;

(** Copy pattern pat in color col to x, y using operation mode. *)
PROCEDURE CopyPattern*(col: Color; pat: Pattern; x, y, mode: LONGINT);
VAR cols, x2, y2, w, w0, h, src, dst, bank, left, h0: LONGINT;  ch: CHAR;
BEGIN
	(*PDR:*)
	IF (mode = invert) & (truecol # 0) & (col = FG) THEN col := 80FFFFFFH END;
	cols := TransColor(col); cols := ASH(cols, 16) + cols;
	SYSTEM.GET(pat, ch);  w := ORD(ch);
	SYSTEM.GET(pat+1, ch);  h := ORD(ch);
	IF (w > 0) & (h > 0) THEN
		x2 := x+w-1;  y2 := y+h-1;	(* (x,y) bottom left & (x2,y2) top right *)
		IF (x >= clipX1) & (y >= clipY1) & (x2 <= clipX2) & (y2 <= clipY2) THEN	(* fully visible - common case *)
			w0 := (w+7) DIV 8;	(* bytes in pattern line *)
			src := pat+2 + (h-1)*w0;	(* last line of pattern *)
			y := maxY-y-h+1;	(* convert to screen coordinate *)
			REPEAT	(* loop over h lines *)
				(*PDR:*)
				dst := y * bytesPerScan + x*bytesPerPixel;
				bank := dst DIV WinSize;
				dst := dst MOD WinSize;
				IF bank # curBank THEN switch(bank) END;
				(*PDR:*)
				left := (WinSize - dst) DIV bytesPerPixel;
				h0 := left DIV displayWidth;	(* h0 = lines that will fit in window *)
				IF h0 > h THEN h0 := h
				ELSIF (h0 = 0) & (left >= w) THEN h0 := 1
				END;
				INC(dst, base);
				IF h0 # 0 THEN
					INC(y, h0);  DEC(h, h0);
					REPEAT	(* loop over h0 lines, without bank crossing *)
						CopyPattern0(0, src, dst, w, cols, mode);
						(*PDR:*)
						DEC(h0);  INC(dst, bytesPerScan);  DEC(src, w0)
					UNTIL h0 = 0
				ELSE	(* h0 = 0 *)
					CopyPattern0(0, src, dst, left, cols, mode);
					switch(bank+1);
					CopyPattern0(left MOD 8, src + left DIV 8, base, w-left, cols, mode);
					INC(y);  DEC(src, w0);  DEC(h)
				END
			UNTIL h = 0
		ELSIF (x2 >= clipX1) & (y2 >= clipY1) & (x <= clipX2) & (y <= clipY2) THEN	(* partially visible *)
			w0 := (w+7) DIV 8;	(* bytes in pattern line *)
			src := pat+2;	(* last line of pattern *)
			REPEAT	(* loop over h lines *)
				CopyPattern1(src, x, y, w, col, mode);
				INC(y);  INC(src, w0);  DEC(h)
			UNTIL h = 0
		ELSE (* invisible *)
		END
	END
END CopyPattern;

(* FillPattern0 - Copy pixels from src to dst, with no clipping, with wraparound in the source.  ofs is the pixel offset to 
start at.  src is the pattern source address.  dst is the screen destination address.  w is the number of pixels to copy.  
pw is the pattern width.  col & mode are the colour and mode respectively. *)

PROCEDURE FillPattern0(ofs, src, dst, w, pw, cols, mode: LONGINT);
VAR ch: CHAR;  m, i, src0, left: LONGINT;  s: SET;
BEGIN
	left := pw-ofs;	(* pixels left to do in pattern *)
	src0 := src;  INC(src, ofs DIV 8);  ofs := ofs MOD 8;	(* start position *)
	REPEAT	(* loop over w pixels *)
		SYSTEM.GET(src, ch);
		i := ofs;	(* start bit *)
		m := 8;	(* stop bit *)
		IF m > ofs+left THEN m := ofs+left END;	(* max left times *)
		IF m > ofs+w THEN m := ofs+w END;	(* max w times *)
		REPEAT	(* loop over bits *)
			(*ASSERT((base # 0A0000H) OR (dst >= 0A0000H) & (dst < 0B0000H));*)
			(*PDR:*)
			IF ODD(ASH(ORD(ch), -i)) THEN	(* pixel on *)
				IF mode = invert THEN
					SYSTEM.GET(dst, SYSTEM.VAL(INTEGER, s));
					SYSTEM.PUT(dst, SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, cols) / s))
				ELSE	(* paint & replace *)
					SYSTEM.PUT(dst, SHORT(cols))
				END
			ELSIF mode = replace THEN	(* pixel off *)
				SYSTEM.PUT(dst, SYSTEM.VAL(INTEGER, s))
			ELSE (* skip *)
			END;
			INC(dst, 2);  INC(i)
		UNTIL i = m;
		INC(src);  DEC(left, m-ofs);  DEC(w, m-ofs);  ofs := 0;
		IF left = 0 THEN src := src0;  left := pw END	(* wrap to start of pattern *)
	UNTIL w = 0
END FillPattern0;

(** Replicate pattern pat in color col into block x, y, w, h using operation mode, proceeding from left to right and from bottom to top, starting at lower left corner. The pattern origin is placed at px, py. *)
PROCEDURE FillPattern*(col: Color; pat: Pattern; px, py, x, y, w, h, mode: LONGINT);
VAR cols, pw, ph, x2, y2, w0, src0, src, dst, bank, left, h0: LONGINT;  ch: CHAR;
BEGIN
	(*PDR:*)
	IF (mode = invert) & (truecol # 0) & (col = FG) THEN col := 80FFFFFFH END;
	cols := TransColor(col); cols := ASH(cols, 16) + cols;
	x2 := x+w-1;  y2 := y+h-1;	(* (x,y) bottom left & (x2,y2) top right *)
	IF x < clipX1 THEN DEC(w, clipX1-x);  x := clipX1
	ELSIF x > clipX2 THEN DEC(w, x-clipX2);  x := clipX2
	END;
	IF y < clipY1 THEN DEC(h, clipY1-y);  y := clipY1
	ELSIF y > clipY2 THEN DEC(h, y-clipY2);  y := clipY2
	END;
	IF x2 < clipX1 THEN DEC(w, clipX1-x2)
	ELSIF x2 > clipX2 THEN DEC(w, x2-clipX2)
	END;
	IF y2 < clipY1 THEN DEC(h, clipY1-y2)
	ELSIF y2 > clipY2 THEN DEC(h, y2-clipY2)
	END;
	IF (w > 0) & (h > 0) THEN
		SYSTEM.GET(pat, ch);  pw := ORD(ch);
		SYSTEM.GET(pat+1, ch);  ph := ORD(ch);
		IF (pw > 0) & (ph > 0) THEN
			INC(pat, 2);	(* adr of bitmap *)
			w0 := (pw+7) DIV 8;	(* bytes in pattern line *)
			src0 := pat + (ph-1)*w0;	(* last line of pattern *)
			src := pat + (h-1 + y-py) MOD ph * w0;	(* start line of pattern *)
			px := (x - px) MOD pw;	(* start pixel offset *)
			y := maxY-y-h+1;	(* convert to screen coordinate *)
			REPEAT	(* loop over h lines *)
				(*PDR:*)
				dst := y * bytesPerScan + x * bytesPerPixel;
				bank := dst DIV WinSize;
				dst := dst MOD WinSize;
				IF bank # curBank THEN switch(bank) END;
				left := (WinSize - dst) DIV bytesPerPixel;
				h0 := left DIV displayWidth;	(* h0 = lines that will fit in window *)
				IF h0 > h THEN h0 := h
				ELSIF (h0 = 0) & (left >= w) THEN h0 := 1
				END;
				INC(dst, base);
				IF h0 # 0 THEN
					INC(y, h0);  DEC(h, h0);
					REPEAT	(* loop over h0 lines, without bank crossing *)
						FillPattern0(px, src, dst, w, pw, cols, mode);
						(*PDR:*)
						DEC(h0);  INC(dst, bytesPerScan);
						IF src = pat THEN src := src0 ELSE DEC(src, w0) END
					UNTIL h0 = 0
				ELSE	(* h0 = 0 *)
					FillPattern0(px, src, dst, left, pw, col, mode);
					switch(bank+1);
					FillPattern0((px + left) MOD pw, src, base, w-left, pw, cols, mode);
					INC(y);  DEC(h);
					IF src = pat THEN src := src0 ELSE DEC(src, w0) END
				END
			UNTIL h = 0
		END
	END
END FillPattern;

(** Like FillPattern, but the pattern origin is placed at 0, 0. *)
PROCEDURE ReplPattern*(col: Color; pat: Pattern; x, y, w, h, mode: LONGINT);
BEGIN
	FillPattern(col, pat, 0, 0, x, y, w, h, mode)
END ReplPattern;

(* ReplConst0 - Replicate a constant in a line in replace mode. *)

(*PDR:*)
PROCEDURE ReplConst0(dst, w, cols: LONGINT);
BEGIN
	(*ASSERT((base # 0A0000H) OR (dst >= 0A0000H) & (dst < 0B0000H));
	ASSERT((w >= 0) & (w <= displayWidth));*)
	IF (dst MOD 4 # 0) & (w # 0) THEN
		SYSTEM.PUT(dst, SHORT(cols));
		INC(dst, 2);  DEC(w)
	END;
	WHILE w >= 2 DO
		SYSTEM.PUT(dst, cols);
		INC(dst, 4);  DEC(w, 2)
	END;
	IF w # 0 THEN SYSTEM.PUT(dst, SHORT(cols)) END
END ReplConst0;

(* ReplConst2 - Replicate a constant in a line in invert mode. *)

PROCEDURE ReplConst2(dst, w, cols: LONGINT);
VAR t: ARRAY 4 OF SET;
BEGIN
	(*ASSERT((base # 0A0000H) OR (dst >= 0A0000H) & (dst < 0B0000H));
	ASSERT((w >= 0) & (w <= displayWidth));*)
	(*PDR:*)
	IF (dst MOD 4 # 0) & (w # 0) THEN
		SYSTEM.GET(dst, SYSTEM.VAL(INTEGER, t[0]));
		SYSTEM.PUT(dst, SYSTEM.VAL(INTEGER, t[0] / SYSTEM.VAL(SET, cols)));
		INC(dst, 2); DEC(w)
	END;
	WHILE w >= 8 DO (* unrolled loop *)
		SYSTEM.GET(dst, t[0]);  SYSTEM.GET(dst+4, t[1]);
		SYSTEM.GET(dst+8, t[2]);  SYSTEM.GET(dst+12, t[3]);
		SYSTEM.PUT(dst, t[0] / SYSTEM.VAL(SET, cols));
		SYSTEM.PUT(dst+4, t[1] / SYSTEM.VAL(SET, cols));
		SYSTEM.PUT(dst+8, t[2] / SYSTEM.VAL(SET, cols));
		SYSTEM.PUT(dst+12, t[3] / SYSTEM.VAL(SET, cols));
		INC(dst, 16);  DEC(w, 8)
	END;
	WHILE w >= 2 DO
		SYSTEM.GET(dst, t[0]);
		SYSTEM.PUT(dst, t[0] / SYSTEM.VAL(SET, cols));
		INC(dst, 4); DEC(w, 2)
	END;
	IF w # 0 THEN 
		SYSTEM.GET(dst, SYSTEM.VAL(INTEGER, t[0]));
		SYSTEM.PUT(dst, SYSTEM.VAL(INTEGER, t[0] / SYSTEM.VAL(SET, cols)))
	END
END ReplConst2;

(** Block fill in color col and operation mode.  mode paint and replace are equivalent. *)
PROCEDURE ReplConst*(col: Color; x, y, w, h, mode: LONGINT);
VAR cols, dst, left, x2, y2, h0, bank: LONGINT;
BEGIN
	x2 := x+w-1;  y2 := y+h-1;	(* (x2,y2) is top right corner *)
	(*PDR:*)
	IF (mode = invert) & (truecol # 0) & (col = FG) THEN col := 80FFFFFFH END;
	cols := TransColor(col); cols := ASH(cols, 16) + cols;
	IF x < clipX1 THEN DEC(w, clipX1-x);  x := clipX1
	ELSIF x > clipX2 THEN DEC(w, x-clipX2);  x := clipX2
	END;
	IF y < clipY1 THEN DEC(h, clipY1-y);  y := clipY1
	ELSIF y > clipY2 THEN DEC(h, y-clipY2);  y := clipY2
	END;
	IF x2 < clipX1 THEN DEC(w, clipX1-x2)
	ELSIF x2 > clipX2 THEN DEC(w, x2-clipX2)
	END;
	IF y2 < clipY1 THEN DEC(h, clipY1-y2)
	ELSIF y2 > clipY2 THEN DEC(h, y2-clipY2)
	END;
	IF (w > 0) & (h > 0) THEN
		y := maxY-y-h+1;	(* convert to screen coordinate *)
		REPEAT
			(*PDR:*)
			dst := y * bytesPerScan + x * bytesPerPixel;
			bank := dst DIV WinSize;
			dst := dst MOD WinSize;
			IF bank # curBank THEN switch(bank) END;
			left := (WinSize - dst) DIV bytesPerPixel;
			h0 := left DIV displayWidth;	(* h0 = lines that will fit in window *)
			IF h0 > h THEN h0 := h
			ELSIF (h0 = 0) & (left >= w) THEN h0 := 1
			END;
			INC(dst, base);
			IF h0 # 0 THEN
				INC(y, h0);  DEC(h, h0);
				REPEAT
					IF mode = invert THEN ReplConst2(dst, w, cols) ELSE ReplConst0(dst, w, cols) END;
					(*PDR:*)
					DEC(h0);  INC(dst, bytesPerScan)
				UNTIL h0 = 0
			ELSE	(* h0 = 0 *)
				IF mode = invert THEN ReplConst2(dst, left, cols) ELSE ReplConst0(dst, left, cols) END;
				switch(bank+1);
				IF mode = invert THEN ReplConst2(base, w-left, cols) ELSE ReplConst0(base, w-left, cols) END;
				INC(y);  DEC(h)
			END
		UNTIL h = 0
	END
END ReplConst;

(** Place a dot of color col in operation mode at x, y. Effect equivalent to ReplConst with a block of size 1, 1. *)
PROCEDURE Dot*(col: Color; x, y, mode: LONGINT);
VAR cols, dst, bank: LONGINT;  s: SET;
BEGIN
	(*PDR:*)
	IF (mode = invert) & (truecol # 0) & (col = FG) THEN col := 80FFFFFFH END;
	cols := TransColor(col); cols := ASH(cols, 16) + cols;
	IF (x >= clipX1) & (x <= clipX2) & (y >= clipY1) & (y <= clipY2) THEN
		dst := (maxY-y) * bytesPerScan + x * bytesPerPixel;
		bank := dst DIV WinSize;
		dst := dst MOD WinSize;
		IF bank # curBank THEN switch(bank) END;
		INC(dst, base);
		IF mode = invert THEN
			SYSTEM.GET(dst, SYSTEM.VAL(INTEGER, s));
			SYSTEM.PUT(dst, SYSTEM.VAL(INTEGER, SYSTEM.VAL(SET, cols) / s))
		ELSE
			SYSTEM.PUT(dst, SHORT(cols))
		END
	END
END Dot;

(** Returns the dimensions of a pattern. *)
PROCEDURE GetDim*(pat: Pattern; VAR w, h: INTEGER);
VAR ch: CHAR;
BEGIN
	SYSTEM.GET(pat, ch);  w := ORD(ch);
	SYSTEM.GET(pat+1, ch);  h := ORD(ch)
END GetDim;

(** Define a new pattern. *)
PROCEDURE NewPattern*(w, h: LONGINT; VAR image: ARRAY OF SET): Pattern;
VAR len, src, dest, i: LONGINT;  p: PatternPtr;  pl: List;
BEGIN
	len := (w+7) DIV 8;
	SYSTEM.NEW(p, 4+len*h);  p.w := CHR(w);  p.h := CHR(h);
	src := SYSTEM.ADR(image[0]);  dest := SYSTEM.ADR(p.pixmap[0]);
	i := 0;
	WHILE i < h DO SYSTEM.MOVE(src, dest, len);  INC(src, 4);  INC(dest, len);  INC(i) END;
	NEW(pl);  pl.pat := p;  pl.next := pattern;  pattern := pl;	(* put in list to avoid GC *)
	RETURN SYSTEM.ADR(p.w)
END NewPattern;
	
(* Define standard patterns. *)
PROCEDURE CreatePatterns;
VAR image: ARRAY 16 OF SET;
BEGIN
	image[0] := {13};
	image[1] := {12..14};
	image[2] := {11..13};
	image[3] := {10..12};
	image[4] := {9..11};
	image[5] := {8..10};
	image[6] := {7..9};
	image[7] := {0, 6..8};
	image[8] := {0, 1, 5..7};
	image[9] := {0..2, 4..6};
	image[10] := {0..5};
	image[11] := {0..4};
	image[12] := {0..5};
	image[13] := {0..6};
	image[14] := {0..7};
	arrow := NewPattern(15, 15, image);
	
	image[0] := {0, 10};
	image[1] := {1, 9};
	image[2] := {2, 8};
	image[3] := {3, 7};
	image[4] := {4, 6};
	image[5] := {};
	image[6] := {4, 6};
	image[7] := {3, 7};
	image[8] := {2, 8};
	image[9] := {1, 9};
	image[10] := {0, 10};
	cross := NewPattern(11, 11, image); 
	
	image[0] := {6};
	image[1] := {5..7};
	image[2] := {4..8};
	image[3] := {3..9};
	image[4] := {2..10};
	image[5] := {5..7};
	image[6] := {5..7};
	image[7] := {5..7};
	image[8] := {5..7};
	image[9] := {5..7};
	image[10] := {5..7};
	image[11] := {5..7};
	image[12] := {5..7};
	image[13] := {5..7};
	image[14] := {};
	downArrow := NewPattern(11, 15, image);
	
	image[0] := {0, 4, 8, 12};
	image[1] := {};
	image[2] := {2, 6, 10, 14};
	image[3] := {};
	image[4] := {0, 4, 8, 12};
	image[5] := {};
	image[6] := {2, 6, 10, 14};
	image[7] := {};
	image[8] := {0, 4, 8, 12};
	image[9] := {};
	image[10] := {2, 6, 10, 14};
	image[11] := {};
	image[12] := {0, 4, 8, 12};
	image[13] := {};
	image[14] := {2, 6, 10, 14};
	image[15] := {};
	grey0 := NewPattern(16, 16, image);
	
	image[0] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[1] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[2] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[3] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[4] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[5] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[6] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[7] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[8] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[9] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[10] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[11] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[12] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[13] := {1, 3, 5, 7, 9, 11, 13, 15};
	image[14] := {0, 2, 4, 6, 8, 10, 12, 14};
	image[15] := {1, 3, 5, 7, 9, 11, 13, 15};
	grey1 := NewPattern(16, 16, image);
	
	image[0] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[1] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[2] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[3] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[4] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[5] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[6] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[7] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[8] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[9] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[10] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[11] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[12] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[13] := {0, 1, 4, 5, 8, 9, 12, 13};
	image[14] := {2, 3, 6, 7, 10, 11, 14, 15};
	image[15] := {2, 3, 6, 7, 10, 11, 14, 15};
	grey2 := NewPattern(16, 16, image);
	
	image[0] := {0..2, 8..11};
	image[1] := {0..2, 7..10};
	image[2] := {0..2, 6..9};
	image[3] := {0..2, 5..8};
	image[4] := {0..2, 4..7};
	image[5] := {0..6};
	image[6] := {0..5};
	image[7] := {0..4};
	image[8] := {0..3};
	image[9] := {0..2};
	image[10] := {0, 1};
	image[11] := {0};
	hook := NewPattern(12, 12, image);
	
	image[0] := {7};
	image[1] := {7};
	image[2] := {2, 7, 12};
	image[3] := {3, 7, 11};
	image[4] := {4, 7, 10};
	image[5] := {5, 7, 9};
	image[6] := {6..8};
	image[7] := {0..6, 8..14};
	image[8] := {6..8};
	image[9] := {5, 7, 9};
	image[10] := {4, 7, 10};
	image[11] := {3, 7, 11};
	image[12] := {2, 7, 12};
	image[13] := {7};
	image[14] := {7};
	star := NewPattern(15, 15, image);
	
	image[0] := {};
	image[1] := {};
	image[2] := {0};
	image[3] := {};
	image[4] := {};
	image[5] := {};
	image[6] := {};
	image[7] := {};
	image[8] := {};
	image[9] := {};
	image[10] := {};
	image[11] := {};
	image[12] := {};
	image[13] := {};
	image[14] := {};
	image[15] := {};
	ticks := NewPattern(16, 16, image);
	
	image[0] := -{};
	image[1] := -{};
	image[2] := -{};
	image[3] := -{};
	image[4] := -{};
	image[5] := -{};
	image[6] := -{};
	image[7] := -{};
	solid := NewPattern(16, 8, image)
END CreatePatterns;
	
(** Return the format of a display region, for TransferBlock. *)
PROCEDURE TransferFormat*(x: LONGINT): LONGINT;
BEGIN
	RETURN unknown
END TransferFormat;

(** Transfer a block of pixels in display format to (mode = set) or from (mode = get)  the display.  Pixels in the rectangular area are transferred from bottom to top and left to right.  The pixels are transferred to or from buf, starting at ofs, and with line increment stride, which may be < 0. *)
PROCEDURE TransferBlock*(VAR buf: ARRAY OF CHAR;  ofs, stride, x, y, w, h, mode: LONGINT);
BEGIN
	HALT(99)
END TransferBlock;

(** Change screen mode. *)
PROCEDURE SetMode*(x: LONGINT; s: SET);
BEGIN
END SetMode;

(* DisplayBlock0 - Display a line in replace mode. *)

PROCEDURE DisplayBlock0(src, dst, w: LONGINT);
VAR ch: CHAR;  s: SET; cols: LONGINT;
BEGIN
	(*ASSERT((base # 0A0000H) OR (dst >= 0A0000H) & (dst < 0B0000H));
	ASSERT((w >= 0) & (w <= displayWidth));*)
	(*PDR:*)
	IF (dst MOD 4 # 0) & (w # 0) THEN
		SYSTEM.GET(src, ch);
		SYSTEM.PUT(dst, SHORT(colmap[ORD(ch)]));
		INC(src);  INC(dst, 2);  DEC(w)
	END;
	WHILE w >= 2 DO
		SYSTEM.GET(src, ch); cols := colmap[ORD(ch)];
		SYSTEM.GET(src+1, ch); cols := cols + ASH(colmap[ORD(ch)], 16);
		SYSTEM.PUT(dst, cols);
		INC(src, 2);  INC(dst, 4);  DEC(w, 2)
	END;
	IF w # 0 THEN
		SYSTEM.GET(src, ch);
		SYSTEM.PUT(dst, SHORT(colmap[ORD(ch)]));
	END
END DisplayBlock0;

(* DisplayBlock2 - Display a line in invert mode. *)

PROCEDURE DisplayBlock2(src, dst, w: LONGINT);
VAR s: SET;  ch: CHAR; cols: LONGINT;
BEGIN
	(*ASSERT((base # 0A0000H) OR (dst >= 0A0000H) & (dst < 0B0000H));
	ASSERT((w >= 0) & (w <= displayWidth));*)
	IF (dst MOD 4 # 0) & (w # 0) THEN
		SYSTEM.GET(src, ch);
		SYSTEM.GET(dst, SYSTEM.VAL(INTEGER, s));
		SYSTEM.PUT(dst, SYSTEM.VAL(INTEGER, s / SYSTEM.VAL(SET, colmap[ORD(ch)])));
		INC(dst, 2); INC(src); DEC(w)
	END;
	WHILE w >= 2 DO
		SYSTEM.GET(src, ch); cols := colmap[ORD(ch)];
		SYSTEM.GET(src+1, ch); cols := cols + ASH(colmap[ORD(ch)], 16);
		SYSTEM.GET(dst, s); SYSTEM.PUT(dst, s / SYSTEM.VAL(SET, cols));
		INC(dst, 4); INC(src, 2); DEC(w, 2)
	END;
	IF w # 0 THEN
		SYSTEM.GET(src, ch);
		SYSTEM.GET(dst, SYSTEM.VAL(INTEGER, s));
		SYSTEM.PUT(dst, SYSTEM.VAL(INTEGER, s / SYSTEM.VAL(SET, colmap[ORD(ch)])))
	END
END DisplayBlock2;

(** Display a picture.  Used internally by Pictures module only. *)
PROCEDURE DisplayBlock*(adr, dx, dy, w, h, sx, sy, mode: LONGINT);
VAR pw, pd, x, y, h0, src, x2, y2, dst, bank, left: LONGINT;
BEGIN
	x := sx;  y := sy;
	x2 := x+w-1;  y2 := y+h-1;	(* (x2,y2) is top right corner *)
	IF x < clipX1 THEN DEC(w, clipX1-x);  INC(dx, clipX1-x);  x := clipX1
	ELSIF x > clipX2 THEN DEC(w, x-clipX2)
	END;
	IF y < clipY1 THEN DEC(h, clipY1-y);  INC(dy, clipY1-y);  y := clipY1
	ELSIF y > clipY2 THEN DEC(h, y-clipY2)
	END;
	IF x2 < clipX1 THEN DEC(w, clipX1-x2)
	ELSIF x2 > clipX2 THEN DEC(w, x2-clipX2)
	END;
	IF y2 < clipY1 THEN DEC(h, clipY1-y2)
	ELSIF y2 > clipY2 THEN DEC(h, y2-clipY2)
	END;
	IF (w > 0) & (h > 0) THEN
		pd := 0;  SYSTEM.GET(adr+4, SYSTEM.VAL(INTEGER, pd));
		IF pd = 8 THEN
			SYSTEM.GET(adr+8, pw);
			SYSTEM.GET(adr+12, src);
			INC(src, (dy+h-1)*pw + dx);	(* top left corner *)
			y := maxY-y-h+1;	(* convert to screen coordinate *)
			REPEAT
				(*PDR:*)
				dst := y*bytesPerScan + x*bytesPerPixel;
				bank := dst DIV WinSize;
				dst := dst MOD WinSize;
				IF bank # curBank THEN switch(bank) END;
				(*PDR:*)
				left := (WinSize - dst) DIV bytesPerPixel;
				h0 := left DIV displayWidth;	(* h0 = lines that will fit in window *)
				IF h0 > h THEN h0 := h
				ELSIF (h0 = 0) & (left >= w) THEN h0 := 1
				END;
				INC(dst, base);
				IF h0 # 0 THEN
					INC(y, h0);  DEC(h, h0);
					REPEAT
						IF mode = invert THEN DisplayBlock2(src, dst, w) ELSE DisplayBlock0(src, dst, w) END;
						(*PDR:*)
						DEC(h0);  DEC(src, pw);  INC(dst, bytesPerScan)
					UNTIL h0 = 0
				ELSE	(* h0 = 0 *)
					IF mode = invert THEN DisplayBlock2(src, dst, left) ELSE DisplayBlock0(src, dst, left) END;
					switch(bank+1);
					IF mode = invert THEN DisplayBlock2(src+left, base, w-left) ELSE DisplayBlock0(src+left, base, w-left) END;
					INC(y);  DEC(h)
				END
			UNTIL h = 0
		ELSE	(* depth not supported *)
			ReplConst(3, sx, sy, w, h, mode)
		END
	END
END DisplayBlock;

(** Return address of display located at x, or 0 if not supported. *)
PROCEDURE Map*(x: LONGINT): LONGINT;
BEGIN
	IF linearbase = 0 THEN RETURN base ELSE RETURN linearbase END
END Map;

(* StrToInt - Convert a string to an integer *)

PROCEDURE StrToInt(VAR i: LONGINT;  VAR s: ARRAY OF CHAR): LONGINT;
VAR vd, vh, sgn, d: LONGINT;  hex: BOOLEAN;
BEGIN
	vd := 0;  vh := 0;  hex := FALSE;
	IF s[i] = "-" THEN sgn := -1; INC(i) ELSE sgn := 1 END;
	LOOP
		IF (s[i] >= "0") & (s[i] <= "9") THEN d := ORD(s[i])-ORD("0")
		ELSIF (CAP(s[i]) >= "A") & (CAP(s[i]) <= "F") THEN d := ORD(CAP(s[i]))-ORD("A")+10; hex := TRUE
		ELSE EXIT
		END;
		vd := 10*vd + d;  vh := 16*vh + d;
		INC(i)
	END;
	IF CAP(s[i]) = "H" THEN hex := TRUE; INC(i) END;	(* optional H *)
	IF hex THEN vd := vh END;
	RETURN sgn * vd
END StrToInt;

(* GetVal - Get config string and convert to integer. *)

PROCEDURE GetVal(name: ARRAY OF CHAR;  default: LONGINT): LONGINT;
VAR v: LONGINT;  s: ARRAY 10 OF CHAR;  p: LONGINT;
BEGIN
	Kernel.GetConfig(name, s);
	IF s[0] = 0X THEN
		v := default
	ELSE
		p := 0;  v := StrToInt(p, s)
	END;
	RETURN v
END GetVal;

(* MapFrameBuffer - Map linear frame buffer. *)

PROCEDURE MapFrameBuffer(VAR virtAdr: LONGINT);
VAR s: ARRAY 16 OF CHAR;  p, physAdr: LONGINT;
BEGIN
	Kernel.GetConfig("DLinBuf", s);
	IF s[0] = 0X THEN
		Kernel.GetInit(1, physAdr)	(* get DX:CX from Init string *)
	ELSE
		p := 0;  physAdr := StrToInt(p, s)
	END;
	Kernel.MapPhysical(physAdr, LinearSize, virtAdr)
END MapFrameBuffer;

(* Init - Initialize the screen dimensions. *)

PROCEDURE Init;
VAR chipSet, mem: LONGINT;
BEGIN
	Kernel.WriteString("SVGA: ");
	base := 0A0000H;  linearbase := 0;
	chipSet := GetVal("SVGA", 0);
	CASE chipSet OF
		1: switch := SwitchS3Aurora64V;  Kernel.WriteString("S3 Aurora")
		|2: switch := SwitchET4000;  Kernel.WriteString("ET4000")
		|3: switch := SwitchS3801;  Kernel.WriteString("S3-801/5");
			SYSTEM.PORTOUT(3D4H, SYSTEM.VAL(INTEGER, 4838H));	(* unlock 1 *)
			SYSTEM.PORTOUT(3D4H, SYSTEM.VAL(INTEGER, 0A539H))	(* unlock 2 *)
		|4: switch := SwitchFireGL;  Kernel.WriteString("Diamond FireGL")
		|5: switch := SwitchGD542x;  Kernel.WriteString("Cirrus Logic GD542x")
		|6: switch := SwitchLinear;  Kernel.WriteString("Linear frame buffer at");
			MapFrameBuffer(linearbase);  Kernel.WriteHex(linearbase, 9)
		|7: switch := SwitchMach32;  Kernel.WriteString("ATI Mach32")
		|8: switch := SwitchTrident9xxx;  Kernel.WriteString("Trident9xxx")
		ELSE switch := SwitchLinear;  Kernel.WriteString("Vesa Linear frame buffer at");
			linearbase := VesaAdr;  Kernel.WriteHex(linearbase, 9)	(* used with MapVesa=1 *)
	END;
	displayWidth := GetVal("DWidth", 1024);	(* assume 1024 if not specified *)
	displayHeight := GetVal("DHeight", 768);	(* assume 768 if not specified *)
	IF GetVal("Color", 1) = 0 THEN depth := 1 ELSE depth := 8 END;

	(*PDR:*)
	truecol := 1; bytesPerPixel := 2; bytesPerScan := displayWidth * bytesPerPixel;
	IF GetVal("Color", 1) = 0 THEN depth := 1 ELSE depth := 8 END;

	mem := GetVal("DMem", 0)*1024;
	IF mem = 0 THEN	(* compute default *)
		mem := 512*1024;
		WHILE displayWidth*displayHeight >= mem DO mem := mem*2 END
	END;
	(*PDR:*)
	displayHeight1 := mem * bytesPerPixel DIV bytesPerScan;	(* maximum lines in display memory *)
	maxY := displayHeight-1;
	Kernel.WriteChar(" ");  Kernel.WriteInt(displayWidth, 1);
	Kernel.WriteChar("x");  Kernel.WriteInt(displayHeight, 1);
	Kernel.WriteString(" (+");  Kernel.WriteInt(displayHeight1-displayHeight, 1);
	Kernel.WriteString(" offscreen)");
	Kernel.WriteLn

END Init;
	
BEGIN
	curBank := -1;  NEW(buffer);
	Init;
	Unit := 10000;
	Left := 0;  ColLeft := 0;
	Bottom := 0;  UBottom := SHORT(displayHeight-displayHeight1+1);
	Width := SHORT(displayWidth);  Height := SHORT(maxY+1);
	pattern := NIL;
	CreatePatterns;
	ResetClip
END Display.

(*
Display=SVGA.

S3 Aurora64 800x600x8 (S3 Aurora Aurora64V+ in Compaq laptop & Trio64V+ in STB PowerGraph 64)
	Init=bb0301b8024fcd10ba00e0b90000
	SVGA=1
	DWidth=800 DHeight=600

ET4000 (Dell) 1024x768x8
	Init=b83800cd10
	SVGA=2

S3 801/805 (Dell/Quadtel) 1024x768x8
	Init=bb0502b8024fcd10
	SVGA=3

Diamond FireGL1000 Pro with 3DLabs PerMedia 640x480x8
	Init=bb0101b8024fcd10
	SVGA=4

Cirrus Logic GD542x 1024x768x8
	Init=bb0501b8024fcd10
	SVGA=5

Linear frame buffer
	Init=... (set DX:CX)
	SVGA=6
	DLinBuf=physical frame buffer address (or specify DX:CX in Init string)

ATI Mach32
	Init=b86400cd10
	SVGA=7

Trident 9xxx 1024x768x8
	Init=bb0501b8024fcd10
	SVGA=8

Compiler.Compile SVGAH.Display.Mod\X ~
*)

TestSVGA.Mod
