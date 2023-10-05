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

MODULE Fonts;	(** portable *) (*JG 16.3.94*)

(**
The Module Fonts implement the Oberon font manager. Fonts are collections 
of characters, each character being a pattern and and metric data.
*)

	IMPORT SYSTEM, Kernel, Files, Objects, Display;

	CONST MaxRuns = 32; IndexSize = 256*4;
		substitute* = -1; font* = 0; metric* = 1; (** Font types. *)
		TraceMissing = TRUE;  TraceAlias = FALSE;
		
	TYPE 
		Char* = POINTER TO CharDesc;
		Font* = POINTER TO FontDesc;

		CharDesc* = RECORD (Objects.ObjDesc)	(** The objects in a font library. *)	(* Note: offset used in GetCharObj *)
			dx*, x*, y*, w*, h*: INTEGER;	(** Character width, pattern offset (x, y), pattern size (w, h). *)
			pat*: Display.Pattern	(** Character raster data. *)
		END;

		FontDesc* = RECORD (Objects.LibDesc)
			type*: SHORTINT;	(** Substitute, font, or metric. *)
			height*, minX*, maxX*, minY*, maxY*: INTEGER	(** Font height, extremal values of characters in font. *)
		END;

		RunRec = RECORD beg, end: INTEGER END;

		BoxRec = RECORD
			dx, x, y, w, h: INTEGER
		END;

	VAR FontId*: CHAR;	(** Initial character of font files (.Fnt). *)
			Default*: Font;	(** Default system screen font (typically Oberon10.Scn.Fnt). *)
			theChar: Char;
			default: Objects.Name;
			conv: BOOLEAN;
	 
	PROCEDURE Put1 (VAR a: LONGINT; x: INTEGER);
	VAR y: SHORTINT;
	BEGIN y := SHORT(x); SYSTEM.PUT(a, y); INC(a)
	END Put1;
	 
	PROCEDURE Put2 (VAR a: LONGINT; x: LONGINT);
	VAR y: INTEGER;
	BEGIN y := SHORT(x); SYSTEM.PUT(a, y); a := a + 2
	END Put2;
	 
	PROCEDURE Put4 (VAR a: LONGINT; x: LONGINT);
	BEGIN SYSTEM.PUT(a, x); a := a + 4
	END Put4;

	PROCEDURE ReadInt (VAR R: Files.Rider; VAR x: INTEGER);
	VAR c0: CHAR; s1: SHORTINT;
	BEGIN Files.Read(R, c0); Files.Read(R, s1); x := s1; x := x * 100H + ORD(c0)
	END ReadInt;

	PROCEDURE *GetCharObj (L: Objects.Library; ref: INTEGER; VAR obj: Objects.Object);
	CODE {SYSTEM.i386}
		MOV EAX, L[EBP]
		MOV EAX, 4[EAX]	; Objects.LibDesc ind
		MOVSX EBX, ref[EBP]
		MOV EAX, [EAX][EBX*4]
		MOV ECX, theChar
		MOVZX DX, BYTE -3[EAX] ;dx
		MOV 24[ECX], DX
		MOVSX DX, BYTE -2[EAX] ;x
		MOV 26[ECX], DX
		MOVSX DX, BYTE -1[EAX] ;y
		MOV 28[ECX], DX
		MOVZX DX, BYTE [EAX] ;w
		MOV 30[ECX], DX
		MOVZX DX, BYTE 1[EAX] ;h
		MOV 32[ECX], DX
		MOV 36[ECX], EAX
		MOV EAX, obj[EBP]
		MOV [EAX], ECX
	END GetCharObj;

(*
	(* portable version *)
	PROCEDURE GetCharObj (L: Objects.Library; ref: INTEGER; VAR obj: Objects.Object);	
	VAR m: LONGINT; h1: SHORTINT; h2: LONGINT; ch: CHAR;
	BEGIN
		SYSTEM.GET(SYSTEM.VAL(LONGINT, L) + 4, m); (* L.ind *)
		SYSTEM.GET(m + ref * SIZE(LONGINT), h2); (* pat adr*)
		theChar.pat := h2; 
		SYSTEM.GET(h2-3, h1); theChar.dx := h1; 
		SYSTEM.GET(h2-2, h1); theChar.x := h1;
		SYSTEM.GET(h2-1, h1); theChar.y := h1;
		SYSTEM.GET(h2, ch); theChar.w := ORD(ch);	(*width & height always positive*)
		SYSTEM.GET(h2+1,ch); theChar.h := ORD(ch);
		obj := theChar
	END GetCharObj;
*)

(** Return the character and data of ch in a font. *)
	PROCEDURE GetChar* (F: Font; ch: CHAR; VAR dx, x, y, w, h: INTEGER; VAR pat: Display.Pattern);
	VAR obj: Objects.Object;
	BEGIN F.GetObj(F, ORD(ch), obj);
		WITH obj: Char DO
			dx := obj.dx; x := obj.x; y := obj.y; w := obj.w; h := obj.h; pat := obj.pat
		END
	END GetChar;

	PROCEDURE Internalize (F: Font; VAR R: Files.Rider; type: SHORTINT);
	VAR n: SHORTINT; ch: CHAR;
			NofRuns, NofBoxes, N, i, k, l, m: INTEGER;
			NofBytes, RasterBase, A, a: LONGINT;
			run: ARRAY MaxRuns OF RunRec;
			box: ARRAY 256 OF BoxRec;
	BEGIN F.type := type;
		Files.Read(R, ch); (*family*)
		Files.Read(R, ch); (*variant*)
		ReadInt(R, F.height);
		ReadInt(R, F.minX); ReadInt(R, F.maxX);
		ReadInt(R, F.minY); ReadInt(R, F.maxY);
		ReadInt(R, NofRuns);
		NofBoxes := 0; k := 0;
		WHILE k # NofRuns DO
			ReadInt(R, run[k].beg); ReadInt(R, run[k].end);
			NofBoxes := NofBoxes + run[k].end - run[k].beg;
			INC(k)
		END;
		l := 0;
		WHILE l # NofBoxes DO
			ReadInt(R, box[l].dx);
			ReadInt(R, box[l].x); ReadInt(R, box[l].y);
			ReadInt(R, box[l].w); ReadInt(R, box[l].h);
			INC(l)
		END;
		IF type = font THEN
			NofBytes := IndexSize + 29; l := 0;
			WHILE l # NofBoxes DO
				NofBytes := NofBytes + 5 + (box[l].w + 7) DIV 8 * box[l].h; INC(l)
			END;
			SYSTEM.NEW(F.ind, NofBytes);
			RasterBase := SYSTEM.VAL(LONGINT, F.ind);
			A := RasterBase; a := A + IndexSize;
			Put1(a, 12); Put1(a, 0); Put1(a, -3); Put1(a, 12); Put1(a, 12); (*null char*)
			Put2(a, 0FFFH);
			Put2(a, 0801H); Put2(a, 0801H); Put2(a, 0801H); Put2(a, 0801H); Put2(a, 0801H);
			Put2(a, 0801H); Put2(a, 0801H); Put2(a, 0801H); Put2(a, 0801H); Put2(a, 0801H);
			Put2(a, 0FFFH);
			k := 0; l := 0; m := 0;
			WHILE k < NofRuns DO
				WHILE m < run[k].beg DO Put4(A, RasterBase + IndexSize + 3); INC(m) END;
				WHILE m < run[k].end DO Put4(A, a + 3);
					Put1(a, box[l].dx);
					Put1(a, box[l].x); Put1(a, box[l].y);
					Put1(a, box[l].w); Put1(a, box[l].h);
					i := (box[l].w + 7) DIV 8 * box[l].h;
					WHILE i # 0 DO Files.Read(R, ch); Put1(a, ORD(ch)); DEC(i) END;
					INC(l); INC(m)
				END;
				INC(k)
			END;
			WHILE m < 256 DO Put4(A, RasterBase + IndexSize + 3); INC(m) END
		ELSE (*type := metric*)
			SYSTEM.NEW(F.ind, IndexSize + 5 + NofBoxes*5);
			RasterBase := SYSTEM.VAL(LONGINT, F.ind);
			A := RasterBase; a := A + IndexSize;
			Put1(a, 12); Put1(a, 0); Put1(a, -3); Put1(a, 12); Put1(a, 12); (*null char*)
			k := 0; l := 0; m := 0;
			WHILE k < NofRuns DO
				WHILE m < run[k].beg DO Put4(A, RasterBase + IndexSize + 3); INC(m) END;
				WHILE m < run[k].end DO Put4(A, a + 3);
					Put1(a, box[l].dx);
					Put1(a, box[l].x); Put1(a, box[l].y);
					Put1(a, box[l].w); Put1(a, box[l].h);
					INC(l); INC(m)
				END;
				INC(k)
			END;
			WHILE m < 256 DO Put4(A, RasterBase + IndexSize + 3); INC(m) END
		END
	END Internalize;

	PROCEDURE Substitute (F: Font);
	BEGIN F.type := substitute;
		F.height := Default.height;
		F.minX := Default.minX; F.maxX := Default.maxX;
		F.minY := Default.minY; F.maxY := Default.maxY;
		F.ind := Default.ind;
		IF TraceMissing THEN
			Kernel.WriteString("Missing: ");  Kernel.WriteString(F.name);  Kernel.WriteLn
		END
	END Substitute;

	PROCEDURE *Load (L: Objects.Library);
	VAR f: Files.File; R: Files.Rider; id: CHAR; i, j: LONGINT;
			name: Objects.Name;
	BEGIN
		WITH L: Font DO
			f := Files.Old(L.name);
			IF f = NIL THEN
				COPY(L.name, name);  name[7] := 0X;
				IF name = "Default" THEN
					IF TraceAlias THEN Kernel.WriteString(L.name);  Kernel.WriteString(" -> ") END;
					COPY(default, name);
					i := 0;  WHILE name[i] # 0X DO INC(i) END;
					j := 7;  WHILE L.name[j] # 0X DO name[i] := L.name[j];  INC(i);  INC(j) END;
					name[i] := 0X;
					IF TraceAlias THEN Kernel.WriteString(name);  Kernel.WriteLn END;
					COPY(name, L.name);
					f := Files.Old(name)
				ELSE
					name[6] := 0X;
					IF conv & (name = "Syntax") THEN
						IF TraceAlias THEN Kernel.WriteString(L.name);  Kernel.WriteString(" -> ") END;
						name := "Oberon";
						i := 6;  WHILE (L.name[i] >= "0") & (L.name[i] <= "9") DO name[i] := L.name[i];  INC(i) END;
						IF L.name[i] = "j" THEN name[i] := "i";  INC(i)	(* Syntax italic bold -> Oberon italic *)
						ELSIF L.name[i] = "m" THEN name[i] := "b";  INC(i)	(* Syntax medium -> Oberon bold *)
						END;
						WHILE L.name[i] # 0X DO name[i] := L.name[i];  INC(i) END;
						name[i] := 0X;
						IF TraceAlias THEN Kernel.WriteString(name);  Kernel.WriteLn END;
						COPY(name, L.name);
						f := Files.Old(name)
					END
				END
			END;
			IF f # NIL THEN
				Files.Set(R, f, 0); Files.Read(R, id);
				IF id = FontId THEN Files.Read(R, L.type);
					IF (L.type = metric) OR (L.type = font) THEN Internalize(L, R, L.type) ELSE Substitute(L) END
				ELSE Substitute(L) END
			ELSE COPY(L.name, name); i := 0;
				WHILE name[i] # 0X DO INC(i) END;
				IF (i >= 8) & (name[i-8] = ".") & (name[i-7] = "M") & (name[i-6] = "d") THEN
					name[i-7] := "P"; name[i-6] := "r"; f := Files.Old(name);
					IF f # NIL THEN
						Files.Set(R, f, 0); Files.Read(R, id);
						IF id = FontId THEN Files.Read(R, L.type);
							IF (L.type = metric) OR (L.type = font) THEN Internalize(L, R, metric) ELSE Substitute(L) END
						ELSE Substitute(L) END
					ELSE Substitute(L) END
				ELSE Substitute(L) END
			END
		END
	END Load;

(** Load and cache a font. *)
	PROCEDURE This* (name: ARRAY OF CHAR): Font;
	VAR L: Objects.Library;
	BEGIN
		L := Objects.ThisLibrary(name);
		IF (L # NIL) & (L IS Font) THEN RETURN L(Font) ELSE RETURN NIL END
	END This;

	PROCEDURE *New (): Objects.Library;
	VAR F: Font;
	BEGIN NEW(F);
		F.Load := Load; F.GetObj := GetCharObj; RETURN F
	END New;

BEGIN FontId := 0DBX; NEW(theChar);
	Kernel.GetConfig("FontConv", default);
	conv := default[0] # "0";
	default := "Oberon";
	Objects.Register("Fnt", New)
END Fonts.

 (* Remarks:

1. Screen fonts and printer fonts are stored in files with extensions .Scn.Fnt and .Prx.Fnt respectively (the x refers to x00dpi printer fonts). A full font name (like Syntax12b.Scn.Fnt) has to be specified to load a font. Should the font not be available, a substitute font is created. This has the same name but the wrong character metrics (often the Syntax10 font is used instead). A file with an .Mdx.Fnt extension is a metric font containing only metric data and no raster patterns. Each printer font has an associated metric font. A metric font is used to make measurements while printing. Sometimes the font module is clever enough to simulate the presence of a metric font by reading the metric data from a printer font (the metric fonts need not necessarily be available). If you need to find out the size of a character on paper, you should always request a metric font (it is faster to load and requires less memory than the printer fonts). Some Font modules support Truetype fonts implemented in the host operating system.

2. Fonts are extensions of Libraries. Each letter of the font is a (virtual) object indexed by ASCII code. Note that to optimize garbage collection, the same object instance is returned for each call to the GetObj library method (no matter what font or character is involved). This is realized by copying the character raster and metrics from a specially compressed representation of the font data. The GetChar procedure fetches a character from the font using this mechanism. The PutObj, GenRef and Store methods of fonts have no function.

3. The pattern (raster) of a character is only as large as required. The x, y, w, h values of a character metric specify the offset of the pattern from a virtual text baseline and the width and height of the pattern. Display.CopyPattern is used to draw the character patterns of the display. Help procedures like Display3.String hides the low-level display process and allows you to display strings at a time.

4. The default font is Oberon10.Scn.Fnt. 
*)