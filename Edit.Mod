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

MODULE Edit;	(** portable *) (*JG 4.4.95 / NW 24.1.91*)

	IMPORT Files, Objects, Display, Viewers, MenuViewers, Printer, Fonts, Texts, TextFrames, Oberon;

	CONST
		CR = 0DX; maxlen = 32;
		StandardMenu = "System.Close System.Copy System.Grow Edit.Search Edit.Store";

	VAR
		W: Texts.Writer;
		time: LONGINT;
		M: INTEGER;
		pat: ARRAY maxlen OF CHAR;
		d: ARRAY 256 OF INTEGER;
        textX, pagenoX, headerY, topY, botY: INTEGER;

	PROCEDURE Max (i, j: LONGINT): LONGINT;
	BEGIN IF i >= j THEN RETURN i ELSE RETURN j END
	END Max;

	PROCEDURE Open*;
		VAR par: Oberon.ParList;
		T: Texts.Text;
		S: Texts.Scanner;
		V: Viewers.Viewer;
		X, Y: INTEGER;
		beg, end, time: LONGINT;
	BEGIN
		par := Oberon.Par;
		Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") OR (S.line # 0) THEN
			Oberon.GetSelection(T, beg, end, time);
			IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
		END;
		IF S.class # Texts.Name THEN S.s := "" END;
		Oberon.AllocateUserViewer(par.vwr.X, X, Y);
		V := MenuViewers.New(
			TextFrames.NewMenu(S.s, StandardMenu),
			TextFrames.NewText(TextFrames.Text(S.s), 0),
			TextFrames.menuH,
			X, Y)
	END Open;

	PROCEDURE Show*;
		VAR par: Oberon.ParList;
			T, t: Texts.Text;
			R: Texts.Reader;
			S: Texts.Scanner;
			V: Viewers.Viewer;
			X, Y, n, i, j: INTEGER;
			pos, len, beg, end, time: LONGINT;
			buf: ARRAY 32 OF CHAR;
			name: ARRAY 35 OF CHAR;
			M: INTEGER;
			pat: ARRAY maxlen OF CHAR;
			d: ARRAY 256 OF INTEGER;

		PROCEDURE Forward (n: INTEGER);
			VAR m: INTEGER; j: INTEGER;
		BEGIN m := M - n;
			j := 0;
			WHILE j # m DO buf[j] := buf[n + j]; INC(j) END;
			WHILE j # M DO Texts.Read(R, buf[j]); INC(j) END
		END Forward;

    BEGIN
		par := Oberon.Par;
		Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") OR (S.line # 0) THEN
			Oberon.GetSelection(T, beg, end, time);
			IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
		END;
		IF S.class = Texts.Name THEN
			i := -1; j := 0;
			WHILE S.s[j] # 0X DO
				IF S.s[j] = "." THEN i := j END;
				name[j] := S.s[j]; j := j+1
			END;
			IF i < 0 THEN name[j] := "."; i := j END;
			name[i+1] := "M"; name[i+2] := "o"; name[i+3] := "d"; name[i+4] := 0X;
			t := TextFrames.Text(name);
			IF j > i THEN (*object name specified*)
				j := i+1; M := 0;
				WHILE (M # maxlen) & (S.s[j] # 0X) DO pat[M] := S.s[j]; j := j+1; M := M+1 END;
				j := 0;
				WHILE j # 256 DO d[j] := M; INC(j) END;
				j := 0;
				WHILE j # M - 1 DO d[ORD(pat[j])] := M - 1 - j; INC(j) END;
				pos := 0; len := t.len;
				Texts.OpenReader(R, t, pos);
				Forward(M); pos := pos + M;
				LOOP j := M;
					REPEAT DEC(j) UNTIL (j < 0) OR (buf[j] # pat[j]);
					IF (j < 0) OR (pos >= len) THEN EXIT END;
					n := d[ORD(buf[M-1])];
					Forward(n); pos := pos + n
				END
			ELSE pos := 0
			END;
			Oberon.AllocateUserViewer(par.vwr.X, X, Y);
			V := MenuViewers.New(
				TextFrames.NewMenu(name, StandardMenu),
				TextFrames.NewText(t, pos-200),
				TextFrames.menuH,
				X, Y)
		END
	END Show;

	PROCEDURE Store*;
		VAR par: Oberon.ParList;
			V: Viewers.Viewer;
			Text: TextFrames.Frame;
			T: Texts.Text;
			S: Texts.Scanner;
			f: Files.File;
			beg, end, time, len: LONGINT;

		PROCEDURE Backup (VAR name: ARRAY OF CHAR);
			VAR res, i: INTEGER; bak: ARRAY 32 OF CHAR;
		BEGIN i := 0;
			WHILE name[i] # 0X DO bak[i] := name[i]; INC(i) END;
			bak[i] := "."; bak[i+1] := "B"; bak[i+2] := "a"; bak[i+3] := "k"; bak[i+4] := 0X;
			Files.Rename(name, bak, res)
		END Backup;

	BEGIN
		Texts.WriteString(W, "Edit.Store ");
		par := Oberon.Par; 
		IF par.frame = par.vwr.dsc THEN
			V := par.vwr; Texts.OpenScanner(S, V.dsc(TextFrames.Frame).text, 0)
		ELSE V := Oberon.MarkedViewer(); Texts.OpenScanner(S, par.text, par.pos)
		END;
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			Oberon.GetSelection(T, beg, end, time);
			IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
		END;
		IF (S.class = Texts.Name) & (V.dsc # NIL) & (V.dsc.next IS TextFrames.Frame) THEN
			Text := V.dsc.next(TextFrames.Frame);
			TextFrames.Mark(Text, -1);
			Texts.WriteString(W, S.s); 
			f := Files.New(S.s);
			IF f = NIL THEN
				Texts.WriteString(W, " invalid name");
				Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf)
			ELSE
				Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf);
				Backup(S.s);
				Texts.Store(Text.text, f, 0, len);
				Files.Register(f)
			END;
			TextFrames.Mark(Text, 1)
		END
	END Store;        

	PROCEDURE CopyFont*;
		VAR R: Texts.Reader;
			T: Texts.Text;
			v: Viewers.Viewer;
			F: Display.Frame;
			beg, end: LONGINT;
			X, Y: INTEGER;
			ch: CHAR;
	BEGIN
		v := Oberon.MarkedViewer(); F := v.dsc;
		X := Oberon.Pointer.X; Y := Oberon.Pointer.Y;
		LOOP
			IF F = NIL THEN EXIT END;
			IF (X >= F.X) & (X < F.X + F.W) & (Y >= F.Y) & (Y < F.Y + F.H) THEN
				IF F IS TextFrames.Frame THEN
					WITH F: TextFrames.Frame DO
						Texts.OpenReader(R, F.text, TextFrames.Pos(F, X, Y));
						Texts.Read(R, ch);
						Oberon.GetSelection(T, beg, end, time);
						IF time >= 0 THEN Texts.ChangeLooks(T, beg, end, {0}, R.lib, 0, 0) END
					END
				END;
				EXIT
			END;
			F := F.next
		END
	END CopyFont;

	PROCEDURE ChangeFont*;
		VAR par: Oberon.ParList; S: Texts.Scanner; T: Texts.Text; beg, end: LONGINT;
	BEGIN
		Oberon.GetSelection(T, beg, end, time);
		IF time >= 0 THEN par := Oberon.Par;
			Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
			IF S.class = Texts.Name THEN
				Texts.ChangeLooks(T, beg, end, {0}, Fonts.This(S.s), 0, 0)
			END
		END
	END ChangeFont;

	PROCEDURE ChangeColor*;
		VAR par: Oberon.ParList;
			S: Texts.Scanner;
			T: Texts.Text;
			col: SHORTINT;
			beg, end, time: LONGINT;
	BEGIN par := Oberon.Par;
		Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
		IF S.class # Texts.Int THEN col := S.col ELSE col := SHORT(SHORT(S.i)) END;
		Oberon.GetSelection(T, beg, end, time);
		IF time >= 0 THEN Texts.ChangeLooks(T, beg, end, {1}, NIL, col, 0) END
	END ChangeColor;

	PROCEDURE Search*;
		VAR Text: TextFrames.Frame;
			V: Viewers.Viewer;
			R: Texts.Reader;
			T: Texts.Text;
			pos, beg, end, prevTime, len: LONGINT; n, i, j: INTEGER;
			buf: ARRAY 32 OF CHAR;

		PROCEDURE Forward (n: INTEGER);
			VAR m: INTEGER; j: INTEGER;
		BEGIN m := M - n;
			j := 0;
			WHILE j # m DO buf[j] := buf[n + j]; INC(j) END;
			WHILE j # M DO Texts.Read(R, buf[j]); INC(j) END
		END Forward;

	BEGIN
		V := Oberon.Par.vwr;
		IF Oberon.Par.frame # V.dsc THEN V := Oberon.MarkedViewer() END;
		IF (V.dsc # NIL) & (V.dsc.next IS TextFrames.Frame) THEN
			Text := V.dsc.next(TextFrames.Frame);
			TextFrames.Mark(Text, -1);
			prevTime := time; Oberon.GetSelection(T, beg, end, time);
			IF time > prevTime THEN
                Texts.OpenReader(R, T, beg);
				i := 0; pos := beg;
				REPEAT Texts.Read(R, pat[i]); INC(i); INC(pos)
				UNTIL (i = maxlen) OR (pos = end);
				M := i;
				j := 0;
				WHILE j # 256 DO d[j] := M; INC(j) END;
				j := 0;
				WHILE j # M - 1 DO d[ORD(pat[j])] := M - 1 - j; INC(j) END
			END;
			IF Text.car > 0 THEN pos := Text.carloc.pos ELSE pos := 0 END;
			len := Text.text.len;
			Texts.OpenReader(R, Text.text, pos);
			Forward(M); pos := pos + M;
			LOOP j := M;
				REPEAT DEC(j) UNTIL (j < 0) OR (buf[j] # pat[j]);
				IF (j < 0) OR (pos >= len) THEN EXIT END;
				n := d[ORD(buf[M-1])];
				Forward(n); pos := pos + n
			END;
			IF j < 0 THEN
				TextFrames.RemoveSelection(Text);
				TextFrames.RemoveCaret(Text);
				Oberon.RemoveMarks(Text.X, Text.Y, Text.W, Text.H);
				TextFrames.Show(Text, pos - 200);
				Oberon.Defocus;
				TextFrames.SetCaret(Text, pos)
			END;
			TextFrames.Mark(Text, 1)
		END
	END Search;

	PROCEDURE Locate*;
		VAR Text: TextFrames.Frame;
			T: Texts.Text; S: Texts.Scanner;
			V: Viewers.Viewer;
			beg, end, time: LONGINT;
	BEGIN
		V := Oberon.MarkedViewer();
		IF (V.dsc # NIL) & (V.dsc.next IS TextFrames.Frame) THEN
			Text := V.dsc.next(TextFrames.Frame);
			Oberon.GetSelection(T, beg, end, time);
			IF time >= 0 THEN
				Texts.OpenScanner(S, T, beg);
				REPEAT Texts.Scan(S) UNTIL S.eot OR (S.class >= Texts.Int); (*skip names*)
				IF S.class = Texts.Int THEN
					TextFrames.RemoveSelection(Text);
					TextFrames.RemoveCaret(Text);
					Oberon.RemoveMarks(Text.X, Text.Y, Text.W, Text.H);
					TextFrames.Show(Text, Max(0, S.i - 200));
					Oberon.Defocus;
					TextFrames.SetCaret(Text, S.i)
				END
			END
		END
	END Locate;

    PROCEDURE AddPrefix*;
      VAR  V: Viewers.Viewer;
        S: Texts.Scanner; R: Texts.Reader; T: TextFrames.Frame;
        pos, beg, end, time: LONGINT; ch: CHAR;
    BEGIN
      Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
      IF (S.class = Texts.Char) & (S.c = "^") THEN
        Oberon.GetSelection(T.text, beg, end, time);
        IF time >= 0 THEN Texts.OpenScanner(S, T.text, beg); Texts.Scan(S) END
      END;
      IF (S.class = Texts.Name) OR (S.class = Texts.String) THEN
        V := Oberon.MarkedViewer();
        IF (V.dsc # NIL) & (V.dsc.next IS TextFrames.Frame) THEN
          T := V.dsc.next(TextFrames.Frame);
          IF T.sel > 0 THEN
            pos := T.selbeg.org; end := T.selend.pos;
            REPEAT
              Texts.WriteString(W, S.s); Texts.Insert(T.text, pos, W.buf);
              Texts.OpenReader(R, T.text, pos); Texts.Read(R, ch); INC(pos);
              WHILE (pos # end) & (ch # CR) DO Texts.Read(R, ch); INC(pos) END
            UNTIL pos = end
          END
        END
      END
    END AddPrefix;

    PROCEDURE RemovePrefix*;
      VAR  V: Viewers.Viewer;
        S: Texts.Scanner; R: Texts.Reader; T: TextFrames.Frame;
        pos, beg, end, time: LONGINT; i: INTEGER; ch: CHAR;
    BEGIN
      Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
      IF (S.class = Texts.Char) & (S.c = "^") THEN
        Oberon.GetSelection(T.text, beg, end, time);
        IF time >= 0 THEN Texts.OpenScanner(S, T.text, beg); Texts.Scan(S) END
      END;
      IF (S.class = Texts.Name) OR (S.class = Texts.String) THEN
        V := Oberon.MarkedViewer();
        IF (V.dsc # NIL) & (V.dsc.next IS TextFrames.Frame) THEN
          T := V.dsc.next(TextFrames.Frame);
          IF T.sel > 0 THEN
            pos := T.selbeg.org; end := T.selend.pos;
            REPEAT
              Texts.OpenReader(R, T.text, pos); Texts.Read(R, ch); i := 0;
              WHILE ~R.eot & (S.s[i] = ch) DO Texts.Read(R, ch); INC(i) END;
              Texts.Delete(T.text, pos, pos + i);
              Texts.OpenReader(R, T.text, pos); Texts.Read(R, ch); INC(pos);
              WHILE ~R.eot & (ch # CR) DO Texts.Read(R, ch); INC(pos) END
            UNTIL R.eot
          END
        END
      END
    END RemovePrefix;

	PROCEDURE Recall*;
		VAR M: Oberon.RecallMsg;
	BEGIN M.F := NIL; Display.Broadcast(M)
	END Recall;

	PROCEDURE Print*;

		VAR
			par: Oberon.ParList;
			Menu, Text: TextFrames.Frame;
			R: Texts.Reader;
			S: Texts.Scanner;
			T: Texts.Text;
			source: Texts.Text;
			lib: Objects.Library;
			V: Viewers.Viewer;
			ch: CHAR;
			pageno: SHORTINT; listing: BOOLEAN;
			nofcopies, lsp, Y: INTEGER;
			beg, end, time: LONGINT;
			server, options: ARRAY 32 OF CHAR;
			font: Fonts.Font;

		PROCEDURE SendHeader;
			VAR pno: ARRAY 4 OF CHAR;
		BEGIN Printer.String(textX, headerY, S.s, Fonts.Default);
			IF pageno DIV 10 = 0 THEN pno[0] := " " ELSE pno[0] := CHR(pageno DIV 10 + 30H) END ;
			pno[1] := CHR(pageno MOD 10 + 30H); pno[2] := 0X;
			Printer.String(pagenoX, headerY, pno, Fonts.Default)
		END SendHeader;

		PROCEDURE PrintUnit (source: Texts.Text; pos: LONGINT);
			CONST BufSize = 200;
			VAR i: INTEGER; new: BOOLEAN;
				buf: ARRAY BufSize OF CHAR;
		BEGIN Texts.WriteString(W, S.s);
			IF source.len # 0 THEN
				Texts.WriteString(W, " printing"); Texts.WriteInt(W, nofcopies, 3);
				Texts.Append(Oberon.Log, W.buf);
				(*lsp := Fonts.Default.height * 7 DIV 2; *)
				font := Printer.GetMetric(Fonts.Default);
				lsp := font.height*110 DIV 100;
				pageno := 0;
				SendHeader; Y := topY;
				Texts.OpenReader(R, source, pos);
				IF ~listing THEN
					REPEAT Texts.Read(R, ch);
						new := TRUE; lib := R.lib;
						WHILE ~R.eot & (ch # CR) DO
							i := 0;
							REPEAT
								IF i < BufSize-4 THEN
									IF ch = 9X THEN (* TABS expand to four spaces *)
										ch := " "; buf[i] := ch; INC(i); buf[i] := ch; INC(i); buf[i] := ch; INC(i);
									END;
									buf[i] := ch; INC(i)
								END;
								Texts.Read(R, ch)
							UNTIL R.eot OR (ch = CR) OR (R.lib # lib);
							buf[i] := 0X;
							IF new THEN Printer.String(textX, Y, buf, lib(Fonts.Font))
								ELSE Printer.ContString(buf, lib(Fonts.Font))
							END;
							new := FALSE; lib := R.lib
						END;
						Y := Y - lsp;
						IF Y < botY THEN
							Printer.Page(nofcopies); INC(pageno); SendHeader; Y := topY
						END
					UNTIL R.eot
				ELSE lsp := 32;
					REPEAT Texts.Read(R, ch);
						WHILE ~R.eot & (ch # CR) DO
							i := 0;
							REPEAT
								IF ch = 9X THEN (* TABS expand to four spaces *)
									ch := " "; buf[i] := ch; INC(i); buf[i] := ch; INC(i); buf[i] := ch; INC(i);
								END;
								buf[i] := ch; INC(i);
								Texts.Read(R, ch)
							UNTIL R.eot OR (ch = CR);
							buf[i] := 0X;
							Printer.String(textX, Y, buf, Fonts.Default)
						END;
						Y := Y - lsp;
						IF Y < botY THEN
							Printer.Page(nofcopies); INC(pageno); SendHeader; Y := topY
						END
					UNTIL R.eot
				END;
				IF Y < topY THEN Printer.Page(nofcopies) END
			ELSE Texts.WriteString(W, " not found")
			END;
			Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END PrintUnit;

		PROCEDURE Option;
			VAR ch: CHAR;
		BEGIN nofcopies := 1;
			IF S.nextCh = Oberon.OptionChar THEN
				Texts.Read(S, ch);
				IF (ch >= "0") & (ch <= "9") THEN nofcopies := ORD(ch) - 30H END ;
				WHILE ch > " " DO Texts.Read(S, ch) END;
				S.nextCh := ch
			END
		END Option;

	BEGIN par := Oberon.Par;
		Texts.WriteString(W, "Edit.Print"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
		Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
		IF S.class IN {Texts.Name,Texts.String} THEN
			COPY(S.s, server);
			IF S.nextCh = Oberon.OptionChar THEN
				Texts.Scan(S);  Texts.Scan(S);
				IF S.class IN {Texts.Name,Texts.String} THEN COPY(S.s, options)
				ELSE options := "" 
				END
			ELSE options := ""
			END;
			Printer.Open(server, options);
			IF Printer.res = 0 THEN
                textX := Printer.Width DIV 10;
                pagenoX := Printer.Width DIV 10 * 9;
                headerY := Printer.Height DIV 20 * 19;
                topY := Printer.Height DIV 10 * 9;
                botY := Printer.Height DIV 20;
                Texts.Scan(S);
				IF (S.class = Texts.Char) & (S.c = "%") THEN
					listing := TRUE; Printer.UseListFont(Fonts.Default.name); Texts.Scan(S)
				ELSE listing := FALSE
				END;
				IF (S.class = Texts.Char) & (S.c = "*") THEN
					Option; V := Oberon.MarkedViewer();
					IF (V.dsc IS TextFrames.Frame) & (V.dsc.next IS TextFrames.Frame) THEN
 						Menu := V.dsc(TextFrames.Frame); Text := V.dsc.next(TextFrames.Frame);
						Texts.OpenScanner(S, Menu.text, 0); Texts.Scan(S);
						TextFrames.Mark(Text, -1); PrintUnit(Text.text, 0); TextFrames.Mark(Text, 1)
					END
				ELSE
					WHILE S.class = Texts.Name DO
						Option; NEW(source); Texts.Open(source, S.s); PrintUnit(source, 0);
						Texts.Scan(S)
					END;
					IF (S.class = Texts.Char) & (S.c = "^") THEN Oberon.GetSelection(T, beg, end, time);
						IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S);
							IF S.class = Texts.Name THEN
								Option; NEW(source); Texts.Open(source, S.s); PrintUnit(source, 0)
							END
						END
					END
				END;
				Printer.Close
			ELSE
				IF Printer.res = 1 THEN Texts.WriteString(W, " no such printer")
					ELSIF Printer.res = 2 THEN Texts.WriteString(W, " no link")
					ELSIF Printer.res = 3 THEN Texts.WriteString(W, " printer not ready")
					ELSIF Printer.res = 4 THEN Texts.WriteString(W, " no permission")
				END;
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		ELSE Texts.WriteString(W, " no printer specified");
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	END Print;

	PROCEDURE InitPattern;
		VAR j: INTEGER;
	BEGIN
		pat[0] := " "; M := 1; time := -1; j := 0;
		WHILE j # 256 DO d[j] := M; INC(j) END
	END InitPattern;

BEGIN Texts.OpenWriter(W); InitPattern
END Edit.
