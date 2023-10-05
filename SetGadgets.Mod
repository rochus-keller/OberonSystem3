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

MODULE SetGadgets;	(** portable *)	(* ps -   *)

	IMPORT BIT, Files, Strings, Display, Display3, Printer, Printer3, Objects, Effects, Oberon, Gadgets;

	CONST
		SetVersion = 1;	FrameVersion = 1;

		backC = 14; setC = 15; freeC = 12;

	TYPE
		Set* = POINTER TO SetDesc;
		SetDesc* = RECORD (Gadgets.ObjDesc)
			val*: SET
		END;

		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD (Gadgets.FrameDesc)
			val*: SET
		END;

(* ------ converters ------ *)

(** Convert an integer into a set *)
PROCEDURE IntToSet* (int: LONGINT; VAR set: SET);
VAR i: SHORTINT;
BEGIN
	set := {};
	FOR i:= 0 TO 31 DO
		IF BIT.BIT(int, i) THEN INCL(set, i) END
	END
END IntToSet;

(** Convert a set into an integer *)
PROCEDURE SetToInt* (set: SET; VAR int: LONGINT);
VAR i: SHORTINT;
BEGIN
	int := 0;
	FOR i := 0 TO 31 DO
		IF i IN set THEN BIT.LSETBIT(int, i) END
	END
END SetToInt;


(** Procedures used by Set *)
PROCEDURE CopySet* (VAR M: Objects.CopyMsg; from, to: Set);
BEGIN Gadgets.CopyObject(M, from, to); to.val := from.val
END CopySet;

PROCEDURE SetHandler* (obj: Objects.Object; VAR M: Objects.ObjMsg);
VAR obj2: Set; ver: LONGINT;
BEGIN
	WITH obj: Set DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN COPY("SetGadgets.NewSet", M.s); M.class := Objects.String; M.res := 0
					ELSIF M.name = "Value" THEN SetToInt(obj.val, M.i); M.class := Objects.Int; M.res := 0
					ELSIF M.name = "String" THEN Strings.SetToStr(obj.val, M.s); M.class := Objects.String; M.res := 0
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.set THEN
					IF M.name = "Value" THEN
						IF M.class = Objects.Int THEN IntToSet(M.i, obj.val); M.res := 0
						ELSIF M.class = Objects.String THEN Strings.StrToInt(M.s, M.i); IntToSet(M.i, obj.val); M.res := 0
						END
					ELSIF M.name = "String" THEN
						IF M.class = Objects.String THEN Strings.StrToSet(M.s, obj.val); M.res := 0 END
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.enum THEN
					M.Enum("String"); M.Enum("Value"); Gadgets.objecthandle(obj, M)
				END
			END
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteNum(M.R, SetVersion); Files.WriteSet(M.R, obj.val);
					Gadgets.objecthandle(obj, M);
				ELSIF M.id = Objects.load THEN
					Files.ReadNum(M.R, ver);
					IF ver = SetVersion THEN
						Files.ReadSet(M.R, obj.val);
						Gadgets.objecthandle(obj, M)
					END
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = obj.stamp THEN M.obj := obj.dlink
				ELSE NEW(obj2); obj.stamp := M.stamp; obj.dlink := obj2; CopySet(M, obj, obj2); M.obj := obj2
				END
			END
		ELSE
			Gadgets.objecthandle(obj, M)
		END
	END
END SetHandler;

PROCEDURE InitSet* (obj: Set);
BEGIN obj.handle := SetHandler
END InitSet;

PROCEDURE NewSet*;
VAR obj: Set;
BEGIN NEW(obj); InitSet(obj); Objects.NewObj := obj;
END NewSet;


(** Procedures used by Frame *)
PROCEDURE Field (F: Frame; VAR name: ARRAY OF CHAR);
VAR A: Objects.AttrMsg;
BEGIN
	A.id := Objects.get; A.name := "Field"; A.class := Objects.Inval; A.s := "";
	F.handle(F, A);
	IF (A.res >= 0) & (A.class = Objects.String) & (A.s # "") THEN COPY(A.s, name)
	ELSE COPY("Value", name)
	END
END Field;

PROCEDURE UpdateModel (F: Frame);
VAR A: Objects.AttrMsg;
BEGIN
	IF F.obj # NIL THEN
		A.id := Objects.get; Field(F, A.name); A.class := Objects.Inval; A.res := -1;
		F.obj.handle(F.obj, A);
		IF A.res >= 0 THEN
			IF A.class = Objects.Int THEN IntToSet(A.i, F.val)
			ELSIF A.class = Objects.String THEN Strings.StrToSet(A.s, F.val)
			END
		END
	END
END UpdateModel;

PROCEDURE SetModel (F: Frame);
VAR A: Objects.AttrMsg;
BEGIN
	IF F.obj # NIL THEN
		A.id := Objects.get; Field(F, A.name); A.class := Objects.Inval; A.res := -1;
		F.obj.handle(F.obj, A);
		A.id := Objects.set; A.res := -1;
		IF A.class = Objects.String THEN Strings.SetToStr(F.val, A.s) ELSE A.class := Objects.Int; SetToInt(F.val, A.i) END;
		F.obj.handle(F.obj, A)
	END
END SetModel;

PROCEDURE HandleAttributes (F: Frame; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN
			M.class := Objects.String; COPY("SetGadgets.NewFrame", M.s); M.res := 0
		ELSIF M.name = "Value" THEN
			M.class := Objects.Int; SetToInt(F.val, M.i); M.res := 0
		ELSIF M.name = "String" THEN
			M.class := Objects.String; Strings.SetToStr(F.val, M.s); M.res := 0
		ELSIF M.name = "LineupHY" THEN M.class := Objects.Int; M.i := F.H DIV 2 - 5; M.res := 0
		ELSIF M.name = "Cmd" THEN
			Gadgets.framehandle(F, M);
			IF M.res < 0 THEN (* no such attribute, simulate one *)
				M.class := Objects.String; M.s := ""; M.res := 0
			END
		ELSIF M.name = "Field" THEN
			Gadgets.framehandle(F, M);
			IF M.res < 0 THEN (* no such attribute, simulate one *)
				M.class := Objects.String; M.s := ""; M.res := 0
			END
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Value" THEN
			IF M.class = Objects.Int THEN IntToSet(M.i, F.val); M.res := 0
			ELSIF M.class = Objects.String THEN Strings.StrToInt(M.s, M.i); IntToSet(M.i, F.val); M.res := 0
			END;
			IF F.obj # NIL THEN SetModel(F); Gadgets.Update(F.obj) END
		ELSIF M.name = "String" THEN
			IF M.class = Objects.String THEN Strings.StrToSet(M.s, F.val); M.res := 0 END;
			IF F.obj # NIL THEN SetModel(F); Gadgets.Update(F.obj) END
		ELSE Gadgets.framehandle(F, M);
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Value"); M.Enum("String"); M.Enum("Field"); M.Enum("Cmd"); Gadgets.framehandle(F, M)
	END
END HandleAttributes;

PROCEDURE Restore (F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER);
VAR sw, i, xx: INTEGER;
BEGIN
	Display3.FilledRect3D(Q, Display3.bottomC, Display3.topC, backC, x, y, w, h, 1, Display.replace);
	sw := (w - 2) DIV 32; xx := x + (w - 32*sw) DIV 2;
	FOR i := 0 TO 31 DO
		IF i IN F.val THEN Display3.ReplConst(Q, setC, xx , y+2, sw-1, h - 4, Display.replace)
		ELSE Display3.ReplConst(Q, freeC, xx , y+2, sw-1, sw-1, Display.replace)
		END;
		INC(xx, sw)
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END Restore;

PROCEDURE Print (F: Frame; VAR M: Display.DisplayMsg);
	VAR Q: Display3.Mask; i: LONGINT; x, y, w, h, sw: INTEGER;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, Q);
	Printer3.FilledRect3D(Q, Display3.bottomC, Display3.topC, backC, M.x, M.y, P(F.W), P(F.H), P(1), Display.replace);
	sw := P(F.W - 2) DIV 32;
	x := M.x + (P(F.W) - 32*sw) DIV 2; y := M.y + P(2); w := sw - P(1); h := P(F.H - 4);
	FOR i := 0 TO 31 DO
		IF i IN F.val THEN Printer3.ReplConst(Q, setC, x , y, w, h, Display.replace)
		ELSE Printer3.ReplConst(Q, freeC, x , y, w, w, Display.replace)
		END;
		INC(x, sw)
	END
END Print;

PROCEDURE TrackFrame (F: Frame; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
VAR Q: Display3.Mask; keysum: SET; pos, xPos, sw: INTEGER;
BEGIN
	sw := (w - 2) DIV 32; xPos := x + (w - 32*sw) DIV 2;
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	Oberon.RemoveMarks(x, y, w, h);
	keysum := M.keys;
	pos := (M.X - xPos) DIV sw; IF pos > 31 THEN pos := 31 ELSIF pos < 0 THEN pos := 0 END;
	xPos := xPos + pos*sw;
	Display3.ReplConst(Q, Display3.red, xPos, y + 2, sw-1, h-4, Display.replace);
	REPEAT
		Effects.TrackMouse(M.keys, M.X, M.Y, Effects.PointHand);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	Oberon.RemoveMarks(x, y, w, h);
	IF keysum = {1} THEN
		IF pos IN F.val THEN
			Display3.ReplConst(Q, backC, xPos, y + 2, sw-1, h-4, Display.replace);
			Display3.ReplConst(Q, freeC, xPos, y + 2, sw-1, sw-1, Display.replace);
			EXCL(F.val, pos)
		ELSE
			Display3.ReplConst(Q, setC, xPos, y + 2, sw-1, h-4, Display.replace);
			INCL(F.val, pos)
		END;
		Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL)
	ELSE
		IF pos IN F.val THEN
			Display3.ReplConst(Q, setC, xPos, y + 2, sw-1, h-4, Display.replace)
		ELSE
			Display3.ReplConst(Q, backC, xPos, y + 2, sw-1, h-4, Display.replace);
			Display3.ReplConst(Q, freeC, xPos, y + 2, sw-1, sw-1, Display.replace);
		END
	END;
	Gadgets.Update(F); M.res := 0
END TrackFrame;

PROCEDURE CopyFrame* (VAR M: Objects.CopyMsg; from, to: Frame);
BEGIN to.val := from.val; Gadgets.CopyFrame(M, from, to)
END CopyFrame;

PROCEDURE FrameHandle* (F: Objects.Object; VAR M: Objects.ObjMsg);
	VAR ver: LONGINT; x, y, w, h: INTEGER; F1: Frame; Q: Display3.Mask;
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
									Restore(F, Q, x, y, w, h)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									Display3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
									Restore(F, Q, x, y, w, h)
								END
							ELSIF M.device = Display.printer THEN Print(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & ~Effects.InCorner(M.X, M.Y, x, y, w, h) &
								(M.keys = {1}) & ~(Gadgets.selected IN F.state) THEN
								TrackFrame(F, x, y, w, h, M);
								IF (F.obj # NIL) THEN SetModel(F); Gadgets.Update(F.obj) END
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Gadgets.UpdateMsg THEN
						WITH M: Gadgets.UpdateMsg  DO
							IF F.obj # NIL THEN F.obj.handle(F.obj, M) END;
							IF M.obj = F.obj THEN
								IF F.stamp # M.stamp THEN F.stamp := M.stamp; UpdateModel(F) END;
								Gadgets.MakeMask(F, x, y, M.dlink, Q);
								Restore(F, Q, x, y, w, h)
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
		ELSIF M IS Objects.AttrMsg THEN HandleAttributes(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteNum(M.R, FrameVersion); Files.WriteSet(M.R, F.val); Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN
					Files.ReadNum(M.R, ver);
					IF ver = FrameVersion THEN
						Files.ReadSet(M.R, F.val);
						Gadgets.framehandle(F, M)
					END
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink	(* non-first arrival *)
				ELSE	(* first arrival *)
					NEW(F1); F.stamp := M.stamp; F.dlink := F1;
					CopyFrame(M, F, F1); M.obj := F1
				END
			END
		ELSE Gadgets.framehandle(F, M)
		END
	END
END FrameHandle;

PROCEDURE InitFrame* (F: Frame);
BEGIN F.W := 162; F.H := 20; F.val := {}; F.handle := FrameHandle
END InitFrame;

PROCEDURE NewFrame*;
VAR F: Frame;
BEGIN NEW(F); InitFrame(F); Objects.NewObj := F
END NewFrame;

END SetGadgets.

(**
Set
	Create with:	Gadgets.Link SetGadgets.NewSet
	Alias:	-
	Function:	Stores a 32 bit set.
	Attributes:
		Value:	Integer representation of the object's value.
		String:	String representation of the object's value (Oberon language convension).
	Links:	-

Frame
	Create with:	Gadgets.Insert SetGadgets.NewFrame
	Alias:	-
	Function:	This frame visualises a 32 bit set. One bit can be included or excluded by clicking
			on its placeholder (bit 0 start at the left hand side of the gadget). A bit is said
			to be included when at its corresponding position a black bar is shown. Otherwise
			the bit is not included in the set.
	Attributes:
		Value:	Integer representation of the object's value.
		String:	String representation of the object's value (Oberon language convension).
	Links:	-

Example
			

*)

System.Free SetGadgets ~

Gadgets.Insert ^ ~
	Panel	TextField	Slider	SetGadgets.NewFrame

Gadgets.ChangeAttr Value '{1,3,5,7,9,11,13,15,17..25,31}'
Gadgets.ChangeAttr Value '{}'
Gadgets.ChangeAttr Value '{0,31}'
