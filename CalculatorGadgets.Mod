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

MODULE CalculatorGadgets;	(** portable *)	(** by W.Ibl *)
(*
	Aug '97	V1.0	first release
	Oct '97	V1.1	several bugfixes
*)
IMPORT SYSTEM,BasicGadgets,Calculator,Conversions,
			  Files,Gadgets,MathL,Objects,Out,Strings;

CONST
	(* Program version *)
	Version = "V 1.1";
	Date = "Oct '97";

	CalcPrefix = "Calculator";	(* Field definition prefix *)
	CalcWidth = 24;	(* width of the calculators display *)
	CalcMem = 1;	(* amount of memory cells supported *)
	CalcUndoKey = 16;	(* amount of removable keyboard inputs *)
	CalcUndoOp = 4;	(* amount of removable values *)

	DEG = 0;	(* trigonometric in degrees *)
	RAD = 1;	(* trigonometric in radiants *)
	GRAD = 2;	(* trigonometric in grad *)
TYPE
	Operand = RECORD	(* a value *)
		value: LONGREAL;
		factor,base,angle: INTEGER;
	END;

	Button* = POINTER TO ButtonDesc;
	ButtonDesc* = RECORD(BasicGadgets.ButtonDesc)
		tag*: ARRAY 32 OF CHAR;	(* the real field value *)
	END;

	Engine* = POINTER TO EngineDesc;	(** the model gadget *)
	EngineDesc* = RECORD(Gadgets.ObjDesc)
		expr*: Calculator.Expression;
		state: INTEGER;
		op: ARRAY CalcUndoOp OF Operand;
		mem: ARRAY CalcMem OF LONGREAL;
		undo: ARRAY CalcUndoKey OF LONGREAL;
		tag: ARRAY 32 OF CHAR;
	END;

(* ** Add-On Operators **************************************** *)

PROCEDURE and(x,y: LONGREAL): LONGREAL;
VAR
	setx,sety: SET;
BEGIN
	setx:= SYSTEM.VAL(SET,ENTIER(x)); sety:= SYSTEM.VAL(SET,ENTIER(y));
	RETURN(SYSTEM.VAL(LONGINT,setx * sety));
END and;

PROCEDURE or(x,y: LONGREAL): LONGREAL;
VAR
	setx,sety: SET;
BEGIN
	setx:= SYSTEM.VAL(SET,ENTIER(x)); sety:= SYSTEM.VAL(SET,ENTIER(y));
	RETURN(SYSTEM.VAL(LONGINT,setx + sety));
END or;

PROCEDURE nor(x,y: LONGREAL): LONGREAL;
VAR
	setx,sety: SET;
BEGIN
	setx:= SYSTEM.VAL(SET,ENTIER(x)); sety:= SYSTEM.VAL(SET,ENTIER(y));
	RETURN(SYSTEM.VAL(LONGINT,(setx / {MIN(SET)..MAX(SET)}) + sety));
END nor;

PROCEDURE xor(x,y: LONGREAL): LONGREAL;
VAR
	setx,sety: SET;
BEGIN
	setx:= SYSTEM.VAL(SET,ENTIER(x)); sety:= SYSTEM.VAL(SET,ENTIER(y));
	RETURN(SYSTEM.VAL(LONGINT,setx / sety));
END xor;

PROCEDURE xnor(x,y: LONGREAL): LONGREAL;
VAR
	setx,sety: SET;
BEGIN
	setx:= SYSTEM.VAL(SET,ENTIER(x)); sety:= SYSTEM.VAL(SET,ENTIER(y));
	RETURN(SYSTEM.VAL(LONGINT,(setx / {MIN(SET)..MAX(SET)}) / sety));
END xnor;

(* ** Built-In Functions **************************************** *)

PROCEDURE not(x: LONGREAL): LONGREAL;
VAR
	setx: SET;
BEGIN
	setx:= SYSTEM.VAL(SET,ENTIER(x));
	RETURN(SYSTEM.VAL(LONGINT,setx / {MIN(SET)..MAX(SET)}));
END not;

PROCEDURE Rad(value: LONGREAL; angle: INTEGER): LONGREAL;
BEGIN
	CASE angle OF
	|	DEG:
			RETURN((value * 2 * MathL.pi) / 360.0);
	|	RAD:
			RETURN(value);
	|	GRAD:
			RETURN((value * 2 * MathL.pi) / 400);
	END;
END Rad;

PROCEDURE Deg(value: LONGREAL; angle: INTEGER): LONGREAL;
BEGIN
	CASE angle OF
	|	DEG:
			RETURN(value);
	|	RAD:
			RETURN((value * 360) / (2 * MathL.pi));
	|	GRAD:
			RETURN((value * 400) / (2 * MathL.pi));
	END;
END Deg;

PROCEDURE RadOp(op: Operand): LONGREAL;
BEGIN
	RETURN(Rad(op.value,op.angle));
END RadOp;

PROCEDURE arcsin(VAR op: Operand): BOOLEAN;
BEGIN
	op.value:= Deg(op.value,op.angle)/MathL.sqrt(1.0-Deg(op.value*op.value,op.angle));
	op.value:= MathL.arctan(op.value);
	RETURN(TRUE);
END arcsin;

PROCEDURE arccos(VAR op: Operand): BOOLEAN;
BEGIN
	op.value:= 1.0/MathL.sqrt(1.0-op.value*op.value);
	op.value:= MathL.arctan(RadOp(op));
	RETURN(TRUE);
END arccos;

PROCEDURE cot(VAR op: Operand): BOOLEAN;
BEGIN
	op.value:= MathL.cos(RadOp(op))/MathL.sin(RadOp(op));
	RETURN(TRUE);
END cot;	

PROCEDURE tan(VAR op: Operand): BOOLEAN;
BEGIN
	op.value:= MathL.sin(RadOp(op)) / MathL.cos(RadOp(op));
	RETURN(TRUE);
END tan;

(* ********************************************************** *)

PROCEDURE InitOperand(VAR O: Operand; base: INTEGER);
BEGIN
	O.value:= 0.0; O.factor:= 0; O.base:= base; O.angle:= 0;
END InitOperand;

PROCEDURE OperandToDisplay(O: Operand; w: INTEGER; VAR s: ARRAY OF CHAR);
	(* transform an Operand to ARRAY OF CHAR depending on it's base *)
VAR
	len,max,ndx: LONGINT;
BEGIN
	IF (O.base = 10) THEN
		Conversions.RealToStr(O.value,s,O.base);
	ELSE
		Conversions.IntToStr(ENTIER(O.value),s,O.base);
	END;
	len:= Strings.Length(s); max:= w; ndx:= 0;
	IF (len > w) THEN
		WHILE (max > 0) DO s[ndx]:= s[len-max]; DEC(max); INC(ndx); END;
	ELSE
		WHILE (len > 0) & (max > 0) DO s[max-1]:= s[len-1]; DEC(max); DEC(len); END;
		WHILE (max > 0) DO s[max-1]:= " "; DEC(max); END;
	END;
	s[w]:= 0X;
END OperandToDisplay;

PROCEDURE AddDigit(E: Engine; c: CHAR): BOOLEAN;
	(* Add a digit to the current Operand depending on it's base *)
VAR
	ok: BOOLEAN;
	val,inp: LONGREAL;
	i: INTEGER;
BEGIN
	ok:= TRUE; val:= E.op[0].value; inp:= MAX(LONGREAL);
	IF Strings.IsDigit(c) THEN
		inp:= ORD(c) - ORD("0");
	ELSIF Strings.IsHexDigit(c) THEN
		inp:= ORD(CAP(c)) - ORD("A") + 10.0;
	END;
	
	IF (inp < E.op[0].base) THEN
		IF (E.state = 1) THEN InitOperand(E.op[0],E.op[0].base); E.state:= 0; END;
		IF (E.op[0].factor # 0) THEN
			E.op[0].value:= E.op[0].value + ((ORD(c) - ORD("0")) / E.op[0].factor);
			E.op[0].factor:= E.op[0].factor * E.op[0].base;
		ELSE
			E.op[0].value:= (E.op[0].value * E.op[0].base) + inp;
		END;
	ELSE
		ok:= FALSE;
	END;
	IF ok THEN
		FOR i:= CalcUndoKey-1 TO 1 BY -1 DO E.undo[i]:= E.undo[i-1]; END;
		E.undo[0]:= val;
	END;
	RETURN(ok);
END AddDigit;

PROCEDURE RemDigit(E: Engine): BOOLEAN;
VAR
	i: INTEGER;
BEGIN
	E.op[0].value:= E.undo[0];
	FOR i:= 0 TO CalcUndoKey-2 DO E.undo[i]:= E.undo[i+1]; END;
	RETURN(TRUE);
END RemDigit;

PROCEDURE ApplyFunction(E: Engine; s: ARRAY OF CHAR): BOOLEAN;
	(* use funktion s on E's current value *)
VAR
	ok: BOOLEAN;
	op: Operand;
	i: INTEGER;
BEGIN
	ok:= FALSE; op:= E.op[0];
	IF (s = "arccos") THEN
		ok:= arccos(E.op[0]);
	ELSIF (s = "arcsin") THEN
		ok:= arcsin(E.op[0]);
	ELSIF (s = "arctan") THEN
		E.op[0].value:= MathL.arctan(RadOp(E.op[0])); ok:= TRUE;
	ELSIF (s = "cos") THEN
		E.op[0].value:= MathL.cos(RadOp(E.op[0])); ok:= TRUE;
	ELSIF (s = "cot") THEN
		ok:= cot(E.op[0]);
	ELSIF (s = "ex") THEN
		E.op[0].value:= Calculator.Power(MathL.e,E.op[0].value); ok:= TRUE;
	ELSIF (s = "fac") THEN
		E.op[0].value:= Calculator.Fac(E.op[0].value); ok:= TRUE;
	ELSIF (s = "gamma") THEN
		E.op[0].value:= Calculator.Fac(E.op[0].value-1.0); ok:= TRUE;
	ELSIF (s = "ld") THEN
		E.op[0].value:= MathL.ln(E.op[0].value) / MathL.ln(2); ok:= TRUE;
	ELSIF (s = "ln") THEN
		E.op[0].value:= MathL.ln(E.op[0].value); ok:= TRUE;
	ELSIF (s = "log") THEN
		E.op[0].value:= MathL.ln(E.op[0].value) / MathL.ln(10); ok:= TRUE;
	ELSIF (s = "not") THEN
		E.op[0].value:= not(E.op[0].value); ok:= TRUE;
	ELSIF (s = "percent") THEN
		E.op[0].value:= E.op[0].value / 100.0; ok:= TRUE;
	ELSIF (s = "sin") THEN
		E.op[0].value:= MathL.sin(RadOp(E.op[0])); ok:= TRUE;
	ELSIF (s = "sqr") THEN
		E.op[0].value:= E.op[0].value * E.op[0].value; ok:= TRUE;
	ELSIF (s = "sqrt") THEN
		E.op[0].value:= MathL.sqrt(E.op[0].value); ok:= TRUE;
	ELSIF (s = "tan") THEN
		ok:= tan(E.op[0]);
	ELSIF (s = "1dx") THEN
		E.op[0].value:= 1.0 / E.op[0].value; ok:= TRUE;
	ELSIF (s = "10px") THEN
		E.op[0].value:= Calculator.Power(10.0,E.op[0].value); ok:= TRUE;
	END;
	IF ok THEN
		FOR i:= CalcUndoOp-1 TO 2 BY -1 DO E.op[i]:= E.op[i-1]; END;
		E.op[1]:= op;
	END;
	RETURN(ok);
END ApplyFunction;

PROCEDURE AddSpecial(E: Engine; s: ARRAY OF CHAR): BOOLEAN;
	(* use a "special" operation on E's expression tree *)
VAR
	ok,keep: BOOLEAN;
	op: Operand;
	i: INTEGER;
BEGIN
	ok:= FALSE; keep:= FALSE; op:= E.op[0];
	IF (s = "POINT") THEN
		IF (E.state = 1) THEN InitOperand(E.op[0],E.op[0].base); E.state:= 0; END;
		E.op[0].factor:= 10; ok:= TRUE;
	ELSIF (s = "=") THEN
		E.state:= 1; keep:= TRUE;
		Calculator.AppendOperand(E.expr,E.op[0].value);
		Calculator.CloseAllBrackets(E.expr);
		E.op[0].value:= Calculator.EvaluateRoot(E.expr);
		ok:= (E.expr.res = Calculator.Done);
		IF ~ok THEN
			Out.String("Calculator Error #"); Out.Int(E.expr.res,0); Out.Ln();
			InitOperand(E.op[0],E.op[0].base);
		END;
		Calculator.InitExpression(E.expr);
	ELSIF (s = "(") & (E.state = 1) THEN
		InitOperand(E.op[0],E.op[0].base); E.state:= 0;
		Calculator.AppendBracket(E.expr,s[0]); ok:= TRUE;
	ELSIF (s = ")") THEN
		keep:= TRUE;
		Calculator.AppendOperand(E.expr,E.op[0].value);
		Calculator.AppendBracket(E.expr,s[0]);
		E.op[0].value:= Calculator.EvaluateCurrent(E.expr);
		ok:= (E.expr.res = Calculator.Done);
		IF ~ok THEN
			Out.String("Calculator Error #"); Out.Int(E.expr.res,0); Out.Ln();
		END;
	ELSIF (s = "CLEAR") THEN
		InitOperand(E.op[0],10); Calculator.InitExpression(E.expr);
		ok:= TRUE; keep:= TRUE;
	ELSIF (s = "CLEARALL") THEN
		Calculator.InitExpression(E.expr);
		FOR i:= 0 TO CalcUndoOp-1 DO InitOperand(E.op[i],10); END;
		FOR i:= 0 TO CalcMem-1 DO E.mem[i]:= 0.0; END;
		FOR i:= 0 TO CalcUndoKey-1 DO E.undo[i]:= 0.0; END;
		ok:= TRUE;
	ELSIF (s = "NEG") THEN
		E.op[0].value:= E.op[0].value * (-1.0); ok:= TRUE; keep:= TRUE;
	ELSIF (s = "UNDO") THEN
		E.op[0]:= E.op[1]; E.state:= 1; ok:= TRUE;
		FOR i:= 1 TO CalcUndoOp-2 DO E.op[i]:= E.op[i+1]; END;
		InitOperand(E.op[i],10);
	ELSIF (s = "STORE") THEN
		E.mem[0]:= E.op[0].value; E.state:= 1; ok:= TRUE;
	ELSIF (s = "RESTORE") THEN
		E.op[0].value:= E.mem[0]; ok:= TRUE; keep:= TRUE;
	ELSIF (s = "STOINC") THEN
		E.mem[0]:= E.mem[0] + E.op[0].value; ok:= TRUE;
	ELSIF (s = "BACK") THEN
		ok:= RemDigit(E);
	END;
	IF ok & keep THEN
		FOR i:= CalcUndoOp-1 TO 2 BY -1 DO E.op[i]:= E.op[i-1]; END;
		E.op[1]:= op;
	END;
	RETURN(ok);
END AddSpecial;

PROCEDURE AddConstant(E: Engine; s: ARRAY OF CHAR): BOOLEAN;
	(* add a predefined constant *)
VAR
	ok: BOOLEAN;
BEGIN
	ok:= FALSE;
	IF (s = "e") THEN
		E.op[0].value:= MathL.e; ok:= TRUE;
	ELSIF (s = "pi") THEN
		E.op[0].value:= MathL.pi; ok:= TRUE;
	END;
	RETURN(ok);
END AddConstant;

PROCEDURE AddOperator(E: Engine; s: ARRAY OF CHAR): BOOLEAN;
VAR
	i: INTEGER;
BEGIN
	FOR i:= CalcUndoOp-1 TO 2 BY -1 DO E.op[i]:= E.op[i-1]; END;
	E.op[1]:= E.op[0]; E.state:= 1;
	Calculator.AppendOperand(E.expr,E.op[0].value);
	E.op[0].value:= Calculator.EvaluateCurrent(E.expr);
	Calculator.AppendOperator(E.expr,s);
	RETURN(E.expr.res = Calculator.Done);
END AddOperator;

PROCEDURE GetSuffix(VAR str(* in *), suf(* out *): ARRAY OF CHAR);
	VAR i, j, l, dot: LONGINT;
BEGIN
	dot := -1; i := 0;
	WHILE str[i] # 0X DO
		IF str[i] = "." THEN dot := i END;
		INC(i)
	END;
	j := 0;
	IF dot > 0 THEN
		l := LEN(suf)-1; i := dot+1;
		WHILE (j < l) & (str[i] # 0X) DO
			suf[j] := str[i]; INC(j); INC(i)
		END
	END;
	suf[j] := 0X
END GetSuffix;

(* ** Engine Handler ** *)

PROCEDURE EngineAttr(E: Engine; VAR M: Objects.AttrMsg);
VAR
	val: ARRAY 32 OF CHAR;
BEGIN
	M.res:= -1;
	IF (M.id = Objects.get) THEN
		IF (M.name = "Gen") THEN
			M.class:= Objects.String; M.res:= 0; M.s:= "CalculatorGadgets.NewEngine";
		ELSIF (M.name = "Value") THEN
			M.class:= Objects.String; OperandToDisplay(E.op[0],CalcWidth,M.s); M.res:= 0;
		ELSIF (M.name = "Angle") THEN
			M.class:= Objects.Int; M.i:= E.op[0].angle; M.res:= 0;
		ELSIF (M.name = "Base") THEN
			M.class:= Objects.Int; M.i:= E.op[0].base; M.res:= 0;
		ELSIF (M.name = "Memory") THEN
			M.class:= Objects.Bool; M.b:= E.mem[0] # 0.0; M.res:= 0;
		ELSIF Strings.Prefix(CalcPrefix,M.name) THEN
			GetSuffix(M.name,val); M.res:= 0;
			M.class:= Objects.Bool; M.b:= (val = E.tag);
		END;
	ELSIF (M.id = Objects.set) THEN
		IF (M.name = "Angle") & (M.class = Objects.Int) THEN
			E.op[0].angle:= SHORT(M.i); M.res:= 0;
		ELSIF (M.name = "Base") & (M.class = Objects.Int) THEN
			E.op[0].base:= SHORT(M.i); M.res:= 0;
		ELSIF Strings.Prefix(CalcPrefix,M.name) & (M.class = Objects.Bool) THEN
			GetSuffix(M.name,val); M.res:= 0;
			IF (M.b = TRUE) THEN
				GetSuffix(M.name,E.tag);
				IF (Strings.Length(val) = 1) & AddDigit(E,val[0]) THEN
					M.res:= 0;
				ELSIF AddConstant(E,val) THEN
					M.res:= 0;
				ELSIF ApplyFunction(E,val) THEN
					M.res:= 0;
				ELSIF AddSpecial(E,val) THEN
					M.res:= 0;
				ELSIF AddOperator(E,val) THEN
					M.res:= 0;
				ELSE
					M.res:= -1;
				END;
			ELSE
				E.tag:= "";
			END;
		END;
	END;
	IF (M.res = -1) THEN Gadgets.objecthandle(E,M); END;
END EngineAttr;

PROCEDURE EngineCopy(E: Engine; VAR M: Objects.CopyMsg);
VAR
	nE: Engine;
BEGIN
	IF (M.stamp = E.stamp) THEN
		M.obj:= E.dlink;
	ELSE
		NEW(nE); M.obj:= nE;
		nE.expr:= E.expr; nE.op:= E.op; nE.mem:= E.mem;
		COPY(E.tag,nE.tag);
	END;
END EngineCopy;

PROCEDURE EngineFile(E: Engine; VAR M: Objects.FileMsg);
VAR
	i,len: LONGINT;
BEGIN
	IF (M.id = Objects.store) THEN
		Files.WriteLInt(M.R,CalcUndoOp);
		FOR i:= 0 TO CalcUndoOp-1 DO
			Files.WriteLReal(M.R,E.op[i].value);
			Files.WriteInt(M.R,E.op[i].factor); Files.WriteInt(M.R,E.op[i].base);
		END;
		Files.WriteLInt(M.R,CalcMem);
		FOR i:= 0 TO CalcMem-1 DO Files.WriteLReal(M.R,E.mem[i]); END;
		Files.WriteLInt(M.R,CalcUndoKey);
		FOR i:= 0 TO CalcUndoKey-1 DO Files.WriteLReal(M.R,E.undo[i]); END;
	ELSIF (M.id = Objects.load) THEN
		Files.ReadLInt(M.R,len); IF (len > CalcUndoOp) THEN len:= CalcUndoOp; END;
		FOR i:= 0 TO len-1 DO
			Files.ReadLReal(M.R,E.op[i].value);
			Files.ReadInt(M.R,E.op[i].factor); Files.ReadInt(M.R,E.op[i].base);
		END;
		Files.ReadLInt(M.R,len); IF (len > CalcMem) THEN len:= CalcMem; END;
		FOR i:= 0 TO len-1 DO Files.ReadLReal(M.R,E.mem[i]); END;
		Files.ReadLInt(M.R,len); IF (len > CalcUndoKey) THEN len:= CalcUndoKey; END;
		FOR i:= 0 TO len-1 DO Files.ReadLReal(M.R,E.undo[i]); END;
	END;
	Gadgets.objecthandle(E,M);
END EngineFile;

PROCEDURE EngineHandler*(E: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH E: Engine DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO EngineAttr(E,M); END;
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO EngineCopy(E,M); END;
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO EngineFile(E,M); END;
		ELSE
			Gadgets.objecthandle(E,M);
		END;
	END;
END EngineHandler;

(* ** Button Handler ** *)

PROCEDURE CopyButton*(VAR M: Objects.CopyMsg; from,to: Button);
BEGIN
	BasicGadgets.CopyButton(M,from,to); COPY(from.tag,to.tag);
END CopyButton;

PROCEDURE ButtonAttr(B: Button; VAR M: Objects.AttrMsg);
BEGIN
	M.res:= -1;
	IF (M.id = Objects.get) THEN
		IF (M.name = "Gen") THEN
			M.class:= Objects.String; M.res:= 0; M.s:= "CalculatorGadgets.NewButton";
		ELSIF (M.name = "Field") THEN
			M.class:= Objects.String; M.s:= ""; M.res:= 0;
			IF (B.tag # "") THEN
				M.s:= CalcPrefix; Strings.AppendCh(M.s,"."); Strings.Append(M.s,B.tag);
			END;
		END;
	ELSIF (M.id = Objects.set) & (M.name = "Field") & (M.class = Objects.String) THEN
		COPY(M.s,B.tag);
		IF Strings.CAPPrefix(CalcPrefix,M.s) THEN GetSuffix(M.s,B.tag); END;
	END;
	IF (M.res = -1) THEN BasicGadgets.ButtonHandler(B,M); END;
END ButtonAttr;

PROCEDURE ButtonCopy(B: Button; VAR M: Objects.CopyMsg);
VAR
	nB: Button;
BEGIN
	IF (M.stamp = B.stamp) THEN
		M.obj:= B.dlink;
	ELSE
		NEW(nB); M.obj:= nB; CopyButton(M,B,nB);
	END;
END ButtonCopy;

PROCEDURE ButtonFile(B: Button; VAR M: Objects.FileMsg);
BEGIN
	IF (M.id = Objects.store) THEN
		Files.WriteString(M.R,B.tag);
	ELSIF (M.id = Objects.load) THEN
		Files.ReadString(M.R,B.tag);
	END;
	BasicGadgets.ButtonHandler(B,M);
END ButtonFile;

PROCEDURE ButtonHandler*(B: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH B: Button DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO ButtonAttr(B,M); END;
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO ButtonCopy(B,M); END;
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO ButtonFile(B,M); END;
		ELSE
			BasicGadgets.ButtonHandler(B,M);
		END;
	END;
END ButtonHandler;

(* ** Generator Functions ** *)

(** Initialize a calculator model *)
PROCEDURE InitEngine*(E: Engine);
VAR
	i: INTEGER;
BEGIN
	NEW(E.expr); Calculator.InitExpression(E.expr);
	FOR i:= 0 TO CalcUndoOp-1 DO InitOperand(E.op[i],10); END;
	FOR i:= 0 TO CalcMem-1 DO E.mem[i]:= 0.0; END;
	FOR i:= 0 TO CalcUndoKey-1 DO E.undo[i]:= 0.0; END;
	E.state:= 0; E.tag:= ""; Calculator.test:= E.expr;
END InitEngine;

(** create a new calculator model *)
PROCEDURE NewEngine*;
VAR
	E: Engine;
BEGIN
	NEW(E); InitEngine(E); E.handle:= EngineHandler;
	Objects.NewObj:= E;
END NewEngine;

(** initialize a calculator button gadget *)
PROCEDURE InitButton*(B: Button);
BEGIN
	BasicGadgets.InitButton(B); B.led:= FALSE; B.ledcol:= 0; B.tag:= "";
END InitButton;

(** create a new calculator button gadget
To pass a value to the model gadget prefix it with Calculator. (p.e. Calculator.1 or Calculator.+).
the model itself tries to determine if it is a value, an operator or a special.
*)
PROCEDURE NewButton*;
VAR
	B: Button;
BEGIN
	NEW(B); InitButton(B); B.handle:= ButtonHandler;
	Objects.NewObj:= B;
END NewButton;

BEGIN
	(* What I wanted to say... *)
	Out.String("Desktop Calculator "); Out.String(Version);
	Out.String(" by W. Ibl, "); Out.String(Date); Out.Ln();
	
	(* add some new Operators to Calculator *)
	Calculator.AddInfixOperator("and",0,and);
	Calculator.AddInfixOperator("or",0,or);
	Calculator.AddInfixOperator("nor",0,nor);
	Calculator.AddInfixOperator("xor",0,xor);
	Calculator.AddInfixOperator("xnor",0,xnor);
END CalculatorGadgets.
