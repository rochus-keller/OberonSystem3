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

MODULE Pictures;	(** portable, except where noted *) (* tn, 1992 *)

(** Module Pictures implement an abstract data type (and object type) for manipulating colored bitmaps of various color depths.
*)

IMPORT SYSTEM, Texts, Oberon, Files, Display, Objects, Bitmaps, Modules, Out;

CONST 
	TryAll = TRUE;	(* try all converters if first one fails *)
	
	redraw* = 4; resize* = 5;	(** UpdateMsg id. *)
	PictFileId*= - 4093; 	(** First two bytes of a .Pict file (0F0H, 3H). *)

TYPE 
	Picture* = POINTER TO PictureDesc;
	UpdateMsg* = RECORD (Display.FrameMsg)
		id*, u*, v*, w*, h*: INTEGER;
		pict*: Picture;
	END;

	Addr = POINTER TO RECORD END;
	
	ColorTable = POINTER TO ColorTableDesc;
	ColorTableDesc = ARRAY 256 OF RECORD red, green, blue: INTEGER END;

	PictureDesc* = RECORD(Objects.ObjDesc)
		width*, height*, depth*: INTEGER;	(** Width, height in pixels, and depth in bits per pixel (1, 4, or 8). *)
		wth: LONGINT;
		bitmap: Bitmaps.Bitmap;
		address*: LONGINT;	(** non-portable *) (** Pointer to bitmap data. *)
		ct: ColorTable;
		refr : Addr
	END;
	
VAR 
	dots*: Display.Pattern;	
	colorD*: INTEGER;	(** Default bitmap color depth. *)
	grey: ARRAY 4 OF Display.Pattern;
	greyPat: ARRAY 4 OF ARRAY 5 OF LONGINT;
	handler: Objects.Handler;
	cRes: INTEGER; cName: ARRAY 128 OF CHAR; cP: Picture;
	first: BOOLEAN;

PROCEDURE InBoundaries(x, y, w, h: INTEGER): BOOLEAN;
CODE {SYSTEM.i386}
	MOV AX, x[EBP]
	MOV BX, y[EBP]
	CMP AX, 0
	JL false
	CMP BX, 0
	JL false
	CMP w[EBP], AX
	JLE false
	CMP h[EBP], BX
	JLE false
	MOV EAX, 1
	LEAVE
	RET 16
false:
	XOR EAX, EAX
	LEAVE 
	RET 16
END InBoundaries;
	
(** Get the color index of the bitmap pixel at X, Y. *)
PROCEDURE Get*(P:Picture;X,Y:INTEGER):INTEGER;
BEGIN 
	IF InBoundaries(X, Y, P.width, P.height) THEN RETURN Bitmaps.Get(P.bitmap,X,Y) ELSE RETURN Display.BG END
END Get;

(** Put a pixel of color col at x, y using mode. *)
PROCEDURE Dot*(P:Picture; col:INTEGER;X,Y,mode:INTEGER);
BEGIN 
	IF InBoundaries(X, Y, P.width, P.height) THEN Bitmaps.Dot(P.bitmap,col,X,Y, mode) END
END Dot;	

(** Starting at position x, y, determine the longest run of the same colored pixels (col) on the same scanline. Afterwards x indicates the first pixel of a different color thatn col. *)
PROCEDURE GetRun*(P:Picture;VAR col:INTEGER; VAR X:INTEGER; Y:INTEGER);
BEGIN
	IF InBoundaries(X, Y, P.width, P.height) THEN
		col := Get(P,X,Y); INC(X); 
		WHILE (Get(P,X,Y) = col) & (X < P.width) DO INC(X) END
	END
END GetRun;

(** Copy a the block sx, sy, w, h from picture sP to position dx, dy in destination picture dP. Source and destination picture may be the same. *)
PROCEDURE CopyBlock* (sP,dP: Picture; SX, SY, W, H, DX, DY, mode: INTEGER); 
BEGIN
	IF InBoundaries(SX, SY, sP.width, sP.height) THEN
		ASSERT((W >= 0) & (H >= 0));
		IF InBoundaries(DX, DY, dP.width, dP.height) THEN
			IF SX+W > sP.width THEN W := sP.width-SX END;
			IF DX+W > dP.width THEN W := dP.width-DX END;
			IF SY+ H > sP.height THEN H := sP.height-SY END;
			IF DY+H > dP.height THEN H := dP.height-DY END;
			Bitmaps.CopyBlock(sP.bitmap, dP.bitmap,SX, SY, W, H, DX, DY,mode);
		END
	END
END CopyBlock;

(** Copy the pattern pat in color col to position x, y using mode. *)
PROCEDURE CopyPattern* (P:Picture;col:INTEGER;pat:LONGINT;X,Y,mode: INTEGER); 
VAR w, h: INTEGER;
BEGIN
	IF InBoundaries(X, Y, P.width, P.height) THEN
		w := 0;  h := 0;  SYSTEM.GET(pat, SYSTEM.VAL(CHAR, w));
		SYSTEM.GET(pat+1, SYSTEM.VAL(CHAR, h));
		IF InBoundaries(X+w-1, Y+h-1, P.width, P.height) THEN
			Bitmaps.CopyPattern(P.bitmap,col,pat,X, Y, mode)
		END
	END
END CopyPattern;
	
(** Block fill area x, y, w, h in color col using mode. *)
PROCEDURE ReplConst* (P:Picture; col,X,Y,W,H,mode:INTEGER); 
BEGIN 
	IF InBoundaries(X, Y, P.width, P.height) THEN
		ASSERT((W >= 0) & (H >= 0));
		IF X+W > P.width THEN W := P.width-X END;
		IF Y+H > P.height THEN H := P.height-Y END;
		Bitmaps.ReplConst(P.bitmap,col, X, Y, W, H, mode)
	END
END ReplConst;
	
(** Pattern fill pattern pat in the area x, y, w, h in color col using mode. *)
PROCEDURE ReplPattern* (P:Picture;col:INTEGER;pat:LONGINT;X,Y,W,H,mode: INTEGER); 
BEGIN
	IF InBoundaries(X, Y, P.width, P.height) THEN
		ASSERT((W >= 0) & (H >= 0));
		IF X+W > P.width THEN W := P.width-X END;
		IF Y+H > P.height THEN H := P.height-Y END;
		Bitmaps.ReplPattern(P.bitmap,col,pat,X,Y,W,H,mode);
	END
END ReplPattern;
	
(** Copy area SX, SY, SW, SH of source picture sP to area DX, DY, DW, DH of destination picture dP. Appropriate scaling is done. *)
PROCEDURE Copy*(sP,dP:Picture;SX,SY,SW,SH,DX,DY,DW,DH,mode:INTEGER); 
VAR hx, hy,DW2,SW2: LONGINT; 
		dx, dy, SXo, DXo: INTEGER;
BEGIN 
	IF (SW> 0) &(SH >0) &(DW >0 ) &(DH > 0) THEN
		dy := DY + DH; dx := DX + DW; SXo := SX; DXo := DX; DW2 := 2 * DW; SW2 := 2 * SW;  
		hy := 2*SH - DH; 
		WHILE DY < dy DO
		hx := 2* SW - DW; DX := DXo; SX := SXo;
			WHILE DX < dx DO
				Dot(dP,Get(sP,SX,SY),DX,DY,mode);
				WHILE hx > 0 DO INC(SX); DEC(hx,DW2) END;
				INC(DX); INC(hx,SW2)
			END;
			WHILE hy > 0 DO INC(SY); hy := hy - 2 * DH END;
			INC(DY); hy := hy + 2* SH
		END
	END
END Copy;

(* ==================================================================================*)
	
(** Define the color palette for color index col. *)
PROCEDURE SetColor* (P: Picture; col, red, green, blue: INTEGER);
BEGIN
	P.ct[col].red := red; P.ct[col].green := green; P.ct[col].blue := blue
END SetColor;

(** Retrieve the color palette entry for color index col. *)
PROCEDURE GetColor* (P: Picture; col: INTEGER; VAR red, green, blue: INTEGER);
BEGIN
	red := P.ct[col].red; green := P.ct[col].green; blue := P.ct[col].blue 
END GetColor;

PROCEDURE StoreCT(VAR R: Files.Rider; ct: ColorTable; depth: INTEGER);
VAR i: INTEGER;
BEGIN 
	Files.WriteBytes(R,depth,2); depth := ABS(depth);
	i := 0; 
	WHILE i < ASH(1,depth) DO 
		Files.WriteBytes(R,ct[i].red,1);Files.WriteBytes(R,ct[i].green,1);Files.WriteBytes(R,ct[i].blue,1);
		INC(i)
	END
END StoreCT;

PROCEDURE LoadCT(VAR R: Files.Rider; ct: ColorTable; depth: INTEGER);
VAR i: INTEGER; 
BEGIN
	i := 0; 
	WHILE i < ASH(1,depth) DO 
		ct[i].red := 0; ct[i].green := 0; ct[i].blue := 0;
		Files.ReadBytes(R,ct[i].red,1);Files.ReadBytes(R,ct[i].green,1);Files.ReadBytes(R,ct[i].blue,1);
		INC(i)
	END
END LoadCT;

(** Indicate that a change has been made to the area X, Y, W, H of P. This results in an UpdateMsg with id = redraw to be broadcasted into the display space. *)
PROCEDURE Update*(P: Picture; X, Y , W, H: INTEGER);
VAR msg: UpdateMsg;
BEGIN
	msg.u := X; msg.v := Y; msg.w := W; msg.h := H; 
	msg.id := redraw; msg.pict := P; msg.res := -1; msg.F := NIL;
	Display.Broadcast(msg)
END Update;

(** Copy the area x, y, w, h of picture P to position dx, dy on the display. *)
PROCEDURE DisplayBlock*(P: Picture; X, Y, W, H, DX, DY, mode: INTEGER);
VAR screen: Picture; 
		L, B, R, T, cw, ch: INTEGER;
BEGIN
	Display.GetClip(L,B,cw,ch); R := L + cw; T := B + ch;
	IF DX + W < R THEN R := DX + W END; IF DY + H < T THEN T := DY + H END;
	IF DX > L THEN L := DX END; IF DY > B THEN B := DY END;
	INC(X,L-DX); INC(Y,B - DY); W := R-L; H := T-B;
	IF (R > L) & (T > B) THEN 
		IF InBoundaries(X, Y, P.width, P.height) THEN
			IF X+W > P.width THEN W := P.width-X END;
			IF Y+H > P.height THEN H := P.height-Y END;
			Bitmaps.DisplayBlock(P.bitmap,X, Y, W, H, L, B, mode)
		END
	END
END DisplayBlock;

PROCEDURE New(VAR P: Picture; width, height, depth: INTEGER; addr: LONGINT);
VAR H: LONGINT;
BEGIN
	P.handle := handler; 
	P.depth := 8; P.width := width; P.height := height; P.wth := width;
	IF addr = 0 THEN 
		H := P.wth* P.height +10; 
		SYSTEM.NEW(P.refr, H); 
		P.address := SYSTEM.VAL(LONGINT,P.refr)
	ELSE P.address := addr END;
	NEW(P.bitmap); 
	Bitmaps.Define(P.bitmap,P.width,P.height,8,P.address); 
	NEW(P.ct)
END New;

PROCEDURE Clear(P: Picture);
BEGIN 
	Bitmaps.Clear(P.bitmap) 
END Clear;

(** Create a picture of size width x height with depth bits per pixel. The picture palette is initialized to a default state. If not enough memory is available to allocate the bitmap data, the width, height, and depth of the picture is set to zero. *) 
PROCEDURE Create*(P: Picture; width, height, depth: INTEGER);
VAR i, r, g, b: INTEGER; 
BEGIN
	IF depth > 8 THEN HALT(99) END; (* number too large *)
	New(P,width,height,depth,0);
	Clear(P);
	i := 0;
	WHILE i < 256 DO Display.GetColor(i, r, g, b); SetColor(P, i, r, g, b); INC(i) END;
END Create;

(** Like Dot, for a line of pixels. *)

PROCEDURE PutLine*(P: Picture; VAR data: ARRAY OF INTEGER; x, y, w: INTEGER);
VAR i: INTEGER;
BEGIN
	i := 0;
	WHILE i < w DO
		Dot(P, data[i], x, y, Display.replace);
		INC(i);  INC(x)
	END
END PutLine;

(** Like Get, for a line of pixels. *)

PROCEDURE GetLine*(P: Picture; VAR data: ARRAY OF INTEGER; x, y, w: INTEGER);
VAR i: INTEGER;
BEGIN
	i := 0;
	WHILE i < w DO
		data[i] := Get(P, x, y);
		INC(i);  INC(x)
	END
END GetLine;

(** Stores picture run length encoded to file F (including tag). *)
PROCEDURE Store* (P: Picture; F : Files.File; pos: LONGINT; VAR len: LONGINT);	
(* stores picture to run length encoded file F  (including tag *)
	VAR j, i,a,b,d,wth: INTEGER; adr, OldAdr, size: LONGINT; h: SHORTINT; 
			buf: ARRAY 129 OF SHORTINT; R: Files.Rider;
			ch: CHAR;
			help: BOOLEAN;
BEGIN
	Files.Set(R, F, pos); 	
	j := PictFileId; Files.WriteBytes(R,j,2); 
	Files.WriteBytes(R,P.width,2); Files.WriteBytes(R,P.height,2); StoreCT(R,P.ct,P.depth);
	d := P.depth;
	wth := SHORT(P.wth);
	IF d=1 THEN wth := SHORT((P.wth+7) DIV 8)
	ELSIF d=4 THEN wth := SHORT((P.wth+1) DIV 2) END;
	size := P.wth*P.height; 
	size := size - P.wth;
	adr := P.address+size;
	i := 0; 
	WHILE i < P.height DO
		OldAdr := adr;
		a := 0;
		j := 1; buf[0] := 0; 
		Bitmaps.GetPix(adr,buf[j],d); 
		b := a + 1;
		WHILE b < wth DO
			Bitmaps.GetPix(adr,h,d); help := (h = buf[j]) & (j = 1);
			IF ((b - a) < 127) & ((buf[0] = 0) OR help OR ((h # buf[j]) & (j > 1))) THEN (* same run *)
					IF h # buf[j] THEN INC(buf[0]); INC(j); buf[j] := h ELSE DEC(buf[0]) END
			ELSE (* new run *)
				IF (buf[j] = h) & (b - a # 127) THEN DEC(buf[0]); Files.WriteBytes(R, buf, j); buf[0] := -1
				ELSE Files.WriteBytes(R, buf, j + 1); buf[0] := 0 END;
				j := 1; buf[j] := h; a := b
			END; 
			b := b + 1 
		END;
		adr := OldAdr; adr := adr-P.wth;
		Files.WriteBytes(R, buf, j + 1); 
		INC(i)
	END;
	len := Files.Pos(R) - pos
END Store;

PROCEDURE LoadRLE(P: Picture; VAR R: Files.Rider; rv: BOOLEAN);
	(* load run length encoded picture *)
	VAR ch: CHAR; k,d,h: INTEGER; a, b,c,ce: LONGINT; cL,cH: CHAR;
BEGIN
	a := P.address;
	c := P.wth;
	b := P.height;
	c := c*(b-1);
	b := a + c;
	a := b;
	ce := b+P.wth;
	c := P.height; 
	d := P.depth;
	WHILE c > 0 DO
		Files.Read(R, ch); k := ORD(ch);
		IF k < 128 THEN 
			REPEAT 
				Files.Read(R, ch); 
				Bitmaps.PutPix(b,ce,ch,d);
				IF b>=ce THEN ce := ce-P.wth; b := a-P.wth; a := b; c := c-1 END;
				k := k -1;
			UNTIL k < 0
		ELSIF k >= 128 THEN
			k := 257 - k; 
			Files.Read(R, ch); 
			REPEAT 
				Bitmaps.PutPix(b,ce,ch,d);
				IF b>=ce THEN ce := ce-P.wth; b := a-P.wth; a := b; c := c-1 END;
				k := k -1 
			UNTIL k < 1 
		END
	END
END LoadRLE;

(** Load a run length encoded picture from position pos from file F. Pos should be AFTER the two byte picture identification of a picture file. *)
PROCEDURE Load*(P: Picture; F : Files.File; pos: LONGINT; VAR len: LONGINT);	
	VAR R: Files.Rider; h, i, orient,id,d: INTEGER; 
			(* buf: ARRAY MaxWth OF CHAR; *) err: ARRAY 32 OF CHAR;
			size,p,adr,n: LONGINT; rle: BOOLEAN;
BEGIN	
	Files.Set(R,F,pos-2); Files.ReadBytes(R,id,2); 
	IF id = PictFileId THEN
		Files.ReadBytes(R,P.width,2); 
		Files.ReadBytes(R,P.height,2); 
		Files.ReadBytes(R,P.depth,2); 
		NEW(P.ct); 
		LoadCT(R,P.ct,P.depth);
		P.wth := P.width; 
		size := P.wth * P.height;
		SYSTEM.NEW(P.refr, size+10); 
		P.address := SYSTEM.VAL(LONGINT,P.refr); 
		NEW(P.bitmap); 
		Bitmaps.Define(P.bitmap,P.width,P.height,P.depth,P.address); 
		LoadRLE(P,R,P.depth = 1)
	ELSE err := "This file is not a picture "; HALT(42) END;
	P.handle := handler;
	len := Files.Pos(R) - pos
END Load;

PROCEDURE SplitName (VAR name, MName, PName: ARRAY OF CHAR);
	VAR i, j: INTEGER;
BEGIN i := 0;
	WHILE name[i] # "." DO MName[i] := name[i]; INC(i) END;
	MName[i] := 0X; INC(i); j := 0;
	WHILE name[i] # 0X DO PName[j] := name[i]; INC(i); INC(j) END;
	PName[j] := 0X
END SplitName;

PROCEDURE GetExt(VAR name, ext: ARRAY OF CHAR);
	VAR i, j: INTEGER;
BEGIN
	i := 0; j := 0; WHILE name[i] # 0X DO IF name[i] = "." THEN j := i+1 END; INC(i) END;
	i := 0; WHILE name[j] # 0X DO ext[i] := name[j]; INC(i); INC(j) END; ext[i] := 0X;
END GetExt;

PROCEDURE TryConverter(newproc: ARRAY OF CHAR);
	VAR mname, pname: ARRAY 32 OF CHAR; mod: Modules.Module; cmd: Modules.Command; 
		FM: Objects.FileMsg; F: Files.File;
BEGIN
	SplitName(newproc, mname, pname);
	(*Kernel.WriteString("Pictures ");  Kernel.WriteString(mname);
	Kernel.WriteChar(".");  Kernel.WriteString(pname);*)
	mod := Modules.ThisMod(mname);
	IF Modules.res = 0 THEN
		cmd := Modules.ThisCommand(mod, pname);
		IF Modules.res = 0 THEN Objects.NewObj := cP; cmd;
			F := Files.Old(cName);
			FM.id := Objects.load; Files.Set(FM.R, F, 0); cP.handle(cP, FM);
			IF FM.len = 0 THEN cRes := 1 ELSE cRes := 0 END
		ELSE cRes := 1
		END
	ELSE cRes := 1
	END;
	(*Kernel.WriteInt(FM.len, 8);  Kernel.WriteInt(cRes, 5);  Kernel.WriteLn*)
END TryConverter;

PROCEDURE ConverterOpen;
	VAR ext: ARRAY 32 OF CHAR; newproc: ARRAY 64 OF CHAR;  s: Texts.Scanner;
BEGIN
	cRes := 0; GetExt(cName, ext);
	Oberon.OpenScanner(s, "PictureConverters");  newproc := "";
	IF first & (s.class = Texts.Inval) THEN
		first := FALSE;  Out.String("Oberon.Text - PictureConverters not found");  Out.Ln
	END;
	WHILE s.class = Texts.Name DO
		IF s.s = ext THEN
			Texts.Scan(s);  Texts.Scan(s);
			IF s.class = Texts.Name THEN
				COPY(s.s, newproc);  s.class := Texts.Inval
			END
		ELSE
			Texts.Scan(s);  Texts.Scan(s);  Texts.Scan(s)
		END
	END;
	IF newproc # "" THEN TryConverter(newproc) ELSE cRes := 1 END;
	IF TryAll & (cRes # 0) THEN
		Oberon.OpenScanner(s, "PictureConverters");
		WHILE (cRes # 0) & (s.class = Texts.Name) DO
			Texts.Scan(s);  Texts.Scan(s);
			IF (s.class = Texts.Name) & (s.s # newproc) THEN TryConverter(s.s) END;
			Texts.Scan(s)
		END
	END
END ConverterOpen;

(** Open the picture file with name from disk. Any graphic file format listed in the PictureConverters section of Oberon.Text can be loaded (e.g. GIF, JPEG, XBM, BMP). *)
PROCEDURE Open*(P: Picture; name: ARRAY OF CHAR; color: BOOLEAN);
	VAR F :Files.File; R: Files.Rider; len: LONGINT; x,depth: INTEGER; P2: Picture;
	dname: ARRAY 64 OF CHAR; d: INTEGER; (* << jm *)
BEGIN
	F := Files.Old(name);
	IF color THEN depth := 8 ELSE depth := 1 END;
	IF F # NIL THEN 			
		Files.Set(R,F, 0); x := 0; Files.ReadInt(R, x);
		IF x = 07F7H THEN (* << document *)
			Files.ReadString(R, dname); Files.ReadInt(R, d); Files.ReadInt(R, d); Files.ReadInt(R, d); Files.ReadInt(R, d);
			Files.ReadInt(R, x);
		END;
		IF x = PictFileId THEN Load(P, F, Files.Pos(R), len); P.handle := handler
		ELSE 
			cP := P; COPY(name, cName); ConverterOpen;
			IF cRes # 0 THEN P.width := 0; P.height := 0; P.depth := 0 END;
			cP := NIL; P.handle := handler
		END;
		IF P.depth < depth THEN 
			NEW(P2); Create(P2, P.width, P.height,depth);
			CopyBlock(P, P2, 0, 0, P.width, P.height, 0, 0, Display.replace);
			P^ := P2^
		END
	ELSE P.width := 0; P.height := 0; P.depth := 0
	END
END Open;

(** Returns the address of the bitmap data of a picture. *)
PROCEDURE Address*(P: Picture): LONGINT;	(** non-portable *)
VAR val, x, i, j: INTEGER; w: LONGINT;
BEGIN 
	HALT(99)	(* should not be used *)
END Address;

(** Default picture object handler. *)

PROCEDURE Handle*(obj: Objects.Object; VAR msg: Objects.ObjMsg);
	VAR len: LONGINT; P2: Picture; ref: INTEGER;
BEGIN		
	WITH obj: Picture DO
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO 
				IF (msg.id = Objects.get) & (msg.name = "Gen") THEN 
					msg.class := Objects.String; COPY("Pictures.NewPicture", msg.s); msg.res := 0 
				END;
			END;
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Store(obj,Files.Base(msg.R), Files.Pos(msg.R), len); 
					Files.Set(msg.R,Files.Base(msg.R),Files.Pos(msg.R) + len)
				ELSIF msg.id = Objects.load THEN
					Load(obj,Files.Base(msg.R), Files.Pos(msg.R)+ 2, len); 
					Files.Set(msg.R,Files.Base(msg.R),Files.Pos(msg.R) +2 + len);
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp = obj.stamp THEN msg.obj := obj.dlink (*non-first arrival*)
				ELSE
					NEW(P2); obj.stamp := msg.stamp; obj.dlink := P2;
					Create(P2,obj.width,obj.height,obj.depth);
					CopyBlock(obj,P2,0,0,obj.width, obj.height, 0,0,Display.replace);
					P2.ct := obj.ct;
					msg.obj := P2;
				END
			END
		ELSIF msg IS Objects.BindMsg THEN
			WITH msg: Objects.BindMsg DO
				IF (obj.lib = NIL) OR (obj.lib.name = "") & (obj.lib # msg.lib) THEN
					msg.lib.GenRef(msg.lib,ref);
					msg.lib.PutObj(msg.lib,ref,obj);
				END;
			END
		END
	END
END Handle;

(** Generator for a picture object. *)
PROCEDURE NewPicture*;
VAR P: Picture;
BEGIN
	NEW(P); Create(P,1,1,1); Objects.NewObj := P 
END NewPicture;

PROCEDURE Init;
VAR i: INTEGER; s: ARRAY 8 OF SET;
BEGIN	
	handler := Handle;  colorD := 8;  first := TRUE;

	s[0] := {}; 
	s[1] := {1..7,9..15,17..23,25..31}; 
	s[2] := s[1]; 
	s[3] := s[1]; 
	s[4] := s[1]; 
	s[5] := s[1]; 
	s[6] := s[1]; 
	s[7] := s[1];
	dots := Display.NewPattern(32,8, s);
	greyPat[0,0] := 02100000H; greyPat[0,1] :=  0AAAAAAAAH; greyPat[0,2] := 0;
	greyPat[1,0] := 04100000H; greyPat[1,1] :=  011111111H; greyPat[1,2] := 0; greyPat[1,3] := 0; greyPat[1,4] := 0;
	greyPat[2,0] := 02100000H; greyPat[2,1] :=  0AAAAAAAAH; greyPat[2,2] := 0FFFFFFFFH;
	greyPat[3,0] := 04100000H; greyPat[3,1] :=  011111111H; greyPat[3,2] := 0; greyPat[3,3] := 044444444H; greyPat[3,4] := 0;

	grey[0] := SYSTEM.ADR(greyPat[1]) +2; 
	grey[1] := SYSTEM.ADR(greyPat[3]) +2; 
	grey[2] := SYSTEM.ADR(greyPat[0]) +2; 
	grey[3] := Display.grey1;
END Init;

BEGIN
	Init	
END Pictures.

(** Remarks

1. The origin (0, 0) is the bottom left corner of a bitmap. A picture has a bitmap and a color palette. The color palette specifies the reg, green, blue components (in the range 0 - 255) of the color indexes in the bitmap data. Only palettized bitmaps are supported in depths of 1, 4, and 8 bits per pixel. On most Oberon platforms the color palette of a picture is ignored when displaying the picture. Instead the picture is displayed with the current screen palette. To see the true colors of a picture, the picture palette has to be copied into the screen palette.

2. The drawing modes are the same as that of module Display (replace, paint, invert). After drawing into a picture, a module should indicate using procedure Update what area of the picture should be displayed fresh.

3. On many Oberon platforms the address of the bitmap data is set to zero. This indicates that it is impossible to access the bitmap directly.

4. Native Oberon only supports bit depths of 8 bits per pixel.

5. When opening a GIF picture with Pictures.Open, the GIF background color is burned in to color 14 (light grey).

6. Implementation restriction
Picture objects cannot be named or have attributes (see module Attributes). Picture objects only understand the messages Objects.FileMsg, Objects.CopyMsg and Objects.BindMsg.

*)