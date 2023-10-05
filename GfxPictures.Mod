MODULE GfxPictures;	(** eos   **)

	(**
		Support for Oberon image maps
	**)
	
	(*
		9.12.98 - first release (together with GfxMaps)
	*)
	
	IMPORT
		SYSTEM, Files, Display, Pictures, GfxMaps;
	
	
	CONST
		R = GfxMaps.R; G = GfxMaps.G; B = GfxMaps.B; A = GfxMaps.A;
		
	
	VAR
		PrntPat*: ARRAY 9 OF Display.Pattern;	(** printer patterns (same as in Printer3) **)
		PatPic: Pictures.Picture;	(* used for converting patterns to maps *)
		
	
	(**--- Oberon Pictures ---**)
	
	(** initialize image map from picture (format=I8, picture contents are copied) **)
	PROCEDURE PictToMap* (pict: Pictures.Picture; map: GfxMaps.Map);
		VAR y, x0, x1, max, idx, dr, dg, db, pr, pg, pb: INTEGER; adr: LONGINT; defaultPal: BOOLEAN; pal: GfxMaps.Palette;
	BEGIN
		GfxMaps.Create(map, pict.width, pict.height, GfxMaps.I8);	(* try default format with default palette *)
		
		(* get picture contents *)
		y := 0; adr := map.adr;
		WHILE y < pict.height DO
			x0 := 0;
			WHILE x0 < pict.width DO
				x1 := x0;
				Pictures.GetRun(pict, idx, x1, y);
				REPEAT SYSTEM.PUT(adr, CHR(idx)); INC(adr); INC(x0) UNTIL x0 = x1
			END
		END;
		
		(* check if palette matches default palette *)
		idx := 0; max := SHORT(ASH(1, pict.depth)); defaultPal := TRUE;
		WHILE (idx < max) & defaultPal DO
			dr := GfxMaps.DisplayPal.col[idx].r;
			dg := GfxMaps.DisplayPal.col[idx].g;
			db := GfxMaps.DisplayPal.col[idx].b;
			Pictures.GetColor(pict, idx, pr, pg, pb);
			defaultPal := (dr = pr) & (dg = pg) & (db = pb);
			INC(idx)
		END;
		
		IF ~defaultPal THEN	(* initialize specific palette *)
			NEW(pal); idx := 0;
			WHILE idx < max DO
				Pictures.GetColor(pict, idx, pr, pg, pb);
				pal.col[idx].r := pr; pal.col[idx].g := pg; pal.col[idx].b := pb;
				INC(idx)
			END;
			GfxMaps.InitPalette(pal, max);
			map.fmt.pal := pal
		END
	END PictToMap;
	
	(** initialize picture from map **)
	PROCEDURE MapToPict* (map: GfxMaps.Map; pict: Pictures.Picture; pal: GfxMaps.Palette);
		VAR fmt: GfxMaps.Format; i, y, x, w: INTEGER; byte: ARRAY 256 OF CHAR; int: ARRAY 256 OF INTEGER;
	BEGIN
		Pictures.Create(pict, map.width, map.height, 8);	(* uses display palette *)
		fmt := GfxMaps.I8;
		IF pal # GfxMaps.DisplayPal THEN	(* modify picture palette *)
			fmt.pal := pal;
			i := 0;
			WHILE i < pal.used DO
				Pictures.SetColor(pict, i, pal.col[i].r, pal.col[i].g, pal.col[i].b);
				INC(i)
			END
		END;
		y := 0;
		WHILE y < map.height DO
			x := 0;
			WHILE x < map.width DO
				w := map.width - x;
				IF w > 256 THEN w := 256 END;
				GfxMaps.GetPixels(map, x, y, w, fmt, byte, GfxMaps.SrcCopy);
				FOR i := 0 TO w-1 DO
					int[i] := ORD(byte[i])
				END;
				Pictures.PutLine(pict, int, x, y, w);
				INC(x, w)
			END;
			INC(y)
		END
	END MapToPict;
	
	(* pack/unpack procedures for I1 and I4 formats *)
	
	PROCEDURE PackI1 (VAR fmt: GfxMaps.Format0; adr, bit: LONGINT; VAR pix: GfxMaps.Pixel);
		VAR b: CHAR;
	BEGIN
		SYSTEM.GET(adr, b);
		IF ODD(GfxMaps.BestIndex(fmt.pal, ORD(pix[R]), ORD(pix[G]), ORD(pix[B]))) THEN
			IF ~ODD(ASH(ORD(b), -bit)) THEN
				SYSTEM.PUT(adr, CHR(ORD(b) + ASH(1, bit)))
			END
		ELSE
			IF ODD(ASH(ORD(b), -bit)) THEN
				SYSTEM.PUT(adr, CHR(ORD(b) - ASH(1, bit)))
			END
		END
	END PackI1;
	
	PROCEDURE UnpackI1 (VAR fmt: GfxMaps.Format0; adr, bit: LONGINT; VAR pix: GfxMaps.Pixel);
		VAR b: CHAR;
	BEGIN
		SYSTEM.GET(adr, b);
		GfxMaps.ColorToPixel(fmt.pal.col[ASH(ORD(b), -bit) MOD 2], pix)
	END UnpackI1;
	
	PROCEDURE PackI4 (VAR fmt: GfxMaps.Format0; adr, bit: LONGINT; VAR pix: GfxMaps.Pixel);
		VAR b: CHAR; i: INTEGER;
	BEGIN
		SYSTEM.GET(adr, b);
		i := GfxMaps.BestIndex(fmt.pal, ORD(pix[R]), ORD(pix[G]), ORD(pix[B])) MOD 10H;
		IF bit = 0 THEN
			SYSTEM.PUT(adr, CHR(ORD(b) - ORD(b) MOD 10H + i))
		ELSE
			SYSTEM.PUT(adr, CHR(ORD(b) MOD 10H + 10H*i))
		END
	END PackI4;
	
	PROCEDURE UnpackI4 (VAR fmt: GfxMaps.Format0; adr, bit: LONGINT; VAR pix: GfxMaps.Pixel);
		VAR b: CHAR;
	BEGIN
		SYSTEM.GET(adr, b);
		GfxMaps.ColorToPixel(fmt.pal.col[ASH(ORD(b), -bit) MOD 10H], pix)
	END UnpackI4;
	
	(* load Oberon picture from file *)
	PROCEDURE LoadPict (map: GfxMaps.Map; VAR fname: ARRAY OF CHAR; VAR done: BOOLEAN);
		VAR
			file: Files.File; r: Files.Rider; id, w, h, depth: INTEGER; gen: ARRAY 64 OF CHAR; i, n, adr, a: LONGINT;
			default: BOOLEAN; pal: GfxMaps.Palette; red, green, blue: ARRAY 256 OF CHAR; fmt: GfxMaps.Format; byte: CHAR;
	BEGIN
		file := Files.Old(fname);
		IF file # NIL THEN
			Files.Set(r, file, 0); Files.ReadInt(r, id);
			IF id = 07F7H THEN	(* document *)
				Files.ReadString(r, gen); Files.Set(r, file, Files.Pos(r) + 4*2); Files.ReadInt(r, id)
			END;
			
			IF id = Pictures.PictFileId THEN
				Files.ReadInt(r, w); Files.ReadInt(r, h); Files.ReadInt(r, depth);
				
				(* load picture palette *)
				i := 0; n := ASH(1, depth); default := TRUE; pal := GfxMaps.DisplayPal;
				WHILE i < n DO
					Files.Read(r, red[i]); Files.Read(r, green[i]); Files.Read(r, blue[i]);
					IF (ORD(red[i]) # pal.col[i].r) OR (ORD(green[i]) # pal.col[i].g) OR (ORD(blue[i]) # pal.col[i].b) THEN
						default := FALSE
					END;
					INC(i)
				END;
				IF ~default THEN
					NEW(pal); i := 0;
					WHILE i < n DO
						pal.col[i].r := ORD(red[i]); pal.col[i].g := ORD(green[i]); pal.col[i].b := ORD(blue[i]);
						INC(i)
					END;
					GfxMaps.InitPalette(pal, SHORT(n))
				END;
				
				(* initialize map *)
				IF depth = 1 THEN
					GfxMaps.InitFormat(fmt, 1, 1, {GfxMaps.Index}, pal, PackI1, UnpackI1)
				ELSIF depth = 4 THEN
					GfxMaps.InitFormat(fmt, 4, 1, {GfxMaps.Index}, pal, PackI4, UnpackI4)
				ELSE
					fmt := GfxMaps.I8; fmt.pal := pal
				END;
				GfxMaps.Create(map, w, h, fmt);
				
				(* load run-length encoded pixels *)
				adr := map.adr + h * map.bpr;
				WHILE h > 0 DO
					a := adr - map.bpr;
					WHILE a < adr DO
						Files.Read(r, byte); n := ORD(byte);
						IF n < 128 THEN
							REPEAT
								Files.Read(r, byte);
								SYSTEM.PUT(a, byte); INC(a);
								DEC(n)
							UNTIL n < 0
						ELSE
							n := 100H - n;
							Files.Read(r, byte);
							REPEAT
								SYSTEM.PUT(a, byte); INC(a);
								DEC(n)
							UNTIL n < 0
						END
					END;
					DEC(h); DEC(adr, map.bpr)
				END;
				
				done := TRUE
			END
		END
	END LoadPict;
	
	(* store Oberon picture *)
	PROCEDURE StorePict (map: GfxMaps.Map; VAR fname: ARRAY OF CHAR; VAR done: BOOLEAN);
		VAR
			file: Files.File; r: Files.Rider; depth, y, x: INTEGER; fmt: GfxMaps.Format; tmp: GfxMaps.Map; i: LONGINT;
			pix: POINTER TO ARRAY OF CHAR; buf: ARRAY 129 OF SHORTINT;
	BEGIN
		file := Files.New(fname);
		IF file # NIL THEN
			Files.Set(r, file, 0);
			Files.WriteInt(r, Pictures.PictFileId);
			Files.WriteInt(r, map.width); Files.WriteInt(r, map.height);
			
			(* find out which format to use *)
			IF map.fmt.components = {GfxMaps.Index} THEN	(* contains index information *)
				IF map.fmt.bpp > 4 THEN
					fmt := GfxMaps.I8; fmt.pal := map.fmt.pal; depth := 8
				ELSIF map.fmt.bpp > 1 THEN
					GfxMaps.InitFormat(fmt, 4, 1, {GfxMaps.Index}, map.fmt.pal, PackI4, UnpackI4);
					depth := 4
				ELSE
					GfxMaps.InitFormat(fmt, 1, 1, {GfxMaps.Index}, map.fmt.pal, PackI1, UnpackI1);
					depth := 1
				END
			ELSE	(* calculate palette and dither to temporary map *)
				fmt := GfxMaps.I8;
				NEW(fmt.pal); NEW(tmp);
				GfxMaps.ComputePalette(map, fmt.pal, 256);
				GfxMaps.Create(tmp, map.width, map.height, fmt);
				GfxMaps.Dither(map, tmp);
				map := tmp; depth := 8
			END;
			
			(* write palette *)
			Files.WriteInt(r, depth);
			i := 0;
			WHILE i < ASH(1, depth) DO
				Files.Write(r, CHR(fmt.pal.col[i].r)); Files.Write(r, CHR(fmt.pal.col[i].g)); Files.Write(r, CHR(fmt.pal.col[i].b));
				INC(i)
			END;
			
			(* write run-length encoded pixels *)
			NEW(pix, map.width); y := map.height;
			WHILE y > 0 DO
				DEC(y);
				GfxMaps.GetPixels(map, 0, y, map.width, fmt, pix^, GfxMaps.SrcCopy);
				buf[0] := 0; buf[1] := SHORT(ORD(pix[0])); x := 1;
				WHILE x < map.width DO
					IF buf[0] < 0 THEN	(* accumulating equal bytes *)
						IF (buf[0] > -128) & (pix[x] = CHR(buf[1])) THEN
							DEC(buf[0])
						ELSE
							Files.WriteBytes(r, buf, 2);
							buf[0] := 0; buf[1] := SHORT(ORD(pix[x]))
						END
					ELSIF buf[1] > 0 THEN	(* accumulating different bytes *)
						IF buf[0] = 127 THEN	(* buffer full *)
							Files.WriteBytes(r, buf, buf[0]+2);
							buf[0] := 0; buf[1] := SHORT(ORD(pix[x]))
						ELSIF pix[x] # CHR(buf[buf[0]+1]) THEN
							INC(buf[0]); buf[buf[0]+1] := SHORT(ORD(pix[x]))
						ELSE
							Files.WriteBytes(r, buf, buf[0]+1);
							buf[0] := -1; buf[1] := SHORT(ORD(pix[x]))
						END
					ELSIF pix[x] = CHR(buf[1]) THEN	(* starting to accumulate equal bytes *)
						buf[0] := -1
					ELSE	(* starting to accumulate different bytes *)
						buf[0] := 1; buf[2] := SHORT(ORD(pix[x]))
					END;
					INC(x)
				END;
				IF buf[0] >= 0 THEN Files.WriteBytes(r, buf, buf[0]+2)
				ELSE Files.WriteBytes(r, buf, 2)
				END;
				INC(y)
			END;
			
			Files.Register(file);
			done := TRUE
		END
	END StorePict;
	
	(** install load/store procedures for handling Oberon pictures **)
	PROCEDURE Install*;
	BEGIN
		GfxMaps.LoadProc := LoadPict; GfxMaps.StoreProc := StorePict
	END Install;
	
	
	(**--- Oberon Patterns ---**)
	
	(** initialize image map from pattern (format=A1; pattern is copied) **)
	PROCEDURE PatternToMap* (pat: Display.Pattern; map: GfxMaps.Map);
		VAR w, h, y, x: INTEGER; pix: GfxMaps.Pixel;
	BEGIN
		ASSERT(pat # 0, 100);
		IF (1 <= pat) & (pat <= 8) THEN pat := PrntPat[pat] END;
		Display.GetDim(pat, w, h);
		GfxMaps.Create(map, w, h, GfxMaps.A1);
		
		(* it seems that the only portable way to access a pattern is to render it into a picture first *)
		IF PatPic = NIL THEN NEW(PatPic) END;
		IF (PatPic.width < w) OR (PatPic.height < h) THEN Pictures.Create(PatPic, w, h, 1) END;
		Pictures.ReplConst(PatPic, 0, 0, 0, w, h, Display.replace);
		Pictures.CopyPattern(PatPic, 1, pat, 0, 0, Display.paint);
		
		y := 0; pix[A] := 0FFX;
		WHILE y < h DO
			x := 0;
			WHILE x < w DO
				IF Pictures.Get(PatPic, x, y) # 0 THEN
					GfxMaps.Put(map, x, y, pix, GfxMaps.SrcCopy)
				END;
				INC(x)
			END;
			INC(y)
		END
	END PatternToMap;
	
	(* initialize printer patterns *)
	PROCEDURE InitPatterns;
		VAR pat: ARRAY 8 OF SET; i: LONGINT;
	BEGIN
		(* adapted from Printer3 *)
		pat[0] := {}; pat[1] := {}; pat[2] := {}; pat[3] := {0,4,8,12,16,20,24,28};
		FOR i := 0 TO 3 DO pat[4 + i] := pat[i] END;
		PrntPat[1] := Display.NewPattern(32, 8, pat);
		pat[0] := {0,4,8,12,16,20,24,28}; pat[1] := {}; pat[2] := {2,6,10,14,18,22,26,30}; pat[3] := {};
		FOR i := 0 TO 3 DO pat[4 + i] := pat[i] END;
		PrntPat[2] := Display.NewPattern(32, 8, pat);
		pat[0] := {}; pat[1] := {0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30};
		FOR i := 0 TO 5 DO pat[2 + i] := pat[i] END;
		PrntPat[3] := Display.NewPattern(32, 8, pat);
		pat[0] := {0,4,8,12,16,20,24,28}; pat[1] := {2,6,10,14,18,22,26,30};
		FOR i := 0 TO 5 DO pat[2 + i] := pat[i] END;
		PrntPat[4] := Display.NewPattern(32, 8, pat);
		PrntPat[5] := Display.solid;
		pat[0] := {0,4,8,12,16,20,24,28}; pat[1] := {1,5,9,13,17,21,25,29};
		pat[2] := {2,6,10,14,18,22,26,30}; pat[3] := {3,7,11,15,19,23,27,31};
		FOR i := 0 TO 3 DO pat[4 + i] := pat[i] END;
		PrntPat[6] := Display.NewPattern(32, 8, pat);
		pat[0] := {3,7,11,15,19,23,27,31}; pat[1] := {2,6,10,14,18,22,26,30};
		pat[2] := {1,5,9,13,17,21,25,29}; pat[3] := {0,4,8,12,16,20,24,28};
		FOR i := 0 TO 3 DO pat[4 + i] := pat[i] END;
		PrntPat[7] := Display.NewPattern(32, 8, pat);
		FOR i := 0 TO 7 DO pat[i] := {0,4,8,12,16,20,24,28} END;
		PrntPat[8] := Display.NewPattern(32, 8, pat)
	END InitPatterns;
	

BEGIN
	InitPatterns
END GfxPictures.
