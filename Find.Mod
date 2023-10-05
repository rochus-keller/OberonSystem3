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

MODULE Find;	(** portable *)	(* tk 12.12.95 / pr 12.12.95 *)

(*
	Changes & Updates:
		12.12.95 pr:
			Ported for Native Oberon (directories removed)
*)

(* Searching a pattern in all files of a filepath *)

	IMPORT Objects, Attributes, Gadgets, Oberon, Files, Lists, Texts, FileDir, Strings, Input;

	TYPE
		File = POINTER TO FileDesc;
		FileDesc = RECORD
			name: ARRAY 32 OF CHAR;
			next: File
		END;

	VAR
		pos:INTEGER; spat, pat: ARRAY 64 OF CHAR; PathChar: ARRAY 2 OF CHAR;
		Output, CommandLine: BOOLEAN;
		progress, list: Objects.Object;
		file: File; out: Texts.Text;
		W: Texts.Writer;

	PROCEDURE ScanPar (VAR s: Texts.Scanner);	
		VAR t: Texts.Text; beg, end, time: LONGINT;
	BEGIN
		Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(s);
		IF (s.class = Texts.Char) & (s.c = "^") THEN
			Oberon.GetSelection(t, beg, end, time);
			IF time >= 0 THEN	Texts.OpenScanner(s, t, beg); Texts.Scan(s)	END
		END
	END ScanPar;
	
	PROCEDURE OpenViewer(name: ARRAY OF CHAR; T: Texts.Text);	
	BEGIN
		Oberon.OpenText(name, T, 300, 200)
	END OpenViewer;
	
	PROCEDURE BrowseFile(filename: ARRAY OF CHAR);
		CONST CR = 0DX; TAB = 09X; bufSize = 31744; (*2**15 - 1024*)
		VAR	F: Files.File; R: Files.Rider; n, pos: LONGINT; m, i, j, i0, b, e: INTEGER;
				ch, patj: CHAR; found: BOOLEAN; tab: ARRAY 265 OF SHORTINT; buffer: ARRAY bufSize OF CHAR;
	BEGIN
		Oberon.Collect;
		F:=Files.Old(filename);
		IF F=NIL THEN RETURN END;
		Files.Set(R, F, 0); pos:=0;

		m:=0; WHILE spat[m]#0X DO INC(m) END; 
		FOR i := 0 TO 255 DO tab[i] := SHORT(m) END;
		FOR i := 0 TO m-2 DO tab[ORD(spat[i])] := SHORT(m - i - 1) END;
		patj := spat[m-1]; found := FALSE;
		LOOP
			(*----- read buffer[0..n-1] *)
			n:=Files.Length(F)-pos;
			IF n>bufSize THEN n:=bufSize END;
			IF n<m THEN EXIT END;
			Files.Set(R, F, pos); Files.ReadBytes(R, buffer, n);
			
			(*----- search spat in buffer[0..n-1] *)
			i := m - 1; j := i;			
			WHILE i < n DO
				IF buffer[i] = patj THEN i0 := i;
					REPEAT DEC(i); DEC(j) UNTIL (j < 0) OR (buffer[i] # spat[j]);
						IF j < 0 THEN
						(*------ found: print result *)
						found := TRUE; 
						IF CommandLine OR Output THEN
							b:=i-30; IF b<0 THEN b:=0 END;
							Texts.WriteString(W, filename); Texts.Write(W, 09X);
							Files.Set(R, F, pos + b); e:=b+60;
							REPEAT 
								Files.Read(R, ch); 
								IF ch>" " THEN Texts.Write(W, ch) ELSE Texts.Write(W, " ") END;
								INC(b) 
							UNTIL (b=e) OR (R.eof); Texts.WriteLn(W); Texts.Append(out, W.buf);
						END
					ELSE i := i + tab[ORD(buffer[i])]
					END;
					IF i <= i0 THEN i := i0 + 1 END;
					j := m - 1
				ELSE i := i + tab[ORD(buffer[i])]
				END
			END;
			pos := pos + i - m + 1
		END;
		IF found & (list#NIL) THEN  
			Lists.InsertItem(list(Lists.List), filename); Gadgets.Update(list);
		 END;
	END BrowseFile;

	PROCEDURE *ListFiles(name: ARRAY OF CHAR; time, date, size: LONGINT; VAR continue: BOOLEAN);
		VAR A: Objects.AttrMsg; newpath: ARRAY 128 OF CHAR; 
	BEGIN
		IF progress # NIL THEN
			A.id:=Objects.set; A.name:="Value"; A.class:=Objects.String; 
			COPY(name, A.s); progress.handle(progress, A); Gadgets.Update(progress)
		END;
		BrowseFile(name);
		continue := Input.Available() = 0
	END ListFiles;

	(* commands part *)

	PROCEDURE GetStrAttr(obj: Objects.Object; name: ARRAY OF CHAR; VAR str: ARRAY OF CHAR);
		VAR A: Objects.AttrMsg;
	BEGIN
		A.id := Objects.get;
		A.s := "";
		COPY(name, A.name);
		obj.handle(obj, A);
		COPY(A.s, str)
	END GetStrAttr;

	PROCEDURE Search*;	(* "listname" "progressname" "pattern" "path" *)
		VAR S: Attributes.Scanner; path: ARRAY 128 OF CHAR; A: Objects.AttrMsg;
			search: Objects.Object;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
		IF (S.class = Attributes.Name) OR (S.class = Attributes.String) THEN 
			list := Gadgets.FindObj(Gadgets.context, S.s); Attributes.Scan(S);
			WITH list: Lists.List DO list.beg:=NIL; list.items:=NIL; list.noitems:=0; Gadgets.Update(list) END;
			IF (S.class = Attributes.Name) OR (S.class = Attributes.String) THEN
				progress := Gadgets.FindObj(Gadgets.context, S.s); Attributes.Scan(S);
				IF (S.class = Attributes.Name) OR (S.class = Attributes.String) THEN
					search := Gadgets.FindObj(Gadgets.context, S.s);
					GetStrAttr(search, "Value", spat);
					Attributes.Scan(S);
					COPY(S.s, pat); Attributes.Scan(S);
					CommandLine:=FALSE;
					IF	Output	THEN	NEW(out); Texts.Open(out, ""); OpenViewer(spat, out)	END;
					FileDir.Enumerate(pat, FALSE, ListFiles);
					IF progress#NIL THEN
						A.id:=Objects.set; A.name:="Value"; A.class:=Objects.String; A.s:="done";
						progress.handle(progress, A); Gadgets.Update(progress)
					END;
					WHILE Input.Available() # 0 DO Input.Read(path[0]) END
				END
			END
		END
	END Search;
	
	PROCEDURE SetDetOutput*;
			VAR S: Texts.Scanner; 
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		IF (S.class = Texts.Name) OR (S.class = Texts.String) THEN
			Output := (S.s#"");
		END
	END SetDetOutput;
	
	PROCEDURE Domain*;	(* {filename} ~ *)	
		VAR s: Texts.Scanner; f, last: File;
	BEGIN file := NIL; last := NIL;
		ScanPar(s);
		WHILE s.class = Texts.Name DO
			NEW(f); f.next := NIL;
			IF last = NIL THEN file := f ELSE last.next := f END;
			last := f;
			COPY(s.s, f.name);
			Texts.Scan(s);
			WHILE (s.class = Texts.Char) & (s.c = Oberon.OptionChar) DO Texts.Scan(s); Texts.Scan(s) END
		END
	END Domain;
	
	PROCEDURE All*;	(* ^ *)	
	VAR pat: ARRAY 128 OF CHAR; m: INTEGER; f: File;
	
	PROCEDURE ReadPattern (VAR pat: ARRAY OF CHAR);	
		VAR t: Texts.Text; r: Texts.Reader; m, beg, end, time: LONGINT; ch: CHAR;
	BEGIN
		Oberon.GetSelection(t, beg, end, time);
		IF time > 0 THEN
			Texts.OpenReader(r, t, beg); m := 0;
			WHILE beg < end DO Texts.Read(r, ch);
				IF m < 127 THEN pat[m] := ch END;
				INC(m); INC(beg)
			END;
			pat[m] := 0X
		END;
	END ReadPattern;
	
BEGIN
	ReadPattern(spat); CommandLine:=TRUE;
	NEW(out); Texts.Open(out, ""); 
	OpenViewer(spat, out); f := file;
	WHILE f # NIL DO
		BrowseFile(f.name);
		f := f.next
	END
END All;

BEGIN
	Output:=FALSE; Texts.OpenWriter(W)
END Find.


(*--------------------------------------------------------------------------
Find.Domain ~
	Specify the files in which Find.All should search for a pattern.
Find.All ^
	Searches the selection in the files specified with Find.Domain.
	Lists all lines containing the pattern.
--------------------------------------------------------------------------*)

System.Free Find ~
