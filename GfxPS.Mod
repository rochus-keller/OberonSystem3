MODULE GfxPS;	(** eos   **)

	(**
		Graphics context generating PostScript code
	**)
	
	(*
		- cache picture palettes like images and patterns
		- algorithmic "standard" printer patterns
		
		12.2.98 - eliminated offset parameter in subpath begin
		17.2.98 - implemented RenderPath
		10.3.98 - fixed bug with empty clip and bounding rectangles
		2.10.98 - new image and font code
		3.11.98 - new dash pattern
	*)
	
	IMPORT
		Files, Texts, Oberon, Math, Strings, BIT, GfxMatrix, GfxMaps, GfxPaths, GfxFonts, Gfx;
		
	
	CONST
		(** useful units **)
		Inch* = 91.44; mm* = Inch/25.4;
		A4W* = 209.9 * mm; A4H* = 297 * mm;
		LetterW* = 215.9 * mm; LetterH* = 279 * mm;
		
		ScreenDPI = 91.44; PSDPI = 72;
		LF = 0AX; CR = 0DX;
		RLEBufLen = 128;
		NofSets = 8;	(* 256/32 *)
		PrologName = "GfxProlog.ps";
		ClipStackDepth = 8;
		
		R = GfxMaps.R; G = GfxMaps.G; B = GfxMaps.B;
		
	
	TYPE
		ClipPath = POINTER TO RECORD
			path: GfxPaths.Path;	(* clip path *)
			llx, lly, urx, ury: REAL;	(* bounding box *)
			evenOdd: BOOLEAN;	(* flag how to interpret path area *)
			next: ClipPath;	(* next element on stack *)
		END;
		
		Image = POINTER TO ImageDesc;
		ImageDesc = RECORD
			next: Image;
			map: GfxMaps.Map;
		END;
		
		Pattern = POINTER TO PatternDesc;
		PatternDesc = RECORD (Gfx.PatternDesc)
			next: Pattern;
			no: INTEGER;
		END;
		
		T1Font = POINTER TO T1FontDesc;
		T1FontDesc = RECORD
			next: T1Font;
			name: GfxFonts.FontName;
		END;
		
		T3Font = POINTER TO T3FontDesc;
		T3FontDesc = RECORD
			next: T3Font;
			name: GfxFonts.FontName;
			font: GfxFonts.Font;
			used: ARRAY NofSets OF SET;	(* characters effectively used in document *)
		END;
		
		Context* = POINTER TO ContextDesc;
		ContextDesc* = RECORD (Gfx.ContextDesc)
			psfile*: Files.File;	(** file onto which PostScript code is written **)
			out*: Files.Rider;	(** current output rider **)
			width*, height*: REAL;	(** paper size in default coordinates **)
			left*, bot*, right*, top*: REAL;	(** borders in default coordinates **)
			level2*, landscape*, eps*: BOOLEAN;	(** flags affecting generated code **)
			res*: LONGINT;	(** device resolution **)
			cp: GfxPaths.Path;	(* current path if Record flag isn't set *)
			llx, lly, urx, ury: REAL;	(* document bounding box *)
			fileLen: LONGINT;	(* number of bytes relevant for output pages *)
			pages: INTEGER;	(* number of pages written *)
			defMatrix: GfxMatrix.Matrix;	(* default matrix *)
			clip: ClipPath;	(* current list of clip paths *)
			clipStack: ARRAY ClipStackDepth OF ClipPath;	(* saved clip paths *)
			clipDepth: LONGINT;	(* number of saved clip paths *)
			simpleCap, simpleJoin, simpleStroke, simpleFill: BOOLEAN;	(* flags for deciding whether to let PostScript stroke the current path *)
			closed: BOOLEAN;	(* flag if current subpath might be closed *)
			sx, sy, cx, cy: REAL;	(* current subpath parameters *)
			color: Gfx.Color;	(* current color in PS graphics state *)
			pattern: Gfx.Pattern;	(* current pattern *)
			images: Image;	(* list of used image maps *)
			patterns: Pattern;	(* list of used patterns *)
			t1fonts: T1Font;	(* list of used outline fonts *)
			t3fonts: T3Font;	(* list of used bitmap fonts *)
			fontname: GfxFonts.FontName;	(* name of current PS font *)
			fontmat: GfxMatrix.Matrix;	(* instance matrix of current PS font *)
		END;
		
		RLEData = RECORD
			len, n: INTEGER;
			buf: ARRAY RLEBufLen OF CHAR;
		END;
		
	
	VAR
		Methods: Gfx.Methods;
		TmpPath: GfxPaths.Path;
		
	
	(*--- Basic Output ---*)
	
	PROCEDURE Ch (VAR r: Files.Rider; ch: CHAR);
	BEGIN
		Files.Write(r, ch)
	END Ch;
	
	PROCEDURE Blank (VAR r: Files.Rider);
	BEGIN
		Files.Write(r, " ")
	END Blank;
	
	PROCEDURE Ln (VAR r: Files.Rider);
	BEGIN
		Files.Write(r, CR); Files.Write(r, LF)
	END Ln;
	
	PROCEDURE Hex (VAR r: Files.Rider; n: LONGINT);
	BEGIN
		IF n >= 10 THEN
			Ch(r, CHR(n - 10 + ORD("a")))
		ELSE
			Ch(r, CHR(n + ORD("0")))
		END
	END Hex;
	
	PROCEDURE HexCol (VAR r: Files.Rider; col: GfxMaps.Color);
	BEGIN
		Hex(r, col.r DIV 16); Hex(r, col.r MOD 16);
		Hex(r, col.g DIV 16); Hex(r, col.g MOD 16);
		Hex(r, col.b DIV 16); Hex(r, col.b MOD 16)
	END HexCol;
	
	PROCEDURE Str (VAR r: Files.Rider; s: ARRAY OF CHAR);
	BEGIN
		Files.WriteBytes(r, s, Strings.Length(s))
	END Str;
	
	PROCEDURE Int (VAR r: Files.Rider; l: LONGINT);
		VAR s: ARRAY 12 OF CHAR;
	BEGIN
		Strings.IntToStr(l, s);
		Str(r, s)
	END Int;
	
	PROCEDURE Real (VAR r: Files.Rider; x: REAL);
		VAR l: LONGINT;
	BEGIN
		IF x < 0 THEN Ch(r, "-"); x := -x END;
		x := x + 0.00005;
		Int(r, ENTIER(x));
		l := ENTIER(10000 * (x - ENTIER(x)));
		IF l > 0 THEN
			Ch(r, ".");
			WHILE l > 0 DO
				Ch(r, CHR(ORD("0") + l DIV 1000));
				l := 10 * (l MOD 1000)
			END
		END
	END Real;
	
	
	(*--- Structure Output ---*)
	
	PROCEDURE Point (VAR r: Files.Rider; x, y: REAL);
	BEGIN
		Real(r, x); Blank(r); Real(r, y)
	END Point;
	
	PROCEDURE Matrix (VAR r: Files.Rider; VAR m: GfxMatrix.Matrix);
	BEGIN
		Ch(r, "[");
		Real(r, m[0, 0]); Blank(r); Real(r, m[0, 1]); Blank(r);
		Real(r, m[1, 0]); Blank(r); Real(r, m[1, 1]); Blank(r);
		Real(r, m[2, 0]); Blank(r); Real(r, m[2, 1]);
		Ch(r, "]");
	END Matrix;
	
	PROCEDURE Array (VAR r: Files.Rider; VAR a: ARRAY OF REAL; len: LONGINT);
		VAR i: LONGINT;
	BEGIN
		Ch(r, "[");
		IF len > 0 THEN
			Real(r, a[0]);
			i := 1;
			WHILE i < len DO
				Blank(r); Real(r, a[i]); INC(i)
			END
		END;
		Ch(r, "]")
	END Array;
	
	PROCEDURE Literal (VAR r: Files.Rider; VAR str: ARRAY OF CHAR);
		VAR i: LONGINT; ch: CHAR;
	BEGIN
		Ch(r, "(");
		i := 0; ch := str[0];
		WHILE ch # 0X DO
			CASE ch OF
			| "(", ")", "\":
				Ch(r, "\"); Ch(r, ch)
			| 01X..08X, 0BX, 0EX..1FX, 80X..0FFX:
				Ch(r, "\");
				Ch(r, CHR(ORD("0") + ORD(ch) DIV 64));
				Ch(r, CHR(ORD("0") + ORD(ch) MOD 64 DIV 8));
				Ch(r, CHR(ORD("0") + ORD(ch) MOD 8))
			ELSE
				Ch(r, ch)
			END;
			INC(i); ch := str[i];
		END;
		Ch(r, ")")
	END Literal;
	
	PROCEDURE Arc (VAR r: Files.Rider; sx, sy, ex, ey, x0, y0, dx1, dy1, dx2, dy2: REAL);
		CONST eps = 0.001;
		
		VAR tmp: REAL; mat, m: GfxMatrix.Matrix;
		
		PROCEDURE angle (x, y: REAL): REAL;
			VAR phi: REAL;
		BEGIN
			IF (ABS(x) < 1.0) & (ABS(y) >= ABS(x * MAX(REAL))) THEN	(* y/x would result in overflow/divide by zero trap *)
				IF y >= 0 THEN phi := 0.5*Math.pi
				ELSE phi := 1.5*Math.pi
				END
			ELSIF x > 0 THEN	(* 1st or 4th quadrant *)
				phi := Math.arctan(y/x)
			ELSIF x < 0 THEN	(* 2nd or 3rd quadrant *)
				phi := Math.arctan(y/x) + Math.pi
			END;
			RETURN phi * (180/Math.pi)
		END angle;
		
	BEGIN
		IF ABS(dy2) <= eps THEN
			tmp := dx2; dx2 := -dx1; dy2 := -dy1;
			dx1 := tmp; dy1 := 0
		END;
		mat := GfxMatrix.Identity;
		IF ABS(dy1) > eps THEN
			tmp := Math.sqrt(dx1 * dx1 + dy1 * dy1);
			GfxMatrix.Rotate(GfxMatrix.Identity, -dy1/tmp, dx1/tmp, mat);
			GfxMatrix.ApplyToVector(mat, dx1, dy1, dx1, dy1);
			GfxMatrix.ApplyToVector(mat, dx2, dy2, dx2, dy2)
		END;
		IF ABS(dx2) > eps THEN
			GfxMatrix.Init(m, 1, -dx2/dy2, 0, 1, 0, 0);
			GfxMatrix.Concat(m, mat, mat)
		END;
		IF ABS(ABS(dx1) - ABS(dy2)) > eps THEN
			GfxMatrix.Scale(mat, 1, ABS(dy2/dx1), mat)
		END;
		IF ~GfxMatrix.Equal(mat, GfxMatrix.Identity) THEN
			GfxMatrix.ApplyToVector(mat, sx, sy, sx, sy);
			GfxMatrix.ApplyToVector(mat, ex, ey, ex, ey);
			GfxMatrix.Translate(GfxMatrix.Identity, x0, y0, m);
			GfxMatrix.Concat(mat, m, m);
			GfxMatrix.Translate(m, -x0, -y0, mat);
			Str(r, "ctm "); Matrix(r, mat); Str(r, " cc "); Ln(r);
		END;
		Point(r, x0, y0); Blank(r); Real(r, dx1); Blank(r);
		IF (sx = ex) & (sy = ey) THEN
			Str(r, "0 360 arc")
		ELSE
			Real(r, angle(sx, sy)); Blank(r); Real(r, angle(ex, ey)); Str(r, " arc");
			IF dx1 * dy2 < 0 THEN Ch(r, "n") END	(* clockwise arc *)
		END;
		IF ~GfxMatrix.Equal(mat, GfxMatrix.Identity) THEN
			Str(r, " sm")
		END;
		Ln(r)
	END Arc;
	
	PROCEDURE Path (VAR r: Files.Rider; path: GfxPaths.Path);
		VAR s: GfxPaths.Scanner; sx, sy, dx, dy, x, y: REAL;
	BEGIN
		GfxPaths.Open(s, path, 0);
		WHILE s.elem = GfxPaths.Enter DO
			sx := s.x; sy := s.y; dx := s.dx; dy := s.dy;
			Point(r, sx, sy); Str(r, " mt"); Ln(r);
			x := sx; y := sy;
			GfxPaths.Scan(s);
			WHILE s.elem # GfxPaths.Exit DO
				CASE s.elem OF
				| GfxPaths.Line: Point(r, s.x, s.y); Str(r, " ln"); Ln(r)
				| GfxPaths.Arc: Arc(r, x - s.x0, y - s.y0, s.x - s.x0, s.y - s.y0, s.x0, s.y0, s.x1 - s.x0, s.y1 - s.y0, s.x2 - s.x0, s.y2 - s.y0)
				| GfxPaths.Bezier: Point(r, s.x1, s.y1); Blank(r); Point(r, s.x2, s.y2); Blank(r); Point(r, s.x, s.y); Str(r, " ct"); Ln(r)
				END;
				x := s.x; y := s.y;
				GfxPaths.Scan(s)
			END;
			IF (x = sx) & (y = sy) & ((dx # 0) OR (dy # 0)) & ((s.dx # 0) OR (s.dy # 0)) THEN
				Str(r, "cp"); Ln(r)
			END;
			GfxPaths.Scan(s)
		END
	END Path;
	
	PROCEDURE Rect (VAR r: Files.Rider; lx, ly, rx, uy: REAL);
	BEGIN
		Point(r, lx, ly); Str(r, " mt ");
		Point(r, rx, ly); Str(r, " ln ");
		Point(r, rx, uy); Str(r, " ln ");
		Point(r, lx, uy); Str(r, " ln cp")
	END Rect;
	
	
	(*--- Run-Length Encoded Output ---*)
	
	PROCEDURE RLEStart (VAR d: RLEData);
	BEGIN
		d.len := 0; d.n := 0
	END RLEStart;
	
	PROCEDURE RLECh (VAR r: Files.Rider; x: CHAR; VAR d: RLEData);
		VAR len, i: LONGINT;
	BEGIN
		IF d.len = 0 THEN
			d.buf[0] := x; d.len := 1
		ELSIF d.len = 1 THEN
			IF x = d.buf[0] THEN
				d.len := -2
			ELSE
				d.buf[1] := x; d.len := 2
			END
		ELSIF d.len > 1 THEN
			len := 0;
			IF (x = d.buf[d.len-1]) & (x = d.buf[d.len-2]) THEN	(* three consecutive bytes equal => switch mode *)
				len := d.len-3;
				d.len := -3
			ELSE
				d.buf[d.len] := x; INC(d.len);
				IF d.len = RLEBufLen THEN
					len := RLEBufLen-1;
					d.len := 0
				END
			END;
			IF len > 0 THEN
				IF d.n = 36 THEN Ln(r); d.n := 0 END;
				Hex(r, len DIV 16); Hex(r, len MOD 16); INC(d.n);
				FOR i := 0 TO len DO
					IF d.n = 36 THEN Ln(r); d.n := 0 END;
					Hex(r, ORD(d.buf[i]) DIV 16); Hex(r, ORD(d.buf[i]) MOD 16); INC(d.n)
				END;
				d.buf[0] := x
			END
		ELSE
			IF (x = d.buf[0]) & (-d.len < RLEBufLen) THEN
				DEC(d.len)
			ELSE
				IF d.n = 36 THEN Ln(r); d.n := 0 END;
				Hex(r, (257 + d.len) DIV 16); Hex(r, (257 + d.len) MOD 16); INC(d.n);
				IF d.n = 36 THEN Ln(r); d.n := 0 END;
				Hex(r, ORD(d.buf[0]) DIV 16); Hex(r, ORD(d.buf[0]) MOD 16); INC(d.n);
				d.buf[0] := x; d.len := 1
			END
		END
	END RLECh;
	
	PROCEDURE RLEStop (VAR r: Files.Rider; VAR d: RLEData);
		VAR len, i: LONGINT;
	BEGIN
		IF d.len > 0 THEN
			len := d.len-1;
			IF d.n = 36 THEN Ln(r) END;
			Hex(r, len DIV 16); Hex(r, len MOD 16); INC(d.n);
			FOR i := 0 TO len DO
				IF d.n = 36 THEN Ln(r); d.n := 0 END;
				Hex(r, ORD(d.buf[i]) DIV 16); Hex(r, ORD(d.buf[i]) MOD 16); INC(d.n)
			END
		ELSIF d.len < 0 THEN
			IF d.n = 36 THEN Ln(r); d.n := 0 END;
			Hex(r, (257 + d.len) DIV 16); Hex(r, (257 + d.len) MOD 16); INC(d.n);
			IF d.n = 36 THEN Ln(r); d.n := 0 END;
			Hex(r, ORD(d.buf[0]) DIV 16); Hex(r, ORD(d.buf[0]) MOD 16); INC(d.n)
		ELSE
			IF d.n = 36 THEN Ln(r); d.n := 0 END;
			Str(r, "80"); INC(d.n)
		END;
		IF d.n > 0 THEN Ln(r) END
	END RLEStop;
	
	
	(*--- Maps ---*)
	
	PROCEDURE Grey (r, g, b: INTEGER): INTEGER;
	BEGIN
		RETURN (3*r + 6*g + b + 5) DIV 10
	END Grey;
	
	PROCEDURE PatternNo (psc: Context; pattern: Gfx.Pattern): INTEGER;
		VAR pat: Pattern; no: INTEGER;
	BEGIN
		pat := psc.patterns; no := 0;
		WHILE (pat # NIL) & (pat # pattern) DO
			pat := pat.next; INC(no)
		END;
		IF pat = NIL THEN no := -1 END;
		RETURN no
	END PatternNo;
	
	PROCEDURE MaskMap (VAR r: Files.Rider; map: GfxMaps.Map);
		VAR y, x, w, i, n: INTEGER; buf: ARRAY 36 OF CHAR;
	BEGIN
		y := 0;
		WHILE y < map.height DO
			x := 0;
			WHILE x < map.width DO
				w := 8*36;
				IF x + w > map.width THEN w := map.width - x END;
				GfxMaps.GetPixels(map, x, y, w, GfxMaps.A1, buf, GfxMaps.SrcCopy);
				i := 0; n := (w+7) DIV 8;
				WHILE i < n DO
					Hex(r, ORD(buf[i]) DIV 10H); Hex(r, ORD(buf[i]) MOD 10H);
					INC(i)
				END;
				INC(x, w); Ln(r)
			END;
			INC(y)
		END
	END MaskMap;
	
	PROCEDURE Palette256 (VAR r: Files.Rider; pal: GfxMaps.Palette);
		VAR i, j: LONGINT;
	BEGIN
		Ln(r); Str(r, " <"); i := 0; j := 0;
		WHILE i < 256 DO
			IF j = 8 THEN
				Ln(r); Str(r, "  "); j := 0
			END;
			HexCol(r, pal.col[i]);
			INC(i); INC(j)
		END;
		Str(r, " >")
	END Palette256;
	
	PROCEDURE DefMap (psc: Context; map: GfxMaps.Map);
		VAR y, x, byte: INTEGER; pix: GfxMaps.Pixel; fmt: GfxMaps.Format;
	BEGIN
		IF ~psc.level2 THEN Ch(psc.out, "{") END;
		Ch(psc.out, "<");
		IF map.fmt.components = {GfxMaps.Alpha} THEN
			MaskMap(psc.out, map)
		ELSIF ~psc.level2 THEN
			y := 0;
			WHILE y < map.height DO
				x := 0;
				WHILE x < map.width DO
					GfxMaps.Get(map, x, y, pix, GfxMaps.SrcCopy);
					byte := Grey(ORD(pix[R]), ORD(pix[G]), ORD(pix[B]));
					Hex(psc.out, byte DIV 10H); Hex(psc.out, byte MOD 10H);
					INC(x)
				END;
				INC(y); Ln(psc.out)
			END
		ELSIF map.fmt.components = {GfxMaps.Index} THEN
			fmt := GfxMaps.I8; fmt.pal := map.fmt.pal;
			y := 0;
			WHILE y < map.height DO
				x := 0;
				WHILE x < map.width DO
					GfxMaps.GetPixels(map, x, y, 1, fmt, pix, GfxMaps.SrcCopy);
					Hex(psc.out, ORD(pix[0]) DIV 10H); Hex(psc.out, ORD(pix[0]) MOD 10H);
					INC(x)
				END;
				INC(y); Ln(psc.out)
			END
		ELSE
			y := 0;
			WHILE y < map.height DO
				x := 0;
				WHILE x < map.width DO
					GfxMaps.Get(map, x, y, pix, GfxMaps.SrcCopy);
					byte := ORD(pix[R]); Hex(psc.out, byte DIV 10H); Hex(psc.out, byte MOD 10H);
					byte := ORD(pix[G]); Hex(psc.out, byte DIV 10H); Hex(psc.out, byte MOD 10H);
					byte := ORD(pix[B]); Hex(psc.out, byte DIV 10H); Hex(psc.out, byte MOD 10H);
					INC(x)
				END;
				INC(y); Ln(psc.out)
			END
		END;
		Ch(psc.out, ">");
		IF psc.level2 THEN Str(psc.out, " cvx") ELSE Ch(psc.out, "}") END;
		Ln(psc.out)
	END DefMap;
	
	PROCEDURE UseMap (psc: Context; map: GfxMaps.Map; no: INTEGER);
		VAR rle: RLEData; y, x: INTEGER; pix: GfxMaps.Pixel; fmt: GfxMaps.Format;
	BEGIN
		Int(psc.out, map.width); Blank(psc.out); Int(psc.out, map.height);
		IF map.fmt.components = {GfxMaps.Alpha} THEN
			IF no >= 0 THEN
				Str(psc.out, " true matrix Images "); Int(psc.out, no); Str(psc.out, " get imask")
			ELSE
				Str(psc.out, " true matrix {"); Int(psc.out, 2*((map.width+7) DIV 8)); Str(psc.out, " rh} imask"); Ln(psc.out);
				MaskMap(psc.out, map); Ln(psc.out)
			END
		ELSIF ~psc.level2 THEN
			IF no >= 0 THEN
				Str(psc.out, " Images "); Int(psc.out, no); Str(psc.out, " get img")
			ELSE
				Str(psc.out, " /rld load img"); Ln(psc.out);
				RLEStart(rle);
				y := 0;
				WHILE y < map.height DO
					x := 0;
					WHILE x < map.width DO
						GfxMaps.Get(map, x, y, pix, GfxMaps.SrcCopy);
						RLECh(psc.out, CHR(Grey(ORD(pix[R]), ORD(pix[G]), ORD(pix[B]))), rle);
						INC(x)
					END;
					INC(y)
				END;
				RLEStop(psc.out, rle); Ln(psc.out)
			END
		ELSIF map.fmt.components = {GfxMaps.Index} THEN
			Palette256(psc.out, map.fmt.pal);
			IF no >= 0 THEN
				Str(psc.out, " Images "); Int(psc.out, no); Str(psc.out, " get pict")
			ELSE
				Str(psc.out, " rlf pict"); Ln(psc.out);
				RLEStart(rle);
				fmt := GfxMaps.I8; fmt.pal := map.fmt.pal;
				y := 0;
				WHILE y < map.height DO
					x := 0;
					WHILE x < map.width DO
						GfxMaps.GetPixels(map, x, y, 1, fmt, pix, GfxMaps.SrcCopy);
						RLECh(psc.out, pix[0], rle);
						INC(x)
					END;
					INC(y)
				END;
				RLEStop(psc.out, rle); Ln(psc.out)
			END
		ELSE
			IF no >= 0 THEN
				Str(psc.out, " Images "); Int(psc.out, no); Str(psc.out, " get colimg")
			ELSE
				Str(psc.out, " rlf colimg"); Ln(psc.out);
				RLEStart(rle);
				y := 0;
				WHILE y < map.height DO
					x := 0;
					WHILE x < map.width DO
						GfxMaps.Get(map, x, y, pix, GfxMaps.SrcCopy);
						RLECh(psc.out, pix[R], rle); RLECh(psc.out, pix[G], rle); RLECh(psc.out, pix[B], rle);
						INC(x)
					END;
					INC(y)
				END;
				RLEStop(psc.out, rle); Ln(psc.out)
			END
		END;
		Ln(psc.out)
	END UseMap;
	
	PROCEDURE RegisterMap (psc: Context; VAR map: GfxMaps.Map; VAR no: INTEGER);
		VAR img: Image; copy: GfxMaps.Map;
		
		PROCEDURE same (m, n: GfxMaps.Map): BOOLEAN;
			VAR y, x, len, l: INTEGER; mbuf, nbuf: ARRAY 4*128 OF CHAR;
		BEGIN
			IF (m.width # n.width) OR (m.height # n.height) THEN
				RETURN FALSE
			END;
			IF (m.fmt.bpp # n.fmt.bpp) OR (m.fmt.components # n.fmt.components) OR (m.fmt.unpack # n.fmt.unpack) THEN
				RETURN FALSE	(* trivial reject case *)
			END;
			y := 0;
			WHILE y < m.height DO
				x := 0;
				WHILE x < m.width DO
					IF x + 128 > m.width THEN len := m.width - x ELSE len := 128 END;
					GfxMaps.GetPixels(m, x, y, len, GfxMaps.PixelFormat, mbuf, GfxMaps.SrcCopy);
					GfxMaps.GetPixels(n, x, y, len, GfxMaps.PixelFormat, nbuf, GfxMaps.SrcCopy);
					l := 0;
					WHILE l < 4*len DO
						IF mbuf[l] # nbuf[l] THEN
							RETURN FALSE
						END;
						INC(l)
					END;
					INC(x, len)
				END;
				INC(y)
			END;
			RETURN TRUE
		END same;
		
	BEGIN
		IF map.width * map.bpr < 8000H THEN	(* predefined images must fit in PostScript string *)
			img := psc.images; no := 0;
			IF img = NIL THEN
				NEW(img); psc.images := img;
				NEW(img.map); GfxMaps.Create(img.map, map.width, map.height, map.fmt);
				GfxMaps.Copy(map, img.map, 0, 0, map.width, map.height, 0, 0, GfxMaps.SrcCopy)
			ELSIF ~same(img.map, map) THEN
				INC(no);
				WHILE (img.next # NIL) & ~same(img.next.map, map) DO
					img := img.next; INC(no)
				END;
				IF img.next = NIL THEN
					NEW(img.next); img := img.next;
					NEW(img.map); GfxMaps.Create(img.map, map.width, map.height, map.fmt);
					GfxMaps.Copy(map, img.map, 0, 0, map.width, map.height, 0, 0, GfxMaps.SrcCopy)
				END
			END;
			map := img.map
		ELSE
			no := -1;
			NEW(copy); GfxMaps.Create(copy, map.width, map.height, map.fmt);
			GfxMaps.Copy(map, copy, 0, 0, map.width, map.height, 0, 0, GfxMaps.SrcCopy);
			map := copy
		END
	END RegisterMap;
	
	
	(*--- Fonts ---*)
	
	PROCEDURE ECh (VAR r: Files.Rider; x: CHAR; VAR ekey, epos: LONGINT);
		CONST c1 = 52845; c2 = 22719;
		VAR c: CHAR;
	BEGIN
		c := BIT.CXOR(x, CHR(ASH(ekey, -8)));
		ekey := ((ORD(c) + ekey) * c1 + c2) MOD 65536;
		Hex(r, ORD(c) DIV 16); Hex(r, ORD(c) MOD 16);
		INC(epos);
		IF epos = 32 THEN
			Ln(r); epos := 0
		END
	END ECh;
	
	PROCEDURE ELn (VAR r: Files.Rider; VAR ekey, epos: LONGINT);
	BEGIN
		ECh(r, LF, ekey, epos)
	END ELn;
	
	PROCEDURE EStr (VAR r: Files.Rider; s: ARRAY OF CHAR; VAR ekey, epos: LONGINT);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE s[i] # 0X DO
			ECh(r, s[i], ekey, epos);
			INC(i)
		END
	END EStr;
	
	PROCEDURE EECh (VAR r: Files.Rider; x: CHAR; VAR eekey, ekey, epos: LONGINT);
		CONST c1 = 52845; c2 = 22719;
		VAR c: CHAR;
	BEGIN
		c := BIT.CXOR(x, CHR(ASH(eekey, -8)));
		eekey := ((ORD(c) + eekey) * c1 + c2) MOD 65536;
		ECh(r, c, ekey, epos)
	END EECh;
	
	PROCEDURE GetName (ch: LONGINT; VAR s: ARRAY OF CHAR);
	BEGIN
		CASE ch OF
		| 32: COPY("space", s)	| 33: COPY("exclam", s)	| 34: COPY("quotedbl", s)	| 35: COPY("numbersign", s)
		| 36: COPY("dollar", s)	| 37: COPY("percent", s)	| 38: COPY("ampersand", s)	| 39: COPY("quotesingle", s)
		| 40: COPY("parenleft", s)	| 41: COPY("parenright", s)	| 42: COPY("asterisk", s)	| 43: COPY("plus", s)
		| 44: COPY("comma", s)	| 45: COPY("minus", s)	| 46: COPY("period", s)	| 47: COPY("slash", s)
		| 48: COPY("zero", s)	| 49: COPY("one", s)	| 50: COPY("two", s)	| 51: COPY("three", s)	| 52: COPY("four", s)
		| 53: COPY("five", s)	| 54: COPY("six", s)	| 55: COPY("seven", s)	| 56: COPY("eight", s)
		| 57: COPY("nine", s)	| 58: COPY("colon", s)	| 59: COPY("semicolon", s)	| 60: COPY("less", s)
		| 61: COPY("equal", s)	| 62: COPY("greater", s)	| 63: COPY("question", s)	| 64: COPY("at", s)
		| 65..90: s[0] := CHR(ch); s[1] := 0X
		| 91: COPY("bracketleft", s)	| 92:  COPY("backslash", s)	| 93: COPY("bracketright", s)	| 94: COPY("arrowup", s)
		| 95: COPY("underscore", s) 	| 96: COPY("grave", s)
		| 97..122: s[0] := CHR(ch); s[1] := 0X
		| 123: COPY("braceleft", s)	| 124: COPY("bar", s)	| 125: COPY("braceright", s)	| 126: COPY("tilde", s)
		| 128: COPY("Adieresis", s)	| 129: COPY("Odieresis", s)	| 130: COPY("Udieresis", s)	| 131: COPY("adieresis", s)
		| 132: COPY("odieresis", s)	| 133: COPY("udieresis", s)	| 134: COPY("acircumflex", s)	| 135: COPY("ecircumflex", s)
		| 136: COPY("icircumflex", s)	| 137: COPY("ocircumflex", s)	| 138: COPY("ucircumflex", s)	| 139: COPY("agrave", s)
		| 140: COPY("egrave", s)	| 141: COPY("igrave", s)	| 142: COPY("ograve", s)	| 143: COPY("ugrave", s)
		| 144: COPY("eacute", s)	| 145: COPY("edieresis", s)	| 146: COPY("idieresis", s)	| 147: COPY("ccedilla", s)
		| 148: COPY("aacute", s)	| 149: COPY("ntilde", s)	| 150: COPY("germandbls", s)	| 155: COPY("endash", s)
		| 159: COPY("hyphen", s)	| 171: COPY("germandbls", s)
		ELSE COPY(".notdef", s)
		END
	END GetName;
	
	PROCEDURE Private (VAR r: Files.Rider; VAR ekey, epos: LONGINT);
	BEGIN
		EStr(r, "dup /Private 8 dict dup begin", ekey, epos); ELn(r, ekey, epos);
		EStr(r, "/RD {string currentfile exch readstring pop} executeonly def", ekey, epos); ELn(r, ekey, epos);
		EStr(r, "/ND {noaccess def} executeonly def", ekey, epos); ELn(r, ekey, epos);
		EStr(r, "/NP {noaccess put} executeonly def", ekey, epos); ELn(r, ekey, epos);
		EStr(r, "/BlueValues [] def", ekey, epos); ELn(r, ekey, epos);
		EStr(r, "/MinFeature {16 16} def", ekey, epos); ELn(r, ekey, epos);
		EStr(r, "/password 5839 def", ekey, epos); ELn(r, ekey, epos);
		EStr(r, "/OtherSubrs", ekey, epos); ELn(r, ekey, epos);
		EStr(r, "[ {} {} {} ] ND", ekey, epos); ELn(r, ekey, epos)
	END Private;
	
	PROCEDURE Char (VAR r: Files.Rider; font: GfxFonts.Font; ch: LONGINT; VAR ekey, epos: LONGINT);
		CONST
			sqrt2 = 1.41421356;
		
		VAR
			len, cx, cy, ix, iy, sx, sy, i, eekey: LONGINT; dx, dy, cr, sr, rad, cos, sin, cdx, sdx, cdy, sdy: REAL;
			s: GfxPaths.Scanner; closed: BOOLEAN; name: ARRAY 32 OF CHAR; cmd: ARRAY 2048 OF CHAR;
		
		PROCEDURE put (x: LONGINT);
		BEGIN
			cmd[len] := CHR(x); INC(len)
		END put;
		
		PROCEDURE num (x: LONGINT);
		BEGIN
			IF (x >= -107) & (x <= 107) THEN
				put(x + 139)
			ELSIF (x >= 108) & (x <= 1131) THEN
				DEC(x, 108);
				put(247 + x DIV 256);
				put(x MOD 256)
			ELSIF (x >= -1131) & (x <= -108) THEN
				x := -x - 108;
				put(251 + x DIV 256);
				put(x MOD 256)
			ELSE
				put(255);
				put(ASH(x, -24) MOD 256);
				put(ASH(x, -16) MOD 256);
				put(ASH(x, -8) MOD 256);
				put(x MOD 256)
			END
		END num;
		
		PROCEDURE bezier (x1, y1, x2, y2, x, y: REAL);
		BEGIN
			IF (ABS(x1 - cx) < 0.5) & (ABS(y2 - y) < 0.5) THEN
				iy := ENTIER(y1 + 0.5); num(iy - cy); cy := iy;
				ix := ENTIER(x2 + 0.5); iy := ENTIER(y2 + 0.5); num(ix - cx); num(iy - cy); cx := ix; cy := iy;
				ix := ENTIER(x + 0.5); num(ix - cx); put(30);	(* vhcurveto *)
				cx := ix
			ELSIF (ABS(y1 - cy) < 0.5) & (ABS(x2 - x) < 0.5) THEN
				ix := ENTIER(x1 + 0.5); num(ix - cx); cx := ix;
				ix := ENTIER(x2 + 0.5); iy := ENTIER(y2 + 0.5); num(ix - cx); num(iy - cy); cx := ix; cy := iy;
				iy := ENTIER(y + 0.5); num(iy - cy); put(31);	(* hvcurveto *)
				cy := iy
			ELSE
				ix := ENTIER(x1 + 0.5); iy := ENTIER(y1 + 0.5); num(ix - cx); num(iy - cy); cx := ix; cy := iy;
				ix := ENTIER(x2 + 0.5); iy := ENTIER(y2 + 0.5); num(ix - cx); num(iy - cy); cx := ix; cy := iy;
				ix := ENTIER(x + 0.5); iy := ENTIER(y + 0.5); num(ix - cx); num(iy - cy); put(8);	(* rrcurveto *)
				cx := ix; cy := iy
			END
		END bezier;
		
	BEGIN
		len := 0;
		GfxFonts.GetWidth(font, CHR(ch), dx, dy);
		GfxFonts.GetOutline(font, CHR(ch), 0, 0, TmpPath);
		num(0); num(ENTIER(dx + 0.5)); put(13);	(* hsbw *)
		cx := 0; cy := 0;
		GfxPaths.Open(s, TmpPath, 0);
		WHILE s.elem # GfxPaths.Stop DO
			CASE s.elem OF
			| GfxPaths.Enter:
				ix := ENTIER(s.x + 0.5); iy := ENTIER(s.y + 0.5);
				IF ix = cx THEN num(iy - cy); put(4)	(* vmoveto *)
				ELSIF iy = cy THEN num(ix - cx); put(22)	(* hmoveto *)
				ELSE num(ix - cx); num(iy - cy); put(21)	(* rmoveto *)
				END;
				closed := (s.dx # 0) OR (s.dy # 0); sx := ix; sy := iy;
				cx := ix; cy := iy
			| GfxPaths.Line:
				ix := ENTIER(s.x + 0.5); iy := ENTIER(s.y + 0.5);
				IF ix = cx THEN num(iy - cy); put(7)	(* vlineto *)
				ELSIF iy = cy THEN num(ix - cx); put(6)	(* hlineto *)
				ELSE num(ix - cx); num(iy - cy); put(5)	(* rlineto *)
				END;
				cx := ix; cy := iy
			| GfxPaths.Arc:
				(* ooohh...shit! let's pray only MetaFonts return these in case of full circles (from closed spline with n=2) *)
				cr := s.x1 - s.x0; sr := s.y1 - s.y0;
				rad := Math.sqrt(cr * cr + sr * sr);
				cos := cr/rad; sin := sr/rad;
				dx := rad * (8/6 * sqrt2 - 15/12); dy := rad * (13/12);
				cdx := cos * dx; sdx := sin * dx; cdy := cos * dy; sdy := sin * dy;
				bezier(s.x0 + cdx + sdy, s.y0 + sdx - cdy, s.x0 + cdy + sdx, s.y0 + sdy - cdx, s.x0 + sr, s.y0 + cr);
				bezier(s.x0 - cdy + sdx, s.y0 - sdy - cdx, s.x0 - cdx + sdy, s.y0 - sdx - cdy, s.x0 - cr, s.y0 - sr);
				bezier(s.x0 - cdx - sdy, s.y0 - sdx + cdy, s.x0 - cdy - sdx, s.y0 - sdy + cdx, s.x0 - sr, s.y0 - cr);
				bezier(s.x0 + cdy - sdx, s.y0 + sdy + cdx, s.x0 + cdx - sdy, s.y0 + sdx + cdy, s.x0 + cr, s.y0 + sr)
			| GfxPaths.Bezier:
				bezier(s.x1, s.y1, s.x2, s.y2, s.x, s.y)
			| GfxPaths.Exit:
				IF (cx = sx) & (cy = sy) & closed & ((s.dx # 0) OR (s.dy # 0)) THEN
					put(9)	(* closepath *)
				END
			END;
			GfxPaths.Scan(s)
		END;
		put(14);	(* endchar *)
		GetName(ch, name);
		ECh(r, "/", ekey, epos); EStr(r, name, ekey, epos); ECh(r, " ", ekey, epos);
		Strings.IntToStr(len+4, name); EStr(r, name, ekey, epos); EStr(r, " RD ", ekey, epos);
		eekey := 4330;
		EECh(r, 0X, eekey, ekey, epos); EECh(r, 0X, eekey, ekey, epos);
		EECh(r, 0X, eekey, ekey, epos); EECh(r, 0X, eekey, ekey, epos);
		FOR i := 0 TO len-1 DO EECh(r, cmd[i], eekey, ekey, epos) END;
		EStr(r, " ND", ekey, epos); ELn(r, ekey, epos)
	END Char;
	
	PROCEDURE CharStrings (VAR r: Files.Rider; font: GfxFonts.Font; VAR ekey, epos: LONGINT);
		VAR ch, n: LONGINT; s: ARRAY 32 OF CHAR; dx, dy: REAL;
	BEGIN
		ch := 0; n := 1;
		WHILE ch < 256 DO
			GetName(ch, s);
			IF s # ".notdef" THEN
				GfxFonts.GetWidth(font, CHR(ch), dx, dy);
				IF (dx # 0) OR (dy # 0) THEN
					INC(n)
				END
			END;
			INC(ch)
		END;
		EStr(r, "2 index /CharStrings ", ekey, epos);
		IF n >= 100 THEN ECh(r, CHR(ORD("0") + n DIV 100), ekey, epos) END;
		IF n >= 10 THEN ECh(r, CHR(ORD("0") + n MOD 100 DIV 10), ekey, epos) END;
		ECh(r, CHR(ORD("0") + n MOD 10), ekey, epos);
		EStr(r, " dict dup begin", ekey, epos); ELn(r, ekey, epos);
		Char(r, font, 0, ekey, epos);
		ch := 1;
		WHILE ch < 256 DO
			GetName(ch, s);
			IF s # ".notdef" THEN
				GfxFonts.GetWidth(font, CHR(ch), dx, dy);
				IF (dx # 0) OR (dy # 0) THEN
					Char(r, font, ch, ekey, epos)
				END
			END;
			INC(ch)
		END;
		EStr(r, "end", ekey, epos); ELn(r, ekey, epos)
	END CharStrings;
	
	(** write type-1 font to rider **)
	PROCEDURE Type1* (VAR r: Files.Rider; VAR name: ARRAY OF CHAR);
		VAR scale: REAL; m: GfxMatrix.Matrix; font: GfxFonts.Font; fam, style: ARRAY 32 OF CHAR; i, j, ekey, epos: LONGINT;
	BEGIN
		scale := 1000 * PSDPI/ScreenDPI;	(* 1000 Postscript points *)
		GfxMatrix.Init(m, scale, 0, 0, scale, 0, 0);
		font := GfxFonts.Open(name, 1, m);
		IF font # NIL THEN
			Str(r, "11 dict begin"); Ln(r);
			Str(r, "/FontInfo 8 dict dup begin"); Ln(r);
			Str(r, "/version (001.000) readonly def"); Ln(r);
			Str(r, "/FullName ("); Str(r, font.name); Str(r, ") readonly def"); Ln(r);
			COPY(font.name, fam); style := ""; i := 0;
			WHILE (fam[i] # 0X) & (fam[i] # "-") DO INC(i) END;
			IF fam[i] = "-" THEN
				fam[i] := 0X; INC(i); j := 0;
				WHILE fam[i] # 0X DO
					style[j] := fam[i]; INC(i); INC(j)
				END;
				style[j] := 0X
			ELSE
				fam[i] := 0X
			END;
			Str(r, "/FamilyName ("); Str(r, fam); Str(r, ") readonly def"); Ln(r);
			Str(r, "/Weight (");
			IF style = "" THEN Str(r, "Roman") ELSE Str(r, style) END;
			Str(r, ") readonly def"); Ln(r);
			IF style = "Italic" THEN Str(r, "/ItalicAngle 30 def") ELSE Str(r, "/ItalicAngle 0 def") END;
			Ln(r);
			Str(r, "/isFixedPitch false def"); Ln(r);
			Str(r, "/UnderlinePosition -100 def"); Ln(r);
			Str(r, "/UnderlineThickness 50 def"); Ln(r);
			Str(r, "end readonly def"); Ln(r);
			Str(r, "/FontName /"); Str(r, font.name); Str(r, " def"); Ln(r);
			Str(r, "/PaintType 0 def"); Ln(r);
			Str(r, "/FontType 1 def"); Ln(r);
			Str(r, "/FontMatrix [0.001 0 0 0.001 0 0] readonly def"); Ln(r);
			Str(r, "/Encoding OberonEncoding def"); Ln(r);
			Str(r, "/FontBBox [");
			Int(r, font.xmin); Ch(r, " "); Int(r, font.ymin); Ch(r, " ");
			Int(r, font.xmax); Ch(r, " "); Int(r, font.ymax);
			Str(r, "] readonly def"); Ln(r);
			Str(r, "currentdict end"); Ln(r);
			Str(r, "currentfile eexec"); Ln(r);
			ekey := 55665; epos := 0;
			ECh(r, 0X, ekey, epos); ECh(r, 0X, ekey, epos); ECh(r, 0X, ekey, epos); ECh(r, 0X, ekey, epos);
			Private(r, ekey, epos);
			CharStrings(r, font, ekey, epos);
			EStr(r, "end", ekey, epos); ELn(r, ekey, epos);
			EStr(r, "readonly put", ekey, epos); ELn(r, ekey, epos);
			EStr(r, "noaccess put", ekey, epos); ELn(r, ekey, epos);
			EStr(r, "dup /FontName get exch definefont pop", ekey, epos); ELn(r, ekey, epos);
			EStr(r, "mark currentfile closefile", ekey, epos); ELn(r, ekey, epos);
			Ln(r);
			FOR i := 0 TO 511 DO
				Ch(r, "0");
				IF i MOD 64 = 63 THEN Ln(r) END
			END;
			Str(r, "cleartomark"); Ln(r)
		END
	END Type1;
	
	PROCEDURE Type3 (VAR r: Files.Rider; VAR t3: T3Font; scale: REAL);
		VAR font: GfxFonts.Font; used, i, j: LONGINT; bx, by, dx, dy: REAL; map: GfxMaps.Map; name: GfxFonts.FontName;
	BEGIN
		font := t3.font;
		Str(r, "8 dict dup begin"); Ln(r);
		Str(r, "/FontType 3 def"); Ln(r);
		Str(r, "/FontMatrix ["); Real(r, scale); Str(r, " 0 0 "); Real(r, scale); Str(r, " 0 0] def"); Ln(r);
		Str(r, "/Encoding OberonEncoding def"); Ln(r);
		Str(r, "/FontBBox ["); 
		Int(r, font.xmin); Ch(r, " "); Int(r, font.ymin); Ch(r, " ");
		Int(r, font.xmax); Ch(r, " "); Int(r, font.ymax);
		Str(r, "] def"); Ln(r);
		used := 0;
		FOR i := 0 TO 7 DO
			FOR j := 0 TO 31 DO
				IF j IN t3.used[i] THEN INC(used) END
			END
		END;
		Str(r, "/CharData "); Int(r, used+1); Str(r, " dict dup begin"); Ln(r);
		GfxFonts.GetMap(font, 0X, bx, by, dx, dy, map);
		IF (dx = 0) & (dy = 0) THEN
			GfxFonts.GetMap(font, " ", bx, by, dx, dy, map);
			Str(r, "/.notdef ["); Int(r, ENTIER(dx)); Ch(r, " "); Int(r, ENTIER(dy)); Str(r, " 0] def"); Ln(r)
		ELSIF map = NIL THEN
			Str(r, "/.notdef ["); Int(r, ENTIER(dx)); Ch(r, " "); Int(r, ENTIER(dy)); Str(r, " 0] def"); Ln(r)
		ELSE
			Str(r, "/.notdef [{<"); MaskMap(r, map); Str(r, ">} ");
			Int(r, ENTIER(dx)); Ch(r, " "); Int(r, ENTIER(dy)); Ch(r, " ");
			Int(r, ENTIER(bx)); Ch(r, " "); Int(r, ENTIER(by)); Ch(r, " ");
			Int(r, map.width); Ch(r, " "); Int(r, map.height); Str(r, "] def"); Ln(r)
		END;
		FOR i := 0 TO 255 DO
			IF (i MOD 32) IN t3.used[i DIV 32] THEN
				GetName(i, name);
				IF name # ".notdef" THEN
					Ch(r, "/"); Str(r, name); Str(r, " [");
					GfxFonts.GetMap(font, CHR(i), bx, by, dx, dy, map);
					IF map = NIL THEN
						Int(r, ENTIER(dx)); Ch(r, " "); Int(r, ENTIER(dy)); Str(r, " 0] def"); Ln(r)
					ELSE
						Str(r, "{<"); MaskMap(r, map); Str(r, ">} ");
						Int(r, ENTIER(dx)); Ch(r, " "); Int(r, ENTIER(dy)); Ch(r, " ");
						Int(r, ENTIER(bx)); Ch(r, " "); Int(r, ENTIER(by)); Ch(r, " ");
						Int(r, map.width); Ch(r, " "); Int(r, map.height); Str(r, "] def"); Ln(r)
					END
				END
			END
		END;
		Str(r, "end readonly def"); Ln(r);
		Str(r, "/BuildGlyph {buildglyph} def"); Ln(r);
		Str(r, "/BuildChar {buildchar} def"); Ln(r);
		Str(r, "end"); Ln(r);
		Ch(r, "/"); Str(r, t3.name); Str(r, " exch definefont pop"); Ln(r)
	END Type3;
	
	PROCEDURE SelectFont (psc: Context; VAR name: ARRAY OF CHAR; VAR m: GfxMatrix.Matrix);
		CONST eps = 0.001;
	BEGIN
		Ch(psc.out, "/"); Str(psc.out, name);
		IF GfxMatrix.Equal(GfxMatrix.Identity, m) THEN
			Str(psc.out, " fsf")
		ELSIF GfxMatrix.Rotated(m) OR (ABS(m[2, 0]) > eps) OR (ABS(m[2, 1]) > eps) OR (ABS(m[0, 0] - m[1, 1]) > eps) THEN
			IF psc.level2 THEN Ch(psc.out, " ") ELSE Str(psc.out, " ff ") END;
			Matrix(psc.out, m);
			IF psc.level2 THEN Str(psc.out, " slf") ELSE Str(psc.out, " msf") END
		ELSE
			IF psc.level2 THEN Ch(psc.out, " ") ELSE Str(psc.out, " ff ") END;
			Real(psc.out, m[0, 0]);
			IF psc.level2 THEN Str(psc.out, " slf") ELSE Str(psc.out, " ssf") END
		END;
		Ln(psc.out);
		COPY(name, psc.fontname);
		psc.fontmat := m
	END SelectFont;
	
	PROCEDURE SetOutlineFont (psc: Context);
		VAR m: GfxMatrix.Matrix; font: GfxFonts.Font; t1: T1Font;
	BEGIN
		GfxMatrix.Init(m, PSDPI/ScreenDPI, 0, 0, PSDPI/ScreenDPI, 0, 0);
		font := GfxFonts.Open(psc.font.name, 1000, m);	(* 1000 Postscript points *)
		IF font = NIL THEN font := GfxFonts.Default END;
		GfxMatrix.Scale(psc.font.mat, psc.font.ptsize, psc.font.ptsize, m);
		IF (font.name # psc.fontname) OR ~GfxMatrix.Equal(m, psc.fontmat) THEN
			t1 := psc.t1fonts;
			WHILE (t1 # NIL) & (t1.name # font.name) DO t1 := t1.next END;
			IF t1 = NIL THEN
				NEW(t1); COPY(font.name, t1.name); t1.next := psc.t1fonts; psc.t1fonts := t1
			END;
			SelectFont(psc, font.name, m)
		END
	END SetOutlineFont;
	
	
	(*--- Postscript Prolog & Setup ---*)
	
	PROCEDURE Prolog (VAR r: Files.Rider);
		VAR text: Texts.Text; tr: Texts.Reader; ch: CHAR;
	BEGIN
		Str(r, "%%BeginProlog"); Ln(r);
		NEW(text);
		Texts.Open(text, PrologName);
		Texts.OpenReader(tr, text, 0);
		Texts.Read(tr, ch);
		WHILE ~tr.eot DO
			IF ch = "%" THEN	(* works only if no '%' is embedded in a string! *)
				Texts.Read(tr, ch);
				IF ch = "%" THEN	(* keep DSC *)
					Ch(r, ch)
				ELSE
					WHILE ~tr.eot & (ch # CR) DO
						Texts.Read(tr, ch)
					END
				END
			END;
			Ch(r, ch);
			IF ch = CR THEN Ch(r, LF) END;
			Texts.Read(tr, ch)
		END;
		Str(r, "%%EndProlog"); Ln(r)
	END Prolog;
	
	PROCEDURE Setup (psc: Context);
		VAR img: Image; pat: Pattern; n: LONGINT; map: GfxMaps.Map; t1: T1Font; t3: T3Font;
	BEGIN
		Str(psc.out, "%%BeginSetup"); Ln(psc.out);
		img := psc.images;
		IF img # NIL THEN
			Str(psc.out, "/Images ["); Ln(psc.out);
			REPEAT
				DefMap(psc, img.map);
				img := img.next
			UNTIL img = NIL;
			Str(psc.out, "] def"); Ln(psc.out)
		END;
		pat := psc.patterns;
		IF psc.level2 & (pat # NIL) THEN
			n := 0; REPEAT INC(n); pat := pat.next UNTIL pat = NIL;
			Str(psc.out, "/Patterns "); Int(psc.out, n); Str(psc.out, " array def"); Ln(psc.out);
			pat := psc.patterns; n := 0;
			REPEAT
				map := pat.map;
				Str(psc.out, "Patterns "); Int(psc.out, n); Str(psc.out, " <<"); Ln(psc.out);
				Str(psc.out, "  /PatternType 1"); Ln(psc.out);
				IF map.fmt.components = {GfxMaps.Alpha} THEN Str(psc.out, "  /PaintType 2"); Ln(psc.out)
				ELSE Str(psc.out, " /PaintType 1"); Ln(psc.out)
				END;
				Str(psc.out, "  /TilingType 1"); Ln(psc.out);
				Str(psc.out, "  /BBox [0 0 "); Int(psc.out, map.width); Blank(psc.out);
				Int(psc.out, map.height); Ch(psc.out, "]"); Ln(psc.out);
				Str(psc.out, "  /XStep "); Int(psc.out, map.width); Ln(psc.out);
				Str(psc.out, "  /YStep "); Int(psc.out, map.height); Ln(psc.out);
				Str(psc.out, "  /PaintProc {"); Ln(psc.out);
				IF pat.no >= 0 THEN
					IF (pat.px # 0) OR (pat.py # 0) THEN
						Str(psc.out, "    "); Point(psc.out, pat.px, pat.py); Str(psc.out, " translate"); Ln(psc.out)
					END;
					Str(psc.out, "    pop ");
					UseMap(psc, map, pat.no)
				ELSE
					Str(psc.out, "    pop 0 0 "); Int(psc.out, pat.map.width); Blank(psc.out); Int(psc.out, pat.map.height);
					Str(psc.out, " rectfill"); Ln(psc.out)
				END;
				Str(psc.out, "  }"); Ln(psc.out);
				Str(psc.out, ">> ");
				Matrix(psc.out, psc.defMatrix);
				Str(psc.out, " makepattern put"); Ln(psc.out);
				pat := pat.next; INC(n)
			UNTIL pat = NIL
		END;
		t1 := psc.t1fonts;
		WHILE t1 # NIL DO
			Str(psc.out, "%%BeginResource: font "); Str(psc.out, t1.name); Ln(psc.out);
			Type1(psc.out, t1.name);
			Str(psc.out, "%%EndResource"); Ln(psc.out);
			t1 := t1.next
		END;
		t3 := psc.t3fonts;
		WHILE t3 # NIL DO
			Str(psc.out, "%%BeginResource: font "); Str(psc.out, t3.name); Ln(psc.out);
			Type3(psc.out, t3, 72/psc.res);
			Str(psc.out, "%%EndResource"); Ln(psc.out);
			t3 := t3.next
		END;
		Str(psc.out, "%%EndSetup"); Ln(psc.out)
	END Setup;
	
	
	(*--- initialization ---*)
	
	PROCEDURE Reset (ctxt: Gfx.Context);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		Gfx.InitContextValues(psc);
		Str(psc.out, "ig "); Real(psc.out, PSDPI/ScreenDPI); Str(psc.out, " slw ");
		Real(psc.out, psc.styleLimit); Str(psc.out, " sml");
		IF psc.level2 THEN Str(psc.out, " /DeviceRGB setcolorspace") END;
		Ln(psc.out);
		Gfx.ResetCTM(psc);
		Gfx.ResetClip(psc);
		psc.simpleCap := TRUE; psc.simpleJoin := TRUE;
		psc.color := Gfx.Black; psc.pattern := NIL;
		psc.fontname := ""
	END Reset;
	
	
	(*--- Coordinate System ---*)
	
	PROCEDURE SetCTM (ctxt: Gfx.Context; VAR mat: GfxMatrix.Matrix);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		psc.ctm := mat;
		IF ~(Gfx.InPath IN psc.mode) THEN
			Str(psc.out, "im ");
			Matrix(psc.out, mat); Str(psc.out, " cc"); Ln(psc.out)
		END
	END SetCTM;
	
	PROCEDURE ResetCTM (ctxt: Gfx.Context);
	BEGIN
		SetCTM(ctxt, ctxt(Context).defMatrix)
	END ResetCTM;
	
	PROCEDURE Translate (ctxt: Gfx.Context; dx, dy: REAL);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		GfxMatrix.Translate(psc.ctm, dx, dy, psc.ctm);
		IF ~(Gfx.InPath IN psc.mode) THEN
			Point(psc.out, dx, dy); Str(psc.out, " tr"); Ln(psc.out)
		END
	END Translate;
	
	PROCEDURE Scale (ctxt: Gfx.Context; sx, sy: REAL);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		GfxMatrix.Scale(psc.ctm, sx, sy, psc.ctm);
		IF ~(Gfx.InPath IN psc.mode) THEN
			Point(psc.out, sx, sy); Str(psc.out, " sc"); Ln(psc.out)
		END
	END Scale;
	
	PROCEDURE Rotate (ctxt: Gfx.Context; sin, cos: REAL);
		VAR psc: Context; m: GfxMatrix.Matrix;
	BEGIN
		psc := ctxt(Context);
		GfxMatrix.Rotate(psc.ctm, sin, cos, psc.ctm);
		IF ~(Gfx.InPath IN psc.mode) THEN
			GfxMatrix.Rotate(GfxMatrix.Identity, sin, cos, m);
			Matrix(psc.out, m); Str(psc.out, " cc"); Ln(psc.out)
		END
	END Rotate;
	
	PROCEDURE Concat (ctxt: Gfx.Context; VAR mat: GfxMatrix.Matrix);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		GfxMatrix.Concat(mat, psc.ctm, psc.ctm);
		IF ~(Gfx.InPath IN psc.mode) THEN
			Matrix(psc.out, mat); Str(psc.out, " cc"); Ln(psc.out)
		END
	END Concat;
	
	
	(*--- Clipping ---*)
	
	PROCEDURE ResetClip (ctxt: Gfx.Context);
		VAR psc: Context; llx, lly, urx, ury: REAL;
	BEGIN
		psc := ctxt(Context);
		IF psc.clip = NIL THEN NEW(psc.clip); NEW(psc.clip.path) END;
		GfxPaths.Clear(psc.clip.path); psc.clip.evenOdd := FALSE; psc.clip.next := NIL;
		psc.clip.llx := MIN(REAL); psc.clip.lly := MIN(REAL); psc.clip.urx := MAX(REAL); psc.clip.ury := MAX(REAL);
		psc.clipDepth := 0;
		IF ~psc.eps THEN
			GfxMatrix.ApplyToRect(psc.defMatrix, 0, 0, psc.width - psc.right - psc.left, psc.height - psc.top - psc.bot, llx, lly, urx, ury);
			GfxPaths.AddRect(psc.clip.path, llx, lly, urx, ury);
			psc.clip.llx := llx; psc.clip.lly := lly; psc.clip.urx := urx; psc.clip.ury := ury;
			IF ~GfxMatrix.Equal(psc.ctm, psc.defMatrix) THEN
				Str(psc.out, "ctm im "); Matrix(psc.out, psc.defMatrix); Str(psc.out, " cc ")
			END;
			Str(psc.out, "ic ");
			IF psc.level2 THEN
				Point(psc.out, 0, 0); Blank(psc.out);
				Point(psc.out, psc.width - psc.right - psc.left, psc.height - psc.top - psc.bot); Str(psc.out, " rectclip")
			ELSE
				Rect(psc.out, 0, 0, psc.width - psc.right - psc.left, psc.height - psc.top - psc.bot); Str(psc.out, " clnp")
			END;
			IF ~GfxMatrix.Equal(psc.ctm, psc.defMatrix) THEN
				Str(psc.out, " sm")
			END;
			Ln(psc.out)
		END
	END ResetClip;
	
	PROCEDURE GetClipRect (ctxt: Gfx.Context; VAR llx, lly, urx, ury: REAL);
		VAR clip: ClipPath;
	BEGIN
		clip := ctxt(Context).clip;
		llx := clip.llx; lly := clip.lly; urx := clip.urx; ury := clip.ury
	END GetClipRect;
	
	PROCEDURE SaveClip (ctxt: Gfx.Context);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		IF psc.clipDepth < ClipStackDepth THEN
			psc.clipStack[psc.clipDepth] := psc.clip
		END;
		INC(psc.clipDepth)
	END SaveClip;
	
	PROCEDURE RestoreClip (ctxt: Gfx.Context);
		VAR psc: Context; inv: GfxMatrix.Matrix; clip: ClipPath;
	BEGIN
		psc := ctxt(Context);
		ASSERT(psc.clipDepth > 0);
		DEC(psc.clipDepth);
		IF psc.clipDepth < ClipStackDepth THEN
			psc.clip := psc.clipStack[psc.clipDepth];
			GfxMatrix.Invert(psc.ctm, inv);
			Str(psc.out, "ic"); Ln(psc.out);
			clip := psc.clip;
			WHILE clip # NIL DO
				GfxPaths.Copy(clip.path, TmpPath);
				GfxPaths.Apply(TmpPath, inv);
				Path(psc.out, TmpPath);
				IF clip.evenOdd THEN Str(psc.out, "eo") END;
				Str(psc.out, "clnp"); Ln(psc.out);
				clip := clip.next
			END
		END
	END RestoreClip;
	
	
	(*--- Graphics State ---*)
	
	PROCEDURE SetLineWidth (ctxt: Gfx.Context; width: REAL);
		VAR psc: Context;
	BEGIN
		IF width # ctxt.lineWidth THEN
			psc := ctxt(Context);
			psc.lineWidth := width;
			Real(psc.out, width); Str(psc.out, " slw"); Ln(psc.out)
		END
	END SetLineWidth;
	
	PROCEDURE SetDashPattern (ctxt: Gfx.Context; VAR on, off: ARRAY OF REAL; len: LONGINT; phase: REAL);
		VAR psc: Context; i: LONGINT; pat: ARRAY 2*Gfx.MaxDashPatSize OF REAL;
	BEGIN
		psc := ctxt(Context);
		Gfx.SetDashArray(psc, on, off, len);
		psc.dashPhase := phase;
		FOR i := 0 TO len-1 DO
			pat[2*i] := on[i]; pat[2*i+1] := off[i]
		END;
		Array(psc.out, pat, 2*len); Ch(psc.out, " "); Real(psc.out, phase); Str(psc.out, " sd"); Ln(psc.out)
	END SetDashPattern;
	
	PROCEDURE SetCapStyle (ctxt: Gfx.Context; style: Gfx.CapStyle);
		VAR psc: Context; butt, round, square: Gfx.CapStyle;
	BEGIN
		IF style # ctxt.capStyle THEN
			psc := ctxt(Context);
			butt := Gfx.ButtCap; round := Gfx.RoundCap; square := Gfx.SquareCap;
			psc.capStyle := style;
			IF style = butt THEN
				psc.simpleCap := TRUE;
				Str(psc.out, "0 slc"); Ln(psc.out)
			ELSIF style = round THEN
				psc.simpleCap := TRUE;
				Str(psc.out, "1 slc"); Ln(psc.out)
			ELSIF style = square THEN
				psc.simpleCap := TRUE;
				Str(psc.out, "2 slc"); Ln(psc.out)
			ELSE
				psc.simpleCap := FALSE
			END
		END
	END SetCapStyle;
	
	PROCEDURE SetJoinStyle (ctxt: Gfx.Context; style: Gfx.JoinStyle);
		VAR psc: Context; miter, bevel, round: Gfx.JoinStyle;
	BEGIN
		IF style # ctxt.joinStyle THEN
			psc := ctxt(Context);
			miter := Gfx.MiterJoin; bevel := Gfx.BevelJoin; round := Gfx.RoundJoin;
			psc.joinStyle := style;
			IF style = miter THEN
				psc.simpleJoin := TRUE;
				Str(psc.out, "0 slj "); Ln(psc.out)
			ELSIF style = round THEN
				psc.simpleJoin := TRUE;
				Str(psc.out, "1 slj"); Ln(psc.out)
			ELSIF style = bevel THEN
				psc.simpleJoin := TRUE;
				Str(psc.out, "2 slj"); Ln(psc.out)
			ELSE
				psc.simpleJoin := FALSE
			END
		END
	END SetJoinStyle;
	
	PROCEDURE SetStyleLimit (ctxt: Gfx.Context; limit: REAL);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		psc.styleLimit := limit;
		Real(psc.out, limit); Str(psc.out, " sml"); Ln(psc.out)
	END SetStyleLimit;
	
	PROCEDURE SetPoint (ctxt: Gfx.Context; x, y: REAL);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		Point(psc.out, x, y); Str(psc.out, " mt"); Ln(psc.out);
		psc.cpx := x; psc.cpy := y
	END SetPoint;
	
	PROCEDURE SetFlatness (ctxt: Gfx.Context; flatness: REAL);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		Real(psc.out, flatness); Str(psc.out, " setflat"); Ln(psc.out);
		ctxt.flatness := flatness
	END SetFlatness;
	
	PROCEDURE GetWidth (ctxt: Gfx.Context; VAR str: ARRAY OF CHAR; VAR dx, dy: REAL);
		VAR psc: Context; scale: REAL; m: GfxMatrix.Matrix; font: GfxFonts.Font;
	BEGIN
		psc := ctxt(Context);
		scale := psc.res/ScreenDPI * Math.sqrt(GfxMatrix.Det(psc.ctm)/GfxMatrix.Det(psc.defMatrix));
		GfxMatrix.Init(m, scale, 0, 0, scale, 0, 0);
		GfxMatrix.Concat(psc.font.mat, m, m);
		font := GfxFonts.Open(psc.font.name, psc.font.ptsize, m);
		IF font = NIL THEN font := GfxFonts.Default END;
		GfxFonts.GetStringWidth(font, str, dx, dy);
		dx := dx/scale; dy := dy/scale
	END GetWidth;
	
	
	(*--- Current Path ---*)
	
	PROCEDURE IncludeBox (psc: Context; llx, lly, urx, ury: REAL);
		VAR clip: ClipPath;
	BEGIN
		clip := psc.clip;
		IF llx < clip.llx THEN llx := clip.llx END;
		IF lly < clip.lly THEN lly := clip.lly END;
		IF urx > clip.urx THEN urx := clip.urx END;
		IF ury > clip.ury THEN ury := clip.ury END;
		IF llx < psc.llx THEN psc.llx := llx END;
		IF lly < psc.lly THEN psc.lly := lly END;
		IF urx > psc.urx THEN psc.urx := urx END;
		IF ury > psc.ury THEN psc.ury := ury END
	END IncludeBox;
	
	PROCEDURE SetColor (psc: Context; col: Gfx.Color; pattern: Gfx.Pattern);
	BEGIN
		IF psc.level2 & ((col.r # psc.color.r) OR (col.g # psc.color.g) OR (col.b # psc.color.b) OR (pattern # psc.pattern)) THEN
			IF (pattern = NIL) OR (pattern.map.fmt.components = {GfxMaps.Alpha}) THEN
				Real(psc.out, col.r/255); Ch(psc.out, " ");
				Real(psc.out, col.g/255); Ch(psc.out, " ");
				Real(psc.out, col.b/255); Ch(psc.out, " ")
			END;
			IF pattern = NIL THEN
				Str(psc.out, "srgb"); Ln(psc.out)
			ELSE
				Int(psc.out, PatternNo(psc, pattern)); Str(psc.out, " spat"); Ln(psc.out)
			END;
			psc.color := col; psc.pattern := pattern
		ELSIF ~psc.level2 &
			(Grey(col.r, col.g, col.b) # Grey(psc.color.r, psc.color.g, psc.color.b)) &
			((pattern = NIL) OR (pattern.map.fmt.components = {GfxMaps.Alpha}))
		THEN
			Real(psc.out, Grey(col.r, col.g, col.b)/255); Str(psc.out, " sg"); Ln(psc.out);
			psc.color := col; psc.pattern := pattern
		END
	END SetColor;
	
	PROCEDURE FillPattern (psc: Context; llx, lly, urx, ury: REAL; pat: Pattern);
		VAR m: GfxMatrix.Matrix; px, py: REAL; vcnt, hcnt: LONGINT;
	BEGIN
		Str(psc.out, "gs clip"); Ln(psc.out);
		GfxMatrix.Invert(psc.defMatrix, m);
		GfxMatrix.ApplyToRect(m, llx, lly, urx, ury, llx, lly, urx, ury);
		ResetCTM(psc);
		px := pat.px + ENTIER((llx - pat.px)/pat.map.width) * pat.map.width;
		py := pat.py + ENTIER((lly - pat.py)/pat.map.height) * pat.map.height;
		Point(psc.out, px, py); Str(psc.out, " tr"); Ln(psc.out);
		vcnt := -ENTIER((py - ury)/pat.map.height);
		REPEAT
			Str(psc.out, "gs"); Ln(psc.out);
			hcnt := -ENTIER((px - urx)/pat.map.width);
			REPEAT
				UseMap(psc, pat.map, pat.no);
				Int(psc.out, pat.map.width); Str(psc.out, " 0 tr"); Ln(psc.out);
				DEC(hcnt)
			UNTIL hcnt <= 0;
			Str(psc.out, "gr 0 "); Int(psc.out, pat.map.height); Str(psc.out, " tr"); Ln(psc.out);
			DEC(vcnt)
		UNTIL vcnt <= 0;
		Str(psc.out, "gr"); Ln(psc.out)
	END FillPattern;
	
	PROCEDURE RenderPath (psc: Context; path: GfxPaths.Path);
		VAR inv: GfxMatrix.Matrix; clip: ClipPath; llx, lly, urx, ury, lw, bw: REAL; savePath: GfxPaths.Path;
	BEGIN
		IF ~GfxPaths.Empty(path) THEN
			IF (psc.mode * {Gfx.Clip, Gfx.Fill} # {}) OR (Gfx.Stroke IN psc.mode) & psc.simpleStroke THEN
				GfxPaths.Copy(path, TmpPath);
				GfxMatrix.Invert(psc.cam, inv);
				GfxPaths.Apply(TmpPath, inv);
				Path(psc.out, TmpPath)
			END;
			GfxPaths.GetBox(path, llx, lly, urx, ury);
			IF Gfx.Clip IN psc.mode THEN
				IF Gfx.EvenOdd IN psc.mode THEN Str(psc.out, "eoclip") ELSE Str(psc.out, "clip") END;
				IF psc.mode * {Gfx.Fill, Gfx.Stroke} = {} THEN
					Str(psc.out, " np")	(* necessary because 'clip' doesn't reset the current path *)
				END;
				Ln(psc.out);
				NEW(clip); clip.evenOdd := Gfx.EvenOdd IN psc.mode;
				NEW(clip.path); GfxPaths.Copy(path, clip.path);
				IF llx > psc.clip.llx THEN clip.llx := llx ELSE clip.llx := psc.clip.llx END;
				IF lly > psc.clip.lly THEN clip.lly := lly ELSE clip.lly := psc.clip.lly END;
				IF urx < psc.clip.urx THEN clip.urx := urx ELSE clip.urx := psc.clip.urx END;
				IF ury < psc.clip.ury THEN clip.ury := ury ELSE clip.ury := psc.clip.ury END;
				clip.next := psc.clip; psc.clip := clip
			END;
			IF Gfx.Fill IN psc.mode THEN
				IncludeBox(psc, llx, lly, urx, ury);
				SetColor(psc, psc.fillCol, psc.fillPat);
				IF psc.simpleFill THEN
					IF (Gfx.Stroke IN psc.mode) & psc.simpleStroke THEN Str(psc.out, "gs ") END;
					IF Gfx.EvenOdd IN psc.mode THEN Str(psc.out, "eofill") ELSE Str(psc.out, "fill") END;
					IF (Gfx.Stroke IN psc.mode) & psc.simpleStroke THEN Str(psc.out, " gr") END;
					Ln(psc.out)
				ELSE
					FillPattern(psc, llx, lly, urx, ury, psc.fillPat(Pattern));
					IF ~(Gfx.Stroke IN psc.mode) THEN
						Str(psc.out, "np"); Ln(psc.out)
					END
				END
			END;
			IF Gfx.Stroke IN psc.mode THEN
				GfxMatrix.ApplyToDist(psc.cam, 0.5*psc.lineWidth, lw);
				bw := lw * psc.styleLimit;
				IncludeBox(psc, llx - bw, lly - bw, urx + bw, ury + bw);
				SetColor(psc, psc.strokeCol, psc.strokePat);
				IF psc.simpleStroke THEN
					Str(psc.out, "stroke"); Ln(psc.out)
				ELSE
					savePath := psc.path; psc.path := path;
					Gfx.GetOutline(psc, TmpPath);
					psc.path := savePath;
					GfxMatrix.Invert(psc.cam, inv);
					GfxPaths.Apply(TmpPath, inv);
					Path(psc.out, TmpPath);
					IF (psc.strokePat = NIL) OR psc.level2 & (PatternNo(psc, psc.fillPat) >= 0) THEN
						Str(psc.out, "fill"); Ln(psc.out)
					ELSE
						FillPattern(psc, llx, lly, urx, ury, psc.strokePat(Pattern));
						Str(psc.out, "np"); Ln(psc.out)
					END
				END
			END
		END
	END RenderPath;
	
	PROCEDURE Begin (ctxt: Gfx.Context; mode: SET);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		psc.mode := mode * {Gfx.Record..Gfx.EvenOdd};
		IF Gfx.Record IN mode THEN
			IF psc.path = NIL THEN NEW(psc.path) END;
			GfxPaths.Clear(psc.path)
		ELSE
			IF psc.cp = NIL THEN NEW(psc.cp) END;
			GfxPaths.Clear(psc.cp);
		END;
		psc.cam := psc.ctm;	(* preserve current transformation for attributes *)
		psc.simpleStroke := psc.simpleCap & psc.simpleJoin;
		psc.simpleStroke := psc.simpleStroke & ((psc.strokePat = NIL) OR psc.level2 & (PatternNo(psc, psc.strokePat) >= 0));
		psc.simpleFill := (psc.fillPat = NIL) OR psc.level2 & (PatternNo(psc, psc.fillPat) >= 0);
	END Begin;
	
	PROCEDURE End (ctxt: Gfx.Context);
		VAR psc: Context; path: GfxPaths.Path;
	BEGIN
		psc := ctxt(Context);
		IF Gfx.Record IN psc.mode THEN path := psc.path ELSE path := psc.cp END;
		RenderPath(psc, path);
		IF ~GfxMatrix.Equal(psc.ctm, psc.cam) THEN	(* update current PS matrix *)
			Str(psc.out, "im "); Matrix(psc.out, psc.ctm); Str(psc.out, " cc"); Ln(psc.out)
		END
	END End;
	
	PROCEDURE Enter (ctxt: Gfx.Context; x, y, dx, dy: REAL);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		psc.closed := (dx # 0) OR (dy # 0);
		GfxMatrix.Apply(psc.ctm, x, y, psc.sx, psc.sy);
		GfxMatrix.ApplyToVector(psc.ctm, dx, dy, dx, dy);
		IF Gfx.Record IN psc.mode THEN
			GfxPaths.AddEnter(psc.path, psc.sx, psc.sy, dx, dy)
		ELSE
			GfxPaths.AddEnter(psc.cp, psc.sx, psc.sy, dx, dy)
		END;
		psc.cx := psc.sx; psc.cy := psc.sy;
		psc.cpx := x; psc.cpy := y
	END Enter;
	
	PROCEDURE Exit (ctxt: Gfx.Context; dx, dy: REAL);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		GfxMatrix.ApplyToVector(psc.ctm, dx, dy, dx, dy);
		IF Gfx.Record IN psc.mode THEN
			GfxPaths.AddExit(psc.path, dx, dy)
		ELSE
			GfxPaths.AddExit(psc.cp, dx, dy)
		END;
		psc.simpleStroke := psc.simpleStroke & ((dx = 0) & (dy = 0) OR (psc.cx = psc.sx) & (psc.cy = psc.sy) & psc.closed)
	END Exit;
	
	PROCEDURE LineTo (ctxt: Gfx.Context; x, y: REAL);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		GfxMatrix.Apply(psc.ctm, x, y, psc.cx, psc.cy);
		IF Gfx.Record IN psc.mode THEN
			GfxPaths.AddLine(psc.path, psc.cx, psc.cy)
		ELSE
			GfxPaths.AddLine(psc.cp, psc.cx, psc.cy)
		END;
		psc.cpx := x; psc.cpy := y
	END LineTo;
	
	PROCEDURE ArcTo (ctxt: Gfx.Context; x, y, x0, y0, x1, y1, x2, y2: REAL);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		GfxMatrix.Apply(psc.ctm, x, y, psc.cx, psc.cy);
		GfxMatrix.Apply(psc.ctm, x0, y0, x0, y0);
		GfxMatrix.Apply(psc.ctm, x1, y1, x1, y1);
		GfxMatrix.Apply(psc.ctm, x2, y2, x2, y2);
		IF Gfx.Record IN psc.mode THEN
			GfxPaths.AddArc(psc.path, psc.cx, psc.cy, x0, y0, x1, y1, x2, y2)
		ELSE
			GfxPaths.AddArc(psc.cp, psc.cx, psc.cy, x0, y0, x1, y1, x2, y2)
		END;
		psc.cpx := x; psc.cpy := y
	END ArcTo;
	
	PROCEDURE BezierTo (ctxt: Gfx.Context; x, y, x1, y1, x2, y2: REAL);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		GfxMatrix.Apply(psc.ctm, x, y, psc.cx, psc.cy);
		GfxMatrix.Apply(psc.ctm, x1, y1, x1, y1);
		GfxMatrix.Apply(psc.ctm, x2, y2, x2, y2);
		IF Gfx.Record IN psc.mode THEN
			GfxPaths.AddBezier(psc.path, psc.cx, psc.cy, x1, y1, x2, y2)
		ELSE
			GfxPaths.AddBezier(psc.cp, psc.cx, psc.cy, x1, y1, x2, y2)
		END;
		psc.cpx := x; psc.cpy := y
	END BezierTo;
	
	PROCEDURE ShowOutline (psc: Context; x, y: REAL; VAR str: ARRAY OF CHAR);
		VAR m: GfxMatrix.Matrix; font: GfxFonts.Font; bw, llx, lly, urx, ury, dx, dy: REAL; i: LONGINT; path: GfxPaths.Path;
	BEGIN
		GfxMatrix.Concat(psc.font.mat, psc.ctm, m);
		font := GfxFonts.Open(psc.font.name, psc.font.ptsize, m);
		IF font # NIL THEN
			IF (psc.mode * {Gfx.Record, Gfx.Clip} = {}) & GfxMatrix.Equal(psc.ctm, psc.cam) &
				(~(Gfx.Stroke IN psc.mode) OR psc.simpleStroke) &
				(~(Gfx.Fill IN psc.mode) OR psc.simpleFill)
			THEN
				RenderPath(psc, psc.cp);
				GfxPaths.Clear(psc.cp);
				SetOutlineFont(psc);
				bw := 0;
				IF Gfx.Fill IN psc.mode THEN
					SetColor(psc, psc.fillCol, psc.fillPat);
					Point(psc.out, x, y); Str(psc.out, " mt "); Literal(psc.out, str); Str(psc.out, " true charpath ");
					IF Gfx.EvenOdd IN psc.mode THEN Str(psc.out, "eofill") ELSE Str(psc.out, "fill") END;
					Ln(psc.out)
				END;
				IF Gfx.Stroke IN psc.mode THEN
					SetColor(psc, psc.strokeCol, psc.strokePat);
					Point(psc.out, x, y); Str(psc.out, " mt "); Literal(psc.out, str); Str(psc.out, " false charpath stroke"); Ln(psc.out);
					GfxMatrix.ApplyToDist(psc.cam, 0.5*psc.lineWidth, bw);
					bw := bw * psc.styleLimit
				END;
				GfxMatrix.Apply(psc.ctm, x, y, x, y);
				i := 0;
				WHILE str[i] # 0X DO
					GfxFonts.GetOutline(font, str[i], x, y, TmpPath);
					GfxPaths.GetBox(TmpPath, llx, lly, urx, ury);
					IncludeBox(psc, llx - bw, lly - bw, urx + bw, ury + bw);
					GfxFonts.GetWidth(font, str[i], dx, dy);
					x := x + dx; y := y + dy;
					INC(i)
				END;
				GfxMatrix.Solve(psc.ctm, x, y, psc.cpx, psc.cpy)
			
			ELSE
				IF Gfx.Record IN psc.mode THEN path := psc.path ELSE path := psc.cp END;
				GfxMatrix.Apply(psc.ctm, x, y, x, y);
				i := 0;
				WHILE str[i] # 0X DO
					GfxFonts.GetOutline(font, str[i], x, y, TmpPath);
					GfxPaths.Append(path, TmpPath);
					GfxFonts.GetWidth(font, str[i], dx, dy);
					x := x + dx; y := y + dy;
					INC(i)
				END;
				GfxMatrix.Solve(psc.ctm, x, y, psc.cpx, psc.cpy)
			END
		END
	END ShowOutline;
	
	PROCEDURE ShowRaster (psc: Context; x, y: REAL; VAR str: ARRAY OF CHAR; font: GfxFonts.Font; VAR m: GfxMatrix.Matrix);
		VAR name, s: GfxFonts.FontName; i, n: LONGINT; t3: T3Font; dx, dy, llx, lly, urx, ury: REAL;
	BEGIN
		IF font.rfont # NIL THEN
			COPY(font.rfont.name, name)
		ELSE
			COPY(font.name, name);
			Strings.AppendCh(name, ".");
			Strings.RealToFixStr(Math.sqrt(GfxMatrix.Det(psc.ctm) * GfxMatrix.Det(font.mat)), s, 3, 1, 0);
			i := 0; WHILE s[i] = " " DO s[i] := "0"; INC(i) END;
			Strings.Append(name, s)
		END;
		t3 := psc.t3fonts; WHILE (t3 # NIL) & (t3.name # name) DO t3 := t3.next END;
		IF (name # psc.fontname) OR ~GfxMatrix.Equal(m, psc.fontmat) THEN
			IF t3 = NIL THEN
				NEW(t3); t3.font := font; COPY(name, t3.name);
				t3.next := psc.t3fonts; psc.t3fonts := t3
			END;
			font := t3.font;
			SelectFont(psc, name, m)
		END;
		i := 0; n := ORD(str[0]);
		WHILE n # 0 DO
			INCL(t3.used[n DIV 32], n MOD 32); INC(i); n := ORD(str[i])
		END;
		Literal(psc.out, str); Blank(psc.out); Point(psc.out, x, y); Str(psc.out, " mts"); Ln(psc.out);
		
		GfxMatrix.Apply(psc.ctm, x, y, x, y);
		GfxFonts.GetStringWidth(font, str, dx, dy);
		GfxMatrix.Scale(m, ScreenDPI/psc.res, ScreenDPI/psc.res, m);
		GfxMatrix.Concat(m, psc.ctm, m);
		GfxMatrix.ApplyToRect(m, font.xmin, font.ymin, dx + font.xmax, dy + font.ymax, llx, lly, urx, ury);
		GfxMatrix.ApplyToVector(m, dx, dy, dx, dy);
		GfxMatrix.Solve(psc.ctm, x + dx, y + dy, psc.cpx, psc.cpy);
		dx := x - m[2, 0]; dy := y - m[2, 1];
		IncludeBox(psc, llx + dx, lly + dy, urx + dx, ury + dy)
	END ShowRaster;
	
	PROCEDURE Show (ctxt: Gfx.Context; x, y: REAL; VAR str: ARRAY OF CHAR);
		VAR psc: Context; scale, dx, dy, llx, lly, urx, ury: REAL; inv, m: GfxMatrix.Matrix; font: GfxFonts.Font;
	BEGIN
		psc := ctxt(Context);
		IF (psc.mode * {Gfx.Record..Gfx.EvenOdd} = {Gfx.Fill}) & psc.simpleFill THEN
			SetColor(psc, psc.fillCol, psc.fillPat);
			scale := Math.sqrt(GfxMatrix.Det(psc.ctm))/(PSDPI/ScreenDPI);	(* overall scale factor wrt default matrix *)
			GfxMatrix.Init(inv, 1/scale, 0, 0, 1/scale, 0, 0);
			scale := scale * psc.res/ScreenDPI;	(* scale factor relative to context font *)
			GfxMatrix.Init(m, scale, 0, 0, scale, 0, 0);
			GfxMatrix.Concat(psc.font.mat, m, m);
			font := GfxFonts.Open(psc.font.name, psc.font.ptsize, m);
			IF font = NIL THEN font := GfxFonts.Default END;
			IF font.niceMaps THEN
				ShowRaster(psc, x, y, str, font, inv)
			ELSE
				SetOutlineFont(psc);
				Literal(psc.out, str); Blank(psc.out); Point(psc.out, x, y); Str(psc.out, " mts"); Ln(psc.out);
				font := GfxFonts.Open(psc.fontname, psc.font.ptsize, psc.font.mat);
				IF font = NIL THEN font := GfxFonts.Default END;
				GfxFonts.GetStringWidth(font, str, dx, dy);
				psc.cpx := psc.cpx + dx; psc.cpy := psc.cpy + dy;
				GfxMatrix.ApplyToRect(psc.ctm, x + font.xmin, y + font.ymin, x + dx + font.xmax, y + dy + font.ymax, llx, lly, urx, ury);
				IncludeBox(psc, llx, lly, urx, ury)
			END
		ELSE
			ShowOutline(psc, x, y, str)
		END
	END Show;
	
	PROCEDURE Flatten (ctxt: Gfx.Context);
	BEGIN
		Gfx.GetFlattenedPath(ctxt, TmpPath);
		GfxPaths.Copy(TmpPath, ctxt.path)
	END Flatten;
	
	PROCEDURE Outline (ctxt: Gfx.Context);
	BEGIN
		Gfx.GetOutline(ctxt, TmpPath);
		GfxPaths.Copy(TmpPath, ctxt.path)
	END Outline;
	
	PROCEDURE Render (ctxt: Gfx.Context; mode: SET);
		VAR psc: Context; s: GfxPaths.Scanner; sx, sy, cx, cy: REAL; closed: BOOLEAN;
	BEGIN
		psc := ctxt(Context);
		psc.mode := mode; psc.cam := psc.ctm;
		IF Gfx.Fill IN mode THEN
			psc.simpleFill := (psc.fillPat = NIL) OR psc.level2 & (PatternNo(psc, psc.fillPat) >= 0)
		END;
		IF Gfx.Stroke IN mode THEN
			psc.simpleStroke := psc.simpleCap & psc.simpleJoin;
			psc.simpleStroke := psc.simpleStroke & ((psc.strokePat = NIL) OR psc.level2 & (PatternNo(psc, psc.strokePat) >= 0));
			GfxPaths.Open(s, psc.path, 0);
			WHILE psc.simpleStroke & (s.elem # GfxPaths.Stop) DO
				CASE s.elem OF
				| GfxPaths.Enter:
					closed := (s.dx # 0) OR (s.dy # 0);
					sx := s.x; sy := s.y; cx := sx; cy := sy
				| GfxPaths.Line, GfxPaths.Arc, GfxPaths.Bezier:
					cx := s.x; cy := s.y
				| GfxPaths.Exit:
					psc.simpleStroke := psc.simpleStroke & ((s.dx = 0) & (s.dy = 0) OR (cx = sx) & (cy = sy) & closed)
				END;
				GfxPaths.Scan(s)
			END
		END;
		RenderPath(psc, psc.path)
	END Render;
	
	
	(*--- Painting Operators ---*)
	
	PROCEDURE Erase (ctxt: Gfx.Context);
		VAR psc: Context;
	BEGIN
		psc := ctxt(Context);
		Str(psc.out, "ep"); Ln(psc.out)
	END Erase;
	
	
	(*--- Images and Patterns ---*)
	
	PROCEDURE ImageM (ctxt: Gfx.Context; x, y: REAL; map: GfxMaps.Map; VAR filter: GfxMaps.Filter);
		VAR psc: Context; no: INTEGER; llx, lly, urx, ury: REAL;
	BEGIN
		psc := ctxt(Context);
		RegisterMap(psc, map, no);
		SetColor(psc, psc.fillCol, NIL);
		UseMap(psc, map, no);
		GfxMatrix.ApplyToRect(psc.ctm, x, y, x + map.width, y + map.height, llx, lly, urx, ury);
		IncludeBox(psc, llx, lly, urx, ury)
	END ImageM;
	
	PROCEDURE NewPattern (ctxt: Gfx.Context; map: GfxMaps.Map; px, py: REAL): Gfx.Pattern;
		VAR psc: Context; no: INTEGER; pat: Pattern;
	BEGIN
		psc := ctxt(Context);
		RegisterMap(psc, map, no);
		pat := psc.patterns;
		IF pat = NIL THEN
			NEW(pat); psc.patterns := pat; pat.map := map; pat.px := px; pat.py := py; pat.no := no
		ELSE
			WHILE (pat.next # NIL) & ((pat.next.map # map) OR (pat.next.px # px) OR (pat.next.py # py)) DO
				pat := pat.next
			END;
			IF pat.next = NIL THEN
				NEW(pat.next); pat.next.map := map; pat.next.px := px; pat.next.py := py; pat.next.no := no
			END;
			pat := pat.next
		END;
		RETURN pat
	END NewPattern;
	
	
	(*--- Method Table ---*)
	
	PROCEDURE InitMethods;
		VAR do: Gfx.Methods;
	BEGIN
		NEW(do);
		Methods := do;
		do.reset := Reset; do.resetCTM := ResetCTM; do.setCTM := SetCTM;
		do.translate := Translate; do.scale := Scale; do.rotate := Rotate; do.concat := Concat;
		do.resetClip := ResetClip; do.getClipRect := GetClipRect; do.saveClip := SaveClip; do.restoreClip := RestoreClip;
		do.setStrokeColor := Gfx.DefSetStrokeColor; do.setStrokePattern := Gfx.DefSetStrokePattern;
		do.setFillColor := Gfx.DefSetFillColor; do.setFillPattern := Gfx.DefSetFillPattern;
		do.setLineWidth := SetLineWidth; do.setDashPattern := SetDashPattern;
		do.setCapStyle := SetCapStyle; do.setJoinStyle := SetJoinStyle; do.setStyleLimit := SetStyleLimit;
		do.setPoint := SetPoint; do.setFlatness := SetFlatness; do.setFont := Gfx.DefSetFont; do.getWidth := GetWidth;
		do.begin := Begin; do.end := End; do.enter := Enter; do.exit := Exit;
		do.line := LineTo; do.arc := ArcTo; do.bezier := BezierTo; do.show := Show;
		do.flatten := Flatten; do.outline := Outline; do.render := Render;
		do.erase := Erase; do.rect := Gfx.DefRect; do.ellipse := Gfx.DefEllipse;
		do.image := ImageM; do.newPattern := NewPattern;
	END InitMethods;
	
	
	(*--- Exported Interface ---*)
	
	(** initialize context **)
	PROCEDURE Init* (psc: Context; level2, landscape: BOOLEAN; width, height, left, right, bot, top: REAL; res: LONGINT);
	BEGIN
		psc.do := Methods;
		psc.eps := FALSE;
		psc.level2 := level2; psc.landscape := landscape;
		psc.width := width; psc.height := height;
		psc.left := left; psc.right := right; psc.bot := bot; psc.top := top;
		psc.res := res
	END Init;
	
	(** initialize context that generates EPS output **)
	PROCEDURE InitEPS* (psc: Context; level2: BOOLEAN; res: LONGINT);
	BEGIN
		psc.do := Methods;
		psc.eps := TRUE;
		psc.level2 := level2; psc.landscape := FALSE;
		psc.res := res
	END InitEPS;
	
	(** start output on given file **)
	PROCEDURE Open* (psc: Context; file: Files.File);
	BEGIN
		psc.psfile := file;
		Files.Set(psc.out, Files.New(""), 0);
		psc.images := NIL; psc.patterns := NIL; psc.t1fonts := NIL; psc.t3fonts := NIL;
		psc.llx := MAX(REAL); psc.lly := MAX(REAL); psc.urx := MIN(REAL); psc.ury := MIN(REAL);
		IF psc.eps THEN
			psc.defMatrix := GfxMatrix.Identity
		ELSE
			psc.pages := 0; psc.fileLen := 0;
			Str(psc.out, "%%Page: 0 1"); Ln(psc.out);
			Str(psc.out, "save"); Ln(psc.out);
			GfxMatrix.Translate(GfxMatrix.Identity, psc.left, psc.bot, psc.defMatrix)
		END;
		IF psc.landscape THEN
			GfxMatrix.Translate(psc.defMatrix, 0, psc.height, psc.defMatrix);
			GfxMatrix.Rotate(psc.defMatrix, -1, 0, psc.defMatrix)
		END;
		GfxMatrix.Scale(psc.defMatrix, PSDPI/ScreenDPI, PSDPI/ScreenDPI, psc.defMatrix);
		Reset(psc)
	END Open;
	
	(** terminate output on current page **)
	PROCEDURE ShowPage* (psc: Context);
	BEGIN
		IF ~psc.eps THEN
			INC(psc.pages);
			Str(psc.out, "showpage"); Ln(psc.out);
			Str(psc.out, "restore"); Ln(psc.out);
			Str(psc.out, "%%PageTrailer"); Ln(psc.out);
			psc.fileLen := Files.Pos(psc.out);
			Str(psc.out, "%%Page: "); Int(psc.out, psc.pages); Blank(psc.out); Int(psc.out, psc.pages+1); Ln(psc.out);
			Str(psc.out, "save"); Ln(psc.out);
			Reset(psc)
		END
	END ShowPage;
	
	(** terminate output for current document **)
	PROCEDURE Close* (psc: Context);
		CONST bufSize = 4096;
		VAR src: Files.Rider; date, time: LONGINT; str: ARRAY 32 OF CHAR; buf: ARRAY bufSize OF CHAR;
	BEGIN
		IF (psc.llx <= psc.urx) & (psc.lly <= psc.ury) & (psc.eps OR (psc.pages > 0)) THEN
			Files.Set(src, Files.Base(psc.out), 0);
			Files.Set(psc.out, psc.psfile, 0);
			Str(psc.out, "%!PS-Adobe-3.0");
			IF psc.eps THEN Str(psc.out, " EPSF-3.0") END;
			Ln(psc.out);
			Str(psc.out, "%%BoundingBox: ");
			Int(psc.out, ENTIER(psc.llx)); Blank(psc.out); Int(psc.out, ENTIER(psc.lly)); Blank(psc.out);
			Int(psc.out, -ENTIER(-psc.urx)); Blank(psc.out); Int(psc.out, -ENTIER(-psc.ury)); Ln(psc.out);
			Str(psc.out, "%%Creator: Oberon (GfxPS.Mod)"); Ln(psc.out);
			Str(psc.out, "%%CreationDate: ");
			Oberon.GetClock(time, date);
			Strings.DateToStr(date, str); Str(psc.out, str); Blank(psc.out);
			Strings.TimeToStr(time, str); Str(psc.out, str); Ln(psc.out);
			IF psc.level2 THEN Str(psc.out, "%%LanguageLevel: 2"); Ln(psc.out) END;
			Str(psc.out, "%%Orientation: ");
			IF psc.landscape THEN Str(psc.out, "Landscape") ELSE Str(psc.out, "Portrait") END; Ln(psc.out);
			IF ~psc.eps THEN Str(psc.out, "%%Pages: "); Int(psc.out, psc.pages); Ln(psc.out) END;
			Str(psc.out, "%%PageOrder: Ascend"); Ln(psc.out);
			Str(psc.out, "%%EndComments"); Ln(psc.out);
			Prolog(psc.out);
			Setup(psc);
			IF psc.eps THEN psc.fileLen := Files.Length(Files.Base(src)) END;
			WHILE psc.fileLen >= bufSize DO
				Files.ReadBytes(src, buf, bufSize);
				Files.WriteBytes(psc.out, buf, bufSize);
				DEC(psc.fileLen, bufSize)
			END;
			Files.ReadBytes(src, buf, psc.fileLen);
			Files.WriteBytes(psc.out, buf, psc.fileLen);
			Str(psc.out, "%%Trailer"); Ln(psc.out);
			Str(psc.out, "end"); Ln(psc.out);
			Str(psc.out, "%%EOF"); Ln(psc.out);
			Files.Register(psc.psfile);
			psc.images := NIL; psc.patterns := NIL; psc.t1fonts := NIL; psc.t3fonts := NIL
		END
	END Close;
	

BEGIN
	NEW(TmpPath);
	InitMethods
END GfxPS.
