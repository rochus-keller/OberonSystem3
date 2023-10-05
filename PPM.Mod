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

MODULE PPM;	(** portable *)	(** by W. Ibl *)
(** The Portable Pixmap/Graymap File Format to Oberon Picture Format *)
(*
	Jul '97	first release
	Aug '97	combined PGM & PPM
	Aug '97	added PBM format
	Aug '97	added DocGadget support
*)
IMPORT BIT,Display,Documents,Files,Objects,Out,Pictures,Strings,Texts;

CONST
	Portable = "P";	(* Indicator for portable formats *)
	PlainGray = "2";	(* Magic Number for the plain format graymap *)
	PlainColor = "3";	(* Magic Number for the plain format pixmap *)
	Bitmap = "4";	(* Magic Number for the raw format bitmap *)
	RawbitsGray = "5";	(* Magic Number for the raw format graymap *)
	RawbitsColor = "6";	(* Magic Number for the raw format pixmap *)
	Comment = "#";
	CR = Strings.CR;
	LF = Strings.LF;
	Tab = Strings.Tab;
TYPE
	(* Combined Rider to parse through PGM Files either stored as an
	Oberon Text or imported from DOS (CR+LF) or UNIX (LF) *)
	Rider = RECORD
		rider: Files.Rider;
		reader: Texts.Reader;
		text: Texts.Text;	(* needed for Set *)
		ofs: LONGINT;	(* needed for Pos - Position, where text starts in file *)
		eof: BOOLEAN;	(* str is for text parsing, eof is copied from rider.eof or reader.eot *)
		Read: PROCEDURE(VAR R: Rider; VAR c: CHAR);	(* read a byte *)
		Pos: PROCEDURE(VAR R: Rider): LONGINT;	(* get current file position *)
		Set: PROCEDURE(VAR R: Rider; pos: LONGINT);	(* seek to given file position *)
	END;
VAR
	map,r0,g0,b0,r1,g1,b1: ARRAY 256 OF INTEGER;
	mode: CHAR;
	depth: LONGINT;
	delta: INTEGER;
	credit: BOOLEAN;

(* Rider Methods *)

PROCEDURE ReadFile(VAR R: Rider; VAR c: CHAR);
BEGIN
	Files.Read(R.rider,c); R.eof:= R.rider.eof;
END ReadFile;

PROCEDURE PosFile(VAR R: Rider): LONGINT;
BEGIN
	RETURN(Files.Pos(R.rider));
END PosFile;

PROCEDURE SetFile(VAR R: Rider; pos: LONGINT);
BEGIN
	Files.Set(R.rider,Files.Base(R.rider),pos); R.eof:= R.rider.eof;
END SetFile;

PROCEDURE ReadText(VAR R: Rider; VAR c: CHAR);
BEGIN
	Texts.Read(R.reader,c); R.eof:= R.reader.eot;
END ReadText;

PROCEDURE PosText(VAR R: Rider): LONGINT;
BEGIN
	RETURN(R.ofs+Texts.Pos(R.reader));
END PosText;

PROCEDURE SetText(VAR R: Rider; pos: LONGINT);
BEGIN
	Texts.OpenReader(R.reader,R.text,pos);
	Files.Set(R.rider,Files.Base(R.rider),pos); R.eof:= R.rider.eof;
END SetText;

(* End of Rider Methods *)

PROCEDURE OpenRider(VAR FR: Files.Rider; VAR R: Rider; pos: LONGINT);
	(* initialize a Rider. Supported are Oberon Texts and DOS/UNIX Files *)
VAR
	c: CHAR;
	len: LONGINT;
	val: INTEGER;
	line: Objects.Name;
BEGIN
	Files.Read(FR,c);
	IF (c = CHR(Documents.Id)) THEN	(* skip document header *)
		Files.Read(FR,c); Files.ReadString(FR,line);
		Files.ReadInt(FR,val); Files.ReadInt(FR,val);
		Files.ReadInt(FR,val); Files.ReadInt(FR,val);
		Files.Read(FR,c);
	END;	
	IF (c = Texts.TextBlockId) THEN
		NEW(R.text); Texts.Load(R.text,Files.Base(FR),pos+1,len);
		Texts.OpenReader(R.reader,R.text,0);
		R.ofs:= pos; R.eof:= R.reader.eot;
		R.Read:= ReadText; R.Pos:= PosText; R.Set:= SetText;
	ELSE
		Files.Set(R.rider,Files.Base(FR),pos); R.eof:= R.rider.eof;
		R.Read:= ReadFile; R.Pos:= PosFile; R.Set:= SetFile;
	END;
END OpenRider;

PROCEDURE WhiteSpace(c: CHAR): BOOLEAN;
BEGIN
	RETURN((c = CR) OR (c = LF) OR (c = Tab) OR (c = " "));
END WhiteSpace;

PROCEDURE SkipComment(VAR R: Rider; VAR c: CHAR);
BEGIN
	REPEAT R.Read(R,c) UNTIL R.eof OR (c = CR) OR (c = LF);
	WHILE WhiteSpace(c) DO R.Read(R,c); END;
	IF (c = Comment) THEN SkipComment(R,c); END;
END SkipComment;

PROCEDURE MagicNumber(VAR R: Rider): BOOLEAN;
	(* check for the magic string *)
VAR
	c: CHAR;
	b: BOOLEAN;
BEGIN
	b:= FALSE; R.Read(R,c);
	IF (c = Comment) THEN SkipComment(R,c); END;
	IF (c = Portable) THEN
		R.Read(R,mode);
		IF (mode = Comment) THEN SkipComment(R,c); END;
		b:= (mode = PlainGray) OR (mode = PlainColor) OR
			  (mode = Bitmap) OR
			  (mode = RawbitsGray) OR (mode = RawbitsColor);
	END;
	RETURN(b);
END MagicNumber;

PROCEDURE Value(VAR R: Rider): INTEGER;
	(* return an integer value read from the text stream *)
VAR
	c: ARRAY 71 OF CHAR;
	i: LONGINT;
BEGIN
	IF R.eof THEN
		i:= -1;
	ELSE
		i:= 0;
		REPEAT R.Read(R,c[i]); UNTIL R.eof OR ~WhiteSpace(c[i]);
		IF (c = Comment) THEN SkipComment(R,c[i]); END;
		WHILE ~R.eof & ~WhiteSpace(c[i]) DO INC(i); R.Read(R,c[i]); END;
		c[i]:= 0X; Strings.StrToInt(c,i);
	END;
	RETURN(SHORT(i));
END Value;

PROCEDURE ScanGrayMap(pict: Pictures.Picture; nrColor: LONGINT; conversion: BOOLEAN);
	(* build a colormap from segmented grayscale values *)
VAR
	Gray: CHAR;
	min,d,x,y,z: LONGINT;
	i,j,k,minj: INTEGER;
BEGIN
	IF conversion THEN
		i:= 0;
		FOR k:= 0 TO SHORT(nrColor) DO
			Gray:= CHR(i); min:= MAX(LONGINT);
			FOR j:= 0 TO SHORT(depth) DO
				x:= ABS(ORD(Gray)-r0[j]); y:= ABS(ORD(Gray)-g0[j]); z:= ABS(ORD(Gray)-b0[j]);
				d:= x;
				IF (y > d) THEN d:= y; END;
				IF (z > d) THEN d:= z; END;
				d:= d*d + (x*x + y*y + z*z);
				IF (d < min) THEN min:= d; minj:= j; END
			END;
			map[k]:= minj;
			Pictures.SetColor(pict,k,r0[k],g0[k],b0[k]);
			INC(i,delta);
		END;
	ELSE
		i:= 0;
		FOR k:= 0 TO SHORT(nrColor) DO
			Gray:= CHR(i);
			Pictures.SetColor(pict,k,ORD(Gray),ORD(Gray),ORD(Gray));
			map[k]:= i;
			INC(i,delta);
		END;
	END;
END ScanGrayMap;

PROCEDURE ScanColor(pict: Pictures.Picture; i,red,green,blue: INTEGER; conversion: BOOLEAN): INTEGER;
	(* build a colormap by using the read values of red,green and blue *)
VAR
	min,d,x,y,z: LONGINT;
	j,k,minj: INTEGER;
BEGIN
	IF conversion THEN
		k:= 0;
		WHILE (k < 256) & (map[k] # -1) DO
			IF (r1[k] = red) & (g1[k] = green) & (b1[k] = blue) THEN RETURN(map[k]); END;
			INC(k);
		END;
		min:= MAX(LONGINT);
		FOR j:= 0 TO SHORT(depth) DO
			x:= ABS((red*delta)-r0[j]); y:= ABS((green*delta)-g0[j]); z:= ABS((blue*delta)-b0[j]);
			d:= x;
			IF (y > d) THEN d:= y; END;
			IF (z > d) THEN d:= z; END;
			d:= d*d + (x*x + y*y + z*z);
			IF (d < min) THEN min:= d; minj:= j; END
		END;
		IF (k < 256) THEN r1[k]:= red; g1[k]:= green; b1[k]:= blue; map[k]:= minj; END;
		Pictures.SetColor(pict,minj,r0[minj],g0[minj],b0[minj]);
		RETURN(minj);
	ELSE
		Pictures.SetColor(pict,i,red*delta,green*delta,blue*delta);
		RETURN(i);
	END;
END ScanColor;

PROCEDURE LoadPPM(VAR R: Rider; transparentCol: INTEGER; colorConversion: BOOLEAN; pict: Pictures.Picture);
VAR
	p,pos: LONGINT;
	i,w,h,x,y,v0,v1,v2: INTEGER;
	c,red,green,blue: CHAR;
	eol: BOOLEAN;

	PROCEDURE LogMono();
	BEGIN
		Out.String("Portable Bitmap ");
		Out.Int(w,0); Out.Char("*"); Out.Int(h,0); Out.Ln();
	END LogMono;

	PROCEDURE LogGrayScale();
	BEGIN
		Out.String("Portable Graymap ");
		Out.Int(w,0); Out.Char("*"); Out.Int(h,0);
		Out.String(", "); Out.Int(p,0); Out.String(" grayscales."); Out.Ln();
	END LogGrayScale;

	PROCEDURE LogColor();
	BEGIN
		Out.String("Portable Pixmap ");
		Out.Int(w,0); Out.Char("*"); Out.Int(h,0);
		Out.String(", "); Out.Int(p,0); Out.String(" colorscales."); Out.Ln();
	END LogColor;

	PROCEDURE GetDepth();
	BEGIN
		p:= Value(R);
		IF (p > depth) THEN p:= depth; END; delta:= SHORT(depth DIV p);
		IF colorConversion THEN
			FOR v0:= 0 TO SHORT(depth) DO
				Display.GetColor(v0,r0[v0],g0[v0],b0[v0]); map[v0]:= -1;
			END;
		END;
	END GetDepth;

BEGIN
	pos:= R.Pos(R);
	IF MagicNumber(R) THEN
		IF ~credit THEN
			Out.String("Portable Picture File Format Release 4.1"); Out.Ln();
			Out.String("(c) SUN Microsystems"); Out.Ln();
			credit:= TRUE;
		END;
		w:= Value(R); h:= Value(R);
		Pictures.Create(pict,w,h,Pictures.colorD);
		IF (pict.depth = 0) THEN
			Out.String("not enough memory"); Out.Ln();
		ELSIF (mode = PlainGray) THEN	(* plain graymap *)
			GetDepth(); LogGrayScale(); ScanGrayMap(pict,p,colorConversion);
			y:= h-1; INC(p);
			WHILE ~R.eof & (y >= 0) DO
				x:= 0;
				WHILE ~R.eof & (x < w) DO
					v0:= Value(R);
					Pictures.Dot(pict,v0,x,y,Display.replace);
					INC(x);
				END;
				WHILE (x < w) DO
					Pictures.Dot(pict,transparentCol,x,y,Display.replace);
					INC(x);
				END;
				DEC(y);
			END;
			WHILE (y >= 0) DO
				FOR x:= 0 TO w-1 DO
					Pictures.Dot(pict,transparentCol,x,y,Display.replace);
				END;
				INC(y);
			END;	(* PlainGray *)
		ELSIF (mode = PlainColor) THEN	(* plain pixmap *)
			GetDepth(); LogColor(); i:= 0; y:= h-1; INC(p);
			WHILE ~R.eof & (y >= 0) DO
				x:= 0;
				WHILE ~R.eof & (x < w) DO
					v0:= Value(R); v1:= Value(R); v2:= Value(R);
					v0:= ScanColor(pict,i,v0,v1,v2,colorConversion);
					Pictures.Dot(pict,map[v0 MOD p],x,y,Display.replace);
					INC(x);
				END;
				WHILE (x < w) DO
					Pictures.Dot(pict,map[transparentCol MOD p],x,y,Display.replace);
					INC(x);
				END;
				DEC(y);
			END;
			WHILE (y >= 0) DO
				FOR x:= 0 TO w-1 DO
					Pictures.Dot(pict,map[transparentCol MOD p],x,y,Display.replace);
				END;
				INC(y);
			END;	(* PlainColor *)
		ELSIF (mode = Bitmap) THEN	(* raw bitmap *)
			LogMono(); y:= h;
			WHILE (y > 0) DO
				x:= 0; eol:= FALSE;
				WHILE ~eol DO
					R.Read(R,c); i:= 7;
					WHILE ~eol & (i >= 0) DO
						IF BIT.CBIT(c,SHORT(i)) THEN v0:= Display.BG; ELSE v0:= Display.FG; END;
						Pictures.Dot(pict,v0,x,y-1,Display.replace);
						IF (x < w-1) THEN INC(x); DEC(i); ELSE DEC(y); eol:= TRUE; END;
					END;
				END;
			END;	(* Bitmap *)
		ELSIF (mode = RawbitsGray) THEN	(* raw graymap *)
			GetDepth(); LogGrayScale(); ScanGrayMap(pict,p,colorConversion);
			FOR y:= h-1 TO 0 BY -1 DO
				FOR x:= 0 TO w-1 DO
					R.Read(R,c);
					Pictures.Dot(pict,map[ORD(c)],x,y,Display.replace);
				END;
			END;	(* RawbitsGray *)
		ELSIF (mode = RawbitsColor) THEN	(* raw pixmap *)
			GetDepth(); LogColor(); i:= 0;
			FOR y:= h-1 TO 0 BY -1 DO
				FOR x:= 0 TO w-1 DO
					R.Read(R,red); R.Read(R,green); R.Read(R,blue);
					v0:= ScanColor(pict,i,ORD(red),ORD(green),ORD(blue),colorConversion);
					Pictures.Dot(pict,v0,x,y,Display.replace);
				END;
			END;
		END;	(* RawbitsColor *)
	ELSE
		R.Set(R,pos);
	END;
END LoadPPM;

PROCEDURE Handle*(obj: Objects.Object; VAR msg: Objects.ObjMsg);
VAR
	R: Rider;
	pos: LONGINT;
BEGIN
	WITH obj: Pictures.Picture DO
		IF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO 
				IF (msg.id = Objects.get) & (msg.name = "Gen") THEN 
					msg.class:= Objects.String; COPY("PGM.NewPicture",msg.s); msg.res:=0 
				END;
			END;
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF (msg.id = Objects.load) THEN
					pos:= Files.Pos(msg.R); OpenRider(msg.R,R,pos);
					LoadPPM(R,14,TRUE,obj); msg.len:= R.Pos(R) - pos;
				ELSE
					Pictures.Handle(obj,msg)
				END;
			END;
		ELSE 
			Pictures.Handle(obj, msg)
		END;
	END;
END Handle;

(** Called from Pictures.Open to try and load an PPM pixmap, a PGM graymap or a PBM bitmap. The picture descriptor
is pre-allocated by Pictures in Objects.NewObj. InitPicture overwrites the handler of the picture with a new handler that
will load the PPM/PGM/PBM Picture when a FileMsg is received (variant load). Supported are Files either stored as an
Oberon Text or imported from DOS (CR+LF) or UNIX (LF) *)
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
	credit:= FALSE; depth:= ASH(1, Display.Depth(0)) - 1;
END PPM.
