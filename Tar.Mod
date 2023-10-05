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

MODULE Tar;	(** portable *)	(* Copyright (c) Jacques Supcik, 1995 / js 19.9.95, V4,  modified for S3 C.Hoffmann, 21.9.95 *)

	IMPORT Gadgets, Desktops, Display, Documents,  Texts, TextDocs, TextGadgets, Objects, Files, Out;

	CONST
		Menu = "Tar.Extract Tar.ExtractAll";
		
	TYPE
		Entry = POINTER TO EntryDesc;
		EntryDesc = RECORD
			name: ARRAY 256 OF CHAR;
			pos, size: LONGINT;
			next: Entry;
		END;
		
		Frame = POINTER TO FrameDesc;
		FrameDesc = RECORD (TextGadgets.FrameDesc)
			entries: Entry;
			file: Files.File;
		END;

	PROCEDURE ExtractFileName(VAR buf: ARRAY OF CHAR; VAR name: ARRAY OF CHAR);
		VAR i, j, k: INTEGER; ch: CHAR; lastDot: BOOLEAN;
	BEGIN
		i := 0; j := 345; lastDot := FALSE;
		WHILE buf[j] # 0X DO
			IF (buf[j] = "/") OR (buf[j] = "\") OR (buf[j] = ".") THEN ch := "." ELSE ch := buf[j] END;
			IF (i = 0) & (ch = ".") THEN (* Skip first characters *)	(* ####*)
			ELSIF lastDot & (ch = ".") THEN (* Skip multiple dots *)
			ELSE name[i] := ch; INC(i); lastDot := ch = ".";
			END;
			INC(j)
		END;
		IF i > 0 THEN name[i] := "."; INC(i) END;
		k := 0;
		WHILE (k < 100) & (buf[k] # 0X) DO
			IF (buf[k] = "/") OR (buf[k] = "\") OR (buf[k] = ".") THEN ch := "." ELSE ch := buf[k] END;
			IF (i = 0) & (ch = ".") THEN (* Skip first signs *)
			ELSIF lastDot & (ch = ".") THEN (* Skip multiple dots *)
			ELSE name[i] := ch; INC(i); lastDot := ch = ".";
			END;
			INC(k)
		END;
		name[i] := 0X;
	END ExtractFileName;
	
	PROCEDURE ExtractSize(VAR buf: ARRAY OF CHAR; VAR size: LONGINT);
		VAR i: INTEGER;
	BEGIN
		i := 124; size := 0;
		REPEAT
			IF ("0" <= buf[i]) & (buf[i] <= "9") THEN
				size := size*8 + ORD(buf[i]) - ORD("0")
			END;
			INC(i)
		UNTIL i = 136
	END ExtractSize;
	
	PROCEDURE ReadEntries(fileName: ARRAY OF CHAR; VAR F: Files.File; VAR entries: Entry);
		VAR R: Files.Rider; p: Entry; buf: ARRAY 512 OF CHAR; pos, size: LONGINT;
	BEGIN
		F := Files.Old(fileName);
		IF F = NIL THEN entries := NIL; RETURN END;
		
		pos := 0;
		LOOP
			Files.Set(R, F, pos); Files.ReadBytes (R, buf, 512);
			IF (R.res # 0) OR (buf[0] = 0X) THEN EXIT END;
			ExtractSize (buf, size); 
			IF buf[156] < "2" THEN
				IF entries = NIL THEN NEW(entries); p := entries ELSE NEW(p.next); p := p.next; END;
				ExtractFileName (buf, p.name); p.size := size; p.pos := pos; 
			END;
			pos := pos + 512 + size + ((-size) MOD 512);
		END
	END ReadEntries;
	
	PROCEDURE DisplayEntries(T: Texts.Text; e: Entry);
		VAR W: Texts.Writer; i: LONGINT;
	BEGIN
		Texts.Delete(T, 0, T.len); Texts.OpenWriter(W);
		i := 0;
		WHILE e # NIL DO
			Texts.WriteInt(W, i, 0); Texts.WriteString(W, "  ");
			Texts.WriteString(W, e.name); Texts.WriteString(W, "  "); Texts.WriteInt(W, e.size, 0); Texts.WriteLn(W);
			e := e.next; INC(i)
		END;
		Texts.Append(T , W.buf);
	END DisplayEntries;
	
	PROCEDURE GetFile(e: Entry; F: Files.File);
		VAR dest: Files.File; W, R: Files.Rider; buf: ARRAY 512 OF CHAR; size: LONGINT;
	BEGIN
		Out.String ("Extracting "); Out.String(e.name);
		dest := Files.New(e.name);
		IF dest # NIL THEN
			size := e.size;
			Files.Set(R, F, e.pos+512); Files.Set(W, dest, 0);
			WHILE size # 0 DO
				Files.ReadBytes(R, buf, 512);
				IF size > 512 THEN Files.WriteBytes(W, buf, 512); DEC(size, 512)
				ELSE Files.WriteBytes(W, buf, size); size := 0
				END;
			END;
			Files.Register(dest); Out.String(" "); Out.Int(e.size, 10); Out.Ln
		ELSE
			Out.String("  failed"); Out.Ln
		END
	END GetFile;
	

PROCEDURE DocHandler*(D: Objects.Object; VAR M: Objects.ObjMsg);	(** Handle  D: Document *)
BEGIN
	WITH D: Documents.Document DO
		IF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF (M.id = Objects.get) & (M.name = "DeskMenu") THEN
					M.obj := Desktops.NewMenu(Menu); M.res := 0
				ELSIF (M.id = Objects.get) & (M.name = "SystemMenu") THEN
					M.obj := Desktops.NewMenu(Menu); M.res := 0
				ELSIF (M.id = Objects.get) & (M.name = "UserMenu") THEN
					M.obj := Desktops.NewMenu(Menu); M.res := 0
				ELSE Documents.Handler(D, M)
				END
			END
		ELSE
			Documents.Handler(D,M);
		END;
	END;
END DocHandler;

PROCEDURE Load(D: Documents.Document);
VAR name: ARRAY 64 OF CHAR; F: Frame; T: Texts.Text;
BEGIN
	COPY(D.name, name);
	
	NEW(F);
	ReadEntries (name, F.file, F.entries);
	IF F.entries = NIL THEN D.dsc := NIL (* cannot load *)
	ELSE
		TextDocs.InitDoc(D);
		D.handle := DocHandler;
		
		NEW(T); Texts.Open(T, "");
		TextGadgets.Init(F, T , FALSE);	(* create content *)
		DisplayEntries (F.text, F.entries);
		COPY(name, D.name);
		Documents.Init(D, F)
	END
END Load;

PROCEDURE Store(D: Documents.Document);
BEGIN
END Store;

PROCEDURE NewDoc*;
VAR D: Documents.Document;
BEGIN
	NEW(D);
	D.Load := Load; D.Store := Store; D.handle := DocHandler;
	D.W := 250; D.H := 200;
	Objects.NewObj := D
END NewDoc;

	PROCEDURE Extract*;
		VAR F: Display.Frame; S: Texts.Scanner; e: Entry; i: LONGINT; ch: CHAR; D: Documents.Document;
	BEGIN
		D := Desktops.CurDoc(Gadgets.context);
		F := D.dsc;
		IF (F IS Frame) & (F(Frame).sel) THEN
			WITH F: Frame DO
				Texts.OpenScanner(S, F.text, F.selbeg.org);
				LOOP
					Texts.Scan(S);
					IF S.class # Texts.Int THEN EXIT END;
					i := S.i; e := F.entries; WHILE (e # NIL) & (i > 0) DO e := e.next; DEC(i) END;
					IF e # NIL THEN GetFile(e, F.file) END;
					REPEAT Texts.Read(S, ch) UNTIL (ch = 0DX) OR (Texts.Pos(S) >= F.selend.pos);
					IF Texts.Pos(S) >= F.selend.pos THEN EXIT END
				END
			END
		END
	END Extract;
	
	PROCEDURE ExtractAll*;
		VAR F: Display.Frame; e: Entry; D: Documents.Document;
	BEGIN
		D := Desktops.CurDoc(Gadgets.context);
		F := D.dsc;
		IF F IS Frame THEN
			WITH F: Frame DO
				e := F.entries; WHILE e # NIL DO GetFile(e, F.file); e := e.next END
			END
		END
	END ExtractAll;

END Tar.
