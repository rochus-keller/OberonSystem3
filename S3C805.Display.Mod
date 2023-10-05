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

MODULE Display;	(* 86C805/801 ard, eos, pjm *)

	IMPORT SYSTEM, Objects, Kernel;
	
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

		(* S3 Constants *)
		index = 3D4H;
		data = 3D5H;
		Xpos = 20H;
		Ypos = 80H;
		Ymajor = 40H;
		advFnCtrl = 4AE8H;
		curX = 86E8H;
		curY = 82E8H;
		axStep = 8AE8H;
		diaStep = 8EE8H;
		errTerm = 92E8H;
		majAxis = 96E8H;
		minAxis = 0BEE8H;
		gpStat = 9AE8H;
		cmdReg = 9AE8H;
		shortStroke = 9EE8H;
		BGcol = 0A2E8H;
		FGcol = 0A6E8H;
		wrtMask = 0AAE8H;
		rdMask = 0AEE8H;
		BGmix = 0B6E8H;
		FGmix = 0BAE8H;
		MFcont = 0BEE8H;
		pixTrans = 0E2E8H;

	TYPE Color* = LONGINT;
	
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
		Height*: (* map hight*)
			INTEGER;
			
		arrow*, star*, cross*, downArrow*, hook*,
		grey0*, grey1*, grey2*, ticks*, solid*: Pattern;

		Broadcast*: MsgProc;

		dmem: LONGINT;
		
		Pat: List;

		clipx, clipy, clipright, cliptop, height, width: INTEGER;	(* clipping variables *)
		pixctrl1, pixctrl2, copycmd: LONGINT;	
		mask: INTEGER;
		
		depth: INTEGER;
		palette: ARRAY 256 OF LONGINT;
	
	PROCEDURE WaitFIFOempty;
	CODE {SYSTEM.i386}
		MOV DX, 9AE8H
lab1:
		IN AX, DX
		AND AX, 200H
		JNZ lab1
	END WaitFIFOempty;
	
	PROCEDURE EnableRegs;
	BEGIN
		WaitFIFOempty;
		SYSTEM.PORTOUT(wrtMask, mask);		; (* Write mask *)
		SYSTEM.PORTOUT(rdMask, mask);		; (* Read mask *)
	END EnableRegs;
		
	PROCEDURE max (i, j: INTEGER): INTEGER; BEGIN IF i >= j THEN RETURN i ELSE RETURN j END END max;
	PROCEDURE min (i, j: INTEGER): INTEGER; BEGIN	IF i >= j THEN RETURN j ELSE RETURN i END END min;
		
	PROCEDURE Map*(x: LONGINT): LONGINT;
	BEGIN RETURN 0A0000H	(* Start of the video RAM *)
	END Map;
	
	PROCEDURE AdjustClip*(x, y, w, h: LONGINT);
	VAR right, top, left, bottom: INTEGER;
	BEGIN 
		right := SHORT(x + w); top := SHORT(y + h);
		clipx := max(clipx, SHORT(x)); clipy := max(clipy, SHORT(y)); 
		clipright := min(right, clipright); cliptop := min(top, cliptop);
		top := height-1-cliptop; left := clipx; bottom := height-1-clipy; right := clipright-1;
		IF top < 0 THEN top := 0 ELSIF top > height-1 THEN top := height-1 END;
		IF left < 0 THEN left := 0 ELSIF left > width THEN left := width END;
		IF bottom < 0 THEN bottom := 0 ELSIF bottom > height-1 THEN bottom := height-1 END;
		IF right < 0 THEN right := 0 ELSIF right > width THEN right := width END;
		WaitFIFOempty;
		SYSTEM.PORTOUT(MFcont, 1000H + top);	(* top *)
		SYSTEM.PORTOUT(MFcont, 2000H + left); 			 (* left *)
		SYSTEM.PORTOUT(MFcont, 3000H + bottom);	(* bottom *)
		SYSTEM.PORTOUT(MFcont, 4000H + right); 		 (* right *)
	END AdjustClip;

	PROCEDURE GetDim*(pat: Pattern; VAR w, h: INTEGER);
	VAR s: CHAR;
	BEGIN SYSTEM.GET(pat, s); w := ORD(s); SYSTEM.GET(pat+1, s); h := ORD(s); 
	END GetDim;

	PROCEDURE ResetClip*;
	BEGIN 
		clipx := 0; clipy := UBottom; 
		clipright := width;
		cliptop := height-1;
		WaitFIFOempty;
		SYSTEM.PORTOUT(MFcont, 1000H);	(* top *)
		SYSTEM.PORTOUT(MFcont, 2000H);	(* left *)
		SYSTEM.PORTOUT(MFcont, 3000H + height-1-UBottom);	(* bottom *)
		SYSTEM.PORTOUT(MFcont, 4000H + width-1);	(* right *)
	END ResetClip;
	
	PROCEDURE SetClip*(x, y, w, h: LONGINT);
	VAR right, top, left, bottom: INTEGER;
	BEGIN	
		clipright := SHORT(x+w);
		cliptop := SHORT(y+h);
		clipy := SHORT(y); clipx := SHORT(x);
		top := height-1-cliptop; left := clipx; bottom := height-1-clipy; right := clipright-1;
		WaitFIFOempty;
		SYSTEM.PORTOUT(MFcont, 1000H + top);	(* top *)
		SYSTEM.PORTOUT(MFcont, 2000H + left); 			 (* left *)
		SYSTEM.PORTOUT(MFcont, 3000H + bottom);	(* bottom *)
		SYSTEM.PORTOUT(MFcont, 4000H + right); 		 (* right *)
	END SetClip;
	
	PROCEDURE GetClip*(VAR x, y, w, h: INTEGER);
	BEGIN 
		x := clipx; y := clipy; w := clipright - clipx; h := cliptop - clipy
	END GetClip;

	PROCEDURE SetColor*(col: Color; red, green, blue: LONGINT);	(* 0 <= col, red, green, blue < 256 *)
	VAR ch: CHAR;
	BEGIN
		palette[col] := ASH(ASH(red, 8) + green, 8) + blue;
		IF (col = 0) OR (col = 15) THEN	(* either 0 or 15 must be black.  set the border to black. *)
				(* note: the S3 uses the palette for the border colour too *)
			SYSTEM.PORTIN(3DAH, ch);
			SYSTEM.PORTOUT(3C0H, 11X);
			IF (red = 0) & (green = 0) & (blue = 0) THEN SYSTEM.PORTOUT(3C0H, CHR(col))
			ELSE SYSTEM.PORTOUT(3C0H, CHR(15-col))
			END;
			SYSTEM.PORTOUT(3C0H, 20X)
		END;
		red := (red + 4) DIV 4 - 1;
		green := (green + 4) DIV 4 - 1;
		blue := (blue + 4) DIV 4 - 1;
		SYSTEM.PORTOUT(3C8H, CHR(col));
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

	PROCEDURE Dot*(col: Color; x, y, mode: LONGINT);
	BEGIN
		y := Height-1-y;
		WaitFIFOempty;
		IF mode = invert THEN SYSTEM.PORTOUT(FGmix, LONG(25H)) ELSE SYSTEM.PORTOUT(FGmix, LONG(27H)) END;
		SYSTEM.PORTOUT(FGcol, SHORT(col));
		SYSTEM.PORTOUT(MFcont, SHORT(pixctrl1));
		SYSTEM.PORTOUT(curX, SHORT(x));
		SYSTEM.PORTOUT(curY, SHORT(y));
		SYSTEM.PORTOUT(cmdReg, 121BH);
		SYSTEM.PORTOUT(shortStroke, LONG(10H));
	END Dot;

	PROCEDURE CopyBlock*(sx, sy, w, h, dx, dy, mode: LONGINT);
	VAR xpos, ypos: INTEGER;
	BEGIN
		IF (w > 0) & (h > 0) THEN 
			xpos := 0; ypos := 0; 
			IF sy < dy THEN INC(sy, h-1); INC(dy, h-1); ypos := 128 END;
			IF sx < dx THEN INC(sx, w-1); INC(dx, w-1) ELSE xpos := 32 END;
			sy := Height - 1- sy; dy := Height -1- dy;
			DEC(w); DEC(h); 
			WaitFIFOempty;
			IF mode = invert THEN SYSTEM.PORTOUT(FGmix, LONG(65H)) ELSE SYSTEM.PORTOUT(FGmix, LONG(67H)) END;
			SYSTEM.PORTOUT(MFcont, SHORT(pixctrl1));
			SYSTEM.PORTOUT(curX, SHORT(sx));
			SYSTEM.PORTOUT(curY, SHORT(sy));
			SYSTEM.PORTOUT(diaStep, SHORT(dx));
			SYSTEM.PORTOUT(axStep, SHORT(dy));
			SYSTEM.PORTOUT(majAxis, SHORT(w));
			SYSTEM.PORTOUT(MFcont, SHORT(h));
			SYSTEM.PORTOUT(cmdReg, SHORT(copycmd) + xpos + ypos)
		END
	END CopyBlock;

	PROCEDURE SetMode*(x: LONGINT; s: SET);
	BEGIN
	END SetMode;
	
	PROCEDURE CopyPattern*(col: Color; pat: Pattern; x, y, mode: LONGINT);
	VAR width, height: SHORTINT; 
			bit16, h, ly: INTEGER; 
			bit8: CHAR; bit24, bit32: SET;
			stride, p: LONGINT;
	BEGIN
		SYSTEM.GET(pat, width);
		SYSTEM.GET(pat+1, height);
		INC(pat, 2);
		WaitFIFOempty; 
		IF mode = invert THEN SYSTEM.PORTOUT(FGmix, LONG(25H)); SYSTEM.PORTOUT(BGmix, LONG(3H)) 
		ELSIF mode = paint THEN SYSTEM.PORTOUT(FGmix, LONG(27H)); SYSTEM.PORTOUT(BGmix, LONG(3H))
		ELSE SYSTEM.PORTOUT(FGmix, LONG(27H)); SYSTEM.PORTOUT(BGmix, LONG(1H)) END;
		SYSTEM.PORTOUT(FGcol, SHORT(col));
		SYSTEM.PORTOUT(MFcont, SHORT(pixctrl2));
		y := Height-1-y;
		stride := ASH(width+7, -3);	(* eos1 *)
		width := SHORT(SHORT(ASH(stride, 3)));
		WHILE width > 32 DO
			INC(x, 31);
			h := height; ly := SHORT(y); p := pat;
			WHILE h > 0 DO
				SYSTEM.PORTOUT(majAxis, 31);
				SYSTEM.PORTOUT(curX, SHORT(x));
				SYSTEM.PORTOUT(curY, ly);
				SYSTEM.PORTOUT(cmdReg, 239BH);
				SYSTEM.GET(p, bit32);
				bit32 := SYSTEM.ROT(bit32, 16);
				SYSTEM.PORTOUT(pixTrans, SYSTEM.VAL(LONGINT, bit32));
				INC(p, stride); DEC(ly); DEC(h)
			END;
			DEC(width, 32); INC(pat, 4); INC(x)
		END;
		INC(x, LONG(LONG(width-1)));
		SYSTEM.PORTOUT(majAxis, LONG(width)-1);
		IF width <= 8 THEN
			WHILE height > 0 DO DEC(height);
				SYSTEM.GET(pat, bit8); INC(pat, stride);
				SYSTEM.PORTOUT(curX, SHORT(x));
				SYSTEM.PORTOUT(curY, SHORT(y));
				SYSTEM.PORTOUT(cmdReg, 219BH);
				SYSTEM.PORTOUT(pixTrans, ORD(bit8));
				DEC(y);
			END
		ELSIF width <= 16 THEN
			WHILE height > 0 DO DEC(height);
				SYSTEM.GET(pat, bit16); INC(pat, stride);
				SYSTEM.PORTOUT(curX, SHORT(x));
				SYSTEM.PORTOUT(curY, SHORT(y));
				SYSTEM.PORTOUT(cmdReg, 239BH);
				SYSTEM.PORTOUT(pixTrans, bit16);
				DEC(y);
			END
		ELSIF width <=24 THEN
			WHILE height > 0 DO DEC(height);
				SYSTEM.GET(pat, bit24); INC(pat, stride);
				bit24 := SYSTEM.LSH(bit24 * {0 .. 23}, 8);
				bit24 := SYSTEM.ROT(bit24, 16);
				SYSTEM.PORTOUT(curX, SHORT(x));
				SYSTEM.PORTOUT(curY, SHORT(y));
				SYSTEM.PORTOUT(cmdReg, 239BH);
				SYSTEM.PORTOUT(pixTrans, SYSTEM.VAL(LONGINT, bit24));
				DEC(y);
			END
		ELSE
			WHILE height > 0 DO DEC(height);
				SYSTEM.GET(pat, bit32); INC(pat, stride);
				bit32 := SYSTEM.ROT(bit32, 16);
				SYSTEM.PORTOUT(curX, SHORT(x));
				SYSTEM.PORTOUT(curY, SHORT(y));
				SYSTEM.PORTOUT(cmdReg, 239BH);
				SYSTEM.PORTOUT(pixTrans, SYSTEM.VAL(LONGINT, bit32));
				DEC(y);
			END
		END;
	END CopyPattern;

	PROCEDURE ReplConst*(col: Color; x, y, w, h, mode: LONGINT);
	BEGIN
		IF (w > 0) & (h > 0) THEN 
			DEC(h); DEC(w); y := Height-1-y; 
			WaitFIFOempty;
			IF mode = invert THEN SYSTEM.PORTOUT(FGmix, LONG(25H)) ELSE SYSTEM.PORTOUT(FGmix, LONG(27H)) END;
			SYSTEM.PORTOUT(FGcol, SHORT(col));
			SYSTEM.PORTOUT(MFcont, SHORT(pixctrl1));
			SYSTEM.PORTOUT(curX, SHORT(x));
			SYSTEM.PORTOUT(curY, SHORT(y));
			SYSTEM.PORTOUT(majAxis, SHORT(w));
			SYSTEM.PORTOUT(minAxis, SHORT(h));
			SYSTEM.PORTOUT(cmdReg, 4073H)
		END
	END ReplConst;

	PROCEDURE FillPattern*(col: Color; pat: Pattern; px, py, x, y, w, h, mode: LONGINT);
		VAR patwidth, patheight: SHORTINT; 
			diastep, axstep, errterm, bit16: INTEGER; 
			offset, W0, Y0, X0: INTEGER; 
			pat0, bit32: LONGINT;
			wth, hgt: INTEGER;
	BEGIN 
		IF (w > 0) & (h > 0) THEN 
			SYSTEM.GET(pat, patwidth);
			SYSTEM.GET(pat+1, patheight);
			INC(pat, 2);
			wth := SHORT(w+7) DIV 8 * 8;	(* nof complete bytes *)
			axstep := 0;
			diastep := -2*wth;
			errterm := -wth-1;
			INC(x, w-1); 
			Y0 := SHORT(y); X0 := SHORT(x); y := Height-1-y;
			WaitFIFOempty;
			IF mode = invert THEN SYSTEM.PORTOUT(FGmix, LONG(25H)); SYSTEM.PORTOUT(BGmix, LONG(3H)) 
			ELSIF mode = paint THEN SYSTEM.PORTOUT(FGmix, LONG(27H)); SYSTEM.PORTOUT(BGmix, LONG(3H))
			ELSE SYSTEM.PORTOUT(FGmix, LONG(27H)); SYSTEM.PORTOUT(BGmix, LONG(1H)) END;
			SYSTEM.PORTOUT(FGcol, SHORT(col));
			SYSTEM.PORTOUT(MFcont, SHORT(pixctrl2));
			SYSTEM.PORTOUT(majAxis, SHORT(w-1));
			SYSTEM.PORTOUT(diaStep, diastep);
			SYSTEM.PORTOUT(axStep, axstep);
			SYSTEM.PORTOUT(errTerm, errterm);
			pat0 := pat; W0 := SHORT(w);
			hgt := patheight - (Y0 + SHORT(py)) MOD patheight;
			offset := (Y0 + SHORT(py)) MOD patheight;
			IF patwidth = 16 THEN
				pat := pat + 2*offset;
				WHILE h > 0 DO 
					w := (w + 7) DIV 8 * 4;
					SYSTEM.GET(pat, bit16); INC(pat, 2);
					bit16 := SYSTEM.ROT(bit16, SHORT(px)-X0);
					SYSTEM.PORTOUT(curX, SHORT(x));
					SYSTEM.PORTOUT(curY, SHORT(y));
					SYSTEM.PORTOUT(cmdReg, 2313H);
					WHILE w > 0 DO
						SYSTEM.PORTOUT(pixTrans, bit16);
						DEC(w,2);
					END;
					DEC(y);
					DEC(h); DEC(hgt); w := W0;
					IF hgt <= 0 THEN hgt := patheight; pat := pat0 END;
				END
			ELSIF patwidth = 32 THEN
				pat := pat + 4*offset;
				WHILE h > 0 DO 
					w := (w + 7) DIV 8 * 2;
					SYSTEM.GET(pat, bit32); INC(pat, 4);
					bit32 := SYSTEM.ROT(bit32, SHORT(px)-X0+16);
					SYSTEM.PORTOUT(curX, SHORT(x));
					SYSTEM.PORTOUT(curY, SHORT(y));
					SYSTEM.PORTOUT(cmdReg, 2313H);
					WHILE w > 0 DO
						SYSTEM.PORTOUT(pixTrans, bit32);
						DEC(w,4)
					END;
					DEC(y);
					DEC(h); DEC(hgt); w := W0;
					IF hgt <= 0 THEN hgt := patheight; pat := pat0 END
				END
			END
		END
	END FillPattern;
	
	PROCEDURE ReplPattern*(col: Color; pat: Pattern; x, y, w, h, mode: LONGINT);
	BEGIN
		FillPattern(col, pat, 0, 0, x, y, w, h, mode)
	END ReplPattern;

	PROCEDURE NewPattern*(w, h: LONGINT; VAR image: ARRAY OF SET): Pattern;
	VAR len, src, dest, i: LONGINT;  p: PatternPtr;  pl: List;
	BEGIN
		len := (w+7) DIV 8;
		SYSTEM.NEW(p, 4+len*h);  p.w := CHR(w);  p.h := CHR(h);
		src := SYSTEM.ADR(image[0]);  dest := SYSTEM.ADR(p.pixmap[0]);
		i := 0;
		WHILE i < h DO SYSTEM.MOVE(src, dest, len);  INC(src, 4);  INC(dest, len);  INC(i) END;
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
		RETURN FALSE
	END TrueColor;

	PROCEDURE DisplayBlock*(adr, dx, dy, w, h, sx, sy, mode: LONGINT);
	VAR BitmapWth, locW, locH: LONGINT;
	CODE {SYSTEM.i386}
		MOVSX EAX, Width
		MOV locW[EBP], EAX	; locW := Width
		
		MOVSX EAX, Height
		DEC EAX
		MOV locH[EBP], EAX	; locH := Height-1
		
		MOV ESI, adr[EBP]    		; address of bitmap descriptor
		MOV EDI, 12[ESI]
		MOV ESI, 8[ESI] 
		MOV BitmapWth[EBP], ESI
		MOV ECX, dy[EBP]
		IMUL ESI,ECX
		MOV EBX, dx[EBP]
		ADD ESI, EBX	
		ADD ESI, EDI				; esi = source index register
		MOV EDI, locW[EBP]
		MOV EBX, locH[EBP]
		DEC EBX										;!!!!
		SUB EBX,sy[EBP]
		IMUL EDI,EBX 
		MOV EBX, sx[EBP]
		ADD EDI, EBX				; edi = destination index register without VGAaddr
		MOV EAX, locH[EBP]
		SUB EAX, sy[EBP]
		MOV sy[EBP], EAX
		
		MOV DX, 9AE8H
lab1:
		IN AX, DX
		AND AX, 100H
		JNZ lab1
		
		CMP mode[EBP], 1
		JL repllab
		JG invlab
		MOV AX, 4BH
		JMP contlab
repllab:
		MOV AX, 47H
		JMP contlab
invlab:
		MOV AX, 45H
contlab:
		MOV DX, 0BAE8H
		OUT DX, AX
		
		MOV DX, 0BEE8H
		MOV AX, 0A000H
		OUT DX, AX
		
		MOV DX, 086E8H
		MOV AX, WORD sx[EBP]
		OUT DX, AX
		MOV DX, 082E8H
		MOV AX, WORD sy[EBP]
		OUT DX, AX
		
		MOV DX, 096E8H
		MOV AX, WORD w[EBP]
		DEC AX
		OUT DX, AX
		
		MOV DX, 0BEE8H
		MOV AX, WORD h[EBP]
		DEC AX
		OUT DX, AX
		
		MOV DX, 09AE8H
		MOV AX, 05331H
		OUT DX, AX
		
		MOV DX, 0E2E8H
		
RowLoopR:
		MOV CX, WORD w[EBP]
		INC CX
		SHR CX, 1
		PUSH ESI
lab2:
		MOV AX, [ESI]
		OUT DX, AX
		INC ESI
		INC ESI
		DEC CX
		JNZ lab2
		POP ESI
		ADD ESI, BitmapWth[EBP]
		DEC h[EBP]
		JNZ RowLoopR
DispEnd:
	END DisplayBlock;
	
	PROCEDURE TransferFormat*(x: LONGINT): LONGINT;
	BEGIN
		RETURN unknown
	END TransferFormat;

	PROCEDURE TransferBlock*(VAR buf: ARRAY OF CHAR;  ofs, stride, x, y, w, h, mode: LONGINT);
	BEGIN
		HALT(99)
	END TransferBlock;
	
	PROCEDURE GetVal(str: ARRAY OF CHAR;  default: LONGINT): LONGINT;
	VAR i: SHORTINT;  v, sgn: LONGINT;  s: ARRAY 10 OF CHAR;
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

BEGIN
	depth := SHORT(GetVal("Color", 1));	(* assume 1 if not specified *)
	IF depth = 0 THEN depth := 1 ELSE depth := 8 END;
	Width := SHORT(GetVal("DWidth", 1024));	(* assume 1024 if not specified *)
	Height := SHORT(GetVal("DHeight", 768));	(* assume 768 if not specified *)
	dmem := GetVal("DMem", 1024)*1024;	(* assume 1Mb if not specified *)
	UBottom := Height - SHORT(dmem DIV Width) + 1;
	Left:= 0; ColLeft:= 0; Bottom:= 0;
	Pat := NIL;
	mask := -1; pixctrl1 := 0A000H; pixctrl2 := 0A080H; copycmd := 0C053H;
	EnableRegs;
	width := Width;
	height := Height;
	ResetClip;
	CreatePatterns;
	Unit := 10000
END Display.
