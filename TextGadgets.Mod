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

MODULE TextGadgets; (** portable *)

(* to do: *)
(*
	24.3.94 - Font cache for metric files optimized
	5.4.94 - Added TAB support
		- storing of TABs
	4.5.94 - Improved metric handling
	5.5.94 - added locking
	5.8.94 - improved printing of large boxes
	8.8.94 - increase line spacing to 120%
	18.4.95 - fixed DisplayLine delete
	7.6.95 - fixed updating of shared styles. Shared styles show their names now L.O
	16.11.95 - Pagebreak styles no remain visible
	15.12.95 - added popuphook (thanks tk)
	15.3.96 - WYSIWYG line breaks
	27.6.96 - added Tabs, Left, Width attributes
	29.7.96 - fixed bug in Format (printer metrics)
	22.5.97 - fixed invertC (thanks mad)
*)

IMPORT Display3, TextGadgets0, Objects, Display, Gadgets, Texts, Oberon, Fonts, Files, Printer, Effects, Printer3, Input, Strings;

CONST
	left* = 1; middle* = 2; right* = 3; pad* = 4; pagebreak* = 5; wysiwyg* = 6; span* = 7; (* style modes *)
	
	(* Frame controls *)
	nocontrol* = 1;
	
	writemode = Display.paint;
	replace = 3; delete = 2; insert = 1; change = 0; (* Text operations *)
	
	MaxTabs = 32;
	
	markerH = 4;
	boxdsr = 3; (* standard descender for boxes *)
	
TYPE
	Style* = POINTER TO StyleDesc;
	StyleDesc* = RECORD (Gadgets.FrameDesc)
		text*: Texts.Text;
		mode*: SET;
		leftM*, width*: INTEGER;
		noTabs*: SHORTINT;
		tab*: ARRAY MaxTabs OF INTEGER;
	END;
	
	Control* = POINTER TO ControlDesc;
	ControlDesc* = RECORD (Gadgets.FrameDesc)
	END;
	
	Frame* = POINTER TO FrameDesc;
	FrameDesc* = RECORD (TextGadgets0.FrameDesc)
		control*: SET; (* lower bits give the default style *)
	END;

VAR
	methods*: TextGadgets0.Methods;
	macroHook*: Objects.Handler;
	popupHook*: Objects.Handler;

	lastfont: Fonts.Font; lastlib: Fonts.Font; (* for font lookup *)
	
	dummy: Fonts.Char;
    BoxPat: ARRAY 12 OF SET;
    
    stylefnt: Fonts.Font; (* only loaded when shared styles are used *)
    
    dummyF: Display.Frame; dummydlink: Objects.Object; dx, dy: INTEGER;
    dummyT: TextGadgets0.Frame; dTx, dTy: INTEGER;
	dummyM: Display3.Mask;

PROCEDURE ^newStyle*(): Style;

PROCEDURE Visible(F: Frame; obj: Objects.Object): BOOLEAN;
BEGIN
	IF obj IS Control THEN RETURN ~(nocontrol IN F.control)
	ELSIF obj IS Style THEN
		RETURN (obj IS Style) & (pagebreak IN obj(Style).mode) OR ~(nocontrol IN F.control)
	ELSE RETURN TRUE
	END
END Visible;

PROCEDURE PrintVisible(F: Frame; obj: Objects.Object): BOOLEAN;
BEGIN RETURN ~(obj IS Control)
END PrintVisible;

PROCEDURE FindStyle*(T: Texts.Text; beg: LONGINT): Style;
VAR F: Texts.Finder; obj: Objects.Object; style: Style;
BEGIN
	Texts.OpenFinder(F, T, 0); style := NIL;
	WHILE ~F.eot & (F.pos <= beg) DO
		Texts.FindObj(F, obj); IF (obj # NIL) & (obj IS Style) THEN style := obj(Style) END
	END;
	RETURN style
END FindStyle;

PROCEDURE Max(x, y: INTEGER): INTEGER;
BEGIN IF x > y THEN RETURN x; ELSE RETURN y; END;
END Max;

PROCEDURE Below(x, y: INTEGER): INTEGER;
BEGIN
	IF x < y THEN RETURN y - x; ELSE RETURN 0 END;
END Below;

PROCEDURE Above(x, y: INTEGER): INTEGER;
BEGIN
	IF x > y THEN RETURN x - y; ELSE RETURN 0 END;
END Above;

PROCEDURE CurStyle(F: Frame; L: TextGadgets0.Line; VAR mode: SET; VAR leftM, width: INTEGER);
VAR style: Style;
BEGIN
	IF (L.obj # NIL) & (L.obj IS Style) THEN
		style := L.obj(Style);
		mode := style.mode;
		leftM := style.leftM;
		width := style.width;
	ELSE (* default style *)
		mode := {left}; leftM := 0; width := 1024
	END
END CurStyle;

(* indentation from leftM *)
PROCEDURE DisplayParam(F: Frame; L: TextGadgets0.Line; VAR leftM, offset, width, a, b: INTEGER);
VAR mode: SET;
BEGIN
	CurStyle(F, L, mode, leftM, width);
	IF middle IN mode THEN offset := (width - L.w) DIV 2
	ELSIF right IN mode THEN offset := width - L.w
	ELSE offset := 0
	END;
	IF offset < 0 THEN offset := 0 END;
	
	IF (pad IN mode) & (L.spaces > 0) THEN
		a := (width - L.w) DIV L.spaces; b := (width - L.w) MOD L.spaces;
	ELSE a := 0; b := 0;
	END;
	IF L.extra = 1 THEN leftM := 0; offset := 0; END; (* !! special hack for styles *)
	L.left := F.left + leftM + offset;
	L.right := F.left + leftM + offset + L.w + a * L.spaces + b + TextGadgets0.eolW;
	IF L.right > F.W - F.right THEN L.right := F.W - F.right END
END DisplayParam;

PROCEDURE Dev(x: INTEGER): INTEGER;
BEGIN RETURN SHORT(LONG(x) * Display.Unit DIV Printer.Unit)
END Dev;

PROCEDURE PrintParam(F: Frame; L: TextGadgets0.Line; VAR leftM, offset, width, a, b: INTEGER);
VAR mode: SET;
BEGIN
	CurStyle(F, L, mode, leftM, width); width := Dev(width);
	IF middle IN mode THEN offset := (width - L.w) DIV 2
	ELSIF right IN mode THEN offset := width - L.w
	ELSE offset := 0
	END;
	IF (pad IN mode) & (L.spaces > 0) THEN
		a := (width - L.w) DIV L.spaces; b := (width - L.w) MOD L.spaces;
	ELSE a := 0; b := 0;
	END;
	IF L.extra = 1 THEN leftM := 0; offset := 0; END; (* !! special hack for styles *)
END PrintParam;

PROCEDURE Background(F: TextGadgets0.Frame; R: Display3.Mask; X, Y, x, y, w, h: INTEGER);
VAR cx, cy, cw, ch: INTEGER;
BEGIN
	WITH F: Frame DO
		IF ~(Gadgets.transparent IN F.state) THEN
			cx := R.X; cy := R.Y; cw := R.W; ch := R.H;
			Display3.AdjustMask(R, X + x, Y + F.H - 1 + y, w, h);
			Oberon.RemoveMarks(R.X, R.Y, R.W, R.H);
			IF TextGadgets0.mayscroll IN F.state0 THEN
				IF TextGadgets0.flat IN F.state0 THEN
					Display3.ReplConst(R, Display3.textbackC, X, Y, 14, F.H, Display.replace);
					Display3.ReplConst(R, F.col, X+14+1, Y, F.W-14-1, F.H, Display.replace)
				ELSE
					Display3.ReplConst(R, Display3.textbackC, X+1, Y+1, 14, F.H-1, Display.replace);
					Display3.ReplConst(R, F.col, X+14+1, Y, F.W-14-1-1, F.H, Display.replace);
					Display3.Rect3D(R, Display3.topC, Display3.bottomC, X, Y, F.W, F.H, 1, Display.replace)
				END
			ELSE
				IF TextGadgets0.flat IN F.state0 THEN
					Display3.ReplConst(R, F.col, X, Y, F.W, F.H, Display.replace)
				ELSE
					Display3.FilledRect3D(R, Display3.topC, Display3.bottomC, F.col, X, Y, F.W, F.H, 1, Display.replace)
				END
			END;
			R.X := cx; R.Y := cy; R.W := cw; R.H := ch;
		END
	END
END Background;

PROCEDURE InSync(F: TextGadgets0.Frame; L, L1: TextGadgets0.Line): BOOLEAN;
BEGIN
	RETURN (L.obj = L1.obj) OR (L1.extra = 1);
END InSync;

PROCEDURE ClearCache;
BEGIN lastfont := NIL; lastlib := NIL;
END ClearCache;

PROCEDURE Lookup(L: Fonts.Font; ch: CHAR; VAR minY, maxY, dx, y, h: INTEGER);
VAR obj: Objects.Object; metric: Fonts.Font;
BEGIN
	IF L = lastfont THEN metric := lastlib
	ELSE
		metric := Printer.GetMetric(L);
		lastlib := metric; lastfont := L
	END;
	IF metric # NIL THEN
		metric.GetObj(metric, ORD(ch), obj);
		WITH obj: Fonts.Char DO
			minY := metric.minY; maxY := metric.maxY; dx := obj.dx; y := obj.y; h := obj.h
		END
	ELSE (* scale display font *)
		L.GetObj(L, ORD(ch), obj);
		WITH obj: Fonts.Char DO
			minY := Dev(L.minY); maxY := Dev(L.maxY); dx := Dev(obj.dx); y := Dev(obj.y); h := Dev(obj.h)
		END
	END;
END Lookup;

PROCEDURE Voff(obj: Objects.Object): INTEGER;
VAR A: Objects.AttrMsg;
BEGIN
	A.id := Objects.get; A.name := "LineupHY"; A.class := Objects.Inval; A.res := -1;
	obj.handle(obj, A);
	IF (A.res >= 0) & (A.class = Objects.Int) THEN RETURN -SHORT(A.i)
	ELSE RETURN 0
	END
END Voff;

PROCEDURE TabSize(obj: Objects.Object; w: INTEGER; VAR dx, pdx: INTEGER);
VAR t: INTEGER;
BEGIN
	IF (obj # NIL) & (obj IS Style) THEN
		WITH obj: Style DO
			IF (obj.noTabs > 0) & (left IN obj.mode) THEN
				t := 0;
				WHILE (t # obj.noTabs) & (w > obj.tab[t]) DO INC(t) END;
				IF t < obj.noTabs THEN
					dx := obj.tab[t] - w + 1; pdx := Dev(dx)
				END
			END
		END
	END
END TabSize;

(* boxes must be inserted in sequence !*)
PROCEDURE Format(F: TextGadgets0.Frame; org: LONGINT; L: TextGadgets0.Line);
VAR obj, Tobj: Objects.Object; R: Texts.Reader; ch: CHAR; box: TextGadgets0.Box; style: SET;
	(* adjust format *)
	maxW, lastw, lastasr, lastdsr, leftM: INTEGER; lastlen: LONGINT; lastbox: TextGadgets0.Box;
	(* WYSIWYG *)
	d, odx, dx, pmaxW, devw, pw: INTEGER; 
	
	objw: INTEGER; lastfnt: Objects.Library;
BEGIN
	IF (org < 0) OR (org > F.text.len) THEN HALT(99) END;
	WITH F: Frame DO
		L.obj := FindStyle(F.text, org);
		L.asr := 10; L.dsr := 3; L.h := 13; L.w := 0; L.len := 0; L.eot := FALSE; (*L.box := NIL; do not! see below! *)
		box := NIL; L.extra := 0;
		lastlen := -1; lastw := 0; lastasr := L.asr; lastdsr := L.dsr; L.spaces := 0; lastbox := NIL;
		CurStyle(F, L, style, leftM, maxW); pmaxW := Dev(maxW); pw := 0; lastfnt := NIL;
		Texts.OpenReader(R, F.text, org); 
		LOOP
			Texts.Read(R, ch);
			IF R.eot THEN INC(L.len); (* INC(L.w, TextGadgets0.eolW); *)
				L.spaces := 0; L.eot := TRUE;
				IF box # NIL THEN box.next := NIL ELSE L.box := NIL END; (* cut off! *)
				EXIT
			END;
			INC(L.len);
			R.lib.GetObj(R.lib, ORD(ch), obj);
			IF obj # NIL THEN
				IF obj IS Fonts.Char THEN
					WITH obj: Fonts.Char DO
						dx := obj.dx; (* save, is destroyed in metric Lookup *)
						IF R.voff # 0 THEN
							L.dsr := Max(L.dsr, Below(R.voff + obj.y, 0));
							L.asr := Max(L.asr, Above(R.voff + obj.y + obj.h, 0));
							L.h := L.dsr + L.asr;
						END;

						IF R.lib # lastfnt THEN
							L.dsr := Max(L.dsr, -R.lib(Fonts.Font).minY);
							L.asr := Max(L.asr, R.lib(Fonts.Font).maxY * 120 DIV 100);
							lastfnt := R.lib;
							L.h := L.dsr + L.asr;
							Lookup(R.lib(Fonts.Font), ch, d, d, odx, d, d); (* get printer size *)
						ELSE
							(* invariant: lastlib is the metric font *)
							IF lastlib # NIL THEN
								lastlib.GetObj(lastlib, ORD(ch), Tobj);
								WITH Tobj: Fonts.Char DO odx := Tobj.dx END
							ELSE (* scale display font *)
								odx := Dev(dx)
							END
						END;	

						IF (L.obj # NIL) & ~(wysiwyg IN L.obj(Style).mode) THEN odx := 0 END;
						
						IF ch = 0DX THEN (* INC(L.w, TextGadgets0.eolW);*) L.spaces := 0; 
							IF box # NIL THEN box.next := NIL ELSE L.box := NIL END; (* cut off! *)
							EXIT
						END;
						
						IF dx > 0 THEN
							IF ch = 09X THEN (* TAB *)
								TabSize(L.obj, L.w, dx, odx);
								pw := Dev(L.w + dx) - odx
							END;
							
							IF (L.w + dx > maxW) OR (pw + odx > pmaxW) THEN
								IF lastlen > 0 THEN
									L.len := lastlen; L.w := lastw; L.asr := lastasr; L.dsr := lastdsr; L.h := L.asr + L.dsr;
									DEC(L.spaces); box := lastbox;
								 ELSE DEC(L.len);
								 END;
								 IF box # NIL THEN box.next := NIL ELSE L.box := NIL END; (* cut off! *)
								EXIT;
							ELSE
								IF (ch = " ") OR (ch = 09X) THEN
									lastw := L.w; lastasr := L.asr; lastdsr := L.dsr;  lastlen := Texts.Pos(R) - org; INC(L.spaces); lastbox := box;
								END;
								INC(L.w, dx); INC(pw, odx);
							END
						ELSE
							L.dsr := Max(L.dsr, -dummy.y); 
							L.asr := Max(L.asr, dummy.h);
							L.h := L.dsr + L.asr;
							INC(L.w, dummy.dx); INC(pw, Dev(dummy.dx));
						END
					END
				ELSIF obj IS Display.Frame THEN
					WITH obj: Display.Frame DO
						IF Visible(F, obj) THEN objw := obj.W ELSE objw := 0 END;
						
						IF (obj IS Style) & (L.len # 1) THEN (* not first character is style *)
							DEC(L.len); (* INC(L.w, TextGadgets0.eolW); *)
							IF box # NIL THEN box.next := NIL ELSE L.box := NIL END; (* cut off! *)
							EXIT 
						END;
						
						IF (L.obj # NIL) & (wysiwyg IN L.obj(Style).mode) THEN devw := Dev(objw) ELSE devw := 0 END;
						
						IF ((L.w + objw > maxW) OR (pw + devw > pmaxW)) & ~(obj IS Style) & (L.len # 1) THEN
							IF lastlen > 0 THEN
								L.len := lastlen; L.w := lastw; L.asr := lastasr; L.dsr := lastdsr; L.h := L.asr + L.dsr;
								DEC(L.spaces); box := lastbox;
							 ELSE DEC(L.len)
							 END;
							 IF box # NIL THEN box.next := NIL ELSE L.box := NIL END; (* cut off! *)
							EXIT
						END;
						(* if a box data structure exists, it should be used again. The line may be formatted
							a few times and might not be displayed. Actual box coordinates are set by the
							display routine. box always set to the last box processed *)
						IF box = NIL THEN (* no last box processed *)
							box := L.box; (* get box out of line descriptor *)
							IF box = NIL THEN NEW(box); L.box := box (* create first box *) END; (* none exists *)
						ELSIF box.next  # NIL THEN box := box.next (* use box if available *)
						ELSE (* create a new box, extending the list *)
							NEW(box.next); box := box.next;
						END;
						box.org := L.len - 1; box.f := obj;
						(* do not set coordinates, kills data if this line won't be displayed:
							box.x := F.left + L.w;
						*)
						INC(L.w, objw); INC(pw, devw); box.voff := R.voff + Voff(obj);
						L.dsr := Max(L.dsr, Below(box.voff, 0) + boxdsr);
						L.asr := Max(L.asr, Above(box.voff + obj.H, 0));
						L.h := L.dsr + L.asr;
						
						IF (obj IS Style) THEN
							obj(Style).text := F.text;
							(* INC(L.w, TextGadgets0.eolW); *) L.spaces := 0; L.extra := 1; L.obj := obj;
							IF (nocontrol IN F.control) & ~(pagebreak IN obj(Style).mode) THEN L.h := 0; L.asr := 0; L.dsr := 0 END; (* not visible *)
							box.next := NIL; (* cut off *)
							EXIT 
						END
					END (* with *)
				ELSE
					L.dsr := Max(L.dsr, -dummy.y); 
					L.asr := Max(L.asr, dummy.h);
					L.h := L.dsr + L.asr;
					INC(L.w, dummy.dx); INC(pw, Dev(dummy.dx));
				END
			END
		END
	END;
END Format;

PROCEDURE PrinterTabSize(obj: Objects.Object; w: INTEGER; VAR dx, pdx: INTEGER);
VAR t: INTEGER;
BEGIN
	(* convert w back to display coordinates *)
	w := SHORT(LONG(w) * Printer.Unit DIV Display.Unit);
	IF (obj # NIL) & (obj IS Style) THEN
		WITH obj: Style DO
			IF (obj.noTabs > 0) & (left IN obj.mode) THEN
				t := 0;
				WHILE (t # obj.noTabs) & (w >= obj.tab[t]) DO INC(t) END;
				IF t < obj.noTabs THEN
					dx := obj.tab[t] - w + 1; pdx := Dev(dx)
				END
			END
		END
	END
END PrinterTabSize;

PROCEDURE PrintFormat(F: TextGadgets0.Frame; org: LONGINT; L: TextGadgets0.Line; VAR break: BOOLEAN);
VAR obj: Objects.Object; R: Texts.Reader; ch: CHAR; box: TextGadgets0.Box; style: SET;
	(* adjust format *)
	pmaxW, lastw, lastasr, lastdsr, leftM: INTEGER; lastlen: LONGINT; lastbox: TextGadgets0.Box;
	voff, minY, maxY, odx, oy, oh, dx, sw, maxW: INTEGER; 
BEGIN
	WITH F: Frame DO
		break := FALSE;
		L.obj := FindStyle(F.text, org);
		L.asr := Dev(10); L.dsr := Dev(3); L.h := L.asr + L.dsr; L.w := 0; L.len := 0; L.eot := FALSE; (*L.box := NIL; do not! see below! *)
		box := NIL; L.extra := 0;
		lastlen := -1; lastw := 0; lastasr := L.asr; lastdsr := L.dsr; L.spaces := 0; lastbox := NIL;
		CurStyle(F, L, style, leftM, maxW); pmaxW := Dev(maxW); sw := 0;
		Texts.OpenReader(R, F.text, org); 
		LOOP
			Texts.Read(R, ch);
			IF R.eot THEN INC(L.len); (* INC(L.w, TextGadgets0.eolW); *)
				L.spaces := 0; L.eot := TRUE;
				IF box # NIL THEN box.next := NIL ELSE L.box := NIL END; (* cut off! *)
				EXIT
			END;
			INC(L.len);
			R.lib.GetObj(R.lib, ORD(ch), obj);
			IF obj # NIL THEN
				IF obj IS Fonts.Char THEN
					WITH obj: Fonts.Char DO
						IF (L.obj # NIL) & (wysiwyg IN L.obj(Style).mode) THEN dx := obj.dx ELSE dx := 0 END;
						
						voff := Dev(R.voff);
						Lookup(R.lib(Fonts.Font), ch, minY, maxY, odx, oy, oh); (* get printer size *)
						IF ch = 09X THEN (* TAB *)
							PrinterTabSize(L.obj, L.w, dx, odx);
						END;
						L.dsr := Max(L.dsr, minY); L.dsr := Max(L.dsr, Below(voff + oy, 0));
						L.asr := Max(L.asr, maxY (* * 120 DIV 100 *)); L.asr := Max(L.asr, Above(voff + oy + oh, 0));
						L.h := L.dsr + L.asr;
						IF ch = 0DX THEN L.spaces := 0; 
							IF box # NIL THEN box.next := NIL ELSE L.box := NIL END; (* cut off! *)
							EXIT
						END;
						IF (L.w + odx > pmaxW) OR (sw + dx > maxW) THEN
							IF lastlen > 0 THEN
								L.len := lastlen; L.w := lastw; L.asr := lastasr; L.dsr := lastdsr; L.h := L.asr + L.dsr;
								DEC(L.spaces); box := lastbox;
							 ELSE DEC(L.len);
							 END;
							 IF box # NIL THEN box.next := NIL ELSE L.box := NIL END; (* cut off! *)
							EXIT;
						ELSE
							IF (ch = " ") OR (ch = 09X) THEN
								lastw := L.w; lastasr := L.asr; lastdsr := L.dsr;  lastlen := Texts.Pos(R) - org; INC(L.spaces); lastbox := box;
							END;
							INC(L.w, odx); INC(sw, dx)
						END;
					END
				ELSIF obj IS Display.Frame THEN
					WITH obj: Display.Frame DO
						IF PrintVisible(F, obj) THEN
							IF (obj IS Style) & (L.len # 1) THEN (* not first character is style *)
								DEC(L.len); (* INC(L.w, TextGadgets0.eolW); *)
								IF box # NIL THEN box.next := NIL ELSE L.box := NIL END; (* cut off! *)
								EXIT 
							END;
							IF (L.obj # NIL) & (wysiwyg IN L.obj(Style).mode) THEN dx := obj.W ELSE dx := 0 END;
							IF ((L.w + Dev(obj.W) > pmaxW) OR (sw + dx > maxW)) & ~(obj IS Style) & (L.len # 1)  THEN
								IF lastlen > 0 THEN
									L.len := lastlen; L.w := lastw; L.asr := lastasr; L.dsr := lastdsr; L.h := L.asr + L.dsr;
									DEC(L.spaces); box := lastbox;
								 ELSE DEC(L.len)
								 END;
								 IF box # NIL THEN box.next := NIL ELSE L.box := NIL END; (* cut off! *)
								EXIT
							END;
							(* if a box data structure exists, it should be used again. The line may be formatted
								a few times and might not be displayed. Actual box coordinates are set by the
								display routine. box always set to the last box processed *)
							IF box = NIL THEN (* no last box processed *)
								box := L.box; (* get box out of line descriptor *)
								IF box = NIL THEN NEW(box); L.box := box (* create first box *) END; (* none exists *)
							ELSIF box.next  # NIL THEN box := box.next (* use box if available *)
							ELSE (* create a new box, extending the list *)
								NEW(box.next); box := box.next;
							END;
							box.org := L.len - 1; box.f := obj;
							(* do not set coordinates, kills data if this line won't be displayed:
								box.x := F.left + L.w;
							*)
							INC(L.w, Dev(obj.W)); INC(sw, dx);
							box.voff := Dev(R.voff + Voff(obj));
							L.dsr := Max(L.dsr, Below(box.voff, 0) + Dev(boxdsr));
							L.asr := Max(L.asr, Above(box.voff + Dev(obj.H), 0));
							L.h := L.dsr + L.asr;
							
							IF (obj IS Style) THEN
								obj(Style).text := F.text;
								(* INC(L.w, TextGadgets0.eolW); *) L.spaces := 0; L.extra := 1; L.obj := obj;
								L.h := 0; L.asr := 0; L.dsr := 0;(* not visible *)
								box.next := NIL; (* cut off *)
								IF pagebreak IN obj(Style).mode THEN break := TRUE END;
								EXIT 
							END
						END (* visible *)
					END (* with *)
				ELSE
					L.dsr := Max(L.dsr, Dev(-dummy.y)); 
					L.asr := Max(L.asr, Dev(dummy.h));
					L.h := L.dsr + L.asr;
					INC(L.w, Dev(dummy.dx)); INC(sw, dummy.dx);
				END
			END
		END
	END;
END PrintFormat;

PROCEDURE ClipAgainst(VAR x, y, w, h: INTEGER; x1, y1, w1, h1: INTEGER);
VAR r, t, r1, t1: INTEGER;
BEGIN
	r := x + w - 1; r1 := x1 + w1 - 1; t := y + h - 1; t1 := y1 + h1 - 1;
	IF x < x1 THEN x := x1 END;
	IF y < y1 THEN y := y1 END;
	IF r > r1 THEN r := r1 END;
	IF t > t1 THEN t := t1 END;
	w := r - x + 1; h := t - y + 1;
END ClipAgainst;

PROCEDURE RestoreFrame0(x, y, w, h: INTEGER);
VAR D: Display.DisplayMsg;
BEGIN
	ClipAgainst(x, y, w, h, dummyM.X, dummyM.Y, dummyM.W, dummyM.H);
	D.device := Display.screen; D.id := Display.area; D.F := dummyF; D.x := dx  - dummyF.X; D.y := dy - dummyF.Y;
	D.u := x - dx; D.v := y - (dy + dummyF.H - 1) ; D.w := w; D.h := h;
	D.res := -1; Objects.Stamp(D); D.dlink := dummydlink;
	Gadgets.Send(dummyT, dTx, dTy, dummyF, D);
END RestoreFrame0;

PROCEDURE RestoreFrame(F: Frame; M: Display3.Mask; X, Y, x, y: INTEGER; f: Display.Frame; dlink: Objects.Object);
VAR dF: Display.Frame; dd: Objects.Object; dT: TextGadgets0.Frame; a, b, c, d: INTEGER; dM: Display3.Mask;
BEGIN
	dF := dummyF; dd := dummydlink; dT := dummyT; a := dx; b := dy; c := dTx; d := dTy; dM := dummyM; (* save *)
	
	dummyT := F; dummyF := f; dummydlink := dlink; dTx := X; dTy := Y; dx := x; dy := y; dummyM := M;
	Display3.EnumRect(M, x, y, f.W, f.H, RestoreFrame0);
	
	dummyF := dF; dummydlink := dd; dummyT := dT; dx := a; dy := b; dTx := c; dTy := d; dummyM := dM (* restore *)
END RestoreFrame;

PROCEDURE DisplayLine(F: TextGadgets0.Frame; M: Display3.Mask; x, y: INTEGER; org: LONGINT; L: TextGadgets0.Line; dlink: Objects.Object);
VAR X, Y: INTEGER; obj: Objects.Object; R: Texts.Reader; ch: CHAR; pos: LONGINT;
	RM: Display.ControlMsg; cx, cy, cw, cch: INTEGER; box: TextGadgets0.Box;
	(* formatting control *)
	leftM, offset, width, a, b, dx, d: INTEGER;
	spaces: INTEGER;
	
	(* optimize *)
	start: LONGINT;
BEGIN
	cx := M.X; cy := M.Y; cw := M.W; cch := M.H;
	WITH F: Frame DO
		
		(* L.obj := FindStyle(F.text, org); << jm*)
		DisplayParam(F, L, leftM, offset, width, a, b);
		
		start := 0;
		IF (L.draw > 0) & (a + b = 0) & ((L.obj = NIL) OR (left IN L.obj(Style).mode)) THEN (* optimize and no extra spaces *)
			start := L.draw;
		END;
		
		X := x + F.left + leftM + offset; Y := y + F.H - 1 + L.base;
		
		IF start = 0 THEN F.do.Background(F, M, x, y, F.left, L.base - L.dsr, F.W, L.h) END;
		Display3.AdjustMask(M, x + F.left, y, F.W - F.left - F.right, F.H);
		Texts.OpenReader(R, F.text, org); pos := org; box := L.box; spaces := L.spaces;
		LOOP
			Texts.Read(R, ch);
			IF R.eot THEN
				IF pos = start THEN F.do.Background(F, M, x, y, X - x, L.base - L.dsr, F.W, L.h); END;
				EXIT
			END;
			IF pos - org + 1 > L.len THEN
				F.do.Background(F, M, x, y, X - x, L.base - L.dsr, F.W, L.h); (* clean rest of the line *)
				EXIT
			END;
			R.lib.GetObj(R.lib, ORD(ch), obj);
			IF obj # NIL THEN
				IF obj IS Fonts.Char THEN
					WITH obj: Fonts.Char DO
						IF ch = 0DX THEN
							IF pos = start THEN F.do.Background(F, M, x, y, X - x, L.base - L.dsr, F.W, L.h); END;
							EXIT
						END;
						IF ch = " " THEN
							IF pos = start THEN F.do.Background(F, M, x, y, X - x, L.base - L.dsr, F.W, L.h); END;
							INC(X, obj.dx);
							IF spaces > 0 THEN INC(X, a) END; DEC(spaces); IF b > 0 THEN INC(X); DEC(b) END;
						ELSIF obj.dx > 0 THEN
							dx := obj.dx;
							IF ch = 09X THEN TabSize(L.obj, X - (x +  F.left + leftM + offset), dx, d) END;
							IF pos >= start THEN
								IF pos = start THEN
									F.do.Background(F, M, x, y, X - x, L.base - L.dsr, F.W, L.h);
								END;
								Display3.CopyPattern(M, LONG(R.col) MOD 256, obj.pat, X + obj.x, Y + obj.y + R.voff, writemode);
							END;
							INC(X, dx);
						ELSE
							IF pos = start THEN F.do.Background(F, M, x, y, X - x, L.base - L.dsr, F.W, L.h); END;
							Display3.CopyPattern(M, Display.FG, dummy.pat, X + dummy.x, Y + dummy.y, writemode);
							INC(X, dummy.dx)
						END
					END
				ELSIF obj IS Display.Frame THEN
					WITH obj: Display.Frame DO
						IF Visible(F, obj) THEN
							(* see *)
							IF box.f # obj THEN HALT(99) END;
							RM.id := Display.restore; RM.res := -1; Objects.Stamp(RM); RM.x := X - obj.X; RM.y := Y - obj.Y + box.voff;
							RM.dlink := dlink; RM.F := NIL; 
							Gadgets.Send(F, x, y, obj, RM);
							box.x := X - x;
							IF pos >= start THEN
								IF pos = start THEN F.do.Background(F, M, x, y, X - x, L.base - L.dsr, F.W, L.h); END;
								(*
								D.device := Display.screen; D.id := Display.full; D.F := NIL; D.x := X - obj.X; D.y := Y - obj.Y + box.voff;
								D.res := -1; Objects.Stamp(D); D.dlink := dlink;
								Gadgets.Send(F, x, y, obj, D);
								*)
								RestoreFrame(F, M, x, y, X, Y + box.voff, obj, dlink);
							END;
							INC(X, obj.W)
						ELSE
							IF box.f # obj THEN HALT(99) END;
							(*
							box.x := X - x
							*)
							(* not visible, set coordinates wrong *)
							box.x := -1;
							IF pos = start THEN F.do.Background(F, M, x, y, X - x, L.base - L.dsr, F.W, L.h); END;
						END; (* Visible *)
						box := box.next
					END (* with *)
				ELSE Display3.CopyPattern(M, Display.FG, dummy.pat, X + dummy.x, Y + dummy.y, writemode);
					INC(X, dummy.dx);
				END
			END;
			INC(pos)
		END
	END;
	M.X := cx; M.Y := cy; M.W := cw; M.H := cch
END DisplayLine;

PROCEDURE PrintLine(F: TextGadgets0.Frame; M: Display3.Mask; x, y: INTEGER; org: LONGINT; L: TextGadgets0.Line; dlink: Objects.Object);
VAR X, Y: INTEGER; obj: Objects.Object; R: Texts.Reader; ch: CHAR; pos: LONGINT;
	dx, odx, d: INTEGER; box: TextGadgets0.Box;
	(* formatting control *)
	leftM, offset, width, a, b: INTEGER;
	spaces: INTEGER;
	lastfnt: Objects.Library; lastvoff, lastcol: INTEGER; buf: ARRAY 1024 OF CHAR; bufp, pX, pY: INTEGER;
	P: Display.DisplayMsg;
	Fdlink, Mdlink: Objects.Object;
	RR: Display3.Mask; OM: Display3.OverlapMsg;
	
	PROCEDURE Put(ch: CHAR; fnt: Objects.Library; voff, col: INTEGER);
	VAR  d, dx: INTEGER;
	BEGIN
		IF (fnt # lastfnt) OR (voff # lastvoff) OR (col # lastcol) OR (ch = 0X) THEN (* new font or new vertical offset, break*)
			IF bufp > 0 THEN (* something in buffer *)
				buf[bufp] := 0X; Printer3.String(M, lastcol, pX, pY + Dev(lastvoff), lastfnt(Fonts.Font), buf, Display.paint);
				bufp := 0; (* clear buffer *)
			END;
			pX := X; pY := Y;
			IF ch = 0X THEN RETURN END;
			lastfnt := fnt; lastvoff := voff; lastcol := col
		END;
		IF fnt # NIL THEN
			buf[bufp] := ch; INC(bufp);
			Lookup(fnt(Fonts.Font), ch, d, d, dx, d, d); INC(X, dx)
		END
	END Put;
	
BEGIN
	WITH F: Frame DO
		lastfnt := NIL; lastvoff := 0; bufp := 0; pX := X; pY := Y; lastcol := Display.FG;
		
		L.obj := FindStyle(F.text, org);
		PrintParam(F, L, leftM, offset, width, a, b);
		X := x + Dev(leftM) + offset; Y := L.base;
		Texts.OpenReader(R, F.text, org); pos := org; box := L.box; spaces := L.spaces;
		LOOP
			Texts.Read(R, ch);
			IF R.eot THEN EXIT END;
			IF pos - org + 1 > L.len THEN EXIT END;
			R.lib.GetObj(R.lib, ORD(ch), obj);
			IF obj # NIL THEN
				IF obj IS Fonts.Char THEN
					WITH obj: Fonts.Char DO
						IF ch = 0DX THEN EXIT END;
						IF ch = " " THEN
							Put(ch, R.lib, R.voff, R.col); Put(0X, NIL, 0, 0);
							IF spaces > 0 THEN INC(X, a) END; DEC(spaces); IF b > 0 THEN INC(X); DEC(b) END;
							pX := X;
						ELSIF ch = 09X THEN (* TAB *)
							Put(0X, NIL, 0, 0);
							Lookup(R.lib(Fonts.Font), ch, d, d, odx, d, d);
							PrinterTabSize(L.obj, X - (x + Dev(leftM)), dx, odx);
							INC(X, odx);
							pX := X
						ELSE Put(ch, R.lib, R.voff, R.col)
						END
					END
				ELSIF obj IS Display.Frame THEN
					WITH obj: Display.Frame DO
						IF PrintVisible(F, obj) THEN
							(* see *)
							IF box.f # obj THEN HALT(99) END;
							box.x := X;
							IF ~(obj IS Style) & ~(obj IS Control) (* OR ~(nocontrol IN F.control) *)THEN
								Put(0X, NIL, 0, 0); (* print stuff so far *)
								NEW(RR); Display3.Open(RR); Display3.Add(RR, 0, -obj.H + 1, obj.W, obj.H);
								OM.F := obj; OM.M := RR; OM.x := 0; OM.y := 0; OM.dlink := NIL; OM.res := -1; obj.handle(obj, OM);
								
								P.F := NIL; P.device := Display.printer; P.id := Display.full; P.x := X; P.y := Y + box.voff;
								P.res := -1; P.dlink := dlink; Objects.Stamp(P);
								Fdlink := F.dlink; Mdlink := P.dlink; F.dlink := P.dlink; P.dlink := F;
								obj.handle(obj, P);
								P.dlink := Mdlink; F.dlink := Fdlink;
								lastcol := Display.FG;
								INC(X, Dev(obj(Display.Frame).W)); INC(pX, Dev(obj(Display.Frame).W)); (* ! offsets *)
							END;
							box := box.next
						END (* Visible *)
					END (* with *)
				ELSE Put(0X, NIL, 0, 0);
					INC(X, Dev(dummy.dx))
				END
			END;
			INC(pos)
		END
	END;
	Put(0X, NIL, 0, 0)
END PrintLine;

PROCEDURE FindLine(F: TextGadgets0.Frame; y, Y: INTEGER; VAR org: LONGINT; VAR L: TextGadgets0.Line);
BEGIN
	L := F.trailer.next; org := F.org;
	WHILE (L.next # F.trailer) & (Y < y + F.H - 1 + L.base - L.dsr) DO org := org + L.len; L := L.next; END;
END FindLine;

PROCEDURE LocateChar(F: TextGadgets0.Frame; x, y, X, Y: INTEGER; VAR loc: TextGadgets0.Loc);
VAR obj: Objects.Object; ox, dx: INTEGER; R: Texts.Reader; ch: CHAR; org: LONGINT;
	(* format *)
	leftM, offset, width, a, b, d: INTEGER;
BEGIN
	WITH F: Frame DO
		FindLine(F, y,  Y, org, loc.line); loc.org := org; loc.pos := org;
		
		loc.line.obj := FindStyle(F.text, org);
		DisplayParam(F, loc.line, leftM, offset, width, a, b);
		ox := x + F.left + leftM + offset;
		Texts.OpenReader(R, F.text, loc.pos);
		LOOP
			Texts.Read(R, ch);
			IF ((ch = 0DX) & (R.lib IS Fonts.Font)) OR R.eot THEN dx := TextGadgets0.eolW; EXIT; END;
			IF loc.pos - org + 1 > loc.line.len THEN dx := TextGadgets0.eolW; EXIT END;
			R.lib.GetObj(R.lib, ORD(ch), obj); dx := 0;
			IF obj # NIL THEN
				IF obj IS Fonts.Char THEN
					WITH obj: Fonts.Char DO
						IF ch = " " THEN
							IF (loc.line.spaces > 0) & (loc.pos = org +  loc.line.len - 1) THEN (* spaces has been adjusted *)
								dx := TextGadgets0.eolW; EXIT
							END;
							dx := obj.dx;
							INC(dx, a); IF b > 0 THEN INC(dx); DEC(b) END
						ELSIF ch = 09X THEN dx := obj.dx; TabSize(loc.line.obj, ox - (x + F.left + leftM + offset), dx, d)
						ELSIF obj.dx > 0 THEN dx := obj.dx
						ELSE dx := dummy.dx
						END
					END
				ELSIF obj IS Display.Frame THEN
					WITH obj: Display.Frame DO
						IF Visible(F, obj) THEN dx := obj.W;
							IF (obj IS Style) THEN EXIT END
						END
					END
				ELSE dx := dummy.dx
				END
			END;
			IF ox + dx > X THEN EXIT; END;
			INC(loc.pos); INC(ox, dx);
		END;
		loc.dx := dx; loc.x := ox - x; loc.y := loc.line.base + R.voff
	END
END LocateChar;

PROCEDURE LocatePos(F: TextGadgets0.Frame; pos: LONGINT; VAR loc: TextGadgets0.Loc);
VAR l: TextGadgets0.Line; obj: Objects.Object; dx, ox: INTEGER; R: Texts.Reader; ch: CHAR; org: LONGINT;
	(* format *)
	leftM, offset, width, a, b, d: INTEGER;
BEGIN
	WITH F: Frame DO
		l := F.trailer.next;
		IF pos < F.org THEN pos := F.org; END;
		IF pos > F.text.len THEN pos := F.text.len; END;
		org := F.org;
		WHILE (l.next # F.trailer) & (pos >= org + l.len) DO org := org + l.len; l := l.next; END;
		loc.org := org; loc.pos := org; loc.line := l;
		
		l.obj := FindStyle(F.text, org);
		DisplayParam(F, l, leftM, offset, width, a, b);
		ox := F.left + leftM + offset;
		Texts.OpenReader(R, F.text, loc.pos);
		LOOP
			Texts.Read(R, ch);
			IF ((ch = 0DX) & (R.lib IS Fonts.Font)) OR R.eot THEN dx := TextGadgets0.eolW; EXIT; END;
			R.lib.GetObj(R.lib, ORD(ch), obj); dx := 0;
			IF obj # NIL THEN
				IF obj IS Fonts.Char THEN
					WITH obj: Fonts.Char DO
						dx := obj.dx;
						IF ch = " " THEN
							INC(dx, a); IF b > 0 THEN INC(dx); DEC(b) END;
						ELSIF ch = 09X THEN TabSize(l.obj, ox - (F.left + leftM + offset), dx, d)
						ELSIF dx <= 0 THEN dx := dummy.dx
						END
					END
				ELSIF obj IS Display.Frame THEN
					WITH obj: Display.Frame DO
						IF Visible(F, obj) THEN dx := obj.W;
							IF (obj IS Style) THEN EXIT END
						END
					END
				ELSE dx := dummy.dx
				END
			END;
			IF loc.pos = pos THEN EXIT; END;
			INC(loc.pos); INC(ox, dx);
		END;
		loc.dx := dx; loc.x := ox; loc.y := loc.line.base + R.voff;
	END
END LocatePos;

PROCEDURE LocateString*(F: TextGadgets0.Frame; x, y, X, Y: INTEGER; VAR loc: TextGadgets0.Loc);
VAR R: Texts.Reader; ch: CHAR; obj: Objects.Object; lim, bpos, pos, org: LONGINT; L: TextGadgets0.Line;
	bx, ox, ex, dx: INTEGER;
	(* format *)
	leftM, offset, width, a, b, d: INTEGER;
BEGIN
	WITH F: Frame DO
		FindLine(F, y, Y, org, L);
		IF (Y > y + F.H - 1) OR (Y < y + F.H - 1 + L.base - L.dsr) THEN loc.pos := -1; loc.dx := 0; loc.x := 0; RETURN END;
		loc.y := L.base; X := X - x;
		lim := org + L.len; IF lim > F.text.len THEN lim := F.text.len END;
		
		L.obj := FindStyle(F.text, org);
		DisplayParam(F, L, leftM, offset, width, a, b);
		bpos := org; pos := org; bx := F.left + leftM + offset; ox := F.left + leftM + offset;
		IF (X < bx) OR (X > bx + L.w + L.spaces * a + b) THEN loc.pos := -1; loc.dx := 0; loc.x := 0; RETURN END;
		Texts.OpenReader(R, F.text, pos); Texts.Read(R, ch);
		LOOP
			LOOP (*scan string*)
				IF (pos = lim) OR (ch <= " ") THEN EXIT END;
				R.lib.GetObj(R.lib, ORD(ch), obj);
				IF obj # NIL THEN
					IF (obj IS Display.Frame) THEN IF Visible(F, obj) THEN dx := obj(Display.Frame).W ELSE dx := 0 END
					ELSIF obj IS Fonts.Char THEN
						dx := obj(Fonts.Char).dx;
						IF ch = " " THEN
							INC(dx, a); IF b > 0 THEN INC(dx); DEC(b) END;
						ELSIF ch = 09X THEN TabSize(L.obj, ox - (F.left + leftM + offset), dx, d)
						ELSIF dx <= 0 THEN dx := dummy.dx
						END
					ELSE dx := dummy.dx
					END;
					INC(pos); ox := ox + dx
				END;
				Texts.Read(R, ch)
			END;
			ex := ox;
			LOOP (*scan gap*)
				IF (pos = lim) OR (ch > " ") THEN EXIT END;
				R.lib.GetObj(R.lib, ORD(ch), obj);
				IF obj # NIL THEN
					IF (obj IS Display.Frame) THEN IF Visible(F, obj) THEN dx := obj(Display.Frame).W ELSE dx := 0 END
					ELSIF obj IS Fonts.Char THEN dx := obj(Fonts.Char).dx;
						IF ch = " " THEN
							INC(dx, a); IF b > 0 THEN INC(dx); DEC(b) END
						ELSIF ch = 09X THEN TabSize(L.obj, ox - (F.left + leftM + offset), dx, d)
						ELSIF dx <= 0 THEN dx := dummy.dx
						END
					ELSE dx := dummy.dx
					END;
					INC(pos); ox := ox + dx
				END;
				Texts.Read(R, ch)
			END;
			IF (pos = lim) OR (ox > X) THEN EXIT END;
			R.lib.GetObj(R.lib, ORD(ch), obj);
			IF obj # NIL THEN
				IF (obj IS Display.Frame) THEN IF Visible(F, obj) THEN dx := obj(Display.Frame).W ELSE dx := 0 END
				ELSIF obj IS Fonts.Char THEN dx := obj(Fonts.Char).dx;
					IF ch = " " THEN
						INC(dx, a); IF b > 0 THEN INC(dx); DEC(b) END;
					ELSIF ch = 09X THEN TabSize(L.obj, ox - (F.left + leftM + offset), dx, d)
					ELSIF dx <= 0 THEN dx := dummy.dx
					END
				ELSE dx := dummy.dx
				END;
				bpos := pos; bx := ox;
				ox := ox + dx
			END;
			INC(pos); Texts.Read(R, ch)
		END;
		loc.pos := bpos; loc.dx := ex -bx; loc.x := bx; loc.line := L
	END
END LocateString;

  PROCEDURE Call (F: TextGadgets0.Frame; pos: LONGINT; keysum: SET; dlink: Objects.Object);
    VAR obj: Objects.Object;
    	A: Objects.AttrMsg; R: Texts.Reader; ch: CHAR; 
  BEGIN
      Texts.OpenReader(R, F.text, pos);
      Texts.Read(R, ch);
      WHILE ~R.eot & ~(R.lib IS Fonts.Font) DO Texts.Read(R, ch) END; (* skip over objects *)
      IF ~R.eot & (R.col # Display.FG) THEN (* special *)
      	obj := NIL;
      	WHILE ~R.eot & (R.lib IS Fonts.Font) & (R.col # Display.FG) DO Texts.Read(R, ch) END;
  		IF ~R.eot THEN
  			R.lib.GetObj(R.lib, ORD(ch), obj);
  			IF (obj # NIL) & (obj IS Control) THEN
  				A.id := Objects.get; A.name := "Cmd"; A.class := Objects.Inval; A.dlink := NIL; Objects.Stamp(A); A.s := ""; A.res := -1;
  				obj.handle(obj, A);
  				IF (A.res >= 0) & (A.class = Texts.String) & (A.s # "") THEN
  					F.dlink := dlink; dlink := F;
  					Gadgets.ExecuteAttr(obj(Gadgets.Frame), "Cmd", dlink, NIL, NIL); RETURN;
  				END
  			END
      	END
      END;
      TextGadgets0.Call(F, pos, keysum, dlink)
  END Call;

PROCEDURE CopyFrame*(VAR M: Objects.CopyMsg; from, to: Frame);
BEGIN TextGadgets0.CopyFrame(M, from, to); to.control := from.control
END CopyFrame;

PROCEDURE ForceString(F: Display.Frame; VAR M: Objects.AttrMsg);
BEGIN Gadgets.framehandle(F, M);
	IF M.res < 0 THEN M.class := Objects.String; M.s := ""; M.res := 0 END
END ForceString;

PROCEDURE HandleStyleAdjust(F: Frame; Sobj: Style);
VAR f: Texts.Finder; from, pos: LONGINT; obj: Objects.Object;
BEGIN
	from := -1; 
	Texts.OpenFinder(f, F.text, 0);
	WHILE ~f.eot DO
		pos := f.pos;
		Texts.FindObj(f, obj);
		IF (obj # NIL) & (obj IS Style) THEN
			IF from >= 0 THEN
				Texts.ChangeLooks(F.text, from, pos, {}, NIL, 0, 0);
				from := -1
			END;
			IF obj = Sobj THEN from := pos END;
		END
	END;
	IF from >= 0 THEN Texts.ChangeLooks(F.text, from, F.text.len, {}, NIL, 0, 0) END
END HandleStyleAdjust;

PROCEDURE FrameAttr(F: Frame; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("TextGadgets.New", M.s); M.res := 0
		ELSIF M.name = "Color" THEN M.class := Objects.Int; M.i := F.col; M.res := 0
		ELSIF M.name = "Locked" THEN M.class := Objects.Bool; M.b := TextGadgets0.locked IN F.state0; M.res := 0
		ELSIF M.name = "Flat" THEN M.class := Objects.Bool; M.b := TextGadgets0.flat IN F.state0; M.res := 0
		ELSIF M.name = "LineupHY" THEN
			M.class := Objects.Int; M.i := F.H - Fonts.Default.height - F.top - Fonts.Default.minY - 1; M.res := 0
		ELSIF M.name = "Cmd" THEN ForceString(F, M)
		ELSIF M.name = "Point" THEN ForceString(F, M)
		ELSE Gadgets.framehandle(F, M)
		END;
	ELSIF M.id = Objects.set THEN
		IF M.name = "Color" THEN
			IF M.class = Objects.Int THEN
				IF M.i < 0 THEN F.col := Display3.textbackC ELSE F.col := SHORT(M.i) END;
				F.invertC := Max(0, 15 - F.col);
				IF F.invertC = 0 THEN F.invertC := 15 END;
				M.res := 0
			END
		ELSIF M.name = "Locked" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN F.state := F.state + {Gadgets.lockedcontents, Gadgets.lockedsize};
					INCL(F.state0, TextGadgets0.locked);
				ELSE F.state := F.state - {Gadgets.lockedcontents, Gadgets.lockedsize};
					EXCL(F.state0, TextGadgets0.locked);
				 END;
				M.res := 0
			END
		ELSIF M.name = "Flat" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN F.state0 := F.state0 + {TextGadgets0.flat}
				ELSE F.state0 := F.state0 - {TextGadgets0.flat}
				END;
				M.res := 0
			END
		ELSE Gadgets.framehandle(F, M);
		END;
	ELSIF M.id = Objects.enum THEN
		M.Enum("Color"); M.Enum("Flat"); M.Enum("Point"); M.Enum("Locked");
		M.Enum("Cmd"); TextGadgets0.FrameHandler(F, M);
	END;
END FrameAttr;

PROCEDURE ConvertMsg(VAR M: Texts.UpdateMsg; VAR id: INTEGER; VAR beg, end: LONGINT);
(* CONST delete = 2; insert = 1; change = 0; *)
BEGIN
	IF M.len = 0 THEN id := delete; beg := M.beg; end := M.end
	ELSIF M.end = M.beg THEN id := insert; beg := M.beg; end := M.beg + M.len
	ELSIF M.end - M.beg = M.len THEN id := change; beg := M.beg; end := M.end
	ELSE id := replace (* ejz *)
	END
END ConvertMsg;

PROCEDURE FrameHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR F0: Frame; style: Style; id: INTEGER; beg, end, pos: LONGINT; L: TextGadgets0.Line; M0: Texts.UpdateMsg;
BEGIN
	WITH F: Frame DO
		IF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyFrame(M, F, F0); M.obj := F0
				END
			END
		ELSIF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO FrameAttr(F, M);
			END
ELSIF M IS Display.FrameMsg THEN
	WITH M: Display.FrameMsg DO
		IF M IS Texts.UpdateMsg THEN
			WITH M: Texts.UpdateMsg DO
				IF M.res >= 0 THEN HALT(99) END;
				IF (M.F # NIL) & (M.F IS Gadgets.Frame) THEN END;
				IF M.text = F.text THEN
					ConvertMsg(M, id, beg, end);
					IF (id = change) & (beg < F.org) & (end > F.org) THEN (* change *)
						pos := TextGadgets0.LinesUp(F.text, F.org, 1);
						NEW(L);
						LOOP
							F.do.Format(F, pos, L); IF L.eot THEN EXIT END;
							IF pos + L.len > F.org THEN EXIT END;
							pos := pos + L.len
						END;
						F.org := pos; F.trailer := NIL; F.car := FALSE; F.sel := FALSE; Gadgets.Update(F);
						(* TextGadgets0.ScrollTo(F, pos) *)
					ELSIF id = replace THEN (* ejz *)
						IF M.len > (M.end-M.beg) THEN
							M0 := M; M0.len := M.end-M.beg; (* change *)
							F.handle(F, M0);
							M0 := M; M0.beg := M.end; M0.end := M.end; M0.len := M.len-(M.end-M.beg); (* insert *)
							F.handle(F, M0)
						ELSIF M.len < (M.end-M.beg) THEN
							M0 := M; M0.end := M.beg+M.len; (* change *)
							F.handle(F, M0);
							M0 := M; M0.len := 0; M0.beg := M.beg+M.len; (* delete *)
							F.handle(F, M0)
						ELSE
							F.handle(F, M) (* change *)
						END
					ELSIF (beg < F.org) & (FindStyle(F.text, F.org) # F.trailer.next.obj) THEN
						pos := TextGadgets0.LinesUp(F.text, F.org, 1);
						NEW(L);
						LOOP
							F.do.Format(F, pos, L); IF L.eot THEN EXIT END;
							IF pos + L.len > F.org THEN EXIT END;
							pos := pos + L.len
						END;
						F.org := pos; F.trailer := NIL; F.car := FALSE; F.sel := FALSE; Gadgets.Update(F);
						(* TextGadgets0.ScrollTo(F, pos) *)
					ELSE TextGadgets0.FrameHandler(F, M)
					END
				ELSE TextGadgets0.FrameHandler(F, M)
				END
			END
		ELSIF M IS Oberon.InputMsg THEN
			WITH M: Oberon.InputMsg DO
				IF (M.id = Oberon.consume) & F.car THEN
					IF (M.ch = 0AX) & ~(TextGadgets0.locked IN F.state0) THEN
						style := newStyle();
						IF style.width > F.left + F.W THEN style.width := F.W - F.left - 10; style.W := style.width END;
						Gadgets.Integrate(style);
						IF (nocontrol IN F.control) THEN
							EXCL(F.control, nocontrol);
							F.trailer := NIL; F.car := FALSE; F.sel := FALSE;
							Gadgets.Update(F);
							TextGadgets0.SetCaret(F, F.carpos.pos);
						END
					ELSIF (macroHook # NIL) & ~(TextGadgets0.locked IN F.state0) THEN
						macroHook(F, M);
						IF M.res < 0 THEN TextGadgets0.FrameHandler(F, M) END
					ELSE TextGadgets0.FrameHandler(F, M)
					END
				ELSIF M.id = Oberon.track THEN
					IF (popupHook#NIL) & ~(TextGadgets0.locked IN F.state0) THEN popupHook(F, M) END;
					IF M.res < 0 THEN TextGadgets0.FrameHandler(F, M) END
				ELSE TextGadgets0.FrameHandler(F, M)
				END
			END
		ELSIF M IS Display.ModifyMsg THEN
			IF (M.F # NIL) & (M.F IS Style) THEN
				TextGadgets0.FrameHandler(F, M);
				HandleStyleAdjust(F, M.F(Style))
			ELSE TextGadgets0.FrameHandler(F, M)
			END
		ELSIF M IS Display.ControlMsg THEN
			WITH M: Display.ControlMsg DO
				TextGadgets0.FrameHandler(F, M);
				IF M.id = Display.newprinter THEN F.trailer := NIL; ClearCache END;
			END
		(* no special treatment here
		ELSIF M IS Display.ConsumeMsg THEN
			WITH M: Display.ConsumeMsg DO
				IF (M.id = Display.integrate) & F.car & (M.obj IS Display.Frame) & (TextGadgets0.mayconsume IN F.state0)
						& ~(Gadgets.lockedcontents IN F.state) THEN
					obj := M.obj;
					WHILE obj # NIL DO
						IF obj IS Style THEN
							WITH obj: Style DO
								IF obj.width > F.left + F.W THEN obj.width := F.W - F.left - 10; obj.W := obj.width END
							END
						END;
						obj := obj.slink
					END
				END;
				TextGadgets0.FrameHandler(F, M)
			END
		*)
ELSIF (M.F # NIL) & (M.F # F) THEN
	IF Visible(F, M.F) THEN
		TextGadgets0.FrameHandler(F, M)
	END
ELSE
	TextGadgets0.FrameHandler(F, M)
END
END
		ELSE 
			TextGadgets0.FrameHandler(F, M)
		END
	END
END FrameHandler;

PROCEDURE Init*(F: Frame; T: Texts.Text; note: BOOLEAN);
BEGIN F.W := 100; F.H := 100;
	TextGadgets0.InitFrame(F, T); F.handle := FrameHandler; F.do := methods; F.right := 3;
	INCL(F.state0, TextGadgets0.blockadj); INCL(F.control, nocontrol);
	IF note THEN
		INCL(F.state0, TextGadgets0.sizeadjust); INCL(F.state0, TextGadgets0.deepcopy);
		INCL(F.state0, TextGadgets0.grow); EXCL(F.state0, TextGadgets0.mayscroll); F.left := 4;
	END
END Init;

PROCEDURE New*;
VAR T: Texts.Text; F: Frame;
BEGIN NEW(T); Texts.Open(T, ""); NEW(F); Init(F, T, FALSE); Objects.NewObj := F; 
END New;

PROCEDURE NewNote*;
VAR F: Frame; T: Texts.Text;
BEGIN NEW(T); Texts.Open(T, ""); NEW(F); Init(F, T, TRUE); Objects.NewObj := F;
END NewNote;

(* ------------------------------- Style code ------------------------------ *)

PROCEDURE StyleChange(F: Style);
VAR A: Display.ModifyMsg;
BEGIN
		A.id := Display.move; A.mode := Display.display; A.F := F;
		A.X := F.X; A.Y := F.Y; A.W := (*F.W*) F.leftM + F.width; A.H := F.H; A.dX := 0; A.dY := 0; A.dW := A.W - F.W; A.dH := 0;
		Display.Broadcast(A)
END StyleChange;

PROCEDURE StyleAttr(F: Style; VAR M: Objects.AttrMsg);
VAR i, j, k: INTEGER; val: LONGINT; nr: ARRAY 6 OF CHAR;
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("TextGadgets.NewStyleProc", M.s); M.res := 0
		ELSIF M.name = "Pagebreak" THEN M.class := Objects.Bool; M.b := pagebreak IN F.mode; M.res := 0
		ELSIF M.name = "WYSIWYG" THEN M.class := Objects.Bool; M.b := wysiwyg IN F.mode; M.res := 0
		ELSIF M.name = "Tabs" THEN	(* ps - 27.6.96 *)
			M.class := Objects.String; M.res := 0;
			i:= 0; j := 0;
			WHILE i < F.noTabs DO
				Strings.IntToStr(F.tab[i], nr);
				IF j < 63 THEN
					k := 0;
					WHILE (nr[k] # 0X) & (j < 63) DO M.s[j] := nr[k]; INC(j); INC(k) END;
					M.s[j] := ","; INC(j)
				END;
				INC(i)
			END;
			IF j > 0 THEN DEC(j) END;
			M.s[j] := 0X
		ELSIF M.name = "Left" THEN M.class := Objects.Int; M.i := F.leftM; M.res := 0
		ELSIF M.name = "Width" THEN M.class := Objects.Int; M.i := F.width; M.res := 0
		ELSIF M.name = "Adjust" THEN M.class := Objects.Bool; M.b := span IN F.mode; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Pagebreak" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN INCL(F.mode, pagebreak) ELSE EXCL(F.mode, pagebreak) END;
				M.res := 0;
			END
		ELSIF M.name = "WYSIWYG" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN INCL(F.mode, wysiwyg) ELSE EXCL(F.mode, wysiwyg) END;
				M.res := 0;
			END
		ELSIF M.name = "Tabs" THEN	(* ps - 27.6.96 *)
			IF M.class = Objects.String THEN
				F.noTabs := 0; j := 0;
				WHILE (F.noTabs < MaxTabs) & (M.s[j] # 0X) DO
					WHILE (M.s[j] # 0X) & ((M.s[j] < "0") OR (M.s[j] > "9")) DO INC(j) END;
					k := 0;
					WHILE (M.s[j] # 0X) & (M.s[j] >= "0") & (M.s[j] <= "9") DO nr[k] := M.s[j]; INC(k); INC(j) END;
					nr[k] := 0X;
					Strings.StrToInt(nr, val);
					IF (val > 0) & (val < F.width) THEN
						i := 0; WHILE (i < F.noTabs) & (val > F.tab[i]) DO INC(i) END;
						IF F.noTabs > 0 THEN	(* move tabs *)
							FOR k := F.noTabs TO i + 1 BY -1 DO F.tab[k] := F.tab[k - 1] END
						END;
						F.tab[i] := SHORT(val);
						INC(F.noTabs)
					END
				END;
				M.res := 0; StyleChange(F)
			END
		ELSIF M.name = "Left" THEN
			IF (M.class = Objects.Int) & (M.i >= 0) THEN
				F.leftM:= SHORT(M.i); M.res := 0; StyleChange(F)
			END
		ELSIF M.name = "Width" THEN
			IF (M.class = Objects.Int) & (M.i > 0) THEN
				F.width:= SHORT(M.i); M.res := 0; StyleChange(F)
			END
		ELSIF M.name = "Adjust" THEN
			IF (M.class = Objects.Bool) THEN
				IF M.b THEN INCL(F.mode, span) ELSE EXCL(F.mode, span) END;
				M.res := 0
			END
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Pagebreak"); M.Enum("WYSIWYG"); M.Enum("Adjust"); M.Enum("Tabs"); M.Enum("Left"); M.Enum("Width");
		Gadgets.framehandle(F, M)
	END
END StyleAttr;

PROCEDURE RestoreStyle(F: Style; M: Display3.Mask; x, y, w, h: INTEGER);
VAR i, j: SHORTINT; name: ARRAY 128 OF CHAR; s: ARRAY 64 OF CHAR;
	
	PROCEDURE WriteTag(VAR s: ARRAY OF CHAR);
	VAR W, H, dsr: INTEGER;
	BEGIN
		IF stylefnt = NIL THEN stylefnt := Fonts.This("Default8.Scn.Fnt") END;
		Display3.StringSize(s, stylefnt, W, H, dsr);
		Display3.ReplConst(M, Display3.textbackC, x + F.leftM + F.width - 10 - W, y, W, h, Display.replace);
		Display3.String(M, Display.FG, x + F.leftM + F.width - 10 - W, y + dsr, stylefnt, s, Display.paint)
	END WriteTag;
	
BEGIN
	IF pagebreak IN F.mode THEN
		Display3.ReplConst(M, Display3.FG, x + F.leftM, y + h DIV 2, F.width, 1, Display.replace)
	ELSE
		Display3.FillPattern(M, Display3.FG, Display.grey1, x, y, x + F.leftM, y + h DIV 2, F.width, 1, Display.replace)
	END;
	IF left IN F.mode THEN
		Display3.ReplConst(M, Display3.FG, x + F.leftM, y + h DIV 2, 7, markerH, Display.replace);
		IF pad IN F.mode THEN
			Display3.ReplConst(M, Display3.FG, x + F.leftM + F.width - 6, y + h DIV 2, 7, markerH, Display.replace)
		END;
		IF F.noTabs > 0 THEN
			FOR i := 0 TO F.noTabs - 1 DO
				Display3.ReplConst(M, Display3.FG, x + F.leftM + F.tab[i], y + h DIV 2 - markerH, 2, markerH, Display.replace)
			END
		END
	ELSIF right IN F.mode THEN
		Display3.ReplConst(M, Display3.FG, x + F.leftM + F.width - 6, y + h DIV 2, 7, markerH, Display.replace)
	ELSIF middle IN F.mode THEN
	END;
	IF (F.lib # NIL) & (F.lib.name # "") THEN (* style is in public library *)
		Objects.GetName(F.lib.dict, F.ref, s);
		IF s # "" THEN
			COPY(F.lib.name, name);
			i := 0; WHILE (name[i] # 0X) & (name[i] # ".") DO INC(i) END;
			name[i] := "."; INC(i);
			j := 0; WHILE s[j] # 0X DO name[i] := s[j]; INC(i); INC(j) END;
			name[i] := 0X;
			WriteTag(name);
		END
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x + F.leftM, y, F.width, h, Display.paint)
	END
END RestoreStyle;

PROCEDURE CopyStyle*(VAR M: Objects.CopyMsg; from, to: Style);
BEGIN
	to.mode := from.mode; to.leftM := from.leftM; to.width := from.width;
	to.noTabs := from.noTabs;
	to.tab := from.tab;
	Gadgets.CopyFrame(M, from, to);
END CopyStyle;

PROCEDURE Highlight(R: Display3.Mask; x, y, w, h: INTEGER): BOOLEAN;
VAR X, Y: INTEGER; keys, keysum: SET;
BEGIN
	keysum := {};
	Display3.ReplConst(R, Display3.FG, x, y, w, h, Display.invert);
	Input.Mouse(keys, X, Y);
	WHILE keys # {} DO
		Input.Mouse(keys, X, Y);
		keysum := keysum + keys;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y)
	END;
	Display3.ReplConst(R, Display3.FG, x, y, w, h, Display.invert);
	RETURN keysum = {1}
END Highlight;

PROCEDURE TrackStyle(F: Style; x, y: INTEGER; R: Display3.Mask; VAR M: Oberon.InputMsg);
VAR bx, i, j: INTEGER; keysum: SET; do: BOOLEAN;

	PROCEDURE TrackButton(VAR bx: INTEGER; VAR keysum: SET; y, w, h: INTEGER);
	VAR offset, last: INTEGER;
	
		PROCEDURE Draw(pos: INTEGER);
		BEGIN Display3.ReplConst(NIL, Display3.invertC, pos, y, w, h, Display.invert) END Draw;
			
	BEGIN
		offset := bx - M.X;
		Oberon.FadeCursor(Oberon.Mouse);
		last := bx; Draw(last);
		WHILE M.keys # {} DO
			Input.Mouse(M.keys, M.X, M.Y); keysum := keysum + M.keys;
			IF M.X + offset # last THEN
				Oberon.FadeCursor(Oberon.Mouse);
				Draw(last); last := M.X + offset; Draw(last)
			END;
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
		END;
		Oberon.FadeCursor(Oberon.Mouse);
		Draw(last);
		bx := last;
	END TrackButton;
	
BEGIN
	keysum := {1};
	IF M.Y >=  y + F.H DIV 2 THEN (* above line *)
		IF (M.X >= x + F.leftM) & (M.X <= x + F.leftM + 7) THEN (* left button *)
			bx := x + F.leftM;
			TrackButton(bx, keysum, y + F.H DIV 2, 7, markerH);
			IF keysum = {1} THEN
				i := F.leftM;
				F.leftM := bx - x; IF F.leftM < 0 THEN F.leftM := 0 END;
				F.width := F.width - (F.leftM - i); IF F.width < 10 THEN F.width := 10 END;
				StyleChange(F)
			END
		ELSIF (M.X >= x + F.leftM + F.width - 6) & (M.X < x + F.leftM + F.width) THEN (* right button *)
			bx := x + F.leftM + F.width - 6;
			TrackButton(bx, keysum, y + F.H DIV 2, 7, markerH);
			IF keysum = {1} THEN
				F.width := bx - (x + F.leftM) + 7;
				IF F.width < 10 THEN F.width := 10 END;
				StyleChange(F)
			END
		ELSIF (M.X >= x + F.leftM + 7) & (M.X <= x + F.leftM + F.width DIV 2) THEN (* left highlight *)
			do := Highlight(R, x + F.leftM, y + F.H DIV 2, 7, markerH);
			IF do THEN
				IF (left IN F.mode) & (pad IN F.mode) THEN F.mode := F.mode - {left, pad} + {right}
				ELSIF left IN F.mode THEN F.mode := F.mode - {left} + {middle}
				ELSIF middle IN F.mode THEN F.mode := F.mode - {middle} + {left}
				ELSIF right IN F.mode THEN F.mode := F.mode - {right} + {left, pad}
				END;
				StyleChange(F);
			END
		ELSIF (M.X >= x + F.leftM + F.width DIV 2) & (M.X < x + F.leftM + F.width) THEN (* right highlight *)
			do := Highlight(R, x + F.leftM + F.width - 6, y + F.H DIV 2, 7, markerH);
			IF do THEN
				IF (left IN F.mode) & (pad IN F.mode) THEN F.mode := F.mode - {left, pad} + {left}
				ELSIF left IN F.mode THEN F.mode := F.mode + {left, pad}
				ELSIF middle IN F.mode THEN F.mode := F.mode - {middle} + {right}
				ELSIF right IN F.mode THEN F.mode := F.mode - {right} + {middle}
				END;
				StyleChange(F);
			END
		ELSE Gadgets.framehandle(F, M)
		END
	ELSE (* Below the line *)
		bx := M.X;
		(* find button *)
		i := 0;
		WHILE (i < F.noTabs) & ~((x + F.leftM + F.tab[i] -2 <= bx) & (bx <= x + F.leftM + F.tab[i] (* + 2*)+ 4)) DO INC(i) END;
		IF (F.noTabs > 0) & (i < F.noTabs) THEN (* found a tab *)
			TrackButton(bx, keysum, y + F.H DIV 2 - markerH, 3, markerH);
			IF keysum = {1} THEN
				(* remove it *)
				IF F.noTabs > 1 THEN FOR j := i TO F.noTabs - 2 DO F.tab[j] := F.tab[j + 1] END END;
				DEC(F.noTabs);
			
				(* Insert a TAB *)
				bx := bx - (x + F.leftM);
				IF (bx > 0) & (bx < F.width) THEN (* fits *)
					i := 0; WHILE (i < F.noTabs) & (bx > F.tab[i]) DO INC(i) END;
					IF F.noTabs > 0 THEN FOR j := F.noTabs TO i + 1 BY -1 DO F.tab[j] := F.tab[j - 1] END END;
					F.tab[i] := bx;
					INC(F.noTabs);
				END;
				StyleChange(F)
			END
		ELSIF F.noTabs < MaxTabs THEN (* Insert a TAB *)
			TrackButton(bx, keysum, y + F.H DIV 2 - markerH, 3, markerH);
			IF keysum = {1, 2} THEN
				(* Insert a TAB *)
				bx := bx - (x + F.leftM);
				IF (bx > 0) & (bx < F.width) THEN (* fits *)
					i := 0; WHILE (i < F.noTabs) & (bx > F.tab[i]) DO INC(i) END;
					IF F.noTabs > 0 THEN FOR j := F.noTabs TO i + 1 BY -1 DO F.tab[j] := F.tab[j - 1] END END;
					F.tab[i] := bx;
					INC(F.noTabs);
					StyleChange(F);
				END
			END
		END
	END;
	M.res := 0
END TrackStyle;

PROCEDURE StyleHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h: INTEGER; F0: Style; R: Display3.Mask;
BEGIN
	WITH F: Style DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN	(* message addressed to this frame *)
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate display coordinates *)
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									RestoreStyle(F, R, x, y, w, h)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreStyle(F, R, x, y, w, h)
								END
							ELSE
								Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & (M.keys = {1}) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								TrackStyle(F, x, y, R, M);
							ELSE
								Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Display.ModifyMsg THEN
						WITH M: Display.ModifyMsg DO
							IF (F.leftM+F.width) > M.W THEN
								IF F.leftM >= M.W THEN
									F.width := M.W; F.leftM := 0
								ELSE
									F.width := M.W-F.leftM
								END
							END
						END;
						Gadgets.framehandle(F, M)
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
			
		(* Object messages *)
		
		ELSIF M IS Objects.AttrMsg THEN StyleAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN (* store private data here *)
					Files.WriteSet(M.R, {0..15, 20});
					Files.WriteSet(M.R, F.mode);
					Files.WriteInt(M.R, F.leftM);
					Files.WriteInt(M.R, F.width);
					Files.WriteInt(M.R, F.noTabs);
					x := 0; WHILE x < F.noTabs DO Files.WriteInt(M.R, F.tab[x]); INC(x) END;
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN (* load private data here *)
					Files.ReadSet(M.R, F.mode);
					IF F.mode = {0..15, 20} THEN (* new format *)
						Files.ReadSet(M.R, F.mode);
						Files.ReadInt(M.R, F.leftM);
						Files.ReadInt(M.R, F.width);
						Files.ReadInt(M.R, y); F.noTabs := SHORT(y);
						x := 0; WHILE x < F.noTabs DO Files.ReadInt(M.R, F.tab[x]); INC(x) END;
						Gadgets.framehandle(F, M)
					ELSE (* old format *)
						Files.ReadInt(M.R, F.leftM);
						Files.ReadInt(M.R, F.width);
						Gadgets.framehandle(F, M)
					END;
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink	(* copy msg arrives again *)
				ELSE	(* first time copy message arrives *)
					NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyStyle(M, F, F0); M.obj := F0
				END
			END
		ELSE	(* unknown msg, framehandler might know it *)
			Gadgets.framehandle(F, M)
		END
	END
END StyleHandler;

PROCEDURE newStyle*(): Style;
VAR F: Style;
BEGIN NEW(F); F.W := SHORT(Printer.Unit * Printer.FrameW DIV Display.Unit); F.H := 10; F.handle := StyleHandler;
	F.state := {Gadgets.transparent, Gadgets.lockedsize};
	F.mode := {left, span}; F.leftM := 0; F.width := F.W;
	RETURN F;
END newStyle;

PROCEDURE NewStyleProc*;
BEGIN Objects.NewObj := newStyle()
END NewStyleProc;

PROCEDURE NewStyle*;
VAR F: Style;
BEGIN F := newStyle(); Gadgets.Integrate(F);
END NewStyle;

(* ------------------- Controls ---------------------- *)
PROCEDURE ControlAttr(F: Control; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("TextGadgets.NewControl", M.s); M.res := 0
		ELSIF M.name = "Cmd" THEN ForceString(F, M)
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		Gadgets.framehandle(F, M);
	ELSIF M.id = Objects.enum THEN
		M.Enum("Cmd"); Gadgets.framehandle(F, M)
	END
END ControlAttr;

PROCEDURE RestoreControl(F: Control; M: Display3.Mask; x, y, w, h: INTEGER);
BEGIN
	IF ~(Gadgets.selected IN F.state) THEN
		Display3.Circle(M, Display.FG, Display.solid, x + w DIV 2, y + w DIV 2, w DIV 2 - 2, 1, {Display3.filled}, Display.replace);
	ELSE
		Display3.Circle(M, Display.FG, Display3.selectpat, x + w DIV 2, y + w DIV 2, w DIV 2 - 2, 1, {Display3.filled}, Display.replace);
	END
END RestoreControl;

PROCEDURE CopyControl*(VAR M: Objects.CopyMsg; from, to: Control);
BEGIN
	Gadgets.CopyFrame(M, from, to);
END CopyControl;

PROCEDURE ControlHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h: INTEGER; F0: Control; R: Display3.Mask; keysum: SET; S: Display.SelectMsg;
BEGIN
	WITH F: Control DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN	(* message addressed to this frame *)
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate display coordinates *)
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									RestoreControl(F, R, x, y, w, h)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreControl(F, R, x, y, w, h)
								END
							ELSE
								Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) & (M.keys = {1}) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								Oberon.RemoveMarks(x, y, w, h);
								Display3.Circle(R, Display3.red, Display.solid, x + w DIV 2, y + w DIV 2, w DIV 2 - 2, 1, {Display3.filled}, Display.replace);
								keysum := M.keys;
								REPEAT
									Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow);
									keysum := keysum + M.keys
								UNTIL M.keys = {};
								Oberon.RemoveMarks(x, y, w, h);
								RestoreControl(F, R, x, y, w, h);
								IF keysum = {1} THEN
									S.F := F; S.id := Display.set; S.time := -1; S.sel := NIL; S.obj := NIL; S.res := -1;
									Objects.Stamp(S); Display.Broadcast(S);
									Gadgets.Execute("Columbus.Inspect", F, M.dlink, NIL, NIL);
									S.F := F; S.id := Display.reset; S.res := -1;
									Objects.Stamp(S); Display.Broadcast(S)
								END;
								M.res := 0
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
			
		(* Object messages *)
		
		ELSIF M IS Objects.AttrMsg THEN ControlAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN (* store private data here *)
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN (* load private data here *)
					Gadgets.framehandle(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink	(* copy msg arrives again *)
				ELSE	(* first time copy message arrives *)
					NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyControl(M, F, F0); M.obj := F0
				END
			END
		ELSE	(* unknown msg, framehandler might know it *)
			Gadgets.framehandle(F, M)
		END
	END
END ControlHandler;

PROCEDURE NewControl*;
VAR F: Control;
BEGIN NEW(F); F.W := 10; F.H := 10; F.handle := ControlHandler;
	INCL(F.state, Gadgets.transparent); INCL(F.state, Gadgets.lockedsize);
	Objects.NewObj := F;
END NewControl;

BEGIN
	NEW(methods); methods.Format := Format; methods.Display := DisplayLine; methods.Background := Background;
	methods.LocateChar := LocateChar; methods.LocatePos := LocatePos;  methods.LocateString := LocateString;
	methods.InSync := InSync;
	methods.PrintFormat := PrintFormat; methods.Print := PrintLine;
	methods.Call := Call;
	
	BoxPat[0] := {0..11}; 
	BoxPat[1] := {0, 11}; BoxPat[2] := {0, 11}; BoxPat[3] := {0, 11}; BoxPat[4] := {0, 11};
	BoxPat[5] := {0, 11}; BoxPat[6] := {0, 11}; BoxPat[7] := {0, 11}; BoxPat[8] := {0, 11};
	BoxPat[9] := {0, 11}; BoxPat[10] := {0, 11}; BoxPat[11] := {0.. 11};
	NEW(dummy);
	dummy.dx := 12; dummy.x := 0; dummy.y := -3; dummy.w := 12; dummy.h := 12;
	dummy.pat := Display.NewPattern(12, 12, BoxPat);
	
	stylefnt := NIL
END TextGadgets.

