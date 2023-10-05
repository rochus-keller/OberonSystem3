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

MODULE HPCalc;	(** portable *)	(** prk   **)

(*
	Welcome to HPCalc.
	HPCalc is a small calculator gadget for Oberon System3.
	
	To create the HPCalc panel, call
		HPCalc.Open
	you can then store the panel and use it.
	
	Created, updated and maintained by Patrik Reali (reali@inf.ethz.ch)
	
	
	HPCalc history:
	
	2.04 / 
		o accept hex numbers in every mode (xyzH)
		o accept dec numbers in every mode (xyz.)
		o SignOn costant not exported anymore (otherwise the sym file is changed!)
	
	2.03 / 05.02.97
		o new functions: ARCSIN, ARCCOS, ARCTAN
		o SQRT moved to Log functions. Caption is x^.5
		o new function LOG
		o display only "usable" functions
		o a function with no name forces a new line in the button list
		o no button panel showed, if no button used!
		o display the stack usage (-> found bug in ProgressMeter!! )
		o remove sub panel when the mode changes (the allowed functions also change! )
		o new functions: Integer ABS, integer MOD
		
	2.02 / 24.01.97
		o new functions: LSH1, LSHN, ROT1, ROTN
		o E -> CONST_E, PI -> CONST_PI, otherwise E is taken as 0Eh
		o new functions: TAN, 1/x, x^2, x^y
		o new functions: SINH, COSH, TANH
		o module imports cleaned. Out is not used anymore
	
	2.01 / 23.01.97
		o Sub-Panels are now locked
		o Logical -> Logic
		o Sub-Panels are replaced, not added
		o Gadgets sizes are now partially parametrized, to simplify layout changes
			o Smaller buttons
			o Larger TextFields
		o Functions appended at end of the list, to preserve the insertion sequence
		o Int->Real, Real->Int without loss of data. The stack is changed: every element takes 2 places in the stack now!
		o RotateStack function
		o small bug in the removal of the functions
		o the function panel was to big when full
		o intercept division by 0 error (found by J. Supcik)
		
	2.0 / 20.01.97
		o all the state information are hold in a model bound to the panel fields.
		o all refreshes are done by gadgets itself
		o new layout of the panel:  only the stack function are fixed. Other function can be viewed in an extension of the panel
		o complete restructuration of the module
		o some conversions routines have been moved in the Conversions.Mod module
		o automatic panel extension to contain the function set
		o functions are now grouped together in a FunctionClass set.
	
	1.3 / 20.09.96
		o Dupl, Drop commands
		o A Swap operation which swaps the TOS and TOS-1 (proposed by pjm)
		o When clicking on Integer it displays "switch to base mode".  This should be "switched to integer mode". (found by PM)
		o Execute Reset and then any operation which takes a parameter.  Garbage is displayed at the top of the stack. (found by PM)
		o use LONGREAL instead of REAL, everywhere. (PM proposal)
		o small improvement in the OutS/OutR/OutI procedures
		o improved parsing: in hex view mode, the input is interpreted as hex input.
		o copy of partial results now supported
		o when the panel is closed and re-opened all the modes are resetted.
		
	1.2 / 05.06.96
		o rename Base with Integer (PM proposal)
		o insert a NEG function in the Integer mode (PM proposal)
		o DIV and SUB are wrong in Integer mode (found by PM)
		o multiple instructions on one line (PS proposal)
		o clear the unused cells after every operation (not only the first one)
		o DROP command inserted (PS proposal)
		
	1.1 / 04.06.96 prk
		o changed the stack. Uses Reals and BIT instead of SYSTEM to convert to and from LONGINT
		o View modes (Decimal or Hex) inserted
		o Name changed to HPCalc
		o Output fields are now locked
			
*)

IMPORT Conversions, Panels, Documents, PanelDocs, Desktops, BIT, Reals, MathL, Texts, Strings, Oberon, Objects, Display,
	Attributes, Links, Gadgets, TextFields;
 
CONST
	PanelLogo = "Calculator 2.04";
	SignOn = "HPCalc 2.04 -- PRK";

	StackSize = 64;

	(* Modes *)
	Real = 0; Integer = 1;
	
	IntOnly = {Integer}; RealOnly = {Real}; IntReal = {Integer, Real};
	
	(* Status *)
	OK = 0; Error = 1; Undef = 2;
	
	(* Sizes and Constraints *)
	(* Objects sizes *)
	TextFieldW = 120;
	ButtonH = 20; ButtonW = 40;
	PanelW = 330;
	
	(* Columns positions *)
	C1 = 10; C2 = 140; C3 = 270;

TYPE
	Name = ARRAY 32 OF CHAR;
	
	CalcModel = POINTER TO CalcModelDesc;
	CalcModelDesc = RECORD (Gadgets.ObjDesc)
		Stack: ARRAY StackSize OF LONGINT;
		TOS: LONGINT;
		Mode, Base: SHORTINT;
		Status: SHORTINT;
		SubPanel: Objects.Object;	(* functions displayed, used to remove the functions *)
	END;
	
	Functions = POINTER TO FunctionsDesc;
	FunctionsDesc = RECORD
		name, caption: Name;
		mode: SET;
		list: Functions;
	END;
	
	FunctionClass = POINTER TO FunctionClassDesc;
	FunctionClassDesc = RECORD (FunctionsDesc)
		next: FunctionClass
	END;
	
VAR
	StatusMsg: ARRAY 3 OF Name;
	Func: FunctionClass;
	W: Texts.Writer;
	
(* ============================================================ *)
(* ---------------------- Model Handling Functions ----------------- *)


(* ---------------------- Stack Handling Functions ----------------- *)
	
PROCEDURE Push(m: CalcModel; i: LONGINT);	(* push to the stack *)
BEGIN
	m.Stack[m.TOS] := i;
	IF m.TOS < StackSize-1 THEN INC(m.TOS)
	ELSE m.Status := Error
	END
END Push;

PROCEDURE Pop(m: CalcModel; VAR i: LONGINT);	(* pop from the stack *)
BEGIN
	IF m.TOS > 0 THEN DEC(m.TOS); i := m.Stack[m.TOS]
	ELSE m.Status := Error
	END
END Pop;

PROCEDURE PushI(m: CalcModel; i: LONGINT);	(* push Longint from the stack *)
BEGIN	Push (m, i); Push (m, 0)
END PushI;

PROCEDURE PopI(m: CalcModel; VAR i: LONGINT);	(* pop Longint from the stack *)
	VAR dummy: LONGINT;
BEGIN	Pop (m, dummy); Pop (m, i)
END PopI;

PROCEDURE PushR(m: CalcModel; r: LONGREAL);	(* push Longreal on the stack *)
	VAR h, l: LONGINT;
BEGIN
	Reals.IntL (r, h, l); Push (m, h); Push (m, l)
END PushR;

PROCEDURE PopR(m: CalcModel; VAR r: LONGREAL);	(* pop Longreal from the stack *)
	VAR h, l: LONGINT;
BEGIN
	Pop (m, l); Pop (m, h); r := Reals.RealL (h, l)
END PopR;

PROCEDURE RotateStack (m: CalcModel);
	VAR i, h, l: LONGINT;
BEGIN
	IF (m.TOS <= 2) THEN RETURN END;	(* to few elements!! *)
	h := m.Stack[0]; l := m.Stack[1];
	i := 2;
	WHILE (i < m.TOS) DO m.Stack[i-2] := m.Stack[i]; INC (i) END;
	m.Stack[i-2] := h; m.Stack[i-1] := l;
END RotateStack;

PROCEDURE RemoveSub (m: CalcModel);
	VAR ctxt, o: Objects.Object;
BEGIN
	IF m.SubPanel # NIL THEN
		Links.GetLink(m.SubPanel, "Context", ctxt);
		o := Gadgets.context; Gadgets.context := m.SubPanel; m.SubPanel.dlink := ctxt;
		PanelDocs.RemovePanel; Gadgets.context := o; m.SubPanel := NIL
	END
END RemoveSub;

PROCEDURE ResetStack (m: CalcModel);
BEGIN
	m.TOS := 0; m.Status := OK;
END ResetStack;

PROCEDURE ResetModel (m: CalcModel);
BEGIN
	ResetStack (m);
	m.Mode := Real; m.Base := 10;
	RemoveSub (m);
END ResetModel;

PROCEDURE ChangeMode (m: CalcModel; from, to: SHORTINT);
	VAR i: LONGINT;
	
	PROCEDURE Convert (VAR h, l: LONGINT);
		VAR r: LONGREAL;
	BEGIN
		IF (from = Real) & (to = Integer) THEN
			r := Reals.RealL (h, l); h := ENTIER(r); l := 0
		ELSIF (from = Integer) & (to = Real) THEN
			Reals.IntL (h, h, l)
		ELSE HALT (99)
		END;
	END Convert;
	
BEGIN
	IF from = to THEN RETURN END;
	i := 0;
	WHILE i < m.TOS DO
		Convert (m.Stack[i], m.Stack[i+1]); INC (i,2)
	END;
END ChangeMode;

PROCEDURE GetModelValue (F: CalcModel; pos: INTEGER; VAR s: ARRAY OF CHAR): INTEGER;	(* get textual value from stack *)
	VAR	lr: LONGREAL; l, h: LONGINT;
BEGIN
	(* Check Range *)
	IF (F.TOS <= pos*2) THEN
		COPY ("", s); IF pos < 4 THEN RETURN 0	ELSE RETURN -1	END
	END;
	IF F.Mode = Real THEN
		l := F.Stack[F.TOS - 2*pos - 1];  h := F.Stack[F.TOS - 2*pos - 2];
		lr := Reals.RealL(h, l); Conversions.RealToStr (lr, s, F.Base)
	ELSIF F.Mode = Integer THEN	Conversions.IntToStr (F.Stack[F.TOS - 2*pos - 2], s, F.Base)
	ELSE HALT (99)
	END;
	RETURN 0 
END GetModelValue;

PROCEDURE HandleAttributes (F: CalcModel; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN
			M.class := Objects.String; COPY("HPCalc.NewModel", M.s); M.res := 0
		ELSIF M.name = "Mode" THEN
			M.class := Objects.Int; M.i := F.Mode; M.res := 0;
		ELSIF M.name = "Base" THEN
			M.class := Objects.Int; M.i := F.Base; M.res := 0;
		ELSIF M.name = "Status" THEN
			M.class := Objects.String; COPY (StatusMsg[F.Status], M.s); M.res := 0;
		ELSIF M.name = "TOS" THEN
(*
			M.class := Objects.String; Strings.IntToStr (F.TOS, M.s); M.res := 0;
*)
			M.class := Objects.Int; M.i := F.TOS; M.res := 0;
		ELSIF (M.name[0] = "S") & (M.name[2] = 0X) THEN
			M.class := Objects.String; M.res := GetModelValue (F, ORD(M.name[1]) - ORD ("0"), M.s)
		ELSE Gadgets.objecthandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Mode" THEN
			IF (M.class = Objects.Int) & ((M.i = Real) OR (M.i = Integer)) THEN
				ChangeMode (F, F.Mode, SHORT(SHORT(M.i)));
				F.Mode := SHORT(SHORT(M.i)); M.res := 0; 
				IF (F.Mode = Real) & (F.Base = 2) THEN F.Base := 10 END;
				RemoveSub (F)
			ELSE Gadgets.objecthandle(F, M) END
		ELSIF M.name = "Base" THEN
			IF (M.class = Objects.Int) & (((F.Mode # Real) & (M.i = 2)) OR (M.i = 10) OR (M.i = 16)) THEN
				F.Base := SHORT(SHORT(M.i)); M.res := 0
			ELSE Gadgets.objecthandle(F, M) END
		ELSE
			Gadgets.objecthandle(F, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("S0"); M.Enum("S1"); M.Enum("S2"); M.Enum("S3");
		M.Enum("Mode"); M.Enum("Base"); M.Enum("Status"); M.Enum("TOS");
		Gadgets.objecthandle(F, M)
	END
END HandleAttributes;

PROCEDURE ModelHandler (obj: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	IF obj IS CalcModel THEN
		WITH obj: CalcModel DO
			IF M IS Objects.AttrMsg THEN	HandleAttributes (obj, M(Objects.AttrMsg))
			ELSE	Gadgets.objecthandle (obj, M)
			END
		END
	END
END ModelHandler;

PROCEDURE NewModel*;	(* allocate a new CalcModel *)
	VAR F: CalcModel;
BEGIN
	NEW (F); ResetModel (F); F.handle := ModelHandler; Objects.NewObj := F
END NewModel;

PROCEDURE GetModel(VAR dlink: Objects.Object):CalcModel;
	VAR o: Objects.Object; name: ARRAY 64 OF CHAR;
BEGIN
	dlink := Gadgets.context;
	IF dlink # NIL THEN Attributes.GetString(dlink, "Name", name) END;
	WHILE (dlink # NIL) & (name # "HPCalc") DO
		dlink := dlink.dlink;
		IF dlink # NIL THEN Attributes.GetString(dlink, "Name", name) END
	END;
	o := Gadgets.FindObj (dlink, "CM");
	RETURN o(CalcModel)
END GetModel;

(* ============================================================ *)
(*	The basic functions of the calculator *)
	
PROCEDURE DoRealFunction (m: CalcModel; VAR FN: ARRAY OF CHAR);
	VAR	a, b, r: LONGREAL;
BEGIN
	IF FN = "ABS" THEN 
		PopR (m, b); r := ABS (b)
	ELSIF FN = "MAXL" THEN
		r := MAX(LONGINT)
	ELSIF FN = "MINL" THEN
		r := MIN(LONGINT)
	ELSIF FN = "SIN" THEN
		PopR (m, b); r := MathL.sin (b)
	ELSIF FN= "COS" THEN 
		PopR (m, b); r := MathL.cos (b)
	ELSIF FN = "TAN" THEN
		PopR (m, b); r := MathL.sin (b) / MathL.cos (b)
	ELSIF FN = "ARCTAN" THEN
		PopR (m, b); r := MathL.arctan (b)
	ELSIF FN = "ARCSIN" THEN
		PopR (m, b); r := MathL.arctan (b/MathL.sqrt(1-b*b))	(* <- from "Taschenbuch der Mathematik *)
	ELSIF FN = "ARCCOS" THEN
		PopR (m, b); r := MathL.pi/2 - MathL.arctan (b/MathL.sqrt(1-b*b))	(* <- from "Taschenbuch der Mathematik *)
	ELSIF FN = "SINH" THEN
		PopR (m, b); r := (MathL.exp(b) - MathL.exp(-b))/2
	ELSIF FN = "COSH" THEN
		PopR (m, b); r := (MathL.exp(b) + MathL.exp(-b))/2
	ELSIF FN = "TANH" THEN
		PopR (m, b); r := (MathL.exp(b) - MathL.exp(-b))/(MathL.exp(b) + MathL.exp(-b))
	ELSIF FN = "CONST_E" THEN
		r := MathL.e
	ELSIF FN = "EXP" THEN
		PopR (m, b); r := MathL.exp (b)
	ELSIF FN = "LN" THEN
		PopR (m, b); r := MathL.ln (b)
	ELSIF FN = "LOG" THEN
		PopR (m, b); r := MathL.ln (b) / MathL.ln (10)
	ELSIF FN = "HOCH2" THEN
		PopR (m, b); r := b*b
	ELSIF FN = "HOCHY" THEN
		PopR (m, b); PopR (m, a); r := MathL.exp ( b*MathL.ln (a))
	ELSIF FN = "CONST_PI" THEN
		r := MathL.pi
	ELSIF FN = "SQRT" THEN 
		PopR (m, b); r := MathL.sqrt (b)
	ELSIF FN = "+" THEN
		PopR (m, b); PopR (m, a); r := a+b
	ELSIF FN = "-" THEN
		PopR (m, b); PopR (m, a); r := a-b
	ELSIF FN = "*" THEN
		PopR (m, b); PopR (m, a); r:= a*b
	ELSIF FN = "/" THEN
		PopR (m, b); PopR (m, a); 
		IF b = 0 THEN m.Status := Error ELSE r := a/b END
	ELSIF FN= "NEG" THEN 
		PopR (m, b); r := -b
	ELSIF FN= "INV" THEN 
		PopR (m, b);
		IF b = 0 THEN m.Status := Error ELSE r := 1/b END
	ELSE m.Status := Undef; r := 0.0
	END;
	IF m.Status = OK THEN PushR (m, r) END
END DoRealFunction;

PROCEDURE DoIntegerFunction (m: CalcModel; VAR FN: ARRAY OF CHAR);
	VAR a, b, r: LONGINT;
BEGIN
	IF FN = "+" THEN
		PopI (m, b); PopI (m, a); r := a+b
	ELSIF FN = "MAXL" THEN
		r := MAX(LONGINT)
	ELSIF FN = "MINL" THEN
		r := MIN(LONGINT)
	ELSIF FN = "-" THEN
		PopI (m, b); PopI (m, a); r := a-b
	ELSIF FN = "*" THEN
		PopI (m, b); PopI (m, a); r := a*b
	ELSIF FN = "/" THEN
		PopI (m, b); PopI (m, a);
		IF b = 0 THEN m.Status := Error ELSE r := a DIV b END
	ELSIF FN = "MOD" THEN
		PopI (m, b); PopI (m, a); r := a MOD b
	ELSIF FN = "ABS" THEN
		PopI (m, b); b := ABS(b)
	ELSIF FN = "AND" THEN
		PopI (m, b); PopI (m, a); r := BIT.LAND(a, b)
	ELSIF FN = "OR" THEN
		PopI (m, b); PopI (m, a); r := BIT.LOR(a, b)
	ELSIF FN = "XOR" THEN
		PopI (m, b); PopI (m, a); r := BIT.LXOR(a, b)
	ELSIF FN = "NOT" THEN
		PopI (m, b); r := -b-1
	ELSIF FN = "NEG" THEN
		PopI (m, b); r := -b
	ELSIF FN = "LSH1" THEN
		PopI (m, b); r := BIT.LLSH (b, 1)
	ELSIF FN = "LSHN" THEN
		PopI (m, a); PopI (m, b); r := BIT.LLSH (b, SHORT(SHORT(a)))
	ELSIF FN = "ROT1" THEN
		PopI (m, b); r := BIT.LROT (b, 1)
	ELSIF FN = "ROTN" THEN
		PopI (m, a); PopI (m, b); r := BIT.LROT (b, SHORT(SHORT(a)))
	ELSE
		m.Status := Undef
	END;
	IF m.Status = OK THEN PushI (m, r) END
END DoIntegerFunction;

PROCEDURE Calc;
	VAR r, r1: LONGREAL; tmp: ARRAY 64 OF CHAR; j, l: LONGINT; hex, number: BOOLEAN; ch: CHAR; R: Texts.Reader;
		m: CalcModel; o, dlink: Objects.Object;
	
	PROCEDURE Read;
	BEGIN
		Texts.Read (R, ch);
		IF R.eot THEN ch := 0X END;
		(*	IF Strings.IsLetter (ch) THEN ch := CAP (ch) END	*)
		ch := Strings.UpperCh(ch)
	END Read;
	
BEGIN
	o := GetModel(dlink);
	IF o = NIL THEN RETURN END;
	m := o(CalcModel);
	m.Status := OK;
	Texts.OpenReader (R, Oberon.Par.text, Oberon.Par.pos); Read;
	LOOP
		WHILE ch=20X DO Read END;
		IF ch = 0X THEN EXIT END;
		j := 0; number := TRUE; hex := FALSE;
		IF (ch = "-") & (j=0) THEN tmp[0] := "-"; j := 1; Read END;
		WHILE (ch # 20X) & (ch # 0X) DO
			number := number & ~hex & (Strings.IsHexDigit(ch) OR (ch = ".") OR (ch = "H"));
			hex := ch = "H";
			tmp[j] := ch; INC (j);
			Read
		END;
		tmp[j] := 0X;
		number := number & ~(tmp="-");
		IF number THEN
			IF hex THEN
				tmp[j-1] := 0X;	(*delete H*)
				Conversions.StrToInt (tmp, l, 16);
				IF m.Mode = Real THEN PushR(m , l) ELSE PushI(m, l) END
			ELSIF tmp[j-1] = "." THEN
				Conversions.StrToInt (tmp, l, 10);
				IF m.Mode = Real THEN PushR(m , l) ELSE PushI(m, l) END
			ELSIF m.Mode = Real THEN
				Strings.StrToReal (tmp, r); PushR (m, r)
			ELSE
				Conversions.StrToInt (tmp, l, m.Base); PushI (m, l)
			END
		ELSIF tmp = "RESET" THEN
			ResetModel (m)
		ELSIF tmp = "CLEAR" THEN
			ResetStack (m)
		ELSIF (tmp = "DROP") & (m.TOS > 0) THEN 
			PopR(m, r)
		ELSIF (tmp = "DUPL") & (m.TOS > 0) THEN 
			PopR(m, r); PushR(m, r); PushR(m, r)
		ELSIF (tmp = "SWAP") & (m.TOS > 3) THEN 
			PopR(m, r); PopR(m, r1); PushR(m, r); PushR(m, r1)
		ELSIF (tmp = "ROTATE") THEN
			RotateStack (m)
		ELSE
			IF m.Mode = Real THEN DoRealFunction (m, tmp)
			ELSIF m.Mode = Integer THEN DoIntegerFunction (m, tmp)
			ELSE m.Status := Error
			END
		END
	END;
	o := Gadgets.FindObj (dlink, "Input");
	Attributes.SetString (o, "Value", ""); Gadgets.Update (o);
	Gadgets.Update (m)
END Calc;

(* ============================================================ *)
(*	Some gadgets common things *)

PROCEDURE NewButton(caption, cmd: ARRAY OF CHAR):Objects.Object;	(* here, to make every button the same size *)
	VAR v: Objects.Object;
BEGIN
	v := Gadgets.CreateObject("BasicGadgets.NewButton");
	v(Gadgets.Frame).H := ButtonH; v(Gadgets.Frame).W := ButtonW;
	Attributes.SetString (v, "Caption", caption); Attributes.SetString (v, "Cmd", cmd);
	RETURN v
END NewButton;

(* ============================================================ *)
(*	Function List handling *)

PROCEDURE FindClass (class: ARRAY OF CHAR): Functions;
	VAR p: FunctionClass;
BEGIN
	p := Func;
	WHILE (p.next # NIL) & (p.next.name # class) DO p := p.next END;
	IF p.next = NIL THEN NEW(p.next); COPY (class, p.next.name); p.next.list := NIL; p.next.mode := {} END;
	RETURN p.next
END FindClass;

PROCEDURE NewFunction (class, name, caption: ARRAY OF CHAR; mode: SET);
	VAR p, q: Functions;
BEGIN
	p := FindClass (class); p.mode := p.mode + mode;
	
	(* it's inefficient, but the new entries are appended at the end of the structure, to
		preserve the insertion order. *)
	NEW (q); COPY (name, q.name); COPY (caption, q.caption); q.mode := mode;
	WHILE p.list # NIL DO p := p.list END;
	q.list := p.list; p.list := q
END NewFunction;

(** Remove the functions buttons from the main panel *)
PROCEDURE RemoveFunctions*;
	VAR parent: Objects.Object; m: CalcModel;
BEGIN
	m := GetModel(parent);
	IF (m = NIL) OR (m.SubPanel = NIL) THEN RETURN END;
	m.SubPanel := NIL;
	PanelDocs.RemovePanel
END RemoveFunctions;

(** Append the functions buttons to the main panel *)
PROCEDURE ShowFunctions*;
	VAR class, tmp: ARRAY 32 OF CHAR; f: Functions; obj: Panels.Panel; S: Texts.Scanner; v, o: Objects.Object;
			x, y: INTEGER; ctxt, new: Display.Frame; locked: BOOLEAN; h: INTEGER;
			cm: Display.ConsumeMsg; mm: Display.ModifyMsg; ctrl: Display.ControlMsg;
			m: CalcModel;
			
BEGIN
	(* get function class *)
	Texts.OpenScanner (S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan (S);
	IF S.class # Texts.Name THEN RETURN END;
	COPY (S.s, class); f := FindClass (class);
	
	(* get the model *)
	o := Gadgets.FindObj (Gadgets.context, "CM"); m := o(CalcModel);
	
	(* Delete the old Sub-Panel *)
	RemoveSub (m);
	
	(* Create the panel *)
	Panels.NewPanel; obj := Objects.NewObj(Panels.Panel);
	obj.W := PanelW;
	
	x := C1-40; y := -3*ButtonH DIV 2; v := NIL;
	f := f.list;
	WHILE f # NIL DO
		IF f.name = "" THEN
			x := C1-40; INC (y, -ButtonH)
		ELSIF m.Mode IN f.mode THEN
			INC (x, 40);
			IF x >= C3 - ButtonH THEN x := C1; INC (y, -ButtonH) END;
			tmp := "HPCalc.Do "; Strings.Append (tmp, f.name);
			v := NewButton (f.caption, tmp); Panels.InsertChild (obj, v(Gadgets.Frame), x, y)
		END;
		f := f.list
	END;
	IF v = NIL THEN RETURN END;	(* no buttons inserted *)
	obj.H := ButtonH DIV 2 - y;
	v := NewButton ("Close", "HPCalc.RemoveFunctions");
	Panels.InsertChild (obj, v(Gadgets.Frame), C3, -3*ButtonH DIV 2);
	Attributes.SetBool (obj, "Locked", TRUE);
	Links.SetLink(obj, "Context", Gadgets.context);
	m.SubPanel := obj;
	
	(* Integrate the panel *)
	IF (obj # NIL) & (Gadgets.context # NIL) & (Gadgets.context IS Display.Frame) THEN
		ctxt := Gadgets.context(Display.Frame);
		Attributes.GetBool(ctxt, "Locked", locked);
		Attributes.SetBool(ctxt, "Locked", FALSE);
		new := obj(*(Display.Frame)*);
		h := new.H;
		cm.F := ctxt; cm.id := Display.drop; cm.obj := new; cm.u := 0; cm.v := -(ctxt.H + h);
		Display.Broadcast(cm);
		Attributes.SetBool(ctxt, "Locked", locked);
		Objects.Stamp(ctrl); ctrl.dlink := NIL; ctrl.F := NIL; ctrl.x := 0; ctrl.y := 0; ctrl.id := Display.restore; ctrl.res := -1;
		new.handle(new, ctrl);
		mm.F := ctxt; mm.id := Display.move; mm.mode := Display.display;
		mm.X := ctxt.X; mm.Y := ctxt.Y - h; mm.W := ctxt.W; mm.H := ctxt.H + h;
		mm.dX := 0; mm.dY := -h; mm.dW := 0; mm.dH := h;
		Display.Broadcast(mm)
	END
END ShowFunctions;

(* ============================================================ *)
(*	interactive part of the program (gadget) *)

(* Locked Text Field - The handler of a normal text field is overriden, to suppress the handling of user changes in the field *)
PROCEDURE LTFHandle (F: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	IF M IS Objects.AttrMsg THEN
		IF M(Objects.AttrMsg).id = Objects.get THEN
			IF M(Objects.AttrMsg).name = "Gen" THEN
				WITH M: Objects.AttrMsg DO M.class := Objects.String; COPY("HPCalc.NewLockedTF", M.s); M.res := 0
				END
			ELSE TextFields.TextFieldHandler (F, M)
			END
		ELSE TextFields.TextFieldHandler (F, M)
		END
	ELSIF M IS Oberon.InputMsg THEN 
		IF (M(Oberon.InputMsg).id = Oberon.track) & ~(2 IN M(Oberon.InputMsg).keys) THEN TextFields.TextFieldHandler (F, M)
		ELSE Gadgets.framehandle (F, M)(* don't send this to the original handler!! *)
		END
	ELSE TextFields.TextFieldHandler(F, M)
	END
END LTFHandle;

PROCEDURE NewLockedTF*;	(* allocate a new Locked Text Field *)
	VAR F: TextFields.TextField;
BEGIN
	NEW (F); TextFields.InitTextField (F); F.handle := LTFHandle; Objects.NewObj := F
END NewLockedTF;

PROCEDURE NewView (gen: ARRAY OF CHAR; model: Objects.Object; field: ARRAY OF CHAR): Gadgets.Frame;
	VAR v: Objects.Object;
BEGIN
	IF gen = "BasicGadgets.NewButton" THEN v := NewButton("", "") ELSE v := Gadgets.CreateObject(gen) END;
	IF (gen = "HPCalc.NewLockedTF") OR (gen = "TextFields.NewTextField") THEN v(Gadgets.Frame).W := TextFieldW END;
	IF model # NIL THEN
		v(Gadgets.Frame).obj := model; Attributes.SetString (v, "Field", field);
	END;
	RETURN v(Gadgets.Frame);
END NewView;

(** HPCalc Panel generation *)
PROCEDURE New*;	(* create a new HPCalc panel *)
	VAR	p: Panels.Panel; c: CalcModel; v: Gadgets.Frame; f: FunctionClass; x, y: INTEGER; cmd: ARRAY 64 OF CHAR;

	PROCEDURE NewCommand (msg: ARRAY OF CHAR; x, y: INTEGER);
		VAR v: Objects.Object;
	BEGIN
		v := NewButton (msg, cmd); Panels.InsertChild (p, v(Gadgets.Frame), x, y);
	END NewCommand;
	
BEGIN
	NewModel; c := Objects.NewObj(CalcModel); Gadgets.NameObj (c, "CM");
	Panels.NewPanel; p := Objects.NewObj(Panels.Panel);
	p.W := PanelW; p.H := 170;
	
	(* Compose Panel *)
	(* the stack *)
	Panels.InsertChild (p, NewView ("HPCalc.NewLockedTF", c, "S3"), C1, -50);
	Panels.InsertChild (p, NewView ("HPCalc.NewLockedTF", c, "S2"), C1, -70);
	Panels.InsertChild (p, NewView ("HPCalc.NewLockedTF", c, "S1"), C1, -90);
	Panels.InsertChild (p, NewView ("HPCalc.NewLockedTF", c, "S0"), C1, -110);
	
	(* status *)
	Panels.InsertChild (p, NewView ("HPCalc.NewLockedTF", c, "Status"), C2, -150);

	(* input field *)
	v := NewView ("TextFields.NewTextField", NIL, ""); Attributes.SetString (v, "Cmd", "HPCalc.Do #Value");
	Gadgets.NameObj (v, "Input"); Panels.InsertChild (p, v, C1, -150);
	
	(* the panel name *)
	v := NewView ("TextFields.NewCaption", NIL, ""); Attributes.SetString (v, "Value", PanelLogo);
	Panels.InsertChild (p, v, C1, -25);
	
	(* mode switch *)
	v := NewView ("BasicGadgets.NewButton", c, "Mode"); Attributes.SetString (v, "YesVal", "0");
	Attributes.SetString (v, "SetVal", "0"); Attributes.SetString (v, "Caption", "Real");
	Panels.InsertChild (p, v, C3, -50);
	v := NewView ("BasicGadgets.NewButton", c, "Mode"); Attributes.SetString (v, "YesVal", "1");
	Attributes.SetString (v, "SetVal", "1"); Attributes.SetString (v, "Caption", "Integer");
	Panels.InsertChild (p, v, C3, -70);

	(* base switch *)
	v := NewView ("BasicGadgets.NewButton", c, "Base"); Attributes.SetString (v, "YesVal", "2");
	Attributes.SetString (v, "SetVal", "2"); Attributes.SetString (v, "Caption", "Bin");
	Panels.InsertChild (p, v, C3, -110);
	v := NewView ("BasicGadgets.NewButton", c, "Base"); Attributes.SetString (v, "YesVal", "10");
	Attributes.SetString (v, "SetVal", "10"); Attributes.SetString (v, "Caption", "Dec");
	Panels.InsertChild (p, v, C3, -130);
	v := NewView ("BasicGadgets.NewButton", c, "Base"); Attributes.SetString (v, "YesVal", "16");
	Attributes.SetString (v, "SetVal", "16"); Attributes.SetString (v, "Caption", "Hex");
	Panels.InsertChild (p, v, C3, -150);

	(* stack usage *)
	v := NewView ("ProgressMeters.NewFrame", c, "TOS"); Attributes.SetInt (v, "Max", StackSize);
	Attributes.SetInt (v, "Step", 1);
	Attributes.SetBool (v, "Marks", FALSE); Attributes.SetBool (v, "Labels", FALSE); v.W := 5; v.H := 80;
	Panels.InsertChild (p, v, C1+TextFieldW, -110);

	(* stack commands *)
	cmd := "HPCalc.Do #Caption";
	NewCommand ("RESET", C2, -50);
	NewCommand ("CLEAR", C2+ButtonW, -50);
	NewCommand ("DROP", C2+2*ButtonW, -50);
	NewCommand ("DUPL", C2, -70);
	NewCommand ("SWAP", C2+ButtonW,  -70);
	NewCommand ("ROTATE", C2+2*ButtonW,-70);

	(* function group commands *)
	cmd := "HPCalc.ShowFunctions #Caption";
	f := Func.next;
	x := C2; y := -90;
	WHILE f # NIL DO
		NewCommand (f.name, x, y); INC (x, ButtonW); f := f.next;
		IF x > C3-ButtonW THEN x := C2; DEC (y, ButtonH) END
	END;
	
	Attributes.SetBool (p, "Locked", TRUE); Attributes.SetString (p, "Name", "HPCalc");
	Objects.NewObj := p
END New;

(** HPCalc Document generation *)
PROCEDURE Open*;
	VAR D: Documents.Document; obj: Gadgets.Frame;
BEGIN
	NEW(D); New; obj := Objects.NewObj(Gadgets.Frame);
	D.Load := PanelDocs.LoadPanel; D.Store := PanelDocs.StorePanel; D.handle := PanelDocs.DocHandle;
	D.name := ""; D.W := obj.W; D.H := obj.H;
	Documents.Init(D, obj); D.name := "HPCalc.Panel";
	Desktops.ShowDoc(D)
END Open;

(** Process some operations. !! Must be called by the panel, because it uses context informations !! *)
PROCEDURE Do*;
BEGIN
	Calc;
END Do;

PROCEDURE Init;	(* module initialisation *)
BEGIN
	StatusMsg [0] := "done"; StatusMsg[1] := "error"; StatusMsg[2] := "undef instruction";
	
	NEW (Func);
	NewFunction ("Math", "+", "+", IntReal);
	NewFunction ("Math", "-", "-", IntReal);
	NewFunction ("Math", "*", "*", IntReal);
	NewFunction ("Math", "/", "/", IntReal);
	NewFunction ("Math", "", "", IntReal);
	NewFunction ("Math", "MOD", "MOD", IntOnly);
	NewFunction ("Math", "NEG", "NEG", IntReal);
	NewFunction ("Math", "ABS", "ABS", IntOnly);
	NewFunction ("Math", "INV", "1/x", RealOnly);
	NewFunction ("Math", "MAXL", "MAXL", IntReal);
	NewFunction ("Math", "MINL", "MINL", IntReal);

	NewFunction ("Logic", "AND", "AND", IntOnly);
	NewFunction ("Logic", "OR", "OR", IntOnly);
	NewFunction ("Logic", "XOR", "XOR", IntOnly);
	NewFunction ("Logic", "NOT", "NOT", IntOnly);
	NewFunction ("Logic", "", "", IntOnly);
	NewFunction ("Logic", "LSH1", "LSH 1", IntOnly);
	NewFunction ("Logic", "LSHN", "LSH n", IntOnly);
	NewFunction ("Logic", "ROT1", "ROT 1", IntOnly);
	NewFunction ("Logic", "ROTN", "ROT n", IntOnly);
	
	NewFunction ("Trig", "SIN", "SIN", RealOnly);
	NewFunction ("Trig", "COS", "COS", RealOnly);
	NewFunction ("Trig", "TAN", "TAN", RealOnly);
	NewFunction ("Trig", "ARCSIN", "ARCSIN", RealOnly);
	NewFunction ("Trig", "ARCCOS", "ARCCOS", RealOnly);
	NewFunction ("Trig", "ARCTAN", "ARCTAN", RealOnly);
	NewFunction ("Trig", "", "", RealOnly);
	NewFunction ("Trig", "SINH", "SINH", RealOnly);
	NewFunction ("Trig", "COSH", "COSH", RealOnly);
	NewFunction ("Trig", "TANH", "TANH", RealOnly);
	NewFunction ("Trig", "CONST_PI", "PI", RealOnly);
	
	NewFunction ("Log", "CONST_E", "e", RealOnly);
	NewFunction ("Log", "EXP", "e^x", RealOnly);
	NewFunction ("Log", "LN", "LN", RealOnly);
	NewFunction ("Log", "LOG", "LOG", RealOnly);
	NewFunction ("Log", "", "", RealOnly);
	NewFunction ("Log", "SQRT", "x^.5", RealOnly);
	NewFunction ("Log", "HOCH2", "x^2", RealOnly);
	NewFunction ("Log", "HOCHY", "x^y", RealOnly);
END Init;


BEGIN Init;
	Texts.OpenWriter (W);
	Texts.WriteString (W, SignOn); Texts.WriteLn (W); Texts.Append (Oberon.Log, W.buf);
END HPCalc.


Gadgets.Insert HPCalc.New ~


HPCalc.Open			Columbus.Inspect

FTPBackup.Do always HPCalc HPCalc.Mod Conversions.Mod ~

Compress.Add HPCalc2.Arc HPCalc.Mod Conversions.Mod HPCalc.Panel ~
AsciiCoder.CodeFiles % HPCalc.Mod Conversions.Mod HPCalc.Panel ~
System.Free HPCalc Conversions ProgressMeters ~
Conversions.Mod
