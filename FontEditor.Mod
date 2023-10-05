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

MODULE FontEditor;	(** portable *)
(** Dieses Modul enthält einen Editor für Fonts basierend auf Rembrandt-Editor *)

(*
	jm 28.6.95 - Fix ConvertStringtopos
*)
IMPORT SYSTEM, Files, Display, D3:=Display3, Objects, Gadgets, Input, Oberon, Rembrandt, Effects,  
				Fonts, Out, Texts, Documents, Pictures, Printer, Printer3, Desktops;

CONST
	border=1;		(* Randdicke für Fonttable *)
	tabled= 3;		(* Abstand des Ursprungs eines Characters von der unteren linken Ecke einer Zelle der Fonttable *)

	dbeg = 33;		(* in Original darstellbare Zeichen: Anfang/Ende *)
	dend = 151;

	dheight = 18;							(* Fläche für ein Character in der Fonttable *)
	dwidth = 18;

	pictupdate = 14000;				(* Fläche des Pictures, für welche das Previewframe noch updated wird *)

	undef = -1;							(* Für den entsprechenden Character sind keine Daten im Raster vorhanden; ist leer *)

	MM= 1;
	MR= 0;

	idmetricx= 0;
	idmetricy = 1;
	idmetricdx = 2;

TYPE
	RunRec = RECORD beg, end: INTEGER END;
	BoxRec = RECORD dx, x, y, w, h: INTEGER END;

	Font = POINTER TO FontDesc;						(* Fontdarstellung *)
	FontDesc = RECORD 
		type, family, variant: CHAR;
		height, minX, maxX, minY, maxY, nofRuns: INTEGER;
		pos: LONGINT;
		run: ARRAY 256 OF RunRec;
		box: ARRAY 256 OF BoxRec;
		p: ARRAY 256 OF LONGINT;
		raster: POINTER TO ARRAY OF CHAR
	END;

	Fonttable = POINTER TO FonttableDesc;			(* Tabelle für Charakterauswahl *)
	FonttableDesc= RECORD (Gadgets.FrameDesc)
									f: Font;
								 col: INTEGER 	(* für Version 1.6 *)
								END;

	Character = POINTER TO CharDesc;					(* Vergrösserte Darstellung eines Characters zum editieren *)
	CharDesc = RECORD (Rembrandt.FrameDesc)	(* Erweiterung von Rembrandt.Frame *)
								f: Font;										(* zugehöriger Font *)
								char: INTEGER;							(* dargestellter Character *)
								x, y, dx: INTEGER;						(* aktuelle Positionen der Metriken *)
								x0, y0: INTEGER;						(* Abstand des Ursprungs von der unteren linken Ecke des Pictures *)
						END;

	Preview = POINTER TO PreviewDesc;				(* Vorschau des vergrösserten zur Zeit in Bearbeitung stehenden Characters *)
	PreviewDesc = RECORD (Rembrandt.FrameDesc)
								f: Font;
								char: INTEGER
						END;

	ChangeMsg = RECORD (Display.FrameMsg) id: INTEGER; d: INTEGER; pict: Pictures.Picture END;
	StoreMsg = RECORD (Display.FrameMsg) obj: Character; pos: INTEGER END;
	SelectMsg = RECORD (Display.SelectMsg) END;

VAR
	fonttrackMM: PROCEDURE (F: Character; VAR M: Oberon.InputMsg; x, y: INTEGER);

	df: Font;	(* Defaultfont *)

	F: Files.File; R: Files.Rider;

PROCEDURE ^NewCharacter(pict: Pictures.Picture; f: Font; pos: INTEGER): Character;

PROCEDURE Min(a, b: INTEGER): INTEGER; BEGIN IF a<b THEN RETURN a ELSE RETURN b END END Min;

PROCEDURE Max(a, b: INTEGER): INTEGER; BEGIN IF a>b THEN RETURN a ELSE RETURN b END END Max;

PROCEDURE Get(F: Font; beg, w, x, y: LONGINT): BOOLEAN;
(* Gibt zurück, ob Punkt im Fontraster gesetzt ist *)
VAR ch: INTEGER; s: SET;
BEGIN
	ch := ORD(F.raster[beg + w * y + x DIV 8]);
	s := SYSTEM.VAL(SET, ch);
	RETURN x MOD 8 IN s
END Get;

PROCEDURE Put(F: Font; beg, w, x, y: LONGINT; b: BOOLEAN);
(* Setzt/löscht einen Punkt im Fontraster *)
VAR ch: INTEGER; s: SET;
BEGIN
	ch := ORD(F.raster[beg+w * y + x DIV 8]);
	s := SYSTEM.VAL(SET, ch);
	IF b THEN s := s + {x MOD 8}
	ELSE s := s - {x MOD 8}
	END;
	F.raster[beg+w * y + x DIV 8] := SYSTEM.VAL(CHAR, s);
END Put;

PROCEDURE CharOrg(F: Font; VAR x0, y0: INTEGER);
(* Gibt den Abstand des Ursprungs eines Character im Pictures von der linken unteren Ecke *)
(* Heuristik: kann irgendwie gewählt werden *)
BEGIN
	x0:= F.height DIV 4; y0:= F.height DIV 3
END CharOrg;

PROCEDURE CharDim(F: Font; sel: INTEGER; VAR dx, dy, w, h: INTEGER);
(* Liefert die Metrik eins Characters *)
CONST dh= 4;
VAR x0, y0: INTEGER;
BEGIN
	CharOrg(F, x0, y0);
	dx:= x0+F.box[sel].x; dy:= y0+F.box[sel].y;
	w:= -dx+F.maxX+Max(F.box[sel].dx, F.box[sel].w); h:= -F.minY+F.box[sel].h+dy+dh;
END CharDim;

PROCEDURE PostoString(pos: INTEGER; VAR s: ARRAY OF CHAR);
(* Wandelt eine Zahl in einen String um *)
VAR hex: ARRAY 17 OF CHAR;
BEGIN
	COPY("0123456789ABCDEF", hex);
	s[0]:= hex[pos DIV 16];
	s[1]:= hex[pos MOD 16];
	s[2]:= 0X
END PostoString;

PROCEDURE ConvertPostoString(pos: INTEGER; VAR s: ARRAY OF CHAR);
(* Wandelt einen ASCII-Code in einen String um; wird als Documentname verwendet *)
BEGIN
	IF (pos>=dbeg) & (pos<dend) THEN
		s[0]:= CHR(pos);
		s[1]:= 0X
	ELSE
		PostoString(pos, s);
	END
END ConvertPostoString;

PROCEDURE ConvertStringtoPos(s: ARRAY OF CHAR; VAR pos: INTEGER);
(* Wandelt einen String in einen entsprechenden ASCII-Code um *)
VAR i: INTEGER; hex: ARRAY 17 OF CHAR;
BEGIN
	COPY("0123456789ABCDEF", hex);
	i := 0; WHILE s[i] # 0X DO INC(i) END;
	IF i = 1 THEN
		pos:= ORD(s[0])
	ELSIF i > 1 THEN
		i := 0; WHILE (i < 16) & (s[0] # hex[i]) DO INC(i) END;
		pos := i * 16;
		i := 0; WHILE (i < 16) & (s[1] # hex[i]) DO INC(i) END;
		pos := (pos+i) MOD 256
	ELSE
		pos := undef
	END
END ConvertStringtoPos;

(** Zoomfaktor des Pictures wird erhöht *)
PROCEDURE Inc*;
CONST dz=3; maxzoom=16;
VAR doc: Documents.Document; F: Rembrandt.Frame; zoom: INTEGER;
BEGIN
	doc := Desktops.CurDoc(Gadgets.context);
	IF (doc # NIL) & (doc.dsc IS Rembrandt.Frame) THEN
		F:= doc.dsc(Rembrandt.Frame);
		Rembrandt.GetZoom(F, zoom);
		INC(zoom, dz);
		IF zoom>maxzoom THEN zoom:=maxzoom END;
		Rembrandt.SetZoom(F, zoom);
	END
END Inc;

(** Zoomfaktor des Pictures wird erniedrigt *)
PROCEDURE Dec*;
CONST dz=3;
VAR doc: Documents.Document; F: Rembrandt.Frame; zoom: INTEGER;
BEGIN
	doc := Desktops.CurDoc(Gadgets.context);
	IF (doc # NIL) & (doc.dsc IS Rembrandt.Frame) THEN
		F:= doc.dsc(Rembrandt.Frame);
		Rembrandt.GetZoom(F, zoom);
		DEC(zoom, dz);
		IF zoom<1 THEN zoom:=1 END;
		Rembrandt.SetZoom(F, zoom);
	END
END Dec;

PROCEDURE LoadDoc(D: Documents.Document);
VAR obj: Character; P: Pictures.Picture;
	x, y, w, h: INTEGER;
BEGIN
	x := 0; y := 0; w := 250; h := 200;
	NEW(P); Pictures.Create(P, w, h, 8);
	obj:= NewCharacter(P, NIL, undef);
	w := obj.pict.width; h := obj.pict.height;
	D.X := x; D.Y := y; D.W := w; D.H := h;
	Documents.Init(D, obj)
END LoadDoc;

PROCEDURE StoreDoc(D: Documents.Document);
(* VAR obj: Character; sM: StoreMsg; pos: INTEGER; *)
BEGIN
	(* obj := D.dsc(Character);
	ConvertStringtoPos(D.name, pos);
	IF pos#undef THEN
		sM.obj:= obj; sM.pos:= pos; sM.res:= -1; sM.F:= NIL; Display.Broadcast(sM)
	END *)
END StoreDoc;

(** Speichert das markierte Zeichen im zugehörigen Font ab *)
PROCEDURE StoreCharacter*;
VAR D: Documents.Document;
		obj: Character; sM: StoreMsg; pos: INTEGER;
BEGIN
	D:= Documents.MarkedDoc();
	IF D.dsc IS Character THEN
		obj := D.dsc(Character);
		ConvertStringtoPos(D.name, pos);
		IF pos#undef THEN
			sM.obj:= obj; sM.pos:= pos; sM.res:= -1; sM.F:= NIL; Display.Broadcast(sM);
			Out.String("Store "); Out.String(D.name); Out.Char("["); Out.Int(pos, 0); Out.Char("]");Out.Ln;
		END
	END
END StoreCharacter;

PROCEDURE DocHandler(D: Objects.Object; VAR M: Objects.ObjMsg);
VAR P: Pictures.Picture; R: D3.Mask;

	PROCEDURE PP(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END PP;

BEGIN
	WITH D: Documents.Document DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN M.class := Objects.String; M.s := "FontEditor.NewDoc"; M.res := 0
					ELSIF M.name = "Adaptive" THEN M.class := Objects.Bool; M.b := TRUE; M.res := 0
					ELSIF M.name = "Icon" THEN M.class := Objects.String; M.s := "Icons.Picture"; M.res := 0
					ELSE Documents.Handler(D, M)
					END
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Display.DisplayMsg THEN
			WITH M: Display.DisplayMsg DO
				IF (M.device = Display.printer) & (M.id = Display.contents) & (D.dsc # NIL) THEN (* print *)
					P := D.dsc(Character).pict;
					IF P = NIL THEN HALT(99) END;
					NEW(R); D3.Open(R); D3.Add(R, 0, 0, Printer.Width, Printer.Height);
					R.X := 0; R.Y := 0; R.W := Printer.Width; R.H := Printer.Height; R.x := 0; R.y := 0;
					Printer3.Pict(R, P, Printer.Width DIV 10, Printer.Height DIV 10 * 9 - PP(P.height), PP(P.width), PP(P.height),Display.replace);
					Printer.Page(1);
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF (M.id = Objects.get) & ((M.name = "DeskMenu") OR (M.name = "SystemMenu") OR (M.name = "UserMenu")) THEN
					M.obj := Desktops.NewMenu("FontEditor.Inc[+] FontEditor.Dec[-]"); M.res := 0
				ELSE Documents.Handler(D, M)
				END
			END
		ELSE Documents.Handler(D, M)
		END
	END
END DocHandler;

PROCEDURE OpenDoc(P: Pictures.Picture; f: Font; pos: INTEGER; name: ARRAY OF CHAR);
(* Ein Document mit dem Charactercode "pos" und Documentname "name", dargestellt im Picture, wird geöffnet *)
VAR doc: Documents.Document; zoom: INTEGER;
		obj: Character;
BEGIN
	IF f.height<=20 THEN zoom:= 16 ELSE zoom:= 7 END;	(* Vergrösserte Darstellung je nach Fontgrösse *)
	NEW(doc); doc.Load:= LoadDoc; doc.Store:= StoreDoc; doc.handle:= DocHandler;
	Objects.NewObj:= doc;
	COPY(name, doc.name);
	obj:= NewCharacter(P, f, pos);
	doc.X:= 0; doc.Y:= 0; doc.W:= obj.pict.width*zoom; doc.H:=obj.pict.height*zoom;
	Documents.Init(doc, obj);
	Rembrandt.SetZoom(obj, zoom);
	Rembrandt.SetGrid(obj, TRUE);
	Desktops.ShowDoc(doc);
	Rembrandt.SetZoom(obj, zoom);
	Rembrandt.BlockSelect
END OpenDoc;

(** Öffnet ein neues Document *)
PROCEDURE NewDoc*;
VAR D: Documents.Document;
BEGIN
	NEW(D); D.Load := LoadDoc; D.Store := StoreDoc; D.handle := DocHandler;
	D.W := 250; D.H := 200; Objects.NewObj := D
END NewDoc;

PROCEDURE DisplayChar(Q: D3.Mask; x, y: INTEGER; F: Font; pos: INTEGER);
(* Stellt einen Fonttable-Eintrag auf dem Bildschirm dar *)
CONST dt= 1;
VAR beg: LONGINT; i, j, h, w, dx, dy, wb: INTEGER; s: ARRAY 3 OF CHAR;
BEGIN
	IF (pos>=dbeg) & (pos<dend) & (F.p[pos]#undef) THEN	(* Sichtbares Zeichen ausgeben *)
		w:= F.box[pos].w; h:= F.box[pos].h; beg:= F.p[pos];
		dx:= F.box[pos].x; dy:= F.box[pos].y; wb:= (w+7) DIV 8;
		j:=0;
		WHILE j#h DO
			i:=0;
			WHILE i#w DO
				IF Get(F, beg, wb, i, j) THEN D3.Dot(Q, D3.FG, x+dx+i+dt, y+dy+j, Display.replace) END;
				INC(i)
			END;
			INC(j)
		END
	ELSE	(* Hexcode ausgeben *)
		PostoString(pos, s);
		DisplayChar(Q, x-2*dt, y, F, ORD(s[0]));
		DisplayChar(Q, x-2*dt+F.box[ORD(s[0])].dx, y, F, ORD(s[1])) 
	END
END DisplayChar;

PROCEDURE BoxesinTable(F: Font; w, h: INTEGER; VAR cw, ch: INTEGER);
(* Gibt die Anzahl Einträge der Fonttable in Höhe und Breite zurück *)
BEGIN
	cw:= (w-2*border) DIV dwidth;
	ch:= (h-2*border) DIV dheight; 
END BoxesinTable;

PROCEDURE DisplayBoxBorder(F: Font; Q: D3.Mask; x, y, w, h, pos, col0, col1: INTEGER);
(* Stellt die Box des Codes pos in der Fonttable dar mit den Farben col0, col1 als 3D-Effekt *)
VAR bw, bh, cx, cy: INTEGER; 
BEGIN
	BoxesinTable(F, w, h, bw, bh);
	cy:= y+h-border-dheight-F.minY+tabled-(pos DIV bw)*dheight;
	cx:= x+border-F.minX+tabled+(pos MOD bw)*dwidth;
	D3.Rect3D(Q, col0, col1, cx+F.minX-tabled, cy+F.minY-tabled, dwidth, dheight, 1, Display.replace);
END DisplayBoxBorder;

PROCEDURE CreateCharPict(F: Font; pos: INTEGER): Pictures.Picture;
VAR beg: LONGINT; i, j, dx, dy, pw, ph, h, w, wb: INTEGER; P: Pictures.Picture;
BEGIN
	NEW(P); 
	IF F.p[pos]#undef THEN
		w:= F.box[pos].w; h:= F.box[pos].h; beg:= F.p[pos];
		CharDim(F, pos, dx, dy, pw, ph);
		Pictures.Create(P, pw, ph, 8);
		wb:= (w+7) DIV 8;
		j:=0;
		WHILE j#h DO
			i:=0;
			WHILE i#w DO
				IF Get(F, beg, wb, i, j) THEN Pictures.Dot(P, D3.FG, dx+i, dy+j, Display.replace) END;
				INC(i)
			END;
			INC(j)
		END
	ELSE
		Pictures.Create(P, (F.maxX-F.minX+4) DIV 3*4, (F.maxY-F.minY+4) DIV 3*4, 8);
	END;
	RETURN P
END CreateCharPict;

PROCEDURE PreviewChar(F: Font; pos: INTEGER);
(* Stellt ein Character in Originalgrösse im Preview-Gadget dar *)
VAR P: Pictures.Picture;
BEGIN 
	P:= CreateCharPict(F, pos);
	Pictures.Update(P, 0, 0, P.width, P.height);
END PreviewChar;

PROCEDURE RestoreTable(F: Fonttable; Q: D3.Mask; x, y, w, h: INTEGER);
VAR pos, sx, sy, xb, yb, maxx, maxy: INTEGER;
BEGIN
	D3.FilledRect3D(Q, D3.bottomC, D3.topC, F.col, x, y, w, h, border, Display.replace); 
(*	IF F.f#NIL THEN *)
		BoxesinTable(df, w, h, maxx, maxy);
		pos:= 0; sx:= x+border-df.minX+tabled; sy:= y+h-border-dheight-df.minY+tabled; xb:=0; yb:=0;
		WHILE (pos#256) & (yb#maxy) DO
			D3.FilledRect3D(Q, D3.topC, D3.bottomC, D3.upC, sx+df.minX-tabled, sy+df.minY-tabled, dwidth, dheight, 1, Display.replace);
			DisplayChar(Q, sx, sy, df, pos);
			INC(pos); sx:= sx+dwidth;
			INC(xb); IF xb=maxx THEN xb:=0; sx:= x+border-df.minX+tabled; sy:= sy-dheight; INC(yb) END;
		END;
(*	END; 	*)
  IF Gadgets.selected IN F.state THEN
    D3.FillPattern(Q, D3.white, D3.selectpat, x, y, x, y, w, h, Display.paint)	(* Version 1.6 *)
  END	
END RestoreTable;

PROCEDURE Selected(F: Font; x, y, w, h, mx, my: INTEGER): INTEGER;
(* Gibt selektierte Character-Code zurück anhand Ausmass der Fonttable *)
VAR bw, bh, cx, cy: INTEGER;
BEGIN
	BoxesinTable(F, w, h, bw, bh);
	cy:= (y+h-my) DIV dheight; IF cy>bh-1 THEN cy:=bh-1 ELSIF cy<0 THEN RETURN undef END;
	cx:= (mx-x-border) DIV dwidth; IF cx>bw-1 THEN cx:= bw-1 ELSIF cx<0 THEN RETURN undef END;
	IF (cx+cy*bw)>255 THEN RETURN undef ELSE RETURN (cx+cy*bw) END;
END Selected;

PROCEDURE OpenCharDoc(F: Fonttable; sel: INTEGER);
VAR P: Pictures.Picture;
		string: ARRAY 32 OF CHAR;
BEGIN
	P:= CreateCharPict(F.f, sel);
	ConvertPostoString(sel, string);
	OpenDoc(P, F.f, sel, string);
END OpenCharDoc;

PROCEDURE SelectChar(F: Fonttable; Q: D3.Mask; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
VAR pos, oldpos: INTEGER; keysum: SET;
BEGIN
	pos:=Selected(df, x, y, w, h, M.X, M.Y); oldpos:= pos;
	Oberon.FadeCursor(Oberon.Mouse);
	IF pos#undef THEN
		DisplayBoxBorder(df, Q, x, y, w, h, pos, D3.bottomC, D3.topC);
		IF F.f#NIL THEN PreviewChar(F.f, pos) END;
	END;
	keysum:= M.keys;
	REPEAT
		Oberon.DrawCursor(Oberon.Mouse, Oberon.Mouse.marker, M.X, M.Y);
		WHILE ~Effects.Inside(M.X, M.Y, x, y, w, h) & (M.keys#{})DO
			Input.Mouse(M.keys, M.X, M.Y); keysum := keysum + M.keys;
			Oberon.DrawCursor(Oberon.Mouse, Oberon.Mouse.marker, M.X, M.Y);
		END;
		IF oldpos#pos THEN
			Oberon.FadeCursor(Oberon.Mouse);
			IF oldpos#undef THEN DisplayBoxBorder(df, Q, x, y, w, h, oldpos, D3.topC, D3.bottomC) END;
			IF pos#undef THEN
				DisplayBoxBorder(df, Q, x, y, w, h, pos, D3.bottomC, D3.topC);
				IF F.f#NIL THEN PreviewChar(F.f, pos) END
			END
		END;
		Input.Mouse(M.keys, M.X, M.Y);
		oldpos:= pos;
		pos:=Selected(df, x, y, w, h, M.X, M.Y);
		keysum := keysum + M.keys;
	UNTIL  M.keys = {};
	Oberon.FadeCursor(Oberon.Mouse);
	IF oldpos#undef THEN DisplayBoxBorder(df, Q, x, y, w, h, oldpos, D3.topC, D3.bottomC) END;
	IF (keysum#{0, 1, 2}) & Effects.Inside(M.X, M.Y, x, y, w, h) & (F.f#NIL) THEN
		pos:=Selected(df, x, y, w, h, M.X, M.Y);
		IF pos#undef THEN OpenCharDoc(F, pos) END;
	END
END SelectChar;

PROCEDURE CopyTable(VAR M: Objects.CopyMsg; from, to: Fonttable);
BEGIN
	Gadgets.CopyFrame(M, from, to);
	to.f^:= from.f^; to.col := from.col
END CopyTable;

PROCEDURE StoreChar(F: Fonttable; M: StoreMsg; fx, fy, fw, fh: INTEGER);
VAR i, j: LONGINT; x, y, x0, x1, y0, y1, w, h, d, nob, actnob, sel, nminx, nminy, nmaxx, nmaxy: INTEGER;
		P: Pictures.Picture; f: Font;
BEGIN
	f:= F.f;
	P:= M.obj.pict; x0:=MAX(INTEGER); x1:=0; y0:= MAX(INTEGER); y1:=0;
	FOR y:=0 TO P.height-1 DO
		FOR x:=0 TO P.width-1 DO
			IF Pictures.Get(P, x, y)# 0 THEN
				x0:= Min(x0, x); x1:= Max(x1, x);
				y0:= Min(y0, y); y1:= Max(y1, y);
			END
		END
	END;
	sel:= M.pos; 
	IF x0=MAX(INTEGER) THEN	(* Character gelöscht *)
		f.box[sel].dx:= M.obj.dx; f.box[sel].x:= 0; f.box[sel].y:= 0;
		f.box[sel].w:= 0; f.box[sel].h:= 0;
	ELSE
		w:= x1-x0+1;			(* Breite und Höhe des Characters berechnen *)
		h:= y1-y0+1;
		nob:= ((w+7) DIV 8 )*h;
		actnob:= ((f.box[sel].w+7) DIV 8)* f.box[sel].h;
		d:= nob-actnob;		(* Mehr oder weniger (+-d) Rasterdaten für Character nötig => Raster shiften *)
		IF (d#0) & (f.p[sel]#undef) THEN
			i:= sel+1; WHILE (i<=255) & (f.p[i]=undef) DO INC(i) END;
			IF i#256 THEN	(* Shift *)
				IF d>0 THEN	(* Rightshift *)
					FOR j:= f.pos-1 TO f.p[i] BY -1 DO f.raster[j+d]:= f.raster[j] END
				ELSE				(* Leftshift *)
					FOR j:= f.p[i] TO f.pos-1 DO f.raster[j+d]:= f.raster[j] END
				END;
				j:= sel+1;
				WHILE j<256 DO IF f.p[j]#undef THEN f.p[j]:= f.p[j]+d END; INC(j) END	(* Pointer in Raster nachführen *)
			END;
			f.pos:= f.pos+d;
		ELSIF f.p[sel]=undef THEN
			f.p[sel]:= f.pos; f.pos:= f.pos+d
		END;
		f.box[sel].dx:= -M.obj.x+M.obj.dx; f.box[sel].x:= x0-M.obj.x0-M.obj.x; f.box[sel].y:= y0-M.obj.y0-M.obj.y;	(* Metrik aktualisieren *)
		f.box[sel].w:= w; f.box[sel].h:= h; 
		y:= y0; j:=0; d:= (f.box[sel].w+7) DIV 8; 
		WHILE y<= y1 DO
			x:= x0; i:=0;
			WHILE x<= x1 DO
				IF Pictures.Get(P, x, y)#0 THEN
					Put(f, f.p[sel], d, i, j, TRUE)
				ELSE
					Put(f, f.p[sel], d, i, j, FALSE)
				END;
				INC(x); INC(i)
			END;
			INC(y); INC(j);
		END;
	END;
	nminy:= MAX(INTEGER); nmaxy:= 0; nminx:= MAX(INTEGER); nmaxx:= 0;
	FOR i:= 0 TO 255 DO
		IF f.p[i]#undef THEN
			nminy:= Min(nminy, f.box[i].y); nmaxy:= Max(nmaxy, f.box[i].y+f.box[i].h);
			nminx:= Min(nminx, f.box[i].x); nmaxx:= Max(nmaxx, f.box[i].x+f.box[i].w);
		END
	END;
	IF (nminy#f.minY) OR (nmaxy#f.maxY) OR (nminx#f.minX) OR (nmaxx#f.maxX) THEN
		f.minY:= nminy; f.maxY:= nmaxy; f.minX:= nminx; f.maxX:= nmaxx; f.height:= f.maxY-f.minY;
	END
END StoreChar;

PROCEDURE FtAttributes (F: Fonttable; VAR M: Objects.AttrMsg);
BEGIN
  IF M.id = Objects.get THEN
    IF M.name = "Gen" THEN
      M.class := Objects.String; COPY("FontEditor.NewFonttable", M.s); M.res := 0
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
END FtAttributes;

PROCEDURE HandleFonttable(F: Objects.Object; VAR M: Objects.ObjMsg);
  VAR x, y, w, h: INTEGER; F1: Fonttable; Q: D3.Mask;
BEGIN
	WITH F: Fonttable DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN 
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
					IF M IS  Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									RestoreTable(F, Q, x, y, w, h)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									D3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreTable(F, Q, x, y, w, h)
								END
							ELSIF M.device = Display.printer THEN
								Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) & (M.keys = {MM}) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, Q);
								SelectChar(F, Q, x, y, w, h, M); M.res := 0;
							ELSE
								Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS StoreMsg THEN
						WITH M: StoreMsg DO
							IF M.obj.f=F.f THEN
								StoreChar(F, M, x, y, w, h); M.res:= 0
							END
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
		ELSIF M IS Gadgets.UpdateMsg THEN
			WITH M: Gadgets.UpdateMsg DO
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
				Gadgets.MakeMask(F, x, y, M.dlink, Q);
				RestoreTable(F, Q, x, y, w, h)
			END
		ELSIF M IS Objects.AttrMsg THEN FtAttributes(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO Gadgets.framehandle(F, M) END
		ELSIF M IS Objects.CopyMsg THEN
		 	WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink (*non-first arrival*)
				ELSE (*first arrival*)
					NEW(F1); F.stamp := M.stamp; F.dlink := F1;
					CopyTable(M, F, F1); M.obj := F1
				END
			END
		ELSE
			Gadgets.framehandle(F, M)
		END
	END
END HandleFonttable;

(* Character *)

PROCEDURE CopyCharacter(VAR M: Objects.CopyMsg; from, to: Character);
BEGIN
	Rembrandt.Copy(M, from, to);
	to.char:= from.char;
	to.f:= from.f;
	to.dx:= from.dx;
	to.x:= from.x; to.y:= from.y;
	to.x0:= from.x0; to.y0:= from.y0
END CopyCharacter;

PROCEDURE MarkedChar(): Character;
VAR doc: Documents.Document;
BEGIN
	doc:= Documents.MarkedDoc();
	IF (doc#NIL ) & (doc.dsc#NIL) & (doc.dsc IS Character) THEN
		RETURN doc.dsc(Character)
	ELSE 
		RETURN NIL
	END 
END MarkedChar;

PROCEDURE GetSelectedChar(VAR f:Character; VAR x, y, w, h: INTEGER);
VAR M: SelectMsg; 
BEGIN
	M.id:= Display.get; M.time:=0; M.F:= NIL; M.obj:= NIL;
	Display.Broadcast(M);
	IF M.time>0 THEN
		f:=M.sel(Character); x:= f.sx; y:= f.sy; w:= f.sw; h:= f.sh
	ELSE
		f:=MarkedChar(); IF f#NIL THEN x:=0; y:=0; w:= f.pict.width;h:= f.pict.height END;
	END
END GetSelectedChar;

PROCEDURE HandlePixel(F: Character; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR keysum: SET; px, py, opx, opy: INTEGER; set: BOOLEAN;
BEGIN
	keysum := M.keys;
	Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
	IF Pictures.Get(F.pict, px, py)=D3.BG THEN
		Pictures.Dot(F.pict, D3.FG, px, py, Display.replace); set:= TRUE
	ELSE
		Pictures.Dot(F.pict, D3.BG, px, py, Display.replace); set:= FALSE
	END;
	Pictures.Update(F.pict, px, py, 1, 1);
	opx:= px; opy:= py;
	REPEAT
		Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, M.X, M.Y);
		IF (opx#px) OR (opy#py) THEN
			IF Effects.Inside(px, py, 0, 0, F.pict.width, F.pict.height) THEN
				IF set THEN Pictures.Dot(F.pict, D3.FG, px, py, Display.replace) ELSE Pictures.Dot(F.pict, 0, px, py, Display.replace) END;
				Pictures.Update(F.pict, px, py, 1, 1);
			END
		END;
		Input.Mouse(M.keys, M.X, M.Y);
		opx:= px; opy:= py;
		Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
		keysum := keysum + M.keys
	UNTIL M.keys = {};
	M.keys:= keysum
END HandlePixel;

PROCEDURE DrawMetricLines(F: Character; Q: D3.Mask; x, y: INTEGER);
VAR sx, sy,  zoom, d: INTEGER;
BEGIN
	Rembrandt.GetZoom(F, zoom);
	IF zoom#1 THEN
		IF zoom<5 THEN d:= 1 ELSE d:= 2 END;
		Rembrandt.PicttoScreen(F, x, y, 0,  F.y0+F.y, sx, sy);									(* Baseline *)
		D3.ReplConst(Q, D3.red, sx, sy, F.pict.width*zoom, d, Display.replace);
		Rembrandt.PicttoScreen(F, x, y, F.x0+F.x,  0, sx, sy);									(* Backline *)
		D3.ReplConst(Q, D3.red, sx, sy, d, F.pict.height*zoom, Display.replace);
		Rembrandt.PicttoScreen(F, x, y, F.x0+F.dx,  0, sx, sy);								(* Dx-Line *)
		D3.ReplConst(Q, D3.blue, sx, sy, d, F.pict.height*zoom, Display.replace)
	END
END DrawMetricLines;

PROCEDURE HandleMetric(F: Character; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR px, py: INTEGER; keysum: SET; opx, opy, old: INTEGER;  cM: ChangeMsg; zoom: INTEGER; Q: D3.Mask;
BEGIN
	Rembrandt.GetZoom(F, zoom);
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	IF zoom#1 THEN
	Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
	IF py= F.y0+F.y THEN	(* select Baseline *)
		opx:=px; opy:= py; old:= F.y;
		keysum:= M.keys;
		REPEAT
			Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, M.X, M.Y);
			IF py<0 THEN py:=0
			ELSIF py>=F.pict.height THEN py:=F.pict.height-1
			END;
			IF opy#py THEN
				F.y:= py-F.y0;
				Oberon.FadeCursor(Oberon.Mouse);
				Rembrandt.RestorePict(F, Q, x, y, F.W, F.H, 0, opy, F.pict.width, 1);
				D3.AdjustMask(Q, x+1, y+1, F.W-2, F.H-2);
				DrawMetricLines(F, Q, x, y)
			END;
			opx:= px; opy:= py;
			Input.Mouse(M.keys, M.X, M.Y);
			Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
			keysum := keysum + M.keys
		UNTIL M.keys = {};
		IF keysum#{0, 1, 2} THEN
			cM.id:= idmetricy; cM.pict:= F.pict;
			cM.res:=-1; cM.F:= NIL; cM.d:= F.y; Display.Broadcast(cM)
		ELSE
			F.y:= old; Gadgets.Update(F);
		END;
		M.keys:= keysum
	ELSIF px=F.x0+F.x THEN	(* select Backline *)
		opx:=px; opy:= py; old:= F.x;
		keysum:= M.keys;
		REPEAT
			Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, M.X, M.Y);
			IF px<0 THEN px:=0
			ELSIF px>=F.pict.width THEN px:= F.pict.width-1
			END;
			IF opx#px THEN
				F.x:= px-F.x0;
				Oberon.FadeCursor(Oberon.Mouse);
				Rembrandt.RestorePict(F, Q, x, y, F.W, F.H, opx, 0, 1, F.pict.height);
				D3.AdjustMask(Q, x+1, y+1, F.W-2, F.H-2);
				DrawMetricLines(F, Q, x, y)
			END;
			opx:= px; opy:= py;
			Input.Mouse(M.keys, M.X, M.Y);
			Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
			keysum := keysum + M.keys
		UNTIL M.keys = {};
		IF keysum#{0, 1, 2} THEN
			cM.id:= idmetricx; cM.pict:= F.pict;
			cM.res:=-1; cM.F:= NIL; cM.d:= F.x; Display.Broadcast(cM)
		ELSE
			F.x:= old; Gadgets.Update(F)
		END;
		M.keys:= keysum
	ELSIF px=F.x0+F.dx THEN	(* select Dx-Line *)
		opx:=px; opy:= py; old:= F.dx;
		keysum:= M.keys;
		REPEAT
			Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, M.X, M.Y);
			IF px<0 THEN px:=0
			ELSIF px>=F.pict.width THEN px:= F.pict.width-1
			END;
			IF opx#px THEN
				F.dx:= px-F.x0;
				Oberon.FadeCursor(Oberon.Mouse);
				Rembrandt.RestorePict(F, Q, x, y, F.W, F.H, opx, 0, 1, F.pict.height);
				D3.AdjustMask(Q, x+1, y+1, F.W-2, F.H-2);
				DrawMetricLines(F, Q, x, y)
			END;
			opx:= px; opy:= py;
			Input.Mouse(M.keys, M.X, M.Y);
			Rembrandt.ScreentoPict(F, x, y, M.X, M.Y, px, py);
			keysum := keysum + M.keys
		UNTIL M.keys = {};
		IF keysum#{0, 1, 2} THEN
			cM.id:= idmetricdx; cM.pict:= F.pict;
			cM.res:=-1; cM.F:= NIL; cM.d:= F.dx; Display.Broadcast(cM)
		ELSE
			F.dx:= old; Gadgets.Update(F)
		END;
		M.keys:= keysum
	END;
	END;
	Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, M.X, M.Y); M.res:=0
END HandleMetric;

PROCEDURE HandleCharacter(F: Objects.Object; VAR M: Objects.ObjMsg);
  VAR x, y, w, h: INTEGER; F1: Character; Q: D3.Mask;
BEGIN
	WITH F: Character DO
	IF M IS Display.FrameMsg THEN
		WITH M: Display.FrameMsg DO
			IF (M.F = NIL) OR (M.F = F) THEN (* message addressed to box *)
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
				IF M IS Oberon.InputMsg THEN
					WITH M: Oberon.InputMsg DO
     			       IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) THEN
							IF (M.keys = {MM}) & Rembrandt.InsidePict(F, M.X, M.Y, x, y) & (F.selection=Rembrandt.No) THEN
								fonttrackMM(F, M, x, y); M.res:=0;
							ELSIF M.keys= {MR} THEN
								Rembrandt.selcolor:= 3;
								Rembrandt.TrackSelection(F, M, x, y, w, h);
							ELSE
								Rembrandt.Handle(F, M)
							END	
						ELSE 
							Rembrandt.Handle(F, M)
						END
					END
				ELSIF M IS ChangeMsg THEN
					WITH M: ChangeMsg DO
						IF F.pict=M.pict THEN
							Gadgets.MakeMask(F, x, y, M.dlink, Q);
							IF M.id= idmetricx THEN
								Rembrandt.RestorePict(F, Q, x, y, w, h, F.x0+F.x, 0, 1, F.pict.height);
								Rembrandt.RestorePict(F, Q, x, y, w, h, F.x0+M.d, 0, 1, F.pict.height);
								F.x:= M.d
							ELSIF M.id = idmetricy THEN
								Rembrandt.RestorePict(F, Q, x, y, w, h, 0, F.y0+F.y, F.pict.width, 1);
								Rembrandt.RestorePict(F, Q, x, y, w, h, 0, F.y0+M.d, F.pict.width, 1);
								F.y:= M.d
							ELSE
								Rembrandt.RestorePict(F, Q, x, y, w, h, F.x0+F.dx, 0, 1, F.pict.height);
								Rembrandt.RestorePict(F, Q, x, y, w, h, F.x0+M.d, 0, 1, F.pict.height);
								F.dx:= M.d
							END;
							D3.AdjustMask(Q, x+1, y+1, w-2, h-2);
							DrawMetricLines(F, Q, x, y)
						END
					END
				ELSIF M IS Display.DisplayMsg THEN
					Rembrandt.Handle(F, M);
					IF M(Display.DisplayMsg).device = Display.screen THEN
						Gadgets.MakeMask(F, x, y, M.dlink, Q);
						D3.AdjustMask(Q, x+1, y+1, w-2, h-2);
						DrawMetricLines(F, Q, x, y)
					END
				ELSIF M IS Pictures.UpdateMsg THEN
					WITH M: Pictures.UpdateMsg DO
						Rembrandt.Handle(F, M);
						IF M.pict= F.pict THEN
							Gadgets.MakeMask(F, x, y, M.dlink, Q);
							D3.AdjustMask(Q, x+1, y+1, w-2, h-2);
							DrawMetricLines(F, Q, x, y)
						END;
					END
				ELSE
					Rembrandt.Handle(F, M);
				END
			END
		END
	ELSIF M IS Objects.CopyMsg THEN
		WITH M: Objects.CopyMsg DO
			IF M.stamp = F.stamp THEN M.obj := F.dlink (*non-first arrival*)
			ELSE (*first arrival*)
				NEW(F1); F.stamp := M.stamp; F.dlink := F1;
				CopyCharacter(M, F, F1); M.obj := F1
			END
		END
	ELSE	  
		Rembrandt.Handle(F, M)
	END
	END
END HandleCharacter;

(* Preview *)

PROCEDURE CopyPreview(VAR M: Objects.CopyMsg; from, to: Preview);
BEGIN
	Rembrandt.Copy(M, from, to);
	to.char:= from.char;
	to.f:= from.f;
END CopyPreview;

PROCEDURE PreviewAttributes (F: Preview; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN
			M.class := Objects.String; COPY("FontEditor.NewPreview", M.s); M.res := 0
		ELSE
			Rembrandt.FrameAttributes(F, M)
		END
	ELSE
		Rembrandt.FrameAttributes(F, M)
	END
END PreviewAttributes;

PROCEDURE HandlePreview(F: Objects.Object; VAR M: Objects.ObjMsg);
  VAR F1: Preview;
BEGIN
	WITH F: Preview DO
	IF M IS Display.FrameMsg THEN
		WITH M: Display.FrameMsg DO
			IF (M.F = NIL) OR (M.F = F) THEN (* message addressed to box *)
				IF M IS Pictures.UpdateMsg THEN
					WITH M: Pictures.UpdateMsg DO
						IF F.pict#M.pict THEN
							IF LONG(M.pict.width)*M.pict.height <pictupdate THEN
								F.pict:= M.pict;
								Gadgets.Update(F); (* Gadgets.Update(F.pict); *)
							END
						ELSE
							Rembrandt.Handle(F, M)
						END	
					END
				ELSIF M IS ChangeMsg THEN
				ELSE
					Rembrandt.Handle(F, M)
				END
			END
		END
	ELSIF M IS Objects.AttrMsg THEN PreviewAttributes(F, M(Objects.AttrMsg))
	ELSIF M IS Objects.CopyMsg THEN
		WITH M: Objects.CopyMsg DO
			IF M.stamp = F.stamp THEN M.obj := F.dlink (*non-first arrival*)
			ELSE (*first arrival*)
				NEW(F1); F.stamp := M.stamp; F.dlink := F1;
				CopyPreview(M, F, F1); M.obj := F1
			END
		END
	ELSE	  
		Rembrandt.Handle(F, M)
	END
	END
END HandlePreview;

(* Teststring *)

PROCEDURE ShowTeststring*;
VAR obj: Objects.Object; len: INTEGER; f: Font; teststring: ARRAY 64 OF CHAR;
		beg: LONGINT;
		pw, ph, i, j, k, sel, w, h, dx, dy, wb, x, y: INTEGER;
		P: Pictures.Picture;
		doc: Documents.Document;
		F: Rembrandt.Frame;
		S: Texts.Scanner; 
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Name THEN COPY(S.s, teststring) ELSE teststring:= "" END;
	pw:=0;
	obj := Gadgets.FindObj(Gadgets.context, "table");
	IF obj#NIL THEN
		f:= obj(Fonttable).f;
		len:= 0;
		WHILE teststring[len]#0X DO pw:= pw+f.box[ORD(teststring[len])].dx; INC(len) END; 
		ph:= f.maxY-f.minY; 
		NEW(P); Pictures.Create(P, pw, ph, 8);
		x:= -f.minX; y:= -f.minY;
		FOR k:= 0 TO len-1 DO
			sel:= ORD(teststring[k]);
			IF f.p[sel]#undef THEN
				w:= f.box[sel].w; h:= f.box[sel].h; beg:= f.p[sel];
				dx:= f.box[sel].x; dy:= f.box[sel].y; wb:= (w+7) DIV 8;
				j:=0;
				WHILE j#h DO
					i:=0;
					WHILE i#w DO
						IF Get(f, beg, wb, i, j) THEN Pictures.Dot(P, D3.FG, x+dx+i, y+dy+j, Display.replace) END;
						INC(i)
					END;
					INC(j)
				END;
				x:= x+ f.box[sel].dx
			END;
		END;	(* Document öffnen *)
		NEW(doc); doc.Load:= LoadDoc; doc.Store:= StoreDoc; doc.handle:= DocHandler;
		Objects.NewObj:= doc;
		NEW(F); 
		Rembrandt.NewP(F, P);
		doc.X:= 0; doc.Y:= 0; doc.W:= F.pict.width*16; doc.H:=F.pict.height*16;
		Documents.Init(doc, F);
		Rembrandt.SetZoom(F, 10);
		Desktops.ShowDoc(doc);
		Rembrandt.SetGrid(F,  TRUE);
	END
END ShowTeststring;

(** Flip horizontal/verticaL *)
PROCEDURE FlipH*;
VAR x, sx, sy, sw, sh: INTEGER; f: Character; P: Pictures.Picture; s: ARRAY 32 OF CHAR;
		obj: Objects.Object; M: Objects.AttrMsg;
BEGIN
	obj:= Gadgets.FindObj(Gadgets.context, "newviewer");
	IF obj#NIL THEN
		M.id:= Objects.get; M.name:= "Value"; M.class:= Objects.Bool; M.res:=-1;
		obj.handle(obj, M);
	ELSE
		M.b:= TRUE
	END;
	GetSelectedChar(f, sx, sy, sw, sh);
	IF f#NIL THEN
		NEW(P); Pictures.Create(P, sw, sh, f.pict.depth);
		x:=sx;
		WHILE x < sx+sw DO
			Pictures.CopyBlock(f.pict, P, x, sy, 1, sh, sx+sw-x-1, 0, Display.replace);
			INC(x)
		END;
		IF M.b THEN
			ConvertPostoString(f.char, s);
			OpenDoc(P, f.f, f.char, s)
		ELSE
			Pictures.CopyBlock(P, f.pict, 0, 0, sw, sh, sx, sy, Display.replace);
			Pictures.Update(f.pict, sx, sy, sw, sh)
		END
	END
END FlipH;

PROCEDURE FlipV*;
VAR y, sx, sy, sw, sh: INTEGER; f: Character; P: Pictures.Picture; s: ARRAY 32 OF CHAR;
		obj: Objects.Object; M: Objects.AttrMsg;
BEGIN
	obj:= Gadgets.FindObj(Gadgets.context, "newviewer");
	IF obj#NIL THEN
		M.id:= Objects.get; M.name:= "Value"; M.class:= Objects.Bool; M.res:=-1;
		obj.handle(obj, M);
	ELSE
		M.b:= TRUE
	END;
	GetSelectedChar(f, sx, sy, sw, sh);
	IF f#NIL THEN
		NEW(P); Pictures.Create(P, sw, sh, f.pict.depth);
		y:=sy;
		WHILE y< sy+sh DO
			Pictures.CopyBlock(f.pict, P, sx, y, sw, 1, 0, sy+sh-y-1, Display.replace);
			INC(y)
		END;
		IF M.b THEN
			ConvertPostoString(f.char, s);
			OpenDoc(P, f.f, f.char, s)
		ELSE
			Pictures.CopyBlock(P, f.pict, 0, 0, sw, sh, sx, sy, Display.replace);
			Pictures.Update(f.pict, sx, sy, sw, sh);
		END
	END
END FlipV;

(** Turn 90 Degrees *)
PROCEDURE Turn*;
VAR P, S, D: Pictures.Picture; f: Character; x, y, col, u, sx, sy, sw, sh: INTEGER; s: ARRAY 32 OF CHAR;
		obj: Objects.Object; M: Objects.AttrMsg;
BEGIN
	obj:= Gadgets.FindObj(Gadgets.context, "newviewer");
	IF obj#NIL THEN
		M.id:= Objects.get; M.name:= "Value"; M.class:= Objects.Bool; M.res:=-1;
		obj.handle(obj, M);
	ELSE
		M.b:= TRUE
	END;
	GetSelectedChar(f, sx, sy, sw, sh);
	IF f#NIL THEN
		P:= f.pict;  
		NEW(S); Pictures.Create(S, sw, sh, P.depth);
		Pictures.CopyBlock(P, S, sx, sy, sw, sh, 0, 0, Display.replace);
		NEW(D); Pictures.Create(D, Max(P.height, P.width), Max(P.height, P.width), P.depth);
		y:=0;
		WHILE y< sh DO
			x:=0;
			WHILE x<sw DO
				u:= x; Pictures.GetRun(S, col, x, y);
				IF col#D3.BG THEN Pictures.ReplConst(D, col, sy+sh-1-y, sx+u, 1, x-u, Display.replace) END;
			END;
			INC(y)
		END;
		IF M.b THEN
			ConvertPostoString(f.char, s);
			OpenDoc(D, f.f, f.char, s)
		ELSE
			Pictures.CopyBlock(D, P, 0, 0, D.width, D.height, sx, sy, Display.replace);
			Pictures.Update(P, sx, sy, D.width, D.height)
		END;
	END
END Turn;

(** Neue Gadgets *)
PROCEDURE NewFonttable*;
VAR F: Fonttable;
BEGIN
	NEW(F); F.handle:= HandleFonttable; F.f:= NIL; F.W:= 100; F.H:= 100; F.col:= D3.upC;
	Objects.NewObj := F
END NewFonttable;

PROCEDURE NewCharacter(pict: Pictures.Picture; f: Font; pos: INTEGER): Character;
VAR F: Character;
BEGIN
	NEW(F); Rembrandt.NewP(F, pict); 
	F.handle:= HandleCharacter; F.f:= f; F.char:= pos;
	F.dx:= f.box[pos].dx; F.x:= 0; F.y:= 0;
	CharOrg(f, F.x0, F.y0);
	RETURN F
END NewCharacter;

PROCEDURE NewPreview*;
VAR F: Preview; P: Pictures.Picture;
BEGIN
	NEW(F); NEW(P); Pictures.Create(P, 50, 50, 8) ; Rembrandt.NewP(F, P);
	F.handle:= HandlePreview; F.f:= NIL; F.char:= undef; F.col:= D3.BG; Objects.NewObj:= F
END NewPreview;

(* Load/Store Font *)

PROCEDURE LoadFont(VAR F: Font; VAR R: Files.Rider);
VAR bitW, bitH: LONGINT; k, l, i: INTEGER; type: CHAR;
BEGIN F := NIL;
	Files.Read(R, type);
	IF type = 0DBX THEN NEW(F);
		Files.Read(R, F.type); 
		Files.Read(R, F.family); 
		Files.Read(R, F.variant); 
		Files.ReadInt(R, F.height); 
		Files.ReadInt(R, F.minX); 
		Files.ReadInt(R, F.maxX); 
		Files.ReadInt(R, F.minY); 
		Files.ReadInt(R, F.maxY); 
		Files.ReadInt(R, F.nofRuns); 
	(*
		Out.String("type = "); Out.Int(ORD(F.type), 0); Out.Ln;
		Out.String("family = "); Out.Int(ORD(F.family), 0); Out.Ln;
		Out.String("variant = "); Out.Int(ORD(F.variant), 0); Out.Ln;
		Out.String("height = "); Out.Int(F.height, 0); Out.Ln;
		Out.String("minX = "); Out.Int(F.minX, 0); Out.Ln;
		Out.String("maxX = "); Out.Int(F.maxX, 0); Out.Ln;
		Out.String("minY = "); Out.Int(F.minY, 0); Out.Ln;
		Out.String("maxY = "); Out.Int(F.maxY, 0); Out.Ln;
	*)
		k := 0;
		WHILE k # F.nofRuns DO
			Files.ReadInt(R, F.run[k].beg); Files.ReadInt(R, F.run[k].end);
			INC(k)
		END;

		l := 0; bitW := 0;
		WHILE l # 256 DO
			k:=0;
			WHILE (k#F.nofRuns) & ~((F.run[k].beg<=l) & (F.run[k].end>l)) DO INC(k) END;
			IF k#F.nofRuns THEN
				Files.ReadInt(R, F.box[l].dx);
				Files.ReadInt(R, F.box[l].x); Files.ReadInt(R, F.box[l].y);
				Files.ReadInt(R, F.box[l].w); Files.ReadInt(R, F.box[l].h);
				bitW := bitW + (F.box[l].w + 7) DIV 8;
				F.p[l]:= 1
			ELSE	(* Charakter nicht vorhanden *)
				F.p[l]:=undef
			END;
			INC(l)
		END;
		bitW := bitW + (-bitW) MOD 4;
		bitH := F.maxY - F.minY;
		NEW(F.raster, bitW*bitH);
		k := 0; F.pos := 0;
		WHILE k # 256 DO
			IF F.p[k]=1 THEN
				i := (F.box[k].w + 7) DIV 8 * F.box[k].h; F.p[k] := F.pos; 
				WHILE i # 0 DO Files.Read(R, F.raster[F.pos]); INC(F.pos); DEC(i) END;
			END;
			INC(k)
		END
	ELSE Out.String("not a font");
		Out.Ln
	END
END LoadFont;

(** Font laden *)
PROCEDURE Load*;
VAR S: Texts.Scanner; F: Files.File; f: Font; R: Files.Rider; obj: Objects.Object;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Name THEN
		F := Files.Old(S.s);
		IF F # NIL THEN
			Files.Set(R, F, 0); LoadFont(f, R);
			Out.Int(f.pos, 0); Out.String(" Bytes loaded");Out.Ln;
 		   obj := Gadgets.FindObj(Gadgets.context, "table");
			IF obj#NIL THEN
				obj(Fonttable).f:= f;
			END;
 		   obj := Gadgets.FindObj(Gadgets.context, "preview");
			IF obj#NIL THEN
				obj(Preview).f:= f; 
				Gadgets.Update(obj)
			END
		ELSE
			Out.String(" file not found"); Out.Ln
		END;
	ELSE
		Out.String(" name expected"); Out.Ln
	END
END Load;

PROCEDURE StoreFont(VAR F: Font; VAR R: Files.Rider);
VAR pos: LONGINT; nofRuns, k, l, i: INTEGER;
BEGIN
	Files.Write(R, 0DBX);
	Files.Write(R, F.type);
	Files.Write(R, F.family);
	Files.Write(R, F.variant);
	Files.WriteInt(R, F.height);
	Files.WriteInt(R, F.minX); Files.WriteInt(R, F.maxX);
	Files.WriteInt(R, F.minY); Files.WriteInt(R, F.maxY);
	i:= 0; nofRuns:= 0;
	WHILE i#256 DO
		WHILE (i#256) & (F.p[i]=undef) DO INC(i) END;
		IF i#256 THEN
			F.run[nofRuns].beg:= i;
			WHILE F.p[i]#undef DO INC(i) END;
			F.run[nofRuns].end:= i;
			INC(nofRuns)
		END
	END;
	Files.WriteInt(R, nofRuns);
	k := 0;
	WHILE k # nofRuns DO
		Files.WriteInt(R, F.run[k].beg); Files.WriteInt(R, F.run[k].end);
		INC(k);
	END;
	l := 0; 
	WHILE l # 256 DO
		k:=0;
		WHILE (k#nofRuns) & ~((F.run[k].beg<=l) & (F.run[k].end>l)) DO INC(k) END;
		IF k#nofRuns THEN
			Files.WriteInt(R, F.box[l].dx);
			Files.WriteInt(R, F.box[l].x); Files.WriteInt(R, F.box[l].y);
			Files.WriteInt(R, F.box[l].w); Files.WriteInt(R, F.box[l].h);
		END;
		INC(l);
	END;
	k := 0; pos := 0;
	WHILE k # 256 DO
		IF F.p[k]#undef THEN
			i := (F.box[k].w + 7) DIV 8 * F.box[k].h; pos:=F.p[k]; 
			WHILE i # 0 DO Files.Write(R, F.raster[pos]); INC(pos); DEC(i) END;
		END;
		INC(k);
	END;
	Out.Int(pos, 5); Out.String(" Bytes stored"); Out.Ln;
END StoreFont;

(** Font speichern *)
PROCEDURE Store*;
VAR S: Texts.Scanner; F: Files.File; f: Font; R: Files.Rider;
		obj: Objects.Object; 
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Name THEN
		F := Files.Old(S.s);
		IF F = NIL THEN F:= Files.New(S.s) END;
		Files.Set(R, F, 0);
		obj := Gadgets.FindObj(Gadgets.context, "table");
		f:=obj(Fonttable).f;
		StoreFont(f, R);
		Files.Register(F);
	ELSE
		Out.String(" name expected"); Out.Ln
	END
END Store;

(** Handler für mittlere Maustaste *)
PROCEDURE MoveMetric*;
BEGIN
	fonttrackMM:= HandleMetric;
END MoveMetric;

PROCEDURE EditPixels*;
BEGIN
	fonttrackMM:= HandlePixel;
END EditPixels;

BEGIN
	EditPixels; NEW(df); 
	F:= Files.Old(Fonts.Default.name);
	IF F # NIL THEN Files.Set(R, F, 0); LoadFont(df, R) END;
END FontEditor.

Gadgets.Insert FontEditor.NewFonttable~

Gadgets.Insert FontEditor.NewPreview~

Desktops.OpenDoc FontEditor.Panel
