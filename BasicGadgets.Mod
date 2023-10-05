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

MODULE BasicGadgets;	(** portable *) (* jm 18.1.95 *)

(** Contains an implementation of the model gadgets Boolean, String, Integer, and Real, and of the visual gadgets Button, Checkbox and Slider. The buttons and checkboxes can also be used as radio-buttons by linking to them an Integer model gadget.
*)
(*
	JM 3.2.93 - New radio button look
					- SetValues improved
					- Gadgets.UpdateMsg goes to abstract gadgets too
	JM 8.2.93 - Cancel combination for button clicks improved
	jm 9.2.93 - new abstract object rooted in gadgets
		- Respond on Viewers.ViewerMsg
	jm 11.2.93 - Display.ControlMsg
	jm 3.2.93 - popout buttons improved
	23.7.93 - simplified copy of abstract objects
	19.4.94 - popout attribute is now set by default for buttons
	19.4.94 - Added Break
	21.4.95 - fixed command execution of checkboxes
	27.9.95 - fixed slider update model
	13.10.95 - Changed popout behavior of buttons
	3.5.96 - YesVal of checkboxes now always returns a value (ps - 3.5.96)
	8.5.96 - Add Look-Link to Buttons (ps - 8.5.96)
	29.7.96 - fixed NIL-trap in SetValues (ps - 29.7.96)
	20.11.96 - add 2 new button attributes (iw)
	25.4.97 - fixed bug in ButtonAttr (YesVal)
*)

IMPORT
	Objects, Gadgets, Display, Display3, Effects, Oberon, Texts, Files, Printer, Printer3, Fonts, Strings;

CONST
	VersionNo = 2; VersionNewButton = 4; VersionAbstract = 4;
	VersionNewCheckbox = 3;
	
	MaxLen = 64;

TYPE
	(* --- Things --- *)
	
	Boolean* = POINTER TO BooleanDesc;
	BooleanDesc* = RECORD (Gadgets.ObjDesc)
		val*: BOOLEAN;
	END;

	String* = POINTER TO StringDesc;
	StringDesc* = RECORD (Gadgets.ObjDesc)
		val*: ARRAY MaxLen OF CHAR;
	END;

	Integer* = POINTER TO IntegerDesc;
	IntegerDesc* = RECORD (Gadgets.ObjDesc)
		val*: LONGINT;
	END;

	Real* = POINTER TO RealDesc;
	RealDesc* = RECORD (Gadgets.ObjDesc)
		val*: LONGREAL;
	END;

	(* --- Gadgets --- *)
	
	Button* = POINTER TO ButtonDesc;
	ButtonDesc* = RECORD (Gadgets.FrameDesc)
		caption*: ARRAY 32 OF CHAR;	(** Caption shown inside the button. *)
		val*: BOOLEAN;	(** Pushed/popped out. *)
		popout*: BOOLEAN;	(** Button should pop out immediately after pressed. *)
		setval*: INTEGER;	(** Button is pressed should the button model have this value. *)
		look*: Objects.Object;	(** Object dropped inside of button, used as button representation instead of caption. *)
		led*: BOOLEAN;	(** visibility of a led if Button is pressed *)
		ledcol*: INTEGER;	(** Color of LED when Button is pressed *)
		inM, outM: Display3.Mask;
	END;
	
	CheckBox* = POINTER TO CheckBoxDesc;
	CheckBoxDesc* = RECORD (Gadgets.FrameDesc)
		val*: BOOLEAN;	(** State. *)
		setval*: INTEGER;	(** checkbox is ticked should the checkbox model have this value. *)
	END;

	Slider* = POINTER TO SliderDesc;
	SliderDesc* = RECORD (Gadgets.FrameDesc)
		min*, max*, val*: LONGINT;	(** Minimum, maximum and current value *)
		B, BW: INTEGER;
	END;

VAR W: Texts.Writer;
	
PROCEDURE Log;
BEGIN Texts.Append(Oberon.Log, W.buf) END Log;

PROCEDURE Min(x, y: INTEGER): INTEGER;
BEGIN IF x < y THEN RETURN x; ELSE RETURN y; END;
END Min;

PROCEDURE KillMasks(F: Objects.Object);
VAR O: Display3.OverlapMsg;
BEGIN
	O.F := NIL; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL; F.handle(F, O);
END KillMasks;

(* --- Version check --- *)

PROCEDURE WriteVersion(VAR R: Files.Rider);
BEGIN Files.WriteNum(R, VersionNo);
END WriteVersion;

PROCEDURE ReadVersion(VAR R: Files.Rider);
VAR x: LONGINT;
BEGIN Files.ReadNum(R, x);
	IF x # VersionNo THEN
		Texts.WriteString(W, "Version "); Texts.WriteInt(W, VersionNo, 3);
		Texts.WriteString(W, " of BasicGadgets cannot read version "); Texts.WriteInt(W, x, 3); Texts.WriteLn(W); Log;
		HALT(42);
	END;
END ReadVersion;

(* ---------- abstract objects ---------- *)

PROCEDURE CopyBoolean*(VAR M: Objects.CopyMsg; from, to: Boolean);
BEGIN
	Gadgets.CopyObject(M, from, to); to.val := from.val;  
END CopyBoolean;

PROCEDURE BooleanHandler*(obj: Objects.Object; VAR M: Objects.ObjMsg);
VAR obj2: Boolean; x: INTEGER; ver: LONGINT;
BEGIN
	WITH obj: Boolean DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN COPY("BasicGadgets.NewBoolean", M.s); M.class := Objects.String; M.res := 0
					ELSIF M.name = "Value" THEN M.b := obj.val; M.class := Objects.Bool; M.res := 0
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.set THEN
					IF M.name = "Value" THEN
						IF M.class = Objects.Bool THEN obj.val := M.b; M.res := 0 END
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.enum THEN
					M.Enum("Value"); Gadgets.objecthandle(obj, M)
				END
			END
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteNum(M.R, VersionAbstract); Files.WriteBool(M.R, obj.val);
					Gadgets.objecthandle(obj, M);
					(* WriteVersion(M.R); IF obj.val THEN Files.WriteInt(M.R, 1); ELSE Files.WriteInt(M.R, 0); END; *)
				ELSIF M.id = Objects.load THEN
					Files.ReadNum(M.R, ver);
					IF ver = VersionNo THEN (* old *)
						Files.ReadInt(M.R, x); obj.val := (x = 1);
					ELSIF ver = VersionAbstract THEN
						Files.ReadBool(M.R, obj.val); Gadgets.objecthandle(obj, M);
					ELSE
						Texts.WriteString(W, "Version "); Texts.WriteInt(W, VersionAbstract, 3);
						Texts.WriteString(W, " of boolean cannot read version "); Texts.WriteInt(W, ver, 3); Texts.WriteLn(W); Log;
						HALT(42);
					END
				END
			END;
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = obj.stamp THEN M.obj := obj.dlink
				ELSE NEW(obj2); obj.stamp := M.stamp; obj.dlink := obj2; CopyBoolean(M, obj, obj2); M.obj := obj2
				END
			END
		ELSE
			Gadgets.objecthandle(obj, M)
		END
	END
END BooleanHandler;

PROCEDURE InitBoolean*(obj: Boolean);
BEGIN obj.handle := BooleanHandler
END InitBoolean;

PROCEDURE NewBoolean*;
VAR obj: Boolean;
BEGIN NEW(obj); InitBoolean(obj); Objects.NewObj := obj;
END NewBoolean;

PROCEDURE CopyString*(VAR M: Objects.CopyMsg; from, to: String);
BEGIN Gadgets.CopyObject(M, from, to); COPY(from.val, to.val); 
END CopyString;

PROCEDURE StringHandler*(obj: Objects.Object; VAR M: Objects.ObjMsg);
VAR obj2: String; ver: LONGINT;
BEGIN
	WITH obj: String DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN COPY("BasicGadgets.NewString", M.s); M.class := Objects.String; M.res := 0
					ELSIF M.name = "Value" THEN COPY(obj.val, M.s); M.class := Objects.String; M.res := 0
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.set THEN
					IF M.name = "Value" THEN
						IF M.class = Objects.String THEN COPY(M.s,  obj.val); M.res := 0
						ELSIF M.class = Objects.Int THEN Strings.IntToStr(M.i, obj.val); M.res := 0
						ELSIF M.class = Objects.Real THEN Strings.RealToStr(M.x, obj.val); M.res := 0
						ELSIF M.class = Objects.LongReal THEN Strings.RealToStr(M.y, obj.val); M.res := 0
						END
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.enum THEN
					M.Enum("Value"); Gadgets.objecthandle(obj, M)
				END
			END
		ELSIF M IS  Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteNum(M.R, VersionAbstract); Files.WriteString(M.R, obj.val);
					Gadgets.objecthandle(obj, M);
				ELSIF M.id = Objects.load THEN
					Files.ReadNum(M.R, ver);
					IF ver = VersionNo THEN (* old *)
						Files.ReadString(M.R, obj.val)
					ELSIF ver = VersionAbstract THEN
						Files.ReadString(M.R, obj.val); Gadgets.objecthandle(obj, M);
					ELSE
						Texts.WriteString(W, "Version "); Texts.WriteInt(W, VersionAbstract, 3);
						Texts.WriteString(W, " of string cannot read version "); Texts.WriteInt(W, ver, 3); Texts.WriteLn(W); Log;
						HALT(42);
					END
				END
			END;
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = obj.stamp THEN M.obj := obj.dlink
				ELSE NEW(obj2); obj.stamp := M.stamp; obj.dlink := obj2; CopyString(M, obj, obj2); M.obj := obj2
				END
			END
		ELSE
			Gadgets.objecthandle(obj, M)
		END
	END
END StringHandler;

PROCEDURE InitString*(obj: String);
BEGIN obj.handle := StringHandler; COPY("", obj.val)
END InitString;

PROCEDURE NewString*;
VAR obj: String;
BEGIN NEW(obj); InitString(obj); Objects.NewObj := obj 
END NewString;

PROCEDURE CopyInteger*(VAR M: Objects.CopyMsg; from, to: Integer);
BEGIN Gadgets.CopyObject(M, from, to); to.val := from.val; 
END CopyInteger;

PROCEDURE IntegerHandler*(obj: Objects.Object; VAR M: Objects.ObjMsg);
VAR obj2: Integer; ver: LONGINT;
BEGIN
	WITH obj: Integer DO
		IF M IS  Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN COPY("BasicGadgets.NewInteger", M.s); M.class := Objects.String; M.res := 0
					ELSIF M.name = "Value" THEN M.i := obj.val; M.class := Objects.Int; M.res := 0
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.set THEN
					IF M.name = "Value" THEN
						IF M.class = Objects.Int THEN obj.val := M.i; M.res := 0
						ELSIF M.class = Objects.String THEN Strings.StrToInt(M.s, obj.val); M.res := 0
						ELSIF M.class = Objects.Real THEN obj.val := ENTIER(M.x); M.res := 0
						ELSIF M.class = Objects.LongReal THEN obj.val := ENTIER(M.x); M.res := 0
						END
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.enum THEN
					M.Enum("Value"); Gadgets.objecthandle(obj, M)
				END
			END;
		ELSIF M IS  Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteNum(M.R, VersionAbstract); Files.WriteLInt(M.R, obj.val); Gadgets.objecthandle(obj, M)
				ELSIF M.id = Objects.load THEN
					Files.ReadNum(M.R, ver);
					IF ver = VersionNo THEN (* old *)
						Files.ReadLInt(M.R, obj.val);
					ELSIF ver = VersionAbstract THEN
						Files.ReadLInt(M.R, obj.val); Gadgets.objecthandle(obj, M);
					ELSE
						Texts.WriteString(W, "Version "); Texts.WriteInt(W, VersionAbstract, 3);
						Texts.WriteString(W, " of integer cannot read version "); Texts.WriteInt(W, ver, 3); Texts.WriteLn(W); Log;
						HALT(42);
					END
				END
			END;
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = obj.stamp THEN
					M.obj := obj.dlink
				ELSE
					NEW(obj2); obj.stamp := M.stamp; obj.dlink := obj2; CopyInteger(M, obj, obj2); M.obj := obj2
				END;
			END;
		ELSE
			Gadgets.objecthandle(obj, M)
		END;
	END;
END IntegerHandler;

PROCEDURE InitInteger*(obj: Integer);
BEGIN obj.handle := IntegerHandler; obj.val := 0
END InitInteger;

PROCEDURE NewInteger*;
VAR obj: Integer;
BEGIN
	NEW(obj); InitInteger(obj); Objects.NewObj := obj 
END NewInteger;

PROCEDURE CopyReal*(VAR M: Objects.CopyMsg; from, to: Real);
BEGIN Gadgets.CopyObject(M, from, to); to.val := from.val; 
END CopyReal;

PROCEDURE RealHandler*(obj: Objects.Object; VAR M: Objects.ObjMsg);
VAR obj2: Real; ver: LONGINT;
BEGIN
	WITH obj: Real DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN COPY("BasicGadgets.NewReal", M.s); M.class := Objects.String; M.res := 0
					ELSIF M.name = "Value" THEN M.y := obj.val; M.class := Objects.LongReal; M.res := 0
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.set THEN
					IF M.name = "Value" THEN
						IF M.class = Objects.LongReal THEN obj.val := M.y; M.res := 0
						ELSIF M.class = Objects.Real THEN obj.val := M.x; M.res := 0
						ELSIF M.class = Objects.Int THEN obj.val := M.i; M.res := 0
						ELSIF M.class = Objects.String THEN Strings.StrToReal(M.s, obj.val); M.res := 0
						END
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.enum THEN
					M.Enum("Value"); Gadgets.objecthandle(obj, M)
				END
			END
		ELSIF M IS  Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteNum(M.R, VersionAbstract); Files.WriteLReal(M.R, obj.val); Gadgets.objecthandle(obj, M)
				ELSIF M.id = Objects.load THEN
					Files.ReadNum(M.R, ver);
					IF ver = VersionNo THEN (* old *)
						Files.ReadLReal(M.R, obj.val);
					ELSIF ver = VersionAbstract THEN
						Files.ReadLReal(M.R, obj.val); Gadgets.objecthandle(obj, M);
					ELSE
						Texts.WriteString(W, "Version "); Texts.WriteInt(W, VersionAbstract, 3);
						Texts.WriteString(W, " of real cannot read version "); Texts.WriteInt(W, ver, 3); Texts.WriteLn(W); Log;
						HALT(42)
					END
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = obj.stamp THEN
					M.obj := obj.dlink
				ELSE
					NEW(obj2); obj.stamp := M.stamp; obj.dlink := obj2; CopyReal(M, obj, obj2); M.obj := obj2
				END
			END
		ELSE
			Gadgets.objecthandle(obj, M)
		END
	END
END RealHandler;

PROCEDURE InitReal*(obj: Real);
BEGIN obj.handle := RealHandler; obj.val := 0
END InitReal;

PROCEDURE NewReal*;
VAR obj: Real;
BEGIN
	NEW(obj); InitReal(obj); Objects.NewObj := obj 
END NewReal;

PROCEDURE Field(F: Gadgets.Frame; VAR name: ARRAY OF CHAR);
VAR A: Objects.AttrMsg;
BEGIN
	A.id := Objects.get; A.name := "Field"; A.class := Objects.Inval; A.s := "";
	F.handle(F, A);
	IF (A.res >= 0) & (A.class = Objects.String) & (A.s # "") THEN COPY(A.s, name)
	ELSE COPY("Value", name)
	END
END Field;

(* ------ Gadgets ------ *)

PROCEDURE ButtonUpdateModel(F: Button);
VAR A: Objects.AttrMsg;
BEGIN
	IF F.obj # NIL THEN
		A.id := Objects.get; Field(F, A.name); A.class := Objects.Inval; A.res := -1;
		F.obj.handle(F.obj, A);
		IF A.res >= 0 THEN
			IF A.class = Objects.Bool THEN F.val := A.b
			ELSIF A.class = Objects.Int THEN F.val := A.i = F.setval
			END
		END
	END
END ButtonUpdateModel;

PROCEDURE ButtonSetModel(F: Button);
VAR A: Objects.AttrMsg;
BEGIN
	IF F.obj # NIL THEN
		A.id := Objects.get; Field(F, A.name); A.class := Objects.Inval; A.res := -1;
		F.obj.handle(F.obj, A);
		IF A.res >= 0 THEN
			A.dlink := F.dlink;
			IF A.class = Objects.Bool THEN A.b := F.val;
				A.id := Objects.set; A.res := -1; F.obj.handle(F.obj, A)
			ELSIF A.class = Objects.Int THEN
				IF F.val THEN A.i := F.setval; A.id := Objects.set; A.res := -1; F.obj.handle(F.obj, A) END
			END
		END
	END
END ButtonSetModel;

PROCEDURE ButtonSetLook(F: Button; f: Gadgets.Frame): BOOLEAN; (* ps - 8.5.96 *)
VAR CM: Display.ControlMsg; B: Objects.BindMsg;
BEGIN
	IF Gadgets.Recursive(F, f) THEN
		Texts.WriteString(W,"Not allowed, will cause recursive structures"); Log;
		RETURN FALSE
	ELSIF (F.lib # NIL) & (f.lib # NIL) & (F.lib # f.lib) & (f.lib.name # "") THEN
		Texts.WriteString(W,"Across library movement not allowed"); Log;
		RETURN FALSE
	ELSE
		CM.id := Display.remove; CM.F := f; Display.Broadcast(CM); (* <<< remove *)
		IF F.lib # NIL THEN B.lib:= F.lib; f.handle(f, B); END;
		F.look := f; KillMasks(F);
		RETURN TRUE
	END;
END ButtonSetLook;

(** Goes through the list of selected gadgets (must be buttons and checkboxes) and assigns to each of
them a different SetValue attribute numbered from 0. This is useful to create mutual exclusive radio-buttons *)
PROCEDURE SetValues*;
VAR M: Display.SelectMsg; b, c: Objects.Object; val: INTEGER;
BEGIN
	M.id := Display.get; M.F := NIL; M.time := 0; M.obj := NIL; Display.Broadcast(M);
	IF M.time > 0 THEN
		b := M.obj; val := 0; 
		WHILE b # NIL DO
			IF b IS Button THEN
				WITH b: Button DO IF (b.obj # NIL) & (b.obj IS Integer) THEN c := b.obj; b.setval := val; INC(val) END
				END
			ELSIF b IS CheckBox THEN
				WITH b: CheckBox DO IF (b.obj # NIL) & (b.obj IS Integer) THEN c := b.obj; b.setval := val; INC(val) END
				END
			END;
			b := b.slink
		END;
		IF c # NIL THEN Gadgets.Update(c) END	(* ps - 29.7.96 *)
	END;
END SetValues;

	PROCEDURE ForceString(F: Display.Frame; VAR M: Objects.AttrMsg);
	BEGIN Gadgets.framehandle(F, M);
		IF M.res < 0 THEN M.class := Objects.String; M.s := ""; M.res := 0 END
	END ForceString;

PROCEDURE ButtonAttr(F: Button; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("BasicGadgets.NewButton", M.s); M.res := 0
		ELSIF M.name = "Caption" THEN M.class := Objects.String; COPY(F.caption, M.s); M.res := 0
		ELSIF M.name = "Value" THEN M.class := Objects.Bool; M.b := F.val; M.res := 0
		ELSIF M.name = "Popout" THEN M.class := Objects.Bool; M.b := F.popout; M.res := 0
		ELSIF M.name = "SetVal" THEN M.class := Objects.Int; M.i := F.setval; M.res := 0
		ELSIF M.name = "LineupHY" THEN M.class := Objects.Int; M.i := F.H DIV 2 - 5; M.res := 0
		ELSIF M.name = "YesVal" THEN
			IF F.val THEN Gadgets.framehandle(F, M);
				IF M.res < 0 THEN M.class := Objects.String; M.s := "" END
			ELSE M.class := Objects.String; M.s := ""
			END;
			M.res := 0
		ELSIF M.name = "Field" THEN ForceString(F, M)
		ELSIF M.name = "Cmd" THEN ForceString(F, M)
		ELSIF M.name = "Led" THEN M.class := Objects.Bool; M.b:= F.led; M.res := 0
		ELSIF M.name = "LedColor" THEN M.class:= Objects.Int; M.i := F.ledcol; M.res := 0
		ELSIF M.name = "Color" THEN
			Gadgets.framehandle(F, M);
			IF M.res < 0 THEN
				M.class := Objects.Int; M.i := Display3.upC; M.res := 0
			END
		ELSE Gadgets.framehandle(F, M) END
	ELSIF M.id = Objects.set THEN
		IF (M.name = "Caption") THEN
			IF  (M.class = Objects.String) THEN COPY(M.s, F.caption); M.res := 0 END
		ELSIF (M.name = "Value") THEN
			IF  (M.class = Objects.Bool) THEN
				IF F.popout THEN M.b := FALSE END; (* small hack *)
				F.val := M.b; M.res := 0;
				IF F.obj # NIL THEN
					ButtonSetModel(F); Gadgets.Update(F.obj)
				END
			END
		ELSIF (M.name = "Popout") THEN
			IF (M.class = Objects.Bool) THEN F.popout := M.b; M.res := 0;
				IF F.val THEN (* pushed in *)
					F.val := FALSE;
					IF F.obj # NIL THEN
				 		ButtonSetModel(F); Gadgets.Update(F.obj);
					 END;
				END;
			END;
		ELSIF (M.name = "SetVal") THEN
			IF (M.class = Objects.Int) THEN F.setval := SHORT(M.i);
				IF F.obj # NIL THEN Gadgets.Update(F.obj) END;
				M.res := 0
			END
		ELSIF (M.name = "Led") THEN
			IF (M.class = Objects.Bool) THEN F.led := M.b; M.res:= 0 END
		ELSIF (M.name = "LedColor") THEN
			IF (M.class = Objects.Int) THEN F.ledcol := SHORT(M.i); M.res:= 0 END
		ELSE Gadgets.framehandle(F, M)
		END;
	ELSIF M.id = Objects.enum THEN
		M.Enum("Caption");
		M.Enum("Value"); M.Enum("Popout"); M.Enum("Led");
		M.Enum("LedColor"); M.Enum("Color"); M.Enum("SetVal");
		M.Enum("YesVal"); M.Enum("Field"); M.Enum("Cmd");
		Gadgets.framehandle(F, M)
	END
END ButtonAttr;

PROCEDURE RestoreButton(R: Display3.Mask; F: Button; x, y, w, h, u, v, w1, h1: INTEGER; dlink: Objects.Object);
VAR D: Display.DisplayMsg; L: Gadgets.Frame; O: Display3.OverlapMsg; A: Objects.AttrMsg; ll, lr, lb, lt, col: INTEGER;
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	A.id := Objects.get; A.name := "Color"; A.class := Objects.Inval; A.i := Display3.upC; A.res := -1;
	F.handle(F, A); IF A.class = Objects.Int THEN col := SHORT(A.i) ELSE col := Display3.upC END;
	IF F.val THEN
		Display3.Rect3D(R, Display3.bottomC, Display3.topC, x, y, w, h, 1, Display.replace);
		Display3.Rect3D(R, Display3.downC, Display3.upC, x + 1, y + 1, w - 2, h - 2, 1, Display.replace);
		Display3.ReplConst(R, col, x + 2, y + 2, w - 4, h - 4, Display.replace); (* inside *)
		
		IF F.caption # "" THEN
			Display3.CenterString(R, Display3.textC, x + 3, y + 1, w - 4, h - 4, Fonts.Default, F.caption, Display3.textmode)
		ELSIF (F.look # NIL) THEN
			L := F.look(Gadgets.Frame);
			ll := x + w DIV 2 - L.W DIV 2 + 1; lr := ll + L.W - 1;
			lb := y + h DIV 2 - L.H DIV 2 - 1; lt := lb + L.H - 1;
			u := x + u; v := y + h - 1 + v;
			IF u < ll THEN DEC(w1, ll - u); u := ll END;
			IF v < lb THEN DEC(h1, lb - y); v := lb END;
			IF u + w1 - 1 > lr THEN w1 := lr + 1 - u END;
			IF v + h1 - 1 > lt THEN h1 := lt + 1 - v END;
			O.F := L; O.res := -1; O.M := F.inM; O.x := 0; O.y := 0; O.dlink := NIL; L.handle(L, O);
			D.device := Display.screen; D.id := Display.area; D.F := L; D.dlink := dlink;
			D.x := ll - L.X; D.y := lb - L.Y;
			D.u := u - ll; D.v := v - lt; D.w := w1; D.h := h1;
			D.res := -1;
			L.handle(L, D)
		END;
		IF F.led THEN
			Display3.ReplConst(R, F.ledcol, x + 4, y + h - 7, 10, 3, Display.replace);
			Display3.ReplConst(R, Display3.black, x + 4, y + h - 8, 10, 1, Display.replace);
			Display3.ReplConst(R, Display3.black, x + 14, y + h - 8, 1, 4, Display.replace)
   	END
	ELSE   		
		Display3.Rect3D(R, Display3.bottomC, Display3.topC, x, y, w, h, 1, Display.replace);
		Display3.Rect3D(R, Display3.topC, Display3.bottomC, x + 1, y + 1, w - 2, h - 2, 1, Display.replace);
   	 Display3.ReplConst(R, col, x + 2, y + 2, w - 4, h - 4, Display.replace); (* inside *)
   	 IF F.caption # "" THEN
			Display3.CenterString(R, Display3.textC, x + 2, y + 2, w - 4, h - 4, Fonts.Default, F.caption, Display3.textmode)
		ELSIF (F.look # NIL) THEN
			L := F.look(Gadgets.Frame);
			ll := x + w DIV 2 - L.W DIV 2; lr := ll + L.W - 1;
			lb := y + h DIV 2 - L.H DIV 2; lt := lb + L.H - 1;
			u := x + u; v := y + h - 1 + v;
			IF u < ll THEN DEC(w1, ll - u); u := ll END;
			IF v < lb THEN DEC(h1, lb - y); v := lb END;
			IF u + w1 - 1 > lr THEN w1 := lr + 1 - u END;
			IF v + h1 - 1 > lt THEN h1 := lt + 1 - v END;
			O.F := L; O.res := -1; O.M := F.outM; O.x := 0; O.y := 0; O.dlink := NIL; L.handle(L, O);
			D.device := Display.screen; D.id := Display.area; D.F := L; D.dlink := dlink;
			D.x := ll - L.X; D.y := lb - L.Y;
			D.u := u - ll; D.v := v - lt; D.w := w1; D.h := h1;
			D.res := -1;
			L.handle(L, D)
		END
	END;
	IF Gadgets.selected IN F.state THEN Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint) END
END RestoreButton;

PROCEDURE PrintButton(F: Button; VAR M: Display.DisplayMsg);
VAR R: Display3.Mask; x, y, w, h: INTEGER; D: Display.DisplayMsg; L: Gadgets.Frame; O: Display3.OverlapMsg;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	x := M.x; y := M.y; w := P(F.W); h := P(F.H);
	IF F.val THEN
		Printer3.Rect3D(R, Display3.bottomC, Display3.topC, x, y, w, h, P(1), Display.replace);
		Printer3.Rect3D(R, Display3.downC, Display3.upC, x + P(1), y + P(1), w - P(2), h - P(2), P(1), Display.replace);
		Printer3.ReplConst(R, Display3.upC, x + P(2), y + P(2), w - P(4), h - P(4), Display.replace); (* inside *)
		
		IF F.caption # "" THEN
			Printer3.CenterString(R, Display3.textC, x + P(3), y + P(1), w - P(4), h - P(4), Fonts.Default, F.caption, Display3.textmode);
		ELSIF (F.look # NIL) THEN
			L := F.look(Gadgets.Frame);
			O.res := -1; O.M := F.inM; O.x := 0; O.y := 0; O.dlink := NIL; L.handle(L, O);
			D.device := Display.printer; D.id := Display.full; D.F := NIL; D.dlink := M.dlink;
			D.x := x + w DIV 2 - P(L.W DIV 2) + P(1); D.y := y + h DIV 2 - P(L.H DIV 2) - P(1);
			D.res := -1;
			L.handle(L, D)
		END;
		IF F.led THEN
			Printer3.ReplConst(R, F.ledcol, x + P(4), y + h - P(7), P(10), P(3), Display.replace);
			Printer3.ReplConst(R, Display3.black, x + P(4), y + h - P(8), P(10), P(1), Display.replace);
			Printer3.ReplConst(R, Display3.black, x + P(14), y + h - P(8), P(1), P(4), Display.replace)
		END
	ELSE
		Printer3.Rect3D(R, Display3.bottomC, Display3.topC, x, y, w, h, P(1), Display.replace);
		Printer3.Rect3D(R, Display3.topC, Display3.bottomC, x + P(1), y + P(1), w - P(2), h - P(2), P(1), Display.replace);
   	 Printer3.ReplConst(R, Display3.upC, x + P(2), y + P(2), w - P(4), h - P(4), Display.replace); (* inside *)
   	 IF F.caption # "" THEN
			Printer3.CenterString(R, Display3.textC, x + P(2), y + P(2), w - P(4), h - P(4), Fonts.Default, F.caption, Display3.textmode);
		ELSIF (F.look # NIL) THEN
			L := F.look(Gadgets.Frame);
			O.res := -1; O.M := F.outM; O.x := 0; O.y := 0; O.dlink := NIL; L.handle(L, O);
			D.device := Display.printer; D.id := Display.full; D.F := NIL; D.dlink := M.dlink;
			D.x := x + w DIV 2 - P(L.W DIV 2); D.y := y + h DIV 2 - P(L.H DIV 2);
			D.res := -1;
			L.handle(L, D);
		END;
	END
END PrintButton;


PROCEDURE CopyButton*(VAR M: Objects.CopyMsg; from, to: Button);
BEGIN
	Gadgets.CopyFrame(M, from, to); COPY(from.caption, to.caption); to.val := from.val; to.popout := from.popout;
	to.look := Gadgets.CopyPtr(M, from.look); to.setval := from.setval;
	to.led := from.led; to.ledcol := from.ledcol
END CopyButton;

PROCEDURE ButtonHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR F2: Button; x, y, w, h: INTEGER;   
	keysum: SET; ver: LONGINT; f: Gadgets.Frame; R: Display3.Mask;
BEGIN
	WITH F: Button DO
		IF M IS  Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO ButtonAttr(F, M) END;
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					IF ~F.led OR (F.ledcol # Display3.red) THEN
						Files.WriteNum(M.R, VersionNewButton);
						IF F.led THEN Files.WriteInt(M.R, 1); ELSE Files.WriteInt(M.R, 0); END;
						Files.WriteInt(M.R, F.ledcol)
					ELSE Files.WriteNum(M.R, 3)
					END;
					Files.WriteString(M.R, F.caption);
					IF F.val THEN Files.WriteInt(M.R, 1); ELSE Files.WriteInt(M.R, 0); END;
					IF F.popout THEN Files.WriteInt(M.R, 1); ELSE Files.WriteInt(M.R, 0); END;
					Files.WriteInt(M.R,F.setval);
					Gadgets.WriteRef(M.R, F.lib, F.look);
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN
					Files.ReadNum(M.R, ver);
					IF ver = VersionNo THEN
						Files.ReadString(M.R, F.caption);
						Files.ReadInt(M.R, x); F.val := (x = 1);
						Files.ReadInt(M.R, x); F.popout := (x = 1);
						Gadgets.framehandle(F, M);
						IF (F.obj # NIL) & (F.obj IS Integer) THEN Files.ReadInt(M.R, x); F.setval := SHORT(x) END;
					ELSIF ver >= 3 THEN
						IF ver = VersionNewButton THEN
							Files.ReadInt(M.R, x); F.led := (x = 1);
							Files.ReadInt(M.R, F.ledcol)
						END;
						Files.ReadString(M.R, F.caption);
						Files.ReadInt(M.R, x); F.val := (x = 1);
						Files.ReadInt(M.R, x); F.popout := (x = 1); IF F.popout THEN F.val := FALSE END;
						Files.ReadInt(M.R,F.setval);
						Gadgets.ReadRef(M.R, F.lib, F.look);
						Gadgets.framehandle(F, M);
					ELSE
						Texts.WriteString(W, "Version "); Texts.WriteInt(W, VersionNewButton, 3);
						Texts.WriteString(W, " of buttons cannot read version "); Texts.WriteInt(W, ver, 3); Texts.WriteLn(W); Log;
						HALT(42);
					END
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN
					M.obj := F.dlink
				ELSE
					NEW(F2); F.stamp := M.stamp; F.dlink := F2; CopyButton(M, F, F2); M.obj := F2
				END
			END
		ELSIF M IS Objects.BindMsg THEN
			Gadgets.framehandle(F, M);
			IF F.look # NIL THEN F.look.handle(F.look, M) END;
		ELSIF M IS Objects.LinkMsg THEN (* ps - 8.5.96 *)
			WITH M: Objects.LinkMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Look" THEN M.obj:= F.look; M.res:= 0
					ELSE Gadgets.framehandle(F, M)
					END
				ELSIF M.id = Objects.set THEN
					IF M.name = "Look" THEN
						IF M.obj = NIL THEN F.look:= NIL; M.res:= 0
						ELSIF M.obj = F.look THEN M.res:= 0
						ELSIF M.obj IS Gadgets.Frame THEN
							IF ButtonSetLook(F, M.obj(Gadgets.Frame)) THEN M.res:= 0 END
						END
					ELSE Gadgets.framehandle(F, M)
					END
				ELSIF M.id = Objects.enum THEN
					M.Enum("Look"); Gadgets.framehandle(F, M)
				END
			END
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF M.res >= 0 THEN RETURN END;
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
				IF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg  DO
						IF M.device = Display.screen THEN
							IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								RestoreButton(R, F, x, y, w, h, 0, 1 - h, w, h, M.dlink)
							ELSIF (M.id = Display.area) & (M.F = F) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R); 
								Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
								RestoreButton(R, F, x, y, w, h, M.u, M.v, M.w, M.h, M.dlink)
							END
						ELSIF M.device = Display.printer THEN PrintButton(F, M)
						END
					END
				ELSIF M IS Display.ConsumeMsg THEN
					WITH M: Display.ConsumeMsg DO (* ps - 8.5.96 *)
						IF (M.id = Display.drop) & (M.F = F) & (F.caption = "") & (M.obj IS Gadgets.Frame) & (F.look = NIL) THEN
							IF ButtonSetLook(F, M.obj(Gadgets.Frame)) THEN
								M.res:= 0; Gadgets.Update(F);
							END
						ELSE
							Gadgets.framehandle(F, M);
						END
					END
				ELSIF M IS Display3.OverlapMsg THEN
					WITH M: Display3.OverlapMsg DO
						Gadgets.framehandle(F, M);
						IF F.look # NIL THEN
							f := F.look(Gadgets.Frame);
							IF F.mask = NIL THEN
								KillMasks(F.look); F.inM := NIL; F.outM := NIL;
							ELSE
								Display3.Copy(M.M, F.outM);
								Display3.Intersect(F.outM, 2, -h + 3, w - 4, h - 4);
								Display3.Intersect(F.outM, w DIV 2 - f.W DIV 2, (-h+1) DIV 2 - f.H DIV 2, f.W, f.H);
								F.outM.x := -(w DIV 2 - f.W DIV 2); F.outM.y := -((-h+1) DIV 2 - f.H DIV 2 + f.H) + 1;
								Display3.Shift(F.outM);
								
								Display3.Copy(M.M, F.inM);
								Display3.Intersect(F.inM, 2, -h + 3, w - 4, h - 4);
								Display3.Intersect(F.inM, w DIV 2 - f.W DIV 2 + 1, (-h+1) DIV 2 - f.H DIV 2 - 1, f.W, f.H);
								F.inM.x := -(w DIV 2 - f.W DIV 2 + 1); F.inM.y := -((-h+1) DIV 2 - f.H DIV 2 + f.H - 1) + 1;
								Display3.Shift(F.inM)
							END
						END
					END
				ELSIF M IS Gadgets.UpdateMsg THEN
					WITH M: Gadgets.UpdateMsg  DO
						IF F.obj # NIL THEN F.obj.handle(F.obj, M) END;
						IF M.obj = F.obj THEN
							IF M.stamp # F.stamp THEN F.stamp := M.stamp;
								ButtonUpdateModel(F)
							END;
							Gadgets.MakeMask(F, x, y, M.dlink, R);
							RestoreButton(R, F, x, y, w, h, 0, 1 - h, w, h, M.dlink)
						ELSE Gadgets.framehandle(F, M)
						END
					END
				ELSIF M IS Display.ControlMsg THEN (*!!! *)
					WITH M: Display.ControlMsg DO
						IF F.obj # NIL THEN F.obj.handle(F.obj, M) END;
						IF (M.id = Display.restore) & (M.stamp # F.stamp) THEN F.stamp := M.stamp;
							ButtonUpdateModel(F)
						END
					END
				ELSIF M IS Oberon.InputMsg THEN
					WITH M: Oberon.InputMsg DO 
						IF (M.id = Oberon.track) & (1 IN M.keys) & Gadgets.InActiveArea(F, M) THEN
							F.val := ~F.val;
							IF F.obj # NIL THEN
								ButtonSetModel(F); Gadgets.Update(F.obj)
							ELSE Gadgets.Update(F)
							END;
							IF F.popout THEN
								keysum := M.keys;
								REPEAT
									IF F.val # Effects.Inside(M.X, M.Y, x, y, w, h) THEN
										F.val := ~F.val;
										IF F.obj # NIL THEN
											ButtonSetModel(F); Gadgets.Update(F.obj);
										ELSE Gadgets.Update(F)
										END;
									END;
									Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow);
									keysum := keysum + M.keys;
								UNTIL M.keys = {}; M.res := 0;
								IF F.val THEN
									F.val := ~F.val;
									IF F.obj # NIL THEN
										ButtonSetModel(F); Gadgets.Update(F.obj)
									ELSE Gadgets.Update(F);
									END;
									IF keysum = {1} THEN
										Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL);
									END
								END
							ELSE
								keysum := M.keys;
								REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys;
								UNTIL M.keys = {}; M.res := 0;
								IF keysum = {1} THEN
									Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL);
								END;
							END;
						ELSIF ~(Gadgets.selected IN F.state) THEN
							Gadgets.framehandle(F, M);
						END; 
					END;
				ELSE
					Gadgets.framehandle(F, M);
				END;
			END;
		ELSE
			Gadgets.framehandle(F, M);
		END;
	END;
END ButtonHandler;

PROCEDURE InitButton*(F: Button);
BEGIN 
	F.handle := ButtonHandler; F.W := 40; F.H := 30;
	F.popout := TRUE; F.led:= TRUE; F.ledcol:= Display3.red;
	COPY("Button", F.caption)
END InitButton;

PROCEDURE NewButton*;
VAR F: Button;
BEGIN
	NEW(F); InitButton(F); Objects.NewObj := F; 
END NewButton;

(* ========== Checkboxes ================ *)

PROCEDURE CheckBoxUpdateModel(F: CheckBox);
VAR A: Objects.AttrMsg;
BEGIN
	IF F.obj # NIL THEN
		A.id := Objects.get; Field(F, A.name); A.class := Objects.Inval; A.res := -1;
		F.obj.handle(F.obj, A);
		IF A.res >= 0 THEN
			IF A.class = Objects.Bool THEN F.val := A.b
			ELSIF A.class = Objects.Int THEN F.val := A.i = F.setval
			END
		END
	END
END CheckBoxUpdateModel;

PROCEDURE CheckBoxSetModel(F: CheckBox);
VAR A: Objects.AttrMsg;
BEGIN
	IF F.obj # NIL THEN
		A.id := Objects.get; Field(F, A.name); A.class := Objects.Inval; A.res := -1;
		F.obj.handle(F.obj, A);
		IF A.res >= 0 THEN
			A.dlink := F.dlink;
			IF A.class = Objects.Bool THEN A.b := F.val;
				A.id := Objects.set; A.res := -1; F.obj.handle(F.obj, A)
			ELSIF A.class = Objects.Int THEN
				IF F.val THEN A.i := F.setval; A.id := Objects.set; A.res := -1; F.obj.handle(F.obj, A) END
			END
		END
	END
END CheckBoxSetModel;

PROCEDURE CheckBoxAttr(B: CheckBox; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("BasicGadgets.NewCheckBox", M.s); M.res := 0
		ELSIF M.name = "Value" THEN M.class := Objects.Bool; M.b := B.val; M.res := 0
		ELSIF M.name = "SetVal" THEN M.class := Objects.Int; M.i := B.setval; M.res := 0
		ELSIF M.name = "LineupHY" THEN M.class := Objects.Int; M.i := B.H DIV 2 - 5; M.res := 0
		ELSIF M.name = "YesVal" THEN (* ps - 3.5.96 *)
			IF B.val THEN 
				Gadgets.framehandle(B, M);
				IF M.res < 0 THEN M.class := Objects.String; M.s := "" END
			ELSE M.class := Objects.String; M.s := "" END; M.res := 0;
		ELSIF M.name = "Field" THEN ForceString(B, M)
		ELSIF M.name = "Cmd" THEN ForceString(B, M)
		ELSIF M.name = "Color" THEN
			Gadgets.framehandle(B, M);
			IF M.res < 0 THEN
				M.class := Objects.Int; M.i := Display3.textbackC; M.res := 0
			END
		ELSE Gadgets.framehandle(B, M);
		END;
	ELSIF M.id = Objects.set THEN
		IF M.name = "Value" THEN
			IF (M.class = Objects.Bool) THEN B.val := M.b; M.res := 0;
				IF B.obj # NIL THEN
			 		CheckBoxSetModel(B); Gadgets.Update(B.obj);
				 END
			END;
		ELSIF M.name = "SetVal" THEN
			IF (M.class = Objects.Int) THEN B.setval := SHORT(M.i);
				IF B.obj # NIL THEN Gadgets.Update(B.obj) END;
				M.res := 0; 
			END
		ELSE Gadgets.framehandle(B, M)
		END;
	ELSIF M.id = Objects.enum THEN
		M.Enum("Value"); M.Enum("YesVal"); M.Enum("SetVal"); M.Enum("Field"); M.Enum("Cmd"); M.Enum("Color"); Gadgets.framehandle(B, M); 
	END;
END CheckBoxAttr;

PROCEDURE RestoreCheckBox(R: Display3.Mask; F: CheckBox; x, y, w, h: INTEGER);
VAR A: Objects.AttrMsg; col: INTEGER;
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	A.id := Objects.get; A.name := "Color"; A.class := Objects.Inval; A.i := Display3.textbackC; A.res := -1;
	F.handle(F, A); IF A.class = Objects.Int THEN col := SHORT(A.i) ELSE col := Display3.textbackC END;
	A.id := Objects.get; Field(F, A.name); A.class := Objects.Inval; A.res := -1;
	IF F.obj # NIL THEN F.obj.handle(F.obj, A) END;
	
	IF (A.res >= 0) & (A.class = Objects.Int) THEN (* change look if integers are involved *)
		Display3.FilledRect3D(R, Display3.bottomC, Display3.topC, col, x, y, w, h, 1, Display.replace);
		IF F.val THEN
			Display3.FilledRect3D(R, Display3.topC, Display3.bottomC, Display3.groupC, x + 3, y + 3, w - 6, h - 6, 1, Display.replace);
		END
	ELSE
		Display3.FilledRect3D(R, Display3.bottomC, Display3.topC, col, x, y, w, h, 1, Display.replace);
		IF F.val THEN
			Display3.ReplConst(R, Display3.white, x + 5, y + 4, 1, 10, Display.replace);
			Display3.ReplConst(R, Display3.black, x + 6, y + 4, 1, 10, Display.replace);
			Display3.Line(R, Display3.white, Display.solid, x + 5, y + 5, x + 17, y + 17, 1, Display.replace);
			Display3.Line(R, Display3.black, Display.solid, x + 5, y + 4, x + 17, y + 16, 1, Display.replace);
		END
	END;
	IF Gadgets.selected IN F.state THEN Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint); END;
END RestoreCheckBox;

PROCEDURE PrintCheckBox(F: CheckBox; VAR M: Display.DisplayMsg);
VAR A: Objects.AttrMsg; R: Display3.Mask; x, y, w, h, col: INTEGER;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	A.id := Objects.get; A.name := "Color"; A.class := Objects.Inval; A.i := Display3.textbackC; A.res := -1;
	F.handle(F, A); IF A.class = Objects.Int THEN col := SHORT(A.i) ELSE col := Display3.textbackC END;
	x := M.x; y := M.y; w := P(F.W); h := P(F.H);
	IF (F.obj # NIL) & (F.obj IS Integer) THEN
		Printer3.FilledRect3D(R, Display3.bottomC, Display3.topC, col, x, y, w, h, P(1), Display.replace);
		IF F.val THEN
			Printer3.FilledRect3D(R, Display3.topC, Display3.bottomC, Display3.groupC, x + P(3), y + P(3), w - P(6), h - P(6), 1, Display.replace);
		END
	ELSE
		Printer3.FilledRect3D(R, Display3.bottomC, Display3.topC, col, x, y, w, h, P(1), Display.replace);
		IF F.val THEN
			Printer3.ReplConst(R, Display3.white, x + P(5), y + P(4), P(1), P(10), Display.replace);
			Printer3.ReplConst(R, Display3.black, x + P(6), y + P(4), P(1), P(10), Display.replace);
			Printer3.Line(R, Display3.white, Display.solid, x + P(5), y + P(5), x + P(17), y + P(17), P(1), Display.replace);
			Printer3.Line(R, Display3.black, Display.solid, x + P(5), y + P(4), x + P(17), y + P(16), P(1), Display.replace);
		END
	END
END PrintCheckBox;

PROCEDURE CopyCheckBox*(VAR M: Objects.CopyMsg; from, to: CheckBox);
BEGIN Gadgets.CopyFrame(M, from, to); to.val := from.val; to.setval := from.setval;
END CopyCheckBox;

PROCEDURE CheckBoxHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h, u, v: INTEGER; ver: LONGINT; F0: CheckBox; R: Display3.Mask; keysum: SET;
BEGIN
	WITH F: CheckBox DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO CheckBoxAttr(F, M) END
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteNum(M.R, VersionNewCheckbox);
					Files.WriteBool(M.R, F.val);
					Files.WriteInt(M.R, F.setval);
					Gadgets.framehandle(F, M);
				ELSIF M.id = Objects.load THEN
					Files.ReadNum(M.R, ver);
					IF ver = VersionNo THEN
						Files.ReadInt(M.R, x); F.val := (x = 1);
						Gadgets.framehandle(F, M);
						IF (F.obj # NIL) & (F.obj IS Integer) THEN Files.ReadInt(M.R, x); F.setval := x END
					ELSIF ver = VersionNewCheckbox THEN
						Files.ReadBool(M.R, F.val);
						Files.ReadInt(M.R, F.setval);
						Gadgets.framehandle(F, M);
					ELSE
						Texts.WriteString(W, "Version "); Texts.WriteInt(W, VersionNewCheckbox, 3);
						Texts.WriteString(W, " of checkboxes cannot read version "); Texts.WriteInt(W, ver, 3); Texts.WriteLn(W); Log;
						HALT(42);
					END
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyCheckBox(M, F, F0); M.obj := F0
				END
			END;
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate actual coordinates *)
				u := M.x; v := M.y; (* store volatile info *)
				IF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg  DO
						IF M.device = Display.screen THEN 
							IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								RestoreCheckBox(R, F, x, y, w, h);
							ELSIF (M.id = Display.area) & (M.F = F) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
								RestoreCheckBox(R, F, x, y, w, h);
							END
						ELSIF M.device = Display.printer THEN PrintCheckBox(F, M)
						END
					END
				ELSIF M IS Gadgets.UpdateMsg THEN
					WITH M: Gadgets.UpdateMsg  DO
						IF F.obj # NIL THEN F.obj.handle(F.obj, M) END;
						IF M.obj = F.obj THEN
							IF M.stamp # F.stamp THEN F.stamp := M.stamp;
								CheckBoxUpdateModel(F)
							END;
							Gadgets.MakeMask(F, x, y, M.dlink, R);
							RestoreCheckBox(R, F, x, y, w, h)
						ELSE Gadgets.framehandle(F, M)
						END
					END
				ELSIF M IS Display.ControlMsg THEN (*!!! *)
					WITH M: Display.ControlMsg DO
						IF F.obj # NIL THEN F.obj.handle(F.obj, M) END;
						IF (M.id = Display.restore) & (M.stamp # F.stamp) THEN F.stamp := M.stamp;
							CheckBoxUpdateModel(F)
						END
					END
				ELSIF M IS Oberon.InputMsg THEN
					WITH M: Oberon.InputMsg DO 
						IF (M.id = Oberon.track) & (1 IN M.keys) & Gadgets.InActiveArea(F, M) THEN
							F.val := ~F.val;
							IF F.obj # NIL THEN
								CheckBoxSetModel(F); Gadgets.Update(F.obj)
							ELSE
								Gadgets.Update(F)
							END;
							keysum := M.keys;
							REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow);
								keysum := keysum + M.keys
							UNTIL M.keys = {};
							M.res := 0;
							IF keysum = {1} THEN Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL) END
						ELSIF ~(Gadgets.selected IN F.state) THEN
							Gadgets.framehandle(F, M);
						END; 
					END;
				ELSE
					Gadgets.framehandle(F, M);	
				END;
				M.x := u; M.y := v; (* restore volatile info *)
			END;
		ELSE
			Gadgets.framehandle(F, M);
		END;
	END;
END CheckBoxHandler;

PROCEDURE InitCheckBox*(F: CheckBox);
BEGIN F.W := 20; F.H := 20; F.handle := CheckBoxHandler;
END InitCheckBox;

PROCEDURE NewCheckBox*;
VAR F: CheckBox;
BEGIN
	NEW(F); InitCheckBox(F); Objects.NewObj := F;
END NewCheckBox;

(* ========== SLIDERS ========= *)

PROCEDURE SliderUpdateModel(F: Slider);
VAR A: Objects.AttrMsg;
BEGIN
	IF F.obj # NIL THEN
		A.id := Objects.get; Field(F, A.name); A.class := Objects.Inval; A.res := -1;
		F.obj.handle(F.obj, A);
		IF A.res >= 0 THEN
			IF A.class = Objects.Int THEN F.val := A.i
			ELSIF A.class = Objects.String THEN Strings.StrToInt(A.s, F.val)
			ELSIF A.class = Objects.Real THEN F.val := ENTIER(A.x)
			ELSIF A.class = Objects.LongReal THEN F.val := ENTIER(A.y)
			END
		END
	END
END SliderUpdateModel;

PROCEDURE SliderSetModel(F: Slider);
VAR A: Objects.AttrMsg;
BEGIN
	IF F.obj # NIL THEN
		A.id := Objects.set; Field(F, A.name); A.class := Objects.Int; A.i := F.val; A.res := -1;
		F.obj.handle(F.obj, A)
	END
END SliderSetModel;

PROCEDURE SliderAttr(F: Slider; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("BasicGadgets.NewSlider", M.s); M.res := 0
		ELSIF M.name = "Min" THEN M.class := Objects.Int; M.i := F.min; M.res := 0
		ELSIF M.name = "Max" THEN M.class := Objects.Int; M.i := F.max; M.res := 0
		ELSIF M.name = "Value" THEN M.class := Objects.Int; M.i := F.val; M.res := 0
		ELSIF M.name = "LineupHY" THEN M.class := Objects.Int; M.i := F.H DIV 2 - 5; M.res := 0
		ELSIF M.name = "Field" THEN ForceString(F, M)
		ELSIF M.name = "Cmd" THEN ForceString(F, M)
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Min" THEN
			IF M.class = Objects.Int THEN F.min := M.i; M.res := 0 END
		ELSIF M.name = "Max" THEN
			IF M.class = Objects.Int  THEN F.max := M.i; M.res := 0 END
		ELSIF M.name = "Value" THEN
			IF M.class = Objects.Int THEN
				F.val := M.i;
				IF (F.obj # NIL) THEN SliderSetModel(F); Gadgets.Update(F.obj) END;
				M.res := 0;
			END;
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Min"); M.Enum("Max"); M.Enum("Value"); M.Enum("Field"); M.Enum("Cmd"); Gadgets.framehandle(F, M)
	END
END SliderAttr;

PROCEDURE RestoreSlider(R: Display3.Mask; F: Slider; x, y, w, h: INTEGER);
BEGIN
	IF F.min = F.max THEN F.max := F.min + 1 END;
	F.BW := Min(w, h);
	F.B := Effects.BarPos(x, y, w, h, F.BW, F.min, F.max, F.val);
	Effects.Bar(R, x, y, w, h, F.B, F.BW);
	IF Gadgets.selected IN F.state THEN Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint); END; 
END RestoreSlider;

PROCEDURE CopySlider*(VAR M: Objects.CopyMsg; from, to: Slider);
BEGIN
	Gadgets.CopyFrame(M, from, to); to.min := from.min; to.max := from.max; to.val := from.val;
	to.B := from.B; to.BW := from.BW;
END CopySlider;

PROCEDURE PrintSlider(F: Slider; VAR M: Display.DisplayMsg);
VAR R: Display3.Mask; x, y, w, h, X0, Y0, B, BW: INTEGER;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	x := M.x; y := M.y; w := P(F.W); h := P(F.H);
	Printer3.FilledRect3D(R,Display3.bottomC,Display3.topC, 12, x,y,w,h,1,Display.replace);
	
	BW := Min(w, h);
	B := Effects.BarPos(x, y, w, h, BW, F.min, F.max, F.val);
	IF w > h THEN X0 := B + 1; Y0 := Min(BW,w-2) 
	ELSE Y0 := B + 1; X0 :=Min(BW,h-2) END;
	
	IF h > w THEN
		Printer3.FilledRect3D(R,Display3.topC,Display3.bottomC,Display3.groupC,x+1, Y0, w-2,X0,1,Display.replace);
		IF w > P(6) THEN
			Printer3.ReplConst(R,Display3.bottomC,x+3,Y0 + X0 DIV 2, w - 6,1,Display.replace);
			Printer3.ReplConst(R,Display3.topC,x+3,Y0 + X0 DIV 2-1, w - 6,1,Display.replace);
		END;
	ELSE
		Printer3.FilledRect3D(R,Display3.topC,Display3.bottomC,Display3.groupC,X0,y+1,Y0,h-2,1,Display.replace);
		IF h >P(6) THEN
			Printer3.ReplConst(R,Display3.bottomC,X0+ Y0 DIV 2-1, y+3, 1,h - 6,Display.replace);
			Printer3.ReplConst(R,Display3.topC,0+ Y0 DIV 2, y+3, 1, h- 6,Display.replace);
		END
	END;
END PrintSlider;

PROCEDURE SliderHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h: INTEGER; F2: Slider;  
	R: Display3.Mask;
BEGIN
	WITH F: Slider DO
		IF M IS  Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO SliderAttr(F, M) END;
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					WriteVersion(M.R);
					Files.WriteLInt(M.R, F.min); Files.WriteLInt(M.R, F.max); Files.WriteLInt(M.R, F.val);
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN
					ReadVersion(M.R);
					Files.ReadLInt(M.R, F.min); Files.ReadLInt(M.R, F.max); Files.ReadLInt(M.R, F.val);
					Gadgets.framehandle(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F2); F.stamp := M.stamp; F.dlink := F2; CopySlider(M, F, F2); M.obj := F2
				END
			END;
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF M.res >= 0 THEN RETURN END;
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
				IF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg  DO
						IF M.device = Display.screen THEN
							IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
								Gadgets.MakeMask(F, x, y,M.dlink,  R);
								RestoreSlider(R, F, x, y, w, h);
							ELSIF (M.id = Display.area) & (M.F = F) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R); 
								Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
								RestoreSlider(R, F, x, y, w, h);
							END
						ELSIF M.device = Display.printer THEN PrintSlider(F, M)
						END
					END
				ELSIF M IS Gadgets.UpdateMsg THEN
					WITH M: Gadgets.UpdateMsg  DO
						IF F.obj # NIL THEN F.obj.handle(F.obj, M) END;
						IF M.obj = F.obj THEN
							IF F.stamp # M.stamp THEN F.stamp := M.stamp; SliderUpdateModel(F) END;
							Gadgets.MakeMask(F, x, y, M.dlink, R);
							RestoreSlider(R, F, x, y, w, h)
						ELSE Gadgets.framehandle(F, M)
						END
					END
				ELSIF M IS Display.ControlMsg THEN (*!!! *)
					WITH M: Display.ControlMsg DO
						IF F.obj # NIL THEN F.obj.handle(F.obj, M) END;
						IF (F.obj # NIL) & (M.id = Display.restore) THEN
							SliderUpdateModel(F)
						END
					END
				ELSIF M IS Oberon.InputMsg THEN
					WITH M: Oberon.InputMsg DO
						IF (M.id = Oberon.track) & (1 IN M.keys) & Gadgets.InActiveArea(F, M) THEN
							Gadgets.MakeMask(F, x, y, M.dlink, R);
							F.B := Effects.BarPos(x, y, w, h, F.BW, F.min, F.max, F.val);
							Effects.TrackBar(R, M.keys, M.X, M.Y, x, y, w, h, F.B, F.BW);
							F.val := Effects.BarValue(x, y, w, h, F.B, F.BW, F.min, F.max);
							IF (F.obj # NIL) THEN
								SliderSetModel(F); Gadgets.Update(F.obj);
							ELSE
								Gadgets.Update(F);
							END;
							 Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL);
							M.res := 0;
						ELSIF ~(Gadgets.selected IN F.state) THEN
							Gadgets.framehandle(F, M);
						END; 
					END;
				ELSE
					Gadgets.framehandle(F, M);
				END;
			END;
		ELSE
			Gadgets.framehandle(F, M);
		END;
	END;
END SliderHandler;

PROCEDURE InitSlider*(S: Slider);
BEGIN S.min := 0; S.max := 100; S.val := 50; S.W := 30; S.H := 60; S.handle := SliderHandler;
	S.BW := Min(S.W, S.H)
END InitSlider;

PROCEDURE NewSlider*;
VAR S: Slider;
BEGIN
	NEW(S); InitSlider(S); Objects.NewObj := S;
END NewSlider;

(** Indicate to the display space that the value of obj has changed. Calls Gadgets.Update. *)
PROCEDURE SetValue*(obj: Objects.Object);
BEGIN Gadgets.Update(obj)
END SetValue;

(*  --- *)

(** Separate a button from its look (F.obj). The object is removed and inserted at the caret. Only functions when the button has a (consumed) gadget as a caption. *)
PROCEDURE Break*;
VAR M: Display.SelectMsg; t: Display.Frame; B: Button;
BEGIN
	M.F := NIL; M.id := Display.get; M.time := -1; M.obj := NIL; Display.Broadcast(M);
	IF (M.time > 0) & (M.obj # NIL) THEN
		IF M.obj IS Button THEN
			B := M.obj(Button);
			IF (B.look # NIL) THEN
				IF B.look IS Display.Frame THEN
					t := B.look(Display.Frame); B.look := NIL; Gadgets.Update(B); Gadgets.Integrate(t)
				ELSE B.look := NIL; Gadgets.Update(B)
				END;
			END
		END
	END
END Break;

BEGIN Texts.OpenWriter(W) 
END BasicGadgets.