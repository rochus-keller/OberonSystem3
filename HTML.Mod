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

MODULE HTML;	(** portable *) (* jm 26.8.94 *)

IMPORT
	Files, Objects, Texts, Oberon, Fonts, Out;

CONST
(* possible values of the variable typ denoting the paragraph type *)
	para = 0;			(* Normal paragraph in xxx12.Scn.Fnt or xxx12i.Scn.Fnt *)
								(* Paragraphs are delimited by one or more empty lines *)
	title = 1;			 (* Title when first character is red *)
	heading = 2;	  (* Heading when in xxx12b.Scn.Fnt *)
	bullet = 3;		  (* Bullet when "*" is first character on a line *)
	line = 4;			 (* Horizontal ruler when "-" is first character on a line *)
	pre = 5;			 (* pre-formatted when in xxx10.Scn.Fnt *)

	tab = 09X;
	
	DocHeader = TRUE;	(* include HTML 2.0 document header comment *)
	BodyColor = FALSE;	(* set body color - Netscape-specific *)

VAR
	out: Files.Rider;
	italic: BOOLEAN;
	sep: CHAR;

PROCEDURE S(s: ARRAY OF CHAR);
VAR i: INTEGER;
BEGIN
	i := 0;
	WHILE s[i] # 0X DO Files.Write(out, s[i]); INC(i) END
END S;

PROCEDURE C(ch: CHAR); BEGIN Files.Write(out, ch) END C;

PROCEDURE L; BEGIN Files.Write(out, sep); END L;

(* Check if font matches type.  type = digit { digit } ("." | "b" | "i"). *)
PROCEDURE MatchFont(font: ARRAY OF CHAR;  type: ARRAY OF CHAR): BOOLEAN;
VAR i, j: LONGINT;
BEGIN
	i := 0;
	WHILE (font[i] # 0X) & ((font[i] < "0") OR (font[i] > "9")) DO	(* skip name *)
		INC(i)
	END;
	j := 0;
	WHILE (font[i] # 0X) & (font[i] >= "0") & (font[i] <= "9") & (font[i] = type[j]) DO
		INC(i);  INC(j)
	END;
	RETURN (font[i] = type[j])
END MatchFont;

(* Delimit a paragraph: begins at lastnl and ends at end *)
PROCEDURE GetPara(VAR R: Texts.Reader; VAR beg, end: LONGINT; VAR typ: SHORTINT);
VAR ch, firstch: CHAR; firstfnt: Objects.Library; firstcol: INTEGER; lastnl: LONGINT;
BEGIN
	beg := Texts.Pos(R); end := beg; lastnl := beg;
	
	(* skip empty lines *)
	Texts.Read(R, ch);
	WHILE ~R.eot & (ch <= " ") DO
		INC(beg);
		IF ch = 0DX THEN lastnl := beg END;
		Texts.Read(R, ch)
	END;
	
	IF ~R.eot THEN
		firstch := ch; firstfnt := R.lib; firstcol := R.col;
		LOOP
			WHILE ~R.eot & (ch # 0DX) DO Texts.Read(R, ch) END; (* read till first nl *)
			IF R.eot THEN EXIT END;
			IF ch = 0DX THEN
				end := Texts.Pos(R)-1;
				Texts.Read(R, ch);
				WHILE ~R.eot & (ch = " ") OR (ch = tab) DO Texts.Read(R, ch) END;
				IF ch = 0DX THEN EXIT END;
			END
		END;
		IF firstcol = 1 THEN (* red *) typ := title
		ELSIF MatchFont(firstfnt.name, "12b") THEN typ := heading
		ELSIF MatchFont(firstfnt.name, "10.") THEN typ := pre; beg := lastnl;
		ELSIF firstch = "*" THEN typ := bullet
		ELSIF firstch = "-" THEN typ := line
		ELSE typ := para
		END
	END
END GetPara;

PROCEDURE WriteStretch(T: Texts.Text; beg, end: LONGINT);
VAR R: Texts.Reader; ch: CHAR; lastlib: Objects.Library;
BEGIN
	IF end > beg THEN 
		Texts.OpenReader(R, T, beg);
		Texts.Read(R, ch); lastlib := R.lib;
		WHILE beg < end DO
			IF R.lib # lastlib THEN
				IF MatchFont(R.lib.name, "12i") THEN
					IF ~italic THEN S("<I>"); italic := TRUE END
				ELSE
					IF italic THEN S("</I>"); italic := FALSE END
				END;
				lastlib := R.lib
			END;
			IF ch = "ü" THEN S("&uuml;")
			ELSIF ch = "Ü" THEN S("&Uuml;")
			ELSIF ch = "ä" THEN S("&auml;")
			ELSIF ch = "Ä" THEN S("&Auml;")
			ELSIF ch = "ö" THEN S("&ouml;")
			ELSIF ch = "Ö" THEN S("&Ouml;")
			ELSIF ch = "é" THEN S("&eacute;")
			ELSIF ch = "è" THEN S("&egrave;")
			ELSIF ch = 0DX THEN C(" "); C(sep)
			ELSIF (ch >= " ") OR (ch = tab) OR (ch = "-") THEN
				C(ch)
			END;
			Texts.Read(R, ch);
			INC(beg)
		END
	END
END WriteStretch;

PROCEDURE WritePara(T: Texts.Text; beg, end: LONGINT);
VAR R: Texts.Reader; ch: CHAR; col: INTEGER;
	pos, lstart: LONGINT; anchor: ARRAY 512 OF CHAR; apos: INTEGER;
BEGIN col := -1; pos := beg; anchor := "";
	Texts.OpenReader(R, T, beg);
	Texts.Read(R, ch); 
	WHILE pos < end DO
		IF (R.col = 3) & (col # 3) THEN (* start link *)
			WriteStretch(T, beg, pos); beg := pos
		END;
		col := R.col;
		 
		IF (col = 3) & (ch = "{") THEN (* reading an anchor *)
			lstart := pos;
			INC(pos); Texts.Read(R, ch);
			apos := 0;
			WHILE ~R.eot & (apos < LEN(anchor)) & (ch # "}") DO
				anchor[apos] := ch; INC(apos);
				INC(pos);
				Texts.Read(R, ch)
			END;
			anchor[apos] := 0X;
			S("<A HREF="); C(22X); S(anchor); C(22X); C(">");
			WriteStretch(T, beg, lstart); beg := pos+1;
			S("</A>")
		ELSE INC(pos); Texts.Read(R, ch)
		END
	END;
	WriteStretch(T, beg, end)
END WritePara;

PROCEDURE GetPrefix(T: Texts.Text; VAR beg, end: LONGINT; VAR s: ARRAY OF CHAR);
VAR R: Texts.Reader; old: LONGINT; ch: CHAR; i: INTEGER;
BEGIN
	old := beg; i := 0;
	Texts.OpenReader(R, T, beg);
	Texts.Read(R, ch);
	WHILE ~R.eot & (ch # ":") & (beg < end) DO
		IF (ch > " ") & (i < LEN(s) - 1) THEN s[i] := ch; INC(i) END;
		INC(beg);
		Texts.Read(R, ch)
	END;
	IF ch = ":" THEN s[i] := 0X; INC(beg)
	ELSE s[0] := 0X; beg := old
	END
END GetPrefix;

PROCEDURE ConvertText(T: Texts.Text; start: LONGINT; VAR filename: ARRAY OF CHAR);
VAR R: Texts.Reader; beg, end, nbeg, nend: LONGINT; typ, ntyp: SHORTINT; body: BOOLEAN;

	PROCEDURE StartBody;
	BEGIN
		S("</HEAD>"); L;
		IF BodyColor THEN
			S("<BODY BGCOLOR="); C(22X); S("#FFFFFF"); C(22X); S(">"); L
		ELSE
			S("<BODY>"); L
		END;
		body := TRUE
	END StartBody;
	
BEGIN
	italic := FALSE; body := FALSE;
	Texts.OpenReader(R, T, start);
	GetPara(R, beg, end, typ);
	IF DocHeader THEN
		S("<!DOCTYPE HTML PUBLIC "); C(22X); S("-//IETF//DTD HTML 2.0//EN"); C(22X); S(">"); L
	END;
	S("<HTML>"); L;
	S("<HEAD>"); L;
	S("<TITLE>");
	IF typ = title THEN
		GetPrefix(T, beg, end, filename); (* Skip that file name, discarding it *)
		WritePara(T, beg, end);
		beg := end	(* title paragraph already written *)
	ELSE
		S("Untitled")
	END;
	S("</TITLE>"); L;
	WHILE ~R.eot DO
		IF ~body & (typ # title) THEN StartBody END; (* first non-title paragraph starts body *)
		GetPara(R, nbeg, nend, ntyp);
		IF body & (ntyp = title) THEN ntyp := para END; (* treat a title paragraph in body like normal *)
		IF typ = bullet THEN S("<LI>"); INC(beg)
		ELSIF typ = heading THEN S("<H2>")
		ELSE (* skip *)
		END;
		IF typ = line THEN S("<HR>") (* Horizontal Ruler *)
		(*ELSIF typ = title THEN*) (* skip *)
		ELSE
			WritePara(T, beg, end); (* write previous *)
			IF typ = pre THEN C(0DX) END
		END;
		IF typ = heading THEN S("</H2>") END;
		IF beg # end THEN L END;
		
		(* List *)
		IF (ntyp = bullet) & (typ # bullet) THEN (* open list *)
			S("<UL>"); L
		ELSIF (ntyp # bullet) & (typ = bullet) THEN (* close list *)
			S("</UL>"); L
		END;
		
		(* Pre-formatted text *)
		IF (ntyp = pre) & (typ # pre) THEN (* start pre-formatted text *)
			S("<PRE>")
		ELSIF (ntyp # pre) & (typ = pre) THEN
			S("</PRE>"); L
		END;
		
		(* Separate 2 consecutive "normal" paragraphs with a paragraph break, except two preformatteds *)
		IF (ntyp = para) & (typ = para) THEN S("<P>"); L END;
		
		end := nend; beg := nbeg; typ := ntyp
	END;
	IF ~body & (typ # title) THEN StartBody END;
	WritePara(T, beg, end); (* write previous *)
	IF (typ = bullet) THEN (* close list *)
		S("</UL>"); L
	END;
	IF (typ = pre) THEN
		S("</PRE>"); L
	END;
	S("</BODY>"); L;
	S("</HTML>"); L
END ConvertText;

(** Show a preview of the HTML text in a text viewer - Processes ONLY one text! *) 
PROCEDURE Show*;
VAR S: Texts.Scanner; T, t: Texts.Text; time, beg, end: LONGINT;
	filename: ARRAY 64 OF CHAR; f: Files.File;
BEGIN
	sep := 0DX;
	beg := 0;		(* Process from the beginning of the text. Modified if "@" used *)
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S); T := NIL;
	IF (S.class = Texts.Char) & (S.c = "*") THEN
		T := Oberon.MarkedText()
	ELSIF (S.class = Texts.Char) & (S.c = "^") THEN
		Oberon.GetSelection(T, beg, end, time);
		IF time >= 0 THEN
			Texts.OpenScanner(S, T, beg);
			Texts.Scan(S);
			IF (S.class = Texts.Name) THEN
				NEW(T); Texts.Open(T, S.s);
				IF T.len = 0 THEN T := NIL END
			END
		ELSE T := NIL
		END
	ELSIF (S.class = Texts.Char) & (S.c = "@") THEN
		Oberon.GetSelection(T, beg, end, time);
		IF time < 0 THEN T := NIL END
	END;
	IF T # NIL THEN
		f := Files.New("Temp.HTML.tmp");
		Files.Set(out, f, 0);
		ConvertText(T, beg, filename);
		Files.Register(f);
		NEW(t); Texts.Open(t, "Temp.HTML.tmp");
		Oberon.OpenText(filename, t, 400, 200)
	END
END Show;

PROCEDURE Compile*;
	VAR S: Texts.Scanner; T: Texts.Text; filename: ARRAY 64 OF CHAR; f: Files.File; beg, end, time: LONGINT;

	PROCEDURE CompileT();
		VAR R: Texts.Reader; beg, end: LONGINT; typ: SHORTINT;
				res, i: INTEGER; bak: ARRAY 64 OF CHAR;
	BEGIN
		IF T.len > 0 THEN
		(* Get the file name from the source text, at the beginning i.e. pos 0 *)
			Texts.OpenReader(R, T, 0);
			GetPara(R, beg, end, typ);
			IF typ = title THEN
				GetPrefix(T, beg, end, filename)
			END;
		(* *)
			IF filename # "" THEN
				Out.String(filename);
			(* Rename the file 'fileName.Bak' *)
				i := 0;
				WHILE filename[i] # 0X DO bak[i] := filename[i]; INC(i) END;
				bak[i] := "."; bak[i+1] := "B"; bak[i+2] := "a"; bak[i+3] := "k"; bak[i+4] := 0X;
				Files.Rename(filename, bak, res);
			(* *)
				f := Files.New(filename);
				Files.Set(out, f, 0);
				ConvertText(T, 0, filename);
				Files.Register(f);
				Out.Int(Files.Length(f), 10);
			ELSE Out.String("no destination file name in text")
			END
		END;
		Out.Ln
	END CompileT;
	
BEGIN
	sep := 0AX;
	Out.String("HTML.Compile"); Out.Ln;
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF (S.class = Texts.Char) & (S.c = "*") THEN
		T := Oberon.MarkedText();
		IF T # NIL THEN
			CompileT()
		END
	ELSE
		end := MAX(LONGINT) - 100;
		IF (S.class = Texts.Char) & (S.c = "^") THEN
			Oberon.GetSelection(T, beg, end, time);
			IF time >= 0 THEN Texts.OpenScanner(S, T, beg); Texts.Scan(S) END
		END;
		WHILE (S.class = Texts.Name) & (Texts.Pos(S) < end + S.len + 1) DO
			Out.String(S.s); Out.String(" => ");
			NEW(T); Texts.Open(T, S.s);
			CompileT();
			Texts.Scan(S)
		END
	END
END Compile;

END HTML.

HTML.Compile ^	HTML.Compile *

HTML.Show ^		HTML.Show *		HTML.Show @

HTML.Compile Native.Text ~
EditTools.OpenUnix Native.html
