MODULE GfxFonts;	(** eos   **)

	(**
		Gfx font engine
	**)
	
	(*
		8.1.98 - GetInstance now transforms an existing bounding box correctly (eos)
		13.1.98 - bug fix in OpenRaster, font.ymax was not computed correctly for scaled raster fonts in OpenRaster
		13.1.98 - improved GetStringWidth; uses outline metrics now if images would be taken from outline, too
		9.2.98 - adapted SplineToBezier to new behaviour of GfxPaths.EnumSpline (no Enter/Exit)
		18.9.98 - major cleanup of both interface and implementation (support for other font formats, switch to GfxMaps,
			aging of cached chars, use GfxFonts0 to enumerate available raster fonts)
		9.12.98 - raster files; adaptation to new GfxMaps
		16.2.99 - bugfix in InitDefault (m[1, 1] wasn't set), tnx to pjm
		12.3.99 - bugfix in WFGetWidth (dy = dx)
		20.4.99 - put point size in separate field instead of merging it with font matrix
	*)
	
	IMPORT
		SYSTEM, Files, Math, Display, Fonts, Texts, Oberon, Strings, GfxMatrix, GfxMaps, GfxPictures, GfxPaths,
		GfxRegions, GfxFonts0;
		
	
	CONST
		FontNameLen* = 64;
		MaxCachedChars = 512;	(* maximal number of cached characters *)
		MetaFontTag = 01F7H; OldMetaFontTag = 701H - 1000H;	(* = F701H *)
		MaxBezierPoints = 3 * GfxPaths.MaxSplinePoints + 1;
		
	
	TYPE
		FontName* = ARRAY FontNameLen OF CHAR;
		
		(* Metafont outlines **)
		Outline = POINTER TO OutlineDesc;
		OutlineDesc = RECORD
			width: ARRAY 256 OF REAL;	(* width including left and right side bearings (0 if character undefined) *)
			len: ARRAY 256 OF SHORTINT;	(* number of subpaths of each character *)
			path: GfxPaths.Path;	(* path containing character outlines *)
			pos: ARRAY 256 OF INTEGER;	(* positions of characters within path *)
			xmin, ymin, xmax, ymax: REAL;	(* union of character bounding boxes *)
		END;
		
		(* cached characters *)
		Char = POINTER TO CharDesc;
		CharDesc = RECORD
			x, y, dx, dy: REAL;	(* metrics *)
			map: GfxMaps.Map;	(* pixels *)
			used: INTEGER;	(* number of accesses to this character *)
		END;
		
		(* raster file *)
		RasterChar = POINTER TO RasterCharDesc;
		RasterCharDesc = RECORD
			dx, x, y, w, h: INTEGER;
			adr: LONGINT;
		END;
		RasterFile = POINTER TO RasterFileDesc;
		RasterFileDesc = RECORD
			xmin, ymin, xmax, ymax: INTEGER;
			char: ARRAY 256 OF RasterChar;
			mem: POINTER TO ARRAY OF CHAR;
		END;
		
		(** font structure **)
		Font* = POINTER TO FontDesc;
		Methods* = POINTER TO MethodDesc;
		FontDesc* = RECORD
			class*: Methods;
			name*: FontName;	(** font name **)
			ptsize*: INTEGER;	(** point size **)
			mat*, wmat: GfxMatrix.Matrix;	(** font matrix **)
			xmin*, ymin*, xmax*, ymax*: INTEGER;	(** union of character bounding boxes **)
			rfont*, wfont: Fonts.Font;	(** raster font (if a suitable one exists) **)
			niceMaps*: BOOLEAN;	(** true if returned maps look better than the filled outlines **)
			outline: Outline;	(* outline, if available *)
			prev, next: Font;	(* previous and next font in font cache *)
			char: ARRAY 256 OF Char;	(* cached characters *)
			rfile: RasterFile;	(* link to raster file *)
		END;
		
		MethodDesc* = RECORD
			derive*: PROCEDURE (font: Font; ptsize: INTEGER; VAR mat: GfxMatrix.Matrix): Font;
			getwidth*: PROCEDURE (font: Font; ch: CHAR; VAR dx, dy: REAL);
			getmap*: PROCEDURE (font: Font; ch: CHAR; VAR x, y, dx, dy: REAL; VAR map: GfxMaps.Map);
			getoutline*: PROCEDURE (font: Font; ch: CHAR; x, y: REAL; path: GfxPaths.Path);
		END;
		
		PathEnumData = RECORD (GfxPaths.EnumData)
			xc, yc: ARRAY MaxBezierPoints OF REAL;	(* control points for spline-Bezier conversion *)
			n: INTEGER;	(* number of control points *)
			lx, ly: REAL;	(* current point for converting path to region *)
			px, py: INTEGER;	(* current region point coordinates *)
			region: GfxRegions.Region;
		END;
		
		RegEnumData = RECORD (GfxRegions.EnumData)
			map: GfxMaps.Map;
			dx, dy: INTEGER;
		END;
		
	
	VAR
		Default*: Font;	(** corresponds to Fonts.Default **)
		RClass, ORClass, FClass, OFClass, WRClass, OWRClass, WFClass, OWFClass, OClass: Methods;	(* builtin font classes *)
		Cache: Font;	(* sentinel for list of cached fonts *)
		Chars: LONGINT;	(* current number of cached characters *)
		TmpPath: GfxPaths.Path;
		TmpRegion: GfxRegions.Region;
		Inv: ARRAY 256 OF CHAR;	(* reverses bit order *)
		
		(**
			An extensible mechanism for opening font files in various formats works as follows: the section
			'FontFormats' in Oberon.Text contains a list of file types associated with command procedures.
			When one of these command procedures is called, it should set the global 'OpenProc' variable
			to a procedure which is able to open a font file if given font name, point size and font matrix
			and which returns a font structure if successful.
		**)
		OpenProc*: PROCEDURE (VAR family, style: ARRAY OF CHAR; size: INTEGER; VAR mat: GfxMatrix.Matrix): Font;
	
	
	(*--- Outlines ---*)
	
	(* append path element to Bezier control points *)
	PROCEDURE AddSplineElem (VAR data: GfxPaths.EnumData);
		CONST
			sqrt3 = 1.7320508; t = 4/3*(sqrt3 - 1);
		VAR
			rx, ry, trx, try: REAL;
	BEGIN
		WITH data: PathEnumData DO
			CASE data.elem OF
			| GfxPaths.Line:	(* spline is line *)
				data.xc[data.n] := data.x; data.yc[data.n] := data.y; INC(data.n)
			| GfxPaths.Arc:	(* spline is full circle *)
				rx := data.x - data.x0; ry := data.y - data.y0;
				trx := t * rx; try := t * ry;
				data.xc[data.n] := data.x0 + rx - try; data.yc[data.n] := data.y0 + ry + trx; INC(data.n);
				data.xc[data.n] := data.x0 - ry + trx; data.yc[data.n] := data.y0 + rx + try; INC(data.n);
				data.xc[data.n] := data.x0 - ry; data.yc[data.n] := data.y0 + rx; INC(data.n);
				data.xc[data.n] := data.x0 - ry - trx; data.yc[data.n] := data.y0 + rx + try; INC(data.n);
				data.xc[data.n] := data.x0 - rx - try; data.yc[data.n] := data.y0 - ry + trx; INC(data.n);
				data.xc[data.n] := data.x0 - rx; data.yc[data.n] := data.y0 - ry; INC(data.n);
				data.xc[data.n] := data.x0 - rx + try; data.yc[data.n] := data.y0 - ry - trx; INC(data.n);
				data.xc[data.n] := data.x0 + ry - trx; data.yc[data.n] := data.y0 - rx - try; INC(data.n);
				data.xc[data.n] := data.x0 + ry; data.yc[data.n] := data.y0 - rx; INC(data.n);
				data.xc[data.n] := data.x0 + ry + trx; data.yc[data.n] := data.y0 - rx + try; INC(data.n);
				data.xc[data.n] := data.x0 + rx + try; data.yc[data.n] := data.y0 + ry - trx; INC(data.n);
				data.xc[data.n] := data.x0 + rx; data.yc[data.n] := data.y0 + ry; INC(data.n)
			| GfxPaths.Bezier:
				data.xc[data.n] := data.x1; data.yc[data.n] := data.y1; INC(data.n);
				data.xc[data.n] := data.x2; data.yc[data.n] := data.y2; INC(data.n);
				data.xc[data.n] := data.x; data.yc[data.n] := data.y; INC(data.n)
			END
		END
	END AddSplineElem;
	
	(* convert natural spline to Bezier control points *)
	PROCEDURE SplineToBezier (VAR x, y: ARRAY OF REAL; VAR n: LONGINT; closed: BOOLEAN);
		VAR data: PathEnumData;
	BEGIN
		data.n := 1; data.x := x[0]; data.y := y[0];
		GfxPaths.EnumSpline(x, y, SHORT(n), closed, AddSplineElem, data);
		n := 1;
		WHILE n < data.n DO
			x[n] := data.xc[n]; y[n] := data.yc[n]; INC(n)
		END
	END SplineToBezier;
	
	(* convert Bezier2 to Bezier *)
	PROCEDURE Bezier2ToBezier (VAR x, y: ARRAY OF REAL; VAR n: LONGINT);
		VAR nout, m: LONGINT;
	BEGIN
		IF ODD(n) THEN
			nout := (n - 1) DIV 2 * 3 + 1;
			m := nout
		ELSE	(* ends with line *)
			nout := (n - 2) DIV 2 * 3 + 2;
			m := nout-1;
			x[m] := x[n-1]; y[m] := y[n-1]
		END;
		WHILE m > 0 DO
			DEC(m); DEC(n);
			x[m] := x[n]; y[m] := y[n];
			DEC(m); DEC(n);
			x[m] := (1/3)*(2*x[n] + x[m+1]); y[m] := (1/3)*(2*y[n] + y[m+1]);
			DEC(m);
			x[m] := (1/3)*(2*x[n] + x[n-1]); y[m] := (1/3)*(2*y[n] + y[n-1])
		END;
		n := nout
	END Bezier2ToBezier;
	
	(* load character outlines *)
	PROCEDURE LoadOutline (outline: Outline; VAR r: Files.Rider);
		CONST
			polygon = 0; bezier = 1; spline = 2; bezier2 = 3;
			maxNofContours = 128;
		
		VAR
			minY, maxY, base, i, y, ntypes, nchars, x, left, ncontours, n, m, cont, k: LONGINT; scale: REAL; ch: CHAR;
			type, pred, succ, last: ARRAY maxNofContours OF LONGINT; str: ARRAY 32 OF CHAR; kind: ARRAY 5 OF INTEGER;
			closed: BOOLEAN; px, py: POINTER TO ARRAY maxNofContours, MaxBezierPoints OF REAL;
			done: ARRAY maxNofContours OF BOOLEAN;
		
		PROCEDURE coincident (px, py, qx, qy: REAL; dist: LONGINT): BOOLEAN;
		BEGIN
			RETURN (ABS(px - qx) <= dist) & (ABS(py - qy) <= dist)
		END coincident;
		
	BEGIN
		minY := MAX(LONGINT); maxY := MIN(LONGINT); base := minY;
		FOR i := 1 TO 5 DO
			Files.ReadNum(r, y);
			IF y > maxY THEN maxY := y END;
			IF y < minY THEN base := minY; minY := y
			ELSIF y < base THEN base := y
			END
		END;
		scale := 1/(maxY - minY);
		
		NEW(outline.path);
		GfxPaths.Clear(outline.path);
		outline.xmin := MAX(REAL); outline.ymin := MAX(REAL);
		outline.xmax := MIN(REAL); outline.ymax := MIN(REAL);
		NEW(px); NEW(py);
		ntypes := 1;
		Files.ReadNum(r, nchars);
		WHILE nchars > 0 DO
			DEC(nchars);
			Files.Read(r, ch); Files.ReadNum(r, x); left := x;
			Files.ReadNum(r, x);
			IF x >= left THEN
				outline.width[ORD(ch)] := scale * SHORT(x - left)
			ELSE
				outline.width[ORD(ch)] := scale * SHORT(left - x);
				left := x
			END;
			
			(* read contour curves *)
			Files.ReadNum(r, ncontours);
			n := 0;
			WHILE n < ncontours DO
				Files.ReadNum(r, type[n]);
				IF type[n] = ntypes THEN
					Files.ReadString(r, str);
					ASSERT(str = "Graphic");
					Files.ReadString(r, str);
					IF str = "PolygonDesc" THEN kind[type[n]] := polygon
					ELSIF str = "BezierDesc" THEN kind[type[n]] := bezier
					ELSIF str = "SplineDesc" THEN kind[type[n]] := spline
					ELSIF str = "Bezier2Desc" THEN kind[type[n]] := bezier2
					ELSE HALT(101)
					END;
					INC(ntypes)
				END;
				Files.ReadBool(r, closed);
				IF closed THEN pred[n] := n; succ[n] := n
				ELSE pred[n] := -1; succ[n] := -1
				END;
				Files.ReadNum(r, m);
				DEC(m);
				FOR i := 0 TO m DO
					Files.ReadNum(r, x); Files.ReadNum(r, y);
					px[n, i] := x - left; py[n, i] := y - base
				END;
				IF m < 1 THEN
					DEC(ncontours)
				ELSE
					IF closed THEN
						INC(m); px[n, m] := px[n, 0]; py[n, m] := py[n, 0]
					END;
					IF kind[type[n]] = spline THEN
						INC(m);
						SplineToBezier(px[n], py[n], m, closed);
						DEC(m)
					ELSIF kind[type[n]] = bezier2 THEN
						INC(m);
						Bezier2ToBezier(px[n], py[n], m);
						DEC(m)
					END;
					FOR i := 0 TO m DO
						IF px[n, i] < outline.xmin THEN outline.xmin := px[n, i] END;
						IF px[n, i] > outline.xmax THEN outline.xmax := px[n, i] END;
						IF py[n, i] < outline.ymin THEN outline.ymin := py[n, i] END;
						IF py[n, i] > outline.ymax THEN outline.ymax := py[n, i] END
					END;
					last[n] := m;
					INC(n)
				END
			END;
			outline.len[ORD(ch)] := SHORT(SHORT(ncontours));
			
			(* find connected curves *)
			FOR i := 0 TO 3 DO
				n := 0;
				WHILE n < outline.len[ORD(ch)] DO
					m := n + 1;
					WHILE (pred[n] < 0) & (m < outline.len[ORD(ch)]) DO
						IF (succ[m] < 0) & coincident(px[n, 0], py[n, 0], px[m, last[m]], py[m, last[m]], i) THEN
							px[m, last[m]] := px[n, 0]; py[m, last[m]] := py[n, 0];
							pred[n] := m; succ[m] := n
						END;
						INC(m)
					END;
					m := n + 1;
					WHILE (succ[n] < 0) & (m < outline.len[ORD(ch)]) DO
						IF (pred[m] < 0) & coincident(px[n, last[n]], py[n, last[n]], px[m, 0], py[m, 0], i) THEN
							px[n, last[n]] := px[m, 0]; py[n, last[n]] := py[m, 0];
							succ[n] := m; pred[m] := n
						END;
						INC(m)
					END;
					INC(n)
				END
			END;
			FOR cont := 0 TO outline.len[ORD(ch)] - 1 DO
				(*done[cont] := (succ[cont] < 0) OR (pred[cont] < 0)*)	(* ignore open curves *)
				done[cont] := FALSE
			END;
			
			(* append contour curves to path *)
			outline.pos[ORD(ch)] := outline.path.elems;
			cont := 0; k := 0;
			WHILE cont < outline.len[ORD(ch)] DO
				IF ~done[cont] THEN
					n := cont; m := pred[n];
					IF m < 0 THEN
						GfxPaths.AddEnter(outline.path, scale * px[n, 0], scale * py[n, 0], 0, 0)
					ELSE
						i := last[m];
						GfxPaths.AddEnter(outline.path, scale * px[n, 0], scale * py[n, 0], scale * (px[m, i] - px[m, i - 1]), scale * (py[m, i] - py[m, i - 1]))
					END;
					REPEAT
						i := 1;
						WHILE i <= last[n] DO
							IF (kind[type[n]] = polygon) OR (i+2 > last[n]) THEN
								GfxPaths.AddLine(outline.path, scale * px[n, i], scale * py[n, i]);
								INC(i)
							ELSE
								GfxPaths.AddBezier(outline.path, scale * px[n, i+2], scale * py[n, i+2], scale * px[n, i], scale * py[n, i],
								  scale * px[n, i+1], scale * py[n, i+1]);
								INC(i, 3)
							END
						END;
						done[n] := TRUE;
						n := succ[n]
					UNTIL (n < 0) OR (n = cont);
					IF n < 0 THEN
						GfxPaths.AddExit(outline.path, 0, 0)
					ELSE
						GfxPaths.AddExit(outline.path, scale * (px[n, 1] - px[n, 0]), scale * (py[n, 1] - py[n, 0]))
					END;
					INC(k)
				END;
				INC(cont)
			END;
			outline.len[ORD(ch)] := SHORT(SHORT(k))
		END;
		outline.xmin := scale * outline.xmin; outline.ymin := scale * outline.ymin;
		outline.xmax := scale * outline.xmax; outline.ymax := scale * outline.ymax
	END LoadOutline;
	
	
	(*--- Font Cache ---*)
	
	(* enter font in font cache *)
	PROCEDURE CacheFont (font: Font);
	BEGIN
		font.prev := Cache.prev; Cache.prev.next := font;
		font.next := Cache; Cache.prev := font
	END CacheFont;
	
	(* put character into cache *)
	PROCEDURE CacheChar (font: Font; ch: CHAR; x, y, dx, dy: REAL; map: GfxMaps.Map);
		VAR char: Char; n, m: LONGINT;
	BEGIN
		NEW(char); font.char[ORD(ch)] := char;
		char.x := x; char.y := y; char.dx := dx; char.dy := dy; char.map := map;
		INC(Chars); char.used := 4;	(* extra bonus for new character in cache *)
		WHILE Chars = MaxCachedChars DO
			font := Cache.next;
			WHILE font # Cache DO
				n := 0; m := 0;
				WHILE n < 256 DO
					char := font.char[n];
					IF char # NIL THEN
						char.used := char.used DIV 2;	(* age number of uses *)
						IF char.used = 0 THEN	(* remove character from cache *)
							DEC(Chars); font.char[n] := NIL
						ELSE
							INC(m)
						END
					END;
					INC(n)
				END;
				IF m = 0 THEN	(* no characters cached => remove font from cache *)
					font.prev.next := font.next; font.next.prev := font.prev
				END;
				font := font.next
			END
		END
	END CacheChar;
	
	(* return cached character *)
	PROCEDURE CachedChar (font: Font; ch: CHAR): Char;
		VAR char: Char;
	BEGIN
		char := font.char[ORD(ch)];
		IF char # NIL THEN INC(char.used) END;
		RETURN char
	END CachedChar;
	
	
	(**--- Fonts ---**)
	
	(* extract family and style from font name *)
	PROCEDURE SplitName (name: ARRAY OF CHAR; VAR fam, style: ARRAY OF CHAR);
		VAR i, j: LONGINT;
	BEGIN
		fam[0] := name[0];
		i := 1;
		WHILE (name[i] >= "a") & (name[i] <= "z") DO
			fam[i] := name[i];
			INC(i)
		END;
		fam[i] := 0X;
		WHILE (name[i] >= "0") & (name[i] <= "9") DO INC(i) END;
		IF (name[i] = "-") OR (name[i] = " ") THEN INC(i) END;
		j := 0;
		WHILE (name[i] # 0X) & (CAP(name[i]) >= "A") & (CAP(name[i]) <= "Z") DO
			style[j] := name[i];
			INC(i); INC(j)
		END;
		IF j = 1 THEN
			CASE CAP(style[0]) OF
			| "I": COPY("Italic", style)
			| "B": COPY("Bold", style)
			| "M": COPY("Medium", style)
			| "J": COPY("BoldItalic", style)
			ELSE style[1] := 0X
			END
		ELSE
			style[j] := 0X
		END
	END SplitName;
	
	(* create font name from family and style *)
	PROCEDURE BuildName (fam, style: ARRAY OF CHAR; VAR name: ARRAY OF CHAR);
	BEGIN
		COPY(fam, name);
		IF style # "" THEN
			Strings.AppendCh(name, "-");
			Strings.Append(name, style)
		END
	END BuildName;
	
	(* open MetaFont *)
	PROCEDURE OpenOutline (VAR family, style: ARRAY OF CHAR): Outline;
		VAR fname: FontName; file: Files.File; r: Files.Rider; tag: INTEGER; outline: Outline;
	BEGIN
		COPY(family, fname); Strings.Append(fname, style); Strings.Append(fname, ".MTF");
		file := Files.Old(fname);
		IF file # NIL THEN
			Files.Set(r, file, 0);
			Files.ReadInt(r, tag);
			IF (tag = OldMetaFontTag) OR (tag = MetaFontTag) THEN
				NEW(outline); LoadOutline(outline, r);
				RETURN outline
			END
		END;
		RETURN NIL
	END OpenOutline;
	
	PROCEDURE LoadRaster (VAR name: ARRAY OF CHAR): RasterFile;
		VAR
			rfile: RasterFile; file: Files.File; r: Files.Rider; id, ch: CHAR; type: SHORTINT; height, runs, i, j: INTEGER;
			beg, end: ARRAY 32 OF INTEGER; size, adr: LONGINT;
	BEGIN
		rfile := NIL;
		file := Files.Old(name);	(* guaranteed to exist *)
		Files.Set(r, file, 0);
		Files.Read(r, id); Files.Read(r, type);
		IF (id = Fonts.FontId) & (type = Fonts.font) THEN
			NEW(rfile);
			Files.Read(r, ch); Files.Read(r, ch); Files.ReadInt(r, height);
			Files.ReadInt(r, rfile.xmin); Files.ReadInt(r, rfile.xmax);
			Files.ReadInt(r, rfile.ymin); Files.ReadInt(r, rfile.ymax);
			Files.ReadInt(r, runs);
			i := 0;
			WHILE i < runs DO
				Files.ReadInt(r, beg[i]); Files.ReadInt(r, end[i]); INC(i)
			END;
			i := 0; size := 0;
			WHILE i < runs DO
				j := beg[i];
				WHILE j < end[i] DO
					NEW(rfile.char[j]);
					Files.ReadInt(r, rfile.char[j].dx);
					Files.ReadInt(r, rfile.char[j].x); Files.ReadInt(r, rfile.char[j].y);
					Files.ReadInt(r, rfile.char[j].w); Files.ReadInt(r, rfile.char[j].h);
					size := size + (rfile.char[j].w + 7) DIV 8 * rfile.char[j].h;
					INC(j)
				END;
				INC(i)
			END;
			NEW(rfile.mem, size);
			i := 0; adr := SYSTEM.ADR(rfile.mem[0]);
			WHILE i < runs DO
				j := beg[i];
				WHILE j < end[i] DO
					rfile.char[j].adr := adr;
					size := (rfile.char[j].w + 7) DIV 8 * rfile.char[j].h;
					WHILE size > 0 DO
						Files.Read(r, ch);
						SYSTEM.PUT(adr, Inv[ORD(ch)]);	(* GfxMaps.A1 expects leftmost pixel in most significant bit! *)
						INC(adr); DEC(size)
					END;
					INC(j)
				END;
				INC(i)
			END
		END;
		RETURN rfile
	END LoadRaster;
	
	(* open raster font *)
	PROCEDURE OpenRaster (VAR family, style: ARRAY OF CHAR; ptsize: INTEGER; VAR mat: GfxMatrix.Matrix; outline: Outline): Font;
		VAR
			rfont: Fonts.Font; rfile: RasterFile; font: Font; scale, xmin, ymin, xmax, ymax: REAL; ppm, fppm: INTEGER;
			ext, pstr: ARRAY 9 OF CHAR; name: FontName;
	BEGIN
		rfont := NIL; rfile := NIL; font := NIL;
		scale := Math.sqrt(ABS(GfxMatrix.Det(mat)));
		
		(* ask system for font *)
		IF scale < 2.5 THEN ppm := SHORT(ENTIER(ptsize * scale + 0.5)); ext := ".Scn.Fnt"
		ELSIF scale < 4.5 THEN ppm := SHORT(ENTIER(ptsize * scale * (914400/Display.Unit)/300 + 0.5)); ext := ".Pr3.Fnt"
		ELSE ppm := SHORT(ENTIER(ptsize * scale * (914400/Display.Unit)/600 + 0.5)); ext := ".Pr6.Fnt"
		END;
		fppm := ppm;	(* match is exact if there is one *)
		Strings.IntToStr(ppm, pstr);
		COPY(family, name); Strings.Append(name, pstr);
		IF style = "BoldItalic" THEN Strings.AppendCh(name, "j")
		ELSIF style # "" THEN Strings.AppendCh(name, CHR(ORD(CAP(style[0])) - ORD("A") + ORD("a")))
		END;
		Strings.Append(name, ext);
		rfont := Fonts.This(name);
		IF (rfont # NIL) & (rfont.type # Fonts.font) THEN rfont := NIL END;	(* dismiss substitutes and metrics *)
		
		(* check available raster font files *)
		IF rfont = NIL THEN
			ppm := SHORT(ENTIER(ptsize * scale + 0.5));
			GfxFonts0.Find(family, style, ppm, name, fppm);
			IF name # "" THEN
				rfont := Fonts.This(name);
				IF (rfont # NIL) & (rfont.type # Fonts.font) THEN rfont := NIL END;	(* dismiss substitutes and metrics *)
				IF rfont = NIL THEN
					rfile := LoadRaster(name)
				END
			END
		END;
		
		IF rfont # NIL THEN	(* found matching Oberon raster font *)
			IF (fppm = ppm) & ~GfxMatrix.Rotated(mat) & (mat[0, 0] > 0) & (mat[1, 1] > 0) & (mat[0, 0] = mat[1, 1]) THEN
				NEW(font); font.outline := outline; font.rfont := rfont; font.niceMaps := TRUE;
				IF outline = NIL THEN font.class := RClass
				ELSE font.class := ORClass
				END;
				font.xmin := rfont.minX; font.ymin := rfont.minY;
				font.xmax := rfont.maxX; font.ymax := rfont.maxY
			ELSIF (outline = NIL) OR (scale <= 2) THEN	(* use warped raster font *)
				NEW(font); font.outline := outline; font.wfont := rfont; font.niceMaps := TRUE;
				IF outline = NIL THEN font.class := WRClass
				ELSE font.class := OWRClass	(* can still use outlines if explicitly requested *)
				END;
				scale := 1/scale * ppm/fppm;
				GfxMatrix.Scale(mat, scale, scale, font.wmat);
				GfxMatrix.ApplyToRect(font.wmat, rfont.minX, rfont.minY, rfont.maxX, rfont.maxY, xmin, ymin, xmax, ymax);
				font.xmin := SHORT(ENTIER(xmin)); font.ymin := SHORT(ENTIER(ymin));
				font.xmax := -SHORT(ENTIER(-xmax)); font.ymax := -SHORT(ENTIER(-ymax))
			END
		
		ELSIF rfile # NIL THEN	(* installable Printer refused to give us Pr?.Fnt though raster file exists *)
			IF (fppm = ppm) & ~GfxMatrix.Rotated(mat) & (mat[0, 0] > 0) & (mat[1, 1] > 0) & (mat[0, 0] = mat[1, 1]) THEN
				NEW(font); font.outline := outline; font.rfile := rfile; font.niceMaps := TRUE;
				IF outline = NIL THEN font.class := FClass
				ELSE font.class := OFClass
				END;
				font.xmin := rfile.xmin; font.ymin := rfile.ymin; font.xmax := rfile.xmax; font.ymax := rfile.ymax
			ELSIF (outline = NIL) OR (scale < 2) THEN	(* use warped font file *)
				NEW(font); font.outline := outline; font.rfile := rfile; font.niceMaps := TRUE;
				IF outline = NIL THEN font.class := WFClass
				ELSE font.class := OWFClass
				END;
				scale := 1/scale * ppm/fppm;
				GfxMatrix.Scale(mat, scale, scale, font.wmat);
				GfxMatrix.ApplyToRect(font.wmat, rfile.xmin, rfile.ymin, rfile.xmax, rfile.ymax, xmin, ymin, xmax, ymax);
				font.xmin := SHORT(ENTIER(xmin)); font.ymin := SHORT(ENTIER(ymin));
				font.xmax := -SHORT(ENTIER(-xmax)); font.ymax := -SHORT(ENTIER(-ymax))
			END
		END;
		
		IF (font = NIL) & (outline # NIL) THEN	(* use outline only, no raster *)
			NEW(font); font.class := OClass; font.outline := outline; font.niceMaps := FALSE;
			scale := ptsize * (914400/Display.Unit)/72.27;	(* scale to display resolution *)
			GfxMatrix.Scale(mat, scale, scale, font.wmat);
			GfxMatrix.ApplyToRect(font.wmat, outline.xmin, outline.ymin, outline.xmax, outline.ymax, xmin, ymin, xmax, ymax);
			font.xmin := SHORT(ENTIER(xmin)); font.ymin := SHORT(ENTIER(ymin));
			font.xmax := -SHORT(ENTIER(-xmax)); font.ymax := -SHORT(ENTIER(-ymax))
		END;
		
		RETURN font
	END OpenRaster;
	
	(**
		open font given point size and transformation matrix. the transformation is applied to the display font at that size.
		the preferred way to specify a font is "Family-Style" (e.g. "Oberon-Bold"), although others are accepted as well
		("OberonBold", "Oberon10b")
	**)
	PROCEDURE Open* (name: ARRAY OF CHAR; ptsize: INTEGER; mat: GfxMatrix.Matrix): Font;
		VAR family, style, fname: FontName; font, cand: Font; s: Texts.Scanner; cmd: FontName; res: INTEGER;
	BEGIN
		mat[2, 0] := 0; mat[2, 1] := 0;
		SplitName(name, family, style);
		BuildName(family, style, fname);
		
		(* search in cache *)
		font := Cache.next; cand := NIL;
		WHILE font # Cache DO
			IF font.name = fname THEN
				cand := font;	(* keep for deriving font *)
				IF (ptsize = font.ptsize) & GfxMatrix.Equal(font.mat, mat) THEN
					RETURN font
				END
			END;
			font := font.next
		END;
		
		(* derive from existing font if possible *)
		IF cand # NIL THEN
			font := cand.class.derive(cand, ptsize, mat);
			IF font # NIL THEN
				COPY(fname, font.name); font.ptsize := ptsize; font.mat := mat;
				CacheFont(font);
				RETURN font
			END
		END;
		
		(* try registered font formats *)
		Oberon.OpenScanner(s, "FontFormats");
		WHILE s.class IN {Texts.Name, Texts.String} DO
			COPY(s.s, cmd); Texts.Scan(s);
			IF (s.class = Texts.Char) & (s.c = "=") THEN
				Texts.Scan(s); cmd := "";
				IF s.class = Texts.Name THEN
					COPY(s.s, cmd); Texts.Scan(s)
				END
			END;
			IF cmd # "" THEN
				OpenProc := NIL;
				Oberon.Call(cmd, Oberon.Par, FALSE, res);
				IF OpenProc # NIL THEN
					font := OpenProc(family, style, ptsize, mat);
					IF font # NIL THEN
						COPY(fname, font.name); font.ptsize := ptsize; font.mat := mat;
						CacheFont(font);
						RETURN font
					END
				END
			END
		END;
		
		(* try standard raster/outline fonts *)
		font := OpenRaster(family, style, ptsize, mat, OpenOutline(family, style));
		IF font # NIL THEN
			COPY(fname, font.name); font.ptsize := ptsize; font.mat := mat;
			CacheFont(font);
			RETURN font
		END;
		
		RETURN NIL
	END Open;
	
	(** open font of specified point size at display resolution **)
	PROCEDURE OpenSize* (name: ARRAY OF CHAR; ptsize: INTEGER): Font;
	BEGIN
		RETURN Open(name, ptsize, GfxMatrix.Identity)
	END OpenSize;
	
	(** return character advance vector **)
	PROCEDURE GetWidth* (font: Font; ch: CHAR; VAR dx, dy: REAL);
		VAR char: Char;
	BEGIN
		char := CachedChar(font, ch);
		IF char # NIL THEN
			dx := char.dx; dy := char.dy
		ELSE
			font.class.getwidth(font, ch, dx, dy)
		END
	END GetWidth;
	
	(** return character image map **)
	PROCEDURE GetMap* (font: Font; ch: CHAR; VAR x, y, dx, dy: REAL; VAR map: GfxMaps.Map);
		VAR char: Char;
	BEGIN
		char := CachedChar(font, ch);
		IF char # NIL THEN
			x := char.x; y := char.y; dx := char.dx; dy := char.dy; map := char.map
		ELSE
			font.class.getmap(font, ch, x, y, dx, dy, map);
			CacheChar(font, ch, x, y, dx, dy, map)
		END
	END GetMap;
	
	(** store character outline rooted at given position in given path **)
	PROCEDURE GetOutline* (font: Font; ch: CHAR; x, y: REAL; path: GfxPaths.Path);
	BEGIN
		font.class.getoutline(font, ch, x, y, path)
	END GetOutline;
	
	(** compute advance vector for complete string **)
	PROCEDURE GetStringWidth* (font: Font; str: ARRAY OF CHAR; VAR dx, dy: REAL);
		VAR i: LONGINT; ddx, ddy: REAL;
	BEGIN
		i := 0; dx := 0; dy := 0;
		WHILE str[i] # 0X DO
			GetWidth(font, str[i], ddx, ddy);
			dx := dx + ddx; dy := dy + ddy;
			INC(i)
		END
	END GetStringWidth;
	
	
	(*--- Derive Methods ---*)
	
	(* cannot derive font if no outline is known *)
	PROCEDURE RFDerive (font: Font; ptsize: INTEGER; VAR mat: GfxMatrix.Matrix): Font;
	BEGIN
		RETURN NIL
	END RFDerive;
	
	(* derive font with same outline *)
	PROCEDURE ODerive (font: Font; ptsize: INTEGER; VAR mat: GfxMatrix.Matrix): Font;
		VAR family, style: FontName;
	BEGIN
		SplitName(font.name, family, style);
		RETURN OpenRaster(family, style, ptsize, mat, font.outline)
	END ODerive;
	
	
	(*--- GetWidth Methods ---*)
	
	(* ... directly from raster font *)
	PROCEDURE RGetWidth (font: Font; ch: CHAR; VAR dx, dy: REAL);
		VAR aw, bx, by, w, h: INTEGER; pat: Display.Pattern;
	BEGIN
		Fonts.GetChar(font.rfont, ch, aw, bx, by, w, h, pat);
		dx := aw; dy := 0
	END RGetWidth;
	
	(* ... from warped raster font *)
	PROCEDURE WRGetWidth (font: Font; ch: CHAR; VAR dx, dy: REAL);
		VAR aw, bx, by, w, h: INTEGER; pat: Display.Pattern;
	BEGIN
		Fonts.GetChar(font.wfont, ch, aw, bx, by, w, h, pat);
		dx := aw * font.wmat[0, 0]; dy := aw * font.wmat[0, 1]
	END WRGetWidth;
	
	(* ... from file *)
	PROCEDURE FGetWidth (font: Font; ch: CHAR; VAR dx, dy: REAL);
		VAR rfile: RasterFile;
	BEGIN
		rfile := font.rfile;
		dx := rfile.char[ORD(ch)].dx; dy := 0
	END FGetWidth;
	
	(* ... from warped file *)
	PROCEDURE WFGetWidth (font: Font; ch: CHAR; VAR dx, dy: REAL);
	BEGIN
		FGetWidth(font, ch, dx, dy);
		dy := dx * font.wmat[0, 1];
		dx := dx * font.wmat[0, 0]
	END WFGetWidth;
	
	(* ... from outline *)
	PROCEDURE OGetWidth (font: Font; ch: CHAR; VAR dx, dy: REAL);
		VAR w: REAL;
	BEGIN
		w := font.outline.width[ORD(ch)];
		dx := w * font.wmat[0, 0]; dy := w * font.wmat[0, 1]
	END OGetWidth;
	
	
	(*--- GetMap Methods ---*)
	
	PROCEDURE WarpMap (src: GfxMaps.Map; mat: GfxMatrix.Matrix; VAR x, y: REAL; VAR dst: GfxMaps.Map);
		VAR
			x0, y0, x1, y1: REAL;
			omiBug: GfxMaps.Filter;	(* force loading of type descriptor *)
	BEGIN
		GfxMatrix.Apply(mat, x, y, x, y);
		x0 := 0; y0 := 0; x1 := 0; y1 := 0;
		IF mat[0, 0] > 0 THEN x1 := src.width * mat[0, 0] ELSE x0 := src.width * mat[0, 0] END;
		IF mat[0, 1] > 0 THEN y1 := src.width * mat[0, 1] ELSE y0 := src.width * mat[0, 1] END;
		IF mat[1, 0] > 0 THEN x1 := x1 + src.height * mat[1, 0] ELSE x0 := x0 + src.height * mat[1, 0] END;
		IF mat[1, 1] > 0 THEN y1 := y1 + src.height * mat[1, 1] ELSE y0 := y0 + src.height * mat[1, 1] END;
		mat[2, 0] := -x0; mat[2, 1] := -y0;
		x := x + x0; y := y + y0;
		NEW(dst); GfxMaps.Create(dst, SHORT(-ENTIER(-x1) - ENTIER(x0)), SHORT(-ENTIER(-y1) - ENTIER(y0)), GfxMaps.A8);
		GfxMaps.Transform(src, dst, mat, GfxMaps.LinearFilter)
	END WarpMap;
	
	(* ... directly from raster font *)
	PROCEDURE RGetMap (font: Font; ch: CHAR; VAR x, y, dx, dy: REAL; VAR map: GfxMaps.Map);
		VAR aw, bx, by, w, h: INTEGER; pat: Display.Pattern;
	BEGIN
		Fonts.GetChar(font.rfont, ch, aw, bx, by, w, h, pat);
		x := bx; y := by; dx := aw; dy := 0;
		IF w * h = 0 THEN
			map := NIL
		ELSE
			NEW(map); GfxPictures.PatternToMap(pat, map)
		END
	END RGetMap;
	
	(* ... by warping raster font *)
	PROCEDURE WRGetMap (font: Font; ch: CHAR; VAR x, y, dx, dy: REAL; VAR map: GfxMaps.Map);
		VAR aw, bx, by, w, h: INTEGER; pat: Display.Pattern;
	BEGIN
		Fonts.GetChar(font.wfont, ch, aw, bx, by, w, h, pat);
		x := bx; y := by;
		dx := aw * font.wmat[0, 0]; dy := aw * font.wmat[0, 1];
		IF w * h = 0 THEN
			map := NIL
		ELSE
			NEW(map); GfxPictures.PatternToMap(pat, map);
			WarpMap(map, font.wmat, x, y, map)
		END
	END WRGetMap;
	
	(* ... from file *)
	PROCEDURE FGetMap (font: Font; ch: CHAR; VAR x, y, dx, dy: REAL; VAR map: GfxMaps.Map);
		VAR char: RasterChar;
	BEGIN
		char := font.rfile.char[ORD(ch)];
		IF char = NIL THEN
			dx := 0; dy := 0; x := 0; y := 0; map := NIL
		ELSE
			dx := char.dx; dy := 0;
			IF char.w * char.h = 0 THEN
				x := 0; y := 0; map := NIL
			ELSE
				x := char.x; y := char.y;
				NEW(map); GfxMaps.Init(map, char.w, char.h, GfxMaps.A1, (char.w+7) DIV 8, char.adr)
			END
		END
	END FGetMap;
	
	(* ... by warping from file *)
	PROCEDURE WFGetMap (font: Font; ch: CHAR; VAR x, y, dx, dy: REAL; VAR map: GfxMaps.Map);
	BEGIN
		FGetMap(font, ch, x, y, dx, dy, map);
		dy := dx * font.wmat[0, 1];
		dx := dx * font.wmat[0, 0];
		IF map # NIL THEN
			WarpMap(map, font.wmat, x, y, map)
		END
	END WFGetMap;
	
	PROCEDURE AddElem (VAR data: GfxPaths.EnumData);
		VAR px, py, x, y, xstep, ystep, steps: INTEGER; dx, ex, dy, ey, e: REAL;
	BEGIN
		WITH data: PathEnumData DO
			CASE data.elem OF
			| GfxPaths.Enter:
				data.lx := data.x; data.ly := data.y;
				data.px := SHORT(ENTIER(data.x + 0.5)); data.py := SHORT(ENTIER(data.y + 0.5))
			| GfxPaths.Line:
				px := SHORT(ENTIER(data.x + 0.5)); py := SHORT(ENTIER(data.y + 0.5));
				x := data.px; y := data.py;
				IF py = y THEN	(* horizontal line => ignore *)
					data.px := px
				ELSE
					dx := data.x - data.lx; dy := data.y - data.ly;
					IF dx >= 0 THEN xstep := 1; ex := data.lx - x
					ELSE xstep := -1; dx := -dx; ex := x - data.lx
					END;
					IF dy >= 0 THEN ystep := 1; ey := data.ly - y
					ELSE ystep := -1; dy := -dy; ey := y - data.ly
					END;
					e := dx * ey - dy * ex + 0.5 * (dy - dx);
					steps := ABS(px - x) + ABS(py - y);
					WHILE steps > 0 DO
						IF (e >= 0) & ((e > 0) OR (xstep <= 0)) THEN
							INC(y, ystep); e := e - dx;
							GfxRegions.AddPoint(data.region, x, y, ystep)
						ELSE
							INC(x, xstep); e := e + dy
							(* don't have to insert point here because regions are sliced horizontally *)
						END;
						DEC(steps)
					END;
					data.px := px; data.py := py
				END;
				data.lx := data.x; data.ly := data.y
			ELSE	(* ignore other elements *)
			END
		END
	END AddElem;
	
	PROCEDURE FillRect (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
		VAR pix: GfxMaps.Pixel;
	BEGIN
		WITH data: RegEnumData DO
			pix[GfxMaps.A] := 0FFX;
			GfxMaps.Fill(data.map, llx - data.dx, lly - data.dy, urx - data.dx, ury - data.dy, pix, GfxMaps.SrcCopy)
		END
	END FillRect;
	
	(* ... by filling interior of warped outline *)
	PROCEDURE OGetMap (font: Font; ch: CHAR; VAR x, y, dx, dy: REAL; VAR map: GfxMaps.Map);
		VAR w: REAL; pathdata: PathEnumData; llx, lly, urx, ury: INTEGER; regdata: RegEnumData;
	BEGIN
		w := font.outline.width[ORD(ch)];
		dx := w * font.wmat[0, 0]; dy := w * font.wmat[0, 1];
		font.class.getoutline(font, ch, 0, 0, TmpPath);
		GfxRegions.Clear(TmpRegion);
		pathdata.region := TmpRegion;
		GfxPaths.EnumFlattened(TmpPath, 0.5, AddElem, pathdata);
		IF GfxRegions.Empty(TmpRegion) THEN
			x := 0; y := 0; map := NIL
		ELSE
			llx := TmpRegion.llx; lly := TmpRegion.lly; urx := TmpRegion.urx; ury := TmpRegion.ury;
			NEW(map); GfxMaps.Create(map, urx - llx, ury - lly, GfxMaps.A1);
			regdata.map := map; regdata.dx := llx; regdata.dy := lly;
			GfxRegions.Enumerate(TmpRegion, llx, lly, urx, ury, FillRect, regdata);
			x := llx; y := lly
		END
	END OGetMap;
	
	
	(*--- GetOutline Methods ---*)
	
	(* ... undefined outline for pure raster fonts *)
	PROCEDURE RGetOutline (font: Font; ch: CHAR; x, y: REAL; path: GfxPaths.Path);
		VAR aw, bx, by, w, h: INTEGER; pat: Display.Pattern; l: REAL;
	BEGIN
		GfxPaths.Clear(path);
		Fonts.GetChar(font.rfont, ch, aw, bx, by, w, h, pat);
		IF w * h > 0 THEN
			x := x + bx; y := y + by; l := 0.1*font.rfont.height;
			GfxPaths.AddRect(path, x, y, x + w, y + h);
			GfxPaths.AddRect(path, x + l, y + h - l, x + w - l, y + l)
		END
	END RGetOutline;
	
	(* ... undefined outline for warped raster fonts *)
	PROCEDURE WRGetOutline (font: Font; ch: CHAR; x, y: REAL; path: GfxPaths.Path);
		VAR aw, bx, by, w, h: INTEGER; pat: Display.Pattern; l: REAL; m: GfxMatrix.Matrix;
	BEGIN
		GfxPaths.Clear(path);
		Fonts.GetChar(font.wfont, ch, aw, bx, by, w, h, pat);
		IF w * h > 0 THEN
			l := 0.1*font.wfont.height;
			GfxPaths.AddRect(path, bx, by, bx + w, by + h);
			GfxPaths.AddRect(path, bx + l, by + h - l, bx + w - l, by + l);
			m := font.wmat; m[2, 0] := m[2, 0] + x; m[2, 1] := m[2, 1] + y;
			GfxPaths.Apply(path, m)
		END
	END WRGetOutline;
	
	(* ... undefined outline for raster file fonts *)
	PROCEDURE FGetOutline (font: Font; ch: CHAR; x, y: REAL; path: GfxPaths.Path);
		VAR rfile: RasterFile; w, h: INTEGER; l: REAL;
	BEGIN
		GfxPaths.Clear(path);
		rfile := font.rfile;
		w := rfile.char[ORD(ch)].w; h := rfile.char[ORD(ch)].h;
		IF w * h > 0 THEN
			x := x + rfile.char[ORD(ch)].x; y := y + rfile.char[ORD(ch)].y;
			l := 0.1*(rfile.ymax - rfile.ymin);
			GfxPaths.AddRect(path, x, y, x + w, y + h);
			GfxPaths.AddRect(path, x + l, y + h - l, x + w - l, y + l)
		END
	END FGetOutline;
	
	(* ... undefined outline for warped raster file fonts *)
	PROCEDURE WFGetOutline (font: Font; ch: CHAR; x, y: REAL; path: GfxPaths.Path);
		VAR rfile: RasterFile; w, h, bx, by: INTEGER; l: REAL; m: GfxMatrix.Matrix;
	BEGIN
		GfxPaths.Clear(path);
		rfile := font.rfile;
		w := rfile.char[ORD(ch)].w; h := rfile.char[ORD(ch)].h;
		IF w * h > 0 THEN
			bx := rfile.char[ORD(ch)].x; by := rfile.char[ORD(ch)].y;
			l := 0.1*(rfile.ymax - rfile.ymin);
			GfxPaths.AddRect(path, bx, by, bx + w, by + h);
			GfxPaths.AddRect(path, bx + l, by + h - l, bx + w - l, by + l);
			m := font.wmat; m[2, 0] := m[2, 0] + x; m[2, 1] := m[2, 1] + y;
			GfxPaths.Apply(path, m)
		END
	END WFGetOutline;
	
	(* ... from outline structure *)
	PROCEDURE OGetOutline (font: Font; ch: CHAR; x, y: REAL; path: GfxPaths.Path);
		VAR outline: Outline; len: LONGINT; mat: GfxMatrix.Matrix; s: GfxPaths.Scanner; scale, dx, dy, x0, y0, x1, y1, x2, y2: REAL;
	BEGIN
		GfxPaths.Clear(path);
		outline := font.outline; len := outline.len[ORD(ch)];
		IF len > 0 THEN
			scale := font.ptsize * (914400/Display.Unit)/72.27;
			GfxMatrix.Scale(font.mat, scale, scale, mat);
			mat[2, 0] := mat[2, 0] + x; mat[2, 1] := mat[2, 1] + y;
			GfxPaths.Open(s, outline.path, outline.pos[ORD(ch)]);
			REPEAT
				CASE s.elem OF
				| GfxPaths.Enter:
					GfxMatrix.Apply(mat, s.x, s.y, x, y); GfxMatrix.ApplyToVector(mat, s.dx, s.dy, dx, dy);
					GfxPaths.AddEnter(path, x, y, dx, dy)
				| GfxPaths.Line:
					GfxMatrix.Apply(mat, s.x, s.y, x, y);
					GfxPaths.AddLine(path, x, y)
				| GfxPaths.Arc:
					GfxMatrix.Apply(mat, s.x, s.y, x, y); GfxMatrix.Apply(mat, s.x0, s.y0, x0, y0);
					GfxMatrix.Apply(mat, s.x1, s.y1, x1, y1); GfxMatrix.Apply(mat, s.x2, s.y2, x2, y2);
					GfxPaths.AddArc(path, x, y, x0, y0, x1, y1, x2, y2)
				| GfxPaths.Bezier:
					GfxMatrix.Apply(mat, s.x, s.y, x, y);
					GfxMatrix.Apply(mat, s.x1, s.y1, x1, y1); GfxMatrix.Apply(mat, s.x2, s.y2, x2, y2);
					GfxPaths.AddBezier(path, x, y, x1, y1, x2, y2)
				| GfxPaths.Exit:
					GfxMatrix.Apply(mat, s.dx, s.dy, dx, dy);
					GfxPaths.AddExit(path, dx, dy);
					DEC(len)
				END;
				GfxPaths.Scan(s)
			UNTIL len = 0
		END
	END OGetOutline;
	
	PROCEDURE InitClasses;
	BEGIN
		NEW(RClass); RClass.derive := RFDerive; RClass.getwidth := RGetWidth;
		RClass.getmap := RGetMap; RClass.getoutline := RGetOutline;
		NEW(ORClass); ORClass.derive := ODerive; ORClass.getwidth := RGetWidth;
		ORClass.getmap := RGetMap; ORClass.getoutline := OGetOutline;
		NEW(FClass); FClass.derive := RFDerive; FClass.getwidth := FGetWidth;
		FClass.getmap := FGetMap; FClass.getoutline := FGetOutline;
		NEW(OFClass); OFClass.derive := ODerive; OFClass.getwidth := FGetWidth;
		OFClass.getmap := FGetMap; OFClass.getoutline := OGetOutline;
		NEW(WRClass); WRClass.derive := RFDerive; WRClass.getwidth := WRGetWidth;
		WRClass.getmap := WRGetMap; WRClass.getoutline := WRGetOutline;
		NEW(OWRClass); OWRClass.derive := ODerive; OWRClass.getwidth := WRGetWidth;
		OWRClass.getmap := WRGetMap; OWRClass.getoutline := OGetOutline;
		NEW(WFClass); WFClass.derive := RFDerive; WFClass.getwidth := WFGetWidth;
		WFClass.getmap := WFGetMap; WFClass.getoutline := WFGetOutline;
		NEW(OWFClass); OWFClass.derive := ODerive; OWFClass.getwidth := WFGetWidth;
		OWFClass.getmap := WFGetMap; OWFClass.getoutline := OGetOutline;
		NEW(OClass); OClass.derive := ODerive; OClass.getwidth := OGetWidth;
		OClass.getmap := OGetMap; OClass.getoutline := OGetOutline
	END InitClasses;
	
	PROCEDURE InitDefault;
		VAR family, style: FontName; i: LONGINT;
	BEGIN
		NEW(Default); Default.class := RClass; Default.rfont := Fonts.Default; Default.niceMaps := TRUE;
		Default.xmin := Default.rfont.minX; Default.ymin := Default.rfont.minY;
		Default.xmax := Default.rfont.maxX; Default.ymax := Default.rfont.maxY;
		SplitName(Fonts.Default.name, family, style); BuildName(family, style, Default.name);
		i := 0; WHILE ("A" <= CAP(Fonts.Default.name[i])) & (CAP(Fonts.Default.name[i]) <= "Z") DO INC(i) END;
		Default.ptsize := 0; WHILE ("0" <= Fonts.Default.name[i]) & (Fonts.Default.name[i] <= "9") DO
			Default.ptsize := 10*Default.ptsize + ORD(Fonts.Default.name[i]) - ORD("0"); INC(i)
		END;
		IF Default.ptsize = 0 THEN Default.ptsize := 1 END;
		Default.mat := GfxMatrix.Identity
	END InitDefault;
	
	PROCEDURE InitInv;
		VAR ch, inv, bit: LONGINT;
	BEGIN
		FOR ch := 0 TO 0FFH DO
			inv := 0;
			FOR bit := 0 TO 7 DO
				IF ODD(ASH(ch, -bit)) THEN
					INC(inv, ASH(1, 7-bit))
				END
			END;
			Inv[ch] := CHR(inv)
		END
	END InitInv;
	

BEGIN
	InitInv;
	InitClasses; InitDefault;
	NEW(Cache); Cache.next := Cache; Cache.prev := Cache; Chars := 0;
	NEW(TmpPath);
	NEW(TmpRegion); GfxRegions.Init(TmpRegion, GfxRegions.Winding)
END GfxFonts.
