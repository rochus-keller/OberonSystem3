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

MODULE Printer3;	(** portable *) (** jm 18.1.95 *)

(** Module Printer3 implements clipped printing through display masks. It has a twin module Display3 for displaying graphics.
*)

(* kr 14. 4. 93 printer patterns 
	kr Tue, 24-Aug-1993 Printer.String fixed 
	jm 29.3.94 - added Pict support
	- fixed line printing with empty mask
	20.4.94 - Fixed CenterString
	4.5.94 - improved metric handling
	8.12.94 - removed NewPattern, CopyPattern
*)

IMPORT Display3, Objects, Display,  Printer, Fonts, Pictures;

CONST
	replConst = 0;  replPattern = 2;  line = 3;
	

VAR 
	Pattern*: ARRAY 9 OF Display.Pattern;		(** Display patterns that correspond to the printer patterns. *)
	class: INTEGER;
	ex, ey, ex1, ey1, pattern: INTEGER;
	
	(* tmp vars for printing pictures *)
	tmpP: Pictures.Picture;
	tX, tY, tW, tH: INTEGER;

VAR
	lastfont: Fonts.Font; lastlib: Fonts.Font; (* for font lookup *)

(* ========= Brush related ========= *)

CONST BrushSize = 100; (* maximum width of the brush *)
	
TYPE
	Brush = RECORD
		brul, brur: ARRAY BrushSize OF INTEGER;
		bufl, bufr: ARRAY BrushSize OF INTEGER;
		bufh, brushr: INTEGER;
		x, y, mode: INTEGER;
		col: Display.Color;
		M: Display3.Mask;
		pat: Display.Pattern
	END;

VAR
	drawingPolygon: BOOLEAN;
	brush: Brush; (* global Brush *)

(* not portable
	PROCEDURE NewPattern*(pat: Display.Pattern): Display.Pattern;
		VAR x, y, b, l, r, t, w, h, i, W, H : INTEGER; s : SET; d : ARRAY 256, 4 OF SET;  p, s0 : LONGINT;  D, P : LONGINT; 
			k : SHORTINT;
			ptr : POINTER TO RECORD END;
	BEGIN
		y := 0;
		WHILE y < 256 DO
			x := 0; WHILE x < 4 DO d[y,x] := {}; INC(x);END;
			INC(y);
		END;
		
		(* zoom pattern *)
		D := Display.Unit; P := Unit;
		Display.GetDim(pat, w, h);
		p := SYSTEM.VAL(LONGINT,pat) + 2; 
		y := 0; 
		WHILE y < h DO x := 0;
			SYSTEM.GET(p,s);
			WHILE x < w  DO
				IF x IN s THEN 
					l := SHORT(x * D DIV P); r := SHORT((x +1) * D DIV P);
					b := SHORT(y * D DIV P); t := SHORT((y +1) * D DIV P);
					WHILE b < t DO i := l;
						WHILE i < r DO
							INCL(d[b, i DIV 32], i MOD 32);
							INC(i)
						END;
						INC(b);
					END
				END;
				INC(x);
			END;
			INC(p,LONG(w + 7) DIV 8 );
			INC(y);
		END;
		
		(* copy pattern *)
		H := SHORT(h * D DIV P);
		W := SHORT(w * D DIV P);
		SYSTEM.NEW(ptr, (W +7) DIV 8 * 8 * H + 8); 
		p := SYSTEM.VAL(LONGINT,ptr); 
		k := SHORT(W); SYSTEM.PUT(p,k); INC(p); 
		k := SHORT(H); SYSTEM.PUT(p,k); INC(p); 
		y := 0;
		WHILE y < H DO x := 0;
			WHILE x < W DO
				SYSTEM.PUT(p,d[y,x DIV 32]); 
				IF W - x >= 32 THEN r := 4 ELSE r := (W - x + 7) DIV 8 END;
				INC(x,32); INC(p,LONG(r));
			END;
			INC(y);
		END ;
		RETURN SYSTEM.VAL(LONGINT,ptr);
	END NewPattern;
*)

	PROCEDURE Min(x, y: INTEGER): INTEGER;
	BEGIN IF x < y THEN RETURN x ELSE RETURN y; END END Min;
	
	PROCEDURE Max(x, y: INTEGER): INTEGER;
	BEGIN IF x > y THEN RETURN x; ELSE RETURN y; END END Max;
	
	PROCEDURE ClipAgainst(VAR x, y, w, h: INTEGER; x1, y1, w1, h1: INTEGER);
	VAR r, t, r1, t1: INTEGER;
	BEGIN
		r := x + w - 1; r1 := x1 + w1 - 1; t := y + h - 1; t1 := y1 + h1 - 1;
		IF x < x1 THEN x := x1 END;
		IF y < y1 THEN y := y1 END;
		IF r > r1 THEN r := r1 END;
		IF t > t1 THEN t := t1 END;
		w := r - x + 1; h := t - y + 1
	END ClipAgainst;
	
	PROCEDURE IntersectLine(VAR x1, y1, x2, y2: INTEGER; X, Y, W, H: INTEGER): BOOLEAN;
		CONST left=0; right=1; bottom=2; top=3;
		VAR c1, c2: SET; R, T, x0, y0 : INTEGER; dx,dy : LONGINT;
			
		PROCEDURE Code(x, y: INTEGER): SET;
			VAR c: SET;
		BEGIN c := {};
			IF x<X THEN INCL(c, left) ELSIF x>R THEN INCL(c, right) END;
			IF y<Y THEN INCL(c, bottom) ELSIF y>T THEN INCL(c, top) END;
			RETURN c
		END Code;
		
		PROCEDURE Clip(VAR x, y : INTEGER; VAR c : SET);
		BEGIN
			IF left IN c THEN 
				y := SHORT(y0 + dy * (X-x0) DIV dx); x := X; 
			ELSIF right IN c THEN
				y := SHORT(y0 + dy* (R-x0) DIV dx); x := R; 
			ELSIF bottom IN c THEN
				x := SHORT(x0 + dx * (Y-y0) DIV dy); y := Y; 
			ELSIF top IN c THEN
				x := SHORT(x0 + dx * (T-y0) DIV  dy); y := T; 
			END;
			c := Code(x,y); 
		END Clip;
		
	BEGIN
		R := X + W ; T := Y + H;
		c1 := Code(x1, y1); c2 := Code(x2, y2);
		dy := y2-y1; dx := x2 - x1; 
		x0 := x1; y0 := y1;
		WHILE  (c1+c2 # {})  & (c1*c2={})  DO
			IF c1 = {} THEN  Clip(x2 ,y2, c2) ELSE Clip(x1, y1, c1) END;
		END;
		RETURN c1*c2={}
	END IntersectLine;

	PROCEDURE PPat(pat: Display.Pattern): INTEGER;
	VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE i < 9 DO
			IF pat = Pattern[i] THEN RETURN i END;
			INC(i);
		END;
		IF pat = Display.grey0 THEN  RETURN  4
		ELSIF pat = Display.grey1 THEN RETURN  4
		ELSIF pat = Display.grey2 THEN  RETURN 4
		ELSIF pat = Display.solid THEN RETURN 5	
		ELSE RETURN 5 
		END
	END PPat;
	
	PROCEDURE UseCol(col: Display.Color);
	VAR r, g, b: INTEGER;
	BEGIN
		Display.GetColor(col, r, g, b);
		Printer.UseColor(r, g, b)
	END UseCol;
	
	PROCEDURE *Enum(X, Y, W, H: INTEGER);
	VAR u, v, u1, v1: INTEGER;
	BEGIN
		CASE class OF
			   replConst: Printer.ReplConst(X, Y, W, H);
			| replPattern: Printer.ReplPattern(X, Y, W, H, pattern);	
			| line: u := ex; v := ey; u1 := ex1; v1 := ey1; 
				IF IntersectLine (u, v, u1, v1, X, Y, W, H) THEN Printer.Line(u, v, u1, v1); Printer.ReplConst(u1, v1, 1, 1) END
		END
	END Enum;
	
	(** Block fill X, Y, W, H using color col. *)
	PROCEDURE ReplConst*(M: Display3.Mask; col: Display.Color; X, Y, W, H, mode: INTEGER);
	BEGIN
		UseCol(col);
		IF M = NIL THEN Printer.ReplConst(X, Y, W, H)
		ELSE 
			ClipAgainst(X, Y, W, H, M.X, M.Y, M.W, M.H);
			IF (W > 0) & (H > 0) THEN class := replConst; Display3.EnumRect(M,X, Y, W, H, Enum) END;
		END;
		UseCol(Display3.black)
	END ReplConst;
	
	(** Print dot in color col at X, Y. *)
	PROCEDURE Dot*(M: Display3.Mask; col: Display.Color; X, Y, mode: INTEGER);
	BEGIN 
		UseCol(col);
		IF  M = NIL THEN Printer.ReplConst(X, Y,1,1)
		ELSIF Display3.Visible(M, X, Y, 1, 1) THEN Printer.ReplConst(X, Y, 1, 1)
		END;
		UseCol(Display3.black)
	END Dot;
	
	(** Replicate fill pattern pat in area X, Y, W, H, using color col. pX, pY is the pattern pin-point. *)
	PROCEDURE FillPattern*(M: Display3.Mask; col: Display.Color; pat: Display.Pattern; pX, pY, X, Y, W, H, mode: INTEGER);
	BEGIN
		UseCol(col);
		pattern := PPat(pat); 
		IF M = NIL THEN
			IF pat = Display.solid THEN Printer.ReplConst(X, Y, W, H)
			ELSE Printer.ReplPattern(X, Y, W, H, pattern)
			END;
		ELSE
			ClipAgainst(X, Y, W, H, M.X, M.Y, M.W, M.H);
			IF (W > 0) & (H > 0) THEN
				IF pat = Display.solid THEN class := replConst
				ELSE class := replPattern
				END;
				Display3.EnumRect(M,X, Y, W, H, Enum)
			END
		END;
		UseCol(Display3.black)
	END FillPattern;

	(** Print rectangle outline X, Y, W, H of width and in pattern pat. *)
	PROCEDURE Rect*(M: Display3.Mask; col: Display.Color; pat: Display.Pattern; X, Y, W, H, width, mode: INTEGER);
	BEGIN
		width := Min(width, Min(H DIV 2, W DIV 2));
		ReplConst(M, col, X, Y, width, H, mode);
		ReplConst(M, col, X + W - width, Y, width, H, mode);
		ReplConst(M, col, X + width, Y, W - 2 * width, width, mode);
		ReplConst(M, col,  X + width, Y + H - width, W - 2 * width, width, mode)
	END Rect;
	
(** Print a rectangle outline X, Y, W, H  of width width in 3D effect using top shadow  topcol and bottom shadow botcol. *)
	PROCEDURE Rect3D*(M: Display3.Mask; topcol, botcol: Display.Color; X, Y, W, H, width, mode: INTEGER);
	BEGIN
		width := Min(width, Min(H DIV 2, W DIV 2));
		WHILE width > 0 DO
			ReplConst(M, botcol, X, Y, W, 1,mode);
			ReplConst(M, topcol, X, Y + H - 1, W, 1, mode);
			ReplConst(M, topcol, X, Y, 1, H, mode);
			ReplConst(M, botcol, X + W - 1, Y, 1, H, mode);
			DEC(width); INC(X); INC(Y); DEC(W, 2); DEC(H, 2)
		END
	END Rect3D;
	
(** Print a filled rectangle X, Y, W, H  of width width in 3D effect using top shadow  topcol and bottom shadow botcol. The "inside" color is incol. *)
	PROCEDURE FilledRect3D*(M: Display3.Mask; topcol, botcol, incol: Display.Color; X, Y, W, H, width, mode: INTEGER);
	BEGIN
		width := Min(width, Min(H DIV 2, W DIV 2));
		WHILE width > 0 DO
			ReplConst(M, botcol, X, Y, W, 1,mode);
			ReplConst(M, topcol, X, Y + H - 1, W, 1, mode);
			ReplConst(M, topcol, X, Y, 1, H, mode);
			ReplConst(M, botcol, X + W - 1, Y, 1, H, mode);
			DEC(width); INC(X); INC(Y); DEC(W, 2); DEC(H, 2);
		END;
		ReplConst(M, incol, X , Y, W, H, mode);
	END FilledRect3D;
	
(* BRUSHES *)

PROCEDURE BrushJump(VAR b: Brush; x, y: INTEGER);
VAR i: INTEGER;
BEGIN
	IF (b.x # x) OR (b.y # y) THEN
		b.x := x; b.y := y;
		FOR i := 0 TO b.bufh - 1 DO b.bufl[i] := b.brul[i] + b.x; b.bufr[i] := b.brur[i] + b.x END
	END
END BrushJump;
		
PROCEDURE BrushWalk(VAR b: Brush; x, y: INTEGER);
VAR i, dx, dy, t: INTEGER;
BEGIN
	dx := x - b.x; dy := y - b.y; t := b.bufh - 1;
	IF dy = 0 THEN (* horizontal move *)
		IF dx < 0 THEN
			FOR i := 0 TO t DO b.bufl[i] := Min(b.bufl[i], b.brul[i] + x) END
		ELSIF dx > 0 THEN
			FOR i := 0 TO t DO b.bufr[i] := Max(b.bufr[i], b.brur[i] + x) END
		END
	ELSIF dy > 0 THEN (* up *)
		FillPattern(b.M, b.col, b.pat, 0, 0, b.bufl[0], b.y - b.brushr, b.bufr[0] - b.bufl[0] + 1, 1, b.mode);
		FOR i := 0 TO b.bufh - 2 DO
			b.bufl[i] := Min(b.bufl[i+1], b.brul[i] + x); b.bufr[i] := Max(b.bufr[i+1], b.brur[i] + x);
		END;
		b.bufl[t] := b.brul[t] + x; b.bufr[t] := b.brur[t] + x
		
	ELSE (* dy < 0 *) (* down *)
		FillPattern(b.M, b.col, b.pat, 0, 0,
			b.bufl[t], b.y - b.brushr + b.bufh-1, b.bufr[t] - b.bufl[t] + 1, 1, b.mode);
		FOR i := b.bufh - 1 TO 1 BY -1 DO
			b.bufl[i] := Min(b.bufl[i-1], b.brul[i] + x); b.bufr[i] := Max(b.bufr[i-1], b.brur[i] + x);
		END;
		b.bufl[0] := b.brul[0] + x; b.bufr[0] := b.brur[0] + x;
	END;
	b.x := x; b.y := y
END BrushWalk;

PROCEDURE BrushFlush(VAR b: Brush);
VAR i: INTEGER;
BEGIN
	FOR i := 0 TO b.bufh - 1 DO
		FillPattern(b.M, b.col, b.pat, 0, 0,
			b.bufl[i], b.y + i - b.brushr, b.bufr[i] - b.bufl[i] + 1, 1, b.mode);
	END
END BrushFlush;

PROCEDURE InitBrush(VAR b: Brush; M: Display3.Mask; pat: Display.Pattern; col: Display.Color; w, mode: INTEGER);
VAR r, x, y, d, dx, dy: INTEGER;

	PROCEDURE Set(x, y: INTEGER);
	BEGIN
		b.brul[y + r] := -x+1; b.brur[y + r] := x; b.brul[-y + r] := -x+1; b.brur[-y + r] := x;
		IF y + r > b.bufh THEN b.bufh := y + r END;
	END Set;

BEGIN b.bufh := 0;
	b.M := M; b.col := col; b.mode := mode; b.pat := pat;
	IF w >= BrushSize THEN w := BrushSize - 1 END;
	
	b.x := MIN(INTEGER); b.y := MIN(INTEGER);
	r := w DIV 2; (* radius *)
	IF r < 0 THEN r := 1 END;
	x := r; y := 0; d := 2 * r; dx := 4 * r; dy := 0;
	Set(x, y);
    WHILE y # r DO
		WHILE d <= 1 DO DEC(x); DEC(dx, 4); INC(d, dx) END;
		INC(y); Set(x, y); INC(dy, 4); DEC(d, dy);
	END;
	b.brushr := r; INC(b.bufh)
END InitBrush;

(* --------------------- Scan line based primitives --------------------- *)

(** Print a line of width width between X, Y and X1, Y1 in color col using pattern pat. Hair-lines (of width = 1) cannot be patterned. *)
PROCEDURE Line*(M: Display3.Mask; col: Display.Color; pat: Display.Pattern; X, Y, X1, Y1, width, mode: INTEGER);
VAR x, y, dx, dy, inx, iny, d, dy2, dx2: INTEGER;
BEGIN
	IF width > 1 THEN
		x := X; y := Y; dx := X1 - X; dy := Y1 - Y;
		IF drawingPolygon THEN
		ELSE InitBrush(brush, M, pat, col, width, mode); BrushJump(brush, x, y)
		END;
		IF ABS(dy) > ABS(dx) THEN
			d := -ABS(dx); dy2 := 2 * ABS(dy); dx2 := 2 * ABS(dx);
			IF dx < 0 THEN inx := -1; ELSE inx := 1; END;
			IF dy < 0 THEN iny := -1; ELSE iny := 1; END;
			WHILE y # Y1 DO
				INC(y, iny);
				INC(d, dx2);
				IF d > 0 THEN INC(x, inx); DEC(d, dy2); END;
				BrushWalk(brush, x, y);
			END;
		ELSE
			d := -ABS(dx); dy2 := 2 * ABS(dy); dx2 := 2 * ABS(dx);
			IF dx < 0 THEN inx := -1; ELSE inx := 1; END;
			IF dy < 0 THEN iny := -1; ELSE iny := 1; END;
			WHILE x # X1 DO
				INC(x, inx);
				INC(d, dy2);
				IF d > 0 THEN INC(y, iny); DEC(d, dx2); END;
				BrushWalk(brush, x, y);
			END;
		END;
		IF ~drawingPolygon THEN BrushFlush(brush) END;
	ELSE (* width = 1 *)
		IF (X = X1) THEN ReplConst(M, col, X, Min(Y, Y1), 1, ABS(Y - Y1), mode)
		ELSIF Y = Y1 THEN ReplConst(M, col, Min(X,X1),Y, ABS(X - X1), 1, mode);
		ELSIF M # NIL THEN
			UseCol(col);
			ex := X; ey := Y; ex1 := X1; ey1 := Y1; class := line;
			Display3.EnumRect(M, Min(X, X1), Min(Y, Y1), ABS(X - X1),  ABS(Y - Y1), Enum);
			UseCol(Display3.black)
		ELSE
			UseCol(col);
			Printer.Line(X, Y, X1, Y1); Printer.ReplConst(X1, Y1,1,1);
			UseCol(Display3.black)
		END;
	END
END Line;

PROCEDURE FilledPoly(M: Display3.Mask; col: Display.Color; pat: Display.Pattern; VAR X, Y: ARRAY OF INTEGER; n, mode: INTEGER);
	TYPE
		Run = POINTER TO RunDesc0;
		RunDesc0 = RECORD next: Run; x: INTEGER END;
	VAR
		scan: ARRAY 2000 OF Run; free, s: Run;
		i, miny, maxy, x0, x1: INTEGER;
		
	PROCEDURE New(VAR s: Run);
	BEGIN IF free = NIL THEN NEW(s) ELSE s := free; free := free.next; s.next := NIL END
	END New;
	
	PROCEDURE Free(VAR s: Run);
	VAR s0: Run;
	BEGIN
		IF s # NIL THEN
			s0 := s; WHILE s0.next # NIL DO s0 := s0.next END;
			s0.next := free; free := s; s := NIL
		END
	END Free;

	PROCEDURE Insert(VAR s: Run; x: INTEGER);
	VAR t, t0: Run;
	BEGIN
		IF s = NIL THEN New(s); s.x := x
		ELSE
			New(t); t.x := x;
			IF x < s.x THEN t.next := s; s := t
			ELSE t0 := s;
				WHILE (t0.next # NIL) & (t0.next.x < x) DO t0 := t0.next END;
				IF t0.next = NIL THEN t0.next := t
				ELSE t.next := t0.next; t0.next := t
				END
			END
		END
	END Insert;
		
	PROCEDURE line(x1, y1, x2, y2: INTEGER); (* standard bresenham *)
	VAR x, y, d, dx, dy, incx, incy: INTEGER;
	BEGIN
		(* Seg(x1,y1); *)
		x := x1; y := y1; dx := (x2 - x1) * 2; dy := (y2 - y1) * 2;
		incx := 0;
		IF dx < 0 THEN incx := -1; dx := -dx;
		ELSIF dx  >0 THEN incx := 1
		END;
		incy := 0;
		IF dy < 0 THEN incy := -1; dy := -dy ELSIF dy > 0 THEN incy := 1 END;
		d := incx * (x1 - x2);
		WHILE y # y2 DO
			INC(y, incy); INC(d, dx);
			WHILE d > 0 DO INC(x, incx); DEC(d, dy) END;
			IF incy > 0 THEN Insert(scan[y], x) ELSE Insert(scan[y+1], x) END
		END;
	END line;

BEGIN free := NIL;
	miny := MAX(INTEGER); maxy := MIN(INTEGER);
	i := 0; WHILE i < n DO IF Y[i] < miny THEN miny := Y[i] END; IF Y[i] > maxy THEN maxy := Y[i]; END; INC(i) END;
	i := 0; WHILE i <= maxy - miny DO scan[i] := NIL; INC(i) END;
	i := 1;
	WHILE i < n DO
		line(X[i - 1], Y[i - 1] - miny, X[i], Y[i] - miny); INC(i)
	END;
	line(X[n - 1], Y[n - 1] - miny, X[0], Y[0] - miny);
	
	i := 0;
	WHILE i <= maxy - miny DO
		s := scan[i];
		WHILE s # NIL DO
			x0 := s.x; s := s.next;
			IF s = NIL THEN x1 := x0 ELSE x1 := s.x; s := s.next END;
			FillPattern(M, col, pat, 0, 0, x0, i + miny, x1 - x0 + 1, 1, mode)
		END;
		Free(scan[i]);
		INC(i)
	END
END FilledPoly;

(** Print a polygon of n vertices in color col and pattern pat. The vertices are passed in the arrays X and Y. Style can be {Display3.filled}. *)
PROCEDURE Poly*(M: Display3.Mask; col: Display.Color; pat: Display.Pattern; VAR X, Y: ARRAY OF INTEGER; n, width: INTEGER; style: SET; mode: INTEGER);
VAR i: INTEGER;
BEGIN
	IF Display3.filled IN style THEN FilledPoly(M, col, pat, X, Y, n, mode)
	ELSE
		drawingPolygon := TRUE;
		IF width > 1 THEN InitBrush(brush, M, pat, col, width, mode); BrushJump(brush, X[0], Y[0]) END;
		i := 0;
		WHILE i < n - 1 DO 
			Line(M, col, pat, X[i], Y[i], X[i+1], Y[i+1], width, mode); INC(i) 
		END;
		drawingPolygon := FALSE;
		IF width > 1 THEN BrushFlush(brush) END
	END
END Poly;

(** Print an ellipse of horizontal radius a and vertical radius b at position X, Y. Implementation restriction: Ellipses cannot be filled or drawn with a thick brush. *)	
PROCEDURE Ellipse*(M: Display3.Mask; col: Display.Color; pat: Display.Pattern; X, Y, a, b, width: INTEGER; style: SET; mode: INTEGER);
VAR x1, y1: INTEGER; d, dx, dy, x2, y2, a1, a2, a8, b1, b2, b8: LONGINT;
		
	PROCEDURE Dot4(x1, x2, y1, y2: INTEGER; col: Display.Color; mode: INTEGER);
	BEGIN
		IF pat = Display.solid THEN
			Dot(M, col, x1, y1,mode); Dot(M, col, x1, y2, mode);
			Dot(M, col, x2, y1,mode); Dot(M, col, x2, y2, mode)
		ELSE
			FillPattern(M, col, pat, 0, 0, x1, y1, 1, 1, mode); FillPattern(M, col, pat, 0, 0, x1, y2, 1, 1, mode);
			FillPattern(M, col, pat, 0, 0, x2, y1, 1, 1, mode); FillPattern(M, col, pat, 0, 0, x2, y2, 1, 1, mode)
		END
	END Dot4;
	
BEGIN
	a1 := a; a2 := a1*a1; a8 := 8*a2; b1 := b; b2 := b1*b1; b8 := 8*b2;
	x1 := a; y1 := 0; x2 := a1*b2; y2 := 0; dx := b8*(a1-1); dy := 4*a2; d := b2*(1- 4*a1);
	WHILE y2 < x2 DO
		Dot4(X-x1-1, X+x1, Y-y1-1, Y+y1, col, mode);
		INC(d, dy); INC(dy, a8); INC(y1); INC(y2, a2);
		IF d >= 0 THEN DEC(d, dx); DEC(dx, b8); DEC(x1); DEC(x2, b2) END
	END;
	INC(d, 4*(x2+y2)-b2+a2);
	WHILE x1 >= 0 DO
		Dot4(X-x1-1, X+x1, Y-y1-1, Y+y1, col, mode);
		DEC(d, dx); DEC(dx, b8); DEC(x1);
		IF d < 0 THEN INC(d, dy); INC(dy, a8); INC(y1) END
	END
END Ellipse;
	
(** Print a circle of radius r and width width using pattern pat and color col at X, Y. Style can be {Display3.filled}. *)
PROCEDURE Circle*(M: Display3.Mask; col: Display.Color; pat: Display.Pattern; X, Y, r, width: INTEGER; style: SET; mode: INTEGER);
VAR x, y, dx, dy, d, e: INTEGER;
BEGIN
	IF Display3.filled IN style THEN
		x := r; y := 0; e := 0; dx := 2; dy := 2;
		WHILE y <=x DO
			FillPattern(M, col, pat, X, Y, X - x, Y + y, 2 * x, 1, mode);
			FillPattern(M, col, pat, X, Y, X - x, Y - y, 2 * x, 1, mode);
			INC(y);
			INC(e, y * dy - 1);
			IF e > x THEN
				DEC(x); DEC(e, x * dx + 1);
				FillPattern(M, col, pat, X, Y, X - y, Y + x, 2* y, 1, mode);
				FillPattern(M, col, pat, X, Y, X - y, Y - x, 2 * y, 1, mode)
			END
		END
	ELSIF width > 1 THEN
		x :=  X + r; y := Y;
		InitBrush(brush, M, pat, col, width, mode); BrushJump(brush, x, y);
		
		d := 2* r; dx := 4* r; dy := 0;
		WHILE y # Y + r DO
			WHILE d <= 1 DO DEC(x); BrushWalk(brush, x, y); DEC(dx,4); INC(d,dx) END;
			INC(y); BrushWalk(brush, x, y); INC(dy,4); DEC(d,dy);
		END;
		WHILE x # X DO DEC(x); BrushWalk(brush, x, y); DEC(dx,4); INC(d,dx) END;
		d := -d;
		WHILE x # X - r DO
			WHILE d <= 1 DO DEC(y); BrushWalk(brush,x,y); DEC(dy,4); INC(d,dy) END;
			DEC(x); BrushWalk(brush,x,y); INC(dx,4); DEC(d,dx);
		END;
		WHILE y # Y DO DEC(y); BrushWalk(brush,x,y); DEC(dy,4); INC(d,dy) END;
		d := -d;
		WHILE y # Y - r DO
			WHILE d <= 1 DO INC(x); BrushWalk(brush,x,y); DEC(dx,4); INC(d,dx) END;
			DEC(y); BrushWalk(brush,x,y); INC(dy,4); DEC(d,dy);
		END;
		WHILE x # X DO INC(x); BrushWalk(brush,x,y); DEC(dx,4); INC(d,dx) END;
		d := -d;
		WHILE x # X + r DO
			WHILE d <= 1 DO INC(y); BrushWalk(brush,x,y); DEC(dy,4); INC(d,dy) END;
			INC(x); BrushWalk(brush,x,y); INC(dx,4); DEC(d,dx);
		END;
		WHILE y # Y DO INC(y); BrushWalk(brush,x,y); DEC(dy,4); INC(d,dy) END;
		BrushFlush(brush)
	ELSIF pat = Display.solid THEN (* single pixel circle *)
		IF Display3.Visible(M, X-r, Y-r, 2 * r, 2 * r) THEN
			UseCol(col); Printer.Circle(X, Y, r); UseCol(Display3.black)
		ELSE
		 	Ellipse(M, col, pat, X, Y, r, r, width, {}, mode)
		END
	ELSE Ellipse(M, col, pat, X, Y, r, r, width, {}, mode)
	END
END Circle;
	
(* lookup the size of a character on the printer/does not use a font cache *)
PROCEDURE Lookup(L: Fonts.Font; ch: CHAR; VAR minY, maxY, dx, y, h: INTEGER);
VAR obj: Objects.Object; metric: Fonts.Font;
	
	PROCEDURE Dev(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(LONG(x) * Display.Unit DIV Printer.Unit)
	END Dev;
	
BEGIN
	IF L = lastfont THEN metric := lastlib
	ELSE
		metric := Printer.GetMetric(L);
		lastlib := metric; lastfont := L
	END;
	IF metric # NIL THEN
		metric.GetObj(metric, ORD(ch), obj);
		WITH obj: Fonts.Char DO
			minY := metric.minY; maxY := metric.maxY; dx := obj.dx; y := obj.y; h := obj.h
		END
	ELSE (* scale display font *)
		L.GetObj(L, ORD(ch), obj);
		WITH obj: Fonts.Char DO
			minY := Dev(L.minY); maxY := Dev(L.maxY); dx := Dev(obj.dx); y := Dev(obj.y); h := Dev(obj.h)
		END
	END;
END Lookup;

(** Returns the size of a string on the printer. Width is w, height is h, and the descender offset is dsr. *)
PROCEDURE StringSize*(s: ARRAY OF CHAR; fnt: Fonts.Font; VAR w, h, dsr: INTEGER);
VAR p, dx, d: INTEGER;
BEGIN
	w := 0;
	p := 0;
	WHILE s[p] # 0X DO
		Lookup(fnt, s[p], d, d, dx, d, d);  INC(w, dx);
		INC(p)
	END;
	IF lastlib = NIL THEN
		dsr := ABS(SHORT(fnt.minY*Display.Unit DIV Printer.Unit));
		h := SHORT(fnt.height*Display.Unit DIV Printer.Unit);
	ELSE dsr := ABS(lastlib.minY); h := lastlib.height
	END
END StringSize;

PROCEDURE StringSize0(fnt: Fonts.Font; s: ARRAY OF CHAR; VAR x, y, w, h: INTEGER; VAR dx: ARRAY OF INTEGER);
VAR i, minY, maxY, cdx, d: INTEGER; 
BEGIN
	w := 0; i := 0; x := 0;  
	WHILE s[i] # 0X DO
		Lookup(fnt, s[i], minY, maxY, cdx, d, d);
		IF i < LEN(dx) THEN dx[i] := cdx END;
		INC(w, cdx);
		INC(i);
	END;
	IF lastlib = NIL THEN
		y := SHORT(fnt.minY*Display.Unit DIV Printer.Unit); h := SHORT(fnt.height*Display.Unit DIV Printer.Unit);
	ELSE
		y := lastlib.minY; h := lastlib.maxY + ABS(lastlib.minY)
	END;
END StringSize0;
		
(** Print string s using font fnt in color col at X, Y. *)
	PROCEDURE String*(M: Display3.Mask; col: Display.Color; X, Y: INTEGER; fnt: Fonts.Font; s: ARRAY OF CHAR; mode: INTEGER);
	VAR W, H, x, y, i: INTEGER; dX: ARRAY 256 OF  INTEGER; t: ARRAY 2 OF CHAR;
	BEGIN
		StringSize0(fnt, s, x, y, W, H, dX);

		(* debug 
		Printer.ReplConst(X + x, Y + y, W, 1); Printer.ReplConst(X + x, Y + y, 1, H);
		*)
		
		UseCol(col);

		IF Display3.Visible(M, X + x, Y + y, W, H) THEN Printer.String(X, Y, s, fnt)
		ELSE 
			i := 0; t[1] := 0X;
			WHILE (s[i] # 0X) & (i < LEN(dX)) DO
				t[0] := s[i]; 
				IF Display3.Visible(M, X + x, Y + y, dX[i], H) THEN
					Printer.String(X, Y, t, fnt); 
				END;
				INC(X, dX[i]);
				INC(i);
			END
		END;
		UseCol(Display3.black)
	END String;

(** Print string s centered in area X, Y, W, H using color col and font fnt. Line-breaks will be inserted if the string is too long. *)
PROCEDURE CenterString*(M: Display3.Mask; col: Display.Color; X, Y, W, H: INTEGER; fnt: Fonts.Font; s: ARRAY OF CHAR; mode: INTEGER);
VAR len, p, h, lspc, i, y: INTEGER; s0: ARRAY 48 OF CHAR; cdx, d, fheight, fminy: INTEGER;
BEGIN
	len := 0; p := 0;
	WHILE (s[p] # 0X) DO
		Lookup(fnt, s[p], d, d, cdx, d, d);
		INC(p); INC(len, cdx);
	END;
	
	IF lastlib = NIL THEN
		fminy := SHORT(fnt.minY*Display.Unit DIV Printer.Unit); fheight := SHORT(fnt.height*Display.Unit DIV Printer.Unit);
	ELSE
		fminy := lastlib.minY; fheight := lastlib.height
	END;
	
	IF len < W - 4 THEN (* normal print *)
		String(M, col, (W - len) DIV 2 + X, Y + H DIV 2 - fheight DIV 2 + ABS(fminy), fnt, s, mode);
	ELSE (* formatted print *)
		p := 0; len := 0; h := 0; lspc := -1; 
		WHILE s[p] # 0X DO
			Lookup(fnt, s[p], d, d, cdx, d, d);
			IF len + cdx >= W THEN (* too long next line *)
				IF s[p] = " " THEN lspc := -1; s[p] := 1X; INC(h, fheight); len := 0;
				ELSIF lspc > 0 THEN (* space exists *) p := lspc; lspc := -1; s[p] := 1X; INC(h, fheight); len := 0;
				ELSE INC(len, cdx)
				END;
			ELSE
				INC(len, cdx);
				IF s[p] = " " THEN lspc := p END;
			END;
			INC(p);
		END; INC(h, fheight);
		
		(* print *)
		p := 0; i := 0; len := 0; y := Y + H DIV 2 + h DIV 2 + ABS(fminy); 
		WHILE s[p] # 0X DO
			Lookup(fnt, s[p], d, d, cdx, d, d);
			IF s[p] = 1X THEN (* break *)
				s0[i] := 0X; i := 0; DEC(y, fheight);
				String(M, col, X + W DIV 2 - len DIV 2, y, fnt, s0, mode);
				len := 0;
			ELSE
				INC(len, cdx);
				s0[i] := s[p]; INC(i);
			END;
			INC(p);
		END; DEC(y, fheight);
		IF i > 0 THEN s0[i] := 0X;
			String(M, col, X + W DIV 2 - len DIV 2, y, fnt, s0, mode);
		END;
	END;
END CenterString;

	PROCEDURE Print(px, py, pw, ph: INTEGER; (* picture *) X, Y, W, H: INTEGER(* printer *);  P: Pictures.Picture);
	BEGIN
		Printer.Picture(P, px, py, pw, ph, X, Y, W, H, Display.replace);
	END Print;
	
PROCEDURE PrintEnum(X, Y, W, H: INTEGER);
VAR px, py, pw, ph: INTEGER;
BEGIN
	px := X - tX; py := Y - tY; pw := W; ph := H; (* in printer coordinates *)
	
	(* map printer pixels to picture pixels *)
	px := SHORT(LONG(px) * tmpP.width DIV tW); py := SHORT(LONG(py) * tmpP.height DIV tH);
	pw := SHORT(LONG(pw) * tmpP.width DIV tW); ph :=  SHORT(LONG(ph) * tmpP.height DIV tH);
	
	(* expand/reduce the px, py, pw, ph of the picture to printer coords X, Y, W, H *)
	Print(px, py, pw, ph, X, Y, W, H, tmpP);
END PrintEnum;

(** Picture is stretched/reduce to fit at X, Y, W, H on the printer. *)
PROCEDURE Pict*(M: Display3.Mask; P: Pictures.Picture; X, Y, W, H, mode: INTEGER); (* printer coordinates *)
VAR x, y, w, h: INTEGER;
BEGIN
	x := X; y := Y; w := W; h := H;
	ClipAgainst(x, y, w, h, M.X, M.Y, M.W, M.H);
	tmpP := P;
	tX := X; tY := Y; tW := W; tH := H;
	Display3.EnumRect(M, x, y, w, h, PrintEnum);
END Pict;

(** Replicate picture P. px, py is the picture origin, X, Y, W, H is printer coordinates of the area to be filled. *)
PROCEDURE ReplPict*(M: Display3.Mask; P: Pictures.Picture; px, py, X, Y, W, H, mode: INTEGER);
VAR x, y, w, h, pw, ph, w0, x0: INTEGER;
	a, b, c, d: INTEGER;

	PROCEDURE PP(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END PP;
	
BEGIN
	a := M.X; b := M.Y; c := M.W; d := M.H;
	pw := PP(P.width); ph := PP(P.height); w0 := W; x0 := X;
	WHILE H > 0 DO
		y := (Y - py) MOD ph; h := Min(H, ph - y);
		W := w0; X := x0;
		WHILE W > 0 DO
			x := (X - px) MOD pw; w := Min(W, pw - x);
			M.X := X; M.Y := Y; M.W := w; M.H := h;
			Pict(M, P, X - x, Y - y, pw, ph, mode);
			INC(X, w); DEC(W, w); 
		END;
		INC(Y, h); DEC(H, h);
	END;
	M.X := a; M.Y := b; M.W := c; M.H := d;
END ReplPict;

PROCEDURE InitPat;
	VAR patS : ARRAY 9,8 OF SET; i : INTEGER;
	
BEGIN
	patS[0,0] := {0..31};	patS[0,1] := {0..31};	
	patS[0,2] := {0..31};	patS[0,3] := {0..31};
	FOR i := 0 TO 3 DO patS[0, i+4] := patS[0, i] END;
	
	patS[1,0] := {};	patS[1,1] := {};	
	patS[1,2] := {};	patS[1,3] := {0,4,8,12,16,20,24,28};
	FOR i := 0 TO 3 DO patS[1, i+4] := patS[1, i] END;

	patS[2,0] := {0,4,8,12,16,20,24,28};	patS[2,1] := {};	
	patS[2,2] := {2,6,10,14,18,22,26,30};	patS[2,3] := {};
	FOR i := 0 TO 3 DO patS[2, i+4] := patS[2, i] END;

	patS[3,0] := {};	patS[3,1] := {0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30};	patS[3,2] := {};
	patS[3,3] := {0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30};
	FOR i := 0 TO 3 DO patS[3, i+4] := patS[3, i] END;

	patS[4,0] := {0,4,8,12,16,20,24,28};	patS[4,1] := {2,6,10,14,18,22,26,30};
	patS[4,2] := {0,4,8,12,16,20,24,28};	patS[4,3] := {2,6,10,14,18,22,26,30};
	FOR i := 0 TO 3 DO patS[4, i+4] := patS[4, i] END;

	patS[5,0] := {0..31};	patS[5,1] := {0..31};	
	patS[5,2] := {0..31};	patS[5,3] := {0..31};
	FOR i := 0 TO 3 DO patS[5, i+4] := patS[5, i] END;

	patS[6,0] := {0,4,8,12,16,20,24,28};	patS[6,1] := {1,5,9,13,17,21,25,29};
	patS[6,2] := {2,6,10,14,18,22,26,30};	patS[6,3] := {3,7,11,15,19,23,27,31};
	FOR i := 0 TO 3 DO patS[6, i+4] := patS[6, i] END;
	
	patS[7,0] := {3,7,11,15,19,23,27,31};	patS[7,1] := {2,6,10,14,18,22,26,30};
	patS[7,2] := {1,5,9,13,17,21,25,29};	patS[7,3] := {0,4,8,12,16,20,24,28};
	FOR i := 0 TO 3 DO patS[7, i+4] := patS[7, i] END;
	
	patS[8,0] := {0,4,8,12,16,20,24,28};	patS[8,1] := {0,4,8,12,16,20,24,28};
	patS[8,2] := {0,4,8,12,16,20,24,28};	patS[8,3] := {0,4,8,12,16,20,24,28};
	FOR i := 0 TO 3 DO patS[8, i+4] := patS[8, i] END;
	
	i := 0; WHILE i < 9 DO Pattern[i] := Display.NewPattern(32,8,patS[i]); INC(i) END;
END InitPat;

BEGIN drawingPolygon := FALSE;
	InitPat
END Printer3.

(** Remarks:

1. Printer3 uses the same mask descriptors as Display3 but expects all coordinates to be specified in printer coordinates (often 300dpi). It has a similar interface as Display3, although some minor differences can be found. Although the formal arguments are approximately the same as those of Display3, some of them are ignored, notably "mode". Due to the very limited interface of the underlying Printer module, strings cannot be clipped correctly. This means that whole characters are clipped at a time. As Oberon has no true color model, the col parameters are indexes into the momentary displayed palette. This means that by changing the display palette, your documents will print in different colors. No special color mappings are attempted for monochrome printers. The latter has to be done by the client.

2. Note that typical Oberon fonts differ non-linearly in size on the display and printer. You cannot multiply a display string size by a constant factor to obtain an approximation of the printer string size.

3. Patterns passed to the print procedures are display patterns (for example Display.solid, Display.grey1, Pattern[x] etc). The Pattern array contains display patterns corresponding to the pattern numbers expected by the Printer module. That is, Pattern[2] is the display pattern that corresponds to pattern number 2 on the printer.

*)