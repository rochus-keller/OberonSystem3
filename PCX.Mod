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

MODULE PCX;	(** portable *)	(* by W. Ibl *)
(** PCX Image files to Oberon Picture Format *)
(*
	Oct '96	first release
	Oct '96	first working release
	Nov '96	color plane bug removed
*)

IMPORT BIT,Display,Files,Objects,Pictures,Out;

TYPE
	PCXHeader = RECORD
		creator,	(* File-Id, should be 10 for ZSoft *)
		version,	(* Version: 0=V2.5, 2=V2.8+Pal, 3=V2.8-Pal,5=V3.0+Pal *)
		encoding,	(* 1=Runlength Encoding *)
		bits: CHAR;	(* Bits/Pixel *)
		xMin,yMin,xMax,yMax,	(* logical Picture Coordinates *)
		hRes,vRes: INTEGER;	(* Resolution of the origin device *)
		palPos,picPos: LONGINT;	(* File positon of palette and picture data *)
		vMode,planes: CHAR;	(* not used *)
		bytesPerLine,	(* Bytes per Scan-Line *)
		paletteInfo: INTEGER;	(* Colorinfo: 1=Color, 2=Grayscale *)
	END;
VAR
	colorMap: ARRAY 256 OF INTEGER;

PROCEDURE ReadPCXHeader(VAR R: Files.Rider; VAR pcxh: PCXHeader): BOOLEAN;
	(* Scan the PCX File Header *)
VAR
	filler: ARRAY 58 OF CHAR;
BEGIN
	Files.Read(R,pcxh.creator);
	IF (pcxh.creator # 0AX) THEN
		Files.Set(R,Files.Base(R),Files.Pos(R)-SIZE(CHAR));
		RETURN(FALSE);
	ELSE
		Files.Read(R,pcxh.version); Files.Read(R,pcxh.encoding);
		Files.Read(R,pcxh.bits);
		Files.ReadInt(R,pcxh.xMin); Files.ReadInt(R,pcxh.yMin);
		Files.ReadInt(R,pcxh.xMax); Files.ReadInt(R,pcxh.yMax);
		Files.ReadInt(R,pcxh.hRes); Files.ReadInt(R,pcxh.vRes);
		IF (pcxh.bits <= 4X) OR (pcxh.version = 00X) OR (pcxh.version = 03X) THEN
			pcxh.palPos:= Files.Pos(R);
		ELSE
			pcxh.palPos:= Files.Length(Files.Base(R)) - (256 * 3);
		END;
		Files.ReadBytes(R,filler,48);
		Files.Read(R,pcxh.vMode); Files.Read(R,pcxh.planes);
		Files.ReadInt(R,pcxh.bytesPerLine); Files.ReadInt(R,pcxh.paletteInfo);
		Files.ReadBytes(R,filler,58); pcxh.picPos:= Files.Pos(R);
		RETURN(TRUE);
	END;
END ReadPCXHeader;

PROCEDURE ScanCol (VAR R: Files.Rider; pict: Pictures.Picture; nrColor: LONGINT; conversion: BOOLEAN);
	(* copied from BMP.Mod *)
VAR Red, Green, Blue: CHAR; C, min, d, x, y, z: LONGINT; i, j, minj: INTEGER; r, g, b: ARRAY 256 OF INTEGER;
BEGIN
	C := ASH(1, Display.Depth(0)) - 1;
	IF nrColor > C THEN nrColor := C ELSE DEC(nrColor) END;
	IF conversion THEN
		FOR i := 0 TO SHORT(C) DO Display.GetColor(i, r[i], g[i], b[i]) END;
		FOR i := 0 TO SHORT(nrColor) DO
			Files.Read(R, Red); Files.Read(R, Green); Files.Read(R, Blue);
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
			Pictures.SetColor(pict, i, r[i], g[i], b[i]);
		END
	ELSE
		FOR i := 0 TO SHORT(nrColor) DO
			Files.Read(R, Red); Files.Read(R, Green); Files.Read(R, Blue);
			Pictures.SetColor(pict, i, ORD(Red), ORD(Green), ORD(Blue));
			colorMap[i] := i
		END
	END
END ScanCol;

PROCEDURE LoadPCX(VAR R: Files.Rider; transparentCol: INTEGER; colorConversion: BOOLEAN; pict: Pictures.Picture);
	(* Load the PCX picture information into an Oberon Pictures.Picture *)
VAR
	pcxh: PCXHeader;
	line: POINTER TO ARRAY OF CHAR;
	x,y,z,w,h,rep: INTEGER;
	k,p: SHORTINT;
	c: CHAR;
BEGIN
	IF ReadPCXHeader(R,pcxh) THEN
		w:= pcxh.xMax-pcxh.xMin; h:= pcxh.yMax-pcxh.yMin;
		p:= 0; x:= 0; y:= h; z:= ORD(pcxh.planes);
		Out.String("ZSoft PC Paintbrush"); Out.Ln();
		Out.Int(w+1,0); Out.Char("*"); Out.Int(h+1,0); Out.String(", ");
		Out.Int(ORD(pcxh.bits),0); Out.String(" bits / ");
		Out.Int(z,0); Out.String(" planes, ");
		Out.Int(ASH(1,z*ORD(pcxh.bits)),0); Out.String(" colors."); Out.Ln();
		IF (pcxh.bits # 1X) & (pcxh.bits # 8X) THEN
			Out.String("Plane depth not supported"); Out.Ln(); RETURN;
		END;
		Pictures.Create(pict,w+1,h+1,z*ORD(pcxh.bits));
		IF (pict.depth = 0) THEN
			Out.String("not enough memory"); Out.Ln();
		ELSE
			NEW(line,pcxh.xMax+1);
			Files.Set(R,Files.Base(R),pcxh.palPos);
			ScanCol(R,pict,ASH(1,z*ORD(pcxh.bits)),colorConversion);
			Files.Set(R,Files.Base(R),pcxh.picPos);
			FOR rep:= 0 TO pcxh.xMax-1 DO line[rep]:= 0X; END;
			WHILE (y >= 0) DO	(* picture scan lines *)
				WHILE (p < z) DO	(* color planes *)
					Files.Read(R,c);
					(* if bit 7 and 8 are both 1, runlength encoding is activated *)
					IF (pcxh.encoding = 1X) & (BIT.CAND(c,0C0X) = 0C0X) THEN
						rep:= ORD(BIT.CAND(c,3FX)); Files.Read(R,c);
					ELSE
						rep:= 1;
					END;
					WHILE (rep > 0) DO	(* runlength encoding *)
						IF (pcxh.bits = 8X) THEN	(* full 256 colors *)
							line[x]:= c;
							IF (x = w) THEN x:= 0; INC(p); ELSE INC(x); END;
						ELSIF (pcxh.bits = 1X) THEN	(* color plane coding *)
							FOR k:= 7 TO 0 BY -1 DO
								IF BIT.BIT(ORD(c),k) THEN BIT.CSETBIT(line[x],p); END;
								IF (x = w) THEN k:= -1; x:= 0; INC(p); ELSE INC(x); END;
							END;
						END;
						DEC(rep);
					END;
				END;
				FOR x:= 0 TO w DO
					Pictures.Dot(pict,colorMap[ORD(line[x])],x,y,Display.replace);
					line[x]:= 0X;
				END;
				x:= 0; DEC(y); p:= 0;
			END;
		END;
	END;
END LoadPCX;

PROCEDURE Handle*(obj: Objects.Object; VAR msg: Objects.ObjMsg);
VAR
	pos: LONGINT;
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
					pos:= Files.Pos(msg.R);
					LoadPCX(msg.R,14,TRUE,obj); msg.len:= Files.Pos(msg.R) - pos;
				ELSE
					Pictures.Handle(obj,msg)
				END;
			END;
		ELSE 
			Pictures.Handle(obj, msg)
		END;
	END;
END Handle;

(** Called from Pictures.Open to try and load an PCX bitmap. The picture descriptor is pre-allocated by Pictures in
Objects.NewObj. InitPicture overwrites the handler of the picture with a new handler that will load the PCX
Picture when a FileMsg is received (variant load). *)
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

END PCX.
