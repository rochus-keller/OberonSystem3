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

MODULE Dim3Paint;	(** portable *)	(* David Ulrich Nov  95 - März 96 *)
(** Dim3Paint covers the basic drawing functions of the module Dim3Engine. It includes color management and
      polygon drawing with and without the dynamic screen data structure **)

IMPORT
	Display, Display3, Pictures, Texts, Oberon, Files, SYSTEM, Math, Dim3Base;

CONST
	NoPattern = 0; Light = 1; Middle = 2; Dark = 3;
	PersLimit = 2;	(* maximal limit for no perspective correction *)
	Ln2 = 0.693147;	(* ln(2) *)
	MinTexture = 2; MaxTexture = 200;	(* minimal and maximal texture size for mipmaps *)
	cheat = 0.9999;
	
TYPE
	TextureMap* = POINTER TO TextureMapDesc;	(** pointer to background bitmap for shaded texture **)
	DSEntry* = POINTER TO DSEntryDesc;	(** Pointer to a dynamic screen entry **)
	TSEntry* = POINTER TO TSEntryDesc;	(** Pointer to the scanline entry for a transparent texture **)
	Color = POINTER TO ColorDesc; 
	
	TextureMapDesc = RECORD END;
	
	DSEntryDesc = RECORD	(* dynamic screen entry *)
		min,max: INTEGER;
		active: BOOLEAN;
		next: DSEntry;
	END;
	
	TSEntryDesc = RECORD	(* Scanline entry for transparent textures *)
		texture: TextureMap;
		X, Y, W: INTEGER;
		u, v, uStep, vStep: REAL;
		next: TSEntry;
	END;
	
	ColorDesc = RECORD	(* data structure of dithering table *)
		pattern: LONGINT; deltaR, deltaG, deltaB: INTEGER;
	END;
	
	Point = RECORD	(* help structure for points *)
		x, y, u, v, w: REAL;
	END;
	
VAR
	T: Texts.Writer;
	DSPool: DSEntry;
	TSPool: TSEntry;
	ColorIndex: ARRAY 10, 10, 6 OF INTEGER;
	DitherTab: ARRAY 4, 4, 4 OF Color;
	PatternTable: ARRAY 4 OF LONGINT;
	ColorTab: ARRAY 3,256 OF INTEGER;
	PDots: ARRAY 4,4 OF BOOLEAN;
	seed: LONGINT;
	GrayIndex: ARRAY 5 OF INTEGER;
	
	
(* Random procedure for dithering *)
 PROCEDURE Random (): REAL;
    CONST a = 16807; m = 2147483647; q = m DIV a; r = m MOD a; (*invm = 0.025 / m;*)
 BEGIN 
	seed := a*(seed MOD q) - r*(seed DIV q);
    IF seed <= 0 THEN seed := seed + m END;
    RETURN (seed * (0.025 / m) - 0.0125);
 END Random;

  
 (*--- Color Handling ---*)
(** initialize standard rembrandt colormap, initialize color and dither tables **)
PROCEDURE InitColors*;
VAR F: Files.File; R: Files.Rider; 
	  i,h,k, pattern, iSgn, hSgn, kSgn, sum, R1, G, B: INTEGER; 
	  r, g, b: CHAR; 
	  
	PROCEDURE GetNearestColor(r,g,b : INTEGER):INTEGER;
	VAR	col, i: INTEGER;	 d, t, min: LONGINT;
	BEGIN
		IF (r = g) & (r = b) THEN	(* use only grayscale colors *)
			min := MAX(LONGINT); col := Dim3Base.White;
			i := 0;
			WHILE i # 256 DO 
				IF (ColorTab[0][i] = ColorTab[1][i]) & (ColorTab[0][i] = ColorTab[2][i]) THEN
					d := (r - ColorTab[0][i]);
					IF ABS(d) < min THEN min := ABS(d); col := i END;
				END;
				INC(i)
			END;
			RETURN col
		ELSE
			min := MAX(LONGINT);
			i := 0;
			WHILE i # 256 DO 
				t := (r - ColorTab[0][i]); 
				IF r > ColorTab[0][i] THEN t := t*2 END; d := t * t;
				t := (g - ColorTab[1][i]); 
				IF g > ColorTab[1][i] THEN t := t*2 END; INC(d, t * t);
				t := (b - ColorTab[2][i]); 
				IF b > ColorTab[2][i] THEN t := t*2 END; INC(d, t * t);
				IF ABS(d) < min THEN min := ABS(d); col := i END;
				INC(i)
			END;
			RETURN col
		END;
	END GetNearestColor;
	
BEGIN
	(* works only with 256 colors *)
	IF Display.Depth(Display.ColLeft) # 8 THEN
		Texts.WriteString(T, "3D-Engine: current implementation works on 256 color systems");
		Texts.WriteLn(T); Texts.Append(Oberon.Log, T.buf);
		HALT(99);
	END;
	
	FOR i := 0 TO 3 DO
		IF i = 0 THEN iSgn := 0 ELSE iSgn := 1 END;
		FOR h := 0 TO 3 DO
			IF h = 0 THEN hSgn := 0 ELSE hSgn := 1 END;
			FOR k := 0 TO 3 DO
				IF k = 0 THEN kSgn := 0 ELSE kSgn := 1 END;
				NEW(DitherTab[i][h][k]);
				DitherTab[i][h][k].deltaR := iSgn;
				DitherTab[i][h][k].deltaG := hSgn;
				DitherTab[i][h][k].deltaB := kSgn;
				sum := 2 * iSgn + 2 * hSgn + kSgn;
				IF sum # 0 THEN pattern := (2 * i + 2 * h + k) DIV sum ELSE pattern := 0 END;
				DitherTab[i][h][k].pattern := PatternTable[pattern];
			END;
		END;
	END;
	
	F:= Files.Old("Rembrandt0.Pal");
	Files.Set(R, F, 0);
	FOR i:= 0 TO 255 DO
		Files.Read(R, r);
		Files.Read(R, g);
		Files.Read(R, b);
		ColorTab[0][i] := ORD(r);
		ColorTab[1][i] := ORD(g);
		ColorTab[2][i] := ORD(b);
		Display.SetColor(i, ORD(r), ORD(g), ORD(b));
	END;
	Dim3Base.CheckColorTab(ColorTab[0], ColorTab[1], ColorTab[2]);
	
	FOR i := 0 TO 8 DO
		FOR h := 0 TO 8 DO
			FOR k := 0 TO 4 DO
				R1 := SHORT(ENTIER(i*31.99)); G := SHORT(ENTIER(h*31.99));  B := SHORT(ENTIER(k*63.99)); 
				ColorIndex[i][h][k] := GetNearestColor(R1, G, B);
			END;
		END;
	END;
	FOR i := 0 TO 8 DO
		FOR h := 0 TO 4 DO
			ColorIndex[9][i][h] := ColorIndex[8][i][h];
			ColorIndex[i][9][h] := ColorIndex[i][8][h];
		END;
	END;
	FOR i := 0 TO 8 DO
		FOR h := 0 TO 8 DO
			ColorIndex[i][h][5] := ColorIndex[i][h][4];
		END;
	END;
	
	FOR i := 0 TO 4 DO
		B := SHORT(ENTIER(i*63.99));
		GrayIndex[i] := GetNearestColor(B, B, B);
	END;
END InitColors;

(** get color index for colormap that matches best **)
PROCEDURE GetColor* (col: ARRAY OF REAL; light: REAL; grayscale: BOOLEAN):INTEGER;
VAR R, G, B: LONGINT;
BEGIN
	IF light <=  0.0 THEN 
		RETURN Dim3Base.Black
	END;
	IF grayscale THEN
		R := ENTIER(light * col[0] * 4.99);
		IF R > 4 THEN R := 4 END;
		RETURN GrayIndex[R]
	ELSE
		R := ENTIER(light * col[0] * 8.99);
		IF R > 8 THEN R := 8 END;
		G := ENTIER(light * col[1] * 8.99);
		IF G > 8 THEN G := 8 END;
		B := ENTIER(light * col[2] * 4.99);
		IF B > 4 THEN B := 4 END;
		RETURN ColorIndex[R][G][B]
	END;
END GetColor;

(* get color indexes for colormap and dithering that matches best *)
PROCEDURE GetColorDither (col: ARRAY OF REAL; light: REAL; grayscale: BOOLEAN; VAR baseCol, patCol: INTEGER;
												VAR pat: LONGINT; rand: REAL);
VAR R, G, B, R1, G1, B1, RMod, GMod, BMod: LONGINT; color: Color; 
BEGIN
	light := light + rand;
	IF light <= 0.0 THEN 
		baseCol := Dim3Base.Black;
		pat := NoPattern;
		RETURN;
	END;
	
	IF grayscale THEN
		B := ENTIER(light * 16.99 * col[2]); IF B > 16 THEN B := 16 END;
		B1 := ASH(B, -2);
		BMod := (B - ASH(B1, 2));
		baseCol := GrayIndex[B1];
		pat := BMod;
		IF B1 < 4 THEN patCol := GrayIndex[B1 + 1] ELSE patCol := baseCol END
	ELSE
		R := ENTIER(light * 32.99 * col[0]); IF R > 32 THEN R := 32 END;
		R1 := ASH(R, -2);
		RMod := (R - ASH(R1, 2));
		G := ENTIER(light * 32.99 * col[1]); IF G > 32 THEN G := 32 END;
		G1 := ASH(G, -2);
		GMod := (G - ASH(G1, 2));
		B := ENTIER(light * 16.99 * col[2]); IF B > 16 THEN B := 16 END;
		B1 := ASH(B, -2);
		BMod := (B - ASH(B1, 2));
	
		color := DitherTab[RMod][GMod][BMod];
		baseCol := ColorIndex[R1][G1][B1];
		patCol := ColorIndex[R1 + color.deltaR][G1 + color.deltaG][B1 + color.deltaB];
		pat := color.pattern;
	END;
END GetColorDither;

(* get color indexes for colormap and dithering that matches best, for specular reflection*)
PROCEDURE GetColorSpecular (col: ARRAY OF REAL; light, spec: REAL; grayscale: BOOLEAN; VAR baseCol, patCol: INTEGER;
													VAR pat: LONGINT; rand: REAL);
VAR R, G, B, R1, G1, B1, RMod, GMod, BMod: LONGINT; color: Color; 
BEGIN
	light := light + rand; spec := spec + 0.001;
	IF light <= 0.0 THEN 
		baseCol := Dim3Base.Black;
		pat := NoPattern;
		RETURN;
	END;
	
	IF grayscale THEN
		B := ENTIER(light * 16.99 * (col[2] + spec)); IF B > 16 THEN B := 16 END;
		B1 := ASH(B, -2);
		BMod := (B - ASH(B1, 2));
		baseCol := GrayIndex[B1];
		pat := BMod;
		IF B1 < 4 THEN patCol := GrayIndex[B1 + 1] ELSE patCol := baseCol END
	ELSE
		R := ENTIER(light * 32.99 * (col[0] + spec)); IF R > 32 THEN R := 32 END;
		R1 := ASH(R, -2);
		RMod := (R - ASH(R1, 2));
		G := ENTIER(light * 32.99 * (col[1] + spec)); IF G > 32 THEN G := 32 END;
		G1 := ASH(G, -2);
		GMod := (G - ASH(G1, 2));
		B := ENTIER(light * 16.99 * (col[2] + spec)); IF B > 16 THEN B := 16 END;
		B1 := ASH(B, -2);
		BMod := (B - ASH(B1, 2));
		
		color := DitherTab[RMod][GMod][BMod];
		baseCol := ColorIndex[R1][G1][B1];
		patCol := ColorIndex[R1 + color.deltaR][G1 + color.deltaG][B1 + color.deltaB];
		pat := color.pattern
	END
END GetColorSpecular;


(*--- TS and DS entry mangement ---*)

(* freeing of a DSEntry to pool *)
PROCEDURE FreeDSEntry(entry: DSEntry);
BEGIN
	entry.next := DSPool;
	DSPool := entry
END FreeDSEntry;

(** freeing of a DSEntryArray to pool **)
PROCEDURE FreeDSList* (VAR ds: ARRAY OF DSEntry; n: INTEGER);
	VAR
		i: INTEGER;
		entry: DSEntry;
BEGIN
	FOR i := 0 TO n DO
		IF ds[i] # NIL THEN
			entry := ds[i];
			WHILE entry.next # NIL DO
				entry := entry.next;
			END;
			entry.next := DSPool;
			DSPool := ds[i];
			ds[i] := NIL
		END;
	END;
END FreeDSList;

(* allocating of a DSEntry from pool *)
PROCEDURE AllocDSEntry(VAR entry: DSEntry);
BEGIN
	IF DSPool = NIL THEN
		NEW(entry)
	ELSE
		entry := DSPool;
		DSPool := entry.next;
	END;
	entry.next := NIL;
	entry.active := TRUE;
END AllocDSEntry;

(* allocating of a TSEntry from pool *)
PROCEDURE AllocTSEntry(VAR entry: TSEntry);
BEGIN
	IF TSPool = NIL THEN
		NEW(entry)
	ELSE
		entry := TSPool;
		TSPool := entry.next;
	END;
END AllocTSEntry;

(** initialisation of the dynamic Screen datastructure, max: screen width, n: screen height **)
PROCEDURE InitDynScreen*(VAR ds: ARRAY OF DSEntry; max,n: INTEGER);
VAR
	i: INTEGER;
BEGIN
	FOR i := 0 TO n DO
		AllocDSEntry(ds[i]);
		ds[i].min := 0;
		ds[i].max := max;
	END;
END InitDynScreen;


(*--- Rendering ---*)

(** Fill not painted rest of the screen with color col, free dynamic screen datastructure **)
PROCEDURE DrawRest* (P: Pictures.Picture; ds: ARRAY OF DSEntry; col: INTEGER);
VAR
	i,max: INTEGER;
	entry, old: DSEntry;
BEGIN
	Dim3Base.SetPicture(P);
	max := P.height;
	FOR i := 0 TO max DO
		entry := ds[i];
		WHILE entry # NIL DO
			Dim3Base.ReplConst(col, entry.min, i, entry.max - entry.min + 1);
			old := entry;
			entry := entry.next;
			FreeDSEntry(old);
		END;
	END;
END DrawRest;

(* Draw pattern using ReplConst and Dot *)
PROCEDURE DrawPattern(baseCol, patCol: INTEGER; pattern: LONGINT;
								  X, Y, W: INTEGER);
VAR	oddY, oddX: BOOLEAN; index: INTEGER; pictAdr: LONGINT;
BEGIN
	oddY := ODD(Y); oddX := ODD(X);
	IF ((pattern = Light) & oddY) OR (pattern = NoPattern) THEN
		Dim3Base.ReplConst(baseCol, X, Y, W);
		RETURN;
	ELSIF (pattern = Dark) & (~oddY) THEN
		Dim3Base.ReplConst(patCol, X, Y, W);
		RETURN;
	ELSIF oddY THEN
		IF oddX THEN index := 1 ELSE index := 0 END;
	ELSE
		IF oddX THEN index := 0 ELSE index := 1 END;
	END;
	Dim3Base.ReplConst(baseCol, X, Y, W);
	
	pictAdr := Dim3Base.GetAddress(X, Y);
	WHILE index < W DO
		SYSTEM.PUT(pictAdr + index, CHR(patCol));
		INC(index,2)
	END;
END DrawPattern;

(* split dynamic screen entry into two entries *)
PROCEDURE SplitSegment(i,j: INTEGER; k: DSEntry);
VAR
	newEntry: DSEntry;
BEGIN
	AllocDSEntry(newEntry);
	newEntry.min := j + 1;
	newEntry.max := k.max;
	k.max := i - 1;
	newEntry.next := k.next;
	k.next := newEntry;
END SplitSegment;

(* draw a gouraud shaded polygon scanline, with dithering and specular reflection *)
PROCEDURE DrawSpecularSegment(sel: BOOLEAN; col: ARRAY OF REAL; planeCol: INTEGER; grayscale: BOOLEAN; entry: DSEntry;
												  			xL, xR: REAL; Y, botL, botR, topL, topR: INTEGER; y, i, s: ARRAY OF REAL);
VAR XL, XR, W: INTEGER; t1, t3, iL, iR, dInten, dSpec, sL, sR: REAL;

	PROCEDURE Display(X, W: INTEGER; iLeft, sLeft: REAL);
	VAR  x, color, oddY, oddX, patCol: INTEGER; inten, spec: REAL; pat, pictAdr: LONGINT; rand: REAL;
	BEGIN
		IF W > 2 THEN rand := Random() ELSE rand := 0 END;
		IF ODD(Y) THEN oddY := 0 ELSE oddY := 2 END;
		oddX := 0;
		inten := iLeft; spec := sLeft; 
		pictAdr := Dim3Base.GetAddress(X, Y);
		WHILE W >= 15 DO
			FOR x := 1 TO 15 DO
				GetColorSpecular(col, inten, spec, grayscale, color, patCol, pat, rand); 
				inten := inten + dInten; spec := spec +dSpec;
				IF PDots[pat][oddY + oddX] THEN
					SYSTEM.PUT(pictAdr, CHR(patCol))
				ELSE
					SYSTEM.PUT(pictAdr, CHR(color))
				END;
				INC(pictAdr);
				oddX := (oddX + 1) MOD 2
			END;
			rand := Random(); DEC(W, 15);
		END;
		WHILE W > 0 DO
			GetColorSpecular(col, inten, spec, grayscale, color, patCol, pat, rand); 
			inten := inten + dInten; spec := spec + dSpec; 
			IF PDots[pat][oddY + oddX] THEN
				SYSTEM.PUT(pictAdr, CHR(patCol))
			ELSE
				SYSTEM.PUT(pictAdr, CHR(color))
			END;
			INC(pictAdr);
			oddX := (oddX + 1) MOD 2;
			DEC(W);
		END;
	END Display;
	
BEGIN
	IF xL <= xR THEN
		XL := SHORT(ENTIER(xL)) + 1;
		XR := SHORT(ENTIER(xR));
		W := XR - XL + 1;
		t1 := (y[topL] - Y) / (y[topL] - y[botL]); 
		t3 := i[botL] - i[topL]; iL := i[topL] + t1 * t3;
		t3 := s[botL] - s[topL]; sL := s[topL] + t1 * t3;
		
		t1 := (y[topR] - Y) / (y[topR] - y[botR]); 
		t3 := i[botR] - i[topR]; iR := i[topR] + t1 * t3;
		t3 := s[botR] - s[topR]; sR := s[topR] + t1 * t3;
	ELSE
		XL := SHORT(ENTIER(xR)) + 1;
		XR := SHORT(ENTIER(xL));
		W := XR - XL + 1;
		t1 := (y[topL] - Y) / (y[topL] - y[botL]); 
		t3 := i[botL] - i[topL]; iR := i[topL] + t1 * t3;
		t3 := s[botL] - s[topL]; sR := s[topL] + t1 * t3;
		
		t1 := (y[topR] - Y) / (y[topR] - y[botR]); 
		t3 := i[botR] - i[topR]; iL := i[topR] + t1 * t3;
		t3 := s[botR] - s[topR]; sL := s[topR] + t1 * t3;
	END;
	
		dInten := (iR - iL) / (W - cheat);
		dSpec := (sR - sL) / (W - cheat);
		
		(* Loop for merging *)
		LOOP
			IF W <= 0 THEN EXIT END;
			IF ~entry.active THEN
				entry := entry.next
			ELSIF XR < entry.min THEN	(* case 1 *)
				EXIT;
			ELSIF XL > entry.max THEN	(* case 8 *)
				entry := entry.next;
			ELSE
				IF XR < entry.max THEN
					IF XL <= entry.min THEN	(* case 2 *)
						Display(entry.min, XR - entry.min + 1, iL + (entry.min - XL) * dInten, sL + (entry.min - XL) * dSpec);
						entry.min := XR + 1;
						EXIT;
					ELSE	(* case 3 *)
						Display( XL, W, iL, sL);
						SplitSegment(XL, XR, entry);
						EXIT;
					END;
				ELSIF XR > entry.max THEN
					IF XL <= entry.min THEN	(* case 6 *)
						Display(entry.min, entry.max - entry.min + 1, iL + (entry.min - XL) * dInten, sL + (entry.min - XL) * dSpec);
						entry.active := FALSE;
						entry := entry.next;
					ELSE	(* case 7 *)
						Display(XL, entry.max - XL + 1, iL, sL);
						entry.max := XL - 1;
						entry := entry.next;
					END;
				ELSE
					IF XL <= entry.min THEN	(* case 4 *)
						Display(entry.min, entry.max - entry.min + 1, iL + (entry.min - XL) * dInten, sL + (entry.min - XL) * dSpec);
							entry.active := FALSE;
						EXIT;
					ELSE	(* case 5 *)
						Display(XL, W, iL, sL);
						entry.max := XL - 1;
						EXIT;
					END;
				END;
			END;
		END; 
END DrawSpecularSegment;

(* draw a gouraud shaded polygon scanline, with dithering *)
PROCEDURE DrawDitherSegment(sel: BOOLEAN; col: ARRAY OF REAL; planeCol: INTEGER; grayscale: BOOLEAN; entry: DSEntry;
												  			xL, xR: REAL; Y, botL, botR, topL, topR: INTEGER; y, i, s: ARRAY OF REAL);
VAR XL, XR, W: INTEGER; t1, t2, t3, iL, iR, dInten: REAL;

	PROCEDURE Display(X, W: INTEGER; iLeft: REAL);
	VAR  x, color, oddY, oddX, patCol: INTEGER; inten: REAL; pat, pictAdr: LONGINT; rand: REAL;
	BEGIN
		IF W > 2 THEN rand := Random() ELSE rand := 0 END;
		IF ODD(Y) THEN oddY := 0 ELSE oddY := 2 END;
		oddX := 0;
		inten := iLeft;
		pictAdr := Dim3Base.GetAddress(X, Y);
		WHILE W >= 15 DO
			FOR x := 1 TO 15 DO
				GetColorDither(col, inten, grayscale, color, patCol, pat, rand); 
				inten := inten + dInten;
				IF PDots[pat][oddY + oddX] THEN
					SYSTEM.PUT(pictAdr, CHR(patCol))
				ELSE
					SYSTEM.PUT(pictAdr, CHR(color))
				END;
				INC(pictAdr);
				oddX := (oddX + 1) MOD 2
			END;
			rand := Random(); DEC(W, 15);
		END;
		WHILE W > 0 DO
			GetColorDither(col, inten, grayscale, color, patCol, pat, rand); 
			inten := inten + dInten;
			IF PDots[pat][oddY + oddX] THEN
				SYSTEM.PUT(pictAdr, CHR(patCol))
			ELSE
				SYSTEM.PUT(pictAdr, CHR(color))
			END;
			INC(pictAdr);
			oddX := (oddX + 1) MOD 2;
			DEC(W);
		END;
	END Display;
	
BEGIN
	IF xL <= xR THEN
		XL := SHORT(ENTIER(xL)) + 1;
		XR := SHORT(ENTIER(xR));
		W := XR - XL + 1;
		t1 := y[topL] - Y; t2 := y[topL] - y[botL]; t3 := i[botL] - i[topL];
		iL := i[topL] + t1 / t2 * t3;
		t1 := y[topR] - Y; t2 := y[topR] - y[botR]; t3 := i[botR] - i[topR];
		iR := i[topR] + t1 / t2 * t3;
		dInten := (iR - iL) / (W - cheat);
	ELSE
		XL := SHORT(ENTIER(xR)) + 1;
		XR := SHORT(ENTIER(xL));
		W := XR - XL + 1;
		t1 := y[topL] - Y; t2 := y[topL] - y[botL]; t3 := i[botL] - i[topL];
		iR := i[topL] + t1 / t2 * t3;
		t1 := y[topR] - Y; t2 := y[topR] - y[botR]; t3 := i[botR] - i[topR];
		iL := i[topR] + t1 / t2 * t3;
		dInten := (iR - iL) / (W - cheat);
	END;
		
	(* Loop for merging *)
	LOOP
		IF W <= 0 THEN EXIT END;
		IF ~entry.active THEN
			entry := entry.next
		ELSIF XR < entry.min THEN	(* case 1 *)
			EXIT;
		ELSIF XL > entry.max THEN	(* case 8 *)
			entry := entry.next;
		ELSE
			IF XR < entry.max THEN
				IF XL <= entry.min THEN	(* case 2 *)
					Display(entry.min, XR - entry.min + 1,iL + (entry.min - XL) * dInten);
					entry.min := XR + 1;
					EXIT;
				ELSE	(* case 3 *)
					Display( XL, W, iL);
					SplitSegment(XL, XR, entry);
					EXIT;
				END;
			ELSIF XR > entry.max THEN
				IF XL <= entry.min THEN	(* case 6 *)
					Display(entry.min, entry.max - entry.min + 1, iL + (entry.min - XL) * dInten);
					entry.active := FALSE;
					entry := entry.next;
				ELSE	(* case 7 *)
					Display(XL, entry.max - XL + 1, iL);
					entry.max := XL - 1;
					entry := entry.next;
				END;
			ELSE
				IF XL <= entry.min THEN	(* case 4 *)
					Display(entry.min, entry.max - entry.min + 1, iL + (entry.min - XL) * dInten);
						entry.active := FALSE;
					EXIT;
				ELSE	(* case 5 *)
					Display(XL, W, iL);
					entry.max := XL - 1;
					EXIT;
				END;
			END;
		END;
	END; 
END DrawDitherSegment;

(* draw a gouraud shaded polygon scanline, no dithering *)
PROCEDURE DrawGouraudSegment(sel: BOOLEAN; col: ARRAY OF REAL; planeCol: INTEGER; grayscale: BOOLEAN; entry: DSEntry;
												  			xL, xR: REAL; Y, botL, botR, topL, topR: INTEGER; y, i, s: ARRAY OF REAL);
VAR XL, XR, W: INTEGER; t1, t2, t3, iL, iR, dInten: REAL;

	PROCEDURE Display(X, W: INTEGER; iLeft: REAL);
	VAR  x, color: INTEGER; inten, dInt: REAL; pictAdr: LONGINT;
	BEGIN
		DEC(W);
		inten := iLeft;
		dInt := dInten;
		pictAdr := Dim3Base.GetAddress(X, Y);
	
		FOR x := 0 TO W DO
			color := GetColor(col, inten, grayscale); 
			inten := inten + dInt;
			SYSTEM.PUT(pictAdr, CHR(color));
			INC(pictAdr);
		END;
	END Display;
	
BEGIN
	IF xL <= xR THEN
		XL := SHORT(ENTIER(xL)) + 1;
		XR := SHORT(ENTIER(xR));
		W := XR - XL + 1;
		t1 := y[topL] - Y; t2 := y[topL] - y[botL]; t3 := i[botL] - i[topL];
		iL := i[topL] + t1 / t2 * t3;
		t1 := y[topR] - Y; t2 := y[topR] - y[botR]; t3 := i[botR] - i[topR];
		iR := i[topR] + t1 / t2 * t3;
		dInten := (iR - iL) / (W - cheat);
	ELSE
		XL := SHORT(ENTIER(xR)) + 1;
		XR := SHORT(ENTIER(xL));
		W := XR - XL + 1;
		t1 := y[topL] - Y; t2 := y[topL] - y[botL]; t3 := i[botL] - i[topL];
		iR := i[topL] + t1 / t2 * t3;
		t1 := y[topR] - Y; t2 := y[topR] - y[botR]; t3 := i[botR] - i[topR];
		iL := i[topR] + t1 / t2 * t3;
		dInten := (iR - iL) / (W - cheat);
	END;
		
	(* Loop for merging *)
	LOOP
		IF W <= 0 THEN EXIT END;
		IF ~entry.active THEN
			entry := entry.next
		ELSIF XR < entry.min THEN	(* case 1 *)
			EXIT;
		ELSIF XL > entry.max THEN	(* case 8 *)
			entry := entry.next;
		ELSE
			IF XR < entry.max THEN
				IF XL <= entry.min THEN	(* case 2 *)
					Display(entry.min, XR - entry.min + 1,iL + (entry.min - XL) * dInten);
					entry.min := XR + 1;
					EXIT;
				ELSE	(* case 3 *)
					Display( XL, W, iL);
					SplitSegment(XL, XR, entry);
					EXIT;
				END;
			ELSIF XR > entry.max THEN
				IF XL <= entry.min THEN	(* case 6 *)
					Display(entry.min, entry.max - entry.min + 1, iL + (entry.min - XL) * dInten);
					entry.active := FALSE;
					entry := entry.next;
				ELSE	(* case 7 *)
					Display(XL, entry.max - XL + 1, iL);
					entry.max := XL - 1;
					entry := entry.next;
				END;
			ELSE
				IF XL <= entry.min THEN	(* case 4 *)
					Display(entry.min, entry.max - entry.min + 1, iL + (entry.min - XL) * dInten);
						entry.active := FALSE;
					EXIT;
				ELSE	(* case 5 *)
					Display(XL, W, iL);
					entry.max := XL - 1;
					EXIT;
				END;
			END;
		END;
	END; 
END DrawGouraudSegment;

(* draw a constant shaded polygon scanline *)
PROCEDURE DrawUniSegment(sel: BOOLEAN; col: ARRAY OF REAL; planeCol: INTEGER; grayscale: BOOLEAN;
												  	entry: DSEntry; xL, xR: REAL; Y, botL, botR, topL, topR: INTEGER; y, i, s: ARRAY OF REAL);
VAR XL, XR, W: INTEGER;

	PROCEDURE Display(X, W: INTEGER);
	BEGIN
		IF sel THEN
			DrawPattern(planeCol, Display3.BG, Middle, X, Y, W)
		ELSE
			Dim3Base.ReplConst(planeCol, X, Y, W)
		END;
	END Display;
	
BEGIN
	IF xL <= xR THEN
		XL := SHORT(ENTIER(xL)) + 1;
		XR := SHORT(ENTIER(xR));
		W := XR - XL + 1;
	ELSE
		XL := SHORT(ENTIER(xR)) + 1;
		XR := SHORT(ENTIER(xL));
		W := XR - XL + 1;
	END;
		
	(* Loop for merging *)
	LOOP
		IF W <= 0 THEN EXIT END;
		IF ~entry.active THEN
			entry := entry.next
		ELSIF XR < entry.min THEN	(* case 1 *)
			EXIT;
		ELSIF XL > entry.max THEN	(* case 8 *)
			entry := entry.next;
		ELSE
			IF XR < entry.max THEN
				IF XL <= entry.min THEN	(* case 2 *)
					Display(entry.min, XR - entry.min + 1);
					entry.min := XR + 1;
					EXIT;
				ELSE	(* case 3 *)
					Display(XL, W);
					SplitSegment(XL, XR, entry);
					EXIT;
				END;
			ELSIF XR > entry.max THEN
				IF XL <= entry.min THEN	(* case 6 *)
					Display(entry.min, entry.max - entry.min + 1);
					entry.active := FALSE;
					entry := entry.next;
				ELSE	(* case 7 *)
					Display(XL, entry.max - XL + 1);
					entry.max := XL - 1;
					entry := entry.next;
				END;
			ELSE
				IF XL <= entry.min THEN	(* case 4 *)
					Display(entry.min, entry.max - entry.min + 1);
						entry.active := FALSE;
					EXIT;
				ELSE	(* case 5 *)
					Display(XL, W);
					entry.max := XL - 1;
					EXIT;
				END;
			END;
		END;
	END; 
END DrawUniSegment;

(** Draw polygon with the dynamic screen method as following:
		uni = TRUE : draw a constant shaded polygon; 
		uni = FALSE & dither = FALSE & specular = FALSE : draw a gouraud shaded polygon without dithering and without specular reflection;
		uni = FALSE & dither = FALSE & specular = TRUE : not allowed;
		uni = FALSE & dither = TRUE & specular = FALSE : draw a gouraud shaded polygon with 2*2 dithering and without specular reflection; 
		uni = FALSE & dither = TRUE & specular = TRUE : draw a gouraud shaded polygon with 2*2 dithering and with specular reflection; **)
PROCEDURE DrawShadePoly* (P: Pictures.Picture; VAR ds: ARRAY OF DSEntry; col: ARRAY OF REAL; planeCol: INTEGER;
										grayscale, uni, sel, dither, specular: BOOLEAN; VAR x, y, i, s: ARRAY OF REAL; n: INTEGER);
VAR
	xL, xR, mL, mR, dxL, dxR, dyL, dyR, yt, pw, ph: REAL;
	sy, topY, stopL, stopR: LONGINT; 
	topL, topR, botL, botR, t, Y: INTEGER;
	drawScanline: PROCEDURE(sel: BOOLEAN; col: ARRAY OF REAL; planeCol: INTEGER; grayscale: BOOLEAN;
												  entry: DSEntry; xL, xR: REAL; Y, botL, botR, topL, topR: INTEGER; y, i, s: ARRAY OF REAL);
BEGIN
	seed := 1235; DEC(n);
	Dim3Base.SetPicture(P);
	
	IF uni  OR sel THEN
		drawScanline := DrawUniSegment
	ELSIF ~dither THEN 	(* draw with dithering or not *)
		drawScanline := DrawGouraudSegment
	ELSIF ~specular THEN
		drawScanline := DrawDitherSegment
	ELSE
		drawScanline := DrawSpecularSegment;
	END;
	
	(* find bottommost point and highest y value *)
	botL := 0; topL := 0;
	pw := ASH(P.width, -1); ph := ASH(P.height, -1);
	x[0] := pw * (cheat + x[0]);
	y[0] := ph * (cheat + y[0]);
	FOR t := 1 TO n DO
		x[t] := pw * (cheat +x[t]);
		yt := ph * (cheat + y[t]);
		y[t] := yt;
		IF yt < y[botL] THEN botL := t END;
		IF yt > y[topL] THEN topL := t END
	END;
	sy := ENTIER(y[botL]) + 1;	(* initialize current scanline *)
	IF sy > ENTIER(y[topL]) THEN	(* polygon lies between scanlines *)
		RETURN
	END;
	
	topY := ENTIER(y[topL]);	(* last scanline to be considered *)
	botR := botL;
	IF botL = 0 THEN topL := n  ELSE topL := botL - 1 END;
	IF botR = n THEN topR := 0 ELSE topR := botR + 1 END;
	
	(* set up parameters for first two edges *)
	dxL := x[topL] - x[botL]; dyL := y[topL] - y[botL];
	stopL := ENTIER(y[topL]);
	WHILE stopL < sy DO
		botL := topL; 
		IF topL = 0 THEN topL := n ELSE DEC(topL) END;
		dxL := x[topL] - x[botL]; dyL := y[topL] - y[botL];
		stopL := ENTIER(y[topL])
	END;
	mL := dxL / dyL;
	xL := x[botL] + (sy - y[botL]) * mL;
	
	dxR := x[topR] - x[botR]; dyR := y[topR] - y[botR];
	stopR := ENTIER(y[topR]);
	WHILE stopR < sy DO
		botR := topR; 
		IF topR = n THEN topR := 0 ELSE INC(topR) END;
		dxR := x[topR] - x[botR]; dyR := y[topR] - y[botR];
		stopR := ENTIER(y[topR])
	END;
	mR := dxR / dyR;
	xR := x[botR] + (sy - y[botR]) * mR;
	
	LOOP
		(* draw current scanline *)
		Y := SHORT(sy);
		drawScanline(sel, col, planeCol, grayscale, ds[sy], xL, xR, Y, botL, botR, topL, topR, y, i, s);
				
		(* exit from loop if topmost scanline has just been drawn *)
		IF sy = topY THEN EXIT END;
		
		(* update left edge *)
		IF sy = stopL THEN
			REPEAT
				botL := topL; 
				IF topL = 0 THEN topL := n ELSE DEC(topL) END;
				dxL := x[topL] - x[botL]; dyL := y[topL] - y[botL];
				stopL := ENTIER(y[topL])
			UNTIL stopL > sy;
			mL := dxL / dyL;
			xL := x[botL] + (sy+1 - y[botL]) * mL;
		ELSE
			xL := xL + mL
		END;
		
		(* update right edge *)
		IF sy = stopR THEN
			REPEAT
				botR := topR; 
				IF topR = n THEN topR := 0 ELSE INC(topR) END;
				dxR := x[topR] - x[botR]; dyR := y[topR] - y[botR];
				stopR := ENTIER(y[topR])
			UNTIL stopR > sy;
			mR := dxR / dyR;
			xR := x[botR] + (sy+1 - y[botR]) * mR;
		ELSE
			xR := xR + mR
		END;
		
		INC(sy)
	END	(* End outer loop *)
END DrawShadePoly;

(** Draw constant shaded polygon without the dynamic screen method **)
PROCEDURE DrawPolygon* (P: Pictures.Picture; col: INTEGER; sel: BOOLEAN; VAR x, y: ARRAY OF REAL; n: INTEGER);
VAR
	xL, xR, mL, mR, dxL, dxR, dyL, dyR, yt, pw, ph: REAL;
	sy, topY, stopL, stopR: LONGINT;
	topL, topR, botL, botR, t, X, W: INTEGER;
BEGIN
	Dim3Base.SetPicture(P); DEC(n);
	
	(* find bottommost point and highest y value *)
	botL := 0; topL := 0;
	pw := ASH(P.width, -1); ph := ASH(P.height, -1);
	x[0] := pw * (cheat + x[0]);
	y[0] := ph * (cheat + y[0]);
	FOR t := 1 TO n DO
		x[t] := pw * (cheat +x[t]);
		yt := ph * (cheat + y[t]);
		y[t] := yt;
		IF yt < y[botL] THEN botL := t END;
		IF yt > y[topL] THEN topL := t END
	END;
	sy := ENTIER(y[botL]) + 1;	(* initialize current scanline *)
	IF sy > ENTIER(y[topL]) THEN	(* polygon lies between scanlines *)
		RETURN
	END;
	
	topY := ENTIER(y[topL]);	(* last scanline to be considered *)
	botR := botL;
	IF botL = 0 THEN topL := n  ELSE topL := botL - 1 END;
	IF botR = n THEN topR := 0 ELSE topR := botR + 1 END;
	
	(* set up parameters for first two edges *)
	dxL := x[topL] - x[botL]; dyL := y[topL] - y[botL];
	stopL := ENTIER(y[topL]);
	WHILE stopL < sy DO
		botL := topL; 
		IF topL = 0 THEN topL := n ELSE DEC(topL) END;
		dxL := x[topL] - x[botL]; dyL := y[topL] - y[botL];
		stopL := ENTIER(y[topL])
	END;
	mL := dxL / dyL;
	xL := x[botL] + (sy - y[botL]) * mL;
	
	dxR := x[topR] - x[botR]; dyR := y[topR] - y[botR];
	stopR := ENTIER(y[topR]);
	WHILE stopR < sy DO
		botR := topR; 
		IF topR = n THEN topR := 0 ELSE INC(topR) END;
		dxR := x[topR] - x[botR]; dyR := y[topR] - y[botR];
		stopR := ENTIER(y[topR])
	END;
	mR := dxR / dyR;
	xR := x[botR] + (sy - y[botR]) * mR;
	
	LOOP
		(* draw current scanline *)
		IF xL <= xR THEN
			X := SHORT(ENTIER(xL));
			W := SHORT(ENTIER(xR)) - X
		ELSE
			X := SHORT(ENTIER(xR));
			W := SHORT(ENTIER(xL)) - X
		END;
		IF sel THEN
			DrawPattern(col, Display3.BG, Middle, X + 1, SHORT(sy), W)
		ELSE
			Dim3Base.ReplConst(col, X + 1, SHORT(sy), W);
		END;
		
		(* exit from loop if topmost scanline has just been drawn *)
		IF sy = topY THEN EXIT END;
		
		(* update left edge *)
		IF sy = stopL THEN
			REPEAT
				botL := topL; 
				IF topL = 0 THEN topL := n ELSE DEC(topL) END;
				dxL := x[topL] - x[botL]; dyL := y[topL] - y[botL];
				stopL := ENTIER(y[topL])
			UNTIL stopL > sy;
			mL := dxL / dyL;
			xL := x[botL] + (sy+1 - y[botL]) * mL
		ELSE
			xL := xL + mL
		END;
		
		(* update right edge *)
		IF sy = stopR THEN
			REPEAT
				botR := topR; 
				IF topR = n THEN topR := 0 ELSE INC(topR) END;
				dxR := x[topR] - x[botR]; dyR := y[topR] - y[botR];
				stopR := ENTIER(y[topR])
			UNTIL stopR > sy;
			mR := dxR / dyR;
			xR := x[botR] + (sy+1 - y[botR]) * mR
		ELSE
			xR := xR + mR
		END;
		
		INC(sy)
	END
END DrawPolygon;

(** draw the transparent texture polygons back to front, free TSList **)
PROCEDURE DrawTSList* (P: Pictures.Picture; ts: TSEntry);
VAR entry, last: TSEntry; x, width, height: INTEGER; baseAdr, adr, U, V, pictAdr, Vmult: LONGINT; c, bg: CHAR; u, v, us, vs: REAL;
		oldText: TextureMap;
BEGIN
	Dim3Base.SetPicture(P); V := -1000;
	oldText := NIL;
	IF ts = NIL THEN RETURN ELSE entry := ts END;
	WHILE entry # NIL DO
		u := entry.u; v := entry.v; us := entry.uStep; vs := entry.vStep;
		IF entry.texture # oldText THEN
			baseAdr := SYSTEM.VAL(LONGINT, entry.texture);
			SYSTEM.GET(baseAdr, width); baseAdr := baseAdr + 2;
			SYSTEM.GET(baseAdr, height); baseAdr := baseAdr + 2;
			SYSTEM.GET(baseAdr, bg); baseAdr := baseAdr + 1;
			oldText := entry.texture;
		END;
		pictAdr := Dim3Base.GetAddress(entry.X, entry.Y);
		
		FOR x := 1 TO entry.W DO
			U := ENTIER(u);
			IF (U >= width) OR (U < 0) THEN U := U MOD width END;
			IF (v >= (V + 1)) OR (v < V) THEN
				V := ENTIER(v);
				IF (V >=height) OR (V < 0) THEN V := V MOD height END;
				Vmult := V * LONG(width)
			END;
			adr := baseAdr + Vmult + U;
			SYSTEM.GET(adr, c);
			IF c # bg THEN 
				SYSTEM.PUT(pictAdr, c);
			END;
			INC(pictAdr);
			u := u + us;
			v := v + vs;
		END;
		last := entry;
		entry := entry.next
	END; 
	
	(* freeing of TSList to TSPool *)
	last.next := TSPool;
	TSPool := ts;
END DrawTSList;

(* draw transparent texture within polygon using the given mipmap, because a transparent texture has to be drawn 
      from back to front, the scanlines are stored in a TSEntry list. Use DrawTSList to display TSList after drawing the BSPTree *)
PROCEDURE DrawTransparent (P: Pictures.Picture; VAR ds: ARRAY OF DSEntry; texture: TextureMap; 
												VAR tsList: TSEntry; VAR x, y, u, v: ARRAY OF REAL; n: INTEGER);
VAR
	xL, xR, mL, mR, dxL, dxR, dyL, dyR, t1, t3, uR, uL, vR, vL, uStep, vStep, invW: REAL;
	sy, topY, stopL, stopR, baseAdr: LONGINT; test: BOOLEAN; 
	topL, topR, botL, botR, t, W, Y, XL, XR, width, height, w2, h2: INTEGER; entry: DSEntry;

	PROCEDURE display(P: Pictures.Picture; texture: TextureMap; X, Y, W: INTEGER; u, v: REAL);
	VAR entry: TSEntry;
	BEGIN
		AllocTSEntry(entry);
		entry.texture := texture;
		entry.X := X; entry.Y := Y; entry.W := W;
		entry.u := u; entry.v := v; entry.uStep := uStep; entry.vStep := vStep;
		entry.next := tsList;
		tsList := entry;
	END display;
	
BEGIN
	Dim3Base.SetPicture(P); DEC(n);
	
	baseAdr := SYSTEM.VAL(LONGINT, texture);
	SYSTEM.GET(baseAdr, width); INC(baseAdr, 2); w2 := width - 1;
	SYSTEM.GET(baseAdr, height); h2 := height - 1; 
		
	(* find bottommost point and highest y value *)
	botL := 0; topL := 0;
	FOR t := 1 TO n DO
		IF y[t] < y[botL] THEN botL := t END;
		IF y[t] > y[topL] THEN topL := t END
	END;
	sy := ENTIER(y[botL]) + 1;	(* initialize current scanline *)
	IF sy > ENTIER(y[topL]) THEN	(* polygon lies between scanlines *)
		RETURN
	END;
	
	topY := ENTIER(y[topL]);	(* last scanline to be considered *)
	botR := botL;
	IF botL = 0 THEN topL := n  ELSE topL := botL - 1 END;
	IF botR = n THEN topR := 0 ELSE topR := botR + 1 END;
	
	(* set up parameters for first two edges *)
	dxL := x[topL] - x[botL]; dyL := y[topL] - y[botL];
	stopL := ENTIER(y[topL]);
	WHILE stopL < sy DO
		botL := topL; 
		IF topL = 0 THEN topL := n ELSE DEC(topL) END;
		dxL := x[topL] - x[botL]; dyL := y[topL] - y[botL];
		stopL := ENTIER(y[topL])
	END;
	mL := dxL / dyL;
	xL := x[botL] + (sy - y[botL]) * mL;
	
	dxR := x[topR] - x[botR]; dyR := y[topR] - y[botR];
	stopR := ENTIER(y[topR]);
	WHILE stopR < sy DO
		botR := topR; 
		IF topR = n THEN topR := 0 ELSE INC(topR) END;
		dxR := x[topR] - x[botR]; dyR := y[topR] - y[botR];
		stopR := ENTIER(y[topR])
	END;
	mR := dxR / dyR;
	xR := x[botR] + (sy - y[botR]) * mR;
	
	IF xL <= xR THEN test := TRUE ELSE test := FALSE END;
	
	LOOP
		(* draw current scanline *)
		entry := ds[sy];
		Y := SHORT(sy);
		
		IF test THEN
			t1 := (y[topL] - sy) / (y[topL] - y[botL]);  
			t3 := u[botL] - u[topL]; uL := u[topL] + t1 * t3;
			t3 := v[botL] - v[topL]; vL := v[topL] + t1 * t3;
			t1 := (y[topR] - sy) / (y[topR] - y[botR]);  
			t3 := u[botR] - u[topR]; uR := u[topR] + t1 * t3;
			t3 := v[botR] - v[topR]; vR := v[topR]+ t1 * t3;
			XL := SHORT(ENTIER(xL)) + 1;
			XR := SHORT(ENTIER(xR));
			W := XR - XL + 1;
		ELSE
			t1 := (y[topL] - sy) / (y[topL] - y[botL]);
			t3 := u[botL] - u[topL]; uR := u[topL] + t1 * t3;
			t3 := v[botL] - v[topL]; vR := v[topL] + t1 * t3;
			t1 := (y[topR] - sy) / (y[topR] - y[botR]); 
			t3 := u[botR] - u[topR]; uL := u[topR] + t1 * t3;
			t3 := v[botR] - v[topR]; vL := v[topR]+ t1 * t3;
			XL := SHORT(ENTIER(xR)) + 1;
			XR := SHORT(ENTIER(xL));
			W := XR - XL + 1;
		END;
		uL := uL * w2; uR := uR * w2;
		vL := vL * h2; vR := vR * h2;
		invW := 1.0 / (W - 0.9999);
		uStep := (uR-uL) * invW;
		vStep := (vR - vL) * invW;
		
		(* Loop for merging *)
		LOOP
			IF W <= 0 THEN EXIT END;
			IF ~entry.active THEN
				entry := entry.next
			ELSIF XR < entry.min THEN	(* case 1 *)
				EXIT;
			ELSIF XL > entry.max THEN	(* case 8 *)
				entry := entry.next;
			ELSE
				IF XR < entry.max THEN
					IF XL <= entry.min THEN	(* case 2 *)
						display(P, texture, entry.min, Y, XR - entry.min + 1, uL + (entry.min-XL) * uStep, vL + (entry.min-XL)*vStep);
						EXIT;
					ELSE	(* case 3 *)
						display(P, texture, XL, Y, W, uL, vL);
						EXIT;
					END;
				ELSIF XR > entry.max THEN
					IF XL <= entry.min THEN	(* case 6 *)
						display(P, texture, entry.min, Y, entry.max - entry.min + 1, uL + (entry.min-XL)*uStep, vL + (entry.min-XL)*vStep);
						entry := entry.next;
					ELSE	(* case 7 *)
						display(P, texture, XL, Y, entry.max - XL + 1, uL, vL);
						entry := entry.next;
					END;
				ELSE
					IF XL <= entry.min THEN	(* case 4 *)
						display(P, texture, entry.min, Y, entry.max - entry.min + 1, uL + (entry.min-XL)*uStep, vL + (entry.min-XL)*vStep);
						EXIT;
					ELSE	(* case 5 *)
						display(P, texture, XL, Y, W, uL, vL);
						EXIT;
					END;
				END;
			END;
		END; 	(* end inner loop *)	
		
		(* exit from loop if topmost scanline has just been drawn *)
		IF sy = topY THEN EXIT END;
		
		(* update left edge *)
		IF sy = stopL THEN
			REPEAT
				botL := topL; 
				IF topL = 0 THEN topL := n ELSE DEC(topL) END;
				dxL := x[topL] - x[botL]; dyL := y[topL] - y[botL];
				stopL := ENTIER(y[topL])
			UNTIL stopL > sy;
			mL := dxL / dyL;
			xL := x[botL] + (sy+1 - y[botL]) * mL;
		ELSE
			xL := xL + mL
		END;
		
		(* update right edge *)
		IF sy = stopR THEN
			REPEAT
				botR := topR; 
				IF topR = n THEN topR := 0 ELSE INC(topR) END;
				dxR := x[topR] - x[botR]; dyR := y[topR] - y[botR];
				stopR := ENTIER(y[topR])
			UNTIL stopR > sy;
			mR := dxR / dyR;
			xR := x[botR] + (sy+1 - y[botR]) * mR;
		ELSE
			xR := xR + mR
		END;
		
		INC(sy)
	END;	(* End outer loop *)
END DrawTransparent;

(* draw texture within polygon using the given mipmap, no transparent textures *)
PROCEDURE DrawTexture (P: Pictures.Picture; VAR ds: ARRAY OF DSEntry; texture: TextureMap; 
												VAR x, y, u, v: ARRAY OF REAL; n: INTEGER);
VAR
	xL, xR, mL, mR, dxL, dxR, dyL, dyR, t1, t3, uR, uL, vR, vL, uStep, vStep, invW: REAL;
	sy, topY, stopL, stopR, baseAdr: LONGINT; test: BOOLEAN; 
	topL, topR, botL, botR, t, W, Y, XL, XR, height, width, width2, height2: INTEGER; entry: DSEntry;
	
	PROCEDURE display (P: Pictures.Picture; texture: TextureMap;  X, Y, W: INTEGER; u, v: REAL);
	VAR x: INTEGER; adr, U, V, pictAdr, Vmult: LONGINT;
	BEGIN
		pictAdr := Dim3Base.GetAddress(X, Y); V := -1000;
		FOR x := 1 TO W DO
			U := ENTIER(u);
			IF (U >= width) OR (U < 0) THEN U := U MOD width END;
			IF (v >= (V + 1)) OR (v < V) THEN
				V := ENTIER(v);
				IF (V >=height) OR (V < 0) THEN V := V MOD height END;
				Vmult := V * LONG(width);
			END;
			adr := baseAdr + Vmult + U;
			SYSTEM.MOVE(adr, pictAdr, 1);
			INC(pictAdr);
			u := u + uStep;
			v := v + vStep;
		END
	END display;
	
BEGIN
	Dim3Base.SetPicture(P); DEC(n);
	
	baseAdr := SYSTEM.VAL(LONGINT, texture);
	SYSTEM.GET(baseAdr, width); INC(baseAdr, 2); width2 := width - 1;
	SYSTEM.GET(baseAdr, height);INC(baseAdr, 3); height2 := height - 1;
	
	(* find bottommost point and highest y value *)
	botL := 0; topL := 0;
	FOR t := 1 TO n DO
		IF y[t] < y[botL] THEN botL := t END;
		IF y[t] > y[topL] THEN topL := t END
	END;
	sy := ENTIER(y[botL]) + 1;	(* initialize current scanline *)
	IF sy > ENTIER(y[topL]) THEN	(* polygon lies between scanlines *)
		RETURN
	END;
	
	topY := ENTIER(y[topL]);	(* last scanline to be considered *)
	botR := botL;
	IF botL = 0 THEN topL := n  ELSE topL := botL - 1 END;
	IF botR = n THEN topR := 0 ELSE topR := botR + 1 END;
	
	(* set up parameters for first two edges *)
	dxL := x[topL] - x[botL]; dyL := y[topL] - y[botL];
	stopL := ENTIER(y[topL]);
	WHILE stopL < sy DO
		botL := topL; 
		IF topL = 0 THEN topL := n ELSE DEC(topL) END;
		dxL := x[topL] - x[botL]; dyL := y[topL] - y[botL];
		stopL := ENTIER(y[topL])
	END;
	mL := dxL / dyL;
	xL := x[botL] + (sy - y[botL]) * mL;
	
	dxR := x[topR] - x[botR]; dyR := y[topR] - y[botR];
	stopR := ENTIER(y[topR]);
	WHILE stopR < sy DO
		botR := topR; 
		IF topR = n THEN topR := 0 ELSE INC(topR) END;
		dxR := x[topR] - x[botR]; dyR := y[topR] - y[botR];
		stopR := ENTIER(y[topR])
	END;
	mR := dxR / dyR;
	xR := x[botR] + (sy - y[botR]) * mR;
	
	IF xL <= xR THEN test := TRUE ELSE test := FALSE END;
	
	LOOP
		(* draw current scanline *)
		entry := ds[sy];
		Y := SHORT(sy);
		
		IF test THEN
			t1 := (y[topL] - sy) / (y[topL] - y[botL]);  
			t3 := u[botL] - u[topL]; uL := u[topL] + t1 * t3;
			t3 := v[botL] - v[topL]; vL := v[topL] + t1 * t3;
			t1 := (y[topR] - sy) / (y[topR] - y[botR]);  
			t3 := u[botR] - u[topR]; uR := u[topR] + t1 * t3;
			t3 := v[botR] - v[topR]; vR := v[topR]+ t1 * t3;
			XL := SHORT(ENTIER(xL)) + 1;
			XR := SHORT(ENTIER(xR));
			W := XR - XL + 1;
		ELSE
			t1 := (y[topL] - sy) / (y[topL] - y[botL]);
			t3 := u[botL] - u[topL]; uR := u[topL] + t1 * t3;
			t3 := v[botL] - v[topL]; vR := v[topL] + t1 * t3;
			t1 := (y[topR] - sy) / (y[topR] - y[botR]); 
			t3 := u[botR] - u[topR]; uL := u[topR] + t1 * t3;
			t3 := v[botR] - v[topR]; vL := v[topR]+ t1 * t3;
			XL := SHORT(ENTIER(xR)) + 1;
			XR := SHORT(ENTIER(xL));
			W := XR - XL + 1;
		END;
		uL := uL * width2; uR := uR * width2;
		vL := vL * height2; vR := vR * height2;
		invW := 1.0 / (W - 0.9999);
		uStep := (uR - uL) * invW;
		vStep := (vR - vL) * invW;
		
		(* Loop for merging *)
		LOOP
			IF W <= 0 THEN EXIT END;
			IF ~entry.active THEN
				entry := entry.next
			ELSIF XR < entry.min THEN	(* case 1 *)
				EXIT;
			ELSIF XL > entry.max THEN	(* case 8 *)
				entry := entry.next;
			ELSE
				IF XR < entry.max THEN
					IF XL <= entry.min THEN	(* case 2 *)
						display(P, texture, entry.min, Y, XR - entry.min + 1, uL + (entry.min-XL) * uStep, vL + (entry.min-XL)*vStep);
						entry.min := XR + 1;
						EXIT;
					ELSE	(* case 3 *)
						display(P, texture, XL, Y, W, uL, vL);
						SplitSegment(XL, XR, entry);
						EXIT;
					END;
				ELSIF XR > entry.max THEN
					IF XL <= entry.min THEN	(* case 6 *)
						display(P, texture, entry.min, Y, entry.max - entry.min + 1, uL + (entry.min-XL)*uStep, vL + (entry.min-XL)*vStep);
						entry.active := FALSE;
						entry := entry.next;
					ELSE	(* case 7 *)
						display(P, texture, XL, Y, entry.max - XL + 1, uL, vL);
						entry.max := XL - 1;
						entry := entry.next;
					END;
				ELSE
					IF XL <= entry.min THEN	(* case 4 *)
						display(P, texture, entry.min, Y, entry.max - entry.min + 1, uL + (entry.min-XL)*uStep, vL + (entry.min-XL)*vStep);
							entry.active := FALSE;
						EXIT;
					ELSE	(* case 5 *)
						display(P, texture, XL, Y, W, uL, vL);
						entry.max := XL - 1;
						EXIT;
					END;
				END;
			END;
		END; 	(* end inner loop *)	
		
		(* exit from loop if topmost scanline has just been drawn *)
		IF sy = topY THEN EXIT END;
		
		(* update left edge *)
		IF sy = stopL THEN
			REPEAT
				botL := topL; 
				IF topL = 0 THEN topL := n ELSE DEC(topL) END;
				dxL := x[topL] - x[botL]; dyL := y[topL] - y[botL];
				stopL := ENTIER(y[topL])
			UNTIL stopL > sy;
			mL := dxL / dyL;
			xL := x[botL] + (sy+1 - y[botL]) * mL;
		ELSE
			xL := xL + mL
		END;
		
		(* update right edge *)
		IF sy = stopR THEN
			REPEAT
				botR := topR; 
				IF topR = n THEN topR := 0 ELSE INC(topR) END;
				dxR := x[topR] - x[botR]; dyR := y[topR] - y[botR];
				stopR := ENTIER(y[topR])
			UNTIL stopR > sy;
			mR := dxR / dyR;
			xR := x[botR] + (sy+1 - y[botR]) * mR;
		ELSE
			xR := xR + mR
		END;
		
		INC(sy)
	END;	(* End outer loop *)
END DrawTexture; 

(** draw perspective correct texture polygon, if transparent = FALSE then use DrawTexture else use DrawTransparent **)
PROCEDURE DrawPersTexture* (P: Pictures.Picture; VAR ds: ARRAY OF DSEntry; texture: ARRAY OF TextureMap; numPict: INTEGER;
									sel, transparent: BOOLEAN; VAR tsList: TSEntry; VAR x, y, w, u, v: ARRAY OF REAL; col, n: INTEGER);
VAR  h, width, height: INTEGER; point1, point2, point3: Point; dummy: ARRAY 50 OF REAL; pw, ph: REAL;
	    adr, width2, height2 : LONGINT;

	PROCEDURE Test(p1, p2: Point; VAR p12: Point): BOOLEAN;
	VAR wsum, dx, dy: REAL;
	BEGIN
		wsum := p1.w + p2.w;
		p12.w := 0.5 * wsum;
		wsum := 1 / wsum;
		p12.x := (p1.w*p1.x + p2.w*p2.x) * wsum;
		p12.y := (p1.w*p1.y + p2.w*p2.y) * wsum;
		dx := p12.x - 0.5 * (p1.x + p2.x); dy := p12.y - 0.5 * (p1.y + p2.y);
		IF (dx*dx + dy*dy) < PersLimit THEN RETURN FALSE END;
		p12.u := 0.5 * (p1.u + p2.u); p12.v := 0.5 * (p1.v + p2.v);
		RETURN TRUE
	END Test;
	
	PROCEDURE Divide(p1, p2, p3: Point);
	VAR p12, p13, p23: Point; test12, test13, test23: BOOLEAN; mipmap: LONGINT;
			x, y, u, v: ARRAY 3 OF REAL; deltaX, deltaY, deltaU, deltaV: REAL;
	BEGIN
		test12 := Test(p1, p2, p12);
		test13 := Test(p1, p3, p13);
		test23 := Test(p2, p3, p23);
		
		IF test12 & test13 & test23 THEN
			Divide(p1, p12, p13); Divide(p12, p2, p23); Divide(p13, p23, p3); Divide(p12, p23, p13);
		ELSIF test12 & test23 THEN
			Divide(p12, p2, p23); Divide(p1, p23, p3); Divide(p1, p12, p23);
		ELSIF test12 & test13 THEN
			Divide(p1, p12, p13); Divide(p12, p2, p3); Divide(p13, p12, p3);
		ELSIF test23 & test13 THEN
			Divide(p13, p23, p3); Divide(p1, p2, p13); Divide(p13, p2, p23);
		ELSIF test12 THEN
			Divide(p1, p12, p3); Divide(p12, p2, p3);
		ELSIF test23 THEN
			Divide(p1, p2, p23); Divide(p1, p23, p3);
		ELSIF test13 THEN
			Divide(p13, p2, p3); Divide(p1, p2, p13);
		ELSE
			x[0] := p1.x; x[1] := p2.x; x[2] := p3.x;
			y[0] := p1.y;  y[1] := p2.y;  y[2] := p3.y;
			u[0] := p1.u; u[1] := p2.u;  u[2] := p3.u;
			v[0] := p1.v; v[1] := p2.v;  v[2] := p3.v;
			deltaX :=  (x[0] - x[1]) * (x[0] - x[1]); deltaY :=  (y[0] - y[1]) * (y[0] - y[1]);
			deltaU :=  (u[0] - u[1]) * (u[0] - u[1]) * width2; deltaV :=  (v[0] - v[1]) * (v[0] - v[1]) * height2;
			mipmap := ENTIER(Math.ln( Math.sqrt((deltaU + deltaV) / (deltaX + deltaY))) / Ln2);
			IF mipmap < 0 THEN mipmap := 0 ELSIF mipmap > (numPict - 1) THEN mipmap := numPict - 1 END;
			IF transparent THEN
				DrawTransparent(P, ds, texture[mipmap], tsList, x, y, u, v, 3);
			ELSE
				DrawTexture(P, ds, texture[mipmap], x, y, u, v, 3)
			END;
		END;
	END Divide;

	
BEGIN
	(* don't draw texture if shape is selected *)
	IF sel THEN
		DrawShadePoly(P, ds, dummy, col, FALSE, TRUE, TRUE, FALSE, FALSE, x, y, dummy, dummy, n);
		RETURN
	END;
	
	(* scale points to picture size *)
	pw := ASH(P.width, -1); ph := ASH(P.height, -1);
	FOR h := 0 TO n-1 DO
		x[h] := pw * (cheat + x[h]);
		y[h] := ph * (cheat + y[h]);
	END;
	
	adr := SYSTEM.VAL(LONGINT, texture[0]);
	SYSTEM.GET(adr, width); SYSTEM.GET(adr + 2, height);
	width2 := LONG(width) * LONG(width); height2 := LONG(height) * LONG(height); 
	
	(* divide the polygons in triangles *)
	point1.x := x[0]; point1.y := y[0]; point1.u := u[0]; point1.v := v[0]; point1.w := w[0];
	point2.x := x[1]; point2.y := y[1]; point2.u := u[1]; point2.v := v[1]; point2.w := w[1];
	FOR h := 2 TO n - 1 DO
		point3.x := x[h]; point3.y := y[h]; point3.u := u[h]; point3.v := v[h]; point3.w := w[h];
		Divide(point1, point2, point3);
		point2 := point3;
	END;
END DrawPersTexture;

(** calculate and shade the mipmaps: P is the origin picture for texture **)
PROCEDURE ShadeTexture* (P: Pictures.Picture;VAR texture: ARRAY OF TextureMap; VAR numPict: INTEGER; trans: BOOLEAN; light: REAL);
VAR   x, y, color, i, r, g, b, w, h, maxlevel, delay, c11, c12, c21, c22, w2, h2, m, n, anz, anz2, baseX, baseY: INTEGER; 
		R, G, B, adr, w1, h1, baseAdr, textAdr: LONGINT; sumR, sumG, sumB, wAlt, anz3: INTEGER;
		pictColorTab: ARRAY 3, 256 OF INTEGER; bgColor, col: CHAR;
BEGIN
	FOR i := 0 TO 255 DO
		Pictures.GetColor(P, i, r, g, b);
		pictColorTab[0][i] := r;
		pictColorTab[1][i] := g;
		pictColorTab[2][i] := b;
	END;

	w := P.width; h := P.height;
	(* set background color of shaded picture *)
	c11 := Pictures.Get(P, 0, 0); c12 := Pictures.Get(P, w-1, 0);
	c21 := Pictures.Get(P, 0, h-1); c22 := Pictures.Get(P, w-1, h-1);
	IF (c11 = c12) & (c11 = c21) & (c11 = c22) THEN
		R := ENTIER(pictColorTab[0][c11] / 255 * light * 8.99); IF R > 8 THEN R := 8 END;
		G := ENTIER(pictColorTab[1][c11] / 255 * light * 8.99); IF G > 8 THEN G := 8 END;
		B := ENTIER(pictColorTab[2][c11] / 255 * light * 4.99); IF B > 4 THEN B := 4 END;
		c11 := ColorIndex[R][G][B];
		bgColor := CHR(c11);
	ELSE 
		bgColor := CHR(Dim3Base.White);
	END;
	
	(* calc number of mipmaps to use *)
	w1 := LONG(w); h1 := LONG(h); maxlevel := 0; delay := 0;
	WHILE (w1 >= MinTexture) & (h1 >= MinTexture) & (maxlevel < 6) DO
		IF (w1 > MaxTexture) OR (h1 > MaxTexture) THEN INC(delay) ELSE INC(maxlevel) END;
		w1 := ASH(w1, -1); h1 := ASH(h1, -1);
	END;
	numPict := maxlevel;
	
	(* calc and shade first mipmap *)
	w2 := SHORT(ASH(w, -delay)); h2 := SHORT(ASH(h, -delay));
	SYSTEM.NEW(texture[0], LONG(w2)*LONG(h2) + 5); adr := SYSTEM.VAL(LONGINT, texture[0]);
	SYSTEM.PUT(adr, w2); adr := adr + 2;
	SYSTEM.PUT(adr, h2); adr := adr + 2;
	SYSTEM.PUT(adr, bgColor); adr := adr + 1;
	anz := SHORT(ASH(1, delay)); anz2 := anz * anz;
	FOR n := 0 TO h2 - 1 DO
		FOR m := 0 TO w2 - 1 DO
			baseX := m*anz; baseY := n*anz; sumR := 0; sumB := 0; sumG := 0; anz3 := anz2;
			FOR y := 0 TO anz - 1 DO
				FOR x := 0 TO anz - 1 DO
					c11 := Pictures.Get(P, baseX + x, baseY + y);
					IF  trans & (CHR(c11) = bgColor) THEN
						DEC(anz3);
					ELSE
						sumR := sumR + pictColorTab[0][c11];
						sumG := sumG + pictColorTab[1][c11];
						sumB := sumB + pictColorTab[2][c11];
					END;
				END;
			END;
			IF (anz3 > 0) & (anz3 >= (anz2 DIV 2)) THEN
				R := ENTIER((sumR / anz3)  / 255 * light * 8.99); IF R > 8 THEN R := 8 END;
				G := ENTIER((sumG / anz3) / 255 * light * 8.99); IF G > 8 THEN G := 8 END;
				B := ENTIER((sumB / anz3) / 255 * light * 4.99); IF B > 4 THEN B := 4 END;
				color := ColorIndex[R][G][B];
				SYSTEM.PUT(adr, CHR(color)); INC(adr)
			ELSE
				SYSTEM.PUT(adr, bgColor); INC(adr)
			END;
		END;
	END;
	
	(* calc the rest of the mipmaps *)
	FOR i := 1 TO maxlevel - 1 DO
		w2 := SHORT(ASH(w2, -1)); h2 := SHORT(ASH(h2, -1));
		SYSTEM.NEW(texture[i], LONG(w2)*LONG(h2) + 5); adr := SYSTEM.VAL(LONGINT, texture[i]);
		SYSTEM.PUT(adr, w2); adr := adr + 2;
		SYSTEM.PUT(adr, h2); adr := adr + 2;
		SYSTEM.PUT(adr, bgColor); adr := adr + 1;
		baseAdr := SYSTEM.VAL(LONGINT, texture[i - 1]);
		SYSTEM.GET(baseAdr, wAlt); baseAdr := baseAdr + 5;
		FOR n := 0 TO h2 - 1 DO
			textAdr := baseAdr + LONG(n) * LONG(wAlt) * 2;
			FOR m := 0 TO w2 - 1 DO
				anz2 := 4; sumR := 0; sumG := 0; sumB := 0;
				FOR x := 1 TO 2 DO
					SYSTEM.GET(textAdr, col); 
					IF  trans & (col = bgColor) THEN DEC(anz2)
					ELSE
						c11 := ORD(col);
						sumR := sumR + ColorTab[0][c11]; sumG := sumG + ColorTab[1][c11]; sumB := sumB + ColorTab[2][c11];
					END;
					SYSTEM.GET(textAdr + wAlt, col); INC(textAdr);
					IF trans & (col = bgColor) THEN DEC(anz2)
					ELSE
						c11 := ORD(col);
						sumR := sumR + ColorTab[0][c11]; sumG := sumG + ColorTab[1][c11]; sumB := sumB + ColorTab[2][c11];
					END;
				END;
				
				IF anz2 >= 2 THEN
					R := ENTIER((sumR / anz2)  / 255 * 8.99); IF R > 8 THEN R := 8 END;
					G := ENTIER((sumG / anz2) / 255  * 8.99); IF G > 8 THEN G := 8 END;
					B := ENTIER((sumB / anz2) / 255  * 4.99); IF B > 4 THEN B := 4 END;
					color := ColorIndex[R][G][B];
					SYSTEM.PUT(adr, CHR(color)); INC(adr);
				ELSE
					SYSTEM.PUT(adr, bgColor); INC(adr);
				END;
			END;
		END;
	END;
END ShadeTexture;

(* define dither patterns *)
PROCEDURE SetDitherPatterns;
BEGIN
	PatternTable[0] := NoPattern;
	PatternTable[1] := Light;
	PatternTable[2] := Middle;
	PatternTable[3] := Dark;
	
	PDots[NoPattern][0] := FALSE; PDots[NoPattern][1] := FALSE; PDots[NoPattern][2] := FALSE; PDots[NoPattern][3] := FALSE; 
	PDots[Light][0] := FALSE; PDots[Light][1] := FALSE; PDots[Light][2] := TRUE; PDots[Light][3] := FALSE;
	PDots[Middle][0] := FALSE; PDots[Middle][1] := TRUE; PDots[Middle][2] := TRUE; PDots[Middle][3] := FALSE;
	PDots[Dark][0] := FALSE; PDots[Dark][1] := TRUE; PDots[Dark][2] := TRUE; PDots[Dark][3] := TRUE;
END SetDitherPatterns;

BEGIN
	Texts.OpenWriter(T);
	DSPool := NIL; TSPool := NIL;
	seed := 1235;
	SetDitherPatterns;
END Dim3Paint.
