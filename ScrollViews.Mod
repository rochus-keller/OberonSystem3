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

MODULE ScrollViews; (** portable *)	(** PS   **)

(**Implementation of camera-views with adjustable viewpoints and scrollbars.
 *)

(*
	9.5.96 - fixed Oberon.ControlMsg, added versioning  (ps - 9.5.96)
	7.6.96 - heavy dragging / still to do: try to remove flickering
	5.1.97 - changed scrollbar model (no division by 0 anymore)
	6.1.97 - heavy dragging / removed flickering (MoveContent)
*)

IMPORT
	Files, Input, Display, Display3, Printer, Printer3, Fonts, Effects, Objects, Gadgets, Views, Oberon, Texts;

CONST
	BarW = 18;
	VersionNo = 2;

TYPE
	Bar = RECORD
		min, max, val: LONGINT;
		backC, knoblen: INTEGER;
		vertical: BOOLEAN
	END;

	View* = POINTER TO ViewDesc;
	ViewDesc* = RECORD (Views.ViewDesc)
		vBar, hBar: Bar;
		hasVBar, hasHBar: BOOLEAN
	END;

VAR
	last: View;
	W: Texts.Writer;

PROCEDURE Max (x, y: INTEGER): INTEGER;
BEGIN IF x > y THEN RETURN x; ELSE RETURN y; END;
END Max;

PROCEDURE Min (x, y: INTEGER): INTEGER;
BEGIN IF x < y THEN RETURN x; ELSE RETURN y; END;
END Min;

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

PROCEDURE P (X: LONGINT): INTEGER;
BEGIN RETURN SHORT(X * Display.Unit DIV Printer.Unit)
END P;

PROCEDURE Value (VAR bar: Bar; x, y, w, h, X, Y: INTEGER; min, max: LONGINT): LONGINT;
VAR res: LONGINT;

	PROCEDURE CalcVal (x, w, bx, bw: INTEGER; min, max: LONGINT): LONGINT;
	VAR r, d: LONGINT;
	BEGIN
		d := max - min;
		IF (d = 0) OR (w = bw) THEN r := 0
		ELSE
			r := (bx - x - bw DIV 2) * d DIV (w - bw);
			r := min + r;
			IF min > max THEN d :=  max; max := min; min := d END;
			IF r > max THEN r := max ELSIF r < min THEN r := min END
		END;
		RETURN r
	END CalcVal;

BEGIN
	IF bar.vertical THEN res := CalcVal(y, h, Y, bar.knoblen, min, max)
	ELSE res := CalcVal(x, w, X, bar.knoblen, min, max)
	END;
	RETURN res
END Value;

PROCEDURE Pos (VAR bar: Bar; x, y, w, h, bw: INTEGER; min, max, val: LONGINT): INTEGER;
VAR res: INTEGER;

	PROCEDURE CalcPos (x, w, bw: INTEGER; min, max, val: LONGINT): INTEGER;
	VAR d: LONGINT;
	BEGIN
		d := ABS(max - min);
		IF d > 0 THEN
			IF max > min THEN
				IF val < min THEN val := min ELSIF val > max THEN val := max END
			ELSE
				IF val > min THEN val := min ELSIF val < max THEN val := max END
			END;
			val := ABS(val - min);
			x := SHORT(x + val * (w - bw) DIV d)
		END;
		RETURN x
	END CalcPos;

BEGIN
	IF bar.vertical THEN res := CalcPos(y, h, bw, min, max, val)
	ELSE res := CalcPos(x, w, bw, min, max, val)
	END;
	RETURN res
END Pos;


(* --------------------- SLIDER - VIEW ------------------- *)

PROCEDURE UpdateBars (F: View);
VAR min, max, len: LONGINT; vx, vy, w, h, W, H, VH: INTEGER;
BEGIN
	IF F.hasVBar THEN	(* vertical *)
		H:= F.H - 2*F.border;
		IF F.hasHBar THEN VH := H - BarW ELSE VH := H END; 
		IF (F.obj = NIL) OR ~(F.obj IS Display.Frame) THEN
			min := 0; max := 0; vy := 0
		ELSE
			h:= F.obj(Display.Frame).H; vy:= F.vy + F.border;
			max:= Min(vy, 0); min:= Max(vy, Max(h - VH, 0))
		END;
		F.vBar.min := min; F.vBar.max := max; F.vBar.val := vy;
		IF min = max THEN len := H
		ELSE
			h := Max(0, vy) + VH + Max(0, Max(VH, h) - vy - VH);
			len := LONG(H) * VH DIV h
		END;
		IF len > H THEN len := H
		ELSIF (len < BarW) & (BarW < H) THEN len := BarW
		END;
		F.vBar.knoblen := SHORT(len)
	END;

	IF F.hasHBar THEN	(* horizontal *)
		W:= F.W - 2*F.border; vx:= F.vx - F.border;
		IF F.hasVBar THEN DEC(vx, BarW); DEC(W, BarW) END;
		IF (F.obj = NIL) OR ~(F.obj IS Display.Frame) THEN
			min := 0; max := 0; vx := 0; 
		ELSE
			w:= F.obj(Display.Frame).W;
			max:= Min(vx, Min(0, W - w)); min:= Max(vx, 0)
		END;
		F.hBar.min := min; F.hBar.max := max; F.hBar.val := vx;
		IF min = max THEN len := W
		ELSE
			w := Max(0, -vx) + W + Max(0, vx + Max(W, w) - W);
			len := LONG(W) * W DIV w
		END;
		IF len > W THEN len := W
		ELSIF (len < BarW) & (BarW < W) THEN len := BarW
		END;
		F.hBar.knoblen := SHORT(len)
	END
END UpdateBars;

PROCEDURE AdjustChildToBar (F: View; bar: Bar);
VAR last0: View; f: Display.Frame; M: Display.ModifyMsg; D: Display.DisplayMsg;
BEGIN
	IF (F.obj # NIL) THEN
		f:= F.obj(Display.Frame); M.dX:= 0; M.dY:= 0;
		IF bar.vertical & F.hasVBar THEN
			M.dY:= SHORT(F.vBar.val) - (F.vy + F.border);
		ELSIF F.hasHBar THEN
			M.dX:= SHORT(F.hBar.val) - (F.vx - F.border);
			IF F.hasVBar THEN INC(M.dX, BarW) END
		END;
		IF (M.dX # 0) OR (M.dY # 0) THEN
			M.id := Display.move; M.mode := Display.state; M.F := f;
			M.X:= M.dX + f.X; M.Y:= M.dY + f.Y; M.W := f.W; M.H := f.H;
			M.dW := 0; M.dH := 0;
			last0:= last; last:= F;
			Display.Broadcast(M);
			last:= last0;
			(* display changes *)
			D.device := Display.screen; D.id := Display.area; D.u := 0; D.v := -F.H; D.w := F.W; D.h := F.H; D.F :=F;
			IF F.hasVBar THEN INC(D.u, BarW); DEC(D.w, BarW) END;
			IF F.hasHBar THEN INC(D.v, BarW); DEC(D.h, BarW) END;
			Display.Broadcast(D)
		END
	END
END AdjustChildToBar;


(* ---------------------- SLIDER ------------------------- *)

PROCEDURE DrawKnob (Q: Display3.Mask; x, y, w, h: INTEGER; vertical: BOOLEAN);
BEGIN
	Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC, x, y, w, h, 1, Display3.replace);
	IF vertical THEN
		y := y + h DIV 2; INC(x, 2); DEC(w, 4);
		Display3.ReplConst(Q, Display3.bottomC, x, y - 2, w, 1, Display.replace);
		Display3.ReplConst(Q, Display3.topC, x, y - 1, w, 1, Display.replace);
		Display3.ReplConst(Q, Display3.bottomC, x, y + 1, w, 1, Display.replace);
		Display3.ReplConst(Q, Display3.topC, x, y + 2, w, 1, Display.replace)
	ELSE
		x := x + w DIV 2; INC(y, 2); DEC(h, 4);
		Display3.ReplConst(Q, Display3.topC, x - 2, y, 1, h, Display.replace);
		Display3.ReplConst(Q, Display3.bottomC, x - 1, y, 1, h, Display.replace);
		Display3.ReplConst(Q, Display3.topC, x + 1, y, 1, h, Display.replace);
		Display3.ReplConst(Q, Display3.bottomC, x + 2, y, 1, h, Display.replace)
	END
END DrawKnob;

PROCEDURE DrawBar (Q: Display3.Mask; VAR bar: Bar; x, y, w, h: INTEGER);
BEGIN
    Oberon.RemoveMarks(x, y, w, h);
	Display3.ReplConst(Q, bar.backC, x, y, w, h, Display.replace);
	IF bar.vertical THEN	(* vertical *)
		Display3.ReplConst(Q, Display3.topC, x + w - 2, y, 1, h, Display.replace);
		Display3.ReplConst(Q, Display3.bottomC, x + w - 1, y, 1, h, Display.replace);
		DEC(w, 2); y := Pos(bar, x, y, w, h, bar.knoblen, bar.min, bar.max, bar.val);
		DrawKnob(Q, x, y, w, bar.knoblen, TRUE)
	ELSE	(* horizontal *)
		Display3.ReplConst(Q, Display3.topC, x, y + h - 1, w, 1, Display.replace);
		Display3.ReplConst(Q, Display3.bottomC, x, y + h - 2, w, 1, Display.replace);
		DEC(h, 2); x := Pos(bar, x, y, w, h, bar.knoblen, bar.min, bar.max, bar.val);
		DrawKnob(Q, x, y, bar.knoblen, h, FALSE)
	END
END DrawBar;

PROCEDURE PrintKnob (Q: Display3.Mask; x, y, w, h: INTEGER; vertical: BOOLEAN);
BEGIN
	Printer3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC, x, y, w, h, P(1), Display.replace);
	IF vertical THEN
		y := y + h DIV 2; INC(x, P(2)); DEC(w, P(4));
		Printer3.ReplConst(Q, Display3.bottomC, x, y-P(2), w, P(1), Display3.replace);
		Printer3.ReplConst(Q, Display3.topC, x, y-P(1), w, P(1), Display3.replace);
		Printer3.ReplConst(Q, Display3.bottomC, x, y+P(1), w, P(1), Display3.replace);
		Printer3.ReplConst(Q, Display3.topC, x, y+P(2), w, P(1), Display3.replace)
	ELSE
		x := x + w DIV 2; INC(y, P(2)); DEC(h, P(4));
		Printer3.ReplConst(Q, Display3.topC, x-P(2), y, P(1), h, Display3.replace);
		Printer3.ReplConst(Q, Display3.bottomC, x-P(1), y+2, P(1), h, Display3.replace);
		Printer3.ReplConst(Q, Display3.topC, x+P(1), y, P(1), h, Display3.replace);
		Printer3.ReplConst(Q, Display3.bottomC, x+P(2), y, P(1), h, Display3.replace)
	END
END PrintKnob;

PROCEDURE PrintBar (Q: Display3.Mask; VAR bar: Bar; x, y, w, h: INTEGER);
VAR knoblen: INTEGER;
BEGIN
	knoblen := P(bar.knoblen);
	Printer3.ReplConst(Q, bar.backC, x, y, w, h, Display.replace);
	IF bar.vertical THEN
		Printer3.ReplConst(Q, Display3.bottomC, x + w - 1, y, 1, h, Display.replace);
		y := Pos(bar, x, y, w, h, knoblen, bar.min, bar.max, bar.val);
		PrintKnob(Q, x, y, w-1, knoblen, TRUE)
	ELSE
		Printer3.ReplConst(Q, Display3.bottomC, x, y + h - 1, w, 1, Display.replace);
		x := Pos(bar, x, y, w, h, knoblen, bar.min, bar.max, bar.val);
		PrintKnob(Q, x, y, knoblen, h - 1, FALSE)
	END
END PrintBar;

PROCEDURE MoveContent (VAR bar: Bar; Q: Display3.Mask; x, y, w, h: INTEGER; F: View; dlink: Objects.Object);
VAR dv, cx, cy, cw, ch, mx, my, mw, mh: INTEGER; copy: BOOLEAN; D: Display.DisplayMsg;
BEGIN
	IF (F.obj # NIL) & (F.obj IS Display.Frame) THEN
		DrawBar(Q, bar, x, y, w, h);

		(* init DisplayMsg *)
		D.id := Display.area; D.device := Display.screen; D.dlink := dlink; D.F := F; D.res := -1;
		D.x := x - F.X - F.border; D.y := y - F.border - F.Y;

		(* copy as much as possible and adjust DisplayMsg *)
		copy := Display3.Rectangular(Q, mx, my, mw, mh);
		IF bar.vertical THEN
			cx := x + BarW; cy := y; cw := F.W - 2*F.border - BarW; ch := h;
			dv := SHORT(bar.val) - (F.vy + F.border);
			F.vy := F.vy + dv;
			IF F.hasHBar THEN INC(cy, BarW); DEC(ch, BarW) END;
			Oberon.RemoveMarks(cx, cy, cw, ch);
			D.u := cx; D.v := cy; D.w := cw; D.h := ch;	(* all the contents area *)
			IF copy THEN
				ClipAgainst(mx, my, mw, mh, Q.X, Q.Y, Q.W, Q.H); ClipAgainst(mx, my, mw, mh, cx, cy, cw, ch);
				IF dv < 0 THEN 	(* new visible area on top *)
					ClipAgainst(cx, cy, cw, ch, cx, cy - dv, cw, h + dv);	(* clip top *)
					ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip source area *)
					INC(cy, dv);
					ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip destination area *)
					D.v := cy + ch; D.h := -dv
				ELSE	(* down; new lines come at bottom *)
					ClipAgainst(cx, cy, cw, ch, cx, cy, cw, h - dv);	(* clip bottom *)
					ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip source area *)
					INC(cy, dv);
					ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip destination area *)
					D.v :=  cy - dv; D.h := dv
				END;
				IF (cw > 0) & (ch > 0) THEN
					Display.CopyBlock(cx, cy - dv, cw, ch, cx, cy, Display.replace)
				END
			END
		ELSE	(* horizontal *)
			cx := x; cy := y + BarW; cw := w; ch := F.H - 2*F.border - BarW;
			dv := SHORT(bar.val) - (F.vx - F.border); 
			IF F.hasVBar THEN DEC(D.x, BarW); INC(dv, BarW) END;
			F.vx := F.vx + dv;
			Oberon.RemoveMarks(cx, cy, cw, ch);
			D.u := cx; D.v := cy; D.w := cw; D.h := ch;	(* all the contents area *)
			IF copy THEN
				ClipAgainst(mx, my, mw, mh, Q.X, Q.Y, Q.W, Q.H); ClipAgainst(mx, my, mw, mh, cx, cy, cw, ch);
				IF dv < 0 THEN 	(* new visible area on the right *)
					ClipAgainst(cx, cy, cw, ch, cx - dv, cy, cw + dv, ch);	(* clip right *)
					ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip source area *)
					INC(cx, dv);
					ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip destination area *)
					D.u := cx + cw; D.w := -dv
				ELSE	(* new visible area on the left *)
					ClipAgainst(cx, cy, cw, ch, cx, cy, cw - dv, ch);	(* clip left *)
					ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip source area *)
					INC(cx, dv);
					ClipAgainst(cx, cy, cw, ch, mx, my, mw, mh);	(* clip destination area *)
					D.u := cx - dv; D.w := dv
				END;
				IF (cw > 0) & (ch > 0) THEN
					Display.CopyBlock(cx - dv, cy, cw, ch, cx, cy, Display.replace)
				END
			END
		END;
		DEC(D.u, D.x + F.X); DEC(D.v, D.y + F.Y + F.H -1);	(* make it relative *)
		F.handle(F, D)
	END
END MoveContent;
 
PROCEDURE TrackBar (F: View; VAR M: Oberon.InputMsg; VAR bar: Bar; x, y, w, h: INTEGER);
	VAR keysum: SET; Q: Display3.Mask; pos, npos, oldpos: LONGINT;
BEGIN
		Gadgets.MakeMask(F, M.x + F.X, M.y + F.Y, M.dlink, Q); Display3.Copy(Q, Q);
		keysum:= M.keys; oldpos := bar.val; pos := oldpos;
		REPEAT
			npos := Value(bar, x, y, w, h, M.X, M.Y, bar.min, bar.max);
			IF npos # pos THEN (* new position *)
				Oberon.FadeCursor(Oberon.Mouse);
				bar.val := npos; MoveContent(bar, Q, x, y, w, h, F, M.dlink);
				pos := npos
			END;
			Input.Mouse(M.keys, M.X, M.Y); keysum := keysum + M.keys;
			Oberon.DrawCursor(Oberon.Mouse, Effects.FlatHand, M.X, M.Y)
		UNTIL M.keys = {};
		IF keysum = {0, 1, 2} THEN bar.val:= oldpos; AdjustChildToBar(F, bar)
		ELSE UpdateBars(F); DrawBar(Q, bar, x, y, w, h)
		END;
		M.res:= 0
END TrackBar;

PROCEDURE InitBar (VAR b: Bar; min, max, val: LONGINT; backC: INTEGER; vertical: BOOLEAN; width: INTEGER);
BEGIN
	b.min:= min; b.max:= max; b.val:= val; b.backC:= backC; b.vertical:= vertical;
	b.knoblen := SHORT(width - ABS(max - min));
	IF b.knoblen < BarW THEN b.knoblen := BarW END
END InitBar;


(* --------------------- SLIDER - VIEW ------------------- *)

PROCEDURE RestoreBars (F: View; x, y: INTEGER; dlink: Objects.Object);
VAR M: Display3.Mask; w, h: INTEGER;
BEGIN
	Gadgets.MakeMask(F, x, y, dlink, M);
	Oberon.RemoveMarks(x, y, F.W, F.H);
	INC(x, F.border); INC(y, F.border); w:= F.W - 2*F.border; h:= F.H - 2*F.border;
	IF F.hasVBar THEN DrawBar(M, F.vBar, x, y, BarW, h); INC(x, BarW); DEC(w, BarW) END;
	IF F.hasHBar THEN DrawBar(M, F.hBar, x, y, w, BarW) END
END RestoreBars;


(* --------------------- VIEW ------------------- *)

PROCEDURE ToFrame (F: View; x, y: INTEGER; VAR M: Display.FrameMsg);
VAR f: Display.Frame;
BEGIN
	IF (F.obj # NIL) & (F.obj IS Display.Frame) THEN
		f:= F.obj(Display.Frame);
		M.x := x + F.vx - f.X; M.y := y + F.H + F.vy - (f.Y + f.H);
		Gadgets.Send(F, x, y, F.obj(Display.Frame), M)
	END
END ToFrame;

(* background drawing procedure *)
PROCEDURE Background (F: View; X, Y: INTEGER; M: Display3.Mask; col, x, y, w, h, mode: INTEGER);
VAR cx, cy, cw, ch, t: INTEGER;
BEGIN
	cx := M.X; cy := M.Y; cw := M.W; ch := M.H;
	Display3.AdjustMask(M, x, y, w, h);
	IF F.border <= 1 THEN
		Display3.FilledRect3D(M, Display3.bottomC, Display3.topC, col, X, Y, F.W, F.H, 1, Display.replace)
	ELSE
		Display3.Rect(M, Display3.black, Display.solid, X, Y, F.W, F.H, 1, Display.replace);
		t := F.border - 2;
		IF t > 0 THEN Display3.Rect(M, Display3.white, Display.solid, X+1, Y+1, F.W-2, F.H-2, t, Display.replace) END;
		t := F.border - 1;
		IF t < 0 THEN t := 0 END;
		Display3.FilledRect3D(M, Display3.black, Display3.black, col, X+t, Y+t, F.W-t*2, F.H-t*2, 1, Display.replace)
	END;
	IF F.hasVBar  & (x < X + BarW) THEN
		DrawBar(M, F.vBar, X + F.border, Y + F.border, BarW, F.H - 2*F.border)
	END;
	IF F.hasHBar  & (y < Y + BarW) THEN
		IF F.hasVBar THEN DrawBar(M, F.hBar, X + F.border + BarW, Y + F.border, F.W - 2*F.border - BarW, BarW)
		ELSE DrawBar(M, F.hBar, X + F.border, Y + F.border, F.W - 2*F.border, BarW)
		END
	END;
	M.X := cx; M.Y := cy; M.W := cw; M.H := ch
END Background;

PROCEDURE CutoutBack (F: View; R: Display3.Mask; x, y, w, h, X, Y, W, H: INTEGER);
VAR B, T, nH: INTEGER;
	
	PROCEDURE Enum (x1, y1, w1, h1: INTEGER);
	BEGIN IF (w1 > 0) & (h1 > 0) THEN Background(F, X, Y , R, Views.background, x1, y1, w1, h1, Display.replace) END
	END Enum;
	
BEGIN
	B := Y;
	IF y > Y THEN B := y; Enum(X, Y, W, Min(H, y - Y)) END; (* bottom block *)
	T := Y + H;
	IF y + h < Y + H THEN T := y + h; Enum(X, T, W, Min(H, Y + H - T)) END; (* top block *)
	nH := T - B;
	IF x > X THEN Enum(X, B, Min(W, x - X), nH) END; (* left block *)
	IF x + w < X + W THEN Enum(x + w, B, Min(W, X + W - (x + w)), nH) END; (* right block *)
END CutoutBack;

PROCEDURE RestoreView (F: View; x, y: INTEGER; dlink: Objects.Object);
	VAR R: Display3.Mask; f: Display.Frame; w, h, col, fx, fy, fw, fh, cx, cy, cw, ch: INTEGER;
			M: Display.DisplayMsg;
BEGIN
	w := F.W; h := F.H; 
	Oberon.RemoveMarks(x, y, w, h);
	Gadgets.MakeMask(F, x, y, dlink, R);
	col := Views.background;
	IF F.hasVBar THEN fx:= x + BarW; fw:= w - BarW
	ELSE fx:= x; fw:= w
	END;
	IF F.hasHBar THEN fy:= y + BarW; fh:= h - BarW
	ELSE fy:= y; fh:= h
	END;
	IF (F.obj # NIL) & (F.obj IS Display.Frame) THEN
		f := F.obj(Display.Frame);
		IF (f IS Gadgets.Frame) & (Gadgets.transparent IN f(Gadgets.Frame).state) THEN
			Background(F, x, y, R, col, x, y, w, h, Display.replace);
		ELSE
			cx := x + F.vx; cy := y + h + F.vy - f.H; cw := f.W; ch := f.H; (* area of child frame *)
			ClipAgainst(cx, cy, cw, ch, fx + F.border, fy + F.border, fw - F.border*2, fh - F.border*2);
			CutoutBack(F, R, cx, cy, cw, ch, x, y, w, h)
		END;
		M.device := Display.screen; M.id := Display.full; M.F := NIL; M.dlink := dlink; M.res := -1; ToFrame(F, x, y, M)
	ELSE
		Background(F, x, y, R, col, x, y, w, h, Display.replace);
		Display3.CenterString(R, Display3.FG, fx, fy, fw, fh, Fonts.Default, "Empty View", Display3.textmode)
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, F.W, F.H, Display3.paint)
	END
END RestoreView;

PROCEDURE RestoreViewArea (F: View; x, y, u, v, w1, h1: INTEGER; dlink: Objects.Object);
	VAR R: Display3.Mask; f: Display.Frame; w, h, col, fx, fy, fw, fh, cx, cy, cw, ch: INTEGER;
			M: Display.DisplayMsg;
BEGIN
	w := F.W; h := F.H;
	Oberon.RemoveMarks(x, y, w, h);
	Gadgets.MakeMask(F, x, y, dlink, R);
	Display3.AdjustMask(R, x + u, y + h - 1 + v, w1, h1);
	col := Views.background;
	IF F.hasVBar THEN fx:= x + BarW; fw:= w - BarW
	ELSE fx:= x; fw:= w
	END;
	IF F.hasHBar THEN fy:= y + BarW; fh:= h - BarW
	ELSE fy:= y; fh:= h
	END;
	IF (F.obj # NIL) & (F.obj IS Display.Frame) THEN
		f := F.obj(Display.Frame);
		IF (f IS Gadgets.Frame) & (Gadgets.transparent IN f(Gadgets.Frame).state) THEN
			Background(F, x, y, R, col, x, y, w, h, Display.replace)
		ELSE
			cx := x + F.vx; cy := y + h + F.vy - f.H; cw := f.W; ch := f.H; (* area of child frame *)
			ClipAgainst(cx, cy, cw, ch, fx + F.border, fy + F.border, fw - F.border*2, fh - F.border*2);
			CutoutBack(F, R, cx, cy, cw, ch, x, y, w, h)
		END;
		ClipAgainst(u, v, w1, h1,  F.vx, F.vy - f.H + 1, f.W, f.H);
		M.u:= u - F.vx; M.v:= v - F.vy; M.w:= w1; M.h:= h1;
		M.device := Display.screen; M.id := Display.area; M.F := f; M.dlink := dlink; M.res := -1; ToFrame(F, x, y, M)
	ELSE
		Background(F, x, y, R, col, x, y, w, h, Display.replace);
		Display3.CenterString(R, Display3.FG, fx, fy, fw, fh, Fonts.Default, "Empty View", Display3.textmode)
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, F.W, F.H, Display3.paint)
	END
END RestoreViewArea;

PROCEDURE PrintView (F: View; M: Display.DisplayMsg);
VAR R: Display3.Mask; f: Display.Frame; x, y, w, h, t, backC: INTEGER; Pr: Display.DisplayMsg;
BEGIN
	x:= M.x; y:= M.y; w:= P(F.W); h:= P(F.H);
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);

	(* background *)
	backC:= Views.background;
	IF F.border <= 1 THEN
		Printer3.FilledRect3D(R, Display3.bottomC, Display3.topC, backC, x, y, w, h, P(1), Display.replace)
	ELSE
		Printer3.Rect(R, Display3.black, Display.solid, x, y, w, h, P(1), Display.replace);
		t := P(F.border - 2);
		IF t > 0 THEN
			Printer3.Rect(R, Display3.white, Display.solid, x+P(1), y+P(1), w-P(2), h-P(2), t, Display.replace)
		END;
		t := P(F.border - 1);
		IF t < 0 THEN t := 0 END;
		Printer3.FilledRect3D(R, Display3.black, Display3.black, backC, x+t, y+t, w-t*2, h-t*2, P(1), Display.replace)
	END;

	(* bars *)
	t:= P(F.border); INC(x, t); INC(y, t); DEC(w, 2*t); DEC(h, 2*t);
	IF F.hasVBar THEN PrintBar(R, F.vBar, x, y, P(BarW), h); INC(x, P(BarW)); DEC(w, P(BarW)) END;
	IF F.hasHBar THEN PrintBar(R, F.hBar, x, y, w, P(BarW)) END;

	(* content *)
	IF F.obj # NIL THEN
		f:= F.obj(Display.Frame);
		Pr.res:= -1; Pr.device := Display.printer; Pr.id:= Display.full; Pr.F:= f; Pr.dlink:= M.dlink;
		Pr.x:= x + P(F.vx + f.X); Pr.y:= y + h + P(F.vy + f.Y - f.H);
		Gadgets.Send(F, x, y, f, Pr)
	ELSE
		Printer3.CenterString(R, Display3.textC, x, y, w, h, Fonts.Default, "Empty View", Display.paint)
	END
END PrintView;

PROCEDURE InHotspot (X, Y, x, y, w, h: INTEGER): BOOLEAN;
CONST size = 10; GravQ = 4; MinGrav = 2;

	PROCEDURE InBorder (mx, my, X, Y, W, H: INTEGER): BOOLEAN;
		VAR hg, vg: INTEGER;
	BEGIN
		IF (W <= Effects.gravity*3) OR (H <= Effects.gravity*3) THEN
			hg := Min(Effects.gravity, Max(W DIV GravQ, MinGrav));
			vg := Min(Effects.gravity, Max(H DIV GravQ, MinGrav));
			RETURN Effects.Inside(mx, my, X + hg, Y, 1, H) OR
				Effects.Inside(mx, my, X, Y + vg, W, 1) OR
				Effects.Inside(mx, my, X+W-hg - 1, Y, 1, H) OR
				Effects.Inside(mx, my, X, Y+H-vg - 1, W, 1)
		ELSE
			RETURN Effects.Inside(mx, my, X+Effects.gravity, Y, 1, H) OR
				Effects.Inside(mx, my, X, Y+Effects.gravity, W, 1) OR
				Effects.Inside(mx, my, X+W-Effects.gravity - 1, Y, 1, H) OR
				Effects.Inside(mx, my, X, Y+H-Effects.gravity - 1, W, 1)
		END
	END InBorder;
	
BEGIN RETURN Effects.Inside(X, Y, x, y + h - size, size, size) OR InBorder(X, Y, x, y, w, h)
END InHotspot;

PROCEDURE TrackSelectChild (F: View; VAR M: Oberon.InputMsg; child: Gadgets.Frame);
VAR keysum: SET; S: Display.SelectMsg; D: Display.DisplayMsg; C: Objects.CopyMsg;
BEGIN
	S.F:= child; S.res := -1; S.dlink:= M.dlink;
	IF Gadgets.selected IN child.state THEN S.id:= Display.reset; F.time:= 0
	ELSE S.id:= Display.set; F.time:= Oberon.Time()
	END;
	ToFrame(F, M.x + F.X, M.y + F.Y, S);
	Oberon.FadeCursor(Oberon.Mouse);
	D.device := Display.screen; D.id:= Display.full; D.F:= child; Display.Broadcast(D);
	keysum:= M.keys;
	REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum:= keysum + M.keys
	UNTIL M.keys = {};
	M.res:= 0;
	IF keysum = {0,2} THEN (* LR -> delete frame *)
		F.obj:= NIL; UpdateBars(F); Gadgets.Update(F)
	ELSIF keysum = {0,1} THEN (* MR -> copy to focus *)
		C.id:= Objects.shallow; C.obj:= NIL; Objects.Stamp(C); child.handle(child, C);
		Gadgets.Integrate(C.obj)
	END
END TrackSelectChild;

PROCEDURE TrackView (F: View; VAR M: Oberon.InputMsg);
VAR last0: View; Mdlink, Fdlink: Objects.Object; f: Display.Frame; x, y, b: INTEGER; L: Display.LocateMsg;
BEGIN
	x:= M.x + F.X; y:= M.y + F.Y;
	L.x:= M.x; L.y:= M.y; L.dlink := M.dlink; L.X := M.X; L.Y := M.Y; L.F := NIL; L.loc := NIL; L.res := -1;
	F.handle(F, L); IF (L.loc = F) OR (F.obj = NIL) THEN f:= NIL ELSE f:= F.obj(Display.Frame) END;
	IF (f # NIL) & ~InHotspot(M.X, M.Y, x, y, F.W, F.H) THEN
		last0 := last; last := F; ToFrame(F, x, y, M); last := last0
	END;
	
	IF M.res < 0 THEN (* child does not respond *)
		last0 := last; last := F;
		IF 2 IN M.keys THEN (* left *)
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y)
		ELSIF 1 IN M.keys THEN (* middle *)
			b:= F.border;
			IF (f # NIL) & (f IS Gadgets.Frame) & ~(Gadgets.lockedcontents IN F.state) THEN
				WITH f: Gadgets.Frame DO
					IF InHotspot(M.X, M.Y, x, y, F.W, F.H) THEN (* move child *)
						M.x:= x + F.vx - f.X; M.y:= y + F.H + F.vy - (f.Y + f.H);
						Fdlink:= F.dlink; Mdlink:= M.dlink; F.dlink:= M.dlink; M.dlink:= F;
						Gadgets.MoveFrame(f, M);
						M.dlink:= Mdlink; F.dlink:= Fdlink;
						M.res:= 0
					ELSIF Gadgets.selected IN f(Gadgets.Frame).state THEN (* move or size child *)
						M.x:= x + F.vx - f.X; M.y:= y + F.H + F.vy - (f.Y + f.H);
						Fdlink:= F.dlink; Mdlink:= M.dlink; F.dlink:= M.dlink; M.dlink:= F;
						IF Effects.InCorner(M.X, M.Y, M.x + f.X, M.y + f.Y, f.W, f.H) & ~(Gadgets.lockedsize IN f.state) THEN
							Gadgets.SizeFrame(f, M)
						ELSE
							Gadgets.MoveFrame(f, M)
						END;
						M.dlink:= Mdlink; F.dlink:= Fdlink;
						M.res:= 0
					END
				END
			ELSIF F.hasVBar & Effects.Inside(M.X, M.Y, x + b, y + b, BarW, F.H - 2*b) THEN
				TrackBar(F, M, F.vBar, x + b, y + b, BarW, F.H - 2*b);
			ELSIF F.hasHBar & Effects.Inside(M.X, M.Y, x + b, y + b, F.W - 2*b, BarW) THEN
				IF F.hasVBar THEN TrackBar(F, M, F.hBar, x + b + BarW, y + b, F.W - 2*b - BarW, BarW)
				ELSE TrackBar(F, M, F.hBar, x + b, y + b, F.W - 2*b, BarW)
				END
			ELSE Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y)
			END
		ELSIF 0 IN M.keys THEN (* right *)
			IF (f # NIL) & (f IS Gadgets.Frame)  & ~(Gadgets.lockedcontents IN F.state) THEN
				TrackSelectChild(F, M, f(Gadgets.Frame))
			ELSE Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y)
			END
		END;
		last := last0
	END
END TrackView;

PROCEDURE AdjustToFrame (F: View; x, y: INTEGER; VAR M: Display.ModifyMsg);
VAR B: Display3.UpdateMaskMsg;
BEGIN
	IF F.obj # NIL THEN
		IF F.mask = NIL THEN B.F := F; Display.Broadcast(B) END;
		M.x := x + F.vx - M.X; M.y := y + F.H + F.vy - M.Y - M.H;
		Gadgets.Send(F, x, y, F.obj(Display.Frame), M)
	END
END AdjustToFrame;

PROCEDURE AdjustChild (F: View; x, y, w, h: INTEGER; VAR M: Display.ModifyMsg);
VAR RM, R: Display3.Mask; cx, cy: INTEGER;
BEGIN
	IF last = F THEN  (* moved or resized in this view *)
		IF M.stamp # F.stamp THEN cx := F.vx + M.dX; cy := F.vy + (M.dY + M.dH) - M.H + 1
		ELSE cx := F.vx; cy := F.vy - M.H + 1
		END;
		IF (M.id = Display.move) & ~Effects.Intersect(cx, cy, M.W, M.H, 0, -F.H+1, F.W, F.H) THEN
			(* completely out of bound, ignore *)
			M.res := 0;
			RETURN
		END;
		IF M.stamp # F.stamp THEN F.vx := F.vx + M.dX; F.vy := F.vy + (M.dY + M.dH); F.stamp := M.stamp END;

		Gadgets.MakeMask(F, x, y, M.dlink, RM);
		Display3.Copy(RM, R); R.x := 0; R.y := 0;
		Display3.Intersect(R, F.vx - M.dX, F.vy - (M.dY + M.dH)- (M.H - M.dH) + 1, M.W - M.dW, M.H - M.dH);
		IF (M.F IS Gadgets.Frame) & ~(Gadgets.transparent IN M.F(Gadgets.Frame).state) THEN
			Display3.Subtract(R, F.vx, F.vy - M.H + 1, M.W, M.H)
		END;
		R.x := x; R.y := y + h - 1;
		Background(F, x, y, R, Views.background, x+F.border, y+F.border, w-F.border*2, h-F.border*2, Display.replace);
		AdjustToFrame(F, x, y, M);
		UpdateBars(F); RestoreBars(F, x, y, M.dlink);
		IF Gadgets.selected IN F.state THEN
			Display3.FillPattern(RM, 15, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	ELSIF (M.dW # 0) OR (M.dH # 0) THEN (* just resize in this view *)
		Gadgets.MakeMask(F, x, y, M.dlink, RM);
		Display3.Copy(RM, R); R.x := 0; R.y := 0;
		Display3.Intersect(R, F.vx, F.vy - (M.H - M.dH) + 1, M.W - M.dW, M.H - M.dH);
		IF (M.F IS Gadgets.Frame) & ~(Gadgets.transparent IN M.F(Gadgets.Frame).state) THEN
			Display3.Subtract(R, F.vx, F.vy - M.H + 1, M.W, M.H)
		END;
		R.x := x; R.y := y + h - 1;
		Background(F, x, y, R, Views.background, x+F.border, y+F.border, w-F.border*2, h-F.border*2, Display.replace);
		AdjustToFrame(F, x, y, M);
		UpdateBars(F); RestoreBars(F, x, y, M.dlink);
		IF Gadgets.selected IN F.state THEN
			Display3.FillPattern(RM, 15, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END
END AdjustChild;

PROCEDURE Absolute (dlink: Objects.Object): BOOLEAN;
VAR A: Objects.AttrMsg;
BEGIN
	IF (dlink # NIL) & (dlink.handle # NIL) THEN (* NIL test because of Script *)
		A.id := Objects.get; A.name := "Absolute"; A.res := -1; dlink.handle(dlink, A);
		RETURN (A.res >= 0) & (A.class = Objects.Bool) & A.b
	ELSE RETURN FALSE
	END
END Absolute;

PROCEDURE CleverAdjust (F: View; VAR M: Display.ModifyMsg);
VAR x, y, w, h, x0, y0, w0, h0, x1, y1, w1, h1: INTEGER; D: Display.DisplayMsg; O: Display3.OverlapMsg;
		abs: BOOLEAN;
BEGIN
	(* calculate old position *)
	abs := Absolute(M.dlink);
	x := M.X - M.dX; y := M.Y - M.dY; w := M.W - M.dW; h := M.H - M.dH;
	
	IF abs & (M.W = w) & (M.X = x) & (M.Y = y) & (h # 0) THEN (* In MenuViewer, width did not change, grow up/down *)
		(* Special optimization *)
		IF M.H > h THEN (* copy up *)
			h1 := M.H - h;
			IF (w > 0) & (h > 0) THEN
				Display.CopyBlock(x, y, w, h, x, M.Y + h1, Display.replace)
			END
		ELSE (* copy down *)
			h1 := h - M.H;
			IF (w > 0) & ((M.H - F.border) > 0) THEN
				Display.CopyBlock(x, y + h1 + F.border, w, M.H - F.border, M.X, M.Y + F.border, Display.replace)
			END
			(* 2 is for the border *)
		END;
		IF M.stamp # F.stamp THEN (* first adjust *)
			F.X := M.X; F.Y := M.Y; F.W := M.W; F.H := M.H; UpdateBars(F);
			O.F := F; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL; F.handle(F, O);
			F.stamp := M.stamp
		END;
		IF M.H > h THEN (* copy up, restore bottom part *)
			D.id := Display.full; D.device := Display.screen; D.F := F; Display.Broadcast(D)
		ELSE (* at least restore the bars *)
			RestoreBars(F, F.X, F.Y, NIL)
		END
	ELSIF (M.X = x) & (M.Y + M.H = y + h) THEN (* left top most corner is stable *) (* << remove *)
		IF (M.mode = Display.display) THEN
			(* extend / reduce Y *)
			w0 := 0; h0 := 0;
			IF M.H > h THEN (* extend *)
				x0 := 0; y0 := -M.H + 1; w0 := M.W; h0 := y - M.Y + F.border
			ELSIF M.H < h THEN (* reduce *)
				x0 := 0; y0 := -M.H + 1; w0 := M.W; h0 := F.border
			END;
			IF F.hasHBar THEN INC(h0, BarW) END;
			
			(* extend / reduce X *)
			w1 := 0; h1 := 0;
			IF M.W > w THEN (* extend *)
				x1 := w - F.border; y1 := -M.H + 1;  w1 := M.W - w + 1 + F.border; h1 := M.H
			ELSIF M.W < w THEN (* reduce *)
				x1 := M.W - F.border; y1 := -M.H + 1; w1 := F.border; h1 := M.H
			END;
			IF (w1 # 0) & (h1 # 0) THEN INC(y1, h0); DEC(h1, h0) END (* eliminate overlap *)
		END;
		IF M.stamp # F.stamp THEN (* first adjust *) 
			F.X := M.X; F.Y := M.Y; F.W := M.W; F.H := M.H; UpdateBars(F);
			O.F := F; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL; F.handle(F, O);
			F.stamp := M.stamp
		END;
		IF (M.mode = Display.display) THEN
			IF F.hasVBar THEN
				D.F := F; D.x := M.x; D.y := M.y; D.F := F; D.device := Display.screen; D.id := Display.area; D.dlink := M.dlink;
				D.u := 0; D.v := y0; D.w := BarW; D.h := F.H; 
				Objects.Stamp(D); D.res := -1; F.handle(F, D)
			END;
			IF (w0 # 0) & (h0 > 0) THEN
				D.F := F; D.x := M.x; D.y := M.y; D.F := F; D.device := Display.screen; D.id := Display.area; D.dlink := M.dlink;
				D.u := x0; D.v := y0; D.w := w0; D.h := h0; 
				Objects.Stamp(D); D.res := -1; F.handle(F, D)
			END;
			IF (w1 # 0) & (h1 > 0) THEN
				D.F := F; D.x := M.x; D.y := M.y; D.F := F; D.device := Display.screen; D.id := Display.area; D.dlink := M.dlink;
				D.u := x1; D.v := y1; D.w := w1; D.h := h1; 
				Objects.Stamp(D); D.res := -1; F.handle(F, D)
			END
		END
	ELSE 
		IF F.stamp # M.stamp THEN (* first adjust *)
			F.X := M.X; F.Y := M.Y; F.W := M.W; F.H := M.H; UpdateBars(F);
			O.F := F; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL; F.handle(F, O);
			F.stamp := M.stamp
		END;
		IF (M.mode = Display.display) & (F.H > 0) & (F.W > 0) THEN
			D.x := M.x; D.y := M.y; D.F := F; D.device := Display.screen; D.id := Display.full; D.dlink := M.dlink; D.res := -1;
			Objects.Stamp(D); F.handle(F, D)
		END
	END
END CleverAdjust;

PROCEDURE Adjust (F: View; VAR M: Display.ModifyMsg);
VAR D: Display.DisplayMsg; O: Display3.OverlapMsg;
BEGIN
	IF F.stamp # M.stamp THEN (* first adjust *)
		F.X := M.X; F.Y := M.Y; F.W := M.W; F.H := M.H;
		UpdateBars(F);
		O.F := F; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL; F.handle(F, O);
		F.stamp := M.stamp
	END;
	IF (M.mode = Display.display) & (F.H > 0) & (F.W >0) THEN
		D.x := M.x; D.y := M.y; D.F := F; D.device := Display.screen; D.id := Display.full;
		D.dlink := M.dlink; D.res := -1; Objects.Stamp(D);
		F.handle(F, D)
	END
END Adjust;

PROCEDURE Consume (F: View;  x, y: INTEGER; VAR M: Display.ConsumeMsg);
VAR f: Display.Frame; CM: Display.ControlMsg; BM: Objects.BindMsg;
BEGIN
	IF (M.id = Display.drop) & (M.F = F) THEN
		IF (F.obj = NIL) & (M.obj IS Display.Frame) THEN
			f:= M.obj(Display.Frame);
			f.slink := NIL;
			IF Gadgets.Recursive(F, f) THEN
				Texts.WriteString(W,"Not allowed, will cause recursive structures"); Texts.Append(Oberon.Log, W.buf)
			ELSIF (F.lib # NIL) & (f.lib # NIL) & (F.lib # f.lib) & (f.lib.name # "") THEN
				Texts.WriteString(W,"Across library movement not allowed"); Texts.Append(Oberon.Log, W.buf)
			ELSE
				CM.id := Display.remove; CM.F := f; Display.Broadcast(CM); (* remove frame from old content *)
				F.obj := f; f.X := 0; f.Y := 0;
				IF F.border < 1 THEN F.vx := 0; F.vy := 0
				ELSE F.vx := F.border; F.vy := -F.border
				END;
				IF F.hasVBar THEN INC(F.vx, BarW) END;
				IF f IS Gadgets.Frame THEN
					WITH f: Gadgets.Frame DO
						IF Gadgets.selected IN f.state THEN F.time:= Oberon.Time() END;
						F.state := f.state*{Gadgets.transparent}; f.mask := NIL
					END
				END;
				IF F.lib # NIL THEN BM.lib := F.lib; F.obj.handle(F.obj, BM); END;
				UpdateBars(F); Gadgets.Update(F)
			END
		END;
		M.res := 0
	ELSE ToFrame(F, x, y, M)
	END
END Consume;

PROCEDURE Locate (F: View; VAR M: Display.LocateMsg);
VAR f: Display.Frame; u, v, fx, fy, fw, fh, cx, cy, cw, ch: INTEGER;
BEGIN
	u := M.x + F.X; v := M.y + F.Y + F.H - 1;
	IF F.obj # NIL THEN
		f := F.obj(Display.Frame);
		cx := u + F.vx; cy := v + F.vy - (f.H - 1); cw:= f.W; ch:= f.H;
		fx:= M.x + F.X + F.border; fy:= M.y + F.Y + F.border; fw:= F.W - 2* F.border; fh:= F.H - 2* F.border;
		IF F.hasVBar THEN INC(fx, BarW); DEC(fw, BarW) END;
		IF F.hasHBar THEN INC(fy, BarW); DEC(fh, BarW) END;
		ClipAgainst(cx, cy, cw, ch, fx, fy, fw, fh);
		IF (M.X >= cx) & (M.Y >= cy) & (M.X < cx + cw) & (M.Y < cy + ch) THEN
			M.x := u + F.vx - f.X; M.y := v + F.vy - (f.Y + f.H - 1);
			M.F := NIL; M.loc := NIL; M.res := -1; M.dlink := NIL;
			f.handle(f, M);
		END
	END;
	IF M.loc = NIL THEN
		M.loc := F; M.u:= M.X - u; M.v:= M.Y - v;
		M.x:= u - F.X; M.y:= v - (F.Y + F.H - 1)
	END;
	M.res:= 0
END Locate;

PROCEDURE UpdateMask (F: View; x, y: INTEGER; VAR M: Display3.UpdateMaskMsg);
	VAR R: Display3.Mask; O: Display3.OverlapMsg;
BEGIN
	IF M.F = F.obj THEN
		NEW(R); Display3.Open(R);
		Display3.Add(R, 0, -F.obj(Display.Frame).H+1, F.obj(Display.Frame).W, F.obj(Display.Frame).H);
		O.F := F.obj(Display.Frame); O.x := 0; O.y := 0; O.M := R; O.res := -1; O.dlink := NIL;
		ToFrame(F, x, y, O); M.res := 0
	ELSIF M.F = F THEN
		NEW(F.mask); Display3.Open(F.mask); Display3.Add(F.mask, 0, -F.H+1, F.W, F.H);
		F.mask.x := 0; F.mask.y := 0
	ELSE ToFrame(F, x, y, M)
	END
END UpdateMask;

PROCEDURE MakeMask (v: Gadgets.View; M: Display3.Mask; ondisplay: BOOLEAN);
VAR x, y, w, h: INTEGER;
BEGIN
	WITH v: View DO
		x:= v.border; w:= x*2; y:= x; h:= w;
		IF v.hasVBar THEN INC(x, BarW); INC(w, BarW) END;
		IF v.hasHBar THEN INC(y, BarW); INC(h, BarW) END;
		IF ondisplay THEN
			Display3.AdjustMask(M, v.absX+x, v.absY+y, v.W-w, v.H-h)
		ELSE
			Display3.AdjustMask(M, v.absX+P(x), v.absY+P(y), P(v.W-w), P(v.H-h))
		END
	END
END MakeMask;

PROCEDURE CopyView* (VAR M: Objects.CopyMsg; from, to: View);
BEGIN
	Gadgets.CopyFrame(M, from, to);
	to.vx := from.vx; to.vy := from.vy; to.border := from.border;
	to.ClipMask:= from.ClipMask;
	to.hasVBar:= from.hasVBar; to.hasHBar:= from.hasHBar;
	to.hBar:= from.hBar; to.vBar:= from.vBar
END CopyView;

PROCEDURE ViewAttr (F: View; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.s := "ScrollViews.NewView"; M.class := Objects.String; M.res := 0
		ELSIF M.name = "LineupHY" THEN M.class := Objects.Int; M.i := F.H - Fonts.Default.height; M.res := 0
		ELSIF M.name = "VScrollBar" THEN M.class := Objects.Bool; M.b := F.hasVBar; M.res := 0
		ELSIF M.name = "HScrollBar" THEN M.class := Objects.Bool; M.b := F.hasHBar; M.res := 0
		ELSIF M.name = "Locked" THEN M.class := Objects.Bool; M.b := Gadgets.lockedcontents IN F.state; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "VScrollBar" THEN
			IF M.class = Objects.Bool THEN
				IF F.hasVBar # M.b THEN
					F.hasVBar:= M.b;
					IF M.b THEN INC(F.vx, BarW) ELSE DEC(F.vx, BarW) END;
					UpdateBars(F)
				END; 
				M.res := 0
			END
		ELSIF M.name = "HScrollBar" THEN
			IF M.class = Objects.Bool THEN
				F.hasHBar:= M.b; UpdateBars(F); 
				M.res := 0
			END
		ELSIF M.name = "Locked" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN
					F.state := F.state + {Gadgets.lockedcontents}
				ELSE
					F.state := F.state - { Gadgets.lockedcontents}
				END;
				M.res := 0
			END
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("HScrollBar"); M.Enum("VScrollBar"); M.Enum("Locked"); Gadgets.framehandle(F, M)
	END
END ViewAttr;

PROCEDURE ViewLinks (F: View; VAR M: Objects.LinkMsg);
BEGIN
	IF M.id = Objects.set THEN
		IF M.name = "Model" THEN
			IF M.obj # F.obj THEN
				F.obj := M.obj;
				IF F.border < 1 THEN F.vx := 0; F.vy := 0 ELSE F.vx := F.border; F.vy := -F.border END;
				IF F.hasVBar THEN INC(F.vx, BarW) END;
				UpdateBars(F)
			END;
			M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSE Gadgets.framehandle(F, M)
	END
END ViewLinks;

PROCEDURE ViewHandler* (F: Objects.Object; VAR M: Objects.ObjMsg);
VAR F0: View; f: Gadgets.Frame; vNo: LONGINT; x, y, w, h, u, v: INTEGER; 
		D: Display.DisplayMsg; S: Display.SelectMsg;
BEGIN
	WITH F: View DO
		IF M IS Objects.AttrMsg THEN ViewAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.LinkMsg THEN ViewLinks(F, M(Objects.LinkMsg))
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyView(M, F, F0); M.obj := F0
				END
			END
		ELSIF M IS Objects.FileMsg THEN (* ps - 9.5.96 *)
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteNum(M.R, VersionNo);
					Files.WriteInt(M.R, F.vx); Files.WriteInt(M.R, F.vy);
					Files.WriteInt(M.R, F.border);
					Files.WriteBool(M.R, F.hasVBar);
					IF F.hasVBar THEN
						Files.WriteInt(M.R, F.vBar.backC); Files.WriteNum(M.R,F.vBar.min);
						Files.WriteNum(M.R, F.vBar.max); Files.WriteNum(M.R, F.vBar.val)
					END;
					Files.WriteBool(M.R, F.hasHBar);
					IF F.hasHBar THEN
						Files.WriteInt(M.R, F.hBar.backC); Files.WriteNum(M.R, F.hBar.min);
						Files.WriteNum(M.R, F.hBar.max); Files.WriteNum(M.R, F.hBar.val)
					END;
					Gadgets.framehandle(F, M);
				ELSIF M.id = Objects.load THEN
					Files.ReadNum(M.R, vNo);
					Files.ReadInt(M.R, F.vx); Files.ReadInt(M.R, F.vy);
					Files.ReadInt(M.R, F.border);
					Files.ReadBool(M.R, F.hasVBar);
					IF F.hasVBar THEN
						Files.ReadInt(M.R, F.vBar.backC); Files.ReadNum(M.R, F.vBar.min);
						Files.ReadNum(M.R, F.vBar.max); Files.ReadNum(M.R, F.vBar.val)
					END;
					Files.ReadBool(M.R, F.hasHBar);
					IF F.hasHBar THEN
						Files.ReadInt(M.R, F.hBar.backC); Files.ReadNum(M.R, F.hBar.min);
						Files.ReadNum(M.R, F.hBar.max); Files.ReadNum(M.R, F.hBar.val)
					END;
					Gadgets.framehandle(F, M);
					IF (F.obj # NIL) & ~(F.obj IS Display.Frame) THEN
						F.obj := NIL;
						Texts.WriteString(W, "Discarding dummy object in View"); Texts.WriteLn(W); 
						Texts.Append(Oberon.Log, W.buf);
					END
				END
			END
		ELSIF M IS Objects.BindMsg THEN Gadgets.framehandle(F, M)
		ELSIF M IS Objects.FindMsg THEN Gadgets.framehandle(F, M)
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				x := M.x + F.X; y := M.y + F.Y; w:= F.W; h:= F.H;
				u := M.x; v := M.y; (* save *)
				IF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg DO
						IF M.device = Display.screen THEN
							IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
								RestoreView(F, x, y, M.dlink)
							ELSIF (M.id = Display.area) & (M.F = F) THEN
								RestoreViewArea(F, x, y, M.u, M.v, M.w, M.h, M.dlink)
							ELSIF F.obj # NIL THEN
								f := F.obj(Gadgets.Frame);
								IF (M.F = f) & (Gadgets.transparent IN f.state) THEN
									RestoreViewArea(F, x, y, F.vx, F.vy-f.H + 1, f.W, f.H, M.dlink)
								END;
								ToFrame(F, x, y, M)
							END
						ELSIF M.device = Display.printer THEN
							PrintView(F, M)
						ELSE ToFrame(F, x, y, M)
						END
					END
				ELSIF M IS Display.ConsumeMsg THEN Consume(F, x, y, M(Display.ConsumeMsg))
				ELSIF M IS Gadgets.UpdateMsg THEN 
					WITH M: Gadgets.UpdateMsg DO
						IF M.obj = F THEN
							UpdateBars(F);
							D.id := Display.full; D.device := Display.screen; D.F := F;
							Display.Broadcast(D)
						ELSIF M.obj = F.obj THEN
							D.id := Display.full; D.device := Display.screen; D.F := F;
							Display.Broadcast(D);
							ToFrame(F, x, y, M)
						ELSE ToFrame(F, x, y, M)
						END
					END
				ELSIF M IS Oberon.InputMsg THEN
					WITH M: Oberon.InputMsg DO
						IF (M.id = Oberon.track) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN
							IF (M.keys # {}) & (M.keys # {2}) & Effects.InBorder(M.X, M.Y, x, y, w, h) THEN
								(* track move or size of view *)
								Gadgets.framehandle(F, M)
							ELSIF ~(Gadgets.selected IN F.state) THEN TrackView(F, M)
							END
						ELSE ToFrame(F, x ,y, M)
						END
					END
				ELSIF M IS Oberon.ControlMsg THEN 
					WITH M: Oberon.ControlMsg DO
						IF (M.id = Oberon.neutralize) & (M.stamp # F.stamp) THEN
							F.stamp:= M.stamp;
							IF (F.time # 0) & (F.obj # NIL) THEN (* was selected *)
								Oberon.RemoveMarks(x, y, w, h);
								S.obj:= F.obj; S.F:= F.obj(Display.Frame); S.res:= -1; Objects.Stamp(S);
								S.id:= Display.reset; S.dlink:= M.dlink; ToFrame(F, x, y, S);
								Gadgets.Update(F.obj)
							END;
							F.time := 0
						END;
						ToFrame(F, x ,y, M)	(* ps - 9.5.96 *)				
					END
				ELSIF M IS Display.LocateMsg THEN 
					WITH M: Display.LocateMsg DO
						IF (M.loc = NIL) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN Locate(F, M) END
					END
				ELSIF M IS Display.SelectMsg THEN 
					WITH M: Display.SelectMsg DO
						IF M.id = Display.get THEN
							IF (F.time > M.time) & (F.obj # NIL) & (Gadgets.selected IN F.obj(Gadgets.Frame).state) THEN
								M.obj := F.obj; M.time := F.time; M.sel := F
							END;
							ToFrame(F, x, y, M)
						ELSIF M.F = F THEN Gadgets.framehandle(F, M);
						ELSIF (F.obj # NIL) & (M.F = F.obj) & (M.stamp # F.stamp) THEN
							F.stamp := M.stamp; ToFrame(F, x, y, M); Gadgets.Update(F.obj); M.res := 0
						ELSE ToFrame(F, x, y, M);
						END
					END
				ELSIF M IS Display.ModifyMsg THEN
					WITH M: Display.ModifyMsg DO
						IF M.F = F THEN
							IF F.obj # NIL THEN CleverAdjust(F, M) ELSE Adjust(F, M) END
						ELSIF M.F = F.obj THEN AdjustChild(F, x, y, w, h, M)
						ELSE ToFrame(F, x, y, M)
						END
					END
				ELSIF M IS Display.ControlMsg THEN
					WITH M: Display.ControlMsg DO
						IF (M.id = Display.remove) & (M.F = F.obj) THEN
							F.obj := NIL; UpdateBars(F); Gadgets.Update(F)
						ELSIF (M.id = Display.restore) & ((M.F = NIL) OR (M.F = F)) THEN
							UpdateBars(F); ToFrame(F, x, y, M)
						ELSE ToFrame(F, x, y, M)
						END
					END
				ELSIF M IS Display3.OverlapMsg THEN Gadgets.framehandle(F, M)
				ELSIF M IS Display3.UpdateMaskMsg THEN UpdateMask(F, x, y, M(Display3.UpdateMaskMsg))
				ELSE ToFrame(F, x, y, M)	
				END;
				M.x := u; M.y := v (* restore *)
			END
		ELSIF F.obj # NIL THEN F.obj.handle(F.obj, M)
		END
	END
END ViewHandler;

PROCEDURE InitView* (F: View; vBar, hBar: BOOLEAN);
BEGIN
	F.W := 120; F.H := 120; F.border := 1; F.handle := ViewHandler;
	F.ClipMask:= MakeMask;
	F.hasVBar:= vBar; F.hasHBar:= hBar;
	F.vx:= 0; F.vy:= 0;
	InitBar(F.vBar, 0, 0, 0, Views.background, TRUE, F.H - 2*F.border);
	InitBar(F.hBar, 0, 0, 0, Views.background, FALSE, F.W - BarW - 2*F.border)
END InitView;

PROCEDURE NewView*;
VAR F: View;
BEGIN NEW(F); InitView(F, TRUE, TRUE); Objects.NewObj := F
END NewView;

(** Create a camera-view of F. *)
PROCEDURE ViewOf* (F: Display.Frame): View;
VAR V: View;
BEGIN
	NewView; V := Objects.NewObj(View); V.obj := F;
	IF V.border < 1 THEN V.vx := 0; V.vy := 0
	ELSE V.vx := V.border; V.vy := -V.border
	END;
	IF V.hasVBar THEN INC(V.vx, BarW) END;
	RETURN V
END ViewOf;

(** enable/disable vertical and horizontal bars of view F. *)
PROCEDURE SetBars* (F: View; vBar, hBar: BOOLEAN);
BEGIN
	IF vBar # F.hasVBar THEN
		IF vBar THEN INC(F.vx, BarW) ELSE DEC(F.vx, BarW) END;
		F.hasVBar:= vBar
	END;
	F.hasHBar:= hBar;
	UpdateBars(F); Gadgets.Update(F)
END SetBars;

BEGIN Texts.OpenWriter(W)
END ScrollViews.

(**
ScrollView
Create with:	Gadgets.Insert ScrollViews.NewView
Alias:	-
Function:	Click for a description of Views. The horizontal and vertical scrollbars of a ScrollView can be enabled or disabled through the corresponding attributes. If both bars are disabled, ScrollViews acts like a normal view.
Attributes:
	HScrollBar	enable/disable horizontal scrollbar
	VScrollBar	enable/disable vertical scrollbar
Links:
*)
