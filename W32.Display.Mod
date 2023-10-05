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

MODULE Display;	(* ET4000W32 ARD/pjm *)

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
	
		(* ACL Registers, queued *)
		PatAdr = 80H;
		SrcAdr = 84H;
		PatYOff = 88H;
		SrcYOff = 8AH;
		DestYOff = 8CH;
		BusSize = 8EH;
		XYDir = 8FH;
		PatWrap = 90H;
		SrcWrap = 92H;
		XPos = 94H;
		YPos = 96H;
		XCnt = 98H;
		YCnt = 9AH;
		RoutCtrl = 9CH;
		RelCtrl = 9DH;
		BgRop = 9EH;
		FgRop = 9FH;
		DestAdr = 0A0H;
		
		(* ACL Registers, non-queued *)
		SusTerm = 30H;
		OpState = 31H;
		SyncEn = 32H;
		IntMask = 34H;
		IntStat = 35H;
		AccStat = 36H;
		
		Base = 0BFF00H;
		MMU = 0B8000H;
		
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
		Height*: INTEGER; (* map hight*)
			
		arrow*, star*, cross*, downArrow*, hook*,
		grey0*, grey1*, grey2*, ticks*, solid*: Pattern;

		Broadcast*: MsgProc;

		dmem, lasty: LONGINT;
		
		pattern: List;

		palette: ARRAY 256 OF LONGINT;
		
		clipx, clipy, clipright, cliptop, height, width: LONGINT;	(* clipping variables *)
		depth: INTEGER;

	PROCEDURE max (i, j: LONGINT): LONGINT; BEGIN IF i >= j THEN RETURN i ELSE RETURN j END END max;
	PROCEDURE min (i, j: LONGINT): LONGINT; BEGIN  IF i >= j THEN RETURN j ELSE RETURN i END END min;
	
	PROCEDURE Wait;
	VAR i: SHORTINT;
	BEGIN
		REPEAT SYSTEM.GET(Base+AccStat, i) UNTIL ~ODD(i) & ~ODD(i DIV 2);
	END Wait;
	
	PROCEDURE Map*(x: LONGINT): LONGINT;
	BEGIN RETURN 0A0000H
	END Map;
	
	PROCEDURE AdjustClip*(x, y, w, h: LONGINT);
	VAR right, top: LONGINT;
	BEGIN 
		right := x + w; top := y + h; clipx := max(clipx, x); clipy := max(clipy, y); 
		clipright := min(right, clipright); cliptop := min(top, cliptop)
	END AdjustClip;

	PROCEDURE GetDim*(pat: Pattern; VAR w, h: INTEGER);
	VAR s: CHAR;
	BEGIN SYSTEM.GET(pat, s); w := ORD(s); SYSTEM.GET(pat+1, s); h := ORD(s)
	END GetDim;

	PROCEDURE ResetClip*;
	BEGIN 
		clipx := 0; clipy := UBottom; 
		clipright := width;
		cliptop := height
	END ResetClip;
	
	PROCEDURE SetClip*(x, y, w, h: LONGINT);
	BEGIN  
		clipright := x+w;
		cliptop := y+h;
		clipy := y; clipx := x
	END SetClip;
	
	PROCEDURE GetClip*(VAR x, y, w, h: INTEGER);
	BEGIN 
		x := SHORT(clipx); y := SHORT(clipy); w := SHORT(clipright - clipx); h := SHORT(cliptop - clipy)
	END GetClip;

	PROCEDURE SetColor*(col: Color; red, green, blue: LONGINT);	(* 0 <= col, red, green, blue < 256 *)
	VAR ch: CHAR;
	BEGIN
		palette[col] := ASH(ASH(red, 8) + green, 8) + blue;
		IF (col = 0) OR (col = 15) THEN	(* either 0 or 15 must be black.  set the border to black. *)
				(* note: use the palette for the border colour too *)
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
	VAR dest: LONGINT;
	BEGIN
		IF (y >= clipy) & (y < cliptop) & (x >= clipx) & (x < clipright) THEN
			dest := (LONG(Height)-1 - y) * Width + x;
			IF mode = invert THEN SYSTEM.PUT(Base+FgRop, 066X) ELSE SYSTEM.PUT(Base+FgRop, 0CCX) END;
			Wait;
			SYSTEM.PUT(Base+XCnt, LONG(0));
			SYSTEM.PUT(Base+YCnt, LONG(0));
			SYSTEM.PUT(Base+RoutCtrl, 1X);
			SYSTEM.PUT(Base, dest);
			SYSTEM.PUT(MMU, col)
		END
	END Dot;

	PROCEDURE CopyBlock*(sx, sy, w, h, dx, dy, mode: LONGINT);
	VAR src, dst, top, right, dX, dY: LONGINT;
	BEGIN
		right := dx + w; top := dy + h; dX := dx; dY := dy;
		IF dx < clipx THEN w := w - (clipx - dx); dx := clipx END; 
		IF dy < clipy THEN h := h - (clipy - dy); dy := clipy END;
		IF clipright < right THEN  w :=  clipright - dx END; 
		IF cliptop  < top THEN h := cliptop - dy END;
		IF (w > 0) & (h > 0) THEN
			sx := sx - (dX - dx);
			sy := sy - (dY - dy);
			src := (LONG(Height) - sy - h) * Width + sx;
			dst := (LONG(Height) - dy - h) * Width + dx;
			IF src # dst THEN
				Wait;
				SYSTEM.PUT(Base+XCnt, LONG(0));
				SYSTEM.PUT(Base+YCnt, LONG(0));
				SYSTEM.PUT(Base+RoutCtrl, 0X);
				SYSTEM.PUT(Base+XYDir, 0X);
				SYSTEM.PUT(Base+FgRop, 0AAX);
				SYSTEM.PUT(Base+SrcAdr, dst);
				SYSTEM.PUT(Base+DestAdr, dst);
				SYSTEM.PUT(Base+OpState, 9X);
				Wait;
				SYSTEM.PUT(Base+XCnt, SHORT(w-1));
				SYSTEM.PUT(Base+YCnt, SHORT(h-1));
				IF dst > src THEN
					src := src + w-1 + Width * (h-1); 
					dst := dst + w-1 + Width * (h-1);
					SYSTEM.PUT(Base+XYDir, 3X)
				ELSE
					SYSTEM.PUT(Base+XYDir, 0X)
				END;
				SYSTEM.PUT(Base+FgRop, 0CCX);
				SYSTEM.PUT(Base+RoutCtrl, 0X);
				SYSTEM.PUT(Base+DestAdr, dst);
				SYSTEM.PUT(Base+SrcAdr, src);
				SYSTEM.PUT(Base+OpState, 9X);
				SYSTEM.PUT(Base+XYDir, 0X)
			END
		END
	END CopyBlock;

	PROCEDURE SetMode*(x: LONGINT; s: SET);
	BEGIN
	END SetMode;
	
	PROCEDURE CopyPatternAsm(cpX, cpY, cpW, cpH, pat: LONGINT;  VAR buf: ARRAY OF INTEGER);
	VAR cpw, cpsw, cph: LONGINT;
	CODE {SYSTEM.i386}
		MOV EBX,cpW[EBP]
		ADD EBX,7
		SHR EBX,3
		MOV cpw[EBP],EBX	; cpw := cpW DIV 8
		MOV ESI,pat[EBP]
		XOR EAX,EAX
		MOV AL,[ESI]
		ADD EAX,7
		SHR EAX,3
		MOV cpsw[EBP],EAX	; cpsw := p.w DIV 8
		MOV EDI,buf[EBP]
		MOV EAX,cpW[EBP]
		MOV [EDI],AL	; new p.w
		INC EDI
		MOV EAX,cpH[EBP]	; new p.h
		MOV [EDI],AL
		INC EDI
		MOV EBX,cpsw[EBP]
		MOV EAX,cpY[EBP]
		IMUL EAX,EBX
		ADD ESI,EAX
		MOV ECX,cpX[EBP]
		SHR ECX,3
		ADD ESI,ECX
		ADD ESI,2	; ESI := Sourcepos for Copyloop
		MOV cph[EBP],0	; init loop variables
		MOV EDX,cph[EBP]
		MOV  ECX,cpX[EBP]
		AND ECX,7	; cpX MOD 8
loopcp:
		CMP   cpH[EBP],EDX
		JLE l7cp	; height reached ?
		MOV   EAX,[ESI]
		SHR EAX,CL	; in proper position
		PUSH ECX
		MOV EBX,-2
		MOV ECX,cpW[EBP]
		SHL EBX,CL
		SHR EBX, 1
		NOT EBX
		AND EAX,EBX
		POP ECX
		MOV [EDI],EAX	; copy for a new pattern
		MOV EAX,cpsw[EBP]
		ADD ESI,EAX	; one line in source up
		MOV EAX,cpw[EBP]
		ADD EDI,EAX	; one line at destination up
		INC EDX
		JMP loopcp
l7cp:
	END CopyPatternAsm;
	
	PROCEDURE CopyPattern*(col: Color; pat: Pattern; x, y, mode: LONGINT);
	VAR dest, i: LONGINT; 
			w, h: CHAR; 
			lx, ly, cpX, cpY, cpW, cpH, nofbytes: LONGINT;
			buf: ARRAY 256 OF INTEGER;
			onebyte: CHAR;
			doublefill: ARRAY 4 OF CHAR;
	BEGIN
		SYSTEM.GET(pat, w); SYSTEM.GET(pat+1, h);
		cpW := ORD(w) + x; cpH := ORD(h) + y; 
		lx := x; ly := y;
		IF x < clipx THEN x := clipx END;
		IF y < clipy THEN y := clipy END;
		IF cpW > clipright THEN cpW := clipright END;
		IF cpH > cliptop THEN cpH := cliptop END;
		cpW := cpW - x; cpH := cpH - y; 
		cpX := x - lx; cpY := y - ly;
		IF (cpW <= 0) OR (cpH <= 0) OR (cpX < 0) OR (cpY < 0) THEN RETURN END;
		IF (cpW # ORD(w)) OR (cpH # ORD(h)) THEN
			CopyPatternAsm(cpX, cpY, cpW, cpH, pat, buf);
			pat := SYSTEM.ADR(buf[0])
		END;
		dest := (LONG(Height)-1-y) * Width + x;
		doublefill[0] := CHR(col); doublefill[1] := CHR(col); doublefill[2] := CHR(col); doublefill[3] := CHR(col);
		SYSTEM.GET(pat, w); 
		SYSTEM.GET(pat+1, h);
		INC(pat, 2);
		nofbytes := (ORD(w)+7) DIV 8;
		
		Wait;
		SYSTEM.PUT(Base+FgRop, 0CCX);
		SYSTEM.PUT(Base+XCnt, LONG(3));
		SYSTEM.PUT(Base+YCnt, LONG(0));
		SYSTEM.PUT(Base, lasty);
		SYSTEM.PUT(Base+RoutCtrl, 1X);
		SYSTEM.PUT(MMU, SYSTEM.VAL(SET, doublefill));
				
		Wait;
		IF mode = invert THEN SYSTEM.PUT(Base+FgRop, 05AX); SYSTEM.PUT(Base+BgRop, 0AAX)
		ELSE SYSTEM.PUT(Base+FgRop, 0F0X); SYSTEM.PUT(Base+BgRop, 0AAX) END;
		SYSTEM.PUT(Base+PatAdr, lasty);
		SYSTEM.PUT(Base+PatWrap, 2X);
		SYSTEM.PUT(Base+XYDir, 2X);
		SYSTEM.PUT(Base+YCnt, SHORT(ORD(h)-1));
		SYSTEM.PUT(Base+XCnt, SHORT(ORD(w)-1));
		SYSTEM.PUT(Base+RoutCtrl, 2X);
		SYSTEM.PUT(Base, dest);
		SYSTEM.PUT(Base+BusSize, 0X);
		FOR i := 0 TO nofbytes*ORD(h)-1 DO SYSTEM.GET(pat+i, onebyte); SYSTEM.PUT(MMU, onebyte) END;
		SYSTEM.PUT(Base+BusSize, 2X);
	END CopyPattern;

	PROCEDURE ReplConst*(col: Color; x, y, w, h, mode: LONGINT);
	VAR dest, right, top: LONGINT; 
			doublefill: ARRAY 4 OF CHAR;
	BEGIN
		top := y + h; right := x + w; 
		IF x < clipx THEN x := clipx END;
		IF y < clipy THEN y := clipy END;
		IF  clipright < right THEN right := clipright END;
		IF cliptop < top THEN top := cliptop END;
		w := right - x; h := top - y;
		IF (w <= 0) OR (h <= 0) OR (x < 0) OR (y < 0) THEN RETURN END;
		dest := (Height - y - h) * Width + x;
		doublefill[0] := CHR(col); doublefill[1] := CHR(col); doublefill[2] := CHR(col); doublefill[3] := CHR(col);
		Wait;
		SYSTEM.PUT(Base+FgRop, 0CCX);
		SYSTEM.PUT(Base+XCnt, LONG(3));
		SYSTEM.PUT(Base+YCnt, LONG(0));
		SYSTEM.PUT(Base, lasty);
		SYSTEM.PUT(Base+RoutCtrl, 1X);
		SYSTEM.PUT(MMU, SYSTEM.VAL(SET, doublefill));
				
		Wait;
		IF mode = invert THEN SYSTEM.PUT(Base+FgRop, 066X) ELSE SYSTEM.PUT(Base+FgRop, 0CCX) END;
		SYSTEM.PUT(Base+SrcWrap, 2X);
		SYSTEM.PUT(Base+SrcAdr, lasty);
		SYSTEM.PUT(Base+DestAdr, dest);
		SYSTEM.PUT(Base+XYDir, 0X);
		SYSTEM.PUT(Base+XCnt, SHORT(w-1));
		SYSTEM.PUT(Base+YCnt, SHORT(h-1));
		SYSTEM.PUT(Base+RoutCtrl, 0X);
		SYSTEM.PUT(Base+OpState, 9X);
		SYSTEM.PUT(Base+SrcWrap, 0FFX)
	END ReplConst;

	PROCEDURE FillPattern*(col: Color; pat: Pattern; px, py, x, y, w, h, mode: LONGINT);
	VAR dest, vertoff, fourbytes, mod, pw, ph, origh, off, right, top: LONGINT; ch: CHAR;
			doublefill: ARRAY 4 OF CHAR;
	BEGIN 
		doublefill[0] := CHR(col); doublefill[1] := CHR(col); doublefill[2] := CHR(col); doublefill[3] := CHR(col);
		SYSTEM.GET(pat, ch); pw := ORD(ch);
		SYSTEM.GET(pat+1, ch); ph := ORD(ch); origh := ph; INC(pat, 2);
		IF (pw # 16) & (pw # 32) THEN RETURN END;
		top := y + h; right := x + w; 
		IF x < clipx THEN x := clipx END;
		IF y < clipy THEN y := clipy END;
		IF clipright < right THEN right := clipright END; 
		IF cliptop < top THEN top := cliptop END;
		w := right - x; h := top - y;
		IF (w <= 0) OR (h <= 0) OR (x < 0) OR (y < 0) THEN RETURN END;
		dest := (LONG(Height)-1 - y) * Width + x;
		off := (x - px) MOD 32;
		vertoff := ((y - py) MOD h) * (w DIV 8);
		Wait;	(* Foreground color *)
		SYSTEM.PUT(Base+FgRop, 0CCX);
		SYSTEM.PUT(Base+XCnt, LONG(31));
		SYSTEM.PUT(Base+YCnt, LONG(0));
		SYSTEM.PUT(Base, lasty);
		SYSTEM.PUT(Base+RoutCtrl, 1X);
		SYSTEM.PUT(MMU, SYSTEM.VAL(SET, SYSTEM.VAL(SET, doublefill))); 
		SYSTEM.PUT(MMU, SYSTEM.VAL(SET, SYSTEM.VAL(SET, doublefill))); 
		SYSTEM.PUT(MMU, SYSTEM.VAL(SET, SYSTEM.VAL(SET, doublefill))); 
		SYSTEM.PUT(MMU, SYSTEM.VAL(SET, SYSTEM.VAL(SET, doublefill)));
		SYSTEM.PUT(MMU, SYSTEM.VAL(SET, SYSTEM.VAL(SET, doublefill))); 
		SYSTEM.PUT(MMU, SYSTEM.VAL(SET, SYSTEM.VAL(SET, doublefill))); 
		SYSTEM.PUT(MMU, SYSTEM.VAL(SET, SYSTEM.VAL(SET, doublefill))); 
		SYSTEM.PUT(MMU, SYSTEM.VAL(SET, SYSTEM.VAL(SET, doublefill)));
		mod := (w DIV 8)*origh;
		Wait;
		SYSTEM.PUT(Base+SrcWrap, 5X);
		SYSTEM.PUT(Base+PatWrap, 5X);
		SYSTEM.PUT(Base+YCnt, LONG(0));
		SYSTEM.PUT(Base+XYDir, 2X);
		SYSTEM.PUT(Base+BgRop, 0CCX);
		WHILE h > 0 DO
			SYSTEM.GET(pat+vertoff, fourbytes); 
			IF pw = 16 THEN
				vertoff := (vertoff + 2) MOD mod;
				fourbytes := fourbytes*10000H + fourbytes MOD 10000H;
			ELSE
				vertoff := (vertoff + 4) MOD mod
			END;
			fourbytes := SYSTEM.ROT(fourbytes, -off);
			Wait;
			SYSTEM.PUT(Base+FgRop, 0F0X);
			SYSTEM.PUT(Base+SrcAdr, lasty+32);
			SYSTEM.PUT(Base+PatAdr, lasty);
			SYSTEM.PUT(Base+XCnt, LONG(31));
			SYSTEM.PUT(Base+RoutCtrl, 2X);
			SYSTEM.PUT(Base, lasty + 96);
			SYSTEM.PUT(MMU, fourbytes);
			IF mode = paint THEN
				Wait;	(* clear color *)
				SYSTEM.PUT(Base+FgRop, 0FFX);
				SYSTEM.PUT(Base, lasty+64);
				SYSTEM.PUT(MMU, fourbytes)
			END;
			Wait;
			IF mode = invert THEN SYSTEM.PUT(Base+FgRop, 066X)
			ELSIF mode = replace THEN SYSTEM.PUT(Base+FgRop, 0CCX)
			ELSE 
				SYSTEM.PUT(Base+PatAdr, lasty+64);
				SYSTEM.PUT(Base+FgRop, 0CEX)
			 END;
			SYSTEM.PUT(Base+SrcAdr, lasty+96);
			SYSTEM.PUT(Base+XCnt, SHORT(w-1));
			SYSTEM.PUT(Base+RoutCtrl, 0X);
			SYSTEM.PUT(Base+DestAdr, dest);
			SYSTEM.PUT(Base+OpState, 9X);
			DEC(h); DEC(dest, LONG(Width))
		END;
		SYSTEM.PUT(Base+SrcWrap, 0FFX)
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
		NEW(pl);  pl.pat := p;  pl.next := pattern;  pattern := pl;	(* put in list to avoid GC *)
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
	
	PROCEDURE Depth*(x: LONGINT): INTEGER;
	BEGIN
		RETURN depth
	END Depth;
	
	PROCEDURE TrueColor*(x: LONGINT): BOOLEAN;
	BEGIN
		RETURN FALSE
	END TrueColor;

	PROCEDURE DisplayBlock*(adr, dx, dy, w, h, sx, sy, mode: LONGINT);
	VAR src, dst, width, i, base: LONGINT; data: CHAR; mmu: LONGINT;
	BEGIN
		dst := Width*(LONG(Height)-1-sy) + sx;
		SYSTEM.GET(adr+8, width);
		SYSTEM.GET(adr+12, base);
		src := base + width * dy + dx;
		Wait;
		SYSTEM.PUT(Base+XCnt, SHORT(w-1));
		SYSTEM.PUT(Base+YCnt, LONG(0));
		SYSTEM.PUT(Base+RoutCtrl, 1X);
		SYSTEM.PUT(Base+XYDir, 0X);
		SYSTEM.PUT(Base+BusSize, 0X);
		IF mode = invert THEN SYSTEM.PUT(Base+FgRop, 066X)
		ELSE SYSTEM.PUT(Base+FgRop, 0CCX)
		END;
		mmu := MMU;
		WHILE h > 0 DO
			Wait;
			SYSTEM.PUT(Base, dst);
			SYSTEM.MOVE(src,mmu,w);
			DEC(dst, LONG(Width)); INC(src, width);
			DEC(h)
		END;
		SYSTEM.PUT(Base+BusSize, 2X)
	END DisplayBlock;

	PROCEDURE TransferFormat*(x: LONGINT): LONGINT;
	BEGIN
		RETURN unknown
	END TransferFormat;

	PROCEDURE TransferBlock*(VAR buf: ARRAY OF CHAR;  ofs, stride, x, y, w, h, mode: LONGINT);
	BEGIN
		HALT(99)
	END TransferBlock;
	
	PROCEDURE Init;
	BEGIN
		Wait; 		
		SYSTEM.PUT(Base+13H, 71X);
		SYSTEM.PUT(Base+SyncEn, 1X);
		SYSTEM.PUT(Base+IntMask, 0X);
		SYSTEM.PUT(Base+BusSize, 2X);
		
		SYSTEM.PUT(Base+SrcWrap, 0FFX);
		SYSTEM.PUT(Base+RelCtrl, LONG(0));
		SYSTEM.PUT(Base+XPos, LONG(0));
		SYSTEM.PUT(Base+YPos,  LONG(0));
		SYSTEM.PUT(Base+SrcYOff, Width-1);
		SYSTEM.PUT(Base+DestYOff, Width-1);
		SYSTEM.PUT(Base+PatYOff, Width-1);
		
		(* Background color *)
		SYSTEM.PUT(Base+FgRop, 0CCX);
		SYSTEM.PUT(Base+XCnt, LONG(31));
		SYSTEM.PUT(Base+YCnt, LONG(0));
		SYSTEM.PUT(Base, lasty+32);
		SYSTEM.PUT(Base+RoutCtrl, 1X);
		SYSTEM.PUT(MMU, LONG(LONG(BG))); SYSTEM.PUT(MMU, LONG(LONG(BG)));
		SYSTEM.PUT(MMU, LONG(LONG(BG))); SYSTEM.PUT(MMU, LONG(LONG(BG)));
		SYSTEM.PUT(MMU, LONG(LONG(BG))); SYSTEM.PUT(MMU, LONG(LONG(BG)));
		SYSTEM.PUT(MMU, LONG(LONG(BG))); SYSTEM.PUT(MMU, LONG(LONG(BG)));
	END Init;
	
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
	lasty := LONG(Height-UBottom)*Width;
	pattern := NIL;
	Init; 

	width := Width;
	height := Height;
	clipx := 0; clipy := UBottom; clipright := width; cliptop := height;
	CreatePatterns;
	Unit := 10000
END Display.
