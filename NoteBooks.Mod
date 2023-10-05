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

MODULE NoteBooks;	(** portable *)
(* NoteBook Gadgets, jm 5.5.94

The NoteBook gadgets are intended as an example of a more complicated container gadget. It is derived from
the Portrait gadgets also provided in source form. It allows you to insert and remove pages (gadgets) into a
notebook, and then to page through it.
*)

IMPORT Fonts, Objects, Display, Gadgets, Display3, Effects, Oberon, Attributes, Files, Views, Out;
	
CONST
	border = 4;		(* border width around the sides of the Notebook *)
	topborder = 16; (* Size of the border at the top *)
	
TYPE
	NoteBook* = POINTER TO NoteBookDesc;
	NoteBookDesc* = RECORD (Gadgets.FrameDesc)
		pages*: Display.Frame;	(* list of pages belonging to the notebook *)
		time*: LONGINT	(* time of selection *)
	END;
	
	(* Message to change the current page *)
	PageMsg = RECORD (Display.FrameMsg)
		newpage: Display.Frame;
	END;

(* Set the mask of a specific gadget *)
PROCEDURE SetMask(F: Display.Frame; M: Display3.Mask);
VAR O: Display3.OverlapMsg;
BEGIN IF F # NIL THEN O.M := M; O.x := 0; O.y := 0; O.F := F; O.dlink := NIL; O.res := -1; F.handle(F, O) END
END SetMask;

(* Calculate and set the mask of the current page *)
PROCEDURE SetMainMask(F: NoteBook);
VAR R: Display3.Mask;
BEGIN
	IF F.dsc # NIL THEN
		IF F.mask = NIL THEN SetMask(F.dsc, NIL)
		ELSE Display3.Copy(F.mask, R); R.x := 0; R.y := 0;
			Display3.Intersect(R, F.dsc.X,  F.dsc.Y, F.dsc.W,  F.dsc.H);
			R.x := -F.dsc.X; R.y := -(F.dsc.Y + F.dsc.H - 1); Display3.Shift(R);
			SetMask(F.dsc, R)
		END
	END
END SetMainMask;

(* Forward a message to the current child *)
PROCEDURE ToMain(F: NoteBook; x, y: INTEGER; VAR M: Display.FrameMsg);
VAR Mdlink, Fdlink: Objects.Object; tx, ty: INTEGER;
BEGIN
	IF F.dsc # NIL THEN tx := M.x; ty := M.y;
		M.x := x; M.y := y + F.H - 1;
		Fdlink := F.dlink; Mdlink := M.dlink; 
		F.dlink := M.dlink; M.dlink := F; F.dsc.handle(F.dsc, M);
		F.dlink := Fdlink; M.dlink := Mdlink;
		M.x := tx; M.y := ty
	END
END ToMain;

(* Handle size adjusting of the NoteBook *)
PROCEDURE Adjust(F: NoteBook; VAR M: Display.ModifyMsg);
VAR A: Display.ModifyMsg;
BEGIN
	IF F.dsc # NIL THEN A.id := Display.extend; A.F := F.dsc; A.mode := Display.state;
		A.X := border; A.Y := -M.H + 1 + border; A.W := M.W - 2 * border; A.H := M.H - (border + topborder);
		A.dX := A.X - F.dsc.X; A.dY := A.Y - F.dsc.Y; A.dW := A.W - F.dsc.W; A.dH := A.H - F.dsc.H;
		A.x := 0; A.y := 0; A.res := -1; Objects.Stamp(A);
		F.dsc.handle(F.dsc, A)
	END;
	Gadgets.framehandle(F, M)
END Adjust;

(* Handle adjusting of the page size *)
PROCEDURE AdjustChild(F: NoteBook; VAR M: Display.ModifyMsg);
VAR A: Display.ModifyMsg;
BEGIN
	IF M.stamp # F.stamp THEN F.stamp := M.stamp;
		A.id := Display.extend; A.F := F; A.mode := Display.display;
		A.X := F.X + M.dX; A.Y := F.Y + M.dY; A.W := M.W + 2 * border; A.H := M.H + (border + topborder);
		A.dX := A.X - F.X; A.dY := A.Y - F.Y; A.dW := A.W - F.W; A.dH := A.H - F.H;
		Display.Broadcast(A)
	END
END AdjustChild;

(* Display the current page title *)
PROCEDURE UpdateTitle(F: NoteBook; R: Display3.Mask; x, y, w, h: INTEGER);
VAR s: ARRAY 64 OF CHAR;
BEGIN
	Display3.ReplConst(R, Display3.textbackC, x + 20, y + h - topborder, w - 21, topborder - 1, Display.replace);
	IF F.dsc # NIL THEN
		Gadgets.GetObjName(F.dsc, s);
		IF s # "" THEN
			Display3.String(R, Display.FG, x + border + 20, y + h - Fonts.Default.height, Fonts.Default, s, Display.paint)
		END
	END;
END UpdateTitle;

PROCEDURE Restore(F: NoteBook; R: Display3.Mask; x, y, w, h: INTEGER; VAR M: Display.DisplayMsg);
VAR D: Display.DisplayMsg; s: ARRAY 64 OF CHAR;

	PROCEDURE ClipAgainst(VAR x, y, w, h: INTEGER; x1, y1, w1, h1: INTEGER);
	VAR r, t, r1, t1: INTEGER;
	BEGIN r := x + w - 1; r1 := x1 + w1 - 1; t := y + h - 1; t1 := y1 + h1 - 1;
		IF x < x1 THEN x := x1 END; IF y < y1 THEN y := y1 END;
		IF r > r1 THEN r := r1 END; IF t > t1 THEN t := t1 END;
		w := r - x + 1; h := t - y + 1;
	END ClipAgainst;
	
BEGIN
	Display3.ReplConst(R, Display3.textbackC, x + 1, y + h - topborder, w - 2, topborder - 1, Display.replace);
	Display3.Rect(R, Display3.textbackC, Display.solid, x+1, y+1, w-2, h-2, border-1, Display.replace);
	
	Display3.Rect3D(R, Display3.bottomC, Display3.topC, x, y, w, h, 1, Display.replace);

	s[0] := CHR(31); s[1] := 0X;
	Display3.String(R, Display.FG, x + border, y + h - Fonts.Default.height, Fonts.Default, s, Display.paint);
	
	s[0] := CHR(27); s[1] := 0X;
	Display3.String(R, Display.FG, x + border + 8, y + h - Fonts.Default.height, Fonts.Default, s, Display.paint);
	
	IF F.dsc # NIL THEN
		Gadgets.GetObjName(F.dsc, s);
		IF s # "" THEN
			Display3.String(R, Display.FG, x + border + 20, y + h - Fonts.Default.height, Fonts.Default, s, Display.paint)
		END
	END;
	
	IF F.dsc = NIL THEN
		Display3.FilledRect3D(R, Display3.topC, Display3.bottomC, (* Display3.white *) 3,
			x + border, y + border, w - border * 2, h - (border + topborder), 1, Display.replace)
	ELSIF M.id = Display.area THEN
		D.device := Display.screen; D.id := Display.area; D.F := F.dsc; D.u := M.u; D.v :=  M.v; D.w := M.w; D.h := M.h;
		ClipAgainst(D.u, D.v, D.w, D.h, F.dsc.X, F.dsc.Y, F.dsc.W, F.dsc.H);
		DEC(D.u, border); INC(D.v,  topborder);
		D.dlink := M.dlink; D.res := -1; Objects.Stamp(D);
		ToMain(F, x, y, D);
	ELSE
		D.device := Display.screen; D.id := Display.full; D.F := F.dsc; D.dlink := M.dlink; D.res := -1; Objects.Stamp(D);
		ToMain(F, x, y, D)
	END;
	IF Gadgets.selected IN F.state THEN Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint) END
END Restore;

PROCEDURE HandlePageMsg(F: NoteBook; x, y, w, h: INTEGER; VAR M: PageMsg);
VAR C: Display.ControlMsg; A: Display.ModifyMsg; f: Display.Frame;
	N: Oberon.ControlMsg; S: Display.SelectMsg;
BEGIN
	IF M.stamp # F.stamp THEN (* first time *)
		F.stamp := M.stamp;
		
		f := M.newpage;
		
		IF f # NIL THEN (* inform the page that it missed a few messages while not visible *)
			C.id := Display.restore; C.F := NIL; C.x := 0; C.y := 0; C.dlink := NIL; C.res := -1; f.handle(f, C)
		END;
		F.dsc := f;
		
		IF f # NIL THEN
			IF Gadgets.selected IN f(Gadgets.Frame).state THEN
				S.id := Display.reset; S.F := f; S.res := -1; ToMain(F, x, y, S)
			END;
	
			A.X := border; A.Y := -F.H + 1 + border; A.W := F.W - 2 * border; A.H := F.H - (border + topborder);
			A.id := Display.extend; A.F := f; A.mode := Display.state; A.dlink := NIL;
			A.dX := A.X - f.X; A.dY := A.Y - f.Y; A.dW := A.W - f.W; A.dH := A.H - f.H;
			A.res := -1; Objects.Stamp(A);
			ToMain(F, x, y, A);
			
			N.id := Oberon.neutralize; N.F := NIL; N.res := -1; N.dlink := M.dlink; ToMain(F, x, y, N)
		END;
		Gadgets.Update(F); M.res := 0;
	END
END HandlePageMsg;

PROCEDURE GotoPage(F: NoteBook; f: Display.Frame);
VAR P: PageMsg;
BEGIN
	IF F.dsc # f THEN P.F := F; P.newpage := f; Display.Broadcast(P) END
END GotoPage;

PROCEDURE InsertPage(F: NoteBook; f: Display.Frame);
VAR t: Display.Frame;
BEGIN
	IF f # NIL THEN
		f.next := NIL;
		IF F.pages = NIL THEN F.pages := f
		ELSE
			t := F.pages;
			WHILE t.next # NIL DO t := t.next END;
			t.next :=  f
		END
	END
END InsertPage;

PROCEDURE RemovePage(F: NoteBook; f: Display.Frame);
VAR t, t0: Display.Frame;
BEGIN
	IF f # NIL THEN
		t := F.pages; t0 := NIL; 
		WHILE (t # NIL) & (t # f) DO t0 := t; t := t.next END;
		IF t = f THEN
			IF t0 # NIL THEN t0.next := f.next
			ELSE F.pages := f.next
			END
		END
	END;
	f.next := NIL
END RemovePage;

PROCEDURE LocatePage(F: NoteBook; type: ARRAY OF CHAR): Display.Frame;
VAR f, f0: Display.Frame; s: ARRAY 64 OF CHAR;
BEGIN
	f := F.pages; f0 := NIL;
	LOOP
		IF f = NIL THEN EXIT END;
		IF type = "Next" THEN
			IF f = F.dsc THEN RETURN f.next END
		ELSIF type = "Previous" THEN
			IF f = F.dsc THEN RETURN f0 END
		ELSIF type = "First" THEN RETURN f 
		ELSIF type = "Last" THEN
			IF f.next = NIL THEN RETURN f END
		ELSE (* name compare *)
			Gadgets.GetObjName(f, s);
			IF s = type THEN RETURN f END
		END;
		f0 := f; f := f.next
	END;
	RETURN NIL
END LocatePage;

PROCEDURE HandleSelect(F: NoteBook; VAR M: Oberon.InputMsg);
VAR S: Display.SelectMsg; f: Gadgets.Frame; keysum: SET; newpage: Display.Frame;
	C: Objects.CopyMsg;
BEGIN
	f := F.dsc(Gadgets.Frame);
	IF Gadgets.selected IN f.state THEN S.id := Display.reset ELSE S.id := Display.set END;
	S.F := f; S.res := -1; S.dlink := NIL; S.x := 0; S.y := 0; Objects.Stamp(S); f.handle(f, S);
	
	Gadgets.Update(f); keysum := M.keys;
	REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys; UNTIL M.keys = {};
	M.res := 0;
	
	IF (keysum = {0, 2}) & (S.id = Display.set) THEN (* RL delete selection *)
		Oberon.FadeCursor(Oberon.Mouse);
		newpage := LocatePage(F, "Previous");
		IF newpage = NIL THEN newpage := LocatePage(F, "First") END;
		IF newpage # F.dsc THEN RemovePage(F, F.dsc); GotoPage(F, newpage)
		ELSE RemovePage(F, F.dsc);  GotoPage(F, NIL)
		END
	ELSIF (keysum = {0, 1}) & (S.id = Display.set) THEN  (* RM copy to focus *)
		C.id := Objects.shallow; C.obj := NIL; Objects.Stamp(C); F.dsc.handle(F.dsc, C);
		IF C.obj # NIL THEN Gadgets.Integrate(C.obj) END
	ELSE F.time := Oberon.Time()
	END
END HandleSelect;

PROCEDURE Edit(F: NoteBook; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
VAR newpage: Display.Frame; s: ARRAY 2 OF CHAR; keysum: SET; R: Display3.Mask;
BEGIN
	IF M.keys = {1} THEN
		IF Effects.Inside(M.X, M.Y, x + border, y + h - Fonts.Default.height, 6, Fonts.Default.height) THEN (* prev *)
			Gadgets.MakeMask(F, x, y, M.dlink, R); Oberon.FadeCursor(Oberon.Mouse);
			
			s[0] := CHR(31); s[1] := 0X;
			Display3.String(R, Display.FG, x + border, y + h - Fonts.Default.height, Fonts.Default, s, Display.invert);
			
			keysum := M.keys;
			REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys; UNTIL M.keys = {};
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.String(R, Display.FG, x + border, y + h - Fonts.Default.height, Fonts.Default, s, Display.invert);

			IF keysum = {1} THEN
				newpage := LocatePage(F, "Previous");
				IF newpage = NIL THEN newpage := LocatePage(F, "First") END;
				GotoPage(F, newpage)
			END;
			M.res := 0
		ELSIF Effects.Inside(M.X, M.Y, x + border + 8, y + h - Fonts.Default.height, 6, Fonts.Default.height) THEN (* next *)
			Gadgets.MakeMask(F, x, y, M.dlink, R); Oberon.FadeCursor(Oberon.Mouse);
			
			s[0] := CHR(27); s[1] := 0X;
			Display3.String(R, Display.FG, x + border + 8, y + h - Fonts.Default.height, Fonts.Default, s, Display.invert);
			
			keysum := M.keys;
			REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys; UNTIL M.keys = {};
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.String(R, Display.FG, x + border + 8, y + h - Fonts.Default.height, Fonts.Default, s, Display.invert);

			IF keysum = {1} THEN
				newpage := LocatePage(F, "Next");
				IF newpage = NIL THEN newpage := LocatePage(F, "Last") END;
				GotoPage(F, newpage)
			END;
			M.res := 0
		END
	END;
END Edit;

PROCEDURE Neutralize(F: NoteBook);
VAR S: Display.SelectMsg; f: Gadgets.Frame;
BEGIN
	IF F.dsc # NIL THEN
		f := F.dsc(Gadgets.Frame);
		IF Gadgets.selected IN f.state THEN
			S.id := Display.reset;
			S.F := f; S.res := -1; S.dlink := NIL; S.x := 0; S.y := 0; Objects.Stamp(S); f.handle(f, S);
			Gadgets.Update(f);
		END
	END
END Neutralize;

PROCEDURE ConsumeMsg(F: NoteBook; x, y, w, h: INTEGER; VAR M: Display.ConsumeMsg);
VAR C: Display.ControlMsg; ok: BOOLEAN; obj: Objects.Object; G, lastobj: Gadgets.Frame;
BEGIN
	ok := TRUE; obj := M.obj;
	WHILE (obj # NIL) & ok DO
		IF Gadgets.Recursive(F, obj) THEN Out.String("Not allowed, will cause recursive structures"); Out.Ln; ok := FALSE;
		ELSIF (F.lib # NIL) & (obj.lib # NIL) & (F.lib # obj.lib) & (obj.lib.name # "") THEN
			Out.String("Across library movement not allowed"); Out.Ln; ok := FALSE
		ELSIF ~(obj IS Gadgets.Frame) THEN Out.String("Only gadgets allowed"); Out.Ln; ok := FALSE
		ELSIF Gadgets.transparent IN obj(Gadgets.Frame).state THEN Out.String("No transparent gadgets allowed"); Out.Ln; ok := FALSE
		END;
		obj := obj.slink
	END;
	IF ok THEN
		C.id := Display.remove; C.F := M.obj(Display.Frame); Display.Broadcast(C); (* remove whole list *)
		
		obj := M.obj;
		WHILE obj # NIL DO
			G := obj(Gadgets.Frame);
			IF Gadgets.lockedsize IN G.state THEN (* create a view *)
				G := Views.ViewOf(G)
			END;
			lastobj := G; InsertPage(F, G); obj := obj.slink
		END;
		GotoPage(F, lastobj)
	END;
	M.res := 0
END ConsumeMsg;

PROCEDURE Copy*(VAR M: Objects.CopyMsg; from, to: NoteBook);
VAR C: Objects.CopyMsg;
BEGIN
	Gadgets.CopyFrame(M, from, to);
	IF from.dsc # NIL THEN C.id := Objects.shallow; Objects.Stamp(C); from.dsc.handle(from.dsc, C);
		to.dsc := C.obj(Gadgets.Frame)
	ELSE to.dsc := NIL
	END;
END Copy;

PROCEDURE Attr(F: NoteBook; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.s := "NoteBooks.New"; M.class := Objects.String; M.res := 0
		ELSIF M.name = "Locked" THEN M.class := Objects.Bool; M.b := Gadgets.lockedcontents IN F.state; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Locked" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN F.state := F.state + {Gadgets.lockedcontents, Gadgets.lockedsize};
				ELSE F.state := F.state - {Gadgets.lockedcontents, Gadgets.lockedsize} END;
				M.res := 0
			END
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Locked"); Gadgets.framehandle(F, M)
	END
END Attr;

PROCEDURE Handler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h: INTEGER; F0: NoteBook; R: Display3.Mask;
	f: Display.Frame; ver: LONGINT; obj: Objects.Object;  
BEGIN
	WITH F: NoteBook DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN	(* message addressed to this frame *)
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate display coordinates *)
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Restore(F, R, x, y, w, h, M)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									Restore(F, R, x, y, w, h, M)
								END
							ELSIF M.device = Display.printer THEN Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & ~(Gadgets.selected IN F.state) THEN
								IF (F.dsc # NIL) & Effects.Inside(M.X, M.Y, x + border, y + border, F.dsc.W, F.dsc.H) THEN
									ToMain(F, x, y, M);
									IF (M.res < 0) & (M.keys = {0}) THEN HandleSelect(F, M) (* select *) END;
								ELSIF Gadgets.InActiveArea(F, M) THEN Edit(F, x, y, w, h, M);
								ELSE Gadgets.framehandle(F, M)
								END
							ELSIF ~(Gadgets.selected IN F.state) THEN ToMain(F, x, y, M)
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Display.ModifyMsg THEN Adjust(F, M(Display.ModifyMsg))
					ELSIF M IS Display.LocateMsg THEN
						WITH M: Display.LocateMsg DO
							IF (M.loc = NIL) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN
								ToMain(F, x, y, M);
								IF M.loc = NIL THEN M.loc := F; M.u := M.X - x; M.v := M.Y - (y + h - 1); M.res := 0 END;
							END
						END
					ELSIF M IS Display.ConsumeMsg THEN
						WITH M: Display.ConsumeMsg DO
							IF (M.id = Display.drop) & (M.F = F) & ~(Gadgets.lockedcontents IN F.state) THEN ConsumeMsg(F, x, y, w, h, M)
							ELSE ToMain(F, x, y, M) (* child may want to consume *)
							END
						END
					ELSIF M IS Display3.OverlapMsg THEN
						WITH M: Display3.OverlapMsg DO F.mask := M.M; SetMainMask(F) END
					ELSIF M IS Oberon.ControlMsg THEN
						WITH M: Oberon.ControlMsg DO
							ToMain(F, x, y, M);
							IF M.id = Oberon.neutralize THEN Neutralize(F) END
						END
					ELSIF M IS Display.SelectMsg THEN
						WITH M: Display.SelectMsg DO
							IF M.id = Display.get THEN
								ToMain(F, x, y, M);
								IF (F.time > M.time) & (F.dsc # NIL) & (Gadgets.selected IN F.dsc(Gadgets.Frame).state) THEN
									M.time := F.time; M.obj := F.dsc; M.sel := F;
								END;
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Gadgets.UpdateMsg THEN
						WITH M: Gadgets.UpdateMsg DO
							IF M.obj = F.dsc THEN
								ToMain(F, x, y, M);
								Gadgets.MakeMask(F, x, y, M.dlink, R); UpdateTitle(F, R, x, y, w, h)
							ELSIF M.obj = F THEN Gadgets.framehandle(F, M)
							ELSE ToMain(F, x, y, M)
							END
						END
					ELSIF M IS PageMsg THEN
						WITH M: PageMsg DO
							IF M.F = F THEN HandlePageMsg(F, x, y, w, h, M)
							ELSE ToMain(F, x, y, M)
							END
						END
					ELSIF M.F # NIL THEN Gadgets.framehandle(F, M) 
					ELSE ToMain(F, x, y, M)
					END
				ELSE (* not for this frame but perhaps for a child *)	
					IF M IS Display3.UpdateMaskMsg THEN
						WITH M: Display3.UpdateMaskMsg DO
							IF M.F = F.dsc THEN SetMainMask(F)
							ELSE ToMain(F, M.x + F.X, M.y + F.Y, M)
							END
						END
					ELSIF M IS Display.ControlMsg THEN
						WITH M: Display.ControlMsg DO
							IF (M.id = Display.remove) & (M.F = F.dsc) THEN
								f := LocatePage(F, "Previous");
								IF f = NIL THEN RemovePage(F, F.dsc);
									f := LocatePage(F, "First"); GotoPage(F, f)
								ELSE
									RemovePage(F, F.dsc); GotoPage(F, f)
								END
							ELSE ToMain(F, M.x + F.X, M.y + F.Y, M) END
						END
					ELSIF M IS Display.ModifyMsg THEN
						IF M.F = F.dsc THEN AdjustChild(F, M(Display.ModifyMsg))
						ELSE ToMain(F, M.x + F.X, M.y + F.Y, M)
						END
					ELSE ToMain(F, M.x + F.X, M.y + F.Y, M)
					END
				END
			END
		(* Object messages *)
		ELSIF M IS Objects.AttrMsg THEN Attr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.BindMsg THEN
			Gadgets.framehandle(F, M);
			f := F.pages; WHILE f # NIL DO f.handle(f, M); f := f.next END (* also bind all children *)
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteNum(M.R, 1);
					Gadgets.WriteRef(M.R, F.lib, F.dsc);
					f := F.pages; x := 0; WHILE f # NIL DO INC(x); f := f.next END; (* count the pages *)
					Files.WriteInt(M.R, x); (* write the count *)
					f := F.pages; x := 0; WHILE f # NIL DO Gadgets.WriteRef(M.R, F.lib, f); f := f.next END;
					Gadgets.framehandle(F, M);
				ELSIF M.id = Objects.load THEN
					Files.ReadNum(M.R, ver); IF ver # 1 THEN HALT(99) END;
					Gadgets.ReadRef(M.R, F.lib, obj);
					IF (obj # NIL) & (obj IS Display.Frame) THEN F.dsc := obj(Display.Frame) ELSE F.dsc := NIL END;
					Files.ReadInt(M.R, x); F.pages := NIL;
					WHILE x > 0 DO
						Gadgets.ReadRef(M.R, F.lib, obj);
						IF (obj # NIL) & (obj IS Display.Frame) THEN InsertPage(F, obj(Display.Frame))
						ELSE Out.String(" discarding page"); Out.Ln
						END;
						DEC(x)
					END;
					IF (F.dsc = NIL) & (F.pages # NIL) THEN F.dsc := F.pages END;
					Gadgets.framehandle(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink (* copy msg arrives again *)
				ELSE (* first time copy message arrives *)
					NEW(F0); F.stamp := M.stamp; F.dlink := F0; Copy(M, F, F0); M.obj := F0
				END
			END
		ELSE	(* unknown msg, framehandler might know it *)
			Gadgets.framehandle(F, M)
		END
	END
END Handler;

PROCEDURE InitNoteBook*(F: NoteBook);
BEGIN F.handle := Handler; F.W := 100; F.H := 100
END InitNoteBook;

PROCEDURE New*;
VAR F: NoteBook;
BEGIN NEW(F); InitNoteBook(F); Objects.NewObj := F;
END New;

(* Show a new page. The following verbs are allowed: "First", "Last", "Next", "Previous", a page name.
The following is accepted by the command:
	NoteBooks.Show "Previous" ~ 			Move to the indicated page in the current notebook
	NoteBooks.Show notebookname "Next"  ~	Move to the indicated page in the named notebook
*)
PROCEDURE Show*;
VAR S: Attributes.Scanner; bookname, where: ARRAY 64 OF CHAR; obj: Objects.Object; f: Display.Frame;
BEGIN
	where := ""; bookname := "";
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF S.class = Attributes.String THEN (* where *)
		COPY(S.s, where)
	ELSIF S.class = Attributes.Name THEN (* book name *)
		COPY(S.s, bookname);
		Attributes.Scan(S);
		IF S.class = Attributes.String THEN (* where *)
			COPY(S.s, where)
		END
	END;
	IF where # "" THEN (* found something *)
		IF bookname # "" THEN (* search for a definite book *)
			obj := Gadgets.FindObj(Gadgets.context, bookname)
		ELSE (* current book *)
			obj := Gadgets.context;
			WHILE (obj # NIL) & ~(obj IS NoteBook) DO obj := obj.dlink END;
		END;
		IF (obj # NIL) & (obj IS NoteBook) THEN
			f := LocatePage(obj(NoteBook), where);
			IF f = NIL THEN
				IF where = "Next" THEN f := LocatePage(obj(NoteBook), "Last")
				ELSIF where = "Previous" THEN  f := LocatePage(obj(NoteBook), "First")
				END
			END;
			IF f # NIL THEN GotoPage(obj(NoteBook), f) END
		ELSE Out.String(" [NoteBook not found]"); Out.Ln
		END
	END
END Show;

END NoteBooks.

Gadgets.Insert NoteBooks.New ~

NoteBooks.Show "Previous" ~ Current notebook
NoteBooks.Show notebookname "Next"  ~

System.Free NoteBooks
