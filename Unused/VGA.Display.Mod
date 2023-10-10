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

MODULE Display;	(* Ott Hans-Werner, ard, pjm *)

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

		pattern: List;

		clipx, clipy, clipright, cliptop, height, width: INTEGER;	(* clipping variables *)
		width3: LONGINT;
		mask, imask: ARRAY 9 OF CHAR;
		rev: ARRAY 256 OF CHAR;
		depth: INTEGER;
		palette: ARRAY 256 OF LONGINT;

	PROCEDURE max (i, j: INTEGER): INTEGER; BEGIN IF i >= j THEN RETURN i ELSE RETURN j END END max;
	PROCEDURE min (i, j: LONGINT): INTEGER; BEGIN  IF i >= j THEN RETURN SHORT(j) ELSE RETURN SHORT(i) END END min;
		
	PROCEDURE Map*(x: LONGINT): LONGINT;
	BEGIN
		RETURN 0A0000H 
	END Map;
	
	PROCEDURE AdjustClip*(x, y, w, h: LONGINT);
	VAR right, top: INTEGER;
	BEGIN 
		right := SHORT(x + w); top := SHORT(y + h); 
		clipx := max(clipx, SHORT(x)); clipy := max(clipy, SHORT(y)); 
		clipright := min(right, clipright); cliptop := min(top, cliptop)
	END AdjustClip;

	PROCEDURE GetDim*(pat: Pattern; VAR w, h: INTEGER);
	VAR ch: CHAR;
	BEGIN
		SYSTEM.GET(pat, ch); w := ORD(ch); SYSTEM.GET(pat+1, ch); h := ORD(ch) 
	END GetDim;

	PROCEDURE ResetClip*;
	BEGIN
		clipx := 0; clipy := UBottom; clipright := width; cliptop := height
	END ResetClip;
	
	PROCEDURE SetClip*(x, y, w, h: LONGINT);
	BEGIN
		clipright := SHORT(x+w); cliptop := SHORT(y+h); clipy := SHORT(y); clipx := SHORT(x)
	END SetClip;
	
	PROCEDURE GetClip*(VAR x, y, w, h: INTEGER);
	BEGIN
		x := clipx; y := clipy; w := clipright - clipx; h := cliptop - clipy
	END GetClip;
	
	PROCEDURE SetColor*(col: Color; red, green, blue: LONGINT);	(* 0 <= col, red, green, blue < 256 *)
	VAR ch: CHAR;
	BEGIN
		palette[col] := ASH(ASH(red, 8) + green, 8) + blue;
		col := col MOD 16;
			(* see table 8.11 of Ferraro, 3rd edition *)
		IF col = 6 THEN col := 14H
		ELSIF col > 7 THEN INC(col, 30H)
		END;
		red := (red + 4) DIV 4 -1;
		green := (green + 4) DIV 4 -1;
		blue := (blue + 4) DIV 4 -1;
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
	CODE {SYSTEM.i386}
		MOV AX, clipy
		CMP WORD y[EBP], AX
		JL ret
		MOV AX, cliptop
		CMP WORD y[EBP], AX
		JGE ret
		MOV AX, clipx
		CMP WORD x[EBP], AX
		JL ret
		MOV AX, clipright
		CMP WORD x[EBP], AX
		JGE ret
		
		MOV AX, 1803H	; AL = Data/Rotate; AH = Modus; DX = Graphic-Controller
		MOV DX, 03CEH
		CMP mode[EBP],invert
		JE smode
		MOV AX,3
		CMP mode[EBP],replace
		JE smode
		MOV AX, 1003H	; paint
smode:
		OUT DX, AX
		
		MOV DX, 03C4H	; AX = Default map mask; DX = Sequencer
		MOV AX, 0F02H
		OUT DX, AX

		MOV DX, 03CEH	; AL = Gaphics mode; AH = Read-Mode = 0/Write-Mode = 2 (bits 0,1)
		MOV AX, 0205H
		OUT DX, AX

		MOV AX, Height
		SUB AX, WORD y[EBP]
		DEC AX
		MOVSX EAX,AX
		IMUL EAX,width3
		MOV ESI, x[EBP]
		SHR ESI, 3
		ADD ESI, EAX
		AND ESI, 0FFFFH
		ADD ESI, 0A0000H
		
		MOV DX, 03CEH
		MOV CL, BYTE x[EBP]
		AND CL, 7
		MOV AH, 128
		SHR AH, CL
		MOV AL, 8
		OUT DX, AX
		MOV AL, [ESI]	; latch bytes
		MOV AL, BYTE col[EBP]
		MOV [ESI], AL
ret:
	END Dot;

	PROCEDURE CopyBlock*(sx, sy, w, h, dx, dy, mode: LONGINT);
	VAR top, right: INTEGER;
			x1, x2, x3, x4, x5, x6, x7, x8: LONGINT;
			help, help2, diff, start, end, msk, imsk, lh: LONGINT;
			leftmask, rightmask: CHAR;  plane, count: SHORTINT;
	CODE {SYSTEM.i386}
		MOV EDX, dx[EBP]
		
		MOV AX,DX
		ADD AX, WORD w[EBP]
		MOV right[EBP], AX	; right := DX + W
		
		MOV AX, WORD dy[EBP]
		ADD AX, WORD h[EBP]
		MOV top[EBP], AX	; top := DY + H
		
			; IF DX < clipx THEN W := W - (clipx - DX); DX := clipx END
		CMP DX, clipx
		JGE ok0
		MOV AX, clipx
		SUB AX, DX
		SUB WORD w[EBP], AX
		MOV DX, clipx
ok0:
			; IF DY < clipy THEN H := H - (clipy - DY); DY := clipy END
		MOV AX, WORD dy[EBP]
		CMP AX, clipy
		JGE ok1
		MOV AX, clipy
		SUB AX, WORD dy[EBP]
		SUB WORD h[EBP], AX
		MOV AX, clipy
		MOV WORD dy[EBP], AX
ok1:
			; IF  clipright < right THEN  W :=  clipright - DX END
		MOV AX, clipright
		CMP AX, right[EBP]
		JGE ok2
		MOV AX, clipright
		SUB AX, DX
		MOV WORD w[EBP], AX
ok2:
			; IF cliptop  < top THEN H := cliptop - DY END
		MOV AX, cliptop
		CMP AX, top[EBP]
		JGE ok3
		MOV AX, cliptop
		SUB AX, WORD dy[EBP]
		MOV WORD h[EBP], AX
ok3:

		;	IF (W <= 0) OR (H <= 0) THEN RETURN END;
		CMP WORD w[EBP], 0
		JLE ret
		CMP WORD h[EBP], 0
		JLE ret
		
		LEA EAX, mask
		MOV msk[EBP], EAX	; msk := SYSTEM.ADR(mask[0])
		LEA EAX, imask
		MOV imsk[EBP], EAX	; imsk := SYSTEM.ADR(imask[0])
		
		MOV AX, height
		DEC AX
		MOVSX EAX,AX
		MOV lh[EBP], EAX	; h := height-1

		MOV dx[EBP], EDX	; DX := DX
		
		MOV	EAX, lh[EBP]
		MOV	EBX, EAX
		SUB	EAX, sy[EBP]	; EAX := height - sy
		MOV	sy[EBP], EAX
		SUB	EBX, dy[EBP]	; EBX := height - dy
		MOV	dy[EBP], EBX
		MOV	EAX, sx[EBP]	; EAX := sx
		MOV	ECX, EAX
		MOV	EBX, EAX
		MOV	EDX, EAX
		SHR	EAX, 3	; EAX := sx DIV 8
		AND	ECX, 7	; ECX := sx MOD 8
		ADD	EBX, w[EBP]
		ADD	EDX, w[EBP]
		SHR	EBX, 3	; EBX := (sx+w) DIV 8
		AND	EDX, 7	; EDX := (sx+w) MOD 8
		MOV	x1[EBP], EAX	; x1 := sx DIV 8
		MOV	x2[EBP], EBX	; x2 := (sx+w) DIV 8
		MOV	x3[EBP], ECX	; x3 := sx MOD 8
		INC	EDX
		MOV	x4[EBP], EDX	; x4 := (sx+w) MOD 8 (+1)
		MOV	EAX, dx[EBP]	; EAX := dx
		MOV	ECX, EAX
		MOV	EBX, EAX
		MOV	EDX, EAX
		SHR	EAX, 3	; EAX := dx DIV 8
		AND	ECX, 7	; ECX := dx MOD 8
		ADD	EBX, w[EBP]	; EBX := dx +w
		ADD	EDX, w[EBP]
		SHR	EBX, 3	; EBX := (dx+w) DIV 8
		AND	EDX, 7	; EDX := (dx+w) MOD 8
		MOV	x5[EBP], EAX	; x5 := dx DIV 8
		MOV	x6[EBP], EBX	; x6 := (dx+w) DIV 8
		MOV	x7[EBP], ECX	; x7 := dx MOD 8
		INC	EDX
		MOV	x8[EBP], EDX	; x8 := (dx+w) MOD 8
		MOV	ESI, sy[EBP]
		IMUL	ESI, width3	; w3[EBP]
		ADD	ESI, x1[EBP]	; ESI := startbyte source bottomleft
		AND ESI, 0FFFFH
		ADD ESI, 0A0000H	; offset of screen
		MOV	EDI, dy[EBP]
		IMUL	EDI, width3	; w3[EBP]
		ADD	EDI, EAX
		AND EDI, 0FFFFH
		ADD EDI, 0A0000H	; offset of screen
		MOV	start[EBP], ESI	; starbyte source bottom left
		MOV	end[EBP], EDI	; startbyte dest bottom left
		MOV	DX, 03CEH
		MOV	AX, 0005
		OUT	DX, AX	; read/writemode = 0
		MOV	AX, 0001
		OUT	DX, AX	; enable/reset = 0000b
		MOV	AH, 0
		MOV	AL, 3
		OUT	DX, AX	; replacemode
		MOV	EBX, x8[EBP]
		DEC	EBX
		MOV	EDX, msk[EBP]
		MOV	AH, [EDX][EBX]
;			MOV	AH, mask[EBX]
		MOV	rightmask[EBP], AH
		MOV	EBX, x7[EBP]
		MOV	EDX, imsk[EBP]
		MOV	AH, [EDX][EBX]
;			MOV	AH, imask[EBX]
		MOV	leftmask[EBP], AH
		MOV	EBX, x6[EBP]
		SUB	EBX, x5[EBP]	; EBX := difference in bytes dx/dx+w
		DEC	EBX
		MOV	diff[EBP], EBX
		JGE	inmorebytes
		MOV	DH, rightmask[EBP]	; EBX = 0 /only one byte
		AND	DH, leftmask[EBP]
		MOV	leftmask[EBP], DH
		MOV	rightmask[EBP], DH
inmorebytes:
		MOV	EDX, h[EBP]	; EDX := h
		MOV	EAX, sx[EBP]	; EAX := sx
		MOV	EBX, sy[EBP]	; EBX := sy
		CMP	EAX, dx[EBP]	; sx < dx ?
		JGE	CB1	; no -> goto CB1
		MOV	ECX, x8[EBP]	; sx < dx !
		SUB	ECX, x4[EBP]	; ECX := differnce between s/dest x
		ADD	ECX, 32
		AND	CL, 1FH	; CL := rotate shift count
		CMP	BX, WORD dy[EBP]	; sy < dy ?	was EBX
		JL	CB10	; yes goto CB10
		JMP	CB13	; else goto CB13
			
CB1:
		SUB	ECX, x3[EBP]	; sx >= dx
		ADD	ECX, 32
		AND	CL, 1FH	; CL:= rotate shift count
		CMP	BX, WORD dy[EBP]	; sy >= dy?
		JGE	CB12	; yes goto CB12
CB11:
		MOV	help[EBP], EDX	; (sx >= dx) & (sy < dy) / save linecounter
		MOV	EBX, diff[EBP]
		CMP	EBX, 1
		JLE	byte11	; in 1 Byte => normal CopyBlock
		CMP	CL, 0	; rotateoffset = 0 ?
		JE	qCB11	; QuickCopy
byte11:
		MOV	count[EBP], 3	; there are 4 Bitplanes
		MOV	plane[EBP], 8	; begin with plane 4
CB11h:
		MOV	DX, 03CEH
		MOV	AH, count[EBP]
		MOV	AL, 4
		OUT	DX, AX	; select plane to read
		MOV	AH, leftmask[EBP]	; bitmask select
		MOV	AL, 8
		OUT	DX, AX	; set mask at destination
		MOV	DX, 03C4H
		MOV	AH, plane[EBP]	; set bitplanemask
		MOV	AL, 2
		OUT	DX, AX	; set sequencer
		XOR	EAX, EAX
		MOV	AH, [ESI]
		MOV	AL, 1[ESI]
		ADD	ESI, 2
		ROR	EAX, CL
		CMP	EBX, 0	; in one byte ?
		JL	cbl31
cbl6i:
		MOV	DL, [EDI]	; latch bytes
		MOV	[EDI], AH
		INC	EDI
		ROL	EAX, 8
		CMP	EBX, 0	; in 2 bytes ?
		JE	cbl3 ;**
		MOV	help2[EBP], EAX
		MOV	DX, 03CEH
		MOV	AX, 0FF08H	; all maskbits
		OUT	DX, AX
		MOV	EAX, help2[EBP]
cbl6:
		ROL	EAX, CL
		MOV	AL, [ESI]
		INC	ESI
		ROR	EAX, CL
		MOV	[EDI], AH
		INC	EDI
		ROL	EAX, 8
		DEC	BX
		JG	cbl6
cbl3:
		MOV	EBX, x6[EBP]
		SUB	EBX, x5[EBP]
		MOV	help2[EBP], EBX
		MOV	EBX, x2[EBP]
		SUB	EBX, x1[EBP]
		CMP	EBX, help2[EBP]
		JE	cbl31
		ROL	EAX, CL
		MOV	AL, [ESI]
		ROR	EAX, CL
cbl31:
		PUSH	EAX
		MOV	DX, 03CEH
		MOV	AH, rightmask[EBP]
		MOV	AL, 8
		OUT	DX, AX	; set right dest bitmask
		POP	EAX
		MOV	DL, [EDI]
		MOV	[EDI], AH
		MOV	ESI, start[EBP]
		MOV	EDI, end[EBP]
		SHR	plane[EBP], 1
		MOV	EBX, diff[EBP]
		DEC	count[EBP]
		JGE	CB11h
		MOV	EDX, help[EBP]	; next line / get linecounter
		SUB	start[EBP], 80
		SUB	end[EBP], 80
		MOV	ESI, start[EBP]
		MOV	EDI, end[EBP]
		MOV	count[EBP], 3
		MOV	plane[EBP], 8
		DEC	EDX
		MOV	help[EBP], EDX	; save new linecounter
		CMP	EDX, 0
		JG	CB11h
		JMP	resetgrafCB
CB12:
		MOV	EAX, h[EBP]	; (sx >= dx) & (sy >= dy)
		DEC	EAX
		IMUL	EAX, width3	; w3[EBP]	; (Note: EDX is not modified)
		SUB	ESI, EAX
		SUB	EDI, EAX
		MOV	start[EBP], ESI
		MOV	end[EBP], EDI
		MOV	help[EBP], EDX	; save linecounter
		MOV	EBX, diff[EBP]
		CMP	EBX, 1 
		JLE	byte12
		CMP	CL, 0	; rotate shift = 0 ?
		JE	qCB12	; quick CopyBlock
byte12:
		MOV	count[EBP], 3	; there are 4 Bitplanes
		MOV	plane[EBP], 8
cbl1:
		MOV	DX, 03CEH
		MOV	AH, count[EBP]
		MOV	AL, 4
		OUT	DX, AX	; select plane to read
		MOV	AH, leftmask[EBP]	; bitmask select
		MOV	AL, 8
		OUT	DX, AX	; set mask at destination
		MOV	DX, 03C4H
		MOV	AH, plane[EBP]
		MOV	AL, 2
		OUT	DX, AX	; set sequencer
		XOR	EAX, EAX
		MOV	AH, [ESI]
		MOV	AL, 1[ESI]
		ADD	ESI, 2
		ROR	EAX, CL
		CMP	EBX, 0
		JL	cbl41
cbl7i:
		MOV	DL, [EDI]	; latch bytes
		MOV	[EDI], AH
		INC	EDI
		ROL	EAX, 8	; ready for new out
		CMP	EBX, 0	; in 2 bytes ?
		JE	cbl4 ;**
		MOV	help2[EBP], EAX
		MOV	DX, 03CEH
		MOV	AX, 0FF08H	; all maskbits
		OUT	DX, AX
		MOV	EAX, help2[EBP]
cbl7:
		ROL	EAX, CL
		MOV	AL, [ESI]
		INC	ESI
		ROR	EAX, CL
		MOV	[EDI], AH
		INC	EDI
		ROL	EAX, 8
		DEC	BX
		JG	cbl7
cbl4:
		MOV	EBX, x6[EBP]
		SUB	EBX, x5[EBP]
		MOV	help2[EBP], EBX
		MOV	EBX, x2[EBP]
		SUB	EBX, x1[EBP]
		CMP	EBX, help2[EBP]
		JE	cbl41
		ROL	EAX, CL
		MOV	AL, [ESI]
		ROR	EAX, CL
cbl41:
		PUSH	EAX
		MOV	DX, 03CEH
		MOV	AH, rightmask[EBP]
		MOV	AL, 8
		OUT	DX, AX	; set right dest bitmask
		POP	EAX
		MOV	DL, [EDI]
		MOV	[EDI], AH
		MOV	ESI, start[EBP]
		MOV	EDI, end[EBP]
		SHR	plane[EBP], 1
		MOV	EBX, diff[EBP]
		DEC	count[EBP]
		JGE	cbl1
		MOV	EDX, help[EBP]	; next line / get linecounter
		ADD	start[EBP], 80
		ADD	end[EBP], 80
		MOV	ESI, start[EBP]
		MOV	EDI, end[EBP]
		MOV	plane[EBP], 8
		MOV	count[EBP], 3
		DEC	EDX
		MOV	help[EBP], EDX	; save new linecounter
		CMP	EDX, 0
		JG	cbl1
		JMP	resetgrafCB
CB10:
		MOV	EAX, x2[EBP]	; (sx < dx) & (sy < dy)
		SUB	EAX, x1[EBP]
		ADD	ESI, EAX
		MOV	EAX, x6[EBP]
		SUB	EAX, x5[EBP]
		ADD	EDI, EAX
		MOV	start[EBP], ESI	; startbyte source bottom right
		MOV	end[EBP], EDI	; starbyte dest bottom right
		MOV	help[EBP], EDX	; save linecounter
		MOV	EBX, diff[EBP]
		CMP	EBX, 1
		JLE	byte10
		CMP	CL, 0
		JE	qCB10	; Quick CopyBlock
byte10:
		MOV	count[EBP], 3	; there are 4 Bitplanes
		MOV	plane[EBP], 8
cbl10:
		MOV	DX, 03CEH
		MOV	AH, count[EBP]
		MOV	AL, 4
		OUT	DX, AX	; select plane to read
		MOV	AH, rightmask[EBP]	; bitmask select
		MOV	AL, 8
		OUT	DX, AX	; set mask at destination
		MOV	DX, 03C4H
		MOV	AH, plane[EBP]
		MOV	AL, 2
		OUT	DX, AX	; set sequencer
		XOR	EAX, EAX
		MOV	AL, [ESI]
		MOV	AH, -1[ESI]
		SUB	ESI, 2
		ROR	EAX, CL
		CMP	EBX, 0	; in one byte ?
		JGE	cbl11i
		MOV	DL, rightmask[EBP]	; xchg masks
		MOV	leftmask[EBP], DL
		JMP	cbl121
cbl11i:
		MOV	DL, [EDI]	; latch bytes
		MOV	[EDI], AL
		DEC	EDI
		ROR	EAX, 8
		CMP	EBX, 0
		JE	cbl12 ;**
		MOV	help2[EBP], EAX
		MOV	DX, 03CEH
		MOV	AX, 0FF08H	; all maskbits
		OUT	DX, AX
		MOV	EAX, help2[EBP]
cbl11:
		ROL	EAX, CL
		MOV	AH, [ESI]
		DEC	ESI
		ROR	EAX, CL
		MOV	[EDI], AL
		DEC	EDI
		ROR	EAX, 8
		DEC	BX
		JG	cbl11
cbl12:
		MOV	EBX, x6[EBP]
		SUB	EBX, x5[EBP]
		MOV	help2[EBP], EBX
		MOV	EBX, x2[EBP]
		SUB	EBX, x1[EBP]
		CMP	EBX, help2[EBP]
		JE	cbl121
		ROL	EAX, CL
		MOV	AH, [ESI]
		ROR	EAX, CL
cbl121:
		PUSH	EAX
		MOV	DX, 03CEH
		MOV	AH, leftmask[EBP]
		MOV	AL, 8
		OUT	DX, AX	; set left dest bitmask
		POP	EAX
		MOV	DL, [EDI]
		MOV	[EDI], AL
		MOV	ESI, start[EBP]
		MOV	EDI, end[EBP]
		SHR	plane[EBP], 1
		MOV	EBX, diff[EBP]
		DEC	count[EBP]
		JGE	cbl10
		MOV	EDX, help[EBP]	; next line / get linecounter
		SUB	start[EBP], 80
		SUB	end[EBP], 80
		MOV	ESI, start[EBP]
		MOV	EDI, end[EBP]
		MOV	plane[EBP], 8
		MOV	count[EBP], 3
		DEC	EDX
		MOV	help[EBP], EDX	; save new linecounter
		CMP	EDX, 0
		JG	cbl10
		JMP	resetgrafCB
CB13:
		MOV	EAX, h[EBP]	; (sx < dx) & (sy >= dy)
		DEC	EAX
		IMUL	EAX, width3	; w3[EBP]
		SUB	ESI, EAX
		SUB	EDI, EAX
		MOV	EAX, x2[EBP]
		SUB	EAX, x1[EBP]
		ADD	ESI, EAX
		MOV	EAX, x6[EBP]
		SUB	EAX, x5[EBP]
		ADD	EDI, EAX
		MOV	start[EBP], ESI
		MOV	end[EBP], EDI
		MOV	help[EBP], EDX	; save linecounter
		MOV	EBX, diff[EBP]
		CMP	EBX, 1
		JLE	byte13
		CMP	CL, 0
		JE	qCB13
byte13:
		MOV	count[EBP], 3	; there are 4 Bitplanes
		MOV	plane[EBP], 8
cbl13:
		MOV	DX, 03CEH
		MOV	AH, count[EBP]
		MOV	AL, 4
		OUT	DX, AX	; select plane to read
		MOV	AH, rightmask[EBP]	; bitmask select
		MOV	AL, 8
		OUT	DX, AX	; set mask at destination
		MOV	DX, 03C4H
		MOV	AH, plane[EBP]
		MOV	AL, 2
		OUT	DX, AX	; set sequencer
		XOR	EAX, EAX
		MOV	AL, [ESI]
		MOV	AH, -1[ESI]
		SUB	ESI, 2
		ROR	EAX, CL
		CMP	EBX, 0
		JGE	cbl14i
		MOV	DL, rightmask[EBP]
		MOV	leftmask[EBP], DL
		JMP	cbl151
cbl14i:
		MOV	DL, [EDI]	; latch bytes
		MOV	[EDI], AL
		DEC	EDI
		ROR	EAX, 8
		CMP	EBX, 0	; in 2 bytes ?
		JE	cbl15 ;**
		MOV	help2[EBP], EAX
		MOV	DX, 03CEH
		MOV	AX, 0FF08H	; all maskbits
		OUT	DX, AX
		MOV	EAX, help2[EBP]
cbl14:
		ROL	EAX, CL
		MOV	AH, [ESI]
		DEC	ESI
		ROR	EAX, CL
		MOV	[EDI], AL
		DEC	EDI
		ROR	EAX, 8
		DEC	BX
		JG	cbl14
cbl15:
		MOV	EBX, x6[EBP]
		SUB	EBX, x5[EBP]
		MOV	help2[EBP], EBX
		MOV	EBX, x2[EBP]
		SUB	EBX, x1[EBP]
		CMP	EBX, help2[EBP]
		JE	cbl151
		ROL	EAX, CL
		MOV	AH, [ESI]
		ROR	EAX, CL
cbl151:
		PUSH	EAX
		MOV	DX, 03CEH
		MOV	AH, leftmask[EBP]
		MOV	AL, 8
		OUT	DX, AX	; set left dest bitmask
		POP	EAX
		MOV	DL, [EDI]
		MOV	[EDI], AL
		MOV	ESI, start[EBP]
		MOV	EDI, end[EBP]
		SHR	plane[EBP], 1
		MOV	EBX, diff[EBP]
		DEC	count[EBP]
		JGE	cbl13
		MOV	EDX, help[EBP]	; next line / get linecounter
		ADD	start[EBP], 80
		ADD	end[EBP], 80
		MOV	ESI, start[EBP]
		MOV	EDI, end[EBP]
		MOV	count[EBP], 3
		MOV	plane[EBP], 8
		DEC	EDX
		MOV	help[EBP], EDX	; save new linecounter
		CMP	EDX, 0
		JG	cbl13
		
		JMP	resetgrafCB
qCB12:
		MOV	DX, 03CEH	; Quick CopyBlock begin
		MOV	AH, leftmask[EBP]	; bitmask select
		MOV	AL, 8
		OUT	DX, AX	; set mask at destination
		MOV	count[EBP], 3
		MOV	plane[EBP], 8
q12lloop:
		MOV	AH, count[EBP]
		MOV	AL, 4
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AH, plane[EBP]
		MOV	AL, 2
		OUT	DX, AX
		MOV	CL, [ESI]	; fetch source
		MOV	AL, [EDI]	; latch at destiation
		MOV	[EDI], CL	; set source
		MOV	DX, 03CEH
		SHR	plane[EBP], 1
		DEC	count[EBP]
		JGE	q12lloop	; next plane
		MOV	DX, 03C4H
		MOV	AH, 00FH
		MOV	AL, 2
		OUT	DX, AX	; all planes again
		MOV	DX, 03CEH
		INC	ESI
		INC	EDI
		MOV	AX, 0105H	; writemode 1
		OUT	DX, AX
qcbl1:
		MOV	AL, [ESI]
		INC	ESI
		MOV	[EDI], AH
		INC	EDI
		DEC	BX
		JG	qcbl1
qcbl7:
		MOV	AH, rightmask[EBP]
		MOV	AL, 8
		OUT	DX, AX	; set right dest bitmask
		MOV	AX, 0005	; writemode 0
		OUT	DX, AX
		MOV	count[EBP], 3
		MOV	plane[EBP], 8
q12rloop:
		MOV	AH, count[EBP]
		MOV	AL, 4
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AH, plane[EBP]
		MOV	AL, 2
		OUT	DX, AX
		MOV	CL, [ESI]	; fetch source
		MOV	AL, [EDI]	; latch at destiation
		MOV	[EDI], CL	; set source
		MOV	DX, 03CEH
		SHR	plane[EBP], 1
		DEC	count[EBP]
		JGE	q12rloop	; next plane
		MOV	EBX, diff[EBP]
		ADD	start[EBP], 80
		ADD	end[EBP], 80
		MOV	ESI, start[EBP]
		MOV	EDI, end[EBP]
		DEC	help[EBP]	; dec linecounter
		JG	qCB12
		JMP	resetgrafCB
qCB11:
		MOV	DX, 03CEH
		MOV	AH, leftmask[EBP]	; bitmask select
		MOV	AL, 8
		OUT	DX, AX	; set mask at destination
		MOV	count[EBP], 3
		MOV	plane[EBP], 8
q11lloop:
		MOV	AH, count[EBP]
		MOV	AL, 4
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AH, plane[EBP]
		MOV	AL, 2
		OUT	DX, AX
		MOV	CL, [ESI]	; fetch source
		MOV	AL, [EDI]	; latch at destiation
		MOV	[EDI], CL	; set source
		MOV	DX, 03CEH
		SHR	plane[EBP], 1
		DEC	count[EBP]
		JGE	q11lloop	; next plane
		MOV	DX, 03C4H
		MOV	AH, 00FH
		MOV	AL, 2
		OUT	DX, AX	; all panes again
		MOV	DX, 03CEH
		INC	ESI
		INC	EDI
		MOV	AX, 0105H	; writemode 1
		OUT	DX, AX
qcbl6:
		MOV	AL, [ESI]
		INC	ESI
		MOV	[EDI], AH
		INC	EDI
		DEC	BX
		JG	qcbl6
qcbl3:
		MOV	AH, rightmask[EBP]
		MOV	AL, 8
		OUT	DX, AX	; set right dest bitmask
		MOV	AX, 0005	; writemode 0
		OUT	DX, AX
		MOV	count[EBP], 3
		MOV	plane[EBP], 8
q11rloop:
		MOV	AH, count[EBP]
		MOV	AL, 4
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AH, plane[EBP]
		MOV	AL, 2
		OUT	DX, AX
		MOV	CL, [ESI]	; fetch source
		MOV	AL, [EDI]	; latch at destiation
		MOV	[EDI], CL	; set source
		MOV	DX, 03CEH
		SHR	plane[EBP], 1
		DEC	count[EBP]
		JGE	q11rloop	; next plane
		MOV	EBX, diff[EBP]
		SUB	start[EBP], 80
		SUB	end[EBP], 80
		MOV	ESI, start[EBP]
		MOV	EDI, end[EBP]
		DEC	help[EBP]	; dec linecounter
		JG	qCB11
		JMP	resetgrafCB
qCB10:
		MOV	DX, 03CEH
		MOV	AH, rightmask[EBP]	; bitmask select
		MOV	AL, 8
		OUT	DX, AX	; set mask at destination
		MOV	count[EBP], 3
		MOV	plane[EBP], 8
q10rloop:
		MOV	AH, count[EBP]
		MOV	AL, 4
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AH, plane[EBP]
		MOV	AL, 2
		OUT	DX, AX
		MOV	CL, [ESI]	; fetch source
		MOV	AL, [EDI]	; latch at destiation
		MOV	[EDI], CL	; set source
		MOV	DX, 03CEH
		SHR	plane[EBP], 1
		DEC	count[EBP]
		JGE	q10rloop	; next plane
		MOV	DX, 03C4H
		MOV	AH, 00FH
		MOV	AL, 2
		OUT	DX, AX	; all panes again
		MOV	DX, 03CEH
		DEC	ESI
		DEC	EDI
		MOV	AX, 0105H	; writemode 1
		OUT	DX, AX
qcbl10:
		MOV	AL, [ESI]
		DEC	ESI
		MOV	[EDI], AH
		DEC	EDI
		DEC	BX
		JG	qcbl10
qcbl12:
		MOV	AX, 0005	; writemode 0
		OUT	DX, AX
		MOV	AH, leftmask[EBP]
		MOV	AL, 8
		OUT	DX, AX	; set left dest bitmask
		MOV	count[EBP], 3
		MOV	plane[EBP], 8
q10lloop:
		MOV	AH, count[EBP]
		MOV	AL, 4
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AH, plane[EBP]
		MOV	AL, 2
		OUT	DX, AX
		MOV	CL, [ESI]	; fetch source
		MOV	AL, [EDI]	; latch at destiation
		MOV	[EDI], CL	; set source
		MOV	DX, 03CEH
		SHR	plane[EBP], 1
		DEC	count[EBP]
		JGE	q10lloop	; next plane
		MOV	EBX, diff[EBP]
		SUB	start[EBP], 80
		SUB	end[EBP], 80
		MOV	ESI, start[EBP]
		MOV	EDI, end[EBP]
		DEC	help[EBP]	; dec linecounter
		JG	qCB10
		JMP	resetgrafCB
qCB13:
		MOV	DX, 03CEH
		MOV	AH, rightmask[EBP]	; bitmask select
		MOV	AL, 8
		OUT	DX, AX	; set mask at destination
		MOV	AH, 0
		MOV	AL, 3
		OUT	DX, AX
		MOV	count[EBP], 3
		MOV	plane[EBP], 8
q13rloop:
		MOV	AH, count[EBP]
		MOV	AL, 4
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AH, plane[EBP]
		MOV	AL, 2
		OUT	DX, AX
		MOV	CL, [ESI]	; fetch source
		MOV	AL, [EDI]	; latch at destiation
		MOV	[EDI], CL	; set source
		MOV	DX, 03CEH
		SHR	plane[EBP], 1
		DEC	count[EBP]
		JGE	q13rloop	; next plane
		MOV	DX, 03C4H
		MOV	AH, 00FH
		MOV	AL, 2
		OUT	DX, AX	; all panes again
		MOV	DX, 03CEH
		DEC	ESI
		DEC	EDI
		MOV	AX, 0105H	; writemode 1
		OUT	DX, AX
qcbl13:
		MOV	AL, [ESI]
		DEC	ESI
		MOV	[EDI], AH
		DEC	EDI
		DEC	BX
		JG	qcbl13
qcbl14:
		MOV	AX, 0005	; writemode 0
		OUT	DX, AX
		MOV	AH, leftmask[EBP]
		MOV	AL, 8
		OUT	DX, AX	; set left dest bitmask
		MOV	count[EBP], 3
		MOV	plane[EBP], 8
q13lloop:
		MOV	AH, BYTE count[EBP]
		MOV	AL, 4
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AH, plane[EBP]
		MOV	AL, 2
		OUT	DX, AX
		MOV	CL, [ESI]	; fetch source
		MOV	AL, [EDI]	; latch at destiation
		MOV	[EDI], CL	; set source
		MOV	DX, 03CEH
		SHR	plane[EBP], 1
		DEC	count[EBP]
		JGE	q13lloop	; next plane
		MOV	EBX, diff[EBP]
		ADD	start[EBP], 80
		ADD	end[EBP], 80
		MOV	ESI, start[EBP]
		MOV	EDI, end[EBP]
		DEC	help[EBP]	; dec linecounter
		JG	qCB13
		JMP	resetgrafCB
resetgrafCB:
		MOV	DX, 03CEH
		MOV	AX, 0FF08H	; default bitmask
		OUT	DX, AX
		MOV	AX, 0005	; default mode-reg
		MOV	DX, AX
		MOV	AX, 0003	; default Function-Select
		OUT	DX, AX
		MOV	AX, 0001	; default enable set/reset
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AX, 0F02H	; default map mask
		OUT	DX, AX
endCB:
ret:
	END CopyBlock;

	PROCEDURE SetMode*(x: LONGINT; s: SET);
	BEGIN END SetMode;
	
	PROCEDURE CPTranslate(pat: LONGINT;  cpX, cpY, cpW, cpH: INTEGER;  VAR buf: ARRAY OF INTEGER);
	VAR cpw, cph, cpsw: SHORTINT;
	CODE {SYSTEM.i386}
		MOV BX,cpW[EBP]
		ADD BX,7
		SHR BX,3
		MOV cpw[EBP],BL				 ; cpw := cpW DIV 8
		MOV ESI,pat[EBP]
		XOR EAX,EAX
		MOV AL,[ESI]
		ADD AX,7
		SHR AX,3
		MOV cpsw[EBP],AL				  ; cpsw := p.w DIV 8
		MOV EDI,buf[EBP]
		MOV AX,cpW[EBP]
		MOV [EDI],AL				 ; new p.w
		INC EDI
		MOV AX,cpH[EBP]				  ; new p.h
		MOV [EDI],AL
		INC EDI
		MOVSX BX,cpsw[EBP]
		MOV AX,cpY[EBP]
		IMUL  AX,BX
		MOVSX EAX,AX
		ADD ESI,EAX
		MOV CX,cpX[EBP]
		SHR CX,3
		MOVSX ECX,CX
		ADD ESI,ECX
		ADD ESI,2					; ESI := Sourcepos for Copyloop
		MOV cph[EBP],0					; init loop variables
		MOV DH, 0
		MOV DL,cph[EBP]
		MOV CX,cpX[EBP]
		AND CX,7					 ; cpX MOD 8  
loopcp:
		CMP cpH[EBP],DX
		JLE l7cp					 ; height reached ?
		MOV EAX,[ESI]
		SHR EAX,CL				 ; in proper position
		PUSH  ECX
		MOV EBX,-2
		MOV CX,cpW[EBP]
		SHL EBX,CL
		SHR EBX, 1
		NOT EBX
		AND EAX,EBX
		POP ECX
		MOV [EDI],EAX				; copy for a new pattern
		MOVSX EAX,cpsw[EBP]
		ADD ESI,EAX				  ; one line in source up
		MOVSX EAX,cpw[EBP]
		ADD EDI,EAX				  ; one line at destination up
		INC DX
		JMP loopcp
l7cp:
	END CPTranslate;
	
	PROCEDURE CP1(col: CHAR;  dest, pat, X: LONGINT;  h: SHORTINT);
	CODE {SYSTEM.i386}
		MOV EDI, dest[EBP]
		MOV ESI, pat[EBP]	; patternaddress
		ADD ESI, 2
		MOV ECX, X[EBP]	; X MOD 8
		AND ECX, 7
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AH, col[EBP]
		MOV AL, 2
		OUT DX, AX
		LEA EAX, rev	; MOV EAX, reverse[EBP]
		MOV DL, h[EBP]
		XOR EBX, EBX
cploop2:
		MOV BL, [ESI]
		INC ESI
		SHL BL, CL
		MOV BL, [EAX][EBX]
		MOV DH, [EDI]	; latch byte
		MOV [EDI], BL	; set pattern
		SUB EDI, width3	; w3[EBP]
		DEC DL
		JG cploop2
	END CP1;

	PROCEDURE CP2(col: CHAR;  dest, pat, X: LONGINT;  h: SHORTINT);
	CODE {SYSTEM.i386}
		MOV EDI, dest[EBP]
		MOV ESI, pat[EBP]	; patternaddress
		ADD ESI, 2
		MOV ECX, X[EBP]	; X MOD 8
		AND ECX, 7
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AH, col[EBP]
		MOV AL, 2
		OUT DX, AX
		LEA EAX, rev	; MOV EAX, reverse[EBP]
cploop3:
		XOR EBX, EBX
		MOV BL, [ESI]
		INC ESI
		SHL BX, CL
		MOV DX, BX
		AND BX, 0FFH
		MOV DL, [EAX][EBX]
		MOV BL, DH
		MOV DH, [EAX][EBX]
		MOV BL, [EDI]	; latch byte
		MOV [EDI], DL	; set pattern
		MOV BL, 1[EDI]	; latch byte
		MOV 1[EDI], DH	; set pattern
		SUB EDI, width3
		DEC h[EBP]
		JG cploop3
	END CP2;
	
	PROCEDURE CP3(col: CHAR;  dest, pat, X: LONGINT;  h: SHORTINT);
	CODE {SYSTEM.i386}
		MOV EDI, dest[EBP]
		MOV ESI, pat[EBP]	; patternaddress
		ADD ESI, 2
		MOV ECX, X[EBP]	; X MOD 8
		AND ECX, 7
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AH, col[EBP]
		MOV AL, 2
		OUT DX, AX
		LEA EAX, rev	; MOV EAX, reverse[EBP]
cploop5:
		XOR EBX, EBX
		MOV BX, [ESI]
		ADD ESI, 2
		SHL BX, CL
		MOV DX, BX
		AND BX, 0FFH
		MOV DL, [EAX][EBX]
		MOV BL, DH
		MOV DH, [EAX][EBX]
		MOV BL, [EDI]	; latch byte
		MOV [EDI], DL	; set pattern
		MOV BL, 1[EDI]	; latch byte
		MOV 1[EDI], DH	; set pattern
		SUB EDI, width3
		DEC h[EBP]
		JG cploop5
	END CP3;
	
	PROCEDURE CP4(col: CHAR;  dest, pat, X: LONGINT;  h: SHORTINT);
	CODE {SYSTEM.i386}
		MOV EDI, dest[EBP]
		MOV ESI, pat[EBP]	; patternaddress
		ADD ESI, 2
		MOV ECX, X[EBP]	; X MOD 8
		AND ECX, 7
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AH, col[EBP]
		MOV AL, 2
		OUT DX, AX
		LEA EAX, rev	; MOV EAX, reverse[EBP]
cploop7:
		XOR EBX, EBX
		MOV BX, [ESI]
		ADD ESI, 2
		SHL EBX, CL
		MOV DX, BX
		SHR EBX, 16
		AND BX, 0FFH
		MOV CH, [EAX][EBX]
		MOV BL, DL
		MOV DL, [EAX][EBX]
		MOV BL, DH
		MOV DH, [EAX][EBX]
		MOV BL, [EDI]	; latch byte
		MOV [EDI], DL	; set pattern
		MOV BL, 1[EDI]	; latch byte
		MOV 1[EDI], DH	; set pattern
		MOV BL, 2[EDI]	; latch byte
		MOV 2[EDI], CH	; set pattern
		SUB EDI, width3
		DEC h[EBP]
		JG cploop7
	END CP4;

	PROCEDURE CP5(col: CHAR;  dest, pat, X: LONGINT;  h: SHORTINT);
	CODE {SYSTEM.i386}
		MOV EDI, dest[EBP]
		MOV ESI, pat[EBP]	; patternaddress
		ADD ESI, 2
		MOV ECX, X[EBP]	; X MOD 8
		AND ECX, 7
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AH, col[EBP]
		MOV AL, 2
		OUT DX, AX
		LEA EAX, rev	; MOV EAX, reverse[EBP]
cploop9:
		MOV EBX, [ESI]
		ADD ESI, 3
		AND EBX, 0FFFFFFH
		SHL EBX, CL
		PUSH ECX
		MOV DX, BX
		SHR EBX, 16
		MOV CX, BX
		AND BX, 0FFH
		MOV CL, [EAX][EBX]
		MOV BL, CH
		MOV CH, [EAX][EBX]
		MOV BL, DL
		MOV DL, [EAX][EBX]
		MOV BL, DH
		MOV DH, [EAX][EBX]
		MOV BL, [EDI]	; latch byte
		MOV [EDI], DL	; set pattern
		MOV BL, 1[EDI]	; latch byte
		MOV 1[EDI], DH	; set pattern
		MOV BL, 2[EDI]	; latch byte
		MOV 2[EDI], CL	; set pattern
		MOV BL, 3[EDI]	; latch byte
		MOV 3[EDI], CH	; set pattern
		POP ECX
		SUB EDI, width3
		DEC h[EBP]
		JG cploop9
	END CP5;

	PROCEDURE CP6(col: CHAR;  dest, pat, X: LONGINT;  h: SHORTINT);
	CODE {SYSTEM.i386}
		MOV EDI, dest[EBP]
		MOV ESI, pat[EBP]	; patternaddress
		ADD ESI, 2
		MOV ECX, X[EBP]	; X MOD 8
		AND ECX, 7
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AH, col[EBP]
		MOV AL, 2
		OUT DX, AX
		LEA EAX, rev	; MOV EAX, reverse[EBP]
cploop11:
		MOV EBX, [ESI]
		ADD ESI, 4
		PUSH ESI
		XOR ESI, ESI
		SHLD ESI, EBX, CL
		SHL EBX, CL
		PUSH ECX
		MOV DX, BX
		SHR EBX, 16
		MOV CX, BX
		AND BX, 0FFH
		MOV CL, [EAX][EBX]
		MOV BL, CH
		MOV CH, [EAX][EBX]
		MOV BL, DL
		MOV DL, [EAX][EBX]
		MOV BL, DH
		MOV DH, [EAX][EBX]
		MOV BH, [EAX][ESI]
		MOV BL, [EDI]	; latch byte
		MOV [EDI], DL	; set pattern
		MOV BL, 1[EDI]	; latch byte
		MOV 1[EDI], DH	; set pattern
		MOV BL, 2[EDI]	; latch byte
		MOV 2[EDI], CL	; set pattern
		MOV BL, 3[EDI]	; latch byte
		MOV 3[EDI], CH	; set pattern
		MOV BL, 4[EDI]	; latch byte
		MOV 4[EDI], BH	; set pattern
		POP ECX
		POP ESI
		SUB EDI, width3
		DEC h[EBP]
		JG cploop11
	END CP6;

	PROCEDURE CP7(col: CHAR;  dest, pat, X: LONGINT;  h: SHORTINT);
	CODE {SYSTEM.i386}
		MOV EDI, dest[EBP]
		MOV ESI, pat[EBP]	; patternaddress
		ADD ESI, 2
		MOV ECX, X[EBP]	; X MOD 8
		AND ECX, 7
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
cploop1:
		MOV AX, 0F02H
		OUT DX, AX
		MOV EDX, 03CEH	; AL = Data/Rotate; AH = Modus; DX = Graphic-Controller
		MOV AX, 0803H
		OUT DX, AX
		XOR EBX, EBX
		MOV BL, [ESI]
		INC ESI
		SHL BL, CL
		LEA EDX, rev
		MOV BL, [EDX][EBX]
		MOV BH, [EDI]	; latch byte
		NOT BL
		MOV [EDI], BL	; clear pattern
		NOT BL
		MOV EDX, 03CEH	; AL = Data/Rotate; AH = Modus; DX = Graphic-Controller
		MOV AX, 1003H
		OUT DX, AX
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AL, 2
		MOV AH, col[EBP]
		OUT DX, AX
		MOV BH, [EDI]	; latch byte
		MOV [EDI], BL	; set pattern
		SUB EDI, width3
		DEC h[EBP]
		JG cploop1
	END CP7;

	PROCEDURE CP8(col: CHAR;  dest, pat, X: LONGINT;  h: SHORTINT);
	CODE {SYSTEM.i386}
		MOV EDI, dest[EBP]
		MOV ESI, pat[EBP]	; patternaddress
		ADD ESI, 2
		MOV ECX, X[EBP]	; X MOD 8
		AND ECX, 7
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
cploop4:
		MOV AX, 0F02H
		OUT DX, AX
		MOV EDX, 03CEH	; AL = Data/Rotate; AH = Modus; DX = Graphic-Controller
		MOV AX, 0803H
		OUT DX, AX
		XOR EBX, EBX
		MOV BL, [ESI]
		INC ESI
		SHL BX, CL
		LEA EDX, rev
		MOV AX, BX
		AND BX, 0FFH
		MOV AL, [EDX][EBX]
		MOV BL, AH
		MOV AH, [EDX][EBX]
		NOT AX
		MOV BH, [EDI]	; latch byte
		MOV [EDI], AL	; clear pattern
		MOV BH, 1[EDI]	; latch byte
		MOV 1[EDI], AH	; clear pattern
		NOT AX
		MOV BX, AX
		MOV EDX, 03CEH	; AL = Data/Rotate; AH = Modus; DX = Graphic-Controller
		MOV AX, 1003H
		OUT DX, AX
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AL, 2
		MOV AH, col[EBP]
		OUT DX, AX
		MOV CH, [EDI]	; latch byte
		MOV [EDI], BL	; set pattern
		MOV CH, 1[EDI]	; latch byte
		MOV 1[EDI], BH	; set pattern
		SUB EDI, width3
		DEC h[EBP]
		JG cploop4
	END CP8;

	PROCEDURE CP9(col: CHAR;  dest, pat, X: LONGINT;  h: SHORTINT);
	CODE {SYSTEM.i386}
		MOV EDI, dest[EBP]
		MOV ESI, pat[EBP]	; patternaddress
		ADD ESI, 2
		MOV ECX, X[EBP]	; X MOD 8
		AND ECX, 7
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
cploop6:
		MOV AX, 0F02H
		OUT DX, AX
		MOV EDX, 03CEH	; AL = Data/Rotate; AH = Modus; DX = Graphic-Controller
		MOV AX, 0803H
		OUT DX, AX
		XOR EBX, EBX
		MOV BX, [ESI]
		ADD ESI, 2
		SHL BX, CL
		LEA EDX, rev
		MOV AX, BX
		AND BX, 0FFH
		MOV AL, [EDX][EBX]
		MOV BL, AH
		MOV AH, [EDX][EBX]
		NOT AX
		MOV BH, [EDI]	; latch byte
		MOV [EDI], AL	; clear pattern
		MOV BH, 1[EDI]	; latch byte
		MOV 1[EDI], AH	; clear pattern
		NOT AX
		MOV BX, AX
		MOV EDX, 03CEH	; AL = Data/Rotate; AH = Modus; DX = Graphic-Controller
		MOV AX, 1003H
		OUT DX, AX
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AL, 2
		MOV AH, col[EBP]
		OUT DX, AX
		MOV CH, [EDI]	; latch byte
		MOV [EDI], BL	; set pattern
		MOV CH, 1[EDI]	; latch byte
		MOV 1[EDI], BH	; set pattern
		SUB EDI, width3
		DEC h[EBP]
		JG cploop6
	END CP9;

	PROCEDURE CP10(col: CHAR;  dest, pat, X: LONGINT;  h: SHORTINT);
	CODE {SYSTEM.i386}
		MOV EDI, dest[EBP]
		MOV ESI, pat[EBP]	; patternaddress
		ADD ESI, 2
		MOV ECX, X[EBP]	; X MOD 8
		AND ECX, 7
cploop8:
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AX, 0F02H
		OUT DX, AX
		MOV EDX, 03CEH	; AL = Data/Rotate; AH = Modus; DX = Graphic-Controller
		MOV AX, 0803H
		OUT DX, AX
		XOR EBX, EBX
		MOV BX, [ESI]
		ADD ESI, 2
		SHL EBX, CL
		LEA EDX, rev
		MOV AX, BX
		SHR EBX, 16
		AND BX, 0FFH
		MOV CH, [EDX][EBX]
		MOV BL, AL
		MOV AL, [EDX][EBX]
		MOV BL, AH
		MOV AH, [EDX][EBX]
		NOT AX
		NOT CH
		MOV BH, [EDI]	; latch byte
		MOV [EDI], AL	; clear pattern
		MOV BH, 1[EDI]	; latch byte
		MOV 1[EDI], AH	; clear pattern
		MOV BH, 2[EDI]	; latch byte
		MOV 2[EDI], CH	; clear pattern
		NOT CH
		NOT AX
		MOV BX, AX
		MOV EDX, 03CEH	; AL = Data/Rotate; AH = Modus; DX = Graphic-Controller
		MOV AX, 1003H
		OUT DX, AX
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AL, 2
		MOV AH, col[EBP]
		OUT DX, AX
		MOV DH, [EDI]	; latch byte
		MOV [EDI], BL	; set pattern
		MOV DH, 1[EDI]	; latch byte
		MOV 1[EDI], BH	; set pattern
		MOV DH, 2[EDI]	; latch byte
		MOV 2[EDI], CH	; set pattern
		SUB EDI, width3
		DEC h[EBP]
		JG cploop8
	END CP10;

	PROCEDURE CP11(col: CHAR;  dest, pat, X: LONGINT;  h: SHORTINT);
	CODE {SYSTEM.i386}
		MOV EDI, dest[EBP]
		MOV ESI, pat[EBP]	; patternaddress
		ADD ESI, 2
		MOV ECX, X[EBP]	; X MOD 8
		AND ECX, 7
cploop10:
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AX, 0F02H
		OUT DX, AX
		MOV EDX, 03CEH	; AL = Data/Rotate; AH = Modus; DX = Graphic-Controller
		MOV AX, 0803H
		OUT DX, AX
		MOV EBX, [ESI]
		AND EBX, 0FFFFFFH
		ADD ESI, 3
		SHL EBX, CL
		PUSH ECX
		LEA EDX, rev
		MOV AX, BX
		SHR EBX, 16
		MOV CX, BX
		AND BX, 0FFH
		MOV CL, [EDX][EBX]
		MOV BL, CH
		MOV CH, [EDX][EBX]
		MOV BL, AL
		MOV AL, [EDX][EBX]
		MOV BL, AH
		MOV AH, [EDX][EBX]
		NOT AX
		NOT CX
		MOV BH, [EDI]	; latch byte
		MOV [EDI], AL	; clear pattern
		MOV BH, 1[EDI]	; latch byte
		MOV 1[EDI], AH	; clear pattern
		MOV BH, 2[EDI]	; latch byte
		MOV 2[EDI], CL	; clear pattern
		MOV BH, 3[EDI]	; latch byte
		MOV 3[EDI], CH	; clear pattern
		NOT CX
		NOT AX
		MOV BX, AX
		MOV EDX, 03CEH	; AL = Data/Rotate; AH = Modus; DX = Graphic-Controller
		MOV AX, 1003H
		OUT DX, AX
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AL, 2
		MOV AH, col[EBP]
		OUT DX, AX
		MOV DH, [EDI]	; latch byte
		MOV [EDI], BL	; set pattern
		MOV DH, 1[EDI]	; latch byte
		MOV 1[EDI], BH	; set pattern
		MOV DH, 2[EDI]	; latch byte
		MOV 2[EDI], CL	; set pattern
		MOV DH, 3[EDI]	; latch byte
		MOV 3[EDI], CH	; set pattern
		POP ECX
		SUB EDI, width3
		DEC h[EBP]
		JG cploop10
	END CP11;

	PROCEDURE CP12(col: CHAR;  dest, pat, X: LONGINT;  h: SHORTINT);
	CODE {SYSTEM.i386}
		MOV EDI, dest[EBP]
		MOV ESI, pat[EBP]	; patternaddress
		ADD ESI, 2
		MOV ECX, X[EBP]	; X MOD 8
		AND ECX, 7
cploop12:
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AX, 0F02H
		OUT DX, AX
		MOV EDX, 03CEH	; AL = Data/Rotate; AH = Modus; DX = Graphic-Controller
		MOV AX, 0803H
		OUT DX, AX
		MOV EBX, [ESI]
		ADD ESI, 4
		PUSH ESI
		XOR ESI, ESI
		SHLD ESI, EBX, CL
		SHL EBX, CL
		PUSH ECX
		LEA EDX, rev
		MOV AX, BX
		SHR EBX, 16
		MOV CX, BX
		AND BX, 0FFH
		MOV CL, [EDX][EBX]
		MOV BL, CH
		MOV CH, [EDX][EBX]
		MOV BL, AL
		MOV AL, [EDX][EBX]
		MOV BL, AH
		MOV AH, [EDX][EBX]
		MOV BL, [EDX][ESI]
		NOT AX
		NOT CX
		NOT BL
		MOV BH, [EDI]	; latch byte
		MOV [EDI], AL	; clear pattern
		MOV BH, 1[EDI]	; latch byte
		MOV 1[EDI], AH	; clear pattern
		MOV BH, 2[EDI]	; latch byte
		MOV 2[EDI], CL	; clear pattern
		MOV BH, 3[EDI]	; latch byte
		MOV 3[EDI], CH	; clear pattern
		MOV BH, 4[EDI]	; latch byte
		MOV 4[EDI], BL	; clear pattern
		NOT BL
		NOT CX
		NOT AX
		MOV DX, BX
		MOV BX, AX
		PUSH EDX
		MOV EDX, 03CEH	; AL = Data/Rotate; AH = Modus; DX = Graphic-Controller
		MOV AX, 1003H
		OUT DX, AX
		MOV EDX, 03C4H	; AL = Plane select; AH = Bitplanemask; DX = Sequencer
		MOV AL, 2
		MOV AH, col[EBP]
		OUT DX, AX
		POP EDX
		MOV DH, [EDI]	; latch byte
		MOV [EDI], BL	; set pattern
		MOV DH, 1[EDI]	; latch byte
		MOV 1[EDI], BH	; set pattern
		MOV DH, 2[EDI]	; latch byte
		MOV 2[EDI], CL	; set pattern
		MOV DH, 3[EDI]	; latch byte
		MOV 3[EDI], CH	; set pattern
		MOV DH, 4[EDI]	; latch byte
		MOV 4[EDI], DL	; set pattern
		POP ECX
		POP ESI
		SUB EDI, width3
		DEC h[EBP]
		JG cploop12
	END CP12;

	PROCEDURE CopyPattern*(col: Color; pat: Pattern; x, y, mode: LONGINT);
	VAR dest, i, diff: LONGINT; 
			w, h: SHORTINT; 
			x1, y1, cpX, cpY, cpW, cpH, nofbytes: INTEGER;
			buf: ARRAY 256 OF INTEGER;
			lm, rm: CHAR;
	BEGIN 
		SYSTEM.GET(pat, w); SYSTEM.GET(pat+1, h); 
		cpW := SHORT(w + x); cpH := SHORT(h + y); 
		x1 := SHORT(x); y1 := SHORT(y);
		IF x1 < clipx THEN x := clipx END;
		IF y1 < clipy THEN y := clipy END;
		IF cpW >  clipright THEN cpW :=  clipright END;
		IF cpH > cliptop THEN cpH := cliptop END;
		cpW := cpW - SHORT(x); cpH := cpH - SHORT(y); 
		cpX := SHORT(x) - x1; cpY := SHORT(y) - y1;
		IF (cpW <= 0) OR (cpH <= 0) OR (cpX < 0) OR (cpY < 0) THEN RETURN END;
		IF (cpW # w) OR (cpH # h) THEN
			CPTranslate(pat, cpX, cpY, cpW, cpH, buf);
			pat := SYSTEM.ADR(buf[0])
		END;
		SYSTEM.GET(pat, w); SYSTEM.GET(pat+1, h); 
		dest := ((Height-SHORT(y)-1) * width3 + SHORT(x) DIV 8) MOD 10000H;
		INC(dest, 0A0000H);	(* display offset *)
		(*help1 := (SHORT(x) + w-1) MOD 8;*)
		diff := (SHORT(x) + w-1) DIV 8 - (SHORT(x) DIV 8);
		SYSTEM.PORTOUT(03CEH, SYSTEM.VAL(INTEGER, 0FF08H));	(* AX = Default bitmask; DX = Graphic-Controller *)
		SYSTEM.PORTOUT(03CEH, SYSTEM.VAL(INTEGER, 5));	(* AL = Graphics mode; AH = Read-Mode = 0/Write-Mode = 0 (bits 0,1) *)
		IF mode = invert THEN
			SYSTEM.PORTOUT(03CEH, SYSTEM.VAL(INTEGER, 1803H));	(* AX = invert mode; DX = Graphic-Controller *)	
			IF w <= 8 THEN
				IF diff = 0 THEN
					CP1(CHR(col), dest, pat, SHORT(x), h)
				ELSE
					CP2(CHR(col), dest, pat, SHORT(x), h)
				END
			ELSIF w <= 16 THEN
				IF diff = 1 THEN
					CP3(CHR(col), dest, pat, SHORT(x), h)
				ELSE
					CP4(CHR(col), dest, pat, SHORT(x), h)
				END
			ELSIF w <= 24 THEN
				CP5(CHR(col), dest, pat, SHORT(x), h)
			ELSE
				CP6(CHR(col), dest, pat, SHORT(x), h)
			END
		ELSE (* paint & replace *)
			IF w <= 8 THEN
				IF diff = 0 THEN 
					CP7(CHR(col), dest, pat, SHORT(x), h)
				ELSE
					CP8(CHR(col), dest, pat, SHORT(x), h)
				END
			ELSIF w <= 16 THEN
				IF diff = 1 THEN
					CP9(CHR(col), dest, pat, SHORT(x), h)
				ELSE
					CP10(CHR(col), dest, pat, SHORT(x), h)
				END
			ELSIF w <= 24 THEN
				CP11(CHR(col), dest, pat, SHORT(x), h)
			ELSE
				CP12(CHR(col), dest, pat, SHORT(x), h)
			END
		END
	END CopyPattern;
	
	PROCEDURE ReplConst1(col: CHAR;  H, start: LONGINT;  rm, lm: CHAR);
	CODE {SYSTEM.i386}
		MOV AH, lm[EBP]
		AND AH, rm[EBP]
		MOV AL, 8
		MOV EDX, 03CEH
		OUT DX, AX	; Bitmask
		MOV AH, col[EBP]
		MOV ECX, H[EBP]
		MOV ESI, start[EBP]
rcloop1:
		MOV AL, [ESI]	; latch bytes
		MOV [ESI], AH
		SUB ESI, width3	;w3[EBP]
		LOOP rcloop1
	END ReplConst1;
	
	PROCEDURE ReplConst2(col: CHAR;  H: INTEGER;  start, end: LONGINT;  rm, lm: CHAR);
	VAR temp: LONGINT;
	CODE {SYSTEM.i386}
		MOV ESI, start[EBP]
		MOV BH, col[EBP]
		MOV EDI, end[EBP]
		SUB EDI, ESI	; difference beween start and end
		MOV temp[EBP], EDI	; save difference beween start and end
		MOV EDX, 03CEH		; set Graphic controller
rcloop2:
		MOV AH, lm[EBP]	; prepare left mask
		MOV AL, 8
		OUT DX, AX	; set left Bitmask
		MOV AL, [ESI]	; latch byte
		MOV [ESI], BH	; set byte
		MOV AX, 0FF08H	; prepare full mask
		OUT DX, AX	; set full mask
		MOV ECX,ESI
		INC ECX
rclabel2:
		CMP EDI, 1
		JLE rclabel1
		MOV AL, [ECX]	; latch bytes
		MOV [ECX], BH	; set bytes
		DEC EDI
		INC ECX
		JMP rclabel2
rclabel1:
		MOV AH, rm[EBP]	; prepare right mask
		MOV AL, 8
		OUT DX, AX	; set right Bitmask
		MOV AL, [ECX]	; latch byte
		MOV [ECX], BH	; set byte
		SUB ESI, width3;	w3[EBP]	; next line
		DEC H[EBP]
		MOV EDI, temp[EBP]
		JG rcloop2
	END ReplConst2;
	
	PROCEDURE ReplConst*(col: Color; x, y, w, h, mode: LONGINT);
	VAR right, top, X, Y, W, H: INTEGER; addr, start, end: LONGINT; rm, lm: CHAR;
	BEGIN 
		X := SHORT(x);  Y := SHORT(y);  W := SHORT(w);  H := SHORT(h);
		top := Y + H; right := X + W;
		IF X < clipx THEN X := clipx END;
		IF Y < clipy THEN Y := clipy END;
		IF  clipright < right THEN right :=  clipright END; 
		IF cliptop < top THEN top := cliptop END;
		W := right - X; H := top - Y;
		IF (W <= 0) OR (H <= 0) OR (X < 0) OR (Y < 0) THEN RETURN END;
		IF mode = invert THEN
			SYSTEM.PORTOUT(03CEH, SYSTEM.VAL(INTEGER, 1803H))	(* AL = Data/Rotate; AH = Modus; DX = Graphic-Controller *)
		ELSE	(* was replace only *)
			SYSTEM.PORTOUT(03CEH, SYSTEM.VAL(INTEGER, 03H))
		(*ELSE (* mode = paint *) SYSTEM.PORTOUT(03CEH, SYSTEM.VAL(INTEGER, 1003H))*)
		END;
		SYSTEM.PORTOUT(03CEH, 205H);	(* AL = Gaphics mode; AH = Read-Mode = 0/Write-Mode = 2 (bits 0,1) *)
		SYSTEM.PORTOUT(03C4H, 0F02H);	(* AL = Plane select; AH = Bitplanemask; DX = Sequencer *)
		addr := ((Height - Y - 1) * width3) MOD 10000H;
		INC(addr, 0A0000H);
		start := addr + X DIV 8; end := addr + (X + W) DIV 8;
		lm := imask[X MOD 8]; rm := mask[(X + W) MOD 8];
		IF start = end THEN
			ReplConst1(CHR(col), H, start, rm, lm)
		ELSE
			ReplConst2(CHR(col), H, start, end, rm, lm)
		END;
	END ReplConst;
	
	PROCEDURE FillPattern1(col: CHAR; pat: Pattern; pX, pY, X, Y, W, H, mode: LONGINT);
	VAR leftmask, rightmask, flag, color, help3: CHAR;  topleft, help, help1, help2: LONGINT;
	CODE {SYSTEM.i386}
		MOV	EAX, mode[EBP]	; get mode and set local AH
		CMP	AX, 0
		JNE	Inv4
		MOV	AH, 0
		JMP	setGC4
Inv4:
		CMP	AX, 2
		JNE	Paint4
		MOV	AH, 18H
		JMP	setGC4
Paint4:
		MOV	AH, 10H	; with wrong mode =>
;		; automatically paint mode
; Set graphic-controller-registers
		
setGC4:
		MOV	DX, 03CEH	; Graphic-Controller
		MOV	AL, 3	; AL = Data/Rotate / AH = Modus
		OUT	DX, AX
		MOV	AX, 0005H	; AL = Read-Mode = 0
;		; Write-Mode = 0 (bits 0, 1)
		OUT	DX, AX	; Set
; Get params x, y
getxy4:
		MOVSX EBX, height
		DEC EBX	; MOV	EBX, hgt[EBP]
		SUB	EBX, Y[EBP]	; (0, 0) in bottom left corner
		MOV	EAX, Y[EBP]
		MOV	Y[EBP], EBX	; y:= height -1 - y
		XOR	EDX, EDX
		SUB	EAX, pY[EBP]
		MOV	ECX, pat[EBP]
		MOVSX	ECX, BYTE 1[ECX]
		IDIV	EAX,ECX
		MOV	help2[EBP], EDX
		MOV	EBX, X[EBP]	; EBX := x
		MOV	ECX, EBX
		MOV	EDX, EBX
		MOV	ESI, EBX
		SHR	EBX, 3	; EBX := X DIV 8
		ADD	EDX, W[EBP]	; EDX := x + w
		DEC	EDX
		SHR	EDX, 3	; EDX := (x + w-1) DIV 8
		AND	ECX, 7	; ECX := x mod 8
		ADD	ESI, W[EBP]
		DEC	ESI
		AND	ESI, 7	; ESI := (x+w-1) MOD 8
		LEA EDI, imask	; MOV	EDI, imsk[EBP]
		MOV	AL, [EDI][ECX]
;		MOV	AL, imask[ECX]
		MOV	leftmask[EBP], AL
		INC	ESI	; *$*
		LEA EDI, mask	; MOV	EDI, msk[EBP]
		MOV	AL, [EDI][ESI]	
;		MOV	AL, mask[ESI]
		MOV	rightmask[EBP], AL
		
		MOV	EDI, width3	; w3[EBP]
		IMUL	EDI, Y[EBP]
		AND EDI, 0FFFFH
		ADD	EDI,0A0000H
		ADD	EDI, EBX	; EDI := START-Adr
		SUB	EDX, EBX	; Diff in bytes
		MOV	help[EBP], EDX
		MOV	help1[EBP], EDI
		MOV	EBX, H[EBP]
		IMUL	EBX, width3	; w3[EBP]
		SUB	EDI, EBX
		MOV	topleft[EBP], EDI
		MOV	EDI, help1[EBP]
		MOV	ESI, pat[EBP]	; get addr of pat
		MOV	EAX, X[EBP]	; EAX := x
		XOR	EDX, EDX
		MOVSX	EBX, BYTE [ESI]
		IDIV	EAX,EBX
		MOV	help3[EBP], DL	;help3 := x MOD p.w
		MOV	DX, 03CEH
		MOV	AH, leftmask[EBP]
		MOV	AL, 8
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AH, col[EBP]
		MOV	AL, 2
		OUT	DX, AX
		
		MOV	EBX, help2[EBP]
		MOV	flag[EBP], 0
		MOV	EDX, help[EBP]
		CMP	EDX, 0	; in one byte ?
		JE	onebyte
		CMP	BYTE [ESI], 16	; width = 16 ?
		JNE	RP32
RP16:
		CMP	mode[EBP], 0	; replacemode ?
		JE	R16
		CMP	mode[EBP], 1	; paintmode ?
		JE	P16left
IP16left:
		MOV	AX, 2[ESI][EBX*2]	; invert/paint p.w = 16
		CMP	help3[EBP], 8
		JGE	label
		ROR	AX, 8
label:
		MOV	CL, BYTE pX[EBP]
		ROL	AX, CL
		XOR	EDX, EDX
		PUSH EBX
		LEA EBX, rev	; MOV EBX, reverse[EBP]
		MOV	DL, AL
		MOV	AL, [EBX][EDX] 
;		MOV	AL, rev[EDX] 
		MOV	DL, AH
		MOV	AH, [EBX][EDX] 
;		MOV	AH, rev[EDX]
		POP EBX
		MOV	CH, [EDI]	; latch
		MOV	[EDI], AH
		ROL	AX, 8
		MOV	EDX, 1
		CMP	EDX, help[EBP]
		JE	IP16right
		MOV	help2[EBP], EAX
		MOV	DX, 03CEH
		MOV	AX, 0FF08H
		OUT	DX, AX
		MOV	EAX, help2[EBP]
		MOV	EDX, 1
IP16mid:
		MOV	CH, [EDI][EDX]	; latch
		MOV	[EDI][EDX], AH
		ROL	AX, 8
		INC	EDX
		CMP	EDX, help[EBP]
		JL	IP16mid
IP16right:
		MOV	help1[EBP], EDX
		MOV	help2[EBP], EAX
		MOV	DX, 03CEH
		MOV	AH, rightmask[EBP]
		MOV	AL, 8
		OUT	DX, AX
		MOV	EAX, help2[EBP]
		MOV	EDX, help1[EBP]
		MOV	CH, [EDI][EDX]
		MOV	[EDI][EDX], AH
		SUB	EDI, width3	; w3[EBP]
		CMP	EDI, topleft[EBP]
		JLE	resetgrafRP
		MOV	DX, 03CEH
		MOV	AH, leftmask[EBP]	; prepare rightmask again
		MOV	AL, 8
		OUT	DX, AX
		XOR	EDX, EDX
		INC	EBX
		CMP	BL, 1[ESI]	; height of pattern reached?
		JNE	IP16left
		XOR	EBX, EBX	; yes, then reset counter
		JMP	IP16left
		
P16left:
		MOV	AX, 2[ESI][EBX*2]	; invert/paint p.w = 16
		CMP	help3[EBP], 8
		JGE	plabel
		ROR	AX, 8
plabel:
		MOV	CL, BYTE pX[EBP]
		ROL	AX, CL
		XOR	EDX, EDX
		MOV	DL, AL
		PUSH EBX
		LEA EBX, rev	; MOV EBX, reverse[EBP]
		MOV	AL, [EBX][EDX] 
;		MOV	AL, rev[EDX] 
		MOV	DL, AH
		MOV	AH, [EBX][EDX] 
;		MOV	AH, rev[EDX]
		POP EBX
		MOV	CH, [EDI]	; latch
		
		PUSH	EDX
		PUSH	EAX
		MOV	DX, 03C4H
		MOV	AX, 0F02H	; set all planes
		OUT	DX, AX	; set color/sequencer planemap
		MOV	AH, 8	; set mode to AND
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		
		POP	EAX
		NOT	AH	; negate AH
		MOV	[EDI], AH	; clear pattern
		NOT	AH	; negate AH
		PUSH	EAX
		
		MOV	AH, 10H	; set mode to OR
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		MOV	AH, col[EBP]	; get color and set bitplanes
		MOV	AL, 2
		MOV	DX, 03C4H
		OUT	DX, AX
		POP	EAX
		POP	EDX
		
		MOV	[EDI], AH
		ROL	AX, 8
		MOV	EDX, 1
		CMP	EDX, help[EBP]
		JE	P16right
		MOV	help2[EBP], EAX
		MOV	DX, 03CEH
		MOV	AX, 0FF08H
		OUT	DX, AX
		MOV	EAX, help2[EBP]
		MOV	EDX, 1
P16mid:
		MOV	CH, [EDI][EDX]	; latch
		
		PUSH	EDX
		PUSH	EAX
		MOV	DX, 03C4H
		MOV	AX, 0F02H	; set all planes
		OUT	DX, AX	; set color/sequencer planemap
		MOV	AH, 8	; set mode to AND
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		
		POP	EAX
		POP	EDX
		NOT	AH	; negate AH
		MOV	[EDI][EDX], AH	; clear pattern
		NOT	AH	; negate AH
		PUSH	EDX
		PUSH	EAX
		
		MOV	AH, 10H	; set mode to OR
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		MOV	AH, col[EBP]	; get color and set bitplanes
		MOV	AL, 2
		MOV	DX, 03C4H
		OUT	DX, AX
		POP	EAX
		POP	EDX
		
		MOV	[EDI][EDX], AH
		ROL	AX, 8
		INC	EDX
		CMP	EDX, help[EBP]
		JL	P16mid
P16right:
		MOV	help1[EBP], EDX
		MOV	help2[EBP], EAX
		MOV	DX, 03CEH
		MOV	AH, rightmask[EBP]
		MOV	AL, 8
		OUT	DX, AX
		MOV	EAX, help2[EBP]
		MOV	EDX, help1[EBP]
		MOV	CH, [EDI][EDX]
		
		PUSH	EDX
		PUSH	EAX
		MOV	DX, 03C4H
		MOV	AX, 0F02H	; set all planes
		OUT	DX, AX	; set color/sequencer planemap
		MOV	AH, 8	; set mode to AND
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		
		POP	EAX
		POP	EDX
		NOT	AH	; negate AH
		MOV	[EDI][EDX], AH	; clear pattern
		NOT	AH	; negate AH
		PUSH	EDX
		PUSH	EAX
		
		MOV	AH, 10H	; set mode to OR
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		MOV	AH, col[EBP]	; get color and set bitplanes
		MOV	AL, 2
		MOV	DX, 03C4H
		OUT	DX, AX
		POP	EAX
		POP	EDX
		
		MOV	[EDI][EDX], AH
		SUB	EDI, width3	; w3[EBP]
		CMP	EDI, topleft[EBP]
		JLE	resetgrafRP
		MOV	DX, 03CEH
		MOV	AH, leftmask[EBP]	; prepare rightmask again
		MOV	AL, 8
		OUT	DX, AX
		XOR	EDX, EDX
		INC	EBX
		CMP	BL, 1[ESI]	; height of pattern reached?
		JNE	P16left
		XOR	EBX, EBX	; yes, then reset counter
		JMP	P16left
		
R16:
		MOV	AH, col[EBP]
		MOV	color[EBP], AH
R16left:
		MOV	AX, 2[ESI][EBX*2]	; replace p.w = 16
		CMP	help3[EBP], 8
		JGE	label1
		ROR	AX, 8
label1:
		MOV	CL, BYTE pX[EBP]
		ROL	AX, CL
		XOR	DX, DX
		MOV	DL, AL
		PUSH EBX
		LEA EBX, rev	; MOV EBX, reverse[EBP]
		MOV	AL, [EBX][EDX] 
;		MOV	AL, rev[EDX]
		MOV	DL, AH
;		MOV	AH, rev[EDX]
		MOV	AH, [EBX][EDX] 
		POP EBX
		MOV	help2[EBP], EAX
		MOV	DX, 03C4H
		MOV	AX, 0F02H
		OUT	DX, AX
		MOV	CH, [EDI]	; latch
		MOV	BYTE [EDI], 0
		MOV	AH, color[EBP]
		MOV	AL, 2
		OUT	DX, AX	; set color
		MOV	EAX, help2[EBP]
		MOV	[EDI], AH
		ROL	AX, 8
		MOV	EDX, 1
		CMP	EDX, help[EBP]
		JE	R16right
		MOV	help2[EBP], EAX
		MOV	DX, 03CEH
		MOV	AX, 0FF08H
		OUT	DX, AX
		MOV	EDX, 1
		MOV	EAX, help2[EBP]
R16mid:
		MOV	help1[EBP], EDX
		MOV	help2[EBP], EAX
		MOV	DX, 03C4H
		MOV	AX, 0F02H
		OUT	DX, AX
		XCHG	help1[EBP], EDX
		MOV	BYTE [EDI][EDX], 0
		XCHG	help1[EBP], EDX
		MOV	AH, color[EBP]
		MOV	AL, 2
		OUT	DX, AX	; set color
		XCHG	help1[EBP], EDX
		XCHG	help2[EBP], EAX
		MOV	[EDI][EDX], AH
		ROL	AX, 8
		INC	EDX
		CMP	EDX, help[EBP]
		JL	R16mid
R16right:
		MOV	help1[EBP], EDX
		MOV	help2[EBP], EAX
		MOV	DX, 03CEH
		MOV	AH, rightmask[EBP]
		MOV	AL, 8
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AX, 0F02H
		OUT	DX, AX
		XCHG	help1[EBP], EDX
		MOV	CH, [EDI][EDX]	; latch
		MOV	BYTE [EDI][EDX], 0
		XCHG	help1[EBP], EDX
		MOV	AH, color[EBP]
		MOV	AL, 2
		OUT	DX, AX	; set color
		MOV	EAX, help2[EBP]
		MOV	EDX, help1[EBP]
		MOV	[EDI][EDX], AH
		SUB	EDI, width3	; w3[EBP]
		CMP	EDI, topleft[EBP]
		JLE	resetgrafRP
		MOV	DX, 03CEH
		MOV	AH, leftmask[EBP]	; prepare rightmask again
		MOV	AL, 8
		OUT	DX, AX
		XOR	EDX, EDX
		INC	EBX
		CMP	BL, 1[ESI]	; height of pattern reached?
		JNE	R16left
		XOR	EBX, EBX	; yes, then reset counter
		JMP	R16left
onebyte:
		CMP	BYTE [ESI], 16	; width = 16 ?
		SETE	flag[EBP]	; flag = 1 if p.w=16
		CMP	mode[EBP], 0	; replace ?
		JE	onebyteR
		CMP	mode[EBP], 1	; paint ?
		JE	onebyteP
IPonebyte:
		CMP	flag[EBP], 1
		JNE	p32
		MOV	AX, 2[ESI][EBX*2]	; p.w = 16
		CMP	help3[EBP], 8
		JGE	label2
		ROR	AX, 8
label2:
		MOV	CL, BYTE pX[EBP]
		ROL	AX, CL
		JMP	down
p32:
		MOV	EAX, 2[ESI][EBX*4]	; p.w = 32
		CMP	help3[EBP], 24
		JL	labela
		ROR	EAX, 24
		JMP	labelc
labela:
		CMP	help3[EBP], 16	
		JL	labelb
		ROR	EAX, 16
		JMP	labelc
labelb:
		CMP	help3[EBP], 8 
		JL	labelc
		ROR	EAX, 8
labelc:
		MOV	CL, BYTE pX[EBP]
		ROL	EAX, CL
down:
		XOR	DX, DX
		MOV	DL, AL
		PUSH EBX
		LEA EBX, rev	; MOV EBX, reverse[EBP]
		MOV	DL, [EBX][EDX] 
;		MOV	DL, rev[EDX]
		POP EBX
		AND	AL, rightmask[EBP]
		MOV	CH, [EDI]	; latch
		MOV	[EDI], AL
		SUB	EDI, width3	; w3[EBP]
		CMP	EDI, topleft[EBP]
		JLE	resetgrafRP
		INC	EBX
		CMP	BL, 1[ESI]
		JNE	IPonebyte
		XOR	EBX, EBX
		JMP	IPonebyte
		
onebyteP:
		CMP	flag[EBP], 1
		JNE	pp32
		MOV	AX, 2[ESI][EBX*2]	; p.w = 16
		CMP	help3[EBP], 8
		JGE	plabel2
		ROR	AX, 8
plabel2:
		MOV	CL, BYTE pX[EBP]
		ROL	AX, CL
		JMP	pdown
pp32:
		MOV	EAX, 2[ESI][EBX*4]	; p.w = 32
		CMP	help3[EBP], 24
		JL	plabela
		ROR	EAX, 24
		JMP	plabelc
plabela:
		CMP	help3[EBP], 16	
		JL	plabelb
		ROR	EAX, 16
		JMP	plabelc
plabelb:
		CMP	help3[EBP], 8 
		JL	plabelc
		ROR	EAX, 8
plabelc:
		MOV	CL, BYTE pX[EBP]
		ROL	EAX, CL
pdown:
		XOR	DX, DX
		MOV	DL, AL
		PUSH EBX
		LEA EBX, rev	; MOV EBX, reverse[EBP]
		MOV	DL, [EBX][EDX] 
;		MOV	DL, rev[EDX]
		POP EBX
		AND	AL, rightmask[EBP]
		MOV	CH, [EDI]	; latch
		
		PUSH	EDX
		PUSH	EAX
		MOV	DX, 03C4H
		MOV	AX, 0F02H	; set all planes
		OUT	DX, AX	; set color/sequencer planemap
		MOV	AH, 8	; set mode to AND
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		
		POP	EAX
		NOT	AL	; negate AL
		MOV	[EDI], AL	; clear pattern
		NOT	AL	; negate AL
		PUSH	EAX
		
		MOV	AH, 10H	; set mode to OR
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		MOV	AH, col[EBP]	; get color and set bitplanes
		MOV	AL, 2
		MOV	DX, 03C4H
		OUT	DX, AX
		POP	EAX
		POP	EDX
		
		MOV	[EDI], AL
		SUB	EDI, width3	; w3[EBP]
		CMP	EDI, topleft[EBP]
		JLE	resetgrafRP
		INC	EBX
		CMP	BL, 1[ESI]
		JNE	onebyteP
		XOR	EBX, EBX
		JMP	onebyteP
		
onebyteR:
		MOV	AH, col[EBP]	; replace in 1 byte
		MOV	color[EBP], AH
Ronebyte:
		CMP	flag[EBP], 1
		JNE	p32r
		MOV	AX, 2[ESI][EBX*2]	; p.w = 16
		CMP	help3[EBP], 8
		JGE	label3
		ROR	AX, 8
label3:
		MOV	CL, BYTE pX[EBP]
		ROL	AX, CL
		JMP	downr
p32r:
		MOV	EAX, 2[ESI][EBX*4]	; p.w = 32
		CMP	help3[EBP], 24
		JL	labelc1
		ROR	EAX, 24
		JMP	labelc1
labela1:
		CMP	help3[EBP], 16	
		JL	labelb1
		ROR	EAX, 16
		JMP	labelc1
labelb1:
		CMP	help3[EBP], 8 
		JL	labelc1
		ROR	EAX, 8
labelc1:
		MOV	CL, BYTE pX[EBP]
		ROL	EAX, CL
downr:
		XOR	EDX, EDX
		MOV	DL, AL
		PUSH EBX
		LEA EBX, rev	; MOV EBX, reverse[EBP]
		MOV	AL, [EBX][EDX] 
;		MOV	AL, rev[EDX]
		POP EBX
		MOV	help1[EBP], EAX
		MOV	AH, leftmask[EBP]
		AND	AH, rightmask[EBP]
		MOV	DX, 03CEH
		MOV	AL, 8
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AX, 0F02H
		OUT	DX, AX
		MOV	CH, [EDI]	; latch
		MOV	BYTE [EDI], 0
		MOV	AH, color[EBP]
		MOV	AL, 2
		OUT	DX, AX	; set color
		MOV	EAX, help1[EBP]
		MOV	[EDI], AL
		SUB	EDI, width3	; w3[EBP]
		CMP	EDI, topleft[EBP]
		JLE	resetgrafRP
		INC	EBX
		CMP	BL, 1[ESI]
		JNE	Ronebyte
		XOR	EBX, EBX
		JMP	Ronebyte
RP32:
		CMP	BYTE [ESI], 32	; p.w = 32 ?
		JNE	endRP	; only p.w = 16 OR 32 allowed
		CMP	mode[EBP], 0
		JE	R32
		CMP	mode[EBP], 1
		JE	P32left
		
IP32left:
		MOV	EAX, 2[ESI][EBX*4]	;invert/paint p.w = 32
		CMP	help3[EBP], 24
		JL	labela2
		ROR	EAX, 24
		JMP	labelc2
labela2:
		CMP	help3[EBP], 16	
		JL	labelb2
		ROR	EAX, 16
		JMP	labelc2
labelb2:
		CMP	help3[EBP], 8 
		JL	labelc2
		ROR	EAX, 8
labelc2:
		MOV	CL, BYTE pX[EBP]
		ROL	EAX, CL
		XOR	EDX, EDX
		PUSH	ECX
		MOV	CX, 4
iloop:
		MOV	DL, AL
		PUSH EBX
		LEA EBX, rev	; MOV EBX, reverse[EBP]
		MOV	AL, [EBX][EDX]
;		MOV	AL, rev[EDX]
		POP EBX
		ROR	EAX, 8
		LOOP	iloop
		POP	ECX
		MOV	CH, [EDI]	; latch
		MOV	[EDI], AL
		ROR	EAX, 8
		MOV	EDX, 1
		CMP	EDX, help[EBP]
		JE	IP32right
		MOV	help2[EBP], EAX
		MOV	DX, 03CEH
		MOV	AX, 0FF08H
		OUT	DX, AX
		MOV	EAX, help2[EBP]
		MOV	EDX, 1
IP32mid:
		MOV	CH, [EDI][EDX]	; latch
		MOV	[EDI][EDX], AL
		ROR	EAX, 8
		INC	EDX
		CMP	EDX, help[EBP]
		JL	IP32mid
IP32right:
		MOV	help2[EBP], EAX
		MOV	help1[EBP], EDX
		MOV	DX, 03CEH
		MOV	AH, rightmask[EBP]
		MOV	AL, 8
		OUT	DX, AX
		MOV	EAX, help2[EBP]
		MOV	EDX, help1[EBP]
		MOV	CH, [EDI][EDX]
		MOV	[EDI][EDX], AL
		SUB	EDI, width3	; w3[EBP]
		CMP	EDI, topleft[EBP]
		JLE	resetgrafRP
		MOV	DX, 03CEH
		MOV	AH, leftmask[EBP]	; prepare leftmask again
		MOV	AL, 8
		OUT	DX, AX
		XOR	EDX, EDX
		INC	EBX
		CMP	BL, 1[ESI]	; height of pattern reached?
		JNE	IP32left
		XOR	EBX, EBX	; yes, then reset counter
		JMP	IP32left
		
P32left:
		MOV	EAX, 2[ESI][EBX*4]	;invert/paint p.w = 32
		CMP	help3[EBP], 24
		JL	plabela2
		ROR	EAX, 24
		JMP	plabelc2
plabela2:
		CMP	help3[EBP], 16	
		JL	plabelb2
		ROR	EAX, 16
		JMP	plabelc2
plabelb2:
		CMP	help3[EBP], 8 
		JL	plabelc2
		ROR	EAX, 8
plabelc2:
		MOV	CL, BYTE pX[EBP]
		ROL	EAX, CL
		XOR	EDX, EDX
		PUSH	ECX
		MOV	CX, 4
piloop:
		MOV	DL, AL
		PUSH EBX
		LEA EBX, rev	; MOV EBX, reverse[EBP]
		MOV	AL, [EBX][EDX] 
;		MOV	AL, rev[EDX]
		POP EBX
		ROR	EAX, 8
		LOOP	piloop
		POP	ECX
		MOV	CH, [EDI]	; latch
		
		PUSH	EDX
		PUSH	EAX
		MOV	DX, 03C4H
		MOV	AX, 0F02H	; set all planes
		OUT	DX, AX	; set color/sequencer planemap
		MOV	AH, 8	; set mode to AND
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		
		POP	EAX
		NOT	AL	; negate AL
		MOV	[EDI], AL	; clear pattern
		NOT	AL	; negate AL
		PUSH	EAX
		
		MOV	AH, 10H	; set mode to OR
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		MOV	AH, col[EBP]	; get color and set bitplanes
		MOV	AL, 2
		MOV	DX, 03C4H
		OUT	DX, AX
		POP	EAX
		POP	EDX
		
		MOV	[EDI], AL
		ROR	EAX, 8
		MOV	EDX, 1
		CMP	EDX, help[EBP]
		JE	P32right
		MOV	help2[EBP], EAX
		MOV	DX, 03CEH
		MOV	AX, 0FF08H
		OUT	DX, AX
		MOV	EAX, help2[EBP]
		MOV	EDX, 1
P32mid:
		MOV	CH, [EDI][EDX]	; latch
		
		PUSH	EDX
		PUSH	EAX
		MOV	DX, 03C4H
		MOV	AX, 0F02H	; set all planes
		OUT	DX, AX	; set color/sequencer planemap
		MOV	AH, 8	; set mode to AND
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		
		POP	EAX
		POP	EDX
		NOT	AL	; negate AL
		MOV	[EDI][EDX], AL	; clear pattern
		NOT	AL	; negate AL
		PUSH	EDX
		PUSH	EAX
		
		MOV	AH, 10H	; set mode to OR
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		MOV	AH, col[EBP]	; get color and set bitplanes
		MOV	AL, 2
		MOV	DX, 03C4H
		OUT	DX, AX
		POP	EAX
		POP	EDX
		
		MOV	[EDI][EDX], AL
		ROR	EAX, 8
		INC	EDX
		CMP	EDX, help[EBP]
		JL	P32mid
P32right:
		MOV	help2[EBP], EAX
		MOV	help1[EBP], EDX
		MOV	DX, 03CEH
		MOV	AH, rightmask[EBP]
		MOV	AL, 8
		OUT	DX, AX
		MOV	EAX, help2[EBP]
		MOV	EDX, help1[EBP]
		MOV	CH, [EDI][EDX]
		
		PUSH	EDX
		PUSH	EAX
		MOV	DX, 03C4H
		MOV	AX, 0F02H	; set all planes
		OUT	DX, AX	; set color/sequencer planemap
		MOV	AH, 8	; set mode to AND
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		
		POP	EAX
		POP	EDX
		NOT	AL	; negate AL
		MOV	[EDI][EDX], AL	; clear pattern
		NOT	AL	; negate AL
		PUSH	EDX
		PUSH	EAX
		
		MOV	AH, 10H	; set mode to OR
		MOV	AL, 3
		MOV	DX, 03CEH
		OUT	DX, AX
		MOV	AH, col[EBP]	; get color and set bitplanes
		MOV	AL, 2
		MOV	DX, 03C4H
		OUT	DX, AX
		POP	EAX
		POP	EDX
		
		MOV	[EDI][EDX], AL
		SUB	EDI, width3	; w3[EBP]
		CMP	EDI, topleft[EBP]
		JLE	resetgrafRP
		MOV	DX, 03CEH
		MOV	AH, leftmask[EBP]	; prepare leftmask again
		MOV	AL, 8
		OUT	DX, AX
		XOR	EDX, EDX
		INC	EBX
		CMP	BL, 1[ESI]	; height of pattern reached?
		JNE	IP32left
		XOR	EBX, EBX	; yes, then reset counter
		JMP	P32left
		
R32:
		MOV	AH, col[EBP]
		MOV	color[EBP], AH
R32left:
		MOV	EAX, 2[ESI][EBX*4]	; replace p.w = 32
		CMP	help3[EBP], 24
		JL	labela3
		ROR	EAX, 24
		JMP	labelc3
labela3:
		CMP	help3[EBP], 16	
		JL	labelb3
		ROR	EAX, 16
		JMP	labelc3
labelb3:
		CMP	help3[EBP], 8 
		JL	labelc3
		ROR	EAX, 8
labelc3:
		MOV	CL, BYTE pX[EBP]
		ROL	EAX, CL
		XOR	EDX, EDX
		PUSH	ECX
		MOV	CX, 4
i2loop:
		MOV	DL, AL
		PUSH EBX
		LEA EBX, rev	; MOV EBX, reverse[EBP]
		MOV	AL, [EBX][EDX] 
;		MOV	AL, rev[EDX]
		POP EBX
		ROR	EAX, 8
		LOOP	i2loop
		POP	ECX
		MOV	help2[EBP], EAX
		MOV	DX, 03C4H
		MOV	AX, 0F02H
		OUT	DX, AX
		MOV	CH, [EDI]	; latch
		MOV	BYTE [EDI], 0
		MOV	AH, color[EBP]
		MOV	AL, 2
		OUT	DX, AX	; set color
		MOV	EAX, help2[EBP]
		MOV	[EDI], AL
		ROR	EAX, 8
		MOV	EDX, 1
		CMP	EDX, help[EBP]
		JE	R32right
		MOV	help2[EBP], EAX
		MOV	DX, 03CEH
		MOV	AX, 0FF08H
		OUT	DX, AX
		MOV	EDX, 1
		MOV	EAX, help2[EBP]
R32mid:
		MOV	help1[EBP], EDX
		MOV	help2[EBP], EAX
		MOV	DX, 03C4H
		MOV	AX, 0F02H
		OUT	DX, AX
		XCHG	help1[EBP], EDX
		MOV	BYTE [EDI][EDX], 0
		XCHG	help1[EBP], EDX
		MOV	AH, color[EBP]
		MOV	AL, 2
		OUT	DX, AX	; set color
		XCHG	help1[EBP], EDX
		XCHG	help2[EBP], EAX
		MOV	[EDI][EDX], AL
		ROR	EAX, 8
		INC	EDX
		CMP	EDX, help[EBP]
		JL	R32mid
R32right:
		MOV	help2[EBP], EAX
		MOV	help1[EBP], EDX
		MOV	DX, 03CEH
		MOV	AH, rightmask[EBP]
		MOV	AL, 8
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AX, 0F02H
		OUT	DX, AX
		XCHG	help1[EBP], EDX
		MOV	CH, [EDI][EDX]	; latch
		MOV	BYTE [EDI][EDX], 0
		XCHG	help1[EBP], EDX
		MOV	AH, color[EBP]
		MOV	AL, 2
		OUT	DX, AX	; set color
		MOV	EAX, help2[EBP]
		MOV	EDX, help1[EBP]
		MOV	[EDI][EDX], AL
		SUB	EDI, width3	; w3[EBP]
		CMP	EDI, topleft[EBP]
		JLE	resetgrafRP
		MOV	DX, 03CEH
		MOV	AH, leftmask[EBP]	; prepare leftmask again
		MOV	AL, 8
		OUT	DX, AX
		XOR	EDX, EDX
		INC	EBX
		CMP	BL, 1[ESI]	; height of pattern reached?
		JNE	R32left
		XOR	EBX, EBX	; yes, then reset counter
		JMP	R32left
		JMP	endRP
resetgrafRP:
		MOV	DX, 03CEH
		MOV	AX, 0FF08H	; default bit mask
		OUT	DX, AX
		MOV	AX, 0005	; default mode-reg
		OUT	DX, AX
		MOV	AX, 0003	; default function
		OUT	DX, AX
		MOV	DX, 03C4H
		MOV	AX, 0F02H	; default map mask
		OUT	DX, AX
endRP:
	END FillPattern1;
	
	PROCEDURE FillPattern*(col: Color; pat: Pattern; px, py, x, y, w, h, mode: LONGINT);
	VAR pw: SHORTINT; right, top: INTEGER;
	BEGIN 
		SYSTEM.GET(pat, pw);
		IF (pw # 16) & (pw # 32) THEN RETURN END;
		top := SHORT(y + h); right := SHORT(x + w); 
		IF x < clipx THEN x := clipx END;
		IF y < clipy THEN y := clipy END;
		IF  clipright < right THEN right :=  clipright END;
		IF cliptop < top THEN top := cliptop END;
		IF (w <= 0) OR (h <= 0) OR (x < 0) OR (y < 0) THEN RETURN END;
		FillPattern1(CHR(col), pat, px, py, x, y, w, h, mode)
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
	VAR BitmapWth, locW, locH, SourceAdr, DestAdr, AreaHeight: LONGINT;
	CODE {SYSTEM.i386}
		MOVSX EAX, Width
		SHR EAX,3
		MOV locW[EBP], EAX	; locW := Width DIV 8
		MOVSX EAX, Height
		DEC EAX
		MOV locH[EBP], EAX	; locH := Height-1
		CLI
		MOV ESI, adr[EBP]		; address of bitmap descriptor
		MOV EDI, 12[ESI]
		MOV EAX, 8[ESI]
		MOV BitmapWth[EBP], EAX
		MOV ECX, dy[EBP]
		IMUL EAX,ECX
		MOV EBX, dx[EBP]
		ADD EAX, EBX
		ADD EAX, EDI		; source address
		MOV SourceAdr[EBP], EAX
		MOV ESI, EAX		; esi = source index register
		MOV EAX, locW[EBP] 
		MOV EBX, locH[EBP] 
		SUB EBX, sy[EBP]
		IMUL EAX,EBX 
		MOV EBX, sx[EBP]
		SHR EBX,3
		ADD EAX, EBX
		AND EAX, 0FFFFH
		ADD EAX, 0A0000H		; destination address
		MOV DestAdr[EBP], EAX
		MOV EDI, EAX		; edi = destination index register
		MOV DX, 03C4H	; AX = Default map mask; DX = Sequencer
		MOV AX, 0F02H
		OUT DX, AX
		MOV DX, 03CEH
		MOV AL, 3
		MOV BX, WORD mode[EBP]
		CMP BX, 1
		JE DispPMode
		JG DispIMode
DispRMode:
		MOV AH,00
		JMP DispSetMode
DispPMode:
		MOV AH, 10H
		JMP DispSetMode
DispIMode:
		MOV AH, 18H
DispSetMode:
		OUT DX, AX	; set rotate and function select
		MOV AX, 0205H
		OUT DX, AX		  ; set writemode 2, readmode 0
		XOR AX, AX
		OUT DX, AX	; disable set/reset
		MOV CL, BYTE sx[EBP]
		AND CL, 7		; ?DX MOD 8
		MOV AX, 8008H	
		SHR AH,CL		  ; prepare bitmask
		MOV DestAdr[EBP], EDI
		MOV ECX, h[EBP]
		IMUL ECX, BitmapWth[EBP]
		ADD ECX, ESI
		MOV EBX, w[EBP]
		MOV AreaHeight[EBP], EBX
DispRowLoop:
		JE DispEnd
		OUT DX, AX		; set bitmask register
		MOV SourceAdr[EBP], ESI
DispColLoop:
		CMP ESI, ECX
		JGE DispColEnd
		MOV BL, [EDI]
		MOV BL, [ESI]		; get PEL from bitmap
		MOV [EDI], BL		; write PEL to VGA
		ADD ESI, BitmapWth[EBP]
		SUB EDI, locW[EBP]
		JMP DispColLoop
DispColEnd:
		MOV ESI, SourceAdr[EBP]
		INC ESI
		INC ECX
		MOV EDI, DestAdr[EBP]
		ROR AH,1
		JNB NextCol
		INC EDI	
		MOV DestAdr[EBP], EDI
NextCol:
		DEC AreaHeight[EBP]		  	; next row
		JMP DispRowLoop
DispEnd:
		MOV AL, 3		; restore invert mode
		MOV AH, 18H
		OUT DX, AX
		MOV AX, 0FF08H		; enable all latches
		OUT DX, AX
		MOV AX, 05H		; restore read/write mode 0
		OUT DX, AX
		STI
	END DisplayBlock;

	PROCEDURE TransferFormat*(x: LONGINT): LONGINT;	(** non-portable *)
	BEGIN
		RETURN unknown
	END TransferFormat;

	PROCEDURE TransferBlock*(VAR buf: ARRAY OF CHAR;  ofs, stride, x, y, w, h, mode: LONGINT);	(** non-portable *)
	BEGIN
		HALT(99)
	END TransferBlock;
	
	PROCEDURE SetBorder;
	VAR ch: CHAR;
	BEGIN
		SYSTEM.PORTIN(3DAH, ch);
		SYSTEM.PORTOUT(3C0H, 11X);
		SYSTEM.PORTOUT(3C0H, 0FFX);
		SYSTEM.PORTOUT(3C0H, 020X)
	END SetBorder;
	
	PROCEDURE Init;
	VAR s: ARRAY 10 OF CHAR;
	BEGIN
		Kernel.GetConfig("Color", s);
		IF s = "0" THEN depth := 1 ELSE depth := 4 END
	END Init;
	
	PROCEDURE InitRev;
	VAR i, j, x: LONGINT;
	BEGIN
		FOR i := 0 TO 255 DO
			x := 0;
			FOR j := 0 TO 7 DO
				x := ASH(x, 1);
				IF ODD(ASH(i, -j)) THEN INC(x) END
			END;
			rev[i] := CHR(x)
		END
	END InitRev;
	
BEGIN
	Init;
	Width := 640; 
	Height := 480; 
	Left:= 0; ColLeft:= 0; Bottom:= 0; UBottom:= -330; 
	pattern := NIL;
	width := Width;
	height := Height;
	clipx := 0; clipy := UBottom; clipright := width; cliptop := height;
	width3 := width DIV 8;
	mask[0] := 0X; mask[1] := 80X; mask[2] := 0C0X; mask[3] := 0E0X; mask[4] := 0F0X; 
	mask[5] := 0F8X; mask[6] := 0FCX; mask[7] := 0FEX; mask[8] := 0FFX;
	imask[0] := 0FFX; imask[1] := 7FX; imask[2] := 3FX; imask[3] := 1FX; imask[4] := 0FX; 
	imask[5] := 7X; imask[6] := 3X; imask[7] := 1X; imask[8] := 0X;
	InitRev;
	CreatePatterns;  SetBorder;
	Unit := 10000
END Display.

Compiler.Compile VGA.Display.Mod\X ~
