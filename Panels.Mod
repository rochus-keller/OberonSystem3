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

MODULE Panels;	(** portable *) (* jm 19.1.95 *)

(** Implementation of a panel container.
*)
(* some nice to haves:
	- control over the new focus point
	- TranslateToGadgets returns lists of gadgets
	- defocus panel when selecting it
	- remove children direct/indirect
	
	- caret disappears when transparent objects are involved
	- missing cursor when overlapped modify + adjust with transparent on top does not work

	14.12.94
		- improved consume
	30.1.95
		- fixed vanishing cursor when resizing transparent gadgets
	19.4.95 - Minor changes in the handling of the left mouse key
	25.4.95 - Changed ChangeBackdrop
	27.4.95 - Fixed resizing of selected lockedsize child
	7.6.95 - changed detection of putting a public object in a panel
	24.8.95 - forward SelectMsg to Children
	7.11.95 - fixed Align0 (thanks jt)
	16.11.95 - fixed insert in locked panel problem
	13.5.96 - fixed Picture link (when L.obj is nil) (ps - 13.5.96)
	13.5.96 - fixed shifting of components (ps - 13.5.96)
	23.5.96 - components stay relative to bottom when panel grows upwards (ps - 23.5.96)
*)

IMPORT 
	Objects, Display, Display3, Fonts, Gadgets, Effects, Oberon, Texts, Input, Files, Printer, Printer3, Attributes, Pictures, Modules;
	
CONST
	DefBorderWidth* = 2;	(** Default border clipping width. *)
	
	(** Panel State0 flags *)
	noselect* = 0;	(** Panel will not attempt to select children. *)
	noinsert* = 1;	(** Panel will refuse to accept additional children. *)
	frozen* = 3;	(** Panel is frozen. no further editing is allowed. *)
	flatlook* = 4;	(** Panel is drawn without its 3D look. *)
	texture* = 5;	(** Panel has a picture replicated as a textured background. *)
	
	outofboundsmodify = 3;
	
	markW = 5;

TYPE
	Panel* = POINTER TO PanelDesc;
	Methods* = POINTER TO MethodsDesc;
	
	PanelDesc* = RECORD (Gadgets.FrameDesc)
		focused*: BOOLEAN;	(** Has the caret ? *)
		focusx*, focusy*: INTEGER;	(** Relative coordinates of caret. *)
		time*: LONGINT;	(** Time of selection. *)
		back*: Display3.Mask;	(** Background mask of the panel, in relative coordinates. *)
		rx*, ry*, rr*, rt*: INTEGER;	(** Current hull to be redrawn (damage region). *)
		borderW*: INTEGER;	(** Size in pixels of the border area to which children are clipped. *)
		do*: Methods;	(** Method block. *)
		state0*: SET;
		grid*: INTEGER;	(** Grid snap size. *)
		col*: INTEGER;	(** Panel background color. *)
		pict*: Pictures.Picture;	(** Background picture, NIL if none is used. *)
	END;

	(** In the following methods x, y is the absolute position of the panel on the display. *)
	MethodsDesc* = RECORD
		(** Draw panel background. *)
		RestoreBackGround*: PROCEDURE (F: Panel; x, y: INTEGER; R: Display3.Mask);
		
		(** Directly draw caret shape. *)
		RestoreCaret*: PROCEDURE (F: Panel; x, y: INTEGER; R: Display3.Mask);
		
		(** Directly display an area of a panel. *)
		RestoreArea*: PROCEDURE (F: Panel; x, y, u, v, w, h: INTEGER; R: Display3.Mask; dlink: Objects.Object);
		
		(** Update the caret. Calls GrowHull followed by DrawHull for the caret area. *)
		UpdateCaret*: PROCEDURE (F: Panel);
		
		(** Default caret tracking. Calls Effects.TrackCross, UpdateCaret, CopyObjList, InsertFrames *)
		TrackCaret*: PROCEDURE (F: Panel; VAR M: Oberon.InputMsg);
		
		(** Default selection tracking. Calls Effects.SizeRect, GetPanelSelection, KillChildren,
		GetPanelSelection, CopyObjList, Gadgets.Integrate *)
		TrackSelection*: PROCEDURE (F: Panel; VAR M: Oberon.InputMsg);
		
		(** Selection tracking started directly on a child. Sends a Display.SelectMsg. Calls GetPanelSelection,
		ResetHull, GrowHull, Effects.TrackMouse, TrackSelection, GetPanelSelection, KillChildren, GetPanelSelection,
		CopyObjList, Gadgets.Integrate *) 
		TrackSelectChild*: PROCEDURE (F: Panel; VAR M: Oberon.InputMsg; child: Gadgets.Frame);
		
		(** Standard selection dragging. Calls GetPanelSelection, BoundingBox, Effects.MoveRect, Gadgets.ThisFrame,
		CopyObjList, ResetHull, GrowHull, TranslateChildren. Sends a ConsumeMsg. *)
		DragSelection*: PROCEDURE (F: Panel; VAR M: Oberon.InputMsg);
		
		(** Standard mouse tracking. Calls Effects.SetSnap, ToChild, TrackCaret, Gadgets.SizeFrame, DragSelection,
		TrackSelection, TrackSelectChild. *)
		TrackMouse*: PROCEDURE (F: Panel; VAR M: Oberon.InputMsg);
		
		(** Standard keyboard handling. Calls BoundingBox, ResetHull, GrowHull, TranslateChildren, InsertFrames. *)
		ConsumeChar*: PROCEDURE (F: Panel; VAR M: Oberon.InputMsg);
		
		(** Convert object into a frame for ConsumeMsg. *)
		TranslateToGadget*: PROCEDURE (F: Panel; VAR obj: Objects.Object);
		
		(** Does panel accept this child? *)
		AcceptChild*: PROCEDURE (F: Panel; VAR obj: Objects.Object): BOOLEAN;
		
		(** Insert child into panel. Calls GrowHull. Directly sends a Display.ModifyMsg. *)
		InsertChild*: PROCEDURE (F: Panel; f: Display.Frame; u, v: INTEGER);
		
		(** Insert several frames into the panel at u, v. Calls BoundingBox, ResetHull, InsertChild, InvalidateMasks,
		UpdateMasks, DrawHull. *)
		InsertFrames*: PROCEDURE (F: Panel; u, v: INTEGER; list: Objects.Object);
		
		(** Removes a child from a panel. Calls GrowHull. *)
		RemoveChild*: PROCEDURE (F: Panel; f: Display.Frame);
		
		(** Removes a list of children. Calls ResetHull, RemoveChild, UpdateMasks, DrawHull. *)
		RemoveFrames*: PROCEDURE (F: Panel; list: Display.Frame);
	END;

VAR
	methods*: Methods;	(** Default method block. *)
	defaultgrid*: INTEGER;	(** Default grid snap for new panels. *)
	newfocusX*, newfocusY*: INTEGER;	(** Set by InsertFrames to indicate the caret position after child consumption. *)
	recall*: Objects.Object;	(** Last deleted children *)
	
	W: Texts.Writer;
	
	(* for invalidating masks *)
	sx, sy, sw, sh: INTEGER; (* also for tracking the selection *)
	tmpR: Display3.Mask;

	(* for restoreRegion *)
	tmpP: Panel; px, py: INTEGER;
	tmpdlink: Objects.Object;
	tmpM: Display3.Mask;
	
PROCEDURE Min(x, y: INTEGER): INTEGER;
BEGIN IF x < y THEN RETURN x; ELSE RETURN y; END;
END Min;

PROCEDURE Max(x, y: INTEGER): INTEGER;
BEGIN IF x > y THEN RETURN x; ELSE RETURN y; END;
END Max;

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

(** Calculate the bounding box and count of a list of frames. *)
PROCEDURE BoundingBox*(list: Display.Frame; VAR x, y, w, h, count: INTEGER);
VAR f: Display.Frame; r, t: INTEGER;
BEGIN
	x := 32000; y := 32000; r := -32000; t := -32000;
	f := list;  count := 0;
	WHILE f # NIL DO
		x := Min(x, f.X); y := Min(y, f.Y); r := Max(r, f.X + f.W - 1); t := Max(t, f.Y + f.H - 1); w := r - x + 1; h := t - y + 1;
		INC(count);
		IF f.slink # NIL THEN f := f.slink(Display.Frame); ELSE f := NIL; END;
	END;
END BoundingBox;

(** Is f in the dsc-next list of F ? *)
PROCEDURE IsChild*(F: Display.Frame; f: Display.Frame): BOOLEAN;
BEGIN
	F := F.dsc;
	WHILE F # NIL DO
		IF F = f THEN RETURN TRUE END;
		F := F.next;
	END;
	RETURN FALSE;
END IsChild;

(** Forward a message M from F to child f. x, y is the display coordinates of F. *)
PROCEDURE ToChild*(F: Panel; f: Display.Frame; x, y: INTEGER; VAR M: Display.FrameMsg);
VAR u, v: INTEGER; Mdlink, Fdlink: Objects.Object;
BEGIN
	IF M.res < 0 THEN
		u := M.x; v := M.y; M.x := x; M.y := y + F.H - 1;
		Fdlink := F.dlink; Mdlink := M.dlink; 
		F.dlink := M.dlink; M.dlink := F; 
		f.handle(f, M);
		F.dlink := Fdlink; M.dlink := Mdlink; 
		M.x := u; M.y := v
	END
END ToChild;

(** Forward message to all children of F. *)
PROCEDURE ToChildren*(F: Panel; VAR M: Objects.ObjMsg);
VAR n, f: Display.Frame; u, v: INTEGER; Mdlink, Fdlink: Objects.Object;
BEGIN
	IF M IS Display.FrameMsg THEN
		WITH M: Display.FrameMsg DO
			IF M.res < 0 THEN
				Fdlink := F.dlink; Mdlink := M.dlink; F.dlink := M.dlink; M.dlink := F;
				u := M.x; v := M.y; M.x := M.x + F.X; M.y := M.y + F.Y + F.H - 1;
				f := F.dsc; 
				WHILE (f # NIL) & (M.res < 0) DO
					n := f.next; f.handle(f, M); f := n
				END;
				M.x := u; M.y := v; F.dlink := Fdlink; M.dlink := Mdlink
			END
		END
	ELSE
		f := F.dsc; 
		WHILE f # NIL DO n := f.next; f.handle(f, M); f := n END
	END
END ToChildren;

(** What child is located at absolute X, Y? x, y is the absolute position of F. *)
PROCEDURE ThisChild*(F: Panel; x, y, X, Y: INTEGER): Display.Frame;
VAR f, T: Display.Frame; childu, childv: INTEGER; M: Display.LocateMsg;
BEGIN
	childu := x; childv := y + F.H - 1;
	M.X := X; M.Y := Y;
	f := F.dsc; T := NIL;
	WHILE f # NIL DO
		x := childu + f.X; y := childv + f.Y;
		IF (X >= x) & (Y >= y) & (X < x + f.W) & (Y < y + f.H) THEN
			M.x := childu; M.y := childv; M.dlink := NIL; M.F := NIL; M.loc := NIL; M.res := -1;
			f.handle(f, M);
			IF M.loc # NIL THEN T := f END;
		END;
		f := f.next;
	END;
	RETURN T
END ThisChild;

(** Return all frames selected inside of F. Link is by slink field. *)
PROCEDURE GetPanelSelection*(F: Panel; VAR list: Display.Frame);
VAR t, last: Display.Frame;
BEGIN
	list := NIL; last := NIL; t := F.dsc;
	WHILE t # NIL DO
		IF (t IS Gadgets.Frame) & (Gadgets.selected IN t(Gadgets.Frame).state) THEN
			IF last = NIL THEN list := t
			ELSE last.slink := t
			END;
			last := t; t.slink := NIL;
		END;
		t := t.next
	END
END GetPanelSelection;

(** Default store mechanism. *)
PROCEDURE StorePanel*(F: Panel; VAR M: Objects.FileMsg);
VAR t: Display.Frame; u: INTEGER;
BEGIN
	Files.WriteNum(M.R, 7);
	Files.WriteSet(M.R, F.state0); Files.WriteNum(M.R, F.borderW); Files.WriteNum(M.R, F.grid);
	t := F.dsc; u := 0; WHILE t # NIL DO INC(u); t := t.next END; (* count the entries *)
	Files.WriteInt(M.R, u); (* write the count *)
	t := F.dsc; WHILE t # NIL DO Gadgets.WriteRef(M.R, F.lib, t); t := t.next END;
	Gadgets.WriteRef(M.R, F.lib, F.pict);
	Files.WriteInt(M.R, F.col);
	Gadgets.framehandle(F, M);
END StorePanel;

PROCEDURE Explain;
BEGIN
	IF (Modules.res # 0) & (Modules.resMsg # "") THEN
		Texts.WriteString(W, " (");  Texts.WriteString(W, Modules.resMsg);  Texts.Write(W, ")")
	END
END Explain;

(** Default load mechanism. *)
PROCEDURE LoadPanel*(F: Panel; VAR M: Objects.FileMsg);
VAR ver, x: LONGINT; u: INTEGER; t: Display.Frame; obj: Objects.Object;
BEGIN
	Files.ReadNum(M.R, ver);
	IF (ver = 5) OR (ver = 6) OR (ver = 7) THEN
		Files.ReadSet(M.R, F.state0);
		Files.ReadNum(M.R, x); F.borderW := SHORT(x); Files.ReadNum(M.R, x); F.grid := SHORT(x);
		Files.ReadInt(M.R, u); F.dsc := NIL; t := NIL;
		WHILE u > 0 DO
			Gadgets.ReadRef(M.R, F.lib, obj);
			IF obj # NIL THEN
				IF obj IS Display.Frame THEN
					obj(Display.Frame).next := NIL;
					IF t = NIL THEN F.dsc := obj(Display.Frame); t := F.dsc;
					ELSE t.next := obj(Display.Frame); t := t.next
					END
				ELSIF obj IS Objects.Dummy THEN (* Alien *)
					Texts.WriteString(W, "Discarding "); Texts.WriteString(W, obj(Objects.Dummy).GName);
					Explain;
					Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
				ELSE HALT(99)
				END
			END;
			DEC(u);
		END;
		IF ver >= 6 THEN
			Gadgets.ReadRef(M.R, F.lib, obj);
			IF obj # NIL THEN
				IF obj IS Pictures.Picture THEN F.pict := obj(Pictures.Picture)
				ELSIF obj IS Objects.Dummy THEN (* Alien *)
					Texts.WriteString(W, "Discarding picture");
					Explain;
					Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
				END
			END;
			IF ver = 7 THEN Files.ReadInt(M.R, F.col) END
		END;
		Gadgets.framehandle(F, M);
	ELSIF (ver = 3) OR (ver = 4) THEN
		Files.ReadSet(M.R, F.state0);
		IF ver > 3 THEN
			Files.ReadNum(M.R, x); F.borderW := SHORT(x); F.grid := defaultgrid
		END;
		Files.ReadInt(M.R, u); F.dsc := NIL; t := NIL;
		WHILE u > 0 DO
			Gadgets.ReadRef(M.R, F.lib, obj);
			IF obj # NIL THEN
				IF obj IS Display.Frame THEN
					obj(Display.Frame).next := NIL;
					IF t = NIL THEN F.dsc := obj(Display.Frame); t := F.dsc;
					ELSE t.next := obj(Display.Frame); t := t.next
					END
				ELSIF obj IS Objects.Dummy THEN (* Alien *)
					Texts.WriteString(W, "Discarding "); Texts.WriteString(W, obj(Objects.Dummy).GName);
					Explain;
					Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
				ELSE HALT(99)
				END
			END;
			DEC(u);
		END;
		Gadgets.framehandle(F, M);
	ELSE HALT(99)
	END;
	IF F.col < 0 THEN F.col := Display3.groupC END;
END LoadPanel;

(** Default copy behavior. *)
PROCEDURE CopyPanel*(VAR M: Objects.CopyMsg; from, to: Panel);
VAR t, t0: Display.Frame; C: Objects.CopyMsg;
BEGIN
	Gadgets.CopyFrame(M, from, to);
	
	t := from.dsc; to.dsc := NIL; C.stamp := M.stamp; C.id := M.id;
	IF t # NIL THEN t.handle(t, C); t0 := C.obj(Display.Frame); t:= t.next; to.dsc := t0 END;
	WHILE t # NIL DO
		t.handle(t, C); t0.next := C.obj(Display.Frame);
		t := t.next; t0 := t0.next
	END;
	
	to.focused := FALSE; to.time := 0; to.grid := from.grid;
	to.borderW := from.borderW; to.state0 := from.state0;
	to.do := from.do;
	IF (from.pict # NIL) & (M.id = Objects.deep) THEN
		C.stamp := M.stamp; C.id := M.id;
		from.pict.handle(from.pict, C);
		to.pict := C.obj(Pictures.Picture)
	ELSE
		to.pict := from.pict
	END;
	to.col := from.col
END CopyPanel;

PROCEDURE PanelAttr(F: Panel; VAR M: Objects.AttrMsg);
VAR f: Files.File;
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("Panels.NewPanel", M.s); M.res := 0
		ELSIF M.name = "LineupHY" THEN M.class := Objects.Int; M.i := F.H - Fonts.Default.height; M.res := 0
		ELSIF M.name = "Locked" THEN M.class := Objects.Bool; M.b := frozen IN F.state0; M.res := 0
		ELSIF M.name = "Color" THEN M.class := Objects.Int; M.i := F.col; M.res := 0
		ELSIF M.name = "Flat" THEN M.class := Objects.Bool; M.b := flatlook IN F.state0; M.res := 0
		ELSIF (M.name = "FocusX") & F.focused THEN  M.class := Objects.Int; M.i := F.focusx; M.res := 0
		ELSIF (M.name = "FocusY") & F.focused THEN  M.class := Objects.Int; M.i := F.focusy; M.res := 0
		ELSIF M.name = "Border" THEN  M.class := Objects.Int; M.i := F.borderW; F.mask := NIL; M.res := 0
		ELSIF M.name = "GridSnap" THEN  M.class := Objects.Int; M.i := F.grid; M.res := 0
		ELSIF M.name = "Texture" THEN M.class := Objects.Bool; M.b := texture IN F.state0; M.res := 0
		ELSE Gadgets.framehandle(F, M);
		END;
	ELSIF M.id = Objects.set THEN
		IF M.name = "Locked" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN F.state := F.state + {Gadgets.lockedcontents, Gadgets.lockedsize};
					F.state0 := F.state0 + {noselect, noinsert, frozen};
				ELSE F.state := F.state - { Gadgets.lockedcontents, Gadgets.lockedsize};
					F.state0 := F.state0 - {noselect, noinsert, frozen};
				END;
				M.res := 0
			END
		ELSIF M.name = "Color" THEN
			IF M.class = Objects.Int THEN F.col := SHORT(M.i); M.res := 0 END
		ELSIF M.name = "Flat" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN INCL(F.state0, flatlook)
				ELSE EXCL(F.state0, flatlook)
				END;
				M.res := 0;
			END
		ELSIF M.name = "Texture" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN INCL(F.state0, texture)
				ELSE EXCL(F.state0, texture)
				END;
				M.res := 0;
			END
		ELSIF M.name = "Border" THEN
			IF (M.class = Objects.Int) & (M.i >= 0) THEN F.borderW := SHORT(M.i); M.res := 0 END
		ELSIF M.name = "GridSnap" THEN
			IF (M.class = Objects.Int) & (M.i >= 1) THEN F.grid := SHORT(M.i); M.res := 0 END
		ELSIF (M.name = "Picture") THEN
			IF M.class = Objects.String THEN
				IF (M.s = "") THEN F.pict := NIL
				ELSE
					f := Files.Old(M.s);
					IF f # NIL THEN
						NEW(F.pict); Pictures.Open(F.pict, M.s, TRUE); (* IF M.res = -1 THEN Gadgets.Update(F); END; *)
					ELSE
						F.pict := NIL
					END
				END;
				M.res := 0;
			END
		ELSE Gadgets.framehandle(F, M);
		END;
	ELSIF M.id = Objects.enum THEN
		M.Enum("Color"); M.Enum("Border"); M.Enum("GridSnap"); M.Enum("Flat"); M.Enum("Texture"); M.Enum("Locked");
		Gadgets.framehandle(F, M);
	END;
END PanelAttr;

PROCEDURE Adjust(F: Panel; x, y: INTEGER; VAR M: Display.ModifyMsg);	(* ps - 23.5.96 *)
VAR f: Display.Frame; A: Display.ModifyMsg;
BEGIN
	IF (M.dH # 0) & (M.Y + M.H # F.Y + F.H) OR (M.dW # 0) & (M.X # F.X) THEN
		A.id := Display.move; A.mode := Display.state; Objects.Stamp(A);
		A.dX := F.X - M.X; A.dY := F.Y + F.H - (M.Y + M.H); A.dW := 0; A.dH:= 0;
		A.x := 0;  A.y := 0; f:= F.dsc;
		WHILE f # NIL DO
			A.X := f.X + A.dX; A.Y := f.Y + A.dY; A.W := f.W; A.H := f.H; A.F := f; A.res := -1;
			ToChild(F, f, x, y, A); f := f.next
		END
	END;
	Gadgets.Adjust(F, M)
END Adjust;

PROCEDURE FindObj(F: Panel; VAR M: Objects.FindMsg);
VAR name: ARRAY 64 OF CHAR; f: Display.Frame;
BEGIN
	Gadgets.framehandle(F, M);
	IF (M.name # "") & (M.obj = NIL) THEN
		(* first search own children *)
		f := F.dsc;
		WHILE (f # NIL) & (M.obj = NIL) DO
			Gadgets.GetObjName(f, name);
			IF name = M.name THEN M.obj := f END;
			f := f.next
		END;
		IF M.obj = NIL THEN (* to all children *)
			f := F.dsc;
			WHILE (f # NIL) & (M.obj = NIL) DO
				f.handle(f, M);
				f := f.next
			END
		END
	END
END FindObj;

(** Default method implementation. x, y is the panel coordinates. u, v, w, h the relative coordinates of the area to be restored. *)
PROCEDURE RestoreArea*(F: Panel; x, y, u, v, w, h: INTEGER; M: Display3.Mask; dlink: Objects.Object);
VAR D: Display.DisplayMsg; B: Display3.Mask; f: Display.Frame; X, Y, W, H: INTEGER;
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
	f := F.dsc;
	WHILE f # NIL DO
		IF Effects.Intersect(u, v, w, h, f.X, f.Y, f.W, f.H) THEN
			(* should clip against here *)
			D.u := f.X; D.v := f.Y; D.w := f.W; D.h := f.H; ClipAgainst(D.u, D.v, D.w, D.h, u, v, w, h);
			D.u := D.u - f.X; D.v := D.v - (f.Y + f.H - 1); D.dlink := dlink;
			D.x := 0;  D.y := 0;
			D.device := Display.screen; D.id := Display.area; D.F := f; D.res := -1; ToChild(F, f, x, y, D)
		END;
		f := f.next
	END;
	IF F.focused THEN Gadgets.MakeMask(F, x, y, dlink, M); F.do.RestoreCaret(F, x, y, M) END;
	IF Gadgets.selected IN F.state THEN Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, F.W, F.H, Display.paint); END;
	
	M.X := X; M.Y := Y; M.W := W; M.H := H;
END RestoreArea;

(** The hull contains the panel area to be updated in rel coordinates. *)
PROCEDURE ResetHull*(F: Panel);
BEGIN F.rx := 32000; F.ry := 32000; F.rr := -32000; F.rt := -32000;
END ResetHull;

PROCEDURE GetHull*(F: Panel; VAR u, v, w, h: INTEGER);
BEGIN
	IF (F.rr > F.rx) & (F.rt > F.ry) THEN u := F.rx; v := F.ry; w := F.rr - F.rx + 1; h := F.rt - F.ry + 1;
	ELSE u := 0; v := 0; w := 0; h := 0;
	END;
END GetHull;

(** Increase the size of the hull with the area u, v, w, h.. *)
PROCEDURE GrowHull*(F: Panel; u, v, w, h: INTEGER);
BEGIN
	F.rx := Min(F.rx, u); F.ry := Min(F.ry, v);
	F.rr := Max(F.rr, u + w - 1); F.rt := Max(F.rt, v + h - 1);
END GrowHull;

(** Draw the hull area. Hull is reset. *)
PROCEDURE DrawHull*(F: Panel);
VAR D: Display.DisplayMsg; x, y, w, h: INTEGER;
BEGIN
	GetHull(F, x, y, w, h);
	IF (w > 0) & (h > 0) THEN
		D.device := Display.screen; D.id := Display.area; D.F := F; D.u := x; D.v := y; D.w := w; D.h := h; ResetHull(F);
		Display.Broadcast(D)
	END
END DrawHull;

(** Recalculate and update all invalid (NIL) masks of children. partialupdate modifies the existing backgound mask to reflect the current situation. buildback recreates the whole background mask from scratch. Both options are normally used mutual exclusive. Partial update is faster if few masks were invalidated, otherwise use buildback.  Partial update requires the use of InvalidateMasks to keep the background mask valid. When in doubt simply use buildback. *)
PROCEDURE UpdateMasks*(F: Panel; partialupdate, buildback: BOOLEAN);
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
						IF Effects.Intersect(f.X, f.Y, f.W, f.H, o.X, o.Y, o.W, o.H) & (o IS Gadgets.Frame) & ~(Gadgets.transparent IN o(Gadgets.Frame).state) THEN
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
END UpdateMasks;

PROCEDURE *Out0(x, y, w, h: INTEGER);
BEGIN
	ClipAgainst(x, y, w, h, sx, sy, sw, sh);
	IF (w > 0) & (h > 0) THEN Display3.Subtract(tmpR, x, y, w, h); END;
END Out0;

(** Invalidate all masks of the children in the specified rectangle except the exception. Background is updated so that the rectangle becomes part of the panel background. *)
PROCEDURE InvalidateMasks*(F: Panel; except: Display.Frame; x, y, w, h: INTEGER);
VAR f: Display.Frame; x0, y0, w0, h0: INTEGER; O: Display3.OverlapMsg;
BEGIN
	IF F.back # NIL THEN
		(* add background in *)
		F.back.x := 0; F.back.y := 0;
		ClipAgainst(x, y, w, h, 0, -F.H+1, F.W, F.H);
		Display3.Add(F.back, x, y, w, h);
	END;
	f := F.dsc; O.M := NIL; O.x := 0; O.F := NIL; O.y := 0; O.res := -1; Objects.Stamp(O);
	WHILE f # NIL DO
		IF Effects.Intersect(x, y, w, h, f.X, f.Y, f.W, f.H) & (f IS Gadgets.Frame) THEN
			IF ~(Gadgets.transparent IN f(Gadgets.Frame).state) & (F.back # NIL) THEN
				x0 := f.X; y0 := f.Y; w0 := f.W; h0 := f.H;
				ClipAgainst(x0, y0, w0, h0, F.borderW,  -F.H + F.borderW + 1, F.W - F.borderW * 2, F.H - F.borderW * 2);
				Display3.Subtract(F.back, x0, y0, w0, h0)
			END;
			IF (f # except) THEN O.F := f; f.handle(f, O); O.res := -1; END;
		END;
		f := f.next;
	END;
	(* cut out parts of the total mask *)
	IF (F.back # NIL) & (F.mask # NIL) THEN
		F.mask.x := 0; F.mask.y := 0; tmpR := F.back;
		sx := 0; sy := -F.H+1; sw := F.W; sh := F.H;
		Display3.EnumInvert(F.mask, Out0);
		tmpR := NIL;
	END;
END InvalidateMasks;

(** Set the selection state of children to Display.reset or Display.set. *)
PROCEDURE SetChildren*(F: Panel; x, y, state: INTEGER);
VAR M: Display.SelectMsg; f: Display.Frame;
BEGIN
	M.id := state;
	f := F.dsc; ResetHull(F);
	WHILE f # NIL DO
		IF ~(f IS Gadgets.Frame) THEN GrowHull(F, f.X, f.Y, f.W, f.H);
		ELSIF (state = Display.reset) & (Gadgets.selected IN f(Gadgets.Frame).state) THEN
			GrowHull(F, f.X, f.Y, f.W, f.H);
		ELSIF (state = Display.set) & ~(Gadgets.selected IN f(Gadgets.Frame).state) THEN
			GrowHull(F, f.X, f.Y, f.W, f.H);
		END;
		M.F := f; M.res := -1; M.dlink := NIL; Objects.Stamp(M);
		M.x := 0;  M.y := 0;  M.time := 0;
		ToChild(F, f, x, y, M);
		f := f.next;
	END;
	DrawHull(F);
END SetChildren;

(** Method implementations. *)
PROCEDURE TrackMouse*(F: Panel; VAR M: Oberon.InputMsg);
VAR T: Display.Frame; x, y, t, u, v: INTEGER; Fdlink, Mdlink: Objects.Object;
BEGIN
	x := M.x + F.X; y := M.y + F.Y; t := y + F.H - 1;
	T := ThisChild(F, x, y, M.X, M.Y);
	
	IF T # NIL THEN Effects.SetSnap(x, t, F.grid, F.grid); ToChild(F, T, x, y, M); Effects.SetSnap(0, 0, 1, 1) END;
	
	IF M.res < 0 THEN
		Effects.SetSnap(x, t, F.grid, F.grid);
		IF 2 IN M.keys THEN (* left *)
			IF ~(noinsert IN F.state0) THEN F.do.TrackCaret(F, M) END
		ELSIF 1 IN M.keys THEN (* middle *)
			IF (T # NIL) & (Gadgets.selected IN T(Gadgets.Frame).state) THEN
				WITH T: Gadgets.Frame DO
					IF Effects.InCorner(M.X, M.Y, x + T.X, t + T.Y, T.W, T.H) & ~(Gadgets.lockedsize IN T.state) (*!!!test here*) THEN
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
			IF ~(noselect IN F.state0) THEN
				IF T = NIL THEN F.do.TrackSelection(F, M)
				ELSE F.do.TrackSelectChild(F, M, T(Gadgets.Frame))
				END
			END
		END;
		Effects.SetSnap(0, 0, 1, 1)
	END
END TrackMouse;

(** Default handling of the LocateMsg. *)
PROCEDURE Locate*(F: Display.Frame; VAR M: Display.LocateMsg);
VAR f, T: Display.Frame; childu, childv, x, y, tx, ty, tu, tv, X, Y, u, v: INTEGER;
BEGIN
	u := M.x; v := M.y; childu := u + F.X; childv := v + F.Y + F.H - 1; X := M.X; Y := M.Y;
	f := F.dsc; T := NIL;
	WHILE f # NIL DO
		x := childu + f.X; y := childv + f.Y;
		IF (X >= x) & (Y >= y) & (X < x + f.W) & (Y < y + f.H) THEN
			M.x := childu; M.y := childv; M.F := NIL; M.loc := NIL; M.res := -1; M.dlink := NIL;
			f.handle(f, M);
			IF M.loc # NIL THEN T := M.loc; tx := M.x; ty := M.y; tu := M.u; tv := M.v; END;
		END;
		f := f.next;
	END;
	IF T = NIL THEN M.loc := F; M.x := u; M.y := v; M.u := M.X - childu; M.v := M.Y - childv;
	ELSE M.loc := T; M.x := tx; M.y := ty; M.u := tu; M.v := tv;
	END;
END Locate;

(* restore all the transparent objects above a certain rectangle *)
PROCEDURE RestoreAboveArea(F: Panel; above: Display.Frame; x, y, u, v, w, h: INTEGER; dlink: Objects.Object; M: Display3.Mask);
VAR D: Display.DisplayMsg; f: Display.Frame; 
BEGIN
	Oberon.RemoveMarks(x + u, y + F.H - 1 + v, w, h);
	f := F.dsc;
	WHILE (f # NIL) & (f # above) DO f := f.next END; IF f = above THEN f := f.next END;
	WHILE f # NIL DO
		IF Effects.Intersect(u, v, w, h, f.X, f.Y, f.W, f.H) & (f IS Gadgets.Frame) & (Gadgets.transparent IN f(Gadgets.Frame).state) THEN
			(* should clip against here *)
			D.u := f.X; D.v := f.Y; D.w := f.W; D.h := f.H; ClipAgainst(D.u, D.v, D.w, D.h, u, v, w, h);
			D.u := D.u - f.X; D.v := D.v - (f.Y + f.H - 1); D.dlink := dlink;
			D.x := 0;  D.y := 0;
			D.device := Display.screen; D.id := Display.area; D.F := f; D.res := -1; ToChild(F, f, x, y, D)
		END;
		f := f.next
	END;
	IF F.focused THEN F.do.RestoreCaret(F, x, y, M) END;
	IF Gadgets.selected IN F.state THEN Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, F.W, F.H, Display.paint); END;
END RestoreAboveArea;

PROCEDURE *RestoreRegion0(x, y, w, h: INTEGER);
BEGIN
	tmpP.do.RestoreArea(tmpP, px, py, x, y, w, h, tmpM, tmpdlink);
END RestoreRegion0;

(** Redraw region M of panel. Mask M is in relative coordinates.*)
PROCEDURE RestoreRegion*(F: Panel; x, y: INTEGER; dlink: Objects.Object; M: Display3.Mask);
VAR P: Panel; tpx, tpy: INTEGER;
BEGIN
	Gadgets.MakeMask(F, x, y, dlink, tmpM);
	P := tmpP; tpx := px; tpy := py; (* save *)
	tmpP := F; px := x; py := y; tmpdlink := dlink;
	Display3.Enum(M, RestoreRegion0);
	tmpP := P; px := tpx; py := tpy; (* restore *)
	tmpM := NIL; tmpdlink := NIL; (* restore *)
END RestoreRegion;

PROCEDURE ^ PromoteChild*(F: Display.Frame; f: Display.Frame);

PROCEDURE HandleChildAdjust(F: Panel; VAR M: Display.ModifyMsg);
VAR u, v, x, y, ox, oy, ow, oh, oldmode: INTEGER; second: BOOLEAN; R: Display3.Mask;

	PROCEDURE Forward;
	VAR f, next: Display.Frame; p, q: INTEGER;
	BEGIN
		f := F.dsc; p := u + F.X; q := v + F.Y;
		WHILE f # NIL DO
			next := f.next;
			IF f # M.F THEN ToChild(F, f, p, q, M); END;
			f := next
		END;
	END Forward;
	
BEGIN
	u := M.x; v := M.y; x := u + F.X; y := v + F.Y;
	
	ox := M.X; oy := M.Y; ow := M.W; oh := M.H;
	ClipAgainst(ox, oy, ow, oh, 0, -F.H+1, F.W, F.H);
	IF ((ow <= 0) OR (oh <= 0)) & (M.id # outofboundsmodify) THEN M.res := 0; RETURN END; (* out of bounds *)
	ox := M.X - M.dX; oy := M.Y - M.dY; ow := M.W - M.dW; oh := M.H - M.dH; (* calculate old position *)
	
	IF 31 IN F.state0 THEN (* recursive adjust *)
		INCL(F.state0, 30); (* recursive adjust happened *)
		oldmode := M.mode;
		M.mode := Display.state;
		ToChild(F, M.F, x, y, M);
		InvalidateMasks(F, M.F, ox, oy, ow, oh); InvalidateMasks(F, M.F, M.X, M.Y, M.W, M.H);
		M.mode := oldmode;
		GrowHull(F, ox, oy, ow, oh); GrowHull(F, M.X, M.Y, M.W, M.H);
		Forward;
	ELSE (* first adjust *)
		(* bring child to front *)
		PromoteChild(F, M.F);
		(* *)
		INCL(F.state0, 31); EXCL(F.state0, 30);
		second := M.stamp = F.stamp; F.stamp := M.stamp; (* check for second time around *)
		
		IF M.mode = Display.state THEN
			ToChild(F, M.F, x, y, M); GrowHull(F, ox, oy, ow, oh); GrowHull(F, M.X, M.Y, M.W, M.H);
			IF ~second THEN InvalidateMasks(F, M.F, ox, oy, ow, oh); InvalidateMasks(F, M.F, M.X, M.Y, M.W, M.H) END;
			
		ELSE (* M.mode = Display.display *)
			IF Effects.Intersect(ox, oy, ow, oh, M.X, M.Y, M.W, M.H) THEN
				IF (M.F IS Gadgets.Frame) & (Gadgets.transparent IN M.F(Gadgets.Frame).state) THEN (* transparent gadgets *)
					GrowHull(F, ox, oy, ow, oh); GrowHull(F, M.X, M.Y, M.W, M.H);
					M.mode := Display.state;
					ToChild(F, M.F, x, y, M);
					IF ~second THEN InvalidateMasks(F, M.F, ox, oy, ow, oh); InvalidateMasks(F, M.F, M.X, M.Y, M.W, M.H) END;
					M.mode := Display.display;
				ELSE
					ToChild(F, M.F, x, y, M);
					IF ~second THEN InvalidateMasks(F, M.F, ox, oy, ow, oh); InvalidateMasks(F, M.F, M.X, M.Y, M.W, M.H) END;
					Gadgets.MakeMask(F, x, y, M.dlink, R);
					RestoreAboveArea(F, M.F, x, y, M.X, M.Y, M.W, M.H, M.dlink, R);
					NEW(R); Display3.Open(R);
					Display3.Add(R, ox, oy, ow, oh);
					Display3.Subtract(R, M.X, M.Y, M.W, M.H);
					RestoreRegion(F, x, y, M.dlink, R);
				END
			ELSE
				ToChild(F, M.F, x, y, M);
				IF ~second THEN InvalidateMasks(F, M.F, ox, oy, ow, oh); InvalidateMasks(F, M.F, M.X, M.Y, M.W, M.H) END;
				Gadgets.MakeMask(F, x, y, M.dlink, R);
				RestoreAboveArea(F, M.F, x, y, M.X, M.Y, M.W, M.H, M.dlink, R);
				F.do.RestoreArea(F, x, y, ox, oy, ow, oh, R, M.dlink);
			END;
		END;
		
		Forward;
		
		IF M.mode = Display.display THEN
			GetHull(F, ox, oy, ow, oh);
			IF (ow > 0) & (oh > 0) THEN 
				IF 30 IN F.state0 THEN (* recursive happened *)
					EXCL(F.state0, 30); DrawHull(F);
				ELSE
					ResetHull(F);
					Gadgets.MakeMask(F, x, y, M.dlink, R);
					F.do.RestoreArea(F, x, y, ox, oy, ow, oh, R, M.dlink);
				END;
			END;
		END;
		EXCL(F.state0, 31);
	END;
END HandleChildAdjust;

(** Get the latest object selection. *)
PROCEDURE GetSelection*(VAR obj: Objects.Object; VAR parent: Display.Frame; VAR time: LONGINT);
VAR S: Display.SelectMsg;
BEGIN
	obj := NIL; parent := NIL;
	S.id := Display.get; S.time := 0; S.sel := NIL; S.obj := NIL; S.F := NIL; Display.Broadcast(S); (* object selection *)
	IF S.time > 0 THEN obj := S.obj; parent := S.sel; time := S.time ELSE time := -1 END	
END GetSelection;

PROCEDURE PrintPanel(F: Panel; x, y: INTEGER; dlink: Objects.Object);
VAR P: Display.DisplayMsg; f: Display.Frame; R: Display3.Mask;

	PROCEDURE Pr(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit) END Pr;

BEGIN
	Gadgets.MakePrinterMask(F, x, y, dlink, R);
	IF F.pict # NIL THEN
		IF ~(texture IN F.state0) THEN
			IF F.pict.width < F.W THEN
				Printer3.FillPattern(R, 15, Display3.selectpat, x, y, x + Pr(F.pict.width), y, Pr(F.W - F.pict.width), Pr(F.H), Display.replace);
			END;
			IF F.pict.height < F.H THEN
				Printer3.FillPattern(R, 15, Display3.selectpat, x, y, x, y, Pr(F.W), Pr(F.H - F.pict.height), Display.replace);
			END;
			Printer3.Pict(R, F.pict, x, y + Pr(F.H - F.pict.height), Pr(F.pict.width), Pr(F.pict.height), Display.replace)
		ELSE Printer3.ReplPict(R, F.pict, x, y, x, y, Pr(F.W), Pr(F.H), Display.replace)
		END
	ELSIF flatlook IN F.state0 THEN
		Printer3.ReplConst(R, F.col, x, y, Pr(F.W), Pr(F.H), Display.replace)
	ELSE
		Printer3.FilledRect3D(R, Display3.topC, Display3.bottomC, F.col, x, y, Pr(F.W), Pr(F.H), 5, Display.replace)
	END;
	f := F.dsc; y := y + Pr(F.H) - 1;
	WHILE (f # NIL) & (Printer.res = 0) DO
		P.res := -1; Objects.Stamp(P); P.device := Display.printer; P.id := Display.full; P.F := f; P.dlink := F;
		P.x := x + SHORT(LONG(f.X) * Display.Unit DIV Printer.Unit);
		P.y := y + SHORT(LONG(f.Y) * Display.Unit DIV Printer.Unit);
		f.handle(f, P);
		f := f.next
	END;
END PrintPanel;

(** Bring f to the top in F. *)
PROCEDURE PromoteChild*(F: Display.Frame; f: Display.Frame);
VAR p, p0: Display.Frame;
BEGIN
	p := F.dsc; p0 := NIL;
	WHILE p # NIL DO
		IF p = f THEN
			IF p0 # NIL THEN p0.next := p.next; ELSE F.dsc := p.next; END;
			IF F.dsc # NIL THEN
				p := F.dsc; WHILE p.next # NIL DO p := p.next; END;
				p.next := f;
			ELSE
				F.dsc := f;
			END;
			f.next := NIL; RETURN
		END;
		p0 := p; p := p.next;
	END;
END PromoteChild;

(** Method implementation. *)
PROCEDURE RemoveChild*(F: Panel; f: Display.Frame);
VAR T, T0: Display.Frame;
BEGIN
	GrowHull(F, f.X, f.Y, f.W, f.H);
	
	T := F.dsc; T0 := NIL;
	WHILE T # NIL DO
		IF T = f THEN
			IF T0 # NIL THEN T0.next := f.next; f.next := NIL;
			ELSE F.dsc := f.next; f.next := NIL;  
			END;
			RETURN
		END;
		T0 := T; T := T.next
	END;
END RemoveChild;

(** Put f at the back in F. *)
PROCEDURE DemoteChild*(F: Panel; f: Display.Frame);
BEGIN
	IF IsChild(F, f) THEN
		RemoveChild(F, f); f.next := F.dsc; F.dsc := f;
	END;
END DemoteChild;

PROCEDURE Priority(F: Panel; f: Display.Frame; where: INTEGER; passon: BOOLEAN);
VAR M: Gadgets.PriorityMsg; g: Display.Frame;
BEGIN
	IF where = Gadgets.top THEN
		PromoteChild(F, f); InvalidateMasks(F, NIL, f.X, f.Y, f.W, f.H); Gadgets.Update(f)
	ELSIF where = Gadgets.bottom THEN
		DemoteChild(F, f); InvalidateMasks(F, NIL, f.X, f.Y, f.W, f.H); Gadgets.Update(f)
	ELSIF where = Gadgets.visible THEN
		g := f.next;
		LOOP
			IF g = NIL THEN EXIT END;
			IF Effects.Intersect(g.X, g.Y, g.W, g.H, f.X, f.Y, f.W, f.H) THEN
				PromoteChild(F, f); InvalidateMasks(F, NIL, f.X, f.Y, f.W, f.H); Gadgets.Update(f);
				EXIT
			END;
			g := g.next
		END
	END;
	IF passon THEN
		M.id := where; M.F := F; M.passon := TRUE; Display.Broadcast(M);
	END;
END Priority;

PROCEDURE CopyOver(F: Panel; text: Texts.Text; beg, end: LONGINT);
VAR T: Texts.Text; buf: Texts.Buffer;
BEGIN
	NEW(buf); Texts.OpenBuf(buf);
	Texts.Save(text, beg, end, buf);
	Oberon.Defocus;
	NEW(T); Texts.Open(T, "");
	Texts.Insert(T, 0, buf); Objects.NewObj := T;
	Gadgets.Execute("TextFields.MakeCaption", NIL, NIL, NIL, NIL);
	IF Objects.NewObj # NIL THEN
		F.do.InsertFrames(F, F.focusx, F.focusy, Objects.NewObj(Display.Frame));
	END;
END CopyOver;

PROCEDURE PanelHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR F2: Panel; u, v, x, y, w, h: INTEGER; R: Display3.Mask; t: Display.Frame; obj: Objects.Object; U: Display3.UpdateMaskMsg;
BEGIN
	WITH F: Panel DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF M.res >= 0 THEN RETURN END;
				u := M.x; v := M.y; x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
				IF (M.F = NIL) OR (M.F = F) THEN (* for this panel or a broadcast *)
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg DO
							IF M.device = Display.screen THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								IF M.id = Display.area THEN F.do.RestoreArea(F, x, y, M.u, M.v, M.w, M.h, R, M.dlink)
								ELSE F.do.RestoreArea(F, x, y, 0, -h + 1, w, h, R, M.dlink)
								END
							ELSIF M.device = Display.printer THEN PrintPanel(F, u, v, M.dlink)
							END
						END
					ELSIF M IS Display3.OverlapMsg THEN
						WITH M: Display3.OverlapMsg DO F.mask := M.M; UpdateMasks(F, FALSE, TRUE); M.res := 0 END
					ELSIF M IS Display3.UpdateMaskMsg THEN
						NEW(F.mask); Display3.Open(F.mask); Display3.Add(F.mask, 0, -F.H+1, F.W, F.H);
						F.mask.x := 0; F.mask.y := 0; UpdateMasks(F, FALSE, TRUE); M.res := 0;
					ELSIF M IS Display.LocateMsg THEN
						WITH M: Display.LocateMsg DO
							IF (M.loc = NIL) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN Locate(F, M) END
						END
					ELSIF M IS Display.SelectMsg THEN
						WITH M: Display.SelectMsg DO
							IF (M.id = Display.get) THEN
								IF (F.time > M.time) & (F.time # 0) THEN
									GetPanelSelection(F, t);
									IF t # NIL THEN M.time := F.time; M.obj := t; M.sel := F END
								ELSE ToChildren(F, M)
								END
							ELSE Gadgets.framehandle(F, M)
							END;
						END
					ELSIF M IS Display.ConsumeMsg THEN
						WITH M: Display.ConsumeMsg DO
							IF ~(noinsert IN F.state0) THEN
								IF (M.id = Display.integrate) & F.focused THEN
									Oberon.Defocus; F.do.InsertFrames(F, F.focusx, F.focusy, M.obj); M.res := 0;
									F.focused := TRUE; F.focusx := newfocusX; F.focusy := newfocusY; F.do.UpdateCaret(F)
								ELSIF M.id = Display.drop THEN
									F.do.InsertFrames(F, M.u, M.v, M.obj); M.res := 0
								END
							END;
							IF M.res < 0 THEN ToChildren(F, M) END
						END
					ELSIF M IS Display.ModifyMsg THEN Adjust(F, x, y, M(Display.ModifyMsg))
					ELSIF M IS Display.ControlMsg THEN ToChildren(F, M)
					
					ELSIF M IS Gadgets.UpdateMsg THEN
						WITH M: Gadgets.UpdateMsg DO
							IF M.obj = F THEN Gadgets.framehandle(F, M)
							ELSIF (M.obj IS Gadgets.Frame) & IsChild(F, M.obj(Gadgets.Frame)) THEN
								ToChildren(F, M);
								obj := M.obj;
								WHILE obj # NIL DO t := obj(Display.Frame);
									IF Gadgets.transparent IN t(Gadgets.Frame).state THEN
										Gadgets.MakeMask(F, x, y, M.dlink, R); F.do.RestoreArea(F, x, y, t.X, t.Y, t.W, t.H, R, M.dlink)
									ELSE Gadgets.MakeMask(F, x, y, M.dlink, R); RestoreAboveArea(F, t, x, y, t.X, t.Y, t.W, t.H, M.dlink, R)
									END;
									obj := obj.slink
								END
							ELSE ToChildren(F, M)	
							END
						END
					ELSIF M IS Oberon.ControlMsg THEN
						WITH M: Oberon.ControlMsg DO
							IF M.id = Oberon.neutralize THEN
								SetChildren(F, x, y, Display.reset); F.time := 0;
								IF F.focused THEN F.focused := FALSE; F.do.UpdateCaret(F) END;
							ELSIF M.id = Oberon.defocus THEN
								IF F.focused THEN F.focused := FALSE; F.do.UpdateCaret(F) END;
							END;
							ToChildren(F, M)
						END
					ELSIF M IS Oberon.ConsumeMsg THEN
						WITH M: Oberon.ConsumeMsg DO
							IF F.focused THEN CopyOver(F, M.text, M.beg, M.end); M.res := 0; ELSE ToChildren(F, M) END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN
								IF (M.keys # {}) & (M.keys # {2}) & Effects.InBorder(M.X, M.Y, x, y, w, h) THEN
									Gadgets.framehandle(F, M)
								ELSIF ~(Gadgets.selected IN F.state) THEN F.do.TrackMouse(F, M)
								END
							ELSIF (M.id = Oberon.consume) & F.focused THEN
								F.do.ConsumeChar(F, M)
							ELSE ToChildren(F, M)
							END
						END
					ELSIF M.F # NIL THEN Gadgets.framehandle(F, M)
					ELSE ToChildren(F, M)
					END
				ELSE (* ================= perhaps for a child *)
					IF IsChild(F, M.F) THEN
						IF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg DO
								IF (M.device = Display.screen) & (Gadgets.transparent IN M.F(Gadgets.Frame).state) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									F.do.RestoreArea(F, x, y, M.F.X, M.F.Y, M.F.W, M.F.H, R, M.dlink)
								ELSE ToChildren(F, M)
								END
							END
						ELSIF M IS Display3.UpdateMaskMsg THEN
							IF F.mask = NIL THEN U.F := F; Display.Broadcast(U)
							ELSE UpdateMasks(F, TRUE, FALSE)
							END
						ELSIF M IS Display.ModifyMsg THEN HandleChildAdjust(F, M(Display.ModifyMsg))
						ELSIF M IS Gadgets.PriorityMsg THEN
							WITH M: Gadgets.PriorityMsg DO Priority(F, M.F, M.id, M.passon); M.res := 0 END
						ELSIF M IS Display.ControlMsg THEN
							WITH M: Display.ControlMsg DO
								ToChildren(F, M);
								IF M.id = Display.remove THEN F.do.RemoveFrames(F, M.F); M.res := 0 END;
							END
						ELSIF M IS Display.SelectMsg THEN
							WITH M: Display.SelectMsg DO
								IF M.id = Display.set THEN F.time := Oberon.Time(); ToChildren(F, M)
								ELSIF M.id = Display.reset THEN
									GetPanelSelection(F, t); IF t = NIL THEN F.time := 0; END;
									ToChildren(F, M)
								END
							END
						ELSIF M IS Display.ConsumeMsg THEN
							WITH M: Display.ConsumeMsg DO
								ToChildren(F, M);
								IF (M.res < 0) & ~(noinsert IN F.state0) THEN (* has not consumed *)
									F.do.InsertFrames(F, M.F.X + M.u, M.F.Y + M.F.H - 1 + M.v, M.obj); M.res := 0
								END
							END
						ELSE ToChildren(F, M)
						END
					ELSE ToChildren(F, M) (* not a direct child *)
					END
				END;
				M.x := u; M.y := v;
			END
		ELSIF M IS Objects.AttrMsg THEN PanelAttr(F, M(Objects.AttrMsg))
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
		ELSIF M IS Objects.BindMsg THEN
			Gadgets.framehandle(F, M); ToChildren(F, M);
			IF F.pict # NIL THEN F.pict.handle(F.pict, M) END
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Picture" THEN M.obj := F.pict; M.res := 0
					ELSE Gadgets.framehandle(F, M)
					END
				ELSIF M.id = Objects.set THEN
					IF M.name = "Picture" THEN (* ps - 13.2.96 *)
						IF M.obj = NIL THEN F.pict:= NIL; M.res:= 0
						ELSIF M.obj IS Pictures.Picture THEN F.pict := M.obj(Pictures.Picture); M.res := 0
						END
					ELSE Gadgets.framehandle(F, M)
					END
				ELSIF M.id = Objects.enum THEN
					M.Enum("Picture"); Gadgets.framehandle(F, M)
				ELSE HALT(99)
				END
			END
		ELSIF M IS Objects.FindMsg THEN FindObj(F, M(Objects.FindMsg))
		ELSE Gadgets.framehandle(F, M)
		END
	END
END PanelHandler;

PROCEDURE InitPanel*(P: Panel);
BEGIN P.handle := PanelHandler; P.dsc := NIL; P.W := 128; P.H := 128; P.focused := FALSE; P.time := 0;
	P.borderW := DefBorderWidth; P.grid := defaultgrid; ResetHull(P);
	P.do := methods; P.col := Display3.groupC
END InitPanel;

PROCEDURE NewPanel*;
VAR P: Panel; 
BEGIN NEW(P); InitPanel(P); Objects.NewObj := P;
END NewPanel;

(** Generator for a panel with a picture as background. Default picture is Default.Pict. *)
PROCEDURE NewPictPanel*;
VAR P: Panel; f: Files.File;
BEGIN NEW(P); InitPanel(P);
	f := Files.Old("Default.Pict");
	IF f # NIL THEN
		NEW(P.pict); Pictures.Open(P.pict, "Default.Pict", TRUE)
	END;
	Objects.NewObj := P
END NewPictPanel;

(** Command to bring the selection of a panel to the front. *)
PROCEDURE ToFront*;
VAR M: Display.SelectMsg; b: Objects.Object; P: Gadgets.PriorityMsg;
BEGIN
	M.id := Display.get; M.time := 0; M.obj := NIL; M.sel := NIL; M.F := NIL; Display.Broadcast(M);
	IF M.time > 0 THEN
		b := M.obj;  
		WHILE b # NIL DO
			P.id := Gadgets.top; P.F := b(Display.Frame); P.passon := TRUE; Display.Broadcast(P);
			b := b.slink
		END
	END;
END ToFront;

(**  Command to take the selection of a panel to the back. *)
PROCEDURE ToBack*;
VAR M: Display.SelectMsg; b: Objects.Object; P: Gadgets.PriorityMsg;
BEGIN
	M.id := Display.get; M.time := 0; M.obj := NIL; M.sel := NIL; M.F := NIL; Display.Broadcast(M);
	IF M.time > 0 THEN
		b := M.obj;  
		WHILE b # NIL DO
			P.id := Gadgets.bottom; P.F := b(Display.Frame); P.passon := TRUE; Display.Broadcast(P);
			b := b.slink
		END
	END;
END ToBack;

(** Used in the form:

	Panels.ChangeBackdrop <picturename>
	
Changes the background of the selected panels. Use a non-existing filename to reset the backdrop of a panel.
*)
PROCEDURE ChangeBackdrop*;
VAR S: Attributes.Scanner; M: Display.SelectMsg; b: Objects.Object; f: Files.File; P: Pictures.Picture;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF S.class = Attributes.Name THEN
		f := Files.Old(S.s);
		IF f # NIL THEN
			NEW(P); Pictures.Open(P, S.s, TRUE);
		ELSE
			Texts.WriteString(W, "  picture not found"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
			P := NIL
		END;
		M.id := Display.get; M.time := 0; M.obj := NIL; M.sel := NIL; M.F := NIL; Display.Broadcast(M);
		IF M.time > 0 THEN
			b := M.obj;  
			WHILE b # NIL DO
				IF b IS Panel THEN
					WITH b: Panel DO b.pict := P; Gadgets.Update(b) END;
				END;
				b := b.slink
			END
		ELSE
			Texts.WriteString(W, "  no selection"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	END
END ChangeBackdrop;

(* Top, Bottom, Left, Right, Vertical, Horizontal, Width, Height, Size *)
PROCEDURE Align0(type: ARRAY OF CHAR);
VAR M: Display.SelectMsg; obj, n: Objects.Object; x, y, w, h, maxW, maxH, px , py, count: INTEGER; A: Display.ModifyMsg;
	L, p, q: Objects.Object; vertical: BOOLEAN;
	
	PROCEDURE Score(F: Display.Frame): LONGINT;
	BEGIN
		IF vertical THEN RETURN 16000 - F.Y ELSE RETURN F.X END
	END Score;
	
BEGIN
	M.id := Display.get; M.time := 0; M.sel := NIL; M.obj := NIL; M.F := NIL;
	Display.Broadcast(M);
	IF (M.time > 0) & (M.obj # NIL) THEN
		BoundingBox(M.obj(Display.Frame), x, y, w, h, count);
		
		vertical := (type = "verticalcenter") OR (type = "vertical");
		(* First Pass *)
		maxW := 0; maxH := 0; L := NIL;
		obj := M.obj;
		WHILE obj # NIL DO
			n := obj.slink; obj.slink := NIL;
			WITH obj: Display.Frame DO	
				maxW := Max(maxW, obj.W); maxH := Max(maxH, obj.H);
				IF L = NIL THEN L := obj;
				ELSE
					q := L; p := NIL;
					WHILE (q # NIL) & (Score(obj) > Score(q(Display.Frame))) DO p := q; q := q.slink END;
					IF p # NIL THEN obj.slink := q; p.slink := obj
					ELSE obj.slink := L; L := obj
					END
				END;
			END;
			obj := n
		END;
		
		(* Second Pass *)
		px := x; py := y + h - 1;
		obj := (*M.obj*) L;
		WHILE obj # NIL DO
			n := obj.slink;
			WITH obj: Display.Frame DO A.id := Display.move; A.mode := Display.display; A.F := obj;
				A.X := obj.X; A.Y := obj.Y; A.W := obj.W; A.H := obj.H;
				IF type = "bottom" THEN A.Y := y
				ELSIF type = "top" THEN A.Y := y + h - obj.H;
				ELSIF type = "left" THEN A.X := x
				ELSIF type = "right" THEN A.X := x + w - obj.W
				ELSIF type = "width" THEN A.W := maxW
				ELSIF type = "height" THEN A.H := maxH
				ELSIF type = "size"THEN A.W := maxW; A.H := maxH
				ELSIF type = "verticalcenter" THEN A.X := x + maxW DIV 2 - obj.W DIV 2;
				ELSIF type = "horizontalcenter" THEN A.Y := y + h - maxH DIV 2 - obj.H DIV 2;
				ELSIF type = "horizontal" THEN A.X := px; INC(px, obj.W)
				ELSIF type = "vertical" THEN A.Y := py - obj.H + 1; DEC(py, obj.H)
				END;
				A.dX := A.X - obj.X; A.dY := A.Y - obj.Y; A.dW := A.W - obj.W; A.dH := A.H - obj.H; Display.Broadcast(A);
			END; 
			obj := n;
		END
	ELSE Texts.WriteString(W, "  no selection "); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	END
END Align0;

(** Aligns the selected children of a panel. Used in the form:

	Panels.Align < bottom | top | left | right | width | height | size | verticalcenter | horizontalcenter | horizontal | vertical >
*)
PROCEDURE Align*;
VAR S: Attributes.Scanner;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF S.class = Attributes.Name THEN Align0(S.s) END;
END Align;

(** Determine if possible to have list as children of F. *)
PROCEDURE NewChildrenOK*(F: Panel; VAR list: Objects.Object): BOOLEAN;
VAR obj, newobj: Objects.Object; ok: BOOLEAN; t: Objects.Object;
BEGIN
	obj := list; list := NIL; ok := TRUE;
	WHILE (obj # NIL) & ok DO
		newobj := obj;
		obj := obj.slink; (* get next already *)
		IF ~(newobj IS Gadgets.Frame) THEN F.do.TranslateToGadget(F, newobj) END;
		ok := F.do.AcceptChild(F, newobj);
		IF ok & (newobj # NIL) & (newobj IS Gadgets.Frame) THEN
			WITH newobj: Gadgets.Frame DO
				IF Gadgets.Recursive(F, newobj) THEN
					Texts.WriteString(W,"Not allowed, will cause recursive structures");
					Texts.Append(Oberon.Log, W.buf); ok := FALSE;
				ELSIF  (newobj.lib # NIL) & (newobj.lib.name # "") & (F.lib # newobj.lib) THEN
					Texts.WriteString(W," sorry, cannot insert public object directly in panel; make a copy first");
					Texts.WriteLn(W);
					Texts.Append(Oberon.Log, W.buf); ok := FALSE;
				END;
			END;
			(* Append to list, can be optimized a little *)
			IF ok THEN
				newobj.slink := NIL;
				IF list = NIL THEN list := newobj
				ELSE t := list; WHILE t.slink # NIL DO t := t.slink END; t.slink := newobj
				END
			END
		END;
	END;
	RETURN ok
END NewChildrenOK;

(** Copy a list of objects Objects.deep or Objects.shallow. *)
PROCEDURE CopyObjList*(id: INTEGER; from: Objects.Object; VAR to: Objects.Object);
VAR t, t0: Objects.Object; C: Objects.CopyMsg;
BEGIN
	t := from; to := NIL; C.stamp := Oberon.Time();
	C.id := id;
	IF t # NIL THEN
		t.handle(t, C); t0 := C.obj; t:= t.slink; to := t0
	END;
	WHILE t # NIL DO
		t.handle(t, C); t0.slink := C.obj;
		t := t.slink; t0 := t0.slink
	END;
END CopyObjList;

(** Recalls last deleted children to the caret. *)
PROCEDURE Recall*;
VAR M: Display.ConsumeMsg;
BEGIN
	IF (recall # NIL) THEN
		M.id := Display.integrate; M.F := NIL; CopyObjList(Objects.deep, recall, M.obj);
		Display.Broadcast(M);
	END;
END Recall;


(* === Method implementations === *)

PROCEDURE RestoreBackGround*(F: Panel; x, y: INTEGER; R: Display3.Mask);
BEGIN
	IF F.pict # NIL THEN
		
		IF ~(texture IN F.state0) THEN
			IF F.pict.width < F.W THEN
				Display3.FillPattern(R, 15, Display3.selectpat, x, y, x + F.pict.width, y, F.W - F.pict.width, F.H, Display.replace);
			END;
			IF F.pict.height < F.H THEN
				Display3.FillPattern(R, 15, Display3.selectpat, x, y, x , y, F.W, F.H - F.pict.height, Display.replace);
			END;
			Display3.Pict(R, F.pict, 0, 0, F.pict.width, F.pict.height, x, y + F.H - F.pict.height, Display.replace)
		ELSE Display3.ReplPict(R, F.pict, x, y, x, y, F.W, F.H, Display.replace)
		END
	ELSIF flatlook IN F.state0 THEN Display3.ReplConst(R, F.col, x, y, F.W, F.H, Display.replace)
	ELSE Display3.FilledRect3D(R, Display3.topC, Display3.bottomC, F.col, x, y, F.W, F.H, 1, Display.replace)
	END
END RestoreBackGround;

PROCEDURE RestoreCaret*(F: Panel; x, y: INTEGER; R: Display3.Mask);
BEGIN
	Display3.CopyPattern(R, Display3.textC, Display.cross, x + F.focusx - markW, y + F.H - 1 + F.focusy - markW, 
			Display3.paint);
END RestoreCaret;

PROCEDURE UpdateCaret*(F: Panel);
BEGIN
	GrowHull(F, F.focusx - markW, F.focusy - markW, markW*2+1, markW*2+1); DrawHull(F);
END UpdateCaret;

PROCEDURE TrackCaret*(F: Panel; VAR M: Oberon.InputMsg);
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
		GetSelection(obj, parent, objtime); Oberon.GetSelection(text, beg, end, texttime);
		IF (obj # NIL) & (objtime > texttime) THEN (* use the object selection *)
			CopyObjList(Objects.shallow, obj, newobj);
			F.do.InsertFrames(F, F.focusx, F.focusy, newobj);
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

(** Select the gadgets in the area u, v, w, h of the panel. *)
PROCEDURE SelectArea*(F: Panel; x, y, u, v, w, h: INTEGER);
VAR M: Display.SelectMsg; f: Display.Frame; b: BOOLEAN;

	PROCEDURE Inside(F: Display.Frame): BOOLEAN;
	BEGIN
		RETURN (u <= F.X) & (v <= F.Y) & (u+w-1 >= F.X+F.W-1) & (v+h-1 >= F.Y+F.H-1);
	END Inside;
	
BEGIN
	ResetHull(F); 
	f := F.dsc; b := FALSE;
	WHILE f # NIL DO
		IF f IS Gadgets.Frame THEN
			IF Inside(f) THEN
				IF ~(Gadgets.selected IN f(Gadgets.Frame).state) THEN
					M.x := 0;  M.y := 0;
					M.id := Display.set; M.res := -1; M.F := f; ToChild(F, f, x, y, M);
					GrowHull(F, f.X, f.Y, f.W, f.H);
				END;
				b := TRUE; 
			ELSE
				IF Gadgets.selected IN f(Gadgets.Frame).state THEN
					M.x := 0;  M.y := 0;
					M.id := Display.reset; M.res := -1; M.F := f; ToChild(F, f, x, y, M); 
					GrowHull(F, f.X, f.Y, f.W, f.H);
				END;
			END;
		END;
		 f := f.next;
	END;
	DrawHull(F); 
	IF b THEN F.time := Oberon.Time(); ELSE F.time := 0; END;
END SelectArea;

PROCEDURE *SelectHandler(mx, my, x, y, w, h: INTEGER; keysum: SET);
BEGIN
	SelectArea(tmpP, px, py, sx - px, y - (py  + tmpP.H - 1), sw, h);
	SelectArea(tmpP, px, py, x - px, y - (py + tmpP.H - 1), w, h);
	sx := x; sy := y; sw := w; sh := h;
END SelectHandler;

(** Delete children from the panel. recall is updated. *)
PROCEDURE KillChildren*(F: Panel; objlist: Objects.Object);
VAR f: Objects.Object; A: Display.ControlMsg;
BEGIN
	IF objlist # NIL THEN
		F.time := 0;
		A.id := Display.remove; A.F := objlist(Display.Frame); Display.Broadcast(A); (* <<< remove everything *)
		recall := objlist; (* update recall list *)
		
		(* unname objects *)
		IF (F.lib # NIL) & (F.lib.name # "") THEN
			f := objlist;
			WHILE f # NIL DO
				IF (f.lib # NIL) & (f.lib = F.lib) THEN
					Objects.PutName(f.lib.dict, f.ref, ""); (* ! *)
					f.lib.FreeObj(f.lib, f.ref); f.lib := NIL; f.ref := -1;
				END;
				f := f.slink
			END
		END
	END
END KillChildren;

PROCEDURE TrackSelection*(F: Panel; VAR M: Oberon.InputMsg);
VAR keysum: SET; objlist: Display.Frame; newobj: Objects.Object;
BEGIN
	px := M.x + F.X; py := M.y + F.Y; tmpP := F;
	sx := M.X; sy := M.Y; sw := 2; sh := 2;
	
	Effects.SizeRect(NIL, keysum, M.X, M.Y, sx, sy, sw, sh, SelectHandler);
	tmpP := NIL;
	M.res := 0;
	
	IF keysum = {0, 2} THEN (* delete selection *)
		GetPanelSelection(F, objlist); KillChildren(F, objlist)
	ELSIF keysum = {0, 1} THEN (* copy to focus *)
		GetPanelSelection(F, objlist);
		IF objlist # NIL THEN
			CopyObjList(Objects.shallow, objlist, newobj);
			Gadgets.Integrate(newobj)
		END
	END
END TrackSelection;

PROCEDURE TrackSelectChild*(F: Panel; VAR M: Oberon.InputMsg; child: Gadgets.Frame);
VAR x, y, sx, sy: INTEGER; S: Display.SelectMsg; keysum: SET; t: Display.Frame; newobj: Objects.Object;
BEGIN
	x := M.x + F.X; y := M.y + F.Y;
	
	S.F := child; S.res := -1; S.dlink := NIL; ResetHull(F);
	S.x := 0;  S.y := 0;
	IF Gadgets.selected IN child.state THEN S.id := Display.reset; ToChild(F, child, x, y, S);
		GetPanelSelection(F, t);
		IF t = NIL THEN F.time := 0; END;
	ELSE S.id := Display.set; ToChild(F, child, x, y, S); F.time := Oberon.Time()
	END;
	GrowHull(F, child.X, child.Y, child.W, child.H); DrawHull(F);
	
	M.res := 0;
	keysum := {}; sx := M.X; sy := M.Y;
	REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys;
	UNTIL (M.keys = {}) OR ~Effects.Invicinity(M.X, M.Y, sx, sy);
	
	IF M.keys # {} THEN F.do.TrackSelection(F, M)
	ELSE
		IF keysum = {0, 2} THEN (* RL delete selection *)
			GetPanelSelection(F, t); KillChildren(F, t)
		ELSIF keysum = {0, 1} THEN  (* RM copy to focus *)
			GetPanelSelection(F, t);
			IF t # NIL THEN
				CopyObjList(Objects.shallow, t, newobj);
				Gadgets.Integrate(newobj)
			END
		END
	END
END TrackSelectChild;
		
(** Accepts and returns a single gadget. *)
PROCEDURE TranslateToGadget*(F: Panel; VAR obj: Objects.Object);
VAR f: Objects.Object; (* C: Display.ConsumeMsg;*) L: Objects.LinkMsg;
	A: Objects.AttrMsg;
BEGIN
	IF obj IS Pictures.Picture THEN
	(* older version 
		f := Gadgets.CreateObject("PictureGadgets.NewPict");
		IF (f # NIL) & (f IS Gadgets.Frame) THEN
			C.id := Display.drop; C.F := f(Display.Frame); C.obj := obj; C.res := -1;
			C.x := 0; C.y := 0; f.handle(f,C); 
			obj := f;
		END;
	 *)
	(* version for Rembrandt *)
		f := Gadgets.CreateObject("Rembrandt.New");
		IF (f # NIL) & (f IS Gadgets.Frame) THEN
			WITH f: Gadgets.Frame DO
				L.id := Objects.set; L.obj := obj; L.res := -1; L.name := "Model"; f.handle(f, L);
				f.W := obj(Pictures.Picture).width; f.H := obj(Pictures.Picture).height;
				
				A.id := Objects.set; A.name := "Locked"; A.class := Objects.Bool; A.b := TRUE; A.res := -1; f.handle(f, A);
				A.id := Objects.set; A.name := "Border"; A.class := Objects.Bool; A.b := FALSE; A.res := -1; f.handle(f, A);
				obj := f
			END
		END;
	(* *)
	END
END TranslateToGadget;

PROCEDURE AcceptChild*(F: Panel; VAR obj: Objects.Object): BOOLEAN;
BEGIN RETURN TRUE
END AcceptChild;

PROCEDURE InsertChild*(F: Panel; f: Display.Frame; u, v: INTEGER);
VAR f0: Display.Frame; B: Objects.BindMsg; A: Display.ModifyMsg;
BEGIN
	IF (F.lib # NIL) & (F.lib.name # "") THEN B.lib := F.lib; f.handle(f, B) END;
	
	(* F.do.ModifyChild(F, f, u, v, TRUE) *)
	A.id := Display.move; A.mode := Display.state; A.x := 0; A.y := 0; A.X := u; A.Y := v; A.W := f.W; A.H := f.H;
	A.dX := 0;  A.dY := 0;  A.dW := 0;  A.dH := 0;
	A.res := -1; A.F := f; A.dlink := NIL;
	Objects.Stamp(A);
	f.handle(f, A);
		
	GrowHull(F, f.X, f.Y, f.W, f.H);
	
	(* add at end of the list *)
	f.next := NIL;
	IF F.dsc # NIL THEN
		f0 := F.dsc; WHILE f0.next # NIL DO f0 := f0.next; END; f0.next := f
	ELSE F.dsc := f
	END
END InsertChild;

PROCEDURE InsertFrames*(F: Panel; u, v: INTEGER; list: Objects.Object);
VAR x, y, w, h, count: INTEGER; f, n: Display.Frame; O: Display3.OverlapMsg; A: Display.ControlMsg;
BEGIN
	newfocusX := F.focusx; newfocusY := F.focusy;
	IF NewChildrenOK(F, list) & (list # NIL) THEN (* insert can proceed *)
	
		BoundingBox(list(Gadgets.Frame), x, y, w, h, count);
		x := u - x; y := v - y;
		
		O.M := NIL; O.F := NIL; O.x := 0; O.y := 0; O.res := -1; Objects.Stamp(O);
		
		A.id := Display.remove; A.F := list(Gadgets.Frame); Display.Broadcast(A); (* <<< remove the whole list *)
		ResetHull(F);
		f := list(Gadgets.Frame);
		WHILE f # NIL DO
			IF f.slink # NIL THEN n := f.slink(Display.Frame) ELSE n := NIL END;
			F.do.InsertChild(F, f, f.X + x, f.Y + y);
			IF count < 10 THEN InvalidateMasks(F, f, f.X, f.Y, f.W, f.H); END;
			O.res := -1; f.handle(f, O);
			f := n;
		END;
		IF count < 10 THEN UpdateMasks(F, TRUE, FALSE) ELSE UpdateMasks(F, FALSE, TRUE) END;
		DrawHull(F);
		newfocusX := u + w + 5; newfocusY := v
	END
END InsertFrames;

PROCEDURE RemoveFrames*(F: Panel; list: Display.Frame);
VAR f: Display.Frame;
BEGIN
	ResetHull(F);
	f := list; 
	WHILE f # NIL DO
		F.do.RemoveChild(F, f);
		IF f.slink # NIL THEN f := f.slink(Display.Frame) ELSE f := NIL END;
	END;
	UpdateMasks(F, FALSE, TRUE); DrawHull(F);
END RemoveFrames;

PROCEDURE NewLocateMsg(F: Display.Frame; u, v: INTEGER; VAR M: Display.LocateMsg);
VAR f, T: Display.Frame; childu, childv, x, y, tu, tv, X, Y: INTEGER;
BEGIN
	childu := u + F.X; childv := v + F.Y + F.H - 1; X := M.X; Y := M.Y;
	f := F.dsc; T := NIL;
	WHILE f # NIL DO
		x := childu + f.X; y := childv + f.Y;
		IF (X >= x) & (Y >= y) & (X < x + f.W) & (Y < y + f.H) & 
			~((f IS Gadgets.Frame) & (Gadgets.selected IN f(Gadgets.Frame).state)) THEN
			M.x := childu; M.y := childv; M.dlink := NIL; M.F := NIL; M.loc := NIL; M.res := -1;
			f.handle(f, M);
			IF M.loc # NIL THEN T := M.loc; (* tx := M.x; ty := M.y; *) tu := M.u; tv := M.v; END;
		END;
		f := f.next;
	END;
	IF T = NIL THEN
	ELSE M.loc := T; M.u := tu; M.v := tv;
	END;
END NewLocateMsg;

PROCEDURE NewHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR u, v: INTEGER; 
BEGIN
	WITH F: Display.Frame DO
		IF M IS Display.LocateMsg THEN
			WITH M: Display.LocateMsg DO
				u := M.x; v := M.y; 
				NewLocateMsg(F, u, v, M);
				IF (M.loc = NIL) & Effects.Inside(M.X, M.Y, u+F.X, v+F.Y, F.W, F.H) THEN
					M.loc := F; M.u := M.X - (u+F.X); M.v := M.Y - (v+F.Y+F.H-1); M.res := 0;
					RETURN
				END
			END
		ELSE HALT(42);
		END;
	END;
END NewHandler;

PROCEDURE TranslateChildren*(F: Panel; list: Display.Frame; count, dx, dy: INTEGER);
VAR p: Display.Frame; A: Display.ModifyMsg; x0, y0: INTEGER;
BEGIN
	p := list;
	WHILE p # NIL DO
		A.id := Display.move; A.mode := Display.state; A.F := p;
		A.X := p.X + dx; A.Y := p.Y + dy; A.W := p.W; A.H := p.H;
		A.dX := A.X - p.X; A.dY := A.Y - p.Y; A.dW := 0; A.dH := 0;
		GrowHull(F, A.X, A.Y, A.W, A.H);
		x0 := p.X; y0 := p.Y; 
		Display.Broadcast(A);
		IF count < 10 THEN InvalidateMasks(F, p, x0, y0, p.W, p.H); InvalidateMasks(F, p, p.X, p.Y, p.W, p.H) END;
		IF p.slink # NIL THEN p := p.slink(Display.Frame) ELSE p := NIL; END;
	END;
	IF count < 10 THEN UpdateMasks(F, TRUE, FALSE) ELSE UpdateMasks(F, FALSE, TRUE) END;
	DrawHull(F)
END TranslateChildren;

PROCEDURE DragSelection*(F: Panel; VAR M: Oberon.InputMsg);
VAR u, v, X, Y, x, y, w, h, nx, ny, nw, nh, u0, v0, count: INTEGER; f, q: Display.Frame; keys: SET;
	C: Display.ConsumeMsg; old: Objects.Handler; nl: Objects.Object; 
BEGIN
	GetPanelSelection(F, f);
	BoundingBox(f, x, y, w, h, count);
	IF (w # 0) & (h # 0) THEN
		u := M.x; v := M.y; x := u + F.X + x; y := v + F.Y + F.H - 1 + y;
		Input.Mouse(keys, X, Y); Effects.Snap(X, Y);
		nx := x; ny := y; nw := w; nh := h;
		Effects.MoveRect(NIL, keys, X, Y, nx, ny, nw, nh);
		old := F.handle; F.handle := NewHandler;
		Gadgets.ThisFrame(X, Y, q, u0, v0);
		F.handle := old;
		IF q # NIL THEN
			IF keys = {1, 0} THEN (* copy frames *)
				CopyObjList(Objects.shallow, f, nl);
				C.id := Display.drop; C.F := q; C.u := u0 + (nx - X); C.v := v0 + (ny - Y); C.obj := nl;
				Display.Broadcast(C);
			ELSIF keys = {1, 2} THEN (* consume frames *)
				C.id := Display.drop; C.F := q; C.u := u0 + (nx - X); C.v := v0 + (ny - Y); C.obj := f;
				Display.Broadcast(C);
			ELSIF keys = {1} THEN
				(* move to own boundary *)
				ResetHull(F); GrowHull(F, x - (F.X + u), y - (v + F.Y + F.H - 1), w, h);
				TranslateChildren(F, f, count, nx - x, ny - y);
			END
		END
	END
END DragSelection;

PROCEDURE ConsumeChar*(F: Panel; VAR M: Oberon.InputMsg);
	
	PROCEDURE Shift(dx, dy: INTEGER);
	VAR f: Display.Frame; x, y, w, h, count: INTEGER;
	BEGIN
		GetPanelSelection(F, f);
		IF f # NIL THEN
			BoundingBox(f, x, y, w, h, count);
			ResetHull(F); GrowHull(F, x, y, w, h);
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

BEGIN Texts.OpenWriter(W); defaultgrid := 2;
	NEW(methods);
	methods.TrackMouse := TrackMouse;
	methods.RestoreBackGround := RestoreBackGround;
	methods.RestoreCaret := RestoreCaret;
	methods.RestoreArea := RestoreArea;
	methods.TrackCaret := TrackCaret;
	methods.TrackSelection := TrackSelection;
	methods.TrackSelectChild := TrackSelectChild;
	methods.ConsumeChar := ConsumeChar;
	methods.UpdateCaret := UpdateCaret;
	methods.InsertChild := InsertChild;
	methods.InsertFrames := InsertFrames;
	methods.AcceptChild := AcceptChild;
	methods.TranslateToGadget := TranslateToGadget;
	methods.RemoveChild := RemoveChild;
	methods.RemoveFrames := RemoveFrames;
	methods.DragSelection := DragSelection
END Panels.

