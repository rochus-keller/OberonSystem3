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

MODULE Display;

(* Type: Cirrus Logic	256 Colors
	Date: 2. 5. 96
	Version: 1.0
	Author: Joerg Derungs *)

(* works on 5430, not on 5420 *)

IMPORT SYSTEM, Objects, Kernel;

CONST
	BG* = 0; FG* = 15;										(*background, foreground*)
	replace* = 0; paint* = 1; invert* = 2;		   (*operation modes*)

	remove* = 0; suspend* = 1; restore* = 2; newprinter* = 3; (*ControlMsg id*)
	reduce* = 0; extend* = 1; move* = 2; (*ModifyMsg id*)
	display* = 0; state* = 1; (*ModifyMsg mode*)
	screen* = 0; printer* = 1; (* DisplayMsg device *)
	full* = 0; area* = 1; contents* = 2; (* DisplayMsg id. *)
	get* = 0; set* = 1; reset* = 2; (*SelectMsg id*)
	drop* = 0; integrate* = 1; (*ConsumeMsg id*)
	
	unknown* = 0; index8* = 8; color555* = 16; color565* = 17; color664* = 18; color888* = 24; color8888* = 32;

	BitBLTAdr = 0B8000H;
	
TYPE Color* = LONGINT;

		Pattern* = LONGINT;
		PatternPtr = POINTER TO RECORD
			w, h: CHAR; pixmap: ARRAY 8192 OF CHAR
		END;
		List = POINTER TO ListDesc;
		ListDesc = RECORD
			next: List;
			pat: PatternPtr
		END;

		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD (Objects.ObjDesc)
			next*, dsc*: Frame;
			X*, Y*, W*, H*: INTEGER
		END;

		FrameMsg* = RECORD (Objects.ObjMsg)
			F*: Frame; (*target*)
			x*, y*, res*: INTEGER
		END;

		ControlMsg* = RECORD (FrameMsg)
			id*: INTEGER
		END;

		ModifyMsg* = RECORD (FrameMsg)
			id*, mode*: INTEGER;
			dX*, dY*, dW*, dH*: INTEGER;
			X*, Y*, W*, H*: INTEGER
		END;

		DisplayMsg* = RECORD (FrameMsg)
			device*: INTEGER;
			id*: INTEGER;
			u*, v*, w*, h*: INTEGER
		END;

		LocateMsg* = RECORD (FrameMsg)
			loc*: Frame;
			X*, Y*, u*, v*: INTEGER
		END;

		SelectMsg* = RECORD (FrameMsg)
			id*: INTEGER;
			time*: LONGINT;
			sel*: Frame;
			obj*: Objects.Object
		END;

		ConsumeMsg* = RECORD (FrameMsg)
			id*: INTEGER;
			u*, v*: INTEGER;
			obj*: Objects.Object
		END;

		MsgProc* = PROCEDURE (VAR M: FrameMsg);

		BitBLTPtr = POINTER TO RECORD
			bg : ARRAY 4 OF SHORTINT;					(* Background Color for Patterns *)
			fg : ARRAY 4 OF SHORTINT;					 (* Foreground Color for Patterns *)
			Width, Height : INTEGER;						 (* BLT Width & Height *)
			DestLen, SrcLen : INTEGER;					  (* Dest & Src Scanline Lenght *)
			DestLo : INTEGER; DestHi : SHORTINT;	(* Dest address *)
			SrcLo : INTEGER; SrcHi : SHORTINT;		 (* Src address *)
			Mask : SHORTINT;									 (* Map Mask *)
			Mode, dmy2 : SHORTINT;						 (* BLT Mode *)
			Op : SHORTINT;										(* Raster Operation *)
			dmy3 : ARRAY 37 OF CHAR;
			Start : SHORTINT;									 (* Start / Reset *)
		END;

VAR Unit*: LONGINT; (* RasterUnit = Unit/36000 mm *)
		Left*,			(* left margin of black-and-white maps *)
		ColLeft*,	   (* left margin of color maps *)
		Bottom*,	  (* bottom of primary map *)
		UBottom*,	(* bottom of secondary map *)
		Width*,		 (* map width *)
		Height*:		(* map hight*)
			INTEGER;

		arrow*, star*, cross*, downArrow*, hook*,
		grey0*, grey1*, grey2*, ticks*, solid*: Pattern;

		Broadcast*: MsgProc;

		Pat: List;
		clipx, clipy, clipright, cliptop : INTEGER;

		CurBank, patterns, patLo : INTEGER;
		patHi : SHORTINT;
		PageSize : LONGINT;

		DispMem : LONGINT;
		depth: INTEGER;
		palette: ARRAY 256 OF LONGINT;

PROCEDURE Map*(x: LONGINT): LONGINT;
BEGIN RETURN SYSTEM.VAL (LONGINT, DispMem)
END Map;

PROCEDURE Min (a, b : INTEGER) : INTEGER;
BEGIN	IF a < b THEN RETURN a ELSE RETURN b END
END Min;

PROCEDURE Max (a, b : INTEGER) : INTEGER;
BEGIN	IF a > b THEN RETURN a ELSE RETURN b END
END Max;

PROCEDURE AdjustClip*(x, y, w, h: LONGINT);
BEGIN
	clipx := Max (clipx, SHORT(x));	clipy := Max (clipy, SHORT(y));
	clipright := Min (clipright, SHORT(x+w));	cliptop := Min (cliptop, SHORT(y+h));
END AdjustClip;

PROCEDURE GetDim*(pat: Pattern; VAR w, h: INTEGER);
VAR s: CHAR;
BEGIN	SYSTEM.GET(pat, s); w := ORD(s); SYSTEM.GET(pat+1, s); h := ORD(s)
END GetDim;

PROCEDURE ResetClip*;
BEGIN	clipx := 0; clipy := UBottom; clipright := Width; cliptop := Height
END ResetClip;

PROCEDURE SetClip*(x, y, w, h: LONGINT);
BEGIN
	clipx := Max (SHORT(x), 0);	clipy := Max (SHORT(y), UBottom);
	clipright := Min (SHORT(x+w), Width);	cliptop := Min (SHORT(y+h), Height);
END SetClip;

PROCEDURE GetClip*(VAR x, y, w, h: INTEGER);
BEGIN	x:= clipx; y:= clipy; w:= clipright-clipx; h:= cliptop-clipy
END GetClip;

PROCEDURE SetColor*(col: Color; red, green, blue: LONGINT);	(* 0 <= col, red, green, blue < 256 *)
BEGIN
	palette[col] := ASH(ASH(red, 8) + green, 8) + blue;
	red := red DIV 4;
	green := green DIV 4;
	blue := blue DIV 4;
	SYSTEM.PORTOUT(3C8H, CHR(col));			(* VGA - write color entry *)
	SYSTEM.PORTOUT(3C9H, CHR(red));
	SYSTEM.PORTOUT(3C9H, CHR(green));
	SYSTEM.PORTOUT(3C9H, CHR(blue))
END SetColor;

PROCEDURE GetColor*(col: Color; VAR red, green, blue: INTEGER);
BEGIN
	IF col >= 0 THEN col := palette[col] END;
	red := SHORT(ASH(col, -16) MOD 256);
	green := SHORT(ASH(col, -8) MOD 256);
	blue := SHORT(col MOD 256)
END GetColor;

PROCEDURE RGB*(red, green, blue: LONGINT): Color;
BEGIN
	RETURN MIN(LONGINT) + ASH(red, 16) + ASH(green, 8) + blue
END RGB;

PROCEDURE -XOR (adr : LONGINT; val : CHAR);
CODE {SYSTEM.i386}
	POP EAX
	POP EBX
	XOR 0[EBX], AL
END XOR;

PROCEDURE Dot*(col: Color; x, y, mode: LONGINT);
VAR Offset : LONGINT; Bank : INTEGER;
BEGIN
	IF (y < clipy) OR (x < clipx) OR (y >= cliptop) OR (x >= clipright) THEN RETURN END;

	Offset := (Height-y-1)*Width + x;
	Bank := SHORT (Offset DIV PageSize);
	Offset := Offset MOD PageSize;
	IF Bank # CurBank THEN
		CurBank := Bank * SHORT(PageSize DIV 4092);
		SYSTEM.PORTOUT (03CEH, 09H);
		SYSTEM.PORTOUT (03CFH, CHR(CurBank))
	END;
	IF mode = invert THEN XOR (DispMem+Offset, CHR(col))
	ELSE SYSTEM.PUT(DispMem+Offset, CHR(col))
	END
END Dot;

PROCEDURE CopyBlock*(sx, sy, w, h, dx, dy, mode: LONGINT);
VAR  SourceAddr, DestAddr, delta : LONGINT; BitBLT : BitBLTPtr;
BEGIN
	IF dx+w > clipright THEN w := clipright - dx END;
	IF dy+h > cliptop THEN h := cliptop - dy END;
	IF dx < clipx THEN w := w - (clipx-dx); sx := sx + (clipx-dx); dx := clipx END;
	IF dy < clipy THEN h := h - (clipy-dy); sy := sy + (clipy-dy); dy := clipy END;
	IF (w <= 0) OR (h <= 0) THEN RETURN END;

	BitBLT := SYSTEM.VAL(BitBLTPtr, BitBLTAdr);
	SourceAddr := (Height-sy-h)*Width + sx;
	DestAddr := (Height-dy-h)*Width + dx;
	IF DestAddr <= SourceAddr THEN BitBLT.Mode := 0
	ELSE
		delta := (h-1)*Width + w-1;
		SourceAddr := SourceAddr + delta;
		DestAddr := DestAddr + delta;
		BitBLT.Mode := 1
	END;

	BitBLT.Width := SHORT(w-1);	BitBLT.Height := SHORT(h-1);
	BitBLT.DestLo := SHORT (DestAddr MOD (256*256));	BitBLT.DestHi := SHORT (SHORT (DestAddr DIV (256*256)));
	BitBLT.SrcLo := SHORT (SourceAddr MOD (256*256));	BitBLT.SrcHi := SHORT (SHORT (SourceAddr DIV (256*256)));
	IF mode < 2 THEN BitBLT.Op := 0DH ELSE BitBLT.Op := 59H END;	BitBLT.Start := 2;
	REPEAT UNTIL (BitBLT.Start MOD 2 = 0);
END CopyBlock;

PROCEDURE SetMode*(x: LONGINT; s: SET);
BEGIN
END SetMode;

PROCEDURE ReversePattern (pat, dest : LONGINT; len, minw, maxw, minh, maxh : INTEGER);
VAR  a, b : INTEGER;
		i, j, k, outlen : INTEGER;
BEGIN
	pat := pat+2+len*(maxh-1);
	outlen := (maxw-minw+7) DIV 8;
	FOR k := minh TO maxh-1 DO
		i := minw;	a := 0;	SYSTEM.GET(pat + i DIV 8, SYSTEM.VAL(CHAR, a));
		IF i MOD 8 # 0 THEN FOR j := 1 TO i MOD 8 DO a := a DIV 2 END END;
		j := 0;	b := 0;
		REPEAT	b := b*2 + a MOD 2;	a := a DIV 2;
			INC (i);	IF i MOD 8 = 0 THEN SYSTEM.GET(pat + i DIV 8, SYSTEM.VAL(CHAR, a)) END;
			IF j MOD 8 = 7 THEN SYSTEM.PUT(dest + j DIV 8, CHR(b)); b := 0 END;	INC (j)
		UNTIL j = outlen*8;
		SYSTEM.PUT(dest + j DIV 8, CHR(b));
		pat := pat - len; dest := dest + outlen
	END;
END ReversePattern;

PROCEDURE CopyPattern* (col: Color; pat: Pattern; x, y, mode: LONGINT);
VAR k : INTEGER;
		w, h, len : INTEGER;
		dst : LONGINT;
		minh, maxh, minw, maxw : INTEGER;
		BitBLT : BitBLTPtr;
BEGIN
	GetDim (pat, w, h);
	len := (w+7) DIV 8;
	
	minh := 0; maxh := h; minw := 0; maxw := w;
	IF x < clipx THEN minw := SHORT(clipx-x) END;
	IF x+w > clipright THEN maxw := SHORT(clipright-x) END;
	IF y < clipy THEN minh := SHORT(clipy-y) END;
	IF y+h > cliptop THEN maxh := SHORT(cliptop-y) END;
	IF (minh >= maxh) OR (minw >= maxw) THEN RETURN END;

	IF CurBank # patterns THEN
		CurBank := patterns;
		SYSTEM.PORTOUT (03CEH, 09H);
		SYSTEM.PORTOUT (03CFH, CHR(CurBank))
	END;
	ReversePattern (pat, 0A0000H, len, minw, maxw, minh, maxh);
	dst := (Height-y-maxh)*Width + x + minw;
	BitBLT := SYSTEM.VAL(BitBLTPtr, BitBLTAdr);

	FOR k := 0 TO 3 DO BitBLT.fg[k] := SYSTEM.VAL (SHORTINT, col) END;
	IF mode = replace THEN col := BG ELSE col := -col-1 END;
	FOR k := 0 TO 3 DO BitBLT.bg[k] := SYSTEM.VAL(SHORTINT, col) END;
	BitBLT.Width := maxw-minw-1;	BitBLT.Height := maxh-minh-1;
	BitBLT.DestLo := SYSTEM.VAL (INTEGER, dst);	BitBLT.DestHi := SHORT (SHORT (dst DIV (256*256)));
	BitBLT.SrcLo := patLo;	BitBLT.SrcHi := patHi;
	IF mode = replace THEN BitBLT.Mode := SYSTEM.VAL (SHORTINT, 80H)
	ELSE BitBLT.Mode := SYSTEM.VAL (SHORTINT, 88H) END;
	IF mode = invert THEN BitBLT.Op := 59H ELSE BitBLT.Op := 0DH END;
	BitBLT.Start := 2;
	REPEAT UNTIL BitBLT.Start MOD 2 = 0;
END CopyPattern;

PROCEDURE ReplConst* (col: Color; x, y, w, h, mode: LONGINT);
VAR fill : SET; dest : LONGINT; BitBLT : BitBLTPtr;
BEGIN
	IF x < clipx THEN w := w - (clipx-x); x := clipx END;
	IF y < clipy THEN h := h - (clipy-y); y := clipy END;
	IF x+w > clipright THEN w := clipright-x END;
	IF y+h > cliptop THEN h := cliptop-y END;
	IF (h <= 0) OR (w <= 0) THEN RETURN END;
	
	IF CurBank # patterns THEN
		CurBank := patterns;
		SYSTEM.PORTOUT (03CEH, 09H);
		SYSTEM.PORTOUT (03CFH, CHR(patterns))
	END;
	fill := {0..31};
	SYSTEM.PUT(0A0000H, fill);
	SYSTEM.PUT(0A0004H, fill);
	dest := (Height-y-h)*Width + x;
	
	BitBLT := SYSTEM.VAL(BitBLTPtr, BitBLTAdr);
	BitBLT.fg[0] := SYSTEM.VAL(SHORTINT, col);
	BitBLT.Width := SHORT(w-1);	BitBLT.Height := SHORT(h-1);
	BitBLT.DestLo := SHORT (dest);	BitBLT.DestHi := SHORT (SHORT (dest DIV (256*256)));
	BitBLT.SrcLo := patLo;	BitBLT.SrcHi := patHi;
	BitBLT.Mode := SYSTEM.VAL (SHORTINT, 0C0H);
	IF mode = invert THEN BitBLT.Op := 59H ELSE BitBLT.Op := 0DH END;
	BitBLT.Start := 2;
	REPEAT UNTIL BitBLT.Start MOD 2 = 0
END ReplConst;

PROCEDURE FillPattern*(col: Color; pat: Pattern; px, py, x, y, w, h, mode: LONGINT);
VAR dh, dw, pw, ph, len, rw, rh : INTEGER;
		row, dest : LONGINT;
		i, j : INTEGER;
		bcol : INTEGER;
		BitBLT : BitBLTPtr;
BEGIN
	IF x < clipx THEN w := w - (clipx-x); x := clipx END;
	IF y < clipy THEN h := h - (clipy-y); y := clipy END;
	IF x+w > clipright THEN w := clipright-x END;
	IF y+h > cliptop THEN h := cliptop-y END;
	IF (h <= 0) OR (w <= 0) THEN RETURN END;
	
	IF CurBank # patterns THEN
		CurBank := patterns;
		SYSTEM.PORTOUT (03CEH, 09H);
		SYSTEM.PORTOUT (03CFH, SYSTEM.VAL (CHAR, CurBank))
	END;

	BitBLT := SYSTEM.VAL(BitBLTPtr, BitBLTAdr);
	GetDim (pat, pw, ph);	len := (pw+7) DIV 8;
	dw := pw - (pw + SHORT(x-px) MOD pw) MOD pw;
	dh := ph - (ph + SHORT(y-py) MOD ph) MOD ph;
	FOR i := 0 TO 3 DO BitBLT.fg[i] := SYSTEM.VAL(SHORTINT, col) END;
	IF mode = replace THEN bcol := BG ELSE bcol := SHORT(-col-1) END;
	FOR i := 0 TO 3 DO BitBLT.bg[i] := SHORT(bcol) END;
	IF mode = replace THEN BitBLT.Mode := SYSTEM.VAL (SHORTINT, 80H)
	ELSE BitBLT.Mode := SYSTEM.VAL (SHORTINT, 88H) END;
	IF mode = invert THEN BitBLT.Op := 59H ELSE BitBLT.Op := 0DH END;
	
	IF dh > h THEN ph := ph-SHORT(dh-h); dh := SHORT(h) END;
	IF dw > w THEN pw := pw-SHORT(dw-w); dw := SHORT(w) END;
	w := w-dw;	h := h-dh;	y := y+dh;
	
	IF (dh > 0) & (w > 0) THEN		(* lower row *)
		ReversePattern (pat, 0A0000H, len, 0, pw, ph-dh, ph);
		BitBLT.Width := pw-1;	BitBLT.Height := dh-1;
		dest := (Height-y)*Width + x+dw;
		FOR i := 1 TO SHORT(w) DIV pw DO
			BitBLT.DestLo := SYSTEM.VAL (INTEGER, dest);	BitBLT.DestHi := SHORT (SHORT (dest DIV (256*256)));
			BitBLT.SrcLo := patLo;	BitBLT.SrcHi := patHi;
			BitBLT.Start := 2;
			REPEAT UNTIL BitBLT.Start MOD 2 = 0;
			dest := dest + pw;
		END;
		rw := SHORT(w) MOD pw;
		IF rw > 0 THEN
			ReversePattern (pat, 0A0000H, len, 0, rw, ph-dh, ph);
			BitBLT.Width := rw-1;
			BitBLT.DestLo := SHORT (dest);	BitBLT.DestHi := SHORT (SHORT (dest DIV (256*256)));
			BitBLT.SrcLo := patLo;	BitBLT.SrcHi := patHi;
			BitBLT.Start := 2;
			REPEAT UNTIL BitBLT.Start MOD 2 = 0;
		END;
	END;
	
	IF (dw > 0) & (h > 0) THEN		(* left column *)
		ReversePattern (pat, 0A0000H, len, pw-dw, pw, 0, ph);
		BitBLT.Width := dw-1;	BitBLT.Height := ph-1;
		dest := (Height-y)*Width + x;
		FOR i := 1 TO SHORT(h) DIV ph DO
			dest := dest - LONG(Width)*ph;
			BitBLT.DestLo := SHORT (dest);	BitBLT.DestHi := SHORT (SHORT (dest DIV (256*256)));
			BitBLT.SrcLo := patLo;	BitBLT.SrcHi := patHi;
			BitBLT.Start := 2;
			REPEAT UNTIL BitBLT.Start MOD 2 = 0;
		END;
		rh := SHORT(h) MOD ph;
		IF rh > 0 THEN
			ReversePattern (pat, 0A0000H, len, pw-dw, pw, 0, rh);
			BitBLT.Height := rh-1;
			dest := dest - LONG(Width)*rh;
			BitBLT.DestLo := SHORT (dest);	BitBLT.DestHi := SHORT (SHORT (dest DIV (256*256)));
			BitBLT.SrcLo := patLo;	BitBLT.SrcHi := patHi;
			BitBLT.Start := 2;
			REPEAT UNTIL BitBLT.Start MOD 2 = 0;
		END;
	END;
	
	IF (dw > 0) & (dh > 0) THEN		(* bottom left corner *)
		ReversePattern (pat, 0A0000H, len, pw-dw, pw, ph-dh, ph);
		BitBLT.Width := dw-1;	BitBLT.Height := dh-1;
		dest := (Height-y)*Width + x;
		BitBLT.DestLo := SHORT (dest);	BitBLT.DestHi := SHORT (SHORT (dest DIV (256*256)));
		BitBLT.SrcLo := patLo;	BitBLT.SrcHi := patHi;
		BitBLT.Start := 2;
		REPEAT UNTIL BitBLT.Start MOD 2 = 0;
	END;

	x := x+dw;
	ReversePattern (pat, 0A0000H, len, 0, pw, 0, ph);		(* easy rectangle *)	(*********************************)
	row := (Height-y)*Width + x;
	BitBLT.Width := pw-1;	BitBLT.Height := ph-1;
	FOR i := 1 TO SHORT(w) DIV pw DO
		dest := row;
		FOR j := 1 TO SHORT(h) DIV ph DO
			dest := dest - LONG(Width)*ph;
			BitBLT.DestLo := SHORT (dest);	BitBLT.DestHi := SHORT (SHORT (dest DIV (256*256)));
			BitBLT.SrcLo := patLo;	BitBLT.SrcHi := patHi;
			BitBLT.Start := 2;
			REPEAT UNTIL BitBLT.Start MOD 2 = 0;
		END;
		row := row+pw;
	END;
	rh := SHORT(h) MOD ph;
	IF rh > 0 THEN			(* top line *)
		BitBLT.Height := rh-1;
		SYSTEM.MOVE (0A0000H + (ph-rh)*len, 0A0000H, rh*len);
		dest := (Height-y-h)*Width + x;
		FOR i := 1 TO SHORT(w) DIV pw DO
			BitBLT.DestLo := SHORT (dest);	BitBLT.DestHi := SHORT (SHORT (dest DIV (256*256)));
			BitBLT.SrcLo := patLo;	BitBLT.SrcHi := patHi;
			BitBLT.Start := 2;
			REPEAT UNTIL BitBLT.Start MOD 2 = 0;
			dest := dest + pw
		END;
	END;
	rw := SHORT(w) MOD pw;
	IF rw > 0 THEN			(* last column *)
		ReversePattern (pat, 0A0000H, len, 0, rw, 0, ph);
		BitBLT.Width := rw-1;	BitBLT.Height := ph-1;
		dest := (Height-y)*Width + x+w-rw;
		FOR i := 1 TO SHORT(h) DIV ph DO
			dest := dest - LONG(Width)*ph;
			BitBLT.DestLo := SHORT (dest);	BitBLT.DestHi := SHORT (SHORT (dest DIV (256*256)));
			BitBLT.SrcLo := patLo;	BitBLT.SrcHi := patHi;
			BitBLT.Start := 2;
			REPEAT UNTIL BitBLT.Start MOD 2 = 0;
		END;
		IF rh > 0 THEN
			BitBLT.Height := rh-1;
			SYSTEM.MOVE (0A0000H + (ph-rh)*((rw+7) DIV 8), 0A0000H, rh*((rw+7) DIV 8));
			dest := dest - LONG(Width)*rh;
			BitBLT.DestLo := SHORT (dest);	BitBLT.DestHi := SHORT (SHORT (dest DIV (256*256)));
			BitBLT.SrcLo := patLo;	BitBLT.SrcHi := patHi;
			BitBLT.Start := 2;
			REPEAT UNTIL BitBLT.Start MOD 2 = 0;
		END
	END
END FillPattern;

PROCEDURE ReplPattern*(col: Color; pat: Pattern; x, y, w, h, mode: LONGINT);
BEGIN
	FillPattern (col, pat, 0, 0, x, y, w, h, mode)
END ReplPattern;

PROCEDURE NewPattern*(w, h: LONGINT; VAR image: ARRAY OF SET): Pattern;
VAR len, src, dest, i: LONGINT; p: PatternPtr; pl: List;
BEGIN 
	len := (w+7) DIV 8;
	SYSTEM.NEW(p, 4+len*h); p.w := CHR(w); p.h := CHR(h);
	src := SYSTEM.ADR(image); dest := SYSTEM.ADR(p.pixmap);
	i := 0;
	WHILE i < h DO SYSTEM.MOVE(src, dest, len); INC(src, 4); INC(dest, len); INC(i) END;
	NEW(pl);  pl.pat := p;  pl.next := Pat;  Pat := pl;	(* put in list to avoid GC *)
	RETURN SYSTEM.ADR(p.w)
END NewPattern;

PROCEDURE CreatePatterns;
VAR image: ARRAY 256 OF SET;
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
	downArrow := NewPattern(15, 15, image);
	
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
	hook:= NewPattern(12, 12, image);

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
	solid := NewPattern(16, 2, image);
	
END CreatePatterns;
	
PROCEDURE Depth*(x: LONGINT): INTEGER;
BEGIN
	RETURN depth
END Depth;

PROCEDURE TrueColor*(x: LONGINT): BOOLEAN;
BEGIN
	RETURN FALSE
END TrueColor;

PROCEDURE DisplayBlock*(adr, dx, dy, w, h, sx, sy, mode: LONGINT);
VAR BlockLen : LONGINT;
		Source, Dest : LONGINT;
		i, j, len : INTEGER;
		Screen, Block, Temp : LONGINT;
		BitBLT : BitBLTPtr;
BEGIN
	BlockLen := 0;
	SYSTEM.GET(adr+8, BlockLen);
	len := SHORT(w+3) DIV 4;
	SYSTEM.GET(adr+12, Source);
	Source := Source + dy*BlockLen + dx;
	Dest := (Height-sy-1)*Width + sx;
	Screen := 0A0000H;
	BitBLT := SYSTEM.VAL(BitBLTPtr, BitBLTAdr);
	BitBLT.Width := SHORT(w-1);	BitBLT.Height := 0;
	BitBLT.Mode := 4;
	IF mode = invert THEN BitBLT.Op := 59H ELSE BitBLT.Op := 0DH END;
	FOR i := 0 TO SHORT(h-1) DO
		Block := Source;
		BitBLT.DestLo := SYSTEM.VAL (INTEGER, Dest);
		BitBLT.DestHi := SHORT (SHORT (Dest DIV (256*256)));
		BitBLT.Start := 2;
		FOR j := 0 TO (len-1)*4 BY 4 DO
			SYSTEM.GET(Block+j, Temp);
			SYSTEM.PUT(Screen+j, Temp)
		END;
		REPEAT UNTIL BitBLT.Start MOD 2 = 0;
		Dest := Dest-Width;	Source := Source+BlockLen;
	END;
END DisplayBlock;

	PROCEDURE TransferFormat*(x: LONGINT): LONGINT;
	BEGIN
		RETURN unknown
	END TransferFormat;

	PROCEDURE TransferBlock*(VAR buf: ARRAY OF CHAR;  ofs, stride, x, y, w, h, mode: LONGINT);
	BEGIN
		HALT(99)
	END TransferBlock;
	
PROCEDURE InitRegister;
CODE {SYSTEM.i386}
	MOV AX, 0017H			; map BLT engine to 0B8000H
	MOV DX, 03C4H
	OUT DX, AL
	MOV DX, 03C5H
	IN AL, DX						; GD5430 - map BitBLT to memory
	OR AX, 0044H
	OUT DX, AL
	MOV DispMem, 0A0000H

	MOV EBX, BitBLTAdr			; reset BLT engine
	MOV AX, 4
	MOV 40H[EBX], AL
END InitRegister;

PROCEDURE InitBitBLT;
VAR BitBLT: BitBLTPtr;
BEGIN
	BitBLT := SYSTEM.VAL(BitBLTPtr, BitBLTAdr);
	BitBLT.DestLen := Width;	BitBLT.SrcLen := Width;
	BitBLT.Mask := 0
END InitBitBLT;

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

PROCEDURE Init;
CONST PatSize = 64*1024;
VAR mem: LONGINT;
BEGIN
	Width := SHORT(GetVal("DWidth", 1024));	(* assume 1024 if not specified *)
	Height := SHORT(GetVal("DHeight", 768));	(* assume 768 if not specified *)
	IF GetVal("Color", 1) = 0 THEN depth := 1 ELSE depth := 8 END;
	mem := GetVal("DMem", 0)*1024;
	IF mem = 0 THEN	(* compute default *)
		mem := 512*1024;
		WHILE LONG(Width)*Height >= mem DO mem := mem*2 END
	END;
	DEC(mem, PatSize);	(* reserve space for patterns *)
	UBottom := SHORT(Height - mem DIV Width);
	patterns := SHORT(mem DIV 4096);	(* page number of patterns *)
	patHi := SHORT(SHORT(mem DIV 10000H));
	patLo := SHORT(mem MOD 10000H)
END Init;

BEGIN
	Init;
	Left:= 0; ColLeft:= 0; Bottom:= 0;
	Pat := NIL;

	ResetClip;
	CreatePatterns;
	Unit := 10000;

	CurBank:= patterns;
	SYSTEM.PORTOUT (03CEH, 09H);
	SYSTEM.PORTOUT (03CFH, CHR(CurBank));
	PageSize := 256 * 256;

	InitRegister;
	InitBitBLT;
	ReplConst(1, Width DIV 2, Height DIV 2, Width DIV 2, Height DIV 2, replace);
END Display.

Compiler.Compile GD54xx.Display.Mod\X ~
