MODULE OTFonts;	(** eos   **)

	(**
		Make OpenType fonts available to Oberon System
	**)
	
	IMPORT
		SYSTEM, Files, Objects, Fonts, Texts, Oberon, Strings, OTInt, OType;
		
	
	CONST
		ScreenDPI = 91;
		
	
	TYPE
		RasterData = RECORD (OType.RasterData)
			adr: LONGINT;	(* base address of pattern *)
			bpr: LONGINT;	(* number of bytes per row *)
		END;
		
		Font = POINTER TO FontDesc;
		FontDesc = RECORD (Fonts.FontDesc)
			inst: OType.Instance;
			glyph: OType.Glyph;
			mem: POINTER TO ARRAY OF CHAR;
			pattern: LONGINT;
		END;
		
	
	VAR
		Pattern: ARRAY 360*360 DIV 8 OF CHAR;	(* enough for 36 point at 720 dpi *)
		Glyph: OType.Glyph;
		Char: Fonts.Char;
		W: Texts.Writer;
		
	
	(* fill rectangle in pattern *)
	PROCEDURE FillRect (llx, lly, urx, ury, opacity: INTEGER; VAR data: OType.RasterData0);
		VAR x0, x1, h, n: INTEGER; adr, a: LONGINT; mask: SET; byte: CHAR;
	BEGIN
		WITH data: RasterData DO
			x0 := llx DIV 8; x1 := urx DIV 8;
			adr := data.adr + data.bpr * lly + x0;
			h := ury - lly;
			IF x0 = x1 THEN
				mask := {(llx MOD 8) .. ((urx-1) MOD 8)}
			ELSE
				mask := {(llx MOD 8) .. 7}
			END;
			n := h; a := adr;
			WHILE n > 0 DO
				SYSTEM.GET(a, byte);
				SYSTEM.PUT(a, SYSTEM.VAL(CHAR, SYSTEM.VAL(SET, byte) + mask));
				DEC(n); INC(a, data.bpr)
			END;
			IF x0 < x1 THEN
				INC(x0); INC(adr);
				WHILE x0 < x1 DO
					n := h; a := adr;
					WHILE n > 0 DO
						SYSTEM.PUT(a, 0FFX);
						DEC(n); INC(a, data.bpr)
					END;
					INC(x0); INC(adr)
				END;
				IF 8*x1 # urx THEN
					mask := {0 .. (urx-1) MOD 8};
					n := h; a := adr;
					WHILE n > 0 DO
						SYSTEM.GET(a, byte);
						SYSTEM.PUT(a, SYSTEM.VAL(CHAR, SYSTEM.VAL(SET, byte) + mask));
						DEC(n); INC(a, data.bpr)
					END
				END
			END
		END
	END FillRect;
	
	PROCEDURE MakeFont (inst: OType.Instance; name: ARRAY OF CHAR);
		CONST
			mode = {OType.Hinted, OType.Width, OType.Raster};
		VAR
			file: Files.File; r, m: Files.Rider; font: OType.Font; i, chars, ranges, xmin, ymin, xmax, ymax, j, no: INTEGER;
			beg, end: ARRAY 64 OF INTEGER; data: RasterData; bytes, k: LONGINT;
	BEGIN
		file := Files.New(name);
		ASSERT(file # NIL);
		Files.Set(r, file, 0);
		Files.Write(r, Fonts.FontId); Files.Write(r, Fonts.font);
		Files.Write(r, 0X); Files.Write(r, 0X);
		i := inst.font.hhea.ascender + inst.font.hhea.descender + inst.font.hhea.lineGap;
		Files.WriteInt(r, SHORT(OTInt.MulDiv(i, inst.yppm, 40H*LONG(inst.font.head.unitsPerEm))));
		Files.WriteInt(r, 0); Files.WriteInt(r, 0); Files.WriteInt(r, 0); Files.WriteInt(r, 0);	(* fix later *)
		
		font := inst.font;
		i := 0; chars := 0; ranges := 0;
		IF OType.UnicodeToGlyph(font, OType.CharToUnicode[1]) = 0 THEN
			i := 2; chars := 1; beg[0] := 0; end[0] := 1; ranges := 1	(* make range for 0X *)
		END;
		REPEAT
			WHILE (i < 256) & (i # 9) & (OType.UnicodeToGlyph(font, OType.CharToUnicode[i]) = 0) DO INC(i) END;
			IF i < 256 THEN
				beg[ranges] := i; INC(i); INC(chars);
				WHILE (i < 256) & (OType.UnicodeToGlyph(font, OType.CharToUnicode[i]) # 0) DO INC(i); INC(chars) END;
				end[ranges] := i; INC(ranges)
			END
		UNTIL i = 256;
		Files.WriteInt(r, ranges);
		i := 0;
		WHILE i < ranges DO
			Files.WriteInt(r, beg[i]); Files.WriteInt(r, end[i]);
			INC(i)
		END;
		
		Files.Set(m, file, Files.Pos(r));	(* open rider for later writing metrics *)
		i := 0;
		WHILE i < chars DO
			Files.WriteInt(r, 0); Files.WriteInt(r, 0); Files.WriteInt(r, 0); Files.WriteInt(r, 0); Files.WriteInt(r, 0);
			INC(i)
		END;
		
		xmin := MAX(INTEGER); ymin := MAX(INTEGER); xmax := MIN(INTEGER); ymax := MIN(INTEGER);
		i := 0;
		WHILE i < ranges DO
			j := beg[i];
			WHILE j < end[i] DO
				no := OType.UnicodeToGlyph(font, OType.CharToUnicode[j]);
				IF (j = 9) & (no = 0) THEN
					no := OType.UnicodeToGlyph(font, OType.CharToUnicode[ORD("I")]);
					OType.LoadGlyph(inst, Glyph, no, {OType.Hinted, OType.Width});
					Glyph.awx := 8*Glyph.awx;
					Glyph.hbx := 0; Glyph.hby := 0; Glyph.rw := 0; Glyph.rh := 0
				ELSE
					OType.LoadGlyph(inst, Glyph, no, mode)
				END;
				Files.WriteInt(m, Glyph.awx);
				Files.WriteInt(m, Glyph.hbx); Files.WriteInt(m, Glyph.hby);
				Files.WriteInt(m, Glyph.rw); Files.WriteInt(m, Glyph.rh);
				IF Glyph.rw * Glyph.rh # 0 THEN
					IF Glyph.hbx < xmin THEN xmin := Glyph.hbx END;
					IF Glyph.hby < ymin THEN ymin := Glyph.hby END;
					IF Glyph.hbx + Glyph.rw > xmax THEN xmax := Glyph.hbx + Glyph.rw END;
					IF Glyph.hby + Glyph.rh > ymax THEN ymax := Glyph.hby + Glyph.rh END;
					data.rect := FillRect; data.adr := SYSTEM.ADR(Pattern); data.bpr := (Glyph.rw+7) DIV 8;
					bytes := Glyph.rh * data.bpr;
					ASSERT(bytes < LEN(Pattern));
					k := 0; REPEAT Pattern[k] := 0X; INC(k) UNTIL k = bytes;
					OType.EnumRaster(Glyph, data);
					k := 0; REPEAT Files.Write(r, Pattern[k]); INC(k) UNTIL k = bytes
				END;
				INC(j)
			END;
			INC(i)
		END;
		
		Files.Set(r, file, 6);
		Files.WriteInt(r, xmin); Files.WriteInt(r, xmax);
		Files.WriteInt(r, ymin); Files.WriteInt(r, ymax);
		Files.Register(file)
	END MakeFont;
	
	PROCEDURE GetChar (font: Font; no: INTEGER; VAR pat: LONGINT);
		VAR glyph: OType.Glyph; p, bytes: LONGINT; data: RasterData;
	BEGIN
		glyph := font.glyph;
		OType.LoadGlyph(font.inst, glyph, no, {OType.Hinted, OType.Width, OType.Raster});
		p := font.pattern;
		SYSTEM.PUT(p, CHR(glyph.awx)); INC(p);
		SYSTEM.PUT(p, SHORT(glyph.hbx)); INC(p);
		SYSTEM.PUT(p, SHORT(glyph.hby)); INC(p);
		pat := p;
		SYSTEM.PUT(p, CHR(glyph.rw)); INC(p);
		SYSTEM.PUT(p, CHR(glyph.rh)); INC(p);
		IF glyph.rw * glyph.rh # 0 THEN
			data.rect := FillRect; data.adr := p; data.bpr := (glyph.rw+7) DIV 8;
			bytes := glyph.rh * data.bpr;
			REPEAT SYSTEM.PUT(p, 0X); INC(p) UNTIL p = data.adr + bytes;
			OType.EnumRaster(glyph, data)
		END;
		font.pattern := p
	END GetChar;
	
	PROCEDURE GetCharObj (lib: Objects.Library; ref: INTEGER; VAR obj: Objects.Object);
		VAR font: Font; adr, pat: LONGINT; no: INTEGER; ch: CHAR; s: SHORTINT;
	BEGIN
		font := lib(Font);
		adr := SYSTEM.ADR(font.mem[0]);
		SYSTEM.GET(adr + 4*ref, pat);
		IF pat = 0 THEN
			no := OType.UnicodeToGlyph(font.inst.font, OType.CharToUnicode[ref]);
			IF no # 0 THEN
				GetChar(font, no, pat)
			ELSIF ref = 9 THEN	(* substitute default tab character *)
				no := OType.UnicodeToGlyph(font.inst.font, OType.CharToUnicode[ORD("I")]);
				OType.LoadGlyph(font.inst, font.glyph, no, {OType.Hinted, OType.Width});
				pat := font.pattern;
				SYSTEM.PUT(pat, CHR(8*font.glyph.awx));
				SYSTEM.PUT(pat+1, LONG(LONG(0)));
				pat := pat+3;
				font.pattern := pat+2
			ELSE
				pat := adr + 4*100H + 3	(* address of default pattern *)
			END;
			SYSTEM.PUT(adr + 4*ref, pat)
		END;
		SYSTEM.GET(pat-3, ch); Char.dx := ORD(ch);
		SYSTEM.GET(pat-2, s); Char.x := s;
		SYSTEM.GET(pat-1, s); Char.y := s;
		SYSTEM.GET(pat, ch); Char.w := ORD(ch);
		SYSTEM.GET(pat+1, ch); Char.h := ORD(ch);
		Char.pat := pat;
		obj := Char
	END GetCharObj;
	
	PROCEDURE LoadFont (font: Font);
		VAR i, size, n, upm, adr: LONGINT; ch: CHAR; name: ARRAY 32 OF CHAR; dpi, h: INTEGER; otfont: OType.Font;
	BEGIN
		(* extract name, size and resolution from font name *)
		i := 0; ch := font.name[0];
		WHILE ("A" <= CAP(ch)) & (CAP(ch) <= "Z") DO
			name[i] := ch; INC(i); ch := font.name[i]
		END;
		name[i] := 0X; size := 0;
		WHILE ("0" <= ch) & (ch <= "9") DO
			size := 10*size + ORD(ch) - ORD("0");
			INC(i); ch := font.name[i]
		END;
		IF ("A" <= CAP(ch)) & (CAP(ch) <= "Z") THEN
			CASE CAP(ch) OF
			| "B": Strings.Append(name, "Bold")
			| "I": Strings.Append(name, "Italic")
			| "J": Strings.Append(name, "BoldItalic")
			| "M": Strings.Append(name, "Medium")
			ELSE
			END;
			WHILE (ch # 0X) & (ch # ".") DO
				INC(i); ch := font.name[i]
			END
		END;
		dpi := ScreenDPI;
		IF ch = "." THEN
			ch := font.name[i+3];
			IF ch = "2" THEN dpi := 200
			ELSIF ch = "3" THEN dpi := 300
			ELSIF ch = "6" THEN dpi := 600
			END
		END;
		
		otfont := OType.Open(name);
		IF otfont = NIL THEN
			Fonts.Default.Load(font)	(* no corresponding OpenType font found => let Fonts module substitute *)
		ELSE
			OType.GetInstance(otfont, 40H*size, dpi, dpi, OType.Identity, font.inst);
			NEW(font.glyph); OType.InitGlyph(font.glyph, otfont);
			
			(* compute number of usable glyphs *)
			n := 1;	(* glyph 0 for undefined characters *)
			FOR i := 0 TO 0FFH DO
				IF OType.UnicodeToGlyph(otfont, OType.CharToUnicode[i]) # 0 THEN
					INC(n)
				END
			END;
			
			(* initialize font fields *)
			font.type := Fonts.font; font.GetObj := GetCharObj;
			upm := 40H*LONG(otfont.head.unitsPerEm);
			h := otfont.hhea.ascender + otfont.hhea.descender + otfont.hhea.lineGap;
			font.height := SHORT(OTInt.MulDiv(h, font.inst.yppm, upm));
			font.minX := SHORT(OTInt.MulDiv(otfont.head.xMin, font.inst.xppm, upm));
			font.minY := SHORT(OTInt.MulDiv(otfont.head.yMin, font.inst.yppm, upm));
			font.maxX := SHORT(OTInt.MulDiv(otfont.head.xMax, font.inst.xppm, upm));
			font.maxY := SHORT(OTInt.MulDiv(otfont.head.yMax, font.inst.yppm, upm));
			
			(* allocate space for index, metrics and patterns *)
			NEW(font.mem, 4*100H + n * (10 + ((font.maxX - font.minX) DIV 8 + 1) * (font.maxY - font.minY)));
			adr := SYSTEM.ADR(font.mem[0]);
			font.pattern := adr + 4*100H;
			WHILE adr < font.pattern DO SYSTEM.PUT(adr, LONG(LONG(0))); INC(adr, 4) END;	(* mark as invalid *)
			GetChar(font, 0, adr)
		END
	END LoadFont;
	
	PROCEDURE *Load (lib: Objects.Library);
		VAR font: Font; i: LONGINT; ch: CHAR; name: ARRAY 64 OF CHAR;
	BEGIN
		font := lib(Font);
		IF Files.Old(font.name) # NIL THEN	(* raster font file exists *)
			Fonts.Default.Load(font)
		ELSE
			i := -1; REPEAT INC(i); ch := font.name[i]; name[i] := ch UNTIL ch = 0X;
			IF (i >= 8) & (name[i-8] = ".") & (name[i-7] = "M") & (name[i-6] = "d") THEN
				name[i-7] := "P"; name[i-6] := "r";
				IF Files.Old(name) # NIL THEN	(* printer font file exists *)
					Fonts.Default.Load(font)
				ELSE
					LoadFont(font)
				END
			ELSE
				LoadFont(font)
			END
		END
	END Load;
	
	PROCEDURE *New (): Objects.Library;
		VAR font: Font;
	BEGIN
		NEW(font); font.Load := Load; font.GetObj := Fonts.Default.GetObj;
		RETURN font
	END New;
	
	(** install new library type for "*.Fnt" **)
	PROCEDURE Install*;
	BEGIN
		Texts.WriteString(W, "Installing dynamic OpenType fonts"); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf);
		Objects.Register("Fnt", New)
	END Install;
	
	(**
		command for creating Oberon raster font files from an OpenType font file
		syntax:
			file - name of OpenType font file (e.g. "Arialb.TTF")
			font - Oberon name (e.g. "Arial")
			[style] - optional style character for Oberon name (e.g. "b")
			{size} - list of point sizes (e.g. "8 10 12 14 16 20 24")
			{dev} - list of device specifiers (e.g. "Scn Pr2 Pr3 Pr6")
	**)
	PROCEDURE Make*;
		VAR
			s: Texts.Scanner; font: OType.Font; name, fname, str: ARRAY 32 OF CHAR; style: CHAR; sizes, i: LONGINT;
			size: ARRAY 16 OF INTEGER; res: INTEGER; inst: OType.Instance;
	BEGIN
		Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(s);
		IF s.class IN {Texts.Name, Texts.String} THEN
			font := OType.Open(s.s);
			IF font # NIL THEN
				OType.InitGlyph(Glyph, font);
				Texts.Scan(s);
				IF s.class IN {Texts.Name, Texts.String} THEN
					COPY(s.s, name);
					Texts.Scan(s);
					IF s.class IN {Texts.Name, Texts.String} THEN
						style := s.s[0];
						Texts.Scan(s)
					ELSE
						style := 0X
					END;
					sizes := 0;
					WHILE s.class = Texts.Int DO
						ASSERT(sizes < LEN(size));
						size[sizes] := SHORT(s.i); INC(sizes);
						Texts.Scan(s)
					END;
					WHILE s.class IN {Texts.Name, Texts.String} DO
						IF s.s = "Scn" THEN res := ScreenDPI
						ELSIF s.s = "Pr2" THEN res := 200
						ELSIF s.s = "Pr3" THEN res := 300
						ELSIF s.s = "Pr6" THEN res := 600
						ELSE res := 0
						END;
						IF res # 0 THEN
							FOR i := 0 TO sizes-1 DO
								COPY(name, fname);
								Strings.IntToStr(size[i], str);
								Strings.Append(fname, str);
								IF style # 0X THEN Strings.AppendCh(fname, style) END;
								Strings.AppendCh(fname, "."); Strings.Append(fname, s.s); Strings.Append(fname, ".Fnt");
								OType.GetInstance(font, 40H*size[i], res, res, OType.Identity, inst);
								Texts.WriteString(W, fname); Texts.Append(Oberon.Log, W.buf);
								MakeFont(inst, fname);
								Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
							END
						END;
						Texts.Scan(s)
					END
				END
			END
		END
	END Make;
	

BEGIN
	NEW(Glyph);
	NEW(Char);
	Texts.OpenWriter(W)
END OTFonts.


OTFonts.Make Verdana.TTF Verdana 10 12 Scn ~
