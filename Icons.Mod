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

MODULE Icons;	(** portable *) (** jm 19.1.95 *)

(** Implementation of Icons and the Iconizer. Also contains an implementation of a very simple camera-view with fixed viewpoint where no editing of the viewed model is allowed.
*)
(*
	29.3.94 - added Icon printing
	5.4.94 - added support for LinkMsg
	27.4.94 - support for priorityMsg
	5.5.94 - added locking
	7.7.94 - iconizers now open to the bottom in text
	14.7.94 - fixed problems with missing masks
	18.7.94 improved mask handling when displaying views
	25.7.95 icons only move themselves when not locked
	28.8.95 - Icons do not allow non-frames as models
	8.5.96 - added links to iconizers (ps - 8.5.96)
	9.6.96 - added links to icons (ps - 9.5.96)
	28.5.96 - centered icon caption (ps - 28.5.96) 
	20.6.96 - added new hot-doc-icon support (ps - 20.6.96)
	28.6.96 - improoved lineup (ps -28.6.96)
	28.6.96 - send defocus and deselect msg to component when flip (ps -28.6.96)
	27.8.96 - fix dlink in TrackPopup
	1.10.96 - fixed problem with getting right frame when poping
	8.1.97 - removed hot-doc-icon support (ps)
*)

IMPORT
	Objects, Gadgets, Effects, Display, Display3, Texts, Oberon, Files, Input, Fonts, 
	Links, Views, Printer, Printer3, Documents;
	
CONST
	pinsize = 10; offset = 2;

TYPE
	(** Simple camera-view. *)
	View* = POINTER TO ViewDesc;
	ViewDesc* = RECORD (Gadgets.ViewDesc)
	END;
	
	Icon* = POINTER TO IconDesc;
	IconDesc* = RECORD (Gadgets.FrameDesc)
		caption*: ARRAY 64 OF CHAR;	(** Caption text. *)
		col: INTEGER;
		h: INTEGER;
	END;
	
	Iconizer* = POINTER TO IconizerDesc;
	IconizerDesc* = RECORD (Gadgets.FrameDesc)
		closedF*, openF*: Display.Frame;	(** Frames of the closed and open sides of the iconizer. *)
		closed*: BOOLEAN;	(** is it closed or not ? *)
		popup*: BOOLEAN;	(** Does it pop up on a middle-click ? *)
		pin*: BOOLEAN;	(** Display switch pin in top left corner? *)
		sel*: BOOLEAN;	(** Does it allow you to select an item when popping open ? *)
		pos*: BOOLEAN;	(** Do the open and close positions differ ? *)
		poping: BOOLEAN;	(* is poped open at the moment *)
		px, py, oX, oY, cX, cY: INTEGER;
	END;
	
	(* Stack = POINTER TO StackDesc; *)
	StackDesc = RECORD
		iconizer: Iconizer;
		(* next: Stack; *)
	END;
	

VAR
	W: Texts.Writer;
	top: Iconizer;
	
PROCEDURE SetMasks(F: Display.Frame; M: Display3.Mask);
VAR O: Display3.OverlapMsg;
BEGIN
	O.M := M; O.x := 0; O.y := 0; O.F := F; O.dlink := NIL; O.res := -1; F.handle(F, O);
END SetMasks;

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

(* ==================== Views ================== *)

PROCEDURE RestoreView(F: View; R: Display3.Mask; x, y, w, h: INTEGER; VAR M: Display.DisplayMsg);
VAR D: Display.DisplayMsg; f: Gadgets.Frame; state: SET;
BEGIN
	IF (F.obj # NIL) & (F.obj IS Gadgets.Frame) THEN
		f := F.obj(Gadgets.Frame); state := f.state; EXCL(f.state, Gadgets.selected);
		(*
		oldR := f.mask;
		NEW(newR); Display3.Open(newR); 
		Display3.Add(newR, 0, -f.H + 1, f.W, f.H); SetMasks(f, newR);
		*)
		
		IF (M.F = NIL) OR (M.id = Display.full) THEN
			D.dlink := M.dlink; D.device := Display.screen; D.id := Display.full;
			D.F := NIL; D.res := -1; D.x := x - f.X; D.y := y - f.Y;
			Gadgets.Send(F, x, y, f, D);
		ELSIF M.id = Display.area THEN
			D.dlink := M.dlink; D.device := Display.screen; D.id := Display.area; D.F := f;
			D.u := M.u; D.v := M.v; D.w := M.w; D.h := M.h;
			D.res := -1; D.x := x - f.X; D.y := y - f.Y;
			Gadgets.Send(F, x, y, f, D);
		END;
		(*
		SetMasks(f, oldR);
		*)
		f.state := state; (* restore previous state *)
	ELSE
		Display3.FilledRect3D(R, Display.FG, Display.FG, Display.BG, x, y, w, h, 2, Display.paint);
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreView;

PROCEDURE PrintView(F: View; VAR M: Display.DisplayMsg);
VAR R: Display3.Mask; (*PM: Display.DisplayMsg;*)
BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R); (* make sure I have a mask too, and it is positioned correctly *)
	
	(*PM := M;*) Gadgets.Send(F, M.x, M.y, F.obj(Display.Frame), (*P*)M);
END PrintView;

PROCEDURE CopyView*(VAR M: Objects.CopyMsg; from, to: View);
VAR C: Objects.CopyMsg;
BEGIN C.id := Objects.shallow; C.stamp := M.stamp; Gadgets.CopyFrame(C, from, to);
END CopyView;

PROCEDURE ViewHandle*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h, u, v, t: INTEGER; F0: View; A: Display.ModifyMsg; f: Display.Frame; R: Display3.Mask;
BEGIN
	WITH F: View DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN COPY("Icons.NewView", M.s); M.res := 0 END
			END
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN
					Gadgets.framehandle(F, M); INCL(F.state, Gadgets.lockedsize);
					IF (F.obj # NIL) & (F.obj IS Objects.Dummy) THEN
						Texts.WriteString(W, "Discarding "); Texts.WriteString(W, F.obj(Objects.Dummy).GName);
						Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
						F.obj := NIL
					END;
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyView(M, F, F0); M.obj := F0
				END
			END
		ELSIF M IS Objects.BindMsg THEN Gadgets.framehandle(F, M)
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
				u := M.x; v := M.y; (* store volatile info *)
				IF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg  DO
						IF M.device = Display.screen THEN
							IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								RestoreView(F, R, x, y, w, h, M);
							ELSIF (M.id = Display.area) & (M.F = F) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
								RestoreView(F, R, x, y, w, h, M);
							END
						ELSIF M.device = Display.printer THEN
							PrintView(F, M)
						END
					END
				ELSIF M IS Display.ModifyMsg THEN
					WITH M: Display.ModifyMsg DO
						IF M.F = F THEN Gadgets.framehandle(F, M)
						ELSIF M.F = F.obj THEN
							t := M.mode; M.mode := Display.state; F.obj.handle(F.obj, M); M.mode := t;
							A.id := Display.extend; A.mode := Display.display; A.F := F;
							f := F.obj(Display.Frame);
							A.X := F.X; A.Y := F.Y; A.W := f.W; A.H := f.H; A.dX := 0; A.dY := 0; A.dW := A.W - f.W; A.dH := A.H - f.H;
							Display.Broadcast(A);
						ELSIF (F.obj # NIL) THEN F.obj.handle(F.obj, M)
						END
					END
				ELSE Gadgets.framehandle(F, M)
				END;
				M.x := u; M.y := v; (* restore volatile info *)
			END;
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF (M.id = Objects.set) & (M.name = "Model") THEN
					IF (M.obj IS Gadgets.Frame) THEN
						Gadgets.framehandle(F, M);
						A.id := Display.extend; A.mode := Display.display; A.F := F;
						f := F.obj(Display.Frame);
						A.X := F.X; A.Y := F.Y; A.W := f.W; A.H := f.H; A.dX := 0; A.dY := 0; A.dW := A.W - f.W; A.dH := A.H - f.H;
						Display.Broadcast(A)
					ELSE
						Texts.WriteString(W, "  sorry, model is not a Display.Frame"); Texts.WriteLn(W);
						Texts.Append(Oberon.Log, W.buf)
					END
				ELSE Gadgets.framehandle(F, M);
				END
			END
		ELSE Gadgets.framehandle(F, M);
		END;
	END
END ViewHandle;

(** Make a simple camera-view of f. *)
PROCEDURE ViewOf*(f: Gadgets.Frame): View;
VAR F: View;
BEGIN
	NEW(F);
	F.obj := f; F.handle := ViewHandle; F.X := 0; F.Y := 0; F.W := f.W; F.H := f.H; INCL(F.state, Gadgets.lockedsize); RETURN F
END ViewOf;

PROCEDURE InitView*(F: View);
BEGIN F.obj := NIL; F.handle := ViewHandle; F.X := 0; F.Y := 0; F.W := 5; F.H := 5; INCL(F.state, Gadgets.lockedsize)
END InitView;

PROCEDURE NewView*;
VAR F: View;
BEGIN
	NEW(F); InitView(F); Objects.NewObj := F;
END NewView;

(* ==================== end of Views ================== *)

PROCEDURE ToIcon(F: Icon; x, y, w, h: INTEGER; VAR M: Display.FrameMsg);
VAR caph0: INTEGER; obj: Display.Frame;
BEGIN
	IF F.obj # NIL THEN 
		obj := F.obj(Display.Frame); caph0 := F.h + 2;
		M.x := x + w DIV 2 - obj.W DIV 2 - obj.X; M.y := y + caph0 - obj.Y;
		obj.handle(obj, M)
	END
END ToIcon;

PROCEDURE StringSize(s: ARRAY OF CHAR; VAR w, h: INTEGER);
VAR r: Objects.Object; p: INTEGER;
BEGIN
	w := 6; h := 0;
	p := 0;
	WHILE s[p] # 0X DO
		Fonts.Default.GetObj(Fonts.Default, ORD(s[p]), r);
		INC(w, r(Fonts.Char).dx); 
		INC(p);
	END;
	h := Fonts.Default.height + 2;
END StringSize;

PROCEDURE IconSize(F: Icon; VAR w, h: INTEGER);
VAR iw, ih, cw: INTEGER; obj: Objects.Object;
BEGIN
	obj := F.obj;
	IF obj = NIL THEN iw := 0; ih := 0
	ELSIF obj IS Display.Frame THEN iw := obj(Display.Frame).W; ih := obj(Display.Frame).H;
	END;
	StringSize(F.caption, cw, F.h);
	h :=  F.h + ih + 2; (* add caption height *)
	IF cw > iw THEN w := cw
	ELSE w := iw;
	END
END IconSize;

PROCEDURE Change(F: Icon);
VAR M: Display.ModifyMsg; w, h: INTEGER;
BEGIN
	M.id := Display.extend; M.mode := Display.display; M.F := F;
	IconSize(F, w, h);
	M.X := F.X + (F.W - w DIV 2 * 2) DIV 2; M.Y := F.Y + F.H - h; M.W := w; M.H := h;
	M.dX := M.X - F.X; M.dY := M.Y - F.Y; M.dW := M.W - F.W; M.dH := M.H - F.H;
	Display.Broadcast(M);
END Change;

PROCEDURE ForceString(F: Display.Frame; VAR M: Objects.AttrMsg);
BEGIN Gadgets.framehandle(F, M);
	IF M.res < 0 THEN M.class := Objects.String; M.s := ""; M.res := 0 END
END ForceString;

PROCEDURE IconAttr(F: Icon; VAR M: Objects.AttrMsg);
VAR obj: Objects.Object;
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class :=Objects.String; COPY("Icons.NewIcon", M.s); M.res := 0
		ELSIF M.name = "Caption" THEN M.class := Objects.String; COPY(F.caption, M.s); M.res := 0
		ELSIF M.name = "Icon" THEN ForceString(F, M)
		ELSIF M.name = "Cmd" THEN ForceString(F, M)
		ELSIF M.name = "ConsumeCmd" THEN ForceString(F, M)
		ELSE Gadgets.framehandle(F, M);
		END;
	ELSIF M.id = Objects.set THEN
		IF M.name = "Caption" THEN
			IF M.class = Objects.String THEN
				IF M.s # F.caption THEN COPY(M.s, F.caption); Change(F) END;
				M.res := 0
			END
		ELSIF M.name = "Icon" THEN
			IF M.class = Objects.String THEN
				IF M.s # "" THEN
					obj := Gadgets.FindPublicObj(M.s);
					IF (obj # NIL) & (obj IS Gadgets.Frame) THEN
						IF (F.obj # NIL) & (F.obj IS View) & (F.obj(View).obj = obj) THEN (* do nothing *)
						ELSE F.obj := ViewOf(obj(Gadgets.Frame)); Change(F)
						END
					ELSE F.obj := NIL; Change(F)
					END
				END;
				Gadgets.framehandle(F, M)
			END
		ELSE Gadgets.framehandle(F, M);
		END;
	ELSIF M.id = Objects.enum THEN
		M.Enum("Caption"); M.Enum("Icon"); M.Enum("Cmd"); M.Enum("ConsumeCmd");
		Gadgets.framehandle(F, M)
	END
END IconAttr;

PROCEDURE IconLink(F: Icon; VAR M: Objects.LinkMsg);
VAR f: Display.Frame; CM: Display.ControlMsg; B: Objects.BindMsg; 
BEGIN
	IF (M.id = Objects.set) & (M.name = "Model") THEN
		IF M.obj = NIL THEN F.obj:= NIL; Change(F); M.res:= 0
		ELSIF M.obj = F.obj THEN M.res:= 0
		ELSIF M.obj IS Display.Frame THEN
			f:= M.obj(Display.Frame);
			IF Gadgets.Recursive(F, f) THEN
				Texts.WriteString(W,"Not allowed, will cause recursive structures"); Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf)
			ELSIF (F.lib # NIL) & (f.lib # NIL) & (F.lib # f.lib) & (f.lib.name # "") THEN
				Texts.WriteString(W,"Across library movement not allowed");
				Texts.Append(Oberon.Log, W.buf)
			ELSE
				CM.id:= Display.remove; CM.F:= f; Display.Broadcast(CM); (* << remove *)
				IF F.lib # NIL THEN B.lib:= F.lib; f.handle(f, B) END;
				IF f IS Gadgets.Frame THEN
					WITH f: Gadgets.Frame DO
						EXCL(f.state, Gadgets.selected); SetMasks(F, NIL)
					END
				END;
				F.obj:= f;
				Change(F); M.res:= 0
			END
		END
	ELSE Gadgets.framehandle(F, M)
	END
END IconLink;

PROCEDURE RestoreIcon(R: Display3.Mask; F: Icon; x, y, w, h: INTEGER; VAR M: Display.DisplayMsg);
VAR obj: Objects.Object; D: Display.DisplayMsg; cx, cy, cw, ch, caph0: INTEGER;
BEGIN
	caph0 := F.h + 2;
	obj := F.obj;
	IF obj = NIL THEN
		Display3.ReplConst(R, Display3.FG, x + w DIV 2 - 3, y + caph0 + (h - caph0) DIV 2 - 3, 3, 3, Display.replace);
	ELSIF obj IS Display.Frame THEN
		WITH obj: Display.Frame DO
			IF (M.F = NIL) OR (M.id = Display.full) THEN
				D.device := Display.screen; D.id := Display.full; D.F := obj; D.res := -1; D.dlink := M.dlink;
				D.x := x + w DIV 2 - obj.W DIV 2 - obj.X; D.y := y + caph0 - obj.Y;
				obj.handle(obj, D)
			ELSIF M.id = Display.area THEN
				cx := w DIV 2 - obj.W DIV 2; cy := -h + caph0 + 1; cw := obj.W; ch := obj.H;
				ClipAgainst(cx, cy, cw, ch, M.u, M.v, M.w, M.h);
				D.device := Display.screen; D.id := Display.area; D.dlink := M.dlink; D.res := -1;
				D.F := obj; D.x := x + w DIV 2 - obj.W DIV 2 - obj.X; D.y := y + caph0 - obj.Y;
				D.u := cx - (w DIV 2 - obj.W DIV 2); D.v := cy - (-h + caph0 + obj.H); D.w := cw; D.h := ch;
				IF (D.w > 0) & (D.h > 0) THEN obj.handle(obj, D) END
			END
		END
	END;
	
	Display3.FilledRect3D(R, Display3.topC, Display3.bottomC, F.col, x, y, w, F.h + 2, 1, Display.replace);
	(* ps - 28.5.96 *)
	Display3.CenterString(R, Display3.textC, x, y, w, F.h + 2, Fonts.Default, F.caption, Display3.textmode);

	IF Gadgets.selected IN F.state THEN
		IF obj = NIL THEN
			Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		ELSIF obj IS Display.Frame THEN
			WITH obj: Display.Frame DO
				Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x + w DIV 2 - obj.W DIV 2, y + caph0, obj.W, obj.H, Display.paint);
			END
		END;
		Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, caph0, Display.paint)
	END
END RestoreIcon;

PROCEDURE PrintIcon(F: Icon; VAR M: Display.DisplayMsg);
VAR R: Display3.Mask; caph0, w, h: INTEGER; obj: Objects.Object; PM: Display.DisplayMsg;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	caph0 := F.h + 2; w := F.W; h := F.H; obj := F.obj;
	IF obj = NIL THEN
		Printer3.ReplConst(R, Display3.FG, M.x + P(w DIV 2 - 3), M.y + P(caph0 + (h - caph0) DIV 2 - 3), P(3), P(3), Display.replace);
	ELSIF obj IS Display.Frame THEN
		WITH obj: Display.Frame DO
			PM.device := Display.printer; PM.id := Display.full; PM.x := M.x + P(w DIV 2 - obj.W DIV 2); PM.y := M.y + P(caph0);
			PM.res := -1; PM.dlink := M.dlink;
			obj.handle(obj, PM)
		END
	END;
	Printer3.FilledRect3D(R, Display3.topC, Display3.bottomC, F.col, M.x, M.y, P(w), P(F.h + 2), 1, Display.replace);
	Printer3.String(R, Display3.textC, M.x+P(3), M.y + P(ABS(Fonts.Default.minY) + 2), Fonts.Default, F.caption, Display3.textmode)
END PrintIcon;

PROCEDURE LocateMsg(F: Icon; x, y, w, h: INTEGER; VAR M: Display.LocateMsg);
VAR caph: INTEGER; obj: Objects.Object;
BEGIN
	IF (M.loc = NIL) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN
		IF F.obj = NIL THEN M.loc := F; M.u := M.X - x; M.v := M.Y - (y+h-1); M.res := 0; RETURN
		ELSE
			obj := F.obj;
			caph := F.h + 2;
			IF Effects.Inside(M.X, M.Y, x, y, w, caph) THEN M.loc := F; M.u := M.X - x; M.v := M.Y - (y+h-1); M.res := 0; RETURN END;
			IF obj IS Display.Frame THEN
				WITH obj: Display.Frame DO
					IF Effects.Inside(M.X, M.Y, x + w DIV 2 - obj.W DIV 2, y + caph, obj.W, obj.H) THEN
						M.loc := F; M.u := M.X - x; M.v := M.Y - (y+h-1); M.res := 0
					END
				END
			END	
		END
	END
END LocateMsg;

PROCEDURE CopyIcon*(VAR M: Objects.CopyMsg; from, to: Icon);
VAR id: INTEGER;
BEGIN
	id := M.id; M.id := Objects.deep; Gadgets.CopyFrame(M, from, to); M.id := id;
	COPY(from.caption, to.caption); to.h := from.h; to.col := from.col
END CopyIcon;

PROCEDURE Size(F: Icon; VAR x, y, w, h: INTEGER);
VAR obj: Objects.Object;
BEGIN
	obj := F.obj;
	IF obj # NIL THEN
		WITH obj: Display.Frame DO
			x := x + w DIV 2 - obj.W DIV 2; y :=  y + F.h + 2; w := obj.W; h := obj.H;
		END
	END
END Size;

PROCEDURE TrackHighlight(R: Display3.Mask; VAR X, Y: INTEGER; x, y, w, h: INTEGER; VAR keysum: SET);
VAR keys: SET; on: BOOLEAN; xx, yy: INTEGER;

	PROCEDURE High;
	BEGIN
		IF Effects.Inside(xx, yy, x, y, w, h) THEN
			IF ~on THEN Oberon.FadeCursor(Oberon.Mouse);
				Display3.ReplConst(R, Display3.invertC, x, y, w, h, Display.invert); on := TRUE
			END;
		ELSE
			IF on THEN Oberon.FadeCursor(Oberon.Mouse);
				Display3.ReplConst(R, Display3.invertC, x, y, w, h, Display.invert); on := FALSE
			END
		END
	END High;
	
BEGIN
	on := FALSE; keysum := {};
	High;
	LOOP
		Input.Mouse(keys, xx, yy); keysum := keysum + keys;
		IF keys = {} THEN EXIT END;
		High;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, xx, yy);
	END;
	X := xx; Y := yy; xx := -100; yy := -100;
	High;
END TrackHighlight;

PROCEDURE IconTrack(F: Icon; R: Display3.Mask; VAR M: Oberon.InputMsg);
VAR x, y, w, h: INTEGER; keysum: SET;
BEGIN
	x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
	Size(F, x, y, w, h);
	TrackHighlight(R, M.X, M.Y, x, y, w, h, keysum);
	IF Effects.Inside(M.X, M.Y, x, y, w, h) & (keysum = {1}) THEN Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL) END;
END IconTrack;

PROCEDURE HasCmdAttr(F: Display.Frame; attr: ARRAY OF CHAR): BOOLEAN;
VAR A: Objects.AttrMsg;
BEGIN
	A.id := Objects.get; COPY(attr, A.name); A.class := Objects.Inval; A.res := -1; A.dlink := NIL; Objects.Stamp(A);
	F.handle(F, A);
	RETURN (A.res >= 0) & (A.class = Objects.String) & (A.s # "") 
END HasCmdAttr;

PROCEDURE IconHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h, u, v, capw: INTEGER; F0: Icon; f: Display.Frame; B: Objects.BindMsg;
	CM: Display.ControlMsg; C: Objects.CopyMsg; R: Display3.Mask;  ver: LONGINT;
BEGIN
	WITH F: Icon DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO IconAttr(F, M) END;
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteNum(M.R, 1);
					Files.WriteString(M.R, F.caption);
					Files.WriteNum(M.R, 0);
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN
					Files.ReadNum(M.R, ver);
					IF ver # 1 THEN HALT(42) END;
					Files.ReadString(M.R, F.caption);
					Files.ReadNum(M.R, ver);
					Gadgets.framehandle(F, M);
					IF (F.obj # NIL) & (F.obj IS Objects.Dummy) THEN
						Texts.WriteString(W, "Discarding "); Texts.WriteString(W, F.obj(Objects.Dummy).GName);
						Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
						F.obj := NIL
					END;
					(* IconSize(F, F.W, F.H); because the icon might not be loaded yet*)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyIcon(M, F, F0); M.obj := F0
				END
			END
		ELSIF M IS Objects.LinkMsg THEN (* ps - 9.5.96 *)
			IconLink(F, M(Objects.LinkMsg))
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate actual coordinates *)
				u := M.x; v := M.y; (* store volatile info *)
				IF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg  DO
						IF M.device = Display.screen THEN
							IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								RestoreIcon(R, F, x, y, w, h, M);
							ELSIF (M.id = Display.area) & (M.F = F) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
								RestoreIcon(R, F, x, y, w, h, M);
							END
						ELSIF M.device = Display.printer THEN PrintIcon(F, M)
						END
					END
				ELSIF M IS Display.LocateMsg THEN
					WITH M: Display.LocateMsg DO
						LocateMsg(F, x, y, w, h, M)
					END
				ELSIF M IS Display3.OverlapMsg THEN
					WITH M: Display3.OverlapMsg DO
						IF (M.F = NIL) OR (M.F = F) THEN
							F.mask := M.M;
							IF (F.obj # NIL) & (F.obj IS Gadgets.Frame) THEN
								IF F.mask = NIL THEN SetMasks(F.obj(Gadgets.Frame), NIL) 
								ELSE
									f := F.obj(Gadgets.Frame);
									Display3.Copy(M.M, R); R.x := 0; R.y := 0;
								
									Display3.Intersect(R, F.W DIV 2 - f.W DIV 2, -F.H + 1 + F.h + 2, f.W, f.H);
									R.x := -(F.W DIV 2 - f.W DIV 2); R.y := 0; Display3.Shift(R); 
									SetMasks(f, R);
								END
							END;
							M.res := 0
						END
					END
				ELSIF M IS Display.ModifyMsg THEN
					WITH M: Display.ModifyMsg DO
						IF M.F = F THEN Gadgets.framehandle(F, M)
						ELSIF M.F = F.obj THEN
							capw := M.mode; M.mode := Display.state; F.obj.handle(F.obj, M); M.mode := capw; Change(F)
						ELSIF F.obj # NIL THEN ToIcon(F, x, y, w, h, M)
						END
					END
				ELSIF M IS Display.ConsumeMsg THEN
					WITH M: Display.ConsumeMsg DO
						IF (M.F = F) THEN
							IF (M.obj IS Display.Frame) & (F.obj = NIL) THEN
								f := M.obj(Display.Frame); f.slink := NIL;
								IF Gadgets.Recursive(F, f) THEN
									Texts.WriteString(W,"Not allowed, will cause recursive structures"); Texts.WriteLn(W);
									Texts.Append(Oberon.Log, W.buf)
								ELSIF (F.lib # NIL) & (f.lib # NIL) & (F.lib # f.lib) & (f.lib.name # "") THEN
									Texts.WriteString(W,"Across library movement not allowed");
									Texts.Append(Oberon.Log, W.buf)
								ELSE
									CM.id := Display.remove; CM.F := M.obj(Display.Frame); Display.Broadcast(CM); (* << remove *)
									C.id := Objects.deep; Objects.Stamp(C); C.obj := NIL; M.obj.handle(M.obj, C);
									F.obj := C.obj;
									IF F.obj IS Gadgets.Frame THEN EXCL(F.obj(Gadgets.Frame).state, Gadgets.selected); SetMasks(F, NIL) END; 
									IF F.lib # NIL THEN B.lib := F.lib; F.obj.handle(F.obj, B); END;
									Change(F); M.res := 0;
								END;
							ELSIF M.obj IS Display.Frame THEN
								Gadgets.ExecuteAttr(F, "ConsumeCmd", M.dlink, M.obj, F); M.res := 0;
							END;
						ELSE
							Gadgets.framehandle(F, M);
						END
					END
				ELSIF M IS Oberon.InputMsg THEN
					WITH M: Oberon.InputMsg DO
						IF ~(Gadgets.selected IN F.state) THEN
							IF (M.id = Oberon.track) & (M.keys = {1}) THEN
								IF Effects.Inside(M.X, M.Y, x, y, w, F.h + 2) & ~Gadgets.IsLocked(F, M.dlink) THEN
									Gadgets.MoveFrame(F, M)
								ELSIF (* ! Gadgets.InActiveArea(F, M) & *) HasCmdAttr(F, "Cmd")THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									IconTrack(F, R, M); M.res := 0
								(* ! ELSE Gadgets.framehandle(F, M) *)
								END
							ELSE Gadgets.framehandle(F, M)
							END
						ELSE
							Gadgets.framehandle(F, M)
						END
					END
				ELSE
					Gadgets.framehandle(F, M);	
				END;
				M.x := u; M.y := v; (* restore volatile info *)
			END
		ELSE
			Gadgets.framehandle(F, M)
		END
	END
END IconHandler;

(** Manufacture an icon with caption name and icon as content. Icon must be of type frame. Icons is typically a simple camera-view created by ViewOf. *)
PROCEDURE MakeIcon*(F: Icon; name: ARRAY OF CHAR; icon: Objects.Object);
BEGIN
	F.handle := IconHandler; F.obj := icon; F.col := Display3.groupC;
	COPY(name, F.caption); IconSize(F, F.W, F.H); F.state := {Gadgets.lockedsize, Gadgets.transparent}
END MakeIcon;

PROCEDURE NewIcon*;
VAR F: Icon;
BEGIN NEW(F); MakeIcon(F, "Icon", NIL); Objects.NewObj := F;
END NewIcon;

(* ========================= Iconizers ========================= *)

PROCEDURE Push(VAR S: StackDesc; F: Iconizer);
BEGIN S.iconizer := top; top := F
END Push;

PROCEDURE Pop(VAR S: StackDesc);
BEGIN top := S.iconizer
END Pop;

PROCEDURE Top(): Iconizer;
BEGIN RETURN top
END Top;

PROCEDURE To(F: Iconizer; childu, childv: INTEGER; VAR M: Display.FrameMsg);
VAR d: Display.Frame; u, v: INTEGER; Fdlink, Mdlink: Objects.Object;
BEGIN
	IF F.closed & ~F.poping THEN d := F.closedF ELSE d := F.openF END;
	IF d # NIL THEN
		u := M.x; v := M.y;
		M.x := childu; M.y := childv;
		IF F.poping THEN (* coord might have changed *)
			INC(M.x, F.px); INC(M.y, F.py)
		END;
		Fdlink := F.dlink; Mdlink := M.dlink; F.dlink := M.dlink; M.dlink := F;
		d.handle(d, M);
		M.dlink := Mdlink; F.dlink := Fdlink;
		M.x := u; M.y := v;
	END;
END To;

(** Executed from within an iconizer causes it to flip open/close. *)
PROCEDURE Flip*;
VAR A: Display.ModifyMsg; n: Display.Frame; i: Iconizer; CM: Display.ControlMsg; P: Gadgets.PriorityMsg;
	OM: Oberon.ControlMsg;
BEGIN
	i := Top();
	IF i  # NIL THEN
		IF i.pos THEN
			IF i.closed THEN i.cX := i.X; i.cY := i.Y + i.H - 1 ELSE i.oX := i.X; i.oY := i.Y + i.H - 1 END;
		END;
		IF i.closed THEN P.id := Gadgets.top; P.F := i; P.passon := FALSE; Display.Broadcast(P) END;
		
		i.closed := ~i.closed;
		IF i.closed THEN n := i.closedF; ELSE n := i.openF; END;
		i.obj := n;
		IF n = NIL THEN n := i; EXCL(i.state, Gadgets.lockedsize) END;
		IF (n # NIL) & (n IS Gadgets.Frame) THEN
			WITH n: Gadgets.Frame DO
				IF Gadgets.transparent IN n.state THEN INCL(i.state, Gadgets.transparent)
				ELSE EXCL(i.state, Gadgets.transparent)
				END;
				IF Gadgets.lockedsize IN n.state THEN INCL(i.state, Gadgets.lockedsize)
				ELSIF ~(Gadgets.lockedcontents IN i.state) THEN EXCL(i.state, Gadgets.lockedsize)
				END;
				(* send restore message down *)
				CM.id := Display.restore; CM.F := NIL; CM.x := 0; CM.y := 0; CM.dlink := NIL; CM.res := -1; Objects.Stamp(CM);
				n.handle(n, CM);
			END;
		END;
		
		A.id := Display.extend; A.mode := Display.display; A.F := i;
		IF i.pos THEN
			IF i.closed THEN A.X := i.cX; A.Y := i.cY - n.H + 1 ELSE A.X := i.oX; A.Y := i.oY - n.H + 1 END
		ELSE
			A.X := i.X; A.Y := i.Y + i.H - n.H
		END;
		A.W := n.W; A.H := n.H;
		A.dX := A.X - i.X; A.dY := A.Y - i.Y; A.dW := A.W - i.W; A.dH := A.H - i.H;
		SetMasks(i, NIL);
		Display.Broadcast(A);
		
		(* neutralize *)
		OM.id := Oberon.neutralize; OM.F := NIL; OM.x := 0; OM.y := 0; OM.dlink := NIL; OM.res := -1;
		Objects.Stamp(OM); n.handle(n, OM);
	END;
END Flip;

PROCEDURE SetLinkObject(F: Iconizer; f: Display.Frame; closed: BOOLEAN): BOOLEAN;
VAR CM: Display.ControlMsg; A: Display.ModifyMsg; B: Objects.BindMsg;
BEGIN
	IF Gadgets.Recursive(F, f) THEN
		Texts.WriteString(W, "Not allowed, will cause recursive structures"); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf);
		RETURN FALSE
	ELSIF (F.lib # NIL) & (f.lib # NIL) & (F.lib # f.lib) & (f.lib.name # "") THEN
		Texts.WriteString(W, "Across library movement not allowed"); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf);
		RETURN FALSE
	ELSE
		CM.id:= Display.remove; CM.F:= f; Display.Broadcast(CM); (* << remove *)
		
		IF F.lib # NIL THEN B.lib:= F.lib; f.handle(f, B) END; (* << binding *)
		f.next:= NIL;
		IF closed THEN F.closedF:= f ELSE F.openF:= f END;
		IF F.closed = closed THEN (* link is know visible *)
			F.obj:= f;

			A.id:= Display.extend; A.mode:= Display.display; A.F:= F;
			A.X:= F.X; A.Y:= F.Y + F.H - f.H; A.W:= f.W; A.H:= f.H;
			A.dX:= A.X - F.X; A.dY:= A.Y - F.Y; A.dW:= A.W - F.W; A.dH:= A.H - F.H;
			
			IF F.pos THEN F.oX:= F.X; F.oY:= A.Y + A.H - 1; F.cX:= F.oX; F.cY:= F.oY END;
			
			IF f IS Gadgets.Frame THEN
				WITH f: Gadgets.Frame DO
					f.mask:= NIL;
					IF Gadgets.lockedsize IN f.state THEN INCL(F.state, Gadgets.lockedsize)
					ELSIF ~(Gadgets.lockedcontents IN F.state) THEN EXCL(F.state, Gadgets.lockedcontents)
					END;
					
					f.state:= f.state - {Gadgets.selected};
					IF Gadgets.transparent IN f.state THEN INCL(F.state, Gadgets.transparent)
					ELSE EXCL(F.state, Gadgets.transparent)
					END
				END
			END;
			Display.Broadcast(A)
		END;
		RETURN TRUE
	END
END SetLinkObject;

PROCEDURE IconizerAttr(F: Iconizer; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("Icons.NewIconizer", M.s); M.res := 0
		ELSIF M.name = "Popup" THEN M.class := Objects.Bool; M.b := F.popup; M.res := 0
		ELSIF M.name = "Menu" THEN M.class := Objects.Bool; M.b := F.sel; M.res := 0
		ELSIF M.name = "FixedViews" THEN M.class := Objects.Bool; M.b := ~F.pos; M.res := 0
		ELSIF M.name = "Pin" THEN M.class := Objects.Bool; M.b := F.pin; M.res := 0
		ELSIF M.name = "Locked" THEN M.class := Objects.Bool; M.b := Gadgets.lockedcontents IN F.state; M.res := 0
		ELSIF M.name = "LineupHY" THEN M.class := Objects.Int;
			(* ps -28.6.96 *)
			IF ~F.closed & (F.closedF # NIL) THEN M.i := F.H - ((F.closedF.H + 1) DIV 2) -5
			ELSE M.i := F.H DIV 2 - 5
			END;
			M.res := 0;
		ELSE  Gadgets.framehandle(F, M);
		END;
	ELSIF M.id = Objects.set THEN
		IF M.name = "Popup" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN F.popup := TRUE; ELSE F.popup := FALSE END;
				M.res := 0;
			END;
		ELSIF M.name = "Menu" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN F.sel := TRUE; F.popup := TRUE ELSE F.sel := FALSE END;
				M.res := 0;
			END
		ELSIF M.name = "FixedViews" THEN
			IF M.class = Objects.Bool THEN
				IF ~M.b THEN
					IF ~F.pos THEN F.oX := F.X; F.oY := F.Y + F.H - 1; F.cX := F.oX; F.cY := F.oY END;
					F.pos := TRUE;
				ELSE F.pos := FALSE END;
				M.res := 0;
			END
		ELSIF M.name = "Pin" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN F.pin := TRUE;
				ELSE F.pin := FALSE END;
				M.res := 0; F.mask := NIL
			END
		ELSIF M.name = "Locked" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN F.state := F.state + {Gadgets.lockedcontents, Gadgets.lockedsize}
				ELSE F.state := F.state - {Gadgets.lockedcontents, Gadgets.lockedsize}
				END;
				M.res := 0
			END
		ELSE Gadgets.framehandle(F, M);
		END;
	ELSIF M.id = Objects.enum THEN
		M.Enum("Popup"); M.Enum("Menu"); M.Enum("FixedViews"); M.Enum("Pin"); M.Enum("Locked");
		 Gadgets.framehandle(F, M);
	END;
END IconizerAttr;

PROCEDURE IconizerLink(F: Iconizer; VAR M: Objects.LinkMsg); (* ps - 8.5.96 *)
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Closed" THEN M.obj:= F.closedF; M.res:= 0
		ELSIF M.name = "Open" THEN M.obj:= F.openF; M.res:= 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Closed" THEN
			IF M.obj = F.closedF THEN M.res:= 0
			ELSE
				IF M.obj = NIL THEN
					F.closedF:= NIL; IF F.closed THEN F.obj:= NIL END;
					M.res:= 0
				ELSIF M.obj IS Display.Frame THEN
					IF SetLinkObject(F, M.obj(Display.Frame), TRUE) THEN M.res:= 0 END
				END
			END
		ELSIF M.name = "Open" THEN
			IF M.obj = F.openF THEN M.res:= 0
			ELSE
				IF M.obj = NIL THEN
					F.openF:= NIL; IF ~F.closed THEN F.obj:= NIL END;
					M.res:= 0
				ELSIF M.obj IS Display.Frame THEN
					IF SetLinkObject(F, M.obj(Display.Frame), FALSE) THEN M.res:= 0 END
				END
			END
		ELSIF M.name = "Model" THEN
			IF M.obj = F.obj THEN M.res:= 0
			ELSE
				IF M.obj = NIL THEN
					F.obj:= NIL; IF F.closed THEN F.closedF:= NIL ELSE F.openF:= NIL END;
					M.res:= 0
				ELSIF M.obj IS Display.Frame THEN
					IF SetLinkObject(F, M.obj(Display.Frame), F.closed) THEN M.res:= 0 END
				END
			END
		ELSE Links.HandleLinkMsg(F.link, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Closed"); M.Enum("Open");
		Links.HandleLinkMsg(F.link, M)
	END
END IconizerLink;

PROCEDURE LocateIconizer(F: Iconizer; VAR M: Display.LocateMsg);
VAR d: Display.Frame;
BEGIN
	IF F.closed THEN d := F.closedF; ELSE d := F.openF; END;
	IF d = NIL THEN
		IF Effects.Inside(M.X, M.Y, M.x + F.X, M.y + F.Y, F.W, F.H) THEN
			M.loc := F; M.res := 0; M.u := M.X - (M.x + F.X); M.v := M.Y - (M.y + F.Y);
		END;
	ELSIF Effects.Inside(M.X, M.Y, M.x + F.X + offset, M.y + F.Y + F.H - pinsize - offset, pinsize, pinsize) THEN
		M.loc := F; M.res := 0; M.u := M.X - (M.x + F.X); M.v := M.Y - (M.y + F.Y)
	ELSE
		To(F, M.x + F.X, M.y + F.Y + F.H - 1, M);
	END;
END LocateIconizer;

PROCEDURE AdjustIconizer(F: Iconizer; VAR M: Display.ModifyMsg);
VAR d: Display.Frame; A: Display.ModifyMsg;
BEGIN
	IF F.closed THEN d := F.closedF; ELSE d := F.openF; END;
	IF d # NIL THEN
		A.X := 0; A.Y := -M.H+1; A.W := M.W; A.H := M.H; A.mode := Display.state; A.id := Display.extend;
		A.dX := A.X - d.X; A.dY := A.Y - d.Y; A.dW := A.W - d.W; A.dH := A.H - d.H;
		A.F := d; A.res := -1; A.dlink := M.dlink; Objects.Stamp(A);
		To(F, M.x + F.X, M.y + F.Y + F.H - 1, A);
		IF d IS Gadgets.Frame THEN
			WITH d: Gadgets.Frame DO
				IF Gadgets.transparent IN d.state THEN INCL(F.state, Gadgets.transparent)
				ELSE EXCL(F.state, Gadgets.transparent)
				END;
				IF Gadgets.lockedsize IN d.state THEN INCL(F.state, Gadgets.lockedsize)
				ELSIF ~(Gadgets.lockedcontents IN F.state) THEN EXCL(F.state, Gadgets.lockedsize)
				END;
			END;
		END
	END;
	IF F.pos THEN
		IF F.closedF = NIL THEN F.cX := M.X; F.cY := M.Y + M.H - 1 END;
		IF F.openF = NIL THEN F.oX := M.X; F.oY := M.Y + M.H - 1 END;
	END;
	(*	Explode(M.x+F.X, M.y+F.Y, F.W, F.H, M.x+M.X, M.y+M.Y, M.W, M.H); *)
	(* KillMasks(F); *)
	
	Gadgets.Adjust(F, M);
END AdjustIconizer;

PROCEDURE AdjustIconizerChild(F: Iconizer; VAR M: Display.ModifyMsg);
VAR A: Display.ModifyMsg; d: Display.Frame;
BEGIN
	M.res := 0;
	A.F := F; A.id := Display.extend; A.mode := M.mode;
	A.X := F.X; A.Y := F.Y + F.H - M.H; A.W := M.W; A.H := M.H;
	A.dX := 0; A.dY := A.Y - F.Y; A.dW := A.W - F.W; A.dH := A.H - F.H;
	IF F.closed THEN d := F.closedF; ELSE d := F.openF; END;
	IF d IS Gadgets.Frame THEN
		WITH d: Gadgets.Frame DO
			IF Gadgets.transparent IN d.state THEN INCL(F.state, Gadgets.transparent)
			ELSE EXCL(F.state, Gadgets.transparent)
			END;
			IF Gadgets.lockedsize IN d.state THEN INCL(F.state, Gadgets.lockedsize)
			ELSIF ~(Gadgets.lockedcontents IN F.state) THEN EXCL(F.state, Gadgets.lockedsize)
			END;
		END
	END;
	Display.Broadcast(A)
END AdjustIconizerChild;

PROCEDURE ConsumeIconizer(F: Iconizer; VAR M: Display.ConsumeMsg);
VAR d: Display.Frame;
BEGIN
	IF F.closed THEN d := F.closedF; ELSE d := F.openF; END;
	IF (d = NIL) & (M.F = F) THEN
		IF SetLinkObject(F, M.obj(Display.Frame), F.closed) THEN M.res:= 0 END
	ELSE
		To(F, M.x + F.X, M.y + F.Y + F.H - 1, M);
	END;
END ConsumeIconizer;

PROCEDURE TrackPopup(F: Iconizer; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
VAR px, py: INTEGER; D: Display.DisplayMsg; block: Views.Block;
	L: Display.LocateMsg; ls: Display.Frame; A: Objects.AttrMsg;
	of: Gadgets.Frame; keysum, fstate: SET;
	R, R0: Display3.Mask; CM: Display.ControlMsg;
	mdlink, fdlink: Objects.Object;

	PROCEDURE Select(f: Display.Frame; state: BOOLEAN);
	VAR D: Display.DisplayMsg;
	BEGIN
		Oberon.FadeCursor(Oberon.Mouse);
		IF state THEN
			Display3.Rect(R0, Display.FG, Display.grey1, px + f.X, py + of.H - 1 + f.Y, f.W, f.H, 2, Display3.textmode);
		ELSE
			D.device := Display.screen; D.id := Display.area; D.F := of; D.u := f.X; D.v := f.Y; D.w := f.W; D.h := f.H;
			D.res := -1; D.x := px- of.X; D.y := py - of.Y; Objects.Stamp(D); D.dlink := M.dlink;
			of.handle(of, D)
		END
	END Select;
	
	PROCEDURE DoSelect(f: Display.Frame);
	BEGIN
		IF ls # NIL THEN Select(ls, FALSE); END;
		IF f # NIL THEN Select(f, TRUE); END;
		ls := f;
	END DoSelect;
	
	PROCEDURE CalcPlace(VAR px, py: INTEGER);
	VAR cx, cy, cw, ch: INTEGER; (* clipping area *) f: Objects.Object;
	BEGIN
		cx := 0; cy := 0; cw := Display.Width + Display.ColLeft; ch := Display.Height;
		f := M.dlink;
		WHILE (f # NIL) DO
			IF f IS Gadgets.View THEN
				WITH f: Gadgets.View DO
					ClipAgainst(cx, cy, cw, ch, f.absX, f.absY, f.W, f.H);
				END
			END;
			f := f.dlink
		END;
		px := x; py := y + h - of.H;
		IF px < cx THEN px := cx; END;
		IF px + of.W >= cx + cw THEN px := cx + cw - 1 - of.W; END;
		IF py < cy THEN py := cy; END;
		IF py + of.H >= cy + ch THEN py := cy + ch - 1 - of.H END;
	END CalcPlace;
	
BEGIN
	IF F.openF # NIL THEN
		(*
		To(F,  x, y + h - 1, M);
		IF M.res >= 0 THEN RETURN END;
		*)
		Oberon.RemoveMarks(x, y, w, h);
		of := F.openF(Gadgets.Frame);
		CalcPlace(px, py);
		Views.GetBlock(px, py, of.W, of.H, M.dlink, block);
		(* Effects.OpenMenu(px, py, of.W, of.H);	(* ps - 15.07.96 *) *)

		CM.id := Display.restore; CM.F := NIL; CM.x := 0; CM.y := 0; CM.res := -1; CM.dlink := NIL;
		of.handle(of, CM);
		
		F.poping := TRUE; F.px := px - (x + of.X); F.py := py - (y + h  - 1 + of.Y);
		of.mask := NIL;
		D.device := Display.screen; D.id := Display.full; D.F := of; D.res := -1;
		D.x := px - of.X; D.y := py - of.Y; D.dlink := M.dlink;
		of.handle(of, D);
		Gadgets.MakeMask(of, px, py, M.dlink, R); Display3.Copy(R, R0);
		Input.Mouse(M.keys, M.X, M.Y); keysum := M.keys; ls := NIL;
		fstate := F.state; INCL(F.state, Gadgets.lockedcontents); mdlink := M.dlink; M.dlink := F; (* jm *)
		fdlink := F.dlink; F.dlink := mdlink; (* ps *)
		WHILE (M.keys # {}) & (M.res < 0) DO
			IF F.sel THEN
				IF Effects.Inside(M.X, M.Y, px, py, of.W, of.H) THEN
					L.F := NIL; L.loc := NIL; L.X := M.X; L.Y := M.Y; L.x := px - F.closedF.X; L.y := py - of.Y; L.res := -1;
					Objects.Stamp(L); L.dlink := NIL;
					of.handle(of, L);
					IF (L.loc # NIL) & (L.loc # of) & (L.loc # ls) & HasCmdAttr(L.loc, "Cmd") THEN
						DoSelect(L.loc)
					ELSIF L.loc # ls THEN DoSelect(NIL)
					END
				ELSE
					DoSelect(NIL)
				END;
			ELSE
				M.x := px - of.X; M.y := py - of.Y; of.handle(of, M)
			END;
			Input.Mouse(M.keys, M.X, M.Y); keysum := keysum + M.keys;
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y)
		END;
		IF ls # NIL THEN Select(ls, FALSE) END;
		F.state := fstate; M.dlink := mdlink; F.dlink := fdlink; (* jm / ps *)

		Oberon.FadeCursor(Oberon.Mouse);
		F.poping := FALSE; of.mask := NIL; 
		Views.RestoreBlock(block);

		(* Effects.CloseMenu; *)
		IF (ls # NIL) & (keysum = {1}) THEN 
			A.id := Objects.get; A.name := "Cmd"; A.res := -1; A.class := Objects.Inval; ls.handle(ls, A);
			IF (A.res >= 0) & (A.class = Objects.String) THEN
				Gadgets.Execute(A.s, ls, M.dlink, NIL, NIL)
			END
		END;
		M.res := 0
	ELSE
		Gadgets.framehandle(F, M)
	END
END TrackPopup;

PROCEDURE PrintIconizer(F: Iconizer; VAR M: Display.DisplayMsg);
VAR R: Display3.Mask; d: Display.Frame; PM: Display.DisplayMsg; Fdlink, Mdlink: Objects.Object; x, y, w, h, a, b: INTEGER;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	x := M.x; y := M.y; w := P(F.W); h := P(F.H);
	
	IF F.closed THEN d := F.closedF ELSE d := F.openF END;
	IF d = NIL THEN
		Printer3.FilledRect3D(R, Display3.FG, Display3.FG, Display3.textbackC, x, y, w, h, 1, Display.replace);
		IF F.closed THEN
			Printer3.CenterString(R, Display3.textC, x, y, w, h, Fonts.Default, "Closed", Display3.textmode);
		ELSE
			Printer3.CenterString(R, Display3.textC, x, y, w, h, Fonts.Default, "Open", Display3.textmode);
		END
	ELSE
		PM.device := Display.printer; PM.id := Display.full; PM.x := M.x; PM.y := M.y; PM.res := -1; PM.dlink := M.dlink;
		
		Fdlink := F.dlink; Mdlink := PM.dlink; F.dlink := PM.dlink; PM.dlink := F;
		d.handle(d, PM);
		PM.dlink := Mdlink; F.dlink := Fdlink
	END;
	IF F.pin THEN
		a := x + P(offset); b := y + h - P(pinsize + offset);
		Printer3.FilledRect3D(R, Display3.bottomC, Display3.topC, Display3.groupC, a, b,
			P(pinsize), P(pinsize), 2, Display.replace);
		IF ~F.closed THEN
			Printer3.Line(R, Display.FG, Display.solid, a+P(1), b+P(1), a + P(pinsize-2), b + P(pinsize-2), P(1), Display.replace);
			Printer3.Line(R, Display.FG, Display.solid, a+P(1), b+P(pinsize-2), a + P(pinsize-2), b+P(1), P(1), Display.replace)
		END;
	END
END PrintIconizer;

PROCEDURE RestoreIconizer(R: Display3.Mask; F: Iconizer; x, y, w, h: INTEGER; dlink: Objects.Object);
VAR d: Display.Frame; M: Display.DisplayMsg; a, b: INTEGER;
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	IF F.closed THEN d := F.closedF ELSE d := F.openF END;
	IF d = NIL THEN
		Display3.FilledRect3D(R, Display3.FG, Display3.FG, Display3.textbackC, x, y, w, h, 1, Display.replace);
		IF F.closed THEN
			Display3.CenterString(R, Display3.textC, x, y, w, h, Fonts.Default, "Closed", Display3.textmode)
		ELSE
			Display3.CenterString(R, Display3.textC, x, y, w, h, Fonts.Default, "Open", Display3.textmode)
		END
	ELSE
		M.device := Display.screen; M.id := Display.full; M.F := d; M.dlink := dlink; M.res := -1; Objects.Stamp(M);
		To(F, x, y + h - 1, M)
	END;
	IF F.pin THEN
		a := x + offset; b := y + h - pinsize - offset;
		Display3.FilledRect3D(R, Display3.bottomC, Display3.topC, Display3.groupC, a, b, pinsize, pinsize, 1, Display.replace);
		IF ~F.closed THEN
			Display3.Line(R, Display.FG, Display.solid, a+1, b+1, a + pinsize-2, b + pinsize-2, 1, Display.replace);
			Display3.Line(R, Display.FG, Display.solid, a+1, b+pinsize-2, a + pinsize-2, b+1, 1, Display.replace)
		END
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreIconizer;

PROCEDURE RestoreIconizerArea(R: Display3.Mask; F: Iconizer; x, y, w, h: INTEGER; VAR M: Display.DisplayMsg);
VAR d: Display.Frame; M0: Display.DisplayMsg; a, b: INTEGER;
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	IF F.closed THEN d := F.closedF ELSE d := F.openF END;
	IF d = NIL THEN
		Display3.FilledRect3D(R, Display3.FG, Display3.FG, Display3.textbackC, x, y, w, h, 1, Display.replace);
		IF F.closed THEN
			Display3.CenterString(R, Display3.textC, x, y, w, h, Fonts.Default, "Closed", Display3.textmode)
		ELSE
			Display3.CenterString(R, Display3.textC, x, y, w, h, Fonts.Default, "Open", Display3.textmode)
		END
	ELSE
		M0 := M; M0.F := d; Objects.Stamp(M0); To(F, x, y + h - 1, M0)
	END;
	IF F.pin THEN
		a := x + offset; b := y + h - pinsize - offset;
		Display3.FilledRect3D(R, Display3.bottomC, Display3.topC, Display3.groupC, a, b, pinsize, pinsize, 1, Display.replace);
		IF ~F.closed THEN
			Display3.Line(R, Display.FG, Display.solid, a+1, b+1, a + pinsize-2, b + pinsize-2, 1, Display.replace);
			Display3.Line(R, Display.FG, Display.solid, a+1, b+pinsize-2, a + pinsize-2, b+1, 1, Display.replace)
		END
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreIconizerArea;

PROCEDURE CopyIconizer*(VAR M: Objects.CopyMsg; from, to: Iconizer);
VAR C: Objects.CopyMsg; 
BEGIN
	Gadgets.CopyFrame(M, from, to); to.pos := from.pos; to.pin:=from.pin;
	to.closed := from.closed; to.popup := from.popup; to.sel := from.sel;
	C.id := Objects.deep; C.stamp := M.stamp; C.obj := NIL;
	IF from.openF # NIL THEN from.openF.handle(from.openF, C); to.openF := C.obj(Display.Frame)
	ELSE to.openF := NIL
	END;
	C.id := Objects.deep; C.stamp := M.stamp; C.obj := NIL;
	IF from.closedF # NIL THEN from.closedF.handle(from.closedF, C); to.closedF := C.obj(Display.Frame)
	ELSE to.closedF := NIL
	END;
	IF to.closed THEN to.obj := to.closedF ELSE to.obj := to.openF END
END CopyIconizer;

PROCEDURE StoreIconizer (F: Iconizer; VAR M: Objects.FileMsg);
BEGIN
	Files.WriteNum(M.R, 3);
	Gadgets.WriteRef(M.R, F.lib, F.closedF);
	Gadgets.WriteRef(M.R, F.lib, F.openF);
	IF F.closed THEN Files.WriteNum(M.R, 1) ELSE Files.WriteNum(M.R, 0) END;
	IF F.popup THEN Files.WriteNum(M.R, 1) ELSE Files.WriteNum(M.R, 0) END;
	IF F.sel THEN Files.WriteNum(M.R, 1) ELSE Files.WriteNum(M.R, 0) END;
	IF F.pin THEN Files.WriteNum(M.R, 1) ELSE Files.WriteNum(M.R, 0) END;
	Files.WriteBool(M.R, F.pos);
	Files.WriteInt(M.R, F.cX); Files.WriteInt(M.R, F.cY);
	Files.WriteInt(M.R, F.oX); Files.WriteInt(M.R, F.oY);
	Gadgets.framehandle(F, M)
END StoreIconizer;

PROCEDURE LoadIconizer (F: Iconizer; VAR M: Objects.FileMsg);
VAR ver, i: LONGINT; obj: Objects.Object;
BEGIN
	Files.ReadNum(M.R, ver);
	IF (ver = 2) OR (ver = 3) THEN
		Gadgets.ReadRef(M.R, F.lib, obj);
		IF (obj # NIL) & (obj IS Display.Frame) THEN F.closedF := obj(Display.Frame) END;
		Gadgets.ReadRef(M.R, F.lib, obj);
		IF (obj # NIL) & (obj IS Display.Frame)  THEN F.openF := obj(Display.Frame) END;
		Files.ReadNum(M.R, i); F.closed := (i = 1);
		Files.ReadNum(M.R, i); F.popup := (i = 1);
		Files.ReadNum(M.R, i); F.sel := (i = 1);
		IF ver = 3 THEN Files.ReadNum(M.R, i); F.pin := (i = 1) ELSE F.pin:=TRUE END;
		Files.ReadBool(M.R, F.pos);
		Files.ReadInt(M.R, F.cX); Files.ReadInt(M.R, F.cY);
		Files.ReadInt(M.R, F.oX); Files.ReadInt(M.R, F.oY);
		Gadgets.framehandle(F, M)
	ELSIF ver = 1 THEN (* oldversion *)
		Gadgets.ReadRef(M.R, F.lib, obj);
		IF (obj # NIL) & (obj IS Display.Frame) THEN F.closedF := obj(Display.Frame) END;
		Gadgets.ReadRef(M.R, F.lib, obj);
		IF (obj # NIL) & (obj IS Display.Frame)  THEN F.openF := obj(Display.Frame) END;
		Files.ReadNum(M.R, i); F.closed := (i = 1);
		Files.ReadNum(M.R, i); F.popup := (i = 1);
		Files.ReadNum(M.R, i); F.sel := (i = 1); F.pos := FALSE; F.pin:=TRUE;
		Gadgets.framehandle(F, M)
	ELSE
		HALT(42)
	END;
	IF F.closed & (F.closedF # NIL) THEN F.obj := F.closedF
	ELSIF F.openF # NIL THEN F.obj := F.openF
	END
END LoadIconizer;

PROCEDURE UpdateMask (F: Iconizer; x, y, w, h: INTEGER; VAR M: Display3.UpdateMaskMsg);
VAR O: Display3.OverlapMsg; U: Display3.UpdateMaskMsg;
BEGIN
	IF M.F = F THEN
	ELSIF (F.mask = NIL) & ((M.F = F.openF) OR (M.F = F.closedF)) THEN
		U.F := F; Display.Broadcast(U);
	ELSIF F.poping & ((M.F = F.openF) OR (M.F = F.closedF)) THEN
		NEW(O.M); Display3.Open(O.M); Display3.Add(O.M, 0, - M.F.H + 1, M.F.W, M.F.H);
		O.F := M.F; O.res := -1; O.x := 0; O.y := 0; O.dlink := NIL;
		M.F.handle(M.F, O);
		M.res := 0
	ELSIF (M.F = F.openF) & (F.mask # NIL) THEN
		Display3.Copy(F.mask, O.M); O.M.x := 0; O.M.y := 0;
		IF F.pin THEN Display3.Subtract(O.M, offset, -pinsize+1 - offset, pinsize, pinsize) END;
		O.F := F.openF; O.res := -1; O.x := 0; O.y := 0; O.dlink := NIL;
		F.openF.handle(F.openF, O);
		M.res := 0
	ELSIF (M.F = F.closedF) & (F.mask # NIL) THEN
		Display3.Copy(F.mask, O.M); O.M.x := 0; O.M.y := 0;
		IF F.pin THEN Display3.Subtract(O.M, offset, -pinsize+1 - offset, pinsize, pinsize) END;
		O.F := F.closedF; O.res := -1; O.x := 0; O.y := 0; O.dlink := NIL;
		F.closedF.handle(F.closedF, O);
		M.res := 0
	ELSE To(F, x, y + h - 1, M)
	END
END UpdateMask;

PROCEDURE TrackIconizer (F: Iconizer; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
VAR R: Display3.Mask; stack: StackDesc;
BEGIN
	IF (M.id = Oberon.track) & ~(Gadgets.selected IN F.state) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN
		IF (M.keys = {1}) & F.pin & Effects.Inside(M.X, M.Y, x + offset, y + h - pinsize - offset, pinsize, pinsize) THEN
			Gadgets.MakeMask(F, x, y, M.dlink, R);
			TrackHighlight(R, M.X, M.Y, x + offset + 1, y + h - pinsize - offset + 1, pinsize - 2, pinsize - 2, M.keys);
			IF Effects.Inside(M.X, M.Y, x + offset + 1, y + h - pinsize - offset + 1, pinsize - 2, pinsize - 2) &
				(M.keys = {1}) THEN
				Push(stack, F); Flip; Pop(stack)
			END;
			M.res := 0
		ELSIF F.popup & (M.keys = {1}) & F.closed & Gadgets.InActiveArea(F, M) THEN
			TrackPopup(F, x, y, w, h, M);
		ELSIF (F.obj # NIL) & Gadgets.InActiveArea(F, M) & ~(Gadgets.selected IN F.state) THEN
			Push(stack, F);  To(F, x, y + h - 1, M); Pop(stack)
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF (M.id = Oberon.track) THEN
		IF Gadgets.selected IN F.state THEN Gadgets.framehandle(F, M)
		ELSE
			Push(stack, F);  To(F, x, y + h - 1, M); Pop(stack);
			IF M.res < 0 THEN Gadgets.framehandle(F, M) END
		END
	ELSE
		Push(stack, F);  To(F, x, y + h - 1, M); Pop(stack);
		IF M.res < 0 THEN Gadgets.framehandle(F, M) END
	END
END TrackIconizer;

PROCEDURE IconizerHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h, u, v: INTEGER; d: Display.Frame; F0: Iconizer; R: Display3.Mask; 
	O: Display3.OverlapMsg; PM: Gadgets.PriorityMsg;
BEGIN
	WITH F: Iconizer DO
		IF M IS Objects.AttrMsg THEN IconizerAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN StoreIconizer(F, M)
				ELSIF M.id = Objects.load THEN LoadIconizer(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyIconizer(M, F, F0); M.obj := F0
				END
			END
		ELSIF M IS Objects.LinkMsg THEN IconizerLink(F, M(Objects.LinkMsg))
		ELSIF M IS Objects.BindMsg THEN
			Gadgets.framehandle(F, M);
			IF F.closedF # NIL THEN F.closedF.handle(F.closedF, M); END;
			IF F.openF # NIL THEN F.openF.handle(F.openF, M); END
		ELSIF M IS Objects.FindMsg THEN
			WITH M: Objects.FindMsg DO
				Gadgets.framehandle(F, M);
				IF M.obj = NIL THEN
					IF F.closedF # NIL THEN F.closedF.handle(F.closedF, M); END;
					IF F.openF # NIL THEN F.openF.handle(F.openF, M); END
				END
			END
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate actual coordinates *)
				u := M.x; v := M.y;  (* store volatile info *)
				IF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg  DO
						IF M.device = Display.screen THEN
							IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								RestoreIconizer(R, F, x, y, w, h, M.dlink)
							ELSIF (M.id = Display.area) & (M.F = F) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
								RestoreIconizerArea(R, F, x, y, w, h, M)
							ELSE
								IF F.closed THEN d := F.closedF ELSE d := F.openF END;
								IF (d # NIL) & (M.F = d) & (d IS Gadgets.Frame) & (Gadgets.transparent IN d(Gadgets.Frame).state) THEN
									INCL(F.state, Gadgets.transparent);
									Gadgets.Update(F)
								ELSE
									To(F, x, y + h - 1, M)
								END
							END
						ELSIF M.device = Display.printer THEN PrintIconizer(F, M)
						ELSE To(F, x, y + h - 1, M)
						END 
					END
				ELSIF M IS Display.LocateMsg THEN LocateIconizer(F, M(Display.LocateMsg))
				ELSIF M IS Display.ConsumeMsg THEN (* ps - 8.5.96 *)
					WITH M: Display.ConsumeMsg DO
						IF (M.id = Display.drop) & (M.F = F) THEN ConsumeIconizer(F, M);
						ELSE To(F, x, y + h - 1, M)
						END;
					END
				ELSIF M IS Display3.OverlapMsg THEN
					WITH M: Display3.OverlapMsg DO
						IF (M.F = NIL) OR (M.F = F) THEN
							F.mask := M.M;
							IF F.obj # NIL THEN
								O.F := F.obj(Gadgets.Frame); O.res := -1; O.x := 0; O.y := 0; O.dlink := NIL;
								IF F.mask = NIL THEN O.M := NIL; F.obj.handle(F.obj, O)
								ELSE
									Display3.Copy(M.M, O.M); O.M.x := 0; O.M.y := 0;
									IF F.pin THEN Display3.Subtract(O.M, offset, -pinsize+1 - offset, pinsize, pinsize) END;
									F.obj.handle(F.obj, O)
								END;
							END;
							M.res := 0
						END
					END
				ELSIF M IS Gadgets.UpdateMsg THEN
					To(F, x, y + h - 1, M);
					Gadgets.framehandle(F, M)
				ELSIF M IS Display3.UpdateMaskMsg THEN UpdateMask(F, x, y, w, h, M(Display3.UpdateMaskMsg))
				ELSIF M IS Display.SelectMsg THEN
					WITH M: Display.SelectMsg DO
						IF ((M.F = NIL) OR (M.F = F)) & ((M.id = Display.set) OR (M.id = Display.reset)) THEN
							 Gadgets.framehandle(F, M)
						ELSE
							To(F, x, y + h - 1, M)
						END;
					END;
				ELSIF M IS Oberon.InputMsg THEN
					WITH M: Oberon.InputMsg DO
						IF M.id = Oberon.track THEN TrackIconizer(F, x, y, w, h, M) 
						ELSE To(F, x, y + h - 1, M)
						END
					END
				ELSIF M IS Gadgets.PriorityMsg THEN
					WITH M: Gadgets.PriorityMsg DO
						IF M.F = F.obj THEN PM.id := M.id; PM.F := F; Display.Broadcast(PM)
						ELSE To(F, x, y + h - 1, M)
						END
					END
				ELSIF M IS Display.ModifyMsg THEN
					WITH M: Display.ModifyMsg DO
						IF M.F = F THEN AdjustIconizer(F, M)
						ELSIF (M.F = F.closedF) OR (M.F = F.openF) THEN AdjustIconizerChild(F, M)
						ELSE To(F, x, y + h - 1, M);
						END
					END
				ELSE To(F, x, y + h - 1, M)
				END;
				M.x := u; M.y := v; (* restore volatile info *)
			END
		ELSE
			IF F.closed THEN d := F.closedF ELSE d := F.openF END;
			IF d # NIL THEN d.handle(d, M) END
		END
	END
END IconizerHandler;

(** Initialize an iconizer from the frames open and close. *)
PROCEDURE MakeIconizer*(F: Iconizer; close, open: Display.Frame);
BEGIN
	F.closed := TRUE; F.poping := FALSE; F.obj := close; F.W := 40; F.H := 40;
	F.handle := IconizerHandler;
	F.closedF := close; F.openF := open; F.pin:=TRUE;
	IF close # NIL THEN
		F.W := close.W; F.H := close.H;
		close.X := 0; close.Y := -close.H+1;
	END;
	IF open # NIL THEN
		open.X := 0; open.Y := -open.H+1;
	END;
END MakeIconizer;

PROCEDURE NewIconizer*;
VAR F: Iconizer;
BEGIN
	NEW(F); F.closed := TRUE; F.pin := TRUE; F.W := 40; F.H := 40;
	F.handle := IconizerHandler; Objects.NewObj := F;
END NewIconizer;

(** Takes the selected iconizer/icon apart and insert the constituents at the caret. *)
PROCEDURE Break*;
VAR M: Display.SelectMsg; t: Display.Frame; I: Icon; F: Iconizer; X: INTEGER;
BEGIN
	M.F := NIL; M.id := Display.get; M.time := -1; M.obj := NIL; Display.Broadcast(M);
	IF (M.time > 0) & (M.obj # NIL) THEN
		IF M.obj IS Icon THEN
			I := M.obj(Icon);
			IF (I.obj # NIL) & (I.obj IS Display.Frame) THEN
				t := I.obj(Display.Frame); I.obj := NIL; Gadgets.Update(I); Gadgets.Integrate(t);
			END;
		ELSIF M.obj IS Iconizer THEN
			F := M.obj(Iconizer);
			t := NIL; X := 0;
			IF F.openF # NIL THEN
				F.openF.slink := t; t := F.openF; F.openF := NIL; t.X := X; t.Y := 0; INC(X, t.W+5);
			END;
			IF F.closedF # NIL THEN
				F.closedF.slink := t; t := F.closedF; F.closedF := NIL;  t.X := X; t.Y := 0;
			END;
			IF t # NIL THEN
				Gadgets.Integrate(t);
				Gadgets.Update(F);
			END;
			F.obj := NIL;
		END;
	END;
END Break;

(* ---------------------- Making an icon out of a document ------------- *)

(** Initialize a new icon for a document. Icon should be in "Library.ObjName" format. The Cmd attribute is initialized to "Desktops.OpenDoc '#Caption '". *)
PROCEDURE CreateIcon*(F: Icon; caption, icon: ARRAY OF CHAR);
VAR A: Objects.AttrMsg; obj: Objects.Object;
BEGIN
	obj := Gadgets.FindPublicObj(icon);
	IF obj # NIL THEN MakeIcon(F, caption, ViewOf(obj(Gadgets.Frame)));
	ELSE MakeIcon(F, caption, NIL);
	END; 
	A.id := Objects.set; A.name := "Cmd"; A.class := Objects.String;
	A.s := "Desktops.OpenDoc '#Caption '";
	A.res := -1;
	F.handle(F, A)
END CreateIcon;

(** Inserts an Icon for the marked document at the caret. *)
PROCEDURE InsertIcon*;
VAR F: Icon;
	A: Objects.AttrMsg; iconname: ARRAY 64 OF CHAR;
	D: Documents.Document;
BEGIN
	D := Documents.MarkedDoc();
	IF D # NIL THEN
		iconname := "Icons.Moon";
		A.id := Objects.get; A.name := "Icon"; A.class := Objects.Inval; A.s := ""; A.res := -1;
		D.handle(D, A);
		IF (A.res >= 0) & (A.class = Objects.String) THEN COPY(A.s, iconname) END;
		NEW(F); CreateIcon(F, D.name, iconname);
		Gadgets.Integrate(F)
	END
END InsertIcon;

BEGIN Texts.OpenWriter(W);
	top := NIL
END Icons.

System.Free Icons ~
Gadgets.Insert Icons.NewIcon ~
Gadgets.Insert Icons.NewTest ~
Gadgets.Insert Icons.NewTest0 ~
Gadgets.Insert Icons.NewIconizer ~
Icons.Break

(** Remarks:

1. Simple Camera-view
The simple camera view is often used for displaying the icon pictures in Icons.Lib. To create a simple camera-view from the icon picture called "Icons.Panel" (i.e. the object called Panel in public library Icons), the following is required:

	obj := Gadgets.FindPublicObj("Icons.Panel");
	Gadgets.Integrate(Icons.ViewOf(obj(Gadgets.Frame)));

The camera-view gadget can be provided with caption by combining it with an icon gadget:

	VAR F: Icons.Icon;
	
	obj := Gadgets.FindPublicObj("Icons.Panel");
	NEW(F);
	Icons.MakeIcon(F, "My caption", Icons.ViewOf(obj(Gadgets.Frame)));
	Gadgets.Integrate(F);

*)