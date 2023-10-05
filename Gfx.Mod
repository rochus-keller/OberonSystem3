MODULE Gfx;	(** eos   **)

	(**
		High-level, device independent, yet efficient 2D-graphics
	**)
	
	(*
		11.2.98 - changed behaviour of GetOutline if current line width is zero: calculates dashed path instead of outline (eos)
		11.2.98 - eliminated offset parameter from subpath begin since it can be simulated by modifying the dash phase
		16.2.98 - DrawPath now accepts current path
		17.2.98 - ...but only if Record is not included in mode
		17.2.98 - added RenderPath
		19.2.98 - simplified cap and join styles to procedures
		19.2.98 - eliminated clip path (was not correct, anyway), introduced GetClipRect instead
		6.3.98 - fixed bug in GetDashOutline (started last dash twice even if fully drawn)
		18.9.98 - several changes: renaming, added stroke pattern and rect/ellipse methods, text is now part of path model,
			standard colors
		9.12.98 - adaptation to new GfxMaps
		10.3.99 - separate dash pattern into on/off arrays
	*)
	
	IMPORT
		Math, Texts, Oberon, GfxMatrix, GfxMaps, GfxPaths, GfxFonts;
		
	
	CONST
		Version = "Gfx 1.30/eos 20.4.99";
		
		Record* = 0; Fill* = 1; Clip* = 2; Stroke* = 3; EvenOdd* = 4;	(** drawing mode elements **)
		InPath* = 5; InSubpath* = 6;	(** context state **)
		MaxDashPatSize* = 8;	(** maximal number of dash entries **)
		
	
	TYPE
		(** graphics context **)
		Context* = POINTER TO ContextDesc;
		
		(** color type **)
		Color* = GfxMaps.Color;
		
		(** fill patterns **)
		Pattern* = POINTER TO PatternDesc;
		PatternDesc* = RECORD
			map*: GfxMaps.Map;	(** replicated image map **)
			px*, py*: REAL;	(** pinpoint coordinates **)
		END;
		
		(** line join styles **)
		JoinStyle* = PROCEDURE (ctxt: Context; cx, cy, idx, idy, odx, ody, hx, hy: REAL; parts: SET; path: GfxPaths.Path);
			(**
				when called:
					- the path corner point is at (cx, cy), incoming direction is (idx, idy), outgoing direction is (odx, ody)
					- idx * ody > idy * odx, i.e. the path executes a left turn
					- (hx, hy) is the vector pointing from (cx, cy) to the outermost vertex of a potential miter join
					- if parts = {0}, a new outline subpath must be begun, ending at (cx + ody, cy - odx)
					- if parts = {1}, the current outline subpath, beginning at (cx + idy, cy - idx), must be ended
					- if parts = {0, 1}, lines, arcs, and beziers should be appended to the outline subpath, leading it
					  from (cx + idy, cy - idx) to (cx + ody, cy - odx)
					- the distance from any point on the outline to the original path mustn't exceed 0.5*width*styleLimit
			**)
		
		(** line cap styles **)
		CapStyle* = PROCEDURE (ctxt: Context; x, y, dx, dy: REAL; path: GfxPaths.Path; VAR dx0, dy0: REAL);
			(**
				when called:
				- the path end point is at (x, y), the (normalized to width) direction of the path is (dx, dy)
				- the current point of the outline path is at (x - dy, y + dx)
				- lines, arcs, and beziers should lead the outline path to (x + dy, y - dx)
				- the initial direction vector of the cap must be returned in (dx0, dy0)
			**)
		
		(** context methods **)
		Methods* = POINTER TO MethodBlock;
		MethodBlock* = RECORD
			(** initialization **)
			reset*: PROCEDURE (ctxt: Context);
			
			(** current transformation matrix **)
			resetCTM*: PROCEDURE (ctxt: Context);
			setCTM*: PROCEDURE (ctxt: Context; VAR mat: GfxMatrix.Matrix);
			translate*: PROCEDURE (ctxt: Context; dx, dy: REAL);
			scale*: PROCEDURE (ctxt: Context; sx, sy: REAL);
			rotate*: PROCEDURE (ctxt: Context; sin, cos: REAL);
			concat*: PROCEDURE (ctxt: Context; VAR mat: GfxMatrix.Matrix);
			
			(** clipping **)
			resetClip*: PROCEDURE (ctxt: Context);
			getClipRect*: PROCEDURE (ctxt: Context; VAR llx, lly, urx, ury: REAL);
			saveClip*: PROCEDURE (ctxt: Context);
			restoreClip*: PROCEDURE (ctxt: Context);
			
			(** graphics state **)
			setStrokeColor*: PROCEDURE (ctxt: Context; color: Color);
			setStrokePattern*: PROCEDURE (ctxt: Context; pat: Pattern);
			setFillColor*: PROCEDURE (ctxt: Context; color: Color);
			setFillPattern*: PROCEDURE (ctxt: Context; pat: Pattern);
			setLineWidth*: PROCEDURE (ctxt: Context; width: REAL);
			setDashPattern*: PROCEDURE (ctxt: Context; VAR on, off: ARRAY OF REAL; len: LONGINT; phase: REAL);
			setCapStyle*: PROCEDURE (ctxt: Context; style: CapStyle);
			setJoinStyle*: PROCEDURE (ctxt: Context; style: JoinStyle);
			setStyleLimit*: PROCEDURE (ctxt: Context; limit: REAL);
			setPoint*: PROCEDURE (ctxt: Context; x, y: REAL);
			setFlatness*: PROCEDURE (ctxt: Context; flatness: REAL);
			setFont*: PROCEDURE (ctxt: Context; font: GfxFonts.Font);
			getWidth*: PROCEDURE (ctxt: Context; VAR str: ARRAY OF CHAR; VAR dx, dy: REAL);
			
			(** current path **)
			begin*: PROCEDURE (ctxt: Context; mode: SET);
			end*: PROCEDURE (ctxt: Context);
			enter*: PROCEDURE (ctxt: Context; x, y, dx, dy: REAL);
			exit*: PROCEDURE (ctxt: Context; dx, dy: REAL);
			line*: PROCEDURE (ctxt: Context; x, y: REAL);
			arc*: PROCEDURE (ctxt: Context; x, y, x0, y0, x1, y1, x2, y2: REAL);
			bezier*: PROCEDURE (ctxt: Context; x, y, x1, y1, x2, y2: REAL);
			show*: PROCEDURE (ctxt: Context; x, y: REAL; VAR str: ARRAY OF CHAR);
			flatten*: PROCEDURE (ctxt: Context);
			outline*: PROCEDURE (ctxt: Context);
			render*: PROCEDURE (ctxt: Context; mode: SET);
			
			(** painting operators (potential for optimization) **)
			erase*: PROCEDURE (ctxt: Context);
			rect*: PROCEDURE (ctxt: Context; x0, y0, x1, y1: REAL);
			ellipse*: PROCEDURE (ctxt: Context; x, y, rx, ry: REAL);
			
			(** images and patterns **)
			image*: PROCEDURE (ctxt: Context; x, y: REAL; map: GfxMaps.Map; VAR filter: GfxMaps.Filter);
			newPattern*: PROCEDURE (ctxt: Context; map: GfxMaps.Map; px, py: REAL): Pattern;
		END;
		
		(** graphics context (continued) **)
		ContextDesc* = RECORD
			do*: Methods;	(** methods associated with context **)
			ctm*: GfxMatrix.Matrix;	(** current transformation matrix **)
			cam*: GfxMatrix.Matrix;	(** current attribute matrix (frozen ctm while inside path) **)
			strokeCol*, fillCol*: Color;	(** current stroke and fill color **)
			strokePat*, fillPat*: Pattern;	(** current stroke and fill pattern **)
			lineWidth*: REAL;	(** current line width **)
			dashPatOn*, dashPatOff*: ARRAY MaxDashPatSize OF REAL;	(** line dash array **)
			dashPatLen*: LONGINT;	(** number of valid elements in dash arrays **)
			dashPhase*: REAL;	(** offset for first dash **)
			dashPeriod*: REAL;	(** sum of dash element lengths **)
			capStyle*: CapStyle;	(** line cap style **)
			joinStyle*: JoinStyle;	(** line join style **)
			styleLimit*: REAL;	(** determines area that may be rendered to by styles **)
			mode*: SET;	(** current drawing mode **)
			path*: GfxPaths.Path;	(** current path in device coordinates (updated only if mode contains the 'Record' flag) **)
			cpx*, cpy*: REAL;	(** current point in user coordinates **)
			flatness*: REAL;	(** current flatness tolerance (in device coordinates) **)
			font*: GfxFonts.Font;	(** current font **)
		END;
		
		PathData = RECORD (GfxPaths.EnumData)
			path: GfxPaths.Path;
		END;
		
	
	VAR
		Black*, White*, Red*, Green*, Blue*, Cyan*, Magenta*, Yellow*, LGrey*, MGrey*, DGrey*: Color;	(** standard colors **)
		DefaultCap*: CapStyle;	(** default line cap style (initially butt caps) **)
		DefaultJoin*: JoinStyle;	(** default line join style (initially miter joins) **)
		DashPath: GfxPaths.Path;	(* path for temporarily storing dashes *)
		TmpPath: GfxPaths.Path;
		W: Texts.Writer;
		
	
	(**--- Contexts ---**)
	
	(** reset context to default values **)
	PROCEDURE Reset* (ctxt: Context);
	BEGIN
		ctxt.do.reset(ctxt)
	END Reset;
	
	(** deep copy of context **)
	PROCEDURE CopyContext* (from, to: Context);
		VAR n: LONGINT;
	BEGIN
		to.do := from.do;
		to.ctm := from.ctm; to.cam := from.cam;
		to.strokeCol := from.strokeCol; to.strokePat := from.strokePat; to.fillCol := from.fillCol; to.fillPat := from.fillPat;
		to.lineWidth := from.lineWidth; to.dashPatLen := from.dashPatLen;
		IF from.dashPatLen > 0 THEN
			n := 0;
			WHILE n < from.dashPatLen DO
				to.dashPatOn[n] := from.dashPatOn[n]; to.dashPatOff[n] := from.dashPatOff[n]; INC(n)
			END;
			to.dashPhase := from.dashPhase; to.dashPeriod := from.dashPeriod
		END;
		to.capStyle := from.capStyle; to.joinStyle := from.joinStyle; to.styleLimit := from.styleLimit;
		to.mode := from.mode;
		IF from.path = NIL THEN
			to.path := NIL
		ELSE
			NEW(to.path); GfxPaths.Copy(from.path, to.path)
		END;
		to.cpx := from.cpx; to.cpy := from.cpy;
		to.flatness := from.flatness;
		to.font := from.font
	END CopyContext;
	
	(** initialize context values to defaults **)
	PROCEDURE InitContextValues* (ctxt: Context);
	BEGIN
		ctxt.ctm := GfxMatrix.Identity; ctxt.cam := ctxt.ctm;
		ctxt.strokeCol := Black; ctxt.strokePat := NIL;
		ctxt.fillCol := Black; ctxt.fillPat := NIL;
		ctxt.lineWidth := 1;
		ctxt.dashPatLen := 0; ctxt.dashPhase := 0; ctxt.dashPeriod := 0;
		ctxt.capStyle := DefaultCap; ctxt.joinStyle := DefaultJoin; ctxt.styleLimit := 5;
		ctxt.mode := {};
		ctxt.path := NIL;
		ctxt.cpx := 0; ctxt.cpy := 0;
		ctxt.flatness := 1;
		ctxt.font := GfxFonts.Default
	END InitContextValues;
	
	
	(**--- Coordinate System ---**)
	
	(** reset current transformation matrix **)
	PROCEDURE ResetCTM* (ctxt: Context);
	BEGIN
		ctxt.do.resetCTM(ctxt)
	END ResetCTM;
	
	(** set current transformation matrix **)
	PROCEDURE SetCTM* (ctxt: Context; VAR mat: GfxMatrix.Matrix);
	BEGIN
		ctxt.do.setCTM(ctxt, mat)
	END SetCTM;
	
	(** translate coordinate system **)
	PROCEDURE Translate* (ctxt: Context; dx, dy: REAL);
	BEGIN
		ctxt.do.translate(ctxt, dx, dy)
	END Translate;
	
	(** scale coordinate system at origin **)
	PROCEDURE Scale* (ctxt: Context; sx, sy: REAL);
	BEGIN
		ctxt.do.scale(ctxt, sx, sy)
	END Scale;
	
	(** scale coordinate system at specified point **)
	PROCEDURE ScaleAt* (ctxt: Context; sx, sy, x, y: REAL);
	BEGIN
		ctxt.do.translate(ctxt, x, y);
		ctxt.do.scale(ctxt, sx, sy);
		ctxt.do.translate(ctxt, -x, -y)
	END ScaleAt;
	
	(** rotate coordinate system at origin **)
	PROCEDURE Rotate* (ctxt: Context; sin, cos: REAL);
	BEGIN
		ctxt.do.rotate(ctxt, sin, cos)
	END Rotate;
	
	(** rotate coordinate system at specified point **)
	PROCEDURE RotateAt* (ctxt: Context; sin, cos, x, y: REAL);
	BEGIN
		ctxt.do.translate(ctxt, x, y);
		ctxt.do.rotate(ctxt, sin, cos);
		ctxt.do.translate(ctxt, -x, -y)
	END RotateAt;
	
	(** concat transformation matrix to CTM **)
	PROCEDURE Concat* (ctxt: Context; VAR mat: GfxMatrix.Matrix);
	BEGIN
		ctxt.do.concat(ctxt, mat)
	END Concat;
	
	
	(**--- Clipping ---**)
	
	(** reset clip path **)
	PROCEDURE ResetClip* (ctxt: Context);
	BEGIN
		ctxt.do.resetClip(ctxt)
	END ResetClip;
	
	(** get bounding box of clipping path in user coordinates **)
	PROCEDURE GetClipRect* (ctxt: Context; VAR llx, lly, urx, ury: REAL);
	BEGIN
		ctxt.do.getClipRect(ctxt, llx, lly, urx, ury)
	END GetClipRect;
	
	(** temporarily save current clipping path **)
	PROCEDURE SaveClip* (ctxt: Context);
	BEGIN
		ctxt.do.saveClip(ctxt)
	END SaveClip;
	
	(** restore saved clipping path **)
	PROCEDURE RestoreClip* (ctxt: Context);
	BEGIN
		ctxt.do.restoreClip(ctxt)
	END RestoreClip;
	
	
	(**--- Graphics State ---**)
	
	(** set stroke color **)
	PROCEDURE SetStrokeColor* (ctxt: Context; color: Color);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ctxt.do.setStrokeColor(ctxt, color)
	END SetStrokeColor;
	
	(** set stroke pattern (NIL = solid) **)
	PROCEDURE SetStrokePattern* (ctxt: Context; pat: Pattern);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ctxt.do.setStrokePattern(ctxt, pat)
	END SetStrokePattern;
	
	(** set fill color **)
	PROCEDURE SetFillColor* (ctxt: Context; color: Color);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ctxt.do.setFillColor(ctxt, color)
	END SetFillColor;
	
	(** set fill pattern (NIL = solid) **)
	PROCEDURE SetFillPattern* (ctxt: Context; pat: Pattern);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ctxt.do.setFillPattern(ctxt, pat)
	END SetFillPattern;
	
	(** set line width **)
	PROCEDURE SetLineWidth* (ctxt: Context; width: REAL);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ASSERT(width >= 0.0, 101);
		ctxt.do.setLineWidth(ctxt, width)
	END SetLineWidth;
	
	(** set dash pattern **)
	PROCEDURE SetDashPattern* (ctxt: Context; VAR on, off: ARRAY OF REAL; len: LONGINT; phase: REAL);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ASSERT((len <= LEN(on)) & (len <= LEN(off)), 101);
		ctxt.do.setDashPattern(ctxt, on, off, len, phase)
	END SetDashPattern;
	
	(** copy values from parameter, and calculate dash period **)
	PROCEDURE SetDashArray* (ctxt: Context; VAR on, off: ARRAY OF REAL; len: LONGINT);
	BEGIN
		ctxt.dashPatLen := len;
		ctxt.dashPeriod := 0;
		IF len > 0 THEN
			REPEAT
				DEC(len);
				ctxt.dashPatOn[len] := on[len]; ctxt.dashPatOff[len] := off[len];
				ctxt.dashPeriod := ctxt.dashPeriod + on[len] + off[len]
			UNTIL len = 0
		END;
		ASSERT((ctxt.dashPatLen = 0) OR (ctxt.dashPeriod # 0), 120)
	END SetDashArray;
	
	(** set line cap style **)
	PROCEDURE SetCapStyle* (ctxt: Context; style: CapStyle);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ASSERT(style # NIL, 101);
		ctxt.do.setCapStyle(ctxt, style)
	END SetCapStyle;
	
	(** set line join style **)
	PROCEDURE SetJoinStyle* (ctxt: Context; style: JoinStyle);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ASSERT(style # NIL, 101);
		ctxt.do.setJoinStyle(ctxt, style)
	END SetJoinStyle;
	
	(** set style border factor **)
	PROCEDURE SetStyleLimit* (ctxt: Context; limit: REAL);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ctxt.do.setStyleLimit(ctxt, limit)
	END SetStyleLimit;
	
	(** set current point **)
	PROCEDURE SetPoint* (ctxt: Context; x, y: REAL);
	BEGIN
		ctxt.do.setPoint(ctxt, x, y)
	END SetPoint;
	
	(** set flatness parameter **)
	PROCEDURE SetFlatness* (ctxt: Context; flatness: REAL);
	BEGIN
		ctxt.do.setFlatness(ctxt, flatness)
	END SetFlatness;
	
	(** set current font **)
	PROCEDURE SetFont* (ctxt: Context; font: GfxFonts.Font);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ASSERT(font # NIL, 101);
		ctxt.do.setFont(ctxt, font)
	END SetFont;
	
	(** set current font using name and size **)
	PROCEDURE SetFontName* (ctxt: Context; fontname: ARRAY OF CHAR; size: INTEGER);
		VAR font: GfxFonts.Font;
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		font := GfxFonts.OpenSize(fontname, size);
		IF font = NIL THEN font := GfxFonts.Default END;
		ctxt.do.setFont(ctxt, font)
	END SetFontName;
	
	(** calculate distance that current point would move if given string were rendered **)
	PROCEDURE GetStringWidth* (ctxt: Context; str: ARRAY OF CHAR; VAR dx, dy: REAL);
	BEGIN
		ctxt.do.getWidth(ctxt, str, dx, dy)
	END GetStringWidth;
	
	
	(**--- Current Path ---**)
	
	(** start new path **)
	PROCEDURE Begin* (ctxt: Context; mode: SET);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ctxt.do.begin(ctxt, mode);
		INCL(ctxt.mode, InPath)
	END Begin;
	
	(** end current path **)
	PROCEDURE End* (ctxt: Context);
	BEGIN
		ASSERT((InPath IN ctxt.mode) & ~(InSubpath IN ctxt.mode), 100);
		ctxt.do.end(ctxt);
		EXCL(ctxt.mode, InPath)
	END End;
	
	(** start subpath, i.e. a sequence of connected segments **)
	PROCEDURE Enter* (ctxt: Context; x, y, dx, dy: REAL);
	BEGIN
		ASSERT((InPath IN ctxt.mode) & ~(InSubpath IN ctxt.mode), 100);
		ctxt.do.enter(ctxt, x, y, dx, dy);
		INCL(ctxt.mode, InSubpath)
	END Enter;
	
	PROCEDURE Enter0* (ctxt: Context; x, y: REAL);
	BEGIN
		ASSERT((InPath IN ctxt.mode) & ~(InSubpath IN ctxt.mode), 100);
		ctxt.do.enter(ctxt, x, y, 0, 0);
		INCL(ctxt.mode, InSubpath)
	END Enter0;
	
	(** end subpath **)
	PROCEDURE Exit* (ctxt: Context; dx, dy: REAL);
	BEGIN
		ASSERT(InSubpath IN ctxt.mode, 100);
		ctxt.do.exit(ctxt, dx, dy);
		EXCL(ctxt.mode, InSubpath)
	END Exit;
	
	PROCEDURE Exit0* (ctxt: Context);
	BEGIN
		ASSERT(InSubpath IN ctxt.mode, 100);
		ctxt.do.exit(ctxt, 0, 0);
		EXCL(ctxt.mode, InSubpath)
	END Exit0;
	
	(** append line to current path **)
	PROCEDURE LineTo* (ctxt: Context; x, y: REAL);
	BEGIN
		ASSERT(InSubpath IN ctxt.mode, 100);
		ctxt.do.line(ctxt, x, y)
	END LineTo;
	
	(** append arc to current path **)
	PROCEDURE ArcTo* (ctxt: Context; x, y, x0, y0, x1, y1, x2, y2: REAL);
	BEGIN
		ASSERT(InSubpath IN ctxt.mode, 100);
		ctxt.do.arc(ctxt, x, y, x0, y0, x1, y1, x2, y2)
	END ArcTo;
	
	(** append cubic bezier to current path **)
	PROCEDURE BezierTo* (ctxt: Context; x, y, x1, y1, x2, y2: REAL);
	BEGIN
		ASSERT(InSubpath IN ctxt.mode, 100);
		ctxt.do.bezier(ctxt, x, y, x1, y1, x2, y2)
	END BezierTo;
	
	(** append character outlines to current path at given point; advance current point to position after last character **)
	PROCEDURE ShowAt* (ctxt: Context; x, y: REAL; str: ARRAY OF CHAR);
	BEGIN
		ASSERT((InPath IN ctxt.mode) & ~(InSubpath IN ctxt.mode), 100);
		ctxt.do.show(ctxt, x, y, str)
	END ShowAt;
	
	(** append character outlines to current path at current point; advance current point to position after last character **)
	PROCEDURE Show* (ctxt: Context; str: ARRAY OF CHAR);
	BEGIN
		ASSERT((InPath IN ctxt.mode) & ~(InSubpath IN ctxt.mode), 100);
		ctxt.do.show(ctxt, ctxt.cpx, ctxt.cpy, str)
	END Show;
	
	
	(**--- Path Flattening ---**)
	
	(** replace arcs and beziers in current path by approximation using straight lines **)
	PROCEDURE Flatten* (ctxt: Context);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ctxt.do.flatten(ctxt)
	END Flatten;
	
	PROCEDURE EnumPathElem (VAR data: GfxPaths.EnumData);
	BEGIN
		WITH data: PathData DO
			CASE data.elem OF
			| GfxPaths.Enter: GfxPaths.AddEnter(data.path, data.x, data.y, data.dx, data.dy)
			| GfxPaths.Line: GfxPaths.AddLine(data.path, data.x, data.y)
			| GfxPaths.Exit: GfxPaths.AddExit(data.path, data.dx, data.dy)
			END
		END
	END EnumPathElem;
	
	(** store flattened current path in given path  **)
	PROCEDURE GetFlattenedPath* (ctxt: Context; path: GfxPaths.Path);
		VAR data: PathData;
	BEGIN
		ASSERT(ctxt.path # path, 100);
		GfxPaths.Clear(path);
		data.path := path;
		GfxPaths.EnumFlattened(ctxt.path, ctxt.flatness, EnumPathElem, data)
	END GetFlattenedPath;
	
	
	(**--- Path Outline ---**)
	
	(** replace current path by outline of area which would be drawn to if the path were stroked **)
	PROCEDURE Outline* (ctxt: Context);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ctxt.do.outline(ctxt)
	END Outline;
	
	(** return vector scaled to given length **)
	PROCEDURE GetNormVector* (x, y, len: REAL; VAR nx, ny: REAL);
		VAR t: REAL;
	BEGIN
		t := len/Math.sqrt(x * x + y * y);
		nx := t * x; ny := t * y
	END GetNormVector;
	
	(** return vector to outer corner of two joining vectors whose lengths correspond to line width **)
	PROCEDURE GetHalfAxisVector* (idx, idy, odx, ody: REAL; VAR hx, hy: REAL);
		VAR cprod, t: REAL;
	BEGIN
		cprod := idx * ody - idy * odx;
		IF ABS(cprod) < 1.0E-3 THEN
			hx := 0; hy := 0
		ELSE	(* intersect outer border lines to find half axis vector *)
			t := ((idy - ody) * ody + (idx - odx) * odx)/cprod;
			IF cprod > 0 THEN	(* left turn *)
				hx := idy - t * idx; hy := -(idx + t * idy)
			ELSE	(* right turn *)
				hx := t * idx - idy; hy := idx + t * idy
			END
		END
	END GetHalfAxisVector;
	
	PROCEDURE GetPolyOutline (ctxt: Context; VAR x, y: ARRAY OF REAL; n: LONGINT; dxi, dyi, dxo, dyo: REAL; dst: GfxPaths.Path);
		VAR width, odx, ody, dx0, dy0, idx, idy, hx, hy, dx1, dy1: REAL; i, j: LONGINT;
	BEGIN
		GfxMatrix.ApplyToDist(ctxt.cam, 0.5*ctxt.lineWidth, width);
		GetNormVector(x[1] - x[0], y[1] - y[0], width, odx, ody);
		IF (dxi = 0) & (dyi = 0) THEN
			GfxPaths.AddEnter(dst, x[0] - ody, y[0] + odx, x[0] - x[1], y[0] - y[1]);
			ctxt.capStyle(ctxt, x[0], y[0], odx, ody, dst, dx0, dy0);
		ELSE
			GetNormVector(dxi, dyi, width, idx, idy);
			GetHalfAxisVector(idx, idy, odx, ody, hx, hy);
			IF (hx = 0) & (hy = 0) THEN	(* collinear vectors *)
				GfxPaths.AddEnter(dst, x[0] + ody, y[0] - odx, dxi, dyi)
			ELSIF idx * ody > idy * odx THEN	(* starts with left turn *)
				ctxt.joinStyle(ctxt, x[0], y[0], idx, idy, odx, ody, hx, hy, {0}, dst)
			ELSE
				GfxPaths.AddEnter(dst, x[0] - hx, y[0] - hy, dxi, dyi)
			END
		END;
		i := 1; j := 2;
		WHILE j <= n DO
			idx := odx; idy := ody;
			GetNormVector(x[j] - x[i], y[j] - y[i], width, odx, ody);
			GetHalfAxisVector(idx, idy, odx, ody, hx, hy);
			IF (hx = 0) & (hy = 0) THEN	(* collinear vectors *)
				GfxPaths.AddLine(dst, x[i] + idy, y[i] - idx)
			ELSIF idx * ody > idy * odx THEN	(* left turn => outer join *)
				GfxPaths.AddLine(dst, x[i] + idy, y[i] - idx);
				ctxt.joinStyle(ctxt, x[i], y[i], idx, idy, odx, ody, hx, hy, {0, 1}, dst)
			ELSE	(* right turn => inner join *)
				GfxPaths.AddLine(dst, x[i] - hx, y[i] - hy)
			END;
			i := j; INC(j)
		END;
		idx := odx; idy := ody;
		IF (dxo = 0) & (dyo = 0) THEN
			GfxPaths.AddLine(dst, x[n] + ody, y[n] - odx);
			ctxt.capStyle(ctxt, x[n], y[n], -odx, -ody, dst, dx1, dy1)
		ELSE
			GetNormVector(dxo, dyo, width, odx, ody);
			GetHalfAxisVector(idx, idy, odx, ody, hx, hy);
			IF (hx = 0) & (hy = 0) THEN	(* collinear vectors *)
				GfxPaths.AddLine(dst, x[n] + idy, y[n] - idx);
				GfxPaths.AddExit(dst, odx, ody);
				GfxPaths.AddEnter(dst, x[n] - idy, y[n] + idx, -dxo, -dyo)
			ELSIF idx * ody > idy * odx THEN	(* ends in left turn *)
				GfxPaths.AddLine(dst, x[n] + idy, y[n] - idx);
				ctxt.joinStyle(ctxt, x[n], y[n], idx, idy, odx, ody, hx, hy, {1}, dst);
				GfxPaths.AddEnter(dst, x[n] - hx, y[n] - hy, -dxo, -dyo)
			ELSE
				GfxPaths.AddLine(dst, x[n] - hx, y[n] - hy);
				GfxPaths.AddExit(dst, dxo, dyo);
				ctxt.joinStyle(ctxt, x[n], y[n], -odx, -ody, -idx, -idy, -hx, -hy, {0}, dst)
			END
		END;
		odx := -idx; ody := -idy;
		i := n-1; j := n-2;
		WHILE j >= 0 DO
			idx := odx; idy := ody;
			GetNormVector(x[j] - x[i], y[j] - y[i], width, odx, ody);
			GetHalfAxisVector(idx, idy, odx, ody, hx, hy);
			IF (hx = 0) & (hy = 0) THEN	(* collinear vectors *)
				GfxPaths.AddLine(dst, x[i] + idy, y[i] - idx)
			ELSIF idx * ody > idy * odx THEN	(* left turn => outer join *)
				GfxPaths.AddLine(dst, x[i] + idy, y[i] - idx);
				ctxt.joinStyle(ctxt, x[i], y[i], idx, idy, odx, ody, hx, hy, {0, 1}, dst)
			ELSE	(* right turn => inner join *)
				GfxPaths.AddLine(dst, x[i] - hx, y[i] - hy)
			END;
			i := j; DEC(j)
		END;
		IF (dxi = 0) & (dyi = 0) THEN
			GfxPaths.AddLine(dst, x[0] + ody, y[0] - odx);
			GfxPaths.AddExit(dst, dx0, dy0)
		ELSE
			idx := odx; idy := ody;
			GetNormVector(-dxi, -dyi, width, odx, ody);
			GetHalfAxisVector(idx, idy, odx, ody, hx, hy);
			IF (hx = 0) & (hy = 0) THEN	(* collinear vectors *)
				GfxPaths.AddLine(dst, x[0] + idy, y[0] - idx);
				GfxPaths.AddExit(dst, -dxi, -dyi)
			ELSIF idx * ody > idy * odx THEN	(* left turn *)
				GfxPaths.AddLine(dst, x[0] + idy, y[0] - idx);
				ctxt.joinStyle(ctxt, x[0], y[0], idx, idy, odx, ody, hx, hy, {1}, dst)
			ELSE
				GfxPaths.AddLine(dst, x[0] - hx, y[0] - hy);
				GfxPaths.AddExit(dst, -dxi, -dyi)
			END
		END
	END GetPolyOutline;
	
	PROCEDURE GetStrokeOutline (ctxt: Context; VAR scan: GfxPaths.Scanner; dst: GfxPaths.Path);
		CONST last = 127;
		VAR x, y: ARRAY last+1 OF REAL; dxi, dyi, dxo, dyo: REAL; n: LONGINT;
	BEGIN
		ASSERT(scan.elem = GfxPaths.Enter);
		x[0] := scan.x; y[0] := scan.y; dxi := scan.dx; dyi := scan.dy;
		GfxPaths.Scan(scan); n := 0;
		WHILE scan.elem = GfxPaths.Line DO
			IF n < last THEN
				INC(n); x[n] := scan.x; y[n] := scan.y
			ELSE
				dxo := scan.x - x[n]; dyo := scan.y - y[n];
				GetPolyOutline(ctxt, x, y, n, dxi, dyi, dxo, dyo, dst);
				dxi := x[n] - x[n-1]; dyi := y[n] - y[n-1];
				x[0] := x[n]; y[0] := y[n];
				x[1] := scan.x; y[1] := scan.y;
				n := 1
			END;
			GfxPaths.Scan(scan)
		END;
		IF n > 0 THEN
			GetPolyOutline(ctxt, x, y, n, dxi, dyi, scan.dx, scan.dy, dst)
		END
	END GetStrokeOutline;
	
	(** get offset values and pattern index of visible and invisible dash part at start of subpath (in device space) **)
	PROCEDURE GetDashOffsets* (ctxt: Context; offset: REAL; VAR beg, end, next: REAL; VAR idx: LONGINT);
		VAR phase, period, len: REAL;
	BEGIN
		idx := 0;
		GfxMatrix.ApplyToDist(ctxt.cam, ctxt.dashPhase, phase);
		GfxMatrix.ApplyToDist(ctxt.cam, ctxt.dashPeriod, period);
		beg := ENTIER((phase + offset)/period) * period - phase;	(* offset - period < beg <= offset *)
		LOOP
			GfxMatrix.ApplyToDist(ctxt.cam, ctxt.dashPatOn[idx], len);
			end := beg + len;
			GfxMatrix.ApplyToDist(ctxt.cam, ctxt.dashPatOff[idx], len);
			next := end + len;
			idx := (idx+1) MOD ctxt.dashPatLen;
			IF next > offset THEN EXIT END;
			beg := next
		END
	END GetDashOffsets;
	
	PROCEDURE GetDashOutline (ctxt: Context; VAR scan: GfxPaths.Scanner; dst: GfxPaths.Path);
		VAR
			width, cx, cy, dx, dy, beg, end, next, offset, len, cos, sin, wdx, wdy, endOff, dash, nx, ny, dx0, dy0, dx1, dy1: REAL;
			index: LONGINT; dscan: GfxPaths.Scanner;
	BEGIN
		GfxMatrix.ApplyToDist(ctxt.cam, 0.5*ctxt.lineWidth, width);
		ASSERT(scan.elem = GfxPaths.Enter);
		cx := scan.x; cy := scan.y; dx := scan.dx; dy := scan.dy;
		GfxPaths.Scan(scan);
		GetDashOffsets(ctxt, 0, beg, end, next, index);
		IF 0 < end THEN	(* starts within dash *)
			IF width = 0 THEN
				GfxPaths.AddEnter(dst, cx, cy, dx, dy)
			ELSE
				GfxPaths.Clear(DashPath);
				GfxPaths.AddEnter(DashPath, cx, cy, dx, dy)
			END
		END;
		offset := 0;
		WHILE scan.elem = GfxPaths.Line DO
			dx := scan.x - cx; dy := scan.y - cy;
			len := Math.sqrt(dx * dx + dy * dy);
			cos := dx/len; sin := dy/len;
			endOff := offset + len;
			IF offset < end THEN	(* begin of line is within dash *)
				IF end <= endOff THEN	(* end of current dash comes before end of line => finish current dash *)
					len := end - offset;
					IF width = 0 THEN
						GfxPaths.AddLine(dst, cx + len * cos, cy + len * sin);
						GfxPaths.AddExit(dst, 0, 0)
					ELSE
						GfxPaths.AddLine(DashPath, cx + len * cos, cy + len * sin);
						GfxPaths.AddExit(DashPath, 0, 0);
						GfxPaths.Open(dscan, DashPath, 0);
						GetStrokeOutline(ctxt, dscan, dst)
					END
				ELSIF width = 0 THEN	(* continue current dash to end of line *)
					GfxPaths.AddLine(dst, scan.x, scan.y)
				ELSE
					GfxPaths.AddLine(DashPath, scan.x, scan.y)
				END
			END;
			IF next < endOff THEN	(* next dash starts before end of line => draw complete dashes *)
				wdx := width * cos; wdy := width * sin;
				beg := offset;
				REPEAT
					len := next - beg;
					cx := cx + len * cos; cy := cy + len * sin;
					beg := next;
					GfxMatrix.ApplyToDist(ctxt.cam, ctxt.dashPatOn[index], dash);
					end := beg + dash;
					GfxMatrix.ApplyToDist(ctxt.cam, ctxt.dashPatOff[index], dash);
					next := end + dash;
					index := (index+1) MOD ctxt.dashPatLen;
					IF end <= endOff THEN	(* next dash can be fully drawn *)
						len := end - beg;
						nx := cx + len * cos; ny := cy + len * sin;
						IF width = 0 THEN
							GfxPaths.AddEnter(dst, cx, cy, 0, 0);
							GfxPaths.AddLine(dst, nx, ny);
							GfxPaths.AddExit(dst, 0, 0)
						ELSE
							GfxPaths.AddEnter(dst, cx - wdy, cy + wdx, nx - cx, ny - cy);
							ctxt.capStyle(ctxt, cx, cy, wdx, wdy, dst, dx0, dy0);
							GfxPaths.AddLine(dst, nx + wdy, ny - wdx);
							ctxt.capStyle(ctxt, nx, ny, -wdx, -wdy, dst, dx1, dy1);
							GfxPaths.AddLine(dst, cx - wdy, cy + wdx);
							GfxPaths.AddExit(dst, dx0, dy0)
						END
					END
				UNTIL next >= endOff;
				IF endOff < end THEN	(* next dash not complete => hasn't been started yet *)
					IF width = 0 THEN
						GfxPaths.AddEnter(dst, cx, cy, 0, 0);
						GfxPaths.AddLine(dst, scan.x, scan.y)
					ELSE
						GfxPaths.Clear(DashPath);
						GfxPaths.AddEnter(DashPath, cx, cy, 0, 0);
						GfxPaths.AddLine(DashPath, scan.x, scan.y)
					END
				END
			END;
			cx := scan.x; cy := scan.y; offset := endOff;
			GfxPaths.Scan(scan)
		END;
		ASSERT(scan.elem = GfxPaths.Exit);
		IF offset < end THEN	(* currently within dash => end properly *)
			IF width = 0 THEN
				GfxPaths.AddExit(dst, scan.dx, scan.dy)
			ELSE
				GfxPaths.AddExit(DashPath, scan.dx, scan.dy);
				GfxPaths.Open(dscan, DashPath, 0);
				GetStrokeOutline(ctxt, dscan, dst)
			END
		END
	END GetDashOutline;
	
	(** store outline/dashes of current path in specified path **)
	PROCEDURE GetOutline* (ctxt: Context; dst: GfxPaths.Path);
		VAR scan: GfxPaths.Scanner;
	BEGIN
		ASSERT(dst # ctxt.path, 100);
		ctxt.do.flatten(ctxt);
		GfxPaths.Clear(dst);
		GfxPaths.Open(scan, ctxt.path, 0);
		WHILE scan.elem = GfxPaths.Enter DO
			IF ctxt.dashPatLen > 0 THEN
				GetDashOutline(ctxt, scan, dst)
			ELSE
				GetStrokeOutline(ctxt, scan, dst)
			END
		END
	END GetOutline;
	
	(** draw current path in requested mode **)
	PROCEDURE Render* (ctxt: Context; mode: SET);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		EXCL(mode, Record);
		IF mode # {} THEN
			ctxt.do.render(ctxt, mode)
		END
	END Render;
	
	
	(**--- Drawing Operations ---**)
	
	(** erase whole context (irrespective of current clip area) **)
	PROCEDURE Erase* (ctxt: Context);
	BEGIN
		ctxt.do.erase(ctxt)
	END Erase;
	
	(** draw given path in requested mode **)
	PROCEDURE DrawPath* (ctxt: Context; path: GfxPaths.Path; mode: SET);
		VAR scan: GfxPaths.Scanner;
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		IF path = ctxt.path THEN
			Render(ctxt, mode)
		ELSE
			ctxt.do.begin(ctxt, mode);
			GfxPaths.Open(scan, path, 0);
			WHILE scan.elem # GfxPaths.Stop DO
				CASE scan.elem OF
				| GfxPaths.Enter: ctxt.do.enter(ctxt, scan.x, scan.y, scan.dx, scan.dy)
				| GfxPaths.Line: ctxt.do.line(ctxt, scan.x, scan.y)
				| GfxPaths.Arc: ctxt.do.arc(ctxt, scan.x, scan.y, scan.x0, scan.y0, scan.x1, scan.y1, scan.x2, scan.y2)
				| GfxPaths.Bezier: ctxt.do.bezier(ctxt, scan.x, scan.y, scan.x1, scan.y1, scan.x2, scan.y2)
				| GfxPaths.Exit: ctxt.do.exit(ctxt, scan.dx, scan.dy)
				END
			END;
			ctxt.do.end(ctxt)
		END
	END DrawPath;
	
	(** draw line in requested mode **)
	PROCEDURE DrawLine* (ctxt: Context; x0, y0, x1, y1: REAL; mode: SET);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ASSERT(mode * {Fill, Clip, EvenOdd} = {}, 101);
		ctxt.do.begin(ctxt, mode);
		ctxt.do.enter(ctxt, x0, y0, 0, 0);
		ctxt.do.line(ctxt, x1, y1);
		ctxt.do.exit(ctxt, 0, 0);
		ctxt.do.end(ctxt)
	END DrawLine;
	
	(** draw rectangle in requested mode **)
	PROCEDURE DrawRect* (ctxt: Context; x0, y0, x1, y1: REAL; mode: SET);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ctxt.do.begin(ctxt, mode);
		ctxt.do.rect(ctxt, x0, y0, x1, y1);
		ctxt.do.end(ctxt)
	END DrawRect;
	
	(** draw circle in requested mode (clockwise if r > 0, counterclockwise if r < 0) **)
	PROCEDURE DrawCircle* (ctxt: Context; x, y, r: REAL; mode: SET);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ctxt.do.begin(ctxt, mode);
		ctxt.do.ellipse(ctxt, x, y, r, ABS(r));
		ctxt.do.end(ctxt)
	END DrawCircle;
	
	(** draw ellipse in requested mode (clockwise if rx*ry > 0, counterclockwise if rx*ry < 0) **)
	PROCEDURE DrawEllipse* (ctxt: Context; x, y, rx, ry: REAL; mode: SET);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ctxt.do.begin(ctxt, mode);
		ctxt.do.ellipse(ctxt, x, y, rx, ry);
		ctxt.do.end(ctxt)
	END DrawEllipse;
	
	(** draw string at given coordinates and move current point to string end **)
	PROCEDURE DrawStringAt* (ctxt: Context; x, y: REAL; str: ARRAY OF CHAR);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ctxt.do.begin(ctxt, {Fill});
		ctxt.do.show(ctxt, x, y, str);
		ctxt.do.end(ctxt)
	END DrawStringAt;
	
	(** draw string at current point and move current point to string end **)
	PROCEDURE DrawString* (ctxt: Context; str: ARRAY OF CHAR);
	BEGIN
		ASSERT(~(InPath IN ctxt.mode), 100);
		ctxt.do.begin(ctxt, {Fill});
		ctxt.do.show(ctxt, ctxt.cpx, ctxt.cpy, str);
		ctxt.do.end(ctxt)
	END DrawString;
	
	
	(**--- Images and Patterns ---**)
	
	(** draw image map at given point **)
	PROCEDURE DrawImageAt* (ctxt: Context; x, y: REAL; map: GfxMaps.Map; VAR filter: GfxMaps.Filter);
	BEGIN
		ctxt.do.image(ctxt, x, y, map, filter)
	END DrawImageAt;
	
	(** draw image map at current point **)
	PROCEDURE DrawImage* (ctxt: Context; map: GfxMaps.Map; VAR filter: GfxMaps.Filter);
	BEGIN
		ctxt.do.image(ctxt, ctxt.cpx, ctxt.cpy, map, filter)
	END DrawImage;
	
	(** return new pattern **)
	PROCEDURE NewPattern* (ctxt: Context; map: GfxMaps.Map; px, py: REAL): Pattern;
	BEGIN
		RETURN ctxt.do.newPattern(ctxt, map, px, py)
	END NewPattern;
	
	
	(**--- Predefined Join Styles ---**)
	
	(** connect outer corner points with a line **)
	PROCEDURE BevelJoin* (ctxt: Context; cx, cy, idx, idy, odx, ody, hx, hy: REAL; parts: SET; path: GfxPaths.Path);
		VAR ix, iy: REAL;
	BEGIN
		IF (hx # 0) OR (hy # 0) THEN
			IF parts = {0} THEN	(* start new subpath in the middle of the bevel line *)
				GfxPaths.IntersectLines(cx, cy, hx, hy, cx + ody, cy - odx, -hy, hx, ix, iy);
				GfxPaths.AddEnter(path, ix, iy, -hy, hx);
				GfxPaths.AddLine(path, cx + ody, cy - odx)
			ELSIF parts = {1} THEN	(* end current subpath in the middle of the bevel line *)
				GfxPaths.IntersectLines(cx, cy, hx, hy, cx + idy, cy - idx, -hy, hx, ix, iy);
				GfxPaths.AddLine(path, ix, iy);
				GfxPaths.AddExit(path, -hy, hx)
			ELSE	(* draw full bevel line *)
				GfxPaths.AddLine(path, cx + ody, cy - odx)
			END
		END
	END BevelJoin;
	
	(** connect outer corner points with a circular arc **)
	PROCEDURE RoundJoin* (ctxt: Context; cx, cy, idx, idy, odx, ody, hx, hy: REAL; parts: SET; path: GfxPaths.Path);
		VAR t: REAL;
	BEGIN
		IF (hx # 0) OR (hy # 0) THEN
			IF parts = {0} THEN
				t := Math.sqrt((odx * odx + ody * ody)/(hx * hx + hy * hy));
				GfxPaths.AddEnter(path, cx + t * hx, cy + t * hy, -hy, hx);
				GfxPaths.AddArc(path, cx + ody, cy - odx, cx, cy, cx - odx, cy - ody, cx + ody, cy - odx)
			ELSIF parts = {1} THEN
				t := Math.sqrt((odx * odx + ody * ody)/(hx * hx + hy * hy));
				GfxPaths.AddArc(path, cx + t * hx, cy + t * hy, cx, cy, cx + idy, cy - idx, cx + idx, cy + idy);
				GfxPaths.AddExit(path, -hy, hx)
			ELSE
				GfxPaths.AddArc(path, cx + ody, cy - odx, cx, cy, cx + idy, cy - idx, cx + idx, cy + idy)
			END
		END
	END RoundJoin;
	
	(** connect outer corner points by extending their tangent vectors until they meet **)
	PROCEDURE MiterJoin* (ctxt: Context; cx, cy, idx, idy, odx, ody, hx, hy: REAL; parts: SET; path: GfxPaths.Path);
		VAR limit: REAL;
	BEGIN
		IF (hx # 0) OR (hy # 0) THEN
			GfxMatrix.ApplyToDist(ctxt.cam, 0.5 * ctxt.lineWidth * ctxt.styleLimit, limit);
			IF hx * hx + hy * hy > limit * limit THEN	(* miter join extends over boundary => use bevel join *)
				BevelJoin(ctxt, cx, cy, idx, idy, odx, ody, hx, hy, parts, path)
			ELSIF parts = {0} THEN
				GfxPaths.AddEnter(path, cx + hx, cy + hy, idx, idy);
				GfxPaths.AddLine(path, cx + ody, cy - odx)
			ELSIF parts = {1} THEN
				GfxPaths.AddLine(path, cx + hx, cy + hy);
				GfxPaths.AddExit(path, odx, ody)
			ELSE
				GfxPaths.AddLine(path, cx + hx, cy + hy);
				GfxPaths.AddLine(path, cx + ody, cy - odx)
			END
		END
	END MiterJoin;
	
	
	(**--- Predefined Cap Styles ---**)
	
	(** connect corner points with straight line **)
	PROCEDURE ButtCap* (ctxt: Context; x, y, dx, dy: REAL; path: GfxPaths.Path; VAR dx0, dy0: REAL);
	BEGIN
		GfxPaths.AddLine(path, x + dy, y - dx);
		dx0 := dy; dy0 := -dx
	END ButtCap;
	
	(** connect corner points with a semi-circular arc **)
	PROCEDURE RoundCap* (ctxt: Context; x, y, dx, dy: REAL; path: GfxPaths.Path; VAR dx0, dy0: REAL);
	BEGIN
		GfxPaths.AddArc(path, x + dy, y - dx, x, y, x - dy, y + dx, x - dx, y - dy);
		dx0 := -dx; dy0 := -dy
	END RoundCap;
	
	(** connect corner points by extending their tangent vectors by half the line width and a line inbetween **)
	PROCEDURE SquareCap* (ctxt: Context; x, y, dx, dy: REAL; path: GfxPaths.Path; VAR dx0, dy0: REAL);
	BEGIN
		GfxPaths.AddLine(path, x - dy - dx, y + dx - dy);
		GfxPaths.AddLine(path, x + dy - dx, y - dx - dy);
		GfxPaths.AddLine(path, x + dy, y - dx);
		dx0 := -dx; dy0 := -dy
	END SquareCap;
	
	
	(**--- Default Methods ---**)
	
	PROCEDURE DefResetContext* (ctxt: Context);
	BEGIN
		InitContextValues(ctxt);
		ctxt.do.resetClip(ctxt);
		ctxt.do.resetCTM(ctxt)
	END DefResetContext;
	
	PROCEDURE DefSetCTM* (ctxt: Context; VAR mat: GfxMatrix.Matrix);
	BEGIN
		ctxt.ctm := mat
	END DefSetCTM;
	
	PROCEDURE DefTranslate* (ctxt: Context; dx, dy: REAL);
	BEGIN
		GfxMatrix.Translate(ctxt.ctm, dx, dy, ctxt.ctm)
	END DefTranslate;
	
	PROCEDURE DefScale* (ctxt: Context; sx, sy: REAL);
	BEGIN
		GfxMatrix.Scale(ctxt.ctm, sx, sy, ctxt.ctm)
	END DefScale;
	
	PROCEDURE DefRotate* (ctxt: Context; sin, cos: REAL);
	BEGIN
		GfxMatrix.Rotate(ctxt.ctm, sin, cos, ctxt.ctm)
	END DefRotate;
	
	PROCEDURE DefConcat* (ctxt: Context; VAR mat: GfxMatrix.Matrix);
	BEGIN
		GfxMatrix.Concat(mat, ctxt.ctm, ctxt.ctm)
	END DefConcat;
	
	PROCEDURE DefSetStrokeColor* (ctxt: Context; color: Color);
	BEGIN
		ctxt.strokeCol := color
	END DefSetStrokeColor;
	
	PROCEDURE DefSetStrokePattern* (ctxt: Context; pat: Pattern);
	BEGIN
		ctxt.strokePat := pat
	END DefSetStrokePattern;
	
	PROCEDURE DefSetFillColor* (ctxt: Context; color: Color);
	BEGIN
		ctxt.fillCol := color
	END DefSetFillColor;
	
	PROCEDURE DefSetFillPattern* (ctxt: Context; pat: Pattern);
	BEGIN
		ctxt.fillPat := pat
	END DefSetFillPattern;
	
	PROCEDURE DefSetLineWidth* (ctxt: Context; width: REAL);
	BEGIN
		ctxt.lineWidth := width
	END DefSetLineWidth;
	
	PROCEDURE DefSetDashPattern* (ctxt: Context; VAR on, off: ARRAY OF REAL; len: LONGINT; phase: REAL);
	BEGIN
		SetDashArray(ctxt, on, off, len);
		ctxt.dashPhase := phase
	END DefSetDashPattern;
	
	PROCEDURE DefSetCapStyle* (ctxt: Context; style: CapStyle);
	BEGIN
		ctxt.capStyle := style
	END DefSetCapStyle;
	
	PROCEDURE DefSetJoinStyle* (ctxt: Context; style: JoinStyle);
	BEGIN
		ctxt.joinStyle := style
	END DefSetJoinStyle;
	
	PROCEDURE DefSetStyleLimit* (ctxt: Context; limit: REAL);
	BEGIN
		ctxt.styleLimit := limit
	END DefSetStyleLimit;
	
	PROCEDURE DefSetPoint* (ctxt: Context; x, y: REAL);
	BEGIN
		IF (InSubpath IN ctxt.mode) & ((x # ctxt.cpx) OR (y # ctxt.cpy)) THEN
			ctxt.do.exit(ctxt, 0, 0);
			ctxt.do.enter(ctxt, x, y, 0, 0)
		END;
		ctxt.cpx := x; ctxt.cpy := y
	END DefSetPoint;
	
	PROCEDURE DefSetFlatness* (ctxt: Context; flatness: REAL);
	BEGIN
		ctxt.flatness := flatness
	END DefSetFlatness;
	
	PROCEDURE DefSetFont* (ctxt: Context; font: GfxFonts.Font);
	BEGIN
		ctxt.font := font
	END DefSetFont;
	
	PROCEDURE DefGetStringWidth* (ctxt: Context; VAR str: ARRAY OF CHAR; VAR dx, dy: REAL);
	BEGIN
		GfxFonts.GetStringWidth(ctxt.font, str, dx, dy)
	END DefGetStringWidth;
	
	PROCEDURE DefFlatten* (ctxt: Context);
	BEGIN
		GetFlattenedPath(ctxt, TmpPath);
		GfxPaths.Copy(TmpPath, ctxt.path);
		GfxPaths.Clear(TmpPath)
	END DefFlatten;
	
	PROCEDURE DefOutline* (ctxt: Context);
	BEGIN
		GetOutline(ctxt, TmpPath);
		GfxPaths.Copy(TmpPath, ctxt.path);
		GfxPaths.Clear(TmpPath)
	END DefOutline;
	
	PROCEDURE DefRect* (ctxt: Context; x0, y0, x1, y1: REAL);
	BEGIN
		ctxt.do.enter(ctxt, x0, y0, 0, y0 - y1);
		ctxt.do.line(ctxt, x1, y0); ctxt.do.line(ctxt, x1, y1); ctxt.do.line(ctxt, x0, y1); ctxt.do.line(ctxt, x0, y0);
		ctxt.do.exit(ctxt, x1 - x0, 0)
	END DefRect;
	
	PROCEDURE DefEllipse* (ctxt: Context; x, y, rx, ry: REAL);
		VAR xr: REAL;
	BEGIN
		xr := x + rx;
		IF xr # x THEN
			ctxt.do.enter(ctxt, xr, y, 0, ry);
			ctxt.do.arc(ctxt, xr, y, x, y, xr, y, x, y + ry);
			ctxt.do.exit(ctxt, 0, ry)
		END
	END DefEllipse;
	
	PROCEDURE DefNewPattern* (ctxt: Context; map: GfxMaps.Map; px, py: REAL): Pattern;
		VAR pat: Pattern;
	BEGIN
		NEW(pat); pat.map := map; pat.px := px; pat.py := py;
		RETURN pat
	END DefNewPattern;
	
	
	(*--- Initialization of Standard Colors ---*)
	
	PROCEDURE InitColors;
		PROCEDURE init (VAR col: Color; r, g, b: INTEGER);
		BEGIN
			col.r := r; col.g := g; col.b := b
		END init;
	BEGIN
		init(Black, 0, 0, 0); init(White, 255, 255, 255); init(Red, 255, 0, 0); init(Green, 0, 255, 0); init(Blue, 0, 0, 255);
		init(Cyan, 0, 255, 255); init(Magenta, 255, 0, 255); init(Yellow, 255, 255, 0);
		init(LGrey, 192, 192, 192); init(MGrey, 160, 160, 160); init(DGrey, 128, 128, 128)
	END InitColors;
	

BEGIN
	InitColors;
	Texts.OpenWriter(W);
	Texts.WriteString(W, Version); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	NEW(DashPath);
	NEW(TmpPath);
	DefaultCap := ButtCap; DefaultJoin := MiterJoin
END Gfx.
