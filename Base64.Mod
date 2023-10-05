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

MODULE Base64;	(** portable *) (* ejz,  *)
(** Base 64 encodeing according to RFC1421 *)
	IMPORT Files, Fonts, Texts, Oberon;

	VAR
		encTable: ARRAY 64 OF CHAR;
		decTable: ARRAY 128 OF INTEGER;
		W: Texts.Writer;

	PROCEDURE DecodeText*(T: Texts.Text; beg: LONGINT; F: Files.File): BOOLEAN;
		VAR
			R: Texts.Reader;
			codes: ARRAY 4 OF INTEGER;
			Ri: Files.Rider;
			i: INTEGER;
			ch: CHAR;
			ok, end: BOOLEAN;
	BEGIN
		Files.Set(Ri, F, 0);
		ok := TRUE; end := FALSE;
		Texts.OpenReader(R, T, beg);
		Texts.Read(R, ch);
		REPEAT
			i := 0;
			WHILE ~R.eot & ok & (i < 4) & (R.lib IS Fonts.Font) DO
				WHILE ~R.eot & (ch <= " ") & (R.lib IS Fonts.Font) DO
					Texts.Read(R, ch)
				END;
				codes[i] := decTable[ORD(ch)];
				ok := codes[i] >= 0; INC(i);
				IF ok THEN
					Texts.Read(R, ch)
				END
			END;
			IF i > 0 THEN
				IF ok THEN
					Files.Write(Ri, CHR(ASH(codes[0], 2)+ASH(codes[1], -4)));
					Files.Write(Ri, CHR(ASH(codes[1], 4)+ASH(codes[2], -2)));
					Files.Write(Ri, CHR(ASH(codes[2], 6)+codes[3]))
				ELSIF ch = "=" THEN
					ok := TRUE; end := TRUE; DEC(i);
					IF i = 2 THEN
						Files.Write(Ri, CHR(ASH(codes[0], 2)+ASH(codes[1], -4)))
					ELSIF i = 3 THEN
						Files.Write(Ri, CHR(ASH(codes[0], 2)+ASH(codes[1], -4)));
						Files.Write(Ri, CHR(ASH(codes[1], 4)+ASH(codes[2], -2)))
					ELSIF i # 0 THEN
						ok := FALSE
					END
				ELSIF i = 4 THEN
					ok := TRUE; end := TRUE;
					Files.Write(Ri, CHR(ASH(codes[0], 2)+ASH(codes[1], -4)));
					Files.Write(Ri, CHR(ASH(codes[1], 4)+ASH(codes[2], -2)));
					Files.Write(Ri, CHR(ASH(codes[2], 6)+codes[3]))
				ELSIF i = 1 THEN
					ok := TRUE; end := TRUE
				END
			ELSE
				end := TRUE
			END
		UNTIL R.eot OR end;
		RETURN ok
	END DecodeText;

	PROCEDURE Decode*;
		VAR
			S: Texts.Scanner;
			F: Files.File;
			T: Texts.Text;
			beg, end, time: LONGINT;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF S.class IN {Texts.Name, Texts.String} THEN
			Texts.WriteString(W, S.s);
			F := Files.New(S.s);
			Texts.Scan(S);
			IF (S.class = Texts.Char) & ((S.c = "@") OR (S.c = "^")) THEN
				T := NIL;
				time := -1;
				Oberon.GetSelection(T, beg, end, time);
				IF T = NIL THEN
					RETURN
				END
			ELSIF S.class IN {Texts.Name, Texts.String} THEN
				NEW(T);
				Texts.Open(T, S.s);
				beg := 0
			ELSE
				beg := Texts.Pos(S);
				T := Oberon.Par.text
			END;
			IF DecodeText(T, beg, F) THEN
				Files.Register(F);
				Texts.WriteString(W, " done")
			ELSE
				Texts.WriteString(W, " failed")
			END;
			Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END
	END Decode;

	PROCEDURE EncodeFile*(F: Files.File; T: Texts.Text);
		VAR
			R: Files.Rider;
			i, j, c, c0, c1, c2, l: LONGINT;
			chars: ARRAY 3 OF CHAR;
		PROCEDURE OutCode();
		BEGIN
			IF l > 80 THEN
				Texts.WriteLn(W); l := 0
			END;
			c0 :=ORD(chars[0]);
			c := ASH(c0, -2);
			Texts.Write(W, encTable[c]); c0 := c0-ASH(c, 2);
			c1 := ORD(chars[1]);
			c := ASH(c0, 4)+ASH(c1, -4);
			Texts.Write(W, encTable[c]); c1 := c1 MOD ASH(1, 4);
			c2 := ORD(chars[2]);
			c := ASH(c1, 2)+ASH(c2, -6);
			Texts.Write(W, encTable[c]); c2 := c2 MOD ASH(1, 6);
			Texts.Write(W, encTable[c2]);
			INC(l, 4)
		END OutCode;
	BEGIN
		l := 0;
		Files.Set(R, F, 0); Files.Read(R, chars[0]); i := 1;
		WHILE ~R.eof DO
			IF i >= 3 THEN
				OutCode(); i := 0
			END;
			Files.Read(R, chars[i]); INC(i)
		END;
		DEC(i);
		IF i > 0 THEN
			j := i;
			WHILE i < 3 DO
				chars[i] := 0X; INC(i)
			END;
			OutCode();
			Texts.Append(T, W.buf);
			IF j < 3 THEN
				j := 3-j;
				Texts.Delete(T, T.len-j, T.len);
				FOR i := 1 TO j DO
					Texts.Write(W, "=")
				END
			END
		END;
		Texts.Append(T, W.buf)
	END EncodeFile;

	PROCEDURE Encode*;
		VAR
			S: Texts.Scanner;
			F: Files.File;
			T: Texts.Text;
	BEGIN
		NEW(T); Texts.Open(T, "");
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF S.class IN {Texts.Name, Texts.String} THEN
			F := Files.Old(S.s);
			IF F # NIL THEN
				EncodeFile(F, T);
				Oberon.OpenText("Encode", T, 100, 100)
			END
		END
	END Encode;

	PROCEDURE InitTables();
		VAR i, max: INTEGER;
	BEGIN
		max := ORD("Z")-ORD("A");
		FOR i := 0 TO max DO
			encTable[i] := CHR(i+ORD("A"))
		END;
		INC(max);
		FOR i := max TO max+ORD("z")-ORD("a") DO
			encTable[i] := CHR(i-max+ORD("a"))
		END;
		max := max+ORD("z")-ORD("a")+1;
		FOR i := max TO max+ORD("9")-ORD("0") DO
			encTable[i] := CHR(i-max+ORD("0"))
		END;
		encTable[62] := "+";
		encTable[63] := "/";
		FOR i := 0 TO 127 DO
			decTable[i] := -1
		END;
		FOR i := 0 TO 63 DO
			decTable[ORD(encTable[i])] := i
		END
	END InitTables;

BEGIN
	InitTables();
	Texts.OpenWriter(W)
END Base64.
