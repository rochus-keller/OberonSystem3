MODULE LeoBasic;	(** eos   **)

	(**
		Basic Leonardo Shapes
	**)
	
	IMPORT
		Files, Objects, Input, Oberon, Effects, Attributes, GfxMatrix, GfxPaths, Gfx, GfxPens, Solver, Figures,
		LeoFrames, LeoPens;
		
	
	CONST
		ML = 2; MM = 1; MR = 0;
		
	
	TYPE
		Shape* = POINTER TO ShapeDesc;
		ShapeDesc* = RECORD (Figures.ShapeDesc)
			fill*, stroke*: GfxPens.Pen;	(** pens for filling area and for stroking outline **)
			mx*, my*, ax*, ay*, bx*, by*: REAL;	(** coordinate system **)
		END;
		
	
	(**--- Shapes ---**)
	
	PROCEDURE ValidateShape* (shape: Shape);
		VAR rx, ry, bw: REAL;
	BEGIN
		rx := ABS(shape.ax) + ABS(shape.bx); ry := ABS(shape.ay) + ABS(shape.by);
		shape.llx := shape.mx - rx; shape.lly := shape.my - ry; shape.urx := shape.mx + rx; shape.ury := shape.my + ry;
		shape.bw := 0;
		IF shape.fill # NIL THEN
			Attributes.GetReal(shape.fill, "BorderWidth", bw);
			IF bw > shape.bw THEN shape.bw := -SHORT(ENTIER(-bw)) END
		END;
		IF shape.stroke # NIL THEN
			Attributes.GetReal(shape.stroke, "BorderWidth", bw);
			IF bw > shape.bw THEN shape.bw := -SHORT(ENTIER(-bw)) END
		END
	END ValidateShape;
	
	PROCEDURE TransformShape* (shape: Shape; VAR tm: Figures.TransformMsg);
		VAR mat, inv: GfxMatrix.Matrix; id: LONGINT;
	BEGIN
		IF tm.id = Figures.Get THEN
			Figures.HandleShape(shape, tm)
		ELSIF (tm.id = Figures.Apply) & (tm.stamp = shape.stamp) THEN
			GfxMatrix.Init(mat, shape.ax, shape.ay, shape.bx, shape.by, shape.mx, shape.my);
			GfxMatrix.Concat(mat, tm.mat, mat);
			Solver.RegisterObj(shape, id);
			Solver.Assign(Solver.Attr(id, "AX"), Solver.Real(mat[0, 0]));
			Solver.Assign(Solver.Attr(id, "AY"), Solver.Real(mat[0, 1]));
			Solver.Assign(Solver.Attr(id, "BX"), Solver.Real(mat[1, 0]));
			Solver.Assign(Solver.Attr(id, "BY"), Solver.Real(mat[1, 1]));
			Solver.Assign(Solver.Attr(id, "MX"), Solver.Real(mat[2, 0]));
			Solver.Assign(Solver.Attr(id, "MY"), Solver.Real(mat[2, 1]))
		ELSIF tm.id = Figures.Suggest THEN
			GfxMatrix.Init(mat, shape.ax, shape.ay, shape.bx, shape.by, shape.mx, shape.my);
			GfxMatrix.Invert(mat, inv);
			GfxMatrix.Apply(inv, tm.x0, tm.y0, tm.x0, tm.y0);
			GfxMatrix.Apply(inv, tm.x1, tm.y1, tm.x1, tm.y1);
			Figures.SuggestHandleTrafo(tm, -1, -1, 1, 1);
			GfxMatrix.Concat(inv, tm.mat, tm.mat); GfxMatrix.Concat(tm.mat, mat, tm.mat)
		END
	END TransformShape;
	
	PROCEDURE CopyShape* (VAR msg: Objects.CopyMsg; from, to: Shape);
	BEGIN
		Figures.CopyShape(msg, from, to);
		LeoPens.CopyRef(msg, from.fill, to.fill);
		LeoPens.CopyRef(msg, from.stroke, to.stroke);
		to.mx := from.mx; to.my := from.my;
		to.ax := from.ax; to.ay := from.ay;
		to.bx := from.bx; to.by := from.by
	END CopyShape;
	
	PROCEDURE HandleShape* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR shape, copy: Shape; ver: LONGINT;
	BEGIN
		shape := obj(Shape);
		IF msg IS Figures.ShapeMsg THEN
			IF (msg IS Figures.ValidateMsg) & (msg.stamp = shape.stamp) THEN
				WITH msg: Figures.ValidateMsg DO
					Figures.UpdateShapeRect(shape, msg.fig, msg.mat);
					ValidateShape(shape);
					Figures.UpdateShapeRect(shape, msg.fig, msg.mat);
					shape.cont.stamp := msg.stamp
				END
			ELSIF msg IS Figures.TransformMsg THEN
				TransformShape(shape, msg(Figures.TransformMsg))
			ELSE
				Figures.HandleShape(shape, msg)
			END
		ELSIF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				Figures.HandleRealAttr(msg, "MX", shape.mx);
				Figures.HandleRealAttr(msg, "MY", shape.my);
				Figures.HandleRealAttr(msg, "AX", shape.ax);
				Figures.HandleRealAttr(msg, "AY", shape.ay);
				Figures.HandleRealAttr(msg, "BX", shape.bx);
				Figures.HandleRealAttr(msg, "BY", shape.by);
				Figures.HandleShape(shape, msg)
			END
		ELSIF msg IS Objects.LinkMsg THEN
			WITH msg: Objects.LinkMsg DO
				LeoPens.LinkRef(msg, "FillPen", TRUE, shape.fill);
				LeoPens.LinkRef(msg, "StrokePen", TRUE, shape.stroke)
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # shape.stamp THEN
					NEW(copy); shape.dlink := copy; shape.stamp := msg.stamp;
					CopyShape(msg, shape, copy)
				END;
				msg.obj := shape.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			IF shape.fill # NIL THEN Figures.Forward(shape, shape.fill, msg) END;
			IF shape.stroke # NIL THEN Figures.Forward(shape, shape.stroke, msg) END;
			Figures.HandleShape(shape, msg)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				Figures.HandleShape(shape, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					LeoPens.WriteRef(msg.R, shape.lib, shape.fill);
					LeoPens.WriteRef(msg.R, shape.lib, shape.stroke);
					Files.WriteReal(msg.R, shape.mx); Files.WriteReal(msg.R, shape.my);
					Files.WriteReal(msg.R, shape.ax); Files.WriteReal(msg.R, shape.ay);
					Files.WriteReal(msg.R, shape.bx); Files.WriteReal(msg.R, shape.by)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver >= 1 THEN
						LeoPens.ReadRef(msg.R, shape.lib, shape.fill);
						LeoPens.ReadRef(msg.R, shape.lib, shape.stroke);
						Files.ReadReal(msg.R, shape.mx); Files.ReadReal(msg.R, shape.my);
						Files.ReadReal(msg.R, shape.ax); Files.ReadReal(msg.R, shape.ay);
						Files.ReadReal(msg.R, shape.bx); Files.ReadReal(msg.R, shape.by);
						ValidateShape(shape)
					END
				END
			END
		ELSE
			Figures.HandleShape(shape, msg)
		END
	END HandleShape;
	
	
	(**--- Rectangles ---**)
	
	PROCEDURE LocateRect (rect: Shape; VAR lm: Figures.LocateMsg);
		VAR rx, ry, d, llx, lly, urx, ury, px, py: REAL; inv: GfxMatrix.Matrix;
	BEGIN
		IF lm.stamp # rect.stamp THEN
			rect.stamp := lm.stamp;
			rx := ABS(rect.ax) + ABS(rect.bx); ry := ABS(rect.ay) + ABS(rect.by);
			IF (lm.id = Figures.Inside) & (lm.llx <= rect.mx - rx) & (rect.mx + rx <= lm.urx) & (lm.lly <= rect.my - ry) & (rect.my + ry <= lm.ury) THEN
				rect.slink := lm.shapes; lm.shapes := rect
			ELSIF (lm.llx <= rect.mx + rx) & (rect.mx - rx <= lm.urx) & (lm.lly <= rect.my + ry) & (rect.my - ry <= lm.ury) THEN
				d := 1/(rect.ax * rect.by - rect.ay * rect.bx);
				GfxMatrix.Init(inv, d * rect.by, -d * rect.ay, -d * rect.bx, d * rect.ax,
					d * (rect.bx * rect.my - rect.by * rect.mx), d * (rect.ay * rect.mx - rect.ax * rect.my));
				IF lm.id = Figures.Overlap THEN
					GfxMatrix.ApplyToRect(inv, lm.llx, lm.lly, lm.urx, lm.ury, llx, lly, urx, ury);
					IF (-1 <= urx) & (llx <= 1) & (-1 <= ury) & (lly <= 1) THEN
						lm.shapes := rect; rect.slink := NIL
					END
				ELSIF lm.id = Figures.Project THEN
					llx := lm.llx; lly := lm.lly; urx := lm.urx; ury := lm.ury;
					GfxMatrix.ApplyToRect(inv, llx, lly, urx, ury, lm.llx, lm.lly, lm.urx, lm.ury);
					Figures.ProjectToHandles(rect, lm, -1, -1, 1, 1);
					IF lm.shapes = rect THEN
						px := lm.px; py := lm.py;
						lm.px := rect.mx + px * rect.ax + py * rect.bx;
						lm.py := rect.my + py * rect.ay + py * rect.by
					END;
					lm.llx := llx; lm.lly := lly; lm.urx := urx; lm.ury := ury
				END
			END
		END
	END LocateRect;
	
	PROCEDURE DrawRect (rect: Shape; VAR dm: Figures.DrawMsg);
		VAR rx, ry, mx, my, ax, ay, bx, by: REAL; ctm, mat: GfxMatrix.Matrix;
		
		PROCEDURE render (pen: GfxPens.Pen);
		BEGIN
			pen.do.begin(pen, dm.ctxt);
			pen.do.enter(pen, mx - ax - bx, my - ay - by, -bx, -by, 0);
			pen.do.line(pen, mx + ax - bx, my + ay - by); pen.do.line(pen, mx + ax + bx, my + ay + by);
			pen.do.line(pen, mx - ax + bx, my - ay + by); pen.do.line(pen, mx - ax - bx, my - ay - by);
			pen.do.exit(pen, ax, ay, 0);
			pen.do.end(pen)
		END render;
		
	BEGIN
		IF dm.all & (rect.stamp # dm.stamp) OR (rect.stamp = dm.stamp) THEN
			rect.stamp := dm.stamp;
			rx := ABS(rect.ax) + ABS(rect.bx) + rect.bw; ry := ABS(rect.ay) + ABS(rect.by) + rect.bw;
			IF (dm.llx <= rect.mx + rx) & (rect.mx - rx <= dm.urx) & (dm.lly <= rect.my + ry) & (rect.my - ry <= dm.ury) THEN
				mx := rect.mx; my := rect.my; ax := rect.ax; ay := rect.ay; bx := rect.bx; by := rect.by;
				IF rect.fill # NIL THEN render(rect.fill) END;
				IF rect.stroke # NIL THEN render(rect.stroke) END;
				IF (dm.id = Figures.Full) & rect.sel THEN
					ctm := dm.ctxt.ctm;
					GfxMatrix.Init(mat, ax, ay, bx, by, mx, my);
					Gfx.Concat(dm.ctxt, mat);
					Figures.DrawHandles(dm, -1, -1, 1, 1);
					Gfx.SetCTM(dm.ctxt, ctm)
				END
			END
		END
	END DrawRect;
	
	PROCEDURE HandleRect* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR rect: Shape;
	BEGIN
		rect := obj(Shape);
		IF msg IS Figures.ShapeMsg THEN
			IF msg IS Figures.LocateMsg THEN
				LocateRect(rect, msg(Figures.LocateMsg))
			ELSIF msg IS Figures.DrawMsg THEN
				DrawRect(rect, msg(Figures.DrawMsg))
			ELSE
				HandleShape(rect, msg)
			END
		ELSIF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				Figures.HandleGenAttr(msg, "LeoBasic.NewRect");
				HandleShape(rect, msg)
			END
		ELSE
			HandleShape(rect, msg)
		END
	END HandleRect;
	
	PROCEDURE InitRect* (rect: Shape; x0, y0, x1, y1: REAL; fill, stroke: GfxPens.Pen);
	BEGIN
		rect.handle := HandleRect;
		rect.fill := fill; rect.stroke := stroke;
		rect.mx := 0.5*(x0 + x1); rect.my := 0.5*(y0 + y1);
		rect.ax := 0.5*(x1 - x0); rect.ay := 0;
		rect.bx := 0; rect.by := 0.5*(y1 - y0);
		ValidateShape(rect)
	END InitRect;
	
	PROCEDURE NewRect*;
		VAR rect: Shape;
	BEGIN
		NEW(rect); InitRect(rect, 0, 0, 1, 1, NIL, NIL);
		Objects.NewObj := rect
	END NewRect;
	
	PROCEDURE TrackRect (frame: LeoFrames.Frame; VAR msg: Oberon.InputMsg);
		VAR fx, fy, mx, my, x, y: INTEGER; x0, y0, x1, y1: REAL; keysum, keys: SET; rect: Shape;
	BEGIN
		fx := msg.x + frame.X; fy := msg.y + frame.Y;
		LeoFrames.PixelToPoint(frame, msg.X - fx, msg.Y - fy, x0, y0);
		LeoFrames.AlignPoint(frame, x0, y0, x0, y0);
		LeoFrames.ResetDragCtxt(frame, fx, fy);
		Oberon.FadeCursor(Oberon.Mouse);
		keysum := msg.keys; keys := msg.keys; mx := msg.X; my := msg.Y; x1 := x0; y1 := y0;
		Gfx.DrawRect(LeoFrames.DragCtxt, x0, y0, x1, y1, {Gfx.Stroke});
		Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, mx, my);
		REPEAT
			Input.Mouse(keys, x, y);
			keysum := keysum + keys;
			IF (keys # {}) & ((x # mx) OR (y # my)) THEN
				Oberon.FadeCursor(Oberon.Mouse);
				Gfx.DrawRect(LeoFrames.DragCtxt, x0, y0, x1, y1, {Gfx.Stroke});
				LeoFrames.PixelToPoint(frame, x - fx, y - fy, x1, y1);
				LeoFrames.AlignPoint(frame, x0, y0, x1, y1);
				Gfx.DrawRect(LeoFrames.DragCtxt, x0, y0, x1, y1, {Gfx.Stroke});
				mx := x; my := y;
				Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, mx, my);
			END
		UNTIL keys = {};
		Oberon.FadeCursor(Oberon.Mouse);
		Gfx.DrawRect(LeoFrames.DragCtxt, x0, y0, x1, y1, {Gfx.Stroke});
		IF (keysum # {ML, MM, MR}) & (x1 # x0) & (y1 # y0) THEN
			NEW(rect); InitRect(rect, x0, y0, x1, y1, LeoPens.Filler, LeoPens.Stroker);
			LeoFrames.Integrate(frame.obj(Figures.Figure), NIL, rect)
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, mx, my);
		msg.res := 0
	END TrackRect;
	
	PROCEDURE HandleRectTool (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR frame: LeoFrames.Frame;
	BEGIN
		frame := obj(LeoFrames.Frame);
		IF msg IS Oberon.InputMsg THEN
			WITH msg: Oberon.InputMsg DO
				IF msg.id = Oberon.track THEN
					IF msg.keys = {ML} THEN
						TrackRect(frame, msg)
					ELSIF msg.keys = {} THEN
						Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, msg.X, msg.Y);
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
	END HandleRectTool;
	
	PROCEDURE SetRectTool*;
	BEGIN
		LeoFrames.SetTool(HandleRectTool)
	END SetRectTool;
	
	
	(**--- Ellipses ---**)
	
	PROCEDURE LocateEllipse (ell: Shape; VAR lm: Figures.LocateMsg);
		VAR rx, ry, d, px, py, dx, dy, llx, lly, urx, ury: REAL; inv: GfxMatrix.Matrix;
	BEGIN
		IF lm.stamp # ell.stamp THEN
			ell.stamp := lm.stamp;
			rx := ABS(ell.ax) + ABS(ell.bx); ry := ABS(ell.ay) + ABS(ell.by);
			IF (lm.id = Figures.Inside) & (lm.llx <= ell.mx - rx) & (ell.mx + rx <= lm.urx) & (lm.lly <= ell.my - ry) & (ell.my + ry <= lm.ury) THEN
				ell.slink := lm.shapes; lm.shapes := ell
			ELSIF (lm.llx <= ell.mx + rx) & (ell.mx - rx <= lm.urx) & (lm.lly <= ell.my + ry) & (ell.my - ry <= lm.ury) THEN
				IF lm.id = Figures.Overlap THEN
					d := 1/(ell.ax * ell.by - ell.ay * ell.bx);
					GfxMatrix.Init(inv, d * ell.by, -d * ell.ay, -d * ell.bx, d * ell.ax, d * (ell.bx * ell.my - ell.by * ell.mx),
						d * (ell.ay * ell.mx - ell.ax * ell.my));
					GfxMatrix.Apply(inv, 0.5*(lm.llx + lm.urx), 0.5*(lm.lly + lm.ury), px, py);
					GfxMatrix.ApplyToVector(inv, lm.urx - lm.llx, lm.ury - lm.lly, dx, dy);
					IF px * px + py * py < 1 + 0.25*dx * dx + dy * dy THEN
						ell.slink := lm.shapes; lm.shapes := ell
					ELSIF ell.sel THEN	(* check corner handles *)
						GfxMatrix.ApplyToRect(inv, lm.llx, lm.lly, lm.urx, lm.ury, llx, lly, urx, ury);
						IF ((llx <= -1) & (-1 < urx) OR (llx <= 1) & (1 <= urx)) & ((lly <= -1) & (-1 <= ury) OR (lly <= 1) & (1 <= ury)) THEN
							lm.shapes := ell; ell.slink := NIL
						END
					END
				ELSIF lm.id = Figures.Project THEN
					GfxPaths.ProjectToEllipse(ell.ax, ell.ay, ell.bx, ell.by, 0.5*(lm.llx + lm.urx) - ell.mx, 0.5*(lm.lly + lm.ury) - ell.my, px, py);
					px := ell.mx + px; py := ell.my + py;
					IF (lm.llx <= px) & (px <= lm.urx) & (lm.lly <= py) & (py <= lm.ury) THEN
						lm.shapes := ell; lm.px := px; lm.py := py
					END
				END
			END
		END
	END LocateEllipse;
	
	PROCEDURE DrawEllipse (ell: Shape; VAR dm: Figures.DrawMsg);
		VAR bw, rx, ry, ax, ay: REAL; ctm, mat: GfxMatrix.Matrix;
		
		PROCEDURE render (pen: GfxPens.Pen);
		BEGIN
			pen.do.begin(pen, dm.ctxt);
			pen.do.enter(pen, ax, ay, ell.bx, ell.by, 0);
			pen.do.arc(pen, ax, ay, ell.mx, ell.my, ax, ay, ell.mx + ell.bx, ell.my + ell.by);
			pen.do.exit(pen, ell.bx, ell.by, 0);
			pen.do.end(pen)
		END render;
		
	BEGIN
		IF dm.all & (ell.stamp # dm.stamp) OR (ell.stamp = dm.stamp) THEN
			ell.stamp := dm.stamp;
			rx := ABS(ell.ax) + ABS(ell.bx) + ell.bw; ry := ABS(ell.ay) + ABS(ell.by) + ell.bw;
			IF (dm.llx <= ell.mx + rx) & (ell.mx - rx <= dm.urx) & (dm.lly <= ell.my + ry) & (ell.my - ry <= dm.ury) THEN
				ax := ell.mx + ell.ax; ay := ell.my + ell.ay;
				IF ell.fill # NIL THEN render(ell.fill) END;
				IF ell.stroke # NIL THEN render(ell.stroke) END;
				IF (dm.id = Figures.Full) & ell.sel THEN
					ctm := dm.ctxt.ctm;
					GfxMatrix.Get3PointTransform(0, 0, ell.mx, ell.my, 1, 0, ax, ay, 0, 1, ell.mx + ell.bx, ell.my + ell.by, mat);
					Gfx.Concat(dm.ctxt, mat);
					Figures.DrawHandles(dm, -1, -1, 1, 1);
					Gfx.SetCTM(dm.ctxt, ctm)
				END
			END
		END
	END DrawEllipse;
	
	PROCEDURE HandleEllipse* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR ell: Shape;
	BEGIN
		ell := obj(Shape);
		IF msg IS Figures.ShapeMsg THEN
			IF msg IS Figures.LocateMsg THEN
				LocateEllipse(ell, msg(Figures.LocateMsg))
			ELSIF msg IS Figures.DrawMsg THEN
				DrawEllipse(ell, msg(Figures.DrawMsg))
			ELSE
				HandleShape(ell, msg)
			END
		ELSIF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				Figures.HandleGenAttr(msg, "LeoBasic.NewEllipse");
				HandleShape(ell, msg)
			END
		ELSE
			HandleShape(ell, msg)
		END
	END HandleEllipse;
	
	PROCEDURE InitEllipse* (ell: Shape; mx, my, a, b: REAL; fill, stroke: GfxPens.Pen);
	BEGIN
		ell.handle := HandleEllipse;
		ell.fill := fill; ell.stroke := stroke;
		ell.mx := mx; ell.my := my;
		ell.ax := a; ell.ay := 0;
		ell.bx := 0; ell.by := b;
		ValidateShape(ell)
	END InitEllipse;
	
	PROCEDURE NewEllipse*;
		VAR ell: Shape;
	BEGIN
		NEW(ell); InitEllipse(ell, 0, 0, 1, 1, NIL, NIL);
		Objects.NewObj := ell
	END NewEllipse;
	
	PROCEDURE TrackEllipse (frame: LeoFrames.Frame; VAR msg: Oberon.InputMsg);
		VAR fx, fy, mx, my, x, y: INTEGER; x0, y0, x1, y1: REAL; keysum, keys: SET; ell: Shape;
	BEGIN
		fx := msg.x + frame.X; fy := msg.y + frame.Y;
		LeoFrames.PixelToPoint(frame, msg.X - fx, msg.Y - fy, x0, y0);
		LeoFrames.AlignPoint(frame, x0, y0, x0, y0);
		LeoFrames.ResetDragCtxt(frame, fx, fy);
		Oberon.FadeCursor(Oberon.Mouse);
		keysum := msg.keys; keys := msg.keys; mx := msg.X; my := msg.Y; x1 := x0; y1 := y0;
		Gfx.DrawEllipse(LeoFrames.DragCtxt, x0, y0, 0, 0, {Gfx.Stroke});
		Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, mx, my);
		REPEAT
			Input.Mouse(keys, x, y);
			keysum := keysum + keys;
			IF (keys # {}) & ((x # mx) OR (y # my)) THEN
				Oberon.FadeCursor(Oberon.Mouse);
				Gfx.DrawEllipse(LeoFrames.DragCtxt, 0.5*(x0 + x1), 0.5*(y0 + y1), 0.5*(x1 - x0), 0.5*(y1 - y0), {Gfx.Stroke});
				LeoFrames.PixelToPoint(frame, x - fx, y - fy, x1, y1);
				LeoFrames.AlignPoint(frame, x0, y0, x1, y1);
				Gfx.DrawEllipse(LeoFrames.DragCtxt, 0.5*(x0 + x1), 0.5*(y0 + y1), 0.5*(x1 - x0), 0.5*(y1 - y0), {Gfx.Stroke});
				mx := x; my := y;
				Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, mx, my);
			END
		UNTIL keys = {};
		Oberon.FadeCursor(Oberon.Mouse);
		Gfx.DrawEllipse(LeoFrames.DragCtxt, 0.5*(x0 + x1), 0.5*(y0 + y1), 0.5*(x1 - x0), 0.5*(y1 - y0), {Gfx.Stroke});
		IF (keysum # {ML, MM, MR}) & (x1 # x0) & (y1 # y0) THEN
			NEW(ell); InitEllipse(ell, 0.5*(x0 + x1), 0.5*(y0 + y1), 0.5*(x1 - x0), 0.5*(y1 - y0), LeoPens.Filler, LeoPens.Stroker);
			LeoFrames.Integrate(frame.obj(Figures.Figure), NIL, ell)
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, mx, my);
		msg.res := 0
	END TrackEllipse;

	PROCEDURE HandleEllipseTool (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR frame: LeoFrames.Frame;
	BEGIN
		frame := obj(LeoFrames.Frame);
		IF msg IS Oberon.InputMsg THEN
			WITH msg: Oberon.InputMsg DO
				IF msg.id = Oberon.track THEN
					IF msg.keys = {ML} THEN
						TrackEllipse(frame, msg)
					ELSIF msg.keys = {} THEN
						Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, msg.X, msg.Y);
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
	END HandleEllipseTool;
	
	PROCEDURE SetEllipseTool*;
	BEGIN
		LeoFrames.SetTool(HandleEllipseTool)
	END SetEllipseTool;
	

END LeoBasic.
