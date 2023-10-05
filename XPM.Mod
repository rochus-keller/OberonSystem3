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

MODULE XPM;	(** portable *)	(** by W. Ibl *)
(** The X PixMap to Oberon Picture Format *)
(*
	May '97	first release
*)
IMPORT ColorModels,Display,Files,In,Objects,Out,Pictures,
			  Strings,Texts;

CONST
	Logo = "/* XPM */";	(* Magic String for Xpm *)
	None = "None";	(* symbolic name for the mask color *)
	ColorVisual = "c";	(* context supported with this module *)
	CR = Strings.CR;
	LF = Strings.LF;
	Tab = Strings.Tab;
	QT = 22X;
TYPE
	(* Combined Rider to parse through Xpm Files either stored as an
	Oberon Text or imported from DOS (CR+LF) or UNIX (LF) *)
	Rider = RECORD
		rider: Files.Rider;
		reader: Texts.Reader;
		text: Texts.Text;	(* needed for Set *)
		ofs: LONGINT;	(* needed for Pos - Position, where text starts in file *)
		str,eof: BOOLEAN;	(* str is for text parsing, eof is copied from rider.eof or reader.eot *)
		Read: PROCEDURE(VAR R: Rider; VAR c: CHAR);	(* read a byte *)
		Pos: PROCEDURE(VAR R: Rider): LONGINT;	(* get current file position *)
		Set: PROCEDURE(VAR R: Rider; pos: LONGINT);	(* seek to given file position *)
	END;

	(* User-defined color entry *)
	ColorEntry = POINTER TO ColorEntryDesc;
	ColorEntryDesc = RECORD
		name: Objects.Name;
		r,g,b: REAL;
		next: ColorEntry;
	END;

VAR
	colorEntry: ColorEntry;
	colorMap: ARRAY 256 OF INTEGER;
	charMap: POINTER TO ARRAY OF CHAR;
	xpmLogo,noColor: ARRAY 10 OF CHAR;
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

PROCEDURE FindUserColor(s: ARRAY OF CHAR): ColorEntry;
	(* search for an entry named s in the list of user-defined colors *)
VAR
	entry: ColorEntry;
BEGIN
	entry:= colorEntry;
	WHILE (entry # NIL) & ~Strings.CAPCompare(entry.name,s) DO entry:= entry.next; END;
	RETURN(entry);
END FindUserColor;

PROCEDURE GetColorEntry(s: ARRAY OF CHAR; VAR r,g,b: REAL; VAR ok: BOOLEAN);
	(* find a color specification in the list of user-defined colors/ColorModels list *)
VAR
	entry: ColorEntry;
BEGIN
	entry:= FindUserColor(s);
	IF (entry # NIL) THEN
		ok:= TRUE; r:= entry.r; g:= entry.g; b:= entry.b;
	ELSE
		ColorModels.StrToRGB(s,r,g,b,ok);
	END;
END GetColorEntry;

PROCEDURE OpenRider(VAR FR: Files.Rider; VAR R: Rider; pos: LONGINT);
	(* initialize a Rider. Supported are Oberon Texts and DOS/UNIX Files *)
VAR
	c: CHAR;
	len: LONGINT;
BEGIN
	Files.Read(FR,c);
	IF (c = Texts.TextBlockId) THEN
		NEW(R.text); Texts.Load(R.text,Files.Base(FR),pos+1,len);
		Texts.OpenReader(R.reader,R.text,0);
		R.ofs:= pos; R.str:= FALSE; R.eof:= R.reader.eot;
		R.Read:= ReadText; R.Pos:= PosText; R.Set:= SetText;
	ELSE
		Files.Set(R.rider,Files.Base(FR),pos); R.str:= FALSE; R.eof:= R.rider.eof;
		R.Read:= ReadFile; R.Pos:= PosFile; R.Set:= SetFile;
	END;
END OpenRider;

PROCEDURE MagicString(VAR R: Rider): BOOLEAN;
	(* check for the magic string *)
VAR
	c: CHAR;
	i: INTEGER;
BEGIN
	i:= 0;
	REPEAT R.Read(R,c); UNTIL R.eof OR ((c # CR) & (c # LF));
	WHILE ~R.eof & (xpmLogo[i] # 0X) & (c = xpmLogo[i]) DO
		R.Read(R,c); INC(i);
	END;
	REPEAT R.Read(R,c); UNTIL R.eof OR ((c # CR) & (c # LF));
	R.Set(R,R.Pos(R)-1);
	RETURN(xpmLogo[i] = 0X);
END MagicString;

PROCEDURE ScanChar(VAR R: Rider): CHAR;
	(* Read a char from a Xpm File. Necessary C Syntax elements are mentioned *)
VAR
	c: CHAR;
BEGIN
	REPEAT R.Read(R,c); UNTIL R.eof OR ((c # CR) & (c # LF));
	IF (c = QT) THEN
		R.str:= ~R.str; c:= ScanChar(R);
	ELSIF ~R.str THEN
		WHILE (c = "/") DO
			R.Read(R,c);
			IF (c # "*") THEN
				R.Set(R,R.Pos(R)-1); RETURN("/");
			ELSE
				WHILE ~R.eof & (c # "/") DO
					WHILE ~R.eof & (c # "*") DO R.Read(R,c); END;
					R.Read(R,c);
				END;
				REPEAT R.Read(R,c); UNTIL R.eof OR ((c # CR) & (c # LF));
			END;
		END;
		IF (c = QT) THEN R.str:= ~R.str; c:= ScanChar(R); END;
	END;
	RETURN(c);
END ScanChar;

PROCEDURE XpmName(VAR R: Rider; VAR name: ARRAY OF CHAR);
	(* Read the Pixmap's internal name *)
VAR
	c: CHAR;
	i: INTEGER;
BEGIN
	i:= 0;
	WHILE ~R.eof & (ScanChar(R) # "*") DO END;
	REPEAT c:= ScanChar(R); UNTIL R.eof OR (c # " ");
	REPEAT
		name[i]:= c; c:= ScanChar(R); INC(i);
	UNTIL R.eof OR (c = " ") OR (c = "[") OR (i = LEN(name));
	name[i]:= 0X;
END XpmName;

PROCEDURE XpmAttr(VAR R: Rider; VAR w,h,c,p: INTEGER);
	(* Read the Pixmap's attributes: width, height, color, chars/pixel *)
VAR
	ch: CHAR;

	PROCEDURE ReadNum(): INTEGER;
	VAR
		i: LONGINT;
		s: ARRAY 64 OF CHAR;
	BEGIN
		i:= 0; ch:= ScanChar(R);
		WHILE ~R.eof & (ch = " ") DO ch:= ScanChar(R); END;
		REPEAT
			s[i]:= ch; INC(i); ch:= ScanChar(R);
		UNTIL R.eof OR (ch = " ") OR (ch = ",");
		s[i]:= 0X; Strings.StrToInt(s,i);
		RETURN(SHORT(i));
	END ReadNum;

BEGIN
	REPEAT ch:= ScanChar(R); UNTIL R.eof OR (ch = "{");
	w:= ReadNum(); h:= ReadNum();
	c:= ReadNum(); p:= ReadNum();
	WHILE ~R.eof & (ch # ",") DO ch:= ScanChar(R); END;
END XpmAttr;

PROCEDURE XpmColor(VAR R: Rider; pict: Pictures.Picture; nrColor,pixChr,traCol: INTEGER; conversion: BOOLEAN);
	(* Read the Pixmap's color entries. Only the color entry (specification 'c') is supported.
	entries starting with '#' are treated as a X color definition, % (HSV) is not supported and
	all others are treated as symbolic colors. The color conversion part is copied from BMP.Mod *)
VAR
	r,g,b,i,j,k: INTEGER;
	x0,x1,x2: REAL;
	C: LONGINT;
	ok: BOOLEAN;
	ch,key,spec: CHAR;
	cval: ARRAY 60 OF CHAR;

	PROCEDURE Value(col: ARRAY OF CHAR; pos,len: INTEGER): REAL;
	VAR
		i: INTEGER;
		v,w: LONGINT;
	BEGIN
		v:= 0; w:= 0;
		FOR i:= 0 TO len-1 DO
			v:= v * 16; w:= (w * 16) + 15;
			IF Strings.IsDigit(col[pos+i]) THEN
				v:= v + ORD(col[pos+i]) - ORD("0");
			ELSE
				v:= v + 10 + ORD(CAP(col[pos+i])) - ORD("A");
			END;
		END;
		RETURN(v/w);
	END Value;

BEGIN
	C:= ASH(1,Display.Depth(0))-1;
	IF (nrColor > C) THEN nrColor:= SHORT(C); ELSE DEC(nrColor); END;
	FOR i:= 0 TO nrColor DO
		WHILE ~R.str DO charMap[i*pixChr]:= ScanChar(R); END;
		FOR j:= 1 TO pixChr-1 DO charMap[(i*pixChr)+j]:= ScanChar(R); END;
		ch:= 0X;
		(* ColorVisual is coded as c colorsymbol or c #rgb or c %hsv *)
		WHILE (ch # " ") & (ch # Tab) DO
			REPEAT
				REPEAT key:= ScanChar(R); UNTIL (key # " ") & (key # Tab);
			UNTIL (key = ColorVisual);
			ch:= ScanChar(R);
		END;
		REPEAT spec:= ScanChar(R); UNTIL (spec # " ") & (spec # Tab);
		ok:= TRUE; j:= 0;
		IF (spec = "#") OR (spec = "%") THEN	(* # = RGB, % = HSV *)
			REPEAT
				ch:= ScanChar(R); cval[j]:= ch; INC(j);
			UNTIL ~Strings.IsHexDigit(ch);
			WHILE (ch # ",") DO ch:= ScanChar(R) END;
			k:= (j DIV 3);
			x0:= Value(cval,0,k); x1:= Value(cval,k,k); x2:= Value(cval,2*k,k);
		ELSE	(* symbolic color *)
			cval[j]:= spec;
			REPEAT
				INC(j); ch:= ScanChar(R); cval[j]:= ch;
			UNTIL ~Strings.IsDigit(ch) & ~Strings.IsAlpha(ch);
			WHILE R.str DO ch:= ScanChar(R) END;
			cval[j]:= 0X;
			IF Strings.CAPCompare(cval,noColor) THEN
				ok:= FALSE; colorMap[i]:= traCol;
			ELSE
				GetColorEntry(cval,x0,x1,x2,ok);
				IF ~ok THEN
					Out.String("color ");
					Out.Char(QT); Out.String(cval); Out.Char(QT);
					Out.String(" is unknown."); Out.Ln();
					x0:= 1.0; x1:= 1.0; x2:= 1.0;
				END;
			END;
		END;
		IF ok THEN
			IF conversion THEN
				IF (spec = "%") THEN ColorModels.HSVToRGB(x0*360,x1,x2,x0,x1,x2); END;
				ColorModels.RGBToPalette(x0,x1,x2,j,r,g,b,(i = 0));
			ELSE
				j:= i; ColorModels.RGBToColor(x0,x1,x2,r,g,b);
			END;
			Pictures.SetColor(pict,j,r,g,b);
			colorMap[i]:= j;
		END;
	END;
	charMap[i*pixChr]:= 0X;
END XpmColor;

PROCEDURE XpmLine(VAR R: Rider; y,w,cpp: INTEGER; pict: Pictures.Picture);
	(* Read a Xpm Scan Line and set the pictures pixels according to the color map *)
VAR
	pat: ARRAY 16 OF CHAR;
	i,j: INTEGER;
	k: LONGINT;
	c: CHAR;
BEGIN 
	FOR i:= 0 TO w-1 DO
		FOR j:= 0 TO cpp-1 DO REPEAT pat[j]:= ScanChar(R); UNTIL R.str; END;
		k:= -1; pat[j]:= 0X;
		REPEAT
			INC(k); Strings.Search(pat,charMap^,k);
		UNTIL (k <= 0) OR (k MOD cpp = 0);
		IF (k > 0) THEN k:= k DIV cpp; END;
		Pictures.Dot(pict,colorMap[k],i,y,Display.replace);
	END;
	REPEAT c:= ScanChar(R); UNTIL R.eof OR (c = ",") OR (c = "}");
END XpmLine;

PROCEDURE LoadXPM(VAR R: Rider; transparentCol: INTEGER; colorConversion: BOOLEAN; pict: Pictures.Picture);
VAR
	pos: LONGINT;
	w,h,col,cpp,y: INTEGER;
	name: ARRAY 60 OF CHAR;
BEGIN
	pos:= R.Pos(R);
	IF MagicString(R) THEN
		IF ~credit THEN	(* give a credit to the inventor *)
			Out.String("X PixMap Format, by Arnaud Le Hors"); Out.Ln();
			Out.String("(c) BULL 1989-95"); Out.Ln(); credit:= TRUE;
		END;
		XpmName(R,name); XpmAttr(R,w,h,col,cpp);
		Out.String("X PixMap ");
		Out.Char(22X); Out.String(name); Out.Char(22X); Out.Char(" ");
		Out.Int(w,0); Out.Char("*"); Out.Int(h,0);
		Out.String(", "); Out.Int(col,0); Out.String(" colors."); Out.Ln();
		Pictures.Create(pict,w,h,Pictures.colorD);
		IF (pict.depth = 0) THEN
			Out.String("not enough memory"); Out.Ln();
		ELSE
			NEW(charMap,col*cpp+1); XpmColor(R,pict,col,cpp,transparentCol,colorConversion);
		END;
		FOR y:= h-1 TO 0 BY -1 DO XpmLine(R,y,w,cpp,pict); END;
	ELSE
		R.Set(R,pos);
	END;
END LoadXPM;

PROCEDURE Handle*(obj: Objects.Object; VAR msg: Objects.ObjMsg);
VAR
	R: Rider;
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
					pos:= Files.Pos(msg.R); OpenRider(msg.R,R,pos);
					LoadXPM(R,14,TRUE,obj); msg.len:= R.Pos(R) - pos;
				ELSE
					Pictures.Handle(obj,msg)
				END;
			END;
		ELSE 
			Pictures.Handle(obj, msg)
		END;
	END;
END Handle;

(** Called from Pictures.Open to try and load an XPM pixmap. The picture descriptor is pre-allocated by Pictures in
Objects.NewObj. InitPicture overwrites the handler of the picture with a new handler that will load the XPM
Picture when a FileMsg is received (variant load). Supported are Files either stored as an Oberon Text or imported
from DOS (CR+LF) or UNIX (LF) *)
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

(** Define a new color. Use this, if a certain color name is undefined when loading a XPM picture.
Syntax is: XPM.DefineColor color red green blue~
color is a colorname, red, green and blue are REAL values between 0.0 and 1.0 *)
PROCEDURE DefineColors*;
VAR
	entry: ColorEntry;
	col: Objects.Name;
	r,g,b: REAL;

	PROCEDURE Valid(x: REAL): BOOLEAN;
	BEGIN
		RETURN((x >= 0.0) & (x <= 1.0));
	END Valid;

BEGIN
	Out.String("XPM.DefineColors"); Out.Ln(); In.Open();
	WHILE In.Done DO
		In.String(col);
		IF In.Done THEN In.Real(r); END;
		IF In.Done THEN In.Real(g); END;
		IF In.Done THEN In.Real(b); END;
		IF In.Done & Valid(r) & Valid(g) & Valid(b) THEN
			entry:= FindUserColor(col);
			IF (entry = NIL) THEN
				NEW(entry); COPY(col,entry.name);
				entry.next:= colorEntry; colorEntry:= entry;
			END;
			entry.r:= r; entry.g:= g; entry.b:= b;
			Out.String(col); Out.String(" defined"); Out.Ln();
		END;
	END;
END DefineColors;

(** Copy a color. Use this, if a certain color name is undefined when loading a XPM picture.
Syntax is XPM.CopyColor from => to~.
from is the source color specification and to is the target color specification *)
PROCEDURE CopyColors*;
VAR
	entry: ColorEntry;
	col0,col1: Objects.Name;
	r,g,b: REAL;
	sep: CHAR;
	ok: BOOLEAN;
BEGIN
	Out.String("XPM.CopyColors"); Out.Ln(); In.Open(); 
	WHILE In.Done DO
		In.String(col0);
		IF In.Done THEN  REPEAT In.Char(sep); UNTIL ~In.Done OR (sep # " "); END;
		IF In.Done & (sep = "=") THEN In.Char(sep); ELSE In.Done:= FALSE; END;
		IF In.Done & (sep = ">") THEN In.String(col1); ELSE In.Done:= FALSE; END;
		IF In.Done THEN
			GetColorEntry(col0,r,g,b,ok);
			IF ok THEN
				entry:= FindUserColor(col1);
				IF (entry = NIL) THEN
					NEW(entry); COPY(col1,entry.name);
					entry.next:= colorEntry; colorEntry:= entry;
				END;
				entry.r:= r; entry.g:= g; entry.b:= b;
				Out.String(col0); Out.String(" => "); Out.String(col1); Out.String(" copying"); Out.Ln();
			ELSE
				Out.String("color ");
				Out.Char(QT); Out.String(col0); Out.Char(QT);
				Out.String(" is unknown."); Out.Ln();
			END;
		END;
	END;
END CopyColors;

BEGIN
	COPY(Logo,xpmLogo); COPY(None,noColor);
	colorEntry:= NIL; credit:= FALSE;
END XPM.

the american-style greyscales
XPM.CopyColors
Grey0 => gray0	Grey1 => gray1	Grey2 => gray2
Grey3 => gray3	Grey4 => gray4	Grey5 => gray5
Grey6 => gray6	Grey7 => gray7	Grey8 => gray8
Grey9 => gray9	Grey10 => gray10	Grey11 => gray11
Grey12 => gray12	Grey13 => gray13	Grey14 => gray14
Grey15 => gray15	Grey16 => gray16	Grey17 => gray17
Grey18 => gray18	Grey19 => gray19	Grey20 => gray20
Grey21 => gray21	Grey22 => gray22	Grey23 => gray23
Grey24 => gray24	Grey25 => gray25	Grey26 => gray26
Grey27 => gray27	Grey28 => gray28	Grey29 => gray29
Grey30 => gray30	Grey31 => gray31	Grey32 => gray32
Grey33 => gray33	Grey34 => gray34	Grey35 => gray35
Grey36 => gray36	Grey37 => gray37	Grey38 => gray38
Grey39 => gray39	Grey40 => gray40	Grey41 => gray41
Grey42 => gray42	Grey43 => gray43	Grey44 => gray44
Grey45 => gray45	Grey46 => gray46	Grey47 => gray47
Grey48 => gray48	Grey49 => gray49	Grey50 => gray50
Grey51 => gray51	Grey52 => gray52	Grey53 => gray53
Grey54 => gray54	Grey55 => gray55	Grey56 => gray56
Grey57 => gray57	Grey58 => gray58	Grey59 => gray59
Grey60 => gray60	Grey61 => gray61	Grey62 => gray62
Grey63 => gray63	Grey64 => gray64	Grey65 => gray65
Grey66 => gray66	Grey67 => gray67	Grey68 => gray68
Grey69 => gray69	Grey70 => gray70	Grey71 => gray71
Grey72 => gray72	Grey73 => gray73	Grey74 => gray74
Grey75 => gray75	Grey76 => gray76	Grey77 => gray77
Grey78 => gray78	Grey79 => gray79	Grey80 => gray80
Grey81 => gray81	Grey82 => gray82	Grey83 => gray83
Grey84 => gray84	Grey85 => gray85	Grey86 => gray86
Grey87 => gray87	Grey88 => gray88	Grey89 => gray89
Grey90 => gray90	Grey91 => gray91	Grey92 => gray92
Grey93 => gray93	Grey94 => gray94	Grey95 => gray95
Grey96 => gray96	Grey97 => gray97	Grey98 => gray98
Grey99 => gray99	Grey100 => gray100~
