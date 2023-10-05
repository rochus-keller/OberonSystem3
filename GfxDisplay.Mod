MODULE GfxDisplay;	(** eos   **)

	(**
		Raster contexts on Oberon display
	**)
	
	(*
		10.12.98 - first release; derived from former GfxDev
		16.4.99 - bugfix in CopyIndex and BlendIndex: used wrong offset into bitmap
		19.4.99 - uses Display transfer and truecolor functionality
	*)
	
	IMPORT
		SYSTEM, Display, Fonts, GfxMatrix, GfxMaps, GfxRegions, GfxFonts, Gfx, GfxRaster;
		
	
	CONST
		R = GfxMaps.R; G = GfxMaps.G; B = GfxMaps.B; A = GfxMaps.A;
		MaxRun = 256;
		
	
	TYPE
		Context* = POINTER TO ContextDesc;
		ContextDesc* = RECORD (GfxRaster.ContextDesc)
			orgX*, orgY*: REAL;	(** origin of default coordinate system **)
			scale*: REAL;	(** scale factor of default coordinate system **)
			defClip*: GfxRegions.Region;	(** default clipping region **)
			bg*: Gfx.Color;	(** background color for erasing **)
			bgCol: Display.Color;	(* display color corresponding to background color *)
			bgPix: GfxMaps.Pixel;	(* pixel value corresponding to background color *)
			dcol: Display.Color;	(* current display color *)
		END;
		
		RegData = RECORD (GfxRegions.EnumData)
			dc: Context;
			dx, dy: INTEGER;
			pat: Display.Pattern;
			map: GfxMaps.Map;
			col: Display.Color
		END;
		
		BlendDotProc = PROCEDURE (dc: Context; map: GfxMaps.Map; mx, my: INTEGER; x, y: LONGINT);
		DrawRunProc = PROCEDURE (VAR buf: ARRAY OF CHAR; len, x, y: LONGINT);
		CopyRunProc = PROCEDURE (map: GfxMaps.Map; mx, my, len: INTEGER; x, y: LONGINT);
		BlendRunProc = PROCEDURE (dc: Context; map: GfxMaps.Map; mx, my, len: INTEGER; x, y: LONGINT);
		WarpProc = PROCEDURE (dc: Context; map: GfxMaps.Map; dx, dy, x0, y0, x1, y1: INTEGER; VAR m: GfxMatrix.Matrix; VAR f: GfxMaps.Filter);
		CopyMapProc = PROCEDURE (dc: Context; map: GfxMaps.Map; dx, dy: INTEGER; VAR filter: GfxMaps.Filter);
		
	
	VAR
		TrueColor, TransferBlock: BOOLEAN;	(* set if corresponding Display features are available *)
		Methods: Gfx.Methods;
		BlendDot: BlendDotProc;	(* copies dot from pattern to display *)
		DrawRun: DrawRunProc;	(* draws buffer run *)
		CopyRun: CopyRunProc;	(* copies run from map to display *)
		BlendRun: BlendRunProc;	(* blends buffer run with display *)
		TileRect: GfxRegions.Enumerator;	(* fills rectangular area with pattern *)
		Warp: WarpProc;	(* applies matrix to map and stores result in buffer *)
		DrawMapRect, BlendMapRect: GfxRegions.Enumerator;	(* draws/blends map rectangle *)
		CopyMap: CopyMapProc;	(* copies visible parts of map to display *)
		
		(* used if TransferBlock is available: *)
		BufFmt: GfxMaps.Format;	(* Gfx format of display *)
		BufMap: GfxMaps.Map;	(* map in display pixel format *)
		
	
	(*--- Blend Dot Into Display ---*)
	
	PROCEDURE BlendDotBlk (dc: Context; map: GfxMaps.Map; mx, my: INTEGER; x, y: LONGINT);
		VAR buf: ARRAY 4 OF CHAR;
	BEGIN
		IF GfxMaps.Alpha IN map.fmt.components THEN	(* get original color from display *)
			Display.TransferBlock(buf, 0, 0, x, y, 1, 1, Display.get);
			map.fmt.col := dc.col	(* use current raster context color *)
		END;
		GfxMaps.GetPixels(map, mx, my, 1, BufFmt, buf, GfxMaps.SrcAlpha);
		Display.TransferBlock(buf, 0, 0, x, y, 1, 1, Display.set)
	END BlendDotBlk;
	
	PROCEDURE BlendDotRGB (dc: Context; map: GfxMaps.Map; mx, my: INTEGER; x, y: LONGINT);
		VAR pix: GfxMaps.Pixel;
	BEGIN
		IF GfxMaps.Alpha IN map.fmt.components THEN
			pix := dc.bgPix; map.fmt.col := dc.col
		END;
		GfxMaps.GetPixels(map, mx, my, 1, GfxMaps.PixelFormat, pix, GfxMaps.SrcAlpha);
		Display.Dot(Display.RGB(ORD(pix[R]), ORD(pix[G]), ORD(pix[B])), x, y, Display.replace)
	END BlendDotRGB;
	
	PROCEDURE BlendDotIdx (dc: Context; map: GfxMaps.Map; mx, my: INTEGER; x, y: LONGINT);
		VAR buf: ARRAY 1 OF CHAR;
	BEGIN
		IF GfxMaps.Alpha IN map.fmt.components THEN
			buf[0] := CHR(dc.bgCol)
		END;
		GfxMaps.GetPixels(map, mx, my, 1, GfxMaps.I8, buf, GfxMaps.SrcAlpha);
		Display.Dot(ORD(buf[0]), x, y, Display.replace)
	END BlendDotIdx;
	
	PROCEDURE Dot (rc: GfxRaster.Context; x, y: LONGINT);
		VAR dc: Context; map: GfxMaps.Map; mw, mh, mx, my: INTEGER;
	BEGIN
		IF (rc.clipState = GfxRaster.In) OR
			(rc.clipState = GfxRaster.InOut) & GfxRegions.RectInside(SHORT(x), SHORT(y), SHORT(x+1), SHORT(y+1), rc.clipReg)
		THEN
			IF rc.pat = NIL THEN
				Display.Dot(rc(Context).dcol, x, y, Display.replace)
			ELSE
				dc := rc(Context); map := dc.pat.map;
				mw := map.width; mh := map.height;
				mx := SHORT(x - ENTIER(dc.orgX + dc.pat.px + 0.5)) MOD mw;
				my := SHORT(y - ENTIER(dc.orgY + dc.pat.py + 0.5)) MOD mh;
				BlendDot(dc, map, mx, my, x, y)
			END
		END
	END Dot;
	
	
	(*--- Draw Run ---*)
	
	PROCEDURE DrawRunRGB (VAR buf: ARRAY OF CHAR; len, x, y: LONGINT);
		VAR i, l: LONGINT; r, g, b: CHAR;
	BEGIN
		i := 0;
		WHILE len > 0 DO
			r := buf[i + R]; g := buf[i + G]; b := buf[i + B]; INC(i, 3); l := 1;
			WHILE (l < len) & (buf[i + R] = r) & (buf[i + G] = g) & (buf[i + B] = b) DO
				INC(i, 3); INC(l)
			END;
			Display.ReplConst(Display.RGB(ORD(r), ORD(g), ORD(b)), x, y, l, 1, Display.replace);
			INC(x, l); DEC(len, l)
		END
	END DrawRunRGB;
	
	PROCEDURE DrawRunIdx (VAR buf: ARRAY OF CHAR; len, x, y: LONGINT);
		VAR i, l: LONGINT; idx: CHAR;
	BEGIN
		i := 0;
		WHILE len > 0 DO
			idx := buf[i]; INC(i); l := 1;
			WHILE (l < len) & (buf[i] = idx) DO INC(i); INC(l) END;
			Display.ReplConst(ORD(idx), x, y, l, 1, Display.replace);
			INC(x, l); DEC(len, l)
		END
	END DrawRunIdx;
	
	
	(*--- Copy Map Run ---*)
	
	PROCEDURE CopyRunRGB (map: GfxMaps.Map; mx, my, len: INTEGER; x, y: LONGINT);
		VAR buf: ARRAY 3*MaxRun OF CHAR;
	BEGIN
		GfxMaps.GetPixels(map, mx, my, len, GfxMaps.BGR24, buf, GfxMaps.SrcCopy);
		DrawRunRGB(buf, len, x, y)
	END CopyRunRGB;
	
	PROCEDURE CopyRunIdx (map: GfxMaps.Map; mx, my, len: INTEGER; x, y: LONGINT);
		VAR buf: ARRAY MaxRun OF CHAR;
	BEGIN
		GfxMaps.GetPixels(map, mx, my, len, GfxMaps.I8, buf, GfxMaps.SrcCopy);
		DrawRunIdx(buf, len, x, y)
	END CopyRunIdx;
	
	
	(*--- Blend Map Run ---*)
	
	PROCEDURE BlendRunRGB (dc: Context; map: GfxMaps.Map; mx, my, len: INTEGER; x, y: LONGINT);
		VAR i, j, l: LONGINT; buf: ARRAY 3*MaxRun OF CHAR; alpha: ARRAY MaxRun OF CHAR; a, r, g, b: CHAR;
	BEGIN
		i := 0; j := 0;
		WHILE i < len DO
			buf[j + B] := dc.bgPix[B]; buf[j + G] := dc.bgPix[G]; buf[j + R] := dc.bgPix[R];
			INC(i); INC(j, 3)
		END;
		map.fmt.col := dc.col;
		GfxMaps.GetPixels(map, mx, my, len, GfxMaps.BGR24, buf, GfxMaps.SrcAlpha);
		GfxMaps.GetPixels(map, mx, my, len, GfxMaps.A8, alpha, GfxMaps.SrcCopy);
		i := 0; j := 0;
		WHILE len > 0 DO
			a := alpha[i]; INC(i);
			IF a = 0X THEN
				INC(j, 3); INC(x); DEC(len)
			ELSE
				r := buf[j + R]; g := buf[j + G]; b := buf[j + B]; INC(j, 3); l := 1;
				WHILE (l < len) & (alpha[i] # 0X) & (buf[j + R] = r) & (buf[j + G] = g) & (buf[j + B] = b) DO
					INC(i); INC(j, 3); INC(l)
				END;
				Display.ReplConst(Display.RGB(ORD(r), ORD(g), ORD(b)), x, y, l, 1, Display.replace);
				INC(x, l); DEC(len, SHORT(l))
			END
		END
	END BlendRunRGB;
	
	PROCEDURE BlendRunIdx (dc: Context; map: GfxMaps.Map; mx, my, len: INTEGER; x, y: LONGINT);
		VAR i, l: LONGINT; buf, alpha: ARRAY MaxRun OF CHAR; idx: CHAR;
	BEGIN
		i := 0; WHILE i < len DO buf[i] := CHR(dc.bgCol); INC(i) END;
		map.fmt.col := dc.col;
		GfxMaps.GetPixels(map, mx, my, len, GfxMaps.I8, buf, GfxMaps.SrcAlpha);
		GfxMaps.GetPixels(map, mx, my, len, GfxMaps.A8, alpha, GfxMaps.SrcCopy);
		i := 0;
		WHILE len > 0 DO
			IF alpha[i] = 0X THEN
				INC(i); INC(x); DEC(len)
			ELSE
				idx := buf[i]; INC(i); l := 1;
				WHILE (l < len) & (alpha[i] # 0X) & (buf[i] = idx) DO INC(i); INC(l) END;
				Display.ReplConst(ORD(idx), x, y, l, 1, Display.replace);
				INC(x, l); DEC(len, SHORT(l))
			END
		END
	END BlendRunIdx;
	
	
	(*--- Draw Rectangle ---*)
	
	PROCEDURE DrawRect (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
	BEGIN
		Display.ReplConst(data(RegData).col, llx, lly, urx - llx, ury - lly, Display.replace)
	END DrawRect;
	
	PROCEDURE TileRectBlk (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
		VAR w, h: INTEGER;
	BEGIN
		WITH data: RegData DO
			w := urx - llx; h := ury - lly;
			GfxMaps.Create(BufMap, w, h, BufFmt);
			IF GfxMaps.Alpha IN data.map.fmt.components THEN
				Display.TransferBlock(BufMap.mem^, 0, BufMap.bpr, llx, lly, w, h, Display.get)
			END;
			GfxMaps.FillPattern(BufMap, data.map, 0, 0, w, h, data.dx - llx, data.dy - lly, GfxMaps.SrcAlpha);
			Display.TransferBlock(BufMap.mem^, 0, BufMap.bpr, llx, lly, w, h, Display.set)
		END
	END TileRectBlk;
	
	PROCEDURE TileRectPix (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
		VAR mw, mh, y, my, x, mx, len: INTEGER;
	BEGIN
		WITH data: RegData DO
			mw := data.map.width; mh := data.map.height;
			y := lly; my := (lly - data.dy) MOD mh;
			WHILE y < ury DO
				x := llx; mx := (llx - data.dx) MOD mw;
				WHILE x < urx DO
					len := urx - x;
					IF mx + len > mw THEN len := mw - mx END;
					IF len > MaxRun THEN len := MaxRun END;
					IF GfxMaps.Alpha IN data.map.fmt.components THEN
						BlendRun(data.dc, data.map, mx, my, len, x, y)
					ELSE
						CopyRun(data.map, mx, my, len, x, y)
					END;
					INC(x, len); INC(mx, len);
					IF mx = mw THEN mx := 0 END
				END;
				INC(y); INC(my);
				IF my = mh THEN my := 0 END
			END
		END
	END TileRectPix;
	
	PROCEDURE Rect (rc: GfxRaster.Context; llx, lly, urx, ury: LONGINT);
		VAR data: RegData; dc: Context;
	BEGIN
		IF rc.clipState # GfxRaster.Out THEN
			IF rc.pat = NIL THEN
				IF rc.clipState = GfxRaster.In THEN
					Display.ReplConst(rc(Context).dcol, llx, lly, urx - llx, ury - lly, Display.replace)
				ELSE
					data.col := rc(Context).dcol;
					GfxRegions.Enumerate(rc.clipReg, SHORT(llx), SHORT(lly), SHORT(urx), SHORT(ury), DrawRect, data)
				END
			ELSE
				dc := rc(Context);
				dc.pat.map.fmt.col := dc.col;
				data.dx := SHORT(ENTIER(dc.orgX + dc.pat.px + 0.5));
				data.dy := SHORT(ENTIER(dc.orgY + dc.pat.py + 0.5));
				data.dc := dc; data.map := dc.pat.map;
				GfxRegions.Enumerate(dc.clipReg, SHORT(llx), SHORT(lly), SHORT(urx), SHORT(ury), TileRect, data)
			END
		END
	END Rect;
	
	
	(*--- Set Color/Pattern for Raster Context ---*)
	
	PROCEDURE SetColPatRGB (rc: GfxRaster.Context; col: Gfx.Color; pat: Gfx.Pattern);
	BEGIN
		rc.col := col; rc.pat := pat; rc(Context).dcol := Display.RGB(col.r, col.g, col.b)
	END SetColPatRGB;
	
	PROCEDURE SetColPatIdx (rc: GfxRaster.Context; col: Gfx.Color; pat: Gfx.Pattern);
	BEGIN
		rc.col := col; rc.pat := pat;
		rc(Context).dcol := GfxMaps.BestIndex(GfxMaps.DisplayPal, col.r, col.g, col.b)
	END SetColPatIdx;
	
	
	(*--- Draw String ---*)
	
	PROCEDURE CopyPattern (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
	BEGIN
		WITH data: RegData DO
			Display.SetClip(llx, lly, urx - llx, ury - lly);
			Display.CopyPattern(data.col, data.pat, data.dx, data.dy, Display.paint);
			Display.ResetClip
		END
	END CopyPattern;
	
	PROCEDURE Show (ctxt: Gfx.Context; x, y: REAL; VAR str: ARRAY OF CHAR);
		VAR
			mat: GfxMatrix.Matrix; font: GfxFonts.Font; dc: Context; u, v: REAL; px, py, i, aw, dx, bx, by, w, h: INTEGER;
			pat: Display.Pattern; data: RegData;
	BEGIN
		GfxMatrix.Concat(ctxt.font.mat, ctxt.ctm, mat);
		font := GfxFonts.Open(ctxt.font.name, ctxt.font.ptsize, mat);
		IF (font.rfont # NIL) & (ctxt.mode * {Gfx.Record..Gfx.EvenOdd} = {Gfx.Fill}) & (ctxt.fillPat = NIL) THEN
			dc := ctxt(Context);
			dc.setColPat(dc, dc.fillCol, NIL);
			GfxMatrix.Apply(dc.ctm, x, y, u, v);
			px := SHORT(ENTIER(u + 0.5)); py := SHORT(ENTIER(v + 0.5));
			i := 0; aw := 0;
			WHILE str[i] # 0X DO
				Fonts.GetChar(font.rfont, str[i], dx, bx, by, w, h, pat);
				INC(aw, dx); INC(i)
			END;
			IF GfxRegions.RectInside(px, py + font.rfont.minY, px + aw, py + font.rfont.maxY, dc.clipReg) THEN
				i := 0;
				WHILE str[i] # 0X DO
					Fonts.GetChar(font.rfont, str[i], dx, bx, by, w, h, pat);
					IF w * h # 0 THEN
						Display.CopyPattern(dc.dcol, pat, px + bx, py + by, Display.paint)
					END;
					INC(px, dx); INC(i)
				END
			ELSE
				data.col := dc.dcol; i := 0;
				WHILE str[i] # 0X DO
					Fonts.GetChar(font.rfont, str[i], dx, bx, by, w, h, pat);
					IF (w * h # 0) & GfxRegions.RectOverlaps(px + bx, py + by, px + bx + w, py + by + h, dc.clipReg) THEN
						data.dx := px + bx; data.dy := py + by; data.pat := pat;
						GfxRegions.Enumerate(dc.clipReg, data.dx, data.dy, data.dx + w, data.dy + h, CopyPattern, data)
					END;
					INC(px, dx); INC(i)
				END
			END;
			dc.cpx := x + aw; dc.cpy := y	(* font coordinates are same as world coordinates *)
		ELSE
			GfxRaster.Show(ctxt, x, y, str)
		END
	END Show;
	
	
	(*--- Transform To Temporary Bitmap ---*)
	
	PROCEDURE WarpBlk (dc: Context; map: GfxMaps.Map; dx, dy, x0, y0, x1, y1: INTEGER; VAR m: GfxMatrix.Matrix; VAR f: GfxMaps.Filter);
		VAR col: GfxMaps.Color;
	BEGIN
		Display.TransferBlock(BufMap.mem^, 0, BufMap.bpr, dx + x0, dy + y0, x1 - x0, y1 - y0, Display.get);
		m[2, 0] := m[2, 0] - x0; m[2, 1] := m[2, 1] - y0;	(* make transform local to BufMap origin *)
		col := map.fmt.col; map.fmt.col := dc.fillCol;
		GfxMaps.Transform(map, BufMap, m, f);
		map.fmt.col := col
	END WarpBlk;
	
	PROCEDURE WarpPix (dc: Context; map: GfxMaps.Map; dx, dy, x0, y0, x1, y1: INTEGER; VAR m: GfxMatrix.Matrix; VAR f: GfxMaps.Filter);
		VAR blend: GfxMaps.BlendProc; col: GfxMaps.Color;
	BEGIN
		m[2, 0] := m[2, 0] - x0; m[2, 1] := m[2, 1] - y0;	(* make transform local to BufMap origin *)
		blend := f.blend; f.blend := GfxMaps.SrcCopyProc;	(* override filter blend operator *)
		col := map.fmt.col; map.fmt.col := dc.fillCol;
		GfxMaps.Transform(map, BufMap, m, f);
		f.blend := blend; map.fmt.col := col
	END WarpPix;
	
	
	(*--- Draw/Blend Map Rectangle ---*)
	
	PROCEDURE DrawMapRectBlk (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
		VAR off: LONGINT;
	BEGIN
		WITH data: RegData DO
			off := (lly - data.dy) * data.map.bpr + LONG(llx - data.dx) * (data.map.fmt.bpp DIV 8);
			Display.TransferBlock(data.map.mem^, off, data.map.bpr, llx, lly, urx - llx, ury - lly, Display.set)
		END
	END DrawMapRectBlk;
	
	PROCEDURE DrawMapRectPix (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
		VAR y, x, len: INTEGER;
	BEGIN
		WITH data: RegData DO
			y := lly;
			WHILE y < ury DO
				x := llx;
				WHILE x < urx DO
					len := MaxRun;
					IF x + MaxRun > urx THEN len := urx - x END;
					CopyRun(data.map, x - data.dx, y - data.dy, len, x, y);
					INC(x, len)
				END;
				INC(y)
			END
		END
	END DrawMapRectPix;
	
	PROCEDURE BlendMapRectPix (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
		VAR y, x, len: INTEGER;
	BEGIN
		WITH data: RegData DO
			y := lly;
			WHILE y < ury DO
				x := llx;
				WHILE x < urx DO
					len := MaxRun;
					IF x + MaxRun > urx THEN len := urx - x END;
					BlendRun(data.dc, data.map, x - data.dx, y - data.dy, len, x, y);
					INC(x, len)
				END;
				INC(y)
			END
		END
	END BlendMapRectPix;
	
	
	(*--- Copy Map To Display ---*)
	
	PROCEDURE CopyMapBlk (dc: Context; map: GfxMaps.Map; dx, dy: INTEGER; VAR filter: GfxMaps.Filter);
		VAR data: RegData; llx, lly, urx, ury: INTEGER; col: Gfx.Color;
	BEGIN
		IF (map.fmt.code = BufFmt.code) & (map.mem # NIL) &
			((filter.blend = GfxMaps.SrcCopy.blend) OR
			 (filter.blend = GfxMaps.SrcAlpha.blend) & ~(GfxMaps.Alpha IN map.fmt.components))
		THEN	(* copy directly from map *)
			data.map := map; data.dx := dx; data.dy := dy;
			GfxRegions.Enumerate(dc.clipReg, llx, lly, urx, ury, DrawMapRectBlk, data)
		ELSE	(* blend into temporary map first *)
			llx := dx; lly := dy; urx := llx + map.width; ury := lly + map.height;
			GfxRegions.ClipRect(llx, lly, urx, ury, dc.clipReg.llx, dc.clipReg.lly, dc.clipReg.urx, dc.clipReg.ury);
			IF ~GfxRegions.RectEmpty(llx, lly, urx, ury) THEN
				GfxMaps.Create(BufMap, urx - llx, ury - lly, BufFmt); col := map.fmt.col;
				IF GfxMaps.Alpha IN map.fmt.components THEN
					Display.TransferBlock(BufMap.mem^, 0, BufMap.bpr, llx, lly, urx - llx, ury - lly, Display.get);
					map.fmt.col := dc.fillCol
				END;
				GfxMaps.Copy(map, BufMap, llx - dx, lly - dy, urx - dx, ury - dy, 0, 0, filter);
				map.fmt.col := col;
				data.map := BufMap; data.dx := llx; data.dy := lly;
				GfxRegions.Enumerate(dc.clipReg, llx, lly, urx, ury, DrawMapRectBlk, data)
			END
		END
	END CopyMapBlk;
	
	PROCEDURE CopyMapPix (dc: Context; map: GfxMaps.Map; dx, dy: INTEGER; VAR filter: GfxMaps.Filter);
		VAR col: Gfx.Color; data: RegData; llx, lly, urx, ury: INTEGER; pix: GfxMaps.Pixel;
	BEGIN
		col := map.fmt.col; map.fmt.col := dc.fillCol;
		IF (filter.blend = GfxMaps.SrcCopy.blend) OR
			~(GfxMaps.Alpha IN map.fmt.components) & (filter.blend = GfxMaps.SrcAlpha.blend)
		THEN
			data.map := map; data.dx := dx; data.dy := dy;
			GfxRegions.Enumerate(dc.clipReg, dx, dy, dx + map.width, dy + map.height, DrawMapRectPix, data)
		ELSIF filter.blend = GfxMaps.SrcAlpha.blend THEN
			data.dc := dc; data.map := map; data.dx := dx; data.dy := dy;
			GfxRegions.Enumerate(dc.clipReg, dx, dy, dx + map.width, dy + map.height, BlendMapRectPix, data)
		ELSE
			llx := dx; lly := dy; urx := llx + map.width; ury := lly + map.height;
			GfxRegions.ClipRect(llx, lly, urx, ury, dc.clipReg.llx, dc.clipReg.lly, dc.clipReg.urx, dc.clipReg.ury);
			IF ~GfxRegions.RectEmpty(llx, lly, urx, ury) THEN
				GfxMaps.Create(BufMap, urx - llx, ury - lly, BufFmt);
				pix[R] := dc.bgPix[R]; pix[G] := dc.bgPix[G]; pix[B] := dc.bgPix[B]; pix[A] := 0X;
				GfxMaps.Fill(BufMap, 0, 0, urx - llx, ury - lly, pix, GfxMaps.SrcCopy);
				GfxMaps.Copy(map, BufMap, llx - dx, lly - dy, urx - dx, ury - dy, 0, 0, filter);
				data.map := BufMap; data.dx := llx; data.dy := lly;
				GfxRegions.Enumerate(dc.clipReg, llx, lly, urx, ury, BlendMapRectPix, data)
			END
		END;
		map.fmt.col := col
	END CopyMapPix;
	
	
	(*--- Draw Bitmap ---*)
	
	PROCEDURE Image (ctxt: Gfx.Context; x, y: REAL; map: GfxMaps.Map; VAR filter: GfxMaps.Filter);
		VAR dc: Context; m: GfxMatrix.Matrix; dx, dy, llx, lly, urx, ury: INTEGER; x0, y0, x1, y1: REAL; data: RegData;
	BEGIN
		dc := ctxt(Context);
		GfxMatrix.Translate(dc.ctm, x, y, m);
		dx := SHORT(ENTIER(m[2, 0])); m[2, 0] := m[2, 0] - dx;
		dy := SHORT(ENTIER(m[2, 1])); m[2, 1] := m[2, 1] - dy;
		IF (filter.hshift # GfxMaps.NoFilter.hshift) & (0.1 < m[2, 0]) & (m[2, 0] < 0.9) OR
			(filter.vshift # GfxMaps.NoFilter.vshift) & (0.1 < m[2, 1]) & (m[2, 1] < 0.9) OR
			GfxMatrix.Scaled(m) OR
			GfxMatrix.Rotated(m)
		THEN	(* transform into temporary image and copy from there *)
			GfxMatrix.ApplyToRect(m, 0, 0, map.width, map.height, x0, y0, x1, y1);
			llx := SHORT(ENTIER(x0)); lly := SHORT(ENTIER(y0));
			urx := -SHORT(ENTIER(-x1)); ury := -SHORT(ENTIER(-y1));
			GfxRegions.ClipRect(llx, lly, urx, ury, dc.clipReg.llx - dx, dc.clipReg.lly - dy, dc.clipReg.urx - dx, dc.clipReg.ury - dy);
			IF ~GfxRegions.RectEmpty(llx, lly, urx, ury) THEN
				GfxMaps.Create(BufMap, urx - llx, ury - lly, BufFmt);
				Warp(dc, map, dx, dy, llx, lly, urx, ury, m, filter);
				data.dc := dc; data.map := BufMap; data.dx := dx + llx; data.dy := dy + lly;
				GfxRegions.Enumerate(dc.clipReg, data.dx, data.dy, dx + urx, dy + ury, BlendMapRect, data)
			END
		ELSE
			CopyMap(dc, map, dx, dy, filter)
		END
	END Image;
	
	
	(*--- Gfx Context Methods ---*)
	
	PROCEDURE ResetCTM (ctxt: Gfx.Context);
		VAR dc: Context;
	BEGIN
		dc := ctxt(Context);
		GfxMatrix.Translate(GfxMatrix.Identity, dc.orgX, dc.orgY, dc.ctm);
		GfxMatrix.Scale(dc.ctm, dc.scale, dc.scale, dc.ctm)
	END ResetCTM;
	
	PROCEDURE ResetClip (ctxt: Gfx.Context);
		VAR dc: Context;
	BEGIN
		dc := ctxt(Context);
		GfxRaster.ResetClip(dc);
		GfxRegions.Copy(dc.defClip, dc.clipReg)
	END ResetClip;
	
	PROCEDURE Erase (ctxt: Gfx.Context);
		VAR dc: Context; data: RegData;
	BEGIN
		dc := ctxt(Context);
		data.col := dc.bgCol;
		GfxRegions.Enumerate(dc.defClip, dc.defClip.llx, dc.defClip.lly, dc.defClip.urx, dc.defClip.ury, DrawRect, data)
	END Erase;
	
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
		do.image := Image; do.newPattern := Gfx.DefNewPattern;
		IF TransferBlock THEN
			BlendDot := BlendDotBlk; TileRect := TileRectBlk;
			DrawMapRect := DrawMapRectBlk; BlendMapRect := DrawMapRectBlk;
			Warp := WarpBlk; CopyMap := CopyMapBlk
		ELSIF TrueColor THEN
			BlendDot := BlendDotRGB; TileRect := TileRectPix;
			DrawRun := DrawRunRGB; CopyRun := CopyRunRGB; BlendRun := BlendRunRGB;
			DrawMapRect := DrawMapRectPix; BlendMapRect := BlendMapRectPix;
			Warp := WarpPix; CopyMap := CopyMapPix
		ELSE
			BlendDot := BlendDotIdx; TileRect := TileRectPix;
			DrawRun := DrawRunIdx; CopyRun := CopyRunIdx; BlendRun := BlendRunIdx;
			DrawMapRect := DrawMapRectPix; BlendMapRect := BlendMapRectPix;
			Warp := WarpPix; CopyMap := CopyMapPix
		END
	END InitMethods;
	
	
	(*--- Exported Interface ---*)
	
	(** set default clip region to rectangle **)
	PROCEDURE SetClipRect* (dc: Context; llx, lly, urx, ury: INTEGER);
	BEGIN
		GfxRegions.SetToRect(dc.defClip, llx, lly, urx, ury)
	END SetClipRect;
	
	(** copy given region to default clip region **)
	PROCEDURE SetClipRegion* (dc: Context; reg: GfxRegions.Region);
	BEGIN
		GfxRegions.Copy(reg, dc.defClip)
	END SetClipRegion;
	
	(** set default coordinate origin and scale factor **)
	PROCEDURE SetCoordinates* (dc: Context; x, y, scale: REAL);
	BEGIN
		dc.orgX := x; dc.orgY := y; dc.scale := scale
	END SetCoordinates;
	
	(** set background color for display context **)
	PROCEDURE SetBGColor* (dc: Context; col: Gfx.Color);
	BEGIN
		dc.bg := col; GfxMaps.ColorToPixel(col, dc.bgPix);
		IF TrueColor THEN dc.bgCol := Display.RGB(col.r, col.g, col.b)
		ELSE dc.bgCol := GfxMaps.BestIndex(GfxMaps.DisplayPal, col.r, col.g, col.b)
		END
	END SetBGColor;
	
	(** initialize display context to rectangle **)
	PROCEDURE Init* (dc: Context; llx, lly, urx, ury: INTEGER);
	BEGIN
		GfxRaster.InitContext(dc);
		dc.do := Methods; dc.dot := Dot; dc.rect := Rect;
		IF TrueColor THEN dc.setColPat := SetColPatRGB
		ELSE dc.setColPat := SetColPatIdx
		END;
		NEW(dc.defClip); GfxRegions.Init(dc.defClip, GfxRegions.Winding);
		SetClipRect(dc, llx, lly, urx, ury);
		SetCoordinates(dc, llx, lly, 1);
		SetBGColor(dc, Gfx.White);
		Gfx.DefResetContext(dc)
	END Init;
	

BEGIN
	TrueColor := Display.TrueColor(Display.ColLeft);
	CASE Display.TransferFormat(Display.ColLeft) OF
	| Display.index8: BufFmt := GfxMaps.I8; TransferBlock := TRUE
	| Display.color555: BufFmt := GfxMaps.BGR555; TransferBlock := TRUE
	| Display.color565: BufFmt := GfxMaps.BGR565; TransferBlock := TRUE
	| Display.color888: BufFmt := GfxMaps.BGR24; TransferBlock := TRUE
	| Display.color8888: BufFmt := GfxMaps.BGRA32; TransferBlock := TRUE
	ELSE BufFmt := GfxMaps.PixelFormat; TransferBlock := FALSE
	END;
	IF TransferBlock THEN
		NEW(BufMap)
	END;
	InitMethods
END GfxDisplay.
