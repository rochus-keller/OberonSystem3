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

MODULE Rot13;	(** portable *)	(** eos 24-Nov-95 **)

	IMPORT
		Fonts, Texts, Oberon;

	VAR
		W: Texts.Writer;

	(** decode rot13 encrypted selection **)
	PROCEDURE Decode*;
		VAR text: Texts.Text; beg, end, time: LONGINT; r: Texts.Reader; ch: CHAR;
	BEGIN
		Oberon.GetSelection(text, beg, end, time);
		IF time >= 0 THEN
			Texts.OpenReader(r, text, beg);
			WHILE Texts.Pos(r) < end DO
				Texts.Read(r, ch);
				IF r.lib IS Fonts.Font THEN
					IF CAP(ch) < "A" THEN
						Texts.Write(W, ch)
					ELSIF CAP(ch) < CHR(ORD("A") + 13) THEN
						Texts.Write(W, CHR(ORD(ch) + 13))
					ELSIF CAP(ch) <= "Z" THEN
						Texts.Write(W, CHR(ORD(ch) - 13))
					ELSE
						Texts.Write(W, ch)
					END
				ELSE
					Texts.Delete(text, beg, Texts.Pos(r) - 1);
					Texts.Insert(text, beg, W.buf);
					beg := Texts.Pos(r)
				END
			END;
			Texts.Delete(text, beg, end);
			Texts.Insert(text, beg, W.buf)
		END
	END Decode;

BEGIN
	Texts.OpenWriter(W)
END Rot13.
