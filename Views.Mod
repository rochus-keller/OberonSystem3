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

MODULE Views;	(** portable *) (* jm 19.1.95 *)

(** Implementation of camera-views with adjustable viewpoints.
 *)

(*
	jm 3.2.93 - OpenViewer systemtrack flag
	jm 15.2.93 - Update optimized for menuviewers
	jm 26.2.93 - Printing trap
		- Heavyweight dragging changed
	5.4.93 - fixed attrmsg
		- fixed selection color
	13.4.93 - introduced hotspot
	
	Fri, 10-Sep-1993 Thrown out Backdrops, Heavydrag, loading, storing, printing
	4.4.94 - GetBlock, RestoreBlock: if not otherwise possible the background bitmap is used
	25.7.94 - return selection correctly
	8.11.94 - removed check of 31 flag
	7.2.95 - fixed loading of views with dummy objects
	21.6.95 - Views are now always created with border = 1
*)

IMPORT
	Objects, Fonts, Gadgets, Display, Display3, Effects, Oberon, Texts, Files, Printer, Printer3;

CONST
	VersionNo = 2;
	
TYPE
	View* = POINTER TO ViewDesc;
	ViewDesc* = RECORD (Gadgets.ViewDesc)
		(** Relative viewpoint of viewer object. Vector from top-left camera-view corner to top-left of contents. *)
		vx*, vy*: INTEGER;
		time*: LONGINT; (** Selection time of viewed gadget. *)
	END;
	
	(** Structure to "store" an area on the display *)
	Block* = RECORD
		mask*: Display3.Mask;	(** Mask bounding the area to be drawn in. *)
		x, y, w, h: INTEGER;
		view: Display.Frame;
	END;
	
VAR
	background*: INTEGER;	(** Background color of camera-views *)
	last: View;
	W: Texts.Writer;
	
PROCEDURE Log;
BEGIN Texts.Append(Oberon.Log, W.buf) END Log;

PROCEDURE Max(x, y: INTEGER): INTEGER;
BEGIN IF x > y THEN RETURN x; ELSE RETURN y; END;
END Max;

PROCEDURE Min(x, y: INTEGER): INTEGER;
BEGIN IF x < y THEN RETURN x; ELSE RETURN y; END;
END Min;

(* background drawing procedure *)
PROCEDURE ReplConst(F: View; X, Y: INTEGER; M: Display3.Mask; col, x, y, w, h: INTEGER);
VAR cx, cy, cw, ch, t: INTEGER;
BEGIN
	(* Display3.ReplConst(M, col, x, y, w, h, Display.replace) *)
	cx := M.X; cy := M.Y; cw := M.W; ch := M.H;
	Display3.AdjustMask(M, x, y, w, h);
	IF F.border <= 1 THEN
		Display3.FilledRect3D(M, Display3.topC, Display3.bottomC, col, X, Y, F.W, F.H, 1, Display.replace)
	ELSE
		Display3.Rect(M, Display3.black, Display.solid, X, Y, F.W, F.H, 1, Display.replace);
		t := F.border - 2;
		IF t > 0 THEN Display3.Rect(M, Display3.white, Display.solid, X+1, Y+1, F.W-2, F.H-2, t, Display.replace) END;
		t := F.border - 1;
		IF t < 0 THEN t := 0 END;
		Display3.FilledRect3D(M, Display3.black, Display3.black, col, X+t, Y+t, F.W-t*2, F.H-t*2, 1, Display.replace)
	END;
	M.X := cx; M.Y := cy; M.W := cw; M.H := ch;
END ReplConst;

(* --- stack ops --- *)

PROCEDURE ToFrame(F: View; u, v: INTEGER; VAR M: Display.FrameMsg);
VAR y: INTEGER; B: Display3.UpdateMaskMsg;
BEGIN
	IF (F.obj # NIL) & (F.obj IS Display.Frame) THEN
		IF F.mask = NIL THEN
			B.F := F; Display.Broadcast(B);
			IF F.mask = NIL THEN
				NEW(F.mask); Display3.Open(F.mask); Display3.Add(F.mask, 0, -F.H+1, F.W, F.H);
				F.mask.x := 0; F.mask.y := 0
			END;
		END;
		M.x := u + (F.vx - F.obj(Display.Frame).X); 
		M.y := v + (F.vy - (F.obj(Display.Frame).Y + F.obj(Display.Frame).H - 1));
		y := v - F.H + 1;
		Gadgets.Send(F, u, y, F.obj(Display.Frame), M);
	END;
END ToFrame;

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

PROCEDURE CutoutBack(F: View; R: Display3.Mask; x, y, w, h, X, Y, W, H: INTEGER);
VAR B, T, nH: INTEGER;
	
	PROCEDURE Enum(x1, y1, w1, h1: INTEGER);
	BEGIN IF (w1 > 0) & (h1 > 0) THEN ReplConst(F, X, Y , R, background, x1, y1, w1, h1) END;
	END Enum;
	
BEGIN
	B := Y;
	IF y > Y THEN (* bottom block *) B := y; Enum(X, Y, W, Min(H, y - Y)) END;
	T := Y + H;
	IF y + h < Y + H THEN (* top block *) T := y + h; Enum(X, T, W, Min(H, Y + H - T)) END;
	nH := T - B (*+ 1 !!!!*);
	IF x > X THEN (* left block *) Enum(X, B, Min(W, x - X), nH) END;
	IF x + w < X + W THEN (* right block *) Enum(x + w, B, Min(W, X + W - (x + w)), nH) END;
END CutoutBack;

PROCEDURE RestoreView(F: View; x, y: INTEGER; dlink: Objects.Object);
VAR M: Display.DisplayMsg; w, h, col, cx, cy, cw, ch: INTEGER; R: Display3.Mask; f: Display.Frame;
BEGIN
	w := F.W; h := F.H; 
	Oberon.RemoveMarks(x, y, w, h);
	Gadgets.MakeMask(F, x, y, dlink, R);
	col := background;
	IF (F.obj # NIL) & (F.obj IS Display.Frame) THEN
		f := F.obj(Display.Frame);
		IF (f IS Gadgets.Frame) & (Gadgets.transparent IN f(Gadgets.Frame).state) THEN
			ReplConst(F, x, y, R, col, x, y, w, h);
		ELSE
			cx := x + F.vx; cy := y + F.H + F.vy - f.H; cw := f.W; ch := f.H; (* area of child frame *)
			ClipAgainst(cx, cy, cw, ch, x + F.border, y + F.border, w - F.border * 2, h - F.border * 2);
			CutoutBack(F, R, cx, cy, cw, ch, x, y, w, h)
		END;
		M.device := Display.screen; M.id := Display.full; M.F := NIL; M.dlink := dlink; M.res := -1;
		ToFrame(F, x, y + h - 1, M)
	ELSE
		ReplConst(F, x, y, R, col, x, y, w, h);
		Display3.CenterString(R, Display3.FG, x, y, w, h, Fonts.Default, "Empty View", Display3.textmode);
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreView;

PROCEDURE RestoreViewArea(F: View; x, y, u, v, w1, h1: INTEGER; dlink: Objects.Object);
VAR M: Display.DisplayMsg; w, h, col, cx, cy, cw, ch: INTEGER; R: Display3.Mask; f: Display.Frame;
BEGIN
	w := F.W; h := F.H; 
	Gadgets.MakeMask(F, x, y, dlink, R);
	col := background;
	Oberon.RemoveMarks(x, y, w, h);
	Display3.AdjustMask(R, x + u, y + h - 1 + v, w1, h1);
	IF (F.obj # NIL) & (F.obj IS Display.Frame) THEN
		f := F.obj(Display.Frame);
		IF (f IS Gadgets.Frame) & (Gadgets.transparent IN f(Gadgets.Frame).state) THEN
			ReplConst(F, x, y, R, col, x, y, w, h)
		ELSE
			cx := x + F.vx; cy := y + F.H + F.vy - f.H; cw := f.W; ch := f.H; (* area of child frame *)
			ClipAgainst(cx, cy, cw, ch, x + F.border, y + F.border, w - F.border * 2, h - F.border * 2);
			CutoutBack(F, R, cx, cy, cw, ch, x, y, w, h)
		END;
		ClipAgainst(u, v, w1, h1, F.vx, F.vy - f.H + 1, f.W, f.H);
		M.u := u - F.vx; M.v := v - F.vy; M.w := w1; M.h := h1;
		M.device := Display.screen; M.id := Display.area; M.F := f; M.dlink := dlink; M.res := -1;
		ToFrame(F, x, y + h - 1, M)
	ELSE
		ReplConst(F, x, y, R, col, x, y, w, h);
		Display3.CenterString(R, Display3.FG, x, y, w, h, Fonts.Default, "Empty View", Display3.textmode);
	END;
	IF Gadgets.selected IN F.state THEN Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint) END;
END RestoreViewArea;

PROCEDURE AdjustToFrame(F: View; u, v: INTEGER; VAR M: Display.ModifyMsg);
VAR y: INTEGER; B: Display3.UpdateMaskMsg;
BEGIN
	IF F.obj # NIL THEN
		IF F.mask = NIL THEN B.F := F; Display.Broadcast(B) END;
		M.x := u + F.vx - M.X; M.y := v + F.vy - M.Y - M.H + 1;
		y := v - F.H + 1;
		Gadgets.Send(F, u, y, F.obj(Display.Frame), M);
	END;
END AdjustToFrame;

PROCEDURE AdjustChild(F: View; x, y, w, h: INTEGER; VAR M: Display.ModifyMsg);
VAR RM, R: Display3.Mask; cx, cy: INTEGER;
BEGIN
	IF (M.F = F.obj) THEN
		IF last = F THEN (* moved or resized in this view *)
			IF M.stamp # F.stamp THEN
				cx := F.vx + M.dX; cy := F.vy + (M.dY + M.dH) - M.H + 1;
			ELSE cx := F.vx; cy := F.vy - M.H + 1;
			END;
			IF (M.id = Display.move) & ~Effects.Intersect(cx, cy, M.W, M.H, 0, -F.H+1, F.W, F.H) THEN
				(* completely out of bound, ignore *)
				M.res := 0;
				RETURN; 
			END;
			IF M.stamp # F.stamp THEN
				F.vx := F.vx + M.dX; F.vy := F.vy + (M.dY + M.dH);
				F.stamp := M.stamp;
			END;
			Gadgets.MakeMask(F, x, y, M.dlink, RM);
			Display3.Copy(RM, R); R.x := 0; R.y := 0;
			Display3.Intersect(R, F.vx - M.dX, F.vy - (M.dY + M.dH)- (M.H - M.dH) + 1, M.W - M.dW, M.H - M.dH);
			IF (M.F IS Gadgets.Frame) & ~(Gadgets.transparent IN M.F(Gadgets.Frame).state) THEN
				Display3.Subtract(R, F.vx, F.vy - M.H + 1, M.W, M.H)
			END;
			R.x := x; R.y := y + h - 1;
			ReplConst(F, x, y, R, background, x+F.border, y+F.border, w-F.border*2, h-F.border*2);
			AdjustToFrame(F, x, y + h - 1, M);
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
			ReplConst(F, x, y, R, background, x+F.border, y+F.border, w-F.border*2, h-F.border*2);
			AdjustToFrame(F, x, y + h - 1, M);
			IF Gadgets.selected IN F.state THEN
				Display3.FillPattern(RM, 15, Display3.selectpat, x, y, x, y, w, h, Display.paint)
			END
		END
	ELSE
		ToFrame(F, x, y+h-1, M);
	END
END AdjustChild;

PROCEDURE CopyView*(VAR M: Objects.CopyMsg; from, to: View);
BEGIN
	Gadgets.CopyFrame(M, from, to); to.vx := from.vx; to.vy := from.vy; to.border := from.border;
END CopyView;

PROCEDURE StoreView(F: View; VAR M: Objects.FileMsg);
BEGIN
	Files.WriteNum(M.R, VersionNo);
	Files.WriteInt(M.R, F.vx); Files.WriteInt(M.R, F.vy);
	Files.WriteInt(M.R, 0); (* hack *)
	Gadgets.framehandle(F, M)
END StoreView;

PROCEDURE LoadView(F: View; VAR M: Objects.FileMsg);
VAR x: LONGINT; dummy: INTEGER;
BEGIN
	Files.ReadNum(M.R, x);
	IF x # VersionNo THEN
		Texts.WriteString(W, "Version "); Texts.WriteInt(W, VersionNo, 3);
		Texts.WriteString(W, " of Views cannot read version "); Texts.WriteInt(W, x, 3);
		Texts.WriteLn(W); Log;
		HALT(42)
	END;
	Files.ReadInt(M.R, F.vx); Files.ReadInt(M.R, F.vy);
	Files.ReadInt(M.R, dummy);
	Gadgets.framehandle(F, M);
	IF (F.obj # NIL) & ~(F.obj IS Display.Frame) THEN
		F.obj := NIL;
		Texts.WriteString(W, "Discarding dummy object in View"); Texts.WriteLn(W); 
		Texts.Append(Oberon.Log, W.buf);
	END
END LoadView;

PROCEDURE ViewAttr(F: View; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.s := "Views.NewView"; M.class := Objects.String; M.res := 0
		ELSIF M.name = "Locked" THEN M.class := Objects.Bool; M.b := Gadgets.lockedcontents IN F.state; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Locked" THEN
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
		M.Enum("Locked"); Gadgets.framehandle(F, M)
	END
END ViewAttr;

PROCEDURE ViewLink(F: View; VAR M: Objects.LinkMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Model" THEN M.obj := F.obj; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name # "Model" THEN Gadgets.framehandle(F, M) END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Model"); Gadgets.framehandle(F, M)
	END
END ViewLink;

PROCEDURE Absolute(dlink: Objects.Object): BOOLEAN;
VAR A: Objects.AttrMsg;
BEGIN
	IF (dlink # NIL) & (dlink.handle # NIL) THEN (* NIL test because of Script *)
		A.id := Objects.get; A.name := "Absolute"; A.res := -1; dlink.handle(dlink, A);
		RETURN (A.res >= 0) & (A.class = Objects.Bool) & A.b
	ELSE RETURN FALSE
	END
END Absolute;

PROCEDURE CleverAdjust(F: View; VAR M: Display.ModifyMsg; VAR stamp: LONGINT; borderW: INTEGER);
VAR x, y, w, h, x0, y0, w0, h0, x1, y1, w1, h1: INTEGER; D: Display.DisplayMsg; abs: BOOLEAN;
BEGIN
	(* calculate old position *)
	abs := Absolute(M.dlink);
	x := M.X - M.dX; y := M.Y - M.dY; w := M.W - M.dW; h := M.H - M.dH;
	
	IF abs & (M.W = w) & (M.X = x) & (M.Y = y) & (h # 0) THEN (* In MenuViewer, width did not change, grow up/down *)
		(* Special optimization *)
		IF M.H > h THEN (* copy up *)
			h1 := M.H - h;
			Display.CopyBlock(x, y, w, h, x, M.Y + h1, Display.replace);
		ELSE (* copy down *)
			h1 := h - M.H;
			Display.CopyBlock(x, y + h1 + F.border, w, M.H - F.border, M.X, M.Y + F.border, Display.replace);
		END;
		IF M.stamp # stamp THEN (* first adjust *) 
			F.X := M.X; F.Y := M.Y; F.W := M.W; F.H := M.H; F.mask := NIL; stamp := M.stamp;
		END;
		IF M.H > h THEN (* copy up, restore bottom part *)
			RestoreViewArea(F, F.X, F.Y, 0, -F.H + 1, F.W, h1 + F.border, NIL);
		END
	ELSIF (M.X = x) & (M.Y + M.H = y + h) THEN (* left top most corner is stable *) (* << remove *)
		IF (M.mode = Display.display) THEN
			(* extend / reduce Y *)
			w0 := 0; h0 := 0;
			IF M.H > h THEN (* extend *)
				x0 := 0; y0 := -M.H + 1; w0 := M.W; h0 := y - M.Y + borderW;
			ELSIF M.H < h THEN (* reduce *)
				x0 := 0; y0 := -M.H + 1; w0 := M.W; h0 := borderW;
			END;
			
			(* extend / reduce X *)
			w1 := 0; h1 := 0;
			IF M.W > w THEN (* extend *)
				x1 := w - borderW; y1 := -M.H + 1;  w1 := M.W - w + 1 + borderW; h1 := M.H;
			ELSIF M.W < w THEN (* reduce *)
				x1 := M.W - borderW; y1 := -M.H + 1; w1 := borderW; h1 := M.H;
			END;
			IF (w1 # 0) & (h1 # 0) THEN (* eliminate overlap *) INC(y1, h0); DEC(h1, h0);
			END
		END;
		IF M.stamp # stamp THEN (* first adjust *) 
			F.X := M.X; F.Y := M.Y; F.W := M.W; F.H := M.H; F.mask := NIL; (* invalidate current mask *) stamp := M.stamp;
		END;
		IF (M.mode = Display.display) THEN
			IF (w0 # 0) & (h0 > 0) THEN
				D.F := F; D.x := M.x; D.y := M.y; D.F := F; D.id := Display.area; D.device := Display.screen;
				D.u := x0; D.v := y0; D.w := w0; D.h := h0; 
				Objects.Stamp(D); D.dlink := M.dlink; D.res := -1;
				F.handle(F, D)
			END;
			IF (w1 # 0) & (h1 > 0) THEN
				D.F := F; D.x := M.x; D.y := M.y; D.F := F; D.id := Display.area; D.device := Display.screen;
				D.u := x1; D.v := y1; D.w := w1; D.h := h1; 
				Objects.Stamp(D); D.dlink := M.dlink; D.res := -1;
				F.handle(F, D)
			END
		END
	ELSE Gadgets.framehandle(F, M)
	END
END CleverAdjust;

PROCEDURE PrintView(F: View; VAR M: Display.DisplayMsg);
VAR R: Display3.Mask; u, v: INTEGER; f: Display.Frame;

	PROCEDURE PP(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END PP;

BEGIN
		Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
		Printer3.Rect(R, 15, Display.solid, M.x, M.y, PP(F.W), PP(F.H), 1, Display3.replace);
		IF F.obj # NIL THEN
			f := F.obj(Display.Frame);
			u := M.x; v := M.y;
			M.x := u + PP(F.vx + f.X); M.y := v + PP(F.H + F.vy - f.H + f.Y);
			Gadgets.Send(F, u, v, f, M)
		ELSE
			Printer3.CenterString(R, Display3.FG, M.x, M.y, PP(F.W), PP(F.H), Fonts.Default, "Empty View", Display.paint)
		END
END PrintView;

PROCEDURE Neutralize(F: View; x, y, w, h: INTEGER; VAR M: Oberon.ControlMsg);
VAR S: Display.SelectMsg;
BEGIN
	F.stamp := M.stamp;
	IF (F.time # 0) & (F.obj # NIL) THEN (* selected *)
		Oberon.RemoveMarks(x, y, w, h);
		S.obj := F.obj; S.F := F.obj(Display.Frame); S.res := -1; Objects.Stamp(S);
		S.id := Display.reset; S.dlink := M.dlink;
		ToFrame(F, x, y + h - 1, S);
		Gadgets.Update(F.obj)
	END;
	F.time := 0
END Neutralize;

PROCEDURE Locate(F: View; x, y, w,h :INTEGER; VAR M: Display.LocateMsg);
VAR cx: INTEGER; L: Display.LocateMsg;
BEGIN
	IF (M.loc = NIL) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN
		L.dlink := M.dlink; L.X := M.X; L.Y := M.Y; L.F := NIL; L.loc := NIL; L.res := -1;
		Objects.Stamp(L); ToFrame(F, x, y + h - 1, L);
		IF L.loc # NIL THEN
			M.loc := L.loc; M.x := L.x; M.y := L.y; M.u := L.u; M.v := L.v; M.res := 0
		ELSIF F.obj # NIL THEN
			M.loc := F; M.u := M.X - (x + F.vx - F.obj(Display.Frame).X);
			cx := (F.obj(Display.Frame).Y + F.obj(Display.Frame).H - 1);
			M.v := M.Y - (y + h - 1 + F.vy - cx); M.res := 0
		ELSE
			M.loc := F; M.u := M.X - x; M.v := M.Y - (y + h - 1); M.res := 0
		END
	END
END Locate;

PROCEDURE Select(F: View; x, y, w, h: INTEGER; VAR M: Display.SelectMsg);
BEGIN
	IF M.id = Display.get THEN
		IF (F.time > M.time) & (F.obj # NIL) & (Gadgets.selected IN F.obj(Gadgets.Frame).state) THEN
			M.obj := F.obj; M.time := F.time; M.sel := F
		END;
		ToFrame(F, x, y + h - 1, M)
	ELSIF M.F = F THEN
		Gadgets.framehandle(F, M)
	ELSIF (F.obj # NIL) & (M.F = F.obj) & (M.stamp # F.stamp) THEN
		F.stamp := M.stamp; ToFrame(F, x, y + h - 1, M); Gadgets.Update(F.obj); M.res := 0
	ELSE
		ToFrame(F, x, y + h - 1, M)
	END
END Select;
 
PROCEDURE UpdateMask(F: View; x, y, w, h: INTEGER; VAR M: Display3.UpdateMaskMsg);
VAR R: Display3.Mask; O: Display3.OverlapMsg;
BEGIN
	IF M.F = F.obj THEN (* mychild *)
		NEW(R); Display3.Open(R);
		Display3.Add(R, 0, -F.obj(Display.Frame).H+1, F.obj(Display.Frame).W, F.obj(Display.Frame).H);
		O.F := F.obj(Display.Frame); O.x := 0; O.y := 0; O.M := R; O.res := -1;
		O.dlink := NIL; ToFrame(F, x, y + h - 1, O);
		M.res := 0;
	ELSIF M.F = F THEN (* view has to construct its own mask *)
		NEW(F.mask); Display3.Open(F.mask); Display3.Add(F.mask, 0, -F.H+1, F.W, F.H);
		F.mask.x := 0; F.mask.y := 0;
	ELSE ToFrame(F, x, y + h - 1, M);
	END
END UpdateMask;

PROCEDURE Consume(F: View; x, y, w, h: INTEGER; VAR M: Display.ConsumeMsg);
VAR f: Display.Frame; C: Display.ControlMsg; B: Objects.BindMsg;
BEGIN
	IF (M.id = Display.drop) & (M.F = F) THEN
		IF  (F.obj = NIL) & (M.obj IS Display.Frame) THEN
			f := M.obj(Display.Frame); f.slink := NIL;
			IF Gadgets.Recursive(F, f) THEN
				Texts.WriteString(W,"Not allowed, will cause recursive structures"); Log;
			ELSIF (F.lib # NIL) & (f.lib # NIL) & (F.lib # f.lib) & (f.lib.name # "") THEN
				Texts.WriteString(W,"Across library movement not allowed"); Log;
			ELSE
				C.id := Display.remove; C.F := f; Display.Broadcast(C); (* << remove *)
				F.obj := f;
				IF F.border <= 1 THEN F.vx := 0; F.vy := 0
				ELSE F.vx := F.border; F.vy := -F.border
				END;
				f.X := 0; f.Y := 0;
				IF f IS Gadgets.Frame THEN f(Gadgets.Frame).mask := NIL END;
				IF F.lib # NIL THEN B.lib := F.lib; F.obj.handle(F.obj, B) END;
				Gadgets.Update(F); M.res := 0
			END;
		ELSE M.res := 0
		END
	ELSE ToFrame(F, x, y + h - 1, M)
	END
END Consume;

PROCEDURE InHotspot(X, Y, x, y, w, h: INTEGER): BOOLEAN;
CONST size = 10; GravQ = 4; MinGrav = 2;

	PROCEDURE InBorder(mx, my, X, Y, W, H: INTEGER): BOOLEAN;
	VAR hg, vg: INTEGER;
	BEGIN
		IF (W <= Effects.gravity*3) OR (H <= Effects.gravity*3) THEN
			hg := Min(Effects.gravity, Max(W DIV GravQ, MinGrav));
			vg := Min(Effects.gravity, Max(H DIV GravQ, MinGrav));
			RETURN Effects.Inside(mx, my, X + hg, Y, 1, H) OR
			 Effects.Inside(mx, my, X, Y + vg, W, 1) OR
			 Effects.Inside(mx, my, X+W-hg - 1, Y, 1, H) OR
			 Effects.Inside(mx, my, X, Y+H-vg - 1, W, 1);
		ELSE
			RETURN Effects.Inside(mx, my, X+Effects.gravity, Y, 1, H) OR
			 Effects.Inside(mx, my, X, Y+Effects.gravity, W, 1) OR
			 Effects.Inside(mx, my, X+W-Effects.gravity - 1, Y, 1, H) OR
			 Effects.Inside(mx, my, X, Y+H-Effects.gravity - 1, W, 1);
		END;
	END InBorder;
	
BEGIN RETURN Effects.Inside(X, Y, x, y + h - size, size, size) OR InBorder(X, Y, x, y, w, h);
END InHotspot;

PROCEDURE TrackMouse(F: View; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
VAR keysum: SET; Fdlink, Mdlink: Objects.Object; last0: View; f: Display.Frame; L: Display.LocateMsg;
		S: Display.SelectMsg; D: Display.DisplayMsg; C: Objects.CopyMsg;
BEGIN
	IF ~Effects.InBorder(M.X, M.Y, x, y, w, h) (*Gadgets.InActiveArea(F, M)*) & ~(Gadgets.selected IN F.state) THEN
		L.dlink := M.dlink; L.X := M.X; L.Y := M.Y; L.F := NIL; L.loc := NIL; L.res := -1; ToFrame(F, x, y + h - 1, L);
		IF (L.loc # NIL) & ~InHotspot(M.X, M.Y, x, y, w, h) THEN
			(* push *) last0 := last; last := F; ToFrame(F, x, y + h - 1, M); last := last0; (* Pop *)
			IF M.res < 0 THEN (* viewed object did not respond *)
				IF (M.keys = {0}) & (F.obj IS Gadgets.Frame) THEN (* select *)
					S.F := F.obj(Gadgets.Frame); S.res := -1; Objects.Stamp(S);
					IF Gadgets.selected IN F.obj(Gadgets.Frame).state THEN S.id := Display.reset; F.time := 0;
					ELSE S.id := Display.set; F.time := Oberon.Time();
					END;
					keysum := M.keys; S.dlink := M.dlink;
					ToFrame(F, x, y + h - 1, S);
					Oberon.FadeCursor(Oberon.Mouse);
					D.device := Display.screen; D.id := Display.full; D.F := F.obj(Display.Frame); Display.Broadcast(D);
					REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys;
					UNTIL M.keys = {};
					IF keysum = {0, 2} THEN (* RL delete selection *)
						F.obj := NIL; Gadgets.Update(F);
					ELSIF keysum = {0, 1} THEN  (* RM copy to focus *)
						C.id := Objects.deep; C.obj := NIL; Objects.Stamp(C); F.obj.handle(F.obj, C);
						Gadgets.Integrate(C.obj);
					END;
					M.res := 0
				ELSIF (M.keys = {1}) & (F.obj IS Gadgets.Frame) & (Gadgets.selected IN F.obj(Gadgets.Frame).state) &
					 ~(Gadgets.lockedcontents IN F.state) THEN (* move *)
						f := F.obj(Display.Frame);
						(* push *) last0 := last; last := F;
						M.x := x + (F.vx - f.X);
						M.y := y + h - 1 + (F.vy - (f.Y + f.H - 1));
						Fdlink := F.dlink; Mdlink := M.dlink; F.dlink := M.dlink; M.dlink := F;
						IF Effects.InCorner(M.X, M.Y, M.x + f.X, M.y + f.Y, f.W, f.H) & ~(Gadgets.lockedsize IN F.state) THEN
							Gadgets.SizeFrame(f, M)
						ELSE
							Gadgets.MoveFrame(f, M)
						END;
						F.dlink := Fdlink; M.dlink := Mdlink;
						last := last0; (* Pop *)
						M.res := 0
				ELSE Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y)
				END
			END
		(* switch on *)
		ELSIF (M.keys = {1}) & (L.loc # NIL) & (F.obj IS Gadgets.Frame) & InHotspot(M.X, M.Y, x, y, w, h) &
			  ~(Gadgets.lockedcontents IN F.state)  THEN
			 f := F.obj(Display.Frame);
			(* push *) last0 := last; last := F;
			M.x := x + (F.vx - f.X);
			M.y := y + h - 1 + (F.vy - (f.Y + f.H - 1));
			Fdlink := F.dlink; Mdlink := M.dlink; F.dlink := M.dlink; M.dlink := F;
			Gadgets.MoveFrame(f, M);
			F.dlink := Fdlink; M.dlink := Mdlink;
			last := last0; (* Pop *)
			M.res := 0
		ELSIF Effects.InBorder(M.X, M.Y, x, y, w, h) THEN Gadgets.framehandle(F, M)
		ELSE Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y)
		END
	ELSIF Effects.InBorder(M.X, M.Y, x, y, w, h) THEN Gadgets.framehandle(F, M)
	END
END TrackMouse;

PROCEDURE *ViewHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h, u, v: INTEGER; F0: View;
BEGIN
	WITH F: View DO
		IF M IS Objects.AttrMsg THEN ViewAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.LinkMsg THEN ViewLink(F, M(Objects.LinkMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN StoreView(F, M)
				ELSIF M.id = Objects.load THEN LoadView(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyView(M, F, F0); M.obj := F0
				END
			END;
		ELSIF M IS Objects.BindMsg THEN
			Gadgets.framehandle(F, M);
			IF F.obj # NIL THEN F.obj.handle(F.obj, M); END;
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate actual coordinates *)
				u := M.x; v := M.y; (* store volatile info *)
				IF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg  DO
						IF M.device = Display.screen THEN
							IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN RestoreView(F, x, y, M.dlink)
							ELSIF (M.id = Display.area) & (M.F = F) THEN RestoreViewArea(F, x, y, M.u, M.v, M.w, M.h, M.dlink)
							ELSE ToFrame(F, x, y + h - 1, M)
							END
						ELSIF M.device = Display.printer THEN PrintView(F, M)
						ELSE ToFrame(F, x, y + h - 1, M)
						END
					END
				ELSIF M IS Gadgets.UpdateMsg THEN
					WITH M: Gadgets.UpdateMsg DO
						IF M.obj = F.obj THEN RestoreView(F, x, y, M.dlink); ToFrame(F, x, y + h - 1, M);
						ELSE ToFrame(F, x, y + h - 1, M);
						END
					END
				ELSIF M IS Oberon.ControlMsg THEN
					WITH M: Oberon.ControlMsg DO
						IF (M.id = Oberon.neutralize) & (M.stamp # F.stamp) THEN Neutralize(F, x, y, w, h, M) END;
						ToFrame(F, x, y + h - 1, M)
					END
				ELSIF M IS Display.LocateMsg THEN Locate(F, x, y, w, h, M(Display.LocateMsg))
				ELSIF M IS Display.SelectMsg THEN Select(F, x, y, w, h, M(Display.SelectMsg))
				ELSIF M IS Display.ConsumeMsg THEN Consume(F, x, y, w, h, M(Display.ConsumeMsg))
				ELSIF M IS Oberon.InputMsg THEN
					WITH M: Oberon.InputMsg DO
						IF (M.id = Oberon.track) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN TrackMouse(F, x, y, w, h, M)
						ELSE ToFrame(F, x, y + h - 1, M)
						END
					END
				ELSIF M IS Display.ModifyMsg THEN
					WITH M: Display.ModifyMsg DO
						IF (M.F = F) & (F.obj # NIL) THEN CleverAdjust(F, M, F.stamp, F.border)
						ELSIF (M.F = F) THEN Gadgets.Adjust(F, M)
						ELSE AdjustChild(F, x, y, w, h, M);
						END
					END
				ELSIF M IS Display.ControlMsg THEN (* << remove *)
					WITH M: Display.ControlMsg DO
						IF (M.id = Display.remove) & (M.F = F.obj) THEN F.obj := NIL; Gadgets.Update(F)
						ELSIF F.obj # NIL THEN ToFrame(F, x, y + h - 1, M)
						END
					END
				ELSIF M IS Display3.OverlapMsg THEN Gadgets.framehandle(F, M)
				ELSIF M IS Display3.UpdateMaskMsg THEN UpdateMask(F, x, y, w,h, M(Display3.UpdateMaskMsg))
				ELSE ToFrame(F, x, y + h - 1, M)	
				END;
				M.x := u; M.y := v	(* restore volatile info *)
			END
		ELSE
			IF F.obj # NIL THEN F.obj.handle(F.obj, M) END
		END
	END
END ViewHandler;

PROCEDURE InitView*(F: View);
BEGIN F.handle := ViewHandler; F.W := 100; F.H := 100; F.border := 1;
END InitView;

PROCEDURE NewView*;
VAR F: View;
BEGIN
	NEW(F); InitView(F); Objects.NewObj := F; 
END NewView;

(** Create a camera-view of F. *)
PROCEDURE ViewOf*(F: Display.Frame): View;
VAR V: View;
BEGIN
	NewView; V := Objects.NewObj(View); V.obj := F;
	IF V.border <= 1 THEN V.vx := 0; V.vy := 0
	ELSE V.vx := V.border; V.vy := -V.border
	END;
	RETURN V
END ViewOf;

(** Save a description of a rectangular area on the display. RestoreBlock will issue a DisplayMsg to redraw this part of the display. Note that the mask of the Block must be used to draw in the area X, Y, W, H as the camera-view might be clipping parts away. These two procedures provide a portable, safe and memory efficient way of "storing" parts of the display while drawing temporarily. A low level way of saving and restoring areas on the display is provided by Effects, or by module Bitmaps. *)
PROCEDURE GetBlock*(X, Y, W, H: INTEGER; dlink: Objects.Object; VAR b: Block);
VAR obj: Objects.Object; F: Gadgets.Frame;
BEGIN
	b.view := NIL; b.mask := NIL;
	obj := dlink;
	WHILE obj # NIL DO
		IF obj IS Gadgets.View THEN
			WITH obj: Gadgets.View DO
				b.view := obj;
				b.x := X - obj.absX; b.y := Y - (obj.absY + obj.H - 1); b.w := W; b.h := H;
				ClipAgainst(b.x, b.y, b.w, b.h, 0, -obj.H + 1, obj.W, obj.H);
				NEW(F); F.X := 0; F.Y := 0; F.W := W; F.H := H;
				NEW(F.mask); Display3.Open(F.mask); Display3.Add(F.mask, 0, -H + 1, W, H);
				Gadgets.MakeMask(F, X, Y, dlink, b.mask);
				RETURN
			END
		ELSIF ((obj IS Gadgets.Frame) & Absolute(dlink)) THEN (* outside *)
			WITH obj: Display.Frame DO (* must be absolutely positioned *)
				b.view := obj;
				b.x := X - obj.X; b.y := Y - (obj.Y + obj.H - 1); b.w := W; b.h := H;
				ClipAgainst(b.x, b.y, b.w, b.h, 0, -obj.H + 1, obj.W, obj.H);
				NEW(F); F.X := 0; F.Y := 0; F.W := W; F.H := H;
				NEW(F.mask); Display3.Open(F.mask); Display3.Add(F.mask, 0, -H + 1, W, H);
				Gadgets.MakeMask(F, X, Y, dlink, b.mask);
				RETURN
			END
		END;
		obj := obj.dlink
	END;
	
	Effects.OpenMenu(X, Y, W, H);
	NEW(b.mask); Display3.Open(b.mask); 
	Display3.Add(b.mask, X, Y, W, H);
END GetBlock;

(** Restore previously "saved" display area. *)
PROCEDURE RestoreBlock*(b: Block);
VAR M: Display.DisplayMsg;
BEGIN
	IF b.view # NIL THEN
		M.device := Display.screen; M.id := Display.area; M.F := b.view; M.u := b.x; M.v := b.y; M.w := b.w; M.h := b.h;
		Display.Broadcast(M)
	ELSE Effects.CloseMenu
	END
END RestoreBlock;

BEGIN Texts.OpenWriter(W); background := (*12*)14;
END Views.

Gadgets.Insert Views.NewView Panel ~
Views.Open Testy.Panel