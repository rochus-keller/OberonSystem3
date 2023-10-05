MODULE GfxBuffer;	(** eos   **)

	(**
		Raster contexts rendering into background buffers
	**)
	
	(*
		10.12.98 - first version; derived from GfxDev
	*)
	
	
	IMPORT
		GfxMatrix, GfxMaps, GfxRegions, Gfx, GfxRaster;
		
	
	TYPE
		Context* = POINTER TO ContextDesc;
		ContextDesc* = RECORD (GfxRaster.ContextDesc)
			orgX*, orgY*: REAL;	(** origin of default coordinate system **)
			scale*: REAL;	(** default scale factor **)
			bgCol*: Gfx.Color;	(** background color for erasing **)
			map*: GfxMaps.Map;	(** target buffer **)
			pix: GfxMaps.Pixel;
		END;
		
		RegData = RECORD (GfxRegions.EnumData)
			dx, dy: INTEGER;
			bc: Context;
		END;
		
	
	VAR
		Methods: Gfx.Methods;
		
	
	(*--- Rendering ---*)
	
	PROCEDURE Color (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
		VAR bc: Context;
	BEGIN
		bc := data(RegData).bc;
		GfxMaps.Fill(bc.map, llx, lly, urx, ury, bc.pix, GfxMaps.SrcCopy)
	END Color;
	
	PROCEDURE Tile (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
		VAR bc: Context;
	BEGIN
		WITH data: RegData DO
			bc := data.bc;
			GfxMaps.FillPattern(bc.map, bc.pat.map, llx, lly, urx, ury, data.dx, data.dy, GfxMaps.SrcAlpha)
		END
	END Tile;
	
	PROCEDURE Dot (rc: GfxRaster.Context; x, y: LONGINT);
		VAR bc: Context; px, py: INTEGER;
	BEGIN
		IF (rc.clipState = GfxRaster.In) OR
			(rc.clipState = GfxRaster.InOut) & GfxRegions.RectInside(SHORT(x), SHORT(y), SHORT(x+1), SHORT(y+1), rc.clipReg)
		THEN
			bc := rc(Context);
			IF bc.pat = NIL THEN
				GfxMaps.Put(bc.map, SHORT(x), SHORT(y), bc.pix, GfxMaps.SrcCopy)
			ELSE
				bc.pat.map.fmt.col := bc.col;
				px := SHORT(x - ENTIER(bc.orgX + bc.pat.px + 0.5)) MOD bc.pat.map.width;
				py := SHORT(y - ENTIER(bc.orgY + bc.pat.py + 0.5)) MOD bc.pat.map.height;
				GfxMaps.Copy(bc.pat.map, bc.map, px, py, px+1, py+1, SHORT(x), SHORT(y), GfxMaps.SrcAlpha)
			END
		END
	END Dot;
	
	PROCEDURE Rect (rc: GfxRaster.Context; llx, lly, urx, ury: LONGINT);
		VAR bc: Context; data: RegData;
	BEGIN
		IF rc.clipState # GfxRaster.Out THEN
			bc := rc(Context);
			IF bc.pat = NIL THEN
				IF rc.clipState = GfxRaster.In THEN
					GfxMaps.Fill(bc.map, SHORT(llx), SHORT(lly), SHORT(urx), SHORT(ury), bc.pix, GfxMaps.SrcCopy)
				ELSE
					data.bc := bc;
					GfxRegions.Enumerate(bc.clipReg, SHORT(llx), SHORT(lly), SHORT(urx), SHORT(ury), Color, data)
				END
			ELSE
				bc.pat.map.fmt.col := bc.col;
				data.bc := bc;
				data.dx := SHORT(ENTIER(bc.orgX + bc.pat.px + 0.5));
				data.dy := SHORT(ENTIER(bc.orgY + bc.pat.py + 0.5));
				GfxRegions.Enumerate(bc.clipReg, SHORT(llx), SHORT(lly), SHORT(urx), SHORT(ury), Tile, data)
			END
		END
	END Rect;
	
	PROCEDURE SetColPat (rc: GfxRaster.Context; col: Gfx.Color; pat: Gfx.Pattern);
		VAR bc: Context;
	BEGIN
		bc := rc(Context);
		bc.col := col; bc.pat := pat;
		GfxMaps.ColorToPixel(col, bc.pix)
	END SetColPat;
	
	
	(*--- Methods ---*)
	
	PROCEDURE ResetCTM (ctxt: Gfx.Context);
		VAR bc: Context;
	BEGIN
		bc := ctxt(Context);
		GfxMatrix.Translate(GfxMatrix.Identity, bc.orgX, bc.orgY, bc.ctm);
		GfxMatrix.Scale(bc.ctm, bc.scale, bc.scale, bc.ctm)
	END ResetCTM;
	
	PROCEDURE ResetClip (ctxt: Gfx.Context);
		VAR bc: Context;
	BEGIN
		bc := ctxt(Context);
		GfxRaster.ResetClip(bc);
		GfxRegions.SetToRect(bc.clipReg, 0, 0, bc.map.width, bc.map.height)
	END ResetClip;
	
	PROCEDURE Erase (ctxt: Gfx.Context);
		VAR bc: Context; pix: GfxMaps.Pixel;
	BEGIN
		bc := ctxt(Context);
		GfxMaps.ColorToPixel(bc.bgCol, pix);
		GfxMaps.Fill(bc.map, 0, 0, bc.map.width, bc.map.height, pix, GfxMaps.SrcCopy)
	END Erase;
	
	PROCEDURE Image (ctxt: Gfx.Context; x, y: REAL; map: GfxMaps.Map; VAR filter: GfxMaps.Filter);
		VAR bc: Context; m: GfxMatrix.Matrix; dx, dy, llx, lly, urx, ury: INTEGER; col: GfxMaps.Color;
	BEGIN
		bc := ctxt(Context);
		GfxMatrix.Translate(bc.ctm, x, y, m);
		dx := SHORT(ENTIER(m[2, 0] + 0.5));
		dy := SHORT(ENTIER(m[2, 1] + 0.5));
		col := map.fmt.col; map.fmt.col := bc.fillCol;
		IF (filter.hshift # GfxMaps.NoFilter.hshift) & (dx + 0.1 < m[2, 0]) & (m[2, 0] < dx + 0.9) OR
			(filter.vshift # GfxMaps.NoFilter.vshift) & (dy + 0.1 < m[2, 1]) & (m[2, 1] < dy + 0.9) OR
			GfxMatrix.Scaled(m) OR
			GfxMatrix.Rotated(m)
		THEN
			GfxMaps.Transform(map, bc.map, m, filter)
		ELSE
			llx := 0; lly := 0; urx := map.width; ury := map.height;
			IF dx + urx > bc.map.width THEN urx := bc.map.width - dx END;
			IF dy + ury > bc.map.height THEN ury := bc.map.height - dy END;
			IF dx < 0 THEN llx := -dx; dx := 0 END;
			IF dy < 0 THEN lly := -dy; dy := 0 END;
			IF (llx < urx) & (lly < ury) THEN	
				GfxMaps.Copy(map, bc.map, llx, lly, urx, ury, dx, dy, filter)
			END
		END;
		map.fmt.col := col
	END Image;
	
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
		do.show := GfxRaster.Show;
		do.flatten := Gfx.DefFlatten; do.outline := Gfx.DefOutline;
		do.render := GfxRaster.Render;
		do.erase := Erase; do.rect := GfxRaster.Rect; do.ellipse := GfxRaster.Ellipse;
		do.image := Image; do.newPattern := Gfx.DefNewPattern;
	END InitMethods;
	
	
	(*--- Exported Interface ---*)
	
	(** set default coordinate origin and scale factor **)
	PROCEDURE SetCoordinates* (bc: Context; x, y, scale: REAL);
	BEGIN
		bc.orgX := x; bc.orgY := y; bc.scale := scale
	END SetCoordinates;
	
	(** set background color **)
	PROCEDURE SetBGColor* (bc: Context; col: Gfx.Color);
	BEGIN
		bc.bgCol := col
	END SetBGColor;
	
	(** initialize buffered context **)
	PROCEDURE Init* (bc: Context; map: GfxMaps.Map);
	BEGIN
		GfxRaster.InitContext(bc);
		bc.map := map; bc.do := Methods; bc.dot := Dot; bc.rect := Rect; bc.setColPat := SetColPat;
		SetCoordinates(bc, 0, 0, 1);
		SetBGColor(bc, Gfx.White);
		Gfx.DefResetContext(bc)
	END Init;
	

BEGIN
	InitMethods
END GfxBuffer.
