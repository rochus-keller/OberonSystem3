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

MODULE WTSDraw;	(** portable *)

	IMPORT Texts, WTS, Panels, BasicFigures, TextFields, Display, Objects, Files, Fonts;

(*
	file = tag stretch.
	stretch = {item} -1.
	item =
		0 0 fontno fontname |
		0 1 libno libname |
		0 2 classno classname allocname |
		1 data |
		2 data fontno string |
		3 data libno macname |
		classno data extension.
	data = x y w h color.
	
	rect = len lwx versx	x=short vers=shade
	curve = len kind lw	2=circle	3=ellipse	0,1=diagline(up/dn)
*)
	VAR
		W: Texts.Writer;
		fontname: ARRAY 8, 32 OF CHAR;
		libname: ARRAY 8, 32 OF CHAR;
		elem: ARRAY 8 OF PROCEDURE (VAR R: Files.Rider; col, x, y, w, h: INTEGER): Display.Frame;

	PROCEDURE Data(VAR R: Files.Rider; VAR x, y, w, h, color: INTEGER);
	BEGIN Files.ReadInt(R, x); Files.ReadInt(R, y);
		Files.ReadInt(R, w); Files.ReadInt(R, h); Files.ReadInt(R, color)
	END Data;

	PROCEDURE ReadString(VAR R: Files.Rider; VAR s: ARRAY  OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN i := 0;
		REPEAT Files.Read(R, ch); s[i] := ch; INC(i) UNTIL (i = LEN(s)) OR (ch < 0DX); s[i-1] := 0X
	END ReadString;

	PROCEDURE RLine(col, x, y, w, h: INTEGER): Display.Frame;
		VAR X, Y: ARRAY 2 OF INTEGER; lw: INTEGER; L: BasicFigures.Figure;
	BEGIN X[0] := 0; Y[0] := 0;
		IF w > h THEN X[1] := w; Y[1] := 0; lw := h ELSE X[1] := 0; Y[1] := h; lw := w END;
		NEW(L); BasicFigures.InitLine(L, X[0], Y[0], X[1], Y[1]);
		(*
		L := Figures.NewPolyLine(col, X, Y, 2, lw, {});
		*)
		L.X := x; L.Y := y; L.col := col; L.width := lw;
		RETURN L
	END RLine;

	PROCEDURE Line(col, x, y, w, h: INTEGER): Display.Frame;
		VAR X, Y: ARRAY 2 OF INTEGER; L: BasicFigures.Figure;
	BEGIN X[0] := 0; Y[0] := 0; X[1] := w; Y[1] := h;
		IF w < 0 THEN X[0] := -w; X[1] := 0 END;
		IF h < 0 THEN Y[0] := -h; Y[1] := 0 END;
		NEW(L); BasicFigures.InitLine(L, X[0], Y[0], X[1], Y[1]);
		(*
		L := Figures.NewPolyLine(col, X, Y, 2, 1, {});
		*)
		L.X := x; L.Y := y; L.col := col; L.width := 1;
		RETURN L
	END Line;
	
	PROCEDURE NewCap*(fnt: Objects.Library; col, X, Y: INTEGER; s: ARRAY OF CHAR): TextFields.Caption;
	VAR cap: TextFields.Caption; x: INTEGER;
	BEGIN
		NEW(cap); 
		NEW(cap.text); Texts.Open(cap.text,"");
		Texts.SetFont(W,fnt);  Texts.WriteString(W,s);  Texts.Append(cap.text,W.buf);
		Texts.SetFont(W,Fonts.Default);
		TextFields.CalcSize(cap, cap.W, cap.H, x, TRUE);
		cap.X := X; cap.Y := Y; cap.handle := TextFields.CaptionHandler;
		RETURN cap;
	END NewCap;
	
	PROCEDURE Caption(fnt: Fonts.Font; col, X, Y: INTEGER; VAR s: ARRAY OF CHAR): Display.Frame;
		VAR C: Display.Frame;
	BEGIN
		C := NewCap(fnt, col, X, Y, s); C.handle := TextFields.CaptionHandler;
		RETURN C
	END Caption;

	PROCEDURE Rect(VAR R: Files.Rider; col, x, y, w, h: INTEGER): Display.Frame;
		VAR state: SET; len: INTEGER; lw, vers: SHORTINT; L: BasicFigures.Figure;
	BEGIN
		Files.ReadInt(R, len); Files.Read(R, lw); Files.Read(R, vers);
		state := {}; IF vers > 0 THEN INCL(state, BasicFigures.filled); col := -BasicFigures.filled + vers END;
		NEW(L); BasicFigures.InitRect(L, w, h); L.width := lw; L.col := col; L.X := x; L.Y := y;
		RETURN L
	END Rect;

	PROCEDURE Curves(VAR R: Files.Rider; col, x, y, w, h: INTEGER): Display.Frame;
		VAR len, kind, lw, r: INTEGER; C: BasicFigures.Figure;
	BEGIN
		Files.ReadInt(R, len); Files.ReadInt(R, kind); Files.ReadInt(R, lw);
		IF kind = 0 THEN RETURN Line(col, x, y, w, h)
		ELSIF kind = 1 THEN RETURN Line(col, x, y, w, -h)
		ELSIF kind = 2 THEN
			r := w DIV 2; NEW(C); BasicFigures.InitCircle(C, r); C.col := col; C.X := x + r; C.Y := y + r;
			RETURN C
		ELSE RETURN NIL
		END
	END Curves;

	PROCEDURE Macro(lib: Objects.Library; col, X, Y: INTEGER; VAR s : ARRAY OF CHAR): Display.Frame;
		VAR F: Display.Frame; obj: Objects.Object; ref: INTEGER;
	BEGIN Objects.GetRef(lib.dict, s, ref); lib.GetObj(lib, ref, obj);
	(*
		F := Figures0.ViewTo(obj(Display.Frame)); F.X := X; F.Y := Y;
	RETURN F
	*)
		RETURN NIL
	END Macro;

	PROCEDURE ThisLib(name: ARRAY OF CHAR): Objects.Library;
	BEGIN
		IF name = "TTL0" THEN RETURN Objects.ThisLibrary("TTL.Lib") END
	END ThisLib;
	
	PROCEDURE Item(VAR R: Files.Rider; type: SHORTINT): Display.Frame;
		VAR s, t: ARRAY 64 OF CHAR;
			x, y, w, h, col: INTEGER;
			no: SHORTINT;
	BEGIN
		IF type = 0 THEN Files.Read(R, no);
			IF no = 0 THEN Files.Read(R, no); ReadString(R, fontname[no])
			ELSIF no = 1 THEN Files.Read(R, no); ReadString(R, libname[no])
			ELSIF no = 2 THEN Files.Read(R, no); ReadString(R, s); ReadString(R, t);	(*class*)(*alloc*)
				IF s = "Rectangles" THEN elem[no] := Rect
				ELSIF s = "Curves" THEN elem[no] := Curves
				END
			END;
			RETURN NIL
		ELSE Data(R, x, y, w, h, col);
			IF type = 1 THEN RETURN RLine(col, x, y, w, h)
			ELSIF type = 2 THEN Files.Read(R, no); ReadString(R, s);
				RETURN Caption(Fonts.This(fontname[no]), col, x, y, s)
			ELSIF type = 3 THEN Files.Read(R, no); ReadString(R, s);
				RETURN NIL;
				RETURN Macro(ThisLib(libname[no]), col, x, y, s)
			ELSE RETURN elem[type](R, col, x, y, w, h)
			END
		END
	END Item;

	PROCEDURE Load(VAR R: Files.Rider; VAR link: Objects.Object);
		VAR p: Display.Frame; tag, type: SHORTINT;
	BEGIN
		Files.Read(R, tag); Files.Read(R, type);
		WHILE type # -1 DO p := Item(R, type);
			IF p # NIL THEN p.slink := link; link := p END;
			Files.Read(R, type)
		END
	END Load;

	PROCEDURE CoordCheck(obj: Objects.Object): INTEGER;
		VAR G: Display.Frame; obj0: Objects.Object; Y0, Y1: INTEGER;
	BEGIN Y0 := MAX(INTEGER); Y1 := MIN(INTEGER); obj0 := obj;
		WHILE obj0 # NIL DO G := obj0(Display.Frame);
			IF G.Y <  Y0 THEN Y0 := G.Y END;
			IF G.Y + G.H > Y1 THEN Y1 := G.Y + G.H END;
			obj0 := obj0.slink
		END;
		RETURN Y1-Y0
	END CoordCheck;

	PROCEDURE New*;
		VAR M: Display.ConsumeMsg;
			F: Display.Frame;
	BEGIN M.obj := NIL; Load(WTS.R, M.obj);
		Objects.NewObj := NIL;
		Panels.NewPanel;
		IF Objects.NewObj # NIL THEN F := Objects.NewObj(Display.Frame);
			F.W := 400; F.H := 400;
			M.id := Display.drop; Objects.Stamp(M); M.res := -1;
			M.F := F; M.x := 0; M.y := 0; M.u := 0; M.v := -CoordCheck(M.obj);
			F.handle(F, M)
		END
	END New;

BEGIN Texts.OpenWriter(W)
END WTSDraw.

WTS.Convert CLiArch.Text /sb ~
