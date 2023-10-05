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

MODULE Splines;	(** portable *)  (*NW 3.11.90 / 5.7.93 / tk ported to System 3 7.6.95*)
	IMPORT Display, Files, Printer, Oberon, Graphics, GraphicFrames;

	CONST N = 20;

	TYPE Spline* = POINTER TO SplineDesc;

		SplineDesc* = RECORD (Graphics.ObjectDesc)
				n*: INTEGER; open*: BOOLEAN;
				u*, v*: ARRAY N OF INTEGER
			END ;

		RealVector = ARRAY N OF REAL;
		Poly = RECORD a, b, c, d, t: REAL END ;
		PolyVector = ARRAY N OF Poly;

	VAR method*: Graphics.Method;

	PROCEDURE mark(col, x0, y0: INTEGER; sp: Spline);
		VAR i, n: INTEGER;
	BEGIN i := 1;
		IF sp.open THEN n := sp.n ELSE n := sp.n-1 END ;
		WHILE i < n DO
			INC(i); Display.ReplConst(col, sp.u[i] + x0, sp.v[i] + y0, 4, 4, 0)
		END
	END mark;

	PROCEDURE markOrg(col, x, y: INTEGER; sp: Spline);
	BEGIN INC(x, sp.u[0]); INC(y, sp.v[0]);
		Display.ReplConst(col, x, y, 4, 4, 0)
	END markOrg;

	PROCEDURE ShowPoly(col: INTEGER; VAR p, q: Poly; lim: REAL);
		VAR t: REAL;
	BEGIN t := 0;
		REPEAT
			Display.Dot(col, SHORT(ENTIER(((p.a * t + p.b) * t + p.c) * t + p.d)),
				SHORT(ENTIER(((q.a * t + q.b) * t + q.c) * t + q.d)), 0);
			t := t + 1.0
		UNTIL t >= lim
	END ShowPoly;

	PROCEDURE SolveTriDiag(VAR a, b, c, y: RealVector; n: INTEGER);
		VAR i: INTEGER;  t: REAL;
	BEGIN (*a, b, c of tri-diag matrix T; solve Ty' = y for y', assign y' to y*)
		i := 1;
		WHILE i < n DO
			t := c[i-1]*y[i-1];  y[i] := y[i] - t;  INC(i)
		END ;
		i := n-1; y[i] := y[i]/a[i];
		WHILE i > 0 DO
			DEC(i);  t := b[i]*y[i+1];  y[i] := (y[i] - t)/a[i]
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
		VAR i: INTEGER; d1, d2, hn, dn: REAL;
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
		d1 := (d[0] + d[i])/(w[0] + w[i] + x[i+1] - x[i]); i := 0;
		WHILE i < n-1 DO d[i] := d[i] - d1*w[i]; INC(i) END ;
		d[i] := d[0]
	END ClosedSpline;

	PROCEDURE CompSpline(col, x0, y0: INTEGER; sp: Spline);
		VAR i, n: INTEGER; dx, dy, ds: REAL;
			x, xd, y, yd, s: RealVector;
			p, q: PolyVector;
	BEGIN (*from u, v compute x, y, s*)
		x[0] := sp.u[0] + x0; y[0] := sp.v[0] + y0; s[0] := 0; n := sp.n; i := 1;
		WHILE i < n DO
			x[i] := sp.u[i] + x0; dx := x[i] - x[i-1];
			y[i] := sp.v[i] + y0; dy := y[i] - y[i-1];
			s[i] := ABS(dx) + ABS(dy) + s[i-1]; INC(i)
		END ;
		IF sp.open THEN OpenSpline(s, x, xd, n); OpenSpline(s, y, yd, n)
		ELSE ClosedSpline(s, x, xd, n); ClosedSpline(s, y, yd, n)
		END ;
		(*compute coefficients from x, y, xd, yd, s*)  i := 0;
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
		END ;
		p[i].t := s[i]; q[i].t := s[i];
		(*display polynomials*)
		i := 0;
		WHILE i < n-1 DO ShowPoly(col, p[i], q[i], p[i+1].t - p[i].t); INC(i) END
	END CompSpline;

	PROCEDURE New*;
		VAR sp: Spline;
	BEGIN NEW(sp); sp.do := method; Graphics.new := sp
	END New;

	PROCEDURE Copy(src, dst: Graphics.Object);
	BEGIN dst(Spline)^ := src(Spline)^
	END Copy;

	PROCEDURE Draw(obj: Graphics.Object; VAR M: Graphics.Msg);
		VAR x, y, w, h, col: INTEGER; f: GraphicFrames.Frame;
	BEGIN
		WITH M: GraphicFrames.DrawMsg DO
			x := obj.x + M.x; y := obj.y + M.y; w := obj.w; h := obj.h; f := M.f;
			IF (x < f.X1) & (f.X <= x+w) & (y < f.Y1) & (f.Y <= y+h) THEN
				Display.SetClip(f.X, f.Y, f.W, f.H);
				IF M.col = Display.BG THEN col := obj.col ELSE col := M.col END ;
				WITH obj: Spline DO
					IF M.mode = 0 THEN
						IF obj.selected THEN mark(Display.FG, x, y, obj) END ;
						CompSpline(col, x, y, obj); markOrg(Display.FG, x, y, obj)
					ELSIF M.mode = 1 THEN mark(Display.FG, x, y, obj)
					ELSIF M.mode = 2 THEN mark(f.col, x, y, obj); markOrg(Display.FG, x, y, obj)
					ELSE mark(f.col, x, y, obj);
						CompSpline(f.col, x, y, obj); markOrg(f.col, x, y, obj)
					END
				END;
				Display.ResetClip
			END
		END
	END Draw;

	PROCEDURE Selectable(obj: Graphics.Object; x, y: INTEGER): BOOLEAN;
		VAR x0, y0: INTEGER;
	BEGIN x0 := obj.x + obj(Spline).u[0]; y0 := obj.y + obj(Spline).v[0];
		RETURN (x0 - 4 <= x) & (x <= x0 + 4) & (y0 - 4 <= y) & (y <= y0 + 4)
	END Selectable;

	PROCEDURE Handle(obj: Graphics.Object; VAR M: Graphics.Msg);
	BEGIN
		IF M IS Graphics.ColorMsg THEN obj.col := M(Graphics.ColorMsg).col END
	END Handle;

	PROCEDURE Read(obj: Graphics.Object; VAR R: Files.Rider; VAR C: Graphics.Context);
		VAR i, j, len: INTEGER; s: SHORTINT;
	BEGIN i := 0; j := 0; Files.ReadInt(R, len);
		WITH obj: Spline DO
			obj.n := (len-1) DIV 4; Files.Read(R, s); obj.open := s=1;
			WHILE i < obj.n DO Files.ReadInt(R, obj.u[i]); INC(i) END;
			WHILE j < obj.n DO Files.ReadInt(R, obj.v[j]); INC(j) END
		END
	END Read;

	PROCEDURE Write(obj: Graphics.Object; cno: SHORTINT; VAR W: Files.Rider; VAR C: Graphics.Context);
		VAR i, j: INTEGER;
	BEGIN i := 0; j := 0;
		WITH obj: Spline DO
			Graphics.WriteObj(W, cno, obj); Files.WriteInt(W, obj.n * 4 + 1);
			IF obj.open THEN Files.Write(W, 1) ELSE Files.Write(W, 0) END ;
			WHILE i < obj.n DO Files.WriteInt(W, obj.u[i]); INC(i) END;
			WHILE j < obj.n DO Files.WriteInt(W, obj.v[j]); INC(j) END
		END
	END Write;

	PROCEDURE Print(obj: Graphics.Object; x, y: INTEGER);
		VAR i, n, open: INTEGER;
			u, v: ARRAY N OF INTEGER;
	BEGIN
		WITH obj: Spline DO
			IF obj.open THEN open := 1 ELSE open := 0 END ;
			n := obj.n; i := 0;
			WHILE i < n DO u[i] := obj.u[i]*Graphics.scale; v[i] := obj.v[i]*Graphics.scale; INC(i) END ;
			Printer.Spline(obj.x*Graphics.scale + x, obj.y*Graphics.scale + y, n, open, u, v)
		END
	END Print;

	PROCEDURE MakeSpline(open: BOOLEAN);
		VAR x0, x1, x2, y0, y1, y2, i, n: INTEGER;
			spl: Spline;
			G: GraphicFrames.Frame;
			L: GraphicFrames.Location;
	BEGIN G := GraphicFrames.Focus();
		IF (G # NIL) & (G.mark.next # NIL) THEN
			GraphicFrames.Deselect(G);
			NEW(spl); x0 := G.mark.x; y0 := G.mark.y; x1 := x0; y1 := y0;
			spl.u[0] := x0; spl.v[0] := y0; L := G.mark.next; i := 0; n := 1;
			WHILE (L # NIL) & (n < N-1) DO
				x2 := L.x; spl.u[n] := x2; y2 := L.y; spl.v[n] := y2;
				IF x2 < x0 THEN x0 := x2 END ;
				IF x1 < x2 THEN x1 := x2 END ;
				IF y2 < y0 THEN y0 := y2 END ;
				IF y1 < y2 THEN y1 := y2 END ;
				INC(n); L := L.next
			END ;
			WHILE i < n DO DEC(spl.u[i], x0); DEC(spl.v[i], y0); INC(i) END ;
			IF ~open THEN spl.u[n] := spl.u[0]; spl.v[n] := spl.v[0]; INC(n) END ;
			spl.x := x0 - G.x; spl.y :=  y0 - G.y; spl.w := x1 - x0 + 1; spl.h := y1 - y0 + 1;
			spl.open := open; spl.n := n; spl.col := Oberon.CurCol; spl.do := method;
			Graphics.Add(G.graph, spl);
			GraphicFrames.Defocus(G); GraphicFrames.DrawObj(G, spl)
		END
	END MakeSpline;

	PROCEDURE MakeOpen*;
	BEGIN MakeSpline(TRUE)
	END MakeOpen;

	PROCEDURE MakeClosed*;
	BEGIN MakeSpline(FALSE)
	END MakeClosed;

BEGIN NEW(method); method.module := "Splines"; method.allocator := "New";
	method.new := New; method.copy := Copy; method.draw := Draw;
	method.selectable := Selectable; method.handle := Handle;
	method.read := Read; method.write := Write; method.print := Print
END Splines.
