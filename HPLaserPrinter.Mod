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

MODULE HPLaserPrinter;	(** non-portable *)  (* L. Truszek, pjm *)

IMPORT SYSTEM, Files, Display, Fonts, Texts, Oberon, Printer, Pictures, Out;

CONST
	(* The maximal logical HP Laserjet page size for A4 format *)

	HPPageWidth = 2480;  HPPageHeight = 3508;
	HPX = 71;  HPY = 148;	(* 6mm & 12.5mm built-in margins *)
	maxfonts = 20;
	BaseFont = 100;	(* starting number for HP font id-s *)
	N = 40;
	BlockSize = 512;

(* spacing *)
	PROPOR = 1; (* proportional *)
	FIXEDSP = 0; (* fixed *)

(* orientation *)
	PORTRAIT = 0; (* portrait	*)
	LANDSCP = 1; (* landscape *)

	ESC = 01BX;
	FF = 0CX;
	
(* compatibility *)
	PW = 2336; PH = 3281; PL = PW DIV 32;
	CH = PH DIV 4;

	ColSubDiv = 6;	(* subdivision of color range in black and white printing *)
	
TYPE
	Pattern = ARRAY 16 OF SET;
	Fontx = Fonts.Font; 
	
	RealVector = ARRAY N OF REAL;
	Poly = RECORD a, b, c, d, t: REAL END ;
	PolyVector = ARRAY N OF Poly;

	Set = POINTER TO ARRAY OF SET;
	WriteProc = PROCEDURE (port: INTEGER; ch: CHAR);

	Font = RECORD 
		name: ARRAY 32 OF CHAR;
		pitch: SHORTINT;
		chartab: Set;	(* ARRAY 256 OF BIT *)
	END;
	
	HPFontDesc = RECORD	(* the HP font descriptor *)
		size: INTEGER;
		res0: SHORTINT;
		type: SHORTINT;
		res1, 
		base,
		cellwidth,
		cellheight: INTEGER;
		orient: SHORTINT;
		space: SHORTINT;
		symbol,
		pitch,
		height,
		xheight: INTEGER;
		widthtype,style*,
		strokeweight,typeface, 
		res2, serifstyle: SHORTINT;
		res3: INTEGER;
		underdist,underheight: SHORTINT;
		textheight, 
		textwidth, 
		res4,res5: INTEGER;
		pitchext,heightext :SHORTINT;
		res6,res7,res8 :INTEGER;
		name: ARRAY 16 OF CHAR;
	END;
	
	HPCharDesc= RECORD	(* the HP Character descriptor *)
		fix1,fix2,
		orient,
		left,
		top,
		width,
		height,
		delta: INTEGER;
	END;
	
	RunP = POINTER TO RunDscP;
	RunDscP = RECORD
		next, prev: RunP;
		x, y, w, h, col: INTEGER
	END;

VAR
	r, u: Files.Rider;
	Unit: LONGINT;
	Depth, Width, Height: INTEGER;
	CurFont, PrevFont: SHORTINT;
	M: POINTER TO ARRAY HPPageHeight OF Set;
	maxX, maxY, minX, minY: INTEGER;
	nofonts: INTEGER;
	font: POINTER TO ARRAY maxfonts OF Font;
	freeP: RunP;

(* Font table procedures *)

PROCEDURE LookupFont(name: ARRAY OF CHAR;  VAR i: SHORTINT;  VAR inserted: BOOLEAN);
BEGIN 
	inserted := FALSE;
	i := 0;  WHILE (i < nofonts) & (font[i].name # name) DO INC(i) END;
	IF i = nofonts THEN
		IF nofonts < maxfonts THEN
			COPY(name, font[i].name);
			INC(nofonts);
			inserted := TRUE
		ELSE
			i := maxfonts	(* table full *)
		END
	END
END LookupFont;

(* Set procedures *)

PROCEDURE New(VAR s: Set;  len: LONGINT);
VAR i, size: LONGINT;
BEGIN
	size := (len + 31) DIV 32;	(* size in SET elements *)
	NEW(s, size); (* size in bytes *)
	i:= 0;  WHILE i < size DO s[i] := {};  INC(i) END
END New;

PROCEDURE Incl(s: Set;  e1: LONGINT);
BEGIN
	INCL(s[e1 DIV 32], e1 MOD 32);
END Incl;

PROCEDURE In(s: Set;  e1: LONGINT): BOOLEAN;
BEGIN
	RETURN e1 MOD 32 IN s[e1 DIV 32]
END In;

(* Swap bytes in INTEGER *)

PROCEDURE SB(i: INTEGER): INTEGER;
BEGIN
	RETURN SHORT(ASH(i, -8) MOD 100H + ASH(i MOD 100H, 8))
END SB;

(* Reverse bits in CHAR *)
PROCEDURE Reverse(VAR c: CHAR);
VAR ib, ob: SET;  ip,op: INTEGER;
BEGIN
	ib := SYSTEM.VAL(SET, c);
	ip := 0;  op := 7;  ob := {};
	WHILE ip < 8 DO
		IF ip IN ib THEN INCL(ob, op) END;
		INC(ip);  DEC(op)
	END;
	c := SYSTEM.VAL(CHAR, ob)
END Reverse;

(* Write procedures *)

PROCEDURE WriteString(VAR s: ARRAY OF CHAR);
VAR i: LONGINT;
BEGIN
	i:= 0;
	WHILE s[i] # 0X DO
		IF s[i] = 9X THEN	(* fix because Pr3 fonts don't have same TAB *)
			Files.Write(r, " ");  Files.Write(r, " ");  Files.Write(r, " ");  Files.Write(r, " ");  INC(i)
		ELSE
			IF (s[i] < CHR(32)) & (ORD(s[i]) IN {0, 7..15, 27}) THEN
				Files.Write(r, ESC);  Files.Write(r, "&");  Files.Write(r, "p"); 
				Files.Write(r, "1");  Files.Write(r, "X")
			END;
			Files.Write(r, s[i]);  INC(i)
		END
	END
END WriteString;

PROCEDURE WriteInt(x: INTEGER);
VAR i, xx: LONGINT;  s: ARRAY 7 OF CHAR;
BEGIN
	i := 0;  xx := ABS(x);
	REPEAT
		s[i] := CHR(xx MOD 10 + ORD("0"));
		INC(i);  xx := xx DIV 10
	UNTIL xx = 0;
	IF x < 0 THEN s[i] := "-"; INC(i) END;
	REPEAT DEC(i);  Files.Write(r, s[i]) UNTIL i = 0
END WriteInt;

PROCEDURE Pos(x, y: INTEGER);
BEGIN
	y := Height - y - HPY;  DEC(x, HPX);
	Files.Write(r, ESC);  Files.Write(r, "*");  Files.Write(r, "p");
	WriteInt(x);  Files.Write(r, "x");
	WriteInt(y);  Files.Write(r, "Y")
END Pos;

PROCEDURE SetRes(res: INTEGER);
BEGIN
 	Files.Write(r, ESC);  Files.Write(r, "*");  Files.Write(r, "t");  WriteInt(res);
 	Files.Write(r, "R")
END SetRes;
	
PROCEDURE Block(w, h: INTEGER);
BEGIN
	IF (w = 1) & (h =1 ) THEN	(* it's only a dot, execute dot macro *)
		Files.Write(r, ESC);  Files.Write(r, "&");  Files.Write(r, "f");
		Files.Write(r, "1");  Files.Write(r, "y");
		Files.Write(r, "2");  Files.Write(r, "X")
	ELSE
		Files.Write(r, ESC);  Files.Write(r, "*");  Files.Write(r, "c");
		WriteInt(w);  Files.Write(r, "a");  WriteInt(h);  Files.Write(r, "b");
		Files.Write(r, "1");  Files.Write(r, "0");  Files.Write(r, "0");  Files.Write(r, "g");	(* 100 % rule pattern *)
		Files.Write(r, "2");  Files.Write(r, "P")
	END
END Block;

PROCEDURE DefineDot;	(* define macro for one dot *)
BEGIN
	Files.Write(r, ESC);  Files.Write(r, "&");  Files.Write(r, "f");
	Files.Write(r, "1");  Files.Write(r, "y");
	Files.Write(r, "0");  Files.Write(r, "X");	(* start macro *)
 
	Files.Write(r, ESC);  Files.Write(r, "*");  Files.Write(r, "c");	(* define block 1x1 *)
	Files.Write(r, "1");  Files.Write(r, "a");  Files.Write(r, "1");  Files.Write(r, "b");
	Files.Write(r, "1");  Files.Write(r, "0");  Files.Write(r, "0");  Files.Write(r, "g");	(* 100 % rule pattern *)
	Files.Write(r, "2");  Files.Write(r, "P");

	(* end macro *)
	Files.Write(r, ESC);  Files.Write(r, "&");  Files.Write(r, "f");
	Files.Write(r, "1");  Files.Write(r, "X")
END DefineDot;

PROCEDURE dot;	(* execute dot macro *)
BEGIN
	Files.Write(r, ESC);  Files.Write(r, "&");  Files.Write(r, "f");
	Files.Write(r, "1");  Files.Write(r, "y");
	Files.Write(r, "2");  Files.Write(r, "X")
END dot;

PROCEDURE InitPage;
VAR y: INTEGER;
BEGIN
	NEW(M);
	y := 0;  WHILE y < Height DO M[y] := NIL; INC(y) END;
	maxX := MIN(INTEGER);  maxY := MIN(INTEGER);
	minX := MAX(INTEGER);  minY := MAX(INTEGER)
END InitPage;

PROCEDURE ClosePage;
VAR k, j, l, x, y, t, i: INTEGER;
BEGIN
	IF M = NIL THEN RETURN END;
	y := minY;
	WHILE y <= maxY DO
		IF M[y] # NIL THEN
			j := minX;
			WHILE j <= maxX DO
				WHILE (j <= maxX) & ~In(M[y], j) DO INC(j) END;
				l := 0;  x := j;
				WHILE (j <= maxX) & In(M[y], j) DO INC(l);  INC(j) END;
				IF l > 0 THEN Pos(x, y);  Block(l,1) END
			END;
			M[y] := NIL	(* Clear *)
		END;
		INC(y)
	END;
	maxX := MIN(INTEGER);
	maxY := MIN(INTEGER);
	minX := MAX(INTEGER);
	minY := MAX(INTEGER)
END ClosePage;

PROCEDURE CreateFontDesc(id, base, cw, ch, or, sp, pi, he: INTEGER;  name: ARRAY OF CHAR);
VAR i: INTEGER;  a: LONGINT;  x: CHAR;  fd: HPFontDesc;  fdlen: INTEGER;
BEGIN
	fdlen := SIZE(HPFontDesc);
	Files.Write(r, ESC);  Files.Write(r, "*");  Files.Write(r, "c");  WriteInt(id);  Files.Write(r, "D");
	Files.Write(r, ESC);  Files.Write(r, "*");  Files.Write(r, "c");  Files.Write(r, "4");  Files.Write(r, "F"); 
	(* temporary font *)
	Files.Write(r, ESC);  Files.Write(r, ")");  Files.Write(r, "s");  WriteInt(fdlen);  Files.Write(r, "W");

	fd.size := SB(fdlen);
	fd.res0 := 0;
	fd.type := 2;	(* any character *)
	fd.res1 := 0;
	fd.base := SB(base);
	fd.cellwidth := SB(cw); 
	fd.cellheight := SB(ch);
	fd.orient := SHORT(or);
	fd.space := SHORT(sp);
	fd.symbol := SB((10 * 32 + ORD("U") - 64));	(* 10U *)
	fd.pitch := SB(pi * 4);
	fd.height := SB(4 * he);
	fd.xheight := 0;  fd.widthtype := 0;  fd.style := 0;  fd.strokeweight := 0;
	fd.typeface := 5;
	fd.res2 := 0;  fd.serifstyle := 0;  fd.res3 := 0;  fd.underdist := 0;  fd.underheight := 0;
	fd.textheight := 0;  fd.textwidth := 0;  fd.res4 := 0;  fd.res5 := 0;  fd.pitchext := 0;
	fd.heightext := 0;  fd.res6 := 0;  fd.res7 := 0;  fd.res8 := 0;
	
	(* copy the font name *)
	i := 0;  WHILE (i < LEN(name)) & (i < LEN(fd.name)) DO fd.name[i] := name[i];  INC(i) END;
	WHILE i < LEN(fd.name) DO fd.name[i] := 0X; INC(i) END;
	
	(* copy the descriptor to file *)
	i:= 0;
	a := SYSTEM.ADR(fd);
	WHILE i < fdlen DO
		SYSTEM.GET(a,x);  INC(a); 
		Files.Write(r, x);
		INC(i)
	END
END CreateFontDesc;

(* define one character for LaserJet *)
PROCEDURE DownloadChar(fnt: Fonts.Font;  ch:CHAR;  num: INTEGER);
CONST maxpat = 256;
TYPE
	Pattern = POINTER TO PatternDesc;
	PatternDesc = RECORD 
		w, h: SHORTINT;
		raster: ARRAY (maxpat+7) DIV 8 * maxpat OF CHAR;
	END;
VAR
	hdr: HPCharDesc;  size, i, hdrlen, dx, x, y, w, h: INTEGER;  pat, a: LONGINT;
	c: CHAR;  p: Pattern;  j, k, l: INTEGER;
BEGIN
	hdrlen := SIZE(HPCharDesc);
	(* Get char definition *)
	Fonts.GetChar(fnt, ch, dx, x, y, w, h, pat);
	(* create char descriptor for HP *)
	hdr.fix1 := 4;	(* 4, 0 *)
	hdr.fix2 := 256 * 1 + 14;	(* 14,1 *)
	hdr.orient := 0; 
	hdr.left := SB(x);	
	hdr.top := SB(h+y); 
	hdr.width := SB(w);
	hdr.height := SB(h);
	hdr.delta := SB(4*dx);	(* multiple of 4 must be *)
	
	(* write commands for HP *)
	size := ((w+7) DIV 8) * h;	(* pattern size *)
	Files.Write(r, ESC);  Files.Write(r, "*");  Files.Write(r, "c");  WriteInt(num);  Files.Write(r, "E");
	Files.Write(r, ESC);  Files.Write(r, "(");  Files.Write(r, "s");  WriteInt(size+hdrlen);  Files.Write(r, "W");
	a := SYSTEM.ADR(hdr);
	i:= 0;
	WHILE i < hdrlen DO		(* write char descriptor *)
		SYSTEM.GET(a,c);  INC(a);
		Files.Write(r, c);
		INC(i)
	END;
	IF size # 0 THEN
		(* write raster data in reverse mode *)
		p := SYSTEM.VAL(Pattern, pat);
		l := (w+7) DIV 8;
		j := size - l;
		WHILE j >= 0 DO 
			k := 0;
			WHILE k < l DO
				c := p.raster[j+k];  Reverse(c);
				Files.Write(r, c);
				INC(k)
			END;
			DEC(j, l)
		END
	END
END DownloadChar;

PROCEDURE SwitchOn(fntno: SHORTINT);
BEGIN
	Files.Write(r, ESC);  Files.Write(r, "(");  WriteInt(BaseFont+fntno);  Files.Write(r, "X")
END SwitchOn;

PROCEDURE CreateFont (fnt: Fonts.Font; fntno, pitch, orient, spacing: INTEGER);
BEGIN
	(* create font descriptor for new font arrived *)
	CreateFontDesc(fntno, fnt.maxY, (* baseline *)
		fnt.maxX-fnt.minX,	(* cell with *)
		fnt.maxY-fnt.minY,	(* cell height *)
		orient,	(* orientation, potrait*)
		spacing,	(* spacing, proportionel *)
		pitch,
		fnt.height,	(* height *)
		fnt.name);
END CreateFont;

PROCEDURE SetFont(name: ARRAY OF CHAR;  VAR s : ARRAY OF CHAR);
VAR fnt: Fonts.Font;  ch, fnttype: CHAR;  i, id: INTEGER;  fntno,pitch: SHORTINT;  inserted: BOOLEAN;

	PROCEDURE ToPr3Font(VAR fn: ARRAY OF CHAR;  VAR pi: SHORTINT);
	VAR i: INTEGER;  ch, ch2, ch3: CHAR;
	BEGIN
		i := 0;  ch := fn[i];
		WHILE ((ch < "0") OR (ch > "9")) & (ch # ".") & (ch # 0X) DO INC(i);  ch := fn[i] END;
		IF (ch = ".") OR (ch = 0X) THEN pi := 0
		ELSE
			pi := SHORT(ORD(ch) - ORD("0"));
			INC(i);  ch := fn[i];
			IF (ch >= "0") & (ch <= "9") THEN
				pi := SHORT (10* pi + (ORD(ch)- ORD("0")));
				INC(i);  ch := fn[i]
			END;
			IF ch # "." THEN INC(i) END
		END;
		(* convert "*.Scn.*" filename to "*.Pr3.*" file name *)
		ch := fn[i+1];
		ch2 := fn[i+2];
		ch3 := fn[i+3];
		IF (ch = "S") & (ch2 = "c") & (ch3= "n") THEN fn[i+1] := "P";  fn[i+2] := "r";  fn[i+3] := "3" END
	END ToPr3Font;

BEGIN
	ToPr3Font(name, pitch);	(* convert name to Printer file name *)
	
	IF (Files.Old(name) = NIL) THEN	(* no such file *)
		COPY("Oberon10.Pr3.Fnt", name)	(* default printer font *);
	END;
	LookupFont(name,fntno,inserted);	(* lookup in own font table *)
	IF inserted THEN	(* if new font then init*)
		font[fntno].pitch := pitch; 
		New(font[fntno].chartab, 256);
		i := 0;
		WHILE s[i] # 0X DO	(* set the used chars in this font *)
			Incl(font[fntno].chartab,ORD(s[i]));
			INC(i)
		END
	ELSIF fntno < maxfonts THEN	(* found *)
		i := 0;
		WHILE s[i] # 0X DO	(* set used characters inside the font *)
			Incl(font[fntno].chartab,ORD(s[i]));
			INC(i)
		END
	ELSE (* table full*)
	END;
	PrevFont := CurFont;
	CurFont := fntno;
	IF CurFont # PrevFont THEN	(* change font if it needed *)
		SwitchOn(fntno)
	END
END SetFont;

PROCEDURE LoadFont(f: SHORTINT);	(* load used font with used chars *)
VAR i: INTEGER;
BEGIN
	CreateFont(Fonts.This(font[f].name), BaseFont+f, font[f].pitch, PORTRAIT, PROPOR);
	i:= 0;
	WHILE i < 256 DO
		IF In(font[f].chartab,i) THEN DownloadChar(Fonts.This(font[f].name), CHR(i), i) END;
		INC(i)
	END
END LoadFont;

PROCEDURE Dot(x, y: INTEGER);
BEGIN
	IF M = NIL THEN InitPage END;	(* the first graphic usage *)
	IF M[y] = NIL THEN New(M[y], Width) END;
	Incl(M[y], x);
	IF x > maxX THEN maxX := x END;
	IF y > maxY THEN maxY := y END;
	IF x < minX THEN minX := x END;
	IF y < minY THEN minY := y END
END Dot;

PROCEDURE line(x0, y0, x1, y1: INTEGER);
VAR x, y, dx, dy, d, inc: INTEGER;
BEGIN
	IF y1 - y0 < x0 - x1 THEN 
		x := x0; 
		x0 := x1; x1 := x; y := y0; 
		y0 := y1; y1 := y 
	END;
	dx := 2 * (x1 - x0);
	dy := 2 * (y1 - y0);
	x := x0; y := y0; inc := 1;
	IF dy > dx THEN
		d := dy DIV 2;
		IF dx < 0 THEN inc := -1; dx := -dx END;
		WHILE y <= y1 DO
			Dot(x, y);
			INC(y); DEC(d, dx);
			IF d < 0 THEN INC(d, dy); INC(x, inc) END
		END
	ELSE
		d := dx DIV 2;
		IF dy < 0 THEN inc := -1; dy := -dy END;
		WHILE x <= x1 DO
			Dot( x, y);
			INC(x); DEC(d, dy);
			IF d < 0 THEN INC(d, dx); INC(y, inc) END
		END
	END
END line;

PROCEDURE circle (x0, y0, r: INTEGER);
VAR x, y, q: INTEGER;
BEGIN
	x := 0; y := r; q := r;
	WHILE x <= y DO
		Dot( x0 + x, y0 + y); Dot( x0 + y, y0 + x);
		Dot( x0 - x, y0 + y); Dot( x0 - y, y0 + x);
		Dot( x0 + x, y0 - y); Dot( x0 + y, y0 - x);
		Dot( x0 - x, y0 - y); Dot( x0 - y, y0 - x);
		INC(x); DEC(q, 2 * x - 1);
		IF q <= 0 THEN DEC(y); INC(q, 2 * y) END
	END
END circle;

PROCEDURE ellipse(x0, y0, a, b: INTEGER);
VAR a2, b2, ex, ey, q: LONGINT; x, y: INTEGER;
BEGIN
	IF (a <= 800) & (b <= 800) THEN (* longint range guard *)
		a2 := LONG(a) * a; b2 := LONG(b) * b;
		ex := b2; ey := a2 * (b * 2 - 1); q := 0;
		a2 := a2 * 2; b2 := b2 * 2;
		x := 0; y := b;
		WHILE ey > ex DO
			Dot( x0 + x, y0 + y); Dot( x0 - x, y0 + y);
			Dot( x0 + x, y0 - y); Dot( x0 - x, y0 - y);
			INC(x); INC(q, 2 * ex); INC(ex, b2);
			IF q > ey THEN DEC(y); DEC(q, 2 * ey); DEC(ey, a2) END
		END;
		WHILE y >= 0 DO
			Dot( x0 + x, y0 + y); Dot( x0 - x, y0 + y);
			Dot( x0 + x, y0 - y); Dot( x0 - x, y0 - y);
			DEC(y); DEC(q, 2 * ey); DEC(ey, a2);
			IF q < -ex THEN INC(x); INC(q, 2 * ex); INC(ex, b2) END
		END
	END
END ellipse;

PROCEDURE PrintPoly(x0, y0: INTEGER; VAR p, q: Poly; lim: REAL);
VAR t: REAL; x, y: LONGINT;
BEGIN t := 0;
	REPEAT
		Dot(SHORT(ENTIER(((p.a * t + p.b) * t + p.c) * t + p.d) + x0),SHORT(ENTIER(((q.a * t + q.b) * t + q.c) * t + q.d) + y0));
		t := t + 1.0
	UNTIL t >= lim
END PrintPoly;

PROCEDURE SolveTriDiag(VAR a, b, c, y: RealVector; n: INTEGER);
VAR i: INTEGER;
		r: REAL;
BEGIN (*a, b, c of tri-diag matrix T; solve Ty' = y for y', assign y' to y*)
	i := 1;
	WHILE i < n DO 
		r := y[i];
		r :=r - c[i-1]*y[i-1]; 
		y[i] := r;
		INC(i) 
	END ;
	i := n-1; y[i] := y[i]/a[i];
	WHILE i > 0 DO 
		DEC(i); r := y[i];
		r := (r- b[i]*y[i+1])/a[i] ;
		y[i] := r;
	END
END SolveTriDiag;

PROCEDURE OpenSpline(VAR x, y, d: RealVector; n: INTEGER);
VAR i: INTEGER; d1, d2: REAL;
		a, b, c: RealVector;
BEGIN (*from x, y compute d = y'*)
	b[0] := 1.0/(x[1] - x[0]); a[0] := 2.0*b[0]; c[0] := b[0];
	d1 := (y[1] - y[0])*3.0*b[0]*b[0]; d[0] := d1; i := 1;
	WHILE i < n-1 DO
		b[i] := 1.0/(x[i+1] - x[i]);
		a[i] := 2.0*(c[i-1] + b[i]);
		c[i] := b[i];
		d2 := (y[i+1] - y[i])*3.0*b[i]*b[i];
		d[i] := d1 + d2; d1 := d2; INC(i)
	END ;
	a[i] := 2.0*b[i-1]; d[i] := d1; i := 0;
	WHILE i < n-1 DO c[i] := c[i]/a[i]; a[i+1] := a[i+1] - c[i]*b[i]; INC(i) END ;
	SolveTriDiag(a, b, c, d, n)
END OpenSpline;

PROCEDURE ClosedSpline(VAR x, y, d: RealVector; n: INTEGER);
VAR i: INTEGER; d1, d2, hn, dn,r: REAL;
		a, b, c, w: RealVector;
BEGIN (*from x, y compute d = y'*)
	hn := 1.0/(x[n-1] - x[n-2]);
	dn := (y[n-1] - y[n-2])*3.0*hn*hn;
	b[0] := 1.0/(x[1] - x[0]);
	a[0] := 2.0*b[0] + hn;
	c[0] := b[0];
	d1 := (y[1] - y[0])*3.0*b[0]*b[0]; d[0] := dn + d1;
	w[0] := 1.0; i := 1;
	WHILE i < n-2 DO
		b[i] := 1.0/(x[i+1] - x[i]);
		a[i] := 2.0*(c[i-1] + b[i]);
		c[i] := b[i];
		d2 := (y[i+1] - y[i])*3.0*b[i]*b[i]; d[i] := d1 + d2; d1 := d2;
		w[i] := 0; INC(i)
	END ;
	a[i] := 2.0*b[i-1] + hn; d[i] := d1 + dn;
	w[i] := 1.0; i := 0;
	WHILE i < n-2 DO c[i] := c[i]/a[i]; a[i+1] := a[i+1] - c[i]*b[i]; INC(i) END ;
	SolveTriDiag(a, b, c, d, n-1); SolveTriDiag(a, b, c, w, n-1); 
	r := d[i];
	d1 := (d[0] + r)/(w[0] + w[i] + x[i+1] - x[i]); i := 0;
	WHILE i < n-1 DO 
		d[i]:=d[i] - d1*w[i]; INC(i) ;
	END ;
	d[i] := d[0]
END ClosedSpline;

PROCEDURE spline (x0, y0, n, open: INTEGER; VAR u,v: ARRAY OF INTEGER);
VAR i: INTEGER; dx, dy, ds: REAL;
		x, xd, y, yd, s: RealVector;
		p, q: PolyVector;
BEGIN (*from u, v compute x, y, s*)
	x[0] := u[0]; y[0] := v[0]; s[0] := 0;	i := 1;
	WHILE i < n DO
		x[i] := u[i]; dx := x[i] - x[i-1];
		y[i] := v[i]; dy := y[i] - y[i-1];
		s[i] := ABS(dx) + ABS(dy) + s[i-1]; INC(i)
	END ;
	IF open = 1	THEN OpenSpline(s, x, xd, n); OpenSpline(s, y, yd, n)
	ELSE ClosedSpline(s, x, xd, n); ClosedSpline(s, y, yd, n)
	END ;
	(*compute coefficients from x, y, xd, yd, s*)	i := 0;
	WHILE i < n-1 DO
		ds := 1.0/(s[i+1] - s[i]);
		dx := (x[i+1] - x[i])*ds;
		p[i].a := ds*ds*(xd[i] + xd[i+1] - 2.0*dx);
		p[i].b := ds*(3.0*dx - 2.0*xd[i] -xd[i+1]);
		p[i].c := xd[i];
		p[i].d := x[i];
		p[i].t := s[i];
		dy := ds*(y[i+1] - y[i]);
		q[i].a := ds*ds*(yd[i] + yd[i+1] - 2.0*dy);
		q[i].b := ds*(3.0*dy - 2.0*yd[i] - yd[i+1]);
		q[i].c := yd[i];
		q[i].d := y[i];
		q[i].t := s[i]; INC(i)
	END;
	(*display polynomials*)
	i := 0;
	WHILE i < n-1 DO PrintPoly( x0, y0, p[i], q[i], p[i+1].t - p[i].t); INC(i) END
END spline;

PROCEDURE GetDim(label: ARRAY OF CHAR;  def: INTEGER;  VAR val: INTEGER);
VAR v: REAL; S: Texts.Scanner;
BEGIN
	Oberon.OpenScanner(S, label);
	IF (S.class = Texts.Int) OR (S.class = Texts.Real) THEN
		IF S.class = Texts.Int THEN v := S.i
		ELSE v := S.x
		END;
		Texts.Scan(S);
		IF S.class = Texts.Name THEN
			IF S.s = "cm" THEN v := v*360000.0
			ELSIF S.s = "mm" THEN v := v*36000.0
			ELSIF S.s = "in" THEN v := v*36000.0*25.4
			ELSE v := v*36000.0
			END
		ELSE v := v*36000.0
		END;
		val := SHORT(ENTIER(v/Unit + 0.5))
	ELSE val := def
	END
END GetDim;

PROCEDURE SetMetrics(P: Printer.Printer);
BEGIN
	Unit := 3048;  P.Unit := Unit;
	Depth := 1;  P.Depth := Depth;
	GetDim("HPLaserPrinter.Width", 2480, Width);
	IF Width > HPPageWidth THEN Width := HPPageWidth END;
	GetDim("HPLaserPrinter.Height", 3508, Height);
	IF Height > HPPageHeight THEN Height := HPPageHeight END;
	P.Width := Width;  P.Height := Height;
	
	GetDim("HPLaserPrinter.LeftMargin", 236, P.FrameX);
	GetDim("HPLaserPrinter.RightMargin", 236, P.FrameW);
	P.FrameW := Width-P.FrameX-P.FrameW;
	GetDim("HPLaserPrinter.BottomMargin", 177, P.FrameY);
	GetDim("HPLaserPrinter.TopMargin", 177, P.FrameH);
	P.FrameH := Height-P.FrameY-P.FrameH
END SetMetrics;

PROCEDURE InitMetrics*(P: Printer.Printer);
VAR M: Display.ControlMsg;  N: Oberon.ControlMsg;
BEGIN
	SetMetrics(P);
	IF Printer.current # NIL THEN
		N.id := Oberon.neutralize;  M.F := NIL; Display.Broadcast(N);
		M.id := Display.newprinter;  M.F := NIL; Display.Broadcast(M);
		M.id := Display.suspend;  M.F := NIL; Display.Broadcast(M);
		M.id := Display.restore;  M.F := NIL; Display.Broadcast(M)
	END
END InitMetrics;

PROCEDURE Open*(P: Printer.Printer;  printer, options: ARRAY OF CHAR);
BEGIN
	Files.Set(r, Files.New(""), 0);
	Files.Set(u, Files.New(printer), 0);
	NEW(font);  nofonts := 0;  CurFont := -1;
	P.res := 0
END Open;

PROCEDURE UseListFont*(P: Printer.Printer;  name: ARRAY OF CHAR);
BEGIN
	(* not implemented *)
END UseListFont;

PROCEDURE ReplConst*(P: Printer.Printer;  x, y, w, h: INTEGER);
BEGIN
	IF (w > 0) & (h > 0 ) THEN Pos(x, y+h);  Block(w,h) END
END ReplConst;
	
PROCEDURE ContString*(P: Printer.Printer;  s: ARRAY OF CHAR;  fnt: Fonts.Font);
BEGIN
	SetFont(fnt.name, s);
	WriteString(s)
END ContString;

PROCEDURE String*(P: Printer.Printer;  x, y: INTEGER;  s: ARRAY OF CHAR;  fnt: Fonts.Font);
BEGIN
	SetFont(fnt.name, s);
	Pos(x, y);
	WriteString(s)
END String;

PROCEDURE ReplPattern*(P: Printer.Printer;  x, y, w, h, col: INTEGER);
BEGIN
	col := ((100 DIV 16) * col) MOD 100 + 1;	(* to range 1..100 *)
	Pos(x, y+h);
	Files.Write(r, ESC);  Files.Write(r, "*");  Files.Write(r, "c");
	WriteInt(w);  Files.Write(r, "a");  WriteInt(h);  Files.Write(r, "b");
	WriteInt(col);  Files.Write(r, "g");
	Files.Write(r, "2");  Files.Write(r, "P")
END ReplPattern;

PROCEDURE Picture*(print: Printer.Printer; P: Pictures.Picture; px, py, pw, ph, X, Y, W, H, mode: INTEGER);
CONST Shift = 100000;	(* max device distance: MAX(LONGINT) DIV Shift *)
VAR scaleX, scaleY: LONGINT;  trailer, run: RunP;  x0, x, y, col: INTEGER;  colored: BOOLEAN;

	PROCEDURE RGBToPatNr(red, green, blue: INTEGER; VAR pNr: INTEGER);
	(* pNr: 0..ColSubdiv-1  [white, light ...dark, black] *)
		CONST ColNrRange = 2550 DIV ColSubDiv;
	BEGIN
		pNr := 10 * 255 - 3 * red - 6 * green - blue;	(* 10 * 255 -> invert value *)
		pNr := pNr DIV ColNrRange;
		IF pNr >= ColSubDiv THEN pNr := ColSubDiv - 1 ELSIF pNr < 0 THEN pNr := 0 END
	END RGBToPatNr;
	
	PROCEDURE Scale(pixel, scale: LONGINT): INTEGER;
	BEGIN
		RETURN SHORT(pixel * scale DIV Shift)
	END Scale;
	
	PROCEDURE PrintRun(VAR run: RunP);
		VAR red, green, blue, pNr: INTEGER;
	BEGIN
		run.w := Scale(run.x + run.w, scaleX); run.x := Scale(run.x, scaleX);	(* scale right and left *)
		run.h := Scale(run.y + run.h, scaleY); run.y := Scale(run.y, scaleY);	(* scale top and bottom *)
		DEC(run.w, run.x); DEC(run.h, run.y);		(* scaled width and height *)
		IF (run.w > 0) & (run.h > 0) THEN	(* run visible *)
			IF colored THEN
				Pictures.GetColor(P, run.col, red, green, blue);
				IF Depth > 1 THEN
					UseColor(print, red, green, blue);
					ReplConst(print, X + run.x, Y + run.y, run.w, run.h)
				ELSE
					RGBToPatNr(red, green, blue, pNr);
					IF pNr = ColSubDiv - 1 THEN ReplConst(print, X + run.x, Y + run.y, run.w, run.h)
					ELSE ReplPattern(print, X + run.x, Y + run.y, run.w, run.h, pNr)
					END
				END
			ELSE
				ReplConst(print, X + run.x, Y + run.y, run.w, run.h)
			END
		END;
		run.prev.next := run.next; run.next.prev := run.prev;	(* remove from run list *)
		run.prev := freeP; freeP := run;				(* recycle printed run *)
		run := run.next; freeP.next := NIL		(* advance in run list *)
	END PrintRun;
	
	PROCEDURE InsertRun(run: RunP; x, y, w, col: INTEGER);
	(* inserts a new run before run *)
		VAR r: RunP;
	BEGIN	(* x + w <= run.x *)
		IF freeP # NIL THEN r := freeP; freeP := freeP.prev ELSE NEW(r) END;
		r.x := x; r.y := y; r.w := w; r.h := 1; r.col := col;
		r.next := run; r.prev := run.prev; run.prev.next := r; run.prev := r	(* add r to run list *)
	END InsertRun;
	
	PROCEDURE EnlargeRun(trailer: RunP; VAR run: RunP; x, y, w, col: INTEGER);
	BEGIN
		WHILE (run # trailer) & (run.x < x) DO PrintRun(run) END;	(* print runs before x *)
		IF run = trailer THEN InsertRun(run, x, y, w, col)
		ELSIF (run.x = x) & (run.w = w) & (run.col = col) THEN INC(run.h); run := run.next	(* enlarge run height *)
		ELSE	(* run.x >= x *)
			WHILE (run # trailer) & (run.x < x + w) DO PrintRun(run) END;
			InsertRun(run, x, y, w, col)
		END
	END EnlargeRun;

BEGIN
	scaleX := W * Shift DIV (*P.width*) pw; scaleY := H * Shift DIV (*P.height*) ph;
	NEW(trailer); trailer.next := trailer; trailer.prev := trailer;
	y := py; colored := P.depth > 1;
	
	IF Depth = 1 THEN UseColor(print, 0, 0, 0) END; (* set color at the beginning !*)
	
	WHILE y < py + ph DO
		x := px; run := trailer.next;
		WHILE x <  px + pw DO
			x0 := x; Pictures.GetRun(P, col, x, y);
			IF x > px + pw THEN x := px + pw END;
			IF colored OR (col # Display.BG) THEN
				EnlargeRun(trailer, run, x0 - px, y - py, x-x0, col)
			END
		END;
		WHILE run # trailer DO PrintRun(run) END;
		INC(y)
	END;

	run := trailer.next; WHILE run # trailer DO PrintRun(run) END;
	UseColor(print, 0, 0, 0)
END Picture;

PROCEDURE Circle*(P: Printer.Printer;  x0, y0, r: INTEGER);
BEGIN
	circle (x0, y0, r)
END Circle;

PROCEDURE Ellipse*(P: Printer.Printer;  x0, y0, a, b: INTEGER);
BEGIN
	ellipse(x0, y0, a, b)
END Ellipse;

PROCEDURE Line*(P: Printer.Printer;  x0, y0, x1, y1: INTEGER);
BEGIN
	IF x0 = x1 THEN	(* if it is a vertical line *)
		ReplConst(P, x0,y0,1,ABS(y1-y0))
	ELSIF y0 = y1 THEN	(* if it is a horizontal line *)
		ReplConst(P, x0,y0,ABS(x1-x0),1)
	ELSE line(x0, y0, x1, y1)
	END
END Line;

PROCEDURE UseColor*(P: Printer.Printer;  red, green, blue: INTEGER);
BEGIN
	(* not implemented *)
END UseColor;

PROCEDURE Spline*(P: Printer.Printer;  x0, y0, n, open: INTEGER;  VAR X, Y: ARRAY OF INTEGER);
BEGIN
	spline(x0, y0, n, open, X, Y)
END Spline;

PROCEDURE Page*(P: Printer.Printer;  nofcopies: INTEGER);
BEGIN
	ClosePage;	(* close graphics page *)
	IF nofcopies > 1 THEN	(* make a copy from the page *)
		Files.Write(r, ESC);  Files.Write(r, "&");  Files.Write(r, "I");
		WriteInt(nofcopies);  Files.Write(r, "X")
	END;
	Files.Write(r, FF)
END Page;

PROCEDURE Close*(P: Printer.Printer);
VAR tmp: Files.Rider;  ch: CHAR;  i: SHORTINT;
BEGIN
	Files.Set(tmp, Files.Base(r), 0);
	Files.Set(r, Files.Base(u), 0);
	Files.Write(r, ESC);  Files.Write(r, "E");	(* Reset Printer *)
	SetRes(300);
	DefineDot;
	i := 0;
	WHILE i < nofonts DO	(* load used fonts *)
		LoadFont(i); INC(i)
	END;

	Files.Read(tmp, ch);
	WHILE ~tmp.eof DO Files.Write(r, ch);  Files.Read(tmp, ch) END;
	ClosePage;	(* the page must be ended if it is not so *)
	Files.Write(r, ESC);  Files.Write(r, "E");	(* Reset Printer *)
	
	Printer.Spool(Files.Base(r));  P.res := Printer.res;
	
	font := NIL;  nofonts := 0;
	Files.Set(r, NIL, 0);  Files.Set(u, NIL, 0);
	M := NIL;
	freeP := NIL
END Close;

PROCEDURE GetMetric* (P: Printer.Printer;  fnt: Fonts.Font): Fonts.Font;
VAR name: ARRAY 32 OF CHAR;  i: INTEGER;  metric: Fonts.Font;
BEGIN
	COPY(fnt.name, name);
	i := 0;  WHILE (name[i] # ".") & (name[i] # 0X) DO INC(i) END;
	(* look for Mdx *)
	name[i] := "."; name[i+1] := "M"; name[i+2] := "d"; name[i+3] := "3";
	name[i+4] := "."; name[i+5] := "F"; name[i+6] := "n"; name[i+7] := "t";
	name[i+8] := 0X;
	metric := Fonts.This(name);
	IF metric.type = Fonts.substitute THEN metric := NIL END;
	RETURN metric
END GetMetric;

PROCEDURE NewPrinter*(): Printer.Printer;
VAR P: Printer.Printer;
BEGIN
	NEW(P);
	P.name := "HPLaserPrinter.Install";
	P.InitMetrics := InitMetrics;
	P.Open := Open;
	P.Close := Close;
	P.Page := Page;
	P.ReplConst := ReplConst; 
	P.ReplPattern := ReplPattern;
	P.Line := Line;
	P.Circle := Circle;
	P.Ellipse := Ellipse;
	P.Spline := Spline;
	P.Picture := Picture;
	P.UseListFont := UseListFont;
	P.String := String;
	P.ContString := ContString;
	P.UseColor := UseColor;
	P.GetMetric := GetMetric;
	RETURN P
END NewPrinter;

PROCEDURE Install*;
BEGIN
	(* register font loader for special metrics, if needed *)
	Printer.Install(NewPrinter());
END Install;

BEGIN
	M := NIL;  freeP := NIL
END HPLaserPrinter.

System.Free HPLaserPrinter ~

HPLaserPrinter.Install
