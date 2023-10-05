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

MODULE Rembrandt0;	(** portable *)

(** Dieses Modul enthält div. Prozeduren für den Rembrandt-Editor und Farboperationen, die auch in weiteren
	Modulen gebraucht werden können. Einige Prozeduren und Variablen sind aus dem Backdrops-Modul übernommen
	worden, da dieses Modul nun auch auf Rembrandt basiert *)

(*
	jt 7.11.95 - Fixed InitCross
*)

IMPORT
	Oberon, Display, Strings, Gadgets, Texts, Pictures, Objects, D3:= Display3, Out, Files, Math;

TYPE
	ColFrame*= POINTER TO ColFrameDesc;
	ColFrameDesc* = RECORD (Gadgets.FrameDesc)
		 col*: INTEGER; 	(* für Version 1.6 *)
									END;

	Color*= POINTER TO ColorDesc;
	ColorDesc* = RECORD (Gadgets.ObjDesc)
		col*: INTEGER
	END;

CONST
	max= 256;

VAR
	Z: LONGINT;
	color*: Color;							(** Aktuelle Farbe für Rembrandt-Editor *)
	noc*, maxnoc* : INTEGER;		(** Anzahl Farben für Backdrops / Maximale Anzahl Farben auf Bildschirm verfügbar *)
	coltable*: ARRAY max OF RECORD r*, g*, b*: INTEGER END;	(** Farbpalette für Backdrops *)

	(* floyd *)
	r, g, b, rpal, gpal, bpal: ARRAY 256 OF INTEGER;
	floyd: POINTER TO RECORD
		errr, errg, errb,clamp: ARRAY 1024 OF LONGINT;
		hash: ARRAY 16, 16, 16 OF CHAR
	END;

(** Zufallszahl **)
PROCEDURE Uniform*(): REAL;
CONST a = 16807; m = 2147483647; q = m DIV a; r = m MOD a;
VAR g: LONGINT;
BEGIN
	g := a*(Z MOD q) - r*(Z DIV q);
	IF g > 0 THEN Z := g ELSE Z := g + m END;
	RETURN Z*(1.0/m)
END Uniform;

PROCEDURE InitSeed*(seed: LONGINT);
BEGIN
	Z := seed
END InitSeed;

(** Dither **)

PROCEDURE InitFloyd;
VAR i, j, k, col: INTEGER; r, g, b: LONGINT;

	PROCEDURE CApprox(r, g, b: LONGINT; VAR col: INTEGER; VAR nr, ng, nb: LONGINT);
	VAR d, t, min: LONGINT; i: INTEGER;
	BEGIN
		min := MAX(LONGINT);
		i := 0;
		WHILE i < ASH(1,Pictures.colorD) DO 
			t := (r - rpal[i]); d := t * t;
			t := (g - gpal[i]); INC(d, t * t);
			t := (b - bpal[i]); INC(d, t * t);
			IF ABS(d) < min THEN min := ABS(d); col := i; nr := rpal[i]; ng := gpal[i]; nb := bpal[i]; END;
			INC(i)
		END;
	END CApprox;

BEGIN
	NEW(floyd);
	i := 0;
	WHILE i < ASH(1,Pictures.colorD) DO
		Display.GetColor(i, rpal[i], gpal[i], bpal[i]); 
		INC(i);
	END;
	i := -512;
	WHILE i < 512 DO
		IF i < 0 THEN floyd.clamp[i + 512] := 0
		ELSIF i > 255 THEN floyd.clamp[i + 512] := 255
		ELSE floyd.clamp[i + 512] := i
		END;
		INC(i)
	END;
	i := 0;
	WHILE i < 16 DO
		j := 0;
		WHILE j < 16 DO
			k := 0;
			WHILE k < 16 DO
				CApprox(i * 16, j * 16, k * 16, col, r, g, b);
				floyd.hash[i, j, k] := CHR(col);
				INC(k);
			END;
			INC(j)
		END;
		INC(i)
	END;
END InitFloyd;

PROCEDURE Floyd*(S, D: Pictures.Picture);
VAR  i, i2,  j,  dcol, col: INTEGER; 
	rcol, gcol, bcol, restim, gestim, bestim: LONGINT; 
	err, er0, er1, er4, eg0, eg1, eg4, eb0, eb1, eb4: LONGINT;
BEGIN

	IF floyd = NIL THEN InitFloyd END;
	i := 0;
	WHILE i < 1024 DO
		floyd.errr[i] := 0; floyd.errg[i] := 0; floyd.errb[i] := 0; 
		INC(i)
	END;
	i := 0;
	WHILE i < ASH(1, S.depth) DO
		Pictures.GetColor(S, i, r[i], g[i], b[i]);
		INC(i);
	END;

	j := 0;
	WHILE j < S.height DO
		i := 0;
		er0 := 0; er1 := 0; er4 := 0; eg0 := 0; eg1 := 0; eg4 := 0; eb0 := 0; eb1 := 0; eb4 := 0; i2 := 0;
		WHILE i < S.width DO
			INC(i2);
			col := Pictures.Get(S, i, j);
			rcol := floyd.clamp[r[col] + floyd.errr[i2] + er4 + 512];
			gcol := floyd.clamp[g[col] + floyd.errg[i2] + eg4 + 512]; 
			bcol := floyd.clamp[b[col] + floyd.errb[i2] + eb4 + 512]; 
			floyd.errr[i2] := 0; floyd.errg[i2] := 0; floyd.errb[i2] := 0; 
			
			dcol := ORD(floyd.hash[rcol DIV 16, gcol DIV 16, bcol DIV 16]);
			restim := rpal[dcol]; gestim := gpal[dcol]; bestim := bpal[dcol];
			
			err := rcol - restim;
			floyd.errr[i] := err * 3 DIV 16 + er0; (* 3 *)
			er0 := err * 5 DIV 16 + er1; (* 5 *)
			er1 := err DIV 16;
			er4 := err * 7 DIV 16; (* 7 *)
			
			err := gcol - gestim;
			floyd.errg[i] := err * 3 DIV 16 + eg0; 
			eg0 :=  err * 5 DIV 16 + eg1;
			eg1 := err DIV 16;
			eg4 := err * 7 DIV 16;

			err := bcol - bestim;
			floyd.errb[i] := err * 3 DIV 16 + eb0; 
			eb0 := err * 5 DIV 16 + eb1;
			eb1 := err DIV 16;
			eb4 := err * 7 DIV 16;

			Pictures.Dot(D, dcol, i, j, Display.replace);
			INC(i);
		END;
		INC(j)
	END;
END Floyd;

PROCEDURE RGBtoHSV(R, G, B: REAL; VAR H, S, V: REAL);
(* Wandelt RGB-Werte in HSV-Werte um *)
CONST	undef = 361;
VAR
	maxVal, minVal, diff, Rdist, Gdist, Bdist: REAL;

	PROCEDURE maxOf(R, G, B: REAL): REAL;
	VAR	max: REAL;
	BEGIN
		IF R > G THEN max := R ELSE max := G END;
		IF B > max THEN RETURN B ELSE RETURN max END;
	END maxOf;

	PROCEDURE minOf(R, G, B: REAL): REAL;
	VAR	min: REAL;
	BEGIN
		IF R < G THEN min := R ELSE min := G END;
		IF B < min THEN RETURN B ELSE RETURN min END
	END minOf;

BEGIN
	maxVal := maxOf(R, G, B);
	minVal := minOf(R, G, B);
	diff := maxVal - minVal;
	V := maxVal;
	IF maxVal # 0 THEN S := diff/maxVal ELSE S := 0 END;
	IF  S = 0 THEN H := undef
	ELSE
		Rdist := (maxVal - R)/diff;
		Gdist := (maxVal - G)/diff;
		Bdist := (maxVal - B)/diff;
		IF R = maxVal THEN H := Bdist - Gdist
		ELSIF G = maxVal THEN H := 2 + Rdist - Bdist
		ELSIF B = maxVal THEN H := 4 + Gdist - Rdist
		END;
		H := H*60;
		IF H < 0 THEN H := H + 360 END
	END
END RGBtoHSV;

PROCEDURE HSVtoRGB(H, S, V: REAL; VAR R, G, B: REAL);
(* Wandelt HSV-Wrte in RGB-Wrte um *)
VAR f, p, q, t: REAL;
		i: LONGINT;
BEGIN
	IF S = 0 THEN R := V; G := V; B := V
	ELSE
		IF H = 360 THEN H := 0 END;
		H := H/60;
		i := ENTIER(H);
		f := H - i;
		p := V*(1 - S);
		q := V*(1 - (S*f));
		t := V*(1 - S*(1-f));
		CASE i OF
			0: R := V; G := t; B := p
		| 1: R := q; G := V; B := p
		| 2: R := p; G := V; B := t
		| 3: R := p; G := q; B := V
		| 4: R := t; G := p; B := V
		| 5: R := V; G := p; B := q
		END
	END
END HSVtoRGB;

(** Verändert die Farben eines Pictures mit den gegebenen Parameter *)
PROCEDURE Reduce*(S, D: Pictures.Picture; ds, dv: REAL);
VAR rr, gr, br, hr, sr, vr  : REAL;
		i, r, g, b, maxc, h : INTEGER;
		P: Pictures.Picture;
BEGIN
	IF S#NIL THEN
		NEW(P); Pictures.Create(P, S.width, S.height, S.depth);
		Pictures.CopyBlock(S, P, 0, 0, S.width, S.height, 0, 0, Display.replace);
		maxc:= SHORT(ASH(2, S.depth-1));
		FOR i:= 0 TO maxc-1 DO
			Pictures.GetColor(S, i, r, g, b);
			IF dv<1 THEN
				rr:= r*1.0; gr:= g*1.0; 	br:= b*1.0;
				RGBtoHSV(rr, gr, br, hr, sr, vr);
				sr:= sr*dv;
				IF sr>255 THEN sr:=255;
				ELSIF sr<0 THEN sr:=0
				END;
				HSVtoRGB(hr, sr, vr, rr, gr, br); 
				r:= SHORT(ENTIER(rr));
				g:= SHORT(ENTIER(gr));
				b:= SHORT(ENTIER(br));
			END;
			IF ds>1 THEN	(* heller *)
				h:= SHORT(ENTIER(256/(r/128+1)*(ds-1))+1);
				r:= r+h;
				h:= SHORT(ENTIER(256/(g/128+1)*(ds-1))+1);
				g:= g+h;
				h:= SHORT(ENTIER(256/(b/128+1)*(ds-1))+1);
				b:= b+h
			ELSIF ds<1 THEN	(* dunkler *)
				h:= SHORT(ENTIER((256-r/2)/256*r*(1-ds))+1);
				r:= r-h;
				h:= SHORT(ENTIER((256-g/2)/256*g*(1-ds))+1);
				g:= g-h;
				h:= SHORT(ENTIER((256-b/2)/256*b*(1-ds))+1);
				b:= b-h
			ELSE
			END;
			IF r>255 THEN r:= 255 ELSIF r<0 THEN r:=0 END;
			IF g>255 THEN g:= 255 ELSIF g<0 THEN g:=0 END;
			IF b>255 THEN b:= 255 ELSIF b<0 THEN b:=0 END;
			Pictures.SetColor(P, i, r, g, b);
		END;
		Floyd(P, D);
		i:= 0; WHILE i<ASH(2, S.depth-1) DO Display.GetColor(i, r, g, b); Pictures.SetColor(D, i, r, g, b); INC(i) END
	END   
END Reduce;

(** Colorgadgets für Farbanzeige im Rembrandt-Panel **)
PROCEDURE HandleColor* (obj: Objects.Object; VAR M: Objects.ObjMsg);
VAR red, green, blue: INTEGER;
BEGIN
	WITH obj: Color DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN
                      M.class := Objects.String; COPY("Rembrandt0.NewColorObj", M.s); M.res := 0
                    ELSIF M.name = "col" THEN M.class := Objects.Int; M.i := obj.col; M.res := 0
					ELSIF M.name = "red" THEN Display.GetColor(obj.col, red, green, blue);
                      M.class := Objects.Int; M.i := red; M.res := 0
					ELSIF M.name = "green" THEN Display.GetColor(obj.col, red, green, blue);
                      M.class := Objects.Int; M.i := green; M.res := 0
					ELSIF M.name = "blue" THEN Display.GetColor(obj.col, red, green, blue);
                      M.class := Objects.Int; M.i := blue; M.res := 0
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.set THEN
                    IF M.name = "col" THEN obj.col := SHORT(M.i); M.res := 0
					ELSIF M.name = "red" THEN
                      IF M.class = Objects.String THEN Strings.StrToInt(M.s, M.i) END;
                      Display.GetColor(obj.col, red, green, blue);
                      Display.SetColor(obj.col, SHORT(M.i), green, blue); M.res := 0
					ELSIF M.name = "green" THEN;
                      IF M.class = Objects.String THEN Strings.StrToInt(M.s, M.i) END;
                      Display.GetColor(obj.col, red, green, blue);
                      Display.SetColor(obj.col, red, SHORT(M.i), blue); M.res := 0
					ELSIF M.name = "blue" THEN
                      IF M.class = Objects.String THEN Strings.StrToInt(M.s, M.i) END;
                      Display.GetColor(obj.col, red, green, blue);
                      Display.SetColor(obj.col, red, green, SHORT(M.i)); M.res := 0
					ELSE Gadgets.objecthandle(obj, M)
					END
				ELSIF M.id = Objects.enum THEN
					M.Enum("col"); M.Enum("red"); M.Enum("green"); M.Enum("blue");
					Gadgets.objecthandle(obj, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN M(Objects.CopyMsg).obj := obj	(* this object must not be copied *)
		ELSE Gadgets.objecthandle(obj, M)
		END
	END
END HandleColor;

PROCEDURE NewColorObj*;
BEGIN
	Objects.NewObj := color
END NewColorObj;

PROCEDURE HandleColFrame*(F: Objects.Object; VAR M: Objects.ObjMsg);
  VAR x, y: INTEGER; Q: D3.Mask; F1: ColFrame;
BEGIN
  WITH F: ColFrame DO
	IF M IS Display.DisplayMsg THEN
		WITH M: Display.DisplayMsg DO
			IF (M.device = Display.screen) & ((M.F = NIL) OR (M.F = F)) THEN (* message addressed to box *)
				x := M.x + F.X; y := M.y + F.Y;
				Gadgets.MakeMask(F, x, y, M.dlink, Q); D3.ReplConst(Q, color.col, x, y, F.W, F.H, Display.replace); 
			ELSE
				Gadgets.framehandle(F, M)
			END
		END
	ELSIF M IS Gadgets.UpdateMsg THEN
		WITH M: Gadgets.UpdateMsg DO
			IF M.obj=F.obj THEN
				x := M.x + F.X; y := M.y + F.Y;
  	           Gadgets.MakeMask(F, x, y, M.dlink, Q); D3.ReplConst(Q, color.col, x, y, F.W, F.H, Display.replace)
			ELSE
				Gadgets.framehandle(F, M)
			END
		END
	ELSIF M IS Objects.AttrMsg THEN
		WITH M: Objects.AttrMsg DO
 		 IF M.id = Objects.get THEN
  		  IF M.name = "Gen" THEN
   		   M.class := Objects.String; COPY("Rembrandt0.NewColFrame", M.s); M.res := 0
  		  ELSIF M.name = "Color" THEN
  		    M.class := Objects.Int; M.i := F.col; M.res := 0 
  		  ELSE Gadgets.framehandle(F, M)
 		   END
		  ELSIF M.id = Objects.set THEN
  		  IF M.name = "Color" THEN
   		   IF M.class = Objects.Int THEN
    		    F.col := SHORT(M.i); M.res := 0
   		   END
  		  ELSE Gadgets.framehandle(F, M);
  		  END
		  ELSIF M.id = Objects.enum THEN
 		   M.Enum("Color"); M.Enum("Cmd"); Gadgets.framehandle(F, M)
  		END
		END
    ELSIF M IS Objects.CopyMsg THEN
      WITH M: Objects.CopyMsg DO
        IF M.stamp = F.stamp THEN M.obj := F.dlink (*non-first arrival*)
        ELSE (*first arrival*)
          NEW(F1); F.stamp := M.stamp; F.dlink := F1;
          Gadgets.CopyFrame(M, F, F1); M.obj := F1
        END
      END
	ELSE
		Gadgets.framehandle(F, M)
	END
  END
END HandleColFrame;

PROCEDURE NewColFrame*;
VAR F: ColFrame;
BEGIN
  NEW(F); F.W := 50; F.H := 50; F.col := D3.black; F.handle := HandleColFrame; Objects.NewObj := F
END NewColFrame;

(** Verschiedene Operationen auf Picture mit Clipping falls negative Koordinaten **)
PROCEDURE CopyBlock*(S, D: Pictures.Picture; x, y: INTEGER; w, h, dx, dy, mode: INTEGER);
BEGIN
	IF dx<0 THEN w:= w+dx; x:=x-dx; dx:=0 END;
	IF dy<0 THEN h:=h+dy; y:=y-dy; dy:=0 END;
	IF (w>0) & (h>0) THEN Pictures.CopyBlock(S, D, x, y, w, h, dx, dy, mode) END
END CopyBlock;

PROCEDURE ReplConst*(P : Pictures.Picture; col, x, y, w, h: INTEGER);
BEGIN
	IF x<0 THEN w:=w+x; x:=0 END;
	IF y<0 THEN h:=h+y; y:=0 END;
	IF (w>0) & (h>0) THEN Pictures.ReplConst(P, col, x, y, w, h, Display.replace) END
END ReplConst;

(** Speicherblock für Picture allozieren oder Fehlermeldung ausgeben **)
PROCEDURE AllocatePictureMem*(VAR P: Pictures.Picture; w, h, d: INTEGER);
BEGIN
	Pictures.Create(P, w, h, d);
	IF P.depth = 0 THEN
		Out.String("Not enough free memory"); Out.Ln; P := NIL
	END
END AllocatePictureMem;

(** Best Match für gesuchten Farbwert in der aktuellen Farbpalette **)
PROCEDURE NearestColor*(r, g, b: LONGINT): INTEGER;
VAR d, t, min: LONGINT; col, i: INTEGER;
BEGIN
	min := MAX(LONGINT);
	i := 0;
	WHILE i # noc DO 
		t := (r - coltable[i].r); d := t * t;
		t := (g - coltable[i].g); INC(d, t * t);
		t := (b - coltable[i].b); INC(d, t * t);
		IF ABS(d) < min THEN min := ABS(d); col := i END;
		INC(i)
	END;
	RETURN col
END NearestColor;

PROCEDURE Gamma( val: INTEGER; gamma: REAL): INTEGER;
VAR gval: REAL;
  BEGIN
	IF val = 0 THEN gval := 0 ELSE gval := Math.exp(Math.ln(val/256.0)*gamma) END;
	RETURN SHORT(ENTIER(256*gval))
END Gamma;

(** Farbpalette ändern **)
PROCEDURE Darken*;
VAR i, r, g, b: INTEGER; gamma: REAL;
BEGIN
	gamma:= 1.25;
	FOR i:= 0 TO maxnoc-1 DO
		Display.GetColor(i, r, g, b);
		Display.SetColor(i, Gamma(r, gamma), Gamma(g, gamma), Gamma(b, gamma))
	END
END Darken;

PROCEDURE Lighten*;
VAR i, r, g, b: INTEGER; gamma: REAL;
BEGIN
	gamma:= 0.8;
	FOR i:= 0 TO maxnoc-1 DO
		Display.GetColor(i, r, g, b);
		Display.SetColor(i, Gamma(r, gamma), Gamma(g, gamma), Gamma(b, gamma))
	END
END Lighten;

PROCEDURE SetColor*;
VAR S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN color.col:= SHORT(S.i) END;
	Gadgets.Update(color)
END SetColor;

PROCEDURE ChangeColor*;
VAR S: Texts.Scanner; 
		r, g, b: INTEGER;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF (S.class = Texts.Int) THEN r:= SHORT(S.i) ELSE r:=0 END;
	Texts.Scan(S);
	IF (S.class = Texts.Int) THEN g:= SHORT(S.i) ELSE g:=0 END;
	Texts.Scan(S);
	IF (S.class = Texts.Int) THEN b:= SHORT(S.i) ELSE b:=0 END;
	Display.SetColor(color.col, r, g, b);
	coltable[color.col].r:=r; coltable[color.col].g:= g; coltable[color.col].b:=b
END ChangeColor;

(** Standardpalette wird neu geladen **)
PROCEDURE ResetAll*;
VAR F: Files.File;
		R: Files.Rider;
		r, g, b : CHAR; i: INTEGER;
BEGIN
	F:= Files.Old("Rembrandt0.Pal");
	Files.Set(R, F, 0);
	FOR i:= 0 TO maxnoc-1 DO
		Files.Read(R, r);
		Files.Read(R, g);
		Files.Read(R, b);
		coltable[i].r:= ORD(r); coltable[i].g:= ORD(g); coltable[i].b:=ORD(b);
		Display.SetColor(i, ORD(r), ORD(g), ORD(b));
	END;
	Gadgets.Update(color)
END ResetAll;

(** Einzelne Farbe auf Standardwert zurückgesetzt **)
PROCEDURE ResetOne*;
VAR F: Files.File;
		R: Files.Rider;
		r, g, b : CHAR; i: INTEGER;
BEGIN
	F:= Files.Old("Rembrandt0.Pal");
	Files.Set(R, F, 0);
	FOR i:= 0 TO maxnoc-1 DO
		Files.Read(R, r);
		Files.Read(R, g);
		Files.Read(R, b);
		IF i=color.col THEN
			coltable[i].r:= ORD(r); coltable[i].g:= ORD(g); coltable[i].b:=ORD(b);
			Display.SetColor(i, ORD(r), ORD(g), ORD(b))
		END;
	END;
	Gadgets.Update(color)
END ResetOne;

BEGIN
	Z := 1; floyd := NIL;
	NEW(color); color.handle:= HandleColor; color.col:= 3; Objects.NewObj := color;
	maxnoc:= 256; noc:= maxnoc
END Rembrandt0.

Gadgets.Insert Rembrandt0.NewColFrame Rembrandt0.NewColorObj~
