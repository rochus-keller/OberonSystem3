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

MODULE Calc;	(** portable *)	(* CAS 28.9.93 / tk adapted for System 3 1.6.95*)
	IMPORT
		MathL, Texts, Oberon;

	CONST
		Version = "Calc / cas 28.9.93";
		End = 7;	(*new scanner symbol*)
		Eps = 1.0D-9; Eps0 = 0.5D-9;

	TYPE
		Symbol = POINTER TO SymbolDesc;
		SymbolDesc = RECORD
			name: ARRAY 32 OF CHAR;
			funct: BOOLEAN;
			val: LONGREAL;
			next: Symbol
		END;

	VAR
		lastTime: LONGINT;
		W: Texts.Writer;
		S: Texts.Scanner;
		syms: Symbol;


	(** expression syntax:
		Expr = Term {AddOp Term}.
		Term = Factor {MulOp Factor}.
		Factor = Atom {PowOp Atom}.
		Atom = Number | Functor Atom | ident | "(" Expr ")".
		PowOp = "^".
		MulOp = "*" | "/" | "%" | "<" | ">".	-- % modulo, < shift left, > shift right
		AddOp = ["+" | "-"].	-- no add op: addition(!)
		Number = (digit {digit}) | (digit {hexDigit} "H") | (digit {hexDigit} "X") | (""" char """).
		Functor = "arccos" | "arcsin" | "arctan" | "cos" | "entier" | "exp" | "ln" | "short" | "sign" | "sin" | "sqrt" | "tan".
	**)

	PROCEDURE err;
	BEGIN S.class := Texts.Inval
	END err;


	PROCEDURE sign (n: LONGREAL): LONGREAL;
	BEGIN
		IF n < 0 THEN RETURN -1
		ELSIF n = 0 THEN RETURN 0
		ELSE RETURN 1 END
	END sign;

	PROCEDURE short (n: LONGREAL): REAL;
	BEGIN RETURN SHORT(n + Eps0)
	END short;

	PROCEDURE entier (n: LONGREAL): LONGINT;
	BEGIN RETURN ENTIER(n + Eps0)
	END entier;


	PROCEDURE sin (n: LONGREAL): LONGREAL;
	BEGIN RETURN MathL.sin(n)
	END sin;

	PROCEDURE cos (n: LONGREAL): LONGREAL;
	BEGIN RETURN MathL.cos(n)
	END cos;

	PROCEDURE tan (n: LONGREAL): LONGREAL;
		VAR x: LONGREAL;
	BEGIN x := MathL.cos(n);
		IF x # 0 THEN RETURN MathL.sin(n) / x ELSE err; RETURN 1 END
	END tan;

	PROCEDURE arcsin (n: LONGREAL): LONGREAL;
		VAR x: LONGREAL;
	BEGIN x := MathL.sqrt(1 - n * n);
		IF x # 0 THEN RETURN MathL.arctan(n / x) ELSE err; RETURN 1 END
	END arcsin;

	PROCEDURE arccos (n: LONGREAL): LONGREAL;
	BEGIN RETURN MathL.pi / 2 - arcsin(n)
	END arccos;

	PROCEDURE arctan (n: LONGREAL): LONGREAL;
	BEGIN RETURN MathL.arctan(n)
	END arctan;

	PROCEDURE exp (n: LONGREAL): LONGREAL;
	BEGIN RETURN MathL.exp(n)
	END exp;

	PROCEDURE ln (n: LONGREAL): LONGREAL;
	BEGIN
		IF n > 0 THEN RETURN MathL.ln(n) ELSE err; RETURN 1 END
	END ln;

	PROCEDURE sqrt (n: LONGREAL): LONGREAL;
	BEGIN
		IF n >= 0 THEN RETURN MathL.sqrt(n) ELSE err; RETURN 1 END
	END sqrt;


	PROCEDURE Ch (ch: CHAR);
	BEGIN Texts.Write(W, ch); 
	END Ch;

	PROCEDURE Str (s: ARRAY OF CHAR);
	BEGIN Texts.WriteString(W, s); 
	END Str;

	PROCEDURE WrHex (n: LONGREAL);
		VAR x, y: LONGINT; i: INTEGER;
			a: ARRAY 10 OF CHAR;
	BEGIN x := entier(n);
		i := 0; Texts.Write(W, " ");
		REPEAT y := x MOD 10H;
			IF y < 10 THEN a[i] := CHR(y + 30H) ELSE a[i] := CHR(y + 37H) END;
			x := x DIV 10H; INC(i)
		UNTIL i = 8;
		REPEAT DEC(i) UNTIL (i = 0) OR (a[i] # "0");
		IF a[i] >= "A" THEN Texts.Write(W, "0") END;
		WHILE i >= 0 DO Texts.Write(W, a[i]); DEC(i) END;
		Texts.Write(W, "H")
	END WrHex;

	PROCEDURE WrInt (n: LONGREAL);
	BEGIN Texts.Write(W, " "); Texts.WriteInt(W, entier(n), 0)
	END WrInt;

	PROCEDURE WrChar (n: LONGREAL);
		VAR ch: CHAR;
	BEGIN ch := CHR(entier(n));
		IF (" " <= ch) & (ch < 7FX) OR (80X <= ch) & (ch < 0A0X) THEN Ch(" "); Ch(22X); Ch(ch); Ch(22X)
		ELSE WrHex(ORD(ch))
		END
	END WrChar;

	PROCEDURE WrReal (n: LONGREAL);
		VAR x: LONGREAL;
	BEGIN
		IF (MIN(LONGINT) <= n) & (n <= MAX(LONGINT)) THEN x := ABS(n - ENTIER(SHORT(n)));
			IF x < Eps THEN WrInt(n); RETURN END
		END;
		IF (MIN(REAL) <= n) & (n <= MAX(REAL)) THEN x := ABS(n - SHORT(n));
			IF x < Eps THEN
				IF (-10000 < n) & (n < 10000) THEN Texts.WriteLongRealFix(W, n, 30, 15, 0)
				ELSE Texts.WriteReal(W, short(n), 14)
				END;
				RETURN
			END
		END;
		Texts.WriteLongReal(W, n, 23)
	END WrReal;

	PROCEDURE WrValue (n: LONGREAL);
		VAR x: LONGREAL;
	BEGIN
		Str(" ="); WrReal(n);
		IF (MIN(LONGINT) <= n) & (n <= MAX(LONGINT)) THEN x := ABS(n - ENTIER(SHORT(n)));
			IF x < Eps THEN Str(" ="); WrHex(n); Str(" ="); WrInt(n);
				IF (0 <= n) & (n < 256) & (entier(n) = n) THEN Str(" ="); WrChar(n) END
			END
		END
	END WrValue;

	PROCEDURE Ln;
	BEGIN Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END Ln;


	PROCEDURE Scan (VAR S: Texts.Scanner);

		PROCEDURE hex (n: LONGINT): LONGINT;
			VAR x, i: LONGINT; d: ARRAY 8 OF LONGINT;
		BEGIN x := 0; i := 0;
			REPEAT d[i] := n MOD 10; n := n DIV 10; INC(i) UNTIL n = 0;
			WHILE i > 0 DO DEC(i); x := 16*x + d[i] END;
			RETURN x
		END hex;

	BEGIN
		IF S.eot THEN S.class := End
		ELSIF S.nextCh = "/" THEN S.class := Texts.Char; S.c := "/"; Texts.Read(S, S.nextCh)
		ELSE Texts.Scan(S)
		END;
		IF S.line # 0 THEN S.class := End END;
		IF (S.class = Texts.Char) & (S.c = " ") THEN S.c := "-"
		ELSIF (S.class = Texts.String) & (S.len = 2) THEN S.i := ORD(S.s[0]); S.class := Texts.Int
		ELSIF (S.class = Texts.Int) & (S.nextCh = "X") THEN S.i := hex(S.i);
			Texts.Read(S, S.nextCh)
		END
	END Scan;

	PROCEDURE OpenScanner (VAR S: Texts.Scanner);
		VAR text: Texts.Text; beg, end, time: LONGINT;
	BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") & (S.line = 0) THEN
			Oberon.GetSelection(text, beg, end, time);
			IF time >= lastTime THEN lastTime := time;
				Texts.OpenScanner(S, text, beg); Scan(S)
			END
		END;
		IF S.line # 0 THEN S.class := Texts.Inval END
	END OpenScanner;


	PROCEDURE FindIdent (name: ARRAY OF CHAR; insert: BOOLEAN; VAR val: LONGREAL);
		VAR s: Symbol;
	BEGIN s := syms;
		WHILE (s # NIL) & ((s.name # name) OR s.funct) DO s := s.next END;
		IF insert THEN
			IF s = NIL THEN NEW(s); s.next := syms; syms := s END;
			COPY(name, s.name); s.funct := FALSE; s.val := val
		ELSIF s # NIL THEN val := s.val
		ELSE S.class := Texts.Inval
		END
	END FindIdent;

	PROCEDURE FindFunct (name: ARRAY OF CHAR; insert: BOOLEAN; VAR sym: Symbol);
		VAR s: Symbol;
	BEGIN s := syms;
		WHILE (s # NIL) & ((s.name # name) OR ~s.funct) DO s := s.next END;
		IF insert THEN
			IF s = NIL THEN s := sym; s.next := syms; syms := sym END;
			COPY(name, s.name); s.funct := TRUE; s.val := 0
		ELSIF s # NIL THEN sym := s
		ELSE sym := NIL
		END
	END FindFunct;

	PROCEDURE InitSyms;
		VAR s: Symbol; n: LONGREAL; name: ARRAY 2 OF CHAR;
	BEGIN name[1] := 0X;
		name[0] := "e"; n := MathL.e; FindIdent(name, TRUE, n);
		n := MathL.pi; FindIdent("pi", TRUE, n);
		n := 0;
		NEW(s); FindFunct("arctan", TRUE, s);
		NEW(s); FindFunct("arccos", TRUE, s);
		NEW(s); FindFunct("arcsin", TRUE, s);
		NEW(s); FindFunct("cos", TRUE, s);
		NEW(s); FindFunct("entier", TRUE, s);
		NEW(s); FindFunct("exp", TRUE, s);
		NEW(s); FindFunct("ln", TRUE, s);
		NEW(s); FindFunct("short", TRUE, s);
		NEW(s); FindFunct("sign", TRUE, s);
		NEW(s); FindFunct("sin", TRUE, s);
		NEW(s); FindFunct("sqrt", TRUE, s);
		NEW(s); FindFunct("tan", TRUE, s)
	END InitSyms;


	PROCEDURE^ Expr (VAR n: LONGREAL);

	PROCEDURE Functor (sym: Symbol; VAR n: LONGREAL);
	BEGIN
		IF sym.name = "arcsin" THEN n := arcsin(n)
		ELSIF sym.name = "arccos" THEN n := arccos(n)
		ELSIF sym.name = "arctan" THEN n := arctan(n)
		ELSIF sym.name = "cos" THEN n := cos(n)
		ELSIF sym.name = "exp" THEN n := exp(n)
		ELSIF sym.name = "entier" THEN n := entier(n)
		ELSIF sym.name = "ln" THEN n := ln(n)
		ELSIF sym.name = "short" THEN n := short(n)
		ELSIF sym.name = "sign" THEN n := sign(n)
		ELSIF sym.name = "sin" THEN n := sin(n)
		ELSIF sym.name = "sqrt" THEN n := sqrt(n)
		ELSIF sym.name = "tan" THEN n := tan(n)
		END
	END Functor;

	PROCEDURE Atom (VAR n: LONGREAL);
		VAR sym: Symbol;
	BEGIN
		IF S.class = Texts.Int THEN n := S.i; Scan(S)
		ELSIF S.class = Texts.Real THEN n := S.x; Scan(S)
		ELSIF S.class = Texts.LongReal THEN n := S.y; Scan(S)
		ELSIF (S.class = Texts.String) & (S.s[0] # 0X) & (S.s[1] = 0X) THEN n := ORD(S.s[0]); Scan(S)
		ELSIF S.class = Texts.Name THEN FindFunct(S.s, FALSE, sym);
			IF sym # NIL THEN Scan(S); Atom(n);
				IF S.class # Texts.Inval THEN Functor(sym, n) END
			ELSE FindIdent(S.s, FALSE, n);
				IF S.class # Texts.Inval THEN Scan(S) END
			END
		ELSIF (S.class = Texts.Char) & (S.c = "(") THEN Scan(S);
			Expr(n);
			IF (S.class = Texts.Char) & (S.c = ")") THEN Scan(S)
			ELSE S.class := Texts.Inval
			END
		ELSE S.class := Texts.Inval
		END
	END Atom;

	PROCEDURE Factor (VAR n: LONGREAL);
		VAR x: LONGREAL;
	BEGIN Atom(n);
		WHILE (S.class = Texts.Char) & (S.c = "^") DO
			Scan(S); Factor(x);
			n := sign(n) * MathL.exp(MathL.ln(ABS(n)) * x)
		END
	END Factor;

	PROCEDURE Term (VAR n: LONGREAL);
		VAR x: LONGREAL; op: CHAR;
	BEGIN Factor(n);
		WHILE (S.class = Texts.Char)
		& ((S.c = "*") OR (S.c = "/") OR (S.c = "%") OR (S.c = ">") OR (S.c = "<")) DO
			op := S.c; Scan(S); Factor(x);
			CASE op OF
				"*": n := n * x
			|   "/": IF x # 0 THEN n := n / x ELSE err END
			|   "%": IF x # 0 THEN n := entier(n) MOD entier(x) ELSE err END
			|   "<": n := ASH(entier(n), entier(x))
			|   ">": n := ASH(entier(n), -entier(x))
			END
		END
	END Term;

	PROCEDURE Expr (VAR n: LONGREAL);
		VAR x: LONGREAL; op: CHAR;
	BEGIN Term(n);
		WHILE (S.class = Texts.Char) & ((S.c = "+") OR (S.c = "-")) OR (S.class = Texts.Int) DO
			IF S.class = Texts.Char THEN op := S.c; Scan(S) ELSE op := "+" END;
			Term(x);
			CASE op OF
				"+": n := n + x
			|   "-": n := n - x
			END
		END
	END Expr;


	PROCEDURE Hex*;	(** expr **)
		VAR n: LONGREAL;
	BEGIN Str("Calc.Hex"); OpenScanner(S); Expr(n);
		IF S.class # Texts.Inval THEN WrHex(n) ELSE Str(" failed: bad argument") END;
		Ln
	END Hex;

	PROCEDURE Dec*;	(** expr **)
		VAR n: LONGREAL;
	BEGIN Str("Calc.Dec"); OpenScanner(S); Expr(n);
		IF S.class # Texts.Inval THEN WrInt(n) ELSE Str(" failed: bad argument") END;
		Ln
	END Dec;

	PROCEDURE Real*;	(** expr **)
		VAR n: LONGREAL;
	BEGIN Str("Calc.Real"); OpenScanner(S); Expr(n);
		IF S.class # Texts.Inval THEN WrReal(n) ELSE Str(" failed: bad argument") END;
		Ln
	END Real;

	PROCEDURE Char*;	(** expr **)
		VAR n: LONGREAL;
	BEGIN Str("Calc.Char"); OpenScanner(S); Expr(n);
		IF S.class # Texts.Inval THEN
			IF (0 <= n) & (n < 256) THEN WrChar(n)
			ELSE Str(" failed: not a character code")
			END
		ELSE Str(" failed: bad argument")
		END;
		Ln
	END Char;

	PROCEDURE Set*;	(** {name ":=" expr} "~" **)
		VAR n: LONGREAL; name: ARRAY 32 OF CHAR;
	BEGIN Str("Calc.Set"); Ln; OpenScanner(S); 
		WHILE S.class = Texts.Name DO COPY(S.s, name); Scan(S);
			IF (S.class = Texts.Char) & (S.c = ":") THEN
				Texts.Scan(S); 
				IF (S.class = Texts.Char) & (S.c = "=") THEN
					Scan(S); Expr(n);
				ELSE S.class:=Texts.Inval
				END;
			ELSE S.class := Texts.Inval
			END;
			IF S.class # Texts.Inval THEN FindIdent(name, TRUE, n);
				IF S.class # Texts.Inval THEN Str("  "); Str(name); WrValue(n); Ln END
			END
		END;
		IF S.class = Texts.Inval THEN Str("  failed: bad argument"); Ln END
	END Set;

	PROCEDURE List*;
		VAR s: Symbol;
	BEGIN Str("Calc.List"); Ln;
		s := syms;
		WHILE s # NIL DO
			IF s.funct THEN Str("  "); Str(s.name) END;
			s := s.next
		END;
		Ln;
		s := syms;
		WHILE s # NIL DO
			IF ~s.funct THEN Str("  "); Str(s.name); WrValue(s.val); Ln END;
			s := s.next
		END
	END List;

	PROCEDURE Reset*;
	BEGIN Str("Calc.Reset"); Ln; syms := NIL; InitSyms
	END Reset;

BEGIN Texts.OpenWriter(W); Texts.WriteString(W, Version); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	lastTime := 0; syms := NIL; InitSyms
END Calc.

(*
	Edit.Open Calc.Tool

	Calc.Reset
	Calc.Set  cos := 33H  otto := 1000H  ~
	Calc.List

	Calc.Hex egon + otto
	Calc.Dec egon * 2
	Calc.Char "j" + 7
	Calc.Real cos (193 * pi)
*)
