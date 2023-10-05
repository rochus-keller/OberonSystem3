MODULE GfxPrinter;	(** eos   **)

	(**
		Raster contexts rendering to Oberon printer
	**)
	
	(*
		10.12.98 - first version; derived from GfxDev
	*)
	
	IMPORT
		Display, Fonts, Printer, GfxMatrix, GfxMaps, GfxRegions, GfxFonts, Gfx, GfxRaster;
		
	
	CONST
		R = GfxMaps.R; G = GfxMaps.G; B = GfxMaps.B; A = GfxMaps.A;
		
	
	TYPE
		Context* = POINTER TO ContextDesc;
		ContextDesc* = RECORD (GfxRaster.ContextDesc)
			orgX*, orgY*: REAL;	(** origin of default coordinate system **)
			scale*: REAL;	(** scale factor of default coordinate system **)
			defClip*: GfxRegions.Region;	(** default clipping region **)
			prcol: Gfx.Color;
		END;
		
		RegData = RECORD (GfxRegions.EnumData)
			pc: Context;
			dx, dy: INTEGER;
			map: GfxMaps.Map;
		END;
		
	
	VAR
		Methods: Gfx.Methods;
		
	
	(*--- Rendering ---*)
	
	PROCEDURE UseColor (pc: Context; col: Gfx.Color);
	BEGIN
		IF (col.r # pc.prcol.r) OR (col.g # pc.prcol.g) OR (col.b # pc.prcol.b) THEN
			Printer.UseColor(col.r, col.g, col.b);
			pc.prcol := col
		END
	END UseColor;
	
	PROCEDURE Color (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
	BEGIN
		WITH data: RegData DO
			UseColor(data.pc, data.pc.col);
			Printer.ReplConst(llx, lly, urx - llx, ury - lly)
		END
	END Color;
	
	PROCEDURE CopyImage (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
		VAR col: Gfx.Color; y, x, len: INTEGER; pix: GfxMaps.Pixel;
	BEGIN
		WITH data: RegData DO
			col.r := -1; col.g := -1; col.b := -1;
			y := lly;
			WHILE y < ury DO
				x := llx; len := 0;
				WHILE x + len < urx DO
					GfxMaps.Get(data.map, x - data.dx + len, y - data.dy, pix, GfxMaps.SrcCopy);
					IF pix[A] # 0X THEN	(* pixel visible; already blended *)
						IF (ORD(pix[R]) = col.r) & (ORD(pix[G]) = col.g) & (ORD(pix[B]) = col.b) THEN	(* same color as last pixel *)
							INC(len)
						ELSE
							IF len > 0 THEN
								UseColor(data.pc, col);
								Printer.ReplConst(x, y, len, 1);
								INC(x, len)
							END;
							col.r := ORD(pix[R]); col.g := ORD(pix[G]); col.b := ORD(pix[B]);
							len := 1
						END
					ELSIF len > 0 THEN
						UseColor(data.pc, col);
						Printer.ReplConst(x, y, len, 1);
						INC(x, len); len := 0
					ELSE
						INC(x)
					END
				END;
				IF len > 0 THEN
					UseColor(data.pc, col);
					Printer.ReplConst(x, y, len, 1)
				END;
				INC(y)
			END
		END
	END CopyImage;
	
	PROCEDURE Tile (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
		VAR mw, mh, mx, my, y, x, len: INTEGER; col: Gfx.Color; white, buf: GfxMaps.Pixel;
	BEGIN
		WITH data: RegData DO
			mw := data.map.width; mh := data.map.height;
			col.r := -1; col.g := -1; col.b := -1;
			white[R] := 0FFX; white[G] := 0FFX; white[B] := 0FFX; white[A] := 0FFX;
			y := lly; my := (lly - data.dy) MOD mh;
			WHILE y < ury DO
				x := llx; mx := (llx - data.dx) MOD mw; len := 0;
				WHILE x + len < urx DO
					buf := white;
					GfxMaps.Get(data.map, mx, my, buf, GfxMaps.SrcCopy);
					IF buf[A] # 0X THEN
						IF (col.r = ORD(buf[R])) & (col.g = ORD(buf[G])) & (col.b = ORD(buf[B])) THEN
							INC(len)
						ELSE
							IF len > 0 THEN
								UseColor(data.pc, col);
								Printer.ReplConst(x, y, len, 1);
								INC(x, len)
							END;
							col.r := ORD(buf[R]); col.g := ORD(buf[G]); col.b := ORD(buf[B]);
							len := 1
						END
					ELSE
						IF len > 0 THEN
							UseColor(data.pc, col);
							Printer.ReplConst(x, y, len, 1);
							INC(x, len); len := 0
						END;
						INC(x)
					END;
					mx := (mx + 1) MOD mw
				END;
				IF len > 0 THEN
					UseColor(data.pc, col);
					Printer.ReplConst(x, y, len, 1)
				END;
				INC(y); my := (my + 1) MOD mh
			END
		END
	END Tile;
	
	PROCEDURE Dot (rc: GfxRaster.Context; x, y: LONGINT);
		VAR pc: Context; px, py: INTEGER; pix: GfxMaps.Pixel; col: Gfx.Color;
	BEGIN
		IF (rc.clipState = GfxRaster.In) OR
			(rc.clipState = GfxRaster.InOut) & GfxRegions.RectInside(SHORT(x), SHORT(y), SHORT(x+1), SHORT(y+1), rc.clipReg)
		THEN
			pc := rc(Context);
			IF rc.pat = NIL THEN
				UseColor(pc, pc.col);
				Printer.ReplConst(SHORT(x), SHORT(y), 1, 1)
			ELSE
				pc.pat.map.fmt.col := pc.col;
				px := SHORT(x - ENTIER(pc.orgX + pc.pat.px + 0.5)) MOD pc.pat.map.width;
				py := SHORT(y - ENTIER(pc.orgY + pc.pat.py + 0.5)) MOD pc.pat.map.height;
				pix[R] := 0FFX; pix[G] := 0FFX; pix[B] := 0FFX; pix[A] := 0FFX;
				GfxMaps.GetPixels(pc.pat.map, px, py, 1, GfxMaps.PixelFormat, pix, GfxMaps.SrcAlpha);
				IF pix[A] # 0X THEN
					col.r := ORD(pix[R]); col.g := ORD(pix[G]); col.b := ORD(pix[B]);
					UseColor(pc, col);
					Printer.ReplConst(SHORT(x), SHORT(y), 1, 1)
				END
			END
		END
	END Dot;
	
	PROCEDURE Rect (rc: GfxRaster.Context; llx, lly, urx, ury: LONGINT);
		VAR pc: Context; data: RegData;
	BEGIN
		IF rc.clipState # GfxRaster.Out THEN
			pc := rc(Context);
			IF pc.pat = NIL THEN
				IF pc.clipState = GfxRaster.In THEN
					UseColor(pc, pc.col);
					Printer.ReplConst(SHORT(llx), SHORT(lly), SHORT(urx - llx), SHORT(ury - lly))
				ELSE
					data.pc := pc;
					GfxRegions.Enumerate(pc.clipReg, SHORT(llx), SHORT(lly), SHORT(urx), SHORT(ury), Color, data)
				END
			ELSE
				pc.pat.map.fmt.col := pc.col;
				data.dx := SHORT(ENTIER(pc.orgX + pc.pat.px + 0.5));
				data.dy := SHORT(ENTIER(pc.orgY + pc.pat.py + 0.5));
				data.map := pc.pat.map; data.pc := pc;
				GfxRegions.Enumerate(pc.clipReg, SHORT(llx), SHORT(lly), SHORT(urx), SHORT(ury), Tile, data)
			END
		END
	END Rect;
	
	PROCEDURE SetColPat (rc: GfxRaster.Context; col: Gfx.Color; pat: Gfx.Pattern);
		VAR pc: Context;
	BEGIN
		pc := rc(Context);
		pc.col := col; pc.pat := pat
	END SetColPat;
	
	
	(*--- Methods ---*)
	
	PROCEDURE ResetCTM (ctxt: Gfx.Context);
		VAR pc: Context;
	BEGIN
		pc := ctxt(Context);
		GfxMatrix.Translate(GfxMatrix.Identity, pc.orgX, pc.orgY, pc.ctm);
		GfxMatrix.Scale(pc.ctm, pc.scale, pc.scale, pc.ctm)
	END ResetCTM;
	
	PROCEDURE ResetClip (ctxt: Gfx.Context);
		VAR pc: Context;
	BEGIN
		pc := ctxt(Context);
		GfxRaster.ResetClip(pc);
		GfxRegions.Copy(pc.defClip, pc.clipReg)
	END ResetClip;
	
	PROCEDURE Show (ctxt: Gfx.Context; x, y: REAL; VAR str: ARRAY OF CHAR);
		VAR
			mat, m: GfxMatrix.Matrix; font: GfxFonts.Font; pc: Context; u, v, du, dv: REAL; metric: Fonts.Font;
			i, aw, dx, bx, by, w, h, px, py: INTEGER; pat: LONGINT;
	BEGIN
		GfxMatrix.Concat(ctxt.font.mat, ctxt.ctm, mat);
		GfxMatrix.Scale(mat, Printer.Unit/Display.Unit, Printer.Unit/Display.Unit, m);	(* check for screen font *)
		font := GfxFonts.Open(ctxt.font.name, ctxt.font.ptsize, m);
		IF (font.rfont # NIL) & (ctxt.mode * {Gfx.Record..Gfx.EvenOdd} = {Gfx.Fill}) & (ctxt.fillPat = NIL) THEN
			pc := ctxt(Context);
			GfxMatrix.Apply(pc.ctm, x, y, u, v);
			metric := Printer.GetMetric(font.rfont);
			i := 0; aw := 0;
			WHILE str[i] # 0X DO
				Fonts.GetChar(metric, str[i], dx, bx, by, w, h, pat);
				INC(aw, dx); INC(i)
			END;
			px := SHORT(ENTIER(u)); py := SHORT(ENTIER(v));
			IF GfxRegions.RectInside(px, py + metric.minY, px + aw, py + metric.maxY, pc.clipReg) THEN
				UseColor(pc, pc.fillCol);
				Printer.String(px, py, str, font.rfont);
				font := GfxFonts.Open(pc.font.name, pc.font.ptsize, mat);	(* use same metrics as GfxRaster.Show *)
				GfxFonts.GetStringWidth(font, str, du, dv);
				GfxMatrix.Solve(pc.ctm, u + du, v + dv, pc.cpx, pc.cpy)
			ELSE
				GfxRaster.Show(ctxt, x, y, str)
			END
		ELSE
			GfxRaster.Show(ctxt, x, y, str)
		END
	END Show;
	
	PROCEDURE Erase (ctxt: Gfx.Context);
		VAR pc: Context; col: Gfx.Color; pat: Gfx.Pattern; data: RegData;
	BEGIN
		pc := ctxt(Context);
		col := pc.col; pat := pc.pat; pc.col := Gfx.White; pc.pat := NIL;
		data.pc := pc;
		GfxRegions.Enumerate(pc.defClip, pc.defClip.llx, pc.defClip.lly, pc.defClip.urx, pc.defClip.ury, Color, data);
		pc.col := col; pc.pat := pat
	END Erase;
	
	PROCEDURE Image (ctxt: Gfx.Context; x, y: REAL; map: GfxMaps.Map; VAR filter: GfxMaps.Filter);
		VAR
			pc: Context; m: GfxMatrix.Matrix; dx, dy, x0, y0, x1, y1, j, i: INTEGER; llx, lly, urx, ury: REAL; tmp: GfxMaps.Map;
			blend: GfxMaps.BlendProc; col: GfxMaps.Color; spix, dpix: GfxMaps.Pixel; data: RegData;
	BEGIN
		pc := ctxt(Context); tmp := NIL;
		GfxMatrix.Translate(pc.ctm, x, y, m);
		dx := SHORT(ENTIER(m[2, 0])); m[2, 0] := m[2, 0] - dx;
		dy := SHORT(ENTIER(m[2, 1])); m[2, 1] := m[2, 1] - dy;
		IF (filter.hshift # GfxMaps.NoFilter.hshift) & (0.1 < m[2, 0]) & (m[2, 0] < 0.9) OR
			(filter.vshift # GfxMaps.NoFilter.vshift) & (0.1 < m[2, 1]) & (m[2, 1] < 0.9) OR
			GfxMatrix.Scaled(m) OR
			GfxMatrix.Rotated(m)
		THEN	(* transform to intermediate map *)
			GfxMatrix.ApplyToRect(m, 0, 0, map.width, map.height, llx, lly, urx, ury);
			x0 := SHORT(ENTIER(llx)); y0 := SHORT(ENTIER(lly));
			x1 := -SHORT(ENTIER(-urx)); y1 := -SHORT(ENTIER(-ury));
			GfxRegions.ClipRect(x0, y0, x1, y1, pc.clipReg.llx - dx, pc.clipReg.lly - dy, pc.clipReg.urx - dx, pc.clipReg.ury - dy);
			NEW(tmp); GfxMaps.Create(tmp, x1 - x0, y1 - y0, GfxMaps.BGRA32);
			
			m[2, 0] := m[2, 0] - x0; m[2, 1] := m[2, 1] - y0;
			blend := filter.blend; filter.blend := GfxMaps.SrcCopyProc;
			col := map.fmt.col; map.fmt.col := pc.fillCol;
			GfxMaps.Transform(map, tmp, m, filter);
			filter.blend := blend; map.fmt.col := col;
			map := tmp; INC(dx, x0); INC(dy, y0)
		END;
		
		IF blend # GfxMaps.SrcCopy.blend THEN	(* blend with background color *)
			IF tmp = NIL THEN	(* need intermediate map to blend *)
				NEW(tmp); GfxMaps.Create(tmp, map.width, map.height, GfxMaps.BGRA32);
				col := map.fmt.col; map.fmt.col := pc.fillCol;
				GfxMaps.Copy(map, tmp, 0, 0, map.width, map.height, 0, 0, GfxMaps.SrcCopy);
				map.fmt.col := col;
				map := tmp
			END;
			dpix[R] := 0FFX; dpix[G] := 0FFX; dpix[B] := 0FFX; dpix[A] := 0FFX;
			j := 0;
			WHILE j < map.height DO
				i := 0;
				WHILE i < map.width DO
					GfxMaps.Get(map, i, j, spix, GfxMaps.SrcCopy);
					IF spix[A] # 0X THEN	(* ignore pixels with zero alpha (not part of transformed image) *)
						filter.blend(filter, spix, dpix, spix);
						GfxMaps.Put(map, i, j, spix, GfxMaps.SrcCopy)
					END;
					INC(i)
				END;
				INC(j)
			END
		END;
		
		(* display visible parts *)
		col := map.fmt.col; map.fmt.col := pc.fillCol;
		data.pc := pc; data.map := map; data.dx := dx; data.dy := dy;
		GfxRegions.Enumerate(pc.clipReg, dx, dy, dx + map.width, dy + map.height, CopyImage, data);
		map.fmt.col := col
	END Image;
	
	PROCEDURE NewPattern (ctxt: Gfx.Context; map: GfxMaps.Map; px, py: REAL): Gfx.Pattern;
		VAR scale: REAL; pat: Gfx.Pattern; w, h: INTEGER;
	BEGIN
		scale := 10000/Printer.Unit;
		NEW(pat); pat.px := scale * px; pat.py := scale * py;
		w := -SHORT(ENTIER(-scale * map.width)); h := -SHORT(ENTIER(-scale * map.height));
		NEW(pat.map); GfxMaps.Create(pat.map, w, h, map.fmt);
		GfxMaps.Scale(map, pat.map, scale, scale, 0, 0, GfxMaps.LinearFilter);
		RETURN pat
	END NewPattern;
	
	PROCEDURE InitMethods;
		VAR do: Gfx.Methods;
	BEGIN
		NEW(do); Methods := do;
		do.reset := Gfx.DefResetContext;
		do.resetCTM := ResetCTM; do.setCTM := Gfx.DefSetCTM; do.translate := Gfx.DefTranslate;
		do.scale := Gfx.DefScale; do.rotate := Gfx.DefRotate; do.concat := Gfx.DefConcat;
		do.resetClip := ResetClip; do.getClipRect := GfxRaster.GetClipRect;
		do.saveClip := GfxRaster.SaveClip; do.restoreClip := GfxRaster.RestoreClip;
		do.setStrokeColor := Gfx.DefSetStrokeColor; do.setStrokePattern := Gfx.DefSetStrokePattern;
		do.setFillColor := Gfx.DefSetFillColor; do.setFillPattern := Gfx.DefSetFillPattern;
		do.setLineWidth := Gfx.DefSetLineWidth; do.setDashPattern := Gfx.DefSetDashPattern;
		do.setCapStyle := Gfx.DefSetCapStyle; do.setJoinStyle := Gfx.DefSetJoinStyle;
		do.setStyleLimit := Gfx.DefSetStyleLimit;
		do.setPoint := Gfx.DefSetPoint; do.setFlatness := Gfx.DefSetFlatness;
		do.setFont := Gfx.DefSetFont; do.getWidth := Gfx.DefGetStringWidth;
		do.begin := GfxRaster.Begin; do.end := GfxRaster.End;
		do.enter := GfxRaster.Enter; do.exit := GfxRaster.Exit;
		do.line := GfxRaster.Line; do.arc := GfxRaster.Arc; do.bezier := GfxRaster.Bezier;
		do.show := Show;
		do.flatten := Gfx.DefFlatten; do.outline := Gfx.DefOutline;
		do.render := GfxRaster.Render;
		do.erase := Erase; do.rect := GfxRaster.Rect; do.ellipse := GfxRaster.Ellipse;
		do.image := Image; do.newPattern := NewPattern;
	END InitMethods;
	
	
	(*--- Exported Interface ---*)
	
	(** set default clip region to rectangle **)
	PROCEDURE SetClipRect* (pc: Context; llx, lly, urx, ury: INTEGER);
	BEGIN
		GfxRegions.SetToRect(pc.defClip, llx, lly, urx, ury)
	END SetClipRect;
	
	(** copy given region to default clip region **)
	PROCEDURE SetClipRegion* (pc: Context; reg: GfxRegions.Region);
	BEGIN
		GfxRegions.Copy(reg, pc.defClip)
	END SetClipRegion;
	
	(** set default coordinate origin and scale factor **)
	PROCEDURE SetCoordinates* (pc: Context; x, y, scale: REAL);
	BEGIN
		pc.orgX := x; pc.orgY := y; pc.scale := scale
	END SetCoordinates;
	
	(** initialize context to printable range **)
	PROCEDURE Init* (pc: Context);
	BEGIN
		GfxRaster.InitContext(pc);
		pc.do := Methods; pc.dot := Dot; pc.rect := Rect; pc.setColPat := SetColPat;
		pc.prcol.r := -1; pc.prcol.g := -1; pc.prcol.b := -1;
		NEW(pc.defClip); GfxRegions.Init(pc.defClip, GfxRegions.Winding);
		SetClipRect(pc, Printer.FrameX, Printer.FrameY, Printer.FrameX + Printer.FrameW, Printer.FrameY + Printer.FrameH);
		SetCoordinates(pc, Printer.FrameX, Printer.FrameY, 10000/Printer.Unit);
		Gfx.DefResetContext(pc)
	END Init;
	

BEGIN
	InitMethods
END GfxPrinter.
