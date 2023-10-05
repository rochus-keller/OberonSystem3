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

MODULE Builder;	(** portable, except where noted *)

(*
	29.3.94 - Check if module is missing
	19.4.04 - Added support for /d compile option
	11.5.94 - remove error gadgets from the text 
	9.6.94 - Can compile from all text editors that keep to the Oberon conventions, does not import documents any more
	17.11.94 - improved option char
	15.11.94 - modified gettext
	12.1.94 - fixed /f option compilation
	18.1.95 - improved NextError
	23.10.95 - fixed free trap
	5.1.96 - increase filename length
	10.02.96 pjm - Native Oberon
	15.03.96 pjm - OptionChar
	25.03.96 pjm - get message from Oberon.Text
	14.05.96 prk - preprocessor
	11.07.96 pjm - fixed module message
	06.08.96 prk - preprocessor initialisation (consequence of the changes in the compiler)
	20.09.96 prk - Correct handling of preprocessor instructions in the WriteFileName procedure
							- small cleanup in the preprocessor
*)

IMPORT
	OPS, OPM,
	Compiler, Oberon, Display, Gadgets, Texts, Attributes, Objects, Icons, Modules, Display3, Fonts, Effects, Files, Strings;
	
CONST
	(* Native Oberon compiler *)
	eof = 67; module = 65; import = 64;  if = 47; elsif = 45; else = 44; end = 43; semicolon = 41;
	ident = 40; becomes = 34; not = 33; then = 26; comma = 19; or = 8; and = 5; undef = 0;
	
	(* Windows & Macintosh Oberon compilers
	eof = 64; module = 63; import = 62; if = 45; elsif = 43; else = 42; end = 41; semicolon = 39;
	ident = 38; becomes = 34; not = 33; then = 26; comma = 19; or = 8; and = 5; undef = 0;
	*)
	
	MaxErrors = 100;

TYPE
	ErrorGadget* = POINTER TO ErrorGadgetDesc;
	ErrorGadgetDesc* = RECORD (Gadgets.FrameDesc)
		errno*: INTEGER;
		msg*: POINTER TO ARRAY 128 OF CHAR;
	END;

	(* Module hierarchy *)
	Mod* = POINTER TO ModDesc;
	Ref* = POINTER TO RefDesc;
	RefDesc* = RECORD
		mod*: Mod;
		next*: Ref;
	END;
	ModDesc* = RECORD 
		name*, fname*, opts*: ARRAY 64 OF CHAR;
		ref*, layer*: INTEGER;
		impl*: Ref;
		next*: Mod;
	END;
	
	Tree* = RECORD
		maxlayer*: INTEGER;
		list*: Mod;
	END;

	List = POINTER TO ListDesc;			(* list of the flags used by the preprocessor *)
	ListDesc = RECORD
		name: ARRAY 32 OF CHAR;
		next: List
	END;

VAR
	W: Texts.Writer;
	sym: SHORTINT; (* << win *)
	error, autoMark: BOOLEAN;

	(*Preprocessor*)
	sourceS: Texts.Scanner;
	targetW: Texts.Writer;
	Flags: List;
	lib: Objects.Library;	(* Library of last character/object read. *)
	col: SHORTINT;		(* Color index of last character read. *)
	ifdepth: LONGINT;		(* number of $if levels *)
	OPSGet: OPS.GetProc;
	skipping: BOOLEAN;
	first: BOOLEAN;	(* first attempt to read Oberon.Text/OP2.Errors *)

(** Get the marked text *)
PROCEDURE GetText(VAR par: Display.Frame): Texts.Text;
BEGIN
	par := Oberon.MarkedFrame();
	RETURN Oberon.MarkedText()
END GetText;

(* ---------------- ErrorGadget -------------- *)

PROCEDURE ErrorGadgetAttr(F: ErrorGadget; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("Builder.NewErrorGadget", M.s); M.res := 0
		ELSIF M.name = "LineupHY" THEN M.class := Objects.Int; M.i := ABS(Fonts.Default.minY) + 1; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		Gadgets.framehandle(F, M);
	ELSIF M.id = Objects.enum THEN
		Gadgets.framehandle(F, M)
	END
END ErrorGadgetAttr;

PROCEDURE RestoreErrorGadget(F: ErrorGadget; M: Display3.Mask; x, y, w, h: INTEGER);
VAR s: ARRAY 128 OF CHAR;
BEGIN
(*
	Display3.FilledRect3D(M, Display3.topC, Display3.bottomC, Display3.groupC, x, y, w, h, 1, Display.replace);
*)
	Display3.ReplConst(M, Display3.groupC, x, y, w, h, Display.replace);
	IF F.msg # NIL THEN
		Display3.CenterString(M, Display.FG, x, y, w, h, Fonts.Default, F.msg^, Display.paint)
	ELSE
		Strings.IntToStr(ABS(F.errno), s);
		Display3.CenterString(M, Display.FG, x, y, w, h, Fonts.Default, s, Display.paint)
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreErrorGadget;

PROCEDURE CopyErrorGadget*(VAR M: Objects.CopyMsg; from, to: ErrorGadget);
BEGIN
	to.errno := from.errno;
	Gadgets.CopyFrame(M, from, to);
END CopyErrorGadget;

PROCEDURE GetErrMsg (errNr: INTEGER; VAR msg: ARRAY OF CHAR);	
VAR s: Texts.Scanner; n: INTEGER; ch: CHAR;  warn: BOOLEAN;
BEGIN
	Oberon.OpenScanner(s, "OP2.Errors");
	IF s.class = Texts.Inval THEN msg[0] := 0X;
		IF first THEN
			Texts.WriteString(W, "Oberon.Text - OP2.Errors not found");  Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf);
			first := FALSE
		END
	ELSE
		warn := (errNr < 0);  errNr := ABS(errNr);
		REPEAT Texts.Scan(s) UNTIL s.eot OR (s.class = Texts.Int) & (s.i = 0);
		WHILE ~ s.eot & ((s.class # Texts.Int) OR (s.i # errNr)) DO
			Texts.Scan(s);  IF (s.class = Texts.Char) & (s.c = "}") THEN s.eot := TRUE END
		END;
		IF ~s.eot THEN Texts.Read(s, ch); n := 0;
			IF warn THEN COPY("warning: ", msg);
				WHILE msg[n] # 0X DO INC(n) END
			END;
			WHILE ~s.eot & (ch # 0DX) DO msg[n] := ch; INC(n); Texts.Read(s, ch) END;
			msg[n] := 0X
		END
	END
END GetErrMsg;

PROCEDURE FlipMsg(F: ErrorGadget);
VAR w, h, dsr: INTEGER; A: Display.ModifyMsg;
BEGIN
	IF F.msg = NIL THEN
		NEW(F.msg); GetErrMsg(F.errno, F.msg^); Display3.StringSize(F.msg^, Fonts.Default, w, h, dsr);
		INC(w, 5);
	ELSE F.msg := NIL; w := 20
	END;
	A.F := F; A.id := Display.extend; A.mode := Display.display;
	A.X := F.X; A.Y := F.Y; A.W := w; A.H := F.H;
	A.dX := 0; A.dY := 0; A.dW := A.W - F.W; A.dH := 0;
	Display.Broadcast(A);
END FlipMsg;

PROCEDURE ErrorGadgetHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h: INTEGER; F0: ErrorGadget; R: Display3.Mask; keysum: SET;
BEGIN
	WITH F: ErrorGadget DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN	(* message addressed to this frame *)
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate display coordinates *)
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									RestoreErrorGadget(F, R, x, y, w, h)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreErrorGadget(F, R, x, y, w, h)
								END
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) & (M.keys = {1}) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								Effects.TrackHighlight(R, keysum, M.X, M.Y, x, y, w, h);
								IF (keysum = {1}) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN
									FlipMsg(F);
								END;
								M.res := 0
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
			
		(* Object messages *)
		
		ELSIF M IS Objects.AttrMsg THEN ErrorGadgetAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN
					Files.WriteInt(M.R, F.errno);
					IF F.msg # NIL THEN Files.WriteInt(M.R, 1); Files.WriteString(M.R, F.msg^) ELSE Files.WriteInt(M.R, 0) END;
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN
					Files.ReadInt(M.R, F.errno);
					Files.ReadInt(M.R, x);
					IF x = 1 THEN NEW(F.msg); Files.ReadString(M.R, F.msg^) END;
					Gadgets.framehandle(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink	(* copy msg arrives again *)
				ELSE	(* first time copy message arrives *)
					NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyErrorGadget(M, F, F0); M.obj := F0
				END
			END
		ELSE	(* unknown msg, framehandler might know it *)
			Gadgets.framehandle(F, M)
		END
	END
END ErrorGadgetHandler;

PROCEDURE NewErrorGadget*;
VAR F: ErrorGadget;
BEGIN NEW(F); F.W := 20; F.H := 14; F.errno := 255;F.handle := ErrorGadgetHandler; Objects.NewObj := F;
END NewErrorGadget;

PROCEDURE MarkErrorPos(T: Texts.Text; pos: LONGINT; err: INTEGER);
VAR obj: Objects.Object;
BEGIN
	NewErrorGadget; obj := Objects.NewObj; obj(ErrorGadget).errno := err;
	Texts.WriteObj(W, obj);
	Texts.Insert(T, pos, W.buf)
END MarkErrorPos;

PROCEDURE RemoveErrors(T: Texts.Text);
VAR first: LONGINT; F: Texts.Finder; o: Objects.Object;
BEGIN
	first := -1;
	LOOP
		Texts.OpenFinder(F, T, 0);
		IF F.eot THEN EXIT END;
		first := F.pos;
		Texts.FindObj(F, o);
		LOOP
			IF F.eot THEN EXIT END;
			IF (o # NIL) & (o IS ErrorGadget) THEN EXIT
			ELSE
				first := F.pos;
				Texts.FindObj(F, o);
			END;
		END;
		IF F.eot THEN EXIT END;
		IF (o # NIL) & (o IS ErrorGadget) THEN
			Texts.Delete(T, first, first+1)
		END
	END
END RemoveErrors;

PROCEDURE markErrors(VAR S: Texts.Scanner; errtext: Texts.Text; par: Display.Frame);
VAR c, err: INTEGER; pos, beg, l, k: LONGINT; C: Oberon.CaretMsg;  warn: BOOLEAN;
	marked: ARRAY MaxErrors OF LONGINT;
BEGIN
	c := 0; beg := -1; marked[0] := 0;
	WHILE (S.class = Texts.Name) & (S.s = "pos") & (c # MaxErrors) DO
		Texts.Scan(S); pos := S.i; Texts.Scan(S);
		warn := (S.class = Texts.Name) & (S.s = "warning");
		Texts.Scan(S); err := SHORT(S.i);
		IF warn THEN err := -err END;
		l := 0;  WHILE (l # c) & (marked[l] < pos) DO INC(l) END;
		k := c;  WHILE k # l DO marked[k] := marked[k-1];  DEC(k) END;
		marked[l] := pos;
		MarkErrorPos(errtext, pos + l, err); INC(c);
		IF beg < 0 THEN
			beg := pos+l
		END;
		l := S.line;  REPEAT Texts.Scan(S) UNTIL S.eot OR (S.line # l)
	END;
	IF (beg > 0) & (par # NIL) THEN
		C.id := Oberon.set; C.F := par; C.car := par; C.text := errtext; C.pos := beg;
		Display.Broadcast(C)
	END
END markErrors;

PROCEDURE MarkErrors*;
VAR S: Texts.Scanner; par: Display.Frame; beg, end, time: LONGINT;  T, errtext: Texts.Text;
BEGIN
	errtext := GetText(par);
	IF errtext # NIL THEN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "^") OR (S.line # 0) THEN
			Oberon.GetSelection(T, beg, end, time);
			IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
		END;
		markErrors(S, errtext, par)
	END
END MarkErrors;

PROCEDURE ClearErrors*;
VAR T: Texts.Text; par: Display.Frame; 
BEGIN
	T := GetText(par);
	IF T # NIL THEN RemoveErrors(T) END
END ClearErrors;

PROCEDURE ErrorAfter(T: Texts.Text; VAR pos: LONGINT);
VAR F: Texts.Finder; o: Objects.Object; p: LONGINT;
BEGIN
	Texts.OpenFinder(F, T, pos);
	p := F.pos; Texts.FindObj(F, o);
	WHILE (o # NIL) & (~(o IS ErrorGadget) OR (p <= pos)) DO p := F.pos; Texts.FindObj(F, o) END;
	IF (o # NIL) & (o IS ErrorGadget) THEN pos := p + 1 ELSE pos := -1 END;
END ErrorAfter;

PROCEDURE NextError*;
VAR M: Oberon.CaretMsg; pos: LONGINT;
BEGIN
	M.F := NIL; M.id := Oberon.get; M.car := NIL; M.text := NIL; Display.Broadcast(M);
	IF (M.car # NIL) & (M.text # NIL) THEN
		pos := M.pos; ErrorAfter(M.text, pos);
		IF pos >= 0 THEN
			M.id := Oberon.set; M.F := M.car; M.pos := pos; Display.Broadcast(M)
		ELSE (* no more errors *)
			pos := 0; ErrorAfter(M.text, pos);
			IF pos >= 0 THEN
				M.id := Oberon.set; M.F := M.car; M.pos := pos; Display.Broadcast(M)
			ELSE Oberon.Defocus
			END
		END
	END
END NextError;

(* ---------------- preprocessor --------------------- *)

PROCEDURE err (pos: LONGINT; msg: ARRAY OF CHAR);
BEGIN
	Texts.WriteString (W, "  pos  "); Texts.WriteInt (W, pos, 1);
	Texts.WriteString (W, "  "); Texts.WriteString (W, msg);
	Texts.WriteLn (W);
	Texts.Append (Oberon.Log, W.buf)
END err;

PROCEDURE FindFlag (name: ARRAY OF CHAR): BOOLEAN;
	VAR p: List;
BEGIN
	p := Flags.next;
	WHILE (p # NIL) & (p.name # name) DO p := p.next END;
	RETURN p # NIL
END FindFlag;

PROCEDURE InsertFlag (name: ARRAY OF CHAR);
	VAR p, q: List;
BEGIN
	p := Flags;
	WHILE (p.next # NIL) & (p.next.name < name) DO p := p.next END;
	NEW(q); COPY(name, q.name); q.next := p.next; p.next := q
END InsertFlag;

PROCEDURE ResetFlags;
BEGIN
	NEW(Flags); Flags.next := NIL
END ResetFlags;

PROCEDURE ReadCh (VAR reader: Texts.Scanner; VAR ch:CHAR);
BEGIN
	ch := reader.nextCh; Texts.Read (reader, ch); reader.nextCh := " "; 
END ReadCh;

PROCEDURE ReadToken (VAR scanner: Texts.Scanner);
BEGIN
	Texts.Scan (scanner)
END ReadToken;

PROCEDURE WriteCh (ch: CHAR);
BEGIN
	IF sourceS.lib # lib THEN Texts.SetFont (targetW, sourceS.lib); lib := sourceS.lib END;
	IF sourceS.col # col THEN Texts.SetColor (targetW, sourceS.col); col := sourceS.col END;
	Texts.Write (targetW, ch)
END WriteCh;

PROCEDURE WriteToken (scanner: Texts.Scanner);
BEGIN
	ASSERT (scanner.class # Texts.Inval);
	IF sourceS.lib # lib THEN Texts.SetFont (targetW, sourceS.lib); lib := sourceS.lib END;
	IF sourceS.col # col THEN Texts.SetColor (targetW, sourceS.col); col := sourceS.col END;
	CASE scanner.class OF
		Texts.Name: Texts.WriteString (targetW, scanner.s)
	|  Texts.String: Texts.Write (targetW, 22X); Texts.WriteString (targetW, scanner.s); Texts.Write (targetW, 22X)
	|  Texts.Int: Texts.WriteInt (targetW, scanner.i, 0)
	|  Texts.Real: Texts.WriteReal (targetW, scanner.x, 0)
	|  Texts.LongReal: Texts.WriteLongReal (targetW, scanner.y, 0)
	|  Texts.Char: Texts.Write (targetW, scanner.c)
	END
END WriteToken;

PROCEDURE Expression(): BOOLEAN;
	VAR r: BOOLEAN;
	
	PROCEDURE Factor(): BOOLEAN;
		VAR r: BOOLEAN;
	BEGIN
		IF (sourceS.class = Texts.Char) & (sourceS.c = "~") THEN
			ReadToken (sourceS);
			RETURN ~Factor()
		END;
		IF sourceS.class # Texts.Name THEN err ( Texts.Pos (sourceS), "ident expected")
		ELSE r := FindFlag (sourceS.s)
		END;
		ReadToken (sourceS);
		RETURN r
	END Factor;
	
	PROCEDURE Term(): BOOLEAN;
		VAR r: BOOLEAN;
	BEGIN
		r := Factor();
		WHILE (sourceS.class = Texts.Char) & (sourceS.c = "&") DO
			ReadToken (sourceS);
			r := Factor() & r;	(* !!! r & Factor() doesn't call Factor() if r is already FALSE *)
		END;
		RETURN r
	END Term;
	
BEGIN
	r := Term();
	WHILE (sourceS.class = Texts.Name) & (sourceS.s = "OR") DO
		ReadToken (sourceS);
		r := Term() OR r;	(* !!! r OR Term() doesn't call Term() if r is already TRUE *)
	END;
	IF (sourceS.class # Texts.Name) OR (sourceS.s # "THEN") THEN
		err ( Texts.Pos (sourceS), "THEN expected")
	ELSE
		(*ReadToken (sourceS)*)
	END;
	RETURN r
END Expression;

PROCEDURE PreCopy (ch: CHAR; copy: BOOLEAN);
	VAR b: BOOLEAN;
BEGIN
	LOOP
		IF sourceS.eot THEN EXIT END;
		IF ch = "$" THEN ReadToken (sourceS);
			b := FALSE;
			IF (sourceS.class = Texts.Name) & (sourceS.s = "IF") THEN
				REPEAT
					ReadToken (sourceS);
					IF ~b & Expression() THEN PreCopy (sourceS.nextCh, copy); b := TRUE
					ELSE PreCopy (sourceS.nextCh, FALSE)
					END;
				UNTIL (sourceS.class # Texts.Name) OR (sourceS.s # "ELSIF");
				IF (sourceS.class = Texts.Name) & (sourceS.s = "ELSE") THEN
					IF ~b  THEN PreCopy (sourceS.nextCh, copy);
					ELSE PreCopy (sourceS.nextCh, FALSE)
					END
				END;
				IF (sourceS.class # Texts.Name) OR (sourceS.s # "END") THEN
					WriteCh ("$"); WriteToken(sourceS); ReadCh(sourceS, ch)
					(*err ( Texts.Pos (sourceS), "wrong command")*)
				END;
				ch := sourceS.nextCh
			ELSIF (sourceS.class = Texts.Name) & (sourceS.s = "ELSIF") THEN EXIT
			ELSIF (sourceS.class = Texts.Name) & (sourceS.s = "ELSE") THEN EXIT
			ELSIF (sourceS.class = Texts.Name) & (sourceS.s = "END") THEN EXIT
			ELSE 
				WriteCh ("$"); WriteToken(sourceS); ReadCh(sourceS, ch)
				(* err ( Texts.Pos (sourceS), "wrong command") *)
			END
		ELSE
			IF copy THEN WriteCh (ch) END;
			IF ch = 22X THEN	(* skip strings *)
				REPEAT
					ReadCh(sourceS, ch);
					IF copy THEN WriteCh (ch) END
				UNTIL (ch = 22X) OR sourceS.eot
			END;
			ReadCh(sourceS, ch)
		END
	END;		
END PreCopy;

(** Builder.Preprocess {\Flag} Source [Target] ~
		The file Source is preprocessed with the symbols Flag and the file Target contains
		the result of the operation. If Target is missing, Source.Pre is generated
*)
PROCEDURE Preprocess*;	(** non-portable *)
	VAR source, target: ARRAY 32 OF CHAR; S: Texts.Scanner; t: Texts.Text; f: Files.File; ch: CHAR;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);	ResetFlags;
	WHILE (S.class = Texts.Char) & (S.c = Oberon.OptionChar) DO
		Texts.Scan(S);
		IF S.s = "D" THEN
			Texts.Scan(S);
			Texts.Scan(S);
			IF S.class = Texts.Name THEN InsertFlag(S.s); (*Texts.WriteString(W, "\D="); Texts.WriteString(W, S.s)*) END;
			Texts.Scan(S);
		END;
	END;
	WHILE S.class = Texts.Name DO COPY(S.s, source);
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "=") & (S.nextCh = ">") THEN
			Texts.Scan(S); Texts.Scan(S);
			IF S.class = Texts.Name THEN
				COPY(S.s, target)
			ELSE
				Texts.WriteString(W, "Error after "); Texts.WriteString(W, source); Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf);
				RETURN
			END
		ELSE COPY (source, target); Strings.Append(target, ".Pre")
		END;
		Texts.Scan(S);
		Texts.WriteString ( W, "Preprocess "); Texts.WriteString (W, source);
		Texts.WriteString ( W, " => "); Texts.WriteString (W, target);
		Texts.WriteLn (W); Texts.Append (Oberon.Log, W.buf);
		NEW(t); Texts.Open(t, source); Texts.OpenScanner(sourceS, t, 0);
		Texts.OpenReader(sourceS, t, 0); ReadCh(sourceS, ch);
		Texts.OpenWriter(targetW);
		col := -1; lib := NIL;
		PreCopy (ch, TRUE);
		NEW(t); Texts.Open(t, ""); Texts.Append(t, targetW.buf);
		f := Files.New (target); Texts.Store (t, f, 0, t.len); Files.Register (f)
	END;
	OPS.Get := NIL;	(*remove preprocessor*)
END Preprocess;


PROCEDURE get(VAR sym: SHORTINT);
	VAR body: BOOLEAN;
	
	PROCEDURE Skip;
	BEGIN
		skipping := TRUE;	(* prevent recursion in Get caused by parsing the comments *)
		REPEAT
			OPSGet(sym);
		UNTIL (sym = undef) OR (sym = eof);
		OPSGet(sym);
		WHILE sym = if DO
			REPEAT Skip UNTIL sym # elsif;
			IF sym = else THEN Skip END;
			Skip
		END;
		skipping := FALSE;
	END Skip;

	PROCEDURE CheckTHEN;
	BEGIN
		IF sym # then THEN err (OPM.errpos, "THEN expected")
		END
	END CheckTHEN;
	
	PROCEDURE Expression(): BOOLEAN;	(* <-- it should be possible to merge the two expression procedures *)
	VAR r: BOOLEAN;
	
	PROCEDURE Factor(): BOOLEAN;
		VAR r: BOOLEAN;
	BEGIN
		IF sym = not THEN
			OPSGet (sym);
			RETURN ~Factor()
		END;
		IF sym # ident THEN err ( Texts.Pos (sourceS), "ident expected")
		ELSE r := FindFlag (OPS.name)
		END;
		OPSGet (sym);
		RETURN r
	END Factor;
	
	PROCEDURE Term(): BOOLEAN;
		VAR r: BOOLEAN;
	BEGIN
		r := Factor();
		WHILE sym = and DO
			OPSGet (sym);
			r := Factor() & r	(* !!! r & Factor() doesn't call Factor() if r is already FALSE *)
		END;
		RETURN r
	END Term;
	
BEGIN
	r := Term();
	WHILE sym = or DO
		OPSGet (sym);
		r := Term() OR r	(* !!! r OR Term() doesn't call Term() if r is already TRUE *)
	END;
	RETURN r
	END Expression;
	
BEGIN
	OPSGet(sym);
	IF skipping THEN RETURN END;
	IF (sym = undef) THEN
		OPSGet(sym); body := TRUE;	(* if an elsif/else is found, it's the end of a "TRUE" section and should skip to the end *)
		IF sym = if THEN
			OPSGet(sym);
			IF Expression() THEN
				CheckTHEN; get(sym); INC(ifdepth); RETURN
			ELSE
				Skip
			END;
			body := FALSE
		END;
		WHILE sym = elsif DO
			OPSGet(sym);
			IF ~body & Expression() THEN
				CheckTHEN; get(sym); INC(ifdepth); RETURN
			END;
			Skip
		END;
		IF sym = else THEN
			IF body THEN 
			Skip ELSE get(sym); INC(ifdepth); RETURN END
		END;
		IF sym = end THEN 
			IF body THEN DEC(ifdepth) END;
			get(sym)
		ELSE
			err (OPM.errpos, "$END expected")
		END
	END
END get;

PROCEDURE InitPreprocessor;
BEGIN
	OPS.Get := NIL; OPS.Init; skipping := FALSE;
	OPSGet := OPS.Get;
	OPS.Get := get
END InitPreprocessor;

(* ---------------- hierarchy calculation -------------- *)

PROCEDURE MatchSym(s: INTEGER): BOOLEAN;
BEGIN
	IF s = sym THEN
		OPS.Get(sym); RETURN TRUE
	ELSE RETURN FALSE END;
END MatchSym;

PROCEDURE GetOptions(VAR S: Attributes.Scanner; VAR opts: ARRAY OF CHAR);
	VAR i: LONGINT;
BEGIN
	i := 0;
	IF (S.class = Attributes.Char) & (S.c = Oberon.OptionChar) THEN
		WHILE (i<LEN(opts)) & (Strings.IsAlpha(S.nextCh) OR Strings.IsDigit(S.nextCh) OR (S.nextCh = ".")) DO
			opts[i] := S.nextCh; Attributes.Read(S.R, S.nextCh); INC(i)
		END;
		Attributes.Scan(S)
	END;
	opts[i] := 0X
END GetOptions;

PROCEDURE Import(VAR T: Tree; M: Mod);
VAR modname: ARRAY 64 OF CHAR; m: Mod; r: Ref;
BEGIN
	IF sym = ident THEN (* ident *)
		COPY(OPS.name, modname); OPS.Get(sym);
		IF sym = becomes THEN (* := *)
			OPS.Get(sym);
			IF sym = ident THEN
				COPY(OPS.name, modname); OPS.Get(sym);
			END;
		END;
		IF modname # "SYSTEM" THEN
			m := T.list; (* find module in list *)
			WHILE (m # NIL) & (m.name # modname) DO m := m.next END;
			IF m = NIL THEN (* module not found in list *)
				NEW(m); COPY(modname, m.name); m.next := T.list; T.list := m; (* insert in list *)
			END;	
			r := M.impl;
			WHILE (r # NIL) & (r.mod # m) DO r := r.next END;
			IF r = NIL THEN
				NEW(r); r.mod := m; r.next := M.impl; M.impl := r; INC(m.ref);
			END;
		END;
	END;
END Import;

PROCEDURE ImportList(VAR T: Tree; M: Mod);
BEGIN
	LOOP Import(T, M);
		IF sym = semicolon THEN EXIT END; (* ; *)
		IF sym # comma THEN EXIT ELSE OPS.Get(sym) END; (* , *)
	END;
END ImportList;	

PROCEDURE AddModule*(VAR T: Tree; s: ARRAY OF CHAR; opts: ARRAY OF CHAR);
VAR M, m: Mod; t: Texts.Text; R: Texts.Reader;
BEGIN
	NEW(M); COPY(s, M.fname);  COPY(opts, M.opts);
	NEW(t); Texts.Open(t, s);
	IF t.len = 0 THEN Texts.WriteString(W, s); Texts.WriteString(W, " not found"); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf);
	ELSE
		Texts.OpenReader(R, t, 0); OPM.Init({}, R, Oberon.Log); (* << win *)
		InitPreprocessor; OPS.Get(sym);	(* <- preproc *)
		IF MatchSym(module) THEN (* module *)
			IF sym = ident THEN (* ident *)
				COPY(OPS.name, M.name);
				OPS.Get(sym);
				IF MatchSym(semicolon) & MatchSym(import) THEN (* ; IMPORT *)
					m := T.list;
					WHILE (m # NIL) & (m.name # M.name) DO m := m.next END;
					IF m = NIL THEN (* not in there already *)
						ImportList(T, M); M.next := T.list; T.list := M;
					ELSE
						IF m.fname[0] = 0X THEN (* already in list but has no file name *)
							M := m; COPY(s, M.fname); COPY(opts, M.opts); ImportList(T, M);
						END;
					END;
					error := FALSE; RETURN
				ELSE
					m := T.list;
					WHILE (m # NIL) & (m.name # M.name) DO m := m.next END;
					IF m = NIL THEN (* not in there already *)
						M.next := T.list; T.list := M
					ELSE
						IF m.fname[0] = 0X THEN (* already in list but has no file name *)
							M := m; COPY(s, M.fname); COPY(opts, M.opts); (* ImportList(T, M); *)
						END
					END;
					error := FALSE; RETURN
					(*
					Texts.WriteString(W, s); Texts.WriteString(W, " IMPORT expected"); Texts.WriteLn(W);
					Texts.Append(Oberon.Log, W.buf);
					*)
				END;
			ELSE
				Texts.WriteString(W, s); Texts.WriteString(W, " identifier expected"); Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf);
			END;
		ELSE
			Texts.WriteString(W, s); Texts.WriteString(W, " MODULE expected"); Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf);
		END
	END;
	error := TRUE
END AddModule;

PROCEDURE Mark(VAR T: Tree; m: Mod; layer: INTEGER);
VAR r: Ref; m0: Mod;
BEGIN
	IF layer > m.layer THEN
		IF layer > T.maxlayer THEN T.maxlayer := layer END;
		m.layer := layer;
		m0 := T.list;
		WHILE m0 # NIL DO
			r := m0.impl;
			WHILE r # NIL DO
				IF r.mod = m THEN Mark(T, m0, layer+1) END;
				r := r.next
			END;
			m0 := m0.next
		END
	END
END Mark;

PROCEDURE Hierarchy*(VAR T: Tree);
VAR m, m0, clist: Mod; r: Ref;
BEGIN
	(* calculate layers *)
	T.maxlayer := 0;
	m := T.list;
	WHILE m # NIL DO
		IF m.fname[0] # 0X THEN Mark(T, m, 1) END;
		m := m.next;
	END;
	(* process *)
	clist := NIL;
	LOOP
		m := T.list; m0 := NIL;
		WHILE (m # NIL) & (m.ref # 0) DO m0 := m; m := m.next END;
		IF m = NIL THEN
			IF T.list # NIL THEN
				Texts.WriteString(W, "inconsistant import hierarchy"); Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf);
			ELSE
				EXIT
			END;
		ELSE (* m is a module to be compiled *)
			(* remove m *)
			IF T.list = m THEN (* first in list *) T.list := m.next;
			ELSE m0.next := m.next;
			END;
			(* put in compile list *)
			m.next := clist; clist := m;
			r := m.impl; WHILE r # NIL DO DEC(r.mod.ref); r := r.next END; (* decrement references *)
		END;
	END;
	T.list := clist;
END Hierarchy;

PROCEDURE Append(VAR list: Display.Frame; f: Display.Frame);
BEGIN
	IF list = NIL THEN
		list := f; f.slink := NIL;
	ELSE
		f.slink := list; list := f;
	END;
END Append;

PROCEDURE InsertHierarchy*;
VAR S: Attributes.Scanner; m: Mod; T: Tree; list: Display.Frame; F: Icons.Icon; x, y, layer: INTEGER; obj: Objects.Object;
	A: Objects.AttrMsg; opts, s: ARRAY 32 OF CHAR;
BEGIN
	T.list := NIL;
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	WHILE S.class = Attributes.Name DO
		COPY(S.s, s);
		Attributes.Scan(S); GetOptions(S, opts); AddModule(T, s, opts);
	END;
	Hierarchy(T);
	IF T.list # NIL THEN
		layer := 1; x := 0; y := 0; list := NIL;
		WHILE layer <= T.maxlayer DO
			m := T.list;
			WHILE m # NIL DO
				IF (m.fname[0] # 0X) & (m.layer = layer) THEN
					obj := Gadgets.FindPublicObj("Icons.Object");
					NEW(F); Icons.MakeIcon(F, m.fname, Icons.ViewOf(obj(Gadgets.Frame))); F.X := x; F.Y := y;
					A.id := Objects.set; A.name := "Cmd"; A.class := Objects.String;
					A.s := "Desktops.OpenDoc '#Caption '"; A.res := -1;
					F.handle(F, A);
					Append(list, F); INC(x, F.W);
				END;
				m := m.next;
			END;
			INC(layer); INC(y, 60); x := 0;
		END;
		Gadgets.Integrate(list);
	END;
END InsertHierarchy;

PROCEDURE Compile*;
VAR S: Attributes.Scanner; T: Tree; m: Mod; s, opts, options: ARRAY 64 OF CHAR; i, line: INTEGER; S1: Texts.Scanner;
	fbeg, fend, ftime: LONGINT; text, ftext: Texts.Text; par: Display.Frame; R: Texts.Reader;

	PROCEDURE Locate(F: Display.Frame;  T: Texts.Text;  pos: LONGINT);
	VAR M: Oberon.CaretMsg;  N: Oberon.ControlMsg;
	BEGIN
		IF pos < 0 THEN pos := 0
		ELSIF pos > T.len THEN pos := T.len
		END;
           N.F := NIL; N.id := Oberon.neutralize; Display.Broadcast(N);
           Oberon.FadeCursor(Oberon.Pointer);
		M.id := Oberon.set; M.F := F; M.car := F; M.text := T; M.pos := pos; Display.Broadcast(M)
	END Locate;
		
BEGIN
	Texts.WriteString(W, "Builder.Compile ");
	T.list := NIL; options := "";
	ResetFlags;	(* <- preproc *)
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	WHILE (S.class = Attributes.Char) & (S.c = Oberon.OptionChar) DO
		IF S.nextCh = "D" THEN
			Attributes.Scan(S);	(* Skip D *)
			Attributes.Scan(S);	(* Skip = *)
			Attributes.Scan(S);
			InsertFlag(S.s);
			Texts.WriteString(W, " \D="); Texts.WriteString(W, S.s);
			Attributes.Scan(S)
		ELSE
			GetOptions(S, options);
			Texts.WriteString(W, " \"); Texts.WriteString(W, options); 
		END
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	IF (S.class = Attributes.Char) & (S.c = "*") THEN
		text := GetText(par);
		IF text # NIL THEN
			RemoveErrors(text);
			InitPreprocessor;	(* <- preproc *)
			Texts.OpenReader(R, text, 0);
			i := 0; WHILE (options[i] # 0X) & (options[i] # ".") & (options[i] # "f") DO INC(i) END;
			IF options[i] = "f" THEN
				OPM.breakpos := 0;
				Oberon.GetSelection(ftext, fbeg, fend, ftime);
				IF ftime >= 0 THEN
					Texts.OpenScanner(S1, ftext, fbeg); Texts.Scan(S1); line := S1.line;
					WHILE ~S1.eot & (S1.class # Texts.Int) & (S1.line = line) DO Texts.Scan(S1) END;
					IF S1.class = Texts.Int THEN
						Compiler.Module(R, options, S1.i, Oberon.Log, error); Locate(par, text, OPM.breakpos); RETURN
					END
				END;
				Texts.WriteString(W, "  pc not selected"); Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf);
				RETURN
			ELSE
				fbeg := Oberon.Log.len;
				Compiler.Module(R, options, MAX(LONGINT), Oberon.Log, error);
				IF error & autoMark THEN
					Texts.OpenScanner(S1, Oberon.Log, fbeg); Texts.Scan(S1);
					markErrors(S1, text, par)
				END
			END
		ELSE Texts.WriteString(W, " text not found"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	ELSE
		error := FALSE;
		WHILE ~S.eot & ~error & (S.class = Attributes.Name) DO
			COPY(S.s, s); Attributes.Scan(S); GetOptions(S, opts);
			AddModule(T, s, opts)
		END;
		IF ~error THEN
			Hierarchy(T);
			m := T.list;
			WHILE (m # NIL) & ~error DO
				IF m.fname[0] # 0X THEN
					NEW(text); Texts.Open(text, m.fname);
					Texts.OpenReader(R, text, 0);
					InitPreprocessor;
					COPY(options, opts); Strings.Append(opts, m.opts);
					Compiler.Module(R, opts, MAX(LONGINT), Oberon.Log, error);
				END;
				m := m.next
			END
		END
	END;
	OPS.Get := NIL	(*remove preprocessor*)
END Compile;

PROCEDURE Free*;
VAR S: Attributes.Scanner; T: Tree;

	PROCEDURE F(mod: Mod);
	BEGIN
		IF mod.next # NIL THEN F(mod.next) END;
		IF (mod.fname[0] # 0X) & (mod.name[0] # 0X) THEN
			Texts.WriteString(W, mod.name); Texts.WriteString(W, " unloading");
			Modules.Free(mod.name, FALSE); 
			IF Modules.res # 0 THEN Texts.WriteString(W, " failed") END;
			Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END;
	END F;
	
BEGIN
	Texts.WriteString(W, "Builder.Free"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	T.list := NIL;
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	WHILE ~S.eot & (S.class = Attributes.Name) DO
		AddModule(T, S.s, ""); Attributes.Scan(S);
	END;
	
	Hierarchy(T);
	IF T.list # NIL THEN F(T.list) END
END Free;

PROCEDURE Init();
	VAR S: Texts.Scanner;
BEGIN
	first := TRUE;
	Oberon.OpenScanner(S, "Builder.AutoMark");
	IF S.class IN {Texts.Name, Texts.String} THEN
		Strings.StrToBool(S.s, autoMark)
	ELSE
		autoMark := TRUE
	END
END Init;

BEGIN
	Texts.OpenWriter(W); Init()
END Builder.

System.Free Builder ~

Builder.MarkErrors ^
Builder.NextError
Builder.ClearErrors
