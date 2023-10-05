MODULE GfxFonts0;	(** eos   **)

	(**
		Non-portable part of GfxFonts
		
			Native Oberon: Builder.Compile GfxFonts0.Mod ~
			Windows Oberon: Builder.Compile \D=WIN GfxFonts0.Mod ~
	**)
	
	(*
		16.2.99 - made unknown font types have ppm=MIN(LONGINT) (to avoid .Md?)
		20.4.99 - merged Native and Windows version (using Builder preprocessor)
	*)
	
	IMPORT
		FileDir, Strings;
		
	
	VAR
		Name, Style: ARRAY 32 OF CHAR;
		PPM, FPPM, Len, Error: INTEGER;
		
	

	PROCEDURE EnumFile (name: ARRAY OF CHAR; time, date, size: LONGINT; VAR continue: BOOLEAN);
		CONST isdir = FALSE;
		VAR i, ppm: INTEGER; s: ARRAY 4 OF CHAR;

	BEGIN
		IF ~isdir THEN
			i := Len; ppm := 0;
			WHILE ("0" <= name[i]) & (name[i] <= "9") DO
				ppm := 10*ppm + ORD(name[i]) - ORD("0");
				INC(i)
			END;
			IF (Style = "") & (name[i] = ".") OR (CAP(Style[0]) = CAP(name[i])) THEN
				WHILE (name[i] # 0X) & (name[i] # ".") DO INC(i) END;
				IF name[i] = "." THEN INC(i) END;
				s[0] := name[i]; s[1] := name[i+1]; s[2] := name[i+2]; s[3] := 0X;
				IF s = "Scn" THEN
				ELSIF s = "Pr2" THEN ppm := SHORT(200 * LONG(ppm) DIV 91)
				ELSIF s = "Pr3" THEN ppm := SHORT(300 * LONG(ppm) DIV 91)
				ELSIF s = "Pr6" THEN ppm := SHORT(600 * LONG(ppm) DIV 91)
				ELSE ppm := MIN(INTEGER)
				END;
				IF ABS(PPM - ppm) < Error THEN
					Error := ABS(PPM - ppm); COPY(name, Name); FPPM := ppm;
					IF Error = 0 THEN continue := FALSE END
				END
			END
		END
	END EnumFile;
	
	(** find raster font file that most closely matches the requested number of pixels per em **)
	PROCEDURE Find* (VAR family, style: ARRAY OF CHAR; ppm: INTEGER; VAR name: ARRAY OF CHAR; VAR fppm: INTEGER);
		VAR pattern: ARRAY 64 OF CHAR;
	BEGIN
		Name := ""; FPPM := 0;
		COPY(style, Style); PPM := ppm; Len := SHORT(Strings.Length(family)); Error := MAX(INTEGER);
		COPY(family, pattern); Strings.AppendCh(pattern, "*");
		IF style = "Bold" THEN Strings.AppendCh(pattern, "b")
		ELSIF style = "Italic" THEN Strings.AppendCh(pattern, "i")
		ELSIF style = "Medium" THEN Strings.AppendCh(pattern, "m")
		ELSIF style = "BoldItalic" THEN Strings.AppendCh(pattern, "j")
		END;
		Strings.Append(pattern, ".*.Fnt");

		FileDir.Enumerate(pattern, FALSE, EnumFile);

		COPY(Name, name); fppm := FPPM
	END Find;
	

END GfxFonts0.
