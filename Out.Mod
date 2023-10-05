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

MODULE Out; (** portable *)	(* based on module from "Programming in Oberon" *)

(** Simple output routines for writing text into the Oberon log or a seperate viewer.
*)

IMPORT Texts, Oberon;

VAR T: Texts.Text; W: Texts.Writer;

(** Write character. *)
PROCEDURE Char*(ch: CHAR);
BEGIN
	Texts.Write(W, ch); Texts.Append(T, W.buf)
END Char;

(** Write a string. *)
PROCEDURE String*(str: ARRAY OF CHAR);
BEGIN
	Texts.WriteString(W, str); Texts.Append(T, W.buf)
END String;

(** Write the integer i in n field positions. *)
PROCEDURE Int*(i, n: LONGINT);
BEGIN
	Texts.WriteInt(W, i, n); Texts.Append(T, W.buf)
END Int;

(** Write the real x in n field positions. *)
PROCEDURE Real*(x: REAL; n: INTEGER);
BEGIN
	Texts.WriteReal(W, x, n); Texts.Append(T, W.buf)
END Real;

(** Write the longreal x in n field positions. *)
PROCEDURE LongReal*(x: LONGREAL; n: INTEGER);
BEGIN
	Texts.WriteLongReal(W, x, n); Texts.Append(T, W.buf)
END LongReal;

(** Write a carriage return (CR or end-of-line). *)
PROCEDURE Ln*;
BEGIN
	Texts.WriteLn(W); Texts.Append(T, W.buf)
END Ln;

(** Open a new viewer and text for log output. *)
PROCEDURE Open*;
BEGIN
	IF T = Oberon.Log THEN NEW(T); Texts.Open(T, "") END;
	Oberon.OpenText("Out.Text", T, 400, 200)
END Open;

BEGIN
	Texts.OpenWriter(W);  T := Oberon.Log
END Out.

(** Remarks:

1. Out uses a Writer from module Texts to write output to the log. Writing output using Out is slow because the log is updated after every procedure call. For fast and flexible output, use module Texts.

2. Out.Open creates a new text and viewer for output.  Once this is done, output is never sent to the system log again.
*)
