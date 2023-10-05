MODULE Captions;	(** eos   **)

	(**
		Compatibility module for users using older version of Leonardo
	**)
	
	IMPORT
		Files, Objects, Texts, Attributes, Gadgets, GfxMatrix, GfxMaps, GfxFonts, Figures, LeoPaths, LeoText;
		
	
	PROCEDURE HandleCaption (cap: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR
			ver, i, size: LONGINT; obj: Objects.Object; text: Texts.Text; r: Texts.Reader; ch: CHAR; font, s: ARRAY 128 OF CHAR;
			color, idummy: INTEGER; anchor: LeoPaths.Point; mat: GfxMatrix.Matrix; rdummy: REAL;
	BEGIN
		WITH msg: Objects.FileMsg DO
			ASSERT(msg.id = Objects.load);
			Figures.HandleShape(cap, msg);
			Files.ReadNum(msg.R, ver);
			ASSERT(ver = 1);
			Gadgets.ReadRef(msg.R, cap.lib, obj);
			text := obj(Texts.Text);
			Texts.OpenReader(r, text, 0);
			Texts.Read(r, ch); i := 0;
			IF ~r.eot THEN
				COPY(r.lib.name, font); color := r.col;
				WHILE (i < LEN(s)-1) & ~r.eot & (ch >= " ") DO
					s[i] := ch; INC(i);
					Texts.Read(r, ch)
				END
			ELSE
				COPY(GfxFonts.Default.name, font); color := GfxMaps.BestIndex(GfxMaps.DisplayPal, 0, 0, 0)
			END;
			s[i] := 0X;
			LeoText.InitCaption(cap(LeoText.Caption), 0, 0, s);
			i := 0; ch := font[i];
			WHILE (CAP(ch) >= "A") & (CAP(ch) <= "Z") DO INC(i); ch := font[i] END;
			size := 0;
			WHILE (ch >= "0") & (ch <= "9") DO
				size := 10*size + ORD(ch) - ORD("0");
				INC(i); ch := font[i]
			END;
			IF size = 0 THEN size := 10 END;
			Attributes.SetString(cap, "Font", font);
			Attributes.SetInt(cap, "Size", size);
			Attributes.SetInt(cap, "Color", color);
			Gadgets.ReadRef(msg.R, cap.lib, obj);
			anchor := obj(LeoPaths.Point);
			Files.ReadInt(msg.R, idummy); Files.ReadInt(msg.R, idummy);	(* alignment, never used *)
			FOR i := 0 TO 2 DO
				Files.ReadReal(msg.R, mat[i, 0]); Files.ReadReal(msg.R, mat[i, 1]); Files.ReadReal(msg.R, rdummy)
			END;
			Attributes.SetReal(cap, "M00", mat[0, 0]); Attributes.SetReal(cap, "M01", mat[0, 1]);
			Attributes.SetReal(cap, "M10", mat[1, 0]); Attributes.SetReal(cap, "M11", mat[1, 1]);
			Attributes.SetReal(cap, "M20", mat[2, 0] + anchor.x); Attributes.SetReal(cap, "M21", mat[2, 1] + anchor.y);
			LeoText.ValidateCaption(cap(LeoText.Caption))
		END
	END HandleCaption;
	
	PROCEDURE NewCaption*;
		VAR cap: LeoText.Caption;
	BEGIN
		NEW(cap); cap.handle := HandleCaption;
		Objects.NewObj := cap
	END NewCaption;
	

END Captions.
