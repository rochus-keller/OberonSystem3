MODULE GfxMaps;	(** eos   **)

	(**
		Raster maps and image processing
	**)
	
	(*
		9.12.98 - this should now be the one to be released
		25.1.99 - made maps be objects
		3.3.99 - handle Display.Depth() > 8 in InitDisplayPalette (tnx to G.Feldmann@informatik.Uni-Bremen.de)
		5.3.99 - made Copy deal with overlapping source and destination area
		10.3.99 - made Create more robust
		15.4.99 - added InitBuf
		15.4.99 - bugfix in Transform: can't overlay temporary maps for pixel format with alpha
		20.4.99 - optimized blend procedures for alpha sources
	*)
	
	IMPORT
		SYSTEM, Files, Display, Objects, Texts, Oberon, GfxMatrix;
		
	
	(* Ports to big-endian architectures: search for ">>byte order!" *)
	
	
	CONST
		B* = 0; G* = 1; R* = 2; A* = 3;	(** indices of components within pixel **)
		
	
	TYPE
		(** pixels with red, green, blue, and alpha information in range 0..255 **)
		Pixel* = ARRAY 4 OF CHAR;
		
		(** color structure with red, green, and blue values in range 0..255 **)
		Color* = RECORD
			r*, g*, b*: INTEGER;
		END;
		
		(** palette structure for indexed map formats **)
		Palette* = POINTER TO PaletteDesc;
		PaletteDesc* = RECORD
			col*: ARRAY 256 OF Color;	(** color table **)
			used*: INTEGER;	(** number of valid entries in color table **)
			cube: ARRAY 8*8*8+1 OF CHAR;
			index: ARRAY 256 OF CHAR;
		END;
		
	VAR
		DisplayPal*: Palette;	(** display palette **)
		
		
	(**
		Although abstract operations on raster maps are available, efficient algorithms often use highly specialized
		pixel formats and need direct access to the memory of the raster map. The internal structure of a map is
		therefore laid open to clients and has the following properties:
			- a map references a contiguous block in memory holding pixel data
			- pixels are organized in rows (usually bottom-up, but can also be top-down)
			- rows can be aligned to an arbitrary number of bytes
			- the leftmost pixel in a row has the lowest address of all pixels in that row
			- every pixel uses the same number of bits; this number must be a multiple or a factor of 8 in range [1..32]
			- pixels using less than 8 bits may be ordered in ascending or descending order within a byte, but...
			- bit addresses within a byte ascend from left to right
			- the components in a pixel are managed by a format record, with procedures for storing and loading pixels
			- optimized pixel transfer routines exist for predefined formats exported as global variables
	**)
	
	CONST
		Red* = 0; Green* = 1; Blue* = 2; Alpha* = 3; Grey* = 4; Index* = 5;	(** component names **)
		a1* = 1; a8* = 2; i8* = 3; bgr555* = 4; bgr565* = 5; bgr24* = 6; bgra32* = 7;	(** format codes **)
	
	
	TYPE
		Format0* = RECORD
			code*: INTEGER;	(** format code for quick format checks **)
			bpp*: SHORTINT;	(** number of bits per pixel **)
			align*: SHORTINT;	(** bytes per row must be multiple of this **)
			components*: SET;	(** set of components that are stored in a pixel **)
			col*: Color;	(** color used when transfering from pure alpha formats to colored ones **)
			pal*: Palette;	(** palette for indexed formats **)
		END;
		
		PackProc* = PROCEDURE (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		
		(** map format **)
		Format* = RECORD (Format0)
			pack*, unpack*: PackProc;	(** procedures storing and loading pixel at given address **)
		END;
		
		(** raster map **)
		Map* = POINTER TO MapDesc;
		MapDesc* = RECORD (Objects.ObjDesc)
			width*, height*: INTEGER;	(** map dimensions **)
			fmt*: Format;	(** pixel format **)
			bpr*: LONGINT;	(** number of bytes per row (may be negative) **)
			adr*: LONGINT;	(** address of lower left pixel **)
			mem*: POINTER TO ARRAY OF CHAR;	(** block where pixels are stored; mem#NIL implies adr=ADR(mem[0]) **)
		END;
		
	VAR
		A1*, A8*, I8*, BGR555*, BGR565*, BGR24*, BGRA32*, PixelFormat*: Format;	(** predefined formats **)
		
		
	(**
		In the context of image processing and alpha channels, an operation may sometimes have to blend
		source and destination pixels to compute the final value for destination pixels. Most operations therefore
		expect a blend operator that specifies how to combine source with destination pixels. Blend operators
		exported in global variables get special treatment using optimized code.
	**)
	
	TYPE
		BlendOp0 = RECORD
			pix: Pixel;	(* constant area for special-case moving *)
			src, dst: Format;	(* source and destination format if needed for transfer *)
			used: ARRAY 8 OF SET;	(* colors already mapped in I8 => I8 transformation *)
			map: ARRAY 256 OF CHAR;	(* color mapping for I8 => I8 transformation *)
		END;
		
		BlendProc* = PROCEDURE (VAR bl: BlendOp0; src, dst: Pixel; VAR res: Pixel);
		MoveProc* = PROCEDURE (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		
		(** blend operator **)
		BlendOp* = RECORD (BlendOp0)
			blend*: BlendProc;	(** procedure blending source with destination pixel **)
			move*: MoveProc;	(** procedure transfering pixels from source to destination **)
		END;
		
	VAR
		SrcCopy*: BlendOp;	(** direct copy of source to destination (cf. Display.replace) **)
		SrcAlpha*: BlendOp;	(** dest = src.alpha * src + (1-src.alpha) * dest;  (cf. Display.paint) **)
		SrcCopyBlend, SrcAlphaBlend: BlendProc;	(* for comparisons *)
		
		
	(**
		Map transform operations are decomposed into a series of one-dimensional shift and scale transforms. These
		are delegated to a filter object provided by the caller. The caller controls visual quality and execution time
		by selecting a filter which complies with its demands.
	**)
	
	TYPE
		Filter0* = RECORD (BlendOp)
		END;
		
		ShiftProc* = PROCEDURE (VAR filter: Filter0; src, dst: Map; sadr, sbit, dadr, dbit, len: LONGINT; t: REAL);
		ScaleProc* = PROCEDURE (VAR filter: Filter0; src, dst: Map; sadr, sbit, dadr, dbit, len: LONGINT; xy, dxy: REAL);
		
		(** transformation filter **)
		Filter* = RECORD (Filter0)
			hshift*, vshift*: ShiftProc;	(** procedures for shifting rows and columns **)
			hscale*, vscale*: ScaleProc;	(** procedures for scaling rows and columns **)
		END;
		
	VAR
		NoFilter*: Filter;	(** uses nearest-neighbor resampling (box filter); bad aliasing when downscaling **)
		LinearFilter*: Filter;	(** uses linear interpolation (triangle filter); blurry when upscaling **)
		
	
	(**
		The mechanism for loading and storing image maps relies on a section 'ImageFormats' in the registry
		(Oberon.Text). It consists of a list of file types associated with command procedures. When one of these
		commands is called, it should initialize the global 'LoadProc' and 'StoreProc' variables. These, when called,
		should read an image from or write an image to the file and set 'done' to TRUE if successful. If no
		procedure is associated with the filename extension, all of them are tried for loading, therefore 'LoadProc'
		procedures must not set 'done' to TRUE in case they don't recognize the file.
	**)
	
	VAR
		LoadProc*: PROCEDURE (map: Map; VAR fname: ARRAY OF CHAR; VAR done: BOOLEAN);
		StoreProc*: PROCEDURE (map: Map; VAR fname: ARRAY OF CHAR; VAR done: BOOLEAN);
		
	
	VAR
		Bit: ARRAY 100H, 8 OF BOOLEAN;	(* Bit[b, i] means bit i (from left) in byte b is set *)
		Set, Clear: ARRAY 100H, 8 OF CHAR;	(* Set/Clear[b, i] is byte b with bit i (from left) set/cleared *)
		Clamp: ARRAY 500H OF CHAR;	(* Clamp[200H+i] clamps i to 0..0FFX *)
		PreCache, Cache: Map;	(* caches for image transformations *)
		
	
	(**--- Color/Pixel conversions ---**)
	
	PROCEDURE ColorToPixel* (col: Color; VAR pix: Pixel);
	BEGIN
		pix[B] := CHR(col.b); pix[G] := CHR(col.g); pix[R] := CHR(col.r); pix[A] := 0FFX
	END ColorToPixel;
	
	PROCEDURE PixelToColor* (pix: Pixel; VAR col: Color);
	BEGIN
		col.r := ORD(pix[R]); col.g := ORD(pix[G]); col.b := ORD(pix[B])
	END PixelToColor;
	
	
	(**--- Image Maps ---**)
	
	PROCEDURE^ Handle* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
	
	(** initialize custom format **)
	PROCEDURE InitFormat* (VAR fmt: Format; bpp, align: SHORTINT; comps: SET; pal: Palette; pack, unpack: PackProc);
	BEGIN
		fmt.code := 0; fmt.bpp := bpp; fmt.align := align; fmt.components := comps; fmt.pal := pal;
		fmt.pack := pack; fmt.unpack := unpack;
		fmt.col.r := 0; fmt.col.g := 0; fmt.col.b := 0
	END InitFormat;
	
	(** initialize custom map **)
	PROCEDURE Init* (map: Map; width, height: INTEGER; VAR fmt: Format; bpr, adr: LONGINT);
	BEGIN
		ASSERT((width > 0) & (height > 0), 100);
		map.handle := Handle; map.width := width; map.height := height; map.fmt := fmt; map.bpr := bpr; map.adr := adr
	END Init;
	
	(** initialize custom map on byte buffer **)
	PROCEDURE InitBuf* (map: Map; width, height: INTEGER; VAR fmt: Format; bpr: LONGINT; VAR buf: ARRAY OF CHAR);
	BEGIN
		ASSERT(height * ABS(bpr) <= LEN(buf), 100);
		IF bpr >= 0 THEN Init(map, width, height, fmt, bpr, SYSTEM.ADR(buf[0]))
		ELSE Init(map, width, height, fmt, bpr, SYSTEM.ADR(buf[0]) + LEN(buf) - bpr)
		END
	END InitBuf;
	
	(** create image map in requested format (allocating or reusing necessary memory) **)
	PROCEDURE Create* (map: Map; width, height: INTEGER; VAR fmt: Format);
		VAR size, a0, a1: LONGINT;
	BEGIN
		ASSERT((width > 0) & (height > 0), 100);
		map.handle := Handle;
		map.width := width; map.height := height;
		map.fmt := fmt;
		map.bpr := (width * fmt.bpp + 7) DIV 8;
		IF fmt.align > 1 THEN
			map.bpr := (map.bpr + fmt.align - 1) DIV fmt.align * fmt.align
		END;
		size := height * map.bpr; INC(size, (-size) MOD 4);
		IF (map.mem = NIL) OR (size < LEN(map.mem^) DIV 2) OR (LEN(map.mem^) < size) THEN
			NEW(map.mem, size)
		ELSE
			a0 := SYSTEM.ADR(map.mem[0]); a1 := a0 + size;
			WHILE a0 # a1 DO
				SYSTEM.PUT(a0, LONG(LONG(0))); INC(a0, SIZE(LONGINT))
			END
		END;
		map.adr := SYSTEM.ADR(map.mem[0])
	END Create;
	
	PROCEDURE GetExtension (VAR name, ext: ARRAY OF CHAR);
		VAR i, j: LONGINT; ch: CHAR;
	BEGIN
		i := 0; j := 0;
		WHILE name[i] # 0X DO
			IF name[i] = "." THEN j := i+1 END;
			INC(i)
		END;
		i := 0;
		REPEAT
			ch := name[j]; ext[i] := ch; INC(i); INC(j)
		UNTIL ch = 0X
	END GetExtension;
	
	PROCEDURE Install (VAR s: Texts.Scanner; VAR ext: ARRAY OF CHAR);
		VAR str: ARRAY 64 OF CHAR; res: INTEGER;
	BEGIN
		ASSERT(s.class IN {Texts.Name, Texts.String});
		COPY(s.s, str); Texts.Scan(s);
		IF (s.class = Texts.Char) & (s.c = "=") THEN	(* str contains extension *)
			IF (ext # "") & (ext # str) THEN
				str := ""; Texts.Scan(s)	(* don't try if extension doesn't match *)
			ELSE
				str := "";
				Texts.Scan(s);
				IF s.class = Texts.Name THEN
					COPY(s.s, str); Texts.Scan(s)
				END
			END
		END;
		IF str # "" THEN
			Oberon.Call(str, Oberon.Par, FALSE, res)
		END
	END Install;
	
	PROCEDURE TryLoad (map: Map; VAR name: ARRAY OF CHAR; ext: ARRAY OF CHAR; VAR done: BOOLEAN);
		VAR s: Texts.Scanner;
	BEGIN
		done := FALSE;
		Oberon.OpenScanner(s, "ImageFormats");
		WHILE ~done & (s.class IN {Texts.Name, Texts.String}) DO
			LoadProc := NIL;
			Install(s, ext);
			IF LoadProc # NIL THEN
				LoadProc(map, name, done)
			END
		END
	END TryLoad;
	
	(** initialize image map from file (see comment for LoadProc and StoreProc) **)
	PROCEDURE Load* (map: Map; name: ARRAY OF CHAR; VAR done: BOOLEAN);
		VAR file: Files.File; ext: ARRAY 64 OF CHAR;
	BEGIN
		done := FALSE; map.handle := Handle; map.width := 0; map.height := 0;
		file := Files.Old(name);
		IF file # NIL THEN
			GetExtension(name, ext);
			TryLoad(map, name, ext, done);
			IF ~done & (ext # "") THEN
				TryLoad(map, name, "", done)	(* try all converters *)
			END
		END
	END Load;
	
	(** store image map in file (see comment for LoadProc and StoreProc) **)
	PROCEDURE Store* (map: Map; name: ARRAY OF CHAR; VAR done: BOOLEAN);
		VAR ext: ARRAY 64 OF CHAR; s: Texts.Scanner;
	BEGIN
		done := FALSE;
		GetExtension(name, ext);
		IF ext # "" THEN
			Oberon.OpenScanner(s, "ImageFormats");
			WHILE ~done & (s.class IN {Texts.Name, Texts.String}) DO
				StoreProc := NIL;
				Install(s, ext);
				IF StoreProc # NIL THEN
					StoreProc(map, name, done)
				END
			END
		END
	END Store;
	
	
	(** predefined blend procedures **)
	
	PROCEDURE SrcCopyProc* (VAR bl: BlendOp0; src, dst: Pixel; VAR res: Pixel);
	BEGIN
		res := src
	END SrcCopyProc;
	
	PROCEDURE SrcAlphaProc* (VAR bl: BlendOp0; src, dst: Pixel; VAR res: Pixel);
		VAR as, ad: LONGINT;
	BEGIN
		IF src[A] = 0FFX THEN
			res := src
		ELSIF src[A] # 0X THEN
			as := ORD(src[A]); ad := 0FFH - as;
			res[R] := CHR((ORD(src[R]) * as + ORD(dst[R]) * ad) DIV 255);
			res[G] := CHR((ORD(src[G]) * as + ORD(dst[G]) * ad) DIV 255);
			res[B] := CHR((ORD(src[B]) * as + ORD(dst[B]) * ad) DIV 255);
			res[A] := CHR(as + ORD(dst[A]) * ad DIV 255)
		END
	END SrcAlphaProc;
	
	
	(*--- Predefined Pack/Unpack Procedures ---*)
	
	PROCEDURE^ BestIndex* (pal: Palette; red, green, blue: INTEGER): INTEGER;
	
	
	(*--- A1 ---*)
	
	PROCEDURE PackA1 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR b: CHAR;
	BEGIN
		SYSTEM.GET(adr, b);
		IF pix[A] >= 80X THEN SYSTEM.PUT(adr, Set[ORD(b), 7-bit])
		ELSE SYSTEM.PUT(adr, Clear[ORD(b), 7-bit])
		END
	END PackA1;
	
	PROCEDURE UnpackA1 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR b: CHAR;
	BEGIN
		SYSTEM.GET(adr, b);
		pix[R] := CHR(fmt.col.r); pix[G] := CHR(fmt.col.g); pix[B] := CHR(fmt.col.b);
		IF Bit[ORD(b), 7-bit] THEN pix[A] := 0FFX
		ELSE pix[A] := 0X
		END
	END UnpackA1;
	
	
	(*--- A8 ---*)
	
	PROCEDURE PackA8 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		SYSTEM.PUT(adr, pix[A])
	END PackA8;
	
	PROCEDURE UnpackA8 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		pix[R] := CHR(fmt.col.r); pix[G] := CHR(fmt.col.g); pix[B] := CHR(fmt.col.b); SYSTEM.GET(adr, pix[A])
	END UnpackA8;
	
	
	(*--- I8 ---*)
	
	PROCEDURE PackI8 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		SYSTEM.PUT(adr, CHR(BestIndex(fmt.pal, ORD(pix[R]), ORD(pix[G]), ORD(pix[B]))))
	END PackI8;
	
	PROCEDURE UnpackI8 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR idx: CHAR;
	BEGIN
		SYSTEM.GET(adr, idx);
		ColorToPixel(fmt.pal.col[ORD(idx)], pix)
	END UnpackI8;
	
	
	(*--- BGR555 ---*)
	
	PROCEDURE PackBGR555 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN	(* >>byte order! *)
		SYSTEM.PUT(adr, SHORT(ASH(ORD(pix[B]), -3) + ASH(ASH(ORD(pix[G]), -3), 5) + ASH(ASH(ORD(pix[R]), -3), 10)))
	END PackBGR555;
	
	PROCEDURE UnpackBGR555 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR int: INTEGER;
	BEGIN	(* >>byte order! *)
		SYSTEM.GET(adr, int);
		pix[B] := CHR(ASH(int MOD 20H, 3));
		pix[G] := CHR(ASH(ASH(int, -5) MOD 20H, 3));
		pix[R] := CHR(ASH(ASH(int, -10) MOD 20H, 3));
		pix[A] := 0FFX
	END UnpackBGR555;
	
	
	(*--- BGR565 ---*)
	
	PROCEDURE PackBGR565 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN	(* >>byte order! *)
		SYSTEM.PUT(adr, SHORT(ASH(ORD(pix[B]), -3) + ASH(ASH(ORD(pix[G]), -2), 5) + ASH(ASH(ORD(pix[R]), -3), 11)))
	END PackBGR565;
	
	PROCEDURE UnpackBGR565 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
		VAR int: INTEGER;
	BEGIN	(* >>byte order! *)
		SYSTEM.GET(adr, int);
		pix[B] := CHR(ASH(int MOD 20H, 3));
		pix[G] := CHR(ASH(ASH(int, -5) MOD 40H, 2));
		pix[R] := CHR(ASH(ASH(int, -11) MOD 20H, 3));
		pix[A] := 0FFX
	END UnpackBGR565;
	
	
	(*--- BGR24 ---*)
	
	PROCEDURE PackBGR24 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		SYSTEM.PUT(adr, pix[B]); SYSTEM.PUT(adr+1, pix[G]); SYSTEM.PUT(adr+2, pix[R])
	END PackBGR24;
	
	PROCEDURE UnpackBGR24 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		SYSTEM.GET(adr, pix[B]); SYSTEM.GET(adr+1, pix[G]); SYSTEM.GET(adr+2, pix[R]); pix[A] := 0FFX
	END UnpackBGR24;
	
	
	(*--- BGRA32 ---*)
	
	PROCEDURE PackBGRA32 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		SYSTEM.MOVE(SYSTEM.ADR(pix[0]), adr, 4)
	END PackBGRA32;
	
	PROCEDURE UnpackBGRA32 (VAR fmt: Format0; adr, bit: LONGINT; VAR pix: Pixel);
	BEGIN
		SYSTEM.MOVE(adr, SYSTEM.ADR(pix[0]), 4)
	END UnpackBGRA32;
	
	
	(*--- Optimized SrcAlpha Procedures ---*)
	
	PROCEDURE BlendA1A1 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in, out: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in); SYSTEM.GET(dadr, out);
		WHILE len > 0 DO
			IF Bit[ORD(in), 7-sbit] THEN
				out := Set[ORD(out), 7-dbit]
			END;
			INC(sbit); INC(dbit); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END;
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out);
				INC(dadr); dbit := 0;
				SYSTEM.GET(dadr, out)
			END
		END;
		SYSTEM.PUT(dadr, out)
	END BlendA1A1;
	
	PROCEDURE BlendA1Const8 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), 7-sbit] THEN
				SYSTEM.PUT(dadr, bl.pix[0])
			END;
			INC(sbit); INC(dadr); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END BlendA1Const8;
	
	PROCEDURE BlendA1Const16 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), 7-sbit] THEN
				SYSTEM.MOVE(SYSTEM.ADR(bl.pix[0]), dadr, 2)
			END;
			INC(sbit); INC(dadr, 2); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END BlendA1Const16;
	
	PROCEDURE BlendA1Const24 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), 7-sbit] THEN
				SYSTEM.MOVE(SYSTEM.ADR(bl.pix[0]), dadr, 3)
			END;
			INC(sbit); INC(dadr, 3); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END BlendA1Const24;
	
	PROCEDURE BlendA1Const32 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), 7-sbit] THEN
				SYSTEM.MOVE(SYSTEM.ADR(bl.pix[0]), dadr, 4)
			END;
			INC(sbit); INC(dadr, 4); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END BlendA1Const32;
	
	PROCEDURE BlendA1Any (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), 7-sbit] THEN
				bl.dst.pack(bl.dst, dadr, dbit, bl.pix)
			END;
			INC(sbit); dbit := dbit + bl.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END BlendA1Any;
	
	PROCEDURE BlendA8A1 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in, out: CHAR;
	BEGIN
		SYSTEM.GET(dadr, out);
		WHILE len > 0 DO
			SYSTEM.GET(sadr, in);
			IF in >= 80X THEN
				out := Set[ORD(out), 7-dbit]
			END;
			INC(sadr); INC(dbit); DEC(len);
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out);
				INC(dadr); dbit := 0;
				SYSTEM.GET(dadr, out)
			END
		END;
		SYSTEM.PUT(dadr, out)
	END BlendA8A1;
	
	PROCEDURE BlendA8A8 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in, out: CHAR;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, in);
			IF in = 0FFX THEN
				SYSTEM.PUT(dadr, 0FFX)
			ELSIF in # 0X THEN
				SYSTEM.GET(dadr, out);
				SYSTEM.PUT(dadr, CHR(ORD(in) + ORD(out) * (0FFH - ORD(in)) DIV 0FFH))
			END;
			INC(sadr); INC(dadr); DEC(len)
		END
	END BlendA8A8;
	
	PROCEDURE BlendA8Any (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR dpix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, bl.pix[A]);
			IF bl.pix[A] # 0X THEN
				bl.dst.unpack(bl.dst, dadr, dbit, dpix);
				SrcAlphaProc(bl, bl.pix, dpix, dpix);
				bl.dst.pack(bl.dst, dadr, dbit, dpix)
			END;
			INC(sadr); DEC(len);
			dbit := dbit + bl.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8
		END
	END BlendA8Any;
	
	PROCEDURE BlendBGRA32A1 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in, out: CHAR;
	BEGIN
		SYSTEM.GET(dadr, out);
		WHILE len > 0 DO
			SYSTEM.GET(sadr + A, in);
			IF in >= 80X THEN
				out := Set[ORD(out), 7-dbit]
			END;
			INC(sadr, 4); INC(dbit); DEC(len);
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out);
				INC(dadr); dbit := 0;
				SYSTEM.GET(dadr, out)
			END
		END;
		SYSTEM.PUT(dadr, out)
	END BlendBGRA32A1;
	
	PROCEDURE BlendBGRA32A8 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in, out: CHAR;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr + A, in);
			IF in = 0FFX THEN
				SYSTEM.PUT(dadr, 0FFX)
			ELSIF in # 0X THEN
				SYSTEM.GET(dadr, out);
				SYSTEM.PUT(dadr, CHR(ORD(in) + ORD(out) * (0FFH - ORD(in)) DIV 0FFH))
			END;
			INC(sadr, 4); INC(dadr); DEC(len)
		END
	END BlendBGRA32A8;
	
	PROCEDURE BlendBGRA32Any (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR spix, dpix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, SYSTEM.ADR(spix[0]), 4);
			IF spix[A] # 0X THEN
				bl.dst.unpack(bl.dst, dadr, dbit, dpix);
				SrcAlphaProc(bl, spix, dpix, dpix);
				bl.dst.pack(bl.dst, dadr, dbit, dpix)
			END;
			INC(sadr, 4); DEC(len);
			dbit := dbit + bl.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8
		END
	END BlendBGRA32Any;
	
	PROCEDURE BlendAnyAny (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR spix, dpix: Pixel;
	BEGIN
		WITH bl: BlendOp DO
			WHILE len > 0 DO
				bl.src.unpack(bl.src, sadr, sbit, spix);
				bl.dst.unpack(bl.dst, dadr, dbit, dpix);
				bl.blend(bl, spix, dpix, dpix);
				bl.dst.pack(bl.dst, dadr, dbit, dpix);
				sbit := sbit + bl.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8;
				dbit := dbit + bl.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
				DEC(len)
			END
		END
	END BlendAnyAny;
	
	
	(*--- Optimized SrcCopy Procedures ---*)
	
	PROCEDURE MoveSetBit (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR out: CHAR;
	BEGIN
		IF (dbit > 0) OR (len < 8) THEN
			SYSTEM.GET(dadr, out);
			WHILE (dbit < 8) & (len > 0) DO
				out := Set[ORD(out), 7-dbit];
				INC(dbit); DEC(len)
			END;
			SYSTEM.PUT(dadr, out)
		END;
		WHILE len >= 8 DO
			SYSTEM.PUT(dadr, 0FFX);
			INC(dadr); DEC(len, 8)
		END;
		IF len > 0 THEN
			SYSTEM.GET(dadr, out); dbit := 0;
			REPEAT
				out := Set[ORD(out), 7-dbit];
				INC(dbit); DEC(len)
			UNTIL len = 0;
			SYSTEM.PUT(dadr, out)
		END
	END MoveSetBit;
	
	PROCEDURE Move1 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in, out: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE (sbit = 0) & (dbit = 0) & (len >= 8) DO
			SYSTEM.PUT(dadr, in);
			INC(sadr); INC(dadr); DEC(len, 8);
			SYSTEM.GET(sadr, in)
		END;
		IF (dbit > 0) OR (len < 8) THEN
			SYSTEM.GET(dadr, out)
		END;
		WHILE len > 0 DO
			IF Bit[ORD(in), 7-sbit] THEN
				out := Set[ORD(out), 7-dbit]
			ELSE
				out := Clear[ORD(out), 7-dbit]
			END;
			INC(sbit); INC(dbit); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END;
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out);
				INC(dadr); dbit := 0;
				IF len < 8 THEN
					SYSTEM.GET(dadr, out)
				END
			END
		END;
		IF dbit > 0 THEN
			SYSTEM.PUT(dadr, out)
		END
	END Move1;
	
	PROCEDURE MoveA1A8 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR in: CHAR;
	BEGIN
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), 7-sbit] THEN
				SYSTEM.PUT(dadr, 0FFX)
			ELSE
				SYSTEM.PUT(dadr, 0X)
			END;
			INC(sbit); INC(dadr); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END MoveA1A8;
	
	PROCEDURE MoveA1BGRA32 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel; in: CHAR;
	BEGIN
		pix := bl.pix;
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), 7-sbit] THEN
				pix[A] := 0FFX
			ELSE
				pix[A] := 0X
			END;
			SYSTEM.MOVE(SYSTEM.ADR(pix), dadr, 4);
			INC(sbit); INC(dadr, 4); DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END MoveA1BGRA32;
	
	PROCEDURE MoveA1Any (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel; in: CHAR;
	BEGIN
		pix := bl.pix;
		SYSTEM.GET(sadr, in);
		WHILE len > 0 DO
			IF Bit[ORD(in), 7-sbit] THEN
				pix[A] := 0FFX
			ELSE
				pix[A] := 0X
			END;
			bl.dst.pack(bl.dst, dadr, dbit, pix);
			INC(sbit); dbit := dbit + bl.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len);
			IF sbit = 8 THEN
				INC(sadr); sbit := 0;
				SYSTEM.GET(sadr, in)
			END
		END
	END MoveA1Any;
	
	PROCEDURE Move8 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR byte: CHAR;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, byte); SYSTEM.PUT(dadr, byte);
			INC(sadr); INC(dadr); DEC(len)
		END
	END Move8;
	
	PROCEDURE MoveConst8 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		WHILE len > 0 DO
			SYSTEM.PUT(dadr, bl.pix[0]);
			INC(dadr); DEC(len)
		END
	END MoveConst8;
	
	PROCEDURE MoveA8A1 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR out, in: CHAR;
	BEGIN
		IF (dbit > 0) OR (len < 8) THEN
			SYSTEM.GET(dadr, out)
		END;
		WHILE len > 0 DO
			SYSTEM.GET(sadr, in);
			IF in >= 80X THEN
				out := Set[ORD(out), 7-dbit]
			ELSE
				out := Clear[ORD(out), 7-dbit]
			END;
			INC(sadr); INC(dbit); DEC(len);
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out);
				INC(dadr); dbit := 0;
				IF len < 8 THEN
					SYSTEM.GET(dadr, out)
				END
			END
		END;
		IF dbit > 0 THEN
			SYSTEM.PUT(dadr, out)
		END
	END MoveA8A1;
	
	PROCEDURE MoveA8BGRA32 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		pix := bl.pix;
		WHILE len > 0 DO
			SYSTEM.GET(sadr, pix[A]);
			SYSTEM.MOVE(SYSTEM.ADR(pix), dadr, 4);
			INC(sadr); INC(dadr, 4); DEC(len)
		END
	END MoveA8BGRA32;
	
	PROCEDURE MoveA8Any (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		pix := bl.pix;
		WHILE len > 0 DO
			SYSTEM.GET(sadr, pix[A]);
			bl.dst.pack(bl.dst, dadr, dbit, pix);
			INC(sadr); dbit := dbit + bl.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len)
		END
	END MoveA8Any;
	
	PROCEDURE MoveI8I8 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR byte: CHAR; idx: LONGINT; col: Color;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, byte); idx := ORD(byte);
			IF ~(idx MOD 32 IN bl.used[idx DIV 32]) THEN
				INCL(bl.used[idx DIV 32], idx MOD 32);
				col := bl.src.pal.col[idx];
				bl.map[idx] := CHR(BestIndex(bl.dst.pal, col.r, col.g, col.b))
			END;
			SYSTEM.PUT(dadr, bl.map[idx]);
			INC(sadr); INC(dadr); DEC(len)
		END
	END MoveI8I8;
	
	PROCEDURE MoveI8BGR555 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR b: CHAR; col: Color;
	BEGIN	(* >>byte order! *)
		WHILE len > 0 DO
			SYSTEM.GET(sadr, b);
			col := bl.src.pal.col[ORD(b)];
			SYSTEM.PUT(dadr, SHORT(ASH(col.b, -3) + ASH(ASH(col.g, -3), 5) + ASH(ASH(col.r, -3), 10)));
			INC(sadr); INC(dadr, 2); DEC(len)
		END
	END MoveI8BGR555;
	
	PROCEDURE MoveI8BGR565 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR b: CHAR; col: Color;
	BEGIN	(* >>byte order! *)
		WHILE len > 0 DO
			SYSTEM.GET(sadr, b);
			col := bl.src.pal.col[ORD(b)];
			SYSTEM.PUT(dadr, SHORT(ASH(col.b, -3) + ASH(ASH(col.g, -2), 5) + ASH(ASH(col.r, -3), 11)));
			INC(sadr); INC(dadr, 2); DEC(len)
		END
	END MoveI8BGR565;
	
	PROCEDURE MoveI8BGR24 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR byte: CHAR; pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, byte);
			ColorToPixel(bl.src.pal.col[ORD(byte)], pix);
			SYSTEM.MOVE(SYSTEM.ADR(pix[0]), dadr, 3);
			INC(sadr); INC(dadr, 3); DEC(len)
		END
	END MoveI8BGR24;
	
	PROCEDURE MoveI8BGRA32 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR byte: CHAR; pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, byte);
			ColorToPixel(bl.src.pal.col[ORD(byte)], pix);
			SYSTEM.MOVE(SYSTEM.ADR(pix[0]), dadr, 4);
			INC(sadr); INC(dadr, 4); DEC(len)
		END
	END MoveI8BGRA32;
	
	PROCEDURE MoveI8Any (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR byte: CHAR; pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, byte);
			ColorToPixel(bl.src.pal.col[ORD(byte)], pix);
			bl.dst.pack(bl.dst, dadr, dbit, pix);
			INC(sadr); dbit := dbit + bl.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len)
		END
	END MoveI8Any;
	
	PROCEDURE Move16 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR int: INTEGER;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, int); SYSTEM.PUT(dadr, int);
			INC(sadr, 2); INC(dadr, 2); DEC(len)
		END
	END Move16;
	
	PROCEDURE MoveConst16 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR int: INTEGER;
	BEGIN
		SYSTEM.GET(SYSTEM.ADR(bl.pix[0]), int);
		WHILE len > 0 DO
			SYSTEM.PUT(dadr, int);
			INC(dadr, 2); DEC(len)
		END
	END MoveConst16;
	
	PROCEDURE MoveBGR555I8 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR int, r, g, b: INTEGER;
	BEGIN	(* >>byte order! *)
		WHILE len > 0 DO
			SYSTEM.GET(sadr, int);
			r := SHORT(ASH(ASH(int, -10) MOD 20H, 3));
			g := SHORT(ASH(ASH(int, -5) MOD 20H, 3));
			b := SHORT(ASH(int MOD 20H, 3));
			SYSTEM.PUT(dadr, CHR(BestIndex(bl.dst.pal, r, g, b)));
			INC(sadr, 2); INC(dadr); DEC(len)
		END
	END MoveBGR555I8;
	
	PROCEDURE MoveBGR555BGR24 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR int: INTEGER;
	BEGIN	(* >>byte order! *)
		WHILE len > 0 DO
			SYSTEM.GET(sadr, int);
			SYSTEM.PUT(dadr, CHR(ASH(int MOD 20H, 3)));
			SYSTEM.PUT(dadr+1, CHR(ASH(ASH(int, -5) MOD 20H, 3)));
			SYSTEM.PUT(dadr+2, CHR(ASH(ASH(int, -10) MOD 20H, 3)));
			INC(sadr, 2); INC(dadr, 3); DEC(len)
		END
	END MoveBGR555BGR24;
	
	PROCEDURE MoveBGR555BGRA32 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR int: INTEGER;
	BEGIN	(* >>byte order! *)
		WHILE len > 0 DO
			SYSTEM.GET(sadr, int);
			SYSTEM.PUT(dadr, CHR(ASH(int MOD 20H, 3)));
			SYSTEM.PUT(dadr+1, CHR(ASH(ASH(int, -5) MOD 20H, 3)));
			SYSTEM.PUT(dadr+2, CHR(ASH(ASH(int, -10) MOD 20H, 3)));
			SYSTEM.PUT(dadr+3, 0FFX);
			INC(sadr, 2); INC(dadr, 4); DEC(len)
		END
	END MoveBGR555BGRA32;
	
	PROCEDURE MoveBGR555Any (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR int: INTEGER; pix: Pixel;
	BEGIN	(* >>byte order! *)
		WHILE len > 0 DO
			SYSTEM.GET(sadr, int);
			pix[B] := CHR(ASH(int MOD 20H, 3));
			pix[G] := CHR(ASH(ASH(int, -5) MOD 20H, 3));
			pix[R] := CHR(ASH(ASH(int, -10) MOD 20H, 3));
			pix[A] := 0FFX;
			bl.dst.pack(bl.dst, dadr, dbit, pix);
			INC(sadr, 2); dbit := dbit + bl.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len)
		END
	END MoveBGR555Any;
	
	PROCEDURE MoveBGR565I8 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR int, r, g, b: INTEGER;
	BEGIN	(* >>byte order! *)
		WHILE len > 0 DO
			SYSTEM.GET(sadr, int);
			r := SHORT(ASH(ASH(int, -11) MOD 20H, 3));
			g := SHORT(ASH(ASH(int, -5) MOD 40H, 2));
			b := SHORT(ASH(int MOD 20H, 3));
			SYSTEM.PUT(dadr, CHR(BestIndex(bl.dst.pal, r, g, b)));
			INC(sadr, 2); INC(dadr); DEC(len)
		END
	END MoveBGR565I8;
	
	PROCEDURE MoveBGR565BGR24 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR int: INTEGER;
	BEGIN	(* >>byte order! *)
		WHILE len > 0 DO
			SYSTEM.GET(sadr, int);
			SYSTEM.PUT(dadr, CHR(ASH(int MOD 20H, 3)));
			SYSTEM.PUT(dadr+1, CHR(ASH(ASH(int, -5) MOD 40H, 2)));
			SYSTEM.PUT(dadr+2, CHR(ASH(ASH(int, -11) MOD 20H, 3)));
			INC(sadr, 2); INC(dadr, 3); DEC(len)
		END
	END MoveBGR565BGR24;
	
	PROCEDURE MoveBGR565BGRA32 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR int: INTEGER;
	BEGIN	(* >>byte order! *)
		WHILE len > 0 DO
			SYSTEM.GET(sadr, int);
			SYSTEM.PUT(dadr, CHR(ASH(int MOD 20H, 3))); INC(dadr);
			SYSTEM.PUT(dadr+1, CHR(ASH(ASH(int, -5) MOD 40H, 2))); INC(dadr);
			SYSTEM.PUT(dadr+2, CHR(ASH(ASH(int, -11) MOD 20H, 3))); INC(dadr);
			SYSTEM.PUT(dadr+3, 0FFX);
			INC(sadr, 2); INC(dadr, 4); DEC(len)
		END
	END MoveBGR565BGRA32;
	
	PROCEDURE MoveBGR565Any (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR int: INTEGER; pix: Pixel;
	BEGIN	(* >>byte order! *)
		WHILE len > 0 DO
			SYSTEM.GET(sadr, int);
			pix[B] := CHR(ASH(int MOD 20H, 3));
			pix[G] := CHR(ASH(ASH(int, -5) MOD 40H, 2));
			pix[R] := CHR(ASH(ASH(int, -11) MOD 20H, 3));
			pix[A] := 0FFX;
			bl.dst.pack(bl.dst, dadr, dbit, pix);
			INC(sadr, 2); dbit := dbit + bl.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len)
		END
	END MoveBGR565Any;
	
	PROCEDURE MoveConst24 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(SYSTEM.ADR(bl.pix[0]), dadr, 3); INC(dadr, 3); DEC(len)
		END
	END MoveConst24;
	
	PROCEDURE MoveBGR24I8 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR b, g, r: CHAR;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.GET(sadr, b);
			SYSTEM.GET(sadr+1, g);
			SYSTEM.GET(sadr+2, r);
			SYSTEM.PUT(dadr, CHR(BestIndex(bl.dst.pal, ORD(r), ORD(g), ORD(b))));
			INC(sadr, 3); INC(dadr); DEC(len)
		END
	END MoveBGR24I8;
	
	PROCEDURE MoveBGR24BGR555 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR b: CHAR; int: INTEGER;
	BEGIN	(* >>byte order! *)
		WHILE len > 0 DO
			SYSTEM.GET(sadr, b); int := SHORT(ASH(ORD(b), -3));
			SYSTEM.GET(sadr+1, b); INC(int, SHORT(ASH(ASH(ORD(b), -3), 5)));
			SYSTEM.GET(sadr+2, b); INC(int, SHORT(ASH(ASH(ORD(b), -3), 10)));
			SYSTEM.PUT(dadr, int);
			INC(sadr, 3); INC(dadr, 2); DEC(len)
		END
	END MoveBGR24BGR555;
	
	PROCEDURE MoveBGR24BGR565 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR b: CHAR; int: INTEGER;
	BEGIN	(* >>byte order! *)
		WHILE len > 0 DO
			SYSTEM.GET(sadr, b); int := SHORT(ASH(ORD(b), -3));
			SYSTEM.GET(sadr+1, b); INC(int, SHORT(ASH(ASH(ORD(b), -2), 5)));
			SYSTEM.GET(sadr+2, b); INC(int, SHORT(ASH(ASH(ORD(b), -3), 11)));
			SYSTEM.PUT(dadr, int);
			INC(sadr, 3); INC(dadr, 2); DEC(len)
		END
	END MoveBGR24BGR565;
	
	PROCEDURE Move24 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, dadr, 3);
			INC(sadr, 3); INC(dadr, 3); DEC(len)
		END
	END Move24;
	
	PROCEDURE MoveBGR24BGRA32 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, dadr, 3); SYSTEM.PUT(dadr+3, 0FFX);
			INC(sadr, 3); INC(dadr, 4); DEC(len)
		END
	END MoveBGR24BGRA32;
	
	PROCEDURE MoveBGR24Any (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		pix[A] := 0FFX;
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, SYSTEM.ADR(pix[0]), 3);
			bl.dst.pack(bl.dst, dadr, dbit, pix);
			INC(sadr, 3); dbit := dbit + bl.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len)
		END
	END MoveBGR24Any;
	
	PROCEDURE Move32 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, dadr, 4);
			INC(sadr, 4); INC(dadr, 4); DEC(len)
		END
	END Move32;
	
	PROCEDURE MoveBGRA32A1 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR out, in: CHAR;
	BEGIN
		INC(sadr, 3);
		IF (dbit > 0) OR (len < 8) THEN
			SYSTEM.GET(dadr, out)
		END;
		WHILE len > 0 DO
			SYSTEM.GET(sadr, in);
			IF in >= 80X THEN out := Set[ORD(out), 7-dbit]
			ELSE out := Clear[ORD(out), 7-dbit]
			END;
			INC(sadr, 4); INC(dbit); DEC(len);
			IF dbit = 8 THEN
				SYSTEM.PUT(dadr, out);
				INC(dadr); dbit := 0;
				IF len < 8 THEN
					SYSTEM.GET(dadr, out)
				END
			END
		END;
		IF dbit > 0 THEN
			SYSTEM.PUT(dadr, out)
		END
	END MoveBGRA32A1;
	
	PROCEDURE MoveBGRA32A8 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR byte: CHAR;
	BEGIN
		INC(sadr, 3);
		WHILE len > 0 DO
			SYSTEM.GET(sadr, byte);
			SYSTEM.PUT(dadr, byte);
			INC(sadr, 4); INC(dadr); DEC(len)
		END
	END MoveBGRA32A8;
	
	PROCEDURE MoveBGRA32I8 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, SYSTEM.ADR(pix[0]), 4);
			SYSTEM.PUT(dadr, CHR(BestIndex(bl.dst.pal, ORD(pix[R]), ORD(pix[G]), ORD(pix[B]))));
			INC(sadr, 4); INC(dadr); DEC(len)
		END
	END MoveBGRA32I8;
	
	PROCEDURE MoveBGRA32BGR24 (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, dadr, 3);
			INC(sadr, 4); INC(dadr, 3); DEC(len)
		END
	END MoveBGRA32BGR24;
	
	PROCEDURE MoveBGRA32Any (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			SYSTEM.MOVE(sadr, SYSTEM.ADR(pix[0]), 4);
			bl.dst.pack(bl.dst, dadr, dbit, pix);
			INC(sadr, 4); dbit := dbit + bl.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8; DEC(len)
		END
	END MoveBGRA32Any;
	
	PROCEDURE MoveAnyAny (VAR bl: BlendOp0; sadr, sbit, dadr, dbit, len: LONGINT);
		VAR pix: Pixel;
	BEGIN
		WHILE len > 0 DO
			bl.src.unpack(bl.src, sadr, sbit, pix);
			bl.dst.pack(bl.dst, dadr, dbit, pix);
			sbit := sbit + bl.src.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8;
			dbit := dbit + bl.dst.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
			DEC(len)
		END
	END MoveAnyAny;
	
	(** find (optimized) pixel transfer procedure for blend operator **)
	PROCEDURE GetMoveProc* (VAR src, dst: Format; VAR bl: BlendOp);
		VAR pix: Pixel; i: LONGINT;
	BEGIN
		IF bl.blend = SrcAlphaBlend THEN
			CASE src.code OF
			| a1:
				CASE dst.code OF
				| a1: bl.move := BlendA1A1
				| a8: bl.pix[0] := 0FFX; bl.move := BlendA1Const8
				| i8: bl.pix[0] := CHR(BestIndex(dst.pal, src.col.r, src.col.g, src.col.b)); bl.move := BlendA1Const8
				| bgr555:
					ColorToPixel(src.col, pix);
					PackBGR555(dst, SYSTEM.ADR(bl.pix[0]), 0, pix);
					bl.move := BlendA1Const16
				| bgr565:
					ColorToPixel(src.col, pix);
					PackBGR565(dst, SYSTEM.ADR(bl.pix[0]), 0, pix);
					bl.move := BlendA1Const16
				| bgr24: ColorToPixel(src.col, bl.pix); bl.move := BlendA1Const24
				| bgra32: ColorToPixel(src.col, bl.pix); bl.move := BlendA1Const32
				ELSE ColorToPixel(src.col, bl.pix); bl.dst := dst; bl.move := BlendA1Any
				END
			
			| a8:
				CASE dst.code OF
				| a1: bl.move := BlendA8A1
				| a8: bl.move := BlendA8A8
				ELSE ColorToPixel(src.col, bl.pix); bl.dst := dst; bl.move := BlendA8Any
				END
			
			| i8:
				CASE dst.code OF
				| a1: bl.move := MoveSetBit
				| a8: bl.pix[0] := 0FFX; bl.move := MoveConst8
				| i8:
					IF src.pal = dst.pal THEN
						bl.move := Move8
					ELSE
						FOR i := 0 TO 7 DO bl.used[i] := {} END;
						bl.src := src; bl.dst := dst; bl.move := MoveI8I8
					END
				| bgr555: bl.src := src; bl.move := MoveI8BGR555
				| bgr565: bl.src := src; bl.move := MoveI8BGR565
				| bgr24: bl.src := src; bl.move := MoveI8BGR24
				| bgra32: bl.src := src; bl.move := MoveI8BGRA32
				ELSE bl.src := src; bl.dst := dst; bl.move := MoveI8Any
				END
			
			| bgr555:
				CASE dst.code OF
				| a1: bl.move := MoveSetBit
				| a8: bl.pix[0] := 0FFX; bl.move := MoveConst8
				| i8: bl.dst := dst; bl.move := MoveBGR555I8
				| bgr555: bl.move := Move16
				| bgr24: bl.move := MoveBGR555BGR24
				| bgra32: bl.move := MoveBGR555BGRA32
				ELSE bl.dst := dst; bl.move := MoveBGR555Any
				END
			
			| bgr565:
				CASE dst.code OF
				| a1: bl.move := MoveSetBit
				| a8: bl.pix[0] := 0FFX; bl.move := MoveConst8
				| i8: bl.dst := dst; bl.move := MoveBGR565I8
				| bgr565: bl.move := Move16
				| bgr24: bl.move := MoveBGR565BGR24
				| bgra32: bl.move := MoveBGR565BGRA32
				ELSE bl.dst := dst; bl.move := MoveBGR565Any
				END
			
			| bgr24:
				CASE dst.code OF
				| a1: bl.move := MoveSetBit
				| a8: bl.pix[0] := 0FFX; bl.move := MoveConst8
				| i8: bl.dst := dst; bl.move := MoveBGR24I8
				| bgr555: bl.move := MoveBGR24BGR555
				| bgr565: bl.move := MoveBGR24BGR565
				| bgr24: bl.move := Move24
				| bgra32: bl.move := MoveBGR24BGRA32
				ELSE bl.dst := dst; bl.move := MoveBGR24Any
				END
			
			| bgra32:
				CASE dst.code OF
				| a1: bl.move := BlendBGRA32A1
				| a8: bl.move := BlendBGRA32A8
				ELSE bl.dst := dst; bl.move := BlendBGRA32Any
				END
			
			ELSE
				bl.src := src; bl.dst := dst; bl.move := BlendAnyAny
			END
			
		ELSIF bl.blend = SrcCopyBlend THEN
			CASE src.code OF
			| a1:
				CASE dst.code OF
				| a1: bl.move := Move1
				| a8: bl.move := MoveA1A8
				| i8: bl.pix[0] := CHR(BestIndex(dst.pal, src.col.r, src.col.b, src.col.b)); bl.move := MoveConst8
				| bgr555:
					ColorToPixel(src.col, pix);
					PackBGR555(dst, SYSTEM.ADR(bl.pix[0]), 0, pix);
					bl.move := MoveConst16
				| bgr565:
					ColorToPixel(src.col, pix);
					PackBGR565(dst, SYSTEM.ADR(bl.pix[0]), 0, pix);
					bl.move := MoveConst16
				| bgr24: ColorToPixel(src.col, bl.pix); bl.move := MoveConst24
				| bgra32: ColorToPixel(src.col, bl.pix); bl.move := MoveA1BGRA32
				ELSE ColorToPixel(src.col, bl.pix); bl.dst := dst; bl.move := MoveA1Any
				END
			
			| a8:
				CASE dst.code OF
				| a1: bl.move := MoveA8A1
				| a8: bl.move := Move8
				| i8: bl.pix[0] := CHR(BestIndex(dst.pal, src.col.r, src.col.g, src.col.b)); bl.move := MoveConst8
				| bgr555: 
					ColorToPixel(src.col, pix);
					PackBGR555(dst, SYSTEM.ADR(bl.pix[0]), 0, pix);
					bl.move := MoveConst16
				| bgr565:
					ColorToPixel(src.col, pix);
					PackBGR565(dst, SYSTEM.ADR(bl.pix[0]), 0, pix);
					bl.move := MoveConst16
				| bgr24: ColorToPixel(src.col, bl.pix); bl.move := MoveConst24
				| bgra32: ColorToPixel(src.col, bl.pix); bl.move := MoveA8BGRA32
				ELSE ColorToPixel(src.col, bl.pix); bl.dst := dst; bl.move := MoveA8Any
				END
			
			| i8:
				CASE dst.code OF
				| a1: bl.move := MoveSetBit
				| a8: bl.pix[0] := 0FFX; bl.move := MoveConst8
				| i8:
					IF src.pal = dst.pal THEN
						bl.move := Move8
					ELSE
						FOR i := 0 TO 7 DO bl.used[i] := {} END;
						bl.src := src; bl.dst := dst; bl.move := MoveI8I8
					END
				| bgr555: bl.src := src; bl.move := MoveI8BGR555
				| bgr565: bl.src := src; bl.move := MoveI8BGR565
				| bgr24: bl.src := src; bl.move := MoveI8BGR24
				| bgra32: bl.src := src; bl.move := MoveI8BGRA32
				ELSE bl.src := src; bl.dst := dst; bl.move := MoveI8Any
				END
			
			| bgr555:
				CASE dst.code OF
				| a1: bl.move := MoveSetBit
				| a8: bl.pix[0] := 0FFX; bl.move := MoveConst8
				| i8: bl.dst := dst; bl.move := MoveBGR555I8
				| bgr555: bl.move := Move16
				| bgr24: bl.move := MoveBGR555BGR24
				| bgra32: bl.move := MoveBGR555BGRA32
				ELSE bl.dst := dst; bl.move := MoveBGR555Any
				END
			
			| bgr565:
				CASE dst.code OF
				| a1: bl.move := MoveSetBit
				| a8: bl.pix[0] := 0FFX; bl.move := MoveConst8
				| i8: bl.dst := dst; bl.move := MoveBGR565I8
				| bgr565: bl.move := Move16
				| bgr24: bl.move := MoveBGR565BGR24
				| bgra32: bl.move := MoveBGR565BGRA32
				ELSE bl.dst := dst; bl.move := MoveBGR565Any
				END
			
			| bgr24:
				CASE dst.code OF
				| a1: bl.move := MoveSetBit
				| a8: bl.pix[0] := 0FFX; bl.move := MoveConst8
				| i8: bl.dst := dst; bl.move := MoveBGR24I8
				| bgr555: bl.move := MoveBGR24BGR555
				| bgr565: bl.move := MoveBGR24BGR565
				| bgr24: bl.move := Move24
				| bgra32: bl.move := MoveBGR24BGRA32
				ELSE bl.dst := dst; bl.move := MoveBGR24Any
				END
			
			| bgra32:
				CASE dst.code OF
				| a1: bl.move := MoveBGRA32A1
				| a8: bl.move := MoveBGRA32A8
				| i8: bl.dst := dst; bl.move := MoveBGRA32I8
				| bgr24: bl.move := MoveBGRA32BGR24
				| bgra32: bl.move := Move32
				ELSE bl.dst := dst; bl.move := MoveBGRA32Any
				END
			
			ELSE bl.src := src; bl.dst := dst; bl.move := MoveAnyAny
			END
		
		ELSE bl.src := src; bl.dst := dst; bl.move := BlendAnyAny
		END;
		
		ASSERT(bl.move # NIL, 120)
	END GetMoveProc;
	
	
	(*--- Map Operations ---*)
	
	(** get pixel **)
	PROCEDURE Get* (map: Map; x, y: INTEGER; VAR pix: Pixel; VAR bl: BlendOp);
		VAR bit, adr: LONGINT;
	BEGIN
		ASSERT((0 <= x) & (x < map.width) & (0 <= y) & (y < map.height), 100);
		bit := x * map.fmt.bpp; adr := map.adr + y * map.bpr + bit DIV 8; bit := bit MOD 8;
		GetMoveProc(map.fmt, BGRA32, bl);
		bl.move(bl, adr, bit, SYSTEM.ADR(pix), 0, 1)
	END Get;
	
	(** put pixel **)
	PROCEDURE Put* (map: Map; x, y: INTEGER; pix: Pixel; VAR bl: BlendOp);
		VAR bit, adr: LONGINT;
	BEGIN
		ASSERT((0 <= x) & (x < map.width) & (0 <= y) & (y < map.height), 100);
		bit := x * map.fmt.bpp; adr := map.adr + y * map.bpr + bit DIV 8; bit := bit MOD 8;
		GetMoveProc(PixelFormat, map.fmt, bl);
		bl.move(bl, SYSTEM.ADR(pix[0]), 0, adr, bit, 1)
	END Put;
	
	(** fill rectangular area **)
	PROCEDURE Fill* (map: Map; llx, lly, urx, ury: INTEGER; pix: Pixel; VAR bl: BlendOp);
		VAR bit, adr, b, a: LONGINT; blend: BlendProc; x: INTEGER;
	BEGIN
		ASSERT((0 <= llx) & (llx < urx) & (urx <= map.width) & (0 <= lly) & (lly < ury) & (ury <= map.height), 100);
		bit := llx * map.fmt.bpp; adr := map.adr + lly * map.bpr + bit DIV 8; bit := bit MOD 8;
		IF (bl.blend = SrcCopyBlend) OR (bl.blend = SrcAlphaBlend) & (pix[A] = 0FFX) THEN	(* dst is replaced *)
			(* get one pixel in lower left corner of rect *)
			blend := bl.blend; bl.blend := SrcCopyProc;
			GetMoveProc(PixelFormat, map.fmt, bl);
			bl.move(bl, SYSTEM.ADR(pix[0]), 0, adr, bit, 1);
			
			(* copy pixel to rest of bottom row *)
			GetMoveProc(map.fmt, map.fmt, bl);
			IF (bit = 0) & (map.fmt.bpp MOD 8 = 0) THEN	(* use simple address calculation *)
				b := map.fmt.bpp DIV 8; a := adr + b; x := llx+1;
				WHILE x < urx DO
					bl.move(bl, adr, 0, a, 0, 1);
					INC(a, b); INC(x)
				END
			ELSE
				b := bit + map.fmt.bpp; a := adr + b DIV 8; b := b MOD 8; x := llx+1;
				WHILE x < urx DO
					bl.move(bl, adr, bit, a, b, 1);
					b := b + map.fmt.bpp; a := a + b DIV 8; b := b MOD 8; INC(x)
				END
			END;
			
			(* now copy bottom row to others *)
			INC(lly); a := adr + map.bpr;
			WHILE lly < ury DO
				bl.move(bl, adr, bit, a, bit, urx - llx);
				INC(lly); INC(a, map.bpr)
			END;
			bl.blend := blend
		
		ELSE	(* fill pixel by pixel *)
			GetMoveProc(PixelFormat, map.fmt, bl);
			WHILE lly < ury DO
				x := llx; a := adr; b := bit;
				WHILE x < urx DO
					bl.move(bl, SYSTEM.ADR(pix[0]), 0, a, b, 1);
					b := b + map.fmt.bpp; a := a + b DIV 8; b := b MOD 8; INC(x)
				END;
				INC(lly); INC(adr, map.bpr)
			END
		END
	END Fill;
	
	(** get several pixels and store them in array in requested format **)
	PROCEDURE GetPixels* (map: Map; x, y, w: INTEGER; VAR fmt: Format; VAR buf: ARRAY OF CHAR; VAR bl: BlendOp);
		VAR sbit, sadr: LONGINT;
	BEGIN
		ASSERT((0 <= x) & (x + w <= map.width) & (0 <= y) & (y <= map.height), 100);
		ASSERT(w * fmt.bpp DIV 8 <= LEN(buf), 101);
		GetMoveProc(map.fmt, fmt, bl);
		sbit := x * map.fmt.bpp; sadr := map.adr + y * map.bpr + sbit DIV 8; sbit := sbit MOD 8;
		bl.move(bl, sadr, sbit, SYSTEM.ADR(buf[0]), 0, w)
	END GetPixels;
	
	(** put several pixels from array in given format into map **)
	PROCEDURE PutPixels* (map: Map; x, y, w: INTEGER; VAR fmt: Format; VAR buf: ARRAY OF CHAR; VAR bl: BlendOp);
		VAR dbit, dadr: LONGINT;
	BEGIN
		ASSERT((0 <= x) & (x + w <= map.width) & (0 <= y) & (y <= map.height), 100);
		ASSERT(w * fmt.bpp DIV 8 <= LEN(buf), 101);
		dbit := x * map.fmt.bpp; dadr := map.adr + y * map.bpr + dbit DIV 8; dbit := dbit MOD 8;
		GetMoveProc(fmt, map.fmt, bl);
		bl.move(bl, SYSTEM.ADR(buf[0]), 0, dadr, dbit, w)
	END PutPixels;
	
	(** copy rectangular area to the same or another map using given blend operator **)
	PROCEDURE Copy* (src, dst: Map; llx, lly, urx, ury, dx, dy: INTEGER; VAR bl: BlendOp);
		VAR w, h: INTEGER; sbit, sadr, dbit, dadr, slen, sa, sb, da, db, len, l: LONGINT;
	BEGIN
		ASSERT((0 <= llx) & (llx <= urx) & (urx <= src.width) & (0 <= lly) & (lly <= ury) & (ury <= src.height), 100);
		ASSERT((0 <= dx) & (dx + urx - llx <= dst.width) & (0 <= dy) & (dy + ury - lly <= dst.height), 101);
		GetMoveProc(src.fmt, dst.fmt, bl);
		w := urx - llx; h := ury - lly;
		IF (src # dst) OR (lly > dy) OR (lly = dy) & ((llx > dx) OR (urx <= dx)) THEN	(* copy lines bottom-up *)
			sbit := llx * src.fmt.bpp; sadr := src.adr + lly * src.bpr + sbit DIV 8; sbit := sbit MOD 8;
			dbit := dx * dst.fmt.bpp; dadr := dst.adr + dy * dst.bpr + dbit DIV 8; dbit := dbit MOD 8;
			WHILE h > 0 DO
				bl.move(bl, sadr, sbit, dadr, dbit, w);
				INC(sadr, src.bpr); INC(dadr, dst.bpr); DEC(h)
			END
		ELSIF lly < dy THEN	(* copy lines top-down *)
			sbit := llx * src.fmt.bpp; sadr := src.adr + ury * src.bpr + sbit DIV 8; sbit := sbit MOD 8;
			dbit := dx * dst.fmt.bpp; dadr := dst.adr + (dy + h) * dst.bpr + dbit DIV 8; dbit := dbit MOD 8;
			WHILE h > 0 DO
				bl.move(bl, sadr, sbit, dadr, dbit, w);
				DEC(sadr, src.bpr); DEC(dadr, dst.bpr); DEC(h)
			END
		ELSIF llx # dx THEN	(* uh oh! overlapping spans *)
			slen := urx - dx;	(* maximal span length guaranteeing non-overlapping spans *)
			sbit := urx * src.fmt.bpp; sadr := src.adr + lly * src.bpr + sbit DIV 8; sbit := sbit MOD 8;
			dbit := (dx + w) * dst.fmt.bpp; dadr := dst.adr + dy * dst.bpr + dbit DIV 8; dbit := dbit MOD 8;
			WHILE h > 0 DO
				sa := sadr; sb := sbit; da := dadr; db := dbit; len := w;
				WHILE len > 0 DO
					l := slen;
					IF l > len THEN l := len END;
					DEC(sb, l * src.fmt.bpp); INC(sa, sb DIV 8); sb := sb MOD 8;
					DEC(db, l * dst.fmt.bpp); INC(da, db DIV 8); db := db MOD 8;
					bl.move(bl, sa, sb, da, db, l);
					DEC(len, l)
				END;
				INC(sadr, src.bpr); INC(dadr, dst.bpr); DEC(h)
			END
		END
	END Copy;
	
	(** replicate image map within rectangular area using given blend operator **)
	PROCEDURE FillPattern* (map, pat: Map; llx, lly, urx, ury, px, py: INTEGER; VAR bl: BlendOp);
		VAR pw, ph, olx, oby, ilx, olw, irw, dy, sy, dx, sx, ty: INTEGER;
	BEGIN
		ASSERT((0 <= llx) & (llx <= urx) & (urx <= map.width) & (0 <= lly) & (lly <= ury) & (ury <= map.height), 100);
		pw := pat.width; ph := pat.height;
		olx := px + (llx - px) DIV pw * pw;
		oby := py + (lly - py) DIV ph * ph;
		ilx := olx + pw; olw := llx - olx;
		irw := (urx - px) MOD pw;
		IF urx - irw < ilx THEN irw := olw + urx - llx END;
		dy := lly; sy := lly - oby;
		IF (oby < lly) & (oby + ph <= ury) THEN
			dx := llx; sx := olw;
			IF (olx < llx) & (ilx <= urx) THEN
				Copy(pat, map, sx, sy, pw, ph, llx, lly, bl);
				dx := ilx; sx := 0
			END;
			WHILE dx + pw <= urx DO
				Copy(pat, map, 0, sy, pw, ph, dx, lly, bl);
				INC(dx, pw)
			END;
			IF dx < urx THEN
				Copy(pat, map, sx, sy, irw, ph, dx, lly, bl)
			END;
			dy := oby + ph; sy := 0
		END;
		WHILE dy + ph <= ury DO
			dx := llx; sx := olw;
			IF (olx < llx) & (ilx <= urx) THEN
				Copy(pat, map, sx, 0, pw, ph, llx, dy, bl);
				dx := ilx; sx := 0
			END;
			WHILE dx + pw <= urx DO
				Copy(pat, map, 0, 0, pw, ph, dx, dy, bl);
				INC(dx, pw)
			END;
			IF dx < urx THEN
				Copy(pat, map, sx, 0, irw, ph, dx, dy, bl)
			END;
			INC(dy, ph)
		END;
		IF dy < ury THEN
			ty := sy + ury - dy;
			dx := llx; sx := olw;
			IF (olx < llx) & (ilx <= urx) THEN
				Copy(pat, map, sx, sy, pw, ty, llx, dy, bl);
				dx := ilx; sx := 0
			END;
			WHILE dx + pw <= urx DO
				Copy(pat, map, 0, sy, pw, ty, dx, dy, bl);
				INC(dx, pw)
			END;
			IF dx < urx THEN
				Copy(pat, map, sx, sy, irw, ty, dx, dy, bl)
			END
		END
	END FillPattern;
	
	(** copy image map to another using error diffusion dithering (Floyd-Steinberg) **)
	PROCEDURE Dither* (src, dst: Map);
		VAR
			scopy, dcopy: BlendOp; e351: POINTER TO ARRAY OF Color; y, x, ex, e, e3, e5: INTEGER;
			sadr, dadr, sa, sb, da, db: LONGINT; e7, e51, e1: Color; spix, dpix: Pixel;
	BEGIN
		ASSERT((src.width <= dst.width) & (src.height <= dst.height), 100);
		scopy.blend := SrcCopyProc;
		GetMoveProc(src.fmt, PixelFormat, scopy);
		dcopy.blend := SrcCopyProc;
		GetMoveProc(PixelFormat, dst.fmt, dcopy);
		GetMoveProc(dst.fmt, PixelFormat, SrcCopy);
		NEW(e351, src.width+2);	(* accumulated error for next row *)
		y := 0; sadr := src.adr; dadr := dst.adr;
		WHILE y < src.height DO 	(* scan from left to right *)
			e7.r := 0; e7.g := 0; e7.b := 0;
			e51.r := 0; e51.g := 0; e51.b := 0;
			e1.r := 0; e1.g := 0; e1.b := 0;
			x := 0; sa := sadr; sb := 0; da := dadr; db := 0;
			WHILE x < src.width DO
				ex := x+1;
				scopy.move(scopy, sa, sb, SYSTEM.ADR(spix[0]), 0, 1);
				spix[R] := Clamp[200H + ORD(spix[R]) + e351[ex].r + e7.r];
				spix[G] := Clamp[200H + ORD(spix[G]) + e351[ex].g + e7.g];
				spix[B] := Clamp[200H + ORD(spix[B]) + e351[ex].b + e7.b];
				dcopy.move(dcopy, SYSTEM.ADR(spix[0]), 0, da, db, 1);
				SrcCopy.move(SrcCopy, da, db, SYSTEM.ADR(dpix[0]), 0, 1);
				e := ORD(spix[R]) - ORD(dpix[R]); e3 := 3*e DIV 16; e5 := 5*e DIV 16;
				e7.r := 7*e DIV 16; e351[x].r := e3 + e51.r; e51.r := e5 + e1.r; e1.r := e - e3 - e5 - e7.r;
				e := ORD(spix[G]) - ORD(dpix[G]); e3 := 3*e DIV 16; e5 := 5*e DIV 16;
				e7.g := 7*e DIV 16; e351[x].g := e3 + e51.g; e51.g := e5 + e1.g; e1.g := e - e3 - e5 - e7.g;
				e := ORD(spix[B]) - ORD(dpix[B]); e3 := 3*e DIV 16; e5 := 5*e DIV 16;
				e7.b := 7*e DIV 16; e351[x].b := e3 + e51.b; e51.b := e5 + e1.b; e1.b := e - e3 - e5 - e7.b;
				sb := sb + src.fmt.bpp; INC(sa, sb DIV 8); sb := sb MOD 8;
				db := db + dst.fmt.bpp; INC(da, db DIV 8); db := db MOD 8;
				x := ex
			END;
			INC(y); INC(sadr, src.bpr); INC(dadr, dst.bpr);
			IF y < src.height THEN	(* scan from right to left *)
				e351[x] := e51;
				e7.r := 0; e7.g := 0; e7.b := 0;
				e51.r := 0; e51.g := 0; e51.b := 0;
				e1.r := 0; e1.g := 0; e1.b := 0;
				INC(sa, src.bpr); INC(da, dst.bpr);
				WHILE x > 0 DO
					ex := x; DEC(x);
					sb := sb - src.fmt.bpp; INC(sa, sb DIV 8); sb := sb MOD 8;
					db := db - dst.fmt.bpp; INC(da, db DIV 8); db := db MOD 8;
					scopy.move(scopy, sa, sb, SYSTEM.ADR(spix[0]), 0, 1);
					spix[R] := Clamp[200H + ORD(spix[R]) + e351[ex].r + e7.r];
					spix[G] := Clamp[200H + ORD(spix[G]) + e351[ex].g + e7.g];
					spix[B] := Clamp[200H + ORD(spix[B]) + e351[ex].b + e7.b];
					dcopy.move(dcopy, SYSTEM.ADR(spix[0]), 0, da, db, 1);
					SrcCopy.move(SrcCopy, da, db, SYSTEM.ADR(dpix[0]), 0, 1);
					INC(ex);
					e := ORD(spix[R]) - ORD(dpix[R]); e3 := 3*e DIV 16; e5 := 5*e DIV 16;
					e7.r := 7*e DIV 16; e351[x].r := e3 + e51.r; e51.r := e5 + e1.r; e1.r := e - e3 - e5 - e7.r;
					e := ORD(spix[G]) - ORD(dpix[G]); e3 := 3*e DIV 16; e5 := 5*e DIV 16;
					e7.g := 7*e DIV 16; e351[x].g := e3 + e51.g; e51.g := e5 + e1.g; e1.g := e - e3 - e5 - e7.g;
					e := ORD(spix[B]) - ORD(dpix[B]); e3 := 3*e DIV 16; e5 := 5*e DIV 16;
					e7.b := 7*e DIV 16; e351[x].b := e3 + e51.b; e51.b := e5 + e1.b; e1.b := e - e3 - e5 - e7.b
				END;
				e351[1] := e51;
				INC(y); INC(sadr, src.bpr); INC(dadr, dst.bpr)
			END
		END
	END Dither;
	
	
	(**--- Image Transformations ---**)
	
	(** predefined filter procedures using box filter (i.e. no filtering): fast and ugly **)
	
	PROCEDURE HShift* (VAR filter: Filter0; src, dst: Map; sadr, sbit, dadr, dbit, len: LONGINT; tx: REAL);
	BEGIN
		IF tx >= 0.5 THEN
			dbit := dbit + dst.fmt.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
			DEC(len)
		END;
		GetMoveProc(src.fmt, dst.fmt, filter);
		filter.move(filter, sadr, sbit, dadr, dbit, len)
	END HShift;
	
	PROCEDURE VShift* (VAR filter: Filter0; src, dst: Map; sadr, sbit, dadr, dbit, len: LONGINT; ty: REAL);
	BEGIN
		IF ty >= 0.5 THEN
			INC(dadr, dst.bpr);
			DEC(len)
		END;
		GetMoveProc(src.fmt, dst.fmt, filter);
		WHILE len > 0 DO
			filter.move(filter, sadr, sbit, dadr, dbit, 1);
			INC(sadr, src.bpr); INC(dadr, dst.bpr);
			DEC(len)
		END
	END VShift;
	
	PROCEDURE HScale* (VAR filter: Filter0; src, dst: Map; sadr, sbit, dadr, dbit, dlen: LONGINT; x, dx: REAL);
		VAR i0, i1: INTEGER;
	BEGIN
		GetMoveProc(src.fmt, dst.fmt, filter);
		i0 := 0;
		WHILE dlen > 0 DO
			i1 := SHORT(ENTIER(x));
			IF i0 < i1 THEN
				IF i1 >= src.width THEN i1 := src.width-1 END;
				sbit := sbit + (i1 - i0) * src.fmt.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8;
				i0 := i1
			END;
			filter.move(filter, sadr, sbit, dadr, dbit, 1);
			dbit := dbit + dst.fmt.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
			x := x + dx; DEC(dlen)
		END
	END HScale;
	
	PROCEDURE VScale* (VAR filter: Filter0; src, dst: Map; sadr, sbit, dadr, dbit, dlen: LONGINT; y, dy: REAL);
		VAR j0, j1: INTEGER;
	BEGIN
		GetMoveProc(src.fmt, dst.fmt, filter);
		j0 := 0;
		WHILE dlen > 0 DO
			j1 := SHORT(ENTIER(y));
			IF j0 < j1 THEN
				IF j1 >= src.height THEN j1 := src.height-1 END;
				INC(sadr, (j1 - j0) * src.bpr);
				j0 := j1
			END;
			filter.move(filter, sadr, sbit, dadr, dbit, 1);
			INC(dadr, dst.bpr);
			y := y + dy; DEC(dlen)
		END
	END VScale;
	
	(** predefined filter procedures for linearly filtered transformations: slow and less ugly **)
	
	PROCEDURE LinearHShift* (VAR filter: Filter0; src, dst: Map; sadr, sbit, dadr, dbit, len: LONGINT; tx: REAL);
		VAR w0, w1, sinc, dinc, da, i, r, g, b, a: LONGINT; scopy: BlendOp; spix, dpix: Pixel;
	BEGIN
		w0 := ENTIER(1000H*tx + 0.5); w1 := 1000H-w0;
		IF (w0 < 10H) OR (w1 < 10H) THEN
			HShift(filter, src, dst, sadr, sbit, dadr, dbit, len, tx)
		ELSE
			sinc := src.fmt.bpp; dinc := dst.fmt.bpp; da := dadr;
			scopy.blend := SrcCopyProc;
			GetMoveProc(src.fmt, PixelFormat, scopy);
			GetMoveProc(PixelFormat, dst.fmt, filter);
			scopy.move(scopy, sadr, sbit, SYSTEM.ADR(spix[0]), 0, 1);
			FOR i := 0 TO 3 DO dpix[i] := CHR(w1 * ORD(spix[i]) DIV 1000H) END;
			filter.move(filter, SYSTEM.ADR(dpix[0]), 0, dadr, dbit, 1);
			INC(dbit, dinc); INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
			DEC(len);
			WHILE len > 0 DO
				r := w0 * ORD(spix[R]); g := w0 * ORD(spix[G]); b := w0 * ORD(spix[B]); a := w0 * ORD(spix[A]);
				INC(sbit, sinc); INC(sadr, sbit DIV 8); sbit := sbit MOD 8;
				scopy.move(scopy, sadr, sbit, SYSTEM.ADR(spix[0]), 0, 1);
				dpix[R] := CHR((r + w1 * ORD(spix[R])) DIV 1000H);
				dpix[G] := CHR((g + w1 * ORD(spix[G])) DIV 1000H);
				dpix[B] := CHR((b + w1 * ORD(spix[B])) DIV 1000H);
				dpix[A] := CHR((a + w1 * ORD(spix[A])) DIV 1000H);
				filter.move(filter, SYSTEM.ADR(dpix[0]), 0, dadr, dbit, 1);
				INC(dbit, dinc); INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
				DEC(len)
			END;
			IF (da - dst.adr) DIV dst.bpr = (dadr - dst.adr) DIV dst.bpr THEN
				FOR i := 0 TO 3 DO dpix[i] := CHR(w0 * ORD(spix[i]) DIV 1000H) END;
				filter.move(filter, SYSTEM.ADR(dpix), 0, dadr, dbit, 1)
			END
		END
	END LinearHShift;
	
	PROCEDURE LinearVShift* (VAR filter: Filter0; src, dst: Map; sadr, sbit, dadr, dbit, len: LONGINT; ty: REAL);
		VAR w0, w1, i, r, g, b, a: LONGINT; scopy: BlendOp; spix, dpix: Pixel;
	BEGIN
		w0 := ENTIER(1000H*ty + 0.5); w1 := 1000H-w0;
		IF (w0 < 10H) OR (w1 < 10H) THEN
			VShift(filter, src, dst, sadr, sbit, dadr, dbit, len, ty)
		ELSE
			scopy.blend := SrcCopyProc;
			GetMoveProc(src.fmt, PixelFormat, scopy);
			GetMoveProc(PixelFormat, dst.fmt, filter);
			scopy.move(scopy, sadr, sbit, SYSTEM.ADR(spix[0]), 0, 1);
			FOR i := 0 TO 3 DO dpix[i] := CHR(w1 * ORD(spix[i]) DIV 1000H) END;
			filter.move(filter, SYSTEM.ADR(dpix[0]), 0, dadr, dbit, 1);
			INC(dadr, dst.bpr);
			DEC(len);
			WHILE len > 0 DO
				r := w0 * ORD(spix[R]); g := w0 * ORD(spix[G]); b := w0 * ORD(spix[B]); a := w0 * ORD(spix[A]);
				INC(sadr, src.bpr);
				scopy.move(scopy, sadr, sbit, SYSTEM.ADR(spix[0]), 0, 1);
				dpix[R] := CHR((r + w1 * ORD(spix[R])) DIV 1000H);
				dpix[G] := CHR((g + w1 * ORD(spix[G])) DIV 1000H);
				dpix[B] := CHR((b + w1 * ORD(spix[B])) DIV 1000H);
				dpix[A] := CHR((a + w1 * ORD(spix[A])) DIV 1000H);
				filter.move(filter, SYSTEM.ADR(dpix[0]), 0, dadr, dbit, 1);
				INC(dadr, dst.bpr);
				DEC(len)
			END;
			IF (dst.adr < dadr) & (dadr < dst.adr + dst.height * dst.bpr) THEN
				FOR i := 0 TO 3 DO dpix[i] := CHR(w0 * ORD(spix[i]) DIV 1000H) END;
				filter.move(filter, SYSTEM.ADR(dpix[0]), 0, dadr, dbit, 1)
			END
		END
	END LinearVShift;
	
	PROCEDURE LinearHScale* (VAR filter: Filter0; src, dst: Map; sadr, sbit, dadr, dbit, dlen: LONGINT; x, dx: REAL);
		VAR scopy: BlendOp; i0, i1: INTEGER; spix: ARRAY 2 OF Pixel; dpix: Pixel; w1, w0, j: LONGINT;
	BEGIN
		scopy.blend := SrcCopyProc;
		GetMoveProc(src.fmt, PixelFormat, scopy);
		GetMoveProc(PixelFormat, dst.fmt, filter);
		x := x + 0.5;	(* displace sample position to midpoint between candidate pixels *)
		i0 := 0; scopy.move(scopy, sadr, sbit, SYSTEM.ADR(spix[0, 0]), 0, 1);
		spix[1] := spix[0];
		WHILE dlen > 0 DO
			i1 := SHORT(ENTIER(x));
			IF i1 > i0 THEN
				INC(i0);
				IF i0 >= src.width THEN
					spix[0] := spix[1]
				ELSIF i1 = i0 THEN
					spix[0] := spix[1];
					sbit := sbit + src.fmt.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8;
					scopy.move(scopy, sadr, sbit, SYSTEM.ADR(spix[1, 0]), 0, 1)
				ELSIF i1 < src.width THEN
					sbit := sbit + (i1 - i0) * src.fmt.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8;
					scopy.move(scopy, sadr, sbit, SYSTEM.ADR(spix[0, 0]), 0, 2);
					sbit := sbit + src.fmt.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8
				ELSE
					sbit := sbit + (src.width - i0) * src.fmt.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8;
					scopy.move(scopy, sadr, sbit, SYSTEM.ADR(spix[0, 0]), 0, 1);
					spix[1] := spix[0]
				END;
				i0 := i1
			END;
			w1 := ENTIER(1000H*(x - i1)); w0 := 1000H-w1;
			FOR j := 0 TO 3 DO
				dpix[j] := Clamp[200H + (ORD(spix[0, j]) * w0 + ORD(spix[1, j]) * w1) DIV 1000H]
			END;
			filter.move(filter, SYSTEM.ADR(dpix[0]), 0, dadr, dbit, 1);
			dbit := dbit + dst.fmt.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
			x := x + dx; DEC(dlen)
		END
	END LinearHScale;
	
	PROCEDURE LinearVScale* (VAR filter: Filter0; src, dst: Map; sadr, sbit, dadr, dbit, dlen: LONGINT; y, dy: REAL);
		VAR scopy: BlendOp; j0, j1: INTEGER; spix: ARRAY 2 OF Pixel; dpix: Pixel; w1, w0, j: LONGINT;
	BEGIN
		scopy.blend := SrcCopyProc;
		GetMoveProc(src.fmt, PixelFormat, scopy);
		GetMoveProc(PixelFormat, dst.fmt, filter);
		y := y + 0.5;	(* displace sample position to midpoint between candidate pixels *)
		j0 := 0; scopy.move(scopy, sadr, sbit, SYSTEM.ADR(spix[0, 0]), 0, 1);
		spix[1] := spix[0];
		WHILE dlen > 0 DO
			j1 := SHORT(ENTIER(y));
			IF j1 > j0 THEN
				INC(j0);
				IF j0 >= src.height THEN
					spix[0] := spix[1]
				ELSIF j1 = j0 THEN
					spix[0] := spix[1];
					INC(sadr, src.bpr);
					scopy.move(scopy, sadr, sbit, SYSTEM.ADR(spix[1, 0]), 0, 1)
				ELSIF j1 < src.height THEN
					INC(sadr, (j1 - j0) * src.bpr);
					scopy.move(scopy, sadr, sbit, SYSTEM.ADR(spix[0, 0]), 0, 2);
					INC(sadr, src.bpr)
				ELSE
					INC(sadr, src.bpr);
					scopy.move(scopy, sadr, sbit, SYSTEM.ADR(spix[0, 0]), 0, 1);
					spix[1] := spix[0]
				END;
				j0 := j1
			END;
			w1 := ENTIER(1000H*(y - j1)); w0 := 1000H-w1;
			FOR j := 0 TO 3 DO
				dpix[j] := Clamp[200H + (ORD(spix[0, j]) * w0 + ORD(spix[1, j]) * w1) DIV 1000H]
			END;
			filter.move(filter, SYSTEM.ADR(dpix), 0, dadr, dbit, 1);
			INC(dadr, dst.bpr);
			y := y + dy; DEC(dlen)
		END
	END LinearVScale;
	
	(** initialize filter with blend and transformation procedures **)
	PROCEDURE InitFilter* (VAR filter: Filter; blend: BlendProc; hshift, vshift: ShiftProc; hscale, vscale: ScaleProc);
	BEGIN
		filter.blend := blend;
		filter.hshift := hshift; filter.vshift := vshift;
		filter.hscale := hscale; filter.vscale := vscale
	END InitFilter;
	
	(* get temporary BGRA32 map for storing intermediate maps *)
	PROCEDURE GetTempMap (VAR map, cache: Map; w, h: INTEGER);
		VAR size: LONGINT;
	BEGIN
		size := LONG(w) * LONG(h);
		IF (size >= 10000H) OR (cache = NIL) THEN
			NEW(map)
		ELSE
			map := cache; cache := NIL
		END;
		Create(map, w, h, BGRA32)
	END GetTempMap;
	
	PROCEDURE FreeTempMap (VAR map, cache: Map);
	BEGIN
		IF LONG(map.width) * LONG(map.height) < 10000H THEN
			cache := map
		END
	END FreeTempMap;
	
	(* depending on matrix elements, transpose/mirror map to avoid bottleneck problems *)
	PROCEDURE Preprocess (VAR src: Map; VAR m: GfxMatrix.Matrix);
		VAR dst: Map; dadr, dinc, sadr, sinc, sa, da, sbit: LONGINT; h, w: INTEGER; mat: GfxMatrix.Matrix; t: REAL;
	BEGIN
		IF ABS(m[0, 0] * m[1, 1]) >= ABS(m[0, 1] * m[1, 0]) THEN	(* no need to swap rows and columns *)
			IF (m[0, 0] <= 0) OR (m[1, 1] <= 0) THEN
				GetTempMap(dst, PreCache, src.width, src.height);
				GetMoveProc(src.fmt, dst.fmt, SrcCopy);
				IF m[0, 0] >= 0 THEN dadr := dst.adr; dinc := 4
				ELSE dadr := dst.adr + 4*(dst.width-1); dinc := -4
				END;
				IF m[1, 1] >= 0 THEN sadr := src.adr; sinc := src.bpr
				ELSE sadr := src.adr + (src.height-1) * src.bpr; sinc := -src.bpr
				END;
				h := 0;
				WHILE h < src.height DO
					w := 0; sa := sadr; sbit := 0; da := dadr;
					WHILE w < src.width DO
						SrcCopy.move(SrcCopy, sa, sbit, da, 0, 1);
						sbit := sbit + src.fmt.bpp; INC(sa, sbit DIV 8); sbit := sbit MOD 8;
						INC(da, dinc); INC(w)
					END;
					INC(sadr, sinc); INC(dadr, dst.bpr); INC(h)
				END;
				IF m[0, 0] < 0 THEN
					GfxMatrix.Init(mat, -1, 0, 0, 1, w, 0);
					GfxMatrix.Concat(mat, m, m)
				END;
				IF m[1, 1] < 0 THEN
					GfxMatrix.Init(mat, 1, 0, 0, -1, 0, h);
					GfxMatrix.Concat(mat, m, m)
				END;
				src := dst;
				FreeTempMap(dst, PreCache)	(* reuse allocated map in next call *)
			END
		ELSE	(* need to transpose *)
			t := m[0, 0]; m[0, 0] := m[1, 0]; m[1, 0] := t;
			t := m[0, 1]; m[0, 1] := m[1, 1]; m[1, 1] := t;
			GetTempMap(dst, PreCache, src.height, src.width);
			GetMoveProc(src.fmt, dst.fmt, SrcCopy);
			IF m[0, 0] <= 0 THEN dadr := dst.adr; dinc := dst.bpr
			ELSE dadr := dst.adr + (dst.height-1) * dst.bpr; dinc := -dst.bpr
			END;
			IF m[1, 1] <= 0 THEN sadr := src.adr; sinc := src.bpr
			ELSE sadr := src.adr + (src.height-1) * src.bpr; sinc := -src.bpr
			END;
			h := 0;
			WHILE h < src.height DO
				w := 0; sa := sadr; sbit := 0; da := dadr;
				WHILE w < src.width DO
					SrcCopy.move(SrcCopy, sa, sbit, da, 0, 1);
					sbit := sbit + src.fmt.bpp; INC(sa, sbit DIV 8); sbit := sbit MOD 8;
					INC(da, dinc); INC(w)
				END;
				INC(sadr, sinc); INC(dadr, 4); INC(h)
			END;
			IF m[0, 0] < 0 THEN
				GfxMatrix.Init(mat, -1, 0, 0, 1, dst.width, 0);
				GfxMatrix.Concat(mat, m, m)
			END;
			IF m[1, 1] < 0 THEN
				GfxMatrix.Init(mat, 1, 0, 0, -1, 0, dst.height);
				GfxMatrix.Concat(mat, m, m)
			END;
			src := dst;
			FreeTempMap(dst, PreCache)
		END
	END Preprocess;
	
	(* shift source row by fractional amount *)
	PROCEDURE SkewRow (src, dst: Map; si, sj, w, di, dj: INTEGER; tx: REAL; VAR filt: Filter);
		VAR sbit, sadr, dbit, dadr: LONGINT;
	BEGIN
		ASSERT((0.0 <= tx) & (tx <= 1.0), 100);	(* rounding problem if using tx < 1.0 *)
		IF si < 0 THEN INC(w, si); DEC(di, si); si := 0 END;
		IF si + w > src.width THEN w := src.width - si END;
		IF w > 0 THEN
			sbit := si * src.fmt.bpp; sadr := src.adr + sj * src.bpr + sbit DIV 8; sbit := sbit MOD 8;
			dbit := di * dst.fmt.bpp; dadr := dst.adr + dj * dst.bpr + dbit DIV 8; dbit := dbit MOD 8;
			filt.hshift(filt, src, dst, sadr, sbit, dadr, dbit, w, tx)
		END
	END SkewRow;
	
	(* shear rectangle in source map horizontally; clip to destination boundary *)
	PROCEDURE SkewRows (src, dst: Map; si, sj, w, h, dj: INTEGER; x, dx: REAL; VAR filter: Filter);
		VAR j, di, n: INTEGER;
	BEGIN
		j := 0;
		IF dj < 0 THEN
			j := -dj;
			IF j >= h THEN RETURN END
		END;
		IF dj + h > dst.height THEN
			h := dst.height - dj;
			IF h <= 0 THEN RETURN END
		END;
		
		IF dx > 0 THEN
			IF x + h * dx >= dst.width THEN
				h := -SHORT(ENTIER((x - dst.width)/dx))
			END;
			x := x + j * dx;
			IF x + w < 0 THEN
				n := -SHORT(ENTIER((x + w)/dx));
				INC(j, n); x := x + n * dx
			END;
			IF x < 0 THEN
				n := j - SHORT(ENTIER(x/dx));
				IF n > h THEN n := h END;
				WHILE j < n DO
					di := SHORT(ENTIER(x));
					IF di + w > dst.width THEN w := dst.width END;
					SkewRow(src, dst, si - di, sj + j, di + w, 0, dj + j, x - di, filter);
					INC(j); x := x + dx
				END
			END;
			WHILE j < h DO
				di := SHORT(ENTIER(x));
				IF di + w > dst.width THEN w := dst.width - di END;
				SkewRow(src, dst, si, sj + j, w, di, dj + j, x - di, filter);
				INC(j); x := x + dx
			END
		
		ELSIF dx < 0 THEN
			IF x + w + h * dx < 0 THEN
				h := -SHORT(ENTIER((x + w)/dx))
			END;
			x := x + j * dx;
			IF x >= dst.width THEN
				n := SHORT(ENTIER((dst.width - x)/dx)) + 1;
				INC(j, n); x := x + n * dx
			END;
			n := j - SHORT(ENTIER(x/dx));	(* row at which x drops below zero *)
			IF n > h THEN n := h END;
			WHILE j < n DO
				di := SHORT(ENTIER(x));
				IF di + w < dst.width THEN
					SkewRow(src, dst, si, sj + j, w, di, dj + j, x - di, filter)
				ELSE
					SkewRow(src, dst, si, sj + j, dst.width - di, di, dj + j, x - di, filter)
				END;
				INC(j); x := x + dx
			END;
			WHILE j < h DO
				di := SHORT(ENTIER(x));
				IF di + w < dst.width THEN
					SkewRow(src, dst, si - di, sj + j, di + w, 0, dj + j, x - di, filter)
				ELSE
					SkewRow(src, dst, si - di, sj + j, dst.width, 0, dj + j, x - di, filter)
				END;
				INC(j); x := x + dx
			END
		
		ELSIF x < 0 THEN
			di := SHORT(ENTIER(x));
			IF di + w > dst.width THEN
				si := si - di; x := x - di;
				WHILE j < h DO
					SkewRow(src, dst, si, sj + j, dst.width, 0, dj + j, x, filter);
					INC(j)
				END
			ELSIF di + w >= 0 THEN
				si := si - di; w := w + di; x := x - di;
				WHILE j < h DO
					SkewRow(src, dst, si, sj + j, w, 0, dj + j, x, filter);
					INC(j)
				END
			END
		
		ELSIF x < dst.width THEN
			di := SHORT(ENTIER(x)); x := x - di;
			IF di + w > dst.width THEN w := dst.width - di END;
			WHILE j < h DO
				SkewRow(src, dst, si, sj + j, w, di, dj + j, x, filter);
				INC(j)
			END
		END
	END SkewRows;
	
	(* shift source column by fractional amount *)
	PROCEDURE SkewCol (src, dst: Map; si, sj, h, di, dj: INTEGER; ty: REAL; VAR filt: Filter);
		VAR sbit, sadr, dbit, dadr: LONGINT;
	BEGIN
		ASSERT((0.0 <= ty) & (ty <= 1.0), 100);	(* rounding problem with ty < 1.0 *)
		IF sj < 0 THEN INC(h, sj); DEC(dj, sj); sj := 0 END;
		IF sj + h > src.height THEN h := src.height - sj END;
		IF h > 0 THEN
			sbit := si * src.fmt.bpp; sadr := src.adr + sj * src.bpr + sbit DIV 8; sbit := sbit MOD 8;
			dbit := di * dst.fmt.bpp; dadr := dst.adr + dj * dst.bpr + dbit DIV 8; dbit := dbit MOD 8;
			filt.vshift(filt, src, dst, sadr, sbit, dadr, dbit, h, ty)
		END
	END SkewCol;
	
	(* shear rectangle in source map vertically; clip to destination boundary *)
	PROCEDURE SkewCols (src, dst: Map; si, sj, w, h, di: INTEGER; y, dy: REAL; VAR filter: Filter);
		VAR i, dj, n: INTEGER;
	BEGIN
		i := 0;
		IF di < 0 THEN
			i := -di;
			IF i >= w THEN RETURN END
		END;
		IF di + w > dst.width THEN
			w := dst.width - di;
			IF w <= 0 THEN RETURN END
		END;
		
		IF dy > 0 THEN
			IF y + w * dy >= dst.height THEN
				w := -SHORT(ENTIER((y - dst.height)/dy))
			END;
			y := y + i * dy;
			IF y + h < 0 THEN
				n := -SHORT(ENTIER((y + h)/dy));
				INC(i, n); y := y + n * dy
			END;
			IF y < 0 THEN
				n := i - SHORT(ENTIER(y/dy));
				IF n > w THEN n := w END;
				WHILE i < n DO
					dj := SHORT(ENTIER(y));
					IF dj + h > dst.height THEN h := dst.height END;
					SkewCol(src, dst, si + i, sj - dj, dj + h, di + i, 0, y - dj, filter);
					INC(i); y := y + dy
				END
			END;
			WHILE i < w DO
				dj := SHORT(ENTIER(y));
				IF dj + h > dst.height THEN h := dst.height - dj END;
				SkewCol(src, dst, si + i, sj, h, di + i, dj, y - dj, filter);
				INC(i); y := y + dy
			END
		
		ELSIF dy < 0 THEN
			IF y + h + w * dy < 0 THEN
				w := -SHORT(ENTIER((y + h)/dy))
			END;
			y := y + i * dy;
			IF y >= dst.height THEN
				n := SHORT(ENTIER((dst.height - y)/dy)) + 1;
				INC(i, n); y := y + n * dy
			END;
			n := i - SHORT(ENTIER(y/dy));	(* column at which y drops below zero *)
			IF n > w THEN n := w END;
			WHILE i < n DO
				dj := SHORT(ENTIER(y));
				IF dj + h < dst.height THEN
					SkewCol(src, dst, si + i, sj, h, di + i, dj, y - dj, filter)
				ELSE
					SkewCol(src, dst, si + i, sj, dst.height - dj, di + i, dj, y - dj, filter)
				END;
				INC(i); y := y + dy
			END;
			WHILE i < w DO
				dj := SHORT(ENTIER(y));
				IF dj + h < dst.height THEN
					SkewCol(src, dst, si + i, sj - dj, h + dj, di + i, 0, y - dj, filter)
				ELSE
					SkewCol(src, dst, si + i, sj - dj, dst.height, di + i, 0, y - dj, filter)
				END;
				INC(i); y := y + dy
			END
		
		ELSIF y < 0 THEN
			dj := SHORT(ENTIER(y));
			IF dj + h > dst.height THEN
				sj := sj - dj; y := y - dj;
				WHILE i < w DO
					SkewCol(src, dst, si + i, sj, dst.height, di + i, 0, y, filter);
					INC(i)
				END
			ELSIF dj + h >= 0 THEN
				sj := sj - dj; h := h + dj; y := y - dj;
				WHILE i < w DO
					SkewCol(src, dst, si + i, sj, h, di + i, 0, y, filter);
					INC(i)
				END
			END
		
		ELSIF y < dst.height THEN
			dj := SHORT(ENTIER(y)); y := y - dj;
			IF dj + h > dst.height THEN h := dst.height - di END;
			WHILE i < w DO
				SkewCol(src, dst, si + i, sj, h, di + i, dj, y, filter);
				INC(i)
			END
		END
	END SkewCols;
	
	(** render translated map on destination **)
	PROCEDURE Translate* (src, dst: Map; tx, ty: REAL; VAR filter: Filter);
		VAR ti, tj, i, j, w, h: INTEGER; tmp: Map;
	BEGIN
		ti := SHORT(ENTIER(tx)); tx := tx - ti;
		tj := SHORT(ENTIER(ty)); ty := ty - tj;
		IF tx < 0.01 THEN
			SkewCols(src, dst, 0, 0, src.width, src.height, ti, tj + ty, 0, filter)
		ELSIF ty < 0.01 THEN
			SkewRows(src, dst, 0, 0, src.width, src.height, tj, ti + tx, 0, filter)
		ELSE
			i := 0; j := 0; w := src.width; h := src.height;
			IF ti < 0 THEN i := -ti; INC(w, ti) END;
			IF ti + w >= dst.width THEN w := dst.width - ti - 1 END;
			IF tj < 0 THEN j := -tj; INC(h, tj) END;
			IF tj + h >= dst.height THEN h := dst.height - tj - 1 END;
			GetTempMap(tmp, Cache, w, h+1);
			SkewCols(src, tmp, i, j, w, h, 0, ty, 0, filter);
			SkewRows(tmp, dst, 0, 0, tmp.width, tmp.height, tj, ti + tx, 0, filter);
			FreeTempMap(tmp, Cache)
		END
	END Translate;
	
	(** render scaled map on destination **)
	PROCEDURE Scale* (src, dst: Map; sx, sy, tx, ty: REAL; VAR filter: Filter);
		VAR xl, xr, yb, yt, w, h, i: INTEGER; dy, y, dx, x: REAL; sadr, sbit, dadr, dbit: LONGINT; tmp: Map;
	BEGIN
		ASSERT((sx > 0) & (sy > 0), 100);
		xl := SHORT(ENTIER(tx)); xr := -SHORT(ENTIER(-(tx + sx * src.width)));
		IF xl < 0 THEN xl := 0 END;
		IF xr > dst.width THEN
			xr := dst.width;
			IF xr <= xl THEN RETURN END;
		END;
		yb := SHORT(ENTIER(ty)); yt := -SHORT(ENTIER(-(ty + sy * src.height)));
		IF yb < 0 THEN yb := 0 END;
		IF yt > dst.height THEN
			yt := dst.height;
			IF yt <= yb THEN RETURN END
		END;
		w := xr - xl; h := yt - yb;
		
		IF ABS(w - src.width) < 1 THEN
			dy := 1.0/sy; y := (0.5 - (ty - ENTIER(ty))) * dy;
			sadr := src.adr; sbit := 0;
			dbit := xl * dst.fmt.bpp; dadr := dst.adr + yb * dst.bpr + dbit DIV 8; dbit := dbit MOD 8;
			i := 0;
			WHILE i < src.width DO
				filter.vscale(filter, src, dst, sadr, sbit, dadr, dbit, h, y, dy);
				sbit := sbit + src.fmt.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8;
				dbit := dbit + dst.fmt.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
				INC(i)
			END
		
		ELSIF ABS(h - src.height) < 1 THEN
			dx := 1.0/sx; x := (0.5 - (tx - ENTIER(tx))) * dx;
			sadr := src.adr; sbit := 0;
			dbit := xl * dst.fmt.bpp; dadr := dst.adr + yb * dst.bpr + dbit DIV 8; dbit := dbit MOD 8;
			i := 0;
			WHILE i < src.height DO
				filter.hscale(filter, src, dst, sadr, sbit, dadr, dbit, w, x, dx);
				INC(sadr, src.bpr); INC(dadr, dst.bpr);
				INC(i)
			END
		
		ELSE
			GetTempMap(tmp, Cache, src.width, h);
			dy := 1.0/sy; y := (0.5 - (ty - ENTIER(ty))) * dy;
			sadr := src.adr; sbit := 0; dadr := tmp.adr; dbit := 0;
			i := 0;
			WHILE i < src.width DO
				filter.vscale(filter, src, tmp, sadr, sbit, dadr, dbit, h, y, dy);
				sbit := sbit + src.fmt.bpp; INC(sadr, sbit DIV 8); sbit := sbit MOD 8;
				dbit := dbit + tmp.fmt.bpp; INC(dadr, dbit DIV 8); dbit := dbit MOD 8;
				INC(i)
			END;
			dx := 1.0/sx; x := (0.5 - (tx - ENTIER(tx))) * dx;
			sadr := tmp.adr; sbit := 0;
			dbit := xl * dst.fmt.bpp; dadr := dst.adr + yb * dst.bpr + dbit DIV 8; dbit := dbit MOD 8;
			i := 0;
			WHILE i < h DO
				filter.hscale(filter, tmp, dst, sadr, sbit, dadr, dbit, w, x, dx);
				INC(sadr, tmp.bpr); INC(dadr, dst.bpr);
				INC(i)
			END;
			FreeTempMap(tmp, Cache)
		END
	END Scale;
	
	(** render rotated map on destination **)
	PROCEDURE Rotate* (src, dst: Map; sin, cos, tx, ty: REAL; VAR filter: Filter);
		VAR m: GfxMatrix.Matrix; tan, htan, wsin, hcos, x, y: REAL; wmax, h, iy, sw, sh: INTEGER; tmp: Map;
	BEGIN
		ASSERT(ABS(sin * sin + cos * cos - 1) < 0.0001, 100);
		m[0, 0] := cos; m[0, 1] := sin; m[1, 0] := -sin; m[1, 1] := cos; m[2, 0] := tx; m[2, 1] := ty;
		Preprocess(src, m);
		cos := m[0, 0]; sin := m[0, 1]; tx := m[2, 0]; ty := m[2, 1];
		tan := sin/(1.0 + cos);	(* identity for tan(phi/2); 1/2 SQRT(3) <= cos <= 1 *)
		sw := src.width; sh := src.height;
		htan := ABS(tan) * sh;
		wsin := ABS(sin) * sw;
		hcos := cos * sh;
		wmax := sw + SHORT(ENTIER(htan)) + 1;	(* width of intermediate image *)
		h := SHORT(ENTIER(wsin + hcos)) + 2;	(* second extra pixel for ty - tj *)
		GetTempMap(tmp, Cache, wmax, h + sh);	(* stack two intermediate images on top of each other *)
		IF sin >= 0 THEN
			x := htan; tx := tx - x; y := hcos - sh
		ELSE
			x := 0; y := wsin; tx := tx + wsin * tan; ty := ty - y
		END;
		iy := SHORT(ENTIER(ty)); y := y + (ty - iy);
		SkewRows(src, tmp, 0, 0, sw, sh, h, x, -tan, filter);	(* first pass: skew horizontal scanlines *)
		SkewCols(tmp, tmp, 0, h, wmax, sh, 0, y, sin, filter);	(* second pass: skew vertical scanlines *)
		SkewRows(tmp, dst, 0, 0, wmax, h, iy, tx, -tan, filter);	(* third pass: skew horizontal scanlines *)
		FreeTempMap(tmp, Cache)
	END Rotate;
	
	(** render horizontally sheared map on destination **)
	PROCEDURE ShearRows* (src, dst: Map; sx, tx: REAL; VAR filter: Filter);
	BEGIN
		SkewRows(src, dst, 0, 0, src.width, src.height, 0, tx, sx, filter)
	END ShearRows;
	
	(** render vertically sheared map on destination **)
	PROCEDURE ShearCols* (src, dst: Map; sy, ty: REAL; VAR filter: Filter);
	BEGIN
		SkewCols(src, dst, 0, 0, src.width, src.height, 0, ty, sy, filter)
	END ShearCols;
	
	(** render affinely transformed map on destination **)
	PROCEDURE Transform* (src, dst: Map; m: GfxMatrix.Matrix; VAR filter: Filter);
		CONST eps = 1.0E-5;
		VAR det, s, dx, x: REAL; iy, w, h, ix: INTEGER; tmp: Map;
	BEGIN
		Preprocess(src, m);
		IF (ABS(m[0, 0]) >= eps) & (ABS(m[1, 1]) >= eps) THEN	(* matrix isn't singular *)
			IF (ABS(m[0, 1]) < eps) & (ABS(m[1, 0]) < eps) THEN	(* no rotation or shear *)
				IF (ABS(m[0, 0]-1) < eps) & (ABS(m[1, 1]-1) < eps) THEN	(* not even scaled *)
					Translate(src, dst, m[2, 0], m[2, 1], filter)
				ELSE
					Scale(src, dst, m[0, 0], m[1, 1], m[2, 0], m[2, 1], filter)
				END
			ELSE
				det := m[0, 0] * m[1, 1] - m[0, 1] * m[1, 0];
				IF ABS(det) >= eps THEN
					IF (ABS(det-1) < eps) & (ABS(m[0, 0] - m[1, 1]) < eps) & (ABS(m[0, 1] + m[1, 0]) < eps) THEN
						Rotate(src, dst, m[0, 1], m[0, 0], m[2, 0], m[2, 1], filter)
					ELSIF ABS(m[0, 1]) < eps THEN	(* horizontal shear *)
						iy := SHORT(ENTIER(m[2, 1]));
						IF ABS(det-1) >= eps THEN	(* scaled *)
							w := SHORT(ENTIER(m[0, 0] * src.width))+1;
							h := SHORT(ENTIER(m[1, 1] * src.height))+1;
							GetTempMap(tmp, Cache, w, h);
							Scale(src, tmp, m[0, 0], m[1, 1], 0, m[2, 1] - iy, filter);
							SkewRows(tmp, dst, 0, 0, tmp.width, tmp.height, iy, m[2, 0], m[1, 0]/m[1, 1], filter);
							FreeTempMap(tmp, Cache)
						ELSIF m[2, 1] - iy < eps THEN	(* integer translation *)
							SkewRows(src, dst, 0, 0, src.width, src.height, iy, m[2, 0], m[1, 0], filter)
						ELSE
							GetTempMap(tmp, Cache, src.width, src.height+1);
							Translate(src, tmp, 0, m[2, 1] - iy, filter);
							SkewRows(tmp, dst, 0, 0, tmp.width, tmp.height, iy, m[2, 0], m[1, 0], filter);
							FreeTempMap(tmp, Cache)
						END
					ELSIF ABS(m[1, 0]) < eps THEN	(* vertical shear *)
						ix := SHORT(ENTIER(m[2, 0]));
						IF ABS(det-1) >= eps THEN	(* scaled *)
							w := SHORT(ENTIER(m[0, 0] * src.width))+1;
							h := SHORT(ENTIER(m[1, 1] * src.height))+1;
							GetTempMap(tmp, Cache, w, h);
							Scale(src, tmp, m[0, 0], m[1, 1], m[2, 0] - ix, 0, filter);
							SkewCols(tmp, dst, 0, 0, tmp.width, tmp.height, ix, m[2, 1], m[0, 1]/m[0, 0], filter);
							FreeTempMap(tmp, Cache)
						ELSIF m[2, 0] - ix < eps THEN	(* integer translation *)
							SkewCols(src, dst, 0, 0, src.width, src.height, ix, m[2, 1], m[0, 1], filter)
						ELSE
							GetTempMap(tmp, Cache, src.width+1, src.height);
							Translate(src, tmp, m[2, 0] - ix, 0, filter);
							SkewRows(tmp, dst, 0, 0, tmp.width, tmp.height, ix, m[2, 1], m[0, 1], filter);
							FreeTempMap(tmp, Cache)
						END
					ELSE
						(*
							use the following identity:
								[ a b ]	[ a         0       ] [        1           0 ] [ 1 b/a ]
								[ c d ] = [ 0 (ad-bc)/a ] [ ca/(ad-bc) 1 ]  [ 0   1   ]
						*)
						s := det/m[0, 0];
						w := SHORT(ENTIER(m[0, 0] * src.width))+1;
						h := SHORT(ENTIER(s * src.height))+1;
						dx := m[1, 0]/s; x := (h-1) * ABS(dx) + 2;
						GetTempMap(tmp, Cache, w - 2*SHORT(ENTIER(-x)) + 1, 2*h);
						Scale(src, tmp, m[0, 0], s, x, h, filter);
						ix := SHORT(ENTIER(m[2, 0]));
						SkewRows(tmp, tmp, 0, h, tmp.width, h, 0, m[2, 0] - ix, dx, filter);
						w := SHORT(ENTIER(x));
						IF dx >= 0 THEN
							SkewCols(tmp, dst, w, 0, tmp.width - w, h, ix, m[2, 1], m[0, 1]/m[0, 0], filter)
						ELSE
							s := m[0, 1]/m[0, 0];
							SkewCols(tmp, dst, 0, 0, tmp.width - w, h, ix - w, m[2, 1] - w * s, s, filter)
						END;
						FreeTempMap(tmp, Cache)
					END
				END
			END
		END
	END Transform;
	
	
	(**--- Palettes ---**)
	
	PROCEDURE RGBDist (dr, dg, db: LONGINT): LONGINT;
	BEGIN
		(* return the sum plus the minimum of the per-color distances *)
		IF dr < dg THEN
			IF dr < db THEN RETURN 2*dr + dg + db
			ELSE RETURN dr + dg + 2*db
			END
		ELSE
			IF dg < db THEN RETURN dr + 2*dg + db
			ELSE RETURN dr + dg + 2*db
			END
		END
	END RGBDist;
	
	(** return index of color in palette that best approximates the requested color **)
	PROCEDURE BestIndex* (pal: Palette; red, green, blue: INTEGER): INTEGER;
		VAR dist, d: LONGINT; rad, n, r, g, b, slot, beg, end, i, dr, dg, db, best: INTEGER; cand: ARRAY 256 OF INTEGER; c: Color;
	BEGIN
		dist := MAX(LONGINT); rad := 2;
		REPEAT
			n := 0;
			FOR r := (red - rad) DIV 32 TO (red + rad) DIV 32 DO
				IF (0 <= r) & (r < 8) THEN
					FOR g := (green - rad) DIV 32 TO (green + rad) DIV 32 DO
						IF (0 <= g) & (g < 8) THEN
							FOR b := (blue - rad) DIV 32 TO (blue + rad) DIV 32 DO
								IF (0 <= b) & (b < 8) THEN
									slot := 64*r + 8*g + b; beg := ORD(pal.cube[slot]); end := ORD(pal.cube[slot+1]);
									WHILE beg # end DO
										cand[n] := ORD(pal.index[beg]); INC(n); beg := (beg+1) MOD 100H
									END
								END
							END
						END
					END
				END
			END;
			i := 0;
			WHILE (i < n) & (dist > 0) DO
				c := pal.col[cand[i]];
				dr := ABS(red - c.r); dg := ABS(green - c.g); db := ABS(blue - c.b);
				IF (dr <= rad) & (dg <= rad) & (db <= rad) THEN
					d := RGBDist(dr, dg, db);
					IF d < dist THEN
						best := cand[i]; dist := d
					END
				END;
				INC(i)
			END;
			rad := rad * rad
		UNTIL dist < MAX(LONGINT);
		RETURN best
	END BestIndex;
	
	(** compute internal palette structures whenever palette colors have been modified **)
	PROCEDURE InitPalette* (pal: Palette; used: INTEGER);
		VAR i, p, s, j, k: INTEGER; perm, slot: ARRAY 256 OF INTEGER;
	BEGIN
		pal.used := used;
		i := 0;
		WHILE i < used DO
			perm[i] := i;
			slot[i] := 64*(pal.col[i].r DIV 32) + 8*(pal.col[i].g DIV 32) + pal.col[i].b DIV 32;
			(* "cube[slot[i]] is mapped to color perm[i]" *)
			INC(i)
		END;
		
		(* sort by insertion (fast for default Oberon palette because large parts of it are already in same order) *)
		i := 0;
		WHILE i < used DO
			p := perm[i]; s := slot[i]; j := i; k := j-1;
			WHILE (k >= 0) & (slot[k] > s) DO
				perm[j] := perm[k]; slot[j] := slot[k];
				j := k; DEC(k)
			END;
			perm[j] := p; slot[j] := s;
			INC(i)
		END;
		
		(* now ready to assign cube slots *)
		i := 0; s := 0;
		WHILE i < used DO
			pal.index[i] := CHR(perm[i]);
			WHILE s <= slot[i] DO pal.cube[s] := CHR(i); INC(s) END;
			INC(i)
		END;
		pal.cube[512] := CHR(i MOD 100H)	(* sentinel value *)
	END InitPalette;
	
	(** (re-)initialize display palette (necessary when Display palette has been updated) **)
	PROCEDURE InitDisplayPalette*;
		VAR i, r, g, b, n: INTEGER;
	BEGIN
		i := 0;
		WHILE i < 256 DO	(* fill complete palette even if display depth is less than 8 *)
			Display.GetColor(i, r, g, b);
			DisplayPal.col[i].r := r; DisplayPal.col[i].g := g; DisplayPal.col[i].b := b;
			INC(i)
		END;
		n := SHORT(ASH(1, Display.Depth(Display.ColLeft)));
		IF n > 256 THEN n := 256 END;
		InitPalette(DisplayPal, n)
	END InitDisplayPalette;
	
	(** compute and initialize a pseudo-optimal palette for an image map (in hi-color or true-color) **)
	PROCEDURE ComputePalette* (map: Map; pal: Palette; maxcols: INTEGER);
		(*
			uses octree-quantization
		*)
		
		TYPE
			Node = POINTER TO RECORD	(* octree node *)
				dsc: ARRAY 8 OF Node;	(* descendants *)
				link: Node;	(* next reducible node on same level *)
				leaf: BOOLEAN;
				weight: LONGINT;	(* accumulated number of pixels represented by this node *)
				r, g, b: LONGINT;	(* accumulated color values *)
			END;
		
		VAR
			sent, root: Node; reducible: ARRAY 8 OF Node; colors, maxDepth, y, x, used: INTEGER;
			adr, a, b: LONGINT; pix: Pixel;
		
		PROCEDURE insert (VAR node: Node; depth: INTEGER; pix: Pixel);
			VAR idx, bit: INTEGER;
		BEGIN
			IF node = NIL THEN
				NEW(node);
				IF depth = maxDepth THEN
					node.leaf := TRUE;
					INC(colors)
				ELSE
					node.leaf := FALSE;
					node.link := reducible[depth]; reducible[depth] := node
				END
			END;
			INC(node.weight);	(* node represents more pixels *)
			IF node.leaf THEN
				INC(node.r, LONG(ORD(pix[R])));
				INC(node.g, LONG(ORD(pix[G])));
				INC(node.b, LONG(ORD(pix[B])))
			ELSE
				idx := 0; bit := 7-depth;
				IF ODD(ASH(ORD(pix[R]), -bit)) THEN INC(idx, 4) END;
				IF ODD(ASH(ORD(pix[G]), -bit)) THEN INC(idx, 2) END;
				IF ODD(ASH(ORD(pix[B]), -bit)) THEN INC(idx) END;
				insert(node.dsc[idx], depth+1, pix)
			END
		END insert;
		
		PROCEDURE reduce;
			VAR d, n, i: INTEGER; node, prev, dsc: Node; min: LONGINT;
		BEGIN
			d := maxDepth-1;
			WHILE reducible[d] = NIL DO
				DEC(d); DEC(maxDepth)
			END;
			sent.link := reducible[d];
			node := sent; min := MAX(LONGINT);
			WHILE node.link # NIL DO
				IF node.link.weight < min THEN
					min := node.link.weight; prev := node
				END;
				node := node.link
			END;
			node := prev.link; prev.link := node.link;
			reducible[d] := sent.link;
			n := 1;	(* number of colors is initially one for the node itself *)
			FOR i := 0 TO 7 DO
				dsc := node.dsc[i];
				IF dsc # NIL THEN
					DEC(n);	(* reducing one color *)
					INC(node.r, dsc.r); INC(node.g, dsc.g); INC(node.b, dsc.b);
					node.dsc[i] := NIL
				END
			END;
			node.leaf := TRUE;
			INC(colors, n)
		END reduce;
		
		PROCEDURE traverse (node: Node);
			VAR i: INTEGER;
		BEGIN
			IF node # NIL THEN
				IF node.leaf THEN
					pal.col[used].r := SHORT(node.r DIV node.weight);
					pal.col[used].g := SHORT(node.g DIV node.weight);
					pal.col[used].b := SHORT(node.b DIV node.weight);
					INC(used)
				ELSE
					FOR i := 0 TO 7 DO
						traverse(node.dsc[i])
					END
				END
			END
		END traverse;
		
	BEGIN	(* ComputePalette *)
		NEW(sent);
		root := NIL; colors := 0; maxDepth := 8;
		GetMoveProc(map.fmt, BGR24, SrcCopy);
		y := 0; adr := map.adr;
		WHILE y < map.height DO
			IF map.fmt.bpp < 8 THEN
				x := 0; a := adr; b := 0;
				WHILE x < map.width DO
					SrcCopy.move(SrcCopy, a, b, SYSTEM.ADR(pix[0]), 0, 1);
					insert(root, 0, pix);
					WHILE colors > maxcols DO
						reduce()
					END;
					INC(x); b := b + map.fmt.bpp; INC(a, b DIV 8); b := b MOD 8
				END
			ELSE
				x := 0; a := adr; b := map.fmt.bpp DIV 8;
				WHILE x < map.width DO
					SrcCopy.move(SrcCopy, a, 0, SYSTEM.ADR(pix[0]), 0, 1);
					insert(root, 0, pix);
					WHILE colors > maxcols DO
						reduce()
					END;
					INC(x); INC(a, b)
				END
			END;
			INC(y); INC(adr, map.bpr)
		END;
		used := 0;
		traverse(root);
		InitPalette(pal, used)
	END ComputePalette;
	
	
	(**--- Map Objects ---**)
	
	PROCEDURE Write* (VAR r: Files.Rider; map: Map);
		VAR m: Map; h, adr, w, a, len: LONGINT; buf: ARRAY 256 OF CHAR;
	BEGIN
		IF ~(map.fmt.code IN {a1..bgra32}) THEN
			NEW(m);
			IF map.fmt.components = {Red, Green, Blue} THEN Create(m, map.width, map.height, BGR24)
			ELSIF map.fmt.components = {Alpha} THEN Create(m, map.width, map.height, A8)
			ELSIF map.fmt.components = {Index} THEN Create(m, map.width, map.height, I8)
			ELSE Create(m, map.width, map.height, BGRA32)
			END;
			Copy(map, m, 0, 0, map.width, map.height, 0, 0, SrcCopy);
			map := m
		END;
		Files.WriteNum(r, 1);	(* version *)
		Files.WriteNum(r, map.fmt.code);
		Files.WriteNum(r, map.width); Files.WriteNum(r, map.height);
		Files.WriteNum(r, ABS(map.bpr));
		h := map.height; adr := map.adr;
		WHILE h > 0 DO
			w := ABS(map.bpr); a := adr;
			WHILE w > 0 DO
				len := 256;
				IF len > w THEN len := w END;
				SYSTEM.MOVE(a, SYSTEM.ADR(buf[0]), len);
				Files.WriteBytes(r, buf, len);
				DEC(w, len); INC(a, len)
			END;
			DEC(h); INC(adr, map.bpr)
		END;
		IF map.fmt.code IN {a1, a8} THEN
			Files.Write(r, CHR(map.fmt.col.r));
			Files.Write(r, CHR(map.fmt.col.g));
			Files.Write(r, CHR(map.fmt.col.b))
		ELSIF map.fmt.code = i8 THEN
			IF map.fmt.pal = DisplayPal THEN
				Files.WriteInt(r, -1)
			ELSE
				Files.WriteInt(r, map.fmt.pal.used);
				a := 0;
				WHILE a < map.fmt.pal.used DO
					Files.Write(r, CHR(map.fmt.pal.col[a].r));
					Files.Write(r, CHR(map.fmt.pal.col[a].g));
					Files.Write(r, CHR(map.fmt.pal.col[a].b));
					INC(a)
				END
			END
		END
	END Write;
	
	PROCEDURE Read* (VAR r: Files.Rider; map: Map);
		VAR ver, code, w, h, bpr, adr, a, len: LONGINT; fmt: Format; buf: ARRAY 256 OF CHAR; ch: CHAR; used: INTEGER;
	BEGIN
		Files.ReadNum(r, ver);	(* only know version 1, skip check *)
		Files.ReadNum(r, code);
		CASE code OF
		| a1: fmt := A1
		| a8: fmt := A8
		| i8: fmt := I8
		| bgr555: fmt := BGR555
		| bgr565: fmt := BGR565
		| bgr24: fmt := BGR24
		| bgra32: fmt := BGRA32
		END;
		Files.ReadNum(r, w); Files.ReadNum(r, h);
		Create(map, SHORT(w), SHORT(h), fmt);
		Files.ReadNum(r, bpr);
		ASSERT(bpr <= map.bpr);
		adr := map.adr;
		WHILE h > 0 DO
			w := bpr; a := adr;
			WHILE w > 0 DO
				len := 256;
				IF len > w THEN len := w END;
				Files.ReadBytes(r, buf, len);
				SYSTEM.MOVE(SYSTEM.ADR(buf[0]), a, len);
				DEC(w, len); INC(a, len)
			END;
			DEC(h); INC(adr, map.bpr)
		END;
		IF code IN {a1, a8} THEN
			Files.Read(r, ch); map.fmt.col.r := ORD(ch);
			Files.Read(r, ch); map.fmt.col.g := ORD(ch);
			Files.Read(r, ch); map.fmt.col.b := ORD(ch)
		ELSIF code = i8 THEN
			Files.ReadInt(r, used);
			IF used < 0 THEN
				map.fmt.pal := DisplayPal
			ELSE
				a := 0;
				WHILE a < used DO
					Files.Read(r, ch); map.fmt.pal.col[a].r := ORD(ch);
					Files.Read(r, ch); map.fmt.pal.col[a].g := ORD(ch);
					Files.Read(r, ch); map.fmt.pal.col[a].b := ORD(ch);
					INC(a)
				END;
				InitPalette(map.fmt.pal, used)
			END
		END
	END Read;
	
	PROCEDURE Handle* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR map, copy: Map; lib: Objects.Library; ref: INTEGER;
	BEGIN
		map := obj(Map);
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				IF msg.id = Objects.enum THEN
					msg.Enum("Width"); msg.Enum("Height")
				ELSIF msg.id = Objects.get THEN
					IF msg.name = "Gen" THEN msg.class := Objects.String; msg.s := "GfxMaps.New"; msg.res := 0
					ELSIF msg.name = "Width" THEN msg.class := Objects.Int; msg.i := map.width; msg.res := 0
					ELSIF msg.name = "Height" THEN msg.class := Objects.Int; msg.i := map.height; msg.res := 0
					END
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # map.stamp THEN
					NEW(copy); map.dlink := copy; map.stamp := msg.stamp;
					IF msg.id = Objects.shallow THEN
						copy.handle := map.handle; copy.width := map.width; copy.height := map.height;
						copy.fmt := map.fmt; copy.bpr := map.bpr; copy.adr := map.adr; copy.mem := map.mem
					ELSE
						Create(copy, map.width, map.height, map.fmt);
						IF (map.fmt.pal # NIL) & (map.fmt.pal # DisplayPal) THEN
							NEW(copy.fmt.pal); copy.fmt.pal.col := map.fmt.pal.col; copy.fmt.pal.used := map.fmt.pal.used;
							copy.fmt.pal.cube := map.fmt.pal.cube; copy.fmt.pal.index := map.fmt.pal.index
						END
					END
				END;
				msg.obj := map.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			lib := msg(Objects.BindMsg).lib;
			IF lib # NIL THEN
				IF (map.lib = NIL) OR (map.lib.name[0] = 0X) & (map.lib # lib) THEN
					lib.GenRef(lib, ref);
					IF ref >= 0 THEN
						lib.PutObj(lib, ref, map)
					END
				END
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Write(msg.R, map)
				ELSIF msg.id = Objects.load THEN
					Read(msg.R, map)
				END
			END
		END
	END Handle;
	
	PROCEDURE New*;
		VAR map: Map;
	BEGIN
		NEW(map); map.handle := Handle;
		Objects.NewObj := map
	END New;
	
	
	(*--- Initialization ---*)
	
	PROCEDURE InitBitTables;
		VAR b, i: LONGINT;
	BEGIN
		FOR b := 0 TO 0FFH DO
			FOR i := 0 TO 7 DO
				IF ODD(ASH(b, -i)) THEN
					Bit[b, i] := TRUE; Set[b, i] := CHR(b); Clear[b, i] := CHR(b - ASH(1, i))
				ELSE
					Bit[b, i] := FALSE; Set[b, i] := CHR(b + ASH(1, i)); Clear[b, i] := CHR(b)
				END
			END
		END
	END InitBitTables;
	
	PROCEDURE InitClamp;
		VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO 1FFH DO Clamp[i] := 0X END;
		FOR i := 0 TO 0FFH DO Clamp[200H+i] := CHR(i) END;
		FOR i := 300H TO 4FFH DO Clamp[i] := 0FFX END
	END InitClamp;
	

BEGIN
	NEW(DisplayPal);
	InitDisplayPalette;
	InitFormat(A1, 1, 1, {Alpha}, NIL, PackA1, UnpackA1); A1.code := a1;
	InitFormat(A8, 8, 1, {Alpha}, NIL, PackA8, UnpackA8); A8.code := a8;
	InitFormat(I8, 8, 1, {Index}, DisplayPal, PackI8, UnpackI8); I8.code := i8;
	InitFormat(BGR555, 16, 2, {Red, Green, Blue}, NIL, PackBGR555, UnpackBGR555); BGR555.code := bgr555;
	InitFormat(BGR565, 16, 2, {Red, Green, Blue}, NIL, PackBGR565, UnpackBGR565); BGR565.code := bgr565;
	InitFormat(BGR24, 24, 4, {Red, Green, Blue}, NIL, PackBGR24, UnpackBGR24); BGR24.code := bgr24;
	InitFormat(BGRA32, 32, 4, {Red, Green, Blue, Alpha}, NIL, PackBGRA32, UnpackBGRA32); BGRA32.code := bgra32;
	PixelFormat := BGRA32;
	SrcCopy.blend := SrcCopyProc; SrcCopyBlend := SrcCopyProc;
	SrcAlpha.blend := SrcAlphaProc; SrcAlphaBlend := SrcAlphaProc;
	InitFilter(NoFilter, SrcAlphaProc, HShift, VShift, HScale, VScale);
	InitFilter(LinearFilter, SrcAlphaProc, LinearHShift, LinearVShift, LinearHScale, LinearVScale);
	InitBitTables; InitClamp
END GfxMaps.
