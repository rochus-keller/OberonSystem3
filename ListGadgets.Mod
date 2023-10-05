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

MODULE ListGadgets;	(** portable *)	(* ps,   *)

IMPORT
	Files, Strings, Input, Display, Display3, Printer, Printer3, Objects, Links, Attributes, Fonts, Texts, Oberon,
	Effects, Gadgets, ListRiders;

CONST
	Version = 1; FoldSize = 7; ScrollLag = 10;
	(* some char *)
	LArrow = 0C4X; RArrow = 0C3X; UArrow = 0C1X; DArrow = 0C2X; CR = 0DX;
	UPage = 0A2X; DPage = 0A3X; Home = 0A8X; End = 0A9X;

	(* data states *)
	Pointed = 1;

	(** frame states *)
	inclpath* = 0;
	multisel* = 1;
	extendsel * = 2;
	exponpoint* = 3;
	locked* = 4;

TYPE
	Frame* = POINTER TO FrameDesc;
	Line* = POINTER TO LineDesc;
	Method* = POINTER TO MethodBlock;

	(** used to identify position of line in list *)
	Loc* = RECORD
		line*: Line;	(** which line *)
		y*: INTEGER	(** line's y relative to top of farme *)
	END;

	LineDesc* = RECORD
		next*, prev*: Line;		(** ring from top to bottom, with sentinel	*)
		key*: LONGINT;		(** key of represented item *)
		dx*, w*, h*, dsr*: INTEGER;		(** true text metrics *)
		n*, lev*: INTEGER;		(** N: line number / lev: ident level *)
		sel*: BOOLEAN;		(** line is selected or not *)
		folded*: BOOLEAN;		(** line's desc. are visible (unfolded) *)
		hasSub: BOOLEAN		(** line has desc. *)
	END;

	MethodBlock* = RECORD
		GetRider*: PROCEDURE(F: Frame; new: BOOLEAN): ListRiders.Rider;
		Format*: PROCEDURE(F: Frame; R: ListRiders.Rider; L: Line);
		Display*: PROCEDURE(F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER; R: ListRiders.Rider; L: Line);
		PrintFormat*: PROCEDURE(F: Frame; R: ListRiders.Rider; L: Line);
		Print*: PROCEDURE(F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER; R: ListRiders.Rider; L: Line)
	END;

	FrameDesc* = RECORD (Gadgets.FrameDesc)
		R*: ListRiders.Rider;
		state0*: SET;
		time*: LONGINT;
		left*, right*, top*, bottom*: INTEGER;
		hoff, levs, tab*: INTEGER;
		textC*, pointC*, backC*: INTEGER;
		lines*: Line;	(** sentinel *)
		first, point: Line;
		vPos, vMax: Objects.Object;
		hPos, hMax: Objects.Object;
		do*: Method;
		fnt*: Fonts.Font;

		car*: BOOLEAN; carloc*: Loc;
		sel*: BOOLEAN
	END;

	CaretMsg = RECORD (Display.FrameMsg)
		carY: INTEGER
	END;

VAR
	methods*: Method;
	WaitTime, mayscroll: LONGINT;
	W: Texts.Writer;
	pointText: Texts.Text;

(* ------------ aux. procs ------------ *)
PROCEDURE P (x: LONGINT): INTEGER;
BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
END P;

PROCEDURE TimeOk (): BOOLEAN;
BEGIN
	IF Oberon.Time() - mayscroll <= 0 THEN RETURN FALSE
	ELSE mayscroll := Oberon.Time() + WaitTime; RETURN TRUE
	END
END TimeOk;

PROCEDURE ValueToStr (d: ListRiders.Data; VAR str: ARRAY OF CHAR);
BEGIN
	IF d = NIL THEN COPY("EMPTY", str)
	ELSE
		IF d IS ListRiders.String THEN COPY(d(ListRiders.String).s, str)
		ELSIF d IS ListRiders.Int THEN Strings.IntToStr(d(ListRiders.Int).i, str)
		ELSIF d IS ListRiders.Real THEN Strings.RealToStr(d(ListRiders.Real).x, str)
		ELSIF d IS ListRiders.LReal THEN Strings.RealToStr(d(ListRiders.LReal).x, str)
		ELSIF d IS ListRiders.Bool THEN Strings.BoolToStr(d(ListRiders.Bool).b, str)
		ELSIF d IS ListRiders.Char THEN str[0] := d(ListRiders.Char).c; str[1] := 0X
		ELSE COPY("UNKNOWN DATA", str)
		END
	END
END ValueToStr;

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

PROCEDURE DrawFold* (Q: Display3.Mask; x, y, dim, col: INTEGER; folded: BOOLEAN);
VAR h, half: INTEGER;
BEGIN
	half := dim DIV 2; h := 1 + 2*half;
	IF folded THEN
		INC(x, dim DIV 4); DEC(y, half);
		WHILE h > 0 DO
			Display3.ReplConst(Q, col, x, y, 1, h, Display3.replace);
			INC(x); INC(y); DEC(h, 2)
		END
	ELSE
		INC(y, (dim DIV 4) + 1);
		WHILE h > 0 DO
			Display3.ReplConst(Q, col, x, y, h, 1, Display3.replace);
			INC(x); DEC(y); DEC(h, 2)
		END
	END
END DrawFold;

PROCEDURE PrintFold* (Q: Display3.Mask; x, y, dim, col: INTEGER; folded: BOOLEAN);
VAR h, half: INTEGER;
BEGIN
	half := dim DIV 2; h := 1 + 2*half;
	IF folded THEN
		DEC(y, half);
		WHILE h > 0 DO
			Printer3.ReplConst(Q, col, x, y, 1, h, Display3.replace);
			INC(x); INC(y); DEC(h, 2)
		END
	ELSE
		INC(y, (dim DIV 4) + 1);
		WHILE h > 0 DO
			Printer3.ReplConst(Q, col, x, y, h, 1, Display3.replace);
			INC(x); DEC(y); DEC(h, 2)
		END
	END
END PrintFold;

PROCEDURE SetVPos (F: Frame; update: BOOLEAN);
BEGIN
	IF F.vPos # NIL THEN
		IF (F.first= NIL) OR (F.first = F.lines) THEN Attributes.SetInt(F.vPos, "Value", 0)
		ELSE Attributes.SetInt(F.vPos, "Value", F.first.n)
		END;
		Gadgets.Update(F.vPos)
	ELSIF update THEN Gadgets.Update(F)
	END
END SetVPos;

PROCEDURE SetVRange (F: Frame);
VAR L: Line;
BEGIN
	IF F.vMax # NIL THEN
		L := F.lines.prev;
		IF L.n <= 0 THEN Attributes.SetInt(F.vMax, "Value", 0)
		ELSE Attributes.SetInt(F.vMax, "Value", L.n)
		END;
		Gadgets.Update(F.vMax)
	END
END SetVRange;

PROCEDURE SetHPos (F: Frame);
BEGIN
	IF F.hPos # NIL THEN
		Attributes.SetInt(F.hPos, "Value", F.hoff DIV F.tab);
		Gadgets.Update(F.hPos)
	END
END SetHPos;

PROCEDURE SetHRange (F: Frame);
BEGIN
	IF F.hMax # NIL THEN
		Attributes.SetInt(F.hMax, "Value", F.levs);
		Gadgets.Update(F.hMax)
	END
END SetHRange;

PROCEDURE FormatLevel (F: Frame; R: ListRiders.Rider; level: INTEGER; L: Line);
VAR last: Line; stamp: LONGINT; n: INTEGER;
BEGIN
	stamp := ListRiders.Stamp(); n := L.n; last := L.next;
	WHILE ~R.eol & (R.do.GetStamp(R) # stamp) DO
		NEW(L.next); L.next.prev := L; L := L.next;
		INC(n); L.n := n;
		L.hasSub := R.dsc; L.folded := TRUE; L.sel := FALSE; L.lev := level; L.key := R.do.Key(R);
		F.do.Format(F, R, L);
		R.do.SetStamp(R, stamp); R.do.Set(R, R.do.Pos(R) + 1)
	END;
	L.next := last; last.prev := L;
	(* renumber *)
	REPEAT L := L.next; INC(n); L.n := n UNTIL L = F.lines;
	F.lines.n := -1;
	IF F.levs < level THEN F.levs := level; SetHRange(F) END
END FormatLevel;

PROCEDURE UpdateLevel (F: Frame; R: ListRiders.Rider; VAR L: Line; level: INTEGER);
VAR fL: Line; stamp, key: LONGINT;
BEGIN
	R.do.Set(R, 0); stamp := ListRiders.Stamp();
	WHILE ~R.eol & (R.do.GetStamp(R) # stamp) DO
		key := R.do.Key(R);
		IF L.key # key THEN
			fL := L; WHILE (fL.lev = level) & (fL.key # key) & (fL # F.lines) DO fL := fL.next END;
			IF (fL.key = key) & (fL.lev = level) THEN	(* delete lines between *)
				fL.prev := L.prev; L.prev.next := fL; L := fL
			ELSE	(* insert new line *)
				NEW(fL);
				fL.prev := L.prev; fL.next := L; L.prev := fL; fL.prev.next := fL; L := fL;
				L.key := key; L.sel := FALSE; L.lev := level
			END
		END;
		L.hasSub := R.dsc; L.folded := TRUE; L.n := L.prev.n + 1; L.lev := level;
		F.do.Format(F, R, L);
		R.do.SetStamp(R, stamp);
		L := L.next;
		IF L.lev > level THEN
			IF R.dsc THEN L.prev.folded := FALSE; UpdateLevel(F, R.do.Desc(R, NIL), L, level + 1)
			ELSE	(* remove sublevel(s) *)
				fL := L; REPEAT fL := fL.next UNTIL (fL.lev = level) OR (fL = F.lines);
				fL.prev := L.prev; L.prev.next := fL; L := fL
			END
		END;
		R.do.Set(R, R.do.Pos(R) + 1)
	END;
	IF (L # F.lines) & (L.lev = level) THEN	(* still lines of same level -> delete them *)
		fL := L; REPEAT fL := fL.next UNTIL (fL.lev < level) OR (fL = F.lines);
		fL.prev := L.prev; L.prev.next := fL; L := fL
	END;
	IF F.levs < level THEN F.levs := level END
END UpdateLevel;

PROCEDURE ReformatFrame (F: Frame);
VAR L: Line; R: ListRiders.Rider; n, lev: INTEGER;
BEGIN
	R := F.do.GetRider(F, TRUE);
	L := F.lines.next; 
	IF R # NIL THEN
		L := F.lines.next; R.do.Seek(R, L.key); lev := L.lev + 1; n := 0;
		WHILE L # F.lines DO
			IF lev = L.lev THEN R.do.Set(R, R.do.Pos(R) + 1)	(* step foreward *)
			ELSIF lev > L.lev THEN R.do.Seek(R, L.key)	(* come up *)
			ELSE R := R.do.Desc(R, R)	(* go down *)
			END;
			L.n := n; INC(n);
			F.do.Format(F, R, L);
			lev := L.lev; L := L.next
		END
	END
END ReformatFrame;

PROCEDURE LocateLine (F: Frame; y, Y: INTEGER; VAR loc: Loc; VAR cnt: INTEGER);
VAR py: INTEGER; L: Line;
BEGIN
	py := y + F.H - F.top; L := F.first;
	IF Y >= py THEN	(* above *)
		cnt := (py - Y - 1) DIV ScrollLag
	ELSIF Y < y + F.bottom THEN	(* below *)
		cnt := 1 + (y + F.bottom - Y) DIV ScrollLag;
		Y := y + F.bottom
	ELSE	(* inside *)
		cnt := 0
	END;
	DEC(py, L.h);
	WHILE (L.next # F.lines) & (Y < py) DO L := L.next; DEC(py, L.h) END;
	loc.line := L; loc.y := py - y - F.H;
END LocateLine;

PROCEDURE LocatePos (F: Frame; L: Line): INTEGER;
VAR L0: Line; Y: INTEGER;
BEGIN
	L0 := F.first;
	Y := -F.top - L0.h;
	IF L0.n < L.n THEN
		REPEAT L0 := L0.next; DEC(Y, L0.h) UNTIL L0 = L
	ELSIF L0.n > L.n THEN
		REPEAT INC(Y, L0.h); L0 := L0.prev UNTIL L0 = L
	END;
	RETURN Y
END LocatePos;

PROCEDURE NextSelLine (F: Frame; L: Line): Line;
BEGIN
	REPEAT L := L.next UNTIL L.sel OR (L= F.lines);
	RETURN L
END NextSelLine;

PROCEDURE FindParent (F: Frame; L: Line; level: INTEGER): Line;
VAR pL: Line;
BEGIN
	pL := L; REPEAT pL := pL.prev UNTIL (pL.lev = level) OR (pL = F.lines);
	RETURN pL
END FindParent;

PROCEDURE DeleteLine (F: Frame; R, linkR: ListRiders.Rider; L: Line);
VAR pL: Line;
BEGIN
	IF (linkR # NIL) & ~linkR.eol THEN
		IF (L.lev > 0) & (R # NIL) THEN
			pL := FindParent(F, L, L.lev-1); R.do.Seek(R, pL.key);
			R.do.DeleteLink(R, linkR)
		ELSE
			R.do.DeleteLink(NIL, linkR)
		END
	END
END DeleteLine;

PROCEDURE WritePath (F: Frame; L: Line; level: INTEGER);
VAR pR: ListRiders.Rider; s: ARRAY 64 OF CHAR;
BEGIN
	IF level >= 0 THEN
		WHILE (L.lev > level) DO L := L.prev END;
		WritePath(F, L, level - 1);
		pR := F.do.GetRider(F, FALSE); pR.do.Seek(pR, L.key);
		ValueToStr(pR.d, s);
		Texts.WriteString(W, s); Texts.Write(W, "/");
	END
END WritePath;

PROCEDURE GetSelection (F: Frame; VAR T: Texts.Text);
VAR L: Line; cnt: LONGINT; R: ListRiders.Rider; str: ARRAY 64 OF CHAR; incl: BOOLEAN;

	PROCEDURE Space (s: ARRAY OF CHAR): BOOLEAN;
	VAR i: LONGINT;
	BEGIN
		i := 0; WHILE (s[i] # 0X) & (s[i] # " ") & (s[i] # 9X) DO INC(i) END;
		RETURN s[i] # 0X;
	END Space;

BEGIN
	NEW(T); Texts.Open(T, "");
	R := F.do.GetRider(F, FALSE);
	IF R # NIL THEN
		incl := inclpath IN F.state0;
		L := NextSelLine(F, F.lines); cnt := 0;
		WHILE L # F.lines DO
			R.do.Seek(R, L.key);
			ValueToStr(R.d, str);
			IF incl OR ((R.d IS ListRiders.String) & Space(str)) THEN
				Texts.Write(W, 22X);
				IF incl THEN WritePath(F, L, L.lev - 1) END;
				Texts.WriteString(W, str); Texts.Write(W, 22X)
			ELSE Texts.WriteString(W, str)
			END;
			INC(cnt); L := NextSelLine(F, L);
			IF incl OR (cnt MOD 10 = 0) THEN Texts.WriteLn(W) ELSE Texts.Write(W, " ") END
		END;
		IF ~incl & (cnt MOD 10 > 0) THEN Texts.WriteLn(W) END;
		Texts.Append(T, W.buf)
	END
END GetSelection;

PROCEDURE RemoveSelection (F: Frame);
VAR L: Line; update: BOOLEAN;
BEGIN
	update := FALSE;
	L := F.lines;
	REPEAT update := update OR L.sel; L.sel := FALSE; L := L.next UNTIL L = F.lines;
	F.sel := FALSE;
	IF update THEN Gadgets.Update(F) END
END RemoveSelection;

PROCEDURE InvertSelection (F: Frame; Q: Display3.Mask; x, y, Y0: INTEGER; L0, L1: Line);
VAR w, Y, cx, cy, cw, ch: INTEGER;
BEGIN
	INC(x, F.left); w := F.W - (F.left + F.right); Y := Y0 + y + F.H;
	cx := Q.X; cy := Q.Y; cw := Q.W; ch := Q.H;
	Display3.AdjustMask(Q, x, y + F.bottom, w, F.H - (F.bottom + F.top));
	REPEAT
		L0.sel := ~L0.sel;
		Display3.ReplConst(Q, Display3.black, x, Y, w, L0.h, Display.invert);
		L0 := L0.next; DEC(Y, L0.h)
	UNTIL L0 = L1;
	Q.X := cx; Q.Y := cy; Q.W := cw; Q.H := ch
END InvertSelection;

PROCEDURE DeleteSelection (F: Frame);
VAR L: Line; R, linkR: ListRiders.Rider; update: BOOLEAN;
BEGIN
	R := F.do.GetRider(F, FALSE); linkR := F.do.GetRider(F, TRUE);
	IF (R # NIL) & (linkR # NIL) THEN
		update := FALSE;
		L := NextSelLine(F, F.lines);
		WHILE L # F.lines DO
			update := TRUE;
			linkR.do.Seek(linkR, L.key); DeleteLine(F, R, linkR, L);
			L := NextSelLine(F, L)
		END;
		IF update THEN Gadgets.Update(F.obj) END
	END
END DeleteSelection;

PROCEDURE AscSelection (F: Frame);
VAR L, pL: Line; R, linkR, pR: ListRiders.Rider; update: BOOLEAN;
BEGIN
	linkR := F.do.GetRider(F, FALSE); pR := F.do.GetRider(F, TRUE); R := F.do.GetRider(F, TRUE);
	IF (R # NIL) & (pR # NIL) & (linkR # NIL) THEN
		L := NextSelLine(F, F.lines); update := FALSE;
		WHILE L # F.lines DO
			IF L.lev > 0 THEN
				update := TRUE;
				linkR.do.Seek(linkR, L.key);
				pL := FindParent(F, L, L.lev-2);
				IF pL = F.lines THEN R.do.WriteLink(NIL, linkR)
				ELSE R.do.Seek(R, pL.key); R.do.WriteLink(R, linkR)
				END;
				DeleteLine(F, pR, linkR, L)
			END;
			L := NextSelLine(F, L)
		END;
		IF update THEN Gadgets.Update(F.obj) END
	END
END AscSelection;

PROCEDURE DescSelection (F: Frame);
VAR L: Line; R, linkR, pR: ListRiders.Rider; update: BOOLEAN;
BEGIN
	linkR := F.do.GetRider(F, FALSE); R := F.do.GetRider(F, TRUE); pR := F.do.GetRider(F, TRUE);
	IF (R # NIL) & (pR # NIL) & (linkR # NIL) THEN
		L := NextSelLine(F, F.lines);
		IF L # F.lines THEN
			update := FALSE;
			REPEAT
				R.do.Seek(R, L.key); R.do.Set(R, R.do.Pos(R) - 1);
				IF ~R.eol THEN
					update := TRUE;
					linkR.do.Seek(linkR, L.key);
					IF ~linkR.eol THEN R.do.WriteLink(R, linkR); DeleteLine(F, pR, linkR, L) END
				END;
				L := NextSelLine(F, L)
			UNTIL L = F.lines;
			IF update THEN Gadgets.Update(F.obj) END
		END
	END
END DescSelection;

PROCEDURE FlipCaret (F: Frame; Q: Display3.Mask; x, y, Y: INTEGER);
BEGIN Display3.ReplConst(Q, Display3.black, x + F.left, y+F.H+Y, F.W - F.left - F.right, 2, Display.invert)
END FlipCaret;

PROCEDURE FlipCaretMsg (F: Frame; carY: INTEGER);
VAR M: CaretMsg;
BEGIN M.F := F; M.carY := carY; Display.Broadcast(M)
END FlipCaretMsg;

PROCEDURE RemoveCaret (F: Frame);
BEGIN IF F.car THEN FlipCaretMsg(F, F.carloc.y); F.car := FALSE END
END RemoveCaret;

PROCEDURE SetCaret (F: Frame; carline: Line; carpos: INTEGER);
BEGIN
	IF F.car THEN FlipCaretMsg(F, F.carloc.y) END;
	F.carloc.line := carline; F.carloc.y := carpos; F.car := TRUE;
	FlipCaretMsg(F, carpos)
END SetCaret;

PROCEDURE ScrollUpdate (F:  Frame; Q: Display3.Mask; x, y, dy: INTEGER; dlink: Objects.Object);
VAR cx, cy, cw, ch, mx, my, mw, mh, w, h: INTEGER; D: Display.DisplayMsg;
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	IF F.car THEN FlipCaret(F, Q, x, y, F.carloc.y - dy) END;
	w := F.W - (F.left + F.right); h := F.H - (F.top + F.bottom);
	IF Display3.Rectangular(Q, mx, my, mw, mh) THEN	(* copy as much as possible *)
		cx := x + F.left; cy := y + F.bottom; cw := w; ch := h;
		ClipAgainst(mx, my, mw, mh, Q.X, Q.Y, Q.W, Q.H); ClipAgainst(mx, my, mw, mh, cx, cy, cw, ch);
		IF dy < 0 THEN	(* up; new lines come on top *)
			ClipAgainst(cx, cy, cw, ch, cx, cy - dy, cw, h + dy);	(* clip top *)
			ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip source area *)
			INC(cy, dy);
			ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip destination area *)
			D.v := cy + ch - (y + F.H - 1); D.h := -dy
		ELSE	(* down; new lines come at bottom *)
			ClipAgainst(cx, cy, cw, ch, cx, cy, cw, h - dy);	(* clip bottom *)
			ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip source area *)
			INC(cy, dy);
			ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip destination area *)
			D.v :=  cy - dy - (y + F.H - 1); D.h := dy
		END;
		Display.CopyBlock(cx, cy - dy, cw, ch, cx, cy, Display.replace)
	ELSE	(* full update *)
		D.v := F.bottom - F.H; D.h := h
	END;
	IF F.car THEN FlipCaret(F, Q, x, y, F.carloc.y) END;
	D.device := Display.screen; D.id := Display.area; D.F := F; D.dlink := dlink;
	D.x := x - F.X; D.y := y - F.Y; D.u := F.left; D.w := w;
	F.handle(F, D)
END ScrollUpdate;

PROCEDURE ScrollSilent (F: Frame; dline: INTEGER; adjust: BOOLEAN; VAR dy: INTEGER);
VAR L, last: Line; Y: INTEGER;
BEGIN
	L := F.first; dy := 0;
	IF dline > 0 THEN	(* down *)
		IF adjust THEN	(* scroll until last line is visible and not more *)
			last := L; Y := F.H -F.top;
			WHILE (last # F.lines) & (Y - last.h > 0) DO DEC(Y, last.h); last := last.next END;
			WHILE ((last # F.lines) OR (Y - last.h < 0)) & (dline > 0) DO
				INC(Y, L.h); INC(dy, L.h); DEC(dline);
				L := L.next; IF last # F.lines THEN DEC(Y, last.h); last := last.next END
			END
		ELSE
			WHILE (L.next # F.lines) & (dline > 0) DO L := L.next; INC(dy, L.h); DEC(dline) END
		END
	ELSIF dline < 0 THEN	(* up *)
		WHILE (L.prev # F.lines) & (dline < 0) DO L := L.prev; DEC(dy, L.h); INC(dline) END
	END;
	IF L # F.first THEN
		F.first := L;
		IF F.car THEN INC(F.carloc.y, dy) END
	END
END ScrollSilent;

PROCEDURE Scroll (F: Frame; Q: Display3.Mask; x, y, dline: INTEGER; dlink: Objects.Object; VAR dy: INTEGER);
BEGIN
	ScrollSilent(F, dline, TRUE, dy);
	IF dy # 0 THEN ScrollUpdate(F, Q, x, y, dy, dlink) END
END Scroll;

PROCEDURE ToggleLine (F: Frame; line: Line);
VAR carL, L: Line; R: ListRiders.Rider; levs, n: INTEGER;
BEGIN
	IF line.hasSub THEN
		IF line.folded THEN	(* unfold lines *)
			R := F.do.GetRider(F, FALSE); R.do.Seek(R, line.key);
			IF (R # NIL) & ~R.eol THEN
				R := R.do.Desc(R, R);
				FormatLevel(F, R, line.lev + 1, line);
				IF F.car THEN SetCaret(F, F.carloc.line, LocatePos(F, F.carloc.line)) END
			END
		ELSE	(* fold lines *)
			L := line.next; carL := F.carloc.line;
			WHILE L.lev > line.lev DO IF L = carL THEN carL := line END; L := L.next END;
			line.next := L; L.prev := line;
			(* renumber & calc levels *)
			levs := 0; L := F.lines;
			REPEAT L := L.next; IF L.lev > levs THEN levs := L.lev END UNTIL L = line;
			n := line.n;
			WHILE L # F.lines DO
				IF L.lev > levs THEN levs := L.lev END;
				L.n := n; INC(n);
				L := L.next
			END;
			IF levs # F.levs THEN F.levs := levs; SetHRange(F) END;
			IF (F.car) & ((carL # F.carloc.line) OR (carL.n > line.n)) THEN SetCaret(F, carL, LocatePos(F, carL)) END
		END;
		line.folded := ~line.folded;
		SetVRange(F)
	END
END ToggleLine;

PROCEDURE InsertItems (F: Frame; T: Texts.Text; beg, end: LONGINT; L: Line);
VAR R: ListRiders.Rider; d: ListRiders.String; S: Texts.Scanner; update: BOOLEAN;
BEGIN
	R := F.do.GetRider(F, FALSE);
	IF R # NIL THEN
		update := FALSE;
		R.do.Seek(R, L.key);
		IF L.hasSub & ~L.folded THEN R := R.do.Desc(R, R)
		ELSE R.do.Set(R, R.do.Pos(R) + 1)
		END;
		Texts.OpenScanner(S, T, beg); S.class := Texts.Inval; Texts.Scan(S); NEW(d);
		WHILE ~(S.class = Texts.Inval) DO
			CASE S.class OF
				Texts.String, Texts.Name: COPY(S.s, d.s)
				| Texts.Int: Strings.IntToStr(S.i, d.s)
				| Texts.Real: Strings.RealToStr(S.x, d.s)
				| Texts.Char: d.s[0] := S.c; d.s[1] := 0X
			ELSE d.s[0] := 0X
			END;
			IF d.s[0] # 0X THEN update := TRUE; R.do.Write(R, d); NEW(d) END;
			S.class := Texts.Inval;
			IF Texts.Pos(S) < end THEN Texts.Scan(S) END
		END;
		IF update THEN Gadgets.Update(F.obj) END
	END
END InsertItems;

PROCEDURE InsertLink (F: Frame; L: Line);
VAR R, linkR: ListRiders.Rider; selL: Line; update: BOOLEAN;
BEGIN
	linkR := F.do.GetRider(F, FALSE);
	IF linkR # NIL THEN
		update := FALSE;
		IF (L.hasSub & ~L.folded) OR (L.lev > 0) THEN
			R := F.do.GetRider(F, TRUE);
			IF ~L.hasSub OR L.folded THEN L := FindParent(F, L, L.lev - 1) END;
			R.do.Seek(R, L.key);
		ELSE
			R := NIL
		END;
		selL := NextSelLine(F, F.lines);
		WHILE selL # F.lines DO
			update := TRUE;
			linkR.do.Seek(linkR, selL.key); linkR.do.WriteLink(R, linkR);
			selL := NextSelLine(F, selL)
		END;
		IF update THEN Gadgets.Update(F.obj) END
	END
END InsertLink;

(** Standard frame methods *)
PROCEDURE GetStandardRider* (F: Frame; new: BOOLEAN): ListRiders.Rider;
VAR M: ListRiders.ConnectMsg;
BEGIN
	IF ((F.R = NIL) OR new) & (F.obj # NIL) THEN M.R := NIL; Objects.Stamp(M); F.obj.handle(F.obj, M); F.R := M.R END;
	RETURN F.R
END GetStandardRider;

PROCEDURE FormatLine* (F: Frame; R: ListRiders.Rider; L: Line);
VAR str: ARRAY 64 OF CHAR;
BEGIN
	ValueToStr(R.d, str);
	Display3.StringSize(str, F.fnt, L.w, L.h, L.dsr);
	L.dx := FoldSize + 2 + L.lev*F.tab
END FormatLine;

PROCEDURE DisplayLine* (F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER; R: ListRiders.Rider; L: Line);
VAR str: ARRAY 64 OF CHAR;
BEGIN
	ValueToStr(R.d, str);
	Display3.ReplConst(Q, F.backC, x, y, w, h, Display.replace);
	INC(x, L.lev*F.tab);
	IF L.hasSub THEN DrawFold(Q, x, y + (h DIV 2), FoldSize, Display3.black, L.folded) END;
	INC(x, FoldSize + 2);
	IF R.do.State(R) = Pointed THEN Display3.String(Q, F.pointC, x, y + L.dsr, F.fnt, str, Display.paint)
	ELSE Display3.String(Q, F.textC, x, y + L.dsr, F.fnt, str, Display.paint)
	END
END DisplayLine;

PROCEDURE PrintFormatLine* (F: Frame; R: ListRiders.Rider; L: Line);
VAR str: ARRAY 64 OF CHAR;
BEGIN
	ValueToStr(R.d, str);
	Printer3.StringSize(str, F.fnt, L.w, L.h, L.dsr);
	L.dx := P(FoldSize + 2 + L.lev*F.tab)
END PrintFormatLine;

PROCEDURE PrintLine* (F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER; R: ListRiders.Rider; L: Line);
VAR str: ARRAY 64 OF CHAR;
BEGIN
	ValueToStr(R.d, str);
	Printer3.ReplConst(Q, F.backC, x, y, w, h, Display.replace);
	INC(x, P(L.lev*F.tab));
	IF L.hasSub THEN PrintFold(Q, x, y + (h DIV 2), P(FoldSize), Display3.black, L.folded) END;
	INC(x, P(FoldSize + 2));
	IF R.do.State(R) = Pointed THEN Printer3.String(Q, F.pointC, x, y + L.dsr, F.fnt, str, Display.paint)
	ELSE Printer3.String(Q, F.textC, x, y + L.dsr, F.fnt, str, Display.paint)
	END
END PrintLine;

(* ------------ standard frame procs ------------ *)
PROCEDURE RestoreFrame (F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER);
VAR L: Line; R: ListRiders.Rider; lev, Y, lx, lw, cx, cy, cw, ch: INTEGER;
BEGIN
	Oberon.FadeCursor(Oberon.Mouse);
	Y :=  y + h - F.top; lx := x + F.left; lw := w - (F.left + F.right);
	L := F.first;
	R := F.do.GetRider(F, FALSE);
	IF R # NIL THEN
		DEC(lx, F.hoff); INC(lw, F.hoff);
		cx := Q.X; cy := Q.Y; cw := Q.W; ch := Q.H;
		Display3.AdjustMask(Q, lx, y + F.bottom, lw, h - (F.top - F.bottom));
		lev := L.lev + 1; 
		WHILE (L # F.lines) & (Y > y + F.bottom) DO
			IF lev = L.lev THEN R.do.Set(R, R.do.Pos(R) + 1)	(* step foreward *)
			ELSIF lev > L.lev THEN R.do.Seek(R, L.key)	(* come up *)
			ELSE R := R.do.Desc(R, R)	(* go down *)
			END;
			DEC(Y, L.h); lev := L.lev;
			F.do.Display(F, Q, lx, Y, lw, L.h, R, L);
			IF L.sel THEN Display3.ReplConst(Q, Display3.black, lx, Y, lw, L.h, Display.invert) END;
			L := L.next
		END;
		INC(lx, F.hoff); DEC(lw, F.hoff);
		Q.X := cx; Q.Y := cy; Q.W := cw; Q.H := ch
	ELSE
		DEC(Y, F.fnt.height);
		Display3.ReplConst(Q, F.backC, lx, Y, lw, F.fnt.height, Display.replace);
		Display3.String(Q, F.textC, lx, Y - F.fnt.minY, F.fnt, "NO MODEL SET", Display.paint)
	END;
	DEC(Y, y); IF Y < F.bottom THEN Y := F.bottom END;

	Display3.Rect3D(Q, Display3.bottomC, Display3.topC, x, y, w, h, 1, Display3.replace);
	Display3.ReplConst(Q, F.backC, x + 1, y + 1, F.left-1, h - 2, Display.replace);
	Display3.ReplConst(Q, F.backC, x + w - F.right, y + 1, F.right - 1, h - 2, Display.replace);
	Display3.ReplConst(Q, F.backC, lx, y + h - F.top, lw, F.top - 1, Display.replace);
	Display3.ReplConst(Q, F.backC, lx, y + 1, lw, Y - 1, Display.replace);

	IF F.car THEN FlipCaret(F, Q, x, y, F.carloc.y) END;

	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display3.paint)
  END
END RestoreFrame;

PROCEDURE PrintFrame (F: Frame; VAR M: Display.DisplayMsg);
VAR L, pL: Line; R: ListRiders.Rider; Q: Display3.Mask; fnt: Fonts.Font;
		x, y, w, h, top, bottom, left, right, lx, lw, Y, cx, cy, cw, ch, lev: INTEGER;
BEGIN
	x := M.x; y := M.y; w := P(F.W); h := P(F.H);
	Gadgets.MakePrinterMask(F, x, y, M.dlink, Q);
	Printer3.FilledRect3D(Q, Display3.bottomC, Display3.topC, F.backC, x, y, w, h, P(1), Display3.replace);
	top := P(F.top); bottom := P(F.bottom); left := P(F.left); right := P(F.right);
	Y :=  y + h - top; lx := x + left; lw := w - (left + right);
	L := F.first;
	R := F.do.GetRider(F, FALSE);
	IF R # NIL THEN
		NEW(pL);
		DEC(lx, P(F.hoff)); INC(lw, P(F.hoff));
		cx := Q.X; cy := Q.Y; cw := Q.W; ch := Q.H;
		lev := L.lev + 1; 
		Display3.AdjustMask(Q, lx, y + bottom, lw, h - (top - bottom));
		WHILE (L # F.lines) & (Y > y + bottom) DO
			IF lev = L.lev THEN R.do.Set(R, R.do.Pos(R) + 1)	(* step foreward *)
			ELSIF lev > L.lev THEN R.do.Seek(R, L.key)	(* come up *)
			ELSE R := R.do.Desc(R, R)	(* go down *)
			END;
			lev := L.lev;
			pL^ := L^; F.do.PrintFormat(F, R, pL);
			DEC(Y, pL.h); 
			F.do.Print(F, Q, lx, Y, lw, pL.h, R, pL);
			L := L.next
		END;
		INC(lx, P(F.hoff)); DEC(lw, P(F.hoff));
		Q.X := cx; Q.Y := cy; Q.W := cw; Q.H := ch
	ELSE
		fnt := Printer.GetMetric(F.fnt);
		IF fnt # NIL THEN DEC(Y, fnt.height + fnt.minY) ELSE DEC(Y, P(F.fnt.height) - P(-F.fnt.minY)) END;
		Printer3.String(Q, F.textC, lx, Y, F.fnt, "NO MODEL SET", Display.paint)
	END
END PrintFrame;

PROCEDURE TrackSelection (F: Frame; x, y: INTEGER; VAR M: Oberon.InputMsg);
VAR Q: Display3.Mask; first, oL, nL: Line; T: Texts.Text; keysum, keys: SET; fy, oy, dy, cnt: INTEGER; loc: Loc;
		C: Oberon.ConsumeMsg;
BEGIN
	Gadgets.MakeMask(F, x, y, M.dlink, Q); Display3.Copy(Q, Q);
	Input.KeyState(keys);
	IF ~(extendsel IN F.state0) OR ~(Input.ALT IN keys) THEN RemoveSelection(F) END;
	
	LocateLine(F, y, M.Y, loc, cnt);
	first := loc.line; oL := first; fy := loc.y; oy := fy;
	InvertSelection(F,  Q, x, y, fy, first, first.next);
	keysum := M.keys;
	REPEAT
		Input.Mouse(M.keys, M.X, M.Y);
		LocateLine(F, y, M.Y, loc, cnt);
		IF cnt # 0 THEN	(* scroll *)
			IF TimeOk() THEN
				Oberon.FadeCursor(Oberon.Mouse);
				Scroll(F, Q, x, y, cnt, M.dlink, dy);
				IF dy # 0 THEN
					IF dy > 0 THEN	(* down *)
						(*
						INC(loc.y, dy);
						WHILE (loc.line.next # F.lines) & (y + F.bottom < loc.y) DO
							loc.line := loc.line.next;
							DEC(loc.y, loc.line.h)
						END
						*)
						LocateLine(F, y, M.Y, loc, cnt)
					ELSE	(* up *)
						loc.line := F.first; loc.y := - F.top - loc.line.h
					END;
					INC(fy, dy); INC(oy, dy)
				END
			END
		END;
		IF oL # loc.line THEN
			Oberon.FadeCursor(Oberon.Mouse);
			IF multisel IN F.state0 THEN
				IF oL.n > loc.line.n THEN nL := oL; oL := loc.line; oy := loc.y
				ELSE nL := loc.line
				END;
				IF (oL.n < first.n) & (nL.n > first.n) THEN InvertSelection(F, Q, x, y, fy, first, first.next) END;
				IF oL.n >= first.n THEN oL := oL.next; DEC(oy, oL.h) END;
				IF nL.n > first.n THEN nL := nL.next END; 
				InvertSelection(F, Q, x, y, oy, oL, nL);
				oy := loc.y; oL := loc.line
			ELSE
				InvertSelection(F, Q, x, y, oy, oL, oL.next);
				oy := loc.y; oL := loc.line;
				InvertSelection(F, Q, x, y, oy, oL, oL.next)
			END
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	Oberon.FadeCursor(Oberon.Mouse);

	F.sel := TRUE; F.time := Oberon.Time();
	IF ~(locked IN F.state0) THEN
		IF keysum = {0, 1} THEN	(* copy over *)
			IF F.car THEN InsertLink(F, loc.line)
			ELSE
				GetSelection(F, T);
				IF T.len > 0 THEN C.F := NIL; C.text := T; C.beg := 0; C.end := T.len; Display.Broadcast(C) END
			END
		ELSIF keysum = {0, 2} THEN DeleteSelection(F)
		END
	END;
	SetVPos(F, TRUE);
	M.res := 0
END TrackSelection;

PROCEDURE TrackPoint (F: Frame; x, y: INTEGER; VAR M: Oberon.InputMsg);
VAR Q: Display3.Mask; R: ListRiders.Rider; oldorg: LONGINT; keysum: SET;
		left, top, w, ox, oy, ow, dy, cnt: INTEGER; update: BOOLEAN; loc: Loc;
BEGIN
	update := FALSE; oldorg := F.first.n;
	left := x + F.left - F.hoff; top := y + F.H; w := F.W - F.left - F.right;
	Gadgets.MakeMask(F, x, y, M.dlink, Q); Display3.Copy(Q, Q);
	Display3.AdjustMask(Q, x + F.left, y + F.bottom, w, F.H - (F.top - F.bottom));
	LocateLine(F, y, M.Y, loc, cnt);
	ox := left + loc.line.dx; oy := loc.y; ow := loc.line.w; 
	Display3.ReplConst(Q, F.backC, ox, top + oy, ow, 2, Display.invert);
	keysum := M.keys;
	REPEAT
		Input.Mouse(M.keys, M.X, M.Y);
		LocateLine(F, y, M.Y, loc, cnt);
		IF cnt # 0 THEN	(* scroll *)
			IF TimeOk() THEN
				Oberon.FadeCursor(Oberon.Mouse);
				Display3.ReplConst(Q, F.backC, ox, top + oy, ow, 2, Display.invert);
				Scroll(F, Q, x, y, cnt, M.dlink, dy); oy := 1; ow := 0
			END
		ELSIF loc.y # oy THEN
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.ReplConst(Q, F.backC, ox, top + oy, ow, 2, Display.invert);
			ox := left + loc.line.dx; oy := loc.y; ow := loc.line.w;
			Display3.ReplConst(Q, F.backC, ox, top + oy, ow, 2, Display.invert)
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	Oberon.FadeCursor(Oberon.Mouse);
	Display3.ReplConst(Q, F.backC, ox, top + oy, ow, 2, Display.invert);

	IF (keysum = {1}) & (cnt = 0) THEN
		IF (exponpoint IN F.state0) OR (x <= M.X) & (M.X < x + loc.line.dx) THEN
			ToggleLine(F, loc.line); update := TRUE
		END;
		IF F.pointC # F.textC THEN
			R := F.do.GetRider(F, FALSE);
			IF R # NIL THEN
				R.do.Seek(R, loc.line.key); R.do.SetState(R, Pointed);
				update := TRUE
			END
		END;
		F.point := loc.line;
		IF ~(exponpoint IN F.state0) & (x + loc.line.dx <= M.X) OR ~loc.line.hasSub THEN
			Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL)
		END;
		F.point := NIL
	END;
	IF update OR (oldorg # F.first.n) THEN
		IF oldorg # F.first.n THEN SetVPos(F, TRUE)
		ELSE Gadgets.Update(F)
		END
	END;
	M.res := 0
END TrackPoint;

PROCEDURE TrackCaret (F: Frame; x, y: INTEGER; VAR M: Oberon.InputMsg);
VAR Q: Display3.Mask; T: Texts.Text; keysum: SET; oldorg, time, beg, end: LONGINT; oy, dy, cnt: INTEGER; loc: Loc;
BEGIN
	Gadgets.MakeMask(F, x, y, M.dlink, Q); Display3.Copy(Q, Q);
	Oberon.Defocus;
	oldorg := F.first.n;
	LocateLine(F, y, M.Y, loc, cnt);
	oy := loc.y;
	FlipCaret(F, Q, x, y, oy);
	keysum := M.keys;
	REPEAT
		Input.Mouse(M.keys, M.X, M.Y);
		LocateLine(F, y, M.Y, loc, cnt);
		IF (cnt > 0) OR (cnt < -1) THEN	(* scroll *)
			IF TimeOk() THEN
				Oberon.FadeCursor(Oberon.Mouse);
				FlipCaret(F, Q, x, y, oy);
				Scroll(F, Q, x, y, cnt, M.dlink, dy);
				oy := 1
			END
		ELSE
			IF cnt = -1 THEN loc.line := F.first.prev; loc.y := -F.top END;
			IF loc.y # oy THEN
				Oberon.FadeCursor(Oberon.Mouse);
				FlipCaret(F, Q, x, y, oy);
				oy := loc.y; FlipCaret(F, Q, x, y, oy)
			END
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	Oberon.FadeCursor(Oberon.Mouse);
	FlipCaret(F, Q, x, y, oy);

	IF (cnt  = 0) OR (cnt = -1) THEN	(* caret in frame *)
		IF ~(locked IN F.state0) & (keysum = {1, 2}) THEN	(* copy over *)
			Oberon.GetSelection(T, beg, end, time);
			IF time >= 0 THEN
				IF time = F.time THEN InsertLink(F, loc.line)
				ELSE InsertItems(F, T, beg, end, loc.line)
				END
			END
		END;
		SetCaret(F, loc.line, oy)
	END;
	IF oldorg # F.first.n THEN SetVPos(F, TRUE) END;
	M.res := 0
END TrackCaret;

PROCEDURE Consume (F: Frame; x, y: INTEGER; VAR M: Oberon.InputMsg);
VAR Q: Display3.Mask; carY, Y, dy, cnt: INTEGER; carL, L: Line; keys: SET;
BEGIN
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	IF (M.ch = LArrow) & ~(locked IN F.state0) THEN AscSelection(F)
	ELSIF (M.ch = RArrow) & ~(locked IN F.state0) THEN  DescSelection(F)
	ELSIF M.ch = UArrow THEN
		IF F.carloc.line # F.lines THEN
			RemoveCaret(F);
			carY := F.carloc.y; carL := F.carloc.line;
			Input.KeyState(keys);
			IF Input.SHIFT IN keys THEN
				IF carL.sel THEN
					IF ~((multisel IN F.state0) & (carL.prev.sel)) & ~(extendsel IN F.state0) THEN RemoveSelection(F) END
				ELSE
					IF ~((multisel IN F.state0) & (carL.next.sel)) & ~(extendsel IN F.state0) THEN RemoveSelection(F) END
				END;
				InvertSelection(F, Q, x, y, carY, carL, carL.next);
				IF carL.sel THEN F.sel := TRUE; F.time := Oberon.Time() END
			END;
			INC(carY, carL.h); carL := carL.prev;
			IF carY >= 0 THEN ScrollSilent(F, carL.next.n - F.first.n, TRUE, dy); INC(carY, dy)
			ELSIF carY < F.bottom - F.H THEN
				L := F.first; Y := carY; cnt := 0;
				REPEAT INC(Y, L.h); L := L.next UNTIL Y >= F.bottom - F.H;
				ScrollSilent(F, L.n - F.first.n, TRUE, dy); INC(carY, dy)
			END;
			SetVPos(F, TRUE);
			SetCaret(F, carL, carY)
		END
	ELSIF M.ch = DArrow THEN
		IF F.carloc.line.next # F.lines THEN
			RemoveCaret(F);
			carY := F.carloc.y; carL := F.carloc.line;
			carL := carL.next; DEC(carY, carL.h);
			Input.KeyState(keys);
			IF Input.SHIFT IN keys THEN
				IF carL.sel THEN
					IF ~((multisel IN F.state0) & (carL.next.sel)) & ~(extendsel IN F.state0) THEN RemoveSelection(F) END
				ELSE
					IF ~((multisel IN F.state0) & (carL.prev.sel)) & ~(extendsel IN F.state0) THEN RemoveSelection(F) END
				END;
				InvertSelection(F, Q, x, y, carY, carL, carL.next);
				IF carL.sel THEN F.sel := TRUE; F.time := Oberon.Time() END
			END;
			IF carY < F.bottom - F.H THEN
				L := F.first; Y := carY; cnt := 0;
				REPEAT INC(cnt); INC(Y, L.h); L := L.next UNTIL Y >= F.bottom - F.H;
				ScrollSilent(F, L.n - F.first.n, TRUE, dy); INC(carY, dy)
			ELSIF carY >= 0 THEN ScrollSilent(F, carL.next.n - F.first.n, TRUE, dy); INC(carY, dy)
			END;
			SetVPos(F, TRUE);
			SetCaret(F, carL, carY)
		END
	ELSIF M.ch = CR THEN
		IF F.carloc.line.hasSub THEN
			ToggleLine(F, F.carloc.line); Gadgets.Update(F)
		ELSE
			F.point := F.carloc.line;
			Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL);
			F.point := NIL
		END
	ELSIF M.ch = Home THEN
		IF F.first # F.lines.next THEN
			ScrollSilent(F, -F.first.n, TRUE, dy);
			SetVPos(F, TRUE);
			SetCaret(F, F.first, - F.top - F.first.h)
		END
	ELSIF M.ch = End THEN
		L := F.lines.prev; dy := F.H - (F.top + F.bottom) - L.h;
		WHILE (L.prev # F.lines) & (dy >= 0) DO L := L.prev; DEC(dy, L.h) END;
		IF L # F.first THEN
			ScrollSilent(F, L.next.n - F.first.n, TRUE, dy);
			SetVPos(F, TRUE);
			SetCaret(F, F.first, - F.top - F.first.h)
		END
	ELSIF M.ch = UPage THEN
		L := F.first; dy := F.H - (F.top + F.bottom) - L.h;
		WHILE (L.prev # F.lines) & (dy > 0) DO L := L.prev; DEC(dy, L.h) END;
		IF L # F.first THEN
			ScrollSilent(F, L.n - F.first.n, TRUE, dy);
			SetVPos(F, TRUE);
			SetCaret(F, F.first, - F.top - F.first.h)
		END
	ELSIF M.ch = DPage THEN
		L := F.first; dy := F.H - (F.top + F.bottom) - L.h;
		WHILE (L.next # F.lines) & (dy > 0) DO L := L.next; DEC(dy, L.h) END;
		IF L # F.first THEN
			ScrollSilent(F, L.n - F.first.n, TRUE, dy);
			SetVPos(F, TRUE);
			SetCaret(F, F.first, - F.top - F.first.h)
		END
	END;
	M.res := 0
END Consume;

PROCEDURE UpdateModel (F: Frame);
VAR oldlevs, key: LONGINT; L: Line; R: ListRiders.Rider;
BEGIN
	R := F.do.GetRider(F, TRUE);	(* get a new rider *)
	IF R # NIL THEN
		oldlevs := F.levs; F.levs := 0;
		RemoveCaret(F);
		key := F.first.key;
		L := F.lines.next;
		UpdateLevel(F, R, L, 0);
		(* find old first line *)
		L := F.lines;
		REPEAT L := L.next UNTIL (L = F.lines) OR (L.key = key);
		IF L = F.lines THEN F.first := L.next ELSE F.first := L END;
		(* check levels *)
		IF oldlevs # F.levs THEN
			IF F.hoff DIV F.tab > F.levs THEN F.hoff := F.levs * F.tab; SetHPos(F) END;
			SetHRange(F)
		END
	END
END UpdateModel;

PROCEDURE UpdateFrame (F: Frame; M: Gadgets.UpdateMsg);
VAR val, n: LONGINT; dy: INTEGER; D: Display.DisplayMsg;
BEGIN
	IF F.obj # NIL THEN F.obj.handle(F.obj, M) END;
	IF F.vPos # NIL THEN F.vPos.handle(F.vPos, M) END;
	IF F.vMax # NIL THEN F.vMax.handle(F.vMax, M) END;
	IF F.hPos # NIL THEN F.hPos.handle(F.hPos, M) END;
	IF F.hMax # NIL THEN F.hMax.handle(F.hMax, M) END;
	IF M.obj = F.obj THEN
		IF M.stamp # F.stamp THEN
			F.stamp := M.stamp;
			UpdateModel(F);
			SetVPos(F, FALSE); SetVRange(F)
		END;
		D.device := Display.screen; D.id := Display.full; D.dlink := M.dlink;
		D.F := F; D.x := M.x; D.y := M.y; D.res := -1;
		F.handle(F, D)
	ELSIF M.obj = F.vPos THEN
		IF M.stamp # F.stamp THEN
			F.stamp := M.stamp;
			Attributes.GetInt(F.vPos, "Value", val);
			IF (F.first = NIL) OR (F.first = F.lines) THEN n := 0 ELSE n := F.first.n END;
			IF val # n THEN
				ScrollSilent(F, SHORT(val - n), FALSE, dy);
				IF dy = 0 THEN SetVPos(F, FALSE) END
			END
		END;
		D.device := Display.screen; D.id := Display.full; D.dlink := M.dlink;
		D.F := F; D.x := M.x; D.y := M.y; D.res := -1;
		F.handle(F, D)
	ELSIF M.obj = F.hPos THEN
		IF M.stamp # F.stamp THEN
			F.stamp := M.stamp;
			Attributes.GetInt(F.hPos, "Value", val);
			IF val < 0 THEN val := 0 END;
			F.hoff := SHORT(val * F.tab)
		END;
		D.device := Display.screen; D.id := Display.full; D.dlink := M.dlink;
		D.F := F; D.x := M.x; D.y := M.y; D.res := -1;
		F.handle(F, D)
	ELSIF M.obj = F.vMax THEN	(* do nothing: causes recursion when models is shared between diff. frames *)
	ELSIF M.obj = F.hMax THEN	(* do nothing: (see vMax) *)
	ELSE Gadgets.framehandle(F, M)
	END
END UpdateFrame;

PROCEDURE FrameAttr (F: Frame; VAR M: Objects.AttrMsg);
VAR R: ListRiders.Rider; l: Line; B: Texts.Buffer;
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN
			M.class := Objects.String; M.s := "ListGadgets.NewFrame"; M.res := 0
		ELSIF M.name = "Cmd" THEN
			Gadgets.framehandle(F, M);
			IF M.res < 0 THEN M.class := Objects.String; M.s := ""; M.res := 0 END
		ELSIF M.name = "Point" THEN
			M.class := Objects.String; M.s := ""; M.res := 0;
			IF F.point # NIL THEN
				R := F.do.GetRider(F, FALSE);
				IF R # NIL THEN
					Oberon.FadeCursor(Oberon.Mouse);
					NEW(B); Texts.OpenBuf(B); Texts.Recall(B);
					IF pointText.len > 0 THEN Texts.Delete(pointText, 0, pointText.len) END;
					IF inclpath IN F.state0 THEN WritePath(F, F.point, F.point.lev - 1) END;
					R.do.Seek(R, F.point.key); ValueToStr(R.d, M.s); Texts.WriteString(W, M.s);
					Texts.Append(pointText, W.buf);
					Attributes.TxtToStr(pointText, M.s);
					Texts.Delete(pointText, 0, pointText.len);
					(* restore restore buffer *)
					Texts.Append(pointText, B); Texts.Delete(pointText, 0, pointText.len)
				END
			END
		ELSIF M.name = "PointKey" THEN
			M.class := Objects.Int; M.i := MIN(LONGINT); M.res := 0;
			IF F.point # NIL THEN M.i := F.point.key END
		ELSIF M.name = "Sel" THEN
			M.class := Objects.String; M.s := ""; M.res := 0;
			IF F.sel THEN
				l := F.first;
				WHILE (l # F.lines) & ~l.sel DO l := l.next END;
				IF l # F.lines THEN
					R := F.do.GetRider(F, FALSE);
					IF R # NIL THEN R.do.Seek(R, l.key); ValueToStr(R.d, M.s) END
				END
			END
		ELSIF M.name = "SelKey" THEN
			M.class := Objects.Int; M.i := MIN(LONGINT); M.res := 0;
			IF F.sel THEN
				l := F.first;
				WHILE (l # F.lines) & ~l.sel DO l := l.next END;
				IF l # F.lines THEN M.i := l.key END
			END
		ELSIF M.name = "Font" THEN M.class := Objects.String; COPY(F.fnt.name, M.s); M.res := 0
		ELSIF M.name = "LineupHY" THEN M.class := Objects.Int; M.i := F.H - Fonts.Default.height; M.res := 0
		ELSIF M.name = "BackCol" THEN M.class := Objects.Int; M.i := F.backC; M.res := 0
		ELSIF M.name = "TextCol" THEN M.class := Objects.Int; M.i := F.textC; M.res := 0
		ELSIF M.name = "PointCol" THEN M.class := Objects.Int; M.i := F.pointC; M.res := 0
		ELSIF M.name = "TabSize" THEN M.class := Objects.Int; M.i := F.tab; M.res := 0
		ELSIF M.name = "InclPath" THEN M.class := Objects.Bool; M.b := inclpath IN F.state0; M.res := 0
		ELSIF M.name = "MultiSel" THEN M.class := Objects.Bool; M.b := multisel IN F.state0; M.res := 0
		ELSIF M.name = "ExtendSel" THEN M.class := Objects.Bool; M.b := extendsel IN F.state0; M.res := 0
		ELSIF M.name = "ExpOnPoint" THEN M.class := Objects.Bool; M.b := exponpoint IN F.state0; M.res := 0
		ELSIF M.name = "Locked" THEN M.class := Objects.Bool; M.b := locked IN F.state0; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Font" THEN
			IF M.class = Objects.String THEN F.fnt := Fonts.This(M.s); ReformatFrame(F); M.res := 0 END
		ELSIF M.name = "BackCol" THEN
			IF M.class = Objects.Int THEN F.backC := SHORT(M.i); M.res := 0 END
		ELSIF M.name = "TextCol" THEN
			IF M.class = Objects.Int THEN F.textC := SHORT(M.i); M.res := 0 END
		ELSIF M.name = "PointCol" THEN
			IF M.class = Objects.Int THEN F.pointC := SHORT(M.i); M.res := 0 END
		ELSIF M.name = "TabSize" THEN
			IF M.class = Objects.Int THEN F.tab := SHORT(M.i); M.res := 0 END
		ELSIF M.name = "InclPath" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN INCL(F.state0, inclpath) ELSE EXCL(F.state0, inclpath) END; M.res := 0
			END
		ELSIF M.name = "MultiSel" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN INCL(F.state0, multisel) ELSE EXCL(F.state0, multisel) END; M.res := 0
			END
		ELSIF M.name = "ExtendSel" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN INCL(F.state0, extendsel) ELSE EXCL(F.state0, extendsel) END; M.res := 0
			END
		ELSIF M.name = "ExpOnPoint" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN INCL(F.state0, exponpoint) ELSE EXCL(F.state0, exponpoint) END; M.res := 0
			END
		ELSIF M.name = "Locked" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN INCL(F.state0, locked) ELSE EXCL(F.state0, locked) END; M.res := 0
			END
		ELSIF (M.name = "Point") OR (M.name = "PointKey") THEN M.res := 0
		ELSIF (M.name = "Sel") OR (M.name = "SelKey") THEN M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("TabSize"); M.Enum("BackCol"); M.Enum("TextCol"); M.Enum("PointCol");
		M.Enum("InclPath"); M.Enum("MultiSel"); M.Enum("ExtendSel"); M.Enum("ExpOnPoint");
		M.Enum("Locked");
		M.Enum("Font"); M.Enum("Cmd");
		(* read only *)
		M.Enum("Point"); M.Enum("Sel"); M.Enum("PointKey"); M.Enum("SelKey");
		Gadgets.framehandle(F, M)
	ELSE Gadgets.framehandle(F, M)
	END
END FrameAttr;

PROCEDURE FrameLink (F: Frame; VAR M: Objects.LinkMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "VPos" THEN M.obj := F.vPos; M.res := 0
		ELSIF M.name = "VRange" THEN M.obj := F.vMax; M.res := 0
		ELSIF M.name = "HPos" THEN M.obj := F.hPos; M.res := 0
		ELSIF M.name = "HRange" THEN M.obj := F.hMax; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "VPos" THEN
			IF M.obj # F.vPos THEN F.vPos := M.obj; SetVPos(F, FALSE) END;
			M.res := 0
		ELSIF M.name = "VRange" THEN
			IF M.obj # F.vMax THEN F.vMax := M.obj; SetVRange(F) END;
			M.res := 0
		ELSIF M.name = "HPos" THEN
			IF M.obj # F.hPos THEN F.hPos := M.obj; SetHPos(F) END;
			M.res := 0
		ELSIF M.name = "HRange" THEN
			IF M.obj # F.hMax THEN F.hMax := M.obj; SetHRange(F) END;
			M.res := 0
		ELSIF M.name = "Model" THEN
			IF M.obj # F.obj THEN
				F.obj := M.obj;
				F.lines.prev := F.lines; F.lines.next := F.lines;
				UpdateModel(F)
			END;
			M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("VPos"); M.Enum("VRange"); M.Enum("HPos"); M.Enum("HRange");
		Gadgets.framehandle(F, M)
	ELSE Gadgets.framehandle(F, M)
	END
END FrameLink;

PROCEDURE FrameBind (F: Frame; VAR M: Objects.BindMsg);
BEGIN
	IF F.vPos # NIL THEN F.vPos.handle(F.vPos, M) END;
	IF F.vMax # NIL THEN F.vMax.handle(F.vMax, M) END;
	IF F.hPos # NIL THEN F.hPos.handle(F.vPos, M) END;
	IF F.hMax # NIL THEN F.hMax.handle(F.vMax, M) END;
	Gadgets.framehandle(F, M)
END FrameBind;

(** Standard procedures *) 
PROCEDURE CopyFrame* (VAR M: Objects.CopyMsg; from, to: Frame);
VAR L, nL: Line;
BEGIN
	to.do := from. do; to.sel := FALSE; to.car := FALSE; to.state0 := from.state0;
	to.tab := from.tab; to.fnt := from.fnt;
	to.textC := from.textC; to.pointC := from.pointC; to.backC := from.backC;
	to.left := from.left; to.top := from.top; to.right := from.right; to.bottom := from.bottom;
	to.R := NIL;
	NEW(nL); nL.key := MIN(LONGINT); nL.n := -1; nL.lev := 0; nL.hasSub := FALSE;
	to.lines := nL;
	L := from.lines.next;
	WHILE L # from.lines DO
		NEW(nL.next);
		nL.next^ := L^; nL.next.prev := nL; nL := nL.next;
		nL.sel := FALSE;
		L := L.next
	END;
	nL.next := to.lines; to.lines.prev := nL;
	to.first := to.lines.next;
	to.vPos := Gadgets.CopyPtr(M, from.vPos);
	to.vMax := Gadgets.CopyPtr(M, from.vMax);
	to.hPos := Gadgets.CopyPtr(M, from.hPos);
	to.hMax := Gadgets.CopyPtr(M, from.hMax);
	Gadgets.CopyFrame(M, from, to)
END CopyFrame;

PROCEDURE StoreFrame (F: Frame; VAR M: Objects.FileMsg);
VAR L: Line;
BEGIN
	Gadgets.framehandle(F, M);
	Files.WriteNum(M.R, Version);
	Files.WriteSet(M.R, F.state0);
	Files.WriteInt(M.R, F.backC); Files.WriteInt(M.R, F.textC); Files.WriteInt(M.R, F.pointC);
	Files.WriteInt(M.R, F.tab); Files.WriteInt(M.R, F.hoff); Files.WriteInt(M.R, F.levs);
	Files.WriteString(M.R, F.fnt.name);
	Files.WriteInt(M.R, F.top); Files.WriteInt(M.R, F.bottom);
	Files.WriteInt(M.R, F.left); Files.WriteInt(M.R, F.right);
	L := F.lines.next;
	WHILE L # F.lines DO
		Files.WriteInt(M.R, L.n); Files.WriteInt(M.R, L.lev); Files.WriteLInt(M.R, L.key);
		Files.WriteBool(M.R, L.hasSub); Files.WriteBool(M.R, L.folded);
		L := L.next
	END;
	Files.WriteInt(M.R, -1);
	Files.WriteInt(M.R, F.first.n);
	Gadgets.WriteRef(M.R, F.lib, F.vPos);
	Gadgets.WriteRef(M.R, F.lib, F.vMax);
	Gadgets.WriteRef(M.R, F.lib, F.hPos);
	Gadgets.WriteRef(M.R, F.lib, F.hMax)
END StoreFrame;

PROCEDURE LoadFrame (F: Frame; VAR M: Objects.FileMsg);
VAR L: Line; ver: LONGINT; n: INTEGER; fntname: ARRAY 32 OF CHAR;
BEGIN
	Gadgets.framehandle(F, M);
	Files.ReadNum(M.R, ver);
	IF ver >= 1 THEN
		Files.ReadSet(M.R, F.state0);
		Files.ReadInt(M.R, F.backC); Files.ReadInt(M.R, F.textC); Files.ReadInt(M.R, F.pointC);
		Files.ReadInt(M.R, F.tab); Files.ReadInt(M.R, F.hoff); Files.ReadInt(M.R, F.levs);
		Files.ReadString(M.R, fntname); F.fnt := Fonts.This(fntname);
		Files.ReadInt(M.R, F.top); Files.ReadInt(M.R, F.bottom);
		Files.ReadInt(M.R, F.left); Files.ReadInt(M.R, F.right);
		Files.ReadInt(M.R, n);
		L := F.lines;
		WHILE n # -1 DO
			NEW(L.next); L.next.prev := L; L := L.next;
			L.n := n; Files.ReadInt(M.R, L.lev); Files.ReadLInt(M.R, L.key);
			Files.ReadBool(M.R, L.hasSub); Files.ReadBool(M.R, L.folded);
			Files.ReadInt(M.R, n)
		END;
		F.lines.prev := L; L.next := F.lines;
		Files.ReadInt(M.R, n);
		L := F.lines; REPEAT L := L.next UNTIL (L.n = n) OR (L = F.lines);
		F.first := L;
		Gadgets.ReadRef(M.R, F.lib, F.vPos);
		Gadgets.ReadRef(M.R, F.lib, F.vMax);
		Gadgets.ReadRef(M.R, F.lib, F.hPos);
		Gadgets.ReadRef(M.R, F.lib, F.hMax)
	END
END LoadFrame;

PROCEDURE FrameHandler* (F: Objects.Object; VAR M: Objects.ObjMsg);
VAR F0: Frame; Q: Display3.Mask; T: Texts.Text; x, y, w, h: INTEGER;
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
									RestoreFrame(F, Q, x, y, w, h)
								END
							ELSIF M.device = Display.printer THEN PrintFrame(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF M.id = Oberon.track THEN
									IF (M.keys # {}) & Gadgets.InActiveArea(F, M) THEN
										Oberon.RemoveMarks(x, y, w, h);
										IF M.keys = {0} THEN TrackSelection(F, x, y, M)
										ELSIF M.keys = {1} THEN TrackPoint(F, x, y, M)
										ELSIF M.keys = {2} THEN TrackCaret(F, x, y, M)
										END
									ELSE Gadgets.framehandle(F, M)
									END
							ELSIF (M.id = Oberon.consume) & F.car THEN Consume(F, x, y, M)
							END
						END
					ELSIF M IS Oberon.ControlMsg THEN
						WITH M: Oberon.ControlMsg DO
							IF M.id = Oberon.neutralize THEN RemoveCaret(F); RemoveSelection(F)
							ELSIF M.id = Oberon.defocus THEN RemoveCaret(F)
							END
						END
					ELSIF M IS Display.ControlMsg THEN
						WITH M: Display.ControlMsg DO
							IF M.id = Display.restore THEN
								RemoveSelection(F); UpdateModel(F); F.car := FALSE
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS CaretMsg THEN
						WITH M: CaretMsg DO
							Gadgets.MakeMask(F, x, y, M.dlink, Q);
							FlipCaret(F, Q, x, y, M.carY)
						END
					ELSIF M IS Gadgets.UpdateMsg THEN UpdateFrame(F, M(Gadgets.UpdateMsg))
					ELSIF M IS Oberon.SelectMsg THEN
						WITH M: Oberon.SelectMsg DO
							IF M.id = Oberon.get THEN
								IF F.sel & (M.time < F.time) THEN
									GetSelection(F, T);
									IF T.len > 0 THEN M.sel := F; M.text := T; M.beg := 0; M.end := T.len; M.time := F.time END
								END
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Oberon.ConsumeMsg THEN
						WITH M: Oberon.ConsumeMsg DO
							IF F.car & ~(locked IN F.state0) THEN
								InsertItems(F, M.text, M.beg, M.end, F.carloc.line);
								SetCaret(F, F.carloc.line, LocatePos(F, F.carloc.line))
							END
						END
					ELSIF M IS Display.ConsumeMsg THEN Gadgets.framehandle(F, M)
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
		ELSIF M IS Objects.AttrMsg THEN FrameAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.LinkMsg THEN FrameLink(F, M(Objects.LinkMsg))
		ELSIF M IS Objects.BindMsg THEN FrameBind(F, M(Objects.BindMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN StoreFrame(F, M)
				ELSIF M.id = Objects.load THEN LoadFrame(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE
					NEW(F0); F.stamp := M.stamp; F.dlink := F0;
					CopyFrame(M, F, F0); M.obj := F0
				END
			END
		ELSE Gadgets.framehandle(F, M)
		END
	END
END FrameHandler;

PROCEDURE InitFrame* (F: Frame);
VAR L: Line;
BEGIN
	F.W := 100; F.H := 100; F.handle := FrameHandler; F.do := methods;
	NEW(L); L.next := L; L.prev := L;
	L.hasSub := FALSE; L.lev := 0; L.n := -1; L.key := MIN(LONGINT);
	F.lines := L; F.first := L;
	F.state0 := {multisel, exponpoint}; F.R := NIL; F.car := FALSE; F.sel := FALSE;
	F.left := 4; F.top := 4; F.right := 2; F.bottom := 2;
	F.backC := Display3.textbackC; F.textC := Display3.textC; F.pointC := F.textC;
	F.hoff := 0; F.levs := 0; F.tab := 10; F.fnt := Fonts.Default
END InitFrame;

PROCEDURE NewFrame*;
VAR F: Frame;
BEGIN
	NEW(F); InitFrame(F); Objects.NewObj := F
END NewFrame;

(* ------------ Commands to create list with scrollbar(s) ------------ *)
PROCEDURE MakeSimpleList (frame, model: ARRAY OF CHAR; VAR P: Display.Frame; VAR F: Frame; VAR vBar: Display.Frame);
VAR obj: Objects.Object;
BEGIN
	F := NIL; P := NIL; vBar := NIL;
	obj := Gadgets.CreateObject(frame);
	IF (obj # NIL) & (obj IS Frame) THEN
		F := obj(Frame);
		obj := Gadgets.CreateObject("Organizer");
		IF obj # NIL THEN
			P := obj(Display.Frame);
			Attributes.SetBool(P, "Flat", TRUE);
			Attributes.SetInt(P, "Border", 0);
	
			Links.SetLink(F, "Model", Gadgets.CreateObject(model));
			F.X := 0; F.Y := 0; P.W := F.W; P.H := F.H;
	
			obj := Gadgets.CreateObject("Scrollbars.New");
			IF obj # NIL THEN
				Links.SetLink(F, "VPos", Gadgets.CreateObject("Integer"));
				Links.SetLink(F, "VRange", Gadgets.CreateObject("Integer"));
				vBar := obj(Display.Frame);
				Links.SetLink(vBar, "Min", F.vMax);
				Links.SetLink(vBar, "Model", F.vPos);
				vBar.X := P.W; vBar.Y := 0; vBar.H := F.H; INC(P.W, vBar.W);
				Attributes.SetInt(vBar, "Max", 0); Attributes.SetBool(vBar, "HeavyDrag", TRUE)
			END;
			F.slink := vBar
		END
	END
END MakeSimpleList;

PROCEDURE Integrate (P, F: Display.Frame);
VAR C: Display.ConsumeMsg;
BEGIN
	C.id := Display.drop; C.x := 0; C.y := 0; C.obj := F;
	C.u := 0; C.v := -P.H; C.res := -1;
	P.handle(P, C);
	Attributes.SetBool(P, "Locked", TRUE);
	Gadgets.Integrate(P)
END Integrate;

(** Integrates a list with a vert. scrollbar at caret position
	Usage: ListGadgets.InsertVScrollList <frame> <model> ~
*)
PROCEDURE InsertVScrollList*;
VAR P, vBar: Display.Frame; F: Frame; str, wStr: ARRAY 16 OF CHAR; fName: ARRAY 32 OF CHAR; S: Attributes.Scanner;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
	IF S.class = Attributes.Name THEN COPY(S.s, fName); Attributes.Scan(S)
	ELSE fName := ""
	END;
	IF S.class = Attributes.Name THEN
		MakeSimpleList(fName, S.s, P, F, vBar);
		IF vBar # NIL THEN
			Strings.IntToStr(-vBar.W, wStr);
			str := ""; Strings.Append(str, wStr); Strings.Append(str, " 0 0 0");
			Attributes.SetString(vBar, "Constraints", str)
		END;
		IF F # NIL THEN
			Strings.IntToStr(P.W - F.W, wStr);
			str := "0 0 "; Strings.Append(str, wStr); Strings.Append(str, " 0");
			Attributes.SetString(F, "Constraints", str);
			Integrate(P, F)
		END
	END
END InsertVScrollList;

(** Integrates a list with a horiz. and vert. scrollbar at caret position
	Usage: ListGadgets.InsertHVScrollList <frame> <model> ~
*)
PROCEDURE InsertHVScrollList*;
VAR P, hBar, vBar: Display.Frame; F: Frame; obj: Objects.Object; str, wStr: ARRAY 16 OF CHAR; fName: ARRAY 32 OF CHAR;
		S: Attributes.Scanner;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
	IF S.class = Attributes.Name THEN COPY(S.s, fName); Attributes.Scan(S)
	ELSE fName := ""
	END;
	IF S.class = Attributes.Name THEN
		MakeSimpleList(fName, S.s, P, F, vBar);
		IF F # NIL THEN
			obj := Gadgets.CreateObject("Scrollbars.New");
			IF obj # NIL THEN
				Links.SetLink(F, "HPos", Gadgets.CreateObject("Integer"));
				Links.SetLink(F, "HRange", Gadgets.CreateObject("Integer"));

				hBar := obj(Display.Frame);
				Attributes.SetInt(hBar, "Min", 0); Attributes.SetBool(hBar, "HeavyDrag", TRUE);
				Attributes.SetBool(hBar, "Vertical", FALSE);
				Links.SetLink(hBar, "Max", F.hMax);
				Links.SetLink(hBar, "Model", F.hPos);
				hBar.X := -hBar.H; hBar.Y := 0; hBar.W := F.W; INC(P.H, hBar.H);
				(* constrinat *)
				str := "0 "; Strings.IntToStr(-hBar.H, wStr); Strings.Append(str, wStr); Strings.AppendCh(str, " ");
				Strings.IntToStr(P.W - hBar.W, wStr); Strings.Append(str, wStr); Strings.Append(str, " 0");
				Attributes.SetString(hBar, "Constraints", str);
				hBar.slink := vBar; F.slink := hBar
			END;
			
			IF vBar # NIL THEN
				Strings.IntToStr(-vBar.W, wStr);
				str := ""; Strings.Append(str, wStr); Strings.Append(str, " 0 0 ");
				Strings.IntToStr(P.H - vBar.H, wStr); Strings.Append(str, wStr);
				Attributes.SetString(vBar, "Constraints", str);
			END;

			Strings.IntToStr(P.W - F.W, wStr);
			str := "0 0 "; Strings.Append(str, wStr); Strings.AppendCh(str, " ");
			Strings.IntToStr(P.H - F.H, wStr);
			Strings.Append(str, wStr);
			Attributes.SetString(F, "Constraints", str);
			Integrate(P, F)
		END
	END
END InsertHVScrollList;

BEGIN
	Texts.OpenWriter(W);
	NEW(pointText); Texts.Open(pointText, "");

	WaitTime := 75 * Input.TimeUnit DIV 1000; mayscroll := Oberon.Time();

	NEW(methods);
	methods.GetRider := GetStandardRider;
	methods.Format := FormatLine; methods.Display := DisplayLine;
	methods.PrintFormat := PrintFormatLine; methods.Print := PrintLine
END ListGadgets.

(*
selections:
1:	oL	xxxxxxx	2:	oL	-------	3:	nL	xxxxxxx	4:	nL	-------
	nL	-------		nL	xxxxxxx		oL	-------		oL	xxxxxxx

5:		xxxxxxx	6:	oL	-------	7:		xxxxxxx	8:	nL	-------
	oL	-------		nL	-------		nL	-------		oL	-------
	nL	-------			xxxxxxx		oL	-------			xxxxxxx

9:	oL	-------	10:	nL	-------
		xxxxxxx			xxxxxxx
	nL	-------		oL	-------

1: oL.next -> nL.next	2: oL -> nL	3: nL.next -> oL.next	4: nL -> oL
5: oL.next -> nL.next	6: oL -> nL	7: nL.next -> oL.next	8: nL -> oL
9: oL -> nL.next (invert first)	10: nL -> oL.next (invert first)

scrolling:
- down:	dline > 0 =>	dy > 0,	new lines come at bottom
- up:	dline < 0 =>	dy < 0,	new lines come on top
*)