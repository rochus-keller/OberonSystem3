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

MODULE WTS;	(** portable *)

IMPORT Files, Display, Objects, Texts, Oberon, TextGadgets, BIT;

CONST
	MaxStyles = 48;

VAR
	R*: Files.Rider;
	E: INTEGER;
	elem: ARRAY 32, 32 OF CHAR;
	W, X: Texts.Writer;
	L: Objects.Library;
	styleOk: BOOLEAN;
	styles: ARRAY MaxStyles OF TextGadgets.Style;
	nofStyles: INTEGER;

	PROCEDURE Msg(s: ARRAY OF CHAR; cr: BOOLEAN);
	BEGIN Texts.WriteString(X, s);
		IF cr THEN Texts.WriteLn(X) END;
		Texts.Append(Oberon.Log, X.buf)
	END Msg;

	PROCEDURE WriteText(VAR R: Files.Rider; lib: Objects.Library; col, voff: SHORTINT; len: LONGINT);
	VAR ch: CHAR;
	BEGIN Texts.SetFont(W, lib); Texts.SetColor(W, col); Texts.SetOffset(W, voff);
		WHILE len > 0 DO Files.Read(R, ch); Texts.Write(W, ch); DEC(len) END
	END WriteText;

	PROCEDURE Parc(VAR R: Files.Rider; n: INTEGER);
	VAR
		style: TextGadgets.Style;
		ref: INTEGER;
		i, tabs: LONGINT;
		opts: LONGINT;
		x: LONGINT;
	BEGIN
		IF L = NIL THEN NEW(L); Objects.OpenLibrary(L) END;
		style := TextGadgets.newStyle();
		Files.ReadNum(R, x); Files.ReadNum(R, x); Files.ReadNum(R, x); style.leftM := SHORT(x DIV Display.Unit);	(*?, first, left*)
		Files.ReadNum(R, x); style.width := SHORT(x DIV Display.Unit);	(*width*)
		Files.ReadNum(R, x (* style.gap *));	(*lead*)
		Files.ReadNum(R, x (*style.lsp*)); Files.ReadNum(R, x (*style.dsr*));	(*lsp, dsr*)
		Files.ReadNum(R, x); opts := x;	(*opts 0=grid, 1=left, 2=right, 3=break*)
		style.mode := {};
		(* IF BIT.BIT(opts, 0) THEN INCL(style.opts, 2) END;	(*grid*) *)
		IF BIT.BIT(opts, 1) THEN INCL(style.mode, TextGadgets.left) END;  (* left *)
		IF BIT.BIT(opts, 2) THEN INCL(style.mode, TextGadgets.right) END; (* right *)
		IF style.mode = {TextGadgets.left, TextGadgets.right} THEN style.mode := {TextGadgets.left, TextGadgets.pad} END;
		IF style.mode = {} THEN style.mode := {TextGadgets.middle} END;
		(* IF BIT.BIT(opts, 3) THEN INCL(style.opts, 3) END; (* break *) *)
		Files.ReadNum(R, tabs);	(*tabs*)
		style.noTabs := 0;
		WHILE (style.noTabs < tabs) & (style.noTabs < 32) DO
			Files.ReadNum(R, x); style.tab[style.noTabs] := SHORT(x DIV Display.Unit); INC(style.noTabs)
		END;
		i := 32;
		WHILE i < tabs DO Files.ReadNum(R, x); INC(i) END;
		styles[nofStyles] := style;
		(*
		i := 0; WHILE ~Styles.Similar(styles[i], style) DO INC(i) END;
		*) i := nofStyles;
		IF i = nofStyles THEN L.GenRef(L, ref); L.PutObj(L, ref, style);	(*into library*)
			IF nofStyles < MaxStyles-1 THEN INC(nofStyles) END;
		ELSE ref := styles[i].ref
		END;
		IF ref > 255 THEN Msg("too many styles, sorry...", TRUE); HALT(44) END;
		Texts.SetFont(W, L); Texts.Write(W, CHR(ref))
	END Parc;

	PROCEDURE PutObj(F: Display.Frame; w, h: INTEGER);
		VAR ref: INTEGER; M: Display.ModifyMsg;
	BEGIN
		IF (F.W # w) OR (F.H # h) THEN
			M.id := Display.extend; M.mode := Display.state;
			M.W := w; M.H := h; M.dW := F.W-w; M.dH := F.H-h; M.dlink := NIL;
			M.X := 0; M.Y := 0; M.dX := 0; M.dY := 0; M.F := F; M.x := 0; M.y := 0; Objects.Stamp(M); F.handle(F, M)
		END;
		IF L = NIL THEN NEW(L); Objects.OpenLibrary(L) END;
		L.GenRef(L, ref); L.PutObj(L, ref, F);	(*into library*)
		IF ref > 255 THEN Msg("too many styles, sorry...", TRUE); HALT(44) END;
		Texts.SetFont(W, L); Texts.Write(W, CHR(ref))
	END PutObj;

	PROCEDURE Elem(VAR R, S: Files.Rider; n: LONGINT);
	VAR w, h, pos: LONGINT;
		ch: CHAR;
		proc, cmd: ARRAY 32 OF CHAR; res: INTEGER;
	BEGIN Files.ReadLInt(R, w); Files.ReadLInt(R, h); Files.Read(R, ch);
		IF ORD(ch) = E THEN 
			Files.ReadString(R, elem[E]); Files.ReadString(R, proc); Msg("   ", FALSE); Msg(elem[E], TRUE);
			INC(E)
		END;
		IF (elem[ORD(ch)] = "ParcElems") & styleOk THEN Parc(R, ORD(ch))
		ELSIF (elem[ORD(ch)] = "StyleElems") & styleOk THEN Parc(R, ORD(ch)); Files.ReadString(R, proc);	(*name*)
		ELSIF (elem[ORD(ch)] = "FoldElems") & styleOk THEN 
			pos := Files.Pos(R);
			Objects.NewObj := NIL; cmd := "WTSFold.New"; Oberon.Call(cmd, Oberon.Par, FALSE, res);
			IF (Objects.NewObj # NIL) & (Objects.NewObj IS Display.Frame) THEN
				PutObj(Objects.NewObj(Display.Frame), SHORT(w DIV Display.Unit), SHORT(h DIV Display.Unit))
			END;
			Files.Set(R, Files.Base(R), pos+n)
		ELSIF (elem[ORD(ch)] = "StampElems") & styleOk THEN 
			pos := Files.Pos(R);
			Objects.NewObj := NIL; cmd := "WTSStamp.New"; Oberon.Call(cmd, Oberon.Par, FALSE, res);
			IF (Objects.NewObj # NIL) & (Objects.NewObj IS Display.Frame) THEN
				PutObj(Objects.NewObj(Display.Frame), SHORT(w DIV Display.Unit), SHORT(h DIV Display.Unit))
			END;
			Files.Set(R, Files.Base(R), pos+n)
		ELSIF (elem[ORD(ch)] = "PictElems") & styleOk THEN pos := Files.Pos(R);
			Objects.NewObj := NIL; cmd := "WTSPict.New"; Oberon.Call(cmd, Oberon.Par, FALSE, res);
			IF (Objects.NewObj # NIL) & (Objects.NewObj IS Display.Frame) THEN
				PutObj(Objects.NewObj(Display.Frame), SHORT(w DIV Display.Unit), SHORT(h DIV Display.Unit))
			END;
			Files.Set(R, Files.Base(R), pos+n)
		ELSIF (elem[ORD(ch)] = "GraphicElems") & styleOk THEN pos := Files.Pos(R);
			Objects.NewObj := NIL; cmd := "WTSDraw.New"; Oberon.Call(cmd, Oberon.Par, FALSE, res);
			IF (Objects.NewObj # NIL) & (Objects.NewObj IS Display.Frame) THEN
				PutObj(Objects.NewObj(Display.Frame), SHORT(w DIV Display.Unit), SHORT(h DIV Display.Unit))
			END;
			Files.Set(R, Files.Base(R), pos+n)
		ELSE Files.Set(R, Files.Base(R), Files.Pos(R)+n)
		END;
		Files.Read(S, ch)	(*skip elem char*)
	END Elem;

	PROCEDURE Conv(VAR R: Files.Rider; VAR T: Texts.Text);
	VAR
		hlen, len: LONGINT;
		N, lib, col, voff: SHORTINT;
		LName: ARRAY 32, 32 OF CHAR;
		S: Files.Rider;
	BEGIN	(*type read 01 F0*)
		Files.ReadLInt(R, hlen);
		Files.Set(S, Files.Base(R), hlen);
		N := 1; E := 1; L := NIL; nofStyles := 0;	(*reset globals*)
		WHILE Files.Pos(R) < hlen - 5 DO
			Files.Read(R, lib);
			IF lib = N THEN Files.ReadString(R, LName[N]); INC(N) END;
			Files.Read(R, col); Files.Read(R, voff); Files.ReadLInt(R, len);
			IF len < 0 THEN Elem(R, S, -len)
			ELSE WriteText(S, Objects.ThisLibrary(LName[lib]), col, voff, len)
			END
		END;
		NEW(T); Texts.Open(T, ""); Texts.Append(T, W.buf)
	END Conv;

	PROCEDURE Backup(name: ARRAY OF CHAR);
	VAR bak: ARRAY 32 OF CHAR; i, res: INTEGER;
	BEGIN i := 0;
		WHILE name[i] # 0X DO bak[i] := name[i]; INC(i) END;
		bak[i] := "."; bak[i+1] := "B"; bak[i+2] := "a"; bak[i+3] := "k"; bak[i+4] := 0X;
		Files.Rename(name, bak, res)
	END Backup;

	PROCEDURE Convert*;
	VAR
		F: Files.File; len: LONGINT;
		S: Texts.Scanner; T: Texts.Text;
		name: ARRAY 32 OF CHAR; x, y: CHAR;
		bak: BOOLEAN;
		i: INTEGER;
	BEGIN
		styleOk := FALSE; bak := FALSE;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		WHILE S.class = Texts.Name DO
			COPY(S.s, name); Texts.Scan(S); styleOk := FALSE;
			IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) THEN Texts.Scan(S);
				IF S.class = Texts.Name THEN
					i := 0;
					WHILE i < S.len DO
						IF S.s[i] =  "s" THEN styleOk := TRUE
						ELSIF S.s[i] =  "b" THEN bak := TRUE
						END;
						INC(i)
					END
				END
			END;
			F := Files.Old(name);
			IF F # NIL THEN
				Files.Set(R, F, 0); Files.Read(R, x); Files.Read(R, y);
				IF ((x = 1X) & (y = 0F0X)) OR ((y = 1X) & (x = 0F0X)) THEN Msg("Converting ", FALSE); Msg(name, TRUE);
					F := Files.New(name); Conv(R, T); Texts.Store(T, F, 0, len);
					IF bak THEN Backup(name) END;
					Files.Register(F)
				ELSE Msg("not a text file ", FALSE); Msg(name, TRUE);
				END
			END;
			Texts.Scan(S)
		END
	END Convert;

BEGIN Texts.OpenWriter(W); Texts.OpenWriter(X)
END WTS.
WTS.Convert Modula.Text\s ~

Debug.Off WTS~
WTS.Scan OberonReport.Text ParcElems ~
Util.Dump  Inter.Text \2000~
---------------------------------


Auf Ganymed befindet sich ein Tool zur Konversion von Writedokumenten
nach Scripts. Alle Elems werden entfernt, Fonts bleiben erhalten.
Die eigentliche "Gag" ist aber die Möglichkeit der Abbildung von Parcs in
Styles, d.h. der Übernahme von Formatmerkmalen in das entsprechende
Scriptsdokument.
Das Original erhält die Extension "*.Bak".

Net.ReceiveFiles Ganymed WTS.Obj Scripts.Obj ScriptFrames.Obj ~

Zum Ausprobieren: Net.ReceiveFiles Pluto OberonReport.Text ~

WTS.Convert OberonReport.Text ~		konvertiert Text (entfernt Elems)
WTS.Convert Cat.Appl.Text/s ~			konvertiert zusätzlich Parcs nach Styles

WTS.Convert   Oberon2.Report.Text/s  ~

System.CopyFiles \wino\Oberon2.Report.Text => x.Text ~
System.CopyFiles \wino\Draw.Text => x.Text ~
WTS.Convert Yellow.CLi.Text/s ~
WTS.Convert  x.Text/s

System.Free WTSFold WTSPict WTSStamp WTSDraw WTS ~

System.CopyFiles \wino\Folds.Mod => x.Text ~
WTS.Convert x.Text/s ~
Hex.Open ^
WTSFold.Mod

Compiler.Compile WTS.Mod WTSFold.Mod WTSPict.Mod WTSStamp.Mod WTSDraw.Mod ~