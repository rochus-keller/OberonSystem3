(* OBERON System 3, Release 2.3.

Copyright 1999 ETH Zürich Institute for Computer Systems, 
ETH Center, CH-8092 Zürich. e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract. The full text can be downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE Display;

(* Type: S3 Trio64 (ard, pjm, Peter Matthias) *)

IMPORT Kernel, SYSTEM, Objects;

CONST
	BG* = 0; FG* = 15; (*background, foreground*)
	replace* = 0; paint* = 1; invert* = 2; (*operation modes*)
	
	remove* = 0; suspend* = 1; restore* = 2; newprinter* = 3; (*ControlMsg id*)
	reduce* = 0; extend* = 1; move* = 2; (*ModifyMsg id*)
	display* = 0; state* = 1; (*ModifyMsg mode*)
	screen* = 0; printer* = 1; (* DisplayMsg device *)
	full* = 0; area* = 1; contents* = 2; (* DisplayMsg id. *)
	get* = 0; set* = 1; reset* = 2; (*SelectMsg id*)
	drop* = 0; integrate* = 1; (*ConsumeMsg id*)
	
	unknown* = 0; index8* = 8; color555* = 16; color565* = 17; color664* = 18; color888* = 24; color8888* = 32;

	(* S3 Constants , packed MMIO *)
	curY= 0A8100H;		curX= 0A8102H;
	axStep= 0A8108H;		diaStep= 0A810AH;
	errTerm= 0A8110H;
	cmd= 0A8118H;
	shortStroke= 0A811CH;
	BGcol= 0A8120H;
	FGcol= 0A8124H;
	wrtMask= 0A8128H;
	rdMask= 0A812CH;
	ColorCMP= 0A8130H;
	BGmix= 0A8134H;	FGmix= 0A8136H;	AltMix= 0A8134H;
	ScissorsT= 0A8138H;	ScissorsL= 0A813AH;	(* clipping top, left *)
	ScissorsB= 0A813CH;	ScissorsR= 0A813EH;	(* clipping bottom, right *)
	PixCntl= 0A8140H;	MultMisc2= 0A8142H;
	MultMisc= 0A8144H;	ReadSel= 0A8146H;
	MinAxis= 0A8148H;	MajAxis= 0A814AH;

	pixTrans = 0AE2E8H;
	pixBase = 0A0000H;
	
	FBPhysAdr = 0E0000000H;
	RegPhysAdr = 0A0000H;
	RegSize = 10000H;

TYPE
	Color* = LONGINT;
	
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

VAR
	Unit*: LONGINT; (* RasterUnit = Unit/36000 mm *)
	Left*, (* left margin of black-and-white maps *)
	ColLeft*, (* left margin of color maps *)
	Bottom*, (* bottom of primary map *)
	UBottom*, (* bottom of secondary map *)
	Width*, (* map width *)
	Height*: INTEGER; (* map height *)
		
	arrow*, star*, cross*, downArrow*, hook*, 
	grey0*, grey1*, grey2*, ticks*, solid*: Pattern;

	Broadcast*: MsgProc;

	Pat: List;	(* root for patterns *)
	dmem, fbase, rbase: LONGINT;
	clipx, clipy, clipright, cliptop: LONGINT;	(* clipping variables *)

	depth: INTEGER;	(* "logical" indexed color depth 1 or 8 *)
		
	truecol: LONGINT;	(* 0 = 256-color palette, 1 = hicolor, 2 = truecolor *)
	colmap: ARRAY 256 OF LONGINT;	(* identity mapping (256-color) or soft palette (hicolor, truecolor) *)
	palette: ARRAY 256 OF LONGINT;	(* cache to speed up palette reading *)

PROCEDURE Wait;
VAR wait: INTEGER;
BEGIN
	REPEAT SYSTEM.GET( rbase+cmd, wait) UNTIL ~ODD( ASH( wait, -9));
END Wait;

PROCEDURE Map*(x: LONGINT): LONGINT;
BEGIN
	RETURN fbase		(* of linear framebuffer *)
END Map;

PROCEDURE AdjustClip*(x, y, w, h: LONGINT);
VAR right, top, left, bottom: LONGINT;
BEGIN
	right := x + w;
	IF x > clipx THEN clipx:= x END;
	IF right < clipright THEN clipright:= right END;
	left:= clipx;
	IF left < 0 THEN left := 0 ELSIF left > Width THEN left := Width-1 END;
	right := clipright-1;
	IF right < 0 THEN right := 0 ELSIF right > Width THEN right := Width-1 END;
	top := y + h;
	IF y> clipy THEN clipy:= y END;
	IF top< cliptop THEN cliptop:= top END;
	top := cliptop-1;
	IF top < 0 THEN top := 0 ELSIF top >= Height THEN top := Height-1 END;
	bottom := clipy;
	IF bottom < 0 THEN bottom := 0 ELSIF bottom > Height THEN bottom := Height-1 END;
	SYSTEM.PUT( rbase+ScissorsT, SYSTEM.VAL(INTEGER, 1000H+ Height-1-top));	(* top *)
	SYSTEM.PUT( rbase+ScissorsL, SYSTEM.VAL(INTEGER, 2000H+ left)); 	(* left *)
	SYSTEM.PUT( rbase+ScissorsB, SYSTEM.VAL(INTEGER, 3000H+ Height-1-bottom));	(* bottom *)
	SYSTEM.PUT( rbase+ScissorsR, SYSTEM.VAL(INTEGER, 4000H+ right))	(* right *)
END AdjustClip;

PROCEDURE GetDim*(pat: Pattern; VAR w, h: INTEGER);
VAR p: PatternPtr;
BEGIN
	p:= SYSTEM.VAL( PatternPtr, pat);
	w:= ORD(p^.w); h:= ORD(p^.h)
END GetDim;

PROCEDURE ResetClip*;
BEGIN 
	clipx := 0; clipy := UBottom; 
	clipright := Width;
	cliptop := Height;
	SYSTEM.PUT( rbase+ScissorsT, SYSTEM.VAL(INTEGER, 1000H));	(* top *)
	SYSTEM.PUT( rbase+ScissorsL, SYSTEM.VAL(INTEGER, 2000H));	(* left *)
	SYSTEM.PUT( rbase+ScissorsB, SYSTEM.VAL(INTEGER, 3000H+ Height-1-UBottom));	(* bottom *)
	SYSTEM.PUT( rbase+ScissorsR, SYSTEM.VAL(INTEGER, 4000H+ Width-1))	(* right *)
END ResetClip;

PROCEDURE SetClip*(x, y, w, h: LONGINT);
BEGIN	
	clipright := x+w;
	cliptop := y+h;
	clipy := y; clipx := x;
	SYSTEM.PUT( rbase+ScissorsT, SYSTEM.VAL(INTEGER, 1000H + Height-cliptop));	(* top *)
	SYSTEM.PUT( rbase+ScissorsL, SYSTEM.VAL(INTEGER, 2000H + clipx));	(* left *)
	SYSTEM.PUT( rbase+ScissorsB, SYSTEM.VAL(INTEGER, 3000H + Height-1-clipy));	(* bottom *)
	SYSTEM.PUT( rbase+ScissorsR, SYSTEM.VAL(INTEGER, 4000H + clipright-1)); 		 (* right *)
END SetClip;

PROCEDURE GetClip*(VAR x, y, w, h: INTEGER);
BEGIN 
	x := SHORT(clipx); y := SHORT(clipy); w := SHORT(clipright - clipx); h := SHORT(cliptop - clipy);
END GetClip;

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

(* Translate a Color value 

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

PROCEDURE Dot*(col: Color; x, y, mode: LONGINT);
BEGIN
	IF mode = invert THEN
		IF (truecol # 0) & (col = FG) THEN col := 80FFFFFFH END;
		SYSTEM.PUT(rbase+FGmix, LONG(25H))
	ELSE
		SYSTEM.PUT(rbase+FGmix, LONG(27H))
	END;
	SYSTEM.PUT(rbase+FGcol, TransColor(col));
	SYSTEM.PUT(rbase+PixCntl, LONG( 0));
	SYSTEM.PUT(rbase+curX, SHORT(x));
	SYSTEM.PUT(rbase+curY, SHORT(Height-1-y));
	Wait;
	SYSTEM.PUT(rbase+cmd, 121BH);
	SYSTEM.PUT(rbase+shortStroke, LONG(10H))
END Dot;

PROCEDURE CopyBlock*(sx, sy, w, h, dx, dy, mode: LONGINT);
VAR comd: INTEGER;
BEGIN
	IF (w > 0) & (h > 0) THEN
		comd := SYSTEM.VAL(INTEGER, 0C073H);
		IF sy <= dy THEN
			INC(sy, h-1); INC(dy, h-1); INC(comd, 128);
			IF sx < dx THEN INC(sx, w-1); INC(dx, w-1); DEC(comd, 32) END
		END;
		IF mode = invert THEN 
			SYSTEM.PUT(rbase+FGmix, LONG(65H))
		ELSE
			SYSTEM.PUT(rbase+FGmix, LONG(67H))
		END;
		SYSTEM.PUT(rbase+PixCntl, LONG(0));
		SYSTEM.PUT(rbase+curX, SHORT(sx));
		SYSTEM.PUT(rbase+curY, SHORT(Height - 1 - sy));
		SYSTEM.PUT(rbase+diaStep, SHORT(dx));
		SYSTEM.PUT(rbase+axStep, SHORT(Height -1 - dy));
		SYSTEM.PUT(rbase+MajAxis, SHORT(w-1));
		SYSTEM.PUT(rbase+MinAxis, SHORT(h-1));
		Wait;
		SYSTEM.PUT(rbase+cmd, comd)
	END
END CopyBlock;

PROCEDURE SetMode*(x: LONGINT; s: SET);
BEGIN
END SetMode;

PROCEDURE CopyPattern*(col: Color; pat: Pattern; x, y, mode: LONGINT);
VAR wth, pwidth, pos: LONGINT; p: PatternPtr;
BEGIN
	p:= SYSTEM.VAL( PatternPtr, pat);
	wth:=(ORD(p.w)+7) DIV 8;
	INC(x, wth*8-1); 
	y := Height-y-ORD(p.h);
	IF mode= invert THEN
		IF (truecol # 0) & (col = FG) THEN col := 80FFFFFFH END;
		SYSTEM.PUT(rbase+AltMix, 250003H)
	ELSIF mode= replace THEN
		SYSTEM.PUT(rbase+AltMix, 270001H)
	ELSE
		SYSTEM.PUT(rbase+AltMix, 270003H)
	END;
	SYSTEM.PUT(rbase+FGcol, TransColor(col));
	SYSTEM.PUT(rbase+PixCntl, ORD( 80X));
	SYSTEM.PUT(rbase+MajAxis, SHORT( wth*8-1));
	pos:= wth*ORD(p.h);
	WHILE pos>0 DO
		SYSTEM.PUT(rbase+curX, SHORT(x));
		SYSTEM.PUT(rbase+curY, SHORT(y));
		Wait;
		SYSTEM.PUT(rbase+cmd, 219BH);
		pwidth:= wth;
		REPEAT
			DEC( pos); DEC( pwidth);
			SYSTEM.PUT( rbase+pixTrans, p.pixmap[ pos]);
		UNTIL (pwidth<=0);
		INC( y)
	END
END CopyPattern;

PROCEDURE ReplConst*(col: Color; x, y, w, h, mode: LONGINT);
BEGIN
	IF (w > 0) & (h > 0) THEN 
		IF mode = invert THEN
			IF (truecol # 0) & (col = FG) THEN col := 80FFFFFFH END;
			SYSTEM.PUT(rbase+FGmix, LONG(25H))
		ELSE
			SYSTEM.PUT(rbase+FGmix, LONG(27H))
		END;
		SYSTEM.PUT(rbase+FGcol, TransColor(col));
		SYSTEM.PUT(rbase+PixCntl, LONG( 0));
		SYSTEM.PUT(rbase+curX, SHORT(x));
		SYSTEM.PUT(rbase+curY, SHORT(Height-1-y));
		SYSTEM.PUT(rbase+MajAxis, SHORT(w-1));
		SYSTEM.PUT(rbase+MinAxis, SHORT(h-1));
		Wait;
		SYSTEM.PUT(rbase+cmd, 4073H)
	END
END ReplConst;

PROCEDURE FillPattern*(col: Color; pat: Pattern; px, py, x, y, w, h, mode: LONGINT);
VAR bit16: INTEGER;  pat0, bit32, yo, hgt, wdt: LONGINT;  p: PatternPtr;
BEGIN 
	IF (w > 0) & (h > 0) THEN
		p:= SYSTEM.VAL( PatternPtr, pat);
		INC(pat, 2);
		INC(x, w-1);
		yo:= (y + py) MOD ORD(p.h);
		y := Height-1-y;
		IF mode= invert THEN
			IF (truecol # 0) & (col = FG) THEN col := 80FFFFFFH END;
			SYSTEM.PUT( rbase+AltMix, 250003H)
		ELSIF mode= replace THEN
			SYSTEM.PUT( rbase+AltMix, 270001H)
		ELSE
			SYSTEM.PUT( rbase+AltMix, 270003H)
		END;
		SYSTEM.PUT(rbase+FGcol, TransColor(col));
		SYSTEM.PUT(rbase+PixCntl, ORD( 80X));
		SYSTEM.PUT(rbase+MajAxis, SHORT(w-1));
		pat0 := pat+ ORD(p.w) DIV 8 * yo;
		hgt := ORD(p.h) - yo;
		WHILE h > 0 DO
			wdt:= ( w + 7 ) DIV 8;
			IF ORD(p.w) = 16 THEN
				SYSTEM.GET(pat0, bit16); INC(pat0, 2);
				bit32:= LONG( bit16)* 10000H+ LONG( bit16) MOD 10000H
			ELSIF ORD(p.w) = 32 THEN SYSTEM.GET(pat0, bit32); INC(pat0, 4)
			END;
			bit32 := SYSTEM.ROT(bit32, px-x);	(* SYSTEM.ROT(bit32, pX-X0+16) ?? *)
			SYSTEM.PUT(rbase+curX, SHORT(x));
			SYSTEM.PUT(rbase+curY, SHORT(y));
			Wait;
			SYSTEM.PUT(rbase+cmd, 239BH);
			WHILE wdt >0 DO
				SYSTEM.PUT(rbase+pixTrans, bit32);
				DEC( wdt,4)
			END;
			DEC(y);
			DEC(h); DEC(hgt);
			IF hgt <= 0 THEN hgt := ORD(p.h); pat0 := pat END
		END
	END
END FillPattern;

PROCEDURE ReplPattern*(col: Color; pat: Pattern; x, y, w, h, mode: LONGINT);
BEGIN
	FillPattern(col, pat, 0, 0, x, y, w, h, mode)
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

PROCEDURE Depth*(x: LONGINT): INTEGER;
BEGIN
	RETURN depth
END Depth;

PROCEDURE TrueColor*(x: LONGINT): BOOLEAN;
BEGIN
	RETURN truecol > 0
END TrueColor;

(* help procedures for DisplayBlock *)

PROCEDURE DB0( adr, bw, wdt, h: LONGINT);
CODE {SYSTEM.i386}
	MOV ESI, adr[ EBP]
	MOV EAX, bw[ EBP]
	MOV EBX, wdt[ EBP]
	ADD EBX, 3
	AND EBX, 0FFFFFFFCH
	SUB EAX, EBX
	SHR EBX, 2
	MOV EDX, h[ EBP]
	CLD
labY:
	MOV EDI, pixBase
	ADD EDI, rbase
	MOV ECX, EBX
	REP MOVSD
	ADD ESI, EAX
	DEC EDX
	JNZ labY
END DB0;

PROCEDURE DB1(adr, bw, wdt, h: LONGINT);
CODE {SYSTEM.i386}
	MOV ESI, adr[EBP]
	MOV ECX, wdt[EBP]
	INC ECX
	AND ECX, 0FFFFFFFEH
	SUB bw[EBP], ECX
	SHR ECX, 1
	MOV wdt[EBP], ECX
	LEA EDX, colmap
	CLD
labY:
	MOV EDI, pixBase
	ADD EDI, rbase
	MOV ECX, wdt[EBP]
loop:
	LODSW
	MOV EBX, EAX
	AND EAX, 0FFH
	SHR EBX, 8
	MOV EAX, [EDX][EAX*4]
	AND EBX, 0FFH
	MOV EBX, [EDX][EBX*4]
	SHL EBX, 16
	OR EAX, EBX
	STOSD
	LOOP loop
	ADD ESI, bw[EBP]
	DEC h[EBP]
	JNZ labY
END DB1;

PROCEDURE DB2(adr, bw, wdt, h: LONGINT);
CODE {SYSTEM.i386}
	MOV ESI, adr[EBP]
	MOV ECX, wdt[EBP]
	SUB bw[EBP], ECX
	LEA EDX, colmap
	CLD
labY:
	MOV EDI, pixBase
	ADD EDI, rbase
	MOV ECX, wdt[EBP]
loop:
	LODSB
	AND EAX, 0FFH
	MOV EAX, [EDX][EAX*4]
	STOSD
	LOOP loop
	ADD ESI, bw[EBP]
	DEC h[EBP]
	JNZ labY
END DB2;

(*
PROCEDURE DB0oberon( adr, bw, wdt, h: LONGINT);
VAR i, j: LONGINT;
BEGIN
	WHILE h>0 DO
		FOR i:=0 TO wdt BY 4 DO
			SYSTEM.GET( rbase+adr+i, j);
			SYSTEM.PUT( rbase+pixTrans, j);		(* pixTrans or 0A0000H..0A7FFCH *)
		END;			
		INC( adr, bw);
		DEC( h);
	END;
END DB0oberon;
*)

PROCEDURE DisplayBlock*(adr, dx, dy, w, h, sx, sy, mode: LONGINT);
VAR width, blockadr: LONGINT;
BEGIN
	SYSTEM.GET(adr+8, width);
	SYSTEM.GET(adr+12, blockadr);
	sy := Height-1-sy;
	IF mode = invert THEN
		SYSTEM.PUT(rbase+FGmix, SYSTEM.VAL(INTEGER, 45H))	(* invert *)
	ELSE
		SYSTEM.PUT(rbase+FGmix, SYSTEM.VAL(INTEGER, 47H))	(* replace, paint *)
	END;
	SYSTEM.PUT(rbase+PixCntl, SYSTEM.VAL(INTEGER, 0A000H));
	SYSTEM.PUT(rbase+curX, SHORT(sx));
	SYSTEM.PUT(rbase+curY, SHORT(sy));
	SYSTEM.PUT(rbase+MajAxis, SHORT(w-1));
	SYSTEM.PUT(rbase+MinAxis, SHORT(h-1));
	Wait;
	SYSTEM.PUT(rbase+cmd, SYSTEM.VAL(INTEGER, 5531H));
	CASE truecol OF
		0: DB0(blockadr + width*dy + dx, width, w, h)
		|1: DB1(blockadr + width*dy + dx, width, w, h)
		|2: DB2(blockadr + width*dy + dx, width, w, h)
	END
END DisplayBlock;

PROCEDURE TransferFormat*(x: LONGINT): LONGINT;
BEGIN
	CASE truecol OF
		0: x := index8
		|1: x := color565
		|2: x := color8888
	END;
	RETURN x
END TransferFormat;

PROCEDURE -Move(src, dst, size: LONGINT);
CODE {SYSTEM.i386}
	POP ECX
	POP EDI
	POP ESI
	CLD
	MOV BL, CL
	SHR ECX, 2
	AND BL, 3
	REP MOVSD
	MOV CL, BL
	REP MOVSB
END Move;

PROCEDURE TransferBlock*(VAR buf: ARRAY OF CHAR;  ofs, stride, x, y, w, h, mode: LONGINT);
VAR src, dst0, dst1, srcstride, ofs1: LONGINT;
BEGIN
	y := Height-1-y;
	IF mode = set THEN
		SYSTEM.PUT(rbase+FGmix, 47H);
		SYSTEM.PUT(rbase+PixCntl, LONG( 0H));
		SYSTEM.PUT(rbase+curX, SHORT(x));
		SYSTEM.PUT(rbase+curY, SHORT(y));
		SYSTEM.PUT(rbase+MajAxis, SHORT(w-1));
		SYSTEM.PUT(rbase+MinAxis, SHORT(h-1));
		Wait;
		SYSTEM.PUT(rbase+cmd, 5531H);
		DB0(SYSTEM.ADR(buf[ofs]), stride, ASH(w, truecol), h)
	ELSIF mode = get THEN
		ASSERT(w >= 0);
		src := fbase + ASH(y*Width + x, truecol);
		srcstride := ASH(Width, truecol);
		ofs1 := ASH(w, truecol)-1;
		WHILE h > 0 DO
			dst0 := SYSTEM.ADR(buf[ofs]);  dst1 := SYSTEM.ADR(buf[ofs+ofs1]);	(* index check *)
			Move(src, dst0, dst1-dst0+1);
			DEC(src, srcstride);  INC(ofs, stride);  DEC(h)
		END
	ELSE
		HALT(99)	(* bad mode *)
	END
END TransferBlock;

PROCEDURE GetVal(str: ARRAY OF CHAR;  default: LONGINT): LONGINT;
VAR i: SHORTINT;  v: LONGINT;  s: ARRAY 10 OF CHAR;
BEGIN
	Kernel.GetConfig(str, s);
	IF s[0] = 0X THEN
		v := default
	ELSE
		v := 0;  i := 0;
		WHILE s[i] # 0X DO v := v*10+(ORD(s[i])-48); INC(i) END
	END;
	RETURN v
END GetVal;

PROCEDURE InitS3;
VAR ch: CHAR; mask, i, mode: LONGINT;
BEGIN
	FOR i := 0 TO 255 DO colmap[i] := i END;
	truecol := GetVal("DDepth", 8) DIV 16;	(* 0, 1 or 2 *)
	mode := GetVal("Color", 1);	(* assume 1 if not specified *)
	IF mode = 0 THEN depth := 1 ELSE depth := 8 END;
	Width := SHORT(GetVal("DWidth", 1024));	(* assume 1024 if not specified *)
	Height := SHORT(GetVal("DHeight", 768));	(* assume 768 if not specified *)
	dmem := GetVal("DMem", 1024)*1024;	(* assume 1Mb if not specified *)
	SYSTEM.PORTOUT( 3D4H, 2DH);
	SYSTEM.PORTIN( 3D5H, ch);
	IF ch= 88X THEN
		SYSTEM.PORTOUT( 3D4H, 2EH);
		SYSTEM.PORTIN( 3D5H, ch);
		IF ch= 11X THEN																(*	Trio found	*)
			Width:=0; Height:=0;
			SYSTEM.PORTOUT( 3D4H, 5DH);								(* get Width *)
			SYSTEM.PORTIN( 3D5H, ch);
			IF ODD( ORD( ch) DIV 2) THEN Width:= 256*8 END;
			SYSTEM.PORTOUT( 3D4H, 1);
			SYSTEM.PORTIN( 3D5H, ch);
			INC( Width, ( ORD( ch)+1)*8);

			IF truecol = 1 THEN Width := Width DIV 2 END;
			SYSTEM.PORTOUT( 3D4H, 5EH);									(* get Height *)
			SYSTEM.PORTIN( 3D5H, ch);
			IF ODD( ORD( ch) DIV 2) THEN Height:= 1024 END;
			SYSTEM.PORTOUT( 3D4H, 7);
			SYSTEM.PORTIN( 3D5H, ch);
			IF ODD( ORD( ch) DIV 2) THEN INC( Height, 256) END;
			IF ODD( ORD( ch) DIV 64) THEN INC( Height, 512) END;
			SYSTEM.PORTOUT( 3D4H, 12H);
			SYSTEM.PORTIN( 3D5H, ch);
			INC( Height, ORD( ch)+1);

			SYSTEM.PORTOUT( 3D4H, 36H);									(* get MemSize *)
			SYSTEM.PORTIN( 3D5H, ch);
			mask:= ASH( ORD( ch), -5);
			IF mask= 0 THEN dmem:= 4096*1024;
			ELSIF mask= 4 THEN dmem:= 2048*1024;
			ELSE dmem:= 1024*1024;
			END;
		END;
	END;
	UBottom := Height - SHORT((dmem-4096) DIV Width DIV ASH(1, truecol)) + 1;	(* Space for 4 Sprites reserved *)

	Kernel.MapPhysical(RegPhysAdr, RegSize, rbase);
	ASSERT(rbase # 0);
	DEC(rbase, RegPhysAdr);
	
	SYSTEM.PORTOUT( 3D4H, 1053H);	(*	10H: enable old MMIO 18H: old & new MMIO	*)
	mask:= -1;
	SYSTEM.PUT(rbase+wrtMask, mask);				(* Write mask *)
	SYSTEM.PUT(rbase+rdMask, mask);					(* Read mask *)
	
	Kernel.MapPhysical(FBPhysAdr, dmem, fbase);
	IF fbase # 0 THEN										(* enable lfb *)
		SYSTEM.PORTOUT( 3D4H, 0831H);		(* CR31  bit 3: enhanced mode mapping*)
		IF dmem<=1024*1024 THEN SYSTEM.PORTOUT( 3D4H, 1158H);
		ELSIF dmem<=2024*1024 THEN SYSTEM.PORTOUT( 3D4H, 1258H);
		ELSE SYSTEM.PORTOUT( 3D4H, 1358H);		(* bit 4: enable lfb, bit 0,1: size: 0= 64k, 1=1MB, 2= 2MB, 3= 4MB *)
		END;
		SYSTEM.PORTOUT( 3D4H, 59H);			(* set base adr for lfb *)
		SYSTEM.PORTOUT( 3D5H, CHR( ASH( FBPhysAdr, -24) MOD 100H));
		SYSTEM.PORTOUT( 3D4H, 5AH);
		SYSTEM.PORTOUT( 3D5H, CHR( ASH( FBPhysAdr, -16) MOD 100H));
(*
		SYSTEM.PORTOUT( 3D4H, 33H);			(* disable border *)
		SYSTEM.PORTIN( 3D5H, ch);
		SYSTEM.PORTOUT( 3D5H, SYSTEM.VAL( CHAR, SYSTEM.VAL( SET, ch)+{5}));
*)
	END;
	SYSTEM.PORTOUT( 3C4H, SYSTEM.VAL( INTEGER, 8009H));		(* disable programmed I/O *)
	
	Kernel.WriteString("S3Trio: ");  Kernel.WriteInt(Width, 1);
	Kernel.WriteChar("x");  Kernel.WriteInt(Height, 1);
	CASE truecol OF
		0: Kernel.WriteString(" 8-bit indexed")
		|1: Kernel.WriteString(" 5,6,5-bit RGB")
		|2: Kernel.WriteString(" 8,8,8-bit RGB")
	END;
	Kernel.WriteString(" (+");  Kernel.WriteInt(-UBottom, 1);
	Kernel.WriteString(" offscreen)");
	Kernel.WriteLn
END InitS3;

BEGIN
	Left:= 0; ColLeft:= 0; Bottom:= 0;
	Pat := NIL;
	InitS3;
	ResetClip;
	CreatePatterns;
	Unit := 10000
END Display.

(*
# Trio64 Display settings
#      0103   800  600  256  P8   0
#      0205  1024  768  256  P8   0
#      0107  1280 1024  256  P8   0
#      0211   640  480  64k  P16  1
#      0111   640  480  64k  P16  1
#      0114   800  600  64k  P16  1
#      0117  1024  768  64k  P16  1
#      011A  1280 1024  64k  P16  1
#      0212   640  480  16m  P24  2
#      0112   640  480  16m  P32  2
#      0115   800  600  16m  P32  2
#      0118  1024  768  16m  P32  2
*)

(*
Compiler.Compile S3Trio.Display.Mod\X ~
*)
