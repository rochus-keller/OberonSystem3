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

MODULE RefGadgets;	(** portable *)  (** PS   *)

(** Gadget providing drag and drop facilities. *)

(*
	27.6.96 - added Create command (thanks eos)
*)

IMPORT Files, Display, Display3, Printer, Printer3, Effects, Objects, Attributes, Texts, Gadgets, Oberon;

TYPE
	Reference* = POINTER TO ReferenceDesc;
	ReferenceDesc* = RECORD (Gadgets.ObjDesc)
		val*: Objects.Object
	END;

	Frame* = POINTER TO FrameDesc;
	FrameDesc* = RECORD (Gadgets.FrameDesc)
		val*: Objects.Object;
		locked*: BOOLEAN;	(** refuse drops & copy over nor allow delete *)
		canDrag*: BOOLEAN	(** allow dragging *)
	END;

VAR
	W: Texts.Writer;

(* Appends current content of writer to the Oberon log *)
PROCEDURE ToLog;
BEGIN Texts.Append(Oberon.Log, W.buf);
END ToLog;


	(* ------------------------	model stuff	------------------------ *)

(* Copies a Reference-Object *)
PROCEDURE CopyReference*(VAR M: Objects.CopyMsg; from, to: Reference);
BEGIN Gadgets.CopyObject(M, from, to); to.val:= from.val
END CopyReference;

PROCEDURE ReferenceHandler*(obj: Objects.Object; VAR M: Objects.ObjMsg);
	VAR obj2: Reference;
BEGIN
	WITH obj: Reference DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN
					COPY("RefGadgets.NewReference", M.s); M.class := Objects.String; M.res := 0
				ELSE Gadgets.objecthandle(obj, M)
				END
			END
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Value" THEN M.obj:= obj.val; M.res:= 0
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.set THEN
					IF M.name = "Value" THEN obj.val:= M.obj; M.res:= 0
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.enum THEN
					M.Enum("Value"); Gadgets.objecthandle(obj, M)
				END
			END
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Gadgets.WriteRef(M.R, obj.lib, obj.val);
					Gadgets.objecthandle(obj, M)
				ELSIF M.id = Objects.load THEN
					Gadgets.ReadRef(M.R, obj.lib, obj.val);
					Gadgets.objecthandle(obj, M)
				END
			END;
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = obj.stamp THEN M.obj := obj.dlink
				ELSE NEW(obj2); obj.stamp := M.stamp; obj.dlink := obj2; CopyReference(M, obj, obj2); M.obj := obj2
				END
			END
		ELSIF M IS Objects.BindMsg THEN
			Gadgets.objecthandle(obj, M);
			IF obj.val # NIL THEN obj.val.handle(obj.val, M) END
		ELSE
			Gadgets.objecthandle(obj, M)
		END
	END
END ReferenceHandler;

PROCEDURE InitReference*(obj: Reference);
BEGIN obj.handle := ReferenceHandler; obj.val:= NIL
END InitReference;

PROCEDURE NewReference*;
VAR obj: Reference;
BEGIN NEW(obj); InitReference(obj); Objects.NewObj := obj;
END NewReference;


	(* ------------------------	frame stuff	------------------------ *)

(* sets 'Frame's model to same value *)
PROCEDURE SetFrameModel(F: Frame);
BEGIN IF (F.obj # NIL) & (F.obj IS Reference) THEN F.obj(Reference).val:= F.val END
END SetFrameModel;

(* sets 'Frame's value to model's value *)
PROCEDURE UpdateFrameModel(F: Frame);
BEGIN IF (F.obj # NIL) & (F.obj IS Reference) THEN F.val:= F.obj(Reference).val END
END UpdateFrameModel;

(* Handles attributes of 'Frame'. Memory for attributes 'Cmd' and 'ConsumeCmd' is allocated when needed
	(by Gdagtes default handler). They will be simulated if none really exists. *)
PROCEDURE FrameAttrs(F: Frame; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN
			M.class := Objects.String; COPY("RefGadgets.NewFrame", M.s); M.res := 0
		ELSIF M.name = "LineupHY" THEN (* makes it appear better in texts *)
			M.class := Objects.Int; M.i := F.H DIV 2 - 5; M.res := 0
		ELSIF M.name = "Cmd" THEN
			Gadgets.framehandle(F, M);
			IF M.res < 0 THEN (* no such attribute, simulate one *)
				M.class := Objects.String; M.s := ""; M.res := 0
			END
		ELSIF M.name = "ConsumeCmd" THEN
			Gadgets.framehandle(F, M);
			IF M.res < 0 THEN (* no such attribute, simulate one *)
				M.class := Objects.String; M.s := ""; M.res := 0
			END
		ELSIF M.name = "Locked" THEN
			M.class:= Objects.Bool; M.b:= F.locked; M.res:= 0
		ELSIF M.name = "Drag" THEN
			M.class:= Objects.Bool; M.b:= F.canDrag; M.res:= 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN 
		IF M.name = "Drag" THEN
			IF M.class = Objects.Bool THEN
				F.canDrag:= M.b; M.res:= 0
			END
		ELSIF M.name = "Locked" THEN
			IF M.class = Objects.Bool THEN
				F.locked:= M.b; M.res:= 0
			END
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Cmd"); M.Enum("ConsumeCmd"); M.Enum("Locked"); M.Enum("Drag");
		Gadgets.framehandle(F, M)
	END
END FrameAttrs;

(* Handles links of 'Frame'. *)
PROCEDURE FrameLinks(F: Frame; VAR M: Objects.LinkMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Value" THEN M.obj:= F.val; M.res:= 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF  M.id = Objects.set THEN
		IF M.name = "Value" THEN
			F.val:= M.obj; M.res:= 0;
			IF F.obj # NIL THEN SetFrameModel(F); Gadgets.Update(F.obj) END
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Value"); Gadgets.framehandle(F, M)
	END
END FrameLinks;

(* Draws a 'Frame' gadget. Switch 'pressed' indicates the gadget's state *)
PROCEDURE Restore (F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER; pressed: BOOLEAN);
	VAR x0, y0, r, r0: INTEGER;
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	Display3.FilledRect3D(Q, Display3.bottomC, Display3.topC, Display3.textbackC, x, y, w, h, 1, Display.replace);
	IF w < h THEN r:= w ELSE r:= h END; r0:= (r - 8) DIV 2;
	IF F.val # NIL THEN
		IF pressed THEN x0:= 1; y0:= -1;
			Display3.FilledRect3D(Q, Display3.downC, Display3.upC, Display3.upC, x+3, y+3, w-6, h-6, 1, Display.replace)
		ELSE x0:= 0; y0:= 0;
			Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.upC, x+3, y+3, w-6, h-6, 1, Display.replace)
		END;

		(* Draw a rectangle if model is of type 'Display.Frame', a filled rectangle if it is of type 'Gadgets.Frame'.
			If model is of type 'Gadgets.Object' draw a filled circle, in all other cases an empty circle *)
		IF F.val IS Display.Frame THEN
			INC(x0, x+((w-r0+1) DIV 2)); INC(y0, y+((h-r0+1) DIV 2));
			Display3.ReplConst(Q, Display3.black, x0, y0, r0, r0, Display.replace)
		ELSE
			INC(x0, x+((w+1) DIV 2)); INC(y0, y+((h+1) DIV 2)); r0:= r0 DIV 2;
			Display3.Circle(Q, Display3.black, Display.solid, x0, y0, r0, 1, {Display3.filled}, Display.replace)
		END
	ELSE
		x0:= x+((w-r0+1) DIV 2); y0:= y+((h-r0+1) DIV 2); DEC(r0);
		Display3.Line(Q, Display3.black, Display.solid, x0, y0, x0+r0, y0+r0, 2, Display.replace);
		Display3.Line(Q, Display3.black, Display.solid, x0, y0+r0, x0+r0, y0, 2, Display.replace)
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END Restore;

(* Prints a 'Frame' gadget *)
PROCEDURE Print (F: Frame; VAR M: Display.DisplayMsg);
	VAR Q: Display3.Mask; x, y, w, h, r, x0, y0, r0: INTEGER;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	x:= M.x; y:= M.y; w:= P(F.W); h:= P(F.H);
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, Q);
	Printer3.FilledRect3D(Q, Display3.bottomC, Display3.topC, Display3.textbackC, x, y, w, h, 1, Display.replace);
	IF w < h THEN r:= w ELSE r:= h END; r0:= (r - P(8)) DIV 2;
	IF F.val # NIL THEN
		Printer3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.upC,
											x+P(3), y+P(3), w-P(6), h-P(6), 1, Display.replace);

		IF F.val IS Display.Frame THEN
			x0:= x+((w-r0+1) DIV 2); y0:= y+((h-r0+1) DIV 2);
			Printer3.ReplConst(Q, Display3.black, x0, y0, r0, r0, Display.replace)
		ELSE
			x0:= x+((w+1) DIV 2); y0:= y+((h+1) DIV 2); r0:= r0 DIV 2;
			Printer3.Circle(Q, Display3.black, Display.solid, x0, y0, r0, 1, {Display3.filled}, Display.replace)
		END
	ELSE
		x0:= x+((w-r0+1) DIV 2); y0:= y+((h-r0+1) DIV 2); DEC(r0);
		Printer3.Line(Q, Display3.black, Display.solid, x0, y0, x0+r0, y0+r0, P(2), Display.replace);
		Printer3.Line(Q, Display3.black, Display.solid, x0, y0+r0, x0+r0, y0, P(2), Display.replace)
	END
END Print;

(* Drops model to frame at point (X, Y). If model is of type 'Display.Frame' a 'ConsumeMsg' with id set to 'drop'
	is sent, otherwise a 'LinkMsg' is sent to frame *)
PROCEDURE DropObject(obj: Objects.Object; X, Y: INTEGER; copy: BOOLEAN);
	VAR F: Display.Frame; C: Objects.CopyMsg; D: Display.ConsumeMsg;
			L: Objects.LinkMsg;
BEGIN
	IF obj #NIL THEN obj.slink:= NIL;
		IF copy THEN C.id:= Objects.shallow; Objects.Stamp(C); obj.handle(obj, C); obj:= C.obj END;
		Gadgets.ThisFrame(X, Y, F, D.u, D.v);
		IF F # NIL THEN
			IF (F IS Frame) OR (obj IS Display.Frame) THEN
				D.id:= Display.drop; D.obj:= obj; D.F:= F; D.res:= -1; Display.Broadcast(D);
				IF D.res < 0 THEN
					Texts.WriteString(W, "[Could not drop frame]"); Texts.WriteLn(W); ToLog
				END
			ELSE
				L.id:= Objects.set; L.name:= "Model"; L.obj:= obj; L.res:= -1; F.handle(F, L);
				Gadgets.Update(obj);
				IF L.res < 0 THEN
					Texts.WriteString(W, "[Could not set object as model]"); Texts.WriteLn(W); ToLog
				END
			END
		END
	END
END DropObject;

(* Tracks mouse if right button was pressed entering frame handler. 
	Allows to delete current value (right, left) or integrate a copy of the value (right, middle). *) 
PROCEDURE TrackRight(F: Frame; VAR M: Oberon.InputMsg);
	VAR Q: Display3.Mask; x, y, w, h: INTEGER; keysum: SET; C:Objects.CopyMsg;
BEGIN
	x:= M.x+F.X; y:= M.y+F.Y; w:= F.W; h:= F.H;
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	Oberon.RemoveMarks(x, y, w, h);
	Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x+4, y+4, w-8, h-8, Display.paint);
	keysum := M.keys;
	REPEAT
		Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	Restore(F, Q, x, y, w, h, FALSE);
	IF (keysum = {0,2}) & ~F.locked THEN (* delete value *)
		F.val:= NIL;
		IF F.obj # NIL THEN SetFrameModel(F); Gadgets.Update(F.obj)
		ELSE Gadgets.Update(F)
		END;
		Gadgets.ExecuteAttr(F, "ConsumeCmd", M.dlink, NIL, F);
	ELSIF (keysum = {0, 1}) & (F.val IS Display.Frame) & F.canDrag THEN (* integrate copy of value *)
		C.id:= Objects.shallow; Objects.Stamp(C); F.val.handle(F.val, C);
		Gadgets.Integrate(C.obj)
	END;
	M.res:= 0
END TrackRight;

(* Tracks mouse if middle button was pressed entering frame handler. 
	Allows to execute attibute 'Cmd' or drag and drop value (middle, left) or a copy (middle, right). *) 
PROCEDURE TrackMiddle(F: Frame; VAR M: Oberon.InputMsg);
	VAR Q: Display3.Mask; x, y, w, h, r, s: INTEGER; keysum: SET; in, drag: BOOLEAN; cursor: Oberon.Marker;
BEGIN
	x:= M.x+F.X; y:= M.y+F.Y; w:= F.W; h:= F.H; r:= x+w-1; s:= y+h-1;
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	Oberon.RemoveMarks(x, y, w, h); Restore(F, Q, x, y, w, h, TRUE);
	keysum := M.keys;
	in := TRUE; drag:= FALSE; cursor:= Effects.Arrow;
	REPEAT
		Effects.TrackMouse(M.keys, M.X, M.Y, cursor);
		keysum := keysum + M.keys;
		IF ((M.keys = {0,1}) OR (M.keys = {1, 2})) & ~drag &F.canDrag THEN
			drag:= TRUE; IF 0 IN M.keys THEN cursor:= Effects.CopyHand ELSE cursor:= Effects.MoveHand END
		ELSIF (keysum = {0, 1, 2}) & drag THEN cursor:= Effects.Arrow
		END;
		IF in & ((M.X < x) OR (M.Y < y) OR (M.X > r) OR (M.Y > s) OR drag) THEN (* mouse leaves frame or dragging *)
			in:= FALSE; Oberon.RemoveMarks(x, y, w, h); Restore(F, Q, x, y, w, h, FALSE)
		ELSIF ~in & (M.X >= x) & (M.Y >= y) & (M.X <= r) & (M.Y <= s) & ~drag THEN (* mouse enters frame *)
			in:= TRUE; Oberon.RemoveMarks(x, y, w, h); Restore(F, Q, x, y, w, h, TRUE)
		END
	UNTIL M.keys = {};
	Restore(F, Q, x, y, w, h, FALSE);
	IF ~in & ~drag THEN keysum:= {} END;
	IF keysum = {1} THEN Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL)
	ELSIF (keysum # {0, 1, 2}) & drag THEN DropObject(F.val, M.X, M.Y, (0 IN keysum))
	END;
	M.res := 0
END TrackMiddle;

(* Tracks mouse if left button was pressed entering frame handler. 
	Allows to copy over an object to be set as new value (left, middle). If succeeded
	executes attribute 'ConsumeCmd'. *) 
PROCEDURE TrackLeft(F: Frame; VAR M: Oberon.InputMsg);
	VAR Q: Display3.Mask; obj: Objects.Object; time: LONGINT; x, y, w, h: INTEGER; keysum: SET;
BEGIN
	x:= M.x+F.X; y:= M.y+F.Y; w:= F.W; h:= F.H;
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	Oberon.RemoveMarks(x, y, w, h);
	Display3.FilledRect3D(Q, Display3.bottomC, Display3.topC, Display3.textbackC, x, y, w, h, 1, Display.replace);
	keysum := M.keys;
	REPEAT
		Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	Restore(F, Q, x, y, w, h, FALSE);
	IF (keysum = {1,2}) & ~F.locked THEN (* copy over selected frame to value *)
		Gadgets.GetSelection(obj, time);
		IF (time > 0) & (obj #NIL) THEN F.val:= obj; 
			IF F.obj #NIL THEN SetFrameModel(F); Gadgets.Update(F.obj)
			ELSE Gadgets.Update(F)
			END;
			Gadgets.ExecuteAttr(F, "ConsumeCmd", M.dlink, obj, F)
		END
	END;
	M.res:= 0
END TrackLeft;

PROCEDURE CopyFrame* (VAR M: Objects.CopyMsg; from, to: Frame);
BEGIN
	Gadgets.CopyFrame(M, from, to);
	to.locked:= from.locked; to.canDrag:= from.canDrag; to.val:= from. val
END CopyFrame;

PROCEDURE FrameHandle* (F: Objects.Object; VAR M: Objects.ObjMsg);
	VAR x, y, w, h: INTEGER; F1: Frame; Q: Display3.Mask;
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
									Restore(F, Q, x, y, w, h, FALSE)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									Display3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
									Restore(F, Q, x, y, w, h, FALSE)
								END
							ELSIF M.id = Display.printer THEN Print(F, M)
							END
						END	(* WITH Display.DisplayMsg *)
					ELSIF M IS Gadgets.UpdateMsg THEN
						WITH M: Gadgets.UpdateMsg  DO
							IF F.obj # NIL THEN F.obj.handle(F.obj, M) END;
							IF M.obj = F.obj THEN
								IF M.stamp # F.stamp THEN F.stamp := M.stamp; UpdateFrameModel(F) END;
								Gadgets.MakeMask(F, x, y, M.dlink, Q);
								Restore(F, Q, x, y, w, h, FALSE)
							ELSE Gadgets.framehandle(F, M)
							END
						END	(* WITH Gadgets.UpdateMsg *)
					ELSIF M IS Display.ControlMsg THEN 
						WITH M: Display.ControlMsg DO
							IF F.obj # NIL THEN F.obj.handle(F.obj, M) END;
							IF (M.id = Display.restore) & (M.stamp # F.stamp) THEN F.stamp := M.stamp; UpdateFrameModel(F) END
						END	(* WITH Display.ControlMsg *)
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF M.id = Oberon.track THEN
								IF Gadgets.InActiveArea(F, M) & (M.keys = {1}) THEN
									IF F.val # NIL THEN TrackMiddle(F, M)
									ELSE
										REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow) UNTIL M.keys = {};
										M.res:= 0
									END
								ELSIF ~(Gadgets.selected IN F.state) & ~Effects.InBorder(M.X, M.Y, x, y, w, h) & (M.keys = {0}) THEN
									IF F.val # NIL THEN TrackRight(F, M)
									ELSE Gadgets.framehandle(F, M)
									END
								ELSIF ~(Gadgets.selected IN F.state) & ~Effects.InBorder(M.X, M.Y, x, y, w, h) & (M.keys = {2}) THEN
									TrackLeft(F, M)
								END
							ELSE Gadgets.framehandle(F, M)
							END
						END	(* WITH Oberon.InputMsg *)
					ELSIF M IS Display.ModifyMsg THEN Gadgets.framehandle(F, M)
					ELSIF M IS Oberon.ControlMsg THEN Gadgets.framehandle(F, M)
					ELSIF M IS Display.SelectMsg THEN Gadgets.framehandle(F, M)
					ELSIF M IS Display.ConsumeMsg THEN
						WITH M: Display.ConsumeMsg DO
							IF (M.id = Display.drop) & ~F.locked THEN
								F.val:= M.obj; F.val.slink:= NIL; M.res:= 0;
								IF F.obj # NIL THEN SetFrameModel(F); Gadgets.Update(F.obj)
								ELSE Gadgets.Update(F)
								END;
								Gadgets.ExecuteAttr(F, "ConsumeCmd", M.dlink, M.obj, F)
							ELSE Gadgets.framehandle(F, M)
							END
						END	(* WITH Display.ConsumeMsg *)
					ELSE Gadgets.framehandle(F, M)
					END
				END	(* IF message addressed to box *)
			END	(* WITH Display.FrameMsg *)
		ELSIF M IS Objects.AttrMsg THEN FrameAttrs(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.LinkMsg THEN FrameLinks(F, M(Objects.LinkMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteBool(M.R, F.locked); Files.WriteBool(M.R, F.canDrag);
					Gadgets.WriteRef(M.R, F.lib, F.val);
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN
					Files.ReadBool(M.R, F.locked); Files.ReadBool(M.R, F.canDrag);
					Gadgets.ReadRef(M.R, F.lib, F.val);
					Gadgets.framehandle(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink (* non-first arrival*)
				ELSE (* first arrival *)
					NEW(F1); F.stamp := M.stamp; F.dlink := F1;
					CopyFrame(M, F, F1); M.obj := F1
				END
			END
		ELSIF M IS Objects.BindMsg THEN
			Gadgets.framehandle(F, M);
			IF F.val #NIL THEN F.val.handle(F.val, M) END
		ELSE Gadgets.framehandle(F, M)
		END
	END
END FrameHandle;

PROCEDURE InitFrame* (F: Frame);
BEGIN
	F.locked:= FALSE; F.canDrag:= TRUE; F.val:= NIL;
	F.W := 20; F.H := 20; F.handle := FrameHandle
END InitFrame;

PROCEDURE NewFrame*;
VAR F: Frame;
BEGIN NEW(F); InitFrame(F); Objects.NewObj := F
END NewFrame;

(** Used in the form: RefGadgets.Create <Generator>

	Creates a new object and set the value link of the specified RefGadget. A destination
	RefGadget is either the executor, selected or marked gadget. *)
PROCEDURE Create*;
VAR obj, ref: Objects.Object; time: LONGINT; L: Objects.LinkMsg; S: Attributes.Scanner;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
	IF S.class IN {Attributes.Name, Attributes.String} THEN
		ref := NIL;
		IF Gadgets.executorObj IS Frame THEN ref := Gadgets.executorObj
		ELSE
			Gadgets.GetSelection(ref, time);
			IF (ref = NIL) OR ~(ref IS Frame) THEN
				IF Oberon.Pointer.on THEN
					ref := Oberon.MarkedFrame();
					IF (ref = NIL) OR ~(ref IS Frame) THEN
						ref := NIL
					END
				ELSE ref := NIL
				END
			END
		END;
		IF ref # NIL THEN
			obj := Gadgets.CreateObject(S.s);
			IF obj # NIL THEN
				L.id := Objects.set; L.name := "Value"; L.res := -1; L.obj := obj;
				ref.handle(ref, L);
				Gadgets.Update(ref)
			END
		END
	END
END Create;

BEGIN
	Texts.OpenWriter(W)
END RefGadgets.

(**
Reference
	Create with:	Gadgets.Link RefGadgets.NewReference
	Alias:	-
	Function:	Stores a reference to any object. It may be used in combination with reference frames.
	Attributes:	-
	Links:
		Value	Reference the model is representing

Frame
	Create with:	Gadgets.Insert RefGadgets.NewFrame
	Alias:	-
	Function:	This frame stores a reference to any object of type Objects.Object. A refrence frame has the ability to execute a command when clicked on. The frame distinguish three kinds of representation;  -> no object,  -> object is a visual gadget or  -> object is a model. When the reference is changed by user interaction (dropping or copy over), it also has the ability to execute a command. References can be changed either by dropping a reference from an otherreference frame, dropping a visual gadget into a frame or copy over a selected gadget. Dragging follows the standard oberon rules. If the dragged reference represents a visual gadget, a drop messgae is sent to the receiving frame. If the dragged reference represents a model, a link message with name set to 'Model' is sent to the receiving frame. The mouse cursor changes its look;  -> drop the referenced object or  -> drop a copy of the referenced object
	Attributes:	
		Cmd	Command executed when clicking on the frame.
		ConsumeCmd	Command executed when an object is dropped or copied over.
		Locked	When set, frame refuse action 'drop', 'copy over' and 'delete'.
		Drag	Allow dragging of value.
	Links:
		Value	Reference the frame is representing
*)