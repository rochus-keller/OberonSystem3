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

MODULE RX;	(** portable *)	(* Andreas Margelisch, 1990 *)

IMPORT RXA, Oberon, Objects, Out, TextGadgets0, Texts, Display;

CONST 
	blank = 32; (* blank *)
	tab = 9; (* tab *)
	cr = 13; (* carriage return *)
	dq = 34; (* double quotes *)
			
	noerror = 0;
	strtoolong = -1;
	linetoolong = -2;
	
	(* nofline = 32000; *) nofline = 10000;
	(* nofrepl = 32000; *) nofrepl = 10000;
			
VAR 
	w: Texts.Writer;
	sbeg, send, errorvar : INTEGER;
	sdfa : RXA.DFA;
	stext : Texts.Text;
	stextpos, slinelen : LONGINT;
	sline : ARRAY(nofline+1) OF CHAR;
	sreplaced, casesens, replset : BOOLEAN;
	replstr : ARRAY(nofrepl+1) OF CHAR;
	ch : CHAR;

PROCEDURE Focus():TextGadgets0.Frame;
	VAR CM: Oberon.CaretMsg;
BEGIN
	CM.id := Oberon.get; Display.Broadcast(CM);
	IF (CM.car # NIL) & (CM.car IS TextGadgets0.Frame) THEN RETURN CM.car(TextGadgets0.Frame)
	ELSE RETURN NIL
	END;
END Focus;

PROCEDURE MyCAP( ch : CHAR ) : CHAR;
BEGIN IF ("a" <= ch ) & ( ch <= "z" ) THEN RETURN CAP( ch ) ELSE RETURN ch END;
END MyCAP;

PROCEDURE ThisFrame(X, Y: INTEGER; VAR F: Display.Frame);
	VAR M: Display.LocateMsg;
BEGIN	M.X := X; M.Y := Y; M.F := NIL; M.loc := NIL; Display.Broadcast(M); F := M.loc
END ThisFrame;

PROCEDURE GetText(  VAR text : Texts.Text; VAR name : ARRAY OF CHAR; VAR s : Texts.Scanner );
	VAR
		 F: Display.Frame;
		 M: Objects.LinkMsg;
BEGIN
	Texts.Scan( s );
	text := NIL; name[0] := 0X;
	IF s.class = Texts.Name THEN
		NEW( text ); Texts.Open( text, s.s ); COPY( s.s, name );
	ELSIF ( s.class = Texts.Char ) & ( s.c = "*" ) THEN
		text := NIL; ThisFrame(Oberon.Pointer.X, Oberon.Pointer.Y, F);
		IF F # NIL THEN
			M.id := Objects.get; M.name := "Model"; M.obj := NIL; M.res := -1; F.handle(F, M);
			IF (M.obj # NIL) & (M.obj IS Texts.Text) THEN text := M.obj(Texts.Text) END
		END;
	END; 
END GetText;

PROCEDURE GetOption( VAR reader : Texts.Reader; VAR opti : BOOLEAN );
BEGIN
	casesens := TRUE;
	opti := FALSE;
	Texts.Read( reader, ch );	
	WHILE ( ORD(ch) = tab ) OR ( ORD(ch) = blank ) OR ( ORD(ch) = cr ) DO Texts.Read( reader, ch ) END;
	IF  ch = Oberon.OptionChar THEN
		REPEAT
			Texts.Read( reader, ch );
			CASE ch OF
				"c"  : casesens := ~casesens |
				"i" : opti := ~opti |
				"~" : RETURN;
			ELSE
			END; 
		UNTIL ( ORD(ch) = blank ) OR ( ORD(ch) = cr ) OR ( ORD(ch) =tab );
	END; 
END GetOption;

PROCEDURE GetStr( VAR reader : Texts.Reader; VAR str : ARRAY OF CHAR );
	VAR strfull, inquotes, first : BOOLEAN;
		strind : INTEGER;
		
	PROCEDURE Append( chr : CHAR );
	BEGIN
		IF strind < LEN( str ) THEN str[strind] := chr; INC(strind) ELSE strfull := TRUE END;
	END Append;
	
BEGIN
	strfull := FALSE; strind := 0; inquotes := FALSE; first := FALSE;
	WHILE ( ORD(ch) = tab ) OR ( ORD(ch) = cr ) OR ( ORD(ch) = blank ) DO Texts.Read( reader, ch ) END;
	WHILE ( ~reader.eot ) & ( ORD(ch) # cr ) DO
		IF ~first & ( ORD(ch) = dq ) THEN inquotes := ~inquotes; first := inquotes; Append( ch );
		ELSE
			IF inquotes & ~casesens THEN Append( MyCAP( ch ) ) ELSE Append( ch ) END;
			first := FALSE;
		END;
		Texts.Read( reader, ch );
	END;
	Append( CHR(0) );
	IF strfull THEN errorvar := strtoolong END;
END GetStr;

PROCEDURE RXAErrorHandler( error, pos : INTEGER );
BEGIN
	CASE error OF
		RXA.noposfree : Texts.WriteString( w,"regular expression too long ( position table full )") |
		RXA.nostatesfree : Texts.WriteString( w,"regular expression too long ( state table full  )") |
		RXA.nometaexp : Texts.WriteString( w,"no metasymbol at pos "); Texts.WriteInt( w, pos, 3 );
								  Texts.WriteString( w," expected ") |
		RXA.chrleft : Texts.WriteString( w,"regular expression not correct ( ')', ']' or '}' on a wrong place )") |
		RXA.wsubexpr : Texts.WriteString( w,"subexpression, String or shorthands 't' or 'c' at pos "); Texts.WriteInt( w,pos, 3);
								   Texts.WriteString( w," expected ") |
		RXA.subexprrest : Texts.WriteString( w,"marked subexpression at pos "); Texts.WriteInt( w,pos, 3); 
									  Texts.WriteString( w," shouldn't be enclosed by '{  }'  ") |
		RXA.wshorthand : Texts.WriteString( w,"wrong shorthand identifier at pos "); Texts.WriteInt( w,pos, 3); Texts.WriteLn( w );
									  Texts.WriteString( w,"permitted are : A, a, b, c, d, h, i, l, o, t, w ") |
		RXA.nodfa : Texts.WriteString( w,"replace faild : automata is missing") |
		RXA.repllinefull : Texts.WriteString( w,"replace faild : replacestring is full ") |
		RXA.notnotexp : Texts.WriteString( w,"metasymbol or more than one literal in qutoes after notoperator") |
		RXA.linecopofl : Texts.WriteString( w, "array linecop in RXA.Replace is too small");
	ELSE
		Texts.Write(w, "'"); Texts.Write(w, CHR(error)); Texts.Write(w, "'"); Texts.WriteString( w," at pos ");
		Texts.WriteInt( w,pos, 3); Texts.WriteString( w," expected ");
	END; 
	Texts.WriteLn( w );
	Texts.Append( Oberon.Log, w.buf);
END RXAErrorHandler;

PROCEDURE RXErrorHandler( text : ARRAY OF CHAR );
BEGIN
	CASE errorvar OF
		strtoolong, linetoolong : Texts.WriteString( w, text ); Texts.WriteString( w," too long "); |
	ELSE
		Texts.WriteString( w, text );
	END; 
	Texts.WriteLn( w );
	Texts.Append( Oberon.Log, w.buf);
	errorvar := noerror;
END RXErrorHandler;

PROCEDURE ParseTexts( text : Texts.Text; name : ARRAY OF CHAR; dfa : RXA.DFA; opti : BOOLEAN );
	VAR 
		ch : CHAR;
		r : Texts.Reader;
		line, linec : ARRAY(nofline+1) OF CHAR;
		lineind, i, beg, end : INTEGER;
		wtext: Texts.Text;
		linefull : BOOLEAN;
		
	PROCEDURE Append( chr : CHAR );
	BEGIN
		IF lineind < LEN( line ) THEN line[lineind] := chr; INC(lineind) ELSE linefull := TRUE END; 
	END Append;
	
BEGIN
	NEW(wtext); Texts.Open(wtext, "");
	Oberon.OpenText("RX.Grep", wtext, Display.Width DIV 2, 200);
	Texts.OpenReader( r, text, 0 );
	WHILE ( ~ r.eot ) DO
		lineind := 0; linefull := FALSE;
		REPEAT
			Texts.Read( r, ch ); Append( ch );
		UNTIL  r.eot OR ( ch = CHR(cr) );
		Append( CHR(0) );
		IF linefull THEN
			RXErrorHandler( " ERROR : line is too long ");
		ELSE
			beg := 0;
			IF casesens THEN
				RXA.Search( dfa, line, beg, end );
			ELSE
				COPY( line, linec ); i := 0; ch := linec[0];
				WHILE ch # 0X DO linec[i] := MyCAP( ch ); INC(i); ch := linec[i] END;
				RXA.Search( dfa, linec, beg, end );
			END; 
			IF r.eot THEN DEC(lineind) END;
			IF ( ( end >= 0 ) & (~opti) ) OR ( ( end < 0 ) & opti ) THEN
				i := 0; WHILE i < lineind-1 DO Texts.Write(w, line[i] ); INC(i) END;
				Texts.Append( wtext, w.buf );
			END; 
		END; 
	END; 
END ParseTexts;


PROCEDURE Grep*;
	VAR 
		opti : BOOLEAN;
		rx : ARRAY(nofline+1) OF CHAR;
		error, erpos : INTEGER;
		dfa : RXA.DFA;
		s : Texts.Scanner;
		text : Texts.Text;
		name : ARRAY 32 OF CHAR;
BEGIN
	Texts.OpenScanner( s, Oberon.Par.text, Oberon.Par.pos );
	GetText( text, name, s );
	GetOption( s, opti );
	GetStr( s, rx );
	IF errorvar = noerror THEN
		RXA.New( rx, dfa, error, erpos );
		IF (error = RXA.noerror) & ( text # NIL ) THEN 
			ParseTexts( text, name, dfa, opti ) 
		ELSE 
			RXAErrorHandler( error, erpos )
		END;
	ELSE
		RXErrorHandler("regular expression");
	END; 
END Grep;

PROCEDURE SetSearch*;
	VAR 
		opti : BOOLEAN;
		rx : ARRAY(nofline+1) OF CHAR;
		error, erpos : INTEGER;
		r : Texts.Reader;
BEGIN
	Texts.OpenReader( r, Oberon.Par.text, Oberon.Par.pos );		
	GetOption( r, opti );
	GetStr( r, rx );
	IF errorvar = noerror THEN
		RXA.New( rx, sdfa, error, erpos );
		IF error # RXA.noerror THEN RXAErrorHandler( error, erpos ) END;
	ELSE
		RXErrorHandler("regular expression");
	END; 
	
(*	RXA.Dump( sdfa, w ); Texts.Append( Oberon.Log, w.buf ); *)
	
END SetSearch;

PROCEDURE SetReplace*;
	VAR r : Texts.Reader;
BEGIN
	replset := TRUE;
	Texts.OpenReader( r, Oberon.Par.text, Oberon.Par.pos );
	Texts.Read(r, ch);	(* << mmb *)
	GetStr( r, replstr );
	IF errorvar # noerror THEN RXErrorHandler("replace pattern"); END;
END SetReplace;
 
PROCEDURE SearchPattern( text : Texts.Text; textpos : LONGINT );
	VAR 
	r : Texts.Reader;
	beg, end, lineind : INTEGER;
	ch : CHAR;
	line : ARRAY(nofline+1) OF CHAR;
	linelen : LONGINT;
	linefull : BOOLEAN;
	
PROCEDURE Append( chr : CHAR );
BEGIN
	IF lineind < LEN( line ) THEN 
		IF ~casesens  THEN line[lineind] := MyCAP( chr ) ELSE line[lineind] := chr END;
		INC(lineind);
	ELSE
		linefull := TRUE;
	END; 
END Append;

BEGIN
	end := -1;
	Texts.OpenReader( r, text, textpos );
	WHILE  ( ~ r.eot ) & ( end < 0 ) DO
		lineind := 0; linefull := FALSE;
		textpos := Texts.Pos( r );
		REPEAT
			Texts.Read( r, ch );
			Append( ch );
		UNTIL r.eot OR ( ch = CHR(cr) );
		linelen := lineind;
		Append( CHR(0) );
		IF linefull THEN
			RXErrorHandler( " ERROR : line is too long ");
		ELSE
			beg := 0;
			RXA.Search( sdfa, line, beg, end ); 
		END; 
	END; 
	IF end >= 0 THEN
		stext := text; stextpos := textpos; slinelen := linelen; sbeg := beg; send := end; sreplaced := FALSE; COPY( line, sline );
		IF r.eot THEN DEC(slinelen) END
	ELSE
		stext := NIL
	END; 
END SearchPattern;


PROCEDURE Search*;
	VAR 
		frame : TextGadgets0.Frame;
		textpos : LONGINT;
BEGIN
	errorvar := noerror;
	frame := Focus();
	IF frame # NIL THEN
		textpos := frame.carpos.pos;
		SearchPattern( frame.text, textpos );
		IF ( ~sreplaced ) & ( frame.text = stext ) THEN
			Oberon.Defocus;
			TextGadgets0.Locate(frame, stextpos + send);
			TextGadgets0.SetSelection(frame, stextpos + sbeg, stextpos + send);
		ELSE 
			TextGadgets0.RemoveSelection(frame); TextGadgets0.RemoveCaret(frame)
		END
	END; 
END Search;

PROCEDURE Replace*;
	VAR 
		error, pos, i : INTEGER;
		frame : TextGadgets0.Frame;
		textpos : LONGINT;
BEGIN
	IF ( ~sreplaced ) & replset THEN
		frame := Focus();
		IF frame # NIL THEN
			IF  frame.carpos.pos = stextpos + send THEN
				RXA.Replace( sdfa, sline, replstr, sbeg, send, error, pos );
				sreplaced := error = RXA.noerror;
				IF sreplaced THEN
					Oberon.Defocus;
					Out.String("delete "); Out.Int(slinelen, 5); Out.String(" characters"); Out.Ln;
					Texts.Delete( frame.text, stextpos,  stextpos + slinelen);
					i := 0; WHILE( i < LEN( sline ) ) & ( sline[i] # 0X ) DO Texts.Write( w, sline[i] ); INC(i) END; 
					Texts.Insert( frame.text, stextpos, w.buf );
					textpos := stextpos + pos;
					SearchPattern( frame.text, textpos );
					IF ~sreplaced & (frame.text = stext) THEN
						TextGadgets0.Locate(frame, stextpos + send);
						TextGadgets0.SetSelection(frame, stextpos + sbeg, stextpos + send); 
					ELSE
						TextGadgets0.RemoveSelection(frame); TextGadgets0.RemoveCaret(frame)
					END;
				ELSE
					RXAErrorHandler( error, pos );
				END;
			END
		END; 
	END; 
END Replace;

PROCEDURE ReplaceAll*;
	VAR 
		frame : TextGadgets0.Frame;
		textpos : LONGINT;
		error, pos, i : INTEGER;
BEGIN
	errorvar := noerror;
	frame := Focus();
	IF ( frame # NIL ) & replset THEN
		textpos := frame.carpos.pos;
		Oberon.Defocus;
		LOOP
			SearchPattern( frame.text, textpos );
			IF ~sreplaced THEN
				RXA.Replace( sdfa, sline, replstr, sbeg, send, error, pos );
				IF error = RXA.noerror THEN
					sreplaced := TRUE;
					Texts.Delete( frame.text, stextpos,  stextpos + slinelen );
					i := 0; WHILE( i < LEN( sline ) ) & ( sline[i] # 0X ) DO Texts.Write( w, sline[i] ); INC(i) END; 
					Texts.Insert( frame.text, stextpos, w.buf );
					textpos := stextpos + pos;
				ELSE
					RXAErrorHandler( error, pos );
					RETURN
				END; 
			ELSE
				EXIT;
			END; 
		END
	END; 
END ReplaceAll;

BEGIN
	Texts.OpenWriter( w );
	errorvar := noerror;
	replset := FALSE;
	sreplaced := TRUE;
	sdfa := NIL;
END RX.