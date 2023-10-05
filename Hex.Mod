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

MODULE Hex;	(** portable *) (* ps /   *)

(* still to do:
	- problems with empty files
	- selection?
	- allow deletion only in insert mode?
*)

IMPORT
	BIT, Reals, Input, Files, Fonts, Display, Display3, Printer, Printer3, Objects, Texts, ListRiders, Gadgets, Views, Effects,
	Oberon, Documents, Desktops, Strings;

CONST
	Version = 1;

	FlipCol = 2;
	bufSize = 512;	MaxPatLen = 32;

	BarW = 15; SliderH = 3; Gab = 5;
	Left = 4; Top = 4; Bot = 4;

	LArrow = 0C4X; RArrow = 0C3X; UArrow = 0C1X; DArrow = 0C2X;
	UPage = 0A2X; DPage = 0A3X; Home = 0A8X; End = 0A9X;
	TAB = 09X; CR = 0DX; BS = 07FX; DEL = 0A1X; INS = 0A0X;

	Menu = "Desktops.Copy[Copy] Hex.Search[Search] Desktops.StoreDoc[Store]";

TYPE
	Loc* = RECORD
		org*, pos*: LONGINT;	(** pos and line origin of location *)
		x*, y*, w*: INTEGER;	(** rel. coords *)
		x1, w1: INTEGER
	END;

	Frame* = POINTER TO FrameDesc;
	FrameDesc* = RECORD (Gadgets.FrameDesc)
		file: Texts.Text;
		org*: LONGINT;
		nibble, insert: BOOLEAN;
		car*: BOOLEAN;
		carloc*: Loc;
		pointloc: Loc
	END;

	CaretMsg* = RECORD (Display.FrameMsg)
		loc*: Loc
	END;

	ScrollMsg = RECORD (Display.FrameMsg)
		org: LONGINT;
		oldLines, newLines: LONGINT;
		dy: INTEGER
	END;

	StoreMsg = RECORD (Display.FrameMsg)
		text: Texts.Text;
	END;

VAR
	W: Texts.Writer;
	R: Texts.Reader;
	fnt: Fonts.Font;
	list: Gadgets.Frame;
	lastF: Frame;
	hBlock, tBlock: INTEGER;
	charW, lineH: INTEGER;
	ch: CHAR;
	Hex: ARRAY 16 OF CHAR;
	buf: ARRAY bufSize OF CHAR;
	sPat: ARRAY MaxPatLen OF CHAR;
	sDv: ARRAY MaxPatLen + 1 OF INTEGER;
	sLen: LONGINT;
	PrintertopY, PrinterbotY, PrinterleftX, PagenoX, HeaderY: INTEGER;

(** ------------ frame stuff ------------ *)
PROCEDURE P (x: LONGINT): INTEGER;
BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
END P;

PROCEDURE IsHexDigit (ch: CHAR): BOOLEAN;
BEGIN RETURN (ch >= "0") & (ch <="9") OR (CAP(ch) >= "A") & (CAP(ch) <= "F")
END IsHexDigit;

PROCEDURE HexToInt (ch: CHAR): LONGINT;
BEGIN
	IF ch <= "9" THEN  RETURN ORD(ch) - ORD("0")
	ELSE RETURN ORD(CAP(ch)) - ORD("A") + 10
	END
END HexToInt;

PROCEDURE ClipAgainst (VAR x, y, w, h: INTEGER; X, Y, W, H: INTEGER);
VAR r, t: INTEGER;
BEGIN
	r := x + w; t := y + h;
	IF x < X THEN x := X END;
	IF y < Y THEN y := Y END;
	IF r > X + W THEN r := X + W END;
	IF t > Y + H THEN t := Y + H END;
	w := r - x; h := t - y
END ClipAgainst;

PROCEDURE LinesVisible* (H: INTEGER): LONGINT;
BEGIN RETURN (H - Top - Bot - fnt.minY) DIV lineH
END LinesVisible;

PROCEDURE CalcPlace (x, y, w, h: INTEGER; VAR px, py: INTEGER);
VAR cx, cy, cw, ch: INTEGER;
BEGIN
	cx := 10; cy := 10; cw := Display.Width - 10; ch := Display.Height - 10;
	px := x; py := y - h DIV 2;
	IF px < cx THEN px := cx END;
	IF px + w >= cx + cw THEN px := cx + cw - 1 - w END;
	IF py < cy THEN py := cy END;
	IF py + h >= cy + ch THEN py := cy + ch - 1 - h END
END CalcPlace;

PROCEDURE LocateLine* (F: Frame; y, Y: INTEGER; VAR loc: Loc);
VAR pos, last: LONGINT; curY: INTEGER;
BEGIN
	pos := F.org; curY := y + F.H - Top - lineH;
	last := F.org + (LinesVisible(F.H) - 1)*16;
	IF last > F.file.len THEN last := ASH(ASH(F.file.len, -4), 4) END;
	WHILE (Y < curY) & (pos < last) DO
		DEC(curY, lineH); INC(pos, 16)
	END;
	loc.org := pos; loc.y := curY - (y + F.H - 1)
END LocateLine;

PROCEDURE LocateChar* (F: Frame; x, y, X, Y: INTEGER; VAR loc: Loc);
VAR pos, len: LONGINT; curX: INTEGER;
BEGIN
	LocateLine(F, y, Y, loc);
	len := F.file.len - loc.org - 1;
	IF len >= 15 THEN len := 15 ELSIF F.insert THEN INC(len) END;
	pos := 0;
	IF X > x + tBlock - 2*Gab THEN
		loc.w := charW - 1; loc.w1 := 2*charW - 1;
		curX := x + tBlock;
		WHILE (X > curX + charW) & (pos < len) DO INC(pos); INC(curX, charW) END;
		loc.x1 := hBlock + SHORT(pos * (2*charW + Gab)) + SHORT((pos DIV 4 + 1) * 5)
	ELSE
		loc.w := 2*charW - 1; loc.w1 := charW - 1;
		curX := x + hBlock + 5;
		WHILE (X > curX + 2*charW + Gab) & (pos < len) DO
			INC(pos);
			INC(curX, 2*charW + Gab);
			IF pos MOD 4 = 0 THEN INC(curX, 5) END
		END;
		loc.x1 := tBlock + SHORT(pos*charW)
	END;
	loc.pos := loc.org + pos; loc.x := curX - x
END LocateChar;

PROCEDURE LocatePos* (F: Frame; pos: LONGINT; hexBlock: BOOLEAN; VAR loc: Loc);
BEGIN
	loc.org := ASH(ASH(pos, -4), 4); loc.pos := pos;
	loc.y := -Top - SHORT(ASH(pos - F.org, -4) + 1) * lineH + 1;
	pos := pos - loc.org;
	IF hexBlock THEN
		loc.x := hBlock + SHORT(pos*(2*charW + Gab) + (pos DIV 4 + 1) * 5);
		loc.x1 := tBlock + SHORT(pos*charW);
		loc.w := 2*charW - 1; loc.w1 := charW - 1
	ELSE
		loc.x := tBlock + SHORT(pos*charW);
		loc.x1 := hBlock + SHORT(pos*(2*charW + Gab) + (pos DIV 4 + 1) * 5);
		loc.w := charW - 1; loc.w1 := 2*charW - 1
	END
END LocatePos;

PROCEDURE ScrollTo* (F: Frame; pos: LONGINT);
VAR S: ScrollMsg;
BEGIN
	IF pos >= F.file.len THEN pos := F.file.len -1 ELSIF pos < 0 THEN pos := 0 END;
	S.org := ASH(ASH(pos, -4), 4);
	S.newLines := ABS(S.org - F.org) DIV 16;
	S.oldLines := LinesVisible(F.H) - S.newLines;
	IF S.org > F.org THEN S.dy := SHORT(S.newLines*lineH)
	ELSE S.dy := -SHORT(S.newLines*lineH)
	END;
	S.F := F; Display.Broadcast(S)
END ScrollTo;

PROCEDURE RemoveCaret (F: Frame);
VAR C: CaretMsg;
BEGIN
	IF F.car THEN C.loc := F.carloc; C.F := F; Display.Broadcast(C) END;
	F.car := FALSE
END RemoveCaret;

PROCEDURE SetCaret (F: Frame; pos: LONGINT);
VAR C: CaretMsg; lines: LONGINT; hexBlock: BOOLEAN;
BEGIN
	hexBlock := F.carloc.x < tBlock;
	RemoveCaret(F);
	IF pos < 0 THEN pos := 0
	ELSIF pos >= F.file.len THEN
		IF (pos > F.file.len) OR ~F.insert THEN IF F.insert THEN pos := F.file.len ELSE pos := F.file.len - 1 END END
	END;
	lines := LinesVisible(F.H);
	IF pos < F.org THEN ScrollTo(F, pos)
	ELSIF pos >= F.org + lines*16 THEN ScrollTo(F, 16 + pos - lines*16)
	END;
	F.nibble := FALSE;
	LocatePos(F, pos, hexBlock, C.loc);
	C.F := F; Display.Broadcast(C);
	F.car := TRUE
END SetCaret;

PROCEDURE FlipCaret (F: Frame; Q: Display3.Mask; x, y: INTEGER; loc: Loc);
VAR Y: INTEGER;
BEGIN
	F.carloc := loc; Y :=  y + F.H - 1 + loc.y;
	IF loc.x < tBlock THEN
		IF F.insert & ~F.nibble THEN
			Oberon.RemoveMarks(x + loc.x, Y - 8, 16, 16);
			Display3.CopyPattern(Q, FlipCol, Display.hook, x + loc.x, Y - 8, Display.invert)
		ELSE
			Oberon.RemoveMarks(x + loc.x, Y, loc.w, lineH);
			Display3.ReplConst(Q, FlipCol, x + loc.x, Y, loc.w, lineH, Display.invert)
		END;
		Oberon.RemoveMarks(x + loc.x1, Y, loc.w1, 2);
		Display3.ReplConst(Q, FlipCol, x + loc.x1, Y, loc.w1, 2, Display.invert)
	ELSE
		Oberon.RemoveMarks(x + loc.x1, Y, loc.w1, 2);
		Display3.ReplConst(Q, FlipCol, x + loc.x1, Y, loc.w1, 2, Display.invert);
		IF F.insert THEN
			Oberon.RemoveMarks(x + loc.x, Y - 8, 16, 16);
			Display3.CopyPattern(Q, FlipCol, Display.hook, x + loc.x, Y - 8, Display.invert)
		ELSE
			Oberon.RemoveMarks(x + loc.x, Y, loc.w, lineH);
			Display3.ReplConst(Q, FlipCol, x + loc.x, Y, loc.w, lineH, Display.invert)
		END
	END
END FlipCaret;

PROCEDURE RestoreSlider (F: Frame; Q: Display3.Mask; x, y: INTEGER);
VAR Y: INTEGER;
BEGIN
	IF F.file.len > 0 THEN Y := SHORT(y + 1 + (F.file.len - F.org) * (F.H - 2 - SliderH) DIV F.file.len)
	ELSE Y := y + F.H - 1 - SliderH
	END;
	Display3.ReplConst(Q, Display3.textbackC, x + 1, y + 1, BarW-2, F.H - 2, Display.replace);
	Display3.ReplConst(Q, Display3.black, x + BarW - 1, y + 1, 1, F.H - 2, Display.replace);
	Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.textbackC,
										x + 2, Y, BarW - 6, SliderH, 1, Display.replace)
END RestoreSlider;

PROCEDURE UpdateArea (F: Frame; u, v, w, h, px, py: INTEGER; dlink: Objects.Object);
VAR D: Display.DisplayMsg;
BEGIN
	D.device := Display.screen; D.id := Display.area;
	D.x := px; D.y := py; D.F := F; D.dlink := dlink;
	D.u := u; D.v := v; D.w := w; D.h := h;
	D.res := -1;
	F.handle(F, D)
END UpdateArea;

PROCEDURE ScrollUpdate (F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER; VAR M: ScrollMsg);
VAR cx, cy, cw, ch, mx, my, mw, mh, Y, H: INTEGER;
BEGIN
	IF F.stamp # M.stamp THEN F.stamp := M.stamp; RemoveCaret(F); F.org := M.org END;

	Oberon.RemoveMarks(x, y, w, h);
	RestoreSlider(F, Q, x, y);
	IF (M.oldLines > 0) & Display3.Rectangular(Q, mx, my, mw, mh) THEN	(* copy as much as possible *)
		cw := w - BarW - 1; ch :=  SHORT(LinesVisible(F.H)*lineH); cx := x + BarW; cy := y + h - Top - ch;
		ClipAgainst(mx, my, mw, mh, Q.X, Q.Y, Q.W, Q.H); ClipAgainst(mx, my, mw, mh, cx, cy, cw, ch);
		IF M.dy < 0 THEN	(* up; new lines come on top *)
			ClipAgainst(cx, cy, cw, ch, cx, cy - M.dy, cw, ch + M.dy);	(* clip top *)
			ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip source area *)
			INC(cy, M.dy);
			ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip destination area *)
			Y := cy + ch; H := -M.dy
		ELSE	(* down; new lines come at bottom *)
			ClipAgainst(cx, cy, cw, ch, cx, cy, cw, ch - M.dy);	(* clip bottom *)
			ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip source area *)
			INC(cy, M.dy);
			ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip destination area *)
			Y := cy - M.dy; H := M.dy
		END;
		Display.CopyBlock(cx, cy - M.dy, cw, ch, cx, cy, Display.replace)
	ELSE	(* full update *)
		H := SHORT(LinesVisible(F.H)*lineH); Y := y + h - Top - H
	END;
	UpdateArea(F, BarW, Y - (y + h - 1), w - BarW, H, M.x, M.y, M.dlink)
END ScrollUpdate;

PROCEDURE DrawChar (Q: Display3.Mask; VAR X, Y: INTEGER; ch: CHAR);
VAR pat: Display.Pattern; x, y, dx, w, h: INTEGER;
BEGIN
	CASE ORD(ch) OF
		32..126, 128..149, 155: Fonts.GetChar(fnt, ch, dx, x, y, w, h, pat)
	ELSE Fonts.GetChar(fnt, ".", dx, x, y, w, h, pat)
	END;
	Display3.CopyPattern(Q, Display3.textC, pat, X+x, Y + y, Display.paint);
	INC(X, charW)
END DrawChar;

PROCEDURE DrawLine (Q: Display3.Mask; x, Y, w, h: INTEGER; pos: LONGINT);
VAR i: LONGINT; X, tX: INTEGER;
BEGIN
	Display3.ReplConst(Q, Display3.textbackC, x + BarW, Y + fnt.minY, w - BarW - 1, h, Display.replace);
	
	(* write pos *)
	X := BarW + x + Left;
	DrawChar(Q, X, Y, Hex[pos DIV 1048576 MOD 16]); DrawChar(Q, X, Y, Hex[pos DIV 65536 MOD 16]);
	DrawChar(Q, X, Y, Hex[pos DIV 4096 MOD 16]); DrawChar(Q, X, Y, Hex[pos DIV 256 MOD 16]);
	DrawChar(Q, X, Y, Hex[pos DIV 16 MOD 16]); DrawChar(Q, X, Y, Hex[pos MOD 16]);

	(* write data *)
	X := x + hBlock; tX := x + tBlock; i := 0; 
	WHILE ~R.eot & (i < 16) DO
		IF i MOD 4 = 0 THEN
			IF i > 0 THEN Display3.ReplConst(Q, 12, X, Y + fnt.minY, 1, lineH, Display.replace) END;
			INC(X, 5)
		END;
		DrawChar(Q, X, Y, Hex[ORD(ch) DIV 16]); DrawChar(Q, X, Y, Hex[ORD(ch) MOD 16]);
		DrawChar(Q, tX, Y, ch);
		INC(i); INC(X, Gab);
		Texts.Read(R, ch)
	END
END DrawLine;

(* ------------ msg handlers ------------ *)
PROCEDURE RestoreFrame (F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER);
VAR pos: LONGINT; Y: INTEGER;
BEGIN
	Display3.Rect3D(Q, Display3.topC, Display3.bottomC, x, y, w, h, 1, Display.replace);

	(* draw scrollbar *)
	RestoreSlider(F, Q, x, y);

	Display3.ReplConst(Q, Display3.textbackC, x + BarW, y + h - Top, w - BarW - 1, Top - 1, Display.replace);
	Y := y + h - Top - fnt.minY - lineH;
	pos := F.org;
	IF pos >= F.file.len THEN R.eot := TRUE
	ELSE Texts.OpenReader(R, F.file, pos); Texts.Read(R, ch)
	END;
	WHILE ~R.eot & (Y > y + Bot) DO
		DrawLine(Q, x, Y, w, lineH, pos);
		INC(pos, 16); DEC(Y,  lineH)
	END;
	INC(Y, fnt.minY + lineH);
	Display3.ReplConst(Q, Display3.textbackC, x + BarW, y + 1, w - BarW - 1, Y - y - 1, Display.replace);

	IF F.car THEN FlipCaret(F, Q, x, y, F.carloc) END;

	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreFrame;

PROCEDURE RestoreFrameArea (F: Frame; Q: Display3.Mask; x, y, w, h, U, V, W, H: INTEGER);
VAR pos, lines: LONGINT; Y, bot: INTEGER;
BEGIN
	Display3.Rect3D(Q, Display3.topC, Display3.bottomC, x, y, w, h, 1, Display.replace);

	(* draw scrollbar *)
	IF U < BarW THEN RestoreSlider(F, Q, x, y) END;

	IF U + W > BarW THEN
		IF -Top > V - 1 THEN
			Display3.ReplConst(Q, Display3.textbackC, x + BarW, y + h - Top, w - BarW - 1, Top - 1, Display.replace);
	
			(* bottom: y + h - 1 + V - (y + h - Top) *)
			lines := -LinesVisible(F.H);
			pos := (V - 1 + Top) DIV lineH; IF pos < lines THEN pos := lines END;
			bot := y + h - Top + SHORT(pos * lineH) - fnt.minY;

			(* top: y + h - 1 + V + H -1 - (y + h - Top) *)
			pos := (V + H - 2 + Top) DIV lineH; IF pos >= 0 THEN pos := -1 END;
			Y := y + h - Top + SHORT(pos * lineH) - fnt.minY;
			pos := F.org + ABS(pos + 1)*16;

			IF pos >= F.file.len THEN R.eot := TRUE
			ELSE Texts.OpenReader(R, F.file, pos); Texts.Read(R, ch)
			END;
			WHILE ~R.eot & (Y >= bot) DO
				DrawLine(Q, x, Y, w, lineH, pos);
				INC(pos, 16); DEC(Y,  lineH)
			END;
			INC(Y, fnt.minY + lineH);
			Display3.ReplConst(Q, Display3.textbackC, x + BarW, y + 1, w - BarW - 1, Y - y - 1, Display.replace);
	
			IF F.car THEN FlipCaret(F, Q, x, y, F.carloc) END
		ELSE
			Display3.ReplConst(Q, Display3.textbackC, x + BarW, y + 1, w - BarW, H - 2, Display.replace)
		END
	END;

	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreFrameArea;

PROCEDURE PrintFrame (F: Frame; M: Display.DisplayMsg);
VAR x, y, w, h: INTEGER; Q: Display3.Mask;
BEGIN
	x := M.x; y := M.y; w := P(F.W); h := P(F.H);
	Gadgets.MakePrinterMask(F, x, y, M.dlink, Q);
	Printer3.FilledRect3D(Q, Display3.bottomC, Display3.topC, Display3.textbackC, x, y, w, h, P(1), Display.replace);
END PrintFrame;

PROCEDURE TrackFrame (F: Frame; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
VAR Q, Q0: Display3.Mask; pos: LONGINT; keysum: SET; block: Views.Block; px, py, top: INTEGER; loc, oLoc: Loc;
		CM: Display.ControlMsg; D: Display.DisplayMsg;
BEGIN
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	top := y + h - 1;
	IF (M.X < x + BarW) & (M.keys # {}) THEN
		Oberon.RemoveMarks(x, y, BarW, h);
		IF M.keys = {1} THEN	(* absolute position *)
			keysum := M.keys;
			REPEAT
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
				keysum := keysum + M.keys;
				Input.Mouse(M.keys, M.X, M.Y)
			UNTIL M.keys = {};
			IF keysum = {1} THEN
				IF F.file.len = 0 THEN ScrollTo(F, 0)
				ELSE
					pos := (M.Y - y - 1 - SliderH DIV 2) * (-F.file.len) DIV (h - 2 - SliderH);
					ScrollTo(F, F.file.len + pos)
				END
			ELSIF keysum = {0, 1} THEN ScrollTo(F, 0)
			ELSIF keysum = {1, 2} THEN ScrollTo(F, F.file.len)
			END
		ELSE
			w := 6*charW;
			LocateLine(F, y, M.Y, loc); oLoc := loc;
			Oberon.RemoveMarks(x + BarW + Left, top + oLoc.y, w, 2);
			Display3.ReplConst(Q, FlipCol, x + BarW + Left, top + oLoc.y, w, 2, Display.invert);
			keysum := M.keys;
			REPEAT
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
				IF oLoc.org # loc.org THEN
					Oberon.RemoveMarks(x + BarW + Left, top + oLoc.y, w, 2);
					Display3.ReplConst(Q, FlipCol, x + BarW + Left, top + oLoc.y, w, 2, Display.invert);
					Oberon.RemoveMarks(x + BarW + Left, top + loc.y, w, 2);
					Display3.ReplConst(Q, FlipCol, x + BarW + Left, top + loc.y, w, 2, Display.invert);
					oLoc := loc
				END;
				Input.Mouse(M.keys, M.X, M.Y);
				keysum := keysum + M.keys;
				LocateLine(F, y, M.Y, loc)
			UNTIL M.keys = {};
			Oberon.RemoveMarks(x + BarW + Left, top + oLoc.y, w, 2);
			Display3.ReplConst(Q, FlipCol, x + BarW + Left, top + oLoc.y, w, 2, Display.invert);

			IF keysum = {0} THEN
				pos := ASH(ASH(oLoc.org - F.org, -4) - LinesVisible(F.H) + 1, 4);
				IF pos # 0 THEN ScrollTo(F, F.org + pos) END
			ELSIF (keysum = {2}) & (F.org # oLoc.org) THEN ScrollTo(F, oLoc.org)
			END
		END
	ELSIF M.keys = {2} THEN
		Oberon.Defocus;
		LocateChar(F, x, y, M.X, M.Y, loc); oLoc := loc;
		FlipCaret(F, Q, x, y, loc);
		keysum := M.keys;
		REPEAT
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
			IF oLoc.pos # loc.pos THEN
				FlipCaret(F, Q, x, y, oLoc);
				FlipCaret(F, Q, x, y, loc);
				oLoc := loc
			END;
			Input.Mouse(M.keys, M.X, M.Y);
			keysum := keysum + M.keys;
			LocateChar(F, x, y, M.X, M.Y, loc)
		UNTIL M.keys = {};
		FlipCaret(F, Q, x, y, loc); F.carloc := loc; SetCaret(F, loc.pos)
	ELSIF (M.keys = {1}) & (list # NIL) THEN
		Oberon.RemoveMarks(0, 0, Display.Width, Display.Height);
		LocateChar(F, x, y, M.X, M.Y, loc); F.pointloc := loc;
		Display3.ReplConst(Q, FlipCol, x+ loc.x, y + h - 1 + loc.y, loc.w, 2, Display.invert);
		Display3.ReplConst(Q, FlipCol, x+ loc.x1, y + h - 1 + loc.y, loc.w1, 2, Display.invert);
		CalcPlace(x + loc.x + loc.w, y + h - 1 + loc.y, list.W, list.H, px, py);
		Views.GetBlock(px, py, list.W, list.H, M.dlink, block);

		CM.id := Display.restore; CM.F := NIL; CM.x := 0; CM.y := 0; CM.res := -1; CM.dlink := NIL;
		list.handle(list, CM); list.mask := NIL;
		D.device := Display.screen; D.id := Display.full; D.F := list; D.res := -1; 
		D.x := px - list.X; D.y := py - list.Y; D.dlink := M.dlink;
		list.handle(list, D);

		lastF := F;
		Gadgets.MakeMask(list, px, py, M.dlink, Q0); 
		Input.Mouse(M.keys, M.X, M.Y); keysum := M.keys;
		WHILE (M.keys # {}) & (M.res < 0) DO
			M.x := px - list.X; M.y := py - list.Y; list.handle(list, M);
			Input.Mouse(M.keys, M.X, M.Y); keysum := keysum + M.keys; 
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y)
		END;
		lastF := NIL;

		Oberon.FadeCursor(Oberon.Mouse);
		Views.RestoreBlock(block);
		Display3.ReplConst(Q, FlipCol, x+ loc.x, y + h - 1 + loc.y, loc.w, 2, Display.invert);
		Display3.ReplConst(Q, FlipCol, x+ loc.x1, y + h - 1 + loc.y, loc.w1, 2, Display.invert)
	ELSE
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y)
	END;
	M.res := 0
END TrackFrame;

PROCEDURE Write (F: Frame; VAR M: Oberon.InputMsg);
VAR R: Texts.Reader; pos: LONGINT; C: CaretMsg; i, j, val: INTEGER; ch: CHAR; keys: SET;
BEGIN
	IF M.ch = UArrow THEN SetCaret(F, F.carloc.pos - 16)
	ELSIF M.ch = DArrow THEN SetCaret(F, F.carloc.pos + 16)
	ELSIF M.ch = LArrow THEN SetCaret(F, F.carloc.pos - 1)
	ELSIF M.ch = RArrow THEN SetCaret(F, F.carloc.pos + 1)
	ELSIF M.ch = Home THEN SetCaret(F, 0);
	ELSIF M.ch = End THEN SetCaret(F, F.file.len - 1)
	ELSIF M.ch = UPage THEN
		pos := F.org - (LinesVisible(F.H) - 1)*16;
		ScrollTo(F, pos); SetCaret(F, pos)
	ELSIF M.ch = DPage THEN
		pos := F.org + (LinesVisible(F.H) - 1)*16;
		ScrollTo(F, pos); SetCaret(F, pos)
	ELSIF M.ch = TAB THEN
		pos := F.carloc.pos; DEC(pos, pos MOD 4);
		Input.KeyState(keys);
		IF ~(Input.SHIFT IN keys) THEN SetCaret(F, pos + 4)
		ELSIF pos = F.carloc.pos THEN SetCaret(F, pos - 4)
		ELSE SetCaret(F, pos - pos MOD 4)
		END
	ELSIF M.ch = CR THEN
		pos := F.carloc.pos - F.carloc.org;
		C.loc := F.carloc; C.F := F; Display.Broadcast(C);	(* remove Caret *)
		i:= F.carloc.x; j := F.carloc.w;
		F.carloc.x := F.carloc.x1; F.carloc.w := F.carloc.w1;
		F.carloc.x1 := i; F.carloc.w1 := j;
		C.loc := F.carloc; C.F := F; Display.Broadcast(C)	(* draw caret *)
	ELSIF M.ch = BS THEN
		IF F.insert THEN
			pos := F.carloc.pos;
			IF pos > 0 THEN Texts.Delete(F.file, pos - 1, pos); SetCaret(F, pos - 1) END
		END
	ELSIF M.ch = DEL THEN
		IF F.insert THEN
			pos := F.carloc.pos;
			IF (pos < F.file.len - 1) OR F.insert & (pos < F.file.len) THEN
				Texts.Delete(F.file, pos, pos + 1); SetCaret(F, pos)
			END
		END
	ELSIF M.ch = INS THEN
		RemoveCaret(F); F.insert := ~F.insert; SetCaret(F, F.carloc.pos)
	ELSE
		pos := F.carloc.pos;
		IF F.carloc.x >= tBlock THEN
			val := ORD(M.ch);
			IF (val >= 32) & (val <= 126) OR (val >= 128) & (val <= 149) OR (val = 155) THEN
				Texts.Write(W, CHR(val));
				IF F.insert THEN Texts.Insert(F.file, pos, W.buf) ELSE Texts.Replace(F.file, pos, pos + 1, W.buf) END;
				SetCaret(F, pos + 1)
			END
		ELSE
			IF IsHexDigit(M.ch) THEN
				IF F.insert & ~F.nibble THEN ch := 0X
				ELSE Texts.OpenReader(R, F.file, pos); Texts.Read(R, ch)
				END;
				Texts.Write(W, CHR(HexToInt(M.ch) + ORD(ch) * 16));
				IF F.insert & ~F.nibble THEN
					F.nibble := TRUE; Texts.Insert(F.file, pos, W.buf)
				ELSE
					Texts.Replace(F.file, pos, pos + 1, W.buf);
					IF F.nibble THEN SetCaret(F, pos + 1) ELSE F.nibble := TRUE END
				END
			END
		END
	END;
	M.res := 0
END Write;

PROCEDURE Update (F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER; M: Texts.UpdateMsg);
VAR bLine, eLine, lastPos: LONGINT; Y, H: INTEGER;
BEGIN
	lastPos := F.org + LinesVisible(F.H)*16;
	IF lastPos > F.file.len THEN lastPos := F.file.len END;
	DEC(lastPos);
	IF M.beg < F.org + LinesVisible(F.H)*16 THEN	(* changes take effect in the visible area *)
		IF M.end - M.beg = M.len THEN	(* replace *)
			IF M.end > F.org THEN	(* changes take effect in the visible area *)
				bLine := M.beg DIV 16; IF bLine < F.org DIV 16 THEN bLine := F.org DIV 16 END;
				eLine := (M.beg + M.len - 1) DIV 16; IF eLine > lastPos DIV 16 THEN eLine := lastPos DIV 16 END; 
				Y := -Top - SHORT(eLine - F.org DIV 16 + 1)*lineH + 1;
				H := SHORT(eLine - bLine + 1)*lineH;
				UpdateArea(F, hBlock, Y, w - hBlock, H, M.x, M.y, M.dlink)
			END
		ELSIF M.end = M.beg THEN	(* insert *)
			bLine := M.beg DIV 16; IF bLine < F.org DIV 16 THEN bLine := F.org DIV 16 END;
			eLine := lastPos DIV 16; 
			Y := -Top - SHORT(eLine - F.org DIV 16 + 1)*lineH + 1;
			H := SHORT(eLine - bLine + 1)*lineH;
			UpdateArea(F, BarW, Y, w - BarW, H, M.x, M.y, M.dlink)
		ELSIF M.len = 0 THEN	(* delete *)
			bLine := M.beg DIV 16; IF bLine < F.org DIV 16 THEN bLine := F.org DIV 16 END;
			IF lastPos = F.file.len - 1 THEN eLine := (lastPos + M.end - M.beg) DIV 16
			ELSE eLine := lastPos DIV 16 
			END;
			Y := -Top - SHORT(eLine - F.org DIV 16 + 1)*lineH + 1;
			H := SHORT(eLine - bLine + 1)*lineH;
			UpdateArea(F, BarW, Y, w - BarW, H, M.x, M.y, M.dlink)
		END
	END;
	IF (M.beg = M.end) OR (M.len = 0) THEN	(* update scrollbar *)
		UpdateArea(F, 1, - h + 1, BarW-2, h - 2, M.x, M.y, M.dlink)
	END
END Update;

PROCEDURE Modify (F: Frame; VAR M: Display.ModifyMsg);
VAR x, y, w, h, Y, H: INTEGER; O: Display3.OverlapMsg;
BEGIN
	IF M.stamp # F.stamp THEN
		F.stamp := M.stamp; F.X := M.X; F.Y := M.Y; F.W := M.W; F.H := M.H;
		O.F := F; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL; F.handle(F, O)
	END;

	IF (M.mode = Display.display) & (F.W > 0) & (F.H > 0) THEN
		x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
		Oberon.RemoveMarks(x, y, w, h);
		IF (M.dX = 0) & (M.dY + M.dH = 0) THEN	(* top left corner stable *)
			Y := -h + 1;
			IF M.dH > 0 THEN
				H := h - SHORT(LinesVisible(h - M.dH)*lineH) - Top;
				UpdateArea(F, BarW, Y, w - BarW, H, M.x, M.y, M.dlink)
			ELSIF M.dH < 0 THEN
				H := h - SHORT(LinesVisible(h)*lineH) - Top;
				UpdateArea(F, BarW, Y, w - BarW, H, M.x, M.y, M.dlink)
			ELSE H := 0
			END;

			Y := Y + H; H := h - H;
			IF M.dW > 0 THEN UpdateArea(F, x + w - M.dW - 1, Y, M.dW + 1, H, M.x, M.y, M.dlink)
			ELSIF M.dW < 0 THEN UpdateArea(F, x + w - 1, Y, 1, H, M.x, M.y, M.dlink)
			END
		ELSE	(* full update *)
			UpdateArea(F, BarW, - h + 1, w - BarW, h, M.x, M.y, M.dlink)
		END;
		(* update slider *)
		UpdateArea(F, 0, - h + 1, BarW, h, M.x, M.y, M.dlink)
	END
END Modify;

PROCEDURE FrameAttr (F: Frame; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN
			M.class := Objects.String; COPY("Hex.NewFrame", M.s); M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		Gadgets.framehandle(F, M)
	ELSIF M.id = Objects.enum THEN
		Gadgets.framehandle(F, M)
	END
END FrameAttr;

PROCEDURE FrameFile (F: Frame; VAR M: Objects.FileMsg);
VAR ver: LONGINT;
BEGIN
	IF M.id = Objects.load THEN
		Gadgets.framehandle(F, M);
		Files.WriteNum(M.R, Version)
	ELSIF M.id = Objects.store THEN
		Gadgets.framehandle(F, M);
		Files.ReadNum(M.R, ver);
		IF ver >= 1 THEN

		END
	END
END FrameFile;

PROCEDURE CopyFrame* (VAR M: Objects.CopyMsg; from, to: Frame);
BEGIN
	to.org := from.org; to.file := from.file; to.car := FALSE;
	Gadgets.CopyFrame(M, from, to)
END CopyFrame;

PROCEDURE FrameHandler* (F: Objects.Object; VAR M: Objects.ObjMsg);
VAR F0: Frame; Q: Display3.Mask; x, y, w, h: INTEGER;
BEGIN
	WITH F: Frame DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN (* message addressed to box *)
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									RestoreFrame(F, Q, x, y, w, h)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									Display3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreFrameArea(F, Q, x, y, w, h, M.u, M.v, M.w, M.h)
								END
							ELSIF M.device = Display.printer THEN
								PrintFrame(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) THEN
								TrackFrame(F, x, y, w, h, M)
							ELSIF (M.id = Oberon.consume) & F.car THEN
								Write(F, M)
							ELSE
								Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Texts.UpdateMsg THEN
						WITH M: Texts.UpdateMsg DO
							IF M.text = F.file THEN
								Gadgets.MakeMask(F, x, y, M.dlink, Q);
								Update(F, Q, x, y, w, h, M)
							END
						END;
					ELSIF M IS CaretMsg THEN
						Gadgets.MakeMask(F, x, y, M.dlink, Q);
						FlipCaret(F, Q, x, y, M(CaretMsg).loc)
					ELSIF M IS ScrollMsg THEN
						Gadgets.MakeMask(F, x, y, M.dlink, Q);
						ScrollUpdate(F, Q, x, y, w, h, M(ScrollMsg))
					ELSIF M IS Display.ModifyMsg THEN Modify(F, M(Display.ModifyMsg))
					ELSIF M IS Display.ControlMsg THEN
						WITH M: Display.ControlMsg DO
							IF (M.id = Display.restore) & (F.org >= F.file.len) THEN
								F.org := ASH(ASH(F.file.len - 1, -4), 4);
								IF F.org < 0 THEN F.org := 0 END;
								RemoveCaret(F)
							END;
							Gadgets.framehandle(F, M)
						END
					ELSIF M IS Oberon.ControlMsg THEN
						WITH M: Oberon.ControlMsg DO
							IF M.id = Oberon.neutralize THEN RemoveCaret(F)
							ELSIF M.id  = Oberon.defocus THEN RemoveCaret(F)
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
		ELSIF M IS Objects.AttrMsg THEN FrameAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN FrameFile(F, M(Objects.FileMsg))
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink 
				ELSE F.stamp := M.stamp; NEW(F0); CopyFrame(M, F, F0); F.dlink := F0; M.obj := F0
				END
			END
		ELSE Gadgets.framehandle(F, M)
		END
	END
END FrameHandler;

PROCEDURE InitFrame* (F: Frame; file: Texts.Text);
BEGIN
	F.W := 200; F.H := 100; F.handle := FrameHandler;
	IF file = NIL THEN NEW(file); Texts.Open(file, "") END;
	F.file := file;
	F.org := 0;
	F.nibble := FALSE; F.insert := file.len = 0; F.car := FALSE
END InitFrame;

PROCEDURE NewFrame*;
VAR F: Frame;
BEGIN NEW(F); InitFrame(F, NIL); Objects.NewObj := F
END NewFrame;

(** ------------ document stuff ------------ *)
PROCEDURE LoadDoc (D: Documents.Document);
VAR main: Frame; F: Files.File; T: Texts.Text; R: Files.Rider; i: LONGINT;
BEGIN
	F := Files.Old(D.name);
	IF F = NIL THEN F := Files.New("") END;
	Files.Set(R, F, 0); Files.ReadBytes(R, buf, bufSize);
	WHILE ~R.eof DO
		i := 0;
		WHILE i < bufSize DO Texts.Write(W, buf[i]); INC(i) END;
		Files.ReadBytes(R, buf, bufSize);
	END;
	i := 0;
	WHILE i < bufSize - R.res DO Texts.Write(W, buf[i]); INC(i) END;
	NEW(T); Texts.Open(T, ""); Texts.Append(T, W.buf);
	NEW(main); InitFrame(main, T);
	Documents.Init(D, main)
END LoadDoc;

PROCEDURE StoreDoc (D: Documents.Document);
VAR main: Frame; rR: Texts.Reader; wR: Files.Rider; F: Files.File; i: INTEGER;
		new: ARRAY 128 OF CHAR; ch: CHAR; M: StoreMsg;
BEGIN
	main := D.dsc(Frame);
	Texts.WriteString(W, "Store "); Texts.Append(Oberon.Log, W.buf);
	IF D.name # "" THEN
		F := Files.New(D.name); IF F = NIL THEN HALT(99) END;

		COPY(D.name, new); i := 0; WHILE new[i] # 0X DO INC(i) END;
		new[i] := "."; new[i+1] := "B"; new[i+2] := "a"; new[i+3] := "k"; new[i+4] := 0X;
		Files.Rename(D.name, new, i);
		
		Texts.OpenReader(rR, main.file, 0); Files.Set(wR, F, 0);
		Texts.Read(rR, ch); i := 0;
		WHILE ~rR.eot DO
			buf[i] := ch; INC(i);
			IF i >= bufSize THEN Files.WriteBytes(wR, buf, i); i := 0 END;
			Texts.Read(rR, ch)
		END;
		IF i > 0 THEN Files.WriteBytes(wR, buf, i) END;
		Files.Register(F);

		Texts.Write(W, 22X); Texts.WriteString(W, D.name); Texts.Write(W, 22X);
		M.F := NIL; M.text := main.file; Display.Broadcast(M)
	ELSE Texts.WriteString(W, "[Untitled document]")
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END StoreDoc;

PROCEDURE ToggleMenu (set: BOOLEAN; dlink: Objects.Object);
VAR menu, f: Display.Frame; A: Objects.AttrMsg;
BEGIN
	menu := Desktops.CurMenu(dlink);
	IF menu # NIL THEN
		f := menu.dsc;
		WHILE f # NIL DO
			A.id := Objects.get; A.name := "Caption"; A.res := -1; A.s := ""; f.handle(f, A);
			IF (A.s = "Store") & set THEN
				A.id := Objects.set; A.name := "Caption"; A.res := -1; A.class := Objects.String; A.s := "Store !"; f.handle(f, A);
				Gadgets.Update(f);
				f := NIL
			ELSIF (A.s = "Store !") & ~set THEN
				A.id := Objects.set; A.name := "Caption"; A.res := -1; A.class := Objects.String; A.s := "Store"; f.handle(f, A);
				Gadgets.Update(f);
				f := NIL
			ELSE f := f.next
			END
		END
	END
END ToggleMenu;

PROCEDURE SetCheck (D: Documents.Document; text: Texts.Text; dlink: Objects.Object);
VAR F: Frame;
BEGIN
	F := D.dsc(Frame);
	IF (text = F.file) & ~(16 IN D.state) THEN
		INCL(D.state, 16);
		ToggleMenu(TRUE, dlink)
	END
END SetCheck;

PROCEDURE ClearCheck (D: Documents.Document; text: Texts.Text; dlink: Objects.Object);
VAR F: Frame;
BEGIN
	F := D.dsc(Frame);
	IF (text = F.file) & (16 IN D.state) THEN
		EXCL(D.state, 16);
		ToggleMenu(FALSE, dlink)
	END
END ClearCheck;

PROCEDURE PrintHeader(title: ARRAY OF CHAR; page: LONGINT);
	VAR str: ARRAY 8 OF CHAR;
BEGIN
	IF title # "" THEN
		Printer.String(PrinterleftX, HeaderY, title, fnt)
	END;
	Strings.IntToStr(page, str);
	Printer.String(PagenoX, HeaderY, str, fnt)
END PrintHeader;

PROCEDURE InitPagePosition();
BEGIN
	PrintertopY := Printer.FrameY + Printer.FrameH; PrinterbotY := Printer.FrameY; PrinterleftX := Printer.FrameX;
	HeaderY := PrintertopY-P(Fonts.Default.height); PrintertopY := HeaderY - P(2*Fonts.Default.height);
	PagenoX := SHORT(LONG(PrinterleftX) + LONG(Printer.FrameW) * 19 DIV 20)
END InitPagePosition;

PROCEDURE PrintLine(X, Y: INTEGER; pos: LONGINT);
	VAR
		str: ARRAY 8 OF CHAR;
		i: LONGINT;
		x,xt: INTEGER;
BEGIN
	str[0] := Hex[pos DIV 1048576 MOD 16];
	str[1] := Hex[pos DIV 65536 MOD 16];
	str[2] := Hex[pos DIV 4096 MOD 16];
	str[3] := Hex[pos DIV 256 MOD 16];
	str[4] := Hex[pos DIV 16 MOD 16];
	str[5] := Hex[pos MOD 16];
	str[6] := 0X;
	Printer.String(X, Y, str, fnt);
	x := X+P(hBlock-Left-BarW); xt := X+P(tBlock-Left-BarW);
	i := 0; 
	WHILE ~R.eot & (i < 16) DO
		IF i MOD 4 = 0 THEN
			IF i > 0 THEN
				Printer.UseColor(200, 200, 200);
				Printer.ReplConst(x, Y + P(fnt.minY), P(1), P(lineH));
				Printer.UseColor(0, 0, 0)
			END;
			x := x+P(5)
		END;
		str[0] := Hex[ORD(ch) DIV 16];
		str[1] := Hex[ORD(ch) MOD 16];
		str[2] := 0X;
		Printer.String(x, Y, str, fnt);
		x := x+P(2*charW+Gab);
		CASE ORD(ch) OF
			32..126, 128..149, 155: str[0] := ch;
			str[1] := 0X;
			Printer.String(xt, Y, str, fnt)
		ELSE
			Printer.UseColor(200, 200, 200);
			Printer.ReplConst(xt, Y, P(charW), P(1));
			Printer.UseColor(0, 0, 0)
		END;
		xt := xt+P(charW); 
		INC(i); Texts.Read(R, ch)
	END
END PrintLine;

PROCEDURE PrintDoc(D: Documents.Document);
	VAR
		pos, page: LONGINT;
		X, Y: INTEGER;
BEGIN
	InitPagePosition(); Printer.UseColor(0, 0, 0);
	X := PrinterleftX; page := 0;
	pos := 0; Texts.OpenReader(R, D.dsc(Frame).file, 0); Texts.Read(R, ch);
	WHILE ~R.eot DO
		PrintHeader(D.name, page);
		Y := PrintertopY;
		WHILE ~R.eot & ((Y-P(lineH)) > PrinterbotY) DO
			PrintLine(X, Y, pos);
			INC(pos, 16); DEC(Y, P(lineH))
		END;
		Printer.Page(1); INC(page)
	END
END PrintDoc;

PROCEDURE DocHandler (D: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH D: Documents.Document DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN M.class := Objects.String; M.s := "Hex.NewDoc"; M.res := 0
					ELSIF M.name = "Adaptive" THEN M.class := Objects.Bool; M.b := TRUE; M.res := 0
					ELSIF M.name = "Icon" THEN M.class := Objects.String; M.s := "Icons.Text"; M.res := 0
					ELSE Documents.Handler(D, M)
					END
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF M.id = Objects.get THEN
					IF (M.name = "SystemMenu") OR (M.name = "UserMenu") OR (M.name = "DeskMenu") THEN
						M.obj := Desktops.NewMenu(Menu); M.res := 0
					ELSE Documents.Handler(D, M)
					END
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Texts.UpdateMsg THEN
			WITH M: Texts.UpdateMsg DO
				SetCheck(D, M.text, M.dlink);
				Documents.Handler(D, M)
			END
		ELSIF M IS StoreMsg THEN
			WITH M: StoreMsg DO
				ClearCheck(D, M.text, M.dlink);
				Documents.Handler(D, M)
			END
		ELSIF M IS Display.DisplayMsg THEN
			WITH M: Display.DisplayMsg DO
				IF (M.device = Display.printer) & (M.id = Display.contents) & (D.dsc # NIL) THEN (* print *)
					PrintDoc(D)
				ELSE
				Documents.Handler(D, M)
				END
			END
		ELSE Documents.Handler(D, M)
		END
	END
END DocHandler;

PROCEDURE NewDoc*;
VAR D: Documents.Document;
BEGIN
	NEW(D);
	D.Load := LoadDoc; D.Store := StoreDoc; D.handle := DocHandler;
	D.W := 590; D.H := 200;
	Objects.NewObj := D
END NewDoc;

(** ------------ commands ------------ *)
PROCEDURE GetFrame (): Frame;
VAR D: Documents.Document;
BEGIN
	D := Desktops.CurDoc(Gadgets.context);
	IF (D = NIL) OR ~(D.dsc IS Frame) THEN D := Documents.MarkedDoc() END;
	IF (D # NIL) & (D.dsc IS Frame) THEN RETURN D.dsc(Frame)
	ELSE RETURN NIL
	END;
END GetFrame;

(** Opens the given file in a hex document.
	Usage: Hex.Open '^' | file
*)
PROCEDURE Open*;
VAR T: Texts.Text; time, beg, end: LONGINT; S: Texts.Scanner;

	PROCEDURE OpenThis (name: ARRAY OF CHAR);
	VAR D: Documents.Document;
	BEGIN
		NewDoc; D := Objects.NewObj(Documents.Document);
		COPY(S.s, D.name);
		D.Load(D);
		Desktops.ShowDoc(D)
	END OpenThis;

BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "^") THEN
		Oberon.GetSelection(T, beg, end, time);
		IF (T # NIL) & (time >= 0) THEN
			Texts.OpenScanner(S, T, beg); Texts.Scan(S);
			IF S.class IN {Texts.String, Texts.Name} THEN OpenThis(S.s) END
		END
	ELSIF S.class IN {Texts.String, Texts.Name} THEN OpenThis(S.s)
	END
END Open;

(** Used internaly to handle middle mouse click *)
PROCEDURE Interpret*;
VAR i, j, s: LONGINT; set: SET; S: Texts.Scanner;

	PROCEDURE ReadLInt (): LONGINT;
	VAR i: LONGINT;
	BEGIN
		i := BIT.LOR(0, ORD(ch)); Texts.Read(R, ch);
		i := BIT.LOR(i, ASH(ORD(ch), 8)); Texts.Read(R, ch);
		i := BIT.LOR(i, ASH(ORD(ch), 16)); Texts.Read(R, ch);
		RETURN BIT.LOR(i, ASH(ORD(ch), 24))
	END ReadLInt;

BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF (lastF # NIL) & (S.class IN {Texts.String, Texts.Name}) & (S.s[0] # "-") THEN
		Texts.OpenReader(R, lastF.file, lastF.pointloc.pos); Texts.Read(R, ch);
		Texts.WriteString(W, "pos ["); Texts.WriteHex(W, lastF.pointloc.pos); Texts.WriteString(W, "H]: ");
		IF S.s = "LONGINT (LSB)" THEN
			Texts.WriteInt(W, ReadLInt(), 0)
		ELSIF S.s = "INTEGER (LSB)" THEN
			i := BIT.LOR(0, ORD(ch)); Texts.Read(R, ch);
			i := ASH(ASH(BIT.LOR(i, ASH(ORD(ch), 8)), 16), -16);
			Texts.WriteInt(W, i, 0)
		ELSIF S.s = "SHORTINT" THEN
			Texts.WriteInt(W, ASH(ASH(ORD(ch), 24), -24), 0)
		ELSIF S.s = "LONGINT (MSB)" THEN
			i := BIT.LOR(0, ASH(ORD(ch),24)); Texts.Read(R, ch);
			i := BIT.LOR(i, ASH(ORD(ch), 16)); Texts.Read(R, ch);
			i := BIT.LOR(i, ASH(ORD(ch), 8)); Texts.Read(R, ch);
			i := BIT.LOR(i, ORD(ch));
			Texts.WriteInt(W, i, 0)
		ELSIF S.s = "INTEGER (MSB)" THEN
			i := ASH(ASH(ORD(ch), 24), -16); Texts.Read(R, ch);
			i := BIT.LOR(i, ORD(ch));
			Texts.WriteInt(W, i, 0)
		ELSIF S.s = "NUM" THEN
			i := 0; s:= 0; j := 1;
			WHILE ORD(ch) >= 128 DO INC(i, ASH(ORD(ch) - 128, s) ); INC(s, 7); Texts.Read(R, ch); INC(j) END;
			Texts.WriteInt(W, i + ASH(ORD(ch) MOD 64 - ORD(ch) DIV 64 * 64, s), 0);
			Texts.WriteString(W, " ("); Texts.WriteInt(W, j, 0);
			IF j > 1 THEN Texts.WriteString(W, " Bytes)") ELSE Texts.WriteString(W, " Byte)") END
		ELSIF S.s = "REAL" THEN
			Texts.WriteReal(W, Reals.Real(ReadLInt()), 16)
		ELSIF S.s = "LONGREAL" THEN
			i := ReadLInt();
			Texts.WriteLongReal(W, Reals.RealL(ReadLInt(), i), 20)
		ELSIF S.s = "SET" THEN
			set := {};
			FOR i := 0 TO 7 DO IF BIT.BIT(ORD(ch), SHORT(SHORT(i))) THEN INCL(set, i) END END;
			Texts.Read(R, ch);
			FOR i := 8 TO 15 DO IF BIT.BIT(ORD(ch), SHORT(SHORT(i - 8))) THEN INCL(set, i) END END;
			Texts.Read(R, ch);
			FOR i := 16 TO 23 DO IF BIT.BIT(ORD(ch), SHORT(SHORT(i - 16))) THEN INCL(set, i) END END;
			Texts.Read(R, ch);
			FOR i := 24 TO 31 DO IF BIT.BIT(ORD(ch), SHORT(SHORT(i - 24))) THEN INCL(set, i) END END;
			Texts.WriteSet(W, set)
		ELSIF S.s = "ADDR (LSB rel.)" THEN
			Texts.WriteHex(W, lastF.pointloc.pos + ReadLInt() + 4); Texts.Write(W, "H")
		END;
		Texts.Write(W, TAB); Texts.Write(W, "'");Texts.WriteString(W, S.s); Texts.Write(W, "'");
		Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END
END Interpret;

(** Searches for the given pattern in the current or marked document. The pattern is either a string,
	a hex-stream or a bit-stream.
 	Usage: HexDocs.Seach ['^' | string | #b{bitdigit} | #h{hexdigit}]
 *)
PROCEDURE Search*;
VAR F: Frame; T: Texts.Text; val, pos, beg, end, time: LONGINT; S: Texts.Scanner;

	PROCEDURE CalcDispVec;	(* calculate displacement vector *)
	VAR i, j, d: INTEGER;
	BEGIN
		i := 1; d := 1;
		WHILE i <= sLen DO
			j := 0; WHILE (j + d < sLen) & (sPat[j] = sPat[j + d]) DO INC(j) END;
			WHILE i <= j + d DO sDv[i] := d; INC(i) END;
			INC(d)
		END
	END CalcDispVec;

	PROCEDURE SPatFound (text: Texts.Text; VAR pos:LONGINT): BOOLEAN;
	VAR R: Texts.Reader; l: LONGINT; i: INTEGER; ch: CHAR;
	BEGIN
		IF sLen > 0 THEN
			Texts.OpenReader(R, text, pos); Texts.Read(R, ch); INC(pos);
			l := text.len; i := 0;
			WHILE (i # sLen) & (pos <= l) DO
				IF ch = sPat[i] THEN
					INC(i); IF i < sLen THEN Texts.Read(R, ch); INC(pos) END
				ELSIF i = 0 THEN Texts.Read(R, ch); INC(pos)
				ELSE DEC(i, sDv[i])
				END
			END;
		ELSE i := -1
		END;
		RETURN i = sLen
	END SPatFound;

BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF (S.class = Texts.Inval) OR (S.class = Texts.Char) & (S.c = "^") THEN
		Oberon.GetSelection(T, beg, end, time);
		IF (T # NIL) & (time >= 0) THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
	END;
	IF S.class IN {Texts.String, Texts.Name} THEN
		COPY(S.s, sPat); sLen := S.len; CalcDispVec
	ELSIF (S.class = Texts.Char) & (S.c = "#") THEN
		Texts.Scan(S);
		IF S.class = Texts.Name THEN
			sLen := 0; val := 0;
			IF CAP(S.s[0]) = "B" THEN	(* binary *)
				pos := 7; beg := 1;
				WHILE (S.s[beg] >= "0") & (S.s[beg] <= "1") DO
					IF S.s[beg] = "1" THEN BIT.LSETBIT(val, SHORT(SHORT(pos))) END;
					DEC(pos); INC(beg);
					IF pos < 0 THEN sPat[sLen] := CHR(val); INC(sLen); val := 0; pos := 7 END
				END
			ELSE	(* hex *)
				IF CAP(S.s[0]) = "H" THEN beg := 1 ELSE beg := 0 END;
				pos := 1;
				WHILE IsHexDigit(S.s[beg]) DO
					val := val * 16 + HexToInt(S.s[beg]);
					DEC(pos); INC(beg);
					IF pos < 0 THEN sPat[sLen] := CHR(val); INC(sLen); val := 0; pos := 1 END
				END 
			END;
			sPat[sLen] := 0X;
			CalcDispVec
		END
	END;
	F := GetFrame();
	IF F # NIL THEN
		IF F.car THEN pos := F.carloc.pos + 1 ELSE pos := 0 END;
		IF SPatFound(F.file, pos) THEN Oberon.Defocus; SetCaret(F, pos - sLen)
		ELSE RemoveCaret(F)
		END
	END
END Search;

(** Sets the caret to the given position in the current (menu) or marked document.
  Usage: Hex.Locate '^' | pos
*)
PROCEDURE Locate*;
VAR VAR T: Texts.Text; beg, end, time: LONGINT; F: Frame; S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "^") THEN
		Oberon.GetSelection(T, beg, end, time);
		IF (T # NIL) & (time >= 0) THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
	END;
	IF S.class = Texts.Int THEN
		F := GetFrame();
		IF F # NIL THEN Oberon.Defocus; SetCaret(F, S.i) END
	END
END Locate;

(* ------------ module init. porcs ------------ *)
PROCEDURE MakeList;
VAR obj: Objects.Object; cnt: INTEGER; M: ListRiders.ConnectMsg; A: Objects.AttrMsg;

	PROCEDURE AddItem (R: ListRiders.Rider; val: ARRAY OF CHAR);
	VAR d: ListRiders.String;
	BEGIN NEW(d); COPY(val, d.s); R.do.Write(R, d); INC(cnt)
	END AddItem;

BEGIN
	obj := Gadgets.CreateViewModel("ListGadgets.NewFrame", "ListModels.NewList");
	IF obj # NIL THEN
		list := obj(Gadgets.Frame);
		A.id := Objects.set; A.name := "Cmd"; A.class := Objects.String; A.s := "Hex.Interpret '#Point'";
		A.res := -1; list.handle(list, A);
		M.R := NIL; list.obj.handle(list.obj, M);
		cnt := 0;
		IF M.R # NIL THEN
			AddItem(M.R, "LONGINT (LSB)");
			AddItem(M.R, "INTEGER (LSB)");
			AddItem(M.R, "SHORTINT");
			AddItem(M.R, "NUM");
			AddItem(M.R, "REAL");
			AddItem(M.R, "LONGREAL");
			AddItem(M.R, "SET");
			AddItem(M.R, "-------------");
			AddItem(M.R, "ADDR (LSB rel.)");
			AddItem(M.R, "-------------");
			AddItem(M.R, "LONGINT (MSB)");
			AddItem(M.R, "INTEGER (MSB)")
		END;
		list.H := Fonts.Default.height*cnt + 6
	END
END MakeList;

BEGIN
	Texts.OpenWriter(W);
	fnt := Fonts.This("Courier10.Scn.Fnt");
	MakeList;

	charW := fnt.maxX + 1; lineH := fnt.height + 1;
	hBlock := BarW + Left + 6*charW + 3*Gab;
	tBlock := hBlock + 16*(2*charW + Gab) + 4*5 + 3*Gab;

	Hex[0] := "0"; Hex[1] := "1"; Hex[2] := "2"; Hex[3] := "3";
	Hex[4] := "4"; Hex[5] := "5"; Hex[6] := "6"; Hex[7] := "7";
	Hex[8] := "8"; Hex[9] := "9"; Hex[10] := "A"; Hex[11] := "B";
	Hex[12] := "C"; Hex[13] := "D"; Hex[14] := "E"; Hex[15] := "F"
END Hex.
