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

MODULE RembrandtDocs; 	(** portable *)
(** Stellt ein Rembrandt-Frame als einen Dokumententyp dar *)

	(*
		7.7.95 - Moved GIF stuff to pictures
		4.8.96 - changed to Printer.Frame (ps)
		24.4.97 - fixed bug in Load, Open and OpenPict (ps)
	*) 
	
IMPORT
	Pictures, Files, Objects, Display, Gadgets, Documents, Desktops, Printer, Printer3, D3:=Display3,
	Oberon, Texts, Rembrandt, Rembrandt0, Out;

CONST
	dz = 3; maxzoom=16;
	DocW = 384; DocH = 250;
	Menu = "Desktops.Copy[Copy] RembrandtDocs.Inc[+] RembrandtDocs.Dec[-] Desktops.StoreDoc[Store]";

(** Erhöht den Zoomfaktor *)
PROCEDURE Inc*;
VAR doc: Documents.Document; F: Rembrandt.Frame; zoom: INTEGER;
BEGIN
	doc := Desktops.CurDoc(Gadgets.context);
	IF (doc # NIL) & (doc.dsc IS Rembrandt.Frame) THEN
		F:= doc.dsc(Rembrandt.Frame);
		Rembrandt.GetZoom(F, zoom);
		zoom:= zoom+dz;
		IF zoom>maxzoom THEN zoom:=maxzoom END;
		Rembrandt.SetZoom(F, zoom);
	END
END Inc;

(** Verkleinert den Zoomfaktor *)
PROCEDURE Dec*;
VAR doc: Documents.Document; F: Rembrandt.Frame; zoom: INTEGER;
BEGIN
	doc := Desktops.CurDoc(Gadgets.context);
	IF (doc # NIL) & (doc.dsc IS Rembrandt.Frame) THEN
		F:= doc.dsc(Rembrandt.Frame);
		Rembrandt.GetZoom(F, zoom);
		zoom:= zoom-dz;
		IF zoom<1 THEN zoom:=1 END;
		Rembrandt.SetZoom(F, zoom);
	END
END Dec;

(** Ein- bzw. ausschalten der Gitterlinien *)
PROCEDURE Grid*;
VAR doc: Documents.Document; F: Rembrandt.Frame; grid: BOOLEAN;
BEGIN
	doc := Desktops.CurDoc(Gadgets.context);
	IF (doc # NIL) & (doc.dsc IS Rembrandt.Frame) THEN
		F:= doc.dsc(Rembrandt.Frame);
		Rembrandt.GetGrid(F, grid);
		Rembrandt.SetGrid(F, ~grid)
	END
END Grid;

PROCEDURE MakeDoc (D: Documents.Document; pict: Pictures.Picture);
VAR P: Rembrandt.Frame;
BEGIN
	NEW(P); Rembrandt.NewP(P, pict);
	D.W := pict.width+2; D.H := pict.height+2;
	Documents.Init(D, P)
END MakeDoc;

PROCEDURE Load(D: Documents.Document);
VAR P: Pictures.Picture; F: Files.File;
BEGIN
	F := Files.Old(D.name);
	IF F # NIL THEN
		NEW(P); Pictures.Open(P, D.name, TRUE);
		IF P.depth = 0 THEN (* not enough memory *)
			D.dsc := NIL;
			Out.String(" out of memory"); Out.Ln;
			RETURN
		END
	ELSE 
		NEW(P); Pictures.Create(P, DocW, DocH, Display.Depth(0))
	END;
	MakeDoc(D, P)
END Load;

PROCEDURE Store(D: Documents.Document);
VAR obj:Rembrandt .Frame; F: Files.File; R: Files.Rider; len: LONGINT;
BEGIN
	obj := D.dsc(Rembrandt.Frame);
	IF D.name # "" THEN
		F := Files.New(D.name);
		IF F = NIL THEN HALT(99) END;
		Files.Set(R, F, 0);
		Files.WriteInt(R, Documents.Id); Files.WriteString(R, "RembrandtDocs.NewDoc");
		Files.WriteInt(R, D.X); Files.WriteInt(R, D.Y); Files.WriteInt(R, D.W); Files.WriteInt(R, D.H);
		Pictures.Store(obj.pict, F, Files.Pos(R), len);
		Out.String("Store "); Out.String(D.name); Out.Ln;
		Files.Register(F)
	ELSE
		Out.String("[Untitled document]"); Out.Ln;
	END
END Store;

PROCEDURE Handler(D: Objects.Object; VAR M: Objects.ObjMsg);
VAR P: Pictures.Picture; R: D3.Mask;

	PROCEDURE PP(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END PP;

BEGIN
	WITH D: Documents.Document DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN M.class := Objects.String; M.s := "RembrandtDocs.NewDoc"; M.res := 0
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
					P := D.dsc(Rembrandt.Frame).pict;
					IF P = NIL THEN HALT(99) END;
					NEW(R); D3.Open(R); D3.Add(R, Printer.FrameX, Printer.FrameY, Printer.FrameW, Printer.FrameH);
					R.X := Printer.FrameX; R.Y := Printer.FrameY; R.W := Printer.FrameW; R.H := Printer.FrameH; R.x := 0; R.y := 0;
					Printer3.Pict(R, P, Printer.FrameX, Printer.FrameY + Printer.FrameH - PP(P.height),
						PP(P.width), PP(P.height), Display.replace);
					Printer.Page(1)
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF (M.id = Objects.get) & (M.name = "DeskMenu") THEN
					M.obj := Gadgets.CopyPublicObject("Rembrandt.DeskMenu", TRUE);
					IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
					M.res := 0
				ELSIF (M.id = Objects.get) & (M.name = "SystemMenu") THEN
					M.obj := Gadgets.CopyPublicObject("Rembrandt.SystemMenu", TRUE);
					IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
					M.res := 0
				ELSIF (M.id = Objects.get) & (M.name = "UserMenu") THEN
					M.obj := Gadgets.CopyPublicObject("Rembrandt.UserMenu", TRUE);
					IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
					M.res := 0
				ELSE Documents.Handler(D, M)
				END
			END
		ELSE Documents.Handler(D, M)
		END
	END
END Handler;

(** Initialisiert ein neues Document *)
PROCEDURE InitDoc*(D: Documents.Document);
BEGIN D.Load := Load; D.Store := Store; D.handle := Handler;
	D.W := DocW; D.H := DocH
END InitDoc;

(** Erstellt eine neues Document *)
PROCEDURE NewDoc*;
VAR D: Documents.Document;
BEGIN
	NEW(D); InitDoc(D); Objects.NewObj := D
END NewDoc;

(** Öffnet ein leeres RembrandtDocument mit Breite und Höhe als Parameter *)
PROCEDURE Open*;
VAR S: Texts.Scanner; x, y, pw, ph, r, g, b: INTEGER;
		doc: Documents.Document;
		P: Pictures.Picture;
BEGIN
	NEW(P); Rembrandt.GetSelectedPict(P, x, y, pw, ph);
	IF P = NIL THEN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF S.class = Texts.Int THEN pw:= ABS(SHORT(S.i)) ELSE pw:= 284 END;
		Texts.Scan(S);
		IF S.class = Texts.Int THEN ph:= ABS(SHORT(S.i)) ELSE ph:= 200 END;
		NEW(P); Rembrandt0.AllocatePictureMem(P, pw, ph, Display.Depth(0));  (* tk *)
		FOR x := 0 TO SHORT(ASH(1, Display.Depth(0))-1) DO Display.GetColor(x, r, g, b); Pictures.SetColor(P, x, r, g, b) END
	END;
	IF P # NIL THEN
		NEW(doc); doc.Load:= Load; doc.Store:= Store; doc.handle:= Handler;
		Objects.NewObj:= doc;
		doc.name:="";
		MakeDoc(doc, P);
		Desktops.ShowDoc(doc)	(* Version 1.6 *)
	END
END Open;

(** Öffnet ein neues RembrandtDocument mit Picture P und Name name *)
PROCEDURE OpenPict*(P: Pictures.Picture; name: ARRAY OF CHAR);
VAR doc: Documents.Document;
BEGIN
	NEW(doc); doc.Load:= Load; doc.Store:= Store; doc.handle:= Handler;
	Objects.NewObj:= doc;
	COPY(name, doc.name);
	MakeDoc(doc, P);
	Desktops.ShowDoc(doc)	(* Version 1.6 *)
END OpenPict;

(** Markiertes RembrandtDocument zurückgeben *)
PROCEDURE MarkedFrame*(): Rembrandt.Frame;
VAR doc: Documents.Document;
BEGIN
	doc:= Documents.MarkedDoc();
	IF (doc#NIL ) & (doc.dsc#NIL) & (doc.dsc IS Rembrandt.Frame) THEN
		RETURN doc.dsc(Rembrandt.Frame)
	ELSE 
		RETURN NIL
	END 
END MarkedFrame;

END RembrandtDocs.

System.Free RembrandtDocs ~
Desktops.OpenDoc Cards.Pict (RembrandtDocs.NewDoc)
