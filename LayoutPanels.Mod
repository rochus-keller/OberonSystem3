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

MODULE LayoutPanels;	(** portable *)	(* ck 6.4.97 / ps 12.5.97 *)

IMPORT
	Files, Objects, Texts, Display, Display3, Effects, Gadgets, Oberon, Panels, PanelDocs, Documents, 
	LP0 := LayoutPanels0;
	
CONST
	oldGenerator = "Panels.NewPanel";
	newGenerator = "LayoutPanels.NewPanel";
	Version = 1;

TYPE
	Panel* = POINTER TO PanelDesc;
	PanelDesc* = RECORD (Panels.PanelDesc)
		layout*: Texts.Text;
		saveOld: BOOLEAN
	END;
	
VAR
	methods*: Panels.Methods;	(** Default method block. *)

PROCEDURE ^ BuildLayoutNewSize(F: Panel; w, h: INTEGER);
PROCEDURE ^ UpdateMasks*(F: Panels.Panel; partialupdate, buildback: BOOLEAN);
PROCEDURE ^ UpdateLayout(F: Panel);

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

(* --- load and store procedures --- *)
PROCEDURE StoreText (T: Texts.Text; VAR R: Files.Rider);
	VAR len: LONGINT;
BEGIN
	Texts.Store(T, Files.Base(R), Files.Pos(R), len);
	Files.Set(R, Files.Base(R), Files.Pos(R) + len)	
END StoreText;

PROCEDURE LoadText (T: Texts.Text; VAR R: Files.Rider);
	VAR len: LONGINT; ch: CHAR;
BEGIN
	Files.Read(R, ch);				
	Texts.Load(T, Files.Base(R), Files.Pos(R), len);
	Files.Set(R, Files.Base(R), Files.Pos(R) + len)
END LoadText;

(** Default store mechanism. *)
PROCEDURE StorePanel*(F: Panel; VAR M: Objects.FileMsg);
VAR obj: Objects.Object;
BEGIN
	IF ~F.saveOld THEN
		Files.WriteNum(M.R, Version);
		IF F.obj # NIL THEN LP0.Produce(F.obj(LP0.Element), F.layout) END;
		StoreText(F.layout, M.R)
	END;
	obj := F.obj; F.obj := NIL;	(* do not save any layout structure [it's saved in a text] *)
	Panels.StorePanel(F, M);
	F.obj := obj	(* restore layout structure *)
END StorePanel;

(** Default load mechanism. *)
PROCEDURE LoadPanel*(F: Panel; VAR M: Objects.FileMsg);
VAR ver: LONGINT; e: LP0.Element;
BEGIN
	Files.ReadNum(M.R, ver);
	IF (ver = 1) THEN LoadText(F.layout, M.R)
	ELSE HALT(99)
	END;
	Panels.LoadPanel(F, M);
	LP0.Parse(F.layout, e, F.lib); F.obj := e;
	BuildLayoutNewSize(F, F.W, F.H)
END LoadPanel;

(** Default copy behavior. *)
PROCEDURE CopyPanel*(VAR M: Objects.CopyMsg; from, to: Panel);
BEGIN
	Panels.CopyPanel(M, from, to);
	to.layout := from.layout	(* should copy text here *)
END CopyPanel;

PROCEDURE PanelAttr(F: Panel; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN
			M.class := Objects.String;
			IF F.saveOld THEN COPY(oldGenerator, M.s) ELSE COPY(newGenerator, M.s) END;
			M.res := 0
		ELSIF M.name = "SaveOld" THEN M.class := Objects.Bool; M.b := F.saveOld; M.res := 0
		ELSE Panels.PanelHandler(F, M)
		END;
	ELSIF M.id = Objects.set THEN
		IF M.name = "SaveOld" THEN
			IF M.class = Objects.Bool THEN F.saveOld := M.b END;
			M.res := 0
		ELSE Panels.PanelHandler(F, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("SaveOld"); Panels.PanelHandler(F, M)
	END;
END PanelAttr;

PROCEDURE PanelLink(F: Panel; VAR M: Objects.LinkMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Layout" THEN M.obj := F.layout; M.res := 0
		ELSE Panels.PanelHandler(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Layout" THEN
			IF M.obj IS Texts.Text THEN F.layout := M.obj(Texts.Text); M.res := 0 END
		ELSE Panels.PanelHandler(F, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Layout"); Panels.PanelHandler(F, M)
	END
END PanelLink;

PROCEDURE Adjust(F: Panel; x, y: INTEGER; VAR M: Display.ModifyMsg);	(* ps - 23.5.96 *)
VAR f: Display.Frame; A: Display.ModifyMsg;
BEGIN
	IF (M.dH # 0) & (M.Y + M.H # F.Y + F.H) OR (M.dW # 0) & (M.X # F.X) THEN
		A.id := Display.move; A.mode := Display.state; Objects.Stamp(A);
		A.dX := F.X - M.X; A.dY := F.Y + F.H - (M.Y + M.H); A.dW := 0; A.dH:= 0;
		f:= F.dsc;
		WHILE f # NIL DO
			A.X := f.X + A.dX; A.Y := f.Y + A.dY; A.W := f.W; A.H := f.H; A.F := f; A.res := -1;
			Panels.ToChild(F, f, x, y, A); f := f.next
		END
	END;
	IF (M.dW # 0) OR (M.dH # 0) THEN BuildLayoutNewSize(F, M.W, M.H) END;
	Gadgets.Adjust(F, M);
	UpdateMasks(F, FALSE, TRUE)
END Adjust;

(** Default method implementation. x, y is the panel coordinates. u, v, w, h the relative coordinates of the area to be restored. *)
PROCEDURE RestoreArea*(F: Panels.Panel; x, y, u, v, w, h: INTEGER; M: Display3.Mask; dlink: Objects.Object);
VAR D: Display.DisplayMsg; B: Display3.Mask; f: Display.Frame; X, Y, W, H: INTEGER; e: LP0.Element;
BEGIN
	Oberon.RemoveMarks(x + u, y + F.H - 1 + v, w, h);
	
	X := M.X; Y := M.Y; W := M.W; H := M.H;
	
	IF M # F.mask THEN
		F.back.x := x; F.back.y := y + F.H - 1;
		Display3.IntersectMasks(M, F.back, B);
		F.back.x := 0; F.back.y := 0; B.x:= 0; B.y := 0;
	ELSE B := F.back; B.x:= 0; B.y := 0;
	END;
	Display3.AdjustMask(M, x + u, y + F.H - 1 + v, w, h);
	B.X := M.X; B.Y := M.Y; B.W := M.W; B.H := M.H;
	B.x := x; B.y := y + F.H - 1;
	F.do.RestoreBackGround(F, x, y, B); (* restore visible background *)

	IF ~(Panels.frozen IN F.state0) THEN e := F.obj(LP0.Element);
		IF Effects.Intersect(u, v, w, h, e.X, e.Y, e.W, e.H) THEN
			D.u := e.X; D.v := e.Y; D.w := e.W; D.h := e.H; ClipAgainst(D.u, D.v, D.w, D.h, u, v, w, h);
			D.u := D.u - e.X; D.v := D.v - (e.Y + e.H - 1); D.dlink := dlink;
			D.device := Display.screen; D.id := Display.area; D.F := NIL; D.res := -1; Panels.ToChild(F, e, x, y, D);
		END
	ELSE
		f := F.dsc;
		WHILE f # NIL DO
			IF Effects.Intersect(u, v, w, h, f.X, f.Y, f.W, f.H) THEN (* should clip against here *)
				D.u := f.X; D.v := f.Y; D.w := f.W; D.h := f.H; ClipAgainst(D.u, D.v, D.w, D.h, u, v, w, h);
				D.u := D.u - f.X; D.v := D.v - (f.Y + f.H - 1); D.dlink := dlink;
				D.device := Display.screen; D.id := Display.area; D.F := f; D.res := -1; Panels.ToChild(F, f, x, y, D)
			END;
			f := f.next
		END
	END;
	
	IF F.focused THEN Gadgets.MakeMask(F, x, y, dlink, M); F.do.RestoreCaret(F, x, y, M) END;
	IF Gadgets.selected IN F.state THEN 
		Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, F.W, F.H, Display.paint)
	END;
	
	M.X := X; M.Y := Y; M.W := W; M.H := H
END RestoreArea;

(* f is Element *)
PROCEDURE BuildElementMasks (F: Panels.Panel; f: Display.Frame; partialupdate, allTransp: BOOLEAN);
VAR o: Display.Frame; O: Display3.OverlapMsg; R: Display3.Mask;
BEGIN
	IF ~partialupdate OR ((f IS Gadgets.Frame) & (f(Gadgets.Frame).mask = NIL)) THEN
		Display3.Copy(F.mask, R);
		Display3.Intersect(R, F.borderW, -F.H + F.borderW + 1, F.W - F.borderW * 2, F.H - F.borderW * 2); 
		Display3.Intersect(R, f.X, f.Y, f.W, f.H);
		IF ~allTransp THEN
			o := f.next;
			WHILE o # NIL DO (* loop through higher priority children *)
				IF Effects.Intersect(f.X, f.Y, f.W, f.H, o.X, o.Y, o.W, o.H) & (o IS Gadgets.Frame) & 
					~(Gadgets.transparent IN o(Gadgets.Frame).state) THEN
					Display3.Subtract(R, o.X, o.Y, o.W, o.H)
				END;
				o := o.next;
			END
		END;
		R.x := -f.X; R.y := -(f.Y+f.H-1); Display3.Shift(R); 
		f(Gadgets.Frame).mask := R
	END;
	
	IF f IS LP0.Container THEN 
		o := f.dsc;
		WHILE o # NIL DO BuildElementMasks(F, o, partialupdate, allTransp); o := o.next END
	ELSE	(* f IS only a ordinary Element *)
		IF f(Gadgets.Frame).obj # NIL THEN
			o := f(Gadgets.Frame).obj(Display.Frame);
			IF ~partialupdate OR ((o IS Gadgets.Frame) & (o(Gadgets.Frame).mask = NIL)) THEN
				O.x := 0; O.y := 0; O.M := R; O.F := o; O.res := -1; O.dlink := NIL; O.x := 0; O.y := 0;
				o.handle(o, O)
			END
		END
	END
END BuildElementMasks;

(** Recalculate and update all invalid (NIL) masks of children. partialupdate modifies the existing backgound 
mask to reflect the current situation. buildback recreates the whole background mask from scratch. Both options 
are normally used mutual exclusive. Partial update is faster if few masks were invalidated, otherwise use buildback.  
Partial update requires the use of InvalidateMasks to keep the background mask valid. When in doubt simply use buildback. *)
PROCEDURE UpdateMasks*(F: Panels.Panel; partialupdate, buildback: BOOLEAN);
VAR f, o: Display.Frame; O: Display3.OverlapMsg; allTransp: BOOLEAN; R: Display3.Mask;
	fx, fy, fw, fh: INTEGER;
BEGIN
	IF F.mask = NIL THEN (* clear everything *)
		F.back := NIL;
		f := F.dsc; O.M := NIL; O.F := NIL; O.x := 0; O.y := 0; O.res := -1; Objects.Stamp(O);
		WHILE f # NIL DO O.res := -1; f.handle(f, O); f := f.next END
	ELSE
		f := F.dsc; allTransp := TRUE; (*  KR *)
		WHILE (f # NIL) & allTransp DO 
			allTransp := allTransp & (f IS Gadgets.Frame) & (Gadgets.transparent IN f(Gadgets.Frame).state);
			f := f.next
		END;
		
		F.mask.x := 0; F.mask.y := 0;
		
		(* build background *)
		IF buildback THEN
			Display3.Copy(F.mask, F.back); (* original background, relative*)
			IF ~allTransp THEN
				f := F.dsc;
				WHILE f # NIL DO
					IF (f IS Gadgets.Frame) & ~(Gadgets.transparent IN f(Gadgets.Frame).state) THEN
						fx := f.X; fy := f.Y; fw := f.W; fh := f.H;
						ClipAgainst(fx, fy, fw, fh, F.borderW, -F.H + F.borderW + 1, F.W - F.borderW * 2, F.H - F.borderW * 2);
						Display3.Subtract(F.back, fx, fy, fw, fh)
					END;
					f := f.next
				END
			END
		END;

		IF ~(Panels.frozen IN F.state0) THEN	(* data structure exists -> build masks for all LP0.Element *)
			BuildElementMasks(F, F.obj(LP0.Element), partialupdate, allTransp)
		ELSE
			(* build masks for children *)
			f := F.dsc;
			WHILE f # NIL DO
				IF ~partialupdate OR ((f IS Gadgets.Frame) & (f(Gadgets.Frame).mask = NIL)) THEN
					Display3.Copy(F.mask, R);
					Display3.Intersect(R, F.borderW, -F.H + F.borderW + 1, F.W - F.borderW * 2, F.H - F.borderW * 2); 
					Display3.Intersect(R, f.X, f.Y, f.W, f.H);
					IF ~allTransp THEN
						o := f.next;
						WHILE o # NIL DO (* loop through higher priority children *)
							IF Effects.Intersect(f.X, f.Y, f.W, f.H, o.X, o.Y, o.W, o.H) & (o IS Gadgets.Frame) & 
								~(Gadgets.transparent IN o(Gadgets.Frame).state) THEN
								Display3.Subtract(R, o.X, o.Y, o.W, o.H)
							END;
							o := o.next;
						END
					END;
					R.x := -f.X; R.y := -(f.Y+f.H-1); Display3.Shift(R); 
					O.x := 0; O.y := 0; O.M := R; O.F := f; O.res := -1; O.dlink := NIL; O.x := 0; O.y := 0; f.handle(f, O);
				END;
				f := f.next
			END
		END
	END
END UpdateMasks;

PROCEDURE ResetElements* (F: Panel);

	PROCEDURE Recursive (F: Panel; e: LP0.Element);
		VAR f: Display.Frame; M: Display.SelectMsg;
	BEGIN
		IF Gadgets.selected IN e.state THEN
			Panels.GrowHull(F, e.Y, e.Y, e.W, e.H);
			M.F := e; M.dlink := F; M.res := -1; M.id := Display.reset; Objects.Stamp(M); e.handle(e, M)
		END;
		IF (e.obj # NIL) & (e.obj IS Gadgets.Frame) & (Gadgets.selected IN e.obj(Gadgets.Frame).state) THEN
			Panels.GrowHull(F, e.X, e.Y, e.W, e.H);
			M.F := e.obj(Display.Frame); M.dlink := F; M.res := -1; M.id := Display.reset; Objects.Stamp(M);
			e.obj.handle(e.obj, M)
		END;
		IF e IS LP0.Container THEN
			f := e.dsc;
			WHILE f # NIL DO Recursive(F, f(LP0.Element)); f := f.next END
		END
	END Recursive;

BEGIN Panels.ResetHull(F); Recursive(F, F.obj(LP0.Element)); Panels.DrawHull(F)
END ResetElements;

(** Method implementations. *)
PROCEDURE TrackMouse*(F: Panels.Panel; VAR M: Oberon.InputMsg);
VAR T: Display.Frame; x, y, t, u, v: INTEGER; Fdlink, Mdlink: Objects.Object; c: LP0.Container;
	X, Y, W, H, MX, MY: INTEGER; A: Objects.AttrMsg;
BEGIN
	x := M.x + F.X; y := M.y + F.Y; t := y + F.H - 1; u := M.X - x; v := M.Y - t;
	T := LP0.Select(F.obj(LP0.Element), u, v, FALSE);
	IF T # NIL THEN
		IF T IS LP0.Element THEN
			WITH T: LP0.Element DO
				IF ~(Panels.frozen IN F.state0) THEN
					IF 1 IN M.keys THEN
						c := LP0.GetContainer(T);
						IF (c # NIL) & ~(c IS LP0.Table) THEN	(* in Place Container *)
							IF Effects.InCorner(u, v, T.X, T.Y, T.W, T.H) THEN	(* corner *)
								X := x + T.X; Y := t + T.Y; W := T.W; H := T.H;
								Effects.SizeRect(NIL, M.keys, MX, MY, X, Y, W, H, NIL);
								T.minx := X - x - c.X; T.miny := Y - y - (c.Y + F.H - 1);
								IF (T.obj # NIL) & (T.obj IS Gadgets.Frame) THEN
									A.id := Objects.set; A.name := "minw"; A.res := -1; A.class := Objects.Int; A.i := W;
									T.obj.handle(T.obj, A);
									A.id := Objects.set; A.name := "minh"; A.res := -1; A.class := Objects.Int; A.i := H;
									T.obj.handle(T.obj, A)
								END;
								UpdateLayout(F(Panel)); M.res := 0
							ELSIF Effects.InBorder(u, v, T.X, T.Y, T.W, T.H) THEN	(* border *)
								X := x + T.X; Y := t + T.Y; W := T.W; H := T.H;
								Effects.MoveRect(NIL, M.keys, MX, MY, X, Y, W, H);
								T.minx := X - x - c.X; T.miny := Y - y - (c.Y + F.H - 1);
								UpdateLayout(F(Panel)); M.res := 0
							ELSE Panels.ToChild(F, T, x, y, M)
							END
						ELSE Panels.ToChild(F, T, x, y, M)
						END
					ELSIF 0 IN M.keys THEN					
					ELSE Panels.ToChild(F, T, x, y, M)
					END
				ELSE Panels.ToChild(F, T, x, y, M)
				END
			END
		ELSE Panels.ToChild(F, T, x, y, M)
		END
	END;
	
	IF M.res < 0 THEN
		Effects.SetSnap(x, t, F.grid, F.grid);
		IF 2 IN M.keys THEN (* left *)
			IF ~(Panels.noinsert IN F.state0) THEN F.do.TrackCaret(F, M) END	(* sets also Focus => don't remove it! *)
		ELSIF 1 IN M.keys THEN (* middle *)
			IF (T # NIL) & (Gadgets.selected IN T(Gadgets.Frame).state) THEN
				WITH T: Gadgets.Frame DO
					IF Effects.InCorner(M.X, M.Y, x + T.X, t + T.Y, T.W, T.H) & ~(Gadgets.lockedsize IN T.state) THEN
						u := M.x; v := M.y; M.x := x; M.y := t; 
						Fdlink := F.dlink; Mdlink := M.dlink; F.dlink := M.dlink; M.dlink := F;
						Gadgets.SizeFrame(T, M);
						F.dlink := Fdlink; M.dlink := Mdlink;
						M.x := u; M.y := v; M.res := 0
					ELSE F.do.DragSelection(F, M)
					END
				END
			END
		ELSIF 0 IN M.keys THEN (* right *)
			IF ~(Panels.noselect IN F.state0) THEN
				T := LP0.Select(F.obj(LP0.Element), u, v, TRUE);
				IF T = NIL THEN F.do.TrackSelection(F, M)
				ELSE F.do.TrackSelectChild(F, M, T(Gadgets.Frame))
				END
			END
		END;
		Effects.SetSnap(0, 0, 1, 1)
	END
END TrackMouse;

PROCEDURE BuildLayoutNewSize(F: Panel; w, h: INTEGER);
	VAR diff: INTEGER; e: LP0.Element;
BEGIN
	e := F.obj(LP0.Element);
	e.size(e);
	diff := (h - 2*F.borderW) - F.obj(LP0.Element).minh;
	IF diff < 0 THEN e.make(e, F.borderW, diff + F.borderW + 1 - h , w - 2*F.borderW, e.minh)
	ELSE e.make(e, F.borderW, F.borderW + 1 - h , w - 2*F.borderW, h - 2*F.borderW)
	END
END BuildLayoutNewSize;

PROCEDURE UpdateLayout(F: Panel);
BEGIN BuildLayoutNewSize(F, F.W, F.H); UpdateMasks(F, FALSE, TRUE); Gadgets.Update(F)
END UpdateLayout;

PROCEDURE ToElement(F: Panel; VAR M: Display.FrameMsg);
	VAR Mdlink, Fdlink: Objects.Object;
BEGIN
	Fdlink := F.dlink; Mdlink := M.dlink; 
	F.dlink := M.dlink; M.dlink := F; 
	F.obj.handle(F.obj, M);
	F.dlink := Fdlink; M.dlink := Mdlink
END ToElement;

(* F # NIL, c # NIL, e # NIL, new # NIL *)
PROCEDURE InsertInTable (F: Panel; c: LP0.Table; e: LP0.Element; new: Objects.Object);
VAR objlist: Display.Frame;
BEGIN
	IF e.obj = NIL THEN
		IF new IS LP0.Element THEN
			WITH new: LP0.Element DO
				objlist := LP0.LinkGadgets(new, NIL);
				IF objlist # NIL THEN F.do.InsertFrames(F, 0, 0, objlist) END;
				LP0.ReplaceElement(c, e, new, FALSE)
			END
		ELSIF new IS Gadgets.Frame THEN
			WITH new: Gadgets.Frame DO
				LP0.InsertGadget(e, new); F.do.InsertFrames(F, 0, 0, new)
			END
		END
	END
END InsertInTable;

(* F # NIL, c # NIL, new # NIL *)
PROCEDURE InsertInContainer (F: Panel; c: LP0.Container; new: Objects.Object; x, y: INTEGER);
	VAR objlist: Display.Frame; e: LP0.Element; slink: Objects.Object;
BEGIN
	IF new IS LP0.Element THEN
		WITH new: LP0.Element DO
			objlist := LP0.LinkGadgets(new, NIL);
			IF objlist # NIL THEN F.do.InsertFrames(F, 0, 0, objlist) END;
			new.minx := x - c.X; new.miny := y - c.Y;
			LP0.InsertPlaceElement(c, new)
		END
	ELSE
		WHILE new # NIL DO
			IF new IS Gadgets.Frame THEN
				WITH new: Gadgets.Frame DO
					slink := new.slink; new.slink := NIL;
					e := LP0.NewElement();
					e.minx := x - c.X + new.X; e.miny := y - c.Y + new.Y;
					F.do.InsertFrames(F, 0, 0, new);
					LP0.InsertGadget(e, new);
					LP0.InsertPlaceElement(c, e);
					new.slink := slink
				END
			END;
			new := new.slink
		END
	END
END InsertInContainer;

PROCEDURE ConsumeElement* (F: Panel; top: LP0.Element; new: Objects.Object; x, y: INTEGER);
	VAR c: LP0.Container; e: Display.Frame;
BEGIN
	e := LP0.Select(top, x, y, FALSE);
	IF e = NIL THEN (* insertion not possible *)
	ELSIF e IS LP0.Table THEN new.slink := NIL;
		c := e(LP0.Container); e := LP0.ClosestTableElement(c(LP0.Table), x, y);
		InsertInTable(F, c(LP0.Table), e(LP0.Element), new)
	ELSIF e IS LP0.Container THEN (* new.slink is still alive *)
		IF (new IS LP0.Table) OR ~(new IS LP0.Container) THEN 
			InsertInContainer(F, e(LP0.Container), new, x, y)
		END
	ELSIF e IS LP0.Element THEN
		c := LP0.GetContainer(e(LP0.Element));
		IF c = NIL THEN (* no container found *)
		ELSIF c IS LP0.Table THEN new.slink := NIL; InsertInTable(F, c(LP0.Table), e(LP0.Element), new)
		ELSIF c IS LP0.Container THEN InsertInContainer(F, c, new, x, y)	(* new.slink is still alive *)
		END
	END
END ConsumeElement;

PROCEDURE PanelHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
	VAR F2: Panel; u, v, x, y, w, h: INTEGER; R: Display3.Mask; t: Display.Frame; e: LP0.Element;
			U: Display3.UpdateMaskMsg;
BEGIN
	WITH F: Panel DO
		IF M IS LP0.CalcMsg THEN UpdateLayout(F)
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF M.res >= 0 THEN RETURN END;
				u := M.x; v := M.y; x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
				IF (M.F = NIL) OR (M.F = F) THEN (* for this panel or a broadcast *)
					IF M IS LP0.PanelMsg THEN ToElement(F, M)
					ELSIF M IS LP0.ContainerMsg THEN ToElement(F, M)
					ELSIF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg DO
							IF M.device = Display.screen THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								IF M.id = Display.area THEN
									F.do.RestoreArea(F, x, y, M.u, M.v, M.w, M.h, R, M.dlink)
								ELSE
									F.do.RestoreArea(F, x, y, 0, -h + 1, w, h, R, M.dlink)
								END
							ELSE Panels.PanelHandler(F, M)
							END
						END
					ELSIF M IS Display3.OverlapMsg THEN
						WITH M: Display3.OverlapMsg DO F.mask := M.M; UpdateMasks(F, FALSE, TRUE); M.res := 0 END
					ELSIF M IS Display3.UpdateMaskMsg THEN
						NEW(F.mask); Display3.Open(F.mask); Display3.Add(F.mask, 0, -F.H+1, F.W, F.H);
						F.mask.x := 0; F.mask.y := 0; UpdateMasks(F, FALSE, TRUE); M.res := 0;
					ELSIF M IS Display.SelectMsg THEN
						WITH M: Display.SelectMsg DO
							IF (M.id = Display.get) THEN
								IF (F.time > M.time) & (F.time # 0) THEN
									t := LP0.GetSelection(F.obj(LP0.Element));
									IF t # NIL THEN M.time := F.time; M.obj := t; M.sel := F END
								ELSE Panels.ToChildren(F, M)
								END
							ELSE Panels.PanelHandler(F, M)
							END
						END
					ELSIF M IS Display.ConsumeMsg THEN
						WITH M: Display.ConsumeMsg DO
							IF ~(Panels.noinsert IN F.state0) THEN
								IF M IS LP0.ConsumeMsg THEN
									WITH M: LP0.ConsumeMsg DO
										IF M.e # NIL THEN
											IF (M.id = Display.integrate) & F.focused THEN
												Oberon.Defocus; 
												ConsumeElement(F, F.obj(LP0.Element), M.e, F.focusx, F.focusy);
												UpdateLayout(F);
												M.res := 0
											ELSIF M.id = Display.drop THEN
												ConsumeElement(F, F.obj(LP0.Element), M.e, M.u, M.v);
												UpdateLayout(F); M.res := 0
											END
										END
									END
								ELSE (* ordinary Display.ConsumeMsg *)
									IF M.obj # NIL THEN
										IF (M.id = Display.integrate) & F.focused THEN
											Oberon.Defocus; 
											ConsumeElement(F, F.obj(LP0.Element), M.obj, F.focusx, F.focusy);
											UpdateLayout(F);
											M.res := 0
										ELSIF M.id = Display.drop THEN
											ConsumeElement(F, F.obj(LP0.Element), M.obj, M.u, M.v);
											UpdateLayout(F); M.res := 0
										END
									END
								END
							END;
							IF M.res < 0 THEN Panels.ToChildren(F, M) END
						END
					ELSIF M IS Display.ModifyMsg THEN Adjust(F, x, y, M(Display.ModifyMsg))
					ELSIF M IS Oberon.ControlMsg THEN
						WITH M: Oberon.ControlMsg DO
							IF M.id = Oberon.neutralize THEN
								IF ~(Panels.frozen IN F.state0) THEN ResetElements(F) END; F.time := 0;
								IF F.focused THEN F.focused := FALSE; F.do.UpdateCaret(F) END
							ELSIF M.id = Oberon.defocus THEN
								IF F.focused THEN F.focused := FALSE; F.do.UpdateCaret(F) END;
							END;
							Panels.ToChildren(F, M)
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN
								IF (M.keys # {}) & (M.keys # {2}) & Effects.InBorder(M.X, M.Y, x, y, w, h) THEN
									Gadgets.framehandle(F, M)
								ELSIF ~(Gadgets.selected IN F.state) THEN
									F.do.TrackMouse(F, M)
								END
							ELSIF (M.id = Oberon.consume) & F.focused THEN (* F.do.ConsumeChar(F, M) *) (* !!!!!! not supported*)
							ELSE Panels.ToChildren(F, M)
							END
						END
					ELSE Panels.PanelHandler(F, M)
					END
				ELSE (* ================= perhaps for a child *)
					IF Panels.IsChild(F, M.F) THEN
						IF M IS Display3.UpdateMaskMsg THEN
							IF F.mask = NIL THEN U.F := F; Display.Broadcast(U)
							ELSE UpdateMasks(F, TRUE, FALSE)
							END
						ELSIF M IS Display.ModifyMsg THEN
							IF ~(Panels.frozen IN F.state0) THEN Panels.PanelHandler(F, M); UpdateLayout(F) END
						ELSIF M IS Display.ControlMsg THEN
							WITH M: Display.ControlMsg DO
								Panels.ToChildren(F, M);
								IF M.id = Display.remove THEN
									e := LP0.GetElementOf(M.F, F.obj(LP0.Element));
									IF e # NIL THEN (* found *)
										F.do.RemoveFrames(F, M.F);
										e.obj := NIL;
										IF LP0.ClearElement(e, t) THEN UpdateLayout(F) END
									END;
									M.res := 0
								END
							END
						ELSE Panels.PanelHandler(F, M)
						END
					ELSE Panels.PanelHandler(F, M)
					END
				END;
				M.x := u; M.y := v;
			END	(* WITH Display.FrameMsg *)
		ELSIF M IS Objects.AttrMsg THEN PanelAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.LinkMsg THEN PanelLink(F, M(Objects.LinkMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.load THEN LoadPanel(F, M)
				ELSIF M.id = Objects.store THEN StorePanel(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F2); F.stamp := M.stamp; F.dlink := F2; CopyPanel(M, F, F2); M.obj := F2
				END
			END
		ELSE Panels.PanelHandler(F, M)
		END
	END
END PanelHandler;

PROCEDURE InitPanel*(P: Panel);
VAR e: LP0.Element;
BEGIN
	Panels.InitPanel(P);
	P.handle := PanelHandler; P.do := methods; P.saveOld := FALSE;
	NEW(P.layout); Texts.Open(P.layout, "");
	e := LP0.EmptyTable(1, 1);
	e(LP0.Table).hborder := 5; e(LP0.Table).vborder := 5; e.hfactor := 1; e.vfactor := 1;
	P.obj := e;
	UpdateLayout(P)
END InitPanel;

PROCEDURE NewPanel*;
VAR P: Panel; 
BEGIN NEW(P); InitPanel(P); Objects.NewObj := P
END NewPanel;

(* === Method implementations === *)

PROCEDURE TrackCaret*(F: Panels.Panel; VAR M: Oberon.InputMsg);
VAR x, y, w, h, LX, LY: INTEGER; keysum: SET;
	obj, newobj: Objects.Object; parent: Display.Frame; objtime, texttime, beg, end: LONGINT; text: Texts.Text;
	buf: Texts.Buffer; T0: Texts.Text;
BEGIN
	x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
	Oberon.Defocus;
	Effects.TrackCross(NIL, keysum, LX, LY, x, y, w, h);
	F.focused := TRUE; F.focusx := LX - x; F.focusy := LY - (y + h - 1);
	F.do.UpdateCaret(F);
	M.res := 0;
	
	IF keysum = {2, 1} THEN (* copy to caret *)
		texttime := 0;
		Panels.GetSelection(obj, parent, objtime); Oberon.GetSelection(text, beg, end, texttime);

		IF (obj # NIL) & (objtime > texttime) THEN (* use the object selection *)
			IF obj IS LP0.Element THEN
				newobj := LP0.CopyElements(obj(LP0.Element));
				IF newobj # NIL THEN LP0.Integrate(newobj) END
			ELSE
				Panels.CopyObjList(Objects.shallow, obj, newobj);
				IF newobj # NIL THEN LP0.Integrate(newobj) END
			END
		ELSIF (texttime > 0) & (texttime > objtime) THEN (* use the text selection *)
			NEW(buf); Texts.OpenBuf(buf);
			Texts.Save(text, beg, end, buf);
			NEW(T0); Texts.Open(T0, "");
			Texts.Insert(T0, 0, buf); Objects.NewObj := T0;
			Gadgets.Execute("TextFields.MakeCaption", NIL, M.dlink, NIL, NIL);
			IF Objects.NewObj # NIL THEN Gadgets.Integrate(Objects.NewObj(Display.Frame)) END
		END
	END
END TrackCaret;

PROCEDURE TrackSelectChild*(F: Panels.Panel; VAR M: Oberon.InputMsg; child: Gadgets.Frame);
VAR x, y, sx, sy: INTEGER; S: Display.SelectMsg; keysum: SET; t, t1: Display.Frame; newobj: Objects.Object;
BEGIN
	x := M.x + F.X; y := M.y + F.Y;
	
	S.F := child; S.res := -1; (* S.dlink := NIL; *) S.dlink := M.dlink; Panels.ResetHull(F);
	IF Gadgets.selected IN child.state THEN S.id := Display.reset; Panels.ToChild(F, child, x, y, S);
		t := LP0.GetSelection(F.obj(LP0.Element));
		IF t = NIL THEN F.time := 0; END;
	ELSE S.id := Display.set; Panels.ToChild(F, child, x, y, S); F.time := Oberon.Time()
	END;
	Panels.GrowHull(F, child.X, child.Y, child.W, child.H); Panels.DrawHull(F);
	
	M.res := 0;
	keysum := {}; sx := M.X; sy := M.Y;
	REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys;
	UNTIL (M.keys = {}) OR ~Effects.Invicinity(M.X, M.Y, sx, sy);

	IF M.keys # {} THEN F.do.TrackSelection(F, M)
	ELSE
		IF keysum = {0, 2} THEN (* RL delete selection *)
			t := LP0.GetSelection(F.obj(LP0.Element));
			IF t # NIL THEN
				IF t IS LP0.Element THEN
					IF LP0.ClearElement(t(LP0.Element), t1) THEN
						F.do.RemoveFrames(F, t1);
						UpdateLayout(F(Panel))
					END
				ELSE Panels.KillChildren(F, t)
				END
			END
		ELSIF keysum = {0, 1} THEN  (* RM copy to focus *)
			t := LP0.GetSelection(F.obj(LP0.Element));
			IF t # NIL THEN
				newobj := LP0.CopyElements(t);
				LP0.Integrate(newobj);
				UpdateLayout(F(Panel))
			END
		END
	END
END TrackSelectChild;

PROCEDURE InsertFrames*(F: Panels.Panel; u, v: INTEGER; list: Objects.Object);
VAR x, y, w, h, count: INTEGER; f, n: Display.Frame; O: Display3.OverlapMsg; A: Display.ControlMsg;
BEGIN
	IF Panels.NewChildrenOK(F, list) & (list # NIL) THEN (* insert can proceed *)	
		Panels.BoundingBox(list(Gadgets.Frame), x, y, w, h, count);
		x := u - x; y := v - y;
		O.M := NIL; O.F := NIL; O.x := 0; O.y := 0; O.res := -1; Objects.Stamp(O);
		A.id := Display.remove; A.F := list(Gadgets.Frame); Display.Broadcast(A); (* <<< remove the whole list *)
		Panels.ResetHull(F);
		f := list(Gadgets.Frame);
		WHILE f # NIL DO
			IF f.slink # NIL THEN n := f.slink(Display.Frame) ELSE n := NIL END;
			F.do.InsertChild(F, f, f.X + x, f.Y + y);
			IF count < 10 THEN Panels.InvalidateMasks(F, f, f.X, f.Y, f.W, f.H) END;
			O.res := -1; f.handle(f, O);
			f := n;
		END;
		IF count < 10 THEN UpdateMasks(F, TRUE, FALSE) ELSE UpdateMasks(F, FALSE, TRUE) END;
		Panels.DrawHull(F)
	END
END InsertFrames;

PROCEDURE RemoveFrames*(F: Panels.Panel; list: Display.Frame);
VAR f: Display.Frame;
BEGIN
	Panels.ResetHull(F);
	f := list; 
	WHILE f # NIL DO
		F.do.RemoveChild(F, f);
		IF f.slink # NIL THEN f := f.slink(Display.Frame) ELSE f := NIL END;
	END;
	UpdateMasks(F, FALSE, TRUE); Panels.DrawHull(F)
END RemoveFrames;

PROCEDURE TranslateChildren*(F: Panels.Panel; list: Display.Frame; count, dx, dy: INTEGER);
VAR p: Display.Frame; A: Display.ModifyMsg; x0, y0: INTEGER;
BEGIN
	p := list;
	WHILE p # NIL DO
		A.id := Display.move; A.mode := Display.state; A.F := p;
		A.X := p.X + dx; A.Y := p.Y + dy; A.W := p.W; A.H := p.H;
		A.dX := A.X - p.X; A.dY := A.Y - p.Y; A.dW := 0; A.dH := 0;
		Panels.GrowHull(F, A.X, A.Y, A.W, A.H);
		x0 := p.X; y0 := p.Y; 
		Display.Broadcast(A);
		IF count < 10 THEN Panels.InvalidateMasks(F, p, x0, y0, p.W, p.H); Panels.InvalidateMasks(F, p, p.X, p.Y, p.W, p.H) END;
		IF p.slink # NIL THEN p := p.slink(Display.Frame) ELSE p := NIL; END;
	END;
	IF count < 10 THEN UpdateMasks(F, TRUE, FALSE) ELSE UpdateMasks(F, FALSE, TRUE) END;
	Panels.DrawHull(F)
END TranslateChildren;

PROCEDURE DragSelection*(F: Panels.Panel; VAR M: Oberon.InputMsg);
VAR u, v, X, Y, x, y, w, h, nx, ny, nw, nh, u0, v0, count: INTEGER; f, q: Display.Frame; keys: SET;
	C: LP0.ConsumeMsg(* Display.ConsumeMsg *); old: Objects.Handler; nl: Objects.Object; 
BEGIN
	f := LP0.GetSelection(F.obj(LP0.Element));
	IF f # NIL THEN
		Panels.BoundingBox(f, x, y, w, h, count);
		IF (w # 0) & (h # 0) THEN
			u := M.x; v := M.y; x := u + F.X + x; y := v + F.Y + F.H - 1 + y;
			Effects.TrackMouse(keys, X, Y, Effects.FlatHand);
			nx := x; ny := y; nw := w; nh := h;
			Effects.MoveRect(NIL, keys, X, Y, nx, ny, nw, nh);
			old := F.handle; F.handle := Panels.NewHandler;
			Gadgets.ThisFrame(X, Y, q, u0, v0);
			F.handle := old;
			IF q # NIL THEN
				IF keys = {1, 0} THEN (* copy frames *)
					nl := LP0.CopyElements(f);
					LP0.Drop(nl, q, nx - (M.x + F.X), ny - (M.y + F.Y + F.H - 1))
				ELSIF keys = {1, 2} THEN (* consume frames *)
					C.id := Display.drop; C.F := q; C.u := u0 + (nx - X); C.v := v0 + (ny - Y); C.obj := f;
					Display.Broadcast(C);
				ELSIF keys = {1} THEN
					(* move to own boundary *)
					Panels.ResetHull(F); Panels.GrowHull(F, x - (F.X + u), y - (v + F.Y + F.H - 1), w, h);
					TranslateChildren(F, f, count, nx - x, ny - y)
				END
			END
		END
	END
END DragSelection;

PROCEDURE ConsumeChar*(F: Panels.Panel; VAR M: Oberon.InputMsg);
	
	PROCEDURE Shift(dx, dy: INTEGER);
	VAR f: Display.Frame; x, y, w, h, count: INTEGER;
	BEGIN
		Panels.GetPanelSelection(F, f);
		IF f # NIL THEN
			Panels.BoundingBox(f, x, y, w, h, count);
			Panels.ResetHull(F); Panels.GrowHull(F, x, y, w, h);
			TranslateChildren(F, f, count, dx, dy);
		END
	END Shift;
	
BEGIN
	IF M.ch = 0C4X THEN (* left arrow *) Shift(-1, 0)
	ELSIF M.ch = 0C3X THEN (* right arrow *) Shift(1, 0)
	ELSIF M.ch = 0C1X THEN (* up arrow *) Shift(0, 1)
	ELSIF M.ch = 0C2X THEN (* down arrow *) Shift(0, -1)
	ELSE
		Objects.NewObj := NIL; Oberon.Defocus;
		Gadgets.Execute("TextFields.MakeCaption", F, M.dlink, NIL, NIL);
		IF Objects.NewObj # NIL THEN
			F.do.InsertFrames(F, F.focusx, F.focusy, Objects.NewObj);
			Objects.NewObj.handle(Objects.NewObj, M)			
		END
	END;
	M.res := 0	(* ps - 13.5.96 *)
END ConsumeChar;

(** Document for LayoutPanels *)
PROCEDURE DocHandle* (D: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	IF M IS Objects.AttrMsg THEN
		WITH M: Objects.AttrMsg DO
			IF M.id = Objects.get THEN
				IF M.name = "Gen" THEN M.class := Objects.String; M.s := "LayoutPanels.NewDoc"; M.res := 0
				ELSIF M.name = "MainGen" THEN M.class := Objects.String; M.s := "LayoutPanels.NewPanel"; M.res := 0
				ELSE PanelDocs.DocHandle(D, M)
				END
			ELSE PanelDocs.DocHandle(D, M)
			END
		END
	ELSE PanelDocs.DocHandle(D, M)
	END
END DocHandle;

PROCEDURE InitDoc*(D: Documents.Document; W, H: INTEGER);
VAR main: Panel;
BEGIN
	D.Store := PanelDocs.StorePanel; D.Load := PanelDocs.LoadPanel; D.handle := DocHandle; D.name := "";
	D.W := W; D.H := H;
	NEW(main); InitPanel(main);
	Documents.Init(D, main)
END InitDoc;

PROCEDURE NewDoc*;
VAR D: Documents.Document;
BEGIN
	NEW(D); InitDoc(D, 266, 200);
	Objects.NewObj := D
END NewDoc;

(* ------------ commands ------------  *)
	
(**
	AddCol "^" "left"|"right"|num
	AddCol "@" "left"|"right"
*)
PROCEDURE AddCol*;
VAR obj: Objects.Object; time: LONGINT; e: LP0.Element; tab: LP0.Table; pos: INTEGER; S: Texts.Scanner;
BEGIN
	Gadgets.GetSelection(obj, time);
	IF (time >= 0) & (obj # NIL) & (obj IS LP0.Element) THEN
		e := obj(LP0.Element);
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & ((S.c = "^") OR (S.c = "@")) THEN
			IF S.c = "@" THEN obj := LP0.GetContainer(e) END;
			IF (obj # NIL) & (obj IS LP0.Table) THEN
				tab := obj(LP0.Table); pos := -1; Texts.Scan(S);
				IF obj = e THEN
					IF S.class = Texts.Int THEN pos := SHORT(S.i)
					ELSIF S.class = Texts.Name THEN
						IF S.s = "right" THEN pos := tab.cols ELSIF S.s = "left" THEN pos := 0 END
					END
				ELSE
					IF S.class = Texts.Name THEN
						IF S.s = "right" THEN pos := e.col + 1 ELSIF S.s = "left" THEN pos := e.col END
					END
				END;
				IF pos >= 0 THEN LP0.InsertCol(tab, pos, TRUE) END
			END
		END
	END
END AddCol;
	
(**
	AddRow "^" "bottom"|"top"|num
	AddRow "@" "lower"|"upper"
*)
PROCEDURE AddRow*;
VAR obj: Objects.Object; time: LONGINT; e: LP0.Element; tab: LP0.Table; pos: INTEGER; S: Texts.Scanner;
BEGIN
	Gadgets.GetSelection(obj, time);
	IF (time >= 0) & (obj # NIL) & (obj IS LP0.Element) THEN
		e := obj(LP0.Element);
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & ((S.c = "^") OR (S.c = "@")) THEN
			IF S.c = "@" THEN obj := LP0.GetContainer(e) END;
			IF (obj # NIL) & (obj IS LP0.Table) THEN
				tab := obj(LP0.Table); pos := 0; Texts.Scan(S);
				IF obj = e THEN
					IF S.class = Texts.Int THEN pos := SHORT(S.i)
					ELSIF S.class = Texts.Name THEN
						IF S.s = "top" THEN pos := tab.rows ELSIF S.s = "bottom" THEN pos := 0 END
					END
				ELSE
					IF S.class = Texts.Name THEN
						IF S.s = "upper" THEN pos := e.row + 1 ELSIF S.s = "lower" THEN pos := e.row END
					END
				END;
				IF pos >= 0 THEN LP0.InsertRow(tab, pos, TRUE) END
			END
		END
	END
END AddRow;
	
(**
	DelCol "^" "left"|"right"|num 
	DelCol "@"
*)
PROCEDURE DelCol*;
VAR obj: Objects.Object; time: LONGINT; e: LP0.Element; tab: LP0.Table; pos: INTEGER; S: Texts.Scanner;
BEGIN
	Gadgets.GetSelection(obj, time);
	IF (time >= 0) & (obj # NIL) & (obj IS LP0.Element) THEN
		e := obj(LP0.Element);
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & ((S.c = "^") OR (S.c = "@")) THEN
			IF S.c = "@" THEN obj := LP0.GetContainer(e) END;
			IF (obj # NIL) & (obj IS LP0.Table) THEN
				tab := obj(LP0.Table); pos := -1;
				IF obj = e THEN
					Texts.Scan(S);
					IF S.class = Texts.Int THEN pos := SHORT(S.i)
					ELSIF S.class = Texts.Name THEN
						IF S.s = "right" THEN pos := tab.cols - 1 ELSIF S.s = "left" THEN pos := 0 END
					END
				ELSE
					pos := e.col
				END;
				IF pos >= 0 THEN LP0.RemoveCol(tab, pos, TRUE) END
			END
		END
	END
END DelCol;

(**
	DelRow "^" "top"|"bottom"|num 
	DelRow "@" 
*)
PROCEDURE DelRow*;
VAR obj: Objects.Object; time: LONGINT; e: LP0.Element; tab: LP0.Table; pos: INTEGER; S: Texts.Scanner;
BEGIN
	Gadgets.GetSelection(obj, time);
	IF (time >= 0) & (obj # NIL) & (obj IS LP0.Element) THEN
		e := obj(LP0.Element);
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & ((S.c = "^") OR (S.c = "@")) THEN
			IF S.c = "@" THEN obj := LP0.GetContainer(e) END;
			IF (obj # NIL) & (obj IS LP0.Table) THEN
				tab := obj(LP0.Table); pos := -1;
				IF obj = e THEN
					Texts.Scan(S);
					IF S.class = Texts.Int THEN pos := SHORT(S.i)
					ELSIF S.class = Texts.Name THEN
						IF S.s = "top" THEN pos := tab.rows - 1 ELSIF S.s = "bottom" THEN pos := 0 END
					END
				ELSE
					pos := e.row
				END;
				IF pos >= 0 THEN LP0.RemoveRow(tab, pos, TRUE) END
			END
		END
	END
END DelRow;

(** Inserts a Table Container at the current selection
	InsertTable ^ <rows> <cols>
*)
PROCEDURE InsertTable*;
VAR obj: Objects.Object; time: LONGINT; c: LP0.Container; cols, rows: INTEGER; S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "^") THEN
		Texts.Scan(S); IF (S.class = Texts.Int) & (S.i > 0) THEN rows := SHORT(S.i) ELSE rows := 2 END;
		Texts.Scan(S); IF (S.class = Texts.Int) & (S.i > 0) THEN cols := SHORT(S.i) ELSE cols := 2 END;
		
		Gadgets.GetSelection(obj, time);
		IF (time >= 0) & (obj # NIL) & (obj IS LP0.Element) THEN
			c := LP0.GetContainer(obj(LP0.Element));
			IF c # NIL THEN
				LP0.ReplaceElement(c, obj(LP0.Element), LP0.EmptyTable(rows, cols), TRUE)
			END
		END
	END
END InsertTable;

(** Inserts a Place Container at the current selection
	Syntax: InsertPlace ^
*)
PROCEDURE InsertPlace*;
VAR obj: Objects.Object; time: LONGINT; c: LP0.Container; new: LP0.Element; S: Texts.Scanner;
BEGIN		
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "^") THEN
		Gadgets.GetSelection(obj, time);
		IF (time >= 0) & (obj # NIL) & (obj IS LP0.Element) THEN
			c := LP0.GetContainer(obj(LP0.Element));
			IF c # NIL THEN
				new := LP0.NewContainer(); new.hfactor := 1; new.vfactor := 1;
				LP0.ReplaceElement(c, obj(LP0.Element), new, TRUE)
			END
		END
	END
END InsertPlace;

(**  Minimize "^" *)
PROCEDURE Minimize*;
VAR F: Objects.Object; time: LONGINT; e: LP0.Element; M: Display.ModifyMsg;
BEGIN
	Gadgets.GetSelection(F, time);
	IF (time >= 0) & (F # NIL) & (F IS Panel) THEN
		WITH F: Panel DO
			IF ~(Panels.frozen IN F.state0) THEN
				e := F.obj(LP0.Element); e.size(e);
				M.F := F; (* M.res := -1; Objects.Stamp(M); *)
				M.id := Display.extend; M.mode := Display.display;
				M.X := F.X; M.Y := F.Y + ((e.minh + 2*F.borderW) - F.H);
				M.W := e.minw + 2*F.borderW; M.H := e.minh + 2*F.borderW;
				M.dX := M.X - F.X; M.dY := M.Y - F.Y; M.dW := M.W - F.W; M.dH := M.H - F.H;
				Display.Broadcast(M)
			END
		END
	END
END Minimize;

BEGIN
	NEW(methods);
	methods.TrackMouse := TrackMouse;
	methods.RestoreBackGround := Panels.RestoreBackGround;
	methods.RestoreCaret := Panels.RestoreCaret;
	methods.RestoreArea := RestoreArea;
	methods.TrackCaret := TrackCaret;
	methods.TrackSelection := Panels.TrackSelection;
	methods.TrackSelectChild := TrackSelectChild;
	methods.ConsumeChar := ConsumeChar;
	methods.UpdateCaret := Panels.UpdateCaret;
	methods.InsertChild := Panels.InsertChild;
	methods.InsertFrames := InsertFrames;
	methods.AcceptChild := Panels.AcceptChild;
	methods.TranslateToGadget := Panels.TranslateToGadget;
	methods.RemoveChild := Panels.RemoveChild;
	methods.RemoveFrames := RemoveFrames;
	methods.DragSelection := DragSelection
END LayoutPanels.
