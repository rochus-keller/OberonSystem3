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

MODULE Shanghai;	(** portable *)	(* ps /   *)

(* ToDo:
	smaller board (64 -> 32)
	3D look?
	sel wenn hit und crosscheck, toggle while mouse move 
*)

IMPORT
	Files, Input, Objects, Fonts, Strings, Display, Display3, Printer, Printer3, Effects, Texts, Oberon, Gadgets,
	Documents, Desktops;

CONST
	Version = "V 1.0";
	IconName = "Icons.EmptyDoc";
	MenuString = "Shanghai.Undo[Undo] Shanghai.Start[New]";

	Tiles = 144; TileW = 64; TileH = 64; TileCol = 12;
	BoardW = 15*TileW; BoardH = 8 * TileH;
	Border = 3;

	FaceFontName = "Shanghai.Scn.Fnt";
	TextFontName = "Oberon24b.Scn.Fnt";

TYPE
	Tile = RECORD
		x, y: INTEGER;
		left, right, top: INTEGER;
		face, col: INTEGER;
		valid: BOOLEAN
	END;

	Frame = POINTER TO FrameDesc;
	FrameDesc = RECORD (Gadgets.FrameDesc)
		time: LONGINT;
		nofTiles: INTEGER;
		sel1, sel2: INTEGER;
		over: BOOLEAN;
		moves: ARRAY Tiles OF INTEGER;
		board: ARRAY Tiles + 1 OF Tile
	END;

	UndoMsg = RECORD (Display.FrameMsg)
	END;

VAR
	DoubleClick: LONGINT;
	seed: LONGINT;
	faceFnt, textFnt: Fonts.Font;
	W: Texts.Writer;

PROCEDURE Random ( z : INTEGER) : INTEGER;
CONST a = 16807; m = 2147483647; q = m DIV a; r = m MOD a;
VAR g: LONGINT;
BEGIN
	g := a*(seed MOD q) - r*(seed DIV q);
	IF g > 0 THEN seed := g ELSE seed := g + m END;
	RETURN SHORT(ENTIER(seed*(1.0/m)*z))
END Random;

PROCEDURE InitBoard (F: Frame);
CONST MH = 4*TileH - TileH DIV 2;
VAR c, i: INTEGER;

	PROCEDURE InitTile (nr, x, y, l, r, t, col: INTEGER);
	BEGIN
		F.board[nr].x := x; F.board[nr].y := y; F.board[nr].col := col;
		F.board[nr].left := l; F.board[nr].right := r; F.board[nr].top := t
	END InitTile;

BEGIN
	(* init sentinel *)
	InitTile(0, MIN(INTEGER), MIN(INTEGER), 0, 0, 0, 0); F.board[0].valid := FALSE;
	
	(* init top level *)
	c := 243;
	InitTile(1, 7*TileW - TileW DIV 2, MH, 0, 0, 0, c);

	(* init 2nd level *)
	c := 228;
	InitTile(2, 6*TileW, 3*TileH, 0, 3, 1, c); InitTile(3, 7*TileW, 3*TileH, 2, 0, 1, c);
	InitTile(4, 6*TileW, 4*TileH, 0, 5, 1, c); InitTile(5, 7*TileW, 4*TileH, 4, 0, 1, c);

	(* init 3rd level *)
	c := 249;
	InitTile(6, 5*TileW, 2*TileH, 0, 7, 0, c); InitTile(7, 6*TileW, 2*TileH, 6, 8, 0, c);
	InitTile(8, 7*TileW, 2*TileH, 7, 9, 0, c); InitTile(9, 8*TileW, 2*TileH, 8, 0, 0, c);
	InitTile(10, 5*TileW, 3*TileH, 0, 11, 0, c); InitTile(11, 6*TileW, 3*TileH, 10, 12, 2, c);
	InitTile(12, 7*TileW, 3*TileH, 11, 13, 3, c); InitTile(13, 8*TileW, 3*TileH, 12, 0, 0, c);
	InitTile(14, 5*TileW, 4*TileH, 0, 15, 0, c); InitTile(15, 6*TileW, 4*TileH, 14, 16, 4, c);
	InitTile(16, 7*TileW, 4*TileH, 15, 17, 5, c); InitTile(17, 8*TileW, 4*TileH, 16, 0, 0, c);
	InitTile(18, 5*TileW, 5*TileH, 0, 19, 0, c); InitTile(19, 6*TileW, 5*TileH, 18, 20, 0, c);
	InitTile(20, 7*TileW, 5*TileH, 19, 21, 0, c); InitTile(21, 8*TileW, 5*TileH, 20, 0, 0, c);

	(* init 4th level *)
	c := 126;
	InitTile(22, 4*TileW, TileH, 0, 23, 0, c); InitTile(23, 5*TileW, TileH, 22, 24, 0, c); InitTile(24, 6*TileW, TileH, 23, 25, 0, c);
	InitTile(25, 7*TileW, TileH, 24, 26, 0, c); InitTile(26, 8*TileW, TileH, 25, 27, 0, c); InitTile(27, 9*TileW, TileH, 26, 0, 0, c);
	InitTile(28, 4*TileW, 2*TileH, 0, 29, 0, c); InitTile(29, 5*TileW, 2*TileH, 28, 30, 6, c); InitTile(30, 6*TileW, 2*TileH, 29, 31, 7, c);
	InitTile(31, 7*TileW, 2*TileH, 30, 32, 8, c); InitTile(32, 8*TileW, 2*TileH, 31, 33, 9, c); InitTile(33, 9*TileW, 2*TileH, 32, 0, 0, c);
	InitTile(34, 4*TileW, 3*TileH, 0, 35, 0, c); InitTile(35, 5*TileW, 3*TileH, 34, 36, 10, c); InitTile(36, 6*TileW, 3*TileH, 35, 37, 11, c); 
	InitTile(37, 7*TileW, 3*TileH, 36, 38, 12, c); InitTile(38, 8*TileW, 3*TileH, 37, 39, 13, c); InitTile(39, 9*TileW, 3*TileH, 38, 0, 0, c);
	InitTile(40, 4*TileW, 4*TileH, 0, 41, 0, c); InitTile(41, 5*TileW, 4*TileH, 40, 42, 14, c); InitTile(42, 6*TileW, 4*TileH, 41, 43, 15, c);
	InitTile(43, 7*TileW, 4*TileH, 42, 44, 16, c); InitTile(44, 8*TileW, 4*TileH, 43, 45, 17, c); InitTile(45, 9*TileW, 4*TileH, 44, 0, 0, c);
	InitTile(46, 4*TileW, 5*TileH, 0, 47, 0, c); InitTile(47, 5*TileW, 5*TileH, 46, 48, 18, c); InitTile(48, 6*TileW, 5*TileH, 47, 48, 19, c);
	InitTile(49, 7*TileW, 5*TileH, 48, 50, 20, c); InitTile(50, 8*TileW, 5*TileH, 49, 51, 21, c); InitTile(51, 9*TileW, 5*TileH, 50, 0, 0, c);
	InitTile(52, 4*TileW, 6*TileH, 0, 53, 0, c); InitTile(53, 5*TileW, 6*TileH, 52, 54, 0, c); InitTile(54, 6*TileW, 6*TileH, 53, 55, 0, c); 
	InitTile(55, 7*TileW, 6*TileH, 54, 56, 0, c); InitTile(56, 8*TileW, 6*TileH, 55, 57, 0, c); InitTile(57, 9*TileW, 6*TileH, 56, 0, 0, c);

	(* init bottom level *)
	c := 79;
	FOR i := 58 TO 69 DO InitTile(i, (i - 57)* TileW, 0, i - 1, i + 1, 0, c) END;
		F.board[58].left := 0; F.board[69].right := 0;
	FOR i := 70 TO 77 DO InitTile(i, (i - 67)* TileW, TileH, i - 1, i + 1, i - 49, c) END;
		F.board[70].left := 0; F.board[70].top := 0; F.board[77].right := 0; F.board[77].top := 0;
	FOR i := 78 TO 87 DO InitTile(i, (i - 76)* TileW, 2*TileH, i - 1, i + 1, 0, c) END;
		FOR i := 80 TO 85 DO F.board[i].top := i - 52 END;
		F.board[78].left := 0; F.board[87].right := 0;
	FOR i := 88 TO 99 DO InitTile(i, (i - 87)* TileW, 3*TileH, i -1, i + 1, 0, c) END;
		FOR i := 91 TO 96 DO F.board[i].top := i - 57 END;
		F.board[88].left := 100; F.board[99].right := 113;
	InitTile(100, 0, MH, 0, 88, 0, c); InitTile(113, 13*TileW, MH, 99, 114, 0, c); InitTile(114, 14*TileW, MH, 113, 0, 0, c);
	FOR i := 101 TO 112 DO InitTile(i, (i - 100)* TileW, 4*TileH, i - 1, i + 1, 0, c) END;
		FOR i := 104 TO 109 DO F.board[i].top := i - 64 END;
	FOR i := 115 TO 124 DO InitTile(i, (i - 113)* TileW, 5*TileH, i - 1, i + 1, 0, c) END;
		FOR i := 117 TO 122 DO F.board[i].top := i - 71 END;
		F.board[115].left := 0; F.board[124].right := 0;
	FOR i := 125 TO 132 DO InitTile(i, (i - 122)* TileW, 6*TileH, i - 1, i + 1, i - 74, c) END;
		F.board[125].left := 0; F.board[125].top := 0; F.board[132].right := 0; F.board[132].top := 0;
	FOR i := 133 TO 144 DO InitTile(i, (i - 132)* TileW, 7*TileW, i - 1, i + 1, 0, c) END;
		F.board[133].left := 0; F.board[144].right := 0
END InitBoard;

PROCEDURE NewGame (F: Frame);
VAR i, k: INTEGER; faces: ARRAY Tiles OF INTEGER;
BEGIN
	(* init tiles array *)
	k := 32;
	FOR i := 0 TO 135 BY 4 DO
		faces[i] := k; faces[i + 1] := k; faces[i + 2] := k; faces[i + 3] := k;
		INC(k)
	END;
	FOR i := 136 TO 143 DO faces[i] := i - 70 END;

	(* setup board *)
	F.over := FALSE;
	F.sel1 := 0; F.sel2 := 0;
	F.nofTiles := Tiles;
	FOR i := Tiles - 1 TO 0 BY -1 DO
		k := Random(i);
		F.board[Tiles - i].face := faces[k]; faces[k] := faces[i];
		F.board[Tiles - i].valid := TRUE
	END
END NewGame;

PROCEDURE FindTile (F: Frame; x, y, X, Y: INTEGER): INTEGER;
VAR i: INTEGER;
BEGIN
	i := 0; X := X - x; Y := Y - y;
	REPEAT
		INC(i); x := F.board[i].x; y := F.board[i].y
	UNTIL (i = Tiles) OR (x <= X) & (X < x+TileW) & (y <= Y) & (Y < y+TileH) & F.board[i].valid;
	IF (i = Tiles) & ((X < x) OR (x+TileW <= X) OR (Y < y) OR (y+TileH <= Y) OR ~F.board[Tiles].valid) THEN INC(i) END;
	RETURN i	(* i = Tiles + 1 if no free tile could be found *)
END FindTile;

PROCEDURE IsFree (F: Frame; VAR tile: Tile): BOOLEAN;
BEGIN
	RETURN ~F.board[tile.top].valid & ~(F.board[tile.right].valid & F.board[tile.left].valid)
END IsFree;

PROCEDURE GetTile (F: Frame; x, y, X, Y: INTEGER): INTEGER;
VAR i: INTEGER;
BEGIN
	i := FindTile(F, x, y, X, Y);
	IF (i > Tiles) OR ~IsFree(F, F.board[i]) THEN i := Tiles + 1 END;
	RETURN i
END GetTile;

PROCEDURE IsSame (face1, face2: INTEGER): BOOLEAN;
VAR res: BOOLEAN;
BEGIN
	IF (face1 < 66) & (face2 < 66) THEN res := (face1 = face2) 
	ELSIF (face1 >= 66) & (face2 >= 66) THEN res := ((face1 - 66) DIV 4 = (face2 - 66) DIV 4)
	ELSE res := FALSE
	END;
	RETURN res
END IsSame;

PROCEDURE FindSame (F: Frame; tileNr: INTEGER; VAR same: ARRAY OF INTEGER; VAR cnt: INTEGER);
VAR i, face: INTEGER; tile: Tile;
BEGIN
	i := 1; cnt := 0; face := F.board[tileNr].face;
	WHILE (i <= Tiles) DO
		tile := F.board[i];
		IF (i # tileNr) & tile.valid & IsSame(tile.face, face) THEN
			IF IsFree(F, tile) THEN same[cnt] := i; INC(cnt) END
		END;
		INC(i)
	END
END FindSame;

PROCEDURE IsOver (F: Frame): BOOLEAN;
VAR same: ARRAY 4 OF INTEGER; i, cnt: INTEGER;
BEGIN
	i := 1; cnt := 0;
	WHILE (i <= Tiles) & (cnt = 0) DO
		IF F.board[i].valid & IsFree(F, F.board[i]) THEN FindSame(F, i, same, cnt) END;
		INC(i)
	END;
	F.over := (cnt = 0);
	RETURN F.over
END IsOver;

PROCEDURE DrawTile (Q: Display3.Mask; col, x, y: INTEGER; VAR tile: Tile);
VAR pat: Display.Pattern; cx, cy, cw, ch, cdx: INTEGER;
BEGIN
	Fonts.GetChar(faceFnt, CHR(tile.face), cdx, cx, cy, cw, ch, pat);
	cx := x + tile.x; cy := y + tile.y;
	Display3.ReplConst(Q, col, cx, cy, TileW, TileH, Display.replace);
	Display3.CopyPattern(Q, Display3.black, pat, cx, cy, Display.paint)
END DrawTile;

PROCEDURE DrawCount (Q: Display3.Mask; x, y, cnt: INTEGER);
VAR str: ARRAY 4 OF CHAR; bw, bh, w, h, dsr: INTEGER;
BEGIN
	x := x + BoardW - 20; y := y + BoardH - 20;
	bw := 7*textFnt.maxX DIV 3; bh := textFnt.height;
	Display3.FilledRect3D(Q, Display3.bottomC, Display3.topC, Display3.groupC, x - bw, y - bh, bw, bh, 1, Display.replace);

	Strings.IntToStr(cnt, str);
	Display3.StringSize(str, textFnt, w, h, dsr);
	Display3.String(Q, Display3.black, x - bw DIV 2 - w DIV 2, y - bh DIV 2 - (h - dsr) DIV 2, textFnt, str, Display.paint)
END DrawCount;

PROCEDURE DrawGameOver (F: Frame; Q: Display3.Mask; x, y: INTEGER);
VAR w, h, dsr: INTEGER; text: ARRAY 24 OF CHAR;
BEGIN
	IF F.nofTiles = 0 THEN text := "Congratulations!" ELSE text := "Game Over..." END;
	Display3.StringSize(text, textFnt, w, h, dsr); INC(w, 8); INC(h, 4);
	x := x + BoardW DIV 2 - w DIV 2; y := y + BoardH DIV 2 - h DIV 2;
	Display3.FilledRect3D(Q, Display3.bottomC, Display3.topC, Display3.groupC, x, y, w, h, 1, Display.replace);
	Display3.CenterString(Q, Display3.black, x, y, w, h, textFnt, text, Display.paint)
END DrawGameOver;

PROCEDURE FlashTiles (F: Frame; Q: Display3.Mask; x, y: INTEGER; tiles: ARRAY OF INTEGER; cnt: INTEGER);
VAR i, time: LONGINT;
BEGIN
	FOR i := 0 TO cnt DO DrawTile(Q, 12, x, y, F.board[tiles[i]]) END;
	time := Oberon.Time() + Input.TimeUnit;
	WHILE Oberon.Time() - time < 0 DO END;
	IF F.sel1 > 0 THEN DEC(cnt); DrawTile(Q, Display3.white, x, y, F.board[F.sel1]) END;
	FOR i := 0 TO cnt DO DrawTile(Q, F.board[tiles[i]].col, x, y, F.board[tiles[i]]) END
END FlashTiles;

PROCEDURE RemoveTiles (F: Frame; Q: Display3.Mask; x, y: INTEGER);

	PROCEDURE DrawBelow (tileNr: INTEGER);
	VAR nr: INTEGER;
	BEGIN
		IF tileNr = 1 THEN
			DrawTile(Q, F.board[2].col, x, y, F.board[2]); DrawTile(Q, F.board[3].col, x, y, F.board[3]);
			DrawTile(Q, F.board[4].col, x, y, F.board[4]); DrawTile(Q, F.board[5].col, x, y, F.board[5])
		ELSE
			nr := FindTile(F, x, y, x + F.board[tileNr].x, y + F.board[tileNr].y);
			IF nr <= Tiles THEN
				DrawTile(Q, F.board[nr].col, x, y, F.board[nr])
			ELSE
				Display3.ReplConst(Q, Display3.groupC, x + F.board[tileNr].x, y + F.board[tileNr].y, TileW, TileH, Display.replace)
			END
		END;
	END DrawBelow;

BEGIN
	IF (F.sel1 > 0) & (F.sel2 > 0) THEN
		F.board[F.sel1].valid := FALSE; F.board[F.sel2].valid := FALSE;
		DrawBelow(F.sel1); DrawBelow(F.sel2);
		DEC(F.nofTiles, 2); DrawCount(Q, x, y, F.nofTiles);
		F.moves[F.nofTiles] := F.sel1; F.moves[F.nofTiles + 1] := F.sel2;
		F.sel1 := 0; F.sel2 := 0;

		IF IsOver(F) THEN DrawGameOver(F, Q, x, y) END
	END
END RemoveTiles;

(* ------------------------ frame stuff ------------------------ *)

PROCEDURE Restore (F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER);
VAR i: INTEGER; tile: Tile;
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	Display3.ReplConst(Q, Display3.groupC, x, y, w, h, Display.replace);
	INC(x, Border); INC(y, Border);
	FOR i := 144 TO 6 BY -1 DO
		tile := F.board[i]; IF tile.valid & ~F.board[tile.top].valid THEN DrawTile(Q, tile.col, x, y, tile) END
	END;
	FOR i := 5 TO 2 BY -1 DO
		tile := F.board[i]; IF tile.valid THEN DrawTile(Q, tile.col, x, y, tile) END
	END;
	IF F.board[1].valid THEN DrawTile(Q, F.board[1].col, x, y, F.board[1]) END;

	IF F.sel1 > 0 THEN DrawTile(Q, Display3.white, x, y, F.board[F.sel1]) END;
	IF F.sel2 > 0 THEN DrawTile(Q, Display3.white, x, y, F.board[F.sel2]) END;
	DrawCount(Q, x, y, F.nofTiles);
	IF F.over THEN DrawGameOver(F, Q, x, y) END;

	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(Q, Display3.white, Display3.selectpat, 0, 0, x - Border, y - Border, w, h, Display.paint)
	END
END Restore;

PROCEDURE Print (F: Frame; VAR M: Display.DisplayMsg);
VAR Q: Display3.Mask;

	PROCEDURE P (x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(LONG(x) * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, Q);
	Printer3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC, M.x, M.y, P(F.W), P(F.H), P(1), Display.replace);
	Printer3.CenterString(Q, Display3.black, M.x, M.y, P(F.W), P(F.H), textFnt, "- | Shanghai | -", Display.paint)
END Print;

PROCEDURE Track (F: Frame; VAR M: Oberon.InputMsg);
VAR Q: Display3.Mask; keysum: SET; x, y, nr, cnt: INTEGER; same: ARRAY 4 OF INTEGER;
BEGIN
	x := M.x + F.X + Border; y := M.y + F.Y + Border;
	IF Effects.Inside(M.X, M.Y, x, y, BoardW, BoardH) THEN
		IF M.keys = {0} THEN	(* right key *)
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
			keysum := {};
			REPEAT
				keysum := keysum + M.keys;
				Input.Mouse(M.keys, M.X, M.Y);
				nr := GetTile(F, x, y, M.X, M.Y);
				IF (nr <= Tiles) & ((F.sel1 = 0) OR (IsSame(F.board[F.sel1].face, F.board[nr].face))) THEN
					Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y)
				ELSE
					Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y)
				END
			UNTIL M.keys = {};
			IF (keysum = {0}) & (nr <= Tiles) THEN
				Oberon.RemoveMarks(x, y, F.W, F.H);
				Gadgets.MakeMask(F, x, y, M.dlink, Q);
				IF nr = F.sel1 THEN
					IF (0 < F.time + DoubleClick - Oberon.Time()) & (F.sel2 > 0)  THEN RemoveTiles(F, Q, x, y)
					ELSE F.sel1 := 0; DrawTile(Q, F.board[nr].col, x, y, F.board[nr])
					END
				ELSIF nr = F.sel2 THEN
					IF (0 < F.time + DoubleClick - Oberon.Time()) & (F.sel1 > 0)  THEN RemoveTiles(F, Q, x, y)
					ELSE F.sel2 := 0; DrawTile(Q, F.board[nr].col, x, y, F.board[nr])
					END
				ELSE
					IF F.sel1 > 0 THEN
						IF IsSame(F.board[F.sel1].face, F.board[nr].face) THEN
							F.sel2 := nr; DrawTile(Q, Display3.white, x, y, F.board[nr])
						END
					ELSE
						F.sel1 := nr; DrawTile(Q, Display3.white, x, y, F.board[nr])
					END
				END;
				F.time := Oberon.Time()
			END
		ELSIF M.keys = {1} THEN	(* middle key *)
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
			keysum := {};
			REPEAT
				keysum := keysum + M.keys;
				Input.Mouse(M.keys, M.X, M.Y);
				nr := GetTile(F, x, y, M.X, M.Y);
				IF (nr <= Tiles) & ((F.sel1 > 0) OR (IsSame(F.board[F.sel1].face, F.board[nr].face))) THEN
					Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y)
				ELSE
					Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y)
				END
			UNTIL M.keys = {};
			IF (keysum = {1}) & (nr <= Tiles) THEN
				IF (F.sel1 = 0) OR (nr = F.sel1) THEN
					IF F.board[nr].valid & IsFree(F, F.board[nr]) THEN
						FindSame(F, nr, same, cnt);
						IF cnt > 0 THEN
							Gadgets.MakeMask(F, x, y, M.dlink, Q);
							same[cnt] := nr;
							Oberon.RemoveMarks(x, y, F.W, F.H);
							FlashTiles(F, Q, x, y, same, cnt)
						END
					END
				ELSIF IsSame(F.board[F.sel1].face, F.board[nr].face) THEN
					Gadgets.MakeMask(F, x, y, M.dlink, Q);
					Oberon.RemoveMarks(x, y, F.W, F.H);
					F.sel2 := nr; RemoveTiles(F, Q, x, y)	
				END
			END
		ELSE
			nr := GetTile(F, x, y, M.X, M.Y);
			IF (nr <= Tiles) & ((F.sel1 = 0) OR (IsSame(F.board[F.sel1].face, F.board[nr].face))) THEN
				Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, M.X, M.Y)
			ELSE
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y)
			END
		END
	ELSE
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y)
	END;
	M.res := 0
END Track;

PROCEDURE Attributes (F: Frame; VAR M: Objects.AttrMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Gen") THEN
		COPY("Shanghai.NewFrame", M.s); M.res := 0
	ELSE Gadgets.framehandle(F, M)
	END
END Attributes;

PROCEDURE Copy* (VAR M: Objects.CopyMsg; from, to: Frame);
VAR i: LONGINT;
BEGIN
	Gadgets.CopyFrame(M, from, to);
	to.nofTiles := from.nofTiles;
	FOR i := 0 TO Tiles DO to.board[i] := from.board[i] END
END Copy;

PROCEDURE Handler* (F: Objects.Object; VAR M: Objects.ObjMsg);
VAR F0: Frame; Q: Display3.Mask; x, y, t1, t2: INTEGER;
BEGIN
	WITH F: Frame DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg DO
							IF M.device = Display.screen THEN
								x := M.x + F.X; y := M.y + F.Y;
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									Restore(F, Q, x, y, F.W, F.H)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									Display3.AdjustMask(Q, x + M.u, y + F.H - 1 + M.v, M.w, M.h);
									Restore(F, Q, x, y, F.W, F.H)
								END
							ELSIF M.device = Display.printer THEN Print(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) THEN Track(F, M)
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS UndoMsg THEN
						x := M.x + F.X; y := M.y + F.Y;
						Gadgets.MakeMask(F, x, y, M.dlink, Q);

						t1 := F.moves[F.nofTiles]; F.board[t1].valid := TRUE; INC(F.nofTiles);
						t2 := F.moves[F.nofTiles]; F.board[t2].valid := TRUE; INC(F.nofTiles);
						IF F.over THEN
							F.over := FALSE;
							Restore(F, Q, x, y, F.W, F.H)
						ELSE
							INC(x, Border); INC(y, Border); 
							DrawTile(Q, F.board[t1].col, x, y, F.board[t1]);
							DrawTile(Q, F.board[t2].col, x, y, F.board[t2]);
							DrawCount(Q, x, y, F.nofTiles)
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
		ELSIF M IS Objects.AttrMsg THEN
			Attributes(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE
					F.stamp := M.stamp;
					NEW(F0); Copy(M, F, F0); F.dlink := F0; M.obj := F0;
				END
			END
		ELSE Gadgets.framehandle(F, M)
		END
	END
END Handler;

PROCEDURE Init* (F: Frame);
BEGIN
	F.W := BoardW + 2*Border; F.H := BoardH + 2*Border;
	F.handle := Handler;
	InitBoard(F); NewGame(F)
END Init;

PROCEDURE New*;
VAR F: Frame;
BEGIN NEW(F); Init(F); Objects.NewObj := F
END New;

(* ------------------------ document stuff ------------------------ *)

PROCEDURE Load (D: Documents.Document);
VAR F: Files.File; R: Files.Rider; f: Frame; x, y, w, h: INTEGER; name: ARRAY 64 OF CHAR; ch: CHAR;
BEGIN
	NEW(f); Init(f);

	F := Files.Old(D.name);
	IF F # NIL THEN
		Files.Set(R, F, 0);
		Files.ReadInt(R, x);
		IF x = Documents.Id THEN
			Files.ReadString(R, name);
			Files.ReadInt(R, x); Files.ReadInt(R, y); Files.ReadInt(R, w); Files.ReadInt(R, h)
		END
	ELSE COPY("Shanghai.Game", D.name)
	END;
	Documents.Init(D, f)	
END Load;

PROCEDURE Store (D: Documents.Document);
VAR F: Files.File; R: Files.Rider;
BEGIN
	Texts.WriteString(W, "Store "); Texts.Append(Oberon.Log, W.buf);
	IF D.name # "" THEN
		F := Files.New(D.name);
		IF F = NIL THEN HALT(99) END;

		Files.Set(R, F, 0);
		Files.WriteInt(R, Documents.Id); Files.WriteString(R, "Shanghai.NewDoc");
		Files.WriteInt(R, D.X); Files.WriteInt(R, D.Y); Files.WriteInt(R, D.W); Files.WriteInt(R, D.H);
		Files.Register(F);
		
		Texts.Write(W, 22X); Texts.WriteString(W, D.name); Texts.Write(W, 22X)
	ELSE Texts.WriteString(W, "[Untitled document]")
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END Store;

PROCEDURE DocHandler (D: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH D: Documents.Document DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN M.class := Objects.String; M.s := "Shanghai.NewDoc"; M.res := 0
					ELSIF M.name = "Adaptive" THEN M.class := Objects.Bool; M.b := FALSE; M.res := 0
					ELSIF M.name = "Icon" THEN M.class := Objects.String; M.s := IconName; M.res := 0
					ELSE Documents.Handler(D, M)
					END
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF (M.id = Objects.get) & ((M.name = "DeskMenu") OR (M.name = "SystemMenu") OR (M.name = "UserMenu")) THEN
					M.obj := Desktops.NewMenu(MenuString);
					M.res := 0
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Display.DisplayMsg THEN
			WITH M: Display.DisplayMsg DO
				IF (M.device = Display.printer) & (M.id = Display.contents) & (D.dsc # NIL) THEN (* print *)
				ELSE Documents.Handler(D, M)
				END
			END
		ELSE Documents.Handler(D, M)
		END
	END
END DocHandler;

PROCEDURE NewDoc*;
VAR D: Documents.Document;
BEGIN
	NEW(D);
	D.Load := Load; D.Store := Store; D.handle := DocHandler;
	D.W := BoardW + 2*Border; D.H := BoardH + 2*Border;
	Objects.NewObj := D
END NewDoc;

(* ------------------------ menu commands ------------------------ *)

PROCEDURE Start*;
VAR F: Frame; D: Documents.Document;
BEGIN
	D := Desktops.CurDoc(Gadgets.context);
	IF (D # NIL) & (D.dsc # NIL) & (D.dsc IS Frame) THEN
		F := D.dsc(Frame);
		NewGame(F); Gadgets.Update(F)
	END
END Start;

PROCEDURE Undo*;
VAR F: Frame; D: Documents.Document; U: UndoMsg;
BEGIN
	D := Desktops.CurDoc(Gadgets.context);
	IF (D # NIL) & (D.dsc # NIL) & (D.dsc IS Frame) THEN
		F := D.dsc(Frame);
		IF F.nofTiles < Tiles THEN Display.Broadcast(U) END
	END
END Undo;

BEGIN
	faceFnt := Fonts.This(FaceFontName); textFnt := Fonts.This(TextFontName);
	seed := ((Oberon.Time() MOD 32133)+1)*2;
	DoubleClick := Input.TimeUnit DIV 4;
	Texts.OpenWriter(W);
	Texts.WriteString(W, "Shanghai by P. Saladin "); Texts.WriteString(W, Version); Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf)
END Shanghai.
