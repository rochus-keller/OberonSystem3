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

MODULE Curves;	(** portable *)  (*NW 8.11.90 / 1.2.91 / JG 14.6.94 ported to System 3*)
	IMPORT Display, Files, Printer, Oberon, Graphics, GraphicFrames;

	TYPE
		Curve* = POINTER TO CurveDesc;

		CurveDesc* = RECORD (Graphics.ObjectDesc)
				kind*, lw*: INTEGER
			END ;

	(*kind: 0 = up-line, 1 = down-line, 2 = circle, 3 = ellipse*)

	VAR method*: Graphics.Method;

	PROCEDURE mark(col, x, y: INTEGER);
	BEGIN Display.ReplConst(col, x, y, 4, 4, 0)
	END mark;

	PROCEDURE line(col: INTEGER; x, y, w, h, d: LONGINT);
		VAR x1, y1, u: LONGINT;
	BEGIN
		IF h < w THEN
			x1 := x+w; u := (h-w) DIV 2;
			IF d = -1 THEN INC(y, h) END ;
			WHILE x < x1 DO
				Display.Dot(col, SHORT(x), SHORT(y), 0); INC(x);
				IF u < 0 THEN INC(u, h) ELSE INC(u, h-w); INC(y, d) END
			END
		ELSE y1 := y+h; u := (w-h) DIV 2;
			IF d = -1 THEN INC(x, w) END ;
			WHILE y < y1 DO
				Display.Dot(col, SHORT(x), SHORT(y), 0); INC(y);
				IF u < 0 THEN INC(u, w) ELSE INC(u, w-h); INC(x, d) END
			END
		END
	END line;

	PROCEDURE circle(col: INTEGER; x0, y0, r: LONGINT);
		VAR x, y, u: LONGINT;
	BEGIN u := 1 - r; x := r; y := 0;
		WHILE y <= x DO
			Display.Dot(col, SHORT(x0+x), SHORT(y0+y), 0);
			Display.Dot(col, SHORT(x0+y), SHORT(y0+x), 0);
			Display.Dot(col, SHORT(x0-y), SHORT(y0+x), 0);
			Display.Dot(col, SHORT(x0-x), SHORT(y0+y), 0);
			Display.Dot(col, SHORT(x0-x), SHORT(y0-y), 0);
			Display.Dot(col, SHORT(x0-y), SHORT(y0-x), 0);
			Display.Dot(col, SHORT(x0+y), SHORT(y0-x), 0);
			Display.Dot(col, SHORT(x0+x), SHORT(y0-y), 0);
			IF u < 0 THEN INC(u, 2*y+3) ELSE INC(u, 2*(y-x)+5); DEC(x) END ;
			INC(y)
		END
	END circle;

	PROCEDURE ellipse(col: INTEGER; x0, y0, a, b: LONGINT);
		VAR x, y, y1, aa, bb, d, g, h: LONGINT;
	BEGIN aa := a*a; bb := b*b;
		h := (aa DIV 4) - b*aa + bb; g := (9*aa DIV 4) - 3*b*aa + bb; x := 0; y := b;
		WHILE g < 0 DO
			Display.Dot(col, SHORT(x0+x), SHORT(y0+y), 0);
			Display.Dot(col, SHORT(x0-x), SHORT(y0+y), 0);
			Display.Dot(col, SHORT(x0-x), SHORT(y0-y), 0);
			Display.Dot(col, SHORT(x0+x), SHORT(y0-y), 0);
			IF h < 0 THEN d := (2*x+3)*bb; INC(g, d)
			ELSE d := (2*x+3)*bb - 2*(y-1)*aa; INC(g, d + 2*aa); DEC(y)
			END ;
			INC(h, d); INC(x)
		END ;
		y1 := y; h := (bb DIV 4) - a*bb + aa; x := a; y := 0;
		WHILE y <= y1 DO
			Display.Dot(col, SHORT(x0+x), SHORT(y0+y), 0);
			Display.Dot(col, SHORT(x0-x), SHORT(y0+y), 0);
			Display.Dot(col, SHORT(x0-x), SHORT(y0-y), 0);
			Display.Dot(col, SHORT(x0+x), SHORT(y0-y), 0);
			IF h < 0 THEN INC(h, (2*y+3)*aa) ELSE INC(h, (2*y+3)*aa - 2*(x-1)*bb); DEC(x) END ;
			INC(y)
		END
	END ellipse;

	PROCEDURE New*;
		VAR c: Curve;
	BEGIN NEW(c); c.do := method; Graphics.new := c
	END New;

	PROCEDURE Copy(src, dst: Graphics.Object);
	BEGIN dst.x := src.x; dst.y := src.y; dst.w := src.w; dst.h := src.h; dst.col := src.col;
		dst(Curve).kind := src(Curve).kind; dst(Curve).lw := src(Curve).lw
	END Copy;

	PROCEDURE Draw(obj: Graphics.Object; VAR M: Graphics.Msg);
		VAR x, y, w, h, col: INTEGER; f: GraphicFrames.Frame;
	BEGIN
		WITH M: GraphicFrames.DrawMsg DO
			x := obj.x + M.x; y := obj.y + M.y; w := obj.w; h := obj.h; f := M.f;
			IF M.col = Display.BG THEN col := obj.col ELSE col := M.col END ;
			IF (x < f.X1) & (f.X <= x+w) & (y < f.Y1) & (f.Y <= y+h) THEN
				Display.SetClip(f.X, f.Y, f.W, f.H);
				IF obj(Curve).kind = 0 THEN  (*up-line*)
					IF M.mode = 0 THEN
						IF obj.selected THEN mark(Display.FG, x, y) END ;
						line(col, x, y, w, h, 1)
					ELSIF M.mode = 1 THEN mark(Display.FG, x, y)
					ELSIF M.mode = 2 THEN mark(f.col, x, y)
					ELSE mark(f.col, x, y); line(f.col, x, y, w, h, 1)
					END
				ELSIF obj(Curve).kind = 1 THEN  (*down-line*)
					IF M.mode = 0 THEN
						IF obj.selected THEN mark(Display.FG, x, y+h) END ;
						line(col, x, y, w, h, -1)
					ELSIF M.mode = 1 THEN mark(Display.FG, x, y+h)
					ELSIF M.mode = 2 THEN mark(f.col, x, y+h)
					ELSE mark(f.col, x, y+h); line(f.col, x, y, w, h, -1)
					END
				ELSIF obj(Curve).kind = 2 THEN  (*circle*)
					w := w DIV 2;
					IF M.mode = 0 THEN
						IF obj.selected THEN mark(Display.FG, x+w, y-4) END ;
						circle(col, x+w, y+w, w)
					ELSIF M.mode = 1 THEN mark(Display.FG, x+w, y-4)
					ELSIF M.mode = 2 THEN mark(f.col, x+w, y-4)
					ELSE mark(f.col, x+w, y-4); circle(f.col, x+w, y+w, w)
					END
				ELSIF obj(Curve).kind = 3 THEN  (*ellipse*)
					w := w DIV 2; h := h DIV 2;
					IF M.mode = 0 THEN
						IF obj.selected THEN mark(Display.FG, x+w, y-4) END ;
						ellipse(col, x+w, y+h, w, h)
					ELSIF M.mode = 1 THEN mark(Display.FG, x+w, y-4)
					ELSIF M.mode = 2 THEN mark(f.col, x+w, y-4)
					ELSE mark(f.col, x+w, y-4); ellipse(f.col, x+w, y+h, w, h)
					END
				END;
				Display.ResetClip
			END
		END
	END Draw;

	PROCEDURE Selectable(obj: Graphics.Object; x, y: INTEGER): BOOLEAN;
		VAR xm, y0, w, h: INTEGER;
	BEGIN
		IF obj(Curve).kind <= 1 THEN  (*line*)
			w := obj.w; h := obj.h;
			IF obj(Curve).kind = 1 THEN y0 := obj.y + h; h := -h ELSE y0 := obj.y END ;
			RETURN (obj.x <= x) & (x < obj.x + w) & (ABS(LONG(y-y0)*w - LONG(x-obj.x)*h) < w*4)
		ELSE (*circle or ellipse*)
			xm := obj.w DIV 2 + obj.x;
			RETURN (xm - 4 <= x) & (x <= xm + 4) & (obj.y - 4 <= y) & (y <= obj.y + 4)
		END
	END Selectable;

	PROCEDURE Handle(obj: Graphics.Object; VAR M: Graphics.Msg);
	BEGIN
		IF M IS Graphics.ColorMsg THEN obj.col := M(Graphics.ColorMsg).col END
	END Handle;

	PROCEDURE Read(obj: Graphics.Object; VAR R: Files.Rider; VAR C: Graphics.Context);
		VAR len: INTEGER;
	BEGIN Files.ReadInt(R, len); Files.ReadInt(R, obj(Curve).kind); Files.ReadInt(R, obj(Curve).lw)
	END Read;

	PROCEDURE Write(obj: Graphics.Object; cno: SHORTINT; VAR W: Files.Rider; VAR C: Graphics.Context);
	BEGIN Graphics.WriteObj(W, cno, obj);
		Files.WriteInt(W, 4); Files.WriteInt(W, obj(Curve).kind); Files.WriteInt(W, obj(Curve).lw)
	END Write;

	PROCEDURE Print(obj: Graphics.Object; x, y: INTEGER);
		VAR x0, y0: INTEGER;
	BEGIN
		IF obj(Curve).kind = 0 THEN
			x0 := obj.x * Graphics.scale + x; y0 := obj.y * Graphics.scale + y;
			Printer.Line(x0, y0, obj.w * Graphics.scale + x0, obj.h * Graphics.scale + y0)
		ELSIF obj(Curve).kind = 1 THEN
			x0 := obj.x * Graphics.scale + x; y0 := obj.y * Graphics.scale + y;
			Printer.Line(x0, obj.h * Graphics.scale + y0, obj.w * Graphics.scale + x0, y0)
		ELSIF obj(Curve).kind = 2 THEN
			Printer.Circle((obj.x*2 + obj.w)*Graphics.scale DIV 2 + x, (obj.y*2 + obj.h)*Graphics.scale DIV 2 + y, 
				obj.w*Graphics.scale DIV 2)
		ELSE
			Printer.Ellipse((obj.x*2 + obj.w)*Graphics.scale DIV 2 + x, (obj.y*2 + obj.h)*Graphics.scale DIV 2 + y, 
				obj.w*Graphics.scale DIV 2, obj.h*Graphics.scale DIV 2)
		END
	END Print;

	PROCEDURE MakeLine*;  (*command*)
		VAR x0, x1, y0, y1: INTEGER;
			c: Curve;
			G: GraphicFrames.Frame;
	BEGIN G := GraphicFrames.Focus();
		IF (G # NIL) & (G.mark.next # NIL) THEN
			GraphicFrames.Deselect(G);
			x0 := G.mark.x; y0 := G.mark.y; x1 := G.mark.next.x; y1 := G.mark.next.y;
			NEW(c); c.col := Oberon.CurCol;
			c.w := ABS(x1-x0); c.h := ABS(y1-y0); c.lw := Graphics.width;
			IF x0 <= x1 THEN c.x := x0;
				IF y0 <= y1 THEN c.kind := 0; c.y := y0 ELSE c.kind := 1; c.y := y1 END
			ELSE c.x := x1;
				IF y1 < y0 THEN c.kind := 0; c.y := y1 ELSE c.kind := 1; c.y := y0 END
			END ;
			DEC(c.x, G.x); DEC(c.y, G.y); c.do := method;
			Graphics.Add(G.graph, c);
			GraphicFrames.Defocus(G); GraphicFrames.DrawObj(G, c)
		END
	END MakeLine;

	PROCEDURE MakeCircle*;  (*command*)
		VAR x0, y0, r: INTEGER;
			c: Curve;
			G: GraphicFrames.Frame;
	BEGIN G := GraphicFrames.Focus();
		IF (G # NIL) & (G.mark.next # NIL) THEN
			GraphicFrames.Deselect(G);
			x0 := G.mark.x; y0 := G.mark.y; r := ABS(G.mark.next.x-x0);
			IF r > 4 THEN
				NEW(c); c.x := x0 - r - G.x; c.y := y0 - r - G.y; c.w := 2*r+1; c.h := c.w;
				c.kind := 2; c.col := Oberon.CurCol;
				c.lw := Graphics.width; c.do := method;
				Graphics.Add(G.graph, c);
				GraphicFrames.Defocus(G); GraphicFrames.DrawObj(G, c)
			END
		END
	END MakeCircle;

	PROCEDURE MakeEllipse*;  (*command*)
		VAR x0, y0, a, b: INTEGER;
			c: Curve;
			G: GraphicFrames.Frame;
	BEGIN G := GraphicFrames.Focus();
		IF (G # NIL) & (G.mark.next # NIL) & (G.mark.next.next # NIL) THEN
			GraphicFrames.Deselect(G);
			x0 := G.mark.x; y0 := G.mark.y;
			a := ABS(G.mark.next.x-x0); b := ABS(G.mark.next.next.y - y0);
			IF (a > 4) & (b > 4) THEN
				NEW(c); c.x := x0 - a - G.x; c.y := y0 - b - G.y; c.w := 2*a+1; c.h := 2*b+1;
				c.kind := 3; c.col := Oberon.CurCol;
				c.lw := Graphics.width; c.do := method;
				Graphics.Add(G.graph, c);
				GraphicFrames.Defocus(G); GraphicFrames.DrawObj(G, c)
			END
		END
	END MakeEllipse;

BEGIN NEW(method); method.module := "Curves"; method.allocator := "New";
	method.new := New; method.copy := Copy; method.draw := Draw;
	method.selectable := Selectable; method.handle := Handle;
	method.read := Read; method.write := Write; method.print := Print
END Curves.
