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

MODULE Terminals;	(** portable *) (* gri/ww 5 Jun 92 *)

	IMPORT Texts;

	CONST
	(* geometry *)
		Height* = 58; MaxWidth* = 132;
		
	(* attributes *)
		none* = 0; bold* = 1; underline* = 2; blinking* = 4; reverse* = 8;
		
	(* notifier id's *)
		update* = 1; moveCursor* = 2; scroll* = 3;
		
	(* control characters *)
		ENQ = 5X; BS = 08X; HT = 09X; LF = 0AX; VT = 0BX; FF = 0CX; CR = 0DX;
		CAN = 18X; SUB = 1AX; ESC = 1BX; DEL = 7FX;
		
	(* flags *)
		ansi* = 0; applic* = 1; lineFeed* = 2; insert* = 3; relative* = 4; cursorKeys* = 5; autowrap* = 6;

	TYPE
		Char* = RECORD ch*: CHAR; attr*: SHORTINT END;

		Line* = POINTER TO RECORD
			len*: INTEGER;
			ch*: ARRAY MaxWidth + 1 OF Char
		END;

		Location* = RECORD
			line*, col*: INTEGER
		END;

		Terminal* = POINTER TO TerminalDesc;

		Sender* = PROCEDURE (T: Terminal; ch: CHAR);

		Breaker* = PROCEDURE (T: Terminal);

		Notifier* = PROCEDURE (T: Terminal; op, fromLine, fromCol, toLine, toCol: INTEGER; oldCursor: Location);

		TerminalDesc* = RECORD
		(* text *)
			attr*: SHORTINT;
			width*, height* : INTEGER;
			top, bottom: INTEGER;
			cursor*: Location;
			wrapBefore: BOOLEAN;
			notify*: Notifier;
			line*: ARRAY Height + 1 OF Line;

		(* state machine *)
			flags*: SET;
			send: Sender;
			break: Breaker;
			state, parPos, strPos: INTEGER;
			parBuf: ARRAY 32 OF CHAR;
			strBuf: ARRAY 256 OF CHAR;
			tabs: ARRAY MaxWidth+1 OF BOOLEAN;
			answerback*: ARRAY 32 OF CHAR;
			oldAttr: SHORTINT;
			oldCursor: Location;
			oldRelative: BOOLEAN;
			cache*: Texts.Writer;
			text*: Texts.Text;
			pin*: LONGINT;
		END;


(* text operations *)

	PROCEDURE MoveLines (t: Terminal; top, bot, dH: INTEGER);
		VAR i, j, d, s, from, to: INTEGER; line: Line; buf: ARRAY Height OF Line;
	BEGIN
		IF (dH # 0) & (top <= bot) THEN
			IF top < 1 THEN top := 1 END;
			IF bot > t.height THEN bot := t.height END;
			IF dH < 0 THEN d := 1; from := top - dH; to := top; s := bot ELSE d := -1; from := bot - dH; to := bot; s := top END;
			i := to; j := 0;
			REPEAT line := t.line[i]; line.len := 0; buf[j] := line; i := i + d; INC(j) UNTIL i = from;
			s := s + d;
			WHILE from # s DO t.line[to] := t.line[from]; to := to + d; from := from + d END;
			j := 0; s := ABS(dH);
			REPEAT t.line[to] := buf[j]; to := to + d; INC(j) UNTIL j = s;
			t.notify(t, scroll, top, dH, bot, 0, t.cursor)
		END
	END MoveLines;

	PROCEDURE Erase (t: Terminal; fromLine, fromCol, toLine, toCol: INTEGER); (* [from, to] *)
		VAR line: Line; i, j, len: INTEGER; char: Char;
	BEGIN char.ch := " "; char.attr := none; line := t.line[fromLine]; len := line.len;
		IF fromLine = toLine THEN
			IF fromCol <= len THEN
				IF toCol > len THEN line.len := fromCol - 1
				ELSE j := fromCol;
					WHILE j <= toCol DO line.ch[j] := char; INC(j) END
				END
			END
		ELSE
			IF fromCol <= len THEN line.len := fromCol - 1 END;
			j := fromLine + 1;
			WHILE j < toLine DO t.line[j].len := 0; INC(j) END;
			line := t.line[toLine]; len := line.len;
			IF toCol >= len THEN line.len := 0
			ELSE i := 1;
				WHILE i <= toCol DO line.ch[i].ch := " "; INC(i) END
			END
		END;
		t.notify(t, update, fromLine, fromCol, toLine, toCol, t.cursor)
	END Erase;

	PROCEDURE DeleteChars (t: Terminal; n: INTEGER); (* including cursor character *)
		VAR c, j, len: INTEGER; line: Line; cursor: Location;
	BEGIN cursor := t.cursor; c := cursor.col; line := t.line[cursor.line]; j := c + n; len := line.len;
		IF j <= len THEN
			REPEAT line.ch[c] := line.ch[j]; INC(c); INC(j) UNTIL j > len;
			line.len := c - 1;
			t.notify(t, update, cursor.line, cursor.col, cursor.line, len, cursor)
		END
	END DeleteChars;

	PROCEDURE DeleteLines (t: Terminal; n: INTEGER); (* including cursor line *)
		VAR top, bot: INTEGER;
	BEGIN top := t.cursor.line; bot := t.bottom;
		IF bot - top + 1 < n THEN n := bot - top + 1 END;
		MoveLines(t, t.cursor.line, t.bottom, -n)
	END DeleteLines;

	PROCEDURE InsertChars (t: Terminal; n: INTEGER); (* move including cursor character, cursor not moved *)
		VAR i, j, len: INTEGER; line: Line; char: Char; cursor: Location;
	BEGIN cursor := t.cursor; line := t.line[cursor.line]; len := line.len; j := len + n;
		IF j >= t.width THEN j := t.width END;
		i := j - n;
		IF i < cursor.col THEN
			IF len >= cursor.col THEN line.len := cursor.col - 1 END
		ELSE line.len := j;
			REPEAT line.ch[j] := line.ch[i]; DEC(i); DEC(j) UNTIL i < cursor.col;
			char.ch := " "; char.attr := none;
			WHILE j >= cursor.col DO line.ch[j] := char; DEC(j) END
		END;
		t.notify(t, update, cursor.line, cursor.col, cursor.line, line.len, cursor)
	END InsertChars;

	PROCEDURE InsertLines (t: Terminal; n: INTEGER); (* move including cursor line, cursor not moved *)
		VAR top, bot: INTEGER;
	BEGIN top := t.cursor.line; bot := t.bottom;
		IF bot - top + 1 < n THEN n := bot - top + 1 END;
		MoveLines(t, top, bot, n)
	END InsertLines;

	PROCEDURE Scroll (t: Terminal; up: BOOLEAN); (* scroll one line within margins *)
	BEGIN
		IF up THEN MoveLines(t, t.top, t.bottom, -1) ELSE MoveLines(t, t.top, t.bottom, 1) END
	END Scroll;

	PROCEDURE SetCursor (t: Terminal; line, col: INTEGER; relative: BOOLEAN); (* (1, 1) means upper, left corner *)
		VAR newLoc: Location;
	BEGIN
		IF relative THEN
			IF line < t.top THEN line := t.top ELSIF line > t.bottom THEN line := t.bottom END
		ELSE
			IF line < 1 THEN line := 1 ELSIF line > t.height THEN line := t.height END
		END;
		IF col < 1 THEN col := 1 ELSIF col > t.width THEN col := t.width END;
		newLoc.line := line; newLoc.col := col;
		t.notify(t, moveCursor, t.cursor.line, t.cursor.col, line, col, newLoc);
		t.cursor := newLoc; t.wrapBefore := FALSE
	END SetCursor;

	PROCEDURE SetMargins (t: Terminal; top, bottom: INTEGER); (* [top, bottom] *)
	BEGIN t.top := top; t.bottom := bottom
	END SetMargins;

	PROCEDURE SetWidth (t: Terminal; width: INTEGER);
		VAR i: INTEGER;
	BEGIN t.width := width; i := 1;
		WHILE i <= t.height DO
			IF t.line[i].len > width THEN t.line[i].len := width END;
			INC(i)
		END;
		IF t.cursor.col > width THEN t.cursor.col := width END;
		t.notify(t, update, 1, 1, t.height, t.width, t.cursor)
	END SetWidth;

	PROCEDURE SetAttribute (t: Terminal; attr: SHORTINT);
	BEGIN
		IF attr = none THEN t.attr := attr ELSE t.attr := t.attr + attr END
	END SetAttribute;

	PROCEDURE PutChar(t: Terminal; VAR cursor: Location; VAR wrapBefore: BOOLEAN; ch: Char; VAR dH: INTEGER);
		VAR len: INTEGER; line: Line; char: Char;
	BEGIN
		IF wrapBefore THEN
			IF cursor.col = t.width THEN INC(cursor.line); cursor.col := 1;
				IF cursor.line > t.bottom THEN Scroll(t, TRUE); DEC(cursor.line); DEC(dH) END
			ELSE INC(cursor.col)
			END
		END;
		line := t.line[cursor.line]; len := line.len;
		IF (ch.ch = " ") & (ch.attr = none) & (cursor.col = len) THEN DEC(line.len)
		ELSIF (ch.ch # " ") OR (ch.attr # none) OR (cursor.col < len) THEN
			IF len <= cursor.col THEN line.len := cursor.col; char.ch := " "; char.attr := none; INC(len);
				WHILE len < cursor.col DO line.ch[len] := char; INC(len) END
			END;
			line.ch[cursor.col] := ch
		END;
		IF cursor.col = t.width THEN wrapBefore := autowrap IN t.flags
		ELSE INC(cursor.col); wrapBefore := FALSE
		END
	END PutChar;

	PROCEDURE WriteString (t: Terminal; s: ARRAY OF CHAR; n: INTEGER); (* writes n characters at curs. pos. *)
		VAR i, dH: INTEGER; cursor, oldCur: Location; char: Char;
	BEGIN cursor := t.cursor;
		oldCur := cursor; char.attr := t.attr; dH := 0; i := 0;
		WHILE i < n DO char.ch := s[i]; PutChar(t, cursor, t.wrapBefore, char, dH); INC(i) END;
		t.cursor := cursor;
		IF oldCur.line + dH < 1 THEN t.notify(t, update, 1, oldCur.col, cursor.line, cursor.col, oldCur)
		ELSE t.notify(t, update, oldCur.line + dH, oldCur.col, cursor.line, cursor.col, oldCur)
		END
	END WriteString;

	PROCEDURE EFill (t: Terminal);
		VAR i, j, w: INTEGER; line: Line; char: Char;
	BEGIN i := 1; w := t.width; char.ch := "E"; char.attr := none;
		WHILE i <= t.height DO j := 1; line := t.line[i]; line.len := w;
			WHILE j <= w DO line.ch[j] := char; INC(j) END;
			INC(i)
		END;
		t.notify(t, update, 1, 1, t.height, t.width, t.cursor)
	END EFill;


(* sequence interpretation *)

	PROCEDURE DelLast (T: Terminal);
	BEGIN
		IF T.cache.buf.len > 0 THEN Texts.Append(T.text, T.cache.buf) END;
		IF T.text.len > 0 THEN Texts.Delete(T.text, T.text.len-1, T.text.len) END
	END DelLast;

	PROCEDURE Reset* (T: Terminal);
		VAR i: INTEGER;
	BEGIN
		T.flags := {ansi, autowrap}; T.state := 0; T.strPos := 0; i := 1;
		WHILE i <= MaxWidth DO T.tabs[i] := i MOD 8 = 1; INC(i) END;
		T.answerback := "*** Hello World ***";
		T.oldAttr := none; T.oldCursor.line := 1; T.oldCursor.col := 1; T.oldRelative := FALSE;
		Erase(T, 1, 1, T.height, T.width);
		SetMargins(T, 1, T.height);
		SetCursor(T, 1, 1, FALSE)
	END Reset;

	PROCEDURE SendStr (T: Terminal; s: ARRAY OF CHAR);
		VAR i: INTEGER;
	BEGIN i := 0;
		WHILE s[i] # 0X DO T.send(T, s[i]); INC(i) END
	END SendStr;
	
	PROCEDURE SendInt (T: Terminal; x: INTEGER);
		VAR i: INTEGER; d: ARRAY 3 OF CHAR;
	BEGIN i := 0;
		REPEAT d[i] := CHR(x MOD 10 + ORD("0")); x := x DIV 10;  INC(i) UNTIL x = 0;
		WHILE i > 0 DO DEC(i); T.send(T, d[i]) END
	END SendInt;

	PROCEDURE Update (T: Terminal);
	BEGIN IF T.strPos > 0 THEN WriteString(T, T.strBuf, T.strPos); T.strPos := 0 END
	END Update;

	PROCEDURE Flush* (T: Terminal);
	BEGIN Update(T);
		IF (T.text # NIL) & (T.cache.buf.len > 0) THEN Texts.Append(T.text, T.cache.buf) END
	END Flush;

	PROCEDURE Write (T: Terminal; ch: CHAR);
	BEGIN
		IF T.strPos >= LEN(T.strBuf) THEN Update(T) END;
		T.strBuf[T.strPos] := ch; INC(T.strPos)
	END Write;

	PROCEDURE ESCSequence (T: Terminal; last: CHAR);
		VAR ch: CHAR;
	BEGIN ch := T.parBuf[0];
		IF ansi IN T.flags THEN
			IF ("7" <= last) & (last <= "c") THEN
				CASE last OF
					| "7": T.oldAttr := T.attr; T.oldCursor := T.cursor; T.oldRelative := relative IN T.flags
					| "8":
						IF ch = "#" THEN EFill(T)
						ELSE SetAttribute(T, T.oldAttr);
							SetCursor(T, T.oldCursor.line, T.oldCursor.col, FALSE);
							IF T.oldRelative THEN INCL(T.flags, relative)
							ELSE EXCL(T.flags, relative)
							END
						END
					| "=": INCL(T.flags, applic)
					| ">": EXCL(T.flags, applic)
					| "D":
						IF T.cursor.line = T.bottom THEN Scroll(T, TRUE)
						ELSE SetCursor(T, T.cursor.line+1, T.cursor.col, FALSE)
						END
					| "E":
						IF T.cursor.line = T.bottom THEN Scroll(T, TRUE); SetCursor(T, T.cursor.line, 1, FALSE)
						ELSE SetCursor(T, T.cursor.line+1, 1, FALSE)
						END
					| "H": T.tabs[T.cursor.col] := TRUE
					| "M":
						IF T.cursor.line = T.top THEN Scroll(T, FALSE)
						ELSE SetCursor(T, T.cursor.line-1, T.cursor.col, relative IN T.flags)
						END
					| "Z": T.send(T, ESC); SendStr(T, "[?1;2c") (* VT100 *)
					| "c": Reset(T)
					| "9" .. "<", "?" .. "C", "F", "G", "I" .. "L", "N" .. "Y", "[" .. "b": (* ignore *)
				END
			END
		ELSE (* VT52 mode *)
			IF ("<" <= last) & (last <= "Z") THEN
				CASE last OF
					| "<": INCL(T.flags, ansi)
					| "=": INCL(T.flags, applic)
					| ">": EXCL(T.flags, applic)
					| "A": SetCursor(T, T.cursor.line-1, T.cursor.col, FALSE)
					| "B": SetCursor(T, T.cursor.line+1, T.cursor.col, FALSE)
					| "C": SetCursor(T, T.cursor.line, T.cursor.col+1, FALSE)
					| "D": SetCursor(T, T.cursor.line, T.cursor.col-1, FALSE)
					| "H": SetCursor(T, 1, 1, FALSE)
					| "I":
						IF T.cursor.line = 1 THEN Scroll(T, FALSE)
						ELSE SetCursor(T, T.cursor.line-1, T.cursor.col, FALSE)
						END
					| "J": Erase(T, T.cursor.line, T.cursor.col, T.height, T.width)
					| "K": Erase(T, T.cursor.line, T.cursor.col, T.cursor.line, T.width)
					| "Z": T.send(T, ESC); SendStr(T, "/Z")
					| "?", "@", "E" .. "G", "L" .. "Y", "[", "\": (* ignore *)
				END
			END
		END
	END ESCSequence;

	PROCEDURE CSISequence (T: Terminal; last: CHAR);
		VAR ch: CHAR; pos, p1, p2: INTEGER;
	
		PROCEDURE Next;
		BEGIN ch := T.parBuf[pos]; INC(pos)
		END Next;
	
		PROCEDURE Par (zeroVal: INTEGER): INTEGER;
			VAR x: INTEGER;
		BEGIN x := 0;
			IF ("0" <= ch) & (ch <= "9") THEN x := ORD(ch) - ORD("0"); Next;
				WHILE ("0" <= ch) & (ch <= "9") & (x <= (MAX(INTEGER) - 9) DIV 10) DO
					x := 10*x + ORD(ch) - ORD("0"); Next
				END;
				WHILE ("0" <= ch) & (ch <= "9") DO Next END;
				IF ch = ";" THEN Next END
			ELSIF ch = ";" THEN Next
			END;
			IF x = 0 THEN x := zeroVal END;
			RETURN x
		END Par;

	BEGIN T.parBuf[T.parPos] := 0FFX; pos := 0; Next;
		IF ( "@" <= last) & (last <= "y") THEN
			CASE last OF
				| "@": InsertChars(T, Par(1))
				| "A": SetCursor(T, T.cursor.line - Par(1), T.cursor.col, relative IN T.flags)
				| "B": SetCursor(T, T.cursor.line + Par(1), T.cursor.col, relative IN T.flags)
				| "C": SetCursor(T, T.cursor.line, T.cursor.col + Par(1), relative IN T.flags)
				| "D": SetCursor(T, T.cursor.line, T.cursor.col - Par(1), relative IN T.flags)
				| "H", "f":
					p1 := Par(1); p2 := Par(1);
					IF relative IN T.flags THEN SetCursor(T, T.top + p1 - 1, p2, TRUE)
					ELSE  SetCursor(T, p1, p2, FALSE)
					END
				| "J":
					p1 := Par(0);
					IF p1 = 0 THEN Erase(T, T.cursor.line, T.cursor.col, T.height, T.width)
					ELSIF p1 = 1 THEN Erase(T, 1, 1, T.cursor.line, T.cursor.col)
					ELSIF p1 = 2 THEN Erase(T, 1, 1, T.height, T.width)
					END
				| "K":
					p1 := Par(0);
					IF p1 = 0 THEN Erase(T, T.cursor.line, T.cursor.col, T.cursor.line, T.width)
					ELSIF p1 = 1 THEN Erase(T, T.cursor.line, 1, T.cursor.line, T.cursor.col)
					ELSIF p1 = 2 THEN Erase(T, T.cursor.line, 1, T.cursor.line, T.width)
					END
				| "L": InsertLines(T, Par(1))
				| "M": DeleteLines(T, Par(1))
				| "P": DeleteChars(T, Par(1))
				| "c": IF Par(0) = 0 THEN T.send(T, ESC); SendStr(T, "[?1;2c") (* VT100 *) END
				| "g":
					REPEAT p1 := Par(0);
						IF p1 = 0 THEN T.tabs[T.cursor.col] := FALSE
						ELSIF p1 = 3 THEN p1 := 1;
							WHILE p1 <= MaxWidth DO T.tabs[p1] := FALSE; INC(p1) END
						END
					UNTIL pos > T.parPos
				| "h":
					IF ch = "?" THEN Next;
						REPEAT p1 := Par(0);
							IF p1 = 1 THEN INCL(T.flags, cursorKeys)
							ELSIF p1 = 3 THEN
								Erase(T, 1, 1, T.height, T.width);
								SetWidth(T, MaxWidth);
								SetMargins(T, 1, T.height);
								SetCursor(T, 1, 1, relative IN T.flags)
							ELSIF p1 = 6 THEN INCL(T.flags, relative); SetCursor(T, 1, 1, TRUE)
							ELSIF p1 = 7 THEN INCL(T.flags, autowrap)
							END
						UNTIL pos > T.parPos
					ELSE
						REPEAT p1 := Par(0);
							IF p1 = 4 THEN INCL(T.flags, insert)
							ELSIF p1 = 20 THEN INCL(T.flags, lineFeed)
							END
						UNTIL pos > T.parPos
					END
				| "l":
					IF ch = "?" THEN Next;
						REPEAT p1 := Par(0);
							IF p1 = 1 THEN EXCL(T.flags, cursorKeys)
							ELSIF p1 = 2 THEN EXCL(T.flags, ansi)
							ELSIF p1 = 3 THEN
								Erase(T, 1, 1, T.height, T.width);
								SetWidth(T, 80);
								SetMargins(T, 1, T.height);
								SetCursor(T, 1, 1, relative IN T.flags)
							ELSIF p1 = 6 THEN EXCL(T.flags, relative); SetCursor(T, 1, 1, FALSE)
							ELSIF p1 = 7 THEN EXCL(T.flags, autowrap)
							END
						UNTIL pos > T.parPos
					ELSE
						REPEAT p1 := Par(0);
							IF p1 = 4 THEN EXCL(T.flags, insert)
							ELSIF p1 = 20 THEN EXCL(T.flags, lineFeed)
							END
						UNTIL pos > T.parPos
					END
				| "m":
					REPEAT p1 := Par(0);
						IF p1 = 0 THEN SetAttribute(T, none)
						ELSIF p1 = 1 THEN SetAttribute(T, bold)
						ELSIF p1 = 4 THEN SetAttribute(T, underline)
						ELSIF p1 = 5 THEN SetAttribute(T, blinking)
						ELSIF p1 = 7 THEN SetAttribute(T, reverse)
						END
					UNTIL pos > T.parPos
				| "n":
					IF ch = "?" THEN Next;
						IF Par(0) = 15 THEN (* printer status report *) T.send(T, ESC); SendStr(T, "[?13n") END
					ELSE p1 := Par(0);
						IF p1 = 5 THEN (* terminal status report *) T.send(T, ESC); SendStr(T, "[0n")
						ELSIF p1 = 6 THEN (* cursor position report *)
							T.send(T, ESC); T.send(T, "[");
							IF relative IN T.flags THEN SendInt(T, T.cursor.line - T.top + 1) 
							ELSE SendInt(T, T.cursor.line) 
							END;
							T.send(T, ";"); SendInt(T, T.cursor.col); T.send(T, "R")
						END
					END
				| "r":
					p1 := Par(0); p2 := Par(0);
					IF (p1 = 0) & (p2 = 0) THEN p1 := 1; p2 := T.height END;
					SetMargins(T, p1, p2);
					SetCursor(T, 1, 1, TRUE)
				|"y":
					p1 := Par(0);
					IF p1 = 2 THEN p1 := Par(0);
						IF p1 = 1 THEN Reset(T)
						ELSE T.send(T, ESC); SendStr(T, "[0n")
						END 
					END
				| "E" .. "G", "I", "N", "O", "Q" .. "b", "d", "e", "i" .. "k", "o" .. "q", "s" .. "x": (* ignore *)
			END
		END
	END CSISequence;

	PROCEDURE Receive* (T: Terminal; ch: CHAR);
		VAR p: INTEGER;
	BEGIN
		ch := CHR(ORD(ch) MOD 128);
		IF ch < " " THEN (* interpret control characters immediately *)
			CASE ch OF
				| ENQ: SendStr(T, T.answerback)
				| BS:
					Update(T); SetCursor(T, T.cursor.line, T.cursor.col-1, FALSE);
					IF T.text # NIL THEN DelLast(T) END
				| HT:
					Update(T); p := T.cursor.col + 1;
					WHILE (p <= T.width) & ~T.tabs[p] DO INC(p) END;
					SetCursor(T, T.cursor.line, p, FALSE);
					IF T.text # NIL THEN Texts.Write(T.cache, HT) END
				| LF, VT, FF:
					Update(T);
					IF T.cursor.line = T.bottom THEN Scroll(T, TRUE);
						IF lineFeed IN T.flags THEN SetCursor(T, T.cursor.line, 1, FALSE) END
					ELSIF lineFeed IN T.flags THEN SetCursor(T, T.cursor.line+1, 1, FALSE)
					ELSE SetCursor(T, T.cursor.line+1, T.cursor.col, FALSE)
					END;
					IF T.text # NIL THEN Texts.Write(T.cache, CR) END
				| CR: Update(T); SetCursor(T, T.cursor.line, 1, FALSE)
				| CAN, SUB: (* cancel *) T.state := 0
				| ESC: T.state := 1
				| 0X .. 4X, 6X, 7X, 0EX .. 17X, 19X, 1CX .. 1FX: (* ignore *)
			END
		ELSE (* drive state machine *)
			CASE T.state OF
				| 0: (* normal characters *)
					IF ch = DEL THEN
						IF T.cursor.col > 1 THEN Update(T);
							SetCursor(T, T.cursor.line, T.cursor.col-1, FALSE);
							DeleteChars(T, 1)
						END;
						IF T.text # NIL THEN DelLast(T) END
					ELSE
						IF insert IN T.flags THEN Update(T); InsertChars(T, 1) END;
						Write(T, ch);
						IF T.text # NIL THEN Texts.Write(T.cache, ch) END
					END
				| 1: (* sequence introduction *)
					IF ch = "[" THEN T.state := 3; T.parPos := 0;
					ELSIF ~(ansi IN T.flags) & (ch = "Y") THEN T.state := 4; T.parPos := 0
					ELSIF (" " <= ch) & (ch <= "/") THEN T.state := 2; T.parBuf[0] := ch; T.parPos := 1
					ELSIF ("0" <= ch) & (ch <= "~") THEN T.state := 2; T.parPos := 0; Update(T); ESCSequence(T, ch); T.state := 0
					ELSE (* error *) T.state := 0
					END
				| 2: (* ESC sequence *)
					IF ("0" <= ch) & (ch <= "~") THEN Update(T); ESCSequence(T, ch); T.state := 0
					ELSIF T.parPos < LEN(T.parBuf) THEN T.parBuf[T.parPos] := ch; INC(T.parPos)
					ELSE (* error *) T.state := 0
					END
				| 3: (* CSI sequence *)
					IF ("@" <= ch) & (ch <= "~") THEN Update(T); CSISequence(T, ch); T.state := 0
					ELSIF T.parPos < LEN(T.parBuf) THEN T.parBuf[T.parPos] := ch; INC(T.parPos)
					ELSE (* error *) T.state := 0
					END
				| 4: (* VT52 ESC Y sequence *)
					IF T.parPos = 0 THEN T.parBuf[0] := ch; T.parPos := 1
					ELSE Update(T); SetCursor(T, ORD(T.parBuf[0])-31, ORD(ch)-31, FALSE); T.state := 0
					END
			END
		END
	END Receive;

	PROCEDURE Send* (T: Terminal; ch: CHAR);
	BEGIN
		IF T.text # NIL THEN T.pin := T.text.len END;
		IF ch <= DEL THEN (* normal ASCII *) T.send(T, ch);
			IF (ch = CR) & (lineFeed IN T.flags) THEN T.send(T, LF) END
		ELSIF ch = 0A9X THEN T.break(T)	(* end *)
		ELSIF ch = 0A8X THEN SendStr(T, T.answerback)	(* home *)
		ELSIF (0C1X <= ch) & (ch <= 0C4X) THEN (* cursor keys *) T.send(T, ESC);
			IF ansi IN T.flags THEN
				IF cursorKeys IN T.flags THEN T.send(T, "O") ELSE T.send(T, "[") END
			END;
			T.send(T, CHR(ORD(ch) - 128))
		END
	END Send;
	
	PROCEDURE SendString* (T: Terminal; VAR s: ARRAY OF CHAR);
		VAR i: INTEGER;
	BEGIN i := 0;
		WHILE s[i] # 0X DO Send(T, s[i]); INC(i) END
	END SendString;

	PROCEDURE SendText* (T: Terminal; text: Texts.Text; beg, end: LONGINT);
		VAR R: Texts.Reader; ch: CHAR;
	BEGIN Texts.OpenReader(R, text, beg);
		WHILE Texts.Pos(R) < end DO Texts.Read(R, ch); Send(T, ch) END
	END SendText;

	PROCEDURE Open* (T: Terminal; text: Texts.Text; send: Sender; break: Breaker; notify: Notifier; height : INTEGER);
		VAR l: Line; i: INTEGER;
	BEGIN T.width := 80; 
		IF height < Height THEN T.height := height ELSE T.height := Height-1 END;
		T.top := 1; T.bottom := T.height; T.cursor.line := 1; T.cursor.col := 1;
		T.attr := none; T.wrapBefore := FALSE; T.notify := notify;
		i := Height;
		REPEAT NEW(l); T.line[i] := l ; DEC(i) UNTIL i = 0;
		Reset(T); T.text := text; Texts.OpenWriter(T.cache); T.pin := 0;
		T.send := send; T.break := break 
	END Open;

END Terminals.
