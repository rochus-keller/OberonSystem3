MODULE LeoPaths;	(** eos   **)

	(**
		Leonardo path shapes
	**)
	
	(*
		Still to do:
		- join curves having the same class
		- curve constraints
	*)
	
	IMPORT
		Modules, Files, Objects, Math, Display, Input, Oberon, Display3, Attributes, Effects, Gadgets, BasicGadgets,
		GfxMatrix, GfxMaps, GfxPictures, GfxPaths, Gfx, GfxPens, Solver, Figures, LeoFrames, Leonardo, LeoPens;
		
	
	CONST
		PointBorder = 3;
		CurveBorder = Figures.BorderWidth;
		
		ML = 2; MM = 1; MR = 0;
		
	
	TYPE
		Point* = POINTER TO PointDesc;
		PointDesc* = RECORD (Figures.ShapeDesc)
			x*, y*: REAL;
		END;
		
		CurveClass* = POINTER TO CurveClassDesc;
		
		Curve* = POINTER TO CurveDesc;
		CurveDesc* = RECORD (Figures.ContainerDesc)
			class*: CurveClass;
			stroke*: GfxPens.Pen;	(** pen used for stroking this curve **)
			succ*, pred*: Curve;	(** curves connected to this one **)
			dx0*, dy0*, dx1*, dy1*: REAL;	(** curve direction at first and last point **)
			boff*, len*, eoff*: REAL;	(** curve offsets and length **)
		END;
		
		Path* = POINTER TO PathDesc;
		PathDesc* = RECORD (Figures.ContainerDesc)
			fill*: GfxPens.Pen;	(* pen used for filling the path **)
		END;
		
		CurveClassDesc* = RECORD
			length*: PROCEDURE (curve: Curve): REAL;
			render*: PROCEDURE (curve: Curve; pen: GfxPens.Pen; VAR dm: Figures.DrawMsg);
			locate*: PROCEDURE (curve: Curve; llx, lly, urx, ury: REAL; VAR prev, next: Figures.Reference; VAR px, py: REAL);
			insert*: PROCEDURE (curve: Curve; p: Point; prev, next: Figures.Reference; fig: Figures.Figure);
			split*: PROCEDURE (curve: Curve; on, p: Point; fig: Figures.Figure);
		END;
		
		(* curve actions *)
		Action = POINTER TO ActionDesc;
		ActionDesc = RECORD (Figures.ActionDesc)
			curve, succ, pred: Curve;
			p: Figures.Shape;
		END;
		
		LengthData = RECORD (GfxPaths.EnumData)
			sx, sy, len: REAL;
		END;
		
		ArcData = RECORD (GfxPaths.EnumData)
			mx, my, rx, ry: REAL;
			sense, tracking: BOOLEAN;
		END;
		
		SplineData = RECORD (GfxPaths.EnumData)
			pen: GfxPens.Pen;
			off: REAL;
		END;
		
		Connector = POINTER TO ConnectorDesc;
		ConnectorDesc = RECORD (Figures.ShapeDesc)
			src, dst: Figures.Shape;
			sstamp, dstamp: LONGINT;
		END;
		
	
	VAR
		PointBG, PointFG: GfxMaps.Map;
		Recorder: GfxPens.Recorder;
		PolygonClass*, ArcClass*, BezierClass*, SplineClass*: CurveClass;
		
		ClosedCurve: BasicGadgets.Boolean;
		Pnt, Cross: Oberon.Marker;
		PntFG, PntBG, CrossFG, CrossBG: Display.Pattern;
		Track: PROCEDURE(frame: LeoFrames.Frame; VAR msg: Oberon.InputMsg);
		Marker: Oberon.Marker;
		
	
	(**--- Connectors ---**)
	
	PROCEDURE HandleConnector (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR
			c, copy: Connector; ctm, mat: GfxMatrix.Matrix; col: Gfx.Color; llx, lly, urx, ury, w, h: REAL;
			tm: Figures.TransformMsg; cm: Objects.CopyMsg; ver: LONGINT;
	BEGIN
		c := obj(Connector);
		IF msg IS Figures.ShapeMsg THEN
			IF msg IS Figures.DrawMsg THEN
				WITH msg: Figures.DrawMsg DO
					IF (msg.id = Figures.Full) & (msg.all OR (c.src.stamp = msg.stamp) OR (c.dst.stamp = msg.stamp)) THEN
						ctm := msg.ctxt.ctm; col := msg.ctxt.fillCol;
						Gfx.ResetCTM(msg.ctxt);
						GfxMatrix.Invert(msg.ctxt.ctm, mat);
						GfxMatrix.Concat(ctm, mat, mat);
						Gfx.SetFillColor(msg.ctxt, Gfx.White);
						GfxMatrix.Apply(mat, c.llx, c.lly, llx, lly);
						GfxMatrix.Apply(mat, c.urx, c.ury, urx, ury);
						w := (urx - llx)/3; h := (ury - lly)/3;
						Gfx.DrawRect(msg.ctxt, llx-3, lly-3, llx+w, lly-2, {Gfx.Fill});
						Gfx.DrawRect(msg.ctxt, llx-3, lly-2, llx-2, lly+h, {Gfx.Fill});
						Gfx.DrawRect(msg.ctxt, urx-w, lly-3, urx+3, lly-2, {Gfx.Fill});
						Gfx.DrawRect(msg.ctxt, urx+2, lly-2, urx+3, lly+h, {Gfx.Fill});
						Gfx.DrawRect(msg.ctxt, llx-3, ury+2, llx+w, ury+3, {Gfx.Fill});
						Gfx.DrawRect(msg.ctxt, llx-3, ury-h, llx-2, ury+2, {Gfx.Fill});
						Gfx.DrawRect(msg.ctxt, urx-w, ury+2, urx+3, ury+3, {Gfx.Fill});
						Gfx.DrawRect(msg.ctxt, urx+2, ury-h, urx+3, ury+2, {Gfx.Fill});
						Gfx.SetFillColor(msg.ctxt, col);
						Gfx.SetCTM(msg.ctxt, ctm)
					END
				END
			ELSIF msg IS Figures.ValidateMsg THEN
				WITH msg: Figures.ValidateMsg DO
					IF (c.dst = NIL) OR (c.dst.cont = NIL) OR (c.src = NIL) OR (c.src.cont = NIL) OR (c.sstamp # c.dstamp) THEN
						c.slink := NIL;
						Figures.Delete(msg.fig, c);
						c.sstamp := MIN(LONGINT); c.dstamp := MIN(LONGINT)
					ELSIF (msg.stamp = c.stamp) OR (msg.stamp = c.src.stamp) OR (msg.stamp = c.dst.stamp) THEN
						c.llx := c.src.llx; c.lly := c.src.lly; c.urx := c.src.urx; c.ury := c.src.ury; c.bw := c.src.bw;
						c.cont.stamp := msg.stamp
					END
				END
			ELSIF msg IS Figures.ControlMsg THEN
				WITH msg: Figures.ControlMsg DO
					IF msg.id = Figures.Remove THEN
						IF (c.dst.stamp = msg.stamp) OR (c.src.stamp = msg.stamp) THEN
							c.stamp := msg.stamp
						END
					END
				END
			ELSIF msg IS Figures.TransformMsg THEN
				WITH msg: Figures.TransformMsg DO
					IF msg.id IN {Figures.Apply, Figures.Notify} THEN
						IF (c.dst.stamp = msg.stamp) & (c.src.stamp # msg.stamp) THEN
							c.src.stamp := msg.stamp;
							c.src.handle(c.src, msg);
							tm.stamp := msg.stamp; tm.fig := msg.fig; tm.id := Figures.Notify; tm.mat := msg.mat;
							msg.fig.handle(msg.fig, tm)
						END;
						c.sstamp := c.src.stamp; c.dstamp := c.dst.stamp
					END
				END
			END
		ELSIF msg IS Objects.AttrMsg THEN
			Figures.HandleGenAttr(msg(Objects.AttrMsg), "LeoPaths.NewConnector")
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # c.stamp THEN
					c.stamp := msg.stamp;
					NEW(copy); c.dlink := copy;
					Figures.CopyShape(msg, c, copy);
					cm.stamp := msg.stamp; cm.id := msg.id;
					c.src.handle(c.src, cm);
					copy.src := cm.obj(Figures.Shape);
					c.dst.handle(c.dst, cm);
					copy.dst := cm.obj(Figures.Shape)
				END;
				msg.obj := c.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			Figures.HandleShape(c, msg)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					Gadgets.WriteRef(msg.R, c.lib, c.dst);
					Gadgets.WriteRef(msg.R, c.lib, c.src)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver >= 1 THEN
						Gadgets.ReadRef(msg.R, c.lib, obj);
						IF (obj # NIL) & (obj IS Figures.Shape) THEN c.dst := obj(Figures.Shape) END;
						Gadgets.ReadRef(msg.R, c.lib, obj);
						IF (obj # NIL) & (obj IS Figures.Shape) THEN c.src := obj(Figures.Shape) END
					END
				END
			END
		END
	END HandleConnector;
	
	PROCEDURE Connect (fig: Figures.Figure; src, dst: Figures.Shape);
		VAR c: Connector;
	BEGIN
		NEW(c); c.handle := HandleConnector;
		c.src := src; c.dst := dst;
		c.sstamp := MIN(LONGINT); c.dstamp := MIN(LONGINT);
		c.llx := src.llx; c.lly := src.lly; c.urx := src.urx; c.ury := src.ury; c.bw := src.bw;
		Figures.Integrate(fig, fig.root.last.shape, c)
	END Connect;
	
	PROCEDURE NewConnector*;
		VAR c: Connector;
	BEGIN
		NEW(c); c.handle := HandleConnector;
		Objects.NewObj := c
	END NewConnector;
	
	
	(**--- Auxiliary Procedures ---**)
	
	PROCEDURE OnLine* (x0, y0, x1, y1, llx, lly, urx, ury: REAL; VAR px, py: REAL): BOOLEAN;
		VAR x, y, dx, dy: REAL;
	BEGIN
		x := 0.5*(llx + urx); y := 0.5*(lly + ury);
		GfxPaths.ProjectToLine(x0, y0, x1, y1, x, y, px, py);
		IF (llx <= px) & (px <= urx) & (lly <= py) & (py <= ury) THEN
			dx := x1 - x0; dy := y1 - y0;
			IF ((x - x0) * dx + (y - y0) * dy >= 0) & ((x1 - x) * dx + (y1 - y) * dy >= 0) THEN
				RETURN TRUE
			END
		END;
		RETURN FALSE
	END OnLine;
	
	PROCEDURE OnArc* (x0, y0, x1, y1, x2, y2, llx, lly, urx, ury: REAL; VAR px, py: REAL): BOOLEAN;
		VAR ax, ay, bx, by, mx, my: REAL;
	BEGIN
		ax := x1 - x2; ay := y1 - y2;
		bx := x1 - x0; by := y1 - y0;
		mx := x0 - ax; my := y0 - ay;
		GfxPaths.ProjectToEllipse(ax, ay, bx, by, 0.5*(llx + urx) - mx, 0.5*(lly + ury) - my, px, py);
		IF ((ax * py - ay * px) >= 0) = ((px * by - py * bx) >= 0) THEN	(* projection is in correct quadrant *)
			px := mx + px; py := my + py;
			IF (llx <= px) & (px <= urx) & (lly <= py) & (py <= ury) THEN
				RETURN TRUE
			END
		END;
		RETURN FALSE
	END OnArc;
	
	PROCEDURE SubdivideBezier* (at, x0, y0, x1, y1, x2, y2, x3, y3: REAL; VAR x11, y11, x12, y12, xm, ym, x21, y21, x22, y22: REAL);
		VAR as, xt, yt: REAL;
	BEGIN
		as := 1 - at;
		x11 := as * x0 + at * x1; y11 := as * y0 + at * y1;
		xt := as * x1 + at * x2; yt := as * y1 + at * y2;
		x22 := as * x2 + at * x3; y22 := as * y2 + at * y3;
		x12 := as * x11 + at * xt; y12 := as * y11 + at * yt;
		x21 := as * xt + at * x22; y21 := as * yt + at * y22;
		xm := as * x12 + at * x21; ym := as * y12 + at * y21
	END SubdivideBezier;
	
	PROCEDURE OnBezier* (x0, y0, x1, y1, x2, y2, x3, y3, llx, lly, urx, ury: REAL; VAR px, py: REAL): BOOLEAN;
		VAR dx, dy, l, d, xa1, ya1, xa2, ya2, xm, ym, xb1, yb1, xb2, yb2: REAL;
	BEGIN
		IF ((llx <= x0) OR (llx <= x1) OR (llx <= x2) OR (llx <= x3)) & ((x0 <= urx) OR (x1 <= urx) OR (x2 <= urx) OR (x3 <= urx)) &
			((lly <= y0) OR (lly <= y1) OR (lly <= y2) OR (lly <= x3)) & ((y0 <= ury) OR (y1 <= ury) OR (y2 <= ury) OR (y3 <= ury))
		THEN
			dx := x3 - x0; dy := y3 - y0;
			l := 0.01*(dx * dx + dy * dy);
			GfxPaths.ProjectToLine(x0, y0, x3, y3, x1, y1, px, py);
			dx := px - x1; dy := py - y1;
			d := dx * dx + dy * dy;
			IF d < l THEN
				GfxPaths.ProjectToLine(x0, y0, x3, y3, x2, y2, px, py);
				dx := px - x2; dy := py - y2;
				d := d + dx * dx + dy * dy
			END;
			IF d < l THEN
				RETURN OnLine(x0, y0, x3, y3, llx, lly, urx, ury, px, py)
			ELSE
				SubdivideBezier(0.5, x0, y0, x1, y1, x2, y2, x3, y3, xa1, ya1, xa2, ya2, xm, ym, xb1, yb1, xb2, yb2);
				IF OnBezier(xm, ym, xb1, yb1, xb2, yb2, x3, y3, llx, lly, urx, ury, px, py) THEN
					RETURN TRUE
				ELSE
					RETURN OnBezier(x0, y0, xa1, ya1, xa2, ya2, xm, ym, llx, lly, urx, ury, px, py)
				END
			END
		ELSE
			RETURN FALSE
		END
	END OnBezier;
	
	PROCEDURE DoSplitPath (fig: Figures.Figure; fa: Figures.Action; stamp: LONGINT; undo: BOOLEAN);
		VAR a: Action; pred, succ: Curve; sm: Figures.SelectMsg;
	BEGIN
		a := fa(Action); pred := a.pred; succ := a.succ;
		IF undo THEN
			pred.succ := succ; succ.pred := pred;
			succ.first.shape := pred.last.shape
		ELSE
			pred.succ := NIL; succ.pred := NIL;
			succ.first.shape := a.p
		END;
		pred.stamp := stamp; succ.stamp := stamp;
		sm.dlink := NIL; sm.fig := fig; sm.id := Figures.Set;
		Figures.Forward(succ, succ.first.shape, sm)
	END DoSplitPath;
	
	PROCEDURE SplitPath* (pred, succ: Curve; p: Point; fig: Figures.Figure);
		VAR cm: Objects.CopyMsg; a: Action;
	BEGIN
		IF p = NIL THEN
			p := succ.first.shape(Point);
			ASSERT(p = pred.last.shape);
			Objects.Stamp(cm); cm.id := Objects.shallow; cm.obj := p;
			p.handle(p, cm);
			p := cm.obj(Point)
		END;
		NEW(a); a.pred := pred; a.succ := succ; a.p := p;
		Figures.AddAction(fig, a, DoSplitPath)
	END SplitPath;
	
	PROCEDURE JoinPaths* (path, with: Path; fig: Figures.Figure);
		VAR ref: Figures.Reference; shapes: Figures.Shape;
	BEGIN
		ref := with.first; shapes := ref.shape;
		WHILE ref.next # NIL DO
			ref.shape.slink := ref.next.shape; ref := ref.next
		END;
		Figures.Delete(fig, shapes);	(* should delete containing path as well *)
		ref.shape.slink := NIL;
		Figures.Integrate(fig, path, shapes)	(* re-integrate curves *)
	END JoinPaths;
	
	PROCEDURE CurveToPath* (fig: Figures.Figure; curve: Curve; VAR path: Path);
		VAR obj: Objects.Object; cont: Figures.Shape;
	BEGIN
		obj := Gadgets.CreateObject("LeoPaths.NewPath"); path := obj(Path);
		cont := curve.cont;
		ASSERT(~(cont IS Path));
		curve.slink := NIL;
		Figures.Delete(fig, curve);
		Figures.Integrate(fig, cont, path);
		Figures.Integrate(fig, path, curve)
	END CurveToPath;
	
	PROCEDURE DoSplitCurve (fig: Figures.Figure; act: Figures.Action; stamp: LONGINT; undo: BOOLEAN);
		VAR a: Action; pred, succ: Curve; ref: Figures.Reference;
	BEGIN
		a := act(Action); pred := a.pred; succ := a.succ;
		IF undo THEN
			ref := succ.first;
			ref.next.prev := NIL;
			WHILE ref # NIL DO ref.shape.cont := pred; ref := ref.next END;
			pred.succ := succ.succ;
			IF pred.succ # NIL THEN pred.succ.pred := pred END
		ELSE
			IF pred.succ # NIL THEN pred.succ.pred := succ END;
			pred.succ := NIL;
			ref := succ.first;
			ref.next.prev := ref;
			WHILE ref # NIL DO ref.shape.cont := succ; ref := ref.next END
		END
	END DoSplitCurve;
	
	PROCEDURE SplitCurve* (pred: Curve; on, p: Point; fig: Figures.Figure);
		VAR path: Path; pf, pl, sf, sl, ref, sref: Figures.Reference; succ: Curve; ca: Figures.ControlAction; a: Action;
	BEGIN
		IF pred.cont # NIL THEN
			IF pred.cont IS Path THEN
				path := pred.cont(Path)
			ELSE
				CurveToPath(fig, pred, path)
			END;
			pf := pred.first; pl := pf;
			WHILE pl.shape # on DO pl := pl.next END;
			NEW(sf); sf.shape := p; sf.next := pl.next;
			sl := pred.last;
			NEW(succ); succ.class := pred.class; succ.handle := pred.handle; succ.stroke := pred.stroke;
			succ.succ := pred.succ; succ.pred := NIL;
			succ.first := sf; succ.last := sl;
			p.cont := succ;
			NEW(ca); Figures.InitControlAction(ca, Figures.Remove, pl, pl.next, sl, NIL, pred);
			Figures.AddAction(fig, ca, Figures.DoControlAction);
			ref := path.first; WHILE ref.shape # pred DO ref := ref.next END;
			NEW(sref); sref.shape := succ;
			NEW(ca); Figures.InitControlAction(ca, Figures.Consume, ref, sref, sref, ref.next, path);
			Figures.AddAction(fig, ca, Figures.DoControlAction);
			NEW(a); a.pred := pred; a.succ := succ;
			Figures.AddAction(fig, a, DoSplitCurve)
		END
	END SplitCurve;
	
	PROCEDURE DoJoinCurves (fig: Figures.Figure; fa: Figures.Action; stamp: LONGINT; undo: BOOLEAN);
		VAR a: Action; pred, succ: Curve; sm: Figures.SelectMsg;
	BEGIN
		a := fa(Action); pred := a.pred; succ := a.succ;
		IF undo THEN
			pred.succ := NIL; succ.pred := NIL;
			pred.last.shape := a.p
		ELSE
			pred.succ := succ; succ.pred := pred;
			pred.last.shape := succ.first.shape
		END;
		pred.stamp := stamp; succ.stamp := stamp;
		sm.dlink := NIL; sm.fig := fig; sm.id := Figures.Set;
		Figures.Forward(pred.cont, pred, sm);
		Figures.Forward(succ.cont, succ, sm)
	END DoJoinCurves;
	
	PROCEDURE JoinCurves* (pred, succ: Curve; fig: Figures.Figure);
		VAR a: Action; path: Path;
	BEGIN
		IF (pred.cont # succ.cont) OR ~(pred.cont IS Path) THEN
			IF (pred.cont IS Path) & (succ.cont IS Path) THEN
				JoinPaths(pred.cont(Path), succ.cont(Path), fig)
			ELSIF pred.cont IS Path THEN
				succ.slink := NIL;
				Figures.Delete(fig, succ);
				Figures.Integrate(fig, pred.cont, succ)
			ELSIF succ.cont IS Path THEN
				pred.slink := NIL;
				Figures.Delete(fig, pred);
				Figures.Integrate(fig, succ.cont, pred)
			ELSE
				CurveToPath(fig, pred, path);
				succ.slink := NIL;
				Figures.Delete(fig, succ);
				Figures.Integrate(fig, path, succ)
			END
		END;
		NEW(a); a.pred := pred; a.succ := succ; a.p := pred.last.shape;
		Figures.AddAction(fig, a, DoJoinCurves)
	END JoinCurves;
	
	
	(**--- Points ---**)
	
	PROCEDURE InitPointImages;
		VAR p: ARRAY 5 OF SET;
	BEGIN
		p[0] := {0..2}; p[1] := {0, 2}; p[2] := {0..2};
		NEW(PointBG); GfxPictures.PatternToMap(Display.NewPattern(3, 3, p), PointBG);
		p[0] := {1..3}; p[1] := {0, 4}; p[2] := {0, 4}; p[3] := {0, 4}; p[4] := {1..3};
		NEW(PointFG); GfxPictures.PatternToMap(Display.NewPattern(5, 5, p), PointFG)
	END InitPointImages;
	
	PROCEDURE RenderPoint* (p: Point; ctxt: Gfx.Context; id: INTEGER; color: Gfx.Color);
		VAR ctm: GfxMatrix.Matrix; px, py: REAL;
	BEGIN
		ctm := ctxt.ctm;
		Gfx.ResetCTM(ctxt);
		GfxMatrix.Apply(ctm, p.x, p.y, px, py);
		GfxMatrix.Solve(ctxt.ctm, ENTIER(px), ENTIER(py), px, py);	(* force pattern to be aligned with figure grid *)
		IF id = Figures.Print THEN
			Gfx.SetFillColor(ctxt, color);
			Gfx.DrawRect(ctxt, px, py, px+1, py+1, {Gfx.Fill})
		ELSIF id = Figures.Full THEN
			Gfx.SetFillColor(ctxt, color);
			IF p.sel THEN
				Gfx.DrawImageAt(ctxt, px-2, py-2, PointFG, GfxMaps.NoFilter);
				Gfx.SetFillColor(ctxt, Gfx.LGrey)
			END;
			Gfx.DrawImageAt(ctxt, px-1, py-1, PointBG, GfxMaps.NoFilter)
		END;
		Gfx.SetCTM(ctxt, ctm)
	END RenderPoint;
	
	PROCEDURE HandlePoint (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR p, q, copy: Point; curve, c: Curve; id, ver: LONGINT; px, py: REAL;
	BEGIN
		p := obj(Point);
		IF msg IS Figures.ShapeMsg THEN
			IF msg IS Figures.LocateMsg THEN
				WITH msg: Figures.LocateMsg DO
					IF msg.stamp # p.stamp THEN
						p.stamp := msg.stamp;
						IF (msg.llx <= p.x) & (p.x <= msg.urx) & (msg.lly <= p.y) & (p.y <= msg.ury) THEN
							IF msg.id = Figures.Inside THEN
								p.slink := msg.shapes; msg.shapes := p
							ELSIF msg.id = Figures.Overlap THEN
								msg.shapes := p; p.slink := NIL
							ELSIF msg.id = Figures.Project THEN
								msg.px := p.x; msg.py := p.y; msg.shapes := p
							END
						END
					END 
				END
			ELSIF msg IS Figures.DrawMsg THEN
				WITH msg: Figures.DrawMsg DO
					IF msg.all OR (p.stamp = msg.stamp) THEN
						RenderPoint(p, msg.ctxt, msg.id, Gfx.Black)
					END
				END
			ELSIF (msg IS Figures.ValidateMsg) & (msg.stamp = p.stamp) THEN
				p.llx := p.x; p.lly := p.y; p.urx := p.x; p.ury := p.y; p.bw := 0;
				Figures.HandleShape(p, msg);
				IF (p.cont # NIL) & (p.cont IS Curve) THEN
					curve := p.cont(Curve);
					IF (p = curve.first.shape) & (curve.pred # NIL) THEN	(* validate both parents of shared point *)
						curve.pred.stamp := msg.stamp
					END
				END
			ELSIF msg IS Figures.ControlMsg THEN
				WITH msg: Figures.ControlMsg DO
					IF (msg.dest = p) & (p.cont # NIL) & (p.cont IS Curve) THEN
						IF msg.shapes IS Curve THEN
							msg.dest := p.cont	(* let containing curve handle this case *)
						ELSIF (msg.shapes IS Point) & (msg.shapes.slink = NIL) THEN
							q := msg.shapes(Point); curve := p.cont(Curve);
							IF q.cont = NIL THEN	(* split path or curve on existing point *)
								IF (p # curve.first.shape) & (p # curve.last.shape) THEN
									curve.class.split(curve, p, q, msg.fig)
								ELSIF (p = curve.first.shape) & (curve.pred # NIL) THEN
									ASSERT((curve.cont # NIL) & (curve.cont IS Path));
									SplitPath(curve.pred, curve, q, msg.fig)
								ELSIF (p = curve.last.shape) & (curve.succ # NIL) THEN
									ASSERT((curve.cont # NIL) & (curve.cont IS Path));
									SplitPath(curve, curve.succ, q, msg.fig)
								END
							ELSIF (p = curve.first.shape) & (curve.pred = NIL) & (q.cont IS Curve) THEN
								c := q.cont(Curve);
								IF (q = c.last.shape) & (c.succ = NIL) THEN
									JoinCurves(c, curve, msg.fig)
								END
							ELSIF (p = curve.last.shape) & (curve.succ = NIL) & (q.cont IS Curve) THEN
								c := q.cont(Curve);
								IF (q = c.first.shape) & (c.pred = NIL) THEN
									JoinCurves(curve, c, msg.fig)
								END
							ELSE	(* establish point-on-point constraint *)
								Connect(msg.fig, q, p)
							END
						END
					END
				END
			ELSIF msg IS Figures.TransformMsg THEN
				WITH msg: Figures.TransformMsg DO
					IF (msg.id = Figures.Apply) & (msg.stamp = p.stamp) THEN
						Solver.RegisterObj(p, id);
						GfxMatrix.Apply(msg.mat, p.x, p.y, px, py);
						Solver.Assign(Solver.Attr(id, "X"), Solver.Real(px));
						Solver.Assign(Solver.Attr(id, "Y"), Solver.Real(py))
					ELSE
						Figures.HandleShape(p, msg)
					END
				END
			ELSE
				Figures.HandleShape(p, msg)
			END
		ELSIF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				Figures.HandleGenAttr(msg, "LeoPaths.NewPoint");
				Figures.HandleRealAttr(msg, "X", p.x);
				Figures.HandleRealAttr(msg, "Y", p.y)
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # p.stamp THEN
					NEW(copy); p.dlink := copy; p.stamp := msg.stamp;
					Figures.CopyShape(msg, p, copy);
					copy.x := p.x; copy.y := p.y
				END;
				msg.obj := p.dlink
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					Files.WriteReal(msg.R, p.x);
					Files.WriteReal(msg.R, p.y)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver > 0 THEN
						Files.ReadReal(msg.R, p.x);
						Files.ReadReal(msg.R, p.y)
					END;
					p.llx := p.x; p.lly := p.y; p.urx := p.x; p.ury := p.y; p.bw := 0
				END
			END
		ELSE
			Figures.HandleShape(p, msg)
		END
	END HandlePoint;
	
	PROCEDURE InitPoint* (p: Point; x, y: REAL);
	BEGIN
		Figures.InitShape(p);
		p.handle := HandlePoint; p.x := x; p.y := y;
		p.llx := p.x; p.lly := p.y; p.urx := p.x; p.ury := p.y; p.bw := 0
	END InitPoint;
	
	PROCEDURE NewPoint*;
		VAR p: Point;
	BEGIN
		NEW(p); InitPoint(p, 0, 0);
		Objects.NewObj := p
	END NewPoint;
	
	
	(**--- Curves ---**)
	
	PROCEDURE RecordCurve* (curve: Curve);
		VAR dm: Figures.DrawMsg;
	BEGIN
		dm.all := TRUE;
		Recorder.do.begin(Recorder, NIL);
		curve.class.render(curve, Recorder, dm);
		Recorder.do.end(Recorder)
	END RecordCurve;
	
	PROCEDURE CurveLength* (curve: Curve): REAL;
	BEGIN
		RecordCurve(curve);
		RETURN GfxPaths.Length(Recorder.path, 1)
	END CurveLength;
	
	PROCEDURE InsertInCurve* (curve: Curve; point: Point; prev, next: Figures.Reference; fig: Figures.Figure);
		VAR ref: Figures.Reference; ca: Figures.ControlAction;
	BEGIN
		NEW(ref); ref.shape := point;
		NEW(ca); Figures.InitControlAction(ca, Figures.Consume, prev, ref, ref, next, curve);
		Figures.AddAction(fig, ca, Figures.DoControlAction)
	END InsertInCurve;
	
	PROCEDURE RenderCurve* (curve: Curve; VAR dm: Figures.DrawMsg);
		VAR pen: GfxPens.Pen;
	BEGIN
		pen := curve.stroke;
		IF pen # NIL THEN	(* render curve path *)
			pen.do.begin(pen, dm.ctxt);
			curve.class.render(curve, pen, dm);
			pen.do.end(pen)
		END
	END RenderCurve;
	
	PROCEDURE RenderSelMarker* (curve: Curve; VAR dm: Figures.DrawMsg);
		VAR
			ctxt: Gfx.Context; ctm, inv: GfxMatrix.Matrix; fillCol: Gfx.Color; fillPat: Gfx.Pattern;
			p: Point; px, py, dx, dy, d: REAL;
		
		PROCEDURE triangle (ctxt: Gfx.Context; px, py, dx, dy: REAL);
		BEGIN
			Gfx.Enter(ctxt, px - 0.5*dy, py + 0.5*dx, 0, 0);
			Gfx.LineTo(ctxt, px + 0.5*dy, py - 0.5*dx);
			Gfx.LineTo(ctxt, px + dx, py + dy);
			Gfx.LineTo(ctxt, px - 0.5*dy, py + 0.5*dx);
			Gfx.Exit(ctxt, 0, 0)
		END triangle;
		
	BEGIN
		IF (dm.id = Figures.Full) & curve.sel & (dm.all OR (curve.stamp = dm.stamp)) THEN	(* render selection markers *)
			ctxt := dm.ctxt;
			ctm := ctxt.ctm; fillCol := ctxt.fillCol; fillPat := ctxt.fillPat;
			Gfx.ResetCTM(ctxt);
			Gfx.SetFillColor(ctxt, Gfx.DGrey);
			Gfx.SetFillPattern(ctxt, NIL);
			GfxMatrix.Invert(ctxt.ctm, inv);
			GfxMatrix.Concat(ctm, inv, inv);	(* maps from current user coords to default user coords *)
			Gfx.Begin(ctxt, {Gfx.Fill});
			p := curve.first.shape(Point);
			GfxMatrix.Apply(inv, p.x, p.y, px, py);
			GfxMatrix.ApplyToVector(inv, curve.dx0, curve.dy0, dx, dy);
			d := 0.5*CurveBorder/Math.sqrt(dx * dx + dy * dy);
			dx := dx*d; dy := dy*d;
			triangle(ctxt, px + dy, py - dx, dx, dy);
			p := curve.last.shape(Point);
			GfxMatrix.Apply(inv, p.x, p.y, px, py);
			GfxMatrix.ApplyToVector(inv, curve.dx1, curve.dy1, dx, dy);
			d := 0.5*CurveBorder/Math.sqrt(dx * dx + dy * dy);
			dx := dx*d; dy := dy*d;
			triangle(ctxt, px - dy - dx, py + dx - dy, dx, dy);
			Gfx.End(ctxt);
			Gfx.SetCTM(ctxt, ctm);
			Gfx.SetFillColor(ctxt, fillCol);
			Gfx.SetFillPattern(ctxt, fillPat)
		END
	END RenderSelMarker;
	
	PROCEDURE ValidateCurve* (curve: Curve);
		VAR bw: REAL; p0, p1: Point;
	BEGIN
		Figures.ValidateContainer(curve);
		IF curve.stroke # NIL THEN
			Attributes.GetReal(curve.stroke, "BorderWidth", bw);
			IF bw > curve.bw THEN curve.bw := bw END
		END;
		IF curve.first = curve.last THEN
			curve.dx0 := 0; curve.dy0 := 0; curve.dx1 := 0; curve.dy1 := 0;
			curve.len := 0
		ELSE
			p0 := curve.first.shape(Point); p1 := curve.first.next.shape(Point);
			curve.dx0 := p1.x - p0.x; curve.dy0 := p1.y - p0.y;
			p0 := curve.last.prev.shape(Point); p1 := curve.last.shape(Point);
			curve.dx1 := p1.x - p0.x; curve.dy1 := p1.y - p0.y;
			curve.len := curve.class.length(curve)
		END;
		curve.boff := 0; curve.eoff := 0	(* may be overridden if part of path *)
	END ValidateCurve;
	
	PROCEDURE SelectCurve (curve: Curve; VAR sm: Figures.SelectMsg);
		VAR shapes: Figures.Shape; ref: Figures.Reference;
	BEGIN
		IF (sm.id = Figures.Get) & curve.sel THEN
			shapes := sm.shapes;
			ref := curve.last;
			IF (curve.succ # NIL) & curve.succ.sel THEN ref := ref.prev END;	(* don't send message twice to shared point *)
			WHILE ref # NIL DO
				Figures.Forward(curve, ref.shape, sm);
				ref := ref.prev
			END;
			IF sm.shapes = shapes THEN
				curve.slink := shapes; sm.shapes := curve
			END
		ELSE
			Figures.HandleContainer(curve, sm)
		END
	END SelectCurve;
	
	PROCEDURE LocateCurve (curve: Curve; VAR lm: Figures.LocateMsg);
		VAR ref, prev, next: Figures.Reference; q, p: Point; px, py: REAL;
	BEGIN
		IF lm.stamp # curve.stamp THEN
			curve.stamp := lm.stamp;
			IF (lm.llx <= curve.urx) & (curve.llx <= lm.urx) & (lm.lly <= curve.ury) & (curve.lly <= lm.ury) THEN
				IF lm.id = Figures.Inside THEN
					IF (lm.llx <= curve.llx) & (curve.urx <= lm.urx) & (lm.lly <= curve.lly) & (curve.ury <= lm.ury) THEN
						curve.slink := lm.shapes; lm.shapes := curve
					ELSE
						Figures.HandleRefs(curve, lm)
					END
				ELSE
					ref := curve.last; q := NIL;
					IF curve.succ # NIL THEN ref := ref.prev END;	(* don't treat shared points twice *)
					WHILE (ref # NIL) & (q = NIL) DO
						p := ref.shape(Point);
						IF (lm.llx <= p.x) & (p.x <= lm.urx) & (lm.lly <= p.y) & (p.y <= lm.ury) THEN q := p END;
						ref := ref.prev
					END;
					IF q = NIL THEN
						curve.class.locate(curve, lm.llx, lm.lly, lm.urx, lm.ury, prev, next, px, py)
					END;
					IF lm.id = Figures.Overlap THEN
						IF (q # NIL) & (curve.sel OR (curve.cont IS Path)) THEN
							q.slink := lm.shapes; lm.shapes := q
						ELSIF (q # NIL) OR (prev # NIL) OR (next # NIL) THEN
							curve.slink := lm.shapes; lm.shapes := curve
						END
					ELSIF lm.id = Figures.Project THEN
						IF q # NIL THEN
							lm.px := p.x; lm.py := p.y; lm.shapes := q
						ELSIF (prev # NIL) OR (next # NIL) THEN
							lm.px := px; lm.py := py; lm.shapes := curve
						END
					END
				END
			END
		END
	END LocateCurve;
	
	PROCEDURE DoUnlinkCurves (fig: Figures.Figure; fa: Figures.Action; stamp: LONGINT; undo: BOOLEAN);
		VAR a: Action;
	BEGIN
		a := fa(Action);
		IF undo THEN a.pred.succ := a.succ; a.succ.pred := a.pred
		ELSE a.pred.succ := NIL; a.succ.pred := NIL
		END;
		a.pred.stamp := stamp; a.succ.stamp := stamp
	END DoUnlinkCurves;
	
	PROCEDURE ControlCurve (curve: Curve; VAR cm: Figures.ControlMsg);
		VAR p: Point; llx, lly, urx, ury: REAL; ref, prev, next: Figures.Reference; px, py: REAL; n: LONGINT; a: Action;
	BEGIN
		IF cm.id = Figures.Consume THEN
			IF cm.dest # curve THEN
				Figures.HandleRefs(curve, cm)
			END;
			IF cm.dest = curve THEN
				IF cm.shapes IS Curve THEN
					cm.dest := curve.cont	(* consuming curves is the responsibility of paths *)
				ELSIF (cm.shapes IS Point) & (cm.shapes.slink = NIL) THEN
					p := cm.shapes(Point); llx := p.x-1; lly := p.y-1; urx := p.x+1; ury := p.y+1;
					ref := curve.last;
					WHILE (ref # NIL) & (cm.dest = curve) DO
						p := ref.shape(Point);
						IF (llx <= p.x) & (p.x <= urx) & (lly <= p.y) & (p.y <= ury) THEN cm.dest := p END;
						ref := ref.prev
					END;
					IF cm.dest # curve THEN
						Figures.Forward(curve, p, cm)
					ELSE
						curve.class.locate(curve, p.x-0.5, p.y-0.5, p.x+0.5, p.y+0.5, prev, next, px, py);
						IF p.cont = NIL THEN	(* insert in curve *)
							IF (prev = NIL) & (next = NIL) THEN	(* append/insert if not on curve *)
								IF curve.succ = NIL THEN prev := curve.last; next := NIL
								ELSE prev := curve.last.prev; next := curve.last
								END
							END;
							curve.class.insert(curve, p, prev, next, cm.fig)
						ELSIF (prev # NIL) OR (next # NIL) THEN	(* establish point-on-curve constraint *)
						END
					END
				END
			END
		ELSIF (cm.id = Figures.Remove) & (cm.stamp # curve.stamp) THEN
			Figures.HandleContainer(curve, cm);
			ref := curve.first; n := 0;
			WHILE ref # NIL DO
				IF ref.shape.stamp # cm.stamp THEN INC(n) END;
				ref := ref.next
			END;
			IF n < 2 THEN	(* not enough points left => remove curve as well *)
				curve.stamp := cm.stamp
			ELSIF (curve.pred # NIL) & (curve.first.shape.stamp = cm.stamp) THEN
				NEW(a); a.pred := curve.pred; a.succ := curve;
				Figures.AddAction(cm.fig, a, DoUnlinkCurves)
			END
		END
	END ControlCurve;
	
	PROCEDURE DoReverseCurve (fig: Figures.Figure; fa: Figures.Action; stamp: LONGINT; undo: BOOLEAN);
		VAR curve, succ: Curve; ref, next: Figures.Reference;
	BEGIN
		curve := fa(Action).curve;
		ref := curve.first; curve.first := curve.last; curve.last := ref;
		WHILE ref # NIL DO
			next := ref.next; ref.next := ref.prev; ref.prev := ref.next;
			ref := next
		END;
		succ := curve.succ; curve.succ := curve.pred; curve.pred := succ;
		curve.stamp := stamp
	END DoReverseCurve;
	
	PROCEDURE ReverseCurve (curve: Curve; fig: Figures.Figure);
		VAR a: Action;
	BEGIN
		IF (curve.pred # NIL) & ~curve.pred.sel THEN
			SplitPath(curve.pred, curve, NIL, fig)
		END;
		IF (curve.succ # NIL) & ~curve.succ.sel THEN
			SplitPath(curve, curve.succ, NIL, fig)
		END;
		NEW(a); a.curve := curve;
		Figures.AddAction(fig, a, DoReverseCurve)
	END ReverseCurve;
	
	PROCEDURE CopyCurve* (VAR msg: Objects.CopyMsg; from, to: Curve);
	BEGIN
		Figures.CopyContainer(msg, from, to);
		to.class := from.class;
		LeoPens.CopyRef(msg, from.stroke, to.stroke);
		to.dx0 := from.dx0; to.dy0 := from.dy0; to.dx1 := from.dx1; to.dy1 := from.dy1;
		to.len := from.len
	END CopyCurve;
	
	PROCEDURE HandleCurve* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR curve, copy: Curve; ref: Figures.Reference; ver: LONGINT;
	BEGIN
		curve := obj(Curve);
		IF msg IS Figures.ShapeMsg THEN
			IF msg IS Figures.SelectMsg THEN
				SelectCurve(curve, msg(Figures.SelectMsg))
			ELSIF msg IS Figures.LocateMsg THEN
				LocateCurve(curve, msg(Figures.LocateMsg))
			ELSIF msg IS Figures.DrawMsg THEN
				WITH msg: Figures.DrawMsg DO
					RenderCurve(curve, msg);
					RenderSelMarker(curve, msg);
					IF curve.sel OR (curve.cont # NIL) & (curve.cont IS Path) & curve.cont.sel THEN
						Figures.HandleRefs(curve, msg)
					END
				END
			ELSIF msg IS Figures.ValidateMsg THEN
				Figures.HandleRefs(curve, msg);
				IF msg.stamp = curve.stamp THEN
					WITH msg: Figures.ValidateMsg DO
						Figures.UpdateShapeRect(curve, msg.fig, msg.mat);
						ValidateCurve(curve);
						Figures.HandleShape(curve, msg)
					END
				END
			ELSIF msg IS Figures.ControlMsg THEN
				ControlCurve(curve, msg(Figures.ControlMsg))
			ELSIF msg IS Figures.PriorityMsg THEN
				WITH msg: Figures.PriorityMsg DO
					IF (msg.id = Figures.Reverse) & curve.sel THEN
						ReverseCurve(curve, msg.fig)
					END
				END
			ELSIF msg IS Figures.TransformMsg THEN
				IF (msg(Figures.TransformMsg).id = Figures.Apply) & (msg.stamp = curve.stamp) THEN
					ref := curve.first;
					WHILE ref # NIL DO ref.shape.stamp := msg.stamp; ref := ref.next END
				END;
				Figures.HandleContainer(curve, msg)
			ELSE
				Figures.HandleContainer(curve, msg)
			END
		ELSIF msg IS Objects.LinkMsg THEN
			WITH msg: Objects.LinkMsg DO
				LeoPens.LinkRef(msg, "StrokePen", TRUE, curve.stroke);
				Figures.HandleContainer(curve, msg)
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # curve.stamp THEN
					NEW(copy); curve.dlink := copy; curve.stamp := msg.stamp;
					CopyCurve(msg, curve, copy)
				END;
				msg.obj := curve.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			IF curve.stroke # NIL THEN Figures.Forward(curve, curve.stroke, msg) END;
			Figures.HandleContainer(curve, msg)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				Figures.HandleContainer(curve, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					LeoPens.WriteRef(msg.R, curve.lib, curve.stroke);
					Gadgets.WriteRef(msg.R, curve.lib, curve.pred);
					Gadgets.WriteRef(msg.R, curve.lib, curve.succ)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver >= 1 THEN
						LeoPens.ReadRef(msg.R, curve.lib, curve.stroke);
						Gadgets.ReadRef(msg.R, curve.lib, obj);
						IF (obj # NIL) & (obj IS Curve) THEN curve.pred := obj(Curve) END;
						Gadgets.ReadRef(msg.R, curve.lib, obj);
						IF (obj # NIL) & (obj IS Curve) THEN curve.succ := obj(Curve) END;
						ValidateCurve(curve)
					END
				END
			END
		ELSE
			Figures.HandleContainer(curve, msg)
		END
	END HandleCurve;
	
	PROCEDURE InitCurve* (curve: Curve; class: CurveClass; first, last: Figures.Reference; stroke: GfxPens.Pen);
	BEGIN
		curve.class := class; curve.stroke := stroke;
		IF (first # last) & (first.shape = last.shape) THEN
			curve.pred := curve; curve.succ := curve
		ELSE
			curve.pred := NIL; curve.succ := NIL
		END;
		curve.first := first; curve.last := last;
		WHILE first # NIL DO first.shape.cont := curve; first := first.next END;
		ValidateCurve(curve)
	END InitCurve;
	
	PROCEDURE Append* (curve: Curve; p: Point);
		VAR ref: Figures.Reference;
	BEGIN
		NEW(ref); ref.shape := p; p.cont := curve;
		IF curve.succ # NIL THEN	(* closed subpath => insert before last point *)
			ref.prev := curve.last.prev; ref.next := curve.last;
			ref.prev.next := ref; ref.next.prev := ref
		ELSE
			ref.prev := curve.last; curve.last.next := ref; curve.last := ref
		END
	END Append;
	
	
	(**--- Paths ---**)
	
	PROCEDURE ValidatePath* (path: Path);
		VAR ref: Figures.Reference; curve: Curve;
	BEGIN
		Figures.ValidateContainer(path);
		ref := path.first;
		WHILE ref # NIL DO
			curve := ref.shape(Curve);
			IF (curve.pred = NIL) OR (ref.prev = NIL) OR (curve.pred # ref.prev.shape) THEN
				curve.boff := 0
			ELSE
				curve.boff := curve.pred.boff + curve.pred.len
			END;
			ref := ref.next
		END;
		ref := path.last;
		WHILE ref # NIL DO
			curve := ref.shape(Curve);
			IF (curve.succ = NIL) OR (ref.next = NIL) OR (curve.succ # ref.next.shape) THEN
				curve.eoff := 0
			ELSE
				curve.eoff := curve.succ.eoff - curve.succ.len
			END;
			ref := ref.prev
		END
	END ValidatePath;
	
	PROCEDURE LocatePath (path: Path; VAR lm: Figures.LocateMsg);
		VAR shapes: Figures.Shape; ref: Figures.Reference; dm: Figures.DrawMsg; curve: Curve;
	BEGIN
		IF lm.stamp # path.stamp THEN
			path.stamp := lm.stamp;
			IF (lm.llx <= path.urx) & (path.llx <= lm.urx) & (lm.lly <= path.ury) & (path.lly <= lm.ury) THEN
				IF lm.id = Figures.Inside THEN
					IF (lm.llx <= path.llx) & (path.urx <= lm.urx) & (lm.lly <= path.lly) & (path.ury <= lm.ury) THEN
						path.slink := lm.shapes; lm.shapes := path
					ELSE
						Figures.HandleRefs(path, lm)
					END
				ELSIF lm.id = Figures.Overlap THEN
					shapes := lm.shapes;
					Figures.HandleRefs(path, lm);
					IF (lm.shapes # shapes) & ~path.sel THEN
						lm.shapes := path; path.slink := shapes
					ELSIF (lm.shapes = shapes) & (path.fill # NIL) THEN	(* check if rect overlaps path interior *)
						Recorder.do.begin(Recorder, NIL);
						ref := path.first; dm.id := Figures.Print; dm.all := TRUE;
						WHILE ref # NIL DO
							curve := ref.shape(Curve);
							curve.class.render(curve, Recorder, dm);
							ref := ref.next
						END;
						Recorder.do.end(Recorder);
						IF GfxPaths.InPath(lm.llx, lm.lly, lm.urx, lm.ury, Recorder.path, FALSE) THEN
							lm.shapes := path; path.slink := shapes
						END
					END
				ELSIF lm.id = Figures.Project THEN
					Figures.HandleRefs(path, lm)
				END
			END
		END
	END LocatePath;
	
	PROCEDURE DrawPath (path: Path; VAR dm: Figures.DrawMsg);
		VAR pen: GfxPens.Pen; ref: Figures.Reference; curve: Curve;
	BEGIN
		IF (dm.llx <= path.urx) & (path.llx <= dm.urx) & (dm.lly <= path.ury) & (path.lly <= dm.ury) THEN
			IF dm.all & (path.fill # NIL) THEN	(* fill path interior *)
				pen := path.fill;
				pen.do.begin(pen, dm.ctxt);
				ref := path.first;
				WHILE ref # NIL DO
					curve := ref.shape(Curve);
					IF (curve.pred # NIL) & (curve.succ # NIL) THEN
						curve.class.render(curve, pen, dm)
					END;
					ref := ref.next
				END;
				pen.do.end(pen)
			END;
			Figures.HandleRefs(path, dm)
		END
	END DrawPath;
	
	PROCEDURE ControlPath (path: Path; VAR cm: Figures.ControlMsg);
		VAR p: Point; llx, lly, urx, ury, px, py: REAL; cref, pref, prev, next: Figures.Reference; curve: Curve; stamp: LONGINT;
		
		PROCEDURE allCurves (obj: Objects.Object): BOOLEAN;
		BEGIN
			WHILE obj # NIL DO
				IF ~(obj IS Curve) THEN RETURN FALSE END;
				obj := obj.slink
			END;
			RETURN TRUE
		END allCurves;
		
	BEGIN
		IF cm.id = Figures.Consume THEN
			IF cm.dest # path THEN
				Figures.HandleRefs(path, cm)
			END;
			IF cm.dest = path THEN
				IF allCurves(cm.shapes) THEN
					Figures.HandleContainer(path, cm)
				ELSIF (cm.shapes IS Path) & (cm.shapes.slink = NIL) THEN
					JoinPaths(path, cm.shapes(Path), cm.fig)
				ELSIF (cm.shapes IS Point) & (cm.shapes.slink = NIL) THEN
					p := cm.shapes(Point); llx := p.x-1; lly := p.y-1; urx := p.x+1; ury := p.y+1;
					cref := path.last;
					WHILE (cref # NIL) & (cm.dest = path) DO
						curve := cref.shape(Curve);
						pref := curve.last;
						WHILE (pref # NIL) & (cm.dest = path) DO
							p := pref.shape(Point);
							IF (llx <= p.x) & (p.x <= urx) & (lly <= p.y) & (p.y <= ury) THEN cm.dest := p END;
							pref := pref.prev
						END;
						IF cm.dest = path THEN
							curve.class.locate(curve, llx, lly, urx, ury, prev, next, px, py);
							IF (prev # NIL) OR (next # NIL) THEN
								cm.dest := curve
							END
						END
					END;
					IF (cm.dest = path) & (cm.shapes(Point).cont = NIL) THEN
						curve := path.last.shape(Curve); cm.dest := curve
					END;
					IF cm.dest # path THEN
						Figures.Forward(path, curve, cm)
					END
				END
			END
		ELSIF (cm.id = Figures.Remove) & (cm.stamp # path.stamp) THEN
			Figures.HandleContainer(path, cm);
			stamp := path.stamp; path.stamp := cm.stamp;
			cref := path.first;
			WHILE cref # NIL DO
				IF cref.shape.stamp = cm.stamp THEN
					curve := cref.shape(Curve);
					IF curve.pred # NIL THEN SplitPath(curve.pred, curve, NIL, cm.fig) END;
					IF curve.succ # NIL THEN SplitPath(curve, curve.succ, NIL, cm.fig) END
				ELSE
					path.stamp := stamp	(* path is only deleted if all its curves are *)
				END;
				cref := cref.next
			END
		END
	END ControlPath;
	
	PROCEDURE CopyPath (VAR msg: Objects.CopyMsg; from, to: Path);
		VAR cm: Objects.CopyMsg; fref, tref: Figures.Reference; fc, tc: Curve;
	BEGIN
		Figures.CopyContainer(msg, from, to);
		LeoPens.CopyRef(msg, from.fill, to.fill);
		cm.stamp := msg.stamp; cm.id := Objects.shallow;	(* use identical stamp to link to already copied curves *)
		fref := from.first; tref := to.first;
		WHILE fref # NIL DO
			fc := fref.shape(Curve); tc := tref.shape(Curve);
			IF fc.pred # NIL THEN
				fc.pred.handle(fc.pred, cm);
				tc.pred := cm.obj(Curve)
			END;
			IF fc.succ # NIL THEN
				fc.succ.handle(fc.succ, cm);
				tc.succ := cm.obj(Curve)
			END;
			tc.boff := fc.boff; tc.eoff := fc.eoff;
			fref := fref.next; tref := tref.next
		END
	END CopyPath;
	
	PROCEDURE ReadCurves (VAR r: Files.Rider; path: Path);
		VAR
			n, i, m: LONGINT; key: INTEGER; name: ARRAY 64 OF CHAR; obj: Objects.Object;
			cv: ARRAY 64 OF Curve; succ, pred, last: ARRAY 64 OF LONGINT; ref: Figures.Reference; curve: Curve;
	BEGIN
		(* compatibility code *)
		Files.ReadNum(r, n);
		i := 0;
		WHILE i < n DO
			Files.ReadInt(r, key);
			Objects.GetName(path.lib.dict, key, name);
			IF (name = "LeoPaths.InitArcClass") OR (name = "LeoPaths.NewArcClass") THEN
				obj := Gadgets.CreateObject("LeoPaths.NewArc")
			ELSIF (name = "LeoPaths.InitBezierClass") OR (name = "LeoPaths.NewBezierClass") THEN
				obj := Gadgets.CreateObject("LeoPaths.NewBezier")
			ELSIF (name = "LeoPaths.InitSplineClass") OR (name = "LeoPaths.NewSplineClass") THEN
				obj := Gadgets.CreateObject("LeoPaths.NewSpline")
			ELSE
				obj := Gadgets.CreateObject("LeoPaths.NewPolygon")
			END;
			cv[i] := obj(Curve);
			LeoPens.ReadRef(r, path.lib, cv[i].stroke);
			Files.ReadNum(r, succ[i]);
			Files.ReadNum(r, pred[i]);
			Files.ReadNum(r, last[i]);
			INC(i)
		END;
		cv[n] := NIL;
		i := 0; ref := path.first; m := 0;
		WHILE i < n DO
			curve := cv[i];
			curve.pred := cv[pred[i]]; curve.succ := cv[succ[i]];
			curve.first := ref; ref.prev := NIL;
			WHILE m < last[i] DO ref := ref.next; INC(m) END;
			curve.last := ref; ref := ref.next; curve.last.next := NIL;
			IF curve.succ # NIL THEN	(* need to create new first ref for successor *)
				NEW(ref.prev); ref.prev.next := ref; ref := ref.prev; ref.shape := curve.last.shape
			END;
			INC(i);
			curve.slink := cv[i]
		END;
		Figures.MakeRefs(cv[0], path.first, path.last)
	END ReadCurves;
	
	PROCEDURE HandlePath* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR path, copy: Path; ref: Figures.Reference; ver: LONGINT;
	BEGIN
		path := obj(Path);
		IF msg IS Figures.ShapeMsg THEN
			IF msg IS Figures.LocateMsg THEN
				LocatePath(path, msg(Figures.LocateMsg))
			ELSIF msg IS Figures.DrawMsg THEN
				DrawPath(path, msg(Figures.DrawMsg))
			ELSIF msg IS Figures.ValidateMsg THEN
				Figures.HandleRefs(path, msg);
				IF msg.stamp = path.stamp THEN
					WITH msg: Figures.ValidateMsg DO
						IF path.fill # NIL THEN
							Figures.UpdateShapeRect(path, msg.fig, msg.mat)
						END;
						ValidatePath(path);
						IF path.fill # NIL THEN
							Figures.UpdateShapeRect(path, msg.fig, msg.mat)
						END;
						path.cont.stamp := msg.stamp
					END
				END
			ELSIF msg IS Figures.ControlMsg THEN
				ControlPath(path, msg(Figures.ControlMsg))
			ELSIF msg IS Figures.TransformMsg THEN
				IF (msg(Figures.TransformMsg).id = Figures.Apply) & (msg.stamp = path.stamp) THEN
					ref := path.first;
					WHILE ref # NIL DO ref.shape.stamp := path.stamp; ref := ref.next END
				END;
				Figures.HandleContainer(path, msg)
			ELSE
				Figures.HandleContainer(path, msg)
			END
		ELSIF msg IS Objects.AttrMsg THEN
			Figures.HandleGenAttr(msg(Objects.AttrMsg), "LeoPaths.NewPath")
		ELSIF msg IS Objects.LinkMsg THEN
			WITH msg: Objects.LinkMsg DO
				LeoPens.LinkRef(msg, "FillPen", TRUE, path.fill);
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # path.stamp THEN
					NEW(copy); path.dlink := copy; path.stamp := msg.stamp;
					CopyPath(msg, path, copy)
				END;
				msg.obj := path.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			IF path.fill # NIL THEN Figures.Forward(path, path.fill, msg) END;
			Figures.HandleContainer(path, msg)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				Figures.HandleContainer(path, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 2);
					LeoPens.WriteRef(msg.R, path.lib, path.fill)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver >= 1 THEN
						LeoPens.ReadRef(msg.R, path.lib, path.fill)
					END;
					IF ver = 1 THEN	(* convert old style path *)
						ReadCurves(msg.R, path)
					END
				END
			END
		END
	END HandlePath;
	
	PROCEDURE InitPath* (path: Path; curve: Curve; fill: GfxPens.Pen);
	BEGIN
		Figures.InitContainer(path);
		path.handle := HandlePath;
		IF curve # NIL THEN
			NEW(path.first); path.first.shape := curve; curve.cont := path; path.last := path.first;
			Figures.ValidateContainer(path)
		END;
		path.fill := fill
	END InitPath;
	
	PROCEDURE NewPath*;
		VAR path: Path;
	BEGIN
		NEW(path); InitPath(path, NIL, NIL);
		Objects.NewObj := path
	END NewPath;
	
	
	(*--- Tool Routines ---*)
	
	PROCEDURE DrawCross (x, y: INTEGER);
	BEGIN
		DEC(x, 8); DEC(y, 8);
		Effects.OpenCursor(x, y, 17, 17);
		Display.CopyPattern(Display3.textbackC, CrossBG, x, y, Display.paint);
		Display.CopyPattern(Display3.black, CrossFG, x, y, Display.paint)
	END DrawCross;
	
	PROCEDURE FadeCross (x, y: INTEGER);
	BEGIN
		Effects.CloseCursor
	END FadeCross;
	
	PROCEDURE InitCross;
		VAR p: ARRAY 17 OF SET; i: LONGINT;
	BEGIN
		p[0] := {}; p[8] := {1..7, 9..15}; p[16] := {};
		FOR i := 1 TO 7 DO p[i] := {8} END;
		FOR i := 9 TO 15 DO p[i] := {8} END;
		CrossFG := Display.NewPattern(17, 17, p);
		p[0] := {7..9}; p[7] := {0..7, 9..16}; p[8] := {0, 16}; p[9] := {0..7, 9..16}; p[16] := {7..9};
		FOR i := 1 TO 6 DO p[i] := {7, 9} END;
		FOR i := 10 TO 15 DO p[i] := {7, 9} END;
		CrossBG := Display.NewPattern(17, 17, p);
		Cross.Draw := DrawCross; Cross.Fade := FadeCross
	END InitCross;
	
	PROCEDURE GetPointPair (x, y: REAL; VAR first, last: Figures.Reference; VAR p: Point);
	BEGIN
		NEW(p); InitPoint(p, x, y);
		NEW(first); first.shape := p;
		NEW(p); InitPoint(p, x, y);
		NEW(last); last.shape := p;
		first.next := last; last.prev := first;
		IF ClosedCurve.val THEN
			NEW(last.next); last.next.prev := last; last := last.next;
			last.shape := first.shape
		END
	END GetPointPair;
	
	PROCEDURE FillPen (): GfxPens.Pen;
	BEGIN
		IF ClosedCurve.val THEN
			RETURN LeoPens.Filler
		ELSE
			RETURN NIL
		END
	END FillPen;
	
	PROCEDURE DragPoint (frame: LeoFrames.Frame; fx, fy: INTEGER; curve: Curve; p: Point; px, py: REAL; VAR keys: SET);
		VAR fig: Figures.Figure; dm: Figures.DrawMsg; mx, my, x, y: INTEGER; mkeys: SET;
	BEGIN
		fig := frame.obj(Figures.Figure);
		Oberon.FadeCursor(Oberon.Mouse);
		dm.fig := fig; dm.id := Figures.Full; dm.all := TRUE; dm.ctxt := LeoFrames.DragCtxt; dm.mat := dm.ctxt.ctm;
		Gfx.GetClipRect(dm.ctxt, dm.llx, dm.lly, dm.urx, dm.ury);
		curve.handle(curve, dm);
		mx := -1; my := -1; mkeys := keys;
		Input.Mouse(keys, x, y);
		Oberon.DrawCursor(Oberon.Mouse, Cross, x, y);
		WHILE keys = mkeys DO
			IF (x # mx) OR (y # my) THEN
				Oberon.FadeCursor(Oberon.Mouse);
				curve.handle(curve, dm);
				LeoFrames.PixelToPoint(frame, x - fx, y - fy, p.x, p.y);
				LeoFrames.AlignPoint(frame, px, py, p.x, p.y);
				curve.handle(curve, dm);
				Oberon.DrawCursor(Oberon.Mouse, Cross, x, y);
				mx := x; my := y
			END;
			Input.Mouse(keys, x, y)
		END;
		p.llx := p.x; p.lly := p.y; p.urx := p.x; p.ury := p.y;
		Oberon.FadeCursor(Oberon.Mouse);
		curve.handle(curve, dm)
	END DragPoint;
	
	PROCEDURE HandleTool (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR frame: LeoFrames.Frame;
	BEGIN
		frame := obj(LeoFrames.Frame);
		IF msg IS Oberon.InputMsg THEN
			WITH msg: Oberon.InputMsg DO
				IF msg.id = Oberon.track THEN
					IF msg.keys = {ML} THEN
						Track(frame, msg)
					ELSIF msg.keys = {} THEN
						Oberon.DrawCursor(Oberon.Mouse, Marker, msg.X, msg.Y);
						msg.res := 0
					ELSE
						LeoFrames.HandleTool(frame, msg)
					END
				ELSE
					LeoFrames.HandleTool(frame, msg)
				END
			END
		ELSE
			LeoFrames.HandleTool(frame, msg)
		END
	END HandleTool;
	
	
	(**--- Polygons ---**)
	
	PROCEDURE PolygonLength (poly: Curve): REAL;
		VAR len, dx, dy: REAL; ref: Figures.Reference; p1, p0: Point;
	BEGIN
		len := 0;
		ref := poly.first; p1 := ref.shape(Point);
		WHILE ref # poly.last DO
			p0 := p1;
			ref := ref.next; p1 := ref.shape(Point);
			dx := p1.x - p0.x; dy := p1.y - p0.y;
			len := len + Math.sqrt(dx * dx + dy * dy)
		END;
		RETURN len
	END PolygonLength;
	
	PROCEDURE RenderPolygon (poly: Curve; pen: GfxPens.Pen; VAR dm: Figures.DrawMsg);
		VAR ref: Figures.Reference; p0, p1, p2: Point; all: BOOLEAN;
	BEGIN
		ref := poly.first; p0 := ref.shape(Point);
		ref := ref.next; p1 := ref.shape(Point);
		all := dm.all OR (poly.stamp = dm.stamp);
		IF all OR (p0.stamp = dm.stamp) OR (p1.stamp = dm.stamp) THEN
			IF poly.pred = NIL THEN pen.do.enter(pen, p0.x, p0.y, 0, 0, 0)
			ELSE pen.do.enter(pen, p0.x, p0.y, poly.pred.dx1, poly.pred.dy1, poly.boff)
			END;
			pen.do.line(pen, p1.x, p1.y)
		END;
		ref := ref.next;
		WHILE ref # NIL DO
			p2 := ref.shape(Point);
			IF all THEN
				pen.do.line(pen, p2.x, p2.y)
			ELSIF p1.stamp = dm.stamp THEN
				pen.do.line(pen, p2.x, p2.y)
			ELSIF p2.stamp = dm.stamp THEN
				IF p0.stamp # dm.stamp THEN
					pen.do.enter(pen, p1.x, p1.y, p1.x - p0.x, p1.y - p0.y, 0)	(* offset? *)
				END;
				pen.do.line(pen, p2.x, p2.y)
			ELSIF p0.stamp = dm.stamp THEN
				pen.do.exit(pen, p2.x - p1.x, p2.y - p1.y, 0)	(* offset? *)
			END;
			p0 := p1; p1 := p2; ref := ref.next
		END;
		IF all OR (p0.stamp = dm.stamp) OR (p1.stamp = dm.stamp) THEN
			IF poly.succ = NIL THEN pen.do.exit(pen, 0, 0, 0)
			ELSE pen.do.exit(pen, poly.succ.dx0, poly.succ.dy0, poly.eoff)
			END
		END
	END RenderPolygon;
	
	PROCEDURE LocatePolygon (poly: Curve; llx, lly, urx, ury: REAL; VAR prev, next: Figures.Reference; VAR px, py: REAL);
		VAR ref: Figures.Reference; p, q: Point;
	BEGIN
		prev := NIL; next := NIL;
		ref := poly.last; p := ref.shape(Point);
		WHILE ref # poly.first DO
			q := p; ref := ref.prev; p := ref.shape(Point);
			IF OnLine(p.x, p.y, q.x, q.y, llx, lly, urx, ury, px, py) THEN
				prev := ref; next := ref.next;
				RETURN
			END
		END
	END LocatePolygon;
	
	PROCEDURE InitPolygonClass;
	BEGIN
		NEW(PolygonClass);
		PolygonClass.length := PolygonLength;
		PolygonClass.render := RenderPolygon; PolygonClass.locate := LocatePolygon;
		PolygonClass.insert := InsertInCurve; PolygonClass.split := SplitCurve
	END InitPolygonClass;
	
	PROCEDURE HandlePolygon* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
	BEGIN
		IF msg IS Objects.AttrMsg THEN
			Figures.HandleGenAttr(msg(Objects.AttrMsg), "LeoPaths.NewPolygon")
		END;
		HandleCurve(obj, msg)
	END HandlePolygon;
	
	PROCEDURE NewPolygon*;
		VAR poly: Curve;
	BEGIN
		NEW(poly); poly.handle := HandlePolygon; poly.class := PolygonClass;
		Objects.NewObj := poly
	END NewPolygon;
	
	PROCEDURE TrackPolygon (frame: LeoFrames.Frame; VAR msg: Oberon.InputMsg);
		VAR fx, fy, mx, my: INTEGER; px, py: REAL; first, last: Figures.Reference; p: Point; poly: Curve; keysum, keys: SET; path: Path;
	BEGIN
		fx := msg.x + frame.X; fy := msg.y + frame.Y;
		LeoFrames.PixelToPoint(frame, msg.X - fx, msg.Y - fy, px, py);
		LeoFrames.AlignPoint(frame, px, py, px, py);
		GetPointPair(px, py, first, last, p);
		NEW(poly); InitCurve(poly, PolygonClass, first, last, LeoPens.Stroker); poly.handle := HandlePolygon; poly.sel := TRUE;
		LeoFrames.ResetDragCtxt(frame, fx, fy);
		keysum := msg.keys; keys := msg.keys;
		REPEAT
			DragPoint(frame, fx, fy, poly, p, px, py, keys);
			keysum := keysum + keys;
			IF (keys = {ML, MM}) & (keysum # {ML, MM, MR}) THEN
				DragPoint(frame, fx, fy, poly, p, px, py, keys);
				keysum := keysum + keys;
				px := p.x; py := p.y;
				NEW(p); InitPoint(p, px, py);
				Append(poly, p)
			END
		UNTIL keys = {};
		IF keysum # {ML, MM, MR} THEN
			ValidateCurve(poly);
			IF ClosedCurve.val THEN
				NEW(path); InitPath(path, poly, FillPen());
				LeoFrames.Integrate(frame.obj(Figures.Figure), NIL, path)
			ELSE
				LeoFrames.Integrate(frame.obj(Figures.Figure), NIL, poly)
			END
		END;
		Input.Mouse(keys, mx, my);
		Oberon.DrawCursor(Oberon.Mouse, Cross, mx, my);
		msg.res := 0
	END TrackPolygon;
	
	PROCEDURE SetPolygonTool*;
	BEGIN
		Track := TrackPolygon; Marker := Cross;
		LeoFrames.SetTool(HandleTool)
	END SetPolygonTool;
	
	
	(**--- Arcs ---**)
	
	PROCEDURE RenderArc (arc: Curve; pen: GfxPens.Pen; VAR dm: Figures.DrawMsg);
		VAR ref: Figures.Reference; p0, p1, p2, p3, p4: Point; all: BOOLEAN;
	BEGIN
		ref := arc.first; p0 := ref.shape(Point);
		ref := ref.next; p1 := ref.shape(Point);
		IF ref = arc.last THEN
			RenderPolygon(arc, pen, dm);
			RETURN
		END;
		ref := ref.next; p2 := ref.shape(Point);
		all := dm.all OR (arc.stamp = dm.stamp);
		IF all OR (p0.stamp = dm.stamp) OR (p1.stamp = dm.stamp) OR (p2.stamp = dm.stamp) THEN
			IF arc.pred = NIL THEN pen.do.enter(pen, p0.x, p0.y, 0, 0, 0)
			ELSE pen.do.enter(pen, p0.x, p0.y, arc.pred.dx1, arc.pred.dy1, arc.boff)
			END;
			pen.do.arc(pen, p2.x, p2.y, p0.x + p2.x - p1.x, p0.y + p2.y - p1.y, p0.x, p0.y, p2.x, p2.y)
		END;
		ref := ref.next;
		WHILE ref # NIL DO
			p3 := ref.shape(Point); ref := ref.next;
			IF ref = NIL THEN
				IF all THEN
					pen.do.line(pen, p3.x, p3.y)
				ELSIF p2.stamp = dm.stamp THEN
					pen.do.line(pen, p3.x, p3.y)
				ELSIF p3.stamp = dm.stamp THEN
					IF (p0.stamp # dm.stamp) & (p1.stamp # dm.stamp) THEN
						pen.do.enter(pen, p2.x, p2.y, p2.x - p1.x, p2.y - p1.y, 0)	(* offset? *)
					END;
					pen.do.line(pen, p3.x, p3.y)
				ELSIF (p0.stamp = dm.stamp) OR (p1.stamp = dm.stamp) THEN
					pen.do.exit(pen, p3.x - p2.x, p3.y - p2.y, 0)	(* offset? *)
				END;
				p0 := p2; p1 := p2; p2 := p3
			ELSE
				p4 := ref.shape(Point); ref := ref.next;
				IF all THEN
					pen.do.arc(pen, p4.x, p4.y, p2.x + p4.x - p3.x, p2.y + p4.y - p3.y, p2.x, p2.y, p4.x, p4.y)
				ELSIF p2.stamp = dm.stamp THEN
					pen.do.arc(pen, p4.x, p4.y, p2.x + p4.x - p3.x, p2.y + p4.y - p3.y, p2.x, p2.y, p4.x, p4.y)
				ELSIF (p3.stamp = dm.stamp) OR (p4.stamp = dm.stamp) THEN
					IF (p0.stamp # dm.stamp) & (p1.stamp # dm.stamp) THEN
						pen.do.enter(pen, p2.x, p2.y, p2.x - p1.x, p2.y - p1.y, 0)	(* offset? *)
					END;
					pen.do.arc(pen, p4.x, p4.y, p2.x + p4.x - p3.x, p2.y + p4.y - p3.y, p2.x, p2.y, p4.x, p4.y)
				ELSIF (p0.stamp = dm.stamp) OR (p1.stamp = dm.stamp) THEN
					pen.do.exit(pen, p3.x - p2.x, p3.y - p2.y, 0)	(* offset? *)
				END;
				p0 := p2; p1 := p3; p2 := p4
			END
		END;
		IF all OR (p0.stamp = dm.stamp) OR (p1.stamp = dm.stamp) OR (p2.stamp = dm.stamp) THEN
			IF arc.succ = NIL THEN pen.do.exit(pen, 0, 0, 0)
			ELSE pen.do.exit(pen, arc.succ.dx0, arc.succ.dy0, arc.eoff)
			END
		END
	END RenderArc;
	
	PROCEDURE DrawArc (arc: Curve; VAR dm: Figures.DrawMsg);
		VAR ref: Figures.Reference;
	BEGIN
		RenderCurve(arc, dm);
		RenderSelMarker(arc, dm);
		IF arc.sel OR (arc.cont # NIL) & (arc.cont IS Path) & arc.cont.sel THEN
			ref := arc.first;
			LOOP
				IF dm.all OR (ref.shape.stamp = dm.stamp) THEN
					RenderPoint(ref.shape(Point), dm.ctxt, dm.id, Gfx.Black)
				END;
				ref := ref.next;
				IF ref = NIL THEN EXIT END;
				IF (dm.id = Figures.Full) & (ref # arc.last) & (dm.all OR (ref.shape.stamp = dm.stamp)) THEN
					RenderPoint(ref.shape(Point), dm.ctxt, Figures.Full, Gfx.DGrey);
					ref := ref.next
				END
			END
		END
	END DrawArc;
	
	PROCEDURE LocateArc (arc: Curve; llx, lly, urx, ury: REAL; VAR prev, next: Figures.Reference; VAR px, py: REAL);
		VAR ref: Figures.Reference; p0, p1, p2: Point;
	BEGIN
		prev := NIL; next := NIL;
		ref := arc.first; p0 := ref.shape(Point);
		REPEAT
			ref := ref.next; p1 := ref.shape(Point);
			IF ref # arc.last THEN
				ref := ref.next; p2 := ref.shape(Point);
				IF OnArc(p0.x, p0.y, p1.x, p1.y, p2.x, p2.y, llx, lly, urx, ury, px, py) THEN
					prev := ref.prev.prev; next := ref
				END;
				p0 := p2
			ELSIF OnLine(p0.x, p0.y, p1.x, p1.y, llx, lly, urx, ury, px, py) THEN
				prev := ref.prev; next := ref
			END
		UNTIL ref = arc.last
	END LocateArc;
	
	PROCEDURE EnumInsertArc (VAR data: GfxPaths.EnumData);
	BEGIN
		WITH data: ArcData DO
			IF data.tracking THEN
				IF (data.rx * (data.y - data.my) - data.ry * (data.x - data.mx) > 0) # data.sense THEN	(* haven't found point yet *)
					data.x0 := data.x; data.y0 := data.y
				ELSE	(* found point *)
					data.x1 := data.x; data.y1 := data.y;
					data.tracking := FALSE
				END
			END
		END
	END EnumInsertArc;
	
	PROCEDURE InsertInArc (arc: Curve; point: Point; prev, next: Figures.Reference; fig: Figures.Figure);
		VAR
			ca: Figures.ControlAction; p0, p1, p2, p: Point; ax, ay, bx, by, dx, dy, x, y: REAL; data: ArcData;
			ref, first, last: Figures.Reference;
	BEGIN
		IF prev.next = next THEN	(* inserting point in line at tail *)
			InsertInCurve(arc, point, prev, next, fig);
			RETURN
		END;
		
		(* remove old control point *)
		ASSERT(prev.next = next.prev);
		NEW(ca); Figures.InitControlAction(ca, Figures.Remove, prev, prev.next, next.prev, next, arc);
		Figures.AddAction(fig, ca, Figures.DoControlAction);
		
		(* find parameters of on-curve intersection *)
		p0 := prev.shape(Point); p1 := prev.next.shape(Point); p2 := next.shape(Point);
		ax := p1.x - p2.x; ay := p1.y - p2.y;
		bx := p1.x - p0.x; by := p1.y - p0.y;
		data.sense := ax * by - ay * bx > 0;
		data.mx := p0.x - ax; data.my := p0.y - ay;
		data.rx := point.x - data.mx; data.ry := point.y - data.my;
		data.x0 := p0.x; data.y0 := p0.y; data.x1 := p2.x; data.y1 := p2.y; data.tracking := TRUE;
		data.x := p0.x; data.y := p0.y;
		GfxPaths.EnumArc(data.mx, data.my, p0.x, p0.y, p2.x, p2.y, p2.x, p2.y, 1, EnumInsertArc, data);
		
		(* create new off-curve points and insert all three points *)
		dx := data.x1 - data.x0; dy := data.y1 - data.y0;
		GfxPaths.IntersectLines(point.x, point.y, dx, dy, p0.x, p0.y, bx, by, x, y);
		NEW(p); InitPoint(p, x, y);
		NEW(first); first.shape := p;
		NEW(ref); ref.shape := point;
		ref.prev := first; first.next := ref;
		GfxPaths.IntersectLines(point.x, point.y, dx, dy, p2.x, p2.y, ax, ay, x, y);
		NEW(p); InitPoint(p, x, y);
		NEW(last); last.shape := p;
		last.prev := ref; ref.next := last;
		NEW(ca); Figures.InitControlAction(ca, Figures.Consume, prev, first, last, next, arc);
		Figures.AddAction(fig, ca, Figures.DoControlAction)
	END InsertInArc;
	
	PROCEDURE InitArcClass;
	BEGIN
		NEW(ArcClass);
		ArcClass.length := CurveLength; ArcClass.render := RenderArc; ArcClass.locate := LocateArc;
		ArcClass.insert := InsertInArc; ArcClass.split := SplitCurve
	END InitArcClass;
	
	PROCEDURE HandleArc* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
	BEGIN
		IF msg IS Figures.DrawMsg THEN
			DrawArc(obj(Curve), msg(Figures.DrawMsg))
		ELSIF msg IS Objects.AttrMsg THEN
			Figures.HandleGenAttr(msg(Objects.AttrMsg), "LeoPaths.NewArc");
			HandleCurve(obj, msg)
		ELSE
			HandleCurve(obj, msg)
		END
	END HandleArc;
	
	PROCEDURE NewArc*;
		VAR arc: Curve;
	BEGIN
		NEW(arc); arc.handle := HandleArc; arc.class := ArcClass;
		Objects.NewObj := arc
	END NewArc;
	
	PROCEDURE TrackArc (frame: LeoFrames.Frame; VAR msg: Oberon.InputMsg);
		VAR 
			fx, fy, mx, my: INTEGER; px, py: REAL; first, last: Figures.Reference; p, q: Point;
			arc: Curve; keysum, keys: SET; path: Path;
	BEGIN
		fx := msg.x + frame.X; fy := msg.y + frame.Y;
		LeoFrames.PixelToPoint(frame, msg.X - fx, msg.Y - fy, px, py);
		LeoFrames.AlignPoint(frame, px, py, px, py);
		GetPointPair(px, py, first, last, p);
		NEW(arc); InitCurve(arc, ArcClass, first, last, LeoPens.Stroker); arc.handle := HandleArc; arc.sel := TRUE;
		q := NIL;
		LeoFrames.ResetDragCtxt(frame, fx, fy);
		keysum := msg.keys; keys := msg.keys;
		REPEAT
			DragPoint(frame, fx, fy, arc, p, px, py, keys);
			keysum := keysum + keys;
			IF (keys = {ML, MM}) & (keysum # {ML, MM, MR}) THEN
				DragPoint(frame, fx, fy, arc, p, px, py, keys);
				keysum := keysum + keys;
				px := p.x; py := p.y;
				IF q # NIL THEN	(* MM interclicked more than once *)
					NEW(p); InitPoint(p, px + (px - q.x), py + (py - q.y));
					Append(arc, p)
				END;
				q := p;
				NEW(p); InitPoint(p, px, py);
				Append(arc, p)
			END
		UNTIL keys = {};
		IF keysum # {ML, MM, MR} THEN
			ValidateCurve(arc);
			IF ClosedCurve.val THEN
				NEW(path); InitPath(path, arc, FillPen());
				LeoFrames.Integrate(frame.obj(Figures.Figure), NIL, path)
			ELSE
				LeoFrames.Integrate(frame.obj(Figures.Figure), NIL, arc)
			END
		END;
		Input.Mouse(keys, mx, my);
		Oberon.DrawCursor(Oberon.Mouse, Cross, mx, my);
		msg.res := 0
	END TrackArc;
	
	PROCEDURE SetArcTool*;
	BEGIN
		Track := TrackArc; Marker := Cross;
		LeoFrames.SetTool(HandleTool)
	END SetArcTool;
	
	
	(**--- Beziers ---**)
	
	PROCEDURE RenderBezier (bezier: Curve; pen: GfxPens.Pen; VAR dm: Figures.DrawMsg);
		VAR ref: Figures.Reference; p0, p1, p2, p3, p4, p5, p6: Point; all: BOOLEAN;
	BEGIN
		ref := bezier.first; p0 := ref.shape(Point);
		ref := ref.next; p1 := ref.shape(Point);
		IF ref = bezier.last THEN
			RenderPolygon(bezier, pen, dm);
			RETURN
		END;
		ref := ref.next; p2 := ref.shape(Point);
		IF ref = bezier.last THEN
			RenderArc(bezier, pen, dm);
			RETURN
		END;
		ref := ref.next; p3 := ref.shape(Point);
		all := dm.all OR (bezier.stamp = dm.stamp);
		IF all OR (p0.stamp = dm.stamp) OR (p1.stamp = dm.stamp) OR (p2.stamp = dm.stamp) OR (p3.stamp = dm.stamp) THEN
			IF bezier.pred = NIL THEN pen.do.enter(pen, p0.x, p0.y, 0, 0, 0)
			ELSE pen.do.enter(pen, p0.x, p0.y, bezier.pred.dx1, bezier.pred.dy1, bezier.boff)
			END;
			pen.do.bezier(pen, p3.x, p3.y, p1.x, p1.y, p2.x, p2.y)
		END;
		ref := ref.next;
		WHILE ref # NIL DO
			p4 := ref.shape(Point); ref := ref.next;
			IF ref = NIL THEN
				IF all THEN
					pen.do.line(pen, p4.x, p4.y)
				ELSIF p3.stamp = dm.stamp THEN
					pen.do.line(pen, p4.x, p4.y)
				ELSIF p4.stamp = dm.stamp THEN
					IF (p0.stamp # dm.stamp) & (p1.stamp # dm.stamp) & (p2.stamp # dm.stamp) THEN
						pen.do.enter(pen, p3.x, p3.y, p3.x - p2.x, p3.y - p2.y, 0)	(* offset? *)
					END;
					pen.do.line(pen, p4.x, p4.y)
				ELSIF (p0.stamp = dm.stamp) OR (p1.stamp = dm.stamp) OR (p2.stamp = dm.stamp) THEN
					pen.do.exit(pen, p4.x - p3.x, p4.y - p3.y, 0)	(* offset? *)
				END;
				p0 := p3; p1 := p3; p2 := p4; p3 := p4
			ELSE
				p5 := ref.shape(Point); ref := ref.next;
				IF ref = NIL THEN
					IF all THEN
						pen.do.arc(pen, p5.x, p5.y, p3.x + p5.x - p4.x, p3.y + p5.y - p4.y, p3.x, p3.y, p5.x, p5.y)
					ELSIF p3.stamp = dm.stamp THEN
						pen.do.arc(pen, p5.x, p5.y, p3.x + p5.x - p4.x, p3.y + p5.y - p4.y, p3.x, p3.y, p5.x, p5.y)
					ELSIF (p4.stamp = dm.stamp) OR (p5.stamp = dm.stamp) THEN
						IF (p0.stamp # dm.stamp) & (p1.stamp # dm.stamp) & (p2.stamp # dm.stamp) THEN
							pen.do.enter(pen, p3.x, p3.y, p3.x - p2.x, p3.y - p2.y, 0)	(* offset *)
						END;
						pen.do.arc(pen, p5.x, p5.y, p3.x + p5.x - p4.x, p3.y + p5.y - p4.y, p3.x, p3.y, p5.x, p5.y)
					ELSIF (p0.stamp = dm.stamp) OR (p1.stamp = dm.stamp) OR (p2.stamp = dm.stamp) THEN
						pen.do.exit(pen, p4.x - p3.x, p4.y - p3.y, 0)	(* offset? *)
					END;
					p0 := p3; p1 := p4; p2 := p4; p3 := p5
				ELSE
					p6 := ref.shape(Point); ref := ref.next;
					IF all THEN
						pen.do.bezier(pen, p6.x, p6.y, p4.x, p4.y, p5.x, p5.y)
					ELSIF p3.stamp = dm.stamp THEN
						pen.do.bezier(pen, p6.x, p6.y, p4.x, p4.y, p5.x, p5.y)
					ELSIF (p4.stamp = dm.stamp) OR (p5.stamp = dm.stamp) OR (p6.stamp = dm.stamp) THEN
						IF (p0.stamp # dm.stamp) & (p1.stamp # dm.stamp) & (p2.stamp # dm.stamp) THEN
							pen.do.enter(pen, p3.x, p3.y, p3.x - p2.x, p3.y - p2.y, 0)	(* offset *)
						END;
						pen.do.bezier(pen, p6.x, p6.y, p4.x, p4.y, p5.x, p5.y)
					ELSIF (p0.stamp = dm.stamp) OR (p1.stamp = dm.stamp) OR (p2.stamp = dm.stamp) THEN
						pen.do.exit(pen, p4.x - p3.x, p4.y - p3.y, 0)	(* offset? *)
					END;
					p0 := p3; p1 := p4; p2 := p5; p3 := p6
				END
			END
		END;
		IF all OR (p0.stamp = dm.stamp) OR (p1.stamp = dm.stamp) OR (p2.stamp = dm.stamp) OR (p3.stamp = dm.stamp) THEN
			IF bezier.succ = NIL THEN pen.do.exit(pen, 0, 0, 0)
			ELSE pen.do.exit(pen, bezier.succ.dx0, bezier.succ.dy0, bezier.eoff)
			END
		END
	END RenderBezier;
	
	PROCEDURE DrawBezier (bezier: Curve; VAR dm: Figures.DrawMsg);
		VAR ref: Figures.Reference;
	BEGIN
		RenderCurve(bezier, dm);
		RenderSelMarker(bezier, dm);
		IF bezier.sel OR (bezier.cont # NIL) & (bezier.cont IS Path) & bezier.cont.sel THEN
			ref := bezier.first;
			LOOP
				IF dm.all OR (ref.shape.stamp = dm.stamp) THEN
					RenderPoint(ref.shape(Point), dm.ctxt, dm.id, Gfx.Black)
				END;
				ref := ref.next;
				IF ref = NIL THEN EXIT END;
				IF (dm.id = Figures.Full) & (ref # bezier.last) & (dm.all OR (ref.shape.stamp = dm.stamp)) THEN
					RenderPoint(ref.shape(Point), dm.ctxt, Figures.Full, Gfx.DGrey);
					ref := ref.next;
					IF (dm.id = Figures.Full) & (ref # bezier.last) & (dm.all OR (ref.shape.stamp = dm.stamp)) THEN
						RenderPoint(ref.shape(Point), dm.ctxt, Figures.Full, Gfx.DGrey);
						ref := ref.next
					END
				END
			END
		END
	END DrawBezier;
	
	PROCEDURE LocateBezier (bezier: Curve; llx, lly, urx, ury: REAL; VAR prev, next: Figures.Reference; VAR px, py: REAL);
		VAR ref, r: Figures.Reference; p0, p1, p2, p3: Point;
	BEGIN
		prev := NIL; next := NIL;
		ref := bezier.first; r := ref; p0 := ref.shape(Point);
		REPEAT
			ref := ref.next; p1 := ref.shape(Point);
			IF ref # bezier.last THEN
				ref := ref.next; p2 := ref.shape(Point);
				IF ref # bezier.last THEN
					ref := ref.next; p3 := ref.shape(Point);
					IF OnBezier(p0.x, p0.y, p1.x, p1.y, p2.x, p2.y, p3.x, p3.y, llx, lly, urx, ury, px, py) THEN
						prev := r; next := ref
					END;
					p0 := p3; r := ref
				ELSIF OnArc(p0.x, p0.y, p1.x, p1.y, p2.x, p2.y, llx, lly, urx, ury, px, py) THEN
					prev := ref.prev.prev; next := ref
				END
			ELSIF OnLine(p0.x, p0.y, p1.x, p1.y, llx, lly, urx, ury, px, py) THEN
				prev := ref.prev; next := ref
			END
		UNTIL ref = bezier.last
	END LocateBezier;
	
	PROCEDURE InsertInBezier (bezier: Curve; point: Point; prev, next: Figures.Reference; fig: Figures.Figure);
		VAR
			p: Point; x0, y0, x1, y1, x2, y2, x3, y3, x, y, t, range, xa, ya, xb, yb, xt, yt, xc, yc, xd, yd, d0, d3: REAL;
			ca: Figures.ControlAction; first, ref, last: Figures.Reference;
	BEGIN
		IF prev.next = next THEN	(* inserting point in line at tail *)
			InsertInCurve(bezier, point, prev, next, fig);
			RETURN
		ELSIF prev.next = next.prev THEN	(* inserting point in arc at tail *)
			InsertInArc(bezier, point, prev, next, fig);
			RETURN
		END;
		
		(* find parameter of on-curve intersection *)
		p := prev.shape(Point); x0 := p.x; y0 := p.y;
		p := prev.next.shape(Point); x1 := p.x; y1 := p.y;
		p := next.prev.shape(Point); x2 := p.x; y2 := p.y;
		p := next.shape(Point); x3 := p.x; y3 := p.y;
		x := point.x; y := point.y;
		t := 0.5; range := 0.5;
		LOOP
			SubdivideBezier(t, x0, y0, x1, y1, x2, y2, x3, y3, xa, ya, xb, yb, xt, yt, xc, yc, xd, yd);
			d0 := (ABS(x - x0) + ABS(y - y0)) / (ABS(xt - x0) + ABS(yt - y0));
			d3 := (ABS(x - x3) + ABS(y - y3)) / (ABS(xt - x3) + ABS(yt - y3));
			IF range * (ABS(x3 - x0) + ABS(y3 - y0)) < 0.5 THEN EXIT END;
			range := 0.5*range;
			IF d0 <= d3 THEN
				t := t - range
			ELSE
				t := t + range
			END
		END;
		
		(* remove old off-curve points *)
		NEW(ca); Figures.InitControlAction(ca, Figures.Remove, prev, prev.next, next.prev, next, bezier);
		Figures.AddAction(fig, ca, Figures.DoControlAction);
		
		(* create and insert new off-curve points around new on-curve point *)
		NEW(p); InitPoint(p, xa, ya);
		NEW(first); first.shape := p;
		NEW(p); InitPoint(p, xb, yb);
		NEW(ref); ref.shape := p;
		first.next := ref; ref.prev := first;
		NEW(last); last.shape := point;
		ref.next := last; last.prev := ref; ref := last;
		NEW(p); InitPoint(p, xc, yc);
		NEW(last); last.shape := p;
		ref.next := last; last.prev := ref; ref := last;
		NEW(p); InitPoint(p, xd, yd);
		NEW(last); last.shape := p;
		ref.next := last; last.prev := ref;
		NEW(ca); Figures.InitControlAction(ca, Figures.Consume, prev, first, last, next, bezier);
		Figures.AddAction(fig, ca, Figures.DoControlAction)
	END InsertInBezier;
	
	PROCEDURE InitBezierClass;
	BEGIN
		NEW(BezierClass);
		BezierClass.length := CurveLength; BezierClass.render := RenderBezier; BezierClass.locate := LocateBezier;
		BezierClass.insert := InsertInBezier; BezierClass.split := SplitCurve
	END InitBezierClass;
	
	PROCEDURE HandleBezier* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
	BEGIN
		IF msg IS Figures.DrawMsg THEN
			DrawBezier(obj(Curve), msg(Figures.DrawMsg))
		ELSIF msg IS Objects.AttrMsg THEN
			Figures.HandleGenAttr(msg(Objects.AttrMsg), "LeoPaths.NewBezier");
			HandleCurve(obj, msg)
		ELSE
			HandleCurve(obj, msg)
		END
	END HandleBezier;
	
	PROCEDURE NewBezier*;
		VAR bezier: Curve;
	BEGIN
		NEW(bezier); bezier.handle := HandleBezier; bezier.class := BezierClass;
		Objects.NewObj := bezier
	END NewBezier;
	
	PROCEDURE TrackBezier (frame: LeoFrames.Frame; VAR msg: Oberon.InputMsg);
		VAR
			fx, fy, mx, my: INTEGER; px, py: REAL; first, last: Figures.Reference; p, q, r: Point;
			bezier: Curve; keysum, keys: SET; path: Path;
	BEGIN
		fx := msg.x + frame.X; fy := msg.y + frame.Y;
		LeoFrames.PixelToPoint(frame, msg.X - fx, msg.Y - fy, px, py);
		LeoFrames.AlignPoint(frame, px, py, px, py);
		GetPointPair(px, py, first, last, p);
		NEW(bezier); InitCurve(bezier, BezierClass, first, last, LeoPens.Stroker); bezier.handle := HandleBezier; bezier.sel := TRUE;
		q := NIL; r := NIL;
		LeoFrames.ResetDragCtxt(frame, fx, fy);
		keysum := msg.keys; keys := msg.keys;
		REPEAT
			DragPoint(frame, fx, fy, bezier, p, px, py, keys);
			keysum := keysum + keys;
			IF (keys = {ML, MM}) & (keysum # {ML, MM, MR}) THEN
				DragPoint(frame, fx, fy, bezier, p, px, py, keys);
				keysum := keysum + keys;
				px := p.x; py := p.y;
				IF r # NIL THEN	(* MM interclicked more than twice *)
					NEW(p); InitPoint(p, px + (px - q.x), py + (py - q.y));
					Append(bezier, p);
					q := NIL
				END;
				r := q; q := p;
				NEW(p); InitPoint(p, px, py);
				Append(bezier, p)
			END
		UNTIL keys = {};
		IF keysum # {ML, MM, MR} THEN
			ValidateCurve(bezier);
			IF ClosedCurve.val THEN
				NEW(path); InitPath(path, bezier, FillPen());
				LeoFrames.Integrate(frame.obj(Figures.Figure), NIL, path)
			ELSE
				LeoFrames.Integrate(frame.obj(Figures.Figure), NIL, bezier)
			END
		END;
		Input.Mouse(keys, mx, my);
		Oberon.DrawCursor(Oberon.Mouse, Cross, mx, my);
		msg.res := 0
	END TrackBezier;
	
	PROCEDURE SetBezierTool*;
	BEGIN
		Track := TrackBezier; Marker := Cross;
		LeoFrames.SetTool(HandleTool)
	END SetBezierTool;
	
	
	(**--- Splines ---**)
	
	PROCEDURE ValidateSpline (spline: Curve);
		VAR bw, sx, sy: REAL; s: GfxPaths.Scanner;
	BEGIN
		RecordCurve(spline);
		GfxPaths.GetBox(Recorder.path, spline.llx, spline.lly, spline.urx, spline.ury);
		spline.bw := 0;
		IF spline.stroke # NIL THEN
			Attributes.GetReal(spline.stroke, "BorderWidth", bw);
			spline.bw := bw
		END;
		GfxPaths.Open(s, Recorder.path, 0);
		sx := s.x; sy := s.y;
		GfxPaths.Scan(s);
		IF s.elem = GfxPaths.Line THEN
			spline.dx0 := s.x - sx; spline.dy0 := s.y - sy;
			spline.dx1 := spline.dx0; spline.dy1 := spline.dy0
		ELSIF s.elem = GfxPaths.Arc THEN	(* must be circle *)
			spline.dx0 := s.x2 - sx; spline.dy0 := s.y2 - sy;
			spline.dx1 := spline.dx0; spline.dy1 := spline.dy0
		ELSIF s.elem = GfxPaths.Bezier THEN
			spline.dx0 := s.x1 - sx; spline.dy0 := s.y1 - sy;
			GfxPaths.Scan(s);
			WHILE s.elem = GfxPaths.Bezier DO
				spline.dx1 := s.x - s.x2; spline.dy1 := s.y - s.y2;
				GfxPaths.Scan(s)
			END;
			spline.len := GfxPaths.Length(Recorder.path, 1)
		ELSE
			spline.dx0 := 0; spline.dy0 := 0; spline.dx1 := 0; spline.dy1 := 0;
			spline.len := 0
		END;
		spline.boff := 0; spline.eoff := 0
	END ValidateSpline;
	
	PROCEDURE EnumSplineElem (VAR data: GfxPaths.EnumData);
	BEGIN
		WITH data: SplineData DO
			CASE data.elem OF
			| GfxPaths.Line: data.pen.do.line(data.pen, data.x, data.y);
			| GfxPaths.Arc: data.pen.do.arc(data.pen, data.x, data.y, data.x0, data.y0, data.x1, data.y1, data.x2, data.y2)
			| GfxPaths.Bezier: data.pen.do.bezier(data.pen, data.x, data.y, data.x1, data.y1, data.x2, data.y2)
			END
		END
	END EnumSplineElem;
	
	PROCEDURE RenderSpline (spline: Curve; pen: GfxPens.Pen; VAR dm: Figures.DrawMsg);
		VAR
			ref: Figures.Reference; p: Point; n: LONGINT; x, y: ARRAY GfxPaths.MaxSplinePoints OF REAL;
			data: SplineData;
	BEGIN
		ref := spline.first;
		IF ~dm.all & (spline.stamp # dm.stamp) THEN
			WHILE (ref # NIL) & (ref.shape.stamp # dm.stamp) DO ref := ref.next END
		END;
		IF ref # NIL THEN	(* at least one point is affected => must render complete spline *)
			ref := spline.first; p := ref.shape(Point);
			IF spline.pred = NIL THEN pen.do.enter(pen, p.x, p.y, 0, 0, 0)
			ELSE pen.do.enter(pen, p.x, p.y, spline.pred.dx1, spline.pred.dy1, spline.boff)
			END;
			x[0] := p.x; y[0] := p.y;
			ref := ref.next; n := 1;
			WHILE (n < GfxPaths.MaxSplinePoints) & (ref # NIL) DO
				p := ref.shape(Point);
				IF ABS(x[n-1] - p.x) + ABS(y[n-1] - p.y) > 1.0E-5 THEN
					x[n] := p.x; y[n] := p.y; INC(n)
				END;
				ref := ref.next
			END;
			IF n >= 2 THEN
				data.x := x[0]; data.y := y[0]; data.pen := pen;
				GfxPaths.EnumSpline(x, y, n, spline.succ = spline, EnumSplineElem, data)
			END;
			IF spline.succ = NIL THEN pen.do.exit(pen, 0, 0, 0)
			ELSE pen.do.exit(pen, spline.succ.dx0, spline.succ.dy0, spline.eoff)
			END
		END
	END RenderSpline;
	
	PROCEDURE LocateSpline (spline: Curve; llx, lly, urx, ury: REAL; VAR prev, next: Figures.Reference; VAR px, py: REAL);
		VAR ref: Figures.Reference; p: Point; s: GfxPaths.Scanner; x, y: REAL;
	BEGIN
		prev := NIL; next := NIL;
		RecordCurve(spline);
		ref := spline.first.next; p := ref.shape(Point);	(* next control point *)
		GfxPaths.Open(s, Recorder.path, 0);
		x := s.x; y := s.y;
		GfxPaths.Scan(s);
		WHILE s.elem # GfxPaths.Exit DO
			IF (x = p.x) & (y = p.y) THEN	(* reached next control point *)
				ref := ref.next; p := ref.shape(Point)
			END;
			CASE s.elem OF
			| GfxPaths.Line:
				IF OnLine(x, y, s.x, s.y, llx, lly, urx, ury, px, py) THEN
					prev := ref.prev; next := ref
				END;
				x := s.x; y := s.y
			| GfxPaths.Arc:	(* must be circle *)
				GfxPaths.ProjectToEllipse(s.x1 - s.x0, s.y1 - s.y0, s.x2 - s.x0, s.y2 - s.y0,
					0.5*(llx + urx) - s.x0, 0.5*(lly + ury) - s.y0, px, py);
				px := s.x0 + px; py := s.y0 + py;
				IF (llx <= px) & (px <= urx) & (lly <= py) & (py <= ury) THEN
					prev := ref.prev; next := ref
				END
			| GfxPaths.Bezier:
				IF OnBezier(x, y, s.x1, s.y1, s.x2, s.y2, s.x, s.y, llx, lly, urx, ury, px, py) THEN
					prev := ref.prev; next := ref
				END;
				x := s.x; y := s.y
			END;
			GfxPaths.Scan(s)
		END
	END LocateSpline;
	
	PROCEDURE InitSplineClass;
	BEGIN
		NEW(SplineClass);
		SplineClass.length := CurveLength; SplineClass.render := RenderSpline; SplineClass.locate := LocateSpline;
		SplineClass.insert := InsertInCurve; SplineClass.split := SplitCurve
	END InitSplineClass;
	
	PROCEDURE HandleSpline* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR spline: Curve;
	BEGIN
		IF msg IS Figures.ValidateMsg THEN
			WITH msg: Figures.ValidateMsg DO
				spline := obj(Curve);
				Figures.HandleRefs(spline, msg);
				IF msg.stamp = spline.stamp THEN
					Figures.UpdateShapeRect(spline, msg.fig, msg.mat);
					ValidateSpline(spline);
					Figures.HandleShape(spline, msg)
				END
			END
		ELSIF msg IS Objects.AttrMsg THEN
			Figures.HandleGenAttr(msg(Objects.AttrMsg), "LeoPaths.NewSpline");
			HandleCurve(obj, msg)
		ELSE
			HandleCurve(obj, msg)
		END
	END HandleSpline;
	
	PROCEDURE NewSpline*;
		VAR spline: Curve;
	BEGIN
		NEW(spline); spline.handle := HandleSpline; spline.class := SplineClass;
		Objects.NewObj := spline
	END NewSpline;
	
	PROCEDURE TrackSpline (frame: LeoFrames.Frame; VAR msg: Oberon.InputMsg);
		VAR
			fx, fy, mx, my: INTEGER; px, py: REAL; first, last: Figures.Reference; p: Point; spline: Curve; keysum, keys: SET;
			path: Path;
	BEGIN
		fx := msg.x + frame.X; fy := msg.y + frame.Y;
		LeoFrames.PixelToPoint(frame, msg.X - fx, msg.Y - fy, px, py);
		LeoFrames.AlignPoint(frame, px, py, px, py);
		GetPointPair(px, py, first, last, p);
		NEW(spline); InitCurve(spline, SplineClass, first, last, LeoPens.Stroker); spline.handle := HandleSpline; spline.sel := TRUE;
		LeoFrames.ResetDragCtxt(frame, fx, fy);
		keysum := msg.keys; keys := msg.keys;
		REPEAT
			DragPoint(frame, fx, fy, spline, p, px, py, keys);
			keysum := keysum + keys;
			IF (keys = {ML, MM}) & (keysum # {ML, MM, MR}) THEN
				DragPoint(frame, fx, fy, spline, p, px, py, keys);
				keysum := keysum + keys;
				px := p.x; py := p.y;
				NEW(p); InitPoint(p, px, py);
				Append(spline, p)
			END
		UNTIL keys = {};
		IF keysum # {ML, MM, MR} THEN
			ValidateSpline(spline);
			IF ClosedCurve.val THEN
				NEW(path); InitPath(path, spline, FillPen());
				LeoFrames.Integrate(frame.obj(Figures.Figure), NIL, path)
			ELSE
				LeoFrames.Integrate(frame.obj(Figures.Figure), NIL, spline)
			END
		END;
		Input.Mouse(keys, mx, my);
		Oberon.DrawCursor(Oberon.Mouse, Cross, mx, my);
		msg.res := 0
	END TrackSpline;
	
	PROCEDURE SetSplineTool*;
	BEGIN
		Track := TrackSpline; Marker := Cross;
		LeoFrames.SetTool(HandleTool)
	END SetSplineTool;
	
	
	(**--- Point Tool ---**)
	
	PROCEDURE DrawPoint (x, y: INTEGER);
	BEGIN
		DEC(x, 8); DEC(y, 8);
		Effects.OpenCursor(x, y, 17, 17);
		Display.CopyPattern(Display3.textbackC, PntBG, x, y, Display.paint);
		Display.CopyPattern(Display3.black, PntFG, x, y, Display.paint)
	END DrawPoint;
	
	PROCEDURE FadePoint (x, y: INTEGER);
	BEGIN
		Effects.CloseCursor
	END FadePoint;
	
	PROCEDURE InitPointTool;
		VAR p: ARRAY 17 OF SET; i: LONGINT;
	BEGIN
		p[0] := {}; p[6] := {7..9}; p[7] := {6, 10}; p[8] := {1..6, 10..15}; p[9] := {6, 10}; p[10] := {7..9}; p[16] := {};
		FOR i := 1 TO 5 DO p[i] := {8} END;
		FOR i := 11 TO 15 DO p[i] := {8} END;
		PntFG := Display.NewPattern(17, 17, p);
		p[0] := {7..9}; p[6] := {6, 10}; p[7] := {0..5, 7..9, 11..16}; p[8] := {0, 7, 9, 16}; p[9] := {0..5, 7..9, 11..16}; p[10] := {6, 10}; p[16] := {7..9};
		FOR i := 1 TO 5 DO p[i] := {7, 9} END;
		FOR i := 11 TO 15 DO p[i] := {7, 9} END;
		PntBG := Display.NewPattern(17, 17, p);
		Pnt.Draw := DrawPoint; Pnt.Fade := FadePoint
	END InitPointTool;
	
	PROCEDURE TrackPoint (frame: LeoFrames.Frame; VAR msg: Oberon.InputMsg);
		VAR fx, fy, mx, my, x, y: INTEGER; fig: Figures.Figure;
			target: Figures.Shape;
			x0, y0, s, x1, y1: REAL;
			lm: Figures.LocateMsg;
			p: Point;
			keysum, keys: SET;
			mat: GfxMatrix.Matrix;
	BEGIN
		fx := msg.x + frame.X; fy := msg.y + frame.Y;
		LeoFrames.LocateShapesAt(frame, msg.X - fx, msg.Y - fy, target);
		IF (target # NIL) & ((target IS Curve) OR (target IS Point)) THEN
			fig := frame.obj(Figures.Figure);
			Figures.DisableUpdate(fig);
			Figures.BeginCommand(fig);
			LeoFrames.PixelToPoint(frame, msg.X - fx, msg.Y - fy, x0, y0);
			s := LeoFrames.Tolerance/frame.scale;
			lm.id := Figures.Project; lm.llx := x0 - s; lm.lly := y0 - s; lm.urx := x0 + s; lm.ury := y0 + s; lm.px := x0; lm.py := y0;
			Figures.Forward(frame, fig, lm);
			x0 := lm.px; y0 := lm.py;
			NEW(p); InitPoint(p, x0, y0);
			LeoFrames.Integrate(fig, target, p);
			LeoFrames.ResetDragCtxt(frame, fx, fy);
			Figures.ComputeTrafo(fig, p, GfxMatrix.Identity);
			LeoFrames.ApplyTrafo; LeoFrames.Redraw(fig, p.stamp); LeoFrames.DrawAlignBars(frame, fx, fy, x0, y0);
			keysum := msg.keys; mx := msg.X; my := msg.Y; x1 := x0; y1 := y0;
			REPEAT
				Input.Mouse(keys, x, y);
				keysum := keysum + keys;
				IF (keys # {}) & ((x # mx) OR (y # my)) THEN
					Oberon.FadeCursor(Oberon.Mouse);
					LeoFrames.DrawAlignBars(frame, fx, fy, x1, y1); LeoFrames.Redraw(fig, p.stamp); LeoFrames.ApplyTrafo;
					LeoFrames.PixelToPoint(frame, x - fx + 0.5, y - fy + 0.5, x1, y1);
					LeoFrames.AlignPoint(frame, x0, y0, x1, y1);
					GfxMatrix.Translate(GfxMatrix.Identity, x1 - x0, y1 - y0, mat);
					Figures.ComputeTrafo(fig, p, mat);
					LeoFrames.ApplyTrafo; LeoFrames.Redraw(fig, p.stamp); LeoFrames.DrawAlignBars(frame, fx, fy, x1, y1);
					mx := x; my := y;
					Oberon.DrawCursor(Oberon.Mouse, Pnt, x, y)
				END
			UNTIL keys = {};
			Oberon.FadeCursor(Oberon.Mouse);
			LeoFrames.DrawAlignBars(frame, fx, fy, x1, y1); LeoFrames.Redraw(fig, p.stamp); LeoFrames.ApplyTrafo;
			IF keysum = {ML} THEN
				Figures.CommitTrafo(fig);
				Figures.EndCommand(fig)
			ELSE
				Figures.CancelCommand(fig)
			END;
			Figures.EnableUpdate(fig);
			Oberon.DrawCursor(Oberon.Mouse, Pnt, x, y)
		ELSE
			Oberon.DrawCursor(Oberon.Mouse, Pnt, msg.X, msg.Y)
		END;
		msg.res := 0
	END TrackPoint;
	
	PROCEDURE SetPointTool*;
	BEGIN
		Track := TrackPoint; Marker := Pnt;
		LeoFrames.SetTool(HandleTool)
	END SetPointTool;
	

BEGIN
	InitPointImages;
	NEW(Recorder); GfxPens.InitRecorder(Recorder);
	InitPolygonClass; InitArcClass; InitBezierClass; InitSplineClass;
	Leonardo.GetPublicBool("ClosedCurve", ClosedCurve);
	InitPointTool; InitCross
END LeoPaths.


	(**--- Curve Methods ---**)
	
	PROCEDURE DoRemoveCurve (fig: Figures.Figure; fact: Figures.Action; stamp: LONGINT; undo: BOOLEAN);
		VAR ra: RemoveAction; curve: Curve; tmp: Figures.Reference;
	BEGIN
		ra := fact(RemoveAction); curve := ra.curve;
		IF undo THEN
			IF (ra.first = NIL) & (ra.last = NIL) THEN
				IF curve.prev # NIL THEN curve.prev.next := curve ELSE ra.path.fc := curve END;
				IF curve.next # NIL THEN curve.next.prev := curve ELSE ra.path.lc := curve END
			ELSE
				tmp := curve.first; curve.first := ra.first; ra.first := tmp;
				tmp := curve.last; curve.last := ra.last; ra.last := tmp;
				curve.pred := ra.pred; curve.succ := ra.succ
			END
		ELSE
			IF (ra.first = NIL) & (ra.last = NIL) THEN
				IF curve.prev # NIL THEN curve.prev.next := curve.next ELSE ra.path.fc := curve.next END;
				IF curve.next # NIL THEN curve.next.prev := curve.prev ELSE ra.path.lc := curve.prev END
			ELSE
				tmp := curve.first; curve.first := ra.first; ra.first := tmp;
				tmp := curve.last; curve.last := ra.last; ra.last := tmp;
				ra.pred := curve.pred; ra.succ := curve.succ;
				curve.pred := NIL; curve.succ := NIL
			END
		END;
		ra.path.stamp := stamp
	END DoRemoveCurve;
	
	PROCEDURE RemoveFromCurve (curve: Curve; path: Path; stamp: LONGINT; fig: Figures.Figure);
		VAR first, last: Figures.Reference; ra: RemoveAction;
	BEGIN
		first := curve.first; last := curve.last;
		IF (first.shape.stamp = stamp) OR (last.shape.stamp = stamp) THEN
			NEW(ra); ra.path := path; ra.curve := curve;
			WHILE (first # last.next) & (first.shape.stamp = stamp) DO first := first.next END;
			WHILE (first # last.next) & (last.shape.stamp = stamp) DO last := last.prev END;
			IF first # last.next THEN
				ra.first := first; ra.last := last
			ELSE
				ra.first := NIL; ra.last := NIL
			END;
			Figures.AddAction(fig, ra, DoRemoveCurve)
		END
	END RemoveFromCurve;
	
	PROCEDURE RemoveFromBezier (bezier: Curve; path: Path; stamp: LONGINT; fig: Figures.Figure);
		VAR first, last: Figures.Reference;
	BEGIN
		first := bezier.first;
		WHILE (first # bezier.last) & (first.shape.stamp = stamp) DO
			first := first.next;
			IF first # bezier.last THEN
				first.shape.stamp := stamp;
				first := first.next;
				IF first # bezier.last THEN
					first.shape.stamp := stamp;
					first := first.next
				END
			END
		END;
		last := bezier.last;
		WHILE (last # first) & (last.shape.stamp = stamp) DO
			last := last.prev;
		END;
		WHILE first # last DO
			first := first.next;
			IF first = last THEN
				first.shape.stamp := stamp
			ELSE
				first := first.next;
				IF first = last THEN
					first.shape.stamp := stamp
				ELSE
					first.prev.shape.stamp := path.stamp; first.shape.stamp := path.stamp;
					first := first.next;
					first.shape.stamp := path.stamp
				END
			END
		END;
		RemoveFromCurve(bezier, path, stamp, fig)
	END RemoveFromBezier;
	
	
