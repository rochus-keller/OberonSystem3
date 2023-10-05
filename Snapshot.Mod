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

MODULE Snapshot;	(** portable *)	(* Native *)

(**
	jm 10.7.95 / pjm 17.10.97

	Snapshot.Viewer *		Make snapshot of viewer
	Snapshot.Document *		Make snapshot of document
	Snapshot.Gadget *		Make snapshot of marked gadget

	Snapshot.InsertViewer *		Insert snapshot of viewer at caret
	Snapshot.InsertDocument *		Insert snapshot of document at caret
	Snapshot.InsertGadget *		Insert snapshot of marked gadget

	Snapshot.Screen 	Make snapshot of the screen
*)

(* known bugs: truecolor/hicolor is very slow *)

IMPORT SYSTEM, Display, Display3, Effects, Objects, Oberon, Pictures, Gadgets,
	Documents, Viewers, Rembrandt, RembrandtDocs;

TYPE
	PositionMsg = RECORD (Display.FrameMsg)
		FX, FY, FW, FH: INTEGER;
	END;
	
VAR
	GetPixel: PROCEDURE (x, y: LONGINT): LONGINT;
	handle: Objects.Handler;
	base, maxy: LONGINT;
	pal: ARRAY 256 OF RECORD
		r, g, b: LONGINT
	END;
	rm, gm, bm, rs, gs: LONGINT;

PROCEDURE CopyBlock(p: Pictures.Picture;  x, y, w, h: INTEGER);
VAR xi, yi: INTEGER;
BEGIN
	FOR xi := x TO x+w-1 DO
		FOR yi := y TO y+h-1 DO
			Pictures.Dot(p, SHORT(GetPixel(xi, yi)), xi-x, yi-y, Display.replace)
		END
	END
END CopyBlock;

PROCEDURE InitPal(p: Pictures.Picture);
VAR i, r, g, b: INTEGER;
BEGIN
	FOR i := 0 TO 255 DO
		Pictures.GetColor(p, i, r, g, b);
		pal[i].r := r DIV (256 DIV rm);
		pal[i].g := g DIV (256 DIV gm);
		pal[i].b := b DIV (256 DIV bm)
	END
END InitPal;

PROCEDURE Border(obj: Rembrandt.Frame; flag: BOOLEAN);
VAR M: Objects.AttrMsg;
BEGIN
	M.id := Objects.set; M.class := Objects.Bool; M.b := flag; M.name := "Border"; M.res := -1;
	obj.handle(obj, M)
END Border;

(* Make a snapshot of any visual gadget. *)
PROCEDURE SnapFrame*(F: Gadgets.Frame; VAR P: Pictures.Picture);
VAR dlink: Objects.Object; D: Display.DisplayMsg; O: Display3.OverlapMsg;
BEGIN
	Effects.OpenMenu(0, 0, F.W, F.H);
	D.id := Display.full; D.device := Display.screen;
	D.x := -F.X; D.y := -F.Y;
	dlink := F.dlink;
	O.M := NIL; O.res := -1; Objects.Stamp(O); F.handle(F, O); F.dlink := NIL;
	IF O.res >= 0 THEN
		D.res := -1; F.handle(F, D);
		F.dlink := dlink;
		NEW(P);  Pictures.Create(P, F.W, F.H, 8);
		InitPal(P);
		CopyBlock(P, 0, 0, F.W, F.H)
	ELSE
		P := NIL
	END;
	Effects.CloseMenu
END SnapFrame;

PROCEDURE Viewer*;
VAR V: Viewers.Viewer; P: Pictures.Picture;
BEGIN
	V := Oberon.MarkedViewer();
	IF V # NIL THEN
		Oberon.RemoveMarks(V.X, V.Y, V.W, V.H);
		NEW(P);  Pictures.Create(P, V.W, V.H, 8);
		InitPal(P);
		CopyBlock(P, V.X, V.Y, V.W, V.H);
		RembrandtDocs.OpenPict(P, "Snapshot.Pict")
	END
END Viewer;

PROCEDURE InsertViewer*;
VAR V: Viewers.Viewer; P: Pictures.Picture; obj: Rembrandt.Frame;
BEGIN
	V := Oberon.MarkedViewer();
	IF V # NIL THEN
		Oberon.RemoveMarks(V.X, V.Y, V.W, V.H);
		NEW(P);  Pictures.Create(P, V.W, V.H, 8);
		InitPal(P);
		CopyBlock(P, V.X, V.Y, V.W, V.H);
		NEW(obj); Rembrandt.NewP(obj, P); Border(obj, FALSE);
		Gadgets.Integrate(obj);
	END
END InsertViewer;

PROCEDURE NewHandler(obj: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH obj: Display.Frame DO
		IF M IS PositionMsg THEN
			WITH M: PositionMsg DO
				IF M.res < 0 THEN
					M.FX := M.x + obj.X; M.FY := M.y + obj.Y; M.FW := obj.W; M.FH := obj.H;
					M.res := 0
				END
			END
		ELSE handle(obj, M)
		END
	END
END NewHandler;

PROCEDURE Document*;
VAR D: Documents.Document; M: PositionMsg; P: Pictures.Picture;
BEGIN
	D := Documents.MarkedDoc();
	IF D # NIL THEN
		handle := D.handle;
		D.handle := NewHandler;
		M.F := D; Display.Broadcast(M);
		D.handle := handle;
		Oberon.RemoveMarks(M.FX, M.FY, M.FW, M.FH);
		NEW(P);  Pictures.Create(P, M.FW, M.FH, 8);
		InitPal(P);
		CopyBlock(P, M.FX, M.FY, M.FW, M.FH);
		RembrandtDocs.OpenPict(P, "Snapshot.Pict")
	END
END Document;

PROCEDURE Gadget*;
VAR D: Display.Frame; M: PositionMsg; P: Pictures.Picture;
BEGIN
	D := Oberon.MarkedFrame();
	IF D # NIL THEN
		handle := D.handle;
		D.handle := NewHandler;
		M.F := D; Display.Broadcast(M);
		D.handle := handle;
		Oberon.RemoveMarks(M.FX, M.FY, M.FW, M.FH);
		NEW(P);  Pictures.Create(P, M.FW, M.FH, 8);
		InitPal(P);
		CopyBlock(P, M.FX, M.FY, M.FW, M.FH);
		RembrandtDocs.OpenPict(P, "Snapshot.Pict")
	END
END Gadget;

PROCEDURE InsertDocument*;
VAR D: Documents.Document; M: PositionMsg; P: Pictures.Picture; obj: Rembrandt.Frame;
BEGIN
	D := Documents.MarkedDoc();
	IF D # NIL THEN
		handle := D.handle;
		D.handle := NewHandler;
		M.F := D; Display.Broadcast(M);
		D.handle := handle;
		Oberon.RemoveMarks(M.FX, M.FY, M.FW, M.FH);
		NEW(P);  Pictures.Create(P, M.FW, M.FH, 8);
		InitPal(P);
		CopyBlock(P, M.FX, M.FY, M.FW, M.FH);
		NEW(obj); Rembrandt.NewP(obj, P); Border(obj, FALSE);
		Gadgets.Integrate(obj);
	END
END InsertDocument;

PROCEDURE InsertGadget*;
VAR D: Display.Frame; M: PositionMsg; P: Pictures.Picture; obj: Rembrandt.Frame;
BEGIN
	D := Oberon.MarkedFrame();
	IF D # NIL THEN
		handle := D.handle;
		D.handle := NewHandler;
		M.F := D; Display.Broadcast(M);
		D.handle := handle;
		Oberon.RemoveMarks(M.FX, M.FY, M.FW, M.FH);
		NEW(P);  Pictures.Create(P, M.FW, M.FH, 8);
		InitPal(P);
		CopyBlock(P, M.FX, M.FY, M.FW, M.FH);
		NEW(obj); Rembrandt.NewP(obj, P); Border(obj, FALSE);
		Gadgets.Integrate(obj);
	END
END InsertGadget;

PROCEDURE Screen*;
	VAR
		P: Pictures.Picture;
		x, y: LONGINT;
		r, g, b, i: INTEGER;
BEGIN
	NEW(P); Pictures.Create(P, Display.Width, Display.Height, 8);
	FOR i := 0 TO 255 DO
		Display.GetColor(i, r, g, b);
		Pictures.SetColor(P, i, r, g, b)
	END;
	FOR x := 0 TO Display.Width-1 DO
		FOR y := 0 TO Display.Height-1 DO
			Pictures.Dot(P, SHORT(GetPixel(x, y)), SHORT(x), SHORT(y), Display.replace)
		END
	END;
	RembrandtDocs.OpenPict(P, "Snapshot.Pict")
END Screen;

PROCEDURE BankGetPixelPlane(x, y: LONGINT): LONGINT;	(* harry *)
VAR offset, mask, col: LONGINT;  pg: SET;  byte: CHAR;
BEGIN
	offset := y*80 + (x DIV 8);	(* Setup the video page *)
	pg := SYSTEM.VAL(SET, offset DIV 10000H) * {0..3};
	pg := pg + SYSTEM.LSH(pg, 4);
	SYSTEM.PORTOUT(3CDH, CHR(SYSTEM.VAL(LONGINT, pg)));
	offset := offset MOD 10000H;
	mask := SYSTEM.LSH(80H, -(x MOD 8));
	SYSTEM.PORTOUT(3CEH, 8X);	(* Select bit *)
	SYSTEM.PORTOUT(3CFH, CHR(mask));
	col := 0;  INC(offset, base);
	SYSTEM.PORTOUT(3CEH, 4X);	(* Select plane 0 *)
	SYSTEM.PORTOUT(3CFH, 0X);
	SYSTEM.GET(offset, byte);
	IF SYSTEM.VAL(SET, byte) * SYSTEM.VAL(SET, mask) # {} THEN INC(col, 1) END;
	SYSTEM.PORTOUT(3CEH, 4X);	(* Select plane 1 *)
	SYSTEM.PORTOUT(3CFH, 1X);
	SYSTEM.GET(offset, byte);
	IF SYSTEM.VAL(SET, byte) * SYSTEM.VAL(SET, mask) # {} THEN INC(col, 2) END;
	SYSTEM.PORTOUT(3CEH, 4X);	(* Select plane 2 *)
	SYSTEM.PORTOUT(3CFH, 2X);
	SYSTEM.GET(offset, byte);
	IF SYSTEM.VAL(SET, byte) * SYSTEM.VAL(SET, mask) # {} THEN INC(col, 4) END;
	SYSTEM.PORTOUT(3CEH, 4X);	(* Select plane 3 *)
	SYSTEM.PORTOUT(3CFH, 3X);
	SYSTEM.GET(offset, byte);
	IF SYSTEM.VAL(SET, byte) * SYSTEM.VAL(SET, mask) # {} THEN INC(col, 8) END;
	RETURN col
END BankGetPixelPlane;

PROCEDURE BankGetPixel(x, y: LONGINT): LONGINT;	(* harry *)
VAR offset: LONGINT;  byte: CHAR;  pg: SET;
BEGIN
	offset := y*Display.Width + x;
	pg := SYSTEM.VAL(SET, offset DIV 10000H) * {0..3};
	pg := pg + SYSTEM.LSH(pg, 4);
	SYSTEM.PORTOUT(3CDH, CHR(SYSTEM.VAL(LONGINT, pg)));
	SYSTEM.GET(base + offset MOD 010000H, byte);
	RETURN ORD(byte)
END BankGetPixel;

PROCEDURE LinearGetPixel(x, y: LONGINT): LONGINT;
VAR ch: CHAR;
BEGIN
	SYSTEM.GET(base + (maxy-y) * Display.Width + x, ch);
	RETURN ORD(ch)
END LinearGetPixel;

PROCEDURE TransferGetPixel8(x, y: LONGINT): LONGINT;
VAR buf: ARRAY 4 OF CHAR;
BEGIN
	Display.TransferBlock(buf, 0, 0, x, y, 1, 1, Display.get);
	RETURN ORD(buf[0])
END TransferGetPixel8;

PROCEDURE TransferGetPixel(x, y: LONGINT): LONGINT;	(* very slow! *)
TYPE Arr4 = ARRAY 4 OF CHAR;
VAR col, r, g, b, r1, g1, b1, i, j, d, m: LONGINT;
BEGIN
	Display.TransferBlock(SYSTEM.VAL(Arr4, col), 0, 0, x, y, 1, 1, Display.get);
	r := ASH(col, rs) MOD rm;
	g := ASH(col, gs) MOD gm;
	b := col MOD bm;
	m := MAX(LONGINT);
	FOR i := 0 TO 255 DO
		r1 := pal[i].r - r;  g1 := pal[i].g - g;  b1 := pal[i].b - b;
		d := r1*r1 + g1*g1 + b1*b1;
		IF d < m THEN j := i;  m := d END
	END;
	RETURN j
END TransferGetPixel;

PROCEDURE Init;
VAR format: LONGINT;
BEGIN
	rm := 256;  gm := 256;  bm := 256;
	maxy := Display.Height-1;
	GetPixel := NIL;
	format := Display.TransferFormat(0);
	IF format = Display.index8 THEN
		GetPixel := TransferGetPixel8
	ELSIF format # Display.unknown THEN
		CASE format OF
			|Display.color555: rm := 32;  gm := 32;  bm := 32;  rs := -10; gs := -5
			|Display.color565: rm := 32;  gm := 64;  bm := 32;  rs := -11;  gs := -5
			|Display.color664: rm := 64;  gm := 64;  bm := 16;  rs := -10;  gs := -4
			|Display.color888, Display.color8888: rm := 256;  gm := 256;  bm := 256;  rs := -16;  gs := -8
		END;
		GetPixel := TransferGetPixel
	ELSE
		base := Display.Map(0);
		IF (base > 0) & (base < 1000000H) THEN
			IF Display.Width = 640 THEN GetPixel := BankGetPixelPlane
	 	   ELSE GetPixel := BankGetPixel
	 	   END
		ELSIF base # 0 THEN
			GetPixel := LinearGetPixel
		ELSE
			(* skip *)
		END
	END
END Init;

BEGIN
	Init
END Snapshot.

Snapshot.Screen
Snapshot.Gadget *
