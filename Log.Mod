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

MODULE Log;	(** portable *) (** ww 7-Jul-90 / mh 26.10.93 **)

	IMPORT Texts, Oberon, MenuViewers, TextFrames, Viewers, Fonts, Objects;

	CONST
		Menu = "System.Close System.Grow  Log.Pin  Log.Clear  Edit.Locate ";
		PinInterval = 500; (*ms*)
		
	delete = 2; insert = 1; change = 0;

	VAR task: Oberon.Task;	w: Texts.Writer;	pin, lastLen: LONGINT;

	(** viewer stuff **)
	
PROCEDURE ConvertMsg(VAR M: Texts.UpdateMsg; VAR id: INTEGER; VAR beg, end: LONGINT);
BEGIN
	IF M.len = 0 THEN id := delete; beg := M.beg; end := M.end
	ELSIF M.end = M.beg THEN id := insert; beg := M.beg; end := M.beg + M.len
	ELSIF M.end - M.beg = M.len THEN id := change; beg := M.beg; end := M.end
	ELSE HALT(99)
	END
END ConvertMsg;


	PROCEDURE Handler (F: Objects.Object; VAR M: Objects.ObjMsg);	(* scrolling *)
		VAR r: Texts.Reader; pos, oldpos, last: LONGINT; ch: CHAR; id: INTEGER; beg, end: LONGINT;
	BEGIN
		WITH F: TextFrames.Frame DO
			TextFrames.Handle(F, M);
			IF M IS Texts.UpdateMsg THEN
				WITH M : Texts.UpdateMsg DO
					ConvertMsg(M, id, beg, end);
					IF (id = insert) & (end = Oberon.Log.len) THEN
						last := TextFrames.Pos(F, MAX(INTEGER), F.Y);
						IF last < Oberon.Log.len-1 THEN
							Oberon.RemoveMarks(F.X, F.Y, F.W, F.H);
							TextFrames.RemoveSelection(F); TextFrames.RemoveCaret(F);
							REPEAT oldpos := pos;
								IF last + 2 <  beg THEN pos :=  beg; TextFrames.Show(F, pos)
								ELSE
									Texts.OpenReader(r, Oberon.Log, F.org);
									REPEAT Texts.Read(r, ch) UNTIL r.eot OR (ch = 0DX);
									pos := Texts.Pos(r); TextFrames.Show(F, pos)
								END;
								last := TextFrames.Pos(F, MAX(INTEGER), F.Y)
							UNTIL (last >= Oberon.Log.len-1) OR (oldpos = pos);
						END
					END
				END
			END
		END
	END Handler;
	
	PROCEDURE Open*;
		VAR v: Viewers.Viewer; f: TextFrames.Frame; x, y: INTEGER; beg: LONGINT;
	BEGIN
		IF Oberon.Log.len > pin THEN beg := pin ELSE beg := 0 END;
		Oberon.AllocateSystemViewer(Oberon.Par.vwr.X, x, y);
		f := TextFrames.NewText(Oberon.Log, beg); f.handle := Handler;
		v := MenuViewers.New(TextFrames.NewMenu("System.Log", Menu), f, TextFrames.menuH, x, y);
	END Open;
	
	PROCEDURE Pin*;	(** puts output of last command on top of the viewer (should be called from viewers menu) **)
		VAR frame: TextFrames.Frame;
	BEGIN
		frame := Oberon.Par.vwr.dsc.next(TextFrames.Frame);
		IF (Oberon.Log.len > pin) & (frame.text = Oberon.Log) THEN
			Oberon.RemoveMarks(frame.X, frame.Y, frame.W, frame.H);
			TextFrames.RemoveSelection(frame); TextFrames.RemoveCaret(frame);
			TextFrames.Show(frame, pin)
		END
	END Pin;

	PROCEDURE Clear*;
	BEGIN Texts.Delete(Oberon.Log, 0,Oberon.Log^.len); pin := 0; lastLen := 0
	END Clear;

	PROCEDURE SetPin(me: Oberon.Task);
		VAR pos: LONGINT;
	BEGIN pos := Oberon.Log.len;
		IF pos # lastLen THEN pin := lastLen; lastLen := pos END;
		INC(me.time, PinInterval);
	END SetPin;

	(** output stuff **)

	(** The procedures behave as the corresponding ones in module Texts **)
	PROCEDURE Int*(x: LONGINT);
	BEGIN Texts.Write(w, " "); Texts.WriteInt(w, x, 0); Texts.Append(Oberon.Log, w.buf)
	END Int;

	PROCEDURE Hex*(x: LONGINT);
	BEGIN Texts.WriteHex(w, x); Texts.Append(Oberon.Log, w.buf)
	END Hex;

	PROCEDURE Real*(x: LONGREAL);
	BEGIN Texts.WriteLongReal(w, x, 24); Texts.Append(Oberon.Log, w.buf)
	END Real;

	PROCEDURE Ch*(ch: CHAR);
	BEGIN Texts.Write(w, ch); Texts.Append(Oberon.Log, w.buf)
	END Ch;

	PROCEDURE Str*(s: ARRAY OF CHAR);
	BEGIN Texts.WriteString(w, s); Texts.Append(Oberon.Log, w.buf)
	END Str;

	PROCEDURE Bool*(b: BOOLEAN);
	BEGIN
		IF b THEN Texts.WriteString(w, " TRUE") ELSE Texts.WriteString(w, " FALSE") END;
		Texts.Append(Oberon.Log, w.buf)
	END Bool;

	PROCEDURE Set*(s: SET);
		VAR i: INTEGER;
	BEGIN
		Texts.WriteString(w, " {"); i := 0;
		WHILE s # {} DO
			IF i IN s THEN
				Texts.WriteInt(w, i, 0); EXCL(s, i);
				IF (i + 2 <= MAX(SET)) & (i+1 IN s) & (i+2 IN s) THEN
					Texts.WriteString(w, "..");
					s := s - {i+1, i+2}; INC(i, 3);
					WHILE (i <= MAX(SET)) & (i IN s) DO EXCL(s, i); INC(i) END;
					Texts.WriteInt(w, i-1, 0)
				END;
				IF s # {} THEN Texts.Write(w, ",") END
			END;
			INC(i)
		END;
		Texts.Write(w, "}"); Texts.Append(Oberon.Log, w.buf)
	END Set;

	PROCEDURE Date*(t, d: LONGINT);
	BEGIN Texts.WriteDate(w, t, d); Texts.Append(Oberon.Log, w.buf)
	END Date;

	PROCEDURE Ln*;
	BEGIN Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf)
	END Ln;

	PROCEDURE DumpRange*(VAR a: ARRAY OF CHAR; beg, len: LONGINT);
		VAR xFont: Fonts.Font;	l, h: INTEGER;	i, j, end: LONGINT;
	BEGIN
		end := beg + len;
		IF end > LEN(a) THEN end := LEN(a) END;
		Texts.WriteLn(w);
		xFont := Fonts.This("Syntax10x.Scn.Fnt"); IF xFont # NIL THEN Texts.SetFont (w, xFont) END;
		i := beg;
		WHILE i < end DO
			h := ORD(a[i]) DIV 16; l := ORD(a[i]) MOD 16;
			IF h > 9 THEN Texts.Write(w, CHR(h - 10 + ORD("A"))) ELSE Texts.Write(w, CHR(h + ORD("0"))) END;
			IF l > 9 THEN Texts.Write(w, CHR(l - 10 + ORD("A"))) ELSE Texts.Write(w, CHR(l + ORD("0"))) END;
			Texts.WriteString(w, "      ");
			INC(i);
			IF i MOD 4 = 0 THEN
				j := i - 4;
				WHILE j < i DO
					IF (ORD(a[j]) < ORD(" ")) OR (ORD(a[j]) > 126) THEN
						Texts.Write(w, "-")
					ELSE Texts.Write(w, a[j]) END;
					INC(j)
				END;
				Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf)
			END
		END;
		IF i MOD 4 # 0 THEN
			REPEAT Texts.WriteString(w, "        "); INC(i) UNTIL i MOD 4 = 0;
			j := i - 4;
			WHILE j < end DO
				IF (ORD(a[j]) < ORD(" ")) OR (ORD(a[j]) > 126) THEN
					Texts.Write(w, "-")
				ELSE Texts.Write(w, a[j]) END;
				INC(j)
			END;
		END;
		Texts.WriteLn(w); Texts.Append(Oberon.Log, w.buf)
	END DumpRange;

	PROCEDURE Dump*(VAR a: ARRAY OF CHAR);
	BEGIN DumpRange(a, 0, LEN(a))
	END Dump;

BEGIN
	Texts.OpenWriter(w);
	NEW(task); task.handle := SetPin; task.safe:= FALSE; pin := 0; lastLen := 0;
	Oberon.Install(task)
END Log.
