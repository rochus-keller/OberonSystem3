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

MODULE Navigators;	(** portable *)

(*
	7.4.94 - Allow middle key for focus too
	5.4.94 - Fixed tracking in navigators
	9.6.94 - Implemented maximum nesting level 
*)

IMPORT Display, Display3, Printer, Printer3, Effects, Objects, Gadgets, Oberon, Documents, Desktops, Views;
	
CONST MaxLevel = 3; (* maximum nesting level where the navigators still function *)
	leftpos = 0;	(*1*)
	toppos = 0;	(* -1 *)
	
TYPE
	Frame* = POINTER TO FrameDesc;
	FrameDesc* = RECORD (Gadgets.FrameDesc)
	END;
	
PROCEDURE FrameAttr(F: Frame; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("Navigators.NewNavigator", M.s); M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSE Gadgets.framehandle(F, M)
	END
END FrameAttr;

PROCEDURE Cx(F: Frame; x: LONGINT): INTEGER;
BEGIN RETURN SHORT(x * F.W DIV (Display.Width * 2))
END Cx;

PROCEDURE Cy(F: Frame; y: LONGINT): INTEGER;
BEGIN RETURN -SHORT((-y) * F.H DIV (Display.Height * 2))
END Cy;

PROCEDURE RestoreFrame(F: Frame; M: Display3.Mask; x, y, w, h: INTEGER; dlink: Objects.Object);
VAR obj: Objects.Object; f, g, v: Display.Frame; X, Y, count: INTEGER;
BEGIN
	Display3.FilledRect3D(M, Display3.FG, Display3.FG, Display3.BG, x, y, w, h, 2, Display.replace);
	
	Display3.FillPattern(M, Display3.FG, Display.grey1, x, y, x + Cx(F, Display.Width), y, 1, h, Display.paint);
	Display3.FillPattern(M, Display3.FG, Display.grey1, x, y, x, y + Cy(F, Display.Height), w, 1, Display.paint);

	obj := dlink; count := 0;
	WHILE (obj # NIL) & ~(obj IS Desktops.DocViewer) DO INC(count); obj := obj.dlink END;
	IF (obj # NIL) & (count <= MaxLevel) & ~Desktops.HasMenu(obj(Desktops.DocViewer)) THEN
		v := obj(Display.Frame).dsc.next; (* grab main frame *)
		obj := v(Gadgets.Frame).obj;
		IF (obj # NIL) & (obj IS Documents.Document) THEN
			f := obj(Documents.Document).dsc;
			IF f # NIL THEN (* main panel *)
				g := f.dsc;
				WHILE g # NIL DO
					(*IF g IS Desktops.DocGadget THEN*)
						Display3.Rect(M, Display3.FG, Display.solid, x + Cx(F, g.X), y + h - 1 + Cy(F, g.Y), Cx(F, g.W), Cy(F, g.H), 1, Display.replace);
					(*END;*)
					g := g.next
				END
			END;
			WITH v: Views.View DO
				IF v.vx = leftpos (*1*) THEN (* left *) X := 0;
				ELSE (* right *) X := Cx(F, Display.Width)
				END;
				IF v.vy = toppos(*-1*) THEN (* top *) Y := Cy(F, Display.Height);
				ELSE (* bottom *) Y := 0;
				END;
				Display3.ReplConst(M, Display3.FG, x + X, y + Y, Cx(F, Display.Width), Cy(F, Display.Height), Display.replace);
			END
		END
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreFrame;

PROCEDURE PrintFrame(F: Frame; VAR M: Display.DisplayMsg);
VAR R: Display3.Mask; x, y, w, h, count: INTEGER; obj: Objects.Object; f, g, v: Display.Frame; X, Y: INTEGER;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	x := M.x; y := M.y; w := P(F.W); h := P(F.H);
	Printer3.FilledRect3D(R, Display3.FG, Display3.FG, Display3.BG, x, y, w, h, P(2), Display.replace);
	
	Printer3.FillPattern(R, Display3.FG, Display.grey1, x, y, x + P(Cx(F, Display.Width)), y, 1, h, Display.paint);
	Printer3.FillPattern(R, Display3.FG, Display.grey1, x, y, x, y + P(Cy(F, Display.Height)), w, 1, Display.paint);

	obj := M.dlink; count := 0;
	WHILE (obj # NIL) & ~(obj IS Desktops.DocViewer) DO INC(count); obj := obj.dlink END;
	IF (obj # NIL) & (count <= MaxLevel) & ~Desktops.HasMenu(obj(Desktops.DocViewer)) THEN
		v := obj(Display.Frame).dsc.next; (* grab main frame *)
		obj := v(Gadgets.Frame).obj;
		IF (obj # NIL) & (obj IS Documents.Document) THEN
			f := obj(Documents.Document).dsc;
			IF f # NIL THEN (* main panel *)
				g := f.dsc;
				WHILE g # NIL DO
					Printer3.Rect(R, Display3.FG, Display.solid, x + P(Cx(F, g.X)), y + h - 1 + P(Cy(F, g.Y)), P(Cx(F, g.W)), P(Cy(F, g.H)), 1, Display.replace);
					g := g.next
				END
			END;
			WITH v: Views.View DO
				IF v.vx = leftpos(*1*) THEN (* left *) X := 0;
				ELSE (* right *) X := Cx(F, Display.Width)
				END;
				IF v.vy = toppos(*-1*) THEN (* top *) Y := Cy(F, Display.Height);
				ELSE (* bottom *) Y := 0;
				END;
				Printer3.ReplConst(R, Display3.FG, x + P(X), y + P(Y), P(Cx(F, Display.Width)), P(Cy(F, Display.Height)), Display.replace);
			END
		END
	END;
END PrintFrame;

PROCEDURE CopyFrame*(VAR M: Objects.CopyMsg; from, to: Frame);
BEGIN
	Gadgets.CopyFrame(M, from, to);
END CopyFrame;

PROCEDURE Focus(F: Frame; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
VAR X, Y, count: INTEGER; obj: Objects.Object;
	A: Display.ModifyMsg; keysum: SET;
BEGIN
	keysum := M.keys;
	REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.PointHand); keysum := keysum + M.keys UNTIL M.keys = {};
	IF keysum # {0, 1, 2} THEN
		Oberon.Defocus;
		IF M.X < x + Cx(F, Display.Width) THEN X := leftpos  ELSE X := -Display.Width END;
		IF M.Y < y + Cy(F, Display.Height) THEN Y := Display.Height ELSE Y := toppos END;
		
		obj := M.dlink; count := 0;
		WHILE (obj # NIL) & ~(obj IS Desktops.DocViewer) DO INC(count); obj := obj.dlink END;
		IF (obj # NIL) & (count <= MaxLevel) & ~Desktops.HasMenu(obj(Desktops.DocViewer)) THEN
			obj := obj(Display.Frame).dsc.next; (* grab main frame *)
			IF (obj # NIL) & (obj IS Views.View) THEN
				WITH obj: Views.View DO
					IF (obj.vx # X) OR (obj.vy # Y) THEN
						A.id := Display.move; A.F := F; A.mode := Display.display;
						A.X := F.X + (obj.vx - X); A.Y := F.Y + (obj.vy - Y); A.W := F.W; A.H := F.H;
						A.dX := A.X - F.X; A.dY := A.Y - F.Y; A.dW := 0; A.dH := 0;
						Display.Broadcast(A);
						obj.vx := X; obj.vy := Y;
						Gadgets.Update(obj)
					END
				END
			END
		END
	END;
	M.res := 0;
END Focus;

PROCEDURE FrameHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h: INTEGER; F0: Frame; R: Display3.Mask;
BEGIN
	WITH F: Frame DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN	(* message addressed to this frame *)
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate display coordinates *)
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									RestoreFrame(F, R, x, y, w, h, M.dlink)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreFrame(F, R, x, y, w, h, M.dlink)
								END
							ELSIF M.device = Display.printer THEN PrintFrame(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) THEN
								IF (M.keys = {2}) OR (M.keys = {1}) THEN (* focus *)
									Focus(F, x, y, w, h, M)
								ELSE Gadgets.framehandle(F, M)
								END
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
			
		(* Object messages *)
		
		ELSIF M IS Objects.AttrMsg THEN FrameAttr(F, M(Objects.AttrMsg))
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
					NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyFrame(M, F, F0); M.obj := F0
				END
			END
		ELSE	(* unknown msg, framehandler might know it *)
			Gadgets.framehandle(F, M)
		END
	END
END FrameHandler;

PROCEDURE InitNavigator*(F: Frame);
BEGIN F.W := 50; F.H := SHORT(LONG(F.W) * Display.Height DIV Display.Width); F.handle := FrameHandler
END InitNavigator;

PROCEDURE NewNavigator*;
VAR F: Frame;
BEGIN NEW(F); InitNavigator(F); Objects.NewObj := F;
END NewNavigator;

END Navigators.

System.Free Navigators ~
Gadgets.Insert Navigators.NewNavigator ~

