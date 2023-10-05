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

MODULE TerminalFrames;	(** portable *) (* ww 5 Jun 92 *)

	IMPORT Objects, Terminals, Oberon, Texts, Display, Fonts, Input;

	CONST
		NoCursor* = 0; FadedCursor* = 1; FullCursor* = 2;
		Left = 2; Middle = 1; Right = 0;	Gap = 2; VSpace = 2 * Gap; HSpace = 3 * VSpace;
		black = Display.BG; white =Display.FG;

	TYPE
		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD(Display.FrameDesc)
			text*: Terminals.Terminal;
			fnt*: Fonts.Font;
			cursorState*, charW*, lineH*: INTEGER;
			hasSel*: BOOLEAN;
			selTime*: LONGINT;
			selFrom*, selTo*: Terminals.Location;
		END;

		UpdateMsg* = RECORD(Display.FrameMsg)
			text: Terminals.Terminal;
			op, fromLine, fromCol, toLine, toCol: INTEGER;
			oldCur: Terminals.Location
		END;

	VAR w: Texts.Writer;

	PROCEDURE NotifyDisplay*
		(t: Terminals.Terminal; op, fromLine, fromCol, toLine, toCol: INTEGER; oldCur: Terminals.Location);
		VAR msg: UpdateMsg;
	BEGIN msg.text := t; msg.op := op;
		msg.fromLine := fromLine; msg.fromCol := fromCol; msg.toLine := toLine; msg.toCol := toCol; msg.oldCur := oldCur;
		msg.F := NIL;
		Display.Broadcast(msg)
	END NotifyDisplay;

	PROCEDURE Open*(f: Frame; h: Objects.Handler; t: Terminals.Terminal; fnt: Fonts.Font);
	BEGIN f.handle := h; f.text := t; f.cursorState := FadedCursor; f.hasSel := FALSE;
		f.fnt := fnt; f.charW := fnt.maxX - fnt.minX; f.lineH := fnt.maxY - fnt.minY + Gap
	END Open;

	PROCEDURE Copy*(from, to: Frame);
	BEGIN Open(to, from.handle, from.text, from.fnt)
	END Copy;

	PROCEDURE DrawCursor(f: Frame; line, col: INTEGER; mode: INTEGER);
		VAR x, y, w, h: INTEGER;
	BEGIN w := f.charW; h := f.lineH; x := f.X + HSpace + w * col; y := f.Y + f.H - VSpace - h * line;
		IF (x < f.X + f.W - HSpace) & (y > f.Y + VSpace) THEN
			IF mode = FullCursor THEN Display.ReplConst(white, x - w, y, w, h - Gap, Display.invert)
			ELSIF mode = FadedCursor THEN
				Display.ReplConst(white, x - w, y + 1, 1, h - Gap - 2, Display.invert);
				Display.ReplConst(white, x - 1, y + 1, 1, h - Gap - 2, Display.invert);
				Display.ReplConst(white, x - w, y + h - Gap - 1, w, 1, Display.invert);
				Display.ReplConst(white, x - w, y, w, 1, Display.invert)
			END
		END
	END DrawCursor;

	PROCEDURE SetCursor*(f: Frame; state: INTEGER);
		VAR loc: Terminals.Location;
	BEGIN loc := f.text.cursor; DrawCursor(f, loc.line, loc.col, f.cursorState);
		f.cursorState := state; DrawCursor(f, loc.line, loc.col, state)
	END SetCursor;

	PROCEDURE DrawSelection(f: Frame; fromLine, fromCol, toLine, toCol: INTEGER);
		VAR x, y, w, h, top, left, right, cw, tw: INTEGER;
	BEGIN top := f.Y + f.H - VSpace; left := f.X + HSpace; right := f.X + f.W - HSpace; h := f.lineH; cw := f.charW;
		y := top - fromLine * h; x := left + (fromCol - 1) * cw;
		IF fromLine = toLine THEN w := (toCol - fromCol + 1) * cw;
			IF x + w > right THEN w := right - x END;
			IF w > 0 THEN Display.ReplConst(white, x, y, w, h, Display.invert) END
		ELSE tw := f.text.width; w := (tw - fromCol + 2) * cw;
			IF x + w > right THEN w := right - x END;
			IF w > 0 THEN Display.ReplConst(white, x, y, w, h, Display.invert) END;
			x := left; w := (tw + 1) * cw;
			IF x + w > right THEN w := right - x END;
			INC(fromLine);
			WHILE fromLine < toLine DO INC(fromLine); y := y - h;
				Display.ReplConst(white, x, y, w, h, Display.invert)
			END;
			y := y - h; w := (toCol) * cw;
			IF x + w > right THEN w := right - x END;
			Display.ReplConst(white, x, y, w, h, Display.invert)
		END
	END DrawSelection;

	PROCEDURE RemoveSelection*(f: Frame);
		VAR from, to: Terminals.Location;
	BEGIN
		IF f.hasSel THEN from := f.selFrom; to := f.selTo; DrawSelection(f, from.line, from.col, to.line, to.col);
			f.hasSel := FALSE
		END
	END RemoveSelection;

	PROCEDURE SetSelection*(f: Frame; fromLine, fromCol, toLine, toCol: INTEGER);
		VAR h: INTEGER; loc: Terminals.Location;
	BEGIN RemoveSelection(f); h := f.H - 2 * VSpace;
		IF h < toLine * f.lineH THEN toLine := h DIV f.lineH; toCol := f.text.width + 1 END;
		IF fromCol > f.text.line[fromLine].len THEN fromCol := f.text.line[fromLine].len + 1 END;
		IF toCol > f.text.line[toLine].len THEN toCol := f.text.width + 1 END;
		IF (fromLine < toLine) OR ((fromLine = toLine) & (fromCol * f.charW < f.W - 2 * HSpace)) THEN
			DrawSelection(f, fromLine, fromCol, toLine, toCol);
			loc.line := fromLine; loc.col := fromCol; f.selFrom := loc;
			loc.line := toLine; loc.col := toCol; f.selTo := loc;
			f.hasSel := TRUE; f.selTime := Oberon.Time()
		END
	END SetSelection;

	PROCEDURE TextOf(f: Frame): Texts.Text;
		VAR i, j, len: INTEGER; line: Terminals.Line; text: Texts.Text;
	BEGIN Texts.SetFont(w, f.fnt); i := 1;
		REPEAT j := 1; line := f.text.line[i]; len := line.len;
			WHILE j <= len DO Texts.Write(w, line.ch[j].ch); INC(j) END;
			Texts.WriteLn(w); INC(i)
		UNTIL i > Terminals.Height;
		NEW(text);
		Texts.Open(text, "");
		Texts.Append(text, w.buf); RETURN text
	END TextOf;

	PROCEDURE TextPos(f: Frame; line, col: INTEGER): INTEGER;
		VAR i, l, len: INTEGER; text: Terminals.Terminal;
	BEGIN i := 1; len := 0; text := f.text;
		WHILE i < line DO len := len + text.line[i].len; INC(i) END;
		IF i <= Terminals.Height THEN l := text.line[i].len ELSE l := 0 END;
		IF l >= col THEN RETURN len + col + i - 2 ELSE RETURN len + l + i - 1 END
	END TextPos;

	PROCEDURE GetSelection*(f: Frame; VAR text: Texts.Text; VAR beg, end, time: LONGINT);
	BEGIN
		IF f.hasSel THEN time := f.selTime; text := TextOf(f);
			beg := TextPos(f, f.selFrom.line, f.selFrom.col); end := TextPos(f, f.selTo.line, f.selTo.col) + 1
		ELSE NEW(text); Texts.Open(text, ""); time := 0; beg := 0
		END
	END GetSelection;

	PROCEDURE Neutralize*(f: Frame);
	BEGIN Oberon.RemoveMarks(f.X, f.Y, f.W, f.H); SetCursor(f, FadedCursor); RemoveSelection(f)
	END Neutralize;

	PROCEDURE DrawChar(f: Frame; x, y: INTEGER; char: Terminals.Char);
		VAR dx, cx, cy, cw, ch: INTEGER; p: Display.Pattern; fnt: Fonts.Font;
	BEGIN fnt := f.fnt; Fonts.GetChar(fnt, char.ch, dx, cx, cy, cw, ch, p);
		Display.CopyPattern(white, p, x + cx - fnt.minX, y + cy - fnt.minY, Display.paint);
		IF ODD(char.attr DIV Terminals.bold) THEN
			Display.CopyPattern(white, p, x + cx - fnt.minX + 1, y + cy - fnt.minY, Display.paint)
		END;
		IF ODD(char.attr DIV Terminals.reverse) OR ODD(char.attr DIV Terminals.blinking) THEN
			Display.ReplConst(white, x, y, f.charW, f.lineH - Gap, Display.invert)
		END;
		IF ODD(char.attr DIV Terminals.underline) THEN
			Display.ReplConst(white, x, y, f.charW, 1, Display.invert)
		END
	END DrawChar;

	PROCEDURE UpdateLine(f: Frame; line, fromCol, toCol: INTEGER);
		VAR x, y, w, h, w2: INTEGER; l: Terminals.Line; text: Terminals.Terminal;
	BEGIN h := f.lineH; y := f.Y + f.H - VSpace - line * h;
		IF y > f.Y + VSpace THEN text := f.text;
			l := text.line[line]; w := f.charW; x := w * fromCol;
			IF x < f.W - 2 * HSpace THEN w2 := w * (toCol - fromCol);
				IF w2 > f.W - 2 * HSpace - x THEN w2 := f.W - 2 * HSpace - x END;
				Display.ReplConst(black, f.X + HSpace + x - w, y, w + w2, h, Display.replace);
				IF toCol > l.len THEN toCol := l.len END;
				WHILE (fromCol <= toCol) & (x < f.W - 2 * HSpace) DO DrawChar(f, f.X + HSpace + x - w, y, l.ch[fromCol]);
					INC(fromCol); x := x + w
				END
			END
		END
	END UpdateLine;

	PROCEDURE UpdateScrolling(f: Frame; top, bot, dH: INTEGER);
		VAR y, lh, h, diff, w: INTEGER;
	BEGIN lh := f.lineH; y := f.Y + f.H - VSpace - bot * lh; diff := (f.Y + VSpace - y + lh) DIV lh;
		IF diff < 0 THEN diff := 0 END;
		y := y + diff * lh; h := (bot - diff - top - ABS(dH) + 1) * lh;
		IF dH < 0 THEN dH := -dH;
			IF h > 0 THEN Display.CopyBlock(f.X, y, f.W, h, f.X, y + dH * lh, Display.replace) END;
			top := bot - diff - dH + 1; w := f.text.width;
			IF top < 1 THEN top := 1 END;
			WHILE top <= bot DO UpdateLine(f, top, 1, w); INC(top) END
		ELSE
			IF h > 0 THEN Display.CopyBlock(f.X, y + dH * lh, f.W, h, f.X, y, Display.replace) END;
			y := f.Y + f.H - VSpace - (top + dH - 1) * lh; h := dH * lh;
			IF y < f.Y + VSpace THEN h := h - f.Y - VSpace + y; y := f.Y + VSpace END;
			IF h > 0 THEN Display.ReplConst(black, f.X, y, f.W, h, Display.replace) END
		END
	END UpdateScrolling;

	PROCEDURE Update*(f: Frame; op, fromLine, fromCol, toLine, toCol: INTEGER; oldCur: Terminals.Location);
		VAR cursor: Terminals.Location;
	BEGIN Oberon.RemoveMarks(f.X, f.Y, f.W, f.H); RemoveSelection(f); cursor := f.text.cursor;
		IF op = Terminals.update THEN DrawCursor(f, oldCur.line, oldCur.col, f.cursorState);
			IF fromLine = toLine THEN UpdateLine(f, fromLine, fromCol, toCol)
			ELSE UpdateLine(f, fromLine, fromCol, Terminals.MaxWidth);
				INC(fromLine);
				WHILE fromLine < toLine DO UpdateLine(f, fromLine, 1, Terminals.MaxWidth); INC(fromLine) END;
				UpdateLine(f, toLine, 1, toCol)
			END;
			DrawCursor(f, cursor.line, cursor.col, f.cursorState)
		ELSIF op = Terminals.moveCursor THEN
			DrawCursor(f, oldCur.line, oldCur.col, f.cursorState); DrawCursor(f, cursor.line, cursor.col, f.cursorState)
		ELSIF op = Terminals.scroll THEN DrawCursor(f, cursor.line, cursor.col, f.cursorState);
			UpdateScrolling(f, fromLine, toLine, fromCol); DrawCursor(f, cursor.line, cursor.col, f.cursorState)
		END
	END Update;

	PROCEDURE TrackSelection*(f: Frame; VAR keySum: SET; x, y: INTEGER);
		VAR keys: SET; top, bot, h, left, w, len, tw: INTEGER; from, to, oldTo: Terminals.Location;
	BEGIN top := f.Y + f.H - VSpace; h := f.lineH; tw := f.text.width;
		IF Terminals.Height * h > top - f.Y - VSpace THEN bot := top - ((top - f.Y - VSpace) DIV h) * h
		ELSE bot := top - Terminals.Height * h
		END;
		left := f.X + HSpace; w := f.charW;
		IF x < left THEN x := left END;
		IF (bot < y) & (y < top) THEN from.line := (top - y) DIV h + 1; from.col := (x - left) DIV w + 1;
			len := f.text.line[from.line].len;
			IF from.col < 1 THEN from.col := 1 ELSIF from.col > len THEN from.col := len + 1 END;
			oldTo := from;
			IF oldTo.col > len THEN oldTo.col  := tw + 1 END;
			IF f.hasSel THEN
				IF (f.selFrom.line = f.selTo.line)
					& ((f.selFrom.col = f.selTo.col) OR (f.selFrom.col = f.text.line[f.selFrom.line].len + 1))
					& (f.selFrom.line = from.line) & (f.selFrom.col = from.col)
				THEN from.col := 1
				END;
				RemoveSelection(f)
			END;
			DrawSelection(f, from.line, from.col, oldTo.line, oldTo.col);
			REPEAT Input.Mouse(keys, x, y); keySum := keySum + keys;
				Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, x, y);
				IF x < left THEN x := left END;
				IF y <= bot THEN y := bot + 1 ELSIF y > top THEN y := top END;
				to.line := (top - y) DIV h + 1; to.col := (x - left) DIV w + 1;
				IF (to.line < from.line) OR ((to.line = from.line) & (to.col < from.col)) THEN to := from;
				END;
				IF to.col > f.text.line[to.line].len THEN to.col := tw + 1 END;
				IF (to.line > oldTo.line) OR ((to.line = oldTo.line) & (to.col > oldTo.col)) THEN
					DrawSelection(f, oldTo.line, oldTo.col, oldTo.line, oldTo.col);
					DrawSelection(f, oldTo.line, oldTo.col, to.line, to.col)
				ELSIF (to.line < oldTo.line) OR ((to.line = oldTo.line) & (to.col < oldTo.col)) THEN
					DrawSelection(f, to.line, to.col, oldTo.line, oldTo.col);
					DrawSelection(f, to.line, to.col, to.line, to.col)
				END;
				oldTo := to
			UNTIL keys = {};
			f.selFrom := from; f.selTo := to; f.hasSel := TRUE; f.selTime := Oberon.Time()
		ELSE Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, x, y)
		END
	END TrackSelection;

	PROCEDURE Call*(f: Frame; cmdLine, cmdCol: INTEGER; new: BOOLEAN);
		VAR i, len: INTEGER; line: Terminals.Line; ch: CHAR;
			name: ARRAY Terminals.MaxWidth OF CHAR;
	BEGIN
		IF cmdCol > 0 THEN i := 0; line := f.text.line[cmdLine]; len := line.len; ch := line.ch[cmdCol].ch;
			WHILE (cmdCol < len) & (ch > " ") DO name[i] := ch; INC(i); INC(cmdCol); ch := line.ch[cmdCol].ch END;
			IF ch > " " THEN name[i] := ch; INC(i); cmdCol := 0; INC(cmdLine) END;
			name[i] := 0X;
			Oberon.Par.text := TextOf(f); Oberon.Par.pos := TextPos(f, cmdLine, cmdCol);
			Oberon.Par.frame := f;
			Oberon.Call(name, Oberon.Par, new, i)
		END
	END Call;

	PROCEDURE DrawLine(f: Frame; from: Terminals.Location);
		VAR line: Terminals.Line; x1, x2, y, tocol, len: INTEGER;
	BEGIN
		IF from.col > 0 THEN line := f.text.line[from.line]; len := line.len; tocol := from.col;
			WHILE (tocol < len) & (line.ch[tocol + 1].ch > " ") DO INC(tocol) END;
			y := f.Y + f.H - VSpace - from.line * f.lineH - 1;
			x1 := f.X + HSpace + (from.col - 1) * f.charW; x2 := f.X + HSpace + tocol * f.charW;
			IF x2 > f.X + f.W - HSpace THEN x2 := f.X + f.W - HSpace END;
			Display.ReplConst(white, x1, y, x2 - x1, 2, Display.invert)
		END
	END DrawLine;

	PROCEDURE TrackWord*(f: Frame; x, y: INTEGER; VAR cmdLine, cmdCol: INTEGER; VAR keySum: SET);
		VAR keys: SET; top, bot, h, left, w, len: INTEGER; pos, oldPos: Terminals.Location; line: Terminals.Line;
	BEGIN top := f.Y + f.H - VSpace; h := f.lineH;
		IF Terminals.Height * h > top - f.Y - VSpace THEN bot := top - ((top - f.Y - VSpace) DIV h) * h
		ELSE bot := top - Terminals.Height * h
		END;
		left := f.X + HSpace; w := f.charW; oldPos.line := 0; oldPos.col := 0;
		REPEAT Input.Mouse(keys, x, y); keySum := keySum + keys;
			Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, x, y);
			IF x < left THEN x := left END;
			IF (y <= bot) OR (y > top) THEN pos.line := 0; pos.col := 0
			ELSE pos.line := (top - y) DIV h + 1; line := f.text.line[pos.line];
				pos.col := (x - left) DIV w + 1; len := line.len;
				IF pos.col > len THEN pos.col := len END;
				WHILE (pos.col > 0) & (line.ch[pos.col].ch <= " ") DO DEC(pos.col) END;
				WHILE (pos.col > 1) & (line.ch[pos.col - 1].ch > " ") DO DEC(pos.col) END;
				IF pos.col = 0 THEN pos.line := 0 END
			END;
			IF (pos.line # oldPos.line) OR (pos.col # oldPos.col) THEN
				DrawLine(f, oldPos); DrawLine(f, pos); oldPos := pos
			END
		UNTIL keys = {};
		DrawLine(f, pos);
		cmdLine := pos.line; cmdCol := pos.col
	END TrackWord;

	PROCEDURE Edit*(f: Frame; keys: SET; x, y: INTEGER);
		VAR keySum: SET; text: Texts.Text; beg, end, time: LONGINT; cmdLine, cmdCol: INTEGER;
			msg: Oberon.ConsumeMsg;
	BEGIN
		IF Left IN keys THEN keySum := keys;
			Oberon.Defocus; SetCursor(f, FullCursor);
			REPEAT Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, x, y);
				Input.Mouse(keys, x, y); keySum := keySum + keys
			UNTIL keys = {};
			IF keySum = {Left, Middle} THEN Oberon.GetSelection(text, beg, end, time);
				IF time > 0 THEN Terminals.SendText(f.text, text, beg, end) END
			END
		ELSIF Middle IN keys THEN TrackWord(f, x, y, cmdLine, cmdCol, keys);
			IF ~(Right IN keys) THEN Call(f, cmdLine, cmdCol, Left IN keys) END
		ELSIF Right IN keys THEN TrackSelection(f, keys, x, y);
			IF keys = {Middle, Right} THEN GetSelection(f, msg.text, msg.beg, msg.end, time);
				msg.F := NIL;
				Display.Broadcast(msg);
				(*
				Oberon.FocusViewer.handle(Oberon.FocusViewer, msg)
				*)
			END
		ELSE Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, x, y)
		END
	END Edit;

	PROCEDURE Modify*(f: Frame; id, Y, H, dY: INTEGER);
		VAR y, h, l1, l2, w: INTEGER; cursor: Terminals.Location;
	BEGIN Neutralize(f); cursor := f.text.cursor; DrawCursor(f, cursor.line, cursor.col, f.cursorState);
		IF H < 2 * VSpace THEN f.Y := Y; f.H := H; Display.ReplConst(black, f.X, Y, f.W, H, Display.replace)
		ELSIF id = Display.reduce THEN h := ((H - 2 * VSpace - 1) DIV f.lineH) * f.lineH;
			IF h < 0 THEN h := 0 END;
			y := f.Y + f.H - VSpace - h;
			IF dY # 0 THEN Display.CopyBlock(f.X, y, f.W, h + VSpace, f.X, y - dY, Display.replace) END;
			IF H - h - VSpace > 0 THEN Display.ReplConst(black, f.X, Y, f.W, H - h - VSpace, Display.replace) END;
			f.Y := Y; f.H := H
		ELSE l1 := (f.H - 2 * VSpace - 1) DIV f.lineH;
			IF l1 < 0 THEN l1 := 0 END;
			h := l1 * f.lineH; y := f.Y + f.H - VSpace - h;
			IF (dY # 0) & (h > 0) THEN Display.CopyBlock(f.X, y, f.W, h + VSpace, f.X, y + dY, Display.replace) END;
			Display.ReplConst(black, f.X, Y + H - VSpace, f.W, VSpace, Display.replace);
			IF H - h - VSpace > 0 THEN Display.ReplConst(black, f.X, Y, f.W, H - h - VSpace, Display.replace) END;
			w := f.text.width; l2 := (H - 2 * VSpace - 1) DIV f.lineH;
			f.Y := Y; f.H := H;
			IF l2 > Terminals.Height THEN l2 := Terminals.Height END;
			WHILE l1 < l2 DO INC(l1); UpdateLine(f, l1, 1, w) END
		END;
		DrawCursor(f, cursor.line, cursor.col, f.cursorState)
	END Modify;

	PROCEDURE Handle*(f: Objects.Object; VAR m: Objects.ObjMsg);
		VAR nF: Frame;
	BEGIN
		WITH f: Frame DO
			IF m IS UpdateMsg THEN
				WITH m: UpdateMsg DO
					IF m.text = f.text THEN Update(f, m.op, m.fromLine, m.fromCol, m.toLine, m.toCol, m.oldCur) END
				END
			ELSIF m IS Objects.CopyMsg THEN
				WITH m: Objects.CopyMsg DO
					IF f.stamp # m.stamp THEN NEW(nF); Copy(f, nF); m.obj := nF; f.dlink := nF; f.stamp := m.stamp;
					ELSE m.obj := f.dlink END;
				END
			ELSIF m IS Display.ModifyMsg THEN
				WITH m: Display.ModifyMsg DO IF m.F = f THEN Modify(f, m.id, m.Y, m.H, m.dY) END END
			ELSIF m IS Oberon.InputMsg THEN
				WITH  m: Oberon.InputMsg DO
					IF m.id = Oberon.track THEN Edit(f, m.keys, m.X, m.Y)
					ELSIF (m.id = Oberon.consume) & (f.cursorState = FullCursor) THEN Terminals.Send(f.text, m.ch)
					END
				END
			ELSIF m IS Oberon.ControlMsg THEN
				WITH m: Oberon.ControlMsg DO
					IF m.id = Oberon.neutralize THEN Neutralize(f)
					ELSIF m.id = Oberon.defocus THEN SetCursor(f, FadedCursor)
					END
				END
			ELSIF (m IS Oberon.ConsumeMsg) & (f.cursorState = FullCursor) THEN
				WITH m: Oberon.ConsumeMsg DO Terminals.SendText(f.text, m.text, m.beg, m.end) END
			ELSIF m IS Oberon.SelectMsg THEN
				WITH m: Oberon.SelectMsg DO
					IF m.id = Objects.get THEN
						IF f.hasSel & (m.time < f.selTime) THEN GetSelection(f, m.text, m.beg, m.end, m.time) END
					END
				END
			END
		END
	END Handle;

	PROCEDURE New*(t: Terminals.Terminal): Frame;
		VAR f: Frame;
	BEGIN NEW(f); Open(f, Handle, t, Fonts.This("Courier10.Scn.Fnt")); RETURN f
	END New;

BEGIN Texts.OpenWriter(w)
END TerminalFrames.
