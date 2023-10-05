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

MODULE Script;	(** portable *)	(* RS, Wed, 9-Jun-1993*)

(* ChangeFont only fnt.type = Objects.font
	Fri, 26-Nov-93 Search: trap on no selection
	Tue, 17-May-1994 visualize page breaks
	Fri, 10-Jun-1994 generich search/replace
*)

	IMPORT ScriptFrames, Texts, MenuViewers, TextFrames, Oberon, Fonts, Objects, Printer, Display, Styles, Files;

	CONST
		(*MenuStr = "System.Close  System.Copy  System.Grow  Script.NewStyle  Script.Style  Script.Search  Script.Store";*)
		MenuStr = "System.Close  System.Copy  System.Grow  Script.NewStyle  Script.Search  Script.Replace  Script.Store";
		TAB = 9X;
		MaxPatLen = 32;

		(* print options *)
		pageNo = 0;	onTop = 1;	alter = 2;	header = 3;	notFirst = 4;	

		(* print units *)
		PrtUnit = 3048;
	
	
		(* print layout *)
(*
		leftX = 290;
		headY = 3300;	topY = 3200;	botY = 300;	pagY = 150;
		pagW = Styles.pageW DIV PrtUnit;
*)

	
	VAR
		W: Texts.Writer;
		sPat: ARRAY MaxPatLen OF CHAR;	(* search pattern [read only] *)
		sTab: ARRAY 256 OF INTEGER;		(* table for Boyer Moore algorithm *)
		sPatLen: INTEGER;	(* number of valid characters in sPat [read only] *)
		rBuf: Texts.Buffer;	(* replace buffer [read only] *)
		lTime: LONGINT;	(* most recent time for sPat and/or rBuf *)
		lastPno: INTEGER;
		printer, ext, options: ARRAY 32 OF CHAR;
		open: BOOLEAN;	(*very ugly: printer flag*)

	(* print layout *)
		leftX, headY, topY, botY, pagY, pagW: INTEGER;

		head, tail: Objects.Object;	(*page break position*)
		pages: INTEGER;
		
	PROCEDURE MarkBrk(pos: LONGINT);
	BEGIN
		IF tail # NIL THEN tail.stamp := pos;
			NEW(tail.slink); tail := tail.slink; tail.stamp := MAX(LONGINT);
			INC(pages)
		END
	END MarkBrk;

	PROCEDURE OpenViewer (name: ARRAY OF CHAR; F: Display.Frame);
		VAR X, Y : INTEGER; V : MenuViewers.Viewer;
	BEGIN Oberon.AllocateUserViewer(Oberon.UserTrack(Oberon.Mouse.X), X, Y);
		V := MenuViewers.New(TextFrames.NewMenu(name, MenuStr),  F, TextFrames.menuH, X, Y )
	END OpenViewer;

	PROCEDURE OpenScanner(VAR S: Texts.Scanner; F: TextFrames.Frame);
		VAR M: Oberon.SelectMsg;
	BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			IF F # NIL THEN M.time := -1; M.id := Oberon.get; TextFrames.GetSelection(F, M)
			ELSE Oberon.GetSelection(M.text, M.beg, M.end, M.time)
			END;
			IF M.time > 0 THEN Texts.OpenScanner(S, M.text, M.beg); Texts.Scan(S) END
		END
	END OpenScanner;

(* -------- Script commands -------- *)

	PROCEDURE Open*;
	VAR S: Texts.Scanner;
		F: ScriptFrames.Frame; T: Texts.Text;
		name: ARRAY 32 OF CHAR;
	BEGIN OpenScanner(S, NIL);
		IF S.class # Texts.Name THEN name := "Script.Open" ELSE COPY(S.s, name) END;
		NEW(T); Texts.Open(T, name); F := ScriptFrames.NewText(T, 0);
		Texts.Scan(S); F.hide := (S.class = Texts.Char) & (S.c = Oberon.OptionChar) & (S.nextCh = "n");
		OpenViewer (name, F)
	END Open;

	PROCEDURE Backup (VAR name: ARRAY OF CHAR);
	VAR res, i: INTEGER; bak: ARRAY 32 OF CHAR;
	BEGIN
		i := 0; WHILE name[i] # 0X DO bak[i] := name[i]; INC(i) END;
		IF i > 31-4 THEN i := 31-4 END;
		bak[i] := "."; bak[i+1] := "B"; bak[i+2] := "a"; bak[i+3] := "k"; bak[i+4] := 0X;
		Files.Rename(name, bak, res)
	END Backup;

	PROCEDURE Store*;
	(*
		Script.Store from title bar = store text of open viewer (name = document name)
		otherwise store marked viewer
			Script.Store X.Text	(name from parameterlist)
			Script.Store ^	(name from selection)
	*)
	
	VAR
		F: ScriptFrames.Frame;
		par: Oberon.ParList;
		V: Display.Frame;
		S: Texts.Scanner;
		f: Files.File;
		len: LONGINT;
	BEGIN
		Texts.WriteString(W, "Script.Store ");
		par := Oberon.Par; S.s := "";
		IF par.frame = par.vwr.dsc THEN (* command in menu frame *)
			V := par.vwr; MenuViewers.GetName(V(MenuViewers.Viewer), S.s)	(*!*)
		ELSE
			V := Oberon.MarkedViewer(); OpenScanner(S, NIL)
		END;
		IF (V.dsc # NIL) & (V.dsc.next # NIL) & (V.dsc.next IS ScriptFrames.Frame) THEN
			Texts.WriteString(W, S.s); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
			F := V.dsc.next(ScriptFrames.Frame);
			ScriptFrames.Mark(F, -1);
			Backup(S.s); f := Files.New(S.s); Texts.Store(F.text,f,0,len); Files.Register(f);
			ScriptFrames.Mark(F, 1)
		END
	END Store;

(*
	PROCEDURE FindPat(F: ScriptFrames.Frame; pos: LONGINT);
	(* searches pattern sPat beginning at position pos *)
		VAR R: Texts.Reader;	buf: ARRAY MaxPatLen OF CHAR;
			len, lPos: LONGINT; 	n, j: INTEGER;

		PROCEDURE Forward (n: INTEGER);
			VAR m: INTEGER; j: INTEGER;
		BEGIN m := sPatLen - n; j := 0;
			WHILE j # m DO buf[j] := buf[n + j]; INC(j) END;
			WHILE j # sPatLen DO Texts.Read(R, buf[j]); INC(j) END
		END Forward;

	BEGIN
		ScriptFrames.Mark(F, -1);
		len := F.text.len;
		Texts.OpenReader(R, F.text, pos);
		Forward(sPatLen); pos := pos + sPatLen;
		LOOP j := sPatLen;
			REPEAT DEC(j) UNTIL (j < 0) OR (buf[j] # sPat[j]);
			IF (j < 0) OR (pos >= len) THEN EXIT END;
			n := sTab[ORD(buf[sPatLen-1])];
			Forward(n); pos := pos + n
		END;
		IF j < 0 THEN
			ScriptFrames.Neutralize(F); 
			IF (pos < ScriptFrames.Pos(F, 0, F.H)) OR (ScriptFrames.Pos(F, F.W, 0) < pos) THEN
				ScriptFrames.Show(F, pos - 200)
			END;
			Oberon.Defocus; ScriptFrames.SetCaret(F, pos);
			ScriptFrames.SetSelection(F, pos - sPatLen, pos); lTime := F.time
		ELSE
			ScriptFrames.Neutralize(F)
		END;
		ScriptFrames.Mark(F, 1)
	END FindPat;
	
	PROCEDURE Search*;
		VAR F: ScriptFrames.Frame;
			R: Texts.Reader;	text: Texts.Text;
			pos, beg, end, time: LONGINT; 	i: INTEGER;
			par: Oberon.ParList;
	BEGIN par := Oberon.Par; F := NIL;
		IF (par.vwr # NIL) & (par.frame = par.vwr.dsc) THEN
			IF par.frame.next IS ScriptFrames.Frame THEN F := par.frame.next(ScriptFrames.Frame) END
		ELSE F := FocusFrame()
		END;
		IF F = NIL THEN RETURN END;	(*###*)
		text := NIL; Oberon.GetSelection(text, beg, end, time);
		IF (time >= 0) & (*(text # NIL) &*) (text.len > 0) & (time > lTime) THEN	(* set search pattern *)
			Texts.OpenReader(R, text, beg);
			i := 0; pos := beg;
			REPEAT Texts.Read(R, sPat[i]); INC(i); INC(pos) UNTIL (i = MaxPatLen) OR (pos = end);
			sPatLen := i; lTime := time;
			i := 0; WHILE i # 256 DO sTab[i] := sPatLen; INC(i) END;
			i := 0; WHILE i # sPatLen - 1 DO sTab[ORD(sPat[i])] := sPatLen - 1 - i; INC(i) END
		END;
		IF F.car THEN pos := F.carLoc.pos ELSE pos := 0 END;
		FindPat(F, pos)
	END Search;

	PROCEDURE replace(): BOOLEAN;
		VAR F: ScriptFrames.Frame;
			R: Texts.Reader;	tBuf: Texts.Buffer;	text: Texts.Text;
			pos, beg, end, time, p, len: LONGINT; 	i: INTEGER;	ch: CHAR;
	BEGIN
		F := FocusFrame();
		IF F = NIL THEN RETURN FALSE END;	(*###*)
		text := NIL; Oberon.GetSelection(text, beg, end, time);
		IF (time >= 0) & (*(text # NIL) &*) (time > lTime) THEN	(* set replace buffer *)
			lTime := time; NEW(rBuf); Texts.OpenBuf(rBuf); Texts.Save(text, beg, end, rBuf)
		END;
		IF ~F.car OR ~ (sPatLen > 0) OR (rBuf = NIL) THEN RETURN FALSE END;	(*###*)
		pos := F.carLoc.pos; p := pos - sPatLen;
		IF p < 0 THEN RETURN FALSE END;	(*###*)
		Texts.OpenReader(R, F.text, p); Texts.Read(R, ch); i := 0;
		WHILE (ch = sPat[i]) & (i < sPatLen) DO Texts.Read(R, ch); INC(i) END;
		IF i = sPatLen THEN
			NEW(tBuf); Texts.OpenBuf(tBuf); Texts.Copy(rBuf, tBuf); len := tBuf.len;
			Texts.Replace(F.text, p, pos, tBuf); pos := p + len
(*
			Texts.Delete(F.text, p, pos); pos := p;
			NEW(tBuf); Texts.OpenBuf(tBuf);
			Texts.Copy(rBuf, tBuf); len := tBuf.len;
			Texts.Insert(F.text, pos, tBuf); pos := pos + len
*)
		END;
		FindPat(F, pos);
		RETURN F.car
	END replace;
*)

	PROCEDURE SetCaret(F: Display.Frame; text: Texts.Text; pos: LONGINT);
		VAR M: Oberon.CaretMsg;
	BEGIN M.res := -1; M.dlink := NIL; Objects.Stamp(M);
		M.id := Oberon.set; M.F := F; M.car := F; M.text := text; M.pos := pos; F.handle(F, M)
	END SetCaret;

	PROCEDURE SetSelection(F: Display.Frame; text: Texts.Text; beg, end: LONGINT; VAR time: LONGINT);
		VAR M: Oberon.SelectMsg;
	BEGIN M.res := -1; M.dlink := NIL; Objects.Stamp(M);
		M.id := Oberon.set; M.F := F; M.sel := F; M.text := text; M.beg := beg; M.end := end;
		F.handle(F, M);
		M.id := Oberon.get; M.res := -1; M.time := -1; F.handle(F, M); time :=  M.time
	END SetSelection;

	PROCEDURE GetCaret(VAR F: Display.Frame; VAR text: Texts.Text; VAR pos: LONGINT);
		VAR M: Oberon.CaretMsg;
	BEGIN text := NIL; F := NIL;
		M.id := Oberon.get; M.F := NIL; M.car := NIL; Display.Broadcast(M);
		IF M.car # NIL THEN F := M.car; text := M.text; pos := M.pos END
	END GetCaret;

	PROCEDURE FindPat(F: Display.Frame; text: Texts.Text; pos, time: LONGINT): BOOLEAN;
	(* searches pattern sPat beginning at position pos *)
		VAR R: Texts.Reader;	buf: ARRAY MaxPatLen OF CHAR;
			len: LONGINT; 	n, j: INTEGER;
			N: Oberon.ControlMsg;

		PROCEDURE Forward (n: INTEGER);
			VAR m: INTEGER; j: INTEGER;
		BEGIN m := sPatLen - n; j := 0;
			WHILE j # m DO buf[j] := buf[n + j]; INC(j) END;
			WHILE j # sPatLen DO Texts.Read(R, buf[j]); INC(j) END
		END Forward;

	BEGIN
		len := text.len;
		Texts.OpenReader(R, text, pos);
		Forward(sPatLen); pos := pos + sPatLen;
		LOOP j := sPatLen;
			REPEAT DEC(j) UNTIL (j < 0) OR (buf[j] # sPat[j]);
			IF (j < 0) OR (pos >= len) THEN EXIT END;
			n := sTab[ORD(buf[sPatLen-1])];
			Forward(n); pos := pos + n
		END;
		IF j < 0 THEN
			N.id := Oberon.neutralize; N.F := F; Display.Broadcast(N);
			Oberon.Defocus; SetCaret(F, text, pos);
			SetSelection(F, text, pos - sPatLen, pos, lTime);
			RETURN TRUE
		ELSE
			N.id := Oberon.neutralize; N.F := F; Display.Broadcast(N);
			RETURN FALSE
		END
	END FindPat;

	PROCEDURE GetFrame(VAR F: Display.Frame; VAR text: Texts.Text; VAR pos: LONGINT);
		VAR M: Objects.LinkMsg; par: Oberon.ParList;
	BEGIN par := Oberon.Par;
		GetCaret(F, text, pos);
		IF (par.vwr # NIL) & (par.frame # NIL) & (par.frame = par.vwr.dsc) & (F # par.frame.next) THEN
			F := par.frame.next;	(*title bar overrides focus frame*)
			Objects.Stamp(M);
			M.id := Objects.get; M.name[0] := 0X; M.res := -1; M.obj := NIL; F.handle(F, M);	(*get text*)
			IF (M.obj # NIL) & (M.obj IS Texts.Text) THEN text := M.obj(Texts.Text); pos := 0
			ELSE F := NIL
			END
		END
	END GetFrame;

	PROCEDURE Search*;
		VAR F: Display.Frame;
			R: Texts.Reader; text, seltext: Texts.Text;
			pos, beg, end, time: LONGINT; i: INTEGER;
	BEGIN GetFrame(F, text, pos);
		IF F # NIL THEN Oberon.GetSelection(seltext, beg, end, time);
			IF (time >= 0) & (seltext.len > 0) & (time > lTime) THEN	(* set search pattern *)
				Texts.OpenReader(R, seltext, beg);
				i := 0;
				REPEAT Texts.Read(R, sPat[i]); INC(i); INC(beg) UNTIL (i = MaxPatLen) OR (beg = end);
				sPatLen := i; lTime := time;
				i := 0; WHILE i # 256 DO sTab[i] := sPatLen; INC(i) END;
				i := 0; WHILE i # sPatLen - 1 DO sTab[ORD(sPat[i])] := sPatLen - 1 - i; INC(i) END
			END;
			IF FindPat(F, text, pos, time) THEN END
		END
	END Search;

	PROCEDURE replace(): BOOLEAN;
		VAR F: Display.Frame;
			R: Texts.Reader;	tBuf: Texts.Buffer;	text, repltext: Texts.Text;
			pos, beg, end, time, p, len: LONGINT; 	i: INTEGER;	ch: CHAR;
	BEGIN GetFrame(F, text, pos);
		IF F # NIL THEN
			Oberon.GetSelection(repltext, beg, end, time);
			IF (time >= 0) & (time > lTime) THEN	(* set replace buffer *)
				lTime := time; NEW(rBuf); Texts.OpenBuf(rBuf); Texts.Save(repltext, beg, end, rBuf)
			END;
			IF ~ (sPatLen > 0) OR (rBuf = NIL) THEN RETURN FALSE END;	(*###*)
			p := pos - sPatLen;
			IF p < 0 THEN RETURN FALSE END;	(*###*)
			Texts.OpenReader(R, text, p); Texts.Read(R, ch); i := 0;
			WHILE (ch = sPat[i]) & (i < sPatLen) DO Texts.Read(R, ch); INC(i) END;
			IF i = sPatLen THEN
				NEW(tBuf); Texts.OpenBuf(tBuf); Texts.Copy(rBuf, tBuf); len := tBuf.len;
				Texts.Replace(text, p, pos, tBuf); pos := p + len
			END;
			RETURN FindPat(F, text, pos, time)
		END;
		RETURN FALSE
	END replace;

	PROCEDURE Replace*;
	BEGIN
		IF replace() THEN END
	END Replace;
	
	PROCEDURE ReplaceAll*;
	BEGIN
		WHILE replace() DO END
	END ReplaceAll;

	PROCEDURE Font(name: ARRAY OF CHAR): Fonts.Font;	(*append .Scn.Fnt if necessary*)
		VAR i, j: INTEGER;
	BEGIN i := 0;
		WHILE (name[i] # ".") & (name[i] # 0X) DO INC(i) END;
		IF name[i] = 0X THEN j := 0;
			WHILE ext[j] # 0X DO name[i] := ext[j]; INC(i); INC(j) END;
			name[i] := 0X
		END;
		RETURN Fonts.This(name)
	END Font;

	PROCEDURE ChangeFont*;
	VAR S: Texts.Scanner;
		T: Texts.Text; beg, end, time: LONGINT;
		fnt: Fonts.Font;
	BEGIN OpenScanner(S, NIL);
		IF S.class = Texts.Name THEN
			Oberon.GetSelection(T, beg, end, time); fnt := Font(S.s);
			IF (time >= 0) & (fnt.type = Fonts.font) THEN Texts.ChangeLooks(T, beg, end, {0}, fnt, 0, 0) END
		END
	END ChangeFont;

	PROCEDURE ChangeColor*;
	VAR S: Texts.Scanner;
		T: Texts.Text; col: SHORTINT; beg, end, time: LONGINT;
	BEGIN OpenScanner(S, NIL);
		IF S.class # Texts.Int THEN col := S.col ELSE col := SHORT(SHORT(S.i)) END;
		Oberon.GetSelection(T, beg, end, time);
		IF time >= 0 THEN Texts.ChangeLooks(T, beg, end, {1}, NIL, col, 0) END
	END ChangeColor;

	PROCEDURE ChangeOffset*;
	VAR S: Texts.Scanner; T: Texts.Text; voff: SHORTINT; beg, end, time: LONGINT;
	BEGIN OpenScanner(S, NIL);
		IF S.class # Texts.Int THEN voff := S.voff ELSE voff := SHORT(SHORT(S.i)) END;
		Oberon.GetSelection(T, beg, end, time);
		IF time >= 0 THEN Texts.ChangeLooks(T, beg, end, {2}, NIL, 0, voff) END
	END ChangeOffset;

	PROCEDURE Recall*;
		VAR M: Oberon.RecallMsg;
	BEGIN M.F := NIL; Display.Broadcast(M)
	END Recall;

	PROCEDURE NewStyle*;
		VAR M : Display.ConsumeMsg;
	BEGIN M.id := Display.integrate; M.res := -1; M.obj := Styles.NewStyle(); M.F := NIL; Display.Broadcast(M)
	END NewStyle;
	
	PROCEDURE SetStyle*;
	VAR M: Styles.ParamMsg;
		style: Styles.Style;
		F: Display.Frame;
	BEGIN F := Oberon.Par.frame;
		IF F IS TextFrames.Frame THEN
			OpenScanner(M.S, F(TextFrames.Frame)); TextFrames.RemoveSelection(F(TextFrames.Frame))
		ELSE OpenScanner(M.S, NIL)
		END;
		Styles.SelStyle(style);
		IF style # NIL THEN M.id := Styles.set; style.handle(style, M) END
	END SetStyle;
	
	PROCEDURE GetStyle*;
	VAR M: Styles.ParamMsg;
		style: Styles.Style;
		F: Display.Frame;
	BEGIN F := Oberon.Par.frame;
		IF F IS TextFrames.Frame THEN
			OpenScanner(M.S, F(TextFrames.Frame)); TextFrames.RemoveSelection(F(TextFrames.Frame))
		ELSE OpenScanner(M.S, NIL)
		END;
		Styles.SelStyle(style);
		IF style # NIL THEN M.T := Oberon.Log; M.id := Styles.get; style.handle(style, M) END
	END GetStyle;

	PROCEDURE Style*;
	VAR V, F: Display.Frame; par: Oberon.ParList;
		M: Display.DisplayMsg;
		S: Texts.Scanner;
	BEGIN par := Oberon.Par; V := NIL;
		IF par.frame = par.vwr.dsc THEN V := par.vwr	(*menu frame*)
		ELSE Texts.OpenScanner(S, par.text, par.pos); Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "*") THEN V := Oberon.MarkedViewer() END
		END;
		IF (V # NIL) & (V.dsc # NIL) & (V.dsc.next # NIL) THEN F := V.dsc.next;
			IF F IS ScriptFrames.Frame THEN
				WITH F: ScriptFrames.Frame DO
					ScriptFrames.Neutralize(F);
					F.hide := ~F.hide; M.F := F; M.device := Display.screen; M.id := Display.full; Display.Broadcast(M)
				END
			END
		END
	END Style;


(* Script.Print server ( * | ^ | name) {option} ~ *)
	PROCEDURE PrintUnit(T: Texts.Text; name: ARRAY OF CHAR; fnt: Fonts.Font; opts: SET; pn0, pnb, pne, copies: INTEGER);
	TYPE
		Line = POINTER TO LineDesc;

		LineDesc = RECORD
			next: Line;
			len: LONGINT;
			w, asr, dsr, h, nSpc: INTEGER;
			eot, brk: BOOLEAN
		END;
(*
	style height
*)

	VAR
		R: Texts.Reader;
		Y, Y0, pno: INTEGER;
		pbrk: BOOLEAN;
		buf, L: Line;
		style: Styles.Style;
		h0: INTEGER;
		ox, sx, rx: INTEGER;

		PROCEDURE log(ch: CHAR);
		BEGIN Texts.Write(W, ch); Texts.Append(Oberon.Log, W.buf)
		END log;

		PROCEDURE ToPrt(d: INTEGER): INTEGER;
		BEGIN RETURN SHORT(LONG(d) * Display.Unit DIV Printer.Unit)
		END ToPrt;
		
		PROCEDURE OpenPrinter();
			VAR retries: INTEGER;
		BEGIN retries := 4;
			Printer.Open(printer, options);
			WHILE (Printer.res > 0) & (Printer.res < 4) & (retries > 0) DO
				log("-"); Printer.Open(printer, options); DEC(retries)
			END;
			IF Printer.res = 1 THEN Texts.WriteString(W, " no such printer")
			ELSIF Printer.res = 2 THEN Texts.WriteString(W, " no link")
			ELSIF Printer.res = 3 THEN Texts.WriteString(W, " printer not ready")
			ELSIF Printer.res = 4 THEN Texts.WriteString(W, " no permission")
			END;
(*
			IF Printer.FrameX > leftX THEN leftX := Printer.FrameX END;	(*adjust sizes*)
			IF Printer.FrameY > pagY THEN pagY := Printer.FrameY + ToPrt(fnt.height); botY := pagY + 150 END;
			IF Printer.FrameW < pagW THEN pagW := Printer.FrameW END;
			IF Printer.FrameY + Printer.FrameH < headY THEN
				headY := Printer.FrameY + Printer.FrameH - ToPrt(fnt.height); topY := headY - 100
			END
*)
		END OpenPrinter;

		PROCEDURE InitFormatterPrt(T: Texts.Text; VAR L: Line);
		BEGIN NEW(L); ScriptFrames.FirstLine(T, L.w, L.asr, L.dsr, L.nSpc, L.len, L.brk, L.eot); L.h := L.asr+L.dsr;
			style := Styles.defStyle
		END InitFormatterPrt;

		PROCEDURE FormatLinePrt(VAR L: Line);
		BEGIN NEW(L); ScriptFrames.NextLine(L.w, L.asr, L.dsr, L.nSpc, L.len, L.brk, L.eot); L.h := L.asr+L.dsr
		END FormatLinePrt;

		PROCEDURE FrameDsr(F: Display.Frame): INTEGER;
			VAR B: Objects.AttrMsg;
		BEGIN B.dlink := NIL; B.i := 0; Objects.Stamp(B);
			B.res := -1; B.id := Objects.get; B.name := "LineupHY"; F.handle(F, B);
			RETURN ToPrt(SHORT(B.i))
		END FrameDsr;

		PROCEDURE ChW(fnt: Fonts.Font; ch: CHAR): INTEGER;
		VAR obj: Objects.Object; unit: LONGINT;
		BEGIN Styles.MetricFnt(fnt, unit, fnt); fnt.GetObj(fnt, ORD(ch), obj);
			IF fnt.type = Fonts.metric THEN RETURN obj(Fonts.Char).dx
			ELSE RETURN SHORT(unit*obj(Fonts.Char).dx DIV Printer.Unit)
			END
		END ChW;

		PROCEDURE print(pno, pnb, pne: INTEGER): BOOLEAN;
		BEGIN RETURN (pnb <= pno) & (pno < pne)
		END print;
	

		PROCEDURE Offsets(L: Line; VAR ox, sx, rx: INTEGER);
		VAR dw: INTEGER;
		BEGIN
			ox := SHORT(style.left DIV Printer.Unit); sx := 0; rx := 0;
			dw := SHORT(style.paraW DIV Printer.Unit) - L.w;
			IF Styles.left IN style.opts THEN
				IF (Styles.right IN style.opts) & ~L.brk & (L.nSpc > 0) THEN
					sx := dw DIV L.nSpc; rx := dw MOD L.nSpc
				END
			ELSE
				IF Styles.right IN style.opts THEN INC(ox, dw) ELSE INC(ox, dw DIV 2) END
			END
		END Offsets;

		PROCEDURE PrintFrame(G: Display.Frame; X, Y, pno: INTEGER);	(*handles big frames*)
		VAR M: Display.DisplayMsg;
		BEGIN M.res := -1; M.device := Display.printer; M.id := Display.full; M.dlink := NIL;
			M.x := X; M.y := Y - FrameDsr(G); Objects.Stamp(M);
			IF M.x = leftX THEN
				IF ToPrt(G.W) > pagW THEN DEC(M.x, (ToPrt(G.W)-pagW) DIV 2) END;	(*!*)
				IF (M.y < 100) OR (M.y + ToPrt(G.H) > topY) THEN M.y := 100 END	(*!*)
			END;
			G.dlink := NIL; M.F := G; G.handle(G, M)	(*G.dlink : HACK*)
		END PrintFrame;

		PROCEDURE PrintLine(VAR R: Texts.Reader; X, Y, pno, sx, rx: INTEGER; len: LONGINT; VAR pbrk: BOOLEAN);	(*X, Y: baseline*)
		VAR
			buf: ARRAY 256 OF CHAR;
			pos, ddX, unit: LONGINT;
			obj: Objects.Object; G: Display.Frame;
			lib: Objects.Library;
			mlib: Fonts.Font;
			k, x, dx, dY, dX, X0, voff, offX, col: INTEGER;
			ch: CHAR;
	
			PROCEDURE Out;
			BEGIN
				IF (k > 0) & print(pno, pnb, pne) THEN buf[k] := 0X; Printer.String(X0, Y + dY, buf, lib(Fonts.Font)) END; k := 0
			END Out;
	
			PROCEDURE UseColor(col: INTEGER);
			VAR r, g, b: INTEGER;
			BEGIN
				IF print(pno, pnb, pne) THEN
					IF col >= 0 THEN
						Display.GetColor(col MOD 256, r, g, b)
					ELSE
						Display.GetColor((col+256) MOD 256, r, g, b)
					END;
					Printer.UseColor(r, g, b)
				END
			END UseColor;

		BEGIN
			lib := NIL; col := -1; k := 0; pos := 0; pbrk := FALSE;
			x := 0; X0 := X; offX := X;
			WHILE pos # len DO
				Texts.Read(R, ch); INC(pos);
				IF R.lib # NIL THEN
					IF (lib # R.lib) OR (voff # R.voff) OR (col # R.col) THEN Out; X0 := X;
						IF col # R.col THEN col := R.col; UseColor(col) END;
						lib := R.lib; voff := R.voff; dY := 0;
						IF lib IS Fonts.Font THEN
							dY := ToPrt(lib(Fonts.Font).height)*voff DIV 100; Styles.MetricFnt(lib(Fonts.Font), unit, mlib)
						END;
					END;
					lib.GetObj(lib, ORD(ch), obj);
					IF obj IS Fonts.Char THEN dx := obj(Fonts.Char).dx;
						mlib.GetObj(mlib, ORD(ch), obj); dX := obj(Fonts.Char).dx;
						IF mlib.type # Fonts.metric THEN dX := SHORT(unit*dX DIV Printer.Unit) END;
						IF (ch = " ") & ((sx # 0) OR (rx # 0)) THEN Out;
							INC(dX, sx); IF rx > 0 THEN INC(dX); DEC(rx) END;
							INC(X, dX); X0 := X
						ELSIF ch = TAB THEN Out; Styles.Tab(style, lib(Fonts.Font), x, LONG(X-offX)*Printer.Unit, dx, ddX);
							INC(X, SHORT(ddX DIV Printer.Unit)); X0 := X
						ELSIF ch >= " " THEN buf[k] := ch; INC(k); INC(X, dX)
						ELSIF (ch =1FX) & (pos = len) THEN buf[k] := "_"; INC(k)	(*hyph*)
						END;
					ELSE	(*object*)
						IF obj IS Styles.Style THEN style := obj(Styles.Style); pbrk := Styles.break IN style.opts; RETURN END;
						IF obj IS Display.Frame THEN G := obj(Display.Frame); dx := G.W; dX := ToPrt(dx);
							IF print(pno, pnb, pne) THEN PrintFrame(G, X, Y+dY+ToPrt((voff*G.H) DIV 100), pno); col := -1 END;
							INC(X, dX); X0 := X
						END
					END;
					INC(x, dx)
				END
			END;
			Out
		END PrintLine;


		PROCEDURE PrintNum(x, y, n: INTEGER; fnt: Fonts.Font; right: BOOLEAN);
		VAR
			s: ARRAY 8 OF CHAR;
			i, w, k: INTEGER;
		BEGIN i := 7;
			REPEAT s[i] := CHR(n MOD 10 + 30H); DEC(i); n := n DIV 10 UNTIL n = 0;
			k := 0; w := 0;
			WHILE i < 7 DO INC(i); s[k] := s[i]; w := w + ChW(fnt, s[k]); INC(k) END; s[k] := 0X;
			IF right THEN DEC(x, w) END;
			Printer.String(x, y, s, fnt)
		END PrintNum;

		PROCEDURE PageHeader(VAR title: ARRAY OF CHAR; pn: INTEGER; opts: SET);
		VAR y, i, w: INTEGER;
		BEGIN
			IF ~print(pn, pnb, pne) THEN RETURN END;
			Printer.UseColor(0, 0, 0);	(*black*)
			IF header IN opts THEN (* only if (pageNo IN opts) & (onTop IN opts) *)
				IF (pageNo IN opts) & (onTop IN opts) & (alter IN opts) & ~ODD(pn) THEN	(* place header right adjusted *)
					i := 0; w := 0; WHILE title[i] # 0X DO w := w + ChW(fnt, title[i]); INC(i) END;
					Printer.String(leftX + pagW - w, headY, title, fnt)
				ELSE
					Printer.String(leftX, headY, title, fnt)
				END
			END;
			IF pageNo IN opts THEN
				IF onTop IN opts THEN y := headY ELSE y := pagY END;
				IF (alter IN opts) & ~ODD(pn) THEN PrintNum(leftX, y, pn, fnt, FALSE)
				ELSE PrintNum(leftX + pagW, y, pn, fnt, TRUE)
				END
			END
		END PageHeader;

		PROCEDURE Empty(L: Line): BOOLEAN;
		BEGIN RETURN L.brk & (L.len = 1)
		END Empty;
	
		PROCEDURE Title(L0, L: Line): BOOLEAN;	(*L is Title*)
		BEGIN RETURN L.brk & (L.len > 1) & L0.brk & (L0.len = 1)
		END Title;

		PROCEDURE StartPage(pno: INTEGER; VAR Y: INTEGER);
		BEGIN Y := topY;
			IF ~open & (pno >= pnb) THEN
				OpenPrinter(); open := TRUE;
				IF Printer.res # 0 THEN RETURN END;
				IF (pno > pn0) OR ~(notFirst IN opts) THEN PageHeader(name, pno, opts) END
			ELSE PageHeader(name, pno, opts)
			END
		END StartPage;

		PROCEDURE Page(nextL: Line; VAR Y: INTEGER);
		BEGIN pbrk := FALSE;	(*not really needed*)
			MarkBrk(Texts.Pos(R));
			IF print(pno, pnb, pne) THEN Printer.Page(copies); log(".") END;
			IF nextL # NIL THEN INC(pno); StartPage(pno, Y) END
		END Page;

		PROCEDURE Flush(L: Line; Y: INTEGER; VAR h0: INTEGER);
		VAR ox, sx, rx: INTEGER;
		BEGIN	(*print buffer upto L (excl) or page break*)
			WHILE (buf # L) & ~pbrk DO h0 := buf.h;
				Offsets(buf, ox, sx, rx);
				PrintLine(R, leftX+ox, Y-buf.asr, pno, sx, rx, buf.len, pbrk); DEC(Y, buf.h); buf := buf.next
			END;
			IF ~pbrk THEN h0 := 0 END
		END Flush;

		PROCEDURE CompletePage(L: Line; VAR Y: INTEGER);
		VAR h0: INTEGER;
		BEGIN Flush(L, Y, h0); Page(L, Y); DEC(Y, h0)
		END CompletePage;

		PROCEDURE CompletePage0(VAR L: Line; VAR Y: INTEGER);
		VAR h0: INTEGER;
		BEGIN Flush(L, Y, h0);
			(*here*)
			IF ~pbrk THEN	(*skip empty lines on top of page*)
				WHILE Empty(L) & ~L.eot & ~pbrk DO h0 := L.h;
					PrintLine(R, 0, 0, pno, 0, 0, L.len, pbrk); FormatLinePrt(L)
				END;
				(*~Empty OR pbrk*)
				buf := L
			END;
			Page(L, Y); DEC(Y, h0)
		END CompletePage0;

		PROCEDURE CompletePage1;	(*end of doc*)
			VAR h0: INTEGER;
		BEGIN REPEAT Flush(NIL, Y, h0); Page(buf, Y); DEC(Y, h0) UNTIL buf = NIL
		END CompletePage1;

		PROCEDURE ResetBuf(VAR L: Line; VAR Y0: INTEGER);
		VAR L0: Line; i: INTEGER;
		BEGIN L0 := buf; Y0 := topY-L0.h; i := 1;
			WHILE L0 # L DO L0 := L0.next; DEC(Y0, L0.h); INC(i) END;
			WHILE ~L.eot & (i < 5) DO
				FormatLinePrt(L.next); L := L.next; DEC(Y0, L.h);
				IF Y0 < botY THEN CompletePage0(L, Y); Y0 := topY-L.h; i := 0 END;	(*!*)
				INC(i)
			END
		END ResetBuf;

		PROCEDURE PageBreak(VAR L: Line; VAR Y: INTEGER);
		VAR L0, L1: Line;
		BEGIN	(*L goes to next page*)
			L0 := buf.next; L1 := L0.next;
			IF Title(buf, L0) & Empty(L1) THEN CompletePage(L0, Y)	(*Title at L0*)
			ELSIF Title(L0, L1) THEN CompletePage(L1, Y)	(*Title at L1*)
			ELSE L0 := L1; L1 := L0.next;
				(*IF Title(L0, L1) OR ~L1.brk & (L.brk OR L0.brk) THEN CompletePage(L1, Y)	break before L1*)
				IF Title(L0, L1) OR ~L1.brk & L0.brk THEN CompletePage(L1, Y)	(*Title OR first 2 lines of para*)
				ELSIF ~L1.brk & L.brk THEN	(*last 2 lines of para*)
					IF buf.next.brk & ~L0.brk THEN CompletePage(L0, Y)	(*3 lines para at once*)
					ELSE CompletePage(L1, Y)	(*last 2 lines of para*)
					END
				ELSE
					CompletePage0(L, Y)	(*normal break at L*)
				END
			END
		END PageBreak;

	BEGIN Texts.WriteString(W, name);
		IF T.len > 0 THEN Texts.WriteString(W, " printing"); Texts.Append(Oberon.Log, W.buf);
			InitFormatterPrt(T, buf); Texts.OpenReader(R, T, 0);
			L := buf; Y := topY; ResetBuf(L, Y0); pno := pn0; pbrk := FALSE;
			StartPage(pno, Y);
			IF open & (Printer.res # 0) THEN RETURN END;
			REPEAT
				h0 := buf.h;	(*save height for explicit page break (gap)*)
				Offsets(buf, ox, sx, rx);
				PrintLine(R, leftX+ox, Y-buf.asr, pno, sx, rx, buf.len, pbrk); DEC(Y, buf.h); buf := buf.next;
				IF pbrk THEN Page(buf, Y); ResetBuf(L, Y0); DEC(Y, h0); DEC(Y0, h0) END;	(*explicit*)
				IF ~L.eot THEN
					FormatLinePrt(L.next); L := L.next; DEC(Y0, L.h);
					IF Y0 < botY THEN
						PageBreak(L, Y); ResetBuf(L, Y0);
						L.eot := L.eot OR (pno >= pne)
					END
				END;
				IF open & (Printer.res # 0) THEN RETURN END
			UNTIL L.eot;
			CompletePage1;
			lastPno := pno;
			(*IF open THEN Printer.Close END*)
		ELSE
			Texts.WriteString(W, " not found"); Texts.Append(Oberon.Log, W.buf)
		END
	END PrintUnit;

(*
	opt = {"/" name [par [par]]}.

	PROCEDURE OutScan(VAR S: Texts.Scanner; s: ARRAY OF CHAR);
	BEGIN
		Out.String(s); Out.Char(" ");
		IF S.class = Texts.Char THEN Out.String("char ");Out.Char(S.c)
		ELSIF S.class = Texts.Name THEN Out.String("name ");Out.String(S.s)
		ELSIF S.class = Texts.Int THEN Out.String("int ");Out.Int(S.i, 0)
		ELSE HALT(66)
		END;
		Out.Ln
	END OutScan;
*)

	PROCEDURE Options(VAR S: Texts.Scanner; VAR fnt: Fonts.Font; VAR opts: SET; VAR pn0, pnb, pne, copies: INTEGER);
	CONST
		pageNo = 0;	onTop = 1;	alter = 2;	header = 3;	notFirst = 4;
	VAR
		i, line: INTEGER;
		opt: ARRAY 16 OF CHAR;
	(* /h header (file name & date)
		/c 0..9
		/p[a][t][f][c] [number] alternate/top
		/r number [number] range
		/f name
	*)
	BEGIN
		opts := {}; pnb := MIN(INTEGER); pne := MAX(INTEGER); copies := 1; pn0 := 0; fnt := Fonts.Default;	(*init*)
		line := S.line;
		WHILE (S.class = Texts.Char) & ((S.c = Oberon.OptionChar)) & (S.line = line) DO
			Texts.Scan(S);	(*opt*)
			IF (S.line = line) & (S.class = Texts.Name) THEN
				COPY(S.s, opt); Texts.Scan(S);
				IF opt[0] = "h" THEN INCL(opts, header)	(*header*)
				ELSIF opt[0] = "c" THEN	(*copies*)
					IF S.class = Texts.Int THEN copies := SHORT(S.i); Texts.Scan(S) END
				ELSIF opt[0] = "r" THEN	(*range*)
					IF S.class = Texts.Int THEN pnb := SHORT(S.i); Texts.Scan(S) END;
					IF S.class = Texts.Int THEN pne := SHORT(S.i); Texts.Scan(S) END
				ELSIF opt[0] = "f" THEN	(*font*)
					IF S.class = Texts.Name THEN fnt := Font(S.s); Texts.Scan(S) END
				ELSIF opt[0] = "u" THEN	(*US letter*)
					topY := 2900; headY := topY + 100
(*
	PROCEDURE ReadString(VAR R: Texts.Reader; VAR s: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN Texts.Read(R, ch);
		WHILE ~R.eot & (ch # 22X) DO Texts.Read(R, ch) END; Texts.Read(R, ch);
		i := 0; WHILE ~R.eot & (ch # 22X) & (i < LEN(s)-1) DO s[i] := ch; INC(i); Texts.Read(R, ch) END;
		s[i] := 0X;
	END ReadString;

				ELSIF opt[0] = "H" THEN	(*Header*)
					IF opt[1] = "t" THEN ReadString(S, ht)
					ELSIF opt[1] = "c" THEN ReadString(S, hc)
					ELSE ReadString(S, ht); COPY(ht, hc)
					END
*)
				ELSIF opt[0] = "p" THEN	(*page numbering*)
					INCL(opts, pageNo); i := 1;
					WHILE opt[i] # 0X DO
						IF opt[i] = "a" THEN	INCL(opts, alter)
						ELSIF opt[i] = "t" THEN INCL(opts, onTop)
						ELSIF opt[i] = "f" THEN INCL(opts, notFirst)
						ELSIF opt[i] = "c" THEN pn0 := lastPno+1	(*continuous*)
						END;
						INC(i)
					END;
					IF S.class = Texts.Int THEN pn0 := SHORT(S.i); Texts.Scan(S) END
				END
			END
		END
	END Options;

	PROCEDURE Scale(VAR x: INTEGER);
	BEGIN
		x := SHORT(LONG(x) * PrtUnit DIV Printer.Unit)
	END Scale;

(* Script.Print Pluto (^ | * [opts] | {name [opts]}) *)
PROCEDURE Print*;
VAR
	S: Texts.Scanner;
	V: Display.Frame;
	F: ScriptFrames.Frame;
	title: ARRAY 32 OF CHAR;
	T: Texts.Text; beg, end, time: LONGINT;
	
	PROCEDURE PrintText(T: Texts.Text; title: ARRAY OF CHAR; VAR S: Texts.Scanner);
	VAR opts: SET; pn0, pnb, pne, copies: INTEGER; fnt: Fonts.Font;
	BEGIN
		leftX := 290; pagW := SHORT(Styles.pageW DIV Printer.Unit);	(*reset default print metrics*)
		headY := 3300; topY := 3200; botY := 300; pagY := 150;
		Scale(leftX);  Scale(headY);  Scale(topY);  Scale(botY);  Scale(pagY);
		Texts.Scan(S);
		Options(S, fnt, opts, pn0, pnb, pne, copies);
		IF T = NIL THEN NEW(T); Texts.Open(T, title) END;
		PrintUnit(T, title, fnt, opts, pn0, pnb, pne, copies)
	END PrintText;

BEGIN
	Texts.WriteString(W, "Script.Print ");
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF S.class IN {Texts.String, Texts.Name} THEN COPY(S.s, printer);
		COPY(S.s, printer);
		IF S.nextCh = Oberon.OptionChar THEN Texts.Scan(S); Texts.Scan(S); 
			COPY(S.s, options)
		ELSE options := ""
		END;
		Texts.WriteString(W, printer); 
		IF options # "" THEN Texts.Write(W, Oberon.OptionChar);
			Texts.WriteString(W, options)
		END;
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
(*	Printer.Open(S.s, Oberon.User, Oberon.Password);
		IF Printer.res = 0 THEN
*)
			Texts.Scan(S); open := FALSE;
			IF S.class = Texts.Char THEN
				IF S.c = "*" THEN V := Oberon.MarkedViewer();
					IF (V.dsc # NIL) & (V.dsc.next # NIL) & (V.dsc.next IS ScriptFrames.Frame) THEN
						F := V.dsc.next(ScriptFrames.Frame);
						MenuViewers.GetName(V(MenuViewers.Viewer), title);
						ScriptFrames.Mark(F, -1); PrintText(F.text, title, S); ScriptFrames.Mark(F, 1)
					END
				ELSIF S.c = "^" THEN Oberon.GetSelection(T, beg, end, time);
					IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S);
						IF S.class = Texts.Name THEN PrintText(NIL, S.s, S) END
					END
				END
			ELSE
				WHILE S.class = Texts.Name DO PrintText(NIL, S.s, S); Texts.WriteLn(W) END
			END;
			IF open THEN Printer.Close END
(*
		ELSE
			IF Printer.res = 1 THEN Texts.WriteString(W, " no such printer")
			ELSIF Printer.res = 2 THEN Texts.WriteString(W, " no link")
			ELSIF Printer.res = 3 THEN Texts.WriteString(W, " printer not ready")
			ELSIF Printer.res = 4 THEN Texts.WriteString(W, " no permission")
			END
		END*)
	ELSE Texts.WriteString(W, " no printer specified")
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END Print;

	PROCEDURE PageBreaks*;
		VAR S: Texts.Scanner;
			V: Display.Frame; F: ScriptFrames.Frame;
			dmy: ARRAY 1 OF CHAR; d: INTEGER;
			opts: SET; fnt: Fonts.Font;
	BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF S.c = "*" THEN V := Oberon.MarkedViewer();
			IF (V.dsc # NIL) & (V.dsc.next # NIL) & (V.dsc.next IS ScriptFrames.Frame) THEN
				F := V.dsc.next(ScriptFrames.Frame);
				leftX := 290; pagW := SHORT(Styles.pageW DIV Printer.Unit);	(*reset default print metrics*)
				headY := 3300; topY := 3200; botY := 300; pagY := 150;
				Scale(leftX);  Scale(headY);  Scale(topY);  Scale(botY);  Scale(pagY);
				Texts.Scan(S); Options(S, fnt, opts, d, d, d, d);
				ScriptFrames.Mark(F, -1);
				NEW(tail); head := tail; dmy[0] := 0X; pages := 0;
				PrintUnit(F.text, dmy, Fonts.Default, {}, MIN(INTEGER), MAX(INTEGER), MAX(INTEGER), 0);
				Texts.WriteInt(W, pages, 5); Texts.WriteString(W, " page(s)"); Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf);
				F.slink := head; tail := NIL; head := NIL;
				ScriptFrames.Mark(F, 1);
				ScriptFrames.Show(F, F.org)
			END
		END
	END PageBreaks;



BEGIN
	Texts.OpenWriter(W); lastPno := 0;
	ext := ".Scn.Fnt"
END Script.
