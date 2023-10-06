(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE Display;	(* pjm *)

(* Native Oberon display module based on Displays. *)

(**
 Module Display provides the display drawing primitives and the base type of the visual objects, called Frames.
*)

IMPORT SYSTEM, AosDisplays := Displays, Kernel, Modules, Objects;

CONST
	BG* = 0; FG* = 15; (** Background, foreground colors. *)
	
	(** Drawing operation modes. *)
	replace* = 0;	(** replace destination. *)
	paint* = 1;	(** paint over destination.  *)
	invert* = 2;	(** invert destination. *)
	
	(** Message ids. *)
	remove* = 0; suspend* = 1; restore* = 2; newprinter* = 3; (** ControlMsg id. *)
	reduce* = 0; extend* = 1; move* = 2; (** ModifyMsg id. *)
	display* = 0; state* = 1; (** ModifyMsg mode. *)
	screen* = 0; printer* = 1; (** DisplayMsg device *)
	full* = 0; area* = 1; contents* = 2; (** DisplayMsg id. *)
	get* = 0; set* = 1; reset* = 2; (** SelectMsg id. *)
	drop* = 0; integrate* = 1; (** ConsumeMsg id. *)
	
	(** TransferFormat types. *)
	unknown* = 0; index8* = 8; color555* = 16; color565* = 17; color664* = 18; color888* = 24; color8888* = 32;

TYPE
	Color* = LONGINT;
	
	Pattern* = LONGINT;
	PatternPtr = POINTER TO RECORD
		buf: ARRAY 8192 OF CHAR	(* w = buf[0], h = buf[1], pixmap = buf[2..] *)
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
	clipX1, clipY1, clipX2, clipY2: LONGINT;	(* bottom left corner & top right corner, in Oberon coordinates *)
	pattern: List;
	
	buf: POINTER TO ARRAY OF CHAR;	(* for DisplayBlock *)
	
	disp: AosDisplays.Display;
	height: LONGINT;

(** Change color palette entry. 0 <= col, red, green, blue < 256. *)
PROCEDURE SetColor*(col: Color; red, green, blue: LONGINT);
BEGIN
	palette[col MOD 256] := ASH(ASH(red, 8) + green, 8) + blue
END SetColor;

(** Retrieve color palette entry or color components. 0 <= red, green, blue < 256. *)
PROCEDURE GetColor*(col: Color; VAR red, green, blue: INTEGER);
BEGIN
	IF col >= 0 THEN col := palette[col MOD 256] END;
	red := SHORT(ASH(col, -16) MOD 256);
	green := SHORT(ASH(col, -8) MOD 256);
	blue := SHORT(col MOD 256)
END GetColor;

(** Return color with specified components. 0 <= red, green, blue < 256. *)
PROCEDURE RGB*(red, green, blue: LONGINT): Color;
BEGIN
	RETURN MIN(LONGINT) + ASH(red, 16) + ASH(green, 8) + blue
END RGB;

(** Returns the number of bits per pixel for the given x coordinate. Typical values are 1, 4, 8 (maximum 8). *)
PROCEDURE Depth*(x: LONGINT): INTEGER;
BEGIN
	RETURN 8
END Depth;

(** Returns if truecolor values are supported in the interface. *)
PROCEDURE TrueColor*(x: LONGINT): BOOLEAN;
BEGIN
	RETURN TRUE
END TrueColor;

(** Get the current clip rectangle. *)
PROCEDURE GetClip*(VAR x, y, w, h: INTEGER);
BEGIN
	x := SHORT(clipX1); y := SHORT(clipY1);
	w := SHORT(clipX2-clipX1+1); h := SHORT(clipY2-clipY1+1)
END GetClip;

(** Set the new clipping rectangle. *)
PROCEDURE SetClip*(x, y, w, h: LONGINT);
BEGIN
	clipX1 := x; clipY1 := y; clipX2 := clipX1+w-1;  clipY2 := clipY1+h-1
END SetClip;

(** Intersect with current clip rectangle resulting in a new clip rectangle. *)
PROCEDURE AdjustClip*(x, y, w, h: LONGINT);
VAR x2, y2: LONGINT;
BEGIN
	x2 := x + w - 1; y2 := y + h - 1;
	IF x > clipX1 THEN clipX1 := x END;
	IF y > clipY1 THEN clipY1 := y END;
	IF x2 < clipX2 THEN clipX2 := x2 END;
	IF y2 < clipY2 THEN clipY2 := y2 END
END AdjustClip;

(** Reset the current clipping rectangle to the whole display, including offscreen area. *)
PROCEDURE ResetClip*;
BEGIN
	clipX1 := 0; clipY1 := UBottom; clipX2 := disp.width-1; clipY2 := height-1
END ResetClip;

(** Copy source block SX, SY, W, H to destination DX, DY using operation mode. A block is given by its lower left corner X, Y and its dimension W, H. *)
PROCEDURE CopyBlock*(sx, sy, w, h, dx, dy, mode: LONGINT);
BEGIN
	disp.Copy(sx, height-sy-h, w, h, dx, height-dy-h)
END CopyBlock;

(* Place a dot of color col in operation mode at x, y. Effect equivalent to ReplConst with a block of size 1, 1. *)
PROCEDURE CopyPattern*(col: Color;  pat: Pattern;  x, y, mode: LONGINT);
VAR pw, ph, stride: LONGINT; p: PatternPtr;
BEGIN
	p := SYSTEM.VAL(PatternPtr, pat); pw := ORD(p.buf[0]); ph := ORD(p.buf[1]);
	IF (x >= clipX1) & (y >= clipY1) & (x+pw-1 <= clipX2) & (y+ph-1 <= clipY2) THEN	(* completely visible *)
		IF col >= 0 THEN col := palette[col MOD 256] END;
		stride := (pw+7) DIV 8;
		CASE mode OF
			replace:
				disp.Mask(p.buf, 16 + (ph-1)*stride*8, -stride, col MOD 1000000H, 
					palette[BG], x, height-y-ph, pw, ph)
			|invert:
				disp.Mask(p.buf, 16 + (ph-1)*stride*8, -stride, col MOD 1000000H + AosDisplays.invert,
					AosDisplays.trans, x, height-y-ph, pw, ph)
			ELSE	(* paint *)
				disp.Mask(p.buf, 16 + (ph-1)*stride*8, -stride, col MOD 1000000H, 
					AosDisplays.trans, x, height-y-ph, pw, ph)
		END
	ELSIF (x+pw-1 >= clipX1) & (y+ph-1 >= clipY1) & (x <= clipX2) & (y <= clipY2) THEN	(* partially visible *)
		FillPattern(col, pat, x, y, x, y, pw, ph, mode)
	ELSE	(* not visible *)
		(* skip *)
	END
END CopyPattern;

(** Replicate pattern pat in color col into block x, y, w, h using operation mode, proceeding from left to right and from bottom to top, starting at lower left corner. The pattern origin is placed at px, py. *)
PROCEDURE FillPattern*(col: Color; pat: Pattern; px, py, x, y, w, h, mode: LONGINT);
VAR pw, ph, rdx, lpx, ldw, lsx, rdw, tdy, bpy, cdy, csy, cdh, cdx, csx, stride, fg, bg: LONGINT; p: PatternPtr;
(* See Displays.Display.Text for documentation *)
BEGIN
	rdx := x+w-1;  tdy := y+h-1;	(* (x,y) bottom left & (rdx,tdy) top right *)
	IF (x <= clipX2) & (y <= clipY2) & (rdx >= clipX1) & (tdy >= clipY1) THEN
		IF x < clipX1 THEN DEC(w, clipX1-x); x := clipX1 END;
		IF y < clipY1 THEN DEC(h, clipY1-y); y := clipY1 END;
		IF rdx > clipX2 THEN DEC(w, rdx-clipX2) END;
		IF tdy > clipY2 THEN DEC(h, tdy-clipY2) END;
		IF (w > 0) & (h > 0) THEN
			IF col >= 0 THEN col := palette[col MOD 256] END;
			CASE mode OF
				replace: fg := col MOD 1000000H; bg := palette[BG]
				|invert: fg := col MOD 1000000H + AosDisplays.invert; bg := AosDisplays.trans
				ELSE fg := col MOD 1000000H; bg := AosDisplays.trans
			END;
			p := SYSTEM.VAL(PatternPtr, pat); pw := ORD(p.buf[0]); ph := ORD(p.buf[1]);
			IF (pw > 0) & (ph > 0) THEN	(* rest of code copied from eos' TileBuffer *)
				stride := (pw+7) DIV 8;
				INC(px, (x - px) DIV pw * pw); INC(py, (y - py) DIV ph * ph);
				rdx := x + w; lpx := px + pw;
				ldw := lpx - x; lsx := pw - ldw;
				IF ldw > w THEN ldw := w END;
				rdw := (rdx - px) MOD pw;
				tdy := y + h; bpy := py + ph;
				cdy := y; csy := y - py;
				IF (py < y) & (bpy < tdy) THEN
					cdh := bpy - cdy;
					cdx := x; csx := lsx;
					IF px < x THEN
						disp.Mask(p.buf, 16 + (csy+cdh-1)*stride*8+lsx, -stride, fg, bg, cdx, height-cdh-cdy, ldw, cdh);
						csx := 0; cdx := lpx
					END;
					WHILE cdx + pw <= rdx DO
						disp.Mask(p.buf, 16 + (csy+cdh-1)*stride*8, -stride, fg, bg, cdx, height-cdh-cdy, pw, cdh);
						INC(cdx, pw)
					END;
					IF cdx < rdx THEN
						disp.Mask(p.buf, 16 + (csy+cdh-1)*stride*8+csx, -stride, fg, bg, cdx, height-cdh-cdy, rdw, cdh);
					END;
					csy := 0; cdy := bpy
				END;
				WHILE cdy + ph <= tdy DO
					cdx := x; csx := lsx;
					IF px < x THEN	(* draw left border *)
						disp.Mask(p.buf, 16 + (ph-1)*stride*8+lsx, -stride, fg, bg, cdx, height-ph-cdy, ldw, ph);
						csx := 0; cdx := lpx
					END;
					WHILE cdx + pw <= rdx DO
						disp.Mask(p.buf, 16 + (ph-1)*stride*8, -stride, fg, bg, cdx, height-ph-cdy, pw, ph);
						INC(cdx, pw)
					END;
					IF cdx < rdx THEN	(* draw right border *)
						disp.Mask(p.buf, 16 + (ph-1)*stride*8+csx, -stride, fg, bg, cdx, height-ph-cdy, rdw, ph);
					END;
					INC(cdy, ph)
				END;
				IF cdy < tdy THEN	(* draw top border *)
					cdh := tdy - cdy;
					cdx := x; csx := lsx;
					IF px < x THEN	(* draw top left corner *)
						disp.Mask(p.buf, 16 + (csy+cdh-1)*stride*8+lsx, -stride, fg, bg, cdx, height-cdh-cdy, ldw, cdh);
						csx := 0; cdx := lpx
					END;
					WHILE cdx + pw <= rdx DO
						disp.Mask(p.buf, 16 + (csy+cdh-1)*stride*8, -stride, fg, bg, cdx, height-cdh-cdy, pw, cdh);
						INC(cdx, pw)
					END;
					IF cdx < rdx THEN	(* draw top right corner *)
						disp.Mask(p.buf, 16 + (csy+cdh-1)*stride*8+csx, -stride, fg, bg, cdx, height-cdh-cdy, rdw, cdh);
					END
				END
			END
		END
	END
END FillPattern;

(** Like FillPattern, but the pattern origin is placed at 0, 0. *)
PROCEDURE ReplPattern*(col: Color; pat: Pattern; x, y, w, h, mode: LONGINT);
BEGIN
	FillPattern(col, pat, 0, 0, x, y, w, h, mode)
END ReplPattern;

(** Block fill in color col and operation mode. **)
PROCEDURE ReplConst*(col: Color; x, y, w, h, mode: LONGINT);
VAR rx, ty: LONGINT;
BEGIN
	rx := x+w-1;  ty := y+h-1;	(* (x,y) bottom left & (rx,ty) top right *)
	IF (x <= clipX2) & (y <= clipY2) & (rx >= clipX1) & (ty >= clipY1) THEN
		IF x < clipX1 THEN DEC(w, clipX1-x); x := clipX1 END;
		IF y < clipY1 THEN DEC(h, clipY1-y); y := clipY1 END;
		IF rx > clipX2 THEN DEC(w, rx-clipX2) END;
		IF ty > clipY2 THEN DEC(h, ty-clipY2) END;
		IF (w > 0) & (h > 0) THEN
			IF col >= 0 THEN col := palette[col MOD 256] END;
			IF mode = invert THEN
				disp.Fill(col MOD 1000000H + AosDisplays.invert, x, height-y-h, w, h)
			ELSE
				disp.Fill(col MOD 1000000H, x, height-y-h, w, h)
			END
		END
	END
END ReplConst;

(** Place a dot of color col in operation mode at x, y. Effect equivalent to ReplConst with a block of size 1, 1. *)
PROCEDURE Dot*(col: Color; x, y, mode: LONGINT);
BEGIN
	IF (x <= clipX2) & (y <= clipY2) & (x >= clipX1) & (y >= clipY1) THEN
		IF col >= 0 THEN col := palette[col MOD 256] END;
		IF mode = invert THEN
			disp.Dot(col MOD 1000000H + AosDisplays.invert, x, height-y-1)
		ELSE
			disp.Dot(col MOD 1000000H, x, height-y-1)
		END
	END
END Dot;

(** Returns the dimensions of a pattern. *)
PROCEDURE GetDim*(pat: Pattern; VAR w, h: INTEGER);
VAR ch: CHAR;
BEGIN
	SYSTEM.GET(pat, ch); w := ORD(ch);
	SYSTEM.GET(pat+1, ch); h := ORD(ch)
END GetDim;

(** Define a new pattern. *)
PROCEDURE NewPattern*(w, h: LONGINT; VAR image: ARRAY OF SET): Pattern;
VAR len, src, dest, i: LONGINT;  p: PatternPtr;  pl: List;
BEGIN
	len := (w+7) DIV 8;
	SYSTEM.NEW(p, 4+len*h); p.buf[0] := CHR(w); p.buf[1] := CHR(h);
	src := SYSTEM.ADR(image[0]); dest := SYSTEM.ADR(p.buf[2]);
	i := 0;
	WHILE i < h DO SYSTEM.MOVE(src, dest, len); INC(src, 4); INC(dest, len); INC(i) END;
	NEW(pl); pl.pat := p; pl.next := pattern;  pattern := pl;	(* put in list to avoid GC *)
	ASSERT(SYSTEM.ADR(p.buf[0]) = SYSTEM.VAL(LONGINT, p));
	RETURN SYSTEM.ADR(p.buf[0])
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
	CASE disp.format OF
		AosDisplays.index8: RETURN index8
		|AosDisplays.color565: RETURN color565
		|AosDisplays.color888: RETURN color888
		|AosDisplays.color8888: RETURN color8888
		ELSE RETURN unknown
	END
END TransferFormat;

(** Transfer a block of pixels in display format to (mode = set) or from (mode = get)  the display.  Pixels in the rectangular area are transferred from bottom to top and left to right.  The pixels are transferred to or from buf, starting at ofs, and with line increment stride, which may be < 0. *)
PROCEDURE TransferBlock*(VAR buf: ARRAY OF CHAR;  ofs, stride, x, y, w, h, mode: LONGINT);
VAR rdx, tdy: LONGINT;
BEGIN
	rdx := x+w-1;  tdy := y+h-1;	(* (x,y) bottom left & (rdx,tdy) top right *)
	IF (x <= clipX2) & (y <= clipY2) & (rdx >= clipX1) & (tdy >= clipY1) THEN
		IF x < clipX1 THEN DEC(w, clipX1-x); INC(ofs, (clipX1-x)*disp.format); x := clipX1 END;
		IF y < clipY1 THEN DEC(h, clipY1-y); INC(ofs, (clipY1-y)*stride); y := clipY1 END;
		IF rdx > clipX2 THEN DEC(w, rdx-clipX2) END;
		IF tdy > clipY2 THEN DEC(h, tdy-clipY2) END;
		IF (w > 0) & (h > 0) THEN
			disp.Transfer(buf, ofs + (h-1)*stride, -stride, x, height-h-y, w, h, mode)
		END
	END
END TransferBlock;

(** Change screen mode. *)
PROCEDURE SetMode*(x: LONGINT; s: SET);
BEGIN
	disp := AosDisplays.main; height := disp.height;
	Left := 0; ColLeft := 0; Bottom := 0;
	Unit := disp.unit;
	UBottom := SHORT(-disp.offscreen);
	Width := SHORT(disp.width); Height := SHORT(height);
	ResetClip
END SetMode;

(** Display a picture.  Used internally by Pictures module only. *)
PROCEDURE DisplayBlock*(adr, dx, dy, w, h, sx, sy, mode: LONGINT);
VAR pw, pd, src, dst, rdx, tdy, col: LONGINT; ch, prev, prevmap: CHAR;
BEGIN
	rdx := sx+w-1;  tdy := sy+h-1;	(* (sx,sy) bottom left & (rdx,tdy) top right *)
	IF (sx <= clipX2) & (sy <= clipY2) & (rdx >= clipX1) & (tdy >= clipY1) THEN
		IF sx < clipX1 THEN DEC(w, clipX1-sx); INC(dx, clipX1-sx); sx := clipX1 END;
		IF sy < clipY1 THEN DEC(h, clipY1-sy); INC(dy, clipY1-sy); sy := clipY1 END;
		IF rdx > clipX2 THEN DEC(w, rdx-clipX2) END;
		IF tdy > clipY2 THEN DEC(h, tdy-clipY2) END;
		IF (w > 0) & (h > 0) THEN
			pd := 0; SYSTEM.GET(adr+4, SYSTEM.VAL(INTEGER, pd));
			IF pd = 8 THEN
				SYSTEM.GET(adr+8, pw); SYSTEM.GET(adr+12, src);
				INC(src, (dy+h-1)*pw + dx);	(* top left corner *)
				IF w*h*disp.format+1 > LEN(buf^) THEN NEW(buf, w*h*disp.format+1) END;	(* +1 for *** below *)
				dst := SYSTEM.ADR(buf[0]);
				CASE disp.format OF
					AosDisplays.index8:
						prev := CHR(BG); prevmap := CHR(disp.ColorToIndex(palette[ORD(prev)]));
						FOR tdy := 0 TO h-1 DO
							FOR rdx := 0 TO w-1 DO
								SYSTEM.GET(src, ch); INC(src);
								IF ch # prev THEN 
									prev := ch; prevmap := CHR(disp.ColorToIndex(palette[ORD(prev)]))
								END;
								SYSTEM.PUT(dst, prevmap); INC(dst)
							END;
							INC(src, -w-pw)
						END
					|AosDisplays.color565:
						FOR tdy := 0 TO h-1 DO
							FOR rdx := 0 TO w-1 DO
								SYSTEM.GET(src, ch); INC(src); col := palette[ORD(ch)];
								SYSTEM.PUT(dst, SYSTEM.VAL(INTEGER, 
										SYSTEM.VAL(SET, ASH(col, 15-23)) * {11..15} +
										SYSTEM.VAL(SET, ASH(col, 10-15)) * {5..10} +
										SYSTEM.VAL(SET, ASH(col, 4-7)) * {0..4}));
								INC(dst, 2)
							END;
							INC(src, -w-pw)
						END
					|AosDisplays.color888, AosDisplays.color8888:
						col := disp.format;	(* size *)
						FOR tdy := 0 TO h-1 DO
							FOR rdx := 0 TO w-1 DO
								SYSTEM.GET(src, ch); INC(src);
								SYSTEM.PUT(dst, palette[ORD(ch)]);	(* *** possible 32-bit write to 24-bit value *)
								INC(dst, col)
							END;
							INC(src, -w-pw)
						END
				END;
				disp.Transfer(buf^, 0, w*disp.format, sx, height-h-sy, w, h, set)
			ELSE	(* depth not supported *)
				(* skip *)
			END
		END
	END
END DisplayBlock;

(** Return address of display located at x, or 0 if not supported. *)
PROCEDURE Map*(x: LONGINT): LONGINT;
BEGIN
	RETURN 0
END Map;

PROCEDURE LoadDriver;
VAR m: Modules.Module; c: Modules.Command; name: ARRAY 32 OF CHAR;
BEGIN
	Kernel.GetConfig("DDriver", name);
	IF name = "" THEN name := "DisplayPermedia2" END;
	m := Modules.ThisMod(name);
	IF m # NIL THEN
		c := Modules.ThisCommand(m, "Install");
		IF c # NIL THEN c() END
	ELSE
		c := NIL
	END;
	IF c = NIL THEN
		Kernel.WriteString("Display: "); Kernel.WriteString(Modules.resMsg); Kernel.WriteLn
	END
END LoadDriver;

BEGIN
	ASSERT((get = AosDisplays.get) & (set = AosDisplays.set));
	LoadDriver;
	NEW(buf, 8192);
	pattern := NIL;
	CreatePatterns;
	SetMode(0, {})
END Display.

Compiler.Compile Displays.Display.Mod\X ~

TestDisplay.Text TestTransferBlock.Mod TestSVGA.Mod
