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

MODULE EditKeys;	(** portable *)	(* CAS/MH 27 Jan 93 / jm 2.5.95 *)
	IMPORT
		Objects, Oberon, Input, Fonts, Display, Texts, Documents, 
		TextGadgets0, TextGadgets, TextDocs, Desktops;

	CONST
		IdentLen = 32; DefaultFile = "EditKeys.Text"; DefaultMacro = "OTHERWISE"; InstallMacro = "INSTALL";
		(*scanner symbols*)
			cmdSym = 0; nameSym = 1; stretchSym = 2; lparen = 3; rparen = 4; bslash = 5; eof = 6;
		(*built-in commands*)
			(*w/ param*)
			writeCmd = "0"; charCmd = "1"; fntCmd = "2"; voffCmd = "3"; callCmd = "4";
			argCmd = "A"; execCmd = "B"; paramCmd = "C";
			(*w/o param*)
			keepCmd = "5"; pickCmd = "6"; caretCmd = "7"; indentCmd = "8"; freezeCmd = "9";
		(*preset.set*)
			fntPreset = 0; pickPreset = 1; voffPreset = 2; caretPreset = 3; freezePreset = 4;

	TYPE
		Ident = ARRAY IdentLen OF CHAR;

		Definition = POINTER TO DefinitionDesc;
		Sequence = POINTER TO SequenceDesc;

		DefinitionDesc = RECORD
			left, right: Definition;
			in: BOOLEAN;
			trig: Ident;
			seq: Sequence
		END;
		SequenceDesc = RECORD
			next: Sequence;
			sym: INTEGER;
			cmd: CHAR;
			def: Definition;
			stretch: Texts.Buffer
		END;

	VAR
		defs, dmy: Definition;
		ch, cmd, hotKey: CHAR;
		sym, errs: INTEGER;
		errpos: LONGINT;
		name, trig: Ident;
		stretch, buf, indent: Texts.Buffer;
		T: Texts.Text;
		R: Texts.Reader;
		W, WB, WL: Texts.Writer;	(*out, compose, host editor*)
		map: ARRAY 17 OF CHAR;
		preset: RECORD
			set: SET;
			pos, caret: LONGINT;
			frame: TextGadgets.Frame;
			def, fnt: Fonts.Font;
			voff: SHORTINT
		END;

	PROCEDURE OpenText(title: ARRAY OF CHAR; T: Texts.Text; systemtrack: BOOLEAN);
	VAR D: Documents.Document; f: TextGadgets.Frame;
	BEGIN
		NEW(D); TextDocs.InitDoc(D); (* make document wrapper *)
				
		NEW(f); TextGadgets.Init(f, T, FALSE);	(* create content *)
		Documents.Init(D, f); (* and merge together *)
		COPY(title, D.name);
		IF systemtrack THEN D.W := Display.Width DIV 8 * 3 - 20 ELSE D.W := Display.Width DIV 8 * 3 + 20 END;
		Desktops.ShowDoc(D)
	END OpenText;

	PROCEDURE Flip (VAR src, dst: ARRAY OF CHAR);
		VAR i, j: INTEGER;
	BEGIN i := -1; j := 0;
		REPEAT INC(i) UNTIL src[i] = 0X;
		WHILE i > 0 DO DEC(i); dst[j] := src[i]; INC(j) END;
		dst[j] := 0X
	END Flip;

	PROCEDURE WLog;
	BEGIN Texts.Append(Oberon.Log, W.buf)
	END WLog;

	PROCEDURE Ch (ch: CHAR);
	BEGIN Texts.Write(W, ch)
	END Ch;

	PROCEDURE Str (s: ARRAY OF CHAR);
	BEGIN Texts.WriteString(W, s)
	END Str;

	PROCEDURE FlipStr (s: ARRAY OF CHAR);
		VAR n: Ident;
	BEGIN Flip(s, n); Str(n)
	END FlipStr;

	PROCEDURE Gap;
	BEGIN Str("  ")
	END Gap;

	PROCEDURE Ln;
	BEGIN Texts.WriteLn(W)
	END Ln;

	PROCEDURE Char (ch: CHAR);
		VAR pat: Display.Pattern; i, n, dx, x, y, w, h: INTEGER;
			d: ARRAY 3 OF CHAR;
	BEGIN Fonts.GetChar(W.lib(Fonts.Font), ch, dx, x, y, w, h, pat);
		IF h > 0 THEN Ch(ch); Str(" (* ") END;
		Ch("#"); i := 0; n := ORD(ch);
		REPEAT d[i] := map[n MOD 10]; n := n DIV 10; INC(i) UNTIL n = 0;
		WHILE i > 0 DO DEC(i); Ch(d[i]) END;
		IF h = 0 THEN Str(" (* ") ELSE Str(", ") END;
		Ch("0"); i := 0; n := ORD(ch);
		REPEAT d[i] := map[n MOD 16]; n := n DIV 16; INC(i) UNTIL n = 0;
		WHILE i > 0 DO DEC(i); Ch(d[i]) END;
		Str("X *)")
	END Char;

	PROCEDURE Append (SB, DB: Texts.Buffer);
	BEGIN Texts.Copy(SB, DB); Texts.OpenBuf(SB)
	END Append;


	(* table handler *)

	PROCEDURE Find (VAR name, trig: Ident; insert: BOOLEAN): Definition;
		VAR p, q, d, x: Definition; i: INTEGER;
	BEGIN Flip(name, trig); p := defs; d := p.right; q := NIL; x := NIL;
		WHILE d # NIL DO i := 0;
			WHILE (trig[i] # 0X) & (trig[i] = d.trig[i]) DO INC(i) END;
			IF trig[i] = d.trig[i] THEN x := d; d := NIL
			ELSIF trig[i] = 0X THEN q := d; d := NIL
			ELSIF trig[i] < d.trig[i] THEN p := d; d := d.left
			ELSE p := d; d := d.right
			END
		END;
		IF insert & (x = NIL) THEN NEW(x); x.right := q; x.in := FALSE; x.trig := trig;
			IF trig < p.trig THEN p.left := x ELSE p.right := x END;
			IF q # NIL THEN dmy.right := NIL; p := dmy;
				WHILE q.left # NIL DO
					WHILE (q.left # NIL) & (q.left.trig > trig) DO q := q.left END;
					WHILE (q.left # NIL) & (q.left.trig < trig) DO p.right := q.left; p := p.right; q.left := p.right; p.right := NIL END
				END;
				x.left := dmy.right
			END
		END;
		RETURN x
	END Find;

	PROCEDURE ResetDefs;
		VAR def: Definition; seq: Sequence;
	BEGIN defs.right := NIL; defs.trig[0] := 0X; hotKey := "\";
		name := DefaultMacro; def := Find(name, trig, TRUE);
		NEW(def.seq); seq := def.seq;
		seq.sym := cmdSym; seq.cmd := pickCmd;
		NEW(seq.next); seq := seq.next;
		Texts.OpenBuf(WB.buf); Texts.Write(WB, "\");
		seq.sym := stretchSym; seq.stretch := WB.buf;
		NEW(WB.buf); Texts.OpenBuf(WB.buf);
		NEW(seq.next); seq := seq.next;
		seq.sym := cmdSym; seq.cmd := writeCmd
	END ResetDefs;

	PROCEDURE Trigger (VAR trig: Ident): Definition;
		VAR d, x: Definition; i: INTEGER;
	BEGIN d := defs.right; x := NIL;
		WHILE d # NIL DO i := 0;
			WHILE (trig[i] # 0X) & (trig[i] = d.trig[i]) DO INC(i) END;
			IF trig[i] = d.trig[i] THEN RETURN d END;
			IF d.trig[i] = 0X THEN x := d END;
			IF trig[i] < d.trig[i] THEN d := d.left ELSE d := d.right END
		END;
		RETURN x
	END Trigger;


	(* macro compiler *)

	PROCEDURE Mark (err: ARRAY OF CHAR);
	BEGIN INC(errs);
		IF Texts.Pos(R) - errpos > 9 THEN
			errpos := Texts.Pos(R); Ln; Str("  pos  "); Texts.WriteInt(W, errpos, 0); Gap; Str(err); WLog
		END
	END Mark;

	PROCEDURE GetCh;
	BEGIN Texts.Read(R, ch);
		IF (R.lib # NIL) & ~(R.lib IS Fonts.Font) THEN ch := " " END;
	END GetCh;

	PROCEDURE CharCode;
		VAR c: INTEGER;
	BEGIN c := 0;
		WHILE ("0" <= ch) & (ch <= "9") DO c := c * 10 + SHORT(ORD(ch) - 30H); GetCh END;
		name[0] := CHR(c); name[1] := 0X	(*unchecked*)
	END CharCode;

	PROCEDURE Name;
		VAR i: INTEGER;
	BEGIN i := 0;
		REPEAT name[i] := ch; INC(i); GetCh
		UNTIL (ch <= " ") OR (ch = "(") OR (ch = ")") OR R.eot OR (i = IdentLen-1);
		IF ~((ch <= " ") OR (ch = "(") OR (ch = ")") OR R.eot) THEN Mark("name too long") END;
		name[i] := 0X
	END Name;

	PROCEDURE Save (text: Texts.Text; beg, end: LONGINT; buf: Texts.Buffer);
	BEGIN
		IF end > beg THEN Texts.Save(text, beg, end, buf) END
	END Save;

	PROCEDURE Stretch;
		VAR beg, end: LONGINT;
	BEGIN beg := Texts.Pos(R); end := beg; GetCh;
		WHILE ~R.eot & (ch # 22X) DO INC(end); GetCh END;
		IF ch = 22X THEN GetCh;
			IF end > beg THEN NEW(stretch); Texts.OpenBuf(stretch); Save(T, beg, end, stretch)
			ELSE Mark("empty stretch")
			END
		ELSE Mark("Closing quote expected")
		END
	END Stretch;

	PROCEDURE Comment;
	BEGIN
		LOOP
			IF ch = "(" THEN GetCh;
				IF ch = "*" THEN GetCh; Comment END
			ELSIF ch = "*" THEN GetCh;
				IF ch = ")" THEN GetCh; EXIT END
			ELSE GetCh
			END
		END
	END Comment;

	PROCEDURE GetSym;
	BEGIN sym := eof;
		REPEAT
			IF ch <= " " THEN GetCh
			ELSIF ch = 22X THEN sym := stretchSym; Stretch
			ELSIF ch = "#" THEN sym := nameSym; GetCh; CharCode
			ELSIF ch = "(" THEN GetCh; IF ch = "*" THEN GetCh; Comment ELSE sym := lparen END
			ELSIF ch = ")" THEN sym := rparen; GetCh
			ELSIF ch = "\" THEN sym := bslash; GetCh
			ELSIF ch = "^" THEN sym := cmdSym; GetCh; cmd := ch; GetCh
			ELSE sym := nameSym; Name
			END
		UNTIL (sym # eof) OR R.eot
	END GetSym;

	PROCEDURE ParseText;
		VAR def: Definition; beg, seq: Sequence;
	BEGIN GetSym;
		IF sym = bslash THEN
			GetSym; IF sym = nameSym THEN hotKey := name[0]; GetSym ELSE Mark("hot-key code expected") END
		END;
		WHILE sym = nameSym DO GetSym; def := Find(name, trig, TRUE);
			IF sym = lparen THEN
				GetSym; NEW(beg); seq := beg; beg.next := NIL;
				WHILE sym IN {cmdSym, nameSym, stretchSym} DO
					NEW(seq.next); seq := seq.next; seq.sym := sym;
					IF sym = cmdSym THEN seq.cmd := cmd
					ELSIF sym = nameSym THEN seq.def := Find(name, trig, FALSE);
						IF seq.def = NIL THEN Mark("illegal forward reference") END
					ELSE (*sym = stretchSym*) seq.stretch := stretch
					END;
					GetSym
				END;
				def.seq := beg.next; IF sym = rparen THEN GetSym ELSE Mark(") expected") END
			ELSE Mark("( expected")
			END
		END;
		IF sym # eof THEN GetSym;
			IF sym # eof THEN Mark("unexpected trailing char.s") END
		END;
		stretch := NIL
	END ParseText;

	PROCEDURE ReadText (name: ARRAY OF CHAR; beg: LONGINT);
	BEGIN Texts.OpenReader(R, T, beg); GetCh;
		IF ~R.eot THEN Str("EditKeys reading "); Str(name); WLog; errs := 0; errpos := -10; ParseText;
			IF errs = 0 THEN (*Str(" done")*) ELSE Str(" error"); ResetDefs END;
			Ln; WLog
		END
	END ReadText;


	(* macro processor *)

	PROCEDURE Insert (frame: TextGadgets.Frame; buf: Texts.Buffer);
		VAR pos, len: LONGINT;
	BEGIN pos := frame.carpos.pos; len := buf.len;
		Texts.Insert(frame.text, pos, buf); TextGadgets0.SetCaret(frame, pos + len)
	END Insert;

	PROCEDURE Delete (frame: TextGadgets.Frame; beg, end: LONGINT);
	BEGIN Texts.Delete(frame.text, beg, end); TextGadgets0.SetCaret(frame, beg)
	END Delete;

	PROCEDURE Err (def: Definition; s: ARRAY OF CHAR);
	BEGIN INC(errs); Gap; Str(s); Str(" in "); FlipStr(def.trig); Ln; WLog
	END Err;

	PROCEDURE PopArg (def: Definition; class: SHORTINT; VAR S: Texts.Scanner; VAR stack: Sequence);
		VAR B: Texts.Buffer;
	BEGIN
		IF stack # NIL THEN NEW(T); Texts.Open(T, "");
			NEW(B); Texts.OpenBuf(B); Texts.Copy(stack.stretch, B);
			Texts.Append(T, B); Texts.OpenScanner(S, T, 0); Texts.Scan(S); stack := stack.next;
			IF (class >= 0) & (S.class # class) THEN Err(def, "illegal param type") END
		ELSE Err(def, "missing param")
		END
	END PopArg;

	PROCEDURE PushArg (buf: Texts.Buffer; VAR stack: Sequence);
		VAR u: Sequence;
	BEGIN NEW(u); u.next := stack; stack := u; u.stretch := buf
	END PushArg;

	PROCEDURE ThisArg (n: LONGINT; args: Sequence): Sequence;
	BEGIN
		WHILE (n > 0) & (args # NIL) DO DEC(n); args := args.next END;
		RETURN args
	END ThisArg;

	PROCEDURE GetArguments (text: Texts.Text; pos: LONGINT; VAR pin: LONGINT; VAR args: Sequence);
		VAR B: Texts.Buffer; R: Texts.Reader; ch: CHAR;
	BEGIN pin := pos; DEC(pos); Texts.OpenReader(R, text, pos); Texts.Read(R, ch);
		IF ch = ":" THEN pin := pos;
			WHILE pos > 0 DO DEC(pos); Texts.OpenReader(R, text, pos); Texts.Read(R, ch); (*inv text[pos] = ch*)
				IF ch <= " " THEN
					NEW(B); Texts.OpenBuf(B); Save(text, pos + 1, pin, B); PushArg(B, args);
					pin := pos + 1; RETURN
				ELSIF ch = ":" THEN
					NEW(B); Texts.OpenBuf(B); Save(text, pos + 1, pin, B); PushArg(B, args);
					pin := pos
				ELSIF (ch = 22X) & (pos = pin - 1) THEN ch := 0X;
					WHILE (pos > 0) & (ch # 22X) DO DEC(pos); Texts.OpenReader(R, text, pos); Texts.Read(R, ch) END;
					IF ch = 22X THEN
						NEW(B); Texts.OpenBuf(B); Save(text, pos + 1, pin - 1, B); PushArg(B, args);
						pin := pos;
						DEC(pos); Texts.OpenReader(R, text, pos); Texts.Read(R, ch);
						IF ch = ":" THEN pin := pos END;
						IF ch <= " " THEN RETURN END
					ELSE RETURN
					END
				END
			END;
			NEW(B); Texts.OpenBuf(B); Save(text, pos, pin, B); PushArg(B, args);
			pin := pos
		END
	END GetArguments;

	PROCEDURE Expand (def: Definition; VAR stack, args, params: Sequence);
		VAR d: Definition; seq, u: Sequence; B: Texts.Buffer; S: Texts.Scanner; par: Oberon.ParList; res: INTEGER;
	BEGIN
		IF ~def.in THEN def.in := TRUE; seq := def.seq;
			WHILE (errs = 0) & (seq # NIL) DO
				IF seq.sym = cmdSym THEN
					IF seq.cmd = writeCmd THEN
						IF stack # NIL THEN Append(stack.stretch, buf); stack := stack.next
						ELSE Err(def, "missing param")
						END
					ELSIF seq.cmd = charCmd THEN PopArg(def, Texts.Int, S, stack);
						Texts.Write(WB, CHR(S.i)); Append(WB.buf, buf)
					ELSIF seq.cmd = fntCmd THEN PopArg(def, Texts.Name, S, stack);
						INCL(preset.set, fntPreset); preset.fnt := Fonts.This(S.s)
					ELSIF seq.cmd = voffCmd THEN PopArg(def, Texts.Int, S, stack);
						INCL(preset.set, voffPreset); preset.voff := SHORT(SHORT(S.i))
					ELSIF seq.cmd = callCmd THEN PopArg(def, Texts.Name, S, stack);
						IF errs = 0 THEN NEW(par); par.vwr := Oberon.MarkedViewer() (*Oberon.FocusViewer*); par.frame := par.vwr.dsc.next;
							IF params # NIL THEN
								NEW(par.text); Texts.Open(par.text, "");
								WHILE params # NIL DO Texts.Insert(par.text, 0, params.stretch);
									params := params.next
								END;
								NEW(B); Texts.OpenBuf(B);
								Texts.Save(T, Texts.Pos(S) - 1, T.len, B); Texts.Append(par.text, B);
								par.pos := 0
							ELSE par.text := T; par.pos := Texts.Pos(S)
							END;
							Oberon.Call(S.s, par, FALSE, res);
							IF res # 0 THEN Texts.WriteInt(W, res, 3); Err(def, "call error ") END
						END
					ELSIF seq.cmd = argCmd THEN PopArg(def, Texts.Int, S, stack);
						IF errs = 0 THEN u := ThisArg(S.i, args);
							IF u # NIL THEN NEW(B); Texts.OpenBuf(B); Texts.Copy(u.stretch, B); PushArg(B, stack)
							ELSE Err(def, "missing argument")
							END
						END
					ELSIF seq.cmd = execCmd THEN PopArg(def, Texts.Name, S, stack);
						IF errs = 0 THEN COPY(S.s, name); d := Find(name, trig, FALSE);
							IF d # NIL THEN Expand(d, stack, args, params)
							ELSE Err(def, "exec of undefined macro")
							END
						END
					ELSIF seq.cmd = paramCmd THEN
						IF stack # NIL THEN u := stack; stack := stack.next; u.next := params; params := u
						ELSE Err(def, "missing param")
						END
					ELSIF seq.cmd = keepCmd THEN INCL(preset.set, fntPreset); preset.fnt := preset.def
					ELSIF seq.cmd = pickCmd THEN INCL(preset.set, pickPreset)
					ELSIF seq.cmd = caretCmd THEN INCL(preset.set, caretPreset); preset.caret := buf.len
					ELSIF seq.cmd = indentCmd THEN
						IF indent.len > 0 THEN Texts.Copy(indent, buf) END
					ELSIF seq.cmd = freezeCmd THEN INCL(preset.set, freezePreset)
					ELSE Err(def, "illegal built-in")
					END
				ELSIF seq.sym = nameSym THEN Expand(seq.def, stack, args, params)
				ELSE (*seq.sym = stretchSym*)
					NEW(B); Texts.OpenBuf(B); Texts.Copy(seq.stretch, B); PushArg(B, stack)
				END;
				seq := seq.next
			END;
			def.in := FALSE
		ELSE Err(def, "cyclic expansion")
		END
	END Expand;

	PROCEDURE InitialExec (name: Ident);
		VAR def: Definition; stack, args, params: Sequence; trig: Ident;
	BEGIN def := Find(name, trig, FALSE);
		IF def # NIL THEN preset.set := {}; stack := NIL; args := NIL; params := NIL; errs := 0;
			Expand(def, stack, args, params);
			IF stack # NIL THEN Err(def, "superfluous param") END
		END
	END InitialExec;

	PROCEDURE Process (frame: TextGadgets.Frame; ch: CHAR; VAR del: LONGINT);
		VAR def: Definition; org, pos, i, tlen, pin: LONGINT; stack, args, params: Sequence; default: BOOLEAN;
			dmy: Texts.Reader;
	BEGIN errs := 0; del := 0; Texts.OpenBuf(buf); org := frame.carpos.pos;
		pos := org - (IdentLen-1);
		IF pos >= 0 THEN i := IdentLen-1 ELSE pos := 0; i := org END;
		trig[i] := 0X; Texts.OpenReader(R, frame.text, pos);
		WHILE i > 0 DO DEC(i); Texts.Read(R, trig[i]) END;
		def := Trigger(trig);
		IF def # NIL THEN default := FALSE; tlen := 0;
			WHILE def.trig[tlen] # 0X DO INC(tlen) END
		ELSE default := TRUE; name := DefaultMacro; def := Find(name, trig, FALSE); tlen := 0
		END;
		IF def # NIL THEN preset.set := {}; stack := NIL; args := NIL; params := NIL;
			GetArguments(frame.text, org - tlen, pin, args);
			Texts.OpenReader(dmy, frame.text, 0);
			Expand(def, stack, args, params);
			IF stack # NIL THEN Err(def, "superfluous param") END;
			IF errs = 0 THEN
				IF ~default THEN del := org - pin END;
				preset.frame := frame; preset.pos := frame.carpos.pos - del;
				IF caretPreset IN preset.set THEN INC(preset.pos, preset.caret) ELSE INC(preset.pos, buf.len) END
			END
		END
	END Process;


	(* editor interface *)

	PROCEDURE Key (frame: TextGadgets.Frame; ch: CHAR; VAR handled: BOOLEAN);
		CONST TAB = 9X; LF = 0AX; CR = 0DX; DEL = 7FX;
		VAR del, pos, beg: LONGINT; voff: SHORTINT; fnt: Fonts.Font; ch1: CHAR;
	BEGIN handled := TRUE; pos := frame.carpos.pos;
		IF frame.text.len > 0 THEN
			IF pos < frame.text.len THEN Texts.OpenReader(R, frame.text, pos); Texts.Read(R, ch1) END;
			IF (pos > 0) & ((pos = frame.text.len) OR (ch1 <= " ")) THEN
				Texts.OpenReader(R, frame.text, pos - 1); Texts.Read(R, ch1)
			END;
			IF (R.lib # NIL) & (R.lib IS Fonts.Font) THEN
				preset.def := R.lib(Fonts.Font)
			ELSE
				preset.def := Fonts.Default
			END;
			Texts.SetColor(WL, R.col);
			IF (ch = CR) OR (ch = TAB) OR (ch = LF) THEN Texts.SetOffset(WL, Oberon.CurOff)
			ELSE Texts.SetOffset(WL, R.voff)
			END
		ELSE preset.def :=  Oberon.CurFnt; Texts.SetColor(WL, Oberon.CurCol); Texts.SetOffset(WL, Oberon.CurOff)
		END;
		fnt := preset.def; voff := WL.voff;
		IF (preset.frame = frame) & (preset.pos = pos) THEN
			IF fntPreset IN preset.set THEN fnt := preset.fnt END;
			IF voffPreset IN preset.set THEN voff := preset.voff END
		END;
		preset.set := {}; preset.frame := NIL;
		IF (WL.lib # NIL) & (WL.lib IS Fonts.Font) & (WL.lib(Fonts.Font) # fnt) THEN Texts.SetFont(WL, fnt) END;
		IF WL.voff # voff THEN Texts.SetOffset(WL, voff) END;
		IF ch = hotKey THEN beg := frame.carpos.org; Texts.OpenReader(R, frame.text, beg); Texts.Read(R, ch1);
			WHILE (Texts.Pos(R) <= pos) & (ch1 <= " ") DO Texts.Read(R, ch1) END;
			Texts.OpenBuf(indent); Save(frame.text, beg, Texts.Pos(R) - 1, indent);
			Process(frame, ch, del);
			IF ~(freezePreset IN preset.set) & (errs = 0) THEN
				IF frame.car & (frame.carpos.pos # pos) THEN preset.pos := frame.carpos.pos - del END;
				TextGadgets0.SetCaret(frame, pos);
				IF del > 0 THEN Delete(frame, pos - del, pos) END;
				IF pickPreset IN preset.set THEN NEW(T); Texts.Open(T, "");
					Texts.Append(T, buf); Texts.ChangeLooks(T, 0, T.len, {0}, preset.def, 0, 0);
					Save(T, 0, T.len, buf)
				END;
				Insert(frame, buf)
			ELSE TextGadgets0.RemoveCaret(frame); preset.pos := frame.carpos.pos
			END;
			IF (0 <= preset.pos) & (preset.pos <= frame.text.len) THEN
				TextGadgets0.SetCaret(frame, preset.pos)
			END
		ELSIF (ch >= " ") & (ch # DEL) & (ch < 95X) OR (ch = 9BX) OR (ch = 9FX) THEN Texts.Write(WL, ch)
		ELSE handled := FALSE
		END;
		IF (WL.buf.len > 0) & frame.car THEN Insert(frame, WL.buf) END
	END Key;

	PROCEDURE Handle* (F: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR frame: TextGadgets.Frame; handled: BOOLEAN;
	BEGIN
		IF msg IS Oberon.InputMsg THEN
			WITH msg: Oberon.InputMsg DO frame := F(TextGadgets.Frame);
				IF (msg.id = Oberon.consume) & frame.car THEN
					Key(frame, msg.ch, handled);
					IF handled THEN msg.res := 0 END
				ELSIF (msg.id = Oberon.track) & (msg.keys # {}) THEN preset.set := {}
				END
			END
		END;
	END Handle;


	(* commands *)
	
	PROCEDURE Reset*;
	BEGIN ResetDefs
	END Reset;

	PROCEDURE Read*;
		VAR S: Texts.Scanner; text: Texts.Text; beg, end, time: LONGINT;
	BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "@") & (S.line = 0) THEN
			Oberon.GetSelection(text, beg, end, time);
			IF time > 0 THEN T := text; ReadText(" @ ", beg) END
		ELSIF (S.class = Texts.Char) & (S.c = ":") & (S.nextCh = "=") & (S.line = 0) THEN Texts.Scan(S);
			T := Oberon.Par.text; ReadText(" := ", Texts.Pos(S) - 1)
		ELSE
			IF (S.class = Texts.Char) & (S.c = "^") & (S.line = 0) THEN
				Oberon.GetSelection(text, beg, end, time);
				IF time > 0 THEN Texts.OpenScanner(S, text, beg); Texts.Scan(S) END
			END;
			WHILE S.class = Texts.Name DO NEW(T); Texts.Open(T, S.s); ReadText(S.s, 0); Texts.Scan(S) END
		END;
		T := NIL
	END Read;

	PROCEDURE Definitions*;
		VAR S: Texts.Scanner; T, text: Texts.Text; tree: Definition;
			beg, end, time: LONGINT;

		PROCEDURE Sort(VAR d: Definition; VAR pat: ARRAY OF CHAR; VAR tree: Definition);
			VAR i: INTEGER; t: Definition; n: Ident;

			PROCEDURE Ins(VAR tree: Definition; t: Definition; VAR n: Ident);
				VAR m: Ident;
			BEGIN
				IF tree = NIL THEN tree := t
				ELSE Flip(tree.trig, m);
					IF n < m THEN Ins(tree.left, t, n) ELSE Ins(tree.right, t, n) END
				END
			END Ins;
		BEGIN
			IF d # NIL THEN Flip(d.trig, n); i := 0;
				WHILE (pat[i] # 0X) & (n[i] = pat[i]) DO INC(i) END;
				IF pat[i] = 0X THEN NEW(t); t^ := d^; t.left := NIL; t.right := NIL; Ins(tree, t, n) END;
				Sort(d.left, pat, tree); Sort(d.right, pat, tree)
			END
		END Sort;

		PROCEDURE Write(tree: Definition);
			PROCEDURE Seq(seq: Sequence);
				VAR b: Texts.Buffer;
			BEGIN
				WHILE seq # NIL DO
					IF seq.sym = cmdSym THEN Ch("^"); Ch(seq.cmd)
					ELSIF seq.sym = nameSym THEN
						IF (name[1] = 0X) & ((name[0] < " ") OR (name[0] > 7EX)) THEN Char(name[0])
						ELSE FlipStr(seq.def.trig)
						END
					ELSE (*seq.sym = stretchSym*) Ch(22X); Append(W.buf, buf);
						NEW(b); Texts.OpenBuf(b); Texts.Copy(seq.stretch, b); Append(b, buf); Ch(22X)
					END;
					seq := seq.next; IF seq # NIL THEN Ch(" ") END
				END
			END Seq;
		BEGIN
			IF tree # NIL THEN
				Write(tree.left); Gap; FlipStr(tree.trig); Gap; Ch("("); Seq(tree.seq); Ch(")"); Ln; Write(tree.right)
			END
		END Write;
	BEGIN Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.line # 0) OR (S.class # Texts.String) & (S.class # Texts.Name) THEN
			Oberon.GetSelection(text, beg, end, time);
			IF time > 0 THEN Texts.OpenScanner(S, text, beg); Texts.Scan(S) END
		END;
		IF (S.line # 0) OR (S.class # Texts.String) & (S.class # Texts.Name) THEN S.s[0] := 0X END;
		Str("(hotkey is "); Char(hotKey); Ch(")"); Ln;
		tree := NIL; Sort(defs.right, S.s, tree); Texts.OpenBuf(buf); Write(tree); Append(W.buf, buf);
		NEW(T); Texts.Open(T, "");
		Texts.Append(T, buf);
		OpenText("EditKeys.Definitions", T, FALSE);
	END Definitions;

	PROCEDURE GetKeyCode*;
	BEGIN Str("EditKeys.GetKeyCode  ('q' to quit)"); WLog;
		REPEAT Input.Read(ch); Ln; Gap; Char(ch); WLog UNTIL ch = "q";
		Ln; WLog
	END GetKeyCode;

	PROCEDURE Install*;
	BEGIN
		TextGadgets.macroHook := Handle
	END Install;

BEGIN
	Texts.OpenWriter(W); Texts.OpenWriter(WB); Texts.OpenWriter(WL);
	NEW(defs); NEW(dmy); NEW(buf); NEW(indent); map := "0123456789ABCDEF";
	Install;
	ResetDefs;
	NEW(T); Texts.Open(T, DefaultFile); ReadText(DefaultFile, 0); T := NIL;
	InitialExec(InstallMacro);
END EditKeys.

EditKeys.GetKeyCode
