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

MODULE WTSFold;	(** portable *)

IMPORT
	Objects, Files, Texts, WTS, Outlines;
	
CONST
	colLeft* = 0; colRight* = 1; expRight* = 2; expLeft* = 3;	(*fold element mode*)
	leftMode = {colLeft, expLeft};

PROCEDURE New*;
VAR k, mode: SHORTINT;  len: LONGINT; F: Outlines.Outline; t: Texts.Text; ch: CHAR;
BEGIN
	Objects.NewObj := NIL; F:= Outlines.MakeOutline(-1);
	Files.Read(WTS.R, k); mode := k MOD 4;
	IF mode IN leftMode THEN
		NEW(F.buf); Texts.OpenBuf(F.buf);
		IF k < 4 THEN
			NEW(t);
			Files.Read(WTS.R, ch);
			IF (ch = Texts.TextBlockId) THEN
				Texts.Load(t, Files.Base(WTS.R), Files.Pos(WTS.R), len);
				Texts.Save(t, 0, t.len, F.buf);
			END
		END
	END;
	IF mode = colLeft THEN
		F.fstate := Outlines.folded; Objects.NewObj := F
	ELSIF mode = colRight THEN
	ELSIF mode = expLeft THEN
		F.fstate := Outlines.open; Objects.NewObj := F
	ELSIF mode = expRight THEN
		F.fstate := Outlines.close; Objects.NewObj := F
	END
END New;

END WTSFold.
