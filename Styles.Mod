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

MODULE Styles;	(** portable *) (* RS, Wed, 9-Jun-1993 *)

(* copy "by hand" -> obj.link*)
(*other kind of feedback*)
(*portable write*)
	IMPORT Display, Printer, Files, Fonts, Objects, Oberon, Texts, Input;

	CONST 
		Left = "left";	Right = "right";	Width = "width";	Gap = "gap";
		Break = "break";	Adj = "adjust";	Tabs = "tabs";	Lsp = "line";
		Grid = "grid";

		Bef = "before";	Norm = "normal";	Block = "block";	Cent = "center";

		left* = 0; right* = 1;	(* format flags *)
		fmode* = 0; leftmarg*  = 1; width* = 2; tabs* = 3;
		Adjust* = {left, right};
		break* = 3;	(* page break *)
		grid* = 2;

		get* = 0;	set* = 1;

		ScnUnit = 10000;	(* Display.Unit *)
		
		mm* = 36000;
		tenth = mm DIV 10;
		pageW* = 160*mm;
		scnW* = pageW DIV ScnUnit;
		MinTabW = 3*mm;	MinTab = 8;

		TAB = 09X;
		BoxH = 7; BoxW = 8; TabW = 5;
		MinW = scnW DIV 6;
		MaxTabs = 32;
		ML = 2;	MM = 1;	MR = 0;
		Version = 1X;

	TYPE
		Style* = POINTER TO StyleDesc;
		StyleDesc* = RECORD(Objects.ObjDesc)
			opts*: SET;	(* opts: {0} = left, {1} = right, {0,1} = adjust, {} = center *)
			paraW*: LONGINT;	(* width of area *)
			left*: LONGINT;	(* left offset *)
			lsp*, dsr*: LONGINT;	(* line spacing *)
			gap*: LONGINT;	(* gap before style *)
			nTabs*: SHORTINT;
			tab*: ARRAY MaxTabs OF LONGINT
		END;
		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD(Display.FrameDesc)
			
			style*: Style;
			sel*, col*: INTEGER;
		END;

		UpdateMsg* = RECORD(Display.FrameMsg)
			id*: INTEGER;	(* 0 = fmode 1 = leftmarg  2 = width 3 = tabs *)
			obj*: Style;
			dX*: INTEGER
		END;

		ParamMsg* = RECORD(Objects.ObjMsg)
			id*: INTEGER;	(*get, set*)
			S*: Texts.Scanner;
			T*: Texts.Text;
		END;

		FontList = POINTER TO FontListDesc;
		FontListDesc = RECORD
			next: FontList;
			name: Objects.Name;
			mfnt: Fonts.Font;
			unit: LONGINT
		END;


	VAR
		defStyle*: Style;
		font: FontList;
		W: Texts.Writer;
		(*pat, pat2: ARRAY 6 OF CHAR;*)
		dash, dash2: LONGINT;
		nfnt: Fonts.Font;

(* document coordinate stuff *)


	PROCEDURE Screen(x: LONGINT): INTEGER;
	BEGIN
		RETURN SHORT(x DIV ScnUnit)
	END Screen;
	
	PROCEDURE Doc(x: INTEGER): LONGINT;
	BEGIN
		RETURN LONG(x)*ScnUnit;
	END Doc;

(* md3 stuff *)

	PROCEDURE Uncache(p: FontList);	(*remove unused & substituted metrics*)
(*
	VAR q: FontList; L: Objects.Library;
	BEGIN q := p.next;
		WHILE q # font DO L := Objects.FirstLib;
			WHILE (L # NIL) & (L.name # q.name) DO L := L.next END;
			IF (L = NIL) OR (q.mfnt.type # Objects.metric) THEN p.next := q.next ELSE p := q END;
			q := q.next
		END
*)
	END Uncache;

	PROCEDURE OpenMetricFont(fnt: Fonts.Font; VAR unit: LONGINT; VAR mfnt: Fonts.Font);
	BEGIN
		mfnt := Printer.GetMetric(fnt);
		IF mfnt = NIL THEN unit := ScnUnit; mfnt := fnt
		ELSE unit := Printer.Unit
		END
	END OpenMetricFont;

	PROCEDURE MetricFnt*(fnt: Fonts.Font; VAR unit: LONGINT; VAR mfnt: Fonts.Font);
	VAR p, q: FontList;
	BEGIN
		q := font.next;
		IF q.name # fnt.name THEN	(*search*)
			p := font; WHILE (p.next # font) & (p.next.name # fnt.name) DO p := p.next END;
			IF p.next = font THEN NEW(q); q.name := fnt.name; OpenMetricFont(fnt, q.unit, q.mfnt); Uncache(font)
			ELSE q := p.next; p.next := q.next
			END;
			q.next := font.next; font.next := q	(*first*)
		END;
		mfnt := q.mfnt; unit := q.unit
	END MetricFnt;

	PROCEDURE Tab*(style: Style; fnt: Fonts.Font; x, X: LONGINT; VAR dx: INTEGER; VAR dX: LONGINT);
	VAR
		t: INTEGER;
		obj: Objects.Object;
		X0, unit: LONGINT;
	BEGIN
		t := 0;
		x := x*ScnUnit;	(* to doc *)
		X0 := X;
		IF x > X0 THEN X0 := x END;
		WHILE t < style.nTabs DO
			dX := style.tab[t];
			IF dX > X0 + MinTabW THEN dx := SHORT((dX - x) DIV ScnUnit); dX := dX - X; RETURN
			ELSE INC(t)
			END
		END;
		fnt.GetObj(fnt, ORD(TAB), obj); dx := obj(Fonts.Char).dx;
		MetricFnt(fnt, unit, fnt); fnt.GetObj(fnt, ORD(TAB), obj); dX := unit*obj(Fonts.Char).dx
	END Tab;

	PROCEDURE Height*(fnt: Fonts.Font; VAR asr, dsr: LONGINT);
	VAR unit: LONGINT;
	BEGIN MetricFnt(fnt, unit, fnt); asr := unit*fnt.maxY; dsr := -unit*fnt.minY
	END Height;

	PROCEDURE Similar*(s0, s1: Style): BOOLEAN;
	VAR n: INTEGER;
	BEGIN
		IF s0 # s1 THEN
			IF (s0.opts # s1.opts) OR (s0.paraW # s1.paraW)
				OR (s0.left # s1.left) OR (s0.nTabs # s1.nTabs)
				OR (s0.lsp # s1.lsp) OR (s0.gap # s1.gap) THEN
				RETURN FALSE
			ELSIF s0.nTabs > 0 THEN
				n := 0;
				WHILE n < s0.nTabs DO
					IF s0.tab[n] # s1.tab[n] THEN RETURN FALSE END;
					INC(n)
				END
			END
		END;
		RETURN TRUE
	END Similar;


	(*old*)

	PROCEDURE ReadLong (VAR R: Files.Rider; VAR x: LONGINT);
	VAR c0, c1, c2: CHAR; s1: SHORTINT;
	BEGIN Files.Read(R, c0); Files.Read(R, c1); Files.Read(R, c2); Files.Read(R, s1);
		x := s1; x := ((x * 100H + LONG(c2)) * 100H + LONG(c1)) * 100H + LONG(c0)
	END ReadLong;

	(*new*)

	PROCEDURE IntToSet(n: LONGINT): SET;	(*[0..255]->[{}..{0..7}]*)
	VAR i: INTEGER; s: SET;
	BEGIN i := 0; s := {};
		REPEAT
			IF ODD(n) THEN INCL(s, i) END; n := n DIV 2; INC(i)
		UNTIL i = 8;
		RETURN s
	END IntToSet;

	PROCEDURE SetToInt(s: SET): LONGINT;	(*[{}..{0..7}]->[0..255]*)
	VAR i: INTEGER; n: LONGINT;
	BEGIN i := 8; n := 0;
		REPEAT DEC(i); n := n*2;
			IF i IN s THEN INC(n) END
		UNTIL i = 0;
		RETURN n
	END SetToInt;

	PROCEDURE WriteData (VAR W: Files.Rider; style: Style);
		VAR i: INTEGER;
	BEGIN
		Files.Write(W, 0CFX); Files.Write(W, Version);
		Files.WriteNum(W, SetToInt(style.opts));
		Files.WriteNum(W, style.paraW);
		Files.WriteNum(W, style.left);	(* left offset *)
		Files.WriteNum(W, style.lsp);	(* line spacing *)
		IF style.lsp > 0 THEN Files.WriteNum(W, style.dsr) END;
		Files.WriteNum(W, style.gap);
		Files.Write(W, style.nTabs);
		i := 0; WHILE i < style.nTabs DO Files.WriteNum(W, style.tab[i]); INC(i) END;
	END WriteData;

	PROCEDURE ReadData (VAR R: Files.Rider; style: Style);
		VAR i: INTEGER; n: LONGINT; x, y: CHAR;
	BEGIN
		Files.Read(R, y); Files.Read(R, x);
		IF x = 0X THEN	(*old*)	(*opts=[y|0|0|0]*)
			Files.Read(R, x); Files.Read(R, x);	(*skip*)
			style.opts := IntToSet(ORD(y));
			ReadLong(R, style.paraW);
			ReadLong(R, style.left);	(* left offset *)
			ReadLong(R, style.lsp);	(* line spacing *)
			ReadLong(R, style.gap);
			Files.Read(R, style.nTabs);
			i := 0; WHILE i < style.nTabs DO ReadLong(R, style.tab[i]); INC(i) END;
			WHILE i < MaxTabs DO style.tab[i] := 0; INC(i) END;
		ELSIF x = Version THEN	(*[CF|1]*)
			Files.ReadNum(R, n); style.opts := IntToSet(n);
			Files.ReadNum(R, style.paraW);
			Files.ReadNum(R, style.left);	(* left offset *)
			Files.ReadNum(R, style.lsp);	(* line spacing *)
			IF style.lsp > 0 THEN Files.ReadNum(R, style.dsr) END;
			Files.ReadNum(R, style.gap);
			Files.Read(R, style.nTabs);
			i := 0; WHILE i < style.nTabs DO Files.ReadNum(R, style.tab[i]); INC(i) END;
			WHILE i < MaxTabs DO style.tab[i] := 0; INC(i) END;
		ELSE HALT(33)
		END
	END ReadData;

	PROCEDURE DrawTab(F : Frame;sel, x, y: INTEGER);
	BEGIN
		Display.ReplConst(Display.FG- F.col, x-2, y, 5, 1, Display.invert);
		Display.ReplConst(Display.FG- F.col, x-1, y+1, 3, 1, Display.invert);
		Display.ReplConst(Display.FG- F.col, x, y+2, 1, 1, Display.invert);
		IF sel > 0 THEN Display.ReplConst(Display.FG- F.col, x -2, y + 1, 5, 2, Display.invert) END
	END DrawTab;

	PROCEDURE DrawMode(F : Frame; opts: SET; x, y, w: INTEGER);
	VAR h: INTEGER;
	BEGIN
		h := BoxH - (BoxH DIV 2)-1; INC(y, BoxH DIV 2+1);
		IF left IN opts THEN Display.ReplConst(Display.FG- F.col, x, y, BoxW, h, Display.invert)
		ELSE Display.ReplConst(Display.FG- F.col, x, y+h-1, BoxW, 1, Display.invert)
		END;
		IF right IN opts THEN Display.ReplConst(Display.FG- F.col, x+w-BoxW, y, BoxW, h, Display.invert)
		ELSE Display.ReplConst(Display.FG- F.col, x+w-BoxW, y+h-1, BoxW, 1, Display.invert)
		END;
	END DrawMode;

	PROCEDURE DrawName(style: Style; x, y, w: INTEGER);
		VAR s: ARRAY 32 OF CHAR; obj: Objects.Object; i: INTEGER;
	BEGIN i := 0; s[0] := 0X; Objects.GetName(style.lib.dict, style.ref, s);
		IF s[0] # 0X THEN
			INC(x, w-100); DEC(y, nfnt.minY);
			WHILE s[i] # 0X DO nfnt.GetObj(nfnt, ORD(s[i]), obj);
				WITH obj: Fonts.Char DO
					Display.ReplConst(Display.BG, x, y+nfnt.minY, obj.dx, nfnt.height, Display.replace); 
					Display.CopyPattern(Display.FG, obj.pat, x+obj.x, y+obj.y, Display.replace); INC(x, obj.dx)
				END;
				INC(i)
			END
		END
	END DrawName;

	PROCEDURE DrawBox(F: Frame; x, y, X, Y, W: INTEGER);
	BEGIN Display.ReplConst(Display.FG, x+F.X + X, y+F.Y+Y, W, BoxH DIV 2, Display.invert)
	END DrawBox;

	PROCEDURE Wide(F: Frame): BOOLEAN;
	BEGIN RETURN (F.W = F.style.paraW DIV ScnUnit)
	END Wide;

	PROCEDURE DrawTabs(F: Frame; x, y: INTEGER);
	VAR i, t: INTEGER;
	BEGIN INC(x, F.X); INC(y, F.Y); i := 0;
		WHILE i < F.style.nTabs DO t := Screen(F.style.tab[i]);
			IF (t < F.W) OR Wide(F) THEN DrawTab(F, 0, x + t, y) END; INC(i)
		END
	END DrawTabs;

	PROCEDURE DrawBar(F: Frame; x, y, w: INTEGER);
	VAR BoxW: INTEGER;
	BEGIN
		INC(x, F.X); INC(y, F.Y); BoxW := 0;
		Display.ReplConst(F.col, x, y , w, F.H, Display.replace);
		IF F.H = BoxH THEN
			IF break IN F.style.opts THEN Display.ReplConst(Display.FG, x+BoxW, y+ F.H DIV 2, w -2*BoxW, 1, Display.replace)
			ELSE Display.ReplPattern(Display.FG, dash, x+BoxW, y+ F.H DIV 2, w -2*BoxW, 1, Display.paint)
			END;
			DrawMode(F, F.style.opts, x, y, w); DrawName(F.style, x, y, w); DrawTabs(F, x-F.X, y-F.Y)
			(*IF F.sel > 0 THEN Display.ReplConst(Display.FG, x, y , w, F.H, Display.invert) END*)
		ELSIF break IN F.style.opts THEN
			Display.ReplPattern(Display.FG, dash2, x, y, F.W, 1, Display.paint)
		END
	END DrawBar;

	PROCEDURE Update(style: Style; what, dX: INTEGER);
		VAR M: UpdateMsg;
	BEGIN M.obj := style; M.dX := dX; M.id := what; M.F := NIL; Display.Broadcast(M)
	END Update;
	
	PROCEDURE CheckTab(style: Style; i: INTEGER);
	VAR
		tab: LONGINT;
		j: INTEGER;
	BEGIN
		tab := style.tab[i]; j := i;
		IF (j < style.nTabs-1) & (style.tab[j+1] <= tab) THEN
			WHILE (j < style.nTabs-1) & (style.tab[j+1] <= tab) DO style.tab[j] := style.tab[j+1]; INC(j) END
		ELSE
			WHILE (j > 0) & (style.tab[j-1] >= tab) DO style.tab[j] := style.tab[j-1]; DEC(j) END
		END;
		IF (j # i) & (style.tab[j] = tab) THEN	(* multiple tabs -> delete *)
			DEC(style.nTabs); WHILE j < style.nTabs DO style.tab[j] := style.tab[j+1]; INC(j) END
		ELSE
			style.tab[j] := tab
		END;
		WHILE (style.nTabs > 0) & (style.tab[style.nTabs-1] > style.paraW) DO DEC(style.nTabs) END
	END CheckTab;

	PROCEDURE FindTab(F: Frame; x: INTEGER; VAR d, t: INTEGER);
	VAR
		tab: INTEGER;
	BEGIN
		t := 0; d := 0;
		WHILE t < F.style.nTabs DO
			tab := Screen(F.style.tab[t]);
			IF (tab - 2 <= x) & (x <= tab + 2) THEN d := x - tab; RETURN ELSE INC(t) END
		END
	END FindTab;

	PROCEDURE TrackMouse(VAR x, y: INTEGER; VAR keys, keysum: SET);
	BEGIN Input.Mouse(keys, x, y); keysum := keysum + keys;
		Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, x, y)
	END TrackMouse;

	PROCEDURE TrackLeft(F: Frame; x, y, X, Y: INTEGER; VAR left: INTEGER; VAR keysum: SET);
	VAR
		d, min, max, left0, boxW: INTEGER;
		Keys: SET;
	BEGIN
		d := X - F.X - x;
		min := -Screen(F.style.left); max := F.W - MinW; left0 := 0; boxW := BoxW;
		left := X - d - F.X - x; DrawBox(F, x, y, left, BoxH DIV 2+1, boxW);
		keysum := {};
		REPEAT
			Input.Mouse(Keys, X, Y);
			IF (ML IN Keys) & ~(ML IN keysum) & Wide(F) THEN	(*move column*)
				max := scnW-F.W+min;
				DrawBox(F, x, y, left0, BoxH DIV 2+1, boxW); boxW := F.W; DrawBox(F, x, y, left, BoxH DIV 2+1, boxW)
			END;
			keysum := keysum + Keys;
			Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, X, Y);
			left := X - d - F.X - x;
			IF left < min THEN left := min ELSIF left > max THEN left := max END;
			IF left # left0 THEN
				Oberon.FadeCursor(Oberon.Mouse);
				DrawBox(F, x, y, left0, BoxH DIV 2+1, boxW); DrawBox(F, x, y, left, BoxH DIV 2+1, boxW); left0 := left
			END
		UNTIL Keys = {};
		DrawBox(F, x, y, left, BoxH DIV 2+1, boxW);
		IF (ML IN keysum) & ~Wide(F) THEN EXCL(keysum, ML) END;
		Oberon.FadeCursor(Oberon.Mouse)
	END TrackLeft;

	PROCEDURE TrackRight(F: Frame; x, y, X, Y: INTEGER; VAR w: INTEGER; VAR keysum: SET);
	VAR
		w0, d: INTEGER;
		max: INTEGER;
		Keys: SET;
	BEGIN
		d := X - F.X - x;
		max := scnW - Screen(F.style.left); w0 := Screen(F.style.paraW);
		w := F.W + X - d - F.X - x; DrawBox(F, x, y, w-BoxW, BoxH DIV 2+1, BoxW);
		keysum := {};
		REPEAT
			TrackMouse(X, Y, Keys, keysum);
			w := F.W + X - d - F.X - x;
			IF w < MinW THEN w := MinW ELSIF w > max THEN w := max END;
			IF w # w0 THEN
				Oberon.FadeCursor(Oberon.Mouse);
				DrawBox(F, x, y, w0-BoxW, BoxH DIV 2+1, BoxW); DrawBox(F, x, y, w-BoxW, BoxH DIV 2+1, BoxW);
				w0 := w
			END
		UNTIL Keys = {};
		DrawBox(F, x, y, w-BoxW, BoxH DIV 2+1, BoxW);
		Oberon.FadeCursor(Oberon.Mouse)
	END TrackRight;

(**)
	PROCEDURE LocTab(style: Style; t, x: INTEGER): INTEGER;
	VAR i, x0: INTEGER;
	BEGIN
		x0 := MinTab; i := 0;
		IF i = t THEN INC(i) END;
		WHILE (i < style.nTabs) & (x0 <= x) DO
			IF (x < Screen(style.tab[i])-MinTab) THEN RETURN x END;
			REPEAT x0 := Screen(style.tab[i])+MinTab; INC(i);
				IF i = t THEN INC(i) END
			UNTIL (i >= style.nTabs) OR (x0 < Screen(style.tab[i])-MinTab)
		END;
		IF (style.nTabs > 0) & (x < x0) THEN RETURN x0
		ELSE RETURN x
		END
	END LocTab;


	PROCEDURE TrackTab(F: Frame; x, y, X, Y: INTEGER; VAR tabX, t: INTEGER; VAR keysum: SET);
	VAR
		d, tabX0: INTEGER;
		new: BOOLEAN;
		Keys: SET;
	BEGIN
		FindTab(F, X - F.X - x, d, t);
		keysum := {};
		tabX0 := X - d - F.X - x;
		IF t < F.style.nTabs THEN tabX0 := Screen(F.style.tab[t]);
			DrawTab(F,0, x + F.X + tabX0, y + F.Y); DrawTab(F,1, x + F.X + tabX0, y + F.Y)
		ELSE
			DrawBox(F, x, y, tabX0-TabW DIV 2, 0, TabW)
		END;
		REPEAT
			TrackMouse(X, Y, Keys, keysum);
			(*tabX := X - d - F.X - x;*)
			tabX := LocTab(F.style, t, X - d - F.X - x);
			IF tabX > F.W + MinTab THEN tabX := F.W + MinTab
			ELSIF tabX < MinTab THEN tabX := MinTab
			END;
			IF (ML IN Keys) & (t = F.style.nTabs) & (F.style.nTabs < MaxTabs) THEN	(* add a new *)
				DrawBox(F, x, y, tabX0-TabW DIV 2, 0, TabW);
				DrawTab(F,1, x + F.X + tabX, y + F.Y); d := 0; tabX0 := tabX; INC(F.style.nTabs); new := TRUE
			END;
			IF tabX # tabX0 THEN
				Oberon.FadeCursor(Oberon.Mouse);
				IF t < F.style.nTabs THEN
					DrawTab(F,1, x + F.X + tabX0, y + F.Y); DrawTab(F,1, x + F.X + tabX, y + F.Y)
				ELSE DrawBox(F, x, y, tabX0-TabW DIV 2, 0, TabW); DrawBox(F, x, y, tabX-TabW DIV 2, 0, TabW)
				END;
				tabX0 := tabX
			END
		UNTIL Keys = {};
		IF t < F.style.nTabs THEN
			DrawTab(F,1, x + F.X + tabX, y + F.Y); DrawTab(F,0, x + F.X + tabX, y + F.Y);	(*unselect*)
			IF (MR IN keysum) OR ~(left IN F.style.opts) OR (tabX >= F.W) & ~Wide(F) THEN INCL(keysum, MR);
				DrawTab(F,0, x + F.X + tabX, y + F.Y);	(* erase *)
				IF new THEN DEC(F.style.nTabs)	(* delete *)
				ELSE DrawTab(F,0, x +F.X + Screen(F.style.tab[t]), y + F.Y)	(* reset at old pos *)
				END
			END
		ELSE DrawBox(F, x, y, tabX-TabW DIV 2, 0, TabW)
		END;
		Oberon.FadeCursor(Oberon.Mouse)
	END TrackTab;

	PROCEDURE TrackMode(F: Frame; x, y, X, Y: INTEGER; VAR keysum: SET);
	VAR x0, y0: INTEGER;
		Keys: SET;
	BEGIN
		INC(x, F.X); INC(y, F.Y);
		IF (X - x > BoxW) & (X - x <= F.W DIV 2) THEN x := x + BoxW
		ELSIF (x + F.W - X > BoxW) & (x + F.W - X <= F.W DIV 2) THEN x := x + F.W DIV 2
		ELSE INCL(keysum, MR); RETURN	(*not hit: do nothing cf. Edit*)
		END;
		Display.ReplPattern(Display.FG, Display.grey1, x, y + BoxH DIV 2 + 1, F.W DIV 2-BoxW, BoxH DIV 2, 2);
		keysum := {};
		REPEAT TrackMouse(x0, y0, Keys, keysum) UNTIL Keys = {};
		Display.ReplPattern(Display.FG, Display.grey1, x, y + BoxH DIV 2 + 1, F.W DIV 2-BoxW, BoxH DIV 2, 2)
	END TrackMode;

	PROCEDURE SelStyle*(VAR style: Style);
	VAR
		T: Texts.Text;
		beg, end, time: LONGINT;
		R: Texts.Reader;
		obj: Objects.Object;
		x: CHAR;
	BEGIN
		Oberon.GetSelection(T, beg, end, time); style := NIL;
		IF time >=0 THEN
			Texts.OpenReader(R, T, beg); Texts.Read(R, x);
			R.lib.GetObj(R.lib, ORD(x), obj);
			IF obj IS Style THEN style := obj(Style) END
		END
	END SelStyle;

	PROCEDURE Edit (F: Frame; x, y, X, Y: INTEGER; Keys: SET; VAR res: INTEGER);
	VAR
		mode, keysum: SET;
		leftX, W, tabX, tab, oldleftX, modif: INTEGER;
		style: Style;
	BEGIN
		Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, X, Y);
		IF Keys = {MM} THEN
			IF X - F.X - x < BoxW THEN TrackLeft(F, x, y, X, Y, leftX, keysum);
				IF ~(MR IN keysum) THEN oldleftX := Screen(F.style.left);
					IF FALSE (*MM IN keysum*) THEN	(* center *)
						F.style.left := (pageW - F.style.paraW) DIV 2;
						leftX := Screen(F.style.left)
					ELSIF leftX # 0 THEN INC(F.style.left, Doc(leftX)); modif := leftmarg;
						IF ~(ML IN keysum) THEN DEC(F.style.paraW, Doc(leftX)); modif := width;
							DrawTabs(F, x, y); CheckTab(F.style, 0); DrawTabs(F, x, y)
						END
					END;
					IF oldleftX # leftX THEN Update(F.style, modif, oldleftX-leftX) END
				END
			ELSIF x + F.X + F.W - X < BoxW THEN
				IF Wide(F) THEN TrackRight(F, x, y, X, Y, W, keysum)
				ELSE REPEAT TrackMouse(X, Y, Keys, keysum) UNTIL Keys = {}; INCL(keysum, MR)
				END;
				IF ~(MR IN keysum) & (W # F.W) THEN
					F.style.paraW := Doc(W);
					DrawTabs(F, x, y); CheckTab(F.style, 0); DrawTabs(F, x, y);	(* drop tabs *)
					Update(F.style, width, 0)
				END
			ELSIF Y - F.Y - y <= BoxH DIV 2 THEN TrackTab(F, x, y, X, Y, tabX, tab, keysum);
				IF ~(MR IN keysum) THEN
					IF (F.style.nTabs > 0) & (tab < F.style.nTabs) THEN F.style.tab[tab] := Doc(tabX);
						DrawTabs(F, x, y); CheckTab(F.style, tab); DrawTabs(F, x, y); Update(F.style, tabs, 0)
					END
				END
			ELSE (*mode*)
				TrackMode(F, x, y, X, Y, keysum);
				IF ~(MR IN keysum) THEN
					mode := F.style.opts;
					IF X - F.X - x < F.W DIV 2 THEN	(* left *)
						IF (left IN F.style.opts) & (F.style.nTabs = 0) THEN EXCL(F.style.opts, left)
						ELSE INCL(F.style.opts, left)
						END;
						modif := left
					ELSIF x + F.X + F.W - X < F.W DIV 2 THEN	(* right *)
						IF right IN F.style.opts THEN EXCL(F.style.opts, right) ELSE INCL(F.style.opts, right) END;
						modif := right
					END;
					IF mode # F.style.opts THEN
						DrawMode(F,mode, x+F.X, y+F.Y, F.W); DrawMode(F,F.style.opts, x+F.X, y+F.Y, F.W);
						Update(F.style, fmode, modif)
					END
				END				
			END;
			res := 0
		ELSIF Keys = {ML} THEN
			REPEAT TrackMouse(X, Y, Keys, keysum) UNTIL Keys = {};
			IF MR IN keysum THEN	(*copy attributes to selection*)
				res := 0;
				IF ~(MM IN keysum) THEN SelStyle(style);
					IF style # NIL THEN	(*selection exists*)
						style.opts := F.style.opts;
						style.paraW := F.style.paraW; style.left := F.style.left; style.lsp := F.style.lsp; style.dsr := F.style.dsr;
						style.gap := F.style.gap; style.nTabs := F.style.nTabs; style.tab := F.style.tab;
						Update(style, tabs+1, 0)
					END
				END
			END;
			res := 0
		END
	END Edit;

	PROCEDURE CopyF(s, d: Frame);
	BEGIN
		d.handle := s.handle; d.lib := s.lib; d.ref := s.ref;
		d.next := s.next; d.dsc := s.dsc; d.slink := s.slink;
		d.X := s.X; d.Y := s.Y; d.W := s.W; d.H := s.H;
		d.style := s.style;
	END CopyF;
	
	PROCEDURE ToLib(lib: Objects.Library; obj: Objects.Object);
	VAR ref: INTEGER;
	BEGIN IF (lib # NIL) & (obj.lib = NIL) THEN lib.GenRef(lib, ref); lib.PutObj(lib, ref, obj) END
	END ToLib;

	PROCEDURE Restore(F: Frame; x, y: INTEGER);
	BEGIN
		Oberon.RemoveMarks(x+F.X, y+F.Y, F.W, F.H);
		Display.ReplConst(F.col, x+F.X, y+F.Y, F.W, F.H, 0);
		DrawBar(F, x, y, F.W)
	END Restore;

	PROCEDURE *FHandle(F: Objects.Object; VAR M: Objects.ObjMsg);	(* volatile frame never stored/bound etc. *)
	VAR
		F1: Frame;
		cx, cy, cw, ch: INTEGER;
		x, y: INTEGER;
	BEGIN
		WITH F: Frame DO
			Display.GetClip(cx, cy, cw, ch); Display.ResetClip;
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					x := M.x; y := M.y;
					IF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & (F.H = BoxH) THEN Edit(F, x, y, M.X, M.Y, M.keys, M.res) END
						END
					ELSIF M IS Display.DisplayMsg THEN
						IF (F = M.F) & (M(Display.DisplayMsg).device = Display.screen) THEN Restore(F, x, y) END
(*
					ELSIF M IS Display.SelectMsg THEN
						WITH M: Display.SelectMsg DO
							IF M.id = Display.set THEN F.sel := 1
							ELSIF M.id = Display.reset THEN F.sel := 0
							END
						END
*)
					ELSIF M IS Display.ModifyMsg THEN
						WITH M: Display.ModifyMsg DO
							IF (M.id = Display.move) & (M.F = F)  & (M.mode # Display.state) THEN
								F.Y := M.Y; F.X := M.X; Restore(F, x, y)
							END
						END
					ELSIF M IS UpdateMsg THEN
						WITH M: UpdateMsg DO
							IF F.style = M.obj THEN Restore(F, x, y) END
						END
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					NEW(F1); CopyF(F, F1);	(* F1^ := F^; *)
					IF M.id = Objects.deep THEN F.style.handle(F.style, M); F1.style := M.obj(Style) END;
					M.obj := F1
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Transparent" THEN M.b := TRUE END
					END
				END
			ELSE F.style.handle(F.style, M)
			END;
			Display.SetClip(cx, cy, cw, ch)
		END
	END FHandle;

	PROCEDURE Copy(s, d: Style);
	BEGIN
		d.handle := s.handle; d.lib := NIL; d.ref := 0;
		d.opts := s.opts;
		d.paraW := s.paraW; d.left := s.left; d.lsp := s.lsp; d.gap := s.gap;
		d.nTabs := s.nTabs; d.tab := s.tab
	END Copy;

	PROCEDURE WTenth(n: LONGINT);
	BEGIN Texts.WriteInt(W, n DIV tenth, 8)
	END WTenth;

	PROCEDURE Tenth(VAR M: ParamMsg; max: LONGINT; VAR n: LONGINT);
	BEGIN
		IF M.id = get THEN Texts.WriteInt(W, n DIV tenth, 8)
		ELSE Texts.Scan(M.S);
			IF M.S.class = Texts.Int THEN M.S.i := M.S.i * tenth;
				IF (0 <= M.S.i) & (M.S.i <= max) THEN n := M.S.i END
			END
		END
	END Tenth;

	PROCEDURE LibMetrics(VAR M: ParamMsg; VAR height, dsr: LONGINT);
	VAR fnt: Fonts.Font;
	BEGIN
		IF M.id = get THEN Texts.WriteInt(W, height DIV tenth, 8)
		ELSE Texts.Scan(M.S);
			height := 34*tenth; dsr := height DIV 4;	(*default*)
			IF M.S.class = Texts.Int THEN M.S.i := M.S.i * tenth;
				height := M.S.i; dsr := height DIV 4
			ELSIF (M.S.class = Texts.Name) & (M.S.s # "default") THEN fnt := Fonts.This(M.S.s);
				IF fnt.type = Fonts.font THEN
(*
					height := LONG(fnt.height)*ScnUnit;	(*line height = 1.2*font height*)
					dsr := -LONG(fnt.minY)*ScnUnit;
*)
					height := LONG(6*fnt.maxY DIV 5)*ScnUnit; dsr := LONG(6*fnt.height DIV 5)*ScnUnit - height;
					height := height+dsr
				END
			END
		END
	END LibMetrics;

	PROCEDURE WString(first: BOOLEAN; s, t: ARRAY OF CHAR);
	BEGIN Texts.Write(W, " ");
		IF first THEN Texts.WriteString(W, s) ELSE Texts.WriteString(W, t) END
	END WString;

	PROCEDURE String(VAR M: ParamMsg; flag: INTEGER; VAR set: SET; s, t: ARRAY OF CHAR);
	BEGIN
		IF M.id = get THEN Texts.Write(W, " ");
			IF flag IN set THEN Texts.WriteString(W, s) ELSE Texts.WriteString(W, t) END
		ELSE Texts.Scan(M.S);
			IF M.S.class = Texts.Name THEN
				IF M.S.s = s THEN INCL(set, flag)
				ELSIF M.S.s = t THEN EXCL(set, flag)
				END
			END
		END
	END String;

	PROCEDURE Params(s: Style; VAR M: ParamMsg);
	VAR
		hint, i, dX: INTEGER;
		old, dmy, right: LONGINT;
	BEGIN
		(*WHILE M.S.class = Texts.Name DO*)
		IF M.S.class = Texts.Name THEN
			IF M.id = get THEN Texts.WriteString(W, M.S.s) END;
			IF M.S.s = Left THEN old := s.left;
				Tenth(M, pageW-s.paraW, s.left);
				hint := leftmarg; dX := Screen(old - s.left)
			ELSIF M.S.s = Width THEN
				Tenth(M, pageW, s.paraW);
				hint := width; dX := 0
			ELSIF M.S.s = Right THEN
				right := s.left + s.paraW;
				Tenth(M, pageW - s.left, right);
				IF M.id = set THEN s.paraW := right - s.left END;
				hint := width; dX := 0
			ELSIF M.S.s = Gap THEN LibMetrics(M, s.gap, dmy); hint := tabs+1; dX := 0
			ELSIF M.S.s = Lsp THEN LibMetrics(M, s.lsp, s.dsr); hint := tabs+1; dX := 0
			ELSIF M.S.s = Grid THEN String(M, grid, s.opts, "on", "off"); hint := tabs+1; dX := 0
			ELSIF M.S.s = Break THEN String(M, break, s.opts, Bef, Norm); hint := -1; dX := 0
			ELSIF M.S.s = Adj THEN
				IF M.id = get THEN
					IF left IN s.opts THEN WString(right IN s.opts, Block, Left)
					ELSE WString(right IN s.opts, Right, Cent)
					END
				ELSE Texts.Scan(M.S);
					IF M.S.s = Block THEN INCL(s.opts, left); INCL(s.opts, right)
					ELSIF M.S.s = Left THEN INCL(s.opts, left); EXCL(s.opts, right)
					ELSIF M.S.s = Cent THEN EXCL(s.opts, left); EXCL(s.opts, right)
					ELSIF M.S.s = Right THEN EXCL(s.opts, left); INCL(s.opts, right)
					END
				END;
				hint := fmode; dX := 0
			ELSIF M.S.s = Tabs THEN
				IF M.id = get THEN
					i := 0; WHILE i < s.nTabs DO WTenth(s.tab[i]); INC(i) END;
					Texts.WriteString(W, " ~")
				ELSE s.nTabs := 0;
					REPEAT Tenth(M, s.paraW, s.tab[s.nTabs]); INC(s.nTabs)
					UNTIL (M.S.class # Texts.Int) OR (s.nTabs = 32);
					DEC(s.nTabs);
					hint := tabs; dX := 0
				END
			ELSIF M.S.s = "name" THEN Texts.Scan(M.S);
				IF M.S.class = Texts.Name THEN Objects.PutName(s.lib.dict, s.ref, M.S.s); hint := -1; dX := 0 END
			ELSE Texts.WriteString(W, " ???")
			END;
			IF M.id = get THEN Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			ELSE Update(s, hint, dX)
			END;
			(*Texts.Scan(S)*)
		END
	END Params;

	PROCEDURE *Handle(obj: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			ob1: Style;
	BEGIN
		WITH obj: Style DO
			IF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					NEW(ob1); Copy(obj, ob1); M.obj := ob1;
				END
			ELSIF M IS Objects.BindMsg THEN
				WITH M: Objects.BindMsg DO ToLib(M.lib, obj) END
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					IF M.id = Objects.load THEN ReadData(M.R, obj)
					ELSE (*store*) WriteData(M.R, obj)
					END
				END
			ELSIF M IS ParamMsg THEN Params(obj, M(ParamMsg))
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN M.s := "Styles.New" END
				END
			END
		END
	END Handle;

	PROCEDURE DefStyle(style: Style);
	BEGIN
		style.opts := {left}; style.paraW := pageW; style.left := 0; style.lsp := 0; style.gap := 0; style.nTabs := 0
	END DefStyle;

	PROCEDURE NewStyle* (): Objects.Object;
		VAR S: Style;
	BEGIN NEW(S); DefStyle(S); S.handle := Handle; RETURN S
	END NewStyle;

	PROCEDURE NewFrame* (style: Style): Display.Frame;
		VAR F: Frame;
	BEGIN
		NEW(F); F.handle := FHandle; F.W := scnW; F.H := BoxH; F.style := style; RETURN F
	END NewFrame;

(* ------ commands ------ *)

	PROCEDURE New*;
	BEGIN Objects.NewObj := NewStyle()
	END New;

	PROCEDURE Gimme*;	(*compatibility*)
	BEGIN New
	END Gimme;

	PROCEDURE Init;
		VAR obj: Objects.Object;
		img: ARRAY 32 OF SET;
		i: LONGINT;
	BEGIN
		obj := NewStyle(); defStyle := obj(Style);
		img[0] := {0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30}; (*055555555H*)
		FOR i := 1 TO 31 DO
			img[i] := img[0]
		END;
		dash := Display.NewPattern(32, 32, img);
		img[0] := {2,6,10,14,18,22,26,30}; (*044444444H*)
		FOR i := 1 TO 31 DO
			img[i] := img[0]
		END;
		dash2 := Display.NewPattern(32, 32, img)
(*
		pat[0] := CHR(32); pat[1] := 1X;
		pat[2] := 055X; pat[3] := 055X; pat[4] := 055X; pat[5] := 055X;
		dash := SYSTEM.ADR(pat);
		pat2[0] := CHR(32); pat2[1] := 1X;
		pat2[2] := 044X; pat2[3] := 044X; pat2[4] := 044X; pat2[5] := 044X;
		dash2 := SYSTEM.ADR(pat2)
*)
	END Init;

BEGIN
	Texts.OpenWriter(W); Init;
	NEW(font); font.next := font; font.name[0] := 0X;
	nfnt := Fonts.This("Default8.Scn.Fnt")
END Styles.
