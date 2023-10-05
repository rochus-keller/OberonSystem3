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

MODULE Lists;	(** portable *) (* jm 18.4.95 *)

(** Implementation of scrollable lists.
*)
(*
	6.5.94 - No more duplicates are allowed in the lists
	4.11.94 - added support for LinkMsg, name = Model
	7.11.94 - allow setting of the Sel attribute
	6.12.94 added sorted attribute (ejz)
	17.1.95 - added support for strange diskette file names
	9.2.95 - Improved InsertItem
	18.4.94 - changed scrolling behaviour
	15.5.95 - changed scrolling behaviour back
	9.5.95 - changed copy over, now works even when focus ist alredy set (ps - 9.5.96)
*)
IMPORT Files, Fonts, Display, Display3, Printer, Printer3, Effects, Objects, Gadgets, Oberon, Input, Texts, Attributes, FileDir,
	Floppy := Diskette;
	
CONST
	barw = 18;
	
TYPE
	Bar = RECORD
		bg, box: INTEGER;
		range, size, pos: LONGINT;
	END;

	Item* = POINTER TO ItemDesc;
	ItemDesc* = RECORD
		sel*: BOOLEAN;	(** Is the list item selected ? *)
		s*: ARRAY 64 OF CHAR;	(** Item value. *)
		prev*, next*: Item;
	END;

	List* = POINTER TO ListDesc;
	ListDesc* = RECORD (Gadgets.FrameDesc)
		items*, last*: Item;	(** First and last element of list of items. *)
		beg*: Item;	(** First item displayed in list. *)
		pointed*: Item;	(** Item pointed at last with the middle mouse button. *)
		time*: LONGINT;	(** Selection time. *)
		focus*: BOOLEAN;	(** Is the list focused ? *)
		sorted*: BOOLEAN;	(** Are list entries sorted ? *)
		noitems*: INTEGER;	(** Number of entries in the list. *)
		cmd*: ARRAY 64 OF CHAR;	(** Cmd command attribute. *)
		scrollbar*: BOOLEAN;	(** Does the list have a scrollbar ? *)
		bar: Bar;
	END;

VAR
	W: Texts.Writer;
	mayscroll, waittime: LONGINT;
	pat, ss: ARRAY 32 OF CHAR;
	pos: INTEGER;

(* ---------------------- SLIDER ------------------------- *)

PROCEDURE Dot(R: Display3.Mask; x, y: INTEGER);
VAR c: INTEGER;

	PROCEDURE D(col: INTEGER);
	BEGIN Display3.Dot(R, col, x, y, Display.replace);
		INC(c); INC(x); IF c MOD 4 = 0 THEN INC(y); DEC(x, 4); END;
	END D;
	
BEGIN
	c := 0;
	D(14); D(13); D(12); D(13);
	D(14); D(14); D(13); D(12);
	D(0); D(14); D(14); D(13);
	D(13); D(0); D(14); D(14);
END Dot;

PROCEDURE Knob(M: Display3.Mask; x, y, w, h: INTEGER);
BEGIN
	Display3.FilledRect3D(M, Display3.topC, Display3.bottomC, Display3.groupC, x, y, w, h, 1, Display.replace);
	Dot(M, x + w DIV 2 - 2, y + h DIV 2 - 2)
END Knob;

PROCEDURE DrawSlider(M: Display3.Mask; VAR bar: Bar; x, y, w, h: INTEGER);
VAR barlen, min, max, pos: LONGINT; i: INTEGER;
BEGIN
	(* border *)
	Oberon.RemoveMarks(x, y, w, h);
	Display3.Rect3D(M, Display3.bottomC, Display3.topC, x, y, w, h, 1, Display.replace);
	IF w > h THEN
		barlen := (w - bar.box * 2) * bar.size DIV bar.range; (* length of bar *)
		IF barlen < 6 THEN barlen := 6 END;
		(* min & max *)
		min := x + bar.box; max := x + w - bar.box - barlen;
		
		(* The following tests are due to rounding problems at the end of the range *)
		IF bar.pos <= 0 THEN pos := min
		ELSIF bar.pos >= bar.range - 1 THEN pos := max
		ELSE pos := min + (max - min + 1) * bar.pos DIV bar.range
		END;

		Display3.FilledRect3D(M, Display3.topC, Display3.bottomC, Display3.groupC, x + 1, y + 1, bar.box - 2, h - 2, 1, Display.replace); (* box inside *)
		Display3.ReplConst(M, Display3.FG, x + bar.box - 1, y + 1, 1, h - 2, Display.replace); (* box border *)
		
		Display3.FilledRect3D(M, Display3.topC, Display3.bottomC, Display3.groupC, x + w - bar.box + 1, y + 1, bar.box - 2, h - 2, 1, Display.replace); (* box inside *)
		Display3.ReplConst(M, Display3.FG, x + w - bar.box, y + 1, 1, h - 2, Display.replace); (* box border *)
		
		(* Triangles *)
		FOR i := -4 TO 1 DO
			Display3.ReplConst(M, Display3.FG, x + bar.box DIV 3 - i, y + h DIV 2 + i, 1, -i*2, Display.replace);
			Display3.ReplConst(M, Display3.FG, x + w -  bar.box DIV 3 + i, y + h DIV 2 + i, 1, -i*2, Display.replace);
		END;
		
		(* inside *)
		Display3.ReplConst(M, bar.bg, x + bar.box, y + 1, w - bar.box * 2, h - 2, Display.replace);
		
		(* draw bar *)
		Knob(M, SHORT(pos), y + 1, SHORT(barlen), h - 2);
	ELSE
		barlen := (h - bar.box * 2) * bar.size DIV bar.range; (* length of bar *)
		IF barlen < 6 THEN barlen := 6 END;
		(* min & max *)
		min := y + bar.box; max := y + h - bar.box - barlen;
		
		(* The following tests are due to rounding problems at the end of the range *)
		IF bar.pos <= 0 THEN pos := max
		ELSIF bar.pos >= bar.range - 1 THEN pos := min
		ELSE pos := min + (max - min + 1) * (bar.range - 1 - bar.pos) DIV bar.range
		END;

		Display3.FilledRect3D(M, Display3.topC, Display3.bottomC, Display3.groupC, x + 1, y + 1, w-2, bar.box - 2, 1, Display.replace); (* box inside *)
		Display3.ReplConst(M, Display3.FG, x + 1, y + bar.box - 1, w-2, 1, Display.replace); (* box border *)
		
		Display3.FilledRect3D(M, Display3.topC, Display3.bottomC, Display3.groupC, x + 1, y + h - bar.box + 1, w - 2, bar.box - 2, 1, Display.replace); (* box inside *)
		Display3.ReplConst(M, Display3.FG, x + 1, y + h - bar.box, w - 2, 1, Display.replace); (* box border *)
		
		(* Triangles *)
		FOR i := -4 TO 1 DO
			Display3.ReplConst(M, Display3.FG, x + w DIV 2 + i, y + bar.box DIV 3 - i, -i*2, 1, Display.replace);
			Display3.ReplConst(M, Display3.FG, x + w DIV 2 + i, y + h - bar.box DIV 3 + i, -i*2, 1, Display.replace);
		END;

		(* inside *)
		Display3.ReplConst(M, bar.bg, x + 1, y + bar.box, w-2, h - bar.box * 2, Display.replace);
		
		(* draw bar *)
		Knob(M, x+1, SHORT(pos), w-2, SHORT(barlen));
	END
END DrawSlider;

PROCEDURE TrackSlider(M: Display3.Mask; VAR bar: Bar; x, y, w, h: INTEGER);
VAR keys: SET; X, Y: INTEGER; barlen, min, max, pos, npos, oldpos: LONGINT; keysum: SET;

	PROCEDURE Pushed(x, y, w, h: INTEGER): BOOLEAN;
	VAR on, newstate: BOOLEAN;
	
		PROCEDURE On(): BOOLEAN;
		BEGIN RETURN Effects.Inside(X, Y, x, y, w, h)
		END On;
		
		PROCEDURE Highlight;
		BEGIN Oberon.FadeCursor(Oberon.Mouse); Display3.ReplConst(M, Display.FG, x, y, w, h, Display.invert)
		END Highlight;
		
	BEGIN
		Input.Mouse(keys, X, Y);
		on := On(); IF on THEN Highlight END;
		keysum := keys;
		WHILE keys # {} DO
			newstate := On();
			IF newstate # on THEN on := newstate; Highlight END;
			Input.Mouse(keys, X, Y); keysum := keysum + keys;
			Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, X, Y)
		END;
		IF on THEN Highlight END;
		RETURN on & (keysum # {0, 1, 2})
	END Pushed;
	
BEGIN
	oldpos := bar.pos; (* backup *)
	IF w > h THEN
		barlen := (w - bar.box * 2) * bar.size DIV bar.range; (* length of bar *)
		IF barlen < 6 THEN barlen := 6 END;
		min := x + bar.box; max := x + w - bar.box - barlen;
		
		(* The following tests are due to rounding problems at the end of the range *)
		IF bar.pos <= 0 THEN pos := min
		ELSIF bar.pos >= bar.range - 1 THEN pos := max
		ELSE pos := min + (max - min + 1) * bar.pos DIV bar.range
		END
	ELSE
		barlen := (h - bar.box * 2) * bar.size DIV bar.range; (* length of bar *)
		IF barlen < 6 THEN barlen := 6 END;
		min := y + bar.box; max := y + h - bar.box - barlen;
		
		(* The following tests are due to rounding problems at the end of the range *)
		IF bar.pos <= 0 THEN pos := max
		ELSIF bar.pos >= bar.range - 1 THEN pos := min
		ELSE pos := min + (max - min + 1) * (bar.range - 1 - bar.pos) DIV bar.range
		END
	END;
	
	Input.Mouse(keys, X, Y);
	IF (w > h) & (X < x + bar.box) THEN (* scroll left *)
		IF Pushed(x + 1, y + 1, bar.box - 2, h - 2) THEN
			DEC(bar.pos, bar.size);
			IF bar.pos < 0 THEN bar.pos := 0 ELSIF bar.pos >= bar.range THEN bar.pos := bar.range - 1 END;
			DrawSlider(M, bar, x, y, w, h);
		END
	ELSIF (w > h) & (X > x + w - bar.box) THEN (* scroll right *)
		IF Pushed(x + w - bar.box + 1, y + 1, bar.box - 2, h - 2) THEN
			INC(bar.pos, bar.size);
			IF bar.pos < 0 THEN bar.pos := 0 ELSIF bar.pos >= bar.range THEN bar.pos := bar.range - 1 END;
			DrawSlider(M, bar, x, y, w, h);
		END
	ELSIF (w <= h) & (Y < y + bar.box) THEN (* scroll down *)
		IF Pushed(x + 1, y + 1, w-2, bar.box - 2) THEN
			INC(bar.pos, bar.size);
			IF bar.pos < 0 THEN bar.pos := 0 ELSIF bar.pos >= bar.range THEN bar.pos := bar.range - 1 END;
			DrawSlider(M, bar, x, y, w, h);
		END
	ELSIF (w <= h) & (Y > y + h - bar.box) THEN (* scroll up *)
		IF Pushed(x + 1, y + h - bar.box + 1, w - 2, bar.box - 2) THEN
			DEC(bar.pos, bar.size);
			IF bar.pos < 0 THEN bar.pos := 0 ELSIF bar.pos >= bar.range THEN bar.pos := bar.range - 1 END;
			DrawSlider(M, bar, x, y, w, h);
		END
	ELSE (* absolute scroll *)
		keysum := keys;
		WHILE keys # {} DO
			IF w > h THEN npos := X - barlen DIV 2
			ELSE npos := Y - barlen DIV 2
			END;
			IF npos < min THEN npos := min END;
			IF npos > max THEN npos := max END;
			
			IF npos # pos THEN (* new position *)
				Oberon.FadeCursor(Oberon.Mouse);
				IF w > h THEN (* horizontal *)
					IF npos > pos THEN (* move right *)
						Display3.ReplConst(M, bar.bg, SHORT(pos), y+1, SHORT(npos - pos), h - 2, Display.replace);
					ELSE (* move left *)
						Display3.ReplConst(M, bar.bg, SHORT(npos + barlen), y+1, SHORT(pos - npos), h - 2, Display.replace);
					END;
					pos := npos;
					Knob(M, SHORT(pos), y + 1, SHORT(barlen), h - 2);
					bar.pos := (pos - min + 1) * bar.range DIV (max - min + 1);
					IF bar.pos < 0 THEN bar.pos := 0 END;
					IF bar.pos > bar.range - 1 THEN bar.pos := bar.range - 1 END;
				ELSE (* vertical *)
					IF npos > pos THEN (* move up *)
						Display3.ReplConst(M, bar.bg, x+1, SHORT(pos), w-2, SHORT(npos - pos), Display.replace);
					ELSE (* move down *)
						Display3.ReplConst(M, bar.bg, x+1, SHORT(npos + barlen), w-2, SHORT(pos - npos), Display.replace);
					END;
					pos := npos;
					Knob(M, x+1, SHORT(pos), w-2, SHORT(barlen));
					bar.pos := (max - pos) * bar.range DIV (max - min + 1);
					IF bar.pos < 0 THEN bar.pos := 0 END;
					IF bar.pos > bar.range - 1 THEN bar.pos := bar.range - 1 END;
				END
			END;
			Input.Mouse(keys, X, Y); keysum := keysum + keys;
			Oberon.DrawCursor(Oberon.Mouse, Effects.FlatHand, X, Y)
		END;
		IF keysum = {0, 1, 2} THEN bar.pos := oldpos; DrawSlider(M, bar, x, y, w, h) END;
	END
END TrackSlider;

(* --------------------- CHOOSER ------------------- *)

PROCEDURE Updatebar(F: List; H: INTEGER);
VAR space: LONGINT;
BEGIN
	space := H DIV (Fonts.Default.height + 2);
	IF F.noitems <= space THEN
		F.bar.range := 1000; F.bar.size := 1000; 
	ELSE
		F.bar.range := F.noitems;
		F.bar.size :=  space
(*
		F.bar.range := F.noitems;
		F.bar.size := H DIV (Fonts.Default.height + 2);
		IF F.bar.range >= F.bar.size THEN
			old := F.bar.range;
			DEC(F.bar.range, F.bar.size - 1);
			DEC(F.bar.size,  F.bar.size * F.bar.range DIV old);
		ELSE F.bar.range := 1;
		END;
		IF F.bar.size > F.bar.range THEN F.bar.size := F.bar.range END;
*)
	END
END Updatebar;

(** Insert an item into the list. Entry comes at the end if the list is unsorted. *)
PROCEDURE InsertItem*(F: List; s: ARRAY OF CHAR);
VAR p, i, j: Item;
BEGIN
	IF F.sorted THEN
		i := F.items; p := NIL;
		IF i = NIL THEN
			NEW(j); COPY(s, j.s); j.sel := FALSE;
			F.items := j
		ELSE
			WHILE (i # NIL) & (s > i.s) DO p := i; i := i.next END;
			IF (i # NIL) & (i.s = s) THEN RETURN END; (* already in list *)
			NEW(j); COPY(s, j.s); j.sel := FALSE;
			IF p = NIL THEN
				j.next := F.items;
				IF F.items # NIL THEN F.items.prev := j; END;
				F.items := j;
			ELSE
				j.next := i; p.next := j; j.prev := p;
				IF i # NIL THEN i.prev := j END;
			END;
		END;
		INC(F.noitems)
	ELSE
		i := F.items;
		p := NIL;
		WHILE i # NIL DO p := i; i := i.next END;
		NEW(j);
		COPY(s, j.s);
		j.sel := FALSE;
		j.next := NIL;
		j.prev := p;
		IF p = NIL THEN
			F.items := j
		ELSE
			p.next := j
		END;
		INC(F.noitems)
	END;
	IF (F.beg = NIL) & (F.items # NIL) THEN F.beg := F.items END;
END InsertItem;

(** Inserts the stretch [beg, end) of text T into the list as entries. *)
PROCEDURE InsertItems*(F: List; T: Texts.Text; beg, end: LONGINT);
VAR S: Attributes.Scanner;
BEGIN
	Attributes.OpenScanner(S, T, beg);
	Attributes.Scan(S);
	WHILE (S.class = Attributes.Name) OR (S.class = Attributes.String) DO
		InsertItem(F, S.s);
		IF (S.R.text = T) & (Attributes.Pos(S.R) >= end) THEN (* base text + beyond end of selection *)
			S.class := Attributes.Inval
		ELSE Attributes.Scan(S)
		END
	END;
	F.beg := F.items; F.bar.pos := 0; (* Updatebar(F, F.H); *)
	Gadgets.Update(F);
END InsertItems;

PROCEDURE Sort(F: List);
VAR new, i, j, p, n: Item; items: INTEGER;
BEGIN
	items := 0;
	new := NIL;
	i := F.items;
	WHILE i # NIL DO
		j := new;
		p := NIL;
		WHILE (j # NIL) & (j.s < i.s) DO
			p := j;
			j := j.next
		END;
		IF (j = NIL) OR (j.s # i.s) THEN
			INC(items);
			NEW(n);
			n^ := i^;
			n.prev := p;
			IF p = NIL THEN
				n.next := new;
				IF new # NIL THEN
					new.prev := n
				END;
				new := n
			ELSE
				n.next := j;
				p.next := n;
				IF j # NIL THEN
					j.prev := n
				END
			END
		END;
		i := i.next
	END;
	F.noitems := items;
	F.items := new;
	F.beg := F.items;
	F.pointed := NIL
END Sort;

PROCEDURE ListAttr(F: List; VAR M: Objects.AttrMsg);
VAR i: Item;
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("Lists.NewList", M.s); M.res := 0
		ELSIF M.name = "ScrollBar" THEN M.class := Objects.Bool; M.b := F.scrollbar; M.res := 0
		ELSIF M.name = "Cmd" THEN M.class := Objects.String; COPY(F.cmd, M.s); M.res := 0
		ELSIF M.name = "LineupHY" THEN M.class := Objects.Int; M.i := F.H - Fonts.Default.height; M.res := 0
		ELSIF M.name = "Point" THEN M.class := Objects.String; 
			IF F.pointed # NIL THEN COPY(F.pointed.s, M.s) ELSE M.s := ""; END; M.res := 0;
		ELSIF M.name = "Sel" THEN
			M.class := Objects.String; M.s := "";
			i := F.beg;
			WHILE (i # NIL) & (M.s = "") DO
				IF i.sel THEN COPY(i.s, M.s) END;
				i := i.next;
			END;
			M.res := 0
		ELSIF M.name = "Sorted" THEN
			M.class := Objects.Bool; M.b := F.sorted; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "ScrollBar" THEN
			IF M.class = Objects.Bool THEN F.scrollbar := M.b; M.res := 0 END
		ELSIF M.name = "Sel" THEN
			IF M.class = Objects.String THEN
				i := F.beg;
				WHILE (i # NIL) & (M.s # i.s) DO i.sel := FALSE; i := i.next END;
				IF i # NIL THEN
					i.sel := TRUE; i := i.next;
					WHILE i # NIL DO i.sel := FALSE; i := i.next END;
				END;
				M.res := 0
			END
		ELSIF M.name = "Point" THEN M.res := 0
		ELSIF M.name = "Cmd" THEN
			IF M.class = Objects.String THEN COPY(M.s, F.cmd); M.res := 0 END
		ELSIF M.name = "Sorted" THEN
			IF M.class = Objects.Bool THEN
				IF M.b # F.sorted THEN
					F.sorted := M.b;
					IF F.sorted THEN Sort(F) END
				END;
				M.res := 0
			END
		ELSE Gadgets.framehandle(F, M);
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("ScrollBar"); M.Enum("Sorted"); M.Enum("Sel"); M.Enum("Point"); M.Enum("Cmd");
		Gadgets.framehandle(F, M)
	END
END ListAttr;

PROCEDURE RestoreList(F: List; M: Display3.Mask; x, y, w, h: INTEGER);
VAR Y: INTEGER; item: Item; cx, cy, cw, ch, barW: INTEGER;
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	IF F.scrollbar THEN barW := barw ELSE barW := 0 END;
	
	Display3.Rect3D(M, Display3.bottomC, Display3.topC, x, y, w - barW, h, 1, Display.replace);
	IF barW > 0 THEN Updatebar(F, h); DrawSlider(M, F.bar, x + w - barW, y, barW, h) END;
	
	(* draw contents *)
	cx := M.X; cy := M.Y; cw := M.W; ch := M.H;
	Display3.AdjustMask(M, x+1, y + 1, w - barW - 2, h - 2);
	
	Y := y + h - 1; item := F.beg;
	WHILE (item # NIL) & (Y > y + 2) DO
		DEC(Y, Fonts.Default.height + 2);
		IF item.sel THEN
			Display3.ReplConst(M, Display3.white, x + 1, Y, w - barW - 2, Fonts.Default.height + 2, Display.replace);
			Display3.String(M, Display3.black, x + 6, Y + 3, Fonts.Default, item.s, Display3.textmode);
		ELSE
			Display3.ReplConst(M, Display3.textbackC, x + 1, Y, w - barW - 2, Fonts.Default.height + 2, Display.replace);
			Display3.String(M, Display3.textC, x + 6, Y + 3, Fonts.Default, item.s, Display3.textmode);
		END;
		IF F.focus THEN
			Display3.ReplConst(M, Display3.FG, x + 2, Y, 1, Fonts.Default.height + 2, Display.replace)
		END;
		item := item.next
	END;
	
	IF Y > y THEN
		Display3.ReplConst(M, Display3.textbackC, x + 1, y, w - barW - 2, Y - y, Display.replace);
		IF F.focus THEN
			Display3.ReplConst(M, Display3.FG, x + 2, y, 1, Y - y, Display.replace)
		END;
	END;
	M.X := cx; M.Y := cy; M.W := cw; M.H := ch;
	
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreList;

PROCEDURE PrintList(F: List; VAR M: Display.DisplayMsg);
VAR R: Display3.Mask; x, y, w, h, cx, cy, cw, ch, Y, barW: INTEGER; item: Item;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

	PROCEDURE PrintSlider(M: Display3.Mask; VAR bar: Bar; x, y, w, h: INTEGER);
	VAR barlen, min, max, pos: LONGINT; i: INTEGER;
	
		PROCEDURE Dot(R: Display3.Mask; x, y: INTEGER);
		VAR c: INTEGER;
		
			PROCEDURE D(col: INTEGER);
			BEGIN Printer3.ReplConst(R, col, x, y, P(1), P(1), Display.replace);
				INC(c); INC(x, P(1)); IF c MOD 4 = 0 THEN INC(y, P(1)); DEC(x, P(4)); END;
			END D;
			
		BEGIN
			c := 0;
			D(14); D(13); D(12); D(13);
			D(14); D(14); D(13); D(12);
			D(0); D(14); D(14); D(13);
			D(13); D(0); D(14); D(14);
		END Dot;

		PROCEDURE Knob(M: Display3.Mask; x, y, w, h: INTEGER);
		BEGIN
			Printer3.FilledRect3D(M, Display3.topC, Display3.bottomC, Display3.groupC, x, y, w, h, 1, Display.replace);
			Dot(M, x + w DIV 2 - 2, y + h DIV 2 - 2)
		END Knob;

	BEGIN
		Printer3.FilledRect3D(M, Display3.bottomC, Display3.topC, Display3.groupC, x, y, w, h, P(1), Display.replace);
		barlen := (h - P(bar.box * 2)) * bar.size DIV bar.range; (* length of bar *)
		IF barlen < 6 THEN barlen := 6 END;
		(* min & max *)
		min := y + P(bar.box); max := y + h - P(bar.box) - barlen;
		
		(* The following tests are due to rounding problems at the end of the range *)
		IF bar.pos <= 0 THEN pos := max
		ELSIF bar.pos >= bar.range - 1 THEN pos := min
		ELSE pos := min + (max - min + 1) * (bar.range - 1 - bar.pos) DIV bar.range
		END;

		Printer3.FilledRect3D(M, Display3.topC, Display3.bottomC, Display3.groupC, x + 1, y + 1, w-2, P(bar.box) - 2, 1, Display.replace); (* box inside *)
		Printer3.ReplConst(M, Display3.FG, x + 1, y + P(bar.box) - 1, w-2, 1, Display.replace); (* box border *)
		
		Printer3.FilledRect3D(M, Display3.topC, Display3.bottomC, Display3.groupC, x + 1, y + h - P(bar.box) + 1, w - 2, P(bar.box) - 2, 1, Display.replace); (* box inside *)
		Printer3.ReplConst(M, Display3.FG, x + 1, y + h - P(bar.box), w - 2, 1, Display.replace); (* box border *)
		
		(* Triangles *)
		FOR i := P(-4) TO P(1) DO
			Printer3.ReplConst(M, Display3.FG, x + w DIV 2 + i, y + P(bar.box) DIV 3 - i, -i*2, P(1), Display.replace);
			Printer3.ReplConst(M, Display3.FG, x + w DIV 2 + i, y + h - P(bar.box) DIV 3 + i, -i*2, P(1), Display.replace);
		END;

		(* inside *)
		Printer3.ReplConst(M, bar.bg, x + 1, y + P(bar.box), w-2, h - P(bar.box) * 2, Display.replace);
		
		(* draw bar *)
		Knob(M, x+1, SHORT(pos), w-2, SHORT(barlen));
	END PrintSlider;

BEGIN
	x := M.x; y := M.y; w := P(F.W); h := P(F.H);
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	IF F.scrollbar THEN barW := P(barw) ELSE barW := 0 END;
	
	Printer3.Rect3D(R, Display3.bottomC, Display3.topC, x, y, w - barW, h, P(1), Display.replace);
	IF barW > 0 THEN PrintSlider(R, F.bar, x + w - barW, y, barW, h) END;
	
	cx := R.X; cy := R.Y; cw := R.W; ch := R.H;
	Display3.AdjustMask(R, x+P(1), y + P(1), w - barW - P(2), h - P(2));

	Y := y + h - P(1); item := F.beg;
	WHILE (item # NIL) & (Y > y + P(2)) DO
		DEC(Y, P(Fonts.Default.height + 2));
		IF item.sel THEN
			Printer3.ReplConst(R, Display3.white, x+P(1), Y, w-barW - P(2), Fonts.Default.height + P(2), Display.replace);
			Printer3.String(R, Display3.black, x + P(6), Y + P(3), Fonts.Default, item.s, Display3.textmode);
		ELSE
			Printer3.ReplConst(R, Display3.textbackC, x+P(1), Y, w-barW - P(2), P(Fonts.Default.height + 2), Display.replace);
			Printer3.String(R, Display3.textC, x + P(6), Y + P(3), Fonts.Default, item.s, Display3.textmode);
		END;
		item := item.next
	END;
	R.X := cx; R.Y := cy; R.W := cw; R.H := ch;
	
	IF Y > y  THEN
		Printer3.ReplConst(R, Display3.textbackC, x+P(1), y, w-barW - P(2), Y - y, Display.replace);
	END;
	IF F.focus THEN
		Printer3.ReplConst(R, Display3.FG, x + P(2), y, 1, h, Display.replace)
	END;
END PrintList;

PROCEDURE Update(F: List);
VAR item: Item; i: INTEGER;
BEGIN
	item := F.items; i := 0;
	WHILE (item # NIL) & (i # F.bar.pos) DO INC(i); item := item.next END;
	F.beg := item;
	Gadgets.Update(F)
END Update;

PROCEDURE CopyList*(VAR M: Objects.CopyMsg; from, to: List);
VAR i: Item;
BEGIN
	 to.bar := from.bar; COPY(from.cmd, to.cmd); to.scrollbar := from.scrollbar; to.sorted := from.sorted;
	to.items := NIL;
	i := from.items;
	WHILE (i # NIL) DO InsertItem(to, i.s); i := i.next END;
	to.beg := to.items;
	Gadgets.CopyFrame(M, from, to);
END CopyList;

PROCEDURE LocateItem(F: List; x, y, MX, MY: INTEGER; VAR item: Item; VAR Y: INTEGER);
VAR i: Item;
BEGIN
	item := NIL;
	IF MY >= y + F.H THEN Y := 1
	ELSIF MY < y THEN  Y := -1
	ELSE
		Y := y + F.H - 1; i := F.beg;
		WHILE (i # NIL) DO
			DEC(Y, Fonts.Default.height + 2);
			IF Effects.Inside(MX, MY, x, Y, F.W, Fonts.Default.height + 2) THEN item := i; RETURN END;
			i := i.next
		END
	END
END LocateItem;

PROCEDURE InvertItem(F: List; M: Display3.Mask; x, y: INTEGER; VAR item: Item; VAR Y: INTEGER);
VAR barW: INTEGER;
BEGIN
	IF item # NIL THEN
		Oberon.FadeCursor(Oberon.Mouse);
		IF F.scrollbar THEN barW := barw ELSE barW := 0 END;
		Display3.ReplConst(M, Display3.invertC, x+4, Y, F.W - barW - 6, Fonts.Default.height + 2, Display.invert);
	END
END InvertItem;

PROCEDURE SelectItem(F: List; M: Display3.Mask; x, y: INTEGER; VAR item: Item; VAR Y: INTEGER);
VAR cx, cy, cw, ch, barW: INTEGER;
BEGIN
	IF (item # NIL) & ~item.sel THEN
		IF F.scrollbar THEN barW := barw ELSE barW := 0 END;
		cx := M.X; cy := M.Y; cw := M.W; ch := M.H;
		Display3.AdjustMask(M, x+1, y + 1, F.W - barW - 2, F.H - 2);
		Oberon.FadeCursor(Oberon.Mouse);
		Display3.ReplConst(M, Display3.white, x+1, Y, F.W-barW-2, Fonts.Default.height + 2, Display.replace);
		Display3.String(M, Display3.black, x + 6, Y + 3, Fonts.Default, item.s, Display3.textmode);
		IF F.focus THEN
			Display3.ReplConst(M, Display3.FG, x+2, Y, 1, Fonts.Default.height + 2, Display.replace);
		END;
		M.X := cx; M.Y := cy; M.W := cw; M.H := ch;
		item.sel := TRUE
	END
END SelectItem;

PROCEDURE TimeOk(): BOOLEAN;
BEGIN
	IF Oberon.Time() - mayscroll <= 0 THEN RETURN FALSE
	ELSE mayscroll := Oberon.Time() + waittime; RETURN TRUE
	END
END TimeOk;

PROCEDURE Check(F: List; R: Display3.Mask; x, y, w, h: INTEGER; item: Item; Y: INTEGER; VAR scroll: BOOLEAN);
VAR t, lineh: INTEGER; i: Item;
BEGIN
	scroll := FALSE;
	IF (item = NIL) & (F.beg # NIL) THEN
		IF TimeOk() THEN
			IF Y = 1 THEN (* one item previous *)
				IF F.beg.prev # NIL THEN
					F.beg := F.beg.prev; DEC(F.bar.pos);
					RestoreList(F, R, x, y, w, h); scroll := TRUE
				END
			ELSIF Y = -1 THEN (* one item more *)
				t := y + h - 1; lineh :=  Fonts.Default.height + 2;
				i := F.beg; WHILE (i # NIL) & (t - lineh > y) DO DEC(t, lineh); i := i.next END;
				IF (F.beg.next # NIL) & (i # NIL) & ((i.next # NIL) OR (t > y)) THEN
					F.beg := F.beg.next; INC(F.bar.pos);
					RestoreList(F, R, x, y, w, h); scroll := TRUE
				END
			END
		END
	END
END Check;

(* during selection *)
PROCEDURE Check2(F: List; R: Display3.Mask; x, y, w, h: INTEGER; item: Item; Y: INTEGER; VAR scroll: BOOLEAN);
VAR t, lineh: INTEGER; i: Item;
BEGIN
	scroll := FALSE;
	IF (item = NIL) & (F.beg # NIL) THEN
		IF TimeOk() THEN
			IF Y = 1 THEN (* one item previous *)
				IF F.beg.prev # NIL THEN
					F.beg := F.beg.prev; DEC(F.bar.pos);
					i := F.beg; WHILE (i # NIL) & ~i.sel DO i.sel := TRUE; i := i.next END;
					RestoreList(F, R, x, y, w, h); scroll := TRUE
				END
			ELSIF Y = -1 THEN (* one item more *)
				t := y + h - 1; lineh :=  Fonts.Default.height + 2;
				i := F.beg; WHILE (i # NIL) & (t - lineh > y) DO DEC(t, lineh); i := i.next END;
				IF (F.beg.next # NIL) & (i # NIL) & ((i.next # NIL) OR (t > y)) THEN
					WHILE (i # NIL) & ~i.sel DO i.sel := TRUE; i := i.prev END;
					
					F.beg := F.beg.next; INC(F.bar.pos);
					RestoreList(F, R, x, y, w, h); scroll := TRUE
				END
			END
		END
	END
END Check2;

(** Deselect all entries in the list. redraw indicates if the list has to be redrawn (only set if items were selected). *)
PROCEDURE DeselectList*(F: List; VAR redraw: BOOLEAN);
VAR i: Item;
BEGIN
	i := F.items; redraw := FALSE;
	WHILE i # NIL DO
		IF i.sel # FALSE THEN i.sel := FALSE; redraw := TRUE; END;
		i := i.next;
	END;
END DeselectList;

(** Delete all selected entries the list. *)
PROCEDURE DeleteSelection*(F: List);
VAR i: Item;
BEGIN
	i := F.items; F.items := NIL; F.noitems := 0;
	WHILE i # NIL DO
		IF ~i.sel THEN InsertItem(F, i.s); END;
		i := i.next;
	END;
	F.beg := F.items;
END DeleteSelection;

(** Returns all selected entries as a text. Entries that contain spaces are quoted. *)
PROCEDURE GetSelection*(F: List; VAR T: Texts.Text);
VAR W: Texts.Writer; i: Item; count: INTEGER;

  PROCEDURE WriteString(VAR W: Texts.Writer; s: ARRAY OF CHAR);
  VAR i: INTEGER;
  BEGIN i := 0;
  	WHILE (s[i] >= " ") OR (s[i] = 9X) DO Texts.Write(W, s[i]); INC(i) END	(* << jm *)
  END WriteString;

	PROCEDURE Space(VAR s: ARRAY OF CHAR): BOOLEAN;
	VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE s[i] # 0X DO
			IF s[i] = " " THEN RETURN TRUE END;
			INC(i)
		END;
		RETURN FALSE
	END Space;
	
BEGIN
	Texts.OpenWriter(W); i := F.items; NEW(T); Texts.Open(T, "");
	count := 0;
	WHILE i # NIL DO
		IF i.sel THEN
			IF Space(i.s) THEN Texts.Write(W, 22X); WriteString(W, i.s); Texts.Write(W, 22X)
			ELSE Texts.WriteString(W, i.s)
			END;
			INC(count);
			IF count MOD 10 =  0 THEN Texts.WriteLn(W)
			ELSE Texts.Write(W, " ")
			END
		END;
		i := i.next
	END;
	Texts.Append(T, W.buf)
END GetSelection;

PROCEDURE TrackList(F: List; R: Display3.Mask; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
VAR item, i: Item; Y, nY: INTEGER; keysum: SET; pos: LONGINT; redraw, scroll, scrolled: BOOLEAN; C: Oberon.ConsumeMsg;
	T: Texts.Text; beg, end, time: LONGINT;
BEGIN
	keysum := M.keys;
	IF (M.keys = {1}) & F.scrollbar & (M.X > x + w - barw) THEN
		pos := F.bar.pos;
		TrackSlider(R, F.bar, x + w - barw, y, barw, h);
		IF F.bar.pos # pos THEN Update(F) END;
		M.res := 0
	ELSIF M.keys = {1} THEN (* point *)
		scrolled := FALSE;
		LocateItem(F, x, y, M.X, M.Y, item, Y); Check(F, R, x, y, w, h, item, Y, scroll); scrolled := scrolled OR scroll; InvertItem(F, R, x, y, item, Y);
		WHILE M.keys # {} DO
			LocateItem(F, x, y, M.X, M.Y, i, nY); Check(F, R, x, y, w, h, i, nY, scroll); scrolled := scrolled OR scroll;
			IF i # item THEN
				IF ~scroll THEN InvertItem(F, R, x, y, item, Y) END; item := i; Y := nY;
				InvertItem(F, R, x, y, item, Y);
			END;
			Input.Mouse(M.keys, M.X, M.Y); keysum := keysum + M.keys;
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
		END;
		InvertItem(F, R, x, y, item, Y);
		IF scrolled THEN Gadgets.Update(F) END;
		IF (F.cmd # "") & (keysum # {0, 1, 2}) & (item # NIL) THEN
			F.pointed := item; Gadgets.Execute(F.cmd, F, M.dlink, NIL, NIL)
		END;
		M.res := 0
	ELSIF M.keys = {0} THEN (* select *)
		DeselectList(F, redraw); IF redraw THEN RestoreList(F, R, x, y, w, h); END;
		LocateItem(F, x, y, M.X, M.Y, item, Y); Check2(F, R, x, y, w, h, item, Y, scroll); SelectItem(F, R, x, y, item, Y);
		WHILE M.keys # {} DO
			LocateItem(F, x, y, M.X, M.Y, i, nY);
			Check2(F, R, x, y, w, h, i, nY, scroll);
			IF i # item THEN
				IF ~scroll THEN
					IF i # NIL THEN
						IF nY < Y THEN (* down *)
							WHILE (item # NIL) & (item # i) DO
								SelectItem(F, R, x, y, item, Y); DEC(Y, Fonts.Default.height + 2); 
								item := item.next
							END
						ELSE
							WHILE (item # NIL) & (item # i) DO
								SelectItem(F, R, x, y, item, Y); INC(Y, Fonts.Default.height + 2); 
								item := item.prev
							END
						END
					END;
					SelectItem(F, R, x, y, i, nY);
				END;
				item := i; Y := nY;
			END;
			Input.Mouse(M.keys, M.X, M.Y); keysum := keysum + M.keys;
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
		END;
		F.time := Oberon.Time();
		IF keysum = {0, 2} THEN (* delete *)
			DeleteSelection(F);
			IF F.bar.pos >= F.noitems THEN F.bar.pos := 0 END;
			(* Updatebar(F, h); *)
			Update(F);
			F.time := 0;
		ELSIF keysum = {0, 1} THEN (* copy over *)
			GetSelection(F, T);
			C.F := NIL; C.text := T; C.beg := 0; C.end := T.len; Display.Broadcast(C);
			Gadgets.Update(F)
		ELSE Gadgets.Update(F)
		END;
		M.res := 0
	ELSIF M.keys = {2} THEN (* focus *)
		IF ~F.focus THEN
			Oberon.Defocus;
			F.focus := TRUE; Gadgets.Update(F); keysum:= {};
			REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys UNTIL M.keys = {}; 			IF keysum = {2, 1} THEN (* copy over *)
				Oberon.GetSelection(T, beg, end, time);
				IF time > 0 THEN InsertItems(F, T, beg, end) END
			END
		ELSE
			keysum:= {};
			REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys UNTIL M.keys = {};
			IF keysum = {2, 1} THEN (* copy over *)
				Oberon.GetSelection(T, beg, end, time);
				IF time > 0 THEN InsertItems(F, T, beg, end) END
			END
		END;
		M.res := 0;
	ELSE Gadgets.framehandle(F, M)
	END
END TrackList;

PROCEDURE Search(F: List; ch: CHAR);
VAR i: Item; j: INTEGER; pos: LONGINT;
BEGIN
	IF ch = 0X THEN
		ss[0] := 0X;
	ELSIF (ch >= " ") & (ch < 86X) OR (ch = 9X) THEN
		j := 0; WHILE (j < 32) & (ss[j] # 0X) DO INC(j) END;
		IF j < 31 THEN ss[j] := ch; ss[j+1] := 0X; END;
		i := F.items; pos := 0;
		WHILE (i # NIL) & (ss> i.s) DO INC(pos); i := i.next END;
		IF (i # NIL) & (F.beg # i) THEN
			F.bar.pos := pos; Update(F);
		END;
	ELSIF ch = 0DX THEN
		ss[0] := 0X;
	END;
END Search;

PROCEDURE ListHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h: INTEGER; F0: List; R: Display3.Mask; redraw: BOOLEAN; T: Texts.Text;
	ver, noitems: LONGINT; l, new: Item;
BEGIN
	WITH F: List DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN	(* message addressed to this frame *)
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate display coordinates *)
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									RestoreList(F, R, x, y, w, h)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreList(F, R, x, y, w, h)
								END
							ELSIF M.device = Display.printer THEN
								PrintList(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & ~(Gadgets.selected IN F.state) & Gadgets.InActiveArea(F, M) & (M.keys # {}) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								TrackList(F, R, x, y, w, h, M)
							ELSIF (M.id = Oberon.consume) & F.focus THEN
								Search(F, M.ch); M.res := 0
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Display.ModifyMsg THEN
						WITH M: Display.ModifyMsg DO
							IF (M.F = F) & (M.dH # 0) THEN F.beg := F.items; F.bar.pos := 0; (* Updatebar(F, M.H)*) END;
							Gadgets.framehandle(F, M)
						END
					ELSIF M IS Oberon.ControlMsg THEN
						WITH M: Oberon.ControlMsg DO
							IF (M.id = Oberon.defocus) THEN Search(F, 0X);
								IF F.focus THEN F.focus := FALSE; Gadgets.Update(F) END;
							END;
							IF M.id = Oberon.neutralize THEN 
								DeselectList(F, redraw); F.time := 0; Search(F, 0X);
								IF redraw OR F.focus THEN F.focus := FALSE; Gadgets.Update(F) END
							END;
						END
					ELSIF M IS Oberon.ConsumeMsg THEN
						WITH M: Oberon.ConsumeMsg DO
							IF F.focus THEN  InsertItems(F, M.text, M.beg, M.end); M.res := 0
							ELSIF M.F = F THEN InsertItems(F, M.text, M.beg, M.end); M.res := 0
							END
						END
					ELSIF M IS Oberon.SelectMsg THEN
						WITH M: Oberon.SelectMsg DO
							IF (F.time > M.time) & (M.stamp # F.stamp) THEN
								F.stamp := F.time; GetSelection(F, T);
								IF T.len # 0 THEN M.text := T; M.sel := F; M.beg := 0; M.end := T.len; M.time := F.time END
							END
						END
					ELSIF M IS Display.ConsumeMsg THEN Gadgets.framehandle(F, M)
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
			
		(* Object messages *)
		
		ELSIF M IS Objects.AttrMsg THEN ListAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN (* store private data here *)
					Files.WriteNum(M.R, 4);
					Files.WriteString(M.R, F.cmd);
					(* paranoia count *)
					l := F.items; F.noitems := 0;
					WHILE l # NIL DO l := l.next; INC(F.noitems) END;
					Files.WriteNum(M.R, F.noitems);

					l := F.items;
					WHILE l # NIL DO Files.WriteString(M.R, l.s); l := l.next END;
					Files.WriteBool(M.R, F.scrollbar);
					Files.WriteBool(M.R, F.sorted);
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN (* load private data here *)
					Files.ReadNum(M.R, ver);
					IF (1 <= ver) & (ver <= 4) THEN
						Files.ReadString(M.R, F.cmd);
						F.noitems := 0; l := NIL;
						IF ver < 4 THEN
							NEW(new); Files.ReadString(M.R, new.s);
							WHILE new.s # "" DO
								IF l = NIL THEN F.items := new ELSE l.next := new; new.prev := l; END;
								INC(F.noitems); l := new; 
								NEW(new); Files.ReadString(M.R, new.s)
							END
						ELSE
							Files.ReadNum(M.R, noitems);
							WHILE F.noitems < noitems DO
								NEW(new); Files.ReadString(M.R, new.s);
								IF l = NIL THEN F.items := new ELSE l.next := new; new.prev := l; END;
								INC(F.noitems); l := new
							END
						END;
						IF ver >= 2 THEN Files.ReadBool(M.R, F.scrollbar) ELSE F.scrollbar := FALSE END;
						IF ver >= 3 THEN Files.ReadBool(M.R, F.sorted) END
					ELSE HALT(99)
					END;
					Gadgets.framehandle(F, M);
					F.beg := F.items; F.bar.pos := 0; Updatebar(F, F.H)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink (* copy msg arrives again *)
				ELSE (* first time copy message arrives *)
					NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyList(M, F, F0); M.obj := F0
				END
			END
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF (M.id = Objects.set) & (M.name = "Model") & (M.obj IS Texts.Text) THEN
					T := M.obj(Texts.Text);
					F.beg := NIL; F.items := NIL; F.noitems := 0;
					InsertItems(F, T, 0, T.len);
					M.res := 0;
				ELSIF (M.id = Objects.get) & (M.name = "Model") THEN
					NEW(T); Texts.Open(T, "");
					l := F.items;
					WHILE l # NIL DO
						Texts.WriteString(W, l.s); Texts.WriteLn(W);
						l := l.next
					END;
					Texts.Append(T, W.buf);
					M.obj := T; M.res := 0;
				ELSE Gadgets.framehandle(F, M)
				END;
			END
		ELSE	(* unknown msg, framehandler might know it *)
			Gadgets.framehandle(F, M)
		END
	END
END ListHandler;

PROCEDURE InitList*(F: List);
BEGIN F.W := 100; F.H := 100; F.handle := ListHandler; F.noitems := 0; F.scrollbar := TRUE;
	F.bar.range := 1000; F.bar.size := 1000; F.bar.pos := 0; F.bar.box := 20; F.bar.bg := Display3.textbackC;
	F.beg := F.items; F.sorted := TRUE;
	F.last := F.items;
	IF F.last # NIL THEN WHILE F.last.next # NIL DO F.last := F.last END END
END InitList;

PROCEDURE NewList*;
VAR F: List;
BEGIN NEW(F); InitList(F); Objects.NewObj := F;
END NewList;

(* --- tools for lists --- *)

(* Native-Oberon version *)
PROCEDURE *ListFiles(name: ARRAY OF CHAR; time, date, size: LONGINT; VAR cont: BOOLEAN);
VAR i0, i1, j0, j1: INTEGER; f: BOOLEAN; 
BEGIN i0 := pos; j0 := pos; f := TRUE;
	LOOP
		IF pat[i0] = "*" THEN INC(i0); IF pat[i0] = 0X THEN EXIT END
		ELSE IF name[j0] # 0X THEN f := FALSE END;
			EXIT
		END;
		f := FALSE;
		LOOP
			IF name[j0] = 0X THEN EXIT END;
			i1 := i0; j1 := j0;
			LOOP
				IF (pat[i1] = 0X) OR (pat[i1] = "*") THEN f := TRUE; EXIT END ;
				IF pat[i1] # name[j1] THEN EXIT END;
				INC(i1); INC(j1)
			END ;
			IF f THEN j0 := j1; i0 := i1; EXIT END;
			INC(j0)
		END;
		IF ~f THEN EXIT END
	END ;
	IF f THEN
		Texts.WriteString(W, name); Texts.WriteLn(W);
	END
END ListFiles;

PROCEDURE GetDir(mask : ARRAY OF CHAR; text : Texts.Text);
	VAR pre : ARRAY 32 OF CHAR; i : INTEGER; 
BEGIN
	i := 0;
	WHILE (mask[i] > " ") & (mask[i] # "/") DO pat[i] := mask[i]; INC(i);  END;
	pat[i] := 0X;
	i := 0;
	WHILE pat[i] > "*" DO pre[i] := pat[i]; INC(i) END;
	pre[i] := 0X; pos := i;
	FileDir.Enumerate(pre,FALSE,ListFiles);
	Texts.Append(text,W.buf);
END GetDir;

PROCEDURE Copy(source : ARRAY OF CHAR; VAR dest : ARRAY OF CHAR);
	VAR i,j : INTEGER;
BEGIN
	j := 0; WHILE (source[j] = " ") DO INC(j); END;
	i := 0; dest[i] := source[j]; WHILE (source[j] # 0X) & (source[j] # " ")  DO INC(i); INC(j); dest[i] := source[j] END;
	dest[i] := 0X;
END Copy;

(** Used in the form:

	Lists.Directory "<pattern>" <Objname> ~
	
Determines all the filenames that match pattern and inserts them into the list named <Objname> in the current context.
*)
PROCEDURE Directory*; (* "mask" "objname" *)
VAR S: Attributes.Scanner; mask: ARRAY 32 OF CHAR; o: Objects.Object; text: Texts.Text;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S); 
	IF (S.class = Attributes.Name) OR (S.class = Attributes.String)  THEN Copy(S.s, mask);
		Attributes.Scan(S);
		IF (S.class = Attributes.Name) OR (S.class = Attributes.String) THEN 
			Copy(S.s, S.s); o := Gadgets.FindObj(Gadgets.context, S.s);
			IF (o # NIL) & (o IS List) THEN
				WITH o: List DO
					NEW(text); Texts.Open(text,""); 
					GetDir(mask, text); o.beg := NIL; o.items := NIL; o.noitems := 0;
					InsertItems(o, text, 0, text.len);
				END
			END
		END
	END
END Directory;

PROCEDURE Match(name,pat : ARRAY OF CHAR): BOOLEAN;
	CONST  VAR i0, i1, j0, j1,pos: INTEGER; f: BOOLEAN; 
BEGIN pos := 0;
	pos := 0; WHILE (pat[pos] # "*") & (pat[pos] # 0X) & (pat[pos] = name[pos]) DO INC(pos) END;
	IF name[pos] = 0X THEN RETURN TRUE END;  
	i0 := pos; j0 := pos; f := TRUE;
	LOOP
		IF pat[i0] = "*" THEN INC(i0);
			IF pat[i0] = 0X THEN EXIT END
		ELSE
			IF name[j0] # 0X THEN f := FALSE END;
			EXIT
		END;
		f := FALSE;
		LOOP
			IF name[j0] = 0X THEN EXIT END;
			i1 := i0; j1 := j0;
			LOOP
				IF (pat[i1] = 0X) OR (pat[i1] = "*") THEN f := TRUE; EXIT END ;
				IF pat[i1] # name[j1] THEN EXIT END;
				INC(i1); INC(j1)
			END ;
			IF f THEN j0 := j1; i0 := i1; EXIT END;
			INC(j0)
		END;
		IF ~f THEN EXIT END
	END ;
	RETURN f
END Match;

PROCEDURE *EntryHandler(name: ARRAY OF CHAR; date, time, size: LONGINT);
BEGIN
	IF (name[0] > " ") & (name[0] < CHR(127)) & Match(name,pat) THEN Texts.WriteString(W,name); Texts.WriteLn(W) END
END EntryHandler;

PROCEDURE GetDiskette(mask: ARRAY OF CHAR; text: Texts.Text);
	VAR i, a, b: INTEGER; 
BEGIN
	i := 0;
	WHILE (mask[i] > " ") & (mask[i] # "/") DO pat[i] := mask[i]; INC(i);  END;
	pat[i] := 0X;
	Floppy.OpenVol(a, b);
	Floppy.Enumerate(EntryHandler);
	Floppy.CloseVol();
	Texts.Append(text,W.buf);
END GetDiskette;

(* Windows version
PROCEDURE GetDiskette(mask: ARRAY OF CHAR; text: Texts.Text);
	VAR  i : INTEGER; 
BEGIN
	i := 0;
	WHILE (mask[i] > " ") & (mask[i] # "/") DO pat[i] := mask[i]; INC(i);  END;
	pat[i] := 0X;
	Texts.Append(text,W.buf);
END GetDiskette;
*)

(** Same as Directory, except the files on Diskette are searched. This command is not functional on all platforms. *)
PROCEDURE Diskette*; (* "mask" "objname" *)
VAR S: Attributes.Scanner; mask: ARRAY 32 OF CHAR; o: Objects.Object;
		text: Texts.Text;
BEGIN	
	Attributes.OpenScanner(S,Oberon.Par.text,Oberon.Par.pos); Attributes.Scan(S); 
	IF (S.class = Attributes.Name) OR (S.class  = Attributes.String)  THEN Copy(S.s, mask);
		Attributes.Scan(S);
		IF (S.class = Attributes.Name) OR (S.class = Attributes.String) THEN 
			Copy(S.s, S.s); o := Gadgets.FindObj(Gadgets.context, S.s);
			IF (o # NIL) & (o IS List) THEN
				WITH o: List DO
					NEW(text); Texts.Open(text, ""); 
					GetDiskette(mask, text); o.beg := NIL; o.items := NIL; o.noitems := 0;
					InsertItems(o, text, 0, text.len);
				END
			END
		END
	END
END Diskette;
		
PROCEDURE LibDir(name: ARRAY OF CHAR; text: Texts.Text);
VAR  L: Objects.Library; ref, i: INTEGER; libName, objName: ARRAY 32 OF CHAR; 
BEGIN
	i := 0; WHILE (name[i] # 0X) & (name[i] # ".") DO INC(i) END;
	name[i] := 0X; COPY(name, libName);
	name[i] := "."; name[i+1] := "L"; name[i+2] := "i"; name[i+3] := "b"; name[i+4] := 0X;
	
	L := Objects.ThisLibrary(name);
	IF L # NIL THEN
		ref := 0;
		REPEAT
			Objects.GetName(L.dict, ref, objName);
			IF (objName[0] # 0X) & (objName[0] >= "A") & (objName[0] <=  "Z") THEN
				Texts.WriteString(W, libName); Texts.Write(W, ".");
				Texts.WriteString(W, objName); Texts.WriteLn(W);
				END;
			INC(ref)
		UNTIL ref = L.maxref
	END;
	Texts.Append(text,W.buf);
END LibDir;

(** Used in the form:

	Lists.Library <Libname> <ObjName>
	
Inserts a list of all object names in <Libname> into the list named <ObjName> in the current context. <Libname> must not include the ".Lib" extension.
*)
PROCEDURE Library*;	(* "lib" "objname" *)
VAR S: Attributes.Scanner; name : ARRAY 32 OF CHAR; o: Objects.Object; text: Texts.Text;
BEGIN
	Attributes.OpenScanner(S,Oberon.Par.text,Oberon.Par.pos); Attributes.Scan(S);
	IF (S.class = Attributes.Name) OR (S.class = Attributes.String)  THEN Copy(S.s, name); 
		Attributes.Scan(S);
		IF (S.class = Attributes.Name) OR (S.class = Attributes.String) THEN 
			Copy(S.s, S.s); o := Gadgets.FindObj(Gadgets.context, S.s);
			IF (o # NIL) & (o IS List) THEN
				WITH o: List DO
					NEW(text); Texts.Open(text, ""); LibDir(name, text); o.beg := NIL; o.items := NIL; o.noitems := 0;
					InsertItems(o, text, 0, text.len);
				END
			END
		END
	END
END Library;

PROCEDURE Init;
	VAR s: Texts.Scanner;
BEGIN
	Oberon.OpenScanner(s, "Gadgets.ListScrollDelay");
	IF (s.class = Texts.Int) & (s.i > 0) THEN waittime := s.i
	ELSE waittime := 100
	END;
	waittime := waittime * Input.TimeUnit DIV 1000
END Init;

BEGIN
	Texts.OpenWriter(W);
	Init()
END Lists.

(** Remarks:

1. Here is some code that illustrates how to insert items into a list. Note that you have to update F.beg to the start of the items you want to show. F.bar.pos says where the scroll bar must be positioned.

	PROCEDURE InsertItems(F: List; T: Texts.Text; beg, end: LONGINT);
	VAR S: Attributes.Scanner;
	BEGIN
		Attributes.OpenScanner(S, T, beg);
		Attributes.Scan(S);
		WHILE (S.class = Attributes.Name) OR (S.class = Attributes.String) DO
			InsertItem(F, S.s);
			IF (S.R.text = T) & (Attributes.Pos(S.R) >= end) THEN (* base text + beyond end of selection *)
				S.class := Attributes.Inval
			ELSE Attributes.Scan(S)
			END
		END;
		F.beg := F.items; F.bar.pos := 0;
		Gadgets.Update(F);
	END InsertItems;

*)

System.Free Lists ~
Gadgets.Insert Lists.NewList ~