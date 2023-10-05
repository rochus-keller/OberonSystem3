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

MODULE ICO;	(** portable *)	(* Win 3.11 Icon Resource files to Oberon Picture Format *)

	(*	Oktober '96			first release						-> V 1.0	*)

IMPORT BIT,Display,Files,Objects,Pictures,Out;

CONST
	ICONRESID = 1;	(* Resource type, Icons have 1 *)
	BMIHSIZE = 40;	(* Size of BitmapInfoHeader Record in Bytes (WfW 3.1)*)
TYPE
	IconDirEntry = RECORD
		width,	(* Width, in pixels, of the image *)
		height,	(* Height, in pixels, of the image *)
		colorCount: CHAR;	(* Number of colors in image, 0 if >= 8bpp *)
		planes,	(* Color Planes *)
		bitCount: INTEGER;	(* Bits per Pixel *)
		bytesInRes,	(* how many bytes in this resource *)
		imageOffset: LONGINT;	(* where in the file is this image? *)
	END;

	BitmapInfoHeader = RECORD
		size,	(* Size of BitmapInfoHeader *)
		width,	(* width of the bitmap in Pixels *)
		height: LONGINT;	(* height of the bitmap in Pixels *)
		planes,	(* # of planes for the target device, must be 1 *)
		bitCount: INTEGER;	(* Bits per Pixels, should be 1,4 or 8 *)
		compression,	(* not used*)
		sizeImage: LONGINT;	(* Imagesize in bytes *)
		xPelsPerMeter,	(* not used *)
		yPelsPerMeter: LONGINT;	(* not used *)
		clrUsed,	(* not used *)
		clrImportant: LONGINT;	(* not used *)
	END;
VAR
	colorMap: ARRAY 256 OF INTEGER;
	iconIndex: INTEGER;

PROCEDURE ReadDir(VAR R: Files.Rider): INTEGER;
	(* Read the File's Directory *)
VAR
	val: INTEGER;
BEGIN
	Files.ReadInt(R,val);	(* Reserved, must be 0 *)
	IF (val # 0) THEN RETURN(-1); END;
	Files.ReadInt(R,val);	(* Resource type *)
	IF (val # ICONRESID) THEN RETURN(-1); END;
	Files.ReadInt(R,val);	(* Amount of Images, should be 1 *)
	RETURN(val);
END ReadDir;

PROCEDURE ReadDirEntry(VAR R: Files.Rider; VAR entry: IconDirEntry);
	(* Read one directory entry *)
VAR
	c: CHAR;
BEGIN
	Files.Read(R,entry.width); Files.Read(R,entry.height);
	Files.Read(R,entry.colorCount);
	Files.Read(R,c);	(* Reserved *)
	Files.ReadInt(R,entry.planes); Files.ReadInt(R,entry.bitCount);
	Files.ReadLInt(R,entry.bytesInRes);
	Files.ReadLInt(R,entry.imageOffset);
END ReadDirEntry;

PROCEDURE ReadBitmapInfoHeader*(VAR R: Files.Rider; VAR bmih: BitmapInfoHeader): BOOLEAN;
	(* scan the Bitmapinfoheader *)
BEGIN
	Files.ReadLInt(R,bmih.size);
	IF (bmih.size # BMIHSIZE) THEN
		Files.Set(R,Files.Base(R),Files.Pos(R)-SIZE(LONGINT)); RETURN(FALSE);
	ELSE
		Files.ReadLInt(R,bmih.width); Files.ReadLInt(R,bmih.height);
		Files.ReadInt(R,bmih.planes); Files.ReadInt(R,bmih.bitCount);
		Files.ReadLInt(R,bmih.compression);
		Files.ReadLInt(R,bmih.sizeImage);
		Files.ReadLInt(R,bmih.xPelsPerMeter);
		Files.ReadLInt(R,bmih.yPelsPerMeter);
		Files.ReadLInt(R,bmih.clrUsed); Files.ReadLInt(R,bmih.clrImportant);
		RETURN(TRUE);
	END;
END ReadBitmapInfoHeader;

PROCEDURE ScanCol (VAR R: Files.Rider; pict: Pictures.Picture; nrColor: LONGINT; conversion: BOOLEAN);
	(* copied from BMP.Mod *)
VAR Red, Green, Blue, c: CHAR; C, min, d, x, y, z: LONGINT; i, j, minj: INTEGER; r, g, b: ARRAY 256 OF INTEGER;
BEGIN
	C := ASH(1, Display.Depth(0)) - 1;
	IF nrColor > C THEN nrColor := C ELSE DEC(nrColor) END;
	IF conversion THEN
		FOR i := 0 TO SHORT(C) DO Display.GetColor(i, r[i], g[i], b[i]) END;
		FOR i := 0 TO SHORT(nrColor) DO
			Files.Read(R, Blue); Files.Read(R, Green); Files.Read(R, Red); Files.Read(R, c);
			min := MAX(LONGINT);
			FOR j := 0 TO SHORT(C) DO
				x := ABS(ORD(Red) - r[j]); y := ABS(ORD(Green) - g[j]); z := ABS(ORD(Blue) - b[j]);
				d := x;
				IF y > d THEN d := y END;
				IF z > d THEN d := z END;
				d := d*d + (x*x + y*y + z*z);
				IF d < min THEN min := d; minj := j END
			END;
			colorMap[i] := minj;
			Pictures.SetColor(pict, i, r[i], g[i], b[i])
		END
	ELSE
		FOR i := 0 TO SHORT(nrColor) DO
			Files.Read(R, Blue); Files.Read(R, Green); Files.Read(R, Red); Files.Read(R, c);
			Pictures.SetColor(pict, i, ORD(Red), ORD(Green), ORD(Blue));
			colorMap[i] := i
		END
	END
END ScanCol;

PROCEDURE LoadIcon(VAR R: Files.Rider; ndx,transparentCol: INTEGER; colorConversion: BOOLEAN; pict: Pictures.Picture);
VAR
	dir: IconDirEntry;
	bmih: BitmapInfoHeader;
	c: CHAR;
	k: SHORTINT;
	i,length: LONGINT;
	
	PROCEDURE PosX(ndx: LONGINT): INTEGER;
	BEGIN
		RETURN(SHORT(ndx MOD bmih.width));
	END PosX;
	
	PROCEDURE PosY(ndx: LONGINT): INTEGER;
	BEGIN
		RETURN(SHORT(ndx DIV bmih.width));
	END PosY;

BEGIN
	FOR i:= 1 TO ndx DO ReadDirEntry(R,dir); END;
	Files.Set(R,Files.Base(R),dir.imageOffset);
	IF ReadBitmapInfoHeader(R,bmih) THEN
		Out.Int(ORD(dir.width),0); Out.Char("*"); Out.Int(ORD(dir.height),0);
		Out.String(", "); Out.Int(ORD(dir.colorCount),0); Out.String(" colors."); Out.Ln();
		IF ((ORD(dir.width) MOD 2) + (ORD(dir.height) MOD 2) > 0) THEN
			Out.String("Icon dimension not supported"); Out.Ln(); RETURN;
		END;
		Pictures.Create(pict,ORD(dir.width),ORD(dir.height),bmih.bitCount);
		IF (pict.depth = 0) THEN
			Out.String("not enough memory"); Out.Ln(); RETURN
		END;
		length:= ORD(dir.width) * ORD(dir.height);
		ScanCol(R,pict,ORD(dir.colorCount),colorConversion);
		i:= 0;
		WHILE (i < length) DO
			Files.Read(R,c);
			IF (bmih.bitCount = 8) THEN
				Pictures.Dot(pict,colorMap[ORD(c)],PosX(i),PosY(i),Display.replace); INC(i);
			ELSIF (bmih.bitCount = 4) THEN
				Pictures.Dot(pict,colorMap[BIT.IAND(BIT.ILSH(ORD(c),-4),0FH)],PosX(i),PosY(i),Display.replace); INC(i);
				Pictures.Dot(pict,colorMap[BIT.IAND(ORD(c),0FH)],PosX(i),PosY(i),Display.replace); INC(i);
			ELSIF (bmih.bitCount = 1) THEN
				FOR k:= 7 TO 0 BY -1 DO
					IF BIT.BIT(ORD(c),k) THEN
						Pictures.Dot(pict,colorMap[15],PosX(i),PosY(i),Display.replace);
					ELSE
						Pictures.Dot(pict,colorMap[0],PosX(i),PosY(i),Display.replace);
					END;
					INC(i);
				END;
			ELSE
				Out.String("ICO-format not supported"); Out.Ln(); RETURN;
			END;
		END;
		i:= 0;
		WHILE (i < length) DO
			Files.Read(R,c);
			FOR k:= 7 TO 0 BY -1 DO
				IF BIT.BIT(ORD(c),k) THEN
					Pictures.Dot(pict,transparentCol,PosX(i),PosY(i),Display.replace);
				END;
				INC(i);
			END;
		END;
	END;
END LoadIcon;

PROCEDURE Handle*(obj: Objects.Object; VAR msg: Objects.ObjMsg);
VAR
	pos: LONGINT;
	icons,this: INTEGER;
BEGIN
	WITH obj: Pictures.Picture DO
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO 
				IF (msg.id = Objects.get) & (msg.name = "Gen") THEN
					msg.class:= Objects.String; COPY("Pictures.NewPicture",msg.s); msg.res:=0 
				END;
			END;
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF (msg.id = Objects.load) THEN
					pos:= Files.Pos(msg.R); icons:= ReadDir(msg.R); this:= 1;
					IF (icons > 0) THEN
						IF (icons > 1) THEN
							IF (iconIndex <= icons) THEN this:= iconIndex; ELSE this:= icons; END;
							Out.String("MS Windows Icon"); Out.Ln();
							Out.Int(this,0); Out.String(". Icon of "); Out.Int(icons,0); Out.String(", ");
						END;
						LoadIcon(msg.R,this,14,TRUE,obj);
					ELSE
						Files.Set(msg.R,Files.Base(msg.R),pos);
					END;
					msg.len:= Files.Pos(msg.R) - pos;
				ELSE
					Pictures.Handle(obj,msg)
				END;
			END;
		ELSE 
			Pictures.Handle(obj, msg)
		END;
	END;
END Handle;

(** Called from Pictures.Open to try and load an ICO bitmap. The picture descriptor is pre-allocated by Pictures in
Objects.NewObj. InitPicture overwrites the handler of the picture with a new handler that will load the Win3.11
Icon when a FileMsg is received (variant load). *)
PROCEDURE InitPicture*;
BEGIN
	Objects.NewObj.handle:= Handle;
END InitPicture;
	
PROCEDURE NewPicture*;
VAR
	P: Pictures.Picture;
BEGIN
	NEW(P); P.handle:= Handle; Objects.NewObj:= P;
END NewPicture;

BEGIN
	iconIndex:= 1;
END ICO.
