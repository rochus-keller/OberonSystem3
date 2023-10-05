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

MODULE In; (** portable *)	(* based on module from "Programming in Oberon" *)

(** Stream oriented text input. Module In encapsulates the parameter scanning process of commands.
*)

IMPORT Texts, Oberon;

VAR
	Done*: BOOLEAN;	(** Has the last scan operation been successful? *)
	S: Texts.Scanner;

(** Initializes the parameter scanner. The parameter stream is assumed to be the selection when ^ is scanned, the marked text viewer when * is scanned; otherwise the text that follows the command itself. *)
PROCEDURE Open*;
VAR beg, end, time: LONGINT; T: Texts.Text;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);  Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "^") THEN
		Oberon.GetSelection(T, beg, end, time);
		IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Done := TRUE
		ELSE Done := FALSE
		END
	ELSIF (S.class = Texts.Char) & (S.c = "*") THEN
		T := Oberon.MarkedText();
		IF T # NIL THEN Texts.OpenScanner(S, T, 0); Done := TRUE
		ELSE Done := FALSE
		END
	ELSE
		T := Oberon.Par.text; Texts.OpenScanner(S, T, Oberon.Par.pos); Done := TRUE
	END
END Open;

(** Scan a single character. The character returned is the character immediately following the last scanned token.*)
PROCEDURE Char*(VAR ch: CHAR);
BEGIN
	IF Done THEN ch := S.nextCh; Done := ~S.eot; Texts.Read(S, S.nextCh) END
END Char;

(** Scan an integer. *)
PROCEDURE Int*(VAR i: INTEGER);
BEGIN
	IF Done THEN
		Texts.Scan(S);
		IF (S.class = Texts.Int) & (MIN(INTEGER) <= S.i) & (S.i <= MAX(INTEGER)) THEN
			i := SHORT(S.i)
		ELSE
			Done := FALSE
		END
	END
END Int;

(** Scan a long integer. *)
PROCEDURE LongInt* (VAR i: LONGINT);
BEGIN
	IF Done THEN
		Texts.Scan(S);
		IF S.class = Texts.Int THEN i := S.i ELSE Done := FALSE END
	END
END LongInt;

(** Scan a real number. *)
PROCEDURE Real* (VAR x: REAL);
BEGIN
	IF Done THEN Texts.Scan(S);
		IF S.class = Texts.Real THEN x := S.x
		ELSIF S.class = Texts.Int THEN x := S.i
		ELSE Done := FALSE
		END
	END
END Real;

(** Scan a long real number. *)
PROCEDURE LongReal* (VAR y: LONGREAL);
BEGIN
	IF Done THEN
		Texts.Scan(S);
		IF S.class = Texts.LongReal THEN y := S.y
		ELSIF S.class = Texts.Real THEN y := S.x
		ELSIF S.class = Texts.Int THEN y := S.i
		ELSE Done := FALSE
		END
	END
END LongReal;

(** Scan a name. The syntax of a name is the same as that of the module Texts scanner. *)
PROCEDURE Name* (VAR name: ARRAY OF CHAR);
BEGIN
	IF Done THEN
		Texts.Scan(S);
		IF S.class = Texts.Name THEN COPY(S.s, name)
		ELSE Done := FALSE
		END
	END
END Name;

(** Scan a double quoted string. The quotes are not returned. *)
PROCEDURE String* (VAR str: ARRAY OF CHAR);
BEGIN
	IF Done THEN
		Texts.Scan(S);
		IF (S.class = Texts.String) OR (S.class = Texts.Name) THEN COPY(S.s, str)
		ELSE Done := FALSE
		END
	END
END String;

BEGIN
	Done := FALSE
END In.

(** Remarks:

1. Module In provides a primitive interface to parameter scanning. It is mainly used in situations where the command parameters must appear in a predefined sequence, and for Oberon beginners. A more flexible means of scanning parameters is provided in the Texts module.

2. Suppose we need to program a command Example.Calculate. There are three ways of passing parameters to this command:

	Example.Calculate par1 par2 par3 ~	Parameters follow directly after the command.
	Example.Calculate ^	Parameters are contained in the text selection.
	Example.Calculate *	Parameters are found in the marked text viewer.
To hide the three parameter passing styles, we can program Example.Calculate in the following way:

	PROCEDURE Calculate*;
	VAR s: ARRAY 64 OF CHAR;
	BEGIN
		In.Open;	(* Initialize the scanner according to one of the three parameter passing styles. *)
		WHILE In.Done DO
			In.Name(s);	(* scan the next name *)
		END
	END Calculate;

After each call to an In scan procedure, the In.Done flag is set to true if a parameter of that type was found in the parameters. If an unexpected parameter (say an integer instead of an string) was scanned, In.Done is is set to FALSE and scanning is immediately terminated. Calls to In will now have no effect until In.Open is called again.

3. The parameter scanner ignores whitespace (characters SPACE 20X, TAB 9X, and CR 0DX).
*)