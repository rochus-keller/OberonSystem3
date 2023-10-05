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

MODULE Backdrops;	(* Daniel Ponti	Jan 94 *)
										(* Revidiert:		Jan 95	Daniel Ponti
										Änderungen:	Basiert nun auf Rembrandt0 und RembrandtDocs Modul *)

(** Dieses Modul enthält alle Backdrop-Algorithmen und verwaltet die zugehörigen Farbpaletten *)

IMPORT 
	Texts, Oberon, Pictures, Rembrandt0, Rembrandt, Display, Math, Input, Gadgets, Objects,
	Files, BasicGadgets, Out, RembrandtDocs;

TYPE ptr = POINTER TO complex;
		complex = RECORD							(* Komplexe Zahl fuer Backdrop Fractal *)
							r,i : REAL
						END;

VAR seed: LONGINT;									(* fuer Zufallszahlenberechnung *)
		noisetable : ARRAY 99, 99 OF INTEGER;	(* Zufallszahlenfeld *)
		maxnoise, px, py : INTEGER;
		r0, r1, g0, g1, b0, b1 : INTEGER;	(* Farbwerte fuer Rampe *)
		
PROCEDURE SetColorRamp();
(* Erstellt eine Farbrampe von RGB(r0, g0, b0) nach RGB(r1, g1, b1) mit BD.noc Farbabstufungen *)
VAR
		i : INTEGER;
		dr, dg, db : REAL;
BEGIN
	IF r0>255 THEN r0:=255 ELSIF r0<0 THEN r0:=0 END;
	IF r1>255 THEN r1:=255 ELSIF r1<0 THEN r1:=0 END;
	IF g0>255 THEN g0:=255 ELSIF g0<0 THEN g0:=0 END;
	IF g1>255 THEN g1:=255 ELSIF g1<0 THEN g1:=0 END;
	IF b0>255 THEN b0:=255 ELSIF b0<0 THEN b0:=0 END;
	IF b1>255 THEN b1:=255 ELSIF b1<0 THEN b1:=0 END;
	dr:= (r1-r0)/(Rembrandt0.noc-1);
	dg:= (g1-g0)/(Rembrandt0.noc-1);
	db:= (b1-b0)/(Rembrandt0.noc-1);
	FOR i:= 0 TO Rembrandt0.noc-1 DO
(* why this ?
		Rembrandt0.coltable[i+1].r:= r0+SHORT(ENTIER(i*dr));
		Rembrandt0.coltable[i+1].g:= g0+SHORT(ENTIER(i*dg));
		Rembrandt0.coltable[i+1].b:= b0+SHORT(ENTIER(i*db))
*)
		Rembrandt0.coltable[i].r:= r0+SHORT(ENTIER(i*dr));
		Rembrandt0.coltable[i].g:= g0+SHORT(ENTIER(i*dg));
		Rembrandt0.coltable[i].b:= b0+SHORT(ENTIER(i*db))

	END
END SetColorRamp;

(** Liest die Werte der Slider in die globalen Variablen r0 bis b1 *)
PROCEDURE SetVal*();
VAR S : Texts.Scanner;
		n : INTEGER;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN n:= SHORT(S.i) END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN 
		CASE n OF
			   0 : r0:= SHORT(S.i) 
			| 1 : g0:= SHORT(S.i) 
			| 2 : b0:= SHORT(S.i)
			| 3 : r1:= SHORT(S.i)
			| 4 : g1:= SHORT(S.i)
			| 5 : b1:= SHORT(S.i)
		END;
	SetColorRamp
	END
END SetVal;

(** Setzt Farben für Wolkenstruktur *)
PROCEDURE SetSkyColor*();
VAR i : INTEGER;
BEGIN
	Rembrandt0.noc:= 6;
	FOR i:= 1 TO 5 DO
		Rembrandt0.coltable[i].r:= (i-1)*60;
		Rembrandt0.coltable[i].g:=Rembrandt0.coltable[i].r;
		Rembrandt0.coltable[i].b:= 255
	END
END SetSkyColor;

(** Setzt Farben für Marmorstruktur *)
PROCEDURE SetMarbleColor*();
VAR i, h : INTEGER;
BEGIN
	Rembrandt0.noc:= 5;
	FOR i:= 1 TO 5 DO
		h:= (i-1)*40+50;
		Rembrandt0.coltable[i].r:= h;
		Rembrandt0.coltable[i].g:= h;
		Rembrandt0.coltable[i].b:= h
	END
END SetMarbleColor;

(** Setzt die Hintergrundfarbe *)
PROCEDURE SetBackground*();
VAR S : Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN Rembrandt0.color.col:= SHORT(S.i) END;
	IF (Rembrandt0.color.col<0) OR (Rembrandt0.color.col>Rembrandt0.maxnoc) THEN Rembrandt0.color.col:=0 END;
	Display.GetColor(Rembrandt0.color.col, Rembrandt0.coltable[0].r, Rembrandt0.coltable[0].g, Rembrandt0.coltable[0].b);
	Rembrandt0.color.col:=0; Gadgets.Update(Rembrandt0.color)
END SetBackground;

(** Eine einzelne Farbe kann geändert werden; Farbnummer colno mit RGB(r, g, b); wird zur Zeit nicht verwendet *)
PROCEDURE SetColor*();
VAR S : Texts.Scanner;
		colno, r, g, b : INTEGER;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN colno:= SHORT(S.i) ELSE colno:= 1 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN r:= SHORT(S.i) ELSE r:= 110 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN g:= SHORT(S.i) ELSE g:= 110 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN b:= SHORT(S.i) ELSE b:= 110 END;
	IF (colno>Rembrandt0.noc) OR (colno<1) THEN colno:= 1 END;
	Rembrandt0.coltable[colno].r:= r;
	Rembrandt0.coltable[colno].g:= g;
	Rembrandt0.coltable[colno].b:= b
END SetColor;

(** Setzt die Anzahl Farben für Farbrampen *)
PROCEDURE SetNoColor*();
VAR S : Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN Rembrandt0.noc:= SHORT(S.i) END;
	IF Rembrandt0.noc>Rembrandt0.maxnoc THEN Rembrandt0.noc:=Rembrandt0.maxnoc 
	ELSIF Rembrandt0.noc<1 THEN Rembrandt0.noc:= 1
	END;
	SetColorRamp
END SetNoColor;

PROCEDURE Random(): LONGINT;
(* Liefert eine Zufallszahl vom Typ Longint *)
CONST a = 16807; m = 2147483647; q = m DIV a; r = m MOD a;
VAR i: LONGINT; 
BEGIN 
	seed := ABS(Oberon.Time()-seed);
	i := a * (seed MOD q) - r * (seed DIV q);
	IF i > 0 THEN seed := i ELSE seed := i + m END;
	RETURN seed 
END Random;

PROCEDURE CheckKeyboard(): BOOLEAN;
(* liefert TRUE zurück falls während dem Zeichnen eine definierte
	Taste gedrückt wurde oder eine Mousetaste*)
CONST Quit=27;	(* ESC_Taste *)
VAR ch: CHAR;
		x, y : INTEGER;
		keys : SET;
BEGIN
	IF Input.Available()#0 THEN
		Input.Read(ch);
		IF ORD(ch)=Quit THEN RETURN TRUE
		ELSE
			RETURN FALSE
		END
	END;
	keys:= {};
	Input.Mouse(keys, x, y);
	IF keys#{} THEN RETURN TRUE ELSE RETURN FALSE END
END CheckKeyboard;

PROCEDURE Initcolor(P : Pictures.Picture);
(* Weist dem Picture die Farben zu *)
VAR i : INTEGER;
BEGIN
	FOR i:= 0 TO Rembrandt0.noc-1 DO
		Pictures.SetColor(P, i, Rembrandt0.coltable[i].r, Rembrandt0.coltable[i].g, Rembrandt0.coltable[i].b)
	END;
END Initcolor; 

PROCEDURE Integer(name : ARRAY OF CHAR): INTEGER;
(* Liefert aktuelle Zahl des gesuchten Modells zurück *)
VAR obj, cont : Objects.Object; 
BEGIN
	cont:= Gadgets.context; obj:= NIL;
	WHILE (cont#NIL) & (obj=NIL) DO
		obj:= Gadgets.FindObj(cont, name);
		cont:= cont.dlink;	(* Aufruf des Befehls aus einem "höheren" Panel *)
	END;
	IF obj#NIL THEN
		RETURN SHORT(obj(BasicGadgets.Integer).val)
	ELSE
		RETURN 0
	END
END Integer;

PROCEDURE Real(name : ARRAY OF CHAR): REAL;
(* Liefert aktuelle Zahl des gesuchten Modells zurück *)
VAR obj, cont : Objects.Object; 
BEGIN
	cont:= Gadgets.context; obj:= NIL;
	WHILE (cont#NIL) & (obj=NIL) DO
		obj:= Gadgets.FindObj(cont, name);
		cont:= cont.dlink;	(* Aufruf des Befehls aus einem "höheren" Panel *)
	END;
	IF obj#NIL THEN
		RETURN SHORT(obj(BasicGadgets.Real).val)
	ELSE
		RETURN 0.0
	END
END Real;

(** Initialisiert die Standardpalette *)
PROCEDURE LoadPalette*();
VAR F: Files.File;
		R: Files.Rider;
		r, g, b : CHAR; i: INTEGER;
BEGIN
	F:= Files.Old("Rembrandt0.Pal");
	Files.Set(R, F, 0);
	FOR i:= 0 TO 255 DO
		Files.Read(R, r);
		Files.Read(R, g);
		Files.Read(R, b);
		Display.SetColor(i, ORD(r), ORD(g), ORD(b));
	END;
END LoadPalette;

PROCEDURE CreatePict(VAR P: Pictures.Picture);
(* Gibt das markierte Picture zurück oder erstellt ein neues *)
(* setzt die Farben *)
VAR F: Rembrandt.Frame; 
BEGIN
	F:= RembrandtDocs.MarkedFrame();
	IF F=NIL THEN NEW(P); Pictures.Create(P, 320, 200, 8); RembrandtDocs.OpenPict(P, "Backdrop.Pict") ELSE P:= F.pict END;
	px:= P.width; py:= P.height;
	Initcolor(P);
END CreatePict;

(** Erstellt ein leeres Picture mit Hintergrundfarbe background *)
PROCEDURE EmptyPicture*();
VAR P: Pictures.Picture;
BEGIN
	LoadPalette;	(* Palette muss neu geladen werden, falls zwischendurch eine andere Palette geladen wurde *)
	CreatePict(P);
	Pictures.ReplConst(P, Rembrandt0.color.col, 0, 0, px, py, Display.replace);
	Pictures.Update(P, 0, 0, px, py)
END EmptyPicture;

(** Dithert ein markiertes Picture mit zusätzlicher Angabe der Helligkeit und Sättigung als Parameter *)
PROCEDURE Reduce*;
VAR D: Pictures.Picture;
		ds, dv, r, g, b: INTEGER;
		S: Texts.Scanner; 
		F: Rembrandt.Frame;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN ds:= SHORT(S.i) ELSE ds:=100 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN dv:= SHORT(S.i) ELSE dv:=100 END;
	F:= RembrandtDocs.MarkedFrame();
	IF F#NIL THEN
		NEW(D); Pictures.Create(D, F.pict.width, F.pict.height, F.pict.depth); 
		Rembrandt0.Reduce(F.pict, D, ds/100, dv/100); 
		ds:=0; WHILE ds<ASH(2, D.depth-1) DO Display.GetColor(ds, r, g, b); Pictures.SetColor(D, ds, r, g, b); INC(ds) END;
		RembrandtDocs.OpenPict(D, "") 
	END
END Reduce;

PROCEDURE WraplConst(P: Pictures.Picture; col, x, y, w, h: INTEGER);
(* Zeichnet ein gefülltes Rechteck im Picture modulo Höhe und Breite *)
BEGIN
	x:=x MOD px; y:= y MOD py;
	 IF (x+w<px) & (y+h<py) THEN 
		Pictures.ReplConst(P, col, x, y, w, h, Display.replace)
	ELSE
		IF x+w>=px THEN
			Pictures.ReplConst(P, col, x, y, px-x, h, Display.replace);
			Pictures.ReplConst(P, col, 0, y, x+w-px, h, Display.replace)
		END;
		IF y+h>=py THEN
			Pictures.ReplConst(P, col, x, y, w, py-h, Display.replace);
			Pictures.ReplConst(P, col, x, 0, w, y+h-py, Display.replace)
		END;
		IF (x+w>=px) & (y+h>=py) THEN		(* Spezialfall *)
			Pictures.ReplConst(P, col, 0, 0, x+w-px, y+h-py, Display.replace)
		END
	END
END WraplConst;

PROCEDURE Circle(P : Pictures.Picture; xm, ym, r, dc, fac: INTEGER; bres : BOOLEAN; dis: INTEGER);
(* Zeichnet einen Kreis mit Mittelpunkt xm, ym Radius r, Farbe dc, Schritte fac *)
VAR x, y  : INTEGER; i, step : REAL;
      d,dx,dy, h: INTEGER;
BEGIN
	IF ~bres THEN
		step:= fac/r;
		i:= 0;
		WHILE i<360 DO
			x:= SHORT(ENTIER(r*Math.sin(i*Math.pi/180)));
			y:= SHORT(ENTIER(r*Math.cos(i*Math.pi/180)));
			IF dis>1 THEN h:= -dis+SHORT(Random()) MOD (2*dis) ELSE h:=0 END;
			IF Pictures.Get(P, (xm+x+h) MOD px, (ym+y+h) MOD py) = Rembrandt0.color.col THEN
				Pictures.Dot(P, dc, (xm+x+h) MOD px, (ym+y+h) MOD py, Display.replace)
			END;
			i:= i+step
		END
	ELSE	(* Bresenham-Methode für gefüllte Kreise *)
		x := r; y := 0; d := 2*r-1; dx := 4*r; dy := 0;
		WHILE y < r DO
			WHILE d <= 0 DO DEC(x); DEC(dx,4); INC(d,dx) END;
			WraplConst(P, dc, xm-x,ym+y,2*x,1);
			INC(y); INC(dy,4); DEC(d,dy);
			WraplConst(P, dc, xm-x,ym-y,2*x,1);
		END
	END
END Circle;

PROCEDURE Ellipse(P: Pictures.Picture; a,b, xm, ym, col : INTEGER; both: BOOLEAN);
(* Zeichnet eine Ellipse mit Mittelpunkt (xm,ym), Achsen a,b und Farbe col *)
(* both=1: zeichnet ganze Ellipse *)
(* both=0: zeichnet nur die obere Hälfte *)
VAR x, y1, y2, y, i, step : REAL;
BEGIN
	i:= 0; step:= 0.5;
	WHILE i<2*a DO
		x:=-a+i;
		i:= i+step;
		y:=b*Math.sqrt(1-x*x/a/a);
		x:= x+xm; y1:= y+ym;
		Pictures.Dot(P, col, SHORT(ENTIER(x) MOD px), SHORT(ENTIER(y1) MOD py), Display.replace);
		IF both THEN
			y2:= ym-y;
			Pictures.Dot(P, col, SHORT(ENTIER(x) MOD px), SHORT(ENTIER(y2) MOD py), Display.replace)
		END
	END
END Ellipse;

PROCEDURE Spirale(P: Pictures.Picture; r0, r1, a0, a1, xm, ym, col, b : INTEGER);
(* Zeichnet eine Spirale von Radius r0 bis r1 und von Winkel a0 bis a1 um
	den Mittelpunkt (xm,ym) *)
(* b=0: einheitliche Farbe *)
(* b=1: Farbverlauf *)
VAR i, x, y : INTEGER; r, dr, coldec, cols : REAL;
BEGIN
	dr:= (r1-r0)/(a1-a0); r:=0;
	IF b=1 THEN coldec:=col/(a1-a0) ELSE coldec:=0 END;
	cols:= col*1.0-coldec;
	FOR i:= a0 TO a1 DO
		x:= SHORT(ENTIER((r0+r)*Math.sin(i*Math.pi/180)));
		y:= SHORT(ENTIER((r0+r)*Math.cos(i*Math.pi/180)));
		x:= x+xm; y:= y+ym;
		Pictures.Dot(P, SHORT(ENTIER(cols)), x MOD px, y MOD py, Display.replace);
		cols:= cols-coldec;
		IF cols<=1 THEN cols:=1 END;
		r:=r+dr;
	END
END Spirale;

(** Backdrops *)
PROCEDURE Fractal*();
(* Generiert das Backdrop Fractal *)
VAR
		endr, Inc, endi, Inr, dw, w, fr0, fi0, fr1, fi1 : REAL;
		loops , max, f, k : LONGINT;
		z, c : complex;
		ret : ptr;		(* Rueckgabe der komplexen Zahl als Pointer *)
		P : Pictures.Picture;
		S : Texts.Scanner;

	PROCEDURE complexsqrt(z: complex): ptr;
		VAR mag : REAL;
	BEGIN
		mag:= Math.sqrt(z.r*z.r+z.i*z.i);
		IF (mag+z.r) < 0 THEN ret.r:=0
		ELSE
			ret.r:= Math.sqrt((mag+z.r)/2);
		END;
		IF (mag-z.r) < 0 THEN ret.i:=0
		ELSE
			ret.i:= Math.sqrt((mag-z.r)/2);
		END;
		IF z.i<0 THEN ret.i:=-ret.i END;
		RETURN ret
	END complexsqrt;

	PROCEDURE iterate(z: complex): ptr;
	VAR help : complex;
			result : ptr;
	BEGIN
		help.r:= z.r-c.r;
		help.i:= z.i-c.i;
		result:= complexsqrt(help);
		IF (Random() MOD 2) = 0 THEN
			result.r:= -result.r; result.i:=-result.i
		END;
		RETURN result
	END iterate;

BEGIN
	CreatePict(P);
	NEW(ret);
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN loops:= SHORT(S.i) ELSE loops:= 10 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN max:= S.i ELSE max:= 10000 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN f:= S.i ELSE f:=1 END;
	fr0:= -1.1; fi0:= 0.2;
	fr1:= -0.9; fi1:= 0.9;
	fr0:= Real("fractalr0"); fi0:= Real("fractali0");
	fr1:= Real("fractalr1"); fi1:= Real("fractali1");
	c.r:= fr0; c.i:= fi0;
	endr:= fr1; endi:= fi1;
	Pictures.ReplConst(P, Rembrandt0.color.col, 0, 0, px, py, Display.replace);
	Inc:= ABS(c.r-endr)/loops;	(* Schrittweiten *)
	Inr:= ABS(c.i-endi)/loops;
	dw:= Rembrandt0.noc/loops; w:= 1;	(* Farbnummerweite *)
	z.r:= 1; z.i:= 0;
		WHILE (loops >0) & (~CheckKeyboard()) DO
			FOR k:= 1 TO 50 DO ret:=iterate(z); z.i:= ret.i; z.r:=ret.r END;	(* Anfangsiteration *)
			FOR k:= 1 TO max DO
				ret:=iterate(z); z.i:= ret.i; z.r:=ret.r;
				Pictures.Dot(P, SHORT(ENTIER(w)), SHORT(ENTIER(px*f*z.r) MOD px) ,
								SHORT(ENTIER(py*f*z.i) MOD py), Display.replace);
			END;
			w:= w+dw;
			Pictures.Update(P, 0,0, px, py);
			c.r:= c.r+Inc;
			c.i:= c.i+Inr;
			DEC(loops)
		END;
END Fractal;

PROCEDURE Initnoise();
(* Füllt das Zufallszahlenfeld *)
VAR x, y, xx, yy  : INTEGER;
BEGIN
	FOR x:= 0 TO maxnoise DO
		FOR y:= 0 TO maxnoise DO
				noisetable[x,y]:= SHORT(Random() MOD 10000);
				IF x = maxnoise THEN xx:=0 ELSE xx:=x END;
				IF y = maxnoise THEN yy:=0 ELSE yy:=y END;
				noisetable[x,y]:= noisetable[xx,yy]
		END
	END
END Initnoise;

PROCEDURE noise(x,y : REAL): REAL;
(* Berechnet mittels linearer Interpolation eine Zufallswert aus dem bestehenden Feld *)
VAR ix, iy: LONGINT;
		ox, oy: REAL;
		n : INTEGER;
		n00, n10 : REAL;
BEGIN
	x:= x+15000; y:= y+15000;   
	ix:= ENTIER(x) MOD maxnoise;
	iy:= ENTIER(y) MOD maxnoise;
	ox:= x-ENTIER(x); oy:= y-ENTIER(y); 
	n:= noisetable[ix, iy];
	n00:= n+ox*(noisetable[ix+1, iy]-n);
	n:= noisetable[ix, iy+1];
	n10:= n+ox*(noisetable[ix+1, iy+1]-n);
	RETURN (n00+oy*(n10-n00))*0.0001
END noise;

PROCEDURE Marble*();
(* Generiert das Backdrop Marble *)
VAR c, prim : INTEGER;
		konst, fac, scale : REAL;
		i,j : LONGINT;
		P : Pictures.Picture;
		S: Texts.Scanner;

	PROCEDURE marb(u,v: REAL; VAR i : REAL);
	VAR d, dd : REAL;
	BEGIN
		d:= prim*noise(u/100*scale, v/100*scale);
		dd:= ENTIER(d) MOD 17; 
		IF dd < 4 THEN i:=noise(u/100*scale, v/100*scale)
		ELSE
			IF (dd<9) OR (dd>=12) THEN
				d:= ABS(d-ENTIER(d/17)*17-10.5)*fac;
				i:= 0.4+0.3*d+0.2*noise(u/100*scale, v/100*scale);
			ELSE
				i:= 0.2+0.2*noise(u/100*scale, v/100*scale);
			END
		END;
	END marb;

BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN prim:= SHORT(S.i) ELSE prim:= 7 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN scale:= 1.0*SHORT(S.i) ELSE scale:= 16 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN fac:= S.i/1000 ELSE fac:= 0.15 END;
	IF scale>49 THEN scale:= 49 END;
	maxnoise:= SHORT(ENTIER(2*scale));
	Initnoise;
	CreatePict(P);
	FOR i:= 0 TO py DO
		FOR j:= 0 TO px DO
			marb(i*200/px, j*200/py, konst);
			c:= SHORT(ENTIER(konst*100)) DIV Rembrandt0.noc;
			Pictures.Dot(P, (c MOD Rembrandt0.noc), SHORT(j), SHORT(i), Display.replace)
		END;
		IF i MOD 4 =0 THEN
			Pictures.Update(P, 0, SHORT(i), px, 2)
		END;
		IF CheckKeyboard() THEN i:= py END;
	END;
	Pictures.Update(P, 0,0, px, py);
END Marble;

PROCEDURE turbulence(x,y: REAL): REAL;
VAR mins, t,s : REAL;
BEGIN
	t:=0; s:=1; mins:= 1/px;
	WHILE s>=mins DO
		t:=t+noise(x/s,y/s)*s; s:=s*0.5; 
	END;
	RETURN t
END turbulence;	
	
(** Dient zur Vorschau eines Backdrops *)
PROCEDURE Preview*();
CONST size=480;					(* Grösse des Pictures *)
VAR i, j, sx, sy  : INTEGER;
		P : Pictures.Picture;
		F: Rembrandt.Frame;
BEGIN
	F:= RembrandtDocs.MarkedFrame();
	IF F#NIL THEN
		NEW(P); Rembrandt0.AllocatePictureMem(P, size, size, 8);
		sy:= size DIV py; sx:=size DIV px;
		FOR i:= 0 TO sy DO
			FOR j:= 0 TO sx DO
				Pictures.CopyBlock(F.pict, P, 1,1,F.pict.width-1, F.pict.height-1,
				j*(F.pict.width-1), i*(F.pict.height-1), Display.replace)
			END
		END;
		RembrandtDocs.OpenPict(P, "Preview")
	END
END Preview;

(** Backdrops *)
PROCEDURE Textils*();
(* Generiert das Backdrop Textils *)
VAR x, y, col, j : INTEGER;
		t, m,n: REAL;
		P : Pictures.Picture;
		S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN maxnoise:= SHORT(S.i) ELSE maxnoise:= 10 END;
	CreatePict(P);
	Initnoise;
	col := 100 DIV (Rembrandt0.noc-1) +1;
	FOR y:= 0 TO py DO
		FOR x:= 0 TO px DO
			m:=x; n:=y; m:= m*maxnoise/px; n:= n*maxnoise/py;
			 t:= turbulence(m,n); 
			j:= SHORT(ENTIER((t-0.05)*60) DIV col) MOD Rembrandt0.noc;
			Pictures.Dot(P, j, x , y , Display.replace)
		END;
		IF y MOD 4 =0 THEN Pictures.Update(P, 0, y, px, 2) END;
		IF CheckKeyboard() THEN y:=py END;
	END;
	Pictures.Update(P, 0,0, px, py);
END Textils;

PROCEDURE Clouds*();
(* Generiert das Backdrop Clouds *)
CONST kor=24;
VAR array, update : INTEGER;
		j, loop  : LONGINT;
		dir, i,  k : INTEGER;
		P : Pictures.Picture;
		S: Texts.Scanner;
		x, y : ARRAY 50 OF INTEGER;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN array:= SHORT(S.i) ELSE array:= 15 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN loop:= S.i ELSE loop:= 10000 END;
	CreatePict(P);
	IF array>49 THEN array:= 49 END;
	Pictures.ReplConst(P, 1, 0,0, px, py, Display.replace);
	Pictures.Update(P, 0,0, px, py);
	(* Zentren initialisieren *)
	FOR i:= 1 TO array DO
		x[i]:= SHORT(Random() MOD px);
		y[i]:= SHORT(Random() MOD py);
		Pictures.Dot(P, 2, x[i],y[i], Display.replace);
		Pictures.Dot(P, 2, x[i]+1,y[i], Display.replace);
		Pictures.Dot(P, 2, x[i]-1,y[i], Display.replace);
		Pictures.Dot(P, 2, x[i],y[i]-1, Display.replace);
		Pictures.Dot(P, 2, x[i],y[i]+1, Display.replace);
		Pictures.Dot(P, 2, x[i]-1,y[i]-1, Display.replace);
		Pictures.Dot(P, 2, x[i]+1,y[i]-1, Display.replace);
		Pictures.Dot(P, 2, x[i]+1,y[i]+1, Display.replace);
		Pictures.Dot(P, 2, x[i]-1,y[i]+1, Display.replace);
	END;
	j:=0; update:= SHORT(loop DIV 100);
	(* Wachstumsphase *)
	WHILE (j< loop) & (~CheckKeyboard()) DO
		FOR i:= 1 TO array DO
			dir:= SHORT(Random() MOD kor);
			CASE dir OF
				0: y[i]:=y[i]+1;	
			  |1: x[i]:=x[i]+1;
			  |2: y[i]:=y[i]-1;	
			  |3: x[i]:=x[i]-1;	
			  |4: x[i]:=x[i]+1; y[i]:=y[i]+1
	  		|5: x[i]:=x[i]+1; y[i]:=y[i]-1;	
			  |6: x[i]:=x[i]-1; y[i]:=y[i]-1;
			  |7: x[i]:=x[i]-1; y[i]:=y[i]+1;
			  |8..16: x[i]:=x[i]-1;	
			  |17..24: x[i]:=x[i]+1;	
			END;
			k:=0;
			IF Pictures.Get(P, x[i] MOD px, (y[i]+1) MOD py) # 1 THEN INC(k) END;
			IF Pictures.Get(P, (x[i]+1) MOD px, y[i] MOD py) # 1 THEN INC(k) END;
			IF Pictures.Get(P, x[i] MOD px, (y[i]-1) MOD py) # 1 THEN INC(k) END;
			IF Pictures.Get(P, (x[i]-1) MOD px, y[i] MOD py) # 1 THEN INC(k) END;
			IF Pictures.Get(P, (x[i]+1) MOD px, (y[i]+1) MOD py) # 1 THEN INC(k) END;
			IF Pictures.Get(P, (x[i]+1) MOD px, (y[i]-1) MOD py) # 1 THEN INC(k) END;
			IF Pictures.Get(P, (x[i]-1) MOD px, (y[i]-1) MOD py) # 1 THEN INC(k) END;
			IF Pictures.Get(P, (x[i]-1) MOD px, (y[i]+1) MOD py) # 1 THEN INC(k) END;
			CASE k OF
			   0, 1 : Pictures.Dot(P, 1, x[i] MOD px, y[i] MOD py, Display.replace)
			| 2, 3 : Pictures.Dot(P, 2, x[i] MOD px, y[i] MOD py, Display.replace)
			| 4, 5 : Pictures.Dot(P, 3, x[i] MOD px, y[i] MOD py, Display.replace)
			| 6, 7 : Pictures.Dot(P, 4, x[i] MOD px, y[i] MOD py, Display.replace)
			| 8 :	 Pictures.Dot(P, 5, x[i] MOD px, y[i] MOD py, Display.replace)
			END
		END;
		IF j MOD update =0 THEN
			Pictures.Update(P, 0,0, px, py)
		END;
		INC(j)
	END;
	Pictures.Update(P, 0,0, px, py)
END Clouds;

PROCEDURE Molecules*();
(* Generiert das Backdrop Molecules *)
VAR x, y, r,t, size, dif, dis : INTEGER;
		frac, col : REAL;
		P : Pictures.Picture;
		S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN size:= SHORT(S.i) ELSE size:= 20 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN dif:= SHORT(S.i) ELSE dif:= 30 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN dis:= SHORT(S.i) ELSE dis:=1 END;
	CreatePict(P);
	y:=SHORT(Random() MOD dif);
	WHILE (y<py) & (~CheckKeyboard()) DO
		x:= SHORT(Random() MOD dif);
		WHILE x<px DO
			x:=x+ SHORT(Random() MOD dif);
			r:= SHORT(Random() MOD size)+1;
			t:= y+SHORT(Random() MOD size);
			frac:= (Rembrandt0.noc-1)*1.0; frac:=frac/r; col:= frac;
			WHILE r>0 DO
				Circle(P, x, t, r, SHORT(ENTIER(col)), 20, FALSE, dis);
				col:=col+frac;
				DEC(r)
			END
		END;
		y:=y+ SHORT(Random() MOD dif);
		Pictures.Update(P, 0,0, px, py)
	END
END Molecules;

PROCEDURE Threads*();
(* Generiert das Backdrop Threads *)
VAR P : Pictures.Picture;
		S: Texts.Scanner;
		x, y, num, j,  i, long, nbr, dir : INTEGER;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN nbr:= SHORT(S.i) ELSE nbr:= 50 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN long:= SHORT(S.i) ELSE long:= 1000 END;
	CreatePict(P); 
	FOR i:= 1 TO nbr DO
		j:=0; 
		dir:= SHORT(Random() MOD 4);
		x:= SHORT(Random() MOD P.width);
		y:= SHORT(Random() MOD P.height); 
		WHILE j < long DO
			num:= dir*2+SHORT(Random() MOD 3); 
			CASE num OF
				0: x:=x+1; y:=y+1; 
			 | 1: x:=x+1;
			 | 2: x:=x+1; y:=y-1; 
			 | 3: y:=y-1;
			 | 4: x:=x-1; y:=y-1; 
			 | 5:  x:=x-1;
			 | 6: x:=x-1; y:=y+1;  
	 		| 7: y:=y+1;
			 | 8: x:=x+1; y:=y+1; 
			END;
			Pictures.Dot(P, i MOD (Rembrandt0.noc-1) +1, x MOD P.width, y MOD P.height, Display.replace);
			INC(j)
		END;
		Pictures.Update(P, 0,0, px, py);
		IF CheckKeyboard() THEN i:=nbr END;
	END
END Threads;

PROCEDURE Damage(P: Pictures.Picture; col, dx, dy, x,y,w,h: INTEGER);
(* Generiert die Defekte zum Backdrop Bricks *)
VAR n, fgd, bgd: INTEGER;
BEGIN
	n:= SHORT(Random() MOD 20)+1;
	fgd:= col-2; IF fgd<=0 THEN fgd:=1 END;
	bgd:= col+2; IF bgd>=Rembrandt0.noc THEN bgd:=Rembrandt0.noc-1 END;
	WHILE n>0 DO
		IF (dx>=0) & (dy>=0) & (dx+1<=w) & (dy+1<=h) THEN
			WraplConst(P, bgd, x+dx+1, y+dy-1, 1, 1);
			WraplConst(P, fgd, x+dx, y+dy, 1, 1);
		END;
		INC(dx, SHORT(Random() MOD 3)-1);
		INC(dy, SHORT(Random() MOD 3)-1);
		DEC(n)
	END
END Damage;

PROCEDURE Brick(P: Pictures.Picture; col, dam, x,y,w,h: INTEGER);
VAR fgd, bgd : INTEGER; n : LONGINT;
BEGIN
	WraplConst(P, col,x,y,w,h);
	fgd:= col-2; IF fgd<=0 THEN fgd:=1 END;
	bgd:= col+2; IF bgd>=Rembrandt0.noc THEN bgd:=Rembrandt0.noc-1 END;
	WraplConst(P, fgd, x-1, y-1, w+2, 1);
	WraplConst(P, bgd, x-1, y-1, 1, h+2);
	WraplConst(P, bgd, x-1, y+h, w+2, 1);
	WraplConst(P, fgd, x+w, y-1, 1, h+2);
	n:= Random() MOD (dam+1);
	WHILE n>0 DO
		Damage(P, col, SHORT(Random() MOD w), SHORT(Random() MOD h),
						x,y,w,h);
		DEC(n)
	END; 
END Brick;

PROCEDURE Bricks*();
(* Generiert das Backdrop Bricks *)
VAR P : Pictures.Picture;
		i,x,y,w,h, dam, loop, col, maxw, maxd : INTEGER;
BEGIN
	loop:= Integer("brian");
	dam:= Integer("bride");
	maxw:= Integer("bribr");
	maxd:=Integer("briho");
	IF maxw>px-8 THEN maxw:= px-8 END;
	IF maxd>py-4 THEN maxd:= py-4 END;
	CreatePict(P);
	i:=0;
	WHILE (i<loop) & (~CheckKeyboard()) DO
		col:= SHORT(Random() MOD (Rembrandt0.noc-4))+3;
		x:= SHORT(Random() MOD px); y:= SHORT(Random() MOD py);
		w:= SHORT(Random() MOD maxw)+8;
		h:= SHORT(Random() MOD maxd)+4;
		Brick(P, col, dam, x, y, w, h);
		Pictures.Update(P,0,0, px, py);
		INC(i)
	END
END Bricks;

PROCEDURE Surface*();
(* Generiert das Backdrop Surface *)
VAR P : Pictures.Picture;
		S: Texts.Scanner;
		rnd, t, fgd, bgd, he, dx, dy, update : INTEGER;
		n, loop : LONGINT;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN loop:=S.i ELSE loop:= 1000 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN rnd:=SHORT(S.i) ELSE rnd:= 25 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN t:=SHORT(S.i) ELSE t:= 1 END;
	Texts.Scan(S);
	CreatePict(P);
	update:= 2500 DIV rnd;
	Pictures.ReplConst(P, (Rembrandt0.noc DIV 2), 0, 0, px, py, Display.replace);	
	WHILE (loop>0) & (~CheckKeyboard()) DO
		n:= SHORT(Random() MOD rnd)+1;
		fgd:= (Rembrandt0.noc DIV 2)-2; IF fgd<=0 THEN fgd:=1 END;
		bgd:= (Rembrandt0.noc DIV 2)+2; IF bgd>=Rembrandt0.noc THEN bgd:=Rembrandt0.noc-1 END;
		dx:= SHORT(Random() MOD px);
		dy:= SHORT(Random() MOD py);
		WHILE n>0 DO
			he:= 1+SHORT(Random() MOD t);
			dx:= dx MOD px; dy:=dy MOD py;
			WraplConst(P, bgd, (dx+2*he) MOD px, (dy-2*he) MOD py, he, 2*he);
			WraplConst(P, bgd, (dx+he) MOD px, (dy-2*he) MOD py, he, he);
			WraplConst(P, bgd-1, (dx+2*he) MOD px, dy, he, he);
			WraplConst(P, bgd-1, dx, (dy-2*he) MOD py, he, he);
			WraplConst(P, bgd-1, (dx+he) MOD px, (dy-he) MOD py, he, he);
			WraplConst(P, fgd, dx, dy, 2*he, he);
			WraplConst(P, fgd, dx, (dy-he) MOD py, he, he);
			INC(dx, SHORT(Random() MOD 3)-1);
			INC(dy, SHORT(Random() MOD 3)-1);
			DEC(n)
		END;
		IF loop MOD update =0 THEN Pictures.Update(P,0,0, px, py) END;
		DEC(loop)
	END; 
	Pictures.Update(P,0,0, px, py)
END Surface;

PROCEDURE Plasma*();
(* Generiert das Backdrop Plasma *)
VAR P : Pictures.Picture;
		S: Texts.Scanner;
		x, y, num, j, k , oldnum, long, nbr : INTEGER;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN nbr:= SHORT(S.i) ELSE nbr:= 10 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN long:= SHORT(S.i) ELSE long:= 10000 END;
	CreatePict(P); num := 0;
	FOR k:= 1 TO nbr DO
		x:= SHORT(Random() MOD px);
		y:= SHORT(Random() MOD py); 
		FOR j:= 1 TO long DO
			oldnum:= num;
			REPEAT
				num:= SHORT(Random() MOD 8)
			UNTIL (oldnum#num) & (ABS(oldnum-num)#1);
			CASE num OF
				0: y:=y+1;
			 | 1: y:=y-1;
			 | 2: x:=x+1;
			 | 3:  x:=x-1;
			 | 4: x:=x+1; y:=y+1;
			 | 5: x:=x-1; y:=y-1;
			 | 6: x:=x-1; y:=y+1;
			 | 7: x:=x+1; y:=y-1;
			END;
			Pictures.Dot(P, k MOD Rembrandt0.noc, x MOD px, y MOD py, Display.replace);
		END;	
		Pictures.Update(P, 0,0, px, py);
		IF CheckKeyboard() THEN k:= nbr END
	END;
	Pictures.Update(P, 0,0, px, py)
END Plasma;

PROCEDURE Coins*();
(* Generiert das Backdrop Coins *)
VAR P : Pictures.Picture;
		S: Texts.Scanner;
		x, y, r, nbr, loop, j  : INTEGER;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN loop:= SHORT(S.i) ELSE loop:= 100 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN nbr:= SHORT(S.i) ELSE nbr:= 30 END;
	CreatePict(P);
	FOR j:= 1 TO loop DO
		x:= SHORT(Random() MOD px);
		y:= SHORT(Random() MOD py);
		r:= SHORT(Random() MOD nbr);
		Circle(P, x, y, r, SHORT(Random() MOD (Rembrandt0.noc-1))+1, 20, TRUE, 1);
		IF j MOD 20 =0 THEN Pictures.Update(P, 0,0, px, py) END;
		IF CheckKeyboard() THEN j:= loop END;
	END;
	Pictures.Update(P, 0,0, px, py)
END Coins;

PROCEDURE Bows*();
(* Generiert das Backdrop Bows *)
VAR P : Pictures.Picture;
		S: Texts.Scanner;
		col, i, j, nbr, loop, x, y, a, b, dick: INTEGER;
		ud : LONGINT;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN loop:= SHORT(S.i) ELSE loop:= 100 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN nbr:= SHORT(S.i) ELSE nbr:= 30 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN dick:= SHORT(S.i) ELSE dick:= Rembrandt0.noc END;
	CreatePict(P);
	ud:= loop; ud:= (ud*nbr) DIV 1000;	(* Update des Pictures *)
	IF ud<10 THEN ud:= 10 END;
	FOR j:= 1 TO loop DO
		x:= SHORT(Random() MOD px);
		y:= SHORT(Random() MOD py);
		a:= SHORT(Random() MOD nbr)+3;
		b:= SHORT(Random() MOD nbr)+3;
		col:=  SHORT(Random() MOD (Rembrandt0.noc-2))+2;
		FOR i:= 1 TO dick DO
			IF col<=1 THEN col:=1 END;
			Ellipse(P, a,b-i+1, x, y, col, FALSE);
			DEC(col);
		END;
		IF j MOD ud=0 THEN Pictures.Update(P, 0,0, px, py) END;
		IF CheckKeyboard() THEN j:= loop END
	END;
	Pictures.Update(P, 0,0, px, py)
END Bows;

PROCEDURE Spirals*();
(* Generiert das Backdrop Spir *)
VAR P : Pictures.Picture;
		col, i, j,  loop, x, y, rad, bool, diff: INTEGER;
		rounds : REAL;
BEGIN
	loop:= Integer("spian");
	rad:= Integer("spira");
	rounds:= Integer("spium")/10;
	diff:= Integer("spili");
	bool:= Integer("spifa");
	CreatePict(P);
	FOR j:= 1 TO loop DO
		x:= SHORT(Random() MOD px);
		y:= SHORT(Random() MOD py);
		col:=  SHORT(Random() MOD (Rembrandt0.noc-3*bool+1))+3*bool+1;
		FOR i:=0 TO diff-1 DO
			Spirale(P, 0, rad, i*(360 DIV diff), SHORT(ENTIER(rounds*360)), x, y, col, bool);
		END;
		IF j MOD 10=0 THEN Pictures.Update(P, 0,0, px, py) END;
		IF CheckKeyboard() THEN j:= loop END
	END;
	Pictures.Update(P, 0,0, px, py)
END Spirals;

PROCEDURE Tree(P: Pictures.Picture; x,y, dir, col, count,max, len : INTEGER);
(* Rekursion für Tree *)
VAR num, red : INTEGER; i: LONGINT;
BEGIN
	IF count<max THEN
		red:=count*(len DIV (max+1));
		FOR i:= 1 TO (Random() MOD (len-red) + 5) DO
			num:= dir;
			num:= (num+SHORT(Random() MOD 3)) MOD 8;
			CASE num OF
				0: x:=x+1; y:=y+1; 
			 | 1: x:=x+1;
			 | 2: x:=x+1; y:=y-1; 
			 | 3: y:=y-1;;
			 | 4: x:=x-1; y:=y-1; 
			 | 5: x:=x-1;
			 | 6: x:=x-1; y:=y+1;  
		 	| 7: y:=y+1;
			 | 8: x:=x+1; y:=y+1; 
			END;
			Pictures.Dot(P, col, x MOD px, y MOD py, Display.replace)
		END;
		IF col+1>Rembrandt0.noc THEN col:=Rembrandt0.noc-1 END;
		Tree(P, x,y, dir, col+1, count+1, max, len);
		Tree(P, x,y, (dir+1) MOD 8, col+1, count+1, max, len);
		IF dir -1<0 THEN dir:=8 END;
		Tree(P, x,y, dir-1, col+1, count+1, max, len)
	END;
	IF count<max-2 THEN Pictures.Update(P, 0,0, px, py) END
END Tree;

PROCEDURE Trees*();
(* Generiert das Backdrop Trees *)
VAR P : Pictures.Picture;
		S: Texts.Scanner;
		i,  loop, x, y, max, len, start: INTEGER;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN loop:= SHORT(S.i) ELSE loop:= 1 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN len:= SHORT(S.i) ELSE len:= 60 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN max:= SHORT(S.i) ELSE max:= 6 END;
	CreatePict(P);
	FOR i:= 1 TO loop DO
		x:= SHORT(Random() MOD px);
		y:= SHORT(Random() MOD py);
		start:= Rembrandt0.noc-max;
		IF start<1 THEN start:= 1 ELSE start:= start DIV 2 END;
		Tree(P, x,y,6, start, 0, max, len);
		IF ~CheckKeyboard() THEN
			Tree(P, x,y,2, start, 0, max, len)
		END;
		IF ~CheckKeyboard() THEN
			Tree(P, x,y,4, start, 0, max, len)
		END;
		IF ~CheckKeyboard() THEN
			Tree(P, x,y, 0, start, 0, max, len)
		END;
		Pictures.Update(P, 0,0, px, py);
		IF CheckKeyboard() THEN i:= loop END
	END;
END Trees;

PROCEDURE Cells*();
(* Generiert das Backdrop Cells *)
VAR P : Pictures.Picture;
		S: Texts.Scanner;
		x, y : ARRAY 500 OF INTEGER;
		i, r, loop, mloop, size  : INTEGER;
		dc, incdc : REAL;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN loop:= SHORT(S.i) ELSE loop:= 10 END;
	Texts.Scan(S);
	IF S.class = Texts.Int THEN size:= SHORT(S.i) ELSE size:= 10 END;
	IF size>200 THEN size:= 200 END;
	CreatePict(P); mloop:= loop-1;
	FOR i:= 0 TO mloop DO
		x[i]:= SHORT(Random() MOD px);
		y[i]:= SHORT(Random() MOD py)
	END; 
	dc:= Rembrandt0.noc/size;
	incdc:= Rembrandt0.noc-1;
	r:= 1;
	WHILE (r <= size) & (~CheckKeyboard()) DO
		FOR i:= 0 TO mloop DO
			Circle(P, x[i], y[i], r, SHORT(ENTIER(incdc)), 20, FALSE, 1)
		END;
		INC(r); incdc:= incdc-dc;
		IF incdc<1 THEN incdc:= 1 END;
		Pictures.Update(P, 0,0, px, py)
	END
END Cells;


BEGIN
	Out.String("Backdrops, DP 24.2.94");
	Out.Ln;
	seed := Oberon.Time();
	Rembrandt0.color.col:=0;
	r0:= 0; g0:= 25; b0:= 0;
	r1:= 0; g1:= 255; b1:= 0;
	LoadPalette;
END Backdrops.

		Backdrops.Preview
		Backdrops.Fractal 10 10000 
		Backdrops.Marble 23 20.0 0.11113
						   prim scale factor
		Backdrops.EmptyPicture
		Backdrops.Textils 22 0.3
		Backdrops.Clouds  20 10000 
		Backdrops.Molecules 30 30 14
		Backdrops.Threads 1500 50
		Backdrops.Plasma 63 20000
		Backdrops.Bricks 20 55 10 10
		Backdrops.Surface 1500 125 4~						
		Backdrops.Spirals 10.0 1 150 5 1
		Backdrops.Coins 1000 10
		Backdrops.Trees 2 200 5
		Backdrops.Bows 100 50 50
		Backdrops.Cells 200 32
