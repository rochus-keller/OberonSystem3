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

MODULE LayLaS;	(** portable *)	(*	Jörg Derungs, 31.7.1996	*)

IMPORT Texts, Oberon, Layouts;

CONST	(** symbol constants *)
		null* = 0;
		(** special caracters *)
		open* = 1; close* = 2; equal* = 4; lbrak* = 6; rbrak* = 7;
		(** argument types *)
		String* = 20; Int* = 21; Real* = 22; Char* = 23; Bool* = 24; Qualident* = 28; Ident* = 29;
		(** operators *)
		Config* = 30; New* = 31; HList* = 32; VList* = 33; Table* = 34; Place* = 35;
		Deep* = 37; Shallow* = 38; Include* = 39;
		Def* = 40; Set* = 41; Params* = 42; Layout* = 43; Attributes* = 44; Links* = 45;
		Virtual* = 46; Default* = 47; Break* = 48; Span* = 49;
		(** special values *)
		Left* = Layouts.Left; Right* = Layouts.Right; Bottom* = Layouts.Bottom; Top* = Layouts.Top;
		Center* = Layouts.Center; Static* = Layouts.Static; Dynamic* = Layouts.Dynamic;
		Hor* = Layouts.Hor; Vert* = Layouts.Vert;

		strlen = 256;
		idlen = 64;

VAR  reader : Texts.Reader;
		ch : CHAR;
		W : Texts.Writer;
		
		error* : BOOLEAN;
		eot* : BOOLEAN;
		errpos : LONGINT;
		
		s* : ARRAY strlen OF CHAR;
		ident* : ARRAY idlen OF CHAR;
		int* : LONGINT;
		real* : REAL;
		char* : CHAR;
		bool* : BOOLEAN;

PROCEDURE Pos* () : LONGINT;		(**	Position of scanner in text	*)
BEGIN	RETURN Texts.Pos(reader)
END Pos;

PROCEDURE Mark* (pos : LONGINT; t : ARRAY OF CHAR);		(**	Write error message t to Log	*)
VAR p : LONGINT;
BEGIN	p := Pos ();
	IF p > errpos THEN
		Texts.WriteString (W, "  pos "); Texts.WriteInt(W, pos, 1);
		Texts.WriteString(W, "  err "); Texts.WriteString(W, t);
		Texts.WriteLn (W);
		Texts.Append (Oberon.Log, W.buf);
	END;
	errpos:=p; error:=TRUE
END Mark;

PROCEDURE ReadChar;
BEGIN	IF ~reader.eot THEN Texts.Read (reader, ch) ELSE ch := ')'; eot := TRUE END
END ReadChar;

PROCEDURE Comment;
VAR p : LONGINT;
BEGIN	p := Pos ();
	REPEAT ReadChar;
		IF ch = '{' THEN Comment END;
		IF eot THEN Mark (p, "Comment not closed"); ch := '}' END
	UNTIL ch = '}';
	ReadChar;
END Comment;

PROCEDURE ReadString (VAR sym : INTEGER);
VAR i : INTEGER;
		quot : CHAR;
		pos : LONGINT;
BEGIN	quot := ch;
	ReadChar; sym := String; pos := Pos ();
	i := 0;
	WHILE (ch # quot) & ~eot DO
		IF i < strlen THEN	s[i] := ch; INC (i)	END;
		ReadChar
	END;
	s[strlen-1] := 0X;
	IF ch # quot THEN Mark (pos, "String not closed")
	ELSIF i = strlen THEN Mark (pos, "String too long")
	ELSE s[i] := 0X END;
	ReadChar;
END ReadString;

PROCEDURE ReadNumber (VAR sym : INTEGER);
VAR  intE, realE : BOOLEAN;
		n : INTEGER;
		quotient : REAL;
BEGIN	sym := Int;
	int := 0;	real := 0;	intE := FALSE;	realE := FALSE;
	WHILE (ch >= '0') & (ch <= '9') DO
		n := ORD(ch)-ORD('0');
		IF (MAX(LONGINT)-n) DIV 10 >= int THEN
			int := int*10 + n;	real := int
		ELSIF (MAX(REAL)-n)/10 >= real THEN
			intE := TRUE;
			real := real*10 + ORD(ch)-ORD('0')
		ELSE realE := TRUE
		END;
		ReadChar
	END;
	IF ch = '.' THEN
		sym := Real;	quotient := 1;
		ReadChar;
		WHILE (ch >= '0') & (ch <= '9') DO
			quotient := quotient/10;	real := real + (ORD(ch)-ORD('0'))*quotient;
			ReadChar;
		END;
	END;
	IF (sym = Int) & intE THEN Mark (Pos (), "Integer overflow")
	ELSIF (sym = Real) & realE THEN Mark (Pos (), "real overflow")
	END
END ReadNumber;

PROCEDURE ReadIdent (VAR sym : INTEGER);
VAR i : INTEGER;
BEGIN	sym := Ident;
	i := 0;
	WHILE ((CAP(ch) >= 'A') & (CAP(ch) <= 'Z')) OR ((ch >= '0') & (ch <= '9')) DO
		IF i < idlen THEN ident[i] := ch; INC (i) END;
		ReadChar
	END;
	WHILE ch = '.' DO	sym := Qualident;
		IF i < idlen THEN ident[i] := ch; INC (i) END;
		ReadChar;
		WHILE ((CAP(ch) >= 'A') & (CAP(ch) <= 'Z')) OR ((ch >= '0') & (ch <= '9')) DO
			IF i < idlen THEN ident[i] := ch; INC (i) END;
			ReadChar
		END;
	END;
	IF i = idlen THEN Mark (Pos (), "Identifier too long"); ident[i-1] := 0X ELSE ident[i] := 0X END;
END ReadIdent;

PROCEDURE Get* (VAR sym : INTEGER);		(**	Get next symbol	*)
BEGIN
	IF eot THEN Mark (Pos (), "end of text") END;
	WHILE (ch <= ' ') & (~eot) DO ReadChar END;
	CASE ch OF
	| '(' : ReadChar; sym := open
	| ')' : ReadChar; sym := close
	| '[' : ReadChar; sym := lbrak
	| ']' : ReadChar; sym := rbrak
	| '-' : ReadChar; IF (ch >= '0') & (ch <= '9') THEN ReadNumber (sym); int := -int; real := -real
								ELSE sym := null END
	| '=' : ReadChar; sym := equal
	| '{' : Comment; Get (sym)
	| '"', "'" : ReadString (sym)
	| '#' : ReadChar; sym := Char; char := ch; ReadChar
	| '0'..'9' : ReadNumber (sym)
	| 'A' : ReadIdent (sym);	IF (ident = "ATTR") OR (ident = "ATTRIBUTES") THEN sym := Attributes END
	| 'B' : ReadIdent (sym);	IF ident = "BREAK" THEN sym := Break
											ELSIF ident = "BOTTOM" THEN sym := Bottom END
	| 'C' : ReadIdent (sym);	IF ident = "CONFIG" THEN sym := Config
											ELSIF ident = "CENTER" THEN sym := Center END
	| 'D' : ReadIdent (sym);	IF ident = "DEF" THEN sym := Def
											ELSIF ident = "DYNAMIC" THEN sym := Dynamic
											ELSIF ident = "DCOPY" THEN sym := Deep
											ELSIF ident = "DEFAULT" THEN sym := Default END
	| 'F' : ReadIdent (sym);	IF ident = "FALSE" THEN sym := Bool; bool := FALSE END
	| 'H' : ReadIdent (sym);	IF ident = "HLIST" THEN sym := HList
											ELSIF ident = "HOR" THEN sym := Hor END
	| 'I' : ReadIdent (sym);	IF ident = "INCLUDE" THEN sym := Include END
	| 'L' : ReadIdent (sym);	IF ident = "LINKS" THEN sym := Links
											ELSIF ident = "LAYOUT" THEN sym := Layout
											ELSIF ident = "LEFT" THEN sym := Left END
	| 'N' : ReadIdent (sym);	IF ident = "NEW" THEN sym := New END
	| 'P' : ReadIdent (sym);	IF ident = "PLACE" THEN sym := Place
											ELSIF ident = "PARAMS" THEN sym := Params END
	| 'R' : ReadIdent (sym);	IF ident = "RIGHT" THEN sym := Right END;
	| 'S' : ReadIdent (sym);	IF ident = "STATIC" THEN sym := Static
											ELSIF ident = "SPAN" THEN sym := Span
											ELSIF ident = "SCOPY" THEN sym := Shallow
											ELSIF ident = "SET" THEN sym := Set END
	| 'T' : ReadIdent (sym);	IF ident = "TABLE" THEN sym := Table
											ELSIF ident = "TRUE" THEN sym := Bool; bool := TRUE
											ELSIF ident = "TOP" THEN sym := Top END
	| 'V' : ReadIdent (sym);	IF ident = "VIRTUAL" THEN sym := Virtual
											ELSIF ident = "VLIST" THEN sym := VList
											ELSIF ident = "VERT" THEN sym := Vert END
	| 'a'..'z', 'E', 'G', 'J', 'K', 'M', 'O', 'Q', 'U', 'W'..'Z' : ReadIdent (sym)
	ELSE sym := null; ReadChar;
	END;
END Get;

PROCEDURE OpenText* (text : Texts.Text; pos : LONGINT);
BEGIN
	Texts.OpenReader (reader, text, pos);
	ch := ' ';
	errpos := pos;
	eot := FALSE;
END OpenText;

PROCEDURE Init*;		(**	to be executed before reading the layout	*)
BEGIN
	error := FALSE;
END Init;

BEGIN
	Texts.OpenWriter (W);
END LayLaS.
