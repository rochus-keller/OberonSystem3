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

MODULE BinHex;	(** portable *) (* ejz,  *)
(** BinHex decodeing, sit not yet supported *)

	IMPORT Files, Texts, Oberon;

	VAR
		encTable: ARRAY 64 OF CHAR;
		decTable: ARRAY 128 OF INTEGER;
		W: Texts.Writer;

	PROCEDURE DecodeText*(T: Texts.Text; beg: LONGINT; F: Files.File): BOOLEAN;
		VAR
			Rt: Texts.Reader;
			Rf, R: Files.Rider;
			S: Texts.Scanner;
			codes: ARRAY 4 OF INTEGER;
			dlen: LONGINT;
			i: INTEGER;
			ok, end: BOOLEAN;
			ch, last: CHAR;
	BEGIN
(* search BinHex *)
		Texts.OpenScanner(S, T, beg); Texts.Scan(S);
		WHILE ~S.eot & ~((S.class = Texts.Name) & (S.s = "BinHex")) DO
			Texts.Scan(S)
		END;
		IF S.eot THEN
			RETURN FALSE
		END;
		Texts.OpenReader(Rt, T, Texts.Pos(S)); Texts.Read(Rt, ch);
		WHILE ~Rt.eot & (ch # ":") DO
			Texts.Read(Rt, ch)
		END;
(* decode ascii to bin *)
		Texts.Read(Rt, ch);
		ok := TRUE; end := FALSE;
		Files.Set(Rf, Files.New(""), 0);
		REPEAT
			i := 0;
			WHILE ~Rt.eot & ok & (i < 4) DO
				WHILE ~Rt.eot & (ch <= " ")  DO
					Texts.Read(Rt, ch)
				END;
				codes[i] := decTable[ORD(ch)];
				ok := codes[i] >= 0; INC(i);
				IF ok THEN
					Texts.Read(Rt, ch)
				END
			END;
			IF i > 0 THEN
				IF ok THEN
					Files.Write(Rf, CHR(ASH(codes[0], 2)+ASH(codes[1], -4)));
					Files.Write(Rf, CHR(ASH(codes[1], 4)+ASH(codes[2], -2)));
					Files.Write(Rf, CHR(ASH(codes[2], 6)+codes[3]))
				ELSIF ch = ":" THEN
					ok := TRUE; end := TRUE; DEC(i);
					IF i = 2 THEN
						Files.Write(Rf, CHR(ASH(codes[0], 2)+ASH(codes[1], -4)))
					ELSIF i = 3 THEN
						Files.Write(Rf, CHR(ASH(codes[0], 2)+ASH(codes[1], -4)));
						Files.Write(Rf, CHR(ASH(codes[1], 4)+ASH(codes[2], -2)))
					ELSIF i # 0 THEN
						ok := FALSE
					END
				END
			ELSE
				end := TRUE; ok := ch = ":"
			END
		UNTIL Rt.eot OR end;
		IF ~ok OR ~end THEN
			RETURN FALSE
		END;
(* decode rle *)
		Files.Set(R, Files.New(""), 0);
		Files.Set(Rf, Files.Base(Rf), 0);
		last := 0X; Files.Read(Rf, ch);
		WHILE ~Rf.eof DO
			IF ch = CHR(090H) THEN
				Files.Read(Rf, ch);
				IF ch = 0X THEN
					last := CHR(090H); Files.Write(R, CHR(0090H))
				ELSE
					i := ORD(ch)-1;
					WHILE i > 0 DO
						Files.Write(R, last); DEC(i)
					END
				END
			ELSE
				last := ch; Files.Write(R, ch);
			END;
			Files.Read(Rf, ch)
		END;
(* decode hqx *)
		Files.Set(Rf, Files.Base(R), 0);
		Files.Read(Rf, ch); last := ch;
		Files.Set(Rf, Files.Base(R), 1+ORD(ch)+1+4+4+2);
		Files.Read(Rf, ch); dlen := ORD(ch);
		Files.Read(Rf, ch); dlen := 256*dlen+ORD(ch);
		Files.Read(Rf, ch); dlen := 256*dlen+ORD(ch);
		Files.Read(Rf, ch); dlen := 256*dlen+ORD(ch);
		Files.Set(Rf, Files.Base(R), 1+ORD(last)+1+4+4+2+4+4+2);
		Texts.Write(W, " "); Texts.WriteInt(W, dlen, 0);
		Texts.WriteLn(W);
		Files.Set(R, F, 0); Files.Read(Rf, ch);
		WHILE ~Rf.eof & (dlen > 0) DO
			Files.Write(R, ch); Files.Read(Rf, ch); DEC(dlen)
		END;
		RETURN dlen = 0
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
			Texts.WriteString(W, S.s); F := Files.New(S.s);
			Texts.Scan(S);
			IF (S.class = Texts.Char) & ((S.c = "@") OR (S.c = "^")) THEN
				T := NIL; time := -1;
				Oberon.GetSelection(T, beg, end, time);
				IF T = NIL THEN
					RETURN
				END
			ELSIF S.class IN {Texts.Name, Texts.String} THEN
				NEW(T); Texts.Open(T, S.s);
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
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	END Decode;

	PROCEDURE InitTables();
		VAR i: INTEGER;
	BEGIN
		FOR i := 0 TO 127 DO
			decTable[i] := -1
		END;
		FOR i := 0 TO 63 DO
			encTable[i] := 0X
		END;
		FOR i := 0 TO 12 DO (* ! .. - *)
			encTable[i] := CHR(i+33)
		END;
		FOR i := 13 TO 19 DO (* 0 .. 6 *)
			encTable[i] := CHR(i-13+48)
		END;
		FOR i := 20 TO 21 DO (* 8 .. 9 *)
			encTable[i] := CHR(i-20+56)
		END;
		FOR i := 22 TO 36 DO (* @ .. N *)
			encTable[i] := CHR(i-22+64)
		END;
		FOR i := 37 TO 43 DO (* P .. V *)
			encTable[i] := CHR(i-37+80)
		END;
		FOR i := 44 TO 47 DO (* X .. [ *)
			encTable[i] := CHR(i-44+88)
		END;
		FOR i := 48 TO 54 DO (* ' .. f *)
			encTable[i] := CHR(i-48+96)
		END;
		FOR i := 55 TO 60 DO (* h .. m *)
			encTable[i] := CHR(i-55+104)
		END;
		FOR i := 61 TO 63 DO (* p  .. r *)
			encTable[i] := CHR(i-61+112)
		END;
		FOR i := 0 TO 63 DO
			decTable[ORD(encTable[i])] := i
		END
	END InitTables;

BEGIN
	InitTables();
	Texts.OpenWriter(W)
END BinHex.

System.Free BinHex ~
