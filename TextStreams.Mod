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

MODULE TextStreams;	(** portable *)
	IMPORT SYSTEM, Streams, Strings, Reals, Texts;

	TYPE
		ReaderStream = POINTER TO ReaderStreamDesc;
		ReaderStreamDesc = RECORD (Streams.StreamDesc)
			R: Texts.Reader;
			T: Texts.Text;
			pos: LONGINT;
			ch: CHAR
		END;
		WriterStream = POINTER TO WriterStreamDesc;
		WriterStreamDesc = RECORD (Streams.StreamDesc)
			W: Texts.Writer;
			T: Texts.Text
		END;

	PROCEDURE Read*(S: Streams.Stream; VAR ch: CHAR);
	BEGIN
		S.ReadBytes(S, ch, 1);
		IF S.mode = Streams.iso8859 THEN
			ch := Strings.ISOToOberon[ORD(ch)]
		END
	END Read;

(** Reads a line of text, terminated by [CR] LF (mode = Streams.iso8859) or CR (mode # Streams.iso8859). *)
	PROCEDURE ReadString*(S: Streams.Stream; VAR s: ARRAY OF CHAR);
		VAR
			i: LONGINT;
			ch, ch0: CHAR;
	BEGIN
		i := -1; ch := 0X;
		IF S.mode = Streams.iso8859 THEN
			REPEAT
				INC(i); ch0 := ch; S.ReadBytes(S, ch, 1); s[i] := Strings.ISOToOberon[ORD(ch)]
			UNTIL (ch = 0X) OR (ch = Strings.LF);
			IF ch0 = Strings.CR THEN
				s[i-1] := 0X
			ELSE
				s[i] := 0X
			END
		ELSE
			REPEAT
				INC(i); S.ReadBytes(S, ch, 1); s[i] := ch
			UNTIL (ch = 0X) OR (ch = Strings.CR);
			s[i] := 0X
		END
	END ReadString;

	PROCEDURE Write*(S: Streams.Stream; ch: CHAR);
	BEGIN
		IF S.mode = Streams.iso8859 THEN
			IF ch # Strings.CR THEN
				Streams.Write(S, Strings.OberonToISO[ORD(ch)])
			ELSE
				S.WriteBytes(S, Strings.CRLF, 2)
			END
		ELSE
			S.WriteBytes(S, ch, 1)
		END
	END Write;

(** Routines for formatted output, similar to module Texts. *)

	PROCEDURE WriteDate*(S: Streams.Stream; t, d: LONGINT);
		PROCEDURE WritePair(ch: CHAR; x: LONGINT);
		BEGIN
			S.WriteBytes(S, ch, 1); Streams.Write(S, CHR(x DIV 10 + 30H)); Streams.Write(S, CHR(x MOD 10 + 30H))
		END WritePair;
	BEGIN
		WritePair(" ", d MOD 32); WritePair(".", d DIV 32 MOD 16); WritePair(".", d DIV 512 MOD 128);
		WritePair(" ", t DIV 4096 MOD 32); WritePair(":", t DIV 64 MOD 64); WritePair(":", t MOD 64)
	END WriteDate;

	PROCEDURE WriteHex*(S: Streams.Stream; x: LONGINT);
		VAR
			i, y: LONGINT;
			a: ARRAY 12 OF CHAR;
	BEGIN
		i := 0; Streams.Write(S, " ");
		REPEAT y := x MOD 10H;
			IF y < 10 THEN a[i] := CHR(y + 30H) ELSE a[i] := CHR(y + 37H) END;
			x := x DIV 10H; INC(i)
		UNTIL i = 8;
		REPEAT
			DEC(i); S.WriteBytes(S, a[i], 1)
		UNTIL i = 0
	END WriteHex;

	PROCEDURE WriteString*(S: Streams.Stream; s: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		IF S.mode = Streams.iso8859 THEN
			WHILE s[i] # 0X DO
				Streams.Write(S, Strings.OberonToISO[ORD(s[i])]); INC(i)
			END
		ELSE
			WHILE s[i] # 0X DO
				S.WriteBytes(S, s[i], 1); INC(i)
			END
		END
	END WriteString;

	PROCEDURE WriteInt*(S: Streams.Stream; x, n: LONGINT);
		VAR
			i, x0: LONGINT;
			a: ARRAY 12 OF CHAR;
	BEGIN
		i := 0;
		IF x < 0 THEN
			IF x = MIN(LONGINT) THEN
				WriteString(S, " -2147483648"); RETURN
			ELSE
				DEC(n); x0 := -x
			END
		ELSE
			x0 := x
		END;
		REPEAT
			a[i] := CHR(x0 MOD 10 + 30H); x0 := x0 DIV 10; INC(i)
		UNTIL x0 = 0;
		WHILE n > i DO
			Streams.Write(S, " "); DEC(n)
		END;
		IF x < 0 THEN Streams.Write(S, "-") END;
		REPEAT
			DEC(i); S.WriteBytes(S, a[i], 1)
		UNTIL i = 0
	END WriteInt;

	PROCEDURE WriteLn*(S: Streams.Stream);
	BEGIN
		IF S.mode = Streams.iso8859 THEN
			S.WriteBytes(S, Strings.CRLF, 2)
		ELSE
			Streams.Write(S, Strings.CR)
		END
	END WriteLn;

	PROCEDURE WriteLongReal*(S: Streams.Stream; x: LONGREAL; n: LONGINT);
	(* BM 1993.4.22. Do not simplify rounding! *)
		VAR
			e, h, l, i: LONGINT;
			z: LONGREAL;
			d: ARRAY 16 OF CHAR;
	BEGIN
		e := Reals.ExpoL(x);
		IF e = 2047 THEN
			WHILE n > 9 DO Streams.Write(S, " "); DEC(n) END;
			WriteString(S, "      NaN")
		ELSE
			IF n <= 9 THEN n := 1 ELSE DEC(n, 8) END;
			REPEAT Streams.Write(S, " "); DEC(n) UNTIL n <= 15; (* 0 <= n <= 15 fraction digits *)
			IF (e # 0) & (x < 0) THEN Streams.Write(S, "-"); x := - x ELSE Streams.Write(S, " ") END;
			IF e = 0 THEN
				h := 0; l := 0 (* no denormals *)
			ELSE
				e := (e - 1023) * 301029 DIV 1000000; (* ln(2)/ln(10) = 0.301029996 *)
				z := Reals.Ten(e+1);
				IF x >= z THEN x := x/z; INC(e) ELSE x := x * Reals.Ten(-e) END;
				IF x >= 10 THEN
					x := x * Reals.Ten(-1) + 0.5D0 / Reals.Ten(n); INC(e)
				ELSE
					x := x + 0.5D0 / Reals.Ten(n);
					IF x >= 10 THEN x := x * Reals.Ten(-1); INC(e) END
				END;
				x := x * Reals.Ten(7); h := ENTIER(x); x := (x-h) * Reals.Ten(8); l := ENTIER(x)
			END;
			i := 15;
			WHILE i > 7 DO d[i] := CHR(l MOD 10 + ORD("0")); l := l DIV 10; DEC(i) END;
			WHILE i >= 0 DO d[i] := CHR(h MOD 10 + ORD("0")); h := h DIV 10; DEC(i) END;
			S.WriteBytes(S, d[0], 1); Streams.Write(S, ".");
			i := 1;
			WHILE i <= n DO S.WriteBytes(S, d[i], 1); INC(i) END;
			IF e < 0 THEN WriteString(S, "D-"); e := - e ELSE WriteString(S, "D+") END;
			Streams.Write(S, CHR(e DIV 100 + ORD("0"))); e := e MOD 100;
			Streams.Write(S, CHR(e DIV 10 + ORD("0"))); Streams.Write(S, CHR(e MOD 10 + ORD("0")))
		END
	END WriteLongReal;

	PROCEDURE WriteLongRealFix*(S: Streams.Stream; x: LONGREAL; n, f, D: LONGINT);
	(* BM 1993.4.22. Do not simplify rounding! / JG formatting adjusted *)
		VAR
			e, h, l, i: LONGINT;
			r, z: LONGREAL;
			d: ARRAY 16 OF CHAR;
			s: CHAR;
	BEGIN
		e := Reals.ExpoL(x);
		IF (e = 2047) OR (ABS(D) > 308) THEN
			WHILE n > 9 DO Streams.Write(S, " "); DEC(n) END;
			WriteString(S, "      NaN")
		ELSE
			IF D = 0 THEN DEC(n, 2) ELSE DEC(n, 7) END;
			IF n < 2 THEN n := 2 END; IF f < 0 THEN f := 0 END;
			IF n < f + 2 THEN n := f + 2 END; DEC(n, f);
			IF (e # 0) & (x < 0) THEN s := "-"; x := - x ELSE s := " " END;
			IF e = 0 THEN
				h := 0; l := 0; DEC(e, D-1) (* no denormals *)
			ELSE
				e := (e - 1023) * 301029 DIV 1000000; (* ln(2)/ln(10) = 0.301029996 *)
				z := Reals.Ten(e+1);
				IF x >= z THEN x := x/z; INC(e) ELSE x:= x * Reals.Ten(-e) END;
				DEC(e, D-1); i := -(e+f);
				IF i <= 0 THEN r := 5 * Reals.Ten(i) ELSE r := 0 END;
				IF x >= 10 THEN
					x := x * Reals.Ten(-1) + r; INC(e)
				ELSE
					x := x + r;
					IF x >= 10 THEN x := x * Reals.Ten(-1); INC(e) END
				END;
				x := x * Reals.Ten(7); h:= ENTIER(x); x := (x-h) * Reals.Ten(8); l := ENTIER(x)
			END;
			i := 15;
			WHILE i > 7 DO d[i] := CHR(l MOD 10 + ORD("0")); l := l DIV 10; DEC(i) END;
			WHILE i >= 0 DO d[i] := CHR(h MOD 10 + ORD("0")); h := h DIV 10; DEC(i) END;
			IF n <= e THEN n := e + 1 END;
			IF e > 0 THEN
				WHILE n > e DO Streams.Write(S, " "); DEC(n) END;
				S.WriteBytes(S, s, 1); e:= 0;
				WHILE n > 0 DO
					DEC(n);
					IF e < 16 THEN S.WriteBytes(S, d[e], 1); INC(e) ELSE Streams.Write(S, "0") END
				END;
				Streams.Write(S, ".")
			ELSE
				WHILE n > 1 DO Streams.Write(S, " "); DEC(n) END;
				S.WriteBytes(S, s, 1); Streams.Write(S, "0"); Streams.Write(S, ".");
				WHILE (0 < f) & (e < 0) DO Streams.Write(S, "0"); DEC(f); INC(e) END
			END;
			WHILE f > 0 DO
				DEC(f);
				IF e < 16 THEN S.WriteBytes(S, d[e], 1); INC(e) ELSE Streams.Write(S, "0") END
			END;
			IF D # 0 THEN
				IF D < 0 THEN WriteString(S, "D-"); D := - D ELSE WriteString(S, "D+") END;
				Streams.Write(S, CHR(D DIV 100 + ORD("0"))); D := D MOD 100;
				Streams.Write(S, CHR(D DIV 10 + ORD("0"))); Streams.Write(S, CHR(D MOD 10 + ORD("0")))
			END
		END
	END WriteLongRealFix;

	PROCEDURE WriteLongRealHex*(S: Streams.Stream; x: LONGREAL);
		VAR h, l: LONGINT; (* BM 1991.12.25 *)
	BEGIN
		Reals.IntL(x, h, l); WriteHex(S, h); WriteHex(S, l)
	END WriteLongRealHex;

	PROCEDURE WriteReal*(S: Streams.Stream; x: REAL; n: LONGINT);
	(* BM 1993.4.22. Do not simplify rounding! *)
		VAR
			e, h, i: LONGINT;
			y: LONGREAL;
			z: REAL;
			d: ARRAY 8 OF CHAR;
	BEGIN
		e:= Reals.Expo(x);
		IF e = 255 THEN
			WHILE n > 8 DO Streams.Write(S, " "); DEC(n) END;
			WriteString(S, "     NaN")
		ELSE
			IF n <= 8 THEN n := 1 ELSE DEC(n, 7) END;
			REPEAT Streams.Write(S, " "); DEC(n) UNTIL n <= 7; (* 0 <= n <= 7 fraction digits *)
			IF (e # 0) & (x < 0) THEN Streams.Write(S, "-"); x := - x ELSE Streams.Write(S, " ") END;
			IF e = 0 THEN
				h := 0 (* no denormals *)
			ELSE
				e := (e - 127) * 301 DIV 1000; (* ln(2)/ln(10) = 0.301029996 *)
				IF e < 38 THEN
					z := SHORT(Reals.Ten(e+1));
					IF x >= z THEN y := LONG(x)/LONG(z); INC(e) ELSE y := x * Reals.Ten(-e) END
				ELSE
					y := x * Reals.Ten(-38)
				END;
				IF y >= 10 THEN
					y := y * Reals.Ten(-1) + 0.5D0 / Reals.Ten(n); INC(e)
				ELSE
					y := y + 0.5D0 / Reals.Ten(n);
					IF y >= 10 THEN y := y * Reals.Ten(-1); INC(e) END
				END;
				y := y * Reals.Ten(7); h := ENTIER(y)
			END;
			i := 7;
			WHILE i >= 0 DO d[i] := CHR(h MOD 10 + ORD("0")); h := h DIV 10; DEC(i) END;
			S.WriteBytes(S, d[0], 1); Streams.Write(S, ".");
			i := 1;
			WHILE i <= n DO S.WriteBytes(S, d[i], 1); INC(i) END;
			IF e < 0 THEN WriteString(S, "E-"); e := - e ELSE WriteString(S, "E+") END;
			Streams.Write(S, CHR(e DIV 10 + ORD("0")));
			Streams.Write(S, CHR(e MOD 10 + ORD("0")))
		END
	END WriteReal;

	PROCEDURE WriteRealFix*(S: Streams.Stream; x: REAL; n, f, E: LONGINT);
	(* BM 1993.4.22. Do not simplify rounding ! / JG formatting adjusted *)
		VAR e, h, i: LONGINT; r, y: LONGREAL; z: REAL; s: CHAR; d: ARRAY 8 OF CHAR;
	BEGIN
		e := Reals.Expo(x);
		IF (e = 255) OR (ABS(E) > 38) THEN
			WHILE n > 8 DO Streams.Write(S, " "); DEC(n) END;
			WriteString(S, "     NaN")
		ELSE
			IF E = 0 THEN DEC(n, 2) ELSE DEC(n, 6) END;
			IF f < 0 THEN f := 0 END; IF n < f + 2 THEN n := f + 2 END;
			DEC(n, f);
			IF (e # 0) & (x < 0) THEN s := "-"; x := - x ELSE s := " " END;
			IF e = 0 THEN
				h := 0; DEC(e, E-1) (* no denormals *)
			ELSE
				e := (e - 127) * 301 DIV 1000; (* ln(2)/ln(10) = 0.301029996 *)
				IF e < 38 THEN
					z := SHORT(Reals.Ten(e+1));
					IF x >= z THEN y := LONG(x)/LONG(z); INC(e) ELSE y := x * Reals.Ten(-e) END
				ELSE
					y := x * Reals.Ten(-38)
				END;
				DEC(e, E-1); i := -(e+f);
				IF i <= 0 THEN r := 5 * Reals.Ten(i) ELSE r := 0 END;
				IF y >= 10 THEN
					y := y * Reals.Ten(-1) + r; INC(e)
				ELSE
					y := y + r;
					IF y >= 10 THEN y := y * Reals.Ten(-1); INC(e) END
				END;
				y := y * Reals.Ten(7); h := ENTIER(y)
			END;
			i := 7;
			WHILE i >= 0 DO d[i] := CHR(h MOD 10 + ORD("0")); h := h DIV 10; DEC(i) END;
			IF n <= e THEN n := e + 1 END;
			IF e > 0 THEN
				WHILE n > e DO Streams.Write(S, " "); DEC(n) END;
				S.WriteBytes(S, s, 1); e := 0;
				WHILE n > 0 DO DEC(n);
					IF e < 8 THEN S.WriteBytes(S, d[e], 1); INC(e) ELSE Streams.Write(S, "0") END
				END;
				Streams.Write(S, ".")
			ELSE
				WHILE n > 1 DO Streams.Write(S, " "); DEC(n) END;
				S.WriteBytes(S, s, 1); Streams.Write(S, "0"); Streams.Write(S, ".");
				WHILE (0 < f) & (e < 0) DO Streams.Write(S, "0"); DEC(f); INC(e) END
			END;
			WHILE f > 0 DO DEC(f);
				IF e < 8 THEN S.WriteBytes(S, d[e], 1); INC(e) ELSE Streams.Write(S, "0") END
			END;
			IF E # 0 THEN
				IF E < 0 THEN
					WriteString(S, "E-"); E := - E
				ELSE
					WriteString(S, "E+")
				END;
				Streams.Write(S, CHR(E DIV 10 + ORD("0"))); Streams.Write(S, CHR(E MOD 10 + ORD("0")))
			END
		END
	END WriteRealFix;

	PROCEDURE WriteRealHex*(S: Streams.Stream; x: REAL);
	BEGIN (* BM 1991.12.25 *)
		WriteHex(S, Reals.Int(x))
	END WriteRealHex;

	PROCEDURE *ReadTextBytes(S: Streams.Stream; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
		VAR i: LONGINT;
	BEGIN
		WITH S: ReaderStream DO
			i := 0;
			WHILE (i < n) & ~S.R.eot DO
				x[i] := S.ch; INC(S.pos); INC(i); Texts.Read(S.R, S.ch)
			END;
			S.eos := S.R.eot; S.res := n-i
		END
	END ReadTextBytes;

	PROCEDURE *ReaderAvailable(S: Streams.Stream): LONGINT;
	BEGIN
		WITH S: ReaderStream DO
			RETURN S.T.len-S.pos
		END
	END ReaderAvailable;

	PROCEDURE *ReaderState(S: Streams.Stream): INTEGER;
	BEGIN
		WITH S: ReaderStream DO
			IF S.T # NIL THEN
				RETURN Streams.in
			ELSE
				RETURN Streams.closed
			END
		END
	END ReaderState;

	PROCEDURE *CloseReader(S: Streams.Stream);
	BEGIN
		WITH S: ReaderStream DO
			S.T := NIL; S.eos := TRUE; S.pos := MAX(LONGINT)
		END
	END CloseReader;

(** Opens a read-only stream on text T starting at position pos. *)
	PROCEDURE OpenReader*(T: Texts.Text; pos: LONGINT): Streams.Stream;
		VAR S: ReaderStream;
	BEGIN
		NEW(S); S.mode := Streams.oberon; S.T := T; S.pos := pos; S.buffer := FALSE;
		Texts.OpenReader(S.R, S.T, S.pos); Texts.Read(S.R, S.ch); S.eos := S.R.eot; S.res := 0;
		S.ReadBytes := ReadTextBytes;
		S.WriteBytes := Streams.NULL.WriteBytes;
		S.Available := ReaderAvailable;
		S.State := ReaderState;
		S.Flush := Streams.NULL.Flush;
		S.Close := CloseReader;
		RETURN S
	END OpenReader;

	PROCEDURE *WriteTextBytes(S: Streams.Stream; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
		VAR i: LONGINT;
	BEGIN
		WITH S: WriterStream DO
			FOR i := 0 TO n-1 DO
				Texts.Write(S.W, SYSTEM.VAL(CHAR, x[i]))
			END;
			S.res := 0
		END
	END WriteTextBytes;

	PROCEDURE *WriterState(S: Streams.Stream): INTEGER;
	BEGIN
		WITH S: WriterStream DO
			IF S.T # NIL THEN
				RETURN Streams.out
			ELSE
				RETURN Streams.closed
			END
		END
	END WriterState;

	PROCEDURE *FlushWriter(S: Streams.Stream);
	BEGIN
		WITH S: WriterStream DO
			Texts.Append(S.T, S.W.buf)
		END
	END FlushWriter;

	PROCEDURE *CloseWriter(S: Streams.Stream);
	BEGIN
		WITH S: WriterStream DO
			S.Flush(S); S.T := NIL; S.eos := TRUE
		END
	END CloseWriter;

(** Opens a write-only stream: Flush will append the text written to Log. *)
	PROCEDURE OpenWriter*(Log: Texts.Text): Streams.Stream;
		VAR S: WriterStream;
	BEGIN
		NEW(S); S.mode := Streams.oberon; S.T := Log; S.res := 0;
		Texts.OpenWriter(S.W); S.eos := FALSE; S.buffer := FALSE;
		S.ReadBytes := Streams.NULL.ReadBytes;
		S.WriteBytes := WriteTextBytes;
		S.Available := Streams.NULL.Available;
		S.State := WriterState;
		S.Flush := FlushWriter;
		S.Close := CloseWriter;
		RETURN S
	END OpenWriter;

END TextStreams.

