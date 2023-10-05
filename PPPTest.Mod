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

MODULE PPPTest;	(** non-portable *)	(* pjm *)
(* $VCS   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 21:19:47 $
    $Log$
$   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 21:19:47
first versioned version, with configurable logging
*)
(* Test procedures for PPP *)

IMPORT SYSTEM, PPPDebug, PPPHDLC, Texts, Oberon, Fonts, Out;

CONST
	MaxSize = 10000H;

VAR
	w: Texts.Writer;
	
PROCEDURE WriteHex(x, width: LONGINT);
VAR
	buf: ARRAY 9 OF CHAR;
	i, j: LONGINT;
BEGIN
	buf[0] := " ";	buf[1] := 0X;
	IF width >= 0 THEN j := 8 ELSE j := 2; width := -width END;
	FOR i := j+1 TO width DO Texts.WriteString(w, buf) END;
	FOR i := j-1 TO 0 BY -1 DO
		buf[i] := CHR(x MOD 10H + 48);
		IF buf[i] > "9" THEN
			buf[i] := CHR(ORD(buf[i]) - 48 + 65 - 10)
		END;
		x := x DIV 10H
	END;
	buf[j] := 0X;
	Texts.WriteString(w, buf)
END WriteHex;

PROCEDURE ShowLogHex*;
CONST W = 16;
VAR t: Texts.Text;  i, j, k, adr, size: LONGINT;  x: SHORTINT;
BEGIN
	NEW(t);  Texts.Open(t, "");
	size := PPPDebug.LogLen;
	i := 0;  adr := SYSTEM.ADR(PPPDebug.Log[0]);
	WHILE (i < size) DO
		WriteHex(adr+i, 8);  Texts.WriteString(w, "H: ");
		(* Do Hex dump. *)
		j := i;
		WHILE (j < i+W) & (j < size) DO
			SYSTEM.GET(adr+j, x);
			WriteHex(x, -3);
			INC(j)
		END;
		(* Spaces between Hex dump and ASCII dump. *)
		FOR k := j TO i+W-1 DO Texts.WriteString(w, "   ") END;
		Texts.WriteString(w, "     ");
		(* Do ASCII dump. *)
		j := i;
		WHILE (j < i+W) & (j < size) DO
			SYSTEM.GET(adr+j, x);
			IF (x > 01FH) & (x < 07FH) THEN Texts.Write(w, CHR(x))
			ELSE Texts.Write(w, ".") END;
			INC(j)
		END;
		Texts.WriteLn(w);
		INC(i, W)
	END;
	Texts.Append(t, w.buf);
	Oberon.OpenText("", t, 400, 200)
END ShowLogHex;

PROCEDURE ShowLog*;
VAR t: Texts.Text;  i: LONGINT;
BEGIN
	NEW(t);  Texts.Open(t, "");
	FOR i := 0 TO PPPDebug.LogLen-1 DO
		IF PPPDebug.Log[i] = 0DX THEN Texts.WriteLn(w)
		ELSE Texts.Write(w, PPPDebug.Log[i])
		END
	END;
	IF PPPDebug.full THEN
		Texts.WriteString(w, "------ leading------ edge -------");
		Texts.WriteLn(w);
		FOR i := PPPDebug.LogLen TO PPPDebug.LogSize-1 DO
			IF PPPDebug.Log[i] = 0DX THEN Texts.WriteLn(w)
			ELSE Texts.Write(w, PPPDebug.Log[i])
			END
		END;
	END;
	Texts.Append(t, w.buf);
	Oberon.OpenText("", t, 400, 200)
END ShowLog;

(** managing the flag for logging PPP traffic for debugging. Default is off *)
PROCEDURE LogState*;
BEGIN
	IF PPPHDLC.debug THEN
		Out.String("PPP logging is on"); Out.Ln;
	ELSE
		Out.String("PPP logging is off"); Out.Ln;
	END;
END LogState;
	
PROCEDURE LogOn*;
BEGIN
	PPPHDLC.debug := TRUE;
	Out.String("PPP logging turned on"); Out.Ln;
END LogOn;

PROCEDURE LogOff*;
BEGIN
	PPPHDLC.debug := FALSE;
	Out.String("PPP logging turned off"); Out.Ln;
END LogOff;

BEGIN
	Texts.OpenWriter(w);  Texts.SetFont(w, Fonts.This("Courier10.Scn.Fnt"))
END PPPTest.

PPPTest.ShowLog
PPPTest.ShowLogHex

PPPTest.LogState
PPPTest.LogOn
PPPTest.LogOff
