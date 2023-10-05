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

(* Native Oberon trace display driver, pjm *)

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
			PatternPtr = POINTER TO RECORD w, h, pixmap: SHORTINT END;
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
			
		arrow*, star*, cross*, downArrow*, hook*: Pattern;
		grey0*, grey1*, grey2*, ticks*, solid*: Pattern;

		Broadcast*: MsgProc;

		Pat: List;

	PROCEDURE Map*(x: LONGINT): LONGINT;
	BEGIN
		Kernel.WriteString("Map(");  Kernel.WriteInt(x, 1);  Kernel.WriteString(") ");
		RETURN 0
	END Map;
	
	PROCEDURE AdjustClip*(x, y, w, h: LONGINT);
	BEGIN
		Kernel.WriteString("AdjustClip(");  Kernel.WriteInt(x, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(y, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(w, 1);
		Kernel.WriteChar(",");  Kernel.WriteInt(h, 1);  Kernel.WriteString(") ")
	END AdjustClip;

	PROCEDURE GetDim*(pat: Pattern; VAR w, h: INTEGER);
	VAR s: SHORTINT;
	BEGIN SYSTEM.GET(pat, s); w := s; SYSTEM.GET(pat+1, s); h := s;
		Kernel.WriteString("GetDim(");  Kernel.WriteHex(pat, 8);  Kernel.WriteString(") ")
	END GetDim;

	PROCEDURE ResetClip*;
	BEGIN 
		Kernel.WriteString("ResetClip ")
	END ResetClip;
	
	PROCEDURE SetClip*(x, y, w, h: LONGINT);
	BEGIN
		Kernel.WriteString("SetClip(");  Kernel.WriteInt(x, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(y, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(w, 1);  
		Kernel.WriteChar(",");  Kernel.WriteInt(h, 1);  Kernel.WriteString(") ")
	END SetClip;
	
	PROCEDURE GetClip*(VAR x, y, w, h: INTEGER);
	BEGIN
		Kernel.WriteString("GetClip ");
		x := 0;  y := 0;  w := Width;  h := Height
	END GetClip;
	
	PROCEDURE SetColor*(col: Color; red, green, blue: LONGINT);	(* 0 <= col, red, green, blue < 256 *)
	BEGIN
		Kernel.WriteString("SetColor(");  Kernel.WriteInt(col, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(red, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(green, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(blue, 1);  Kernel.WriteString(") ")
	END SetColor;

	PROCEDURE GetColor*(col: Color; VAR red, green, blue: INTEGER);
	BEGIN
		Kernel.WriteString("GetColor(");  Kernel.WriteInt(col, 1);  Kernel.WriteString(") ");
		IF col < 0 THEN
			red := SHORT(ASH(col, -16) MOD 256);
			green := SHORT(ASH(col, -8) MOD 256);
			blue := SHORT(col MOD 256)
		ELSE
			red := 0;  green := 0;  blue := 0
		END
	END GetColor;

	PROCEDURE RGB*(red, green, blue: LONGINT): Color;
	BEGIN
		Kernel.WriteString("RGB(");  Kernel.WriteInt(red, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(green, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(blue, 1);
		Kernel.WriteString(") ");
		RETURN MIN(LONGINT) + ASH(red, 16) + ASH(green, 8) + blue
	END RGB;

	PROCEDURE Dot*(col: Color; x, y, mode: LONGINT);
	BEGIN
		Kernel.WriteString("Dot(");  Kernel.WriteInt(col, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(x, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(y, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(mode, 1);  Kernel.WriteString(") ")
	END Dot;
	
	PROCEDURE CopyBlock*(sx, sy, w, h, dx, dy, mode: LONGINT);
	BEGIN 
		Kernel.WriteString("CopyBlock(");  Kernel.WriteInt(sx, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(sy, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(w, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(h, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(dx, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(dy, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(mode, 1);  Kernel.WriteString(") ")
	END CopyBlock;
	
	PROCEDURE SetMode*(x: LONGINT; s: SET);
	BEGIN
		Kernel.WriteString("SetMode(");  Kernel.WriteInt(x, 1);  Kernel.WriteChar(",");
		Kernel.WriteHex(SYSTEM.VAL(LONGINT, s), 8);  Kernel.WriteString(") ")
	END SetMode;
	
	PROCEDURE CopyPattern*(col: Color; pat: Pattern; x, y, mode: LONGINT);
	BEGIN
		Kernel.WriteString("CopyPattern(");  Kernel.WriteInt(col, 1);  Kernel.WriteChar(",");
		Kernel.WriteHex(pat, 8);  Kernel.WriteChar(",");  Kernel.WriteInt(x, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(y, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(mode, 1);  Kernel.WriteString(") ")
	END CopyPattern;
	
	PROCEDURE ReplConst*(col: Color; x, y, w, h, mode: LONGINT);	(* col not used if mode is invert *)
	BEGIN
		Kernel.WriteString("ReplConst(");  Kernel.WriteInt(col, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(x, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(y, 1);  
		Kernel.WriteChar(",");  Kernel.WriteInt(w, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(h, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(mode, 1);  
		Kernel.WriteString(") ")
	END ReplConst;
	
	PROCEDURE FillPattern*(col: Color; pat: Pattern; px, py, x, y, w, h, mode: LONGINT);
	BEGIN
		Kernel.WriteString("FillPattern(");  Kernel.WriteInt(col, 1);  Kernel.WriteChar(",");
		Kernel.WriteHex(pat, 8);  Kernel.WriteChar(",");  Kernel.WriteInt(px, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(py, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(x, 1);  
		Kernel.WriteChar(",");  Kernel.WriteInt(y, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(w, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(h, 1);  
		Kernel.WriteChar(",");  Kernel.WriteInt(mode, 1);  Kernel.WriteString(") ")
	END FillPattern;

	PROCEDURE ReplPattern*(col: Color; pat: Pattern; x, y, w, h, mode: LONGINT);
	BEGIN
		Kernel.WriteString("Repl/");
		FillPattern(col, pat, 0, 0, x, y, w, h, mode)
	END ReplPattern;
	
	PROCEDURE NewPattern*(w, h: LONGINT; VAR image: ARRAY OF SET): Pattern;
	VAR len, src, dest: LONGINT; i: INTEGER; p: PatternPtr; inter: SET;  pl: List;
	BEGIN
		Kernel.WriteString("NewPattern(");  Kernel.WriteInt(w, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(h, 1);  Kernel.WriteString(") ");
		len := (w+7) DIV 8;
		SYSTEM.NEW(p, 4+len*h); p.w := SHORT(SHORT(w)); p.h := SHORT(SHORT(h));
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
		solid := NewPattern(16, 2, image);
		
	END CreatePatterns;
	
	PROCEDURE Depth*(x: LONGINT): INTEGER;
	BEGIN
		Kernel.WriteString("Depth(");  Kernel.WriteInt(x, 1);  Kernel.WriteString(") ");
		RETURN 8
	END Depth; 
	
	PROCEDURE TrueColor*(x: LONGINT): BOOLEAN;
	BEGIN
		RETURN FALSE
	END TrueColor;

	PROCEDURE DisplayBlock*(adr, dx, dy, w, h, sx, sy, mode: LONGINT);
	BEGIN
		Kernel.WriteString("DisplayBlock(");  Kernel.WriteHex(adr, 8);  Kernel.WriteChar(",");
		Kernel.WriteInt(dx, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(dy, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(w, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(h, 1);  
		Kernel.WriteChar(",");  Kernel.WriteInt(sx, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(sy, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(mode, 1);  
		Kernel.WriteString(") ")
	END DisplayBlock;

	PROCEDURE TransferFormat*(x: LONGINT): LONGINT;
	BEGIN
		Kernel.WriteString("TransferFormat(");  Kernel.WriteInt(x, 1);  Kernel.WriteString(") ");
		RETURN unknown
	END TransferFormat;

	PROCEDURE TransferBlock*(VAR buf: ARRAY OF CHAR;  ofs, stride, x, y, w, h, mode: LONGINT);
	BEGIN
		Kernel.WriteString("TransferBlock(");  Kernel.WriteHex(SYSTEM.ADR(buf[0]), 8);  Kernel.WriteChar(",");
		Kernel.WriteInt(ofs, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(stride, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(x, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(y, 1);  
		Kernel.WriteChar(",");  Kernel.WriteInt(w, 1);  Kernel.WriteChar(",");
		Kernel.WriteInt(h, 1);  Kernel.WriteChar(",");  Kernel.WriteInt(mode, 1);  
		Kernel.WriteString(") ")
	END TransferBlock;
	
BEGIN
	Width := 640;
	Height := 480;
	Left:= 0;
	ColLeft:= 0;
	Bottom:= 0;
	UBottom:= -330; 
	CreatePatterns;
	Unit := 10000
END Display.
