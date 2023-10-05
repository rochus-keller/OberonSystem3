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

MODULE DOS;	(** non-portable *)	(* pjm *)

IMPORT Files, Fonts, Texts, Modules, Oberon, FATFiles;

CONST
	BufSize = 32768;

VAR
	wd, wn: Texts.Writer;
	count: LONGINT;
	dir: ARRAY 64 OF CHAR;
	cleanup: Oberon.Task;

PROCEDURE OpenScanner(VAR s: Texts.Scanner);
VAR time, beg, end: LONGINT;  text: Texts.Text;
BEGIN
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);  Texts.Scan(s);
	IF (s.class = Texts.Char) & (s.c = "^") THEN
		Oberon.GetSelection(text, beg, end, time);
		IF time < 0 THEN s.class := Texts.Inval;  s.eot := TRUE
		ELSE Texts.OpenScanner(s, text, beg);  Texts.Scan(s)
		END
	END
END OpenScanner;

PROCEDURE DirHandler(name: ARRAY OF CHAR; time, date, size: LONGINT; attr: SET; VAR continue: BOOLEAN);
VAR i: LONGINT;
BEGIN
	Texts.WriteString(wd, name);
	i := 0;  WHILE name[i] # 0X DO INC(i) END;
	WHILE i < 12 DO Texts.Write(wd, " ");  INC(i) END;
	IF 4 IN attr THEN Texts.WriteString(wd, "     <dir>")
	ELSIF 3 IN attr THEN Texts.WriteString(wd, "     <vol>")
	ELSE Texts.WriteInt(wd, size, 10);  INC(count)
	END;
	Texts.WriteDate(wd, time, date);  Texts.Write(wd, " ");
	IF FATFiles.Hidden IN attr THEN Texts.Write(wd, "H") END;
	IF FATFiles.System IN attr THEN Texts.Write(wd, "S") END;
	IF FATFiles.ReadOnly IN attr THEN Texts.Write(wd, "R") END;
	IF FATFiles.Archive IN attr THEN Texts.Write(wd, "A") END;
	Texts.WriteLn(wd)
END DirHandler;

PROCEDURE Error(VAR w: Texts.Writer;  err: LONGINT);
BEGIN
	IF (err = 8902) OR (err = 8903) OR (err = 8908) THEN Texts.WriteString(w, "file not found")
	ELSIF (err = 8905) OR (err = 8906) THEN Texts.WriteString(w, "disk full")
	ELSIF (err = 8915) OR (err = 8942) THEN Texts.WriteString(w, "read-only file")
	ELSIF (err = 8916) OR (err = 8927) OR (err = 8941) THEN Texts.WriteString(w, "invalid name")
	ELSE Texts.WriteString(w, "error ");  Texts.WriteInt(w, err, 1)
	END
END Error;

PROCEDURE Cleanup;
BEGIN
	IF cleanup # NIL THEN
		Oberon.Remove(cleanup);  cleanup := NIL
	END
END Cleanup;

PROCEDURE CleanupTask(me: Oberon.Task);
BEGIN
	FATFiles.Reset;
	Cleanup
END CleanupTask;

PROCEDURE StartTask;
BEGIN
	IF cleanup = NIL THEN
		NEW(cleanup);  cleanup.time := 0;  cleanup.safe := FALSE;
		cleanup.handle := CleanupTask;  Oberon.Install(cleanup)
	END
END StartTask;

(** DOS.Directory dir ~  Directory of DOS drive. *)

PROCEDURE Directory*;
VAR res, size, i: LONGINT;  t: Texts.Text;  s: Texts.Scanner;
BEGIN
	OpenScanner(s);
	IF s.class IN {Texts.Name, Texts.String} THEN
		i := 0;  WHILE s.s[i] # 0X DO INC(i) END;
		IF (i > 2) & (s.s[1] = ":") THEN
			IF s.s[i-1] = "/" THEN
				s.s[i] := "*";  s.s[i+1] := ".";  s.s[i+2] := "*";  s.s[i+3] := 0X
			END;
			StartTask;
			count := 0;  FATFiles.Enumerate(s.s, DirHandler, res);
			NEW(t);  Texts.Open(t, "");  Texts.Append(t, wd.buf);
			IF res = 0 THEN
				Texts.WriteLn(wn);  Texts.WriteInt(wn, count, 1);  Texts.WriteString(wn, " files");
				FATFiles.GetFreeDiskSpace(s.s[0], size, res);
				IF res = 0 THEN
					Texts.WriteString(wn, ", ");  Texts.WriteInt(wn, size DIV 1024, 1);  
					Texts.WriteString(wn, "K bytes free")
				END;
				Texts.WriteLn(wn);  Texts.Append(t, wn.buf);  Oberon.OpenText(s.s, t, 400, 400)
			ELSE Error(wn, res);  Texts.WriteLn(wn);  Texts.Append(Oberon.Log, wn.buf)
			END
		END
	END
END Directory;

PROCEDURE CopyDosToOberon(from, to: ARRAY OF CHAR);
VAR
	fat: FATFiles.File;  oberon: Files.File;  res: LONGINT;  src: FATFiles.Rider;  dst: Files.Rider;
	buf: ARRAY BufSize OF CHAR;
BEGIN
	fat := FATFiles.Old(from, res);
	IF fat # NIL THEN
		oberon := Files.New(to);
		IF oberon # NIL THEN
			FATFiles.Set(src, fat, 0);  Files.Set(dst, oberon, 0);
			LOOP
				FATFiles.ReadBytes(src, buf, BufSize, res);
				IF res # 0 THEN Texts.Write(wn, " ");  Error(wn, res);  EXIT END;	(* ### *)
				IF src.res = BufSize THEN Files.Register(oberon);  EXIT END;	(* ### *)
				Files.WriteBytes(dst, buf, BufSize-src.res);
				IF dst.res # 0 THEN Texts.WriteString(wn, " write error");  EXIT END	(* ### *)
			END
		ELSE Texts.WriteString(wn, " can not create file")
		END
	ELSE Texts.Write(wn, " ");  Error(wn, res)
	END
END CopyDosToOberon;

PROCEDURE CopyOberonToDos(from, to: ARRAY OF CHAR);
VAR
	fat: FATFiles.File;  oberon: Files.File;  res: LONGINT;  dst: FATFiles.Rider;  src: Files.Rider;
	buf: ARRAY BufSize OF CHAR;
BEGIN
	oberon := Files.Old(from);
	IF oberon # NIL THEN
		fat := FATFiles.New(to, res);
		IF fat # NIL THEN
			FATFiles.Set(dst, fat, 0);  Files.Set(src, oberon, 0);
			LOOP
				Files.ReadBytes(src, buf, BufSize);
				IF src.res = BufSize THEN
					FATFiles.Register(fat, res);
					IF res # 0 THEN Texts.Write(wn, " ");  Error(wn, res) END;
					EXIT	(* ### *)
				END;
				FATFiles.WriteBytes(dst, buf, BufSize-src.res, res);
				IF res # 0 THEN Texts.Write(wn, " ");  Error(wn, res);  EXIT END;	(* ### *)
				IF dst.res # 0 THEN Texts.WriteString(wn, " write error");  res := -1;  EXIT END	(* ### *)
			END;
			IF res # 0 THEN FATFiles.Purge(fat, res) END
		ELSE Texts.Write(wn, " ");  Error(wn, res)
		END
	ELSE Texts.WriteString(wn, " file not found")
	END
END CopyOberonToDos;

PROCEDURE OberonName(s: ARRAY OF CHAR): BOOLEAN;
VAR i: LONGINT;  ch: CHAR;
BEGIN
	i := 0;
	WHILE s[i] # 0X DO
		ch := s[i];
		IF ((CAP(ch) >= "A") & (CAP(ch) <= "Z")) OR ((ch >= "0") & (ch <= "9")) OR (ch = ".") THEN INC(i)
		ELSE RETURN FALSE
		END
	END;
	RETURN (CAP(s[0]) >= "A") & (CAP(s[0]) <= "Z")
END OberonName;

(** DOS.Copy { from => to } ~  Copy files between Oberon and DOS file systems. *)

PROCEDURE Copy*;	(* { from => to } ~ *)
VAR s: Texts.Scanner;  from, to: ARRAY 64 OF CHAR;
BEGIN
	OpenScanner(s);
	WHILE s.class IN {Texts.Name, Texts.String} DO
		COPY(s.s, from);  Texts.Scan(s);
		IF (s.class = Texts.Char) & (s.c = "=") THEN
			Texts.Scan(s);
			IF (s.class = Texts.Char) & (s.c = ">") THEN
				Texts.Scan(s);
				IF (s.class IN {Texts.Name, Texts.String}) THEN
					StartTask;
					COPY(s.s, to);  Texts.Scan(s);
					Texts.WriteString(wn, from);  Texts.WriteString(wn, " => ");  Texts.WriteString(wn, to);
					Texts.Append(Oberon.Log, wn.buf);
					IF OberonName(from) THEN
						IF OberonName(to) THEN Texts.WriteString(wn, " invalid name")
						ELSE CopyOberonToDos(from, to)
						END
					ELSE
						IF OberonName(to) THEN CopyDosToOberon(from, to)
						ELSE Texts.WriteString(wn, " invalid name")
						END
					END;
					Texts.WriteLn(wn);  Texts.Append(Oberon.Log, wn.buf)
				END
			ELSE s.class := Texts.Inval
			END
		ELSE s.class := Texts.Inval
		END
	END
END Copy;

PROCEDURE JoinName(dir, name: ARRAY OF CHAR;  VAR path: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
	i := 0;  WHILE dir[i] # 0X DO path[i] := dir[i];  INC(i) END;
	IF (i # 0) & (dir[i-1] # "/") THEN path[i] := "/";  INC(i) END;
	j := 0;  WHILE name[j] # 0X DO path[i] := name[j];  INC(i);  INC(j) END;
	path[i] := 0X;
END JoinName;

PROCEDURE CopyHandler(name: ARRAY OF CHAR; time, date, size: LONGINT; attr: SET; VAR continue: BOOLEAN);
VAR from: ARRAY 64 OF CHAR;
BEGIN
	IF attr * {FATFiles.VolLabel, FATFiles.SubDir} = {} THEN
		JoinName(dir, name, from);
		Texts.WriteString(wn, from);  Texts.WriteString(wn, " => ");  Texts.WriteString(wn, name);
		Texts.Append(Oberon.Log, wn.buf);
		IF OberonName(name) THEN CopyDosToOberon(from, name)
		ELSE Texts.WriteString(wn, " invalid name")
		END;
		Texts.WriteLn(wn);  Texts.Append(Oberon.Log, wn.buf)
	END
END CopyHandler;

(** DOS.CopyFrom dir { file } ~  Copy files (wildcards allowed) from specified DOS directory. *)

PROCEDURE CopyFrom*;
VAR s: Texts.Scanner;  i, res: LONGINT;  continue: BOOLEAN;
BEGIN
	OpenScanner(s);
	IF s.class IN {Texts.Name, Texts.String} THEN
		StartTask;
		COPY(s.s, dir);  Texts.Scan(s);
		WHILE s.class IN {Texts.Name, Texts.String} DO
			i := 0;  WHILE (s.s[i] # 0X) & (s.s[i] # "?") & (s.s[i] # "*") DO INC(i) END;
			IF s.s[i] = 0X THEN	(* no wildcard *)
				CopyHandler(s.s, 0, 0, 0, {}, continue)
			ELSE
				JoinName(dir, s.s, s.s);
				FATFiles.Enumerate(s.s, CopyHandler, res);
				IF res # 0 THEN
					Texts.WriteString(wn, s.s);  Texts.Write(wn, " ");
					Error(wn, res);  Texts.WriteLn(wn);  Texts.Append(Oberon.Log, wn.buf)
				END
			END;
			Texts.Scan(s)
		END
	END
END CopyFrom;

(** DOS.CopyTo dir { file } ~  Copy files to specified DOS directory. *)

PROCEDURE CopyTo*;
VAR s: Texts.Scanner;  to: ARRAY 64 OF CHAR;
BEGIN
	OpenScanner(s);
	IF s.class IN {Texts.Name, Texts.String} THEN
		StartTask;
		COPY(s.s, dir);  Texts.Scan(s);
		WHILE s.class IN {Texts.Name, Texts.String} DO
			JoinName(dir, s.s, to);
			Texts.WriteString(wn, s.s);  Texts.WriteString(wn, " => ");  Texts.WriteString(wn, to);
			Texts.Append(Oberon.Log, wn.buf);
			CopyOberonToDos(s.s, to);
			Texts.WriteLn(wn);  Texts.Append(Oberon.Log, wn.buf);
			Texts.Scan(s)
		END
	END
END CopyTo;

(** DOS.Delete { file } ~  Delete files on DOS drive. *)

PROCEDURE Delete*;
VAR s: Texts.Scanner;  res: LONGINT;
BEGIN
	OpenScanner(s);
	WHILE s.class IN {Texts.Name, Texts.String} DO
		StartTask;
		Texts.WriteString(wn, s.s);  Texts.Append(Oberon.Log, wn.buf);
		FATFiles.Delete(s.s, res);
		IF res # 0 THEN Texts.Write(wn, " ");  Error(wn, res) END;
		Texts.WriteLn(wn);  Texts.Append(Oberon.Log, wn.buf);
		Texts.Scan(s)
	END
END Delete;

(** DOS.Rename { from => to } ~  Rename files on a DOS file system. *)

PROCEDURE Rename*;	(* { from => to } ~ *)
VAR s: Texts.Scanner;  from, to: ARRAY 64 OF CHAR;  res: LONGINT;
BEGIN
	OpenScanner(s);
	WHILE s.class IN {Texts.Name, Texts.String} DO
		COPY(s.s, from);  Texts.Scan(s);
		IF (s.class = Texts.Char) & (s.c = "=") THEN
			Texts.Scan(s);
			IF (s.class = Texts.Char) & (s.c = ">") THEN
				Texts.Scan(s);
				IF (s.class IN {Texts.Name, Texts.String}) THEN
					StartTask;
					COPY(s.s, to);  Texts.Scan(s);
					Texts.WriteString(wn, from);  Texts.WriteString(wn, " => ");  Texts.WriteString(wn, to);
					Texts.Append(Oberon.Log, wn.buf);
					IF OberonName(from) OR OberonName(to) THEN
						Texts.WriteString(wn, " invalid name")
					ELSE
						FATFiles.Rename(from, to, res);
						IF res # 0 THEN Texts.Write(wn, " ");  Error(wn, res) END
					END;
					Texts.WriteLn(wn);  Texts.Append(Oberon.Log, wn.buf)
				END
			ELSE s.class := Texts.Inval
			END
		ELSE s.class := Texts.Inval
		END
	END
END Rename;

BEGIN
	Texts.OpenWriter(wd);  Texts.SetFont(wd, Fonts.This("Courier10.Scn.Fnt"));
	Texts.OpenWriter(wn);  cleanup := NIL;
	Modules.InstallTermHandler(Cleanup)
END DOS.

DOS.Copy c:/tst.1=>t c:/tst.1=>t t=>t~
DOS.Directory ^ c:/ c:/recycled/ "c:/dos/*.com" a:/ "c:/new*.*" c:/tmp/
DOS.CopyFrom c:/ "*.bak" "*.bat" fat dos config.sys ~

System.Free DOS FATFiles ~
