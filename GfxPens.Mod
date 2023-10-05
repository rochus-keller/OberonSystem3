MODULE GfxPens;	(** eos   **)
	
	(**
		Pen objects rendering on Gfx contexts.
		
		Pens offer an additional level of abstraction compared to using Gfx contexts directly. Instead of
		setting context state variables directly, clients let a pen decide which attributes have to be modified
		and/or reset. Clients therefore don't have to keep values for all context attributes either but only
		need to reference a pen object instead. In addition, pens may implement graphical effects that
		cannot be done with contexts (e.g. arrow heads) and offer a way for doing partial updates of
		paths with correct handling of dash offsets etc. Many pens use other pens for doing the
		actual rendering, effecting in complex but very flexible pen hierarchies.
	**)
	
	(*
		8.4.98 - fixed bug in splitters (didn't handle premature end of path in head part)
		15.4.98 - many bug fixes
		16.5.98 - fixed arrow bug that prevented correct rendering of arrow ends for elen > 0
		10.12.98 - adaptation to GfxMaps and release 1.01b
		26.1.99 - added line and cap styles to wide pens, pattern data to strokers and fillers; removed easy pens
		16.2.99 - bugfix in HandleEasyPen: colors stored in older versions use four bytes, not three!
	*)
	
	IMPORT
		Files, Math, Objects, Strings, Attributes, Gadgets, GfxMatrix, GfxMaps, GfxPaths, Gfx;
		
	
	CONST
		MaxSubpaths = 16;	(* maximal number of subpaths *)
		CacheSize = 4;	(* number of temporary paths *)
		
	
	TYPE
		Methods* = POINTER TO MethodBlock;
		
		(** abstract pen object for drawing on a graphical context **)
		Pen* = POINTER TO PenDesc;
		PenDesc* = RECORD (Objects.ObjDesc)
			do*: Methods;	(** pen methods **)
			ctxt*: Gfx.Context;	(** graphic context the pen is connected to **)
		END;
		
		MethodBlock* = RECORD
			(** begin and finish drawing with a pen on a context **)
			begin*: PROCEDURE (pen: Pen; ctxt: Gfx.Context);
			end*: PROCEDURE (pen: Pen);
			
			(** enter and exit subpath **)
			enter*: PROCEDURE (pen: Pen; x, y, dxi, dyi, blen: REAL);
			exit*: PROCEDURE (pen: Pen; dxo, dyo, elen: REAL);
			(**
				Concerning blen and elen: they let you enter and exit a subpath at any control point (not only the first
				one) without messing up dash offsets, which may be useful when doing partial updates of a context.
				They are also used for some less common features such as dashed arrow heads. Pass the accumulated
				length of all curves before the entry point in blen and the accumulated length of all curves after the exit
				point in elen to use this feature. Otherwise just pass 0.
			**)
			
			(** append curves to current subpath **)
			line*: PROCEDURE (pen: Pen; x, y: REAL);
			arc*: PROCEDURE (pen: Pen; x, y, x0, y0, x1, y1, x2, y2: REAL);
			bezier*: PROCEDURE (pen: Pen; x, y, x1, y1, x2, y2: REAL);
			
			(** append path structure to current path **)
			render*: PROCEDURE (pen: Pen; ctxt: Gfx.Context; VAR blen, elen: ARRAY OF REAL; n: LONGINT);
			
			(** return whether using the pen may invalidate the current path of the context **)
			destructive*: PROCEDURE (pen: Pen): BOOLEAN;
		END;
		
		(** pens dealing with different line widths (abstract) **)
		WidePen* = POINTER TO WidePenDesc;
		WidePenDesc* = RECORD (PenDesc)
			width*: REAL;
			limit*: REAL;
			capstyle*: Gfx.CapStyle;
			joinstyle*: Gfx.JoinStyle;
		END;
		
		(** pen recording the visited path **)
		Recorder* = POINTER TO RecorderDesc;
		RecorderDesc* = RECORD (PenDesc)
			path*: GfxPaths.Path;	(** recorded path **)
		END;
		
		(** basic stroking pen **)
		Stroker* = POINTER TO StrokerDesc;
		StrokerDesc* = RECORD (WidePenDesc)
			col*: Gfx.Color;
			map*: GfxMaps.Map;
			px*, py*: REAL;
		END;
		
		(** basic filling pen **)
		Filler* = POINTER TO FillerDesc;
		FillerDesc* = RECORD (PenDesc)
			col*: Gfx.Color;
			map*: GfxMaps.Map;
			px*, py*: REAL;
		END;
		
		(** pen drawing dashed curves **)
		Dasher* = POINTER TO DasherDesc;
		DasherDesc* = RECORD (PenDesc)
			base*: Pen;	(** pen for rendering dashes **)
			on*, off*, saveon, saveoff: ARRAY Gfx.MaxDashPatSize OF REAL;	(** dash pattern **)
			len*, savelen: LONGINT;	(** number of entries in the dash pattern **)
			phase*, savephase: REAL;	(** offset into pattern **)
			continuous*: BOOLEAN;	(** if true, dashes are given blen/elen according to their position within the dashed path **)
		END;
		
		(** pen splitting a path and forwarding pieces **)
		Splitter* = POINTER TO SplitterDesc;
		SplitterDesc = RECORD (PenDesc)
			head*, tail*: Pen;	(** pens for rendering begin/end of path **)
			relative*: BOOLEAN;	(** flag whether split is relative to length of path **)
			offset*: REAL;	(** absolute/relative offset from start (> 0) or end (< 0) of path **)
			blen: REAL;
		END;
		
		(** pen forwarding visited path to two pens **)
		Forker* = POINTER TO ForkerDesc;
		ForkerDesc* = RECORD (PenDesc)
			lower*, upper*: Pen;	(** pens that the visited path is forwarded to **)
			blen, elen: ARRAY MaxSubpaths OF REAL;
			n: LONGINT;
		END;
		
		(** pen reversing visited path before forwarding it **)
		Reverser* = POINTER TO ReverserDesc;
		ReverserDesc* = RECORD (PenDesc)
			base*: Pen;	(** pen for rendering reversed paths **)
			blen, elen: ARRAY MaxSubpaths OF REAL;
			n: LONGINT;
		END;
		
		(** pen replacing visited path by its outline **)
		Outliner* = POINTER TO OutlinerDesc;
		OutlinerDesc* = RECORD (WidePenDesc)
			base*: Pen;	(** pen used for rendering outlines **)
			blen: REAL;
		END;
		
		(** pen replacing visited path by outline, putting an arrow head at the end **)
		Arrow* = POINTER TO ArrowDesc;
		ArrowDesc* = RECORD (OutlinerDesc)
			len*: REAL;	(** maximal length of arrow head **)
			tan*: REAL;	(** tangent of arrow angle **)
			stem*: REAL;	(** stem width **)
			inbias*: REAL;	(** amount of curvature for outer edges **)
			fwdbias*: REAL;	(** amount of curvature for connecting edge **)
		END;
		
		EasyPen = POINTER TO EasyPenDesc;
		EasyPenDesc = RECORD (PenDesc)
			base: Pen;
		END;
		
	
	VAR
		Dummy*: Pen;	(** dummy pen (not doing anything) **)
		RecorderMethods, StrokerMethods, FillerMethods, DasherMethods, SplitterMethods, ForkerMethods,
			ReverserMethods, OutlinerMethods, ArrowMethods, EasyPenMethods: Methods;
		Path: ARRAY CacheSize OF GfxPaths.Path;	(* temporary path structures *)
		PathNo: LONGINT;	(* number of path to allocate next *)
		
	
	(**--- Pens ---**)
	
	PROCEDURE Copy* (VAR msg: Objects.CopyMsg; from, to: Pen);
	BEGIN
		to.handle := from.handle; to.do := from.do; to.ctxt := NIL
	END Copy;
	
	PROCEDURE Handle* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen: Pen;
	BEGIN
		pen := obj(Pen);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Border")
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Gen" THEN msg.class := Objects.String; msg.s := "GfxPens.New"; msg.res := 0
					ELSIF msg.name = "Border" THEN msg.class := Objects.Real; msg.x := 0; msg.res := 0
					END
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			msg(Objects.CopyMsg).obj := pen
		ELSIF msg IS Objects.BindMsg THEN
			Gadgets.BindObj(pen, msg(Objects.BindMsg).lib)
		END
	END Handle;
	
	PROCEDURE Begin* (pen: Pen; ctxt: Gfx.Context);
	BEGIN
		pen.ctxt := ctxt
	END Begin;
	
	PROCEDURE End* (pen: Pen);
	BEGIN
		pen.ctxt := NIL
	END End;
	
	PROCEDURE Enter* (pen: Pen; x, y, dxi, dyi, boff: REAL);
	BEGIN
		Gfx.Enter(pen.ctxt, x, y, dxi, dyi)
	END Enter;
	
	PROCEDURE Exit* (pen: Pen; dxo, dyo, eoff: REAL);
	BEGIN
		Gfx.Exit(pen.ctxt, dxo, dyo)
	END Exit;
	
	PROCEDURE Line* (pen: Pen; x, y: REAL);
	BEGIN
		Gfx.LineTo(pen.ctxt, x, y)
	END Line;
	
	PROCEDURE Arc* (pen: Pen; x, y, x0, y0, x1, y1, x2, y2: REAL);
	BEGIN
		Gfx.ArcTo(pen.ctxt, x, y, x0, y0, x1, y1, x2, y2)
	END Arc;
	
	PROCEDURE Bezier* (pen: Pen; x, y, x1, y1, x2, y2: REAL);
	BEGIN
		Gfx.BezierTo(pen.ctxt, x, y, x1, y1, x2, y2)
	END Bezier;
	
	PROCEDURE Destructive* (pen: Pen): BOOLEAN;
	BEGIN
		RETURN TRUE
	END Destructive;
	
	PROCEDURE NonDestructive* (pen: Pen): BOOLEAN;
	BEGIN
		RETURN FALSE
	END NonDestructive;
	
	PROCEDURE GetTempPath* (VAR path: GfxPaths.Path);
	BEGIN
		IF PathNo = CacheSize THEN
			NEW(path)
		ELSE
			IF Path[PathNo] = NIL THEN NEW(Path[PathNo]) END;
			path := Path[PathNo];
			INC(PathNo)
		END
	END GetTempPath;
	
	PROCEDURE ReleaseTempPath* (path: GfxPaths.Path);
	BEGIN
		IF path = Path[PathNo-1] THEN DEC(PathNo) END
	END ReleaseTempPath;
	
	PROCEDURE RenderPath* (pen: Pen; ctxt: Gfx.Context; VAR blen, elen: ARRAY OF REAL; n: LONGINT);
		VAR path: GfxPaths.Path; inv: GfxMatrix.Matrix; s: GfxPaths.Scanner; i: LONGINT;
	BEGIN
		IF pen.do.destructive(pen) THEN
			GetTempPath(path);
			GfxPaths.Copy(ctxt.path, path)
		ELSE
			path := ctxt.path
		END;
		GfxMatrix.Invert(ctxt.ctm, inv);
		GfxPaths.Apply(path, inv);
		pen.do.begin(pen, ctxt);
		GfxPaths.Open(s, path, 0); i := 0;
		WHILE (i < n) & (s.elem = GfxPaths.Enter) DO
			pen.do.enter(pen, s.x, s.y, s.dx, s.dy, blen[i]);
			GfxPaths.Scan(s);
			WHILE s.elem # GfxPaths.Exit DO
				IF s.elem = GfxPaths.Line THEN
					pen.do.line(pen, s.x, s.y)
				ELSIF s.elem = GfxPaths.Arc THEN
					pen.do.arc(pen, s.x, s.y, s.x0, s.y0, s.x1, s.y1, s.x2, s.y2)
				ELSIF s.elem = GfxPaths.Bezier THEN
					pen.do.bezier(pen, s.x, s.y, s.x1, s.y1, s.x2, s.y2)
				END;
				GfxPaths.Scan(s)
			END;
			pen.do.exit(pen, s.dx, s.dy, elen[i]);
			INC(i)
		END;
		pen.do.end(pen);
		IF path # ctxt.path THEN
			ReleaseTempPath(path)
		END
	END RenderPath;
	
	
	(*--- Dummy ---*)
	
	PROCEDURE EnterDummy (pen: Pen; x, y, dx, dy, blen: REAL);
	END EnterDummy;
	
	PROCEDURE ExitDummy (pen: Pen; dx, dy, elen: REAL);
	END ExitDummy;
	
	PROCEDURE DummyLine (pen: Pen; x, y: REAL);
	END DummyLine;
	
	PROCEDURE DummyArc (pen: Pen; x, y, x0, y0, x1, y1, x2, y2: REAL);
	END DummyArc;
	
	PROCEDURE DummyBezier (pen: Pen; x, y, x1, y1, x2, y2: REAL);
	END DummyBezier;
	
	PROCEDURE DummyRender (pen: Pen; ctxt: Gfx.Context; VAR blen, elen: ARRAY OF REAL; n: LONGINT);
	END DummyRender;
	
	PROCEDURE InitDummy;
		VAR do: Methods;
	BEGIN
		NEW(do);
		do.begin := Begin; do.end := End;
		do.enter := EnterDummy; do.exit := ExitDummy;
		do.line := DummyLine; do.arc := DummyArc; do.bezier := DummyBezier;
		do.render := DummyRender; do.destructive := NonDestructive;
		NEW(Dummy); Dummy.handle := Handle; Dummy.do := do
	END InitDummy;
	
	
	(**--- Wide Pens ---**)
	
	PROCEDURE CopyWidePen* (VAR msg: Objects.CopyMsg; from, to: WidePen);
	BEGIN
		Copy(msg, from, to);
		to.width := from.width; to.capstyle := from.capstyle; to.joinstyle := from.joinstyle; to.limit := from.limit
	END CopyWidePen;
	
	PROCEDURE WidePenAttr* (pen: WidePen; VAR msg: Objects.AttrMsg);
		VAR cap: Gfx.CapStyle; join: Gfx.JoinStyle;
	BEGIN
		IF msg.id = Objects.enum THEN
			msg.Enum("Width"); msg.Enum("Limit"); msg.Enum("CapStyle"); msg.Enum("JoinStyle");
			Handle(pen, msg)
		ELSIF msg.id = Objects.get THEN
			IF msg.name = "Width" THEN msg.class := Objects.Real; msg.x := pen.width; msg.res := 0
			ELSIF msg.name = "Limit" THEN msg.class := Objects.Real; msg.x := pen.limit; msg.res := 0
			ELSIF msg.name = "Border" THEN msg.class := Objects.Real; msg.x := 0.5 * pen.width * pen.limit; msg.res := 0
			ELSIF msg.name = "CapStyle" THEN
				msg.class := Objects.String; msg.s := "unknown"; msg.res := 0;
				cap := Gfx.ButtCap; IF pen.capstyle = cap THEN msg.s := "Gfx.ButtCap" END;
				cap := Gfx.RoundCap; IF pen.capstyle = cap THEN msg.s := "Gfx.RoundCap" END;
				cap := Gfx.SquareCap; IF pen.capstyle = cap THEN msg.s := "Gfx.SquareCap" END
			ELSIF msg.name = "JoinStyle" THEN
				msg.class := Objects.String; msg.s := "unknown"; msg.res := 0;
				join := Gfx.BevelJoin; IF pen.joinstyle = join THEN msg.s := "Gfx.BevelJoin" END;
				join := Gfx.RoundJoin; IF pen.joinstyle = join THEN msg.s := "Gfx.RoundJoin" END;
				join := Gfx.MiterJoin; IF pen.joinstyle = join THEN msg.s := "Gfx.MiterJoin" END
			ELSE Handle(pen, msg)
			END
		ELSIF msg.id = Objects.set THEN
			IF msg.name = "Width" THEN
				IF msg.class = Objects.Int THEN pen.width := msg.i; msg.res := 0
				ELSIF msg.class = Objects.Real THEN pen.width := msg.x; msg.res := 0
				ELSIF msg.class = Objects.LongReal THEN pen.width := SHORT(msg.y); msg.res := 0
				END
			ELSIF msg.name = "Limit" THEN
				IF msg.class = Objects.Int THEN pen.limit := msg.i; msg.res := 0
				ELSIF msg.class = Objects.Real THEN pen.limit := msg.x; msg.res := 0
				ELSIF msg.class = Objects.LongReal THEN pen.limit := SHORT(msg.y); msg.res := 0
				END
			ELSIF msg.name = "CapStyle" THEN
				IF msg.class = Objects.String THEN
					IF msg.s = "Gfx.ButtCap" THEN pen.capstyle := Gfx.ButtCap; msg.res := 0
					ELSIF msg.s = "Gfx.RoundCap" THEN pen.capstyle := Gfx.RoundCap; msg.res := 0
					ELSIF msg.s = "Gfx.SquareCap" THEN pen.capstyle := Gfx.SquareCap; msg.res := 0
					END
				END
			ELSIF msg.name = "JoinStyle" THEN
				IF msg.class = Objects.String THEN
					IF msg.s = "Gfx.BevelJoin" THEN pen.joinstyle := Gfx.BevelJoin; msg.res := 0
					ELSIF msg.s = "Gfx.RoundJoin" THEN pen.joinstyle := Gfx.RoundJoin; msg.res := 0
					ELSIF msg.s = "Gfx.MiterJoin" THEN pen.joinstyle := Gfx.MiterJoin; msg.res := 0
					END
				END
			ELSE
				Handle(pen, msg)
			END
		END
	END WidePenAttr;
	
	PROCEDURE WriteWidePen* (pen: WidePen; VAR r: Files.Rider);
		VAR s: ARRAY 32 OF CHAR; key: INTEGER;
	BEGIN
		Files.WriteNum(r, 1);
		Files.WriteReal(r, pen.width); Files.WriteReal(r, pen.limit);
		Attributes.GetString(pen, "CapStyle", s);
		Objects.GetKey(pen.lib.dict, s, key);
		Files.WriteInt(r, key);
		Attributes.GetString(pen, "JoinStyle", s);
		Objects.GetKey(pen.lib.dict, s, key);
		Files.WriteInt(r, key)
	END WriteWidePen;
	
	PROCEDURE ReadWidePen* (pen: WidePen; VAR r: Files.Rider);
		VAR ver: LONGINT; key: INTEGER; s: ARRAY 32 OF CHAR;
	BEGIN
		Files.ReadNum(r, ver);
		Files.ReadReal(r, pen.width); Files.ReadReal(r, pen.limit);
		Files.ReadInt(r, key);
		Objects.GetName(pen.lib.dict, key, s);
		Attributes.SetString(pen, "CapStyle", s);
		Files.ReadInt(r, key);
		Objects.GetName(pen.lib.dict, key, s);
		Attributes.SetString(pen, "JoinStyle", s)
	END ReadWidePen;
	
	
	(**--- Recorders ---**)
	
	PROCEDURE HandleRecorder* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen, copy: Recorder; ver: LONGINT;
	BEGIN
		pen := obj(Recorder);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF (msg.id = Objects.get) & (msg.name = "Gen") THEN
					msg.class := Objects.String; msg.s := "GfxPens.NewRecorder"; msg.res := 0
				ELSE
					Handle(pen, msg)
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # pen.stamp THEN
					NEW(copy); pen.dlink := copy; pen.stamp := msg.stamp;
					Copy(msg, pen, copy);
					copy.path := NIL
				END;
				msg.obj := pen.dlink
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver)
				END
			END
		ELSE
			Handle(pen, msg)
		END
	END HandleRecorder;
	
	PROCEDURE InitRecorder* (pen: Recorder);
	BEGIN
		pen.handle := HandleRecorder; pen.do := RecorderMethods
	END InitRecorder;
	
	PROCEDURE NewRecorder*;
		VAR pen: Recorder;
	BEGIN
		NEW(pen); InitRecorder(pen);
		Objects.NewObj := pen
	END NewRecorder;
	
	PROCEDURE BeginRecorder (pen: Pen; ctxt: Gfx.Context);
		VAR rec: Recorder;
	BEGIN
		rec := pen(Recorder);
		Begin(rec, ctxt);
		IF rec.path = NIL THEN
			NEW(rec.path)
		END;
		GfxPaths.Clear(rec.path)
	END BeginRecorder;
	
	PROCEDURE EnterRecorder (pen: Pen; x, y, dxi, dyi, blen: REAL);
	BEGIN
		GfxPaths.AddEnter(pen(Recorder).path, x, y, dxi, dyi)
	END EnterRecorder;
	
	PROCEDURE ExitRecorder (pen: Pen; dxo, dyo, elen: REAL);
	BEGIN
		GfxPaths.AddExit(pen(Recorder).path, dxo, dyo)
	END ExitRecorder;
	
	PROCEDURE RecordLine (pen: Pen; x, y: REAL);
	BEGIN
		GfxPaths.AddLine(pen(Recorder).path, x, y)
	END RecordLine;
	
	PROCEDURE RecordArc (pen: Pen; x, y, x0, y0, x1, y1, x2, y2: REAL);
	BEGIN
		GfxPaths.AddArc(pen(Recorder).path, x, y, x0, y0, x1, y1, x2, y2)
	END RecordArc;
	
	PROCEDURE RecordBezier (pen: Pen; x, y, x1, y1, x2, y2: REAL);
	BEGIN
		GfxPaths.AddBezier(pen(Recorder).path, x, y, x1, y1, x2, y2)
	END RecordBezier;
	
	PROCEDURE RecordPath (pen: Pen; ctxt: Gfx.Context; VAR blen, elen: ARRAY OF REAL; n: LONGINT);
	BEGIN
		GfxPaths.Copy(ctxt.path, pen(Recorder).path)
	END RecordPath;
	
	PROCEDURE InitRecorders;
	BEGIN
		NEW(RecorderMethods);
		RecorderMethods.begin := BeginRecorder; RecorderMethods.end := End;
		RecorderMethods.enter := EnterRecorder; RecorderMethods.exit := ExitRecorder;
		RecorderMethods.line := RecordLine; RecorderMethods.arc := RecordArc; RecorderMethods.bezier := RecordBezier;
		RecorderMethods.render := RecordPath; RecorderMethods.destructive := NonDestructive
	END InitRecorders;
	
	
	(**--- Stroker ---**)
	
	PROCEDURE HandleStroker* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen, copy: Stroker; ver: LONGINT; ch: CHAR;
	BEGIN
		pen := obj(Stroker);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Color"); msg.Enum("PinX"); msg.Enum("PinY");
					WidePenAttr(pen, msg)
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Gen" THEN msg.class := Objects.String; msg.s := "GfxPens.NewStroker"; msg.res := 0
					ELSIF msg.name = "Color" THEN
						msg.class := Objects.Int; msg.i := GfxMaps.BestIndex(GfxMaps.DisplayPal, pen.col.r, pen.col.g, pen.col.b); msg.res := 0
					ELSIF msg.name = "PinX" THEN msg.class := Objects.Real; msg.x := pen.px; msg.res := 0
					ELSIF msg.name = "PinY" THEN msg.class := Objects.Real; msg.x := pen.py; msg.res := 0
					ELSE WidePenAttr(pen, msg)
					END
				ELSIF msg.id = Objects.set THEN
					IF msg.name = "Color" THEN
						IF msg.class = Objects.Int THEN pen.col := GfxMaps.DisplayPal.col[msg.i MOD 100H]; msg.res := 0 END
					ELSIF msg.name = "PinX" THEN
						IF msg.class = Objects.Int THEN pen.px := msg.i; msg.res := 0
						ELSIF msg.class = Objects.Real THEN pen.px := msg.x; msg.res := 0
						ELSIF msg.class = Objects.LongReal THEN pen.px := SHORT(msg.y); msg.res := 0
						END
					ELSIF msg.name = "PinY" THEN
						IF msg.class = Objects.Int THEN pen.py := msg.i; msg.res := 0
						ELSIF msg.class = Objects.Real THEN pen.py := msg.x; msg.res := 0
						ELSIF msg.class = Objects.LongReal THEN pen.py := SHORT(msg.y); msg.res := 0
						END
					ELSE
						WidePenAttr(pen, msg)
					END
				END
			END
		ELSIF msg IS Objects.LinkMsg THEN
			WITH msg: Objects.LinkMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Map")
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Map" THEN msg.obj := pen.map; msg.res := 0 END
				ELSIF msg.id = Objects.set THEN
					IF msg.name = "Map" THEN
						IF msg.obj = NIL THEN pen.map := NIL; msg.res := 0
						ELSIF msg.obj IS GfxMaps.Map THEN pen.map := msg.obj(GfxMaps.Map); msg.res := 0
						END
					END
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # pen.stamp THEN
					NEW(copy); pen.dlink := copy; pen.stamp := msg.stamp;
					CopyWidePen(msg, pen, copy);
					copy.col := pen.col; copy.px := pen.px; copy.py := pen.py; copy.map := pen.map
				END;
				msg.obj := pen.dlink
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 2);
					Files.Write(msg.R, CHR(pen.col.r)); Files.Write(msg.R, CHR(pen.col.g)); Files.Write(msg.R, CHR(pen.col.b));
					WriteWidePen(pen, msg.R);
					IF pen.map = NIL THEN
						Gadgets.WriteRef(msg.R, pen.lib, NIL)
					ELSE
						Gadgets.WriteRef(msg.R, pen.lib, pen.map);
						Files.WriteReal(msg.R, pen.px); Files.WriteReal(msg.R, pen.py)
					END
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver = 1 THEN
						Files.Read(msg.R, ch); pen.col.b := ORD(ch);
						Files.Read(msg.R, ch); pen.col.g := ORD(ch);
						Files.Read(msg.R, ch); pen.col.r := ORD(ch);
						Files.Read(msg.R, ch);
						Files.ReadReal(msg.R, pen.width); pen.width := ABS(pen.width);
						pen.map := NIL
					ELSE
						Files.Read(msg.R, ch); pen.col.r := ORD(ch);
						Files.Read(msg.R, ch); pen.col.g := ORD(ch);
						Files.Read(msg.R, ch); pen.col.b := ORD(ch);
						ReadWidePen(pen, msg.R);
						Gadgets.ReadRef(msg.R, pen.lib, obj);
						IF (obj # NIL) & (obj IS GfxMaps.Map) THEN
							pen.map := obj(GfxMaps.Map);
							Files.ReadReal(msg.R, pen.px); Files.ReadReal(msg.R, pen.py)
						END
					END
				END
			END
		ELSE
			Handle(pen, msg)
		END
	END HandleStroker;
	
	PROCEDURE InitStroker* (pen: Stroker; col: Gfx.Color; width: REAL);
	BEGIN
		pen.handle := HandleStroker; pen.do := StrokerMethods;
		pen.col := col; pen.map := NIL;
		pen.width := ABS(width); pen.limit := 5; pen.capstyle := Gfx.DefaultCap; pen.joinstyle := Gfx.DefaultJoin
	END InitStroker;
	
	PROCEDURE NewStroker*;
		VAR pen: Stroker;
	BEGIN
		NEW(pen); InitStroker(pen, Gfx.Black, 1);
		Objects.NewObj := pen
	END NewStroker;
	
	PROCEDURE NewSolidStroker*;
	BEGIN
		NewStroker	(* obsolete, only kept for compatibility reasons *)
	END NewSolidStroker;
	
	PROCEDURE BeginStroker (pen: Pen; ctxt: Gfx.Context);
		VAR p: Stroker;
	BEGIN
		p := pen(Stroker);
		Begin(p, ctxt);
		Gfx.SetStrokeColor(ctxt, p.col);
		IF p.map = NIL THEN Gfx.SetStrokePattern(ctxt, NIL)
		ELSE Gfx.SetStrokePattern(ctxt, Gfx.NewPattern(ctxt, p.map, p.px, p.py))
		END;
		Gfx.SetLineWidth(ctxt, p.width); Gfx.SetStyleLimit(ctxt, p.limit);
		Gfx.SetCapStyle(ctxt, p.capstyle); Gfx.SetJoinStyle(ctxt, p.joinstyle);
		Gfx.Begin(ctxt, {Gfx.Stroke})
	END BeginStroker;
	
	PROCEDURE EndStroker (pen: Pen);
	BEGIN
		Gfx.End(pen.ctxt);
		End(pen)
	END EndStroker;
	
	PROCEDURE RenderStroker (pen: Pen; ctxt: Gfx.Context; VAR blen, elen: ARRAY OF REAL; n: LONGINT);
		VAR p: Stroker;
	BEGIN
		p := pen(Stroker);
		Gfx.SetStrokeColor(ctxt, p.col);
		IF p.map = NIL THEN Gfx.SetStrokePattern(ctxt, NIL)
		ELSE Gfx.SetStrokePattern(ctxt, Gfx.NewPattern(ctxt, p.map, p.px, p.py))
		END;
		Gfx.SetLineWidth(ctxt, p.width); Gfx.SetStyleLimit(ctxt, p.limit);
		Gfx.SetCapStyle(ctxt, p.capstyle); Gfx.SetJoinStyle(ctxt, p.joinstyle);
		Gfx.Render(ctxt, {Gfx.Stroke})
	END RenderStroker;
	
	PROCEDURE InitStrokers;
	BEGIN
		NEW(StrokerMethods);
		StrokerMethods.begin := BeginStroker; StrokerMethods.end := EndStroker;
		StrokerMethods.enter := Enter; StrokerMethods.exit := Exit;
		StrokerMethods.line := Line; StrokerMethods.arc := Arc; StrokerMethods.bezier := Bezier;
		StrokerMethods.render := RenderStroker; StrokerMethods.destructive := NonDestructive
	END InitStrokers;
	
	
	(**--- Fillers ---**)
	
	PROCEDURE HandleFiller* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen, copy: Filler; ver: LONGINT; ch: CHAR;
	BEGIN
		pen := obj(Filler);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Color"); msg.Enum("PinX"); msg.Enum("PinY");
					Handle(pen, msg)
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Gen" THEN msg.class := Objects.String; msg.s := "GfxPens.NewFiller"; msg.res := 0
					ELSIF msg.name = "Color" THEN
						msg.class := Objects.Int; msg.i := GfxMaps.BestIndex(GfxMaps.DisplayPal, pen.col.r, pen.col.g, pen.col.b); msg.res := 0
					ELSIF msg.name = "PinX" THEN msg.class := Objects.Real; msg.x := pen.px; msg.res := 0
					ELSIF msg.name = "PinY" THEN msg.class := Objects.Real; msg.x := pen.py; msg.res := 0
					ELSE Handle(pen, msg)
					END
				ELSIF msg.id = Objects.set THEN
					IF msg.name = "Color" THEN
						IF msg.class = Objects.Int THEN pen.col := GfxMaps.DisplayPal.col[msg.i MOD 100H]; msg.res := 0 END
					ELSIF msg.name = "PinX" THEN
						IF msg.class = Objects.Int THEN pen.px := msg.i; msg.res := 0
						ELSIF msg.class = Objects.Real THEN pen.px := msg.x; msg.res := 0
						ELSIF msg.class = Objects.LongReal THEN pen.px := SHORT(msg.y); msg.res := 0
						END
					ELSIF msg.name = "PinY" THEN
						IF msg.class = Objects.Int THEN pen.py := msg.i; msg.res := 0
						ELSIF msg.class = Objects.Real THEN pen.py := msg.x; msg.res := 0
						ELSIF msg.class = Objects.LongReal THEN pen.py := SHORT(msg.y); msg.res := 0
						END
					ELSE
						Handle(pen, msg)
					END
				END
			END
		ELSIF msg IS Objects.LinkMsg THEN
			WITH msg: Objects.LinkMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Map")
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Map" THEN msg.obj := pen.map; msg.res := 0 END
				ELSIF msg.id = Objects.set THEN
					IF msg.name = "Map" THEN
						IF msg.obj = NIL THEN pen.map := NIL; msg.res := 0
						ELSIF msg.obj IS GfxMaps.Map THEN pen.map := msg.obj(GfxMaps.Map); msg.res := 0
						END
					END
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # pen.stamp THEN
					NEW(copy); pen.dlink := copy; pen.stamp := msg.stamp;
					Copy(msg, pen, copy);
					copy.col := pen.col; copy.px := pen.px; copy.py := pen.py; copy.map := pen.map
				END;
				msg.obj := pen.dlink
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 2);
					Files.Write(msg.R, CHR(pen.col.r)); Files.Write(msg.R, CHR(pen.col.g)); Files.Write(msg.R, CHR(pen.col.b));
					IF pen.map = NIL THEN
						Gadgets.WriteRef(msg.R, pen.lib, NIL)
					ELSE
						Gadgets.WriteRef(msg.R, pen.lib, pen.map);
						Files.WriteReal(msg.R, pen.px); Files.WriteReal(msg.R, pen.py)
					END
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver = 1 THEN
						Files.Read(msg.R, ch); pen.col.b := ORD(ch);
						Files.Read(msg.R, ch); pen.col.g := ORD(ch);
						Files.Read(msg.R, ch); pen.col.r := ORD(ch);
						Files.Read(msg.R, ch)
					ELSE
						Files.Read(msg.R, ch); pen.col.r := ORD(ch);
						Files.Read(msg.R, ch); pen.col.g := ORD(ch);
						Files.Read(msg.R, ch); pen.col.b := ORD(ch);
						Gadgets.ReadRef(msg.R, pen.lib, obj);
						IF (obj # NIL) & (obj IS GfxMaps.Map) THEN
							pen.map := obj(GfxMaps.Map);
							Files.ReadReal(msg.R, pen.px); Files.ReadReal(msg.R, pen.py)
						END
					END
				END
			END
		ELSE
			Handle(pen, msg)
		END
	END HandleFiller;
	
	PROCEDURE InitFiller* (pen: Filler; col: Gfx.Color);
	BEGIN
		pen.handle := HandleFiller; pen.do := FillerMethods; pen.col := col
	END InitFiller;
	
	PROCEDURE NewFiller*;
		VAR pen: Filler;
	BEGIN
		NEW(pen); InitFiller(pen, Gfx.White);
		Objects.NewObj := pen
	END NewFiller;
	
	PROCEDURE NewSolidFiller*;
	BEGIN
		NewFiller	(* obsolete, only kept for compatibility reasons *)
	END NewSolidFiller;
	
	PROCEDURE BeginFiller (pen: Pen; ctxt: Gfx.Context);
		VAR p: Filler;
	BEGIN
		p := pen(Filler);
		Begin(p, ctxt);
		Gfx.SetFillColor(ctxt, p.col);
		IF p.map = NIL THEN Gfx.SetStrokePattern(ctxt, NIL)
		ELSE Gfx.SetStrokePattern(ctxt, Gfx.NewPattern(ctxt, p.map, p.px, p.py))
		END;
		Gfx.Begin(ctxt, {Gfx.Fill})
	END BeginFiller;
	
	PROCEDURE EndFiller (pen: Pen);
	BEGIN
		Gfx.End(pen.ctxt);
		End(pen)
	END EndFiller;
	
	PROCEDURE RenderFiller (pen: Pen; ctxt: Gfx.Context; VAR blen, elen: ARRAY OF REAL; n: LONGINT);
		VAR p: Filler;
	BEGIN
		p := pen(Filler);
		Gfx.SetFillColor(ctxt, p.col);
		IF p.map = NIL THEN Gfx.SetStrokePattern(ctxt, NIL)
		ELSE Gfx.SetStrokePattern(ctxt, Gfx.NewPattern(ctxt, p.map, p.px, p.py))
		END;
		Gfx.Render(ctxt, {Gfx.Fill})
	END RenderFiller;
	
	PROCEDURE InitFillers;
	BEGIN
		NEW(FillerMethods);
		FillerMethods.begin := BeginFiller; FillerMethods.end := EndFiller;
		FillerMethods.enter := Enter; FillerMethods.exit := Exit;
		FillerMethods.line := Line; FillerMethods.arc := Arc; FillerMethods.bezier := Bezier;
		FillerMethods.render := RenderFiller; FillerMethods.destructive := NonDestructive
	END InitFillers;
	
	
	(**--- Dasher ---**)
	
	PROCEDURE PatternToString (VAR on, off: ARRAY OF REAL; len: LONGINT; VAR s: ARRAY OF CHAR);
		VAR i, l, j: LONGINT; x: REAL; num: ARRAY 10 OF CHAR;
	BEGIN
		s[0] := "["; i := 1;
		l := 0;
		WHILE l < 2*len DO
			IF ODD(l) THEN x := off[l DIV 2] + 0.0005
			ELSE x := on[l DIV 2] + 0.0005
			END;
			Strings.IntToStr(ENTIER(x), num);
			j := 0; WHILE num[j] # 0X DO s[i] := num[j]; INC(i); INC(j) END;
			x := x - ENTIER(x);
			IF x >= 0.001 THEN
				s[i] := "."; INC(i);
				Strings.IntToStr(ENTIER(1000 * x), num);
				j := 0; WHILE num[j] # 0X DO s[i] := num[j]; INC(i); INC(j) END
			END;
			INC(l);
			IF l < 2*len THEN s[i] := " "; INC(i) END
		END;
		s[i] := "]"; s[i+1] := 0X
	END PatternToString;
	
	PROCEDURE StringToPattern (VAR s: ARRAY OF CHAR; VAR on, off: ARRAY OF REAL; VAR len: LONGINT);
		VAR i, j: LONGINT; num: ARRAY 32 OF CHAR; x: LONGREAL;
	BEGIN
		i := 0; len := 0;
		IF s[i] = "[" THEN INC(i) END;
		WHILE (0X < s[i]) & (s[i] <= " ") DO INC(i) END;
		WHILE ("0" <= s[i]) & (s[i] <= "9") DO
			j := 0; REPEAT num[j] := s[i]; INC(i); INC(j) UNTIL (s[i] < "0") OR ("9" < s[i]);
			IF s[i] = "." THEN
				REPEAT num[j] := s[i]; INC(i); INC(j) UNTIL (s[i] < "0") OR ("9" < s[i])
			END;
			num[j] := 0X;
			Strings.StrToReal(num, x);
			IF ODD(len) THEN off[len DIV 2] := SHORT(ABS(x))
			ELSE on[len DIV 2] := SHORT(ABS(x))
			END;
			INC(len);
			WHILE (0X < s[i]) & (s[i] <= " ") DO INC(i) END
		END;
		IF ODD(len) THEN
			off[len DIV 2] := 0; INC(len)
		END;
		len := len DIV 2
	END StringToPattern;
	
	PROCEDURE HandleDasher* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen, copy: Dasher; ver, n: LONGINT;
	BEGIN
		pen := obj(Dasher);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Pattern"); msg.Enum("Phase"); msg.Enum("Continuous");
					Handle(pen, msg)
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Gen" THEN msg.class := Objects.String; msg.s := "GfxPens.NewDasher"; msg.res := 0
					ELSIF msg.name = "Pattern" THEN msg.class := Objects.String; PatternToString(pen.on, pen.off, pen.len, msg.s); msg.res := 0
					ELSIF msg.name = "Phase" THEN msg.class := Objects.Real; msg.x := pen.phase; msg.res := 0
					ELSIF msg.name = "Continuous" THEN msg.class := Objects.Bool; msg.b := pen.continuous; msg.res := 0
					ELSIF msg.name = "Border" THEN pen.base.handle(pen.base, msg)
					ELSE Handle(pen, msg)
					END
				ELSIF msg.id = Objects.set THEN
					IF msg.name = "Pattern" THEN
						IF msg.class = Objects.String THEN StringToPattern(msg.s, pen.on, pen.off, pen.len); msg.res := 0 END
					ELSIF msg.name = "Phase" THEN
						IF msg.class = Objects.Int THEN pen.phase := msg.i; msg.res := 0
						ELSIF msg.class = Objects.Real THEN pen.phase := msg.x; msg.res := 0
						ELSIF msg.class = Objects.LongReal THEN pen.phase := SHORT(msg.y); msg.res := 0
						END
					ELSIF msg.name = "Continuous" THEN
						IF msg.class = Objects.Bool THEN pen.continuous := msg.b; msg.res := 0 END
					ELSE
						Handle(pen, msg)
					END
				END
			END
		ELSIF msg IS Objects.LinkMsg THEN
			WITH msg: Objects.LinkMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Base")
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Base" THEN msg.obj := pen.base; msg.res := 0 END
				ELSIF msg.id = Objects.set THEN
					IF (msg.name = "Base") & (msg.obj # NIL) & (msg.obj IS Pen) THEN pen.base := msg.obj(Pen); msg.res := 0 END
				END
			END
		ELSIF msg IS Objects.BindMsg THEN
			pen.base.handle(pen.base, msg);
			Handle(pen, msg)
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # pen.stamp THEN
					NEW(copy); pen.dlink := copy; pen.stamp := msg.stamp;
					Copy(msg, pen, copy);
					obj := Gadgets.CopyPtr(msg, pen.base);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					copy.base := obj(Pen);
					copy.on := pen.on; copy.off := pen.off; copy.len := pen.len;
					copy.phase := pen.phase; copy.continuous := pen.continuous
				END;
				msg.obj := pen.dlink
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					Gadgets.WriteRef(msg.R, pen.lib, pen.base);
					Files.WriteNum(msg.R, 2*pen.len);
					n := 0;
					WHILE n < pen.len DO
						Files.WriteReal(msg.R, pen.on[n]); Files.WriteReal(msg.R, pen.off[n]); INC(n)
					END;
					Files.WriteReal(msg.R, pen.phase);
					Files.WriteBool(msg.R, pen.continuous)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					Gadgets.ReadRef(msg.R, pen.lib, obj);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					pen.base := obj(Pen);
					Files.ReadNum(msg.R, pen.len); pen.len := pen.len DIV 2;
					n := 0;
					WHILE n < pen.len DO
						Files.ReadReal(msg.R, pen.on[n]); Files.ReadReal(msg.R, pen.off[n]); INC(n)
					END;
					Files.ReadReal(msg.R, pen.phase);
					Files.ReadBool(msg.R, pen.continuous)
				END
			END
		ELSE
			Handle(pen, msg)
		END
	END HandleDasher;
	
	PROCEDURE InitDasher* (pen: Dasher; base: Pen; VAR on, off: ARRAY OF REAL; len: LONGINT);
	BEGIN
		ASSERT(base # NIL, 100);
		pen.handle := HandleDasher; pen.do := DasherMethods;
		pen.base := base; pen.len := len; pen.phase := 0; pen.continuous := FALSE;
		WHILE len > 0 DO
			DEC(len); pen.on[len] := on[len]; pen.off[len] := off[len]
		END
	END InitDasher;
	
	PROCEDURE NewDasher*;
		VAR pen: Dasher;
	BEGIN
		NEW(pen); InitDasher(pen, Dummy, pen.on, pen.off, 0);
		Objects.NewObj := pen
	END NewDasher;
	
	PROCEDURE BeginDasher (pen: Pen; ctxt: Gfx.Context);
		VAR p: Dasher; n: LONGINT;
	BEGIN
		p := pen(Dasher);
		Begin(p, ctxt);
		n := 0; p.savelen := ctxt.dashPatLen; p.savephase := ctxt.dashPhase;
		WHILE n < p.savelen DO
			p.saveon[n] := ctxt.dashPatOn[n]; p.saveoff[n] := ctxt.dashPatOff[n]; INC(n)
		END
	END BeginDasher;
	
	PROCEDURE EndDasher (pen: Pen);
		VAR p: Dasher;
	BEGIN
		p := pen(Dasher);
		Gfx.SetDashPattern(p.ctxt, p.saveon, p.saveoff, p.savelen, p.savephase);
		End(p)
	END EndDasher;
	
	PROCEDURE DashSubpath (pen: Pen; blen, elen: REAL);
		VAR
			p: Dasher; ctxt: Gfx.Context; base: Pen; width, len, beg, end, next: REAL; idx: LONGINT;
			inv: GfxMatrix.Matrix; path: GfxPaths.Path; s: GfxPaths.Scanner;
	BEGIN
		p := pen(Dasher); ctxt := p.ctxt; base := p.base;
		width := ctxt.lineWidth;
		Gfx.SetLineWidth(ctxt, 0);
		len := GfxPaths.Length(ctxt.path, 1);	(* calculate complete length, including dash breaks *)
		Gfx.Outline(ctxt);	(* path is flattened at the same time *)
		IF ~GfxPaths.Empty(ctxt.path) THEN
			ctxt.cam := GfxMatrix.Identity;	(* calculate offsets in user space instead of device space *)
			Gfx.GetDashOffsets(ctxt, blen, beg, end, next, idx);
			GfxMatrix.Invert(ctxt.ctm, inv);
			GfxPaths.Apply(ctxt.path, inv);	(* transform path back to user space *)
			GfxMatrix.ApplyToDist(inv, len, len);
			Gfx.SetDashPattern(ctxt, p.on, p.off, 0, 0);	(* empty pattern *)
			IF base.do.destructive(base) THEN GetTempPath(path); GfxPaths.Copy(ctxt.path, path)
			ELSE path := ctxt.path
			END;
			GfxPaths.Open(s, path, 0);
			base.do.begin(base, ctxt);
			IF end <= blen THEN	(* subpath starts between dashes *)
				base.do.enter(base, s.x, s.y, s.dx, s.dy, next);
				len := len - (next - blen);
				idx := (idx + 1) MOD p.len;
				beg := next; end := beg + p.on[idx]; next := end + p.off[idx]
			ELSIF p.continuous THEN
				base.do.enter(base, s.x, s.y, s.dx, s.dy, blen);
				beg := blen
			ELSE
				base.do.enter(base, s.x, s.y, s.dx, s.dy, blen - beg);
				beg := blen
			END;
			GfxPaths.Scan(s);
			WHILE s.elem # GfxPaths.Stop DO
				CASE s.elem OF
				| GfxPaths.Enter:
					IF p.continuous THEN base.do.enter(base, s.x, s.y, s.dx, s.dy, beg)
					ELSE base.do.enter(base, s.x, s.y, s.dx, s.dy, 0)
					END
				| GfxPaths.Line:
					base.do.line(base, s.x, s.y)
				| GfxPaths.Exit:
					len := len - (end - beg);
					IF len > 0 THEN	(* dash end comes before end of subpath *)
						IF p.continuous THEN base.do.exit(base, s.dx, s.dy, len + elen)
						ELSE base.do.exit(base, s.dx, s.dy, 0)
						END;
						len := len - (next - end);
						idx := (idx + 1) MOD p.len;
						beg := next; end := beg + p.on[idx]; next := end + p.off[idx]
					ELSIF p.continuous THEN
						base.do.exit(base, s.dx, s.dy, elen)
					ELSE
						base.do.exit(base, s.dx, s.dy, -len)
					END
				END;
				GfxPaths.Scan(s)
			END;
			base.do.end(base);
			IF path # ctxt.path THEN
				ReleaseTempPath(path)
			END
		END;
		Gfx.SetLineWidth(ctxt, width)
	END DashSubpath;
	
	PROCEDURE EnterDasher (pen: Pen; x, y, dxi, dyi, blen: REAL);
		VAR p: Dasher; base: Pen; ctxt: Gfx.Context;
	BEGIN
		p := pen(Dasher); base := p.base; ctxt := p.ctxt;
		Gfx.SetDashPattern(ctxt, p.on, p.off, p.len, p.phase + blen);
		IF base IS Stroker THEN base.do.begin(base, ctxt)	(* render directly *)
		ELSE Gfx.Begin(ctxt, {Gfx.Record})	(* record first *)
		END;
		Gfx.Enter(p.ctxt, x, y, dxi, dyi)
	END EnterDasher;
	
	PROCEDURE ExitDasher (pen: Pen; dxo, dyo, elen: REAL);
		VAR p: Dasher; base: Pen;
	BEGIN
		p := pen(Dasher); base := p.base;
		Gfx.Exit(p.ctxt, dxo, dyo);
		IF base IS Stroker THEN
			base.do.end(base)
		ELSE
			Gfx.End(p.ctxt);
			DashSubpath(p, p.ctxt.dashPhase - p.phase, elen)
		END
	END ExitDasher;
	
	PROCEDURE RenderDasher (pen: Pen; ctxt: Gfx.Context; VAR blen, elen: ARRAY OF REAL; n: LONGINT);
		VAR p: Dasher; simple: BOOLEAN; i: LONGINT;
	BEGIN
		p := pen(Dasher); simple := p.base IS Stroker;
		IF n = 1 THEN
			BeginDasher(p, ctxt);
			Gfx.SetDashPattern(ctxt, p.on, p.off, p.len, p.phase + blen[0]);
			IF simple THEN RenderStroker(p.base, ctxt, blen, elen, 1)
			ELSE DashSubpath(p, blen[0], elen[0])
			END;
			EndDasher(p)
		ELSE
			i := 1;
			WHILE simple & (i < n) DO simple := (blen[i] = blen[0]); INC(i) END;
			IF simple THEN	(* dash phase remains constant for all subpaths *)
				BeginDasher(p, ctxt);
				Gfx.SetDashPattern(ctxt, p.on, p.off, p.len, p.phase + blen[0]);
				RenderStroker(p.base, ctxt, blen, elen, n);
				EndDasher(p)
			ELSE	(* worst case: cannot use existing path, must revisit *)
				RenderPath(p, ctxt, blen, elen, n)
			END
		END
	END RenderDasher;
	
	PROCEDURE DasherDestructive (pen: Pen): BOOLEAN;
	BEGIN
		RETURN ~(pen(Dasher).base IS Stroker)
	END DasherDestructive;
	
	PROCEDURE InitDashers;
	BEGIN
		NEW(DasherMethods);
		DasherMethods.begin := BeginDasher; DasherMethods.end := EndDasher;
		DasherMethods.enter := EnterDasher; DasherMethods.exit := ExitDasher;
		DasherMethods.line := Line; DasherMethods.arc := Arc; DasherMethods.bezier := Bezier;
		DasherMethods.render := RenderDasher; DasherMethods.destructive := DasherDestructive
	END InitDashers;
	
	
	(**--- Splitters ---**)
	
	PROCEDURE HandleSplitter* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen, copy: Splitter; bw: REAL; ver: LONGINT;
	BEGIN
		pen := obj(Splitter);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Relative"); msg.Enum("Offset");
					Handle(pen, msg)
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Gen" THEN msg.class := Objects.String; msg.s := "GfxPens.NewSplitter"; msg.res := 0
					ELSIF msg.name = "Offset" THEN msg.class := Objects.Real; msg.x := pen.offset; msg.res := 0
					ELSIF msg.name = "Relative" THEN msg.class := Objects.Bool; msg.b := pen.relative; msg.res := 0
					ELSIF msg.name = "Border" THEN
						pen.head.handle(pen.head, msg); bw := msg.x;
						pen.tail.handle(pen.tail, msg);
						IF bw > msg.x THEN msg.x := bw END
					ELSE Handle(pen, msg)
					END
				ELSIF msg.id = Objects.set THEN
					IF msg.name = "Offset" THEN
						IF msg.class = Objects.Int THEN pen.offset := msg.i; msg.res := 0
						ELSIF msg.class = Objects.Real THEN pen.offset := msg.x; msg.res := 0
						ELSIF msg.class = Objects.LongReal THEN pen.offset := SHORT(msg.y); msg.res := 0
						END;
						IF pen.relative THEN
							IF pen.offset < 0 THEN pen.offset := 0
							ELSIF pen.offset > 1 THEN pen.offset := 1
							END
						END
					ELSIF msg.name = "Relative" THEN
						IF msg.class = Objects.Bool THEN
							pen.relative := msg.b; msg.res := 0;
							IF (pen.offset < 0) OR (1 < pen.offset) THEN pen.offset := 0.5 END
						END
					ELSE
						Handle(pen, msg)
					END
				END
			END
		ELSIF msg IS Objects.LinkMsg THEN
			WITH msg: Objects.LinkMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Head"); msg.Enum("Tail")
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Head" THEN msg.obj := pen.head; msg.res := 0
					ELSIF msg.name = "Tail" THEN msg.obj := pen.tail; msg.res := 0
					END
				ELSIF msg.id = Objects.set THEN
					IF msg.name = "Head" THEN
						IF (msg.obj # NIL) & (msg.obj IS Pen) THEN pen.head := msg.obj(Pen); msg.res := 0 END
					ELSIF msg.name = "Tail" THEN
						IF (msg.obj # NIL) & (msg.obj IS Pen) THEN pen.tail := msg.obj(Pen); msg.res := 0 END
					END
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # pen.stamp THEN
					NEW(copy); pen.dlink := copy; pen.stamp := msg.stamp;
					Copy(msg, pen, copy);
					obj := Gadgets.CopyPtr(msg, pen.head);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					copy.head := obj(Pen);
					obj := Gadgets.CopyPtr(msg, pen.tail);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					copy.tail := obj(Pen);
					copy.offset := pen.offset; copy.relative := pen.relative
				END;
				msg.obj := pen.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			pen.head.handle(pen.head, msg); pen.tail.handle(pen.tail, msg);
			Handle(pen, msg)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					Gadgets.WriteRef(msg.R, pen.lib, pen.head);
					Gadgets.WriteRef(msg.R, pen.lib, pen.tail);
					Files.WriteReal(msg.R, pen.offset);
					Files.WriteBool(msg.R, pen.relative)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					Gadgets.ReadRef(msg.R, pen.lib, obj);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					pen.head := obj(Pen);
					Gadgets.ReadRef(msg.R, pen.lib, obj);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					pen.tail := obj(Pen);
					Files.ReadReal(msg.R, pen.offset);
					Files.ReadBool(msg.R, pen.relative)
				END
			END
		ELSE
			Handle(pen, msg)
		END
	END HandleSplitter;
	
	PROCEDURE InitSplitter* (pen: Splitter; head, tail: Pen; offset: REAL; relative: BOOLEAN);
	BEGIN
		ASSERT((head # NIL) & (tail # NIL), 100);
		pen.handle := HandleSplitter; pen.do := SplitterMethods;
		pen.head := head; pen.tail := tail;
		pen.offset := offset; pen.relative := relative
	END InitSplitter;
	
	PROCEDURE NewSplitter*;
		VAR pen: Splitter;
	BEGIN
		NEW(pen); InitSplitter(pen, Dummy, Dummy, 0.5, TRUE);
		Objects.NewObj := pen
	END NewSplitter;
	
	PROCEDURE SplitSubpath (pen: Splitter; blen, elen: REAL);
		VAR ctxt: Gfx.Context; path, head, tail: GfxPaths.Path; inv: GfxMatrix.Matrix; len, split, s: REAL; bl, el: ARRAY 1 OF REAL;
	BEGIN
		ctxt := pen.ctxt; path := ctxt.path;
		GfxMatrix.Invert(ctxt.ctm, inv);
		GfxMatrix.ApplyToDist(inv, GfxPaths.Length(path, 1), len);
		IF pen.relative THEN split := pen.offset * (blen + len + elen) - blen
		ELSIF pen.offset > 0 THEN split := pen.offset - blen
		ELSE split := len + elen + pen.offset
		END;
		IF split < 0 THEN
			bl[0] := blen; el[0] := elen;
			pen.tail.do.render(pen.tail, ctxt, bl, el, 1)
		ELSIF split > len THEN
			bl[0] := blen; el[0] := elen;
			pen.head.do.render(pen.head, ctxt, bl, el, 1)
		ELSE
			GetTempPath(head); GetTempPath(tail);
			GfxMatrix.ApplyToDist(ctxt.ctm, split, s);	(* back to device coordinates *)
			GfxPaths.Split(path, s, head, tail);
			ctxt.path := head; bl[0] := blen; el[0] := elen - (len - split);
			pen.head.do.render(pen.head, ctxt, bl, el, 1);
			ctxt.path := tail; bl[0] := el[0]; el[0] := elen;
			pen.tail.do.render(pen.tail, ctxt, bl, el, 1);
			ctxt.path := path;
			ReleaseTempPath(head); ReleaseTempPath(tail)
		END
	END SplitSubpath;
	
	PROCEDURE EnterSplitter (pen: Pen; x, y, dxi, dyi, blen: REAL);
		VAR p: Splitter;
	BEGIN
		p := pen(Splitter);
		Gfx.Begin(p.ctxt, {Gfx.Record});
		Gfx.Enter(p.ctxt, x, y, dxi, dyi);
		p.blen := blen
	END EnterSplitter;
	
	PROCEDURE ExitSplitter (pen: Pen; dxo, dyo, elen: REAL);
		VAR p: Splitter;
	BEGIN
		p := pen(Splitter);
		Gfx.Exit(p.ctxt, dxo, dyo);
		Gfx.End(p.ctxt);
		SplitSubpath(p, p.blen, elen)
	END ExitSplitter;
	
	PROCEDURE SplitPath (pen: Pen; ctxt: Gfx.Context; VAR blen, elen: ARRAY OF REAL; n: LONGINT);
	BEGIN
		IF n = 1 THEN
			Begin(pen, ctxt);
			SplitSubpath(pen(Splitter), blen[0], elen[0]);
			End(pen)
		ELSE
			RenderPath(pen, ctxt, blen, elen, n)
		END
	END SplitPath;
	
	PROCEDURE InitSplitters;
	BEGIN
		NEW(SplitterMethods);
		SplitterMethods.begin := Begin; SplitterMethods.end := End;
		SplitterMethods.enter := EnterSplitter; SplitterMethods.exit := ExitSplitter;
		SplitterMethods.line := Line; SplitterMethods.arc := Arc; SplitterMethods.bezier := Bezier;
		SplitterMethods.render := SplitPath; SplitterMethods.destructive := Destructive
	END InitSplitters;
	
	
	(**--- Forkers ---**)
	
	PROCEDURE HandleForker* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen, copy: Forker; bw: REAL; ver: LONGINT;
	BEGIN
		pen := obj(Forker);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF msg.id = Objects.get THEN
					IF msg.name = "Gen" THEN msg.class := Objects.String; msg.s := "GfxPens.NewForker"; msg.res := 0
					ELSIF msg.name = "Border" THEN
						pen.lower.handle(pen.lower, msg); bw := msg.x;
						pen.upper.handle(pen.upper, msg);
						IF bw > msg.x THEN msg.x := bw END
					END
				ELSE
					Handle(pen, msg)
				END
			END
		ELSIF msg IS Objects.LinkMsg THEN
			WITH msg: Objects.LinkMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Lower"); msg.Enum("Upper")
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Lower" THEN msg.obj := pen.lower; msg.res := 0
					ELSIF msg.name = "Upper" THEN msg.obj := pen.upper; msg.res := 0
					END
				ELSIF msg.id = Objects.set THEN
					IF msg.name = "Lower" THEN
						IF (msg.obj # NIL) & (msg.obj IS Pen) THEN pen.lower := msg.obj(Pen); msg.res := 0 END
					ELSIF msg.name = "Upper" THEN
						IF (msg.obj # NIL) & (msg.obj IS Pen) THEN pen.upper := msg.obj(Pen); msg.res := 0 END
					END
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # pen.stamp THEN
					NEW(copy); pen.dlink := copy; pen.stamp := msg.stamp;
					Copy(msg, pen, copy);
					obj := Gadgets.CopyPtr(msg, pen.lower);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					copy.lower := obj(Pen);
					obj := Gadgets.CopyPtr(msg, pen.upper);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					copy.upper := obj(Pen)
				END;
				msg.obj := pen.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			pen.lower.handle(pen.lower, msg); pen.upper.handle(pen.upper, msg);
			Handle(pen, msg)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					Gadgets.WriteRef(msg.R, pen.lib, pen.lower);
					Gadgets.WriteRef(msg.R, pen.lib, pen.upper)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					Gadgets.ReadRef(msg.R, pen.lib, obj);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					pen.lower := obj(Pen);
					Gadgets.ReadRef(msg.R, pen.lib, obj);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					pen.upper := obj(Pen)
				END
			END
		END
	END HandleForker;
	
	PROCEDURE InitForker* (pen: Forker; lower, upper: Pen);
	BEGIN
		ASSERT((lower # NIL) & (upper # NIL), 100);
		pen.handle := HandleForker; pen.do := ForkerMethods;
		pen.lower := lower; pen.upper := upper
	END InitForker;
	
	PROCEDURE NewForker*;
		VAR pen: Forker;
	BEGIN
		NEW(pen); InitForker(pen, Dummy, Dummy);
		Objects.NewObj := pen
	END NewForker;
	
	PROCEDURE BeginForker (pen: Pen; ctxt: Gfx.Context);
	BEGIN
		Begin(pen, ctxt);
		Gfx.Begin(ctxt, {Gfx.Record});
		pen(Forker).n := 0
	END BeginForker;
	
	PROCEDURE ForkPath (pen: Pen; ctxt: Gfx.Context; VAR blen, elen: ARRAY OF REAL; n: LONGINT);
		VAR p: Forker; path: GfxPaths.Path;
	BEGIN
		p := pen(Forker);
		IF p.lower.do.destructive(p.lower) THEN
			GetTempPath(path);
			GfxPaths.Copy(ctxt.path, path);
			p.lower.do.render(p.lower, ctxt, blen, elen, n);
			GfxPaths.Copy(path, ctxt.path);
			ReleaseTempPath(path)
		ELSE
			p.lower.do.render(p.lower, ctxt, blen, elen, n)
		END;
		p.upper.do.render(p.upper, ctxt, blen, elen, n)
	END ForkPath;
	
	PROCEDURE EndForker (pen: Pen);
		VAR p: Forker;
	BEGIN
		p := pen(Forker);
		Gfx.End(p.ctxt);
		ForkPath(p, p.ctxt, p.blen, p.elen, p.n);
		End(p)
	END EndForker;
	
	PROCEDURE EnterForker (pen: Pen; x, y, dx, dy, blen: REAL);
		VAR p: Forker;
	BEGIN
		p := pen(Forker);
		Gfx.Enter(p.ctxt, x, y, dx, dy);
		IF p.n < MaxSubpaths THEN
			p.blen[p.n] := blen
		END
	END EnterForker;
	
	PROCEDURE ExitForker (pen: Pen; dx, dy, elen: REAL);
		VAR p: Forker;
	BEGIN
		p := pen(Forker);
		Gfx.Exit(p.ctxt, dx, dy);
		IF p.n < MaxSubpaths THEN
			p.elen[p.n] := elen; INC(p.n)
		END
	END ExitForker;
	
	PROCEDURE InitForkers;
	BEGIN
		NEW(ForkerMethods);
		ForkerMethods.begin := BeginForker; ForkerMethods.end := EndForker;
		ForkerMethods.enter := EnterForker; ForkerMethods.exit := ExitForker;
		ForkerMethods.line := Line; ForkerMethods.arc := Arc; ForkerMethods.bezier := Bezier;
		ForkerMethods.render := ForkPath; ForkerMethods.destructive := Destructive
	END InitForkers;
	
	
	(**--- Reversers ---**)
	
	PROCEDURE HandleReverser* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen, copy: Reverser; ver: LONGINT;
	BEGIN
		pen := obj(Reverser);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF msg.id = Objects.get THEN
					IF msg.name = "Gen" THEN msg.class := Objects.String; msg.s := "GfxPens.NewReverser"; msg.res := 0
					ELSIF msg.name = "Border" THEN pen.base.handle(pen.base, msg)
					END
				ELSE
					Handle(pen, msg)
				END
			END
		ELSIF msg IS Objects.LinkMsg THEN
			WITH msg: Objects.LinkMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Base")
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Base" THEN msg.obj := pen.base; msg.res := 0 END
				ELSIF msg.id = Objects.set THEN
					IF msg.name = "Base" THEN
						IF (msg.obj # NIL) & (msg.obj IS Pen) THEN pen.base := msg.obj(Pen); msg.res := 0 END
					END
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # pen.stamp THEN
					NEW(copy); pen.dlink := copy; pen.stamp := msg.stamp;
					Copy(msg, pen, copy);
					obj := Gadgets.CopyPtr(msg, pen.base);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					copy.base := obj(Pen)
				END;
				msg.obj := pen.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			pen.base.handle(pen.base, msg);
			Handle(pen, msg)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					Gadgets.WriteRef(msg.R, pen.lib, pen.base)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					Gadgets.ReadRef(msg.R, pen.lib, obj);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					pen.base := obj(Pen)
				END
			END
		END
	END HandleReverser;
	
	PROCEDURE InitReverser* (pen: Reverser; base: Pen);
	BEGIN
		pen.handle := HandleReverser; pen.do := ReverserMethods;
		pen.base := base
	END InitReverser;
	
	PROCEDURE NewReverser*;
		VAR pen: Reverser;
	BEGIN
		NEW(pen); InitReverser(pen, Dummy);
		Objects.NewObj := pen
	END NewReverser;
	
	PROCEDURE ReversePath (pen: Pen; ctxt: Gfx.Context; VAR blen, elen: ARRAY OF REAL; n: LONGINT);
		VAR path: GfxPaths.Path; i, j: LONGINT; bl, el: ARRAY MaxSubpaths OF REAL; base: Pen;
	BEGIN
		GetTempPath(path);
		GfxPaths.Copy(ctxt.path, path);
		GfxPaths.Reverse(path, ctxt.path);
		ReleaseTempPath(path);
		i := 0; j := n-1;
		WHILE i < j DO
			bl[i] := elen[j]; bl[j] := elen[i];
			el[i] := blen[j]; el[j] := blen[i];
			INC(i); DEC(j)
		END;
		base := pen(Reverser).base;
		base.do.render(base, ctxt, bl, el, n)
	END ReversePath;
	
	PROCEDURE BeginReverser (pen: Pen; ctxt: Gfx.Context);
	BEGIN
		Begin(pen, ctxt);
		Gfx.Begin(ctxt, {Gfx.Record});
		pen(Reverser).n := 0
	END BeginReverser;
	
	PROCEDURE EndReverser (pen: Pen);
		VAR p: Reverser;
	BEGIN
		p := pen(Reverser);
		Gfx.End(p.ctxt);
		ReversePath(p, p.ctxt, p.blen, p.elen, p.n);
		End(p)
	END EndReverser;
	
	PROCEDURE EnterReverser (pen: Pen; x, y, dx, dy, blen: REAL);
		VAR p: Reverser;
	BEGIN
		p := pen(Reverser);
		Gfx.Enter(p.ctxt, x, y, dx, dy);
		IF p.n < LEN(p.blen) THEN
			p.blen[p.n] := blen
		END
	END EnterReverser;
	
	PROCEDURE ExitReverser (pen: Pen; dx, dy, elen: REAL);
		VAR p: Reverser;
	BEGIN
		p := pen(Reverser);
		Gfx.Exit(p.ctxt, dx, dy);
		IF p.n < LEN(p.blen) THEN
			p.elen[p.n] := elen; INC(p.n)
		END
	END ExitReverser;
	
	PROCEDURE InitReversers;
	BEGIN
		NEW(ReverserMethods);
		ReverserMethods.begin := BeginReverser; ReverserMethods.end := EndReverser;
		ReverserMethods.enter := EnterReverser; ReverserMethods.exit := ExitReverser;
		ReverserMethods.line := Line; ReverserMethods.arc := Arc; ReverserMethods.bezier := Bezier;
		ReverserMethods.render := ReversePath; ReverserMethods.destructive := Destructive
	END InitReversers;
	
	
	(**--- Outliners ---**)
	
	PROCEDURE HandleOutliner* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen, copy: Outliner; ver: LONGINT;
	BEGIN
		pen := obj(Outliner);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF msg.id = Objects.get THEN
					IF msg.name = "Gen" THEN msg.class := Objects.String; msg.s := "GfxPens.NewOutliner"; msg.res := 0
					ELSE WidePenAttr(pen, msg)
					END
				ELSE
					WidePenAttr(pen, msg)
				END
			END
		ELSIF msg IS Objects.LinkMsg THEN
			WITH msg: Objects.LinkMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Base")
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Base" THEN msg.obj := pen.base; msg.res := 0 END
				ELSIF msg.id = Objects.set THEN
					IF (msg.name = "Base") & (msg.obj # NIL) & (msg.obj IS Pen) THEN pen.base := msg.obj(Pen); msg.res := 0 END
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # pen.stamp THEN
					NEW(copy); pen.dlink := copy; pen.stamp := msg.stamp;
					CopyWidePen(msg, pen, copy);
					obj := Gadgets.CopyPtr(msg, pen.base);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					copy.base := obj(Pen);
				END;
				msg.obj := pen.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			pen.base.handle(pen.base, msg);
			Handle(pen, msg)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 2);
					Gadgets.WriteRef(msg.R, pen.lib, pen.base);
					WriteWidePen(pen, msg.R)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					Gadgets.ReadRef(msg.R, pen.lib, obj);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					pen.base := obj(Pen);
					IF ver = 1 THEN
						Files.ReadReal(msg.R, pen.width)
					ELSE
						ReadWidePen(pen, msg.R)
					END
				END
			END
		ELSE
			Handle(pen, msg)
		END
	END HandleOutliner;
	
	PROCEDURE InitOutliner* (pen: Outliner; base: Pen; width: REAL);
	BEGIN
		pen.handle := HandleOutliner; pen.do := OutlinerMethods;
		pen.base := base;
		pen.width := ABS(width); pen.limit := 5; pen.capstyle := Gfx.DefaultCap; pen.joinstyle := Gfx.DefaultJoin
	END InitOutliner;
	
	PROCEDURE NewOutliner*;
		VAR pen: Outliner;
	BEGIN
		NEW(pen); InitOutliner(pen, Dummy, 1);
		Objects.NewObj := pen
	END NewOutliner;
	
	PROCEDURE OutlinePath (pen: Pen; ctxt: Gfx.Context; VAR blen, elen: ARRAY OF REAL; n: LONGINT);
		VAR p: Outliner;
	BEGIN
		p := pen(Outliner);
		Gfx.SetLineWidth(ctxt, p.width); Gfx.SetStyleLimit(ctxt, p.limit);
		Gfx.SetCapStyle(ctxt, p.capstyle); Gfx.SetJoinStyle(ctxt, p.joinstyle);
		Gfx.Outline(ctxt);
		p.base.do.render(p.base, ctxt, blen, elen, n)
	END OutlinePath;
	
	PROCEDURE EnterOutliner (pen: Pen; x, y, dx, dy, blen: REAL);
	BEGIN
		Gfx.Begin(pen.ctxt, {Gfx.Record});
		Gfx.Enter(pen.ctxt, x, y, dx, dy);
		pen(Outliner).blen := blen
	END EnterOutliner;
	
	PROCEDURE ExitOutliner (pen: Pen; dx, dy, elen: REAL);
		VAR bl, el: ARRAY 1 OF REAL;
	BEGIN
		Gfx.Exit(pen.ctxt, dx, dy);
		Gfx.End(pen.ctxt);
		bl[0] := pen(Outliner).blen; el[0] := elen;
		OutlinePath(pen, pen.ctxt, bl, el, 1) 
	END ExitOutliner;
	
	PROCEDURE InitOutliners;
	BEGIN
		NEW(OutlinerMethods);
		OutlinerMethods.begin := Begin; OutlinerMethods.end := End;
		OutlinerMethods.enter := EnterOutliner; OutlinerMethods.exit := ExitOutliner;
		OutlinerMethods.line := Line; OutlinerMethods.arc := Arc; OutlinerMethods.bezier := Bezier;
		OutlinerMethods.render := OutlinePath; OutlinerMethods.destructive := Destructive
	END InitOutliners;
	
	
	(**--- Arrow Heads ---**)
	
	PROCEDURE HandleArrow* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR pen, copy: Arrow; t: REAL; ver: LONGINT;
	BEGIN
		pen := obj(Arrow);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Length"); msg.Enum("Angle"); msg.Enum("Stem");
					msg.Enum("InBias"); msg.Enum("FwdBias");
					HandleOutliner(pen, msg)
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Gen" THEN msg.class := Objects.String; msg.s := "GfxPens.NewArrow"; msg.res := 0
					ELSIF msg.name = "Length" THEN msg.class := Objects.Real; msg.x := pen.len; msg.res := 0
					ELSIF msg.name = "Angle" THEN msg.class := Objects.Real; msg.x := 180 * Math.arctan(pen.tan)/Math.pi; msg.res := 0
					ELSIF msg.name = "Stem" THEN msg.class := Objects.Real; msg.x := pen.stem; msg.res := 0
					ELSIF msg.name = "InBias" THEN msg.class := Objects.Real; msg.x := 100*pen.inbias; msg.res := 0
					ELSIF msg.name = "FwdBias" THEN msg.class := Objects.Real; msg.x := 100*pen.fwdbias; msg.res := 0
					ELSIF msg.name = "Border" THEN
						pen.base.handle(pen.base, msg);
						msg.x := msg.x + pen.tan * pen.len
					ELSE
						HandleOutliner(pen, msg)
					END
				ELSIF msg.id = Objects.set THEN
					IF msg.name = "Length" THEN
						IF msg.class = Objects.Int THEN pen.len := msg.i; msg.res := 0
						ELSIF msg.class = Objects.Real THEN pen.len := msg.x; msg.res := 0
						ELSIF msg.class = Objects.LongReal THEN pen.len := SHORT(msg.y); msg.res := 0
						END
					ELSIF msg.name = "Angle" THEN
						t := -1;
						IF msg.class = Objects.Int THEN t := msg.i
						ELSIF msg.class = Objects.Real THEN t := msg.x
						ELSIF msg.class = Objects.LongReal THEN t := SHORT(msg.y)
						END;
						IF (5 <= t) & (t <= 85) THEN
							t := t * (Math.pi/180); pen.tan := Math.sin(t)/Math.cos(t); msg.res := 0
						END
					ELSIF msg.name = "Stem" THEN
						IF msg.class = Objects.Int THEN pen.stem := msg.i; msg.res := 0
						ELSIF msg.class = Objects.Real THEN pen.stem := msg.x; msg.res := 0
						ELSIF msg.class = Objects.LongReal THEN pen.stem := SHORT(msg.y); msg.res := 0
						END
					ELSIF msg.name = "InBias" THEN
						t := MIN(REAL);
						IF msg.class = Objects.Int THEN t := msg.i
						ELSIF msg.class = Objects.Real THEN t := msg.x
						ELSIF msg.class = Objects.LongReal THEN t := SHORT(msg.y)
						END;
						IF ABS(t) <= 50 THEN
							pen.inbias := 0.01*t; msg.res := 0
						END
					ELSIF msg.name = "FwdBias" THEN
						t := MIN(REAL);
						IF msg.class = Objects.Int THEN t := msg.i
						ELSIF msg.class = Objects.Real THEN t := msg.x
						ELSIF msg.class = Objects.LongReal THEN t := SHORT(msg.y)
						END;
						IF ABS(t) <= 50 THEN
							pen.fwdbias := 0.01*t; msg.res := 0
						END
					ELSE
						HandleOutliner(pen, msg)
					END
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # pen.stamp THEN
					NEW(copy); pen.dlink := copy; pen.stamp := msg.stamp;
					CopyWidePen(msg, pen, copy);
					obj := Gadgets.CopyPtr(msg, pen.base);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					copy.base := obj(Pen);
					copy.len := pen.len; copy.tan := pen.tan; copy.stem := pen.stem;
					copy.inbias := pen.inbias; copy.fwdbias := pen.fwdbias
				END;
				msg.obj := pen.dlink
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 2);
					Gadgets.WriteRef(msg.R, pen.lib, pen.base);
					Files.WriteReal(msg.R, pen.len); Files.WriteReal(msg.R, pen.tan); Files.WriteReal(msg.R, pen.stem);
					Files.WriteReal(msg.R, pen.inbias); Files.WriteReal(msg.R, pen.fwdbias);
					WriteWidePen(pen, msg.R)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					Gadgets.ReadRef(msg.R, pen.lib, obj);
					IF (obj = NIL) OR ~(obj IS Pen) THEN obj := Gadgets.CreateObject("GfxPens.NewStroker") END;
					pen.base := obj(Pen);
					Files.ReadReal(msg.R, pen.len); Files.ReadReal(msg.R, pen.tan); Files.ReadReal(msg.R, pen.stem);
					IF ver > 1 THEN
						Files.ReadReal(msg.R, pen.inbias); Files.ReadReal(msg.R, pen.fwdbias);
						ReadWidePen(pen, msg.R)
					END
				END
			END
		ELSE
			Handle(pen, msg)
		END
	END HandleArrow;
	
	PROCEDURE InitArrow* (pen: Arrow; base: Pen; len, tan, stem: REAL);
		VAR width: REAL;
	BEGIN
		ASSERT(base # NIL, 100);
		Attributes.GetReal(base, "Width", width);
		InitOutliner(pen, base, width);
		pen.handle := HandleArrow; pen.do := ArrowMethods;
		pen.len := len; pen.tan := tan; pen.stem := stem; pen.inbias := 0; pen.fwdbias := 0
	END InitArrow;
	
	PROCEDURE NewArrow*;
		VAR pen: Arrow;
	BEGIN
		NEW(pen); InitArrow(pen, Dummy, 1, 0.5, 1);
		Objects.NewObj := pen
	END NewArrow;
	
	PROCEDURE GetHalfAxisVector (dxi, dyi, dxo, dyo: REAL; VAR hx, hy: REAL);
	BEGIN
		Gfx.GetHalfAxisVector(dxi, dyi, dxo, dyo, hx, hy);
		IF (hx = 0) & (hy = 0) THEN hx := dyo; hy := -dxo	(* collinear vectors *)
		ELSIF dxi * dyo < dyi * dxo THEN hx := -hx; hy := -hy	(* ensure h points to the right *)
		END
	END GetHalfAxisVector;
	
	PROCEDURE DrawArrow (pen: Arrow; blen, elen: REAL);
		CONST
			eps = 1.0E-4;
		VAR
			ctxt: Gfx.Context; path, head, tail: GfxPaths.Path;
			l, len, x0, y0, dxi, dyi, x1, y1, dx1, dy1, d1, w, hx, hy, d0, dx0, dy0, t, dxo, dyo: REAL;
			bl, el: ARRAY 1 OF REAL; inv: GfxMatrix.Matrix; base: Pen;
			s: GfxPaths.Scanner; xc, yc: ARRAY 128 OF REAL; i: LONGINT;
	BEGIN
		ctxt := pen.ctxt; path := ctxt.path;
		GfxMatrix.ApplyToDist(ctxt.ctm, pen.len - elen, l);
		len := GfxPaths.Length(path, 1);
		GetTempPath(head); GetTempPath(tail);
		GfxPaths.Split(path, len - l, head, tail);
		IF ~GfxPaths.Empty(head) THEN
			ctxt.path := head; bl[0] := blen; el[0] := pen.len;
			OutlinePath(pen, ctxt, bl, el, 1)
		END;
		IF ~GfxPaths.Empty(tail) THEN
			GfxMatrix.Invert(ctxt.ctm, inv);
			GfxPaths.Apply(tail, inv);
			len := GfxPaths.Length(tail, 1);
			GfxMatrix.ApplyToDist(inv, GfxPaths.Length(head, 1), l);
			blen := blen + l;
			base := pen.base;
			base.do.begin(base, ctxt);
			GfxPaths.Open(s, tail, 0);
			x0 := s.x; y0 := s.y; dxi := s.dx; dyi := s.dy;
			GfxPaths.Scan(s);
			x1 := s.x; y1 := s.y; dx1 := x1 - x0; dy1 := y1 - y0; d1 := Math.sqrt(dx1 * dx1 + dy1 * dy1);
			GfxPaths.Scan(s);
			w := pen.tan * len;
			IF (dxi = 0) & (dyi = 0) THEN
				hx := dy1 * w/d1; hy := -dx1 * w/d1;
				base.do.enter(base, x0, y0, dy1, -dx1, blen);
				base.do.line(base, x0 + hx, y0 + hy);
				xc[0] := x0; yc[0] := y0; i := 1
			ELSIF ABS(len - pen.len) < eps THEN
				hx := dy1 * w/d1; hy := -dx1 * w/d1;
				GfxMatrix.ApplyToDist(ctxt.ctm, pen.width, t);
				IF t <= 1 THEN dx0 := 0; dy0 := 0
				ELSE dx0 := 0.5 * pen.width * dy1/d1; dy0 := -0.5 * pen.width * dx1/d1
				END;
				base.do.enter(base, x0 + dx0, y0 + dy0, hx, hy, blen);
				base.do.line(base, x0 + hx, y0 + hy);
				xc[0] := x0 - dx0; yc[0] := y0 - dy0; i := 1
			ELSE
				d0 := Math.sqrt(dxi * dxi + dyi * dyi);
				dx0 := dxi * w/d0; dy0 := dyi * w/d0;
				GetHalfAxisVector(dx0, dy0, dx1 * w/d1, dy1 * w/d1, hx, hy);
				base.do.enter(base, x0 + hx, y0 + hy, dx0 - dy0 * pen.tan, dy0 + dx0 * pen.tan, blen);
				i := 0
			END;
			xc[i] := x0 - hx; yc[i] := y0 - hy; INC(i);
			WHILE s.elem = GfxPaths.Line DO
				len := len - d1;
				w := pen.tan * len;
				dx0 := (x1 - x0) * w/d1; dy0 := (y1 - y0) * w/d1;
				x0 := x1; y0 := y1;
				REPEAT
					x1 := s.x; y1 := s.y;
					GfxPaths.Scan(s);
					dx1 := x1 - x0; dy1 := y1 - y0; d1 := Math.sqrt(dx1 * dx1 + dy1 * dy1)
				UNTIL (s.elem # GfxPaths.Line) OR (d1 > eps);
				IF d1 > eps THEN
					dx1 := dx1 * w/d1; dy1 := dy1 * w/d1;
					GetHalfAxisVector(dx0, dy0, dx1, dy1, hx, hy);
					base.do.line(base, x0 + hx, y0 + hy);
					xc[i] := x0 - hx; yc[i] := y0 - hy; INC(i)
				END
			END;
			
			dxo := s.dx; dyo := s.dy;
			GfxPaths.Scan(s);
			IF elen = 0 THEN
				base.do.line(base, x1, y1)
			ELSE
				len := len - d1;
				w := pen.tan * len;
				dx0 := (x1 - x0) * w/d1; dy0 := (y1 - y0) * w/d1;
				IF (dxo = 0) & (dyo = 0) THEN
					base.do.line(base, x1 + dy0, y1 - dx0);
					base.do.line(base, x1 - dy0, y1 + dx0)
				ELSE
					d1 := Math.sqrt(dxo * dxo + dyo * dyo);
					dx1 := dxo * w/d1; dy1 := dyo * w/d1;
					GetHalfAxisVector(dx0, dy0, dx1, dy1, hx, hy);
					base.do.line(base, x1 + hx, y1 + hy);
					base.do.exit(base, dx1 - dy1 * pen.tan, dy1 + dx1 * pen.tan, elen);
					base.do.enter(base, x1 - hx, y1 - hy, -dx1 - dy1 * pen.tan, -dy1 + dx1 * pen.tan, elen)
				END
			END;
			
			WHILE i > 0 DO
				DEC(i);
				base.do.line(base, xc[i], yc[i])
			END;
			IF (dxi = 0) & (dyi = 0) THEN
				base.do.exit(base, xc[0] - xc[1], yc[0] - yc[1], blen)
			ELSE
				base.do.exit(base, -dxi, -dyi, blen)
			END;
			base.do.end(base)
		END;
		
		ctxt.path := path;
		ReleaseTempPath(head); ReleaseTempPath(tail)
	END DrawArrow;
	
	PROCEDURE EnterArrow (pen: Pen; x, y, dx, dy, blen: REAL);
		VAR p: Arrow;
	BEGIN
		p := pen(Arrow);
		Gfx.Begin(p.ctxt, {Gfx.Record});
		Gfx.Enter(p.ctxt, x, y, dx, dy);
		p.blen := blen
	END EnterArrow;
	
	PROCEDURE ExitArrow (pen: Pen; dx, dy, elen: REAL);
		VAR p: Arrow;
	BEGIN
		p := pen(Arrow);
		Gfx.Exit(p.ctxt, dx, dy);
		Gfx.End(p.ctxt);
		DrawArrow(p, p.blen, elen)
	END ExitArrow;
	
	PROCEDURE RenderArrow (pen: Pen; ctxt: Gfx.Context; VAR blen, elen: ARRAY OF REAL; n: LONGINT);
	BEGIN
		IF n = 1 THEN
			Begin(pen, ctxt);
			DrawArrow(pen(Arrow), blen[0], elen[0]);
			End(pen)
		ELSE
			RenderPath(pen, ctxt, blen, elen, n)
		END
	END RenderArrow;
	
	PROCEDURE InitArrows;
	BEGIN
		NEW(ArrowMethods);
		ArrowMethods.begin := Begin; ArrowMethods.end := End;
		ArrowMethods.enter := EnterArrow; ArrowMethods.exit := ExitArrow;
		ArrowMethods.line := Line; ArrowMethods.arc := Arc; ArrowMethods.bezier := Bezier;
		ArrowMethods.render := RenderArrow; ArrowMethods.destructive := NonDestructive
	END InitArrows;
	
	
	(**--- Easy Pens (Obsolete!) ---**)
	
	PROCEDURE HandleEasyPen (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR
			pen: EasyPen; ver, dlen, n: LONGINT; ch: CHAR; col, fcol: Gfx.Color; w, alen, aw, fw: REAL;
			dashed, sarr, earr, framed: BOOLEAN; don, doff: ARRAY Gfx.MaxDashPatSize OF REAL;
			fill: Filler; strk: Stroker; frk: Forker; outl: Outliner; dash: Dasher; abase: Pen; arr: Arrow; split: Splitter; rev: Reverser;
	BEGIN
		pen := obj(EasyPen);
		IF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					pen.base.handle(pen.base, msg)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver = 1 THEN
						Files.Read(msg.R, ch); col.b := ORD(ch);
						Files.Read(msg.R, ch); col.g := ORD(ch);
						Files.Read(msg.R, ch); col.r := ORD(ch);
						Files.Read(msg.R, ch)
					ELSE
						Files.Read(msg.R, ch); col.r := ORD(ch);
						Files.Read(msg.R, ch); col.g := ORD(ch);
						Files.Read(msg.R, ch); col.b := ORD(ch)
					END;
					Files.ReadReal(msg.R, w);
					Files.ReadBool(msg.R, dashed); Files.ReadNum(msg.R, dlen); dlen := dlen DIV 2;
					n := 0;
					WHILE n < dlen DO
						Files.ReadReal(msg.R, don[n]); Files.ReadReal(msg.R, doff[n]); INC(n)
					END;
					Files.ReadBool(msg.R, sarr); Files.ReadBool(msg.R, earr);
					Files.ReadReal(msg.R, alen); Files.ReadReal(msg.R, aw);
					Files.ReadBool(msg.R, framed);
					IF ver = 1 THEN
						Files.Read(msg.R, ch); fcol.b := ORD(ch);
						Files.Read(msg.R, ch); fcol.g := ORD(ch);
						Files.Read(msg.R, ch); fcol.r := ORD(ch);
						Files.Read(msg.R, ch)
					ELSE
						Files.Read(msg.R, ch); col.r := ORD(ch);
						Files.Read(msg.R, ch); col.g := ORD(ch);
						Files.Read(msg.R, ch); col.b := ORD(ch)
					END;
					Files.ReadReal(msg.R, fw);
					IF framed THEN
						NEW(fill); InitFiller(fill, col);
						NEW(strk); InitStroker(strk, fcol, fw);
						NEW(frk); InitForker(frk, fill, strk);
						NEW(outl); InitOutliner(outl, frk, w);
						pen.base := outl
					ELSE
						NEW(strk); InitStroker(strk, col, w);
						pen.base := strk
					END;
					IF dashed THEN
						NEW(dash); InitDasher(dash, pen.base, don, doff, dlen);
						pen.base := dash
					END;
					IF sarr OR earr THEN
						IF framed THEN abase := frk
						ELSE NEW(fill); InitFiller(fill, col); abase := fill
						END;
						NEW(arr); InitArrow(arr, abase, alen, 0.5*aw/alen, w)
					END;
					IF earr THEN
						NEW(split); InitSplitter(split, pen.base, arr, -alen, FALSE); pen.base := split
					END;
					IF sarr THEN
						NEW(rev); InitReverser(rev, arr);
						NEW(split); InitSplitter(split, rev, pen.base, alen, FALSE); pen.base := split
					END
				END
			END
		ELSE
			pen.base.handle(pen.base, msg)
		END
	END HandleEasyPen;
	
	PROCEDURE NewEasyPen*;
		VAR pen: EasyPen;
	BEGIN
		NEW(pen); pen.handle := HandleEasyPen; pen.do := EasyPenMethods; pen.base := Dummy;
		Objects.NewObj := pen
	END NewEasyPen;
	
	PROCEDURE BeginEasyPen (pen: Pen; ctxt: Gfx.Context);
	BEGIN
		pen.ctxt := ctxt; pen := pen(EasyPen).base; pen.do.begin(pen, ctxt)
	END BeginEasyPen;
	
	PROCEDURE EndEasyPen (pen: Pen);
	BEGIN
		pen.ctxt := NIL; pen := pen(EasyPen).base; pen.do.end(pen)
	END EndEasyPen;
	
	PROCEDURE EnterEasyPen (pen: Pen; x, y, dxi, dyi, boff: REAL);
	BEGIN
		pen := pen(EasyPen).base; pen.do.enter(pen, x, y, dxi, dyi, boff)
	END EnterEasyPen;
	
	PROCEDURE ExitEasyPen (pen: Pen; dxo, dyo, eoff: REAL);
	BEGIN
		pen := pen(EasyPen).base; pen.do.exit(pen, dxo, dyo, eoff)
	END ExitEasyPen;
	
	PROCEDURE EasyPenLine (pen: Pen; x, y: REAL);
	BEGIN
		pen := pen(EasyPen).base; pen.do.line(pen, x, y)
	END EasyPenLine;
	
	PROCEDURE EasyPenArc (pen: Pen; x, y, x0, y0, x1, y1, x2, y2: REAL);
	BEGIN
		pen := pen(EasyPen).base; pen.do.arc(pen, x, y, x0, y0, x1, y1, x2, y2)
	END EasyPenArc;
	
	PROCEDURE EasyPenBezier (pen: Pen; x, y, x1, y1, x2, y2: REAL);
	BEGIN
		pen := pen(EasyPen).base; pen.do.bezier(pen, x, y, x1, y1, x2, y2)
	END EasyPenBezier;
	
	PROCEDURE EasyPenDestructive (pen: Pen): BOOLEAN;
	BEGIN
		pen := pen(EasyPen).base;
		RETURN pen.do.destructive(pen)
	END EasyPenDestructive;
	
	PROCEDURE RenderEasyPen (pen: Pen; ctxt: Gfx.Context; VAR blen, elen: ARRAY OF REAL; n: LONGINT);
	BEGIN
		pen := pen(EasyPen).base; pen.do.render(pen, ctxt, blen, elen, n)
	END RenderEasyPen;
	
	PROCEDURE InitEasyPens;
	BEGIN
		NEW(EasyPenMethods);
		EasyPenMethods.begin := BeginEasyPen; EasyPenMethods.end := EndEasyPen;
		EasyPenMethods.enter := EnterEasyPen; EasyPenMethods.exit := ExitEasyPen;
		EasyPenMethods.line := EasyPenLine; EasyPenMethods.arc := EasyPenArc; EasyPenMethods.bezier := EasyPenBezier;
		EasyPenMethods.render := RenderEasyPen; EasyPenMethods.destructive := EasyPenDestructive
	END InitEasyPens;
	

BEGIN
	InitDummy; InitRecorders; InitStrokers; InitFillers;
	InitDashers; InitSplitters; InitForkers; InitReversers; InitOutliners; InitArrows; InitEasyPens
END GfxPens.
