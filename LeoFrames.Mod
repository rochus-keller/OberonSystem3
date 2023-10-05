MODULE LeoFrames;	(** eos   **)

	(**
		Support for installable tools in the Leonardo figure editor
	**)
	
	IMPORT
		Files, Objects, Math, Display, Input, Oberon, Display3, Effects, Gadgets, GfxMatrix, GfxMaps, GfxPaths,
		GfxFonts, Gfx, Solver, Figures, FigureGadgets;
		
	
	CONST
		Activate* = 0; Deactivate* = 1; Show* = 2; Hide* = 3;	(** tool message id **)
		Translate* = 0; Scale* = 1; Rotate* = 2; Shear* = 4; Mirror* = 5;	(** focus styles **)
		ML* = 2; MM* = 1; MR* = 0;	(** standard mouse buttons **)
		
	
	TYPE
		(* special graphics context for simplified rendering in invert mode *)
		Context = POINTER TO ContextDesc;
		ContextDesc = RECORD (Gfx.ContextDesc)
			orgX, orgY: REAL;	(* origin of default coordinate system *)
			scale: REAL;	(* default coordinate system scale factor *)
			u, v: REAL;
			px, py: INTEGER;
		END;
		
		PathData = RECORD (GfxPaths.EnumData)
			context: Context;
		END;
		
		(** layer shapes **)
		Layer* = POINTER TO LayerDesc;
		LayerDesc* = RECORD (Figures.ContainerDesc)
			name*: ARRAY 16 OF CHAR;	(** layer name **)
			display*, print*, align*, edit*: BOOLEAN;	(** layer flags **)
		END;
		
		(** Leonardo frame **)
		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD (FigureGadgets.FrameDesc)
			unit*: REAL;	(** unit of measurement in figure coordinates **)
			subdiv*: INTEGER;	(** number of alignment points per unit **)
			align*: BOOLEAN;	(** indicates whether mouse coordinates within frame get aligned to grid **)
		END;
		
		(** message for notifying changes to edit tools **)
		ToolMsg* = RECORD (Display.FrameMsg)
			id*: INTEGER;	(** Activate/Deactivate/Show/Hide **)
		END;
		
	
	VAR
		DragCtxt*: Context;	(** context for temporary quick rendering (inverting) **)
		Tolerance*: REAL;	(* tolerance for locating shapes *)
		ToolHandle*: Objects.Handler;	(** current tool handler **)
		ToolFrame*: Frame;	(** frame which represents current tool graphics **)
		
		FocusVisible: BOOLEAN;	(* flag whether focus is visible *)
		FocusStyle: INTEGER;	(* current kind of focus *)
		FocusPoints: INTEGER;	(* number of focus points *)
		FocusX, FocusY: ARRAY 2 OF REAL;	(* focus position within focus frame *)
		
		TranslatePat, RotatePat, ScalePat, ShearPat, MirrorPat, AuxPat: Display.Pattern;
		AlignAxes: INTEGER;	(* number of axes to constrain dragging *)
		
		Methods: Gfx.Methods;
		
	
	(*--- Drag Contexts ---*)
	
	PROCEDURE ResetCTM (ctxt: Gfx.Context);
		VAR dc: Context;
	BEGIN
		dc := ctxt(Context);
		GfxMatrix.Translate(GfxMatrix.Identity, dc.orgX, dc.orgY, dc.ctm);
		GfxMatrix.Scale(dc.ctm, dc.scale, dc.scale, dc.ctm)
	END ResetCTM;
	
	PROCEDURE ResetClip (ctxt: Gfx.Context);
	END ResetClip;
	
	PROCEDURE GetClipRect (ctxt: Gfx.Context; VAR llx, lly, urx, ury: REAL);
		VAR x, y, w, h: INTEGER; inv: GfxMatrix.Matrix;
	BEGIN
		Display.GetClip(x, y, w, h);
		GfxMatrix.Invert(ctxt.ctm, inv);
		GfxMatrix.ApplyToRect(inv, x, y, x + w, y + h, llx, lly, urx, ury)
	END GetClipRect;
	
	PROCEDURE SaveClip (ctxt: Gfx.Context);
	END SaveClip;
	
	PROCEDURE RestoreClip (ctxt: Gfx.Context);
	END RestoreClip;
	
	PROCEDURE EnterLine (dc: Context; u, v: REAL);
	BEGIN
		dc.px := SHORT(ENTIER(u)); dc.py := SHORT(ENTIER(v));
		Display.Dot(Display3.invertC, dc.px, dc.py, Display.invert);
		dc.u := u; dc.v := v
	END EnterLine;
	
	PROCEDURE DrawLine (dc: Context; u, v: REAL);
		VAR px, py, xstep, ystep, steps: INTEGER; du, dv, eu, ev, e: REAL;
	BEGIN
		px := SHORT(ENTIER(u)); py := SHORT(ENTIER(v));
		IF px = dc.px THEN
			IF py > dc.py THEN
				Display.ReplConst(Display3.invertC, px, dc.py+1, 1, py - dc.py, Display.invert)
			ELSIF py < dc.py THEN
				Display.ReplConst(Display3.invertC, px, py, 1, dc.py - py, Display.invert)
			END;
			dc.py := py
		ELSIF py = dc.py THEN
			IF px > dc.px THEN
				Display.ReplConst(Display3.invertC, dc.px+1, py, px - dc.px, 1, Display.invert)
			ELSE
				Display.ReplConst(Display3.invertC, px, py, dc.px - px, 1, Display.invert)
			END;
			dc.px := px
		ELSE
			du := u - dc.u; dv := v - dc.v;
			IF du >= 0 THEN
				xstep := 1; eu := dc.u - (dc.px + 0.5)
			ELSE
				xstep := -1; du := -du; eu := dc.px + 0.5 - dc.u
			END;
			IF dv >= 0 THEN
				ystep := 1; ev := dc.v - (dc.py + 0.5)
			ELSE
				ystep := -1; dv := -dv; ev := dc.py + 0.5 - dc.v
			END;
			IF du >= dv THEN
				e := du * ev - dv * eu + dv - 0.5*du;
				steps := ABS(px - dc.px);
				WHILE steps > 0 DO
					IF (e >= 0) & ((e > 0) OR (ystep <= 0)) THEN
						INC(dc.py, ystep);
						e := e - du
					END;
					INC(dc.px, xstep);
					e := e + dv;
					Display.Dot(Display3.invertC, dc.px, dc.py, Display.invert);
					DEC(steps)
				END
			ELSE
				e := dv * eu - du * ev + du - 0.5*dv;
				steps := ABS(py - dc.py);
				WHILE steps > 0 DO
					IF (e >= 0) & ((e > 0) OR (xstep <= 0)) THEN
						INC(dc.px, xstep);
						e := e - dv
					END;
					INC(dc.py, ystep);
					e := e + du;
					Display.Dot(Display3.invertC, dc.px, dc.py, Display.invert);
					DEC(steps)
				END
			END
		END;
		dc.u := u; dc.v := v
	END DrawLine;
	
	PROCEDURE StrokePathElem (VAR data: GfxPaths.EnumData);
		VAR dc: Context;
	BEGIN
		dc := data(PathData).context;
		CASE data.elem OF
		| GfxPaths.Enter: EnterLine(dc, data.x, data.y)
		| GfxPaths.Line: DrawLine(dc, data.x, data.y)
		ELSE
		END
	END StrokePathElem;
	
	PROCEDURE Begin (ctxt: Gfx.Context; mode: SET);
	BEGIN
		ctxt.mode := mode;
		ctxt.cam := ctxt.ctm;	(* preserve current transformation for attributes *)
		IF Gfx.Record IN ctxt.mode THEN
			IF ctxt.path = NIL THEN NEW(ctxt.path) END;
			GfxPaths.Clear(ctxt.path)
		END
	END Begin;
	
	PROCEDURE End (ctxt: Gfx.Context);
	END End;
	
	PROCEDURE Enter (ctxt: Gfx.Context; x, y, dx, dy: REAL);
		VAR dc: Context; du, dv: REAL;
	BEGIN
		dc := ctxt(Context);
		GfxMatrix.Apply(dc.ctm, x, y, dc.u, dc.v);
		IF Gfx.Record IN dc.mode THEN
			GfxMatrix.ApplyToVector(dc.ctm, dx, dy, du, dv);
			GfxPaths.AddEnter(dc.path, dc.u, dc.v, du, dv)
		END;
		IF dc.mode * {Gfx.Stroke, Gfx.Fill} # {} THEN
			EnterLine(dc, dc.u, dc.v)
		END;
		dc.cpx := x; dc.cpy := y
	END Enter;
	
	PROCEDURE Exit (ctxt: Gfx.Context; dx, dy: REAL);
		VAR du, dv: REAL;
	BEGIN
		IF Gfx.Record IN ctxt.mode THEN
			GfxMatrix.ApplyToVector(ctxt.ctm, dx, dy, du, dv);
			GfxPaths.AddExit(ctxt.path, du, dv)
		END
	END Exit;
	
	PROCEDURE LineTo (ctxt: Gfx.Context; x, y: REAL);
		VAR dc: Context; u, v: REAL;
	BEGIN
		dc := ctxt(Context);
		GfxMatrix.Apply(dc.ctm, x, y, u, v);
		IF Gfx.Record IN dc.mode THEN
			GfxPaths.AddLine(dc.path, u, v)
		END;
		IF dc.mode * {Gfx.Stroke, Gfx.Fill} # {} THEN
			DrawLine(dc, u, v)
		END;
		dc.cpx := x; dc.cpy := y
	END LineTo;
	
	PROCEDURE ArcTo (ctxt: Gfx.Context; x, y, x0, y0, x1, y1, x2, y2: REAL);
		VAR dc: Context; u, v, u0, v0, u1, v1, u2, v2: REAL; data: PathData;
	BEGIN
		dc := ctxt(Context);
		GfxMatrix.Apply(dc.ctm, x, y, u, v);
		GfxMatrix.Apply(dc.ctm, x0, y0, u0, v0);
		GfxMatrix.Apply(dc.ctm, x1, y1, u1, v1);
		GfxMatrix.Apply(dc.ctm, x2, y2, u2, v2);
		IF Gfx.Record IN dc.mode THEN
			GfxPaths.AddArc(dc.path, u, v, u0, v0, u1, v1, u2, v2)
		END;
		IF dc.mode * {Gfx.Stroke, Gfx.Fill} # {} THEN
			data.context := dc; data.x := dc.u; data.y := dc.v;
			GfxPaths.EnumArc(u0, v0, u1, v1, u2, v2, u, v, 1, StrokePathElem, data)
		END;
		dc.cpx := x; dc.cpy := y
	END ArcTo;
	
	PROCEDURE BezierTo (ctxt: Gfx.Context; x, y, x1, y1, x2, y2: REAL);
		VAR dc: Context; u, v, u1, v1, u2, v2: REAL; data: PathData;
	BEGIN
		dc := ctxt(Context);
		GfxMatrix.Apply(dc.ctm, x, y, u, v);
		GfxMatrix.Apply(dc.ctm, x1, y1, u1, v1);
		GfxMatrix.Apply(dc.ctm, x2, y2, u2, v2);
		IF Gfx.Record IN dc.mode THEN
			GfxPaths.AddBezier(dc.path, u, v, u1, v1, u2, v2)
		END;
		IF dc.mode * {Gfx.Stroke, Gfx.Fill} # {} THEN
			data.context := dc; data.x := dc.u; data.y := dc.v;
			GfxPaths.EnumBezier(u1, v1, u2, v2, u, v, 1, StrokePathElem, data)
		END;
		dc.cpx := x; dc.cpy := y
	END BezierTo;
	
	PROCEDURE ShowM (ctxt: Gfx.Context; x, y: REAL; VAR str: ARRAY OF CHAR);
		VAR font: GfxFonts.Font; dx, dy: REAL;
	BEGIN
		font := ctxt.font;
		GfxFonts.GetStringWidth(font, str, dx, dy);
		Enter(ctxt, x, y + font.ymin, 0, 0);
		LineTo(ctxt, x, y + font.ymax); LineTo(ctxt, x + dx, y + dy + font.ymax);
		LineTo(ctxt, x + dx, y + dy + font.ymin); LineTo(ctxt, x, y + font.ymin);
		Exit(ctxt, 0, 0)
	END ShowM;
	
	PROCEDURE Render (ctxt: Gfx.Context; mode: SET);
		VAR data: PathData;
	BEGIN
		IF mode * {Gfx.Fill, Gfx.Stroke} # {} THEN
			ctxt.cam := ctxt.ctm;
			data.context := ctxt(Context);
			GfxPaths.EnumFlattened(ctxt.path, ctxt.flatness, StrokePathElem, data)
		END
	END Render;
	
	PROCEDURE Erase (ctxt: Gfx.Context);
	END Erase;
	
	PROCEDURE Image (ctxt: Gfx.Context; x, y: REAL; map: GfxMaps.Map; VAR filter: GfxMaps.Filter);
	BEGIN
		Gfx.DrawRect(ctxt, x, y, x + map.width, y + map.height, {Gfx.Stroke})
	END Image;
	
	PROCEDURE InitMethods;
		VAR do: Gfx.Methods;
	BEGIN
		NEW(do);
		Methods := do;
		do.reset := Gfx.DefResetContext;
		do.resetCTM := ResetCTM; do.setCTM := Gfx.DefSetCTM; do.translate := Gfx.DefTranslate;
		do.scale := Gfx.DefScale; do.rotate := Gfx.DefRotate; do.concat := Gfx.DefConcat;
		do.resetClip := ResetClip; do.getClipRect := GetClipRect; do.saveClip := SaveClip; do.restoreClip := RestoreClip;
		do.setStrokeColor := Gfx.DefSetStrokeColor; do.setStrokePattern := Gfx.DefSetStrokePattern;
		do.setFillColor := Gfx.DefSetFillColor; do.setFillPattern := Gfx.DefSetFillPattern;
		do.setLineWidth := Gfx.DefSetLineWidth; do.setDashPattern := Gfx.DefSetDashPattern;
		do.setCapStyle := Gfx.DefSetCapStyle; do.setJoinStyle := Gfx.DefSetJoinStyle;
		do.setStyleLimit := Gfx.DefSetStyleLimit;
		do.setPoint := Gfx.DefSetPoint; do.setFlatness := Gfx.DefSetFlatness;
		do.setFont := Gfx.DefSetFont; do.getWidth := Gfx.DefGetStringWidth;
		do.begin := Begin; do.end := End;
		do.enter := Enter; do.exit := Exit;
		do.line := LineTo; do.arc := ArcTo; do.bezier := BezierTo; do.show := ShowM;
		do.flatten := Gfx.DefFlatten; do.outline := Gfx.DefOutline; do.render := Render;
		do.erase := Erase; do.rect := Gfx.DefRect; do.ellipse := Gfx.DefEllipse;
		do.image := Image; do.newPattern := Gfx.DefNewPattern;
	END InitMethods;
	
	PROCEDURE SetCoordinates (dc: Context; x, y, scale: REAL);
	BEGIN
		dc.orgX := x; dc.orgY := y; dc.scale := scale
	END SetCoordinates;
	
	PROCEDURE InitContext (dc: Context);
	BEGIN
		dc.do := Methods;
		SetCoordinates(dc, Display.ColLeft, Display.Bottom, 1.0);
		dc.do.reset(dc)
	END InitContext;
	
	
	(**--- Layers ---**)
	
	PROCEDURE HandleLayer* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR layer, copy: Layer; ver: LONGINT;
	BEGIN
		layer := obj(Layer);
		IF msg IS Figures.ShapeMsg THEN
			IF msg IS Figures.SelectMsg THEN
				IF msg(Figures.SelectMsg).id IN {Figures.Get, Figures.Reset} THEN
					Figures.HandleRefs(layer, msg)
				ELSE
					Figures.HandleContainer(layer, msg)
				END
			ELSIF msg IS Figures.LocateMsg THEN
				WITH msg: Figures.LocateMsg DO
					IF (msg.id = Figures.Project) & layer.align OR (msg.id IN {Figures.Inside, Figures.Overlap}) & layer.edit THEN
						Figures.HandleRefs(layer, msg)
					END
				END
			ELSIF msg IS Figures.DrawMsg THEN
				WITH msg: Figures.DrawMsg DO
					IF (msg.id = Figures.Full) & layer.display OR (msg.id = Figures.Print) & layer.print THEN
						Figures.HandleRefs(layer, msg)
					END
				END
			ELSE
				Figures.HandleContainer(layer, msg)
			END
		ELSIF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				Figures.HandleGenAttr(msg, "LeoFrames.NewLayer");
				Figures.HandleStringAttr(msg, "Name", layer.name);
				Figures.HandleBoolAttr(msg, "Display", layer.display);
				Figures.HandleBoolAttr(msg, "Print", layer.print);
				Figures.HandleBoolAttr(msg, "Align", layer.align);
				Figures.HandleBoolAttr(msg, "Edit", layer.edit);
				Figures.HandleContainer(layer, msg)
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # layer.stamp THEN
					NEW(copy); layer.dlink := copy; layer.stamp := msg.stamp;
					Figures.CopyContainer(msg, layer, copy);
					copy.display := layer.display; copy.print := layer.print; copy.align := layer.align; copy.edit := layer.edit
				END;
				msg.obj := layer.dlink
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				Figures.HandleContainer(layer, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					Files.WriteString(msg.R, layer.name);
					Files.WriteBool(msg.R, layer.display);
					Files.WriteBool(msg.R, layer.print);
					Files.WriteBool(msg.R, layer.align);
					Files.WriteBool(msg.R, layer.edit)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver = 1 THEN
						Files.ReadString(msg.R, layer.name);
						Files.ReadBool(msg.R, layer.display);
						Files.ReadBool(msg.R, layer.print);
						Files.ReadBool(msg.R, layer.align);
						Files.ReadBool(msg.R, layer.edit)
					END
				END
			END
		ELSE
			Figures.HandleContainer(layer, msg)
		END
	END HandleLayer;
	
	PROCEDURE InitLayer* (layer: Layer; name: ARRAY OF CHAR; display, print, align, edit: BOOLEAN);
	BEGIN
		Figures.InitContainer(layer);
		layer.handle := HandleLayer;
		COPY(name, layer.name);
		layer.display := display; layer.print := print; layer.align := align; layer.edit := edit
	END InitLayer;
	
	PROCEDURE NewLayer*;
		VAR layer: Layer;
	BEGIN
		NEW(layer); InitLayer(layer, "", FALSE, FALSE, FALSE, FALSE);
		Objects.NewObj := layer
	END NewLayer;
	
	
	(**--- Frames ---**)
	
	PROCEDURE SendToolMsg* (frame: Frame; id: INTEGER);
		VAR tm: ToolMsg;
	BEGIN
		tm.F := frame; tm.id := id;
		Display.Broadcast(tm)
	END SendToolMsg;
	
	PROCEDURE SetTool* (handle: Objects.Handler);
	BEGIN
		IF ToolFrame # NIL THEN
			SendToolMsg(ToolFrame, Hide);
			ToolFrame := NIL
		END;
		SendToolMsg(NIL, Deactivate);
		ToolHandle := handle;
		SendToolMsg(NIL, Activate)
	END SetTool;
	
	PROCEDURE SetToolFrame* (frame: Frame);
	BEGIN
		IF ToolFrame # frame THEN
			IF ToolFrame # NIL THEN
				SendToolMsg(ToolFrame, Hide)
			END;
			ToolFrame := frame
		END
	END SetToolFrame;
	
	PROCEDURE DrawGrid (frame: Frame; VAR msg: Display.FrameMsg);
		VAR fx, fy, col: INTEGER; mask: Display3.Mask; oy, spacing, lx, y, x: REAL;
	BEGIN
		fx := msg.x + frame.X; fy := msg.y + frame.Y;
		Gadgets.MakeMask(frame, fx, fy, msg.dlink, mask);
		oy := frame.H + frame.oy;
		spacing := frame.unit*frame.scale;
		IF spacing >= 10 THEN
			col := GfxMaps.BestIndex(GfxMaps.DisplayPal, Gfx.DGrey.r, Gfx.DGrey.g, Gfx.DGrey.b);
			lx := frame.ox - ENTIER(frame.ox/spacing) * spacing;
			y := oy - ENTIER(oy/spacing) * spacing;
			WHILE y < frame.H DO
				x := lx;
				WHILE x < frame.W DO
					Display3.Dot(mask, col, fx + SHORT(ENTIER(x + 0.5)), fy + SHORT(ENTIER(y + 0.5)), Display.replace);
					x := x + spacing
				END;
				y := y + spacing
			END
		END;
		IF spacing >= 1 THEN
			spacing := 10*spacing;
			col := GfxMaps.BestIndex(GfxMaps.DisplayPal, Gfx.Black.r, Gfx.Black.g, Gfx.Black.b);
			lx := frame.ox - ENTIER(frame.ox/spacing) * spacing;
			y := oy - ENTIER(oy/spacing) * spacing;
			WHILE y < frame.H DO
				x := lx;
				WHILE x < frame.W DO
					Display3.Dot(mask, col, fx + SHORT(ENTIER(x + 0.5)), fy + SHORT(ENTIER(y + 0.5)), Display.replace);
					x := x + spacing
				END;
				y := y + spacing
			END
		END
	END DrawGrid;
	
	PROCEDURE HandleFrame (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR frame, copy: Frame; ver: LONGINT;
	BEGIN
		frame := obj(Frame);
		IF msg IS Display.FrameMsg THEN
			WITH msg: Display.FrameMsg DO
				IF (msg.F = frame) OR (msg.F = NIL) THEN
					IF msg IS ToolMsg THEN
						ToolHandle(frame, msg)
					ELSIF msg IS Oberon.InputMsg THEN
						WITH msg: Oberon.InputMsg DO
							IF (msg.id = Oberon.track) & Gadgets.InActiveArea(frame, msg) & ~(Gadgets.selected IN frame.state) THEN
								ToolHandle(frame, msg)
							ELSIF msg.id = Oberon.consume THEN
								ToolHandle(frame, msg)
							END
						END
					ELSIF msg IS Oberon.ConsumeMsg THEN
						ToolHandle(frame, msg)
					ELSIF msg IS Oberon.ControlMsg THEN
						IF (msg(Oberon.ControlMsg).id = Oberon.neutralize) & (frame = ToolFrame) THEN
							SendToolMsg(frame, Hide);
							ToolFrame := NIL
						END;
						ToolHandle(frame, msg);
						FigureGadgets.HandleFrame(frame, msg)
					ELSIF msg IS Figures.UpdateMsg THEN
						IF frame = ToolFrame THEN SendToolMsg(frame, Hide) END;
						FigureGadgets.HandleFrame(frame, msg);
						DrawGrid(frame, msg(Display.FrameMsg));
						IF frame = ToolFrame THEN SendToolMsg(frame, Show) END
					ELSIF msg IS Display.DisplayMsg THEN
						IF frame = ToolFrame THEN SendToolMsg(frame, Hide) END;
						FigureGadgets.HandleFrame(frame, msg);
						DrawGrid(frame, msg(Display.DisplayMsg));
						IF frame = ToolFrame THEN SendToolMsg(frame, Show) END
					ELSIF msg IS Display.ModifyMsg THEN
						IF frame = ToolFrame THEN
							SendToolMsg(frame, Hide);
							ToolFrame := NIL
						END;
						FigureGadgets.HandleFrame(frame, msg);
						IF msg(Display.ModifyMsg).mode = Display.display THEN
							DrawGrid(frame, msg(Display.ModifyMsg))
						END
					ELSIF msg IS Display.ControlMsg THEN
						IF (msg(Display.ControlMsg).id = Display.suspend) & (frame = ToolFrame) THEN
							SendToolMsg(frame, Hide)
						END;
						FigureGadgets.HandleFrame(frame, msg)
					ELSIF msg IS Display.ConsumeMsg THEN
						ToolHandle(frame, msg)
					ELSE
						FigureGadgets.HandleFrame(frame, msg)
					END
				END
			END
		ELSIF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				Figures.HandleGenAttr(msg, "LeoFrames.NewFrame");
				FigureGadgets.HandleFrame(frame, msg);
				Figures.HandleRealAttr(msg, "Unit", frame.unit);
				Figures.HandleIntAttr(msg, "Subdivisions", frame.subdiv, 1, 1000);
				Figures.HandleBoolAttr(msg, "AlignToGrid", frame.align)
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # frame.stamp THEN
					NEW(copy); frame.dlink := copy; frame.stamp := msg.stamp;
					FigureGadgets.CopyFrame(msg, frame, copy);
					copy.unit := frame.unit; copy.subdiv := frame.subdiv; copy.align := frame.align
				END;
				msg.obj := frame.dlink
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				FigureGadgets.HandleFrame(frame, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					Files.WriteReal(msg.R, frame.unit);
					Files.WriteInt(msg.R, frame.subdiv);
					Files.WriteBool(msg.R, frame.align)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver >= 1 THEN
						Files.ReadReal(msg.R, frame.unit);
						Files.ReadInt(msg.R, frame.subdiv);
						Files.ReadBool(msg.R, frame.align)
					END
				END
			END
		ELSE
			FigureGadgets.HandleFrame(frame, msg)
		END
	END HandleFrame;
	
	PROCEDURE InitFrame* (frame: Frame; fig: Figures.Figure; unit: REAL; subdiv: INTEGER);
	BEGIN
		FigureGadgets.InitFrame(frame, fig);
		frame.handle := HandleFrame;
		frame.unit := unit; frame.subdiv := subdiv; frame.align := TRUE
	END InitFrame;
	
	PROCEDURE NewFrame*;
		VAR frame: Frame;
	BEGIN
		NEW(frame); InitFrame(frame, NIL, Figures.cm, 10);
		Objects.NewObj := frame
	END NewFrame;
	
	
	(**--- Tools ---**)
	
	PROCEDURE Min (x, y: INTEGER): INTEGER;
	BEGIN
		IF x < y THEN RETURN x ELSE RETURN y END
	END Min;
	
	PROCEDURE Max (x, y: INTEGER): INTEGER;
	BEGIN
		IF x > y THEN RETURN x ELSE RETURN y END
	END Max;
	
	PROCEDURE PixelToPoint* (frame: Frame; x, y: REAL; VAR u, v: REAL);
	BEGIN
		u := (x - frame.ox)/frame.scale;
		v := (y - frame.H - frame.oy)/frame.scale
	END PixelToPoint;
	
	PROCEDURE PointToPixel* (frame: Frame; u, v: REAL; VAR x, y: REAL);
	BEGIN
		x := u * frame.scale + frame.ox;
		y := v * frame.scale + frame.oy + frame.H
	END PointToPixel;
	
	PROCEDURE AlignToGrid* (frame: Frame; VAR x, y: REAL);
		VAR dist: REAL;
	BEGIN
		dist := frame.unit/frame.subdiv;
		x := ENTIER(x/dist + 0.5) * dist;
		y := ENTIER(y/dist + 0.5) * dist
	END AlignToGrid;
	
	PROCEDURE AlignToAxis* (frame: Frame; sx, sy: REAL; VAR x, y: REAL);
		VAR phi, dx, dy, len, atan: REAL;
	BEGIN
		phi := 2.0 * Math.pi/AlignAxes;
		dx := x - sx; dy := y - sy;
		len := Math.sqrt(dx * dx + dy * dy);
		IF len >= Tolerance/frame.scale THEN
			IF (ABS(dx) < 1.0) & (ABS(dy) >= ABS(dx * MAX(REAL))) THEN	(* dy/dx would result in overflow/divide by zero trap *)
				IF dy >= 0 THEN atan := 0.5 * Math.pi
				ELSE atan := 1.5 * Math.pi
				END
			ELSIF dx > 0 THEN	(* 1st or 4th quadrant *)
				atan := Math.arctan(dy/dx)
			ELSIF dx < 0 THEN	(* 2nd or 3rd quadrant *)
				atan := Math.arctan(dy/dx) + Math.pi
			END;
			atan := ENTIER(atan/phi + 0.5) * phi;
			x := sx + len * Math.cos(atan); y := sy + len * Math.sin(atan)
		ELSE
			x := sx; y := sy
		END
	END AlignToAxis;
	
	PROCEDURE AlignToShape* (frame: Frame; VAR x, y: REAL);
		VAR s, px: REAL; lm: Figures.LocateMsg;
	BEGIN
		s := Tolerance/frame.scale;
		Objects.Stamp(lm); lm.id := Figures.Project; lm.llx := x - s; lm.urx := x + s; lm.px := x; lm.py := y;
		lm.lly := -(frame.oy + frame.H)/frame.scale;
		lm.ury := -frame.oy/frame.scale;
		Figures.Forward(frame, frame.obj, lm);
		px := lm.px;
		Objects.Stamp(lm); lm.lly := y - s; lm.ury := y + s; lm.px := x; lm.py := y;
		lm.llx := -frame.ox/frame.scale;
		lm.urx := (frame.W - frame.ox)/frame.scale;
		Figures.Forward(frame, frame.obj, lm);
		x := px; y := lm.py
	END AlignToShape;
	
	PROCEDURE AlignPoint* (frame: Frame; sx, sy: REAL; VAR x, y: REAL);
		VAR state: SET; fx, fy: REAL;
	BEGIN
		Input.KeyState(state);
		AlignToGrid(frame, x, y);
		IF Input.CTRL IN state THEN
			AlignToShape(frame, x, y)
		END;
		IF Input.SHIFT IN state THEN
			IF (frame = ToolFrame) & FocusVisible & (FocusPoints >= 1) THEN
				PixelToPoint(frame, FocusX[0], FocusY[0], fx, fy);
				AlignToAxis(frame, fx, fy, x, y)
			ELSE
				AlignToAxis(frame, sx, sy, x, y)
			END
		END
	END AlignPoint;
	
	PROCEDURE AlignPixel* (frame: Frame; sx, sy, x, y: REAL; VAR px, py: REAL);
	BEGIN
		PixelToPoint(frame, sx, sy, sx, sy);
		PixelToPoint(frame, x, y, x, y);
		AlignPoint(frame, sx, sy, x, y);
		PointToPixel(frame, x, y, px, py)
	END AlignPixel;
	
	PROCEDURE LocateShapesAt* (frame: Frame; x, y: INTEGER; VAR shapes: Figures.Shape);
		VAR u, v, s: REAL; lm: Figures.LocateMsg;
	BEGIN
		PixelToPoint(frame, x+0.5, y+0.5, u, v);
		s := Tolerance/frame.scale;
		Objects.Stamp(lm); lm.id := Figures.Overlap; lm.llx := u - s; lm.lly := v - s; lm.urx := u + s; lm.ury := v + s; lm.shapes := NIL;
		Figures.Forward(frame, frame.obj, lm);
		shapes := lm.shapes
	END LocateShapesAt;
	
	PROCEDURE LocateShapesIn* (frame: Frame; llx, lly, urx, ury: INTEGER; VAR shapes: Figures.Shape);
		VAR lm: Figures.LocateMsg;
	BEGIN
		Objects.Stamp(lm); lm.id := Figures.Inside; lm.shapes := NIL;
		PixelToPoint(frame, llx+0.5, lly+0.5, lm.llx, lm.lly);
		PixelToPoint(frame, urx+0.5, ury+0.5, lm.urx, lm.ury);
		Figures.Forward(frame, frame.obj, lm);
		shapes := lm.shapes
	END LocateShapesIn;
	
	PROCEDURE Integrate* (fig: Figures.Figure; target, shapes: Figures.Shape);
		VAR ref: Figures.Reference;
	BEGIN
		IF target = NIL THEN
			target := fig.root;
			ref := fig.root.first;
			WHILE ref # NIL DO
				IF (ref.shape IS Layer) & ref.shape(Layer).edit THEN
					target := ref.shape
				END;
				ref := ref.next
			END
		END;
		Figures.DisableUpdate(fig);
		Figures.ClearSelection(fig);
		Figures.Integrate(fig, target, shapes);
		Figures.EnableUpdate(fig)
	END Integrate;
	
	PROCEDURE GetNewSelection* (frame: Frame; fig: Figures.Figure; x, y: INTEGER; VAR target, sel: Figures.Shape);
	BEGIN
		LocateShapesAt(frame, x, y, target);
		IF (target # NIL) & ~(target.sel) THEN
			Figures.DisableUpdate(fig);
			Figures.ClearSelection(fig);
			Figures.Select(fig, target);
			Figures.EnableUpdate(fig)
		END;
		Figures.GetSelection(fig, sel)
	END GetNewSelection;
	
	PROCEDURE ResetDragCtxt* (frame: Frame; fx, fy: INTEGER);
	BEGIN
		SetCoordinates(DragCtxt, fx + frame.ox, fy + frame.H + frame.oy, DragCtxt.scale);
		Gfx.Reset(DragCtxt);
		Gfx.Scale(DragCtxt, frame.scale, frame.scale)
	END ResetDragCtxt;
	
	PROCEDURE ApplyTrafo*;
		VAR id: LONGINT; obj: Objects.Object; attr: Solver.AttrNode;
	BEGIN
		id := 0; Solver.GetObject(0, obj, attr);
		WHILE obj # NIL DO
			Solver.ApplyAttr(obj, attr);
			INC(id); Solver.GetObject(id, obj, attr)
		END
	END ApplyTrafo;
	
	PROCEDURE Redraw* (fig: Figures.Figure; stamp: LONGINT);
		VAR dm: Figures.DrawMsg;
	BEGIN
		dm.stamp := stamp; dm.id := Figures.Full; dm.all := FALSE; dm.ctxt := DragCtxt; dm.mat := dm.ctxt.ctm;
		fig.handle(fig, dm)
	END Redraw;
	
	PROCEDURE DrawAlignBars* (frame: Frame; fx, fy: INTEGER; x, y: REAL);
		VAR ix, iy: INTEGER;
	BEGIN
		PointToPixel(frame, x, y, x, y);
		ix := fx + SHORT(ENTIER(x)); iy := fy + SHORT(ENTIER(y));
		Display.ReplConst(Display3.invertC, fx, iy, frame.W, 1, Display.invert);
		Display.ReplConst(Display3.invertC, ix, fy, 1, frame.H, Display.invert)
	END DrawAlignBars;
	
	PROCEDURE TrackSelection (frame: Frame; VAR msg: Oberon.InputMsg);
		VAR
			fig: Figures.Figure;
			fx, fy, mx, my, x, y: INTEGER;
			keys, keysum: SET;
			shape, sel: Figures.Shape;
			obj: Objects.Object;
			mask: Display3.Mask;
	BEGIN
		fig := frame.obj(Figures.Figure);
		fx := msg.x + frame.X; fy := msg.y + frame.Y;
		LocateShapesAt(frame, msg.X - fx, msg.Y - fy, shape);
		Input.KeyState(keys);
		IF (keys * {Input.SHIFT, Input.ALT} = {}) & ((shape = NIL) OR ~shape.sel) THEN
			Figures.ClearSelection(fig)
		END;
		IF shape # NIL THEN
			obj := shape;
			WHILE (obj.slink # NIL) & (obj.slink(Figures.Shape).cont = shape.cont) DO obj := obj.slink END;
			obj.slink := NIL;
			IF shape.sel THEN
				Figures.Deselect(fig, shape)
			ELSE
				Figures.Select(fig, shape)
			END;
			keysum := msg.keys;
			REPEAT
				Input.Mouse(keys, mx, my);
				keysum := keysum + keys;
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, mx, my)
			UNTIL keys = {};
			IF keysum = {ML, MR} THEN
				Figures.GetSelection(fig, sel);
				Figures.Delete(fig, sel)
			END
		ELSE
			Gadgets.MakeMask(frame, fx, fy, msg.dlink, mask);
			Oberon.FadeCursor(Oberon.Mouse);
			mx := msg.X; my := msg.Y; keysum := msg.keys;
			Display3.Rect(mask, Display3.invertC, Display.solid, Min(msg.X, mx), Min(msg.Y, my), ABS(msg.X - mx), ABS(msg.Y - my), 1, Display.invert);
			Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, mx, my);
			REPEAT
				Input.Mouse(keys, x, y);
				keysum := keysum + keys;
				IF (keys # {}) & ((x # mx) OR (y # my)) THEN
					Oberon.FadeCursor(Oberon.Mouse);
					Display3.Rect(mask, Display3.invertC, Display.solid, Min(msg.X, mx), Min(msg.Y, my), ABS(msg.X - mx), ABS(msg.Y - my), 1, Display.invert);
					mx := x; my := y;
					Display3.Rect(mask, Display3.invertC, Display.solid, Min(msg.X, mx), Min(msg.Y, my), ABS(msg.X - mx), ABS(msg.Y - my), 1, Display.invert);
					Oberon.DrawCursor(Oberon.Mouse, Effects.PointHand, mx, my)
				END
			UNTIL keys = {};
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.Rect(mask, Display3.invertC, Display.solid, Min(msg.X, mx), Min(msg.Y, my), ABS(msg.X - mx), ABS(msg.Y - my), 1, Display.invert);
			LocateShapesIn(frame, Min(msg.X, mx) - fx, Min(msg.Y, my) - fy, Max(msg.X, mx) - fx, Max(msg.Y, my) - fy, shape);
			Figures.DisableUpdate(fig);
			obj := shape;
			WHILE obj # NIL DO
				Figures.Select(fig, obj(Figures.Shape));
				obj := obj.slink
			END;
			IF keysum = {ML, MR} THEN
				Figures.GetSelection(fig, sel);
				Figures.Delete(fig, sel)
			END;
			Figures.EnableUpdate(fig)
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, mx, my)
	END TrackSelection;
	
	PROCEDURE GetMatrix (frame: Frame; target: Figures.Shape; x0, y0, x1, y1: REAL; VAR mat: GfxMatrix.Matrix);
		CONST
			eps = 1.0E-5;
		VAR
			cx, cy, dx0, dy0, s, dx1, dy1, ax, ay, cos, sin, u, v, cp: REAL;
			tm: Figures.TransformMsg; inv: GfxMatrix.Matrix;
	BEGIN
		IF (FocusPoints = 1) & (ToolFrame = frame) & FocusVisible THEN
			PixelToPoint(frame, FocusX[0], FocusY[0], cx, cy);
			dx0 := x0 - cx; dy0 := y0 - cy;
			s := dx0 * dx0 + dy0 * dy0;
			IF s < eps * eps THEN s := eps * eps END;
			dx1 := x1 - cx; dy1 := y1 - cy;
			s := Math.sqrt((dx1 * dx1 + dy1 * dy1)/s);
			IF FocusStyle = Rotate THEN
				GfxMatrix.Get2PointTransform(cx, cy, cx, cy, x0, y0, cx + dx1/s, cy + dy1/s, mat)
			ELSIF FocusStyle = Scale THEN
				IF dx0 * dx1 + dy0 * dy1 < 0 THEN s := -s END;
				GfxMatrix.ScaleAt(GfxMatrix.Identity, cx, cy, s, s, mat)
			ELSE	(* mirror at point *)
				GfxMatrix.ScaleAt(GfxMatrix.Identity, cx, cy, -1, -1, mat)
			END
		ELSIF (FocusPoints = 2) & (ToolFrame = frame) & FocusVisible THEN
			PixelToPoint(frame, FocusX[0], FocusY[0], cx, cy);
			PixelToPoint(frame, FocusX[1], FocusY[1], ax, ay);
			dx0 := ax - cx; dy0 := ay - cy;
			IF FocusStyle = Translate THEN
				GfxPaths.ProjectToLine(x0, y0, x0 + dx0, y0 + dy0, x1, y1, x1, y1);
				GfxMatrix.Translate(GfxMatrix.Identity, x1 - x0, y1 - y0, mat)
			ELSIF FocusStyle = Scale THEN
				s := Math.sqrt(dx0 * dx0 + dy0 * dy0);
				IF s < eps THEN s := eps END;
				cos := dx0/s; sin := dy0/s;
				dx0 := x0 - cx; dy0 := y0 - cy;
				s := dx0 * dx0 + dy0 * dy0;
				IF s < eps * eps THEN s := eps * eps END;
				dx1 := x1 - cx; dy1 := y1 - cy;
				s := Math.sqrt((dx1 * dx1 + dy1 * dy1)/s);
				IF dx0 * dx1 + dy0 * dy1 < 0 THEN s := -s END;
				GfxMatrix.RotateAt(GfxMatrix.Identity, cx, cy, sin, cos, mat);
				GfxMatrix.ScaleAt(mat, cx, cy, s, 1, mat);
				GfxMatrix.RotateAt(mat, cx, cy, -sin, cos, mat)
			ELSIF FocusStyle = Mirror THEN
				s := Math.sqrt(dx0 * dx0 + dy0 * dy0);
				IF s < eps THEN s := eps END;
				cos := dx0/s; sin := dy0/s;
				GfxMatrix.RotateAt(GfxMatrix.Identity, cx, cy, sin, cos, mat);
				GfxMatrix.ScaleAt(mat, cx, cy, 1, -1, mat);
				GfxMatrix.RotateAt(mat, cx, cy, -sin, cos, mat)
			ELSE
				GfxPaths.ProjectToLine(cx, cy, cx - dy0, cy + dx0, x0, y0, u, v);
				dx1 := x1 - cx; dy1 := y1 - cy;
				cp := dx0 * dy1 - dy0 * dx1;
				IF (-eps < cp) & (cp < 0) THEN cp := -eps
				ELSIF (0 <= cp) & (cp < eps) THEN cp := eps
				END;
				s := ((cx - u) * dy1 - (cy - v) * dx1)/cp;
				GfxMatrix.Get3PointTransform(cx, cy, cx, cy, ax, ay, ax, ay, x0, y0, u + s * dx0, v + s * dy0, mat)
			END
		ELSIF target # NIL THEN	(* let the target shape suggest a transformation *)
			tm.fig := frame.obj(Figures.Figure); tm.id := Figures.Get;
			target.handle(target, tm);
			mat := tm.mat; GfxMatrix.Invert(mat, inv);
			tm.id := Figures.Suggest;
			GfxMatrix.Apply(inv, x0, y0, tm.x0, tm.y0); GfxMatrix.Apply(inv, x1, y1, tm.x1, tm.y1);
			GfxMatrix.Translate(GfxMatrix.Identity, tm.x1 - tm.x0, tm.y1 - tm.y0, tm.mat);
			target.handle(target, tm);
			GfxMatrix.Concat(tm.mat, mat, mat); GfxMatrix.Concat(inv, mat, mat)
		ELSE
			GfxMatrix.Translate(GfxMatrix.Identity, x1 - x0, y1 - y0, mat)
		END
	END GetMatrix;
	
	PROCEDURE TrackMove (frame: Frame; VAR msg: Oberon.InputMsg);
		VAR
			fig: Figures.Figure; fx, fy, mx, my, x, y: INTEGER; target, shapes: Figures.Shape;
			keysum, keys: SET; x0, y0, x1, y1: REAL; mat: GfxMatrix.Matrix; cm: Display.ConsumeMsg;
			obj, link: Objects.Object;
	BEGIN
		fig := frame.obj(Figures.Figure);
		fx := msg.x + frame.X; fy := msg.y + frame.Y;
		GetNewSelection(frame, fig, msg.X - fx, msg.Y - fy, target, shapes);
		IF shapes = NIL THEN
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, msg.X, msg.Y);
			RETURN
		END;
		mx := -1; my := -1; keysum := msg.keys;
		PixelToPoint(frame, msg.X - fx + 0.5, msg.Y - fy + 0.5, x0, y0);
		AlignPoint(frame, x0, y0, x0, y0);
		x1 := x0; y1 := y0;
		Oberon.FadeCursor(Oberon.Mouse);
		ResetDragCtxt(frame, fx, fy);
		Figures.ComputeTrafo(fig, shapes, GfxMatrix.Identity);
		ApplyTrafo; Redraw(fig, shapes.stamp); DrawAlignBars(frame, fx, fy, x1, y1);
		REPEAT
			Input.Mouse(keys, x, y);
			keysum := keysum + keys;
			IF (keys # {}) & ((x # mx) OR (y # my)) THEN
				Oberon.FadeCursor(Oberon.Mouse);
				DrawAlignBars(frame, fx, fy, x1, y1); Redraw(fig, shapes.stamp); ApplyTrafo;
				PixelToPoint(frame, x - fx + 0.5, y - fy + 0.5, x1, y1);
				AlignPoint(frame, x0, y0, x1, y1);
				GetMatrix(frame, target, x0, y0, x1, y1, mat);
				Figures.ComputeTrafo(fig, shapes, mat);
				ApplyTrafo; Redraw(fig, shapes.stamp); DrawAlignBars(frame, fx, fy, x1, y1);
				mx := x; my := y;
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, x, y)
			END
		UNTIL keys = {};
		Oberon.FadeCursor(Oberon.Mouse);
		DrawAlignBars(frame, fx, fy, x1, y1); Redraw(fig, shapes.stamp); ApplyTrafo;
		IF keysum = {MM} THEN
			Figures.CommitTrafo(fig)
		ELSIF keysum = {MM, ML} THEN
			LocateShapesAt(frame, mx - fx, my - fy, target);
			IF target # NIL THEN
				WHILE target.sel & (target.slink # NIL) DO target := target.slink(Figures.Shape) END;
				IF target.sel THEN target := NIL END;
				Figures.GetSelection(fig, shapes)
			END;
			Figures.DisableUpdate(fig);
			Figures.BeginCommand(fig);
			Figures.CommitTrafo(fig);
			Integrate(fig, target, shapes);
			Figures.EndCommand(fig);
			Figures.EnableUpdate(fig)
		ELSIF keysum = {MM, MR} THEN
			Figures.DisableUpdate(fig);
			Gadgets.ThisFrame(mx, my, cm.F, cm.u, cm.v);
			IF cm.F = frame THEN
				Figures.CommitTrafo(fig);
				Figures.CopyShapes(shapes, shapes);
				Figures.Undo(fig);
				Integrate(fig, NIL, shapes)
			ELSE
				mat[2, 0] := mat[2, 0] - x1; mat[2, 1] := mat[2, 1] - y1;
				Figures.Transform(fig, shapes, mat);
				Figures.CopyShapes(shapes, shapes);
				obj := shapes; shapes := NIL;
				WHILE obj # NIL DO
					link := obj.slink; obj.slink := shapes; shapes := obj(Figures.Shape); obj := link
				END;
				Figures.Undo(fig);
				cm.id := Display.drop; cm.obj := shapes;
				Display.Broadcast(cm)
			END;
			Figures.EnableUpdate(fig)
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, x, y)
	END TrackMove;
	
	PROCEDURE InitFocusPatterns;
		VAR p: ARRAY 9 OF SET;
	BEGIN
		p[0] := {4}; p[1] := {4}; p[2] := {4}; p[3] := {4}; p[4] := {0..8}; p[5] := {4}; p[6] := {4}; p[7] := {4}; p[8] := {4};
		TranslatePat := Display.NewPattern(9, 9, p);
		p[0] := {3..5}; p[1] := {1..2, 6..7}; p[2] := {1, 7}; p[3] := {0, 8}; p[4] := {0, 4, 8};
		p[5] := {0, 8}; p[6] := {1, 7}; p[7] := {1..2, 6..7}; p[8] := {3..5};
		RotatePat := Display.NewPattern(9, 9, p);
		p[0] := {0, 8}; p[1] := {1, 7}; p[2] := {2, 6}; p[3] := {3, 5}; p[4] := {4};
		p[5] := {3, 5}; p[6] := {2, 6}; p[7] := {1, 7}; p[8] := {0, 8};
		ScalePat := Display.NewPattern(9, 9, p);
		p[0] := {4}; p[1] := {3, 5}; p[2] := {2, 6}; p[3] := {1, 7}; p[4] := {0, 4, 8}; p[5] := {1, 7}; p[6] := {2, 6}; p[7] := {3, 5}; p[8] := {4};
		ShearPat := Display.NewPattern(9, 9, p);
		p[0] := {0..8}; p[1] := {0..1, 7..8}; p[2] := {0, 2, 6, 8}; p[3] := {0, 3, 5, 8}; p[4] := {0, 4, 8};
		p[5] := {0, 3, 5, 8}; p[6] := {0, 2, 6, 8}; p[7] := {0..1, 7..8}; p[8] := {0..8};
		MirrorPat := Display.NewPattern(9, 9, p);
		p[0] := {0..4}; p[1] := {0, 4}; p[2] := {0, 4}; p[3] := {0, 4}; p[4] := {0..4};
		AuxPat := Display.NewPattern(5, 5, p)
	END InitFocusPatterns;
	
	PROCEDURE FlipFocus (fx, fy: INTEGER; mask: Display3.Mask);
		VAR pat: Display.Pattern; x0, y0, x1, y1: INTEGER;
	BEGIN
		IF FocusPoints > 0 THEN
			CASE FocusStyle OF
			| Translate: pat := TranslatePat
			| Rotate: pat := RotatePat
			| Scale: pat := ScalePat
			| Shear: pat := ShearPat
			| Mirror: pat := MirrorPat
			END;
			x0 := fx + SHORT(ENTIER(FocusX[0])); y0 := fy + SHORT(ENTIER(FocusY[0]));
			Display3.CopyPattern(mask, Display3.invertC, pat, x0 - 4, y0 - 4, Display.invert);
			IF FocusPoints > 1 THEN
				x1 := fx + SHORT(ENTIER(FocusX[1])); y1 := fy + SHORT(ENTIER(FocusY[1]));
				Display3.Line(mask, Display3.invertC, Display.solid, x0, y0, x1, y1, 1, Display.invert);
				Display3.CopyPattern(mask, Display3.invertC, AuxPat, x1 - 2, y1 - 2, Display.invert)
			END
		END;
		FocusVisible := ~FocusVisible
	END FlipFocus;
	
	PROCEDURE ShowFocus (fx, fy: INTEGER; mask: Display3.Mask);
	BEGIN
		IF ~FocusVisible THEN FlipFocus(fx, fy, mask) END
	END ShowFocus;
	
	PROCEDURE HideFocus (fx, fy: INTEGER; mask: Display3.Mask);
	BEGIN
		IF FocusVisible THEN FlipFocus(fx, fy, mask) END
	END HideFocus;
	
	PROCEDURE TrackFocus (frame: Frame; VAR msg: Oberon.InputMsg);
		VAR fx, fy, mx, my, x, y: INTEGER; mask: Display3.Mask; sx, sy, px, py: REAL; keys: SET;
	BEGIN
		fx := msg.x + frame.X; fy := msg.y + frame.Y;
		Oberon.RemoveMarks(fx, fy, frame.W, frame.H);
		Gadgets.MakeMask(frame, fx, fy, msg.dlink, mask);
		sx := msg.X - fx + 0.5; sy := msg.Y - fy + 0.5;
		AlignPixel(frame, sx, sy, sx, sy, px, py);
		IF ToolFrame # frame THEN
			Oberon.Defocus;
			FocusStyle := Scale; FocusVisible := FALSE;
			SetToolFrame(frame)
		ELSE
			HideFocus(fx, fy, mask);
			IF (FocusPoints > 0) & (ABS(px - FocusX[0]) <= Tolerance) & (ABS(py - FocusY[0]) <= Tolerance) THEN
				px := FocusX[0]; py := FocusY[0];
				IF FocusStyle = Translate THEN FocusStyle := Scale
				ELSIF FocusStyle = Scale THEN FocusStyle := Rotate
				ELSIF FocusStyle IN {Rotate, Shear} THEN FocusStyle := Mirror
				ELSIF FocusStyle = Mirror THEN FocusStyle := Translate
				END
			ELSE
				FocusStyle := Scale
			END
		END;
		FocusX[0] := px; FocusY[0] := py; FocusPoints := 1;
		ShowFocus(fx, fy, mask);
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, x, y);
		mx := msg.X; my := msg.Y;
		REPEAT
			Input.Mouse(keys, x, y);
			IF (keys # {}) & ((x # mx) OR (y # my)) THEN
				AlignPixel(frame, sx, sy, x - fx + 0.5, y - fy + 0.5, px, py);
				mx := x; my := y;
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, x, y)
			END
		UNTIL (keys = {}) OR (ABS(px - FocusX[0]) > Tolerance) OR (ABS(py - FocusY[0]) > Tolerance);
		IF keys # {} THEN
			Oberon.FadeCursor(Oberon.Mouse);
			FlipFocus(fx, fy, mask);
			FocusX[1] := px; FocusY[1] := py; FocusPoints := 2;
			IF FocusStyle = Rotate THEN FocusStyle := Shear END;
			FlipFocus(fx, fy, mask);
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, mx, my);
			REPEAT
				Input.Mouse(keys, x, y);
				IF (keys # {}) & ((x # mx) OR (y # my)) THEN
					Oberon.FadeCursor(Oberon.Mouse);
					FlipFocus(fx, fy, mask);
					AlignPixel(frame, sx, sy, x - fx + 0.5, y - fy + 0.5, FocusX[1], FocusY[1]);
					mx := x; my := y;
					FlipFocus(fx, fy, mask);
					Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, x, y)
				END
			UNTIL keys = {}
		ELSIF FocusStyle = Translate THEN	(* can't translate with one reference point => invisible focus *)
			Oberon.FadeCursor(Oberon.Mouse);
			FlipFocus(fx, fy, mask);
			FocusPoints := 0;
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, mx, my)
		END
	END TrackFocus;
	
	PROCEDURE Consume (frame: Frame; VAR msg: Display.ConsumeMsg);
		VAR fig: Figures.Figure; shapes, target: Figures.Shape; x, y: REAL; mat: GfxMatrix.Matrix;
	BEGIN
		IF (msg.id = Display.drop) & (msg.F = frame) & (msg.obj IS Figures.Shape) THEN
			fig := frame.obj(Figures.Figure); shapes := msg.obj(Figures.Shape);
			LocateShapesAt(frame, msg.u, msg.v + frame.H - 1, target);
			Figures.BeginCommand(fig);
			Integrate(fig, NIL, shapes);
			PixelToPoint(frame, msg.u, msg.v + frame.H - 1, x, y);
			GfxMatrix.Translate(GfxMatrix.Identity, x, y, mat);
			Figures.Transform(fig, shapes, mat);
			IF target # NIL THEN
				Figures.Delete(fig, shapes);
				Integrate(fig, target, shapes)
			END;
			Figures.EndCommand(fig)
		END
	END Consume;
	
	PROCEDURE HandleTool* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR
			frame: Frame;
			fx, fy: INTEGER;
			mask: Display3.Mask;
			fig: Figures.Figure;
			sel: Figures.Shape;
			dist: REAL;
			mat: GfxMatrix.Matrix;
	BEGIN
		frame := obj(Frame);
		IF msg IS ToolMsg THEN
			WITH msg: ToolMsg DO
				IF (msg.id = Show) & (frame = ToolFrame) THEN
					fx := msg.x + frame.X; fy := msg.y + frame.Y;
					Gadgets.MakeMask(frame, fx, fy, msg.dlink, mask);
					ShowFocus(fx, fy, mask)
				ELSIF (msg.id = Hide) & (frame = ToolFrame) THEN
					fx := msg.x + frame.X; fy := msg.y + frame.Y;
					Gadgets.MakeMask(frame, fx, fy, msg.dlink, mask);
					HideFocus(fx, fy, mask)
				END
			END
		ELSIF msg IS Oberon.InputMsg THEN
			WITH msg: Oberon.InputMsg DO
				IF msg.id = Oberon.track THEN
					IF msg.keys = {MR} THEN TrackSelection(frame, msg)
					ELSIF msg.keys = {MM} THEN TrackMove(frame, msg)
					ELSIF msg.keys = {ML} THEN TrackFocus(frame, msg)
					ELSE Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, msg.X, msg.Y)
					END;
					msg.res := 0
				ELSIF (msg.id = Oberon.consume) & (frame = ToolFrame) & (0C1X <= msg.ch) & (msg.ch <= 0C4X) THEN
					fig := frame.obj(Figures.Figure);
					Figures.GetSelection(fig, sel);
					IF sel # NIL THEN
						IF frame.align THEN dist := frame.unit/frame.subdiv ELSE dist := 1/frame.scale END;
						CASE msg.ch OF
						| 0C1X: GfxMatrix.Translate(GfxMatrix.Identity, 0, dist, mat)
						| 0C2X: GfxMatrix.Translate(GfxMatrix.Identity, 0, -dist, mat)
						| 0C3X: GfxMatrix.Translate(GfxMatrix.Identity, dist, 0, mat)
						| 0C4X: GfxMatrix.Translate(GfxMatrix.Identity, -dist, 0, mat)
						END;
						Figures.Transform(fig, sel, mat)
					END;
					msg.res := 0
				END
			END
		ELSIF msg IS Oberon.ControlMsg THEN
			WITH msg: Oberon.ControlMsg DO
				IF (msg.id = Oberon.defocus) & (frame = ToolFrame) THEN
					SetToolFrame(NIL)
				END
			END
		ELSIF msg IS Display.ConsumeMsg THEN
			Consume(frame, msg(Display.ConsumeMsg))
		ELSE
			FigureGadgets.HandleFrame(obj, msg)
		END
	END HandleTool;
	
	PROCEDURE SetDefaultTool*;
	BEGIN
		SetTool(HandleTool)
	END SetDefaultTool;
	

BEGIN
	InitMethods;
	NEW(DragCtxt); InitContext(DragCtxt);
	ToolHandle := HandleTool;
	Tolerance := 5; AlignAxes := 8;
	InitFocusPatterns
END LeoFrames.
