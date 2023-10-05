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

MODULE BasicFigures;	(** portable *) (* jm 27.4.95 *)

(** Gadgets for basic geometric figures. This modules provides a base for creating further geometric gadgets based on the editing of control points.
*)

(*
	Taken from Figures by Karl Rege:
		- Spline to polygon conversion
		- Hit Detection inside a polygon
		
	Known problems:
		- on Windows, the pattern origins are not calculated correctly
		- grid snapping seems to be a problem
		- hit detection inside filled polygon might be a problem
*)

IMPORT Math, Files, Display, Display3, Printer, Printer3, Effects, Objects, Gadgets, Oberon;

CONST
	(** State0 settings. *)
	filled* = 0;	(** Primitive is filled. *)
	closed* = 1;	(** Beginning and ending control points are connected. *)
	editpoints* = 3;	(** Editing of control points allowed. *)
	
	trackmode* = 3; (** Mode parameter for Draw method. Indicates fast drawing during interactive tracking. *)
	
	PointOffset = 2; PointSize = 5; (* size of the control points. Currently not related to Effects.gravity *)
	
TYPE
	Point* = POINTER TO PointDesc;
	PointDesc* = RECORD
		prev*, next*: Point;	(** Control point list. *)
		x*, y*: INTEGER; (* Point position relative to the bottom left corner of the figure bounding box. *)
	END;
	
	Figure* = POINTER TO FigureDesc;

	Methods* = POINTER TO MethodDesc;
	MethodDesc* = RECORD
		(** Request to redraw figure. Hint indicates a control point that has moved (useful for optimizing redraws). *)
		Draw*: PROCEDURE (F: Figure; M: Display3.Mask; x, y: INTEGER; hint: Point; mode: INTEGER);
		Print*: PROCEDURE (F: Figure; M: Display3.Mask; x, y: INTEGER);
		
		(* Because the control points might be moved outside of the figure bounding box, we have to normalize the coordinate system of the control points and adjust the bounding box. *)
		Normalize*: PROCEDURE (F: Figure; VAR x, y, w, h: INTEGER);
		
		(* Adjust points in figure after resizing *)
		Modify*: PROCEDURE (F: Figure; nw, nh: INTEGER);

		(* Is point mx, my part of the figure ? *)
		HitTest*: PROCEDURE (F: Figure; x, y, mx, my: INTEGER): BOOLEAN;
	END;
	
	FigureDesc* = RECORD (Gadgets.FrameDesc)
		p*: Point;	(** List of control points. *)
		width*: INTEGER;	(** Line width. *)
		state0*: SET;	(** filled, closed, editpoints *)
		col*: INTEGER;	(** Color index. *)
		patno*: INTEGER;	(** Drawing pattern. *)
		do*: Methods;	(** Method block. *)
	END;
	
VAR
	(** Standard method blocks. *)
	CircleMethods*,
	LineMethods*,
	RectMethods*,
	Rect3DMethods*,
	SplineMethods*: Methods;

	u, v: ARRAY 2048 OF INTEGER; (* used for spline to polygon conversion + scratch area for drawing polygons *)
	
PROCEDURE Distance(x, y, x0, y0: INTEGER): INTEGER;
VAR dx, dy: LONGINT;
BEGIN dx := x - x0; dy := y - y0;
	RETURN SHORT(ENTIER(Math.sqrt(dx * dx + dy * dy)))
END Distance;

PROCEDURE Min(x, y: INTEGER): INTEGER;
BEGIN IF x < y THEN RETURN x ELSE RETURN y END
END Min;

PROCEDURE Max(x, y: INTEGER): INTEGER;
BEGIN IF x > y THEN RETURN x ELSE RETURN y END
END Max;

(* convert display coordinates to printer coordinates *)
PROCEDURE Dev(x: INTEGER): INTEGER;
BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
END Dev;

PROCEDURE GetPat(no: INTEGER): Display.Pattern;
BEGIN
	IF (no > 0) & (no < 9) THEN RETURN Printer3.Pattern[no] ELSE RETURN Display.solid END
END GetPat;

(* Is X, Y somewhere inside the polygon defined by p ? *)
PROCEDURE Inside(p: Point; x, y: INTEGER; X, Y: LONGINT): BOOLEAN;
VAR c: INTEGER; q: Point;
	
	PROCEDURE Intersect(x0,y0,x1,y1 : INTEGER) : BOOLEAN;
	BEGIN
		IF ((Y >= y0) & (Y < y1)) OR ((Y >= y1) & (Y < y0)) THEN
			IF y1 > y0 THEN RETURN x0 + (Y - y0) * (x1 -x0) DIV (y1 - y0) - X >= 0 
			ELSIF y1 <  y0 THEN RETURN x0 + (Y - y0) * (x0 -x1) DIV (y0 - y1) - X >= 0
			ELSE RETURN (x0 > X) OR (x1 > X)
			END
		ELSE RETURN FALSE
		END
	END Intersect;
	
BEGIN q := p; c := 0;
	WHILE p.next # NIL DO
		IF Intersect(p.x + x, p.y + y, p.next.x + x, p.next.y + y) THEN INC(c) END;
		p := p.next;
	END;
	IF Intersect(p.x + x, p.y + y, q.x + x, q.y + y) THEN INC(c) END;
	RETURN ODD(c);
END Inside;

PROCEDURE FigureAttr(F: Figure; VAR M: Objects.AttrMsg);
VAR A: Display.ModifyMsg; possiblechange: BOOLEAN;
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.class := Objects.String; COPY("BasicFigures.NewFigure", M.s); M.res := 0
		ELSIF M.name = "Color" THEN M.class := Objects.Int; M.i := F.col; M.res := 0 
		ELSIF M.name = "Width" THEN M.class := Objects.Int; M.i := F.width; M.res := 0
		ELSIF M.name = "Closed" THEN M.class := Objects.Bool; M.b := closed IN F.state0; M.res := 0
		ELSIF M.name = "Filled" THEN M.class := Objects.Bool; M.b := filled IN F.state0; M.res := 0
		ELSIF M.name = "Pattern" THEN M.class := Objects.Int; M.i := F.patno; M.res := 0
		ELSIF M.name = "Cmd" THEN
			Gadgets.framehandle(F, M);
			IF M.res < 0 THEN M.class := Objects.String; M.s := ""; M.res := 0 END;
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		possiblechange := FALSE;
		IF M.name = "Color" THEN
			IF M.class = Objects.Int THEN F.col := SHORT(M.i); M.res := 0 END
		ELSIF M.name = "Pattern" THEN
			IF M.class = Objects.Int THEN
				F.patno := SHORT(M.i);
				IF (F.patno < 0) OR (F.patno > 8) THEN F.patno := 0 END;
				M.res := 0
			END
		ELSIF M.name = "Width" THEN
			IF M.class = Objects.Int THEN F.width := SHORT(M.i); M.res := 0; possiblechange := TRUE END;
		ELSIF M.name = "Closed" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN INCL(F.state0, closed) ELSE EXCL(F.state0, closed) END;
				M.res := 0; possiblechange := TRUE
			END
		ELSIF M.name = "Filled" THEN
			IF M.class = Objects.Bool THEN
				IF M.b THEN INCL(F.state0, filled) ELSE EXCL(F.state0, filled) END;
				M.res := 0;
				possiblechange := TRUE
			END
		ELSE Gadgets.framehandle(F, M);
		END;
		(* check for changes *)
		IF possiblechange THEN
			F.do.Normalize(F, A.X, A.Y, A.W, A.H);
			IF (A.X # F.X) OR (A.Y # F.Y) OR (A.W # F.W) OR (A.H # F.H) THEN
				A.id := Display.extend; A.F := F; A.mode := Display.display;
				A.dX := A.X - F.X; A.dY := A.Y - F.Y; A.dW := A.W - F.W; A.dH := A.H - F.H;
				Display.Broadcast(A)
			END
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Color"); M.Enum("Width"); M.Enum("Pattern"); M.Enum("Closed"); M.Enum("Filled");
		M.Enum("Cmd");
		Gadgets.framehandle(F, M)
	END
END FigureAttr;

PROCEDURE RestoreFigure(F: Figure; M: Display3.Mask; x, y, w, h: INTEGER);
VAR p: Point;
BEGIN
	F.do.Draw(F, M, x, y, NIL, Display.replace);
	IF Gadgets.selected IN F.state THEN
		p := F.p;
		WHILE p # NIL DO
			Display3.FilledRect3D(M, Display.FG, Display.FG, Display.BG, x + p.x - PointOffset, y + p.y - PointOffset,
				PointSize, PointSize, 1, Display.paint);
			p := p.next
		END
	END
END RestoreFigure;

PROCEDURE PrintFigure (F: Figure; VAR M: Display.DisplayMsg);
VAR Q: Display3.Mask;
BEGIN
  Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, Q); F.do.Print(F, Q, M.x, M.y);
END PrintFigure;

PROCEDURE CopyFigure*(VAR M: Objects.CopyMsg; from, to: Figure);
VAR p, q, lq: Point;
BEGIN
	to.col := from.col; to.width := from.width; to.state0 := from.state0;
	to.do := from.do;
	to.patno := from.patno;
	to.p := NIL; lq := NIL;
	p := from.p;
	WHILE p # NIL DO
		NEW(q); q^ := p^;
		IF lq = NIL THEN to.p := q
		ELSE lq.next := q; q.prev := lq;
		END;
		lq := q; p := p.next
	END;
	Gadgets.CopyFrame(M, from, to);
END CopyFigure;

(** Return point located at mouse position mx. my (NIL if no point at location). *)
PROCEDURE ThisPoint*(F: Figure; x, y, mx, my: INTEGER): Point;
VAR p: Point;
BEGIN
	p := F.p;
	WHILE p # NIL DO
		IF Effects.Invicinity(mx, my, x + p.x, y + p.y) THEN RETURN p END;
		p := p.next
	END;
	RETURN NIL
END ThisPoint;

PROCEDURE EmptyHandler(obj: Objects.Object; VAR M: Objects.ObjMsg);
END EmptyHandler;

PROCEDURE ThisFrame(not: Display.Frame; X, Y: INTEGER; VAR F: Display.Frame; VAR u, v: INTEGER);
VAR old: Objects.Handler;
BEGIN
	old := not.handle; not.handle := EmptyHandler;
	Gadgets.ThisFrame(X, Y, F, u, v);
	not.handle := old;
END ThisFrame;

PROCEDURE HasCmdAttr(F: Display.Frame; attr: ARRAY OF CHAR): BOOLEAN;
VAR A: Objects.AttrMsg;
BEGIN
	A.id := Objects.get; COPY(attr, A.name); A.class := Objects.Inval; A.res := -1; A.dlink := NIL; Objects.Stamp(A);
	F.handle(F, A);
	RETURN (A.res >= 0) & (A.class = Objects.String) & (A.s # "") 
END HasCmdAttr;

(** Standard Tracking behavior. *)
PROCEDURE Track*(F: Figure; x, y: INTEGER; VAR M: Oberon.InputMsg);
VAR p, q: Point; mx, my, px, py, ox, oy: INTEGER; A: Display.ModifyMsg; lastkeys, keysum: SET;
	f: Display.Frame; u0, v0: INTEGER; C: Display.ConsumeMsg; CM: Objects.CopyMsg;
	R: Display3.Mask;
BEGIN
	IF M.keys = {1} THEN
		p := ThisPoint(F, x, y, M.X, M.Y);
		IF (p # NIL) & (Gadgets.selected IN F.state) & ~Gadgets.IsLocked(F, M.dlink) THEN
			Effects.Snap(M.X, M.Y);
			keysum := M.keys; lastkeys := M.keys; ox := p.x; oy := p.y;
			mx := M.X; my := M.Y; Oberon.FadeCursor(Oberon.Mouse); F.do.Draw(F, NIL, x, y, p, trackmode);
			REPEAT
				Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow);
				IF (mx # M.X) OR (my # M.Y) OR (M.keys # lastkeys) THEN
					Oberon.FadeCursor(Oberon.Mouse); F.do.Draw(F, NIL, x, y, p, trackmode);
					IF (lastkeys = {1, 0}) & (M.keys = {1}) & (editpoints IN F.state0) THEN (* copy combination *)
						NEW(q); q.x := p.x + M.X - mx; q.y := p.y + M.Y - my;
						
						p.x := ox; p.y := oy;  ox := q.x; oy := q.y;
						q.next := p.next; p.next := q;
						q.prev := p; IF q.next # NIL THEN q.next.prev := q END;
						
						F.do.Normalize(F, A.X, A.Y, A.W, A.H);
						A.id := Display.extend; A.F := F; A.mode := Display.display;
						A.dX := A.X - F.X; A.dY := A.Y - F.Y; A.dW := A.W - F.W; A.dH := A.H - F.H;
						Display.Broadcast(A);
						x := x + A.dX; y := y + A.dY;
						p := q; Oberon.FadeCursor(Oberon.Mouse); F.do.Draw(F, NIL, x, y, p, trackmode);
					ELSIF (lastkeys = {1, 2}) & (M.keys = {1}) & ~((F.p.next # NIL) & (F.p.next.next = NIL)) &
						(editpoints IN F.state0) THEN (* delete combination *)
						IF p.prev # NIL THEN p.prev.next := p.next ELSE F.p := p.next END;
						IF p.next # NIL THEN p.next.prev := p.prev END;
						F.do.Normalize(F, A.X, A.Y, A.W, A.H);
						A.id := Display.extend; A.F := F; A.mode := Display.display;
						A.dX := A.X - F.X; A.dY := A.Y - F.Y; A.dW := A.W - F.W; A.dH := A.H - F.H;
						Display.Broadcast(A);
						REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); UNTIL M.keys = {};
						M.res := 0; RETURN;
					ELSE
						p.x := p.x + M.X - mx; p.y := p.y + M.Y - my;
						mx := M.X; my := M.Y;
						Oberon.FadeCursor(Oberon.Mouse); F.do.Draw(F, NIL, x, y, p, trackmode);
					END;
				END;
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
				lastkeys := M.keys;
				keysum := keysum + M.keys;
			UNTIL M.keys = {};
			Oberon.FadeCursor(Oberon.Mouse);
			F.do.Draw(F, NIL, x, y, p, trackmode);
			IF keysum = {0, 1, 2} THEN p.x := ox; p.y := oy END;
			F.do.Normalize(F, A.X, A.Y, A.W, A.H);
			A.id := Display.extend; A.F := F; A.mode := Display.display;
			A.dX := A.X - F.X; A.dY := A.Y - F.Y; A.dW := A.W - F.W; A.dH := A.H - F.H;
			Display.Broadcast(A);
			M.res := 0;
		ELSIF ~(Gadgets.selected IN F.state) & F.do.HitTest(F, x, y, M.X, M.Y) THEN (* not a control point *)
			IF HasCmdAttr(F, "Cmd") THEN
				Gadgets.MakeMask(F, x, y, M.dlink, R);
				Oberon.FadeCursor(Oberon.Mouse);
				F.do.Draw(F, R, x, y, NIL, Display.invert);
				keysum := M.keys;
				REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys UNTIL M.keys = {};
				Oberon.FadeCursor(Oberon.Mouse);
				F.do.Draw(F, R, x, y, NIL, Display.invert);
				IF F.do.HitTest(F, x, y, M.X, M.Y) & (keysum = {1}) THEN Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL) END;
			ELSIF ~Gadgets.IsLocked(F, M.dlink) THEN
				Effects.Snap(M.X, M.Y);
				ox := M.X - x; oy := M.Y - y;
				keysum := M.keys; mx := M.X; my := M.Y; px := x; py := y;
				Oberon.FadeCursor(Oberon.Mouse); F.do.Draw(F, NIL, px, py, NIL, trackmode);
				REPEAT
					Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow);
					IF (mx # M.X) OR (my # M.Y) THEN
						Oberon.FadeCursor(Oberon.Mouse);
						F.do.Draw(F, NIL, px, py, NIL, trackmode);
						px := px + M.X - mx; py := py + M.Y - my;
						mx := M.X; my := M.Y;
						F.do.Draw(F, NIL, px, py, NIL, trackmode);
					END;
					Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
					keysum := keysum + M.keys;
				UNTIL M.keys = {};
				Oberon.FadeCursor(Oberon.Mouse);
				F.do.Draw(F, NIL, px, py, NIL, trackmode);
				IF keysum = {1} THEN (* move *)
					A.id := Display.move; A.F := F; A.mode := Display.display;
					A.X := F.X + px - x; A.Y := F.Y + py - y; A.W := F.W; A.H := F.H;
					A.dX := A.X - F.X; A.dY := A.Y - F.Y; A.dW := A.W - F.W; A.dH := A.H - F.H;
					Display.Broadcast(A);
				ELSIF keysum = {1, 2} THEN (* consume *)
					ThisFrame(F, M.X, M.Y, f, u0, v0);
					IF f # NIL THEN
						C.id := Display.drop; C.obj := F; F.slink := NIL; C.F := f; C.u := u0 - ox; C.v := v0 - oy;
						Display.Broadcast(C)
					END
				ELSIF keysum = {1, 0} THEN (* copy *)
					ThisFrame(F, M.X, M.Y, f, u0, v0);
					IF f # NIL THEN
						CM.id := Objects.shallow; Objects.Stamp(CM); F.handle(F, CM); CM.obj.slink := NIL; (* copy the object *)
						C.id := Display.drop; C.obj := CM.obj; C.F := f; C.u := u0 - ox; C.v := v0 - oy;
						Display.Broadcast(C)
					END
				END
			END;
			M.res := 0;
		END
	END
END Track;

PROCEDURE ModifyFigure (F: Figure; VAR M: Display.ModifyMsg);
VAR D: Display.DisplayMsg; O: Display3.OverlapMsg;
BEGIN
	IF (F.X # M.X) OR (F.Y # M.Y) OR (F.W # M.W) OR (F.H # M.H) THEN (* first adjust *)
		F.X := M.X; F.Y := M.Y; F.W := M.W; F.H := M.H;
		IF (M.dW # 0) OR (M.dH # 0) THEN F.do.Modify(F, M.W, M.H) END;
		O.F := F; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL; F.handle(F, O)
	END;
	IF (M.mode = Display.display) & (F.H > 0) & (F.W >0) THEN
		D.x := M.x; D.y := M.y; D.F := F; D.device := Display.screen; D.id := Display.full;
		D.dlink := M.dlink; D.res := -1; D.stamp := M.stamp;
		F.handle(F, D)
	END
END ModifyFigure;

PROCEDURE FigureHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h: INTEGER; F0: Figure; R: Display3.Mask; p, p0: Point;
BEGIN
	WITH F: Figure DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN	(* message addressed to this frame *)
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate display coordinates *)
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									RestoreFigure(F, R, x, y, w, h)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreFigure(F, R, x, y, w, h)
								END
							ELSIF M.device = Display.printer THEN PrintFigure(F, M)
							END
						END
					ELSIF M IS Display.LocateMsg THEN
						WITH M: Display.LocateMsg DO
							IF (M.loc = NIL) & F.do.HitTest(F, x, y, M.X, M.Y) THEN
								M.loc := F; M.u := M.X - x; M.v := M.Y - (y + F.H - 1); M.res := 0
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN
								Track(F, x, y, M)
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Display.ModifyMsg THEN
						WITH M: Display.ModifyMsg DO
							IF M.F = F THEN ModifyFigure(F, M) END
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			END
		ELSIF M IS Objects.AttrMsg THEN FigureAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN (* store private data here *)
					Files.WriteInt(M.R, 1); Files.WriteInt(M.R, F.col);
					Files.WriteInt(M.R, F.width); Files.WriteInt(M.R, F.patno); Files.WriteSet(M.R, F.state0);
					x := 0; p := F.p; WHILE p # NIL DO INC(x); p := p.next END;
					Files.WriteInt(M.R, x);
					
					p := F.p; WHILE p # NIL DO Files.WriteInt(M.R, p.x); Files.WriteInt(M.R, p.y); p := p.next END;
					Gadgets.framehandle(F, M)
				ELSIF M.id = Objects.load THEN (* load private data here *)
					Files.ReadInt(M.R, x);
					IF x # 1 THEN HALT(99) END;
					Files.ReadInt(M.R, F.col); Files.ReadInt(M.R, F.width); Files.ReadInt(M.R, F.patno);
					Files.ReadSet(M.R, F.state0);
					Files.ReadInt(M.R, x);
					p0 := NIL;
					WHILE x > 0 DO
						NEW(p); Files.ReadInt(M.R, p.x); Files.ReadInt(M.R, p.y);
						IF p0 = NIL THEN F.p := p ELSE p0.next := p; p.prev := p0 END;
						p0 := p;
						DEC(x)
					END;
					Gadgets.framehandle(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink
				ELSE NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyFigure(M, F, F0); M.obj := F0
				END
			END
		ELSE Gadgets.framehandle(F, M)
		END
	END
END FigureHandler;

(** Append a point with relative coordinates x, y to the control point list of F. *)
PROCEDURE AddPoint*(F: Figure; x, y: INTEGER);
VAR p, q: Point;
BEGIN
	NEW(p); p.x := x; p.y := y;
	IF F.p = NIL THEN F.p := p
	ELSE q := F.p;
		WHILE q.next # NIL DO q := q.next END;
		q.next := p; p.prev := q
	END
END AddPoint;

(** === Lines === *)

PROCEDURE DrawLine*(F: Figure; M: Display3.Mask; x, y: INTEGER; hint: Point; mode: INTEGER);
VAR p, q: Point; n, w, md: INTEGER; pat: LONGINT;

	PROCEDURE Prev(q: Point): Point;
	VAR p: Point;
	BEGIN
		IF q.prev # NIL THEN RETURN q.prev
		ELSIF (closed IN F.state0) OR (filled IN F.state0) THEN
			p := F.p; WHILE p.next # NIL DO p := p.next END;
			RETURN p
		ELSE RETURN NIL
		END
	END Prev;
	
	PROCEDURE Next(q: Point): Point;
	BEGIN
		IF q.next # NIL THEN RETURN q.next
		ELSIF (closed IN F.state0) OR (filled IN F.state0) THEN RETURN F.p
		ELSE RETURN NIL
		END
	END Next;
	
BEGIN
	IF mode = trackmode THEN w := 1; pat := Display.solid; md := Display.invert
	ELSE w := F.width; pat := GetPat(F.patno); md := mode
	END;
	IF hint # NIL THEN
		q := Prev(hint);
		IF q # NIL THEN Display3.Line(M, F.col, pat, x + q.x, y + q.y, x + hint.x, y + hint.y, w, md) END;
		p := Next(hint);
		IF (p # NIL) & (p # q) THEN Display3.Line(M, F.col, pat, x + hint.x, y + hint.y, x + p.x, y + p.y, w, md) END;
	ELSE
		n := 0; p := F.p;
		WHILE p # NIL DO
			u[n] := p.x + x; v[n] := p.y + y; INC(n); p := p.next
		END;
		IF ((closed IN F.state0) OR (filled IN F.state0)) & (n > 2) THEN
			u[n] := u[0]; v[n] := v[0]; INC(n);
		END;
		IF (filled IN F.state0) & (n > 2) & (mode # trackmode) THEN Display3.Poly(M, F.col, pat, u, v, n, w, {Display3.filled}, md)
		ELSE Display3.Poly(M, F.col, pat, u, v, n, w, {}, md)
		END
	END
END DrawLine;

PROCEDURE PrintLine*(F: Figure; M: Display3.Mask; x, y: INTEGER);
VAR p: Point; n: INTEGER; pat: LONGINT;
BEGIN pat := GetPat(F.patno);
	n := 0; p := F.p;
	WHILE p # NIL DO
		u[n] := Dev(p.x) + x; v[n] := Dev(p.y) + y; INC(n); p := p.next
	END;
	IF ((closed IN F.state0) OR (filled IN F.state0)) & (n > 2) THEN
		u[n] := u[0]; v[n] := v[0]; INC(n);
	END;
	IF (filled IN F.state0) & (n > 2) THEN Printer3.Poly(M, F.col, pat, u, v, n, Dev(F.width), {Display3.filled}, Display.replace)
	ELSE Printer3.Poly(M, F.col, pat, u, v, n, Dev(F.width), {}, Display.replace)
	END
END PrintLine;

PROCEDURE HitTestLine*(F: Figure; x, y, mx, my: INTEGER): BOOLEAN;
VAR p, q: Point;
BEGIN
	IF filled IN F.state0 THEN
		IF Inside(F.p, x, y, mx, my) THEN RETURN TRUE END;
	END;
	p := F.p; q := F.p.next;
	WHILE q # NIL DO
		IF Effects.InLineVicinity(mx, my, x + p.x, y + p.y, x + q.x, y + q.y) THEN RETURN TRUE END;
		p := q; q := q.next
	END;
	IF (closed IN F.state0) OR (filled IN F.state0) THEN
		IF Effects.InLineVicinity(mx, my, x + p.x, y + p.y, x + F.p.x, y + F.p.y) THEN RETURN TRUE END;
	END;
	RETURN FALSE
END HitTestLine;

PROCEDURE NormalizeLine*(F: Figure; VAR x, y, w, h: INTEGER);
VAR p: Point; r, t, n: INTEGER;
BEGIN
	x := MAX(INTEGER); r := MIN(INTEGER); t := MIN(INTEGER); y := MAX(INTEGER);
	p := F.p;
	WHILE p # NIL DO
		IF p.x < x THEN x := p.x END;
		IF p.x > r THEN r := p.x END;
		IF p.y < y THEN y := p.y END;
		IF p.y > t THEN t := p.y END;
		p := p.next;
	END;
	n := PointSize DIV 2 + F.width DIV 2 + 1;
	x := x - n; y := y - n; t := t + n; r := r + n;
	w := r - x + 1; h := t - y + 1;
	p := F.p; WHILE p # NIL DO p.x := p.x - x; p.y := p.y - y; p := p.next; END;
	x := F.X + x; y := F.Y + y;
END NormalizeLine;

PROCEDURE ModifyLine* (F: Figure; nw, nh: INTEGER);
VAR p: Point; x, y, r, t, n, ow, oh: INTEGER;
BEGIN
	x := MAX(INTEGER); r := MIN(INTEGER); t := MIN(INTEGER); y := MAX(INTEGER);
	p := F.p;
	WHILE p # NIL DO
		IF p.x < x THEN x := p.x END;
		IF p.x > r THEN r := p.x END;
		IF p.y < y THEN y := p.y END;
		IF p.y > t THEN t := p.y END;
		p := p.next;
	END;
	n := PointSize DIV 2 + F.width DIV 2 + 1;
	ow := r - x + 1; oh := t - y + 1; nw := nw - 2*n; nh := nh - 2*n;
	p := F.p;
	WHILE p # NIL DO
		p.x := SHORT(LONG(p.x - x)*nw DIV ow + x); p.y := SHORT(LONG(p.y - y)*nh DIV oh + y);
		p := p.next
	END
END ModifyLine;

PROCEDURE LineHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH F: Figure DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN M.class := Objects.String; COPY("BasicFigures.NewLine", M.s); M.res := 0
				ELSE FigureHandler(F, M)
				END
			END
		ELSE FigureHandler(F, M)
		END
	END
END LineHandler;

PROCEDURE InitLine*(F: Figure; x, y, x0, y0: INTEGER);
BEGIN
	F.handle := LineHandler; F.col := Display.FG; F.width := 1; F.patno := 0;
	INCL(F.state, Gadgets.transparent); INCL(F.state0, editpoints);
	AddPoint(F, x, y); AddPoint(F, x0, y0);
	F.do := LineMethods;
	F.do.Normalize(F, F.X, F.Y, F.W, F.H);
END InitLine;

PROCEDURE NewLine*;
VAR F: Figure;
BEGIN NEW(F); InitLine(F, 0, 0, 20, 20); Objects.NewObj := F;
END NewLine;

(** === Circles === *)

PROCEDURE DrawCircle*(F: Figure; M: Display3.Mask; x, y: INTEGER; hint: Point; mode: INTEGER);
VAR p, q: Point; w, md: INTEGER; pat: LONGINT;
BEGIN
	IF mode = trackmode THEN w := 1; pat := Display.solid; md := Display.invert
	ELSE w := F.width; pat := GetPat(F.patno); md := mode
	END;
	p := F.p; q := F.p.next;
	IF (filled IN F.state0) & (mode # trackmode) THEN
		Display3.Circle(M, F.col, pat, x + p.x, y + p.y, Distance(p.x, p.y, q.x, q.y), w, {Display3.filled}, md)
	ELSE
		Display3.Circle(M, F.col, pat, x + p.x, y + p.y, Distance(p.x, p.y, q.x, q.y), w, {}, md)
	END
END DrawCircle;

PROCEDURE PrintCircle*(F: Figure; M: Display3.Mask; x, y: INTEGER);
VAR p, q: Point; pat: LONGINT;
BEGIN pat := GetPat(F.patno);
	p := F.p; q := F.p.next;
	IF (filled IN F.state0)THEN
		Printer3.Circle(M, F.col, pat, x + Dev(p.x), y + Dev(p.y), Dev(Distance(p.x, p.y, q.x, q.y)),
			Dev(F.width), {Display3.filled}, Display.replace)
	ELSE
		Printer3.Circle(M, F.col, pat, x + Dev(p.x), y + Dev(p.y), Dev(Distance(p.x, p.y, q.x, q.y)), Dev(F.width), {}, Display.replace)
	END
END PrintCircle;

PROCEDURE NormalizeCircle*(F: Figure; VAR x, y, w, h: INTEGER);
VAR p, q: Point; r, n: INTEGER;
BEGIN
	p := F.p; q := F.p.next; r := Distance(p.x, p.y, q.x, q.y);
	n := r + PointSize DIV 2 + F.width DIV 2 + 1;
	x := p.x - n; y := p.y - n; w := n * 2; h := w;
	p := F.p; WHILE p # NIL DO p.x := p.x - x; p.y := p.y - y; p := p.next; END;
	x := F.X + x; y := F.Y + y;
END NormalizeCircle;

PROCEDURE ModifyCircle* (F: Figure; nw, nh: INTEGER);
VAR p, q: Point; nr, dr, n: INTEGER;
BEGIN
	p := F.p; q := p.next;
	n := PointSize DIV 2 + F.width DIV 2 + 1;
	nw := nw - 2*n; nh := nh - 2*n;
	nr := Min(nw, nh) DIV 2; dr := nr - Distance(p.x, p.y, q.x, q.y);
	p.x := p.x + dr; p.y := p.y + dr;
	q.y := p.y; q.x := p.x + nr
END ModifyCircle;

PROCEDURE HitTestCircle*(F: Figure; x, y, mx, my: INTEGER): BOOLEAN;
VAR p, q: Point; r, r2: INTEGER;
BEGIN
	p := F.p; q := F.p.next; r := Distance(p.x, p.y, q.x, q.y);
	IF (Gadgets.selected IN F.state) & Effects.Invicinity(mx, my, x + p.x, y + p.y) THEN RETURN TRUE
	ELSE
		r2 := Distance(mx - x, my - y, p.x, p.y);
		IF filled IN F.state0 THEN
			RETURN r2 < r + Effects.gravity DIV 2
		ELSE RETURN ABS(r2 - r) <= Effects.gravity
		END
	END
END HitTestCircle;

PROCEDURE CircleHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH F: Figure DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN M.class := Objects.String; COPY("BasicFigures.NewCircle", M.s); M.res := 0
				ELSE FigureHandler(F, M)
				END
			END
		ELSE FigureHandler(F, M)
		END
	END
END CircleHandler;

PROCEDURE InitCircle*(F: Figure; r: INTEGER);
BEGIN
	F.handle := CircleHandler; F.col := Display.FG; F.width := 1; F.patno := 0;
	INCL(F.state, Gadgets.transparent);
	AddPoint(F, 0, 0); AddPoint(F, r, 0);
	F.do := CircleMethods;
	F.do.Normalize(F, F.X, F.Y, F.W, F.H);
END InitCircle;

PROCEDURE NewCircle*;
VAR F: Figure;
BEGIN NEW(F); InitCircle(F, 20); Objects.NewObj := F;
END NewCircle;

(** === Rectangles === *)

PROCEDURE DrawRect*(F: Figure; M: Display3.Mask; x, y: INTEGER; hint: Point; mode: INTEGER);
VAR p, q: Point; w, md: INTEGER; pat: LONGINT;
BEGIN
	IF mode = trackmode THEN w := 1; pat := Display.solid; md := Display.invert
	ELSE w := F.width; pat := GetPat(F.patno); md := mode
	END;
	p := F.p; q := F.p.next;
	IF (filled IN F.state0) & (mode # trackmode) THEN
		Display3.FillPattern(M, F.col, pat, 0, 0, x + Min(p.x, q.x), y + Min(p.y, q.y),
			ABS(p.x - q.x) + 1, ABS(p.y - q.y) + 1, md)
	ELSE
		Display3.Rect(M, F.col, pat, x + Min(p.x, q.x), y + Min(p.y, q.y),
			ABS(p.x - q.x) + 1, ABS(p.y - q.y) + 1, w, md)
	END
END DrawRect;

PROCEDURE PrintRect*(F: Figure; M: Display3.Mask; x, y: INTEGER);
VAR p, q: Point; pat: LONGINT;
BEGIN pat := GetPat(F.patno);
	p := F.p; q := F.p.next;
	IF (filled IN F.state0) THEN
		Printer3.FillPattern(M, F.col, pat, 0, 0, x + Dev(Min(p.x, q.x)), y + Dev(Min(p.y, q.y)),
			Dev(ABS(p.x - q.x) + 1), Dev(ABS(p.y - q.y) + 1), Display.replace)
	ELSE
		Printer3.Rect(M, F.col, pat, x + Dev(Min(p.x, q.x)), y + Dev(Min(p.y, q.y)),
			Dev(ABS(p.x - q.x) + 1), Dev(ABS(p.y - q.y) + 1), Dev(F.width), Display.replace)
	END
END PrintRect;

PROCEDURE NormalizeRect*(F: Figure; VAR x, y, w, h: INTEGER);
VAR p, q: Point;
BEGIN
	p := F.p; q := F.p.next;
	x := Min(p.x, q.x); y := Min(p.y, q.y); w := ABS(p.x - q.x) + 1; h := ABS(p.y - q.y) + 1;
	x := x - PointOffset; y := y - PointOffset; w := w + PointOffset * 2; h := h + PointOffset * 2;
	p := F.p; WHILE p # NIL DO p.x := p.x - x; p.y := p.y - y; p := p.next; END;
	x := F.X + x; y := F.Y + y;
END NormalizeRect;

PROCEDURE ModifyRect* (F: Figure; nw, nh: INTEGER);
VAR p, q: Point;
BEGIN
	p := F.p; q := p.next;
	nw := nw - 1 - 2*PointOffset; nh := nh - 1 - 2*PointOffset;
	IF p. x > q.x THEN p.x := q.x + nw ELSE q.x := p.x + nw END;
	IF p.y > q.y THEN p.y := q.y + nh ELSE q.y := p.y + nh END
END ModifyRect;

PROCEDURE HitTestRect*(F: Figure; x, y, mx, my: INTEGER): BOOLEAN;
BEGIN
	IF filled IN F.state0 THEN
		RETURN Effects.Inside(mx, my, x - PointOffset, y - PointOffset, F.W + PointOffset * 2, F.H + PointOffset * 2)
	ELSE
		RETURN Effects.InBorder(mx, my, x - PointOffset, y - PointOffset, F.W + PointOffset * 2, F.H + PointOffset * 2)
	END
END HitTestRect;

PROCEDURE RectHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH F: Figure DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN M.class := Objects.String; COPY("BasicFigures.NewRect", M.s); M.res := 0
				ELSE FigureHandler(F, M)
				END
			END
		ELSE FigureHandler(F, M)
		END
	END
END RectHandler;

PROCEDURE InitRect*(F: Figure; w, h: INTEGER);
BEGIN F.handle := RectHandler; F.col := Display.FG; F.width := 1; F.patno := 0;
	INCL(F.state, Gadgets.transparent);
	AddPoint(F, 0, h); AddPoint(F, w, 0);
	F.do := RectMethods;
	F.do.Normalize(F, F.X, F.Y, F.W, F.H);
END InitRect;

PROCEDURE NewRect*;
VAR F: Figure;
BEGIN NEW(F); InitRect(F, 30, 20); Objects.NewObj := F;
END NewRect;

(** === 3D-Rectangles === *)

PROCEDURE DrawRect3D*(F: Figure; M: Display3.Mask; x, y: INTEGER; hint: Point; mode: INTEGER);
VAR p, q: Point; w, h, wid: INTEGER;
BEGIN
	p := F.p; q := F.p.next;
	x := x + Min(p.x, q.x); y := y + Min(p.y, q.y); w := ABS(p.x - q.x) + 1; h := ABS(p.y - q.y) + 1;
	IF mode = trackmode THEN Display3.Rect(M, F.col, Display.solid, x, y, w, h, 1, Display.invert)
	ELSE
		wid := F.width;
		Display3.Rect3D(M, Display3.bottomC, Display3.topC, x, y, w, h, wid, mode);
		Display3.Rect3D(M, Display3.topC, Display3.bottomC, x + wid, y + wid, w - 2*wid, h - 2*wid, wid, mode);
		IF (w > 4*wid) & (h > 4*wid) & (filled IN F.state0) THEN	(* inside *)
			INC(wid, wid);
			Display3.FillPattern(M, F.col, GetPat(F.patno), 0, 0, x + wid, y + wid, w - 2*wid, h - 2*wid, mode)
		END
	END
END DrawRect3D;

PROCEDURE PrintRect3D*(F: Figure; M: Display3.Mask; x, y: INTEGER);
VAR p, q: Point; pat: LONGINT; wid, w, h: INTEGER;
BEGIN pat := GetPat(F.patno);
	p := F.p; q := F.p.next;
	x := x + Dev(Min(p.x, q.x)); y := y + Dev(Min(p.y, q.y)); w := Dev(ABS(p.x - q.x) + 1); h := Dev(ABS(p.y - q.y) + 1);
	wid := Dev(F.width);
	Printer3.Rect3D(M, Display3.bottomC, Display3.topC, x, y, w, h, wid, Display.replace);
	Printer3.Rect3D(M, Display3.topC, Display3.bottomC, x + wid, y + wid, w - 2*wid, h - 2*wid, wid, Display.replace);
	IF (filled IN F.state0) & (w > 4*wid) & (h > 4*wid) THEN
		INC(wid, wid);
		Printer3.FillPattern(M, F.col, pat, 0, 0, x + wid, y + wid, w - 2*wid, h - 2*wid, Display.replace)
	END
END PrintRect3D;

(* NormalizeRect3D = NormalizeRect *)

(* ModifyRect3D = ModifyRect *)

(* HitTestRect3D = HitTestRect *)

PROCEDURE Rect3DHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH F: Figure DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN M.class := Objects.String; COPY("BasicFigures.NewRect3D", M.s); M.res := 0
				ELSE FigureHandler(F, M)
				END
			END
		ELSE FigureHandler(F, M)
		END
	END
END Rect3DHandler;

PROCEDURE InitRect3D*(F: Figure; w, h: INTEGER);
BEGIN F.handle := Rect3DHandler; F.col := Display.FG; F.width := 1; F.patno := 0;
	INCL(F.state, Gadgets.transparent);
	AddPoint(F, 0, h); AddPoint(F, w, 0);
	F.do := Rect3DMethods;
	F.do.Normalize(F, F.X, F.Y, F.W, F.H)
END InitRect3D;

PROCEDURE NewRect3D*;
VAR F: Figure;
BEGIN NEW(F); InitRect3D(F, 30, 20); Objects.NewObj := F;
END NewRect3D;

(** === Splines === *)

(* start of Rege code *)

		PROCEDURE MakePoly(VAR RX, RY, RXstrich, RYstrich, RS: ARRAY OF REAL; n: INTEGER; 
									VAR X, Y: ARRAY OF INTEGER; VAR k: INTEGER);
									
			 TYPE Polynom = RECORD A, B, C, D: REAL END;
			 VAR i, cs, smax, k1: INTEGER; px, py: Polynom; 
					 x, dx1, dx2, dx3, y, dy1, dy2, dy3: REAL; L, B, R, T,dW  : INTEGER; 
				
				PROCEDURE GetPolynom((* VAR *) y1, y2, y1s, y2s: REAL; VAR p: Polynom);
					VAR dx1, dyx: REAL;
				BEGIN
					IF RS[i] # RS[i+1] THEN dx1 := 1.0/(RS[i + 1] - RS[i]) ELSE dx1 := 1.0 END;
					dyx := (y2 - y1)*dx1; 
					p.A := dx1*dx1*(-2.0*dyx + y1s + y2s); 
					p.B := dx1*(3.0*dyx - 2.0*y1s - y2s); 
					p.C := y1s; 
					p.D := y1
				END GetPolynom;
				
		BEGIN  
			X[0] := SHORT(ENTIER(RX[1])); Y[0] := SHORT(ENTIER(RY[1])); 
			L := MAX(INTEGER);  B := MAX(INTEGER); R := MIN(INTEGER); T := MIN(INTEGER);
			i := 1; WHILE i <= n DO
				L := Min(L,SHORT(ENTIER(RX[i]))); B := Min(B,SHORT(ENTIER(RY[i])));
				R := Max(R,SHORT(ENTIER(RX[i]))); T := Max(T,SHORT(ENTIER(RY[i])));
				INC(i);
			END;
			
			dW := Max(1,Min((Max(R-L ,T-B)  * 3 DIV n DIV 20),4));
			i := 1; k := 1;
			WHILE i < n DO
				GetPolynom(RX[i], RX[i+1], RXstrich[i], RXstrich[i+1], px); 
				x := px.D; 
				dx1 := px.A + px.B + px.C; 
				dx3 := 6.0*px.A; 
				dx2 := dx3 + 2.0*px.B;
				GetPolynom(RY[i], RY[i+1], RYstrich[i], RYstrich[i+1], py); 
				y := py.D; 
				dy1 := py.A + py.B + py.C; 
				dy3 := 6.0*py.A; 
				dy2 := dy3 + 2.0*py.B;
				smax := SHORT(ENTIER(RS[i+1]-RS[i]));
				cs := 0; 				
				WHILE cs <= smax DO
					X[k] := SHORT(ENTIER(x)); Y[k] := SHORT(ENTIER(y)); 
					k1 := k-1;
					IF (ABS(X[k] - X[k1]) > dW) OR (ABS(Y[k] - Y[k1]) > dW) THEN INC(k) END;
					x   := x + dx1;    y   := y + dy1; 
					dx1 := dx1 + dx2;  dy1 := dy1 + dy2; 
					dx2 := dx2 + dx3;  dy2 := dy2 + dy3;
					INC(cs);
				END;
				INC(i);
			END; (* FOR i *)
			X[k] := SHORT(ENTIER(RX[n])); Y[k] := SHORT(ENTIER(RY[n])); INC(k);
		END MakePoly;

	PROCEDURE SplineToPoly(c: Point; closed: BOOLEAN; VAR X, Y: ARRAY OF INTEGER; VAR k: INTEGER);
		TYPE RealVect = ARRAY 256 OF REAL; 
		VAR   n, i: INTEGER; RS, RX, RY ,RXstrich, RYstrich : RealVect; dx, dy: REAL;
			helpR: REAL;

		PROCEDURE NatSplineDerivates(VAR x, y, d: ARRAY OF REAL; n: INTEGER);
			VAR i: INTEGER; d1, d2: REAL; a, b, c: RealVect; 
		
			PROCEDURE SolveTriDiag(VAR a, b, c: ARRAY OF REAL; n: INTEGER; VAR y: ARRAY OF REAL);
				VAR i: INTEGER; t: REAL;
			BEGIN i := 1;
				WHILE i < n DO t := a[i]; c[i] := c[i]/t; helpR := c[i]*b[i]; a[i+1] := a[i+1] -  helpR; INC(i); END;
				i := 2; 
				WHILE i <= n DO helpR := c[i-1]*y[i-1]; y[i] := y[i] - helpR; INC(i); END;
				t := a[n]; y[n] := y[n]/t; i := n-1;
				WHILE i > 0 DO  t := y[i+1]; helpR :=y[i] - b[i]*t; y[i] := helpR/a[i]; DEC(i) END
			END SolveTriDiag;
		
			BEGIN  (* NatSplineDerivates *)
				IF x[1] # x[2] THEN b[1] := 1.0/(x[2] - x[1]); ELSE b[1] := 1.0 END;
				a[1] := 2.0*b[1]; c[1] := b[1]; 
				d1 := (y[2] - y[1])*3.0*b[1]*b[1]; 
				d[1] := d1;
				i :=2;
				WHILE i < n DO
					IF x[i] # x[i+1] THEN b[i] := 1.0 /(x[i+1] - x[i]) ELSE b[i] := 1.0 END;
					a[i] := 2.0*(c[i-1] + b[i]); c[i] := b[i]; 
					d2 := (y[i+1] - y[i])*3.0*b[i]*b[i]; 
					d[i] := d1 + d2; d1 := d2;
					INC(i);
				END;
				a[n] := 2.0*b[n-1]; d[n] := d1; 
				SolveTriDiag(a, b, c, n, d)
			END NatSplineDerivates; 
			
		PROCEDURE ClSplineDerivates(VAR x, y, d: ARRAY OF REAL; n: INTEGER);
			VAR i: INTEGER; hn1, dn1, d1, d2: REAL; a, b, c, u: RealVect;
				
			PROCEDURE SolveTriDiag2(VAR a, b, c: ARRAY OF REAL; n:INTEGER; VAR y1, y2: ARRAY OF REAL);
			VAR i: INTEGER; t: REAL;
			BEGIN
				i := 1;
				WHILE i < n DO
					t := a[i]; c[i] := c[i]/t; 
					helpR := c[i]*b[i]; a[i+1] := a[i+1] - helpR;
					INC(i)
				END;
				i :=2;
				WHILE i <= n DO
					helpR := c[i-1]*y1[i-1];  y1[i] := y1[i] - helpR; 
					helpR :=  c[i-1]*y2[i-1]; y2[i] := y2[i] - helpR;
					INC(i);
				END;
				t := a[n]; y1[n] := y1[n]/t; t := a[n]; y2[n] := y2[n]/t;
				i := n-1;
				WHILE i > 0 DO
					t := y1[i+1]; helpR := y1[i] - b[i]* t; y1[i] := helpR/a[i]; 
					t := y2[i+1]; helpR :=y2[i] - b[i]*t; y2[i] := helpR/a[i];
					DEC(i)
				END 
			END SolveTriDiag2;
	
		BEGIN  (* ClSplineDerivates *)
			hn1 := 1.0/(x[n] - x[n-1]); 
			dn1 := (y[n] - y[n-1])*3.0*hn1*hn1; 
			IF x[2] # x[1] THEN
				b[1] := 1.0/(x[2] - x[1]); 
			ELSE
				b[1] := 0
			END;
			a[1] := hn1 + 2.0*b[1]; 
			c[1] := b[1]; 
			d1 := (y[2] - y[1])*3.0*b[1]*b[1]; 
			d[1] := dn1 + d1; 
			u[1] := 1.0;
			i := 2;
			WHILE i < n-1 DO
				IF x[i+1] # x[i] THEN b[i] := 1.0/(x[i+1] - x[i]) ELSE b[i] := 0 END;
				a[i] := 2.0*(c[i-1] + b[i]); 
				c[i] := b[i]; 
				d2 := (y[i+1] - y[i])*3.0*b[i]*b[i]; 
				d[i] := d1 + d2; 
				d1 := d2; 
				u[i] := 0.0;
				INC(i)
			END;
			a[n-1] := 2.0*b[n-2] + hn1; 
			d[n-1] := d1 + dn1; 
			u[n-1] := 1.0; 
			SolveTriDiag2(a, b, c, n-1, u, d); 
			helpR := u[1] + u[n-1] + x[n] - x[n-1];
			d1 := (d[1] + d[n-1])/helpR; 
			i := 1;
			WHILE i < n DO 
				d[i] := d[i] - d1*u[i];
				INC(i)
			END; 
			d[n] := d[1]
		END ClSplineDerivates;
		
	BEGIN
		n := 0; WHILE c # NIL DO RX[n+1] := c.x ; RY[n+1] := c.y; INC(n); c := c.next END;
		IF closed THEN RX[n+1] := RX[1]; RY[n+1] := RY[1]; INC(n) ; END;
		RS[1] := 0.0; i := 2;
		WHILE i <= n DO
			dx := RX[i] - RX[i-1];  dy := RY[i] - RY[i-1]; 
			RS[i] := RS[i-1] + Math.sqrt(dx*dx + dy*dy);
			INC(i);
		END;
		IF ~closed THEN
			NatSplineDerivates(RS, RX, RXstrich, n); 
			NatSplineDerivates(RS, RY, RYstrich, n);
		ELSE
			ClSplineDerivates(RS, RX, RXstrich, n);
			ClSplineDerivates(RS, RY, RYstrich, n)
		END;
		MakePoly(RX, RY, RXstrich, RYstrich, RS, n, X, Y, k);
	END SplineToPoly;

(* end of Rege code *)
		
PROCEDURE DrawSpline*(F: Figure; M: Display3.Mask; x, y: INTEGER; hint: Point; mode: INTEGER);
VAR n, i, w, md: INTEGER; pat: LONGINT;
BEGIN
	IF mode = trackmode THEN w := 1; pat := Display.solid; md := Display.invert
	ELSE w := F.width; pat := GetPat(F.patno); md := mode
	END;

	SplineToPoly(F.p, closed IN F.state0, u, v, n);
	
	FOR i := 0 TO n - 1 DO INC(u[i], x); INC(v[i], y) END;
	IF (filled IN F.state0) & (mode # trackmode) THEN Display3.Poly(M, F.col, pat, u, v, n, w, {Display3.filled}, md)
	ELSE
		IF (filled IN F.state0) THEN
			u[n] := u[0]; v[n] := v[0]; INC(n)
		END;
		Display3.Poly(M, F.col, pat, u, v, n, w, {}, md)
	END
END DrawSpline;

PROCEDURE PrintSpline*(F: Figure; M: Display3.Mask; x, y: INTEGER);
VAR n, i: INTEGER; pat: LONGINT; p, q, lq, to: Point;
BEGIN
	lq := NIL; p := F.p; to := NIL;
	WHILE p # NIL DO
		NEW(q); q.x := Dev(p.x); q.y := Dev(p.y);
		IF lq = NIL THEN to := q
		ELSE lq.next := q; q.prev := lq;
		END;
		lq := q; p := p.next
	END;
	
	pat := GetPat(F.patno);
	SplineToPoly(to, closed IN F.state0, u, v, n);
	
	FOR i := 0 TO n - 1 DO u[i] := u[i] + x; v[i] :=  v[i] + y END;
	IF filled IN F.state0 THEN Printer3.Poly(M, F.col, pat, u, v, n, Dev(F.width), {Display3.filled}, Display3.replace)
	ELSE
		IF (filled IN F.state0) THEN
			u[n] := u[0]; v[n] := v[0]; INC(n)
		END;
		Printer3.Poly(M, F.col, pat, u, v, n, Dev(F.width), {}, Display3.replace)
	END
END PrintSpline;

PROCEDURE NormalizeSpline*(F: Figure; VAR x, y, w, h: INTEGER);
VAR n, i, r, t: INTEGER; p: Point;
BEGIN
	SplineToPoly(F.p, closed IN F.state0, u, v, n);
	x := MAX(INTEGER); r := MIN(INTEGER); t := MIN(INTEGER); y := MAX(INTEGER);
	i := 0;
	WHILE i < n DO
		IF u[i] < x THEN x := u[i] END;
		IF u[i] > r THEN r := u[i] END;
		IF v[i] < y THEN y := v[i] END;
		IF v[i] > t THEN t := v[i] END;
		INC(i)
	END;
	n := PointSize DIV 2 + F.width DIV 2 + 1;
	x := x - n; y := y - n; t := t + n; r := r + n;
	w := r - x + 1; h := t - y + 1;
	p := F.p; WHILE p # NIL DO p.x := p.x - x; p.y := p.y - y; p := p.next; END;
	x := F.X + x; y := F.Y + y
END NormalizeSpline;

PROCEDURE ModifySpline* (F: Figure; nw, nh: INTEGER);
VAR p: Point; i, x, y, r, t, n, ow, oh: INTEGER;
BEGIN
	SplineToPoly(F.p, closed IN F.state0, u, v, n);
	x := MAX(INTEGER); r := MIN(INTEGER); t := MIN(INTEGER); y := MAX(INTEGER);
	i := 0;
	WHILE i < n DO
		IF u[i] < x THEN x := u[i] END;
		IF u[i] > r THEN r := u[i] END;
		IF v[i] < y THEN y := v[i] END;
		IF v[i] > t THEN t := v[i] END;
		INC(i)
	END;
	n := PointSize DIV 2 + F.width DIV 2 + 1;
	ow := r - x + 1; oh := t - y + 1; nw := nw - 2*n; nh := nh - 2*n;
	p := F.p;
	WHILE p # NIL DO
		p.x := SHORT(LONG(p.x - x)*nw DIV ow + x); p.y := SHORT(LONG(p.y - y)*nh DIV oh + y);
		p := p.next
	END
END ModifySpline;

PROCEDURE HitTestSpline*(F: Figure; x, y, mx, my: INTEGER): BOOLEAN;
VAR n, i: INTEGER;
BEGIN
	IF filled IN F.state0 THEN 
		IF Inside(F.p, x, y, mx, my) THEN RETURN TRUE END
	END;
	SplineToPoly(F.p, closed IN F.state0, u, v, n);
	i := 0;
	WHILE i < n - 1 DO
		IF Effects.InLineVicinity(mx, my, u[i]+x, v[i]+y, u[i+1]+ x, v[i+1] + y) THEN RETURN TRUE END;
		INC(i)
	END;
	IF (closed IN F.state0) OR (filled IN F.state0) THEN
		IF Effects.InLineVicinity(mx, my, u[n-1]+x, v[n-1]+y, u[0]+ x, v[0] + y) THEN RETURN TRUE END;
	END;
	RETURN FALSE
END HitTestSpline;

PROCEDURE SplineHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH F: Figure DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN M.class := Objects.String; COPY("BasicFigures.NewSpline", M.s); M.res := 0
				ELSE FigureHandler(F, M)
				END
			END
		ELSE FigureHandler(F, M)
		END
	END
END SplineHandler;

PROCEDURE InitSpline*(F: Figure);
BEGIN
	F.handle := SplineHandler; F.col := Display.FG; F.width := 1;
	INCL(F.state, Gadgets.transparent); INCL(F.state0, editpoints);
	AddPoint(F, 0, 20); AddPoint(F, 20, 0); AddPoint(F, 20, 20); AddPoint(F, 30, 30);
	F.do := SplineMethods;
	F.do.Normalize(F, F.X, F.Y, F.W, F.H);
END InitSpline;

PROCEDURE NewSpline*;
VAR F: Figure;
BEGIN NEW(F); InitSpline(F); Objects.NewObj := F;
END NewSpline;

BEGIN
	NEW(LineMethods);
	LineMethods.Draw := DrawLine;
	LineMethods.Print := PrintLine;
	LineMethods.HitTest := HitTestLine;
	LineMethods.Normalize := NormalizeLine;
	LineMethods.Modify := ModifyLine;
	
	NEW(CircleMethods);
	CircleMethods.Draw := DrawCircle;
	CircleMethods.Print := PrintCircle;
	CircleMethods.HitTest := HitTestCircle;
	CircleMethods.Normalize := NormalizeCircle;
	CircleMethods.Modify := ModifyCircle;

	NEW(RectMethods);
	RectMethods.Draw := DrawRect;
	RectMethods.Print := PrintRect;
	RectMethods.HitTest := HitTestRect;
	RectMethods.Normalize := NormalizeRect;
	RectMethods.Modify := ModifyRect;

	NEW(Rect3DMethods);
	Rect3DMethods.Draw := DrawRect3D;
	Rect3DMethods.Print := PrintRect3D;
	Rect3DMethods.HitTest := HitTestRect;
	Rect3DMethods.Normalize := NormalizeRect;
	Rect3DMethods.Modify := ModifyRect;

	NEW(SplineMethods);
	SplineMethods.Draw := DrawSpline;
	SplineMethods.Print := PrintSpline;
	SplineMethods.HitTest := HitTestSpline;
	SplineMethods.Normalize := NormalizeSpline;
	SplineMethods.Modify := ModifySpline
END BasicFigures.		xxx

System.Free BasicFigures~
Gadgets.Insert BasicFigures.NewLine ~
Gadgets.Insert BasicFigures.NewCircle ~
Gadgets.Insert BasicFigures.NewRect ~
Gadgets.Insert BasicFigures.NewRect3D ~
Gadgets.Insert BasicFigures.NewSpline ~

Gadgets.ChangeAttr Width 6
Gadgets.ChangeAttr Width 2
Gadgets.ChangeAttr Width 1
Gadgets.ChangeAttr Width 40

Gadgets.ChangeAttr Closed Yes
Gadgets.ChangeAttr Closed No

Gadgets.ChangeAttr Filled Yes
Gadgets.ChangeAttr Filled No

(** Remarks:

1. Coordinate Systems
In contrast to the typical gadgets relative coordinate system, the origin for relative control points is the left lower corner of a figure gadget. The x, y coordinates passed to the methods is the lower left corner of the gadget on the display.
*)

