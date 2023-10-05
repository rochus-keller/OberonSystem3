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

MODULE Rembrandt;	(** portable *)
(** Ist das Hauptmodul für den Rembrandt-Editor *)
(* tk, picture-depth corrections 25.5.1995 *)
(* jm, fixed Copy 4.12.95 *)
(* ps, resize dep. of attr. Border 21.5.96 *)
(* ps, changed to Printer.Frame 4.8.96 *)
(* ps, changed behaviour of {MM, MR} 8.10.96 *)
(* ps, bugfix in GetSelection 24.4.97 *)

IMPORT
	Rembrandt0, Files, Display, D3:=Display3, Texts, Printer3, Printer, Effects, Objects, Gadgets, Fonts, Oberon, Pictures, Out,
	Input, Attributes;

CONST
	(* Konstanten für Mouseklicks *)
	MM = 1;
	MR = 0;
	ML = 2;
	Cancel = {MM, MR, ML};

	(** ID's für Selection *)
	No* = 0;				(** Keine Selektion *)	
	Block* = 1;			(** Rectangle selektiert *)
	Image* = 2;			(** Ganzes Picture selektiert *)
	Object* = 3;			(** Ein Gebiet mit einer best. Farbe selektiert *)
	Freehand* = 4;		(** Polygon selektiert *)

	idMove*=0;			(** Belegung der MM falls Selektion vorhanden *)
	idRotate*=1;
	idScale*= 2;

TYPE
	Element = POINTER TO ElemDesc;
	ElemDesc= RECORD
							next: Element;
							x, y, w: INTEGER
						END;


	Lockrec= RECORD
						scaledpict: Pictures.Picture;					(* Skaliertes Picture falls Gadget locked *)
						lw, lh, lpx, lpy, actlw, actlh: INTEGER		(* Originalframegrösse ; aktuelle Abstand zu Ecke ; aktuelle Framegrösse*)
				END;

	Frame* = POINTER TO FrameDesc;
	FrameDesc* = RECORD (Gadgets.FrameDesc) 
		pict*: Pictures.Picture;
		px, py: INTEGER;			(* Position des Bildes innerhalb des Frames; Nullpkt. linke, obere Ecke *)
		locked: BOOLEAN;		(* Pictures ändern möglich oder nicht *)
		lockdata: Lockrec;		(* Daten für Zustand locked *)
		border: BOOLEAN;		(* Rand sichtbar oder nicht *)
		selection*: INTEGER; 
		sx*, sy*, sw*, sh*: INTEGER;	(** Selektionsbereich *)
		selstruct: Element; 						(* Beliebige Fläche selektiert *)
		seloutline: Element;			(* Darstellung des selektierten *)
		selcolor: INTEGER;		(* Selektionsfarbe *)
		selcol: INTEGER;				(* Farbe der Fläche *)
		seltime: LONGINT;
		selpict: Pictures.Picture;
		car* : BOOLEAN;
		cx*, cy*: INTEGER;
		string: RECORD len, x, y: INTEGER END;
		zoom: INTEGER;				(* Zoomweite: 1=normal *)
		grid: BOOLEAN;				(* Rasterlinien *)
		time: LONGINT;
		col*: INTEGER; 	(* für Version 1.6 *)
	END;

	TrackMMProc* = PROCEDURE (F: Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);

	DrawSelectionMsg = RECORD (Display.FrameMsg) END;
	DrawCaretMsg = RECORD (Display.FrameMsg) END;
	DrawGridMsg = RECORD (Display.FrameMsg) u, v, w, h: INTEGER END;
	ZoomMsg = RECORD (Display.DisplayMsg) zoom: INTEGER END;
	FocusMsg = RECORD (Display.FrameMsg) u, v: INTEGER END;
	SelectMsg = RECORD (Display.SelectMsg)
							pict: Pictures.Picture;
							u, v, w, h: INTEGER
						END;

	Region = POINTER TO RegionDesc;
	RegionDesc= RECORD
							next: Region;
							px, py: INTEGER;
							P, pict: Pictures.Picture
						END;

VAR
	trackMM*: TrackMMProc;		(** Handler für Operationen *)
	trackSelMM*: RECORD			(** Handler für Selektionsoperationen *)
								id*: SHORTINT;
								track*: TrackMMProc
						END;
	undo (*, redo *): Region;	(* Picture für letzte Änderung rückgängig machbar *)
	cursor*: Oberon.Marker;
	seltype: INTEGER;
	selcolor*: INTEGER;		(** Farbe für Selektion *)
	clipboard: RECORD
						id, col: INTEGER;
						P: Pictures.Picture;
						selstruct: Element;
						sw, sh: INTEGER;
						Paste: PROCEDURE(D: Pictures.Picture; dx, dy: INTEGER);
					END;
	seldir: ARRAY 4 OF RECORD dx, dy, ind: SHORTINT END;	(* Hilfsarray für Outlinebestimmung von bel. Selektion *)

PROCEDURE ^ NewP*(F: Frame;pict: Pictures.Picture);

PROCEDURE Min(a, b: INTEGER): INTEGER;
BEGIN
	IF a<b THEN RETURN a ELSE RETURN b END;
END Min;

PROCEDURE Max(a, b: INTEGER): INTEGER;
BEGIN
	IF a>b THEN RETURN a ELSE RETURN b END;
END Max;

PROCEDURE SizeFrame(F: Frame; d: INTEGER);	(* ps - 21.5.96 *)
VAR M: Display.ModifyMsg;
BEGIN
	INC(F.px, d); INC(F.py, d); INC(F.lockdata.lpx, d); INC(F.lockdata.lpy, d);
	M.id := Display.extend; M.mode := Display.display; M.F := F;
	M.X := F.X - d; M.Y := F.Y - d; M.W := F.W + 2*d; M.H := F.H + 2*d;
	M.dX := -d; M.dY := -d; M.dW := 2*d; M.dH := 2*d;
	Display.Broadcast(M)
END SizeFrame;

(** Handler für Attribute *)
PROCEDURE FrameAttributes*(F: Frame; VAR M: Objects.AttrMsg);
VAR L: Lockrec; old: BOOLEAN;
BEGIN
  IF M.id = Objects.get THEN
    IF M.name = "Gen" THEN
      M.class := Objects.String; COPY("Rembrandt.New", M.s); M.res := 0
    ELSIF M.name = "Color" THEN
      M.class := Objects.Int; M.i := F.col; M.res := 0 
	ELSIF M.name = "Locked" THEN
	 M.class:= Objects.Bool; M.b:= F.locked; M.res:=0
	ELSIF M.name = "Border" THEN
	 M.class:= Objects.Bool; M.b:= F.border; M.res:=0
	ELSIF M.name = "LineupHY" THEN M.class := Objects.Int; M.res := 0; M.i := F.H DIV 2 - 5
	ELSIF M.name = "Cmd" THEN
		Gadgets.framehandle(F, M);
		IF M.res < 0 THEN M.class := Objects.String; M.s := ""; M.res := 0 END
	ELSIF M.name = "Zoom" THEN
		M.class:= Objects.Int; M.i:= F.zoom; M.res:= 0
    ELSE Gadgets.framehandle(F, M)
    END
  ELSIF M.id = Objects.set THEN
    IF M.name = "Color" THEN
      IF M.class = Objects.Int THEN
        F.col := SHORT(M.i); M.res := 0
      END
	ELSIF M.name = "Locked" THEN
	  IF M.class = Objects.Bool THEN
		F.locked:= M.b;
		IF F.locked THEN
			L := F.lockdata;
			L.scaledpict := NIL;
			L.lw := F.W; L.lh := F.H; L.lpx := F.px; L.lpy := F.py; 
			L.actlw := F.W; L.actlh := F.H;
			F.lockdata := L
		END;
		M.res:=0
	  END
	ELSIF M.name = "Border" THEN
	  IF M.class = Objects.Bool THEN
		old:= F.border; F.border:= M.b; M.res:=0;
		IF F.border#old THEN
			IF F.border THEN SizeFrame(F, 1)
			ELSE SizeFrame(F, -1)
			END
		END;
		Gadgets.Update(F)
	  END
	ELSIF (M.name = "Zoom") & (M.class = Objects.Int) & (M.i > 0) THEN
		F.zoom:= SHORT(M.i); Gadgets.Update(F); M.res:= 0
    ELSE Gadgets.framehandle(F, M)
    END
  ELSIF M.id = Objects.enum THEN
    M.Enum("Color"); M.Enum("Cmd"); M.Enum("Locked"); M.Enum("Border"); M.Enum("Zoom");
    Gadgets.framehandle(F, M)
  END
END FrameAttributes;

PROCEDURE FrameLinks(F: Frame; VAR M: Objects.LinkMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Model" THEN M.obj := F.pict; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END;
	ELSIF M.id = Objects.set THEN
		IF M.name = "Model" THEN
			IF (M.obj # NIL) & (M.obj IS Pictures.Picture) THEN
				F.pict := M.obj(Pictures.Picture); Gadgets.Update(F); M.res := 0
			ELSE Gadgets.framehandle(F, M)
			END
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.enum THEN Gadgets.framehandle(F, M)
	END
END FrameLinks;

(** Wandelt die absoluten Bildschirmkoordinaten in Picturekoordinaten um *)
PROCEDURE ScreentoPict*(F: Frame; x, y, absx, absy: INTEGER; VAR px, py: INTEGER);
BEGIN
	px:= (absx-x-F.px*F.zoom) DIV F.zoom;
	py:= (absy-y-F.H+F.pict.height*F.zoom+F.py*F.zoom) DIV F.zoom
END ScreentoPict;

(** Wandelt relative Picturekoordinaten in absulute Bildschirmkoordinaten um *)
PROCEDURE PicttoScreen*(F: Frame; x, y, relx, rely: INTEGER; VAR absx, absy: INTEGER);
VAR h: INTEGER;
BEGIN
	IF F.locked & (F.lockdata.scaledpict # NIL) THEN h := F.lockdata.scaledpict.height ELSE h := F.pict.height END;
	absx:= (relx+F.px)*F.zoom+x;
	absy:= (rely-h-F.py)*F.zoom+y+F.H
END PicttoScreen;

(** Entfernt eine vorhandene Selektion im Frame F*)
PROCEDURE RemoveSelection*(F: Frame);
VAR M: DrawSelectionMsg;
BEGIN
	IF F.selection#No THEN
		M.res:= -1; M.F:= F; Display.Broadcast(M);
		F.selection:= No; F.selstruct:= NIL; 
	END
END RemoveSelection;

PROCEDURE SetSelection(F: Frame; id: INTEGER);
VAR M: DrawSelectionMsg;
BEGIN
	F.selection:= id; 
	M.res:= -1; M.F:= F; Display.Broadcast(M);
	F.time:= Oberon.Time();
END SetSelection;

PROCEDURE GetSelection(VAR F: Frame; VAR P: Pictures.Picture; VAR time: LONGINT; VAR x, y, w, h: INTEGER);
VAR M: SelectMsg; M2: Display.SelectMsg; time2: LONGINT;
BEGIN
	M.id := Display.get; M.time := 0; M.pict := NIL; M.F := NIL; M.obj := NIL;
	Display.Broadcast(M);
	time := M.time;
	time2 := 0;
	M2.id := Display.get; M2.time := 0; M2.F := NIL; M2.obj := NIL;
	Display.Broadcast(M2);
	IF M2.obj # NIL THEN
		IF M2.obj IS Frame THEN M2.obj := M2.obj(Frame).pict END;
		IF M2.obj IS Pictures.Picture THEN time2:= M2.time  END
	END;
	IF (time > 0) & (time > time2) THEN
		IF M.pict # NIL THEN
			F:= M.sel(Frame); 
			P:= M.pict; x:= M.u; y:= M.v; w:= M.w; h:= M.h; 
		END
	ELSIF time2 > 0 THEN 
		IF M2.obj IS Pictures.Picture THEN
			IF M.sel IS Frame THEN F := M.sel(Frame) ELSE F:= NIL END;
			P := M2.obj(Pictures.Picture); time:= time2; x:=0; y:=0; w:= P.width; h:= P.height
		END
	END
END GetSelection;

PROCEDURE DrawOutline(F: Frame; Q: D3.Mask; sx, sy: INTEGER);
VAR act: Element; x0, y0: INTEGER;
BEGIN
	act:= F.seloutline;
	IF act#NIL THEN act:= act.next END;
	WHILE act#NIL DO
		x0:=sx+act.x*F.zoom; y0:= sy+act.y*F.zoom;
		D3.ReplConst(Q, F.selcolor, x0, y0, F.zoom, F.zoom, Display.invert);
		act:= act.next;
	END;
END DrawOutline;

PROCEDURE DrawSelection(F: Frame; Q: D3.Mask; x, y: INTEGER);
VAR ox, oy: INTEGER;
BEGIN
	PicttoScreen(F, x, y, F.sx, F.sy, ox, oy);
	Oberon.FadeCursor(Oberon.Mouse);
	IF (F.selection=Block) OR (F.selection=Image) THEN
		D3.Rect(Q, F.selcolor, Display.solid, ox-F.zoom, oy-F.zoom, (F.sw+2)*F.zoom, (F.sh+2)*F.zoom, F.zoom , Display.invert)
	ELSE	(* Freehand or Object*)
		DrawOutline(F, Q, ox, oy);
	END
END DrawSelection;

(** Kopiert Picture-Palette *)
PROCEDURE CopyPalette*(S, D: Pictures.Picture);
VAR i, r, g, b: INTEGER;
BEGIN
	i:=0;
	WHILE i< ASH(1, S.depth) DO Pictures.GetColor(S, i, r, g, b); Pictures.SetColor(D, i, r, g, b); INC(i) END
END CopyPalette;

(** Gibt die letzte Selektion in Form eines Pictures zurück *)
PROCEDURE GetSelectedPict*(VAR P: Pictures.Picture; VAR x, y, w, h: INTEGER);
VAR F: Frame;
		time: LONGINT;
		act: Element;
BEGIN
	GetSelection(F, P, time, x, y, w, h);
	IF time>0 THEN
		IF (F#NIL) & (F.selection>=Object) THEN
			NEW(P); Rembrandt0.AllocatePictureMem(P, w, h, F.pict.depth);	(* tk *)
			CopyPalette(F.pict, P);
			IF F.selection=Object THEN
				act:= F.selstruct;
				WHILE act#NIL DO
					Pictures.ReplConst(P, F.selcol, act.x, act.y, act.w, 1, Display.replace); 
					act:= act.next
				END;
			ELSE
				act:= F.selstruct;
				WHILE act#NIL DO
					Rembrandt0.CopyBlock(F.pict, P, x+act.x, y+act.y, act.w, 1, act.x, act.y, Display.replace);
					act:= act.next
				END;
			END;
			x:= 0; y:=0;
		END
	ELSE
		NEW(P); P:= NIL
	END
END GetSelectedPict;

(** Gibt Selektion innerhalb eines bestimmten Frames zurück *)
PROCEDURE GetSelectioninFrame*(F: Frame; VAR P: Pictures.Picture; VAR x, y, w, h: INTEGER);
VAR act: Element;
BEGIN
	IF (F#NIL) & (F.selection#No) THEN
		w:= F.sw; h:= F.sh; x:= F.sx; y:= F.sy;
		(* NEW(P); Rembrandt0.AllocatePictureMem(P, w, h, F.pict.depth);   *) (* tk *)
		IF F.selection=Object THEN
			NEW(P); Rembrandt0.AllocatePictureMem(P, w, h, F.pict.depth);	(* tk *)
			CopyPalette(F.pict, P);
			act:= F.selstruct;
			WHILE act#NIL DO
				Pictures.ReplConst(P, F.selcol, act.x, act.y, act.w, 1, Display.replace); 
				act:= act.next
			END; x:=0; y:=0;
		ELSIF F.selection=Freehand THEN
			NEW(P); Rembrandt0.AllocatePictureMem(P, w, h, F.pict.depth);	(* tk *)
			CopyPalette(F.pict, P);
			act:= F.selstruct;
			WHILE act#NIL DO
				Rembrandt0.CopyBlock(F.pict, P, x+act.x, y+act.y, act.w, 1, act.x, act.y, Display.replace);
				act:= act.next
			END; x:=0; y:=0;
		ELSE	(* Block or Image *)
			P:= F.pict; 
		END; 
	ELSE
		P:= NIL
	END
END GetSelectioninFrame;

PROCEDURE Select(F: Frame; x, y: INTEGER; VAR M: Display.SelectMsg);
VAR F1: Frame;
BEGIN
	IF M.id= Display.get THEN
		IF (F.time > M.time) & (F.selection#No) THEN
			M.time:= F.time; M.sel:= F;
			IF M IS SelectMsg THEN
				WITH M: SelectMsg DO
					M.pict:= F.pict; M.u:= F.sx; M.v:= F.sy; M.w:= F.sw; M.h:= F.sh; 
				END
			ELSE
				IF F.seltime#F.time THEN
					NEW(F.selpict); Pictures.Create(F.selpict, F.sw, F.sh, F.pict.depth);
					CopyPalette(F.pict, F.selpict);	(* tk *)
					Pictures.CopyBlock(F.pict, F.selpict, F.sx, F.sy, F.sw, F.sh, 0, 0, Display.replace);
					F.seltime:= F.time
				END;
				IF F.selection >= Object THEN M.obj:= F
				ELSE
					NEW(F1); NewP(F1, F.selpict);
					Attributes.SetBool(F1, "Locked", TRUE); Attributes.SetBool(F1, "Border", FALSE);
					M.obj:= F1; M.sel:= F
				END
			END
		END
	ELSE
		Gadgets.framehandle(F, M)
	END
END Select;

(** Gibt einen String in den angegebenen Bereich aus *)
PROCEDURE DisplayText*(sx, sy, sw, sh: INTEGER; text: ARRAY OF CHAR);
CONST bg= 3;
VAR i, x: INTEGER; f: Fonts.Font; dx, fx, fy, fw, fh: INTEGER; pat: LONGINT;
BEGIN
	Display.ReplConst(bg, sx, sy, sw, sh, Display.replace);
	i:=0; x:= sx+4; f:= Fonts.Default;
	WHILE text[i]#0X DO
		Fonts.GetChar(f, text[i], dx, fx, fy, fw, fh, pat);
		Display.CopyPattern(D3.BG, pat, x+fx, sy+4+fy, Display.paint);
		x:=x+dx;
		INC(i)
	END
END DisplayText;

(** Testet, ob die Koordinaten mx,my innerhalb des dargestellten Picture sind *)
PROCEDURE InsidePict*(F: Frame; mx, my, x, y: INTEGER): BOOLEAN;
VAR px, py: INTEGER;
BEGIN
	PicttoScreen(F, x, y, 0, 0, px, py);
	IF Effects.Inside(mx, my, px, py, F.pict.width*F.zoom, F.pict.height*F.zoom) THEN RETURN TRUE ELSE RETURN FALSE END
END InsidePict;

PROCEDURE Defocus(F: Frame);
VAR M: DrawCaretMsg;
BEGIN
	IF F.car THEN
		M.res:=-1; M.F:= F; Display.Broadcast(M);
		F.car:= FALSE
	END
END Defocus;

PROCEDURE Neutralize(F: Frame; x, y, w, h: INTEGER);
BEGIN
	Oberon.RemoveMarks(x, y, w, h); Defocus(F); RemoveSelection(F)
END Neutralize;

PROCEDURE DrawGrid(F: Frame; Q: D3.Mask; x,y ,w ,h, picx, picy, picw, pich : INTEGER);
VAR px, py, sx, sy, dh: INTEGER;
BEGIN
	IF picx<0 THEN picw:= picw+picx; picx:= 0 END;
	IF picx+picw>F.pict.width THEN picw:= F.pict.width-picx END;
	IF picy<0 THEN pich:= pich+picy; picy:=0 END;
	IF picy+pich> F.pict.height THEN pich:= F.pict.height-picy END;
	PicttoScreen(F, x, y, picx, picy+pich, sx, sy);
	IF sx<x THEN
		IF (x-sx) < picw*F.zoom THEN
			picx:=picx+(x-sx) DIV F.zoom;
			picw:=picw-(x-sx) DIV F.zoom;
			sx:=x
		ELSE
			picw:=0
		END
	END;
	IF sx>x+w THEN
		picw:=0
	ELSE
		IF sx+picw*F.zoom>x+w THEN
			picw:=picw-(sx+picw*F.zoom-(x+w)) DIV F.zoom
		END;
		IF sy>y+h THEN
			IF sy-(y+h) < pich*F.zoom THEN
				pich:= pich-(sy-(y+h)) DIV F.zoom;
				sy:=y+h; 
			ELSE
				pich:=0
			END;
		END;
		IF sy-pich*F.zoom<y THEN
			dh:= (y-(sy-pich*F.zoom)) DIV F.zoom;
			picy:= picy+dh;
			pich:=pich-dh
		END;
	END;
	IF (picw>0) & (pich>0)  THEN
		px:= 1;
		WHILE px<=picw DO
			D3.ReplConst(Q, D3.black, sx+px*F.zoom-1, sy-pich*F.zoom, 1, pich*F.zoom, Display.invert);
			px:= px+1
		END;
		py:= 1;
		WHILE py<=pich DO
			D3.ReplConst(Q, D3.black, sx, sy-py*F.zoom, picw*F.zoom, 1, Display.invert);
			py:= py+1
		END
	END
END DrawGrid;

PROCEDURE DisplayBlock(F: Frame; Q: D3.Mask; p: Pictures.Picture; x, y ,w ,h, picx, picy, picw, pich: INTEGER);
(* Stellt ein gezoomtes Gebiet auf dem Bildschirm dar *)
VAR px, py, col, px0, dy, ox, oy, sx, sy, dh: INTEGER;
BEGIN
	IF picx<0 THEN picw:= picw+picx; picx:= 0 END;
	IF picx+picw>p.width THEN picw:= p.width-picx END;
	IF picy<0 THEN pich:= pich+picy; picy:=0 END;
	IF picy+pich> p.height THEN pich:= p.height-picy END;
	PicttoScreen(F, x, y, picx, picy+pich, sx, sy);
	(* Clipping *)
	IF sx<x THEN
		IF (x-sx) < picw*F.zoom THEN
			picx:=picx+(x-sx) DIV F.zoom;
			picw:=picw-(x-sx) DIV F.zoom;
			sx:=x
		ELSE
			picw:=0
		END
	END;
	IF sx>x+w THEN
		picw:=0
	ELSE
		IF sx+picw*F.zoom>x+w THEN
			picw:=picw-(sx+picw*F.zoom-(x+w)) DIV F.zoom
		END;
		IF sy>y+h THEN
			IF sy-(y+h) < pich*F.zoom THEN
				pich:= pich-(sy-(y+h)) DIV F.zoom;
				sy:=y+h; 
			ELSE
				pich:=0
			END;
		END;
		IF sy-pich*F.zoom<y THEN
			dh:= (y-(sy-pich*F.zoom)) DIV F.zoom;
			picy:= picy+dh;
			pich:=pich-dh
		END;
	END;
	IF (picw>0) & (pich>0)  THEN
		(* Pixeloutput *)
		ox:= picx; oy:= picy+pich-1; py:= oy;
		WHILE py>=picy DO
			px:=ox; dy:= sy-(oy-py)*F.zoom-F.zoom;
			WHILE px<(picx+picw) DO
				px0:= px;
				Pictures.GetRun(p, col, px, py);
				IF px>(picx+picw) THEN px:= picx+picw END;
				D3.ReplConst(Q, col, sx+(px0-ox)*F.zoom, dy, (px-px0)*F.zoom, F.zoom, Display.replace)
			END;
			DEC(py);
		END;
		IF F.grid THEN DrawGrid(F, Q, x, y, w, h, picx, picy, picw, pich) END;
	END
END DisplayBlock;

(** Zeichnet den Pictureausschnitt neu *)
PROCEDURE RestorePict*(F: Frame; Q: D3.Mask; x, y, w, h, picx, picy, picw, pich: INTEGER);
VAR px, py: INTEGER; p: Pictures.Picture;
BEGIN
	IF F.locked & (F.lockdata.scaledpict # NIL) THEN p := F.lockdata.scaledpict ELSE p := F.pict END;
	
	IF F.border THEN D3.AdjustMask(Q, x+1, y+1, w-2, h-2) END;
	IF F.zoom=1 THEN
		PicttoScreen(F, x, y, picx, picy, px, py);
		D3.Pict(Q, p, picx, picy, picw, pich, px, py, Display.replace)
	ELSE
		DisplayBlock(F, Q, p, x, y, w, h, picx, picy, picw, pich)
	END;
END RestorePict;

PROCEDURE Restore (F: Frame; Q: D3.Mask; x, y, w, h, picx, picy, picw, pich: INTEGER);
(* Zeichnet ein bestimmtes Gebiet neu inkl Background *)
VAR sx, sy: INTEGER; M: D3.Mask; pw, ph: REAL; L: Lockrec;
BEGIN
	NEW(M);
	D3.Open(M);
	D3.Copy(Q, M);
	IF F.locked THEN
		L:= F.lockdata;
		pw:= w/L.lw; ph:= h/L.lh;
		picx:= SHORT(ENTIER(picx*pw+0.5));
		picy:= SHORT(ENTIER(picy*ph+0.5)); 
		picw:= SHORT(ENTIER(F.pict.width*pw+0.5));
		pich:= SHORT(ENTIER(F.pict.height*ph+0.5));

		IF (pw = 1) & (ph = 1) THEN L.scaledpict := NIL
		ELSIF (w # L.actlw) OR (h # L.actlh) THEN
			L.actlw:= w; L.actlh:= h;
			F.px:= SHORT(ENTIER(L.lpx*pw+0.5)); F.py:= SHORT(ENTIER(L.lpy*ph+0.5));
			NEW(L.scaledpict);
			Rembrandt0.AllocatePictureMem(L.scaledpict, picw, pich, F.pict.depth);	(* tk *)
			IF L.scaledpict # NIL THEN
				Pictures.Copy(F.pict, L.scaledpict, 0, 0, F.pict.width, F.pict.height, 0, 0, L.scaledpict.width, L.scaledpict.height, Display.replace)
			ELSE
				Out.String(" out of memory"); Out.Ln
			END;
		END;
		F.lockdata:= L
	END;
	RestorePict(F, M, x, y, w, h, picx, picy, picw, pich);
	IF F.border THEN D3.AdjustMask(M, x+1, y+1, w-2, h-2) END;
	(* Restore Background *)
	PicttoScreen(F, x, y, picx, picy, sx, sy);
	IF sx>x THEN	(* left *)
		D3.ReplConst(M, F.col, x, sy, sx-x, pich*F.zoom, Display.replace)
	END;
	IF sx+picw*F.zoom < x+w THEN	(* right *)
		D3.ReplConst(M, F.col, sx+picw*F.zoom, sy, x+w-sx-picw*F.zoom, pich*F.zoom, Display.replace)
	END;
	IF sy+pich*F.zoom<y+h THEN	(* top *)
		D3.ReplConst(M, F.col, x, sy+pich*F.zoom, w, y+h-sy-pich*F.zoom, Display.replace)
	END;
	IF sy>y THEN	(* bottom *)
		D3.ReplConst(M, F.col, x, y, w, sy-y, Display.replace)
	END; 
	(* Rand *)
	IF F.border THEN D3.Rect3D(Q, D3.topC, D3.bottomC, x, y, w, h, 1, Display.replace) END;
	IF Gadgets.selected IN F.state THEN
     	D3.FillPattern(Q, D3.white, D3.selectpat, x, y, x, y, w, h, Display.paint)		(* Version 1.6 *)
	END
END Restore;

PROCEDURE DrawCaret(Q: D3.Mask; x, y: INTEGER);
BEGIN
	Oberon.FadeCursor(Oberon.Mouse);
	D3.CopyPattern(Q, D3.black, Display.cross, x-6, y-6, Display.invert)
END DrawCaret;

PROCEDURE SetCaret(F: Frame; cx, cy: INTEGER);
VAR M: DrawCaretMsg;
BEGIN
	Oberon.Defocus; 
	F.car:= TRUE;
	F.cx:=cx; F.cy:= cy; 
	M.res:=-1; M.F:=F; Display.Broadcast(M);
END SetCaret;

PROCEDURE Print (F: Frame; VAR M: Display.DisplayMsg);
VAR R: D3.Mask;

  PROCEDURE PP(x: INTEGER): INTEGER;
  BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
  END PP;

BEGIN
	IF M.id = Display.contents THEN
		NEW(R); D3.Open(R); D3.Add(R, Printer.FrameX, Printer.FrameY, Printer.FrameW, Printer.FrameH);
		R.X := Printer.FrameX; R.Y := Printer.FrameY; R.W := Printer.FrameW; R.H := Printer.FrameH; R.x := 0; R.y := 0;
		Printer3.Pict(R, F.pict, Printer.FrameX, Printer.FrameY + Printer.FrameH - PP(F.pict.height),
			PP(F.pict.width), PP(F.pict.height), Display.replace);
		Printer.Page(1)
	ELSE
		Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
		Printer3.Pict(R, F.pict, M.x, M.y, PP(F.W), PP(F.H), Display.replace)
	END
END Print;

(** Kopiert ein Rembrandt-Gadget *)
PROCEDURE Copy* (VAR M: Objects.CopyMsg; from, to: Frame);
VAR obj:Objects.Object; C: Objects.CopyMsg;
BEGIN 
	Gadgets.CopyFrame(M, from, to);
	to.col := from.col; 
	to.px:=  from.px; to.py:= from.py;
	to.selection:= No; to.selstruct:= NIL;
	to.locked:= from.locked; to.lockdata:= from.lockdata;
	to.zoom:= from.zoom;
	to.grid:= from.grid;
	to.car:= FALSE;
	to.border:= from.border;
	to.time:= from.time; to.seltime:= from.seltime; to.selpict:= from.selpict; to.selcol:= from.selcol;
	
	obj := Gadgets.CopyPtr(M, from.pict);
	IF obj # NIL THEN to.pict := obj(Pictures.Picture) END;
	
	IF from.lockdata.scaledpict # NIL THEN
		C.id := Objects.deep; C.obj := NIL; Objects.Stamp(C);
		from.lockdata.scaledpict.handle(from.lockdata.scaledpict, C);
		to.lockdata.scaledpict:= C.obj(Pictures.Picture);
	END
END Copy;

PROCEDURE StoreFrame(F: Frame; VAR M: Objects.FileMsg);
BEGIN
	Files.WriteInt(M.R, 16971);
	Gadgets.framehandle(F, M);
	Files.WriteInt(M.R, F.col); Files.WriteBool(M.R, F.locked);
	IF F.locked THEN
		Files.WriteInt(M.R, F.lockdata.lw); Files.WriteInt(M.R, F.lockdata.lh);
		Files.WriteInt(M.R, F.lockdata.lpx); Files.WriteInt(M.R, F.lockdata.lpy);
		Files.WriteInt(M.R, F.lockdata.actlw); Files.WriteInt(M.R, F.lockdata.actlh);
		Files.WriteInt(M.R, F.pict.width); Files.WriteInt(M.R, F.pict.height)
	END;
	Files.WriteBool(M.R, F.border); Files.WriteInt(M.R, F.px);
	Files.WriteInt(M.R, F.py);
	Files.WriteInt(M.R, F.W);
	Files.WriteInt(M.R, F.H);
	Gadgets.WriteRef(M.R, F.lib, F.pict)
END StoreFrame;

PROCEDURE LoadFrame(F: Frame; VAR M: Objects.FileMsg);
VAR version, w, h: INTEGER; obj: Objects.Object;
BEGIN
	Files.ReadInt(M.R, version);
	IF (version#16970) & (version#16971) THEN HALT(99) END; 
	Gadgets.framehandle(F, M);
	Files.ReadInt(M.R, F.col); Files.ReadBool(M.R, F.locked);
	IF F.locked THEN
		Files.ReadInt(M.R, F.lockdata.lw); Files.ReadInt(M.R, F.lockdata.lh);
		Files.ReadInt(M.R, F.lockdata.lpx); Files.ReadInt(M.R, F.lockdata.lpy);
		Files.ReadInt(M.R, F.lockdata.actlw); Files.ReadInt(M.R, F.lockdata.actlh);
		Files.ReadInt(M.R, w); Files.ReadInt(M.R, h)
	END;
	Files.ReadBool(M.R, F.border); Files.ReadInt(M.R, F.px);
	Files.ReadInt(M.R, F.py);
	Files.ReadInt(M.R, F.W);
	Files.ReadInt(M.R, F.H);
	IF version = 16970 THEN
		F.pict.handle(F.pict, M);
		IF (F.lib # NIL) & (F.lib.name # "") & (F.pict.lib # F.lib) THEN Gadgets.BindObj(F.pict, F.lib) END
	ELSIF version = 16971 THEN
		Gadgets.ReadRef(M.R, F.lib, obj);
		IF (obj # NIL) & (obj IS Pictures.Picture) THEN F.pict := obj(Pictures.Picture)
		ELSE
			Out.String("  discarding picture object ");
			IF (obj # NIL) & (obj IS Objects.Dummy) THEN Out.String(obj(Objects.Dummy).GName) END;
			Out.Ln;
			NEW(F.pict); Pictures.Create(F.pict, 32, 32, Display.Depth(0))
		END
	ELSE HALT(99)
	END;
	IF F.locked  THEN
		F.lockdata.actlw := 0; F.lockdata.actlh := 0
	END
END LoadFrame;

(** Sichert den angegebenen Bereich des Picture als Undo-Information *)
PROCEDURE SavePicture*(P: Pictures.Picture; x, y ,w, h: INTEGER);
BEGIN
	IF undo=NIL THEN NEW(undo) END;
	NEW(undo.P); 
	Rembrandt0.AllocatePictureMem(undo.P, w, h, P.depth);
	CopyPalette(P, undo.P);	(* tk *)
	IF undo.P#NIL THEN
		Pictures.CopyBlock(P, undo.P, x, y, w, h, 0, 0, Display.replace);
		undo.px:=x; undo.py:= y; undo.pict:= P;  undo.next:= NIL
	END	
END SavePicture;

PROCEDURE ScanBorder(S: Pictures.Picture; y0: INTEGER; VAR list: Element);
VAR i, x, y, decx, decy, x0 : INTEGER; vertex, act, last: Element; 
BEGIN
	y:=y0; x0:=0; WHILE Pictures.Get(S, x0+1, y0)=0 DO INC(x0) END;
	x:= x0; 
	i:= 3; NEW(vertex); vertex.x:= -2; vertex.y:= -2; list:= vertex; 
	NEW(vertex); vertex.x:= x0-1; vertex.y:= y0-1; vertex.next:= NIL; list.next:= vertex;
	REPEAT
		WHILE Pictures.Get(S, seldir[i].dx+x, seldir[i].dy+y)#0 DO i:= (i+1) MOD 4 END;
		x:= x+seldir[i].dx; y:= y+seldir[i].dy; decx:= x-1; decy:= y-1;
		(* Add to sorted List *)
		act:= list;
		WHILE (act.y<decy) & (act.next#NIL) DO last:= act; act:= act.next END;
		WHILE (act.x<decx) & (act.y=decy) & (act.next#NIL) DO last:= act; act:= act.next END;
		IF (act.y#decy) OR (act.x#decx) THEN
			NEW(vertex); vertex.x:= decx; vertex.y:= decy;
			IF (act.next=NIL) & ((act.y<decy) OR ((act.x<decx) & (act.y=decy))) THEN last:= act END;
			vertex.next:= last.next; last.next:= vertex;
		END;
		i:= seldir[i].ind;
	UNTIL (x=x0) & (y=y0); 
END ScanBorder;

PROCEDURE SelectArea(F: Frame; P: Pictures.Picture; x0, y0: INTEGER);
CONST    size=10;

TYPE Stack=POINTER TO StackDesc;
		StackDesc=RECORD
			x, y: ARRAY size OF INTEGER;
			prev, next: Stack;
		END;

VAR  st: Stack;
		bg,fg : INTEGER; 
		x, y, 	
		l, r, 		(*left and right border of actual line*)
		l0, r0, 	(*left and right border of previous line*)
		l2, r2, 
		pos: INTEGER;  	(*stack pointer*)
		first, act: Element; 
	
	PROCEDURE PUT(x, y: INTEGER);
	(*put the pair x, y onto the stack*)
	BEGIN
		IF pos=size THEN
			IF st.next=NIL THEN NEW(st.next);  st.next.prev:=st END;
			st:=st.next;  pos:=0;
		END; (*if*)
		st.x[pos]:=x;  st.y[pos]:=y;
		INC(pos);
	END PUT;
	
	PROCEDURE GET(VAR x, y: INTEGER): BOOLEAN;
	(*fetch the pair x, y from the stack, return FALSE<=>stack is empty*)
	BEGIN
		IF pos=0 THEN
			st:=st.prev;  pos:=size;
		END;
		IF st#NIL THEN
			DEC(pos);
			x:=st.x[pos];  y:=st.y[pos];
			RETURN TRUE;
		ELSE
			RETURN FALSE;
		END; (*if*)
	END GET;

	PROCEDURE ScanRight(x0, lim, y: INTEGER;  background : BOOLEAN): INTEGER;
	(*scan line on y to first pixel in col, starting at x0*)
	BEGIN
		IF background THEN WHILE (x0<lim) & (bg # Pictures.Get(P,x0,y)) DO INC(x0) END;
		ELSE WHILE (x0<lim) & (bg = Pictures.Get(P,x0,y)) DO INC(x0) END END;
		RETURN x0;
	END ScanRight;
	
	PROCEDURE ScanLeft(x0, lim, y: INTEGER;  background : BOOLEAN): INTEGER;
	(*scan line on y to first pixel in col, starting at x0*)
	BEGIN
		IF background THEN WHILE (x0>lim) & (bg #  Pictures.Get(P,x0,y)) DO DEC(x0) END;
		ELSE WHILE (x0>lim) & (bg = Pictures.Get(P,x0,y)) DO DEC(x0) END END;
		RETURN x0;
	END ScanLeft;
	
	PROCEDURE FillLine(x, y: INTEGER;  VAR l, r: INTEGER);
	(*fill line starting at x, y with black, return left & right end of line*)
	VAR p: Element;

	BEGIN
		l:=ScanLeft(x, -1, y, FALSE)+1;
		IF l>x THEN (*no line to fill*)
			r:=x-1; 
		ELSE
			r := ScanRight(x, P.width,y,FALSE)-1;
			IF r>=P.width THEN r:=P.width-1 END;
			NEW(p); p.x:= l; p.y:= y; p.w:= r-l+1; p.next:= first; first:=p;
			 Pictures.ReplConst(P, fg, l, y,p.w,1,Display.replace);
			F.sx:= Min(F.sx, l); F.sy:= Min(F.sy, y); F.sw:= Max(F.sw, r+1); F.sh:= Max(F.sh, y);
		END; (*if*)
	END FillLine;

BEGIN
	F.sx:=MAX(INTEGER); F.sy:=MAX(INTEGER); F.sw:=0; F.sh:=0;
	bg := Pictures.Get(P,x0, y0);
	first:= NIL;
	IF Rembrandt0.color.col = bg THEN fg:= Rembrandt0.color.col+1 ELSE fg:= Rembrandt0.color.col END;
	NEW(st); pos:=0;
	PUT(x0, y0);
	WHILE GET(x, y) DO
		WHILE (y>0) & (Pictures.Get(P,x, y-1)= bg) DO DEC(y) END;
		r0:=x-1;  l0:=x+1;
		REPEAT
			FillLine(x, y, l, r);
			IF (r-r0>1) & (y>0) THEN	(*fill area to the right beneath y*)
				l2:=r0+1;
				LOOP
					l2:=ScanRight(l2, r+1, y-1, TRUE);
					IF l2<=r THEN
						r2:=ScanRight(l2, P.width, y-1, FALSE)-1;
						PUT((l2+r2) DIV 2, y-1);  l2:=r2+1;
					ELSE
						EXIT;
					END; (*if*)
				END; (*loop*)
			ELSIF (r0-r>1) THEN	(*fill area to the right above y*)
				l2:=r+1;
				LOOP
					l2:=ScanRight(l2, r0+1, y, TRUE);
					IF l2<=r0 THEN
						r2:=ScanRight(l2, P.width, y, FALSE)-1;
						PUT((l2+r2) DIV 2, y);  l2:=r2+1;
					ELSE
						EXIT;
					END; (*if*)
				END; (*loop*)
			END; (*if*)
			IF (l0-l>1) & (y>0) THEN	(*fill area to the left beneath y*)
				r2:=l0-1;
				LOOP
					r2:=ScanLeft(r2, l-1, y-1, TRUE);
					IF r2>=l THEN
						l2:=ScanLeft(r2, -1, y-1, FALSE)+1;
						PUT((l2+r2) DIV 2, y-1);  r2:=l2-1;
					ELSE
						EXIT;
					END; (*if*)
				END; (*loop*)
			ELSIF (l-l0>1) THEN	(*fill area to the left above y*)
				r2:=l-1;
				LOOP
					r2:=ScanLeft(r2, l0-1, y, TRUE);
					IF r2>=l0 THEN
						l2:=ScanLeft(r2, -1, y, FALSE)+1;
						PUT((l2+r2) DIV 2, y);  r2:=l2-1;
					ELSE
						EXIT;
					END; (*if*)
				END; (*loop*)
			END; (*if*)
			INC(y);
			l0:=l;  r0:=r;
		UNTIL (y=P.height) OR (l>r);
	END; (*while*) 
	F.sw:= F.sw-F.sx; F.sh:= F.sh-F.sy+1;
	act:= first; F.selcol:= bg;
	(* Koordinaten relativieren *)
	WHILE act#NIL DO
		Pictures.ReplConst(P, bg, act.x, act.y, act.w, 1, Display.replace);
		act.x:= act.x-F.sx; act.y:= act.y-F.sy; 
		act:= act.next
	END;
	F.selstruct:= first;
END SelectArea;

PROCEDURE TrackObjectSelection(F: Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR x0, y0, oldsel: INTEGER; keysum: SET; P: Pictures.Picture; act: Element; f: Frame; fM: FocusMsg;
BEGIN
	oldsel:= F.selection;
	RemoveSelection(F);
	keysum:= M.keys;
	IF (MR IN keysum) & (keysum#Cancel) & (oldsel#Object) THEN
		ScreentoPict(F, x, y, M.X, M.Y, x0, y0);
		IF Effects.Inside(x0, y0, 0, 0, F.pict.width, F.pict.height) THEN
			SelectArea(F, F.pict, x0, y0); 
			NEW(P); Rembrandt0.AllocatePictureMem(P, F.sw+2, F.sh+2, F.pict.depth);	(* tk *)
			CopyPalette(F.pict, P);
			act:= F.selstruct;
			WHILE act#NIL DO
				Pictures.ReplConst(P, D3.FG, act.x+1, act.y+1, act.w, 1, Display.replace);
				act:= act.next
			END;
			ScanBorder(P, y0+1-F.sy, F.seloutline); 
			SetSelection(F, Object);
		END
	END;
	REPEAT
		Oberon.DrawCursor(Oberon.Mouse, cursor, M.X, M.Y);
		Input.Mouse(M.keys, M.X, M.Y);
		keysum:= keysum+M.keys;
	UNTIL M.keys={};
	IF keysum={MR, ML} THEN	(* Selektion löschen *)
		SavePicture(F.pict, F.sx, F.sy, F.sw, F.sh);
		act:= F.selstruct;
		WHILE act#NIL DO
			Pictures.ReplConst(F.pict, D3.BG, F.sx+act.x, F.sy+act.y, act.w, 1, Display.replace);
			act:= act.next
		END;
		Pictures.Update(F.pict, F.sx, F.sy, F.sw, F.sh)
	ELSIF keysum={MR, MM} THEN	(* Selektion kopieren *)
		fM.F:= NIL; fM.res:=-1; Display.Broadcast(fM);
		IF (fM.F#NIL) & (fM.F IS Frame) THEN
			f:= fM.F(Frame);
			SavePicture(f.pict, f.cx, f.cy, F.sw, F.sh);
			act:= F.selstruct;
			WHILE act#NIL DO
				Rembrandt0.ReplConst(f.pict, F.selcol, f.cx+act.x, f.cy+act.y, act.w, 1);
				act:= act.next
			END;
			Pictures.Update(f.pict, f.cx, f.cy, F.sw, F.sh)
		END
	END
END TrackObjectSelection;

PROCEDURE ProcessList(F: Frame; VAR first: Element);
VAR act: Element;  P: Pictures.Picture; x0, y0, col: INTEGER;
BEGIN col:=D3.FG;
	y0:=F.sh DIV 2; x0:= 1;
	first:= first.next;
	NEW(P); Rembrandt0.AllocatePictureMem(P, F.sw+2, F.sh+2, F.pict.depth);	(* tk *)
	CopyPalette(F.pict, P);
	IF P#NIL THEN
		WHILE first#NIL DO
			Pictures.Dot(P, col, first.x-F.sx+1, first.y-F.sy+1, Display.replace);
			IF y0=first.y-F.sy THEN x0:= first.x-F.sx END;
			first:= first.next
		END;
		ScanBorder(P, y0, F.seloutline);
		Rembrandt0.AllocatePictureMem(P, F.sw+2, F.sh+2, F.pict.depth);	(* tk *)
		CopyPalette(F.pict, P);
		IF P#NIL THEN
			act:= F.seloutline.next; 
			WHILE act#NIL DO
				Pictures.ReplConst(P, col, act.x, act.y, 1, 1, Display.replace);
				act:= act.next
			END; 
			SelectArea(F, P, x0, y0);
			act:= F.selstruct.next; first:= act;
			IF act=NIL THEN F.selstruct:= NIL END
		ELSE
			first:= NIL
		END
	ELSE
		first:= NIL
	END
END ProcessList;

PROCEDURE Line(x0, y0, x1, y1: INTEGER; VAR first: Element);
VAR x, y, d, dx, dy, incx, incy, oldy: INTEGER;

	PROCEDURE AddtoList(x, y: INTEGER; w: INTEGER);
	VAR p: Element;
	BEGIN
		NEW(p); p.x:= x; p.y:= y; p.w:= w;
		p.next:= first.next; first.next:= p
	END AddtoList;

BEGIN
	x:= x0; y:= y0; 
	dx:= (x1-x0)*2; dy:= (y1-y0)*2;
	incx:=0;
	IF dx<0 THEN incx:=-1; dx:=-dx ELSIF dx>0 THEN incx:=1 END;
	incy:=0;
	IF dy<0 THEN incy:=-1; dy:=-dy ELSIF dy>0 THEN incy:=1 END;
	d:= incx*(x0-x1); oldy:= y;
	AddtoList(x, y, 1); 
	IF dx>dy THEN
		WHILE x#x1 DO
			INC(x, incx); INC(d, dy);
			IF d>0 THEN INC(y, incy); DEC(d, dx) END;
			AddtoList(x, y, oldy-y);
			oldy:= y
		END
	ELSE
		WHILE y#y1 DO
			INC(y, incy); INC(d, dx);
			IF d>0 THEN INC(x, incx); DEC(d, dy) END;
			AddtoList(x, y, oldy-y);
			oldy:= y
		END
	END;
END Line;

(** Zeichnet eine Linie von x0, y0 nach x1, y1 mit Dicke dw; kann als Gummilinie benutzt werden *)
PROCEDURE DisplayLine*(F: Frame; x, y: INTEGER; Q: D3.Mask; col, x0, y0, x1, y1, dw: INTEGER);
VAR lx, ly, d, dx, dy, incx, incy, sx, sy: INTEGER;
BEGIN
	ScreentoPict(F, x, y, x0, y0, x0, y0);
	ScreentoPict(F, x, y, x1, y1, x1, y1);
	lx:= x0; ly:= y0;
	PicttoScreen(F, x, y, lx, ly, sx, sy);
	D3.ReplConst(Q, col, sx, sy, dw, dw, Display.invert);
	dx:= (x1-x0)*2; dy:= (y1-y0)*2;
	incx:=0;
	IF dx<0 THEN incx:=-1; dx:=-dx ELSIF dx>0 THEN incx:=1 END;
	incy:=0;
	IF dy<0 THEN incy:=-1; dy:=-dy ELSIF dy>0 THEN incy:=1 END;
	d:= incx*(x0-x1);
	IF dx>dy THEN
		WHILE lx#x1 DO
			INC(lx, incx); INC(d, dy);
			IF d>0 THEN INC(ly, incy); DEC(d, dx) END;
			PicttoScreen(F, x, y, lx, ly, sx, sy);
			D3.ReplConst(Q, col, sx, sy, dw, dw, Display.invert);
		END
	ELSE
		WHILE ly#y1 DO
			INC(ly, incy); INC(d, dx);
			IF d>0 THEN INC(lx, incx); DEC(d, dy) END;
			PicttoScreen(F, x, y, lx, ly, sx, sy);
			D3.ReplConst(Q, col, sx, sy, dw, dw, Display.invert);
		END
	END
END DisplayLine;

PROCEDURE TrackFreehandSelection(F: Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR x0, y0, ox, oy, mx, my, px0, py0, px1, py1, startx, starty, oldsel: INTEGER; keysum: SET; list: Element;
		ofsx, ofsy, ofsw, ofsh: INTEGER; nomove: BOOLEAN;
		prev, last: RECORD x, y: INTEGER END; Q: D3.Mask;
BEGIN
	oldsel:= F.selection;
	RemoveSelection(F);
	Gadgets.MakeMask(F, x, y, M.dlink, Q); 
	NEW(list); list.next:= NIL; list.x:=-1; list.y:= -1; 
	nomove:= TRUE;
	ScreentoPict(F, x, y, M.X, M.Y, startx, starty); PicttoScreen(F, x, y, startx, starty, mx, my);
	x0:= mx; y0:= my;
	keysum:= M.keys; 
	ScreentoPict(F, x, y, mx, my, px0, py0);
	WHILE ~Effects.Inside(px0, py0, 0, 0, F.pict.width, F.pict.height) & (M.keys#{}) DO
		Input.Mouse(M.keys, mx, my);
		x0:= mx; y0:= my;
		ScreentoPict(F, x, y, mx, my, px0, py0); startx:= px0; starty:= py0;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, mx+F.zoom DIV 2, my+F.zoom DIV 2);
	END; 
	Oberon.FadeCursor(Oberon.Mouse);
	DisplayLine(F, x, y, Q, F.selcolor, x0, y0, x0, y0, F.zoom);
	F.sx:= px0; F.sy:= py0; F.sw:= px0; F.sh:= py0;
	prev.x:= MAX(INTEGER); prev.y:= MAX(INTEGER); last:= prev;;
	REPEAT
		ox:=mx; oy:= my;
		Input.Mouse(M.keys, mx, my);
		ScreentoPict(F, x, y, mx, my, px1, py1); PicttoScreen(F, x, y, px1, py1, mx, my);
		IF (mx#ox) OR (my#oy) THEN
			Oberon.FadeCursor(Oberon.Mouse);
			DisplayLine(F, x, y, Q, F.selcolor, x0, y0, ox, oy, F.zoom);
			DisplayLine(F, x, y, Q, F.selcolor, x0, y0, mx, my, F.zoom);
		END;
		IF keysum = {MR, MM}  THEN
			IF (px0#px1) OR (py0#py1) THEN
				IF Effects.Inside(px1, py1, 0, 0, F.pict.width, F.pict.height) THEN
					Line(px0, py0, px1, py1, list);
					F.sx:= Min(px1, F.sx); F.sy:= Min(py1, F.sy); F.sw:= Max(px1, F.sw); F.sh:= Max(py1, F.sh);
					x0:= mx; y0:= my; nomove:= FALSE;
					px0:= px1; py0:= py1
				END
			END;
			EXCL(keysum, MM);
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Cross, mx+F.zoom DIV 2, my+F.zoom DIV 2);
		keysum := keysum + M.keys;
	UNTIL M.keys={};
	Oberon.FadeCursor(Oberon.Mouse);
	IF (MR IN keysum) & (keysum#Cancel)  & ~nomove THEN
		PicttoScreen(F, x, y, startx, starty, px1, py1);
		DisplayLine(F, x, y, Q, F.selcolor, x0, y0, px1, py1, F.zoom);
		Line(px0, py0, startx, starty, list);
		F.sw:= F.sw-F.sx+2; F.sh:= F.sh-F.sy+2;
		IF (F.sw>2) & (F.sh>2)  THEN
			ofsx:= F.sx; ofsy:= F.sy; ofsw:= F.sw; ofsh:= F.sh;
			ProcessList(F, list);
			F.sx:= ofsx; F.sy:= ofsy; F.sw:= ofsw; F.sh:= ofsh;
			F.selcol:= Rembrandt0.color.col;
			IF keysum = {MR, ML} THEN	(* Selektion löschen *)
				SavePicture(F.pict, F.sx, F.sy, F.sw, F.sh);
				WHILE list#NIL DO Pictures.ReplConst(F.pict, D3.BG, F.sx+list.x, F.sy+list.y, list.w, 1, Display.replace); list:= list.next END;
				Pictures.Update(F.pict, F.sx, F.sy, F.sw, F.sh)
			ELSE
				Pictures.Update(F.pict, F.sx, F.sy, F.sw, F.sh);
				IF list #NIL THEN SetSelection(F, Freehand) END
			END
		ELSE
			Pictures.Update(F.pict, F.sx, F.sy, F.sw, F.sh)
		END
	ELSIF (keysum = {MR}) & nomove & (oldsel=No) THEN
		F.seloutline:= NIL;
		F.sx:=0; F.sy:= 0; F.sw:= F.pict.width; F.sh:= F.pict.height;
		Pictures.Update(F.pict, F.sx, F.sy, F.sw, F.sh);
		SetSelection(F, Image);
	ELSE
		DisplayLine(F, x, y, Q, F.selcolor, x0, y0, ox, oy, F.zoom);
		Pictures.Update(F.pict, 0, 0, F.pict.width, F.pict.height); F.seloutline:= NIL;
	END;
END TrackFreehandSelection;

(* PROCEDURE UndoRedo(VAR s, d: Region);
VAR last, act: Region; p: Pictures.Picture;
BEGIN
	IF s#NIL THEN
		NEW(p);
		Rembrandt0.AllocatePictureMem(p, s.P.width, s.P.height, s.P.depth);
		CopyPalette(s.F.pict, p);	(* tk *)
		IF p#NIL THEN
			Pictures.CopyBlock(s.F.pict,  p, s.px, s.py, s.P.width, s.P.height, 0, 0, Display.replace);
			Pictures.CopyBlock(s.P, s.F.pict, 0, 0, s.P.width, s.P.height, s.px, s.py, Display.replace);
			last:= s; s:= s.next; last.next:= d; d:= last; d.P:= p; 
			Pictures.Update(last.F.pict, 0, 0, last.F.pict.width, last.F.pict.height)
		ELSE
			WHILE (s#NIL) & (p=NIL) DO
				act:= s; last:= NIL; WHILE act.next#NIL DO last:= act; act:= act.next END;
				IF last=NIL THEN s:=NIL ELSE last.next:= NIL END;
				NEW(p);
				Rembrandt0.AllocatePictureMem(p, s.P.width, s.P.height, s.P.depth);
				CopyPalette(s.F.pict, p);	(* tk *)
			END;
			IF p#NIL THEN
				Pictures.CopyBlock(s.F.pict,  p, s.px, s.py, s.P.width, s.P.height, 0, 0, Display.replace);
				Pictures.CopyBlock(s.P, s.F.pict, 0, 0, s.P.width, s.P.height, s.px, s.py, Display.replace);
				last:= s; s:= s.next; last.next:= d; d:= last; d.P:= p; 
				Pictures.Update(last.F.pict, 0, 0, last.F.pict.width, last.F.pict.height)
			END
		END
	END
END UndoRedo; *)

(** Undo; kopiert den zuvor gesicherten Bereich ins entsprechende Picture zurück *)
PROCEDURE Undo*;	(* Redo für 1 Level gleich *)
VAR p: Pictures.Picture;
BEGIN
	(* UndoRedo(undo, redo) *)
	IF (undo#NIL) & (undo.P#NIL) THEN
		NEW(p);
		Rembrandt0.AllocatePictureMem(p, undo.P.width, undo.P.height, undo.P.depth);
		CopyPalette(undo.pict, p);
		IF p#NIL THEN Pictures.CopyBlock(undo.pict, p, undo.px, undo.py, undo.P.width, undo.P.height, 0, 0, Display.replace) END;
		Pictures.CopyBlock(undo.P, undo.pict, 0, 0, undo.P.width, undo.P.height, undo.px, undo.py, Display.replace);
		IF p#NIL THEN undo.P:= p END;
		Pictures.Update(undo.pict, 0, 0, undo.pict.width, undo.pict.height)
	END
END Undo;

(* PROCEDURE Redo*;
BEGIN
	UndoRedo(redo, undo)
END Redo; *)

PROCEDURE WriteChar(F: Frame; lib: Objects.Library; col: INTEGER; ch: CHAR; VAR px, py: INTEGER);
(* Schreibt einen Buchstaben an die Position px, py im Picture *)
VAR dx: INTEGER; obj: Objects.Object; 
BEGIN
	IF (px# F.string.x) OR (py#F.string.y) THEN
		F.string.len:=0;
		SavePicture(F.pict, 0, 0, F.pict.width, F.pict.height)
	END; 
	dx:=0; 
	IF ch=0DX THEN
		(* Return-Taste gedrückt *)
		py:= py-lib(Fonts.Font).height;
		px:= px-F.string.len;
		F.string.len:=0
	ELSIF (ch>= " ") OR (ch=09X) THEN
		lib.GetObj(lib, ORD(ch), obj);
		WITH obj: Fonts.Char DO
			dx:= obj.dx;
			IF (px>=0) & (px+obj.w<F.pict.width) & (py>=0) & (py+obj.h<F.pict.height) THEN
				Pictures.CopyPattern(F.pict, Rembrandt0.color.col, obj.pat, px+obj.x, py+obj.y, Display.paint);
			END
		END
	END;
	px:=px+dx;
	INC(F.string.len, dx);
	F.string.x:=px; F.string.y:= py;
END WriteChar;

PROCEDURE Write(F: Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR obj: Objects.Object; VAR px, py: INTEGER;
BEGIN
	px:= F.cx; py:= F.cy;
	WriteChar(F, M.fnt, Rembrandt0.color.col, M.ch, px, py);
	M.fnt.GetObj(M.fnt, ORD(M.ch), obj);
	WITH obj: Fonts.Char DO
		Pictures.Update(F.pict, px-obj.dx+obj.x, py+obj.y, obj.w, obj.h);
		SetCaret(F, px, py)
	END;
	M.res:= 0
END Write;

PROCEDURE CopyText(F: Frame; text: Texts.Text; beg, end: LONGINT; x, y: INTEGER);
(* Kopiert einen selektierten Text an die Caretposition im Picture *)
VAR R: Texts.Reader; ch: CHAR; px, py: INTEGER;
BEGIN
	Texts.OpenReader(R, text, beg);
	Texts.Read(R, ch);
	px:= F.cx; py:= F.cy;
	WHILE beg<end DO
		WriteChar(F, R.lib, R.col, ch, px, py);
		Texts.Read(R, ch);
		INC(beg);
	END;
	Pictures.Update(F.pict, 0, 0, F.pict.width, F.pict.height);
	SetCaret(F, px, py);
END CopyText;

PROCEDURE CopyOver(F: Frame; P: Pictures.Picture; x, y: INTEGER);
BEGIN
	IF F.car & (P # NIL) THEN
		Oberon.RemoveMarks(x, y, F.W, F.H);
		SavePicture(F.pict, F.cx, F.cy, P.width, P.height);
		Pictures.CopyBlock(P, F.pict, 0, 0, P.width, P.height, F.cx, F.cy, Display.replace);
		Pictures.Update(F.pict, F.cx, F.cy, P.width, P.height)
	END
END CopyOver;

(** Aufspannen eines Rechtecks mit der Maus; analog Effects.SizeRect jedoch zusätzlich mit Prozentangabe falls info=TRUE *)
PROCEDURE SizeRect*(F: Frame; x, y: INTEGER; Q: D3.Mask; VAR keysum: SET; VAR mx, my, sx, sy, sw, sh: INTEGER; info: BOOLEAN);
VAR keys: SET; ox, oy, opx, opy, dz, oldsw, oldsh, cmx, cmy: INTEGER; disptext: ARRAY 22 OF CHAR;

	PROCEDURE ConvertNumberstoText(x, y: LONGINT; VAR text: ARRAY OF CHAR);
	BEGIN
		text[0]:= "X"; text[1]:= ":"; text[2]:= " ";
		IF x>999 THEN text[3]:= CHR(x DIV 1000+48) ELSE text[3]:= " " END;
		text[4]:= CHR((x MOD 1000) DIV 100 +48);
		text[5]:= CHR((x MOD 100) DIV 10 +48);
		text[6]:= CHR(x MOD 10 +48);
		text[7]:= " "; text[8]:= "%"; text[9]:= " "; text[10]:= " ";
		text[11]:= "Y"; text[12]:= ":"; text[13]:= " ";
		IF y>999 THEN text[14]:= CHR(y DIV 1000+48) ELSE text[14]:= " " END;
		text[15]:= CHR((y MOD 1000) DIV 100 +48);
		text[16]:= CHR((y MOD 100) DIV 10 +48);
		text[17]:= CHR(y MOD 10 +48);
		text[18]:= " "; text[19]:= "%"; text[20]:= 0X;
	END ConvertNumberstoText;

BEGIN
	keys:= keysum; oldsw:= sw; oldsh:= sh; dz:= F.zoom; cmx:= sx+sw*dz DIV 2-50; cmy:= sy+sh*dz DIV 2;
	ScreentoPict(F, x, y, mx, my, mx, my); PicttoScreen(F, x, y, mx, my, mx, my);
	ScreentoPict(F, x, y, sx, sy, sx, sy); PicttoScreen(F, x, y, sx, sy, sx, sy);
	IF (sw=0) OR (sh=0) THEN
		ox:= mx; oy:= my;
		opx:= ox; opy:= oy; 
	ELSE
		IF sx+sw DIV 2 >mx THEN
			IF sy+sh DIV 2 >my THEN opx:= sx+sw; opy:= sy+sh; ox:= sx; oy:= sy
			ELSE opx:= sx+sw; opy:= sy; ox:= sx; oy:= sy+sh
			END
		ELSE
			IF sy+sh DIV 2 >my THEN opx:= sx; opy:= sy+sh; oy:= sy; ox:= sx+sw
			ELSE opx:= sx; opy:= sy; oy:= sy; ox:= sx
			END 
		END
	END;
	Oberon.FadeCursor(Oberon.Mouse); 
	IF info THEN
		ConvertNumberstoText((100*(LONG(sw DIV F.zoom))) DIV (oldsw DIV F.zoom), (100*(LONG(sh DIV F.zoom))) DIV (oldsh DIV F.zoom), disptext);
		Effects.OpenMenu(cmx, cmy, 100, 16);
		DisplayText(cmx, cmy, 100, 16, disptext)
	END;
	D3.Rect(Q, selcolor, Display.solid, sx, sy, sw, sh, dz, Display.invert); 
	Oberon.DrawCursor(Oberon.Mouse, cursor, mx, my);
	REPEAT
		IF (ox#mx) OR (oy#my) THEN
			Oberon.FadeCursor(Oberon.Mouse); 
			D3.Rect(Q, selcolor, Display.solid, sx, sy, sw, sh, dz, Display.invert);
			IF mx<opx THEN
				sw:= opx-mx+dz; sx:=mx
			ELSE
				sw:= mx-opx; sx:= opx;
			END;
			IF my<opy THEN
				sh:= opy-my+dz; sy:= my
			ELSE
				sh:=my-opy; sy:=opy
			END; 
			D3.Rect(Q, selcolor, Display.solid, sx, sy, sw, sh, dz, Display.invert);
			IF info THEN
				ConvertNumberstoText((100*(LONG(sw DIV F.zoom))) DIV (oldsw DIV F.zoom), (100*(LONG(sh DIV F.zoom))) DIV (oldsh DIV F.zoom), disptext);
				DisplayText(cmx, cmy, 100, 16, disptext)
			END;
			Oberon.DrawCursor(Oberon.Mouse,cursor, mx, my);
		END;
		ox:= mx; oy:= my;
		Input.Mouse(keys, mx, my);
		ScreentoPict(F, x, y, mx, my, mx, my); PicttoScreen(F, x, y, mx, my, mx, my);
		keysum := keysum + keys
	UNTIL keys = {};
	Oberon.FadeCursor(Oberon.Mouse); 
	D3.Rect(Q, selcolor, Display.solid, sx, sy, sw, sh, dz, Display.invert);
	IF info THEN Effects.CloseMenu END;
	sw:= sw DIV F.zoom; sh:= sh DIV F.zoom; 
END SizeRect;

(** Handler für rechte Maustaste *)
PROCEDURE TrackSelection*(F: Frame; VAR M: Oberon.InputMsg; x, y, w, h: INTEGER);
VAR Q: D3.Mask; cM: Display.ConsumeMsg; ox, oy, fx, fy, oldsel: INTEGER; P: Pictures.Picture;
		F0: Frame;
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	F.selcolor:= selcolor;
	IF seltype = Freehand THEN TrackFreehandSelection(F, M, x, y)
	ELSIF seltype = Object THEN TrackObjectSelection(F, M, x, y)
	ELSE	(* Block or Image *)
		oldsel:= F.selection;
		RemoveSelection(F); 
		Gadgets.MakeMask(F, x, y, M.dlink, Q);
		fx:= M.X; fy:= M.Y; F.sw:= 0; F.sh:= 0; 
		SizeRect(F, x, y, Q, M.keys, M.X, M.Y, fx, fy, F.sw, F.sh, FALSE);
		IF (M.keys = {MR}) & (F.sw>1) & (F.sh>1) THEN
			ScreentoPict(F, x, y, fx, fy, ox, oy);
			IF ox<0 THEN F.sw:= F.sw+ox; ox:= 0 END;
			IF oy<0 THEN F.sh:= F.sh+oy; oy:= 0 END;
			IF ox+F.sw > F.pict.width THEN F.sw:= F.pict.width-ox END;
			IF oy+F.sh > F.pict.height THEN F.sh:= F.pict.height-oy END;
			F.sx:= ox; F.sy:= oy;
			IF (F.sw= F.pict.width) & (F.sh=F.pict.height) THEN
				SetSelection(F, Image);
			ELSE
				SetSelection(F, Block)
			END
		ELSIF (M.keys = {MR}) & (oldsel=No) THEN	(* Ganzes Picture selektieren falls vorher nichts sel. wurde *)
			F.sx:= 0; F.sy:=0; F.sw:= F.pict.width; F.sh:= F.pict.height;
			SetSelection(F, Image);
		ELSIF (M.keys= {MR, ML}) THEN
			(* Selektion löschen *)
			ScreentoPict(F, x, y, fx, fy, ox, oy); 
			IF ox<0 THEN F.sw:= F.sw+ox; ox:= 0 END;
			IF oy<0 THEN F.sh:= F.sh+oy; oy:= 0 END;
			IF (F.sw<=1) OR (F.sh<=1) THEN F.sw:= F.pict.width; F.sh:= F.pict.height; ox:= 0; oy:= 0 END;
			SavePicture(F.pict, ox, oy, F.sw, F.sh);
			Pictures.ReplConst(F.pict, D3.BG, ox, oy, F.sw, F.sh, Display.replace);
			Pictures.Update(F.pict, ox, oy, F.sw, F.sh);
		ELSIF (M.keys= {MR, MM}) & (F.sw>1) & (F.sh>1) THEN
			(* Copy selected Area to caret position *)
			NEW(P); Rembrandt0.AllocatePictureMem(P, F.sw, F.sh, F.pict.depth);
			CopyPalette(F.pict, P); 	(* tk *)
			ScreentoPict(F, x, y, fx, fy,ox, oy);
			CopyPalette(F.pict, P); Pictures.CopyBlock(F.pict, P, ox, oy, F.sw, F.sh, 0, 0, Display.replace);
			NEW(F0); NewP(F0, P);
			Attributes.SetBool(F0, "Locked", TRUE); Attributes.SetBool(F0, "Border", FALSE);
			cM.obj:= F0; cM.id:= Display.integrate; cM.F:= NIL; Display.Broadcast(cM)  
		END
	END;
	M.res := 0 
END TrackSelection;

PROCEDURE MovePicture(F: Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR ox, oy, ow, oh: INTEGER;
	f: Display.Frame; C: Display.ConsumeMsg; CM: Objects.CopyMsg;
BEGIN
	(* Gadgets.MakeMask(F, x, y, M.dlink, Q); *)
	ow:= F.pict.width*F.zoom; oh:= F.pict.height*F.zoom;
	PicttoScreen(F, x, y, 0, 0, ox, oy); 
	F.sx:= ox; F.sy:= oy;
	Effects.MoveRect(NIL (* Q *), M.keys, M.X, M.Y, ox, oy, ow, oh);
	IF M.keys = {MM} THEN
		F.px:= F.px+(ox-F.sx) DIV F.zoom;
		F.py:= F.py-(oy-F.sy) DIV F.zoom;
		F.car:= FALSE;
		IF F.selection=Image THEN
			F.sx:=0; F.sy:=0; 
			Gadgets.Update(F);
			SetSelection(F, Image);

		ELSE
			Gadgets.Update(F)
		END;
	ELSE
		IF F.selection=Image THEN
			F.sx:=0; F.sy:=0; x := M.x + F.X; y := M.y + F.Y;
			Gadgets.ThisFrame(M.X, M.Y, f, ox, oy);
			IF (f # NIL) & (f # F) THEN
				IF M.keys = {MM, MR} THEN
					CM.id := Objects.deep
				ELSIF M.keys = {ML, MM} THEN
					CM.id := Objects.shallow
				ELSE
					CM.id := -1
				END;
				IF CM.id IN {Objects.deep, Objects.shallow} THEN
					Objects.Stamp(CM); F.handle(F, CM); CM.obj.slink := NIL; (* copy the object *)
					CM.obj(Display.Frame).W := F.pict.width; CM.obj(Display.Frame).H := F.pict.height;
					C.id := Display.drop; C.obj := CM.obj; C.F := f; C.u := ox + (x - M.X); C.v := oy + (y - M.Y);
					Display.Broadcast(C)
				END
			END
		END
	END;
	M.res:=0
END MovePicture;

PROCEDURE MakePictMask(F: Frame; x, y: INTEGER; Q: D3.Mask);
VAR ax, ay, aw, ah : INTEGER;
BEGIN
		IF F.px>0 THEN
			ax:=x+F.px
		ELSE
			ax:= x+1
		END;
		IF y>y+F.H-F.py-F.pict.height THEN
			ay:=y+1
		ELSE
			ay:= y+F.H-F.py-F.pict.height
		END;
		IF F.W>F.px+F.pict.width THEN
			aw:= x+F.pict.width+F.px-ax
		ELSE
			aw:= x+F.W-ax-1
		END;
		IF F.py>0 THEN
			ah:= y+F.H-F.py-ay
		ELSE
			ah:= y+F.H-ay-1
		END;
		IF F.border THEN D3.AdjustMask(Q, ax, ay, aw, ah) ELSE D3.AdjustMask(Q, ax-1, ay-1, aw+2, ah+2) END;
END MakePictMask;

PROCEDURE MoveBlock(F: Frame; x, y: INTEGER; Q: D3.Mask; VAR M: Oberon.InputMsg; P: Pictures.Picture; VAR sx, sy: INTEGER; w, h: INTEGER; interclick: BOOLEAN);
VAR keys: SET; omx, omy, px, py, dx, dy, opx, opy, dw, dh : INTEGER; first: BOOLEAN;
BEGIN
	Oberon.RemoveMarks(x, y, F.W, F.H); RemoveSelection(F);
	IF F.zoom=1 THEN 
		MakePictMask(F, x, y, Q);
		keys:= M.keys; first:= TRUE;
		omx:= M.X; omy:= M.Y;
		dx:= M.X-sx; dy:= M.Y-sy;
		ScreentoPict(F, x, y, omx-dx, omy-dy, opx, opy);
		D3.Pict(Q, P, 0, 0, w, h, M.X-dx, M.Y-dy, Display.replace); 
		REPEAT
			IF interclick & first & (keys = {MM, ML}) THEN
				Oberon.FadeCursor(Oberon.Mouse); first:= FALSE;
				ScreentoPict(F, x, y, omx-dx, omy-dy, opx, opy);
				dw:= M.X-omx; dh:= M.Y-omy;
				IF dw>0 THEN
					D3.Pict(Q, F.pict, opx, opy, dw, h, omx-dx, omy-dy, Display.replace);
					IF dh>0 THEN
						D3.Pict(Q, F.pict, opx+dw, opy, w-dw, dh, omx-dx+dw, omy-dy, Display.replace)
					ELSE
						D3.Pict(Q, F.pict, opx+dw, opy+h+dh, w-dw, -dh, omx-dx+dw, omy-dy+h+dh, Display.replace)
					END
				ELSE
					D3.Pict(Q, F.pict, opx+w+dw, opy, -dw, h, omx+w+dw-dx, omy-dy, Display.replace);
					IF dh>0 THEN
						D3.Pict(Q, F.pict, opx, opy, w-dw, dh, omx-dx, omy-dy, Display.replace);
					ELSE
						D3.Pict(Q, F.pict, opx, opy+h+dh, w+dw, -dh, omx-dx, omy-dy+h+dh, Display.replace)
					END
				END;
				ScreentoPict(F, x, y, M.X-dx, M.Y-dy, opx, opy);
				clipboard.Paste(F.pict, opx, opy);
				MakePictMask(F, x, y, Q);
				EXCL(keys, ML);
				Oberon.DrawCursor(Oberon.Mouse, Effects.FlatHand, M.X, M.Y); 
			ELSIF (omx#M.X) OR (omy#M.Y) THEN
				Oberon.FadeCursor(Oberon.Mouse);  first:= TRUE;
				ScreentoPict(F, x, y, omx-dx, omy-dy, opx, opy);
				dw:= M.X-omx; dh:= M.Y-omy;
				IF dw>0 THEN
					D3.Pict(Q, F.pict, opx, opy, dw, h, omx-dx, omy-dy, Display.replace);
					IF dh>0 THEN
						D3.Pict(Q, F.pict, opx+dw, opy, w-dw, dh, omx-dx+dw, omy-dy, Display.replace)
					ELSE
						D3.Pict(Q, F.pict, opx+dw, opy+h+dh, w-dw, -dh, omx-dx+dw, omy-dy+h+dh, Display.replace)
					END
				ELSE
					D3.Pict(Q, F.pict, opx+w+dw, opy, -dw, h, omx+w+dw-dx, omy-dy, Display.replace);
					IF dh>0 THEN
						D3.Pict(Q, F.pict, opx, opy, w-dw, dh, omx-dx, omy-dy, Display.replace);
					ELSE
						D3.Pict(Q, F.pict, opx, opy+h+dh, w+dw, -dh, omx-dx, omy-dy+h+dh, Display.replace)
					END
				END;
				D3.Pict(Q, P, 0, 0, w, h, M.X-dx, M.Y-dy, Display.replace); 
				Oberon.DrawCursor(Oberon.Mouse, Effects.FlatHand, M.X, M.Y); 
			END;
			omx:= M.X; omy:= M.Y;
			Input.Mouse(keys, M.X, M.Y);
			M.keys := M.keys + keys
		UNTIL keys = {};
		sx:= M.X-dx; sy:= M.Y-dy
	ELSE	(* falls zoom dann nur Gummirechteck verschieben *)
		Gadgets.MakeMask(F, x, y, M.dlink, Q);
		w:= w*F.zoom; h:=h*F.zoom; F.selcolor:= selcolor;
		ScreentoPict(F, x, y, M.X, M.Y, opx, opy); PicttoScreen(F, x, y, opx, opy, M.X, M.Y);
		Oberon.FadeCursor(Oberon.Mouse); first:= TRUE;
		D3.Rect(Q, F.selcolor, Display.solid, sx-F.zoom, sy-F.zoom, w+2*F.zoom, h+2*F.zoom, F.zoom, Display.invert);
		Oberon.DrawCursor(Oberon.Mouse, Effects.FlatHand, M.X, M.Y);
		REPEAT
			ScreentoPict(F, x, y, M.X, M.Y, px, py);
			IF interclick & first & (keys = {MM, ML}) THEN
				Oberon.FadeCursor(Oberon.Mouse); first:= FALSE;
				D3.Rect(Q, F.selcolor, Display.solid, sx-F.zoom, sy-F.zoom, w+2*F.zoom, h+2*F.zoom, F.zoom, Display.invert);
				sx:=sx+(px-opx)*F.zoom; sy:=sy+(py-opy)*F.zoom;
				ScreentoPict(F, x, y, sx, sy, opx, opy);
				clipboard.Paste(F.pict, opx, opy);
				EXCL(keys, ML);
				D3.Rect(Q, F.selcolor, Display.solid, sx-F.zoom, sy-F.zoom, w+2*F.zoom, h+2*F.zoom, F.zoom, Display.invert);
				PicttoScreen(F, x, y, px, py, M.X, M.Y);
				Oberon.DrawCursor(Oberon.Mouse, Effects.FlatHand, M.X, M.Y)
			ELSIF (opx#px) OR (opy#py) THEN
				Oberon.FadeCursor(Oberon.Mouse); first:= TRUE;
				D3.Rect(Q, F.selcolor, Display.solid, sx-F.zoom, sy-F.zoom, w+2*F.zoom, h+2*F.zoom, F.zoom, Display.invert);
				sx:=sx+(px-opx)*F.zoom; sy:=sy+(py-opy)*F.zoom;
				D3.Rect(Q, F.selcolor, Display.solid, sx-F.zoom, sy-F.zoom, w+2*F.zoom, h+2*F.zoom, F.zoom, Display.invert);
				PicttoScreen(F, x, y, px, py, M.X, M.Y);
				Oberon.DrawCursor(Oberon.Mouse, Effects.FlatHand, M.X, M.Y)
			END;
			opx:=px; opy:= py;
			Input.Mouse(keys, M.X, M.Y);
			M.keys := M.keys + keys
		UNTIL keys = {};
		Oberon.FadeCursor(Oberon.Mouse);
		D3.Rect(Q, F.selcolor, Display.solid, sx-F.zoom, sy-F.zoom, w+2*F.zoom, h+2*F.zoom, F.zoom, Display.invert);
		w:= w DIV F.zoom; h:= h DIV F.zoom
	END
END MoveBlock;

PROCEDURE MoveStructure(F: Frame; x, y: INTEGER; VAR M: Oberon.InputMsg; fselcol, typ: INTEGER; fp: Pictures.Picture; struct: Element; first: BOOLEAN; VAR selx, sely, selw, selh: INTEGER; interclick: BOOLEAN);
VAR Q: D3.Mask; keys: SET; sx, sy, xx, yy, ox, oy, opx, opy, oldbw, oldbh: INTEGER; P: Pictures.Picture;

	PROCEDURE DrawUniSel(dx, dy: INTEGER);
	VAR act: Element;
	BEGIN
		act:= struct;
		WHILE act#NIL DO
			Rembrandt0.ReplConst(P, fselcol, dx+act.x, dy+act.y, act.w, 1);
			act:= act.next
		END
	END DrawUniSel;
	
	PROCEDURE DrawPolySel(dx, dy: INTEGER);
	VAR act: Element;
	BEGIN
		act:= struct; 
		WHILE act#NIL DO
			Rembrandt0.CopyBlock(fp, P, opx+act.x, opy+act.y, act.w, 1, dx+act.x, dy+act.y, Display.replace);
			act:= act.next
		END;
	END DrawPolySel;

	PROCEDURE DoubleBuffering(w, h: INTEGER);
	VAR dx, dy, fromx, fromy, bw, bh: INTEGER;
	BEGIN
		IF w>0 THEN
			fromx:= selx; dx:= w; bw:= selw+w
		ELSE
			fromx:=selx+w; dx:= 0; bw:= selw-w
		END;
		IF h>0 THEN
			fromy:= sely; dy:= h; bh:= selh+h
		ELSE
			fromy:= sely+h; dy:= 0; bh:= selh-h
		END;
		(* Copy Block *)
		IF fromx<0 THEN bw:=bw+fromx; dx:=dx+fromx; fromx:=0 END;
		IF fromy<0 THEN bh:= bh+fromy; dy:= dy+fromy; fromy:=0 END;
		IF (bw>0) & (bh>0) THEN
			IF (bw>oldbw) OR (bh>oldbh) THEN
				oldbw:= Max(oldbw, bw); oldbh:= Max(oldbh, bh);
				Rembrandt0.AllocatePictureMem(P, oldbw, oldbh, F.pict.depth);
				CopyPalette(F.pict, P);	(* tk *)
			END;
			IF P#NIL THEN
				Pictures.CopyBlock(F.pict, P, fromx, fromy, bw, bh, 0, 0, Display.replace);
				IF typ=Object THEN DrawUniSel(dx, dy) ELSE DrawPolySel(dx, dy) END;
				PicttoScreen(F, x, y, fromx, fromy, fromx, fromy);
				D3.Pict(Q, P, 0, 0, bw, bh, fromx, fromy, Display.replace)
			END
		END;
		selx:= selx+w; sely:= sely+h
	END DoubleBuffering;

BEGIN
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	RemoveSelection(F);
	PicttoScreen(F, x, y, selx, sely, sx, sy);
	IF interclick THEN opx:=0; opy:= 0 ELSE opx:= selx; opy:= sely END;
	Oberon.FadeCursor(Oberon.Mouse); 
	IF F.zoom=1 THEN
		MakePictMask(F, x, y, Q); 
		NEW(P); oldbw:=0; oldbh:=0;
		IF first THEN ox:= M.X; oy:= M.Y ELSE ox:=sx; oy:= sy END; first:= TRUE;
		keys:= M.keys;
		REPEAT
			IF interclick & first & (keys = {MM, ML}) THEN
				DoubleBuffering(M.X-ox, M.Y-oy);
				ScreentoPict(F, x, y, M.X, M.Y, ox, oy); first:= FALSE;
				clipboard.Paste(F.pict, ox, oy);
				MakePictMask(F, x, y, Q);
				EXCL(keys, ML);
			ELSIF (ox#M.X) OR (oy#M.Y) THEN
				DoubleBuffering(M.X-ox, M.Y-oy); first:= TRUE;
			END;
			ox:= M.X; oy:= M.Y;
			Input.Mouse(keys, M.X, M.Y);
			M.keys := M.keys + keys
		UNTIL keys = {};
	ELSE
		ScreentoPict(F, x, y, M.X, M.Y, M.X, M.Y); PicttoScreen(F, x, y, M.X, M.Y, M.X, M.Y);
		ox:=M.X; oy:= M.Y; xx:= ox; yy:= oy; first:= TRUE;
		DrawOutline(F, Q, sx+M.X-xx, sy+M.Y-yy);
		keys:= M.keys;
		REPEAT
			ScreentoPict(F, x, y, M.X, M.Y, M.X, M.Y); PicttoScreen(F, x, y, M.X, M.Y, M.X, M.Y);
			IF interclick & first & (keys = {MM, ML}) THEN
				Oberon.FadeCursor(Oberon.Mouse); first:= FALSE;
				DrawOutline(F, Q, sx+ox-xx, sy+oy-yy);
				ScreentoPict(F, x, y, sx+ox-xx, sy+oy-yy, ox, oy);
				clipboard.Paste(F.pict, ox, oy);	
				DrawOutline(F, Q, sx+M.X-xx, sy+M.Y-yy);
				EXCL(keys, ML);
				Oberon.DrawCursor(Oberon.Mouse, Effects.FlatHand, M.X, M.Y)
			ELSIF (ox#M.X) OR (oy#M.Y) THEN
				Oberon.FadeCursor(Oberon.Mouse); first:= TRUE;
				DrawOutline(F, Q, sx+ox-xx, sy+oy-yy);
				DrawOutline(F, Q, sx+M.X-xx, sy+M.Y-yy);
				Oberon.DrawCursor(Oberon.Mouse, Effects.FlatHand, M.X, M.Y)
			END;
			ox:= M.X; oy:= M.Y;
			Input.Mouse(keys, M.X, M.Y);
			M.keys := M.keys + keys
		UNTIL keys = {};
		selx:= selx+(ox-xx) DIV F.zoom; sely:= sely+(oy-yy) DIV F.zoom;
	END
END MoveStructure;

PROCEDURE HandleStructure(F: Frame; x, y: INTEGER; VAR M: Oberon.InputMsg; f: Frame; struct: Element; same: BOOLEAN; selx, sely, selw, selh: INTEGER);
VAR typ: INTEGER; act: Element; P: Pictures.Picture; opx, opy: INTEGER;

	PROCEDURE DrawPolySel;
	VAR act: Element;
	BEGIN
		act:= struct; 
		WHILE act#NIL DO
			Rembrandt0.CopyBlock(f.pict, P, opx+act.x, opy+act.y, act.w, 1, act.x, act.y, Display.replace);
			act:= act.next
		END;
	END DrawPolySel;

BEGIN
	typ:= f.selection;
	opx:= selx; opy:= sely; 
	MoveStructure(F, x, y, M, f.selcol, f.selection, f.pict, struct, same, selx, sely, selw, selh, FALSE);
	Oberon.FadeCursor(Oberon.Mouse); 
	IF M.keys= {MM} THEN
		SavePicture(F.pict, 0, 0, F.pict.width, F.pict.height);
		IF typ=Freehand THEN
			NEW(P);
			Rembrandt0.AllocatePictureMem(P, selw, selh, F.pict.depth);
			CopyPalette(F.pict, P);	(* tk *)
			DrawPolySel; 
			act:= struct; 
			WHILE act#NIL DO
				Rembrandt0.ReplConst(F.pict, D3.BG, opx+act.x, opy+act.y, act.w, 1);
				act:= act.next
			END;
			act:= struct;
			WHILE act#NIL DO
				Rembrandt0.CopyBlock(P, F.pict, act.x, act.y, act.w, 1, selx+act.x, sely+act.y, Display.replace);
				act:= act.next
			END;	
		ELSE
			act:= struct;
			WHILE act#NIL DO
				Pictures.ReplConst(F.pict, D3.BG, opx+act.x, opy+act.y, act.w, 1, Display.replace);
				act:= act.next
			END;
			act:= struct; 
			WHILE act#NIL DO
				Rembrandt0.ReplConst(F.pict, f.selcol, selx+act.x, sely+act.y, act.w, 1);
				act:= act.next
			END
		END;
		Pictures.Update(F.pict, opx, opy, selw, selh)
	ELSIF M.keys= {ML, MM} THEN
		SavePicture(F.pict, 0, 0, F.pict.width, F.pict.height);
		IF typ=Freehand THEN
			 NEW(P);
			Rembrandt0.AllocatePictureMem(P, selw, selh, F.pict.depth);
			CopyPalette(F.pict, P);
			DrawPolySel;
			act:= struct; 
			WHILE act#NIL DO
				Rembrandt0.CopyBlock(P, F.pict, act.x, act.y, act.w, 1, selx+act.x, sely+act.y, Display.replace);
				act:= act.next
			END;
		ELSE
			act:= struct; 
			WHILE act#NIL DO
				Rembrandt0.ReplConst(F.pict, f.selcol, selx+act.x, sely+act.y, act.w, 1);
				act:= act.next
			END
		END
	END;
	Pictures.Update(F.pict, selx, sely, selw, selh);
END HandleStructure;

PROCEDURE HandleMove(F: Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
(* Verschiebt selektierter Teil *)
VAR Q: D3.Mask; px, py, ux, uy, uw, uh, ox, oy: INTEGER;
		P: Pictures.Picture;
BEGIN
	IF F.selection=Image THEN
		MovePicture(F, M, x, y)
	ELSIF F.selection=Block THEN
		PicttoScreen(F, x, y, F.sx, F.sy, ox, oy);
		Gadgets.MakeMask(F, x, y, M.dlink, Q);
		RemoveSelection(F);
		NEW(P); Rembrandt0.AllocatePictureMem(P, F.sw, F.sh, F.pict.depth);
		CopyPalette(F.pict, P);	(* tk *)
		Pictures.CopyBlock(F.pict, P, F.sx, F.sy, F.sw, F.sh, 0, 0, Display.replace);
		MoveBlock(F, x, y, Q, M, P, ox, oy, F.sw, F.sh, FALSE);
		IF M.keys={MM} THEN
			(* Block verschieben *)
			ScreentoPict(F, x, y, ox, oy, px, py);
			IF F.sx<px THEN
				ux:=F.sx; uw:= px+F.sw-ux
			ELSE
				ux:= px; uw:= F.sx+F.sw-ux
			END;
			IF F.sy<py THEN
				uy:= F.sy; uh:= py+F.sh-uy
			ELSE
				uy:= py; uh:= F.sy+F.sh-uy
			 END;
			SavePicture(F.pict, ux, uy, uw, uh);
			Pictures.ReplConst(F.pict, D3.BG, F.sx, F.sy, F.sw, F.sh, Display.replace);	
			Rembrandt0.CopyBlock(P, F.pict, 0, 0, F.sw, F.sh, px, py, Display.replace);
			Pictures.Update(F.pict, F.sx, F.sy, F.sw, F.sh);
			Pictures.Update(F.pict, px, py, F.sw, F.sh)
		ELSIF M.keys={MM, ML} THEN
			(* Block kopieren *)
			ScreentoPict(F, x, y, ox, oy, px, py);
			SavePicture(F.pict, px, py, F.sw, F.sh);
			Rembrandt0.CopyBlock(P, F.pict, 0, 0, F.sw, F.sh, px, py, Display.replace);
			Pictures.Update(F.pict, px, py, F.sw, F.sh)
		ELSE
			Pictures.Update(F.pict, 0, 0, F.pict.width, F.pict.height)
		END
	ELSIF F.selection >= Object THEN
		HandleStructure(F, x, y, M, F, F.selstruct, TRUE, F.sx, F.sy, F.sw, F.sh) 
	END;
	M.res:=0
END HandleMove;

PROCEDURE HandleStamp(F: Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR px, py, mx, my, w, h: INTEGER; Q: D3.Mask;
BEGIN
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	SavePicture(F.pict, 0, 0, F.pict.width, F.pict.height);
	ScreentoPict(F, x, y, M.X, M.Y, mx, my); PicttoScreen(F, x, y, mx, my, mx, my);
	w:= (clipboard.sw DIV 2)*F.zoom; h:= (clipboard.sh DIV 2)*F.zoom;
	px:= mx-w; py:= my-h;
	IF clipboard.id=Block THEN
		MoveBlock(F, x, y, Q, M, clipboard.P, px, py, clipboard.sw, clipboard.sh, TRUE);
	ELSE
		ScreentoPict(F, x, y, px, py, px, py);
		MoveStructure(F, x, y, M,  clipboard.col,  clipboard.id, clipboard.P, clipboard.selstruct, FALSE, px, py, clipboard.sw, clipboard.sh, TRUE);
	END;
	Pictures.Update(F.pict, 0, 0, F.pict.width, F.pict.height);
	M.keys:= {}; M.res:=0
END HandleStamp;

PROCEDURE TrackCaret(F: Frame; VAR M: Oberon.InputMsg; x, y: INTEGER);
VAR f: Frame; p: Pictures.Picture; sx, sy, sw, sh, dx, dy: INTEGER; time, time2: LONGINT;
		text: Texts.Text; beg, end: LONGINT; keys: SET;Q: D3.Mask; mx, my: INTEGER; 
BEGIN
	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	keys := M.keys; 
	ScreentoPict(F, x, y, M.X, M.Y, M.X, M.Y); PicttoScreen(F, x, y, M.X, M.Y, M.X, M.Y);
	mx:= M.X; my:= M.Y;
	DrawCaret(Q, mx, my);
	REPEAT
		IF (mx#M.X) OR (my#M.Y) THEN
			DrawCaret(Q, mx, my);
			DrawCaret(Q, M.X, M.Y)
		END;
		(* Oberon.DrawCursor(Oberon.Mouse, cursor, M.X, M.Y); *)
		mx:= M.X; my:= M.Y;
		Input.Mouse(keys, M.X, M.Y);
		ScreentoPict(F, x, y, M.X, M.Y, M.X, M.Y); PicttoScreen(F, x, y, M.X, M.Y, M.X, M.Y);
		M.keys := M.keys + keys
	UNTIL (keys = {}) OR (keys = {ML, MM});
	DrawCaret(Q, mx, my);
	IF M.keys = {ML} THEN
		ScreentoPict(F, x, y, M.X, M.Y, sx, sy); 
		IF Effects.Inside(sx, sy, 0, 0, F.pict.width, F.pict.height) THEN SetCaret(F, sx, sy) END;
	ELSIF M.keys = {ML, MM} THEN
		GetSelection(f, p, time, sx, sy, sw, sh);
		Oberon.GetSelection(text, beg, end, time2);
		IF (time>time2) & (time>0) THEN
			IF (f#NIL) & (f.selection>=Object) THEN
				ScreentoPict(F, x, y, M.X, M.Y, mx, my);
				HandleStructure(F, x, y, M, f, f.selstruct, FALSE,  f.sx, f.sy, sw, sh);
				ScreentoPict(F, x, y, M.X, M.Y, sx, sy);
				IF sx<0 THEN sx:=0 END; IF sy<0 THEN sy:=0 END;
				Pictures.Update(F.pict, sx, sy, sw, sh)
			ELSE
				ScreentoPict(F, x, y, M.X, M.Y, mx, my); PicttoScreen(F, x, y, mx, my, mx, my);
				MoveBlock(F, x, y, Q, M, p, mx, my, sw, sh, FALSE);
				ScreentoPict(F, x, y, mx, my, sx, sy);
				IF M.keys # Cancel THEN
					 M.X:= mx; M.Y:= my;
					IF sx<0 THEN sw:= sw+sx; dx:=0; sx:= -sx ELSE dx:= sx; sx:=0 END;
					IF sy<0 THEN sh:= sh+sy; dy:= 0; sy:= -sy ELSE dy:= sy; sy:= 0 END;
					SavePicture(F.pict, dx, dy, sw, sh);
					Rembrandt0.CopyBlock(p, F.pict, sx, sy, sw, sh, dx, dy, Display.replace);
					Pictures.Update(F.pict, dx, dy, sw, sh)
				ELSE Pictures.Update(F.pict, sx, sy, sw, sh)
				END
			END;
		ELSIF time2>0 THEN
			keys := M.keys; mx:= M.X; my:= M.Y;
			DrawCaret(Q, mx, my);
			REPEAT
				IF (mx#M.X) OR (my#M.Y) THEN
					DrawCaret(Q, mx, my);
					DrawCaret(Q, M.X, M.Y)
				END;
				mx:= M.X; my:= M.Y;
				Input.Mouse(keys, M.X, M.Y);
				M.keys := M.keys + keys
			UNTIL keys = {};
			DrawCaret(Q, mx, my);
			ScreentoPict(F, x, y, M.X, M.Y, sx, sy);
			IF Effects.Inside(sx, sy, 0, 0, F.pict.width, F.pict.height) THEN
				SetCaret(F, sx, sy);
				CopyText(F, text, beg, end, x, y)
			END
		END
	END;
END TrackCaret;

PROCEDURE TrackEffects(F: Frame; VAR M: Oberon.InputMsg; x, y, w, h: INTEGER);
VAR keys: SET;
BEGIN
	IF trackMM#NIL THEN
		trackMM(F, M, x, y)
	ELSE
		keys := M.keys;
		REPEAT
			Oberon.DrawCursor(Oberon.Mouse, cursor, M.X, M.Y);
			Input.Mouse(keys, M.X, M.Y);
			M.keys := M.keys + keys
		UNTIL keys = {};
		M.keys:= keys; M.res:=0
	END
END TrackEffects;

PROCEDURE Edit (F: Frame; VAR M: Oberon.InputMsg; x, y, w, h: INTEGER);
BEGIN
	IF M.keys = {MR} THEN
		IF ~Effects.InBorder(M.X, M.Y, x, y, w, h) THEN selcolor:= D3.FG; TrackSelection(F, M, x, y, w, h)
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF (M.keys = {MM}) & ~InsidePict(F, M.X, M.Y, x, y) THEN
		MovePicture(F, M, x, y); M.res:=0
	ELSIF (M.keys = {MM}) & (F.selection#No) THEN
		Defocus(F); trackSelMM.track(F, M, x, y); M.res:=0
	ELSIF (M.keys = {ML}) & InsidePict(F, M.X, M.Y, x, y) THEN
		TrackCaret(F, M, x, y); M.res:=0
	ELSIF (M.keys = {MM}) THEN
		TrackEffects(F, M, x, y, w, h); M.res:=0
	ELSIF (trackSelMM.id=idMove) & (F.selection=Image) THEN
		Oberon.DrawCursor(Oberon.Mouse, Effects.FlatHand, M.X, M.Y); M.res:=0
	ELSE
		Oberon.DrawCursor(Oberon.Mouse, cursor, M.X, M.Y); M.res:=0
	END
END Edit;

PROCEDURE Zoom(F: Frame; Q: D3.Mask; x, y, w, h, factor: INTEGER);
BEGIN
	IF (F.selection#No) & (F.selection#Image) THEN
		Neutralize(F, x, y, w, h);
		F.px:= -F.sx; F.py:= -F.pict.height+F.sh+F.sy; 
	ELSE
		Neutralize(F, x, y, w, h);
		IF F.px>0 THEN F.px:=0 END;
		IF F.py>0 THEN F.py:=0 END; 
	END;
	F.zoom:= factor;
	Restore(F, Q, x, y, w, h, 0, 0, F.pict.width, F.pict.height)
END Zoom;

(** Zoomfaktor abfragen bzw. setzen *)
PROCEDURE GetZoom*(F: Frame; VAR factor: INTEGER);
BEGIN
	factor:= F.zoom
END GetZoom;

PROCEDURE SetZoom*(F: Frame; factor: INTEGER);
VAR zM: ZoomMsg;
BEGIN
	zM.F:= F; zM.zoom:= factor; Display.Broadcast(zM)
END SetZoom; 

(** Gitterlinien abfragen bzw. setzen *)
PROCEDURE GetGrid*(F: Frame; VAR set: BOOLEAN);
BEGIN
	set:= F.grid
END GetGrid;

PROCEDURE SetGrid*(F: Frame; set: BOOLEAN);
VAR M: DrawGridMsg;
BEGIN
	F.grid:= set;
	M.F:= F; M.res:= -1; M.u:= 0; M.v:= 0; M.w:= F.pict.width; M.h:= F.pict.height; Display.Broadcast(M);
END SetGrid;

(** Attribut locked abfragen bzw. setzen *)
PROCEDURE GetLocked*(F: Frame; VAR locked: BOOLEAN);
BEGIN
	locked:= F.locked
END GetLocked;

PROCEDURE SetLocked*(F: Frame; locked: BOOLEAN);
VAR M: Objects.AttrMsg;
BEGIN
	M.id:= Objects.set; M.class:= Objects.Bool; COPY("Locked", M.name); M.b:= locked; M.res:= -1; 
	F.handle(F, M);
END SetLocked;

(** Attribut border abfragen bzw. setzen *)
PROCEDURE GetBorder*(F: Frame; VAR border: BOOLEAN);
BEGIN
	border:= F.border
END GetBorder;

PROCEDURE SetBorder*(F: Frame; border: BOOLEAN);
VAR M: Objects.AttrMsg;
BEGIN
	M.id:= Objects.set; M.class:= Objects.Bool; COPY("Border", M.name); M.b:= border; M.res:= -1; 
	F.handle(F, M);
END SetBorder;

(** Selektionsoperation verschieben aktivieren *)
PROCEDURE Move*;
BEGIN
	trackSelMM.id:= idMove;
	trackSelMM.track:= HandleMove;
	cursor:= Effects.Cross 
END Move;

(** Operation Stamp für Clipboard *)
PROCEDURE ClipboardStamp*;
BEGIN
	trackMM:= HandleStamp;
	cursor:= Effects.Cross;
END ClipboardStamp;

PROCEDURE ClipboardDraw(D: Pictures.Picture; dx, dy: INTEGER);
VAR act: Element;
BEGIN
	IF clipboard.id= Block THEN
		Rembrandt0.CopyBlock(clipboard.P, D, 0, 0, clipboard.sw, clipboard.sh, dx, dy, Display.replace);
		Pictures.Update(D, dx, dy, clipboard.sw, clipboard.sh)
	ELSIF clipboard.id= Object THEN
		act:= clipboard.selstruct;
		WHILE act#NIL DO
			Rembrandt0.ReplConst(D, clipboard.col, dx+act.x, dy+act.y, act.w, 1);
			act:= act.next
		END;
		Pictures.Update(D, dx, dy, clipboard.sw, clipboard.sh)
	ELSIF clipboard.id= Freehand THEN
		act:= clipboard.selstruct;
		WHILE act#NIL DO
			Rembrandt0.CopyBlock(clipboard.P, D, act.x, act.y, act.w, 1, dx+act.x, dy+act.y, Display.replace);
			act:= act.next
		END;
		Pictures.Update(D, dx, dy, clipboard.sw, clipboard.sh)
	END;
END ClipboardDraw;

PROCEDURE CutCopy(clear: BOOLEAN);
VAR P, D: Pictures.Picture; F: Frame; px, py, pw, ph: INTEGER; time: LONGINT; act: Element;
BEGIN
	P:= NIL; F:= NIL;
	GetSelection(F, P, time, px, py, pw, ph);
	IF (F#NIL) & (P#NIL) & (F.selection=Object) THEN
		NEW(P); Rembrandt0.AllocatePictureMem(P, pw, ph, F.pict.depth);	(* tk *)
		CopyPalette(F.pict, P);
		act:= F.selstruct;
		WHILE act#NIL DO
			Pictures.ReplConst(P, F.selcol, act.x, act.y, act.w, 1, Display.replace); 
			act:= act.next
		END;
		clipboard.P:= P;
		clipboard.id:= Object;
		clipboard.col:= F.selcol;
		clipboard.selstruct:= F.selstruct;
		clipboard.sw:= pw;
		clipboard.sh:= ph;
		IF clear THEN
			SavePicture(F.pict, px, py, pw, ph);
			act:= F.selstruct;
			WHILE act#NIL DO
				Pictures.ReplConst(F.pict, D3.BG, px+act.x, py+act.y, act.w, 1, Display.replace); 
				act:= act.next
			END;
			Pictures.Update(F.pict, px, py, pw, ph)
		END
	ELSIF (F#NIL) & (P#NIL) & (F.selection=Freehand) THEN
		NEW(P); Rembrandt0.AllocatePictureMem(P, pw, ph, F.pict.depth);	(* tk *)
		CopyPalette(F.pict, P);
		act:= F.selstruct;
		WHILE act#NIL DO
			Rembrandt0.CopyBlock(F.pict, P, px+act.x, py+act.y, act.w, 1, act.x, act.y, Display.replace);
			act:= act.next
		END;
		clipboard.id:= Freehand;
		clipboard.P:= P;
		clipboard.selstruct:= F.selstruct;
		clipboard.sw:= pw;
		clipboard.sh:= ph;
		IF clear THEN
			SavePicture(F.pict, px, py, pw, ph);
			act:= F.selstruct;
			WHILE act#NIL DO
				Pictures.ReplConst(F.pict, D3.BG, px+act.x, py+act.y, act.w, 1, Display.replace); 
				act:= act.next
			END;
			Pictures.Update(F.pict, px, py, pw, ph)
		END
	ELSIF P#NIL THEN	(* Block *)
		NEW(D); Rembrandt0.AllocatePictureMem(D, pw, ph, P.depth);	(* tk *)
		CopyPalette(P, D);
		Pictures.CopyBlock(P, D, px, py, pw, ph, 0, 0, Display.replace);
		clipboard.id:= Block;
		clipboard.selstruct:=NIL;
		clipboard.P:= D;
		clipboard.sw:= pw;
		clipboard.sh:= ph;
		IF clear THEN
			SavePicture(F.pict, F.sx, F.sy, pw, ph);
			Pictures.ReplConst(F.pict, D3.BG, F.sx, F.sy, pw, ph, Display.replace);
			Pictures.Update(F.pict, F.sx, F.sy, pw, ph)
		END
	END;
	IF F#NIL THEN RemoveSelection(F) END
END CutCopy;

(** Clipboardfunktionen *)
PROCEDURE ClipboardCopy*;
BEGIN
	CutCopy(FALSE)
END ClipboardCopy;

PROCEDURE ClipboardCut*;
BEGIN
	CutCopy(TRUE)
END ClipboardCut;

PROCEDURE ClipboardPaste*;
VAR F: Frame; M: FocusMsg;
BEGIN
	M.F:= NIL; M.res:=-1; Display.Broadcast(M);
	IF (M.F#NIL) & (M.F IS Frame) THEN
		F:= M.F(Frame);
		clipboard.Paste(F.pict, F.cx, F.cy);
	END
END ClipboardPaste;

(** Selektionsarten aktivieren *)
PROCEDURE BlockSelect*;
BEGIN
	seltype:= Block;
	cursor:= Effects.Cross
END BlockSelect;

PROCEDURE ObjectSelect*;
BEGIN
	seltype:= Object;
	cursor:= Effects.Cross
END ObjectSelect;

PROCEDURE FreehandSelect*;
BEGIN
	seltype:= Freehand;
	cursor:= Effects.Cross
END FreehandSelect;

(** Generiert Pattern-Code aus der letzten Block-Selektion; sollte nicht grösser als 32*32 sein *)
PROCEDURE MakePattern*;
VAR F: Frame; P: Pictures.Picture; sx, sy, sw, sh, x0, x1, y: INTEGER;
		time: LONGINT; first: BOOLEAN;
BEGIN
	GetSelection(F, P, time, sx, sy, sw, sh);
	IF time>0 THEN
		IF (sw>=32) OR (sh>=32) THEN Out.String("Patternsize too big"); Out.Ln
		ELSE
			y:=0;
			Out.String("VAR pattern: ARRAY "); Out.Int(P.height, 2); Out.String(" OF SET;"); Out.Ln; 
			Out.String("       pat: LONGINT;");Out.Ln;
			WHILE y<P.height DO
				x0:=0; Out.String("pattern["); Out.Int(y, 2); Out.String("]:={"); first:= TRUE;
				WHILE x0<P.width DO
					x1:=x0;
					WHILE (Pictures.Get(P, x0, y)#D3.BG) & (x0<P.width) DO INC(x0) END;
					IF x0-x1 > 1 THEN
						IF first THEN first:= FALSE ELSE Out.String(", ") END;
						Out.Int(x1,0); Out.String(".."); Out.Int(x0-1, 0)
					ELSIF x0-x1=1 THEN
						IF first THEN first:= FALSE ELSE Out.String(", ") END;
						Out.Int(x1,0)
					END;
					INC(x0)
				END;
				Out.String("};"); Out.Ln;
				INC(y)
			END;
			Out.String("pat:= Display.NewPattern("); Out.Int(x0, 2); Out.Char(","); Out.Int(y, 2); Out.String(", pattern);"); Out.Ln;
		END
	END
END MakePattern;

(** Haupthandler *)
PROCEDURE Handle* (F: Objects.Object; VAR M: Objects.ObjMsg);
  VAR x, y, w, h, ox, oy: INTEGER; F1: Frame; Q: D3.Mask;
BEGIN
  WITH F: Frame DO
    IF M IS Display.FrameMsg THEN
      WITH M: Display.FrameMsg DO
        IF (M.F = NIL) OR (M.F = F) THEN (* message addressed to box *)
          x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
          IF M IS  Display.DisplayMsg THEN
            WITH M: Display.DisplayMsg  DO
				IF M IS ZoomMsg THEN
                	Gadgets.MakeMask(F, x, y, M.dlink, Q);
					Zoom(F, Q, x, y, w, h, M(ZoomMsg).zoom)
				ELSIF M.device = Display.screen THEN
					IF (M.id = Display.full) OR (M.F = NIL) THEN
						Neutralize(F, x, y, w, h);
	                	Gadgets.MakeMask(F, x, y, M.dlink, Q);
	                	Restore(F, Q, x, y, w, h, 0, 0, F.pict.width, F.pict.height); 
					ELSIF M.id = Display.area THEN
						Neutralize(F, x, y, w, h); 
						Gadgets.MakeMask(F, x, y, M.dlink, Q);
	                	D3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
	                	Restore(F, Q, x, y, w, h, 0, 0, F.pict.width, F.pict.height)
					END
				ELSIF M.device = Display.printer THEN Print(F, M)
				END
            END
		  ELSIF M IS DrawCaretMsg THEN
             Gadgets.MakeMask(F, x, y, M.dlink, Q);
		 	PicttoScreen(F, x, y, F.cx, F.cy, ox, oy);
		 	DrawCaret(Q, ox, oy);
		  ELSIF M IS DrawSelectionMsg THEN
                Gadgets.MakeMask(F, x, y, M.dlink, Q); 
				DrawSelection(F, Q, x, y); 
		  ELSIF (M IS DrawGridMsg) & (M.F=F) THEN
			WITH M: DrawGridMsg DO
				Neutralize(F, x, y, w, h);
				Gadgets.MakeMask(F, x, y, M.dlink, Q);
				DrawGrid(F, Q, x, y, w, h, M.u, M.v, M.w, M.h)
			END
		  ELSIF M IS Pictures.UpdateMsg THEN
			WITH M: Pictures.UpdateMsg DO
				IF M.pict=F.pict THEN
					IF M.id= Pictures.redraw THEN
						Neutralize(F, x, y, w, h);
						 Gadgets.MakeMask(F, x, y, M.dlink, Q);
						RestorePict(F, Q, x, y, w, h, M.u, M.v, M.w, M.h);
					ELSIF M.id= Pictures.resize THEN
						Gadgets.MakeMask(F, x, y, M.dlink, Q);
						Restore(F, Q, x, y, w, h, 0, 0, F.pict.width, F.pict.height)
					ELSE Gadgets.framehandle(F, M)
					END
				ELSE Gadgets.framehandle(F, M)
				END
			END
          ELSIF M IS Oberon.InputMsg THEN
            WITH M: Oberon.InputMsg DO
   	         IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) & ~F.locked THEN Edit(F, M, x, y, w ,h)
				ELSIF (M.id=Oberon.consume) & (F.car) & ~F.locked THEN Write(F, M, x, y); M.res:=0
				ELSE Gadgets.framehandle(F, M)
              END
            END
          ELSIF M IS Display.ModifyMsg THEN Gadgets.framehandle(F, M)
		  ELSIF M IS FocusMsg THEN
			IF F.car THEN M(FocusMsg).F := F; M(FocusMsg).u:=x; M(FocusMsg).v:=y; M.res:=0 END
          ELSIF M IS Oberon.ControlMsg THEN
				WITH M : Oberon.ControlMsg DO
					IF M.id= Oberon.defocus THEN Defocus(F)
					ELSIF M.id=Oberon.neutralize THEN Neutralize(F, x, y, w, h)
					ELSE Gadgets.framehandle(F, M)
					END
				END
			ELSIF M IS Oberon.ConsumeMsg THEN
				IF F.car THEN
					WITH M: Oberon.ConsumeMsg DO
						CopyText(F, M.text, M.beg, M.end, x, y)
					END
				END
			 ELSIF M IS Display.SelectMsg THEN Select(F, x, y, M(Display.SelectMsg))
			 ELSIF M IS Display.ConsumeMsg THEN
				WITH M: Display.ConsumeMsg DO
					IF M.id = Display.integrate THEN
						IF M.obj IS Pictures.Picture THEN CopyOver(F, M.obj(Pictures.Picture), x, y)
						ELSIF M.obj IS Frame THEN CopyOver(F, M.obj(Frame).pict, x, y)
						END
					END
				END
			ELSE Gadgets.framehandle(F, M)
			END
        END
      END
    ELSIF M IS Objects.AttrMsg THEN FrameAttributes(F, M(Objects.AttrMsg))
    ELSIF M IS Objects.BindMsg THEN F.pict.handle(F.pict, M); Gadgets.framehandle(F, M)
    ELSIF M IS Objects.LinkMsg THEN FrameLinks(F, M(Objects.LinkMsg))
    ELSIF M IS Objects.FileMsg THEN
      WITH M: Objects.FileMsg DO
        IF M.id = Objects.store THEN StoreFrame(F, M)
        ELSIF M.id = Objects.load THEN LoadFrame(F, M)
        END
      END
    ELSIF M IS Objects.CopyMsg THEN
      WITH M: Objects.CopyMsg DO
        IF M.stamp = F.stamp THEN M.obj := F.dlink
        ELSE NEW(F1); F.stamp := M.stamp; F.dlink := F1; Copy(M, F, F1); M.obj := F1
        END
      END
    ELSE Gadgets.framehandle(F, M)
    END
  END
END Handle;

(** Erstellt ein neues Gadget *)
PROCEDURE New*;
VAR F: Frame;
		P: Pictures.Picture;
BEGIN
	NEW(F);
	F.col := 14; F.px:=1; F.py:= 1; 
	F.handle := Handle;
	F.zoom:=1; 
	NEW(P);
	Pictures.Create(P, 20, 20, 8);
	F.pict:= P;
	F.car:= FALSE; F.border:= TRUE; 
	F.selection:= No;
	F.grid:= FALSE; F.locked:= FALSE; F.lockdata.scaledpict:= NIL; F.selcolor:= D3.FG;
	F.W:= F.pict.width; F.H:= F.pict.height; 
	Objects.NewObj := F; 
END New;

(** Fügt ein als Parameter angegebenes Picture als Rembrandt-Frame in ein Panel ein *)
PROCEDURE Insert*;
VAR F: Frame;
		P: Pictures.Picture;
		S: Attributes.Scanner;
		name: ARRAY 64 OF CHAR;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF S.class = Attributes.Name THEN COPY(S.s, name) ELSE COPY("Default.Pict", name) END;
	NEW(F);
	F.col := 14; F.px:=0; F.py:= 0;
	F.handle := Handle;
	F.zoom:=1; 
	NEW(P);
	Pictures.Open(P, name, TRUE);
	F.pict:= P;
	F.car:= FALSE; F.border:= FALSE;
	F.selection:= No;
	F.grid:= FALSE;  F.selcolor:= D3.FG;
	F.W:= F.pict.width; F.H:= F.pict.height;
	F.lockdata.scaledpict:= NIL; SetLocked(F, TRUE);
	Gadgets.Integrate(F); 
END Insert;

(** Erstellt ein neues Gadgets mit dem Picture pict *)
PROCEDURE NewP*(F: Frame;pict: Pictures.Picture);
BEGIN
	F.col := 14; F.px:=1; F.py:= 1;
	F.handle := Handle;
	F.zoom:= 1;
	IF pict=NIL THEN Rembrandt0.AllocatePictureMem(pict, 320, 200, 8) END;
	F.pict:= pict;  
	F.car:= FALSE; F.border:= TRUE;
	F.selection:= No;
	F.grid:= FALSE; F.locked:= FALSE; F.lockdata.scaledpict:= NIL;
	F.selcolor:= D3.FG;
	F.W:= F.pict.width; F.H:= F.pict.height; 
END NewP;

BEGIN
	cursor:= Effects.Cross; undo:= NIL;  selcolor:= D3.FG; trackMM:= NIL;
	trackSelMM.track:= HandleMove; trackSelMM.id:= idMove; clipboard.id:= No; clipboard.Paste:= ClipboardDraw;
	seldir[0].dx:= 0; seldir[0].dy:= 1; seldir[0].ind:= 3;
	seldir[1].dx:= -1; seldir[1].dy:= 0; seldir[1].ind:= 0;
	seldir[2].dx:= 0; seldir[2].dy:= -1; seldir[2].ind:= 1;
	seldir[3].dx:= 1; seldir[3].dy:= 0; seldir[3].ind:= 2;
	(*
	Out.String("Rembrandt, DP 10.3.95"); Out.Ln
	*)
END Rembrandt.

System.Free Rembrandt ~

Gadgets.Insert Rembrandt.NewColFrame Rembrandt.NewColorObj~
Gadgets.Insert Rembrandt.New~

Rembrandt.Insert Clown.Pict
