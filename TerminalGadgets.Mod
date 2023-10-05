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

MODULE TerminalGadgets;	(** portable *) (* ww 5 Jun 92, dk, März 94, rs 21-Apr-1994*)

IMPORT Objects, Terminals, Oberon, Texts, Display, Display3, Gadgets, Fonts, Input, Printer, Printer3;


CONST
	NoCursor* = 0; FadedCursor* = 1; FullCursor* = 2;
	Left = 2; Middle = 1; Right = 0;
	Gap* = 2; VSpace = 2 * Gap; HSpace = 3 * Gap;						 (* (in pixels) for nice spacing and leading of the font *)

TYPE
	Frame* = POINTER TO FrameDesc;
	FrameDesc* = RECORD(Gadgets.FrameDesc)
		text*: Terminals.Terminal;
		fnt*: Fonts.Font;
		cursorState*, charW*, lineH*, textcol*, profile*: INTEGER;
		hasSel*: BOOLEAN;
		selTime*: LONGINT;
		selFrom*, selTo*: Terminals.Location;
		col: INTEGER
	END;

	UpdateMsg* = RECORD(Display.FrameMsg)
		text: Terminals.Terminal;
		op, fromLine, fromCol, toLine, toCol: INTEGER;
		oldCur: Terminals.Location
	END;

	MarksMsg = RECORD(Display.FrameMsg)
		id: INTEGER
	END;

VAR 
	w: Texts.Writer;


PROCEDURE InvC(F: Frame) : INTEGER;
BEGIN
	IF F.col = Display3.textbackC THEN RETURN 1
	ELSIF (F.col = Display.BG) OR (F.col = Display3.white) THEN RETURN Display3.FG
	ELSIF F.col > 0  THEN RETURN 15 - F.col
	ELSE RETURN Display3.FG
	END
END  InvC;


PROCEDURE NotifyDisplay*(t: Terminals.Terminal; op, fromLine, fromCol, toLine, toCol: INTEGER; oldCur: Terminals.Location);
VAR
	msg: UpdateMsg;
BEGIN
	msg.text := t;
	msg.op := op;
	msg.F := NIL;
	msg.fromLine := fromLine;
	msg.fromCol := fromCol;
	msg.toLine := toLine;
	msg.toCol := toCol;
	msg.oldCur := oldCur;
	Display.Broadcast(msg)
END NotifyDisplay;

PROCEDURE Open*(f: Frame; handle: Objects.Handler; t: Terminals.Terminal; fnt: Fonts.Font);
BEGIN
	f.handle := handle;
	f.text := t;
	f.cursorState := FadedCursor;
	f.hasSel := FALSE;
	f.fnt := fnt;
(*
	f.charW := 0; f.lineH := 0;
	FOR i := 32 TO 127 DO
		Fonts.GetChar(fnt, CHR(i), dx, x, y, w, h, pat);
		IF w > f.charW THEN
			f.charW := w
		END;
		IF h > f.lineH THEN
			f.lineH := h
		END
	END;
	f.lineH := f.lineH+Gap;
*)
	f.charW := fnt.maxX - fnt.minX;
	f.lineH := fnt.maxY - fnt.minY + Gap;
	f.W := t.width * f.charW + 2*HSpace + 1; (*!*)
	f.H := t.height * f.lineH + 2*VSpace + 1; (*!*)
	(*f.col := Display.BG; f.textcol := Display.FG;*)
	f.col := Display3.textbackC; f.textcol := Display3.textC;
	f.profile := 0	(*flat*)
END Open;


PROCEDURE Copy*(from, to: Frame);
BEGIN
	Open(to, from.handle, from.text, from.fnt)
END Copy;



PROCEDURE DrawCursor(f: Frame; frameX, frameY: INTEGER; R: Display3.Mask; line, col: INTEGER; mode: INTEGER);
VAR
	x, y, w, h: INTEGER;
BEGIN	(*white->InvC(f)*)
	w := f.charW;
	h := f.lineH;
	x := HSpace + w * col;
	y := f.H - VSpace - h * line;

	IF (x < f.W - HSpace) & (y > VSpace) THEN
		x := x + frameX;
		y := y + frameY;
		IF mode = FullCursor THEN
			Display3.ReplConst(R, InvC(f), x - w, y, w, h - Gap, Display.invert)
		ELSIF mode = FadedCursor THEN
			Display3.ReplConst(R, InvC(f), x - w, y + 1, 1, h - Gap - 2, Display.invert);
			Display3.ReplConst(R, InvC(f), x - 1, y + 1, 1, h - Gap - 2, Display.invert);
			Display3.ReplConst(R, InvC(f), x - w, y + h - Gap - 1, w, 1, Display.invert);
			Display3.ReplConst(R, InvC(f), x - w, y, w, 1, Display.invert)
		END
	END
END DrawCursor;



PROCEDURE SetCursor(f: Frame; frameX, frameY: INTEGER; R: Display3.Mask; state: INTEGER);
VAR
	loc: Terminals.Location;
BEGIN
	loc := f.text.cursor;
	DrawCursor(f, frameX, frameY, R, loc.line, loc.col, f.cursorState);
	f.cursorState := state;
	DrawCursor(f, frameX, frameY, R, loc.line, loc.col, state)
END SetCursor;



PROCEDURE DrawSelection(f: Frame; frameX, frameY: INTEGER; R: Display3.Mask; fromLine, fromCol, toLine, toCol: INTEGER);
VAR
	x, y, w, h, top, left, right, cw, tw: INTEGER;
BEGIN	(*white->InvC(f)*)
	top := frameY + f.H - VSpace;
	left := frameX + HSpace;
	right := frameX + f.W - HSpace;
	h := f.lineH;
	cw := f.charW;
	x := left + (fromCol - 1) * cw;
	y := top - fromLine * h;
	IF fromLine = toLine THEN
		w := (toCol - fromCol + 1) * cw;
		IF x + w > right THEN
			w := right - x
		END;
		IF w > 0 THEN
			Display3.ReplConst(R, InvC(f), x, y, w, h, Display.invert)
		END
	ELSE
		tw := f.text.width; w := (tw - fromCol + 2) * cw;
		IF x + w > right THEN 
			w := right - x 
		END;
		IF w > 0 THEN
			Display3.ReplConst(R, InvC(f), x, y, w, h, Display.invert)
		END;
		x := left; w := (tw + 1) * cw;
		IF x + w > right THEN w := right - x END;
		INC(fromLine);
		WHILE fromLine < toLine DO
			INC(fromLine); y := y - h;
			Display3.ReplConst(R, InvC(f), x, y, w, h, Display.invert)
		END;
		y := y - h; w := (toCol) * cw;
		IF x + w > right THEN
			w := right - x
		END;
		Display3.ReplConst(R, InvC(f), x, y, w, h, Display.invert)
	END
END DrawSelection;



PROCEDURE RemoveSelection(f: Frame; frameX, frameY: INTEGER; R: Display3.Mask);
VAR
	from, to: Terminals.Location;
BEGIN
	IF f.hasSel THEN
		from := f.selFrom;
		to := f.selTo;
		DrawSelection(f, frameX, frameY, R, from.line, from.col, to.line, to.col);
		f.hasSel := FALSE
	END
END RemoveSelection;



PROCEDURE TextOf(f: Frame): Texts.Text;
VAR
	i, j, len: INTEGER;
	line: Terminals.Line;
	text: Texts.Text;
BEGIN
	Texts.SetFont(w, f.fnt); i := 1;
	REPEAT
		j := 1;
		line := f.text.line[i];
		len := line.len;
		WHILE j <= len DO
			Texts.Write(w, line.ch[j].ch);
			INC(j)
		END;
		Texts.WriteLn(w);
		INC(i)
	UNTIL i > Terminals.Height;
	NEW(text);
	Texts.Open(text, "");
	Texts.Append(text, w.buf);
	RETURN text
END TextOf;



PROCEDURE TextPos(f: Frame; line, col: INTEGER): INTEGER;
VAR
	i, l, len: INTEGER;
	text: Terminals.Terminal;
BEGIN
	i := 1;
	len := 0;
	text := f.text;
	WHILE i < line DO
		len := len + text.line[i].len;
		INC(i)
	END;
	IF i <= Terminals.Height THEN
		l := text.line[i].len
	ELSE
		l := 0
	END;
	IF l >= col THEN
		RETURN len + col + i - 2
	ELSE
		RETURN len + l + i - 1
	END
END TextPos;



PROCEDURE GetSelection*(f: Frame; VAR text: Texts.Text; VAR beg, end, time: LONGINT);
BEGIN
	IF f.hasSel THEN
		time := f.selTime;
		text := TextOf(f);
		beg := TextPos(f, f.selFrom.line, f.selFrom.col);
		end := TextPos(f, f.selTo.line, f.selTo.col) + 1
	ELSE
		NEW(text);
		Texts.Open(text, "");
		time := 0; beg := 0
	END
END GetSelection;



PROCEDURE Neutralize*(f: Frame; frameX, frameY: INTEGER; R: Display3.Mask);
BEGIN 
	Oberon.RemoveMarks(frameX, frameY, f.W, f.H);
	SetCursor(f, frameX, frameY, R, FadedCursor);
	RemoveSelection(f, frameX, frameY, R);
END Neutralize;



PROCEDURE DrawChar(f: Frame; xPos, yPos: INTEGER; R: Display3.Mask; char: Terminals.Char);
VAR
	dx, cx, cy, cw, ch: INTEGER;
	p: Display.Pattern;
	fnt: Fonts.Font;
BEGIN	(*white -> f.textcol*)
	fnt := f.fnt;
	Fonts.GetChar(fnt, char.ch, dx, cx, cy, cw, ch, p);
	Display3.CopyPattern(R, f.textcol, p, xPos + cx - fnt.minX, yPos + cy - fnt.minY, Display.paint);
	IF ODD(char.attr DIV Terminals.bold) THEN
		Display3.CopyPattern(R, f.textcol, p, xPos + cx - fnt.minX + 1, yPos + cy - fnt.minY, Display.paint)
	END;
	IF ODD(char.attr DIV Terminals.reverse) OR ODD(char.attr DIV Terminals.blinking) THEN
		Display3.ReplConst(R, InvC(f), xPos, yPos, f.charW, f.lineH - Gap, Display.invert)
	END;
	IF ODD(char.attr DIV Terminals.underline) THEN
		Display3.ReplConst(R, f.textcol, xPos, yPos, f.charW, 1, Display.replace(*invert*))
	END
END DrawChar;



PROCEDURE DisplayLine(f: Frame; frameX, frameY: INTEGER; R: Display3.Mask; line, fromCol, toCol: INTEGER);
VAR
	x, y, w, h, w2: INTEGER; 
	l: Terminals.Line;
	text: Terminals.Terminal;
BEGIN
	h := f.lineH;
	y := f.H - VSpace - line * h;
	IF y > VSpace THEN
		text := f.text;
		l := text.line[line];
		w := f.charW;
		x := w * fromCol;
		IF x < f.W - 2 * HSpace THEN
			w2 := w * (toCol - fromCol);
			IF w2 > f.W - 2 * HSpace - x THEN
				w2 := f.W - 2 * HSpace - x
			END;
			Display3.ReplConst(R, f.col, frameX + HSpace + x - w, frameY + y, w + w2, h, Display.replace);
			IF toCol > l.len THEN
				toCol := l.len
			END;
			WHILE (fromCol <= toCol) & (x < f.W - 2 * HSpace) DO
				DrawChar(f, frameX + HSpace + x - w, frameY + y, R, l.ch[fromCol]);
				INC(fromCol);
				x := x + w
			END
		END
	END
END DisplayLine;

	PROCEDURE Shift(F: Frame; x, y: INTEGER; msk: Display3.Mask; Y, H, dY, top, bot: INTEGER);
		VAR Y0, H0: INTEGER;
	BEGIN
		Y0 := Y+dY; IF Y < Y0 THEN Y0 := Y END;
		IF dY > 0 THEN H0 := H+dY ELSE H0 := H-dY END;
		IF Display3.Visible(msk, x, Y0, F.W, H0) THEN
			Display.CopyBlock(x, Y, F.W, H, x, Y+dY, Display.replace)
		ELSE
			WHILE top <= bot DO
				DisplayLine(F, x, y, msk, top, 1, F.text.width); INC(top)
			END
		END
	END Shift;


PROCEDURE UpdateScrolling(f: Frame; frameX, frameY: INTEGER; R: Display3.Mask; top, bot, dH: INTEGER);
VAR
	y, lh, h, diff, w: INTEGER;
BEGIN
	lh := f.lineH;
	y := frameY + f.H - VSpace - bot * lh;
	diff := (frameY + VSpace - y + lh) DIV lh;	(*lines partially or fully below frameY + VSpace*)
	IF diff < 0 THEN
		diff := 0
	END;
	y := y + diff * lh;
	h := (bot - diff - top - ABS(dH) + 1) * lh;
	(* !!*)
		IF dH < 0 THEN
			dH := -dH;
			IF h > 0 THEN
				Shift(f, frameX, frameY, R, y, h, dH * lh, top, bot)
(*
				Display.CopyBlock(frameX, y, f.W, h, frameX, y + dH * lh, Display.replace)
*)
			END;
			top := bot - diff - dH + 1;
			w := f.text.width;
			IF top < 1 THEN
				top := 1
			END;
			WHILE top <= bot DO
				DisplayLine(f, frameX, frameY, R, top, 1, w);
				INC(top)
			END
		ELSE
			IF h > 0 THEN
				Shift(f, frameX, frameY, R, y + dH * lh, h, -dH * lh, top, bot)
(*
				Display.CopyBlock(frameX, y + dH * lh, f.W, h, frameX, y, Display.replace)
*)
			END;
			y := frameY + f.H - VSpace - (top + dH - 1) * lh;
			h := dH * lh;
			IF y < frameY + VSpace THEN
				h := h - frameY - VSpace + y;
				y := frameY + VSpace
			END;
			IF h > 0 THEN
				Display3.ReplConst(R, f.col, frameX, y, f.W, h, Display.replace)
			END
		END
	(**)
END UpdateScrolling;



PROCEDURE Update*(f: Frame; frameX, frameY: INTEGER; R: Display3.Mask; op: INTEGER;
										fromLine, fromCol, toLine, toCol: INTEGER; oldCur: Terminals.Location);
VAR
	cursor: Terminals.Location;
BEGIN
	Oberon.RemoveMarks(frameX, frameY, f.W, f.H);
	RemoveSelection(f, frameX, frameY, R);
	cursor := f.text.cursor;
	IF op = Terminals.update THEN
		DrawCursor(f, frameX, frameY, R, oldCur.line, oldCur.col, f.cursorState);
		IF fromLine = toLine THEN
			DisplayLine(f, frameX, frameY, R, fromLine, fromCol, toCol)
		ELSE
			DisplayLine(f, frameX, frameY, R, fromLine, fromCol, Terminals.MaxWidth);
			INC(fromLine);
			WHILE fromLine < toLine DO
				DisplayLine(f, frameX, frameY, R, fromLine, 1, Terminals.MaxWidth); 
				INC(fromLine);
			END;
			DisplayLine(f, frameX, frameY, R, toLine, 1, toCol)
		END;
		DrawCursor(f, frameX, frameY, R, cursor.line, cursor.col, f.cursorState)
	ELSIF op = Terminals.moveCursor THEN
		DrawCursor(f, frameX, frameY, R, oldCur.line, oldCur.col, f.cursorState);
		DrawCursor(f, frameX, frameY, R, cursor.line, cursor.col, f.cursorState)
	ELSIF op = Terminals.scroll THEN
		DrawCursor(f, frameX, frameY, R, cursor.line, cursor.col, f.cursorState);
		UpdateScrolling(f, frameX, frameY, R, fromLine, toLine, fromCol);
		DrawCursor(f, frameX, frameY, R, cursor.line, cursor.col, f.cursorState)
	END
END Update;



PROCEDURE TrackSelection*(f: Frame; frameX, frameY: INTEGER; R: Display3.Mask; VAR keySum: SET; x, y: INTEGER);
VAR
	keys: SET;
	top, bot, h, left, w, len, tw: INTEGER;
	from, to, oldTo: Terminals.Location;
BEGIN
	top := frameY + f.H - VSpace;
	h := f.lineH;
	tw := f.text.width;
	IF Terminals.Height * h > top - frameY - VSpace THEN
		bot := top - ((top - frameY - VSpace) DIV h) * h
	ELSE
		bot := top - Terminals.Height * h
	END;
	left := frameX + HSpace;
	w := f.charW;
	IF x < left THEN
		x := left
	END;
	IF (bot < y) & (y < top) THEN
		from.line := (top - y) DIV h + 1;
		from.col := (x - left) DIV w + 1;
		len := f.text.line[from.line].len;
		IF from.col < 1 THEN
			from.col := 1
		ELSIF from.col > len THEN
			from.col := len + 1
		END;
		oldTo := from;
		IF oldTo.col > len THEN
			oldTo.col  := tw + 1
		END;
		IF f.hasSel THEN
			IF (f.selFrom.line = f.selTo.line)
			& ((f.selFrom.col = f.selTo.col) OR (f.selFrom.col = f.text.line[f.selFrom.line].len + 1))
			& (f.selFrom.line = from.line) & (f.selFrom.col = from.col) THEN
				from.col := 1
			END;
			RemoveSelection(f, frameX, frameY, R)
		END;
		DrawSelection(f, frameX, frameY, R, from.line, from.col, oldTo.line, oldTo.col);
		REPEAT
			Input.Mouse(keys, x, y);
			keySum := keySum + keys;
			Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, x, y);
			IF x < left THEN
				x := left
			END;
			IF y <= bot THEN
				y := bot + 1
			ELSIF y > top THEN
				y := top
			END;
			to.line := (top - y) DIV h + 1;
			to.col := (x - left) DIV w + 1;
			IF (to.line < from.line) OR ((to.line = from.line) & (to.col < from.col)) THEN
				to := from;
			END;
			IF to.col > f.text.line[to.line].len THEN
				to.col := tw + 1
			END;
			IF (to.line > oldTo.line) OR ((to.line = oldTo.line) & (to.col > oldTo.col)) THEN
				DrawSelection(f, frameX, frameY, R, oldTo.line, oldTo.col, oldTo.line, oldTo.col);
				DrawSelection(f, frameX, frameY, R, oldTo.line, oldTo.col, to.line, to.col)
			ELSIF (to.line < oldTo.line) OR ((to.line = oldTo.line) & (to.col < oldTo.col)) THEN
				DrawSelection(f, frameX, frameY, R, to.line, to.col, oldTo.line, oldTo.col);
				DrawSelection(f, frameX, frameY, R, to.line, to.col, to.line, to.col)
			END;
			oldTo := to
		UNTIL keys = {};
		f.selFrom := from;
		f.selTo := to;
		f.hasSel := TRUE;
		f.selTime := Oberon.Time()
	ELSE
		Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, x, y)
	END
END TrackSelection;



PROCEDURE Call*(f: Frame; cmdLine, cmdCol: INTEGER; new: BOOLEAN);
VAR
	i, len: INTEGER;
	line: Terminals.Line;
	ch: CHAR;
	name: ARRAY Terminals.MaxWidth OF CHAR;
BEGIN
	IF cmdCol > 0 THEN
		i := 0;
		line := f.text.line[cmdLine];
		len := line.len;
		ch := line.ch[cmdCol].ch;
		WHILE (cmdCol < len) & (ch > " ") DO
			name[i] := ch;
			INC(i);
			INC(cmdCol);
			ch := line.ch[cmdCol].ch
		END;
		IF ch > " " THEN
			name[i] := ch;
			INC(i);
			cmdCol := 0;
			INC(cmdLine)
		END;
		name[i] := 0X;
		Oberon.Par.text := TextOf(f);
		Oberon.Par.pos := TextPos(f, cmdLine, cmdCol);
		Oberon.Par.frame := f;
		Oberon.Call(name, Oberon.Par, new, i)
	END
END Call;



PROCEDURE DrawLine(f: Frame; frameX, frameY: INTEGER; R: Display3.Mask; from: Terminals.Location);
VAR
	line: Terminals.Line;
	x1, x2, y, tocol, len: INTEGER;
BEGIN
	IF from.col > 0 THEN
		line := f.text.line[from.line];
		len := line.len;
		tocol := from.col;
		WHILE (tocol < len) & (line.ch[tocol + 1].ch > " ") DO
			INC(tocol)
		END;
		y := frameY + f.H - VSpace - from.line * f.lineH - 1;
		x1 := frameX + HSpace + (from.col - 1) * f.charW;
		x2 := frameX + HSpace + tocol * f.charW;
		IF x2 > frameX + f.W - HSpace THEN
			x2 := frameX + f.W - HSpace
		END;
		Display3.ReplConst(R, InvC(f), x1, y, x2 - x1, 2, Display.invert)
	END
END DrawLine;



PROCEDURE TrackWord*(f: Frame; frameX, frameY: INTEGER; R: Display3.Mask; x, y: INTEGER; VAR cmdLine, cmdCol: INTEGER; VAR keySum: SET);
VAR
	keys: SET;
	top, bot, h, left, w, len: INTEGER;
	pos, oldPos: Terminals.Location;
	line: Terminals.Line;
BEGIN
	top := frameY + f.H - VSpace;
	h := f.lineH;
	IF Terminals.Height * h > top - frameY - VSpace THEN
		bot := top - ((top - frameY - VSpace) DIV h) * h
	ELSE
		bot := top - Terminals.Height * h
	END;
	left := frameX + HSpace;
	w := f.charW;
	oldPos.line := 0;
	oldPos.col := 0;
	REPEAT
		Input.Mouse(keys, x, y);
		keySum := keySum + keys;
		Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, x, y);
		IF x < left THEN
			x := left
		END;
		IF (y <= bot) OR (y > top) THEN
			pos.line := 0;
			pos.col := 0
		ELSE
			pos.line := (top - y) DIV h + 1;
			line := f.text.line[pos.line];
			pos.col := (x - left) DIV w + 1;
			len := line.len;
			IF pos.col > len THEN
				pos.col := len
			END;
			WHILE (pos.col > 0) & (line.ch[pos.col].ch <= " ") DO
				DEC(pos.col)
			END;
			WHILE (pos.col > 1) & (line.ch[pos.col - 1].ch > " ") DO
				DEC(pos.col)
			END;
			IF pos.col = 0 THEN
				pos.line := 0
			END
		END;
		IF (pos.line # oldPos.line) OR (pos.col # oldPos.col) THEN
			DrawLine(f, frameX, frameY, R, oldPos);
			DrawLine(f, frameX, frameY, R, pos);
			oldPos := pos
		END
	UNTIL keys = {};
	DrawLine(f, frameX, frameY, R, pos);
	cmdLine := pos.line; cmdCol := pos.col
END TrackWord;



PROCEDURE Edit*(f: Frame; frameX, frameY: INTEGER; R: Display3.Mask; keys: SET; mouseX, mouseY: INTEGER);
VAR
	keySum: SET;
	text: Texts.Text;
	beg, end, time: LONGINT;
	cmdLine, cmdCol: INTEGER;
	msg: Oberon.ConsumeMsg;
BEGIN
	IF Left IN keys THEN
		keySum := keys;
		Oberon.Defocus; 
		SetCursor(f, frameX, frameY, R, FullCursor);
		REPEAT
			Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, mouseX, mouseY);
			Input.Mouse(keys, mouseX, mouseY); keySum := keySum + keys;
		UNTIL keys = {};
		IF keySum = {Left, Middle} THEN
			Oberon.GetSelection(text, beg, end, time);
			IF time > 0 THEN
				Terminals.SendText(f.text, text, beg, end)
			END
		END
	ELSIF Middle IN keys THEN
		TrackWord(f, frameX, frameY, R, mouseX, mouseY, cmdLine, cmdCol, keys);
		IF ~(Right IN keys) THEN
			Call(f, cmdLine, cmdCol, Left IN keys)
		END
	ELSIF Right IN keys THEN
		TrackSelection(f, frameX, frameY, R, keys, mouseX, mouseY);
		IF keys = {Middle, Right} THEN
			GetSelection(f, msg.text, msg.beg, msg.end, time);
			msg.F := NIL; Display.Broadcast(msg);
			(* !!
			Oberon.FocusViewer.handle(Oberon.FocusViewer, msg)
			*)
		END
	ELSE
		Oberon.DrawCursor(Oberon.Mouse, (*Effects.*)Oberon.Arrow, mouseX, mouseY)
	END
END Edit;



PROCEDURE Modify*(f: Frame; frameX, frameY: INTEGER; R: Display3.Mask; id, Y, H, dY: INTEGER);
VAR
	h, l1, l2, w: INTEGER;
	cursor: Terminals.Location;
BEGIN
	HALT(66);
	Neutralize(f, frameX, frameY, R);
	cursor := f.text.cursor;
	DrawCursor(f, frameX, frameY, R, cursor.line, cursor.col, f.cursorState);
	IF H < 2 * VSpace THEN
		frameY := Y;
		f.H := H;
		Display3.ReplConst(R, f.col, frameX, Y, f.W, H, Display.replace)
	ELSIF id = Display.reduce THEN
		h := ((H - 2 * VSpace - 1) DIV f.lineH) * f.lineH;
		IF h < 0 THEN
			h := 0
		END;
		(* !!
		IF dY # 0 THEN
			Display3.CopyBlock(R, frameX, y, f.W, h + VSpace, frameX, y - dY, Display.replace)
		END;
		*)
		IF H - h - VSpace > 0 THEN
			Display3.ReplConst(R, f.col, frameX, Y, f.W, H - h - VSpace, Display.replace)
		END;
		frameY := Y; f.H := H
	ELSE 
		l1 := (f.H - 2 * VSpace - 1) DIV f.lineH;
		IF l1 < 0 THEN
			l1 := 0
		END;
		h := l1 * f.lineH; 
		(* !!
		IF (dY # 0) & (h > 0) THEN
			Display3.CopyBlock(R, frameX, y, f.W, h + VSpace, frameX, y + dY, Display.replace)
		END;
		*)
		Display3.ReplConst(R, f.col, frameX, Y + H - VSpace, f.W, VSpace, Display.replace);
		IF H - h - VSpace > 0 THEN
			Display3.ReplConst(R, f.col, frameX, Y, f.W, H - h - VSpace, Display.replace)
		END;
		w := f.text.width; l2 := (H - 2 * VSpace - 1) DIV f.lineH;
		frameY := Y; f.H := H;
		IF l2 > Terminals.Height THEN
			l2 := Terminals.Height
		END;
		WHILE l1 < l2 DO
			INC(l1);
			DisplayLine(f, frameX, frameY, R, l1, 1, w)
		END
	END;
	DrawCursor(f, frameX, frameY, R, cursor.line, cursor.col, f.cursorState)
END Modify;


	PROCEDURE SetFont(F: Frame; name: ARRAY OF CHAR);
		VAR fnt: Fonts.Font; M: Display.ModifyMsg;
	BEGIN
		fnt := Fonts.This(name);
		IF fnt # F.fnt THEN F.fnt := fnt;
			F.charW := fnt.maxX - fnt.minX;
			F.lineH := fnt.maxY - fnt.minY + Gap;
			M.W := F.text.width * F.charW + 2*HSpace+ 1; (*!*)
			M.H := F.text.height * F.lineH + 2*VSpace + 1; (*!*)
			M.X := F.X; M.Y := F.Y;
			M.dX := 0; M.dY := 0; M.dW := M.W-F.W; M.dH := M.H-F.H;
			M.id := Display.extend; M.F := F; Display.Broadcast(M)
		END
	END SetFont;

PROCEDURE FrameAttr(F: Frame; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN
			M.class := Objects.String;
			COPY("TerminalGadgets.NewFrame", M.s);
			M.res := 0
		ELSIF M.name = "Color" THEN
			M.class := Objects.Int;
			M.i := F.col;
			M.res := 0
		ELSIF M.name = "Font" THEN M.class := Objects.String; COPY(F.fnt.name, M.s); M.res := 0
		ELSIF M.name = "TextCol" THEN M.class := Objects.Int; M.i := F.textcol; M.res := 0
		ELSIF M.name = "Profile" THEN M.class := Objects.Int; M.i := F.profile; M.res := 0
		ELSE
			Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Color" THEN
			IF M.class = Objects.Int THEN
				F.col := SHORT(M.i);
				M.res := 0
			END;
		ELSIF M.name = "Font" THEN SetFont(F, M.s); M.res := 0
		ELSIF M.name = "TextCol" THEN F.textcol := SHORT(M.i); M.res := 0
		ELSIF M.name = "Profile" THEN F.profile := SHORT(M.i); M.res := 0
		ELSE
			Gadgets.framehandle(F, M);
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Color"); M.Enum("TextCol"); M.Enum("Profile"); M.Enum("Font");
		Gadgets.framehandle(F, M)
	END
END FrameAttr;

PROCEDURE RestoreFrame(F: Frame; frameX, frameY: INTEGER; R: Display3.Mask);
	VAR b, t: INTEGER;
BEGIN
	IF F.profile = 0 THEN Display3.ReplConst(R, F.col, frameX, frameY, F.W, F.H, Display.replace)	(*flat*)
	ELSE
		IF F.profile = 1 THEN b := Display3.topC; t := Display3.bottomC	(*down*)
		ELSIF F.profile = 2 THEN b := Display3.bottomC; t := Display3.topC	(*up*)
		END;
		Display3.FilledRect3D(R, t, b, F.col, frameX, frameY, F.W, F.H, 1, Display.replace)
	END;
	Update(F, frameX, frameY, R, Terminals.update, 1, 1, F.text.height, F.text.width, F.text.cursor);
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(R, Display3.white, Display3.selectpat, frameX, frameY, frameX, frameY, F.W, F.H, Display.paint)
	END
END RestoreFrame;

	PROCEDURE Print(F: Frame; VAR M: Display.DisplayMsg);
		VAR
			R: Display3.Mask;
			b, t, i, j: INTEGER;
			print: ARRAY 2 OF CHAR;
		PROCEDURE P(x: LONGINT): INTEGER;
		BEGIN
			RETURN SHORT((x * Display.Unit + Printer.Unit DIV 2) DIV Printer.Unit)
		END P;
	BEGIN
		Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
		IF F.profile = 0 THEN
			Printer3.ReplConst(R, F.col, M.x, M.y, P(F.W), P(F.H), Display.replace)	(*flat*)
		ELSE
			IF F.profile = 1 THEN
				b := Display3.topC; t := Display3.bottomC	(*down*)
			ELSIF F.profile = 2 THEN
				b := Display3.bottomC; t := Display3.topC	(*up*)
			END;
			Printer3.FilledRect3D(R, t, b, F.col, M.x, M.y, P(F.W), P(F.H), 1, Display.replace)
		END;
		print[1] := 0X;
		FOR j := 1 TO F.text.height DO
			FOR i := 1 TO F.text.line[j].len DO
				print[0] := F.text.line[j].ch[i].ch;
				Printer3.String(R, F.textcol, M.x+P(HSpace+i*F.charW), M.y+P(F.H-VSpace-j*F.lineH), 
					Fonts.This("Courier8.Scn.Fnt"), print, Display.paint)
			END
		END
	END Print;

PROCEDURE CopyFrame*(VAR M: Objects.CopyMsg; from, to: Frame);
BEGIN
	to.col := from.col;
	Gadgets.CopyFrame(M, from, to);
	to.text := from.text; to.fnt := from.fnt;
	to.cursorState := from.cursorState;
	to.charW := from.charW; to.lineH := from.lineH;
	to.textcol := from.textcol; to.profile := from.profile;
	to.hasSel := from.hasSel;
	to.selTime := from.selTime;
	to.selFrom := from.selFrom; to.selTo := from.selTo
END CopyFrame;


	PROCEDURE RemoveMarks(F: Frame; x, y: INTEGER; VAR M: MarksMsg);
		VAR R: Display3.Mask;
	BEGIN
		IF M.F = F THEN
			Gadgets.MakeMask(F, x, y, M.dlink, R);
			IF M.id = Oberon.neutralize THEN
				Neutralize(F, x, y, R)
			ELSIF M.id = Oberon.defocus THEN
				SetCursor(F, x, y, R, FadedCursor)
			END
		END
	END RemoveMarks;


PROCEDURE Handle*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR
	frameX, frameY: INTEGER;
	F0: Frame;
	R: Display3.Mask;
	m: MarksMsg;
BEGIN
	WITH F: Frame DO
		IF M IS UpdateMsg THEN
			WITH M: UpdateMsg DO
				frameX := M.x + F.X; frameY := M.y + F.Y;																	 (* calculate display coordinates *)
				IF M.text = F.text THEN
					Gadgets.MakeMask(F, frameX, frameY, M.dlink, R);
					Update(F, frameX, frameY, R, M.op, M.fromLine, M.fromCol, M.toLine, M.toCol, M.oldCur);
				END
			END
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				frameX := M.x + F.X; frameY := M.y + F.Y;
				IF (M.F = NIL) OR (M.F = F) THEN																 		(* message addressed to this frame *)				
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, frameX, frameY, M.dlink, R);
									RestoreFrame(F, frameX, frameY, R)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, frameX, frameY, M.dlink, R);
									Display3.AdjustMask(R, frameX + M.u, frameY + F.H - 1 + M.v, M.w, M.h);
									RestoreFrame(F, frameX, frameY, R)
								END
							ELSIF M.device = Display.printer THEN
								Print(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) THEN
								IF Gadgets.InActiveArea(F, M) THEN
									Gadgets.MakeMask(F, frameX, frameY, M.dlink, R);
									Edit( F, frameX, frameY, R, M.keys, M.X, M.Y );
									M.res := 0;
								ELSE
									Gadgets.framehandle(F, M);
								END
							ELSIF (M.id = Oberon.consume) & (F.cursorState = FullCursor) THEN
								Terminals.Send( F.text, M.ch );
								M.res := 0;
							ELSE
								Gadgets.framehandle(F, M)
							END
						END
				(* !!
					ELSIF M IS Display.ModifyMsg THEN
						WITH M: Display.ModifyMsg DO
							IF M.F = F THEN
								Gadgets.MakeMask(F, frameX, frameY, M.dlink, R);
								Modify(F, frameX, frameY, R, M.id, M.X, M.Y, M.W, M.H, M.dY);
							END 
						END
				*)
					ELSIF (M IS Oberon.ConsumeMsg) & (F.cursorState = FullCursor) THEN
						WITH M: Oberon.ConsumeMsg DO
						 	Terminals.SendText(F.text, M.text, M.beg, M.end)
						 END
					ELSIF M IS Oberon.SelectMsg THEN
						WITH M: Oberon.SelectMsg DO
							IF M.id = Oberon.get THEN
								IF F.hasSel & (M.time < F.selTime) THEN
									GetSelection(F, M.text, M.beg, M.end, M.time)
								END
							END
						END
					ELSIF M IS Oberon.ControlMsg THEN
						WITH M: Oberon.ControlMsg DO
							m.F := F; m.id := M.id; Display.Broadcast(m)
						END
					ELSIF M IS MarksMsg THEN RemoveMarks(F, frameX, frameY, M(MarksMsg))
					ELSIF M IS Display.SelectMsg THEN
						Gadgets.framehandle(F, M)
					ELSIF M IS Display.ConsumeMsg THEN
						Gadgets.framehandle(F, M)
					ELSE
						Gadgets.framehandle(F, M)
					END
				END
			END
			
		(* Object messages *)
		
		ELSIF M IS Objects.AttrMsg THEN
			FrameAttr(F, M(Objects.AttrMsg))
		ELSIF  M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN																		(* copy msg arrives again *)
					 M.obj := F.dlink
				ELSE																											(* first time copy message arrives *)
					NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyFrame(M, F, F0); M.obj := F0
				END
			END
(*
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN (* store private data here *)
					Files.WriteInt(M.R, F.col); Files.WriteInt(M.R, F.textcol);
					Files.WriteInt(M.R, F.profile); Files.WriteString(M.R, F.fnt.name);
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN (* load private data here *)
					Files.ReadInt(M.R, col); Files.ReadInt(M.R, textcol);
					Files.ReadInt(M.R, profile); Files.ReadString(M.R, name);
					Open(F, F.handler, F.text, Fonts.This(name));
					F.col := col; F.textcol := textcol; F.profile := profile;
					Gadgets.framehandle(F, M)
				END
			END
*)
		ELSE																								(* unknown msg, framehandler might know it *)
			Gadgets.framehandle(F, M)
		END
	END
END Handle;



BEGIN
	Texts.OpenWriter(w);
END TerminalGadgets.
