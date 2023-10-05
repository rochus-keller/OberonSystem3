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

MODULE Calculator;	(** portable *)	(** by W. Ibl *)
(*
	Aug '97	V 1.0	first release
	Oct '97	V1.1	added pre- in- and postfix classification
*)
IMPORT MathL,Oberon,Objects,Texts;

CONST
	EOC = "~";
	Done* = 0;
	UnmatchedBrackets* = 1;
	UnknownOperator* = 2;
	MisplacedOperator* = 3;
	MisplacedOperand* = 4;
	NoOperand* = 5;
	InternalError* = 6;

	PREFIX = 1;
	POSTFIX = 2;
	INFIX = 3;
	OPERAND = 4;
TYPE
	(** Implementation of unary resp. binary operators *)
	UnaryFunc* = PROCEDURE(x: LONGREAL): LONGREAL;
	BinaryFunc* = PROCEDURE(x: LONGREAL; y: LONGREAL): LONGREAL;

	Reference = POINTER TO ReferenceDesc;	(* Element of the list of known operators *)
	ReferenceDesc = RECORD
		name: Objects.Name;	(* "+", "-", "sqrt", "log", etc. *)
		weight: INTEGER;	(* the operator's weight, 0 is minor *)
		next: Reference;
	END;

	PrefixOperator = POINTER TO PrefixOperatorDesc;
	PrefixOperatorDesc = RECORD(ReferenceDesc)
		op: UnaryFunc;
	END;

	InfixOperator = POINTER TO InfixOperatorDesc;
	InfixOperatorDesc = RECORD(ReferenceDesc)
		op: BinaryFunc;
	END;

	Node = POINTER TO NodeDesc;	(* an element of the expression tree *)
	NodeDesc = RECORD
		left,right,up: Node;
	END;

	Operator = POINTER TO OperatorDesc;
	OperatorDesc = RECORD(NodeDesc)
		ref: Reference;
	END;

	Result = POINTER TO ResultDesc;
	ResultDesc = RECORD(NodeDesc)
	END;

	Value = POINTER TO ValueDesc;
	ValueDesc = RECORD(NodeDesc)
		value: LONGREAL;
	END;

	Expression* = POINTER TO ExpressionDesc;	(** the expression tree *)
	ExpressionDesc* = RECORD
		root,curr: Node;
		res*,nest,last: INTEGER;	(** error flag *)
	END;
VAR
	F,D: LONGINT;	(* fraction and decimals *)
	ref: Reference;	(* List of available operators *)
	test*: Expression;	(** FOR DEBUGGING ONLY *)

(* ** Built-In Operators **************************************** *)

PROCEDURE Add(to,this: LONGREAL): LONGREAL;
BEGIN
	RETURN(to+this);
END Add;

PROCEDURE Subtract(this,from: LONGREAL): LONGREAL;
BEGIN
	RETURN(from-this);
END Subtract;

PROCEDURE Multiply(by,this: LONGREAL): LONGREAL;
BEGIN
	RETURN(this*by);
END Multiply;

PROCEDURE Divide(by,this: LONGREAL): LONGREAL;
BEGIN
	RETURN(this/by);
END Divide;

(** raise base by exponent using e ^ (exponent * ln(base)). This is exportet for Calculator Gadgets *)
PROCEDURE Power*(base,exponent: LONGREAL): LONGREAL;
VAR
	res: LONGREAL;
BEGIN
	IF (base <= 0.0) THEN
		res:= 0.0;
	ELSE
		res:= MathL.exp(exponent * MathL.ln(base));
	END;
	RETURN(res);
END Power;

(** calculate factorial of this using Stirling's approximation. This is exportet for Calculator Gadgets *)
PROCEDURE Fac*(this: LONGREAL): LONGREAL;
VAR
	cf: LONGREAL;
BEGIN
	IF (this > 0.0) THEN
		cf:= 1.0+1.0/(12.0*this)+1.0/(288.0*this*this)-139.0/(51840.0*this*this*this)-571.0/(2488320.0*this*this*this*this);
		RETURN(MathL.sqrt(2*MathL.pi*this)*MathL.exp(this*MathL.ln(this)-this)*cf);
	ELSE
		RETURN(1.0);
	END;
END Fac;

(* ********************************************************** *)

PROCEDURE Calc(node: Node; VAR res: INTEGER): LONGREAL;
	(* rekursive calculation of node results *)
VAR
	val,val0: LONGREAL;
	ref: Reference;
BEGIN
	IF (res # Done) THEN
	ELSIF (node = NIL) THEN
		res:= InternalError; (* damaged tree structure *)
	ELSIF node IS Operator THEN
		WITH node: Operator DO ref:= node.ref; END;
		IF ref IS PrefixOperator THEN
			WITH ref: PrefixOperator DO val:= ref.op(Calc(node.left,res)); END;
		ELSIF ref IS InfixOperator THEN
			WITH ref: InfixOperator DO
				val0:= Calc(node.right,res); val:= Calc(node.left,res);
				val:= ref.op(val0,val);
			END;
		END;
	ELSIF node IS Result THEN
		val:= Calc(node.left,res);
	ELSIF node IS Value THEN
		WITH node: Value DO val:= node.value; END;
	ELSE
		res:= InternalError; (* unknown type of tree node *)
	END;
	RETURN(val);
END Calc;

PROCEDURE Weight(node: Node): INTEGER;
	(* determine an operator's weight, starting at 0 *)
VAR
	weight: INTEGER;
BEGIN
	IF (node # NIL) THEN
		IF node IS Result THEN
			weight:= -2;
		ELSIF node IS Operator THEN
			WITH node: Operator DO weight:= node.ref.weight; END;
		END;
	ELSE
		weight:= -1;
	END;
	RETURN(weight);
END Weight;

PROCEDURE InitNode(node: Node);
	(* initialize a new node *)
BEGIN
	node.left:= NIL; node.right:= NIL; node.up:= NIL;
END InitNode;

PROCEDURE NewResult(): Result;
	(* create a new result node *)
VAR
	result: Result;
BEGIN
	NEW(result); InitNode(result);
	RETURN(result);
END NewResult;

(** Initialize a new expression tree. *)
PROCEDURE InitExpression*(VAR exp: Expression);
VAR
	result: Result;
BEGIN
	ASSERT(exp # NIL);
	result:= NewResult();
	exp.root:= result; exp.curr:= result; exp.nest:= 0; exp.res:= Done;
END InitExpression;

PROCEDURE AppendValue(exp: Expression; val: Value);
	(* add a new value node to the expression tree *)
BEGIN
	ASSERT((val # NIL) & ~(exp.curr IS Value));
	IF (exp.curr.left = NIL) THEN
		exp.curr.left:= val;
	ELSE
		exp.curr.right:= val;
	END;
	val.up:= exp.curr; exp.curr:= val; exp.last:= OPERAND;
END AppendValue;

(** Add an opening '(' or closing ')' bracket to the expression tree. All operations between those brackets
are resolved first on evaluation. This is exported for CalculatorGadgets. *)
PROCEDURE AppendBracket*(VAR exp: Expression; bracket: CHAR);
VAR
	result: Result;
BEGIN
	IF (bracket = "(") THEN
		INC(exp.nest);
		result:= NewResult();
		IF (exp.curr.left = NIL) THEN
			exp.curr.left:= result;
		ELSE
			exp.curr.right:= result;
		END;
		result.up:= exp.curr; exp.curr:= result;
	ELSIF (bracket = ")") THEN
		DEC(exp.nest);
		WHILE (Weight(exp.curr.up) >= 0) DO exp.curr:= exp.curr.up; END;
		IF (exp.curr.up # NIL) THEN exp.curr:= exp.curr.up; END;
	END;
	exp.last:= 0;
END AppendBracket;

(** Close all open brackets in the expression tree. This is exported for CalculatorGadgets. *)
PROCEDURE CloseAllBrackets*(VAR exp: Expression);
BEGIN
	WHILE (exp.nest > 0) DO AppendBracket(exp,")"); END;
END CloseAllBrackets;

(** Add a new operator to the expression tree. The operator must be either built-in or been added by
AddPrefixOperator/AddPostfixOperator resp. AddInfixOperator before. This is exported for CalculatorGadgets. *)
PROCEDURE AppendOperator*(VAR exp: Expression; op: ARRAY OF CHAR);
VAR
	rider: Reference;
	eval: Operator;
	weight: INTEGER;
BEGIN
	rider:= ref;
	WHILE (rider # NIL) & (rider.name # op) DO rider:= rider.next; END;
	IF (rider = NIL) THEN
		exp.res:= UnknownOperator;
	ELSE
		NEW(eval); InitNode(eval); eval.ref:= rider;
		weight:= Weight(eval);
		IF (weight = MIN(INTEGER)) THEN
			exp.last:= POSTFIX;
			IF (exp.curr.up = NIL) THEN
				exp.res:= MisplacedOperator;
			ELSE
				eval.left:= exp.curr; eval.up:= exp.curr.up; exp.curr.up:= eval;
				IF (eval.up.left = exp.curr) THEN
					eval.up.left:= eval;
				ELSE
					eval.up.right:= eval;
				END;
			END;
		ELSIF (weight = MAX(INTEGER)) THEN
			exp.last:= PREFIX;
			IF (exp.curr IS Operator) OR (exp.curr IS Result) THEN
				eval.up:= exp.curr;
				IF (exp.curr.left = NIL) THEN exp.curr.left:= eval; ELSE exp.curr.right:= eval; END;
			ELSE
				exp.res:= MisplacedOperator;
			END;
		ELSE
			exp.last:= INFIX;
			WHILE (Weight(exp.curr.up) > weight) DO exp.curr:= exp.curr.up; END;
			eval.left:= exp.curr; eval.up:= exp.curr.up; exp.curr.up:= eval;
			IF (eval.up # NIL) THEN
				IF (eval.up.left = exp.curr) THEN
					eval.up.left:= eval;
				ELSE
					eval.up.right:= eval;
				END;
			END;
		END;
		exp.curr:= eval;
	END;
END AppendOperator;

(** Add a new operand to the expression tree. This is exported for CalculatorGadgets. *)
PROCEDURE AppendOperand*(VAR exp: Expression; op: LONGREAL);
VAR
	val: Value;
BEGIN
	exp.last:= OPERAND;
	NEW(val); InitNode(val); val.value:= op; AppendValue(exp,val);
END AppendOperand;

(** Scan a text and build an expression tree. No result is calculated. *)
PROCEDURE Scan*(VAR exp: Expression; VAR S: Texts.Scanner);
VAR
	val: Value;
	last: INTEGER;
BEGIN
	exp.last:= 0; last:= 0; Texts.Scan(S);
	IF ~S.eot & ~((S.class = Texts.Char) & (S.c = EOC)) THEN
		InitExpression(exp);
		WHILE (exp.res = Done) & ~S.eot & ~((S.class = Texts.Char) & (S.c = EOC)) DO
			IF (S.class = Texts.Char) THEN
				S.s[0]:= S.c; S.s[1]:= 0X;
				IF (S.c = "(") OR (S.c = ")") THEN
					AppendBracket(exp,S.c);
				ELSE
					S.s[0]:= S.c; S.s[1]:= 0X;
					AppendOperator(exp,S.s);
					IF (exp.last = INFIX) & (last # OPERAND) & (last # 0) THEN
						exp.res:= MisplacedOperator;
					END;
				END;
			ELSIF (S.class = Texts.Name) THEN
				AppendOperator(exp,S.s);
				IF (exp.last = INFIX) & (last # OPERAND) & (last # 0) THEN
					exp.res:= MisplacedOperator;
				END;
			ELSE
				NEW(val); InitNode(val);
				IF (S.class = Texts.Int) THEN
					val.value:= S.i;
				ELSIF (S.class = Texts.Real) THEN
					val.value:= S.x;
				ELSIF (S.class = Texts.LongReal) THEN
					val.value:= S.y;
				ELSE
					exp.res:= NoOperand;
				END;
				IF (last = OPERAND) THEN
					exp.res:= MisplacedOperand;
				ELSE
					AppendValue(exp,val);
				END;
			END;
			IF (exp.res = Done) THEN last:= exp.last; Texts.Scan(S); END;
		END;
		IF (exp.res = Done) & (exp.nest # 0) THEN exp.res:= UnmatchedBrackets; END;
	END;
END Scan;

(** traverse the expression tree starting from the current node of exp and return the result. *)
PROCEDURE EvaluateCurrent*(exp: Expression): LONGREAL;
VAR
	res: LONGREAL;
	node: Node;
BEGIN
	node:= exp.curr; exp.res:= Done;
	WHILE ~(node IS Result) & (node # NIL) DO node:= node.up; END;
	IF (node # NIL) THEN res:= Calc(node,exp.res); ELSE exp.res:= InternalError; END;
	RETURN(res);
END EvaluateCurrent;

(** traverse the expression tree starting from the topmost node of exp and return the result *)
PROCEDURE EvaluateRoot*(exp: Expression): LONGREAL;
VAR
	res: LONGREAL;
BEGIN
	IF (exp.res = Done) THEN
		IF (exp.nest # 0) THEN
			exp.res:= UnmatchedBrackets;
		ELSE
			res:= Calc(exp.root,exp.res);
		END;
	END;
	RETURN(res);
END EvaluateRoot;

(** set the fraction value of the output of Calculator.Calculate *)
PROCEDURE Fraction*;
VAR
	S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S,Oberon.Par.text,Oberon.Par.pos);
	Texts.Scan(S);
	IF (S.class = Texts.Int) THEN F:= S.i; END;
END Fraction;

(** set the exponent value of the output of Calculator.Calculate *)
PROCEDURE Exponent*;
VAR
	S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S,Oberon.Par.text,Oberon.Par.pos);
	Texts.Scan(S);
	IF (S.class = Texts.Int) THEN D:= S.i; END;
END Exponent;

(** scan a text, traverse the resulting tree and print the result into Oberon.Log *) 
PROCEDURE Calculate*;
VAR
	S: Texts.Scanner;
	W: Texts.Writer;
	exp: Expression;
	val: LONGREAL;
BEGIN
	Texts.OpenWriter(W); NEW(exp); test:= exp;
	Texts.OpenScanner(S,Oberon.Par.text,Oberon.Par.pos); Scan(exp,S);
	IF (exp.res = Done) THEN val:= EvaluateRoot(exp); END;
	CASE exp.res OF
	| Done:
		Texts.WriteLongRealFix(W,val,0,F,D);
	| UnmatchedBrackets:
		Texts.WriteString(W,"unmatched brackets");
	| UnknownOperator:
		Texts.Write(W,22X); Texts.WriteString(W,S.s); Texts.Write(W,22X);
		Texts.WriteString(W," is an unknown operator");
	| MisplacedOperator:
		Texts.Write(W,22X); Texts.WriteString(W,S.s); Texts.Write(W,22X);
		Texts.WriteString(W," is misplaced");
	| MisplacedOperand:
		Texts.WriteString(W,"misplaced operand");
	| NoOperand:
		Texts.Write(W,22X); Texts.WriteString(W,S.s); Texts.Write(W,22X);
		Texts.WriteString(W," is not a proper operand");
	ELSE
		Texts.WriteString(W,"internal error");
	END;
	Texts.WriteLn(W);
	Texts.Append(Oberon.Log,W.buf);
END Calculate;

(** Add a new unary prefix operator. It must be followed by a value and is calculated first on Evaluation.
f must be PROCEDURE(x: LONGREAL) returning LONGREAL. For example to define the unary operator log

		PROCEDURE log(x: LONGREAL): LONGREAL;
		BEGIN
			RETURN(MathL.ln(x) / MathL.ln(10));
		END log;

		Calculator.AddPrefixOperator("log",log);
*)
PROCEDURE AddPrefixOperator*(name: ARRAY OF CHAR; f: UnaryFunc);
VAR
	op: PrefixOperator;
	rider: Reference;
BEGIN
	rider:= ref;
	WHILE (rider # NIL) & (rider.name # name) DO rider:= rider.next; END;
	IF (rider = NIL) THEN
		NEW(op); op.next:= ref; COPY(name,op.name);
		op.weight:= MAX(INTEGER); op.op:= f; ref:= op;
	ELSE
		WITH rider: PrefixOperator DO rider.op:= f; END;
	END;
END AddPrefixOperator;

(** Add a new binary infix operator. It must be between two expressions and is calculated depending on w.
f must be PROCEDURE(x: LONGREAL; y: LONGREAL) returning LONGREAL. For example to define the binary
operator modulo

		PROCEDURE modulo(x,y: LONGREAL): LONGREAL;
		BEGIN
			RETURN(ENTIER(x) MOD ENTIER(y));
		END modulo;

		Calculator.AddInfixOperator("mod",0,modulo);
*)
PROCEDURE AddInfixOperator*(name: ARRAY OF CHAR; w: INTEGER; f: BinaryFunc);
VAR
	op: InfixOperator;
	rider: Reference;
	W: Texts.Writer;
BEGIN
	IF (w < 0) THEN
		Texts.OpenWriter(W); Texts.WriteString(W,"invalid operator weight");
		Texts.WriteLn(W); Texts.Append(Oberon.Log,W.buf);
	ELSE
		rider:= ref;
		WHILE (rider # NIL) & (rider.name # name) DO rider:= rider.next; END;
		IF (rider = NIL) THEN
			NEW(op); op.next:= ref; COPY(name,op.name);
			op.weight:= w; op.op:= f; ref:= op;
		ELSE
			WITH rider: InfixOperator DO rider.weight:= w; rider.op:= f; END;
		END;
	END;
END AddInfixOperator;

(** Add a new unary postfix operator. It must be preceeded by a value and is calculated last on evaluation.
f must be PROCEDURE(x: LONGREAL) returning LONGREAL. For example to define a simple unary operator fac

		PROCEDURE fac(x: LONGREAL): LONGREAL;
		VAR
			i: LONGINT;
			y: LONGREAL;
		BEGIN
			i:= 0; y:= 1.0;
			WHILE (i < ENTIER(x)) DO y:= y * i; INC(i); END;
			RETURN(y);
		END fac;

		Calculator.AddPostfixOperator("!",fac);
*)
PROCEDURE AddPostfixOperator*(name: ARRAY OF CHAR; f: UnaryFunc);
VAR
	op: PrefixOperator;
	rider: Reference;
BEGIN
	rider:= ref;
	WHILE (rider # NIL) & (rider.name # name) DO rider:= rider.next; END;
	IF (rider = NIL) THEN
		NEW(op); op.next:= ref; COPY(name,op.name);
		op.weight:= MIN(INTEGER); op.op:= f; ref:= op;
	ELSE
		WITH rider: PrefixOperator DO rider.op:= f; END;
	END;
END AddPostfixOperator;

(* FOR DEBUGGING ONLY ****************************************

PROCEDURE ShowNode(node: Node);
BEGIN
	IF node IS Value THEN
		WITH node: Value DO Log.PutReal(SHORT(node.value),0,0); END;
	ELSIF node IS Operator THEN
		WITH node: Operator DO
			Log.PutChar(" ");
			Log.PutString(node.ref.name);
			Log.PutChar(" ");
		END;
	ELSIF node IS Result THEN
		Log.PutChar("=");
	ELSE
		Log.PutString("unknown node");
	END;
END ShowNode;

PROCEDURE WriteExpression(exp: Expression);

	PROCEDURE WriteNode(node: Node);
	BEGIN
		IF (node # NIL) THEN
			WriteNode(node.left);
			ShowNode(node);
			WriteNode(node.right);
		END;
	END WriteNode;

BEGIN
	Log.Message("Expression:");	
	WriteNode(exp.root);
	Log.PutLn();
END WriteExpression;

PROCEDURE ShowRoot*;
BEGIN
	IF (test.root = NIL) THEN
		Log.Message("root is NIL");
	ELSE
		ShowNode(test.root); test.curr:= test.root; Log.PutLn();
	END;
END ShowRoot;

PROCEDURE ShowCurr*;
BEGIN
	IF (test.curr = NIL) THEN
		Log.Message("curr is NIL");
	ELSE
		ShowNode(test.curr); Log.PutLn();
	END;
END ShowCurr;

PROCEDURE DownLeft*;
BEGIN
	IF (test.curr = NIL) THEN
		Log.Message("curr is NIL");
	ELSIF (test.curr.left = NIL) THEN
		Log.Message("no left node");
	ELSE
		ShowNode(test.curr.left);
		test.curr:= test.curr.left;
		Log.PutLn();
	END;
END DownLeft;

PROCEDURE DownRight*;
BEGIN
	IF (test.curr = NIL) THEN
		Log.Message("curr is NIL");
	ELSIF (test.curr.right = NIL) THEN
		Log.Message("no right node");
	ELSE
		ShowNode(test.curr.right);
		test.curr:= test.curr.right;
		Log.PutLn();
	END;
END DownRight;

PROCEDURE Up*;
BEGIN
	IF (test.curr = NIL) THEN
		Log.Message("curr is NIL");
	ELSIF (test.curr.up = NIL) THEN
		Log.Message("no upper node");
	ELSE
		ShowNode(test.curr.up);
		test.curr:= test.curr.up;
		Log.PutLn();
	END;
END Up;

**************************************************************)

BEGIN
	F:= 8; D:= 0; ref:= NIL;

(** predefined Operators are
Infix:	+ Add, - Subtract, * Multiply, / Divide, ^ Power
Prefix:	arctan, sin, cos, exp, ln, sqrt
Postfix: ! Factorial

used operator weights are 0 to 4

Syntax of expression must be according to Texts.Scanner
*)

	(* those are the basic built-in's *)
	AddInfixOperator("+",0,Add);	(* INFIX *)
	AddInfixOperator("-",1,Subtract);
	AddInfixOperator("*",2,Multiply);
	AddInfixOperator("/",3,Divide);
	AddInfixOperator("^",4,Power);

	(* accessable MathL functions can be added immediately *)
	AddPrefixOperator("arctan",MathL.arctan);	(* PREFIX *)
	AddPrefixOperator("sin",MathL.sin);
	AddPrefixOperator("cos",MathL.cos);
	AddPrefixOperator("exp",MathL.exp);
	AddPrefixOperator("ln",MathL.ln);
	AddPrefixOperator("sqrt",MathL.sqrt);

	AddPostfixOperator("!",Fac);	(* POSTFIX *)

	NEW(test);
END Calculator.

System.Free Calculator~
Calculator.Fraction 1
Calculator.Exponent 0
Calculator.Calculate 2 * ( 12 + 14 ) - sin 2~
Calculator.Calculate 5 + 4 / 2~
Calculator.ShowCurr
Calculator.ShowRoot
Calculator.Up
Calculator.DownLeft
Calculator.DownRight

