MODULE GfxRaster;	(** eos   **)

	(**
		Gfx contexts rendering on abstract raster devices
		(probably only interesting for extensions rendering to concrete devices)
	**)
	
	(*
		12.2.98 - eliminated offset parameter from subpath begin
		12.2.98 - fixed bug with path not being allocated for mode=Clip in BeginPath
		12.2.98 - fixed bug with ASSERT being executed before rc was assigned in RestoreClip
		17.2.98 - implemented RenderPath
		24.2.98 - adaption to new cap and join styles
		27.2.98 - fixed bug with filled paths (didn't update (u, v) in context)
		6.4.98 - fixed bug in RenderPath (didn't alloc and init pathReg for thick lines)
		6.4.98 - fixed bug with thick lines (didn't treat (hx, hy) = (0, 0) correctly)
		8.4.98 - made filled regions more robust regarding open boundary curves
		8.4.98 - fixed bug in BeginSubpath (didn't set rc.u and rc.v for mode = {Record})
		15.4.98 - fixed clipState (now only updated while stroking, removed OutIn state, added InOut state)
		15.4.98 - improved autoclose logic for filled paths (now only connects open subpaths)
		18.9.98 - minor changes to comply with new GfxMaps, GfxFonts and Gfx interfaces
		21.9.98 - implemented special cases for circles and axis-aligned ellipses
		10.3.99 - new dash pattern
		1.4.99 - bugfix in Rect: incorrect use of GfxRegions.AddPoint when mode included Clip
	*)
	
	IMPORT
		Math, GfxMatrix, GfxMaps, GfxPaths, GfxRegions, GfxFonts, Gfx;
		
	
	CONST
		In* = 0; Out* = 1; InOut* = 2;	(** clip states **)
		
	
	TYPE
		(** stackable regions **)
		Region* = POINTER TO RegionDesc;
		RegionDesc* = RECORD (GfxRegions.RegionDesc)
			next*: Region;	(** link to last previously saved region **)
		END;
		
		(** abstract raster context **)
		Context* = POINTER TO ContextDesc;
		ContextDesc* = RECORD (Gfx.ContextDesc)
			clipReg*: Region;	(** region inside clip path **)
			dot*: PROCEDURE (rc: Context; x, y: LONGINT);	(** current dot procedure **)
			rect*: PROCEDURE (rc: Context; lx, ly, rx, uy: LONGINT);	(** current rect procedure **)
			setColPat*: PROCEDURE (rc: Context; col: Gfx.Color; pat: Gfx.Pattern);
			col*: Gfx.Color;	(** current color **)
			pat*: Gfx.Pattern;	(** current pattern **)
			clipState*: SHORTINT;	(* current clip state (In, Out, InOut) *)
			useRegion, lateStroke: BOOLEAN;	(* flags for path operations *)
			cp: GfxPaths.Path;	(* current path if lateStroke is set *)
			pathReg: GfxRegions.Region;	(* region surrounded by current path *)
			plx, ply, prx, puy: INTEGER;	(* rectangle around last point *)
			border: INTEGER;	(* safety border in proportion to style limit around points *)
			devWidth: REAL;	(* half the line width in device space *)
			u, v: REAL;	(* current position in device space *)
			su, sv: REAL;	(* position of first point for thick lines *)
			du, dv: REAL;	(* current direction for thick lines *)
			tu, tv: REAL;	(* point on thick line perpendicular to current inner join vertex *)
			px, py: LONGINT;	(* current pixel position *)
			fu, fv: REAL;	(* current outline position for filled areas *)
			offset: REAL;	(* current offset *)
			sx, sy: LONGINT;	(* current starting point of fill path *)
			disconnected: BOOLEAN;	(* indicates whether fill path must be closed *)
			cfx0, cfy0, cfx1, cfy1: LONGINT;	(* end points of line that closes fill path *)
		END;
		
		(* path data for filling paths *)
		PathData = RECORD (GfxPaths.EnumData)
			context: Context;
		END;
		
		RegData = RECORD (GfxRegions.EnumData)
			context: Context;
		END;
		
	
	VAR
		TmpPath: GfxPaths.Path;
		
	
	(**--- Ellipse Test ---**)
	
	(** return if arc parameter describe axis-aligned ellipse and, if so, the radii in x and y direction **)
	PROCEDURE IsEllipse* (x0, y0, x1, y1, x2, y2, sx, sy, ex, ey, flatness: REAL; VAR rx, ry: REAL): BOOLEAN;
		CONST eps = 0.01;
		VAR x, y: REAL;
	BEGIN
		IF (ABS(x1 - x0) < eps) & (ABS(y2 - y0) < eps) THEN
			rx := x0 - x2; ry := y0 - y1
		ELSIF (ABS(x2 - x0) < eps) & (ABS(y1 - y0) < eps) THEN
			rx := x1 - x0; ry := y2 - y0
		ELSE
			RETURN FALSE
		END;
		flatness := 0.25*flatness;
		IF (ABS(rx - ENTIER(rx + 0.5)) < flatness) & (ABS(ry - ENTIER(ry + 0.5)) < flatness) &
			(ABS(x0 - 0.5 - ENTIER(x0)) < flatness) & (ABS(y0 - 0.5 - ENTIER(y0)) < flatness) &
			(ABS(sx - ex) < eps) & (ABS(sy - ey) < eps)
		THEN
			GfxPaths.ProjectToEllipse(rx, 0, 0, ry, sx, sy, x, y);
			RETURN (ABS(sx - x) < eps) & (ABS(sy - y) < eps)
		ELSE
			RETURN FALSE
		END
	END IsEllipse;
	
	
	(**--- Clipping ---**)
	
	PROCEDURE ResetClip* (ctxt: Gfx.Context);
		VAR rc: Context;
	BEGIN
		rc := ctxt(Context);
		rc.clipReg.next := NIL;
		GfxRegions.Clear(rc.clipReg)
	END ResetClip;
	
	PROCEDURE GetClipRect* (ctxt: Gfx.Context; VAR llx, lly, urx, ury: REAL);
		VAR inv: GfxMatrix.Matrix; reg: GfxRegions.Region;
	BEGIN
		GfxMatrix.Invert(ctxt.ctm, inv);
		reg := ctxt(Context).clipReg;
		GfxMatrix.ApplyToRect(inv, reg.llx, reg.lly, reg.urx, reg.ury, llx, lly, urx, ury)
	END GetClipRect;
	
	PROCEDURE SaveClip* (ctxt: Gfx.Context);
		VAR rc: Context; reg: Region;
	BEGIN
		rc := ctxt(Context);
		NEW(reg); GfxRegions.Copy(rc.clipReg, reg);
		reg.next := rc.clipReg; rc.clipReg := reg
	END SaveClip;
	
	PROCEDURE RestoreClip* (ctxt: Gfx.Context);
		VAR rc: Context;
	BEGIN
		rc := ctxt(Context);
		ASSERT(rc.clipReg.next # NIL);
		rc.clipReg := rc.clipReg.next
	END RestoreClip;
	
	PROCEDURE InitClipState (rc: Context; x, y: INTEGER);
	BEGIN
		rc.plx := x - rc.border; rc.ply := y - rc.border;
		rc.prx := x + rc.border; rc.puy := y + rc.border;
		IF GfxRegions.RectInside(rc.plx, rc.ply, rc.prx, rc.puy, rc.clipReg) THEN
			rc.clipState := In
		ELSIF GfxRegions.RectOverlaps(rc.plx, rc.ply, rc.prx, rc.puy, rc.clipReg) THEN
			rc.clipState := InOut
		ELSE
			rc.clipState := Out
		END
	END InitClipState;
	
	PROCEDURE UpdateClipState (rc: Context; x, y: INTEGER);
		VAR plx, ply, prx, puy: INTEGER;
	BEGIN
		plx := x - rc.border; ply := y - rc.border; prx := x + rc.border; puy := y + rc.border;
		GfxRegions.IncludeRect(rc.plx, rc.ply, rc.prx, rc.puy, plx, ply, prx, puy);
		IF GfxRegions.RectInside(rc.plx, rc.ply, rc.prx, rc.puy, rc.clipReg) THEN
			rc.clipState := In
		ELSIF GfxRegions.RectOverlaps(rc.plx, rc.ply, rc.prx, rc.puy, rc.clipReg) THEN
			rc.clipState := InOut
		ELSE
			rc.clipState := Out
		END;
		rc.plx := plx; rc.ply := ply; rc.prx := prx; rc.puy := puy
	END UpdateClipState;
	
	
	(*--- Hairlines ---*)
	
	PROCEDURE HairLineEnter (rc: Context; u, v: REAL);
	BEGIN
		rc.u := u; rc.v := v;
		rc.px := ENTIER(u); rc.py := ENTIER(v);
		InitClipState(rc, SHORT(rc.px), SHORT(rc.py));
		rc.dot(rc, rc.px, rc.py)
	END HairLineEnter;
	
	PROCEDURE HairLineTo (rc: Context; u, v: REAL);
		VAR px, py, xstep, ystep, steps: LONGINT; du, dv, eu, ev, e: REAL;
	BEGIN
		px := ENTIER(u); py := ENTIER(v);
		UpdateClipState(rc, SHORT(px), SHORT(py));
		IF px = rc.px THEN	(* horizontal line *)
			IF py > rc.py THEN rc.rect(rc, px, rc.py + 1, px + 1, py + 1)
			ELSIF py < rc.py THEN rc.rect(rc, px, py, px + 1, rc.py)
			END;
			rc.py := py
		ELSIF py = rc.py THEN	(* vertical line *)
			IF px > rc.px THEN rc.rect(rc, rc.px + 1, py, px + 1, py + 1)
			ELSE rc.rect(rc, px, py, rc.px, py + 1)
			END;
			rc.px := px
		ELSE
			du := u - rc.u; dv := v - rc.v;
			
			(* bring parameters into first quadrant *)
			IF du >= 0 THEN xstep := 1; eu := rc.u - (rc.px + 0.5)
			ELSE xstep := -1; du := -du; eu := rc.px + 0.5 - rc.u
			END;
			IF dv >= 0 THEN ystep := 1; ev := rc.v - (rc.py + 0.5)
			ELSE ystep := -1; dv := -dv; ev := rc.py + 0.5 - rc.v
			END;
			
			IF du >= dv THEN	(* x-dominant case *)
				e := du * ev - dv * eu + dv - 0.5*du;
				steps := ABS(px - rc.px);
				WHILE steps > 0 DO
					IF (e >= 0) & ((e > 0) OR (ystep <= 0)) THEN
						INC(rc.py, ystep); e := e - du
					END;
					INC(rc.px, xstep); e := e + dv;
					rc.dot(rc, rc.px, rc.py);
					DEC(steps)
				END
			ELSE	(* y-dominant case *)
				e := dv * eu - du * ev + du - 0.5*dv;
				steps := ABS(py - rc.py);
				WHILE steps > 0 DO
					IF (e >= 0) & ((e > 0) OR (xstep <= 0)) THEN
						INC(rc.px, xstep); e := e - dv
					END;
					INC(rc.py, ystep); e := e + du;
					rc.dot(rc, rc.px, rc.py);
					DEC(steps)
				END
			END
		END;
		rc.u := u; rc.v := v
	END HairLineTo;
	
	PROCEDURE HairCircle (rc: Context; mx, my, r: LONGINT);
		VAR llx, lly, urx, ury: INTEGER; x, y, d, de, dse: LONGINT;
	BEGIN
		llx := SHORT(mx - r); lly := SHORT(my - r); urx := SHORT(mx + r + 1); ury := SHORT(my + r + 1);
		IF GfxRegions.RectOverlaps(llx, lly, urx, ury, rc.clipReg) THEN
			IF GfxRegions.RectInside(llx, lly, urx, ury, rc.clipReg) THEN rc.clipState := In
			ELSE rc.clipState := InOut
			END;
			x := 0; y := r; d := 1-r; de := 3; dse := -2*r + 5;
			rc.dot(rc, mx, my + y); rc.dot(rc, mx, my - y); rc.dot(rc, mx + y, my); rc.dot(rc, mx - y, my);
			WHILE y > x DO
				IF d < 0 THEN
					INC(d, de); INC(de, 2); INC(dse, 2); INC(x)
				ELSE
					INC(d, dse); INC(de, 2); INC(dse, 4); INC(x); DEC(y)
				END;
				rc.dot(rc, mx + x, my + y); rc.dot(rc, mx + y, my + x);
				rc.dot(rc, mx + x, my - y); rc.dot(rc, mx - y, my + x);
				rc.dot(rc, mx - x, my - y); rc.dot(rc, mx - y, my - x);
				rc.dot(rc, mx - x, my + y); rc.dot(rc, mx + y, mx - x)
			END
		END
	END HairCircle;
	
	PROCEDURE HairEllipse (rc: Context; mx, my, rx, ry: LONGINT);
		VAR llx, lly, urx, ury: INTEGER; x, y, aa, bb, da, db, dy, dx, d: LONGINT;
	BEGIN
		llx := SHORT(mx - rx); lly := SHORT(my - ry); urx := SHORT(mx + rx + 1); ury := SHORT(my + ry + 1);
		IF GfxRegions.RectOverlaps(llx, lly, urx, ury, rc.clipReg) THEN
			IF GfxRegions.RectInside(llx, lly, urx, ury, rc.clipReg) THEN rc.clipState := In
			ELSE rc.clipState := InOut
			END;
			x := rx; y := 0;
			aa := rx * rx; bb := ry * ry;
			da := -8*aa; db := -8*bb;
			dy := -4*aa; dx := -db * (x-1);
			d := bb * (4*x - 1);
			WHILE db * x < da * y DO
				rc.dot(rc, mx + x, my + y); rc.dot(rc, mx + x, my - y);
				rc.dot(rc, mx - x, my + y); rc.dot(rc, mx - x, my - y);
				INC(d, dy); INC(dy, da); INC(y);
				IF d < 0 THEN
					INC(d, dx); INC(dx, db); DEC(x)
				END
			END;
			dx := 4 * bb * (2*x - 1); dy := da * (y+1);
			d := d - bb * (4*x - 1) - aa * (4*y + 1);
			WHILE x >= 0 DO
				rc.dot(rc, mx + x, my + y); rc.dot(rc, mx + x, my - y);
				rc.dot(rc, mx - x, my + y); rc.dot(rc, mx - x, my - y);
				INC(d, dx); INC(dx, db); DEC(x);
				IF d >= 0 THEN
					INC(d, dy); INC(dy, da); INC(y)
				END
			END
		END
	END HairEllipse;
	
	
	(*--- Filled Areas ---*)
	
	PROCEDURE AddLine (rc: Context; u, v: REAL);
		VAR px, py, x, y, xstep, ystep, steps: LONGINT; du, dv, eu, ev, e: REAL;
	BEGIN
		px := ENTIER(u + 0.5); py := ENTIER(v + 0.5);
		x := rc.px; y := rc.py;
		IF py = y THEN	(* horizontal line => ignore *)
			rc.px := px
		ELSE
			du := u - rc.fu; dv := v - rc.fv;
			IF du >= 0 THEN xstep := 1; eu := rc.fu - x
			ELSE xstep := -1; du := -du; eu := x - rc.fu
			END;
			IF dv >= 0 THEN ystep := 1; ev := rc.fv - y
			ELSE ystep := -1; dv := -dv; ev := y - rc.fv
			END;
			e := du * ev - dv * eu + 0.5 * (dv - du);
			steps := ABS(px - x) + ABS(py - y);
			WHILE steps > 0 DO
				IF (e >= 0) & ((e > 0) OR (xstep <= 0)) THEN
					INC(y, ystep); e := e - du;
					GfxRegions.AddPoint(rc.pathReg, SHORT(x), SHORT(y), SHORT(ystep))
				ELSE
					INC(x, xstep); e := e + dv
					(* don't have to insert point here because regions are sliced horizontally *)
				END;
				DEC(steps)
			END;
			rc.px := px; rc.py := py
		END;
		rc.fu := u; rc.fv := v
	END AddLine;
	
	PROCEDURE EnterLine (rc: Context; u, v: REAL);
	BEGIN
		rc.fu := u; rc.fv := v;
		rc.px := ENTIER(u + 0.5); rc.py := ENTIER(v + 0.5);
		rc.sx := rc.px; rc.sy := rc.py
	END EnterLine;
	
	PROCEDURE ExitLine (rc: Context);
		VAR px, py: LONGINT;
	BEGIN
		IF rc.disconnected THEN	(* previous subpath wasn't closed *)
			IF (rc.sx # rc.px) OR (rc.sy # rc.py) THEN	(* and this one isn't either => connect them *)
				IF (rc.px = rc.cfx1) & (rc.py = rc.cfy1) THEN rc.disconnected := FALSE END;
				px := rc.px; py := rc.py;
				rc.fu := rc.cfx0; rc.fv := rc.cfy0;
				rc.px := rc.cfx0; rc.py := rc.cfy0;
				AddLine(rc, rc.sx, rc.sy);
				rc.cfx0 := px; rc.cfy0 := py
			ELSE	(* but this one is  *)
			END
		ELSIF (rc.sx # rc.px) OR (rc.sy # rc.py) THEN	(* this subpath isn't closed *)
			rc.cfx0 := rc.px; rc.cfy0 := rc.py; rc.cfx1 := rc.sx; rc.cfy1 := rc.sy;
			rc.disconnected := TRUE
		END
	END ExitLine;
	
	PROCEDURE AddCircle (rc: Context; mx, my, r: LONGINT);
		VAR x, y, d, de, dse: LONGINT; enter, exit: INTEGER;
	BEGIN
		x := 0; y := r; d := 1-r; de := 3; dse := -2*r + 5;
		IF r > 0 THEN enter := -1; exit := 1
		ELSE enter := 1; exit := -1
		END;
		WHILE y >= x DO
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx - y), SHORT(my - x), enter);
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx + y), SHORT(my - x), exit);
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx - x), SHORT(my - y), enter);
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx + x), SHORT(my - y), exit);
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx - x), SHORT(my + y), enter);
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx + x), SHORT(my + y), exit);
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx - y), SHORT(my + x), enter);
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx + y), SHORT(my + x), exit);
			IF d < 0 THEN
				INC(d, de); INC(de, 2); INC(dse, 2); INC(x)
			ELSE
				INC(d, dse); INC(de, 2); INC(dse, 4); INC(x); DEC(y)
			END
		END
	END AddCircle;
	
	PROCEDURE AddEllipse (rc: Context; mx, my, rx, ry: LONGINT);
		VAR x, y, aa, bb, da, db, dy, dx, d: LONGINT; enter, exit: INTEGER;
	BEGIN
		x := rx; y := 0;
		aa := rx * rx; bb := ry * ry;
		da := -8*aa; db := -8*bb;
		dy := -4*aa; dx := -db * (x-1);
		d := bb * (4*x - 1);
		IF rx * ry > 0 THEN enter := -1; exit := 1
		ELSE enter := 1; exit := -1
		END;
		WHILE db * x < da * y DO
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx - x), SHORT(my - y), enter);
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx + x), SHORT(my - y), exit);
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx - x), SHORT(my + y), enter);
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx + x), SHORT(my + y), exit);
			INC(d, dy); INC(dy, da); INC(y);
			IF d < 0 THEN
				INC(d, dx); INC(dx, db); DEC(x)
			END
		END;
		dx := 4 * bb * (2*x - 1); dy := da * (y+1);
		d := d - bb * (4*x - 1) - aa * (4*y + 1);
		WHILE x >= 0 DO
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx - x), SHORT(my - y), enter);
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx + x), SHORT(my - y), exit);
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx - x), SHORT(my + y), enter);
			GfxRegions.AddPoint(rc.pathReg, SHORT(mx + x), SHORT(my + y), exit);
			INC(d, dx); INC(dx, db); DEC(x);
			IF d >= 0 THEN
				INC(d, dy); INC(dy, da); INC(y)
			END
		END
	END AddEllipse;
	
	PROCEDURE BeginRegion (rc: Context);
	BEGIN
		rc.disconnected := FALSE
	END BeginRegion;
	
	PROCEDURE EndRegion (rc: Context);
	BEGIN
		IF rc.disconnected THEN	(* close path with line *)
			rc.fu := rc.cfx0; rc.fv := rc.cfy0;
			rc.px := rc.cfx0; rc.py := rc.cfy0;
			AddLine(rc, rc.cfx1, rc.cfy1)
		END
	END EndRegion;
	
	PROCEDURE EnumRegion (lx, ly, rx, uy: INTEGER; VAR data: GfxRegions.EnumData);
		VAR rc: Context;
	BEGIN
		rc := data(RegData).context;
		rc.rect(rc, lx, ly, rx, uy)
	END EnumRegion;
	
	PROCEDURE FillRegion (rc: Context);
		VAR data: RegData; reg: GfxRegions.Region;
	BEGIN
		reg := rc.pathReg;
		IF ~GfxRegions.Empty(reg) THEN
			data.context := rc;
			GfxRegions.Enumerate(reg, reg.llx, reg.lly, reg.urx, reg.ury, EnumRegion, data)
		END
	END FillRegion;
	
	PROCEDURE AddPathElem (VAR data: GfxPaths.EnumData);
		VAR rc: Context; x, y: REAL;
	BEGIN
		rc := data(PathData).context;
		CASE data.elem OF
		| GfxPaths.Enter:
			EnterLine(rc, data.x, data.y)
		| GfxPaths.Line:
			AddLine(rc, data.x, data.y)
		| GfxPaths.Arc:
			IF IsEllipse(data.x0, data.y0, data.x1, data.y1, data.x2, data.y2, data.x, data.y, rc.u, rc.v, rc.flatness, x, y) THEN
				IF ABS(ABS(x) - ABS(y)) < rc.flatness THEN
					IF x * y > 0 THEN
						AddCircle(rc, ENTIER(data.x0), ENTIER(data.y0), ENTIER(ABS(x) + 0.5))
					ELSE
						AddCircle(rc, ENTIER(data.x0), ENTIER(data.y0), -ENTIER(ABS(x) + 0.5))
					END
				ELSE
					AddEllipse(rc, ENTIER(data.x0), ENTIER(data.y0), ENTIER(ABS(x) + 0.5), ENTIER(ABS(y) + 0.5))
				END
			ELSE
				x := data.x; y := data.y;
				data.x := rc.fu; data.y := rc.fv;
				GfxPaths.EnumArc(data.x0, data.y0, data.x1, data.y1, data.x2, data.y2, x, y, rc.flatness, AddPathElem, data)
			END
		| GfxPaths.Bezier:
			x := data.x; y := data.y;
			data.x := rc.fu; data.y := rc.fv;
			GfxPaths.EnumBezier(data.x1, data.y1, data.x2, data.y2, x, y, rc.flatness, AddPathElem, data)
		| GfxPaths.Exit:
			ExitLine(rc)
		END
	END AddPathElem;
	
	
	(*--- Thick Lines ---*)
	
	PROCEDURE StrokeHalfJoin (rc: Context; cu, cv, u, v, du, dv, hu, hv: REAL; part: LONGINT);
		VAR miter, bevel, round: Gfx.JoinStyle; limit, bu, bv, t: REAL; data: PathData; ps: GfxPaths.Scanner;
	BEGIN
		IF (hu # 0) OR (hv # 0) THEN
			miter := Gfx.MiterJoin; bevel := Gfx.BevelJoin; round := Gfx.RoundJoin;
			IF du * hv > dv * hu THEN
				du := -du; dv := -dv; part := 1 - part	(* turn right turns into left turns *)
			END;
			IF rc.joinStyle = miter THEN
				limit := rc.devWidth * rc.styleLimit
			END;
			IF part = 0 THEN
				IF (rc.joinStyle = bevel) OR (rc.joinStyle = miter) & (hu * hu + hv * hv > limit * limit) THEN
					GfxPaths.IntersectLines(cu, cv, hu, hv, cu + dv, cv - du, -hv, hu, bu, bv);
					EnterLine(rc, bu, bv); AddLine(rc, cu + dv, cv - du)
				ELSIF rc.joinStyle = miter THEN
					bu := cu + hu; bv := cv + hv; EnterLine(rc, bu, bv); AddLine(rc, cu + dv, cv - du)
				ELSIF rc.joinStyle = round THEN
					t := Math.sqrt((du * du + dv * dv)/(hu * hu + hv * hv));
					bu := cu + t * hu; bv := cv + t * hv; EnterLine(rc, bu, bv);
					data.context := rc; data.x := rc.fu; data.y := rc.fv;
					GfxPaths.EnumArc(cu, cv, cu - du, cv - dv, cu + dv, cv - du, cu + dv, cv - du, rc.flatness, AddPathElem, data)
				ELSE
					GfxPaths.Clear(TmpPath);
					rc.joinStyle(rc, cu, cv, du, dv, du, dv, hu, hv, {0}, TmpPath);
					data.context := rc;
					GfxPaths.EnumFlattened(TmpPath, rc.flatness, AddPathElem, data);
					GfxPaths.Open(ps, TmpPath, 0);
					bu := ps.x; bv := ps.y
				END;
				AddLine(rc, u + dv, v - du); AddLine(rc, u - dv, v + du); AddLine(rc, cu, cv); AddLine(rc, bu, bv);
				ExitLine(rc)
			ELSE (* part = 1 *)
				EnterLine(rc, cu, cv); AddLine(rc, u - dv, v + du); AddLine(rc, u + dv, v - du); AddLine(rc, cu + dv, cv - du);
				IF (rc.joinStyle = bevel) OR (rc.joinStyle = miter) & (hu * hu + hv * hv > limit * limit) THEN
					GfxPaths.IntersectLines(cu, cv, hu, hv, cu + dv, cv - du, -hv, hu, bu, bv);
					AddLine(rc, bu, bv)
				ELSIF rc.joinStyle = miter THEN
					AddLine(rc, cu + hu, cv + hv)
				ELSIF rc.joinStyle = round THEN
					t := Math.sqrt((du * du + dv * dv)/(hu * hu + hv * hv));
					data.context := rc; data.x := rc.fu; data.y := rc.fv;
					GfxPaths.EnumArc(cu, cv, cu - du, cv - dv, cu + dv, cv - du, cu + t * hu, cv + t * hv, rc.flatness, AddPathElem, data)
				ELSE
					GfxPaths.Clear(TmpPath);
					rc.joinStyle(rc, cu, cv, du, dv, du, dv, hu, hv, {1}, TmpPath);
					data.context := rc; data.x := rc.fu; data.y := rc.fv;
					GfxPaths.EnumFlattened(TmpPath, rc.flatness, AddPathElem, data)
				END;
				AddLine(rc, cu, cv); ExitLine(rc)
			END
		END
	END StrokeHalfJoin;
	
	PROCEDURE StrokeFullJoin (rc: Context; su, sv, cu, cv, eu, ev, idu, idv, odu, odv, hu, hv: REAL);
		VAR miter, bevel, round: Gfx.JoinStyle; t, limit: REAL; data: PathData;
	BEGIN
		IF (hu # 0) OR (hv # 0) THEN
			miter := Gfx.MiterJoin; bevel := Gfx.BevelJoin; round := Gfx.RoundJoin;
			IF idu * odv < idv * odu THEN	(* turn right turns into left turns *)
				t := idu; idu := -odu; odu := -t;
				t := idv; idv := -odv; odv := -t;
				t := su; su := eu; eu := t;
				t := sv; sv := ev; ev := t
			END;
			IF rc.joinStyle = miter THEN
				limit := rc.devWidth * rc.styleLimit
			END;
			EnterLine(rc, su - idv, sv + idu); AddLine(rc, su + idv, sv - idu); AddLine(rc, cu + idv, cv - idu);
			IF (rc.joinStyle = bevel) OR (rc.joinStyle = miter) & (hu * hu + hv * hv > limit * limit) THEN
				AddLine(rc, cu + odv, cv - odu)
			ELSIF rc.joinStyle = miter THEN
				AddLine(rc, cu + hu, cv + hv)
			ELSIF rc.joinStyle = round THEN
				data.context := rc; data.x := rc.fu; data.y := rc.fv;
				GfxPaths.EnumArc(cu, cv, cu + idv, cv - idu, cu + idu, cv + idv, cu + odv, cv - odu, rc.flatness, AddPathElem, data)
			ELSE
				GfxPaths.Clear(TmpPath);
				rc.joinStyle(rc, cu, cv, idu, idv, odu, odv, hu, hv, {0, 1}, TmpPath);
				data.context := rc; data.x := rc.fu; data.y := rc.fv;
				GfxPaths.EnumFlattened(TmpPath, rc.flatness, AddPathElem, data)
			END;
			AddLine(rc, eu + odv, ev - odu); AddLine(rc, eu - odv, ev + odu); AddLine(rc, su - idv, sv + idu);
			ExitLine(rc)
		END
	END StrokeFullJoin;
	
	PROCEDURE StrokeCap (rc: Context; u, v, du, dv: REAL);
		VAR butt, round, square: Gfx.CapStyle; data: PathData; tu, tv: REAL;
	BEGIN
		butt := Gfx.ButtCap;
		IF rc.capStyle # butt THEN
			round := Gfx.RoundCap; square := Gfx.SquareCap;
			EnterLine(rc, u - dv, v + du);
			IF rc.capStyle = round THEN
				data.context := rc; data.x := rc.fu; data.y := rc.fv;
				GfxPaths.EnumArc(u, v, u - dv, v + du, u - du, v - dv, u + dv, v - du, rc.flatness, AddPathElem, data)
			ELSIF rc.capStyle = square THEN
				AddLine(rc, u - du - dv, v - dv + du); AddLine(rc, u - du + dv, v - dv - du); AddLine(rc, u + dv, v - du)
			ELSE
				GfxPaths.Clear(TmpPath);
				rc.capStyle(rc, u, v, du, dv, TmpPath, tu, tv);
				data.context := rc; data.x := rc.fu; data.y := rc.fv;
				GfxPaths.EnumFlattened(TmpPath, rc.flatness, AddPathElem, data)
			END;
			AddLine(rc, u - dv, v + du); ExitLine(rc)
		END
	END StrokeCap;
	
	PROCEDURE ThickVerticalLine (rc: Context; lu, v0, v1: REAL);
		VAR left, right, bot, top: LONGINT;
	BEGIN
		IF v0 < v1 THEN
			left := ENTIER(lu + 0.5); right := left + ENTIER(2*rc.devWidth + 0.5);
			bot := ENTIER(v0 + 0.5); top := ENTIER(v1 + 0.5)
		ELSE
			right := ENTIER(lu + 0.5); left := right - ENTIER(2*rc.devWidth + 0.5);
			bot := ENTIER(v1 + 0.5); top := ENTIER(v0 + 0.5)
		END;
		rc.rect(rc, SHORT(left), SHORT(bot), SHORT(right), SHORT(top))
	END ThickVerticalLine;
	
	PROCEDURE ThickHorizontalLine (rc: Context; rv, u0, u1: REAL);
		VAR left, right, bot, top: LONGINT;
	BEGIN
		IF u0 < u1 THEN
			left := ENTIER(u0 + 0.5); right := ENTIER(u1 + 0.5);
			bot := ENTIER(rv + 0.5); top := bot + ENTIER(2*rc.devWidth + 0.5)
		ELSE
			left := ENTIER(u1 + 0.5); right := ENTIER(u0 + 0.5);
			top := ENTIER(rv + 0.5); bot := top - ENTIER(2*rc.devWidth + 0.5)
		END;
		rc.rect(rc, SHORT(left), SHORT(bot), SHORT(right), SHORT(top))
	END ThickHorizontalLine;
	
	PROCEDURE ThickLine (rc: Context; su, sv, eu, ev, du, dv: REAL);
	BEGIN
		IF ABS(eu - su) < 0.5 THEN
			ThickVerticalLine(rc, su - dv, sv, ev)
		ELSIF ABS(ev - sv) < 0.5 THEN
			ThickHorizontalLine(rc, sv - du, su, eu)
		ELSE
			EnterLine(rc, su - dv, sv + du);
			AddLine(rc, su + dv, sv - du); AddLine(rc, eu + dv, ev - du);
			AddLine(rc, eu - dv, ev + du); AddLine(rc, su - dv, sv + du);
			ExitLine(rc)
		END
	END ThickLine;
	
	PROCEDURE TrimJoinLength (cu, cv, u, v, du, dv, hu, hv: REAL; VAR tu, tv: REAL);
	BEGIN
		IF (u - cu + hu) * du + (v - cv + hv) * dv < 0 THEN	(* joint is longer than allowed *)
			tu := u; tv := v
		ELSIF du * hv > dv * hu THEN	(* right turn *)
			tu := cu - hu - dv; tv := cv - hv + du
		ELSE
			tu := cu - hu + dv; tv := cv - hv - du
		END
	END TrimJoinLength;
	
	PROCEDURE ThickEnter (rc: Context; u, v, idu, idv: REAL);
	BEGIN
		rc.su := u; rc.sv := v;
		rc.u := u; rc.v := v;
		rc.du := idu; rc.dv := idv;
		InitClipState(rc, SHORT(ENTIER(u)), SHORT(ENTIER(v)))
	END ThickEnter;
	
	PROCEDURE ThickLineTo (rc: Context; u, v: REAL);
		VAR cu, cv, idu, idv, odu, odv, hu, hv, tu, tv: REAL;
	BEGIN
		cu := rc.u; cv := rc.v;
		idu := rc.du; idv := rc.dv;
		Gfx.GetNormVector(u - cu, v - cv, rc.devWidth, odu, odv);
		IF (cu = rc.su) & (cv = rc.sv) THEN	(* first call *)
			IF (idu = 0) & (idv = 0) THEN
				StrokeCap(rc, cu, cv, odu, odv);
				rc.tu := cu; rc.tv := cv
			ELSE	(* render initial joint *)
				Gfx.GetNormVector(idu, idv, rc.devWidth, idu, idv);
				Gfx.GetHalfAxisVector(idu, idv, odu, odv, hu, hv);
				IF (hu = 0) & (hv = 0) THEN
					rc.tu := cu; rc.tv := cv
				ELSE
					TrimJoinLength(cu, cv, 0.5*(cu + u), 0.5*(cv + v), odu, odv, hu, hv, rc.tu, rc.tv);
					StrokeHalfJoin(rc, cu, cv, rc.tu, rc.tv, odu, odv, hu, hv, 0)
				END
			END
		ELSE
			UpdateClipState(rc, SHORT(ENTIER(cu)), SHORT(ENTIER(cv)));
			Gfx.GetHalfAxisVector(idu, idv, odu, odv, hu, hv);
			IF (hu = 0) & (hv = 0) THEN
				tu := cu; tv := cv
			ELSE
				TrimJoinLength(cu, cv, rc.tu, rc.tv, -idu, -idv, hu, hv, tu, tv)
			END;
			IF (tu - rc.tu) * idu + (tv - rc.tv) * idv > 0 THEN
				ThickLine(rc, rc.tu, rc.tv, tu, tv, idu, idv)
			END;
			IF (hu = 0) & (hv = 0) THEN
				rc.tu := cu; rc.tv := cv
			ELSE
				TrimJoinLength(cu, cv, 0.5*(cu + u), 0.5*(cv + v), odu, odv, hu, hv, rc.tu, rc.tv);
				StrokeFullJoin(rc, tu, tv, cu, cv, rc.tu, rc.tv, idu, idv, odu, odv, hu, hv)
			END
		END;
		rc.su := cu; rc.sv := cv;
		rc.u := u; rc.v := v;
		rc.du := odu; rc.dv := odv
	END ThickLineTo;
	
	PROCEDURE ThickExit (rc: Context; odu, odv: REAL);
		VAR cu, cv, idu, idv, hu, hv, tu, tv: REAL;
	BEGIN
		cu := rc.u; cv := rc.v;
		IF (cu # rc.su) OR (cv # rc.sv) THEN	(* at least one thick line was rendered *)
			idu := rc.du; idv := rc.dv;
			UpdateClipState(rc, SHORT(ENTIER(cu)), SHORT(ENTIER(cv)));
			IF (odu = 0) & (odv = 0) THEN
				ThickLine(rc, rc.tu, rc.tv, cu, cv, idu, idv);
				StrokeCap(rc, cu, cv, -idu, -idv)
			ELSE
				Gfx.GetNormVector(odu, odv, rc.devWidth, odu, odv);
				Gfx.GetHalfAxisVector(idu, idv, odu, odv, hu, hv);
				IF (hu = 0) & (hv = 0) THEN
					tu := cu; tv := cv
				ELSE
					TrimJoinLength(cu, cv, rc.tu, rc.tv, -idu, -idv, hu, hv, tu, tv)
				END;
				IF (tu - rc.tu) * idu + (tv - rc.tv) * idv > 0 THEN
					ThickLine(rc, rc.tu, rc.tv, tu, tv, idu, idv)
				END;
				IF (hu # 0) OR (hv # 0) THEN
					StrokeHalfJoin(rc, cu, cv, tu, tv, idu, idv, hu, hv, 1)
				END
			END
		END
	END ThickExit;
	
	
	(*--- Dashed Lines ---*)
	
	PROCEDURE DashEnter (rc: Context; su, sv, idu, idv: REAL);
		VAR beg, end, next: REAL; index: LONGINT;
	BEGIN
		rc.offset := 0;
		Gfx.GetDashOffsets(rc, 0, beg, end, next, index);
		IF end > 0 THEN
			IF rc.devWidth <= 0.75 THEN HairLineEnter(rc, su, sv)
			ELSE ThickEnter(rc, su, sv, idu, idv)
			END
		ELSE
			rc.u := su; rc.v := sv
		END
	END DashEnter;
	
	PROCEDURE DashLineTo (rc: Context; u, v: REAL);
		VAR cu, cv, du, dv, len, cos, sin, wdu, wdv, offset, beg, end, next, dash, tu, tv: REAL; index: LONGINT;
	BEGIN
		cu := rc.u; cv := rc.v;
		du := u - cu; dv := v - cv;
		len := Math.sqrt(du * du + dv * dv);
		cos := du/len; sin := dv/len;
		wdu := rc.devWidth * cos; wdv := rc.devWidth * sin;
		offset := rc.offset; rc.offset := offset + len;
		Gfx.GetDashOffsets(rc, offset, beg, end, next, index);
		IF offset < end THEN	(* inside dash *)
			IF end <= rc.offset THEN	(* finish current dash *)
				len := end - offset;
				IF rc.devWidth <= 0.75 THEN
					HairLineTo(rc, cu + len * cos, cv + len * sin)
				ELSE
					ThickLineTo(rc, cu + len * cos, cv + len * sin);
					ThickExit(rc, 0, 0)
				END
			ELSIF rc.devWidth <= 0.75 THEN
				HairLineTo(rc, u, v)
			ELSE
				ThickLineTo(rc, u, v)
			END
		END;
		beg := offset;
		LOOP
			len := next - beg;
			cu := cu + len * cos; cv := cv + len * sin;
			beg := next;
			GfxMatrix.ApplyToDist(rc.cam, rc.dashPatOn[index], dash);
			end := beg + dash;
			GfxMatrix.ApplyToDist(rc.cam, rc.dashPatOff[index], dash);
			next := end + dash;
			index := (index+1) MOD rc.dashPatLen;
			IF end > rc.offset THEN EXIT END;
			len := end - beg;
			IF rc.devWidth <= 0.75 THEN
				HairLineEnter(rc, cu, cv);
				HairLineTo(rc, cu + len * cos, cv + len * sin)
			ELSE
				StrokeCap(rc, cu, cv, wdu, wdv);
				InitClipState(rc, SHORT(ENTIER(cu)), SHORT(ENTIER(cv)));
				tu := cu + len * cos; tv := cv + len * sin;
				UpdateClipState(rc, SHORT(ENTIER(tu)), SHORT(ENTIER(tv)));
				ThickLine(rc, cu, cv, tu, tv, wdu, wdv);
				StrokeCap(rc, tu, tv, -wdu, -wdv)
			END
		END;
		IF beg <= rc.offset THEN	(* begin next dash *)
			IF rc.devWidth <= 0.75 THEN
				HairLineEnter(rc, cu, cv);
				HairLineTo(rc, u, v)
			ELSE
				ThickEnter(rc, cu, cv, 0, 0);
				ThickLineTo(rc, u, v)
			END
		ELSE
			rc.u := u; rc.v := v
		END
	END DashLineTo;
	
	PROCEDURE DashExit (rc: Context; odu, odv: REAL);
		VAR beg, end, next: REAL; index: LONGINT;
	BEGIN
		Gfx.GetDashOffsets(rc, rc.offset, beg, end, next, index);
		IF (beg < rc.offset) & (rc.offset < end) & (rc.devWidth > 0.75) THEN
			ThickExit(rc, odu, odv)
		END
	END DashExit;
	
	
	(*--- Stroking ---*)
	
	PROCEDURE StrokePrepare (rc: Context);
	BEGIN
		GfxMatrix.ApplyToDist(rc.cam, 0.5*rc.lineWidth, rc.devWidth);
		IF rc.devWidth <= 0.75 THEN
			rc.border := 1
		ELSE
			rc.border := -SHORT(ENTIER(-rc.devWidth * rc.styleLimit));
		END;
		rc.setColPat(rc, rc.strokeCol, rc.strokePat)
	END StrokePrepare;
	
	PROCEDURE StrokeEnter (rc: Context; u, v, du, dv: REAL);
	BEGIN
		IF rc.devWidth > 0.75 THEN
			GfxRegions.Clear(rc.pathReg);
			BeginRegion(rc)
		END;
		IF rc.dashPatLen > 0 THEN
			DashEnter(rc, u, v, du, dv)
		ELSIF rc.devWidth <= 0.75 THEN
			HairLineEnter(rc, u, v)
		ELSE
			ThickEnter(rc, u, v, du, dv)
		END
	END StrokeEnter;
	
	PROCEDURE StrokeLineTo (rc: Context; u, v: REAL);
	BEGIN
		IF rc.dashPatLen > 0 THEN
			DashLineTo(rc, u, v)
		ELSIF rc.devWidth <= 0.75 THEN
			HairLineTo(rc, u, v)
		ELSE
			ThickLineTo(rc, u, v)
		END
	END StrokeLineTo;
	
	PROCEDURE StrokeExit (rc: Context; du, dv: REAL);
	BEGIN
		IF rc.dashPatLen > 0 THEN
			DashExit(rc, du, dv)
		ELSIF rc.devWidth > 0.75 THEN
			ThickExit(rc, du, dv)
		END;
		IF rc.devWidth > 0.75 THEN
			EndRegion(rc);
			GfxRegions.Intersect(rc.pathReg, rc.clipReg);
			IF ~GfxRegions.Empty(rc.pathReg) THEN
				rc.clipState := In;
				FillRegion(rc)
			END
		END
	END StrokeExit;
	
	PROCEDURE StrokePathElem (VAR data: GfxPaths.EnumData);
		VAR rc: Context; x, y: REAL;
	BEGIN
		rc := data(PathData).context;
		CASE data.elem OF
		| GfxPaths.Enter:
			StrokeEnter(rc, data.x, data.y, data.dx, data.dy)
		| GfxPaths.Line:
			IF (data.x # rc.u) OR (data.y # rc.v) THEN
				StrokeLineTo(rc, data.x, data.y)
			END
		| GfxPaths.Arc:
			IF (rc.dashPatLen = 0) & (rc.devWidth <= 0.75) &
				IsEllipse(data.x0, data.y0, data.x1, data.y1, data.x2, data.y2, data.x, data.y, rc.u, rc.v, rc.flatness, x, y)
			THEN
				IF ABS(ABS(x) - ABS(y)) < rc.flatness THEN
					IF x * y > 0 THEN
						HairCircle(rc, ENTIER(data.x0), ENTIER(data.y0), ENTIER(ABS(x) + 0.5))
					ELSE
						HairCircle(rc, ENTIER(data.x0), ENTIER(data.y0), -ENTIER(ABS(x) + 0.5))
					END
				ELSE
					HairEllipse(rc, ENTIER(data.x0), ENTIER(data.y0), ENTIER(ABS(x) + 0.5), ENTIER(ABS(y) + 0.5))
				END
			ELSE
				x := data.x; y := data.y;
				data.x := rc.u; data.y := rc.v;
				GfxPaths.EnumArc(data.x0, data.y0, data.x1, data.y1, data.x2, data.y2, x, y, rc.flatness, StrokePathElem, data)
			END
		| GfxPaths.Bezier:
			x := data.x; y := data.y;
			data.x := rc.u; data.y := rc.v;
			GfxPaths.EnumBezier(data.x1, data.y1, data.x2, data.y2, x, y, rc.flatness, StrokePathElem, data)
		| GfxPaths.Exit:
			StrokeExit(rc, data.dx, data.dy)
		END
	END StrokePathElem;
	
	
	(**--- Path Methods ---**)
	
	PROCEDURE Begin* (ctxt: Gfx.Context; mode: SET);
		VAR rc: Context;
	BEGIN
		rc := ctxt(Context);
		rc.mode := mode * {Gfx.Record..Gfx.EvenOdd};
		rc.cam := rc.ctm;	(* preserve current transformation for attributes *)
		IF Gfx.Record IN rc.mode THEN
			IF rc.path = NIL THEN NEW(rc.path) END;
			GfxPaths.Clear(rc.path)
		END;
		rc.useRegion := {Gfx.Clip, Gfx.Fill} * rc.mode # {};
		rc.lateStroke := rc.useRegion & (Gfx.Stroke IN rc.mode);
		IF rc.lateStroke THEN
			IF rc.cp = NIL THEN NEW(rc.cp) END;
			GfxPaths.Clear(rc.cp)
		END;
		IF Gfx.Stroke IN rc.mode THEN
			StrokePrepare(rc)
		END;
		IF rc.useRegion OR (Gfx.Stroke IN rc.mode) & (rc.devWidth > 0.75) THEN
			IF rc.pathReg = NIL THEN NEW(rc.pathReg) END;
			IF Gfx.EvenOdd IN rc.mode THEN
				GfxRegions.Init(rc.pathReg, GfxRegions.EvenOdd)
			ELSE
				GfxRegions.Init(rc.pathReg, GfxRegions.Winding)
			END
		END;
		IF rc.useRegion THEN
			BeginRegion(rc)
		END
	END Begin;
	
	PROCEDURE End* (ctxt: Gfx.Context);
		VAR rc: Context; data: PathData;
	BEGIN
		rc := ctxt(Context);
		IF rc.useRegion THEN
			EndRegion(rc)
		END;
		IF Gfx.Clip IN rc.mode THEN
			GfxRegions.Intersect(rc.clipReg, rc.pathReg)
		END;
		IF Gfx.Fill IN rc.mode THEN
			GfxRegions.Intersect(rc.pathReg, rc.clipReg);
			IF ~GfxRegions.Empty(rc.pathReg) THEN
				rc.clipState := In;
				rc.setColPat(rc, rc.fillCol, rc.fillPat);
				FillRegion(rc)
			END
		END;
		IF rc.lateStroke THEN
			rc.setColPat(rc, rc.strokeCol, rc.strokePat);
			data.context := rc;
			GfxPaths.Enumerate(rc.cp, StrokePathElem, data)
		END
	END End;
	
	PROCEDURE Enter* (ctxt: Gfx.Context; x, y, dx, dy: REAL);
		VAR rc: Context; u, v, du, dv: REAL;
	BEGIN
		rc := ctxt(Context);
		GfxMatrix.Apply(rc.ctm, x, y, u, v);
		GfxMatrix.ApplyToVector(rc.ctm, dx, dy, du, dv);
		IF Gfx.Record IN rc.mode THEN
			GfxPaths.AddEnter(rc.path, u, v, du, dv)
		END;
		IF rc.lateStroke THEN
			GfxPaths.AddEnter(rc.cp, u, v, du, dv)
		END;
		IF rc.useRegion THEN
			EnterLine(rc, u, v);
			rc.u := u; rc.v := v
		ELSIF Gfx.Stroke IN rc.mode THEN
			StrokeEnter(rc, u, v, du, dv)
		ELSE
			rc.u := u; rc.v := v
		END;
		rc.cpx := x; rc.cpy := y
	END Enter;
	
	PROCEDURE Exit* (ctxt: Gfx.Context; dx, dy: REAL);
		VAR rc: Context; du, dv: REAL;
	BEGIN
		rc := ctxt(Context);
		GfxMatrix.ApplyToVector(rc.ctm, dx, dy, du, dv);
		IF Gfx.Record IN rc.mode THEN
			GfxPaths.AddExit(rc.path, du, dv)
		END;
		IF rc.lateStroke THEN
			GfxPaths.AddExit(rc.cp, du, dv)
		END;
		IF rc.useRegion THEN
			ExitLine(rc)
		ELSIF Gfx.Stroke IN rc.mode THEN
			StrokeExit(rc, du, dv)
		END
	END Exit;
	
	PROCEDURE Line* (ctxt: Gfx.Context; x, y: REAL);
		VAR rc: Context; u, v: REAL;
	BEGIN
		rc := ctxt(Context);
		GfxMatrix.Apply(ctxt.ctm, x, y, u, v);
		IF (u # rc.u) OR (v # rc.v) THEN
			IF Gfx.Record IN rc.mode THEN
				GfxPaths.AddLine(rc.path, u, v)
			END;
			IF rc.lateStroke THEN
				GfxPaths.AddLine(rc.cp, u, v)
			END;
			IF rc.useRegion THEN
				AddLine(rc, u, v);
				rc.u := u; rc.v := v
			ELSIF Gfx.Stroke IN rc.mode THEN
				StrokeLineTo(rc, u, v)
			ELSE
				rc.u := u; rc.v := v
			END;
			rc.cpx := x; rc.cpy := y
		END
	END Line;
	
	PROCEDURE Arc* (ctxt: Gfx.Context; x, y, x0, y0, x1, y1, x2, y2: REAL);
		VAR rc: Context; u, v, u0, v0, u1, v1, u2, v2, ru, rv: REAL; data: PathData;
	BEGIN
		rc := ctxt(Context);
		GfxMatrix.Apply(rc.ctm, x, y, u, v);
		GfxMatrix.Apply(rc.ctm, x0, y0, u0, v0);
		GfxMatrix.Apply(rc.ctm, x1, y1, u1, v1);
		GfxMatrix.Apply(rc.ctm, x2, y2, u2, v2);
		IF Gfx.Record IN rc.mode THEN
			GfxPaths.AddArc(rc.path, u, v, u0, v0, u1, v1, u2, v2)
		END;
		IF rc.lateStroke THEN
			GfxPaths.AddArc(rc.cp, u, v, u0, v0, u1, v1, u2, v2)
		END;
		IF rc.useRegion THEN
			IF IsEllipse(u0, v0, u1, v1, u2, v2, rc.u, rc.v, u, v, rc.flatness, ru, rv) THEN
				IF ABS(ABS(ru) - ABS(rv)) < rc.flatness THEN
					IF ru * rv > 0 THEN
						AddCircle(rc, ENTIER(u0), ENTIER(v0), ENTIER(ABS(ru) + 0.5))
					ELSE
						AddCircle(rc, ENTIER(u0), ENTIER(v0), -ENTIER(ABS(ru) + 0.5))
					END
				ELSE
					AddEllipse(rc, ENTIER(u0), ENTIER(v0), ENTIER(ABS(ru) + 0.5), ENTIER(ABS(rv) + 0.5))
				END
			ELSE
				data.context := rc(Context); data.x := rc.u; data.y := rc.v;
				GfxPaths.EnumArc(u0, v0, u1, v1, u2, v2, u, v, rc.flatness, AddPathElem, data);
				rc.u := u; rc.v := v
			END
		ELSIF Gfx.Stroke IN rc.mode THEN
			IF (rc.dashPatLen = 0) & (rc.devWidth <= 0.75) &
				IsEllipse(u0, v0, u1, v1, u2, v2, rc.u, rc.v, u, v, rc.flatness, ru, rv)
			THEN
				IF ABS(ABS(ru) - ABS(rv)) < rc.flatness THEN
					IF ru * rv > 0 THEN
						HairCircle(rc, ENTIER(u0), ENTIER(v0), ENTIER(ABS(ru) + 0.5))
					ELSE
						HairCircle(rc, ENTIER(u0), ENTIER(v0), -ENTIER(ABS(ru) + 0.5))
					END
				ELSE
					HairEllipse(rc, ENTIER(u0), ENTIER(v0), ENTIER(ABS(ru) + 0.5), ENTIER(ABS(rv) + 0.5))
				END
			ELSE
				data.context := rc; data.x := rc.u; data.y := rc.v;
				GfxPaths.EnumArc(u0, v0, u1, v1, u2, v2, u, v, rc.flatness, StrokePathElem, data)
			END
		END;
		rc.cpx := x; rc.cpy := y
	END Arc;
	
	PROCEDURE Bezier* (ctxt: Gfx.Context; x, y, x1, y1, x2, y2: REAL);
		VAR rc: Context; u, v, u1, v1, u2, v2: REAL; data: PathData;
	BEGIN
		rc := ctxt(Context);
		GfxMatrix.Apply(rc.ctm, x, y, u, v);
		GfxMatrix.Apply(rc.ctm, x1, y1, u1, v1);
		GfxMatrix.Apply(rc.ctm, x2, y2, u2, v2);
		IF Gfx.Record IN rc.mode THEN
			GfxPaths.AddBezier(rc.path, u, v, u1, v1, u2, v2)
		END;
		IF rc.lateStroke THEN
			GfxPaths.AddBezier(rc.cp, u, v, u1, v1, u2, v2)
		END;
		IF rc.useRegion THEN
			data.context := rc(Context); data.x := rc.u; data.y := rc.v;
			GfxPaths.EnumBezier(u1, v1, u2, v2, u, v, rc.flatness, AddPathElem, data);
			rc.u := u; rc.v := v
		ELSIF Gfx.Stroke IN rc.mode THEN
			data.context := rc(Context); data.x := rc.u; data.y := rc.v;
			GfxPaths.EnumBezier(u1, v1, u2, v2, u, v, rc.flatness, StrokePathElem, data)
		END;
		rc.cpx := x; rc.cpy := y
	END Bezier;
	
	PROCEDURE Show* (ctxt: Gfx.Context; x, y: REAL; VAR str: ARRAY OF CHAR);
		VAR
			rc: Context; mat: GfxMatrix.Matrix; font: GfxFonts.Font; u, v, bu, bv, du, dv: REAL; i: LONGINT;
			map: GfxMaps.Map; data: PathData;
	BEGIN
		rc := ctxt(Context);
		GfxMatrix.Concat(rc.font.mat, rc.ctm, mat);
		font := GfxFonts.Open(rc.font.name, rc.font.ptsize, mat);
		GfxMatrix.Apply(rc.ctm, x, y, u, v);
		IF (rc.mode * {Gfx.Record..Gfx.EvenOdd} = {Gfx.Fill}) & (rc.fillPat = NIL) THEN
			mat := rc.ctm; rc.ctm := GfxMatrix.Identity;
			rc.setColPat(rc, rc.fillCol, rc.fillPat);
			i := 0;
			WHILE str[i] # 0X DO
				GfxFonts.GetMap(font, str[i], bu, bv, du, dv, map);
				IF map # NIL THEN
					rc.do.image(rc, u + bu, v + bv, map, GfxMaps.NoFilter)
				END;
				u := u + du; v := v + dv;
				INC(i)
			END;
			rc.ctm := mat
		ELSE
			i := 0;
			WHILE str[i] # 0X DO
				GfxFonts.GetOutline(font, str[i], u, v, TmpPath);
				GfxFonts.GetWidth(font, str[i], du, dv);
				u := u + du; v := v + dv;
				IF Gfx.Record IN rc.mode THEN
					GfxPaths.Append(rc.path, TmpPath)
				END;
				IF rc.lateStroke THEN
					GfxPaths.Append(rc.cp, TmpPath)
				END;
				IF rc.useRegion THEN
					data.context := rc;
					GfxPaths.Enumerate(TmpPath, AddPathElem, data);
					rc.u := rc.fu; rc.v := rc.fv
				ELSIF Gfx.Stroke IN rc.mode THEN
					data.context := rc;
					GfxPaths.Enumerate(TmpPath, StrokePathElem, data)
				END;
				INC(i)
			END
		END;
		GfxMatrix.Solve(rc.ctm, u, v, rc.cpx, rc.cpy)
	END Show;
	
	PROCEDURE Render* (ctxt: Gfx.Context; mode: SET);
		VAR rc: Context; data: PathData;
	BEGIN
		rc := ctxt(Context);
		IF mode * {Gfx.Clip, Gfx.Fill} # {} THEN
			IF rc.pathReg = NIL THEN NEW(rc.pathReg) END;
			IF Gfx.EvenOdd IN mode THEN
				GfxRegions.Init(rc.pathReg, GfxRegions.EvenOdd)
			ELSE
				GfxRegions.Init(rc.pathReg, GfxRegions.Winding)
			END;
			BeginRegion(rc);
			data.context := rc;
			GfxPaths.Enumerate(rc.path, AddPathElem, data);
			EndRegion(rc);
			GfxRegions.Intersect(rc.pathReg, rc.clipReg);
			IF Gfx.Clip IN mode THEN
				GfxRegions.Copy(rc.pathReg, rc.clipReg)
			END;
			IF Gfx.Fill IN mode THEN
				rc.clipState := In;
				rc.setColPat(rc, rc.fillCol, rc.fillPat);
				FillRegion(rc)
			END
		END;
		IF Gfx.Stroke IN mode THEN
			rc.cam := rc.ctm;
			StrokePrepare(rc);
			IF rc.devWidth > 0.75 THEN
				IF rc.pathReg = NIL THEN NEW(rc.pathReg) END;
				IF Gfx.EvenOdd IN rc.mode THEN
					GfxRegions.Init(rc.pathReg, GfxRegions.EvenOdd)
				ELSE
					GfxRegions.Init(rc.pathReg, GfxRegions.Winding)
				END
			END;
			data.context := rc;
			GfxPaths.Enumerate(rc.path, StrokePathElem, data)
		END
	END Render;
	
	PROCEDURE Rect* (ctxt: Gfx.Context; x0, y0, x1, y1: REAL);
		VAR rc: Context; u0, v0, u1, v1, t: REAL; enter, exit, llx, lly, urx, ury: INTEGER;
	BEGIN
		IF ~(Gfx.Record IN ctxt.mode) & ~GfxMatrix.Rotated(ctxt.ctm) THEN
			rc := ctxt(Context);
			GfxMatrix.Apply(rc.ctm, x0, y0, u0, v0);
			GfxMatrix.Apply(rc.ctm, x1, y1, u1, v1);
			enter := -1; exit := 1;
			IF u0 > u1 THEN t := u0; u0 := u1; u1 := t END;
			IF v0 > v1 THEN t := v0; v0 := v1; v1 := t; enter := -enter; exit := -exit END;
			IF rc.lateStroke THEN
				GfxPaths.AddRect(rc.cp, u0, v0, u1, v1)
			END;
			IF rc.useRegion THEN
				llx := SHORT(ENTIER(u0 + 0.5)); lly := SHORT(ENTIER(v0 + 0.5));
				urx := SHORT(ENTIER(u1 + 0.5)); ury := SHORT(ENTIER(v1 + 0.5));
				IF Gfx.Clip IN rc.mode THEN
					WHILE lly < ury DO
						GfxRegions.AddPoint(rc.pathReg, llx, lly, enter);
						INC(lly);
						GfxRegions.AddPoint(rc.pathReg, urx, lly, exit)
					END
				ELSIF GfxRegions.RectOverlaps(llx, lly, urx, ury, rc.clipReg) THEN
					IF GfxRegions.RectInside(llx, lly, urx, ury, rc.clipReg) THEN rc.clipState := In
					ELSE rc.clipState := InOut
					END;
					rc.setColPat(rc, rc.fillCol, rc.fillPat);
					rc.rect(rc, llx, lly, urx, ury)
				END
			ELSIF Gfx.Stroke IN rc.mode THEN
				IF (rc.dashPatLen > 0) OR (rc.devWidth > 0.75) THEN
					StrokeEnter(rc, u0, v0, 0, v0 - v1);
					StrokeLineTo(rc, u1, v0); StrokeLineTo(rc, u1, v1); StrokeLineTo(rc, u0, v1); StrokeLineTo(rc, u0, v0);
					StrokeExit(rc, u1 - u0, 0)
				ELSE
					llx := SHORT(ENTIER(u0)); lly := SHORT(ENTIER(v0));
					urx := SHORT(ENTIER(u1)); ury := SHORT(ENTIER(v1));
					IF GfxRegions.RectOverlaps(llx, lly, urx, ury, rc.clipReg) THEN
						IF GfxRegions.RectInside(llx, lly, urx, ury, rc.clipReg) THEN rc.clipState := In
						ELSE rc.clipState := InOut
						END;
						rc.rect(rc, llx, lly, urx, lly+1); rc.rect(rc, urx, lly, urx+1, ury+1);
						rc.rect(rc, llx, ury, urx, ury+1); rc.rect(rc, llx, lly+1, llx+1, ury)
					END
				END 
			END
		ELSE
			Gfx.DefRect(ctxt, x0, y0, x1, y1)
		END
	END Rect;
	
	PROCEDURE Ellipse* (ctxt: Gfx.Context; x, y, rx, ry: REAL);
		VAR rc: Context; u, v, ru, rv: REAL; data: PathData;
	BEGIN
		IF ~(Gfx.Record IN ctxt.mode) & ~GfxMatrix.Rotated(ctxt.ctm) THEN
			rc := ctxt(Context);
			GfxMatrix.Apply(rc.ctm, x, y, u, v);
			GfxMatrix.ApplyToVector(rc.ctm, rx, ry, ru, rv);
			IF rc.lateStroke THEN
				GfxPaths.AddEnter(rc.cp, u + ru, v, 0, rv);
				GfxPaths.AddArc(rc.cp, u + ru, v, u, v, u + ru, v, u, v + rv);
				GfxPaths.AddExit(rc.cp, 0, rv)
			END;
			IF rc.useRegion THEN
				AddEllipse(rc, ENTIER(u), ENTIER(v), ENTIER(ru + 0.5), ENTIER(rv + 0.5))
			ELSIF Gfx.Stroke IN rc.mode THEN
				IF (rc.dashPatLen = 0) & (rc.devWidth <= 0.75) THEN
					HairEllipse(rc, ENTIER(u), ENTIER(v), ENTIER(ru + 0.5), ENTIER(rv + 0.5))
				ELSE
					StrokeEnter(rc, u + ru, v, 0, rv);
					data.context := rc; data.x := rc.u; data.y := rc.v;
					GfxPaths.EnumArc(u, v, u + ru, v, u, v + rv, u + ru, v, rc.flatness, StrokePathElem, data);
					StrokeExit(rc, 0, rv)
				END
			END
		ELSE
			Gfx.DefEllipse(ctxt, x, y, rx, ry)
		END
	END Ellipse;
	
	
	(**--- Raster Contexts ---**)
	
	PROCEDURE SetColPat* (rc: Context; col: Gfx.Color; pat: Gfx.Pattern);
	BEGIN
		rc.col := col; rc.pat := pat
	END SetColPat;
	
	(** initialize raster context **)
	PROCEDURE InitContext* (rc: Context);
	BEGIN
		rc.setColPat := SetColPat;
		NEW(rc.clipReg);
		GfxRegions.Init(rc.clipReg, GfxRegions.Winding);
		rc.clipReg.next := NIL
	END InitContext;
	

BEGIN
	NEW(TmpPath)
END GfxRaster.
