MODULE GfxOType;	(** eos   **)

	(**
		Support for OpenType fonts within the Gfx library (optional)
	**)
	
	IMPORT
		Math, Display, Strings, GfxMatrix, GfxMaps, GfxPaths, GfxFonts, OType;
		
	
	TYPE
		(** Gfx font wrapper for OpenType font **)
		Font* = POINTER TO FontDesc;
		FontDesc* = RECORD (GfxFonts.FontDesc)
			fam*: OType.Font;
			inst*: OType.Instance;
			glyph*: OType.Glyph;
			grey*: BOOLEAN;
		END;
		
		(* outline enumeration *)
		OutlineData = RECORD (OType.OutlineData)
			path: GfxPaths.Path;
			dx, dy: REAL;
			x, y: REAL;
		END;
		
		(* raster enumeration *)
		RasterData = RECORD (OType.RasterData)
			map: GfxMaps.Map;
		END;
		
	
	VAR
		Class: GfxFonts.Methods;
		
	
	(*--- Opening Fonts ---*)
	
	PROCEDURE OpenInstance (fam: OType.Font; glyph: OType.Glyph; ptsize: INTEGER; VAR mat: GfxMatrix.Matrix): Font;
		VAR font: Font; scale: REAL; dpi: INTEGER; m: OType.Matrix;
	BEGIN
		NEW(font); font.class := Class; font.fam := fam; font.glyph := glyph;
		scale := Math.sqrt(GfxMatrix.Det(mat));
		dpi := SHORT(ENTIER(scale * 914400/Display.Unit + 0.5));
		m[0] := ENTIER(10000H * mat[0, 0]/scale + 0.5); m[1] := ENTIER(10000H/scale * mat[0, 1] + 0.5);
		m[2] := ENTIER(10000H * mat[1, 0]/scale + 0.5); m[3] := ENTIER(10000H/scale * mat[1, 1] + 0.5);
		OType.GetInstance(fam, 40H*ptsize, dpi, dpi, m, font.inst);
		font.xmin := SHORT(font.inst.xmin DIV 40H); font.ymin := SHORT(font.inst.ymin DIV 40H);
		font.xmax := SHORT((font.inst.xmax + 3FH) DIV 40H); font.ymax := SHORT((font.inst.ymax + 3FH) DIV 40H);
		font.rfont := NIL;
		IF scale >= 50 THEN
			font.niceMaps := FALSE; font.grey := FALSE	(* considered equivalent to filled outlines *)
		ELSE
			font.niceMaps := font.inst.useHints; font.grey := font.inst.useGrey
		END;
		RETURN font
	END OpenInstance;
	
	PROCEDURE Open (VAR family, style: ARRAY OF CHAR; ptsize: INTEGER; VAR mat: GfxMatrix.Matrix): GfxFonts.Font;
		VAR font: Font; name: GfxFonts.FontName; fam: OType.Font; glyph: OType.Glyph;
	BEGIN
		font := NIL;
		COPY(family, name); Strings.Append(name, style);
		fam := OType.Open(family);
		IF fam # NIL THEN
			NEW(glyph); OType.InitGlyph(glyph, fam);
			font := OpenInstance(fam, glyph, ptsize, mat)
		END;
		RETURN font
	END Open;
	
	(** install procedure in GfxFonts.OpenProc **)
	PROCEDURE Install*;
	BEGIN
		GfxFonts.OpenProc := Open
	END Install;
	
	
	(*--- Font Methods ---*)
	
	PROCEDURE Derive (gfont: GfxFonts.Font; ptsize: INTEGER; VAR mat: GfxMatrix.Matrix): GfxFonts.Font;
		VAR font: Font;
	BEGIN
		font := gfont(Font);
		RETURN OpenInstance(font.fam, font.glyph, ptsize, mat)
	END Derive;
	
	PROCEDURE GetWidth (gfont: GfxFonts.Font; ch: CHAR; VAR dx, dy: REAL);
		VAR font: Font; num: INTEGER; mode: SET;
	BEGIN
		font := gfont(Font);
		num := OType.UnicodeToGlyph(font.fam, OType.CharToUnicode[ORD(ch)]);
		IF num < font.fam.maxp.numGlyphs THEN
			mode := {OType.Width};
			IF font.inst.useHints THEN INCL(mode, OType.Hinted) END;
			OType.LoadGlyph(font.inst, font.glyph, num, mode);
			dx := font.glyph.awx; dy := font.glyph.awy
		ELSE
			dx := 0; dy := 0
		END
	END GetWidth;
	
	PROCEDURE FillRect (llx, lly, urx, ury, opacity: INTEGER; VAR data: OType.RasterData0);
		VAR alpha: GfxMaps.Pixel;
	BEGIN
		WITH data: RasterData DO
			alpha[GfxMaps.A] := CHR(opacity);
			GfxMaps.Fill(data.map, llx, lly, urx, ury, alpha, GfxMaps.SrcCopy)
		END
	END FillRect;
	
	PROCEDURE GetMap (gfont: GfxFonts.Font; ch: CHAR; VAR x, y, dx, dy: REAL; VAR map: GfxMaps.Map);
		VAR font: Font; num: INTEGER; mode: SET; data: RasterData;
	BEGIN
		font := gfont(Font);
		num := OType.UnicodeToGlyph(font.fam, OType.CharToUnicode[ORD(ch)]);
		IF num < font.fam.maxp.numGlyphs THEN
			mode := {OType.Width, OType.Raster};
			IF font.inst.useHints THEN INCL(mode, OType.Hinted) END;
			IF font.inst.useGrey THEN INCL(mode, OType.Grey) END;
			OType.LoadGlyph(font.inst, font.glyph, num, mode);
			x := font.glyph.hbx; y := font.glyph.hby; dx := font.glyph.awx; dy := font.glyph.awy;
			IF font.glyph.rw * font.glyph.rh > 0 THEN
				NEW(map);
				IF font.inst.useGrey THEN GfxMaps.Create(map, font.glyph.rw, font.glyph.rh, GfxMaps.A8)
				ELSE GfxMaps.Create(map, font.glyph.rw, font.glyph.rh, GfxMaps.A1)
				END;
				data.rect := FillRect; data.map := map;
				OType.EnumRaster(font.glyph, data)
			ELSE
				map := NIL
			END
		ELSE
			x := 0; y := 0; dx := 0; dy := 0; map := NIL
		END
	END GetMap;
	
	PROCEDURE MoveTo (x, y: OType.F26D6; VAR data: OType.OutlineData0);
	BEGIN
		WITH data: OutlineData DO
			IF ~GfxPaths.Empty(data.path) THEN
				GfxPaths.AddExit(data.path, 0, 0)
			END;
			data.x := x/40H; data.y := y/40H;
			GfxPaths.AddEnter(data.path, data.x + data.dx, data.y + data.dy, 0, 0)
		END
	END MoveTo;
	
	PROCEDURE LineTo (x, y: OType.F26D6; VAR data: OType.OutlineData0);
	BEGIN
		WITH data: OutlineData DO
			data.x := x/40H; data.y := y/40H;
			GfxPaths.AddLine(data.path, data.x + data.dx, data.y + data.dy)
		END
	END LineTo;
	
	PROCEDURE BezierTo (x, y: ARRAY OF OType.F26D6; n: INTEGER; VAR data: OType.OutlineData0);
		VAR t, x1, x2, y1, y2: REAL;
	BEGIN
		WITH data: OutlineData DO
			IF n = 2 THEN	(* degree 2 *)
				t := 2*x[0]/40H; x1 := (data.x + t)/3; data.x := x[1]/40H; x2 := (data.x + t)/3;
				t := 2*y[0]/40H; y1 := (data.y + t)/3; data.y := y[1]/40H; y2 := (data.y + t)/3
			ELSE	(* degree 3 *)
				x1 := x[0]/40H; x2 := x[1]/40H; data.x := x[2]/40H;
				y1 := y[0]/40H; y2 := y[1]/40H; data.y := y[2]/40H
			END;
			GfxPaths.AddBezier(data.path, data.x + data.dx, data.y + data.dy, x1 + data.dx, y1 + data.dy, x2 + data.dx, y2 + data.dy)
		END
	END BezierTo;
	
	PROCEDURE GetOutline (gfont: GfxFonts.Font; ch: CHAR; x, y: REAL; path: GfxPaths.Path);
		VAR font: Font; num: INTEGER; data: OutlineData;
	BEGIN
		font := gfont(Font);
		GfxPaths.Clear(path);
		num := OType.UnicodeToGlyph(font.fam, OType.CharToUnicode[ORD(ch)]);
		IF num < font.fam.maxp.numGlyphs THEN
			OType.LoadGlyph(font.inst, font.glyph, num, {OType.Outline});
			data.moveto := MoveTo; data.lineto := LineTo; data.bezierto := BezierTo; data.path := path; data.dx := x; data.dy := y;
			OType.EnumOutline(font.glyph, data);
			IF ~GfxPaths.Empty(data.path) THEN
				GfxPaths.AddExit(data.path, 0, 0)
			END;
			GfxPaths.Close(path)
		END
	END GetOutline;
	
	PROCEDURE InitClass;
	BEGIN
		NEW(Class); Class.derive := Derive; Class.getwidth := GetWidth; Class.getmap := GetMap; Class.getoutline := GetOutline
	END InitClass;
	

BEGIN
	InitClass
END GfxOType.
