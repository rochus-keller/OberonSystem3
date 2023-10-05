(* OBERON System 3, Release 2.3.

Copyright 1999 ETH Zürich Institute for Computer Systems, 
ETH Center, CH-8092 Zürich. e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract. The full text can be downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE PSPrinter;	(** portable *)  (*UNIX version: JT 11.5.90, RC 2.7.93,  JS 29.4.9, Windows version: jm 20.12.95 *)

	(*
		jm 20.12.95 EPS support added
		ps 4.8.96 added border to page (left, right: 2cm / top, bottom: 1.5 cm)
	*)
	
	IMPORT Files, Printer, Objects, Fonts, Texts, Strings, Display, Oberon, Pictures;

	CONST
		N = 20;	(* max spline points *)
		maxFonts = 64;
		headerFileName = "PSHeader.Text";
		bold = 0; italics = 1; medium = 2;
		oneup = 0;  twoup = 1;  fourup = 2;
		
	TYPE
		Name* = ARRAY 32 OF CHAR;
		
		PSPrinter* = POINTER TO PSPrinterDesc;
		PSPrinterDesc* = RECORD (Printer.PrinterDesc)
			Escape*: PROCEDURE (P: Printer.Printer; s: ARRAY OF CHAR);
			printF*: Files.File;
			eps*: BOOLEAN; (** Is EPS output being written? *)
			pno*: INTEGER; (** Current page being printer on (starts with 1) *)
			
			l, t, r, b: LONGINT;
			sx, sy: INTEGER; (* current string pos *)
			mode, location: SHORTINT
		END;
		
		FontDesc = RECORD
			name: Name;
			used: ARRAY 8 OF SET;
		END;
		RealVector = ARRAY N OF REAL;
		Poly = RECORD a, b, c, d, t: REAL END ;
		PolyVector = ARRAY N OF Poly;

	TYPE
		MetricDesc = RECORD
			dx, x, y, w, h: INTEGER;
		END;
		Metrics = POINTER TO RECORD (Objects.IndexDesc)
			metrics: ARRAY 256 OF MetricDesc;
		END;
		FontDef = POINTER TO FontDefDesc;
		FontDefDesc = RECORD
			name: ARRAY 64 OF CHAR;
			family: ARRAY 32 OF CHAR;
			size: INTEGER;
			attr: CHAR;
			next: FontDef
		END;

	VAR
			(* to do: many of these variables should be local to the printer object *)
		fontTable: ARRAY maxFonts OF FontDesc;
		fontIndex, curFont: INTEGER;
		listFont: Name;
		headerT: Texts.Text;
		bodyF: Files.File;
		bodyR: Files.Rider;
		ppos: LONGINT;
		hexArray: ARRAY 17 OF CHAR;
		curR, curG, curB, setR, setG, setB: INTEGER;

		metric: Objects.Library;
		fontMapDict: FontDef;
		fontMapDictN: INTEGER;
	    theChar: Fonts.Char;
		default: Objects.Name;
		curRes: LONGINT;
		
	(* -- Output procedures -- *)

	PROCEDURE Ch (VAR R: Files.Rider; ch: CHAR);
	BEGIN
		Files.Write(R, ch)
	END Ch;

	PROCEDURE Str (VAR R: Files.Rider; s: ARRAY OF CHAR);
		VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE s[i] # 0X DO Ch(R, s[i]); INC(i) END;
	END Str;

	PROCEDURE Int (VAR R: Files.Rider; i: LONGINT);
		VAR j: LONGINT;
	BEGIN
		IF i = 0 THEN Ch(R, "0") ELSIF i < 0 THEN i := -i; Ch(R, "-") END;
		j := 1;
		WHILE (i DIV j) # 0 DO j := j * 10 END;
		WHILE j >= 10 DO j := j DIV 10; Ch(R, CHR(30H + (i DIV j) MOD 10)) END;
	END Int;

	PROCEDURE Hex2(VAR R: Files.Rider; ch: CHAR);
	BEGIN
		Ch(R, hexArray[ORD(ch) DIV 16]);
		Ch(R, hexArray[ORD(ch) MOD 16]);
	END Hex2;

	PROCEDURE Real(VAR R: Files.Rider; x: REAL);
	VAR
		n, i, xi: INTEGER;
		d: ARRAY 4 OF CHAR;
	BEGIN
		xi := SHORT(ENTIER(x));
		IF x = xi THEN Int(R, xi); RETURN END;
		IF x < 0 THEN Files.Write(R, "-"); x := -x; xi := -xi END;
		Int(R, xi); Files.Write(R, "."); x := x-xi;
		n := SHORT(ENTIER(x*1000));
		i := 0;
		REPEAT
			d[i] := CHR(n MOD 10+30H); n := n DIV 10; INC(i)
		UNTIL i = 3;
		WHILE i > 0 DO DEC(i); Files.Write(R, d[i]) END
	END Real;

	PROCEDURE Ln(VAR R: Files.Rider);
	BEGIN
		Ch(R, 0DX);
		Ch(R, 0AX);
	END Ln;

	(* -- Error handling -- *)

	PROCEDURE Error(s0, s1: ARRAY OF CHAR);
		VAR error, f: ARRAY 32 OF CHAR;
	BEGIN COPY(s0, error); COPY(s1, f); HALT(99)
	END Error;

	(* -- Bounding Box -- *)
	
	PROCEDURE Min(x, y: LONGINT): LONGINT;
	BEGIN IF x < y THEN RETURN x ELSE RETURN y END
	END Min;

	(* Increase the size of the bounding box. *)
	PROCEDURE Box*(P: PSPrinter; x, y, w, h: LONGINT);
	BEGIN
		IF x < P.l THEN P.l := x END;
		IF x + w - 1 > P.r THEN P.r := x + w - 1 END;
		IF y < P.b THEN P.b := y END;
		IF y + h - 1 > P.t THEN P.t := y + h - 1 END;
	END Box;
	
	(* -- Font Mapping -- *)

	PROCEDURE SetMappedFont(VAR fontR: Files.Rider; fname: ARRAY OF CHAR);
		VAR family: ARRAY 7 OF CHAR;
	BEGIN
		COPY(fname, family);
		Ch(fontR, "/"); Str(fontR, fname); 
		IF (family = "Syntax") OR (family = "Oberon") OR (family = "Default") THEN Str(fontR, " DefineSMapFont")
		ELSE Str(fontR, " DefineMapFont") END;
		Ln(fontR); Ln(fontR);
	END SetMappedFont;

	PROCEDURE SetBitmapFont(VAR fontR, R: Files.Rider; fd: FontDesc; pRes: INTEGER);
		CONST fontFileId = 0DBX;
		TYPE
			RunRec = RECORD beg, end: INTEGER END;
			Metrics = RECORD dx, x, y, w, h: INTEGER END;

		VAR
			ch: CHAR;
			pixmapDX, n, b: LONGINT;
			k, m: INTEGER;
			height, minX, maxX, minY, maxY: INTEGER;
			nOfBoxes, nOfRuns: INTEGER;
			run: ARRAY 16 OF RunRec;
			metrics: ARRAY 256 OF Metrics;

		PROCEDURE Flip(ch: CHAR): CHAR;
			VAR i, s, d: INTEGER;
		BEGIN
			i := 0; s := ORD(ch); d := 0;
			WHILE i < 8 DO
				IF s MOD 2 = 1 THEN d := d * 2 + 1 ELSE d := d * 2 END;
				s := s DIV 2;
				INC(i)
			END;
			RETURN CHR(d);
		END Flip;

		PROCEDURE Name(m: INTEGER);
		BEGIN
			CASE m OF
			| 9: Str(fontR, "tab")
			| 32: Str(fontR, "space")
			| 33: Str(fontR, "exclam")
			| 34: Str(fontR, "quotedbl")
			| 35: Str(fontR, "numbersign")
			| 36: Str(fontR, "dollar")
			| 37: Str(fontR, "percent")
			| 38: Str(fontR, "ampersand")
			| 39: Str(fontR, "quotesingle")
			| 40: Str(fontR, "parenleft")
			| 41: Str(fontR, "parenright")
			| 42: Str(fontR, "asterisk")
			| 43: Str(fontR, "plus")
			| 44: Str(fontR, "comma")
			| 45: Str(fontR, "minus")
			| 46: Str(fontR, "period")
			| 47: Str(fontR, "slash")
			| 48: Str(fontR, "zero")
			| 49: Str(fontR, "one")
			| 50: Str(fontR, "two")
			| 51: Str(fontR, "three")
			| 52: Str(fontR, "four")
			| 53: Str(fontR, "five")
			| 54: Str(fontR, "six")
			| 55: Str(fontR, "seven")
			| 56: Str(fontR, "eight")
			| 57: Str(fontR, "nine")
			| 58: Str(fontR, "colon")
			| 59: Str(fontR, "semicolon")
			| 60: Str(fontR, "less")
			| 61: Str(fontR, "equal")
			| 62: Str(fontR, "greater")
			| 63: Str(fontR, "question")
			| 64: Str(fontR, "at")
			| 65..90: Ch(fontR, CHR(m))
			| 91: Str(fontR, "bracketleft")
			| 92:  Str(fontR, "backslash")
			| 93: Str(fontR, "bracketright")
			| 94: Str(fontR, "arrowup")
			| 95: Str(fontR, "underscore") 
			| 96: Str(fontR, "grave")
			| 97..122: Ch(fontR, CHR(m))
			| 123: Str(fontR, "braceleft")
			| 124: Str(fontR, "bar")
			| 125: Str(fontR, "braceright")
			| 126: Str(fontR, "tilde")
			| 128: Str(fontR, "Adieresis")
			| 129: Str(fontR, "Odieresis")
			| 130: Str(fontR, "Udieresis")
			| 131: Str(fontR, "adieresis")
			| 132: Str(fontR, "odieresis")
			| 133: Str(fontR, "udieresis")
			| 134: Str(fontR, "acircumflex")
			| 135: Str(fontR, "ecircumflex")
			| 136: Str(fontR, "icircumflex")
			| 137: Str(fontR, "oicircumflex")
			| 138: Str(fontR, "uicircumflex")
			| 139: Str(fontR, "agrave")
			| 140: Str(fontR, "egrave")
			| 141: Str(fontR, "igrave")
			| 142: Str(fontR, "ograve")
			| 143: Str(fontR, "ugrave")
			| 144: Str(fontR, "eacute")
			| 145: Str(fontR, "edieresis")
			| 146: Str(fontR, "idieresis")
			| 147: Str(fontR, "ccedilla")
			| 148: Str(fontR, "aacute")
			| 149: Str(fontR, "ntilde")
			| 150: Str(fontR, "germandbls")
			| 155: Str(fontR, "endash")
			| 159: Str(fontR, "hyphen")
			ELSE
				Str(fontR, "ascii");
				Ch(fontR, CHR(30H + (m DIV 100) MOD 10));
				Ch(fontR, CHR(30H + (m DIV 10) MOD 10));
				Ch(fontR, CHR(30H + m MOD 10))
			END
		END Name;

	BEGIN
		Str(fontR, "% Conversion of the Oberon font "); Str(fontR, fd.name); Ln(fontR);
		Files.Read(R, ch);
		IF ch = fontFileId THEN
			Files.Read(R, ch); Str(fontR, "% abstraction: "); Int(fontR, ORD(ch)); 
			Files.Read(R, ch); Str(fontR, ", family: "); Ch(fontR, ch); 
			Files.Read(R, ch); Str(fontR, ", variant: "); Int(fontR, ORD(ch)); Ln(fontR);
			Files.ReadInt(R, height); Str(fontR, "% height: "); Int(fontR, height); Ln(fontR); Ln(fontR);
			Files.ReadInt(R, minX); Files.ReadInt(R, maxX);
			Files.ReadInt(R, minY); Files.ReadInt(R, maxY);
			Files.ReadInt(R, nOfRuns);
			nOfBoxes := 0; k := 0;
			WHILE k # nOfRuns DO
				Files.ReadInt(R, run[k].beg); Files.ReadInt(R, run[k].end);
				INC(nOfBoxes, run[k].end - run[k].beg);
				INC(k)
			END;
			Str(fontR, "9 dict begin"); Ln(fontR); Ln(fontR);
			Str(fontR, "/FontType 3 def"); Ln(fontR);
			Str(fontR, "/FontMatrix [ 72 "); Int(fontR, pRes); Str(fontR, " div "); Str(fontR, " factor1 div 0 0 ");
			Str(fontR, "72 "); Int(fontR, pRes); Str(fontR, " div "); Str(fontR, " factor2 div 0 0");
			Str(fontR, "] def"); Ln(fontR);
			Str(fontR, "/FontBBox [");  
			Int(fontR, minX); Ch(fontR, " ");
			Int(fontR, minY); Ch(fontR, " ");
			Int(fontR, maxX); Ch(fontR, " ");
			Int(fontR, maxY);
			Str(fontR, "] def"); Ln(fontR); Ln(fontR);
			Str(fontR, "/Encoding 256 array def"); Ln(fontR);
			Str(fontR, "0 1 255 {Encoding exch /.notdef put} for"); Ln(fontR);
			Str(fontR, "Encoding OberonEncoding /Encoding exch def"); Ln(fontR);
			Ln(fontR);
			Str(fontR, "/CharData "); Int(fontR, nOfBoxes+1);
			Str(fontR, " dict def"); Ln(fontR);
			Str(fontR, "CharData begin"); Ln(fontR);
			k := 0; m := 0;
			WHILE k < nOfRuns DO
				m := run[k].beg;
				WHILE m < run[k].end DO
					Files.ReadInt(R, metrics[m].dx);
					Files.ReadInt(R, metrics[m].x); Files.ReadInt(R, metrics[m].y);
					Files.ReadInt(R, metrics[m].w); Files.ReadInt(R, metrics[m].h);
					INC(m);
				END;
				INC(k)
			END;
			Str(fontR, "/.notdef"); Str(fontR, " [");
			Int(fontR, metrics[32].w); Str(fontR, " 0 0 0 0 1 1 0 0"); Ln(fontR);
			Str(fontR, "<>] bdef"); Ln(fontR);
			k := 0; m := 0;
			WHILE k < nOfRuns DO
				m := run[k].beg;
				WHILE m < run[k].end DO
					IF m MOD 32 IN fd.used[m DIV 32] THEN
						Str(fontR, "/"); Name(m); Str(fontR, " [");
						Int(fontR, metrics[m].dx); Str(fontR, " ");
						Int(fontR, metrics[m].x); Str(fontR, " "); Int(fontR, metrics[m].y); Str(fontR, " ");
						Int(fontR, metrics[m].x + metrics[m].w); Str(fontR, " ");
						Int(fontR, metrics[m].y + metrics[m].h); Str(fontR, " ");
						IF metrics[m].w > 0 THEN Int(fontR, metrics[m].w); ELSE Int(fontR, 1) END; Str(fontR, " ");
						IF metrics[m].h > 0 THEN Int(fontR, metrics[m].h); ELSE Int(fontR, 1) END; Str(fontR, " ");
						Int(fontR, -metrics[m].x); Str(fontR, " "); Int(fontR, -metrics[m].y); Ln(fontR);
						Str(fontR, "<");
						pixmapDX := (metrics[m].w + 7) DIV 8;
						n := pixmapDX * metrics[m].h;
						b := 0;
						WHILE b < n DO
							Files.Read(R, ch); Hex2(fontR, Flip(ch));
							INC(b);
							IF b MOD 32 = 0 THEN Ln(fontR); Str(fontR, " ") END
						END;
						Str(fontR, ">] bdef"); Ln(fontR);
					ELSE
						n := (metrics[m].w + 7) DIV 8 * metrics[m].h;
						b := 0; WHILE b < n DO Files.Read(R, ch); INC(b) END;
					END;
					INC(m);
				END;
				INC(k)
			END;
			Str(fontR, "  end"); Ln(fontR); Ln(fontR);
			Str(fontR, "/BuildGlyph {GlobalBuildGlyph} bdef"); Ln(fontR);
			Str(fontR, "/BuildChar {GlobalBuildChar} bdef"); Ln(fontR); Ln(fontR);
			Str(fontR, "/imageMaskMatrix [1 0 0 1 0 0] bdef"); Ln(fontR); Ln(fontR);
			Str(fontR, "currentdict"); Ln(fontR); Ln(fontR);
			Str(fontR, "end"); Ln(fontR); Ln(fontR);
			Ch(fontR, "/"); Str(fontR, fd.name);
			Str(fontR, " exch definefont pop"); Ln(fontR); Ln(fontR);
		END;
	END SetBitmapFont;

	PROCEDURE DefineFont(VAR fontR: Files.Rider; fd: FontDesc; echo: BOOLEAN);
		VAR
			family, name: ARRAY 32 OF CHAR;
			i, size, dpi: INTEGER;
			f: Files.File; R: Files.Rider;
			fontDef: FontDef;
			attr: CHAR;
	BEGIN
		dpi := SHORT(914400 DIV Printer.current.Unit);
		COPY(fd.name, name); i := 0; size := 0;
		WHILE (name[i] # 0X) & (name[i] # ".") & ((name[i] < "0") OR (name[i] > "9")) DO
			family[i] := name[i]; INC(i)
		END;
		family[i] := 0X;
		size := 0;
		WHILE (name[i] >= "0") & (name[i] <= "9") DO size := size * 10 + ORD(name[i]) - 30H; INC(i) END;
		attr := 0X;
		WHILE (name[i] # 0X) & (name[i] # ".") DO attr := CAP(name[i]); INC(i) END;
		fontDef := fontMapDict;
		WHILE (fontDef # NIL) & ~((fontDef.size = size) & (fontDef.attr = attr) & (fontDef.family = family)) DO
			fontDef := fontDef.next
		END;
		IF fontDef = NIL THEN
			NEW(fontDef); fontDef.next := fontMapDict; fontMapDict := fontDef; INC(fontMapDictN);
			COPY(name, fontDef.name); COPY(family, fontDef.family);
			fontDef.size := size; fontDef.attr := attr
		END;
		IF ~echo THEN RETURN END;
		IF (name[i] # ".") OR (name[i+1] # "S") OR (name[i+2] # "c") OR (name[i+3] # "n") THEN
			SetMappedFont (fontR, fd.name);
		ELSE
			name[i+1] := "P"; name[i+2] := "r";  name[i+3] := CHR((dpi DIV 100)+ORD("0"));
			f := Files.Old(name);
			IF f = NIL THEN
				SetMappedFont (fontR, fd.name);
			ELSE
				Files.Set(R, f, 0); SetBitmapFont(fontR, R, fd, dpi)
			END;
		END;
	END DefineFont;

	(* -- Metric Font loading -- *)

	PROCEDURE ParseName (VAR name, family: ARRAY OF CHAR; VAR size: LONGINT; VAR style: SET; VAR class: ARRAY OF CHAR);
	VAR i, j: INTEGER;
	BEGIN
		size := 0; style := {}; i := 0;
		WHILE (name[i] > "9") OR (name[i] = " ") DO family[i] := name[i]; INC(i) END;
		family[i] := 0X;
		WHILE ("0" <= name[i]) & (name[i] <= "9") DO size := 10*size + (ORD(name[i]) - 30H); INC(i) END;
		WHILE (name[i] # 0X) & (name[i] # ".") DO
			CASE CAP(name[i]) OF
				| "I": INCL(style, italics); name[i] := "i"
				| "B": INCL(style, bold); name[i] := "b"
				| "M": INCL(style, medium); name[i] := "m"
			ELSE
			END;
			INC(i)
		END;
		j := 0;
		INC(i); WHILE (name[i] # 0X) & (name[i] # ".") DO class[j] := name[i]; INC(i); INC(j) END;
		class[j] := 0X;
	END ParseName;

	PROCEDURE BuildName (family: ARRAY OF CHAR; size: LONGINT; style: SET; class: ARRAY OF CHAR; VAR name: ARRAY OF CHAR);
	VAR i, j: INTEGER;
	
		(* Convert an integer into a string *)
		PROCEDURE IntToStr(i: LONGINT; VAR j: INTEGER; VAR s: ARRAY OF CHAR);
		VAR k: INTEGER; x0: LONGINT; a: ARRAY 10 OF CHAR;
		BEGIN
			IF i > 0 THEN
				k := 0; x0 := i;
				REPEAT
					a[k] := CHR(x0 MOD 10 + 30H); x0 := x0 DIV 10; INC(k)
				UNTIL x0 = 0;
				REPEAT DEC(k); s[j] := a[k]; INC(j) UNTIL k = 0
			END
		END IntToStr;
	
	BEGIN
		i := 0;
		j := 0; WHILE family[j] # 0X DO name[i] := family[j]; INC(i); INC(j) END;
		IntToStr(size, i, name);
		IF italics IN style THEN name[i] := "i"; INC(i)
		ELSIF medium IN style THEN name[i] := "m"; INC(i)
		ELSIF bold IN style THEN name[i] := "b"; INC(i)
		END;
		name[i] := "."; INC(i);
		j := 0; WHILE class[j] # 0X DO name[i] := class[j]; INC(i); INC(j) END;
		name[i] := "."; INC(i);
		name[i] := "F"; INC(i);
		name[i] := "n"; INC(i);
		name[i] := "t"; INC(i);
		name[i] := 0X
	END BuildName;

	PROCEDURE Substitute(L: Fonts.Font);
	BEGIN
		L.type := Fonts.substitute;
		L.height := Fonts.Default.height;
		L.minX := Fonts.Default.minX; L.maxX := Fonts.Default.maxX;
		L.minY := Fonts.Default.minY; L.maxY := Fonts.Default.maxY;
		L.ind := Fonts.Default.ind
	END Substitute;

PROCEDURE Load(F: Fonts.Font; VAR R: Files.Rider; subst: ARRAY OF CHAR; type: SHORTINT);
	TYPE
		RunRec = RECORD beg, end: INTEGER END;
		BoxRec = RECORD dx, x, y, w, h: INTEGER END;
	VAR
		raster: Metrics;
		nofRuns, nofBoxes: INTEGER;
		k, l, m: INTEGER;
		ch: CHAR;
		run: ARRAY 16 OF RunRec;
		box: ARRAY 256 OF BoxRec;

		PROCEDURE DummyCh (m: INTEGER);
		VAR raster: Metrics;
		BEGIN
			raster := F.ind(Metrics);
			raster.metrics[m].dx := 0;
			raster.metrics[m].x := 0; raster.metrics[m].y := 0;
			raster.metrics[m].w := 0; raster.metrics[m].h := 0
		END DummyCh;

	BEGIN
		F.type := type;
		Files.Read(R, ch); (*family*)
		Files.Read(R, ch); (*variant*)
		NEW(raster); F.ind := raster;
		Files.ReadInt(R, F.height);
		Files.ReadInt(R, F.minX); Files.ReadInt(R, F.maxX);
		Files.ReadInt(R, F.minY); Files.ReadInt(R, F.maxY);
		Files.ReadInt(R, nofRuns);
		nofBoxes := 0; k := 0;
		WHILE k # nofRuns DO
			Files.ReadInt(R, run[k].beg); Files.ReadInt(R, run[k].end);
			nofBoxes := nofBoxes + run[k].end - run[k].beg;
			INC(k);
		END;
		l := 0;
		WHILE l # nofBoxes DO
			Files.ReadInt(R, box[l].dx);
			Files.ReadInt(R, box[l].x); Files.ReadInt(R, box[l].y);
			Files.ReadInt(R, box[l].w); Files.ReadInt(R, box[l].h);
			INC(l);
		END;
		k := 0; l := 0; m := 0;
		WHILE k < nofRuns DO
			WHILE m < run[k].beg DO DummyCh(m); INC(m) END;
			WHILE m < run[k].end DO
				raster.metrics[m].dx := box[l].dx;
				raster.metrics[m].x := box[l].x;
				raster.metrics[m].y := box[l].y;
				raster.metrics[m].w := box[l].w; raster.metrics[m].h := box[l].h;
				INC(l); INC(m);
			END;
			INC(k);
		END;
		WHILE m < 256 DO DummyCh(m); INC(m) END;
	END Load;

	PROCEDURE GetCharObj (L: Objects.Library; ref: INTEGER; VAR obj: Objects.Object);
	VAR raster: Metrics;
	BEGIN
		raster := L.ind(Metrics);
		theChar.dx := raster.metrics[ref].dx;
		theChar.x := raster.metrics[ref].x;
		theChar.y := raster.metrics[ref].y;
		theChar.w := raster.metrics[ref].w;
		theChar.h := raster.metrics[ref].h;
		obj := theChar;
	END GetCharObj;
	
	PROCEDURE OpenLib (L: Objects.Library);
	VAR f: Files.File; R: Files.Rider; id: CHAR;
		family, class, tmp: Objects.Name; prClass: ARRAY 4 OF CHAR; size, i, j: LONGINT; style: SET;
	BEGIN
		WITH L: Fonts.Font DO
			ParseName(L.name, family, size, style, class);	(* take name apart *)
			IF family = "Default" THEN
				COPY(default, family); BuildName(family, size, style, class, L.name)
			END;
			IF (class[0] # "M") OR (class[1] # "d") THEN Substitute(L)
			ELSE
				COPY(class, prClass); prClass[0] := "P"; prClass[1] := "r";
				BuildName(family, size, style, prClass, tmp);
				f := Files.Old(tmp);
				IF f # NIL THEN
					Files.Set(R, f, 0); Files.Read(R, id);
					IF id = Fonts.FontId THEN Files.Read(R, L.type);
						IF L.type = Fonts.font THEN
							Load(L, R, L.name, Fonts.metric);	(* only read the metrics *)
							RETURN
						END
					END
				END;
				
				f := Files.Old(L.name);
				IF f # NIL THEN
					Files.Set(R, f, 0); Files.Read(R, id);
					IF id = Fonts.FontId THEN Files.Read(R, L.type);
						IF L.type = Fonts.metric THEN Load(L, R, L.name, Fonts.metric)
						ELSE Substitute(L)
						END
					ELSE Substitute(L)
					END
				ELSE Substitute(L)
				END;
			END
		END
	END OpenLib;

	PROCEDURE New (): Objects.Library;
	VAR F: Fonts.Font;
	BEGIN NEW(F);
		F.Load := OpenLib; F.GetObj := GetCharObj; RETURN F
	END New;

	(* -- Exported Procedures -- *)

	PROCEDURE GetDim(P: Printer.Printer;  label: ARRAY OF CHAR;  def: INTEGER;  VAR val: INTEGER);
	VAR v: REAL; S: Texts.Scanner;
	BEGIN
		Oberon.OpenScanner(S, label);
		IF (S.class = Texts.Int) OR (S.class = Texts.Real) THEN
			IF S.class = Texts.Int THEN v := S.i
			ELSE v := S.x
			END;
			Texts.Scan(S);
			IF S.class = Texts.Name THEN
				IF S.s = "cm" THEN v := v*360000.0
				ELSIF S.s = "mm" THEN v := v*36000.0
				ELSIF S.s = "in" THEN v := v*36000.0*25.4
				ELSE v := v*36000.0	(* default mm *)
				END
			ELSE v := v*36000.0	(* default mm *)
			END;
			val := SHORT(ENTIER(v/P.Unit + 0.5))
		ELSE
			val := SHORT(ENTIER(def*36000.0/P.Unit + 0.5))
		END
	END GetDim;
	
	PROCEDURE initMetrics(P: Printer.Printer;  register: BOOLEAN);
	VAR val: ARRAY 12 OF CHAR;  S: Texts.Scanner;
	BEGIN
		Oberon.OpenScanner(S, "PSPrinter.Resolution");
		IF S.class # Texts.Int THEN S.i := 300 END;	(* default *)
		
		IF register OR (S.i # curRes) THEN
			curRes := S.i;
			
			val := "Md#.Fnt";
			val[2] := CHR(48 + S.i DIV 100 MOD 10);
			Objects.Register(val, New);	(* e.g. Md3.Fnt *)
			val[0] := "P";  val[1] := "r";
			Objects.Register(val, New)	(* e.g. Pr3.Fnt *)
		END;
		P.Unit := 914400 DIV S.i;
		P.Depth := 24;

		GetDim(P, "PSPrinter.Width", 210, P.Width);
		GetDim(P, "PSPrinter.Height", 297, P.Height);
		GetDim(P, "PSPrinter.LeftMargin", 20, P.FrameX);
		GetDim(P, "PSPrinter.RightMargin", 20, P.FrameW);
		P.FrameW := P.Width-P.FrameX-P.FrameW;
		GetDim(P, "PSPrinter.BottomMargin", 15, P.FrameY);
		GetDim(P, "PSPrinter.TopMargin", 15, P.FrameH);
		P.FrameH := P.Height-P.FrameY-P.FrameH
	END initMetrics;

	PROCEDURE InitMetrics*(P: Printer.Printer);
	VAR M: Display.ControlMsg; N: Oberon.ControlMsg;
	BEGIN
		initMetrics(P, TRUE);
		IF Printer.current # NIL THEN
			N.id := Oberon.neutralize; M.F := NIL; Display.Broadcast(N);
			M.id := Display.newprinter; M.F := NIL; Display.Broadcast(M);
			M.id := Display.suspend; M.F := NIL; Display.Broadcast(M);
			M.id := Display.restore; M.F := NIL; Display.Broadcast(M)
		END
	END InitMetrics;
	
	PROCEDURE GetSuffix(VAR str(** in *), suf(** out *): ARRAY OF CHAR);
		VAR i, j, dot: LONGINT;
	BEGIN
		dot := -1; i := 0;
		WHILE str[i] # 0X DO
			IF str[i] = "." THEN dot := i END;
			INC(i)
		END;
		j := 0;
		IF dot > 0 THEN
			i := dot+1;
			WHILE str[i] # 0X DO
				suf[j] := str[i]; INC(j); INC(i)
			END
		END;
		suf[j] := 0X
	END GetSuffix;

	PROCEDURE SetColor;
	BEGIN
		IF (setR # curR) OR (setG # curG) OR (setB # curB) THEN
			setR := curR;  setG := curG;  setB := curB;
			Real(bodyR, setR/255); Ch(bodyR, " ");
			Real(bodyR, setG/255); Ch(bodyR, " ");
			Real(bodyR, setB/255); Ch(bodyR, " ");
			Str(bodyR, "u ");
			Ln(bodyR)
		END
	END SetColor;
	
	PROCEDURE ResetColor;
	BEGIN
		curR := 0; curG := 0; curB := 0;
		setR := 255;  setG := 255;  setB := 255	(* different from cur *)
	END ResetColor;

	PROCEDURE Open*(P: Printer.Printer; printer, options: ARRAY OF CHAR);
	VAR suffix: ARRAY 32 OF CHAR;  i: LONGINT;
	BEGIN
		WITH P: PSPrinter DO
			ResetColor;
			P.res := 1;	(* no such printer *)
			P.printF := Files.New(printer);
			IF P.printF # NIL THEN
				GetSuffix(printer, suffix);
				P.eps := (suffix = "EPS") OR (suffix = "eps");
				i := 0;  P.mode := oneup;  P.location := 0;
				WHILE (options[i] # 0X) & (options[i] # Oberon.OptionChar) DO
					IF options[i] = "l" THEN P.mode := twoup
					ELSIF options[i] = "d" THEN P.mode := fourup
					ELSIF options[i] = "e" THEN P.eps := TRUE
					END;
					INC(i)
				END;
				initMetrics(P, FALSE);
				fontMapDict := NIL; fontMapDictN := 0;
				P.l := MAX(LONGINT); P.r := MIN(LONGINT); P.t := MIN(LONGINT); P.b := MAX(LONGINT);
				
				NEW(headerT); Texts.Open(headerT, headerFileName);
				IF headerT.len > 0 THEN
					bodyF := Files.New(""); Files.Set(bodyR, bodyF, 0);
					fontIndex := -1; curFont := -1; listFont := ""; ppos := 0; P.pno := 1;
					P.res := 0
				ELSE
					Error("file not found", headerFileName)
				END
			END
		END
	END Open;
	
	PROCEDURE UseListFont*(P: Printer.Printer; name: ARRAY OF CHAR);
	BEGIN
		COPY(name, listFont); curFont := -1
	END UseListFont;

	(** Don't forget to update the bounding box of eps files by calling procedure Box. *)
	PROCEDURE Escape*(P: Printer.Printer; s: ARRAY OF CHAR);
	BEGIN
		WITH P: PSPrinter DO
			(* Don't make more that one page when making eps *)
			IF P.eps & (P.pno > 1) THEN RETURN END;
			SetColor;
			Str(bodyR, s)
		END
	END Escape;

	PROCEDURE ReplConst*(P: Printer.Printer; x, y, w, h: INTEGER);
	BEGIN
		WITH P: PSPrinter DO
			(* Don't make more that one page when making eps *)
			IF P.eps & (P.pno > 1) THEN RETURN END;
			IF (w > 0) & (h > 0) THEN
				SetColor;
				Box(P, x, y, w, h);
				Int(bodyR, x+1); Ch(bodyR, " ");
				Int(bodyR, y);  Ch(bodyR, " ");
				Int(bodyR, w-1); Ch(bodyR, " ");
				Int(bodyR, h-1); Str(bodyR, " l"); Ln(bodyR);
			END
		END
	END ReplConst;
		
	PROCEDURE StringSize(VAR s: ARRAY OF CHAR; fnt: Fonts.Font; VAR w, h, dsr: INTEGER);
	VAR p: INTEGER; obj: Objects.Object;
	BEGIN
		w := 0; h := 0; dsr := 0;
		p := 0;
		IF (metric = NIL) OR (fnt.name # metric.name) THEN metric := Printer.GetMetric(fnt) END;
		IF (metric # NIL) & (metric(Fonts.Font).type = Fonts.metric) THEN
			WHILE s[p] # 0X DO
				metric.GetObj(metric, ORD(s[p]), obj);
				INC(w, obj(Fonts.Char).dx);
				INC(p)
			END;
			h := metric(Fonts.Font).height;
			dsr := ABS(metric(Fonts.Font).minY);
		END
	END StringSize;

	PROCEDURE ContString*(P: Printer.Printer; s: ARRAY OF CHAR; fnt: Fonts.Font);
		VAR fNo, i, n, w, h, dsr: INTEGER; ch: CHAR; family: ARRAY 7 OF CHAR;

		PROCEDURE Use(ch: CHAR);
		BEGIN
			INCL(fontTable[curFont].used[ORD(ch) DIV 32], ORD(ch) MOD 32);
		END Use;

	BEGIN
		WITH P: PSPrinter DO
			(* Don't make more that one page when making eps *)
			IF P.eps & (P.pno > 1) THEN RETURN END;
			SetColor;
			StringSize(s, fnt, w, h, dsr);
			Box(P, P.sx - dsr, P.sy, w, h);
			INC(P.sx, w);
			IF (curFont < 0) OR (fontTable[curFont].name # fnt.name) THEN
				COPY(fnt.name, fontTable[fontIndex+1].name);
				i := 0; WHILE i < 8 DO fontTable[fontIndex+1].used[i] := {}; INC(i) END;		
				fNo := 0;
				WHILE fontTable[fNo].name # fnt.name DO INC(fNo) END;
				IF fNo > fontIndex THEN (* DefineFont(fname); *) fontIndex := fNo END;
				curFont := fNo; Ch(bodyR, "(");
				IF fontTable[curFont].name = listFont THEN
					Str(bodyR, "Courier8.Scn.Fnt")
				ELSE
					Str(bodyR, fontTable[curFont].name)
				END;
				Str(bodyR, ") f ")
			END;
			Ch(bodyR, "(");
			i := 0; ch := s[0];
			WHILE ch # 0X DO
				CASE ch OF
				| "(", ")", "\": Ch(bodyR, "\"); Ch(bodyR, ch); Use(ch);
				| 9X: Str(bodyR, "  "); Use(" ")	(* or Str("\tab") *)
				| 80X..95X, 0ABX:
					Str(bodyR, "\2"); n := ORD(ch)-128;
					Ch(bodyR, CHR(n DIV 8 + 48)); Ch(bodyR, CHR(n MOD 8 + 48)); Use(ch)
				| 9FX: COPY(fontTable[curFont].name, family);
					IF family = "Courie" THEN Ch(bodyR, " ") ELSE Str(bodyR, "  ") END; Use(" ");
				ELSE
					Ch(bodyR, ch); Use(ch);
				END ;
				INC(i); ch := s[i];
			END;
			Str(bodyR, ") s"); Ln(bodyR)
		END
	END ContString;
	
	PROCEDURE String*(P: Printer.Printer; x, y: INTEGER; s: ARRAY OF CHAR; fnt: Fonts.Font);
	VAR w, h, dsr: INTEGER;
	BEGIN
		WITH P: PSPrinter DO
			(* Don't make more that one page when making eps *)
			IF P.eps & (P.pno > 1) THEN RETURN END;
			SetColor;
			StringSize(s, fnt, w, h, dsr);
			Box(P, x - dsr, y, w, h);
			P.sx := x + w; P.sy := y;

			Int(bodyR, x); Ch(bodyR, " ");
			Int(bodyR, y); Str(bodyR, " m "); ContString(P, s, fnt)
		END
	END String;

	PROCEDURE ReplPattern*(P: Printer.Printer; x, y, w, h, col: INTEGER);
	BEGIN
		WITH P: PSPrinter DO
			(* Don't make more that one page when making eps *)
			IF P.eps & (P.pno > 1) THEN RETURN END;
			SetColor;
			Box(P, x, y, w, h);
			Int(bodyR, x+1); Ch(bodyR, " ");
			Int(bodyR, y); Ch(bodyR, " ");
			Int(bodyR, w-1); Ch(bodyR, " ");
			Int(bodyR, h-1); Ch(bodyR, " ");
			Int(bodyR, col); Str(bodyR, " b"); Ln(bodyR)
		END
	END ReplPattern;

	(* mode is not used *)
	PROCEDURE Picture*(P: Printer.Printer; pict: Pictures.Picture; sx, sy, sw, sh, dx, dy, dw, dh, mode: INTEGER);
	VAR
		x, y: INTEGER;
		n, h0, h1, k, i: INTEGER;
		h: ARRAY 128 OF INTEGER;
		
		PROCEDURE WColTab(n: INTEGER);
		VAR i, r, g, b: INTEGER;
		BEGIN
			i := 0; WHILE i < n DO Pictures.GetColor(pict, i, r, g, b); Hex2(bodyR, CHR(r)); INC(i) END; Ln(bodyR);
			i := 0; WHILE i < n DO Pictures.GetColor(pict, i, r, g, b); Hex2(bodyR, CHR(g)); INC(i) END; Ln(bodyR);
			i := 0; WHILE i < n DO Pictures.GetColor(pict, i, r, g, b); Hex2(bodyR, CHR(b)); INC(i) END; Ln(bodyR);
		END WColTab;
		
		PROCEDURE H(n: INTEGER);
		VAR d0, d1: INTEGER;
		BEGIN
			d0 := n MOD 16; IF d0 > 9 THEN INC(d0, 7) END;
			d1 := n DIV 16; IF d1 > 9 THEN INC(d1, 7) END;
			Files.Write(bodyR, CHR(d1+30H)); Files.Write(bodyR, CHR(d0+30H))
		END H;
		
		PROCEDURE Out;
		BEGIN
			IF n > 0 THEN
				IF n = 1 THEN H(0); H(h[0])
				ELSIF (n = 2) & (h[0] = h[1]) THEN H(81H); H(h[0])
				ELSE H(n-1); i := 0; WHILE i < n DO H(h[i]); INC(i) END
				END;
				n := 0
			END;
			WHILE k > 128 DO H(127+128); H(h0); DEC(k, 128) END;
			H(127+k); H(h0)
		END Out;

	BEGIN
		WITH P: PSPrinter DO
			(* Don't make more that one page when making eps *)
			IF P.eps & (P.pno > 1) THEN RETURN END;
			Box(P, dx, dy, dw, dh);
			Str(bodyR, "gsave ");
			Int(bodyR, dx); Ch(bodyR, " ");
			Int(bodyR, dy);
			Str(bodyR, " translate ");
			Real(bodyR, dw/sw); Ch(bodyR, " "); Real(bodyR, dh/sh); Str(bodyR, " scale ");
			
			Int(bodyR, sw); Ch(bodyR, " "); Int(bodyR, sh);
			Str(bodyR, " rlepic ");
			WColTab(256);
			
			y := sy + sh - 1;
			WHILE y >= sy DO
				n := 0; x := sx;
				h0 := Pictures.Get(pict, x, y); INC(x); k := 1;
				WHILE x < sx + sw DO
					h1 := Pictures.Get(pict, x, y); h[n] := h1;
					IF h1 = h0 THEN INC(k)
					ELSE
						IF k < 3 THEN
							IF n + k >= 128 THEN H(127);
								i := 0; WHILE i < n DO H(h[i]); INC(i) END;
								i := 0; WHILE n + i < 128 DO H(h0); INC(i); DEC(k) END;
								n := 0
							END;
							WHILE k > 0 DO DEC(k); h[n] := h0; INC(n) END
						ELSE Out
						END;
						h0 := h1; k := 1
					END;
					INC(x)
				END;
				Out;
				DEC(y); Ln(bodyR)
			END;
			Ln(bodyR);
			Str(bodyR, "grestore "); Ln(bodyR)
		END
	END Picture;

	PROCEDURE Circle*(P: Printer.Printer; x0, y0, r: INTEGER);
	BEGIN
		WITH P: PSPrinter DO
			(* Don't make more that one page when making eps *)
			IF P.eps & (P.pno > 1) THEN RETURN END;
			SetColor;
			Box(P, x0 - r, y0 - r, r * 2, r * 2);
			Int(bodyR, x0); Ch(bodyR, " ");
			Int(bodyR, y0); Ch(bodyR, " ");
			Int(bodyR, r); Ch(bodyR, " ");
			Int(bodyR, r); Str(bodyR, " c");
			Ln(bodyR)
		END
	END Circle;

	PROCEDURE Ellipse*(P: Printer.Printer; x0, y0, a, b: INTEGER);
	BEGIN
		WITH P: PSPrinter DO
			(* Don't make more that one page when making eps *)
			IF P.eps & (P.pno > 1) THEN RETURN END;
			SetColor;
			Box(P, x0 - a, y0 - b, a * 2 , b * 2);
			Int(bodyR, x0); Ch(bodyR, " ");
			Int(bodyR, y0); Ch(bodyR, " ");
			Int(bodyR, a); Ch(bodyR, " ");
			Int(bodyR, b); Str(bodyR, " c");
			Ln(bodyR)
		END
	END Ellipse;

	PROCEDURE Line*(P: Printer.Printer; x0, y0, x1, y1: INTEGER);
	BEGIN
		WITH P: PSPrinter DO
			(* Don't make more that one page when making eps *)
			IF P.eps & (P.pno > 1) THEN RETURN END;
			SetColor;
			Box(P, Min(x0, x1), Min(y0, y1), ABS(x1 - x0), ABS(y1 - y0));
			Int(bodyR, x0); Ch(bodyR, " ");
			Int(bodyR, y0); Ch(bodyR, " ");
			Int(bodyR, x1-x0); Ch(bodyR, " ");
			Int(bodyR, y1-y0); Str(bodyR, " x");
			Ln(bodyR)
		END
	END Line;
	
	PROCEDURE UseColor*(P: Printer.Printer; red, green, blue: INTEGER);
	BEGIN
		curR := red;  curG := green;  curB := blue
	END UseColor;

	(* -- Spline computation -- *)

	PROCEDURE SolveTriDiag(VAR a, b, c, y: RealVector; n: INTEGER);
		VAR i: INTEGER; t, tt: REAL;
	BEGIN (*a, b, c of tri-diag matrix T; solve Ty' = y for y', assign y' to y*)
		i := 1;
		WHILE i < n DO t := y[i-1]; y[i] := y[i] - c[i-1]*t; INC(i) END ;
		i := n-1; y[i] := y[i]/a[i];
		WHILE i > 0 DO DEC(i); t := a[i]; tt := b[i]*y[i+1]; y[i] := (y[i] - tt)/t END
	END SolveTriDiag;

	PROCEDURE OpenSpline(VAR x, y, d: RealVector; n: INTEGER);
		VAR i: INTEGER; d1, d2: REAL;
			a, b, c: RealVector;
	BEGIN (*from x, y compute d = y'*)
		b[0] := 1.0/(x[1] - x[0]); a[0] := 2.0*b[0]; c[0] := b[0];
		d1 := (y[1] - y[0])*3.0*b[0]*b[0]; d[0] := d1; i := 1;
		WHILE i < n-1 DO
			b[i] := 1.0/(x[i+1] - x[i]);
			a[i] := 2.0*(c[i-1] + b[i]);
			c[i] := b[i];
			d2 := (y[i+1] - y[i])*3.0*b[i]*b[i];
			d[i] := d1 + d2; d1 := d2; INC(i)
		END ;
		a[i] := 2.0*b[i-1]; d[i] := d1; i := 0;
		WHILE i < n-1 DO c[i] := c[i]/a[i]; a[i+1] := a[i+1] - c[i]*b[i]; INC(i) END ;
		SolveTriDiag(a, b, c, d, n)
	END OpenSpline;

	PROCEDURE ClosedSpline(VAR x, y, d: RealVector; n: INTEGER);
		VAR i: INTEGER; d1, d2, hn, dn: REAL;
			a, b, c, w: RealVector;
	BEGIN (*from x, y compute d = y'*)
		hn := 1.0/(x[n-1] - x[n-2]);
		dn := (y[n-1] - y[n-2])*3.0*hn*hn;
		b[0] := 1.0/(x[1] - x[0]);
		a[0] := 2.0*b[0] + hn;
		c[0] := b[0];
		d1 := (y[1] - y[0])*3.0*b[0]*b[0]; d[0] := dn + d1;
		w[0] := 1.0; i := 1;
		WHILE i < n-2 DO
			b[i] := 1.0/(x[i+1] - x[i]);
			a[i] := 2.0*(c[i-1] + b[i]);
			c[i] := b[i];
			d2 := (y[i+1] - y[i])*3.0*b[i]*b[i]; d[i] := d1 + d2; d1 := d2;
			w[i] := 0; INC(i)
		END ;
		a[i] := 2.0*b[i-1] + hn; d[i] := d1 + dn;
		w[i] := 1.0; i := 0;
		WHILE i < n-2 DO c[i] := c[i]/a[i]; a[i+1] := a[i+1] - c[i]*b[i]; INC(i) END ;
		SolveTriDiag(a, b, c, d, n-1); SolveTriDiag(a, b, c, w, n-1); 
		d1 := (d[0] + d[i])/(w[0] + w[i] + x[i+1] - x[i]); i := 0;
		WHILE i < n-1 DO d[i] := d[i] - d1*w[i]; INC(i) END ;
		d[i] := d[0]
	END ClosedSpline;

	PROCEDURE PrintPoly(P: PSPrinter; VAR p, q: Poly; lim: REAL);
		VAR x0, y0, x1, y1, x2, y2, x3, y3: REAL;
			xx0, yy0, xx1, yy1, xx2, yy2, xx3, yy3: LONGINT;
	
	BEGIN
		x0 := p.d;
		y0 := q.d;
		x1 := x0 + p.c*lim/3.0;
		y1 := y0 + q.c*lim/3.0;
		x2 := x1 + (p.c + p.b*lim)*lim/3.0;
		y2 := y1 + (q.c + q.b*lim)*lim/3.0;
		x3 := x0 + (p.c + (p.b + p.a*lim)*lim)*lim;
		y3 := y0 + (q.c + (q.b + q.a*lim)*lim)*lim;

		xx0 := ENTIER(x0); yy0 := ENTIER(y0); xx1 := ENTIER(x1); yy1 := ENTIER(y1); 
		xx2 := ENTIER(x2); yy2 := ENTIER(y2); xx3 := ENTIER(x3); yy3 := ENTIER(y3);
		
		Int(bodyR, xx1); Ch(bodyR, " ");
		Int(bodyR, yy1); Ch(bodyR, " ");
		Int(bodyR, xx2); Ch(bodyR, " ");
		Box(P, Min(xx1, xx2), Min(yy1, yy2), ABS(xx2-xx1), ABS(yy2-yy1));
		
		Int(bodyR, yy2); Ch(bodyR, " ");
		Int(bodyR, xx3); Ch(bodyR, " ");
		Box(P, Min(xx2, xx3), Min(yy2, yy3), ABS(xx3-xx2), ABS(yy3-yy2));
		
		Int(bodyR, yy3); Ch(bodyR, " ");
		Int(bodyR, xx0); Ch(bodyR, " ");
		Int(bodyR, yy0); Str(bodyR, " z");
		Box(P, Min(xx3, xx0), Min(yy3, yy0), ABS(xx0-xx3), ABS(yy0-yy3));
		
		Ln(bodyR);
	END PrintPoly;

	PROCEDURE Spline*(P: Printer.Printer; x0, y0, n, open: INTEGER; VAR X, Y: ARRAY OF INTEGER);
		VAR i: INTEGER; dx, dy, ds: REAL;
			x, xd, y, yd, s: RealVector;
			p, q: PolyVector;
	BEGIN
		WITH P: PSPrinter DO
			(* Don't make more that one page when making eps *)
			IF P.eps & (P.pno > 1) THEN RETURN END;
			SetColor;
			(*from u, v compute x, y, s*)
			x[0] := X[0] + x0; y[0] := Y[0] + y0; s[0] := 0; i := 1;
			WHILE i < n DO
				x[i] := X[i] + x0; dx := x[i] - x[i-1];
				y[i] := Y[i] + y0; dy := y[i] - y[i-1];
				s[i] := ABS(dx) + ABS(dy) + s[i-1]; INC(i)
			END ;
			IF open = 1 THEN OpenSpline(s, x, xd, n); OpenSpline(s, y, yd, n)
			ELSE ClosedSpline(s, x, xd, n); ClosedSpline(s, y, yd, n)
			END ;
			(*compute coefficients from x, y, xd, yd, s*)  i := 0;
			WHILE i < n-1 DO
				ds := 1.0/(s[i+1] - s[i]);
				dx := (x[i+1] - x[i])*ds;
				p[i].a := ds*ds*(xd[i] + xd[i+1] - 2.0*dx);
				p[i].b := ds*(3.0*dx - 2.0*xd[i] -xd[i+1]);
				p[i].c := xd[i];
				p[i].d := x[i];
				p[i].t := s[i];
				dy := ds*(y[i+1] - y[i]);
				q[i].a := ds*ds*(yd[i] + yd[i+1] - 2.0*dy);
				q[i].b := ds*(3.0*dy - 2.0*yd[i] - yd[i+1]);
				q[i].c := yd[i];
				q[i].d := y[i];
				q[i].t := s[i]; INC(i)
			END ;
			p[i].t := s[i]; q[i].t := s[i];
			(*print polynomials*)
			i := 0;
			WHILE i < n-1 DO PrintPoly(P, p[i], q[i], p[i+1].t - p[i].t); INC(i) END
		END
	END Spline;

	PROCEDURE Page*(P: Printer.Printer; nofcopies: INTEGER);
	VAR x, y: LONGINT;
	BEGIN
		WITH P: PSPrinter DO
			ResetColor;
			CASE P.mode OF
				oneup:
					IF ~P.eps THEN
						Int(bodyR, nofcopies); Str(bodyR, " p"); Ln(bodyR)
					END;
					curFont := -1; INC(P.pno); ppos := Files.Pos(bodyR);
					Str(bodyR, "%%Page: 0 "); Int(bodyR, P.pno); Ln(bodyR);
				|twoup:
					x := 2336 * 3048 DIV P.Unit;
					CASE P.location OF
						| 0: Int(bodyR, x);  Str(bodyR, " 0 translate"); Ln(bodyR)
						| 1: Int(bodyR, -x);  Str(bodyR, " 0 translate"); Ln(bodyR);
							Int(bodyR, nofcopies); Str(bodyR, " p"); Ln(bodyR);
							curFont := -1; INC(P.pno); ppos := Files.Pos(bodyR);
							Str(bodyR, "%%Page: 0 "); Int(bodyR, P.pno); Ln(bodyR)
					END; (* CASE *)
					P.location := 1-P.location
				|fourup:
					x := 2336 * 3048 DIV P.Unit;  y := 3520 * 3048 DIV P.Unit;
					CASE P.location OF
						| 0: Int(bodyR, x);  Str(bodyR, " 0 translate"); Ln(bodyR)
						| 1: Int(bodyR, -x);  Ch(bodyR, " ");  Int(bodyR, -y);  Str(bodyR, " translate"); Ln(bodyR)
						| 2: Int(bodyR, x);  Str(bodyR, " 0 translate"); Ln(bodyR)
						| 3: Int(bodyR, -x);  Ch(bodyR, " ");  Int(bodyR, y);  Str(bodyR, " translate"); Ln(bodyR);
							Int(bodyR, nofcopies); Str(bodyR, " p"); Ln(bodyR);
							curFont := -1; INC(P.pno); ppos := Files.Pos(bodyR);
							Str(bodyR, "%%Page: 0 "); Int(bodyR, P.pno); Ln(bodyR)
					END; (* CASE *)
					P.location := (P.location+1) MOD 4
			END (* CASE *)
		END
	END Page;

	PROCEDURE Close*(P: Printer.Printer);
		CONST bufSize = 4*1024;
		VAR
			dpi: LONGINT;
			i: INTEGER;
			printR, srcR: Files.Rider; buffer: ARRAY bufSize OF CHAR;
			S: Texts.Scanner;
			R: Texts.Reader; ch: CHAR;
			fontDef: FontDef;
			alias: ARRAY 64 OF CHAR;
	BEGIN
		WITH P: PSPrinter DO
			dpi := 914400 DIV Printer.current.Unit;
			IF (P.mode # oneup) & (P.location # 0) THEN
				Int(bodyR, 1); Str(bodyR, " p"); Ln(bodyR);
				curFont := -1; INC(P.pno); ppos := Files.Pos(bodyR)
			END;
			Files.Set(bodyR, bodyF, ppos);	(*overwrite last %%Page line*)
			Str(bodyR, "%%Trailer         "); Ln(bodyR);
			Str(bodyR, "restore"); Ln(bodyR);	(* page save *)
			Str(bodyR, "restore"); Ln(bodyR);	(* header file save *)
			
			Files.Set(printR, P.printF, 0);
			
			IF P.eps & (P.l <= P.r) & (P.b <= P.t) THEN
				Str(printR, "%!PS-Adobe-1.0"); Ln(printR);
				Str(printR, "%%BoundingBox: ");
				Int(printR, 0); Ch(printR, " "); Int(printR, 0); Ch(printR, " "); 
				Int(printR, (P.r - P.l + 1)* 72 DIV (914400 DIV P.Unit)); Ch(printR, " "); Int(printR, (P.t - P.b + 1) * 72 DIV (914400 DIV P.Unit)); Ch(printR, " ");
				Ln(printR);
				Str(printR, "%%Creator: ETH Oberon System 3"); Ln(printR);
				Str(printR, "%%EndComments"); Ln(printR);
			END;
			
			Texts.OpenReader(R, headerT, 0);
			Texts.Read(R, ch);
			WHILE ~R.eot DO
				Files.Write(printR, ch);
				IF ch = 0DX THEN Files.Write(printR, 0AX) END;
				Texts.Read(R, ch)
			END;
			Str(printR, "/factor1 ");
			Real(printR, P.Unit/12700.0);
			Str(printR, " def"); Ln(printR);
			Str(printR, "/factor2 ");
			Real(printR, P.Unit/12700.0);
			Str(printR, " def"); Ln(printR); Ln(printR);
			i := 0;
			WHILE i <= fontIndex DO DefineFont(printR, fontTable[i], FALSE); INC(i) END;
			IF fontMapDictN > 0 THEN
				Str(printR, "/FontMapDict "); Int(printR, fontMapDictN); Str(printR, " dict def"); Ln(printR);
				Str(printR, "FontMapDict begin"); Ln(printR);
				fontDef := fontMapDict;
				WHILE fontDef # NIL DO
					Ch(printR, "/"); Str(printR, fontDef.name); Str(printR, " [/");
					IF (fontDef.family = "Syntax") OR (fontDef.family = "Oberon") OR (fontDef.family = "Default") THEN
						Str(printR, "Helvetica");
						CASE fontDef.attr OF
							"I": Str(printR, "-Oblique")
							|"M", "B": Str(printR, "-Bold")
						ELSE
						END;
						Ch(printR, " ");
						Int(printR, fontDef.size*(4*dpi) DIV 300)
						(*Int(printR, (fontDef.size*11+2)*dpi DIV 100)*)
					ELSIF (fontDef.family = "Helvetica") OR (fontDef.family = "Courier") THEN
						Str(printR, fontDef.family);
						CASE fontDef.attr OF
							"I": Str(printR, "-Oblique")
							|"M", "B": Str(printR, "-Bold")
						ELSE
						END;
						Ch(printR, " ");
						Int(printR, fontDef.size*(4*dpi) DIV 300)
					ELSIF fontDef.family = "Times" THEN
						Str(printR, "Times");
						CASE fontDef.attr OF
							"I": Str(printR, "-Italic")
							|"M", "B": Str(printR, "-Bold")
						ELSE
							Str(printR, "-Roman")
						END;
						Ch(printR, " ");
						Int(printR, fontDef.size*(4*dpi) DIV 300)
					ELSE
						buffer := "PSPrinter."; Strings.Append(buffer, fontDef.family);
						Oberon.OpenScanner (S, buffer);
						IF S.class IN {Texts.Name, Texts.String} THEN
							COPY(S.s, alias); Str(printR, alias)
						ELSE
							Str(printR, fontDef.family)
						END;
						CASE fontDef.attr OF
							"I": Str(printR, "-Italic")
							|"M", "B": Str(printR, "-Bold")
						ELSE
						END;
						Ch(printR, " ");
						Int(printR, fontDef.size*(4*dpi) DIV 300)
					END;
					Str(printR, "] def"); Ln(printR);
					fontDef := fontDef.next
				END;
				Str(printR, "end"); Ln(printR);
				fontMapDict := NIL; fontMapDictN := 0
			END;
			Ln(printR);
			i := 0;
			WHILE i <= fontIndex DO DefineFont(printR, fontTable[i], TRUE); INC(i) END;
			Ln(printR);
			Str(printR, "OberonInit"); Ln(printR); Ln(printR);
			CASE P.mode OF
				oneup:
					(* skip *)
				|twoup:
					Str(printR, "90 rotate"); Ln(printR);
					Str(printR, "0.7071 0.7071 scale"); Ln(printR);
					Str(printR, "0 ");  Int(printR, -3520 * 3048 DIV P.Unit); Str(printR, " translate"); Ln(printR)
				|fourup:
					Str(printR, "0.5 0.5 scale"); Ln(printR); 
					Str(printR, "0 ");  Int(printR, 3520 * 3048 DIV P.Unit); Str(printR, " translate"); Ln(printR)
			END;
			Str(printR, "save"); Ln(printR); Ln(printR);
			Str(printR, "%%EndProlog"); Ln(printR);
			Str(printR, "%%Page: 0 1"); Ln(printR);
			
			Ln(printR);
	
			IF P.eps THEN
				Int(printR, -P.l); Ch(printR, " "); Int(printR, -P.b);
				Str(printR, " translate"); Ln(printR);
			END;
			
			Files.Set(srcR, bodyF, 0);
			REPEAT Files.ReadBytes(srcR, buffer, bufSize); Files.WriteBytes(printR, buffer, bufSize-srcR.res) UNTIL srcR.eof;
			Printer.Spool(P.printF);  P.res := Printer.res;
			
			Files.Set(bodyR, NIL, 0);
			headerT := NIL; bodyF := NIL
		END
	END Close;
	
	PROCEDURE GetMetric* (P: Printer.Printer; fnt: Fonts.Font): Fonts.Font;
	VAR name: ARRAY 32 OF CHAR; i: INTEGER; metric: Fonts.Font;
	BEGIN
		COPY(fnt.name, name);
		i := 0; WHILE (name[i] # ".") & (name[i] # 0X) DO INC(i) END;
		(* look for Mdx *)
		name[i] := "."; name[i+1] := "M"; name[i+2] := "d";
		name[i+3] := CHR(30H + 914400 DIV (100 * P.Unit));
		name[i+4] := "."; name[i+5] := "F"; name[i+6] := "n"; name[i+7] := "t";
		name[i+8] := 0X;
		metric := Fonts.This(name);
		IF metric.type = Fonts.substitute THEN metric := NIL END;
		RETURN metric
	END GetMetric;
	
 PROCEDURE NewPrinter*(): Printer.Printer;
  VAR P: PSPrinter;
  BEGIN
	NEW(P);
	P.name := "PSPrinter.Install";
	P.InitMetrics := InitMetrics;
	P.Escape := Escape;
	P.Open := Open;
	P.Close := Close;
	P.Page := Page;
	P.ReplConst := ReplConst; 
	P.ReplPattern := ReplPattern;
	P.Line := Line;
	P.Circle := Circle;
	P.Ellipse := Ellipse;
	P.Spline := Spline;
	P.Picture := Picture;
	P.UseListFont := UseListFont;
	P.String := String;
	P.ContString := ContString;
	P.UseColor := UseColor;
	P.GetMetric := GetMetric;
	RETURN P
  END NewPrinter;

  PROCEDURE Install*;
  BEGIN Printer.Install(NewPrinter());
  END Install;

	PROCEDURE Init();
		VAR class: Objects.Name; size: LONGINT; style: SET;
	BEGIN
		ParseName(Fonts.Default.name, default, size, style, class)
	END Init;

BEGIN
	hexArray := "0123456789ABCDEF";
	metric := NIL;  curRes := 0;
	NEW(theChar);
	Init()
END PSPrinter.

System.Free PSPrinter ~
PSPrinter.Install

EmptyPrinter.Install

System.Free EamonPrinter LPRPrinter PSPrinter ~
LPRPrinter.Install
